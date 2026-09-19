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
##
## ⚠️ **THE TWO BRIDGE KINDS ARE DELIBERATELY ABSENT.** One terrain, one sprite is the
## assumption this table encodes, and a bridge breaks it -- see `BRIDGE_PIECES`. Being
## missing from here is load-bearing rather than an oversight: `_terrain_image()` reads
## this table and returning null for a bridge is what keeps the blend layer off it.
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

## The four EDGE-sharing neighbours, bits 0-3. In this projection these are the NE,
## SE, SW and NW sides on screen.
const EDGE_OFFSETS := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

## Sign pair per edge for the diamond's own equation. A tile is |X| + |Y| <= 1 about
## its centre, and each of its four sides is where `sx*X + sy*Y == 1` -- so this is
## both which side a bit means and the distance function that fades away from it.
const EDGE_SIGNS := [Vector2(1.0, -1.0), Vector2(1.0, 1.0),
		Vector2(-1.0, 1.0), Vector2(-1.0, -1.0)]

## The four CORNER-sharing neighbours, bits 4-7, each between the two edges of the same
## index and the next -- corner 0 sits between edge 0 (NE) and edge 1 (SE), which is the
## diamond's right-hand point. On screen these four are right, down, left, up.
##
## ⚠️ **THAT LAST SENTENCE READ "straight up, right, down, left" UNTIL 2026-09-19 AND WAS
## ROTATED BY ONE**, contradicting the sentence before it, which was right. Spotted by the
## art side while cutting the bridge set and confirmed here from the offsets: corner c is
## `EDGE_OFFSETS[c] + EDGE_OFFSETS[c + 1]`, so corner 0 is `(0,-1) + (1,0) = (1,-1)`, the
## east point. Nothing read the comment, so nothing was broken -- but **the cliff set will
## read these bits**, and a corner-bit table wired from the wrong sentence would come out
## a quarter turn off with every individual piece looking correct.
## THEY WERE LEFT OUT OF THE FIRST VERSION and the project owner reported the result in
## one word: "the diagonals need work". A tile touching another terrain only at a VERTEX
## got no blend at all, so every step of the staircase kept one hard point -- the soft
## edges made those points MORE conspicuous, not less, because they were then the only
## crisp thing left on the boundary.
const CORNER_OFFSETS := [Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(-1, -1)]

## A corner's ramp peaks at one POINT rather than along a line, and `min` of its two
## adjacent edge functions is exactly that: both reach 1 at their shared vertex and at
## least one is negative everywhere else on the diamond.
##
## A corner bit is dropped whenever either adjacent edge carries the same terrain, since
## an edge ramp is already opaque along its whole length INCLUDING both its endpoints.
## That is what keeps the variant count at 47 rather than 256 -- the classic blob set,
## arrived at here for the same reason it exists everywhere else.
const CORNER_BIT := 4

