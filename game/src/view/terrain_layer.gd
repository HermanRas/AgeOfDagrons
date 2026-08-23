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

## THE BLEND (project owner, 2026-08-23). Terrain is one flat diamond per kind, so
## grass meeting water is a pixel-crisp zigzag of 64x32 diamonds and reads as a
## staircase. The sand band softened the contrast; this softens the EDGE.
##
## NO NEW ART, and that was the owner's reason for choosing this over baked corner
## tiles: "adding more sprites will make theme packs harder later on". A theme pack
## still ships exactly one diamond per terrain and gets its blending for free, because
## every transition below is generated from that diamond at load time.
##
## HOW. A second TileMapLayer sits above the base one. For each tile, the neighbour
## with the higher `BLEND_ORDER` is drawn over it a second time, through an alpha ramp
## that is opaque at the shared edge and gone by the far side -- so grass reaches into
## sand and sand reaches into water, and the join stops being a line.
##
## Which of the two neighbours does the reaching is what `BLEND_ORDER` decides, and it
## is the natural direction rather than an arbitrary one: sand washes over a waterline,
## grass grows down onto sand. Reversed, the water would climb the beach.
const BLEND_ORDER := {
	SimMap.Terrain.WATER_DEEP: 0,
	SimMap.Terrain.WATER_SHALLOW: 1,
	SimMap.Terrain.SAND: 2,
	SimMap.Terrain.DIRT: 3,
	SimMap.Terrain.GRASS: 4,
	SimMap.Terrain.ROCK: 5,
	SimMap.Terrain.FOREST: 6,
}

## How far into the tile the neighbour reaches, as a fraction of the diamond's
## half-width. Above 0.5 the ramps from opposite edges overlap in the middle, which is
## what stops a one-tile isthmus of sand from having a hard seam down its spine.
const BLEND_REACH := 0.58

## The four EDGE-sharing neighbours, in mask-bit order. Diagonals are deliberately
## absent: they share a corner, not an edge, and there is no edge for a ramp to start
## from. In this projection these four are the NE, SE, SW and NW sides on screen.
const EDGE_OFFSETS := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

## Sign pair per edge for the diamond's own equation. A tile is |X| + |Y| <= 1 about
## its centre, and each of its four sides is where `sx*X + sy*Y == 1` -- so this is
## both which side a bit means and the distance function that fades away from it.
const EDGE_SIGNS := [Vector2(1.0, -1.0), Vector2(1.0, 1.0),
		Vector2(-1.0, 1.0), Vector2(-1.0, -1.0)]

## Every non-empty subset of four edges. Packed one per column of a strip texture, so
## a terrain's fifteen transitions are one image and one TileSet source.
const EDGE_COMBOS := 15

var _size: Vector2i = Vector2i.ZERO

## Drawn above this layer because it is a CHILD of it: Godot draws a parent CanvasItem
## and then its children, and the whole terrain subtree still comes before the entity
## pool, which is GameView's next sibling. So it covers the ground and nothing else.
var _blend: TileMapLayer = null


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

	_build_blend(size, terrain)


func size() -> Vector2i:
	return _size


## The transition layer, or null before the first `build()`. A test seam: the blend is
## invisible to every other caller and there is nothing here to configure.
func blend_layer() -> TileMapLayer:
	return _blend


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


## Paint the transition layer. One cell wherever a tile has a higher-order neighbour,
## carrying that neighbour's terrain faded in from the shared edge or edges.
##
## ONE NEIGHBOUR PER TILE, the highest-order one, because a TileMapLayer holds a single
## cell per coordinate. Where three terrains meet -- grass, sand and water on one tile,
## which the shore pass makes rare but not impossible -- the strongest wins and the
## other join stays crisp. A second layer per order would fix it and is not worth its
## cost until somebody can point at one.
func _build_blend(size: Vector2i, terrain: PackedByteArray) -> void:
	if _blend == null:
		_blend = TileMapLayer.new()
		add_child(_blend)
	_blend.clear()
	# Zero, not `_align_to_iso`: it is a child, so it already inherits this layer's
	# alignment. Shifting it again would offset every transition by one tile.
	_blend.position = Vector2.ZERO
	_blend.rendering_quadrant_size = QUADRANT_TILES
	_blend.tile_set = _build_blend_tile_set(terrain)
	if _blend.tile_set == null:
		return

	for y in range(size.y):
		for x in range(size.x):
			var t := Vector2i(x, y)
			var mine: int = terrain[y * size.x + x]
			var over := _dominant_neighbour(size, terrain, t, mine)
			if over < 0 or not _blend.tile_set.has_source(over):
				continue
			var bits := _edges_facing(size, terrain, t, over)
			if bits == 0:
				continue
			_blend.set_cell(t, over, Vector2i(bits - 1, 0))


## The neighbouring terrain that should reach over `mine`, or -1 for none. Highest
## `BLEND_ORDER` wins; ties cannot happen because a tie means the same terrain.
func _dominant_neighbour(size: Vector2i, terrain: PackedByteArray, t: Vector2i,
		mine: int) -> int:
	var best := -1
	var best_order: int = BLEND_ORDER.get(mine, 0)
	for offset in EDGE_OFFSETS:
		var n: Vector2i = t + offset
		if n.x < 0 or n.y < 0 or n.x >= size.x or n.y >= size.y:
			continue
		var kind: int = terrain[n.y * size.x + n.x]
		var order: int = BLEND_ORDER.get(kind, 0)
		if order > best_order:
			best_order = order
			best = kind
	return best


