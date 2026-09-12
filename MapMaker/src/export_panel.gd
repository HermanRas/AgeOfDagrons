## The Export Scenario screen (PLAN.md 16.8): the dialog that turns the open map into a campaign
## mission.
##
## ## ⚠️ IT ASKS FOR THE SIX THINGS A `scenario.json` CANNOT DERIVE, AND NOTHING ELSE
##
## Everything a scenario declares is either **on the map already** or **a decision only a person
## can make**, and the panel is the second list:
##
##   | declared      | where it comes from                                        |
##   |---------------|------------------------------------------------------------|
##   | `mode`        | DERIVED from the conditions — see `ScenarioExport`          |
##   | `map`         | the map's own sidecar, as provenance                        |
##   | `objectives`  | the Conditions panel (16.6), verbatim                       |
##   | `name`        | asked — it is what the scenario list shows                  |
##   | `description` | asked                                                       |
##   | `message`     | asked — 15.6's briefing modal                               |
##   | `opponents`   | asked, and BOUNDED by the map's seats                       |
##   | `starting_age`| asked                                                       |
##
## ⛔ **THERE IS NO MODE PICKER AND THAT IS THE ONE ABSENCE WORTH DEFENDING.** `ScenarioDef`
## refuses three of the four combinations of mode and condition list, so a picker would be a
## control whose wrong setting authors a mission that will not start, for no expressive gain at
## all. The summary line says which mode the export will write and why, because a derived field
## nobody can see reads as a missing feature.
##
## ## AN OVERLAY `Control`, NOT A `Window`
##
## `ConditionPanel`'s reason exactly: half of this tool's checks have no viewport, so a popup
## would answer nothing in the suite, and `preview_editor` photographs the screen rather than the
## desktop. Every reading this panel offers a test — `request()`, `summary_text()`, `message()`,
## `campaign_rows()` — works with no tree at all.
##
## **The icon chooser is the exception and is a `Window`**, on card #93's ruling: a file picker is
## a thing the operating system already knows how to draw. `pick_icon()` is the seam underneath it,
## so nothing in the suite has to open one.
##
## ## ⚠️ THE CAMPAIGN PICKER IS A LIST OF FOLDERS ON DISK, AND THAT IS WHAT MAKES IT SAFE
##
## A campaign folder is the **progress key** (`user://campaign_progress.json` is keyed by it), so
## the difference between picking `HowToPlay` and typing `howtoplay` is the difference between
## adding a mission to the shipped campaign and creating a second one beside it that no player has
## any progress in. A free-text field alone would make that a typo; a picker of what is already
## there makes it a choice, and the New Campaign row is where typing is the right answer.
class_name ExportPanel
extends Control

## Emitted after a successful export, carrying the absolute paths written. The editor puts the
## count on its notice line; the panel says the rest itself.
signal exported(paths: Array)

## Emitted whenever the panel changes something the editor's status line reads — today only the
## document's directory, which an export re-points. `ConditionPanel.changed`'s shape.
signal changed

const _LABEL_W := 128
const _FIELD_W := 320

## See `ConditionPanel._ID_SHIFT` — `add_item(text, -1)` means *"use the index as the id"*, so an
## id of -1 can never be stored and `select(-1)` DESELECTS the control.
const _ID_SHIFT := 1

## The picker row that means "type a new one". **Not a campaign folder**, so it can never collide
## with one: a directory name cannot contain a space (`ScenarioExport._check_folder`).
const _NEW_CAMPAIGN := "new campaign…"

var _document: MapDocument = null
var _startup: Startup = null

## Where campaigns are read from and written to. Overridable so the suite can point the whole
## panel at a scratch directory — the same seam `MapSources.discover()` keeps by taking a root.
var _root := ""

var _campaign: OptionButton = null
var _campaign_folder: LineEdit = null
var _campaign_name: LineEdit = null
var _campaign_description: LineEdit = null
var _folder: LineEdit = null
var _name: LineEdit = null
var _description: LineEdit = null
var _message_field: TextEdit = null
var _opponent_count: SpinBox = null
var _opponent_box: HBoxContainer = null
var _starting_age: SpinBox = null
var _summary: Label = null
var _message: Label = null
var _export_button: Button = null
var _icon_labels: Dictionary = {}
var _icon_paths: Dictionary = {}
var _icon_dialog: FileDialog = null
var _icon_wanted := -1

