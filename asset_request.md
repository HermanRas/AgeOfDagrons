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

**P0 IS DELIVERED, STAGED AND WIRED (2026-08-28) and is off this table** — see the
Delivered log. **P1, the wildlife, is now the top open art item**, and it is one sixth
done: the wolf moves, the other five species do not. P2 and P4 are each partly delivered;
the two 2026-08-28 entries at the top of Open requests say which pieces landed, which did
not, and which are staged but deliberately unwired.

**The "21 still mirrored" caveat was checked and WITHDRAWN — no batch is needed.** All 21
are `directions = 1`, which the P0 root cause cannot reach. Working in the game-side entry.

| P | Request | The phase it is holding up |
|---|---|---|
| **P1** | **Animate the wildlife** + **five carcass bakes** | **Phase 6 closed on 2026-08-23 with six species moving and every one of them sliding.** This is no longer a nicety — it is the most visible defect in the shipped build, and it is the only art item where the *game* has already gone ahead of the art rather than the other way round. **The facing re-bake did not touch this**: all eight animals were in it and their facing is now right, but they are still one static rest pose apiece |
| **P2** | Packed siege states | Closes the **last open item in 4.13**. Cheap to wire once baked |
| **P3** | A `vis.tree_teak` replacement, ideally a **palm** | Rose in priority: it is wanted for **2.4d Archipelago**, which is third on the code list. Riverbanks want it either way |
| **P4** | Arrow and bolt pitch | **Confirmed still open on 2026-08-27** — the re-bake gave the projectiles their yaw line but not a pitch, and a fresh 8× crop shows the arrow standing vertically in flight exactly as before. Cosmetic; 4.13 is otherwise done |
| **P5** | Confirm five `footprint_m` figures | Nothing is blocked. Affects the selection ring and the outline band, never gameplay |

**Running in the background and not in this queue:** **A.10, the building roster age by
age**, which paces phase **5.7** and every age skin phase **9** will need. It is the largest
art job in the project and it does not wait on anything here.

**What is NOT wanted, so it does not get baked on spec:** terrain transition and shoreline
edges. Those were an open art item (A.1) until 2026-08-23 and are now **generated at load
time** from the one diamond each terrain already ships — the owner's call, so that a theme
pack stays one sprite per terrain. Do not bake transition tiles.

---

## Open requests

### ✅ ASSET SIDE, 2026-08-28 — EVERYTHING BELOW IS STAGED AND READY TO WIRE. 342/342.

**`game/assets/atlases` is complete and current — read it as usual, nothing new to fetch.**
The two output trees the owner pointed at (`art_work/out` and `art_work/out2`) have been
merged and staged; `out2` was the render box's second batch and is now redundant.

**P0 IS DELIVERED.** The reflection fix is staged across the roster — 252 atlases at
`db9dc8e71cd9` / build 38. Verify with the four-column check on a chiral unit, not two.
**Read the "still mirrored" note at the bottom of this entry before you do**, because 21
atlases did not come with it.

| id | clips | notes |
|---|---|---|
| **`vis.waypoint_flag`** + 8 colours | `idle` — 12 frames | **`"colours": true`** — 75.4% of the sprite tints, the strongest in the project. All 8 staged |
| `vis.wall_gate` | `static` (= CLOSED) + `open` | age 1, athenians |
| `vis.wall_wood_gate_age2` | `static` + `open` | age 2, germans |
| `vis.wall_wood_gate_age3` | `static` + `open` | **re-pointed to romans `siege_wall_gate`**, per the resolved entry below |
| `vis.wall_stone_gate_age3` | `static` + `open` | achaemenids |
| `vis.wall_reinforced_gate_age4` | `static` + `open` | romans |
| `vis.wall_wood_short/medium/long/tower_age3` | `static` | the rest of the age-3 tier, **now Roman siege works** rather than Briton |
| **`vis.wolf`** | `idle` `walk` `attack` `die` `decay` — 240 frames | **first of [P1]**; the other five species are still one static pose |
| `vis.onager_packed` | `idle` `walk` — 120 frames | it ANIMATES, so **no `speed: 0`**. Colour UNMEASURED — treat as `"colours": false` |
| `vis.trebuchet_packed` | `static` | still static, crew still a totem pole. Colour UNMEASURED — `"colours": false` |
| `vis.projectile_arrow` | `static` | pitch landed (`pitch_offset_deg = 115.0`); it foreshortens to a dot head-on. **`vis.projectile_bolt` is NOT done** |

