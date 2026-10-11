%RUN_DEMO Interactive demo: denoise one audio clip with every method.
%   Pick an audio file (defaults to audio/Flute_audio.mp3), add white noise
%   at 15 dB, compare the four methods by SNR and Hildebrand-Sekhon SNR, plot the
%   spectra and optionally play the results.

repo = fileparts(fileparts(mfilename('fullpath')));
[file, folder] = uigetfile({'*.wav;*.mp3;*.flac', 'Audio files'}, ...
    'Select an audio file', fullfile(repo, 'audio', 'Flute_audio.mp3'));
if isequal(file, 0)
    disp('No file selected'); return;
end
[x, fs] = audioread(fullfile(folder, file));
x = mean(x, 2);
x = x(1:min(end, fs));          % first second, as in the paper
x = x / max(abs(x));

input_snr = 15;
rng(0);
noisy = add_white_noise(x, input_snr);

methods = {'emd_svd', 'wavelet', 'emd_hurst', 'eemd_mspca'};
signals = {x, noisy};
names = {'clean', 'noisy'};
for m = 1:numel(methods)
    t = tic;
    signals{end + 1} = denoise(noisy, methods{m}); %#ok<SAGROW>
    names{end + 1} = methods{m}; %#ok<SAGROW>
    fprintf('%-10s done in %.1f s\n', methods{m}, toc(t));
end

fprintf('\n%-10s %10s %10s\n', 'signal', 'SNR (dB)', 'HS-SNR');
for k = 1:numel(signals)
    fprintf('%-10s %10.2f %10.2f\n', names{k}, snr_db(signals{k}, x), hs_snr(signals{k}, fs));
end

figure('Name', 'Spectra');
hold on;
for k = 1:numel(signals)
    [pxx, f] = pwelch(signals{k}, hamming(1024), 512, 1024, fs);
    plot(f, 10 * log10(pxx), 'DisplayName', names{k});
end
hold off;
set(gca, 'XScale', 'log');
xlim([50 fs / 2]);
xlabel('Frequency (Hz)'); ylabel('PSD (dB/Hz)');
legend('Location', 'southwest'); grid on;
title(sprintf('Welch PSD, white noise at %d dB', input_snr));

if strcmp(questdlg('Play the clips?', 'Playback', 'Yes', 'No', 'No'), 'Yes')
    for k = 1:numel(signals)
        fprintf('Playing %s...\n', names{k});
        sound(signals{k}, fs);
        pause(numel(signals{k}) / fs + 0.5);
    end
end
