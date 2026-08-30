# BUGS.md

Playtest findings from the project owner. **Open items in full; a fixed one is kept only
if it still earns its place**, which means one of three things: it left a standing hazard
that can bite again, it reversed a documented decision, or it imposed a live constraint
somebody would otherwise be surprised by. Everything else is in the code it fixed and in
git.

An item here is the owner's word on the behaviour they want — where that reverses an
earlier deliberate decision, the reversal is noted rather than argued.

*Cleaned 2026-08-23: 424 lines to this. Nothing open was removed. The fixed items dropped
were ones whose reasoning already lives in the code — villager facing, the sort-band
teleport, the mid-stride corpse, the entombed foundations, wall merging, the rotated lobby
preview, the MTU measurements (now PLAN.md §12.1f), and the AI's building-only targeting.*

---

## Open

### Playtest, 2026-08-30 — FOUR DEVICES, six findings, all six closed

*The first session on **two Windows machines, an Android handset and an AI** — and it is
the device count that produced four of the six. Two of them (the missing alerts, the
silent forfeit) are things **only a joined client can see**, and one (the dead volume
sliders) is a thing only a FINGER can see. All three had been in the code since the
feature was written, invisible because everything is tested solo, on a desktop, with a
mouse — so the branch that is wrong is the branch nobody takes.*

- [x] **"Player 2 and player 3 does not get alert for not enough resources when placing a
      building or trying to age up."** ✅ **Every polite refusal in `GameScene` asked
      `Net.host().world`, which is NULL on a joined client** — so the guard in front of the
      toast was simply false for players 2..8, the command went out, `validate()` dropped
      it in silence, and the button read as broken. Three handlers: age advance, train and
      research.

      ⚠️ **THE COMMENTS ON ALL THREE SAID THE FIX WAS "a job for the multiplayer phase",
      AND THEY WERE WRONG WHEN THEY WERE WRITTEN.** `SnapshotSystem` has sent every player
      their own `stock` for as long as `player_state` has existed, and `GameView` already
      cached it — which is exactly why the **placement ghost was the one refusal that
      already worked for a joined player**, and why the owner's report names age-up
      alongside it: on a client the ghost turned red and said "Not enough resources" while
      the age badge went dead and said nothing. One path now serves both sides,
      `PlacementAdvice.can_afford` over `GameView.stock_of`, the way the ghost always did.

      *Two things went in with it.* Train never checked COST at all, on either side, so a
      press with no gold did nothing and said nothing; it does now. And every one of these
      messages **names the shortfall** ("Need 120 food and 30 gold") rather than saying
      "Not enough resources", which was the age badge's standard since 2026-08-28 and had
      not reached the other four.

      **The general form is worth keeping: a guard of the shape `if <thing only a host
      has> != null and <the rule>` is not a guard, it is a rule that is off on every
      client.** Grep for `Net.host()` before writing another.

- [x] **"When a player disconnects or resigns the server does not notify other players."**
      ✅ Also **BUGS.md's own older "a forfeit is announced as an elimination"**, which is
      the same gap seen from the other end and is now closed with it.

      `SimPlayer.defeat_reason` (`NONE / ELIMINATED / RESIGNED / DISCONNECTED`) rides
      `player_state` beside `defeated`, and `Net` labels the `ResignCommand` it queues for
      a vanished peer as DISCONNECTED. `GameScene._announce_defeats` toasts "Player 3 has
      resigned" the moment it happens, and the result screen finally tells the truth about
      how the match ended instead of "All opponents eliminated" about somebody whose phone
      lost signal.

      ⚠️ **`SimPlayer.defeat()` KEEPS THE FIRST REASON AND THAT IS THE WHOLE REASON IT IS A
      FUNCTION.** `WinConditionSystem` retests every player every tick and defeats anyone
      owning nothing, so a player who resigns and then has their abandoned base knocked
      down would have been relabelled ELIMINATED — the winner told the opposite of what
      happened, which is this bug arriving through a different door. A two-player world
      cannot catch it: `match_over` latches on the first concession and the system stops
      evaluating. The test uses three.

      *Primed, not announced, on the first snapshot* — a defeat is a STATE and not an
      event, so a client joining a match where somebody has already conceded would open
      with a toast about something that happened before it arrived. Same trap
      `MatchAudio`'s header records for hp.

- [x] **"Wood needs a buff, there is not enough by a long shot, by mid age 3 we gathered
      every tree on the map, lets start by doubling it. We need to light sprinkle trees
      over the rendered maps."** ✅ Both halves. `res.tree` 40/100/175 → **80/200/350**, and
      `MapGenerator._sprinkle_trees` puts single trees on a coarse lattice over open
      ground, off the wood mask entirely.

      **THE SPRINKLE IS THE HALF THAT MATTERED, and the measurement says why.** The copses
      only ever go where the terrain noise said wood may go, so a desert's open sand and a
      river's far bank were bare — the desert carried **38** trees after the sprinkle
      against roughly 16 before, so on the sparse types it did more than the doubling did.
      Wood per player, measured: island 5,185 → 10,370, desert 4,025 → 8,050, river
      10,020 → 20,040, forest 54,600 → 109,200.

      ⚠️ **THE CEILING IS `AISystem`'s PER-TICK LINEAR SEARCHES, NOT THE SNAPSHOT** — see
      `SHAPE`'s note on the `clump: 9` attempt that took the AI match to 24.83 ms a tick
      and hung a session. **Amount-per-tree is the free lever and trees-per-map is the
      expensive one**, which is why the doubling did the heavy lifting and the sprinkle is
      a dozen or two trees a board.

      *One thing it nearly broke:* the sprinkle does not read the wood mask, which is what
      makes it a sprinkle — and clearing the mask is how the forest's **road** between
      players is kept clear. `_clear_lanes` now returns the road as a set and the sprinkle
      avoids it. Only `test_there_is_a_clear_road_between_the_players` would have said so.

- [x] **"The archipelago map type is so small you cannot fit half of the building from age
      2 on it."** ✅ `ISLAND_RADIUS` 18 → **26**, and the board is now derived from the
      island instead of the island being capped by the board (`archipelago_side`): 128 at
      two players, 160 at four, 240 at eight, against `side_for`'s 96 / 128 / 192.

      ⚠️ **RAISING THE RADIUS ALONE MAKES THE ISLANDS SMALLER, and that is the trap.**
      `_archipelago_ring_radius` subtracts the radius from the half-side, so a bigger
      island pulls the start ring inward, which shortens the chord between neighbours,
      which is exactly what `_island_radius` caps against — at 26 on the old 96-tile
      two-player board the cap lands at **12**. The dependency had to be inverted, not
      re-tuned. `ISLAND_RADIUS`'s note records the reversal: it used to argue that nothing
      above the validator's floor bought anything.

      **AND THE WOOD PASS COULD NOT REACH THIS TYPE, which the count caught and nobody had
      asked about.** The mask is nearly empty on an island and the sprinkle lattice is laid
      over a board that is 92% sea, so it landed **one** tree on a two-player map: 1,971
      wood per player at eight players, against a desert's 4,025, on the map whose whole
      point is a fleet — a galley is 90 wood and a galleon 200. `CONTENT` gained
      `start_wood` 20 (from 8) out to 22 tiles, through the guaranteed-opening mechanism
      rather than a fourth lever. Now 5,300 and 4,562 per player.

