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

## Worth reading, not worth stopping for: a drifted icon copy, or no staged art (16.3).
const _WARN := Color(0.95, 0.78, 0.35)

var _startup: Startup = null
var _root: GameRoot = null
var _guard: FormatGuard = null
var _label: RichTextLabel = null
var _actions: HBoxContainer = null


func _ready() -> void:
	_build_ui()
	var lines := _report()
	_label.text = "\n".join(PackedStringArray(lines))
	for line in lines:
		# Stripped of BBCode for the console: the tags are for the label, and a terminal
		# showing literal [color=...] is worse than plain text.
		print(_plain(line))

	if DisplayServer.get_name() == "headless":
		# The exit code is the answer -- see the class comment. Deferred rather than called
		# here so the print buffer is flushed and, on a non-headless run, the frame is drawn.
		get_tree().quit(0 if ready_to_work() else 1)
		return

	# ── into the editor (16.2) ──
	#
	# THE REPORT IS A GATE, NOT A SPLASH. The button appears whatever the guard said, and
	# `Editor.setup()` is told which -- because a drifted copy makes SAVING dangerous, not
	# drawing: an author should still be able to open the tool and look at a map while the
	# copies are brought back into step. `Editor.save()` is where decision 3 is enforced.
	var open := Button.new()
	open.text = "New map  →" if ready_to_work() else "Open the editor anyway (saving disabled)"
	open.pressed.connect(_open_editor)
	_actions.add_child(open)


func _open_editor() -> void:
	# INSTANTIATED AND SWAPPED BY HAND rather than `change_scene_to_file`, so the guard result
	# can be handed over: the editor must not have to re-run the check to know whether it may
	# save, and a static would be a second place that answer lives.
	var editor: Control = load("res://Editor.tscn").instantiate()
	editor.setup(_startup)
	get_tree().root.add_child(editor)
	# Removed rather than hidden: this screen holds a `FormatGuard` and a report and has
	# nothing to contribute once the editor is up.
	get_parent().remove_child(self)
	queue_free()


## Is the tool in a state where it could author a map?
##
## Delegated to `Startup` since 2026-09-04, so this screen and `Editor` cannot come to
## different conclusions -- and so a screen opened on its own can reach the same answer. See
## `Startup`'s header for the playtest bug that moved it.
func ready_to_work() -> bool:
	return _startup != null and _startup.can_save()


## The whole report, as BBCode lines. Named `_report` and not `_startup` because the field
## holding the `Startup` took that name -- GDScript will not have both, and the collision is a
## parse error rather than a shadow.
func _report() -> Array[String]:
	var lines: Array[String] = []
	lines.append("[b]AOD MapMaker[/b]   Godot %s" % Engine.get_version_info().string)
	lines.append("")

	# ── the game project ──
	#
	# Through `Startup`, which does the resolve, the roster load and the guard in one place
	# so this screen and `Editor` cannot disagree. The locals below are kept for the report,
	# which walks the same three stages and prints each.
	_startup = Startup.check()
	_root = _startup.root
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

	# ── the palette's icons (16.3) ──
	lines.append_array(_icon_lines())
	lines.append("")

	# ── what there is to open (16.4a) ──
	lines.append_array(_openable_lines())
	lines.append("")

	if ready_to_work():
		lines.append("[color=#8ccc8c]READY[/color] — the roster loaded and every format copy"
				+ " is current.")
	else:
		lines.append("[color=#f27366]NOT READY[/color] — see above. Saving would be refused.")
	return lines


