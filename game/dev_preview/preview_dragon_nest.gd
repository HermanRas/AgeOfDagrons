## The dragon nest, drawn through the real seam, next to things whose size is known
## (PLAN.md 13.2).
##
## ## WHY THIS NEEDS EYES AND NOT AN ASSERTION
##
## `vis.dragon_nest` is a **composite with no bespoke art**: the shrine's atlas as the core and
## 34 props arranged around it. Everything a test can check about that is already checked —
## every prop id resolves, the offsets are inside the footprint, the atlases exist. **None of
## that says it looks like a nest.** Whether 22 bushes and 12 standing stones read as an
## overgrown henge or as a suspiciously regular circle of shrubbery is a question for a person,
## which is `preview_walls`' reason for existing too.
##
## ## THE SCALE COMPANIONS ARE THE POINT, NOT DECORATION
##
## A 17.6 m composite photographed alone tells you nothing: every screenshot of a single object
## fills the frame. So a **villager** (~1 m, the human yardstick) and the **mother dragon**
## herself (9.19 m, the thing that lives here) stand beside it. The three together answer the
## question actually worth asking — *can a player tell at a glance that this is a landmark and
## that the dragon belongs to it* — and the dragon-to-nest ratio is what says whether she looks
## like she fits in her own nest.
##
## ## WHAT A FAILURE LOOKS LIKE
##
## - **A magenta box in the middle** means the core did not resolve — the shrine atlas is the
##   core precisely so this cannot happen, so magenta means that wiring broke.
## - **Bushes painted over the shrine** means the prop depth sort is wrong. It is sorted by
##   `x+y`, because `Iso._project` puts screen y at `(x+y) * half.y` and `EntityView` splits
##   behind-the-core from in-front at `at.y < 0`. Sorting by world `y` produces exactly this
##   and looks like a renderer bug.
## - **Props outside the drawn footprint** means `building.dragon_nest`'s 10×10 no longer
##   contains the layout, and the art will hang over tiles the nest does not claim.
##
## Usage:
##   Godot --path game res://dev_preview/preview_dragon_nest.tscn
extends Node2D

const SHOT_PATH := "user://dragon_nest.png"
const SETTLE_FRAMES := 12

## Tile 0,0 of the drawn ground sits here, and everything else is projected from it, so the
## nest's own origin lands where its footprint says it does.
const ORIGIN := Vector2(700.0, 250.0)

## `building.dragon_nest`'s footprint, read from the def rather than repeated: the whole point
## of drawing it is to see whether the art fits inside it, and a number copied to here would
## make the two agree by construction.
var _footprint := Vector2i(10, 10)

var _frames := 0


func _ready() -> void:
	var bd: BuildingDef = GameDataRegistry.building(&"building.dragon_nest")
	if bd == null:
		printerr("building.dragon_nest is not declared -- nothing to preview")
		get_tree().quit(1)
		return
	_footprint = bd.footprint

	var ground := Node2D.new()
	ground.draw.connect(_draw_ground.bind(ground))
	add_child(ground)

	# ⚠️ **THE NEST SITS AT THE CENTRE OF ITS FOOTPRINT, NOT AT ITS CORNER, AND THE FIRST
	# VERSION OF THIS PREVIEW GOT IT WRONG.** `MapData.footprint_rect_of` anchors a footprint
	# top-left, so it is tempting to draw the art at 0,0 and the outline from there -- which
	# put half the nest outside its own footprint and looked like a data fault. But a
	# `SimBuilding`'s `pos` is the footprint's CENTRE in sub-tile units (five tiles off the
	# top-left for an 8x8 town centre), so the sprite is centred and the outline has to be
	# drawn around it. Getting this backwards makes correct data look broken.
	_place(bd.visual, Vector2i.ZERO, "%s  %dx%d tiles" % [bd.name, bd.footprint.x, bd.footprint.y])

	# THE SCALE COMPANIONS, well clear of the nest's 4.4-tile reach so nothing overlaps and
	# the comparison is not confused by occlusion. Both to the SOUTH-WEST, where there is
	# room for a caption -- to the east the labels ran off the viewport.
	_place(&"vis.villager", Vector2i(-9, 2), "villager  ~1 m")
	_place(&"vis.dragon_rigged", Vector2i(-4, 9), "mother dragon  9.19 m")

	var report := Label.new()
	report.text = ("dragon nest: %s core + %d props   |   footprint %dx%d tiles = %.1f x %.1f m"
			% [_core_name(bd.visual), _prop_count(bd.visual),
			bd.footprint.x, bd.footprint.y,
			bd.footprint.x * Iso.METRES_PER_TILE, bd.footprint.y * Iso.METRES_PER_TILE])
	report.position = Vector2(20.0, 16.0)
	report.size = Vector2(1360.0, 22.0)
	add_child(report)


func _place(visual_id: StringName, tile: Vector2i, caption: String) -> void:
	var view := EntityView.new()
	view.visual_id = visual_id
	view.position = ORIGIN + Iso.tile_to_world_f(Vector2(tile))
	# `idle` rather than `static`: `AtlasEntry.resolve_anim` falls back, so this works for a
	# building's single static clip AND for the dragon's real idle without a special case.
	view.play_anim(&"idle", 0)
	add_child(view)

	var label := Label.new()
	label.text = caption
	label.position = view.position + Vector2(-110.0, 40.0)
	label.size = Vector2(220.0, 20.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(label)


## Grass, plus the nest's own footprint outlined on it. The outline is the load-bearing part:
## it is what makes "does the art fit the tiles it claims" a thing you can see rather than
## infer.
func _draw_ground(on: Node2D) -> void:
	var spec := PlaceholderSpec.from_dict({
		"shape": "diamond", "footprint_m": [2.0, 2.0], "color": "#4a6f30",
	})
	for tx in range(-13, 10):
		for ty in range(-9, 14):
			# `draw_into` paints at the CanvasItem's own origin, so the position goes through
			# the transform -- `preview_placeholders._draw_grid`'s arrangement.
			on.draw_set_transform(
					ORIGIN + Iso.tile_to_world(Vector2i(tx, ty)), 0.0, Vector2.ONE)
			PlaceholderRenderer.draw_into(on, spec, 0)
	on.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# CENTRED ON THE ART, because that is where a building's origin is -- see `_ready()`.
	var h := Vector2(_footprint) * 0.5
	var corners := PackedVector2Array([
		ORIGIN + Iso.tile_to_world_f(Vector2(-h.x, -h.y)),
		ORIGIN + Iso.tile_to_world_f(Vector2(h.x, -h.y)),
		ORIGIN + Iso.tile_to_world_f(Vector2(h.x, h.y)),
		ORIGIN + Iso.tile_to_world_f(Vector2(-h.x, h.y)),
	])
	on.draw_polyline(corners + PackedVector2Array([corners[0]]),
			Color(1.0, 0.85, 0.3, 0.9), 2.0)


func _core_name(visual_id: StringName) -> String:
	var e := GameDataRegistry.atlas_for(visual_id)
	return "PLACEHOLDER (core did not resolve)" if e == null or e.is_placeholder \
			else "real art"


func _prop_count(visual_id: StringName) -> int:
	return GameDataRegistry.props_for(visual_id, 1).size()


func _process(_delta: float) -> void:
	_frames += 1
	if _frames < SETTLE_FRAMES:
		return
	get_viewport().get_texture().get_image().save_png(SHOT_PATH)
	print("wrote ", ProjectSettings.globalize_path(SHOT_PATH))
	get_tree().quit(0)
