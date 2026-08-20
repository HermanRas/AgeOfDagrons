## A `MapData` as a picture: one pixel per tile, terrain underneath, entities over it,
## start positions ringed (PLAN.md 1.6's preview).
##
## Shared by the skirmish screen and `dev_preview/preview_mapgen.tscn` on purpose. The
## dev tool had this first and the screen would have been the second implementation of
## it -- two pictures of the same map that could disagree about what it contains is
## exactly the kind of drift that makes a preview untrustworthy.
##
## **This is a rendering of the entity list, not the map format.** The `game_map_gen/`
## prototype used the pixels AS the format, which is why a town centre, a villager and
## a scout were all `ff0000` and could only be told apart by guessing at blob sizes
## (11.2 fix 2). Here the data is authoritative and the colours are free to be legible.
class_name MapPreview
extends TextureRect

const C_GRASS := Color("4caf50")
const C_SAND := Color("fff8e7")
const C_WATER := Color("0288d1")
const C_DEEP := Color("01579b")
const C_ROCK := Color("6d4c41")
const C_TREE := Color("1b5e20")
const C_GOLD := Color("ffd700")
const C_STONE := Color("9e9e9e")
const C_FOOD := Color("e91e63")
const C_TOWN := Color("d50000")
const C_UNIT := Color("ffffff")
const C_START := Color("00e5ff")


func _init() -> void:
	# NEAREST, or a 96-pixel image scaled to fit a panel turns into mush -- and the
	# whole point of the preview is being able to count tiles between things.
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Draw `data`, or clear to nothing when it is null.
func show_map(data: MapData) -> void:
	texture = render(data) if data != null else null


## One pixel per tile. `scale` is for callers writing a PNG to look at by eye
## (`preview_mapgen`); on screen the TextureRect does the scaling, so 1 is right there.
static func render(data: MapData, scale: int = 1) -> ImageTexture:
	if data == null or data.size.x <= 0 or data.size.y <= 0:
		return null
	var img := Image.create(data.size.x * scale, data.size.y * scale, false, Image.FORMAT_RGBA8)

	for y in range(data.size.y):
		for x in range(data.size.x):
			_blot(img, Vector2i(x, y), scale, terrain_colour(data.terrain_at(Vector2i(x, y))))

	# Entities over the ground, in list order, so a base drawn after its own clearing
	# wins rather than being painted over by it.
	for e in data.entities:
		var colour := entity_colour(e["def_id"])
		for t in MapData.footprint_rect_of(e):
			_blot(img, t, scale, colour)

	# Start rings last. A town centre is 10 tiles across and there is no other way to
	# see WHERE a player begins on a 192-tile map.
	for s in data.starts:
		for radius in range(6, 9):
			for degrees in range(0, 360, 12):
				var t := s + Vector2i(Vector2(cos(deg_to_rad(degrees)),
						sin(deg_to_rad(degrees))) * float(radius))
				_blot(img, t, scale, C_START)

	return ImageTexture.create_from_image(img)


static func terrain_colour(kind: int) -> Color:
	match kind:
		SimMap.Terrain.SAND: return C_SAND
		SimMap.Terrain.WATER_SHALLOW: return C_WATER
		SimMap.Terrain.WATER_DEEP: return C_DEEP
		SimMap.Terrain.ROCK: return C_ROCK
		SimMap.Terrain.FOREST: return C_TREE
		SimMap.Terrain.DIRT: return C_SAND.darkened(0.25)
		_: return C_GRASS


static func entity_colour(def_id: StringName) -> Color:
	match def_id:
		&"res.tree": return C_TREE
		&"res.gold_mine": return C_GOLD
		&"res.stone": return C_STONE
		&"res.berry_bush": return C_FOOD
		&"building.town_center": return C_TOWN
		_: return C_UNIT


static func _blot(img: Image, tile: Vector2i, scale: int, colour: Color) -> void:
	for dy in range(scale):
		for dx in range(scale):
			var px := tile.x * scale + dx
			var py := tile.y * scale + dy
			if px >= 0 and py >= 0 and px < img.get_width() and py < img.get_height():
				img.set_pixel(px, py, colour)
