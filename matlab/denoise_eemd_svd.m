function y = denoise_eemd_svd(x, opts)
%DENOISE_EEMD_SVD EEMD + Hankel-SVD denoising.
%   y = denoise_eemd_svd(x) is the EEMD counterpart of DENOISE_EMD_SVD and
%   the EEMD-Hankel-SVD baseline in Peng et al. (2021): decompose x with
%   EEMD, drop the leading components whose variance contribution rate is
%   below vcr_min (as in EEMD-MSPCA), then truncate each remaining
%   component's Hankel singular values below thr*median (as in EMD-SVD).
arguments
    x (:,1) double
    opts.n_ensemble (1,1) double {mustBePositive, mustBeInteger} = 100
    opts.noise_ratio (1,1) double {mustBeNonnegative} = 0.2
    opts.seed = 0
    opts.vcr_min (1,1) double {mustBeNonnegative} = 0.01
    opts.L (1,1) double {mustBePositive, mustBeInteger} = 20
    opts.thr (1,1) double {mustBeNonnegative} = 0.6
end

c = eemd(x, n_ensemble=opts.n_ensemble, noise_ratio=opts.noise_ratio, seed=opts.seed);
v = var(c, 1, 1);
first = find(v / sum(v) >= opts.vcr_min, 1);
if isempty(first)
    first = size(c, 2);
end
y = svd_denoise_imfs(c(:, first:end), opts.L, opts.thr);
end
