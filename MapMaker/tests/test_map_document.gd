## PLAN.md 16.2: the document every mutation funnels through, and the start layout.
##
## **THE ASSERTIONS THAT MATTER ARE ABOUT WHAT THE GAME WILL DO WITH THE RESULT**, not about
## the editor. A map this tool calls fine and the game refuses to seat, or seats and gives a
## player nothing, is the failure the whole phase is arranged to avoid — so `seats()` is
## checked against the same arithmetic 16.0's `can_start()` enforces, and the start layout is
## checked against what `MapGen.build_from()` actually spawns.
##
## Saving happens under `user://`, never into repo-root `maps/`: the authored maps there are
## content under version control and a test that wrote into them would be a test that edits
## the game. Same rule as `test_map_file` on the game side.
extends TestCase

const SCRATCH := "user://test_map_document"

var _n := 0
var doc: MapDocument = null


func before_each() -> void:
	_n += 1
	GameDataRegistry.load_from(GameRoot.resolve())
	doc = MapDocument.create(Vector2i(96, 96), "Test Map")


func _dir() -> String:
	return ProjectSettings.globalize_path("%s/case_%d" % [SCRATCH, _n])


# ── painting ────────────────────────────────────────────────────────────────

func test_painting_changes_the_tile() -> void:
	assert_true(doc.paint(Vector2i(4, 5), SimMap.Terrain.WATER_DEEP))
	assert_eq(doc.data.terrain_at(Vector2i(4, 5)), SimMap.Terrain.WATER_DEEP)


## ⚠️ **THE RETURN VALUE IS LOAD-BEARING, NOT A COURTESY.** A drag delivers the same tile
## dozens of times, so without this the canvas would redraw on every mouse-move and 16.2a's
## undo stack would fill with thousands of no-op entries for one stroke.
func test_repainting_the_same_kind_reports_no_change() -> void:
	assert_true(doc.paint(Vector2i(4, 5), SimMap.Terrain.SAND))
	assert_false(doc.paint(Vector2i(4, 5), SimMap.Terrain.SAND),
			"the second call changed nothing and must say so")


func test_painting_off_the_map_is_refused_rather_than_wrapping() -> void:
	assert_false(doc.paint(Vector2i(-1, 0), SimMap.Terrain.SAND))
	assert_false(doc.paint(Vector2i(96, 0), SimMap.Terrain.SAND))
	assert_false(doc.paint(Vector2i(0, 999), SimMap.Terrain.SAND))


func test_a_new_map_is_dirty_because_it_is_nowhere_on_disk() -> void:
	assert_true(doc.dirty)
	assert_eq(doc.dir, "")


func test_a_size_outside_the_limits_is_clamped_not_refused() -> void:
	var tiny := MapDocument.create(Vector2i(2, 2), "Tiny")
	assert_eq(tiny.data.size, Vector2i(MapDocument.MIN_SIZE, MapDocument.MIN_SIZE))
	var huge := MapDocument.create(Vector2i(9999, 9999), "Huge")
	assert_eq(huge.data.size, Vector2i(MapDocument.MAX_SIZE, MapDocument.MAX_SIZE))


# ── starts, and the base behind them ────────────────────────────────────────

## ⚠️ **A START MARKER ON ITS OWN AUTHORS A PLAYER WHO OWNS NOTHING.**
## `MapGen.build_from()` gives a player their town centre and units purely from the entities
## the map LISTS for their index — it never derives a base from a start. So placing a start
## must place a base, and this is the assertion that says so.
func test_placing_a_start_places_the_base_too() -> void:
	assert_true(doc.place_start(1, Vector2i(30, 30)))
	assert_eq(doc.data.starts.size(), 1)
	assert_eq(doc.data.starts[0], Vector2i(30, 30))

	var town_centres := 0
	var units := 0
	for e in doc.data.entities:
		if int(e["player"]) != 1:
			continue
		if e["def_id"] == StartLayout.TOWN_CENTRE:
			town_centres += 1
		else:
			units += 1
	assert_eq(town_centres, 1, "exactly one town centre")
	assert_eq(units, StartLayout.VILLAGERS + 1, "five villagers and a scout")


## The town centre's ORIGIN is `centre - footprint / 2`, matching
## `MapGenerator._place_base()`. Getting this wrong by half a footprint puts the base five
## tiles from where the author clicked, which reads as the click being inaccurate.
func test_the_town_centre_is_centred_on_the_start() -> void:
	var centre := Vector2i(40, 40)
	doc.place_start(1, centre)
	var footprint := GameDataRegistry.building(StartLayout.TOWN_CENTRE).footprint
	for e in doc.data.entities:
		if e["def_id"] == StartLayout.TOWN_CENTRE:
			assert_eq(e["tile"], centre - footprint / 2)
			return
	fail("no town centre placed")


