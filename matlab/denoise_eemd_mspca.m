function [y, info] = denoise_eemd_mspca(x, opts)
%DENOISE_EEMD_MSPCA EEMD and multiscale PCA denoising (Peng, Guo & Shang, 2021).
%   y = denoise_eemd_mspca(x) follows Peng et al., Sensors 21(16):5271:
%     1. EEMD: x -> IMFs c_1..c_n and residual c_n+1.
%     2. Drop the leading high-frequency IMFs whose variance contribution
%        rate (VCR) is below vcr_min.
%     3. For each remaining component, PCA on its Hankel matrix (L rows):
%        keep the principal components up to `energy` of the cumulative
%        eigenvalue sum and rebuild the component (diagonal averaging by
%        default; the paper's first-row/last-column readout via `readout`).
%     4. Soft-threshold the component with T = sigma*sqrt(2*log(N)).
%     5. Sum the denoised components.
%
%   [y, info] = denoise_eemd_mspca(...) also returns the intermediate steps
%   (used by plot_eemd_mspca): components, vcr, first kept component, the
%   eigenvalues and number kept per component, thresholds, and each
%   component after PCA and after thresholding.
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
    opts.t_scale (1,1) double {mustBeNonnegative} = 1   % multiplies the soft threshold (0 = no threshold)
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

n = size(c, 2);
info = struct('components', c, 'vcr', vcr, 'first', first, 'vcr_min', opts.vcr_min, ...
    'energy', opts.energy, 'lambda', nan(opts.L, n), 'k', zeros(1, n), 'T', zeros(1, n), ...
    'after_pca', zeros(N, n), 'denoised', zeros(N, n));
y = zeros(N, 1);
for i = first:n
    [ci, info.lambda(:, i), info.k(i)] = hankel_pca(c(:, i), opts.L, opts.energy, opts.readout);
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
    info.T(i) = opts.t_scale * s * sqrt(2 * log(N));
    info.after_pca(:, i) = ci;
    info.denoised(:, i) = soft_threshold(ci, info.T(i));
    y = y + info.denoised(:, i);
end
end

function [ci, lambda, k] = hankel_pca(c, L, energy, readout)
% PCA of the L-row Hankel matrix of c, keeping components up to `energy`
% of the cumulative eigenvalue sum of H'*H (eigenvalues = singular values^2).
H = hankel_matrix(c, L);
[U, S, V] = svd(H, 'econ');
lambda = diag(S).^2;
k = find(cumsum(lambda) / sum(lambda) >= energy, 1);
if isempty(k)  % all-zero component (EEMD pads unused IMF slots with zeros)
    k = 0;
end
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
