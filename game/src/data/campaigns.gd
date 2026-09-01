## Finds campaigns on disk and reads them into `CampaignDef`s (PLAN.md 15.1, roots in
## 3.3). Phase 15.1.
##
## ## NOT AN AUTOLOAD, DELIBERATELY
##
## PLAN.md 6.1's autoload table is exactly four and the front door is the only thing that
## reads campaigns. Instantiate it, call `discover()`, read `warnings`, let it go:
##
##     var c := Campaigns.new()
##     for campaign in c.discover():
##         ...
##     for w in c.warnings:
##         push_warning(w)
##
## `warnings` is per-instance rather than static for the reason `GameDataRegistry`'s
## `load_warnings` is an array and not a print: a caller that wants to show the player a
## broken campaign needs the text, and a caller that does not can ignore it.
##
## ## THE LOADER TAKES A ROOT LIST, NOT A PATH
##
## PLAN.md 3.3, and the list being DATA is the point -- a fourth root is a line here
## rather than a rewrite. First match wins **by campaign folder name**, so a dev override
## shadows an installed copy of the same campaign instead of the two appearing twice.
##
##   1. the DEV OVERRIDE -- repo-root `scenarios/`, EDITOR RUNS ONLY
##   2. `user://content/scenarios/` -- every platform, always, and writable
##
## ## THE DEV OVERRIDE NEEDS NO CONFIG FILE, AND THAT IS A DEPARTURE WORTH NAMING
##
## PLAN.md 3.3 describes it as *"named in a gitignored local config"*, on
## `tools/isobake.local.toml`'s precedent. That precedent does not transfer, because the
## art root is genuinely machine-specific (an 11 GB checkout anywhere on disk) while
## this path is **fixed by the repo's own layout**: `scenarios/` is the sibling of
## `game/`, which is the Godot project, so `res://../scenarios` finds it on every clone.
##
## Deriving it means a fresh checkout runs the campaign with no setup step -- and a setup
## step nobody performs is why `game/assets/ui/` was gitignored for months and a clean
## clone had no HUD. `content.local.json` is still read first for anyone whose layout
## differs, so the escape hatch survives; it is simply not required.
##
## ⚠️ **THE OVERRIDE IS GATED ON `OS.has_feature("editor")`, AND THAT GATE IS THE WHOLE
## SAFETY ARGUMENT.** It is true for editor runs, the headless suite and every
## `dev_preview` scene, and false in an exported build -- so a dev path cannot reach a
## release even if the file ships in the APK. Nothing else about the override is
## load-bearing.
##
## ## THE PRICE, STATED PLAINLY
##
## **A campaign cannot be tested on a phone until 0.3 `AssetPacks` lands.** `user://` on
## Android is internal app storage and is not `adb push`-able, and the override is
## editor-only. Everything in Phase 15 is fully exercisable on Windows and in the
## headless suite; the first on-device run waits on 0.3. That is a real dependency, not a
## footnote -- PLAN.md 3.3 lists the two escapes if it bites first, and both are a line
## in `ROOT_*` below rather than a redesign.
class_name Campaigns
extends RefCounted

## Where a device reads campaigns. Writable, so a campaign can be installed, updated,
## shared in and deleted again -- which is why `AssetPacks` gains a second verb for
## content: art is MOUNTED read-only under `res://`, a campaign is INSTALLED here.
const USER_ROOT := "user://content/scenarios/"

## Optional, gitignored, editor-only. `{"scenarios_root": "D:/somewhere/scenarios"}`.
const LOCAL_CONFIG := "res://content.local.json"

## Every complaint from the last `discover()`, in the order found. Never printed from
## here: see the class comment.
var warnings: Array[String] = []


## The roots to search, in priority order, skipping any that do not exist.
##
## Returned rather than walked inline so a test can assert the ORDER and the editor gate
## without a filesystem -- the ordering is the rule and the paths are inputs.
func roots() -> Array[String]:
	var out: Array[String] = []
	if OS.has_feature("editor"):
		var dev := _dev_root()
		if not dev.is_empty():
			out.append(dev)
	out.append(USER_ROOT)
	return out


## Repo-root `scenarios/`: the configured path if `content.local.json` names one, else
## the sibling of the Godot project. Editor only -- `roots()` owns that gate.
func _dev_root() -> String:
	var configured := _configured_dev_root()
	if not configured.is_empty():
		return configured
	# `res://` globalizes to the project directory (`.../AOD_Mobile/game`), whose sibling
	# is the authored content. `simplify_path` resolves the `..` so the path a warning
	# prints is one somebody can paste.
	return ProjectSettings.globalize_path("res://").path_join("../scenarios").simplify_path()


func _configured_dev_root() -> String:
	if not FileAccess.file_exists(LOCAL_CONFIG):
		return ""
	var parsed: Variant = _parse_json(LOCAL_CONFIG)
	if not parsed is Dictionary:
		warnings.append("%s is not a JSON object; ignoring it" % LOCAL_CONFIG)
		return ""
	return str((parsed as Dictionary).get("scenarios_root", ""))


