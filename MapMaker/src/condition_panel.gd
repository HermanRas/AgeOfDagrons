## The Map Conditions editor (PLAN.md 16.6): the screen that authors §11.8's vocabulary.
##
## ## ⚠️ IT INVENTS NOTHING, AND EVERY DROPDOWN IN IT IS READ OUT OF `ObjectiveDef`
##
## PLAN.md 11.8a's requirement is *"one language, written down once"* — a hand-written
## `scenario.json` and this screen must emit the same records, or the tool can author maps the
## game misreads. A panel with its own written-out list of subjects would be that second dialect,
## living in the one place nobody would think to diff.
##
## So the four vocabulary pickers are built from `ObjectiveDef`'s own constants:
##
##   | picker  | source                                   |
##   |---------|------------------------------------------|
##   | Subject | `_SUBJECTS`, minus `_NOT_YET`            |
##   | Owner   | `_OWNERS`, plus "player…" for an index   |
##   | Compare | `_COMPARES`                              |
##   | Output  | `_OUTPUTS`                               |
##
## ✅ **AND THE `_NOT_YET` SUBTRACTION IS THE ONE WORTH KEEPING.** `named_unit` is refused by the
## loader until 16.7, so offering it would be a row an author can select, fill in and be refused
## on. Deriving the list means the day 16.7 deletes that line, the subject appears in this
## dropdown **with no edit here** — which is exactly how `area` and `ticks` arrived.
##
## 📝 **READING A CONST WHOSE NAME STARTS WITH `_` IS DELIBERATE HERE AND IS THE SAFE DIRECTION.**
## The underscore is a convention about what the game's own code should reach for, and this is not
## the game's own code — it is a second project that must not develop an opinion. `FormatGuard`
## hashes `format/objective_def.gd`, so if those constants are renamed the tool refuses to save
## and names the file, which is a louder failure than a hand-copied list drifting in silence.
##
## ## AN OVERLAY `Control`, NOT A `Window` — THE REASON IS THE SAME AS 16.4a's
##
## Half of this tool's checks have no viewport: the suite drives `Editor` outside the tree, so a
## popup would answer nothing there, and `preview_editor` photographs the screen rather than the
## desktop, so a `Window` would not be in the screenshot. Every reading this panel offers a test
## (`rows()`, `message()`, `form_record()`) therefore works with no tree at all.
##
## **The two `FileDialog`s are the exception and stay `Window`s** — the owner asked for a real
## file picker in card #93, and a file picker is a thing the operating system already knows how to
## draw. A condition list is not.
##
## ## ⚠️ THE RECORDS ARE THE AUTHOR'S WORDS AND NEVER `to_dict()`'s INTEGERS
##
## `ObjectiveDef.to_dict()` is the WIRE form — every enum an int, so the sim never re-parses a
## `">="`. A `scenario.json` is the opposite and holds the words. This panel builds words,
## `MapDocument` stores words, and `ObjectiveDef.from_dict` is used only to **validate**. See
## `MapDocument.objectives` for what goes wrong if that is got backwards.
class_name ConditionPanel
extends Control

## Emitted whenever the document's condition list changes, so the editor can refresh its status
## line and its Undo button. **Not emitted for a selection or a keystroke** — those change what
## the panel shows and nothing about the map.
signal changed

## Widths that keep the form's labels in one column. A `GridContainer` rather than a row of
## `HBoxContainer`s, on §6's rule: *"mirroring a layout is not sharing one"* — two rows built from
## the same constants drift apart because the one expanding child absorbs whatever their
## minimums differ by, which is what put the lobby's headings out of line with its slots.
const _LABEL_W := 96
const _FIELD_W := 260

## What the Owner picker calls an explicit player number. Not a value `ObjectiveDef._OWNERS`
## carries, because an index is spelled as a NUMBER in the record rather than as a word — see
## `_read_owner`, which branches on the JSON type. This is the picker's way of asking for one.
const _OWNER_INDEX_LABEL := "player…"