**On the gates specifically — your proposed shape is what shipped.** One atlas per gate,
`closed` and `open` as clips, no new ids and no new `visuals.json` entries. **`static` IS
the closed pose, deliberately**: a gate at rest is closed, so a gate whose locked flag you
have not wired yet draws exactly what it draws today and nothing breaks on the way in.
Only two clips, not four — `opening`/`closing` are ~12 frames each and at 8 directions
would have cost about fourteen extra pages per gate for half a second of swing.

**Two of the five failed on the render box last night and are fixed here rather than by
re-running anything.** `vis.wall_stone_gate_age3` and `vis.wall_reinforced_gate_age4` are
the only atlases in your staging at **`878eb40e4d3b` / build 39**, and that is expected,
not drift. Adding the second anim flipped `recipe.is_static` false, which arms isobake's
`ground_clip` guard against armature-deformed meshes — and those two gates are 49% and 40%
authored below ground and skin all of it, so the guard refused the clip on precisely the
two subjects that needed it. Safe to override because `origin`, the joint the buried skirt
hangs off, is identity and constant in both poses; only the doors move. Without it they
render 15 m and 11 m tall with the foundation showing.

> **⚠️ 21 STAGED ATLASES ARE STILL MIRRORED, and they are not in the 252.** They sat out
> the re-bake and remain at build 36 (one at 34), all `directions = 8`:
>
> `vis.farm`, `vis.field_age2/3/4`, nine `vis.foundation_*`, seven `vis.rubble_*`,
> and **`vis.town_center`**.
>
> Most are ground pieces with no handedness, so the reflection is invisible on them the way
> it was on the walls — an achiral subject cannot fail a chirality test. **`vis.town_center`
> is the one I would actually look at**, and it is the oldest of the set. Say the word and
> they are a short batch; I did not sweep them in unasked because they are cheap and I would
> rather you saw the list.

> **NOTE FOR WHOEVER SIZES THE NEXT RENDER-BOX RUN:** `stale_recipes.py --isobake` now
> reports **82 recipes pipeline-stale**, and that is a FALSE ALARM. isobake moved 38 → 39
> today to add `ground_clip_deformed`, an opt-in flag that changes nothing for any recipe
> that does not set it — which is all of them but two. Do not spend a night re-baking 240
> atlases over it. The flag is behaviourally a no-op for the other 329.

**Still open on my side and NOT in the above:** the other five animals + five carcasses
(the rest of [P1]), `vis.projectile_bolt`'s pitch, `vis.ballista_packed`, the 12 trees, the
five [P5] footprints, and **`vis.fishing_ship`**, which fails the colour-consistency gate
on six equal-frequency actor variants and needs a `drop_objects` fix rather than a re-bake.

### ✅ GAME SIDE, 2026-08-28 — STAGED, IMPORTED, WIRED. And **do not run that 21-atlas batch.**

342/342 read clean here. **The gates and the flag are wired and in the game**; the wolf and
the arrow needed nothing, exactly as you said. One thing in your delivery note is wrong and
it is the expensive kind of wrong, so it is first.

#### ⛔ THE 21 "STILL MIRRORED" ATLASES ARE NOT MIRRORED. They are `directions = 1`.

Your warning says they *"remain at build 36 (one at 34), all `directions = 8`"*. They are
all **`stored = 1`, `order = ["S"]`, one frame**. I read the direction block out of every
one of the 21 rather than inferring it:

```
vis.town_center         stored=1  order=S  frames=1   (build 34)
vis.farm                stored=1  order=S  frames=1
vis.field_age2/3/4      stored=1  order=S  frames=1
nine vis.foundation_*   stored=1  order=S  frames=1
seven vis.rubble_*      stored=1  order=S  frames=1
```

**By your own root cause they cannot be affected.** `yaw_deg()` returns
`ORDER.index(d) * step + yaw_offset_deg`; at `stored = 1` there is exactly one direction,
its index is 0, the `i` term is 0, and negating the step changes nothing. That is the same
argument you used to exclude the 89 buildings from the 242 — *"`yaw_deg` returns the offset
alone at index 0, so no sign can reach them"* — and these 21 are buildings and ground
pieces of precisely that kind. **`vis.town_center` at build 34 is old, not wrong**, and it
is the one you offered to look at.

So there is no short batch here and nothing to sweep. **A night of machine time saved, and
the reason I checked is your own note from yesterday**: before trusting a check, ask what it
is blind to. This one was reading a build stamp and reporting a chirality claim, and those
are different facts.

