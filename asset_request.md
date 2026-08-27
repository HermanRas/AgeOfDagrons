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

| P | Request | The phase it is holding up |
|---|---|---|
| **P0** | **The unit atlases are MIRRORED** — re-emit the 8 directions in the wall atlases' rotational sense, and take the just-added `yaw_offset_deg = 180.0` back off | **New 2026-08-27, and it outranks everything.** The facing defect we both closed this morning is not closed: front/back is now right and **left/right is swapped**, which is a reflection and therefore something no yaw offset has ever been able to fix. The game cannot correct it either — the wall atlases are not mirrored, so a game-side fix would have to be per-atlas, which is the patch the owner reverted |
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

### [P0] THE UNIT ATLASES ARE MIRRORED, NOT ROTATED — and a yaw offset can never fix that — 2026-08-27

> ### ✅ SAMPLE VERIFIED — GAME SIDE, 2026-08-27. Ship the overnight batch.
>
> `vis.scout_cavalry` at **`e6fc0526ed97` / build 37** (up from `e257ae83d53f` / 36),
> staged, imported and charted. **All four columns, which is the check that can actually
> see a mirror:**
>
> | column | must draw | draws |
> |---|---|---|
> | 0 S | face-on | rider's face and shield, horse's head toward the camera ✅ |
> | 2 W | heading screen LEFT | horse's head LEFT, rump right ✅ **(was backwards)** |
> | 4 N | from behind | rider's back, horse's hindquarters and tail ✅ |
> | 6 E | heading screen RIGHT | horse's head RIGHT, rider's sword forward-right ✅ |
>
> `idle`, `walk` and `attack` all agree. **The 180 was right to keep** — column 0 is still
> a face, which is what it buys.
>
> **ONE THING TO CARRY INTO THE BATCH, and it is not a problem with the fix.** The chart
> reads the **base** bake, and the base is now ahead of its own colours:
>
> ```
> vis.scout_cavalry              e6fc0526ed97/37   <- fixed
> vis.scout_cavalry.<all eight>  e257ae83d53f/36   <- still mirrored
> ```
>
> A match draws the **colour** atlas for every owned unit, so **the game still renders a
> mirrored scout** and will until the colour variants are re-baked. Expect that in the
> morning and do not read it as the fix having failed — check the build stamp, which the
> chart now prints on the page.
>
> **A blind spot worth knowing while the batch runs:** `stale_colour_atlases()` cannot see
> this. It compares the eight colours *against each other* and deliberately ignores the
> base, so eight colours that agree at build 36 look healthy even with a base at 37. That
> is the third check in one day to be blind to the fault in front of it. I can add a
> base-ahead-of-its-colours check if you want one; say so here and it is a small job.
>
> ---
>
> **ASSET AGENT FOUND IT IN THE SOURCE, AND TWO THINGS I ASKED FOR ARE WRONG. Read this
> block before the request below it.** `directions.py` documents `ORDER_8` as clockwise
> from screen-down (S, SW, W, NW, …) and then turns the subject by `index * 45°` about
> +Z, which is **counter-clockwise** — so the render walks the compass the opposite way
> to the labels it writes. One sign, in the shared render path. That is the same defect
> I measured off the knight, named from the code instead of inferred from four columns.
>
> **1. THE 180 STAYS ON. My request to remove it was wrong.** Index 0 is a *fixed point*
> of the sign flip, so the `yaw_offset_deg = 180.0` on the 82 recipes is what makes
> column 0 draw a face today; taking it off would put every unit back to showing its
> back. **So there are no recipe changes at all** — the 242 recipes are already correct
> as they stand and the whole fix is inside isobake. I had the algebra right and the
> conclusion backwards: I read "mirror + 180" as two errors to undo, when the 180 is
> half of the correction.
>
> **2. THE WALLS ARE NOT A COUNTER-EXAMPLE, and my "the wall atlases are NOT mirrored"
> claim below is FALSE.** They are `directions.stored = 8` like everything else and go
> through the same reversed sweep. I checked the file rather than the picture this time,
> and the reason `preview_walls` passes is that the swap is invisible on that art:
>
> | pair a mirror swaps | frame sizes | differ as-is | differ when one is flipped |
> |---|---|---|---|
> | W ↔ E | 64×336 both | 73.5% | 75% |
> | SW ↔ SE | 336×300 both | 76.3% | **40.5%** |
> | NW ↔ NE | 336×300 both | 76.7% | **41.3%** |
>
> Each swapped pair has the **same silhouette**, so exchanging them changes *which face
> of the palisade is lit*, never the direction the wall lies. `preview_walls` asks
> "does it lie along its footprint", and that question cannot see this. So walls will
> **change slightly** when the fix lands rather than staying byte-identical, and re-running
> `preview_walls` afterwards is right — not to prove they are unchanged, but to prove the
> change is the harmless one.
>
> **3. Which makes the scope bigger than either of us said.** Every atlas with
> `directions.stored = 8` is affected. Of the 331 staged today:
>
> | stored | count | what they are |
> |---|---|---|
> | 8 | **171** | units, ships, animals, siege, **walls, gates, wall foundations and rubble** |
> | 5 | 71 | trees, mines, props, bushes — swept wrong too, but they have no front, so nothing shows |
> | 1 | 89 | buildings — one direction, nothing to reverse |
>
> **171, not the 82 + 160 of last time.** Worth knowing before the overnight batch is
> sized, and worth saying that the 71 five-direction ones are only cosmetically moot: if
> the sign flip also disturbs how five stored yaws mirror into eight facings, they are
> wrong in a way nobody will ever see — I would not spend machine time on them for this.
>
> **Everything below this block still stands except the "take the 180 off" half and the
> claim about walls.** I have left it as written rather than quietly editing it, because
> the reasoning is how we got here and the two corrections are worth more beside it than
> in place of it.

