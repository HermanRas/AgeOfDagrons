"""Pin every [anims.decay] to the final pose of its Death clip.

`decay` has no source animation of its own -- 0 A.D. ships no corpse clip, so
every decay reuses `Death`. Sampling that clip from 0.0 makes the first decay
frame the moment BEFORE the unit falls, so corpses sprang upright for a frame
and then collapsed again. `start = 1.0` holds the final pose instead.

Idempotent: skips any decay block that already sets `start`.
"""

import re
from pathlib import Path

RECIPES = Path(__file__).resolve().parent / "recipes"

NOTE = (
    "# Pinned to the clip's final pose 2026-08-16. Without this, decay's first\n"
    "# frame is Death at t=0 -- the unit still standing -- so the corpse stood up\n"
    "# for one frame before falling over again. See isobake AnimSpec.start.\n"
    "start = 1.0\n"
)

changed = []
for path in sorted(RECIPES.glob("*.toml")):
    text = path.read_text(encoding="utf-8")
    if "[anims.decay]" not in text:
        continue

    lines = text.splitlines(keepends=True)
    out, i, touched = [], 0, False
    while i < len(lines):
        out.append(lines[i])
        if lines[i].strip() == "[anims.decay]":
            # Collect the block so we can check for an existing `start`.
            j = i + 1
            block = []
            while j < len(lines) and not lines[j].lstrip().startswith("["):
                block.append(lines[j])
                j += 1
            if any(re.match(r"\s*start\s*=", b) for b in block):
                out.extend(block)
            else:
                # Insert after the block's last non-blank line, so the note sits
                # with the keys rather than after the trailing blank.
                last = max((k for k, b in enumerate(block) if b.strip()), default=-1)
                out.extend(block[: last + 1])
                out.append(NOTE)
                out.extend(block[last + 1 :])
                touched = True
            i = j
            continue
        i += 1

    if touched:
        path.write_text("".join(out), encoding="utf-8")
        changed.append(path.stem)

print(f"{len(changed)} recipe(s) updated")
for name in changed:
    print(f"  {name}")
