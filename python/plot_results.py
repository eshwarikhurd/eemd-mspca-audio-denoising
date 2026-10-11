"""Figures and a listening page for a finished benchmark run.

Reads results/<dataset>/results.csv and the WAV files in results/<dataset>/work,
and writes PNG figures to results/<dataset>/figures/ plus results/<dataset>/listen.html.

Examples:
    python python/plot_results.py --dataset noizeus
    python python/plot_results.py --dataset flute --examples Flute_audio_white_0dB Flute_audio_white_15dB
    python python/plot_results.py --dataset noizeus --decomposition   # also MATLAB IMF figures
"""

import argparse
import html
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
import numpy as np  # noqa: E402
import pandas as pd  # noqa: E402
import soundfile as sf  # noqa: E402
from matplotlib.colors import LinearSegmentedColormap, TwoSlopeNorm  # noqa: E402
from scipy.signal import stft, welch  # noqa: E402

import matlab_bridge  # noqa: E402

REPO = Path(__file__).resolve().parent.parent

# Colours follow the method, never its rank (validated: CVD-safe as adjacent series).
METHOD_STYLE = {
    "noisy": dict(color="#898781", marker="o", label="Noisy input"),
    "emd_svd": dict(color="#2a78d6", marker="s", label="EMD-SVD"),
    "eemd_mspca": dict(color="#eb6834", marker="D", label="EEMD-MSPCA"),
    "wavelet": dict(color="#1baf7a", marker="^", label="Wavelet"),
    "emd_hurst": dict(color="#eda100", marker="v", label="EMD-Hurst"),
    # Baselines from Peng et al. (2021), drawn dashed.
    "lowpass": dict(color="#e87ba4", marker="P", label="Low-pass", baseline=True),
    "wavelet_mspca": dict(color="#008300", marker="X", label="Wavelet-MSPCA", baseline=True),
    "eemd_svd": dict(color="#4a3aa7", marker="h", label="EEMD-SVD", baseline=True),
}
INK, INK_2, MUTED = "#0b0b0b", "#52514e", "#898781"
GRID, AXIS, SURFACE = "#e1e0d9", "#c3c2b7", "#fcfcfb"
BLUES = ["#cde2fb", "#9ec5f4", "#6da7ec", "#3987e5", "#256abf", "#184f95", "#0d366b"]
SEQ = LinearSegmentedColormap.from_list("seq_blue", [SURFACE] + BLUES)
DIVERGING = LinearSegmentedColormap.from_list(
    "blue_red", ["#e34948", "#f3a3a2", "#f0efec", "#9ec5f4", "#2a78d6"])  # worse <- 0 -> better
METRICS = {"snr": "SNR change (dB)", "pesq": "PESQ change", "stoi": "STOI change"}

plt.rcParams.update({
    "font.family": "sans-serif",
    "font.sans-serif": ["Helvetica Neue", "Helvetica", "Arial", "DejaVu Sans"],
    "font.size": 10,
    "figure.facecolor": SURFACE,
    "axes.facecolor": SURFACE,
    "savefig.facecolor": SURFACE,
    "axes.edgecolor": AXIS,
    "axes.linewidth": 0.8,
    "axes.labelcolor": INK_2,
    "axes.titlecolor": INK,
    "axes.titlesize": 11,
    "axes.titleweight": "bold",
    "axes.spines.top": False,
    "axes.spines.right": False,
    "axes.grid": True,
    "grid.color": GRID,
    "grid.linewidth": 0.8,
    "axes.axisbelow": True,
    "xtick.color": MUTED,
    "ytick.color": MUTED,
    "xtick.labelcolor": INK_2,
    "ytick.labelcolor": INK_2,
    "legend.frameon": False,
    "lines.linewidth": 2,
    "lines.solid_capstyle": "round",
    "lines.solid_joinstyle": "round",
})


def parse_args():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--dataset", default="flute", help="dataset name used for the benchmark run")
    p.add_argument("--out", type=Path, help="benchmark output folder (default: results/<dataset>)")
    p.add_argument("--examples", nargs="+", help="case ids for spectrograms and the listening page "
                   "(default: first clip and noise at the lowest and highest input SNR)")
    p.add_argument("--decomposition", action="store_true",
                   help="also draw the IMF and EEMD-MSPCA step-by-step figures with MATLAB")
    p.add_argument("--matlab", help="path to the matlab executable")
    return p.parse_args()


