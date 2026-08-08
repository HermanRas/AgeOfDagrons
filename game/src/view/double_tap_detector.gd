## Disambiguates a single tap from a double tap on a GUI control (PLAN.md
## 10.1: assign a control group on double-tap, reselect on single). Separate
## from `InputRouter`'s tap detection because that class reads raw
## `_unhandled_input` over the game view, while a HUD button's presses arrive
## already filtered through Godot's UI system as `pressed` -- this only needs
## the timestamp comparison, not the slop/press-tracking machinery.
##
## Pure timestamps in, no scene tree -- headlessly testable, unlike the
## deferred timer a caller needs to actually WAIT and see whether a second tap
## follows before committing to the single-tap action.
class_name DoubleTapDetector
extends RefCounted

const DOUBLE_TAP_MS := 300

var _last_tap_ms: int = -1000000


## Register a tap at `now_ms`. Returns true if it pairs with the immediately
## preceding one as a double tap (and resets, so a third tap starts fresh
## rather than chaining into another double); false for a single tap that is
## not yet final -- see `is_still_pending()`.
func register_tap(now_ms: int) -> bool:
	var is_double := now_ms - _last_tap_ms <= DOUBLE_TAP_MS
	_last_tap_ms = -1000000 if is_double else now_ms
	return is_double


## True if the tap timestamped `tap_ms` is still the most recent one seen --
## i.e. no later tap (which would have paired with it as a double, or started
## a newer single) has arrived since. A "single" caller schedules its action
## after `DOUBLE_TAP_MS` and checks this first, so a double-tap completing
## inside that wait does not ALSO fire the single's action.
func is_still_pending(tap_ms: int) -> bool:
	return _last_tap_ms == tap_ms
