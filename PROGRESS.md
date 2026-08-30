# PROGRESS.md

**Where the project is, phase by phase.** One screen if you only read the first table.

This is the *status* document. It deliberately holds no reasoning — every "why" lives in
`PLAN.md`, every owner-reported defect in `BUGS.md`, every art request in
`asset_request.md`. If this file and `PLAN.md` disagree, `PLAN.md` is the one that gets
read next to the code, so fix this one.

**Updated 2026-08-30**, tagged **v0.9.0 — the first BETA tag**, per IDEA.md's scheme
(v0.1.0–0.8.9 alpha, v0.9.0–0.9.9 beta, v1.0.0 release). Suite: **1779 tests, 208,740
assertions, 0 failures** — measured, not quoted. **361 atlases staged**, and 150 UI asset
files now ship with them (`tools/licence_audit.py`: PASS). Android build: 320.6 MB **as of
2026-08-27 and certainly stale** — two art deliveries, three phases and the whole UI
overhaul have landed since and nobody has rebuilt. Re-measure before quoting it.

⚠️ **`test_tick_cost` is the one thing in this suite that can fail for reasons that are
not the code.** It reported an 8-player tick at 49.81 ms against its budget on a loaded
workstation and passed comfortably on the same commit forty minutes later, in a run that
took 350 s against the previous one's 594 s. Re-run it alone before believing it.

---

## The one-line answer

**The MVP is achieved and the game is played on a phone.** Of the fifteen phases, **four
are finished outright** (4 units, 6 resources, 7 the resource HUD, 10 control groups),
**seven are one or two items short**, **two are substantially built** (5 buildings, 12
multiplayer/AI), and **two have not been started**: 13 dragons, which is **blocked on art**,
and 14, which is a declared ceiling rather than a phase. Nothing is blocked on a decision.

**Three things closed on 2026-08-27, all of which this line used to name as next:** the
unit-speed pass (2026-08-23, owner-confirmed *"sound and speed is much better"*), the whole
roster's **facing re-bake**, staged and verified in a match, and **12.2b, the AI**. That last
one grew from "re-tune it" into a rule engine: five real difficulties driven by resource
triggers in `data/ai_*.json` instead of a script of timed steps. The owner's summary of why
it matters — *"the update system support customization and supports random maps, thats the
big win from this update."*

**THE UI IS THE PROJECT'S OWN, 2026-08-30.** `asset_request.md` [P8] delivered 130 pieces
of owner-generated UI art and two OFL font families, and the game-side landing of it was
the largest single change to `game/` in the project's history — chrome, icons, the action
tiles, the minimap frame, the menu buttons, and **a typeface, which the game had never had
at all**. The line that matters beyond the pixels: **`game/assets/ui/` is committed in
full and a clean clone now runs with its chrome intact.** It never did before — the UI was
third-party itch.io art whose licence forbids redistributing the originals, so three
directories were gitignored and every developer downloaded two packs by hand.
`tools/licence_audit.py` went from 129 problems to PASS.

**THE LOBBY WAS REWORKED THE SAME DAY** to the owner's spec — chat down the left two
thirds, GAME SETUP and MAP SETUP down the right third, a one-row nav strip hugging the
bottom — and **HOW TO PLAY exists** (1.8): six annotated captures of this game's own HUD,
one to a page, behind the front-door button that had answered with a "not available yet"
toast since 1.1. Every front-door button now opens a screen except QUIT. Two bugs the
overhaul surfaced were fixed with it: **construction was reading as damage** and blowing
the under-attack horn (`spawn_building` starts a foundation at `max_hp/10` and
`add_build_progress` then set hp from a build fraction of a few thousandths — a fall of 52
hp on the first tick of work, wrong since the line was written and invisible until
something diffed hp across time), and **the boot splash was cropped on every device**
(a `TextureRect`'s default `expand_mode` makes the texture's own size a minimum, and a
minimum size beats anchors — the 1376×768 plate drew at 1:1 in a smaller window).

**PHASE 4 CLOSED 2026-08-29** — the owner's instruction was to close out its open steps, and
all three did: **4.10 special abilities** (the monk heals, the dragon breathes fire over a
5×5, both promised in IDEA.md long before they existed), **4.12 stances** (four; a soldier
now defends itself and walks back to where it was standing, a villager does not), and
**4.14 formations** (line, grid, vee, box — the four the selection panel has offered as
greyed placeholders since 4.3). **4.13 closed the day before** with `SiegeSystem`.

**The dragon went to the art side the same day.** `vis.dragon` has exactly one clip,
`static` — it cannot walk, attack or die — so **phase 13 is blocked on art, not on code**.
`asset_request.md` [P7].

**THE TECH TREE IS WIRED, 2026-08-29** — 9.3 and 9.4, on the owner's instruction, and it went
in ahead of Phase 5. **27 technologies at seven buildings**, bought from an action tile on the
building that holds them; the tech-tree page behind the minimap is the guide to what is where
and issues no command at all, which is the owner's own ruling and what that page has claimed
about itself since it was written. A research rides the building's existing **production
queue**, so the timer, the progress bar, the cancel and the refund were all already there —
which is why PLAN's promised `TechSystem` turned into `TechMods`, a static modifier resolver.
**The icons are backlog** (`asset_request.md` [P8]): every tile draws its name.

⚠️ **The AI does not research.** `techs: true` has been in every `ai_profile` since 12.2b
against nothing, and it still is. Both sides of the AI ladder are equally untouched, so its
table below stands — but a human buying Blast Furnace now fights an army that never will.

