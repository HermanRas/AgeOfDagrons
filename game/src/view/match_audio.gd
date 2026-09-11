## Turns snapshots into sound (PLAN.md 7.5). The view-side half of the audio
## seam: `AudioManager` knows how to play a sound id, `audio_map.json` knows which
## id an entity uses, and this decides WHEN.
##
## WHY THE SIM DOES NOT DO THIS, which is the whole reason the class exists.
## `src/sim/` may not load an asset or touch the tree (PLAN.md 4,
## `tests/sim/test_sim_boundary.gd` greps for it), so it cannot call
## `AudioManager` -- and it should not want to: a sim that made noise would make
## it during a headless AI-vs-AI run and during the host's simulation of a client
## it is not rendering. The sim reports facts; this listens.
##
## SO IT DIFFS CONSECUTIVE SNAPSHOTS. A snapshot is a full statement of what a
## player may see (`SnapshotSystem`), not a delta, so "a building finished" is not
## a message that arrives -- it is `phase` having been UNDER_CONSTRUCTION last
## tick and COMPLETE this one. Every event below is a transition of that shape,
## which has one large advantage over the sim emitting events: it works
## identically on the host and on a joined client, because both receive the same
## snapshots and neither has to have the event forwarded.
##
## THREE CONSEQUENCES OF DIFFING, all of them handled here and none obvious:
##
## 1. **The first snapshot must be swallowed.** Every entity in it is "new", so a
##    match would open with two hundred trained-unit reports. `_primed` does that.
##
## 2. **Absence is ambiguous.** An entity missing from `updated` may have died, or
##    may merely have walked into the fog -- `GameView` has the same problem and
##    the same answer. So a death is only ever read from an entry that is PRESENT
##    and says `alive: false`; a vanished id is forgotten silently. A unit killed
##    out of sight makes no sound, which is correct.
##
## 3. **A remembered entity carries no live fields.** `_remembered()` strips `hp`,
##    `anim`, `phase`'s siblings and more, so every read here uses the previous
##    value as its default and a remembered building cannot fake a completion.
##
## Sounds a PLAYER causes -- a button, a refused order -- are NOT here. Those fire
## at the call site in `GameScene`, where the cause is known; routing them through
## a snapshot diff would be a worse answer arriving a tick later.
class_name MatchAudio
extends RefCounted

## `SimBuilding.Phase`, mirrored rather than imported. The view may name sim
## classes (the boundary rule is one-directional), but `phase` arrives off the
## wire as a plain int and comparing against a named constant here is what makes
## the transition below readable.
const _PHASE_COMPLETE := 2

## Per-entity state carried between snapshots. Only the fields a transition
## needs -- keeping whole entries would be a second copy of the world.
var _prev: Dictionary = {}          # id -> Dictionary
var _prev_age: Dictionary = {}      # player_id -> int
var _primed := false
var _announced_result := false

## HOW LONG A HOLDER MUST HOLD BEFORE IT IS ANNOUNCED, in snapshots (PLAN.md 11.2,
## `11.x-koth-control-sound`). The owner's ask carried its own warning -- *"short subtile
## sound, it will play often"* -- and the rule built under it is worse than that warning
## knew: **a tie has no UNIQUE leader**, so `koth_holder` drops to 0 the instant a fight is even
## and returns the instant one side is one unit ahead. A real 5-v-5 on the hill is therefore
## `1 -> 0 -> 1 -> 0` several times a second, not `1 -> 2 -> 1`.
##
## 📝 **THIS SAID "a tie pays NOBODY" UNTIL THE LADDER FIX LATER THE SAME DAY, AND THE FLICKER IS
## UNCHANGED.** Under PLAN.md §11.9 a tie pays everybody present 1 — but `koth_holder` names the
## unique leader either way, so every word about the cadence below still holds. The old phrasing
## is corrected rather than dropped because it is the reasoning a reader would otherwise re-derive
## from a rule the game no longer has.
##
## ⚠️ **AN INTERVAL ALONE DOES NOT FIX THAT, WHICH IS WHY THERE ARE TWO GUARDS.** Throttling
## turns a machine gun into a metronome: still a sound every few seconds, still saying
## nothing, and still fired during the exact moment the player is busiest. The card's word
## for the second guard is hysteresis, and this is its cheapest honest form -- a value has to
## SURVIVE to count, so a flickering hill announces nothing at all and a hill somebody
## actually took announces once.
##
## 📝 **IT IS A DWELL RATHER THAN A LEAD MARGIN, AND THAT IS FORCED BY THE WIRE.** The card
## asks for hysteresis "about the LEAD, not about the holder id" -- correct, and the lead is
## not on the snapshot: `koth_holder` is one int and deriving a margin here would mean
## counting units in the zone, which is the client-side counting `GameView.koth_holder`'s own
## header forbids (half a contested zone is in fog). A dwell buys the same property off the
## field we are actually sent: an oscillating lead cannot hold a value still.
const _KOTH_DWELL_TICKS := 12

