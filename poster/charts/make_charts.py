"""Poster charts for the Graption demo.

Numbers come from ml/tone/DISCUSSION_LOG.md (A4.1 team clips, A7 CREMA-D threshold
tuning) and docs/GRAPTION_CONTEXT.md (feature spec, latency target). Run from the
repo root:  uv run python poster/charts/make_charts.py
Writes PNG (300 dpi) and SVG next to this file.
"""

from pathlib import Path

import matplotlib.pyplot as plt
from matplotlib.lines import Line2D
from matplotlib.patches import FancyBboxPatch, Rectangle

OUT = Path(__file__).parent

# Poster surface and ink (cream paper, Graption pine text).
SURFACE = "#FBF6F0"
INK = "#1D3A3A"
INK_2 = "#52514e"
GRID = "#E4DDD3"

# Tone tags: validated all-pairs on SURFACE (validate_palette.js, CVD dE >= 15).
# Yellow is < 3:1 on cream, so every use carries a direct label or marker shape.
TONE = {"calm": "#2a78d6", "excited": "#eda100", "upset": "#e34948", "none": "#8a8780"}
SHAPE = {"calm": "o", "excited": "^", "upset": "s", "none": "D"}
SERIES_1, SERIES_2 = "#2a78d6", "#eb6834"  # two-series charts (validated pair)
BLOCKS = ["#2a78d6", "#eb6834", "#1baf7a", "#eda100"]  # adjacent-order slots 1-4

plt.rcParams.update({
    "font.family": ["Helvetica Neue", "Helvetica", "Arial", "DejaVu Sans"],
    "font.size": 15,
    "axes.edgecolor": GRID,
    "axes.labelcolor": INK_2,
    "axes.titlecolor": INK,
    "xtick.color": INK_2,
    "ytick.color": INK_2,
    "axes.spines.top": False,
    "axes.spines.right": False,
    "figure.facecolor": SURFACE,
    "axes.facecolor": SURFACE,
    "savefig.facecolor": SURFACE,
})


def titled(fig, title, subtitle):
    fig.text(0.04, 0.955, title, fontsize=22, fontweight="bold", color=INK, va="top")
    fig.text(0.04, 0.885, subtitle, fontsize=14, color=INK_2, va="top")


def source(fig, text):
    fig.text(0.04, 0.025, text, fontsize=11, color=INK_2)


def save(fig, name):
    for ext in ("png", "svg"):
        fig.savefig(OUT / f"{name}.{ext}", dpi=300, facecolor=fig.get_facecolor())
    plt.close(fig)


# A4.1 team recordings: (intended label, arousal, valence, latency ms).
TEAM_CLIPS = [
    ("calm", 0.44277, 0.5856, 615.97), ("calm", 0.4733, 0.50756, 591.44),
    ("calm", 0.45869, 0.57254, 594.74), ("calm", 0.41518, 0.43334, 571.06),
    ("calm", 0.35808, 0.54589, 580.81), ("calm", 0.3088, 0.44497, 602.81),
    ("calm", 0.38408, 0.52823, 705.92), ("calm", 0.39295, 0.56352, 760.07),
    ("excited", 0.81619, 0.81739, 657.09), ("excited", 0.69894, 0.47741, 542.05),
    ("excited", 0.6892, 0.62782, 568.57), ("excited", 0.47862, 0.4807, 751.27),
    ("excited", 0.58893, 0.20495, 692.40), ("excited", 0.66858, 0.7723, 634.54),
    ("excited", 0.64938, 0.6641, 847.48), ("excited", 0.70393, 0.66788, 844.04),
    ("none", 0.29238, 0.47676, 530.15), ("none", 0.41863, 0.54257, 451.10),
    ("none", 0.35345, 0.40732, 482.44), ("none", 0.36106, 0.49524, 748.29),
    ("upset", 0.61186, 0.21576, 604.95), ("upset", 0.63486, 0.28663, 717.67),
    ("upset", 0.5545, 0.23688, 889.41), ("upset", 0.56496, 0.33733, 524.23),
    ("upset", 0.47301, 0.29636, 705.46), ("upset", 0.54898, 0.61797, 743.28),
    ("upset", 0.37828, 0.47705, 778.24), ("upset", 0.48402, 0.34614, 605.34),
]


