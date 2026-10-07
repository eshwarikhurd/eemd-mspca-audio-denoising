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
eemd-mspca-audio-denoising/
├── matlab/                     # Denoising methods (pure functions: signal in, signal out)
│   ├── denoise_emd_svd.m       # EMD + Hankel-SVD (iterative) — main method of the paper
│   ├── denoise_wavelet.m       # Wavelet denoising using wden (sym8)
│   ├── denoise_emd_hurst.m     # EMD + Hurst exponent IMF selection
│   ├── denoise.m               # Run a method by name
│   ├── denoise_batch.m         # Batch entry point used by the Python benchmark
│   ├── run_demo.m              # Interactive demo: plots, metrics, playback
│   ├── hs_snr.m, snr_db.m, ... # Metrics and helpers
│   └── tests/                  # MATLAB unit tests
├── python/                     # Dataset, noise, metrics and benchmark runner
│   ├── run_benchmark.py
│   ├── datasets.py, noise.py, metrics.py, matlab_bridge.py
│   └── tests/
├── audio/Flute_audio.mp3       # Test audio: flute sample @ 44100 Hz
├── .github/workflows/          # CI: MATLAB tests + small benchmark on every push
├── requirements.txt
└── README.md
```

---

## Methods

### 1. EMD + Hankel-SVD (`denoise_emd_svd.m`)
The primary method from the paper. Applies iterative denoising over 5 passes:
1. Decompose the signal into Intrinsic Mode Functions (IMFs) via EMD with PCHIP interpolation.
2. Retain the first 6 IMFs (least noisy).
3. For each IMF, build a Hankel matrix and perform SVD.
4. Apply adaptive thresholding: zero out singular values below `0.6 × median(σ)`.
5. Reconstruct via diagonal averaging.
6. Apply a final moving-mean smoother (window = 5).

**Metrics reported:** Hildebrand-Sekhon SNR (via Welch PSD).

### 2. Wavelet Denoising (`denoise_wavelet.m`)
Single-pass denoising using MATLAB's `wden`:
- Wavelet: `sym8`
- Thresholding rule: `sqtwolog` (universal threshold), soft
- Decomposition level: 3
- Noise estimation: `mln` (level-dependent)

### 3. EMD + Hurst Exponent (`denoise_emd_hurst.m`)
- Decomposes signal into IMFs.
- Estimates the Hurst exponent `H` for each IMF (rescaled-range analysis, `estimate_hurst.m`).
- Subtracts IMFs with `H < 0.5` (anti-persistent, noise-dominated components).

---

## Requirements

Everything used here is free for academic use.

- **MATLAB R2021a or later** with the **Signal Processing Toolbox** (`emd`, `pwelch`) and **Wavelet Toolbox** (`wden`)
- **Python 3.10+** for the benchmark: `pip install -r requirements.txt`

---

## Usage

### Use a method directly (MATLAB)
```matlab
addpath('matlab')
[x, fs] = audioread('audio/Flute_audio.mp3');
y = denoise_emd_svd(x(1:fs, 1));             % paper defaults
y = denoise_emd_svd(x(1:fs, 1), L=30, n_iter=3);
y = denoise(x(1:fs, 1), 'wavelet');          % or 'emd_svd', 'emd_hurst'
```

### Interactive demo (MATLAB)
```matlab
run('matlab/run_demo.m')
```
Adds white noise at 15 dB to the chosen clip (default: the flute), runs all three methods,
prints SNR and Hildebrand-Sekhon SNR, plots the spectra and can play the results.

### Benchmark (Python + MATLAB)
```bash
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt

# Flute clip with white noise at 0/5/10/15 dB
python python/run_benchmark.py --dataset flute

# NOIZEUS speech corpus (downloaded automatically to data/noizeus)
python python/run_benchmark.py --dataset noizeus
python python/run_benchmark.py --dataset noizeus --noises babble car --snrs 5 15 --limit 5

# Any audio file or folder, with white noise or your own noise recording
python python/run_benchmark.py --dataset path/to/clips --noises white path/to/noise.wav
```
The runner finds MATLAB on `PATH` or in `/Applications` (override with `--matlab` or `MATLAB_BIN`).
Results go to `results/<dataset>/`:
- `results.csv`: one row per clip × noise × input SNR × method, with SNR, segmental SNR, PESQ, STOI,
  Hildebrand-Sekhon SNR and runtime. The `noisy` method is the unprocessed input (baseline).
- `summary.csv`: means per method, noise and input SNR.

**NOIZEUS** (Hu & Loizou, 2007) has 30 IEEE sentences at 8 kHz with 8 real-world noises at
0/5/10/15 dB, and is free for research. Please cite *Hu, Y. and Loizou, P. (2007). Subjective
evaluation and comparison of speech enhancement algorithms. Speech Communication, 49, 588-601.*

### Tests
```bash
pytest python/tests                                   # Python
matlab -batch "runtests('matlab/tests')"              # MATLAB
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
