## PLAN.md 8.1a/8.1c: only the non-drawing state is asserted here -- _draw()
## output isn't inspectable headlessly, same boundary EntityView's own tests
## already respect (they check health_pct/anim state, never pixels).
extends TestCase

var view: EntityPortraitView


func before_each() -> void:
	view = EntityPortraitView.new()


func after_each() -> void:
	view.free()


func test_defaults_to_no_entity() -> void:
	assert_eq(view.def_id, &"")


func test_def_id_is_settable() -> void:
	view.def_id = &"unit.villager"
	assert_eq(view.def_id, &"unit.villager")


func test_has_a_fixed_minimum_size() -> void:
	assert_eq(view.custom_minimum_size, Vector2(EntityPortraitView.SIZE, EntityPortraitView.SIZE))
