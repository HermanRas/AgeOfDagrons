## Phase 0.7: enforces PLAN.md 4's most important rule -- "Nothing in sim/
## may extends Node, load a texture, read input, or reference view/" --
## by grepping every script under src/sim/.
##
## Implemented as a headless test rather than a separate Python script
## (tools/licence_audit.py's style) so the whole suite, this check included,
## runs through the one command in PLAN.md 7.7 with no second thing to remember.
## That matters more than it would elsewhere: there is no CI (PLAN.md 1.2), so a
## check living outside the suite is a check nobody runs.
extends TestCase

const _SIM_ROOT := "res://src/sim/"

## Node and everything derived from it that a sim script could plausibly
## extend. "extends Node" alone would miss "extends Node2D" etc.
const _NODE_LIKE_BASE_CLASSES := [
	"Node", "Node2D", "Node3D", "Control", "CanvasLayer", "CanvasItem",
	"Viewport", "Window", "Camera2D", "Camera3D", "Sprite2D", "AnimatedSprite2D",
]

## Substrings that have no legitimate reason to appear in sim/: reading
## input, loading a visual/audio asset, or naming a view/ class.
const _FORBIDDEN_SUBSTRINGS := [
	"Input.", "InputEvent", "_input(", "_unhandled_input(", "_unhandled_key_input(",
	"get_viewport(", "get_tree(", "add_child(", "queue_free(",
	"res://assets/", "res://scenes/",
	"GameView", "EntityView", "EntityViewPool", "CameraRig", "InputRouter", "Iso.",
]


func test_no_sim_script_extends_a_node_like_class() -> void:
	for path in _gd_files(_SIM_ROOT):
		var extends_line := _find_extends_line(path)
		if extends_line.is_empty():
			continue
		var target := extends_line.trim_prefix("extends").strip_edges()
		for forbidden in _NODE_LIKE_BASE_CLASSES:
			assert_ne(target, forbidden, "%s extends %s" % [path, target])


func test_no_sim_script_contains_a_forbidden_reference() -> void:
	for path in _gd_files(_SIM_ROOT):
		var text := FileAccess.get_file_as_string(path)
		for forbidden in _FORBIDDEN_SUBSTRINGS:
			assert_false(text.contains(forbidden), "%s contains %s" % [path, forbidden])


func _gd_files(dir_path: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		fail("cannot open %s" % dir_path)
		return found

	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = dir.get_next()
			continue
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			found.append_array(_gd_files(full))
		elif entry.ends_with(".gd"):
			found.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
	return found


func _find_extends_line(path: String) -> String:
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var stripped := line.strip_edges()
		if stripped.begins_with("extends "):
			return stripped
	return ""