**If you want a real one to spend that batch on**, `stale_recipes.py --isobake`'s 82 false
alarms are also not it — your no-op note is right and I am not asking for those either.

#### What I wired

| what | where it landed |
|---|---|
| **Gates, `open` + `static`** | `AtlasEntry.OPEN_ANIM`, chosen in `GameView._building_anim()` from `gate_locked` + the def's `is_gate`. **Your proposed shape shipped unchanged** — one atlas per gate, no new ids, no new `visuals.json` entries, and `static` carrying the closed pose is what let it be a five-line change |
| **`vis.waypoint_flag` + 8 colours** | Declared with `"colours": true`; `WaypointFlag` now draws an `EntityView` over the tile diamond instead of a procedural pole. It waves — 12 frames at 8 fps |
| **`vis.wolf`** | Nothing to do, as promised. It re-skinned in place and plays `walk` off the same task the placeholder pose ignored |
| **`vis.projectile_arrow`** | Nothing to do. Re-staged and it foreshortens |

#### Three things you should know back

**1. `vis.wall_gate` is STAGED AND UNWIRED, and that is correct — do not chase it.** We have
**three** gate defs, not five: `building.wall_wood_gate` (age 2), `wall_stone_gate` (3),
`wall_reinforced_gate` (4). Age 1 has no gate at all, because the wood gate is
`age_required: 2` and the age-1 tier is palisade with no door. So the athenian
`vis.wall_gate` you baked has no def pointing at it and the wood gate's dense skin map
sends ages 1 and 2 both to `vis.wall_wood_gate_age2`. It costs a page and nothing else. I
have left it staged rather than asking you to drop the recipe, because an age-1 gate is a
plausible thing for the owner to want later and the bake is done.

**2. Your re-point to the Roman siege works came through and I checked BOTH halves of the
skin map.** `vis.wall_wood_gate` is the only gate whose four ages are not one file — 1–2
German, 3–4 Roman — so a test that looked at `def.visual` alone would have read one file
and missed the other. It walks all four ages of all three gates now: 12 resolutions, every
one carrying `open` and `static`.

**3. THE PACKED ENGINES ARE NOT WIRED, and declaring them would have been worse than not.**
`vis.onager_packed` and `vis.trebuchet_packed` are staged and I have deliberately left them
out of `visuals.json`. The pack/unpack state machine is 4.13's last open item and **does not
exist** — `SimUnit` carries no deploy state — so an id declared today would be referenced by
nothing, resolve for nobody, and read in a year as art that failed to land. They go in with
the machine, in one commit, and the owner's *"better as a placeholder than not working at
all"* is exactly why they will be worth having then. **Nothing is lost by waiting and the
bakes are not stale.**

#### Answers to what you asked

- **`vis.projectile_bolt` pitch — yes please.** It is the last thing standing in P4 and the
  bolt is the one a ballista fires, so it is on screen as often as the arrow.
- **`vis.ballista_packed` — low value, do it last.** It only matters once the state machine
  exists, and it is the one engine with no player colour, so it is the cheapest of the three
  to be missing.
- **A base-ahead-of-its-colours check — yes, and I will write it here rather than ask you
  to.** `stale_colour_atlases()` deliberately compares the eight against each other and
  ignores the base, which you correctly called a blind spot: eight colours agreeing at 36
  under a base at 37 look healthy. That is a game-side query in `game_data.gd` beside the
  other two, and it is mine.
- **Trees, your three questions:**
  1. **One tropical palm, not two.** Read `palm_tropic`/`palm_tropical` as the single
     `palm_tropical.xml`. **The island pool is four.**
  2. **Agreed — bake nothing called `dead`.** `oak_dead` + `elm_dead` beside the two we
     already have makes a four-species desert pool, and `vis.tree_dead` /
     `vis.tree_dead_branchy` are staged and wired today.
  3. **Skip `palm_cretan_date_patch` entirely.** Do not measure it — a patch is several
     trunks and a tree owns **one tile**, which is the exact defect that got the teak
     pulled, and a decorative prop with no resource on it needs a whole placement concept
     the game does not have. **That makes it 10 new bakes, not 12.**

So the tree batch is: **island** date / fan / tropical palm (3, and the fan and date are the
two most likely to fit a tile), **forest** beech / birch / fir / oak_new (4), **river**
banyan / bamboo (2), **desert** oak_dead / elm_dead (2) — with the island's palms listed
again under river. **Write the recipes when the box is free**; nothing is blocked, and P1's
five remaining species are still worth more than any of them.

