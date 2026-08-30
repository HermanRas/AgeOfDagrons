## The three volume sliders (PLAN.md 8.2b, 13.2 item 11).
##
## Shared by the in-match SETTINGS page (`PauseMenu`, reached from the corner
## button beside the minimap) and the front door's SETTINGS button, because the
## alternative was the same three rows built twice and drifting -- and a mix
## control that behaves differently depending on where you opened it is worse
## than one that only exists in one place.
##
## THREE SLIDERS CONTROL EVERYTHING, which is a property of the BUS GRAPH rather
## than of this panel: `AudioManager.BUS_SENDS` routes UI, VOICE and AMBIENT into
## SFX, so "Effects" really does mean everything that is not music. Six sliders
## would be a mixing desk nobody asked for, and on a phone it is six things to
## miss with a thumb. Per-category trim still exists in the data for whoever needs
## it, it just is not a player-facing control.
##
## It writes straight through to `AudioManager`, which persists to `user://` on
## every change. There is no OK/Cancel and there should not be: the feedback for a
## volume slider is that the volume changes, and a player who has heard the result
## has already decided.
class_name VolumePanel
extends VBoxContainer

## Label -> bus, in the order drawn. "Effects" rather than "SFX" because that is
## what it means to a player, and because it is not only the SFX bus.
const ROWS: Array = [
	["Master", &"Master"],
	["Music", &"MUSIC"],
	["Effects", &"SFX"],
]

## A thumb needs a target. 30 px is the smallest that stayed comfortable, judged
## the same way the 76 px menu buttons were.
const ROW_HEIGHT := 30.0

## What one row costs vertically: the label, the 2 px gap under it, and the
## slider. Exposed because the caller has to lay out whatever sits BELOW the
## panel, and measuring it by hand is how that drifts (see PauseMenu, where the
## buttons went under the sliders and the panel had to grow to fit both).
const ROW_TOTAL := 19.0 + 2.0 + ROW_HEIGHT

## Between rows.
const ROW_SEPARATION := 6


## Total height for `ROWS.size()` rows. One number for the caller to trust.
static func height() -> float:
	return ROWS.size() * ROW_TOTAL + (ROWS.size() - 1) * ROW_SEPARATION

var _sliders: Dictionary = {}


func _init(width: float = 240.0) -> void:
	add_theme_constant_override("separation", ROW_SEPARATION)
	custom_minimum_size.x = width
	for row in ROWS:
		add_child(_row(row[0], row[1], width))


## Label above the slider, not beside it: at 240 px a side-by-side label leaves
## the slider too short to aim at.
func _row(text: String, bus: StringName, width: float) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)

	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 15)
	box.add_child(label)

	# ⚠️ **A `TouchSlider`, NOT AN `HSlider`** (project owner, 2026-08-30: *"on android
	# while in game opening settings does not allow me to interact with volume sliders"*).
	# Godot's `Slider` reads mouse events and nothing else, and `GameScene` turns mouse
	# emulation OFF for the length of a match so the camera does not pan twice per thumb --
	# so these three were **completely inert** on the phone from the moment they landed,
	# and worked perfectly on the front door's copy of this same panel. Measured; see
	# `TouchSlider`'s header for the table and for why the fix is the control rather than
	# the project setting.
	var slider := TouchSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = AudioManager.bus_volume(bus)
	slider.custom_minimum_size = Vector2(width, ROW_HEIGHT)
	# An HSlider is not a BaseButton, so `AudioManager`'s automatic click sound
	# does not reach it -- which is wanted. A click per 0.05 step while dragging
	# would be a machine gun.
	slider.value_changed.connect(
		func(v: float) -> void: AudioManager.set_bus_volume(bus, v))
	box.add_child(slider)

	_sliders[bus] = slider
	return box


## Re-read the live values. Called when the panel is shown, because the OTHER
## copy of it may have been the one last touched -- `AudioManager` is the single
## source of truth and neither panel may assume it still holds it.
##
## `set_value_no_signal`, or refreshing would fire `value_changed` and write the
## value it just read back to the bus. Harmless today; a loop the moment anything
## rounds or clamps.
func refresh() -> void:
	for bus in _sliders:
		(_sliders[bus] as TouchSlider).set_value_no_signal(AudioManager.bus_volume(bus))
