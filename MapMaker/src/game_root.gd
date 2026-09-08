## Where the game's project lives, so the tool can read its roster and its source.
##
## PLAN.md §16 decision 2: two Godot projects cannot share a `res://`, so MapMaker reads the
## game's own folders — `data/*.json` for what is placeable and how big each footprint is,
## `src/` for the originals `FormatGuard` checks its copies against.
##
## ## THE PATH IS DERIVED, AND A CONFIG FILE IS THE ESCAPE HATCH RATHER THAN THE MECHANISM
##
## `Campaigns`' argument, transferred: `game/` is a sibling of `MapMaker/`, both inside the
## repo, so `res://../game` finds it on every clone and a fresh checkout needs no setup step.
## **A setup step nobody performs is why `game/assets/ui/` was gitignored for months and a
## clean clone had no HUD.** `mapmaker.local.json` is read first for anyone whose layout
## differs, so the hatch survives; it is simply not required.
##
## ⚠️ **A JUNCTION OR SYMLINK INTO `game/` IS REJECTED — as a DESIGN choice, not a check.**
## PLAN.md §16 decision 2: this repo sits inside Google Drive sync, and a link there is one
## more way to corrupt a `.git` that has been corrupted once already (§1.3). So the tool
## reads through a *path* and never asks for a link to exist. Nothing here detects one,
## because there is nothing to detect: if somebody makes a junction anyway it behaves like a
## directory and the risk it carries is Drive's, not this tool's.
##
## ## IT REPORTS WHAT IS WRONG RATHER THAN ASSERTING
##
## Every failure mode here is a person's machine being set up differently, so each one comes
## back as a sentence somebody can act on: which path was tried, what was expected in it,
## and which config key would override it. A tool that simply does not start is a tool
## somebody has to read the source of.
class_name GameRoot
extends RefCounted

## Optional, gitignored.
## `{"game_root": "D:/somewhere/AOD_Mobile/game", "game_user_dir": "D:/other/AgeOfDragons"}`.
const LOCAL_CONFIG := "res://mapmaker.local.json"

## Overrides `game_user_dir()` outright. Its own key rather than a suffix on `game_root`,
## because the two are unrelated directories: one is a checkout, the other is per-user state
## a platform decides the location of.
const USER_DIR_KEY := "game_user_dir"

## Files that must be present for a directory to BE the game project. Chosen as one file
## per thing this tool needs — the project itself, the roster, and the source `FormatGuard`
## reads — so a path pointing at the repo root rather than at `game/` is caught here with a
## useful message instead of failing later as an empty roster.
const MARKERS := [
	"project.godot",
	"data/buildings.json",
	"src/sim/map_data.gd",
]

## The resolved absolute path, or empty if nothing usable was found.
var path: String = ""

## Why, when `path` is empty — or a note about the override when it is not.
var problems: Array[String] = []

## `mapmaker.local.json` as parsed, or `{}`. Held rather than re-read so `game_user_dir()`
## does not parse the same file a second time and cannot come to a different conclusion
## about it than `resolve()` did.
var _config: Dictionary = {}


static func resolve() -> GameRoot:
	var r := GameRoot.new()
	var configured := r._configured()
	var candidates: Array[String] = []
	if not configured.is_empty():
		candidates.append(configured)
	candidates.append(r._sibling())

	for candidate in candidates:
		var missing := r._missing_markers(candidate)
		if missing.is_empty():
			r.path = candidate
			return r
		r.problems.append("%s is not the game project: no %s"
				% [candidate, ", ".join(PackedStringArray(missing))])

	r.problems.append("set %s to the game project directory, e.g. {\"game_root\": \"%s\"}"
			% [LOCAL_CONFIG, r._sibling()])
	return r


func data_path(file_name: String) -> String:
	return path.path_join("data").path_join(file_name)


## A file inside the game project, by its path RELATIVE TO the project — which is how
## `FormatGuard` names originals, so its table reads like the game's own tree.
func source_path(relative: String) -> String:
	return path.path_join(relative)


