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

- [ ] **Double-tap to clear the selection does not work reliably on the phone.**
      Owner-reported 2026-08-23. Documented and **not** to be fixed as-is — the call is to
      replace the gesture with a button rather than keep tuning it.

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

- [ ] **A forfeit is announced as an elimination.** The joiner's process was killed
      mid-match and the host read **"All opponents eliminated"**. Nobody was eliminated —
      they left, and a resign says the same thing. It is the existing "match over and you
      won" message, and the snapshot carries no *reason* for a defeat, only the fact of
      one. Telling a forfeit from a conquest needs a reason field on `player_state` (or
      beside `winner_id`) and a decision about how many reasons are worth naming: resigned,
      disconnected, wiped out. Cosmetic, but it tells the winner something untrue about how
      they won.

- [ ] **Every unit faces the wrong way — art side, and there is no game-side half.**
      isobake's zeroad adapter turns every subject 180° from the direction the atlas labels
      it; 81 of 171 recipes cancel it and the rest do not. **A game-side compensation was
      built and reverted inside a day, on the owner's word both times** — the second time
      with a screenshot: *"undo the reverse changes… i dont want to waist any more time on
      patching a known root cause."* Nothing in `game/` compensates, so nothing has to be
      un-applied when the bakes land.

      Kept because it makes the recipe fix a one-liner: the `unit.knight` chart is 180° out
      **uniformly across idle, walk and attack**, so rider and horse turn together and no
      clip needs its own treatment. The sim is not implicated — `CombatSystem` sets `facing`
      toward the target on every swing. Full request and the 36-recipe list are
      `asset_request.md` [P2]; tracked as PLAN.md §13.2 item 10.

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

**Baseline, so a regression is visible.** Forest, 12,000 ticks. **Re-measured 2026-08-23
after every unit speed was halved** (see the balance item at the top — that was the owner's
call and this is what it cost):

| seed | outcome | before the halving |
|---|---|---|
| 3 | MATCH OVER t8806, winner p1 | t8282, p1 |
| 4 | **UNRESOLVED** | t7776, **p2** |
| 5 | MATCH OVER t9470, winner p1 | t8763, p1 |
| 6 | UNRESOLVED — p2 at 0 units and one unreachable foundation (parked, above) | UNRESOLVED |

- [ ] **Halving unit speed cost the baseline its best property, and the cause is the
      already-open "gives up when short of resources" bug, amplified.** Two in four resolve
      now rather than three, and — the part that matters — **seed 4 was the only seed p2
      ever won**, which is what made the set evidence that the result is not an artefact of
      the script favouring player 1. That evidence is gone.

      **Not a window problem: seed 4 does not resolve at 20,000 ticks either**, so it is
      not a match that merely fell just outside the cut. What happens is on the record:

      ```
      t2445  p2 step 14 -- cannot place barracks: cost 175 wood vs stock 74 wood
      t2450  p2 step 15: gather wood x1
      t3430  p2 step 16 -- no building.barracks standing
      t3435  p2 step 17: attack                     <- attacks with nothing
      t2736  p1 step 15 timed out
      t3640  p1 step 16 -- building.barracks is still a foundation (0% built)
      t3645  p1 step 17: attack                     <- also attacks with nothing
      ```

      Both sides reach the attack step with no army, and neither can kill the other, so it
      runs forever. That is **exactly the open item above** — a build step that gives up
      when short of resources — now hitting BOTH players instead of one.

      **Why halving speed did this, and it is worth understanding before tuning further:**
      a gather trip is walk-out, extract, walk-home, deposit, and halving speed doubles both
      walks. Resource income is therefore closer to HALVED than unaffected, and the further
      the node the worse it is. Meanwhile every AI step timeout is still the number it was.
      So the speed change did not just make units slower to watch — it cut the economy, and
      the AI's timeouts are now far too tight for the world they run in. Fixing the
      affordability timeout is the first thing to try; re-tuning `gather_rate` upward to
      compensate is the other lever, and that one is the owner's call.

---

## Standing hazards left behind by fixed bugs

Short, and kept because each can bite again.

- **An empty double-tap on a control-group slot wipes that group.** `CTRL+1`..`5` with
  nothing selected now clears the group deliberately, and mobile's double-tap on a slot
  shares that path. Gate it at the callers if it bites. **Now doubly relevant**, since
  double-tap discrimination is exactly what the open mobile bug is about.
- **A Control laid over the minimap swallows every tap.** The chat/trade/tech-tree/settings
  buttons were a `PRESET_FULL_RECT` grid added *over* it, and Godot hit-tested them first:
  minimap click-to-move and double-tap-to-centre were both dead while looking implemented.
  Check hit-test order before concluding a minimap feature is missing.
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
