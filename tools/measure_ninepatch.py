"""Measure the nine-patch stretch margins of the sliced UI chrome.

    <venv>\\python.exe tools\\measure_ninepatch.py

ART_PROMPT.md ASKED for 256 px corners on `panel_ornate` and 160 on `panel_hud`.
What Gemini drew is its own business, and a margin that is one pixel too small
puts a slice of dragon into the stretched run -- where it smears. So the numbers
that go into Godot are measured off the art, not carried over from the prompt.

HOW A STRETCHABLE RUN IS FOUND. A nine-patch stretches by repeating one column
(or row) of pixels, so a run is stretchable exactly where consecutive columns
are near-identical. `d[x]` below is the mean absolute difference between column
x and column x+1; it is ~0 along plain moulding and spikes anywhere the art
changes. The longest low run through the middle is the stretchable region and
the distance from each end to it is that side's margin.

THE TOLERANCE IS NOT ZERO AND CANNOT BE. This art is smooth-shaded and JPEG'd:
a perfectly plain gold run still has a gentle lighting falloff along it plus
encoder noise, so consecutive columns differ by a few levels everywhere. The
floor is measured per image -- the median of d over the middle third, which is
plain moulding by construction on every one of these -- and the cut is set well
above it. Reporting the floor alongside the answer is the point; if the floor is
not far below the cut, the measurement is not separating anything and the number
should not be trusted. That is the same rule AGENT_ASSET.md 4 records for
comparing rendered frames: establish the noise floor before choosing a threshold.
"""
from __future__ import annotations

import json
from pathlib import Path

import numpy as np
from PIL import Image

# What each piece does when it is drawn at a size other than its own.
#   "both" - stretches horizontally and vertically (a panel)
#   "h"    - horizontally only (a bar, a banner, a button)
#   "none" - drawn at one size, measured only to confirm it needs no margins
PIECES: dict[str, str] = {
    "panel_ornate": "both",
    "panel_hud": "both",
    "banner_alert": "h",
    "banner_age": "h",
    "frame_minimap": "none",
    "button_normal": "h",
    "button_pressed": "h",
    "button_disabled": "h",
    "bar_groove": "h",
    "bar_fill_health": "h",
    "bar_fill_progress": "h",
    "field_input": "h",
    "tile_frame": "both",
    "tile_frame_selected": "both",
    "tile_frame_disabled": "both",
    "portrait_frame": "both",
    "tab_plate": "h",
}


