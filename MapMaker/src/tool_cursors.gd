## The five mouse cursors, and the hotspots that decide where each one AIMS (PLAN.md 16.4e).
##
## ## ⚠️ THE CURSOR IS SCOPED TO THE CANVAS BY A BUILT-IN SHAPE, NOT SET GLOBALLY
##
## `Input.set_custom_mouse_cursor(tex, shape, hotspot)` is **application-wide state**: it replaces
## the art for one of Godot's built-in cursor shapes everywhere. Registering the brush against
## `CURSOR_ARROW` — the obvious thing to do — would put a paintbrush over the toolbar, over the
## palette, over every button and every dropdown in the tool. An author's pointer would claim it
## was about to paint the Save button.
##
## So the art is registered against **`CURSOR_CROSS`**, which nothing else in this tool uses, and
## `MapCanvas.mouse_default_cursor_shape` is set to it. Godot then draws our texture over the map
## and the ordinary system arrow everywhere else, with no per-control bookkeeping and nothing to
## un-set on the way out. Switching tools re-registers that one shape.
##
## ✅ **AND THE FALLBACK IS FREE AND CORRECT.** If the art does not load, `CURSOR_CROSS` is still
## what the canvas asks for, so an author gets the system **crosshair** over the map — which is a
## perfectly sensible map-editing pointer. That is why this file has no drawn fallback either
## (16.4d's argument), and why a missing file is not an emergency.
##
## ## THE HOTSPOTS ARE READ FROM `hotspots.json` AND NEVER COPIED INTO CODE
##
## The art side's card is explicit: *"do not copy these numbers into code — a re-cut re-measures
## them, and the JSON is the only thing that stays true."* Each hotspot is measured on its own
## image, as the foreground pixel minimising x+y (the outer corner of the keyline), so **the three
## pointers differ from each other and that is correct rather than drift**: the picture shifts a
## pixel or two under the pointer when the tool changes and the AIM does not move. Averaging them,
## or measuring one and using it for three, is the way to break that.
##
## `fraction` is the field this file reads, because it is the only one that survives a resize —
## see `SIZE`. The JSON's `at_32` is a cross-check `test_tool_cursors` asserts against, which is
## what catches a `fraction`/`at_100` mix-up: at 32 px the two are a factor of three apart and
## every cursor would aim at its own middle.
##
## ## ⚠️ THE RESIZE FILTER IS A CORRECTNESS QUESTION HERE, NOT A TASTE ONE
##
## Every other glyph in this UI set sits in a panel of known colour. **A cursor floats over grass,
## water, dark rock and bright sand**, so these are gold with a hard dark keyline all the way
## round: the gold body reads on the dark half of a map and the keyline reads on the light half. It
## is the one place in `ART_PROMPT.md` where an outline is required rather than forbidden.
##
## The rim is ~10 px in the 236 px master and the slicer already took 236 → 100 through LANCZOS
## for that reason. **100 → 32 here is the step that matters**, and a soft edge is the failure
## mode — a cursor that loses its keyline looks fine on grass and disappears over sand. LANCZOS,
## and looked at: `assets/UI_Gen/sliced/review/sheet_i_mapmaker_cursors.png` composites all five
## over dark grass AND pale sand, because a checkerboard is two light greys and answers half the
## question.
##
## ## ⚠️ `hotspots.json` IS A RAW FILE IN `res://` AND AN EXPORT CAN DROP IT
##
## `export_filter="all_resources"` exports what Godot recognises as a *resource*. A `.json` is
## read here with `FileAccess`, not `load()`, so `*.json` is named in the preset's
## `include_filter` — otherwise the exported `MapMaker.exe` would run with every hotspot
## defaulting and nothing would say so. That is recorded here and not in `export_presets.cfg`,
## because opening the export dialog rewrites that file the way it rewrites `project.godot`.
class_name ToolCursors
extends RefCounted

## Where the committed art lives, beside `ToolIcons`' and for the owner's same reason.
const DIR := "res://assets/ui/cursors"

## The measured hotspots, as the art side wrote them.
const HOTSPOT_PATH := DIR + "/hotspots.json"

## The drawn size, in pixels. **Godot draws a cursor at the texture's own pixel size**, so the
## 100 px art would give a pointer a third the height of the palette. 32 is the platform's
## ordinary cursor size and the size the art side pre-computed `at_32` for.
const SIZE := 32

## ⚠️ **THE SHAPE THE ART IS REGISTERED AGAINST — see the class comment.** Nothing else in this
## tool asks for `CURSOR_CROSS`, which is what keeps the paintbrush off the Save button.
const SHAPE := Input.CURSOR_CROSS

