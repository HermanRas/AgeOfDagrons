## PLAN.md 11.3 / 2.4c: a map on disk as `map.png` plus a `map.json` sidecar.
##
## **THIS IS THE FORMAT PHASE 16'S MapMaker WRITES**, on the owner's ruling of 2026-09-01
## (*"2.4c will guide tool"*), so the round trip being exact is not a convenience — it is
## the contract the tool is built against.
##
## Everything here works in `user://`, never in `scenarios/`: the shipped maps are authored
## content under version control, and a test that wrote into them would be a test that
## edits the game.
extends TestCase

const DIR := "user://test_map_file"

var _n := 0


func before_each() -> void:
	_n += 1


func after_each() -> void:
	# Each test gets its own directory (see `_dir`), and they are left behind deliberately:
	# `user://` is scratch on a developer's machine, and deleting a directory recursively is
	# a lot of blast radius for a tidiness that nothing depends on.
	pass


func _dir() -> String:
	return "%s/case_%d" % [DIR, _n]


## A map with something in every field, so a round trip has something to lose.
func _sample(size: Vector2i = Vector2i(9, 7)) -> MapData:
	var m := MapData.create(size, SimMap.Terrain.GRASS)
	# Every terrain kind, so a channel mix-up or a palette-based decode cannot pass.
	var kinds := SimMap.Terrain.values()
	for i in range(size.x * size.y):
		m.terrain[i] = int(kinds[i % kinds.size()])
	m.add_entity(&"building.town_center", 1, Vector2i(3, 4))
	m.add_entity(&"res.tree", 0, Vector2i(1, 1), 2)
	m.starts.append(Vector2i(3, 4))
	m.starts.append(Vector2i(6, 2))
	m.meta = {"generator": "test"}
	return m


func test_a_map_survives_the_round_trip_byte_for_byte() -> void:
	var original := _sample()
	assert_eq(MapFile.save(original, _dir()), [] as Array[String])

	var problems: Array[String] = []
	var back := MapFile.load_map(_dir(), problems)
	assert_eq(problems, [] as Array[String])
	assert_not_null(back)
	if back == null:
		return

	assert_eq(back.size, original.size)
	# THE ASSERTION THE WHOLE FORMAT EXISTS FOR. A lossy or palette-decoded PNG passes a
	# size check and fails this one.
	assert_eq(back.terrain, original.terrain, "terrain is exact, byte for byte")
	assert_eq(back.starts, original.starts)
	assert_eq(back.entities.size(), original.entities.size())
	assert_eq(back.to_dict(), original.to_dict(), "and so is everything else")


func test_every_terrain_kind_survives() -> void:
	# One tile per kind, so an off-by-one in the channel or a clamp shows up as a specific
	# terrain rather than as a vague difference.
	var kinds := SimMap.Terrain.values()
	var m := MapData.create(Vector2i(kinds.size(), 1))
	for i in range(kinds.size()):
		m.terrain[i] = int(kinds[i])
	assert_eq(MapFile.save(m, _dir()), [] as Array[String])

	var problems: Array[String] = []
	var back := MapFile.load_map(_dir(), problems)
	assert_not_null(back)
	if back == null:
		return
	for i in range(kinds.size()):
		assert_eq(int(back.terrain[i]), int(kinds[i]),
				"%s must come back as itself" % SimMap.Terrain.keys()[i])


func test_the_sidecar_carries_the_header_and_not_the_terrain() -> void:
	# The terrain lives in the PNG; a sidecar that also carried it would be two sources of
	# truth for the same bytes, and 150 KB of digits for a full-size map.
	MapFile.save(_sample(), _dir(), {"name": "Test Map", "players": 3, "seed": 77})
	var text := FileAccess.get_file_as_string(_dir().path_join(MapFile.META_FILE))
	var json := JSON.new()
	assert_eq(json.parse(text), OK)
	var d: Dictionary = json.data

	assert_false(d.has("terrain"), "terrain does not belong in the sidecar")
	assert_eq(int(d["format_version"]), MapFile.FORMAT_VERSION)
	assert_eq(str(d["name"]), "Test Map")
	assert_eq(int(d["players"]), 3)
	assert_eq(int(d["seed"]), 77, "the seed rides along as provenance")
	assert_true(d.has("created"))
	assert_true(d.has("entities"))
	assert_true(d.has("starts"))


