#!/usr/bin/env python3
"""Did every colour variant of a unit import the SAME geometry? Run before staging.

THE DEFECT THIS EXISTS FOR. The Pyrogenesis importer rewrites every `.dae` it
loads, in place. isobake restores each file afterwards, but that restore is shared
between parallel bake slots, so a slot reading a mesh while another rewrites it
**imports fewer objects and says nothing**. The bake reports `ok`, the frames pack
cleanly, the tint lands on the right pixels, and the atlas is internally
consistent. On 2026-08-17 `onager__blue` came out of a 2-wide batch with one of its
three crew missing -- 5% of the sprite -- and only a fill percentage 3 points off
its siblings gave it away.

Colour variants are the worst case for that race: all eight of a unit load an
IDENTICAL mesh set, so every pair of slots collides on every file. A batch of eight
unrelated units mostly does not.

TWO CHECKS, AND WHY THE REFERENCE IS THE MAXIMUM OVER THE COLOURS. The race can
only ever LOSE objects -- nothing about it invents geometry -- so a unit's true
count is the highest any of its eight colours reports, and anything below that is
short. The reference is deliberately taken over the COLOURS ALONE and never
includes the base bake: the eight are generated from one recipe and baked in one
run, so they are comparable by construction, where the base is often months older
and made by different isobake code. `vis.swordsman`'s base imports 21 objects and
all eight of its colours import 20, which is that, not damage.

    objects   `N object(s) imported` from each bake's own `_result.json`, which
              isobake leaves beside the atlas. Cheap and it names the defect
              directly, but it counts EMPTIES, armature shells and coincident
              duplicate meshes, so a difference is not necessarily visible --
              `vis.fishing_ship` loses a 0-bone shell and a duplicate hull mesh
              between two colours and renders identically. Reported as WARN.
    pixels    Opaque pixels summed over a unit's pages, which must be EQUAL across
              eight bakes that differ only in tint. Slower (it reads every page),
              and it is the verdict: it measures the artefact the game loads.
              Reported as SHORT. --pixels.

    python tools/check_colour_consistency.py                # object counts, from art_work/out
    python tools/check_colour_consistency.py --pixels        # also compare pages
    python tools/check_colour_consistency.py --staged        # audit what is staged instead

Exits 1 if any variant is short, so it can gate a staging step.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import tomllib
from collections import defaultdict
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
RECIPES = REPO / "tools" / "recipes"
STAGED = REPO / "game" / "assets" / "atlases"
LOCAL_CONFIG = REPO / "tools" / "isobake.local.toml"

#: `_result.json` note the Blender half writes once per bake.
OBJECTS_NOTE = re.compile(r"(\d+) object\(s\) imported")

#: Edge antialiasing is sampled, so two renders of one mesh disagree by a few
#: pixels. A lost prop is orders of magnitude larger -- the onager's crew member
#: was 5.1%, the archer's 4.9-6.4%. Anything under this is noise.
PIXEL_TOLERANCE_PCT = 0.5


def out_root() -> Path | None:
    """Where isobake writes. Machine-local, so it is never committed."""
    if not LOCAL_CONFIG.exists():
        return None
    with LOCAL_CONFIG.open("rb") as fh:
        data = tomllib.load(fh)
    raw = data.get("paths", {}).get("out")
    return Path(raw) if raw else None


def colour_families() -> dict[str, list[str]]:
    """Base id -> its colour variant ids, read from the generated recipes.

    From the recipes rather than by listing directories, for the reason
    `stage_atlases.py` gives: the output root also accumulates probes and
    isobake's own test artefacts, and those are not ours to judge.
    """
    families: dict[str, list[str]] = defaultdict(list)
    for path in sorted((RECIPES / "player").glob("*.toml")):
        with path.open("rb") as fh:
            rid = str(tomllib.load(fh).get("id", "")).strip()
        if not rid:
            continue
        base = rid.rsplit(".", 1)[0]
        families[base].append(rid)
    return dict(families)


def imported_objects(result: Path) -> int | None:
    """The object count this bake recorded, or None if it never wrote one."""
    try:
        with result.open("rb") as fh:
            notes = json.load(fh).get("notes", [])
    except (OSError, json.JSONDecodeError):
        return None
    for note in notes:
        found = OBJECTS_NOTE.search(str(note))
        if found:
            return int(found.group(1))
    return None


def opaque_pixels(atlas: Path) -> int | None:
    """Opaque pixels over every page this atlas names.

    Alpha only, so it is independent of the tint -- which is the entire point:
    eight bakes that differ only in colour must agree here exactly. Counted from
    the alpha histogram rather than pixel by pixel, and without numpy, to keep
    this runnable with nothing but Pillow.
    """
    from PIL import Image

    try:
        with atlas.open("rb") as fh:
            pages = json.load(fh)["pages"]
    except (OSError, json.JSONDecodeError, KeyError):
        return None

    total = 0
    for page in pages:
        path = atlas.parent / page
        if not path.exists():
            return None
        with Image.open(path) as img:
            alpha = img.convert("RGBA").getchannel("A")
        # >8 rather than >0: a fully transparent pixel can carry a stray 1 or 2
        # from the downsample of an antialiased edge.
        total += sum(alpha.histogram()[9:])
    return total


def atlas_dir(root: Path, rid: str, staged: bool) -> Path:
    return root if staged else root / rid


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--pixels", action="store_true", help="also compare opaque pixels over the pages"
    )
    parser.add_argument(
        "--staged", action="store_true", help="read game/assets/atlases instead of the bake output"
    )
    args = parser.parse_args()

    root = STAGED if args.staged else out_root()
    if root is None:
        print("no paths.out in tools/isobake.local.toml; nothing to check")
        return 1
    where = "staged atlases" if args.staged else "bake output"
    print(f"checking {where} in {root}\n")

    families = colour_families()
    if not families:
        print("no colour recipes under tools/recipes/player; nothing to check")
        return 1

    short_units = 0
    warn_units = 0
    for base in sorted(families):
        counts: dict[str, int] = {}
        pixels: dict[str, int] = {}
        for rid in sorted(families[base]):
            directory = atlas_dir(root, rid, args.staged)
            # A family can legitimately be mid-bake or not baked at all. Absent is
            # not short.
            if not args.staged:
                n = imported_objects(directory / "_result.json")
                if n is not None:
                    counts[rid] = n
            if args.pixels:
                p = opaque_pixels(directory / f"{rid}.atlas.json")
                if p is not None:
                    pixels[rid] = p

        # SHORT: the pages themselves disagree, so the staged art is wrong.
        short: list[str] = []
        if pixels:
            hi = max(pixels.values())
            for rid, n in sorted(pixels.items()):
                pct = 100.0 * (hi - n) / hi if hi else 0.0
                if pct > PIXEL_TOLERANCE_PCT:
                    short.append(f"{rid:28} {n:9} px, {pct:5.2f}% short of {hi}")

        # WARN: the imports disagreed. Real, but possibly invisible -- see the
        # module docstring on what an object count includes.
        warn: list[str] = []
        if counts:
            expected = max(counts.values())
            for rid, n in sorted(counts.items()):
                if n < expected:
                    warn.append(
                        f"{rid:28} {n:6} objects, {expected - n} fewer than the "
                        f"{expected} its siblings import"
                    )

        summary = f"{len(counts) or len(pixels)} colour bake(s)"
        if short:
            short_units += 1
            print(f"SHORT {base:24} {summary}  -- the pages disagree")
        elif warn:
            warn_units += 1
            print(f"WARN  {base:24} {summary}  -- imports disagreed")
        else:
            print(f"ok    {base:24} {summary}")
        for line in short + warn:
            print(f"        {line}")

        # The base bake for context only, never as the reference: it is usually
        # older than the colours and made by different code, so a uniform
        # difference between it and all eight is a version gap, not damage.
        if counts and not args.staged:
            base_n = imported_objects(atlas_dir(root, base, args.staged) / "_result.json")
            if base_n is not None and base_n not in set(counts.values()):
                print(
                    f"        (for context: the base bake imports {base_n}, and all "
                    f"{len(counts)} colours agree on {max(counts.values())} -- "
                    f"rebake the base if you want them comparable)"
                )

    print(
        f"\n{len(families)} colourable unit(s): {short_units} with pages that "
        f"disagree, {warn_units} where only the import counts did"
    )
    if short_units or warn_units:
        print(
            "Rebake the flagged variants at -Parallel 1 and re-run; confirm a WARN with\n"
            "--pixels before spending the time. This is the parallel-slot import race,\n"
            "not a colour problem: see AGENT_ASSET.md 4."
        )
    return 1 if (short_units or warn_units) else 0


if __name__ == "__main__":
    sys.exit(main())
