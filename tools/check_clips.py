"""Cross-check every recipe's [anims] clip names against what its actor declares.

A wrong clip name is a bake that fails ~10 minutes in (vis.scout_cavalry did
exactly that), and it is entirely decidable from the XML beforehand.

Two things the first version of this script got wrong, both of which produced
false positives on vis.villager:

  1. Variant files reference OTHER variant files. `biped/female_death.xml` is
     nothing but `<variant file="biped/death_infantry.xml"/>`, so a one-level
     walk sees no animations and concludes the actor has no Death. Resolution
     has to recurse.
  2. A recipe's `clip` may name a VARIANT, not an animation. `carry_metal` is
     `<variant name="carry_metal">`, whose animations are called Idle/Walk/Run.
     isobake resolves both, so both count as declared.

Getting these wrong nearly caused a "fix" to an asset that was not broken.
"""
import os
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

HERE = Path(__file__).resolve().parent
RECIPES = HERE / "recipes"


def _art_source() -> Path:
    """Where the 0 A.D. checkout lives -- never hardcoded (PLAN.md 2.6).

    Same two places isobake itself looks: $ISOBAKE_ART_SOURCE, then
    tools/isobake.local.toml, which is gitignored per-machine state.
    """
    env = os.environ.get("ISOBAKE_ART_SOURCE")
    if env:
        return Path(env)
    local = HERE / "isobake.local.toml"
    if local.exists():
        m = re.search(
            r'(?m)^\s*art_source\s*=\s*"([^"]+)"',
            local.read_text(encoding="utf-8", errors="replace"),
        )
        if m:
            return Path(m.group(1))
    sys.exit(
        "cannot find the 0 A.D. checkout -- set ISOBAKE_ART_SOURCE or put "
        "art_source in tools/isobake.local.toml"
    )


ART = _art_source()
ACTORS = ART / "art" / "actors"
VARIANTS = ART / "art" / "variants"


def _parse(p: Path):
    try:
        return ET.parse(p).getroot()
    except (ET.ParseError, OSError):
        return None


def _walk(root, names: set[str], seen: set[str]) -> None:
    """Collect animation names AND variant names, following variant files."""
    if root is None:
        return
    for a in root.iter("animation"):
        if a.get("name"):
            names.add(a.get("name"))
    for v in root.iter("variant"):
        if v.get("name"):
            names.add(v.get("name"))
        ref = v.get("file")
        if not ref or ref in seen:
            continue
        seen.add(ref)
        vp = VARIANTS / ref
        if vp.exists():
            _walk(_parse(vp), names, seen)


def declared(actor_rel: str) -> set[str]:
    p = ACTORS / actor_rel
    if not p.exists():
        return set()
    names: set[str] = set()
    _walk(_parse(p), names, set())
    return names


bad = []
for toml in sorted(RECIPES.glob("*.toml")):
    text = toml.read_text(encoding="utf-8", errors="replace")
    m = re.search(r'(?m)^actor\s*=\s*"([^"]+)"', text)
    if not m:
        continue
    actor_rel = m.group(1)
    clips = re.findall(r'(?m)^clip\s*=\s*"([^"]+)"', text)
    if not clips:
        continue
    have = declared(actor_rel)
    if not have:
        bad.append((toml.name, actor_rel, "actor unreadable or declares nothing", []))
        continue
    missing = sorted({c for c in clips if c not in have})
    if missing:
        bad.append((toml.name, actor_rel, ", ".join(missing), sorted(have)))

if not bad:
    print("OK - every recipe clip name resolves against its actor")
    sys.exit(0)

print(f"{len(bad)} recipe(s) reference clips their actor does not declare:\n")
for name, actor, missing, have in bad:
    print(f"  {name}")
    print(f"    actor   : {actor}")
    print(f"    MISSING : {missing}")
    print(f"    declares: {have}")
    print()
