## Dev check for garrison (PLAN.md 4.8/4.9): put archers in a tower and photograph
## every state a green test cannot judge.
##
## THREE THINGS HERE HAVE NO TEST THAT COULD FAIL FOR THE RIGHT REASON:
##
##   1. **A garrisoned unit has to actually stop being drawn.** The sim tests assert it
##      leaves `SpatialHash` and the snapshot, which is the mechanism -- but the thing
##      the player sees is whether three archers vanish into the stonework or go on
##      standing there looking ordered. Those are the same green suite.
##   2. **The panel's badge and roster.** "3/5" on the Garrison slot and three archer
##      portraits in the detail grid are pure layout, and the action row for a castle
##      now sits on exactly its eighth slot -- one off and something drops off the end
##      silently (`SelectionActions._capped`).
##   3. **A tower's arrow.** A building has no arm to swing, so if the projectile is
##      missing there is nothing on screen to explain a health bar falling. This is the
##      same problem `preview_projectiles` exists for, and it borrows that file's two
##      tricks: freeze the sim before the picture, and PRINT the numbers so a
##      blank-looking screenshot can be told from a badly-timed one.
##
## It also prints the damage each shot actually lands, with the garrison and without,
## because "half of each archer's damage" is arithmetic nobody should have to trust:
## a guard tower is 8 alone and 8 + 3x2 = 14 with three archers in it.
##
## Usage:
##   Godot --path game res://dev_preview/preview_garrison.tscn
##       -- writes user://garrison_*.png and quits.
##   ... -- --interactive     -- leaves it running.
extends Node

const SHOT_DIR := "user://"
const STEP_FRAMES := 12
const POLL_LIMIT := 900

## Three archers into a guard tower, which is cap 5 and damage 8 -- so the shot goes
## from 8 to 14 and there is still visible room left on the badge (3/5 rather than a
## full 5/5, which would read the same as a cap of 3).
const TOWER := &"building.guard_tower"
const GARRISON_SIZE := 3

var _game: Node = null
var _frames := 0
var _phase := 0
var _polls := 0
var _interactive := false

var _tower_id := 0
var _archer_ids: Array[int] = []
var _raider_id := 0
var _raider_hp := 0
var _bonus_hit := 0
var _base_hit := 0
var _at := Vector2i.ZERO


func _ready() -> void:
	_interactive = OS.get_cmdline_user_args().has("--interactive")
	_game = load("res://scenes/game/Game.tscn").instantiate()
	add_child(_game)


## PANEL AND ROSTER EACH GET THEIR OWN SHOT PHASE, one step later, and that is not
## tidiness. **A screenshot taken in the same frame as an action shows the state before
## it** (AGENT_GAME_CODER.md 5) -- the first run pressed the Garrison slot and
## photographed the same frame, and what came back was a panel with an EMPTY detail
## grid: the roster's four slots were in `_detail_slots` and the log said so, and none
## of them had been drawn yet. Photographing the selection had the same fault one step
## earlier and produced a picture with no panel in it at all.
enum {
	SET_UP, SHOT_BEFORE, ORDER, WAIT_IN, SHOT_INSIDE, PANEL, SHOT_PANEL,
	ROSTER, SHOT_ROSTER,
	RAID, WAIT_BONUS_HIT, CATCH_ARROW, SHOT_ARROW,
	EJECT, WAIT_OUT, SHOT_OUT, WAIT_BASE_HIT,
	REFILL, DESTROY, SHOT_DEAD, DONE,
}

## The polling phases, which check every frame rather than waiting out a fixed delay.
## An arrow is in the air for a handful of ticks and a walk across open ground takes
## as long as it takes; both would be missed by a timer.
const POLLING := [WAIT_IN, WAIT_BONUS_HIT, CATCH_ARROW, WAIT_OUT, WAIT_BASE_HIT]


