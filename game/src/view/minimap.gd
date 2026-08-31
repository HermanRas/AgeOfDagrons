## The minimap (PLAN.md 8.2a): baked terrain colours, entity blips, tap to move
## the camera there (3.8), and double-tap to centre on the player's own Town
## Centre (3.4). No camera-viewport rectangle -- dropped per UI_Design.md, the
## diamond reads better without one.
##
## THE ORNATE DIAMOND FRAME IS REAL ART NOW ([P8], 2026-08-30) and it is NOT DRAWN
## HERE. This file used to record that no such piece existed and that it approximated
## one with a double gold `draw_rect`; `chrome/frame_minimap.png` is that frame, and
## `GameScene._build_hud` draws it into the unrotated 200x200 area this widget sits in.
##
## THE REASON IT CANNOT LIVE IN THIS FILE is the same trick that makes the rest of the
## file simple: this Control is rotated 45 degrees so terrain, blips and fog can be
## drawn in plain unrotated coordinates and carried into the diamond by Godot's canvas
## transform. The frame art is ALREADY a diamond inside a square, so drawing it here
## would turn it 45 degrees further and produce a square frame around a square map.
##
## What is still drawn here is the thin gold edge immediately around the map itself,
## which is a different line from the frame -- it is what separates terrain from the
## black field the frame's own diamond encloses.
##
## Terrain is baked into a small `Image` once per `build_terrain()` call --
## the same placeholder-colour trick `TerrainLayer._placeholder_texture()`
## already uses per-tile, at minimap scale instead. Entities are cheap to
## redraw fresh every snapshot since they move every tick.
class_name Minimap
extends Control

## The footprint `GameScene` reserves for the minimap and everything around it: the
## ornate frame fills exactly this, and the four corner buttons sit in the four bosses
## the frame's own art puts near its corners.
##
## 240 SINCE 2026-08-30, up from 200, and the extra 40 px is what stops the map being
## shrunk to pay for the frame. See `SIZE`.
const AREA_SIZE := 240.0

## How far the frame's clear aperture reaches from the centre, as a fraction of the
## frame's drawn size. MEASURED off `chrome/frame_minimap.png` rather than eyed: the
## largest diamond about the centre containing no gold is 178 px of a 512 px image.
##
## THE MEASUREMENT IS THE WHOLE POINT OF THIS CONSTANT. The first version of the frame
## swap left `SIZE` at 150 against a 200 px area, which put the map's diamond 18 % wider
## than the hole it was supposed to sit in -- so the map covered the frame's braided
## diamond bar entirely and left two dragons apparently floating in the corners. It
## looked like a z-order bug and was arithmetic.
const APERTURE_RATIO := 0.3477

## The square this control draws, before the 45-degree rotation `_init()` applies to
## turn it into a diamond.
##
## DERIVED, NOT CHOSEN, and that is deliberate: a rotated square of side S has a
## half-diagonal of S / sqrt(2), and it fits the aperture exactly when that equals
## `AREA_SIZE * APERTURE_RATIO`. Two hand-picked numbers that had to agree is precisely
## how the map came to overflow its frame; now changing the area moves the map with it.
const SIZE := AREA_SIZE * APERTURE_RATIO * 1.41421356
const OWN_COLOR := Color(0.35, 1.0, 0.45)
const OTHER_COLOR := Color(1.0, 0.35, 0.3)
const GAIA_COLOR := Color(0.55, 0.5, 0.35, 0.7)

## AN ALLY (project owner, 2026-08-31: *"minimap is a problem, lets use your idea and
## tint allies.. a diffrent color maybe sky blue if its not to close to the water
## colour"*). Sky blue, `#87CEEB`, and the owner's question is the right one to have
## asked -- it was measured rather than eyeballed.
##
## **THE HUE IS ALMOST EXACTLY SHALLOW WATER'S AND THE LIGHTNESS IS NOWHERE NEAR IT.**
## `terrain.water_shallow` is `#3f7fa6` at hue 203°, this is hue 197° -- six degrees
## apart, so on hue alone it would have been a bad pick. What separates them is CIE
## `L*`: 79 against water's 51, and against deep water's 30. That is the same principle
## `web/player-colour-ladder.html` settled the eight-player palette on, where the whole
## eight span L* 36 to 100 and neighbours are about nine apart; 28 is three of those
## steps. A pale blue dot on a mid-blue field reads, and it is the only pairing on this
## map that has to work at all -- an ally in the water is a SHIP, and the archipelago is
## the map whose whole point is a fleet.
##
## **IT IS DELIBERATELY NOT PALER THAN THIS**, which is the other bound. Pushing L* up
## to 86 would separate it further from the water and start eating the one value
## `DAMAGE_FLASH_COLOR` reserves -- see its note directly below, which is only true for
## as long as no blip sits near white.
const ALLY_COLOR := Color("#87CEEB")