## The footprint is READ FROM THE ROSTER, never assumed -- the game's own note records the
## prototype reserving 5x5 for a building that is 10x10 in the data.
func test_the_footprint_comes_from_the_roster() -> void:
	doc.place_start(1, Vector2i(40, 40))
	var footprint := GameDataRegistry.building(StartLayout.TOWN_CENTRE).footprint
	var claimed := 0
	for e in doc.data.entities:
		if e["def_id"] == StartLayout.TOWN_CENTRE:
			claimed = MapData.footprint_rect_of(e).size()
	assert_eq(claimed, footprint.x * footprint.y)


## An opening with no economy is a map you cannot age up on, so the start brings one.
## Provisional numbers -- see `StartLayout._ECONOMY` -- so this asserts the KINDS, which are
## the four the game's generator guarantees, rather than the counts.
func test_a_start_comes_with_all_four_resource_kinds() -> void:
	doc.place_start(1, Vector2i(48, 48))
	var kinds: Dictionary = {}
	for e in doc.data.entities:
		if int(e["player"]) == 0:
			kinds[e["def_id"]] = true
	for wanted in [&"res.berry_bush", &"res.tree", &"res.gold_mine", &"res.stone"]:
		assert_true(kinds.has(wanted), "a start needs %s within reach" % wanted)


## Nothing is authored standing in water. `is_ground_passable` is asked of `MapData`, which
## asks `SimMap`'s own tables, so the tool cannot disagree with the grid the map becomes.
func test_nothing_is_placed_on_impassable_ground() -> void:
	doc.fill_all(SimMap.Terrain.WATER_DEEP)
	# One island, big enough for a base and its ring.
	for y in range(30, 60):
		for x in range(30, 60):
			doc.paint(Vector2i(x, y), SimMap.Terrain.GRASS)
	doc.place_start(1, Vector2i(45, 45))
	for e in doc.data.entities:
		# Buildings are forced by the map (`build_from` spawns them with `forced = true`), so
		# the rule under test is about UNITS, which have to stand somewhere walkable.
		if GameDataRegistry.building(e["def_id"]) != null:
			continue
		if GameDataRegistry.resource_def(e["def_id"]) != null:
			continue
		assert_true(doc.data.is_ground_passable(e["tile"]),
				"%s at %s is in the water" % [e["def_id"], e["tile"]])


## ⚠️ **THE TEST THAT FOUND MOVING A START LITTERS THE MAP.** Removing by owner alone left
## the first cluster behind — every resource node is gaia, so the owner cannot find them —
## and the count went 24 → 40. With no delete tool in 16.2, a mis-clicked start was permanent
## litter. `StartLayout.ORIGIN_KEY` is the fix.
func test_placing_a_start_twice_replaces_rather_than_doubles_it() -> void:
	doc.place_start(1, Vector2i(30, 30))
	var first := doc.data.entities.size()
	doc.place_start(1, Vector2i(60, 60))
	assert_eq(doc.data.entities.size(), first, "the second placement replaced the first")
	assert_eq(doc.data.starts[0], Vector2i(60, 60))
	# And it moved: nothing is left near where the first start was.
	for e in doc.data.entities:
		assert_true((Vector2(e["tile"]) - Vector2(30, 30)).length() > 8.0,
				"%s at %s is left over from the first placement" % [e["def_id"], e["tile"]])


## The tag is **session-only editing metadata** and `MapFile` drops it, because
## `MapData.to_dict()` writes exactly `def_id`, `player`, `x`, `y` and `size_class`. Pinned
## rather than assumed: silently-lost state is a trap, so the fact that it is lost — and that
## nothing in the format changes because of it — is asserted.
func test_the_start_tag_is_editing_metadata_and_never_reaches_the_file() -> void:
	doc.place_start(1, Vector2i(30, 30))
	var tagged := 0
	for e in doc.data.entities:
		if e.has(StartLayout.ORIGIN_KEY):
			tagged += 1
	assert_true(tagged > 0, "the placement tags what it placed")

	assert_eq(doc.save(_dir()), [] as Array[String])
	var problems: Array[String] = []
	var back := MapFile.load_map(doc.dir, problems)
	assert_not_null(back)
	if back == null:
		return
	for e in back.entities:
		assert_false(e.has(StartLayout.ORIGIN_KEY),
				"the tag must not ride into the saved format")
	# The map itself is unchanged by the tag's absence, which is the point.
	assert_eq(back.entities.size(), doc.data.entities.size())


## Cleared BY OWNER, not by proximity: sweeping "what is near the start" would also take the
## gaia trees an author had put there on purpose.
func test_clearing_a_start_takes_that_players_things_and_nobody_elses() -> void:
	doc.place_start(1, Vector2i(30, 30))
	doc.place_start(2, Vector2i(70, 70))
	doc.remove_start(1)
	for e in doc.data.entities:
		assert_ne(int(e["player"]), 1, "player 1 has nothing left")
	var p2 := 0
	for e in doc.data.entities:
		if int(e["player"]) == 2:
			p2 += 1
	assert_eq(p2, StartLayout.VILLAGERS + 2, "player 2 keeps their base and units")