func _process(_delta: float) -> void:
	if _interactive:
		return
	if _phase == DONE:
		get_tree().quit()
		return

	if POLLING.has(_phase):
		_polls += 1
		if _poll():
			_advance()
		elif _polls > POLL_LIMIT:
			push_warning("preview_garrison: phase %d never resolved in %d frames"
					% [_phase, POLL_LIMIT])
			if _tower_id != 0 and _tower() != null:
				_dump_candidates()
			_advance()
		return

	_frames += 1
	if _frames < STEP_FRAMES:
		return
	_frames = 0

	match _phase:
		SET_UP: _set_up()
		SHOT_BEFORE: _shoot("garrison_1_before")
		ORDER: _order_them_in()
		SHOT_INSIDE: _report_inside()
		PANEL: _open_the_panel()
		SHOT_PANEL: _shoot("garrison_3_panel")
		ROSTER: _open_the_roster()
		SHOT_ROSTER: _shoot("garrison_4_roster")
		RAID: _send_a_raider()
		SHOT_ARROW: _photograph_the_arrow()
		EJECT: _turn_them_out()
		SHOT_OUT: _shoot("garrison_5_out")
		REFILL: _put_them_back()
		DESTROY: _burn_it_down()
		SHOT_DEAD: _shoot("garrison_6_dead")
	_advance()


func _advance() -> void:
	_phase += 1
	_frames = 0
	_polls = 0


func _world() -> SimWorld:
	var host := Net.host()
	return host.world if host != null else null


func _tower() -> SimBuilding:
	var w := _world()
	return w.get_entity(_tower_id) as SimBuilding if w != null else null


# ── polling ─────────────────────────────────────────────────────────────────

func _poll() -> bool:
	match _phase:
		WAIT_IN:
			return _tower() != null and _tower().garrison.size() >= GARRISON_SIZE
		WAIT_BONUS_HIT:
			return _record_hit(true)
		CATCH_ARROW:
			return _catch_the_arrow()
		WAIT_OUT:
			return _tower() != null and _tower().garrison.is_empty()
		WAIT_BASE_HIT:
			return _record_hit(false)
	return true


## Watch the raider's health for one shot and record what it cost. Two calls, one with
## the garrison and one without, and the difference between them IS the 4.9 bonus.
func _record_hit(with_garrison: bool) -> bool:
	var w := _world()
	var raider := w.get_entity(_raider_id) if w != null else null
	if raider == null or not raider.alive:
		return true
	if raider.hp >= _raider_hp:
		return false

	var hit: int = _raider_hp - raider.hp
	_raider_hp = raider.hp
	var t := _tower()
	# THE LANDED FIGURE IS AFTER ARMOUR, so it is a point or two under
	# `attack_damage + attack_bonus` -- the raider is a militia and militia carry
	# pierce armour. Both numbers are printed so the gap is visibly armour rather than
	# looking like the bonus arithmetic being wrong, which is how the first run of this
	# read (8 declared, 7 landed).
	if with_garrison:
		_bonus_hit = hit
		print("  WITH %d archers inside: %d damage landed (tower %d + garrison %d, "
				% [t.garrison.size(), hit, t.attack_damage, t.attack_bonus(w)]
				+ "less the target's armour)")
	else:
		_base_hit = hit
		print("  EMPTY tower: %d damage landed (tower %d + garrison 0, less armour)"
				% [hit, t.attack_damage])
		print("  so three archers were worth %d damage a shot, and the declared "
				% (_bonus_hit - _base_hit)
				+ "bonus was %d" % (GARRISON_SIZE * 2))
		if _bonus_hit - _base_hit != GARRISON_SIZE * 2:
			push_warning("preview_garrison: expected the garrison to add %d, it added %d"
					% [GARRISON_SIZE * 2, _bonus_hit - _base_hit])
	return true


