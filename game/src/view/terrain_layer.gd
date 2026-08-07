## Draws the terrain grid (PLAN.md 3.1 / 6.3). Phase 3.1.
##
## A real TileMapLayer rather than a `_draw()` loop, which is what sim_map.gd said
## the view would build. The difference is not cosmetic: the engine culls to the
## viewport and batches a chunk into one draw call, so a 64x64 map costs the same
## as a 16x16 one and neither shows up against the <200 draw-call budget (PLAN.md
## 3.1). The hand-rolled loop in dev_preview issued one command per tile.
##
## **Takes terrain data, never a SimMap.** The view layer does not hold a
## reference into the simulation (PLAN.md 4) -- it is handed `size` and the raw
## terrain bytes, which is all of SimMap that rendering needs and is also exactly
## what a networked client would receive. That keeps this testable with a literal
## PackedByteArray and no world.
##
## Tiles resolve through the same asset seam as everything else, so terrain with a
## baked atlas draws real art and terrain without one draws its declared
## placeholder. Today that means grass is real and the dirt border is not: there is
## no `terrain.dirt` in visuals.json yet (art track A.1), so it resolves to the
## loud magenta unknown. That is the seam reporting a missing declaration, and it
## is meant to look wrong.
class_name TerrainLayer
extends TileMapLayer

## Terrain kind -> visual ID. Spelled out rather than derived from the enum name
## so that renaming a Terrain member is a change you have to make here too, in
## front of the person making it, instead of silently unmapping a tile.
const TERRAIN_VISUALS := {
	SimMap.Terrain.GRASS: &"terrain.grass",
	SimMap.Terrain.DIRT: &"terrain.dirt",
	SimMap.Terrain.SAND: &"terrain.sand",
	SimMap.Terrain.WATER_SHALLOW: &"terrain.water_shallow",
	SimMap.Terrain.WATER_DEEP: &"terrain.water_deep",
	SimMap.Terrain.ROCK: &"terrain.rock",
	SimMap.Terrain.FOREST: &"terrain.forest",
}

## Tiles per side of a rendering chunk. Measured, not guessed -- and the result is
## backwards from the obvious reasoning that bigger chunks batch better. Draw calls
## at 200 units with the settlement, on desktop (StressTest.tscn):
##
##   quadrant 32   280 calls   50 fps
##   quadrant 16   165 calls   58 fps      <- engine default
##   quadrant  8    32 calls   57 fps
##   quadrant  4    32 calls   58 fps
##
## The reason is the isometric projection: a chunk is a diamond, the viewport is a
## rectangle, and a big diamond overlaps the screen edge over a long span while
## having to draw every tile inside it. Small chunks cull far more tightly, and the
## saving swamps the extra per-chunk overhead. 8 rather than 4 because they tie on
## draw calls and 8 is a quarter of the CanvasItems, which will matter on a 128x128
## map (256 chunks against 1024) more than it does on this one.
const QUADRANT_TILES := 8

var _size: Vector2i = Vector2i.ZERO


## Paint `terrain` (row-major, one byte per tile, values are SimMap.Terrain) over
## a `size` grid. Safe to call again to rebuild; clears first.
func build(size: Vector2i, terrain: PackedByteArray) -> void:
	_size = size
	clear()

	if size.x <= 0 or size.y <= 0 or terrain.size() < size.x * size.y:
		return

	rendering_quadrant_size = QUADRANT_TILES
	tile_set = _build_tile_set(terrain)
	_align_to_iso()

	for y in range(size.y):
		var row := y * size.x
		for x in range(size.x):
			var kind := int(terrain[row + x])
			if tile_set.has_source(kind):
				set_cell(Vector2i(x, y), kind, Vector2i.ZERO)


func size() -> Vector2i:
	return _size


