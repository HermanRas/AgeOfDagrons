## A cliff is a gaia building, and these are the claims that make that true (#97/#99).
##
## ## WHAT THIS FILE IS ACTUALLY GUARDING, AND IT IS NOT THE DEFS
##
## Ten rows in buildings.json are cheap to write and cheap to read. What is expensive is
## everything those rows QUIETLY DEPEND ON, and every one of it is a claim made in a comment
## somewhere and enforced by nothing:
##
##   - a gaia BUILDING cannot be attacked, which is the whole of "unkillable"
##   - `blocks_movement` stops land and does not stop the dragon
##   - the sim facings resolve to the stored frames the art side MEASURED, through a
##     conversion that runs the opposite way and has already been misread twice
##   - a def that declares no `facings` still gets `WallPlan.FACING_FOR_AXIS`, so twelve
##     wall defs and six committed maps are untouched
##
## ⚠️ **THE FACING ONE IS THE ONE THAT WOULD SHIP.** `Iso.sim_facing_to_sprite` is
## `posmod(7 - f, 8)`, so a table written in sprite order and read as sim facings is wrong
## in a way that looks right: the cliff still stands, still blocks, still hashes the same,
## and draws the frame for a different edge. That is the identical failure `test_wall_facing`
## exists for -- ninety degrees on a symmetric object, found by the owner six days later --
## except a cliff is NOT symmetric, so it is worse: a face frame on a far edge hangs
## backwards into the plateau it belongs to.
extends TestCase

## The axis families and the stored frames the art side measured for each, by composing a
## whole plateau on a real boundary rather than by deriving anything.
##
##     the tile's LOW neighbour          piece                 stored
##     (0, +1) +y                        vis.cliff_face          5
##     (+1, 0) +x                        vis.cliff_face          3
##     (0, -1) -y                        vis.cliff_back          1
##     (-1, 0) -x                        vis.cliff_back          7
##     the E-W notch and the corner      vis.cliff_*_diag        4
const FACE_STORED := {WallPlan.AXIS_X: 5, WallPlan.AXIS_Y: 3}
const BACK_STORED := {WallPlan.AXIS_X: 1, WallPlan.AXIS_Y: 7}
const DIAG_STORED := 4

const FACE_DEFS := [
	&"building.cliff_face", &"building.cliff_face_short",
	&"building.cliff_face_medium", &"building.cliff_face_long",
]
const BACK_DEFS := [
	&"building.cliff_back", &"building.cliff_back_short",
	&"building.cliff_back_medium", &"building.cliff_back_long",
]
const DIAG_DEFS := [&"building.cliff_face_diag", &"building.cliff_back_diag"]

## The long diagonal pieces, which are ART ONLY: `blocks_movement` false, footprint [1, 1].
## A run's ground is claimed by `BLOCKER` instead, one per tile. See `_note_cliff_diag_runs`.
const DIAG_RUN_DEFS := [
	&"building.cliff_face_diag_short", &"building.cliff_face_diag_long",
	&"building.cliff_back_diag_short", &"building.cliff_back_diag_long",
]

const BLOCKER := &"building.cliff_blocker"

## Every atlas the art side staged, including the six that deliberately have no def.
const ALL_VISUALS := [
	&"vis.cliff_face", &"vis.cliff_face_short", &"vis.cliff_face_medium",
	&"vis.cliff_face_long",
	&"vis.cliff_back", &"vis.cliff_back_short", &"vis.cliff_back_medium",
	&"vis.cliff_back_long",
	&"vis.cliff_face_diag", &"vis.cliff_face_diag_short",
	&"vis.cliff_face_diag_medium", &"vis.cliff_face_diag_long",
	&"vis.cliff_back_diag", &"vis.cliff_back_diag_short",
	&"vis.cliff_back_diag_medium", &"vis.cliff_back_diag_long",
]


## The pieces that both DRAW and BLOCK, which was every cliff until the long diagonals
## landed. Most claims below are about these and would be false of the other two kinds.
func _defs() -> Array:
	return FACE_DEFS + BACK_DEFS + DIAG_DEFS


## Every cliff def of any kind: the ones that draw and block, the long diagonals that only
## draw, and the blocker that only blocks.
func _all_defs() -> Array:
	return _defs() + DIAG_RUN_DEFS + [BLOCKER]


# ── the shape of a gaia cliff ───────────────────────────────────────────────