## The SAME shape again, in the other enum. **`Input.CursorShape` and `Control.CursorShape` are
## two different types with identical members and identical values**, and GDScript refuses to
## assign one to the other — `mouse_default_cursor_shape` wants this one,
## `Input.set_custom_mouse_cursor` wants the one above.
##
## ⚠️ **SO ONE FACT IS DECLARED TWICE, WHICH IS A HAZARD WITH A NAME IN THIS PROJECT.** Changing
## one and not the other registers the art against a shape nothing asks for, and the failure is
## **silent**: the canvas shows whatever its shape's default art is, the tool reports nothing, and
## every test about textures and hotspots still passes. `test_tool_cursors` asserts the two agree
## numerically, which is the only thing that can catch it.
const CANVAS_SHAPE := Control.CURSOR_CROSS

const IDS: Array[StringName] = [
	&"cur_brush", &"cur_place", &"cur_erase", &"cur_select", &"cur_move",
]

static var _cache: Dictionary = {}
static var _hotspots: Dictionary = {}
static var _read := false
static var _warned: Dictionary = {}


## The cursor id for one `Editor.Tool` value, or `&""` when that tool has none.
##
## ⚠️ **MATCHED AGAINST THE ENUM AND NEVER AGAINST A NUMBER**, for `ToolIcons.for_tool()`'s
## reason: `Tool.START`'s removal renumbered every member after it on 2026-09-08 and a test
## driving tools by literal went on passing while exercising the wrong ones.
static func for_tool(tool_value: int) -> StringName:
	var tools = load("res://src/editor.gd").Tool
	match tool_value:
		tools.PAINT:
			return &"cur_brush"
		tools.PLACE:
			return &"cur_place"
		tools.ERASE:
			return &"cur_erase"
		tools.SELECT:
			return &"cur_select"
		tools.MOVE:
			return &"cur_move"
	# ⚠️ **`Tool.AREA` (16.5) DELIBERATELY HAS NONE, AND THAT IS BETTER THAN BORROWING ONE.** The
	# empty answer makes `arm()` clear the custom cursor, so the canvas's `CURSOR_CROSS` falls back
	# to the SYSTEM CROSSHAIR — which is the conventional cursor for dragging out a rectangle in
	# every editor there is, and is more right for this tool than any of the five pointers above.
	# There is no `cur_area` in the art side's cut and none is wanted.
	#
	# 📝 The general shape is `ToolIcons.for_tool()`'s inverted: there, one picture shared between
	# the tab and the button was the honest answer; here, the ABSENCE of one is. Both are choices
	# rather than gaps, and both say so where somebody would otherwise file a bug.
	return &""


## The art for one cursor id at `SIZE`, or null when the file is missing.
static func texture(id: StringName) -> Texture2D:
	if _cache.has(id):
		return _cache[id]
	var tex := _load(id)
	_cache[id] = tex
	return tex


## Where that cursor aims, in pixels, at `SIZE`.
##
## Derived from the measured `fraction` rather than read from `at_32`, so a different `SIZE` needs
## no new art and no new measurement. Rounded, not floored: `cur_place`'s (0.08, 0.09) floors to
## (2, 2) and rounds to (3, 3), and the JSON's own `at_32` says (3, 3).
##
## **Falls back to the CENTRE and not to the corner** when a hotspot is unknown. A corner default
## would silently aim every pointer at the tip of nothing, which is a tool that places tiles one
## or two off where the author clicked — subtle enough to survive a screenshot. The centre is
## visibly wrong for the three pointers and correct for the two that are centred anyway.
static func hotspot(id: StringName) -> Vector2:
	_read_hotspots()
	var half := Vector2(SIZE, SIZE) * 0.5
	if not _hotspots.has(id):
		return half
	var frac = _hotspots[id]
	if not (frac is Array) or (frac as Array).size() != 2:
		return half
	return Vector2(roundi(float(frac[0]) * SIZE), roundi(float(frac[1]) * SIZE))


## Point `SHAPE` at the cursor for one tool. Returns whether real art was used.
##
## A false answer is not a failure to report loudly: the canvas keeps asking for `CURSOR_CROSS`
## and the author gets a system crosshair. `Boot` counts the files; this does not warn again.
##
## ⚠️ **GUARDED ON THE DISPLAY SERVER, BECAUSE THE SUITE RUNS HEADLESS.** There is no cursor to
## set there, and the arithmetic is what the tests are about — `texture()` and `hotspot()` are
## both callable and both pure. `preview_editor` is what proves the registration.
static func arm(tool_value: int) -> bool:
	var id := for_tool(tool_value)
	var tex: Texture2D = texture(id) if not id.is_empty() else null
	if DisplayServer.get_name() == "headless":
		return tex != null
	if tex == null:
		# ⚠️ **CLEARED RATHER THAN LEFT ALONE.** Without this, switching from a tool whose art
		# loaded to one whose art did not would keep the PREVIOUS tool's picture on screen — an
		# eraser wearing the brush's cursor, which is worse than a crosshair by a wide margin.
		Input.set_custom_mouse_cursor(null, SHAPE)
		return false
	Input.set_custom_mouse_cursor(tex, SHAPE, hotspot(id))
	return true


