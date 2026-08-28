## Dev check for projectiles (PLAN.md 4.13): shoot something and photograph the arrow.
##
## THE THING NO TEST CAN JUDGE IS WHETHER IT IS ON THE SCREEN. A projectile's whole job
## is to be looked at -- it carries no damage and changes no outcome -- so a suite that
## asserts one exists, flies and despawns can be entirely green while nothing is ever
## drawn. That is not hypothetical: the first version had `ProjectileSystem` running
## after `CombatSystem`, so a short shot was spawned and despawned inside one tick and
## never reached a snapshot. Every test passed.
##
## So this catches the arrow mid-flight and takes its picture, and prints where the
## thing actually is so a blank-looking screenshot can be told from a missing sprite.
##
## Three shooters, because they use three different bakes and the art side has been
## caught before by a wrong one: an archer (arrow), a ballista (bolt) and a trebuchet
## (stone).
##
## FOUR NOW, and the fourth is a BUILDING (project owner, 2026-08-28: *"watch tower is
## not showing 5x rocks when attacking + X x arrows for each archer in garrison"*). A
## tower is the case the three unit shooters cannot stand in for, twice over: its shot is
## a volley rather than a single projectile, and it needs no order at all -- it
## auto-acquires, so there is no `AttackCommand` to watch land. It also has no archer
## sprite drawing a bow, which is why the volley mattered enough to report: one arrow
## every two seconds off a stone tower reads as a tower doing nothing.
##
## AND A FIFTH PICTURE PER SHOOTER THAT IS NOT OF A PROJECTILE AT ALL -- the litter it
## leaves (`SpentProjectiles`). Same reasoning as the rest of this file: a decal that only
## exists to be looked at cannot be judged by a green suite, and the tests for it assert
## bookkeeping (how many, for how long) rather than that anything reached a screen.
##
## Usage:
##   Godot --path game res://dev_preview/preview_projectiles.tscn
##       -- writes user://projectile_*.png and quits.
##   ... -- --interactive     -- leaves it running.
extends Node

const SHOT_DIR := "user://"
const SETTLE_FRAMES := 30
const STEP_FRAMES := 10

## How long to let the volley land and settle before photographing the ground, in
## frames. `SpentProjectiles.LIFETIME` is 4 s and the fade is the last 1.5, so this wants
## to be comfortably inside the first half or the picture is of arrows going transparent.
const LITTER_FRAMES := 45

## Shooter, its projectile, and how far away to stand its victim. The range is inside
## each unit's own `attack.range` so it fires without walking, which matters because
## the siege engines carry `speed: 0` and cannot close at all.
##
## `building` swaps the whole set-up: no order is issued and `garrison` archers go inside,
## which is what makes the volley count something other than five.
const SHOOTERS := [
	{"unit": &"unit.archer", "visual": &"vis.projectile_arrow", "gap": 4},
	{"unit": &"unit.ballista", "visual": &"vis.projectile_bolt", "gap": 8},
	{"unit": &"unit.trebuchet", "visual": &"vis.projectile_stone", "gap": 11},
	{"unit": &"building.watch_tower", "visual": &"vis.projectile_stone", "gap": 5,
			"building": true, "garrison": 3},
]

var _game: Node = null
var _frames := 0
var _phase := 0
var _interactive := false

var _shooter_index := 0
var _shooter_id := 0
var _victim_id := 0
var _at := Vector2i.ZERO


func _ready() -> void:
	_interactive = OS.get_cmdline_user_args().has("--interactive")
	_game = load("res://scenes/game/Game.tscn").instantiate()
	add_child(_game)


## THE SIM IS FROZEN BEFORE THE PICTURE IS TAKEN, and that is the whole trick here.
##
## A projectile is in the air for 2 to 8 ticks. `get_viewport().get_texture()` returns
## the frame BEFORE the one being processed (AGENT_GAME_CODER.md 5), and the fixed
## step cadence lets another tick or two pass between deciding to shoot and shooting --
## so a screenshot chasing a live arrow lands wherever it happens to land, and the
## first run of this could not tell the arrow apart from the bow the archer was
## holding. `SimClock.stop()` makes it a still life instead: catch the arrow mid-flight,
## stop the world, let the view settle, then photograph a frame that cannot have moved.
enum { SET_UP, ORDER, CATCH, SHOOT, LITTER, CLEAR }

