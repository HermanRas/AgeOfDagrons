## Throwaway visual check for 0.2b: draws one of every declared visual through
## the real seam, on a grass tile grid, and screenshots itself.
extends Node2D

## Coordinates are in the 1404x648 design viewport (PLAN.md 3.0), not window
## pixels -- the project stretches canvas_items, so window size is irrelevant here.
const SHOT_PATH := "user://placeholder_preview.png"
const BASELINE_Y := 520.0
const GRID_CENTRE := Vector2(702.0, 430.0)
const ROW := [
	&"vis.villager", &"vis.deer", &"vis.gold_mine", &"vis.tree",
	&"vis.house", &"vis.town_center",
]

var _frames := 0


func _ready() -> void:
	var grid := Node2D.new()
	grid.draw.connect(_draw_grid.bind(grid))
	add_child(grid)

	# Hand-placed rather than evenly spaced: the widths differ by 25x, which is
	# itself the thing worth looking at.
	var xs := [80.0, 170.0, 290.0, 430.0, 640.0, 1090.0]
	for i in range(ROW.size()):
		var view := EntityView.new()
		view.visual_id = ROW[i]
		view.position = Vector2(xs[i], BASELINE_Y)
		view.play_anim(&"idle", 0)
		add_child(view)

		var label := Label.new()
		label.text = String(ROW[i]).replace("vis.", "")
		label.position = Vector2(xs[i] - 80.0, BASELINE_Y + 24.0)
		label.size = Vector2(160.0, 20.0)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(label)


func _draw_grid(on: Node2D) -> void:
	var spec := PlaceholderSpec.from_dict({
		"shape": "diamond", "footprint_m": [2.0, 2.0], "color": "#4a6f30",
	})
	for tx in range(-7, 8):
		for ty in range(-7, 8):
			on.draw_set_transform(
				GRID_CENTRE + Iso.tile_to_world(Vector2i(tx, ty)), 0.0, Vector2.ONE)
			PlaceholderRenderer.draw_into(on, spec, 0)


func _process(_delta: float) -> void:
	_frames += 1
	if _frames < 6:
		return
	var img := get_viewport().get_texture().get_image()
	img.save_png(SHOT_PATH)
	print("wrote ", ProjectSettings.globalize_path(SHOT_PATH))
	get_tree().quit()