- [x] **"Galley WarShip does not render arrows, it needs to do batchs of 10."** ✅
      `UnitDef.attack_volley`, `BuildingDef.attack_volley`'s twin, and `unit.galley` is the
      one unit in the roster that declares one.

      **THE ARROW WAS NEVER MISSING.** A galley reloads every 30 ticks and a projectile is
      airborne for 2–8 of them, so at `SimClock.TICK_HZ` 10 the boat drew one arrow every
      three seconds for about half a second — the watch tower's complaint of 2026-08-28,
      for the identical reason: neither has an archer sprite drawing a bow to explain where
      the shot came from, and a ship with no walk clip that also appears not to fire reads
      as scenery.

      **Cosmetic, so the 6 damage is untouched** — `SimProjectile` carries none. There is a
      test pinning that, because the day a projectile carries a hit a galley becomes a
      60-damage warship. `buildings.json`'s note asked for a unit volley to be priced
      against 12.1f first: one galley holds ~1.3 arrows in the air on average, less than a
      land archer's one every 10 ticks, and a FLEET is what makes it add up — so it is on
      the one unit that asked and not on every ranged unit.

      **`unit.galleon` is deliberately left at 1** and needs the owner's word: it is the
      bigger warship at range 7 and 12 damage, so a galley out-drawing it will look wrong
      the first time the two are side by side.

- [x] **"On android while in game opening settings does not allow me to interact with
      volume sliders."** ✅ `TouchSlider`, and **"in game" is the whole report** — the front
      door's SETTINGS shows the same `VolumePanel` and has always worked.

      **MEASURED RATHER THAN GUESSED**, because "cannot interact" has half a dozen
      plausible causes and only one of them is this. A throwaway probe pushed real touch
      events through the viewport at an `HSlider` starting at 0.50, tapping and dragging at
      95% of its track:

      | route | `emulate_mouse_from_touch` | tap | drag |
      |---|---|---|---|
      | real input pipeline | **false** — the in-match case | 0.50 | 0.50 |
      | real input pipeline | true — the menus | 0.95 | 0.95 |
      | a mouse click | — | 0.95 | |

      So it is not a hit-test order problem, not a small target, not sluggish: Godot's
      `Slider` drives its value from `InputEventMouseButton` and `InputEventMouseMotion`
      and from **nothing else**, and this project sets
      `emulate_mouse_from_touch = false` — which `GameScene` turns off on entry and hands
      back in `_exit_tree`, so it is off **for exactly as long as a match lasts**. The
      three sliders were inert on the phone from the day they landed.

      ⚠️ **THE FIX IS THE CONTROL, NOT THE PROJECT SETTING, and the one-liner is a trap.**
      Turning emulation back on while the menu is up would fix every control at once and
      leave a global flag that must be turned off again on every path out of the menu — and
      the failure when one path misses it is a camera that pans twice for the rest of the
      match, silently. That is `GameScene._exit_tree`'s own recorded hazard from the other
      direction.

      `TouchSlider` is `TouchLineEdit`'s twin one control along, and **additive rather than
      a replacement**: `accept_event()` is deliberately not called, so with emulation on the
      base class still runs and both set the same value from the same position. Setting a
      value from a position is idempotent, which is what makes doubling up harmless here
      where it would not be on a button. The arithmetic is Godot's own from
      `Slider::gui_input`, grabber width included, so a thumb and a mouse land on the same
      number rather than on similar ones — measured at 0.95 either way.

      **The general form, and it is why this was invisible for so long: every other control
      in the game is a `BaseButton`, and a button DOES answer a raw touch.** These three
      sliders are the only controls in the project that are not, so "touch works on this
      screen" was true of everything anybody had pressed.

*Three things this round turned up that were nobody's report:*

- ⚠️ **A GALLEY STANDING ON LAND CANNOT BE ORDERED TO ATTACK ANYTHING, and it looks
  exactly like a volley that will not draw.** `AttackCommand.validate()` returns true, the
  route comes back empty from `PathService` because a water unit on grass has no start
  node, the task is retired on the first tick, and `task` reads IDLE with nothing logged.
  The debug map has **zero** water tiles, so both the test and the preview had to paint a
  channel (`test_transport._make_a_coast`'s trick, plus `PathService.rebuild` — `AStarGrid2D`
  holds solidity in the grid, not in the query). Real naval combat is still unbuilt (§15).
- ⚠️ **`preview_projectiles` HAD NEVER ONCE CAUGHT THE TREBUCHET**, and said so in a
  warning every run since siege packing landed on 2026-08-28. Its catch budget was 240
  frames — 40 ticks — and a trebuchet spends `packing.ticks` **80** deploying before it may
  fire. The onager's 50 would have failed too. `CATCH_FRAMES` is 900 now and all five
  shooters land a picture.
- ⚠️ **THAT PREVIEW WAS ALSO PHOTOGRAPHING THE WRONG SHOT.** Every shooter in it is
  DEFENSIVE by default (4.12) and every victim stands inside `GUARD_RADIUS`, so the volley
  it caught was the auto-acquired one fired during set-up, a frame or two before it
  despawned — invisible while every shooter loosed exactly one projectile, and obvious the
  moment the galley's ten reported **1 in the air (expected about 10)**. Both ends are
  PASSIVE now. Same class as the six tests that broke on 2026-08-29: *a fixture whose
  premise is "nobody acts unless I say so" is resting on an absence.*

### Playtest, 2026-08-29 (second round) — two findings, one fixed whole and one fixed by half

- [x] **"the green circle when selecting units don't look good on buildings. replace the
      green circle with one tracing the footprint square."** ✅ `EntityView.ring_square`,
      set by `GameView` for anything the registry calls a building. The corners are
      literally `PlaceholderRenderer.footprint_points` — the same four `PlacementGhost`
      draws — so the box the player was shown while placing is the box they get back when
      they select what they placed. That function's header has said *"public because the
      selection ring will want the same outline later"* since 0.2b.

      **The sizing changed with it, and that is the half worth knowing.** A ring had always
      been drawn from the VISUAL's measured extent — `vis.villager` is an authored 0.6 m —
      and buildings now read the SIM's footprint instead. The two are not the same rect: an
      age-4 town centre's mesh overhangs its 8×8 gameplay box, so the traced square cuts
      across the art rather than containing it. **That is correct and is the point of
      tracing** — the square is the ground the building holds, refuses to be built over and
      was ghosted on. A ring drawn to the mesh would be a prettier lie.

      Units keep the ellipse, and must: a villager occupies a vague 0.6 m of a tile, not
      the tile, and a ring the size of her footprint would be three times too big.

      *One case folded in rather than kept special:* a north-south wall was already sized
      from its footprint (the 2026-08-22 fix, since its art is baked east-west) and that
      branch is now simply the general rule.

