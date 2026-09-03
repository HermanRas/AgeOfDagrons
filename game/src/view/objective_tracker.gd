## The live objective list (PLAN.md 15.6): what this scenario asks for, and how far along
## each row is, in the corner of the match HUD for as long as the match lasts.
##
## ## WHY IT EXISTS AT ALL, WHICH IS NOT "TO LOOK COMPLETE"
##
## `ScenarioBriefing` states the goal ONCE and is dismissed by an X. Everything after that
## is memory, and 15.2's play-test is what proved memory is not enough: the owner stopped
## building because they could not see how far along they were, on a scenario that was
## winnable the whole time. A goal a player cannot check is a goal they are guessing at,
## and *"nothing happens"* is what a rule that is correct-but-unreached looks like from the
## player's chair -- the same shape as a rule that is wrong.
##
## ## IT READS THE SIM'S OWN NUMBERS AND COMPUTES NOTHING
##
## `SimPlayer.objective_progress` and `.objective_done` are written by `ObjectiveSystem`
## and ride `player_state` on every snapshot, so this widget is a renderer of facts the
## server already decided. It must stay that way: a tracker that counted villagers itself
## would be a second evaluator, and the tick it disagreed with the server would be a
## player watching "14 / 14" while the match refused to end. PLAN.md 4's invariant with
## the volume turned down -- if the client decides it won, the client can decide it won.
##
## ⚠️ **THE PROGRESS BELONGS TO `MatchConfig.objective_player_id`, NOT TO THE VIEWER.**
## Only that player's row is ever filled (`ObjectiveSystem` writes one player's), so a
## co-op client reading its OWN `player_state` would find an empty list and draw a tracker
## with no numbers in it. `GameScene` is what picks the row; this takes what it is handed.
##
## ## WIN ROWS ONLY
##
## An `alert` row is a MESSAGE and not a goal -- `GameScene` delivers it as a toast when it
## latches -- and a `lose` row is a failure condition whose "progress" reads as an
## instruction: *"Lose your town centre 1 / 1"* is a checklist item nobody wants ticked.
## The author states those in `message` prose, where they can be worded. `_ROW_OUTPUTS` is
## the one place that decision lives, so showing lose rows later is a one-line change
## rather than a hunt.
##
## Row order is the AUTHOR'S order, and the index into `objective_progress` is kept beside
## each row rather than re-derived -- the progress array is indexed by position in the FULL
## objective list, alerts and losses included, so a tracker that renumbered its own rows
## would show scenario 1's house count against its villager target.
##
## Built in `_init()` rather than `_ready()`, the convention every widget here follows, so
## a bare `.new()` is fully wired for a headless test.
class_name ObjectiveTracker
extends PanelContainer

## Wide enough for an authored line at `_ROW_FONT_SIZE` plus its count, and narrow enough
## to sit between the control-group stack and the age header at 1152 (86 + 300 = 386
## against the header's left edge at 493). Rows autowrap, so a longer line costs height
## rather than width -- which is the axis with room, since the stack below it ends at 340.
const PANEL_WIDTH := 300.0

const _TITLE_FONT_SIZE := 15
const _ROW_FONT_SIZE := 14

## The plate's painted border eats this much on each side. `ScenarioBriefing`'s figures
## scaled down for a smaller panel: `HudStyle.PANEL_MARGIN` is 12, and text drawn inside
## that lands on the moulding.
const _MARGINS := {"left": 18, "right": 18, "top": 14, "bottom": 14}

## The tick column, and the count column. Fixed so every row's text starts and ends at the
## same x -- a ragged left edge reads as three unrelated labels rather than as a list.
const _MARK_WIDTH := 16.0
const _COUNT_WIDTH := 62.0

## Which outputs get a row. See the header: this is the whole of that decision.
const _ROW_OUTPUTS: Array[int] = [ObjectiveDef.Output.WIN]

## A completed row. Gold is the HUD's "this is yours and it is good" colour (the age badge,
## every panel title); a pending row is left at the theme's own body colour, so the
## difference between the two is a change in one thing rather than two shades a player has
## to compare.
const DONE_COLOR := Color("#E5B842")