## Every campaign found, in root order then alphabetical by folder within a root.
##
## Alphabetical WITHIN a root rather than in directory order, because `DirAccess` order is
## a filesystem detail and a selection list that reshuffles between runs looks broken.
## Campaign order across the whole list is not a design decision the way scenario order
## is -- if it ever becomes one, `campaign.json` gains a field and this gains a sort key.
func discover() -> Array[CampaignDef]:
	warnings.clear()
	var out: Array[CampaignDef] = []
	var seen: Dictionary = {}

	for root in roots():
		var dir := DirAccess.open(root)
		if dir == null:
			# Absent is NORMAL and not a warning: a fresh clone has no
			# `user://content/scenarios/` until something installs one, and a machine
			# with no repo checkout has no dev root. Only a root that exists and cannot
			# be read is worth saying anything about.
			continue

		var folders := dir.get_directories()
		folders.sort()
		for folder in folders:
			if seen.has(folder):
				# First match wins, PLAN.md 3.3. Said out loud because a developer with
				# both an override and an installed copy is otherwise editing a file the
				# game is not reading -- which is `game/assets/atlases/`'s staleness trap
				# wearing different clothes.
				warnings.append("campaign '%s' in %s is shadowed by the copy in %s"
						% [folder, root, seen[folder]])
				continue
			var campaign := _read_campaign(root, folder)
			if campaign == null:
				continue
			seen[folder] = root
			out.append(campaign)

	return out


func _read_campaign(root: String, folder: String) -> CampaignDef:
	var dir_path := root.path_join(folder)
	var json_path := dir_path.path_join(CampaignDef.JSON_FILE)
	if not FileAccess.file_exists(json_path):
		# A directory with no campaign.json is not a campaign. Silent rather than warned:
		# an installed pack may keep sibling directories, and warning about every one of
		# them trains people to ignore the warnings.
		return null

	var parsed: Variant = _parse_json(json_path)
	if not parsed is Dictionary:
		warnings.append("%s is not a JSON object" % json_path)
		return null

	var d: Dictionary = parsed
	var c := CampaignDef.new()
	c.folder = folder
	c.root = root
	c.name = str(d.get("name", folder))
	c.description = str(d.get("description", ""))

	var icon := dir_path.path_join(CampaignDef.ICON_FILE)
	if FileAccess.file_exists(icon):
		c.icon_path = icon
	var background := dir_path.path_join(CampaignDef.BACKGROUND_FILE)
	if FileAccess.file_exists(background):
		c.background_path = background

	_read_scenarios(c, dir_path, d.get("scenarios", []))
	for p in c.all_problems():
		warnings.append(p)
	return c


func _read_scenarios(c: CampaignDef, dir_path: String, raw: Variant) -> void:
	if not raw is Array or (raw as Array).is_empty():
		c.problems.append("no 'scenarios' list -- a campaign names its scenario folders"
				+ " in play order (scenario_10 sorts before scenario_2, so the order"
				+ " cannot be derived from the names)")
		return

	var named: Dictionary = {}
	for entry in (raw as Array):
		var folder := str(entry)
		named[folder] = true
		var scenario_dir := dir_path.path_join(folder)
		var json_path := scenario_dir.path_join(ScenarioDef.JSON_FILE)
		if not FileAccess.file_exists(json_path):
			c.problems.append("names scenario '%s' but %s does not exist"
					% [folder, json_path])
			continue

		var parsed: Variant = _parse_json(json_path)
		if not parsed is Dictionary:
			c.problems.append("scenario '%s' is not a JSON object" % folder)
			continue
		c.scenarios.append(ScenarioDef.from_dict(folder, parsed as Dictionary, scenario_dir))

	# A folder the order list forgot. Reported rather than appended: it is either work in
	# progress or a typo in the list, and playing it last is wrong for both. See
	# `CampaignDef`'s class comment.
	var on_disk := DirAccess.open(dir_path)
	if on_disk != null:
		for folder in on_disk.get_directories():
			if not named.has(folder) \
					and FileAccess.file_exists(dir_path.path_join(folder)
							.path_join(ScenarioDef.JSON_FILE)):
				c.problems.append("folder '%s' holds a %s but campaign.json's order does"
						% [folder, ScenarioDef.JSON_FILE]
						+ " not name it, so it will never be played")


## ⚠️ **`JSON.new().parse()`, NEVER `JSON.parse_string()`, AND THAT IS NOT A STYLE
## CHOICE.**
##
## The static helper **pushes an engine error per failure** where the instance form
## returns a code (AGENT_GAME_CODER.md §6, found via `LanBeacon.decode`). Irrelevant on a
## config file that ships with the game; a real hole here, because **a campaign is
## downloadable, shareable content** -- PLAN.md 3.3's whole reason for moving it out of
## `res://` -- so these bytes are as untrusted as a network packet. One malformed shared
## campaign should cost one warning a player can read, not a log somebody else can fill.
##
## `GameDataRegistry._read_json` uses the static form and is right to: `res://data/*.json`
## ships in the APK and cannot be replaced by a third party.
func _parse_json(path: String) -> Variant:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		warnings.append("%s is empty or unreadable" % path)
		return null
	var json := JSON.new()
	if json.parse(text) != OK:
		warnings.append("%s: line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data