## Bitmask of which of `t`'s four edges face `kind`, in EDGE_OFFSETS order.
func _edges_facing(size: Vector2i, terrain: PackedByteArray, t: Vector2i,
		kind: int) -> int:
	var bits := 0
	for i in range(EDGE_OFFSETS.size()):
		var n: Vector2i = t + EDGE_OFFSETS[i]
		if n.x < 0 or n.y < 0 or n.x >= size.x or n.y >= size.y:
			continue
		if int(terrain[n.y * size.x + n.x]) == kind:
			bits |= 1 << i
	return bits


## A source per terrain that could ever reach over another -- i.e. every kind on the
## map except the lowest-order one, which nothing is below.
func _build_blend_tile_set(terrain: PackedByteArray) -> TileSet:
	var kinds := _kinds_used(terrain)
	if kinds.size() < 2:
		return null                    # a single-terrain map has nothing to blend

	var ts := TileSet.new()
	ts.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	ts.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_DOWN
	ts.tile_offset_axis = TileSet.TILE_OFFSET_AXIS_HORIZONTAL
	ts.tile_size = Vector2i(Iso.TILE_SIZE)
	for kind in kinds:
		var source := _blend_source_for(kind)
		if source != null:
			ts.add_source(source, kind)
	return ts


## One terrain's fifteen edge combinations, packed across a single strip texture.
##
## A strip rather than fifteen sources or fifteen alternative tiles: alternatives in
## Godot share one texture region and differ only by transform, so they cannot carry
## fifteen different masks, and fifteen sources per terrain would multiply the source
## ids the base layer deliberately keeps equal to the Terrain enum.
func _blend_source_for(kind: int) -> TileSetAtlasSource:
	var src := _terrain_image(kind)
	if src == null:
		return null
	var w := src.get_width()
	var h := src.get_height()

	var strip := Image.create(w * EDGE_COMBOS, h, false, Image.FORMAT_RGBA8)
	strip.fill(Color(0.0, 0.0, 0.0, 0.0))
	for bits in range(1, EDGE_COMBOS + 1):
		strip.blit_rect(_masked(src, bits), Rect2i(0, 0, w, h),
				Vector2i((bits - 1) * w, 0))

	var source := TileSetAtlasSource.new()
	source.texture = ImageTexture.create_from_image(strip)
	source.texture_region_size = Vector2i(w, h)
	for bits in range(1, EDGE_COMBOS + 1):
		source.create_tile(Vector2i(bits - 1, 0))
	return source


## `src` with its alpha multiplied by the ramp for the edges in `bits`.
func _masked(src: Image, bits: int) -> Image:
	var w := src.get_width()
	var h := src.get_height()
	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	out.fill(Color(0.0, 0.0, 0.0, 0.0))

	for y in range(h):
		# Normalised to the diamond: -1 at the top point, +1 at the bottom. Half-pixel
		# centres, so the extreme rows sample inside the tile rather than exactly on
		# its boundary where the ramp is degenerate.
		var ny := (y + 0.5) / (h * 0.5) - 1.0
		for x in range(w):
			var nx := (x + 0.5) / (w * 0.5) - 1.0
			var a := _edge_alpha(nx, ny, bits)
			if a <= 0.0:
				continue
			var c := src.get_pixel(x, y)
			c.a *= a
			out.set_pixel(x, y, c)
	return out


## How strongly the neighbour shows through at diamond coordinate (nx, ny), given the
## edges it is arriving from. The strongest edge wins rather than the sum, so a tile
## with water on two sides is not doubly transparent along the diagonal between them.
func _edge_alpha(nx: float, ny: float, bits: int) -> float:
	var best := 0.0
	for i in range(EDGE_OFFSETS.size()):
		if bits & (1 << i) == 0:
			continue
		var s: Vector2 = EDGE_SIGNS[i]
		# 1 exactly on that edge, -1 at the opposite point of the diamond.
		var f := s.x * nx + s.y * ny
		var a := (f - (1.0 - 2.0 * BLEND_REACH)) / (2.0 * BLEND_REACH)
		best = maxf(best, smoothstep(0.0, 1.0, clampf(a, 0.0, 1.0)))
	return best


## One terrain's tile as a plain Image, from the bake if there is one and from the
## declared placeholder if there is not.
##
## Separate from `_source_for`'s texture path on purpose: that one hands the TileSet an
## AtlasTexture pointing into the shared page, which costs nothing and is right for
## drawing. Masking needs the pixels themselves.
func _terrain_image(kind: int) -> Image:
	var visual_id: StringName = TERRAIN_VISUALS.get(kind, &"")
	if visual_id == &"":
		return null

	var entry := GameDataRegistry.atlas_for(visual_id)
	if entry.is_placeholder:
		return _placeholder_image(entry)

	var f := entry.frame_at(AtlasEntry.STATIC_ANIM, 0, 0)
	if f.is_empty():
		return null
	var page := entry.texture(int(f["page"]))
	if page == null:
		return null
	var img := page.get_image()
	if img == null:
		return null
	# An imported texture arrives in whatever format the importer chose, and
	# `get_region` and `get_pixel` both refuse a compressed one.
	if img.is_compressed():
		if img.decompress() != OK:
			return null
	var rect: Rect2i = f["rect"]
	return img.get_region(rect)


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
	return ImageTexture.create_from_image(_placeholder_image(entry))


func _placeholder_image(entry: AtlasEntry) -> Image:
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

	return img
