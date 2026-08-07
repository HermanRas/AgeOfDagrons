#!/usr/bin/env python3
"""Stage baked atlases into the Godot project for the packager. Phase 0.3 input.

`isobake` writes each bake to its own directory under the art working root, and
most of what lands there is scaffolding: the intermediate `frames/` renders, the
`verify_*.png` contact sheets, and isobake's own `_payload.json` / `_result.json`.
The game needs exactly two kinds of file per asset -- the atlas JSON and the PNG
pages it names -- and shipping the rest would put hundreds of megabytes of
intermediate renders into a pack.

So this copies **only** the atlas JSON and its declared pages, for **only** the
IDs this project actually declares:

    art_work/out/<id>/<id>.atlas.json  ->  game/assets/atlases/<id>.atlas.json
    art_work/out/<id>/<id>_0.png       ->  game/assets/atlases/<id>_0.png

The ID list comes from `tools/recipes/*.toml`, not from listing the output
directory. That matters: the output root also accumulates isobake's own test
artefacts (`test.smoke`), and those are not ours to ship. Pages are read from the
atlas JSON's `pages` array rather than globbed, so a multi-page asset copies
correctly without this script knowing how many pages it has.

`game/assets/atlases/` is **gitignored on purpose**. These are build output,
reproducible from the committed recipes plus isobake, and they reach players
through the downloadable art pack (PLAN.md 3.2) rather than through git or the
APK. Re-run this after any rebake.

    python tools/stage_atlases.py            # copy, skipping unchanged files
    python tools/stage_atlases.py --clean     # empty the destination first
    python tools/stage_atlases.py --dry-run   # report what would happen
"""

from __future__ import annotations

import argparse
import filecmp
import json
import shutil
import sys
import tomllib
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
RECIPES = REPO / "tools" / "recipes"
DEST = REPO / "game" / "assets" / "atlases"

LOCAL_CONFIG = REPO / "tools" / "isobake.local.toml"


def out_root() -> Path | None:
    """Where isobake writes. Machine-local, so it is never committed."""
    if not LOCAL_CONFIG.exists():
        return None
    with LOCAL_CONFIG.open("rb") as fh:
        data = tomllib.load(fh)
    raw = data.get("paths", {}).get("out")
    return Path(raw) if raw else None


def recipe_ids() -> list[str]:
    ids = []
    for path in sorted(RECIPES.glob("*.toml")):
        data = tomllib.loads(path.read_text(encoding="utf-8-sig"))
        rid = data.get("id")
        if rid:
            ids.append(rid)
    return ids


def files_for(root: Path, asset_id: str) -> tuple[list[Path], str | None]:
    """The atlas JSON plus every page it declares, or an error string."""
    atlas = root / asset_id / f"{asset_id}.atlas.json"
    if not atlas.exists():
        return [], f"not baked yet (no {atlas.name})"

    try:
        pages = json.loads(atlas.read_text(encoding="utf-8")).get("pages", [])
    except json.JSONDecodeError as exc:
        return [], f"atlas JSON is unreadable: {exc}"

    wanted = [atlas]
    for page in pages:
        p = atlas.parent / str(page)
        if not p.exists():
            return [], f"declares page '{page}' which does not exist"
        wanted.append(p)
    return wanted, None


def size_str(n: float) -> str:
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024 or unit == "GB":
            return f"{n:.1f} {unit}"
        n /= 1024.0
    return f"{n:.1f} GB"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--clean", action="store_true",
                        help="delete the destination directory first")
    parser.add_argument("--dry-run", action="store_true",
                        help="report without copying")
    args = parser.parse_args()

    root = out_root()
    if root is None:
        print("error: tools/isobake.local.toml has no paths.out -- see "
              "isobake.local.toml.example", file=sys.stderr)
        return 1
    if not root.is_dir():
        print(f"error: bake output root does not exist: {root}", file=sys.stderr)
        return 1

    ids = recipe_ids()
    if not ids:
        print("error: no recipes found", file=sys.stderr)
        return 1

    if args.clean and DEST.exists() and not args.dry_run:
        shutil.rmtree(DEST)
        print(f"cleaned {DEST.relative_to(REPO).as_posix()}")

    if not args.dry_run:
        DEST.mkdir(parents=True, exist_ok=True)

    copied = skipped = 0
    total = 0
    missing: list[str] = []

    for asset_id in ids:
        wanted, error = files_for(root, asset_id)
        if error:
            missing.append(f"{asset_id}: {error}")
            continue

        for src in wanted:
            dst = DEST / src.name
            total += src.stat().st_size
            if dst.exists() and filecmp.cmp(src, dst, shallow=False):
                skipped += 1
                continue
            if not args.dry_run:
                shutil.copy2(src, dst)
            copied += 1

    verb = "would copy" if args.dry_run else "copied"
    print(f"staged {len(ids) - len(missing)}/{len(ids)} atlases into "
          f"{DEST.relative_to(REPO).as_posix()}")
    print(f"  {verb} {copied} file(s), {skipped} already current, "
          f"{size_str(total)} total")

    if missing:
        print(f"\n  {len(missing)} not staged:")
        for m in missing:
            print(f"    - {m}")
        print("\n  RESULT: INCOMPLETE -- the game falls back to placeholders for these")
        return 1

    print("  RESULT: OK -- every declared atlas is staged")
    return 0


if __name__ == "__main__":
    sys.exit(main())
