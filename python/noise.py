"""Add noise to clean signals at a chosen SNR."""

import numpy as np


def add_noise(clean, snr_db, rng, noise=None):
    """Return clean + noise scaled so the SNR is exactly snr_db.

    noise=None adds white Gaussian noise; otherwise a random segment of the
    given noise recording is used (repeated if it is shorter than clean).
    """
    n = len(clean)
    if noise is None:
        segment = rng.standard_normal(n)
    else:
        noise = np.tile(noise, int(np.ceil(n / len(noise))) + 1)
        start = rng.integers(0, len(noise) - n + 1)
        segment = noise[start : start + n]
    gain = np.sqrt(np.mean(clean**2) / (np.mean(segment**2) * 10 ** (snr_db / 10)))
    return clean + gain * segment
