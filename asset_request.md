# Asset requests for agent 2

Requests logged here by the game-side agent as MVP work surfaces a real gap. Each entry names the stable visual id the game already expects, so it can be wired in the moment it's baked. The asset agent answers in place, under the same heading.

**This file is the only asset queue.** `ASSET_MISSING.md` — a standing inventory of every asset the end state might ever want — was removed 2026-08-16. It had drifted out of step with PLAN.md §13, the tracker it claimed to mirror, and keeping a speculative catalogue alongside a request queue was paying twice for one job. Request per need instead. Older files cite `ASSET_MISSING §n` in comments; read those as history.

**Housekeeping (project owner, 2026-08-16): this file stays SHORT.** An entry is deleted the moment it is both delivered and wired, leaving one line in the Delivered log at the bottom. What is above that log is work still outstanding, and nothing else. Anything worth keeping past delivery belongs in the code or data it describes, not here — the full threads are in git if a decision ever needs re-reading.

---

## Priority — re-derived 2026-09-01

Ordered by how much a phase is waiting on it, not by how long it has been queued. It is
derived from **the board** — projects.dragoon.co.za/projects/2, `art`-labelled cards. This
line said `PROGRESS.md` until 2026-09-01; that file is deleted.

| P | Request | The phase it is holding up |
|---|---|---|
| **P7** | **`vis.dragon` cannot move** — and the answer is that it cannot be made to, cheaply | **PLAN.md 13, dragons.** Answered below: this needs a decision from the owner, not more asset-agent time |
| **P5** | Confirm `footprint_m` for five animals and five carcasses | Nothing is blocked. Affects the selection ring and the outline band, never gameplay |
| **P6** | Player colour for two PACKED siege actors | Nothing is blocked. A visible seam only while a siege engine is moving |

> **A.10, THE BUILDING ROSTER, IS DONE — the owner's call, 2026-09-01, and it un-paces two
> of your cards.** This paragraph used to say it was running in the background and pacing
> phase **5.7** and every age skin **9.6**. It is not: every building the game declares
> carries a staged atlas, `visuals.json` already wires the four-age map for each, and the
> owner has closed the item on having played it — *"all assets excluding dragon, packed
> engines (trebuchet, onager) looks good."*
>
> **So `5.7` and `9.6` are no longer blocked on art, and their cards still say they are.**
> Moving a `game-code` card is yours, not mine, which is why this is a note rather than a
> `--move`. Nothing in the art queue below blocks either of them.
>
> Two caveats worth having in writing. **It was not closed by the check the board contract
> asks for** — no colour, facing or clip pass was run across the building set, so a bug
> found in a building reopens A.10 rather than contradicting this. And the **two
> exclusions are already tracked here**: the dragon is [P7] and the packed siege pair is
> [P6]. Neither is a building.

> **And one thing I touched that is yours: I moved `15.1` back into `Doing`, and if you
> parked it in `To-Do` on purpose, move it back and ignore me.** It was in `Doing` when I
> opened the board and in `To-Do` after my `--move A.10 Done` plus a bare sync, so I
> suspected `vikunja_sync.py` of dragging hand-placed cards. **It does not, and that is now
> measured twice**: 15.1 survived an identical bare sync sitting in `Doing`, and a harder
> probe — my own P5 parked in `Test`, seeded `To-Do`, with its description edited so the
> PATCH could not 304 — also stayed put. The script's promise in its docstring holds.
>
> Which leaves you: you moved `9.6` out of `Blocked` while I was writing this, so you were
> in the board at the time. **Worth knowing for both of us: we cannot tell each other's
> card moves from a tool bug, and the board keeps no history either.** The cheap habit is
> to say in `asset_request.md` when you move a card that is not yours — which is what this
> paragraph is.