## ⚠️ **EVERY ID IN EVERY PICKER IS SHIFTED BY ONE, AND THAT IS §6's `add_item(text, -1)` ROW.**
## `OptionButton.add_item(text, -1)` means *"use the index as the id"*, so an id of -1 is never
## stored, `get_item_index(-1)` finds nothing and `select(-1)` DESELECTS the control — which is
## how 16.3's colour picker came out blank. Keeping every id >= 1 means no picker in this file can
## reach that value by accident, and `_selected_key()` subtracts it in one place.
const _ID_SHIFT := 1

var _document: MapDocument = null

## Which row the form is editing, or -1 when it is composing a new one.
##
## ⚠️ **AN INDEX, SO IT HAS TO BE INVALIDATED** — `MapDocument.selected`'s rule exactly. Removing
## a row filters the list and undo/redo replace it wholesale, so a stale index would make the next
## Update land on a different condition **silently**. Both paths clear it.
var _editing := -1

var _rows_box: VBoxContainer = null
var _summary: Label = null
var _message: Label = null
var _subject: OptionButton = null
var _owner: OptionButton = null
var _owner_index: SpinBox = null
var _compare: OptionButton = null
var _value: SpinBox = null
var _output: OptionButton = null
var _id_field: LineEdit = null
var _area_field: LineEdit = null
var _text_field: LineEdit = null
var _add_button: Button = null
var _cancel_button: Button = null

## True while `fill_form()` is assigning the controls.
##
## ⚠️ **ASSIGNING AN `OptionButton` EMITS `item_selected`**, which is 16.4's `_filling_inspector`
## met a second time. Without this, filling the form from a row would fire the handlers that
## rebuild the form from the controls — harmless today and exactly the shape that stops being
## harmless the moment a handler writes back to the document.
var _filling := false

var _open := false


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# ⚠️ **`STOP`, NOT `PASS` — THIS IS THE WHOLE MODALITY.** The panel covers the canvas, and
	# `MapCanvas` would otherwise go on receiving the clicks that land on the dim: an author
	# closing this dialog would find they had painted a line across their map through it.
	mouse_filter = Control.MOUSE_FILTER_STOP
	# HIDDEN VIA `hidden`, NOT `visible = false` DIRECTLY -- the harness's reset clears
	# `display:none`-style state and `hidden` is what `[hidden]` honours. Here it is simply the
	# field Godot reads; `close()` is the only writer.
	visible = false
	_build()


# ── what a test and the editor ask ──────────────────────────────────────────

func set_document(doc: MapDocument) -> void:
	_document = doc
	_editing = -1
	_reset_form()
	refresh()


func open() -> void:
	_open = true
	visible = true
	_editing = -1
	_reset_form()
	refresh()


func close() -> void:
	_open = false
	visible = false


func is_open() -> bool:
	return _open


## One line per condition, as the game's own `describe()` renders it.
##
## ⚠️ **THROUGH `ObjectiveDef.describe()` AND NOT A SENTENCE BUILT HERE**, because that function
## is what 15.6's objective tracker draws when an author wrote no `text` — so the list in this
## panel reads exactly as the row will read to a player. A second phrasing here would let an
## author lay out a list that says something different in the game.
##
## A row that will not parse cannot describe itself, so it says so and keeps its place: see
## `MapDocument._objectives_in()` on why an unparseable row is kept and reported rather than
## dropped.
func rows() -> Array[String]:
	var out: Array[String] = []
	if _document == null:
		return out
	for record in _document.objectives:
		var problems: Array[String] = []
		var o := ObjectiveDef.from_dict(record, problems)
		if o == null:
			out.append("⚠ unreadable — %s" % " | ".join(PackedStringArray(problems)))
			continue
		out.append("%s: %s" % [_output_word(record).to_upper(), o.describe()])
	return out


## The last thing said to the author: a refusal, or "" when nothing went wrong.
func message() -> String:
	return _message.text if _message != null else ""


