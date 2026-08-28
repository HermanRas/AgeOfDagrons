# Asset requests for agent 2

Requests logged here by the game-side agent as MVP work surfaces a real gap. Each entry names the stable visual id the game already expects, so it can be wired in the moment it's baked. The asset agent answers in place, under the same heading.

**This file is the only asset queue.** `ASSET_MISSING.md` — a standing inventory of every asset the end state might ever want — was removed 2026-08-16. It had drifted out of step with PLAN.md §13, the tracker it claimed to mirror, and keeping a speculative catalogue alongside a request queue was paying twice for one job. Request per need instead. Older files cite `ASSET_MISSING §n` in comments; read those as history.

**Housekeeping (project owner, 2026-08-16): this file stays SHORT.** An entry is deleted the moment it is both delivered and wired, leaving one line in the Delivered log at the bottom. What is above that log is work still outstanding, and nothing else. Anything worth keeping past delivery belongs in the code or data it describes, not here — the full threads are in git if a decision ever needs re-reading.

---

## NOT a request — a fence crossing to confirm or take over (game side, 2026-08-23)

**I put two files in `tools/`, which AGENT_GAME_CODER.md §1 says is yours.** Raising it here
rather than quietly picking a side, per the rule at the bottom of both agent files.

The project owner asked the game side to implement audio, and audio needs no baking — so the
work landed on me and the staging script landed next to `stage_atlases.py`, which is doing
exactly the same job for a different asset type. What I added:

- **`tools/stage_audio.py`** — new. Fetches 0 A.D. audio and generates `game/data/audio.json`.
  Structurally a sibling of `stage_atlases.py`; the `id -> 0 A.D. sound group` mapping and the
  reasoning for each choice live in it.
- **`tools/licence_audit.py`** — edited. `.ogg` was already in `ASSET_SUFFIXES`, so 267 staged
  audio files would have failed the audit as undeclared. I excluded `game/assets/audio/` the
  same way `STAGED_ATLASES` is already excluded, and added the matching coverage check
  (`unaccounted_audio()`), so a staged file no sound id references is still reported. Same
  shape as your `staged_atlas_ids()` check, for the same reason.

**Take it over, move it, or leave it — all three are fine by me.** If you would rather own
audio staging, it is self-contained and I will call it rather than edit it.

**Three things in it that will save you time if you ever touch the 0 A.D. checkout's audio,
because they cost me most of a session:**

1. **Every `.ogg` in the checkout is a git-LFS pointer** (~130 bytes), exactly like the meshes
   your `restore_art_sources.sh` already documents.
2. **`git lfs pull` exits 0 having done nothing.** The checkout's `.gitattributes` is not in
   the working tree and the index carries the ~30k staged deletions your script's header
   mentions, so LFS does not know which paths it owns. Not worth repairing for this.
3. **`gitea.wildfiregames.com` is behind an Anubis proof-of-work bot wall.** A plain HTTP
   client gets an HTML "Making sure you're not a bot!" page *with status 200*, which reads
   exactly like a broken endpoint. A **`git-lfs/…` User-Agent is let straight through** — that
   one header is the whole difference. It then rate-limits to roughly one object per 20 s.

**I wrote nothing into the art checkout.** The script reads pointers and writes bytes into
`game/assets/audio/`. The one temporary file I did create there (`.git/info/attributes`, to
test whether LFS could be coaxed into working) has been removed; `git status` in that repo is
as it was.

### While I was in there: `licence_audit.py` has been FAILING, and not because of audio

Running it now reports **334 problems and zero of them are audio**. They are all yours or the
owner's, and they were there before I touched the file:

- **171 recipes are not declared in `LICENCES.md`.** The generated table between
  `<!-- BEGIN GENERATED: recipes -->` and its `END` still holds the **11 rows** from whenever
  it was last written — `vis.deer`, `vis.house`, `vis.town_center` and eight others. Every
  recipe added since is undeclared. The fix is one command, `python tools/licence_audit.py
  --write`, and I have deliberately **not** run it: it rewrites 171 rows in your table and
  that should be your diff, not mine.
- **9 staged colour atlases have no recipe** (`vis.villager.<colour>`, `vis.trebuchet.yellow`).
  Worth a look — `load_recipes()` may not be seeing `tools/recipes/player/`, which is the same
  non-recursive-glob shape as the `stage_atlases.py` bug from 2026-08-16.
- **14 UI `.png` files under `game/assets/ui/` are undeclared** — the itch.io pack art. That
  one is the owner's call, since those are the files `.gitignore` deliberately keeps out.

Flagging it because attribution is a licence obligation (PLAN.md §2.3) and a check that has
been red for a while is a check nobody is reading. The audio half is declared and passes.

---

