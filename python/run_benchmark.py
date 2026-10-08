"""Benchmark the denoising methods on a dataset.

Pipeline: load clean audio -> make noisy versions -> denoise with MATLAB ->
score against the clean audio -> results.csv (one row per clip/noise/SNR/method)
and summary.csv (mean per method/noise/SNR).

Examples:
    python python/run_benchmark.py --dataset flute --snrs 5 15
    python python/run_benchmark.py --dataset noizeus --noises babble car --limit 5
    python python/run_benchmark.py --dataset path/to/folder --noises white

--stage prepare / score split the run around the MATLAB step, so MATLAB can be
run separately (e.g. in CI): matlab -batch "addpath('matlab'); denoise_batch('<out>/work')"
"""

import argparse
import zlib
from pathlib import Path

import numpy as np
import pandas as pd
import soundfile as sf
from tqdm import tqdm

import datasets
import matlab_bridge
import metrics
from noise import add_noise

REPO = Path(__file__).resolve().parent.parent
MATLAB_METHODS = ("emd_svd", "wavelet", "emd_hurst")
METHODS = ("noisy",) + MATLAB_METHODS  # "noisy" = no denoising (baseline)


def parse_args():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--dataset", default="flute", help="noizeus, flute, or a path to an audio file/folder")
    p.add_argument("--noises", nargs="+", help="NOIZEUS noise names, 'white', or noise .wav paths "
                   "(default: all NOIZEUS noises for noizeus, otherwise white)")
    p.add_argument("--snrs", nargs="+", type=int, default=[0, 5, 10, 15], help="input SNRs in dB")
    p.add_argument("--methods", nargs="+", default=list(METHODS), choices=METHODS)
    p.add_argument("--limit", type=int, help="use only the first N clips")
    p.add_argument("--seconds", type=float, help="trim clips to N seconds (flute default: 1)")
    p.add_argument("--seed", type=int, default=0)
    p.add_argument("--out", type=Path, help="output folder (default: results/<dataset>)")
    p.add_argument("--stage", choices=("all", "prepare", "score"), default="all")
    p.add_argument("--matlab", help="path to the matlab executable")
    return p.parse_args()


def load_clips(args):
    if args.dataset == "noizeus":
        noises = args.noises or list(datasets.NOIZEUS_NOISES)
        return datasets.load_noizeus(REPO / "data" / "noizeus", noises, args.snrs, args.limit), noises
    if args.dataset == "flute":
        path, seconds = REPO / "audio" / "Flute_audio.mp3", args.seconds or 1.0
    else:
        path, seconds = Path(args.dataset), args.seconds
    return datasets.load_files(path, seconds, args.limit), args.noises or ["white"]


def make_noisy(clip, noise, snr, seed):
    """Dataset-provided noisy clip if there is one, otherwise add noise ourselves."""
    if (noise, snr) in clip.noisy:
        return clip.noisy[(noise, snr)]
    if noise in datasets.NOIZEUS_NOISES:
        raise ValueError(f"NOIZEUS noise '{noise}' is only available with --dataset noizeus")
    noise_signal = None
    if noise != "white":
        noise_signal, fs = datasets.read_audio(noise)
        if fs != clip.fs:
            raise ValueError(f"{noise} has sample rate {fs}, clip {clip.name} has {clip.fs}")
    # Seed from the case itself so each case gets the same noise on every run.
    rng = np.random.default_rng([seed, zlib.crc32(f"{clip.name}|{noise}|{snr}".encode())])
    return add_noise(clip.clean, snr, rng, noise_signal)


def prepare(args, work):
    """Write clean/noisy wavs, cases.csv and one MATLAB job file per method."""
    clips, noises = load_clips(args)
    for old in work.glob("jobs_*.txt"):
        old.unlink()
    (work / "clean").mkdir(parents=True, exist_ok=True)
    (work / "noisy").mkdir(exist_ok=True)
    cases = []
    for clip in clips:
        sf.write(work / "clean" / f"{clip.name}.wav", clip.clean, clip.fs, subtype="FLOAT")
        for noise in noises:
            for snr in args.snrs:
                noise_name = Path(noise).stem
                case_id = f"{clip.name}_{noise_name}_{snr}dB"
                sf.write(work / "noisy" / f"{case_id}.wav", make_noisy(clip, noise, snr, args.seed),
                         clip.fs, subtype="FLOAT")
                cases.append(dict(id=case_id, clip=clip.name, noise=noise_name, snr_in=snr, fs=clip.fs))
    pd.DataFrame(cases).to_csv(work / "cases.csv", index=False)
    for method in args.methods:
        if method in MATLAB_METHODS:
            lines = [f"noisy/{c['id']}.wav\tdenoised/{method}/{c['id']}.wav" for c in cases]
            (work / f"jobs_{method}.txt").write_text("\n".join(lines) + "\n")
    print(f"Prepared {len(cases)} noisy files from {len(clips)} clips in {work}")


def score(args, work, out):
    """Compare every method's output with the clean clip and write the CSVs."""
    cases = pd.read_csv(work / "cases.csv")
    times = {}
    for method in args.methods:
        tfile = work / f"times_{method}.csv"
        if tfile.exists():
            t = pd.read_csv(tfile)
            times[method] = dict(zip(t["job"].str.split("\t").str[0], t["seconds"]))
    rows = []
    for case in tqdm(cases.itertuples(), total=len(cases), desc="Scoring"):
        clean, fs = sf.read(work / "clean" / f"{case.clip}.wav")
        for method in args.methods:
            path = work / ("noisy" if method == "noisy" else f"denoised/{method}") / f"{case.id}.wav"
            if not path.exists():
                print(f"Missing {path}, skipping")
                continue
            est, _ = sf.read(path)
            row = dict(dataset=args.dataset, clip=case.clip, noise=case.noise, snr_in=case.snr_in,
                       method=method, seconds=times.get(method, {}).get(f"noisy/{case.id}.wav", 0.0))
            row.update(metrics.compute_all(clean, est, fs))
            rows.append(row)
    results = pd.DataFrame(rows)
    results.to_csv(out / "results.csv", index=False)

    cols = ["snr", "segsnr", "pesq", "stoi", "hs_snr", "seconds"]
    summary = results.groupby(["method", "noise", "snr_in"], sort=False)[cols].mean().reset_index()
    summary.to_csv(out / "summary.csv", index=False)
    overall = results.groupby(["snr_in", "method"], sort=False)[cols].mean()
    with pd.option_context("display.float_format", "{:.2f}".format, "display.width", 120):
        print("\nMean over all clips and noises:\n")
        print(overall)
    print(f"\nWrote {out / 'results.csv'} and {out / 'summary.csv'}")


def main():
    args = parse_args()
    out = args.out or REPO / "results" / Path(args.dataset).stem
    work = out / "work"
    if args.stage in ("all", "prepare"):
        prepare(args, work)
    if args.stage == "all" and any(m in MATLAB_METHODS for m in args.methods):
        matlab_bridge.run_batch(work, args.matlab)
    if args.stage in ("all", "score"):
        score(args, work, out)


if __name__ == "__main__":
    main()
