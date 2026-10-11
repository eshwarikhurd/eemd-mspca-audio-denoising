function y = denoise_wavelet(x, opts)
%DENOISE_WAVELET Wavelet soft-threshold denoising with wden.
%   y = denoise_wavelet(x) uses sym8, level 3, universal threshold
%   ('sqtwolog'), soft thresholding and level-dependent noise estimate ('mln').
arguments
    x (:,1) double
    opts.wavelet (1,:) char = 'sym8'
    opts.level (1,1) double {mustBePositive, mustBeInteger} = 3
    opts.rule (1,:) char = 'sqtwolog'
    opts.sorh (1,:) char = 's'
    opts.scal (1,:) char = 'mln'
end

y = wden(x, opts.rule, opts.sorh, opts.scal, opts.level, opts.wavelet);
y = y(:);
end
