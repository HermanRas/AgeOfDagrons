# BUGS.md

Playtest findings from the project owner, newest batch first. One line per item,
struck through when fixed with the commit that did it.

An item here is the owner's word on the behaviour they want — where that reverses
an earlier deliberate decision, the reversal is noted rather than argued.

---

## 2026-08-20 — first AI playtest

The AI gathered, built and raised a house, a tower and several other buildings.
These are what the owner saw while watching it.

### View / rendering

- [x] **Villagers face the wrong way when idle-walking north-east.** The sim's
      `facing` is a maths octant in tile space (0 = +x, anticlockwise);
      `AtlasEntry.FACINGS` is a sprite table starting at S and running the other
      way. `GameView` passed the sim's number straight in, drawing the mirror of
      the right sprite — 45° out walking south, **135° out walking north-east**,
      which is why NE is what got noticed. Both ends were pinned by their own
      tests; nothing tested that they agreed. Fixed with `Iso.sim_facing_to_sprite`
      plus a test that walks all eight directions through both conventions.
- [x] **Villagers randomly teleport from the outer edges of the screen.** A unit
      stepping into the sort band in front of a building gains
      `_ADJACENT_TO_BUILDING_BONUS` (100,000 px) on the position it *sorts* at,
      and `draw_offset` cancels it — but the position is interpolated and the
      offset is not, so for one window they did not cancel. Measured by the new
      test: drawn at y = **−99,520** where it should be y = 384. Fixed by snapping
      instead of gliding on the tick the offset changes.

### Input / HUD

- [x] **`CTRL+1`..`5` with nothing selected does not clear the group.** It was
      refused in two places, both deliberately. Now clears. **Watch for:** the
      same path serves mobile's double-tap on a group slot, so an accidental
      empty double-tap now wipes a group. Gate it at the callers if that bites.
- [x] **Clicking the minimap does not move the camera.** It was implemented all
      along — the placeholder chat/trade/tech-tree/settings buttons are a
      `PRESET_FULL_RECT` grid added *over* the minimap, so Godot hit-tested them
      first and they swallowed every tap. Double-tap-to-centre was dead too.
- [x] **Tapping the minimap with units selected issues a move command** (PLAN.md
      3.7). Selection decides: something movable selected → order; nothing
      selected → camera. The camera deliberately does not follow the order.

### Simulation

- [x] **A villager killed in mid-stride kept walking to its destination.** Death
      marked the unit but never cancelled the ORDER, and `MovementSystem` drives
      anything with a waypoint left — it did not ask whether the walker was alive,
      where combat, animation and separation all do. Measured by the new test:
      the corpse covered ~10 tiles after dying. Fixed at the root (`DeathSystem`
      calls `stop()` on a fresh death) plus an `alive` guard in `MovementSystem`,
      which is needed because Movement runs at slot 9, between the kill at 6 and
      the cleanup at 12. The same leftover task would have had a corpse gathering
      and building, so `GatherSystem`, `BuildSystem` and `TaskSystem` got the
      guard too — a unit destroyed by a *command* is already dead when those run.
- [x] **A unit whose target dies re-targets**: 5×5 box, units before buildings,
      ties by distance then lowest id. Gaia excluded.
      **Note:** this reverses a deliberate decision — PLAN.md 4.12 had
      `CombatSystem` explicitly *not* re-target, and `AISystem`'s standing order 3
      exists to paper over it for the AI. That standing order should be re-read
      now to see what it still needs to do.

---

## 2026-08-21 — two-device bring-up (PLAN.md 12.1g)

Phone hosting as player 1, laptop joining as player 2, over real WiFi on the same
subnet. **All six checks passed**, including both view fixes from the batch above,
which had never been seen on a device. The owner's words on the transport: "it
plays very well, its snappy and responsive, even clicking on one device and
watching the other seems instant."

That is step (f)'s risk measured rather than assumed — one snapshot is 12,092
bytes, which exceeds ENet's MTU and fragments, and snapshots are
`unreliable_ordered`. At this entity count it is not hurting. It still wants
re-checking at a bigger army, which is what (f) is for.

