clc;
clear all;

%% --- Load Audio ---
[filename, pathname] = uigetfile('.', 'Select an audio file');
if isequal(filename, 0)
    disp('No file selected'); return;
end
[y, Fs] = audioread(fullfile(pathname, filename));
x = y(1:min(end, 44100));
x = x / max(abs(x)); x = x(:);

%% --- Add Noise ---
snr_noisy = 15;
signal_power = mean(x.^2);
noise_power = signal_power / (10^(snr_noisy / 10));
noise = sqrt(noise_power) * randn(size(x));
xn = x + noise;

xden = wden(xn,'sqtwolog','s','mln',3,'sym8');

subplot(3,1,1);
plot(x);
title('Original Signal');
subplot(3,1,2);
plot(xn,'r');
title('Noisy Signal');
subplot(3,1,3);
plot(xden,'g');
title('Denoised Signal');

% Match lengths
min_len = min([length(x), length(xn), length(xden)]);
x = x(1:min_len);
noisy_signal = xn(1:min_len);
denoised_final_smoothed = xden(1:min_len);

% Frequency Spectrum
X = abs(fft(x, min_len));
Y = abs(fft(xn, min_len));
Z = abs(fft(xden, min_len));
f = (0:min_len/2-1) * (Fs/min_len);

figure;
subplot(3,1,1);
plot(f, X(1:min_len/2));
title('Original Signal Spectrum'); xlabel('Frequency (Hz)'); ylabel('Magnitude'); xlim([0 1000]);

subplot(3,1,2);
plot(f, Y(1:min_len/2), 'r');
title('Noisy Signal Spectrum'); xlabel('Frequency (Hz)'); ylabel('Magnitude'); xlim([0 1000]);

subplot(3,1,3);
plot(f, Z(1:min_len/2), 'g');
title('Denoised Signal Spectrum'); xlabel('Frequency (Hz)'); ylabel('Magnitude'); xlim([0 1000]);

% Playback
disp('Playing original audio...'); sound(x, Fs); pause(length(x) / Fs + 1);
disp('Playing noisy audio...'); sound(noisy_signal, Fs); pause(length(noisy_signal) / Fs + 1);
disp('Playing denoised audio...'); sound(denoised_final_smoothed, Fs); pause(length(denoised_final_smoothed) / Fs + 1);

%% --- Final Metrics ---
fprintf('\n=== Final Metrics ===\n');
print_all_metrics('Original Signal', x, x, Fs);
print_all_metrics('Noisy Signal', xn, x, Fs);
print_all_metrics('Denoised Signal (Best)', xden, x, Fs);

disp('Audio playback completed.');

%% --- Print All Metrics ---
function print_all_metrics(name, signal, reference, Fs)
    

    [pxx, ~] = pwelch(signal, hamming(1024), 512, 1024, Fs);
    [~, ~, hs_snr] = hildebrand_sekhon(pxx, 1);

    fprintf('\n=== %s ===\n', name);
    fprintf('Hildebrand-Sekhon SNR: %.4f dB\n', hs_snr);
    
end
%% --- Hildebrand-Sekhon SNR ---
function [noise_power, signal_power, snr_db] = hildebrand_sekhon(power_spectrum, n_avg)
    power_spectrum = sort(power_spectrum);
    N = length(power_spectrum);

    for i = N:-1:2
        subset = power_spectrum(1:i);
        mean_val = mean(subset);
        variance = var(subset);

        if variance <= (mean_val^2 / n_avg)
            noise_power = mean_val;
            break;
        end
    end

    if ~exist('noise_power', 'var')
        noise_power = mean(power_spectrum);
    end

    total_power = mean(power_spectrum);
    signal_power = max(total_power - noise_power, eps);
    snr_db = 10 * log10(signal_power / noise_power);
end