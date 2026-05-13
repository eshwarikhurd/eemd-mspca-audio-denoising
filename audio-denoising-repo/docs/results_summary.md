# Results Summary

## Experimental Setup

| Parameter | Value |
|-----------|-------|
| Audio file | Flute recording (monophonic) |
| Sample rate | 44,100 Hz |
| Duration used | 1 second (44,100 samples) |
| Input SNR (added noise) | 15 dB AWGN |
| SNR metric | Hildebrand-Sekhon (via Welch PSD, Hamming window 1024, 50% overlap) |

---

## SNR Results

| Signal | H-S SNR (dB) |
|--------|-------------|
| Original | — (reference) |
| Noisy (15 dB AWGN) | degraded baseline |
| **EMD + Hankel-SVD** | **+12.53 dB improvement over noisy** |
| Wavelet (`sym8`, `sqtwolog`) | competitive |

*The EMD-SVD method outperformed wavelet and low-pass filter baselines.*

---

## EMD-SVD Pipeline Parameters

| Parameter | Value |
|-----------|-------|
| Hankel window size `L` | 20 |
| Number of iterations | 5 |
| IMFs retained | min(6, total IMFs) |
| SVD threshold | `0.6 × median(singular values)` |
| Final smoother | Moving mean, window = 5 |
| EMD interpolation | PCHIP |

---

## Wavelet Parameters

| Parameter | Value |
|-----------|-------|
| Wavelet | `sym8` |
| Threshold rule | `sqtwolog` (universal) |
| Threshold type | Soft |
| Noise estimation | `mln` (level-dependent) |
| Decomposition level | 3 |

---

## Notes

- The Hildebrand-Sekhon SNR estimator works by iteratively finding a noise floor in the sorted power spectrum where the variance of a subset falls below `mean² / n_avg`. It is well-suited for audio signals with tonal structure.
- The EMD-SVD approach is computationally heavier but provides finer adaptive control via per-IMF singular value thresholding.
- The wavelet method is faster but uses a fixed global threshold, which can over-smooth or under-smooth depending on the signal.
