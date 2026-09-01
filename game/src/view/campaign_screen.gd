## The CAMPAIGN screen (PLAN.md 15.4): one row per campaign found on disk, and the way
## into a campaign.
##
## WHY THIS SCREEN EXISTS AT ALL. PLAY and MULTIPLAYER both opened the skirmish screen,
## because 1.6's whole design is one screen where a lobby is that screen with a slot set to
## Open — so the two buttons genuinely had nowhere different to go, and PLAY was the button
## with no meaning of its own. PLAY is the campaign and MULTIPLAYER is the skirmish/lobby
## screen, so each button leads somewhere only it leads.
##
## ## IT WAS A PLACEHOLDER UNTIL 2026-09-01, AND WHAT REPLACED IT IS A BODY
##
## The frame, the scene change and the way back were built first and on purpose (see the
## note under `_on_back_pressed`), so 15.4 is the list going into a room that already
## existed. **The last front-door destination that was a placeholder rather than a
## feature.**
##
## ## BUILT IN CODE, AND `Campaign.tscn` IS NOW A SHELL
##
## `HelpScreen`'s reasoning, and it applies harder here: **the row list is DATA, and
## discovered at runtime at that.** There is no number of rows to author — a player may
## have one campaign installed or nine — so a `.tscn` could not hold this list even in
## principle. Authoring it in code also sidesteps AGENT_GAME_CODER.md §6: Godot rewrites a
## `.tscn`'s layout properties whenever the project is open in the editor.
##
## Built in `_init()` rather than `_ready()`, which is `HelpScreen`'s pattern and is what
## makes the screen testable headlessly — `CampaignScreen.new()` is a whole screen with no
## `SceneTree` anywhere near it. Nothing here touches `get_tree()` except leaving.
##
## ## ⚠️ THE LIST SCROLLS, AND THAT IS NOT DECORATION
##
## **A `VBoxContainer` overflows. It does not clip, scroll, or compress past its children's
## minimum sizes.** The lobby shipped with its bottom nav strip off the bottom of the screen
## for exactly this reason and every structural test passed, because a test that asks a node
## for its rect gets the rect it asked for whether or not the window contains it. One
## campaign fits; the list is built inside a `ScrollContainer` from the first line anyway,
## because the failure only appears on the machine with the content and by then the screen
## reads as broken rather than as full.
class_name CampaignScreen
extends Control

const _MAIN_MENU_SCENE := "res://scenes/menu/MainMenu.tscn"

## The credits and help screens' ground colour, so the pages behind the front door are
## recognisably the same room.
const _GROUND := Color(0.16862746, 0.11372549, 0.078431375, 1.0)
const _PARCHMENT := Color(0.9372549, 0.8784314, 0.7529412, 1.0)
const _GOLD := Color(0.8980392, 0.7215686, 0.25882354, 1.0)

## Drawn size of a campaign icon. The files are authored 256×256 (`scenarios/README.md`)
## and are drawn far smaller, which is deliberate: there is no mipmap on a texture built by
## `ContentImage` (no `.import` sidecar), so the alternative to a big source scaled down is
## a small source scaled up, and that looks worse on every device.
const ICON_SIZE := 88

## Tall enough for the icon plus its margins, so a description of any length grows the row
## rather than squeezing the icon.
const ROW_HEIGHT := ICON_SIZE + 24

var _campaigns: Array[CampaignDef] = []
var _warnings: Array[String] = []
var _rows: Array[Button] = []

var _list: VBoxContainer
var _empty: Label
var _back_button: Button
var _toast: NoticeToast

