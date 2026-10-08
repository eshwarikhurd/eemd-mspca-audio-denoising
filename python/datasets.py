"""Load clean (and, for NOIZEUS, pre-made noisy) audio clips for the benchmark."""

import io
import ssl
import urllib.request
import zipfile
from dataclasses import dataclass, field
from pathlib import Path

import certifi
import numpy as np
import soundfile as sf

NOIZEUS_URL = "https://ecs.utdallas.edu/loizou/speech/noizeus/"
NOIZEUS_NOISES = ("airport", "babble", "car", "exhibition", "restaurant", "station", "street", "train")
NOIZEUS_SNRS = (0, 5, 10, 15)
# The NOIZEUS server does not send its intermediate certificate, so TLS
# verification fails unless we add it ourselves (browsers fetch it silently).
NOIZEUS_INTERMEDIATE_CA = "http://crt.sectigo.com/InCommonRSAServerCA2.crt"
AUDIO_EXTS = {".wav", ".flac", ".mp3", ".ogg"}


@dataclass
class Clip:
    name: str
    clean: np.ndarray
    fs: int
    # Ready-made noisy versions shipped with the dataset, keyed by (noise, snr_db).
    noisy: dict = field(default_factory=dict)


def read_audio(path, max_seconds=None, normalize=False):
    """Read an audio file as a mono float64 array."""
    x, fs = sf.read(str(path), dtype="float64", always_2d=True)
    x = x.mean(axis=1)
    if max_seconds is not None:
        x = x[: int(round(max_seconds * fs))]
    if normalize:
        x = x / np.max(np.abs(x))
    return x, fs


def _noizeus_ssl_context():
    """Verified TLS context that also knows the server's missing intermediate CA.

    The intermediate is only used to build the chain: partial chains are
    disabled, so it must still chain up to a trusted root in certifi.
    """
    ctx = ssl.create_default_context(cafile=certifi.where())
    ctx.verify_flags &= ~ssl.VERIFY_X509_PARTIAL_CHAIN
    with urllib.request.urlopen(NOIZEUS_INTERMEDIATE_CA) as resp:
        ctx.load_verify_locations(cadata=resp.read())
    return ctx


def download_noizeus(root, noises=NOIZEUS_NOISES, snrs=NOIZEUS_SNRS):
    """Download and unzip the NOIZEUS files that are not in root yet."""
    root = Path(root)
    wanted = [("clean.zip", root / "clean" / "sp01.wav")]
    wanted += [(f"{n}_{s}dB.zip", root / f"{s}dB" / f"sp01_{n}_sn{s}.wav") for n in noises for s in snrs]
    missing = [name for name, marker in wanted if not marker.exists()]
    if not missing:
        return
    ctx = _noizeus_ssl_context()
    for name in missing:
        print(f"Downloading NOIZEUS {name}")
        with urllib.request.urlopen(NOIZEUS_URL + name, context=ctx) as resp:
            zipfile.ZipFile(io.BytesIO(resp.read())).extractall(root)


def load_noizeus(root, noises=NOIZEUS_NOISES, snrs=NOIZEUS_SNRS, limit=None):
    """NOIZEUS: 30 IEEE sentences at 8 kHz with 8 real noises at 0/5/10/15 dB.

    Cite: Hu, Y. and Loizou, P. (2007), Speech Communication 49, 588-601.
    """
    root = Path(root)
    noises = [n for n in noises if n in NOIZEUS_NOISES]
    download_noizeus(root, noises, snrs)
    clips = []
    for path in sorted((root / "clean").glob("sp*.wav"))[:limit]:
        clean, fs = read_audio(path)
        clip = Clip(path.stem, clean, fs)
        for n in noises:
            for s in snrs:
                clip.noisy[(n, s)], _ = read_audio(root / f"{s}dB" / f"{path.stem}_{n}_sn{s}.wav")
        clips.append(clip)
    return clips


def load_files(path, max_seconds=None, limit=None):
    """Load one audio file or every audio file in a folder (normalized to peak 1)."""
    path = Path(path)
    files = [path] if path.is_file() else sorted(p for p in path.iterdir() if p.suffix.lower() in AUDIO_EXTS)
    clips = []
    for f in files[:limit]:
        x, fs = read_audio(f, max_seconds, normalize=True)
        clips.append(Clip(f.stem, x, fs))
    return clips