## The last holder we ANNOUNCED, the candidate currently under observation, and how many
## consecutive snapshots that candidate has survived. `-1` means nothing has been announced
## yet, which is distinct from 0 -- see `_koth_transitions`.
var _koth_announced := -1
var _koth_candidate := -1
var _koth_dwell := 0

## Everything a villager could be working, rebuilt each snapshot: resource nodes
## and buildings, as {tile, def_id}. See `_work_sound` for why this exists rather
## than the unit naming its own target.
var _work_candidates: Array = []

## Set false by the test suite and the AI-vs-AI preview: they step thousands of
## ticks with nobody listening, and a real match's worth of sound is pure cost.
var enabled := true

## WHERE SOUNDS GO. Null means the `AudioManager` autoload, which is what the
## game uses; the test suite substitutes a spy that records what was asked for.
##
## Injected rather than the test swapping the autoload out from under the tree.
## An autoload is reached through a global identifier, so faking it means
## renaming and reparenting a live singleton the rest of the project is holding
## -- which works until something else in the same run resolves it, and then
## fails in a way that has nothing to do with the test that broke it.
var sink: Object = null


func _out() -> Object:
	return sink if sink != null else AudioManager


## Feed one snapshot. `listener` is the camera's centre in world pixels, used to
## cull distant sounds; pass `Vector2.INF` to hear everything regardless.
func observe(snap: Dictionary, local_player_id: int, listener: Vector2 = Vector2.INF) -> void:
	if not enabled:
		return

	# TWO PASSES, because `_work_sound` needs every candidate target before it can
	# say what any worker is doing, and `updated` is in no useful order.
	_work_candidates.clear()
	for e in snap.get("updated", []):
		var entry: Dictionary = e
		# A resource node carries `amount`; a building carries `phase`. Both are
		# things a villager works, and a unit carries neither.
		if entry.has("amount") or entry.has("phase"):
			_work_candidates.append({
				"tile": _tile_of(entry.get("pos", Vector2i.ZERO)),
				"def_id": StringName(entry.get("def_id", &"")),
			})

	var seen: Dictionary = {}
	for e in snap.get("updated", []):
		var entry: Dictionary = e
		var id := int(entry.get("id", 0))
		if id == 0:
			continue
		seen[id] = true
		var was: Dictionary = _prev.get(id, {})
		if not was.is_empty():
			_transitions(entry, was, local_player_id, listener)
		elif _primed:
			_appeared(entry, local_player_id)
		_prev[id] = _keep(entry, was)

	# Forget anything not in this snapshot. It may be dead or merely out of
	# vision and the snapshot cannot tell us which (see the header); dropping the
	# memory means it will be treated as newly appeared if it comes back, which
	# is why `_appeared` only reports units the local player OWNS -- an enemy
	# army walking in and out of vision would otherwise announce itself.
	for id in _prev.keys():
		if not seen.has(id):
			_prev.erase(id)

	_player_transitions(snap, local_player_id)
	_koth_transitions(snap)
	_primed = true


## Reset between matches. A `MatchAudio` outliving its match would compare the
## new world's entity 1 against the old one's.
func reset() -> void:
	_prev.clear()
	_prev_age.clear()
	_work_candidates.clear()
	_primed = false
	_announced_result = false
	# A carried-over holder would announce the new match's first hill as a THEFT from
	# whoever held the old one's -- and `-1` rather than `0` because `0` is a real state
	# the wire sends (nobody, or contested) and would swallow the first genuine capture.
	_koth_announced = -1
	_koth_candidate = -1
	_koth_dwell = 0