## What the form's controls currently spell, as a record `ObjectiveDef.from_dict` can read.
##
## ⚠️ **EMPTY FIELDS ARE OMITTED RATHER THAN SENT AS `""`, AND FOR `area` THAT IS THE DIFFERENCE
## BETWEEN A REFUSAL AND A ROW.** `_read_area` refuses any non-`area` subject that CARRIES a
## region — and `str(d.get("area", ""))` is empty either way, so this happens to be safe today.
## It is done anyway because `_read_id` is the same shape and `resource` REQUIRES an id: sending
## `"id": ""` on every row makes the record say *"this author named no resource"* where omitting
## it says nothing at all, and the two want to stay distinguishable if that check ever tightens.
func form_record() -> Dictionary:
	var record: Dictionary = {
		"subject": _selected_key(_subject),
		"compare": _selected_key(_compare),
		"output": _selected_key(_output),
		"value": int(_value.value),
	}
	# THE OWNER IS A WORD OR A NUMBER, and the TYPE is what `_read_owner` branches on. An index
	# sent as the string "3" would fall through to the word lookup and be refused as an unknown
	# owner, which is a confusing message for a perfectly ordinary intention.
	var owner_key := _selected_key(_owner)
	record["owner"] = int(_owner_index.value) if owner_key == _OWNER_INDEX_LABEL else owner_key
	for pair in [["id", _id_field], ["area", _area_field], ["text", _text_field]]:
		var field := pair[1] as LineEdit
		var typed := field.text.strip_edges()
		if not typed.is_empty():
			record[pair[0]] = typed
	return record


## Put `record` into the controls. The inverse of `form_record()`.
##
## ⚠️ **EVERY CONTROL IS ASSIGNED UNCONDITIONALLY, INCLUDING THE ONES THE RECORD DOES NOT
## MENTION.** 16.3's rule in one line: *"assign the control from the field unconditionally, not
## only when the value changes"*. An `OptionButton` nobody has selected displays **item 0**, so a
## record with no `output` would leave the picker showing whatever the last row said while the
## record meant `win` — the panel and the record disagreeing, with only a screenshot able to see
## it. The defaults below are `ObjectiveDef.from_dict`'s own.
func fill_form(record: Dictionary) -> void:
	_filling = true
	_select_key(_subject, str(record.get("subject", "unit")).to_lower())
	_select_key(_compare, str(record.get("compare", ">=")))
	_select_key(_output, str(record.get("output", "win")).to_lower())
	_value.value = int(record.get("value", 0))

	var raw: Variant = record.get("owner", "self")
	if raw is float or raw is int:
		_select_key(_owner, _OWNER_INDEX_LABEL)
		_owner_index.value = int(raw)
	else:
		_select_key(_owner, str(raw).to_lower())
		_owner_index.value = 1
	_id_field.text = str(record.get("id", ""))
	_area_field.text = str(record.get("area", ""))
	_text_field.text = str(record.get("text", ""))
	_filling = false
	_refresh_form_state()


## Add the form's record, or update the row being edited. False when the loader refused it.
##
## **ONE BUTTON FOR BOTH**, because they are the same act with a different destination and two
## buttons would need a rule about which one applies when a row is selected. Its label says which
## it is doing, which is `_refresh_form_state()`'s job.
func press_add() -> bool:
	if _document == null:
		return false
	var problems: Array[String] = []
	var record := form_record()
	var ok := _document.set_objective(_editing, record, problems) if _editing >= 0 \
			else _document.add_objective(record, problems)
	if not ok:
		# THE LOADER'S OWN SENTENCES, verbatim and all of them. `from_dict` appends every
		# complaint rather than returning the first, precisely so an author is not fixing one
		# typo per attempt -- summarising them here would undo that.
		_say(" | ".join(PackedStringArray(problems)), UiChrome.BAD)
		return false
	# THE FORM IS CLEARED ONLY ON SUCCESS, so a refused row is still in front of the author with
	# the message above it. Clearing it would make them retype the whole condition to fix a typo.
	_editing = -1
	_reset_form()
	_say("", UiChrome.DIM)
	refresh()
	changed.emit()
	return true


## Load row `at` into the form for editing.
func press_edit(at: int) -> bool:
	if _document == null or at < 0 or at >= _document.objectives.size():
		return false
	_editing = at
	fill_form(_document.objectives[at])
	_say("", UiChrome.DIM)
	refresh()
	return true


