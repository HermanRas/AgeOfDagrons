## Export a scenario WITHOUT a mouse, so the round trip can be checked by two commands
## (PLAN.md 16.8).
##
## ## WHY THIS EXISTS, AND IT IS 16.2's ARGUMENT ONE FORMAT FURTHER OUT
##
## §16 decision 8: **the tool is not allowed to be the only thing that can judge its output.** The
## suite can prove the tool writes what the tool meant to write; it cannot prove the GAME can read
## it, because the game is a different Godot project with a different `res://` and its own loader.
## So the check is two processes:
##
##     Godot --headless --path MapMaker res://dev/export_scenario.tscn
##     Godot --headless --path game res://dev_preview/preview_exported_campaign.tscn -- --campaign ExportCheck
##     Remove-Item -Recurse -Force scenarios\ExportCheck     # ⚠️ AND THEN DELETE IT
##
## Neither can check the other, which is decision 2's whole point — **the FILE is the contract**.
##
## ⚠️ **DELETE THE CAMPAIGN AFTERWARDS.** The owner's rule of 2026-09-04 about test maps applies
## with more force here: `scenarios/` holds the shipped campaign, and a leftover `ExportCheck`
## would appear in the game's own campaign list. It is written to a folder nothing else uses and
## rebuilt in seconds, so it is a build artefact that happens to land in a tracked directory.
##
## ⛔ **AND A `Remove-Item -Recurse` IN THIS REPO TAKES OUT THE FILES AND LEAVES THE FOLDERS**,
## because Google Drive marks every directory read-only and Windows will not remove a read-only
## directory even when it is empty. That is survivable here and worth knowing: an empty
## `scenarios/ExportCheck/` is **not** a campaign — `Campaigns._is_campaign_dir()` asks for a
## `campaign.json` — so the husk is inert rather than a broken campaign in the list.
##
## ## IT AUTHORS SOMETHING THAT EXERCISES THE VOCABULARY, NOT THE MINIMUM
##
## A scenario with one `unit >= 1` win row round-trips through anything. This one declares a
## **region and an `area` row that names it**, which is the only pairing in the schema that no
## single file can validate: `ObjectiveDef` has never seen a map, and `ScenarioDef.build_config()`
## is the first moment both halves exist. A map whose region did not survive leaves that row
## counting nothing forever, and every other assertion still passes.
##
## Usage:
##   Godot --headless --path MapMaker res://dev/export_scenario.tscn [-- --force] [--campaign X]
extends Node

## The campaign this writes. **A name nothing else uses**, so the delete at the end of the round
## trip can never take somebody's content with it.
const DEFAULT_CAMPAIGN := "ExportCheck"

const SCENARIO_FOLDER := "scenario_1"
const AREA_NAME := &"the_ford"
const SIDE := 64