- [ ] **"units path find through each other, pushing each other out of the way."**
      ⚠️ **Half fixed. The pushing is answered; the pathing is not, and cannot be cheaply.**

      **What was fixed:** `SeparationSystem` split every push evenly, so a soldier crossing
      the base barged a line of gatherers off their nodes on the way through and left them
      there. A unit that is standing still is no longer moved by one that is walking — the
      walker owes the whole correction, because it is the one that chose to be there — and
      the walker's correction is turned SIDEWAYS across its own heading, so it steps around
      rather than bouncing back down the line it is about to re-walk. Two walkers still
      split evenly; **so do two standers, and that one is load-bearing** — a barracks
      emptying its queue puts several units on one tile and nothing else would ever part
      them (`SimWorld.find_free_adjacent` says so in its own header).

      ⚠️ **THE TRAP, and it cost three deadlocked tests before it was found: a positional
      correction has to be small next to a tick's movement, or it is not a nudge, it is a
      throw.** `MAX_PUSH` is 120 sub-units and a villager covers ~26 in a tick, so an
      uncapped sidestep outweighed the step `MovementSystem` had just taken by five to one.
      The unit was thrown clear, spent several ticks walking back to the line it was thrown
      off, and got thrown again — forward progress **zero**, for as long as the order stood.
      Capping the correction at the mover's own `speed` is what makes it steering instead
      of a collision. Anything else that writes to `pos` outside `MovementSystem` owes the
      same comparison.

      **What is NOT fixed:** a route is still planned as though the map were empty. Units
      are not in the pathing grid and putting them there is not a small change —
      `AStarGrid2D` holds solidity IN THE GRID rather than in the query (`PathService`'s own
      note), so avoidance would mean re-weighting up to 200 cells every tick and would make
      a route depend on where everyone happened to be standing when it was solved. Real
      local avoidance is PLAN.md 4.2's *"steering"*, which `SeparationSystem`'s header has
      always admitted is short of RVO. **Left open rather than half-attempted**: the visible
      symptom the owner reported — being shoved — is gone, and walking *over* somebody
      still looks wrong.

### Playtest, 2026-08-29 — one finding, FIXED the same day, and the ruling matters more than the fix

- [x] **"game is stuck, villagers died" → "the villagers walk past the knight/scout to
      build the house, the scout kills most of them"** (project owner, minutes after 4.12
      shipped). ✅ **Fixed in the TEST MAP, not in the sim, and that was the owner's call:**
      *"game mechanics is working correctly no change needed, just move the enemy a little
      bit away in the test map."*

      **What happened.** Stances gave military units a DEFENSIVE default, so a unit
      acquires anything hostile within `StanceSystem.GUARD_RADIUS` (5) of where it stands.
      `MapGen.DEBUG_ENEMY_SQUAD` had sat at (12, 0) and (14, 0) since it was written —
      **three tiles from the starting villagers**, who ring the town centre one tile off
      its wall. That placement was correct for as long as nothing attacked unasked, and
      became a firing squad the moment something did. `preview_match` reproduced it
      headlessly and finished with a population of **2 of 10**.

      **Two things were moved.** The squad went to (20, 18) — twenty tiles out, into the
      one quadrant of the debug map with no villager traffic, since gold, berries, stone,
      wood and the pasture between them cover every other direction. And the archer and
      knight were **separated from two tiles apart to twelve**: with a radius of 5 each
      covers the other, so anything close enough to trade blows with the archer is close
      enough to be ridden down by the knight, and the pair was not two enemies but one
      fight the opening cannot take. `MapGen`'s header carries both arguments.

      ⚠️ **The ruling to keep: the mechanic was right and the CONTENT was wrong.** This
      is the third finding in a row (see the two rounds below) where nothing was a wrong
      number. What made it look like a bug was a fixture written under an assumption that
      had quietly stopped holding — the same shape as the six *tests* that broke the same
      day, all of which put two hostile units near each other and expected nothing to
      happen. **A placement is a claim about behaviour, and 4.12 changed the behaviour.**

      *One consequence, recorded because it is not obviously an improvement:* the squad
      is now **behind the fog**, so `preview_match` had to march the villagers out to find
      it before it could tap one. Its standoff must be inside the villager's own `los` of
      **4** — the first attempt used 6 and the villagers stood next to an enemy they could
      not see, which reported as "nobody to fight".

### Playtest, 2026-08-28 (second round) — three findings, ALL THREE FIXED the same day

*Two of them are about what the player can SEE, and the third is about what they can DO.
Worth noticing together: none of the three was a wrong number. The tower's damage was
right and invisible, the wolf's damage was right and inescapable, and the arrow's flight
was right and left nothing behind.*

- [x] **"watch tower is not showing 5x rocks when attacking + X x arrows for each archer
      in garrison in it when attacking. guard towers are not showing 5x arrows + X x
      arrows for each archer in garrison in it when attacking."** ✅ `attack.volley` in
      buildings.json — 5 for both towers and the castle — plus **one more per garrisoned
      archer, drawn with that archer's own projectile**, so a crossbowman in a guard tower
      throws a bolt and nobody maintains a list of which unit shoots what twice. The watch
      tower now throws `vis.projectile_stone` rather than arrows; **its garrison still
      shoots arrows, because the arrows come from the archers.**

      **THE DAMAGE IS UNTOUCHED AND THAT IS WHAT MAKES IT SAFE.** A projectile carries no
      damage — the blow lands the instant it is fired — so twenty arrows out of a full
      castle are the one 42-damage hit `attack_bonus` already priced, drawn twenty times.
      Every number in buildings.json's table still stands. There is a test asserting
      exactly this, because the day somebody makes a projectile carry a hit, the volley
      silently becomes five attacks.

      *Judged from `preview_projectiles`, which grew a fourth shooter for it: a garrisoned
      watch tower, 5 stones + 3 arrows, photographed mid-flight and again where they land.
      A tower needed adding because it is the case no unit can stand in for — its shot is
      a volley, and **nothing can order a building to attack**, so there is no command to
      watch land.*

