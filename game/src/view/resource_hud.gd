## The resource counter row (PLAN.md 7.1): stone/gold/wood/food plus idle/total
## villagers.
##
## Deliberately plain text, in the same spirit as SelectionPanel's stand-in
## (4.3): the real icons are ASSET_MISSING.md 1.5's TODO, and whatever is drawn
## here is thrown away the day they land, so it is not worth polishing now.
##
## Reads ONLY from `EventBus` (PLAN.md 6.2), never from the sim and never by
## holding a `GameView` reference -- the same separation SelectionPanel keeps by
## reading `facts_for()` instead of reaching into `SimWorld`. `GameScene` is the
## thing that currently computes these numbers and emits them; this control does
## not need to know that, or it would need to change every time that does.
class_name ResourceHUD
extends PanelContainer

## Which player this HUD reports on. Set once by whoever builds it (GameScene).
## Every signal for a different player is ignored -- in solo play there is only
## ever one, but the filter is what keeps this correct the day a second player
## exists rather than something to add later.
var player_id: int = 0

## Last values applied, kept apart from the Label text so both the labels and a
## test (or a future tooltip) can read "what is this HUD currently showing"
## without parsing it back out of a formatted string.
var _stock: Dictionary = {}
var _idle: int = 0
var _total: int = 0

var _stock_labels: Dictionary = {}   # StringName kind -> Label
var _villagers_label: Label


## Built in `_init()`, not `_ready()`: nothing here needs the node to be inside
## a tree, and a bare `.new()` fully wiring itself (labels built, EventBus
## connected) is what lets a test exercise it without adding it to a SceneTree,
## the same way GameView's pool/terrain are field initializers rather than
## `_ready()`-only setup.
func _init() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	add_child(row)

	for kind in GameDefs.RESOURCE_KINDS:
		var label := Label.new()
		row.add_child(label)
		_stock_labels[kind] = label

	_villagers_label = Label.new()
	row.add_child(_villagers_label)

	_refresh_labels()

	EventBus.resources_changed.connect(_on_resources_changed)
	EventBus.villagers_changed.connect(_on_villagers_changed)


func _exit_tree() -> void:
	EventBus.resources_changed.disconnect(_on_resources_changed)
	EventBus.villagers_changed.disconnect(_on_villagers_changed)


func stock_of(kind: StringName) -> int:
	return int(_stock.get(kind, 0))


func villager_counts() -> Vector2i:
	return Vector2i(_idle, _total)


func _on_resources_changed(p_id: int, stock: Dictionary) -> void:
	if p_id != player_id:
		return
	_stock = stock
	_refresh_labels()


func _on_villagers_changed(p_id: int, idle: int, total: int) -> void:
	if p_id != player_id:
		return
	_idle = idle
	_total = total
	_refresh_labels()


func _refresh_labels() -> void:
	for kind in _stock_labels:
		(_stock_labels[kind] as Label).text = "%s %d" % [_tag(kind), stock_of(kind)]
	_villagers_label.text = "V %d/%d" % [_idle, _total]


## Stand-in for the icon: the resource's initial, capitalised, so the row reads
## as a row of counters and not as a sentence -- "F 50" not "food 50".
func _tag(kind: StringName) -> String:
	return String(kind).left(1).to_upper()