## THE BRIDGE, and it is the one terrain whose tile is not a single fixed diamond.
##
## Every other kind here is one flat sprite repeated. A bridge tile's piece is chosen
## from its NEIGHBOURS -- a deck mid-span, a kerbed rail down each long side -- so one
## terrain byte needs four different frames and the cell's atlas coordinate is what
## picks between them. `_build_tile_set` packs those four into a strip and this table
## is the strip.
##
## ⛔ **THIS TABLE IS THE ART SIDE'S, MEASURED, NOT DERIVED** (asset_request.md,
## 2026-09-19). Two of its numbers cannot be re-derived from anything on this side:
##
## - **Only stored 1, 3, 5 and 7 are usable.** `directions` rotates the object and a
##   square tile only lands on its own diamond at multiples of 90 degrees, so stored
##   0/2/4/6 trim to a 46 x 24 RECTANGLE. They are baked, they are in the atlas, and
##   they must never be drawn.
## - **The kerb lands on the edge OPPOSITE the direction's name** -- stored 1 is "SW"
##   and puts the kerb on NE. That was measured by differencing the rail bake against
##   the deck bake frame by frame, because the 8-direction path applies a base yaw of
##   its own. **Do not re-derive it from the yaw and expect the same answer.**
##
## `cross` names the two EDGE bits facing the bridge's long sides -- the only two bits
## read. A bridge is a ribbon, so its corner neighbours decide nothing.
const BRIDGE_PIECES := {
	SimMap.Terrain.BRIDGE_X: {
		"cross": [0, 2],                          # NE (0,-1) and SW (0,+1)
		"columns": [
			[&"vis.bridge_deck", 1],              # 0: both long sides continue
			[&"vis.bridge_rail", 1],              # 1: NE is open -- kerb on NE
			[&"vis.bridge_rail", 5],              # 2: SW is open -- kerb on SW
			[&"vis.bridge_rail_both", 1],         # 3: a one-tile-wide bridge
		],
	},
	SimMap.Terrain.BRIDGE_Y: {
		"cross": [1, 3],                          # SE (+1,0) and NW (-1,0)
		"columns": [
			[&"vis.bridge_deck", 3],
			[&"vis.bridge_rail", 3],              # 1: SE is open -- kerb on SE
			[&"vis.bridge_rail", 7],              # 2: NW is open -- kerb on NW
			[&"vis.bridge_rail_both", 3],
		],
	},
}

var _size: Vector2i = Vector2i.ZERO

## Drawn above this layer because it is a CHILD of it: Godot draws a parent CanvasItem
## and then its children, and the whole terrain subtree still comes before the entity
## pool, which is GameView's next sibling. So it covers the ground and nothing else.
var _blend: TileMapLayer = null

## canonical mask -> strip column, and its inverse. Built once for the class: the set
## of 47 is a property of the geometry, not of any particular map.
static var _mask_column: Dictionary = {}
static var _mask_at_column: Array[int] = []


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
			if not tile_set.has_source(kind):
				continue
			var t := Vector2i(x, y)
			# Every other terrain is one diamond at column 0; a bridge picks one of four
			# by what its long-side neighbours are. Same source id either way, so a cell
			# still reads back as its own terrain.
			var column := 0 if not SimMap.is_bridge(kind) \
					else bridge_column(kind, _bridge_edges(size, terrain, t))
			set_cell(t, kind, Vector2i(column, 0))

	_build_blend(size, terrain)


func size() -> Vector2i:
	return _size


## The transition layer, or null before the first `build()`. A test seam: the blend is
## invisible to every other caller and there is nothing here to configure.
func blend_layer() -> TileMapLayer:
	return _blend


## Which neighbours the transition at `tile` is reaching in from, as a canonical mask,
## or 0 for none. A test seam: the column a cell points at is an index into a packed
## strip and says nothing readable on its own.
func blend_mask_at(tile: Vector2i) -> int:
	if _blend == null:
		return 0
	var column := _blend.get_cell_atlas_coords(tile)
	if column.x < 0 or column.x >= _mask_at_column.size():
		return 0
	return _mask_at_column[column.x]


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
			# ⛔ **A BRIDGE NEITHER RECEIVES A TRANSITION NOR CASTS ONE**, and the first
			# half is the one that bites. `BLEND_ORDER` has no bridge row, so a bridge
			# scores 0 -- below deep water -- and every deck tile in a river would have
			# had water faded across it from both banks. The blend exists to soften a
			# staircase between two ground textures; a bridge is a built thing standing
			# on the ground, and its edge is meant to be crisp.
			if SimMap.is_bridge(mine):
				continue
			var over := _dominant_neighbour(size, terrain, t, mine)
			if over < 0 or not _blend.tile_set.has_source(over):
				continue
			var bits := _edges_facing(size, terrain, t, over)
			if bits == 0:
				continue
			_blend.set_cell(t, over, Vector2i(int(_mask_column[bits]), 0))


