## Dev check for which way a fighter faces (PLAN.md 4.13), reported from play on
## 2026-08-22: "attack animation faces away from the thing they are attacking".
##
## EIGHT ATTACKERS IN A RING AROUND ONE VICTIM, all swinging at once. That shape is the
## point: a facing bug is almost never wrong in every direction by the same amount, and
## the ring shows immediately which of the three it is --
##
##   all eight wrong by 180 deg      a sign error on the delta
##   all eight MIRRORED              the sim/sprite table conversion, which has been
##                                   wrong before (`Iso.sim_facing_to_sprite`)
##   only the diagonals wrong        an octant rounding or table-order problem
##   only some units wrong           the ART, not the code -- a clip baked facing the
##                                   wrong way for one actor
##
## It prints the sim facing, the sprite index and the direction each attacker OUGHT to
## be looking, so the numbers can be checked without squinting at the picture, and then
## freezes the world and photographs it so the picture can be checked against them.
## Both halves are needed: the numbers can be right while the art faces the other way.
##
## Usage:
##   Godot --path game res://dev_preview/preview_combat_facing.tscn
##   ... -- --interactive
extends Node

const SHOT_DIR := "user://"
const STEP_FRAMES := 12

## Who does the swinging, and -- crucially -- a WALKING ring for comparison.
##
## The walk ring is not padding. `MovementSystem` and `CombatSystem` set facing with
## the same `SimUnit.facing_toward` on the same "toward the thing" delta, so the two
## CANNOT disagree: if attacking faces backwards then walking does too, and the fault
## is in the one shared conversion rather than in combat. Photographing both in one run
## is what tells those apart, and it is the difference between a one-line fix in
## `Iso.sim_facing_to_sprite` and a hunt through `CombatSystem`.
const ATTACKERS := [
	{"unit": &"unit.swordsman", "mode": "attack"},
	{"unit": &"unit.archer", "mode": "attack"},
	{"unit": &"unit.swordsman", "mode": "walk"},
	{"unit": &"unit.swordsman", "mode": "clip"},
	{"unit": &"unit.archer", "mode": "clip"},
]

## The eight tile directions, in `Iso.FACING_TILE_DIRS` order, with the name of the
## screen direction an attacker standing there has to LOOK to see the victim -- which
## is the opposite of where it is standing.
const RING := [
	{"at": Vector2i(1, 1), "look": "N"},
	{"at": Vector2i(0, 1), "look": "NE"},
	{"at": Vector2i(-1, 1), "look": "E"},
	{"at": Vector2i(-1, 0), "look": "SE"},
	{"at": Vector2i(-1, -1), "look": "S"},
	{"at": Vector2i(0, -1), "look": "SW"},
	{"at": Vector2i(1, -1), "look": "W"},
	{"at": Vector2i(1, 0), "look": "NW"},
]

enum { SET_UP, ORDER, WAIT, REPORT, DONE }

var _game: Node = null
var _frames := 0
var _phase := 0
var _which := 0
var _victim_id := 0
var _ring_ids: Array[int] = []
var _interactive := false


func _ready() -> void:
	_interactive = OS.get_cmdline_user_args().has("--interactive")
	_game = load("res://scenes/game/Game.tscn").instantiate()
	add_child(_game)