## The form and the window onto it, kept so `preview_editor` can measure the fold.
##
## ⚠️ **A SCROLL'S VIEWPORT AND ITS CONTENT ARE THE TWO NUMBERS THAT DECIDE WHAT IS HIDDEN**, and
## neither is visible in a screenshot — two renders of this panel differing by 30 px of viewport
## were indistinguishable by eye and one of them hid a whole row. §6's rule: measure it.
var _scroll: ScrollContainer = null
var _form_grid: GridContainer = null

## The centred plate, as opposed to THIS control, which is the full-screen dim behind it.
##
## ⛔ **KEPT BECAUSE `panel.size.y` IS ALWAYS THE WHOLE WINDOW AND THEREFORE ALWAYS FITS IT.**
## `_init()` sets `PRESET_FULL_RECT`, so a preview asking this Control how tall it is gets the
## viewport's height back and a *"does the plate fit?"* test built on it can never fail — the exact
## shape of §6's row about a verification blind to the fault it is for. `ConditionPanel` has the
## same measurement and the same hole; flagged rather than fixed there, because 16.6 is in `Test`.
var _plate: PanelContainer = null

## True while the panel is assigning its own controls — `ConditionPanel._filling`'s hazard:
## assigning an `OptionButton` emits `item_selected`, and a handler that rebuilds the form from the
## controls would then race the fill.
var _filling := false

var _open := false


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# `STOP`, NOT `PASS` — the whole modality. See `ConditionPanel._init`: without it the canvas
	# goes on receiving clicks that land on the dim, and closing the dialog reveals a line painted
	# across the map through it.
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build()


# ── what the editor and a test ask ──────────────────────────────────────────

func set_document(doc: MapDocument) -> void:
	_document = doc
	refresh()


func set_startup(startup: Startup) -> void:
	_startup = startup
	refresh()


## Point the panel at a different `scenarios/` root. The suite's seam; `""` means the real one.
func set_root(root: String) -> void:
	_root = root
	refresh()


func root() -> String:
	return _root if not _root.is_empty() else ScenarioExport.scenarios_root()


## Open it, re-reading what is on disk and re-deriving every default.
##
## ⚠️ **THE CAMPAIGN LIST AND THE `scenario_N` DEFAULT ARE READ HERE AND NOT AT BUILD TIME.** Both
## are facts about a directory two agents commit to, and the tool can sit open for an hour — a list
## built once would offer a campaign somebody deleted and aim the export at a folder somebody has
## since created.
func open() -> void:
	_open = true
	visible = true
	_reload_campaigns()
	_reset_form()
	refresh()


func close() -> void:
	_open = false
	visible = false


func is_open() -> bool:
	return _open


## The campaigns the picker is offering, as `{folder, name, scenarios}` rows. What a test reads
## instead of the control.
func campaign_rows() -> Array[Dictionary]:
	return ScenarioExport.campaigns_in(root())


## What the controls currently spell, as a request `ScenarioExport.run()` can take.
##
## ⚠️ **THE CAMPAIGN FOLDER COMES FROM THE PICKER WHEN ONE IS CHOSEN AND FROM THE FIELD ONLY ON
## `new campaign…`.** Reading the field unconditionally would work right up until somebody picked
## an existing campaign and then edited the greyed text, which is exactly the state
## `_refresh_form_state()` disables the field to prevent.
func request() -> Dictionary:
	var chosen := _selected_campaign()
	var existing := chosen != _NEW_CAMPAIGN and not chosen.is_empty()
	var out := {
		"campaign_folder": chosen if existing else _campaign_folder.text.strip_edges(),
		"campaign_name": _campaign_name.text.strip_edges(),
		"campaign_description": _campaign_description.text.strip_edges(),
		"folder": _folder.text.strip_edges(),
		"name": _name.text.strip_edges(),
		"description": _description.text.strip_edges(),
		"message": _message_field.text,
		"opponents": _opponent_levels(),
		"starting_age": int(_starting_age.value),
		"icons": _icon_paths.duplicate(),
	}
	return out


