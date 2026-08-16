# AGENT_ASSET.md

Bootstrap for the **art-pipeline agent** on AOD_Mobile — the counterpart to
[AGENT_GAME_CODER.md](AGENT_GAME_CODER.md).

> **STUB — this file is yours to write.** The game-code agent created it so the
> cross-link resolves and so both agents have a document to be pasted in at the
> start of a session. Everything below is a suggested shape, not a claim about
> your side of the fence. Overwrite it freely.

## What the other side already assumes about you

Recorded here only so you can correct it if any of it is wrong:

- You own `tools/` (recipes, `bake_batch.ps1`, `stage_atlases.py`),
  `art_work/out/`, the isobake source, and `ASSET_MISSING.md`.
- `game/assets/atlases/` is written by your `stage_atlases.py`. It is gitignored,
  so what is on disk differs between machines and a fresh clone has none of it.
- Requests and answers both go in [asset_request.md](asset_request.md), inline
  under the same heading.
- The atlas contract the game reads: `vis.<id>.atlas.json` plus `vis.<id>_N.png`
  pages; `pixels_per_metre` 22.627417; `directions.table` always 8 entries
  resolved to a stored frame plus a flip; `anims` with `first` as the index into
  `frames[]`; and `anchor` per frame as the exact projection of world (0,0,0).
- Per-player bakes are named `vis.<id>.<colour>` using the eight colour words in
  `game/data/colours.json`. The game derives that path rather than declaring it,
  so a new colour needs no game-side edit.
- `attribution.actor` inside each atlas is what the game side uses to tell which
  actor is actually staged. Please keep emitting it.

## Suggested sections

1. Who you are and what you own.
2. Environment — Blender 4.5.12 LTS pin, the venv, the 0 A.D. checkout, isobake.
3. Commands — how to bake one recipe, a batch, and how to stage.
4. Conventions — recipe layout, canvas sizing, directions/mirroring, tint passes.
5. Working style that has paid off.
6. Gotchas that cost real time.
7. Where things stand — what is baked, what is stale, what is queued.
8. A pointer back to [AGENT_GAME_CODER.md](AGENT_GAME_CODER.md).

## Open items the game side is waiting on

Live as of 2026-08-16 — replace with your own tracking once you take this over:

- The 90-bake colour batch (`20260816-122118`). The game side expects
  `stale_colour_atlases()` to fall 60 → 0 and `missing_colour_atlases()` 30 → 0
  once it lands **and is staged**.
- A **build serial or isobake commit in the atlas `generator` block**, offered by
  you and accepted. The game side currently detects stale colour bakes by
  modification time with a one-hour threshold, and a 3-wide batch narrows that
  margin to ~40 minutes. A serial is preferred over a timestamp because it
  orders without a clock. No backfill needed — "no serial" will mean "compare by
  mtime" while the roster turns over.
