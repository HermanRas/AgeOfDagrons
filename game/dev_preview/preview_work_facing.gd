## Which way a unit looks while it WORKS, and while it hits a BUILDING.
##
## Reported from play on 2026-08-27, on the first build carrying the corrected atlases:
## *"Villager mining away from gold, scout attacking away from building."* Both survived
## the re-bake, which is what makes them worth a preview of their own -- `preview_facing_
## chart` proves the ATLAS is right and `preview_combat_facing` proves unit-versus-unit
## combat is right, so whatever is left is neither the art nor the shared conversion.
##
## THE TWO RINGS HERE ARE THE TWO CASES THAT WERE NEVER COVERED:
##
##   gather ring    eight villagers around one gold node, all mining it
##   siege ring     eight cavalry around one enemy house, all hitting it
##
## Each unit is checked against `SimUnit.facing_toward(target.pos - u.pos)` -- what the
## sim WOULD pick if it recomputed facing at the thing right now. A row flagged STALE
## means nothing turned the unit at all, which is a different bug from turning it the
## wrong way, and the two want different fixes:
##
##   every row STALE                  nothing sets facing for this task -- the sim
##   facing set but the sprite wrong  the conversion (`Iso.sim_facing_to_sprite`)
##   numbers agree, picture disagrees the bake, and no arithmetic here will fix it
##
## Usage:
##   Godot --path game res://dev_preview/preview_work_facing.tscn
##   ... -- --interactive
extends Node

const SHOT_DIR := "user://"
const STEP_FRAMES := 12
## Generous: a villager has to path around seven siblings to reach its own spot.
const MAX_WAIT_STEPS := 120

const CASES := [
	{"mode": "gather", "unit": &"unit.villager", "target": &"res.gold_mine"},
	{"mode": "siege", "unit": &"unit.scout_cavalry", "target": &"building.house"},
]

## The eight tile directions in `Iso.FACING_TILE_DIRS` order, with the screen direction
## a unit standing there must LOOK to see the thing in the middle -- the opposite of
## where it stands, exactly as `preview_combat_facing`'s ring does it.
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
var _waited := 0
var _phase := 0
var _which := 0
var _target_id := 0
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
	if _which >= CASES.size():
		get_tree().quit()
		return
	if _frames < STEP_FRAMES:
		return
	_frames = 0

	var spec: Dictionary = CASES[_which]
	match _phase:
		SET_UP:
			_set_up(spec)
			_waited = 0
			_phase = ORDER
		ORDER:
			_order(spec)
			_phase = WAIT
		WAIT:
			_waited += 1
			# A timeout REPORTS rather than skips. A ring that never settles is itself
			# a finding, and a silent skip would read as a pass.
			if _everybody_is_working(spec) or _waited > MAX_WAIT_STEPS:
				if _waited > MAX_WAIT_STEPS:
					print("  (timed out waiting for the ring to settle -- reporting anyway)")
				_phase = REPORT
		REPORT:
			SimClock.stop()
			_report(spec)
			_shoot("workfacing_%s" % spec["mode"])
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