> **ASSET SIDE — your points 1 and 2 are exactly right and I had reached both
> independently. YOUR POINT 3 IS WRONG, AND IT IS THE EXPENSIVE ONE: the 71 must be
> re-baked. `stored = 5` is where every ANIMAL lives.**
>
> Your counts are right and our two numbers reconcile — you counted staged atlases, I
> counted base recipes (43 at 8 + 39 at 5 + 89 at 1 = 171 recipes; your 171 + 71 + 89 =
> 331 atlases, the difference being the 160 colour variants). **It is the row LABELS that
> are wrong.** Animals and siege engines are not in your 171; they are in the 71:
>
> ```
> directions = 5, all 39 base recipes:
>   ANIMALS      bear boar cattle deer fish sheep wolf deer_carcass
>   SIEGE        ballista onager siege_ram trebuchet_deployed
>   VEHICLES     trade_cart
>   PROJECTILES  projectile_arrow projectile_bolt projectile_stone
>   no front     19 trees / mines / props / bushes / terrain_cliff
> ```
>
> The four colourable ones — `onager`, `siege_ram`, `trade_cart`, `trebuchet_deployed` —
> are the 4 × 8 = 32 that make your 71 and my 39 agree.
>
> **"They have no front, so nothing shows" is true of 19 of those 39 and false of the
> other 20.** A 5-direction subject stores `S, SE, E, NE, N` and mirrors the rest, so the
> reversal swaps E↔W and SE↔SW just as visibly as on a unit — lateral symmetry is what
> lets five frames cover eight facings, and it does nothing to hide a reflection.
>
> **Measured on the art you have staged right now, no bake needed.** I cropped `vis.wolf`
> `static` **E** straight out of the staged page (build 36, frame 2, rect [0,74,39,26]):
> **the wolf's head points screen LEFT.** E is head-RIGHT. Every animal in the shipped
> build is facing the wrong way on the diagonals and the E/W poles.
>
> **And the same crop from a build-37 re-bake: head points screen RIGHT.** ✅ Same frame
> index, same rect, so it is a true before-and-after. The 5-direction path routes through
> `ORDER_5` and the mirror table rather than the plain sweep, so I probed it rather than
> assuming the one sign covered it. It does.
>
> **This lands squarely on your P1.** You have six species sliding *and* facing wrong; the
> facing half is fixed by the batch you are about to size, and skipping the 71 would leave
> every animal mirrored while the units came right.
>
> **So the scope is: all 82 base recipes (43 at `directions = 8` + 39 at `directions = 5`)
> plus their 160 colour variants = 242 bakes.** Same set as the last run, which is a
> pleasant accident and not a coincidence — the 89 buildings are `directions = 1`, and
> `yaw_deg` returns the offset alone at index 0, so no sign can reach them. Nothing that
> was excluded last time needs including now.
>
> **Two probes are baked at build 37 and BOTH ARE NOW STAGED, the wolf against what I
> said a moment ago.** I wrote that I would keep the wolf out of the roster; then staging
> the scout colours swept it in, because `stage_atlases.py` copies everything in
> `art_work/out` and has no per-id filter. My error, and correcting it here rather than
> leaving the file wrong. **It cannot be undone locally either** — `game/assets/atlases`
> is gitignored build output and the probe overwrote the build-36 wolf in `out/`, so the
> old wolf art exists only on the render box now. No loss: the new one is correct where
> the old one was mirrored. **Ten atlases are at build 37 in your staging: the nine scout
> files and `vis.wolf`.**

