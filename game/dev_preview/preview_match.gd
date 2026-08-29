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
## Where the occlusion step sent the villagers, so the wait can tell "arrived
## behind the building" from "happened to already be behind something".
var _occlusion_target := Vector2i.ZERO
## Where the camera was when the placing finger reached the edge strip, so the next
## step can say whether the map actually slid rather than photographing one and
## hoping. Paired with the screen position the finger was left at.
var _edge_pan_from := Vector2.ZERO
var _edge_pan_target := Vector2.ZERO
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
			_report_panel_hitboxes()
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
			# THE MARCH RIDES THIS STEP because it is the last one with no wait of its
			# own, and it needs one (2026-08-29). `DEBUG_ENEMY_SQUAD` moved twenty tiles
			# out -- MapGen's header carries the owner's report that moved it -- which
			# puts it behind the FOG, so step 18 had nothing to tap and warned "nobody to
			# fight". That was the fog working, not the tap being broken.
			#
			# After the screenshot, so `match_building` still photographs the house going
			# up with its builders on it rather than walking away from it.
			_march_on_the_enemy_squad()
			_wait_until(_an_enemy_is_visible)
		18:
			# Combat (4.13), through the tap path rather than a hand-built command:
			# what is being checked is that tapping an enemy with an army in hand
			# MEANS attack, which is a decision `GameView.tap_action()` makes and a
			# submitted AttackCommand would bypass entirely.
			#
			# Villagers, because the town centre is the only trainer on the debug
			# map and villagers are all it makes. A peasant mob at damage 3 apiece
			# is a slow way to kill an archer and a perfectly real one.
			#
			# THE ARCHER FIGHTS BACK NOW (4.12), which it did not when this step was
			# written: it is DEFENSIVE by default, so the peasant mob is a real trade
			# rather than free damage, and some of them die. That is the mechanic
			# working -- the project owner ruled on it the day it landed.
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
		22:
			# Occlusion (3.1). Walk the villagers to the far side of the town
			# centre -- the side the camera cannot see past -- and photograph what
			# the player is left with. They used to be drawn standing ON the roof;
			# they should now be hidden, with a player-coloured rim over the
			# building saying they are back there.
			_send_villagers_behind_the_town_centre()
			_wait_until(_someone_is_behind_the_town_centre)
		23:
			_report_occlusion()
			_shoot("match_occluded")
		24:
			# The idle walk (7.1). Last, because it wants a spread-out map: by now
			# the villagers have fought, built and walked to opposite corners, so a
			# tap that does NOT move the camera is visible as a tap that did
			# nothing. Halt them first and wait for the count to come back up --
			# run straight after the occlusion step there was exactly ONE idle
			# unit, and a walk of one visits the same villager twice and proves
			# nothing about the cycling.
			_stop_everyone()
			_wait_until(_several_are_idle)
		25:
			# Pressed through the badge's own signal, like _press_advance --
			# setting the selection directly would pass with the button unwired.
			_walk_the_idle_badge()
		26:
			_shoot("match_idle")
		27:
			# A mill with its four fields, to look at the four crops. Spawned
			# straight into the world rather than placed through commands: what is
			# being checked is that four plots on four tiles draw four DIFFERENT
			# pictures (visuals.json `variants`), and steps 16-17 already prove the
			# placement path.
			_stand_up_a_farm()
		28:
			# And then send everyone to farm one plot, which is the other half of
			# what there is to look at: five villagers spread ACROSS the crop rather
			# than queued on its corner, standing on ground that used to be a wall.
			_farm_the_first_field()
			_wait_until(_somebody_is_farming)
		29:
			_report_field_crops()
			_shoot("match_fields")
		30:
			# Behind the GOLD, not behind a building. Nothing but buildings was ever
			# an occluder, so a unit walking behind a rock vanished with no outline
			# (project owner, 2026-08-17). The seam is 244 px on a one-tile
			# footprint, which is also why the screen-column band had to widen.
			_send_villagers_behind_the_gold()
			_wait_until(_someone_is_behind_the_gold)
		31:
			_report_occlusion()
			_shoot("match_occluded_by_gold")
		32:
			# BUILD MODE HELD OPEN, which nothing else here does -- steps 16-17 enter it
			# and place in the same breath. Entering it LOCKS THE CAMERA so one finger
			# can drag the ghost, and until 2026-08-21 the only ways out were Escape and
			# right-click: on a phone, with no legal spot on screen and no way to pan to
			# one, a placement could be neither finished nor abandoned. The project owner
			# found it in a two-device match, with the ghost stuck to their thumb.
			#
			# Reselects a villager first: by this point the script has sent them off
			# farming and behind the gold, and the Build action only exists on a
			# villager's panel.
			_select_a_villager()
			_open_build_menu()
		33:
			_enter_build_mode_and_hold()
		34:
			_report_build_mode()
			_shoot("match_build_mode_cancellable")
		35:
			_press_cancel_build()
		36:
			_report_build_mode()
			_shoot("match_build_mode_cancelled")
		37:
			# EDGE-PAN, the other half of the same dead end (BUGS.md). Cancel let a phone
			# player OUT of a placement they could not finish; edge-pan lets them finish
			# it, by sliding the map when the ghost is dragged into the edge strip. Driven
			# through the placement handlers the InputRouter calls rather than by setting
			# `edge_push` directly, because the WIRING is the thing in doubt -- exactly as
			# with the cancel button one step above.
			_select_a_villager()
			_open_build_menu()
		38:
			_start_edge_pan()
		39:
			# The camera moved in the frames BETWEEN these two steps, driven by
			# CameraRig._process with the finger held still against the edge.
			_report_edge_pan()
			_shoot("match_edge_pan")
		40:
			_start_disarmed_placement()
		41:
			_report_disarmed()
		42:
			# THE MINIMAP'S FOUR CORNER PAGES (8.2b), all four of them real buttons since
			# 2026-08-21. Pressed through the actual TextureButtons rather than by calling
			# the handlers: these were disabled placeholders with MOUSE_FILTER_IGNORE until
			# today, and "the page opens" proves nothing about whether a thumb on the
			# corner of the minimap can open it.
			#
			# A MARKET FIRST, or the trade page is a screenful of correctly greyed buttons
			# and a line explaining why. Spawned straight into the world like the dropsites
			# above: what is under test is the page, and the placement path is proven by
			# steps 16-17.
			_stand_up_a_market()
		43:
			_press_corner(&"trade")
		44:
			_report_page(_game._market, "market")
			_shoot("match_market")
		45:
			# A real trade, through the real button, so the page is exercised and not just
			# photographed. Shot on the NEXT step: the command round-trips through a
			# snapshot, and shooting here would photograph the stockpile before it moved.
			_buy_at_the_market()
		46:
			_report_market_trade()
			_shoot("match_market_traded")
		47:
			_press_corner(&"techtree")
		48:
			_report_page(_game._tech_tree, "tech tree")
			_shoot("match_techtree")
		49:
			_press_corner(&"chat")
		50:
			_report_page(_game._chat, "chat")
			_shoot("match_chat")
		51:
			# SETTINGS, which is where the pause menu went when the age header's pause
			# button was retired. Closes the chat page on the way, which is the other half
			# of the rule: one page at a time.
			_press_corner(&"settings")
		52:
			_report_settings()
			_shoot("match_settings")
		53:
			# Back out of it, so the resign below opens it again the way a player would
			# rather than finding it already up.
			_game._pause_menu._on_resume_pressed()
		54:
			# THE [X] THAT DROPS THE SELECTION (8.8), on a town centre because that is the
			# tallest panel this map can produce and the button's whole design constraint is
			# vertical: it has exactly 40 px between the control-group stack and the panel's
			# own ceiling, and a button pushed under that stack keeps DRAWING and stops
			# taking taps. Only a live rect can tell those apart.
			_select_a_town_centre()
		55:
			_report_the_clear_button()
			_shoot("match_clear_button")
		56:
			_press_the_clear_button()
		57:
			# Shot a step later, like every other press here: the panel repaints off the
			# next snapshot, so photographing the same frame would show it still open.
			_report_the_clear_button()
			_shoot("match_cleared")
		58:
			# RESEARCH (PLAN.md 9.3). The blacksmith is not on the debug map, so it is
			# stood up the same way the market is -- through the host world, the
			# documented solo-only exception. Age 4 by now, so all twelve of its
			# technologies are unlocked and the grid is full.
			_stand_up_a_blacksmith()
		59:
			_select_the_blacksmith()
			_open_research()
		60:
			_report_research()
			_shoot("match_research")
		61:
			# Through the detail slot's own press, not a hand-built ResearchCommand:
			# what is in doubt is the whole chain -- a tile with no icon and only a
			# label draws and takes a tap, `SelectionPanel` turns it into
			# `research_requested`, `GameScene` into a command, and the queue moves.
			_research_the_first_thing()
		62:
			_report_research_queue()
			_shoot("match_researching")
		63:
			# RESIGNING (12.1e). Left until last on purpose: it ends the match, so nothing
			# after it would have a match to photograph.
			#
			# Until today this button called `Net.leave()` and changed scene -- a local act
			# the simulation never heard about. It now submits a `ResignCommand`, and what
			# is in doubt is exactly that: that a real press reaches the sim and comes back
			# as a defeat. Pressed through `pressed.emit()` on the real button for the same
			# reason the cancel-build one is.
			_resign_the_match()
		64:
			_report_resigned()
			_shoot("match_resigned")
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


