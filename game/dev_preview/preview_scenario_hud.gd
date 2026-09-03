## Dev check for 15.6: what a SCENARIO's match HUD actually looks like -- the briefing
## modal, the objective tracker beside the control-group stack, and an `alert` row's banner.
##
## ## WHY THIS EXISTS WHEN `test_objective_tracker.gd` IS GREEN
##
## Because none of the three faults this widget can have are expressible in a headless
## test. A Control outside a tree has never had a layout pass, so its size is whatever its
## `custom_minimum_size` says and nothing has ever been positioned against anything else:
## a tracker that overlaps the control-group stack, runs under the age header, or grows off
## the bottom of a 648 px viewport passes every assertion in that file. The lobby's fold and
## the CANCEL BUILD button sitting on top of the minimap were both found this way and by
## nothing else.
##
## It drives the REAL `Game.tscn` through the REAL launch path -- `Net.pending_match` and
## then the scene, which is what `ScenarioScreen.launch()` does -- so what is photographed
## is the game and not a mock-up of it.
##
## ## IT INJECTS AN `alert` ROW, AND SAYS SO LOUDLY
##
## No shipped scenario has one (`ObjectiveDef.Output.ALERT` is authored by 16.6's Map
## Conditions screen, which is unbuilt), so the banner half of 15.6 has no content to
## exercise it. Rather than photograph a feature with nothing in it, this appends one alert
## row to the config it launches: *own a house* -> a banner. **The injected row is this
## script's and is not in `scenario.json`** -- if a real one is ever authored, delete this.
##
## The row is appended, never inserted, for the reason the tracker's own header gives:
## `objective_progress` is indexed by position in the full list, so putting the alert first
## would renumber the two win rows the panel is drawn from.
##
## Usage:
##   Godot --path game res://dev_preview/preview_scenario_hud.tscn
##       -- writes user://scenario_hud_*.png and quits.
##   ... -- --scenario 2      -- a different mission (1-based, as the player counts them)
##   ... -- --interactive     -- leaves it running to play with instead.
extends Node

const SHOT_DIR := "user://"

## The first snapshot only arrives after `SimHost` has stepped, and the tracker draws from
## it -- a shot before that is a photograph of a panel that has never had a number in it.
const SETTLE_FRAMES := 45
const STEP_FRAMES := 15

## The campaign this drives. The only one that ships; named rather than "the first one"
## so a second campaign appearing does not silently change what is photographed.
const CAMPAIGN := "HowToPlay"

## The alert row's text. LONG ON PURPOSE (> `GameScene._SHORT_ALERT_CHARS`), because the
## paragraph banner is the half of `NoticeToast` that had never had a caller and had never
## been positioned by anybody -- see its `_resize`.
const ALERT_TEXT := "A house is up. Keep training villagers until you have fourteen."

var _game: Node = null
var _frames := 0
var _step := 0
var _interactive := false
var _scenario_index := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_interactive = args.has("--interactive")
	var at := args.find("--scenario")
	if at >= 0 and at + 1 < args.size():
		# 1-based on the command line, because that is how the scenario screen numbers them
		# for the player. Clamped rather than trusted.
		_scenario_index = maxi(0, int(args[at + 1]) - 1)

	var cfg := _config()
	if cfg == null:
		get_tree().quit(1)
		return
	Net.pending_match = cfg
	_game = load("res://scenes/game/Game.tscn").instantiate()
	add_child(_game)


## The scenario's own config, off disk, through `ScenarioDef.build_config` -- the same call
## the PLAY button makes. Returns null having said why.
func _config() -> MatchConfig:
	var campaign: CampaignDef = null
	for c in Campaigns.new().discover():
		if c.folder == CAMPAIGN:
			campaign = c
	if campaign == null:
		push_error("preview_scenario_hud: no campaign '%s' found" % CAMPAIGN)
		return null
	if _scenario_index >= campaign.scenarios.size():
		push_error("preview_scenario_hud: %s has %d scenarios, asked for %d"
				% [CAMPAIGN, campaign.scenarios.size(), _scenario_index + 1])
		return null

	var s := campaign.scenarios[_scenario_index]
	var problems: Array[String] = []
	var cfg := s.build_config(problems)
	if cfg == null:
		push_error("preview_scenario_hud: %s refused to build a config: %s"
				% [s.folder, "; ".join(problems)])
		return null
	print("scenario %d: %s -- mode=%d objectives=%d objective_player=%d"
			% [_scenario_index + 1, s.name, cfg.mode, cfg.objectives.size(),
			cfg.objective_player_id])

	var alert := ObjectiveDef.from_dict({"subject": "building", "id": "building.house",
			"owner": "self", "compare": ">=", "value": 1, "output": "alert",
			"text": ALERT_TEXT}, problems)
	if alert != null:
		cfg.objectives.append(alert)
		print("  + injected an alert row at index %d (this script's, not the file's)"
				% (cfg.objectives.size() - 1))
	return cfg


func _process(_delta: float) -> void:
	if _interactive or _game == null:
		return
	_frames += 1
	if _frames < SETTLE_FRAMES + _step * STEP_FRAMES:
		return
	_advance()


## One action per step, and A SHOT IS A STEP OF ITS OWN -- `preview_match`'s rule, and it
## is sharper here than anywhere: the tracker only changes when the next SNAPSHOT arrives,
## so a spawn and a photograph in the same frame photograph the panel before it heard.
func _advance() -> void:
	match _step:
		0:
			_shoot("scenario_hud_briefing")
			_report_briefing()
		1:
			_dismiss_briefing()
		2:
			_shoot("scenario_hud_start")
			_report_tracker("at the opening")
			_report_geometry()
		3:
			_stand_up_a_house()
		4:
			_shoot("scenario_hud_ticked")
			_report_tracker("after a house")
			_report_alert()
		_:
			get_tree().quit()
			return
	_step += 1


