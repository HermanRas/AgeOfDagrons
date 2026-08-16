## Dev check for the age/colour skin work: run the REAL match scene, drive it the
## way a player would, and screenshot each step.
##
## The distinction preview_world.gd already draws applies double here -- it draws
## nothing of its own and checks the real render path rather than a copy. This
## goes one further and instantiates `Game.tscn` itself, so what it photographs
## is the actual game: the real `SimHost`, the real command path, the real HUD.
## A preview that rebuilt any of that could show a working age badge while the
## game's own was broken.
##
## Drives rather than merely launching: it selects a villager, opens the build
## menu, pages it, and advances the age -- because "it started" is not evidence
## that the build grid pages or that a town centre re-skins.
##
## Usage:
##   Godot --path game res://dev_preview/preview_match.tscn
##       -- writes user://match_age1.png ... user://match_age4.png and quits.
##   ... -- --interactive     -- leaves it running to play with instead.
extends Node

const SHOT_DIR := "user://"

## Ticks to let the match settle before touching anything. The first snapshot
## only arrives after SimHost has stepped, and a screenshot taken before that is
## a photograph of an empty map.
const SETTLE_FRAMES := 30
## Between steps -- long enough for a command to land, be applied, and come back
## in a snapshot the HUD has drawn from.
const STEP_FRAMES := 12

## How long any _wait_until() will stall before giving up, warning, and carrying
## on. A preview that hangs forever reports nothing at all; one that shoots the
## wrong picture and says so in the log at least leaves evidence -- and the
## conditions waited on here are exactly the ones a regression would break.
const WAIT_TIMEOUT_FRAMES := 3600

var _game: Node = null
var _frames := 0
var _step := 0
## Set by _wait_until(); the script stalls until it returns true. Null means
## "not waiting on anything".
var _await_check: Callable = Callable()
var _await_since := 0
var _interactive := false


func _ready() -> void:
	_interactive = OS.get_cmdline_user_args().has("--interactive")
	_game = load("res://scenes/game/Game.tscn").instantiate()
	add_child(_game)


func _process(_delta: float) -> void:
	if _interactive:
		return
	_frames += 1

	# A wait outranks the frame gate: it is waiting on the SIM, which the frame
	# counter knows nothing about.
	if _await_check.is_valid():
		if not bool(_await_check.call()):
			if _frames - _await_since < WAIT_TIMEOUT_FRAMES:
				return
			push_warning("preview_match: gave up waiting at step %d" % _step)
		_await_check = Callable()
		# Re-base the frame gate, or every step after a wait fires immediately
		# because the counter has run far past its threshold.
		#
		# Re-based one STEP short of the threshold, not onto it, so the step after
		# a wait still gets the ordinary pause. Landing exactly on it fired the
		# next step in the very frame the wait came true -- and `_shoot()` reads
		# the viewport texture, which is the frame ALREADY DRAWN, so the combat
		# shot came out one frame stale: a photograph of the archer a moment
		# before it died, which is the same class of lie this script's own header
		# warns about for commands.
		_frames = SETTLE_FRAMES + (_step - 1) * STEP_FRAMES

	if _frames < SETTLE_FRAMES + _step * STEP_FRAMES:
		return
	_advance_script()


