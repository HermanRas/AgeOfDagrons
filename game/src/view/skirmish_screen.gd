## The skirmish settings screen (PLAN.md 1.6), **and the multiplayer lobby**.
##
## The two differ only in what fills a player slot, so this is one screen with one
## dropdown per slot: Human (this device) / PlayTest AI / Open (waiting for a peer).
## All-local is a skirmish; an Open slot plus a listening host is a multiplayer match.
## That is the whole reason there is no second screen: the flow tested solo tonight is
## the flow that runs on two devices, rather than a parallel path that first executes
## on the day it matters.
##
## Everything it collects **is** a `MatchConfig`, which is what `build_config()`
## returns -- so the screen has no vocabulary of its own to translate out of, and a
## test can assert what it would start without touching a scene tree.
##
## Built in `_init()` rather than `_ready()`, the convention every widget here follows.
## Uses Godot's stock `OptionButton`/`SpinBox` rather than the dragon-pack art: this is
## the `ResourceHUD`-at-7.1 stage of the screen, where the job is the WIRING and the
## skin comes later, and a settings screen made of TextureButtons would need art for
## every dropdown state before it could be used at all.
class_name SkirmishScreen
extends Control

## What fills a player slot. `OPEN` is the multiplayer half: the slot is advertised and
## a joining peer takes it (12.1), so it is offered but cannot be started on yet.
enum Role { HUMAN, PLAYTEST_AI, OPEN }

## Emitted with the assembled config. `GameScene` is reached through `Net.pending_match`
## rather than through this signal -- the signal is for tests and for whatever screen
## eventually wraps this one.
signal start_requested(cfg: MatchConfig)
signal back_requested()

const _GAME_SCENE := "res://scenes/game/Game.tscn"
const _MAIN_MENU_SCENE := "res://scenes/menu/MainMenu.tscn"
const _PREVIEW_SIZE := Vector2(320.0, 320.0)
const _SEED_MAX := 999999

## Player counts the generator supports. Only 2 is offered while nothing else is
## tested; shown DISABLED rather than hidden, so the limit is visible rather than
## looking like an oversight.
const _MAX_OFFERED_PLAYERS := 2

var _seed: int = 1
var _type: MapGenerator.Type = MapGenerator.Type.RANDOM
var _players: int = 2
var _mode: MatchConfig.Mode = MatchConfig.Mode.LAST_MAN_STANDING
var _roles: Array[Role] = [Role.HUMAN, Role.PLAYTEST_AI]
var _colours: Array[int] = [2, 1]          # yellow against red, the owner's default

var _data: MapData = null

var _preview: MapPreview
var _status: Label
var _seed_box: SpinBox
var _type_picker: OptionButton
var _start_button: Button
var _slot_rows: Array[Dictionary] = []      # {role: OptionButton, colour: Button}


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var backdrop := ColorRect.new()
	backdrop.color = HudStyle.DARK_BG
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 24)
	add_child(margin)

	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 12)
	margin.add_child(page)

	page.add_child(_heading("SKIRMISH"))

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(columns)
	columns.add_child(_build_map_column())
	columns.add_child(_build_match_column())

	regenerate()


# ── layout ──────────────────────────────────────────────────────────────────

func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", HudStyle.GOLD)
	return label


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", HudStyle.GOLD)
	label.custom_minimum_size = Vector2(110.0, 0.0)
	return label


func _build_map_column() -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)

	_preview = MapPreview.new()
	_preview.custom_minimum_size = _PREVIEW_SIZE
	column.add_child(_preview)

	var type_row := HBoxContainer.new()
	type_row.add_child(_label("Map"))
	_type_picker = OptionButton.new()
	# RANDOM first and selected, per 1.6: a random map is the default, and picking a
	# type is the deliberate act.
	for type in [MapGenerator.Type.RANDOM, MapGenerator.Type.ISLAND,
			MapGenerator.Type.RIVER, MapGenerator.Type.DESERT, MapGenerator.Type.FOREST]:
		_type_picker.add_item(MapGenerator.type_name(type), int(type))
	_type_picker.item_selected.connect(_on_type_selected)
	type_row.add_child(_type_picker)
	column.add_child(type_row)

	# THE SEED IS VISIBLE AND EDITABLE. Without it "I liked that map" has no answer but
	# a saved file, and two people cannot compare notes on the same layout.
	var seed_row := HBoxContainer.new()
	seed_row.add_child(_label("Seed"))
	_seed_box = SpinBox.new()
	_seed_box.min_value = 0
	_seed_box.max_value = _SEED_MAX
	_seed_box.value = _seed
	_seed_box.value_changed.connect(_on_seed_changed)
	seed_row.add_child(_seed_box)
	seed_row.add_child(_button("Re-generate", _on_reroll_pressed))
	column.add_child(seed_row)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(_PREVIEW_SIZE.x, 40.0)
	column.add_child(_status)
	return column


