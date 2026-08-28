"""Generate one recipe per (unit, player colour) from the base unit recipes.

isobake bakes the player tint INTO the atlas and `isobake build` has no
--set override, so "eight players" means eight recipes per unit, each with its
own `id` (the id names the output directory) and its own `source.player_colour`.

Generated recipes go to tools/recipes/player/, NOT tools/recipes/. bake_batch.ps1
globs *.toml non-recursively, so keeping them in a subdirectory means a normal
full batch does not suddenly grow by 112 recipes; the player batch is run with
`-RecipeDir recipes/player`.

WHY THE COLOURS ARE CONVERTED. game/data/colours.json stores sRGB hex, because
that is what Godot and every colour picker speak. A Blender colour socket's
default_value is LINEAR. Writing 0.84 into the socket for #0043D6's blue channel
would bake a markedly lighter blue than the one the palette was designed around
-- and since colours.json separates its eight hues by CIE L* precisely so that
colour-blind players can tell them apart by lightness, getting lightness wrong is
not a cosmetic miss, it is the whole point missed. So convert here, and write the
hex into the generated file as a comment so the two can be checked against each
other by eye.

The conversion happens HERE rather than in the adapter on purpose: existing
recipes' `player_colour` values are already linear by the adapter's contract, and
changing that contract would silently re-tint every hand-written recipe.
"""

from __future__ import annotations

import json
import re
import shutil
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
RECIPES = REPO / "tools" / "recipes"
OUT = RECIPES / "player"
COLOURS_JSON = REPO / "game" / "data" / "colours.json"

# Every unit recipe that carries player colour.
#
# The five at the end were EXCLUDED from the first two batches because they all
# reported alpha role 'opaque' and took no tint, which would have made eight
# identical atlases apiece. That was the per-actor role bug, not a property of
# the assets: the role was read off the root actor, which for a mounted unit is
# the horse and for the trebuchet is the engine, so the rider was never reached.
# Fixed 2026-08-16 by deciding player colour per material; they tint now.
UNITS = [
    "villager",
    "militia",
    "spearman",
    "archer",
    "monk",
    "swordsman",
    "elite_swordsman",
    "crossbowman",
    "siege_ram",
    "trade_cart",
    "galley",
    "galleon",
    "transport_ship",
    "fishing_ship",
    "scout_cavalry",
    "sword_cavalry",
    "cavalry_archer",
    "knight",
    "trebuchet_deployed",
    # Static siege engines, added 2026-08-16 on the game agent's request. Their
    # roots are opaque and they tint at all only because player colour is now
    # decided per material -- the same fix that unblocked the cavalry.
    #
    # `ballista` is deliberately NOT here: measured 0.0% of the sprite moving
    # between white and blue, so eight bakes would be eight identical atlases.
    #
    # The cause is the LITHOBOLOS ART SET, not siege engines as a class -- an
    # earlier note here claimed the latter and was wrong, generalised from a
    # scan that only covered lithobolos/ballista/oxybeles/scorpio/polybolos.
    # For the record, measured on the delivered atlases:
    #
    #   siege_ram  6.8% tinted   its actor IS player_trans_norm_spec
    #   onager     7.1% tinted   via crew props that carry a mask
    #   ballista   0.0%          no_trans_parallax_spec, and the props it
    #                            mounts carry no mask either
    #
    # So always MEASURE before deciding a unit cannot take colour. Reading the
    # root material is not enough in either direction: the onager's root is
    # opaque and it tints anyway, and the ballista's props are player_trans and
    # it does not.
    "onager",
    # Not a unit at all -- the rally/waypoint marker, added on the owner's
    # request 2026-08-27. It belongs here because this list is really "things
    # that get one atlas per player colour", and a marker whose entire job is to
    # say WHOSE it is needs that more than most.
    #
    # 75.4% of the sprite tints (4881 opaque px, 3681 moved > 64), which is the
    # highest in the project by a wide margin -- it is nearly all banner cloth.
    # Measured the same way as everything above, because the actor's
    # player_trans material would still not have proved it.
    "waypoint_flag",
]


def srgb_to_linear(c: float) -> float:
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hex_to_linear(hex_colour: str) -> tuple[float, float, float]:
    h = hex_colour.lstrip("#")
    srgb = [int(h[i : i + 2], 16) / 255.0 for i in (0, 2, 4)]
    return tuple(round(srgb_to_linear(c), 6) for c in srgb)


def load_colours() -> list[dict]:
    data = json.loads(COLOURS_JSON.read_text(encoding="utf-8"))
    out = []
    for index, entry in enumerate(data["colours"]):
        out.append(
            {
                "slot": index + 1,
                # "colour.blue" -> "blue"
                "key": entry["id"].split(".", 1)[1],
                "name": entry["name"],
                "hex": entry["hex"],
                "linear": hex_to_linear(entry["hex"]),
            }
        )
    return out