## Hand the shape back to the system and drop the art.
##
## ⚠️ **THIS EXISTS BECAUSE THE FIRST VERSION LEAKED A TEXTURE AT EXIT, AND THE ERROR NAMED THE
## CAUSE ONE LINE DOWN:** *"1 RID allocation of type GLES3Texture were leaked at exit ... Parameter
## `RenderingServer::get_singleton()` is null at ~ImageTexture"*. The `DisplayServer` holds a
## reference to whatever cursor is currently armed, and a static cache holds the rest — both
## outlive the rendering server, so the textures are destroyed after the thing that owns their
## GPU memory has already gone.
##
## 5 KB at process exit is not a bug anybody would feel. **It is fixed anyway because it is the
## same shape as a rule this project already paid for:** `GameScene` turns
## `emulate_mouse_from_touch` off on entry and hands it back in `_exit_tree`, and its note is that
## a flag toggled per screen has to be un-toggled on *every* path out. Application-wide state
## claimed by a screen is the screen's to give back — and an ERROR at exit is how a preview stops
## being trusted to run clean.
static func release() -> void:
	if DisplayServer.get_name() != "headless":
		Input.set_custom_mouse_cursor(null, SHAPE)
	forget()


## Every id whose file is missing. Empty is the healthy answer; `Boot` prints it.
static func missing() -> Array[StringName]:
	var gone: Array[StringName] = []
	for id in IDS:
		if texture(id) == null:
			gone.append(id)
	return gone


## Ids the hotspot file does not describe. Separate from `missing()` because the two have
## different consequences: no art is a crosshair, no hotspot is a pointer that aims at its own
## middle — and the second is the one that looks like it works.
static func unmeasured() -> Array[StringName]:
	_read_hotspots()
	var out: Array[StringName] = []
	for id in IDS:
		if not _hotspots.has(id):
			out.append(id)
	return out


## Drop the caches. For the tests, and for nothing else.
static func forget() -> void:
	_cache.clear()
	_hotspots.clear()
	_warned.clear()
	_read = false


static func _load(id: StringName) -> Texture2D:
	var path := "%s/%s.png" % [DIR, id]
	# `FileAccess.file_exists` and NOT `ResourceLoader.exists`, on 16.3's measurement that the
	# second one answers TRUE for a file `load()` returns null for.
	if not FileAccess.file_exists(path):
		_warn(id, "no file at %s" % path)
		return null
	var res := load(path)
	if res == null or not (res is Texture2D):
		_warn(id, "%s did not load — run: godot --headless --path MapMaker --import" % path)
		return null
	var img := (res as Texture2D).get_image()
	if img == null:
		_warn(id, "%s loaded but carries no image" % path)
		return null
	if img.is_compressed():
		img.decompress()
	# LANCZOS -- see the class comment. This is the line the keyline lives or dies on.
	img.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(img)


## Read the measured fractions once.
##
## ⚠️ **`JSON.new().parse()` AND NOT `JSON.parse_string()`.** The static form pushes an engine
## error per failure, and this file is content that can be regenerated by a tool run — so a
## malformed one should produce one warning naming the file, not a stack of engine errors that
## reads like a broken build. Same rule the campaign loader follows for the same reason.
static func _read_hotspots() -> void:
	if _read:
		return
	_read = true
	if not FileAccess.file_exists(HOTSPOT_PATH):
		push_warning("ToolCursors: %s is missing — every cursor will aim at its own centre"
				% HOTSPOT_PATH)
		return
	var text := FileAccess.get_file_as_string(HOTSPOT_PATH)
	var parser := JSON.new()
	if parser.parse(text) != OK:
		push_warning("ToolCursors: %s did not parse at line %d: %s"
				% [HOTSPOT_PATH, parser.get_error_line(), parser.get_error_message()])
		return
	var data = parser.data
	if not (data is Dictionary):
		push_warning("ToolCursors: %s is not an object" % HOTSPOT_PATH)
		return
	for key in (data as Dictionary):
		var entry = (data as Dictionary)[key]
		if entry is Dictionary and (entry as Dictionary).has("fraction"):
			# ⚠️ **`fraction` IS THE FIELD, NOT `at_100` OR `at_32`.** The other two are the same
			# measurement pre-multiplied for one size, and reading either would break the day
			# `SIZE` changes — silently, because a wrong hotspot is a cursor that aims slightly
			# off and every test about textures still passes.
			_hotspots[StringName(key)] = (entry as Dictionary)["fraction"]


static func _warn(id: StringName, why: String) -> void:
	if _warned.has(id):
		return
	_warned[id] = true
	push_warning("ToolCursors: %s unavailable — %s" % [id, why])
