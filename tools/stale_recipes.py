"""Name the recipes whose staged atlas no longer matches the recipe.

WHY THIS IS COMPUTABLE AT ALL. isobake stamps `generator.recipe_sha256` into
every atlas, and that value is `sha256(recipe file bytes)` -- see Recipe.load.
So "has this recipe changed since the atlas was baked" is an exact question with
an exact answer, and it does not need a hand-kept list of pending work that goes
stale the moment somebody edits a recipe without updating it.

IT IS SENSITIVE TO LINE ENDINGS, and that is inherited, not a choice. isobake
hashes the recipe's raw bytes, so a file rewritten CRLF reads as changed even
when every character of its content is identical. Two things do that on Windows
without meaning to: `git checkout` under core.autocrlf, and Python's
`Path.write_text`, whose default translates \n to \r\n. Both have already caused
a false "needs rebaking" here. Recipes in this repo are LF; if this tool reports
a suspiciously round number of stale recipes, check for CRLF before believing it.

WHAT IT DOES NOT CATCH, and the distinction matters. This compares the RECIPE
against the atlas. It says nothing about whether the isobake code that baked it
has since changed -- an atlas can be present, match its recipe exactly, and still
be wrong because a pipeline fix landed afterwards. That is what
`generator.isobake_commit` is for, and what the game side's staleness rule reads.
Two different kinds of stale; this tool answers one of them.

    python tools/stale_recipes.py                # human summary
    python tools/stale_recipes.py --names        # bare names, for -RecipeList
    python tools/stale_recipes.py --player       # the colour variants instead

A recipe with no staged atlas at all counts as stale: it has never been baked, or
it was baked and never staged, and either way the render box should run it.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
import tomllib
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
RECIPES = REPO / "tools" / "recipes"
ATLASES = REPO / "game" / "assets" / "atlases"


def recipe_id(path: Path) -> str | None:
    try:
        return str(tomllib.loads(path.read_text(encoding="utf-8")).get("id", "")).strip() or None
    except Exception:
        return None


def staged_sha(rid: str) -> str | None:
    atlas = ATLASES / f"{rid}.atlas.json"
    if not atlas.exists():
        return None
    try:
        return json.loads(atlas.read_text(encoding="utf-8")).get("generator", {}).get("recipe_sha256")
    except Exception:
        return None


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--player", action="store_true", help="check recipes/player/ instead of recipes/")
    ap.add_argument("--names", action="store_true", help="print bare recipe names, one per line")
    args = ap.parse_args()

    where = RECIPES / "player" if args.player else RECIPES
    stale, never, fresh, unreadable = [], [], [], []

    for path in sorted(where.glob("*.toml")):
        rid = recipe_id(path)
        if rid is None:
            unreadable.append(path.name)
            continue
        want = hashlib.sha256(path.read_bytes()).hexdigest()
        have = staged_sha(rid)
        if have is None:
            never.append(path.stem)
        elif have != want:
            stale.append(path.stem)
        else:
            fresh.append(path.stem)

    if args.names:
        # `never` first: an id the game references but cannot draw is a harder
        # failure than one it draws slightly wrong.
        for name in never + stale:
            print(name)
        return

    print(f"  {where.relative_to(REPO)}")
    print(f"    up to date       : {len(fresh)}")
    print(f"    recipe changed   : {len(stale)}")
    print(f"    never staged     : {len(never)}")
    if unreadable:
        print(f"    UNREADABLE       : {len(unreadable)}  {unreadable}")
    if stale:
        print("\n  changed since their atlas was baked:")
        for name in stale:
            print(f"      {name}")
    if never:
        print("\n  no staged atlas at all:")
        for name in never:
            print(f"      {name}")
    print(f"\n  total to bake: {len(stale) + len(never)}")

    if unreadable:
        sys.exit(1)


if __name__ == "__main__":
    main()