## ⚠️ **THE TICK IS DRAWN, NOT TYPED, BECAUSE THE SHIPPED FACE HAS NO CHECK MARK.**
## Measured rather than assumed, which is the only reason this is known: New Rocker
## (`UiFont.BODY_PATH`) answers `has_char` FALSE for U+2713, U+2714 and U+2717, and for
## every geometric substitute worth trying -- ●, ○, ■, ★, √. What it does have is `•`, `»`,
## `†`, `§` and ASCII. A missing glyph does not fail loudly; it draws a tofu box, and the
## first render of this panel put a literal `*` beside a completed objective.
##
## A `_draw` costs twelve lines, cannot be broken by a font swap, and is the mark the
## player expects. See `TickMark`.
class TickMark extends Control:
	var colour := Color.WHITE

	var done := false:
		set(value):
			done = value
			queue_redraw()

	func _draw() -> void:
		if not done:
			return
		var w := size.x
		var h := size.y
		# Proportions rather than pixels, so the mark follows `_ROW_FONT_SIZE` if that ever
		# moves. Antialiased: at 16 px a hard-edged diagonal reads as a staircase.
		draw_polyline([Vector2(w * 0.18, h * 0.52), Vector2(w * 0.42, h * 0.78),
				Vector2(w * 0.88, h * 0.18)], colour, 2.0, true)

## One entry per drawn row: `{index, mark, text, count, def}`. `index` is the position in
## the FULL objective list and is what `show_progress` reads by.
var _rows: Array[Dictionary] = []

var _title: Label
var _column: VBoxContainer

## Latched, so the two paths into `GameScene._start_match()` cannot build the list twice.
## Same reason and same shape as `ScenarioBriefing._shown`.
var _built := false


func _init() -> void:
	visible = false
	# IGNORE, ON EVERY NODE AND NOT ONLY THE ROOT. `mouse_filter` does not inherit, and
	# `NoticeToast`'s header records what a widget that quietly takes presses costs: an
	# invisible hole in the HUD that read as three build-menu tiles being broken. This one
	# has nothing to press, sits over the map, and must let a tap through to the world.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(PANEL_WIDTH, 0.0)
	# The box is its content's height and no more -- an empty tracker is hidden outright,
	# and a two-row one should not reserve room for five.
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	HudStyle.add_panel_background(self)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in _MARGINS:
		margin.add_theme_constant_override("margin_%s" % side, int(_MARGINS[side]))
	add_child(margin)

	_column = VBoxContainer.new()
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_theme_constant_override("separation", 6)
	margin.add_child(_column)

	_title = Label.new()
	_title.text = "OBJECTIVES"
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiFont.title(_title, _TITLE_FONT_SIZE, true)
	_title.add_theme_color_override("font_color", HudStyle.GOLD)
	_column.add_child(_title)


## Build the list from the config's objectives. Idempotent -- `GameScene._start_match()`
## runs twice on a client whose config arrived late.
##
## AN EMPTY RESULT SHOWS NOTHING, which is every skirmish, every debug factory and the
## three How To Play missions that are won by conquest: `ScenarioDef` refuses objectives
## on a `last_man_standing` scenario, so those carry none. An empty panel with a heading
## on it is worse than no panel, for `ScenarioBriefing.show_message`'s reason.
func setup(objectives: Array[ObjectiveDef]) -> void:
	if _built:
		return
	_built = true
	for i in range(objectives.size()):
		var o := objectives[i]
		if not _ROW_OUTPUTS.has(int(o.output)):
			continue
		_rows.append(_add_row(i, o))
	visible = not _rows.is_empty()


## This tick's figures. `progress` and `done` are `SimPlayer.objective_progress` and
## `.objective_done` off `player_state`, indexed by position in the full objective list.
##
## SHORT OR ABSENT IS NORMAL AND IS NOT AN ERROR. `ObjectiveSystem` sizes both arrays on
## its first tick (`VisionSystem`'s convention: empty means "nothing evaluated yet", not
## "a list of zeros"), so the snapshot that stands the match up carries neither -- and a
## row is simply left at its opening state rather than being drawn as a zero the sim never
## said.
func show_progress(progress: Array, done: Array) -> void:
	for row in _rows:
		var i: int = row["index"]
		var measured: int = int(progress[i]) if i < progress.size() else -1
		var is_done: bool = i < done.size() and int(done[i]) != 0
		(row["count"] as Label).text = _progress_text(row["def"], measured)
		var colour: Color = DONE_COLOR if is_done else _pending_colour()
		(row["text"] as Label).add_theme_color_override("font_color", colour)
		(row["count"] as Label).add_theme_color_override("font_color", colour)
		var mark: TickMark = row["mark"]
		mark.colour = colour
		mark.done = is_done


