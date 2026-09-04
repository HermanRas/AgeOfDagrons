## Headless test runner for **MapMaker**. The single entry point for its whole suite.
##
## ⚠️ **A COPY OF THE GAME'S `tests/run_tests.gd`, AND IT IS NOT IN `format/`** — so it is
## NOT hash-checked, unlike the six files that decide what a map means. PLAN.md §16 decision
## 8 asks for the game's harness here on the grounds that everything the tool carries is a
## pure function and the format is exactly what must not drift silently. The harness itself
## drifting costs a missing feature in a test runner, not a corrupt map file, so it is copied
## for the behaviour rather than pinned for the contract.
##
## **Worth keeping in step by hand anyway**, because two of its rules were each paid for once
## on the game side and neither is obvious: an empty suite is a FAILURE (a renamed base class
## silently collapsed discovery to zero while reporting PASS), and a test that asserts
## nothing is a FAILURE (an exploding `before_each` counted a whole file green). The
## `ScriptErrorSpy` below is the third and the subtlest.
##
## Run by hand -- this repo has no CI (PLAN.md 1.2). The exit code is meaningful
## so that adding one later is trivial, but nothing runs this automatically today.
##
##     godot --headless --path MapMaker res://tests/run_tests.tscn
##
## Exit code 0 = all passed, 1 = one or more failures.
##
## Discovers every `test_*.gd` under res://tests/ recursively, instantiates it,
## and runs each `test_*` method. No window, no rendering -- which is only
## possible because src/sim/ holds no Node types (PLAN.md 4).
##
## This is a scene script (a Node under run_tests.tscn), not a --script
## SceneTree override: a custom --script MainLoop skips the normal main-scene
## boot sequence that parents autoload singletons under the tree root, which
## silently breaks anything needing get_tree()/get_multiplayer() (e.g. Net) --
## discovered building phase 0.6. A real scene, even headless, boots exactly
## like the shipped game does, so autoloads work the same way here as on device.
extends Node

const TEST_ROOT := "res://tests/"


## Watches for the one category of error that silently truncates a test.
##
## GDScript cannot catch a runtime error. An invalid assignment, or a property read on
## a null, abandons the REST OF THE FUNCTION and carries on at the caller -- so every
## assertion after the bad line never runs, and never running is indistinguishable from
## passing. `test_the_wire_form_survives_json_the_way_a_packet_would` reported PASS on
## that basis while verifying nothing (found 2026-08-21).
##
## The zero-assertion floor in `_run_file` cannot catch it alone, which is what its own
## comment used to claim: that test made ONE assertion before it died, so it cleared the
## floor with a truncated body. The two checks catch different things and both are kept.
##
## KEYED ON THE ERROR TYPE, NOT ON THE TEST, which is what makes this cheap. Script
## errors are never deliberate -- no test wants one -- while the noise this suite makes
## on purpose is engine ERRORs and WARNINGs: the net tests provoke "unknown peer ID" to
## prove a vanishing peer cannot freeze a match, and the occlusion tests make the shader
## compiler grumble. Those are ERROR_TYPE_ERROR and ERROR_TYPE_WARNING and pass straight
## through. So no test has to declare anything, and there is no opt-out list to rot.
class ScriptErrorSpy extends Logger:
	var _seen: Array[String] = []
	var _watching := false

	func _log_error(function: String, file: String, line: int, code: String,
			rationale: String, _editor_notify: bool, error_type: int,
			_script_backtraces: Variant) -> void:
		if not _watching or error_type != ERROR_TYPE_SCRIPT:
			return
		var what: String = rationale if rationale != "" else code
		_seen.append("%s (%s:%d in %s)" % [what, file.get_file(), line, function])

	## Only watch while a test is actually running, so an error raised by discovery or
	## by loading a file is not pinned on whichever test happened to run next.
	func begin() -> void:
		_seen.clear()
		_watching = true

	func take() -> Array[String]:
		_watching = false
		return _seen.duplicate()


var _spy := ScriptErrorSpy.new()
var _total := 0
var _passed := 0
var _failed := 0
var _assertions := 0
var _failure_log: Array[String] = []