func test_every_cliff_piece_is_declared() -> void:
	for id in _all_defs():
		assert_not_null(GameDataRegistry.building(id), "%s is in buildings.json" % id)


func test_a_cliff_is_placed_by_a_map_and_never_by_a_player() -> void:
	for id in _all_defs():
		var bd: BuildingDef = GameDataRegistry.building(id)
		assert_false(bd.buildable, "%s is never offered in the build menu" % id)
		assert_true(bd.cost.is_empty(), "%s costs nothing -- nobody buys one" % id)
		assert_eq(bd.build_time_ticks, 0, "%s is placed complete" % id)
		# NOT a wall run. `wall_lengths` is what turns a def into a DRAG TOOL, and a cliff
		# sharing the wall's 1/3/6/9 ladder must not be mistaken for sharing that.
		assert_false(bd.is_wall_run(), "%s is not a drag tool" % id)


func test_a_cliff_blocks_and_has_nothing_to_say() -> void:
	for id in _all_defs():
		var bd: BuildingDef = GameDataRegistry.building(id)
		assert_false(bd.selectable, "%s cannot be tapped -- it has no panel" % id)
		assert_eq(bd.los, 0, "%s gives nobody vision" % id)
		assert_false(bd.leaves_rubble, "%s leaves no wreckage" % id)

	# ⛔ **BLOCKING IS NOW A PROPERTY OF THE KIND, NOT OF BEING A CLIFF**, and asserting it
	# of every cliff is what this test used to do. A long diagonal draws a run it does not
	# own: its footprint is the [1, 1] anchor, so claiming the ground would mean claiming
	# the NxN box around a 1-tile line. Split rather than dropped, because "the art piece
	# blocks nothing" is the half that is easy to lose and expensive to notice -- a run
	# that blocked from its anchor would look right and let units walk through the rock.
	for id in _defs():
		assert_true(GameDataRegistry.building(id).blocks_movement,
				"%s draws its own tile, so it blocks it" % id)
	for id in DIAG_RUN_DEFS:
		assert_false(GameDataRegistry.building(id).blocks_movement,
				"%s is art over ground it does not own" % id)
	assert_true(GameDataRegistry.building(BLOCKER).blocks_movement,
			"the blocker is the half that does own it")


## ⛔ THE WHOLE OF "UNKILLABLE", AND IT IS NOT A FLAG ANYWHERE.
##
## The owner asked for a cliff that cannot be killed and the answer was that gaia already
## works that way -- `Diplomacy.is_enemy` returns `e is SimUnit` for owner 0, so a gaia
## BUILDING is never a legal target for an attack order, a tower, or a dragon's blast.
## There is no `invulnerable` field to read, so the only honest way to assert it is to ask
## the rule, for a real cliff, from a real player.
func test_a_cliff_cannot_be_attacked_by_anybody() -> void:
	var w := SimWorld.new()
	w.setup(MatchConfig.debug_skirmish())
	var cliff := w.spawn_building(&"building.cliff_face_long", 0, Vector2i(10, 10),
			SimBuilding.Phase.COMPLETE, true)
	assert_not_null(cliff)
	for player in [1, 2]:
		assert_false(Diplomacy.is_enemy(cliff, player, w.teams),
				"player %d cannot target a cliff" % player)


# ── the facings, which is the part that would ship wrong ────────────────────


func test_the_axis_pieces_resolve_to_the_frames_the_art_side_measured() -> void:
	for id in FACE_DEFS:
		var bd: BuildingDef = GameDataRegistry.building(id)
		for axis in FACE_STORED:
			assert_eq(Iso.sim_facing_to_sprite(bd.facing_for(axis)), int(FACE_STORED[axis]),
					"%s on axis %d draws stored %d" % [id, axis, FACE_STORED[axis]])
	for id in BACK_DEFS:
		var bd: BuildingDef = GameDataRegistry.building(id)
		for axis in BACK_STORED:
			assert_eq(Iso.sim_facing_to_sprite(bd.facing_for(axis)), int(BACK_STORED[axis]),
					"%s on axis %d draws stored %d" % [id, axis, BACK_STORED[axis]])


