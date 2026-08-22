## Every direction of every clip, laid out in a labelled grid (PLAN.md 4.13).
##
## Built because "the attack animation faces away from the thing it is attacking" could
## not be settled by looking at a battle. In a fight the units overlap, the reader has
## to hold the isometric axes in their head, and two people can look at the same
## screenshot and disagree -- which is exactly what happened: the sim numbers checked
## out, the walking ring looked right, the attack ring looked wrong, and those three
## facts cannot all be true.
##
## So this takes the sim out entirely. It drives `EntityView` directly, one per cell,
## and writes the sprite index and the direction name under each. What a column looks
## like IS what direction `n` draws as, with nothing in between to be wrong about.
##
## Rows are CLIPS. If a unit's `attack` row points the opposite way to its `idle` row,
## the bake is inconsistent between clips and no game-side arithmetic can fix it. If
## every row agrees but points the wrong way for its label, the conversion is wrong.
## If everything agrees and looks right, the bug was never here.
##
## Usage:
##   Godot --path game res://dev_preview/preview_facing_chart.tscn
extends Node2D

const SHOT_DIR := "user://"
const CELL := Vector2(168.0, 210.0)
const ORIGIN := Vector2(130.0, 150.0)

## A villager is about 40 px tall at native scale, which is the size the game draws her
## at and far too small to tell a front from a back in a screenshot. The chart exists
## to be READ, so it magnifies -- nearest-neighbour, since everything else here is
## pixel art and a smoothed sprite would invent detail to be misled by.
const MAGNIFY := 3.0
const CLIPS: Array[StringName] = [&"idle", &"walk", &"attack"]

## One page per unit, so a wrong clip can be blamed on one actor rather than on the
## pipeline. The swordsman is the melee case from the report and the archer the ranged
## one.
const UNITS: Array[StringName] = [&"unit.swordsman", &"unit.archer"]

var _page := 0
var _frames := 0
var _views: Array[EntityView] = []
var _labels: Array[Node] = []


func _ready() -> void:
	_build(UNITS[0])


func _process(_delta: float) -> void:
	_frames += 1
	# A couple of frames per page: the views resolve their atlas lazily on first draw,
	# and the viewport texture lags a frame behind the one being processed.
	if _frames < 12:
		return
	_frames = 0
	_shoot("facing_chart_%s" % String(UNITS[_page]).trim_prefix("unit."))
	_page += 1
	if _page >= UNITS.size():
		get_tree().quit()
		return
	_build(UNITS[_page])


func _build(unit_id: StringName) -> void:
	for v in _views:
		v.queue_free()
	for l in _labels:
		l.queue_free()
	_views.clear()
	_labels.clear()

	var ud: UnitDef = GameDataRegistry.unit(unit_id)
	var visual: StringName = ud.visual if ud != null else &""
	_add_label(Vector2(20.0, 30.0),
			"%s  (%s)   columns are SPRITE INDEX -- the number the view passes down"
			% [unit_id, visual], 20)

	for row in range(CLIPS.size()):
		var clip := CLIPS[row]
		_add_label(Vector2(10.0, ORIGIN.y + row * CELL.y - 10.0), String(clip), 18)
		for col in range(AtlasEntry.FACINGS.size()):
			var at := ORIGIN + Vector2(col * CELL.x, row * CELL.y)
			var view := EntityView.new()
			add_child(view)
			view.visual_id = visual
			view.skin_age = 0
			view.skin_colour = -1
			view.position = at
			view.scale = Vector2(MAGNIFY, MAGNIFY)
			view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			# SET DIRECTLY, not through `Iso.sim_facing_to_sprite`. The chart is about
			# what the ART does with an index; putting the conversion in the middle of
			# it would make the picture unable to answer the question it is for.
			view.play_anim(clip, col)
			_views.append(view)
			if row == 0:
				_add_label(at + Vector2(-24.0, -128.0),
						"%d %s" % [col, AtlasEntry.FACINGS[col]], 18)

	# The legend that makes the picture readable without the axes in your head.
	_add_label(Vector2(20.0, ORIGIN.y + CLIPS.size() * CELL.y + 20.0),
			"Screen directions:  S = toward the camera (down).  N = away (up).", 18)
	_add_label(Vector2(20.0, ORIGIN.y + CLIPS.size() * CELL.y + 46.0),
			"E = right.  W = left.  So column 0 (S) must SHOW ITS FACE and column 4 (N) its BACK.",
			18)


func _add_label(at: Vector2, text: String, size: int) -> void:
	var l := Label.new()
	l.text = text
	l.position = at
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color.WHITE)
	add_child(l)
	_labels.append(l)


func _draw() -> void:
	# A flat backdrop, so a pale sprite is not judged against whatever the window last
	# had in it.
	draw_rect(Rect2(Vector2.ZERO, Vector2(1600.0, 900.0)), Color(0.22, 0.30, 0.18))


func _shoot(name: String) -> void:
	var path := SHOT_DIR + name + ".png"
	get_viewport().get_texture().get_image().save_png(path)
	print("wrote ", ProjectSettings.globalize_path(path))
