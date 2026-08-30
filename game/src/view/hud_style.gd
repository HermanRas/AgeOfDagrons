## Shared look for the HUD panels (dark-brown/gold): the panel plate plus the gold
## accent colour. `SelectionPanel` originated this look; `ResourceHUD` and `Minimap`
## now share it through here instead of each re-loading the texture and re-typing the
## colour, so the three read as one system rather than three one-off implementations.
##
## THE PLATE CHANGED TWICE ON 2026-08-30 and both halves matter. It was Kibyra's
## `hud/panel_background.png` -- 160x192, third-party, un-redistributable, and the
## reason `game/assets/ui/` was gitignored. It is now `chrome/panel_hud.png`, project
## art, 1024x1024, and drawn as a NINE-PATCH rather than a scaled bitmap.
##
## THE NINE-PATCH IS THE REAL CHANGE, not the file. `panel_background` was a fixed
## bitmap drawn at a dozen different sizes, so its border thickness varied with the
## panel: `ResourceHUD` had to pin a 152x196 box and switch to KEEP_ASPECT_COVERED to
## get the crop it wanted, and `HudPanel` refused to use it at full-page size at all
## because a filled panel stretched that far reads as a smear. A nine-patch has one
## border thickness at every size, which is the property both of those were working
## around.
class_name HudStyle
extends RefCounted

const PANEL_BG_PATH := "res://assets/ui/chrome/panel_hud.png"

## MEASURED off the art, then RESIZED to make this number the right one.
##
## `tools/measure_ninepatch.py` reports the painted border at 46 px of the 1024 px
## master (noise floor 3 against a cut of 11, so the run is separating something
## real). The handover in asset_request.md quoted 64; measured beats quoted.
##
## 46 IS NOT WHAT GOES HERE, AND THAT IS THE TRAP THIS COMMENT EXISTS FOR. Godot draws
## a NinePatchRect's border AT 1:1 -- the margin is in SOURCE pixels and does not scale
## with the rect. A 46 px border on the 152 px resource panel is 92 of its 152 pixels,
## and the counters get clipped by their own frame. Shrinking the margin instead makes
## it worse rather than better: the margin says where the border ENDS, so 12 against a
## painted 46 leaves 34 px of bevel inside the stretched region, smeared across the
## panel. The only lever that moves the DRAWN border is the source size.
##
## So `tools/prepare_ui_chrome.py` writes `game/assets/ui/chrome/` at the size that
## makes the painted border come out at the thickness a widget wants -- 1024 -> 267 for
## this plate -- and 12 is that thickness. Change the wanted figure THERE and this
## follows; changing it here alone smears the moulding.
##
## STRETCHED, NOT TILED. The same tool reports this plate's edge is plain moulding
## (period 1); the one piece in the set that repeats is `banner_alert`, which
## `NoticeToast` draws whole rather than patching at all.
const PANEL_MARGIN := 12

## The ORNATE plate, at the size the resource counter draws it (project owner,
## 2026-08-30: *"swap the resources frame to panel_ornate type"*).
##
## A SEPARATE FILE FROM THE MENU'S COPY OF THE SAME ARTWORK, and it has to be. Godot
## draws a nine-patch border at 1:1, so the 90 px border that reads correctly on the
## 640 px main menu would leave nothing at all between the corners of a 152 px panel.
## `tools/prepare_ui_chrome.py` emits `panel_ornate_small` off the same master at a
## tenth scale; its `EXTRA_SIZES` table is where that decision lives.
const PANEL_ORNATE_PATH := "res://assets/ui/chrome/panel_ornate_small.png"
const PANEL_ORNATE_MARGIN := 30

const GOLD := Color("#E5B842")
const DARK_BG := Color("#2B1D14")


## Adds a panel plate as a full-rect, mouse-ignoring backdrop behind `target`'s
## other children. Returns null (adding nothing) if the art is missing, the same
## "leave it out rather than fake it" convention every other optional asset load in
## this codebase follows.
##
## `ornate` picks the dragon-cornered frame over the plain one. It is a flag rather
## than a second function because the two differ only in a path and a number, and the
## trap they share -- the 1:1 border -- is one both callers need explained once.
##
## RETURNS A NinePatchRect, where this used to return a TextureRect. The one caller
## that touched the return value was `ResourceHUD`, and it touched it to fix a crop
## that a nine-patch does not have.
static func add_panel_background(target: Control, ornate: bool = false) -> NinePatchRect:
	# PanelContainer/Panel draw their own themed "panel" StyleBox regardless of
	# what children are added -- left alone, its default rectangular fill shows
	# through the art's transparent, rounded corners as a shadow-like halo (found
	# live comparing the in-editor HUD builder against the running game).
	target.add_theme_stylebox_override("panel", StyleBoxEmpty.new())

	var path := PANEL_ORNATE_PATH if ornate else PANEL_BG_PATH
	var margin := PANEL_ORNATE_MARGIN if ornate else PANEL_MARGIN
	if not ResourceLoader.exists(path):
		return null
	var bg := NinePatchRect.new()
	bg.texture = load(path)
	# LINEAR. This is a painted plate drawn at some size other than its own; NEAREST
	# was correct for the pixel-art plate it replaced and is what made everything
	# scaled crunchy. See the sweep of 2026-08-30.
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	bg.patch_margin_left = margin
	bg.patch_margin_right = margin
	bg.patch_margin_top = margin
	bg.patch_margin_bottom = margin
	if ornate:
		# TILE_FIT, NOT STRETCH. The ornate frame's edges are a run of BEADS, and a
		# repeating ornament pulled to three times its length is a run of ellipses.
		# TILE_FIT over plain TILE because it nudges the repeat to a whole number, so
		# an edge does not end on half a bead.
		bg.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_TILE_FIT
		bg.axis_stretch_vertical = NinePatchRect.AXIS_STRETCH_MODE_TILE_FIT
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	target.add_child(bg)
	target.move_child(bg, 0)
	return bg