## Delete row `at`.
func press_remove(at: int) -> bool:
	if _document == null or _document.remove_objective(at) == 0:
		return false
	# ⚠️ **THE FORM STOPS EDITING, because the list just shifted underneath the index it held.**
	# `MapDocument.selected`'s hazard exactly: without this, removing row 0 while editing row 1
	# would point Update at what is now row 0 and rewrite the wrong condition silently.
	_editing = -1
	_reset_form()
	refresh()
	changed.emit()
	return true


## Rebuild the list and the summary from the document. Safe with no tree and safe with no
## document, which is what lets the editor call it before a map exists.
func refresh() -> void:
	if _rows_box == null:
		return
	for child in _rows_box.get_children():
		child.queue_free()
		# ⚠️ **REMOVED IMMEDIATELY AS WELL AS FREED.** `queue_free()` takes effect at the end of
		# the frame, so a headless test that rebuilds twice in one call stack would count every
		# row twice -- and `rows()` reads the DOCUMENT rather than these children precisely so a
		# test never has to care. This keeps the two from disagreeing on screen.
		_rows_box.remove_child(child)

	var descriptions := rows()
	for i in descriptions.size():
		_rows_box.add_child(_row_control(i, descriptions[i]))

	if _summary != null:
		_summary.text = _summary_text()
		_summary.add_theme_color_override("font_color",
				UiChrome.WARN if not _problems().is_empty() else UiChrome.DIM)
	_refresh_form_state()


# ── the sentence at the top ─────────────────────────────────────────────────

func _problems() -> Array[String]:
	return _document.objective_problems() if _document != null else ([] as Array[String])


## What the panel says about the list as a whole.
##
## ⚠️ **A MAP WITH NO CONDITIONS IS A HEALTHY MAP AND MUST NOT BE SCOLDED**, which is PLAN.md
## 16.6's ruling written as a sentence: *"a map whose answer is 'beat them' therefore needs no
## conditions at all"*, because owning nothing is defeat on every map in this game whatever it
## declares. So the empty state explains what empty MEANS rather than blaming the author — the
## Areas tab's *"no areas yet — type a name and drag"* precedent, which is the only other panel in
## this tool whose emptiness is correct.
func _summary_text() -> String:
	if _document == null:
		return "no map open"
	var total := _document.objectives.size()
	if total == 0:
		return "no conditions — this map is won by conquest, which needs no rows at all"
	var problems := _problems()
	if not problems.is_empty():
		return "%d condition(s), %d win — %s" % [total, _document.win_count(),
				" | ".join(PackedStringArray(problems))]
	return "%d condition(s), %d win" % [total, _document.win_count()]


func _say(text: String, colour: Color) -> void:
	if _message == null:
		return
	_message.text = text
	_message.add_theme_color_override("font_color", colour)


# ── building it ─────────────────────────────────────────────────────────────

func _build() -> void:
	var dim := ColorRect.new()
	# THE DIM IS WHAT SAYS THE REST OF THE TOOL IS UNREACHABLE. 16.4a measured that its file
	# dialog genuinely covered the toolbar rather than assuming it; this is the same statement
	# made by a sibling that fills the screen and stops the mouse.
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var plate := PanelContainer.new()
	plate.add_theme_stylebox_override("panel", UiChrome.panel_style())
	plate.set_anchors_preset(Control.PRESET_CENTER)
	plate.custom_minimum_size = Vector2(760, 0)
	# CENTRED BY THE PRESET AND THEN PULLED BACK BY HALF ITS OWN WIDTH. `PRESET_CENTER` anchors
	# the top-left corner to the middle, not the control's middle -- the same half-delta arithmetic
	# `NoticeToast` needed when its long banner kept the short one's left edge.
	plate.grow_horizontal = Control.GROW_DIRECTION_BOTH
	plate.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(plate)

	var column := VBoxContainer.new()
	plate.add_child(column)

	var title := Label.new()
	title.text = "MAP CONDITIONS"
	title.add_theme_color_override("font_color", UiChrome.GOLD)
	column.add_child(title)

	_summary = Label.new()
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.custom_minimum_size = Vector2(720, 0)
	column.add_child(_summary)

	column.add_child(_list_area())
	column.add_child(HSeparator.new())
	column.add_child(_form())

	_message = Label.new()
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.custom_minimum_size = Vector2(720, 0)
	column.add_child(_message)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	_add_button = _button("Add", func() -> void: press_add())
	buttons.add_child(_add_button)
	_cancel_button = _button("Cancel edit", func() -> void:
		_editing = -1
		_reset_form()
		refresh())
	buttons.add_child(_cancel_button)
	buttons.add_child(_button("Done", func() -> void: close()))
	column.add_child(buttons)


