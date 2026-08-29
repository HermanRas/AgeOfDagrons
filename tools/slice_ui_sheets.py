"""Cut the Gemini UI sheets in `assets/UI_Gen` into keyed RGBA PNGs.

Run with the venv python (see AGENT_ASSET.md 2); nothing here is on PATH.

    <venv>\\python.exe tools\\slice_ui_sheets.py [--out assets/UI_Gen/sliced]

WHY THIS IS NOT A LATTICE CROP, which is what the plan assumed it would be.
Gemini does not centre its cells on a strict 256 px grid, and it does not keep
the artwork inside them: the dragon on `sheet_widgets` cell 1 runs off the top
of the canvas and the selected frame's glow bleeds into its neighbour. A blind
`crop(c*256, r*256, ...)` clips the dragon heads off three of the four frames.
So the lattice only ASSIGNS a piece to a slot; the crop is the piece's own
content bounding box, grown out of the cell it was assigned to.

WHY THE BACKGROUND IS REMOVED BY FLOOD FILL AND NOT BY A THRESHOLD, which is
the part that actually matters. Half these icons contain large genuinely dark
regions -- `act_repair`'s black anvil, the dark openings of `act_enter` and
`act_exit`, `act_garrison`'s shadowed archway. A global `luma < t` key punches
holes straight through them. The background is not "the dark pixels", it is
"the dark pixels REACHABLE FROM THE BORDER", and only a fill can tell those
apart from a dark pixel enclosed by artwork.

The threshold is derived per sheet rather than fixed, because the sheets do not
agree on what black is: `sheet_a_command_verbs` came back on a uniform #111111
ground (border p99.5 = 18) where every other sheet is a true #000000 (p99.5 = 2).
One constant would either leak into the artwork on one sheet or leave a grey
mat on the other.

ON THE SOURCE BEING JPEG. It is fine, and it is worth writing down why so the
question does not get re-litigated. JPEG's failure mode is ringing at hard
edges between flat colours -- which is pixel art, and this is not. Smooth
gradients on a flat ground are the case it handles best, the measured border
noise is under 6/255 on twelve of the fourteen sheets, and every icon is
downsampled 256 -> 100 on the way out, which averages what ringing there is
below the point of visibility. What must NOT happen is a second JPEG round
trip, so everything this writes is PNG and the masters are kept.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

# ── what is in each sheet, in reading order ─────────────────────────────────
#
# Ids are the filenames the game will load, minus `.png`. The order is the
# order of the prompt in ART_PROMPT.md, which is the order Gemini drew them;
# `verify_slices.py` is what checks that claim rather than trusting it.

GRID_SHEETS: dict[str, tuple[int, int, list[str]]] = {
    # sheet: (rows, cols, ids)
    "sheet_a_command_verbs": (4, 4, [
        "act_move", "act_stop", "act_attack", "act_build",
        "act_repair", "act_harvest", "act_destroy", "act_garrison",
        "act_enter", "act_exit", "act_leave", "act_upgrade",
        "act_research", "act_stance", "ui_close",
    ]),
    "sheet_b_resources_and_hud": (4, 4, [
        "res_food", "res_wood", "res_gold", "res_stone",
        "res_villagers", "res_idle", "hud_chat", "hud_trade",
        "hud_techtree", "hud_settings", "hud_score", "hud_menu",
        "hud_pause", "hud_alert", "hud_volume",
    ]),
    "sheet_c_formations_stances_ages": (4, 4, [
        "form_line", "form_grid", "form_vee", "form_box",
        "stance_aggressive", "stance_defensive", "stance_stand_ground",
        "stance_passive",
        "abil_heal", "abil_fire_breath", "age_1", "age_2",
        "age_3", "age_4", "age_advance",
    ]),
    # Rows 1-3 are the four blacksmith ladders read DOWN the columns, which is
    # how the age-4 research grid puts them on screen. Reading order here is
    # therefore across the ladders, not along them -- that is not a mistake.
    "sheet_d_military_techs": (4, 4, [
        "tech_forging", "tech_fletching", "tech_scale_mail", "tech_padded_armour",
        "tech_iron_casting", "tech_bodkin_arrow", "tech_chain_mail",
        "tech_leather_armour",
        "tech_blast_furnace", "tech_bracer", "tech_plate_mail", "tech_ring_armour",
        "tech_ballistics", "tech_chemistry", "tech_generic",
    ]),
    "sheet_e_economy_techs": (4, 4, [
        "tech_wheelbarrow", "tech_hand_cart", "tech_horse_collar",
        "tech_heavy_plough",
        "tech_crop_rotation", "tech_double_bit_axe", "tech_bow_saw",
        "tech_gold_mining",
        "tech_stone_mining", "tech_gold_shaft_mining", "tech_stone_shaft_mining",
        "tech_sanctity",
        "tech_fervour",
    ]),
    "sheet_f_multiplayer_and_voice": (4, 4, [
        "mic_on", "mic_muted", "voice_on", "voice_muted",
        "chat_send", "chat_clear", "net_refresh", "net_join",
        "net_host", "net_filter", "lobby_faction", "lobby_team",
        "lobby_gametype", "lobby_victory", "lobby_mapsize",
    ]),
    "sheet_g_system_and_modes": (4, 4, [
        "file_save", "file_load", "file_delete", "replay_play",
        "replay_pause", "replay_step", "pack_download", "pack_retry",
        "victory_regicide", "victory_trophy", "transport_load",
        "transport_unload",
        "act_pack", "act_unpack", "ui_confirm",
    ]),
    "sheet_widgets": (4, 4, [
        "tile_frame", "tile_frame_selected", "tile_frame_disabled",
        "portrait_frame",
        "group_slot_ring", "badge_round", "checkbox_off", "checkbox_on",
        "radio_off", "radio_on", "arrow_down", "arrow_up",
        "arrow_left", "arrow_right", "tab_plate",
    ]),
}

# `sheet_bars` IS NOT A LATTICE AND CANNOT BE TREATED AS ONE. The prompt asked
# for seven 128 px rows with an empty band at the bottom; Gemini spread seven
# bars of unequal height over the whole canvas with unequal gaps, so `h // 7`
# lands mid-bar four times out of seven and the seventh row of the lattice falls
# entirely inside the empty band -- which is why `field_input` came back EMPTY
# and four of its neighbours came back BLED on the first run.
#
# Bars are separated by clear horizontal gaps, so a row projection finds them
# exactly and needs no guess about how tall each one is.
BAND_SHEETS: dict[str, list[str]] = {
    "sheet_bars": [
        "button_normal", "button_pressed", "button_disabled",
        "bar_groove", "bar_fill_health", "bar_fill_progress", "field_input",
    ],
}

# Which sheets produce square 100x100 game icons, and which produce chrome that
# keeps its own aspect. `ResourceHUD`'s comment is the reason the icons are
# pinned to a size at all: a TextureRect's minimum size comes from the texture's
# real pixels, so 100x100 is a contract with the twenty already shipped.
ICON_SHEETS = {
    "sheet_a_command_verbs", "sheet_b_resources_and_hud",
    "sheet_c_formations_stances_ages", "sheet_d_military_techs",
    "sheet_e_economy_techs", "sheet_f_multiplayer_and_voice",
    "sheet_g_system_and_modes",
}

# Full-canvas pieces. `keyed` says whether the background is removed: a panel
# fills its canvas and has no background to remove, a minimap frame is a hole in
# the middle of one and very much does.
FULL_CANVAS: dict[str, bool] = {
    "panel_ornate": False,
    "panel_hud": False,
    "banner_alert": True,
    "banner_age": True,
    "frame_minimap": True,
}

ICON_PX = 100
MASTER_PX = 256
PAD_FRAC = 0.06          # breathing room around the content bbox

# ── icons drawn with a deliberate GLOW ──────────────────────────────────────
#
# A GLOW ON BLACK CANNOT BE KEYED BY A FLOOD FILL, and the reason is not a bug
# in the fill: a glow IS partial transparency, and compositing it over black
# already destroyed the information that says so. The fill can only answer
# "background or not", so it keeps the whole falloff as opaque and the icon
# ships with a black disc around it. That is what `abil_heal` was reported for.
#
# TWO AUTOMATIC DISCRIMINATORS WERE TRIED AND BOTH FAILED ON MEASUREMENT, which
# is why this is a hand-written list and not a heuristic:
#
#   luma        the halo runs p25/p50 = 20/29 and `act_repair`'s black anvil
#               runs 38/45. Any ramp that feathers the glow makes the anvil
#               half transparent.
#   edge energy the halo is featureless (p90 = 5.2) where the anvil has facets
#               and an outline (p90 = 35.3) -- but the anvil's FLATTEST pixels
#               (p10 = 1.0) are flatter than the glow's (p10 = 2.6), so a
#               per-pixel cut punches holes in the anvil instead.
#
# The list wins because it uses information the image does not carry:
# ART_PROMPT.md SPECIFIED which cells get a glow, so this is read off the
# prompt rather than guessed from the pixels. Add an id here if a cell is
# regenerated with a bloom; the ramp is safe only where the icon has no large
# dark subject, which is true of every glow the prompts asked for (a gold
# cross, a gold chevron, a gold frame).
GLOW_ICONS = {
    "abil_heal",        # "a soft warm white glow blooming behind it"
    "age_advance",      # "a bright starburst behind its point"
}
GLOW_CAP_OFFSET = 90     # luma above threshold at which the glow is fully opaque


def luma(rgb: np.ndarray) -> np.ndarray:
    """Max channel, not a weighted luminance.

    A saturated dark red -- `act_destroy`'s cross, the health bar -- has a low
    perceptual luminance and is emphatically not background. Taking the max
    channel asks "is any channel lit?", which is the question being put.
    """
    return rgb.max(axis=2)


def background_threshold(lum: np.ndarray) -> int:
    """A per-sheet cut, from what the border actually looks like."""
    border = np.concatenate([
        lum[0, :], lum[-1, :], lum[:, 0], lum[:, -1],
    ])
    return int(min(40, max(10, np.percentile(border, 99.5) + 8)))


def fill_from_border(dark: np.ndarray) -> np.ndarray:
    """Pixels of `dark` connected to the image border, 4-connected.

    Iterated dilation constrained to `dark`, rather than a recursive fill:
    numpy does the whole frontier in one shift-and-or, and a 1024x1024 sheet
    converges in a few hundred passes. A recursive fill in Python blows the
    stack on an image this size, and that is the only reason this is written
    out longhand.
    """
    seed = np.zeros_like(dark)
    seed[0, :] = dark[0, :]
    seed[-1, :] = dark[-1, :]
    seed[:, 0] = dark[:, 0]
    seed[:, -1] = dark[:, -1]

    cur = seed
    for _ in range(4096):
        grown = cur.copy()
        grown[1:, :] |= cur[:-1, :]
        grown[:-1, :] |= cur[1:, :]
        grown[:, 1:] |= cur[:, :-1]
        grown[:, :-1] |= cur[:, 1:]
        grown &= dark
        if np.array_equal(grown, cur):
            return cur
        cur = grown
    return cur


def grow_within(seed: np.ndarray, allowed: np.ndarray, limit: int = 4096) -> np.ndarray:
    """Same primitive, seeded from a region instead of from the border."""
    cur = seed & allowed
    for _ in range(limit):
        grown = cur.copy()
        grown[1:, :] |= cur[:-1, :]
        grown[:-1, :] |= cur[1:, :]
        grown[:, 1:] |= cur[:, :-1]
        grown[:, :-1] |= cur[:, 1:]
        grown &= allowed
        if np.array_equal(grown, cur):
            return cur
        cur = grown
    return cur


def dilate(mask: np.ndarray, n: int = 1) -> np.ndarray:
    cur = mask
    for _ in range(n):
        g = cur.copy()
        g[1:, :] |= cur[:-1, :]
        g[:-1, :] |= cur[1:, :]
        g[:, 1:] |= cur[:, :-1]
        g[:, :-1] |= cur[:, 1:]
        cur = g
    return cur


def own_components(fg: np.ndarray, cell: tuple[int, int, int, int],
                   reach: int = 128) -> np.ndarray:
    """Every blob BELONGING to one cell, by centroid.

    THE TIER PIPS ARE A SEPARATE CONNECTED COMPONENT AND THAT IS WHAT BROKE
    `tech_bracer`. ART_PROMPT.md asked for "small gold pips in the lower right",
    and Gemini drew several of them detached from the glyph. Growing outward
    from the cell centre therefore found the bracer and not its three pips, so
    the bounding box came out at 77% of the cell where its siblings are 90-99%,
    and the square crop taken around that undersized box sliced the pips in half
    -- which reads as the icon being cut off, because it is.

    The same defect from the other side is the edge artefact on
    `tech_blast_furnace`: a NEIGHBOUR's pips fall inside this icon's crop
    rectangle. Cropping a rectangle keeps whatever is in it.

    So ownership is decided per blob, by which cell its centroid lands in, and
    the alpha is masked to the blobs this cell owns. A detached pip inside the
    cell is kept; a neighbour's pip overlapping the crop is dropped. Both
    symptoms are the one bug: the bounding box was being treated as the icon.
    """
    y0, x0, y1, x1 = cell
    h, w = fg.shape

    win = np.zeros_like(fg)
    win[max(0, y0 - reach):min(h, y1 + reach),
        max(0, x0 - reach):min(w, x1 + reach)] = True
    allowed = fg & win

    core = np.zeros_like(fg)
    ch, cw = y1 - y0, x1 - x0
    core[y0 + int(ch * 0.2):y0 + int(ch * 0.8),
         x0 + int(cw * 0.2):x0 + int(cw * 0.8)] = True

    own = grow_within(core & allowed, allowed)

    # Anything else inside the CELL is a detached blob; keep it if its centre
    # of mass is in this cell, drop it if it belongs to a neighbour.
    cell_mask = np.zeros_like(fg)
    cell_mask[y0:y1, x0:x1] = True
    left = allowed & cell_mask & ~own

    while left.any():
        ys, xs = np.nonzero(left)
        seed = np.zeros_like(fg)
        seed[ys[0], xs[0]] = True
        comp = grow_within(seed, allowed)
        cy, cx = np.nonzero(comp)
        if y0 <= cy.mean() < y1 and x0 <= cx.mean() < x1:
            own |= comp
        left &= ~comp
    return own


def box_blur3(a: np.ndarray) -> np.ndarray:
    """One 3x3 box pass, for a single pixel of edge anti-aliasing."""
    p = np.pad(a, 1, mode="edge")
    out = np.zeros_like(a, dtype=np.float32)
    for dy in (0, 1, 2):
        for dx in (0, 1, 2):
            out += p[dy:dy + a.shape[0], dx:dx + a.shape[1]]
    return out / 9.0


def key_background(rgb: np.ndarray) -> tuple[np.ndarray, np.ndarray, int]:
    """RGB in, (rgb unpremultiplied, alpha 0..1, threshold used) out."""
    lum = luma(rgb)
    thresh = background_threshold(lum)
    bg = fill_from_border(lum <= thresh)

    alpha = box_blur3((~bg).astype(np.float32))
    # The source was composited over black, so an edge pixel is already
    # colour*coverage. Dividing it back out is what stops a dark fringe
    # appearing when the icon is finally drawn over a lit panel.
    safe = np.maximum(alpha, 1e-3)[..., None]
    out = np.clip(rgb.astype(np.float32) / safe, 0, 255)
    return out, alpha, thresh


def content_bbox(mask: np.ndarray) -> tuple[int, int, int, int] | None:
    ys, xs = np.nonzero(mask)
    if ys.size == 0:
        return None
    return int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1


def square_pad(box: tuple[int, int, int, int], w: int, h: int, pad_frac: float):
    x0, y0, x1, y1 = box
    side = max(x1 - x0, y1 - y0)
    side = int(round(side * (1.0 + 2 * pad_frac)))
    cx, cy = (x0 + x1) / 2.0, (y0 + y1) / 2.0
    nx0 = int(round(cx - side / 2.0))
    ny0 = int(round(cy - side / 2.0))
    return nx0, ny0, nx0 + side, ny0 + side


def to_image(rgb: np.ndarray, alpha: np.ndarray) -> Image.Image:
    rgba = np.dstack([rgb.astype(np.uint8), (alpha * 255).astype(np.uint8)])
    return Image.fromarray(rgba, "RGBA")


def crop_padded(im: Image.Image, box) -> Image.Image:
    """Crop that tolerates a box running off the canvas, filling with alpha 0."""
    x0, y0, x1, y1 = box
    out = Image.new("RGBA", (x1 - x0, y1 - y0), (0, 0, 0, 0))
    sx0, sy0 = max(0, x0), max(0, y0)
    sx1, sy1 = min(im.width, x1), min(im.height, y1)
    if sx1 > sx0 and sy1 > sy0:
        out.paste(im.crop((sx0, sy0, sx1, sy1)), (sx0 - x0, sy0 - y0))
    return out


def checkerboard(size: tuple[int, int], step: int = 16) -> Image.Image:
    w, h = size
    a = np.zeros((h, w, 3), dtype=np.uint8)
    yy, xx = np.mgrid[0:h, 0:w]
    a[...] = np.where((((yy // step) + (xx // step)) % 2)[..., None], 210, 170)
    return Image.fromarray(a, "RGB")


def slice_grid(src: Path, rows: int, cols: int, ids: list[str], out: Path,
               as_icon: bool, report: list[dict]) -> list[Image.Image]:
    rgb = np.asarray(Image.open(src).convert("RGB")).astype(np.int16)
    h, w = rgb.shape[:2]
    keyed_rgb, alpha, thresh = key_background(rgb)
    fg = alpha > 0.5
    full = to_image(keyed_rgb, alpha)

    ch, cw = h // rows, w // cols
    pieces: list[Image.Image] = []

    for i, ident in enumerate(ids):
        r, c = divmod(i, cols)
        y0, x0 = r * ch, c * cw
        grown = own_components(fg, (y0, x0, y0 + ch, x0 + cw))
        box = content_bbox(grown)
        if box is None:
            report.append({"id": ident, "sheet": src.stem, "status": "EMPTY"})
            continue

        bw, bh = box[2] - box[0], box[3] - box[1]
        # A piece that has grown far wider than its cell has bridged into its
        # neighbour -- `tile_frame_selected`'s glow is the case that does it.
        bled = bw > cw * 1.45 or bh > ch * 1.45

        # MASK TO WHAT THIS CELL OWNS, so a neighbour's blob inside the crop
        # rectangle is dropped rather than cropped. Dilated by 2 first, or the
        # masking would shear off the anti-aliased rim that `box_blur3` just
        # built and put a hard jagged edge back on every icon.
        keep = dilate(grown, 2)
        piece_alpha = alpha * keep

        piece_rgb = keyed_rgb
        if ident in GLOW_ICONS:
            # Recover the alpha a glow always had. The falloff was composited
            # over black, so its luminance IS its coverage -- ramping alpha with
            # luma turns the retained black disc back into a bloom that fades
            # out. `minimum` so the bright core keeps the fill's opaque alpha
            # and only the dim surround is softened.
            lum = luma(rgb)
            cap = float(thresh + GLOW_CAP_OFFSET)
            ramp = np.clip((lum - thresh) / max(1.0, cap - thresh), 0.0, 1.0)
            piece_alpha = np.minimum(piece_alpha, ramp.astype(np.float32))
            # AND UN-PREMULTIPLY AGAINST THE NEW ALPHA, not the fill's. Without
            # this the halo keeps the dim colour it had when it was opaque and
            # is then multiplied down again at draw time -- a luma-29 pixel at
            # alpha 0.19 renders at 5, so the bloom all but disappears. Dividing
            # recovers the bright warm colour the glow actually is.
            piece_rgb = np.clip(
                rgb.astype(np.float32) / np.maximum(piece_alpha, 1e-3)[..., None],
                0, 255)

        # A NEW IMAGE PER PIECE, never a rebind of `full`. The mask is specific
        # to this cell, so writing it back over the shared image would carry
        # cell 1's mask into cell 2 and blank most of the sheet.
        piece_full = to_image(piece_rgb, piece_alpha)

        if as_icon:
            crop = crop_padded(piece_full, square_pad(box, w, h, PAD_FRAC))
            crop.resize((MASTER_PX, MASTER_PX), Image.LANCZOS).save(
                out / "masters" / f"{ident}.png")
            piece = crop.resize((ICON_PX, ICON_PX), Image.LANCZOS)
            piece.save(out / "icons" / f"{ident}.png")
        else:
            pad_x = int(round(bw * PAD_FRAC * 0.5))
            pad_y = int(round(bh * PAD_FRAC * 0.5))
            piece = crop_padded(piece_full, (box[0] - pad_x, box[1] - pad_y,
                                             box[2] + pad_x, box[3] + pad_y))
            piece.save(out / "chrome" / f"{ident}.png")

        pieces.append(piece)
        report.append({
            "id": ident, "sheet": src.stem, "status": "BLED" if bled else "ok",
            "bbox": list(box), "w": bw, "h": bh, "threshold": thresh,
            "cell": [cw, ch],
        })
    return pieces


def slice_bands(src: Path, ids: list[str], out: Path,
                report: list[dict]) -> list[Image.Image]:
    """Cut a sheet of full-width horizontal pieces by row projection.

    A row belongs to a bar if a meaningful fraction of it is lit. 5% is well
    above the stray-pixel level and well below the ~95% a real bar occupies, so
    the runs it finds are the bars and the gaps between them are the gaps.
    """
    rgb = np.asarray(Image.open(src).convert("RGB")).astype(np.int16)
    h, w = rgb.shape[:2]
    keyed_rgb, alpha, thresh = key_background(rgb)
    fg = alpha > 0.5
    full = to_image(keyed_rgb, alpha)

    lit = fg.sum(axis=1) > (w * 0.05)
    bands: list[tuple[int, int]] = []
    start = None
    for y, on in enumerate(lit):
        if on and start is None:
            start = y
        elif not on and start is not None:
            bands.append((start, y))
            start = None
    if start is not None:
        bands.append((start, h))
    # Ignore anything too thin to be one of the seven -- JPEG can leave a lit
    # row or two in an otherwise empty gap.
    bands = [b for b in bands if b[1] - b[0] >= 24]

    pieces: list[Image.Image] = []
    if len(bands) != len(ids):
        report.append({"id": src.stem, "sheet": src.stem,
                       "status": f"BANDS {len(bands)} != {len(ids)}",
                       "bands": bands})
        return pieces

    for ident, (y0, y1) in zip(ids, bands):
        box = content_bbox(fg[y0:y1, :])
        if box is None:
            report.append({"id": ident, "sheet": src.stem, "status": "EMPTY"})
            continue
        x0, by0, x1, by1 = box
        piece = full.crop((x0, y0 + by0, x1, y0 + by1))
        piece.save(out / "chrome" / f"{ident}.png")
        pieces.append(piece)
        report.append({"id": ident, "sheet": src.stem, "status": "ok",
                       "bbox": [x0, y0 + by0, x1, y0 + by1],
                       "w": piece.width, "h": piece.height, "threshold": thresh})
    return pieces


def do_full_canvas(src: Path, keyed: bool, out: Path, report: list[dict]) -> None:
    rgb = np.asarray(Image.open(src).convert("RGB")).astype(np.int16)
    if keyed:
        keyed_rgb, alpha, thresh = key_background(rgb)
        im = to_image(keyed_rgb, alpha)
        box = content_bbox(alpha > 0.5)
        if box is not None:
            im = im.crop(box)
        report.append({"id": src.stem, "sheet": src.stem, "status": "ok",
                       "threshold": thresh, "w": im.width, "h": im.height})
    else:
        im = Image.open(src).convert("RGBA")
        report.append({"id": src.stem, "sheet": src.stem, "status": "ok",
                       "threshold": None, "w": im.width, "h": im.height})
    im.save(out / "chrome" / f"{src.stem}.png")


def contact_sheet(pieces: list[Image.Image], cols: int, cell: int) -> Image.Image:
    rows = max(1, (len(pieces) + cols - 1) // cols)
    sheet = checkerboard((cols * cell, rows * cell)).convert("RGBA")
    for i, p in enumerate(pieces):
        r, c = divmod(i, cols)
        fit = p.copy()
        fit.thumbnail((cell - 8, cell - 8), Image.LANCZOS)
        sheet.alpha_composite(
            fit, (c * cell + (cell - fit.width) // 2,
                  r * cell + (cell - fit.height) // 2))
    return sheet


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default="assets/UI_Gen")
    ap.add_argument("--out", default="assets/UI_Gen/sliced")
    args = ap.parse_args()

    src_dir, out = Path(args.src), Path(args.out)
    for sub in ("icons", "masters", "chrome", "review"):
        (out / sub).mkdir(parents=True, exist_ok=True)

    report: list[dict] = []

    for sheet, (rows, cols, ids) in GRID_SHEETS.items():
        path = src_dir / f"{sheet}.jpg"
        if not path.exists():
            path = src_dir / f"{sheet}.png"
        if not path.exists():
            print(f"  MISSING {sheet}")
            continue
        pieces = slice_grid(path, rows, cols, ids, out,
                            sheet in ICON_SHEETS, report)
        contact_sheet(pieces, cols, 256).save(out / "review" / f"{sheet}.png")
        print(f"  {sheet:36s} {len(pieces):2d} pieces")

    for sheet, ids in BAND_SHEETS.items():
        path = src_dir / f"{sheet}.jpg"
        if not path.exists():
            path = src_dir / f"{sheet}.png"
        if not path.exists():
            print(f"  MISSING {sheet}")
            continue
        pieces = slice_bands(path, ids, out, report)
        if pieces:
            gap = 12
            board = checkerboard(
                (1024, sum(p.height for p in pieces) + gap * (len(pieces) + 1))
            ).convert("RGBA")
            y = gap
            for p in pieces:
                board.alpha_composite(p, ((1024 - p.width) // 2, y))
                y += p.height + gap
            board.save(out / "review" / f"{sheet}.png")
        print(f"  {sheet:36s} {len(pieces):2d} pieces")

    for stem, keyed in FULL_CANVAS.items():
        path = src_dir / f"{stem}.jpg"
        if not path.exists():
            path = src_dir / f"{stem}.png"
        if not path.exists():
            print(f"  MISSING {stem}")
            continue
        do_full_canvas(path, keyed, out, report)
        print(f"  {stem:36s}  full canvas, keyed={keyed}")

    (out / "slice_report.json").write_text(
        json.dumps(report, indent=2), encoding="utf-8")

    bad = [r for r in report if r["status"] != "ok"]
    print(f"\n{len(report)} pieces, {len(bad)} needing a look")
    for r in bad:
        print(f"  {r['status']:6s} {r['sheet']}/{r['id']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