# ── the briefing ────────────────────────────────────────────────────────────

func _report_briefing() -> void:
	var b: ScenarioBriefing = _game._briefing
	print("briefing: shown=%s open=%s  %d characters"
			% [b.is_shown(), b.is_open(), b.message_text().length()])
	if not b.is_open():
		push_warning("preview_scenario_hud: the briefing did not open -- a scenario"
				+ " launching with its goal invisible is the 15.2 defect returning")


## Through the real X, not `close()`. On this project a button wired to nothing has twice
## looked exactly like a working one.
func _dismiss_briefing() -> void:
	_game._briefing.close_button().pressed.emit()
	print("briefing: dismissed through the X; open=%s" % _game._briefing.is_open())


# ── the tracker ─────────────────────────────────────────────────────────────

## PRINT WHAT THE PANEL SAYS, not only that it is there. `preview_projectiles`' lesson: at
## 1:1 a small thing being wrong and a small thing being absent look identical, and here
## the failure mode is subtler still -- a row showing the RIGHT number against the WRONG
## target is a correct-looking panel.
func _report_tracker(when: String) -> void:
	var t: ObjectiveTracker = _game._tracker
	print("tracker %s: visible=%s rows=%d" % [when, t.visible, t.row_count()])
	for i in range(t.row_count()):
		print("    [%d] objective %d  done=%s  %s"
				% [i, t.row_index(i), t.row_is_done(i), t.row_line(i)])
	if t.row_count() == 0:
		push_warning("preview_scenario_hud: no rows -- a scenario whose objectives the"
				+ " player cannot see is what 15.6 exists to end")


## THE CHECK NO HEADLESS TEST CAN MAKE. Sizes exist only after a layout pass inside a tree,
## so every one of these numbers is unavailable to `test_objective_tracker.gd`; two of the
## three faults it looks for have shipped before in other widgets.
func _report_geometry() -> void:
	var t: ObjectiveTracker = _game._tracker
	var rect := t.get_global_rect()
	var view := get_viewport().get_visible_rect()
	print("tracker rect: %s   viewport: %s" % [rect, view.size])
	if not view.encloses(rect):
		push_warning("preview_scenario_hud: the tracker is off the screen at %s" % rect)
	for named in [["control groups", _game._groups_hud], ["resource HUD", _game._hud]]:
		var other: Control = named[1]
		if other == null:
			continue
		var theirs := other.get_global_rect()
		print("    vs %s: %s" % [named[0], theirs])
		if rect.intersects(theirs):
			push_warning("preview_scenario_hud: the tracker overlaps the %s" % named[0])


# ── the alert, and what fires it ────────────────────────────────────────────

## A finished house for the objective player, which ticks scenario 1's first win row AND
## satisfies the injected alert -- one act, both halves of 15.6 in one photograph.
##
## SPAWNED RATHER THAN BUILT, `preview_scenario_win._satisfy`'s reasoning: building one
## properly means driving a villager for a minute of simulated time, and what is under the
## camera here is the panel, not the economy. A spawned house is the same entity a built
## one is, which is the only property `ObjectiveSystem._census` cares about.
func _stand_up_a_house() -> void:
	var host := Net.host()
	if host == null:
		push_warning("preview_scenario_hud: no host -- a scenario is a solo hosted match")
		return
	var world: SimWorld = host.world
	var pid := world.objective_player_id if world.objective_player_id > 0 \
			else Net.local_player_id()
	var tile := _clear_tile(world)
	if world.spawn_building(&"building.house", pid, tile,
			SimBuilding.Phase.COMPLETE, true) == null:
		push_warning("preview_scenario_hud: no room for a house at %s" % tile)
		return
	print("stood up a completed house for player %d at %s" % [pid, tile])


## A tile with nothing on it, a good way from the middle. Walks outward rather than
## trusting one spot -- a generated map has water on it and the town centre is 10x10.
## `is_passable(tile, Domain.LAND)`, because `SimMap.is_walkable` does not exist and
## calling it threw twice a run in the first version of `preview_scenario_win`.
func _clear_tile(w: SimWorld) -> Vector2i:
	var size := w.map.size
	for radius in range(6, maxi(size.x, size.y)):
		var t := Vector2i(radius, radius)
		if w.map.in_bounds(t) and w.map.is_passable(t, SimMap.Domain.LAND):
			return t
	return Vector2i(2, 2)


func _report_alert() -> void:
	var toast: NoticeToast = _game._toast
	print("alert banner: %s   long=%s   rect=%s"
			% [toast.current_text(), toast.is_long(), toast.get_global_rect()])
	if toast.current_text() != ALERT_TEXT:
		push_warning("preview_scenario_hud: the alert row did not reach the banner")
		return
	# THE CENTRING, MEASURED RATHER THAN EYEBALLED. `show_long_message` changes the width
	# under an offset written once, and before 15.6 nothing had ever called it -- so a
	# 720 px banner hung 200 px right of centre with nothing in `GameScene` to blame.
	var rect := toast.get_global_rect()
	var view := get_viewport().get_visible_rect()
	var drift := absf(rect.get_center().x - view.size.x * 0.5)
	print("    banner centre is %.1f px off the screen's axis" % drift)
	if drift > 2.0:
		push_warning("preview_scenario_hud: the alert banner is %.1f px off centre" % drift)


func _shoot(name: String) -> void:
	var path := SHOT_DIR + name + ".png"
	get_viewport().get_texture().get_image().save_png(path)
	print("wrote ", ProjectSettings.globalize_path(path))
