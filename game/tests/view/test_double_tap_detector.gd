## PLAN.md 10.1: the single/double-tap disambiguation control groups use to
## tell "assign" from "reselect" on the same icon.
extends TestCase


func test_two_taps_within_the_window_are_a_double_tap() -> void:
	var d := DoubleTapDetector.new()
	assert_false(d.register_tap(1000))
	assert_true(d.register_tap(1000 + DoubleTapDetector.DOUBLE_TAP_MS))


func test_two_taps_outside_the_window_are_two_singles() -> void:
	var d := DoubleTapDetector.new()
	assert_false(d.register_tap(1000))
	assert_false(d.register_tap(1000 + DoubleTapDetector.DOUBLE_TAP_MS + 1))


func test_a_double_tap_consumes_itself_so_a_third_tap_starts_fresh() -> void:
	var d := DoubleTapDetector.new()
	d.register_tap(1000)
	assert_true(d.register_tap(1100), "completes the pair")
	assert_false(d.register_tap(1150), "the pair was consumed; this is a new single")


func test_is_still_pending_true_until_a_later_tap_arrives() -> void:
	var d := DoubleTapDetector.new()
	d.register_tap(1000)
	assert_true(d.is_still_pending(1000))
	d.register_tap(1500)
	assert_false(d.is_still_pending(1000), "superseded by the later tap")


func test_is_still_pending_false_once_a_double_tap_consumes_it() -> void:
	var d := DoubleTapDetector.new()
	d.register_tap(1000)
	d.register_tap(1100)          # completes the double, resets state
	assert_false(d.is_still_pending(1000))
