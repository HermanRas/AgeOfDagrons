## The half-turn compensation for atlases baked facing the wrong way
## (`AtlasEntry.facing_offset`, `directions_reversed` in visuals.json).
##
## **THIS WHOLE FILE IS TEMPORARY AND SHOULD BE DELETED WITH THE LAST FLAG.** The
## defect it covers is in the recipes, not in the game: isobake's zeroad adapter
## turns every subject 180 degrees from the direction the atlas labels it, 81 of
## the 171 recipes cancel that with `yaw_offset_deg = 180.0`, and the rest -- every
## unit, ship, animal and siege engine -- were baked backwards. The re-bake is
## queued behind a day of machine time (asset_request.md), so the game compensates
## in the meantime.
##
## Its own file rather than more of test_atlas_entry, for exactly that reason: when
## the recipes are fixed, the flags come out of visuals.json and this file goes
## with them in one commit, instead of being unpicked from tests that outlive it.
##
## What it does NOT test is which way a sprite actually points -- no headless test
## can judge that, and `dev_preview/preview_facing_chart.tscn` is what does.
extends TestCase

const REGISTRY_SCRIPT := "res://src/autoload/game_data.gd"
const VISUALS_PATH := "res://data/visuals.json"

var reg: Node
var _visuals: Dictionary = {}


func before_each() -> void:
	reg = (load(REGISTRY_SCRIPT) as GDScript).new()
	reg.load_all()
	_visuals = JSON.parse_string(FileAccess.get_file_as_string(VISUALS_PATH))


func after_each() -> void:
	reg.free()


## Eight stored directions, one frame each, so a resolved frame's rect.x IS the
## stored direction it came from and the mapping can be read off by eye.
func _eight_dirs() -> AtlasEntry:
	var frames: Array = []
	for i in range(8):
		frames.append({"page": 0, "rect": [i, 0, 1, 1], "anchor": [0.0, 0.0]})
	var table: Array = []
	for i in range(8):
		table.append({"dir": AtlasEntry.FACINGS[i], "stored_index": i, "flip_x": false})
	return AtlasEntry.from_atlas_dict(&"test.eight", {
		"pages": ["p0.png"],
		"pixels_per_metre": Iso.PIXELS_PER_METRE,
		"directions": {"stored": 8, "mirror_for_8": false, "table": table},
		"anims": {"static": {"fps": 1.0, "loop": false, "frames": 1, "first": 0}},
		"frames": frames,
	}, "res://tests/fixtures")


## A real 5-stored, mirrored bake -- the shape animals and siege engines have.
func _mirrored() -> AtlasEntry:
	var text := FileAccess.get_file_as_string("res://tests/fixtures/gold_mine.atlas.json")
	return AtlasEntry.from_atlas_dict(
			&"test.mirrored", JSON.parse_string(text) as Dictionary, "res://tests/fixtures")


# ── the mechanism ──────────────────────────────────────────────────────────

func test_a_parsed_atlas_is_not_compensated_unless_something_asks() -> void:
	# The default has to be inert: 140 of the 171 recipes are correct, and a
	# compensation applied by accident is the same bug pointing the other way.
	assert_eq(_eight_dirs().facing_offset, 0, "parsing an atlas sets no offset")
	assert_eq(_mirrored().facing_offset, 0, "not even for a mirrored bake")


func test_half_a_turn_maps_every_facing_to_its_opposite() -> void:
	var e := _eight_dirs()
	e.facing_offset = AtlasEntry.HALF_TURN
	for facing in range(8):
		var opposite := (facing + 4) % 8
		assert_eq(int((e.frame_at(&"static", facing, 0)["rect"] as Rect2i).position.x), opposite,
				"asking for %s draws the frame stored as %s"
						% [AtlasEntry.FACINGS[facing], AtlasEntry.FACINGS[opposite]])


func test_the_compensation_is_its_own_inverse() -> void:
	# Applying it twice is the identity, which is what makes a double-applied flag
	# invisible rather than 90 degrees out -- worth knowing when the re-bake lands
	# and someone has to tell "flag removed" from "flag not removed".
	var plain := _eight_dirs()
	var turned := _eight_dirs()
	turned.facing_offset = AtlasEntry.HALF_TURN * 2
	for facing in range(8):
		assert_eq(turned.frame_at(&"static", facing, 0)["rect"],
				plain.frame_at(&"static", facing, 0)["rect"],
				"two half turns leave %s where it was" % AtlasEntry.FACINGS[facing])