## Freeze the world on an airborne arrow that has left the tower, so the picture and
## the frame the viewport actually holds are the same still life.
##
## `elapsed_ticks >= 1` for the reason `preview_projectiles` records: at tick 0 the
## arrow is standing on its shooter's own tile, and for a tower that means somewhere
## inside the battlements where nothing can be judged.
func _catch_the_arrow() -> bool:
	var w := _world()
	if w == null:
		return false
	var ids := w.entities.keys()
	ids.sort()
	for id in ids:
		var e = w.entities[id]
		if not (e is SimProjectile) or (e as SimProjectile).elapsed_ticks < 1:
			continue
		var p: SimProjectile = e
		SimClock.stop()
		var at: Vector2 = _game._view.get_global_transform_with_canvas() \
				* Iso.sub_to_world(p.pos)
		# The numbers, so a screenshot with no visible arrow can be told from one taken
		# at the wrong moment -- and so there is a coordinate to crop to. These are 2-8
		# px sprites; at 1:1 you cannot see one.
		print("  tower arrow: %s at tile %s, tick %d of %d, facing %d, SCREEN %s"
				% [p.def_id, p.tile(), p.elapsed_ticks, p.total_ticks, p.facing, at.round()])
		if GameDataRegistry.atlas_for(p.def_id).is_placeholder:
			push_warning("preview_garrison: %s has no staged art" % p.def_id)
		if _game._view.pool.get_view(p.id) == null:
			push_warning("preview_garrison: %s has no EntityView -- nothing draws it" % p.def_id)
		return true
	return false


# ── the script ──────────────────────────────────────────────────────────────

## A tower on clear ground near the player's own base, with three archers beside it.
##
## NEAR THE BASE, not in a corner, and that is `preview_projectiles`' scar rather than
## tidiness: a first version that swept from (4, 4) put the whole scene in ground the
## player had never explored, and `ClientFog` painted every subject out of a screenshot
## whose entire purpose was to show them. What came back was a black rectangle and a
## warning-free log.
func _set_up() -> void:
	var w := _world()
	if w == null:
		push_warning("preview_garrison: no host world")
		_phase = DONE
		return
	_add_an_opponent(w)
	_at = _clear_ground(w, Vector2i(14, 7))

	var me := Net.local_player_id()
	var tower := w.spawn_building(TOWER, me, _at + Vector2i(6, 2))
	if tower == null:
		push_warning("preview_garrison: could not place the tower")
		_phase = DONE
		return
	_tower_id = tower.id

	for i in range(GARRISON_SIZE):
		var a := w.spawn_unit(&"unit.archer", me, _at + Vector2i(1 + i, 3))
		if a != null:
			_archer_ids.append(a.id)

	print("  %s at %s (cap %d, damage %d, range %d), %d archers at %s"
			% [TOWER, tower.tile(), tower.garrison_cap, tower.attack_damage,
			tower.attack_range, _archer_ids.size(), _at + Vector2i(1, 3)])
	_game._camera.centre_on(Iso.tile_centre_to_world(_at + Vector2i(5, 3)))
	_game._camera.zoom = Vector2(CameraRig.MAX_ZOOM, CameraRig.MAX_ZOOM)


## Through the real command, so what is exercised is the path a player's tap takes.
## The tap itself is `GameView.tap_action` returning GARRISON, which
## `tests/view/test_garrison_ui.gd` covers -- this drives the order behind it.
func _order_them_in() -> void:
	Net.submit_command(GarrisonCommand.new(Net.local_player_id(), _archer_ids, _tower_id))