# ── per-entity ──────────────────────────────────────────────────────────────

func _transitions(now: Dictionary, was: Dictionary, me: int, listener: Vector2) -> void:
	var def_id := StringName(now.get("def_id", was.get("def_id", &"")))
	var at := Iso.sub_to_world(now.get("pos", Vector2i.ZERO))

	# ── death ───────────────────────────────────────────────────────────────
	# `alive` defaults to the previous value, so a remembered entry -- which does
	# not carry it -- cannot read as a death.
	var alive := bool(now.get("alive", was.get("alive", true)))
	if bool(was.get("alive", true)) and not alive:
		_out().play_sfx_at(
			GameDataRegistry.entity_sfx(def_id, &"death"), at, listener)
		# A building coming down is a bigger noise than whatever it was made of,
		# and it is the same sound for all of them.
		if now.has("phase"):
			_out().play_sfx_at(&"building.destroyed", at, listener)
		return          # nothing dead has anything else to say this tick

	if not alive:
		return

	# ── a building finishing ────────────────────────────────────────────────
	var phase := int(now.get("phase", was.get("phase", -1)))
	if phase != -1 and int(was.get("phase", -1)) != _PHASE_COMPLETE and phase == _PHASE_COMPLETE:
		# Flat, not positional: it is a report to the player that their order
		# completed, and it should not be quieter because the camera moved.
		# Only for OUR buildings -- an enemy finishing a house is not our news,
		# and on a fogless test map that would be every building on the board.
		if int(now.get("owner_id", 0)) == me:
			_out().play_sfx(GameDataRegistry.entity_sfx(def_id, &"complete"))

	# ── a gate being worked ─────────────────────────────────────────────────
	if now.has("gate_locked") and was.has("gate_locked"):
		var shut := bool(now["gate_locked"])
		if shut != bool(was["gate_locked"]):
			_out().play_sfx_at(
				&"gate.close" if shut else &"gate.open", at, listener)

	# ── work and fighting, from the animation the sim chose ─────────────────
	#
	# Keyed off `anim` rather than `task` because AnimationSystem has already
	# done the hard part: it decides that a unit has ARRIVED and is swinging,
	# where `task == ATTACK` is also true of one still walking across the map.
	# These repeat for as long as the anim holds and are rate-limited by
	# `throttle_ms` in audio.json, not by a transition test -- chopping is a
	# continuous noise, and firing once when the anim changed would give one
	# chop per tree.
	# The ENTITY ID goes with these two, and only these two. `AudioManager` paces
	# each source at its own cadence and caps the crowd separately, which is what
	# makes one villager chop about once a second while twenty of them sound like
	# a work site rather than either a machine gun or a single lonely axe.
	var id := int(now.get("id", 0))
	var anim := StringName(now.get("anim", was.get("anim", &"")))
	if anim == &"attack":
		_out().play_sfx_at(
			GameDataRegistry.entity_sfx(def_id, &"attack"), at, listener, id)
	elif anim.begins_with("work_"):
		_out().play_sfx_at(_work_sound(now, anim), at, listener, id)


## Which working noise a unit is making. The unit's own def cannot say -- a
## villager chops, mines, forages, fishes, farms and builds -- so this asks what
## it is working ON.
##
## IT FINDS THE TARGET BY POSITION, and that is a deliberate choice over the
## obvious one. `SimUnit.task_target_id` would answer exactly, and it is NOT ON
## THE WIRE (`to_snapshot` sends task, anim, facing and corpse ticks, and no
## more). Putting it there for audio would have cost a field name per shape per
## snapshot, which is precisely what 12.1f spent an optimisation pass removing --
## and worse, a field present on working units and absent on idle ones would
## split every unit into two shape tables and cost more than it saved.
##
## So: a unit playing a work anim is standing next to the thing it is working,
## and every candidate is already in the snapshot with a position. Nearest
## candidate within `_WORK_REACH` tiles that has a sound for this kind of work
## wins. Approximate by construction -- two adjacent forests, and it may credit
## the wrong tree -- which does not matter, because they sound the same. What it
## gets right is the distinction that IS audible: a berry bush from a carcass
## from a fishing spot, all three of which are `food` and all three of which
## `AnimationSystem` collapses into one `work_hunt` clip because that is all the
## ART has. Keying off the anim alone would have inherited that limitation for no
## reason (see audio_map.json's note).
##
## `&""` -- silence -- when nothing is in reach. A villager gathering from a node
## at the edge of vision is the honest case for that.
const _WORK_REACH := 4