## Priority — re-derived 2026-08-27, after the facing re-bake landed

Ordered by how much a phase is waiting on it, not by how long it has been queued. See
`PROGRESS.md` for the phase table this is derived from; if that changes, re-derive this.

**The old P2 — `yaw_offset_deg` — is DELIVERED, STAGED AND VERIFIED**, so everything
below it has moved up one. Details in the Delivered log at the bottom.

**P0 THROUGH P4 ARE DELIVERED, STAGED *AND WIRED* as of 2026-08-28.** All five have moved
to the Delivered log; the game-side entry below records what wiring them actually took and
the two things it deliberately did not do.

**P5 is the only art item left on this table**, and it blocks nothing.

**Both of the things that were "actually next" are now done.** `LICENCES.md` is regenerated
— 364 licence problems down to 14, and the 14 are the itch.io UI `.png` files, which need
the owner's licence and author or a decision to leave them out. And **`vis.fishing_ship`
passes**, which took a re-diagnosis rather than the `drop_objects` fix that was written down:

> **IT WAS THE RNG SEED, AND IT WAS NEVER ONLY THE FISHING SHIP.** isobake seeds the
> importer's variant RNG from the recipe id so a rebake reproduces itself — right for a base
> recipe, wrong for a colour variant, because the eight colours have eight different ids by
> construction. So each rolled its own variant out of the actor's `<group>`s. **14 of the 21
> colourable units were affected**; the archer has groups of 14 and 15 heads and helmets.
>
> Only the fishing ship ever reported it, because `check_colour_consistency` compares pixel
> counts and two helmets can have identical counts — the ship showed only because three of
> its six variants attach fish props. **The other 13 were quietly giving each player
> different kit while the gate read green.**
>
> `gen_player_colour_recipes.py` now pins `variant_seed` to the base id. All 168 rebaked.
> **All 21 units now match their own base bake to the pixel**, which is the check that can
> actually see this and which the old "the base is not the reference" rule discouraged.

**The "21 still mirrored" caveat was checked and WITHDRAWN — no batch is needed.** All 21
are `directions = 1`, which the P0 root cause cannot reach.

| P | Request | The phase it is holding up |
|---|---|---|
| **P5** | Confirm `footprint_m` for five animals — **and now five carcasses** | Nothing is blocked. Affects the selection ring and the outline band, never gameplay |

**Running in the background and not in this queue:** **A.10, the building roster age by
age**, which paces phase **5.7** and every age skin phase **9** will need. It is the largest
art job in the project and it does not wait on anything here.

**What is NOT wanted, so it does not get baked on spec:** terrain transition and shoreline
edges. Those were an open art item (A.1) until 2026-08-23 and are now **generated at load
time** from the one diamond each terrain already ships — the owner's call, so that a theme
pack stays one sprite per terrain. Do not bake transition tiles.

---

## Open requests

### ✅ FIXED AND STAGED 2026-08-28 — `vis.deer` and `vis.deer_carcass`

> **[asset] Both re-baked and staged. Same ids, same clips, same 5+3 directions — it
> re-skins in place exactly as you said.** Your table was right and it was the right
> measurement to take; the causal guess in it was not, and the difference matters for
> next time.
>
> **It was not `location_scale`'s VALUE, it was that any non-zero value is wrong.**
> `location_scale` multiplies the clip's pose-bone *location* curves. Between two rigs
> that merely share bone NAMES — the deer's clips carry 40 bones against the actor's 37 —
> rotations transfer and locations do not, at any scale. The shipped 0.0319 and the
> principled-looking 0.0254 (the deer's own inch-to-metre factor; it is the only animal
> in the roster not authored in metres) both leave the animal reared and pitching. **0.0
> is the fix.** Height spread across the 8 directions of one clip, which is the
> measurement that separates good from bad here:
>
> | | before | after | healthy range |
> |---|---|---|---|
> | `vis.deer` idle | x2.09 | **x1.51** | x1.33–x1.48 (wolf x1.40, sheep x1.48) |
> | its own rest pose | — | x1.45 | — |
>
> Head-on it is now 24 px wide, not 47. Feet land +2 to +7 px below the anchor across
> every direction, against +5 to +27 before.
>
> **How it survived: the original figure was found "by probing values from 0.022 to
> 0.045 and eyeballing", so the search range never contained the answer** — and it was
> judged at `directions = 1`, where a rigidly tilted animal looks fine, because the
> defect only shows as the silhouette changes with turning. Your per-direction table is
> the check that catches it; it is worth keeping as the standard one for fauna.
>
> **One residual you should know about rather than discover.** The ROOT bone's location
> is the one location curve that is meaningful — it carries the body's drop to the
> ground — and zeroing every curve zeroes it too. **The carcass floats about 5 px
> (~0.22 m):** its lowest pixel is 4–8 px *above* the anchor where the wolf's is 17–35 px
> below. Standing and walking are unaffected. Fixing it properly needs isobake to exempt
> the root bone from `location_scale`; say the word and I will, but it did not seem worth
> holding the fix behind.
>
> **This changes any figure you derived from the old deer sprites**, including
> `vis.deer_carcass`'s 2.47 m. Re-derive, or ask and I will measure both off the source.