## The picture that matters most, and the log line that says whether it is honest: an
## archer that is still being DRAWN while the sim thinks it is indoors would look
## exactly like a screenshot taken a moment too early.
func _report_inside() -> void:
	var w := _world()
	var t := _tower()
	print("  inside: %d/%d" % [t.garrison.size(), t.garrison_cap])
	for id in _archer_ids:
		var u := w.get_entity(id) as SimUnit
		var drawn := _game._view.pool.get_view(id) != null
		var in_facts: bool = not (_game._view.facts_for(id) as Dictionary).is_empty()
		print("    archer %d: garrisoned_in %d, still in facts %s, still drawn %s"
				% [id, u.garrisoned_in if u != null else -1, in_facts, drawn])
		if u != null and u.garrisoned_in != 0 and (drawn or in_facts):
			push_warning("preview_garrison: archer %d is indoors and still on screen" % id)
	_shoot("garrison_2_inside")


func _open_the_panel() -> void:
	_game._view.select([_tower_id] as Array[int])
	_game._refresh_panel()
	var panel: SelectionPanel = _game._panel
	var badges: Array[String] = []
	for slot in panel._action_slots:
		if slot.visible and slot.action != null:
			badges.append("%s%s" % [slot.action.id,
					"[%s]" % slot.action.badge if slot.action.badge != "" else ""])
	print("  action row (%d of %d slots): %s"
			% [badges.size(), SelectionActions.MAX_ACTIONS, ", ".join(badges)])


## Presses the Garrison slot, which is an `expands` action -- so this fills the detail
## grid rather than issuing anything, and the Empty button lives in there.
func _open_the_roster() -> void:
	var panel: SelectionPanel = _game._panel
	for slot in panel._action_slots:
		if slot.visible and slot.action != null and slot.action.id == &"garrison":
			panel._on_action_pressed(slot.action)
			var ids: Array[String] = []
			for d in panel._detail_slots:
				if d.visible and d.action != null:
					ids.append(String(d.action.id))
			print("  roster: %s" % ", ".join(ids))
			return
	push_warning("preview_garrison: no garrison action on the tower's panel")


## Somebody for the tower to shoot. A great deal of health, so it survives long enough
## to be hit once with the garrison and once without -- a militia has 40 and a loaded
## guard tower lands 14.
func _send_a_raider() -> void:
	var w := _world()
	var t := _tower()
	var raider := w.spawn_unit(&"unit.militia", _enemy_id(),
			t.tile() + Vector2i(t.attack_range - 1, 0))
	if raider == null:
		push_warning("preview_garrison: could not place a raider")
		return
	raider.max_hp = 100000
	raider.hp = raider.max_hp
	_raider_id = raider.id
	_raider_hp = raider.hp
	print("  raider at %s, %d tiles from the tower's footprint"
			% [raider.tile(), CombatSystem.tile_gap(raider.tile(), t.footprint_rect())])
	_dump_candidates()


## EVERYTHING THE TOWER COULD BE SHOOTING, and whether it would.
##
## This exists because the first run of this preview reported a tower that fired
## steadily and never touched the raider five tiles away -- the arrow was going
## somewhere and the log could not say where. Nearest-target-wins means anything closer
## than the intended subject makes the whole measurement silently meaningless, and on a
## debug map "anything closer" is a grazing animal.
func _dump_candidates() -> void:
	var w := _world()
	var t := _tower()
	var rect := t.footprint_rect().grow(maxi(1, t.attack_range))
	var lines: Array[String] = []
	for e in w.entities_in_rect(rect):
		if not (e is SimUnit):
			continue
		var u: SimUnit = e
		var gap := CombatSystem.tile_gap(u.tile(), t.footprint_rect())
		if gap > t.attack_range:
			continue
		lines.append("%s owner %d at %s gap %d hp %d -> %s"
				% [u.def_id, u.owner_id, u.tile(), gap, u.hp,
				"TARGET" if CombatSystem._is_at_war_with(w, u, t.owner_id) else "ignored"])
	lines.sort()
	print("  in range of the tower: %s" % ("nothing" if lines.is_empty() else ""))
	for line in lines:
		print("    %s" % line)


func _photograph_the_arrow() -> void:
	# The world has been stopped for a few frames, so this frame and the one the
	# texture actually holds are the same picture.
	_shoot("garrison_arrow")
	SimClock.start()


