## Draws the fog of war over the ground (PLAN.md 2.5's `FogLayer`, listed as
## `src/view/fog_overlay.gd` in 6.3). Phase 2.5.
##
## A `TileMapLayer` for exactly the reasons `TerrainLayer` is one: the engine culls
## to the viewport and batches a chunk into a single draw call, so covering a 64x64
## map costs about what covering a 16x16 one does, and neither shows up against
## PLAN.md 3.1's <200 draw-call budget. A `_draw()` loop over 4096 diamonds would not
## survive contact with a phone.
##
## TWO TILES, and the third state is the absence of one:
##
##   UNSEEN    opaque black. Nothing has ever been there to see.
##   EXPLORED  half-transparent black. The ground is remembered, so terrain and any
##             remembered building show through, dimmed.
##   VISIBLE   no cell at all. Cheapest possible answer for the tiles that matter
##             most, since a player spends the match looking at these.
##
## **Takes vision bytes, never a SimPlayer.** Same rule `TerrainLayer` follows for
## terrain (PLAN.md 4): the view is handed the raw array the snapshot carries, which
## is all of the fog that rendering needs and exactly what a networked client
## receives. That also keeps this testable with a literal PackedByteArray.
##
## ONLY CHANGED TILES ARE TOUCHED. `apply()` diffs against the last array it was
## given, because a full sweep would be 4096 `set_cell()` calls ten times a second
## and each one dirties its rendering quadrant -- where what actually changes between
## two ticks is the rim of vision around whatever moved, which is tens of tiles.
class_name FogOverlay
extends TileMapLayer

## Source ids in the generated TileSet. They are the `SimPlayer.Fog` values they
## stand for, so a cell's source id IS its fog state and reading a cell back needs no
## second mapping to get out of step -- the same trick `TerrainLayer` plays with
## terrain kinds.
const SOURCE_UNSEEN := SimPlayer.Fog.UNSEEN
const SOURCE_EXPLORED := SimPlayer.Fog.EXPLORED

## How dark each state paints. Explored is a wash rather than a veil: it has to leave
## the terrain readable, because the whole point of remembering ground is being able
## to look at it.
const UNSEEN_COLOR := Color(0.02, 0.02, 0.04, 1.0)
const EXPLORED_COLOR := Color(0.02, 0.02, 0.04, 0.45)

## Matches TerrainLayer.QUADRANT_TILES, and for the same measured reason: small
## chunks cull far more tightly against an isometric diamond than large ones.
const QUADRANT_TILES := 8

var _size: Vector2i = Vector2i.ZERO
var _last: PackedByteArray = PackedByteArray()


## Prepare to cover a `size` grid. Safe to call again; drops whatever was drawn.
func build(size: Vector2i) -> void:
	_size = size
	_last = PackedByteArray()
	clear()
	if size.x <= 0 or size.y <= 0:
		return

	rendering_quadrant_size = QUADRANT_TILES
	tile_set = _build_tile_set()
	# Godot's isometric TileMapLayer has its own idea of where tile (0,0) sits;
	# measure the difference once so this layer and Iso agree, exactly as
	# TerrainLayer._align_to_iso does. Without it the fog would be offset from the
	# ground it is meant to be covering.
	position = Iso.tile_centre_to_world(Vector2i.ZERO) - map_to_local(Vector2i.ZERO)


## Paint `vision` (row-major `SimPlayer.Fog` bytes, as the snapshot carries it).
##
## An EMPTY array means the world has no fog -- see `SimPlayer.vision` -- and clears
## the overlay rather than blacking the map out, which is the same direction every
## other "no data yet" case in the view resolves in.
func apply(vision: PackedByteArray) -> void:
	if _size.x <= 0 or _size.y <= 0 or tile_set == null:
		return
	var count := _size.x * _size.y
	if vision.size() < count:
		if not _last.is_empty():
			clear()
			_last = PackedByteArray()
		return

	var fresh := _last.size() != count
	if fresh:
		_last.resize(count)
		_last.fill(255)          # a state no Fog value has, so every tile reads changed

	for i in range(count):
		var state := vision[i]
		if state == _last[i]:
			continue
		_last[i] = state
		var cell := Vector2i(i % _size.x, i / _size.x)
		if state == SimPlayer.Fog.VISIBLE:
			erase_cell(cell)
		else:
			set_cell(cell, state, Vector2i.ZERO)


func size() -> Vector2i:
	return _size


## What the overlay is currently drawing at `cell`: a `SimPlayer.Fog` value, with
## VISIBLE meaning "no cell". For tests, and for anything that later wants to ask
## whether a tap landed in the dark.
func fog_at(cell: Vector2i) -> int:
	var source := get_cell_source_id(cell)
	return SimPlayer.Fog.VISIBLE if source < 0 else source


func _build_tile_set() -> TileSet:
	var ts := TileSet.new()
	ts.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	ts.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_DOWN
	ts.tile_offset_axis = TileSet.TILE_OFFSET_AXIS_HORIZONTAL
	ts.tile_size = Vector2i(Iso.TILE_SIZE)
	ts.add_source(_diamond_source(UNSEEN_COLOR), SOURCE_UNSEEN)
	ts.add_source(_diamond_source(EXPLORED_COLOR), SOURCE_EXPLORED)
	return ts


func _diamond_source(color: Color) -> TileSetAtlasSource:
	var source := TileSetAtlasSource.new()
	source.texture = _diamond_texture(color)
	source.texture_region_size = Vector2i(Iso.TILE_SIZE)
	source.create_tile(Vector2i.ZERO)
	return source


## One tile-sized diamond in a flat colour.
##
## The same scanline fill `TerrainLayer._placeholder_texture()` uses, and copied
## rather than shared because the two want different things from it: that one is a
## stand-in for missing ART and belongs to the asset seam, this one is a deliberate
## piece of rendering. Sized to exactly one tile so the fog tessellates with the
## ground it covers.
static func _diamond_texture(color: Color) -> Texture2D:
	var w := int(Iso.TILE_SIZE.x)
	var h := int(Iso.TILE_SIZE.y)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	for y in range(h):
		var ny := absf((y + 0.5) / (h * 0.5) - 1.0)
		var half := (1.0 - ny) * (w * 0.5)
		for x in range(w):
			if absf((x + 0.5) - w * 0.5) <= half:
				img.set_pixel(x, y, color)

	return ImageTexture.create_from_image(img)
