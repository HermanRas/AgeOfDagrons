## The resource counter column (PLAN.md 7.1): stone/gold/wood/food plus the
## population row -- units on the map against the limit their buildings provide
## (4.11) -- styled per UI_Design.md 3 as a vertical stack of icon+number badges
## sitting above the minimap, not the plain text row this used to be.
##
## The bottom row showed IDLE/TOTAL villagers until 2026-08-17. That was wrong on
## both halves: it is the population counter, and idle villagers belong to the age
## header's badge, which is a button that walks to them (`IdleVillagerBadge`).
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
var _pop_used: int = 0
var _pop_cap: int = 0

var _stock_labels: Dictionary = {}   # StringName kind -> Label
var _pop_label: Label

const _ICON_DIR := "res://assets/ui/icons/"
const _ICON_SIZE := Vector2(24.0, 24.0)

## UI_Design.md 3's stacking order: Stone, Gold, Wood, Food, then villagers.
##
## PUBLIC, because it is the order the player has already learned -- the market
## page (8.2b) orders its tribute buttons and exchange rows by it so the four
## resources read the same way everywhere they are listed. Was private until there
## was a second place that listed them.
const DISPLAY_ORDER: Array[StringName] = [&"stone", &"gold", &"wood", &"food"]


## Built in `_init()`, not `_ready()`: nothing here needs the node to be inside
## a tree, and a bare `.new()` fully wiring itself (labels built, EventBus
## connected) is what lets a test exercise it without adding it to a SceneTree,
## the same way GameView's pool/terrain are field initializers rather than
## `_ready()`-only setup.
## The box this panel occupies. Still FIXED rather than sized to its rows, but for a
## much duller reason than it used to be: five rows of a 24 px icon and a 16 pt number
## want a predictable column, and the minimap below it is a fixed size too.
##
## THE LONG NOTE THAT USED TO BE HERE IS OBSOLETE AND IS WORTH KNOWING ABOUT. It
## explained that the background was drawn KEEP_ASPECT_COVERED so the art's own
## proportions survived, and that the panel's aspect therefore decided WHERE the crop
## fell -- 152x196 (0.776) against art at 160x192 (0.833) filled the height, while an
## auto-sized 152x179 filled the width and put the gold border somewhere else relative
## to the rows. All of that was true of a fixed bitmap stretched to fit. The plate is a
## NINE-PATCH now (`HudStyle.PANEL_MARGIN`): its border is 46 px of a 1024 px source at
## every size, there is no crop and no aspect to preserve, and the panel could be
## resized freely without the frame moving. Kept as a note because the same class of
## bug will come back the day anything here goes back to a scaled bitmap.
const PANEL_SIZE := Vector2(152.0, 196.0)


func _init() -> void:
	custom_minimum_size = PANEL_SIZE
	HudStyle.add_panel_background(self)

	# INSIDE THE PLATE'S OWN BORDER. These were 22/10/35/8 -- asymmetric, because the
	# old art's gold edge was thicker along the top and left and the numbers were eyed
	# against it in the mockup. The nine-patch border is even on all four sides, so the
	# margins are even too, and they are derived from it rather than tuned: the plate's
	# 46 px border on a 1024 px source draws at about 7 px on a 152 px panel, and 12
	# clears it with room for the icons not to touch the moulding.
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 12)
	add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	margin.add_child(column)

	for kind in DISPLAY_ORDER:
		_stock_labels[kind] = _add_badge(column, "res_%s.png" % kind)
	_pop_label = _add_badge(column, "res_villagers.png")

	_refresh_labels()

	EventBus.resources_changed.connect(_on_resources_changed)
	EventBus.population_changed.connect(_on_population_changed)


func _exit_tree() -> void:
	EventBus.resources_changed.disconnect(_on_resources_changed)
	EventBus.population_changed.disconnect(_on_population_changed)


func stock_of(kind: StringName) -> int:
	return int(_stock.get(kind, 0))


## Units on the map, and the population limit their buildings provide.
func population() -> Vector2i:
	return Vector2i(_pop_used, _pop_cap)


func _on_resources_changed(p_id: int, stock: Dictionary) -> void:
	if p_id != player_id:
		return
	_stock = stock
	_refresh_labels()


func _on_population_changed(p_id: int, used: int, cap: int) -> void:
	if p_id != player_id:
		return
	_pop_used = used
	_pop_cap = cap
	_refresh_labels()


func _refresh_labels() -> void:
	for kind in _stock_labels:
		(_stock_labels[kind] as Label).text = str(stock_of(kind))
	# Units on the map over the population limit (PLAN.md 4.11), NOT idle over
	# total -- which is what this row used to show, and was never what it was for
	# (project owner, 2026-08-17). Idle villagers are the age header's badge.
	_pop_label.text = "%d/%d" % [_pop_used, _pop_cap]


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
		# A counter is read, never pressed, and `mouse_filter` does not inherit
		# from the panel -- see NoticeToast._init for what a display TextureRect
		# left on Control's STOP default did to the build grid.
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)

	var label := Label.new()
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", HudStyle.GOLD)
	row.add_child(label)
	return label
