# Audio Denoising with Empirical Mode Decomposition: Reproducing and Benchmarking EMD-SVD, EEMD-MSPCA and Their Baselines

---

## 1. Intent (Why?)

**Problem Statement**
Our SmartCom 2025 review (Khurd et al., 2026) proposed an EMD + Hankel-SVD pipeline for audio denoising and reported a
+12.53 dB improvement on a 1-second flute clip with 15 dB white noise. That result came from a single clip, a single
noise type and a single metric, the blind Hildebrand-Sekhon SNR (HS-SNR). HS-SNR estimates noise from the shape of the
output's own spectrum and never compares the output with the clean signal. The original code was also three
interactive scripts (file picker, plots, playback) that could not be run on a dataset, and one of them called a function
that did not exist. This repository turns that work into something that can be measured: reusable methods, a public
speech dataset with real-world noise, standard reference-based metrics, and the EEMD-MSPCA method of Peng et al. (2021)
with the baselines from their comparison.

**Significance**
- EMD-family methods are adaptive and need no training data, which makes them attractive for audio where labelled
  clean/noisy pairs are scarce. Whether they actually beat simple filters on real noise is rarely tested on a common
  benchmark.
- Blind metrics such as HS-SNR can reward outputs that sound worse. Comparing them with SNR, PESQ (perceived quality)
  and STOI (intelligibility) on the same files shows how far a claim depends on the metric chosen.
- Peng et al. leave several settings of EEMD-MSPCA unspecified. A reproduction that documents each choice is useful to
  anyone building on that paper.

**Stakeholders / Beneficiaries**
- The paper's authors, who need defensible numbers before citing or extending the +12.53 dB result.
- Signal-processing students and researchers who want a free, runnable reference for EMD, EEMD, Hankel-SVD and MSPCA
  denoising in MATLAB, with Python evaluation.
- Reviewers, who can re-run every number from one command.

**Consequences of Inaction**
The published improvement would stay unverifiable and, as the benchmark below shows, it does not hold for true SNR or
perceived quality. Any follow-up work would inherit an untested method and a metric that cannot tell good outputs from
bad ones.

**Alignment with Broader Goals**
The project combines two threads: (1) decomposition-based denoising (EMD, EEMD, Hankel SVD/PCA, wavelets), and
(2) reproducible evaluation with public data and standard metrics. Every resource used is free for academic use.

---

## 2. Desired Outcome (What?)

**Target Results**
- Every method as a MATLAB function (signal in, denoised signal out) with the published settings as defaults.
- A benchmark that runs any method over a dataset and reports reference-based metrics per file.
- A faithful, documented implementation of EEMD-MSPCA (Peng et al., 2021), checked against the paper's Table 1.
- Figures that show both *how well* each method does and *what it does internally*.
- Settings tuned on held-out data, so the methods are compared at their best rather than at values tuned for one clip.

**Success Metrics**
- **SNR change (dB)**: global SNR of the output against the clean signal, minus that of the noisy input.
- **Segmental SNR**: SNR over 30 ms frames, clamped to [-10, 35] dB, which weights quiet passages more fairly.
- **PESQ change**: ITU-T P.862 perceived quality (narrowband at 8 kHz, wideband at 16 kHz).
- **STOI change**: short-time objective intelligibility (0 to 1).
- **HS-SNR**: kept only for comparison with the paper; it is blind and saturates (see Section 5).
- **Runtime** per file.

**Minimum Viable Outcome**
All methods running on NOIZEUS and the flute clip with SNR, PESQ and STOI reported per input SNR, and the EMD-SVD
output shown to match the original script.

**Definition of Done**
- [x] Restructured EMD-SVD identical to the original script (max difference 6.7e-15).
- [x] EEMD-MSPCA implemented and checked against Peng et al.'s Table 1 (partial reproduction, Section 5).
- [x] Baselines from Peng et al.'s comparison implemented and benchmarked.
- [x] Full NOIZEUS (960 noisy files) and flute benchmarks for all seven methods.
- [x] Parameter sweep: tune on sentences 1-10, report on held-out sentences 11-30.
- [x] README results section updated with the benchmark numbers (the paper's claim is qualified there; restating it in the paper is the authors' call).

