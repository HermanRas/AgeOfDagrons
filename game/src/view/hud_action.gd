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

## WHICH ONE OF A SET IS CURRENTLY IN FORCE -- the stance a unit is on, the formation
## its moves are using (4.12, 4.14). Drawn as a ring by `ActionSlot`.
##
## A THIRD STATE, and it had to be: `enabled` already means two things a player must be
## able to tell apart from this one ("not built yet" and "nothing to act on"), and both
## draw greyed. A stance the unit is already on is neither -- it is live, pressable, and
## the answer to "which of these four am I looking at". Reusing `enabled = false` for it
## would have made the current stance the one slot that looks broken.
##
## Ignored by every action that is not one of a set, which is nearly all of them.
var selected: bool = false

## Free-form rider the caller needs back: the `def_id` a train/build action
## names, the entity id a portrait stands for. Never interpreted here.
var payload: Variant = null

## What pressing this costs, as `{kind: amount}` -- empty for anything free
## (project owner, 2026-08-22: "add resource cost per building & unit, per type of
## resource").
##
## A DICTIONARY RATHER THAN A FORMATTED STRING, so the one place that knows how to
## abbreviate a cost is `ActionSlot`. A pre-rendered "60F 20G" here would put a
## rendering decision in the pure-data half of the split this class exists to keep,
## and the panel could not then order the kinds the way the resource counter does.
var cost: Dictionary = {}


func _init(p_id: StringName = &"", p_label: String = "", p_icon: String = "",
		p_enabled: bool = true) -> void:
	id = p_id
	label = p_label
	icon = p_icon
	enabled = p_enabled
