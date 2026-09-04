## CAN YOU SEE AN ALLY ON THE MINIMAP, AND CAN YOU SEE ONE ON THE WATER?
##
## Exists for `preview_projectiles`' reason, which is the strongest one in this folder:
## a blip is TWO PIXELS and its entire job is to be looked at, so a green suite proves
## nothing about it. The project owner asked the question directly (2026-08-31, *"a
## diffrent color maybe sky blue if its not to close to the water colour"*) and it is
## not answerable from a colour swatch — it is answerable from a picture of four blip
## colours sitting on the three terrains they have to be told apart from.
##
## THE WIDGET, NOT A MATCH. `Minimap.update_entities` is a pure fact-to-colour mapping
## and `build_terrain` takes raw bytes, so standing up a whole 2v2 to photograph two
## pixels would be a great deal of machinery between the question and the answer — and
## it would leave the ships, which is the case that matters, up to where the generator
## felt like putting the water.
##
## ⚠️ **IT SAVES A 6x NEAREST-NEIGHBOUR CROP AS WELL AS THE SCREENSHOT**, and that is
## the half worth copying. At 1:1 a minimap blip is a couple of pixels of a 240 px
## diamond: "I cannot see it" and "it is not drawn" look identical, which is exactly
## the trap `preview_projectiles` records paying for. The zoom is the picture somebody
## can actually judge a colour from.
##
## Usage:
##   Godot --path game res://dev_preview/preview_minimap_teams.tscn
extends Node

const SHOT_DIR := "user://"
const SETTLE_FRAMES := 20
const ZOOM := 6

## A small board, laid out so every blip colour lands on every terrain that could hide
## it: grass down the left, shallow water through the middle, deep water on the right.
const BOARD := Vector2i(48, 48)
const SHALLOW_BAND := Vector2i(16, 30)     # x range, inclusive-exclusive
const DEEP_BAND := Vector2i(30, 48)

## Which owner sits where. Player 1 is us, 2 is our ally, 3 the enemy, 0 gaia — and each
## gets one blip on each of the three terrains, so the picture is a 4x3 grid of the only
## question this page asks.
const OWNERS := [1, 2, 3, 0]
const ROW_SPACING := 6
const COLUMN_X := [6, 22, 38]              # grass, shallow, deep

var _minimap: Minimap
var _frames := 0
var _shot := false


func _ready() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = HudStyle.DARK_BG
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	_minimap = Minimap.new()
	# CENTRED BY HAND rather than dropped in a container, because the control spins 45°
	# about its own pivot and Godot's containers place a rotated child by its UNROTATED
	# rect — the trap `SkirmishScreen._framed_preview` records in full.
	_minimap.position = Vector2(360.0, 140.0)
	add_child(_minimap)

	_minimap.build_terrain(BOARD, _terrain())
	_minimap.update_entities(_facts(), 1, {}, {1: 1, 2: 1, 3: 2})

	add_child(_legend())


func _process(_delta: float) -> void:
	_frames += 1
	if _shot or _frames < SETTLE_FRAMES:
		return
	_shot = true
	_report()
	_shoot("minimap_teams")
	get_tree().quit()


## Grass, a shallow channel and a deep one. Row-major `SimMap.Terrain` bytes, which is
## exactly what a snapshot's `terrain` carries.
func _terrain() -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(BOARD.x * BOARD.y)
	for y in range(BOARD.y):
		for x in range(BOARD.x):
			var kind := SimMap.Terrain.GRASS
			if x >= DEEP_BAND.x:
				kind = SimMap.Terrain.WATER_DEEP
			elif x >= SHALLOW_BAND.x:
				kind = SimMap.Terrain.WATER_SHALLOW
			bytes[y * BOARD.x + x] = kind
	return bytes


## One blip per owner per terrain, in `GameView.all_facts()`'s shape.
func _facts() -> Dictionary:
	var facts: Dictionary = {}
	var id := 1
	for row in range(OWNERS.size()):
		for column_x in COLUMN_X:
			facts[id] = {
				"id": id,
				"tile": Vector2i(column_x, 8 + row * ROW_SPACING),
				"owner_id": int(OWNERS[row]),
				"alive": true,
			}
			id += 1
	return facts


