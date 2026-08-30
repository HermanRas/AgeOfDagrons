## The chat WIDGET -- voice bar, player tabs, message log, composer (PLAN.md 8.4b).
##
## SPLIT OUT OF `ChatPanel` ON 2026-08-30, when the project owner asked the lobby to
## *"duplicate chat panel from mini map button"*. Duplicate is the one thing not done:
## this is the widget, and both places hold the same one. A second copy of a wireframe
## would be two layouts to keep in step, and the moment chat gets a real transport it
## would be two places to wire it into -- with the lobby's copy the one nobody
## remembers.
##
## A `VBoxContainer` rather than a page, so it drops into anything. `ChatPanel` is now
## the dimmed full-screen chrome around one of these; `SkirmishScreen` puts one in the
## left two thirds of the lobby.
##
## A WIREFRAME, and the project owner asked for it as one: the layout is real so the art
## can be drawn against it, and there is no chat transport underneath. What makes it a
## wireframe rather than a mock-up is that everything it CAN know, it knows for real --
## the player tabs are the actual players, with their actual colours, so the row is the
## right width with the right number of chips in it. Only the messages are invented, and
## they are drawn in the note colour with a marker saying so.
##
## EVERY CONTROL HERE IS DISABLED, and that is load-bearing rather than lazy. A wireframe
## whose buttons worked locally would be worse than one whose buttons do not: a message
## that appears on your own screen and nowhere else is a bug report waiting to happen,
## and a MICROPHONE toggle that flips is a player believing they are being heard. The
## roster grid in `SelectionPanel` is the standing lesson here -- it drew, took taps and
## played the click sound for the whole life of the project while doing nothing.
##
## WHAT THE REAL THING NEEDS, so the next person does not have to re-derive it:
## an ordinary reliable RPC pair on `Net` (`say()` up, `_recv_say()` down),
## rebroadcast by the host so it cannot be forged for somebody else -- the same
## `_recv_command` trick that makes `ResignCommand` safe -- plus a decision about
## whether chat is all-players or per-team, which is a design question and not a
## coding one. It is NOT a `Command`: chat changes no sim state, so putting it
## through the tick would give it a 100 ms floor and put text in `state_hash()`.
class_name ChatBoard
extends VBoxContainer

const _TAB_MIN := Vector2(150.0, 40.0)
const _CHIP := 16.0

## THE VOICE ROW ALONG THE TOP (project owner, 2026-08-30: *"voice toggles on the top
## with messanger contols at the bottom"*). Label, and whether it starts lit.
##
## `CheckButton`s rather than plain buttons, because a toggle has to show a STATE and
## these have one to show even with nothing behind them: a player looking at this page
## should be able to see at a glance that their microphone is the thing that is off.
## They are disabled like everything else here, and a disabled CheckButton still draws
## its knob on the side it is set to.
##
## The defaults are the ones a voice feature would want on its first run: speakers up,
## microphone down, push-to-talk on. Nobody is joined to a voice channel they did not
## ask to be heard on.
const _VOICE_TOGGLES: Array = [
	["Speakers", true],
	["Microphone", false],
	["Push to talk", true],
]

## The quick phrases beside the message field. A stand-in for whatever the real thing
## offers, and there for the same reason `_SAMPLE_LINES` is: a row of controls is the
## wrong shape to draw art against unless something plausible is in it.
const _QUICK_PHRASES: Array[String] = ["Attack!", "Help!", "Yes", "No"]

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
var _quick_buttons: Array[Button] = []

## The voice toggles along the top, by label, so a preview or a test can look at one
## without walking the tree. Held for `GameScene.corner_buttons`' reason: on this screen
## a control wired to nothing has twice looked exactly like a working one.
var voice_toggles: Dictionary = {}

## The message field at the bottom. A `TouchLineEdit` rather than a `LineEdit` for the
## reason the lobby's join field records: this project turns off mouse emulation from
## touch, so a plain field never takes focus from a finger and never raises a keyboard.
## It is disabled anyway today -- but a wireframe whose field is the WRONG CLASS is one
## that will be found not to work on the day it is wired up, which is exactly the class
## of surprise the join field cost.
var _message_field: TouchLineEdit


