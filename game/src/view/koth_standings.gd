## KING OF THE HILL's standings panel (PLAN.md 11.9, card 11.x-koth-hud).
##
## **THE OWNER ASKED FOR IT BY PLAYING WITHOUT IT**, 2026-09-11: *"the objective pannel from
## Campaign, is missing showing time to win, players has not idea how far they are, but win and
## lose is working correctly."* The mode was decidable and illegible — a rule you can only lose to,
## which is the same sentence 11.2 used to argue for the minimap ring.
##
## It is `ObjectiveTracker`'s sibling and deliberately not a reuse of it: that widget's rows are
## built from `ObjectiveDef`s and marked with a tick, and a KotH row is a player with a clock.
## Forcing one through the other would mean fabricating objectives that no scenario declares.
## **What IS shared is the position and the chrome** — top-left beside the control-group stack,
## `HudStyle.add_panel_background`, the same margins and font sizes — because the two never appear
## together: the tracker is scenario-only and this is KotH-only.
##
## ## ⚠️ WHAT A ROW SAYS, AND THE OWNER RULED IT
##
## **Time at the player's CURRENT rate** (2026-09-11), chosen over a best-rate reading. §11.9's
## ladder pays 3 / 2 / 1, so the same side reads **5:00 alone and 15:00 contested** — and the number
## moving when the hill contests is the whole of what the ladder does, so it is information rather
## than noise. The alternative was stable and always optimistic, which is the kind of number that
## gets believed.
##
## ⚠️ **A PLAYER WITH NOBODY ON THE HILL HAS NO FINITE TIME AND GETS A DASH.** Not "0:00", which
## means they have arrived, and not a blank, which reads as a widget that failed to draw.
## `GameView.koth_seconds_remaining` answers -1 for it.
##
## ## 📝 ROWS ARE IN PLAYER ORDER AND DO NOT RE-SORT
##
## A scoreboard sorted by score is the obvious thing and is wrong here: scores step by 1, 2 or 3
## with ties everywhere, so rows would swap constantly and a player could not find their own.
## Fixed order, and the **leader is marked instead** — which is also what the minimap ring says, so
## the two agree. Same instinct as `SelectionActions`' *"the slot must not move under the player's
## thumb"*, applied to a panel nobody presses.
class_name KothStandings
extends PanelContainer

## Matches `ObjectiveTracker.PANEL_WIDTH` — they occupy the same slot and a player who plays a
## campaign and then a skirmish should not see the furniture change size.
const PANEL_WIDTH := 300.0

const _TITLE_FONT_SIZE := 15
const _ROW_FONT_SIZE := 14

const _MARGINS := {"left": 18, "right": 18, "top": 14, "bottom": 14}

## The swatch, the score and the clock. Fixed so every row's columns line up; a ragged edge reads
## as unrelated labels rather than as a table. The name takes whatever is left.
const _SWATCH := 10.0
const _SCORE_WIDTH := 54.0
const _TIME_WIDTH := 54.0

## The side currently holding the hill. `HudStyle.GOLD` is the HUD's "this is the good one"
## throughout — the age badge, every panel title, `ObjectiveTracker`'s completed rows.
const LEADER_COLOR := Color("#E5B842")

## A player on the hill but not leading it. Readable, and plainly not the gold.
const PRESENT_COLOR := Color("#D8D8D8")

## Nobody on the hill: the row is still there — a player who vanished from the table would read as
## eliminated — but it is dimmed, because it is not participating in the race this tick.
const IDLE_COLOR := Color("#8A8A8A")

## ⚠️ **ASCII, AND THAT IS DELIBERATE RATHER THAN LAZY.** The obvious character here is an em dash,
## and §6 records what the shipped body face does with a glyph it lacks: **nothing visible fails —
## it draws a tofu box**, which in a screenshot reads as a broken widget rather than as a missing
## font. New Rocker was measured to lack ✓ ✗ ● ○ ■ ▪ ★ √, and U+2014 is not on the list of what it
## was measured to HAVE (`•`, `»`, `†`, `§`, `·` and ASCII). Two hyphens cost nothing and cannot
## fail. 15.6 shipped a literal `*` beside a completed objective for exactly this reason.
const NO_TIME := "--"

## `{id, swatch, name, score, time}` per player, in player order.
var _rows: Array[Dictionary] = []

var _title: Label
var _column: VBoxContainer
var _built := false


func _init() -> void:
	visible = false
	# IGNORE ON EVERY NODE, not only the root: `mouse_filter` does not inherit, and this panel
	# sits over the map with nothing to press. `NoticeToast`'s header records what a widget that
	# quietly eats presses costs — an invisible hole in the HUD.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(PANEL_WIDTH, 0.0)
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
	_title.text = "KING OF THE HILL"
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiFont.title(_title, _TITLE_FONT_SIZE, true)
	_title.add_theme_color_override("font_color", HudStyle.GOLD)
	_column.add_child(_title)