func test_a_mirrored_bake_keeps_resolving_its_own_flips() -> void:
	# The reason the offset is applied to the REQUEST rather than by rewriting
	# dir_table: a 5-stored atlas mirrors SW/W/NW from SE/E/NE, and turning the
	# request through half a turn has to land on the mirror table intact. S and N
	# are the two facings that cannot be mirrored from anything, so after the turn
	# they must still be the unflipped pair -- just each other's frame.
	var plain := _mirrored()
	var turned := _mirrored()
	turned.facing_offset = AtlasEntry.HALF_TURN

	assert_eq(turned.frame_at(&"static", 0, 0)["rect"], plain.frame_at(&"static", 4, 0)["rect"],
			"S now draws what N used to")
	assert_eq(turned.frame_at(&"static", 4, 0)["rect"], plain.frame_at(&"static", 0, 0)["rect"],
			"and N draws what S used to")
	assert_false(bool(turned.frame_at(&"static", 0, 0)["flip_x"]), "S stays unflipped")
	assert_false(bool(turned.frame_at(&"static", 4, 0)["flip_x"]), "N stays unflipped")

	# Exactly three of the eight are mirrors either way round -- a turn that lost
	# or gained one would mean a sprite drawn backwards in the OTHER sense.
	var flipped := 0
	for facing in range(8):
		if bool(turned.frame_at(&"static", facing, 0)["flip_x"]):
			flipped += 1
	assert_eq(flipped, 3, "three facings are mirrors before the turn and after it")


func test_a_placeholder_ignores_the_offset_entirely() -> void:
	# Placeholders are drawn procedurally from a facing (PlaceholderRenderer), not
	# read out of a table, and they were never baked -- so a compensation for the
	# bake must not reach them.
	var e := AtlasEntry.from_placeholder(&"vis.x", PlaceholderSpec.unknown())
	e.facing_offset = AtlasEntry.HALF_TURN
	assert_true(e.frame_at(&"static", 0, 0).is_empty(), "still no atlas frame to resolve")


# ── the wiring, and the shipped data ───────────────────────────────────────

func test_the_flagged_entries_are_exactly_what_the_registry_reports() -> void:
	var declared: Array[StringName] = []
	for id in _visuals:
		if String(id).begins_with("_"):
			continue
		if bool((_visuals[id] as Dictionary).get("directions_reversed", false)):
			declared.append(StringName(id))
	declared.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))

	assert_false(declared.is_empty(),
			"the flags are still in visuals.json -- if the re-bake landed, delete this file")
	assert_eq(reg.reversed_direction_atlases(), declared,
			"the diagnostic enumerates the flagged entries and nothing else")


func test_every_flagged_entry_is_a_declared_visual_with_an_atlas() -> void:
	# A typo'd id would sit here compensating nothing, and nothing else would ever
	# read it -- the flag has no effect on an id no def reaches for.
	for id in reg.reversed_direction_atlases():
		var decl: Dictionary = _visuals[String(id)]
		assert_false(str(decl.get("atlas", "")).is_empty(),
				"%s declares an atlas path to compensate" % id)
		assert_true(reg.visual_ids().has(id), "%s is a visual the registry knows" % id)


func test_the_offset_reaches_a_resolved_entry_through_every_skin_axis() -> void:
	# Guarded on the art being staged: `assets/atlases/` is gitignored, so a fresh
	# clone resolves these to placeholders and has nothing to carry an offset.
	var flagged: Array = reg.reversed_direction_atlases()
	assert_false(flagged.is_empty(), "there is something to check")
	for id in flagged:
		var base: AtlasEntry = reg.atlas_for(id)
		if base.is_placeholder:
			continue
		assert_eq(base.facing_offset, AtlasEntry.HALF_TURN, "%s is compensated" % id)
		# An age skin and a colour tint are separate bakes of the same actor, turned
		# the same way round, so one flag has to cover every path the skin key picks.
		for age in [1, 4]:
			assert_eq((reg.atlas_for(id, age) as AtlasEntry).facing_offset,
					AtlasEntry.HALF_TURN, "%s at age %d is compensated too" % [id, age])
		for colour in [0, 3]:
			assert_eq((reg.atlas_for(id, 0, colour) as AtlasEntry).facing_offset,
					AtlasEntry.HALF_TURN, "%s in colour %d is compensated too" % [id, colour])


func test_nothing_unflagged_is_compensated() -> void:
	var flagged: Array = reg.reversed_direction_atlases()
	var checked := 0
	for id in reg.visual_ids():
		if flagged.has(id):
			continue
		var entry: AtlasEntry = reg.atlas_for(id)
		if entry.is_placeholder:
			continue
		assert_eq(entry.facing_offset, 0, "%s is drawn as baked" % id)
		checked += 1
	assert_true(checked > 0 or flagged.size() > 0,
			"either some art is staged, or there is nothing here to get wrong")


func test_a_flag_on_a_single_direction_bake_would_do_nothing_and_is_not_there() -> void:
	# The reason the buildings could NOT be fixed this way, asserted so that the
	# next person to add a flag finds out here rather than by looking at the game.
	# A `directions = 1` bake serves all eight facings from one stored frame, so
	# rotating the request lands on the same image and the flag is a lie.
	for id in reg.reversed_direction_atlases():
		var entry: AtlasEntry = reg.atlas_for(id)
		if entry.is_placeholder:
			continue
		var stored := {}
		for dir in entry.dir_table:
			stored[int((dir as Dictionary)["stored_index"])] = true
		assert_true(stored.size() > 1,
				"%s stores %d directions; a half turn only means something above one"
						% [id, stored.size()])