def methods_in(results):
    return [m for m in METHOD_STYLE if m in set(results.method)]


def with_deltas(results):
    """Add d_<metric> columns: change relative to the noisy input of the same case."""
    key = ["clip", "noise", "snr_in"]
    base = results[results.method == "noisy"][key + list(METRICS)]
    out = results.merge(base, on=key, suffixes=("", "_noisy"))
    for m in METRICS:
        out[f"d_{m}"] = out[m] - out[f"{m}_noisy"]
    return out


def line_style(m):
    return "--" if METHOD_STYLE[m].get("baseline") else "-"


def legend_row(fig, methods):
    handles = [plt.Line2D([], [], color=METHOD_STYLE[m]["color"], marker=METHOD_STYLE[m]["marker"],
                          linestyle=line_style(m), markersize=7, markeredgecolor=SURFACE,
                          markeredgewidth=1.5, label=METHOD_STYLE[m]["label"]) for m in methods]
    fig.legend(handles=handles, loc="upper center", ncol=min(len(handles), 4), bbox_to_anchor=(0.5, 1.0),
               handlelength=2.2, columnspacing=1.6, labelcolor=INK_2)


def plot_metric_vs_snr(d, methods, path, title):
    """Main results figure: change in each metric vs input SNR, one line per method."""
    snrs = sorted(d.snr_in.unique())
    fig, axes = plt.subplots(1, len(METRICS), figsize=(12, 4.2), constrained_layout=True)
    fig.get_layout_engine().set(rect=(0, 0, 1, 0.9))
    for ax, (metric, label) in zip(axes, METRICS.items()):
        ax.axhline(0, color=AXIS, linewidth=1, zorder=1)
        for m in methods:
            if m == "noisy":
                continue
            g = d[d.method == m].groupby("snr_in")[f"d_{metric}"]
            mean, n = g.mean().reindex(snrs), g.count().reindex(snrs)
            half = 1.96 * g.std().reindex(snrs) / np.sqrt(n)
            st = METHOD_STYLE[m]
            if (n > 1).all():
                ax.fill_between(snrs, mean - half, mean + half, color=st["color"], alpha=0.1, linewidth=0)
            ax.plot(snrs, mean, color=st["color"], marker=st["marker"], markersize=7, linestyle=line_style(m),
                    linewidth=1.5 if st.get("baseline") else 2, markeredgecolor=SURFACE,
                    markeredgewidth=1.5, zorder=3)
        ax.set_title(label, loc="left")
        ax.set_xlabel("Input SNR (dB)")
        ax.set_xticks(snrs)
        ax.grid(axis="x", visible=False)
    fig.suptitle(title, x=0.01, y=1.06, ha="left", fontsize=13, fontweight="bold", color=INK)
    legend_row(fig, [m for m in methods if m != "noisy"])
    fig.savefig(path, dpi=200, bbox_inches="tight")
    plt.close(fig)


def plot_distributions(d, methods, path, title):
    """Spread of the per-file change in PESQ and STOI for each method."""
    methods = [m for m in methods if m != "noisy"]
    fig, axes = plt.subplots(1, 2, figsize=(11, 0.6 * len(methods) + 1.6), constrained_layout=True)
    for ax, metric in zip(axes, ["pesq", "stoi"]):
        data = [d[d.method == m][f"d_{metric}"].dropna() for m in methods]
        pos = np.arange(len(methods))[::-1]
        bp = ax.boxplot(data, positions=pos, orientation="horizontal", widths=0.5, patch_artist=True,
                        showfliers=False, medianprops=dict(color=INK, linewidth=1.5),
                        whiskerprops=dict(color=MUTED), capprops=dict(color=MUTED))
        for box, m in zip(bp["boxes"], methods):
            box.set(facecolor=METHOD_STYLE[m]["color"], alpha=0.35, edgecolor=METHOD_STYLE[m]["color"])
        for p, vals, m in zip(pos, data, methods):
            share = (vals > 0).mean()
            ax.annotate(f"{share:.0%} improved", (1.0, p), xycoords=("axes fraction", "data"),
                        xytext=(4, 0), textcoords="offset points", va="center", color=INK_2, fontsize=9)
        ax.axvline(0, color=AXIS, linewidth=1)
        ax.set_yticks(pos, [METHOD_STYLE[m]["label"] for m in methods])
        ax.set_title(METRICS[metric], loc="left")
        ax.grid(axis="y", visible=False)
    fig.suptitle(title, x=0.01, ha="left", fontsize=13, fontweight="bold", color=INK)
    fig.savefig(path, dpi=200, bbox_inches="tight")
    plt.close(fig)