**What is next is Phase 5, buildings**, whose 5.3 open question is now answered: an upgrade is
the per-building mechanism and a technology is the player-wide one, so 5.3 needs a cost and a
time and nothing else. 2.4d Archipelago closed 2026-08-29 together with transports, which had
to ship with it — an archipelago nobody can cross is a map on which no player can reach another.

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
| 1 | Main menu | 🟢 | Server browser (see below); lobby wants faction, team and game-type controls it has no systems for yet. **1.5 settings and 1.8 HOW TO PLAY both closed 2026-08-30** — settings as an overlay rather than a screen, HOW TO as a six-page picture guide. The two setup panels in the lobby still do not both fit at 1152×648 and the column scrolls; flagged to the owner rather than guessed at |
| 2 | Map | 🟢 | **2.4c save map**, and nothing else — 2.4d Archipelago closed 2026-08-29 |
| 3 | Camera & world view | 🟢 | 3.5 camera-follow, 3.7 tap-minimap-to-move |
| 4 | Units | ✅ | **CLOSED 2026-08-29.** The last three landed together: 4.10 abilities (monk heal, dragon fire breath), 4.12 stances (four, military defaults Defensive), 4.14 formations (line/grid/vee/box). 4.13 closed 2026-08-28 with `SiegeSystem` |
| 5 | Buildings | 🟡 | **UP NEXT.** **5.7 more buildings — art-paced, not code-paced** (23 buildings, ~70 bakes; art side's A.10). **5.3 upgrades is the code half and is half-built**: `upgrades_to` + `UpgradeBuildingCommand` + `convert_building` all ship the wall→gate upgrade. Missing is a COST and a TIME for a non-gate upgrade — and nothing else, since **9.3 answered the third question**: an upgrade is the per-building mechanism and a technology is the player-wide one, so they stay two things. The queue 9.3 taught to hold a research is where the time goes |
| 6 | Resources & wildlife | ✅ | **Closed 2026-08-23** |
| 7 | Resource HUD | ✅ | |
| 8 | Main game interface | 🟢 | **8.6 chat** (wireframe only — no transport). 8.8's [X] clear-selection button landed 2026-08-28 |
| 9 | Ages & tech | 🟢 | **Ages are real: they cost resources** (AoE II's ladder, 2026-08-27) and advance on a timer with a HUD ring. **9.3 and 9.4 landed 2026-08-29**: 27 technologies at seven buildings, researched from an action tile on the building, with the tech-tree page as the read-only guide to what is where. What is left is **9.5 civilisations** and **9.6 the age re-skin**, both art-paced. ⚠️ **The AI researches nothing** — `techs: true` in every profile against no rule that emits a `ResearchCommand` |
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

*Swept 2026-08-29. **Everything this list held has shipped** — the unit-speed pass, 4.8
garrison, 8.8's [X] button, 2.4d Archipelago and 9.3/9.4 the tech tree — so the whole list
was replaced rather than ticked off. `PLAN.md` §15 is the authoritative version of this and
carries the reasoning; what follows is its first three lines.*

**1. Phase 5, buildings** — the owner's call, and two very different jobs. **5.7, the full
roster**, is 23 buildings and ~70 bakes: art-paced, waiting on A.10. **5.3, upgrades**, is
the code half and is half-built — it needs a cost and a time for a non-gate upgrade, and
nothing else now that 9.3 has settled that an upgrade and a technology are two mechanisms.

**2. The AI has no rule that researches.** `techs: true` has been declared in every
`ai_profile` since 12.2b against nothing, and 9.3 did not change that — it made it matter.
Note that the first rule that researches invalidates every row of BUGS.md's ladder table.

**3. Then, in no forced order:** 2.4c the map save format, 12.1b LAN discovery, 12.3
campaign, phase 14's AI enemy-blindness, and 13.x dragons once the art lands.

---

## Blocked on art, not on code

`asset_request.md` is the authoritative queue and its own priority table is derived from
this file — so this is the short version, not a second list to keep in step.

**Swept 2026-08-29.** Four of the five rows this table used to hold had been delivered on
2026-08-28 and none had been crossed off — the wildlife animations, the six carcasses, the
palm that replaced `vis.tree_teak`, and the mirrored-atlas fix that the `yaw_offset_deg` row
was really about. It read as a wall of blockers when one thing was blocked.

| Priority | Item | Why it matters now |
|---|---|---|
| **P7** | **`vis.dragon` cannot move** — it has one clip, `static` | **The only art gap that blocks a whole phase.** PLAN.md 13 is unstartable while the dragon is a statue. Nothing is blocked today: it trains, fights and breathes fire |
| **A.10** | Building roster by age | Paces **5.7** (23 buildings, ~70 bakes) and phase 9.6's age skins. Running in the background on the art side and not in the request queue |
| **P8** | 27 technology icons | Backlog by the owner's instruction. Every research tile draws its name instead; no code changes when they land |
| **P5** | Ten estimated `footprint_m` figures — five animals and five carcasses | Confirm with `isobake inspect`. Affects the selection ring and outline band, not gameplay |
| **P6** | Player colour on two packed siege actors | A blue player's onager turns plain while it is rolling. Cosmetic, and only while moving |

---

## Design material with no implementation yet

Committed as planning so the intent survives; none of it is built.

- **`AI_Player_difficulty.md`** — the per-difficulty behaviour spec for **12.2b**. The
  difficulty *list* ships and the opponents behind it do not: Normal, Hard and Unfair are
  all Easy wearing three names and the screen says so. It used to be *"partly gated on phase
  9"* because the spec leans on tech-tree upgrades; **that gate lifted on 2026-08-29** — the
  technologies exist and `ResearchCommand` is there to be emitted. What is missing is a rule
  that emits one.
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