func _roster_lines() -> Array[String]:
	var lines: Array[String] = []
	# ALREADY LOADED BY `Startup.check()`. Loading again here would be a second read of the
	# same files and a second chance for the two to disagree about what is in them.
	var ok := GameDataRegistry.is_loaded()
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
	# `Startup`'s, not a fresh check: seven file hashes are cheap but two results are not one
	# result, and this screen hands the SAME object to the editor.
	_guard = _startup.guard if _startup.guard != null else FormatGuard.check(_root)
	lines.append("[b]format copies[/b]  (PLAN.md 16 decision 3 — a copy nobody diffs has"
			+ " drifted)")
	for r in _guard.results:
		var good := int(r["status"]) == int(FormatGuard.Status.OK)
		lines.append("  [color=%s]%s[/color] %-30s [color=#b3b3bb]%s[/color]" % [
				_OK.to_html(false) if good else _BAD.to_html(false),
				"ok  " if good else "FAIL",
				r["name"], r["detail"]])
	# ⚠️ **`note` AND NOT `FAIL`, and the word is the report.** These two decide what a map
	# LOOKS LIKE in the palette, not what it means on disk, so drift here does not disable
	# saving -- `FormatGuard.PRESENTATION` carries the full argument and flags it as a
	# deliberate departure from PLAN.md §16 decision 2's letter.
	for r in _guard.presentation_results:
		var good := int(r["status"]) == int(FormatGuard.Status.OK)
		lines.append("  [color=%s]%s[/color] %-30s [color=#b3b3bb]%s[/color]" % [
				_OK.to_html(false) if good else _WARN.to_html(false),
				"ok  " if good else "note",
				r["name"], r["detail"]])
	if not _guard.passed():
		lines.append("")
		for line in _guard.refusal().split("\n"):
			lines.append("  [color=#f27366]%s[/color]" % line)
	return lines


## What the palette will find to draw with (16.3).
##
## ⚠️ **TWO NUMBERS, BECAUSE ONE OF THEM BEING ZERO IS FINE AND THE OTHER IS NOT.** `declared`
## is how many visual ids `visuals.json` names — zero means the file was not read and every
## icon in the tool will be a lettered plate for the wrong reason. `staged` is how many of
## those have an atlas on THIS machine, and **zero is the correct, expected state of a clean
## clone**: `game/assets/atlases/` is gitignored art. So the second is reported as a note in
## the author's own words rather than as a fault, which is 16.3's *"a palette that finds no
## atlases must draw lettered plates and carry on"* made visible before the editor opens.
##
## **It does not affect the exit code.** A tool with no art is a working tool.
func _icon_lines() -> Array[String]:
	var lines: Array[String] = []
	var icons := IconAtlas.new()
	icons.load_from(_root)
	var counts := icons.counts()
	var declared := int(counts["declared"])
	var staged := int(counts["staged"])
	lines.append("[b]palette icons[/b]  (16.3 — cropped live from the game's staged atlases)")
	lines.append("  declared  %4d   [color=#b3b3bb]visuals.json entries[/color]" % declared)
	lines.append("  staged    %4d   [color=%s]%s[/color]" % [staged,
			(_DIM if staged > 0 else _WARN).to_html(false),
			"atlases on this machine" if staged > 0
			else "no staged art — the palette will draw lettered plates, which is correct"])
	if declared == 0:
		lines.append("  [color=#f27366]visuals.json was not read[/color] — every icon will be a"
				+ " plate, and not because the art is missing")

	# ── the toolbar's own art (16.4d) ──
	#
	# ⚠️ **A DIFFERENT KIND OF MISSING FROM THE TWO NUMBERS ABOVE, AND THAT IS WHY IT IS REPORTED
	# SEPARATELY.** `staged` being zero is the correct state of a clean clone; these 13 files are
	# COMMITTED into this project, so zero means a broken checkout or a skipped `--import` — and
	# the second is by far the likelier, because a `.ctex` lives in `.godot/` which is gitignored.
	#
	# ⚠️ **IT DOES NOT GATE `ready_to_work()`, DELIBERATELY.** A map authored with a blank button
	# is byte-identical to one authored with a gold one, so refusing to save over it would be
	# `FormatGuard`'s own *"a check that cries wolf is a check somebody disables"* — the same
	# tiebreak `PRESENTATION` is the standing example of. Loud line, no gate.
	var gone := ToolIcons.missing()
	lines.append("  toolbar   %4d   [color=%s]%s[/color]" % [
			ToolIcons.IDS.size() - gone.size(),
			(_DIM if gone.is_empty() else _BAD).to_html(false),
			"of %d committed glyphs, drawn at %d px" % [ToolIcons.IDS.size(), ToolIcons.SIZE]
			if gone.is_empty()
			else "MISSING %s — run: godot --headless --path MapMaker --import" % ", ".join(
					PackedStringArray(_as_strings(gone)))])

	# ── the mouse cursors (16.4e) ──
	#
	# ⚠️ **TWO FACTS, BECAUSE THEY FAIL IN OPPOSITE DIRECTIONS.** Missing ART means the canvas
	# falls back to the system crosshair, which is a sensible map pointer and visibly not ours.
	# A missing HOTSPOT means the cursor is drawn correctly and **aims at its own middle** — so
	# every click lands a tile or two off where the author pointed, and nothing looks wrong. The
	# second is the one worth a line of its own on a startup report.
	var no_art := ToolCursors.missing()
	var no_aim := ToolCursors.unmeasured()
	lines.append("  cursors   %4d   [color=%s]%s[/color]" % [
			ToolCursors.IDS.size() - no_art.size(),
			(_DIM if no_art.is_empty() else _BAD).to_html(false),
			"of %d, drawn at %d px, aiming by measured hotspot"
					% [ToolCursors.IDS.size(), ToolCursors.SIZE]
			if no_art.is_empty()
			else "MISSING %s — the canvas falls back to a system crosshair" % ", ".join(
					PackedStringArray(_as_strings(no_art)))])
	if not no_aim.is_empty():
		lines.append("  [color=#f27366]no measured hotspot[/color] %s — these aim at their own"
				% ", ".join(PackedStringArray(_as_strings(no_aim)))
				+ " centre, which looks correct and is not")

	# ── the chrome (16.4f) ──
	#
	# TWO FACTS AGAIN, and again because they fail differently. A missing PLATE falls back to the
	# flat panels the tool had until today -- unstyled, entirely usable, and the state a person
	# would describe as "it looks like the old one". A missing FONT is not a fallback anybody
	# chose: `gui/theme/custom_font` naming a file that is not there leaves every label in the
	# engine default, which looks deliberate and is how a font swap silently does not happen.
	lines.append("  plate     %4s   [color=%s]%s[/color]" % [
			"yes" if UiChrome.has_plate() else "no",
			(_DIM if UiChrome.has_plate() else _WARN).to_html(false),
			"%s, %d px border at every panel size" % [UiChrome.PANEL_PATH.get_file(),
					UiChrome.MARGIN]
			if UiChrome.has_plate()
			else "%s is missing — panels draw flat, which is the old look and still works"
					% UiChrome.PANEL_PATH])
	var font_path: String = ProjectSettings.get_setting("gui/theme/custom_font", "")
	lines.append("  font      %4s   [color=%s]%s[/color]" % [
			"ok" if FileAccess.file_exists(font_path) else "MISS",
			(_DIM if FileAccess.file_exists(font_path) else _BAD).to_html(false),
			font_path.get_file() if FileAccess.file_exists(font_path)
			else "gui/theme/custom_font names %s and it is not there" % font_path])
	return lines