func _build_match_column() -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var count_row := HBoxContainer.new()
	count_row.add_child(_label("Players"))
	var count_picker := OptionButton.new()
	for n in range(MapGenerator.MIN_PLAYERS, MapGenerator.MAX_PLAYERS + 1):
		count_picker.add_item(str(n), n)
		if n > _MAX_OFFERED_PLAYERS:
			count_picker.set_item_disabled(count_picker.item_count - 1, true)
	count_picker.select(0)
	count_picker.disabled = _MAX_OFFERED_PLAYERS <= MapGenerator.MIN_PLAYERS
	count_row.add_child(count_picker)
	column.add_child(count_row)

	for i in range(_players):
		column.add_child(_build_slot_row(i))

	var mode_row := HBoxContainer.new()
	mode_row.add_child(_label("Victory"))
	var mode_picker := OptionButton.new()
	# Trophy and King of the Hill are DECLARED and inert (11.2), so they are listed and
	# disabled -- a mode that silently decided nothing would be worse than one greyed.
	for mode in [MatchConfig.Mode.LAST_MAN_STANDING, MatchConfig.Mode.TROPHY,
			MatchConfig.Mode.KING_OF_THE_HILL]:
		mode_picker.add_item(MatchConfig.mode_name(mode), int(mode))
		if mode != MatchConfig.Mode.LAST_MAN_STANDING:
			mode_picker.set_item_disabled(mode_picker.item_count - 1, true)
	mode_picker.select(0)
	mode_row.add_child(mode_picker)
	column.add_child(mode_row)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	_start_button = _button("START", _on_start_pressed)
	_start_button.custom_minimum_size = Vector2(160.0, 48.0)
	buttons.add_child(_start_button)
	buttons.add_child(_button("Back", _on_back_pressed))
	column.add_child(buttons)
	return column


func _build_slot_row(index: int) -> Control:
	var row := HBoxContainer.new()
	row.add_child(_label("Player %d" % (index + 1)))

	var colour := Button.new()
	colour.custom_minimum_size = Vector2(96.0, 0.0)
	colour.pressed.connect(_on_colour_pressed.bind(index))
	row.add_child(colour)

	var role := OptionButton.new()
	role.add_item("Human", int(Role.HUMAN))
	role.add_item("PlayTest AI", int(Role.PLAYTEST_AI))
	role.add_item("Open (waiting)", int(Role.OPEN))
	# OPEN needs a listening host and a peer to fill it (12.1), neither of which exists
	# yet. Offered and disabled, for the same reason the inert victory modes are.
	role.set_item_disabled(2, true)
	role.select(int(_roles[index]))
	role.item_selected.connect(_on_role_selected.bind(index))
	row.add_child(role)

	_slot_rows.append({"role": role, "colour": colour})
	_refresh_colour_button(index)
	return row