func _process(_delta: float) -> void:
	if _interactive:
		return
	_frames += 1
	if _which >= ATTACKERS.size():
		get_tree().quit()
		return
	if _frames < STEP_FRAMES:
		return
	_frames = 0

	var spec: Dictionary = ATTACKERS[_which]
	match _phase:
		SET_UP:
			if spec["mode"] == "clip":
				_set_up_clip_pair(spec)
			else:
				_set_up(spec)
			_phase = ORDER
		ORDER:
			if spec["mode"] == "walk":
				_order_the_walks()
			elif spec["mode"] == "clip":
				_order_the_clip_attack()
			else:
				_order_the_attacks()
			_phase = WAIT
		WAIT:
			# Long enough for everybody to close and start swinging. The melee ring
			# starts adjacent, so this is mostly for the archers to settle. A walking
			# ring is caught the other way round -- while it is still moving.
			if spec["mode"] == "walk":
				if _everybody_is_walking():
					_phase = REPORT
			elif spec["mode"] == "clip":
				# Only the attacker has to be swinging; its twin is idle on purpose.
				var a := _world().get_entity(_ring_ids[0]) as SimUnit if not _ring_ids.is_empty() \
						else null
				if a != null and a.anim == &"attack":
					_phase = REPORT
			elif _everybody_is_swinging():
				_phase = REPORT
		REPORT:
			SimClock.stop()
			_report(spec)
			_shoot("facing_%s_%s"
					% [String(spec["unit"]).trim_prefix("unit."), spec["mode"]])
			_phase = DONE
		DONE:
			SimClock.start()
			_clear()
			_which += 1
			_phase = SET_UP


func _world() -> SimWorld:
	return Net.host().world


func _enemy_id() -> int:
	return Net.local_player_id() + 1


## A victim in the middle and eight attackers around it, one per tile direction.
##
## The ring stands at `gap` tiles so a ranged attacker is already in range and does not
## have to walk -- a unit still closing is facing the way it WALKS, which is a different
## question and would muddy the picture.
func _set_up(spec: Dictionary) -> void:
	var unit_id: StringName = spec["unit"]
	var world := _world()
	if world.player_for(_enemy_id()) == null:
		var p := SimPlayer.new()
		p.id = _enemy_id()
		p.colour = 3
		world.players.append(p)

	var ud: UnitDef = GameDataRegistry.unit(unit_id)
	var gap: int = maxi(1, ud.attack_range if ud != null else 1)
	var centre := _clear_ground(world, gap * 2 + 4)

	var victim := world.spawn_unit(&"unit.militia", _enemy_id(), centre)
	if victim == null:
		push_warning("preview_combat_facing: nowhere to stand the victim")
		return
	# It must survive being hit from eight sides for as long as the picture takes.
	victim.max_hp = 100000
	victim.hp = 100000
	_victim_id = victim.id

	_ring_ids.clear()
	for spot in RING:
		var at: Vector2i = centre + (spot["at"] as Vector2i) * gap
		var u := world.spawn_unit(unit_id, Net.local_player_id(), at)
		if u == null:
			push_warning("preview_combat_facing: could not place at %s" % at)
			continue
		_ring_ids.append(u.id)

	_game._camera.centre_on(Iso.tile_centre_to_world(centre))
	_game._camera.zoom = Vector2(CameraRig.MAX_ZOOM, CameraRig.MAX_ZOOM) * 0.7


## THE EXPERIMENT THAT SEPARATES CODE FROM ART.
##
## Two of the same unit, side by side, at the SAME sim facing -- one idle, one
## attacking. Facing and the sim/sprite conversion are therefore identical for both,
## and the only thing that differs is which CLIP the atlas draws. If they look the same
## way, the fault is in the code. If the attacker is mirrored, the fault is in the bake
## and no amount of game-side arithmetic will fix it.
##
## Both are pointed EAST in tile space (sim facing 0, sprite index 7, "SE") -- screen
## down-right, which is unambiguous to read.
var _idle_id := 0