## The last campaign `open_campaign` was asked for. **This is 15.5's seam**, and it is a
## field rather than a signal because the thing that replaces `open_campaign` is a scene
## change, not a listener. It is also what lets the suite assert that a row press picks the
## right campaign without a tree to show a toast in.
var _last_opened: CampaignDef = null


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = _GROUND
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 48)
	margin.add_theme_constant_override("margin_right", 48)
	margin.add_theme_constant_override("margin_top", 32)
	margin.add_theme_constant_override("margin_bottom", 28)
	add_child(margin)

	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 14)
	margin.add_child(page)

	var heading := Label.new()
	heading.text = "CAMPAIGN"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_color_override("font_color", _GOLD)
	UiFont.title(heading, 30, true)
	page.add_child(heading)

	# THE LIST IS THE ONLY THING THAT GROWS — see the class comment on scrolling.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 10)
	# FILL, so a row is as wide as the scroll view rather than as wide as its own text.
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)

	# Shown only when there is nothing to list, which in an exported build is the ordinary
	# state until a campaign is installed. An empty panel would read as a broken screen.
	_empty = Label.new()
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty.add_theme_color_override("font_color", _PARCHMENT)
	_empty.visible = false
	page.add_child(_empty)

	# BACK at the bottom (`scenarios/README.md`). In the page's flow rather than anchored
	# to the window, so it cannot end up under the list on a short viewport.
	var footer := HBoxContainer.new()
	page.add_child(footer)
	_back_button = Button.new()
	_back_button.text = "BACK"
	_back_button.custom_minimum_size = Vector2(180, 58)
	UiFont.title(_back_button, 22)
	_back_button.pressed.connect(_on_back_pressed)
	footer.add_child(_back_button)

	# THIS SCREEN OWNS ITS OWN TOAST rather than borrowing the main menu's, because the two
	# are different scenes — `MainMenu.tscn`'s `%Toast` is gone the moment this one loads.
	# Added last so it draws over the list, and positioned the way `GameScene` positions
	# one: centred horizontally, which for a fixed-width banner is an offset and not an
	# anchor preset.
	_toast = NoticeToast.new()
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.position = Vector2(-NoticeToast.SIZE.x / 2.0, 24.0)
	add_child(_toast)

	reload()


## Re-read the roots and rebuild the rows. Public so a test can call it after writing a
## campaign, and so an install can refresh the screen without a scene change.
func reload() -> void:
	# Detach BEFORE freeing, and `free()` rather than `queue_free()`: a deferred free needs
	# a tree to process it, and this screen is instantiated without one all through the
	# suite — so `queue_free` here would leave the old rows in `_list` for the rest of the
	# test and the second `reload()` would double the list.
	for row in _rows:
		_list.remove_child(row)
		row.free()
	_rows.clear()

	var loader := Campaigns.new()
	_campaigns = loader.discover()
	_warnings = loader.warnings.duplicate()

	# The loader deliberately never prints (see its class comment); this is the caller that
	# decides to. A shadowed or malformed campaign is a developer's problem nine times out
	# of ten, and silence is how `game/assets/atlases/` went stale for a fortnight.
	for w in _warnings:
		push_warning("campaigns: " + w)

	for i in range(_campaigns.size()):
		var row := _build_row(_campaigns[i], i)
		_rows.append(row)
		_list.add_child(row)

	_empty.visible = _campaigns.is_empty()
	if _campaigns.is_empty():
		_empty.text = _nothing_found_text()


## One campaign: icon left, title top, description right, both growing rightwards
## (`scenarios/README.md`).
##
## A `Button` with the layout INSIDE IT rather than a panel with an input handler, so it
## answers a tap, a keyboard focus and a screen reader the way every other control on the
## front door does. Children are `MOUSE_FILTER_IGNORE` so the press lands on the button and
## not on the label the finger happened to be over.
func _build_row(c: CampaignDef, index: int) -> Button:
	var row := Button.new()
	row.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# A campaign whose own `campaign.json` is broken, or which has no playable scenario at
	# all, is SHOWN AND DISABLED rather than hidden: a campaign that silently vanishes is
	# indistinguishable from one the game failed to find, and the player has a folder on
	# disk they can see.
	row.disabled = not c.is_playable()
	row.tooltip_text = "\n".join(c.all_problems()) if row.disabled else ""
	row.pressed.connect(_on_row_pressed.bind(index))

	var pad := MarginContainer.new()
	pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	pad.add_theme_constant_override("margin_left", 12)
	pad.add_theme_constant_override("margin_right", 12)
	pad.add_theme_constant_override("margin_top", 12)
	pad.add_theme_constant_override("margin_bottom", 12)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(pad)

	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 14)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(line)

	line.add_child(_build_icon(c))

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text.add_theme_constant_override("separation", 4)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(text)

	var title := Label.new()
	title.text = c.name
	title.add_theme_color_override("font_color", _GOLD)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiFont.title(title, 22)
	text.add_child(title)

	var blurb := Label.new()
	blurb.text = c.description if not c.description.is_empty() else _fallback_blurb(c)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	blurb.add_theme_color_override("font_color", _PARCHMENT)
	blurb.add_theme_font_size_override("font_size", 15)
	blurb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_child(blurb)

	return row