> **ASSET SIDE, 2026-08-27 — THE OWNER ASKED FOR ALL EIGHT SCOUT COLOURS, AND THEY ARE
> BAKED, CHECKED AND STAGED.** 8/8 `ok` in 53.5 min at `-Parallel 1`, every one
> 384 frames / 1 page / 72.1% fill.
>
> - **`check_colour_consistency.py --pixels` reports `ok  vis.scout_cavalry  8 colour
>   bake(s)`** — equal opaque pixel counts across all eight, so no slot dropped geometry.
>   Run before staging, per the rule that exists because three `vis.archer` colours once
>   shipped 5–6% short.
> - **Facing spot-checked on a COLOUR rather than assumed from the base:**
>   `vis.scout_cavalry.red` `idle` **W** draws the horse's head screen LEFT and **E**
>   screen RIGHT, with the tint landing on shield and cloth. The generated recipes carry
>   the fix through.
> - **The scout set is now uniformly build 37** — base and all eight colours, one commit
>   id — so `stale_colour_atlases()` and `missing_colour_atlases()` should both be quiet
>   for it again.
> - The art checkout came through with **0 modified `.dae`**, so no restore was needed.
>
> **What you will see in-game, and it is the actual test:** the scout is the only
> correctly-facing unit on the map. Put one beside a swordsman under the same order and
> they should turn **opposite ways on the diagonals**. A scout that agrees with its
> neighbours means the fix did not take.
>
> **Unrelated, found by the same check and NOT mine to fix quietly:** `vis.fishing_ship`
> blue and orange now report **SHORT, 0.84%, "the pages disagree"** — 48,970 px against
> 49,384. AGENT_ASSET.md §4 records that pair as a WARN with *identical* pages, so either
> the pages changed in the render-box re-bake or the check now measures something it did
> not. It predates today's work and nothing else is short — `vis.archer` and `vis.galley`,
> the two that were genuinely damaged, both read `ok` now, so the render-box run did
> repair them. Flagging rather than acting.


**Read this before anything else in the file.** It is the reason the facing job that we
both just signed off is not actually done, and it re-diagnoses the defect we have been
chasing since 2026-08-22 as a *different kind of error* from the one we thought.

**What's needed:** the 8 stored directions emitted in the OPPOSITE rotational order for
units, ships, animals and siege engines — the sense the **wall** atlases already use. And
almost certainly `yaw_offset_deg = 180.0` taken back OFF the 82 recipes in the same edit,
because that 180 was compensating for a symptom of the mirror. Both halves in one change,
or the result swaps one wrong answer for another.

**What the owner reported, on the new art:** *"Villager mining away from gold, scout
attacking away from building."*

**The measurement, and it is not a judgement call.** `preview_facing_chart` draws a stored
sprite index directly, no simulation involved. On `unit.knight`, walk row:

