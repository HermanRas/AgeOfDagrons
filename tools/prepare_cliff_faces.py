"""Gemini cliff sheets -> keyed, toned cliff-face textures the bake can map.

    <venv>\\python.exe tools\\prepare_cliff_faces.py

Masters in `assets/Cliff_Gen/*.jpg` are committed; this writes
`assets/Cliff_Gen/prepared/`, which is derived and gitignored -- the same split
`slice_ui_sheets.py` uses, and for the same reason: the sheet is the art, this
is a build step.

WHAT IT DOES, and every number in it was measured rather than chosen.

1. KEYS THE BLACK, reusing `slice_ui_sheets.key_background`'s primitives so
   there is one implementation of "dark AND reachable from the border".

   ⚠️ THE SHARED THRESHOLD IS WRONG FOR DARK ROCK, which is why `THRESHOLD`
   exists. `background_threshold` returns min(40, max(10, border_p99.5 + 8)),
   and on every cliff sheet the rock runs to the border, so the 40 cap decides.
   40 suits pale limestone and EATS dark stone: sheet v3's shadows measure
   #191C1D, below the cut, so the fill walks in through them. Swept, v3 keys on
   a clean plateau to 16 (+0.03..0.07% per step, same as v1 and v2) and then
   runs away -- +1.58% at 24, +5.77% at 30, +6.61% at 40. At 40 it removed
   47.7% of the canvas against 33% for the others, punching holes clean through
   the face.

   THE TELL IS A PLATEAU, not a value: sweep the threshold and take the flat
   part. A sheet with no plateau has rock and ground in one population and has
   to be regenerated, not re-keyed.

2. TONES IT. A cliff has to SEPARATE from the ground it stands on -- that is
   gameplay, because a cliff is impassable and the player reads it at a glance.
   Measured against the staged terrain (grass mean luminance 139.4, sand 197.5):

       sheet   face lum   face sd   separation from grass
       v1        141.1      43.8       1.7    <- same value as the grass
       v2        147.6      48.9       8.2
       v3         57.3      28.7      82.1    <- darker than anything we ship

   v1 was rejected by the owner on sight and THAT is the number behind it: its
   face is luminance-identical to grass, so no silhouette can save it.

   v2 has the most modelling of the three and the wrong value, and value is the
   half a curve can fix. `TARGET_MEAN`/`GAIN` take v2_s1 to lum 102, separation
   37, and sd 55 -- MORE form than it started with, because the gain expands
   contrast rather than flattening it toward grey.

   Applied as a per-pixel gain on RGB so the warm limestone hue survives; a lerp
   toward grey would desaturate it into v3's family, which is the thing being
   avoided.

3. SPLITS THE STRIPS and records each one's lip/face/scree zones in
   `zones.json`, because the recipe needs to know where z = 0 falls inside the
   texture. The face is the rows that are solid across the full width; the lip
   and the scree are scattered rock and are not.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from slice_ui_sheets import background_threshold, box_blur3, fill_from_border, luma

SRC = Path("assets/Cliff_Gen")
OUT = SRC / "prepared"

#: Per-sheet background cut where the shared default is wrong. See the header.
THRESHOLD: dict[str, int] = {"v3": 16}

#: Where the face's mean luminance should land, and how much to expand contrast
#: on the way. 105/1.15 measured against grass 139.4 and sand 197.5.
TARGET_MEAN = 105.0
GAIN = 1.15

#: Sheets to tone. A sheet already in the right value range would be listed
#: here with a gain of 1.0 rather than left out, so the intent stays visible.
TONE = {"v1": True, "v2": True, "v3": False}

#: How much of the strip's TOP becomes the crest -- the far-edge piece, which
#: shows the rocky lip of a plateau and nothing below it. Owner 2026-09-22.
#:
#: ⚠️ IT REPLACES A HAND CUT, and the two faults that cut had are both why this
#: is a build step now rather than a file:
#:   - 0.89 m tall, which is 25 px on screen against a 32 px tile diamond. It
#:     read as a dark smear rather than a rim.
#:   - 27% of its columns carried under a quarter of the lip's height, in two
#:     holes 2.34 m and 1.88 m wide. The face strip has NO such columns, so
#:     cutting from the toned face strip inherits its continuity for free.
#: A one-tile piece showed 181 px of the strip and could sit between those holes
#: forever, which is why they only appeared once the pieces got longer.
CREST_METRES = 1.88
#: The bottom of that, dissolved rather than ruled off. A straight horizontal cut
#: reads as a sliced band; this one breaks up through the rock's own dark
#: crevices, so the edge follows the stone.
CREST_DISSOLVE_M = 0.60

W = np.array([0.2126, 0.7152, 0.0722])


def key(rgb: np.ndarray, tag: str) -> tuple[np.ndarray, np.ndarray, int]:
    lum = luma(rgb)
    thr = THRESHOLD.get(tag, background_threshold(lum))
    bg = fill_from_border(lum <= thr)
    a01 = box_blur3((~bg).astype(np.float32))
    # The sheet was composited over black, so an edge pixel is colour*coverage.
    # Dividing it back out is what stops a dark fringe when the strip is finally
    # drawn over lit ground.
    safe = np.maximum(a01, 1e-3)[..., None]
    return np.clip(rgb.astype(np.float32) / safe, 0, 255), a01, thr


def tone(rgb: np.ndarray, a01: np.ndarray) -> np.ndarray:
    op = a01 > 0.5
    if not op.any():
        return rgb
    lum = rgb @ W
    want = np.clip((lum - lum[op].mean()) * GAIN + TARGET_MEAN, 1, 255)
    return np.clip(rgb * (want / np.maximum(lum, 1e-3))[..., None], 0, 255)


def crest(rgb: np.ndarray, a01: np.ndarray, rows_per_m: float) -> np.ndarray:
    """Alpha for the far-edge piece: the top `CREST_METRES`, dissolved at the foot.

    Returns an alpha the same shape as the strip, so the crest and the face share
    one canvas and one `texture_metres`. That shared canvas is what makes a near
    edge and a far edge of the same plateau register by construction -- every
    geometry number in cliff_back*.toml is copied from cliff_face*.toml and this
    is the reason it may be.

    The dissolve keeps the BRIGHTEST pixels longest, so the band breaks up
    through shadowed crevices and leaves lit boulder tops standing. Thresholding
    on the image's own luminance rather than on noise is what makes the edge
    follow the stone instead of cutting across it.
    """
    h = a01.shape[0]
    keep_rows = min(h, int(round(CREST_METRES * rows_per_m)))
    band = max(1, int(round(CREST_DISSOLVE_M * rows_per_m)))
    solid = max(0, keep_rows - band)

    out = np.zeros_like(a01)
    out[:solid] = a01[:solid]

    if keep_rows > solid:
        lum = rgb[solid:keep_rows] @ W
        op = a01[solid:keep_rows] > 0.5
        if op.any():
            lo, hi = np.percentile(lum[op], [5, 95])
            score = np.clip((lum - lo) / max(hi - lo, 1e-3), 0, 1)
            t = np.linspace(0.0, 1.0, keep_rows - solid)[:, None]
            out[solid:keep_rows] = np.where(score > t, a01[solid:keep_rows], 0.0)

    # One blur pass so the dissolve is not single-pixel confetti, then clamp back
    # under the strip's own alpha so it can never invent coverage.
    return np.minimum(box_blur3(out), a01)


def strips(a01: np.ndarray) -> list[tuple[int, int]]:
    rows = (a01 > 0.5).any(axis=1)
    runs, start = [], None
    for i, v in enumerate(rows):
        if v and start is None:
            start = i
        elif not v and start is not None:
            runs.append((start, i))
            start = None
    if start is not None:
        runs.append((start, len(rows)))
    return [r for r in runs if r[1] - r[0] > 20]


def face_rows(a01: np.ndarray) -> tuple[int, int]:
    """The solid band. The lip and the scree are scattered rock, not solid."""
    dens = (a01 > 0.5).mean(axis=1)
    solid = dens >= 0.97
    if not solid.any():
        return 0, len(solid)
    return int(np.argmax(solid)), int(len(solid) - np.argmax(solid[::-1]))


def main() -> int:
    sheets = sorted(SRC.glob("sheet_cliff_faces_*.jpg"))
    if not sheets:
        print(f"no sheets in {SRC}")
        return 1
    OUT.mkdir(parents=True, exist_ok=True)
    report: dict[str, dict] = {}

    for f in sheets:
        tag = f.stem.split("_")[-1]
        src = np.asarray(Image.open(f).convert("RGB")).astype(np.int16)
        rgb, a01, thr = key(src, tag)
        if TONE.get(tag, True):
            rgb = tone(rgb, a01)

        print(f"{f.name}: threshold {thr}, keyed {100*(a01 <= 0.5).mean():.1f}%, "
              f"toned {TONE.get(tag, True)}")
        for k, (y0, y1) in enumerate(strips(a01), 1):
            band_rgb, band_a = rgb[y0:y1], a01[y0:y1]
            fy0, fy1 = face_rows(band_a)
            h = y1 - y0
            face_px = max(1, fy1 - fy0)
            name = f"cliff_{tag}_s{k}"
            Image.fromarray(np.dstack([
                band_rgb, np.clip(band_a * 255, 0, 255)]).astype(np.uint8), "RGBA"
            ).save(OUT / f"{name}.png")

            # The far-edge piece, cut from the TONED strip so it carries the same
            # value as the face it meets at a corner. The hand cut it replaces was
            # made before the tone curve and sat 11 points darker.
            rows_per_m = h / (4.0 * h / face_px)
            crest_a = crest(band_rgb, band_a, rows_per_m)
            Image.fromarray(np.dstack([
                band_rgb, np.clip(crest_a * 255, 0, 255)]).astype(np.uint8), "RGBA"
            ).save(OUT / f"{name}_crest.png")

            lum = band_rgb @ W
            op = band_a > 0.5
            face_lum = float(lum[fy0:fy1][op[fy0:fy1]].mean())
            report[name] = {
                "size": [int(band_rgb.shape[1]), int(h)],
                "lip_px": int(fy0), "face_px": int(face_px),
                "scree_px": int(h - fy1),
                # At a 4.0 m face -- the owner's confirmed cliff height -- these
                # are the metres the recipe has to carry.
                "lip_m": round(4.0 * fy0 / face_px, 3),
                "face_m": 4.0,
                "scree_m": round(4.0 * (h - fy1) / face_px, 3),
                "strip_m": round(4.0 * h / face_px, 3),
                "face_luminance": round(face_lum, 1),
                "separation_from_grass": round(abs(face_lum - 139.4), 1),
                "crest_m": CREST_METRES,
                "crest_px": int((crest_a > 0.5).any(axis=1).sum()),
                # Columns carrying under a quarter of the tallest one. This is
                # the number the hand cut failed on (27%), and it only shows up
                # once a piece is long enough to cross a hole.
                "crest_thin_cols_pct": round(100.0 * float(
                    ((crest_a > 0.5).sum(axis=0)
                     < 0.25 * max(1, (crest_a > 0.5).sum(axis=0).max())).mean()), 1),
            }
            r = report[name]
            print(f"  {name}: {r['strip_m']:.2f} m tall "
                  f"(lip {r['lip_m']:.2f} / face 4.0 / scree {r['scree_m']:.2f}), "
                  f"face lum {r['face_luminance']}, "
                  f"separation {r['separation_from_grass']}")

    (OUT / "zones.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(f"\n-> {OUT}  ({len(report)} strips + zones.json)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