## Enter build mode and STAY there, which is the state the bug lived in.
##
## Through the build grid's own slot rather than by setting `_placing_def_id`, so this
## exercises the path a player takes -- and so it cannot pass with the grid unwired.
func _enter_build_mode_and_hold() -> void:
	# Straight into placement rather than through the build grid, which by this point in
	# the script is a paged age-4 menu whose contents are not what is under test -- and
	# the grid-to-placement path is already proven by steps 16-17, which place a real
	# building through it. What is under test is the way OUT.
	_game._enter_placement(&"building.house")


## Press the button a phone player now has. Deliberately `pressed.emit()` on the real
## Button rather than calling `_exit_placement()`, because what is in doubt is the
## WIRING: an unconnected button would leave a touch player exactly as stuck as before.
func _press_cancel_build() -> void:
	var button: Button = _game._cancel_build
	if button == null or not button.visible:
		push_warning("preview_match: no cancel-build button to press")
		return
	button.pressed.emit()


## Enter placement, put a finger down in the middle, and drag it to the LEFT edge --
## then let go of nothing. The finger stays there, and the map should start sliding.
func _start_edge_pan() -> void:
	_game._enter_placement(&"building.house")
	var view_rect := get_viewport().get_visible_rect().size
	# Down in the middle first, which is also what ARMS the edge strip: a drag that
	# begins inside the strip is ignored by it, because the build grid opens along the
	# bottom edge and the tap that picks a building leaves a finger exactly there.
	_game._on_placement_pressed(view_rect * 0.5)
	# Hard against the left edge, where the push is at full speed.
	_edge_pan_target = Vector2(2.0, view_rect.y * 0.5)
	_game._on_placement_drag(_edge_pan_target)
	_edge_pan_from = _game._camera.position
	print("  edge pan: finger at %s, push %s, camera %s"
			% [_edge_pan_target, _game._camera.edge_push, _edge_pan_from])


