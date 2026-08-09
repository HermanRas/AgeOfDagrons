## The minimap (PLAN.md 8.2a): baked terrain colours, entity blips, the
## camera's current viewport rectangle, tap to move the camera there (3.8),
## and double-tap to centre on the player's own Town Centre (3.4).
##
## No dedicated minimap frame exists in the Kibyra pack (ASSET_MISSING.md
## 1.5) -- UI_Design.jpg's ornate diamond frame is drawn here as a double gold
## rectangle border (`HudStyle.GOLD`, the same accent every other HUD panel
## uses) instead of left missing, the same "placeholder until the art exists"
## convention as everywhere else art is not final.
##
## Terrain is baked into a small `Image` once per `build_terrain()` call --
## the same placeholder-colour trick `TerrainLayer._placeholder_texture()`
## already uses per-tile, at minimap scale instead. Entities and the camera
## rect are cheap to redraw fresh every snapshot since they move every tick.
class_name Minimap
extends Control

const SIZE := 220.0
const OWN_COLOR := Color(0.35, 1.0, 0.45)
const OTHER_COLOR := Color(1.0, 0.35, 0.3)
const GAIA_COLOR := Color(0.55, 0.5, 0.35, 0.7)
const CAMERA_RECT_COLOR := Color(1.0, 1.0, 1.0, 0.85)
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
var _camera_rect_tiles: Rect2 = Rect2()
var _double_tap := DoubleTapDetector.new()


func _init() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	mouse_filter = Control.MOUSE_FILTER_STOP


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


## `facts` is `GameView.all_facts()`-shaped: id -> {tile, owner_id, alive, ...}.
func update_entities(facts: Dictionary, local_owner: int) -> void:
	_blips.clear()
	for f in facts.values():
		if not bool(f.get("alive", true)):
			continue
		var owner_id := int(f.get("owner_id", 0))
		var color := GAIA_COLOR
		if owner_id == local_owner:
			color = OWN_COLOR
		elif owner_id != 0:
			color = OTHER_COLOR
		_blips.append({"tile": f["tile"], "color": color})
	queue_redraw()


## `visible_tiles` is the camera's current view, in fractional tile
## coordinates -- `CameraRig.position`/`visible_size()` converted through
## `Iso.world_to_tile_f()` by the caller, which already owns the camera.
func update_camera_rect(visible_tiles: Rect2) -> void:
	_camera_rect_tiles = visible_tiles
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

	if _map_size.x > 0 and _map_size.y > 0 and _camera_rect_tiles.size != Vector2.ZERO:
		var a := _map_to_local(_camera_rect_tiles.position)
		var b := _map_to_local(_camera_rect_tiles.end)
		draw_rect(Rect2(a, b - a), CAMERA_RECT_COLOR, false, 2.0)

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
