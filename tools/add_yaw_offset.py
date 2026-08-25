"""Add `yaw_offset_deg = 180.0` to every zeroad recipe that lacks it.

WHY. The zeroad adapter renders every subject 180 degrees from the direction the
atlas then labels it, so a recipe without this line bakes a subject that faces
away from wherever the game points it. It was found first in the `directions = 1`
buildings, which show a blank rear wall instead of an entrance, and compensated
there one recipe at a time -- 82 of them. On 2026-08-22 the game side put eight
unit directions side by side in `preview_facing_chart` and found the units are
180 out too: column 0 (south, toward the camera) draws the swordsman's BACK.

The previous belief was that characters were exempt because their base yaw
already faced them screen-down. That was wrong, and being wrong in a plausible
way is how every unit, ship, animal and siege engine shipped facing backwards for
months while the buildings were fixed one by one. Do not re-derive that exemption.

WHY IT IS NOT A DEFAULT IN ISOBAKE. `RenderSpec.yaw_offset_deg` lives in the
generic recipe layer, not in the zeroad adapter, so flipping its default would
impose a 0 A.D. quirk on every other adapter. Changing that properly means making
the default adapter-dependent, which is a layering change and not something to do
in the same pass as a 249-bake batch. Until then the compensation is per recipe,
and this script is how it stays complete.

IDEMPOTENT. A recipe that already sets the key is left exactly as it is --
including `prop_shrine_celtic.toml`, which deliberately sets 45.0.

    python tools/add_yaw_offset.py [--dry-run]

Run `python tools/gen_player_colour_recipes.py` afterwards: the colour variants
are generated from these files as text, so they inherit the line, but only once
they are regenerated.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

RECIPES = Path(__file__).resolve().parent / "recipes"

NOTE = (
    "# The zeroad adapter renders every subject 180 deg from the direction the\n"
    "# atlas then labels it; this cancels it. Added 2026-08-25 -- asset_request.md P2.\n"
    "yaw_offset_deg = 180.0\n"
)


def patch(text: str) -> str | None:
    """Return the rewritten recipe, or None if it already sets the key."""
    if re.search(r"(?m)^\s*yaw_offset_deg\s*=", text):
        return None

    lines = text.splitlines(keepends=True)
    try:
        start = next(i for i, ln in enumerate(lines) if ln.strip() == "[render]")
    except StopIteration:
        return None  # no [render] block: not a bakeable recipe, leave it alone

    # End of the [render] block: the next top-level table header, or EOF. Back up
    # over trailing blank lines so the new key joins the block rather than
    # floating between two sections.
    end = len(lines)
    for i in range(start + 1, len(lines)):
        if lines[i].lstrip().startswith("["):
            end = i
            break
    while end > start + 1 and not lines[end - 1].strip():
        end -= 1

    return "".join(lines[:end]) + NOTE + "".join(lines[end:])


def main() -> None:
    dry = "--dry-run" in sys.argv
    changed, skipped, norender = [], [], []

    for path in sorted(RECIPES.glob("*.toml")):
        text = path.read_text(encoding="utf-8")
        out = patch(text)
        if out is None:
            (skipped if re.search(r"(?m)^\s*yaw_offset_deg\s*=", text) else norender).append(path.name)
            continue
        changed.append(path.name)
        if not dry:
            path.write_text(out, encoding="utf-8")

    print(f"  already set : {len(skipped)}")
    print(f"  no [render] : {len(norender)}" + (f"  {norender}" if norender else ""))
    print(f"  {'would patch' if dry else 'patched'}     : {len(changed)}")
    for name in changed:
        print(f"      {name}")
    if changed and not dry:
        print("\n  now run: python tools/gen_player_colour_recipes.py")


if __name__ == "__main__":
    main()