## Put a request into the controls. The inverse of `request()`, and what a test drives the panel
## with rather than clicking.
##
## **EVERY CONTROL IS ASSIGNED UNCONDITIONALLY**, 16.3's rule: an `OptionButton` nobody has
## selected displays item 0 while `get_selected_id()` answers -1, so a field the request does not
## mention would otherwise keep whatever the last map put there.
func fill_request(r: Dictionary) -> void:
	_filling = true
	var folder := str(r.get("campaign_folder", ""))
	if _campaign_has(folder):
		_select_key(_campaign, folder)
		_campaign_folder.text = folder
	else:
		_select_key(_campaign, _NEW_CAMPAIGN)
		_campaign_folder.text = folder
	_campaign_name.text = str(r.get("campaign_name", ""))
	_campaign_description.text = str(r.get("campaign_description", ""))
	_folder.text = str(r.get("folder", ""))
	_name.text = str(r.get("name", ""))
	_description.text = str(r.get("description", ""))
	_message_field.text = str(r.get("message", ""))
	_starting_age.value = int(r.get("starting_age", 1))
	var opponents: Array = r.get("opponents", []) if r.get("opponents") is Array else []
	_opponent_count.value = opponents.size()
	_rebuild_opponents(opponents)
	_icon_paths = (r.get("icons", {}) as Dictionary).duplicate() \
			if r.get("icons") is Dictionary else {}
	_filling = false
	refresh()


## Name a PNG for one of the three slots. The seam under the "Choose…" buttons, so the suite never
## opens a `FileDialog`.
func pick_icon(slot: int, path: String) -> void:
	var key := str(ScenarioExport.ICON_SLOTS.get(slot, ""))
	if key.is_empty():
		return
	if path.strip_edges().is_empty():
		_icon_paths.erase(key)
	else:
		_icon_paths[key] = path
	refresh()


## Do it. False when the export refused, with the reason on the panel's message line.
func press_export() -> bool:
	if _document == null:
		_say("there is no map open", UiChrome.BAD)
		return false
	var exporter := ScenarioExport.new()
	# ⚠️ **THE GUARD COMES FROM `Startup` AND A MISSING ONE IS NOT QUIETLY TREATED AS FINE.**
	# `ScenarioExport.run()` takes it as a required argument for this reason, and passing `null`
	# refuses rather than skipping the check — a panel opened before `Startup.check()` ran is
	# exactly the 2026-09-04 main-scene bug, where a screen that only works when something else ran
	# first was opened directly.
	var guard: FormatGuard = _startup.guard if _startup != null else null
	var problems := exporter.run(_document, request(), guard, root())
	if not problems.is_empty():
		# ALL OF THEM, `ConditionPanel.press_add()`'s rule: the refusals are independent, and
		# showing one at a time is an author fixing one field per attempt.
		_say(" | ".join(PackedStringArray(problems)), UiChrome.BAD)
		refresh()
		return false

	# ⚠️ **THE WARNINGS ARE SHOWN ON SUCCESS AND THEY ARE NOT A FAILURE.** `MapDocument.save()`'s
	# amber "SAVED, BUT LOOK" third state, which exists because two states could not express *the
	# file wrote perfectly and there is still something to do* — here that is almost always an
	# empty icon slot, which is genuinely worth a sentence and genuinely not a problem.
	var said := "exported %d file(s) to %s" % [exporter.written.size(), _target_dir()]
	if not exporter.warnings.is_empty():
		_say("%s — %s" % [said, " | ".join(PackedStringArray(exporter.warnings))], UiChrome.WARN)
	else:
		_say(said, UiChrome.GOOD)
	# RE-READ AFTER THE EXPORT, because it moved: the document now lives in the scenario folder and
	# its conditions now live in the `scenario.json` beside it. Both are on screen in this panel's
	# summary and on the editor's status line, and a stale one would tell an author their next Save
	# goes somewhere it does not.
	_reload_campaigns()
	refresh()
	exported.emit(exporter.written)
	changed.emit()
	return true


## The last thing said to the author. Empty when nothing has gone wrong.
func message() -> String:
	return _message.text if _message != null else ""


## What the panel says about the export as a whole: where it lands, which mode it will write and
## why, and how the opponents sit against the map.
##
## ⛔ **THE DERIVED MODE IS THE HALF THAT HAD TO BE ON SCREEN.** It is the one field of the schema
## with no control, so without a sentence naming it the tool would be making a decision an author
## cannot see, about the thing that decides their mission — and *"why is my scenario won by
## conquest"* is not a question anything else here can answer.
func summary_text() -> String:
	if _document == null:
		return "no map open"
	var conditions := _document.objectives.size()
	var mode := "last_man_standing"
	var why := "this map declares no win conditions, so the mission is won by conquest"
	if conditions > 0:
		mode = "scenario"
		why = "this map declares %d condition(s), %d of them a win" \
				% [conditions, _document.win_count()]
	var seats := _document.seats()
	var players := _opponent_levels().size() + 1
	return "%s → mode \"%s\": %s. %d of %d seat(s) filled." \
			% [_target_dir(), mode, why, players, seats]


