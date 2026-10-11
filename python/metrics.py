"""Quality metrics comparing a denoised signal with the clean reference."""

import warnings

import numpy as np
from pesq import pesq as _pesq
from pystoi import stoi as _stoi
from scipy.signal import resample_poly, welch
from scipy.signal.windows import hamming


def _align(ref, est):
    n = min(len(ref), len(est))
    return ref[:n], est[:n]


def snr(ref, est):
    """Global SNR in dB."""
    ref, est = _align(ref, est)
    return 10 * np.log10(np.sum(ref**2) / np.sum((ref - est) ** 2))


def segsnr(ref, est, fs, frame_ms=30, lo=-10.0, hi=35.0):
    """Segmental SNR in dB (30 ms frames, 75% overlap, clamped to [-10, 35])."""
    ref, est = _align(ref, est)
    win = int(round(frame_ms * fs / 1000))
    hop = win // 4
    vals = []
    for start in range(0, len(ref) - win + 1, hop):
        r = ref[start : start + win]
        e = r - est[start : start + win]
        vals.append(10 * np.log10(np.sum(r**2) / (np.sum(e**2) + 1e-12) + 1e-12))
    return float(np.mean(np.clip(vals, lo, hi)))


def pesq(ref, est, fs):
    """PESQ score and mode: narrowband at 8 kHz, otherwise wideband at 16 kHz."""
    ref, est = _align(ref, est)
    if fs == 8000:
        mode = "nb"
    else:
        mode = "wb"
        if fs != 16000:
            ref, est = resample_poly(ref, 16000, fs), resample_poly(est, 16000, fs)
            fs = 16000
    try:
        return float(_pesq(fs, ref, est, mode)), mode
    except Exception as err:  # e.g. no speech detected in a music clip
        warnings.warn(f"PESQ failed: {err}")
        return float("nan"), mode


def stoi(ref, est, fs):
    """Short-time objective intelligibility (0-1)."""
    ref, est = _align(ref, est)
    return float(_stoi(ref, est, fs, extended=False))


def hs_snr(x, fs):
    """Blind Hildebrand-Sekhon SNR (dB) on the Welch PSD; port of matlab/hs_snr.m."""
    _, pxx = welch(x, fs, window=hamming(1024, sym=True), nperseg=1024, noverlap=512,
                   nfft=1024, detrend=False)
    p = np.sort(pxx)
    noise_power = p.mean()
    for i in range(len(p), 1, -1):
        subset = p[:i]
        if subset.var(ddof=1) <= subset.mean() ** 2:
            noise_power = subset.mean()
            break
    signal_power = max(p.mean() - noise_power, np.finfo(float).eps)
    return 10 * np.log10(signal_power / noise_power)


def compute_all(ref, est, fs):
    """All metrics as a dict."""
    pesq_score, pesq_mode = pesq(ref, est, fs)
    return {
        "snr": snr(ref, est),
        "segsnr": segsnr(ref, est, fs),
        "pesq": pesq_score,
        "pesq_mode": pesq_mode,
        "stoi": stoi(ref, est, fs),
        "hs_snr": hs_snr(est, fs),
    }
