# Audio Signal Denoising — EMD-SVD & Wavelet Methods

[![Paper](https://img.shields.io/badge/Paper-SpringerLink-blue)](https://link.springer.com/chapter/10.1007/978-981-96-7499-2_27)
[![Conference](https://img.shields.io/badge/Conference-SmartCom%202025-orange)](https://link.springer.com/conference/smartcom)
[![MATLAB](https://img.shields.io/badge/Language-MATLAB-red)](https://www.mathworks.com/)

MATLAB implementation of audio signal denoising techniques presented in:

> **Khurd, E., Kamthankar, S., Kelkar, A., & Yerram, R. B.** (2026). *Denoising Techniques of Audio Signals — A Review.* In: *Smart Trends in Computing and Communications* (SmartCom 2025). Lecture Notes in Networks and Systems, vol 1458. Springer, Singapore.  
> DOI: [10.1007/978-981-96-7499-2_27](https://doi.org/10.1007/978-981-96-7499-2_27)

---

## Overview

This repository provides implementations of four audio denoising pipelines evaluated on a flute audio sample at **15 dB input SNR**. Performance is measured using the **Hildebrand-Sekhon SNR estimator** applied to the Welch power spectral density.

| Method | Key Technique | Highlight |
|--------|--------------|-----------|
| **EMD + SVD** | Empirical Mode Decomposition → Hankel-SVD | Iterative, adaptive thresholding |
| **Wavelet** | `wden` soft-thresholding (`sym8`, level 3) | Fast, single-pass |
| **EMD (Hurst-based)** | EMD → Hurst exponent IMF selection | Eliminates fractal noise IMFs |
| **EEMD-MSPCA** | Ensemble EMD → per-IMF Hankel PCA → soft threshold | Method of Peng et al. (2021) |

---

## Repository Structure

```
eemd-mspca-audio-denoising/
├── matlab/                     # Denoising methods (pure functions: signal in, signal out)
│   ├── denoise_emd_svd.m       # EMD + Hankel-SVD (iterative) — main method of the paper
│   ├── denoise_wavelet.m       # Wavelet denoising using wden (sym8)
│   ├── denoise_emd_hurst.m     # EMD + Hurst exponent IMF selection
│   ├── denoise_eemd_mspca.m    # EEMD + multiscale PCA (Peng et al., 2021)
│   ├── eemd.m                  # Ensemble EMD
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

### 4. EEMD-MSPCA (`denoise_eemd_mspca.m`)
Follows Peng, Guo & Shang (2021):
1. Decompose the signal with ensemble EMD (`eemd.m`: 100 trials, added noise std = 0.2 × signal std) into IMFs and a residual.
2. Drop the leading high-frequency IMFs whose variance contribution rate (VCR) is below 0.01.
3. For each remaining component, run PCA on its Hankel matrix and keep the principal components up to 85% of the cumulative eigenvalue sum.
4. Soft-threshold each component with `T = σ·sqrt(2·ln N)`.
5. Sum the denoised components.

The paper does not give every setting. These were chosen by reproducing its synthetic tests
(Table 1: `wnoise` Blocks, Bumps, Heavy sine and Doppler, N = 1024, noise `0.2·randn`):
- Hankel matrix with `L = 10` rows.
- Components are rebuilt by diagonal averaging. The paper reads out the first row and last column, which scored lower in every test.
- `σ` is the noise level of what the PCA step removed (`median(|r|)/0.6745`). Taking `σ` as the component's own std or variance, as the paper's wording suggests, sets almost every sample to zero.

With these settings the reproduction is partial: Blocks 7.01 → 12.01 dB (paper: 12.55), Bumps 12.57 → 16.89
(20.13), Heavy sine 9.53 → 16.13 (19.28), Doppler 9.34 → 14.24 (16.84). All options are exposed as name-value
arguments, e.g. `denoise_eemd_mspca(x, L=16, sigma='std', readout='first_row_last_col')`.

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
y = denoise(x(1:fs, 1), 'wavelet');          % or 'emd_svd', 'emd_hurst', 'eemd_mspca'
```

### Interactive demo (MATLAB)
```matlab
run('matlab/run_demo.m')
```
Adds white noise at 15 dB to the chosen clip (default: the flute), runs the methods,
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

### Figures and listening page
```bash
python python/plot_results.py --dataset noizeus
python python/plot_results.py --dataset flute --examples Flute_audio_white_0dB --decomposition
```
Writes to `results/<dataset>/figures/`:
- `metric_vs_snr.png`: change in SNR, PESQ and STOI relative to the noisy input, per input SNR (the main results figure)
- `distributions.png`: per-file spread of the PESQ and STOI change, with the share of files each method improved
- `noise_heatmap_pesq.png`: mean PESQ change per noise type and method (datasets with several noise types)
- `spectrogram_<case>.png`, `psd_<case>.png`: one example in detail, including each method's error against the clean clip
- `decomposition_<case>.png` (with `--decomposition`, needs MATLAB): IMFs with their Hurst exponent, EMD-SVD singular values and EEMD variance contribution rates

and `results/<dataset>/listen.html`, which plays every version of the example clips at the same gain next to their metrics.

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

## References

- Peng, K., Guo, H., Shang, X. (2021). EEMD and multiscale PCA-based signal denoising method and its application to seismic P-phase arrival picking. *Sensors*, 21(16), 5271. https://doi.org/10.3390/s21165271
- Wu, Z., Huang, N. E. (2009). Ensemble empirical mode decomposition: a noise-assisted data analysis method. *Advances in Adaptive Data Analysis*, 1(1), 1–41.
- Hu, Y., Loizou, P. (2007). Subjective evaluation and comparison of speech enhancement algorithms. *Speech Communication*, 49, 588–601. (NOIZEUS)

---

## Authors

- **Eshwari Khurd** — UC Irvine (MS EECS) · [GitHub](https://github.com/eshwarikhurd) · [LinkedIn](https://linkedin.com/in/eshwarikhurd)
- **Shravani Kamthankar** — Pune Institute of Computer Technology
- **Avani Kelkar** — Pune Institute of Computer Technology
- **Ravinder B. Yerram** — Pune Institute of Computer Technology (Advisor)

---

## License

This repository is made available for academic and research purposes. See [LICENSE](LICENSE) for details.
