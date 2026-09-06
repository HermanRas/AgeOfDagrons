## The SCENARIO screen (PLAN.md 15.5): one campaign's scenarios, and the button that
## starts one.
##
## Campaign title at the top, a scrolling column of scenario rows on the left with
## everything past `progress` locked, and a main panel carrying the campaign background,
## the selected scenario's title and description, and PLAY.
##
## ## SELECTING A ROW SWAPS THE PANEL. IT DOES NOT CHANGE SCENE.
##
## The owner's spec, and it is the reason this is one screen rather than a screen per
## scenario: the background is a 1920×1080 decode (`ContentImage`'s header) and re-entering
## a scene to read a different paragraph would pay for it again every time.
##
## ## HOW A CAMPAIGN GETS IN HERE: `pending`, ON `Net.pending_match`'s PRECEDENT
##
## A `CampaignDef` is a live object, not a path, so it cannot travel through
## `change_scene_to_file`. `Net.pending_match` already solves exactly this for a
## `MatchConfig` — the caller parks it, the next scene consumes it — and this is that
## pattern with the same shape and the same one-shot clear. **An autoload was the other
## option and was rejected**: PLAN.md 6.1's autoload table is exactly four, and a fifth for
## one handoff between two adjacent screens is a global to save a field.
##
## `open()` is public and takes the campaign directly, so the suite never touches `pending`
## and nor does anything that already has the object in hand.
##
## ## BUILT IN CODE, IN `_init()`
##
## `CampaignScreen`'s reasoning exactly: the row list is data discovered at runtime, and
## `_init()` is what lets `ScenarioScreen.new()` be a whole screen with no `SceneTree`.
## Nothing here touches `get_tree()` except leaving and launching.
##
## ## RESET PROGRESS LIVES HERE, AND IT CLEARS THIS CAMPAIGN ONLY
##
## Owner, 2026-09-06 (no PLAN.md row — Phase 15 had closed): *"add a reset button ... with an
## alert asking the user if they are sure they want to reset the progress of all scenarios;
## set progress back to 0"*, then, on seeing it built on `CampaignScreen`, *"the reset is per
## campaign, so on the progress tree page not the campaigns page."*
##
## The two halves of that correction go together and they are the same point: **a control
## belongs on the screen that shows the state it changes.** The campaign list shows a name
## and a blurb, so a reset there is a button whose effect you take on trust. This screen is a
## column of locks — that column *is* the progress — so a reset here visibly does the thing
## it says, and the campaign it belongs to is not in question because there is exactly one on
## screen.
##
## It follows that this screen must **redraw itself**, which `CampaignScreen` had nothing to
## redraw for: `_progress` is read once in `open()`, and a screen that cleared the file
## without rebuilding its rows would leave every mission looking unlocked until the player
## left and came back. `_on_reset_confirmed` re-reads and rebuilds.
##
## The press does nothing but ask. Everything that touches the file is behind
## `ConfirmOverlay`'s `confirmed` signal, so there is no path from one tap to a cleared
## campaign.
##
## ⚠️ **BOTH COLUMNS SCROLL, AND NEITHER IS DECORATION.** A `VBoxContainer` overflows — it
## does not clip, scroll or compress past its children's minimums — and the lobby shipped
## with its nav strip off the bottom of the screen for exactly that while every structural
## test passed. Three scenarios fit; a nine-mission campaign does not, and the description
## in the main panel is authored text of no fixed length.
class_name ScenarioScreen
extends Control

const _CAMPAIGN_SCENE := "res://scenes/menu/Campaign.tscn"
const _GAME_SCENE := "res://scenes/game/Game.tscn"

const _GROUND := Color(0.16862746, 0.11372549, 0.078431375, 1.0)
const _PARCHMENT := Color(0.9372549, 0.8784314, 0.7529412, 1.0)
const _GOLD := Color(0.8980392, 0.7215686, 0.25882354, 1.0)
const _DIM := Color(0.55, 0.5, 0.44, 1.0)

