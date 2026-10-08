"""Parameter sweep: tune every method on some NOIZEUS sentences, report on the others.

Stage "tune": every setting in GRID runs on the tuning set (sentences 1-10, four noises, all
SNRs). For each method the setting with the best mean PESQ change is kept (results/sweep/best.json).

Stage "eval": the tuned settings run on the held-out sentences (11-30, all eight noises) and
are compared with the default settings on the same files, taken from the full benchmark run
(results/noizeus/results.csv, so run `run_benchmark.py --dataset noizeus` first).

    python python/run_sweep.py                 # tune, then eval
    python python/run_sweep.py --stage eval    # reuse best.json
"""

import argparse
import itertools
import json
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

import pandas as pd
import soundfile as sf

import datasets
import matlab_bridge
import metrics

REPO = Path(__file__).resolve().parent.parent
OUT = REPO / "results" / "sweep"

# Values to try per method. The paper defaults are always included.
GRID = {
    "emd_svd": dict(n_iter=[1, 5], n_imfs=[6, 99], thr=[0.3, 0.6, 1.0], smooth=[1, 5]),
    "eemd_mspca": dict(n_ensemble=[25], t_scale=[0, 0.25, 0.5, 1], energy=[0.85, 0.95, 0.99]),
    "wavelet": dict(level=[3, 5], sorh=["s", "h"], rule=["sqtwolog", "minimaxi"], scal=["mln", "sln"]),
    "emd_hurst": dict(threshold=[0.3, 0.5, 0.7]),
    "lowpass": dict(wn=[0.25, 0.5, 0.75]),
    "wavelet_mspca": dict(L=[4, 10, 32], level=[3, 5]),
    "eemd_svd": dict(n_ensemble=[25], L=[10, 20], thr=[0.6, 1.0, 2.0]),
}
TUNE_CLIPS, EVAL_CLIPS = range(0, 10), range(10, 30)
TUNE_NOISES = ["babble", "car", "street", "train"]
SNRS = [0, 5, 10, 15]


def variant_name(method, options):
    if not options:
        return method
    return method + "@" + ",".join(f"{k}={v}" for k, v in options.items())


def grid_variants(method):
    keys = list(GRID[method])
    for values in itertools.product(*(GRID[method][k] for k in keys)):
        yield variant_name(method, dict(zip(keys, values)))


def prepare(work, clip_range, noises, variants):
    """Write clean and noisy WAVs for the chosen sentences plus one job file per variant."""
    clips = datasets.load_noizeus(REPO / "data" / "noizeus", noises, SNRS)
    clips = [clips[i] for i in clip_range]
    (work / "clean").mkdir(parents=True, exist_ok=True)
    (work / "noisy").mkdir(exist_ok=True)
    for old in work.glob("jobs_*.txt"):
        old.unlink()
    cases = []
    for clip in clips:
        sf.write(work / "clean" / f"{clip.name}.wav", clip.clean, clip.fs, subtype="FLOAT")
        for (noise, snr), noisy in clip.noisy.items():
            case_id = f"{clip.name}_{noise}_{snr}dB"
            sf.write(work / "noisy" / f"{case_id}.wav", noisy, clip.fs, subtype="FLOAT")
            cases.append(dict(id=case_id, clip=clip.name, noise=noise, snr_in=snr))
    for v in variants:
        if not (work / "denoised" / v).is_dir() or len(list((work / "denoised" / v).glob("*.wav"))) < len(cases):
            lines = [f"noisy/{c['id']}.wav\tdenoised/{v}/{c['id']}.wav" for c in cases]
            (work / f"jobs_{v}.txt").write_text("\n".join(lines) + "\n")
    pd.DataFrame(cases).to_csv(work / "cases.csv", index=False)
    print(f"{len(cases)} files, {len(variants)} settings, "
          f"{len(list(work.glob('jobs_*.txt')))} still to run, in {work}")
    return cases


def _score_case(args):
    work, case, variants = args
    clean, fs = sf.read(work / "clean" / f"{case['clip']}.wav")
    rows = []
    for v in ["noisy"] + variants:
        path = work / ("noisy" if v == "noisy" else f"denoised/{v}") / f"{case['id']}.wav"
        est, _ = sf.read(path)
        pesq_score, _ = metrics.pesq(clean, est, fs)
        rows.append(dict(case, variant=v, method=v.split("@")[0], snr=metrics.snr(clean, est),
                         pesq=pesq_score, stoi=metrics.stoi(clean, est, fs)))
    return rows


def score(work, cases, variants):
    """SNR, PESQ and STOI of every variant, plus the change relative to the noisy input."""
    jobs = [(work, c, variants) for c in cases]
    with ProcessPoolExecutor() as pool:
        rows = [r for chunk in pool.map(_score_case, jobs, chunksize=8) for r in chunk]
    df = pd.DataFrame(rows)
    base = df[df.variant == "noisy"].set_index("id")
    for m in ("snr", "pesq", "stoi"):
        df[f"d_{m}"] = df[m] - df["id"].map(base[m])
    return df[df.variant != "noisy"]


