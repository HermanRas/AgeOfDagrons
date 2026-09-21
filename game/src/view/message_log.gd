## A running log of short lines over the map: who said what, and what the match is doing
## (PLAN.md 8.4b). Newest at the bottom, oldest falling off the top.
##
## ## WHAT IT IS FOR, AND WHY IT IS NOT A `NoticeToast`
##
## `NoticeToast` answers *"that press did not work"* -- one line, centred, replacing whatever
## was there, gone in 2.5 s. It is deliberately a thing you cannot miss and cannot accumulate.
## This is the opposite shape and the two do not substitute for each other: several lines,
## kept in order, read at leisure or not at all. **A running commentary in a toast would
## overwrite itself**, and a failed placement in here would scroll away unseen.
##
## ## ⛔ EVERY NODE IS `MOUSE_FILTER_IGNORE`, AND THAT IS NOT A DETAIL
##
## The project owner asked for it *"not clickable"* and the codebase already knows why:
## `NoticeToast`'s header records a toast that took presses and was **an invisible hole in
## the build grid for a week**, and `SelectionPanel`'s roster grid drew, took taps and played
## the click sound for the whole life of the project while doing nothing. This widget sits
## over the MAP -- the one surface every order is issued through -- so a control here that
## swallowed a tap would eat build placements and move orders in whatever rectangle it
## happened to cover, which is a bug that presents as *"the game ignored me"* and points
## nowhere near this file.
##
## ⚠️ **IT IS SET ON THE ROOT, THE BOX AND EVERY LINE.** `MOUSE_FILTER_IGNORE` is not
## inherited -- a `Label` defaults to `MOUSE_FILTER_STOP` in Godot -- so a line added at
## runtime without it would be a hole that appears only once somebody speaks.
##
## ## THE OWNER'S EVICTION RULE, EXACTLY AS ASKED
##
## *"oldest messages are deleted every 5 sec until the text block is clear, new messages are
## added at the bottom and old messages deleted from the top."* That is ONE repeating 5 s
## eviction that drains the log, **not** a 5 s lifetime per line: a burst of six lines takes
## thirty seconds to clear, and the last line of a burst outlives the first. That is the
## intended reading -- it keeps a conversation on screen long enough to be a conversation,
## rather than flashing each line for five seconds and losing the thread.
##
## `MAX_LINES` is the bound the rule needs and the owner did not have to state: without it a
## burst larger than the drain rate grows down the screen without limit. Over the cap the
## oldest goes immediately, which is the same direction the timer moves in.
##
## ## ⏳ IT IS THE CHAT PANEL'S FUTURE FRONT END
##
## Owner, 2026-09-20: *"this pannel will later be used by actual chat when it lands."* So the
## entry point is `say(speaker, text)` and the shape it prints is `P1: message` -- the format
## from the owner's own sketch and the one `ChatBoard`'s wireframe log already shows. When a
## transport lands (`ChatBoard`'s header sets out what it needs: an ordinary reliable RPC pair
## rebroadcast by the host, and NOT a `Command`), it calls this and nothing here changes.
class_name MessageLog
extends Control


## How long before the oldest line is dropped. The owner's number.
const EVICT_SECONDS := 5.0

## The most lines that may stand at once. See the header: the eviction rule alone does not
## bound a burst. Six is about what fits over the map without becoming the view.
const MAX_LINES := 6

## Wide enough for a sentence, narrow enough to leave the map readable. Lines wrap inside it.
##
## Sized to the block the owner drew on a screenshot (2026-09-20) rather than chosen: it spans
## from a little wider than the minimap frame out to the right margin.
const WIDTH := 560.0

## ⛔ **A FIXED HEIGHT, AND THE LINES STACK UPWARD INSIDE IT.** The owner placed this directly
## ABOVE THE MINIMAP, so its BOTTOM edge is the one that must not move -- a box that grew
## downward from a fixed top would creep over the minimap as a conversation got longer, and one
## that grew upward from a fixed bottom without a reserved height would shove whatever sat above
## it. Reserving `MAX_LINES` worth of room and filling it from the bottom means the block never
## moves and never overruns, whether it holds one line or six.
const HEIGHT := 26.0 * MAX_LINES

const _FONT_SIZE := 14

## ⚠️ **AN OUTLINE, BECAUSE THIS DRAWS OVER TERRAIN AND NOT OVER A PANEL.** The owner's own
## screenshot has pale desert sand and near-black shadow within one screen width of each
## other, so there is no single text colour that reads on both. A dark outline round a light
## glyph reads on either, which is why subtitles have done it for fifty years.
const _OUTLINE_SIZE := 4
const _OUTLINE_COLOUR := Color(0.0, 0.0, 0.0, 0.85)

## What a line with no speaker is drawn in -- the match talking about itself rather than a
## player talking. Gold, matching every other thing on this HUD that the game says.
const SYSTEM_COLOUR := Color(0.93, 0.82, 0.50)