## `res://` globalizes to this project's directory (`.../AOD_Mobile/MapMaker`), whose sibling
## is the game. `simplify_path` resolves the `..` so a path printed in a warning is one
## somebody can paste.
func _sibling() -> String:
	return ProjectSettings.globalize_path("res://").path_join("../game").simplify_path()


func _configured() -> String:
	if not FileAccess.file_exists(LOCAL_CONFIG):
		return ""
	var text := FileAccess.get_file_as_string(LOCAL_CONFIG)
	var json := JSON.new()
	if json.parse(text) != OK or not json.data is Dictionary:
		problems.append("%s is not a JSON object; ignoring it" % LOCAL_CONFIG)
		return ""
	_config = json.data as Dictionary
	return str(_config.get("game_root", "")).simplify_path()


# ── the game's own user:// (PLAN.md 16.4a) ──────────────────────────────────

## Where the GAME keeps its per-user files, so the tool can find `user://maps/` — the
## directory a map handed back from a played match lands in (16.0's third root).
##
## ⚠️ **`user://` MEANS A DIFFERENT DIRECTORY IN EACH GODOT PROJECT, AND THAT IS THE WHOLE
## PROBLEM THIS SOLVES.** This tool's own `user://` is `.../app_userdata/AOD MapMaker`; the
## game's is `.../app_userdata/AgeOfDragons`. A tool that listed *its own* `user://maps/`
## would have shipped a root that is empty by construction and looks, from the outside,
## exactly like the root that is empty because nothing has written to it yet.
##
## ## IT IS DERIVED, AND THE DERIVATION IS STATED SO IT CAN BE DISBELIEVED
##
## Both projects sit under the same `app_userdata` parent, so the game's directory is this
## project's with the leaf swapped for the game's `config/name` — read out of the game's own
## `project.godot`, which is the only file that knows it.
##
## **Two things this cannot see, and both fail the same safe way**: a game project setting
## `use_custom_user_dir` (neither does today) would live somewhere else entirely, and Godot
## sanitises a project name into a directory name by rules this does not reimplement — the two
## `AOD MapMaker` / `AOD_MapMaker` folders on the author's machine are evidence that it
## genuinely does something. `AgeOfDragons` is alphanumeric and therefore unchanged, and where
## a derivation would be wrong the directory simply does not exist, the root is silently
## absent (`MapSources.maps_in`), and `USER_DIR_KEY` is the escape hatch.
##
## Empty when it cannot be worked out at all.
func game_user_dir() -> String:
	var override := str(_config.get(USER_DIR_KEY, "")).simplify_path()
	if not override.is_empty():
		return override
	var game_name := game_project_name()
	if game_name.is_empty():
		return ""
	return OS.get_user_data_dir().get_base_dir().path_join(game_name)


## The game's `application/config/name`, read as TEXT out of its `project.godot`.
##
## As text and not through `ConfigFile`, for one reason worth writing down: **Godot rewrites
## `project.godot` whenever the project is opened in the editor** (§6's first gotcha), so this
## file is one whose exact formatting nothing may depend on. A line match is indifferent to
## every rewrite that keeps the setting; a parse that expected sections would not be.
func game_project_name() -> String:
	var text := FileAccess.get_file_as_string(path.path_join("project.godot"))
	for line in text.split("\n"):
		var trimmed := line.strip_edges()
		if trimmed.begins_with("config/name="):
			return trimmed.trim_prefix("config/name=").strip_edges().trim_prefix("\"") \
					.trim_suffix("\"")
	return ""


func _missing_markers(dir: String) -> Array[String]:
	var missing: Array[String] = []
	if dir.is_empty():
		return ["a path at all"] as Array[String]
	for marker in MARKERS:
		if not FileAccess.file_exists(dir.path_join(marker)):
			missing.append(marker)
	return missing