def chart_tone_zones():
    fig = plt.figure(figsize=(11, 8.5))
    ax = fig.add_axes([0.1, 0.12, 0.62, 0.68])
    lo, hi = 0.15, 0.9
    zones = [  # (tag, x0, y0, x1, y1) from AudeeringThresholds
        ("excited", 0.64, 0.45, hi, hi),
        ("upset", 0.47, lo, hi, 0.40),
        ("calm", 0.38, 0.45, 0.48, hi),
    ]
    for tag, x0, y0, x1, y1 in zones:
        ax.add_patch(Rectangle((x0, y0), x1 - x0, y1 - y0, facecolor=TONE[tag],
                               alpha=0.12, edgecolor=TONE[tag], lw=1.5, ls="--"))
        ax.text(x1 - 0.01, y1 - 0.015, f"{tag} zone", ha="right", va="top",
                fontsize=13, color=INK, fontweight="bold")
    for tag in ("calm", "excited", "upset", "none"):
        pts = [(a, v) for lbl, a, v, _ in TEAM_CLIPS if lbl == tag]
        ax.scatter([p[0] for p in pts], [p[1] for p in pts], s=120, marker=SHAPE[tag],
                   color=TONE[tag], edgecolors=SURFACE, linewidths=2, zorder=3)
    ax.set_xlim(lo, hi)
    ax.set_ylim(lo, hi)
    ax.set_xlabel("Arousal (energy)")
    ax.set_ylabel("Valence (positive ↔ negative)")
    ax.grid(color=GRID, lw=0.8)
    ax.set_axisbelow(True)
    handles = [Line2D([], [], marker=SHAPE[t], ls="", markersize=12, color=TONE[t],
                      markeredgecolor=SURFACE, label=f"{t} (n={sum(c[0] == t for c in TEAM_CLIPS)})")
               for t in ("calm", "excited", "upset", "none")]
    fig.legend(handles=handles, title="What the speaker meant", loc="upper left",
               bbox_to_anchor=(0.74, 0.8), frameon=False, title_fontsize=14, labelcolor=INK)
    fig.text(0.74, 0.45, "Shaded zones are the\ntuned thresholds the\nbaseline uses to tag.\n\n"
             "A clip outside every\nzone gets no tag.", fontsize=13, color=INK_2, va="top")
    titled(fig, "Tone baseline on our own voices",
           "audEERING arousal and valence for 28 team clips (3 speakers), with the tag zones")
    source(fig, "Source: ml/tone/DISCUSSION_LOG.md, A4.1 run. Model: audeering/wav2vec2-large-robust-12-ft-emotion-msp-dim")
    save(fig, "1_tone_zones_team_clips")


def chart_team_accuracy():
    rows = [("excited", 6, 8), ("upset", 6, 8), ("calm", 5, 8), ("no tag", 3, 4)]
    fig = plt.figure(figsize=(11, 6.5))
    ax = fig.add_axes([0.16, 0.15, 0.7, 0.62])
    y = range(len(rows))[::-1]
    for yi, (name, ok, n) in zip(y, rows):
        color = TONE["none" if name == "no tag" else name]
        ax.barh(yi, n, height=0.55, color=GRID)
        ax.barh(yi, ok, height=0.55, color=color)
        ax.text(n + 0.15, yi, f"{ok}/{n}  ({ok / n:.0%})", va="center", fontsize=15, color=INK)
    ax.set_yticks(list(y), [r[0] for r in rows], fontsize=16, color=INK)
    ax.set_xlim(0, 10)
    ax.set_xticks([0, 2, 4, 6, 8])
    ax.set_xlabel("Clips tagged correctly (gray = total clips)")
    ax.spines["left"].set_visible(False)
    ax.tick_params(axis="y", length=0)
    titled(fig, "20 of 28 team clips tagged correctly (71%)",
           "audEERING baseline with tuned thresholds, judged against what the speaker intended")
    source(fig, "Source: ml/tone/DISCUSSION_LOG.md, A4.1 run, 3 speakers")
    save(fig, "2_team_clip_accuracy")


