#!/usr/bin/env python3
"""Licence audit -- PLAN.md 2.3, phase 0.2c.

Attribution is a licence obligation, not a courtesy. 0 A.D.'s art/LICENSE.txt
requires three things verbatim: a link to the CC-BY-SA 3.0 deed, the author named
as "Wildfire Games", and a link to wildfiregames.com. Shipping a sprite derived
from their models without all three is a licence violation, and it is exactly the
kind of thing that rots quietly as assets get added.

So this asks one question: **is every asset we ship declared in
game/assets/LICENCES.md?** Two populations count as shipped:

  1. Files under game/assets/ -- these go inside the APK.
  2. Every recipe in tools/recipes/ -- each bakes one atlas that goes into the
     downloadable art pack (PLAN.md 3.2). The atlases themselves are not in the
     repo, so the recipe is the durable record of what we ship and where it came
     from.

It also checks the recipes actually carry attribution, and that the three
required elements appear in the files that must carry them. A recipe added
without an [attribution] block is the realistic failure mode -- it bakes fine and
nothing else notices.

    python tools/licence_audit.py            # audit; exit 1 on any problem
    python tools/licence_audit.py --write    # regenerate the generated section
                                             # of LICENCES.md from the recipes

THERE IS NO CI (PLAN.md 1.2). Nothing runs this for you. Run it before a release
and whenever you add an asset.
"""

from __future__ import annotations

import argparse
import re
import sys
import tomllib
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
RECIPES = REPO / "tools" / "recipes"
ASSETS = REPO / "game" / "assets"
LICENCES = ASSETS / "LICENCES.md"
CREDITS = REPO / "CREDITS.md"

#: The three elements 0 A.D.'s art/LICENSE.txt and audio/LICENSE.txt require
#: verbatim. Checked as substrings, so shortening any of them fails the audit.
REQUIRED_0AD_ELEMENTS = [
    "http://creativecommons.org/licenses/by-sa/3.0/",
    "Wildfire Games",
    "http://www.wildfiregames.com/",
]

#: Extensions that constitute a shipped asset. Source, docs and Godot's own
#: sidecar files are not assets.
ASSET_SUFFIXES = {
    ".png", ".jpg", ".jpeg", ".webp", ".svg",
    ".ttf", ".otf", ".woff", ".woff2",
    ".ogg", ".wav", ".mp3",
}

#: Every attribution block must carry these. `actor` is optional -- terrain
#: recipes name a terrain rather than an actor.
REQUIRED_ATTRIBUTION_KEYS = ["source", "licence", "licence_url", "author", "author_url"]

GENERATED_BEGIN = "<!-- BEGIN GENERATED: recipes -->"
GENERATED_END = "<!-- END GENERATED: recipes -->"


class Problem:
    def __init__(self, where: str, what: str) -> None:
        self.where = where
        self.what = what

    def __str__(self) -> str:
        return f"{self.where}: {self.what}"


def load_recipes() -> tuple[list[dict], list[Problem]]:
    """Every recipe, as {id, path, attribution}, plus any that would not parse.

    A recipe that fails to parse is REPORTED, not raised. An audit that dies with
    a traceback on one malformed file tells you nothing about the other ten, and
    the whole point is to get a complete list of what is wrong in one run.

    The BOM strip is not hypothetical: PowerShell's `Set-Content -Encoding utf8`
    writes UTF-8 *with* a BOM on Windows PowerShell 5.1, tomllib rejects it, and
    this is a Windows-first project (PLAN.md 1.2).
    """
    out: list[dict] = []
    problems: list[Problem] = []
    for path in sorted(RECIPES.glob("*.toml")):
        try:
            text = path.read_text(encoding="utf-8-sig")
            data = tomllib.loads(text)
        except (tomllib.TOMLDecodeError, OSError, UnicodeDecodeError) as exc:
            problems.append(Problem(_rel(path), f"cannot be parsed: {exc}"))
            continue
        out.append({
            "id": data.get("id", ""),
            "path": path,
            "attribution": data.get("attribution", {}),
            "source": data.get("source", {}),
        })
    return out, problems


def shipped_asset_files() -> list[Path]:
    """Asset files inside game/assets/, relative to the repo root."""
    if not ASSETS.is_dir():
        return []
    return sorted(
        p for p in ASSETS.rglob("*")
        if p.is_file() and p.suffix.lower() in ASSET_SUFFIXES
    )


def declared_keys(text: str) -> set[str]:
    """Everything quoted in inline backticks in LICENCES.md.

    Deliberately loose. A stricter table parser would break every time the file
    is reformatted, and the question being asked is only "is this named here",
    which a backtick token answers.

    Two things this has to get right, both found the hard way on the first run:
    fenced ``` blocks are stripped first, because their unpaired backticks shift
    every pairing after them and silently swallow the whole document; and a token
    may not contain a newline, because inline code never spans lines and allowing
    it lets one stray backtick match half the file.
    """
    without_fences = re.sub(r"```.*?```", " ", text, flags=re.DOTALL)
    return set(re.findall(r"`([^`\n]+)`", without_fences))