## Rebuild every derived label from the document and the controls. Safe with no tree, no document
## and no startup, which is what lets the editor call it before a map exists.
func refresh() -> void:
	if _summary == null:
		return
	_summary.text = summary_text()
	for slot in _icon_labels:
		var key := str(ScenarioExport.ICON_SLOTS[slot])
		var label := _icon_labels[slot] as Label
		var chosen := str(_icon_paths.get(key, ""))
		label.text = chosen.get_file() if not chosen.is_empty() else "(none — the slot is left empty)"
		label.add_theme_color_override("font_color",
				UiChrome.TEXT if not chosen.is_empty() else UiChrome.DIM)
	_refresh_form_state()


# ── the campaign picker ─────────────────────────────────────────────────────

func _reload_campaigns() -> void:
	if _campaign == null:
		return
	var was := _selected_campaign()
	_filling = true
	_campaign.clear()
	var rows := campaign_rows()
	for i in rows.size():
		# THE FOLDER IS THE ITEM TEXT AND THE NAME IS A SUFFIX, not the other way round: the folder
		# is the identity and the progress key, and two campaigns may perfectly well share a
		# display name. `_selected_campaign()` reads the text, so the folder has to be the head of
		# it -- hence the split rather than a prettier "Name (folder)".
		var row: Dictionary = rows[i]
		_campaign.add_item(str(row["folder"]), i + _ID_SHIFT)
		_campaign.set_item_tooltip(i, "%s — %d scenario(s)"
				% [row["name"], (row["scenarios"] as Array).size()])
	_campaign.add_item(_NEW_CAMPAIGN, rows.size() + _ID_SHIFT)
	_filling = false
	if not _select_key(_campaign, was):
		# NOTHING PRESELECTED MEANS THE NEW ROW, deliberately: a tool opened on a repo with no
		# campaigns at all must not preselect a campaign, and `select(0)` there would silently aim
		# the first export at whichever one sorts first.
		_select_key(_campaign, _NEW_CAMPAIGN)
	_on_campaign_chosen()


## Fill the campaign fields from whichever row is selected, and default the scenario folder.
func _on_campaign_chosen() -> void:
	if _filling or _campaign_folder == null:
		return
	var chosen := _selected_campaign()
	if chosen == _NEW_CAMPAIGN or chosen.is_empty():
		_folder.text = "scenario_1"
		_refresh_form_state()
		return
	for row in campaign_rows():
		if str(row["folder"]) != chosen:
			continue
		_filling = true
		_campaign_folder.text = chosen
		_campaign_name.text = str(row["name"])
		_campaign_description.text = str(row["description"])
		_filling = false
		# THE NEXT FREE FOLDER ON DISK, not the order list's length + 1 — see
		# `ScenarioExport.next_scenario_folder()`, which would otherwise aim an export at somebody's
		# work in progress.
		_folder.text = ScenarioExport.next_scenario_folder(root().path_join(chosen))
		break
	_refresh_form_state()


func _campaign_has(folder: String) -> bool:
	for row in campaign_rows():
		if str(row["folder"]) == folder:
			return true
	return false


func _selected_campaign() -> String:
	if _campaign == null:
		return ""
	var at := _campaign.get_selected()
	return _campaign.get_item_text(at) if at >= 0 else ""


## Where this export will land, for the summary line. `?` for a campaign nobody has named yet,
## which is honest: the path is not decided until it is.
func _target_dir() -> String:
	var r := request()
	var campaign := str(r["campaign_folder"])
	var folder := str(r["folder"])
	if campaign.is_empty() or folder.is_empty():
		return "scenarios/?"
	return "scenarios/%s/%s" % [campaign, folder]


# ── opponents ───────────────────────────────────────────────────────────────

