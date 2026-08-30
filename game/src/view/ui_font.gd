## The two typefaces, and the one rule about which goes where.
##
## THE GAME SHIPPED NO FONT AT ALL UNTIL 2026-08-30. There was no `.ttf` or `.otf`
## anywhere under `game/` and every label drew in Godot's built-in default, which is
## why asset_request.md [P8] 4b called the typeface "the one part of the overhaul that
## touches every screen at once". It does, and this file is deliberately not how it
## does it: the BODY face is `gui/theme/custom_font` in `project.godot`, one line that
## reaches every Control in the project without a single call site changing.
##
## THE POINTER IN `project.godot` DID NOT SURVIVE ITS FIRST `--import`, which is §6 of
## AGENT_GAME_CODER.md arriving exactly on schedule: Godot rewrites that file and strips
## every comment from it. So there is nothing there to explain the two settings, and
## this paragraph is the only record that `gui/theme/custom` (the button plates plus a
## `default_font`) and `gui/theme/custom_font` (the same face again) are BOTH set on
## purpose. Either alone would give the game its typeface; carrying both means a theme
## that fails to load costs the buttons and not the words.
##
## THE BODY FACE IS **NEW ROCKER**, AND IT WAS CHOSEN ON ITS DIGITS. MedievalSharp went
## in first and lasted a day. The owner's verdict on the first three candidates was that
## "the numbers on all 3 read hard" -- which is the right test for this game and not the
## obvious one: an RTS HUD is mostly NUMBERS, and a specimen sheet set in words will
## happily sell you a face whose 0/6/8 are indistinguishable at 16 px. The second round
## was judged on `assets/UI_Gen/font_comparison.png`, which leads with `0123456789` and
## with the strings the HUD actually prints -- `4870`, `6/10`, `2000 / 2000`, `84%`,
## `50G 100F` -- at the sizes it prints them.
##
## SO WHAT IS HERE IS ONLY THE EXCEPTION -- the display face for things that are a
## NAME rather than a sentence. A title, a menu button, the result screen's verdict.
## Cinzel Decorative is a Roman capitalis; it is magnificent at 28 px and unreadable at
## 11, so it is opt-in per label and never a default.
##
## BOTH FAMILIES ARE SIL OPEN FONT LICENSE 1.1, confirmed by reading each archive's
## own `OFL.txt` rather than by recognising the names. That is the difference between
## these and Kibyra's packs and it is the whole reason they can be committed: the OFL
## permits redistribution, so a clean checkout gets them. The two conditions that bite
## are that the licence text must ship with the fonts -- it does, as
## `assets/ui/fonts/OFL-*.txt`, and `game/assets/LICENCES.md` says so -- and the
## Reserved Font Name, which only applies to a MODIFIED build keeping the name.
## Nothing here modifies a font.
class_name UiFont
extends RefCounted

const BODY_PATH := "res://assets/ui/fonts/NewRocker-Regular.ttf"
const TITLE_PATH := "res://assets/ui/fonts/CinzelDecorative-Bold.ttf"
const TITLE_HEAVY_PATH := "res://assets/ui/fonts/CinzelDecorative-Black.ttf"

## Below this, Cinzel Decorative stops being legible and starts being texture.
##
## MEASURED BY LOOKING, not chosen: it is a high-contrast Roman capitalis with fine
## serifs, and its thin strokes fall below one pixel somewhere in the low teens. Every
## caller that wants a title smaller than this wants the body face instead, and
## `title()` refuses rather than obliging -- a title that has quietly degraded into a
## grey smear is harder to notice than one that is simply the wrong face.
const TITLE_MIN_SIZE := 16


## Put the display face on `label` (or any Control with a `font` theme item) at
## `size`, and do nothing at all below `TITLE_MIN_SIZE`.
##
## RETURNS WHETHER IT APPLIED, so a caller can tell the difference between "titled"
## and "left as body text" without re-deriving the threshold. Nothing reads it today;
## it is there because a silent no-op is the one thing about this function that could
## surprise somebody.
static func title(label: Control, size: int, heavy: bool = false) -> bool:
	if size < TITLE_MIN_SIZE:
		return false
	var path := TITLE_HEAVY_PATH if heavy else TITLE_PATH
	if not ResourceLoader.exists(path):
		return false
	label.add_theme_font_override("font", load(path))
	label.add_theme_font_size_override("font_size", size)
	return true


## The body face as a resource, for the handful of places that draw a string
## themselves (`ControlGroupSlot._draw`, `Minimap`) and cannot go through a theme
## override because there is no Control to hang one on.
##
## Falls back to `ThemeDB`'s default rather than returning null: every caller of this
## is inside a `_draw`, where a null font is a hard error and a wrong font is a
## cosmetic one.
static func body() -> Font:
	if ResourceLoader.exists(BODY_PATH):
		return load(BODY_PATH)
	return ThemeDB.fallback_font