## What each colour is, in words, beside the picture. The whole point of the page is a
## judgement about colour, and a reader who has to count rows to work out which one is
## the ally is being asked the wrong question.
func _legend() -> Control:
	var column := VBoxContainer.new()
	column.position = Vector2(24.0, 24.0)
	column.add_theme_constant_override("separation", 6)
	column.add_child(HudPanel.text_label("MINIMAP BLIPS ON GRASS / SHALLOW / DEEP", 16))
	for entry in [["you", Minimap.OWN_COLOR], ["ally", Minimap.ALLY_COLOR],
			["enemy", Minimap.OTHER_COLOR], ["gaia", Minimap.GAIA_COLOR],
			["hit (flash)", Minimap.DAMAGE_FLASH_COLOR]]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var chip := ColorRect.new()
		chip.color = entry[1]
		chip.custom_minimum_size = Vector2(18.0, 18.0)
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(chip)
		row.add_child(HudPanel.text_label("%s   L* %.0f"
				% [entry[0], _lightness(entry[1])], 14))
		column.add_child(row)
	return column


## The numbers behind the picture, so a disagreement between the two is settleable.
##
## CIE `L*` for every blip colour and every terrain it sits on. Lightness rather than
## hue because hue is what does NOT separate sky blue from shallow water — they are six
## degrees apart — and lightness is what does. Same measure the eight-player palette was
## chosen on (`web/server/app/player-colour-ladder.html`).
func _report() -> void:
	var terrains := {
		"grass": GameDataRegistry.placeholder_for(&"terrain.grass").color,
		"shallow": GameDataRegistry.placeholder_for(&"terrain.water_shallow").color,
		"deep": GameDataRegistry.placeholder_for(&"terrain.water_deep").color,
	}
	print("terrain L*:")
	for name in terrains:
		print("    %-8s %.0f  %s" % [name, _lightness(terrains[name]),
				Color(terrains[name]).to_html(false)])
	print("blip L* and its distance from each terrain:")
	for entry in [["you", Minimap.OWN_COLOR], ["ally", Minimap.ALLY_COLOR],
			["enemy", Minimap.OTHER_COLOR], ["gaia", Minimap.GAIA_COLOR]]:
		var l := _lightness(entry[1])
		var parts: Array[String] = []
		for name in terrains:
			parts.append("%s %.0f" % [name, absf(l - _lightness(terrains[name]))])
		print("    %-6s L* %-5.0f  %s" % [entry[0], l, ", ".join(parts)])
		# The pairing the owner asked about, and the only one with a floor on it.
		if entry[0] == "ally" and absf(l - _lightness(terrains["shallow"])) < 20.0:
			push_warning("preview_minimap_teams: the ally blip is too close to shallow "
					+ "water to be seen on it -- a ship would vanish")


func _lightness(c: Color) -> float:
	var y := 0.2126 * _linear(c.r) + 0.7152 * _linear(c.g) + 0.0722 * _linear(c.b)
	return (116.0 * pow(y, 1.0 / 3.0) - 16.0) if y > 0.008856 else (903.3 * y)


func _linear(channel: float) -> float:
	return channel / 12.92 if channel <= 0.04045 \
			else pow((channel + 0.055) / 1.055, 2.4)


## The screenshot, and the zoom that makes it readable.
##
## `INTERPOLATE_NEAREST`, never the default. A blip is a two-pixel dot and every
## smoothing filter turns it into a soft smudge halfway to the terrain colour underneath
## — which is precisely the judgement this page exists to support, ruined by the
## enlargement meant to support it.
func _shoot(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(SHOT_DIR + name + ".png")
	print("wrote ", ProjectSettings.globalize_path(SHOT_DIR + name + ".png"))

	# CENTRED ON THE DIAMOND, WHICH IS NOT THE CONTROL'S POSITION. `Minimap` rotates 45°
	# about its own middle, so the diamond's bounding box is centred at the control's
	# centre with a half-extent of `SIZE / sqrt(2)` — the same relation `SIZE` itself is
	# derived from. Cropping from `position` instead sliced the top row of blips off.
	var area := int(Minimap.SIZE * 1.42) + 16
	var centre := _minimap.position + Vector2(Minimap.SIZE, Minimap.SIZE) * 0.5
	var crop := img.get_region(Rect2i(
			Vector2i(centre) - Vector2i(area, area) / 2, Vector2i(area, area)))
	crop.resize(area * ZOOM, area * ZOOM, Image.INTERPOLATE_NEAREST)
	crop.save_png(SHOT_DIR + name + "_zoom.png")
	print("wrote ", ProjectSettings.globalize_path(SHOT_DIR + name + "_zoom.png"))