## RESET PROGRESS' ink, and `ConfirmOverlay`'s confirm button wears the same one so the
## button and the modal it opens are visibly one action.
##
## ⚠️ **A LIGHT CORAL, NOT A SATURATED RED, AND THAT WAS MEASURED RATHER THAN CHOSEN.** The
## first version was `#E65C5C`, the obvious "danger" red, and it is nearly invisible here:
## the theme's button plate is itself a dark red, so a mid red on it has almost no contrast
## and the button reads as **greyed out** — the one thing a live control must never look
## like, and the exact opposite of the warning intended. `campaign_reset_alert.png` from
## `preview_campaign` is what showed it; nothing in the suite could have.
const _DANGER := Color(1.0, 0.61960787, 0.5176471, 1.0)

## Scenario icons are authored 256×256 and drawn small — see `CampaignScreen.ICON_SIZE` for
## why the source is not shrunk instead.
const ICON_SIZE := 56
const ROW_HEIGHT := ICON_SIZE + 18

## Width of the scenario column. Fixed rather than a share of the window, because the main
## panel is the part that wants the room and a description is what grows.
const COLUMN_WIDTH := 280

## The campaign to open in the next `ScenarioScreen` built by a scene change. One-shot:
## `_init()` takes it and clears it, so a second visit with nothing parked shows the
## no-campaign notice rather than silently reopening the last one.
static var pending: CampaignDef = null

var _campaign: CampaignDef = null
var _progress := 0
var _selected := -1
var _rows: Array[Button] = []

var _heading: Label
var _list: VBoxContainer
var _art: TextureRect
var _title: Label
var _blurb: Label
var _note: Label
var _play_button: Button
var _reset_button: Button
var _confirm: ConfirmOverlay
var _toast: NoticeToast

## Set by `launch()` instead of changing scene when there is no tree — the suite's hook, and
## the reason `launch()` can be asserted on at all.
var _launched: MatchConfig = null

## Which progress file RESET PROGRESS clears. **A field with the real one as its default,
## and it is not a nicety — it is the only thing between the suite and the developer's own
## saved campaign.**
##
## `CampaignProgress` takes a `path` on every single function for exactly this reason, and
## its header records what happened the one time real `user://` state leaked into a test: a
## progress file written by hand for a play-test turned **this screen's** heading test into a
## failure with nothing to do with what it tested. That was a test *reading* it. This button
## **writes** it, so a test pressing the confirm button through the default would clear the
## progress of whoever ran the suite — silently, and once per run.
##
## Production never sets this; `open()` still reads through the default, because a screen
## that showed one file's locks and cleared another's would be worse than either.
## `test_scenario_screen` sets it before it presses anything.
var progress_path: String = CampaignProgress.USER_FILE


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = _GROUND
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 36)
	margin.add_theme_constant_override("margin_right", 36)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	add_child(margin)

	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 12)
	margin.add_child(page)

	_heading = Label.new()
	_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_heading.add_theme_color_override("font_color", _GOLD)
	UiFont.title(_heading, 28, true)
	page.add_child(_heading)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(body)

	body.add_child(_build_column())
	body.add_child(_build_panel())

	var footer := HBoxContainer.new()
	page.add_child(footer)
	var back := Button.new()
	back.text = "BACK"
	back.custom_minimum_size = Vector2(160, 52)
	UiFont.title(back, 20)
	back.pressed.connect(_on_back_pressed)
	footer.add_child(back)

	# RESET PROGRESS AT THE FAR END, not beside BACK. It is the only destructive control on
	# this screen and BACK is pressed often and without looking; the width of the footer
	# between them is the cheapest guard there is, and the modal is the real one. An
	# expanding spacer rather than an anchor, because the footer is in the page's FLOW --
	# a control pinned to the viewport can end up under the scenario column on a short one.
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	footer.add_child(spacer)

	_reset_button = Button.new()
	_reset_button.text = "RESET PROGRESS"
	_reset_button.custom_minimum_size = Vector2(280, 52)
	UiFont.title(_reset_button, 20)
	# NOT GATED ON THERE BEING PROGRESS TO CLEAR. Reading the file to decide would make this
	# screen's construction depend on real `user://` state -- the trap this screen's own
	# heading test fell into once already (see `progress_path`). A reset with nothing to
	# reset is a no-op that says so.
	_reset_button.add_theme_color_override("font_color", _DANGER)
	_reset_button.add_theme_color_override("font_hover_color", _DANGER)
	_reset_button.add_theme_color_override("font_pressed_color", _DANGER)
	_reset_button.add_theme_color_override("font_focus_color", _DANGER)
	_reset_button.pressed.connect(_on_reset_pressed)
	footer.add_child(_reset_button)

	_toast = NoticeToast.new()
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.position = Vector2(-NoticeToast.SIZE.x / 2.0, 16.0)
	add_child(_toast)

	# LAST, so it draws over the toast as well as over the two columns. Nothing raises a
	# banner while this is open today, but the ordering is the bug `GameScene` records paying
	# for -- an alert raised after an overlay is drawn BEHIND it -- and a modal a banner can
	# cover is a question the player cannot read.
	_confirm = ConfirmOverlay.new()
	_confirm.confirmed.connect(_on_reset_confirmed)
	add_child(_confirm)

	# ONE-SHOT, and cleared before `open()` rather than after: `open()` can push a warning,
	# and a static left set through an error is a campaign that reopens itself on the next
	# visit for no reason the player could see.
	if pending != null:
		var c := pending
		pending = null
		open(c)
	else:
		_show_no_campaign()


