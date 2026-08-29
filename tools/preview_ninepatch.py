"""Render the sliced panels as nine-patches at extreme sizes.

    <venv>\\python.exe tools\\preview_ninepatch.py

`measure_ninepatch.py` reports a NUMBER; this renders what that number does.
The failure a wrong margin causes -- a dragon dragged out into a smear -- is
obvious in a picture and invisible in a table, and three versions of that
measurement in a row produced confident, symmetric, wrong figures. So the margin
that ships is the one that survives this, not the one the table liked.

The sizes below are deliberately hostile: very wide and short, then very narrow
and tall. A margin that is too small smears at BOTH, and one that is merely
generous looks the same as a correct one, which is the right way round.
"""
from __future__ import annotations

import json
from pathlib import Path

from PIL import Image

# (source, margin, [output sizes]). Margins are rounded UP from
# measure_ninepatch.py's figures -- generous costs nothing, short smears.
CASES = [
    ("panel_ornate", 256, [(1024, 1024), (900, 340), (340, 900), (620, 620)]),
    ("panel_hud", 64, [(1024, 1024), (900, 340), (340, 900), (620, 620)]),
    ("tile_frame", 128, [(256, 256), (500, 200), (200, 500)]),
    ("portrait_frame", 56, [(254, 254), (500, 200), (200, 500)]),
]


def nine_patch(src: Image.Image, size: tuple[int, int], m: int) -> Image.Image:
    w, h = size
    sw, sh = src.size
    # Corners cannot overlap. If the target is smaller than two margins, shrink
    # the margin for this draw -- which is exactly what Godot does, and is the
    # signal that the texture wants downscaling before use rather than a
    # different margin.
    mx = min(m, max(1, w // 2 - 1), max(1, sw // 2 - 1))
    my = min(m, max(1, h // 2 - 1), max(1, sh // 2 - 1))

    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    cols_s = [(0, mx), (mx, sw - mx), (sw - mx, sw)]
    rows_s = [(0, my), (my, sh - my), (sh - my, sh)]
    cols_d = [(0, mx), (mx, w - mx), (w - mx, w)]
    rows_d = [(0, my), (my, h - my), (h - my, h)]

    for (sy0, sy1), (dy0, dy1) in zip(rows_s, rows_d):
        for (sx0, sx1), (dx0, dx1) in zip(cols_s, cols_d):
            if sx1 <= sx0 or sy1 <= sy0 or dx1 <= dx0 or dy1 <= dy0:
                continue
            part = src.crop((sx0, sy0, sx1, sy1))
            out.paste(part.resize((dx1 - dx0, dy1 - dy0), Image.LANCZOS),
                      (dx0, dy0))
    return out


def main() -> int:
    root = Path("assets/UI_Gen/sliced/chrome")
    out_dir = Path("assets/UI_Gen/sliced/review")
    out_dir.mkdir(parents=True, exist_ok=True)
    measured = json.loads(
        Path("assets/UI_Gen/sliced/ninepatch.json").read_text(encoding="utf-8"))

    for name, margin, sizes in CASES:
        path = root / f"{name}.png"
        if not path.exists():
            print(f"  MISSING {name}")
            continue
        src = Image.open(path).convert("RGBA")
        rec = measured.get(name, {})
        worst = max(rec.get("left", 0), rec.get("right", 0),
                    rec.get("top", 0), rec.get("bottom", 0))
        flag = "" if margin >= worst else f"  <-- BELOW measured {worst}"
        print(f"  {name:20s} margin {margin:4d}  (measured max {worst:4d}){flag}")

        pad = 16
        board_w = sum(s[0] for s in sizes) + pad * (len(sizes) + 1)
        board_h = max(s[1] for s in sizes) + pad * 2
        board = Image.new("RGBA", (board_w, board_h), (26, 26, 30, 255))
        x = pad
        for size in sizes:
            board.alpha_composite(nine_patch(src, size, margin), (x, pad))
            x += size[0] + pad
        board.save(out_dir / f"ninepatch_{name}.png")

    print("\nwritten: assets/UI_Gen/sliced/review/ninepatch_*.png")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