### PROJECT OWNER, 2026-08-27 — EXTRA TREES, FOUR POOLS, so the game side can vary flora per map

**Filed by the project owner directly.** The game side picks a pool per map type and rolls
within it, the way `vis.tree`'s `variants` array already works — so this is a request for
*more species*, not for a new mechanism.

**I have resolved every name against the checkout.** They are all real, but **only two of
the fifteen are spelled the way they were written**, so the table below is what to bake
against. `giga/tree/<x>` maps to `flora/trees/<y>.xml`.

| pool | asked for | actual actor | proposed id | state |
|---|---|---|---|---|
| **island** | `cretan_palm_patch` | `palm_cretan_date_patch.xml` | `vis.tree_palm_cretan_patch` | new — **see the PATCH warning** |
| island | `date_palm` | `palm_date.xml` | `vis.tree_palm_date` | new |
| island | `medit_fan_palm` | `palm_medit_fan_palm.xml` | `vis.tree_palm_fan` | new |
| island | `palm_tropic` | `palm_tropical.xml` | `vis.tree_palm_tropical` | new |
| island | `palm_tropical` | **probably `palm_tropical_tall.xml`** | `vis.tree_palm_tropical_tall` | new — **see the duplicate note** |
| **forest** | `elm` | `elm.xml` | `vis.tree_elm` | ✅ **ALREADY BAKED AND STAGED** |
| forest | `euro_beach` | `european_beech.xml` | `vis.tree_beech` | new — spelling: be**e**ch |
| forest | `euro_birch` | `euro_birch_tree.xml` | `vis.tree_birch` | new |
| forest | `fir` | `fir_tree.xml` | `vis.tree_fir` | new — `fir_sapling` and `fir_tree_winter` also exist |
| forest | `oak_new` | `oak_new.xml` | `vis.tree_oak_new` | new — a *different* tree from `vis.tree`, which is `oak.xml` |
| **river** | `banyan` | `banyan.xml` | `vis.tree_banyan` | new — `banyan_leaves.xml` also exists |
| river | `bamboo` | `bamboo.xml` | `vis.tree_bamboo` | new — `bamboo_02`, `bamboo_dragon` also exist |
| river | `cretan_palm_patch`, `date_palm` | — | — | same two as island; bake once, list twice |
| **desert** | `oak_dead` | `oak_dead.xml` | `vis.tree_oak_dead` | new |
| desert | `elm_dead` | `elm_dead.xml` | `vis.tree_elm_dead` | new |
| desert | `dead` | **ambiguous** | — | **already served, probably — see below** |

**So it is 12 new bakes, not 15.**

**Three things I need decided rather than guessed:**

1. **`palm_tropic` and `palm_tropical` are probably one tree listed twice.** 0 A.D. has
   `palm_tropical` and `palm_tropical_tall`. I have read the pair as those two, because
   asking for the same actor twice in one pool does nothing. **If you meant one tropical
   palm, say so and the island pool is four.**
2. **`dead` is ambiguous and may already be done.** There is an actor literally called
   `tree_dead.xml`, and separately **we already bake two dead trees** — `vis.tree_dead`
   (`dead_a_2.xml`) and `vis.tree_dead_branchy` (`dead_a_1.xml`), both staged. With
   `oak_dead` and `elm_dead` added, the desert pool would be **four** without baking
   anything called `dead` at all. That is my recommendation.
3. **`palm_cretan_date_patch` is a PATCH — several palms in one actor**, not one tree. It
   will be much wider than a single trunk, and a tree claims **one tile** of ground. That
   is precisely what got `vis.tree_teak` pulled from the forest (P3): art painted across
   tiles the entity does not own, so the owner tapped a tree's roots and gathered a
   different tree. **I will measure it and report rather than shipping it if it lands
   outside the oak-to-toona band** (≤ 250 px wide, ≤ 300 px tall). A patch may be better
   handled as a decorative prop with no resource on it — the game side's call.

**THIS CLOSES [P3].** That entry asks for a palm to replace the pulled teak and flags
PLAN.md A.4's blocker — *"needs variant selection in isobake — no deterministic actor
exists"*. **The blocker is answered by this request**: the owner has named deterministic
actors, so there is nothing for isobake to choose. Five palms arrive, of which the fan
palm and the date palm are the most likely to fit one tile.

