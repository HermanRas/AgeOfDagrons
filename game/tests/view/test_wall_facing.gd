## Which way a wall's ART lies, measured off the staged pixels (PLAN.md 5.8).
##
## THE CHECK THAT WAS MISSING, and its absence cost the project owner six days of
## walls laid ninety degrees across their own drag. `WallPlan.FACING_FOR_AXIS` picks
## a sprite direction per axis, and until 2026-08-28 it picked the wrong one of the
## eight for both -- derived on the assumption that a wall runs ALONG the direction
## it is baked facing, where the art has it running ACROSS. Nothing could catch that:
## a wall lying across its footprint has the same footprint, the same origin, the same
## `state_hash` and the same *frame size* as one lying along it, so every existing
## test passed. `WallPlan`'s own header said "VERIFY THESE BY LOOKING" and
## `preview_walls` photographed both axes for somebody to look at, which is a check
## that runs only when a human runs it and only catches what a human notices.
##
## So this looks instead. One step along tile axis X projects to (+32, +16) screen
## pixels and one along axis Y to (-32, +16) -- `Iso.TILE_SIZE` -- so a wall lying on
## axis X leans DOWN to the right and one on axis Y leans UP, and regressing the mean
## opaque-pixel y against x over the frame recovers which. That number is what
## `FACING_FOR_AXIS`'s comment is written from, and re-measuring it here is what makes
## a rebake that turns a wall fail the suite instead of reaching a playtest.
##
## Covers foundations and rubble too, and not for completeness: they were turned by
## the same constant, and a nine-tile foundation laid across its run is what the owner
## screenshotted. It was misdiagnosed as the construction art being unreadable.
extends TestCase

## Loaded by path, like every other test that wants its own registry -- game_data.gd
## has no `class_name` because one would shadow the autoload.
const REGISTRY_SCRIPT := "res://src/autoload/game_data.gd"

## Every other pixel, in both axes. A regression is invariant under uniform
## subsampling, and reading a quarter of ~40 frames is the difference between this
## test costing a second and costing ten.
const SAMPLE_STEP := 2

## Below this lean, the art is telling us nothing about which way it lies, and
## asserting on it would be asserting on noise. The floor has to sit between the two
## real cases, and there is a wide gap to put it in: `vis.foundation_3x3_wall` is a
## symmetric heap of stones and measures 0.01 whichever way it is asked for, while the
## flattest piece that does carry a direction -- the three-tile reinforced segment,
## as tall as the nine-tile one and a third as long, so its height dominates the fit --
## still manages 0.14. The long pieces all sit near the ideal 0.5.
const FLAT := 0.08

## How many directional pairs the suite must actually have measured, so that this can
## never pass by finding nothing: a renamed atlas, a missing page or a `get_image()`
## that stops answering headless would otherwise skip every case in silence and report
## green. Eighteen wall visuals across four ages is 72 pairs and 68 of them are
## directional today -- the four that are not are the 3x3 foundation at each age.
const MIN_DIRECTIONAL := 60

var reg: Node

## (page path + rect) -> lean, so four ages pointing at one atlas measure it once.
var _leans: Dictionary = {}
## res:// png path -> {w, data} of an RGBA8 copy, or {} if it would not load.
var _pages: Dictionary = {}


func before_each() -> void:
	reg = (load(REGISTRY_SCRIPT) as GDScript).new()
	reg.load_all()


func after_each() -> void:
	reg.free()
	_leans.clear()
	_pages.clear()


func test_a_wall_is_drawn_along_the_axis_it_was_dragged_on() -> void:
	var directional := 0
	for visual_id in _wall_visuals():
		for age in range(1, reg.age_count() + 1):
			var entry: AtlasEntry = reg.atlas_for(visual_id, age)
			assert_false(entry.is_placeholder,
					"%s at age %d resolves to a real atlas, not a placeholder"
							% [visual_id, age])

			var along_x := _lean(entry, WallPlan.AXIS_X)
			var along_y := _lean(entry, WallPlan.AXIS_Y)
			if is_nan(along_x) or is_nan(along_y):
				fail("%s at age %d has no `static` frame for one of the two axes"
						% [visual_id, age])
				continue

			# THE INVARIANT EVERY PIECE OWES, flat art included: whatever axis X's
			# frame leans, axis Y's frame leans the other way. Two frames with the
			# same lean are one frame used twice, which is the shape the bug had.
			assert_true(along_x >= along_y,
					"%s at age %d: the axis-X sprite leans %+.2f and the axis-Y one %+.2f, so they are the wrong way round"
							% [visual_id, age, along_x, along_y])

			if maxf(absf(along_x), absf(along_y)) < FLAT:
				continue        # symmetric art -- it has no axis to be wrong about
			directional += 1
			# A step along tile axis X is (+32, +16) screen pixels and screen y grows
			# downward, so the sprite must lean DOWN to the right; axis Y is (-32, +16)
			# and leans up.
			assert_true(along_x > FLAT,
					"%s at age %d lies along tile axis X and so must lean down-right, but leans %+.2f"
							% [visual_id, age, along_x])
			assert_true(along_y < -FLAT,
					"%s at age %d lies along tile axis Y and so must lean up-right, but leans %+.2f"
							% [visual_id, age, along_y])

	assert_true(directional >= MIN_DIRECTIONAL,
			"%d wall sprites carried a measurable direction, and at least %d should -- a skip here would make this whole test vacuous"
					% [directional, MIN_DIRECTIONAL])


