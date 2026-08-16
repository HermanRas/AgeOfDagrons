## The resource counter column (PLAN.md 7.1): stone/gold/wood/food plus
## idle/total villagers, styled per UI_Design.md 3 as a vertical stack of
## icon+number badges sitting above the minimap, not the plain text row this
## used to be.
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

const _ICON_DIR := "res://assets/ui/icons/"
const _ICON_SIZE := Vector2(24.0, 24.0)

## UI_Design.md 3's stacking order: Stone, Gold, Wood, Food, then villagers.
const _DISPLAY_ORDER: Array[StringName] = [&"stone", &"gold", &"wood", &"food"]


## Built in `_init()`, not `_ready()`: nothing here needs the node to be inside
## a tree, and a bare `.new()` fully wiring itself (labels built, EventBus
## connected) is what lets a test exercise it without adding it to a SceneTree,
## the same way GameView's pool/terrain are field initializers rather than
## `_ready()`-only setup.
func _init() -> void:
	custom_minimum_size = Vector2(120.0, 0.0)
	var bg := HudStyle.add_panel_background(self)
	# Tuned in the ui_builder HUD mockup against the dragon-frame art: the frame's
	# gold border is thicker along the top and left than the plain 10px margin
	# HudStyle's default fit assumed, and KEEP_ASPECT_COVERED (vs. the shared
	# STRETCH_SCALE default) keeps the border's own proportions correct.
	if bg != null:
		bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED

	# The bottom margin is 28, not the 8 it started at. The frame art's bottom
	# border is nearly as deep as its top one, and 8 px put the last row -- the
	# villager count -- underneath it, clipped (found live, screenshotted: the
	# pop counter was sliced by the border). The top margin was already 35 for
	# exactly this reason on the other side; the bottom simply never got the same
	# treatment because the panel used to end in a resource row that happened to
	# sit higher.
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 35)
	margin.add_theme_constant_override("margin_bottom", 28)
	add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	margin.add_child(column)

	for kind in _DISPLAY_ORDER:
		_stock_labels[kind] = _add_badge(column, "res_%s.png" % kind)
	_villagers_label = _add_badge(column, "res_villagers.png")

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
		(_stock_labels[kind] as Label).text = str(stock_of(kind))
	_villagers_label.text = "%d/%d" % [_idle, _total]


## One row: the resource's icon (or nothing, if it hasn't landed yet -- the
## number alone still reads) followed by its count label.
func _add_badge(column: VBoxContainer, icon_file: String) -> Label:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	column.add_child(row)

	var icon_path := _ICON_DIR + icon_file
	if ResourceLoader.exists(icon_path):
		var icon := TextureRect.new()
		icon.texture = load(icon_path)
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		# Without this, TextureRect's default EXPAND_KEEP_SIZE makes its real
		# minimum size the texture's own pixels (the icon pack ships at
		# 100x100) regardless of custom_minimum_size below -- exactly the
		# HudStyle.add_panel_background() bug, just not caught here too. Five
		# rows of that ballooned this panel to 532px tall and off the bottom
		# of a 648px viewport (found live, screenshotted).
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.custom_minimum_size = _ICON_SIZE
		row.add_child(icon)

	var label := Label.new()
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", HudStyle.GOLD)
	row.add_child(label)
	return label