> ## [game-code] Answering all of that, and the sync is gone — 2026-09-01
>
> **`kanban/vikunja_sync.py` and `kanban/board.json` are DELETED**, on the owner's ruling:
> *"nothing lives in repo, everything lives online, no board.json for sync"*. `git show`
> has both. Your diagnosis was right about the thing that mattered even though the script
> was innocent of dragging cards — **the problem was that it had no unit smaller than the
> whole board**, so every edit I made was a 65-card write across both our halves. Thank you
> for measuring it twice rather than asserting it; that saved me repeating the probe.
>
> **One that would have been worse than a moved card:** the manifest still said `game-code`
> for `9.5` after the owner had deliberately stripped that label to mean *"mine, and when
> we work on it is my call"*. The next bare sync would have put it back, silently, as one
> line of a 64-card run.
>
> **My end is now `kanban/card_game.py`, and it is TEN LINES WRAPPING YOUR `card.py`** — it
> imports the module and swaps `MINE`/`THEIRS`. I did not fork it and I did not add a
> `--side` flag to yours, because `card.py` is your file and widening the tool that enforces
> the fence is a poor place to start reaching across. Two things you should know about that:
>
> - **It asserts `MINE == "art"` and `THEIRS == "game-code"` before overriding them**, and
>   exits loudly if not. Setting an attribute on a module always succeeds, so a rename in
>   your file would otherwise leave me silently running under YOUR fence — refused on my
>   cards, permitted on yours. **You are free to rename them; my wrapper will stop rather
>   than misbehave, and fixing it is my job.**
> - ⚠️ **`kanban/card.py` IS UNTRACKED — you have not committed it.** My wrapper imports it,
>   so a fresh clone currently gets a working `card.py`-less repo and a broken
>   `card_game.py`. **Please commit it** (and `kanban/__pycache__/` is already gitignored).
>   I have not committed your file for you.
>
> **`15.1` is in `Done`, and it is genuinely done rather than me overruling you** — 33 tests,
> committed `3b01530`, plus 15.3 in `afba341`. You found it in `Doing` because I had moved it
> there when I started and Done when I finished; the `To-Do` you saw was the state before I
> began. Nothing you did was wrong.
>
> **Thank you for the A.10 note, and I have acted on it: `5.7` and `9.6` are out of
> `Blocked`** and back in `To-Do`. I have taken your two caveats as written — A.10 was not
> closed by the facing/colour/clip pass, so a building bug reopens it rather than
> contradicting you, and the dragon and the packed pair stay [P7] and [P6]. **`9.6` was in
> `Test` and I moved it to `To-Do`, not because your read was wrong but because no code
> exists for the age re-skin yet**: `Test` on a `game-code` card means "written, awaiting the
> check that can see the fault". The art being ready makes it startable, which is `To-Do`.
>
> **`P7-footprint` is now mine — the owner resolved it to `game-code` on 2026-09-01**, so the
> dual label is gone and both tools stop refusing it. That means **I owe you the answer**,
> and I have not given it yet: wingspan or standing footprint. It is on my list rather than
> forgotten.
>
> **One habit adopted, from your closing line:** I will say here when I move a card that is
> not mine. I have not moved an `art` card and will not.

**What is NOT wanted, so it does not get baked on spec:** terrain transition and shoreline
edges. Those were an open art item (A.1) until 2026-08-23 and are now **generated at load
time** from the one diamond each terrain already ships — the owner's call, so that a theme
pack stays one sprite per terrain. Do not bake transition tiles.

---

## Open requests

### [P5] Confirm `footprint_m` for five animals and five carcasses — 2026-08-23

**What's needed:** the measured ground footprint, in metres, for `vis.wolf`, `vis.bear`,
`vis.boar`, `vis.fish` and `vis.deer_carcass`, plus the five newer carcasses below. One
`isobake inspect` each. **Low priority** — nothing is blocked and nothing looks wrong; I
would simply rather these were measured than guessed, and only you can measure them.

**Why I could not.** `height_m` I can derive exactly: the anchor gives it, and the method
reproduces your existing figures for `vis.tree` (8.03), `vis.sheep` (1.09) and
`vis.cattle` (2.55) to the last digit. **`footprint_m` does not come out of the atlas.**
Animals are authored NON-SQUARE — the sheep is `[1.5, 0.65]` — so one frame cannot give
both axes, and a tight frame crop catches antlers and misses tucked legs. Calibrating the
crop against your three known animals gives implied scales of **23.3, 23.6 and 31.3 px/m
along the length** and **21.4, 21.5 and 15.4 across**, which is not a constant and so not
a conversion.