def variant(text: str, unit: str, colour: dict) -> str:
    """Rewrite one base recipe into one colour variant.

    A text splice rather than a parse-and-re-emit: the base recipes carry a lot
    of hard-won commentary (which actor was rejected and why, which canvas was
    calibrated against what) and a round-trip through a TOML writer would throw
    all of it away.
    """
    key, name, hex_colour = colour["key"], colour["name"], colour["hex"]
    r, g, b = colour["linear"]

    # `id` names the output directory, so it must be unique per variant. Read
    # the existing id rather than assuming it matches the filename -- it does not
    # always: trebuchet_deployed.toml declares `id = "vis.trebuchet"`.
    match = re.search(r'(?m)^\s*id\s*=\s*"([^"]+)"', text)
    if match is None:
        raise SystemExit(f"{unit}: no `id` found")
    base_id = match.group(1)
    text = (
        text[: match.start(1)] + f"{base_id}.{key}" + text[match.end(1) :]
    )

    if re.search(r"(?m)^\s*player_colour\s*=", text):
        raise SystemExit(f"{unit}: already sets player_colour; refusing to guess")

    # `variant_seed` PINS THE VARIANT ROLL TO THE BASE RECIPE, and without it the
    # eight colours of one unit are not the same unit.
    #
    # 0 A.D. actors carry <group>s of interchangeable <variant>s -- an archer has
    # groups of 14 and 15 heads and helmets -- and the importer picks one per
    # group with `random.randint` when the first declares no frequency. isobake
    # seeds that RNG from the recipe id so a rebake reproduces its own output
    # (zeroad.py `_import_actor`). Correct for a base recipe; WRONG here, because
    # every colour recipe has a DIFFERENT id by construction, so each of the eight
    # rolled its own kit. 14 of the 21 colourable units have an ambiguous group.
    #
    # Mostly that was invisible -- two helmets can have identical pixel counts --
    # which is exactly why it survived. `vis.fishing_ship` is where it showed:
    # celts/fishing_boat.xml has a six-variant group and three of them attach fish
    # props, so blue and orange came out 0.84% short of the other six and failed
    # `check_colour_consistency.py` on every run for a fortnight. It was blamed on
    # the parallel-slot race and then on missing variant pinning; it was neither.
    # Proved 2026-08-28 by baking one actor six times changing ONLY the seed:
    # `vis.fishing_ship`/`.blue`/`.orange` give 6498 opaque px and `.red`/`.white`/
    # `.green` give 6551 -- the same two-way split, and the same two colours, that
    # the staged atlases show.
    #
    # Seeding every colour with the BASE id also makes the eight agree with the
    # base bake, which is what the game falls back to when a colour is missing.
    text, n = re.subn(
        r"(?m)^(\[source\]\s*$)",
        r"\g<1>\n"
        f"# Player {colour['slot']} ({name}, {hex_colour}). Generated by\n"
        "# tools/gen_player_colour_recipes.py -- edit that, not this.\n"
        f'variant_seed = "{base_id}"\n'
        f"player_colour = [{r}, {g}, {b}]",
        text,
        count=1,
    )
    if n != 1:
        raise SystemExit(f"{unit}: expected exactly one [source] table, found {n}")

    header = (
        f"# GENERATED FILE -- do not edit. Source: tools/recipes/{unit}.toml\n"
        f"# Player {colour['slot']}: {name} {hex_colour} "
        f"(linear {r}, {g}, {b})\n"
        f"# Regenerate: python tools/gen_player_colour_recipes.py\n\n"
    )
    return header + text


def main() -> None:
    colours = load_colours()

    # Wiped rather than merged: a stale variant from a colour that was renamed
    # or a unit that was dropped would otherwise sit in the batch forever.
    #
    # Files are unlinked individually rather than rmtree'd. The repo lives in a
    # Google Drive folder and the sync client holds a handle on the DIRECTORY,
    # so removing the directory itself fails with WinError 5 while deleting its
    # contents is fine.
    OUT.mkdir(parents=True, exist_ok=True)
    for old in OUT.glob("*.toml"):
        old.unlink()

    written = 0
    for unit in UNITS:
        base = RECIPES / f"{unit}.toml"
        if not base.exists():
            raise SystemExit(f"missing base recipe: {base}")
        text = base.read_text(encoding="utf-8")
        for colour in colours:
            target = OUT / f"{unit}__{colour['key']}.toml"
            target.write_text(variant(text, unit, colour), encoding="utf-8")
            written += 1

    print(f"{written} recipes -> {OUT}")
    print(f"  {len(UNITS)} units x {len(colours)} colours")
    for colour in colours:
        r, g, b = colour["linear"]
        print(
            f"  player {colour['slot']}  {colour['name']:<7} {colour['hex']}"
            f"  -> linear [{r}, {g}, {b}]"
        )


if __name__ == "__main__":
    main()