## One picker per opponent, rebuilt when the count changes.
##
## ⚠️ **THE COUNT IS A `SpinBox` AND THE LEVELS ARE SEPARATE CONTROLS**, rather than one "number of
## bots at difficulty X". A campaign's second mission is a passive economy lesson and its fifth is
## a real duel; a 2v2 wants a hard ally's enemy and an easy one. The shipped campaign has one
## opponent in every mission, which is exactly the case that makes a single shared picker look
## sufficient until it is not.
func _rebuild_opponents(levels: Array) -> void:
	if _opponent_box == null:
		return
	for child in _opponent_box.get_children():
		child.queue_free()
		# REMOVED AS WELL AS FREED. `queue_free()` takes effect at the end of the frame, so a
		# headless test that changed the count twice in one call stack would read both sets.
		_opponent_box.remove_child(child)
	for i in levels.size():
		var picker := OptionButton.new()
		for j in AIProfile.IDS.size():
			picker.add_item(str(AIProfile.IDS[j]), j + _ID_SHIFT)
		_select_key(picker, str(levels[i]))
		_opponent_box.add_child(picker)


func _opponent_levels() -> Array[String]:
	var out: Array[String] = []
	if _opponent_box == null:
		return out
	for child in _opponent_box.get_children():
		var picker := child as OptionButton
		if picker == null:
			continue
		var at := picker.get_selected()
		out.append(picker.get_item_text(at) if at >= 0 else AIProfile.DEFAULT_LEVEL)
	return out


func _on_opponent_count_changed(value: float) -> void:
	if _filling:
		return
	var wanted := int(value)
	var levels := _opponent_levels()
	# THE EXISTING CHOICES SURVIVE A COUNT CHANGE. Rebuilding from `DEFAULT_LEVEL` every time would
	# silently reset four carefully-picked difficulties because somebody added a fifth bot.
	while levels.size() > wanted:
		levels.remove_at(levels.size() - 1)
	while levels.size() < wanted:
		levels.append(AIProfile.DEFAULT_LEVEL)
	_rebuild_opponents(levels)
	refresh()


# ── building it ─────────────────────────────────────────────────────────────

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var plate := PanelContainer.new()
	_plate = plate
	plate.add_theme_stylebox_override("panel", UiChrome.panel_style())
	plate.set_anchors_preset(Control.PRESET_CENTER)
	plate.custom_minimum_size = Vector2(820, 0)
	# HALF-DELTA CENTRING, `ConditionPanel`'s note: `PRESET_CENTER` anchors the top-LEFT corner to
	# the middle, not the control's middle.
	plate.grow_horizontal = Control.GROW_DIRECTION_BOTH
	plate.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(plate)

	var column := VBoxContainer.new()
	plate.add_child(column)

	var title := Label.new()
	title.text = "EXPORT SCENARIO"
	title.add_theme_color_override("font_color", UiChrome.GOLD)
	column.add_child(title)

	_summary = Label.new()
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.custom_minimum_size = Vector2(780, 0)
	column.add_child(_summary)

	# ⚠️ **THE WHOLE FORM IS INSIDE A `ScrollContainer`**, §6's row: a `VBoxContainer` does not clip,
	# scroll or compress past its children's minimum sizes — it OVERFLOWS. This form has a variable
	# number of opponent pickers and a multi-line briefing box in it, and the lobby shipped with its
	# bottom nav strip off the screen for exactly this reason with every structural test passing.
	# ⚠️ **500 AND NOT 360, MEASURED OFF TWO RENDERS RATHER THAN CHOSEN.** At 360 the fold landed
	# inside the opponents row, so the three icon slots — the half of this panel an author is least
	# likely to go looking for — were below it with nothing on screen saying they existed. A scroll
	# bar says *"there is more"*; it does not say *"there are three things down there you have to
	# fill in"*. 470 showed two of the three, which is the same fault with a shorter reach; 500 with
	# the briefing box trimmed shows all of them, and `_report_export()` measures the plate against
	# the window on every preview run so this cannot quietly grow past it.
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(780, 500)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_form_grid = _form()
	_scroll.add_child(_form_grid)
	column.add_child(_scroll)

	_message = Label.new()
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.custom_minimum_size = Vector2(780, 0)
	column.add_child(_message)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	_export_button = _button("Export", func() -> void: press_export())
	buttons.add_child(_export_button)
	buttons.add_child(_button("Close", func() -> void: close()))
	column.add_child(buttons)

	_build_icon_dialog()


## How tall the CENTRED PLATE is — the thing that has to fit the window. See `_plate`.
func plate_height() -> float:
	return _plate.size.y if _plate != null else 0.0