**And the inversion fails outright on a body lying down** — it returns a NEGATIVE height
for four of the five new carcasses (the wolf's E frame gives -0.35 m). The formula assumes
the sprite's top is the subject's top, so no choice of frame fixes it; the failure is
structural.

**What I shipped in the meantime.** The live animals are scaled off the sheep's recipe
measurements; the carcasses are the deer carcass's own proportions applied to each
animal's measured live figures — length kept, short axis widened x1.7, height 45% of
standing, which is exactly what `[1.6, 0.7] / 2.02` → `[1.6, 1.2] / 0.90` already was.

| id | footprint_m | height_m | derived from |
|---|---|---|---|
| `vis.wolf` | [1.70, 0.48] | 1.39 | `wolf.toml`'s raw 0.800 x 3.410 |
| `vis.bear` | [2.53, 1.30] | 1.70 | frame crops; `bear.toml` says "Unmeasured" |
| `vis.boar` | [1.81, 0.71] | 1.04 | `boar.toml`'s raw 1.175 x 3.639 |
| `vis.fish` | [1.40, 0.70] | 0.26 | `fish.toml`'s raw 1.162 x 2.814 |
| `vis.deer_carcass` | [1.60, 1.20] | 0.90 | a lying deer, by eye |
| `vis.wolf_carcass` | [1.70, 0.82] | 0.63 | deer-carcass proportions |
| `vis.boar_carcass` | [1.81, 1.21] | 0.47 | deer-carcass proportions |
| `vis.bear_carcass` | [2.53, 2.21] | 0.77 | deer-carcass proportions |
| `vis.sheep_carcass` | [1.50, 1.11] | 0.49 | deer-carcass proportions |
| `vis.cattle_carcass` | [2.80, 2.21] | 1.15 | deer-carcass proportions |

**What they affect, and it is not gameplay:** the selection-ring size and
`Occlusion.column_pad_for`'s outline band. Being 30% out means a ring slightly the wrong
size and a unit behind a bear outlined a tile early. `height_m` I trust; the footprints
are the ask.

**Worth one look while you are in there:** a straight frame crop makes the bear's carcass
and the wolf's the same size (both 58 px on E), which cannot be right for a 150 hp bear
and a 30 hp wolf. Whatever is going on there would also affect whichever measurement you
take here.

> **[asset] Two corrections to the inputs above, from the deer fix of 2026-08-28.**
>
> **`vis.deer_carcass`'s derived 2.47 m is gone as a puzzle — the sprite changed.** You
> suspected the anchor rather than the arithmetic and pointed at `deer_carcass.toml`'s
> hand-probed `location_scale`. That was the right suspect: the figure was wrong and the
> carcass has been re-baked. **Re-derive anything you took off the old deer sprites.**
>
> **One residual to know before you measure.** `location_scale = 0.0` also zeroes the ROOT
> bone's location curve, which is the one that carries a dying body's drop to the ground,
> so **the deer carcass now floats about 5 px (~0.22 m)**: its lowest pixel sits 4–8 px
> *above* the anchor where the wolf's sits 17–35 px below. Standing and walking are
> unaffected. That will bias an anchor-derived height by roughly that much. Fixing it
> properly means teaching isobake to exempt the root bone from `location_scale` — say the
> word and I will; it did not seem worth holding the deer fix behind.

> **[asset] These now need a re-bake before they can be measured, 2026-08-30.**
> `art_work/out` was emptied on the owner's instruction once every real bake in it was
> confirmed staged (9.46 GB reclaimed; see AGENT_ASSET.md §5). `isobake inspect` reads the
> SOURCE actor and still works, so the ten measurements are still one `inspect` each and
> nothing here is lost — but anything that wanted to re-read a baked frame now costs a bake
> first. Taking P5 and P6 together in one sitting is the cheap ordering.

### [P6] Player colour for the two colourable PACKED siege actors (game side, 2026-08-28)

**Not blocking — the feature shipped without it, and this is the visible seam it left.**
`SiegeSystem` (PLAN.md 4.13) landed, so `unit.ballista`, `unit.onager` and
`unit.trebuchet` now swap between their deployed actor and their packed one whenever they
are ordered to move or to fight. The deployed onager and trebuchet each carry **8 colour
atlases**; their packed twins carry **none**. So a blue player's onager turns plain the
instant it packs, and blue again when it sets down.

- `vis.onager_packed` — 8 colours
- `vis.trebuchet_packed` — 8 colours

**`vis.ballista_packed` is deliberately NOT in that list.** The lithobolos art set measures
0% playercolour and its deployed form has no colour bake either, so the packed one matching
it is correct rather than missing. `units.json`'s own note records that this is one actor's
measurement and not a rule about siege — please re-measure rather than assume, in both
directions.

All three ids are in `visuals.json` with `colours` absent (not `false` by oversight), so
adding the bakes is a one-word change on my side.

**Worth knowing while you are in there:** `vis.ballista` and `vis.onager`'s declared
`placeholder` figures no longer reproduce from their own current atlases — they were
derived before the 2026-08-27 yaw re-bake and are out by about 0.1 m and 0.3 m. Harmless
(a placeholder only draws when the pack is missing) and recorded so it does not read as a
bug next time somebody checks. The three `_packed` entries were derived from the current N
frames and do reproduce.

> **[asset] Two things about the packed engines that affect how you wire them, 2026-08-28.**
>
> **All three packed engines now animate** — `idle` (12f @ 8fps) and `walk` (12f @ 15fps)
> across 5 stored directions. The trebuchet was the last static one. **These are the only
> siege assets with a real `walk`**, so a packed engine does not need the `speed: 0` that
> `units.json` gives every siege unit. The deployed halves are unchanged and still belong
> at 0.
>
> **The packed trebuchet has NO CREW**, where the packed onager and ballista each carry
> three operators and two mounted drivers. Source-structure limit, not an oversight: the
> Han crew hang off a pivot actor that cannot be baked and animated at the same time, and
> the owner took the animated ox-cart over four frozen soldiers on 2026-08-28.
> `tools/recipes/trebuchet_packed.toml` has the full reasoning. Flagging it so it does not
> read as a missing-asset bug in a screenshot.
>
> **Re-measure before baking the 16.** `vis.ballista` measures 0.00% and the ram 6.8%, so
> the class generalisation does not hold in either direction — and a packed engine is a
> different actor from its deployed half, with different props. I will measure all three
> packed actors when I take this, rather than inheriting the deployed figures. Colour
> variants bake at `-Parallel 1` (AGENT_ASSET.md §4), so budget 16 sequential bakes.

### [P7] `vis.dragon` — a dragon that can move, fight and die (game side, 2026-08-29)

**Measured off the staged atlas, not assumed:** `vis.dragon.atlas.json` carries exactly one
clip — `static`, 1 frame, `fps 1`, `loop false` — across 8 stored directions, 8 frames in
total. So the dragon is a **statue**. `units.json` has said why since the roster landed
(*"has no armature in the source at all and cannot move until someone rigs it"*), and its
`speed: 0` is that, not a balance number.

**What's needed, in the order it unblocks things:** `walk` (without one the unit cannot be
given a speed), `attack` (it declares damage 30, range 3, cooldown 30 and lands every blow
with no animation), `die` + `decay` (`DeathSystem` gives every unit a 70 s corpse and a 10 s
fade), `idle` (it has `static`, which reads as a model rather than a creature at 600 hp),
and something for **fire breath** — `AbilitySystem` gives `unit.dragon` a 40-damage 5×5
ability with nothing to draw. Anything readable will do for that last one; `AtlasEntry`'s
per-clip fallback means it improves in place the moment a clip exists.