def tune(matlab):
    work = OUT / "tune"
    variants = [v for m in GRID for v in grid_variants(m)]
    cases = prepare(work, TUNE_CLIPS, TUNE_NOISES, variants)
    if list(work.glob("jobs_*.txt")):
        matlab_bridge.run_batch(work, matlab)
    df = score(work, cases, variants)
    df.to_csv(OUT / "tune_results.csv", index=False)
    table = df.groupby(["method", "variant"])[["d_snr", "d_pesq", "d_stoi"]].mean().reset_index()
    table.to_csv(OUT / "tune_summary.csv", index=False)
    best = table.loc[table.groupby("method").d_pesq.idxmax()].set_index("method")
    with pd.option_context("display.width", 160, "display.max_colwidth", 80, "display.float_format", "{:+.3f}".format):
        print("\nBest setting per method on the tuning set (by mean PESQ change):\n")
        print(best)
    (OUT / "best.json").write_text(json.dumps(best.variant.to_dict(), indent=2))


def evaluate(matlab):
    work = OUT / "eval"
    best = json.loads((OUT / "best.json").read_text())
    variants = list(best.values())
    cases = prepare(work, EVAL_CLIPS, datasets.NOIZEUS_NOISES, variants)
    if list(work.glob("jobs_*.txt")):
        matlab_bridge.run_batch(work, matlab)
    tuned = score(work, cases, variants).assign(setting="tuned")

    # Defaults on the same held-out files, from the full benchmark run.
    full = pd.read_csv(REPO / "results" / "noizeus" / "results.csv")
    full = full[full["clip"].isin({c["clip"] for c in cases})]
    key = ["clip", "noise", "snr_in"]
    base = full[full.method == "noisy"][key + ["snr", "pesq", "stoi"]]
    default = full[full.method.isin(best)].merge(base, on=key, suffixes=("", "_noisy"))
    for m in ("snr", "pesq", "stoi"):
        default[f"d_{m}"] = default[m] - default[f"{m}_noisy"]
    default = default.assign(setting="default", variant=default.method)

    cols = ["clip", "noise", "snr_in", "method", "variant", "setting", "snr", "pesq", "stoi",
            "d_snr", "d_pesq", "d_stoi"]
    df = pd.concat([default[cols], tuned[cols]], ignore_index=True)
    df.to_csv(OUT / "eval_results.csv", index=False)
    summary = df.groupby(["method", "setting", "snr_in"])[["d_snr", "d_pesq", "d_stoi"]].mean().reset_index()
    summary.to_csv(OUT / "eval_summary.csv", index=False)
    overall = df.groupby(["method", "setting"])[["d_snr", "d_pesq", "d_stoi"]].mean().unstack("setting")
    with pd.option_context("display.width", 160, "display.float_format", "{:+.3f}".format):
        print("\nHeld-out sentences 11-30, mean change vs the noisy input:\n")
        print(overall)
        print("\nTuned settings:")
        for m, v in best.items():
            print(f"  {m}: {v}")
    plot_default_vs_tuned(df, OUT / "default_vs_tuned.png")
    print(f"\nWrote {OUT / 'eval_results.csv'}, {OUT / 'eval_summary.csv'} and {OUT / 'default_vs_tuned.png'}")


def plot_default_vs_tuned(df, path):
    """Dumbbell per method: default (hollow) -> tuned (filled), mean over held-out files."""
    import matplotlib.pyplot as plt
    from plot_results import AXIS, INK_2, METHOD_STYLE, SURFACE

    means = df.groupby(["method", "setting"])[["d_snr", "d_pesq", "d_stoi"]].mean()
    methods = [m for m in METHOD_STYLE if m in means.index.get_level_values(0)]
    labels = {"d_snr": "SNR change (dB)", "d_pesq": "PESQ change", "d_stoi": "STOI change"}
    fig, axes = plt.subplots(1, 3, figsize=(13, 0.5 * len(methods) + 1.8), sharey=True, constrained_layout=True)
    for ax, metric in zip(axes, labels):
        ax.axvline(0, color=AXIS, linewidth=1)
        for y, m in enumerate(reversed(methods)):
            st = METHOD_STYLE[m]
            a, b = means.loc[(m, "default"), metric], means.loc[(m, "tuned"), metric]
            ax.plot([a, b], [y, y], color=st["color"], linewidth=2, alpha=0.5, zorder=2)
            ax.plot(a, y, "o", markersize=8, markerfacecolor=SURFACE, markeredgecolor=st["color"],
                    markeredgewidth=2, zorder=3)
            ax.plot(b, y, "o", markersize=8, color=st["color"], markeredgecolor=SURFACE, markeredgewidth=1.5,
                    zorder=4)
        ax.set_title(labels[metric], loc="left")
        ax.set_yticks(range(len(methods)), [METHOD_STYLE[m]["label"] for m in reversed(methods)])
        ax.grid(axis="y", visible=False)
    handles = [plt.Line2D([], [], linestyle="", marker="o", markersize=8, markerfacecolor=SURFACE,
                          markeredgecolor=INK_2, markeredgewidth=2, label="default settings"),
               plt.Line2D([], [], linestyle="", marker="o", markersize=8, color=INK_2, label="tuned settings")]
    fig.legend(handles=handles, loc="upper right", ncol=2, bbox_to_anchor=(1, 1.08), labelcolor=INK_2)
    fig.suptitle("NOIZEUS held-out sentences 11-30: default vs tuned settings (mean change vs noisy input)",
                 x=0.01, y=1.08, ha="left", fontsize=13, fontweight="bold")
    fig.savefig(path, dpi=200, bbox_inches="tight")
    plt.close(fig)


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--stage", choices=("all", "tune", "eval"), default="all")
    p.add_argument("--matlab", help="path to the matlab executable")
    args = p.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    if args.stage in ("all", "tune"):
        tune(args.matlab)
    if args.stage in ("all", "eval"):
        evaluate(args.matlab)


if __name__ == "__main__":
    main()