## Godot's isometric TileMapLayer has its own idea of where tile (0, 0) sits, and
## Iso is meant to be the only place grid<->screen math lives. Rather than trust
## the two to coincide, measure the constant difference once and shift the layer
## by it -- after which `map_to_local()` and `Iso.tile_centre_to_world()` agree for
## every tile, which test_terrain_layer.gd asserts across the grid (a mismatch in
## SLOPE rather than offset would survive this and is exactly what that test is
## there to catch).
func _align_to_iso() -> void:
	position = Iso.tile_centre_to_world(Vector2i.ZERO) - map_to_local(Vector2i.ZERO)


func _build_tile_set(terrain: PackedByteArray) -> TileSet:
	var ts := TileSet.new()
	ts.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	ts.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_DOWN
	ts.tile_offset_axis = TileSet.TILE_OFFSET_AXIS_HORIZONTAL
	ts.tile_size = Vector2i(Iso.TILE_SIZE)

	# One source per terrain kind actually used, with the source id set to the
	# Terrain enum value. That makes a painted cell's source id *be* its terrain,
	# so set_cell() needs no lookup table and a cell can be read back and checked
	# against the sim without a second mapping to get out of step.
	for kind in _kinds_used(terrain):
		var source := _source_for(kind)
		if source != null:
			ts.add_source(source, kind)
	return ts


## Only the kinds the map actually contains, so a grass-and-dirt map does not
## build and hold five unused atlas textures.
func _kinds_used(terrain: PackedByteArray) -> Array[int]:
	var seen: Array[int] = []
	for i in range(terrain.size()):
		var kind := int(terrain[i])
		if not seen.has(kind):
			seen.append(kind)
	seen.sort()                        # deterministic source order
	return seen


func _source_for(kind: int) -> TileSetAtlasSource:
	var visual_id: StringName = TERRAIN_VISUALS.get(kind, &"")
	if visual_id == &"":
		return null

	var entry := GameDataRegistry.atlas_for(visual_id)
	var tex: Texture2D = _placeholder_texture(entry) if entry.is_placeholder \
			else _atlas_texture(entry)
	if tex == null:
		return null

	var source := TileSetAtlasSource.new()
	source.texture = tex
	source.texture_region_size = Vector2i(tex.get_size())
	source.create_tile(Vector2i.ZERO)
	return source


## The frame lifted off its atlas page as a standalone texture.
##
## An AtlasTexture rather than pointing TileSetAtlasSource at the page and giving
## it a grid: a baked frame sits wherever isobake packed it, which is not
## necessarily on a boundary of its own size, and a grid cannot address that.
func _atlas_texture(entry: AtlasEntry) -> Texture2D:
	var f := entry.frame_at(AtlasEntry.STATIC_ANIM, 0, 0)
	if f.is_empty():
		return null
	var page := entry.texture(int(f["page"]))
	if page == null:
		return null

	var rect: Rect2i = f["rect"]
	var at := AtlasTexture.new()
	at.atlas = page
	at.region = Rect2(rect.position, rect.size)
	return at


## A flat diamond in the placeholder's colour, drawn into an image because a
## TileSet needs a texture and cannot call PlaceholderRenderer.
##
## Sized to one tile exactly, so an undeclared terrain still tiles seamlessly and
## the gap reads as "wrong colour" rather than "holes in the ground".
func _placeholder_texture(entry: AtlasEntry) -> Texture2D:
	var w := int(Iso.TILE_SIZE.x)
	var h := int(Iso.TILE_SIZE.y)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var color := entry.placeholder.color if entry.placeholder != null \
			else PlaceholderSpec.UNKNOWN_COLOR

	# Scanline fill of the diamond |x/(w/2)| + |y/(h/2)| <= 1, measured from the
	# centre. Half-pixel centres so the top and bottom rows are not empty.
	for y in range(h):
		var ny := absf((y + 0.5) / (h * 0.5) - 1.0)
		var half := (1.0 - ny) * (w * 0.5)
		for x in range(w):
			if absf((x + 0.5) - w * 0.5) <= half:
				img.set_pixel(x, y, color)

	return ImageTexture.create_from_image(img)
