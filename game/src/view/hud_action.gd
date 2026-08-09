## One entry in the selection panel's action column or detail grid (UI_Design.md
## selection-panel redesign).
##
## Deliberately a plain data record, not a widget: `SelectionActions` decides
## WHAT a selection can do from facts alone (headlessly testable, no tree), and
## `ActionSlot` decides how one is drawn. Keeping those apart is what lets the
## action set be asserted in a test without instancing a single Control, the
## same split `GameView.tap_action()` already uses for taps.
##
## `enabled = false` is the "coming soon" state, not an error: MVP has no
## combat, repair, research or formations (see `SelectionActions` for which),
## so those slots are laid out and greyed rather than left out, which is how
## the minimap's corner buttons already handle the same problem. Each becomes
## live by flipping this one flag once its command exists.
class_name HudAction
extends RefCounted

## Stable identifier -- `&"move"`, `&"stop"`, `&"destroy"`, or a
## parameterised one like `&"train:unit.villager"` / `&"build:building.house"`.
## `SelectionPanel` emits this back out; nothing switches on it internally.
var id: StringName = &""

## Shown under the icon, and INSTEAD of it when no icon art exists yet
## (ASSET_MISSING.md 1.5) -- a labelled empty frame still reads as an action.
var label: String = ""

## Filename inside `res://assets/ui/icons/`, or "" for none. Several of these
## are deliberately the nearest existing icon rather than bespoke art; see
## `SelectionActions.ICONS`.
var icon: String = ""

## False draws the slot greyed and swallows its press. See the class header.
var enabled: bool = true

## Small corner text -- a production queue count, an overflow "+N". Empty
## draws nothing.
var badge: String = ""

## Tapping this fills the DETAIL grid instead of issuing an order -- Build on a
## villager offers buildings, Move on a soldier offers formations. The panel
## tracks which action is expanded and re-asks for its details.
var expands: bool = false

## Free-form rider the caller needs back: the `def_id` a train/build action
## names, the entity id a portrait stands for. Never interpreted here.
var payload: Variant = null


func _init(p_id: StringName = &"", p_label: String = "", p_icon: String = "",
		p_enabled: bool = true) -> void:
	id = p_id
	label = p_label
	icon = p_icon
	enabled = p_enabled
