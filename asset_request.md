# Asset requests for agent 2

Requests logged here by the game-side agent as MVP work surfaces a real gap. Each entry names the stable visual id the game already expects, so it can be wired in the moment it's baked — see `ASSET_MISSING.md` for the full tracker and status legend this mirrors.

## Open requests

_(none right now)_

## Baked

### `vis.berry_bush` — delivered, wired 2026-08-08

Not a request that went through this file — the user pointed at an existing bake sitting unwired at `art_work\out\vis.berry_bush\` (atlas + PNG, real 0 A.D. `props/flora/berry_bush.xml`, CC-BY-SA 3.0). Copied into `game/assets/atlases/` and wired into `visuals.json`/`resources.json` as `res.berry_bush`, which now replaces `res.deer` as the MVP's active food node (session decision — no hunt/kill/carcass state machine needed, it gathers like a tree). `res.deer`/`vis.deer` stay defined but unused.

### `vis.deer_carcass` — requested 2026-08-08, baked 2026-08-08

**What's needed:** a static (no animation needed) sprite for a dead/downed deer, to show once `res.deer` (PLAN.md 6.1a/6.2, the huntable food node) is fully gathered. Same treatment as `vis.deer` itself, which is already baked static-only (`tools/recipes/deer.toml`, `fauna/deer.xml`, 5 directions mirrored to 8, 128×128 canvas) — no animation is expected or wanted here either.

**Why:** `game/data/resources.json` calls this out explicitly: *"The carcass still has no art and stays on its placeholder."* `res.deer`'s node itself is fully implemented and baked; only the depleted/carcass visual state is missing. Not currently blocking — the game falls back to the standard placeholder — but it's a known, named gap on the path to a complete MVP gather loop (chop wood / mine gold / hunt a deer).

**Candidate source:** 0 A.D.'s asset set may have a dead/carcass variant near `fauna/deer.xml` (worth checking sibling fauna actors, e.g. boar/sheep/wolf equivalents, for a `_dead` or corpse mesh) — same CC-BY-SA 3.0 source already in use for every other fauna bake (`vis.deer`, `vis.boar`, `vis.sheep`, `vis.fish`, `vis.wolf`). If no dedicated corpse mesh exists in 0 A.D.'s set, a static downed-deer pose (or even the standing stag mesh laid on its side) would be an acceptable substitute — readability at sprite scale matters more than anatomical accuracy, same call already made for `vis.fish` (tuna over the true fish mesh) and `vis.stone_mine` (quarried rock over a civ-matched but less legible pick).

**Where it plugs in once baked:** `game/data/visuals.json` (new `vis.deer_carcass` entry, same shape as `vis.deer`'s) and `game/data/resources.json`'s `res.deer` entry (a depleted-state visual field, once the sim side reads one — not implemented yet, tracked separately under PLAN.md 6.1a/6.2).

**Baked 2026-08-08:** `vis.deer_carcass`, 5 directions mirrored to 8, 192×192 canvas, `tools/recipes/deer_carcass.toml`. Turned out not to need a substitute pose — the death clip's own collapsed frame now bakes correctly, since this request prompted a real fix for the animation-transfer bug that had kept `vis.deer` static (`isobake` gained a per-clip `location_scale` correction; see ASSET_MISSING.md §1.1 for detail). One cosmetic caveat: a small tear at the neck/antler seam in the collapsed pose, accepted as placeholder-quality. Wiring into `visuals.json`/`resources.json` is on your side of the fence.

**Not wired in, on purpose:** the game swapped its MVP food node to `res.berry_bush` this same session (see above), so nothing currently gathers a deer to leave this carcass behind. The fix is real and worth keeping — it also means `vis.deer` itself could regain proper walk/idle animation instead of staying static-only, which was not attempted here. Revisit if wildlife hunting comes back.

---

## Format for new entries

```
### `vis.<id>` — requested <date>

**What's needed:** ...
**Why:** ...
**Candidate source:** ...
**Where it plugs in once baked:** ...
```

Move an entry to a "Baked" section (or just delete it) once agent 2 confirms it's done and it's wired in.