- [x] **"wolf is very very strong against early villagers… if a wolf, bear, boar gets
      within 15 tiles of a building it should retreat to a random spot opposite direction
      from the building and reset agro, so early game the player can manually run
      villagers back town to save them, at this stage 1 wolf eats 4 villagers before they
      get to kill it, decimating the player early game."** ✅ `WildlifeSystem`
      `SETTLEMENT_RADIUS` 15, measured from the **footprint** so a castle's sanctuary is
      15 tiles beyond its 7×7. A predator inside it stops, forgets its target, and walks
      to a point `15 + 5` tiles out on **its own side** of the building, with a
      deterministic ±0.9 rad of spread so a pack does not retrace one ray.

      **THE ARITHMETIC WAS NEVER THE PROBLEM.** A wolf deals 20 to a 30 hp villager who
      deals 3 back: she loses in two bites and needs ten to win. That is *fine* — it is
      what makes a wolf frightening — but there was no OUT, because `_hunt` re-acquires
      the moment `CombatSystem` drops the task, so a wolf chased a fleeing villager into
      the town centre and kept eating. The fix is ground rather than a rule about
      villagers: **the predator leaves, whoever it was chasing**, which a player can also
      *see* happen.

      Three behaviours were reused rather than added, and the retreat rides `flee_ticks`
      to get all of them for one line each: it already means "do not think, you are
      running", so the animal ignores `_hunt` for the journey, plays the `run` clip, and
      on expiry relocates `roam_home` to where it ended up — so the wolf takes up
      residence outside instead of drifting back to the clearing it was driven from.

      **Three consequences worth knowing.** A tower will now rarely shoot a bear, since
      the bear leaves before it gets close. `test_a_wolf_does_not_gnaw_buildings` still
      passes but for a new reason — the wolf is not gnawing because it is leaving. And
      **the AI-vs-AI baseline table below is measured against predators that did not do
      this**: an AI's villagers work inside their own settlement, so this takes a source
      of attrition off both sides. Nothing in the table is invalidated, but the next
      change measured against it should re-run the five seeds first rather than compare
      across this line.

- [x] **"in AOE arrows linger on the ground after hitting for a few seconds, can we
      simulate our arrows and rocks and bolts to work in the same way"** ✅
      `SpentProjectiles`, a decal layer between the ground and the entities: 4 s, fading
      over the last 1.5, darkened, scattered a few pixels so a volley reads as litter
      rather than a stack, capped at 240.

      **NONE OF IT IS IN THE SIM, deliberately.** A spent arrow has no hit points, blocks
      nothing and can be tapped by nobody — putting it on the wire would send a hundred
      fog-filtered, hash-folded entities during a siege to draw marks on the grass, and
      would make "when does it vanish" something two hosts can disagree about. The view
      infers it from `removed`, the same way `MatchAudio` infers sound from snapshot
      diffs.

      **The ambiguity `MatchAudio`'s header warns about is resolved here rather than
      lived with**: an entity absent from `updated` may have died or may have walked into
      the fog, but `removed` is only ever an explicit despawn — so an arrow that flies
      into the fog leaves no litter, which is right, because you did not see it land.
      That did cost a reordering: `GameView` used to run its forget pass *before*
      `removed`, which erased the facts of a despawned entity first and threw the
      distinction away every time.

      **It also uncovered a real bug in flight.** `ProjectileSystem` despawned a shot on
      the very tick `advance()` clamped it to its target, so that position never reached
      a snapshot and **every arrow in the game vanished about a tile and a half short of
      what it was fired at**. Unreported for the obvious reason: an arrow is on screen for
      two ticks, and a sprite failing to appear somewhere is far harder to notice than one
      appearing wrongly.

### Playtest, 2026-08-28 — four findings, ALL FOUR FIXED the same day

*Kept in full rather than collapsed, because three of them were **dead code** — a check
written for a case it could never reach — and that is a class worth being able to
recognise again. Two of the three were cancelling each other out.*

- [x] **"Gathering dropoff only in front of building, add all 4 corners and middel of
      each side if we can."** ✅ **It was not "the front" — it was ONE TILE**, and the
      distinction matters because the symptom looked like a facing or a side rule.
      `GatherSystem._start_return` asked to path to `bld.tile()`, which is the building's
      **centre** and therefore solid, so `PathService.goal_for` substituted
      `_nearest_walkable` — a fixed ring sweep, deterministic by design, which handed
      **every villager on the map the same tile**. Now `SimBuilding.drop_off_points()`
      offers the owner's eight (four corners, four side middles, one tile out) and
      `_drop_off_spot` takes the nearest, ties to the earlier point, over a fixed order
      because two clients picking different corners for one villager is a desync.

      **A side effect worth knowing: a villager working right beside its drop-off now
      makes no journey at all.** It is already standing on a drop-off point, so it banks
      from where it stands. That is strictly better than the old walk-to-a-fixed-tile-and-
      back, and it broke a test that had been asserting the journey
      (`test_animation_system`'s carry clip, whose tree was one tile from the town
      centre). The tree moved; the behaviour stayed.

- [x] **"Villager push each other out of the way, when they are pushed too far from build
      site for mining rock or tree for chopping it stops their work and leaves them
      idle."** ✅ Three systems read "not adjacent to my work" as "this order cannot be
      honoured" and retired the unit: `BuildSystem._process`,
      `GatherSystem._process_gather` and `_process_return`. Fair when the only way to lose
      adjacency was a stale walk-up tile.

      **`SeparationSystem`'s own comment says it cannot happen, and it is wrong.**
      `MAX_PUSH` is 120 against a 256 sub-tile, and the note argues 120 "can never carry a
      unit out of the tile MovementSystem just placed it in" because it is inside half a
      tile. True only from the tile's *centre*: from sub-position 250 a +120 push lands at
      370, the next tile along. The code under that comment already calls
      `spatial.move()` when the tile changes. `SimSystem.rejoin_work` now walks the worker
      back, bounded by `SAME_WORK_RADIUS` so a genuine displacement still retires, and
      self-limiting because an unreachable goal comes back as an empty route.

- [x] **"Age up, does not tell you why its failing when clicked."** ✅ The invisible case
      was **cost**: `AdvanceAgeCommand.validate()` refuses silently, and a dropped command
      is indistinguishable from a dead button — the exact failure mode
      `_on_train_requested` was given a polite half for. `_on_age_advance_requested` now
      names the **shortfall** ("Need 120 food and 30 gold to reach the Imperial Age")
      rather than the rule. `AgeBadge` also gained `advance_unavailable`, so its two
      silently-swallowed presses (already advancing, last age) say so too — both states
      are drawn on the badge and neither reads as an answer to a press.

