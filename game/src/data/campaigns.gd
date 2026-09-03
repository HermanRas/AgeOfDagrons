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
## ## THE PRICE THIS USED TO CARRY, AND WHO PAYS IT NOW: NOBODY (0.3 landed 2026-09-03)
##
## This header used to say, in bold, that **a campaign could not be tested on a phone until
## 0.3 `AssetPacks` landed** -- `user://` on Android being internal app storage, and the dev
## override being editor-only. That was true when it was written and it is **no longer
## true**, twice over:
##
##   - **0.3 is built.** `PackInstaller` downloads a campaign, verifies its SHA-256 and
##     installs it into `USER_ROOT`, so the delivery path this file reads from is a real one
##     rather than a promise. **VERIFIED ON HARDWARE by the owner, 2026-09-03**, on PC and
##     phone, offline, online, and on a throttled 125 kbps connection.
##   - **A debug build never needed to wait anyway.** A `--export-debug` APK is
##     `android:debuggable`, so `adb shell run-as <pkg>` reaches the app's own files
##     directory -- a third escape beyond PLAN.md 3.3's two, needing no code and no
##     re-export. `Docs/MOBILE_DEPLOY.md` carries it, and it is how Phase 15 was first
##     played on a phone on 2026-09-02, before 0.3 existed.
##
## Kept rather than deleted because the SHAPE of the dependency is still the thing to
## understand about this file: the override is editor-only, a device reads `USER_ROOT`, and
## something has to put content there.
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
##
## ⚠️ **AN EMPTY `warnings` IS THE SHIPPED-CONTENT CONTRACT**, which `test_campaign_screen`
## asserts: a shadowed, malformed or half-declared campaign in the repo's own `scenarios/`
## is a broken commit rather than a runtime state. That is exactly why `notes` below is a
## SECOND list and not more entries in this one.
var warnings: Array[String] = []

## Things worth saying that are not wrong (2026-09-02). Separate from `warnings` because
## that list has to be able to stay empty -- see its note.
##
## Today this is one thing: a scenario folder `campaign.json`'s order does not name, which
## is what a half-written mission looks like on disk. The owner started authoring
## `scenario_4/` and, while it was a `warning`, it both failed the shipped-content test and
## made the three finished missions unplayable. `CampaignDef.notes` carries the reasoning.
var notes: Array[String] = []


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
	notes.clear()
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
	# Notes go into their OWN list, not into `warnings`. A designer wants to be told that a
	# folder of theirs will never be played; `warnings` has to be able to stay empty for
	# shipped content, and a half-written mission on a developer's disk must not break that.
	for n in c.all_notes():
		notes.append(n)
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
		var s := ScenarioDef.from_dict(folder, parsed as Dictionary, scenario_dir)
		# WHERE IT SITS IN THIS CAMPAIGN (15.7). Set here because only this loop knows: the
		# ORDER comes from `campaign.json`'s list and deliberately not from the folder names
		# (`scenario_10` sorts before `scenario_2`), so the index is the position in THIS
		# append sequence and nothing else can derive it. `progress` is a count of
		# completions and so also the index of the first locked scenario, which is why the
		# index rather than the folder is what a win is recorded against.
		s.campaign_folder = c.folder
		s.index = c.scenarios.size()
		c.scenarios.append(s)

	# A folder the order list forgot. Still reported -- it is the only warning a designer
	# gets that a scenario they have written will never be played -- but reported as a NOTE
	# rather than a problem, so it does not stop the campaign.
	#
	# ⚠️ **IT WAS A `problem` UNTIL 2026-09-02 AND THAT MADE A WORK IN PROGRESS FATAL.** The
	# owner began authoring `scenario_4/`, and because `CampaignDef.is_playable()` is
	# `problems.is_empty()`, the three FINISHED missions could no longer be started. An
	# unnamed folder means either work in progress or a typo in the order list; the first
	# wants the campaign to keep working, and the second is caught by the other end of the
	# same pair a few lines up -- an order entry naming a folder that does not exist is
	# still a `problem`, and still fatal. Never appended to the play order, either way:
	# playing it last is wrong for both readings.
	var on_disk := DirAccess.open(dir_path)
	if on_disk != null:
		for folder in on_disk.get_directories():
			if not named.has(folder) \
					and FileAccess.file_exists(dir_path.path_join(folder)
							.path_join(ScenarioDef.JSON_FILE)):
				c.notes.append("folder '%s' holds a %s but campaign.json's order does"
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