func _turn_them_out() -> void:
	Net.submit_command(UngarrisonCommand.new(Net.local_player_id(), _tower_id,
			UngarrisonCommand.ALL))


## Straight into the sim rather than through the command, because this is set-up for
## the last picture rather than a thing being tested -- and the command path has
## already been driven above.
func _put_them_back() -> void:
	var w := _world()
	var t := _tower()
	for id in _archer_ids:
		var u := w.get_entity(id) as SimUnit
		if u != null and u.alive:
			w.garrison_unit(t, u)
	print("  refilled: %d/%d for the last picture" % [t.garrison.size(), t.garrison_cap])


## The rule the owner asked for and the one most worth a picture: the tower falls and
## the bodies appear around it rather than the garrison walking out.
func _burn_it_down() -> void:
	var t := _tower()
	var held := t.garrison.size()
	t.take_damage(t.hp, 0)
	print("  destroyed the tower with %d inside" % held)


# ── ground and opponents ────────────────────────────────────────────────────

func _enemy_id() -> int:
	return Net.local_player_id() + 1


func _add_an_opponent(w: SimWorld) -> void:
	if w.player_for(_enemy_id()) != null:
		return
	var p := SimPlayer.new()
	p.id = _enemy_id()
	p.colour = 3
	w.players.append(p)


## A clear box of `span` tiles found by expanding rings around the player's own town
## centre, so the scene lands in ground they can already see.
##
## CLEAR OF UNITS AS WELL AS OF OCCUPIED TILES, and the second half is this preview's
## own scar. `can_place_building` asks the MAP, and units are not written into map
## occupancy (SimMap's static-footprint rule) -- so the first version happily chose a
## box with a **bear** standing one tile from where the tower was about to go. The tower
## then behaved perfectly and the measurement was worthless: nearest-target-wins, the
## bear carries 130 hp, and ten shots later the raider five tiles out had still never
## been touched. It mauled the archer standing outside for good measure.
##
## Only units that are NOT the local player's matter -- their own villagers wandering
## past are nobody's target -- which is why this is not simply "no units at all", a
## condition no ground near a town centre would ever satisfy.
##
## Grown by `margin` so the exclusion covers the tower's whole reach rather than just
## the box: an animal just outside the footprint is still nearer than the raider.
func _clear_ground(w: SimWorld, span: Vector2i, margin: int = 9) -> Vector2i:
	var anchor := _home_tile(w)
	for ring in range(4, 24):
		for dy in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dy)) != ring:
					continue
				var origin := anchor + Vector2i(dx, dy)
				if origin.x < 2 or origin.y < 2:
					continue
				if origin.x + span.x >= w.map.size.x - 2 \
						or origin.y + span.y >= w.map.size.y - 2:
					continue
				var rect := SimMap.footprint_rect(origin, span)
				if not w.map.can_place_building(rect):
					continue
				if _has_a_stranger(w, rect.grow(margin)):
					continue
				return origin
	push_warning("preview_garrison: no clear %s ground near home" % span)
	return anchor


## Any unit in `rect` that is not the local player's -- gaia's animals included, which
## is the case that actually bit.
func _has_a_stranger(w: SimWorld, rect: Rect2i) -> bool:
	for e in w.entities_in_rect(rect):
		if e is SimUnit and e.owner_id != Net.local_player_id():
			return true
	return false


func _home_tile(w: SimWorld) -> Vector2i:
	var ids := w.entities.keys()
	ids.sort()
	for id in ids:
		var e = w.entities[id]
		if e is SimBuilding and e.owner_id == Net.local_player_id():
			return (e as SimBuilding).tile()
	return w.map.size / 2


func _shoot(name: String) -> void:
	var path := SHOT_DIR + name + ".png"
	get_viewport().get_texture().get_image().save_png(path)
	print("wrote ", ProjectSettings.globalize_path(path))