def chart_generalization():
    tags = ["excited", "upset"]
    tuning = [81.8, 80.0]
    held = [61.5, 63.0]
    fig = plt.figure(figsize=(11, 7))
    ax = fig.add_axes([0.1, 0.13, 0.62, 0.64])
    w = 0.34
    for i, tag in enumerate(tags):
        for dx, val, col in ((-w / 2 - 0.01, tuning[i], SERIES_1), (w / 2 + 0.01, held[i], SERIES_2)):
            ax.add_patch(FancyBboxPatch((i + dx - w / 2, 0), w, val, boxstyle="round,pad=0,rounding_size=0.02",
                                        mutation_aspect=40, color=col, lw=0))
            ax.text(i + dx, val + 1.5, f"{val:.1f}%", ha="center", fontsize=15, color=INK, fontweight="bold")
    ax.axhline(80, color=INK, ls="--", lw=1.5)
    ax.text(1.58, 78, "80% target", ha="right", va="top", fontsize=13, color=INK)
    ax.set_xlim(-0.6, 1.6)
    ax.set_ylim(0, 100)
    ax.set_xticks([0, 1], tags, fontsize=16, color=INK)
    ax.set_ylabel("Precision (tag was right)")
    ax.yaxis.set_major_formatter(lambda v, _: f"{v:.0f}%")
    ax.grid(axis="y", color=GRID, lw=0.8)
    ax.set_axisbelow(True)
    ax.tick_params(axis="x", length=0)
    handles = [Rectangle((0, 0), 1, 1, color=SERIES_1, label="Tuning speakers (150 clips)"),
               Rectangle((0, 0), 1, 1, color=SERIES_2, label="New speakers (150 clips)")]
    fig.legend(handles=handles, loc="upper left", bbox_to_anchor=(0.73, 0.79), frameon=False,
               labelcolor=INK, fontsize=13, handlelength=1.2)
    fig.text(0.74, 0.5, "Thresholds tuned on one\ngroup of actors lose\n17–20 points on actors\n"
             "they have never heard.\n\nCalm: 0 of 6 calm tags\nwere right, so calm is\nwithheld.",
             fontsize=13, color=INK_2, va="top")
    titled(fig, "Hand-tuned tone thresholds don't generalize",
           "CREMA-D, 300 clips, split by actor (85 actors): precision before and after switching speakers")
    source(fig, "Source: ml/tone/DISCUSSION_LOG.md, A7. Next: a custom WavLM tone model (in progress)")
    save(fig, "3_threshold_generalization")


def chart_coverage():
    parts = [("untagged", 69.3, TONE["none"]), ("upset", 18.0, TONE["upset"]),
             ("excited", 8.7, TONE["excited"]), ("calm", 4.0, TONE["calm"])]
    fig = plt.figure(figsize=(11, 4.6))
    ax = fig.add_axes([0.04, 0.13, 0.92, 0.6])
    left = 0
    rows = iter([-0.85, -1.4])
    for name, pct, col in parts:
        ax.barh(0, pct - 0.4, left=left + 0.2, height=1, color=col)
        mid = left + pct / 2
        if pct > 15:
            ax.text(mid, 0, f"{name}\n{pct:.1f}%", ha="center", va="center", fontsize=15,
                    color="white", fontweight="bold")
        else:
            row = next(rows)
            ax.plot([mid, mid], [-0.52, row], color=INK_2, lw=1)
            ax.text(mid - 0.6, row, f"{name} {pct:.1f}%", ha="right", va="center", fontsize=14, color=INK)
        left += pct
    ax.set_xlim(0, 100)
    ax.set_ylim(-1.6, 0.55)
    ax.axis("off")
    titled(fig, "Most speech gets no tag, on purpose",
           "Share of held-out CREMA-D clips that received each tag (150 clips, new speakers)")
    source(fig, "Source: ml/tone/DISCUSSION_LOG.md, A7 tuned thresholds. A wrong tone tag is worse than none.")
    save(fig, "4_tag_coverage")


