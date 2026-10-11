import sys
from pathlib import Path

import numpy as np
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import datasets  # noqa: E402
import metrics  # noqa: E402
from noise import add_noise  # noqa: E402

FLUTE = Path(__file__).resolve().parents[2] / "audio" / "Flute_audio.mp3"


@pytest.fixture
def tone():
    fs = 16000
    t = np.arange(fs) / fs
    return np.sin(2 * np.pi * 440 * t) * (1 + 0.5 * np.sin(2 * np.pi * 3 * t)), fs


@pytest.mark.parametrize("snr_db", [0, 5, 15])
def test_white_noise_hits_target_snr(tone, snr_db):
    x, _ = tone
    noisy = add_noise(x, snr_db, np.random.default_rng(0))
    assert metrics.snr(x, noisy) == pytest.approx(snr_db, abs=1e-9)


def test_recorded_noise_hits_target_snr(tone):
    x, _ = tone
    rng = np.random.default_rng(0)
    noisy = add_noise(x, 5, rng, noise=rng.standard_normal(1000))  # shorter than x: gets tiled
    assert metrics.snr(x, noisy) == pytest.approx(5, abs=1e-9)


def test_noise_is_reproducible(tone):
    x, _ = tone
    a = add_noise(x, 5, np.random.default_rng(42))
    b = add_noise(x, 5, np.random.default_rng(42))
    np.testing.assert_array_equal(a, b)


def test_metrics_rank_cleaner_signal_higher(tone):
    x, fs = tone
    rng = np.random.default_rng(0)
    low = metrics.compute_all(x, add_noise(x, 0, rng), fs)
    high = metrics.compute_all(x, add_noise(x, 20, rng), fs)
    for key in ("snr", "segsnr", "stoi", "hs_snr"):
        assert high[key] > low[key], key


def test_segsnr_is_clamped(tone):
    x, fs = tone
    assert metrics.segsnr(x, x, fs) == pytest.approx(35.0)


def test_flute_loads():
    x, fs = datasets.read_audio(FLUTE, max_seconds=1, normalize=True)
    assert fs == 44100
    assert len(x) == 44100
    assert np.max(np.abs(x)) == pytest.approx(1.0)