## One action per step, and the SHOT IS A STEP OF ITS OWN. Screenshotting in the
## same frame as the action photographs the state before it: an advance goes out
## as a command, and the HUD only moves when the next snapshot comes back. The
## first version of this shot immediately and produced an "age 4" image showing
## age 3 -- a lie about the thing it existed to check.
func _advance_script() -> void:
	match _step:
		0:
			_select_a_villager()
			_open_build_menu()
		1:
			_shoot("match_age1")
		2:
			# The real button: a timed research, so the ring starts filling. Held
			# for half of `advance_time_ticks` before the shot, or the photograph
			# is of a ring 2% round and says nothing.
			_press_advance()
			_wait_for_progress(0.5)
		3:
			_shoot("match_advancing")
		4:
			# The rest of the ladder uses the INSTANT debug jump. Sitting through
			# three more real researches would add 30 s to every preview run for
			# nothing -- the ring is already photographed, and what these shots
			# are for is the building skins.
			_jump_age(2)
		5:
			_shoot("match_age2")
		6:
			_jump_age(3)
		7:
			_shoot("match_age3")
		8:
			_jump_age(4)
			_select_a_villager()
			_open_build_menu()
		9:
			_shoot("match_age4")
		10:
			_page_build_menu()
		11:
			_shoot("match_age4_page2")
		12:
			# The town centre's own panel: its train row, and its queue once
			# something is in it. The queue slots crop the unit's portrait, which
			# needs the def ids to have survived the snapshot.
			_select_a_town_centre()
		13:
			_train_from_selection()
		14:
			_train_from_selection()
		15:
			_shoot("match_queue")
		16:
			# Placement, end to end: select a villager, order a house, and wait for
			# the house to actually be UNDER CONSTRUCTION. That last part is the
			# whole point -- a foundation appears whether or not anyone was sent to
			# raise it, so "the building is there" would have photographed the bug
			# reported on 2026-08-16 as a pass. Progress means a villager walked
			# over on its own and started work.
			_select_a_villager()
			_place_a_house()
			_wait_until(_a_house_is_going_up)
		17:
			_shoot("match_building")
		18:
			# Combat (4.13), through the tap path rather than a hand-built command:
			# what is being checked is that tapping an enemy with an army in hand
			# MEANS attack, which is a decision `GameView.tap_action()` makes and a
			# submitted AttackCommand would bypass entirely.
			#
			# Villagers, because the town centre is the only trainer on the debug
			# map and villagers are all it makes. A peasant mob at damage 3 apiece
			# is a slow way to kill an archer and a perfectly real one.
			_select_all_villagers()
			_tap_an_enemy()
			_wait_until(_an_enemy_is_dead)
		19:
			# Printed as well as photographed. A unit's `die` clip opens on it
			# still standing, so a corpse and a nearly-dead soldier look identical
			# in a single frame -- the picture cannot tell you which one you got.
			_report_enemies()
			_shoot("match_combat")
		20:
			# The three dropsites and their props. Age 4 by now, so the mill has
			# its food crates as well as the camps having their timber and stone.
			_stand_up_the_dropsites()
			_clear_selection()
		21:
			_shoot("match_props")
		_:
			get_tree().quit()
			return
	_step += 1


## Hold the script until `check` returns true, then carry on.
##
## Waits on something the SIM reports rather than on a frame count. The first
## version of the advance wait converted seconds to frames via
## `Engine.get_frames_per_second()` and hung the preview -- frames and sim ticks
## are different clocks (SimClock runs at a fixed 10 Hz whatever the frame rate
## does), so any frame count is a guess about a quantity the sim will happily
## tell you. This asks it.
func _wait_until(check: Callable) -> void:
	_await_check = check
	_await_since = _frames


## Hold until the local player's advance ring is at least this far round.
func _wait_for_progress(fraction: float) -> void:
	var view: GameView = _game._view
	_wait_until(func() -> bool:
		return view.age_progress_of(Net.local_player_id()) >= fraction)


func _select_a_villager() -> void:
	var view: GameView = _game._view
	var ids: Array = view.all_facts().keys()
	ids.sort()
	for id in ids:
		var f: Dictionary = view.facts_for(int(id))
		if bool(f.get("is_unit", false)) and StringName(f.get("def_id", &"")) == &"unit.villager":
			view.select([int(id)] as Array[int])
			_game._refresh_panel()
			return
	push_warning("preview_match: no villager to select")


## Idempotent, because the panel's Build action is a TOGGLE. Calling this twice
## across a script that reselects the same villager closed the menu instead of
## reopening it, and the age-4 shot came out with no build grid at all -- an
## empty grid photographed as though it were the finished thing.
func _open_build_menu() -> void:
	var panel: SelectionPanel = _game._panel
	if panel._active_action == &"build":
		return
	for slot in panel._action_slots:
		if slot.visible and slot.action != null and slot.action.id == &"build":
			panel._on_action_pressed(slot.action)
			return
	push_warning("preview_match: no build action on the panel")


func _page_build_menu() -> void:
	var panel: SelectionPanel = _game._panel
	for slot in panel._detail_slots:
		if slot.visible and slot.action != null and slot.action.id == SelectionActions.PAGE_NEXT:
			panel._on_detail_pressed(slot.action)
			return
	push_warning("preview_match: build menu does not page at this age")


