clc; 
clear; 
close all;

% Load audio
[filename, pathname] = uigetfile('.', 'Select an audio file');
if isequal(filename, 0)
    disp('No file selected');
    return;
end
[y, Fs] = audioread(fullfile(pathname, filename));

% FIX: guard against audio shorter than 1 second
x = y(1:min(length(y), 44100));
x = x / max(abs(x)); % Normalize signal

% Define SNR values
snr_noisy = 15; % Noisy signal SNR in dB

% Generate noise
signal_power = mean(x.^2);
noise_power = signal_power / (10^(snr_noisy / 10)); 
noise = sqrt(noise_power) * randn(size(x));
noisy_signal = x + noise;

% Initialize denoising
L = 20; % Hankel matrix window size
num_iterations = 5;
denoised_signal = noisy_signal;

for n = 1:num_iterations
    [IMF, ~, ~] = emd(denoised_signal, 'Interpolation', 'pchip', 'Display', 0);

    % IMF selection: discard last (noisier) IMFs
    IMF = IMF(:, 1:min(6, size(IMF, 2))); 

    denoised_signal = svd_denoising(IMF, L);

    % Safe SNR evaluation
    min_len_iter = min(length(denoised_signal), length(x));
    signal_snr = denoised_signal(1:min_len_iter);
    reference_snr = x(1:min_len_iter);
end

% Smooth final output
denoised_final_smoothed = movmean(denoised_signal, 5);

% Match lengths
min_len = min([length(x), length(noisy_signal), length(denoised_final_smoothed)]);

% FIX: force even length for clean FFT frequency axis
min_len = min_len - mod(min_len, 2);

x = x(1:min_len);
noisy_signal = noisy_signal(1:min_len);
denoised_final_smoothed = denoised_final_smoothed(1:min_len);

% Frequency Spectrum
X = abs(fft(x, min_len));
Y = abs(fft(noisy_signal, min_len));
Z = abs(fft(denoised_final_smoothed, min_len));
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

% FIX: capture and print SNR values
fprintf('\n=== SNR Results ===\n');
snr_orig    = compute_snr(x, x);
snr_noisy_  = compute_snr(noisy_signal, x);
snr_den     = compute_snr(denoised_final_smoothed, x);
fprintf('Original Signal SNR     : %.4f dB\n', snr_orig);
fprintf('Noisy Signal SNR        : %.4f dB\n', snr_noisy_);
fprintf('Denoised Signal SNR     : %.4f dB\n', snr_den);
fprintf('SNR Improvement         : %.4f dB\n', snr_den - snr_noisy_);

%% --- Final Metrics ---
fprintf('\n=== Hildebrand-Sekhon Metrics ===\n');
print_all_metrics('Original Signal', x, x, Fs);
print_all_metrics('Noisy Signal', noisy_signal, x, Fs);
print_all_metrics('Denoised Signal (Best)', denoised_final_smoothed, x, Fs);

disp('Audio playback completed.');

% ------------------------------------------------------------------
% SVD Denoising Function
function denoised_signal = svd_denoising(IMF, L)
    [N, num_IMFs] = size(IMF);
    denoised_signal = zeros(N, 1);

    for i = 1:num_IMFs
        H = hankel_matrix(IMF(:, i), L);
        [U, S, V] = svd(H, 'econ');

        % Adaptive thresholding
        singular_vals = diag(S);
        threshold = median(singular_vals) * 0.6;
        S(S < threshold) = 0;

        % FIX: was V, must be V' for correct SVD reconstruction
        H_denoised = U * S * V';
        recovered_signal = diagonal_averaging(H_denoised);

        recovered_signal = recovered_signal(:);
        recovered_signal = recovered_signal(1:min(N, length(recovered_signal)));
        denoised_signal(1:length(recovered_signal)) = denoised_signal(1:length(recovered_signal)) + recovered_signal;
    end
end

% ------------------------------------------------------------------
% Hankel Matrix Function
function H = hankel_matrix(data, L)
    N = length(data);
    K = N - L + 1;
    H = zeros(L, K);
    for i = 1:L
        H(i, :) = data(i:K + i - 1);
    end
end

% ------------------------------------------------------------------
% Diagonal Averaging
function x = diagonal_averaging(H)
    [L, K] = size(H);
    N = L + K - 1;
    x = zeros(1, N);
    count = zeros(1, N);

    for i = 1:L
        for j = 1:K
            x(i + j - 1) = x(i + j - 1) + H(i, j);
            count(i + j - 1) = count(i + j - 1) + 1;
        end
    end

    x = x ./ count;
    x = x(:);
end

% ------------------------------------------------------------------
% SNR Computation — FIX: removed unused label arg, now returns value
function SNR_dB = compute_snr(signal, reference)
    signal = signal(:); reference = reference(:);
    min_len = min(length(signal), length(reference));
    signal = signal(1:min_len);
    reference = reference(1:min_len);

    signal_power = mean(reference.^2);
    noise_power = mean((reference - signal).^2);
    SNR_dB = 10 * log10(signal_power / noise_power);
end

% ------------------------------------------------------------------
% Hildebrand-Sekhon SNR Estimator
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

% ------------------------------------------------------------------
% Print All Metrics
function print_all_metrics(name, signal, ~, Fs)
    [pxx, ~] = pwelch(signal, hamming(1024), 512, 1024, Fs);
    [~, ~, hs_snr] = hildebrand_sekhon(pxx, 1);
    fprintf('\n=== %s ===\n', name);
    fprintf('Hildebrand-Sekhon SNR: %.4f dB\n', hs_snr);
end