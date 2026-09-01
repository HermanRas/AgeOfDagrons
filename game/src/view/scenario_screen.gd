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
var _toast: NoticeToast

## Set by `launch()` instead of changing scene when there is no tree — the suite's hook, and
## the reason `launch()` can be asserted on at all.
var _launched: MatchConfig = null


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

	_toast = NoticeToast.new()
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.position = Vector2(-NoticeToast.SIZE.x / 2.0, 16.0)
	add_child(_toast)

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
	_progress = CampaignProgress.completed(c.folder)
	_heading.text = c.name

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
## scenario can start, and it is also the function that GENERATES THE MAP — a 192×192
## `MapGenerator.generate` per row selection would make browsing the list cost a map each
## time. So this is the cheap predicate and `launch()` still asks the real one; if the two
## ever disagree, `launch()` wins and says so in a toast rather than starting something
## broken.
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
	if s.mode == ScenarioDef.Mode.SCENARIO:
		# 15.2. Said in the player's terms rather than as a row number, and stated rather
		# than hidden: two of the three shipped How To Play scenarios are this case, and a
		# PLAY button that simply did nothing would read as a broken game.
		return "Objective scenarios are not playable yet — only the last-man-standing ones."
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


func _say(text: String) -> void:
	# Guarded on the tree, not on the toast: `NoticeToast` fades with a tween and a tween
	# needs a `SceneTree`, and the suite never parents this screen.
	if is_inside_tree():
		_toast.show_message(text)


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(_CAMPAIGN_SCENE)


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
