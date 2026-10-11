function snr_db = hs_snr(x, fs)
%HS_SNR Blind SNR estimate (dB) of x using the Hildebrand-Sekhon method
%   on its Welch PSD (Hamming 1024, 50% overlap). Needs no clean reference.
pxx = pwelch(x(:), hamming(1024), 512, 1024, fs);
[~, ~, snr_db] = hildebrand_sekhon(pxx, 1);
end

function [noise_power, signal_power, snr_db] = hildebrand_sekhon(p, n_avg)
p = sort(p);
noise_power = mean(p);
for i = numel(p):-1:2
    subset = p(1:i);
    if var(subset) <= mean(subset)^2 / n_avg
        noise_power = mean(subset);
        break;
    end
end
signal_power = max(mean(p) - noise_power, eps);
snr_db = 10 * log10(signal_power / noise_power);
end