## How tall the window onto the form actually is. See `_scroll`.
func _form_viewport() -> Vector2:
	return _scroll.size if _scroll != null else Vector2.ZERO


## How tall the form actually is. Anything past `_form_viewport().y` is behind the scroll.
func _form_content() -> Vector2:
	return _form_grid.size if _form_grid != null else Vector2.ZERO


func _form() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_campaign = OptionButton.new()
	_campaign.item_selected.connect(func(_at: int) -> void: _on_campaign_chosen())
	_add_field(grid, "Campaign", _campaign)

	_campaign_folder = _line_edit("the folder on disk — and the key a player's progress is under")
	_add_field(grid, "Folder", _campaign_folder)
	_campaign_name = _line_edit("what the campaign list shows")
	_add_field(grid, "Campaign name", _campaign_name)
	# ⚠️ **"CAMPAIGN BLURB", NOT "ABOUT IT".** Both halves of this form have a name and a
	# description, and labelling them the same word twice made the first render read as two
	# unrelated fields that happened to look alike — the separator groups them and a caption is what
	# NAMES them. §6's lobby row is the same fault in a different direction: a layout that is
	# correct and unreadable.
	_campaign_description = _line_edit("one line, under the name")
	_add_field(grid, "Campaign blurb", _campaign_description)

	grid.add_child(HSeparator.new())
	grid.add_child(HSeparator.new())

	_folder = _line_edit("scenario_1")
	_add_field(grid, "Scenario folder", _folder)
	_name = _line_edit("what the scenario list shows")
	_add_field(grid, "Scenario name", _name)
	_description = _line_edit("one line, under the name")
	_add_field(grid, "Scenario blurb", _description)

	# A `TextEdit` AND NOT A `LineEdit`, because a briefing is paragraphs: every shipped one holds
	# blank lines, and 15.6 draws it in a modal that wraps. Typing `\n` into a single-line field is
	# the alternative and is not a thing anybody should have to do.
	_message_field = TextEdit.new()
	# 76 px IS THREE LINES AND IT SCROLLS PAST THAT. The briefing is the tallest single control in
	# the form, so every pixel it takes is a pixel of the icon rows below the fold — and a briefing
	# is written once and read in the GAME's modal, not here.
	_message_field.custom_minimum_size = Vector2(_FIELD_W, 76)
	_message_field.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_add_field(grid, "Briefing", _message_field)

	grid.add_child(HSeparator.new())
	grid.add_child(HSeparator.new())

	var opponents := HBoxContainer.new()
	_opponent_count = SpinBox.new()
	_opponent_count.min_value = 1
	# THE GAME'S OWN CAP, minus the human. Read from the guarded stand-in rather than typed, so the
	# day a map seats more players this control follows without an edit.
	_opponent_count.max_value = MapGenerator.MAX_PLAYERS - 1
	_opponent_count.value = 1
	_opponent_count.value_changed.connect(_on_opponent_count_changed)
	opponents.add_child(_opponent_count)
	_opponent_box = HBoxContainer.new()
	opponents.add_child(_opponent_box)
	_add_field(grid, "Opponents", opponents)

	_starting_age = SpinBox.new()
	_starting_age.min_value = 1
	_starting_age.max_value = 4
	_starting_age.value = 1
	_add_field(grid, "Starting age", _starting_age)

	grid.add_child(HSeparator.new())
	grid.add_child(HSeparator.new())

	for pair in [
		[ScenarioExport.Icon.SCENARIO, "Scenario tile"],
		[ScenarioExport.Icon.CAMPAIGN, "Campaign tile"],
		[ScenarioExport.Icon.BACKGROUND, "Campaign backdrop"],
	]:
		_add_field(grid, str(pair[1]), _icon_row(int(pair[0])))
	return grid


## One slot: what has been chosen, a button to choose, and a button to take it back.
##
## **THE CLEAR BUTTON IS NOT DECORATION.** Without it a path chosen by mistake can only be replaced,
## never removed — and the slot's honest empty state is a real answer, because a campaign with no
## backdrop is perfectly playable.
func _icon_row(slot: int) -> Control:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_icon_labels[slot] = label
	row.add_child(label)
	row.add_child(_button("Choose…", func() -> void: _choose_icon(slot)))
	row.add_child(_button("Clear", func() -> void: pick_icon(slot, "")))
	return row