func _set_up_clip_pair(spec: Dictionary) -> void:
	var world := _world()
	if world.player_for(_enemy_id()) == null:
		var p := SimPlayer.new()
		p.id = _enemy_id()
		p.colour = 3
		world.players.append(p)

	var ud: UnitDef = GameDataRegistry.unit(spec["unit"])
	var gap: int = maxi(1, ud.attack_range if ud != null else 1)
	var centre := _clear_ground(world, gap + 6)

	# The attacker and its victim, laid out east-west so the attacker faces east.
	var attacker := world.spawn_unit(spec["unit"], Net.local_player_id(), centre)
	var victim := world.spawn_unit(&"unit.militia", _enemy_id(),
			centre + Vector2i(gap, 0))
	# The idle twin, two tiles south of the attacker, pointed the same way by hand.
	# Nothing recomputes an idle unit's facing, so this simply stays put.
	var idle := world.spawn_unit(spec["unit"], Net.local_player_id(),
			centre + Vector2i(0, 3))
	if attacker == null or victim == null or idle == null:
		push_warning("preview_combat_facing: could not lay out the clip pair")
		return
	victim.max_hp = 100000
	victim.hp = 100000
	idle.facing = 0

	_ring_ids = [attacker.id, idle.id] as Array[int]
	_victim_id = victim.id
	_idle_id = idle.id
	_game._camera.centre_on(Iso.tile_centre_to_world(centre + Vector2i(gap / 2, 1)))
	_game._camera.zoom = Vector2(CameraRig.MAX_ZOOM, CameraRig.MAX_ZOOM)


func _order_the_clip_attack() -> void:
	if _ring_ids.is_empty():
		return
	Net.submit_command(AttackCommand.new(Net.local_player_id(), [_ring_ids[0]], _victim_id))


func _order_the_attacks() -> void:
	for id in _ring_ids:
		Net.submit_command(AttackCommand.new(Net.local_player_id(), [id], _victim_id))


## Send each ring unit further OUT along the spoke it is already standing on, so it is
## walking directly away from the centre -- the same eight directions the attack ring
## covers, in the opposite sense. The victim is despawned first so nobody is walking
## into it.
func _order_the_walks() -> void:
	var world := _world()
	if _victim_id != 0 and world.get_entity(_victim_id) != null:
		world.despawn(_victim_id)
		_victim_id = 0
	for i in range(_ring_ids.size()):
		var u := world.get_entity(_ring_ids[i]) as SimUnit
		if u == null:
			continue
		var out: Vector2i = u.tile() + (RING[i]["at"] as Vector2i) * 3
		Net.submit_command(MoveCommand.new(Net.local_player_id(), [u.id], out))


## Everybody is actually in motion, which is when a walk facing means anything.
func _everybody_is_walking() -> bool:
	var world := _world()
	var moving := 0
	for id in _ring_ids:
		var u := world.get_entity(id) as SimUnit
		if u != null and u.alive and u.has_waypoint():
			moving += 1
	return moving == _ring_ids.size()


## Everybody has stopped walking and is actually swinging, which is when facing means
## what this preview is about. A unit still closing faces the way it walks.
func _everybody_is_swinging() -> bool:
	var world := _world()
	for id in _ring_ids:
		var u := world.get_entity(id) as SimUnit
		if u == null or not u.alive:
			continue
		if u.task != SimUnit.Task.ATTACK or u.has_waypoint() or u.path_pending:
			return false
	return true