func _report_edge_pan() -> void:
	var now: Vector2 = _game._camera.position
	var moved := now - _edge_pan_from
	print("  edge pan: camera %s -> %s (moved %s), still placing %s, ghost visible %s"
			% [_edge_pan_from, now, moved, _game._placing_def_id != &"", _game._ghost.visible])
	if moved.x >= 0.0:
		push_warning("preview_match: the left edge did not pan the camera left")
	if _game._placing_def_id == &"":
		push_warning("preview_match: edge-pan dropped the placement it was serving")


## The guard, which is the part a screenshot cannot show: a placement whose FIRST
## touch lands inside the strip must not scroll, or picking a building from the grid
## along the bottom edge would send the map flying on its own.
func _start_disarmed_placement() -> void:
	_game._exit_placement()
	_game._enter_placement(&"building.house")
	var view_rect := get_viewport().get_visible_rect().size
	_game._on_placement_pressed(Vector2(2.0, view_rect.y * 0.5))
	_edge_pan_from = _game._camera.position
	print("  disarmed: pressed inside the strip, push %s" % _game._camera.edge_push)


func _report_disarmed() -> void:
	var moved: Vector2 = _game._camera.position - _edge_pan_from
	print("  disarmed: camera moved %s (want zero)" % moved)
	if moved != Vector2.ZERO:
		push_warning("preview_match: a placement that began at the edge panned anyway")
	_game._exit_placement()


# ── the minimap's corner pages (PLAN.md 8.2b) ───────────────────────────────

## Somewhere clear of everything else this script has built. The market is 8x8 and
## the debug map is 64x64, so it goes in the top-left corner the script never uses.
const MARKET_SITE := Vector2i(3, 3)


## A finished market, so the trade page has something to license its buttons with.
func _stand_up_a_market() -> void:
	var world: SimWorld = Net.host().world
	var me := Net.local_player_id()
	if world.spawn_building(GameDataRegistry.market_building(), me, MARKET_SITE,
			SimBuilding.Phase.COMPLETE, true) == null:
		push_warning("preview_match: no room for a market at %s" % MARKET_SITE)
		return
	# And something to trade WITH, or every button is correctly greyed for lack of
	# funds and the picture says nothing about the page.
	var p := world.player_for(me)
	for kind in [&"food", &"wood", &"stone", &"gold"]:
		p.stock[kind] = maxi(int(p.stock.get(kind, 0)), 2000)


## Press one of the four corner buttons -- the REAL TextureButton, found by name on
## `GameScene.corner_buttons`. They were disabled placeholders with
## MOUSE_FILTER_IGNORE until 2026-08-21, so "the page opened" is not evidence that a
## thumb on the corner of the minimap opens it.
func _press_corner(name: StringName) -> void:
	var button: TextureButton = _game.corner_buttons.get(name)
	if button == null:
		push_warning("preview_match: no corner button named %s" % name)
		return
	print("  corner %s: rect %s, filter %d, disabled %s"
			% [name, button.get_global_rect(), button.mouse_filter, button.disabled])
	if button.disabled or button.mouse_filter == Control.MOUSE_FILTER_IGNORE:
		push_warning("preview_match: the %s corner button cannot be pressed" % name)
	button.pressed.emit()


## Whether a page is actually open and how big it came out. The rect is the half a
## screenshot cannot argue with: a page laid out to zero size is invisible and looks
## exactly like a page that never opened.
func _report_page(page: HudPanel, label: String) -> void:
	print("  %s: open %s, rect %s" % [label, page.is_open(), page.get_global_rect()])
	if not page.is_open():
		push_warning("preview_match: the %s page did not open" % label)
	# ONE AT A TIME. They are full-screen overlays, so two open at once means one
	# invisibly on top of the other still taking the taps meant for the visible one.
	var others: Array[String] = []
	for other in [_game._chat, _game._tech_tree, _game._market]:
		if other != page and other.is_open():
			others.append(other.title())
	if not others.is_empty():
		push_warning("preview_match: %s opened with %s still up" % [label, others])


## Buy a lot at the market, through the page's own button. What is in doubt is the
## whole chain: a press emits a signal, `GameScene` turns it into a command, the
## server validates it against a market it can see, and the stockpile moves.
func _buy_at_the_market() -> void:
	var world: SimWorld = Net.host().world
	var me := Net.local_player_id()
	var kinds := GameDataRegistry.market_kinds()
	if kinds.is_empty():
		push_warning("preview_match: no market prices declared")
		return
	_market_kind = kinds[0]
	_market_before = int(world.player_for(me).stock.get(_market_kind, 0))
	_market_gold_before = int(world.player_for(me).stock.get(
			GameDataRegistry.market_currency(), 0))

	for row in _game._market._exchange_box.get_children():
		for child in row.get_children():
			if child is Button and child.get_meta(&"kind", &"") == _market_kind \
					and bool(child.get_meta(&"buying", false)):
				print("  market: buying %s, button '%s', disabled %s"
						% [_market_kind, child.text, child.disabled])
				if child.disabled:
					push_warning("preview_match: the buy button is greyed with a market up")
				child.pressed.emit()
				return
	push_warning("preview_match: no buy button for %s" % _market_kind)


var _market_kind: StringName = &""
var _market_before := 0
var _market_gold_before := 0

## The wolf `_stand_up_a_farm` drops onto a crop, kept so `_report_field_crops` can
## measure it against the field it is standing on (2026-08-28).
var _wolf_on_the_field: SimUnit = null