func _build_column() -> Control:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(COLUMN_WIDTH, 0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	return scroll


func _build_panel() -> Control:
	var panel := Control.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.clip_contents = true

	# THE CAMPAIGN BACKGROUND, behind the text and loaded once per campaign. `TextureRect`
	# with `EXPAND_IGNORE_SIZE` for the reason `Boot.tscn` was cropped on a phone for a
	# month: the default `EXPAND_KEEP_SIZE` makes the texture's own 1920×1080 the control's
	# MINIMUM, and a minimum size beats every anchor.
	_art = TextureRect.new()
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_art.set_anchors_preset(Control.PRESET_FULL_RECT)
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Dimmed, because this is a 1920×1080 illustration with a paragraph on top of it and
	# parchment text over a bright sky is unreadable.
	_art.modulate = Color(0.55, 0.55, 0.55, 1.0)
	panel.add_child(_art)

	var pad := MarginContainer.new()
	pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 22)
	panel.add_child(pad)

	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 10)
	pad.add_child(stack)

	_title = Label.new()
	_title.add_theme_color_override("font_color", _GOLD)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiFont.title(_title, 24, true)
	stack.add_child(_title)

	# The description scrolls on its own: it is authored text of no fixed length, and the
	# panel is the half of the screen that has to absorb that.
	var blurb_scroll := ScrollContainer.new()
	blurb_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	blurb_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	stack.add_child(blurb_scroll)

	_blurb = Label.new()
	_blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_blurb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_blurb.add_theme_color_override("font_color", _PARCHMENT)
	_blurb.add_theme_font_size_override("font_size", 16)
	blurb_scroll.add_child(_blurb)

	# Why PLAY is disabled, when it is. Its own line rather than a tooltip, because a
	# disabled button on a touch screen has nowhere to hover.
	_note = Label.new()
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.add_theme_color_override("font_color", _DIM)
	_note.add_theme_font_size_override("font_size", 14)
	_note.visible = false
	stack.add_child(_note)

	var play_row := HBoxContainer.new()
	play_row.alignment = BoxContainer.ALIGNMENT_END
	stack.add_child(play_row)

	_play_button = Button.new()
	_play_button.text = "PLAY"
	_play_button.custom_minimum_size = Vector2(200, 56)
	UiFont.title(_play_button, 22)
	_play_button.pressed.connect(_on_play_pressed)
	play_row.add_child(_play_button)

	return panel


