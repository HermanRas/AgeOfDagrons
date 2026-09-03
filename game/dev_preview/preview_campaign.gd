## Dev check for 15.9: the whole campaign path, screen by screen, pressing the real
## buttons — CAMPAIGN list -> the scenario list with its locks -> PLAY -> a match with its
## briefing up.
##
## ## WHY A SCRIPT WHEN A PERSON CAN CLICK IT
##
## The owner walked this path by hand on 2026-09-03 and it worked. That answered the
## question for that build; it cannot answer it again next month. What this adds is a
## command anybody can run to get the same four pictures plus the numbers behind them —
## which row is locked, which is selected, what `campaign_progress.json` says, whether PLAY
## is live and what it launched.
##
## ⚠️ **IT PERFORMS THE SCENE CHANGES ITSELF, AND THAT IS THE ONE THING IT DOES NOT PROVE.**
## Both screens do their handoff and then call `get_tree().change_scene_to_file` — which
## from here would replace THIS script's own scene and end the run. So each press is made
## with the screen OUT of the tree, which is the same branch the suite uses (`is_inside_tree()`
## guards the scene change in both screens, deliberately, so a press is assertable). The
## preview then instantiates the next scene itself, **using the constant the screen it just
## pressed names** (`CampaignScreen._SCENARIO_SCENE`, `ScenarioScreen._GAME_SCENE`) rather
## than a path of its own, so a wrong constant shows up here as the wrong screen appearing.
##
## What it therefore covers: the two HANDOFFS (`ScenarioScreen.pending` and the config
## `launch()` builds), which is where a live object crossing between screens can be dropped.
## What it does not: that `change_scene_to_file` is reached. `test_campaign_screen` and
## `test_scenario_screen` cover the press; nothing covers the change, and nothing can
## without a second process.
##
## Usage:
##   Godot --path game res://dev_preview/preview_campaign.tscn
##       -- writes user://campaign_list.png, campaign_scenarios.png, campaign_in_match.png
##          and quits.
##   ... -- --scenario 3     -- pick a different mission off the list (1-based)
##   ... -- --interactive    -- stop after the scenario screen and leave it up.
extends Node

const SHOT_DIR := "user://"

const CAMPAIGN_SCENE := "res://scenes/menu/Campaign.tscn"

## Frames between steps, and the longer wait after the match is stood up -- the tracker has
## no numbers in it until the first snapshot has been drawn from.
const STEP_FRAMES := 15
const SETTLE_FRAMES := 45

var _frames := 0
var _step := 0
var _gap := STEP_FRAMES
var _interactive := false
## -1 IS "TAKE WHAT THE SCREEN CHOSE", WHICH IS NOT THE SAME AS 0. `ScenarioScreen.open()`
## selects the furthest unlocked mission, and scenario 1 is a real answer -- defaulting to
## 0 would have made `--scenario 1` indistinguishable from asking for nothing, which is
## exactly what it did on the first run.
var _want_scenario := -1

var _campaign_screen: CampaignScreen = null
var _scenario_screen: ScenarioScreen = null
var _game: Node = null


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_interactive = args.has("--interactive")
	var at := args.find("--scenario")
	if at >= 0 and at + 1 < args.size():
		# 1-based on the command line, the way the screen numbers them for the player, so
		# `--scenario 1` is index 0 and is a real request rather than the default.
		_want_scenario = maxi(0, int(args[at + 1]) - 1)

	_campaign_screen = load(CAMPAIGN_SCENE).instantiate() as CampaignScreen
	add_child(_campaign_screen)


func _process(_delta: float) -> void:
	_frames += 1
	if _frames < _gap:
		return
	_frames = 0
	_gap = STEP_FRAMES
	_advance()


func _advance() -> void:
	match _step:
		0:
			_shoot("campaign_list")
			_report_campaigns()
		1:
			_open_the_campaign()
		2:
			_shoot("campaign_scenarios")
			_report_scenarios()
			if _interactive:
				set_process(false)
				return
		3:
			_press_play()
			_gap = SETTLE_FRAMES
		4:
			_shoot("campaign_in_match")
			_report_match()
		_:
			get_tree().quit()
			return
	_step += 1


# ── the campaign list ───────────────────────────────────────────────────────

func _report_campaigns() -> void:
	var n := _campaign_screen.campaign_count()
	print("campaign list: %d campaign(s), empty notice=%s"
			% [n, _campaign_screen.showing_empty_notice()])
	# PRINTED, NOT RAISED. The one that shows up on a developer's machine every run is
	# *"'HowToPlay' in user://content/ is shadowed by the copy in scenarios/"* -- which is
	# the dev override doing exactly its job for anyone who has also installed the pack.
	# Warning on it would train the reader to ignore this line, which is where a real
	# complaint about a campaign would appear.
	for w in _campaign_screen.warnings():
		print("    warning from the loader: %s" % w)
	# ⚠️ THE NAME COMES FROM THE DEF, NOT FROM `button.text`. These rows are built from an
	# icon and two Labels inside a Button, so the Button's own `text` is EMPTY -- the first
	# version of this printed a column of blanks and read as a list of nameless campaigns.
	var defs := _campaign_screen.campaigns()
	for i in range(n):
		print("    [%d] %s" % [i, defs[i].name if i < defs.size() else "<no def>"])
	if n == 0:
		push_warning("preview_campaign: nothing installed -- the dev override reads"
				+ " res://../scenarios and is editor-only, so this is a real finding in an"
				+ " export and a broken checkout here")


