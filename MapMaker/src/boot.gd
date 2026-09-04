## 16.1's deliverable, and it is deliberately tiny: **launch, find the game, read its
## roster, and print what was found.**
##
## PLAN.md 16.1: *"it launches, reads the game's `data/*.json`, and prints how many unit,
## building, resource and terrain entries it found. If that number is wrong, nothing built
## on top of it can be right."* Everything in Phase 16 stands on those two things — the
## roster being real, and the format copies being current — so both are reported before a
## single pixel of editor exists.
##
## ## IT SHOWS THE SAME REPORT ON SCREEN AND ON STDOUT
##
## On screen because this is a windowed tool and a person double-clicking it should not have
## to find a console; on stdout because `--headless` is how the check gets run from a script
## and how the test suite's sibling reads it. Neither is the primary — they are one report
## rendered twice.
##
## ## THE EXIT CODE IS MEANINGFUL UNDER `--headless`
##
## 0 when the roster loaded and every format copy matches; 1 otherwise. So the whole
## startup contract is one command in a script, which is what `run_tests` does for the
## suite. A windowed run never quits on its own — there is a person looking at it.
##
## Usage:
##   Godot --path MapMaker                      # the window
##   Godot --headless --path MapMaker --quit-after 2   # the check, by exit code
extends Control

## Painted rather than themed. This project has no theme yet (the game's lives in its own
## `res://`, which is exactly what cannot be shared), and 16.1 is not the row that invents
## one -- a boot report in the default font is honest about how early this is.
const _BG := Color(0.09, 0.09, 0.11)
const _OK := Color(0.55, 0.80, 0.55)
const _BAD := Color(0.95, 0.45, 0.40)
const _DIM := Color(0.70, 0.70, 0.74)

var _root: GameRoot = null
var _guard: FormatGuard = null
var _label: RichTextLabel = null


func _ready() -> void:
	_build_ui()
	var lines := _startup()
	_label.text = "\n".join(PackedStringArray(lines))
	for line in lines:
		# Stripped of BBCode for the console: the tags are for the label, and a terminal
		# showing literal [color=...] is worse than plain text.
		print(_plain(line))

	if DisplayServer.get_name() == "headless":
		# The exit code is the answer -- see the class comment. Deferred rather than called
		# here so the print buffer is flushed and, on a non-headless run, the frame is drawn.
		get_tree().quit(0 if ready_to_work() else 1)


## Is the tool in a state where it could author a map?
##
## **BOTH HALVES, AND NEITHER IS OPTIONAL.** A roster with no game project behind it means an
## empty palette; format copies that have drifted mean a file the game cannot read. 16.4b's
## save path asks exactly this question.
func ready_to_work() -> bool:
	return _root != null and not _root.path.is_empty() \
			and GameDataRegistry.is_loaded() and _guard != null and _guard.passed()


func _startup() -> Array[String]:
	var lines: Array[String] = []
	lines.append("[b]AOD MapMaker[/b]   Godot %s" % Engine.get_version_info().string)
	lines.append("")

	# ── the game project ──
	_root = GameRoot.resolve()
	if _root.path.is_empty():
		lines.append("[color=#f27366]CANNOT FIND THE GAME PROJECT[/color]")
		for p in _root.problems:
			lines.append("  %s" % p)
		# RETURNED EARLY AND SAID PLAINLY. Everything below reads the game project, so
		# carrying on would print a wall of zeroes and a wall of failed hashes -- which
		# reads as a broken tool rather than as a path that needs setting.
		return lines
	lines.append("game project: [color=#b3b3bb]%s[/color]" % _root.path)
	for p in _root.problems:
		# Non-fatal notes -- e.g. a configured root that did not check out, having fallen
		# back to the sibling. Worth showing: the tool is not reading what was asked for.
		lines.append("  [color=#f2c266]note[/color] %s" % p)
	lines.append("")

	# ── the roster ──
	lines.append_array(_roster_lines())
	lines.append("")

	# ── the format copies ──
	lines.append_array(_format_lines())
	lines.append("")

	if ready_to_work():
		lines.append("[color=#8ccc8c]READY[/color] — the roster loaded and every format copy"
				+ " is current.")
	else:
		lines.append("[color=#f27366]NOT READY[/color] — see above. Saving would be refused.")
	return lines


func _roster_lines() -> Array[String]:
	var lines: Array[String] = []
	var ok := GameDataRegistry.load_from(_root)
	lines.append("[b]roster[/b]  (read live from the game's data/, never copied)")
	lines.append("  units       %4d" % GameDataRegistry.unit_ids().size())
	lines.append("  buildings   %4d" % GameDataRegistry.building_ids().size())
	lines.append("  resources   %4d" % GameDataRegistry.resource_ids().size())
	# TERRAIN COMES OFF THE ENUM, not off a file: `sim_map.gd` is the authority on its own
	# terrain kinds and this is the copy FormatGuard checks. So this count and the paint
	# brushes 16.2 offers cannot disagree.
	lines.append("  terrain     %4d   (%s)" % [
			GameDataRegistry.terrain_kinds().size(),
			", ".join(PackedStringArray(_as_strings(GameDataRegistry.terrain_kinds())))])
	if not ok:
		lines.append("  [color=#f27366]nothing loaded[/color]")
	for w in GameDataRegistry.load_warnings:
		lines.append("  [color=#f27366]warn[/color] %s" % w)

	# A SAMPLE, BECAUSE A COUNT ALONE CANNOT BE WRONG IN AN INTERESTING WAY. If the ids read
	# as `res.tree`/`building.house` then the files parsed AND the keys are what the rest of
	# the tool will look them up by; a count of 31 proves only that something was read.
	var sample := GameDataRegistry.building_ids()
	if not sample.is_empty():
		var first := sample[0]
		lines.append("  first building: %s — \"%s\", footprint %s" % [
				first, GameDataRegistry.display_name(first),
				GameDataRegistry.building(first).footprint])
	return lines


func _format_lines() -> Array[String]:
	var lines: Array[String] = []
	_guard = FormatGuard.check(_root)
	lines.append("[b]format copies[/b]  (PLAN.md 16 decision 3 — a copy nobody diffs has"
			+ " drifted)")
	for r in _guard.results:
		var good := int(r["status"]) == int(FormatGuard.Status.OK)
		lines.append("  [color=%s]%s[/color] %-30s [color=#b3b3bb]%s[/color]" % [
				_OK.to_html(false) if good else _BAD.to_html(false),
				"ok  " if good else "FAIL",
				r["name"], r["detail"]])
	if not _guard.passed():
		lines.append("")
		for line in _guard.refusal().split("\n"):
			lines.append("  [color=#f27366]%s[/color]" % line)
	return lines


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = _BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)

	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.selection_enabled = true          # so a person can copy a path out of a warning
	_label.add_theme_color_override("default_color", _DIM)
	_label.add_theme_font_override("normal_font", ThemeDB.fallback_font)
	margin.add_child(_label)


static func _as_strings(names: Array[StringName]) -> Array[String]:
	var out: Array[String] = []
	for n in names:
		out.append(String(n))
	return out


## BBCode stripped for the console. Tags only ever wrap whole words here, so a
## non-greedy sweep between brackets is enough and a regex would be more machinery than
## the job needs.
static func _plain(text: String) -> String:
	var out := ""
	var inside := false
	for i in text.length():
		var c := text[i]
		if c == "[":
			inside = true
		elif c == "]":
			inside = false
		elif not inside:
			out += c
	return out
