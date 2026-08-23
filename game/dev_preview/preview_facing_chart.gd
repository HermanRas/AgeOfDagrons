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
##   ... -- --units unit.knight,unit.villager    -- chart those instead of the default set
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
## pipeline. The swordsman is the melee case from the report, the archer the ranged one,
## and the KNIGHT is here because the owner's 2026-08-23 screenshots are of a mounted
## unit: a rider and a horse are two meshes with two authored headings, so "the whole
## roster is 180 degrees out" is a claim about infantry until a horse has been looked at.
const DEFAULT_UNITS: Array[StringName] = [
	&"unit.swordsman", &"unit.archer", &"unit.knight", &"unit.scout_cavalry",
]

## Overridable from the command line, because the next unit somebody doubts is not
## necessarily one of these four and rebuilding the list in code to look at one actor is
## how a diagnostic tool stops being reached for.
var _units: Array[StringName] = DEFAULT_UNITS

var _page := 0
var _frames := 0
var _views: Array[EntityView] = []
var _labels: Array[Node] = []


func _ready() -> void:
	_units = _units_argument()
	_build(_units[0])


## `-- --units a,b,c`, falling back to the default set. Unknown ids are kept rather than
## filtered: a page that draws a magenta placeholder says "there is no such unit" out
## loud, where dropping it silently would look like the chart agreeing with a typo.
func _units_argument() -> Array[StringName]:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		if args[i] != "--units":
			continue
		var out: Array[StringName] = []
		for name in args[i + 1].split(",", false):
			out.append(StringName(name.strip_edges()))
		if not out.is_empty():
			return out
	return DEFAULT_UNITS


func _process(_delta: float) -> void:
	_frames += 1
	# A couple of frames per page: the views resolve their atlas lazily on first draw,
	# and the viewport texture lags a frame behind the one being processed.
	if _frames < 12:
		return
	_frames = 0
	_shoot("facing_chart_%s" % String(_units[_page]).trim_prefix("unit."))
	_page += 1
	if _page >= _units.size():
		get_tree().quit()
		return
	_build(_units[_page])


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