## The row list, inside a `ScrollContainer`.
##
## ⚠️ **THE SCROLL IS NOT OPTIONAL AND §6 HAS THE ROW.** A `VBoxContainer` does not clip, scroll
## or compress past its children's minimum sizes — it simply OVERFLOWS — and the number of
## conditions is something the author controls. The lobby shipped with its bottom nav strip off
## the screen at eight player slots for exactly this reason, with every structural test passing.
func _list_area() -> Control:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(720, 180)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_rows_box = VBoxContainer.new()
	_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows_box)
	return scroll


func _row_control(at: int, description: String) -> Control:
	var row := HBoxContainer.new()
	var text := Label.new()
	text.text = "%d. %s" % [at + 1, description]
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(text)
	row.add_child(_button("Edit", func() -> void: press_edit(at)))
	row.add_child(_button("Remove", func() -> void: press_remove(at)))
	return row


## The compose/edit form.
##
## A `GridContainer` of two columns rather than a stack of rows each holding a label and a field:
## the columns are then shared BY CONSTRUCTION, which is §6's *"mirroring a layout is not sharing
## one"* — two rows built from the same width constants drift apart because the one expanding
## child absorbs whatever their minimums differ by.
func _form() -> Control:
	var grid := GridContainer.new()
	grid.columns = 2

	_subject = _picker(_subject_keys())
	_subject.item_selected.connect(func(_at: int) -> void: _refresh_form_state())
	_add_field(grid, "Subject", _subject)

	# THE OWNER IS TWO CONTROLS SHARING ONE CELL, because "player 3" needs a number and the other
	# four spellings do not. The spin box is DISABLED rather than hidden when a word is selected:
	# a control that vanishes takes its own explanation with it, and an author who picks "player…"
	# then has to find where the number went.
	var owner_cell := HBoxContainer.new()
	_owner = _picker(_owner_keys())
	_owner.item_selected.connect(func(_at: int) -> void: _refresh_form_state())
	owner_cell.add_child(_owner)
	_owner_index = SpinBox.new()
	_owner_index.min_value = 1
	_owner_index.max_value = 8
	_owner_index.value = 1
	owner_cell.add_child(_owner_index)
	_add_field(grid, "Owner", owner_cell)

	var test_cell := HBoxContainer.new()
	_compare = _picker(_compare_keys())
	test_cell.add_child(_compare)
	_value = SpinBox.new()
	# ⚠️ **NO NEGATIVES: `from_dict` REFUSES THEM** (*"nothing this counts can go below zero"*),
	# so a spin box that could reach -1 would be a control whose value is always rejected.
	_value.min_value = 0
	# HIGH ENOUGH FOR A CLOCK, which is the one subject whose numbers are large: `ticks` runs at
	# ten a second, so an hour is 36,000. A cap under that would make the time limit the one
	# condition this panel could not express.
	_value.max_value = 999999
	test_cell.add_child(_value)
	_add_field(grid, "Test", test_cell)

	_output = _picker(_output_keys())
	_add_field(grid, "Outcome", _output)

	_id_field = _line_edit("blank means any — e.g. unit.villager, building.house, food")
	_add_field(grid, "Which", _id_field)

	_area_field = _line_edit("only for subject 'area' — the region's name, spelled exactly")
	_add_field(grid, "Region", _area_field)

	_text_field = _line_edit("what the player reads — blank uses the sentence above")
	_add_field(grid, "Label", _text_field)
	return grid


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


