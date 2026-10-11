function tests = test_denoising
%TEST_DENOISING Unit tests for the denoising functions.
%   Run with: runtests('matlab/tests')
tests = functiontests(localfunctions);
end

function setupOnce(tc)
here = fileparts(mfilename('fullpath'));
addpath(fileparts(here));
[x, fs] = audioread(fullfile(here, '..', '..', 'audio', 'Flute_audio.mp3'));
x = mean(x, 2);
x = x(1:fs);
tc.TestData.x = x / max(abs(x));
tc.TestData.fs = fs;
rng(0);
tc.TestData.noisy = add_white_noise(tc.TestData.x, 15);
end

function test_hankel_round_trip(tc)
x = randn(200, 1);
verifyEqual(tc, diagonal_averaging(hankel_matrix(x, 20)), x, 'AbsTol', 1e-12);
end

function test_diagonal_averaging_matches_loop(tc)
H = randn(7, 30);
[L, K] = size(H);
ref = zeros(L + K - 1, 1);
cnt = zeros(L + K - 1, 1);
for i = 1:L
    for j = 1:K
        ref(i + j - 1) = ref(i + j - 1) + H(i, j);
        cnt(i + j - 1) = cnt(i + j - 1) + 1;
    end
end
verifyEqual(tc, diagonal_averaging(H), ref ./ cnt, 'AbsTol', 1e-12);
end

function test_hurst_white_noise(tc)
rng(1);
h = estimate_hurst(randn(8192, 1));
verifyGreaterThan(tc, h, 0.4);
verifyLessThan(tc, h, 0.7);
end

function test_hurst_random_walk(tc)
rng(1);
verifyGreaterThan(tc, estimate_hurst(cumsum(randn(8192, 1))), 0.8);
end

function test_add_white_noise_snr(tc)
verifyEqual(tc, snr_db(tc.TestData.noisy, tc.TestData.x), 15, 'AbsTol', 0.3);
end

function test_methods_keep_length(tc)
for m = {'emd_svd', 'wavelet', 'emd_hurst', 'eemd_mspca', 'lowpass', 'wavelet_mspca', 'eemd_svd'}
    y = denoise(tc.TestData.noisy, m{1});
    verifySize(tc, y, size(tc.TestData.noisy), m{1});
    verifyTrue(tc, all(isfinite(y)), m{1});
end
end

function test_emd_svd_improves_hs_snr(tc)
% The paper reports the gain in blind Hildebrand-Sekhon SNR. (True SNR against
% the clean flute drops at 15 dB input, in the original code too.)
y = denoise_emd_svd(tc.TestData.noisy);
fs = tc.TestData.fs;
verifyGreaterThan(tc, hs_snr(y, fs), hs_snr(tc.TestData.noisy, fs) + 10);
end

function test_wavelet_improves_snr(tc)
y = denoise_wavelet(tc.TestData.noisy);
verifyGreaterThan(tc, snr_db(y, tc.TestData.x), snr_db(tc.TestData.noisy, tc.TestData.x));
end

function test_eemd_without_noise_is_emd(tc)
% With no added noise every ensemble member is the same EMD, so the
% components must add back up to the signal exactly.
x = tc.TestData.noisy(1:4096);
c = eemd(x, n_ensemble=2, noise_ratio=0);
verifyEqual(tc, sum(c, 2), x, 'AbsTol', 1e-10);
end

function test_eemd_reconstruction(tc)
% Averaged added noise shrinks with the ensemble size: ~ 0.2*std(x)/sqrt(M).
x = tc.TestData.noisy(1:4096);
c = eemd(x, n_ensemble=50, seed=1);
verifyLessThan(tc, rms(sum(c, 2) - x), 2 * 0.2 * std(x) / sqrt(50));
end

function test_eemd_seed_is_reproducible(tc)
x = tc.TestData.noisy(1:4096);
verifyEqual(tc, eemd(x, n_ensemble=5, seed=3), eemd(x, n_ensemble=5, seed=3));
end

function test_eemd_mspca_blocks(tc)
% Peng et al. (2021), Table 1: Blocks, N = 1024, noise 0.2*randn,
% 6.99 -> 12.55 dB. Our defaults reach about 12 dB.
x = wnoise(1, 10).';
x = x / rms(x) * 0.2 * 10^(6.99 / 20);
rng(1);
xn = x + 0.2 * randn(1024, 1);
verifyGreaterThan(tc, snr_db(denoise_eemd_mspca(xn, seed=1), x), snr_db(xn, x) + 4);
end

function test_lowpass_removes_high_frequencies(tc)
fs = 8000;
t = (0:fs - 1).' / fs;
x = sin(2 * pi * 200 * t) + sin(2 * pi * 3500 * t);
y = denoise_lowpass(x, wn=0.25);   % cutoff 1 kHz
mid = 100:numel(t) - 100;          % skip the filter's edge transients
verifyEqual(tc, y(mid), sin(2 * pi * 200 * t(mid)), 'AbsTol', 0.05);
end

function test_wavelet_mspca_blocks(tc)
% Peng et al. (2021), Table 1, wavelet-MSPCA column: Blocks 6.99 -> 11.83 dB.
x = wnoise(1, 10).';
x = x / rms(x) * 0.2 * 10^(6.99 / 20);
rng(1);
xn = x + 0.2 * randn(1024, 1);
verifyGreaterThan(tc, snr_db(denoise_wavelet_mspca(xn), x), snr_db(xn, x) + 4);
end

function test_unknown_method(tc)
verifyError(tc, @() denoise(1:10, 'nope'), 'denoise:unknownMethod');
end