## What the count column says.
##
## ⚠️ **THE COMPARISON DECIDES THE SENTENCE, NOT ONLY THE ARITHMETIC.** `4 / 14` is
## progress towards a floor and reads correctly for `>=`; the same two numbers under `<=`
## would tell a player to climb towards a number they must stay below -- PLAN.md 11.8's
## own example, *leave the enemy nothing*, is `<= 0`, and "3 / 0" reads as a bug. So an
## at-most row says what its number is FOR.
##
## A measurement of -1 is `ObjectiveSystem._count`'s "cannot be measured" sentinel, which
## no shipped row can produce -- `ObjectiveDef` refuses the three unevaluable subjects at
## load. It is drawn as a dash rather than as a number, because printing -1 in a HUD is
## how a sentinel becomes a bug report about arithmetic.
func _progress_text(o: ObjectiveDef, measured: int) -> String:
	if measured < 0:
		return "--"
	# AT_LEAST and EXACTLY share a form on purpose: both are numbers to arrive AT, and
	# "3 / 3" is right for either. Only the ceiling needs saying out loud.
	if o.compare == ObjectiveDef.Compare.AT_MOST:
		return "%d / max %d" % [measured, o.value]
	return "%d / %d" % [measured, o.value]


func _add_row(index: int, o: ObjectiveDef) -> Dictionary:
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override("separation", 4)
	_column.add_child(line)

	# SHRINK_BEGIN, so the mark stays beside the FIRST line of a row that wrapped to three
	# rather than floating down the middle of it.
	var mark := TickMark.new()
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.custom_minimum_size = Vector2(_MARK_WIDTH, float(_ROW_FONT_SIZE) + 2.0)
	mark.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	line.add_child(mark)

	# THE AUTHOR'S OWN WORDS WHERE THERE ARE ANY. `describe()` is never empty and is the
	# fallback, because a row with no label is a line the player reads as a bug.
	var text := Label.new()
	text.text = o.describe()
	text.add_theme_font_size_override("font_size", _ROW_FONT_SIZE)
	# WORD SMART, and the width comes from EXPAND_FILL rather than from a minimum: a Label
	# reports its whole unwrapped line as its minimum width, which would push this panel
	# as wide as the longest objective anybody authors. `ScenarioBriefing._body` pays for
	# the same lesson one container further out.
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(text)

	var count := Label.new()
	count.custom_minimum_size = Vector2(_COUNT_WIDTH, 0.0)
	count.add_theme_font_size_override("font_size", _ROW_FONT_SIZE)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	count.text = _progress_text(o, -1)
	line.add_child(count)

	return {"index": index, "def": o, "mark": mark, "text": text, "count": count}


## The theme's own body colour, so a pending row is not a hardcoded near-white that stops
## matching the day the theme changes. `Control.get_theme_color` falls back to the default
## theme outside a tree, which is what a headless test runs in.
func _pending_colour() -> Color:
	return get_theme_color(&"font_color", &"Label")


## How many rows are drawn, which is the WIN rows and not the objective count. For tests
## and for `GameScene`, which shows nothing when this is zero.
func row_count() -> int:
	return _rows.size()


## One row's WORDS as the player reads them: `"Build a house  0 / 1"`. The tick is not in
## it -- it is drawn rather than typed (see `TickMark`) and `row_is_done` is the question
## about it -- so this is the text half of the screenshot in one string, which is what lets
## a test assert what the panel says rather than that a Label exists somewhere inside it.
func row_line(row: int) -> String:
	if row < 0 or row >= _rows.size():
		return ""
	var r := _rows[row]
	return "%s  %s" % [(r["text"] as Label).text, (r["count"] as Label).text]


## Whether row `row` is drawn as complete. Read off the MARK ITSELF rather than off a flag
## this class kept beside it, so it answers what is on the screen and not what it was told.
func row_is_done(row: int) -> bool:
	if row < 0 or row >= _rows.size():
		return false
	return (_rows[row]["mark"] as TickMark).done


## What colour a row is drawn in. The tick is the primary signal and this is the second
## one; both are asserted, because "ticked" and "ticked and still grey" are two different
## screenshots and only one of them reads as done.
func row_colour(row: int) -> Color:
	if row < 0 or row >= _rows.size():
		return Color.TRANSPARENT
	return (_rows[row]["text"] as Label).get_theme_color(&"font_color")


## Which objective a drawn row came from. The mapping the header is about: row 0 of a
## tracker is not objective 0 when the author put an alert first.
func row_index(row: int) -> int:
	if row < 0 or row >= _rows.size():
		return -1
	return int(_rows[row]["index"])