Confirmed on device: client→host commands both ways; ownership refusal (player 2
cannot select or move player 1's units); the advisory placement ghost; fog of war
per unit per player; villagers facing correctly walking north-east; no teleport
crossing in front of a building.

- [x] **No way to cancel a building placement on a touch screen.** Entering build
      mode LOCKS THE CAMERA on purpose, so one finger can drag the ghost rather
      than pan — and the only ways out were Escape and right-click, neither of
      which a phone has. With no legal spot on screen and no way to pan to one, a
      placement could be neither finished nor abandoned: the ghost stayed stuck to
      the owner's thumb for the rest of the match. The Cancel Build button that
      used to do this "went away with the dev row". Restored, visible only while
      placing. **Its first position was wrong too** — bottom centre looked empty
      and is exactly where the build grid opens, so it covered the menu it belongs
      to; caught by `preview_match`'s screenshot rather than by the code.
      **Confirmed fixed on the device by the owner 2026-08-21**, in the same
      two-device match that validated the lobby.
- [x] **A LineEdit gets no soft keyboard on Android.** Tapping the address field in
      the debug screen raises no keyboard, by hand or via `adb input text`, so an
      address cannot be typed on the phone at all. Worked around for the bring-up
      by having the phone HOST and the laptop join (the laptop takes `--net join
      --ip` from a terminal). **This blocks 12.1c**, whose lobby needs an address
      field, and wants sorting before that screen is built.

      **Root cause found, and it is ours, not Android's.** This project sets
      `input_devices/pointing/emulate_mouse_from_touch = false`
      ([project.godot:35](game/project.godot#L35)) — it has to, because `CameraRig`
      handles both `InputEventScreenDrag` and `InputEventMouseMotion`, so a touch
      arriving as both would pan two thumbs' worth per thumb. Godot's GUI does still
      route raw touches to controls: a Button reacts to one, and a LineEdit's
      `gui_input` sees them. What the touch path does not do is grab keyboard
      **focus**, and LineEdit asks for the keyboard on focus-enter. Measured on
      4.7.1 with an identical field:

          focus after a SCREEN TOUCH = false
          focus after a MOUSE CLICK  = true

      Fixed by [`TouchLineEdit`](game/src/view/touch_line_edit.gd), which grabs focus
      from the touch itself. Flipping the project setting instead was rejected: it
      would fix typing by breaking the camera. **Confirmed on the device 2026-08-21**
      — the owner reports the keyboard comes up on a tap, and `adb shell input text
      "192.168.4.77"` now lands in the field, replacing the selected `127.0.0.1`
      rather than prepending to it. Scripted device input works again too, which it
      did not before.
- [ ] **The soft keyboard covers the address field.** Seen in the screenshot that
      confirmed the fix above, so it is a consequence of there finally BEING a
      keyboard rather than a regression. The game is landscape (`orientation=4`), and
      a landscape Android keyboard takes roughly the bottom two thirds: the field sits
      at y≈340 of 1200 and the keyboard starts at y≈375, so the address is half
      hidden while it is being typed. Survivable in the throwaway debug screen — you
      can type blind and check afterwards — but **12.1c's lobby must not lay out an
      address field and hope.** Either put it in the top third, or shift the layout up
      while the keyboard is open (`DisplayServer.virtual_keyboard_get_height()`, and
      `virtual_keyboard_enter`/`virtual_keyboard_exit` on the Window to know when).
- [ ] **A tap cannot place the caret in a text field.** The same gap one layer down,
      found while fixing the one above: LineEdit places its caret from
      `InputEventMouseButton` only, so tapping 90 px into a field puts the caret at
      column 0 where clicking the same spot puts it at column 11. With the caret
      pinned at 0, typing into a field pre-filled with `127.0.0.1` inserts in FRONT
      of it — "192" gives "192127.0.0.1". `TouchLineEdit` sidesteps it by selecting
      all on focus, so the first keystroke replaces the lot, which is the right
      behaviour for an address field and wrong for a field you want to edit in
      place. Properly fixing it means mapping a touch to a caret column by hand, and
      nothing needs that yet.
- [ ] **Every unit feels too fast.** Owner-reported 2026-08-21, from a real
      two-device match played for several minutes on a phone. **Parked
      deliberately** — this is a balancing number, not a defect, and it wants
      doing as one pass over every unit's `speed` in the data rather than a nudge
      to whichever unit was on screen. Recorded now so the observation survives
      until that pass; nothing here should be tuned piecemeal before it.
- [x] **Panning while placing.** Cancel removed the dead end, but the workflow was
      still cancel → pan → re-open the menu. **Owner chose edge-pan** over
      two-finger pan (which is box-select's own trigger, 8.3). Dragging the ghost
      into the 100-unit edge strip now slides the map under it, ramped by how deep
      into the strip the finger is, and the ghost is re-read each time the ground
      moves beneath it. Two guards worth knowing about: the strip cannot push until
      the finger has been seen OUTSIDE it once during the drag — the build grid
      opens along the bottom edge, so the tap that picks a building leaves your
      finger exactly there — and a camera parked against the map's clamp reports no
      movement, so a resting thumb does not re-preview the placement every frame.
      The cost is that you cannot zoom while placing: the side strips are the zoom
      gesture's, and placement owns them for the duration. Zoom is one tap away
      before the menu opens; reaching an off-screen site was not.
- [x] **A test that errors out mid-body still counts as PASS.** Found while running
      the suite for the edge-pan work, and it is the more serious of the two things
      here. `test_the_wire_form_survives_json_the_way_a_packet_would` prints three
      SCRIPT ERRORs and is reported as passed: a GDScript runtime error abandons the
      rest of the function, so its last three assertions never ran and their absence
      looks identical to success. Every test in the suite has this property.

      **Fixed by keying on the error TYPE rather than on the test.** The owner asked
      whether the two candidate checks could be combined — fail-on-logged-error for
      most tests, the assertion floor for the ones that log errors deliberately. They
      can, but the second tier turns out to be unnecessary: `OS.add_logger` takes a
      scriptable `Logger`, and `_log_error` carries an `error_type`. Script errors
      (`ERROR_TYPE_SCRIPT`) are the ones that abort a test, and no test ever wants
      one; the noise this suite makes on purpose is `ERROR`s and `WARNING`s — the net
      tests provoking a vanished peer, the occlusion tests making the shader compiler
      grumble. So the category separates the two cleanly and no test has to declare
      anything. The zero-assertion floor (already there since 0.2b) is kept alongside
      it: it catches a test that asserts nothing, the spy catches one that dies part
      way through, and neither sees the other's case. Switched on, it found exactly
      one bad test in 889.
- [x] **`MapData.from_dict()` cannot read its own JSON.** What the vacuous test above
      was written to catch. `JSON.stringify` encodes a `PackedByteArray` as a
      *string* — `"[1, 2, 250]"`, verified on 4.7.1 — so `terrain` returns as a
      String, the assignment on `map_data.gd:183` errors, and `from_dict` returns
      null. Notable that every other field there was already defended against JSON,
      with `int()` around each one because JSON numbers come back as floats; terrain
      was the one field that looked like it needed no conversion. **The two-device
      match is not affected** and that is why (g) passed: ENet hands the config across
      as a Dictionary using Godot's own binary serialization, where a
      `PackedByteArray` survives intact. Replays are unaffected too — they carry only
      `player_ids` and `commands`, not a map. It would have bitten the saved sidecar
      (2.4c) and 12.4's save/load. `from_dict` now reads bytes, JSON's string, or a
      plain list; `to_dict` goes on sending raw bytes, because base64 would add a
      third to 20–40 KB of terrain and 12.1f is about wire size.
- [ ] **A forfeit is announced as an elimination.** Seen while proving 12.1e: the
      joiner's process was killed mid-match and the host's screen read **"All
      opponents eliminated"**. Nobody was eliminated — they left. Same wording for a
      resign. It is the existing message for "match over and you won", and the
      snapshot carries no reason for a defeat, only the fact of one, so telling a
      forfeit from a conquest needs a reason field on `player_state` (or beside
      `winner_id`) and a decision about how many reasons are worth naming —
      resigned, disconnected, wiped out. Cosmetic, but it tells the winner something
      untrue about how they won.
- [x] **Snapshots are four times the MTU and sent unreliably.** 12.1f, with a number on
      it at last. **The fog half is fixed** (2026-08-21): the grid is no longer sent at
      all — `ClientFog` computes it from the client's own entities and the map it already
      has, which took the 8-player board from 53,928 bytes to 17,040 and 39 fragments to
      13. Snapshot size no longer depends on the board. See PLAN.md §12.1f for the option
      that was not taken and the drawback of the one that was.

      **The entity payload is fixed too, and not by delta encoding.** Only 36 entities
      are visible on the 8-player board and they cost 16 KB — ~445 bytes each — because
      half of every entry was the names of its own fields. `footprint` is no longer sent
      (the client derives it from `def_id`), `pos` is a `Vector2i` rather than a
      two-key dictionary, and entries are packed into per-shape tables so field names go
      once per snapshot instead of once per entity. **53,928 → 6,824 bytes, 39 fragments
      → 5**; ENet's live warning went from 18,532 to 4,360.

      **Measured on real WiFi and closed.** Phone joined to a PC host, ~90 s of play:
      **3.4% of snapshots lost, every loss a single one** — never a run. One 100 ms frame
      of stale state, self-healing because a full snapshot needs nothing from its
      predecessor, and invisible under interpolation. `unreliable_ordered` STAYS, now as
      a decision: `reliable_ordered` would trade invisible gaps for head-of-line
      blocking, and a retransmitted snapshot is worthless by the time it lands because a
      newer one has already been sent. The measured per-fragment loss is ~0.7%, which is
      why the fragment count mattered so much — at this morning's 39 fragments the same
      link would have dropped ~24% of snapshots. ENet says so itself, on the host, during an ordinary two-process match:

          WARNING: Sending 18532 bytes unreliably which is above the MTU (1392),
                   this will result in higher packet loss
             at: put_packet (enet_multiplayer_peer.cpp:365)
             [0] _broadcast_snapshot (net.gd:451)

      **18.5 KB per snapshot against a 1392-byte MTU** — about fourteen fragments, and
      losing any one of them loses the whole snapshot, because `_recv_snapshot` is
      `unreliable_ordered`. This was a 96×96 generated map with 105 entities, and it
      scales with entity count, so a real army makes it worse rather than better.
      **Invisible on loopback**, which is exactly why it wanted measuring: the PC-to-PC
      run it came from looked perfect. The owner's "snappy" verdict from (g) was on
      ~12 KB over real WiFi, so the fear is not disproved, just not yet reproduced —
      what is now known is the size, the call site, and that the transport is already
      complaining before anybody has stress-tested it.
- [ ] **This WiFi isolates clients.** Not a project bug, recorded so the next
      bring-up does not lose time: the office network put the two devices on
      different /24s with no route between them (100% packet loss). `adb reverse`
      is NOT a workaround — it tunnels TCP and ENet is UDP. What worked was
      putting both devices on the phone's own network.

---

## 2026-08-22 — walls, facing and the lobby

- [x] **Every unit faces the wrong way, and it is not just the units.** Reported as
      "the attack animation faces away from the thing they are attacking"; combat is
      only where it is *visible*. The cause is in the recipes, not the game —
      isobake's zeroad adapter turns every subject 180° from the direction the atlas
      labels it, and 81 of 171 recipes cancel it with `yaw_offset_deg = 180.0`.
      **The owner declined the re-bake for now** ("no to the rebake of the entire
      asset suite and all recipes, can we fix it in code, and add it as a polish item
      at the end, before investing 3 days of baking time") — they are getting a
      faster machine for it. So the game compensates: `"directions_reversed": true`
      on 31 `visuals.json` entries adds half a turn (`AtlasEntry.facing_offset`).
      Covers units, ships, siege, animals and the wall foundations and rubble, all of
      which had the same hole. **The flags must come off per entry as the art is
      re-baked** — PLAN.md §13.2 item 10, contract in `asset_request.md`.
- [x] **Short wall pieces should merge into longer ones** (the owner's design, and it
      wins on its own terms: fewer entities, seams and vision circles). Built as
      `WallMerge`, with the owner's amendment that **only complete pieces merge** —
      otherwise a merge eats a foundation out from under its builder. Health is the
      exact sum, the merge is silent and free, and a merged long can then be upgraded
      to a gate, which is how a wall built in short pieces gets a door at all.
- [x] **The lobby preview should be rotated to match the in-game minimap.** It was a
      square with north-west top-left; the match opens on `Iso`'s projection with tile
      (0, 0) at the top, so the layout a player picked a start position on arrived
      turned 45°. Turned in the pixels (`MapPreview.to_diamond`) rather than by
      rotating the Control, which a `VBoxContainer` lays out by its unrotated rect.
      The dev tool's PNG stays square deliberately.
- [ ] **No wall corner piece**, and 0 A.D. has none either — it puts a `wall_tower` at
      every corner, which is art we already have (`building.guard_tower` is baked from
      exactly those actors). What is missing is anything that *detects* a corner and
      places one there; two drags meeting at 90° still overlap or leave a notch.

---

## Open from the AI-vs-AI match run (not owner-reported)

Found by `dev_preview/preview_ai_match.tscn` on seed 3, forest, 12,000 ticks.
See the run log in that scene's output for the exact lines.

- [x] **The preview never quit** — `_ready()` returned into an idle headless main
      loop that Godot spins at max FPS, so the process kept burning a core long
      after printing its report. Fixed with `get_tree().quit()`.
- [x] **"could not be issued" named six different failures with one word.** The AI
      now records *why* each step failed, and every log line carries its tick.
- [ ] **`MAX_PLACEMENT_RADIUS` 26 → 14 blocks 6×6 placements.** p1 never built its
      field: `no legal 6x6 spot within 14 tiles of (48,23)`. The cut bought the
      tick budget; it needs to buy it some other way.
- [ ] **A build step gives up when short of resources.** p2 abandoned its barracks
      73 wood short of the 175 it cost, never built one, and died holding 950 wood
      and 1,190 food. A person waits for the wood; the timeout should not count
      affordability. **This is now the single biggest thing between the two AIs** —
      p1 won 8,282 to nothing largely because p2 never fielded a soldier.

- [x] **An army would not attack anything but a building, even one it could not
      reach.** `_nearest_enemy` ended `return best_building if best_building != 0
      else best_any` — buildings preferred unconditionally. On seed 6 p2 was down
      to one mining camp no route reached, with six of its villagers standing 11
      steps away: p1's six soldiers were sent at the camp, `_close_in` got an
      empty path, `set_path([])` retired them, and the standing order re-sent them
      five ticks later. **Six soldiers idled beside a beaten opponent for 24,000
      ticks.** Targets are now ranked buildings-first, then nearest, then lowest
      id, and the first *reachable* one wins (capped at `REACH_PROBES` path
      solves). Seed 6 now wipes out every p2 unit by t6001 instead of standing
      still. Tick cost unaffected: 1.32 ms/tick with two AIs, `ai_system` 0.40 ms.

- [ ] **PARKED: placement can choose ground that seals itself off.** p2's mining
      camp was placed on ground its builder *could* reach, and the 3×5 footprint
      then filled the neck of the pocket it stood in — thirteen free tiles left
      beside it, all now cut off, because the only route in ran over the tiles the
      camp was sitting on. The foundation stays at 0% forever, and since a
      foundation keeps its owner in the game (11.1) the match cannot be won: seed 6
      still ends UNRESOLVED with p2 at zero units and one phantom foundation.
      Two fixes were tried and **neither worked** — testing that the origin tile is
      reachable (it was), then testing for a route to a tile beside the footprint
      that avoids the footprint. Both were reverted rather than left in the hot
      path unproven. Parked by the project owner 2026-08-20: the AI is good enough,
      and ranged units will change this geometry anyway.
- [x] **A placed foundation can sit at 0% forever** — and it was neither suspect.
      **Units are entombed by their own foundations.** `can_place_building()` asks
      the MAP whether the footprint is free, and units are not written into map
      occupancy, so a building goes up on top of them. `AStarGrid2D` will no more
      plan a route *out of* a solid cell than into one, so every path the unit
      asked for came back empty, `set_path([])` retired the task, and it stood
      there for the rest of the match. The diagnostic read
      `barracks at (49,25), 0 builder(s), NO ROUTE from (49,27)` — a tile squarely
      inside the 6×6. **Not an AI bug:** a player who drops a house on their own
      villagers seals them in exactly the same way. Fixed by stepping units aside
      in `SimWorld.spawn_building`, and it took two more fixes to land:
      - **`find_path()` conflated "nowhere to go" with "you are already there",**
        both returning an empty array that `set_path()` turns into `stop()` — so
        a unit standing on the tile its new order wanted was retired instead of
        getting on with the job. Its own header said empty meant the former.
        Split with `goal_for()` + `SimUnit.arrive()`.
      - **The first eviction invented a worse bug.** `find_free_adjacent` sweeps
        the rect's *top edge* first (it answers a different question — where to
        put a freshly trained unit), so a villager at a house's bottom-right
        corner was thrown clear across to the top-left, onto a tile that was
        passable but walled in by forest. It could never path again: 196 empty
        route requests in 1,000 ticks were all that one villager. Replaced with
        `_step_aside_tile`, nearest to where the unit already stood — which is
        connected to the map for the simplest reason, it just walked there.

**Result: the AI-vs-AI match reaches a conclusion.** Forest, 12,000 ticks:

| seed | outcome |
|---|---|
| 3 | MATCH OVER t8282, winner p1 |
| 4 | MATCH OVER t7776, winner **p2** |
| 5 | MATCH OVER t8763, winner p1 |
| 6 | UNRESOLVED — p2 reduced to 0 units and one unreachable foundation (parked, above) |

Three in four resolve, and both sides win across the set, so the result is not an
artefact of the script favouring player 1. Seed 6 is a known, understood
limitation rather than a hang: the match is decided in every practical sense and
only the win condition cannot fire.
- [x] **Match wall-clock varies 4×** (41.3 s vs 161.0 s for the same seed). Not a
      regression: the test suite swung the same way on the same machine (34 s to
      110 s across four runs of identical code), so it is load on the workstation,
      not the sim. `test_tick_cost` is the number to trust — it reports 6.44
      ms/tick for a 2-player map with two AIs, of which `ai_system` is 2.15 ms.