## 16.7's half of the round trip: a named hero with all three overrides on him.
##
## ⛔ **HE IS HERE BECAUSE THE NAME IS THE SECOND THING NO SINGLE FILE CAN VALIDATE.** A region was
## the first — `ObjectiveDef` has never seen a map — and a hero is the same gap one row along:
## the `named_unit` condition below names him, the map declares him, and **only the game, in the
## other project, can say the two met.** The overrides ride with him because they are the other
## half of 16.7 and they are invisible in every file they pass through: a map whose `hp: 900` did
## not survive the JSON builds a 40 hp militia and every other assertion still passes.
const HERO_NAME := &"Sir Roland"
const HERO_DEF := &"unit.militia"
const HERO_HP := 900
const HERO_ATTACK := 60
const HERO_SPEED := 150


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var campaign := _arg(args, "--campaign", DEFAULT_CAMPAIGN)
	var force := args.has("--force")

	var root := GameRoot.resolve()
	if root.path.is_empty():
		printerr("cannot find the game project: %s"
				% "; ".join(PackedStringArray(root.problems)))
		get_tree().quit(1)
		return
	if not GameDataRegistry.load_from(root):
		printerr("could not read the roster from %s" % root.path)
		get_tree().quit(1)
		return

	# ⚠️ **BOTH GUARDS, AND THEY ANSWER DIFFERENT QUESTIONS.** `passed()` is the permission to write
	# a MAP and `schema_ok()` is the permission to write a SCENARIO — see `FormatGuard.SCHEMA`. A
	# dev script that honoured one and not the other would be the hole the pair exists to close,
	# and it would be the quieter of the two: a stale scenario vocabulary produces a file the game
	# refuses rather than a file it misreads.
	var guard := FormatGuard.check(root)
	if not guard.passed():
		printerr(guard.refusal())
		get_tree().quit(1)
		return
	if not guard.schema_ok():
		printerr(guard.schema_refusal())
		get_tree().quit(1)
		return

	var scenarios := ScenarioExport.scenarios_root()
	var target := scenarios.path_join(campaign).path_join(SCENARIO_FOLDER)
	if MapFile.exists_in(target) and not force:
		# REFUSES TO OVERWRITE, `dev/author_map.gd`'s rule: authored content is under version
		# control, and a silent replacement would overwrite something somebody may have balanced
		# against. The export itself refuses too; this is the earlier, clearer message.
		print("keeping the existing %s — pass --force to replace it" % target)
		get_tree().quit(0)
		return
	if force:
		# THE EXPORT'S OWN REFUSAL IS WHAT `--force` IS OVERRIDING, so the map has to go first.
		# Only this one folder, and only its two files: a recursive delete here would be a script
		# that removes directories in a repo where directories are read-only.
		for f in [MapFile.META_FILE, MapFile.TERRAIN_FILE, ScenarioDef.JSON_FILE,
				ScenarioDef.ICON_FILE]:
			DirAccess.remove_absolute(target.path_join(f))

	var doc := _author()
	var exporter := ScenarioExport.new()
	var problems := exporter.run(doc, _request(campaign), guard, scenarios)
	if not problems.is_empty():
		printerr("export refused: %s" % "; ".join(PackedStringArray(problems)))
		get_tree().quit(1)
		return

	print("wrote:")
	for path in exporter.written:
		print("  %s" % path)
	for w in exporter.warnings:
		print("  note: %s" % w)

	var ok := _verify(doc, scenarios.path_join(campaign))
	print("")
	print("NOW PROVE THE GAME CAN READ IT, WHICH THIS PROCESS CANNOT:")
	print("  Godot --headless --path game res://dev_preview/preview_exported_campaign.tscn"
			+ " -- --campaign %s" % campaign)
	print("  Remove-Item -Recurse -Force scenarios\\%s      # and then delete it" % campaign)
	get_tree().quit(0 if ok else 1)


# ── the map ─────────────────────────────────────────────────────────────────

## A small two-player map with a ford across it and a named region on the ford.
##
## Everything goes through `MapDocument`'s real mutations — the same calls the editor's buttons
## make — so this exercises the tool's own path rather than a shortcut into `MapData`.
func _author() -> MapDocument:
	var doc := MapDocument.create(Vector2i(SIDE, SIDE), "Export Check")
	var mid := SIDE / 2
	for y in range(SIDE):
		# A WANDERING river, so the map is not mirror-symmetric: a symmetric map cannot tell a
		# correct round trip from one that transposed x and y.
		var centre := mid + int(round(sin(float(y) / 7.0) * 4.0))
		for x in range(SIDE):
			var d := absi(x - centre)
			if d <= 1:
				doc.paint(Vector2i(x, y), SimMap.Terrain.WATER_DEEP)
			elif d <= 3:
				doc.paint(Vector2i(x, y), SimMap.Terrain.WATER_SHALLOW)
			elif d <= 5:
				doc.paint(Vector2i(x, y), SimMap.Terrain.SAND)
	# THE FORD ITSELF: dry ground across the river, so the region below sits on something a person
	# can see in the editor rather than on open water.
	for y in range(mid - 2, mid + 3):
		for x in range(SIDE):
			doc.paint(Vector2i(x, y), SimMap.Terrain.GRASS)

	# PLACED CLEAR OF THE WATER, `dev/author_map.gd`'s note: `StartLayout` refuses to put a unit on
	# ground it cannot stand on, so a start in the river comes out with fewer villagers than it
	# should — a map that loads, plays, and is wrong in a way only a count would reveal.
	doc.place_start(1, Vector2i(12, 44))
	doc.place_start(2, Vector2i(SIDE - 12, 16))

	if not doc.add_area(AREA_NAME, Rect2i(mid - 6, mid - 2, 13, 5)):
		printerr("the region did not go down — the area round trip is not being checked")

	# ⛔ **THE HERO GOES DOWN THROUGH THE REAL MUTATIONS**, including the selection the inspector
	# acts on — `set_selected_name` and `set_selected_override` are exactly what the panel calls,
	# so this exercises the tool's own path rather than writing the record by hand.
	if doc.add_entity(HERO_DEF, 1, Vector2i(mid - 10, mid)):
		doc.selected = doc.data.entities.size() - 1
		doc.set_selected_name(HERO_NAME)
		doc.set_selected_override("hp", HERO_HP)
		doc.set_selected_override("attack", HERO_ATTACK)
		doc.set_selected_override("speed", HERO_SPEED)
		doc.clear_selection()
	else:
		printerr("the hero did not go down — 16.7's round trip is not being checked")

	for record in _conditions():
		var row_problems: Array[String] = []
		if not doc.add_objective(record, row_problems):
			printerr("condition refused: %s" % "; ".join(PackedStringArray(row_problems)))
	return doc