func _report_market_trade() -> void:
	var world: SimWorld = Net.host().world
	var p := world.player_for(Net.local_player_id())
	var currency := GameDataRegistry.market_currency()
	var after := int(p.stock.get(_market_kind, 0))
	var gold_after := int(p.stock.get(currency, 0))
	print("  market: %s %d -> %d, %s %d -> %d"
			% [_market_kind, _market_before, after, currency,
			_market_gold_before, gold_after])
	if after <= _market_before:
		push_warning("preview_match: the buy never reached the simulation")
	if gold_after >= _market_gold_before:
		push_warning("preview_match: the buy was free")


func _report_settings() -> void:
	print("  settings: pause menu visible %s, pages open %s"
			% [_game._pause_menu.visible,
			[_game._chat.is_open(), _game._tech_tree.is_open(), _game._market.is_open()]])
	if not _game._pause_menu.visible:
		push_warning("preview_match: the settings corner button did not open the menu")
	if _game._chat.is_open() or _game._tech_tree.is_open() or _game._market.is_open():
		push_warning("preview_match: settings opened over a page it should have closed")


## Open the pause menu and concede, both through the real controls.
func _resign_the_match() -> void:
	var pause: PauseMenu = _game._pause_menu
	pause.open()
	var button: Button = pause._resign_button
	if button == null:
		push_warning("preview_match: no resign button to press")
		return
	print("  resign: pause open, submitting as player %d" % Net.local_player_id())
	button.pressed.emit()
	# The step machinery's own STEP_FRAMES gap before the next step is what gives the
	# command time to land: it is queued for a tick boundary, and the defeat has to come
	# back round through a snapshot before the result screen can know about it.


func _report_resigned() -> void:
	var world: SimWorld = Net.host().world
	var me := Net.local_player_id()
	print("  resign: player %d defeated %s, match_over %s, winner %d, result shown %s"
			% [me, world.player_for(me).defeated, world.match_over, world.winner_id,
			_game._result.is_shown()])
	if not world.player_for(me).defeated:
		push_warning("preview_match: the resign never reached the simulation")
	if not _game._result.is_shown():
		push_warning("preview_match: conceded, but nothing on screen says so")


func _report_build_mode() -> void:
	var placing: StringName = _game._placing_def_id
	var button: Button = _game._cancel_build
	print("  build mode: placing %s, cancel button visible %s, camera locked %s"
			% [placing if placing != &"" else "(nothing)",
			button != null and button.visible, _game._camera.locked])


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
	# top-left. Off the town centre's right-hand corner: a few tiles' walk from the
	# villagers ringing it, and on screen where neither the selection panel nor the
	# minimap covers it.
	var footprint: Vector2i = tc.get("footprint", Vector2i.ONE)
	var tc_origin: Vector2i = (tc["tile"] as Vector2i) - footprint / 2
	# Two tiles off the right wall and level with the middle of it: clear of the
	# gold, and clear of the skirmish squad's own tiles, which units do not block
	# but which would put two enemy soldiers inside the shot's house.
	var origin := _free_house_spot(tc_origin + Vector2i(footprint.x + 1, 4))
	if origin.x < 0:
		push_warning("preview_match: nowhere to put a house near the town centre")
		return
	_game._enter_placement(&"building.house")
	_game._on_placement_released(
			view.get_global_transform_with_canvas() * Iso.tile_to_world(origin))


## `preferred` if a house fits there, otherwise the nearest spot outward that one
## does. Vector2i(-1, -1) if there is nowhere at all.
##
## THE PREVIEW USED TO TAKE A FIXED TILE, and the project owner found what that
## costs: the gold cluster moved onto that tile, the placement was refused, and an
## interactive run sat in build mode waiting for a human to finish the step. A
## hand-picked tile is a promise about the whole map, and this file cannot keep one
## -- the map is content and changes for its own reasons.
##
## Searched in the same widening-ring order MapGen uses for villagers, so the
## answer is deterministic and the fallback lands as near the preferred spot as it
## can. The warning is deliberate: drifting off the chosen tile means the shot is
## framed differently, and that should be visible in the log rather than a surprise
## in the picture.
func _free_house_spot(preferred: Vector2i) -> Vector2i:
	var world: SimWorld = Net.host().world
	var bd: BuildingDef = GameDataRegistry.building(&"building.house")
	var size := bd.footprint if bd != null else Vector2i.ONE

	if world.map.can_place_building(SimMap.footprint_rect(preferred, size)):
		return preferred

	for ring in range(1, 12):
		for dy in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dy)) != ring:
					continue          # only the new ring; inner ones were searched
				var candidate := preferred + Vector2i(dx, dy)
				if not world.map.can_place_building(SimMap.footprint_rect(candidate, size)):
					continue
				push_warning("preview_match: %s is taken, building at %s instead"
						% [preferred, candidate])
				return candidate
	return Vector2i(-1, -1)


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


## Walk the villagers out to the enemy squad, so the player can SEE it before step 18
## tries to tap it (2026-08-29).
##
## **NEEDED BECAUSE THE SQUAD MOVED, AND THE FOG IS WHY.** `DEBUG_ENEMY_SQUAD` used to
## sit three tiles off the town centre wall, inside the opening vision circle, so
## `_an_enemy()` found it in the client's facts on tick 1. It is twenty tiles out now
## (see MapGen's header for the owner's report that moved it), which is well outside
## every starting unit's `los` — so the client is not told it exists and the tap had
## nothing to aim at. It reported as `nobody to fight`, which is exactly what a fogged
## enemy SHOULD look like from here.
##
## THE DESTINATION COMES FROM THE HOST'S WORLD, which is the documented solo-only
## exception `_preview_placement` and `_on_train_requested` already take: the client
## cannot know where to march when the whole point is that it cannot see. What is under
## test in step 18 is the TAP, not the scouting, so handing the walk a fogged answer is
## a fixture doing its job rather than a shortcut past one.
##
## ⚠️ **THE STANDOFF MUST BE INSIDE THE VILLAGER'S OWN `los`, WHICH IS 4.** The first
## attempt used 6, reasoning that arriving outside the archer's `GUARD_RADIUS` would let
## the tap name an unengaged target rather than re-ordering a fight already under way.
## That is a nice property and it is unreachable: a villager who stops six tiles away
## **cannot see six tiles**, so the enemy never entered the client's facts and
## `_tap_an_enemy` warned "nobody to fight" from a squad the villagers were standing next
## to. The wait before it passed on a flicker -- somebody caught a glimpse in passing --
## which is worse than failing, because it moved the failure one step downstream.
##
## 2, so they arrive with it plainly lit. The archer opens fire as they close, and the
## tap then re-orders the same fight -- which still tests what this step is for:
## `GameView.tap_action()` has to DECIDE that a tap on an enemy means attack, and it makes
## that decision whether or not a fight is already running.
const _MARCH_STANDOFF := 2


