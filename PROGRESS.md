# PROGRESS.md

**Where the project is, phase by phase.** One screen if you only read the first table.

This is the *status* document. It deliberately holds no reasoning — every "why" lives in
`PLAN.md`, every owner-reported defect in `BUGS.md`, every art request in
`asset_request.md`. If this file and `PLAN.md` disagree, `PLAN.md` is the one that gets
read next to the code, so fix this one.

**Updated 2026-08-29.** Suite: **1621 tests, 207,652 assertions, 0 failures** — measured,
not quoted. **361 atlases staged.** Android build: 320.6 MB **as of 2026-08-27 and
certainly stale** — two art deliveries and a phase have landed since and nobody has
rebuilt. Re-measure before quoting it.

⚠️ **`test_tick_cost` is the one thing in this suite that can fail for reasons that are
not the code.** It reported an 8-player tick at 49.81 ms against its budget on a loaded
workstation and passed comfortably on the same commit forty minutes later, in a run that
took 350 s against the previous one's 594 s. Re-run it alone before believing it.

---

## The one-line answer

**The MVP is achieved and the game is played on a phone.** Five phases are finished
outright, six are one or two items short, and **two have not been started: 9 (ages and
tech) and 13 (dragons)**. Nothing is blocked on a decision; **13 is blocked on art**.

**Three things closed on 2026-08-27, all of which this line used to name as next:** the
unit-speed pass (2026-08-23, owner-confirmed *"sound and speed is much better"*), the whole
roster's **facing re-bake**, staged and verified in a match, and **12.2b, the AI**. That last
one grew from "re-tune it" into a rule engine: five real difficulties driven by resource
triggers in `data/ai_*.json` instead of a script of timed steps. The owner's summary of why
it matters — *"the update system support customization and supports random maps, thats the
big win from this update."*

**PHASE 4 CLOSED 2026-08-29** — the owner's instruction was to close out its open steps, and
all three did: **4.10 special abilities** (the monk heals, the dragon breathes fire over a
5×5, both promised in IDEA.md long before they existed), **4.12 stances** (four; a soldier
now defends itself and walks back to where it was standing, a villager does not), and
**4.14 formations** (line, grid, vee, box — the four the selection panel has offered as
greyed placeholders since 4.3). **4.13 closed the day before** with `SiegeSystem`.

**The dragon went to the art side the same day.** `vis.dragon` has exactly one clip,
`static` — it cannot walk, attack or die — so **phase 13 is blocked on art, not on code**.
`asset_request.md` [P7].

**What is next is Phase 5, buildings**, then 9.3 `TechSystem` (moved up because ages now
cost resources and the tech tree is what the age ladder is *for*). 2.4d Archipelago closed
2026-08-29 together with transports, which had to ship with it — an archipelago nobody can
cross is a map on which no player can reach another.

**Two things closed 2026-08-28:** 8.8's [X] clear-selection button, and the art delivery —
**gates open and close**, and the rally-point flag is baked art instead of a placeholder.

**4.8 garrison and 4.9 landed 2026-08-27.** Towers and the castle hold units (5/5/15,
nothing else — walls ruled out by the owner), garrisoned units heal 1 hp per 5 ticks and
die with the building, and **buildings can attack for the first time**: each garrisoned
archer adds half its own damage to the tower's shot. Siege out-ranges every tower on
purpose. It moved the AI ladder's tick counts, because the AI builds towers — see BUGS.md.

**Rally points landed with it.** Select one of your own buildings, tap bare ground, and a
flag goes down; anything leaving that building walks to it — an ejected garrison **and**
every unit it trains. No waypoint means the old behaviour, unchanged. What is missing is a
way to *clear* one (BUGS.md); moving it works.

---

## Phases

Legend: ✅ complete · 🟢 essentially done, small items open · 🟡 substantially built,
real work remains · ⛔ not started