func _button(text: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(on_pressed)
	return b


# ── state ───────────────────────────────────────────────────────────────────

## Generate from the current settings and refresh the preview and the Start button.
##
## Public because it is the whole behaviour of the screen and a test wants to drive it
## without pressing anything.
func regenerate() -> void:
	_data = MapGenerator.generate(_seed, _type, _players)
	_preview.show_map(_data)

	var problems: Array = _data.meta.get("problems", [])
	if problems.is_empty():
		_status.text = "%s, %d x %d — ready" % [
				MapGenerator.type_name(_data.meta.get("type", _type) as MapGenerator.Type),
				_data.size.x, _data.size.y]
		_status.add_theme_color_override("font_color", HudStyle.GOLD)
	else:
		# A MAP THAT FAILS VALIDATION CANNOT BE STARTED (2.4b's gate). Saying why beats
		# a greyed button with no explanation -- and every one of these reads as a
		# sentence because MapValidator writes them for a person.
		_status.text = "Unplayable map: %s" % String(problems[0])
		_status.add_theme_color_override("font_color", HealthDot.CRITICAL_COLOR)
	if _start_button != null:
		_start_button.disabled = not problems.is_empty()


## The config this screen would start. Exactly a `MatchConfig`, with no translation.
func build_config() -> MatchConfig:
	var cfg := MatchConfig.new()
	cfg.player_ids = []
	cfg.colours = []
	cfg.ai_players = []
	for i in range(_players):
		cfg.player_ids.append(i + 1)
		cfg.colours.append(_colours[i])
		cfg.ai_players.append(_roles[i] == Role.PLAYTEST_AI)
	cfg.seed = _seed
	cfg.map_type = _type
	cfg.map_data = _data
	cfg.map_size = _data.size if _data != null else MatchConfig.DEBUG_MAP_SIZE
	cfg.mode = _mode
	return cfg


func map_data() -> MapData:
	return _data


func can_start() -> bool:
	return _data != null and (_data.meta.get("problems", []) as Array).is_empty()


func status_text() -> String:
	return _status.text


# ── handlers ────────────────────────────────────────────────────────────────

func _on_type_selected(index: int) -> void:
	_type = _type_picker.get_item_id(index) as MapGenerator.Type
	regenerate()


func _on_seed_changed(value: float) -> void:
	_seed = int(value)
	regenerate()


## A new seed AND a regenerate, so the button is one press rather than "type a number,
## then press the other button".
##
## `randi()` is fine here: this is the view choosing what to ask for, not the sim
## deciding anything -- and whatever it picks is then visible in the box, which is the
## point of showing the seed at all.
func _on_reroll_pressed() -> void:
	_seed = randi() % (_SEED_MAX + 1)
	_seed_box.set_value_no_signal(_seed)
	regenerate()


## Colour is a cycle rather than a palette popup: one button per slot, and the only
## rule is that two players cannot share a colour -- so a press steps to the next one
## nobody else has taken. With colour the ONLY thing telling players apart (§1), a
## duplicate is not a cosmetic mistake, it is an unplayable match.
func _on_colour_pressed(index: int) -> void:
	var count := _palette_size()
	for step in range(1, count + 1):
		var candidate := (_colours[index] + step) % count
		if not _colours.slice(0, _players).has(candidate):
			_colours[index] = candidate
			_refresh_colour_button(index)
			return


func _on_role_selected(item: int, index: int) -> void:
	_roles[index] = (_slot_rows[index]["role"] as OptionButton).get_item_id(item) as Role


func _on_start_pressed() -> void:
	if not can_start():
		return
	var cfg := build_config()
	start_requested.emit(cfg)
	# Carried on `Net` rather than through the signal, because the config has to survive
	# a scene change: `GameScene._ready()` is what starts the session, and it runs after
	# this node is gone.
	Net.pending_match = cfg
	get_tree().change_scene_to_file(_GAME_SCENE)


func _on_back_pressed() -> void:
	back_requested.emit()
	get_tree().change_scene_to_file(_MAIN_MENU_SCENE)


## How many colours the palette has. Asked of the data rather than restated here: the
## palette IS `colours.json` (§9), its order is a contract pinned by tests, and a second
## copy of it in the UI is a copy that drifts.
func _palette_size() -> int:
	if GameDataRegistry == null:
		return 8
	return maxi(1, GameDataRegistry.colour_count())


func _refresh_colour_button(index: int) -> void:
	var button: Button = _slot_rows[index]["colour"]
	var palette_index: int = _colours[index]
	if GameDataRegistry != null:
		button.text = String(GameDataRegistry.colour_slug(palette_index)) \
				.trim_prefix("colour.").capitalize()
		# The label is drawn IN the colour, which is the swatch -- there is no separate
		# colour chip to keep in step with the name.
		button.add_theme_color_override("font_color", GameDataRegistry.colour(palette_index))
	else:
		button.text = "Colour %d" % (palette_index + 1)