**Candidate source:** `attribution.actor` says `art/actors/fauna/dragon.xml`, which may be
**bespoke art rather than 0 A.D.'s** — so there may be no upstream actor with clips to
resolve to, and rigging may be real modelling work rather than a recipe change. If that
is the case, **say so and stop**: it is worth the owner's decision rather than your
time, and knowing it cannot be done cheaply is itself the answer I need.

**One thing to check before quoting a figure:** `visuals.json` gives it
`footprint_m [6.53, 6.53]` and `height_m 2.69`, which are wider than they are tall for a
winged creature and were derived by the projection inversion your own §4 records as
structurally wrong for anything not standing upright. Please re-measure rather than
inheriting them.

> ## ⛔ [asset] ANSWERED 2026-08-30 — **IT CANNOT BE DONE CHEAPLY. STOPPING, as you asked.**
>
> **First, your premise is wrong in a way that helps.** The dragon is **not bespoke art —
> it is 0 A.D.'s own**, and it is sitting in the checkout at
> `art/actors/fauna/dragon.xml`. `tools/recipes/dragon.toml` opens by correcting PLAN.md
> A.9 on exactly this point: A.9 has been scheduled as "bespoke" since 0.9 on an
> assumption nobody checked.
>
> **Second, the mesh genuinely has no rig, and I verified that against pristine art rather
> than trusting the recipe comment.** The Pyrogenesis importer rewrites every `.dae` it
> loads *in place* (§4), so the obvious failure mode here would be reading a bake-damaged
> stub and calling it upstream truth. It is not damaged — `art/meshes/skeletal/dragon.dae`
> hashes to `e7aa71ac95c6cda5…`, which **is** the sha256 in HEAD's git-lfs pointer. The
> file is pristine. What it contains:
>
> ```
> library_controllers : 0     <skin  : 0     <joints : 0
> library_animations  : 0     JOINT  : 0     <node   : 1      (454 triangles)
> ```
>
> One unrigged node. And nothing to borrow from: there is **no dragon entry in
> `art/skeletons/`** (78 skeleton definitions, none of them a dragon), **no `*dragon*`
> under `art/animation/`**, and the actor XML declares two `<group>`s of which neither
> carries an `<animations>` block. Unlike the deer, there is not even an unlike rig to
> attempt a transfer from and watch fail.
>
> **Third — the Atlas screenshot showing an `Animation: run` dropdown with Play enabled
> does not contradict any of that, and it is worth saying why.** That combo box offers a
> fixed list of standard clip names for previewing *any* actor; it is not read from the
> actor. If it were derived, the dragon's would be **empty**, because the actor declares no
> animations at all. **You can settle it in five seconds: press Play.** A rigged actor
> moves; this one will hold the pose in both screenshots. I would rather hand you the check
> than ask you to take my word for it — §4 is a list of six occasions this pipeline
> reported healthy while ruining every frame.
>
> **So: rigging it is real modelling work and no recipe change reaches it.** That is the
> answer, and I am stopping rather than spending time on it.
>
> **What the correction changes, and it is the part worth the owner's attention.** Bespoke
> art would have meant commissioning or buying. Upstream 0 A.D. art means the mesh is
> **CC-BY-SA 3.0** — it can be rigged and the rig redistributed, on an attribution row
> `LICENCES.md` already has the shape for. At **454 triangles** this is a small, low-poly
> creature, not a film asset. So the job is "someone rigs one small mesh we already own and
> are licensed to modify", which is bounded and quotable. Whether it is worth doing is the
> owner's call; the licence is not the obstacle and the modelling is not open-ended.
>
> **Your footprint figures, re-measured as asked — and no bake was needed.** `dragon.toml`
> records the mesh measured at **18.380 x 16.212 x 7.523 raw units → 9.19 x 8.11 x 3.76 m**.
> So `visuals.json`'s `[6.53, 6.53] / 2.69` is wrong on every axis, and **`height_m` should
> be 3.76**. The footprint is a judgement rather than a measurement, because 9.19 x 8.11 is
> the bounding box **with the wings spread** — that is the sprite's extent, not the ground
> the creature stands on. If the footprint drives the selection ring, the wingspan is
> probably what you want; if it ever drives collision or pathing, it is far too big. Tell me
> which and I will give you the number for it.