func _process(_delta: float) -> void:
	if _interactive:
		return
	_frames += 1
	if _shooter_index >= SHOOTERS.size():
		get_tree().quit()
		return

	# CATCH polls every frame rather than waiting out a step: the whole flight is a
	# handful of ticks and a fixed delay would miss most of it.
	if _phase == CATCH:
		if _catch_it_in_the_air(SHOOTERS[_shooter_index]):
			_phase = SHOOT
			_frames = 0
		elif _frames > 240:
			push_warning("preview_projectiles: %s never got anything in the air"
					% SHOOTERS[_shooter_index]["unit"])
			_phase = SHOOT
			_frames = 0
		return

	# LITTER runs the world for a while rather than a single step, so the shots it is
	# waiting on can actually land.
	if _phase == LITTER and _frames < LITTER_FRAMES:
		return
	if _frames < STEP_FRAMES:
		return
	_frames = 0

	match _phase:
		SET_UP:
			_set_up(SHOOTERS[_shooter_index])
			_phase = ORDER
		ORDER:
			_order_the_shot()
			_phase = CATCH
		SHOOT:
			# The world has been stopped for a few frames now, so this frame and the
			# one the texture actually holds are the same picture.
			_shoot("projectile_%s" % _name_of(SHOOTERS[_shooter_index]))
			# Let it land: the arrow is frozen mid-flight right now, and what comes next
			# is a picture of where it ends up.
			SimClock.start()
			_phase = LITTER
		LITTER:
			SimClock.stop()
			_report_litter()
			_shoot("projectile_%s_spent" % _name_of(SHOOTERS[_shooter_index]))
			_phase = CLEAR
		CLEAR:
			SimClock.start()
			_clear_the_field()
			_shooter_index += 1
			_phase = SET_UP


func _name_of(spec: Dictionary) -> String:
	return String(spec["unit"]).trim_prefix("unit.").trim_prefix("building.")


## What is lying on the ground, and where. Printed for exactly the reason every other
## number in this file is: a decal is a handful of pixels at 1:1, so "I cannot see one"
## and "there is not one" are indistinguishable in a screenshot without a count beside it.
func _report_litter() -> void:
	var layer: SpentProjectiles = _game._view.spent
	print("  spent on the ground: %d (they fade after %.0f s)"
			% [layer.count(), SpentProjectiles.LIFETIME])
	if layer.count() == 0:
		push_warning("preview_projectiles: nothing landed -- no decals were left")


## Stand a shooter and a victim on clear ground, in view, at a range the shooter can
## actually fire from.
func _set_up(spec: Dictionary) -> void:
	var world: SimWorld = Net.host().world
	_add_an_opponent(world)
	_at = _clear_ground(world, int(spec["gap"]) + 6)

	var shooter: SimEntity = _place_tower(world, spec) if spec.get("building", false) \
			else world.spawn_unit(spec["unit"], Net.local_player_id(), _at)
	var victim := world.spawn_unit(&"unit.militia", _enemy_id(),
			_at + Vector2i(int(spec["gap"]), 0))
	if shooter == null or victim == null:
		push_warning("preview_projectiles: could not place %s" % spec["unit"])
		return
	_shooter_id = shooter.id
	_victim_id = victim.id
	# A LOT of health, so the victim cannot die before the picture is taken -- a
	# trebuchet hits for 40 and a militia has 40.
	victim.max_hp = 4000
	victim.hp = 4000

	print("  %s at %s shooting %s at %s"
			% [spec["unit"], shooter.tile(), victim.def_id, victim.tile()])
	_game._camera.centre_on(Iso.tile_centre_to_world(
			_at + Vector2i(int(spec["gap"]) / 2, 0)))
	_game._camera.zoom = Vector2(CameraRig.MAX_ZOOM, CameraRig.MAX_ZOOM)


