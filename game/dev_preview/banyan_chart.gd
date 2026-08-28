## The still-life half of `preview_banyan` (`--chart`): three trees at 1:1 on a tile
## grid, each with eight villagers standing one and two tiles out, drawn UNDER it.
##
## It produced the numbers in asset_request.md and it is still the cheapest way to see
## the three silhouettes against each other. **It cannot answer the question that
## actually decides the banyan** -- whether a tap meant for one thing lands on another --
## which is why `preview_banyan` boots the real game by default and this is the flag.
##
## 1:1 AND NOT MAGNIFIED, deliberately: the whole question is screen coverage, and a zoom
## would change the answer.
extends Node2D

const SHOT_DIR := "user://"
const WINDOW := Vector2i(1600, 900)

## Where the subject's tile lands on screen. LOW, because a tree is drawn almost entirely
## ABOVE its anchor: a centred origin leaves the top third empty and crops the canopy of
## the one tree this is about.
const ORIGIN := Vector2(800.0, 700.0)

## Half-width of the drawn grid, in tiles. 5 so the far corner clears the bottom edge at
## this origin -- a grid running off the page reads as the tree covering more ground than
## it does.
const GRID := 5

## The one-tile band the art side measures every tree against (tree_teak.toml).
const BAND_PX := 250.0

## Subject, then the two reference points. Order matters: the banyan is what is being
## asked about, and the two after it are what the answer is measured against.
const TREES: Array[StringName] = [&"vis.tree_banyan", &"vis.tree_teak", &"vis.tree"]

const NOTES := {
	&"vis.tree_banyan": "ASKED ABOUT -- baked and flagged, in NO pool until this is answered",
	&"vis.tree_teak": "REJECTED 2026-08-23 -- owner tapped its roots and gathered another tree",
	&"vis.tree": "IN THE GAME TODAY -- the oak, the shape everything else is judged against",
}

## Villager rings, in tiles from the subject. One out is the tap that matters; two out is
## where the teak still reached, so a canopy that clears the first ring and not the
## second is a different answer from one that clears both.
const RINGS := [1, 2]

var _page := 0
var _frames := 0
var _spawned: Array[Node] = []


func _ready() -> void:
	get_window().size = WINDOW
	get_window().content_scale_size = WINDOW
	_build(TREES[0])


func _process(_delta: float) -> void:
	_frames += 1
	# The views resolve their atlas lazily on first draw and the viewport texture lags a
	# frame behind, so a shot taken on arrival photographs an empty grid.
	if _frames < 12:
		return
	_frames = 0
	_shoot("banyan_%s" % String(TREES[_page]).trim_prefix("vis."))
	_page += 1
	if _page >= TREES.size():
		get_tree().quit()
		return
	_build(TREES[_page])


func _build(tree_id: StringName) -> void:
	for n in _spawned:
		n.queue_free()
	_spawned.clear()

	# The villagers go down FIRST and the tree after, so the tree draws over them --
	# which is the whole thing being judged.
	for ring in RINGS:
		for d in [Vector2i(ring, 0), Vector2i(-ring, 0), Vector2i(0, ring), Vector2i(0, -ring)]:
			_add_view(&"vis.villager", d, &"idle", 0, 0)
	_add_view(tree_id, Vector2i.ZERO, AtlasEntry.STATIC_ANIM, 0, -1)

	var width := _sprite_width(tree_id)
	var over := width - BAND_PX
	_add_label(Vector2(24.0, 24.0), "%s   %s" % [tree_id, NOTES.get(tree_id, "")], 22)
	_add_label(Vector2(24.0, 56.0),
			"widest frame %d px   band %d px   %s" % [int(width), int(BAND_PX),
				("OVER by %d px" % int(over)) if over > 0.0 else "inside the band"], 20)
	# WHICH FILE THIS IS, on the page. A judgement made from a screenshot of a stale
	# atlas is worse than no judgement -- see preview_facing_chart, same trap.
	var path := GameDataRegistry.atlas_path_for(tree_id, 0, -1)
	var identity := GameDataRegistry.atlas_identity_for(tree_id, 0, -1)
	_add_label(Vector2(24.0, 84.0), "bake: %s   [%s]"
			% [path if not path.is_empty() else "NOTHING DECLARED",
				identity if not identity.is_empty() else "not staged"], 16)
	print("  %s -> %s  [%s]  widest %d px" % [tree_id,
			path if not path.is_empty() else "nothing declared",
			identity if not identity.is_empty() else "not staged", int(width)])

	_add_label(Vector2(24.0, 126.0),
			"Filled diamond: the tile the tree stands on.  Outline: its 2x2 pick rect.", 18)
	_add_label(Vector2(24.0, 152.0),
			"Eight villagers, one and two tiles out, drawn UNDER the tree on purpose.", 18)
	_add_label(Vector2(24.0, 178.0),
			"THE TAP QUESTION IS NOT ON THIS PAGE -- run without --chart for that.", 18)
	queue_redraw()


