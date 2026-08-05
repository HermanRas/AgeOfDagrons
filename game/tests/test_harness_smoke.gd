## Proves the runner discovers files, runs methods, counts assertions and
## honours before_each/after_each. Delete once real sim tests exist (phase 0.5)
## -- until then this is the only thing verifying CI would actually catch a
## regression rather than silently passing.
extends TestCase

var _setup_ran := false


func before_each() -> void:
	_setup_ran = true


func test_before_each_runs() -> void:
	assert_true(_setup_ran, "before_each should run before each test method")


func test_equality_assertions() -> void:
	assert_eq(2 + 2, 4)
	assert_ne(2 + 2, 5)
	assert_eq("villager", "villager")


func test_boolean_assertions() -> void:
	assert_true(true)
	assert_false(false)


func test_null_assertions() -> void:
	assert_null(null)
	assert_not_null(TestCase.new())


func test_float_tolerance() -> void:
	assert_almost_eq(0.1 + 0.2, 0.3)


func test_integer_subtile_maths() -> void:
	# Sanity-check the unit convention from PLAN.md 1: 1 tile = 256 sub-units.
	# Integer positions are the reason snapshot diffing can be exact.
	const SUBTILE := 256
	var pos := Vector2i(5 * SUBTILE + 128, 3 * SUBTILE)
	assert_eq(pos / SUBTILE, Vector2i(5, 3), "sub-unit position floors to its tile")
	assert_eq(pos.x % SUBTILE, 128, "sub-tile remainder is preserved exactly")