var _box: VBoxContainer
var _since_evict := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(WIDTH, HEIGHT)
	size = Vector2(WIDTH, HEIGHT)

	_box = VBoxContainer.new()
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_theme_constant_override("separation", 2)
	# ⛔ **FILLED FROM THE BOTTOM.** `ALIGNMENT_END` is what makes the newest line sit on the
	# block's bottom edge with older ones rising above it, rather than the first line sitting
	# at the top and the block growing down into the minimap. Append order still puts the
	# newest last, which is what the owner asked for -- this decides which END of the reserved
	# space that "last" is pinned to.
	_box.alignment = BoxContainer.ALIGNMENT_END
	_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_box)


## Put a line up. `speaker` empty means the match is talking, not a player.
##
## Returns nothing and refuses nothing: a log that could reject a message would need every
## caller to care, and there is no failure here worth a caller's attention.
func say(speaker: String, text: String, colour: Color = SYSTEM_COLOUR) -> void:
	if text.strip_edges().is_empty():
		return                    # an empty line is a gap in the log, not a message
	var line := Label.new()
	# ⛔ NOT INHERITED -- see the header. A Label defaults to STOP and would be a tap-eating
	# rectangle over the map from the moment somebody spoke.
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.custom_minimum_size = Vector2(WIDTH, 0.0)
	# ⛔ **RIGHT, BECAUSE THE BLOCK IS PINNED TO THE RIGHT** (owner, playtest 2026-09-20:
	# *"message text chat text needs to right align"*, confirmed against a screenshot of the
	# disconnect notices). `GameScene` anchors this at `PRESET_BOTTOM_RIGHT` and the lines are
	# `WIDTH` wide whatever they say, so left-aligned text left every short line trailing off
	# into the map with a ragged right edge against the minimap below it.
	#
	# 📝 **AND THE EDGE IT LANDS ON IS THE MINIMAP'S, WHICH IS MEASURED RATHER THAN LUCK.** This
	# block sits at `-WIDTH - GameScene._MINIMAP_MARGIN`, and the minimap directly beneath it is
	# `Minimap.AREA_SIZE` square at that same inset — so both right edges are `viewport - 12`.
	# Right-aligned, the text shares an edge with the panel under it, and the two keep sharing it
	# if the viewport changes shape because both are derived from the one constant.
	#
	# ⚠️ **IT IS EVERY LINE AND NOT "MINE RIGHT, THEIRS LEFT".** That is the chat-bubble idiom
	# and it is a different feature: it needs the sender compared against the local player, and
	# nothing here has a sender yet — `say()`'s `speaker` is empty for all of it, because until
	# 8.6 lands the transport this log is the match talking and not the players. Asked and
	# settled rather than guessed; revisit when real chat arrives and there is a "mine" to mean.
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	line.text = text if speaker.is_empty() else "%s: %s" % [speaker, text]
	line.add_theme_font_size_override("font_size", _FONT_SIZE)
	line.add_theme_color_override("font_color", colour)
	line.add_theme_constant_override("outline_size", _OUTLINE_SIZE)
	line.add_theme_color_override("font_outline_color", _OUTLINE_COLOUR)
	_box.add_child(line)

	# OVER THE CAP THE OLDEST GOES AT ONCE, in the same direction the timer moves. Without
	# this a burst faster than the drain grows down the screen without limit.
	while _box.get_child_count() > MAX_LINES:
		_drop_oldest()


## The lines currently standing, oldest first. For tests and for the debug overlay.
func lines() -> PackedStringArray:
	var out := PackedStringArray()
	for child in _box.get_children():
		out.append((child as Label).text)
	return out


## Drain one step. **Public and called from `_process`** so the suite can drive it: a widget
## whose only clock is the frame loop is one whose eviction rule can never be asserted, and
## the rule is the whole of what the owner specified.
func advance(delta: float) -> void:
	if _box.get_child_count() == 0:
		# RESET RATHER THAN RUN ON. An empty log accumulating credit would evict a brand new
		# line the instant it arrived, which reads as messages being swallowed at random.
		_since_evict = 0.0
		return
	_since_evict += delta
	while _since_evict >= EVICT_SECONDS and _box.get_child_count() > 0:
		_since_evict -= EVICT_SECONDS
		_drop_oldest()


## Empty it now. What a match ending uses, so the next one does not open mid-conversation.
func clear() -> void:
	for child in _box.get_children():
		child.queue_free()
		_box.remove_child(child)
	_since_evict = 0.0


func _process(delta: float) -> void:
	advance(delta)


func _drop_oldest() -> void:
	if _box.get_child_count() == 0:
		return
	var oldest := _box.get_child(0)
	_box.remove_child(oldest)
	oldest.queue_free()