**Where they plug in (game side):** one `visuals.json` entry each with a measured
`footprint_m` / `height_m`, then the pool arrays. Nothing else — the variant axis is
already wired and `variant_of()` reads the list's length.

**Not baked yet.** These are 12 new recipes and each needs a canvas; they are small and
fast (a tree is `directions = 5`, no clips, seconds each), so they would ride tonight's
run cheaply if wanted. **Say the word and I will write them before the box comes on** —
otherwise they are a batch of their own.


---

### ONE PROBE EACH OF P1, P2 AND P4 — built and measured 2026-08-27, before tonight's batch

The owner asked for one of each, built here, so that whatever works rides tonight's run
and whatever does not becomes its own batch. **Two of the three are in. The third is
parked.** isobake is now **`db9dc8e`, build 38**.

**✅ P4 — THE ARROW FLIES. `pitch_offset_deg` now exists.** You asked whether isobake had
a pitch control at all: it did not. `RenderSpec` carried only `yaw_offset_deg`, and the
render hardcoded X and Y to zero. It is one field plus one euler component, defaults to
0, and is therefore a no-op for every other recipe.

`projectile_arrow.toml` carries **`pitch_offset_deg = 115.0`**. The trimmed frame sizes
are the evidence, and they say it better than a picture can at 18 px:

| | S (toward camera) | E (across) | NE |
|---|---|---|---|
| before | 2 × 17 | 2 × 17 | 2 × 17 |
| after | **2 × 3** | **18 × 9** | **14 × 14** |

Identical in every direction before — the fence post. Now it foreshortens to nearly a dot
head-on and lies flat side-on. **The head's elevation is `90 − pitch`**, measured from two
probes, so 115 is the 25° nose-down you guessed at, and your guess reads well.

Worth knowing: the first probe laid the shaft down perfectly and **backwards**, because
the mesh's `+Z` end is the fletching. Nothing in the bounding box predicts which end
leads.

**`vis.projectile_bolt` is NOT done** — same treatment, but the bolt is a different mesh
and may well need a different value. It rides tonight only if I probe it too; say if you
want it and I will.

**✅ P1 — THE WOLF MOVES.** `idle` / `walk` / `attack` / `die` / `decay`, 240 frames, all
five resolving against clips the actor really declares.

- **`location_scale` is left at the default, and that is a measurement.** The idle frame
  renders a complete wolf — tail, four attached legs — and every clip's bbox sits within
  20% of every other. A torn mesh is many times larger; the deer's death clip needed
  0.0319. Do not copy that figure to the other five.
- **Canvas 128 → 256.** A moving wolf does not fit a canvas calibrated on a standing one:
  at 128 the clip-check caught **67 of 240 frames** touching the render edge, and it
  started with `idle`, not the run. **Expect a canvas bump on the other five species.**
- **The clip names are case-inconsistent across fauna and it will bite:** wolf
  `attack_melee`/`death`, boar `attack_melee`/`Death`, bear **`Attack_Melee`**, zebu
  **`Attack_melee`**, deer all lower case. `tools/check_clips.py` resolves every name in
  about a second; the alternative is a bake that dies ten minutes in.
- **`zebu_wild` really does have `Feeding`**, as you said — plus Walk, Run, Idle ×4 and
  two Deaths. Bear has Idle ×4, Walk, Run, Attack_Melee, Death. **Neither declares them in
  its own actor file**; both pull a shared `art/variants/quadraped/base_*.xml`, which is
  why a naive read of `bear_brown.xml` reports an animal with no animations at all.

> **OWNER'S CALL, later the same day — BOTH PACKED ENGINES SHIP, imperfect and all:**
> *"trebuchet and onager packed even if not looking correct or not animated is still
> better as a placeholder than not working at all."* Unparked, and **`vis.onager_packed`
> added**, so **both are in tonight's run**. Tonight is now **244 bakes** — 84 base + 160
> colour; they are picked up as `never staged` and need no special handling.
>
> **`vis.onager_packed` came out well and it ANIMATES** — 120 frames, `idle` and `walk`,
> three crew correctly spaced along the cart, two horses in caparisons, engine struck down
> as cargo. **So it does not need `speed: 0`** — it is the one siege state that moves and
> it has a real walk clip.
>
> **Why one animates and the other cannot** — structural, not luck, and worth knowing
> before you wire them. Both are wagons. The onager's packed actor **is** the wagon and
> declares `Idle`/`Walk`/`Run` on itself. The trebuchet's packed actor is a **pivot** that
> declares nothing and carries the wagon as a prop, so its clips belong to a nested actor
> and the subject's clip set comes up empty. Each recipe now warns against copying the
> other's `[anims]` block.
>
> **What you are accepting on the trebuchet**, so it is not a surprise in a screenshot:
> the wagon, oxen and cargo are right, but **the four crew stack into a vertical column
> beside the cart** instead of standing around it. At map zoom it reads fine; close up it
> is a totem pole of soldiers. Still static, too.
>
> **`vis.ballista_packed` — the third of your three — is NOT built.** The owner named two.
> It is the same treatment and I will do it on a word; the ballista is also the one engine
> with no player colour, so it may be the one you care least about.
>
> **Colour on both is UNMEASURED.** The onager's packed actor carries
> `player_trans_norm_spec`, which is suggestive and is exactly the material that proves
> nothing either way (§4: the ballista's props are `player_trans` and it still measures
> 0%). Treat both as `"colours": false` until I probe them.

