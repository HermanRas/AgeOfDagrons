## Can the GAME read a campaign the MapMaker wrote? (PLAN.md 16.8, the second half of the round
## trip.) **Headless, no screenshots, and the exit code is the answer.**
##
## ## ⛔ WHY THIS LIVES HERE AND NOT IN THE MAPMAKER'S SUITE
##
## §16 decision 8: *the tool is not allowed to be the only thing that can judge its output.* 16.8
## makes the MapMaker the **second consumer of 15.1's schema**, and a second writer is where a
## format quietly grows a dialect — but the tool's own tests can only ever prove it wrote what it
## meant to write. The question that matters is whether `Campaigns`, `CampaignDef` and
## `ScenarioDef` — **in this project, with this project's loader** — accept the result, and no
## process in the MapMaker can answer it.
##
## That is the same shape as 16.2's map round trip (`author_map` writes, `preview_saved_map` plays)
## one format further out, and the same rule underneath: **the FILE is the contract, not the code.**
##
##     Godot --headless --path MapMaker res://dev/export_scenario.tscn
##     Godot --headless --path game res://dev_preview/preview_exported_campaign.tscn -- --campaign ExportCheck
##     Remove-Item -Recurse -Force scenarios\ExportCheck
##
## ## WHAT IT CHECKS THAT A GREEN SUITE CANNOT
##
##   - **`Campaigns.discover()` finds it at all.** A campaign whose folder or `campaign.json` is
##     misspelled is simply absent from the list, which looks identical to "nothing was written".
##   - **`warnings` is EMPTY.** `test_campaign_screen` asserts that of shipped content for a
##     reason: a warning here is the loader saying it read something it did not like.
##   - **every scenario is `is_playable()`**, which is what greys the PLAY button. A scenario that
##     loads and refuses to start is the failure this whole row is arranged around, and its only
##     symptom in the game is a dead button.
##   - **`build_config()` returns a config**, which is where the two halves of an `area` objective
##     meet for the first time: `ObjectiveDef` has never seen a map, so a row naming a region the
##     map has not got is caught HERE and nowhere earlier.
##   - **the map the config carries is the map on disk.** A scenario that reads its terrain from
##     somewhere else looks perfect in every other assertion.
##
## ⚠️ **`--campaign HowToPlay` WORKS AND IS ANNOUNCED RATHER THAN REFUSED.** Running these checks
## against the shipped campaign is a reasonable thing to want — they are the same checks — but a
## pass there says nothing whatever about the export, and *"I ran it and it passed"* is exactly the
## sentence that ends an investigation. So the run says out loud which campaign it read.
extends Node

## What `dev/export_scenario.tscn` writes, and therefore what this reads.
const DEFAULT_CAMPAIGN := "ExportCheck"

## The shipped campaign. Named only so a run against it can say so — see the class comment.
const SHIPPED_CAMPAIGN := "HowToPlay"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var wanted := _arg(args, "--campaign", DEFAULT_CAMPAIGN)
	print("\n=== exported campaign check (16.8) ===")
	print("looking for campaign '%s'" % wanted)
	if wanted == SHIPPED_CAMPAIGN:
		print("⚠ that is the SHIPPED campaign, not an exported one — these checks pass on it")
		print("  whatever the MapMaker does. Run dev/export_scenario.tscn and read %s instead."
				% DEFAULT_CAMPAIGN)

	var loader := Campaigns.new()
	var campaigns := loader.discover()
	var found: CampaignDef = null
	for c in campaigns:
		if c.folder == wanted:
			found = c

	var ok := true
	if found == null:
		var names := PackedStringArray()
		for c in campaigns:
			names.append(c.folder)
		# NAMES WHAT IT DID FIND, because "not found" and "found under another name" want
		# different fixes and look identical from one line of output. `Campaigns` reads repo-root
		# `scenarios/` only in an EDITOR run, which is the other thing this could mean.
		printerr("no campaign '%s'. Found: [%s] in roots [%s]"
				% [wanted, ", ".join(names), ", ".join(PackedStringArray(loader.roots()))])
		printerr("  (run dev/export_scenario.tscn in the MapMaker first)")
		get_tree().quit(1)
		return

	print("\ncampaign '%s' (%s) from %s" % [found.name, found.folder, found.root])
	print("  %d scenario(s) in play order: %s" % [found.scenarios.size(),
			_folders(found)])
	print("  icon=%s  background=%s"
			% [_yes_no(found.icon_path), _yes_no(found.background_path)])

	# ⛔ **A WARNING IS A FAILURE HERE.** `test_campaign_screen` holds shipped content to exactly
	# this standard — *"a shadowed, malformed or half-declared campaign in the repo's own
	# `scenarios/` is a broken commit rather than a runtime state"* — and a campaign the tool just
	# wrote has no excuse the shipped one does not have.
	for w in loader.warnings:
		printerr("  WARNING: %s" % w)
		ok = false
	# A NOTE IS NOT. The one thing it says today is *"a folder the order list does not name"*, which
	# is a half-written mission on somebody's disk and deliberately not fatal.
	for n in loader.notes:
		print("  note: %s" % n)

	if not found.is_playable():
		printerr("  the campaign is not playable: %s" % [found.all_problems()])
		ok = false

	for s in found.scenarios:
		if not _check(s):
			ok = false

	print("")
	print("=== %s ===" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)