func _init() -> void:
	add_theme_constant_override("separation", 10)

	# VOICE ALONG THE TOP, above the player row it applies to.
	add_child(_build_voice_row())

	# WHO IS IN THE MATCH, along the top, the way the mockup draws it. Filled by
	# `show_players()`; empty until the first snapshot arrives, which is a state a page
	# opened on the very first frame can genuinely be in -- and the state the lobby is
	# in before anybody has joined.
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 8)
	add_child(_tabs)

	# The log SCROLLS, and it has to: four sample lines fit and forty would not, and
	# a page that grew past its own frame is the failure mode `ResourceHUD` records.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	_log = VBoxContainer.new()
	_log.add_theme_constant_override("separation", 8)
	_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_log)

	# MESSENGER CONTROLS ALONG THE BOTTOM: the field you would type in, what you would
	# press to send it, and the quick phrases beside it.
	add_child(_build_composer_row())

	# Says it to whoever is LOOKING AT THE SCREEN, not to whoever is reading this file:
	# the project owner reviews by screenshot, and a picture of a chat page is
	# indistinguishable from a working chat unless the page itself says otherwise.
	add_child(HudPanel.note_label(
			"Wireframe — layout only. Nothing typed here goes anywhere yet: there is no "
			+ "chat transport (PLAN.md 8.4b), and no voice transport at all. The player "
			+ "tabs above are real."))

	_rebuild_log([])


## The voice bar. Every control here is DISABLED, and the header says why.
func _build_voice_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.add_child(HudPanel.text_label("VOICE", 16))

	for spec in _VOICE_TOGGLES:
		var label := String(spec[0])
		var toggle := CheckButton.new()
		toggle.text = label
		toggle.button_pressed = bool(spec[1])
		toggle.disabled = true
		toggle.focus_mode = Control.FOCUS_NONE
		# SHRINK, or the row's height stretches each of these into a plate the size of a
		# playing card -- a `CheckButton` wears the theme's painted Button nine-patch,
		# and it scales.
		toggle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		voice_toggles[label] = toggle
		row.add_child(toggle)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)

	# The one honest thing this row can say today.
	#
	# AUTOWRAP OFF -- see `HudPanel.note_label`, which autowraps and says at length what
	# that does to a label in an HBox with no width. This one sat after an expanding
	# spacer, so it was squeezed to its narrowest box, wrapped to one character per
	# line, and grew a 300 px column of single letters that stretched the three toggles
	# beside it and crushed the message log below to nothing.
	var note := HudPanel.note_label("no voice channel", 13)
	note.autowrap_mode = TextServer.AUTOWRAP_OFF
	note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(note)
	return row


## The composer: field, send, quick phrases. Disabled for the voice row's reason.
func _build_composer_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	_message_field = TouchLineEdit.new()
	_message_field.placeholder_text = "Message your allies…"
	_message_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_message_field.editable = false
	row.add_child(_message_field)

	_send_button = Button.new()
	_send_button.text = "SEND"
	_send_button.custom_minimum_size = Vector2(110.0, 40.0)
	_send_button.disabled = true
	row.add_child(_send_button)

	for phrase in _QUICK_PHRASES:
		var quick := Button.new()
		quick.text = phrase
		quick.disabled = true
		_quick_buttons.append(quick)
		row.add_child(quick)
	return row


## The players in this conversation, from the snapshot's `player_state` -- which
## carries every player's id and colour (SnapshotSystem.build), so this needs nothing
## the client is not already told.
##
## THE LOBBY BUILDS THE SAME SHAPE OUT OF ITS SLOTS rather than out of a snapshot,
## because before a match there is no snapshot and the slot rows are the only roster
## there is. That is why this takes a plain dictionary and not a `SimWorld` or a
## `MatchConfig`: the argument is the one thing both callers can produce.
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