## A finished tower with archers inside it, which is a different shape of set-up from a
## unit in three ways worth naming.
##
## COMPLETE, because `CombatSystem._process_building` will not fire on a foundation's
## behalf -- a tower you have not finished paying for does not defend you. Garrisoned
## through `SimWorld.garrison_unit` rather than by appending to `b.garrison` by hand, so
## the archers actually leave the map: units standing around the tower would be in the
## picture and would also be shot at. And it needs no `AttackCommand` at all, which is
## what `_order_the_shot` skips: nothing can order a building to attack, so auto-acquire
## is the only way its data ever means anything.
func _place_tower(world: SimWorld, spec: Dictionary) -> SimEntity:
	var tower := world.spawn_building(spec["unit"], Net.local_player_id(), _at,
			SimBuilding.Phase.COMPLETE, true)
	if tower == null:
		return null
	for i in range(int(spec.get("garrison", 0))):
		var a := world.spawn_unit(&"unit.archer", Net.local_player_id(),
				_at + Vector2i(0, 4 + i))
		if a != null:
			world.garrison_unit(tower, a)
	print("  %s garrisoned with %d archer(s): volley %d + %d"
			% [spec["unit"], tower.garrison.size(), tower.attack_volley,
			tower.garrison_projectiles(world).size()])
	return tower


## Everything the shot needs that is not a unit: a second player to be hostile to, and
## enough vision that the snapshot is not fog-filtering the arrow away from its own
## viewer. `AttackCommand` refuses gaia and refuses your own.
func _add_an_opponent(world: SimWorld) -> void:
	if world.player_for(_enemy_id()) != null:
		return
	var p := SimPlayer.new()
	p.id = _enemy_id()
	p.colour = 3
	world.players.append(p)


func _enemy_id() -> int:
	return Net.local_player_id() + 1


## Ground with `span` clear tiles running east, found rather than assumed -- the same
## lesson `test_walls._clear_run` records -- and found NEAR THE PLAYER'S OWN BASE.
##
## The base part is not tidiness. The first version swept from (4, 4) and put the whole
## shot in a corner of the map the player had never explored, so `ClientFog` painted
## the archer, the victim and the arrow out of a screenshot whose entire purpose was to
## show them. What came back was a black rectangle with a warning-free log beside it.
##
## Searched as expanding rings around the town centre, so the shot lands in ground the
## player can already see without needing vision granted to them by hand.
func _clear_ground(world: SimWorld, span: int) -> Vector2i:
	var anchor := _home_tile(world)
	for ring in range(3, 20):
		for dy in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dy)) != ring:
					continue
				var origin := anchor + Vector2i(dx, dy)
				if origin.x < 2 or origin.y < 2:
					continue
				if origin.x + span >= world.map.size.x - 2 \
						or origin.y + 2 >= world.map.size.y - 2:
					continue
				if world.map.can_place_building(
						SimMap.footprint_rect(origin, Vector2i(span, 2))):
					return origin
	push_warning("preview_projectiles: no clear %d-tile ground near home" % span)
	return anchor


## The player's town centre, which is the one thing they can definitely see.
func _home_tile(world: SimWorld) -> Vector2i:
	var ids := world.entities.keys()
	ids.sort()
	for id in ids:
		var e = world.entities[id]
		if e is SimBuilding and e.owner_id == Net.local_player_id():
			return (e as SimBuilding).tile()
	return world.map.size / 2


## Through `AttackCommand`, the real order, so what is exercised is the path a player's
## tap actually takes into `CombatSystem`.
func _order_the_shot() -> void:
	if _shooter_id == 0:
		return
	# A BUILDING CANNOT BE ORDERED TO ATTACK -- there is no command that would name one
	# as the attacker, which is exactly why `CombatSystem` lets buildings auto-acquire
	# where it refuses it for units. Sending one here would be rejected and would look,
	# from the log, like the tower failing to fire.
	if bool(SHOOTERS[_shooter_index].get("building", false)):
		return
	Net.submit_command(AttackCommand.new(Net.local_player_id(), [_shooter_id], _victim_id))