## The widest frame in the atlas, in pixels -- the number the art side quotes and the one
## the band is about. Read off the staged atlas rather than trusted from a note, because
## a re-bake moves it and a hard-coded figure would not.
func _sprite_width(tree_id: StringName) -> float:
	var entry := GameDataRegistry.atlas_for(tree_id, 0, -1)
	if entry.is_placeholder:
		return 0.0
	var widest := 0.0
	for facing in range(AtlasEntry.FACINGS.size()):
		var f := entry.frame_at(AtlasEntry.STATIC_ANIM, facing, 0)
		if not f.is_empty():
			widest = maxf(widest, float((f["rect"] as Rect2i).size.x))
	return widest


func _add_view(visual: StringName, tile: Vector2i, anim: StringName,
		facing: int, colour: int) -> void:
	var view := EntityView.new()
	add_child(view)
	view.visual_id = visual
	view.skin_age = 0
	view.skin_colour = colour
	view.position = ORIGIN + Iso.tile_centre_to_world(tile)
	view.play_anim(anim, facing)
	_spawned.append(view)


func _add_label(at: Vector2, text: String, size: int) -> void:
	var l := Label.new()
	l.text = text
	l.position = at
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color.WHITE)
	add_child(l)
	_spawned.append(l)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(WINDOW)), Color(0.20, 0.26, 0.17))
	for x in range(-GRID, GRID + 1):
		for y in range(-GRID, GRID + 1):
			_diamond(Vector2i(x, y), Color(1.0, 1.0, 1.0, 0.10), false)
	# The tree's own tile, and the 2x2 the tap actually tests against.
	_diamond(Vector2i.ZERO, Color(1.0, 0.85, 0.3, 0.35), true)
	for t in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
		_diamond(t, Color(1.0, 0.85, 0.3, 0.55), false)
	for ring in RINGS:
		for d in [Vector2i(ring, 0), Vector2i(-ring, 0), Vector2i(0, ring), Vector2i(0, -ring)]:
			_diamond(d, Color(0.45, 0.85, 1.0, 0.55), false)


func _diamond(tile: Vector2i, colour: Color, filled: bool) -> void:
	var c := ORIGIN + Iso.tile_centre_to_world(tile)
	var half := Iso.TILE_SIZE * 0.5
	var pts := PackedVector2Array([
		c + Vector2(0.0, -half.y), c + Vector2(half.x, 0.0),
		c + Vector2(0.0, half.y), c + Vector2(-half.x, 0.0), c + Vector2(0.0, -half.y)])
	if filled:
		draw_colored_polygon(pts, colour)
	else:
		draw_polyline(pts, colour, 1.5)


func _shoot(name: String) -> void:
	var path := SHOT_DIR + name + ".png"
	get_viewport().get_texture().get_image().save_png(path)
	print("wrote ", ProjectSettings.globalize_path(path))