def plot_noise_heatmap(d, methods, path, title, metric="pesq"):
    """Mean change per noise type x method (diverging around 'no change')."""
    methods = [m for m in methods if m != "noisy"]
    table = d[d.method.isin(methods)].pivot_table(index="noise", columns="method", values=f"d_{metric}")
    table = table[methods]
    lim = np.nanmax(np.abs(table.values))
    fig, ax = plt.subplots(figsize=(1.5 * len(methods) + 2.5, 0.45 * len(table) + 1.6), constrained_layout=True)
    im = ax.imshow(table.values, cmap=DIVERGING, norm=TwoSlopeNorm(0, -lim, lim), aspect="auto")
    for (i, j), v in np.ndenumerate(table.values):
        rgb = np.array(im.cmap(im.norm(v))[:3])
        ink = "white" if rgb @ [0.299, 0.587, 0.114] < 0.55 else INK
        ax.text(j, i, f"{v:+.2f}", ha="center", va="center", color=ink, fontsize=9)
    ax.set_xticks(range(len(methods)), [METHOD_STYLE[m]["label"] for m in methods])
    ax.set_yticks(range(len(table)), table.index)
    ax.tick_params(length=0)
    ax.grid(False)
    for s in ax.spines.values():
        s.set_visible(False)
    cb = fig.colorbar(im, ax=ax, shrink=0.8)
    cb.outline.set_visible(False)
    cb.set_label(f"Mean {METRICS[metric]} (red = worse, blue = better)", color=INK_2)
    ax.set_title(title, loc="left")
    fig.savefig(path, dpi=200, bbox_inches="tight")
    plt.close(fig)


def load_case(work, case_id, clip, methods):
    clean, fs = sf.read(work / "clean" / f"{clip}.wav")
    signals = {"clean": clean}
    for m in methods:
        p = work / ("noisy" if m == "noisy" else f"denoised/{m}") / f"{case_id}.wav"
        if p.exists():
            signals[m] = sf.read(p)[0][: len(clean)]
    return signals, fs