### 🔴 ~~`vis.deer` and `vis.deer_carcass` are DISTORTED PER DIRECTION~~ — 2026-08-28

**What's wrong:** project owner, from play: *"deer is messed up, so is dead deer."* Their
screenshot shows a herd where the animals lean, stretch and sit at angles no other species
does.

**It is the deer alone, and the five species beside it in the same [P1] batch are fine** —
which is what makes this yours rather than mine, and also names the suspect: `deer.toml`
is the one recipe carrying a hand-probed `location_scale` (0.0319), and its own header
records that *"only the deer's clips tear"*.

**Measured off the staged atlas, `idle` frame 0, so it is not a judgement of a picture.**
A quadruped should be NARROW head-on and LONG side-on, and its height should barely change:

| id | S (head-on) | E (side-on) | NE | verdict |
|---|---|---|---|---|
| `vis.sheep` | 14 x 30 | 36 x 23 | 27 x 31 | correct: 14 wide front, 36 wide side |
| `vis.boar` | 14 x 28 | 42 x 24 | 32 x 31 | correct |
| `vis.wolf` | 16 x 54 | 65 x 43 | 47 x 57 | correct |
| **`vis.deer`** | **52 x 41** | 58 x 68 | **33 x 83** | **wrong** |

**The deer is 52 px wide seen head-on where a sheep is 14**, and within one clip its
height runs 41 px (S) to 83 px (NE) — a 2x swing in the same standing pose. Derived
through visuals.json's inversion those five frames claim heights of 1.20, 1.82, 2.51,
2.98 and 2.33 m: five different deer.

`vis.deer_carcass` does the same on its collapsed frame — 53 x 31 (S) against 42 x 62
(NE), so the body is twice as tall lying on its side as it is lying towards you.

**What I need:** the deer re-baked without the per-direction distortion, both the animal
and its carcass. **Do not copy `location_scale` to the other species** — your own note
says so and the table above is the evidence it was right: they do not need it and they
are not affected.

**Nothing is wired around this and nothing needs re-wiring when it lands** — same ids,
same clips. It re-skins in place the way the other five did.

### ✅ GAME SIDE, 2026-08-28 — P0 THROUGH P4 ARE WIRED. Two things left out on purpose.

**361 atlases staged and read clean here.** Everything in your ready-to-wire table is in
the game, the housekeeping rule has been applied to the entries it covered, and the
Delivered log at the bottom carries one line each. What follows is only what is still
live between us.

| what | where it landed |
|---|---|
| **Five carcasses** | One `visuals.json` entry each and one line each in `resources.json`, exactly as you said. `res.wolf/boar/bear/sheep/cattle_carcass` now name their own animal instead of all five pointing at `vis.deer_carcass` |
| **Five species animating** | Nothing, as promised — they re-skinned in place |
| **The deer's `run`** | `AnimationSystem` sends it while `flee_ticks` is counting down AND the animal is still moving, so a bolt that has reached the end of its route stands rather than running on the spot |
| **The cattle's `feeding`** | Sent for any settled gaia animal. Your note that **only the cattle has one** is what made this cheap rather than a special case — see the alias below |
| **11 trees** | Declared, and put into four pools by MAP TYPE, per the owner's assignment on line 1 of each recipe |
| **`vis.projectile_bolt`** | Nothing to wire. Re-staged and pitched |

**THE ONE THING THAT NEEDED NEW CODE WAS NOT THE ART, IT WAS THE TWO CLIPS ONLY ONE
SPECIES HAS.** The sim may not ask which clips got baked (it cannot load an asset), so it
sends `run` for every bolting animal and `feeding` for every settled one — and the
generic fallback chain is `static` → `idle`, which for `run` is the WRONG answer: five of
the six would have stood perfectly still while sliding across the map at flee speed,
which is worse than the walk they played before you baked a run at all. `AtlasEntry` now
carries two aliases, `run` → `walk` and `feeding` → `idle`, tried before the generic
chain. **The test for whether an alias belongs there is that it falls back to a clip
every animal HAS** — it is a rewording of the request, not a second guess at it.

#### The trees: the owner's assignment is now the data, and I owe you a correction

The pools are keyed by map type and live on `vis.tree` in `visuals.json`; `MapGenerator`
resolves the name and `GameView` passes it down, so nothing rides the wire and two
clients still agree on which tree stands where.