## The diagonal piece has exactly one usable frame, so every axis has to reach it.
##
## It is a quad through the notch tile's top vertex and there is nothing to turn: the other
## seven frames of that atlas are the same geometry pointed at nothing the camera can see.
func test_a_diagonal_piece_draws_the_same_frame_whichever_axis_it_is_laid_on() -> void:
	for id in DIAG_DEFS + DIAG_RUN_DEFS:
		var bd: BuildingDef = GameDataRegistry.building(id)
		for axis in [WallPlan.AXIS_X, WallPlan.AXIS_Y, WallPlan.AXIS_D1, WallPlan.AXIS_D2]:
			assert_true(bd.can_face(axis), "%s can be laid on axis %d" % [id, axis])
			assert_eq(Iso.sim_facing_to_sprite(bd.facing_for(axis)), DIAG_STORED,
					"%s on axis %d still draws stored %d" % [id, axis, DIAG_STORED])


## ⛔ THE CLAIM THAT MAKES THIS CHANGE FREE FOR EVERYTHING THAT ALREADY EXISTS.
##
## Twelve wall defs, six committed maps and every `PlaceWallCommand` read
## `WallPlan.FACING_FOR_AXIS`, and they go on reading it because an empty `facings` is what
## they all have. If this ever fails, every wall on every saved map has turned.
func test_a_def_that_declares_no_facings_still_gets_the_wall_table() -> void:
	var wall: BuildingDef = GameDataRegistry.building(&"building.wall_stone_long")
	assert_not_null(wall)
	assert_true(wall.facings.is_empty(), "a wall declares no facings of its own")
	for axis in range(WallPlan.FACING_FOR_AXIS.size()):
		assert_eq(wall.facing_for(axis), int(WallPlan.FACING_FOR_AXIS[axis]),
				"a wall on axis %d is unchanged" % axis)


## ⚠️ AN ABSENT KEY IS A REAL ANSWER, which is why `facings` is a Dictionary.
##
## There is no north-south cliff face and there cannot be one -- that face's normal is
## perpendicular to the view direction, so it is invisible at any span -- and the axis
## families have nothing for a diagonal either. A four-entry list would have had to hold
## SOMETHING in those slots.
func test_an_axis_piece_says_it_has_no_art_for_a_diagonal() -> void:
	for id in FACE_DEFS + BACK_DEFS:
		var bd: BuildingDef = GameDataRegistry.building(id)
		assert_true(bd.can_face(WallPlan.AXIS_X), "%s draws on axis X" % id)
		assert_true(bd.can_face(WallPlan.AXIS_Y), "%s draws on axis Y" % id)
		assert_false(bd.can_face(WallPlan.AXIS_D1), "%s has no D1 art" % id)
		assert_false(bd.can_face(WallPlan.AXIS_D2), "%s has no D2 art" % id)


## And asking for one anyway is answered rather than crashed, because `facing_for` runs
## inside `MapGen.build_from` where a refusal would take the whole match down over one bad
## entity. Deterministic, so two hosts building the same bad map still build one world.
func test_an_impossible_axis_falls_back_instead_of_failing() -> void:
	var bd: BuildingDef = GameDataRegistry.building(&"building.cliff_face_short")
	var first := bd.facing_for(WallPlan.AXIS_D1)
	assert_eq(first, bd.facing_for(WallPlan.AXIS_D1), "the same answer twice")
	assert_eq(first, bd.facing_for(WallPlan.AXIS_X), "it falls back to the lowest declared")


# ── the footprint ───────────────────────────────────────────────────────────


## ⛔ THE FACE CLAIMS THE GROUND ITS ART IS PAINTED ON, AND FOR A DAY IT DID NOT.
##
## The owner walked a villager into the middle of a cliff on 2026-09-22 and reported it as a
## collision bug. Per-tile collision was already exact -- every claimed tile blocked -- and
## the fault was that the piece claimed ONE row while its rock covers three. A cliff is a
## flat drop-in with no top quad, so the face hangs entirely outside its own cell and the
## tiles it is painted over were ordinary walkable ground.
##
## ⚠️ **THREE IS MEASURED, NOT PICKED.** `vis.cliff_face` stored 5 is a 52x126 frame whose
## anchor sits 16 px down, so 110 px of art hangs below where the piece stands; one (+1, +1)
## tile step is 32 px down the screen, so the rock covers 110 / 32 = 3.4 tiles.
##
## THE CREST STAYS ONE DEEP: a 1.88 m rim on a far edge, with no face to fall.
func test_the_face_claims_the_ground_its_rock_covers() -> void:
	for id in FACE_DEFS:
		var bd: BuildingDef = GameDataRegistry.building(id)
		assert_eq(bd.footprint.y, 3, "%s claims the lip and the two tiles of scree" % id)
	for id in BACK_DEFS:
		var bd: BuildingDef = GameDataRegistry.building(id)
		assert_eq(bd.footprint.y, 1, "%s is a rim and covers only its own tile" % id)
	assert_eq(int(GameDataRegistry.building(&"building.wall_stone_long").footprint.y),
			WallPlan.DEPTH, "a wall is still two, and is a different kind of object")