## Show `c`, read its progress, and select the furthest scenario the player may enter.
func open(c: CampaignDef) -> void:
	_campaign = c
	# THROUGH `progress_path`, the same file RESET PROGRESS clears. A screen that showed one
	# file's locks and cleared another's would be worse than either.
	_progress = CampaignProgress.completed(c.folder, progress_path)
	_heading.text = c.name
	# ⚠️ RE-ENABLED HERE, because `_init()` disables it when nothing is parked and `open()` is
	# what arrives afterwards. Caught by `test_the_reset_button_is_on_the_screen`: a screen
	# reached through `open()` rather than through `pending` had a permanently dead RESET
	# button, which is the one failure mode a disabled-state guard can create by itself.
	_reset_button.disabled = false

	# ONCE PER CAMPAIGN, never per selection — `scenarios/README.md` is explicit that a
	# 1920×1080 background costs a real decode and must not be loaded for a list.
	_art.texture = ContentImage.load_texture(c.background_path)

	_rebuild_rows()

	# The furthest UNLOCKED scenario, which is the one a returning player wants: opening on
	# scenario 1 of a campaign they are eight missions into makes them scroll every visit.
	var open_at := mini(_progress, c.scenarios.size() - 1)
	select(maxi(0, open_at))


func _rebuild_rows() -> void:
	# Detach before freeing, and free immediately — `queue_free()` needs a tree to process
	# it and this screen is built without one all through the suite, so the deferred form
	# would leave the old rows in the list. Same trap `CampaignScreen.reload()` records.
	for row in _rows:
		_list.remove_child(row)
		row.free()
	_rows.clear()

	if _campaign == null:
		return
	for i in range(_campaign.scenarios.size()):
		var row := _build_row(_campaign.scenarios[i], i)
		_rows.append(row)
		_list.add_child(row)


## One scenario: its icon and its title. Locked rows are SHOWN AND DISABLED rather than
## hidden — a campaign whose list grows as you play it hides how long it is, and the point
## of the column is that the player can see what is ahead.
func _build_row(s: ScenarioDef, index: int) -> Button:
	var unlocked := _campaign.is_unlocked(index, _progress)
	var row := Button.new()
	row.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.toggle_mode = true
	# DISABLED FOR LOCKED ONLY, not for a broken scenario: an unplayable scenario must still
	# be SELECTABLE so the panel can explain itself. PLAY is the button that refuses.
	row.disabled = not unlocked
	row.pressed.connect(select.bind(index))

	var pad := MarginContainer.new()
	pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 9)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(pad)

	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(line)

	var holder := Control.new()
	holder.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tex := ContentImage.load_texture(s.icon_path)
	if tex != null:
		var art := TextureRect.new()
		art.texture = tex
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# A locked mission's picture is greyed rather than withheld — it is a signpost, and
		# hiding it would make the row look like an error.
		if not unlocked:
			art.modulate = Color(0.4, 0.4, 0.4, 1.0)
		holder.add_child(art)
	else:
		var plate := ColorRect.new()
		plate.color = Color(0.28, 0.2, 0.14, 1.0)
		plate.set_anchors_preset(Control.PRESET_FULL_RECT)
		plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(plate)
	line.add_child(holder)

	var label := Label.new()
	# NUMBERED FROM THE LIST, not from the folder name: `scenario_10` sorts before
	# `scenario_2` and the order is `campaign.json`'s declaration (see `CampaignDef`).
	label.text = "%d. %s" % [index + 1, s.name]
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.add_theme_color_override("font_color", _GOLD if unlocked else _DIM)
	label.add_theme_font_size_override("font_size", 16)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(label)

	return row


