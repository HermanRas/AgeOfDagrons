## The tool's shared look: the `panel_hud` plate, and the colours that go with it (PLAN.md 16.4f).
##
## Owner, 2026-09-09: *"for map maker we will use the same `panel_hud.png` for all the panels, and
## same font used in the game."* The font is one line in `project.godot`
## (`gui/theme/custom_font`); this file is the plate and the palette.
##
## ## IT EXISTS BECAUSE SIX CONSTANTS WERE DECLARED TWICE
##
## `_TEXT`, `_DIM` and `_PANEL` were in **both** `editor.gd` and `object_palette.gd`, and `boot.gd`
## carried its own `_OK`/`_BAD`/`_WARN`/`_DIM` besides. Three flat plates were built from three
## copies of one recipe. That is §6's *"mirroring a layout is not sharing one"* with colours
## instead of widths — and the failure is not dramatic, it is drift: one panel goes brown and the
## other two stay grey, each correct according to its own file. `HudStyle` is the game's precedent
## and its header makes the same argument: *"the three read as one system rather than three one-off
## implementations."*
##
## ## ⚠️ THE 1:1 BORDER TRAP, AND WHY 12 IS ALREADY THE ANSWER
##
## Godot draws a nine-patch border **at 1:1** — the margin is in SOURCE pixels and does not scale
## with the rect. The art's painted border measures **46 px** on the 1024 px master, and 46 would
## put 92 px of corner on a 200 px inspector row. **Shrinking the margin is worse than leaving it**:
## the margin says where the border ENDS, so 12 against a painted 46 leaves 34 px of bevel inside
## the stretched region, smeared across the panel.
##
## The only lever is the SOURCE SIZE, and `tools/prepare_ui_chrome.py` has already pulled it: the
## committed `panel_hud.png` is **267 px, not 1024**, sized so its painted border comes out at 12.
## So `MARGIN` is 12, it matches `HudStyle.PANEL_MARGIN` in the game, and **it is right at every
## size this tool draws** — a 200 px row and a 1200 px dialog get the same moulding, which is the
## whole property a nine-patch has and the fixed bitmap it replaced did not. No `EXTRA_SIZES`
## output is needed here and that script does not change.
##
## ## 📝 `StyleBoxTexture`, WHERE THE GAME USES A `NinePatchRect` CHILD
##
## `HudStyle.add_panel_background()` adds a full-rect nine-patch child and overrides the panel
## stylebox to `StyleBoxEmpty`, because a `PanelContainer`'s own fill would otherwise show through
## the art's transparent rounded corners as a halo (found live, comparing the HUD builder against
## the running game). A `StyleBoxTexture` **replaces** that fill rather than sitting behind it, so
## the halo cannot arise, `content_margin_*` gives the gutter with no extra node, and a
## `PanelContainer` keeps doing its own layout. Same drawing, less machinery.
##
## **Stretched, not tiled.** `measure_ninepatch.py` reports this plate's edge as plain moulding
## (period 1); the one piece in the set that repeats is `panel_ornate`, which this tool does not
## use.
class_name UiChrome
extends RefCounted

const PANEL_PATH := "res://assets/ui/chrome/panel_hud.png"

## The drawn border, in screen pixels. **Not the 46 the art measures** — see the class comment.
const MARGIN := 12

# ── the palette ─────────────────────────────────────────────────────────────
#
# ⚠️ **THE CANVAS SURROUND IS THE ONE SURFACE THAT STAYS NEUTRAL, AND IT IS DELIBERATE.** Every
# panel goes brown and gold; the ground behind the MAP does not. An author judges terrain colours
# against whatever surrounds them, and a warm brown surround shifts the apparent hue of grass,
# sand and shallow water — so the one place that must stay grey is the one the map is seen
# against. Same class of reasoning as the minimap's ally tint being settled on CIE L* rather than
# on hue: the question is what a colour is judged NEXT TO.

## Behind the canvas. Neutral on purpose — see above.
const BG := Color(0.09, 0.09, 0.11)

## The flat plate, kept as the fallback when the art is missing and as the colour the plate's own
## recess is matched against.
const PANEL := Color(0.13, 0.13, 0.16)

## Ordinary text on a plate. Warmer than the old `#D1D1DB` so it sits on brown rather than on
## grey — the same move the game made when the HUD stopped being flat.
const TEXT := Color(0.91, 0.87, 0.78)

## Secondary text: a disabled inspector, a row count, a hint.
const DIM := Color(0.66, 0.62, 0.55)

## The accent. `HudStyle.GOLD`, verbatim, because the two projects are showing the same art and a
## second opinion about which gold would be visible.
const GOLD := Color("#E5B842")

const GOOD := Color(0.55, 0.80, 0.55)
const BAD := Color(0.95, 0.45, 0.40)
const WARN := Color(0.95, 0.78, 0.35)

## Set true to draw the flat plates regardless of what is on disk.
##
## `IconAtlas.ignore_atlases`' precedent and for its reason: **the fallback path is one this
## machine never takes**, since the plate is committed — so without a lever it would never be
## exercised at all and §5's *"the second rendering never gets looked at"* would apply. A test
## drives both branches through this.
static var ignore_art := false

static var _plate: Texture2D = null
static var _looked := false