## Three rows, chosen to exercise three different halves of the vocabulary.
##
## ⛔ **THE `area` ROW IS THE ONE THIS SCRIPT EXISTS FOR.** It is the only pairing in the schema
## that no single file can validate — `ObjectiveDef` has never seen a map, so the region name is
## checked for the first time in `ScenarioDef.build_config()`, in the other project. A map whose
## region did not survive the JSON leaves this row counting nothing forever, and every other
## assertion in both processes still passes.
func _conditions() -> Array[Dictionary]:
	return [
		{
			"subject": "building", "id": "building.house", "owner": "self",
			"compare": ">=", "value": 1, "output": "win", "text": "Build a house",
		},
		{
			"subject": "unit", "id": "unit.villager", "owner": "self",
			"compare": ">=", "value": 8, "output": "win", "text": "Reach 8 villagers",
		},
		{
			"subject": "area", "area": String(AREA_NAME), "owner": "self",
			"compare": ">=", "value": 1, "output": "alert",
			"text": "Somebody of yours is standing on the ford",
		},
		# ⛔ **16.7's ROW, AND IT IS THE SHAPE AN AUTHOR ACTUALLY WANTS: "protect him".** `== 0` with
		# `output: "lose"` fires on the tick he dies — which is only safe because the map DECLARES
		# him, so 0 means *gone* rather than *nobody is called that*. Written this way round on
		# purpose: `>= 1` as a win row would latch on tick 1 and prove nothing.
		{
			"subject": "named_unit", "name": String(HERO_NAME), "owner": "self",
			"compare": "==", "value": 0, "output": "lose",
			"text": "Sir Roland must survive",
		},
	] as Array[Dictionary]


func _request(campaign: String) -> Dictionary:
	return {
		"campaign_folder": campaign,
		"campaign_name": "Export Check",
		"campaign_description": "Written by dev/export_scenario.tscn. Delete it after the check.",
		"folder": SCENARIO_FOLDER,
		"name": "The Ford",
		"description": "A two-player duel across a river with one crossing.",
		"message": "Objective: build a house and reach eight villagers.\n\n"
				+ "Overview: this scenario exists to prove the export, not to be fun.",
		"opponents": ["passive"],
		"starting_age": 1,
		"icons": {},
	}


# ── verification, from this side only ───────────────────────────────────────