- [x] **"Wolf renders behind the field i am unable to target it for attack."** ✅ **Two
      dead guards that had been cancelling out**, which is why this one is worth reading
      twice.

      `GameView._in_front_of_any` contained `if r.has_point(tile): return true` — standing
      on it counts — below a guard that made it unreachable: `Occlusion.is_in_front` is
      `tile.x >= r.end.x or tile.y >= r.end.y`, false for **every tile inside the rect**.
      So the one case it was written for was the one case it could never answer. It shows
      only on a building a unit can stand inside, i.e. a walkable one — a field, or an
      open gate. `Occlusion.hides()` returns false for the same case *correctly*, so the
      wolf got no sort lift **and** no outline and simply vanished under the wheat.
      **Targeting was downstream of drawing**: `pick()` already prefers units and answers
      by tile, so a wolf you cannot see is a wolf you cannot aim at.

      **Fixing it immediately failed three unrelated sort tests**, and that is the second
      dead guard: the caller read `not entry.has("footprint")` to mean "is a unit", and
      **12.1f took `footprint` off the wire**. Every entry looked like a unit, so every
      *building* was asking `_in_front_of_any` about itself — harmless only because a
      building's own tile is inside its own rect and the unreachable branch answered
      false. The occluder loop twenty lines above had already been fixed for exactly this
      and its comment says so; the sort guard was missed. It asks the registry now.

      **The standing hazard:** a guard that infers an entity's KIND from which fields a
      snapshot happens to carry is wrong the moment the wire format is optimised, and
      12.1f did that once already. Ask `GameDataRegistry`.

### Facing — reported 2026-08-27 on the freshly re-baked art

*"Villager mining away from gold, scout attacking away from building."* **Two separate
faults that looked like one**, which is why the morning's re-bake appeared to fix nothing:

- [x] **The villager was never turned at all — FIXED 2026-08-27, and it was ours.** Until
      today `facing` was written in exactly **two** places: `MovementSystem` (the way you
      walk) and `CombatSystem` (the thing you are hitting). Nothing turned a unit toward
      what it *worked*, so a villager kept whatever direction her last path step left her
      in and mined over her shoulder for the rest of the match. `GatherSystem` and
      `BuildSystem` now face the unit at the node or the foundation, at the same point in
      the tick each of them already checks adjacency — so a villager waiting her turn at a
      busy seam looks at it too, not only the one extracting this tick.

      **The standing hazard it leaves:** `facing` is part of `state_hash()`, so anything
      that sets it must be a pure function of sim state on every host. Both new lines are
      (two positions in, one octant out) — but the next system that wants to turn a unit
      must clear the same bar, and "it looked right on my screen" is not that bar.

