## The running message log over the map (PLAN.md 8.4b), and the owner's eviction rule.
##
## The rule is the whole specification and it is easy to implement as the WRONG thing -- a 5 s
## lifetime per line rather than one 5 s drain -- so most of this file pins the difference.
extends TestCase


func _log() -> MessageLog:
	var m := MessageLog.new()
	# Never added to the tree: `advance()` exists precisely so the rule can be driven without
	# a frame loop. `_process` only forwards to it.
	return m


# ── what a line looks like ──────────────────────────────────────────────────

func test_a_player_line_is_named_and_a_system_line_is_not() -> void:
	var m := _log()
	m.say("P1", "ready to attack the stone ruins")
	m.say("", "Player 2 has left the match")
	assert_eq(m.lines()[0], "P1: ready to attack the stone ruins",
			"the owner's format, and ChatBoard's wireframe already shows it")
	assert_eq(m.lines()[1], "Player 2 has left the match",
			"the match talking about itself carries no speaker")
	m.free()


func test_the_newest_line_is_at_the_bottom() -> void:
	# The owner's words: "new messages are added at the bottom and old messages deleted from
	# the top". Order is the whole readability of a conversation.
	var m := _log()
	m.say("P1", "one")
	m.say("P2", "two")
	m.say("P1", "three")
	assert_eq(Array(m.lines()), ["P1: one", "P2: two", "P1: three"])
	m.free()


func test_an_empty_message_is_not_a_line() -> void:
	var m := _log()
	m.say("P1", "   ")
	m.say("", "")
	assert_eq(m.lines().size(), 0, "a blank line is a gap in the log, not a message")
	m.free()


# ── the eviction rule ───────────────────────────────────────────────────────

func test_the_oldest_line_goes_first() -> void:
	var m := _log()
	m.say("P1", "one")
	m.say("P2", "two")
	m.advance(MessageLog.EVICT_SECONDS)
	assert_eq(Array(m.lines()), ["P2: two"], "from the top, as asked")
	m.free()


func test_one_drain_empties_the_log_rather_than_each_line_having_a_lifetime() -> void:
	# ⛔ THE DISTINCTION THIS FILE EXISTS FOR. A 5 s lifetime per line would take every one of
	# these away at once, five seconds after they were posted together. The owner asked for
	# "oldest messages are deleted every 5 sec UNTIL THE TEXT BLOCK IS CLEAR" -- a drain, so
	# three lines take fifteen seconds and the last outlives the first. That is what keeps a
	# conversation on screen long enough to be read as one.
	var m := _log()
	m.say("P1", "one")
	m.say("P2", "two")
	m.say("P1", "three")

	m.advance(MessageLog.EVICT_SECONDS)
	assert_eq(m.lines().size(), 2, "one gone, not all three")
	m.advance(MessageLog.EVICT_SECONDS)
	assert_eq(m.lines().size(), 1)
	m.advance(MessageLog.EVICT_SECONDS)
	assert_eq(m.lines().size(), 0, "until the block is clear")
	m.free()


func test_a_long_wait_drains_several_at_once_rather_than_only_one() -> void:
	# A frame the game spent loading, or a test stepping coarsely. Time that has genuinely
	# passed has to count, or a stalled frame leaves the log fuller than the rule allows.
	var m := _log()
	for i in range(4):
		m.say("P1", "line %d" % i)
	m.advance(MessageLog.EVICT_SECONDS * 3.0)
	assert_eq(m.lines().size(), 1)
	m.free()


func test_time_under_the_threshold_takes_nothing() -> void:
	var m := _log()
	m.say("P1", "one")
	m.advance(MessageLog.EVICT_SECONDS * 0.9)
	assert_eq(m.lines().size(), 1, "the line is still readable")
	m.free()


func test_an_empty_log_does_not_bank_time_against_the_next_message() -> void:
	# ⚠️ THE BUG THIS PREVENTS IS INVISIBLE UNTIL SOMEBODY SPEAKS AFTER A QUIET SPELL: with
	# the accumulator left running, a log empty for a minute would evict the next arrival on
	# the very next frame, and messages would look like they were being swallowed at random.
	var m := _log()
	m.advance(MessageLog.EVICT_SECONDS * 10.0)
	m.say("P1", "hello")
	m.advance(0.1)
	assert_eq(m.lines().size(), 1, "a new line gets its own five seconds")
	m.free()


func test_a_burst_is_capped_so_it_cannot_grow_down_the_screen() -> void:
	# The bound the eviction rule does not provide on its own: messages arriving faster than
	# one per five seconds would otherwise stack without limit and become the view.
	var m := _log()
	for i in range(MessageLog.MAX_LINES + 4):
		m.say("P1", "line %d" % i)
	assert_eq(m.lines().size(), MessageLog.MAX_LINES)
	assert_eq(m.lines()[0], "P1: line 4", "the oldest went, not the newest")
	m.free()


func test_clearing_takes_everything_and_resets_the_clock() -> void:
	var m := _log()
	m.say("P1", "one")
	m.advance(MessageLog.EVICT_SECONDS * 0.9)
	m.clear()
	assert_eq(m.lines().size(), 0)
	m.say("P2", "two")
	m.advance(0.2)
	assert_eq(m.lines().size(), 1, "the next match does not inherit a part-spent timer")
	m.free()


# ── it must never take a tap ────────────────────────────────────────────────

func test_nothing_in_here_can_swallow_a_press() -> void:
	# ⛔ THE ONE THAT MATTERS MOST, and the reason is in the widget's header: this sits over
	# the MAP, which is the surface every order is issued through. A control here that took a
	# press would eat build placements and move orders inside its own rectangle, and present
	# as "the game ignored me" with nothing pointing at this file. `NoticeToast` cost a week
	# of exactly that, and `MOUSE_FILTER_IGNORE` is NOT inherited -- a Label defaults to STOP,
	# so a line added at runtime is a fresh hole unless `say()` sets it every time.
	var m := _log()
	m.say("P1", "one")
	m.say("", "two")
	assert_eq(m.mouse_filter, Control.MOUSE_FILTER_IGNORE, "the root")
	_assert_ignores(m)
	m.free()


func _assert_ignores(node: Node) -> void:
	for child in node.get_children():
		if child is Control:
			assert_eq((child as Control).mouse_filter, Control.MOUSE_FILTER_IGNORE,
					"%s would take a tap over the map" % child)
		_assert_ignores(child)