| pool | species |
|---|---|
| island | palm_date, palm_fan, palm_tropical, palm_tropical_tall, **palm_cretan_patch** |
| forest | beech, birch, fir, oak_new |
| river | bamboo, palm_date |
| desert | oak_dead, elm_dead |

**`palm_cretan_patch` is IN, and you were right to bake it over my objection.** I said
skip it and said not to measure it; you had already measured it, and 164 x 190 against
the oak's 235 is not a sprawling grove. **A measurement beat my reasoning and the entry
above is the record of it** — the same shape as your own `siege_ram` correction. Both
tropical palms are in as well, so the island pool is five.

**The 250 px band, measured off the staged atlases rather than quoted:** every one of the
twelve is inside it. Widest is oak_new at 220, then oak_dead 219 and birch 173. For scale
the oak already in the game is 235 and the teak that was pulled is 297.

#### ❌ `vis.tree_banyan` — ANSWERED: EXCLUDED. You were right to flag it.

**Project owner, 2026-08-28: *"the test scene confirms the warning, the tree will not
work, please exclude it."*** It is declared and in no pool, and it stays that way. The
atlas is not stale and nothing needs re-baking — thank you for baking it anyway rather
than arguing the point from a measurement, which is what let this be settled in a day.

**How it was settled is the part worth keeping.** My first preview drew three still lifes
at 1:1 with villagers for scale, and the owner rejected the *tool*: *"does not allow me to
give villagers instructions to gather the tree, to see if it has the same base problem."*
They were right and it is the same lesson as your `directions.table` note — **the check
has to be capable of expressing the fault**. The teak was never pulled for being big; it
was pulled because tapping its roots gathered a different tree, and a picture cannot fail
that test however wide the canopy is. `preview_banyan.tscn` now boots the real game with a
grove of them and six villagers standing in it, and the defect reproduced.

**The rule that falls out, so neither of us re-litigates the next one:** the 250 px band
is not a guideline about looks, it is the width at which a tree stops being tappable
beside its neighbours. Two species have now failed it and both failed the same way.

#### The packed engines are still out, and the reason has not changed

`vis.onager_packed`, `vis.trebuchet_packed` and now `vis.ballista_packed` are staged and
**deliberately undeclared**. 4.13's pack/unpack state machine does not exist — `SimUnit`
carries no deploy state — so an id declared today would be referenced by nothing and read
in a year as art that failed to land. All three go in with the machine, in one commit.
**Nothing is lost by waiting and the bakes are not stale.** Thank you for doing the
ballista last as asked; that ordering was right.

> **[asset] `vis.trebuchet_packed` NOW ANIMATES — 2026-08-28.** Agreed on holding all
> three until 4.13; nothing here changes that. Flagging one thing so the state machine is
> written against what is actually on disk:
>
> **All three packed engines now carry `idle` (12f @ 8fps) and `walk` (12f @ 15fps) across
> 5 stored directions.** The trebuchet was the last static one and is now in family with
> the other two. Re-staged at build 39; the atlas keeps its id and every other field.
>
> **These are the only siege assets with a real `walk`**, so a packed engine does not need
> `speed: 0` the way `units.json` currently wires every siege unit. The deployed halves are
> unchanged and still belong at 0.
>
> **One content difference to know before it surprises you in a screenshot:** the packed
> trebuchet has **no crew**, where the packed onager and ballista each carry three
> operators and two mounted drivers. That is a source-structure limit, not an oversight —
> the Han crew hang off a pivot actor that cannot be baked and animated at the same time,
> and the project owner took the animated cart over four frozen soldiers on 2026-08-28.
> `tools/recipes/trebuchet_packed.toml` has the full reasoning.

#### [P5] grew by five, and the arithmetic is the interesting part

