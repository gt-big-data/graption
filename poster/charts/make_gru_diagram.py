"""Poster diagram: the planned speaker GRU (docs/GRAPTION_CONTEXT.md §8).

Run from the repo root:  uv run python poster/charts/make_gru_diagram.py
"""

import matplotlib.pyplot as plt
from matplotlib.patches import FancyArrowPatch, FancyBboxPatch, Rectangle

from make_charts import OUT

# Graption web dashboard palette (apps/web/src/style.css).
PINE = "#0f3b3a"         # background
PINE_RAISED = "#164745"  # surfaces
LINE = "#4e8f88"         # borders
SAGE = "#8ed0c3"         # secondary text
CREAM = "#ffe2cc"        # text
PEACH = "#f09070"        # accent

SURFACE, INK, INK_2, GRID = PINE, CREAM, SAGE, PINE_RAISED
GRU_FILL, CELL_TEXT = PEACH, PINE
BLOCKS = [CREAM, SAGE, PEACH, LINE]  # lips 80, mouth 12, pose 3, loudness 1

plt.rcParams.update({
    "font.family": ["Inter", "Helvetica Neue", "Helvetica", "Arial", "DejaVu Sans"],
    "figure.facecolor": PINE,
    "savefig.facecolor": PINE,
})


def titled(fig, title, subtitle):
    fig.text(0.04, 0.955, title, fontsize=22, fontweight="bold", color=CREAM, va="top")
    fig.text(0.04, 0.885, subtitle, fontsize=14, color=SAGE, va="top")


def source(fig, text):
    fig.text(0.04, 0.025, text, fontsize=11, color=SAGE)


def save(fig, name):
    for ext in ("png", "svg"):
        fig.savefig(OUT / f"{name}.{ext}", dpi=300)
    plt.close(fig)


def box(ax, x, y, w, h, fill, text="", color=CELL_TEXT, size=14, weight="bold", lw=0, edge=None):
    ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0,rounding_size=0.12",
                                facecolor=fill, edgecolor=edge or fill, lw=lw))
    if text:
        ax.text(x + w / 2, y + h / 2, text, ha="center", va="center", fontsize=size,
                color=color, fontweight=weight)


def arrow(ax, a, b, color=INK_2, lw=1.8):
    ax.add_patch(FancyArrowPatch(a, b, arrowstyle="-|>", mutation_scale=16, color=color, lw=lw,
                                 shrinkA=0, shrinkB=0))


def frame_strip(ax, x, y, w, h):
    """One frame's 96 features as a vertical strip, blocks sized 80/12/3/1."""
    sizes = [80, 12, 3, 1]
    top = y + h
    for size, col in zip(sizes, BLOCKS):
        seg = h * size / 96
        ax.add_patch(Rectangle((x, top - seg), w, seg, facecolor=col, edgecolor=SURFACE, lw=0.8))
        top -= seg