## A trailing placeholder would make `player_count()` -- which IS `starts.size()` -- count a
## slot nobody is in, so the lobby would offer a seat that leads nowhere.
func test_clearing_the_last_start_shortens_the_list() -> void:
	doc.place_start(1, Vector2i(30, 30))
	doc.place_start(2, Vector2i(70, 70))
	assert_eq(doc.data.starts.size(), 2)
	doc.remove_start(2)
	assert_eq(doc.data.starts.size(), 1, "no placeholder left on the end")


# ── seats: the number the lobby enforces ────────────────────────────────────

func test_seats_counts_players_who_have_both_a_start_and_a_base() -> void:
	assert_eq(doc.seats(), 0, "an empty map seats nobody")
	doc.place_start(1, Vector2i(30, 30))
	assert_eq(doc.seats(), 1)
	doc.place_start(2, Vector2i(70, 70))
	assert_eq(doc.seats(), 2)


## ⚠️ **THIS IS THE ARITHMETIC 16.0's RULE 7 ENFORCES**, duplicated here on purpose because
## the two projects cannot call each other -- so the number the tool shows is the number the
## lobby will allow. The test that keeps them honest is
## `test_the_authored_map_seats_what_the_game_thinks_it_does`.
func test_a_start_with_its_base_deleted_stops_counting_as_a_seat() -> void:
	doc.place_start(1, Vector2i(30, 30))
	doc.place_start(2, Vector2i(70, 70))
	# Reach past the document to strip player 2's entities without clearing their start --
	# which is the state 16.4's move cursor will be able to create for real.
	var kept: Array[Dictionary] = []
	for e in doc.data.entities:
		if int(e.get("player", 0)) != 2:
			kept.append(e)
	doc.data.entities = kept
	assert_eq(doc.seats(), 1, "a start with nothing behind it is not a seat")


# ── saving ──────────────────────────────────────────────────────────────────

func test_saving_writes_a_map_the_game_can_read_back() -> void:
	doc.place_start(1, Vector2i(30, 30))
	doc.place_start(2, Vector2i(70, 70))
	doc.paint(Vector2i(50, 50), SimMap.Terrain.WATER_DEEP)
	var problems := doc.save(_dir())
	assert_eq(problems, [] as Array[String])
	assert_false(doc.dirty, "saving clears the flag")
	assert_ne(doc.dir, "")

	var read_problems: Array[String] = []
	var back := MapFile.load_map(doc.dir, read_problems)
	assert_eq(read_problems, [] as Array[String])
	assert_not_null(back)
	if back == null:
		return
	# THE ASSERTION THE FORMAT EXISTS FOR, on the tool's side of the fence this time.
	assert_eq(back.terrain, doc.data.terrain)
	assert_eq(back.starts, doc.data.starts)
	assert_eq(back.entities.size(), doc.data.entities.size())


## The sidecar's `players` is what 16.0's picker labels its rows from, so it has to be the
## seat count and not the number of starts dropped.
func test_the_sidecar_records_the_seat_count() -> void:
	doc.place_start(1, Vector2i(30, 30))
	doc.place_start(2, Vector2i(70, 70))
	assert_eq(doc.save(_dir()), [] as Array[String])
	var problems: Array[String] = []
	var header := MapFile.read_header(doc.dir, problems)
	assert_eq(int(header.get("players", -1)), 2)
	assert_eq(str(header.get("name", "")), "Test Map")


func test_saving_twice_writes_to_the_same_directory() -> void:
	doc.place_start(1, Vector2i(30, 30))
	assert_eq(doc.save(_dir()), [] as Array[String])
	var first := doc.dir
	doc.paint(Vector2i(1, 1), SimMap.Terrain.ROCK)
	assert_eq(doc.save(_dir()), [] as Array[String])
	assert_eq(doc.dir, first, "a re-save must not spawn a second folder")


func test_a_nameless_map_is_refused_with_a_reason() -> void:
	doc.map_name = ""
	var problems := doc.save(_dir())
	assert_eq(problems.size(), 1)
	assert_true(problems[0].contains("name"), problems[0])


## A PATH IS NOT A LABEL. The name is whatever the author types; a folder carrying it
## verbatim is a folder that breaks on one machine and not another.
func test_the_folder_name_is_a_slug_and_never_empty() -> void:
	doc.map_name = "The Owner's  RIVER map!! (v2)"
	assert_eq(doc.slug(), "the_owner_s_river_map_v2")
	doc.map_name = "!!!"
	assert_eq(doc.slug(), "untitled_map", "a name with nothing usable in it still saves")