def _stft_db(x, fs):
    nper = int(2 ** np.ceil(np.log2(0.032 * fs)))  # ~32 ms frames
    f, t, z = stft(x, fs, nperseg=nper, noverlap=3 * nper // 4, boundary=None, padded=False)
    return f, t, z


def plot_spectrograms(signals, fs, path, title):
    """Each version's spectrogram (shared dB scale) and its error against the clean signal."""
    names = list(signals)
    f, t, zc = _stft_db(signals["clean"], fs)
    specs = {n: _stft_db(x, fs)[2] for n, x in signals.items()}
    db = {n: 20 * np.log10(np.abs(z) + 1e-10) for n, z in specs.items()}
    vmax = max(v.max() for v in db.values())
    vmin = vmax - 70
    fig, axes = plt.subplots(len(names), 2, figsize=(12, 1.7 * len(names) + 0.8), sharex=True, sharey=True,
                             constrained_layout=True)
    fmax = min(fs / 2, 8000)
    for row, n in enumerate(names):
        label = "Clean" if n == "clean" else METHOD_STYLE[n]["label"]
        a, b = axes[row]
        im = a.pcolormesh(t, f, db[n], cmap=SEQ, vmin=vmin, vmax=vmax, shading="auto", rasterized=True)
        a.set_ylabel(label, color=INK, fontweight="bold")
        if n != "clean":
            err = 20 * np.log10(np.abs(specs[n] - zc) + 1e-10)
            im2 = b.pcolormesh(t, f, err, cmap=SEQ, vmin=vmin, vmax=vmax, shading="auto", rasterized=True)
        else:
            b.text(0.5, 0.5, "reference", transform=b.transAxes, ha="center", va="center", color=MUTED)
        for ax in (a, b):
            ax.set_ylim(0, fmax)
            ax.grid(False)
            ax.yaxis.set_major_formatter(matplotlib.ticker.FuncFormatter(lambda v, _: f"{v / 1000:g}k"))
    axes[0, 0].set_title("Spectrogram", loc="left")
    axes[0, 1].set_title("Error vs clean (|STFT(x) − STFT(clean)|)", loc="left")
    axes[-1, 0].set_xlabel("Time (s)")
    axes[-1, 1].set_xlabel("Time (s)")
    cb = fig.colorbar(im, ax=axes, shrink=0.5, location="right")
    cb.outline.set_visible(False)
    cb.set_label("dB", color=INK_2)
    fig.suptitle(title, x=0.01, ha="left", fontsize=13, fontweight="bold", color=INK)
    fig.savefig(path, dpi=150, bbox_inches="tight")
    plt.close(fig)


def plot_psd(signals, fs, path, title):
    """Welch PSD of every version on one log-frequency axis."""
    fig, ax = plt.subplots(figsize=(10, 4.5), constrained_layout=True)
    nper = min(2048, len(signals["clean"]))
    for n, x in signals.items():
        f, p = welch(x, fs, nperseg=nper)
        if n == "clean":
            ax.plot(f[1:], 10 * np.log10(p[1:]), color=INK, linewidth=1.5, label="Clean", zorder=4)
        else:
            st = METHOD_STYLE[n]
            ax.plot(f[1:], 10 * np.log10(p[1:]), color=st["color"], linewidth=1.5 if n != "noisy" else 1.2,
                    linestyle=line_style(n), label=st["label"], zorder=2 if n == "noisy" else 3)
    ax.set_xscale("log")
    ax.set_xlim(50, fs / 2)
    ax.set_xlabel("Frequency (Hz)")
    ax.set_ylabel("PSD (dB/Hz)")
    ax.legend(loc="lower left", ncol=3, labelcolor=INK_2)
    ax.set_title(title, loc="left")
    fig.savefig(path, dpi=200, bbox_inches="tight")
    plt.close(fig)


def write_listening_page(out, examples, results, methods):
    """listen.html: audio players and spectrograms for each example."""
    listen = out / "listen"
    listen.mkdir(exist_ok=True)
    work = out / "work"
    sections = []
    for case_id, clip, noise, snr in examples:
        signals, fs = load_case(work, case_id, clip, methods)
        peak = max(np.max(np.abs(x)) for x in signals.values())  # one gain keeps relative loudness
        rows = []
        for n, x in signals.items():
            wav = listen / f"{case_id}_{n}.wav"
            sf.write(wav, x / peak * 0.9, fs, subtype="PCM_16")
            label = "Clean" if n == "clean" else METHOD_STYLE[n]["label"]
            r = results[(results["clip"] == clip) & (results.noise == noise) & (results.snr_in == snr)
                        & (results.method == n)]
            cells = "".join(f"<td>{r.iloc[0][k]:.2f}</td>" if len(r) else "<td>–</td>"
                            for k in ("snr", "pesq", "stoi"))
            swatch = METHOD_STYLE[n]["color"] if n in METHOD_STYLE else INK
            rows.append(f'<tr><th><span class="sw" style="background:{swatch}"></span>{html.escape(label)}</th>'
                        f'<td><audio controls preload="none" src="listen/{wav.name}"></audio></td>{cells}</tr>')
        sections.append(f"""
<section>
  <h2>{html.escape(clip)} · {html.escape(noise)} · {snr} dB input</h2>
  <table>
    <thead><tr><th>Version</th><th>Audio</th><th>SNR (dB)</th><th>PESQ</th><th>STOI</th></tr></thead>
    <tbody>{''.join(rows)}</tbody>
  </table>
  <img src="figures/spectrogram_{case_id}.png" alt="Spectrograms of every version of {html.escape(case_id)}">
</section>""")
    page = f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Denoising listening test</title>
<style>
:root {{ --surface:#fcfcfb; --page:#f9f9f7; --ink:#0b0b0b; --ink2:#52514e; --muted:#898781; --rule:#e1e0d9; }}
@media (prefers-color-scheme: dark) {{
  :root {{ --surface:#1a1a19; --page:#0d0d0d; --ink:#ffffff; --ink2:#c3c2b7; --muted:#898781; --rule:#2c2c2a; }}
}}
body {{ margin:0; background:var(--page); color:var(--ink); font:15px/1.5 system-ui,-apple-system,"Segoe UI",sans-serif; }}
main {{ max-width:1000px; margin:0 auto; padding:24px 16px 64px; }}
h1 {{ font-size:24px; margin:0 0 4px; }} p.sub {{ color:var(--ink2); margin:0 0 24px; }}
section {{ background:var(--surface); border:1px solid var(--rule); border-radius:12px; padding:16px; margin:0 0 24px; }}
h2 {{ font-size:17px; margin:0 0 12px; }}
table {{ width:100%; border-collapse:collapse; font-variant-numeric:tabular-nums; }}
th, td {{ text-align:left; padding:6px 8px; border-bottom:1px solid var(--rule); }}
thead th {{ color:var(--muted); font-weight:500; font-size:13px; }}
td:nth-child(n+3) {{ text-align:right; }} audio {{ width:100%; min-width:180px; height:32px; }}
.sw {{ display:inline-block; width:10px; height:10px; border-radius:50%; margin-right:8px; }}
img {{ width:100%; margin-top:16px; border-radius:8px; background:#fcfcfb; }}
.scroll {{ overflow-x:auto; }}
</style></head>
<body><main>
<h1>Denoising listening test</h1>
<p class="sub">Every version of a clip is played at the same gain, so loudness differences are real. Metrics compare each version with the clean clip.</p>
{''.join(sections)}
</main></body></html>"""
    (out / "listen.html").write_text(page)


def default_examples(results):
    first = results.iloc[0]
    rows = results[(results["clip"] == first["clip"]) & (results.noise == first.noise)]
    snrs = sorted(rows.snr_in.unique())
    return [f"{first["clip"]}_{first.noise}_{s}dB" for s in sorted({snrs[0], snrs[-1]})]


def main():
    args = parse_args()
    out = args.out or REPO / "results" / Path(args.dataset).stem
    figs = out / "figures"
    figs.mkdir(parents=True, exist_ok=True)
    results = pd.read_csv(out / "results.csv")
    methods = methods_in(results)
    d = with_deltas(results)
    n_files = d[["clip", "noise", "snr_in"]].drop_duplicates().shape[0]
    name = args.dataset

    per_snr = n_files // d.snr_in.nunique()
    spread = ", mean ± 95% CI" if per_snr > 1 else ""
    plot_metric_vs_snr(d, methods, figs / "metric_vs_snr.png",
                       f"{name}: change vs the noisy input ({per_snr} files per input SNR{spread})")
    plot_distributions(d, methods, figs / "distributions.png", f"{name}: per-file change vs the noisy input")
    if d.noise.nunique() > 1:
        plot_noise_heatmap(d, methods, figs / "noise_heatmap_pesq.png", f"{name}: mean PESQ change by noise type")

    cases = d.assign(case_id=d["clip"] + "_" + d.noise + "_" + d.snr_in.astype(str) + "dB")
    lookup = cases.drop_duplicates("case_id").set_index("case_id")
    examples = []
    for case_id in args.examples or default_examples(results):
        if case_id not in lookup.index:
            raise SystemExit(f"Unknown example {case_id}. Example ids look like {lookup.index[0]}")
        row = lookup.loc[case_id]
        examples.append((case_id, row["clip"], row.noise, int(row.snr_in)))
        signals, fs = load_case(out / "work", case_id, row["clip"], methods)
        plot_spectrograms(signals, fs, figs / f"spectrogram_{case_id}.png", f"{case_id}")
        plot_psd(signals, fs, figs / f"psd_{case_id}.png", f"{case_id}: power spectral density")
        if args.decomposition:
            noisy = (out / "work" / "noisy" / f"{case_id}.wav").resolve()
            clean = (out / "work" / "clean" / f"{row['clip']}.wav").resolve()
            matlab_bridge.run_command(
                f"plot_decomposition('{noisy}', '{(figs / f'decomposition_{case_id}.png').resolve()}'); "
                f"plot_eemd_mspca('{noisy}', '{(figs / f'eemd_mspca_{case_id}.png').resolve()}', '{clean}')",
                args.matlab)
    write_listening_page(out, examples, results, methods)
    print(f"Wrote figures to {figs} and {out / 'listen.html'}")


if __name__ == "__main__":
    main()