## The numbers, per attacker: where it stands, which way it must look, what the sim
## says, and what the view will draw. Anything that disagrees is flagged in place, so
## the log alone says whether this is a code bug or an art one.
func _report(spec: Dictionary) -> void:
	var world := _world()
	if spec["mode"] == "clip":
		print("  %s clip pair -- both at sim facing 0 (sprite 7, SE, screen down-right):"
				% spec["unit"])
		for id in _ring_ids:
			var c := world.get_entity(id) as SimUnit
			if c == null:
				continue
			print("    %s at %s  anim %s  sim %d  sprite %d (%s)"
					% ["idle twin" if id == _idle_id else "attacker", c.tile(), c.anim,
					c.facing, Iso.sim_facing_to_sprite(c.facing),
					AtlasEntry.FACINGS[Iso.sim_facing_to_sprite(c.facing)]])
		print("    IF THESE TWO FACE OPPOSITE WAYS IN THE PICTURE, IT IS THE BAKE.")
		return

	var walking: bool = spec["mode"] == "walk"
	var victim := world.get_entity(_victim_id)
	if not walking and victim == null:
		push_warning("preview_combat_facing: the victim is gone")
		return

	print("  %s ring (%s):" % [spec["unit"], spec["mode"]])
	var wrong := 0
	for i in range(_ring_ids.size()):
		var u := world.get_entity(_ring_ids[i]) as SimUnit
		if u == null:
			continue
		# What the sim SHOULD have picked, from the same function it uses -- so this
		# checks that the facing was actually recomputed toward the thing, not that
		# `facing_toward` agrees with itself.
		#
		# A WALKER LOOKS THE OPPOSITE WAY to an attacker standing on the same spoke:
		# it is heading outward, away from the centre, where the attacker is looking
		# inward at it. That inversion is deliberate -- if both rings photograph the
		# same way round, the conversion is direction-blind.
		var want := SimUnit.facing_toward(u.waypoint_subpos() - u.pos) if walking \
				else SimUnit.facing_toward(victim.pos - u.pos)
		var sprite := Iso.sim_facing_to_sprite(u.facing)
		var name: String = AtlasEntry.FACINGS[sprite] if sprite < AtlasEntry.FACINGS.size() \
				else "?"
		var expected: String = _opposite(RING[i]["look"]) if walking else RING[i]["look"]
		var flag := ""
		if u.facing != want:
			flag = "  <-- SIM FACING IS STALE (want %d)" % want
			wrong += 1
		elif name != expected:
			flag = "  <-- TABLE SAYS %s, SHOULD BE %s" % [name, expected]
			wrong += 1
		print("    stands %s  anim %s  sim %d  sprite %d (%s)  should look %s%s"
				% [u.tile(), u.anim, u.facing, sprite, name, expected, flag])

	if wrong == 0:
		print("    all eight agree with the tables -- if the PICTURE disagrees, the")
		print("    fault is downstream of the sim: the conversion or the art.")
	else:
		push_warning("preview_combat_facing: %d of %d face wrong"
				% [wrong, _ring_ids.size()])


## The compass point 180 degrees from `dir`, for the walking ring's expectation.
static func _opposite(dir: String) -> String:
	var i := AtlasEntry.FACINGS.find(dir)
	if i < 0:
		return "?"
	return AtlasEntry.FACINGS[(i + 4) % AtlasEntry.FACINGS.size()]


func _clear() -> void:
	var world := _world()
	var doomed := _ring_ids.duplicate()
	doomed.append(_victim_id)
	doomed.sort()
	for id in doomed:
		if world.get_entity(id) != null:
			world.despawn(id)
	_ring_ids.clear()
	_victim_id = 0


## Clear ground near the player's base, so the fight is not staged in unexplored fog --
## the mistake `preview_projectiles` made first and photographed a black rectangle for.
func _clear_ground(world: SimWorld, span: int) -> Vector2i:
	var anchor := _home_tile(world)
	for ring in range(4, 24):
		for dy in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dy)) != ring:
					continue
				var origin := anchor + Vector2i(dx, dy)
				if origin.x - span < 2 or origin.y - span < 2:
					continue
				if origin.x + span >= world.map.size.x - 2 \
						or origin.y + span >= world.map.size.y - 2:
					continue
				if world.map.can_place_building(SimMap.footprint_rect(
						origin - Vector2i(span, span), Vector2i(span * 2, span * 2))):
					return origin
	push_warning("preview_combat_facing: no clear ground near home")
	return anchor


func _home_tile(world: SimWorld) -> Vector2i:
	var ids := world.entities.keys()
	ids.sort()
	for id in ids:
		var e = world.entities[id]
		if e is SimBuilding and e.owner_id == Net.local_player_id():
			return (e as SimBuilding).tile()
	return world.map.size / 2


func _shoot(name: String) -> void:
	var path := SHOT_DIR + name + ".png"
	get_viewport().get_texture().get_image().save_png(path)
	print("wrote ", ProjectSettings.globalize_path(path))