## The neighbouring terrain that should reach over `mine`, or -1 for none. Highest
## `BLEND_ORDER` wins; ties cannot happen because a tie means the same terrain.
## ALL EIGHT NEIGHBOURS, edges and corners alike. Scanning only the edges was the
## other half of the diagonal bug: a tile whose sole higher-order neighbour met it at a
## vertex was rejected here and never reached the mask at all, so the corner ramps
## could not have helped it however correct they were.
func _dominant_neighbour(size: Vector2i, terrain: PackedByteArray, t: Vector2i,
		mine: int) -> int:
	var best := -1
	var best_order: int = BLEND_ORDER.get(mine, 0)
	for offsets in [EDGE_OFFSETS, CORNER_OFFSETS]:
		for offset in offsets:
			var n: Vector2i = t + offset
			if n.x < 0 or n.y < 0 or n.x >= size.x or n.y >= size.y:
				continue
			var kind: int = terrain[n.y * size.x + n.x]
			var order: int = BLEND_ORDER.get(kind, 0)
			if order > best_order:
				best_order = order
				best = kind
	return best


## Which of `t`'s eight neighbours are `kind`: bits 0-3 the edges, 4-7 the corners,
## already canonicalised so a corner shadowed by one of its edges is dropped.
func _edges_facing(size: Vector2i, terrain: PackedByteArray, t: Vector2i,
		kind: int) -> int:
	var bits := 0
	for i in range(EDGE_OFFSETS.size()):
		if _terrain_at_is(size, terrain, t + EDGE_OFFSETS[i], kind):
			bits |= 1 << i
	for i in range(CORNER_OFFSETS.size()):
		if _terrain_at_is(size, terrain, t + CORNER_OFFSETS[i], kind):
			bits |= 1 << (CORNER_BIT + i)
	return canonical_mask(bits)


func _terrain_at_is(size: Vector2i, terrain: PackedByteArray, n: Vector2i,
		kind: int) -> bool:
	if n.x < 0 or n.y < 0 or n.x >= size.x or n.y >= size.y:
		return false
	return int(terrain[n.y * size.x + n.x]) == kind


## `bits` with every corner dropped that one of its own edges already covers. Two masks
## that canonicalise the same draw the same picture, which is what collapses 256
## combinations to 47.
static func canonical_mask(bits: int) -> int:
	var out := bits & 0x0F
	for c in range(CORNER_OFFSETS.size()):
		if bits & (1 << (CORNER_BIT + c)) == 0:
			continue
		# The two edges either side of corner c. Either one being present makes the
		# corner redundant -- an edge ramp is opaque right up to both its endpoints.
		if bits & (1 << c) != 0 or bits & (1 << ((c + 1) % 4)) != 0:
			continue
		out |= 1 << (CORNER_BIT + c)
	return out


## Every distinct canonical mask, lowest first. Column `i` of a blend strip is
## `_mask_at_column[i]`.
static func _mask_table() -> Array[int]:
	if not _mask_at_column.is_empty():
		return _mask_at_column
	var seen: Dictionary = {}
	for bits in range(1 << 8):
		seen[canonical_mask(bits)] = true
	var keys: Array = seen.keys()
	keys.sort()
	for i in range(keys.size()):
		var m := int(keys[i])
		if m == 0:
			continue          # nothing to draw; never gets a column
		_mask_column[m] = _mask_at_column.size()
		_mask_at_column.append(m)
	return _mask_at_column


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

	var masks := _mask_table()
	var strip := Image.create(w * masks.size(), h, false, Image.FORMAT_RGBA8)
	strip.fill(Color(0.0, 0.0, 0.0, 0.0))
	for i in range(masks.size()):
		strip.blit_rect(_masked(src, masks[i]), Rect2i(0, 0, w, h), Vector2i(i * w, 0))

	var source := TileSetAtlasSource.new()
	source.texture = ImageTexture.create_from_image(strip)
	source.texture_region_size = Vector2i(w, h)
	for i in range(masks.size()):
		source.create_tile(Vector2i(i, 0))
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
		# 1 exactly on that edge, -1 at the opposite point of the diamond.
		best = maxf(best, _ramp(_edge_field(nx, ny, i)))
	for c in range(CORNER_OFFSETS.size()):
		if bits & (1 << (CORNER_BIT + c)) == 0:
			continue
		# A point, not a line: `min` of the two edges meeting at that vertex is 1
		# there and below 1 everywhere else, so the ramp closes to a rounded cap
		# over the corner instead of washing along a whole side.
		best = maxf(best, _ramp(minf(_edge_field(nx, ny, c),
				_edge_field(nx, ny, (c + 1) % 4))))
	return best


