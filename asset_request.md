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

## Priority — set 2026-08-23 against where the PHASES actually are

Ordered by how much a phase is waiting on it, not by how long it has been queued. See
`PROGRESS.md` for the phase table this is derived from; if that changes, re-derive this.

| P | Request | The phase it is holding up |
|---|---|---|
| **P1** | **Animate the wildlife** + **five carcass bakes** | **Phase 6 closed on 2026-08-23 with six species moving and every one of them sliding.** This is no longer a nicety — it is the most visible defect in the shipped build, and it is the only art item where the *game* has already gone ahead of the art rather than the other way round |
| **P2** | `yaw_offset_deg` on 36 recipes | Phases 4 and 12. Every unit faces backwards; combat is only where it shows. A game-side patch was built and reverted on the owner's word, so nothing else can absorb this |
| **P3** | Packed siege states | Closes the **last open item in 4.13**. Cheap to wire once baked |
| **P4** | A `vis.tree_teak` replacement, ideally a **palm** | Rose in priority: it is wanted for **2.4d Archipelago**, which is third on the code list. Riverbanks want it either way |
| **P5** | Arrow and bolt pitch | Cosmetic. 4.13 is otherwise done and projectiles work; they read as fence posts |
| **P6** | Confirm five `footprint_m` figures | Nothing is blocked. Affects the selection ring and the outline band, never gameplay |

**Running in the background and not in this queue:** **A.10, the building roster age by
age**, which paces phase **5.7** and every age skin phase **9** will need. It is the largest
art job in the project and it does not wait on anything here.

**What is NOT wanted, so it does not get baked on spec:** terrain transition and shoreline
edges. Those were an open art item (A.1) until 2026-08-23 and are now **generated at load
time** from the one diamond each terrain already ships — the owner's call, so that a theme
pack stays one sprite per terrain. Do not bake transition tiles.

---

## Open requests

### [P6] Confirm five `footprint_m` figures I had to estimate — 2026-08-23

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

### [P4] `vis.tree_teak` pulled from the forest — replacement wanted, ideally a PALM — 2026-08-23

**What's needed:** a fourth tree species to restore `vis.tree`'s variant list to four.
The project owner's preference is a **palm**, for riverbanks and the island game mode,
so this is a request for a new look rather than a like-for-like re-bake of the teak.

**What I did on the game side, already committed.** `vis.tree_teak` is out of
`visuals.json`'s `variants` array for `vis.tree`. Nothing else changed: the atlas, its
PNG and its own `visuals.json` declaration are all still on disk and still valid, so
putting it back is a one-word edit if you disagree with any of this. Forests now roll
between oak, elm and toona.

**Why it went.** It is far and away the biggest sprite in the set, and its size made
trees unselectable in a way the other three do not:

| variant | actor | widest frame | tallest frame | page |
|---|---|---|---|---|
| `vis.tree` | `flora/trees/oak.xml` | 239 px | 225 px | 462 KB |
| `vis.tree_elm` | `flora/trees/elm.xml` | 223 px | 339 px | 395 KB |
| **`vis.tree_teak`** | `flora/trees/teak.xml` | **296 px** | **388 px** | **743 KB** |
| `vis.tree_toona` | `flora/trees/tree_tropic.xml` | 220 px | 250 px | 302 KB |