def audit() -> list[Problem]:
    problems: list[Problem] = []

    if not LICENCES.exists():
        problems.append(Problem(
            _rel(LICENCES),
            "does not exist -- every shipped asset needs a provenance entry",
        ))
        return problems

    licences_text = LICENCES.read_text(encoding="utf-8")
    declared = declared_keys(licences_text)

    # 1. Recipes: attribution completeness, then declaration.
    recipes, parse_problems = load_recipes()
    problems.extend(parse_problems)
    if not recipes and not parse_problems:
        problems.append(Problem(_rel(RECIPES), "no recipes found -- expected at least one"))

    for r in recipes:
        where = _rel(r["path"])
        if not r["id"]:
            problems.append(Problem(where, "recipe declares no id"))
        attribution = r["attribution"]
        if not attribution:
            problems.append(Problem(where, "no [attribution] block -- this bakes an asset we ship"))
            continue
        for key in REQUIRED_ATTRIBUTION_KEYS:
            if not str(attribution.get(key, "")).strip():
                problems.append(Problem(where, f"[attribution] is missing '{key}'"))

        if r["id"] and r["id"] not in declared:
            problems.append(Problem(
                _rel(LICENCES),
                f"'{r['id']}' is baked by {r['path'].name} but is not declared",
            ))

    # 2. Files that ship inside the APK.
    for path in shipped_asset_files():
        rel = path.relative_to(ASSETS).as_posix()
        if rel not in declared and path.name not in declared:
            problems.append(Problem(
                _rel(LICENCES), f"shipped asset '{rel}' is not declared"
            ))

    # 3. Declared-but-unlicensed. Being NAMED in LICENCES.md is not the same as
    #    having a licence, and treating it as such would make this tool report
    #    PASS while shipping an asset whose rights nobody has established --
    #    precisely the failure it exists to prevent. UNVERIFIED is the sentinel
    #    for "someone has to answer this", and it fails until they do.
    for lineno, line in enumerate(licences_text.splitlines(), start=1):
        if "UNVERIFIED" in line and line.lstrip().startswith("|"):
            names = re.findall(r"`([^`\n]+)`", line)
            subject = ", ".join(names) if names else "row"
            problems.append(Problem(
                f"{_rel(LICENCES)}:{lineno}",
                f"{subject} is listed but its licence is UNVERIFIED",
            ))

    # 4. The three verbatim elements, wherever 0 A.D. material is credited.
    for target in (LICENCES, CREDITS):
        if not target.exists():
            problems.append(Problem(_rel(target), "does not exist"))
            continue
        text = target.read_text(encoding="utf-8")
        if "0 A.D." not in text and "Wildfire" not in text:
            continue
        for element in REQUIRED_0AD_ELEMENTS:
            if element not in text:
                problems.append(Problem(
                    _rel(target),
                    f"missing the required 0 A.D. attribution element: {element}",
                ))

    return problems


def render_generated_section(recipes: list[dict]) -> str:
    """The recipe-derived table. Regenerated wholesale by --write."""
    lines = [
        GENERATED_BEGIN,
        "",
        "<!-- Do not edit by hand. Regenerate with:",
        "       python tools/licence_audit.py --write -->",
        "",
        "| Asset ID | Source file | Origin | Licence |",
        "|---|---|---|---|",
    ]
    for r in recipes:
        a = r["attribution"]
        origin = a.get("actor") or r["source"].get("terrain") or "--"
        licence = a.get("licence", "?")
        url = a.get("licence_url", "")
        licence_cell = f"[{licence}]({url})" if url else licence
        lines.append(
            f"| `{r['id']}` | `{r['path'].name}` | `{origin}` | {licence_cell} |"
        )
    lines += ["", GENERATED_END]
    return "\n".join(lines)


def write_generated() -> int:
    if not LICENCES.exists():
        print(f"error: {_rel(LICENCES)} does not exist -- create it first", file=sys.stderr)
        return 1

    text = LICENCES.read_text(encoding="utf-8")
    if GENERATED_BEGIN not in text or GENERATED_END not in text:
        print(
            f"error: {_rel(LICENCES)} has no generated block.\n"
            f"       Add these two markers where the table should go:\n"
            f"         {GENERATED_BEGIN}\n         {GENERATED_END}",
            file=sys.stderr,
        )
        return 1

    recipes, parse_problems = load_recipes()
    if parse_problems:
        # Regenerating from a partial read would silently drop the broken recipe's
        # row, which is the opposite of what this file is for.
        for p in parse_problems:
            print(f"error: {p}", file=sys.stderr)
        print("error: refusing to regenerate from unparseable recipes", file=sys.stderr)
        return 1
    section = render_generated_section(recipes)
    start = text.index(GENERATED_BEGIN)
    end = text.index(GENERATED_END) + len(GENERATED_END)
    LICENCES.write_text(text[:start] + section + text[end:], encoding="utf-8")
    print(f"rewrote the generated block in {_rel(LICENCES)}")
    return 0


def _rel(path: Path) -> str:
    try:
        return path.resolve().relative_to(REPO).as_posix()
    except ValueError:
        return str(path)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--write", action="store_true",
        help="regenerate the recipe-derived table in LICENCES.md, then audit",
    )
    args = parser.parse_args()

    if args.write:
        code = write_generated()
        if code != 0:
            return code

    problems = audit()
    recipe_count = len(load_recipes()[0])
    asset_count = len(shipped_asset_files())

    print(f"licence audit: {recipe_count} recipe(s), {asset_count} shipped asset file(s)")

    if not problems:
        print("  RESULT: PASS -- everything shipped is declared")
        return 0

    print(f"\n  {len(problems)} problem(s):")
    for p in problems:
        print(f"    - {p}")
    print("\n  RESULT: FAIL")
    print("  Attribution is a licence obligation (PLAN.md 2.3), not a warning.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
