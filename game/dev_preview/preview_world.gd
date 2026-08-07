## Dev check for 2.3/2.4a/2.6: build the real debug world through MapGen and draw
## it. Terrain from SimMap, entities through the asset seam, and it screenshots
## itself.
##
## Not phase 3.1 -- there is no TileMapLayer, no camera and no Y-sort container
## here, just enough drawing to answer "did MapGen make a sensible world?" by
## looking instead of by reading a hash.
extends Node2D

const SHOT_PATH := "user://world_preview.png"
## Middle of the 1404x648 design viewport (PLAN.md 3.0).
const SCREEN_CENTRE := Vector2(702.0, 340.0)

var _frames := 0
var _world: SimWorld

## Offset that puts the town centre in the middle of the screen. A 64x64 map is
## ~4096 px wide projected, so without this the viewport shows the map's top
## corner and nothing else. This is the poor cousin of the camera at 3.3.
var _origin := SCREEN_CENTRE


func _ready() -> void:
	_world = SimWorld.new()
	_world.setup(MatchConfig.debug_single_player())
	MapGen.build_debug_map(_world)

	for e in _world.entities.values():
		if e is SimBuilding:
			_origin = SCREEN_CENTRE - Iso.sub_to_world(e.pos)
			break

	var ground := Node2D.new()
	ground.draw.connect(_draw_ground.bind(ground))
	add_child(ground)

	# Painter's order: back to front by tile sum, which is what Iso.depth_sort_key
	# gives and what 3.1 will get from a Y-sorted container instead.
	var sorted := _world.entities.values()
	sorted.sort_custom(func(a, b): return Iso.depth_sort_key(a.tile()) < Iso.depth_sort_key(b.tile()))

	for e in sorted:
		var view := EntityView.new()
		view.visual_id = _visual_for(e)
		view.position = _origin + Iso.sub_to_world(e.pos)
		view.play_anim(&"idle", 0)
		add_child(view)

	var label := Label.new()
	label.text = "%d entities  |  map %dx%d  |  hash %d" % [
		_world.entities.size(), _world.map.size.x, _world.map.size.y, _world.state_hash()]
	label.position = Vector2(12, 12)
	add_child(label)


## The sim knows def ids; visuals.json knows visual ids. GameDataRegistry is the
## seam between them -- exactly the indirection PLAN.md 2.1 exists for.
func _visual_for(e: SimEntity) -> StringName:
	if e is SimBuilding:
		var bd: BuildingDef = GameDataRegistry.building(e.def_id)
		return bd.visual_for_phase(int((e as SimBuilding).phase)) if bd != null else &""
	if e is SimResourceNode:
		var rd: ResourceDef = GameDataRegistry.resource_def(e.def_id)
		return rd.visual if rd != null else &""
	var ud: UnitDef = GameDataRegistry.unit(e.def_id)
	return ud.visual if ud != null else &""


func _draw_ground(on: Node2D) -> void:
	var grass := PlaceholderSpec.from_dict({
		"shape": "diamond", "footprint_m": [2.0, 2.0], "color": "#4a6f30"})
	var dirt := PlaceholderSpec.from_dict({
		"shape": "diamond", "footprint_m": [2.0, 2.0], "color": "#6b5a3c"})

	for ty in range(_world.map.size.y):
		for tx in range(_world.map.size.x):
			var t := Vector2i(tx, ty)
			on.draw_set_transform(_origin + Iso.tile_to_world(t), 0.0, Vector2.ONE)
			var kind := _world.map.terrain_at(t)
			PlaceholderRenderer.draw_into(on, dirt if kind == SimMap.Terrain.DIRT else grass, 0)


func _process(_delta: float) -> void:
	_frames += 1
	if _frames < 6:
		return
	get_viewport().get_texture().get_image().save_png(SHOT_PATH)
	print("wrote ", ProjectSettings.globalize_path(SHOT_PATH))
	get_tree().quit()