## The diamond's own edge equation for edge `i`: 1 along that side, -1 at the point
## opposite it.
func _edge_field(nx: float, ny: float, i: int) -> float:
	var s: Vector2 = EDGE_SIGNS[i]
	return s.x * nx + s.y * ny


func _ramp(f: float) -> float:
	var a := (f - (1.0 - 2.0 * BLEND_REACH)) / (2.0 * BLEND_REACH)
	return smoothstep(0.0, 1.0, clampf(a, 0.0, 1.0))


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


## Which column of `kind`'s strip a tile with this edge nibble draws. `mask` bits are
## `EDGE_OFFSETS` order, set where that neighbour is ALSO a bridge -- either byte, since
## the two are one surface and a bend between them is still a continuous deck.
##
## Static and public: it is the whole of the art side's table in four lines, and a test
## can exercise every case of it without a texture, an atlas or a tree.
static func bridge_column(kind: int, mask: int) -> int:
	var cross: Array = (BRIDGE_PIECES[kind] as Dictionary)["cross"]
	var first := mask & (1 << int(cross[0])) != 0
	var second := mask & (1 << int(cross[1])) != 0
	if first and second:
		return 0                       # mid-span: deck
	if second:
		return 1                       # cross[0] is the open side
	if first:
		return 2                       # cross[1] is the open side
	return 3                           # open both sides: a one-tile-wide bridge


## Which of `t`'s four EDGE neighbours are bridge, as bits 0-3.
##
## The corners are not gathered at all, unlike `_edges_facing`. A bridge is a ribbon:
## the art side's table reads the edge nibble and nothing else, so collecting four more
## bits would only invite a later reader to believe they mean something.
func _bridge_edges(size: Vector2i, terrain: PackedByteArray, t: Vector2i) -> int:
	var bits := 0
	for i in range(EDGE_OFFSETS.size()):
		var n: Vector2i = t + EDGE_OFFSETS[i]
		if n.x < 0 or n.y < 0 or n.x >= size.x or n.y >= size.y:
			continue
		if SimMap.is_bridge(int(terrain[n.y * size.x + n.x])):
			bits |= 1 << i
	return bits


