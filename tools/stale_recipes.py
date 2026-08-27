"""Name the recipes whose staged atlas no longer matches the recipe, or the code.

WHY THIS IS COMPUTABLE AT ALL. isobake stamps `generator.recipe_sha256` into
every atlas, and that value is `sha256(recipe file bytes)` -- see Recipe.load.
So "has this recipe changed since the atlas was baked" is an exact question with
an exact answer, and it does not need a hand-kept list of pending work that goes
stale the moment somebody edits a recipe without updating it.

IT IS SENSITIVE TO LINE ENDINGS, and that is inherited, not a choice. isobake
hashes the recipe's raw bytes, so a file rewritten CRLF reads as changed even
when every character of its content is identical. Two things do that on Windows
without meaning to: `git checkout` under core.autocrlf, and Python's
`Path.write_text`, whose default translates \\n to \\r\\n. Both have already caused
a false "needs rebaking" here. Recipes in this repo are LF; if this tool reports
a suspiciously round number of stale recipes, check for CRLF before believing it.

THERE ARE TWO KINDS OF STALE AND THIS TOOL NOW ANSWERS BOTH.

    recipe changed      the .toml differs from the one the atlas records
    pipeline changed    the RECIPE is identical but the isobake commit that
                        baked it is not the isobake commit installed now

The second one is `--isobake`, and it exists because its absence nearly wasted a
whole night. On 2026-08-27 a one-character fix in isobake's `directions.py`
corrected a reflection that had mirrored every 8- and 5-direction atlas ever
baked. Not one recipe changed -- the defect was never in the recipes -- so this
tool reported `total to bake: 0` for all 331 atlases, and `render_box_bake.ps1`,
which asks this tool what to do, would have printed "nothing is out of date" and
idled until morning. An atlas can match its recipe exactly and still be wrong.

WHY `--isobake` IS OPT-IN RATHER THAN THE DEFAULT. It flags every atlas not
baked at the current commit, which today is 321 of 331 -- including the 298 that
predate the stamp entirely and the 89 buildings that no direction fix can reach.
Most pipeline changes touch a knowable subset, and re-rendering the rest costs
hours of machine time to produce identical bytes. Pair it with `--directions` to
say which subset, and say WHY in the commit that runs it.

`--directions 5,8` filters to recipes whose `[render].directions` is in the set,
which is exactly the blast radius of a change to the direction sweep. Generated
colour recipes carry their own full `[render]` block, so they filter correctly
without resolving back to their base recipe.

    python tools/stale_recipes.py                       # human summary
    python tools/stale_recipes.py --names               # bare names, for -RecipeList
    python tools/stale_recipes.py --player              # the colour variants instead
    python tools/stale_recipes.py --isobake             # + those baked by older code
    python tools/stale_recipes.py --isobake --directions 5,8

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


def recipe_doc(path: Path) -> dict | None:
    try:
        return tomllib.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return None


def staged_generator(rid: str) -> dict | None:
    """The atlas's `generator` block, or None if there is no staged atlas."""
    atlas = ATLASES / f"{rid}.atlas.json"
    if not atlas.exists():
        return None
    try:
        return json.loads(atlas.read_text(encoding="utf-8")).get("generator", {})
    except Exception:
        return None


def current_isobake_commit() -> str:
    """The commit isobake would stamp into an atlas baked right now.

    Imported from isobake rather than reimplemented, so this tool and the bake
    can never disagree about what "the current commit" means. That is not
    theoretical caution: `isobake inspect` once reported a different armature
    than the bake used, and a recipe reasoned correctly from the false premise
    all the way to shipping a static sprite for a year.

    Fails loudly. A silent "cannot tell" here would report nothing as stale,
    which is indistinguishable from "everything is current" and is the exact
    failure this flag exists to prevent.
    """
    try:
        from isobake.build_id import build_id
    except ImportError:
        sys.exit(
            "--isobake needs the isobake package importable; run this with the venv "
            "python (tools_env\\venv\\Scripts\\python.exe)"
        )

    commit = build_id().get("isobake_commit")
    if not commit:
        sys.exit(
            "--isobake: isobake could not identify its own commit (is git on PATH?). "
            "Refusing to report staleness rather than reporting none."
        )
    return commit


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--player", action="store_true", help="check recipes/player/ instead of recipes/")
    ap.add_argument("--names", action="store_true", help="print bare recipe names, one per line")
    ap.add_argument("--isobake", action="store_true",
                    help="also flag atlases baked by an isobake commit other than the current one")
    ap.add_argument("--directions", metavar="LIST",
                    help="only consider recipes whose [render].directions is in this set, e.g. 5,8")
    args = ap.parse_args()

    want_directions: set[int] | None = None
    if args.directions:
        try:
            want_directions = {int(n) for n in args.directions.split(",") if n.strip()}
        except ValueError:
            sys.exit(f"--directions wants a comma-separated list of integers, got {args.directions!r}")

    commit = current_isobake_commit() if args.isobake else None

    where = RECIPES / "player" if args.player else RECIPES
    stale, never, pipeline, fresh, unreadable = [], [], [], [], []
    skipped = 0

    for path in sorted(where.glob("*.toml")):
        doc = recipe_doc(path)
        rid = str((doc or {}).get("id", "")).strip()
        if doc is None or not rid:
            unreadable.append(path.name)
            continue

        if want_directions is not None:
            # Absent means 1: a recipe with no [render].directions renders once.
            directions = int(doc.get("render", {}).get("directions", 1))
            if directions not in want_directions:
                skipped += 1
                continue

        generator = staged_generator(rid)
        if generator is None:
            never.append(path.stem)
            continue

        if generator.get("recipe_sha256") != hashlib.sha256(path.read_bytes()).hexdigest():
            stale.append(path.stem)
        elif commit is not None and generator.get("isobake_commit") != commit:
            # Covers a differing commit AND a missing/null key -- an atlas from
            # before the stamp existed is older code by definition.
            pipeline.append(path.stem)
        else:
            fresh.append(path.stem)

    if args.names:
        # `never` first: an id the game references but cannot draw is a harder
        # failure than one it draws slightly wrong. `stale` before `pipeline`
        # for the same reason -- a changed recipe is a deliberate edit waiting
        # to land, a pipeline rebake reproduces something that already renders.
        for name in never + stale + pipeline:
            print(name)
        return

    print(f"  {where.relative_to(REPO)}")
    print(f"    up to date       : {len(fresh)}")
    print(f"    recipe changed   : {len(stale)}")
    if commit is not None:
        print(f"    pipeline changed : {len(pipeline)}  (baked by isobake != {commit})")
    print(f"    never staged     : {len(never)}")
    if want_directions is not None:
        print(f"    not in --directions {sorted(want_directions)}: {skipped} skipped")
    if unreadable:
        print(f"    UNREADABLE       : {len(unreadable)}  {unreadable}")
    if stale:
        print("\n  changed since their atlas was baked:")
        for name in stale:
            print(f"      {name}")
    if pipeline:
        print("\n  baked by older isobake code:")
        for name in pipeline:
            print(f"      {name}")
    if never:
        print("\n  no staged atlas at all:")
        for name in never:
            print(f"      {name}")
    print(f"\n  total to bake: {len(stale) + len(never) + len(pipeline)}")

    if unreadable:
        sys.exit(1)


if __name__ == "__main__":
    main()
