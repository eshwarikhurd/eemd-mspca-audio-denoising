function y = denoise_emd_hurst(x, opts)
%DENOISE_EMD_HURST EMD denoising with Hurst-exponent IMF selection.
%   y = denoise_emd_hurst(x) decomposes x into IMFs and removes every IMF whose
%   Hurst exponent is below threshold (anti-persistent, noise-like components).
arguments
    x (:,1) double
    opts.threshold (1,1) double = 0.5
end

imf = emd(x, 'Display', 0);
y = x;
for i = 1:size(imf, 2)
    if estimate_hurst(imf(:, i)) < opts.threshold
        y = y - imf(:, i);
    end
end
end
