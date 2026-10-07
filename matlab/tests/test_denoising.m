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
for m = {'emd_svd', 'wavelet', 'emd_hurst'}
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

function test_unknown_method(tc)
verifyError(tc, @() denoise(1:10, 'nope'), 'denoise:unknownMethod');
end