## The icon, or a lettered stand-in when there is no file. **Never `load()`** — see
## `ContentImage`.
func _build_icon(c: CampaignDef) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var tex := ContentImage.load_texture(c.icon_path)
	if tex != null:
		var art := TextureRect.new()
		art.texture = tex
		# EXPAND_IGNORE_SIZE, for the reason `HelpScreen._art` records and the reason
		# `Boot.tscn` was cropped on a phone for a month: a `TextureRect` defaults to
		# `EXPAND_KEEP_SIZE`, which makes the texture's own 256×256 the control's MINIMUM,
		# and a minimum size beats a `custom_minimum_size` of 88.
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		# LINEAR: these are pictures scaled by whatever ratio the row happens to want, and
		# nearest-neighbour resampling of a picture is speckle on every edge.
		art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(art)
		return holder

	var plate := ColorRect.new()
	plate.color = Color(0.28, 0.2, 0.14, 1.0)
	plate.set_anchors_preset(Control.PRESET_FULL_RECT)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(plate)

	var letter := Label.new()
	letter.text = c.name.substr(0, 1).to_upper() if not c.name.is_empty() else "?"
	letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	letter.set_anchors_preset(Control.PRESET_FULL_RECT)
	letter.add_theme_color_override("font_color", _GOLD)
	letter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiFont.title(letter, 34, true)
	holder.add_child(letter)
	return holder


## What a row says when `campaign.json` gives no description. A broken campaign gets its
## first complaint, because that is the one thing a player or a designer can act on; a
## sound one gets its size, which is at least true.
func _fallback_blurb(c: CampaignDef) -> String:
	var problems := c.all_problems()
	if not problems.is_empty():
		return problems[0]
	var n := c.scenarios.size()
	return "%d scenario%s" % [n, "" if n == 1 else "s"]


## Why the list is empty, in the terms of whoever is reading it.
##
## THE TWO CASES ARE GENUINELY DIFFERENT and conflating them wastes somebody's afternoon.
## In the editor the dev override is live, so an empty list means the repo's `scenarios/`
## folder is missing or unreadable. In an exported build there is no override at all
## (`Campaigns.roots()` gates it on `OS.has_feature("editor")`), so an empty list is the
## normal state before a campaign is installed — and on Android `user://` is internal app
## storage that cannot be pushed to until 0.3 `AssetPacks` lands.
func _nothing_found_text() -> String:
	if OS.has_feature("editor"):
		return ("No campaigns found. The editor reads the repository's own `scenarios/`"
				+ " folder; searched:\n" + "\n".join(Campaigns.new().roots()))
	return ("No campaigns are installed yet.\n\nCampaigns arrive as content packs and are"
			+ " read from " + Campaigns.USER_ROOT + ".")


## Open a campaign — 15.5's scenario screen, which does not exist yet.
##
## ANSWERS WITH A TOAST RATHER THAN DOING NOTHING, which is PLAN.md 1.1's rule for the
## front door and the reason HOW TO had a toast for the eleven days before `HelpScreen`
## landed: a button that visibly does nothing reads as a bug, and a button that says why
## reads as a plan. **This function body is the whole of what 15.5 replaces** — the row, the
## press and the campaign it hands over are all in place.
func open_campaign(c: CampaignDef) -> void:
	_last_opened = c
	# GUARDED ON THE TREE, not on the toast existing. `NoticeToast` fades with a tween and a
	# tween needs a `SceneTree`; the suite builds this screen with `CampaignScreen.new()` and
	# never parents it, so an unguarded call would fail every test that presses a row rather
	# than the one that meant to check the message.
	if is_inside_tree():
		_toast.show_message("%s — the scenario list is not built yet" % c.name)


func _on_row_pressed(index: int) -> void:
	if index < 0 or index >= _campaigns.size():
		return
	open_campaign(_campaigns[index])


## BACK, and this is the ONE thing here that touches the tree.
##
## Not exercised in the suite, for the reason `test_help_screen` and `test_pause_menu` both
## give: `get_tree()` is called unconditionally because this is only ever pressed by a
## screen that is on screen.
func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(_MAIN_MENU_SCENE)


# ── readers, for the suite and for 15.5 ──────────────────────────────────────

func campaign_count() -> int:
	return _campaigns.size()


func campaigns() -> Array[CampaignDef]:
	return _campaigns


func warnings() -> Array[String]:
	return _warnings


func row(index: int) -> Button:
	return _rows[index] if index >= 0 and index < _rows.size() else null


func showing_empty_notice() -> bool:
	return _empty.visible


## The campaign the last press handed to `open_campaign`, or null. See `_last_opened`.
func last_opened() -> CampaignDef:
	return _last_opened
