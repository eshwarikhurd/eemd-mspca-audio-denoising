function y = add_white_noise(x, snr_db)
%ADD_WHITE_NOISE Add white Gaussian noise to x at the given SNR (dB).
noise_power = mean(x.^2) / 10^(snr_db / 10);
y = x + sqrt(noise_power) * randn(size(x));
end