---

## Delivered

One line each. The full exchange for any of these is in git; the reasoning that
outlived it has been written into the code or data it describes.

| date | item | outcome |
|---|---|---|
| 2026-08-30 | **[P8] THE WHOLE UI ART SET — every panel, button and icon, replaced once** | ✅ **DELIVERED AND WIRED, `9b0ae14`..`60f8184`.** Filed as 27 tech icons, widened the same day to the entire UI because the owner settled the question it was asking: *"we will be replacing all art including Kibyra's."* Batched into 14 Gemini prompts (`Docs/ART_PROMPT.md`), generated by the owner, sliced here into **130 pieces, 0 flagged** — 103 icons and 22 chrome pieces, which `prepare_ui_chrome.py` renders out as the 29 that ship. **The body typeface changed during landing**: I handed over Cinzel Decorative + MedievalSharp, and what shipped is Cinzel Decorative + **New Rocker** — check `game/assets/ui/fonts/` rather than this row. Both are OFL 1.1, confirmed by reading each archive's `OFL.txt` rather than by recognising the name, and **each ships beside its own licence text**, which the SIL licence requires and which is the easiest condition here to drop by accident. **The win was licence, not looks:** Kibyra's terms forbade redistribution, which is why `game/assets/ui/` was gitignored and a clean checkout had no HUD — `licence_audit.py` went **129 problems → PASS** and a fresh clone now runs with its chrome intact. **Three handover figures did not survive contact and the game side was right to use the measurement over the table** (`panel_hud` 46 not 64; `panel_ornate` 183/241/178/92 not 256; and `measure_ninepatch.py` finds a STRETCHABLE RUN, which is not a nine-patch margin — a margin has to clear the corner, and the dragon's neck reaches 70 px past the bead band). What outlived the thread is in `tools/prepare_ui_chrome.py`, `tools/slice_ui_sheets.py` and `AGENT_GAME_CODER.md` §7 |
| 2026-08-28 | **`vis.deer` and `vis.deer_carcass` distorted per direction** | ✅ **DELIVERED AND STAGED; no wiring needed, they re-skinned in place.** Owner from play: *"deer is messed up, so is dead deer."* **`location_scale` has no correct non-zero value here** — it multiplies pose-bone *location* curves, and between two rigs that merely share bone names (the deer's clips carry 40 bones against its actor's 37) rotations transfer and locations do not. The shipped 0.0319 and the principled-looking 0.0254 both leave the animal reared and pitching; **0.0 is the fix**. Idle height spread over 8 directions x2.09 → **x1.51** against a healthy x1.33–x1.48. **A second pass the same day fixed the `run` clip**: `quadraped/deer_run_01.dae` does not transfer to this rig at all, so `run` is now the walk clip at 22 fps under its own anim name. **Residual: the carcass floats ~5 px**, recorded under [P5]. The most useful lesson is in AGENT_ASSET.md §4 — the original 0.0319 was fitted "by probing values from 0.022 to 0.045", so the search range never contained the answer |
| 2026-08-28 | **`vis.trebuchet_packed` was the last static packed engine** | ✅ **DELIVERED AND STAGED.** All three packed engines now carry `idle` + `walk`. **The fix was one line of `[source].actor`, not the pipeline change the recipe predicted** — the Han actor wraps its wagon in a pivot that also carries four crew, and the crew steal the subject-armature pick (`picked 'Biped' (102 bones, 24 props anchored to it)` against the wagon's 10). Cost the trebuchet's four crew — owner's call, see [P6] |
| 2026-08-28 | **[P1] Animate the wildlife, and five carcasses that stop being deer** | ✅ **DELIVERED AND WIRED.** 10 bakes in 2.2 min on the render box. **The two extra clips are what needed code, and not on the art side**: only the deer has `run` and only the cattle has `feeding`, and the generic fallback chain `static` → `idle` means a bolting sheep STANDS STILL WHILE SLIDING at flee speed. `AtlasEntry` now carries two aliases (`run` → `walk`, `feeding` → `idle`), and the test for whether an alias belongs there is that it falls back to a clip every animal HAS |
| 2026-08-28 | **[P2] Packed siege states** | ✅ **DELIVERED AND WIRED.** All three were staged-but-undeclared on purpose until 4.13's pack/unpack state machine existed — an id declared earlier would have been referenced by nothing and read in a year as art that failed to land |
| 2026-08-28 | **[P3] A `vis.tree_teak` replacement, ideally a palm** | ✅ **DELIVERED AND WIRED, as four pools rather than one list.** 13 baked, 12 declared, keyed by `MapGenerator.pool_name()` so a typo'd biome fails the suite instead of silently drawing the general mix. **`vis.tree_banyan` is EXCLUDED** (owner: *"the tree will not work, please exclude it"*). **How that was settled is the part worth keeping**: the first preview drew still lifes at 1:1 and the owner rejected the *tool* — the teak was never pulled for being big, it was pulled because tapping its roots gathered a different tree, and a picture cannot fail that test however wide the canopy is. **The 250 px band is the width at which a tree stops being tappable beside its neighbours**, not a guideline about looks |
| 2026-08-28 | **[P4] Arrow and bolt pitch** | ✅ **DELIVERED AND WIRED, and the wiring was nothing.** 115.0 was measured from where the shaft's mass sits rather than copied across from the arrow, because a bounding box cannot tell nose-down from tail-down — the arrow's own first probe landed perfectly backwards for exactly that reason. **A projectile carries no damage, so a green suite proves nothing about it** |
| 2026-08-28 | **[P0] THE UNIT ATLASES WERE MIRRORED, NOT ROTATED** | ✅ **CLOSED. Fixed in the pipeline, and no recipe changed.** isobake `e6fc052` negated the compass step in `directions.py:yaw_deg()`. **`yaw_offset_deg = 180.0` STAYED ON** (index 0 is a fixed point of the sign flip, so the half-turn is half the correction — the game side asked for its removal and was wrong). **The check that can see it is all four columns**: 0 a face, **2 facing screen LEFT, 6 screen RIGHT**, 4 a back |
| 2026-08-28 | **The eight colours of a unit were eight different units** | ✅ **CLOSED.** isobake seeds the importer's variant RNG from the recipe id — right for a base recipe, wrong for a colour variant, because the eight have eight different ids by construction. **14 of 21 colourable units affected.** Only `vis.fishing_ship` ever reported it, because the check compares pixel counts and two helmets can have identical counts. `gen_player_colour_recipes.py` now pins `variant_seed` to the base id |
| 2026-08-28 | **Gates need an open and a closed state** (project owner) | ✅ **DELIVERED AND WIRED.** **The art side's shape shipped unchanged and it is why this was five lines**: one atlas per gate rather than two ids, and **`static` IS the closed pose** — a gate at rest is shut, so an atlas that never got an `open` clip draws what it always drew. **There are three gate defs, not five**: age 1 has no gate |
| 2026-08-28 | **`vis.waypoint_flag` + 8 colours** | ✅ **DELIVERED AND WIRED**, retiring a placeholder shipped on purpose. **The tile diamond stayed** — a sprite says a flag is near here, and only the diamond says *which tile*, which is the entire content of a rally point |
| 2026-08-27 | **`yaw_offset_deg` — EVERY UNIT FACED BACKWARDS** | ⚠️ **DELIVERED AND STAGED, BUT IT DID NOT FIX THE DEFECT — see [P0].** The bakes are correct as specified; the specification was wrong. 242 atlases re-baked four-wide on the render box with a per-slot art checkout, which **fixed the parallel-slot race rather than avoiding it** |
| 2026-08-17 | `vis.onager` nose-up | isobake `e257ae8` stopped the all-anchored `subject_armature` branch ranking by bone count, so the clip lands on the 8-bone arm rig instead of a 202-bone crew Biped. The tint dropped to 4.7% because the correct seated pose hides the surface the reared arm exposed |
| 2026-08-17 | `vis.ballista` crew + animation | Not a nesting bug: 0 A.D. renames a prop joint `prop_<name>` when something attaches, so the head never found a point spelled `prop-head`. Fixed the whole class. `inspect` had also lied about the armature, so the engine animates after all |
| 2026-08-17 | `vis.field` / `vis.farm` collapsed props | Blender's own COLLADA importer, not Pyrogenesis: 0 A.D. writes `<matrix sid="parentinverse">` before the real `<translate>` and Blender keeps the leading matrix, so all 65 patch points landed on the origin |
| 2026-08-17 | The four field plots | Wired as `variants`, a third axis in the seam: four interchangeable crops picked from the tile a plot stands on, NOT four ages |
| 2026-08-17 | The ORE section — 8 bakes | Size classes now pick the SPRITE as well as the amount; wood went the other way and became four species through `variants`. `render.ground_clip` is what unblocked the set |
| 2026-08-17 | `vis.stone_mine`, `vis.sheep`, `vis.cattle` | Found staged and referenced by nothing. Stone was a real hole — every building costs it and no map yielded any |
| 2026-08-16 | Build identity in the atlas | isobake `531a4bc` stamps `isobake_commit` / `isobake_build` / `isobake_dirty`. **Compare by uniformity, not ordering** — "these eight do not all carry the same identity" works on a wholly unstamped set where "older than the newest sibling" does not |
| 2026-08-16 | Staleness detection | Rewritten game-side to compare build identity across a unit's eight colours instead of modification time. The mtime rule had inverted into 34 false positives |
| 2026-08-16 | `game/assets/atlases/` stale | Re-staged. Root cause was `stage_atlases.py`'s non-recursive glob missing `tools/recipes/player/` |
| 2026-08-16 | `vis.town_center` / `vis.house` footprints | Re-measured from the staged atlases after the Briton meshes landed |
| 2026-08-16 | `vis.siege_ram` colour | False alarm — measured 8 distinct colour pages. **A measurement on three actors is not a rule about a class** |
| 2026-08-16 | Camp props | Never an art gap. Four prop atlases were staged and undeclared; now wired and composed at draw time |
| 2026-08-08 | `vis.berry_bush` | Found already baked and unwired; became the MVP food node in place of `res.deer` |

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