| # | Phase | State | What is left |
|---|---|---|---|
| 0 | Foundation | 🟢 | **0.3 `AssetPacks`** — manifest, download, verify, mount, plus a download screen |
| 1 | Main menu | 🟢 | Server browser (see below); lobby wants faction, team and game-type controls it has no systems for yet |
| 2 | Map | 🟢 | **2.4c save map**; **2.4d Archipelago** (new, specified) |
| 3 | Camera & world view | 🟢 | 3.5 camera-follow, 3.7 tap-minimap-to-move |
| 4 | Units | ✅ | **CLOSED 2026-08-29.** The last three landed together: 4.10 abilities (monk heal, dragon fire breath), 4.12 stances (four, military defaults Defensive), 4.14 formations (line/grid/vee/box). 4.13 closed 2026-08-28 with `SiegeSystem` |
| 5 | Buildings | 🟡 | **UP NEXT.** **5.7 more buildings — art-paced, not code-paced** (23 buildings, ~70 bakes; art side's A.10). **5.3 upgrades is the code half and is half-built**: `upgrades_to` + `UpgradeBuildingCommand` + `convert_building` all ship the wall→gate upgrade. Missing is what a non-gate upgrade needs — a cost, a time, and whether an upgrade is per-building or a player-wide tech (which is 9.3's question too) |
| 6 | Resources & wildlife | ✅ | **Closed 2026-08-23** |
| 7 | Resource HUD | ✅ | |
| 8 | Main game interface | 🟢 | **8.6 chat** (wireframe only — no transport). 8.8's [X] clear-selection button landed 2026-08-28 |
| 9 | Ages & tech | 🟡 | **Ages are real: they cost resources** (AoE II's ladder, 2026-08-27) and advance on a timer with a HUD ring. **`TechSystem` still does not exist** — `techs.json` is deliberately empty and the tech-tree page renders whatever is in it. Now the biggest unstarted piece |
| 10 | Control groups | ✅ | |
| 11 | Win conditions | 🟢 | Conquest works. Regicide and Trophy are declared and inert |
| 12 | Multiplayer & AI | 🟡 | **12.2b done 2026-08-27** — five real difficulties, rule sets in `data/ai_*.json`. Left: **12.1b LAN discovery**, 12.3 campaign, 12.4 save/load and replays |
| 13 | Dragons | ⛔ | Not started — and as of 2026-08-29 **blocked on art rather than on sequencing**: `vis.dragon` carries one clip, `static`, so the unit cannot walk, attack or die. `asset_request.md` [P7]. The unit itself is real and trainable at the castle from age 4, and 4.10 gave it its fire breath |
| 14 | **NEEDS UPGRADE** — AI enemy-blindness | ⛔ | Opened 2026-08-27 with 12.2b. A declared ceiling, not a defect: no rule can see the opponent, so an army is a target number and never a response |

**Cross-cutting: 7.5 audio is BUILT** (2026-08-23) — `AudioManager`, `MatchAudio`,
`data/audio_map.json`, 131 sound ids. This line used to say it was not, which was the one
item that had claimed to be built and was not. What is left is BYTES: the 0 A.D. fetch is
rate-limited and incremental, and a clean checkout runs silently by design.

---

## What is actually next

*The two items that used to head this list are both closed. **The unit-speed pass** was
done 2026-08-23 and the owner confirmed it on 2026-08-27 — *"sound and speed is much
better"*. **4.8 garrison** was done 2026-08-27, and it did not close the wall hole it was
billed as closing: the owner ruled walls out of garrison, so 0 A.D.'s eight turret points
per medium wall stay unused by decision rather than by omission.*

**1. 2.4d Archipelago.** One island per player, a few sheep, nothing hostile. Specified in
`PLAN.md` §11.6, including the one hard part: `MapValidator` requires every start to reach
every other **by land**, which an archipelago fails by definition, so that claim has to
change rather than relax.

*~~2. 8.8, the [X] button.~~ Built 2026-08-28 — `ClearSelectionButton`, 40 px, which is the
exact height left between the control-group stack and the selection panel's ceiling.*

**2. 9.3 `TechSystem`.** The biggest genuinely unstarted phase, and it moved up because
ages now cost resources — which makes the tech tree what the age ladder is *for*.

---

## Blocked on art, not on code

Ordered by how visible the gap is in play. All in `asset_request.md`.

| Priority | Item | Why it matters now |
|---|---|---|
| **1** | **Animate the wildlife** (A.4a) | **Six species move and every one slides.** Phase 6 closed with wolves, boar, bears, deer, sheep and cattle all walking, and every fauna atlas is a single static rest pose. The most visible defect in the game |
| **2** | 36-recipe `yaw_offset_deg` re-bake (§13.2 item 10) | Every unit faces backwards. A game-side patch was built and reverted on the owner's word — this is the root fix |
| **3** | Five carcass bakes | Five defs draw `vis.deer_carcass`; a dead bear looks like a dead deer |
| **4** | A `vis.tree_teak` replacement, ideally a palm | Pulled from the forest rotation for being unselectable. Also wanted for Archipelago |
| **5** | Building roster by age (A.10) | Paces phase 5.7 and phase 9's age skins |
| — | Five estimated `footprint_m` figures | Confirm with `isobake inspect`. Affects the selection ring and outline band, not gameplay |

---

## Design material with no implementation yet

Committed as planning so the intent survives; none of it is built.

- **`AI_Player_difficulty.md`** — the per-difficulty behaviour spec for **12.2b**. The
  difficulty *list* ships and the opponents behind it do not: Normal, Hard and Unfair are
  all Easy wearing three names and the screen says so. Note the spec leans on tech-tree
  upgrades, so it is **partly gated on phase 9**.
- **`UI_Design_Lobby.png`** — the hosting lobby, and it is ahead of the systems: it shows
  **faction** and **team** columns, a **game type** (Conquest / Regicide) and a **victory
  condition** picker, a map-size choice and in-lobby chat. One civilisation is a locked v1
  decision (§1), teams do not exist, and Regicide is declared inert (11.2).
- **`UI_Design_Hosting.png`** — a **server browser** with filters, versions and a server
  list. **12.1b is the LAN subset of this**; the rest implies a master server.
- **`web/player-colour-ladder.html`** — the research behind the eight-colour palette:
  CIE lightness spread, dichromacy safety, and why the A.6 tint shader is not a multiply.

---

## Known limits worth not rediscovering

- A dock built inland before 2026-08-23 stays inland — `requires_shore` gates new placement
  only.
- Naval combat does not exist: transports have no load/unload and nothing has fought at sea.
- An open gate is open to everyone, besiegers included. Per-player passability needs a
  pathfinding grid per player.
- A static destroyed behind the fog stops being sent rather than leaving a stale ghost.
- **Routes are planned as though the map held no units.** A walker no longer shoves a
  standing unit aside — it steps around it — but it still *walks over* it, because units
  are not in the pathing grid and putting them there is not cheap (BUGS.md, 2026-08-29).
- Terrain blending draws one neighbour per tile, so where three terrains meet the third
  join stays crisp.