## ⛔ **THE WHOLE POINT OF THE LONG DIAGONALS, IN ONE NUMBER.** A 9-step run claims 9 tiles,
## not 81. The old arrangement gave the art a footprint and got the box around its line: 81
## tiles of which about 30 are rock, the rest two triangles -- 36 tiles of the plateau top
## behind the cliff and 15 of open ground past its base.
##
## ⚠️ **ASSERTED THROUGH `MapData.footprint_rect_of` RATHER THAN OFF `bd.footprint`.** That
## function is the rule the validator and `MapGen.build_from` both read, and reading the def
## directly would pass while the thing that actually claims ground still squared the run --
## which is precisely the failure this arrangement exists to prevent.
func test_a_long_diagonal_claims_its_line_and_not_the_square_around_it() -> void:
	var art := MapData.footprint_rect_of({
		"def_id": &"building.cliff_face_diag_long", "tile": Vector2i(10, 20),
		"axis": WallPlan.AXIS_D2})
	assert_eq(art.size(), 1, "the art owns its anchor tile and nothing else")

	# The run the art is drawn over, laid the way a map lays it: one blocker a tile.
	var claimed: Dictionary = {}
	for step in range(9):
		var t := Vector2i(10 + step, 20 - step)
		for tile in MapData.footprint_rect_of({"def_id": BLOCKER, "tile": t}):
			claimed[tile] = true
	assert_eq(claimed.size(), 9, "nine tiles for a nine-step run, one deep")
	assert_true(claimed.has(Vector2i(10, 20)), "it starts where the art is anchored")
	assert_true(claimed.has(Vector2i(18, 12)), "and reaches the far end of the run")
	# The two corners of the box that used to be claimed and are the reason this changed:
	# one is the plateau top behind the cliff, the other open ground past its base.
	assert_false(claimed.has(Vector2i(10, 12)), "nothing taken on the high side")
	assert_false(claimed.has(Vector2i(18, 20)), "nothing taken out past the base")


## ⛔ **`set_occupied` ASSIGNS THE BLOCKING BYTE, IT DOES NOT MERGE INTO IT** -- so a
## non-blocking cliff spawned onto a tile a blocker already holds OPENS that tile.
##
## This is the whole risk the two-entity arrangement takes on, and it is invisible: the run
## still reports every piece standing, the art still draws, and a single tile at the middle
## of the wall -- the one the art is anchored on -- is walkable. `_check_world` in
## `preview_cliff_variants` caught it by naming both entities on the tile, and the fix is
## that a run lays its ART FIRST and its blockers after.
##
## Asserted against `SimMap` rather than against the preview, because this is a property of
## the occupancy grid and would be just as true of any other pair of entities sharing a tile.
func test_a_later_non_blocking_claim_clears_an_earlier_blocking_one() -> void:
	var m := SimMap.create(Vector2i(8, 8), SimMap.Terrain.GRASS)
	var one := Rect2i(3, 3, 1, 1)

	m.set_occupied(one, 11, true)
	assert_false(m.is_passable(Vector2i(3, 3), SimMap.Domain.LAND),
			"the blocker holds the tile")

	m.set_occupied(one, 12, false)
	assert_true(m.is_passable(Vector2i(3, 3), SimMap.Domain.LAND),
			"and art landing on top of it opens the tile again -- assignment, not a merge")

	# The order a run actually uses, which is the other way round and holds.
	m.set_occupied(one, 13, false)
	m.set_occupied(one, 14, true)
	assert_false(m.is_passable(Vector2i(3, 3), SimMap.Domain.LAND),
			"art first, blocker second: the tile stays shut")


func test_the_axis_ladder_is_the_walls_ladder_plus_a_filler() -> void:
	var lengths: Array[int] = []
	for id in FACE_DEFS:
		lengths.append(int(GameDataRegistry.building(id).footprint.x))
	lengths.sort()
	assert_eq(lengths, [1, 3, 6, 9] as Array[int],
			"1 is the filler that lets a run of any length close; 3/6/9 are the wall's")