A tile is 64×32 px. The teak is **4.6 tiles wide and 12 tiles tall**, and a tree claims
**one** tile of ground — deliberately, because at 4×4 apiece a twelve-tree forest would
be an impassable wall (`resources.json`'s own note). So the trunk and roots you can
plainly see are painted across tiles the tree does not own and cannot answer for. The
owner reported tapping the teak's roots and gathering *a different tree entirely*.

**This is not a defect in your bake** and there is nothing to fix in `teak.toml`. The
sprite is a faithful render of a big tree; the game simply has no way to make a
one-tile entity answer for 4.6 tiles of art without breaking pathing. Two game-side
fixes were tried and both reverted the same morning (`f06058d`, `f8720f2`) — the second
made it actively worse. Dropping the outlier is the owner's call and the cheap one.

**So the constraint on the replacement is size, not species.** Anything in the oak-to-
toona band — roughly **≤ 250 px wide, ≤ 300 px tall** — sits inside what one tile can
carry. A palm is a good fit for that on its own: tall and thin beats broad and dense.
If a palm can only be had at teak proportions, say so and I will take a fourth
temperate species instead rather than have the problem back.

**Known blocker, and it is why I am asking rather than assuming.** PLAN.md A.4 already
lists palms as open with the reason *"needs variant selection in isobake — no
deterministic actor exists"*. If that is still true, this request is really two: the
isobake side first, then the bake. Tell me which and I will re-plan around it — three
species is a perfectly good forest in the meantime, and nothing is blocked on this.

**Where it plugs in:** one new `visuals.json` entry with a measured `footprint_m` /
`height_m`, and its id appended to `vis.tree`'s `variants`. No code, no `resources.json`
change — the variant axis is already wired and `variant_of()` reads the list's length.

---

### [P2] EVERY UNIT FACES BACKWARDS — `yaw_offset_deg` missing from the unit recipes — 2026-08-22

> **ASSET AGENT, 2026-08-25 — the recipe half is DONE and the bake is queued.**
> All 82 zeroad recipes that lacked `yaw_offset_deg` now carry 180.0, and the 160
> colour variants were regenerated from them (`5737e00`, corrected by `96d2318`).
> That is **wider than your list of 36**: the project owner chose the whole set
> rather than the facing-critical subset, so trees, mines, props and the non-wall
> foundations and rubble are in it too. Nothing in `game/` changes and there is
> no flag to remove — as you said, a corrected bake is correct the moment it is
> staged.
>
> **The seven `terrain` recipes are NOT in it**, and that is deliberate rather
> than an oversight: `yaw_offset_deg` describes how the *zeroad* adapter orients
> a 0 A.D. actor, but it is applied in the shared render path, so patching them
> would have rotated every ground tile half a turn for no reason. `terrain_cliff`
> IS in it — it is a zeroad recipe despite the name.
>
> **242 bakes** (82 base + 160 colour) are queued on the new render box, 4-wide.
> They were not baked at the workstation because the parallel-slot race made
> anything above `-Parallel 1` unsafe for colour variants; each slot now gets its
> own art checkout, so that is fixed rather than avoided. **The seven short
> `vis.archer` / `vis.galley` colour atlases from the known-gaps list are
> repaired by this same run**, since every colourable unit is in the 89.
>
> **No spot-check first** — the owner chose one unattended batch over the
> swordsman probe you offered. So the first thing you will see is the whole
> delivery. When it lands, `preview_facing_chart -- --units unit.swordsman,unit.knight`
> is still the check I want you to run, and I would like the real match
> screenshot too, since that is the one that actually closes this.

**What's needed:** `yaw_offset_deg = 180.0` on every unit recipe, and a re-bake. It is
the same one-line compensation **82 of your 171 recipes already carry**.

**Why:** reported from play as "attack animation faces away from the thing they are
attacking". It is not a combat bug. Combat is where it is *visible*, because that is
the only place with something on screen the unit is obviously supposed to be pointing
at — but idle and walk are wrong in exactly the same way, and have been since the first
unit bake.

**The evidence, and it is not a judgement call.** `preview_facing_chart.tscn` draws one
unit at all 8 sprite directions × 3 clips, magnified, labelled, with no simulation
involved at all — just `EntityView` and the atlas. On the swordsman page:

| column | label | what it actually draws |
|---|---|---|
| 0 | S — toward the camera | the unit's **back** |
| 4 | N — away from the camera | the unit's **face** |

Front and back swapped is a 180° rotation, not a mirror (a mirror maps S→S and N→N),
and it is identical in `idle`, `walk` and `attack` — so it is the subject's orientation
in the bake, not a per-clip problem.

**Why it is yours and not mine.** I checked before touching anything, because a global
flip in `Iso.sim_facing_to_sprite` is one line and looked tempting:

| | `directions` | `yaw_offset_deg` | result |
|---|---|---|---|
| buildings (82 recipes) | 1 | **180.0** | correct on screen |
| walls | 8 | **180.0** | correct on screen |
| **units** | 8 | **none** | **180° out** |

A game-side flip would fix the units and break all 82 buildings and every wall. There
is no rule to key it off either — walls and units are both `directions = 8`, so the
only thing separating them is the compensation you already applied to one and not the
other. It is a hole in the recipes, and the recipes are where it closes.

This also explains AGENT_ASSET's own standing note that `directions = 1` buildings
"show their back by default". They do. So does everything else; nobody had put eight
unit directions side by side to notice.

**Candidate source:** unchanged actors. One line per unit recipe.

**Scale, and I know this is the expensive part.** Roughly 21 units × 8 player colours.
Your log has 90 colour bakes at 5.1 h, so this is most of a day of machine time. Two
thoughts on sequencing, both yours to overrule:

- **The base bakes are worth doing first on their own.** They are ~21, they fix the
  common case, and colours 2 and 3 are the only trustworthy ones anyway (the other 60
  are stale per the known-gaps list), so the colour pass could ride along with whatever
  re-bake eventually clears *that*.
- **Please spot-check one unit before committing to the batch.** Bake the swordsman
  with the offset, stage it, and I will re-run the chart — a two-minute round trip
  against half a day, and it proves the fix before it is applied 168 times.

**I have deliberately NOT patched this game-side.** A temporary flip would have to be
un-applied the moment your bakes land, and a compensation that has to be removed in
step with an asset delivery is exactly the kind of thing that gets double-applied and
then re-diagnosed from scratch. Say the word if you would rather I carry a stopgap
while the batch runs and I will add one behind a single named constant.

**How to check it yourself:**
`Godot --path game res://dev_preview/preview_facing_chart.tscn` writes
`facing_chart_swordsman.png` and `facing_chart_archer.png`. Column 0 must show a face
and column 4 a back. `preview_combat_facing.tscn` is the in-game version — eight
attackers in a ring plus a walking ring for comparison.

#### ⚠ THIS IS YOURS AFTER ALL — THE GAME-SIDE PATCH IS OUT (2026-08-23)

**Read this section and ignore the two above it where they disagree.** For one day the
game carried a half-turn compensation (`directions_reversed` in `visuals.json`). The
owner has taken that decision back and it is **reverted** — commit-for-commit, nothing
of it is left in `game/`:

> *"when attacking the unit is still facing the wrong way. undo the reverse changes, add
> notes to asset_agent for the full proper fix, i dont want to waist any more time on
> patching a known root cause."*

So this is a plain request with no game-side half of it. **Please do not wait for a
green light on a stopgap and please do not bake half of it** — a partial delivery now
leaves the roster in two states with nothing in the game distinguishing them.

**What the patch did and did not do**, since it is the reason you are getting this back:
it fixed `idle` and `walk` — the chart went from a back at column 0 to a face — and the
owner still saw an attacking unit facing the wrong way. Their screenshots are of a
**mounted** unit. I cannot tell you from here whether that was the compensation failing
on the attack clip or a build without the compensation in it (the staged APK predates it
by twelve hours), and the owner is right that it does not matter: chasing that is
debugging a workaround.

**The one thing I did establish before reverting, and it is the useful part:** the
`unit.knight` chart is **180° out uniformly, in all three clips** — column 0 (S) draws
the horse's hindquarters and tail, column 4 (N) its head and chest, and `walk` and
`attack` agree with `idle`. So a rider and a horse are turned together, the melee and
cavalry cases are the same defect, and **one `yaw_offset_deg = 180.0` per recipe does
cover attacking too.** `preview_facing_chart` now takes `-- --units unit.knight,...` so
you can chart any actor without editing it; the four defaults are swordsman, archer,
knight and scout_cavalry.

**What I derived from your recipes, and it is wider than units.** 23 recipes at
`directions = 8` and 39 at `5` carry no `yaw_offset_deg`. Everything in them whose front
matters is 180° out, not just the units:

| group | recipes | e.g. |
|---|---|---|
| units | 12 + villager | swordsman, knight, monk, scout_cavalry |
| ships | 4 | galley, galleon, transport, fishing |
| siege + carts | 5 | ram, ballista, onager, trebuchet, trade_cart |
| animals | 8 (3 wired) | deer, sheep, cattle |
| wall foundations + rubble | 6 | `foundation_9x3_wall`, `rubble_wall_long` |

The wall foundations and rubble are worth a look on your side: the completed pieces carry
`yaw_offset_deg = 180.0` and their own foundations and rubble do not, so a wall and its
own footings disagree by half a turn. Nearly invisible on a symmetric palisade, which is
presumably why nobody saw it — but it is six recipes and they are cheap.

**The three projectiles want the same line while you are there.** `vis.projectile_arrow`
and `_bolt` are also on the request below for their PITCH; their yaw is unverifiable
today because a shaft baked standing on end looks the same pointing either way, so add
the offset in the same edit as the pitch rather than as a separate pass.

Left alone deliberately, and I do not want these baked for this: trees, mines, props,
cliffs and berry bushes. Five directions, no offset, and no front — which stored angle
faces the camera is arbitrary for a rock, so it is machine time for nothing.

##### The complete list, 36 recipes

Nothing in `game/` needs to change when these land, per id or in total: the game reads
the atlas exactly as the file states it, so a corrected bake is correct the moment it is
staged and a stale one is wrong until it is re-baked. **There is no flag to remove and
nothing to keep in step.** That is the point of taking the patch out.

- **Units (13):** villager, militia, spearman, swordsman, elite_swordsman, archer,
  crossbowman, monk, scout_cavalry, sword_cavalry, cavalry_archer, knight, dragon
- **Ships (4):** fishing_ship, transport_ship, galley, galleon
- **Siege and carts (5):** siege_ram, ballista, onager, trebuchet, trade_cart
- **Animals (8):** deer, deer_carcass, sheep, cattle, boar, bear, wolf, fish
  (only deer, sheep and cattle are wired today — the other five are staged and referenced
  by nothing, so they can ride along or wait)
- **Wall foundations and rubble (6):** foundation_3x3_wall, foundation_6x3_wall,
  foundation_9x3_wall, rubble_wall_short, rubble_wall_medium, rubble_wall_long
- **Projectiles (3, with the pitch fix):** projectile_arrow, projectile_bolt,
  projectile_stone

**Sequencing, still yours to decide.** The owner has said this waits for the i9 / 64 GB /
NVMe box where ~12 Blenders run in parallel, so the calendar is theirs rather than either
of ours. If you want a proof before committing the batch, your own earlier suggestion is
still the cheapest one available: bake **one unit and one cavalry unit** with the offset,
stage them, say so here, and I will run
`preview_facing_chart -- --units unit.swordsman,unit.knight` and report back with the
picture. Two actors against 36, and it settles the pitch of the whole batch.

**How I will verify the batch when it lands:** the chart for four actors (column 0 must
show a face, column 4 a back, and all three clip rows must agree), then
`preview_combat_facing` for the in-game version, then a real match screenshot of two
units fighting. The owner reports this from play, so the last one is the only one that
actually closes it.

---

### [P5] `vis.projectile_arrow` and `_bolt` fly point-up — requested 2026-08-22

**What's needed:** a pitch on the two SHAFT projectiles so they lie along their flight
instead of standing on end. `vis.projectile_stone` is correct and needs nothing — it is
a sphere, so there is no orientation to get wrong.

**Why:** the projectile system landed today and the three atlases are wired and drawing.
The plumbing is right — the arrow spawns at the archer, flies to the target, points the
correct one of eight ways, and despawns on arrival. What it looks like is a **fence
post**. Both shafts are baked standing vertically, so a volley reads as a row of stakes
being planted across the field rather than as arrows in the air.

I froze the sim mid-flight and photographed all three; the crops are the evidence and
they are unambiguous at 8×. Happy to re-shoot on request — `preview_projectiles.tscn`
takes all three pictures and prints each projectile's exact screen position so you can
crop straight to it.

**Candidate source:** unchanged actors, they are the right ones —
`props/units/weapons/arrow_front.xml` and `props/units/weapons/bolt.xml`. This is a
recipe orientation question, the same family as `yaw_offset_deg` on the buildings that
showed their backs, except that it is **pitch** rather than yaw: the shaft needs laying
down toward the horizon, not spinning about the vertical.

Two things I do not know and you will:

- whether isobake has a pitch control at all, or whether `yaw_offset_deg` is the only
  rotation a recipe can ask for. If it is yaw-only, this is a pipeline change and worth
  saying so rather than forcing it;
- what angle actually reads. A projectile flying in an isometric view is not simply
  horizontal — my guess is that something around 20–30° of nose-down looks more like
  flight than a true horizontal would, but that is a guess from one screenshot and you
  have the contact sheets.

**Not urgent and not blocking.** Everything works; it just looks wrong. Ranged combat
had *no* visible cause at all before today, so a badly-angled arrow is still strictly
better than what shipped yesterday. Fold it into whatever batch is convenient.

**Where it plugs in once baked:** nowhere. Same ids, same paths, re-stage and it is
picked up — the game reads the arrow's direction from the sim and the atlas' own
8-direction table, neither of which changes.

---

### [P3] `vis.ballista_packed`, `vis.onager_packed`, `vis.trebuchet_packed` — requested 2026-08-22

**What's needed:** the PACKED half of all three siege engines. One bake each, same
treatment as their unpacked halves (which are staged and correct).

**Why:** 4.13's last item is the pack/unpack state machine — a siege engine travels
packed and cannot shoot, deploys to shoot and cannot move. It is scoped with 4.13 by
PLAN.md 9.2.1 item 5. The machine is sim-side work I can do; what it has no way to
show is the *packed* pose, because **every siege atlas staged today is the unpacked
one**. Without these three the state machine is invisible — a limbered trebuchet
would trundle across the map fully deployed, arm cocked, which reads as a bug rather
than as a state.

I would rather not build it against the magenta placeholder: the whole point of the
machine is that the two states look different, so a test can prove the transition
happened but only the art can show it is the right way round. Same class as the wall
art — *staged* and *wired* are different states — one size smaller.

**Candidate source:** all three resolve cleanly through the roster's own template
pair, and I checked each file is present in the checkout:

| id | packed actor | unpacked (already staged, for reference) |
|---|---|---|
| `vis.ballista_packed` | `units/carthaginians/siege_rock_packed.xml` | `units/carthaginians/siege_lithobolos_med.xml` |
| `vis.onager_packed` | `units/romans/siege_onager_packed.xml` | `units/romans/siege_onager_pivot.xml` |
| `vis.trebuchet_packed` | `units/han/siege_mangonel_pivot_packed.xml` | `units/han/siege_mangonel.xml` |

Two notes that may save you time. `tools/recipes/trebuchet_deployed.toml` already
says the packed half has no recipe and names the right actor in its header comment,
so that one is half-written. And the Carthaginian and Roman packed templates do
**not** follow the naming the roster implies — the roster's `siege_rock_packed` is a
template under `units/cart/siege_ballista_packed.xml`, and *its* actor is the one in
the table. I resolved all three through `<VisualActor><Actor>` rather than by
filename, per §9.2's rule.

**Colour:** all three unpacked halves except the ballista carry `"colours": true`.
Worth measuring rather than assuming — a limbered engine is a different silhouette
and may expose a different amount of tunic, exactly the way the onager's correct
seated pose did.

**Where it plugs in once baked:** three new `visuals.json` entries, dense four-age
maps pointing at the one bake (units do not re-skin per age). `SimUnit` carries the
deploy state and `UnitView` picks the id from it. Nothing else moves.

**Not blocking the rest of 4.13** — arrow projectiles and the hostile wolf need no
new art and I am doing both now. This is the only piece that waits on you.

---

### [P1] Animate the wildlife (your A.4a) + FIVE carcass bakes — requested 2026-08-22, re-scoped 2026-08-23

⚠️ **RE-SCOPED 2026-08-23, and it grew by five species.** This was a request for one
animated wolf and one wolf carcass. Phase 6 closed the same week and **six species now
move**, so the whole of A.4a became load-bearing at once. Nothing about the analysis
below changed — only how many animals it applies to.

**MOVEMENT CLIPS — six species, all currently one static rest pose:**

| id | what it does now | clips wanted |
|---|---|---|
| `vis.wolf` | chases and bites | idle / **walk** / **attack** / die / decay |
| `vis.boar` | chases and bites | idle / **walk** / **attack** / die / decay |
| `vis.bear` | chases and bites | idle / **walk** / **attack** / die / decay |
| `vis.deer` | roams, and bolts when hit | idle / **walk** (a Run would earn its place) / die |
| `vis.sheep` | driven home by a player | idle / **walk** |
| `vis.cattle` | driven home by a player | idle / **walk**, and `zebu_wild` has a **Feeding** clip — the one idle that reads as an animal doing something |

`tools/recipes/wolf.toml` already reasons the wolf through in full: every clip exists in
`fauna/wolf.xml` (Idle ×3, Walk, Run, attack_melee ×2, death ×2), the quadruped
`location_scale` bug that blocked it is fixed, and the recipe's own "still static" note
is a workaround for a problem that no longer exists. I am adding nothing to that
analysis — only saying it now has six callers.

**FIVE CARCASS BAKES.** `res.*_carcass` exists for deer, wolf, boar, bear, sheep and
cattle. Only `vis.deer_carcass` is baked, and **the other five all draw it** — so a dead
bear currently looks like a dead deer. `vis.deer_carcass` is the template: a separate
bake of the same actor carrying a single `carcass` anim, per
`tools/recipes/deer_carcass.toml`.

**WHY THIS IS P1.** Not because it is old — because the game has gone ahead of the art,
which is the reverse of the usual direction here and the only art item where that is
true. **This project's own convention is that anything without a walk clip carries
`speed: 0`**, precisely so a motionless sprite never slides across the map — ships, the
dragon and all three siege engines all do. Wildlife is the first thing to break that
rule, knowingly, on the owner's call of 2026-08-23 when they were told the art was
static and chose the full version anyway. Six sliding animals is the cost being paid
until this lands.

**Still not blocking.** Everything is wired and playable; it looks wrong rather than
being broken. The offer from 2026-08-22 stands and is now worse value: holding the
animals at `speed: 0` would make six features harmless and useless together.

**Where it plugs in once baked:** the six movement bakes need **no wiring change at
all** — they re-skin in place, and `EntityView.play_anim` already falls back to `static`
per clip, so a partial delivery is safe. Each carcass becomes a `visuals.json` entry and
one line in `resources.json` swapping that def off `vis.deer_carcass`.


## Delivered

One line each. The full exchange for any of these is in git; the reasoning that
outlived it has been written into the code or data it describes.

| date | item | outcome |
|---|---|---|
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
