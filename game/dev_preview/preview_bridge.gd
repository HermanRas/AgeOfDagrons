## Dev check for the river bridge (card 2.x-river-bridge): draw one and look at it.
##
## ⛔ **THE SUITE CANNOT JUDGE THIS AND SHOULD NOT BE ASKED TO.** `test_terrain_layer`'s
## bridge section pins which COLUMN each tile picks, which is the art side's table read
## correctly. It says nothing about whether the result is a bridge. Three faults live
## entirely in the gap, and every one of them passes a green suite:
##
## - **a kerb on the wrong long side**, because `BRIDGE_PIECES` maps a stored direction
##   to an edge and that mapping was MEASURED off the bake rather than derived. A bridge
##   with both rails on the same side is still a bridge in a table;
## - **a frame placed off its anchor**, which shifts the planks a pixel or two per tile
##   and turns a deck into a zigzag. The rails trim to 65 x 42 where a bare tile is
##   64 x 34, so they are the one terrain in the game that does not fill its own cell;
## - **a kerb eaten by the tile behind it.** 8 px of it stand above the diamond, and
##   whether a TileMapLayer draws the cell behind first is a question about Godot's
##   quadrant ordering that no assertion here could ask.
##
## So this takes pictures. It also prints the two things a picture cannot settle: the
## frame each column actually resolved to, and where its anchor sits -- because "the
## kerb is on the wrong side" and "the whole frame is offset" look identical at 1:1 and
## want opposite fixes.
##
## ⚠️ **READ BOTH AXES.** `BRIDGE_X` and `BRIDGE_Y` are separate rows of the table and
## each is self-consistent, so a bridge that is right in one axis proves nothing about
## the other -- the same blindness that let a MIRRORED roster pass the facing check
## twice (AGENT_GAME_CODER.md §3).
##
## Usage:
##   Godot --path game res://dev_preview/preview_bridge.tscn
##       -- writes user://bridge_*.png and quits.
##   ... -- --seed 11        -- which River seed the real-map shot uses.
extends Node2D

const SHOT_DIR := "user://"
const WINDOW := Vector2i(1280, 800)
const SETTLE_FRAMES := 12

## The synthetic span: long enough to have a middle as well as two ends, and wide
## enough that a kerb on the wrong side is obvious rather than arguable.
const RUN := 9
const WIDE := 5

var _layer: TerrainLayer = null
var _step := 0
var _frames := 0
var _seed := 11


func _ready() -> void:
	get_window().size = WINDOW
	get_window().content_scale_size = WINDOW
	_seed = _seed_argument()
	_report_the_pieces()
	_build_synthetic(SimMap.Terrain.BRIDGE_Y)


func _seed_argument() -> int:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		if args[i] == "--seed":
			return int(args[i + 1])
	return 11


func _process(_delta: float) -> void:
	_frames += 1
	if _frames < SETTLE_FRAMES:
		return
	_frames = 0
	match _step:
		0:
			_shoot("bridge_axis_y")
			_build_synthetic(SimMap.Terrain.BRIDGE_X)
		1:
			_shoot("bridge_axis_x")
			_build_synthetic(SimMap.Terrain.BRIDGE_Y, 1)
		2:
			_shoot("bridge_one_wide")
			_build_real_river()
		3:
			_shoot("bridge_river_seed_%d" % _seed)
			get_tree().quit()
	_step += 1


# ── what the seam actually resolved ────────────────────────────────────────

## ⚠️ **THE FRAME SIZES ARE THE HALF OF THIS THAT SURVIVES A BAD SCREENSHOT.** If the
## window comes out black, or the camera lands somewhere else, this still says whether
## the four pieces resolved and whether any of them came back as a 46 x 24 rectangle --
## which is what a 45-degree frame trims to and is the single most likely way to draw a
## bridge out of the wrong art while every test passes.
func _report_the_pieces() -> void:
	print("\n── the pieces, per axis ──")
	for kind in TerrainLayer.BRIDGE_PIECES:
		print("  %s" % SimMap.Terrain.keys()[kind])
		var columns: Array = (TerrainLayer.BRIDGE_PIECES[kind] as Dictionary)["columns"]
		for i in range(columns.size()):
			var id: StringName = columns[i][0]
			var stored := int(columns[i][1])
			var entry := GameDataRegistry.atlas_for(id)
			if entry.is_placeholder:
				print("    col %d  %-22s stored %d  PLACEHOLDER (not staged)"
						% [i, id, stored])
				continue
			var facing := _facing_for_stored(entry, stored)
			var f := entry.frame_at(AtlasEntry.STATIC_ANIM, facing, 0)
			if f.is_empty():
				print("    col %d  %-22s stored %d  NO FRAME" % [i, id, stored])
				continue
			var rect: Rect2i = f["rect"]
			var anchor: Vector2 = f["anchor"]
			var flag := ""
			# A tile is 64 x 34 off this bake. Anything near 46 x 24 is a 45-degree
			# frame and must never have been asked for.
			if rect.size.x < 56:
				flag = "  ⛔ RECTANGLE, not a tile"
			elif rect.size.y > 36:
				flag = "  (stands %d px above a bare tile)" % (rect.size.y - 34)
			print("    col %d  %-22s stored %d  %d x %d  anchor %.1f, %.1f%s"
					% [i, id, stored, rect.size.x, rect.size.y, anchor.x, anchor.y, flag])


