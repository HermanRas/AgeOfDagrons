## The minimap (PLAN.md 8.2a): baked terrain colours, entity blips, tap to move
## the camera there (3.8), and double-tap to centre on the player's own Town
## Centre (3.4). No camera-viewport rectangle -- dropped per UI_Design.md, the
## diamond reads better without one.
##
## No dedicated minimap frame exists in the Kibyra pack (ASSET_MISSING.md
## 1.5) -- UI_Design.jpg's ornate diamond frame is approximated by drawing an
## ordinary square (double gold rectangle border, `HudStyle.GOLD`) and rotating
## the whole control 45 degrees in `_init()`, rather than a fallback "left
## missing" rectangle.
##
## Terrain is baked into a small `Image` once per `build_terrain()` call --
## the same placeholder-colour trick `TerrainLayer._placeholder_texture()`
## already uses per-tile, at minimap scale instead. Entities are cheap to
## redraw fresh every snapshot since they move every tick.
class_name Minimap
extends Control

## The square itself, before the 45-degree rotation `_init()` applies to turn
## it into UI_Design.jpg's diamond frame. `AREA_SIZE` is the footprint
## GameScene reserves for it (the rotated bounding box plus a little room for
## the diamond's tips), used to centre this square inside that footprint.
const SIZE := 150.0
const AREA_SIZE := 200.0
const OWN_COLOR := Color(0.35, 1.0, 0.45)
const OTHER_COLOR := Color(1.0, 0.35, 0.3)
const GAIA_COLOR := Color(0.55, 0.5, 0.35, 0.7)
const FRAME_COLOR := Color("#E5B842")   # HudStyle.GOLD -- not a constant expression to reference directly
const _FRAME_OUTER_WIDTH := 4.0
const _FRAME_INNER_WIDTH := 1.5
const _FRAME_INSET := 4.0

## Tap moves the camera there (3.8); double tap centres on the player's own
## Town Centre (3.4) instead -- `GameScene` resolves the latter since finding
## "my Town Centre" is a `GameView` question, not this widget's.
signal tapped(tile: Vector2i)
signal double_tapped()

var _map_size: Vector2i = Vector2i.ZERO
var _terrain_tex: ImageTexture = null
var _blips: Array[Dictionary] = []          # [{tile: Vector2i, color: Color}]
var _double_tap := DoubleTapDetector.new()

## The fog, as its own texture over the terrain one (PLAN.md 2.5). A second image
## rather than baking the fog into `_terrain_tex`, because the two change on
## completely different clocks: terrain is built once per match and the fog moves
## every tick, so combining them would mean re-colouring every tile of the map ten
## times a second to move one villager.
##
## Blips are drawn BETWEEN the two (see `_draw`), so an enemy blip cannot show through
## ground the player has not explored -- which would give away on the minimap exactly
## what the snapshot filter withheld from the map.
var _fog_tex: ImageTexture = null
var _fog: PackedByteArray = PackedByteArray()


func _init() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Rotate around the square's own centre, not its top-left corner -- terrain,
	# blips and the frame are all drawn in _draw() below in the SAME unrotated
	# local space, so Godot's canvas transform carries every one of them into
	# the diamond automatically; nothing here needs its own rotation math.
	pivot_offset = Vector2(SIZE, SIZE) * 0.5
	rotation = deg_to_rad(45.0)


## Safe to call again to rebuild; a size/terrain mismatch clears to blank
## rather than reading out of bounds.
func build_terrain(size: Vector2i, terrain: PackedByteArray) -> void:
	_map_size = size
	if size.x <= 0 or size.y <= 0 or terrain.size() < size.x * size.y:
		_terrain_tex = null
		queue_redraw()
		return

	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	for y in range(size.y):
		var row := y * size.x
		for x in range(size.x):
			img.set_pixel(x, y, _terrain_color(int(terrain[row + x])))
	_terrain_tex = ImageTexture.create_from_image(img)
	queue_redraw()


## Paint the fog (PLAN.md 2.5), from the same row-major `SimPlayer.Fog` bytes the
## snapshot carries and `FogOverlay` draws in the world. Empty clears it, which is
## what a world with no fog sends.
##
## Rebuilt whole on each call rather than diffed like `FogOverlay.apply()` does: this
## is a `set_pixel` into a 64x64 image, where the overlay's equivalent is a
## `set_cell` that dirties a rendering quadrant. Skipped entirely when the bytes are
## unchanged, which is the only cheap case worth catching.
func set_fog(vision: PackedByteArray) -> void:
	if vision == _fog:
		return
	_fog = vision.duplicate()

	var count := _map_size.x * _map_size.y
	if _map_size.x <= 0 or _map_size.y <= 0 or vision.size() < count:
		_fog_tex = null
		queue_redraw()
		return

	var img := Image.create(_map_size.x, _map_size.y, false, Image.FORMAT_RGBA8)
	for y in range(_map_size.y):
		var row := y * _map_size.x
		for x in range(_map_size.x):
			img.set_pixel(x, y, _fog_color(int(vision[row + x])))
	_fog_tex = ImageTexture.create_from_image(img)
	queue_redraw()