## An `OptionButton` holding `keys`, with every id shifted off zero. See `_ID_SHIFT`.
func _picker(keys: Array[String]) -> OptionButton:
	var picker := OptionButton.new()
	for i in keys.size():
		picker.add_item(keys[i], i + _ID_SHIFT)
	if not keys.is_empty():
		# SELECTED EXPLICITLY rather than left to the default. An `OptionButton` nobody has
		# selected DISPLAYS item 0 while `get_selected_id()` answers -1, so the control would show
		# a word the record did not contain -- 16.3's Gaia-versus-player-1 fault exactly.
		picker.select(0)
	return picker


func _button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(on_press)
	return b


# ── the vocabulary, read out of `ObjectiveDef` ──────────────────────────────

## The subjects an author may choose: everything the language declares, minus what the loader
## still refuses. See the class comment on why this is derived rather than written out.
static func _subject_keys() -> Array[String]:
	var out: Array[String] = []
	for key in ObjectiveDef._SUBJECTS:
		if ObjectiveDef._NOT_YET.has(ObjectiveDef._SUBJECTS[key]):
			continue
		out.append(str(key))
	return out


static func _owner_keys() -> Array[String]:
	var out: Array[String] = []
	for key in ObjectiveDef._OWNERS:
		out.append(str(key))
	out.append(_OWNER_INDEX_LABEL)
	return out


static func _compare_keys() -> Array[String]:
	var out: Array[String] = []
	for key in ObjectiveDef._COMPARES:
		out.append(str(key))
	return out


static func _output_keys() -> Array[String]:
	var out: Array[String] = []
	for key in ObjectiveDef._OUTPUTS:
		out.append(str(key))
	return out


static func _output_word(record: Dictionary) -> String:
	return str(record.get("output", "win")).to_lower()


# ── the form's own state ────────────────────────────────────────────────────

## What `picker` is showing, as the word the record carries.
##
## Reads the TEXT rather than mapping the id back through the key list, so there is one place the
## two can be related and it is `_picker()`. `get_selected()` is -1 for an unselected control and
## `get_item_text(-1)` would push an error, hence the guard.
static func _selected_key(picker: OptionButton) -> String:
	var at := picker.get_selected()
	return picker.get_item_text(at) if at >= 0 else ""


static func _select_key(picker: OptionButton, key: String) -> void:
	for i in picker.item_count:
		if picker.get_item_text(i) == key:
			picker.select(i)
			return
	# A KEY THE PICKER HAS NOT GOT LEAVES ITEM 0 SELECTED rather than deselecting the control.
	# Reachable from an opened map whose condition names a subject this build refuses -- and
	# `select(-1)` there would draw a BLANK box, which reads as a broken panel rather than as a
	# row the tool cannot represent. The row's own `⚠ unreadable` line in the list is what says so.
	if picker.item_count > 0:
		picker.select(0)


func _reset_form() -> void:
	# THE DEFAULTS ARE `from_dict`'s, so a freshly opened form spells the row the loader would
	# build from an empty record -- the panel and the language agreeing about what "nothing
	# specified" means.
	fill_form({"subject": "unit", "owner": "self", "compare": ">=", "value": 1, "output": "win"})


## Enable and label the controls for what is currently selected.
##
## ⚠️ **`_owner_index` AND `_area_field` ARE DISABLED RATHER THAN HIDDEN, AND THE ADD BUTTON
## CHANGES ITS WORD.** A disabled control still says what it is for; a hidden one takes its
## explanation with it. This is also the panel's only defence against the *other* half of §6's
## row about disabled controls — *"a disabled control's reason for being disabled is not the same
## fact as its being disabled"* — which is why the region field's placeholder names the subject it
## belongs to rather than merely greying out.
func _refresh_form_state() -> void:
	if _subject == null or _filling:
		return
	_owner_index.editable = _selected_key(_owner) == _OWNER_INDEX_LABEL
	_area_field.editable = _selected_key(_subject) == "area"
	if _add_button != null:
		_add_button.text = "Update" if _editing >= 0 else "Add"
	if _cancel_button != null:
		# ⚠️ **DISABLED AND NOT HIDDEN**, the same rule one line up: a Cancel that appears and
		# disappears as rows are selected is a control an author cannot learn the position of.
		_cancel_button.disabled = _editing < 0