func _select_a_town_centre() -> void:
	var view: GameView = _game._view
	var ids: Array = view.all_facts().keys()
	ids.sort()
	for id in ids:
		if StringName(view.facts_for(int(id)).get("def_id", &"")) == &"building.town_center":
			view.select([int(id)] as Array[int])
			_game._refresh_panel()
			return
	push_warning("preview_match: no town centre to select")


## Presses the first train button on the panel, the way a player would, rather
## than submitting a TrainCommand directly -- the queue slots are what is being
## checked and they only fill if the whole round trip works.
func _train_from_selection() -> void:
	var panel: SelectionPanel = _game._panel
	for slot in panel._action_slots:
		if slot.visible and slot.action != null and String(slot.action.id).begins_with("train:"):
			panel._on_action_pressed(slot.action)
			return
	push_warning("preview_match: nothing to train on the selected building")


## Through the badge's own signal path, not by poking SimPlayer -- the point is
## to check the BUTTON works, and a preview that set the age directly would pass
## with it unwired. Starts a timed research; the age lands seconds later.
func _press_advance() -> void:
	_game._age_badge._on_pressed()


## The instant debug jump, for getting to an age quickly. Deliberately NOT the
## button: it skips the research entirely, so a preview that used it everywhere
## would never exercise the thing the button does.
func _jump_age(to_age: int) -> void:
	Net.submit_command(DebugSetAgeCommand.new(Net.local_player_id(), to_age))


## Order a house onto clear ground just below the town centre, the way a player
## does: enter build mode, then release the drag over the target tile. NOT by
## submitting a PlaceBuildingCommand -- the thing being checked is that the
## placement carries the SELECTION with it (5.1), and a hand-built command would
## be the preview supplying the very list the bug was that nobody supplied.
##
## Close to the town centre on purpose: the villagers ring it, so the walk is a
## few tiles and the wait that follows is seconds rather than a minute.
func _place_a_house() -> void:
	var view: GameView = _game._view
	var tc := _town_centre_facts()
	if tc.is_empty():
		push_warning("preview_match: no town centre to build beside")
		return
	# `tile` is a footprint's CENTRE; the ghost and the command both want its
	# top-left. Off the town centre's right-hand corner, which is clear of the
	# resource clusters, a few tiles' walk from the villagers ringing it, and --
	# the reason for this offset rather than a nearer one -- lands on screen where
	# neither the selection panel nor the minimap covers it.
	var footprint: Vector2i = tc.get("footprint", Vector2i.ONE)
	var origin: Vector2i = (tc["tile"] as Vector2i) - footprint / 2 \
			+ Vector2i(footprint.x + 3, 6)
	_game._enter_placement(&"building.house")
	_game._on_placement_released(
			view.get_global_transform_with_canvas() * Iso.tile_to_world(origin))


## True once some house has real construction progress on it -- phase leaves
## FOUNDATION only when a builder has arrived and put a tick of work in.
func _a_house_is_going_up() -> bool:
	var view: GameView = _game._view
	for id in view.all_facts().keys():
		var f: Dictionary = view.facts_for(int(id))
		if StringName(f.get("def_id", &"")) != &"building.house":
			continue
		if int(f.get("phase", 0)) != SimBuilding.Phase.FOUNDATION:
			return true
	return false


func _select_all_villagers() -> void:
	var view: GameView = _game._view
	var ids: Array = view.all_facts().keys()
	ids.sort()
	var mine: Array[int] = []
	for id in ids:
		var f: Dictionary = view.facts_for(int(id))
		if int(f.get("owner_id", 0)) == Net.local_player_id() \
				and StringName(f.get("def_id", &"")) == &"unit.villager" \
				and bool(f.get("alive", true)):
			mine.append(int(id))
	view.select(mine)
	_game._refresh_panel()


## Tap the nearest enemy, at its own tile, the way a finger would. `pick()` is
## tile-based, so a tap at the tile centre lands on it.
func _tap_an_enemy() -> void:
	var view: GameView = _game._view
	var target := _an_enemy()
	if target.is_empty():
		push_warning("preview_match: nobody to fight")
		return
	var world := Iso.tile_centre_to_world(target["tile"] as Vector2i)
	_game._on_tapped(view.get_global_transform_with_canvas() * world)