func _work_sound(now: Dictionary, anim: StringName) -> StringName:
	var event := &"build" if anim == &"work_build" else &"work"
	var tile := _tile_of(now.get("pos", Vector2i.ZERO))
	var best := &""
	var best_d := _WORK_REACH + 1
	for cand in _work_candidates:
		var entry: Dictionary = cand
		var sound := GameDataRegistry.entity_sfx(
			StringName(entry["def_id"]), event)
		if sound == &"":
			continue
		var d: int = maxi(
			absi(entry["tile"].x - tile.x), absi(entry["tile"].y - tile.y))
		if d < best_d:
			best_d = d
			best = sound
	return StringName(best)


## Sub-tile position to tile. `SimWorld.SUBTILE` is the sim's own divisor and the
## view already reads it elsewhere; integer division matches how the sim floors.
func _tile_of(pos: Vector2i) -> Vector2i:
	return Vector2i(pos.x / SimWorld.SUBTILE, pos.y / SimWorld.SUBTILE)


## A unit that was not here last tick. Only OUR units report, and only units --
## a building appearing is a foundation being placed, which the player just
## ordered and already has feedback for.
func _appeared(now: Dictionary, me: int) -> void:
	if int(now.get("owner_id", 0)) != me:
		return
	if now.has("phase") or now.has("amount"):
		return          # a building or a resource node, not a trained unit
	if not now.has("anim"):
		return          # not a unit shape at all
	_out().play_sfx(
		GameDataRegistry.entity_sfx(StringName(now.get("def_id", &"")), &"trained"))


## The fields a transition needs next tick. Merged over the previous value so a
## REMEMBERED entry -- which carries none of the live ones -- does not erase what
## we knew, which would make the next full sighting look like a change.
func _keep(now: Dictionary, was: Dictionary) -> Dictionary:
	var out := was.duplicate()
	for key in ["def_id", "owner_id", "alive", "phase", "anim", "gate_locked",
			"task_target_id", "pos"]:
		if now.has(key):
			out[key] = now[key]
	return out


# ── per-player and per-match ────────────────────────────────────────────────

func _player_transitions(snap: Dictionary, me: int) -> void:
	var state: Dictionary = snap.get("player_state", {})
	var mine: Dictionary = state.get(me, {})

	# An age landing. Ours only -- an opponent advancing is not something the
	# player is told about anywhere else either.
	var age := int(mine.get("age", 0))
	var before := int(_prev_age.get(me, 0))
	if _primed and age > before and before > 0:
		_out().play_sfx(&"ui.age_advance")
		_out().play_music(StringName("match.age%d" % age))
	elif not _prev_age.has(me) and age > 0:
		# First sight of our own age: start the music without the fanfare.
		_out().play_music(StringName("match.age%d" % age))
	if age > 0:
		_prev_age[me] = age

	# The result, once. `_refresh_result` in GameScene owns the SCREEN and reads
	# the same three fields; this is deliberately independent of it rather than
	# called from it, so the sound cannot be lost to an early return there.
	if _announced_result:
		return
	var over := bool(snap.get("match_over", false))
	var defeated := bool(mine.get("defeated", false))
	if not over and not defeated:
		return
	_announced_result = true
	# YOUR SIDE WINNING IS YOU WINNING (2026-08-31), the same rule `_refresh_result`
	# applies to the screen -- and it has to be applied twice, because this is
	# deliberately independent of that function rather than called from it. The one
	# thing it does NOT copy is the forfeit clause: the screen distinguishes "you
	# resigned" from "you lost" in words, and there is no third fanfare to play.
	var winning_team := int(snap.get("winner_team", 0))
	var won := over and (int(snap.get("winner_id", 0)) == me
			or (winning_team > 0 and winning_team == int(mine.get("team", 0))))
	_out().play_sfx(&"ui.victory" if won else &"ui.defeat")
	_out().play_music(&"match.victory" if won else &"match.defeat")