## A panel plate with `pad` pixels of gutter inside its border.
##
## The gutter is ON TOP OF `MARGIN`, not inside it: content has to clear the moulding first, so
## `content_margin` is border + pad. Getting that wrong is what put the game's resource rows
## under their own frame — `ResourceHUD` had been padding to a painted bead instead of to the
## nine-patch margin, which is a different number.
static func panel_style(pad_h: int = 8, pad_v: int = 6) -> StyleBox:
	var tex := plate()
	if tex == null:
		return _flat_style(pad_h, pad_v)
	var box := StyleBoxTexture.new()
	box.texture = tex
	box.texture_margin_left = MARGIN
	box.texture_margin_right = MARGIN
	box.texture_margin_top = MARGIN
	box.texture_margin_bottom = MARGIN
	box.content_margin_left = MARGIN + pad_h
	box.content_margin_right = MARGIN + pad_h
	box.content_margin_top = MARGIN + pad_v
	box.content_margin_bottom = MARGIN + pad_v
	return box


## A theme carrying nothing but the tool's text colour.
##
## ⚠️ **THIS EXISTS BECAUSE `gui/theme/custom_font` CHANGES THE FACE AND NOT THE COLOUR**, and the
## first render of the plates showed exactly that: `Label`s came out cream (they carry per-control
## `font_color` overrides) while every `Button`, `LineEdit`, `OptionButton` and `SpinBox` stayed the
## engine default's cold `#DFDFDF`. Measured off the screenshot: 223,223,223 beside 232,222,199.
##
## On the flat grey panels those two were indistinguishable, which is why nobody had noticed. **On
## a warm brown plate the cold grey reads as a different family** — which is precisely the
## complaint the owner made about the game's age panel: *"the only chrome left on screen using the
## plain plate ... it reads as a different family."*
##
## **It sets font colours and nothing else.** Not button plates, not margins, not the panel
## stylebox — those are `panel_style()`'s and the individual screens'. A fuller theme is the
## game's `aod_theme.tres`, and copying that here would drag in button art the owner did not ask
## for and a second copy of a file that is not hash-checked.
##
## 📝 **TYPE INHERITANCE DOES THE REST.** Godot's theme lookup walks a control's class hierarchy,
## so `Button` covers `OptionButton`, `CheckBox` and `CheckButton` without naming them. The types
## below are the ones the tool actually builds; `SpinBox` is named because it is a `Range` and not
## a `Button`, and its child `LineEdit` is what draws the number.
static func theme() -> Theme:
	var t := Theme.new()
	for type in ["Button", "OptionButton", "LineEdit", "SpinBox", "ItemList", "Label"]:
		t.set_color("font_color", type, TEXT)
	# HOVER AND PRESSED TOO, or a button reverts to cold grey under the pointer -- which is worse
	# than being cold all the time, because it only shows up while somebody is using it.
	for entry in ["font_hover_color", "font_pressed_color", "font_focus_color"]:
		t.set_color(entry, "Button", TEXT)
	t.set_color("font_disabled_color", "Button", DIM)
	# THE PLACEHOLDER IS THE ONE THAT MUST NOT BE `TEXT`: "search" and "New Map" would then look
	# like typed content, and an author would clear a field that was already empty.
	t.set_color("font_placeholder_color", "LineEdit", DIM)
	t.set_color("font_selected_color", "ItemList", BG)
	return t


## The plate texture, or null. Loaded once.
##
## ⚠️ **`load()` WORKS HERE AND WOULD NOT IF THIS READ THE GAME'S COPY.** The plate is committed
## into THIS project and imported here, so it has a sidecar pointing into this project's cache.
## 16.3 measured what happens the other way round: the game's PNGs are inside the GAME's `res://`
## with a sidecar redirecting to `res://.godot/imported/...`, and `res://` from here is here — so
## `ResourceLoader.exists` answers TRUE and `load()` returns null plus three engine errors *per
## attempt*. Reading the game's `assets/ui/` directly was therefore never an option; a committed
## copy is what makes this one line rather than an `Image.load_from_file` path.
static func plate() -> Texture2D:
	if ignore_art:
		return null
	if _looked:
		return _plate
	_looked = true
	if not FileAccess.file_exists(PANEL_PATH):
		push_warning("UiChrome: %s is missing — panels will draw flat" % PANEL_PATH)
		return null
	var res := load(PANEL_PATH)
	if res == null or not (res is Texture2D):
		push_warning("UiChrome: %s did not load — run: godot --headless --path MapMaker --import"
				% PANEL_PATH)
		return null
	_plate = res as Texture2D
	return _plate


## Is the tool drawing the real plate? `Boot` reports it; a test asserts both answers.
static func has_plate() -> bool:
	return plate() != null


static func forget() -> void:
	_plate = null
	_looked = false


## The look this tool had before the plate, and the honest fallback if the art goes missing.
##
## ⚠️ **A MISSING PLATE MUST NOT MEAN NO STYLEBOX**, which is the one thing that separates this
## from `ToolIcons`' deliberate no-fallback. A button with no icon still has its word; a panel with
## no plate has **no visible boundary at all** — every control floats on the canvas surround and
## the tool reads as broken rather than as unstyled. So the fallback is a real second rendering
## here, and `ignore_art` is what keeps it exercised.
static func _flat_style(pad_h: int, pad_v: int) -> StyleBox:
	var box := StyleBoxFlat.new()
	box.bg_color = PANEL
	box.content_margin_left = pad_h
	box.content_margin_right = pad_h
	box.content_margin_top = pad_v
	box.content_margin_bottom = pad_v
	return box