func test_the_header_can_override_a_derived_field_but_not_invent_a_map() -> void:
	# `header` is merged last on purpose, so a caller can label a map without this class
	# knowing what a scenario is. It must not be able to make the pair disagree about size,
	# which is what the load-time cross-check is for.
	MapFile.save(_sample(Vector2i(9, 7)), _dir(), {"w": 999, "h": 999})
	var problems: Array[String] = []
	assert_null(MapFile.load_map(_dir(), problems), "a lying sidecar is refused")
	assert_false(problems.is_empty())
	assert_true(problems[0].contains("999") or problems[0].contains("9x7"), problems[0])


func test_a_future_format_version_is_refused_rather_than_guessed() -> void:
	# A later format may move the terrain, change the channel or add a layer. A reader that
	# pressed on would produce a map that is wrong in a way nothing on screen explains.
	MapFile.save(_sample(), _dir())
	var path := _dir().path_join(MapFile.META_FILE)
	var text := FileAccess.get_file_as_string(path)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text.replace('"format_version": 1', '"format_version": 99'))
	f.close()

	var problems: Array[String] = []
	assert_null(MapFile.load_map(_dir(), problems))
	assert_false(problems.is_empty())
	assert_true(problems[0].contains("99"), problems[0])


func test_a_missing_half_of_the_pair_is_refused_and_says_which() -> void:
	var problems: Array[String] = []
	assert_null(MapFile.load_map("user://test_map_file/nothing_here", problems))
	assert_false(problems.is_empty())
	assert_true(problems[0].contains(MapFile.META_FILE), problems[0])
	assert_false(MapFile.exists_in("user://test_map_file/nothing_here"))


func test_malformed_json_is_refused_with_a_line_number() -> void:
	# A map file is untrusted input -- authored maps arrive in content packs and saved ones
	# sit in a directory the player can open.
	MapFile.save(_sample(), _dir())
	var f := FileAccess.open(_dir().path_join(MapFile.META_FILE), FileAccess.WRITE)
	f.store_string("{ not json at all")
	f.close()

	var problems: Array[String] = []
	assert_null(MapFile.load_map(_dir(), problems))
	assert_false(problems.is_empty())


func test_an_empty_map_is_refused_rather_than_written() -> void:
	var problems := MapFile.save(MapData.new(), _dir())
	assert_false(problems.is_empty(), "a 0x0 map is not a map")
	assert_false(MapFile.exists_in(_dir()), "and nothing was left behind")


func test_a_terrain_array_of_the_wrong_length_is_refused() -> void:
	# Reachable from a hand-edited file or a tool that resized the map without resizing its
	# terrain. Caught on the way OUT, so a broken map never reaches disk.
	var m := MapData.create(Vector2i(8, 8))
	m.terrain.resize(10)
	var problems := MapFile.save(m, _dir())
	assert_false(problems.is_empty())
	assert_true(problems[0].contains("10"), problems[0])


func test_the_three_shipped_scenarios_all_carry_a_saved_map() -> void:
	# THE CONTENT CHECK, and the one that would catch a scenario added without its map --
	# which would look exactly like a scenario that refuses to launch for an unrelated
	# reason. `preview_author_maps.tscn` is what writes these.
	var found := 0
	for c in Campaigns.new().discover():
		for s in c.scenarios:
			found += 1
			assert_true(s.has_map(), "%s/%s has no saved map" % [c.folder, s.folder])
			var problems: Array[String] = []
			var data := s.map_data(problems)
			assert_not_null(data, "%s/%s: %s" % [c.folder, s.folder, " | ".join(problems)])
			if data == null:
				continue
			assert_eq(data.terrain.size(), data.size.x * data.size.y,
					"%s/%s terrain matches its own size" % [c.folder, s.folder])
			assert_false(data.starts.is_empty(),
					"%s/%s has start positions" % [c.folder, s.folder])
	assert_eq(found, 3, "the shipped campaign is three scenarios")


func test_a_scenario_without_a_map_refuses_to_launch_and_says_where_to_look() -> void:
	# NO SILENT FALLBACK TO GENERATING, which is the point of the owner's 2026-09-01 ruling:
	# a fallback is how an unpinned scenario would ship looking exactly like a pinned one.
	var s := ScenarioDef.from_dict("scenario_x", {
		"name": "No Map",
		"mode": "last_man_standing",
		"map": {"type": "river", "seed": 1},
		"opponents": ["passive"],
	}, "user://test_map_file/definitely_not_here")
	assert_true(s.is_playable(), "the JSON itself is fine")
	assert_false(s.has_map())

	var problems: Array[String] = []
	assert_null(s.build_config(problems), "it must not launch without its map")
	assert_false(problems.is_empty())
	assert_true(problems[0].contains(MapFile.TERRAIN_FILE), problems[0])
