## The CHAT page behind the minimap's top-left corner button (PLAN.md 8.4b).
##
## A WIREFRAME, and the project owner asked for it as one: the layout is real so
## the art can be drawn against it, and there is no chat transport underneath. What
## makes it a wireframe rather than a mock-up is that everything it CAN know, it
## knows for real -- the player tabs are the actual players in this match, with
## their actual colours off the snapshot, so the row is the right width with the
## right number of chips in it. Only the messages are invented, and they are drawn
## in the note colour with a marker saying so.
##
## SEND and CLEAR are present and DISABLED. A wireframe whose buttons worked
## locally would be worse than one whose buttons do not: a message that appears on
## your own screen and nowhere else is a bug report waiting to happen, and on this
## project the "beware fixtures that agree with the bug" note exists precisely
## because something that looked finished was not. Disabled says which half is
## missing.
##
## WHAT THE REAL THING NEEDS, so the next person does not have to re-derive it:
## an ordinary reliable RPC pair on `Net` (`say()` up, `_recv_say()` down),
## rebroadcast by the host so it cannot be forged for somebody else -- the same
## `_recv_command` trick that makes `ResignCommand` safe -- plus a decision about
## whether chat is all-players or per-team, which is a design question and not a
## coding one. It is NOT a `Command`: chat changes no sim state, so putting it
## through the tick would give it a 100 ms floor and put text in `state_hash()`.
class_name ChatPanel
extends HudPanel

const _TAB_MIN := Vector2(150.0, 40.0)
const _CHIP := 16.0

## The sample conversation, so the log area has the right shape and the right
## number of lines in it. Rendered against the REAL player names below, which is
## why this is bodies without speakers.
const _SAMPLE_LINES: Array[String] = [
	"Ready to attack the stone ruins. Need archers!",
	"Sending resources now.",
	"Villagers are exposed near the western river!",
	"I will defend the southern ford.",
]

var _tabs: HBoxContainer
var _log: VBoxContainer
var _send_button: Button
var _clear_button: Button


func _init() -> void:
	# The chrome, and it is not optional -- see `HudPanel._init`.
	super()
	set_title("CHAT")

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	body.add_child(column)

	# WHO IS IN THE MATCH, along the top, the way the mockup draws it. Filled by
	# `show_players()`; empty until the first snapshot arrives, which is a state a
	# page opened on the very first frame can genuinely be in.
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 8)
	column.add_child(_tabs)

	# The log SCROLLS, and it has to: four sample lines fit and forty would not, and
	# a page that grew past its own frame is the failure mode `ResourceHUD` records.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	_log = VBoxContainer.new()
	_log.add_theme_constant_override("separation", 8)
	_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_log)

	# Says it to whoever is LOOKING AT THE SCREEN, not to whoever is reading this
	# file: the project owner reviews by screenshot, and a picture of a chat page is
	# indistinguishable from a working chat unless the page itself says otherwise.
	column.add_child(HudPanel.note_label(
			"Wireframe — layout only. Nothing typed here goes anywhere yet: there is no "
			+ "chat transport (PLAN.md 8.4b). The player tabs above are real."))

	# SEND / CLEAR / CLOSE, in the mockup's order, which is why CLOSE is added last
	# here rather than left to `HudPanel.open()`'s safety net.
	_send_button = add_button("SEND MESSAGE", Callable())
	_clear_button = add_button("CLEAR CHAT", Callable())
	for b in [_send_button, _clear_button]:
		b.disabled = true
	add_close_button()

	_rebuild_log([])


## The players in this match, from the snapshot's `player_state` -- which carries
## every player's id and colour (SnapshotSystem.build), so this needs nothing the
## client is not already told.
##
## Safe to call on every snapshot; it rebuilds, which at eight tabs is cheaper than
## deciding what changed. `GameScene` calls it only when the page is open.
func show_players(player_state: Dictionary, local_id: int) -> void:
	for child in _tabs.get_children():
		_tabs.remove_child(child)
		child.queue_free()

	var ids: Array = player_state.keys()
	# SORTED, because dictionary order is not guaranteed and a chat tab row that
	# reshuffled itself between snapshots would be unusable.
	ids.sort()

	var names: Array[String] = []
	for id in ids:
		var entry: Dictionary = player_state[id]
		var pid := int(id)
		var label := "Player %d%s" % [pid, " (you)" if pid == local_id else ""]
		names.append(label)
		_tabs.add_child(_tab(label, int(entry.get("colour", 0)),
				bool(entry.get("defeated", false))))

	_rebuild_log(names)


## One player's tab: their colour as a chip, their name beside it. A defeated
## player is dimmed rather than dropped -- they are still in the conversation, and
## a tab row that shrank as players lost would move every other tab under a
## thumb already on its way to one.
func _tab(text: String, colour_index: int, defeated: bool) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = _TAB_MIN
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.35)
	style.border_color = Color(HudStyle.GOLD, 0.5)
	style.set_border_width_all(1)
	style.set_content_margin_all(6)
	panel.add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)

	row.add_child(HudPanel.colour_chip(colour_index, _CHIP))
	row.add_child(HudPanel.text_label(text, 14))
	if defeated:
		panel.modulate = Color(1.0, 1.0, 1.0, 0.45)
	return panel


## The sample conversation, spoken by whoever is actually in the match. Every line
## is drawn in the note colour, and the marker above them says what they are --
## without that, a screenshot of this page is indistinguishable from a screenshot
## of a working chat.
func _rebuild_log(names: Array[String]) -> void:
	for child in _log.get_children():
		_log.remove_child(child)
		child.queue_free()

	_log.add_child(HudPanel.note_label("— sample messages, not a transcript —", 13))
	if names.is_empty():
		return
	for i in range(_SAMPLE_LINES.size()):
		_log.add_child(HudPanel.note_label(
				"%s: %s" % [names[i % names.size()], _SAMPLE_LINES[i]], 15))
