# Audio Signal Denoising — EMD-SVD & Wavelet Methods

[![Paper](https://img.shields.io/badge/Paper-SpringerLink-blue)](https://link.springer.com/chapter/10.1007/978-981-96-7499-2_27)
[![Conference](https://img.shields.io/badge/Conference-SmartCom%202025-orange)](https://link.springer.com/conference/smartcom)
[![MATLAB](https://img.shields.io/badge/Language-MATLAB-red)](https://www.mathworks.com/)

MATLAB implementation of audio signal denoising techniques presented in:

> **Khurd, E., Kamthankar, S., Kelkar, A., & Yerram, R. B.** (2026). *Denoising Techniques of Audio Signals — A Review.* In: *Smart Trends in Computing and Communications* (SmartCom 2025). Lecture Notes in Networks and Systems, vol 1458. Springer, Singapore.  
> DOI: [10.1007/978-981-96-7499-2_27](https://doi.org/10.1007/978-981-96-7499-2_27)

---

## Overview

This repository provides implementations of three audio denoising pipelines evaluated on a flute audio sample at **15 dB input SNR**. Performance is measured using the **Hildebrand-Sekhon SNR estimator** applied to the Welch power spectral density.

| Method | Key Technique | Highlight |
|--------|--------------|-----------|
| **EMD + SVD** | Empirical Mode Decomposition → Hankel-SVD | Iterative, adaptive thresholding |
| **Wavelet** | `wden` soft-thresholding (`sym8`, level 3) | Fast, single-pass |
| **EMD (Hurst-based)** | EMD → Hurst exponent IMF selection | Eliminates fractal noise IMFs |

---

## Repository Structure

```
audio-denoising/
├── src/
│   ├── emd_svd_denoising.m      # Main pipeline: EMD + Hankel-SVD (iterative)
│   ├── wavelet_denoising.m      # Wavelet denoising using wden (sym8)
│   └── emd_denoising.m          # EMD + Hurst exponent IMF selection
├── audio/
│   └── Flute_audio.mp3          # Test audio: 1-second flute sample @ 44100 Hz
├── docs/
│   └── results_summary.md       # SNR results and method comparison
├── .gitignore
└── README.md
```

---

## Methods

### 1. EMD + Hankel-SVD (`emd_svd_denoising.m`)
The primary method from the paper. Applies iterative denoising over 5 passes:
1. Decompose the signal into Intrinsic Mode Functions (IMFs) via EMD with PCHIP interpolation.
2. Retain the first 6 IMFs (least noisy).
3. For each IMF, build a Hankel matrix and perform SVD.
4. Apply adaptive thresholding: zero out singular values below `0.6 × median(σ)`.
5. Reconstruct via diagonal averaging.
6. Apply a final moving-mean smoother (window = 5).

**Metrics reported:** Hildebrand-Sekhon SNR (via Welch PSD).

### 2. Wavelet Denoising (`wavelet_denoising.m`)
Single-pass denoising using MATLAB's `wden`:
- Wavelet: `sym8`
- Thresholding rule: `sqtwolog` (universal threshold), soft
- Decomposition level: 3
- Noise estimation: `mln` (level-dependent)

### 3. EMD + Hurst Exponent (`emd_denoising.m`)
- Decomposes signal into IMFs.
- Estimates the Hurst exponent `H` for each IMF.
- Subtracts IMFs with `H < 0.5` (anti-persistent, noise-dominated components).

---

## Requirements

- **MATLAB R2019b or later**
- Signal Processing Toolbox (for `pwelch`, `wden`, `hamming`)
- Wavelet Toolbox (for `wden`)
- **Signal Processing Toolbox** built-in `emd` function (R2018a+)

---

## Usage

### EMD + SVD Pipeline (main method)
```matlab
% Run from MATLAB — a file picker dialog will appear
run('src/emd_svd_denoising.m')
```
Select `audio/Flute_audio.mp3` when prompted. The script will:
- Add AWGN at 15 dB SNR
- Run 5 iterations of EMD-SVD denoising
- Plot frequency spectra (original / noisy / denoised)
- Play back all three audio versions
- Print Hildebrand-Sekhon SNR for each

### Wavelet Pipeline
```matlab
run('src/wavelet_denoising.m')
```

### EMD + Hurst Exponent
```matlab
[y, Fs] = audioread('audio/Flute_audio.mp3');
emd_denoising(y(1:44100));
```

---

## Results

Evaluated on a 1-second flute recording (44100 Hz, normalized). Noise added at **15 dB SNR**.

| Signal | Hildebrand-Sekhon SNR |
|--------|----------------------|
| Original | baseline |
| Noisy (15 dB AWGN) | degraded |
| EMD + SVD denoised | **+12.53 dB improvement** |
| Wavelet denoised | competitive baseline |

*See [`docs/results_summary.md`](docs/results_summary.md) for detailed metrics.*

---

## Citation

If you use this code in your research, please cite:

```bibtex
@inproceedings{khurd2026denoising,
  title     = {Denoising Techniques of Audio Signals---A Review},
  author    = {Khurd, Eshwari and Kamthankar, Shravani and Kelkar, Avani and Yerram, Ravinder B.},
  booktitle = {Smart Trends in Computing and Communications},
  series    = {Lecture Notes in Networks and Systems},
  volume    = {1458},
  pages     = {317--326},
  year      = {2026},
  publisher = {Springer, Singapore},
  doi       = {10.1007/978-981-96-7499-2_27}
}
```

---

## Authors

- **Eshwari Khurd** — UC Irvine (MS EECS) · [GitHub](https://github.com/eshwarikhurd) · [LinkedIn](https://linkedin.com/in/eshwarikhurd)
- **Shravani Kamthankar** — Pune Institute of Computer Technology
- **Avani Kelkar** — Pune Institute of Computer Technology
- **Ravinder B. Yerram** — Pune Institute of Computer Technology (Advisor)

---

## License

This repository is made available for academic and research purposes. See [LICENSE](LICENSE) for details.
