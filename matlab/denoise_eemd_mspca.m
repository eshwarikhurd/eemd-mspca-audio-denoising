function y = denoise_eemd_mspca(x, opts)
%DENOISE_EEMD_MSPCA EEMD and multiscale PCA denoising (Peng, Guo & Shang, 2021).
%   y = denoise_eemd_mspca(x) follows Peng et al., Sensors 21(16):5271:
%     1. EEMD: x -> IMFs c_1..c_n and residual c_n+1.
%     2. Drop the leading high-frequency IMFs whose variance contribution
%        rate (VCR) is below vcr_min.
%     3. For each remaining component, PCA on its Hankel matrix (L rows):
%        keep the principal components up to `energy` of the cumulative
%        eigenvalue sum and rebuild the component from the first row and
%        last column of the reconstructed matrix.
%     4. Soft-threshold the component with T = sigma*sqrt(2*log(N)).
%     5. Sum the denoised components.
%
%   EEMD options (n_ensemble, noise_ratio, seed) are passed to EEMD.
arguments
    x (:,1) double
    opts.n_ensemble (1,1) double {mustBePositive, mustBeInteger} = 100
    opts.noise_ratio (1,1) double {mustBeNonnegative} = 0.2
    opts.seed = 0
    opts.vcr_min (1,1) double {mustBeNonnegative} = 0.01
    opts.L (1,1) double {mustBePositive, mustBeInteger} = 10
    opts.energy (1,1) double {mustBeInRange(opts.energy, 0, 1)} = 0.85
    opts.sigma (1,:) char {mustBeMember(opts.sigma, {'std', 'var', 'mad', 'removed', 'none'})} = 'removed'
    opts.readout (1,:) char {mustBeMember(opts.readout, {'first_row_last_col', 'diagonal'})} = 'diagonal'
end

N = numel(x);
c = eemd(x, n_ensemble=opts.n_ensemble, noise_ratio=opts.noise_ratio, seed=opts.seed);

% Step 2: skip the leading IMFs with a small variance contribution rate.
v = var(c, 1, 1);
vcr = v / sum(v);
first = find(vcr >= opts.vcr_min, 1);
if isempty(first)
    first = size(c, 2);
end

y = zeros(N, 1);
for i = first:size(c, 2)
    ci = hankel_pca(c(:, i), opts.L, opts.energy, opts.readout);
    switch opts.sigma
        case 'std'      % std of the component
            s = std(ci, 1);
        case 'var'      % paper wording: "sigma denotes data variance"
            s = var(ci, 1);
        case 'mad'      % robust noise estimate (Donoho & Johnstone)
            s = median(abs(ci - median(ci))) / 0.6745;
        case 'removed'  % noise level of what the PCA step removed
            r = c(:, i) - ci;
            s = median(abs(r - median(r))) / 0.6745;
        case 'none'
            s = 0;
    end
    y = y + soft_threshold(ci, s * sqrt(2 * log(N)));
end
end

function ci = hankel_pca(c, L, energy, readout)
% PCA of the L-row Hankel matrix of c, keeping components up to `energy`
% of the cumulative eigenvalue sum of H'*H (eigenvalues = singular values^2).
H = hankel_matrix(c, L);
[U, S, V] = svd(H, 'econ');
lambda = diag(S).^2;
k = find(cumsum(lambda) / sum(lambda) >= energy, 1);
Hr = U(:, 1:k) * S(1:k, 1:k) * V(:, 1:k)';
switch readout
    case 'first_row_last_col'
        ci = [Hr(1, :), Hr(2:end, end)'].';
    case 'diagonal'
        ci = diagonal_averaging(Hr);
end
end

function y = soft_threshold(x, T)
y = sign(x) .* max(abs(x) - T, 0);
end