## The transposition is `MapData.footprint_rect_of`'s, asked of a cliff rather than a wall,
## because it is the one rule the validator and `build_from` both read and a cliff is the
## first def whose two sides are different lengths in a way an author can get backwards.
func test_a_cliff_laid_north_south_claims_a_transposed_footprint() -> void:
	var along_x := MapData.footprint_rect_of({
		"def_id": &"building.cliff_face_long", "tile": Vector2i(4, 4),
		"axis": WallPlan.AXIS_X})
	var along_y := MapData.footprint_rect_of({
		"def_id": &"building.cliff_face_long", "tile": Vector2i(4, 4),
		"axis": WallPlan.AXIS_Y})
	assert_eq(along_x.size(), 27, "nine long by three deep, either way")
	assert_eq(along_y.size(), 27)
	assert_true(along_x.has(Vector2i(12, 4)), "east-west reaches along x")
	assert_true(along_y.has(Vector2i(4, 12)), "north-south reaches along y")
	# ⚠️ AND THE DEPTH TRANSPOSES WITH IT, which is the half that would be missed: an
	# east-west face falls toward +y and a north-south one toward +x, so the three-tile
	# claim has to turn with the piece or it blocks the plateau instead of the scree.
	assert_true(along_x.has(Vector2i(4, 6)), "east-west claims two tiles toward +y")
	assert_true(along_y.has(Vector2i(6, 4)), "north-south claims two tiles toward +x")
	# ⛔ AND IT REACHES ONE WAY ONLY. The depth is scree in FRONT of the cliff; growing it
	# backwards as well would block the plateau the cliff belongs to.
	assert_false(along_x.has(Vector2i(4, 3)), "nothing is claimed behind an east-west face")
	assert_false(along_y.has(Vector2i(3, 4)), "nor behind a north-south one")


## ⛔ TWO CLIFFS MAY SHARE A TILE AND NOTHING ELSE MAY (#97).
##
## A plateau is four edges that each want a whole number of one length PLUS a corner piece,
## which over-constrains one-entity-per-tile -- and the owner photographed what happens when
## the corner is given away instead: *"the east corner has a gap, i see single tile cliffs in
## that spot."* Safe for cliffs alone because a cliff never despawns, so nothing depends on
## which of the two ids the occupancy cell ends up holding, and both of them block.
func test_two_cliffs_may_stand_on_one_tile() -> void:
	var data := _bare_map()
	data.add_entity(&"building.cliff_face_short", 0, Vector2i(10, 10), 0, WallPlan.AXIS_X)
	data.add_entity(&"building.cliff_face_diag", 0, Vector2i(10, 10), 0, WallPlan.AXIS_X)
	assert_false(_mentions(MapValidator.problems(data), "overlap"),
			"a corner piece may sit on the end of a face run")


func test_a_cliff_sharing_with_an_ordinary_building_is_still_an_overlap() -> void:
	# The narrowing that keeps the rule above from being a hole: a house CAN be destroyed,
	# and despawning it would clear the occupancy cell the cliff was also relying on.
	var data := _bare_map()
	data.add_entity(&"building.cliff_face_short", 0, Vector2i(10, 10), 0, WallPlan.AXIS_X)
	data.add_entity(&"building.house", 1, Vector2i(10, 10))
	assert_true(_mentions(MapValidator.problems(data), "overlap"),
			"a house on a cliff is exactly as wrong as it ever was")


func test_two_cliffs_apart_from_each_other_are_not_reported_either() -> void:
	# The control for both: it proves the fixture is CLEAN, so that "no overlap" above is a
	# statement about the rule rather than about a validator that has stopped counting.
	var data := _bare_map()
	data.add_entity(&"building.cliff_face_short", 0, Vector2i(10, 10), 0, WallPlan.AXIS_X)
	data.add_entity(&"building.cliff_face_short", 0, Vector2i(20, 20), 0, WallPlan.AXIS_X)
	assert_false(_mentions(MapValidator.problems(data), "overlap"))


# ── the map ─────────────────────────────────────────────────────────────────