func _march_on_the_enemy_squad() -> void:
	var world: SimWorld = Net.host().world if Net.host() != null else null
	if world == null:
		push_warning("preview_match: no host to ask where the enemy is")
		return
	var ids: Array = world.entities.keys()
	ids.sort()
	for id in ids:
		var e = world.entities[id]
		if not (e is SimUnit) or not e.alive:
			continue
		if e.owner_id == 0 or e.owner_id == Net.local_player_id():
			continue
		_select_all_villagers()
		Net.submit_command(MoveCommand.new(Net.local_player_id(),
				(_game._view as GameView).movable_selection(),
				e.tile() - Vector2i(_MARCH_STANDOFF, _MARCH_STANDOFF)))
		return
	push_warning("preview_match: the host has no enemy either")


func _an_enemy_is_visible() -> bool:
	return not _an_enemy().is_empty()


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
## Moved two tiles down on 2026-08-17: the resource clusters were pushed six tiles
## clear of the town centre to free up building space, and the forest landed on
## (17..20, 40..42) -- straight through the mining camp's old spot, which reported
## itself as "no room for building.mining_camp". The +6,-4 stepping is unchanged.
const DROPSITE_SITES := [
	[&"building.lumber_camp", Vector2i(8, 52)],
	[&"building.mining_camp", Vector2i(14, 48)],
	[&"building.mill", Vector2i(20, 44)],
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


# ── research (PLAN.md 9.3) ──────────────────────────────────────────────────

## Away from the town centre and the dropsites, on ground this map leaves open.
const BLACKSMITH_SITE := Vector2i(6, 3)

var _blacksmith_id: int = 0


## A finished blacksmith, so the Research row has something to hang off. Stood up
## through the host world for `_stand_up_a_market`'s reason and with the same
## solo-only caveat: this is not a client operation and is not pretending to be one.
func _stand_up_a_blacksmith() -> void:
	var world: SimWorld = Net.host().world
	var me := Net.local_player_id()
	var b := world.spawn_building(&"building.blacksmith", me, BLACKSMITH_SITE,
			SimBuilding.Phase.COMPLETE, true)
	if b == null:
		push_warning("preview_match: no room for a blacksmith at %s" % BLACKSMITH_SITE)
		return
	_blacksmith_id = b.id
	# And something to pay with, or every tile is correctly greyed for lack of funds
	# and the picture says nothing about the row.
	var p := world.player_for(me)
	for kind in [&"food", &"wood", &"stone", &"gold"]:
		p.stock[kind] = maxi(int(p.stock.get(kind, 0)), 3000)
	var def: BuildingDef = GameDataRegistry.building(&"building.blacksmith")
	_game._camera.centre_on(Iso.tile_centre_to_world(BLACKSMITH_SITE + def.footprint / 2))


func _select_the_blacksmith() -> void:
	if _blacksmith_id == 0:
		return
	_game._view.select([_blacksmith_id] as Array[int])
	_game._refresh_panel()


## Open the Research row, through the real action slot. It EXPANDS rather than
## ordering anything, so this is a view toggle and the order comes from the grid.
func _open_research() -> void:
	var panel: SelectionPanel = _game._panel
	for slot in panel._action_slots:
		if slot.visible and slot.action != null and slot.action.id == &"research":
			panel._on_action_pressed(slot.action)
			return
	push_warning("preview_match: the blacksmith offers no Research row")


## WHAT THE GRID ACTUALLY DREW, printed because a screenshot of twelve unlabelled
## tiles cannot be told from a screenshot of twelve empty ones. The owner asked for
## "blank action tiles with only labels filled" (2026-08-29) and the label is
## therefore the whole content of a tile -- so it is the thing to check.
func _report_research() -> void:
	var panel: SelectionPanel = _game._panel
	var shown: Array[String] = []
	var blank := 0
	for slot in panel._detail_slots:
		if not slot.visible or slot.action == null:
			continue
		shown.append("%s%s" % [slot.action.label,
				"" if slot.action.enabled else " (locked)"])
		if slot.action.label.strip_edges().is_empty():
			blank += 1
	print("  research: %d tiles -- %s" % [shown.size(), ", ".join(shown)])
	if shown.is_empty():
		push_warning("preview_match: the research grid is empty")
	if blank > 0:
		push_warning("preview_match: %d research tiles have no label and no icon, "
				% blank + "so they are invisible")


## Press the first tile that is actually available.
func _research_the_first_thing() -> void:
	var panel: SelectionPanel = _game._panel
	for slot in panel._detail_slots:
		if slot.visible and slot.action != null and slot.action.enabled \
				and String(slot.action.id).begins_with("research:"):
			panel._on_detail_pressed(slot.action)
			return
	push_warning("preview_match: nothing on the research grid could be pressed")


func _report_research_queue() -> void:
	var world: SimWorld = Net.host().world
	var b := world.get_entity(_blacksmith_id) as SimBuilding
	if b == null:
		push_warning("preview_match: the blacksmith is gone")
		return
	var queued: Array[String] = []
	for entry in b.queue:
		queued.append("%s %s %d/%d" % [entry["kind"], entry["def_id"],
				entry["progress"], entry["total"]])
	print("  research queue: %s" % ("(empty)" if queued.is_empty() else ", ".join(queued)))
	if queued.is_empty():
		push_warning("preview_match: the press never reached the simulation")


func _clear_selection() -> void:
	_game._view.select([] as Array[int])
	_game._refresh_panel()


## Press the [X], through the real Button rather than by calling `_clear_selection()`.
## The same reasoning as `_press_cancel_build`: an unconnected button leaves a touch
## player exactly as stuck as they were, and calling the handler proves the handler.
func _press_the_clear_button() -> void:
	var button: Button = _game._panel._clear_button
	if button == null or not _game._panel.visible:
		push_warning("preview_match: no selection panel to clear")
		return
	button.pressed.emit()


## THE ONE MEASUREMENT THIS BUTTON NEEDS, and it cannot be taken headlessly.
##
## `ClearSelectionButton.SIZE` is 40 because that is exactly what is left between the
## control-group stack (which ends at y 364) and the selection panel's ceiling on a
## 648 px canvas. The failure mode if that is ever wrong is silent: the stack is added
## to the HUD after the panel, so Godot hit-tests it first, and the overlapping strip
## of the [X] goes on drawing while refusing taps -- the minimap corner-button trap.
## A screenshot cannot show that and a headless test cannot see the real viewport, so
## the two rects are printed and compared here.
func _report_the_clear_button() -> void:
	var panel: SelectionPanel = _game._panel
	print("clear button: panel %s visible %s" % [panel.get_global_rect(), panel.visible])
	if not panel.visible:
		print("  selection cleared -- panel is down")
		return

	var x_rect: Rect2 = panel._clear_button.get_global_rect()
	var groups_rect: Rect2 = _game._groups_hud.get_global_rect()
	print("  [X] at %s, control groups end at y %.0f" % [x_rect, groups_rect.end.y])
	if x_rect.intersects(groups_rect):
		push_warning("preview_match: the [X] is under the control-group stack, "
				+ "which is hit-tested first -- part of it will be silently dead")
	var screen := get_viewport().get_visible_rect().size.y
	if x_rect.position.y < 0.0 or x_rect.end.y > screen:
		push_warning("preview_match: the [X] is off the screen")


## Where the build grid's slots actually ARE, and whether a tap at each one
## reaches the button or falls through to the map.
##
## Reported live on the real HUD because the project owner found three of the
## five build buttons doing nothing (2026-08-16) -- the villager walked to the
## ground under the icon instead, which is what happens when NO Control consumes
## the press and `InputRouter` picks it up as a world tap. A rect is what tells a
## button that is not there from a button that is there and deaf.
func _report_panel_hitboxes() -> void:
	var panel: SelectionPanel = _game._panel
	print("panel rect  ", panel.get_global_rect())
	print("details grid ", panel._details_grid.get_global_rect())
	for slot in panel._detail_slots:
		if not slot.visible or slot.action == null:
			continue
		var r := slot.get_global_rect()
		var hit := panel.get_viewport().gui_get_focus_owner()   # keep the API warm
		print("  %-22s rect %s  disabled %s  filter %d  in-panel %s" % [
				slot.action.id, r, slot.disabled, slot.mouse_filter,
				panel.get_global_rect().encloses(r)])
		hit = hit          # unused; the rects above are the evidence


## Order every villager to the north-west of the town centre -- up-screen of it,
## where the building stands between them and the camera -- and put the camera
## back on the town centre so the shot frames the thing being tested.
func _send_villagers_behind_the_town_centre() -> void:
	var tc := _town_centre_facts()
	if tc.is_empty():
		return
	var centre: Vector2i = tc["tile"]
	var footprint: Vector2i = tc.get("footprint", Vector2i.ONE)
	# Two tiles clear of the north-west corner: behind the sprite, and not so far
	# back that Occlusion.BEHIND_TILES stops calling it hidden.
	var behind := centre - footprint / 2 - Vector2i(2, 2)

	_occlusion_target = behind
	_select_all_villagers()
	var view: GameView = _game._view
	Net.submit_command(MoveCommand.new(Net.local_player_id(),
			view.movable_selection(), behind))
	_game._camera.centre_on(Iso.sub_to_world(tc["tile"] as Vector2i * SimWorld.SUBTILE))


## True once a villager has ARRIVED at the spot behind the building and been
## marked hidden.
##
## Both halves matter. "Anybody is occluded" fired instantly the first time,
## because the villagers were still standing where the battle left them and two
## of those happened to be behind the town centre's north flank -- a true answer
## to the wrong question, and the shot went off before the order had been walked.
func _someone_is_behind_the_town_centre() -> bool:
	var view: GameView = _game._view
	for id in view.all_facts().keys():
		var f: Dictionary = view.facts_for(int(id))
		var v := view.pool.get_view(int(id))
		if v == null or not v.occluded:
			continue
		if (f.get("tile", Vector2i.ZERO) as Vector2i - _occlusion_target).length() <= 3.0:
			return true
	return false


## Which units the view thinks are hidden, and where everyone actually is. The
## picture cannot answer either question on its own: a villager that never set
## off looks the same as one that arrived somewhere unhelpful.
func _report_occlusion() -> void:
	var view: GameView = _game._view
	var ids: Array = view.all_facts().keys()
	ids.sort()
	for id in ids:
		var f: Dictionary = view.facts_for(int(id))
		if not bool(f.get("is_unit", false)):
			continue
		var v := view.pool.get_view(int(id))
		if v == null:
			continue
		print("  unit %-18s tile %s  owner %d  occluded %s" % [
				f.get("def_id", &"?"), f.get("tile", Vector2i.ZERO),
				int(f.get("owner_id", 0)), v.occluded])


## A mill and the four fields one mill will carry, on clear ground in the map's
## south-east quarter, with the camera moved to them.
##
## The four spots are the arrangement `test_fields.gd` uses -- two plots down each
## side of the mill, none overlapping -- because that is the layout the max_per_host
## rule was written against. Field origins are top-left tiles; the mill is 5x4 and
## each field 6x6.
const FARM_MILL := Vector2i(40, 44)


func _stand_up_a_farm() -> void:
	var world: SimWorld = Net.host().world
	var mill := world.spawn_building(&"building.mill", Net.local_player_id(), FARM_MILL,
			SimBuilding.Phase.COMPLETE)
	if mill == null:
		push_warning("preview_match: no room for the mill at %s" % FARM_MILL)
		return

	var fields: Array[SimBuilding] = []
	for offset in [Vector2i(-6, -6), Vector2i(-6, 0), Vector2i(5, -6), Vector2i(5, 0)]:
		var f := world.spawn_building(&"building.field", Net.local_player_id(),
				FARM_MILL + offset, SimBuilding.Phase.COMPLETE)
		if f == null:
			push_warning("preview_match: no room for a field at %s" % (FARM_MILL + offset))
		else:
			fields.append(f)

	# A WOLF STANDING ON THE CROP (project owner, 2026-08-28: *"wolf renders behind the
	# field i am unable to target it for attack"*). A field is the only building a unit
	# routinely stands INSIDE, because it is walkable -- and `_in_front_of_any` had the
	# case written and unreachable, so the wolf got neither the sort lift nor an
	# outline and simply vanished under the wheat.
	#
	# On the LAST field, which is on the far side of the mill from the one
	# `_farm_the_first_field` sends everybody to: a predator dropped among five
	# villagers turns this step into a battle and the crop shot into a fight scene.
	if not fields.is_empty():
		_wolf_on_the_field = world.spawn_unit(&"unit.wolf", 0, fields[-1].tile())
		if _wolf_on_the_field == null:
			push_warning("preview_match: no room for the wolf on the field")

	_game._camera.centre_on(Iso.tile_centre_to_world(FARM_MILL))


## Walk the villagers up-screen of the largest gold seam -- behind it, where the
## sprite stands between them and the camera -- and frame the seam.
func _send_villagers_behind_the_gold() -> void:
	var view: GameView = _game._view
	var seam := _largest_gold_tile()
	if seam == Vector2i.ZERO:
		push_warning("preview_match: no gold to hide behind")
		return

	# Two tiles up and left: behind the sprite, and well inside BEHIND_TILES.
	_occlusion_target = seam - Vector2i(2, 2)
	_select_all_villagers()
	Net.submit_command(MoveCommand.new(Net.local_player_id(),
			view.movable_selection(), _occlusion_target))
	_game._camera.centre_on(Iso.tile_centre_to_world(seam))


## The tile of the biggest gold node on the map -- size class 2, the 244 px seam.
func _largest_gold_tile() -> Vector2i:
	var world: SimWorld = Net.host().world
	var ids := world.entities.keys()
	ids.sort()
	var best := Vector2i.ZERO
	var best_size := -1
	for id in ids:
		var n := world.get_entity(int(id)) as SimResourceNode
		if n == null or n.kind != &"gold":
			continue
		if n.size_class > best_size:
			best_size = n.size_class
			best = n.tile()
	return best


func _someone_is_behind_the_gold() -> bool:
	var view: GameView = _game._view
	for id in view.all_facts().keys():
		var f: Dictionary = view.facts_for(int(id))
		var v := view.pool.get_view(int(id))
		if v == null or not v.occluded:
			continue
		if (f.get("tile", Vector2i.ZERO) as Vector2i - _occlusion_target).length() <= 3.0:
			return true
	return false


## Send every villager to the nearest of the four plots. Through the ordinary
## command, so the per-unit gather spots are the ones a player's tap would get.
func _farm_the_first_field() -> void:
	var view: GameView = _game._view
	var field := _first_field_id()
	if field == 0:
		push_warning("preview_match: no field to farm")
		return
	_select_all_villagers()
	Net.submit_command(GatherCommand.new(Net.local_player_id(),
			view.movable_selection(), field))


func _first_field_id() -> int:
	var view: GameView = _game._view
	var ids: Array = view.all_facts().keys()
	ids.sort()
	for id in ids:
		if StringName(view.facts_for(int(id)).get("def_id", &"")) == &"building.field":
			return int(id)
	return 0


## True once a villager is standing ON a field and carrying food off it. Both
## halves matter: "somebody is carrying food" was true from the berry bushes long
## before this step, and "somebody is on the crop" would be true of a villager that
## merely walked across it.
func _somebody_is_farming() -> bool:
	var view: GameView = _game._view
	var world: SimWorld = Net.host().world
	for id in view.all_facts().keys():
		var u := world.get_entity(int(id)) as SimUnit
		if u == null or u.carry_amount <= 0 or u.carry_kind != &"food":
			continue
		var host := world.get_entity(u.gather_node_id) as SimBuilding
		if host != null and host.def_id == &"building.field":
			return true
	return false


## Which crop each plot drew. The picture shows four fields; only this says whether
## they are four DIFFERENT ones, and a screenshot of four identical plots looks
## exactly like variants that are not wired.
## DOES THE WOLF DRAW OVER THE CROP IT IS STANDING ON, measured rather than looked at.
##
## The project owner's report was *"wolf renders behind the field i am unable to target
## it for attack"*, and a picture is a poor witness here: at map zoom a wolf half hidden
## in wheat and a wolf correctly on top of it are a few pixels apart, and the wheat is
## the same colour as the wolf. Godot Y-sorts by `position.y`, so the comparison IS the
## bug -- greater y draws later, i.e. in front.
##
## Prints both sort positions and the wolf's `draw_offset`, because the lift and the
## offset must cancel: the node is moved down-screen by `_ADJACENT_TO_BUILDING_BONUS`
## to win the sort and the art is moved back up by the same amount, so a wolf that
## draws in the right PLACE and the wrong ORDER is a different fault from one drawn a
## screen and a half away (`GameView` records that second one from 2026-08-20).
func _report_the_wolf_on_the_crop() -> void:
	if _wolf_on_the_field == null:
		return
	var view: GameView = _game._view
	var wolf := view.pool.get_view(_wolf_on_the_field.id)
	if wolf == null:
		push_warning("preview_match: the wolf on the crop has no view")
		return

	var tile: Vector2i = view.facts_for(_wolf_on_the_field.id).get("tile", Vector2i.ZERO)
	var ids: Array = view.all_facts().keys()
	ids.sort()
	for id in ids:
		var f: Dictionary = view.facts_for(int(id))
		if StringName(f.get("def_id", &"")) != &"building.field":
			continue
		var rect := Rect2i(f["tile"] - f["footprint"] / 2, f["footprint"])
		if not rect.has_point(tile):
			continue
		var field := view.pool.get_view(int(id))
		if field == null:
			continue
		print("  wolf at %s stands on the field at %s: wolf sort y %.1f, field sort y %.1f"
				% [tile, rect, wolf.position.y, field.position.y])
		print("    wolf draw offset %s (cancels the sort lift)" % wolf.draw_offset)
		if wolf.position.y <= field.position.y:
			push_warning("preview_match: the wolf sorts BEHIND the crop it is standing on")
		# Drawn where it stands, not where it sorts.
		var drawn := wolf.position + wolf.draw_offset
		if absf(drawn.y - Iso.tile_centre_to_world(tile).y) > 1.0:
			push_warning("preview_match: the wolf is drawn %.0f px from the tile it is on"
					% absf(drawn.y - Iso.tile_centre_to_world(tile).y))
		return
	print("  the wolf is not standing on a field -- nothing to compare")


func _report_field_crops() -> void:
	var view: GameView = _game._view
	var ids: Array = view.all_facts().keys()
	ids.sort()
	var seen: Array[String] = []
	var plots := 0
	for id in ids:
		var f: Dictionary = view.facts_for(int(id))
		if StringName(f.get("def_id", &"")) != &"building.field":
			continue
		var v := view.pool.get_view(int(id))
		if v == null:
			continue
		plots += 1
		print("  field at %s draws %s" % [f.get("tile", Vector2i.ZERO), v.visual_id])
		if not seen.has(String(v.visual_id)):
			seen.append(String(v.visual_id))
	print("  %d distinct crop(s) across %d plots" % [seen.size(), plots])
	_report_the_wolf_on_the_crop()

	# Where the farmers actually ended up, which the picture cannot tell you: five
	# on one corner and five spread over the crop look similar at this zoom.
	var world: SimWorld = Net.host().world
	var on_crop := 0
	var tiles: Array[Vector2i] = []
	for id in ids:
		var u := world.get_entity(int(id)) as SimUnit
		if u == null or u.task != SimUnit.Task.GATHER:
			continue
		var host := world.get_entity(u.gather_node_id) as SimBuilding
		if host == null or host.def_id != &"building.field":
			continue
		if host.footprint_rect().has_point(u.tile()):
			on_crop += 1
		if not tiles.has(u.tile()):
			tiles.append(u.tile())
	print("  %d farmer(s) standing on a crop, on %d distinct tiles" % [on_crop, tiles.size()])


## Halt every villager, so there is a spread-out set of idle units for the badge
## to walk. The same StopCommand the panel's Stop button issues.
func _stop_everyone() -> void:
	_select_all_villagers()
	Net.submit_command(StopCommand.new(Net.local_player_id(),
			(_game._view as GameView).movable_selection()))
	_clear_selection()


func _several_are_idle() -> bool:
	return (_game._view as GameView).idle_villager_ids(Net.local_player_id()).size() >= 3


## Tap the idle badge once per idle villager and print where each tap landed.
##
## The count of DISTINCT villagers is what matters and what the printout is for: a
## walk that visits the same villager five times looks identical in a screenshot
## to one that visits five, and both look identical to a badge whose count is
## right and whose button does nothing. The line also prints the population the
## resource panel is showing, which is the OTHER counter and must not agree with
## this one by coincidence.
func _walk_the_idle_badge() -> void:
	var view: GameView = _game._view
	var badge: IdleVillagerBadge = _game._idle_badge
	var idle := view.idle_villager_ids(Net.local_player_id())
	print("idle badge reads %d; view has %d idle: %s; population %s" % [
			badge.count, idle.size(), idle, _game._hud.population()])

	var visited: Array[int] = []
	# One more tap than there are idle units, so the wrap is exercised too.
	for i in range(idle.size() + 1):
		badge._on_pressed()
		var landed: int = _game._view.selection.primary()
		if not visited.has(landed):
			visited.append(landed)
		print("  tap %d -> unit %d at %s, camera %s" % [i + 1, landed,
				view.facts_for(landed).get("tile", Vector2i.ZERO), _game._camera.position])
	print("  visited %d distinct of %d idle" % [visited.size(), idle.size()])


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