func _set_up(spec: Dictionary) -> void:
	var world := _world()
	if world.player_for(_enemy_id()) == null:
		var p := SimPlayer.new()
		p.id = _enemy_id()
		p.colour = 3
		world.players.append(p)

	var centre := _clear_ground(world, 10)
	var gap := 3
	_ring_ids.clear()

	if spec["mode"] == "gather":
		var node := world.spawn_resource_node(spec["target"], centre)
		if node == null:
			push_warning("preview_work_facing: could not place the node")
			return
		# It has to outlast eight miners for as long as the picture takes. The first
		# run of this preview photographed nothing because they mined it out and the
		# node despawned while the ring was still settling.
		node.amount = 100000000
		node.starting_amount = node.amount
		# Every villager gathers at once, so nobody is left standing at a spot with
		# no slot -- an idle unit in the ring would be a row that proves nothing.
		node.gather_slots = RING.size()
		_target_id = node.id
	else:
		var bd: BuildingDef = GameDataRegistry.building(spec["target"])
		var foot: Vector2i = bd.footprint if bd != null else Vector2i.ONE
		var b := world.spawn_building(spec["target"], _enemy_id(),
				centre - foot / 2, SimBuilding.Phase.COMPLETE, true)
		if b == null:
			push_warning("preview_work_facing: could not place the building")
			return
		# It has to outlive eight attackers for as long as the picture takes.
		b.max_hp = 1000000
		b.hp = 1000000
		_target_id = b.id
		gap = maxi(foot.x, foot.y) + 2

	for spot in RING:
		var at: Vector2i = centre + (spot["at"] as Vector2i) * gap
		var u := world.spawn_unit(spec["unit"], Net.local_player_id(), at)
		if u == null:
			push_warning("preview_work_facing: could not place at %s" % at)
			continue
		_ring_ids.append(u.id)

	_game._camera.centre_on(Iso.tile_centre_to_world(centre))
	_game._camera.zoom = Vector2(CameraRig.MAX_ZOOM, CameraRig.MAX_ZOOM) * 0.7


func _order(spec: Dictionary) -> void:
	for id in _ring_ids:
		if spec["mode"] == "gather":
			Net.submit_command(GatherCommand.new(
					Net.local_player_id(), [id], _target_id))
		else:
			Net.submit_command(AttackCommand.new(
					Net.local_player_id(), [id], _target_id))


## Arrived and settled: on the order, and no longer walking. A unit still closing is
## facing the way it WALKS, which is the question this preview is NOT asking.
func _everybody_is_working(spec: Dictionary) -> bool:
	var world := _world()
	var want: int = SimUnit.Task.GATHER if spec["mode"] == "gather" else SimUnit.Task.ATTACK
	for id in _ring_ids:
		var u := world.get_entity(id) as SimUnit
		if u == null or not u.alive:
			continue
		if u.task != want or u.has_waypoint() or u.path_pending:
			return false
	return true


func _report(spec: Dictionary) -> void:
	var world := _world()
	var target := world.get_entity(_target_id)
	if target == null:
		push_warning("preview_work_facing: the target is gone")
		return

	print("  %s ring around %s:" % [spec["unit"], spec["target"]])
	var stale := 0
	for i in range(_ring_ids.size()):
		var u := world.get_entity(_ring_ids[i]) as SimUnit
		if u == null:
			continue
		# What the sim would pick if it turned the unit at the thing right now. This
		# asks whether facing was RECOMPUTED, not whether facing_toward agrees with
		# itself -- so a unit that merely kept its travel facing is caught.
		var want := SimUnit.facing_toward(target.pos - u.pos)
		var sprite := Iso.sim_facing_to_sprite(u.facing)
		var name: String = AtlasEntry.FACINGS[sprite] if sprite < AtlasEntry.FACINGS.size() \
				else "?"
		var should: String = AtlasEntry.FACINGS[Iso.sim_facing_to_sprite(want)]
		var flag := ""
		if u.facing != want:
			flag = "  <-- STALE: nothing turned it (sim %d, wants %d = %s)" \
					% [u.facing, want, should]
			stale += 1
		print("    stands %s  task %d  anim %s  sim %d  sprite %d (%s)  should be %s%s"
				% [u.tile(), u.task, u.anim, u.facing, sprite, name, should, flag])

	if stale == 0:
		print("    all eight are turned at the target -- if the PICTURE disagrees, the")
		print("    fault is downstream of the sim: the conversion or the art.")
	else:
		print("    %d of %d NEVER TURNED. That is the sim, not the bake."
				% [stale, _ring_ids.size()])


func _clear() -> void:
	var world := _world()
	var doomed := _ring_ids.duplicate()
	doomed.append(_target_id)
	doomed.sort()
	for id in doomed:
		if world.get_entity(id) != null:
			world.despawn(id)
	_ring_ids.clear()
	_target_id = 0


## Clear ground near the player's base, so the ring is not staged in unexplored fog --
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
	push_warning("preview_work_facing: no clear ground near home")
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