def run_margins(a: np.ndarray, axis: int) -> tuple[int, int, float, float, int]:
    """(margin_before, margin_after, noise_floor, cut, period) along `axis`.

    TWO EARLIER VERSIONS OF THIS WERE WRONG IN OPPOSITE DIRECTIONS, and both
    failures are the reason it now works the way it does.

    The first compared each column to its NEIGHBOUR and averaged over the full
    height. It put `panel_ornate`'s left margin at 75 px. Its dragon heads reach
    ~250 px in, but a column through one also crosses 700 px of flat brown
    field, which dilutes the head below any cut. Using that number would have
    stretched a dragon.

    The second took p99.5 of that same neighbour difference and included the
    alpha channel. On a keyed piece the alpha edge is a 0 -> 255 step, so the
    noise floor came out at 255 and every margin collapsed to zero.

    WHAT WAS ACTUALLY WRONG WITH BOTH: these edges are not uniform, they are
    PERIODIC. ART_PROMPT.md asked for bead-and-reel moulding "the same profile
    repeating steadily", and a repeating bead is not stretchable -- stretching
    smears it. It is TILEABLE, which is a different Godot setting
    (`StyleBoxTexture.axis_stretch_horizontal = AXIS_STRETCH_MODE_TILE`).

    So the comparison is against the column one PERIOD away, not one pixel away.
    In the regular run every column matches its period-mate; in the ornament it
    does not. That measures the thing being asked about, and it reports the
    period as well, because a tiled region has to be a whole number of beads or
    the seam shows.
    """
    moved = np.moveaxis(a, axis, 0).astype(np.float32)
    n = moved.shape[0]
    # RGB only. Alpha is a hard step at the silhouette and swamps everything.
    sig = moved[..., :3].reshape(n, -1)

    lo, hi = n // 4, (3 * n) // 4

    def period_diff(p: int) -> np.ndarray:
        # p95 across the column: an ornament occupying a quarter of the column's
        # length must still register, but one noisy pixel must not.
        return np.percentile(np.abs(sig[:-p] - sig[p:]), 95, axis=1)

    # The period is whatever shift makes the middle of the piece agree with
    # itself best. A genuinely uniform run agrees at every shift and lands on
    # the smallest, which is correct and harmless.
    best_p, best_score = 1, None
    for p in range(1, max(2, n // 6)):
        d = period_diff(p)
        score = float(np.median(d[lo:min(hi, len(d))]))
        if best_score is None or score < best_score - 1e-9:
            best_p, best_score = p, score

    d = period_diff(best_p)
    floor = float(best_score or 0.0)
    cut = max(floor * 3.0 + 2.0, 4.0)

    quiet = d <= cut
    centre = min(n // 2, len(quiet) - 1)
    if not quiet[centre]:
        return 0, 0, floor, cut, best_p
    start = centre
    while start > 0 and quiet[start - 1]:
        start -= 1
    end = centre
    while end < len(quiet) - 1 and quiet[end + 1]:
        end += 1
    # `end` indexes the first of a matching pair, so the run really reaches
    # end + best_p.
    return int(start), int(max(0, n - 1 - (end + best_p))), floor, cut, best_p


def main() -> int:
    root = Path("assets/UI_Gen/sliced/chrome")
    out: dict[str, dict] = {}

    print(f"{'piece':24s} {'size':>11s}  {'L':>4s} {'R':>4s} {'T':>4s} {'B':>4s}"
          f"  {'floor':>6s} {'cut':>5s}  verdict")
    print("-" * 82)

    for name, mode in PIECES.items():
        path = root / f"{name}.png"
        if not path.exists():
            print(f"{name:24s} MISSING")
            continue
        a = np.asarray(Image.open(path).convert("RGBA"))
        h, w = a.shape[:2]
        rec: dict = {"w": w, "h": h, "mode": mode}

        left = right = top = bottom = 0
        floor = cut = 0.0
        px = py = 1
        if mode in ("both", "h"):
            left, right, floor, cut, px = run_margins(a, 1)
        if mode == "both":
            top, bottom, f2, c2, py = run_margins(a, 0)
            floor, cut = max(floor, f2), max(cut, c2)

        # A margin that eats most of the piece means no run was found -- the
        # art is ornamented all the way along and cannot be stretched on that
        # axis without smearing.
        span_h = w - left - right
        span_v = h - top - bottom
        bad = (mode in ("both", "h") and span_h < w * 0.15) or \
              (mode == "both" and span_v < h * 0.15)
        verdict = "NO CLEAN RUN" if bad else ("n/a" if mode == "none" else "ok")

        # A period of more than a few pixels means the edge REPEATS and must be
        # tiled, not stretched. Godot: StyleBoxTexture with
        # axis_stretch_horizontal/vertical = AXIS_STRETCH_MODE_TILE.
        tiled = px > 4 or py > 4
        rec.update({"left": left, "right": right, "top": top, "bottom": bottom,
                    "period_x": px, "period_y": py,
                    "draw": "tile" if tiled else "stretch",
                    "noise_floor": round(floor, 3), "cut": round(cut, 3),
                    "verdict": verdict})
        out[name] = rec
        print(f"{name:24s} {w:5d}x{h:<5d}  {left:4d} {right:4d} {top:4d} "
              f"{bottom:4d}  {floor:6.2f} {cut:5.2f}  "
              f"{('tile p=%d/%d' % (px, py)) if tiled else 'stretch':13s} {verdict}")

    Path("assets/UI_Gen/sliced/ninepatch.json").write_text(
        json.dumps(out, indent=2), encoding="utf-8")
    print("\nwritten: assets/UI_Gen/sliced/ninepatch.json")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