## Build one row per player. Idempotent, for `ObjectiveTracker.setup`'s reason: both paths into
## `GameScene._start_match()` run it, and a client whose config arrived late runs it twice.
##
## **AN EMPTY PLAYER LIST SHOWS NOTHING**, which is every non-KotH match — `GameScene` only calls
## this when the mode is `KING_OF_THE_HILL`, and a panel with a heading and no rows is worse than
## no panel (`ScenarioBriefing.show_message`'s rule).
func setup(player_ids: Array, local_player_id: int = 0) -> void:
	if _built:
		return
	_built = true
	for pid in player_ids:
		_rows.append(_add_row(int(pid), int(pid) == local_player_id))
	visible = not _rows.is_empty()


## This tick's figures, from the snapshot. `view` supplies the tally, the rung and the holder —
## all three off the wire, none of them counted here.
func show_standings(view: GameView, holder: int) -> void:
	for row in _rows:
		var pid := int(row["id"])
		var rate := view.koth_rate(pid)
		var secs := view.koth_seconds_remaining(pid)
		# THE SWATCH IS REFRESHED HERE RATHER THAN AT BUILD TIME, because `setup()` runs before
		# any snapshot has arrived and `colour` rides `player_state` -- colouring once at build
		# would give every row the neutral tint for the life of the match. Eight assignments a
		# tick is not worth a "have the skins landed yet" flag to avoid.
		var idx := int(view.skin_for(pid).get("colour", -1))
		(row["swatch"] as ColorRect).color = GameDataRegistry.colour(idx) if idx >= 0 \
				else IDLE_COLOR
		(row["score"] as Label).text = _grouped(view.koth_score(pid))
		(row["time"] as Label).text = format_time(secs)
		# THE HOLDER IS THE SIDE THE RING IS DRAWN IN, so the panel and the minimap cannot
		# disagree about who is ahead. A tie has no holder and nobody is gold — correct, and the
		# state most likely to be read as a bug (see `_king_of_the_hill()`).
		var colour := IDLE_COLOR
		if pid == holder:
			colour = LEADER_COLOR
		elif rate > 0:
			colour = PRESENT_COLOR
		for key in ["name", "score", "time"]:
			(row[key] as Label).add_theme_color_override("font_color", colour)


## `M:SS`, or `NO_TIME` for "no finite time". Public so a test can assert the formatting without
## standing up a view — the dash is the case worth pinning and it is easy to render as "-1:00".
static func format_time(seconds: float) -> String:
	if seconds < 0.0:
		return NO_TIME
	var whole := int(ceil(seconds))
	return "%d:%02d" % [whole / 60, whole % 60]


## Thousands separated, because `2730` and `27300` are hard to tell apart at a glance and the
## target is five figures.
static func _grouped(n: int) -> String:
	var s := str(n)
	var out := ""
	for i in range(s.length()):
		if i > 0 and (s.length() - i) % 3 == 0:
			out += ","
		out += s[i]
	return out


func _add_row(pid: int, is_me: bool) -> Dictionary:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	_column.add_child(row)

	# THE SWATCH IS THE PLAYER'S OWN COLOUR, resolved through the registry rather than indexed
	# here: `colours.json`'s order is load-bearing and a second place indexing into it is a second
	# place to get it wrong. `GameScene` does the same for the minimap ring.
	var swatch := ColorRect.new()
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	swatch.custom_minimum_size = Vector2(_SWATCH, _SWATCH)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(swatch)

	var name_label := Label.new()
	name_label.text = "Player %d%s" % [pid, " (you)" if is_me else ""]
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# CLIPPED RATHER THAN WRAPPED: a two-line name would make one row twice the height of its
	# neighbours and the table would stop reading as a table.
	name_label.clip_text = true
	name_label.add_theme_font_size_override("font_size", _ROW_FONT_SIZE)
	row.add_child(name_label)

	var score_label := Label.new()
	score_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	score_label.custom_minimum_size = Vector2(_SCORE_WIDTH, 0.0)
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score_label.text = "0"
	score_label.add_theme_font_size_override("font_size", _ROW_FONT_SIZE)
	row.add_child(score_label)

	var time_label := Label.new()
	time_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	time_label.custom_minimum_size = Vector2(_TIME_WIDTH, 0.0)
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	time_label.text = NO_TIME
	time_label.add_theme_font_size_override("font_size", _ROW_FONT_SIZE)
	row.add_child(time_label)

	return {"id": pid, "swatch": swatch, "name": name_label,
			"score": score_label, "time": time_label}


# ── what a test reads ───────────────────────────────────────────────────────

func row_count() -> int:
	return _rows.size()


func row_player(row: int) -> int:
	return int(_rows[row]["id"]) if row >= 0 and row < _rows.size() else 0


func row_time(row: int) -> String:
	return (_rows[row]["time"] as Label).text if row >= 0 and row < _rows.size() else ""


func row_score(row: int) -> String:
	return (_rows[row]["score"] as Label).text if row >= 0 and row < _rows.size() else ""


func row_colour(row: int) -> Color:
	if row < 0 or row >= _rows.size():
		return Color.BLACK
	return (_rows[row]["name"] as Label).get_theme_color(&"font_color")
