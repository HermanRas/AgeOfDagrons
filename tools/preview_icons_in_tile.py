"""Composite every sliced icon into `tile_frame` at real HUD size.

    <venv>\\python.exe tools\\preview_icons_in_tile.py

A CHECKERBOARD IS THE WRONG BACKGROUND TO JUDGE THESE ON, and reviewing on one
produced two false alarms already. `tech_blast_furnace`'s chimney smoke and
`abil_heal`'s bloom are both dark, soft-edged art whose alpha is genuinely
ambiguous -- against grey squares they read as blobs, and against the dark brown
field they will actually be drawn on they are close to invisible. The
checkerboard's job is finding holes punched in artwork; it is actively
misleading about anything dark and soft.

So this renders what the player sees: the icon inside `tile_frame`, at
`ActionSlot`'s real geometry -- a 72 px tile with the icon drawn at 52 px. It is
the last check before the art goes over the fence, and the only one at the size
it will be used.

Rendered at 3x for review because 72 px is too small to inspect on a desktop
monitor, with a 1x strip alongside so the actual legibility is visible too --
an icon that reads at 3x and turns to mush at 1x is the failure this catches.
"""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).parent))
from slice_ui_sheets import GRID_SHEETS, ICON_SHEETS  # noqa: E402

TILE = 72          # ActionSlot.SIZE
ICON = 52          # SIZE minus the 10 px inset each side
ZOOM = 3
GAP = 8
COLS = 8
BG = (18, 14, 11)


def main() -> int:
    sl = Path("assets/UI_Gen/sliced")
    out = sl / "review"
    out.mkdir(parents=True, exist_ok=True)

    frame_path = sl / "chrome" / "tile_frame.png"
    if not frame_path.exists():
        print("no tile_frame.png -- run slice_ui_sheets.py first")
        return 1
    frame = Image.open(frame_path).convert("RGBA")

    for sheet, (_, _, ids) in GRID_SHEETS.items():
        if sheet not in ICON_SHEETS:
            continue
        cells = []
        for ident in ids:
            p = sl / "icons" / f"{ident}.png"
            if not p.exists():
                continue
            for z in (ZOOM, 1):
                t = TILE * z
                cell = Image.new("RGBA", (t, t), (0, 0, 0, 0))
                cell.alpha_composite(frame.resize((t, t), Image.LANCZOS))
                icon = Image.open(p).convert("RGBA").resize(
                    (ICON * z, ICON * z), Image.LANCZOS)
                cell.alpha_composite(icon, ((t - ICON * z) // 2,
                                            (t - ICON * z) // 2))
                cells.append((cell, z))

        big = [c for c, z in cells if z == ZOOM]
        small = [c for c, z in cells if z == 1]
        rows = (len(big) + COLS - 1) // COLS
        bw = TILE * ZOOM
        board = Image.new(
            "RGBA",
            (COLS * (bw + GAP) + GAP, rows * (bw + GAP) + GAP + TILE + GAP * 2),
            BG + (255,))
        for i, c in enumerate(big):
            r, col = divmod(i, COLS)
            board.alpha_composite(c, (GAP + col * (bw + GAP),
                                      GAP + r * (bw + GAP)))
        # the 1x strip, so actual legibility is on the same page
        y = GAP + rows * (bw + GAP) + GAP
        for i, c in enumerate(small):
            board.alpha_composite(c, (GAP + i * (TILE + 4), y))

        board.convert("RGB").save(out / f"in_tile_{sheet}.png")
        print(f"  {sheet:36s} {len(big):2d} tiles")

    print("\nwritten: assets/UI_Gen/sliced/review/in_tile_*.png")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
