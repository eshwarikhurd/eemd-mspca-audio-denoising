function y = denoise_lowpass(x, opts)
%DENOISE_LOWPASS Butterworth low-pass filter baseline.
%   y = denoise_lowpass(x) applies a 4th-order Butterworth low-pass filter
%   with cutoff wn (fraction of the Nyquist frequency, default 0.5). Peng et
%   al. (2021) use this as their simplest comparison. The filter runs forwards
%   and backwards (zero phase) by default, so it does not shift the waveform.
arguments
    x (:,1) double
    opts.wn (1,1) double {mustBeInRange(opts.wn, 0, 1, 'exclusive')} = 0.5
    opts.order (1,1) double {mustBePositive, mustBeInteger} = 4
    opts.zero_phase (1,1) logical = true
end

[b, a] = butter(opts.order, opts.wn);
if opts.zero_phase
    y = filtfilt(b, a, x);
else
    y = filter(b, a, x);
end
end