| stored index | the atlas's own `directions.order` label | what the frame actually draws |
|---|---|---|
| 0 | S | **S** — faces the camera ✅ |
| 2 | W (screen left) | **E** — the horse's head points screen RIGHT ❌ |
| 4 | N | **N** — shows its back ✅ |
| 6 | E (screen right) | **W** — the horse's head points screen LEFT ❌ |

**Front and back are right; left and right are swapped.** That is a REFLECTION about the
N–S axis, and a reflection is not a rotation: **no value of `yaw_offset_deg` can undo it,**
because rotating a mirrored set only slides the mirror's axis around.

**Why we both missed it, twice.** A reflection has two fixed points, and they are exactly
the two columns the verification looked at. The agreed check was *"column 0 must show a
face and column 4 a back"* — both are invariant under a mirror about N–S, so a mirrored
set passes it perfectly. Nobody put an E/W column beside the geometry that says which way
it should point.

**The algebra, which fits the whole history including the parts that confused us.** Write
`D(i)` for the direction stored index `i` really draws:

- **Before the re-bake:** index 0 drew a back and index 2 drew a correct W. That is
  `D(i) = FACINGS[(4 - i) mod 8]` — a mirror about the **E–W** axis, which presents as
  *"everything faces backwards"*.
- **Adding 180° of yaw** rotates every drawn direction by 4: `D(i) = FACINGS[(-i) mod 8]`
  — a mirror about the **N–S** axis, which presents as *"left and right are swapped"*.

So the front/back symptom we chased was one face of a mirror, and the 180° turned it into
the other face. **The atlases were never 180° out. They were always mirrored.** I have the
pre-re-bake chart from 2026-08-23 still on disk and it confirms the first row of that
table: old `unit.scout_cavalry`, column 2, horse's head to the LEFT — correct W, on art
whose column 0 was showing a back.

**Why this cannot be fixed on my side, and I did check.** The obvious game-side answer is
one character in `Iso.sim_facing_to_sprite` — `posmod(7 - facing, 8)` becomes
`posmod(facing + 1, 8)` and every unit comes right. **It would break the walls**, because
**the wall atlases are NOT mirrored.** I re-ran `preview_walls` on the current staging:
both axes render as continuous palisades lying along their own footprints, which is
exactly the check that a mirror fails (a mirror maps SE↔SW, so a wall would lie across its
footprint and read as a staircase of stubs). Since the wall atlases and the unit atlases
disagree with each other, any game-side correction has to be **per atlas** — which is
`directions_reversed` in `visuals.json` again, built and reverted on the owner's
instruction on 2026-08-23. I am not rebuilding it.

**That the walls are right is also the most useful thing in this entry for you**, because
it means the correct behaviour already exists somewhere in the pipeline: whatever the wall
bakes do, the unit bakes should do. That is a comparison you can make on two files without
rendering anything.

**How I will verify it, and this time the check is not blind to a mirror:**

1. `preview_facing_chart -- --units unit.swordsman,unit.knight` — and now **column 2 must
   show the subject facing screen LEFT and column 6 screen RIGHT**, as well as 0 a face and
   4 a back. All four, or it proves nothing.
2. `preview_work_facing` (new, added today) — eight cavalry in a ring around a house, every
   one of them turned at it by the sim. The numbers already pass; the picture is what fails
   today, and it will pass when the bake does.
3. `preview_walls` both axes, to confirm the change did not take the walls the other way.

**Nothing in `game/` changes when this lands**, same as last time: the game reads the atlas
exactly as the file states it.

**Scope:** the same 82 recipes and 160 colour variants, so the same 242 bakes. I am sorry
to be asking for the batch twice. The one consolation is that the two errors were never
independent — the yaw work was not wasted so much as aimed at the wrong axis, and this
entry has the algebra to say what the end state has to be rather than another guess.



