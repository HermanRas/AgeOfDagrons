## PLAN.md 8.1a/8.1b: the HP bar fill, independent of whether the art pack
## happens to be staged (game/assets/ui/hud/ is gitignored, per-developer art).
extends TestCase

var bar: HealthBarView


func before_each() -> void:
	bar = HealthBarView.new()


func after_each() -> void:
	bar.free()


func test_defaults_to_full() -> void:
	assert_almost_eq(bar.fraction, 1.0, 0.001)


func test_fraction_is_settable() -> void:
	bar.fraction = 0.4
	assert_almost_eq(bar.fraction, 0.4, 0.001)


func test_fraction_clamps_below_zero_and_above_one() -> void:
	bar.fraction = -0.5
	assert_almost_eq(bar.fraction, 0.0, 0.001)
	bar.fraction = 1.5
	assert_almost_eq(bar.fraction, 1.0, 0.001)