## One scenario, from the loader's verdict through to the config a PLAY button would build.
func _check(s: ScenarioDef) -> bool:
	print("\n--- %s : %s" % [s.folder, s.name])
	var ok := true
	if not s.is_playable():
		# ⛔ **THIS IS THE FAILURE THE WHOLE ROW IS ARRANGED AROUND.** `is_playable()` is what
		# `ScenarioScreen` greys the PLAY button on, so an unplayable scenario is a mission whose
		# only symptom in the game is a dead button and a line in a log nobody is reading.
		for p in s.problems:
			printerr("    UNPLAYABLE: %s" % p)
		return false

	var problems: Array[String] = []
	var cfg := s.build_config(problems)
	if cfg == null:
		printerr("    REFUSED TO LAUNCH: %s" % " | ".join(problems))
		return false

	var levels := PackedStringArray()
	for i in cfg.ai_players.size():
		if cfg.ai_players[i]:
			var level: int = cfg.ai_levels[i]
			levels.append(AIProfile.IDS[level] if level >= 0 and level < AIProfile.IDS.size()
					else "?")
	print("    mode=%s  players=%d  opponents=[%s]  age=%d  objectives=%d"
			% [MatchConfig.mode_name(cfg.mode), cfg.player_ids.size(), ", ".join(levels),
			cfg.starting_age, cfg.objectives.size()])
	print("    briefing=%s  icon=%s" % [_yes_no(cfg.scenario_message), _yes_no(s.icon_path)])
	for o in cfg.objectives:
		print("      row: %s" % o.describe())

	# ⚠️ **THE MODE AGAINST THE OBJECTIVES, WHICH THE EXPORT DERIVED.** `ScenarioDef` already
	# refuses both disagreements at load, so reaching here means they agree — printing it is what
	# makes a derived field visible in the one place it can be checked against a real file.
	if cfg.mode == MatchConfig.Mode.SCENARIO and cfg.objectives.is_empty():
		printerr("    a scenario-mode mission with no objectives")
		ok = false

	# ⛔ **THE MAP THE CONFIG CARRIES AGAINST THE MAP ON DISK.** `preview_saved_map`'s load-bearing
	# step: a screen that previews one map and hands the match another looks perfect in both
	# screenshots. Here the risk is narrower and the same shape — `map_data()` reads the folder, so
	# a scenario pointed at the wrong directory would carry somebody else's ground.
	var on_disk := MapFile.load_map(s.dir, problems)
	if on_disk == null:
		printerr("    the map will not load: %s" % " | ".join(problems))
		return false
	if cfg.map_data == null or cfg.map_data.terrain != on_disk.terrain:
		printerr("    the config's map is not the map in %s" % s.dir)
		ok = false
	if cfg.map_size != on_disk.size:
		printerr("    config map_size %s, file %s" % [cfg.map_size, on_disk.size])
		ok = false
	print("    map=%dx%d  regions=%s  starts=%d"
			% [on_disk.size.x, on_disk.size.y, on_disk.area_names(), on_disk.starts.size()])

	# ⚠️ **EVERY `area` ROW AGAINST THE MAP THAT CARRIES IT.** `build_config()` already refuses an
	# unknown region — `_unknown_areas` — so this cannot fail while the call above succeeded. It is
	# printed because the pairing is the one thing NEITHER project can check alone, and a run that
	# says `area 'the_ford' ✓` is the only evidence anywhere that the region survived two formats
	# and a process boundary.
	for o in cfg.objectives:
		if o.subject != ObjectiveDef.Subject.AREA:
			continue
		var here := on_disk.has_area(o.area)
		print("      area '%s' declared by the map: %s" % [o.area, here])
		if not here:
			printerr("    an area row names a region the map has not got")
			ok = false

	# ⛔ **AND THE SAME PAIRING FOR A NAMED HERO (16.7), WHICH IS THE SECOND THING NEITHER PROJECT
	# CAN CHECK ALONE.** Built into a real world rather than read off the record, because the
	# question is not *"does the file say 900"* — `export_scenario` already asserted that in the
	# other process — but *"does the match the game builds from this file give him 900"*. That is
	# `MapGen._apply_authoring`, and it is the last link in the chain.
	if not _report_named_units(cfg, on_disk):
		ok = false
	return ok


