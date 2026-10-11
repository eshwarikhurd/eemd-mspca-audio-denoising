function y = denoise_emd_svd(x, opts)
%DENOISE_EMD_SVD Iterative EMD + Hankel-SVD denoising (main method of the paper).
%   y = denoise_emd_svd(x) denoises the signal x with the default settings.
%   y = denoise_emd_svd(x, L=20, n_iter=5, n_imfs=6, thr=0.6, smooth=5)
%
%   Each iteration decomposes the signal into IMFs (EMD, pchip), keeps the
%   first n_imfs, denoises every IMF by truncating the singular values of its
%   Hankel matrix below thr*median(sigma), and sums the IMFs back together.
%   The result is smoothed with a moving mean of length smooth.
arguments
    x (:,1) double
    opts.L (1,1) double {mustBePositive, mustBeInteger} = 20
    opts.n_iter (1,1) double {mustBePositive, mustBeInteger} = 5
    opts.n_imfs (1,1) double {mustBePositive, mustBeInteger} = 6
    opts.thr (1,1) double {mustBeNonnegative} = 0.6
    opts.smooth (1,1) double {mustBePositive, mustBeInteger} = 5
end

y = x;
for n = 1:opts.n_iter
    imf = emd(y, 'Interpolation', 'pchip', 'Display', 0);
    imf = imf(:, 1:min(opts.n_imfs, size(imf, 2)));
    y = svd_denoise_imfs(imf, opts.L, opts.thr);
end
y = movmean(y, opts.smooth);
end