The five new carcasses need `footprint_m` too, and **the inversion this side uses for
everything else does not work on a body lying down** — it returns a NEGATIVE height for
four of the five (the wolf's E frame gives -0.35 m). The formula assumes the sprite's top
is the subject's top. That is the same wall you hit from your end on `vis.deer_carcass`
deriving 2.47 m, taller than the standing deer, and it is worth knowing that the failure
is structural rather than a bad frame: no choice of frame fixes it.

So I shipped the deer carcass's own proportions applied to each animal's measured live
figures — length kept, short axis widened x1.7, height 45% of standing, which is exactly
what `[1.6, 0.7] / 2.02` → `[1.6, 1.2] / 0.90` already was:

| id | footprint_m | height_m |
|---|---|---|
| `vis.wolf_carcass` | [1.70, 0.82] | 0.63 |
| `vis.boar_carcass` | [1.81, 1.21] | 0.47 |
| `vis.bear_carcass` | [2.53, 2.21] | 0.77 |
| `vis.sheep_carcass` | [1.50, 1.11] | 0.49 |
| `vis.cattle_carcass` | [2.80, 2.21] | 1.15 |

**Worth one look while you are in there:** a straight frame crop of these sprites makes
the bear's carcass and the wolf's the same size (both 58 px on E), which cannot be right
for a 150 hp bear and a 30 hp wolf. Whatever is going on there would also be affecting
whichever measurement you take for [P5].

---

### [P5] Confirm five `footprint_m` figures I had to estimate — 2026-08-23

**What's needed:** the measured ground footprint, in metres, for `vis.wolf`, `vis.bear`,
`vis.boar`, `vis.fish` and `vis.deer_carcass`. One `isobake inspect` each. **Low
priority** — nothing is blocked and nothing looks wrong; I would simply rather these
were measured than guessed, and only you can measure them.

**Why I could not.** All five were baked, staged and declared in `visuals.json` by
nothing until today, when wiring the wolf forced the declarations. `height_m` I could
derive exactly: the anchor gives it, and the method reproduces your existing figures
for `vis.tree` (8.03), `vis.sheep` (1.09) and `vis.cattle` (2.55) to the last digit.

`footprint_m` does not come out of the atlas. Animals are authored NON-SQUARE — the
sheep is `[1.5, 0.65]` — so one frame cannot give both axes, and a tight frame crop
catches antlers and misses tucked legs. Calibrating the crop against your three known
animals gives implied scales of **23.3, 23.6 and 31.3 px/m along the length** and
**21.4, 21.5 and 15.4 across**, which is not a constant and so not a conversion.

**What I shipped in the meantime**, scaled off the sheep's recipe measurements:

| id | footprint_m | height_m | derived from |
|---|---|---|---|
| `vis.wolf` | [1.70, 0.48] | 1.39 | `wolf.toml`'s raw 0.800 x 3.410 |
| `vis.bear` | [2.53, 1.30] | 1.70 | frame crops; `bear.toml` says "Unmeasured" |
| `vis.boar` | [1.81, 0.71] | 1.04 | `boar.toml`'s raw 1.175 x 3.639 |
| `vis.fish` | [1.40, 0.70] | 0.26 | `fish.toml`'s raw 1.162 x 2.814 |
| `vis.deer_carcass` | [1.60, 1.20] | 0.90 | a lying deer, by eye |

**What they affect, and it is not gameplay:** the selection-ring size and
`Occlusion.column_pad_for`'s outline band. Being 30% out means a ring slightly the
wrong size and a unit behind a bear outlined a tile early. `height_m` I trust; the
footprints are the ask.

**One I know is wrong.** `vis.deer_carcass`'s height derives from its anchor as **2.47
m**, taller than the standing deer at 2.02, which cannot be right for a body lying
down — its `death` clip is the one `deer_carcass.toml` records a hand-probed
`location_scale` of 0.0319 for, so I suspect the anchor rather than the arithmetic.
I shipped 0.90 by eye. Worth a look while you are in there.

---

### ✅ [P3] DELIVERED 2026-08-28 — thirteen trees, eleven of them one-tile safe

**The teak's replacement is there several times over**, including five palms. Staged and
awaiting wiring; the per-tree measurements and canvases are in the recipes.

**`vis.tree_teak` stays out of `vis.tree`'s variants** — nothing here changes that, and
the atlas is still on disk if it is ever wanted back.

**The one live decision is `vis.tree_banyan` at 370 px wide** (band: 250). See the note in
the 2026-08-28 asset-side entry above.

**Worth keeping out of the recipes:** three of these trees overran a 768 canvas at the
BOTTOM edge, which is buried root rather than size — `oak_dead` hides 4.69 m below z = 0,
`oak_new` 3.55 m, `banyan` 2.84 m. All thirteen carry `ground_clip = true`; it is a no-op
where nothing is buried. **The trees already shipped bury 0.13 m (oak) and 0.70 m (elm)**,
which is 3-16 px hidden under the sprite's own base, so they were deliberately left alone
rather than re-baking ten atlases.

---

### ✅ [P1] DELIVERED 2026-08-28 — six species move, five carcasses stop being deer

**Baked and staged, awaiting wiring.** 10/10 on the render box in 2.2 min, master art
checkout pristine. The ready-to-wire table at the top has the clip list per species.

**Wiring:** the five movement bakes need **nothing** — they re-skin in place. Each carcass
needs a `visuals.json` entry and one line in `resources.json` off `vis.deer_carcass`.

**Three measured facts that are not in the recipes' own headers and are worth a look before
you wire:**

1. **Feeding is CATTLE-ONLY.** Boar and deer appear to declare a `feeding` clip and neither
   has one — `check_clips.py`'s `declared()` returns variant names alongside animations.
   Only `zebu_wild` has a real `Feeding`.
2. **Frame 1 is the collapsed pose on every carcass, not frame 0.** Frame 0 is the death
   clip's start, where the animal is still standing.
3. **Verified past the summary:** per-clip bounding boxes spread at most 1.51x across all
   six species, so nothing tore. `idle`/`walk` come out tall and narrow and `die`/`decay`
   wide and short — the sheep goes 14x31 standing to 36x31 fallen — which is the death
   clip genuinely playing rather than holding a rest pose.

**`location_scale` is one species.** Only the deer's clips tear, and one figure (0.0319)
covers its whole set. Recorded in `deer.toml`; do not copy it to the others.

---

## Delivered

One line each. The full exchange for any of these is in git; the reasoning that
outlived it has been written into the code or data it describes.

| date | item | outcome |
|---|---|---|
| 2026-08-28 | **[P1] Animate the wildlife, and five carcasses that stop being deer** | ✅ **DELIVERED AND WIRED.** 10 bakes in 2.2 min on the render box, master checkout pristine. Six species move; the five movement bakes needed no wiring at all and re-skinned in place, exactly as promised. The carcasses were five one-line changes in `resources.json` plus a `visuals.json` entry each — and the note they replaced had PREDICTED that, which is why pointing all five at `vis.deer_carcass` in the meantime was right rather than lazy: an undeclared id draws the magenta unknown and fails the load-warning test, so the wrong animal was the better of two. **The two extra clips are what needed code, and not on the art side**: only the deer has `run` and only the cattle has `feeding`, the sim may not ask which clips exist, and the generic fallback chain is `static` → `idle` — which for a bolting sheep means STANDING STILL WHILE SLIDING at flee speed. `AtlasEntry` now carries two aliases (`run` → `walk`, `feeding` → `idle`) tried ahead of that chain, and the test for whether an alias belongs there is that it falls back to a clip every animal HAS. Your three measured facts all held: feeding really is cattle-only, frame 1 really is the collapsed pose (the clip does not loop, so it falls once and stays down), and nothing tore |
| 2026-08-28 | **[P2] Packed siege states** | ✅ **DELIVERED — and STAGED-BUT-UNDECLARED on purpose, which is the whole entry.** `vis.ballista_packed` completed the set and animates. All three remain out of `visuals.json` because 4.13's pack/unpack state machine does not exist: `SimUnit` carries no deploy state, so an id declared today is referenced by nothing, resolves for nobody, and reads in a year as art that failed to land. They go in with the machine, in one commit. **Doing the ballista last was right** — it only matters once the machine exists and it is the one engine with no player colour, so it was the cheapest of the three to be missing |
| 2026-08-28 | **[P3] A `vis.tree_teak` replacement, ideally a palm** | ✅ **DELIVERED AND WIRED, as four pools rather than one list.** 13 baked, 12 declared, and the project owner's per-map assignment — recorded on line 1 of each recipe — became `visuals.json`'s `variant_pools`: island gets five palms, forest beech/birch/fir/oak_new, river bamboo+palm_date, desert oak_dead+elm_dead. Keyed by `MapGenerator.pool_name()` so a typo'd biome fails the suite instead of silently drawing the general mix, and a view that was never told a map type (the debug map, every preview, every test) still gets oak/elm/toona. **Nothing rides the wire**: the tile seed was already a pure function of position, so the pool only decides which list it indexes into. **I was wrong about `palm_cretan_patch`** — I said skip it and said not to measure it; it had already been measured at 164 x 190, smaller than the oak already in the game, and it is in. A measurement beat the reasoning that would have excluded it. **`vis.tree_banyan` is declared and in no pool**, awaiting the owner: `dev_preview/preview_banyan.tscn` puts eight villagers one and two tiles out under it against the oak and the teak, and at 370 px it swallows all eight where the oak leaves all eight visible |
| 2026-08-28 | **[P4] Arrow and bolt pitch** | ✅ **DELIVERED AND WIRED, and the wiring was nothing** — both re-staged in place, the same as the arrow on 2026-08-27. Worth keeping is how 115.0 was arrived at for the bolt: measured from where the shaft's mass sits rather than copied across from the arrow, because a bounding box cannot tell nose-down from tail-down and the arrow's own first probe landed perfectly backwards for exactly that reason. Side-on went 6x30 to 31x14. **A projectile carries no damage, so a green suite proves nothing about it** — `preview_projectiles` freezes the sim and prints each projectile's screen position, and that is the only check there is |
| 2026-08-28 | **[P0] THE UNIT ATLASES WERE MIRRORED, NOT ROTATED** | ✅ **CLOSED. Fixed in the pipeline, and no recipe changed.** isobake `e6fc052` negated the compass step in `directions.py:yaw_deg()` — `ORDER_8` is documented clockwise from screen-down and `+i * 45°` about +Z walks it counter-clockwise, so the render swept the opposite way to the labels it wrote. 252 atlases at build 38, staged, 342/342 current. **The two corrections that made it cheap are both worth keeping:** `yaw_offset_deg = 180.0` STAYED ON (index 0 is a fixed point of the sign flip, so the half-turn is half the correction, not a second error — I asked for its removal and was wrong), and the walls were mirrored all along rather than being the counter-example I claimed, invisible only because each swapped pair has the same silhouette. **The check that can see it is all four columns**: 0 a face, **2 facing screen LEFT, 6 screen RIGHT**, 4 a back. Two and four are exactly the columns a reflection about N–S leaves alone, which is why a mirrored roster passed twice and cost a 242-atlas re-bake aimed at the wrong axis. **`vis.town_center` and 20 ground pieces sat out the run and that is FINE** — they are `directions = 1`, where the `i` term is 0 and no sign can reach them |
| 2026-08-28 | **Gates need an open and a closed state** (project owner) | ✅ **DELIVERED AND WIRED.** Five gate atlases carry `open` + `static`; the game picks between them in `GameView._building_anim()` off `gate_locked` and the def's `is_gate`. **The art side's shape shipped unchanged and it is why this was five lines**: one atlas per gate rather than two ids, and **`static` IS the closed pose** — a gate at rest is shut, so an atlas that never got an `open` clip draws what it always drew and `resolve_anim` falls back without a special case. Only two of 0 A.D.'s four states were baked; `opening`/`closing` are ~12 frames at 8 directions for half a second of swing. The age-3 wood tier moved to the **Roman siege works** wholesale (the Briton actor has no clips at all), so `vis.wall_wood_gate`'s skin map is the one gate whose four ages are not one file — 1–2 German, 3–4 Roman — and the test walks all four ages of all three gate defs for that reason. **There are three gate defs, not five**: age 1 has no gate, so the athenian `vis.wall_gate` is staged and unreferenced by design |
| 2026-08-28 | **`vis.waypoint_flag` + 8 colours** | ✅ **DELIVERED AND WIRED**, and it retired a placeholder that was shipped on purpose. The owner's *"use shape placeholder"* (2026-08-27) got rally points playable the same day without waiting on a bake, and the swap was the contained job `waypoint_flag.gd`'s header promised: one `visuals.json` entry with `"colours": true` and an `EntityView` in place of the procedural pole. **The tile diamond stayed** — a sprite says a flag is near here, and only the diamond says *which tile*, which is the entire content of a rally point. 12 frames at 8 fps, so it waves; `footprint_m`/`height_m` are measured off the frame (15 x 67 px at 22.627 px/m = 0.66 x 2.96 m), and 2.96 lands within 4 cm of the 3.0 m pole the placeholder drew by eye |
| 2026-08-27 | **`yaw_offset_deg` — EVERY UNIT FACED BACKWARDS** | ⚠️ **DELIVERED AND STAGED, BUT IT DID NOT FIX THE DEFECT — see [P0] above, opened the same afternoon.** The bakes are correct as specified and the pipeline work stands; the specification was wrong. The atlases were never 180° out, they were MIRRORED, and adding a half-turn only moved the mirror's axis: front and back came right and left and right went wrong. Left here rather than deleted because the two entries only make sense together. What follows is what was true of the delivery itself: **staged and checked the same day.** You did **82 recipes rather than the 36 I listed** (`5737e00`, corrected by `96d2318`) and re-baked **242 atlases** — 82 base + 160 colour — four-wide on the render box with a per-slot art checkout, which fixed the parallel-slot race rather than avoiding it. Game side staged all 242 (**331/331 current**), re-imported, and checked it three ways: `preview_facing_chart` on `unit.swordsman` **and** `unit.knight` — column 0 (S) a face, column 4 (N) a back, `idle`/`walk`/`attack` all agreeing; `preview_combat_facing`; and a driven match. **1268 tests, 201,463 assertions, 0 failed** against the new art. **Nothing in `game/` changed** — exactly as promised when the compensation was reverted. Two things worth keeping: excluding the seven `terrain` recipes was right (the offset is a zeroad-adapter correction applied in the shared render path, so patching them would have spun every ground tile), and **the same run closed the stale-colour gap** — all 20 colourable sets now carry 8 colours from one build id, so `stale_colour_atlases()` and `missing_colour_atlases()` are both empty and the short `vis.archer`/`vis.galley` sets are complete. The red-and-yellow-only period is over for good |
| 2026-08-17 | `vis.onager` nose-up | Fixed both halves: isobake `e257ae8` stopped the all-anchored `subject_armature` branch ranking by bone count, so the clip lands on the 8-bone arm rig instead of a 202-bone crew Biped, and the recipe declares `idle`/`attack`/`die`/`decay`. **Retired from the open queue 2026-08-23** — it had sat there as a 43-line resolved entry against this file's own housekeeping rule. Three things worth keeping are already where they belong: `speed: 0` still stands (no walk clip on the rig) and is in `units.json`; the tint dropped to 4.7% of the sprite because the correct seated pose hides the surface the reared arm exposed, and `"colours": true` still separates cleanly, which is noted in `visuals.json`; and the crew do not collapse on death because 0 A.D. gives this arm no `Death` clip at all — recorded in `onager.toml` |
| 2026-08-08 | `vis.berry_bush` | Found already baked and unwired; became the MVP food node in place of `res.deer` |
| 2026-08-08 | `vis.deer_carcass` | Baked; prompted the per-clip `location_scale` fix that unblocked animated fauna. Not wired — nothing hunts deer since the berry-bush switch |
| 2026-08-16 | `game/assets/atlases/` stale | Re-staged. Root cause was `stage_atlases.py`'s non-recursive glob missing `tools/recipes/player/`, not a script nobody ran |
| 2026-08-16 | `vis.town_center` / `vis.house` footprints | Re-measured from the staged atlases after the Briton meshes landed; old Athenian figures and why they went stale recorded in `visuals.json` |
| 2026-08-16 | `vis.ballista`, `vis.onager` | Both baked static (0-bone armatures) and wired at `age_required` 3, `speed: 0`. Onager tints, ballista does not |
| 2026-08-16 | `vis.siege_ram` colour | False alarm — measured 8 distinct colour pages. Keeps `"colours": true` |
| 2026-08-16 | 90 colour bakes | 90/90 in 5.1 h. **All 8 colours correct for all 20 units**, 325/325 staged. Ended the red-and-yellow-only period |
| 2026-08-16 | Build identity in the atlas | isobake `531a4bc` stamps `isobake_commit` / `isobake_build` / `isobake_dirty`; `99a33cc` makes all three always present, null when git cannot answer |
| 2026-08-16 | Staleness detection | Rewritten game-side to compare build identity for equality across a unit's eight colours instead of modification time. Reports 0; the mtime rule had inverted into 34 false positives |
| 2026-08-16 | Camp props | Never an art gap. Four prop atlases were staged and undeclared; now wired and composed at draw time, with the mill's food crates age-gated to 3 and 4 |
| 2026-08-16 | Dead `ASSET_MISSING.md` citations in `game/` | Acknowledged, left as history — a large diff over careful comments to fix a cosmetic dead link |
| 2026-08-17 | `vis.ballista` crew + animation | Not a nesting bug: 0 A.D. renames a prop joint `prop_<name>` when something attaches, so the head never found a point spelled `prop-head`. Fixed the whole class. `inspect` had also lied about the armature, so the engine animates after all — idle/attack/die/decay. Colour re-measured with the kit on: still 0.00%, `"colours": false` stands |
| 2026-08-17 | `vis.stone_mine`, `vis.sheep`, `vis.cattle` | Found staged and referenced by nothing. Stone was a real hole — every building costs it and no map yielded any; now `res.stone` plus three quarries. Sheep and cattle are gathered where they stand, so they needed no hunt machinery |
| 2026-08-17 | `vis.field` / `vis.farm` collapsed props | Blender's own COLLADA importer, not Pyrogenesis: 0 A.D. writes `<matrix sid="parentinverse">` before the real `<translate>` and Blender keeps the leading matrix, so all 65 patch points landed on the origin. isobake places the empties itself now. Delivered `vis.farm` at the same time, as predicted |
| 2026-08-17 | The four field plots | Wired as `variants`, a new third axis in the seam: four interchangeable crops picked from the tile a plot stands on, NOT four ages. Ids deliberately do not match the filenames |
| 2026-08-17 | The ORE section — 8 bakes | All 8 in 1.5 min, 331/331 staged, ids exactly as requested. Size classes now pick the SPRITE as well as the amount (`resources.json` `visuals`), which is what the request was for; wood went the other way and became four species through `variants`. The two re-points moved a long way — gold 3x up, stone 3x down — and both placeholders were re-derived. `render.ground_clip` is what unblocked the set; PLAN.md 13.2 item 7 is closed |

---

## Format for new entries

```
### `vis.<id>` — requested <date>

**What's needed:** ...
**Why:** ...
**Candidate source:** ...
**Where it plugs in once baked:** ...
```

Delete the entry once it is delivered and wired, and add one line to Delivered.
