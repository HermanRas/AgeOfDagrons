"""Turn the sliced UI chrome masters into the sizes the game actually draws.

    <venv>\\python.exe tools\\prepare_ui_chrome.py [--check]

    assets/UI_Gen/sliced/chrome/*.png   ->   game/assets/ui/chrome/*.png

GAME-SIDE SCRIPT LIVING IN tools/, the same arrangement `stage_audio.py` has and
by the same reasoning (asset_request.md, 2026-08-23): ownership follows who can
maintain the thing. The art side owns what is in `sliced/`; this is the game
side deciding what size a widget wants, which is a layout question.

WHY A RESIZE STEP EXISTS AT ALL, because "just ship the master" is the obvious
alternative and it is wrong for exactly one reason:

    Godot draws a NinePatchRect's BORDER AT 1:1. The margin is in source pixels
    and does not scale with the rect.

So `panel_hud`, a 1024 px plate whose painted border measures 46 px, gives a 46
px border on a 152 px resource panel -- 92 of its 152 pixels are corner, and the
numbers inside get clipped. Shrinking the MARGIN instead does not help and is
worse: the margin says where the border ENDS, so a margin of 12 against a 46 px
painted border leaves 34 px of bevel inside the stretched region, smeared across
the whole panel. The only lever that moves the drawn border is the source size.

HOW THE TARGET SIZE IS CHOSEN. Each piece below names the border thickness it
should draw at, in screen pixels, on the 1152x648 design canvas. The scale factor
is that over the measured margin, and the output size follows. The alternative --
picking output sizes and reporting what border they give -- was tried first and
reads backwards: the number anybody would ever want to change is the border.

WHAT IS NOT RESIZED, and it is most of the set. Anything drawn at a fixed size
with no nine-patch (`tile_frame`, `portrait_frame`, `group_slot_ring`, the
arrows, the checkboxes) is scaled by the engine with a plain filter and looks
correct from any source, so it keeps its master resolution and the extra pixels
cost only APK size. They are listed as PASSTHROUGH rather than omitted, so this
file is a full inventory of the 27 and a new piece cannot be forgotten by
falling through a default.

IDEMPOTENT. It reads `sliced/` and writes `game/`, never the other way, so
running it twice is the same as running it once and running it after a re-slice
picks up the new art. `--check` reports what it would do and writes nothing.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image

SRC = Path("assets/UI_Gen/sliced/chrome")
DST = Path("game/assets/ui/chrome")

# piece -> ((measured left, right, top, bottom), wanted thickest border px)
#
# The measured figures come from `tools/measure_ninepatch.py`, verbatim. A zero
# means the piece does not nine-patch on that axis at all -- a bar and a button
# stretch horizontally and are drawn at their own height.
#
# THE WANTED FIGURE APPLIES TO THE THICKEST MEASURED SIDE and the rest follow by
# the same scale, because a frame's four sides are one drawing and rescaling them
# independently would need four source images. `panel_ornate` is the piece that
# forced this: its border is genuinely lopsided (241 px of dragon on the right
# against 92 px of plain moulding along the bottom), and an earlier version of
# this table carried one number per piece and quietly stretched the difference.
NINE_PATCH: dict[str, tuple[tuple[int, int, int, int], int]] = {
    # Drawn from 152x196 (the resource counter) up to a full page (~620x500),
    # so the border has to read at the small end without swallowing it. 12 px
    # clears the resource rows and still looks like moulding on a page.
    "panel_hud": ((46, 46, 46, 46), 12),
    # THE ONE PIECE `measure_ninepatch.py` GETS WRONG, and it is worth knowing why
    # rather than just taking the number below on trust. That tool looks for a
    # STRETCHABLE RUN, and on this frame it finds the bead band and stops at its
    # outer edge -- 183 px on the left. But a nine-patch margin has to clear the
    # CORNER, and the corner here is a dragon whose head and neck reach about 250
    # px in and 300 px down. Margins of 183/241/178/92 put the boundary through
    # the dragon's neck, so the neck was in the stretched region: the project
    # owner reported it as "the left side of main menu is stretched, the 9 patch
    # did not slice correctly" on 2026-08-30, and it was.
    #
    # 300 ON ALL FOUR SIDES, measured off the art by eye against the rendered
    # frame, because the automatic measurement is answering a different question.
    # The extra margin below the dragons is plain bead band drawn at 1:1 instead
    # of tiled, which costs nothing and is what makes one number safe for four
    # sides that are not identical.
    "panel_ornate": ((300, 300, 300, 300), 90),
    # A button is ~200x40. Its end caps are the border; 14 px leaves room for a
    # word between them.
    "button_normal": ((28, 27, 0, 0), 14),
    "button_pressed": ((26, 25, 0, 0), 14),
    "button_disabled": ((25, 26, 0, 0), 14),
    # A bar is ~176x30 and its caps are the moulded ends of the channel. 12 px
    # each end leaves 150 for the fill to travel.
    "bar_groove": ((33, 34, 0, 0), 12),
    "bar_fill_health": ((34, 33, 0, 0), 12),
    "bar_fill_progress": ((32, 32, 0, 0), 12),
    "field_input": ((23, 23, 0, 0), 12),
    # A tab is ~110x28.
    "tab_plate": ((19, 19, 0, 0), 10),
}

#: A SECOND OUTPUT FROM ONE MASTER, at a different size. output -> (source, border)
#:
#: This exists because Godot draws a nine-patch border at 1:1, which is the trap
#: this whole script is about -- and one consequence of it is that ONE PREPARED
#: SIZE CANNOT SERVE TWO DRAW SIZES. `panel_ornate` is drawn at 640 px on the
#: main menu, where a 90 px dragon reads correctly, and at 152 px on the resource
#: counter, where that same 90 px border would leave 0 px of panel between the
#: two corners. So the resource counter gets its own copy of the same artwork,
#: prepared for its own size.
#:
#: The alternative -- scaling a NinePatchRect by putting it inside a scaled
#: Control -- makes the border blurry and the layout arithmetic a fiction. Two
#: files off one master is 40 KB and no cleverness.
EXTRA_SIZES: dict[str, tuple[str, int]] = {
    "panel_ornate_small": ("panel_ornate", 30),
}

#: Pieces whose border REPEATS rather than being uniform, and which must
#: therefore be tiled rather than stretched. `measure_ninepatch.py` reports the
#: period; a run of beads pulled to three times its length is a run of ellipses.
#: The consumer sets `NinePatchRect.axis_stretch_horizontal/vertical` to
#: `AXIS_STRETCH_MODE_TILE`; this set is the record of which need it.
TILED = {"panel_ornate", "panel_ornate_small"}

# piece -> longest edge in the output, or None to keep the master.
#
# These are drawn WHOLE at a known size, so there is no border arithmetic -- the
# only question is how much resolution the engine needs to scale from. Twice the
# largest drawn size, which is the usual rule for a bitmap that may land on a
# denser phone panel than the design canvas.
WHOLE: dict[str, int | None] = {
    "banner_alert": 640,      # drawn 320 wide
    "banner_age": 640,        # drawn ~320 wide
    "frame_minimap": 512,     # drawn ~230 square
    "tile_frame": None,       # 72 px, and the corners must stay crisp
    "tile_frame_selected": None,
    "tile_frame_disabled": None,
    "portrait_frame": None,   # 72 px
    "group_slot_ring": None,  # 64 px
    "badge_round": None,      # 24-32 px
    "checkbox_off": None,
    "checkbox_on": None,
    "radio_off": None,
    "radio_on": None,
    "arrow_up": None,
    "arrow_down": None,
    "arrow_left": None,
    "arrow_right": None,
}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true",
                    help="report what would change and write nothing")
    args = ap.parse_args()

    if not SRC.is_dir():
        print(f"no {SRC} -- run tools/slice_ui_sheets.py first", file=sys.stderr)
        return 1
    DST.mkdir(parents=True, exist_ok=True)

    known = set(NINE_PATCH) | set(WHOLE)
    found = {p.stem for p in SRC.glob("*.png")}
    # An extra size is an OUTPUT, not a master, so it must not be looked for in
    # the source directory -- but its own source must exist.
    for out_name, (src_name, _) in EXTRA_SIZES.items():
        if src_name not in NINE_PATCH:
            print(f"  !! {out_name}: its source {src_name} has no nine-patch entry")
            return 1
    for missing in sorted(known - found):
        print(f"  !! {missing}: named here but not in {SRC}")
    for stranger in sorted(found - known):
        print(f"  !! {stranger}: in {SRC} and named nowhere here -- add a line")
    if found - known:
        return 1

    print(f"{'piece':24s} {'source':>11s} -> {'output':>11s}  "
          f"{'L':>3s} {'R':>3s} {'T':>3s} {'B':>3s}  note")
    print("-" * 84)
    jobs = [(n, n) for n in sorted(found)]
    jobs += [(out, src) for out, (src, _) in sorted(EXTRA_SIZES.items())]

    for name, source_name in jobs:
        src = SRC / f"{source_name}.png"
        im = Image.open(src).convert("RGBA")
        w, h = im.size

        margin = ""
        if name in EXTRA_SIZES:
            measured, _ = NINE_PATCH[source_name]
            wanted = EXTRA_SIZES[name][1]
            scale = wanted / max(measured)
            out = (max(1, round(w * scale)), max(1, round(h * scale)))
            margin = " ".join("%3d" % round(m * scale) for m in measured)
            note = f"nine-patch off {source_name}, x{scale:.3f}"
        elif name in NINE_PATCH:
            measured, wanted = NINE_PATCH[name]
            scale = wanted / max(measured)
            out = (max(1, round(w * scale)), max(1, round(h * scale)))
            # THE NUMBERS THE .gd FILES CARRY. They are constants in the widget
            # that draws each piece rather than data loaded at runtime: there are
            # ten of them, they change only when the art does, and a `patch_margin`
            # read from a json would be one more file that can go missing at boot.
            margin = " ".join("%3d" % round(m * scale) for m in measured)
            note = f"nine-patch, x{scale:.3f}"
        else:
            longest = WHOLE[name]
            if longest is None:
                out = (w, h)
                note = "PASSTHROUGH"
            else:
                scale = longest / max(w, h)
                out = (max(1, round(w * scale)), max(1, round(h * scale)))
                note = f"whole, x{scale:.3f}"

        if name in TILED:
            note += ", TILE"
        print(f"{name:24s} {w:5d}x{h:<5d} -> {out[0]:5d}x{out[1]:<5d}  "
              f"{margin if margin else ' ' * 15}  {note}")
        if args.check:
            continue
        # LANCZOS: these are smooth painted pieces being reduced, which is the
        # case it is for. Nothing here is pixel art, so there is no grid to
        # preserve and NEAREST would only alias the moulding.
        if out != (w, h):
            im = im.resize(out, Image.LANCZOS)
        im.save(DST / f"{name}.png")

    if args.check:
        print("\n--check: nothing written")
    else:
        print(f"\nwritten: {len(jobs)} pieces to {DST}")
        print("Godot must see them: run --import before the suite.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