## Press the first campaign's row, with the screen OUT OF THE TREE so its own scene change
## does not end the run, then stand up the screen it names. See the header.
func _open_the_campaign() -> void:
	if _campaign_screen.campaign_count() == 0:
		get_tree().quit(1)
		return
	remove_child(_campaign_screen)
	_campaign_screen.row(0).pressed.emit()
	var opened := _campaign_screen.last_opened()
	print("pressed campaign row 0 -> opened '%s', parked=%s"
			% [opened.name if opened != null else "<nothing>",
			ScenarioScreen.pending != null])
	if ScenarioScreen.pending == null:
		push_warning("preview_campaign: the row press parked no campaign -- the handoff"
				+ " between the two screens is what 15.5 is made of")
	_campaign_screen.queue_free()
	_campaign_screen = null

	# The constant the screen ITSELF names, not a path of this script's.
	_scenario_screen = load(CampaignScreen._SCENARIO_SCENE).instantiate() as ScenarioScreen
	add_child(_scenario_screen)


# ── the scenario list, and what is locked ───────────────────────────────────

func _report_scenarios() -> void:
	var s := _scenario_screen
	var c := s.campaign()
	print("scenario list: campaign='%s' progress=%d selected=%d play=%s"
			% [c.name if c != null else "<none>", s.progress(), s.selected_index(),
			s.play_enabled()])
	# ⚠️ THE LOCKS ARE THE POINT OF THIS PICTURE. `progress` is a completion COUNT and
	# therefore the index of the first locked row, so this table is what says whether a win
	# was recorded -- the same fact the owner reads off the screen by which rows are bright.
	# The name off the DEF and the lock off the BUTTON — see `_report_campaigns` for why the
	# button cannot supply the first.
	var defs: Array[ScenarioDef] = c.scenarios if c != null else ([] as Array[ScenarioDef])
	for i in range(s.row_count()):
		print("    [%d] %-36s %s%s" % [i,
				defs[i].name if i < defs.size() else "<no def>",
				"LOCKED" if s.row(i).disabled else "open",
				"   <- selected" if i == s.selected_index() else ""])
	if not s.play_note().is_empty():
		print("    note: %s" % s.play_note())

	if _want_scenario >= 0 and _want_scenario < s.row_count():
		s.select(_want_scenario)
		print("    selected scenario %d: play=%s %s"
				% [_want_scenario + 1, s.play_enabled(), s.play_note()])


# ── PLAY, and the match behind it ───────────────────────────────────────────

## Press the real PLAY button, out of the tree for `_open_the_campaign`'s reason, then do
## by hand the TWO LINES the tree would have run: park the config on `Net` and change to
## the game scene. `launch()` sets `_launched` either way, which is the suite's hook and is
## what makes the config readable here at all.
func _press_play() -> void:
	if not _scenario_screen.play_enabled():
		push_warning("preview_campaign: PLAY is disabled: %s" % _scenario_screen.play_note())
		get_tree().quit(1)
		return
	remove_child(_scenario_screen)
	_scenario_screen._play_button.pressed.emit()
	var cfg := _scenario_screen.launched()
	if cfg == null:
		push_warning("preview_campaign: PLAY built no config -- `launch()` refused where"
				+ " `play_enabled()` said it would not, which means the two have drifted")
		get_tree().quit(1)
		return
	print("pressed PLAY -> mode=%d objectives=%d campaign='%s' scenario_index=%d"
			% [cfg.mode, cfg.objectives.size(), cfg.campaign_folder, cfg.scenario_index])
	if cfg.campaign_folder.is_empty() or cfg.scenario_index < 0:
		push_warning("preview_campaign: the config carries no campaign row, so winning it"
				+ " would record no progress (15.7)")
	var game_scene: String = ScenarioScreen._GAME_SCENE
	_scenario_screen.queue_free()
	_scenario_screen = null

	Net.pending_match = cfg
	_game = load(game_scene).instantiate()
	add_child(_game)


func _report_match() -> void:
	var briefing: ScenarioBriefing = _game._briefing
	var tracker: ObjectiveTracker = _game._tracker
	print("in match: briefing open=%s (%d characters), tracker rows=%d"
			% [briefing.is_open(), briefing.message_text().length(), tracker.row_count()])
	for i in range(tracker.row_count()):
		print("    [%d] done=%s  %s" % [i, tracker.row_is_done(i), tracker.row_line(i)])
	if not briefing.is_open():
		push_warning("preview_campaign: the mission launched with its goal invisible")
	# A conquest mission carries no objectives and correctly shows no tracker, so this is a
	# warning only when the config that launched has some.
	if tracker.row_count() == 0 and not Net.match_config().objectives.is_empty():
		push_warning("preview_campaign: objectives were launched with nothing showing them")


func _shoot(name: String) -> void:
	var path := SHOT_DIR + name + ".png"
	get_viewport().get_texture().get_image().save_png(path)
	print("wrote ", ProjectSettings.globalize_path(path))