## ⛔ THE HALF THAT TURNS A SILENT WRONG FRAME INTO A SENTENCE SOMEBODY READS.
##
## `facing_for` falls back rather than failing, so a cliff face laid on a diagonal builds,
## blocks, and draws a frame that is merely wrong. Nothing crashes and nothing warns. This
## is the only place it is caught, and it is caught where there is an author in front of it.
func test_a_map_that_lays_a_cliff_on_an_axis_it_cannot_draw_is_refused() -> void:
	var data := _playable_map()
	data.add_entity(&"building.cliff_face_short", 0, Vector2i(30, 30), 0, WallPlan.AXIS_D1)
	var problems := MapValidator.problems(data)
	var named := false
	for p in problems:
		if p.contains("cliff_face_short") and p.contains("30,30"):
			named = true
	assert_true(named, "the complaint names the piece and the tile: %s" % str(problems))


## And the same map WITHOUT that entity carries no such complaint, so the test above is
## measuring the rule rather than measuring a map that was broken anyway.
##
## 📝 Asserted as "this complaint is absent" rather than "there are no problems at all",
## because the fixture is a GENERATED map and a generator that had a bad day would turn a
## test about one rule into a test about map generation.
func test_the_same_map_without_it_carries_no_such_complaint() -> void:
	assert_false(_mentions(MapValidator.problems(_playable_map()), "no art for"))


func test_a_wall_on_a_diagonal_is_still_perfectly_legal() -> void:
	var data := _playable_map()
	data.add_entity(&"building.wall_stone_short", 1, Vector2i(30, 30), 0, WallPlan.AXIS_D1)
	assert_false(_mentions(MapValidator.problems(data), "no art for"),
			"#98 built exactly this and it must not now be a map problem")


func _mentions(problems: Array[String], text: String) -> bool:
	for p in problems:
		if p.contains(text):
			return true
	return false


# ── the art is on disk ──────────────────────────────────────────────────────


## All sixteen, including the six with no building def.
##
## ⚠️ **TWO OF THE SIXTEEN STILL HAVE NO DEF, AND THE REASON CHANGED ON 2026-09-22.** It used
## to be all six diagonal lengths, because a diagonal segment claims a SQUARE of its own run.
## That is no longer how a run is built -- the art claims nothing and `cliff_blocker` claims
## the tiles -- so the 3 and the 9 now have defs.
##
## The two `_diag_medium` atlases remain defless for an unrelated reason that no footprint can
## fix: 386 px wide with the anchor at 193 puts it 160 px along a run whose tiles sit every
## 64 px, half a tile off the grid, because an EVEN-step run centres between tiles. Declaring
## them still keeps them in the art pack (`build_packs.py` resolves `base` out of visuals.json)
## so that a 32 px anchor shift is a rebake and not a rediscovery.
func test_every_cliff_atlas_resolves_to_real_art() -> void:
	for id in ALL_VISUALS:
		var entry: AtlasEntry = GameDataRegistry.atlas_for(id, 1)
		assert_not_null(entry, "%s is declared in visuals.json" % id)
		assert_false(entry.is_placeholder, "%s resolves to a staged atlas" % id)


## The frames the tables above index have to EXIST, which is a different question from the
## atlas resolving: a rebake at `directions = 1` would resolve perfectly and have one frame.
func test_the_frames_the_facing_tables_index_are_really_there() -> void:
	# `BLOCKER` is left out and cannot simply be added: it names no visual, so `atlas_for`
	# would hand back the magenta unknown and this would assert against that.
	for id in _defs() + DIAG_RUN_DEFS:
		var bd: BuildingDef = GameDataRegistry.building(id)
		var entry: AtlasEntry = GameDataRegistry.atlas_for(bd.visual, 1)
		assert_not_null(entry)
		for axis in bd.facings:
			var sprite := Iso.sim_facing_to_sprite(bd.facing_for(int(axis)))
			assert_false((entry.frame_at(&"static", sprite, 0) as Dictionary).is_empty(),
					"%s has a frame at stored %d" % [bd.visual, sprite])


# ── fixture ─────────────────────────────────────────────────────────────────


## The smallest map `MapValidator` calls playable: two starts that can reach each other and
## enough of each resource beside both. Generated rather than hand-built, because hand-built
## is how you get a fixture that agrees with the bug -- the tests above are about ONE added
## entity, so everything else has to be known good.
func _playable_map() -> MapData:
	return MapGenerator.generate(4242, MapGenerator.Type.RANDOM, 2, 2)