## Deliberately the same two washes `FogOverlay` paints in the world, so the minimap
## and the map agree about how dark "explored" is.
func _fog_color(state: int) -> Color:
	match state:
		SimPlayer.Fog.UNSEEN:
			return FogOverlay.UNSEEN_COLOR
		SimPlayer.Fog.EXPLORED:
			return FogOverlay.EXPLORED_COLOR
		_:
			return Color(0, 0, 0, 0)


## `facts` is `GameView.all_facts()`-shaped: id -> {tile, owner_id, alive, ...}.
func update_entities(facts: Dictionary, local_owner: int) -> void:
	_blips.clear()
	for f in facts.values():
		if not bool(f.get("alive", true)):
			continue
		# An arrow in flight is not a thing on the map (4.13). Without this every
		# volley would strobe extra blips across the minimap in the shooter's own
		# colour, which reads as reinforcements arriving.
		if bool(f.get("is_effect", false)):
			continue
		var owner_id := int(f.get("owner_id", 0))
		var color := GAIA_COLOR
		if owner_id == local_owner:
			color = OWN_COLOR
		elif owner_id != 0:
			color = OTHER_COLOR
		_blips.append({"tile": f["tile"], "color": color})
	queue_redraw()


func _terrain_color(kind: int) -> Color:
	var visual_id: StringName = TerrainLayer.TERRAIN_VISUALS.get(kind, &"")
	if visual_id == &"":
		return PlaceholderSpec.UNKNOWN_COLOR
	return GameDataRegistry.placeholder_for(visual_id).color


func _map_to_local(tile: Vector2) -> Vector2:
	if _map_size.x <= 0 or _map_size.y <= 0:
		return Vector2.ZERO
	return Vector2(tile.x / float(_map_size.x) * SIZE, tile.y / float(_map_size.y) * SIZE)


func _local_to_tile(local: Vector2) -> Vector2i:
	if _map_size.x <= 0 or _map_size.y <= 0:
		return Vector2i.ZERO
	return Vector2i(
			clampi(int(local.x / SIZE * _map_size.x), 0, _map_size.x - 1),
			clampi(int(local.y / SIZE * _map_size.y), 0, _map_size.y - 1))


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, Vector2(SIZE, SIZE))
	if _terrain_tex != null:
		draw_texture_rect(_terrain_tex, rect, false)
	else:
		draw_rect(rect, HudStyle.DARK_BG)

	for b in _blips:
		draw_circle(_map_to_local(b["tile"]), 2.0, b["color"])

	# OVER the blips (2.5). A remembered building is dimmed along with the ground it
	# stands on, and nothing the player cannot see can shine through unexplored black
	# -- which would hand back on the minimap exactly what the snapshot filter
	# withheld from the map. Under the frame, so the gold border stays crisp.
	if _fog_tex != null:
		draw_texture_rect(_fog_tex, rect, false)

	# A double line rather than one stroke, echoing the gold-on-dark edge every
	# other panel gets from `panel_background.png`'s own border art -- there is
	# no equivalent texture for the minimap (see this file's header), so the
	# nearest a plain `draw_rect` gets to that look is an outer band with a
	# thinner inner line set apart from it.
	draw_rect(rect, FRAME_COLOR, false, _FRAME_OUTER_WIDTH)
	draw_rect(rect.grow(-_FRAME_INSET), FRAME_COLOR, false, _FRAME_INNER_WIDTH)


## A single tap is deferred by `DoubleTapDetector.DOUBLE_TAP_MS` before it
## commits, exactly like `ControlGroupsHud`'s slots -- otherwise every
## double-tap-to-centre would also fire a spurious move-camera for the tap
## that started it.
func _gui_input(event: InputEvent) -> void:
	var pos := Vector2.ZERO
	var released := false
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		pos = touch.position
		released = not touch.pressed
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index != MOUSE_BUTTON_LEFT:
			return
		pos = button.position
		released = not button.pressed
	else:
		return
	if not released:
		return

	var now := Time.get_ticks_msec()
	var tile := _local_to_tile(pos)
	if _double_tap.register_tap(now):
		double_tapped.emit()
		return
	if is_inside_tree():
		get_tree().create_timer(DoubleTapDetector.DOUBLE_TAP_MS / 1000.0).timeout.connect(
				_on_single_tap_window_elapsed.bind(tile, now))


func _on_single_tap_window_elapsed(tile: Vector2i, tap_ms: int) -> void:
	if is_instance_valid(self) and _double_tap.is_still_pending(tap_ms):
		tapped.emit(tile)