## Build the world this config describes and report every named hero in it, with the numbers the
## SIM ended up giving him.
##
## ⚠️ **A REAL `SimWorld`, WHICH NOTHING ELSE IN THIS PREVIEW NEEDS.** Every other check here reads
## a config or a file; this one has to go one step further, because an override that reached the
## file and not the entity is invisible in both. `PreviewScenarioWin`'s own argument for standing
## up the real thing: *a rule that is correct and never reached looks exactly like a rule that is
## wrong.*
func _report_named_units(cfg: MatchConfig, on_disk: MapData) -> bool:
	var wanted: Array[StringName] = []
	for o in cfg.objectives:
		if o.subject == ObjectiveDef.Subject.NAMED_UNIT and not wanted.has(o.unit_name):
			wanted.append(o.unit_name)
	if wanted.is_empty() and not _map_names_anybody(on_disk):
		return true

	var w := SimWorld.new()
	w.setup(cfg)
	MapGen.build(w, cfg)
	var ok := true
	var found: Dictionary = {}
	for e in w.entities.values():
		if e.entity_name.is_empty():
			continue
		found[e.entity_name] = true
		print("      '%s' is a %s: hp %d/%d, attack override %d, speed override %d"
				% [e.entity_name, e.def_id, e.hp, e.max_hp, e.attack_override,
				e.speed_override])
	for name in wanted:
		# THE DECLARED SET AND NOT THE LIVE ONE, because that is what decides whether the row is
		# measurable at all -- see `SimWorld.named_units`.
		if not w.named_units.has(name):
			printerr("    a named_unit row is about '%s' and the world declares nobody by that"
					% name + " name -- the row would count -1 forever")
			ok = false
		elif not found.has(name):
			# NOT A FAILURE: a hero who is declared and not standing there is a hero who is meant
			# to arrive, or one belonging to a player this match has not seated. The count is 0,
			# which is a real answer, and only the scenario's author knows if it is the right one.
			print("      '%s' is declared and nothing carries it -- that row counts 0" % name)
	return ok


func _map_names_anybody(map: MapData) -> bool:
	for e in map.entities:
		if not str(e.get("name", "")).strip_edges().is_empty():
			return true
	return false


func _folders(c: CampaignDef) -> String:
	var out := PackedStringArray()
	for s in c.scenarios:
		out.append(s.folder)
	return ", ".join(out)


func _yes_no(value: String) -> String:
	return "yes" if not value.is_empty() else "no"


func _arg(args: PackedStringArray, key: String, fallback: String) -> String:
	var at := Array(args).find(key)
	return str(args[at + 1]) if at >= 0 and at + 1 < args.size() else fallback