## Look for an airborne projectile that has actually LEFT the shooter, and freeze the
## world the moment one is found. True once the world is stopped and the next step may
## take the picture.
##
## `elapsed_ticks >= 1` is the load-bearing part. At tick 0 the arrow is standing on the
## shooter's own tile, indistinguishable in a screenshot from the bow in its hands --
## which is exactly what the first run produced and what could not be judged.
func _catch_it_in_the_air(spec: Dictionary) -> bool:
	var host := Net.host()
	if host == null:
		return false
	var world: SimWorld = host.world
	var flying: SimProjectile = null
	var airborne := 0
	var ids := world.entities.keys()
	ids.sort()
	for id in ids:
		var e = world.entities[id]
		if e is SimProjectile and (e as SimProjectile).elapsed_ticks >= 1:
			airborne += 1
			if flying == null:
				flying = e
	if flying == null:
		return false

	SimClock.stop()

	var name := _name_of(spec)
	# THE COUNT, for the volley. Five stones drawn on top of each other are one stone as
	# far as a screenshot is concerned, so the number beside the picture is what says
	# whether the fan is working or whether they are all on one line.
	var want := 1
	if bool(spec.get("building", false)):
		want = int(spec.get("garrison", 0)) + \
				GameDataRegistry.building(spec["unit"]).attack_volley
	print("  %s: %d in the air (expected about %d)" % [name, airborne, want])
	# THE NUMBERS, so a picture with no visible arrow can be told apart from a picture
	# taken at the wrong moment -- including where on the screen to look for it.
	var at: Vector2 = _game._view.get_global_transform_with_canvas() \
			* Iso.sub_to_world(flying.pos)
	print("  %s: %s at tile %s, tick %d of %d, facing %d, SCREEN %s"
			% [name, flying.def_id, flying.tile(), flying.elapsed_ticks,
			flying.total_ticks, flying.facing, at.round()])
	if flying.def_id != spec["visual"]:
		push_warning("preview_projectiles: %s threw %s, expected %s"
				% [name, flying.def_id, spec["visual"]])
	# The art has to be real, or the picture is a magenta box and says nothing about
	# whether the projectile system works.
	if GameDataRegistry.atlas_for(flying.def_id).is_placeholder:
		push_warning("preview_projectiles: %s has no staged art" % flying.def_id)
	# And there has to BE a view for it, which is the half the sim tests cannot see.
	if _game._view.pool.get_view(flying.id) == null:
		push_warning("preview_projectiles: %s has no EntityView -- nothing is drawing it"
				% flying.def_id)
	return true


## Clear the board between shooters, so the next picture has one arrow in it.
func _clear_the_field() -> void:
	var world: SimWorld = Net.host().world
	var doomed: Array[int] = []
	for id in world.entities:
		var e = world.entities[id]
		# `garrisoned_in` catches the tower's archers, which are off the map and would
		# otherwise survive into the next shooter's picture as an invisible garrison.
		if e is SimProjectile or int(id) == _shooter_id or int(id) == _victim_id \
				or (e is SimUnit and (e as SimUnit).garrisoned_in == _shooter_id):
			doomed.append(int(id))
	doomed.sort()
	for id in doomed:
		world.despawn(id)
	# Otherwise the last shooter's litter is lying in the next one's picture -- and
	# despawning the projectiles above would ADD to it, since a despawn is exactly what
	# leaves a decal.
	_game._view.spent.clear()
	_shooter_id = 0
	_victim_id = 0


func _shoot(name: String) -> void:
	var path := SHOT_DIR + name + ".png"
	get_viewport().get_texture().get_image().save_png(path)
	print("wrote ", ProjectSettings.globalize_path(path))