func _facing_for_stored(entry: AtlasEntry, stored: int) -> int:
	for i in range(entry.dir_table.size()):
		if int((entry.dir_table[i] as Dictionary)["stored_index"]) == stored:
			return i
	return stored


# ── the two subjects ───────────────────────────────────────────────────────

## A bare span over open water, which is the shape the table was written against and
## the one where a wrong kerb has nothing to hide behind.
func _build_synthetic(kind: int, wide: int = WIDE) -> void:
	var size := Vector2i(WIDE + 8, RUN + 8) if kind == SimMap.Terrain.BRIDGE_Y \
			else Vector2i(RUN + 8, WIDE + 8)
	var bytes := PackedByteArray()
	bytes.resize(size.x * size.y)
	for i in range(bytes.size()):
		bytes[i] = SimMap.Terrain.WATER_SHALLOW
	# Grass banks at both ends, so the deck is seen MEETING something rather than
	# stopping in open water -- the join is half of what makes it read as a bridge.
	for y in range(size.y):
		for x in range(size.x):
			var along := y if kind == SimMap.Terrain.BRIDGE_Y else x
			if along < 4 or along >= (RUN + 4):
				bytes[y * size.x + x] = SimMap.Terrain.GRASS
	for i in range(RUN):
		for j in range(wide):
			var t := Vector2i(4 + j, 4 + i) if kind == SimMap.Terrain.BRIDGE_Y \
					else Vector2i(4 + i, 4 + j)
			bytes[t.y * size.x + t.x] = kind
	_show(size, bytes)


## And the real thing, through the real generator, because the synthetic span is a
## shape I chose and the generated crossing is the shape the game ships.
func _build_real_river() -> void:
	var data := MapGenerator.generate(_seed, MapGenerator.Type.RIVER, 2)
	var count := 0
	for i in range(data.terrain.size()):
		if SimMap.is_bridge(int(data.terrain[i])):
			count += 1
	print("\n── seed %d, the generated river ──" % _seed)
	print("  %d x %d, %d bridge tiles" % [data.size.x, data.size.y, count])
	if count == 0:
		push_warning("the generated river has no bridge terrain on it at all")
	_show(data.size, data.terrain, _first_bridge(data))


func _first_bridge(data: MapData) -> Vector2i:
	for y in range(data.size.y):
		for x in range(data.size.x):
			if SimMap.is_bridge(data.terrain_at(Vector2i(x, y))):
				return Vector2i(x, y)
	return data.size / 2


# ── drawing ────────────────────────────────────────────────────────────────

func _show(size: Vector2i, bytes: PackedByteArray, centre_on := Vector2i(-1, -1)) -> void:
	if _layer != null:
		_layer.queue_free()
	_layer = TerrainLayer.new()
	add_child(_layer)
	_layer.build(size, bytes)
	var centre := centre_on if centre_on.x >= 0 else size / 2
	# The layer draws in Iso's world space; put the tile of interest in the middle of
	# the window rather than wherever tile (0, 0) happens to project to.
	_layer.position += Vector2(WINDOW) * 0.5 - Iso.tile_centre_to_world(centre)


func _draw() -> void:
	# A flat backdrop. A pale deck judged against whatever the window last held is not
	# a judgement about the deck.
	draw_rect(Rect2(Vector2.ZERO, Vector2(WINDOW)), Color(0.10, 0.12, 0.16))


func _shoot(name: String) -> void:
	var path := SHOT_DIR + name + ".png"
	get_viewport().get_texture().get_image().save_png(path)
	print("wrote ", ProjectSettings.globalize_path(path))