## What File ▸ Open would offer, and the directories it looked in (16.4a).
##
## **HERE FOR 16.1's REASON, ONE ROW LATER**: *"if that number is wrong, nothing built on top
## of it can be right."* Three roots, one of them **derived** from the game's project name and
## one walked a level deeper than the others, is three ways for the dialog to come up empty —
## and an empty list inside the editor cannot distinguish "no maps" from "looking in the wrong
## place". Printing the paths beside the count makes that answerable before the editor opens,
## and it makes the headless startup check say it too.
##
## ⚠️ **IT DOES NOT AFFECT THE EXIT CODE.** A machine with no authored maps is a perfectly
## ready tool — that is the state a clean clone is in — so this is a report and not a gate.
func _openable_lines() -> Array[String]:
	var lines: Array[String] = []
	var sources := MapSources.new()
	var rows := sources.discover(_root)
	lines.append("[b]maps to open[/b]  (16.4a — File ▸ Open)")
	for entry in sources.roots(_root):
		var path := str(entry["path"])
		var here := 0
		for row in rows:
			if str(row["dir"]).begins_with(path):
				here += 1
		lines.append("  %-9s %3d   [color=#b3b3bb]%s%s[/color]" % [
				MapSources.source_name(int(entry["source"])), here, path,
				"" if DirAccess.dir_exists_absolute(path) else "   (absent)"])
	for w in sources.warnings:
		# UNREADABLE, NOT MISSING. A folder on disk holding a map pair this build cannot
		# parse is the one fault an author cannot diagnose by looking at the list.
		lines.append("  [color=#f27366]unreadable[/color] %s" % w)
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

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 12)
	margin.add_child(rows)

	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.selection_enabled = true          # so a person can copy a path out of a warning
	_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_label.add_theme_color_override("default_color", _DIM)
	_label.add_theme_font_override("normal_font", ThemeDB.fallback_font)
	rows.add_child(_label)

	_actions = HBoxContainer.new()
	_actions.add_theme_constant_override("separation", 8)
	rows.add_child(_actions)


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