## Swap the main panel to scenario `index`. No scene change — see the class comment.
func select(index: int) -> void:
	if _campaign == null or index < 0 or index >= _campaign.scenarios.size():
		return
	_selected = index
	for i in range(_rows.size()):
		_rows[i].set_pressed_no_signal(i == index)

	var s := _campaign.scenarios[index]
	_title.text = "%d. %s" % [index + 1, s.name]
	_blurb.text = s.description

	var why := _why_not_playable(index)
	_play_button.disabled = not why.is_empty()
	_note.text = why
	_note.visible = not why.is_empty()


## Why PLAY is refused for `index`, or "" when it is not.
##
## ⚠️ **DELIBERATELY DOES NOT CALL `build_config()`.** That is the authority on whether a
## scenario can start, and it is also the function that READS THE SAVED MAP OFF DISK — a
## `MapFile.load_map` per row selection is a PNG decode plus an 18 KB JSON parse every
## time the player moves the highlight. So this is the cheap predicate and `launch()`
## still asks the real one; if the two ever disagree, `launch()` wins and says so in a
## toast rather than starting something broken.
##
## *(Before 2026-09-01 the expensive thing was `MapGenerator.generate` rather than a file
## read, which was the owner's correction and is now 11.3. The argument for a cheap
## predicate survived the change of what it was avoiding.)*
##
## **THE `mode == SCENARIO` CLAUSE IS GONE AS OF 15.2.** It said *"objective scenarios are
## not playable yet"*, and it was true and load-bearing for exactly one day: `ObjectiveSystem`
## evaluates them now, so scenarios 1 and 2 are as startable as scenario 3.
func _why_not_playable(index: int) -> String:
	var s := _campaign.scenarios[index]
	if not _campaign.is_unlocked(index, _progress):
		return "Locked — finish the previous scenario first."
	if not s.is_playable():
		# Written as a statement rather than a ternary: `"..." % x if c else "..."` parses
		# the way it should here and still reads like a bug every time somebody meets it.
		var problems := s.problems_or_self()
		if problems.is_empty():
			return "This scenario cannot be played."
		return "This scenario cannot be played: %s" % problems[0]
	return ""


## Start the selected scenario. Returns whether it actually started.
##
## `Net.pending_match` and then the scene change, which is the SOLO path `SkirmishScreen`
## already proves: `GameScene._ready()` calls `host_solo()` and consumes the config. A
## campaign is a hosted match on loopback with nobody invited, so it is that path exactly —
## it must NOT be `Net.start_match()`, which is for a lobby whose socket is already open.
func launch() -> bool:
	if _campaign == null or _selected < 0 or _selected >= _campaign.scenarios.size():
		return false
	var problems: Array[String] = []
	var cfg := _campaign.scenarios[_selected].build_config(problems)
	if cfg == null:
		# The real authority refused where `_why_not_playable` did not. Reported rather than
		# swallowed: it means the two have drifted, and a silent no-op is how a button ends
		# up doing nothing at all.
		var why := problems[0] if not problems.is_empty() else "this scenario cannot start"
		_say(why)
		push_warning("scenario '%s' refused to build a config: %s"
				% [_campaign.scenarios[_selected].folder, "; ".join(problems)])
		return false

	_launched = cfg
	if is_inside_tree():
		Net.pending_match = cfg
		get_tree().change_scene_to_file(_GAME_SCENE)
	return true


func _on_play_pressed() -> void:
	launch()


func _show_no_campaign() -> void:
	# Reachable by loading `Scenario.tscn` directly — from the editor, or from a scene
	# change that forgot to park a campaign. An empty screen with a dead PLAY would look
	# like a broken campaign rather than a wrong entrance.
	_heading.text = "CAMPAIGN"
	_title.text = "No campaign selected"
	_blurb.text = ("This screen shows one campaign's scenarios and is opened from the"
			+ " campaign list. Go back and choose a campaign.")
	_play_button.disabled = true
	_note.visible = false
	# There is no campaign to clear the progress OF. The button is otherwise never disabled;
	# this is the one state where pressing it could not name a target.
	_reset_button.disabled = true