func _ready() -> void:
	var started := Time.get_ticks_msec()
	OS.add_logger(_spy)

	print_rich("[b]AOD MapMaker test run[/b]  Godot %s" % Engine.get_version_info().string)
	print("")

	var files := _discover(TEST_ROOT)
	files.sort()

	if files.is_empty():
		# Discovering nothing is a FAILURE, never a pass. A runner that exits 0
		# on an empty suite is worse than no runner: it reports PASS while testing
		# nothing. This was observed for real -- renaming the TestCase base
		# script invalidated .godot/global_script_class_cache.cfg and discovery
		# silently collapsed to zero while still reporting PASS.
		# If this fires, run:  godot --headless --path game --import --quit
		printerr("FATAL: no test files found under %s" % TEST_ROOT)
		printerr("       expected at least one test_*.gd")
		printerr("       if scripts were renamed, rebuild the class cache with --import")
		_report(started)
		get_tree().quit(1)
		return

	for path in files:
		_run_file(path)

	_report(started)
	OS.remove_logger(_spy)
	get_tree().quit(1 if _failed > 0 else 0)


func _discover(dir_path: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_error("cannot open %s" % dir_path)
		return found

	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = dir.get_next()
			continue
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			found.append_array(_discover(full))
		elif entry.begins_with("test_") and entry.ends_with(".gd"):
			found.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
	return found


func _run_file(path: String) -> void:
	var script: Resource = load(path)
	if script == null:
		_fail_hard(path, "failed to load script")
		return

	# Check compilability BEFORE calling new(). A script with a parse error still
	# loads as a GDScript, but calling new() on it raises "Nonexistent function
	# 'new'", and a raised error ABORTS this function -- so the file was dropped
	# from the run entirely and the suite still reported PASS with a smaller
	# count. Observed at 0.2b: one uncompilable file took 8 tests out of the run
	# silently. can_instantiate() asks the same question without the aborting call.
	if script is GDScript and not (script as GDScript).can_instantiate():
		_fail_hard(path, "script does not compile -- see the parse error above")
		return

	var instance: Object = script.new()
	if instance == null:
		_fail_hard(path, "failed to instantiate")
		return
	if not instance.has_method("_failure_list"):
		_fail_hard(path, "does not extend TestCase")
		return

	var suite := path.get_file().get_basename()
	print("  %s" % suite)

	for method in _test_methods(instance):
		_total += 1
		instance._reset()
		# before_each and after_each are inside the watch on purpose: a setup that
		# explodes is the 0.2b failure below, and it has to be attributed to the test
		# it wrecked rather than passing unnoticed.
		_spy.begin()
		instance.before_each()
		instance.call(method)
		instance.after_each()
		var truncated := _spy.take()

		_assertions += instance._assertion_count()
		var failures: Array = instance._failure_list()

		# A test that asserted nothing is a FAILURE, not a pass -- same principle
		# as the empty-suite check above. GDScript reports a runtime script error
		# (a null from a broken before_each, a renamed method) by printing and
		# continuing, so an exploded test records no failures and used to be
		# counted green. Found at 0.2b, where a whole file's worth of tests
		# reported PASS while every one of them was erroring on line 1 of its setup.
		#
		# This catches a test that asserted nothing at all. It does NOT catch one that
		# died PART WAY THROUGH -- it clears the floor on the assertions it managed
		# before the bad line, and the rest are silently skipped. That is what the spy
		# above is for; the two together are the coverage, neither alone.
		if failures.is_empty() and instance._assertion_count() == 0:
			failures = ["no assertions ran -- check the output above for a script error"]

		# Reported FIRST, and reported even when the test also recorded ordinary
		# assertion failures: when a test both errors and comes up short, the error is
		# the cause and the short assertions are its symptom.
		if not truncated.is_empty():
			var with_errors: Array = []
			for e in truncated:
				with_errors.append("aborted by a script error -- %s" % e)
			with_errors.append_array(failures)
			failures = with_errors

		if failures.is_empty():
			_passed += 1
			print("    PASS  %s" % method)
		else:
			_failed += 1
			print("    FAIL  %s" % method)
			for f in failures:
				print("            %s" % f)
				_failure_log.append("%s::%s -- %s" % [suite, method, f])


func _test_methods(instance: Object) -> Array[String]:
	var names: Array[String] = []
	for m in instance.get_method_list():
		var n: String = m.name
		if n.begins_with("test_") and not names.has(n):
			names.append(n)
	names.sort()
	return names


func _fail_hard(path: String, reason: String) -> void:
	_total += 1
	_failed += 1
	print("  %s" % path)
	print("    FAIL  %s" % reason)
	_failure_log.append("%s -- %s" % [path, reason])


func _report(started_ms: int) -> void:
	var elapsed := Time.get_ticks_msec() - started_ms
	print("")
	print("  %d test(s), %d assertion(s) in %d ms" % [_total, _assertions, elapsed])
	print("  %d passed, %d failed" % [_passed, _failed])
	if not _failure_log.is_empty():
		print("")
		print("  failures:")
		for f in _failure_log:
			print("    - %s" % f)
	print("")
	print("  RESULT: %s" % ("PASS" if _failed == 0 else "FAIL"))
