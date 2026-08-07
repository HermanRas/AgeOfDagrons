## Phase 0.2a: AtlasEntry parses PLAN.md 9.1 atlases and indexes frames.
##
## The frame-index formula and the direction table are the two things the view
## layer cannot afford to get wrong -- an off-by-one in either shows up as the
## wrong sprite for the wrong facing, which looks like an art bug and gets chased
## in the wrong repo. So both are asserted against a REAL isobake output
## (tests/fixtures/gold_mine.atlas.json, a verbatim copy of a shipped bake) as
## well as against hand-built dictionaries, because a parser tested only against
## its author's idea of the format proves very little.
extends TestCase

const FIXTURE := "res://tests/fixtures/gold_mine.atlas.json"


func _fixture() -> AtlasEntry:
	var text := FileAccess.get_file_as_string(FIXTURE)
	var parsed: Variant = JSON.parse_string(text)
	return AtlasEntry.from_atlas_dict(&"vis.gold_mine", parsed as Dictionary, "res://tests/fixtures")


## An 8-direction, multi-anim atlas shaped like the villager's, small enough to
## reason about by hand. 2 anims x 8 directions x 3 frames = 48 frames.
func _multi_anim() -> AtlasEntry:
	var frames: Array = []
	for i in range(48):
		frames.append({"page": 0, "rect": [i, 0, 10, 20], "anchor": [5.0, 19.0]})

	var table: Array = []
	for i in range(8):
		table.append({"dir": AtlasEntry.FACINGS[i], "stored_index": i, "flip_x": false})

	return AtlasEntry.from_atlas_dict(&"test.multi", {
		"pages": ["p0.png"],
		"pixels_per_metre": Iso.PIXELS_PER_METRE,
		"directions": {"stored": 8, "mirror_for_8": false, "table": table},
		"anims": {
			"idle": {"fps": 8.0, "loop": true, "frames": 3, "first": 0},
			"walk": {"fps": 15.0, "loop": true, "frames": 3, "first": 24},
		},
		"frames": frames,
	}, "res://tests/fixtures")


# ── real isobake output ────────────────────────────────────────────────────

func test_a_real_bake_parses_into_frames_anims_and_a_full_direction_table() -> void:
	var e := _fixture()
	assert_false(e.is_placeholder, "a parsed atlas is not a placeholder")
	assert_eq(e.frames.size(), 5, "the gold mine bake has 5 stored frames")
	assert_true(e.has_anim(&"static"), "a static prop declares the 'static' anim")
	assert_eq(e.dir_table.size(), 8,
			"isobake always emits all 8 facings even when it stored 5")
	assert_almost_eq(e.pixels_per_metre, Iso.PIXELS_PER_METRE, 0.01,
			"the shipped bake agrees with the projection the game draws at")


func test_five_stored_directions_resolve_to_eight_facings_by_mirroring() -> void:
	var e := _fixture()
	# S and N are the two axis facings that cannot be mirrored from anything else.
	assert_false(bool(e.frame_at(&"static", 0, 0)["flip_x"]), "S is stored, not flipped")
	assert_false(bool(e.frame_at(&"static", 4, 0)["flip_x"]), "N is stored, not flipped")

	# SW/W/NW are the mirrors of SE/E/NE, and must point at the same stored frame.
	for pair in [[1, 7], [2, 6], [3, 5]]:
		var mirrored: Dictionary = e.frame_at(&"static", pair[0], 0)
		var stored: Dictionary = e.frame_at(&"static", pair[1], 0)
		assert_true(bool(mirrored["flip_x"]),
				"facing %s is a mirror" % AtlasEntry.FACINGS[pair[0]])
		assert_false(bool(stored["flip_x"]),
				"facing %s is stored" % AtlasEntry.FACINGS[pair[1]])
		assert_eq(mirrored["rect"], stored["rect"],
				"%s mirrors %s, so they share one stored frame"
				% [AtlasEntry.FACINGS[pair[0]], AtlasEntry.FACINGS[pair[1]]])


func test_a_missing_png_page_yields_no_texture_rather_than_failing() -> void:
	# The fixture deliberately ships without its PNG: parsing an atlas must never
	# depend on the pages existing, which is what lets the seam and its tests run
	# with no art in the repo.
	assert_null(_fixture().texture(0), "absent page loads as null, not an error")


# ── frame indexing ─────────────────────────────────────────────────────────

func test_frame_index_is_direction_major_within_an_anim() -> void:
	var e := _multi_anim()
	# PLAN.md 9.1: first + stored_direction * frames + frame.
	# idle starts at 0, walk at 24; 3 frames per direction.
	assert_eq(e.frame_at(&"idle", 0, 0)["rect"], Rect2i(0, 0, 10, 20), "idle S frame 0")
	assert_eq(e.frame_at(&"idle", 0, 2)["rect"], Rect2i(2, 0, 10, 20), "idle S frame 2")
	assert_eq(e.frame_at(&"idle", 1, 0)["rect"], Rect2i(3, 0, 10, 20), "idle SW frame 0")
	assert_eq(e.frame_at(&"walk", 0, 0)["rect"], Rect2i(24, 0, 10, 20), "walk S frame 0")
	assert_eq(e.frame_at(&"walk", 7, 2)["rect"], Rect2i(47, 0, 10, 20), "walk SE frame 2")


func test_frame_and_facing_wrap_instead_of_going_out_of_range() -> void:
	var e := _multi_anim()
	assert_eq(e.frame_at(&"idle", 0, 3)["rect"], e.frame_at(&"idle", 0, 0)["rect"],
			"frame 3 of a 3-frame anim wraps to 0")
	assert_eq(e.frame_at(&"idle", 8, 0)["rect"], e.frame_at(&"idle", 0, 0)["rect"],
			"facing 8 wraps to S")
	assert_eq(e.frame_at(&"idle", -1, 0)["rect"], e.frame_at(&"idle", 7, 0)["rect"],
			"facing -1 wraps to SE, not to a negative index")


func test_anim_metadata_is_read_per_anim() -> void:
	var e := _multi_anim()
	assert_eq(e.frame_count(&"idle"), 3)
	assert_almost_eq(e.fps(&"walk"), 15.0)
	assert_true(e.loops(&"walk"))


# ── graceful degradation ───────────────────────────────────────────────────

func test_a_missing_anim_falls_back_rather_than_drawing_nothing() -> void:
	# PLAN.md 2.1: gameplay never blocks on art. A villager whose work_hunt clip
	# has not been baked yet should stand there, not vanish.
	var e := _multi_anim()
	assert_eq(e.resolve_anim(&"work_hunt"), &"idle",
			"an unbaked anim falls back to idle")
	assert_false(e.frame_at(&"work_hunt", 0, 0).is_empty(),
			"the fallback still resolves to a drawable frame")

	var static_only := _fixture()
	assert_eq(static_only.resolve_anim(&"walk"), &"static",
			"a static prop asked to walk stays static")


func test_a_placeholder_entry_reports_one_inert_frame() -> void:
	var e := AtlasEntry.from_placeholder(&"vis.x", PlaceholderSpec.unknown())
	assert_true(e.is_placeholder)
	assert_eq(e.frame_count(&"walk"), 1, "placeholders do not animate")
	assert_true(e.frame_at(&"walk", 0, 0).is_empty(),
			"placeholders have no atlas frame -- the caller draws shapes instead")