## Read both files back and say whether they are what we wrote.
##
## ⚠️ **THIS IS THE HALF THAT PROVES NOTHING ON ITS OWN AND IS STILL WORTH DOING.** A fault it
## catches is one the game would also report, one process earlier and with the tool's own
## vocabulary to describe it. What it cannot do is speak for the game's loader, which is the whole
## reason for the second command.
func _verify(doc: MapDocument, campaign_dir: String) -> bool:
	var ok := true
	var scenario_dir := campaign_dir.path_join(SCENARIO_FOLDER)
	var scenario := _read(scenario_dir.path_join(ScenarioDef.JSON_FILE))
	var campaign := _read(campaign_dir.path_join(CampaignDef.JSON_FILE))
	if scenario.is_empty() or campaign.is_empty():
		return false

	print("")
	# ⚠️ **`int()` ON THE AGE, AND IT IS NOT TIDINESS.** This line reads the file back through
	# `JSON.parse`, which widens every integer to a float — so printing it raw says `age=1.0` about
	# a file that correctly holds `1`. §6's rule about the profiler's stale number: *a number that
	# is quietly wrong is worse than no number, because it gets believed*, and here it would be
	# believed as evidence AGAINST the very widening fix this export performs.
	print("  scenario.json  mode=%s  opponents=%s  age=%d  objectives=%d"
			% [scenario.get("mode", "?"), scenario.get("opponents", []),
			int(scenario.get("starting_age", 0)),
			(scenario.get("objectives", []) as Array).size()])
	print("  campaign.json  name=%s  order=%s"
			% [campaign.get("name", "?"), campaign.get(CampaignDef.ORDER_KEY, [])])

	if str(scenario.get("mode", "")) != "scenario":
		printerr("mode should be derived as 'scenario' from four condition rows")
		ok = false
	if (scenario.get("objectives", []) as Array).size() != 4:
		printerr("four conditions were authored")
		ok = false
	# ⛔ **THE AUTHOR'S WORDS AND NOT THE WIRE FORM.** `to_dict()` writes every enum as an int, and a
	# `scenario.json` of integers is one the game's own loader cannot read at all — while this tool
	# looks perfect throughout, because it never re-parses its own output.
	for entry in (scenario.get("objectives", []) as Array):
		var row: Dictionary = entry
		if not (row.get("subject") is String):
			printerr("an objective's subject is not a word: %s" % [row])
			ok = false
	# THE SIDECAR MUST NOT KEEP A SECOND COPY. The map is saved before the scenario exists, so the
	# rows land there first and the export has to move them.
	var sidecar := _read(scenario_dir.path_join(MapFile.META_FILE))
	if sidecar.has("objectives"):
		printerr("the map sidecar kept a stale copy of the conditions: %s" % [sidecar["objectives"]])
		ok = false
	if doc.dir != scenario_dir:
		printerr("the document was not re-pointed: %s" % doc.dir)
		ok = false

	# THE REGION, READ BACK OFF THE MAP FILE. `area` is the newest field in the format and its
	# absence is invisible from the scenario alone — the row would simply count nothing forever.
	var problems: Array[String] = []
	var back := MapFile.load_map(scenario_dir, problems)
	if back == null:
		printerr("cannot read the map back: %s" % "; ".join(PackedStringArray(problems)))
		return false
	if not back.has_area(AREA_NAME):
		printerr("the region '%s' did not survive — the area row counts nothing" % AREA_NAME)
		ok = false

	# ⛔ **THE HERO AND HIS THREE NUMBERS, READ BACK OFF THE FILE** (16.7). Both keys are OPTIONAL,
	# which is what keeps `FORMAT_VERSION` at 1 — and optional is exactly the shape that can vanish
	# through a writer without anything failing. A map whose `hp: 900` did not survive builds an
	# ordinary 40 hp militia, and every other line in this report still reads correctly.
	var hero: Dictionary = {}
	for e in back.entities:
		if StringName(e.get("name", &"")) == HERO_NAME:
			hero = e
	if hero.is_empty():
		printerr("'%s' did not survive the file — the named_unit row counts nobody" % HERO_NAME)
		ok = false
	else:
		var overrides: Dictionary = hero.get("overrides", {})
		for pair in [["hp", HERO_HP], ["attack", HERO_ATTACK], ["speed", HERO_SPEED]]:
			var got := int(overrides.get(str(pair[0]), -999))
			if got != int(pair[1]):
				printerr("%s override: wrote %d, read back %d" % [pair[0], pair[1], got])
				ok = false
		print("  hero           '%s' %s" % [HERO_NAME, overrides])
	print("  map.json       %dx%d  seats=%d  regions=%s"
			% [back.size.x, back.size.y, doc.seats(), back.area_names()])
	return ok


func _read(path: String) -> Dictionary:
	var problems: Array[String] = []
	var d := ScenarioFile.read(path, problems)
	if not problems.is_empty():
		printerr("%s: %s" % [path, "; ".join(PackedStringArray(problems))])
	elif d.is_empty():
		printerr("%s is missing" % path)
	return d


func _arg(args: PackedStringArray, key: String, fallback: String) -> String:
	var at := Array(args).find(key)
	return str(args[at + 1]) if at >= 0 and at + 1 < args.size() else fallback
