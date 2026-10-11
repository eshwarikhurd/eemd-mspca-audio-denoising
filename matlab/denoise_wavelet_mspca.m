function y = denoise_wavelet_mspca(x, opts)
%DENOISE_WAVELET_MSPCA Wavelet multiscale PCA denoising (Bakshi, 1998).
%   y = denoise_wavelet_mspca(x) embeds x in an L-column Hankel matrix (its
%   lagged copies act as the variables), runs MATLAB's wmspca (wavelet
%   decomposition, PCA at every scale keeping components by the Kaiser rule,
%   then a final PCA) and averages the anti-diagonals back into a signal.
%   This is the wavelet-MSPCA baseline in Peng et al. (2021).
arguments
    x (:,1) double
    opts.L (1,1) double {mustBePositive, mustBeInteger} = 10
    opts.level (1,1) double {mustBePositive, mustBeInteger} = 5
    opts.wavelet (1,:) char = 'sym4'
    opts.npc = 'kais'
end

X = hankel_matrix(x, opts.L).';   % (N-L+1)-by-L
Xs = wmspca(X, opts.level, opts.wavelet, opts.npc);
y = diagonal_averaging(Xs.');
end