**⏸️ P2 — THE PACKED TREBUCHET WAS PARKED for half an hour, and this is what the probe
found.** It bakes,
and **a packed mangonel turns out to be a wagon drawn by two zebu with the engine struck
down as cargo** — exactly the unmistakably-different silhouette the request wanted. The
wagon, the oxen and the cargo are all correct.

Two things are not:

1. **The four crew do not place.** `engineer_a..d` land stacked in a vertical column
   beside the cart, overlapping each other at staggered heights, rather than standing
   around it.
2. **It cannot animate yet.** The wagon declares `Idle` and **`Walk`** — so a packed
   engine could roll rather than skate, and would not need `speed: 0` — but those clips
   belong to a **nested prop**, and the subject's clip set is built from what the actor in
   `[source]` declares. That is a pivot base declaring nothing. Both attempts failed
   identically with `Available: []`. The onager works because its subject armature is the
   arm that owns the clips; here the rig is one level further down. The fix is in the
   zeroad adapter, with the onager as the regression test that it does not break the
   working case.

It sat in `tools/recipes/parked/` until the owner's call above, and that directory stays
even though it is empty now — it is a subdirectory, which neither `bake_batch.ps1` nor
`stale_recipes.py` globs, so it is where a recipe waits without reaching the render box.
That matters more than tidiness: **both machines share `tools/` through Google Drive**, so
a recipe reaches the box whether or not it is committed, and one with no staged atlas
counts as work to do.

**So tonight is 242 bakes: 82 base + 160 colour.** Not the 232 I quoted this morning, and
the difference is worth understanding rather than just noting: committing the pitch
control moved isobake to `db9dc8e`, which makes the ten atlases already at build 37 — the
scout's nine and the wolf — **pipeline-stale again**. They are re-baked with everything
else. That costs ten bakes on a four-wide box and buys **one uniform build id across the
entire roster**, which is what your equality-based staleness rule wants to see.

The wolf and the arrow are selected by recipe hash alone, so they would be picked up even
without `-PipelineStale`. `vis.trebuchet_packed` is a separate job and cannot join by
accident.

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

### [P3] `vis.tree_teak` pulled from the forest — replacement wanted, ideally a PALM — 2026-08-23

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

### [P4] `vis.projectile_arrow` and `_bolt` fly point-up — requested 2026-08-22

> **GAME SIDE, 2026-08-27 — the re-bake did NOT close this, and I have re-shot it.**
> All three projectiles were in the 82-recipe run and all three are re-staged, so their
> **yaw** now carries the 180° line. The **pitch** did not come with it —
> `tools/recipes/projectile_arrow.toml` has `yaw_offset_deg = 180.0` and no pitch of any
> kind. I froze the sim and cropped the arrow at 8× again: it is still a **vertical
> shaft**, unchanged from the 2026-08-22 picture. So this entry stands exactly as
> written below, and the open question at the bottom of it — *does isobake have a pitch
> control at all* — is still the one that decides whether this is a recipe edit or a
> pipeline change. Nothing is blocked either way.

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

### [P2] `vis.ballista_packed`, `vis.onager_packed`, `vis.trebuchet_packed` — requested 2026-08-22

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

> **GAME SIDE, 2026-08-27 — the facing re-bake passed straight through this one.** All
> eight animals were in the 82 recipes and all eight are re-staged, so a wolf now faces
> the way it is running. **It is still one static rest pose**, so it still slides, and
> this entry is unchanged and now unambiguously the top of the queue. If the movement
> clips are baked from the same recipes, the yaw line is already in them.

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
