## Headless test runner. CI entry point.
##
##     godot --headless --path game/ res://tests/run_tests.tscn
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

var _total := 0
var _passed := 0
var _failed := 0
var _assertions := 0
var _failure_log: Array[String] = []


func _ready() -> void:
	var started := Time.get_ticks_msec()

	print_rich("[b]AOD test run[/b]  Godot %s" % Engine.get_version_info().string)
	print("")

	var files := _discover(TEST_ROOT)
	files.sort()

	if files.is_empty():
		# Discovering nothing is a FAILURE, never a pass. A runner that exits 0
		# on an empty suite is worse than no runner: CI goes green while testing
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
		instance.before_each()
		instance.call(method)
		instance.after_each()

		_assertions += instance._assertion_count()
		var failures: Array = instance._failure_list()

		# A test that asserted nothing is a FAILURE, not a pass -- same principle
		# as the empty-suite check above. GDScript reports a runtime script error
		# (a null from a broken before_each, a renamed method) by printing and
		# continuing, so an exploded test records no failures and used to be
		# counted green. Found at 0.2b, where a whole file's worth of tests
		# reported PASS while every one of them was erroring on line 1 of its
		# setup. Zero assertions is the one signal that catches all of it.
		if failures.is_empty() and instance._assertion_count() == 0:
			failures = ["no assertions ran -- check the output above for a script error"]

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
