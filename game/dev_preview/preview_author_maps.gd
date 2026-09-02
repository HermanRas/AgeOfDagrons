## Writes the saved map for any scenario that has not got one (PLAN.md 11.3 / 2.4c).
##
## ## THIS IS AN AUTHORING STEP, RUN BY HAND, AND ITS OUTPUT IS COMMITTED
##
## The owner's ruling of 2026-09-01: *"just generate a map and save it for the scenario, not
## gen one every time you click the scenario.. it is just a way to get a map once off while
## i have no tool to provide you with a valid map."* So `MapGenerator` is a **tool** here and
## not a runtime step — this scene is the tool, `map.png` + `map.json` is the product, and
## `ScenarioDef.build_config()` reads the product and never calls the generator.
##
## **PHASE 16'S MapMaker REPLACES THIS SCENE, not the format.** `MapFile` is what both
## write, which is why 11.3 was promoted ahead of Phase 16: building the tool first would
## have meant inventing a second format and then reconciling two.
##
## ## IT REFUSES TO OVERWRITE, AND THAT IS THE POINT
##
## A saved map is **authored content under version control**. Regenerating one silently
## would replace a map somebody has balanced a tutorial against — and because the generator
## is `FastNoiseLite`, re-running it on a different machine or after a generator change
## produces a *different* map from the same seed, which is the whole reason the file exists.
## `--force` exists for a deliberate re-roll and says what it destroyed.
##
## Usage:
##   Godot --headless --path game res://dev_preview/preview_author_maps.tscn
##       [-- --force] [--campaign HowToPlay] [--scenario scenario_3]
extends Node


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var force := args.has("--force")
	var only_campaign := _arg("--campaign", "")
	var only_scenario := _arg("--scenario", "")

	print("AUTHORING SAVED MAPS — %s"
			% ("FORCE: existing maps will be REPLACED" if force else "skipping any that exist"))
	print("")

	var loader := Campaigns.new()
	var campaigns := loader.discover()
	for w in loader.warnings:
		print("  ! %s" % w)

	if campaigns.is_empty():
		print("No campaigns found. Searched:")
		for r in loader.roots():
			print("  %s" % r)
		get_tree().quit(1)
		return

	var written := 0
	var skipped := 0
	var failed := 0

	for c in campaigns:
		if not only_campaign.is_empty() and c.folder != only_campaign:
			continue
		print("── %s (%s) ──" % [c.name, c.folder])
		for s in c.scenarios:
			if not only_scenario.is_empty() and s.folder != only_scenario:
				continue
			var outcome := _author(s, force)
			match outcome:
				"written": written += 1
				"skipped": skipped += 1
				_: failed += 1
		print("")

	print("%d written, %d already had one, %d failed" % [written, skipped, failed])
	if written > 0:
		print("")
		print("COMMIT THE NEW FILES. They are the map from now on; the seed beside them is")
		print("only a record of how it was first made and will not reproduce it.")
	# A headless scene does not end when `_ready` returns, and a tool that has printed its
	# answer and then sits there reads as a hang.
	get_tree().quit(1 if failed > 0 else 0)


func _author(s: ScenarioDef, force: bool) -> String:
	if s.has_map() and not force:
		print("  = %-14s already has %s" % [s.folder, MapFile.TERRAIN_FILE])
		return "skipped"

	# EVERY COMPLAINT THE LOADER FOUND STILL COUNTS. A scenario with a broken `opponents`
	# list would get a map it can never use, and the player count below comes off that same
	# list -- so a map authored for a broken scenario could be the wrong SHAPE too.
	if not s.is_playable():
		print("  ! %-14s not playable, no map written: %s"
				% [s.folder, "; ".join(s.problems_or_self())])
		return "failed"

	# One human plus the declared opponents, which is exactly what `build_config` will ask
	# for. Derived from the same field rather than from a count written twice.
	var players := 1 + s.opponents.size()
	var data := MapGenerator.generate(s.seed, s.map_type, players)
	if data == null or data.size.x <= 0:
		print("  ! %-14s generator produced nothing for seed %d" % [s.folder, s.seed])
		return "failed"

	# THE VALIDATOR'S VERDICT TRAVELS WITH THE MAP. `MapGenerator` surfaces its own
	# complaints in `meta.problems` after retrying, and 1.6 uses them to grey out Start. A
	# map authored past them would be a tutorial nobody can finish, found in play rather
	# than here.
	var map_problems: Array = data.meta.get("problems", [])
	if not map_problems.is_empty():
		print("  ! %-14s map failed validation: %s"
				% [s.folder, "; ".join(PackedStringArray(map_problems))])
		return "failed"

	var was := s.has_map()
	var problems := MapFile.save(data, s.dir, {
		"name": s.name,
		"map_type": MapGenerator.Type.keys()[s.map_type],
		"players": players,
		"seed": s.seed,
		"authored_by": "preview_author_maps",
	})
	if not problems.is_empty():
		print("  ! %-14s %s" % [s.folder, "; ".join(problems)])
		return "failed"

	print("  %s %-14s %dx%d, %d entities, %d starts, seed %d%s" % [
			"~" if was else "+", s.folder, data.size.x, data.size.y,
			data.entities.size(), data.starts.size(), s.seed,
			"  (REPLACED)" if was else ""])

	# READ IT BACK BEFORE CLAIMING IT IS WRITTEN. The point of this tool is a file the game
	# can load, and a round trip is the only thing that proves the pair agree -- the size
	# cross-check in `load_map` is exactly what a half-written PNG would trip.
	var check: Array[String] = []
	var reloaded := MapFile.load_map(s.dir, check)
	if reloaded == null:
		print("    ! WROTE IT AND CANNOT READ IT BACK: %s" % "; ".join(check))
		return "failed"
	if reloaded.terrain != data.terrain:
		print("    ! round trip changed the terrain -- the PNG is not lossless here")
		return "failed"
	return "written"


func _arg(name: String, fallback: String) -> String:
	var args := OS.get_cmdline_user_args()
	var at := args.find(name)
	if at >= 0 and at + 1 < args.size():
		return args[at + 1]
	return fallback
