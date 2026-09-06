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

## Armies a scenario starts its HUMAN with, stamped into the saved map after generation.
## Keyed `"<campaign folder>/<scenario folder>"`; absent means the ordinary opening.
##
## ## WHY THE ARMY IS IN THE MAP AND NOT IN `scenario.json`
##
## A saved map **already is** the per-scenario starting-entity list -- `MapGen.build_from`
## spawns exactly what it lists, resolving the 1-based player index as it goes -- so putting
## the army there needs no runtime code at all, and it is the form Phase 16's MapMaker will
## author anyway. A `starting_units` field in `scenario.json` would be a second mechanism
## for the same thing, and a worse one: the map is what a launch reads, so the field would
## be a number in a file that **does nothing until somebody re-runs this tool**. That is a
## documented lie waiting to happen, and it is the same shape as the `seed` trap this whole
## file exists to close -- *the map is the authority; everything beside it is provenance*.
##
## So this table is the authoring record, `--force` re-applies it, and `test_campaigns`
## asserts the saved map really carries what the briefing promises.
##
## ⚠️ **THE POPULATION CAP IS NOT RAISED TO MATCH, DELIBERATELY.** 75 units against a town
## centre's 10 is a HUD reading of `81/10` for as long as the army is alive, and no
## training is possible until losses bring it back under. That is `PopulationSystem`'s
## declared direction (*report the truth, refuse only the NEXT order*) rather than a
## defect, and it is not a dead end: the army dying frees the cap, so the player can always
## rebuild. Covering it would mean either houses by the dozen or castles, which train and
## shoot and would change the mission. **The owner's call, and it was looked at on the
## first playtest** -- the army came down, the cap did not go up.
##
## **CUT FROM 155 TO 75 ON 2026-09-06 AFTER THAT PLAYTEST** -- *"the army is way too much,
## make it 25 elite swardsmen and 0 anogers"*. Swordsmen 100 -> 25 and the onagers dropped
## outright; **archers were not mentioned and stay at 50**, which is the literal reading of
## an instruction that named two numbers precisely and left the third alone.
##
## Losing the onagers costs the mission nothing and tidies something up: they are `speed: 0`
## siege that must pack to move, they were the slowest thing in the column by a long way, and
## a **flying** target is the one thing a siege engine is worst against. They were in the
## first draft because "an army" wants a siege piece in it, which is a habit rather than a
## reason.
const GARRISONS := {
	"HowToPlay/scenario_4": [
		[&"unit.elite_swordsman", 25],
		[&"unit.archer", 50],
	],
}


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

	# THE GARRISON GOES IN AFTER THE VALIDATOR HAS ALREADY PASSED THE MAP, so it is
	# re-validated below rather than trusted. `MapGenerator.generate` runs `MapValidator`
	# itself and writes the verdict into `meta.problems`, which is what was just checked --
	# a map with 155 entities added since is not the map that was checked.
	var garrison := GARRISONS.get("%s/%s" % [s.campaign_folder, s.folder], []) as Array
	if not garrison.is_empty():
		var placed := _garrison(data, garrison)
		if placed < 0:
			print("  ! %-14s no room for the garrison near player 1's start" % s.folder)
			return "failed"
		print("    + garrison: %d units at player 1's start" % placed)

		# RE-RUN, and not because units are expected to break anything -- they are not
		# blocking and they are not resources, so connectivity and `MIN_NEARBY` cannot move.
		# It is the OVERLAP count that matters: a unit's tile is claimed as far as placement
		# goes, and 155 of them stamped near a base is exactly where two entities end up on
		# one tile. An overlapping map retries eight times in the generator and hands back an
		# unplayable one; stamped in afterwards there is nothing to retry, so it has to be
		# caught here or it ships.
		var after := MapValidator.problems(data)
		if not after.is_empty():
			print("  ! %-14s the garrison broke the map: %s" % [s.folder, "; ".join(after)])
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


## Stand `spec`'s units on free ground around player 1's start. Returns how many were
## placed, or **-1 if it could not place every one of them**.
##
## ALL OR NOTHING, because the briefing names the numbers. Placing 94 of 100 swordsmen
## because the ground ran out is a mission that is quietly harder than the one that was
## authored, and the only symptom is a player losing a fight they were meant to win.
##
## RINGS OUTWARD FROM THE START, in a fixed order, so the same table produces the same map
## every time -- no RNG is drawn here at all, which is what keeps this step from disturbing
## the generator's stream the way `_place_nest` had to be careful not to.
##
## ⚠️ **A UNIT'S TILE IS CLAIMED EVEN THOUGH A UNIT BLOCKS NOTHING.** `MapData` says so at
## `footprint_rect_of` and `MapValidator._overlapping_entities` enforces it: two villagers
## must not be written onto one tile. So `claimed` grows as we go, and the town centre's
## 10x10 and every resource node in the opening are already in it.
##
## SIZE_CLASS 0 and PLAYER 1: the human. A garrison for an opponent would want the player
## index passed in, and no scenario has asked for one -- when one does, that is the change,
## not a second function.
func _garrison(data: MapData, spec: Array) -> int:
	if data.starts.is_empty():
		return -1
	var start: Vector2i = data.starts[0]
	var claimed := data.claimed_tiles()

	# Flattened first, so one walk outward places the whole army rather than one walk per
	# def -- which would put the archers in a ring outside the swordsmen and the onagers
	# outside them again, and 155 units is far enough out for that to be a visible band.
	var wanted: Array[StringName] = []
	for row in spec:
		var def_id: StringName = row[0]
		if GameDataRegistry.unit(def_id) == null:
			print("    ! no such unit as '%s'" % def_id)
			return -1
		for i in range(int(row[1])):
			wanted.append(def_id)

	var at := 0
	for radius in range(1, maxi(data.size.x, data.size.y)):
		for t in _ring(start, radius):
			if at >= wanted.size():
				break
			if claimed.has(t) or not data.is_ground_passable(t):
				continue
			claimed[t] = true
			data.add_entity(wanted[at], 1, t)
			at += 1
		if at >= wanted.size():
			return at
	return -1


## The tiles exactly `radius` from `centre` in Chebyshev distance, clockwise from the
## top-left corner. A ring rather than a filled square so each radius is visited once.
func _ring(centre: Vector2i, radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for x in range(centre.x - radius, centre.x + radius + 1):
		out.append(Vector2i(x, centre.y - radius))
		out.append(Vector2i(x, centre.y + radius))
	for y in range(centre.y - radius + 1, centre.y + radius):
		out.append(Vector2i(centre.x - radius, y))
		out.append(Vector2i(centre.x + radius, y))
	return out


func _arg(name: String, fallback: String) -> String:
	var args := OS.get_cmdline_user_args()
	var at := args.find(name)
	if at >= 0 and at + 1 < args.size():
		return args[at + 1]
	return fallback