## What one of ours flashes to when it is being hit (2026-08-30). WHITE, on the owner's
## ask, and it is the right pick for a reason worth keeping: the map already spends green
## on us, red on the enemy and a dull khaki on gaia, so any HUE would collide with a
## meaning the player has already learned. White is the one value left that no blip ever
## sits at, and it is the furthest from all three at minimap scale, which is two pixels.
##
## **THAT ARGUMENT NOW HAS FOUR COLOURS UNDER IT AND STILL HOLDS, BUT ONLY JUST.**
## `ALLY_COLOR` above is the closest anything has come to white (L* 79 against 100), and
## it is capped there for this reason. **A fifth blip colour has to be checked against
## this one**, not only against the terrain.
const DAMAGE_FLASH_COLOR := Color.WHITE
const FRAME_COLOR := Color("#E5B842")   # HudStyle.GOLD -- not a constant expression to reference directly
## The hairline around the map itself.
##
## With `SIZE` derived from the aperture it lands directly under the frame's own bar
## and is nearly invisible, which is correct -- what it is really for is the case where
## `chrome/frame_minimap.png` does not load, where without it the map has no edge at
## all. `_FRAME_OUTER_WIDTH` (4.0) and `_FRAME_INSET` (4.0) sat beside this and were
## the other half of the hand-drawn double border; they went with it on 2026-08-30.
const _FRAME_INNER_WIDTH := 1.5

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
##
## `flashing` is `DamageAlert.flashing()` -- `id -> true` for everything of ours that has
## been hit in the last two seconds. Those blips are drawn WHITE on alternate phases so
## the player can see, at a glance, where the fighting is (project owner, 2026-08-30:
## *"the flashing units / building tell you where multiple units / building are taking
## damage"*).
##
## THE PHASE IS ASKED ONCE, HERE, and passed down rather than recomputed per blip. It is
## a function of the clock alone, so six hit units pulse TOGETHER and read as one alarm;
## computing it inside the loop would be the same answer today and the wrong shape the
## moment anything staggers it.
## `teams` is `GameView.teams()` -- player id -> team number, straight off the wire.
##
## **DEFAULTED, UNLIKE THE ONE `Diplomacy` TAKES, AND THE DIFFERENCE IS WHAT A MISSING
## ARGUMENT COSTS.** There it is mandatory because leaving it out is a hostility rule
## silently OFF -- an ally you can shoot, with nothing on screen to say so. Here leaving
## it out draws an ally red, which is exactly what the map did before today and is
## visible in the first screenshot anybody takes. An empty table is also the honest
## answer for a free-for-all, which is every match this game has played until now.
func update_entities(facts: Dictionary, local_owner: int,
		flashing: Dictionary = {}, teams: Dictionary = {}) -> void:
	_blips.clear()
	var white := not flashing.is_empty() and DamageAlert.white_phase()
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
			# AN ALLY IS NOT AN ENEMY, and until 2026-08-31 this map said it was: green
			# for your own and red for everything else, so in a 2v2 your partner's army
			# crossing the map read as an incoming attack. Own and ally stay two colours
			# rather than one -- you still have to find YOUR units, and a shared green
			# would make a rescue indistinguishable from your own reinforcements.
			#
			# `owner_id != 0` first, so gaia never reaches the ally test: it has no row
			# in `teams` and `Diplomacy.allied` guards it anyway, but the order here is
			# what keeps the khaki default meaning what it always did.
			color = ALLY_COLOR if Diplomacy.allied(local_owner, owner_id, teams) \
					else OTHER_COLOR
		# Only ever OUR entities: `DamageAlert` records nobody else's, so this cannot
		# light up an enemy blip even if the caller passed one in.
		if white and flashing.has(int(f.get("id", 0))):
			color = DAMAGE_FLASH_COLOR
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

	# ONE LINE NOW, NOT TWO. The double stroke was standing in for a frame that did
	# not exist -- an outer band with a thinner inner line set apart from it was the
	# nearest a plain `draw_rect` got to the gold-on-dark edge the art gives
	# everything else. `chrome/frame_minimap.png` is that edge, drawn by `GameScene`
	# around this control, and a second gold rectangle inside a gold dragon frame is
	# one gold rectangle too many.
	#
	# The single stroke stays because it is doing a job the frame cannot: the frame's
	# diamond encloses a black field larger than the map, and this is what says where
	# the MAP ends inside it.
	draw_rect(rect, FRAME_COLOR, false, _FRAME_INNER_WIDTH)


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