- [x] **The scout was turned correctly and DRAWN backwards — the atlases were MIRRORED.**
      ✅ **FIXED on the art side and CONFIRMED BY MEASUREMENT 2026-08-29.** The pipeline fix
      was `isobake e6fc052`, which negated the compass step in `directions.py:yaw_deg()` —
      the render swept the opposite way to the labels it wrote — and 242 atlases were
      re-baked with it (`asset_request.md`'s Delivered log, [P0]).

      **How it was confirmed rather than assumed**, since this bug survived two rounds of
      being declared fixed: `preview_work_facing` puts eight cavalry in a ring around a
      house and reports all eight turned at it, and `workfacing_siege.png` was then read at
      the two columns that matter. The rider WEST of the house looks right; the rider EAST
      of it looks left. **Both are looking at the house**, which a mirror about N–S makes
      impossible — it is the one thing that swaps exactly those two.

      ⚠️ **THE STANDING HAZARD OUTLIVES THE BUG, and it is the expensive lesson here:** the
      agreed check was *"column 0 must show a face and column 4 a back"* — **and those are
      exactly the two columns a mirror about N–S leaves alone.** A verification blind to the
      fault it is meant to catch will pass forever, and this one passed twice while a
      242-atlas re-bake was spent on the wrong diagnosis. **Any facing check reads columns
      2 and 6 as well.** `test_wall_facing` is the automated half (it measures the staged
      pixels and fails a rebake that turns a wall); `preview_work_facing` is the half that
      needs an eye, and it states the geometry rather than leaving it to be judged.

### Balance — the top of the list

- [x] **Every unit feels too fast — DONE 2026-08-23, every speed halved.** Owner-reported
      2026-08-21 from a real two-device match on a phone, parked deliberately until it could
      be done as ONE pass over the whole roster rather than a nudge to whichever unit was on
      screen. The owner's instruction closed it: *"if we reduce the unit speed by 50% making
      them half as slow as they are now"*. The villager went 200 → 100 and every other unit
      scaled by the same half, so relative pacing is untouched; `units.json`'s note carries
      the arithmetic and the four `speed: 0` units stayed 0.

      **Two consequences to weigh before tuning anything else**, both of them new open items
      rather than reasons to undo this:

      1. **It cut the economy, not just the walking speed.** A gather trip is walk-out,
         extract, walk-home, deposit — halving speed doubles both walks, so resource income
         is closer to halved than unaffected, and worse the further the node. If the game now
         feels slow rather than merely calmer, `gather_rate` is the lever, not `speed`.
      2. **It broke the AI-vs-AI baseline** (see that section below), by amplifying the
         already-open "a build step gives up when short of resources" bug until both AIs
         reach their attack step with no army.

      **The sound half of the same report was a separate cause and is fixed separately.**
      The report reasoned that chopping, mining and wildlife attacks repeated too fast
      *because* units moved too fast. They do not: while a unit holds a work or attack
      animation, the repeat rate is set by `throttle_ms`/`crowd_ms` in `data/audio.json` and
      by nothing else — a stationary villager chopping is unaffected by how fast she walks.
      Those were retuned in the same session against the real `cooldown_ticks` (a swordsman
      swings once every 2 s and the sound was gated at 90 ms). Kept because the two symptoms
      arrived together and will look related again.

### Input and HUD

- [x] **Double-tap to clear the selection does not work reliably on the phone.**
      Owner-reported 2026-08-23, **answered 2026-08-28 with the [X] button** (PLAN.md 8.8).
      The gesture was never fixed and deliberately still is not — the root is
      `InputRouter`'s tap/pan discrimination, which is its own job. What shipped is a second,
      reliable route to the same verb. **Awaiting the owner's device confirmation.**

      The behaviour is deliberate: single tap on empty ground moves, double tap lets go
      ([game_scene.gd:927](game/src/view/game_scene.gd#L927)). The move goes out on the
      *first* tap, so a double tap moves and then deselects; waiting to see whether a
      second tap is coming would put `DOUBLE_TAP_MS` of lag on every order in the game.

      **`_ground_tap`'s own header predicted this and named the right fix location:** *"the
      fix is `InputRouter.TAP_SLOP` / `TAP_TIME_MS`, which is where the discrimination
      actually belongs — telling a pan from a tap is the router's job."* A thumb wobbles
      where a mouse does not, so a second tap the router scores as a small drag never
      reaches the detector. Desktop was never affected: right-click clears.

      **The owner's interim workaround reveals the shape:** a two-finger box select over
      empty space clears the selection, because a box select has no double-tap timing to
      get wrong.

      **The fix chosen is an [X] button** — top of `SelectionPanel`, hugging the left edge
      below the five control-group icons, visible only while something is selected.
      Clearing is a discoverable action on a touch screen where a gesture is not; it costs
      desktop nothing; and it does not wait on the router improving, which is the real root
      and a separate job. **The gesture stays.** PLAN.md 8.8.

      **What building it actually turned out to be** (2026-08-28): not a UI question, a
      layout one. The HUD's left edge is fully committed — the control-group stack runs to
      y 364 and the selection panel, bottom-anchored and growing upward, tops out at 244 —
      leaving **exactly 40 px** on the 648 px canvas. So `ClearSelectionButton.SIZE` was
      *derived*, not chosen, and there is no headroom left: any extra height above the
      portrait row slides the button under the fifth group slot, which is added to the HUD
      later and so wins the hit test, leaving a strip of the button silently dead. That is
      the minimap's corner-button trap again, and it is asserted in
      `test_the_tallest_panel_still_clears_the_control_group_stack`.

      One press also **exits a placement first**, where right-click takes two. Right-click is
      a general "not that" and resolving one thing per press suits a key that is always
      there; a button marked [X] on a panel is a player saying they are finished with the
      selection, and leaving the villager selected with the ghost gone reads as a half press.

- [ ] **The soft keyboard covers the address field.** A consequence of there finally being
      a keyboard rather than a regression. The game is landscape (`orientation=4`) and a
      landscape Android keyboard takes roughly the bottom two thirds: the field sits at
      y≈340 of 1200 and the keyboard starts at y≈375, so the address is half hidden while
      being typed. Survivable in the throwaway debug screen — you can type blind and check
      afterwards — but **a lobby must not lay out an address field and hope.** Either put
      it in the top third, or shift the layout while the keyboard is open
      (`DisplayServer.virtual_keyboard_get_height()`, with `virtual_keyboard_enter` /
      `virtual_keyboard_exit` on the Window to know when).

- [ ] **A tap cannot place the caret in a text field.** `LineEdit` places its caret from
      `InputEventMouseButton` only, so tapping 90 px into a field puts the caret at column
      0 where clicking the same spot puts it at 11. With the caret pinned at 0, typing into
      a field pre-filled with `127.0.0.1` inserts in FRONT of it — "192" gives
      "192127.0.0.1". `TouchLineEdit` sidesteps it by selecting all on focus, which is
      right for an address field and wrong for one you want to edit in place. Properly
      fixing it means mapping a touch to a caret column by hand, and nothing needs that
      yet.

### Presentation

- [x] ~~**A forfeit is announced as an elimination.**~~ **CLOSED 2026-08-30**, with the
      owner's *"the server does not notify other players"* — the same gap from the other
      end, and the two wanted the same field. This entry had already named the fix
      ("a reason field on `player_state`... resigned, disconnected, wiped out") and that is
      exactly what `SimPlayer.defeat_reason` is. See the 2026-08-30 round above for the
      hazard it left: **the FIRST reason is the true one**, because `WinConditionSystem`
      would otherwise relabel a resignation as an elimination the moment the abandoned base
      fell.

*A second facing entry lived here until 2026-08-29 — "every unit faces the wrong way, and
there is no game-side half" — describing the same defect as the Facing section above from
the 180°-rotation diagnosis that turned out to be wrong. It is deleted rather than closed:
it was one bug reported twice, it is fixed, and the two things worth keeping from it are
already elsewhere. **The owner's rule about patching art defects in the game** is in
`AGENT_GAME_CODER.md`'s gotcha table (`"i dont want to waist any more time on patching a
known root cause"`, built and reverted inside a day, both times on their word). **The
diagnosis lesson** is the standing hazard under the Facing section.*

- [ ] **No wall corner piece**, and 0 A.D. has none either — it puts a `wall_tower` at
      every corner, which is art we already have (`building.guard_tower` is baked from
      exactly those actors). What is missing is anything that *detects* a corner and places
      one; two drags meeting at 90° still overlap or leave a notch. PLAN.md §5.8.

### Environment, not a project bug

- [ ] **This WiFi isolates clients.** Recorded so the next bring-up does not lose an hour:
      the office network put two devices on different /24s with no route between them (100%
      loss). **`adb reverse` is NOT a workaround** — it tunnels TCP and ENet is UDP. What
      worked was putting both devices on the phone's own network.

---

## Open from the AI-vs-AI match run (not owner-reported)

Found by `dev_preview/preview_ai_match.tscn`, forest, 12,000 ticks.

- [ ] **A build step gives up when short of resources. Still the single biggest gap
      between the two AIs.** p2 abandoned its barracks 73 wood short of the 175 it cost,
      never built one, and died holding 950 wood and 1,190 food — p1 won 8,282 to nothing
      largely because p2 never fielded a soldier. A person waits for the wood; the timeout
      should not count affordability.

- [ ] **`MAX_PLACEMENT_RADIUS` 26 → 14 blocks 6×6 placements.** p1 never built its field:
      `no legal 6x6 spot within 14 tiles of (48,23)`. The cut bought the tick budget; it
      needs to buy it some other way.

- [ ] **PARKED — placement can choose ground that seals itself off.** p2's mining camp
      went on ground its builder *could* reach, and the 3×5 footprint then filled the neck
      of the pocket it stood in: thirteen free tiles beside it, all cut off, because the
      only route in ran over the tiles the camp now occupies. The foundation stays at 0%
      forever, and since a foundation keeps its owner in the game (11.1) the match cannot
      be won. **Two fixes were tried and neither worked** — testing the origin tile is
      reachable (it was), then testing for a route to a tile beside the footprint that
      avoids the footprint. Both reverted rather than left unproven in the hot path. Parked
      by the owner 2026-08-20: the AI is good enough, and ranged units will change this
      geometry anyway.

- [ ] **Re-read `AISystem`'s standing order 3.** It exists to paper over `CombatSystem`
      not re-targeting — and `CombatSystem` re-targets now (see the reversal below). Nobody
      has checked what the standing order still needs to do.

**Baseline, so a regression is visible. REPLACED 2026-08-27, and the old one is gone
rather than kept**: it measured two EASY bots against each other under a script that no
longer exists (12.2b), and the owner agreed it is meaningless. Two identical bots could
only ever report that the simulation is symmetric.

**What replaced it is the LADDER** — each difficulty against the one above it, which is
the question `AI_Player_difficulty.md` actually makes a claim about. Run it with:

```
Godot --headless --path game res://dev_preview/preview_ai_match.tscn -- --ticks 20000
```

**A STALEMATE IS A RESULT** (project owner, 2026-08-27): *"the stalemate 1v1 dead lock is
a result in it self, meaning its balancing correctly."* So an UNRESOLVED row is evidence
the two levels are evenly matched, not a bug to chase. What WOULD be a finding is the
lower level winning, or a level that never gets an economy up.

**Seed 3, Forest 96×96, 20,000 ticks (33 min of game time), measured 2026-08-27** with
the army caps, the AoE age costs and the 12.2b rule sets all in:

| rung | outcome | was, before towers shot back | reads as |
|---|---|---|---|
| passive v easy | **easy wins at t8323** (13.9 min) | t8327 | ✅ correct |
| easy v normal | **normal wins at t18351** (30.6 min) | t11366 — **+62%** | ✅ correct |
| normal v hard | **normal wins at t13054** (21.8 min) | t14726 | ❌ **the wrong way round** |
| hard v unfair | stalemate at 20,000 ticks | stalemate | ✅ acceptable — evenly matched |

**RE-MEASURED 2026-08-27 after 4.9 gave buildings an attack**, and the third column is
kept because the shift is the point: `ai_normal`, `ai_hard` and `ai_unfair` all build
watch towers, guard towers or a castle, so **every rung now has to get through one**.
Every winner held and only the durations moved — which is the outcome that says the
feature changed the game without breaking the ladder. `easy v normal` is the one worth
noticing: a timing attack that used to land at t11366 now takes half again as long,
because the thing it is attacking shoots.

The two open items below were written against the OLD numbers and both still hold: the
`normal v hard` inversion is a build-order argument that towers do not settle either way,
and Unfair still fails to beat Hard.

- [ ] **NORMAL BEATS HARD, and the cause is a design tension rather than a bug.** Hard is
      GREEDIER: it waits for 12 villagers, a mill, a barracks and 8 swordsmen before its
      attack rule fires, where Normal pushes on a 7-minute clock with 4. So Normal lands
      a timing attack while Hard is still teching, and Hard dies at age 2 having never
      spent the economy it built — 1,400 stone and 510 gold banked at the end.

      **Both halves of that are working as designed**, which is what makes it a balance
      question rather than a defect: "attacks after eco has been established" is the
      difficulty table's own wording for Hard, and an economy-first build order genuinely
      does lose to a well-timed rush. The levers, in the order I would try them:
      **lower Hard's attack gate** (it is the greediest number in any profile), give Hard
      **towers before its third production building** so it survives the window, or slow
      Normal's clock. All three are balance and belong to the owner.

      Two things this run DID prove: Hard now ages (it was stuck at age 1 for two whole
      runs before the reservation and rule-order fixes), and three of the four rungs
      order correctly.

      **THE OWNER HAS ACCEPTED THIS RUNG AS IT STANDS** (2026-08-27): *"i think if we add
      a human into the mix the normal vs hard will work well."* A bot-versus-bot ladder
      measures build orders against each other, and a human changes what Hard's extra
      economy is worth. So this is parked rather than tuned — do not move the numbers
      above without a reason from PLAY.

- [ ] **UNFAIR IS NOT GOOD ENOUGH YET** — owner, 2026-08-27: *"i am not happy with unfair
      but it needs work so its okay for now."* Accepted for the moment, not settled.

      What it is today: Hard's rule set, plus a head start of 3 villagers and 2 swordsmen,
      plus a zero reaction delay. It stalemated Hard over 20,000 ticks, which is a level
      called *unfair* failing to beat the one below it.

      **The head start is the weakest of its three advantages and the villagers are the
      strongest part of that** — 8 against 5 is a ~60% opening economy lead that compounds,
      where two swordsmen trade once. But the deeper issue is that Unfair plays the same
      GAME as Hard, only slightly richer, and "unfair" ought to mean something a fair
      player cannot do. That is Phase 14 territory (an AI that can see and answer what it
      is fighting) as much as it is a numbers question, which is why it is parked rather
      than dialled up.

**What this replaced, kept in one line because the conclusion outlived the numbers:**
halving unit speed doubled both legs of every gather trip, which cut income roughly in
half and starved a build step that gave up when short of resources — so both bots reached
their attack step with no army and the match ran forever. **12.2b removed the mechanism
entirely.** A rule has no timeout: it waits. The old table's seed-4 tick log is in git if
the failure shape is ever wanted again.

---

## Standing hazards left behind by fixed bugs

Short, and kept because each can bite again.

- ⚠️ **`if Net.host() != null and <the rule>` IS NOT A GUARD — IT IS A RULE THAT IS OFF ON
  EVERY CLIENT.** Three of `GameScene`'s polite refusals were written that way and were
  dead for players 2..8 from the day each was added (owner, 2026-08-30). It survives
  because everything is tested and played solo, where the local player IS the host, so the
  branch that is wrong is the branch nobody takes. **Whatever a client needs to answer, it
  is almost certainly already in `player_state`** — stock, population, age, techs and now
  the defeat reason all ride it every tick. Grep for `Net.host()` before writing another;
  the legitimate uses are the documented solo-only exceptions and tools.
- **A defeat is a STATE, not an event, so anything that reacts to one has to prime.** A
  client joining (or reconnecting into) a match where somebody has already conceded reads
  a first snapshot full of `defeated: true` and would announce every one of them as
  breaking news. `GameScene._announce_defeats` records the opening silently. Same shape as
  `MatchAudio`'s "the first snapshot must be swallowed" and `DamageAlert`'s missing `hp`.
- **`SimPlayer.defeat()` keeps the FIRST reason and later ones are ignored**, because
  `WinConditionSystem` re-tests every player every tick. Set the flag directly and a
  resignation becomes an elimination the moment the abandoned base falls. A two-player
  world cannot catch it — `match_over` latches and the system stops evaluating.
- **A water unit standing on land cannot be ORDERED to do anything, and it reports
  nothing.** `validate()` passes, `PathService` returns an empty route because there is no
  start node for its domain, the task is retired on the first tick, and the log says the
  order was accepted. The debug map has **zero** water tiles, so any fixture involving a
  ship has to paint a channel and then call `PathService.rebuild` — `AStarGrid2D` holds
  solidity IN THE GRID rather than in the query, so terrain written behind its back does
  not exist as far as pathing is concerned.
- **A tree amount is read by tests that are not about trees.** Doubling `res.tree` on
  2026-08-30 broke five: three in `test_gather` (two hardcoded `40`, and a 4,000-tick
  budget that was generous at four round trips and short at eight) and two in
  `test_game_data`. All five now derive from the data. The general form: **a balance number
  written into an assertion is a test that fails when the owner asks for a balance
  change**, and none of the five was making a claim about wood.

- **An empty double-tap on a control-group slot wipes that group.** `CTRL+1`..`5` with
  nothing selected now clears the group deliberately, and mobile's double-tap on a slot
  shares that path. Gate it at the callers if it bites. **Now doubly relevant**, since
  double-tap discrimination is exactly what the open mobile bug is about.
- **A Control laid over the minimap swallows every tap.** The chat/trade/tech-tree/settings
  buttons were a `PRESET_FULL_RECT` grid added *over* it, and Godot hit-tested them first:
  minimap click-to-move and double-tap-to-centre were both dead while looking implemented.
  Check hit-test order before concluding a minimap feature is missing.
- ⚠️ **A CONTROL THAT DRIVES ITSELF FROM MOUSE EVENTS IS INERT ON THE PHONE INSIDE A
  MATCH, and `BaseButton` is the exception that hides it.** `emulate_mouse_from_touch` is
  off for exactly as long as a match lasts (`GameScene` turns it off on entry and hands it
  back in `_exit_tree`), so any control Godot drives from `InputEventMouseButton` /
  `InputEventMouseMotion` alone does nothing under a thumb. **A button answers a raw
  touch**, which is why every HUD control anyone had pressed worked and the three volume
  sliders — the only non-buttons in the game — were dead from the day they landed
  (owner, 2026-08-30). Measured: an `HSlider` at 0.50, tapped at 95% of its track, reads
  0.50 with emulation off and 0.95 with it on. **The fix is a touch-aware subclass
  (`TouchSlider`, `TouchLineEdit`), never the project setting** — a flag toggled per screen
  has to be un-toggled on every path out, and the failure when one path misses it is a
  camera that pans twice for the rest of the match.
- **Touch does not grab keyboard focus in this project, so any new text field needs
  `TouchLineEdit`.** `emulate_mouse_from_touch = false`
  ([project.godot:35](game/project.godot#L35)) is required — `CameraRig` handles both
  `InputEventScreenDrag` and `InputEventMouseMotion`, so a touch arriving as both would pan
  twice per thumb. Godot still routes raw touches to controls, but the touch path does not
  take focus, and `LineEdit` asks for the keyboard on focus-enter. Measured on 4.7.1:
  `focus after a SCREEN TOUCH = false`, `after a MOUSE CLICK = true`. Flipping the project
  setting would fix typing by breaking the camera.
- **`JSON.stringify` encodes a `PackedByteArray` as a *string*** — `"[1, 2, 250]"`,
  verified on 4.7.1. It bit `MapData.from_dict()`, which now reads bytes, JSON's string or
  a plain list. **Relevant to 2.4c's saved sidecar and 12.4's save/load**, which are the
  two places that will next put sim data through JSON. Everything else in that function was
  already defended with `int()` because JSON numbers return as floats; `terrain` was the one
  field that looked like it needed no conversion.
- **You cannot zoom while placing a building.** Edge-pan owns the side strips for the
  duration of a placement and they are the zoom gesture's. Deliberate: zoom is one tap away
  before the menu opens, where reaching an off-screen site was not.
- **`Diplomacy.is_enemy` answers "MAY I attack this", not "am I at WAR with this", and a
  tower needs the second one.** Shipped wrong in 4.9 and found by `preview_garrison`, not by
  60 green tests: a sheep *may* be attacked, because hunting is how a deer becomes food, so
  a watch tower opened fire on the livestock — and a **herded** sheep is still gaia's
  (`herded_by` is separate from `owner_id` by design), so a player's own flock grazing past
  their own tower was shot by it. It presented as something else: nearest-target-wins meant
  every shot went to an animal two tiles away and the raider five tiles out was never
  touched, so the tower read as broken rather than as mis-aimed. `CombatSystem._is_at_war_with`
  is the auto-acquire predicate — enemy players always, gaia only if `aggro_radius > 0`.
  **`AISystem._nearest_enemy` keeps its own copy of this for the identical reason**, and its
  comment says so; anything else that acquires targets *unasked* needs the war question, not
  the permission question.
- **Ejected units come out BEHIND a building**, tower or barracks alike — **and the answer
  is now a RALLY POINT** (owner, 2026-08-27: *"if a way point is set the ejected units will
  queue a walk to destination"*). `find_free_adjacent` sweeps the rect's top edge first, so
  anything leaving a building appears up-screen of it, where the occlusion outline is the
  only thing making it visible. Set a waypoint and they walk out of it; set none and the old
  behaviour stands, which is what the owner asked for. **The underlying sweep order was NOT
  changed** — it affects every building in the game and a rally point makes it opt-out
  per building, which is the cheaper fix by a wide margin.
  Still open and cosmetic: **corpses stack**, because the eject-then-kill path in
  `DeathSystem._kill_garrison` puts every occupant on the same tile and `SeparationSystem`
  does not move the dead. A castle losing 15 reads as one body until they fade. A rally
  point does not help here and must not — the dead are put out so their corpses have
  somewhere to be, not sent anywhere (`ungarrison_unit`'s `send` flag).
- ~~**A rally point has no CLEAR gesture yet.**~~ **CLOSED 2026-08-27, same day it was
  filed** — the owner's answer: *"resuse stop action button to clear waypoint with building
  selected"*. Stop now means two things, chosen by the selection: halt these units, or take
  this building's rally point down. They cannot collide, because `movable_selection()` is
  units-only and `waypoint_target()` demands exactly one building, so at most one is ever
  non-empty. **Reusing the button is what made it affordable** — the castle's action row was
  already sitting on its eighth and last slot, so a ninth verb would have dropped something.
  The hazard that produced instead: **`repair` moved to LAST in a building's row**, so a
  castle with a rally point sheds the disabled placeholder rather than `destroy`. Anything
  added to `SelectionActions._building_actions` from now on drops a real command.
- **Wall-clock timings are worthless on this workstation** — the same seed ran 41.3 s and
  161.0 s, and the test suite swung 34 s to 110 s across four runs of identical code. Trust
  `test_tick_cost`, which reports per-system milliseconds.
- **The test harness has two independent guards and needs both.** A GDScript runtime error
  abandons the rest of a function, so a test that dies part way through looks exactly like
  one that passed — found in `test_the_wire_form_survives_json_the_way_a_packet_would`,
  which printed three SCRIPT ERRORs and reported PASS. Fixed by keying on the error *type*
  (`ERROR_TYPE_SCRIPT` aborts a test and no test ever wants one; the `ERROR`s and
  `WARNING`s this suite makes on purpose are left alone), alongside the pre-existing
  zero-assertion floor. The spy catches a test that dies; the floor catches one that
  asserts nothing. Neither sees the other's case.

## Reversed decisions

- **`CombatSystem` re-targets when its target dies** — 5×5 box, units before buildings,
  ties by distance then lowest id, gaia excluded. **This reversed a documented decision:**
  PLAN.md 4.13 had it explicitly *not* re-target, and that reasoning still holds for
  *acquiring* a fight from idle, which is why the radius stayed at 2 while
  `SAME_WORK_RADIUS` went to 10. See the open AI item about standing order 3.