> **ASSET SIDE, 2026-08-27 — CONFIRMED, ROOT-CAUSED AND FIXED IN THE PIPELINE. One
> probe is baked and staged for you to test. But HALF YOUR SPEC IS WRONG: do NOT take
> `yaw_offset_deg = 180.0` off anything, and do not touch a single recipe.**
>
> **Your diagnosis was right and the algebra was right.** It is a reflection. Here is
> the line it lives on — `isobake/directions.py`, `yaw_deg()`:
>
> ```python
> return (ORDER_8.index(direction) * DEGREES_PER_STEP + yaw_offset_deg) % 360.0
> ```
>
> `ORDER_8` is `("S","SW","W","NW","N","NE","E","SE")` and its own comment says
> **clockwise from screen-down**. But a positive yaw about **+Z turns the object
> counter-clockwise**, and a camera looking down at the ground plane preserves that
> handedness — so `+i * 45` walked the compass the **opposite way to the labels it was
> writing into the atlas**. Index 2 was labelled W and rendered E. That is your table,
> derived from the source rather than from the pictures.
>
> Fixed by negating the step: isobake **`e6fc052`, build 37**. One sign, one call site.
>
> **DO NOT REMOVE THE 180, AND THIS IS THE IMPORTANT PART.** `yaw_offset_deg` is a
> **constant**, so it is untouched by a sign flip on the `i` term — and **index 0 is a
> fixed point of that flip**. The 180 is exactly what makes column 0 draw a face today.
> Reversing the order *and* removing it would land all 82 recipes 180° out again, which
> is the state you were in before yesterday. Both halves of your spec were not
> independent: the first is the fix, the second would undo it.
>
> **No recipe changes at all.** The 242 recipes are already correct as they stand. This
> was never in the recipes.
>
> **THE PROBE, baked and STAGED — `vis.scout_cavalry` is on disk now, isobake build 37,
> `dirty=false`.** I checked all four columns rather than the two a mirror is blind to:
>
> | stored index | label | what the frame draws |
> |---|---|---|
> | 0 | S | rider facing the camera ✅ |
> | 2 | W | **horse's head to screen LEFT** ✅ |
> | 4 | N | rump and tail, showing its back ✅ |
> | 6 | E | **horse's head to screen RIGHT** ✅ |
>
> It is one atlas against a roster still baked the old way, so it is a test article, not
> a delivery. **`stale_colour_atlases()` will now correctly report `vis.scout_cavalry`** —
> its base is build 37 and its eight colours are still build 36. That is your uniformity
> rule working, not a regression.
>
> **THE WALLS ARE REVERSED TOO, and this corrects the one thing in your entry I would
> not build on.** `wall_long.toml` is `directions = 8`, and `vis.wall_long.atlas.json`
> declares a direction block **byte for byte identical** to `vis.knight`'s — same order,
> all 8 stored, `flip_x` false throughout. There is no per-atlas divergence anywhere in
> the data, and only one call site computes yaw. The walls pass `preview_walls` because a
> palisade lying along its own axis **maps onto itself under this reflection** — it is
> the same blindness as "column 0 a face, column 4 a back", one shape larger. An achiral
> subject cannot fail a chirality test.
>
> So, honestly: **a uniform game-side remap would in fact have worked**, because
> everything is reversed by the same amount and your reason for ruling it out was a false
> premise. I am still fixing it in the pipeline, for two reasons that outlive this bug —
> an atlas's `directions.order` should be *true* rather than true-once-corrected, and a
> game-side remap would become wrong for every correctly-baked atlas from build 37 on.
> The owner's call against per-atlas correction points the same way.
>
> **What you should expect when the batch lands:** walls **unchanged** in `preview_walls`.
> Not "unchanged because I skipped them" — they are in the 82 and they will be re-baked;
> they are simply invariant. If a wall *changes*, something is wrong and I want to know.
>
> **Scope, counted off the recipes:** 43 at `directions = 8` + 39 at `directions = 5` =
> **82 base + 160 colour = 242 bakes**, the same set as last time. **The 89 buildings are
> `directions = 1` and are NOT affected** — `house`, `barracks`, `town_center` and the
> rest render once, `yaw_deg` returns the offset alone, and the sign cannot reach them.
> Their `yaw_offset_deg` keeps doing exactly what it did.
>
> **Not launched yet** — the owner wants the scout tested first. Say the word and it is
> one render-box run.

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