---

## 3. Deliverable (How?)

**Methodology Overview**
MATLAB does the signal processing; Python does everything around it. Python prepares clean and noisy WAV files, writes
one job list per method, calls MATLAB once with `matlab -batch`, then scores the outputs and draws the figures. Using
files as the interface keeps the two languages independent: the same MATLAB step runs locally, in GitHub Actions, or
by hand in MATLAB Online.

```
 datasets.py ──► clean audio ──► noise.py / NOIZEUS files ──► noisy WAVs + jobs_<method>.txt
                                                                      │
                                         matlab -batch denoise_batch  ▼
                                    denoise.m ──► denoise_<method>.m ──► denoised WAVs
                                                                      │
              metrics.py (SNR, segSNR, PESQ, STOI, HS-SNR) ◄──────────┘
                     │
                     ▼
     results.csv / summary.csv ──► plot_results.py ──► figures/*.png, listen.html
                     │
                     ▼
     run_sweep.py (tune on sentences 1-10, evaluate on 11-30)
```

**How the methods work**

1. **EMD-SVD** (the paper's method). Empirical mode decomposition splits the signal into intrinsic mode functions
   (IMFs), from high to low frequency. The first 6 IMFs are kept. Each one is turned into a Hankel (trajectory) matrix
   of its 20 lagged copies; singular values below 0.6 × their median are set to zero, and the matrix is averaged back
   into a signal. The IMFs are summed, the whole process repeats 5 times, and a 5-sample moving average smooths the
   result.
2. **Wavelet**. `wden` with the `sym8` wavelet, 3 levels, universal threshold, soft thresholding and level-dependent
   noise estimates.
3. **EMD-Hurst**. Each IMF's Hurst exponent is estimated by rescaled-range analysis. IMFs with H < 0.5 behave like
   anti-persistent noise and are subtracted from the signal.
4. **EEMD-MSPCA** (Peng et al., 2021). Ensemble EMD averages the IMFs of 100 copies of the signal, each with small added
   white noise, which reduces mode mixing. Leading components with a variance contribution rate below 0.01 are dropped.
   Each remaining component gets PCA on its Hankel matrix, keeping principal components up to 85% of the cumulative
   eigenvalues, then soft thresholding with T = σ·√(2 ln N). The components are summed.
5. **Baselines from Peng et al.'s comparison**: a zero-phase Butterworth low-pass filter; wavelet-MSPCA (Bakshi, 1998)
   applied to the signal's lagged copies with MATLAB's `wmspca`; and EEMD-SVD, which combines the EEMD and VCR steps of
   EEMD-MSPCA with the singular-value rule of EMD-SVD.

**Files**

*MATLAB methods (`matlab/`)*

| File | What it does |
|---|---|
| `denoise.m` | Runs a method by name (`'emd_svd'`, `'wavelet'`, `'emd_hurst'`, `'eemd_mspca'`, `'lowpass'`, `'wavelet_mspca'`, `'eemd_svd'`) and passes options on. |
| `denoise_emd_svd.m` | EMD-SVD. Options `L`, `n_iter`, `n_imfs`, `thr`, `smooth`; defaults are the paper's. |
| `denoise_wavelet.m` | Wavelet thresholding with `wden`. Options `wavelet`, `level`, `rule`, `sorh`, `scal`. |
| `denoise_emd_hurst.m` | Removes IMFs whose Hurst exponent is below `threshold` (0.5). |
| `denoise_eemd_mspca.m` | EEMD-MSPCA. Options for EEMD (`n_ensemble`, `noise_ratio`, `seed`), VCR (`vcr_min`), PCA (`L`, `energy`, `readout`) and thresholding (`sigma`, `t_scale`). A second output returns every intermediate step for plotting. |
| `denoise_lowpass.m` | Butterworth low-pass, cutoff `wn` as a fraction of Nyquist, zero phase by default. |
| `denoise_wavelet_mspca.m` | Wavelet-MSPCA via `wmspca` on an `L`-column Hankel embedding. |
| `denoise_eemd_svd.m` | EEMD + VCR rule + the EMD-SVD singular-value rule. |
| `eemd.m` | Ensemble EMD. MATLAB has only plain `emd`; this fixes the number of IMFs so the trials line up, and returns IMFs plus residual. |
| `svd_denoise_imfs.m` | Hankel-SVD truncation of each IMF, summed. Shared by EMD-SVD and EEMD-SVD. |
| `hankel_matrix.m`, `diagonal_averaging.m` | Build the L-row trajectory matrix and invert it by averaging anti-diagonals (vectorised with `accumarray`). |
| `estimate_hurst.m` | Hurst exponent by rescaled-range analysis. The original code called a function that did not exist. |
| `snr_db.m`, `hs_snr.m` | Reference SNR, and the blind Hildebrand-Sekhon SNR on a Welch PSD (one shared copy). |
| `add_white_noise.m` | White Gaussian noise at a given SNR, for the demo and tests. |
| `denoise_batch.m` | Batch entry point for Python: runs every `jobs_<method>.txt` in a folder and writes 32-bit float WAVs and timings. A job named `jobs_emd_svd@smooth=1,thr=0.3.txt` passes those options. |
| `run_demo.m` | The original interactive experience: pick a clip (default the flute), add 15 dB noise, run every method, print SNR and HS-SNR, plot spectra, optional playback. |
| `plot_decomposition.m` | Figure: EMD IMFs with Hurst exponents, EMD-SVD singular values against the threshold, EEMD variance contribution rates. |
| `plot_eemd_mspca.m` | Figure: EEMD-MSPCA step by step, in the style of Peng et al.'s Figs. 3-4. |
| `tests/test_denoising.m` | 15 unit tests: Hankel round trip, vectorised averaging vs a loop, Hurst on known signals, EEMD reconstruction and seeding, Peng's Blocks test for EEMD-MSPCA and wavelet-MSPCA, output length for every method. |

*Python pipeline (`python/`)*

| File | What it does |
|---|---|
| `datasets.py` | Loads NOIZEUS (downloaded on first use into `data/noizeus`; works around the server's incomplete TLS chain without disabling verification), the flute clip, or any audio file or folder. |
| `noise.py` | `add_noise`: white noise or a random segment of a noise recording, scaled to an exact SNR, seeded per case. |
| `metrics.py` | SNR, segmental SNR, PESQ, STOI, and a Python port of `hs_snr.m` that matches MATLAB to 4 decimals. |
| `matlab_bridge.py` | Finds MATLAB (`--matlab`, `$MATLAB_BIN`, `PATH`, or `/Applications`) and runs commands with `matlab -batch`. |
| `run_benchmark.py` | Prepare, denoise, score. Writes `results/<dataset>/results.csv` (one row per clip × noise × SNR × method) and `summary.csv`. `--stage prepare` / `--stage score` split the run around MATLAB for CI. |
| `plot_results.py` | Figures and the listening page from a finished run (Section 6). `--decomposition` also draws the MATLAB figures. |
| `run_sweep.py` | Parameter sweep: 70 settings tuned on NOIZEUS sentences 1-10, best per method re-run on sentences 11-30 and compared with the defaults. |
| `tests/test_pipeline.py` | 8 tests: exact SNR from `add_noise`, reproducible noise, metric ordering, segSNR clamping, flute loading. |

*Everything else*

| Path | Contents |
|---|---|
| `audio/Flute_audio.mp3` | The paper's test clip (44.1 kHz; the first second is used). |
| `.github/workflows/matlab.yml` | CI on GitHub Actions (MATLAB is free there for public repositories): MATLAB tests, then a small benchmark whose CSVs are uploaded. Installs GStreamer so MATLAB can read MP3 on Linux. |
| `requirements.txt` | Python dependencies, all open source. |
| `data/` (gitignored) | NOIZEUS download and local notes such as `data/plan.md`. |
| `results/` (gitignored) | Benchmark outputs: per-dataset CSVs, WAVs, `figures/`, `listen.html`, and `sweep/`. |

**Integration with Existing Knowledge**
Builds on EMD (Huang et al.) and EEMD (Wu & Huang, 2009), Hankel/singular-spectrum denoising, wavelet thresholding
(Donoho & Johnstone), MSPCA (Bakshi, 1998), EEMD-MSPCA (Peng et al., 2021), and the NOIZEUS evaluation corpus with
PESQ and STOI (Hu & Loizou, 2007).

---

## 4. Constraints (How not?)

**Business Constraints**
- Free resources only: MATLAB through the UCI campus license (and free in GitHub Actions for this public repository),
  open-source Python packages, and datasets free for research use.

**Technical Constraints**
- MATLAB on this Mac only accepts the UCI sign-in outside sandboxed shells, so automated runs need that permission.
- On Linux, MATLAB needs GStreamer plugins to decode MP3 (installed in CI).
- PESQ only works at 8 or 16 kHz, so other rates are resampled to 16 kHz for PESQ only.
- NOIZEUS defines SNR on the active speech level after telephone-band filtering, so whole-file SNR of its noisy files is
  about 0.6 dB below the nominal value.
- EEMD runs EMD 100 times per signal: about 1.4 s per NOIZEUS file and 3 s for the flute clip.

**Resource Constraints**
- NOIZEUS is 30 sentences at 8 kHz: enough to compare methods, too small to train a model.

**Explicitly Ruled Out**
- HS-SNR as a headline metric. It is blind, and it saturates: the clean flute scores 47.7 dB, and several outputs score
  about the same regardless of how noisy the input was.
- The MATLAB Engine for Python. All files go to MATLAB in one `matlab -batch` call, so the engine would add a Python
  version dependency and nothing else.
- Republishing NOIZEUS audio. Figures and listening pages stay in the gitignored `results/` folder.

**Ethical / Regulatory Considerations**
- NOIZEUS must be cited (Hu & Loizou, 2007) when used.

**Time-Boxing**
- **Phase 1, restructure and verify:** functions, tests, identical EMD-SVD output. Done.
- **Phase 2, benchmark:** NOIZEUS and flute with reference metrics, EEMD-MSPCA and baselines, figures. Done.
- **Phase 3, tuning and write-up:** held-out parameter sweep and README update. Done; the paper claim is pending.

---

## 5. Preliminary Results

**Current Status (as of 2026-10-07)**

*Reproduction checks*
- Restructured EMD-SVD matches the original script to 6.7e-15 on the same input.
- Peng et al.'s Table 1 (synthetic `wnoise` signals, N = 1024, noise 0.2·randn, rescaled to the paper's noisy SNR):

| Signal | Noisy | EEMD-MSPCA (ours / paper) | Wavelet-MSPCA (ours / paper) |
|---|---|---|---|
| Blocks | 7.01 | 12.01 / 12.55 | 14.6 / 11.83 |
| Bumps | 12.57 | 16.89 / 20.13 | 16.0 / 19.88 |
| Heavy sine | 9.53 | 16.13 / 19.28 | 20.9 / 19.04 |
| Doppler | 9.34 | 14.24 / 16.84 | 14.9 / 16.58 |

  The paper leaves the Hankel size, the reconstruction rule and the meaning of σ open. With σ read literally (the
  component's own spread) the threshold zeroes nearly every sample, so σ is taken as the noise level of what the PCA
  step removed. The remaining gap is most likely EMD sifting and ensemble settings the paper does not report.

*Benchmark: mean change against the noisy input at default settings*

NOIZEUS (30 sentences × 8 real noises, 240 files per input SNR):

| Method | ΔSNR 0 dB | ΔSNR 15 dB | ΔPESQ 0 dB | ΔPESQ 15 dB | ΔSTOI 0 dB | ΔSTOI 15 dB |
|---|---|---|---|---|---|---|
| EMD-SVD | +1.44 | −9.08 | +0.09 | +0.18 | −0.05 | −0.07 |
| EEMD-MSPCA | **+3.63** | −5.22 | −0.05 | −0.19 | −0.05 | −0.12 |
| Wavelet | +1.59 | −7.45 | −0.11 | −0.68 | −0.11 | −0.10 |
| EMD-Hurst | +0.28 | −9.36 | −0.26 | −0.54 | −0.30 | −0.23 |
| Low-pass | +0.70 | −2.51 | +0.06 | +0.10 | −0.03 | −0.05 |
| Wavelet-MSPCA | +1.33 | −5.94 | **+0.15** | **+0.29** | −0.03 | −0.06 |
| EEMD-SVD | +0.02 | **−0.24** | +0.01 | +0.03 | −0.01 | −0.01 |

Flute (white noise, 1 s, one file per input SNR):

| Method | ΔSNR 0 dB | ΔSNR 15 dB | ΔPESQ 0 dB | ΔPESQ 15 dB |
|---|---|---|---|---|
| EMD-SVD | +3.36 | −2.27 | +0.17 | −1.60 |
| EEMD-MSPCA | +5.63 | −6.26 | +0.22 | −0.88 |
| Wavelet | +9.00 | **+8.00** | +0.48 | +0.14 |
| EMD-Hurst | +7.92 | +4.29 | +0.44 | −0.03 |
| Low-pass | +3.36 | +3.39 | +0.00 | +0.00 |
| Wavelet-MSPCA | **+11.20** | +4.37 | **+0.49** | **+0.30** |
| EEMD-SVD | +0.14 | +0.22 | +0.03 | +0.05 |

**What the benchmark actually shows so far**
- **The paper's +12.53 dB is an HS-SNR gain.** On the same setting (flute, 15 dB white noise) EMD-SVD raises HS-SNR by
  about 16.7 dB but lowers true SNR by 2.3 dB and PESQ by 1.6.
- **At default settings, every method makes 10-15 dB speech worse by SNR**, and no method improves STOI anywhere. The
  settings were chosen for 44.1 kHz flute audio; at 8 kHz, EMD-SVD's 5-sample moving average already cuts frequencies
  above about 1.6 kHz.
- **EEMD-MSPCA has the best SNR on noisy speech** (+3.6 dB at 0 dB input). Its step-by-step figure shows why it fails
  at high SNR: the VCR step drops nothing on our audio, the PCA step changes little, and the soft threshold shrinks the
  real signal along with the noise (about 20% lower peaks on the flute).
- **Wavelet-MSPCA is the strongest baseline**: the best PESQ gain on NOIZEUS at every SNR, and the best flute SNR at
  0-5 dB.
- **EMD-SVD still improves PESQ on speech for every noise type.** Wavelet-MSPCA and the low-pass filter do too, and
  EEMD-SVD by a negligible +0.01-0.03; wavelet, EMD-Hurst and EEMD-MSPCA lower it.

*Parameter sweep*: 70 settings tuned on NOIZEUS sentences 1-10 (4 noises, all SNRs; best setting per method by mean
PESQ change), then default and tuned settings compared on held-out sentences 11-30 (all 8 noises, 640 files). Mean
change against the noisy input, averaged over 0-15 dB:

| Method | Tuned setting | ΔSNR default → tuned | ΔPESQ default → tuned | ΔSTOI default → tuned |
|---|---|---|---|---|
| EMD-SVD | 1 pass, all IMFs, thr = 1.0 | −3.37 → −3.30 | +0.10 → +0.11 | −0.06 → −0.04 |
| EEMD-MSPCA | no soft threshold (`t_scale = 0`) | −0.60 → −0.23 | −0.11 → **+0.11** | −0.09 → −0.03 |
| Wavelet | minimax threshold, single-level noise estimate | −3.12 → **+0.84** | −0.42 → −0.06 | −0.11 → −0.02 |
| EMD-Hurst | H < 0.3 (removes nothing) | −4.39 → 0.00 | −0.34 → 0.00 | −0.25 → 0.00 |
| Low-pass | wn = 0.25 | −0.56 → −3.57 | +0.07 → +0.04 | −0.04 → −0.08 |
| Wavelet-MSPCA | L = 32 | −1.71 → −1.69 | **+0.19** → +0.16 | −0.05 → −0.06 |
| EEMD-SVD | thr = 2.0 | −0.06 → −2.35 | +0.02 → −0.02 | −0.01 → −0.09 |

- Tuning helps wavelet most: it becomes the only method with a positive average SNR change on held-out speech.
- EEMD-MSPCA's best setting switches off its soft threshold, which turns a PESQ loss into a gain and confirms what the
  step-by-step figure shows. EMD-Hurst's best setting removes no IMFs, i.e. the method has nothing useful to offer on
  this data.
- For low-pass, EEMD-SVD and wavelet-MSPCA the tuned setting is worse than the default on held-out files: the tuning set
  had 4 noise types, the held-out set 8, and the differences being chased were small.
- The best held-out PESQ gain is still wavelet-MSPCA at its default settings (+0.19). No setting of any method
  improves STOI on average.
- Tuned EEMD runs used 25 ensemble members instead of 100 to keep the sweep fast; on audio this changed SNR by less
  than 0.1 dB in earlier tests.

Files: `results/sweep/tune_summary.csv` (every setting), `best.json`, `eval_summary.csv`, `default_vs_tuned.png`.

Not yet done: significance tests across files, a music dataset beyond the single flute clip, and listening tests.

---

## 6. Demos

- `run('matlab/run_demo.m')`: interactive comparison on any clip, with playback.
- `python python/plot_results.py --dataset noizeus --decomposition` writes to `results/noizeus/`:
  - `figures/metric_vs_snr.png`: change in SNR, PESQ and STOI per input SNR, mean ± 95% CI.
  - `figures/distributions.png`: per-file spread and the share of files each method improved.
  - `figures/noise_heatmap_pesq.png`: PESQ change per noise type and method.
  - `figures/spectrogram_<case>.png`, `figures/psd_<case>.png`: one clip in detail, with each method's error.
  - `figures/decomposition_<case>.png`, `figures/eemd_mspca_<case>.png`: what the EMD-based methods keep and remove.
  - `listen.html`: every version of the example clips at the same gain, next to their metrics.

---

## 7. Risks & Open Questions

- **Should the paper's +12.53 dB be restated?** It is reproducible as an HS-SNR gain but not as an improvement in true
  SNR or PESQ. This is the authors' call.
- **EEMD-MSPCA is only partly reproduced** (0.5-3.2 dB short on Peng's signals). Their code or EMD settings would close
  the gap.
- **EEMD-SVD's singular-value rule is a guess.** Peng et al. cite Li et al. without describing it; we reuse the EMD-SVD
  rule, which keeps almost everything.
- **One music clip is not a music benchmark.** A music dataset (e.g. MUSDB18 clips with DEMAND noise) would test whether
  the flute results generalise.
- **Tuning by mean PESQ can pick "do nothing".** EMD-Hurst's winning setting removes nothing. A criterion that also
  requires an SNR gain, or tuning per input SNR, may give more useful settings.

---

## 8. Timeline

- **Done:** functions and tests; Python benchmark; CI; EEMD-MSPCA; baselines; figures and listening page; NOIZEUS and
  flute benchmarks; held-out parameter sweep.
- **Next:** decision on the paper claim, a music dataset, per-SNR tuning, significance tests.

---

## 9. References

- Khurd, E., Kamthankar, S., Kelkar, A., Yerram, R. B. (2026). Denoising Techniques of Audio Signals—A Review. In:
  *Smart Trends in Computing and Communications* (SmartCom 2025), LNNS vol. 1458, pp. 317-326. Springer, Singapore.
  https://doi.org/10.1007/978-981-96-7499-2_27
- Peng, K., Guo, H., Shang, X. (2021). EEMD and multiscale PCA-based signal denoising method and its application to
  seismic P-phase arrival picking. *Sensors*, 21(16), 5271. https://doi.org/10.3390/s21165271
- Wu, Z., Huang, N. E. (2009). Ensemble empirical mode decomposition: a noise-assisted data analysis method.
  *Advances in Adaptive Data Analysis*, 1(1), 1-41.
- Bakshi, B. R. (1998). Multiscale PCA with application to multivariate statistical process monitoring.
  *AIChE Journal*, 44(7), 1596-1610.
- Hu, Y., Loizou, P. (2007). Subjective evaluation and comparison of speech enhancement algorithms.
  *Speech Communication*, 49, 588-601.