func _build_icon_dialog() -> void:
	_icon_dialog = FileDialog.new()
	_icon_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	# THE WHOLE FILESYSTEM, because art lives wherever the author keeps it and this tool is PC-only
	# (§16 decision 6). `ACCESS_RESOURCES` would confine the picker to `res://`, which holds nothing
	# anybody would put in a campaign.
	_icon_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_icon_dialog.add_filter("*.png", "PNG image")
	_icon_dialog.title = "Choose a picture"
	_icon_dialog.file_selected.connect(func(path: String) -> void:
		pick_icon(_icon_wanted, path))
	add_child(_icon_dialog)


func _choose_icon(slot: int) -> void:
	_icon_wanted = slot
	if _icon_dialog != null:
		_icon_dialog.popup_centered_ratio(0.7)


# ── the form's own state ────────────────────────────────────────────────────

func _reset_form() -> void:
	if _document == null:
		return
	var r := ScenarioExport.default_request(_document)
	# THE PICKER'S CURRENT CHOICE SURVIVES A RESET, because `_reload_campaigns()` has just made it
	# and `default_request()` knows nothing about campaigns. Overwriting it here would make opening
	# the dialog a second time forget which campaign the author was adding to.
	r["campaign_folder"] = _selected_campaign() if _selected_campaign() != _NEW_CAMPAIGN else ""
	r["folder"] = _folder.text.strip_edges() if not _folder.text.strip_edges().is_empty() \
			else "scenario_1"
	fill_request(r)
	_on_campaign_chosen()
	_say("", UiChrome.DIM)


## Enable what applies and disable what does not.
##
## ⚠️ **THE CAMPAIGN FIELDS ARE DISABLED RATHER THAN HIDDEN WHEN AN EXISTING CAMPAIGN IS CHOSEN**,
## `ConditionPanel._refresh_form_state()`'s rule: a disabled control still says what it is for, and
## a hidden one takes its explanation with it. It also matters more here — the fields show the
## chosen campaign's real name and description, so greying them says *"this is what you are adding
## to"* where hiding them would say nothing at all.
##
## ⛔ **AND IT IS WHY `request()` READS THE PICKER RATHER THAN THE FOLDER FIELD.** A disabled
## `LineEdit` still holds text, so the two can disagree; the picker is the one the author chose
## with.
func _refresh_form_state() -> void:
	if _campaign_folder == null:
		return
	var is_new := _selected_campaign() == _NEW_CAMPAIGN
	_campaign_folder.editable = is_new
	_campaign_name.editable = is_new
	_campaign_description.editable = is_new
	if _export_button != null:
		# ⚠️ **DISABLED ON A SCHEMA THAT HAS DRIFTED, AND THE REASON IS ON THE MESSAGE LINE RATHER
		# THAN IMPLIED BY THE GREY.** §6's row: *"a disabled control's reason for being disabled is
		# not the same fact as its being disabled"*. `press_export()` refuses for the same reason
		# anyway, so this is the visible half rather than the guard.
		var blocked := _startup != null and not _startup.can_export()
		_export_button.disabled = blocked or _document == null
		if blocked and _message != null and _message.text.is_empty():
			_say(_startup.guard.schema_refusal() if _startup.guard != null
					else _startup.reason, UiChrome.BAD)


func _say(text: String, colour: Color) -> void:
	if _message == null:
		return
	_message.text = text
	_message.add_theme_color_override("font_color", colour)


func _add_field(grid: GridContainer, caption: String, field: Control) -> void:
	var label := Label.new()
	label.text = caption
	label.custom_minimum_size = Vector2(_LABEL_W, 0)
	grid.add_child(label)
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(field)


func _line_edit(hint: String) -> LineEdit:
	var field := LineEdit.new()
	field.placeholder_text = hint
	field.custom_minimum_size = Vector2(_FIELD_W, 0)
	return field


func _button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(on_press)
	return b


## Select the item whose TEXT is `key`. False when the picker has not got it — the caller decides
## what that means, which is the difference from `ConditionPanel._select_key()`: there an unknown
## key falls back to item 0, and here falling back would silently aim an export at the wrong
## campaign.
static func _select_key(picker: OptionButton, key: String) -> bool:
	if picker == null or key.is_empty():
		return false
	for i in picker.item_count:
		if picker.get_item_text(i) == key:
			picker.select(i)
			return true
	return false