## The four pieces of one bridge axis, packed across a single strip -- the same shape
## `_blend_source_for` uses, and for the same reason: a TileSetAtlasSource addresses one
## texture by grid coordinate, so four frames means four columns of one image.
##
## ⚠️ **THE FRAMES ARE NOT ALL THE SAME SIZE AND ARE NOT ALL TILE-SIZED.** A rail trims
## to 65 x 42 where a bare tile is 64 x 34, because its kerb stands 0.410 m above the
## deck and that is 8 px of screen Y. So the cell is sized to hold the largest of them
## **about their anchors**, and each frame is blitted so its own anchor lands at the
## cell's centre -- which is where Godot puts a tile's origin. Packing them flush left,
## or sizing the cell to the largest frame and centring each one in it, both draw a
## bridge whose kerb shifts by a pixel or two from tile to tile.
func _bridge_source_for(kind: int) -> TileSetAtlasSource:
	var columns: Array = (BRIDGE_PIECES[kind] as Dictionary)["columns"]

	# Gathered before anything is sized: the cell has to fit all four at once.
	var images: Array[Image] = []
	var anchors: Array[Vector2i] = []
	for column in columns:
		var got := _bridge_frame(column[0] as StringName, int(column[1]))
		if got.is_empty():
			return null
		images.append(got["image"] as Image)
		anchors.append(got["anchor"] as Vector2i)

	var half := Vector2i.ZERO
	for i in range(images.size()):
		var img: Image = images[i]
		var a: Vector2i = anchors[i]
		half.x = maxi(half.x, maxi(a.x, img.get_width() - a.x))
		half.y = maxi(half.y, maxi(a.y, img.get_height() - a.y))

	var cell := half * 2
	var strip := Image.create(cell.x * images.size(), cell.y, false, Image.FORMAT_RGBA8)
	strip.fill(Color(0.0, 0.0, 0.0, 0.0))
	for i in range(images.size()):
		var img: Image = images[i]
		# `blit_rect` refuses a source in a different format from the destination, and
		# the four pieces do not have to agree: a staged page arrives in whatever the
		# importer chose and a placeholder is built RGBA8 here. A bridge with two pieces
		# baked and one missing is exactly the state a half-finished re-bake leaves.
		if img.get_format() != Image.FORMAT_RGBA8:
			img.convert(Image.FORMAT_RGBA8)
		strip.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()),
				Vector2i(i * cell.x, 0) + half - anchors[i])

	var source := TileSetAtlasSource.new()
	source.texture = ImageTexture.create_from_image(strip)
	source.texture_region_size = cell
	for i in range(images.size()):
		source.create_tile(Vector2i(i, 0))
	return source


## One piece's frame as a standalone image plus the anchor within it, or {} if the
## seam cannot produce one.
##
## An undeclared or unbaked piece falls back to the placeholder diamond rather than to
## nothing, so `atlas_for` stays total here the way it is everywhere else: a bridge with
## no art is a loud magenta crossing, not a hole in the river.
func _bridge_frame(visual_id: StringName, stored: int) -> Dictionary:
	var entry := GameDataRegistry.atlas_for(visual_id)
	if entry.is_placeholder:
		var flat := _placeholder_image(entry)
		return {"image": flat, "anchor": flat.get_size() / 2}

	var f := entry.frame_at(AtlasEntry.STATIC_ANIM, _facing_for_stored(entry, stored), 0)
	if f.is_empty():
		return {}
	var page := entry.texture(int(f["page"]))
	if page == null:
		return {}
	var img := page.get_image()
	if img == null:
		return {}
	if img.is_compressed() and img.decompress() != OK:
		return {}

	var rect: Rect2i = f["rect"]
	var cut := img.get_region(rect)
	var anchor: Vector2 = f["anchor"]
	# Belt and braces: this bake is `mirror_for_8: false`, so nothing is flipped today.
	# A re-bake that turned mirroring on would otherwise put every kerb on the wrong
	# side of the deck silently -- and a kerb on the wrong side is a picture that still
	# looks like a bridge.
	if bool(f["flip_x"]):
		cut.flip_x()
		anchor.x = float(cut.get_width()) - anchor.x
	return {"image": cut, "anchor": Vector2i(roundi(anchor.x), roundi(anchor.y))}


## The facing index whose entry in the atlas's own direction table stores `stored`.
##
## `frame_at` takes a FACING and looks the stored index up; the art side's table names
## STORED indices, because that is what it measured off the packed page. Searching the
## table rather than assuming they coincide -- they do in this bake -- is what keeps the
## two from drifting apart in a re-bake that reorders or mirrors.
static func _facing_for_stored(entry: AtlasEntry, stored: int) -> int:
	for i in range(entry.dir_table.size()):
		if int((entry.dir_table[i] as Dictionary)["stored_index"]) == stored:
			return i
	return stored


func _source_for(kind: int) -> TileSetAtlasSource:
	if SimMap.is_bridge(kind):
		return _bridge_source_for(kind)

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