def chart_latency():
    lat = sorted(c[3] for c in TEAM_CLIPS)
    mean = sum(lat) / len(lat)
    fig = plt.figure(figsize=(11, 5))
    ax = fig.add_axes([0.06, 0.24, 0.9, 0.45])
    # Beeswarm-lite: stack dots that fall in the same 25 ms bin.
    bins = {}
    for v in lat:
        b = int(v // 25)
        k = bins.get(b, 0)
        bins[b] = k + 1
        ax.scatter(v, k, s=130, color=SERIES_1, edgecolors=SURFACE, linewidths=2, zorder=3)
    ax.axvline(700, color=INK, ls="--", lw=1.5)
    ax.text(705, 3.6, "0.7 s target\n(tone tag after caption)", fontsize=13, color=INK, va="top")
    ax.axvline(mean, color=SERIES_1, lw=2, zorder=1)
    ax.text(mean - 5, 3.6, f"mean {mean:.0f} ms", fontsize=13, color=INK, ha="right", va="top")
    ax.set_xlim(420, 920)
    ax.set_ylim(-0.7, 4)
    ax.set_yticks([])
    ax.spines["left"].set_visible(False)
    ax.set_xlabel("Tone inference time per sentence (ms), one dot per clip")
    titled(fig, f"Tone inference takes about {mean / 1000:.2f} s per sentence",
           f"28 clips, range {lat[0]:.0f}–{lat[-1]:.0f} ms. Captions never wait for tone.")
    source(fig, "Source: ml/tone/DISCUSSION_LOG.md, A4.1. Inference only, on a team Mac; network time not included.")
    save(fig, "5_tone_latency")


def chart_feature_vector():
    blocks = [("Lip landmarks", 80, "40 points × (x, y), nose-centered,\nscaled by eye distance"),
              ("Mouth shapes", 12, "jawOpen, pucker, funnel, …"),
              ("Head pose", 3, "yaw, pitch, roll"),
              ("Loudness", 1, "mic level vs. room")]
    fig = plt.figure(figsize=(13, 5.2))
    ax = fig.add_axes([0.04, 0.2, 0.92, 0.5])
    left = 0
    label_x = [0.0, 0.0, 0.0, 0.0]
    for i, (name, n, _) in enumerate(blocks):
        ax.barh(0, n - 0.4, left=left + 0.2, height=1, color=BLOCKS[i])
        label_x[i] = left + n / 2
        left += n
    ax.text(40, 0, "80 lip values", ha="center", va="center", color="white", fontsize=16, fontweight="bold")
    ax.set_xlim(0, 96)
    ax.set_ylim(-2.3, 0.5)
    ax.axis("off")
    positions = [20, 56, 74, 90]
    for i, (name, n, desc) in enumerate(blocks):
        tx = positions[i]
        ax.annotate("", (label_x[i], -0.5), (tx, -1.05),
                    arrowprops=dict(arrowstyle="-", color=INK_2, lw=1))
        ax.text(tx, -1.15, f"{name} ({n})", ha="center", va="top", fontsize=15, color=INK, fontweight="bold")
        ax.text(tx, -1.5, desc, ha="center", va="top", fontsize=12, color=INK_2)
    titled(fig, "Each face becomes 96 numbers, 15 times a second",
           "A speaker model reads the last 15 frames: an input of [1 × 15 × 96]. Python and Swift match to 1e-6.")
    source(fig, "Source: ml/common/features.py (features-v1), mirrored in GraptionVision/FeatureBuilder.swift")
    save(fig, "6_feature_vector")


# Web dashboard palette (apps/web/src/style.css), used for the dark tone-model diagram.
PINE = "#0f3b3a"
PINE_RAISED = "#164745"
PINE_HOVER = "#1d5654"
LINE = "#4e8f88"
SAGE = "#8ed0c3"
PEACH = "#f09070"
CREAM = "#ffe2cc"


def chart_tone_model():
    fig = plt.figure(figsize=(14, 6.6), facecolor=PINE)
    ax = fig.add_axes([0.03, 0.17, 0.94, 0.62])
    ax.set_facecolor(PINE)
    ax.set_xlim(0, 140)
    ax.set_ylim(0, 44)
    ax.axis("off")
    w, y0, h = 18, 8, 30
    xs = [1, 25, 49, 73, 97, 121]

    def frame(x, fill, edge, ls="-"):
        ax.add_patch(FancyBboxPatch((x, y0), w, h, boxstyle="round,pad=0,rounding_size=1.2",
                                    facecolor=fill, edgecolor=edge, lw=2, ls=ls))

    def box(x, fill, edge, title, lines, title_color=CREAM, line_color=SAGE, ls="-"):
        frame(x, fill, edge, ls)
        ax.text(x + w / 2, y0 + h - 3, title, ha="center", va="top", fontsize=15,
                fontweight="bold", color=title_color)
        ax.text(x + w / 2, y0 + h - 11, lines, ha="center", va="top", fontsize=12,
                color=line_color, linespacing=1.4)

    box(xs[0], PINE, LINE, "Sentence\naudio", "one VAD segment\n16 kHz mono\n(never stored)", ls="--")
    box(xs[1], PINE_HOVER, PINE_HOVER, "WavLM-base+",
        "pretrained speech\nmodel, frozen\n~94M params\n\nout: 13 layers\n× time × 768")
    box(xs[2], PEACH, PEACH, "Layer mix\n+ average",
        "13 learned weights\npick useful layers,\nthen average\nover time\n\nout: 768 numbers",
        title_color=PINE, line_color=PINE)
    box(xs[3], PEACH, PEACH, "Tone head", "Linear 768→256\nReLU, Dropout 0.3\nLinear 256→6\n~198k params",
        title_color=PINE, line_color=PINE)

    # 6 emotion probabilities as a mini bar chart (example values from the event schema).
    x = xs[4]
    frame(x, PINE_RAISED, LINE)
    ax.text(x + w / 2, y0 + h - 3, "6 emotions", ha="center", va="top", fontsize=15,
            fontweight="bold", color=CREAM)
    probs = [("happy", 0.72), ("neutral", 0.15), ("anger", 0.05), ("fear", 0.03), ("sad", 0.03), ("disgust", 0.02)]
    for i, (name, p) in enumerate(probs):
        yy = y0 + h - 10 - i * 3.3
        ax.text(x + 6.3, yy, name, ha="right", va="center", fontsize=11, color=SAGE)
        ax.add_patch(Rectangle((x + 7, yy - 1.1), 9.5 * p, 2.2,
                               color=PEACH if name == "happy" else LINE, lw=0))
        ax.text(x + 7.4 + 9.5 * p, yy, f"{p:.2f}", va="center", fontsize=10, color=CREAM)

    x = xs[5]
    frame(x, PINE_RAISED, LINE)
    ax.text(x + w / 2, y0 + h - 3, "Tag on\ncaption", ha="center", va="top", fontsize=15,
            fontweight="bold", color=CREAM)
    ax.add_patch(FancyBboxPatch((x + 3.5, y0 + 13.5), w - 7, 4.4, boxstyle="round,pad=0,rounding_size=2",
                                facecolor=PEACH, lw=0))
    ax.text(x + w / 2, y0 + 15.7, "excited", ha="center", va="center", fontsize=13, fontweight="bold", color=PINE)
    ax.text(x + w / 2, y0 + 10.5, "happy → excited\nanger → upset\nelse → no tag\nonly if p ≥ 0.6",
            ha="center", va="top", fontsize=11, color=SAGE, linespacing=1.35)

    for i in range(5):
        a, b = xs[i] + w + 0.4, xs[i + 1] - 0.4
        ax.annotate("", (b, y0 + h / 2), (a, y0 + h / 2),
                    arrowprops=dict(arrowstyle="-|>", color=CREAM, lw=1.8, mutation_scale=16))

    # Bracket over the trained part.
    bx0, bx1, by = xs[2], xs[3] + w, y0 + h + 2
    ax.plot([bx0, bx0, bx1, bx1], [by, by + 1.2, by + 1.2, by], color=PEACH, lw=2)
    ax.text((bx0 + bx1) / 2, by + 2, "the only part we train", ha="center", va="bottom", fontsize=13,
            color=PEACH, fontweight="bold")

    handles = [Rectangle((0, 0), 1, 1, color=PINE_HOVER, label="Pretrained, frozen"),
               Rectangle((0, 0), 1, 1, color=PEACH, label="Trained by us on CREMA-D")]
    fig.legend(handles=handles, loc="lower left", bbox_to_anchor=(0.03, 0.06), ncol=2, frameon=False,
               labelcolor=CREAM, fontsize=13, handlelength=1.2)
    fig.text(0.97, 0.085, "Status: in progress. Data downloaded and split by actor; not trained yet.",
             ha="right", fontsize=13, color=CREAM, fontweight="bold")
    fig.text(0.04, 0.955, "Tone Model Architecture", fontsize=22, fontweight="bold", color=CREAM, va="top")
    fig.text(0.04, 0.885, "WavLM features run once per clip, so training the small head takes minutes on a team Mac",
             fontsize=14, color=SAGE, va="top")
    fig.text(0.04, 0.025, "Spec: docs/GRAPTION_CONTEXT.md §7 and §9. Probabilities shown are an example, not a result.",
             fontsize=11, color=SAGE)
    save(fig, "8_tone_model")


if __name__ == "__main__":
    chart_tone_zones()
    chart_team_accuracy()
    chart_generalization()
    chart_coverage()
    chart_latency()
    chart_feature_vector()
    chart_tone_model()
    print("wrote", sorted(p.name for p in OUT.glob("*.png")))
