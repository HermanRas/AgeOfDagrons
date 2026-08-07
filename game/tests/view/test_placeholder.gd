## Phase 0.2b: the procedural placeholder renderer (PLAN.md 2.4).
##
## Tests the geometry and the spec parsing, not pixels. The draw_* calls need a
## live CanvasItem inside _draw(), which the headless suite has no business
## standing up -- but the geometry is where the bugs would be, and it is pure.
extends TestCase


func test_spec_parses_a_visuals_json_placeholder_block() -> void:
	var spec := PlaceholderSpec.from_dict({
		"shape": "box",
		"footprint_m": [15.5, 15.0],
		"height_m": 6.8,
		"color": "#b9a887",
		"facing_marker": true,
	})
	assert_eq(spec.shape, PlaceholderSpec.Shape.BOX)
	assert_almost_eq(spec.footprint_m.x, 15.5)
	assert_almost_eq(spec.height_m, 6.8)
	assert_true(spec.facing_marker)
	assert_almost_eq(spec.color.r, Color("#b9a887").r, 0.001)


func test_an_unrecognised_shape_falls_back_rather_than_crashing() -> void:
	# visuals.json is hand-edited data; a typo should degrade, not take the game
	# down on boot.
	var spec := PlaceholderSpec.from_dict({"shape": "dodecahedron"})
	assert_eq(spec.shape, PlaceholderSpec.Shape.CAPSULE, "unknown shapes become a capsule")


func test_a_spec_with_no_colour_is_visibly_wrong_rather_than_invisible() -> void:
	assert_eq(PlaceholderSpec.from_dict({}).color, PlaceholderSpec.UNKNOWN_COLOR)


func test_footprint_points_form_a_diamond_matching_the_tile_grid() -> void:
	# A 1-tile footprint must project to exactly the tile diamond, or placeholder
	# terrain will not line up with the grid it is standing in for.
	var pts := PlaceholderRenderer.footprint_points(
			Vector2(Iso.METRES_PER_TILE, Iso.METRES_PER_TILE))
	assert_eq(pts.size(), 4)

	var width := pts[1].x - pts[3].x
	var height := pts[2].y - pts[0].y
	assert_almost_eq(width, Iso.TILE_SIZE.x, 0.01, "one tile wide")
	assert_almost_eq(height, Iso.TILE_SIZE.y, 0.01, "one tile tall")


func test_footprint_points_are_centred_on_the_ground_anchor() -> void:
	# The anchor convention has to match a baked atlas frame's anchor (PLAN.md
	# 9.1), otherwise swapping placeholder for real art shifts the entity.
	var pts := PlaceholderRenderer.footprint_points(Vector2(4.0, 6.0))
	var sum := Vector2.ZERO
	for p in pts:
		sum += p
	assert_almost_eq(sum.x / 4.0, 0.0, 0.01, "centroid sits on the origin in x")
	assert_almost_eq(sum.y / 4.0, 0.0, 0.01, "centroid sits on the origin in y")


func test_lifting_a_footprint_moves_it_straight_up() -> void:
	var base := PlaceholderRenderer.footprint_points(Vector2(2.0, 2.0))
	var top := PlaceholderRenderer.footprint_points(Vector2(2.0, 2.0), 3.0)
	for i in range(4):
		assert_almost_eq(top[i].x, base[i].x, 0.01, "height does not shear the footprint")
		assert_almost_eq(top[i].y, base[i].y + Iso.height_to_world(3.0).y, 0.01)


func test_a_bigger_footprint_produces_a_proportionally_bigger_diamond() -> void:
	var small := PlaceholderRenderer.footprint_points(Vector2(2.0, 2.0))
	var big := PlaceholderRenderer.footprint_points(Vector2(4.0, 4.0))
	assert_almost_eq(big[1].x - big[3].x, (small[1].x - small[3].x) * 2.0, 0.01)