## Control of the King of the Hill zone changing hands (PLAN.md 11.2,
## `11.x-koth-control-sound`). Owner's ask, 2026-09-08: *"sound on change of most units in
## area of KOTH for all payers (short subtile sound, it will play often)"*.
##
## **EVERY PLAYER HEARS IT, which is the ask and is also the only thing that can be true.**
## `koth_holder` is a fact about the MATCH and rides the top of the snapshot beside
## `claim_owner`, not in `player_state` -- so unlike an age landing or a finished building,
## there is no "ours only" clause to apply and nothing here reads `me`. The hill is a rule
## both sides are playing to.
##
## ⚠️ **READ OFF THE WIRE, NEVER COUNTED HERE**, and that is `GameView.koth_holder`'s rule
## rather than a preference: half the units in a contested zone are in fog for every player
## but their owner, so a client that counted would hear a different match from its opponent
## for a question the server has already answered. 13.2c's claim is on the wire for the same
## reason.
##
## ## WHICH TRANSITIONS MAKE A NOISE -- THE OWNER'S RULING, 2026-09-11
##
## There are three, not one, and only two of them sound:
##
## | | | |
## |---|---|---|
## | **taken** | 0 -> someone | ✅ sounds |
## | **stolen** | someone -> someone else | ✅ sounds |
## | **lost** | someone -> 0 (contested, or the hill emptied) | ⛔ **silent** |
##
## ⛔ **`lost` IS THE ONE THAT FIRES MOST AND MEANS LEAST**, because a tie has no unique leader:
## the holder drops to 0 every time a fight on the hill is even, **while both sides go on
## scoring**. Announcing it is how a short subtle sound becomes a stutter during the one moment
## the player is busiest — and it would be announcing a loss of the LEAD, not of progress.
## Offered to the
## owner with that argument and with the case against (losing the hill is arguably the most
## actionable thing to hear); they chose taken + stolen.
##
## 📝 **SO A HILL RETAKEN AFTER A LONG CONTESTED SPELL DOES SOUND AGAIN**, because the
## silence on `lost` still MOVES the announced holder to 0. That is deliberate: the
## alternative -- holding the announced value at the old winner through the contest -- makes
## retaking your own hill silent, which is a capture the player is never told about.
func _koth_transitions(snap: Dictionary) -> void:
	# NO HILL, NO SOUND. An empty rect is `SimWorld.koth_zone`'s arming convention carried
	# across the wire, and it is how every non-KotH match in the game reaches this function
	# -- the field is sent unconditionally, so without this clause a conquest match would
	# announce a permanent holder of 0 on its first snapshot.
	if not snap.has("koth_holder") or Rect2i(
			int(snap.get("koth_x", 0)), int(snap.get("koth_y", 0)),
			int(snap.get("koth_w", 0)), int(snap.get("koth_h", 0))).size == Vector2i.ZERO:
		return

	var holder := int(snap["koth_holder"])

	# THE DWELL. A candidate has to survive `_KOTH_DWELL_TICKS` consecutive snapshots before
	# it is believed, so a hill flickering between two sides settles on neither and stays
	# silent. Resetting the counter on any change is what makes that true -- a candidate that
	# merely APPEARS often is not a candidate that held.
	if holder != _koth_candidate:
		_koth_candidate = holder
		_koth_dwell = 1
		return
	_koth_dwell += 1
	if _koth_dwell < _KOTH_DWELL_TICKS:
		return

	# Believed. Nothing to say if it is what we already announced -- which is also what stops
	# a stable hill re-announcing itself on every snapshot for the rest of the match.
	if holder == _koth_announced:
		return

	# ⚠️ **THE FIRST BELIEVED READING IS RECORDED AND NOT ANNOUNCED.** `_koth_announced`
	# starts at -1, so a player joining a match in progress -- or simply the first snapshot
	# after the mode arms -- would otherwise be told the hill had just been taken by whoever
	# happened to be standing on it. Same swallow as `_primed`, for the same reason.
	var first := _koth_announced == -1
	_koth_announced = holder
	if first:
		return
	# `lost` is silent: see the table above.
	if holder == 0:
		return
	_out().play_sfx(&"ui.koth_control")