func test_the_two_axes_ask_for_different_sprites_at_all() -> void:
	# The cheap half of the same property, stated where it can be read without a PNG:
	# one facing for both axes would draw every wall the same way round, and the drag
	# would be undetectable from the art no matter which facing was chosen.
	assert_ne(WallPlan.FACING_FOR_AXIS[WallPlan.AXIS_X],
			WallPlan.FACING_FOR_AXIS[WallPlan.AXIS_Y],
			"the two axes are baked at different directions")
	# And that both are directions the atlas actually stores, rather than numbers that
	# happen to survive `posmod`.
	for axis in [WallPlan.AXIS_X, WallPlan.AXIS_Y]:
		var sprite := Iso.sim_facing_to_sprite(WallPlan.FACING_FOR_AXIS[axis])
		assert_true(sprite >= 0 and sprite < AtlasEntry.FACINGS.size(),
				"axis %d maps to sprite facing %d, which is in the table" % [axis, sprite])


## Every visual a wall run can put on the ground: the segments themselves, their
## gates, and the foundation and rubble they pass through. Read off the DEFS rather
## than by matching `vis.wall_*` by name, so a tier added to buildings.json is covered
## the day it is added and a staged-but-unused bake is not.
func _wall_visuals() -> Array[StringName]:
	var out: Array[StringName] = []
	for def_id in reg.building_ids():
		var bd: BuildingDef = reg.building(def_id)
		if bd == null:
			continue
		# `wall_tier` answers for a segment and null for a gate -- a gate is an upgrade
		# of the long piece, not a length a drag can lay -- so a gate is named
		# separately. It is turned by exactly the same constant.
		if reg.wall_tier(def_id) == null and not bd.is_gate:
			continue
		for v in [bd.visual, bd.visual_foundation, bd.visual_rubble] as Array[StringName]:
			if not String(v).is_empty() and not out.has(v):
				out.append(v)
	out.sort()
	return out


## The slope the opaque pixels of this atlas's frame for `axis` lean at, or NAN if
## there is no such frame. Positive is down-to-the-right on screen.
func _lean(entry: AtlasEntry, axis: int) -> float:
	var sprite := Iso.sim_facing_to_sprite(WallPlan.FACING_FOR_AXIS[axis])
	var f := entry.frame_at(AtlasEntry.STATIC_ANIM, sprite, 0)
	if f.is_empty():
		return NAN

	var page := int(f["page"])
	var rect: Rect2i = f["rect"]
	var key := "%s|%d,%d,%d,%d" % [entry.pages[page], rect.position.x, rect.position.y,
			rect.size.x, rect.size.y]
	if not _leans.has(key):
		# A mirrored frame leans the other way, and no wall atlas stores one today --
		# they all bake eight real directions. Applied anyway, because the day one is
		# baked mirrored is the day this would otherwise start lying.
		var slope := _regress(_page(entry, page), rect)
		_leans[key] = -slope if bool(f["flip_x"]) else slope
	return _leans[key]


## Mean opaque-pixel y regressed on x over `rect`. NAN if the frame is empty or a
## single column, both of which mean the same thing: no lean to measure.
func _regress(page: Dictionary, rect: Rect2i) -> float:
	if page.is_empty():
		return NAN
	var w := int(page["w"])
	var data: PackedByteArray = page["data"]

	var n := 0.0
	var sx := 0.0
	var sy := 0.0
	var sxx := 0.0
	var sxy := 0.0
	var y := rect.position.y
	while y < rect.position.y + rect.size.y:
		var row := y * w
		var x := rect.position.x
		while x < rect.position.x + rect.size.x:
			# Half alpha, so the soft edge of a shadow does not drag the fit.
			if data[(row + x) * 4 + 3] >= 128:
				n += 1.0
				sx += float(x)
				sy += float(y)
				sxx += float(x) * float(x)
				sxy += float(x) * float(y)
			x += SAMPLE_STEP
		y += SAMPLE_STEP

	if n < 10.0:
		return NAN
	var den := n * sxx - sx * sx
	if is_zero_approx(den):
		return NAN
	return (n * sxy - sx * sy) / den


## The atlas page as raw RGBA8 bytes, cached per path.
##
## Through `AtlasEntry.texture()` -- the same route the game draws by -- rather than
## `Image.load_from_file` on the source PNG. Both work here, but the source-file route
## reads a file that is not in an exported build and says so in a warning on every
## page, and the point of measuring the staged art is to measure what the game
## actually puts on screen. These pages import at `compress/mode=0`, so the image
## comes back losslessly and `get_image()` answers even with the dummy renderer the
## headless suite runs on.
func _page(entry: AtlasEntry, page: int) -> Dictionary:
	var path: String = entry.pages[page]
	if _pages.has(path):
		return _pages[path]
	var out: Dictionary = {}
	var tex := entry.texture(page)
	var img: Image = tex.get_image() if tex != null else null
	if img != null and img.get_width() > 0:
		img.convert(Image.FORMAT_RGBA8)
		out = {"w": img.get_width(), "data": img.get_data()}
	_pages[path] = out
	return out
