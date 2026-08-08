## PLAN.md 8.1a/8.1c/10.4: the shared "crop a battle sprite as a portrait"
## helper. Must never depend on real baked art being staged --
## game/assets/atlases/ is gitignored, so a fresh clone resolves every
## visual_id to a placeholder.
extends TestCase


func test_an_undeclared_def_id_yields_no_frame() -> void:
	assert_eq(EntityPortrait.frame_for(&"unit.nonexistent"), {})


func test_empty_def_id_yields_no_frame() -> void:
	assert_eq(EntityPortrait.frame_for(&""), {})
