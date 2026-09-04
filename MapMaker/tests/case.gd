## Minimal assertion helper for headless sim tests.
##
## Deliberately tiny and dependency-free: sim tests must run with no scene,
## no window and no rendering (PLAN.md 7.7). A full framework (GdUnit4) lands
## at phase 0.7 -- until then this is enough to write real tests against.
##
## Subclass it, name methods `test_*`, and the runner will find them.
class_name TestCase
extends RefCounted

var _failures: Array[String] = []
var _assertions := 0

# ── lifecycle hooks (override as needed) ────────────────────────────────────

func before_each() -> void:
	pass

func after_each() -> void:
	pass

# ── assertions ─────────────────────────────────────────────────────────────

func assert_true(value: bool, msg: String = "") -> void:
	_assertions += 1
	if not value:
		_fail("expected true, got false", msg)

func assert_false(value: bool, msg: String = "") -> void:
	_assertions += 1
	if value:
		_fail("expected false, got true", msg)

func assert_eq(actual: Variant, expected: Variant, msg: String = "") -> void:
	_assertions += 1
	if actual != expected:
		_fail("expected %s, got %s" % [_fmt(expected), _fmt(actual)], msg)

func assert_ne(actual: Variant, unexpected: Variant, msg: String = "") -> void:
	_assertions += 1
	if actual == unexpected:
		_fail("expected value other than %s" % _fmt(unexpected), msg)

func assert_null(value: Variant, msg: String = "") -> void:
	_assertions += 1
	if value != null:
		_fail("expected null, got %s" % _fmt(value), msg)

func assert_not_null(value: Variant, msg: String = "") -> void:
	_assertions += 1
	if value == null:
		_fail("expected non-null", msg)

func assert_almost_eq(actual: float, expected: float, tolerance: float = 0.0001,
		msg: String = "") -> void:
	_assertions += 1
	if absf(actual - expected) > tolerance:
		_fail("expected %f +/- %f, got %f" % [expected, tolerance, actual], msg)

func fail(msg: String) -> void:
	_assertions += 1
	_fail("explicit failure", msg)

# ── runner interface ───────────────────────────────────────────────────────

func _failure_list() -> Array[String]:
	return _failures

func _assertion_count() -> int:
	return _assertions

func _reset() -> void:
	_failures.clear()
	_assertions = 0

func _fail(detail: String, msg: String) -> void:
	_failures.append(detail if msg.is_empty() else "%s -- %s" % [msg, detail])

func _fmt(v: Variant) -> String:
	return "<null>" if v == null else str(v)