def main():
    fig = plt.figure(figsize=(14, 7.2))
    ax = fig.add_axes([0.02, 0.08, 0.96, 0.76])
    ax.set_xlim(0, 28)
    ax.set_ylim(0, 10)
    ax.axis("off")

    # Time steps shown: 1, 2, 3, …, 15.
    steps = [("t1", 3.2), ("t2", 6.2), ("t3", 9.2), ("t15", 14.6)]
    strip_y, strip_h, strip_w = 0.6, 2.4, 0.55
    l1_y, l2_y, cell_w, cell_h = 4.0, 6.6, 2.0, 1.4

    for name, cx in steps:
        frame_strip(ax, cx - strip_w / 2, strip_y, strip_w, strip_h)
        ax.text(cx, strip_y - 0.35, name, ha="center", va="top", fontsize=13, color=INK_2)
        arrow(ax, (cx, strip_y + strip_h + 0.05), (cx, l1_y - 0.05))
        box(ax, cx - cell_w / 2, l1_y, cell_w, cell_h, GRU_FILL, "GRU", size=15)
        arrow(ax, (cx, l1_y + cell_h + 0.05), (cx, l2_y - 0.05))
        box(ax, cx - cell_w / 2, l2_y, cell_w, cell_h, GRU_FILL, "GRU", size=15)

    # Hidden state carried left to right (memory of earlier frames).
    for (_, a), (_, b) in zip(steps, steps[1:]):
        for y in (l1_y, l2_y):
            mid = y + cell_h / 2
            if b - a > 4:  # gap before t15: dotted "…"
                ax.plot([a + cell_w / 2 + 0.1, b - cell_w / 2 - 0.25], [mid, mid],
                        ls=(0, (1, 3)), color=INK_2, lw=2.2)
                arrow(ax, (b - cell_w / 2 - 0.4, mid), (b - cell_w / 2 - 0.05, mid))
            else:
                arrow(ax, (a + cell_w / 2 + 0.05, mid), (b - cell_w / 2 - 0.05, mid))
    ax.text(11.9, strip_y + strip_h / 2, "…", ha="center", va="center", fontsize=26, color=INK_2)

    # Left labels.
    ax.text(0.2, strip_y + strip_h / 2, "15 frames\n(1 second)\n96 numbers\neach",
            ha="left", va="center", fontsize=13, color=INK)
    ax.text(0.2, l1_y + cell_h / 2, "Layer 1", ha="left", va="center", fontsize=14, color=INK, fontweight="bold")
    ax.text(0.2, l2_y + cell_h / 2, "Layer 2", ha="left", va="center", fontsize=14, color=INK, fontweight="bold")
    ax.text(8.9, l2_y + cell_h + 0.45, "64-number memory passed frame to frame",
            ha="center", va="bottom", fontsize=13, color=INK_2, style="italic")

    # Output head from the last top cell.
    last_x = steps[-1][1]
    out_y = l2_y + cell_h / 2
    arrow(ax, (last_x + cell_w / 2 + 0.05, out_y), (17.9, out_y))
    box(ax, 18.0, out_y - 0.7, 2.6, 1.4, PINE_RAISED, "Linear\n64 → 1", color=INK, size=13,
        lw=2, edge=LINE)
    arrow(ax, (20.65, out_y), (21.35, out_y))
    box(ax, 21.4, out_y - 0.7, 2.4, 1.4, PINE_RAISED, "sigmoid", color=INK, size=13, lw=2, edge=LINE)
    arrow(ax, (23.85, out_y), (24.55, out_y))

    # p(speaking) meter.
    mx, my, mw, mh = 24.6, out_y - 0.45, 3.2, 0.9
    ax.add_patch(FancyBboxPatch((mx, my), mw, mh, boxstyle="round,pad=0,rounding_size=0.12",
                                facecolor=GRID, lw=0))
    ax.add_patch(FancyBboxPatch((mx, my), mw * 0.94, mh, boxstyle="round,pad=0,rounding_size=0.12",
                                facecolor=PEACH, lw=0))
    ax.text(mx + mw / 2, my + mh / 2, "0.94", ha="center", va="center", fontsize=16,
            color=PINE, fontweight="bold")
    ax.text(mx + mw / 2, my + mh + 0.25, "p(speaking)", ha="center", va="bottom", fontsize=15,
            color=INK, fontweight="bold")
    ax.text(mx + mw / 2, my - 0.3, "per face, every frame\n→ smoothed over 5\n→ fusion picks the\n    caption's speaker",
            ha="center", va="top", fontsize=12, color=INK_2)

    titled(fig, "Proposed Speaker Detection Architecture",
           "2-layer GRU, 64 hidden units, about 56k parameters. Not yet trained.")
    source(fig, "Spec: docs/GRAPTION_CONTEXT.md §8. Trains on AVA-ActiveSpeaker; must beat a "
           "logistic-regression baseline on std(jawOpen) + mean(loudness). Example value shown.")
    save(fig, "7_speaker_gru")


if __name__ == "__main__":
    main()