## The first entity belonging to somebody who is neither us nor gaia.
func _an_enemy() -> Dictionary:
	var view: GameView = _game._view
	var ids: Array = view.all_facts().keys()
	ids.sort()
	for id in ids:
		var f: Dictionary = view.facts_for(int(id))
		var owner := int(f.get("owner_id", 0))
		if owner != 0 and owner != Net.local_player_id() and bool(f.get("alive", true)):
			return f
	return {}


## True once an enemy is actually DEAD, not merely hurt.
##
## Waiting for the kill rather than the first scratch is what makes the shot
## worth taking: it proves the whole chain -- order, chase, reach, cooldown,
## damage, armour, and the hand-off to DeathSystem that turns a hit unit into a
## corpse. Cheap to wait for, too: five villagers at 3 damage every 20 ticks put
## a 30 hp archer down in about four seconds.
func _an_enemy_is_dead() -> bool:
	var view: GameView = _game._view
	for id in view.all_facts().keys():
		var f: Dictionary = view.facts_for(int(id))
		var owner := int(f.get("owner_id", 0))
		if owner == 0 or owner == Net.local_player_id():
			continue
		if not bool(f.get("alive", true)):
			return true
	return false


## Stand the three dropsites up on clear ground, COMPLETE, so their props can be
## looked at. Spawned straight into the host's world rather than placed through a
## command: what this step checks is RENDERING -- that a lumber camp draws its
## timber and an age-4 mill its crates -- and steps 16-17 already prove the
## placement path. Paying 30 s of build time per building to photograph a sprite
## would be waiting, not testing.
##
## Absolute tiles rather than offsets from the town centre, and the camera moves
## to them: the debug map's south-west quarter is the only sizeable patch clear
## of the town centre, the wood cluster, the gold and the berries all at once, and
## an offset that dodges every one of those is a number nobody can check by
## reading it. Stepping +6,-4 between the three sends them 320 px apart along the
## screen's horizontal (iso maps dx - dy to screen x), so all three sit side by
## side in one frame.
const DROPSITE_SITES := [
	[&"building.lumber_camp", Vector2i(10, 46)],
	[&"building.mining_camp", Vector2i(16, 42)],
	[&"building.mill", Vector2i(22, 40)],
]


func _stand_up_the_dropsites() -> void:
	var world: SimWorld = Net.host().world
	for spec in DROPSITE_SITES:
		var def_id: StringName = spec[0]
		if world.spawn_building(def_id, Net.local_player_id(), spec[1] as Vector2i,
				SimBuilding.Phase.COMPLETE) == null:
			push_warning("preview_match: no room for %s at %s" % [def_id, spec[1]])
	# Centre on the middle of the three. The camera opened on the town centre and
	# these are deliberately nowhere near it.
	var mid: BuildingDef = GameDataRegistry.building(DROPSITE_SITES[1][0])
	_game._camera.centre_on(Iso.tile_centre_to_world(
			(DROPSITE_SITES[1][1] as Vector2i) + mid.footprint / 2))


func _clear_selection() -> void:
	_game._view.select([] as Array[int])
	_game._refresh_panel()


func _report_enemies() -> void:
	var view: GameView = _game._view
	var ids: Array = view.all_facts().keys()
	ids.sort()
	for id in ids:
		var f: Dictionary = view.facts_for(int(id))
		var owner := int(f.get("owner_id", 0))
		if owner == 0 or owner == Net.local_player_id():
			continue
		print("  enemy %s  hp %d/%d  %s" % [f.get("def_id", &"?"), int(f.get("hp", 0)),
				int(f.get("max_hp", 0)), "alive" if bool(f.get("alive", true)) else "DEAD"])


func _town_centre_facts() -> Dictionary:
	var view: GameView = _game._view
	var ids: Array = view.all_facts().keys()
	ids.sort()
	for id in ids:
		var f: Dictionary = view.facts_for(int(id))
		if StringName(f.get("def_id", &"")) == &"building.town_center":
			return f
	return {}


func _shoot(name: String) -> void:
	var path := SHOT_DIR + name + ".png"
	get_viewport().get_texture().get_image().save_png(path)
	print("wrote ", ProjectSettings.globalize_path(path))