func _say(text: String) -> void:
	# Guarded on the tree, not on the toast: `NoticeToast` fades with a tween and a tween
	# needs a `SceneTree`, and the suite never parents this screen.
	if is_inside_tree():
		_toast.show_message(text)


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(_CAMPAIGN_SCENE)


## RESET PROGRESS -> ask first. The owner's words, 2026-09-06: *"with an alert asking the
## user if they are sure they want to reset the progress of all scenarios"*.
##
## THE PRESS DOES NOTHING BUT ASK. Everything that touches the file is behind
## `_on_reset_confirmed`, reachable only from the modal's own signal, so there is no path
## from one tap to a cleared campaign and no second caller to keep in step.
##
## ⚠️ **THE MODAL NAMES THE CAMPAIGN**, which is the whole point of the button being on this
## screen rather than the list. "Reset progress?" on a screen that may be one of nine
## campaigns is a question the player cannot answer safely; *"This clears your progress
## through How To Play"* is.
##
## And it says what is lost in the PLAYER'S terms, not the file's. "Progress" is a number in
## a JSON file; what they have is unlocked missions, and the sentence that matters is that
## those lock again — which is a claim this screen then makes good on visibly, because the
## column beside them is those locks.
func _on_reset_pressed() -> void:
	if _campaign == null:
		return
	_confirm.open("RESET PROGRESS",
			"This clears your progress through %s." % _campaign.name
					+ " Every scenario but the first locks again, and this cannot be undone."
					+ "\n\nAre you sure?",
			"RESET")


## The deed, and the only place in the game that calls `CampaignProgress.reset`.
##
## ⚠️ **IT REDRAWS, WHICH IS WHY THE BUTTON BELONGS ON THIS SCREEN.** `_progress` is read
## once in `open()`, so clearing the file without rebuilding would leave every mission
## looking unlocked until the player left and came back — a reset that appears to have done
## nothing, on the one screen that can actually show it working. Re-read, rebuild the rows,
## and select scenario 1, because after a reset that is the only one open.
##
## **IT SAYS SO EITHER WAY.** A reset that failed — a read-only `user://`, a file held open
## by something else — looks exactly like one that worked. `CampaignProgress.reset` pushes a
## warning for the developer; this is the half the player can see.
func _on_reset_confirmed() -> void:
	if _campaign == null:
		return
	var ok := CampaignProgress.reset(_campaign.folder, progress_path)
	_progress = CampaignProgress.completed(_campaign.folder, progress_path)
	_rebuild_rows()
	select(0)
	# Written out rather than as `"..." % x if ok else "..."` -- that parses the way it should
	# and still reads like a bug every time somebody meets it, which `_why_not_playable`
	# above says in the same words.
	if ok:
		_say("%s progress reset" % _campaign.name)
	else:
		_say("Could not reset progress")


# ── readers, for the suite ───────────────────────────────────────────────────

func campaign() -> CampaignDef:
	return _campaign


func selected_index() -> int:
	return _selected


func progress() -> int:
	return _progress


func row(index: int) -> Button:
	return _rows[index] if index >= 0 and index < _rows.size() else null


func row_count() -> int:
	return _rows.size()


func play_enabled() -> bool:
	return not _play_button.disabled


func play_note() -> String:
	return _note.text if _note.visible else ""


func reset_button() -> Button:
	return _reset_button


## The "are you sure" modal, so a test can assert it opened and press one of its two buttons
## rather than calling the handler it guards.
func confirm_overlay() -> ConfirmOverlay:
	return _confirm


func panel_title() -> String:
	return _title.text


func panel_description() -> String:
	return _blurb.text


func has_background() -> bool:
	return _art.texture != null


## The config the last successful `launch()` built. The suite's window onto a launch that
## cannot change scene because there is no tree to change.
func launched() -> MatchConfig:
	return _launched
