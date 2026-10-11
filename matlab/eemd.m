function c = eemd(x, opts)
%EEMD Ensemble empirical mode decomposition (Wu & Huang, 2009).
%   c = eemd(x) returns an N-by-(n_imfs+1) matrix: the ensemble-averaged IMFs
%   followed by the averaged residual, so that sum(c, 2) ~ x.
%
%   Each of the n_ensemble trials decomposes x plus white Gaussian noise with
%   standard deviation noise_ratio*std(x). n_imfs is fixed (default
%   floor(log2(N)) - 1) so the trials line up; trials with fewer IMFs are
%   zero-padded.
arguments
    x (:,1) double
    opts.n_ensemble (1,1) double {mustBePositive, mustBeInteger} = 100
    opts.noise_ratio (1,1) double {mustBeNonnegative} = 0.2
    opts.n_imfs (1,1) double {mustBeNonnegative, mustBeInteger} = 0  % 0 = default
    opts.seed = []
end

N = numel(x);
K = opts.n_imfs;
if K == 0
    K = floor(log2(N)) - 1;
end
if ~isempty(opts.seed)
    stream = RandStream('mt19937ar', 'Seed', opts.seed);
else
    stream = RandStream.getGlobalStream;
end

sigma = opts.noise_ratio * std(x);
c = zeros(N, K + 1);
for j = 1:opts.n_ensemble
    xj = x + sigma * randn(stream, N, 1);
    [imf, res] = emd(xj, 'MaxNumIMF', K, 'Display', 0);
    n = size(imf, 2);
    c(:, 1:n) = c(:, 1:n) + imf;
    c(:, end) = c(:, end) + res;
end
c = c / opts.n_ensemble;
end