## Empty grass with two starts and NOTHING else on it, for the overlap rules.
##
## ⛔ **A GENERATED MAP IS THE WRONG FIXTURE FOR THIS AND IT COST A RED SUITE.** The overlap
## tests first used `_playable_map()`, and a generated 2-player board has a few hundred trees
## and rocks scattered over it -- so the tile the test dropped two cliffs on already had
## something standing there, and "the corner piece may share a tile" failed on an overlap
## with a tree. ⚠️ **The paired test passed at the same time and was equally wrong**: it
## asserted an overlap IS reported and would have got one from that tree whatever the rule
## did. A fixture with things in it cannot answer a question about what is in it.
##
## Two starts because `MapValidator.problems()` returns early below that; the connectivity
## and resource complaints that follow are expected here and are ignored -- every test using
## this looks for the word "overlap" rather than for an empty list.
func _bare_map() -> MapData:
	var data := MapData.create(Vector2i(40, 40), SimMap.Terrain.GRASS)
	data.starts.append(Vector2i(4, 4))
	data.starts.append(Vector2i(35, 35))
	return data

# ── the cover tables ────────────────────────────────────────────────────────


## The tiles one piece's art is drawn over, measured off the STAGED ATLAS and the real
## projection, exactly as `EntityView` places a frame.
func _measured_cover(def_id: StringName, axis: int) -> Array[Vector2i]:
	var bd: BuildingDef = GameDataRegistry.building(def_id)
	var vis := GameDataRegistry.atlas_for(bd.visual)
	var footprint := bd.footprint
	if WallPlan.is_diagonal(axis):
		var side := WallPlan.diagonal_step(footprint.x)
		footprint = Vector2i(side, side)
	elif axis == WallPlan.AXIS_Y:
		footprint = Vector2i(footprint.y, footprint.x)

	var origin := Vector2i(20, 20)
	# The anchor lands on the projected footprint CENTRE -- which is the premise three
	# hand-derivations of this got wrong, so it is spelt out rather than folded in.
	var at := Iso.sub_to_world(SimBuilding.centre_of(origin, footprint))
	var f := vis.frame_at(&"idle", Iso.sim_facing_to_sprite(int(bd.facings[axis])), 0)
	var rect: Rect2i = f["rect"]
	var box := Rect2(at - (f["anchor"] as Vector2), Vector2(rect.size))

	var out: Array[Vector2i] = []
	for dy in range(-6, 10):
		for dx in range(-6, 10):
			if box.has_point(Iso.tile_centre_to_world(origin + Vector2i(dx, dy))):
				out.append(Vector2i(dx, dy))
	out.sort()
	return out


## ⛔ REGRESSION, and the one that would have caught all three rounds of this.
##
## `CliffPlan` lays its blockers from a hand-written table of where a piece's rock falls, and
## that table was wrong three times running -- "3 tiles straight down", then the same again
## with the diagonals added, then an `AXIS_Y` band a tile off the rock it was meant to hold.
## ⚠️ **EVERY TIME, THE FIX, THE UNIT TEST AND THE PROBE SHARED THE PREMISE**, so all three
## agreed and the fault reached the owner, who rode a scout along it and photographed it.
##
## This asks the ART instead. Nothing here is derived from `COVER_FACE`: the frame comes from
## the staged atlas, the anchor from `SimBuilding.centre_of`, the placement from `Iso`, and a
## tile counts as covered when the point the sim stands a unit on lands inside the frame. A
## re-bake that moves an anchor fails this rather than shipping a walkable cliff.
func test_the_cover_tables_are_what_the_atlas_says() -> void:
	for axis in [WallPlan.AXIS_X, WallPlan.AXIS_Y]:
		var want := _measured_cover(CliffPlan.FACE[1], axis)
		var got := CliffPlan.rock_tiles(Vector2i.ZERO, axis, CliffPlan.FACE)
		got.sort()
		assert_eq(got, want, "cliff_face on axis %d covers %s, and COVER_FACE says %s"
				% [axis, want, got])

	# The diagonal draws one frame on every axis, so every axis must agree with it.
	for axis in [WallPlan.AXIS_X, WallPlan.AXIS_Y, WallPlan.AXIS_D1, WallPlan.AXIS_D2]:
		var want := _measured_cover(CliffPlan.FACE_DIAG[1], axis)
		var got := CliffPlan.rock_tiles(Vector2i.ZERO, axis, CliffPlan.FACE_DIAG)
		got.sort()
		assert_eq(got, want, "cliff_face_diag on axis %d covers %s, and COVER_FACE_DIAG says %s"
				% [axis, want, got])
