## The skirmish settings screen (PLAN.md 1.6), **and the multiplayer lobby**.
##
## The two differ only in what fills a player slot, so this is one screen with one
## dropdown per slot: Human (this device) / PlayTest AI / Open (waiting for a peer).
## All-local is a skirmish; an Open slot plus a listening host is a multiplayer match.
## That is the whole reason there is no second screen: the flow tested solo tonight is
## the flow that runs on two devices, rather than a parallel path that first executes
## on the day it matters.
##
## THE LOBBY HALF (12.1c). Setting a slot to Open IS opening the socket -- there is no
## separate host button to forget, and no way to advertise a slot nobody can dial. START
## then waits until every advertised slot has somebody in it, which is the difference
## between this and the throwaway (g) screen it replaces: that one launched the match the
## instant anybody connected, because it had no slots to speak of. The joining device runs
## this same screen in `Lobby.JOINED`, where it configures nothing and waits, because the
## host's settings are the match's settings.
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

## What fills a player slot. `OPEN` is the multiplayer half: the slot is advertised and a
## joining peer takes it (12.1c).
##
## `CLOSED` is a slot with NOBODY in it, and it is what makes the player count and the map
## size two different things: eight slots with six closed is a two-player match on a map
## with eight players' worth of room. Its space on the map is still reserved -- the board
## is sized for every slot -- it simply holds no player, no base and no bot.
## The four AI roles past `PLAYTEST_AI` are APPENDED rather than slotted in beside it,
## which keeps HUMAN/PLAYTEST_AI/OPEN/CLOSED on the integers they have always had. The
## order the player SEES is the order `_add_role_items` lists them in and owes nothing
## to these numbers.
##
## `PLAYTEST_AI` keeps its name and is labelled **AI (Easy)** on screen (project owner,
## 2026-08-22). The name is what it IS -- the PlayTest AI of 12.2a, unchanged -- and the
## label is what it means to somebody choosing an opponent. Renaming the member would
## have churned a dozen tests to say the same thing.
enum Role { HUMAN, PLAYTEST_AI, OPEN, CLOSED, AI_PASSIVE, AI_NORMAL, AI_HARD, AI_UNFAIR }

## Role -> `SimPlayer.AILevel`, for the roles that are bots. Anything absent is not a
## bot, which is what `_is_ai_role` reads it for -- one table rather than a predicate
## and a mapping that could disagree about which roles are AI.
const AI_ROLE_LEVELS := {
	Role.AI_PASSIVE: SimPlayer.AILevel.PASSIVE,
	Role.PLAYTEST_AI: SimPlayer.AILevel.EASY,
	Role.AI_NORMAL: SimPlayer.AILevel.NORMAL,
	Role.AI_HARD: SimPlayer.AILevel.HARD,
	Role.AI_UNFAIR: SimPlayer.AILevel.UNFAIR,
}


static func _is_ai_role(role: Role) -> bool:
	return AI_ROLE_LEVELS.has(role)


## The inverse of `AI_ROLE_LEVELS`, for a joined client turning a host's config back
## into rows. Derived from the same table rather than written out again, so the two
## directions cannot disagree; an unknown level lands on Easy, which is also what
## `SimWorld.setup` falls back to.
static func _role_for_level(level: int) -> Role:
	for role in AI_ROLE_LEVELS:
		if int(AI_ROLE_LEVELS[role]) == level:
			return role
	return Role.PLAYTEST_AI

## Which side of a network match this screen is on, which is the third thing it is.
##
## `LOCAL` is a skirmish: nothing is listening and START plays at once. `HOSTING` is the
## same screen with a slot advertised and a socket open. `JOINED` is the screen on the
## OTHER device -- and it configures nothing, because the host's settings are the
## match's settings, so every control is disabled and it waits to be told to start.
enum Lobby { LOCAL, HOSTING, JOINED }

## Emitted with the assembled config. `GameScene` is reached through `Net.pending_match`
## rather than through this signal -- the signal is for tests and for whatever screen
## eventually wraps this one.
signal start_requested(cfg: MatchConfig)
signal back_requested()

const _GAME_SCENE := "res://scenes/game/Game.tscn"
const _MAIN_MENU_SCENE := "res://scenes/menu/MainMenu.tscn"
const _PREVIEW_SIZE := Vector2(320.0, 320.0)
const _SEED_MAX := 999999

## Slot counts offered, which is the whole 2-8 the generator supports. Was pinned at 2
## while nothing else was tested; the generator has validated every type at every count
## since 2.4b, and CLOSED means a big board no longer forces a big match.
const _MAX_OFFERED_PLAYERS := MapGenerator.MAX_PLAYERS

## A match needs two sides. Fewer active slots than this is a lobby, not a game -- and
## `MapValidator` says the same thing from the other end ("a match needs at least 2
## starts"), so without this the generator would silently clamp up to 2 and hand back a
## map with a start nobody is standing on.
const _MIN_PLAYERS := MapGenerator.MIN_PLAYERS

## HOW MANY SLOTS, WHICH IS HOW BIG THE MAP IS -- not how many people are playing.
##
## The two used to be one number, and separating them is the whole of this feature: eight
## slots with six CLOSED is a request for eight players' worth of room with two people in
## it. `_active_slots()` is the other number, and every place that used to say `_players`
## now has to say which one it meant.
var _slots: int = 2

var _seed: int = 1
var _type: MapGenerator.Type = MapGenerator.Type.RANDOM
var _mode: MatchConfig.Mode = MatchConfig.Mode.LAST_MAN_STANDING

## Sized for the maximum, so raising the slot count never has to grow them mid-change.
## Slots past `_slots` are simply not looked at.
var _roles: Array[Role] = []
var _colours: Array[int] = []

var _data: MapData = null

var _lobby: Lobby = Lobby.LOCAL

## Host only, from `--autostart`: press START as soon as the lobby is full and everyone
## has agreed. See `_apply_cmdline`.
var _autostart := false

## Joiner only, from `--autoready`: press READY as soon as the host's proposal arrives.
var _autoready := false

## The port advertising a slot binds. `Net.PORT` in the game, always.
##
## Settable because opening a slot binds a REAL socket -- that is the behaviour, and a
## faked one would test the fake -- and a fixed port makes the suite fight anything else
## on the machine holding it. Found the honest way: ten lobby tests went red while the
## owner had this very screen open with a slot advertised, because the game had 27015 and
## the tests could not have it. The suite now hosts somewhere nobody else would.
var host_port: int = Net.PORT

## Slot index -> the peer id standing in it. Only ever holds OPEN slots.
##
## Kept here rather than asked of `Net.peer_players()` on demand because that map is
## keyed the other way and knows nothing about SLOTS -- it maps a peer to the player id
## the server handed out, and which slot on this screen that fills is this screen's
## business.
var _slot_peers: Dictionary = {}

var _preview: MapPreview
var _status: Label
var _seed_box: SpinBox
var _type_picker: OptionButton
var _start_button: Button
var _slot_rows: Array[Dictionary] = []      # {role: OptionButton, colour: Button}
var _join_field: TouchLineEdit
var _join_button: Button
var _lobby_status: Label
var _reroll_button: Button
var _count_picker: OptionButton
var _mode_picker: OptionButton
var _ready_button: Button
var _slot_box: VBoxContainer

## The palette grid a colour button opens. ONE instance for the whole screen rather
## than one per slot row: the rows are torn down and rebuilt whenever the slot count
## changes, and a picker owned by a row would be freed underneath the finger that
## opened it. `_picking_slot` is which row it was opened for.
var _colour_picker: ColourPickerPopup
var _picking_slot: int = -1

## This device's own answer, on a joined client. Reset to false whenever a new proposal
## arrives, because agreeing to one match is not agreeing to the next one.
var _am_ready := false


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

	# Before any row is built, since a row reads the role and colour it is showing.
	_seed_slot_defaults()

	page.add_child(_heading("SKIRMISH"))
	page.add_child(_build_join_row())

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(columns)
	columns.add_child(_build_map_column())
	columns.add_child(_build_match_column())

	# LAST CHILD, so it draws over the page it covers. Added to the screen rather
	# than to a slot row for the reason `_colour_picker`'s own note gives.
	_colour_picker = ColourPickerPopup.new()
	_colour_picker.colour_chosen.connect(_on_colour_chosen)
	_colour_picker.cancelled.connect(func() -> void: _picking_slot = -1)
	add_child(_colour_picker)

	regenerate()

	Net.peer_joined.connect(_on_peer_joined)
	Net.peer_left.connect(_on_peer_left)
	Net.match_configured.connect(_on_match_configured)
	Net.lobby_config_received.connect(_on_lobby_config_received)
	Net.lobby_ready_changed.connect(_on_lobby_ready_changed)
	Net.lobby_colour_requested.connect(_on_lobby_colour_requested)
	Net.session_ended.connect(_on_session_ended)
	_refresh_lobby()
	_apply_cmdline()


# ── layout ──────────────────────────────────────────────────────────────────

## Joining someone else's match: an address and a button, and nothing more.
##
## AT THE TOP OF THE PAGE ON PURPOSE. A landscape Android keyboard covers roughly the
## bottom two thirds of the screen, so a field any lower is one you type into blind --
## measured on the device once there WAS a keyboard to measure (BUGS.md). The top third
## is the part that stays visible.
##
## A `TouchLineEdit`, not a `LineEdit`: this project turns off mouse emulation from
## touch, so a plain field never takes focus from a finger and never raises a keyboard
## at all. That is the bug that blocked this whole screen.
func _build_join_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(_label("Join"))

	_join_field = TouchLineEdit.new()
	_join_field.placeholder_text = "host address, e.g. 192.168.0.12"
	_join_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_join_field)

	_join_button = _button("JOIN", _on_join_pressed)
	row.add_child(_join_button)

	_lobby_status = Label.new()
	_lobby_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	column.add_child(row)
	column.add_child(_lobby_status)
	return column

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
	_reroll_button = _button("Re-generate", _on_reroll_pressed)
	seed_row.add_child(_reroll_button)
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
	_count_picker = OptionButton.new()
	for n in range(MapGenerator.MIN_PLAYERS, MapGenerator.MAX_PLAYERS + 1):
		_count_picker.add_item(str(n), n)
		if n > _MAX_OFFERED_PLAYERS:
			_count_picker.set_item_disabled(_count_picker.item_count - 1, true)
	_count_picker.select(0)
	_count_picker.disabled = _MAX_OFFERED_PLAYERS <= MapGenerator.MIN_PLAYERS
	_count_picker.item_selected.connect(_on_count_selected)
	count_row.add_child(_count_picker)
	column.add_child(count_row)

	# The rows live in their own box so changing the slot count can rebuild just them,
	# without disturbing the count picker above or the victory row below.
	_slot_box = VBoxContainer.new()
	_slot_box.add_theme_constant_override("separation", 8)
	column.add_child(_slot_box)
	_rebuild_slot_rows()

	var mode_row := HBoxContainer.new()
	mode_row.add_child(_label("Victory"))
	_mode_picker = OptionButton.new()
	# Trophy and King of the Hill are DECLARED and inert (11.2), so they are listed and
	# disabled -- a mode that silently decided nothing would be worse than one greyed.
	for mode in [MatchConfig.Mode.LAST_MAN_STANDING, MatchConfig.Mode.TROPHY,
			MatchConfig.Mode.KING_OF_THE_HILL]:
		_mode_picker.add_item(MatchConfig.mode_name(mode), int(mode))
		if mode != MatchConfig.Mode.LAST_MAN_STANDING:
			_mode_picker.set_item_disabled(_mode_picker.item_count - 1, true)
	_mode_picker.select(0)
	mode_row.add_child(_mode_picker)
	column.add_child(mode_row)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	_start_button = _button("START", _on_start_pressed)
	_start_button.custom_minimum_size = Vector2(160.0, 48.0)
	buttons.add_child(_start_button)

	# The joining player's say. Only visible to them -- a host readies by pressing START,
	# and two buttons meaning the same thing on one screen would be one too many.
	_ready_button = _button("READY", _on_ready_pressed)
	_ready_button.custom_minimum_size = Vector2(160.0, 48.0)
	_ready_button.visible = false
	buttons.add_child(_ready_button)

	buttons.add_child(_button("Back", _on_back_pressed))
	column.add_child(buttons)
	return column


## Default roles and colours for as many slots as could ever be shown.
##
## Slot 1 is the human at this device, slot 2 the PlayTest AI -- the owner's default, and
## the one press-to-play skirmish 1.6 exists to protect. Everything past that starts
## CLOSED: raising the count to eight should widen the BOARD, not silently conjure six
## opponents nobody asked for.
func _seed_slot_defaults() -> void:
	_roles.clear()
	_colours.clear()
	for i in range(_MAX_OFFERED_PLAYERS):
		_roles.append(Role.HUMAN if i == 0 else (
				Role.PLAYTEST_AI if i == 1 else Role.CLOSED))
	# Yellow against red first, the owner's default; the rest take whatever is left, since
	# two players sharing a colour is an unplayable match (§1) at any count.
	var preferred := [2, 1]
	for i in range(_MAX_OFFERED_PLAYERS):
		if i < preferred.size():
			_colours.append(int(preferred[i]))
			continue
		for candidate in range(_palette_size()):
			if not _colours.has(candidate):
				_colours.append(candidate)
				break
	while _colours.size() < _MAX_OFFERED_PLAYERS:
		_colours.append(0)          # a palette smaller than the slot count; last resort


## Tear the rows down and build exactly `_slots` of them.
##
## Rebuilt rather than shown and hidden: a hidden row still holds a role that
## `build_config()` would read, and the bug that would produce -- a player in the match
## who is not on the screen -- is the worst kind available here.
func _rebuild_slot_rows() -> void:
	for child in _slot_box.get_children():
		_slot_box.remove_child(child)
		child.queue_free()
	_slot_rows.clear()
	for i in range(_slots):
		_slot_box.add_child(_build_slot_row(i))


func _build_slot_row(index: int) -> Control:
	var row := HBoxContainer.new()
	var name_label := _label("Player %d" % (index + 1))
	row.add_child(name_label)

	var colour := Button.new()
	colour.custom_minimum_size = Vector2(96.0, 0.0)
	colour.pressed.connect(_on_colour_pressed.bind(index))
	row.add_child(colour)

	var role := OptionButton.new()
	role.add_item("Human", int(Role.HUMAN))
	# THE AI LADDER, easiest first, with the placeholders SAYING SO on screen. Listing
	# them before they work is deliberate (project owner, 2026-08-22): it shows the
	# shape of the choice, and it means the list does not renumber under a player's
	# muscle memory when 12.2b fills them in. All three placeholders play as Easy.
	role.add_item("AI (Passive)", int(Role.AI_PASSIVE))
	role.add_item("AI (Easy)", int(Role.PLAYTEST_AI))
	role.add_item("AI (Normal) — as Easy", int(Role.AI_NORMAL))
	role.add_item("AI (Hard) — as Easy", int(Role.AI_HARD))
	role.add_item("AI (Unfair) — as Easy", int(Role.AI_UNFAIR))
	# "Open", not "Open (waiting)". A dropdown lists the CHOICES; whether the chair is
	# still empty is status, and the lobby line below already says. The longer label read
	# as a contradiction the moment somebody was sitting in it -- a slot showing "Open
	# (waiting)" directly above "Player 2: peer 7777 joined".
	role.add_item("Open", int(Role.OPEN))
	role.add_item("Closed", int(Role.CLOSED))
	role.select(role.get_item_index(int(_roles[index])))
	role.item_selected.connect(_on_role_selected.bind(index))
	row.add_child(role)

	# WHO IS ACTUALLY IN THIS CHAIR, on the row for that chair.
	#
	# Occupancy used to live in a separate block of text below, listing only the Open
	# slots -- so the host had a list of what it was waiting for rather than a list of
	# players, and the two could disagree with the rows above them. On the row is the one
	# place it cannot: there is exactly one player list now and both devices render it
	# from the same fields.
	var status := Label.new()
	status.custom_minimum_size = Vector2(220.0, 0.0)
	status.add_theme_color_override("font_color", HudStyle.GOLD)
	row.add_child(status)

	_slot_rows.append({"role": role, "colour": colour, "name": name_label, "status": status})
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
	# TWO COUNTS. The map is SIZED for every slot and POPULATED for the players actually
	# in them, which is what makes "eight players, six closed" a big empty board for two
	# rather than two starts crammed into one corner of it.
	_data = MapGenerator.generate(_seed, _type, _active_slots().size(), _slots)
	_preview.show_map(_data)

	var problems: Array = _data.meta.get("problems", [])
	var active := _active_slots().size()
	if active < _MIN_PLAYERS:
		# Said rather than shown as a dead button. Closing one slot too many is easy to do
		# and impossible to diagnose from a greyed START.
		_status.text = "%d player — close fewer slots, a match needs %d" % [active, _MIN_PLAYERS]
		_status.add_theme_color_override("font_color", HealthDot.CRITICAL_COLOR)
	elif problems.is_empty():
		# The player count AND the size, because they are now different numbers and the
		# whole point of closing a slot is the gap between them.
		_status.text = "%s, %d x %d — %d players on room for %d — ready" % [
				MapGenerator.type_name(_data.meta.get("type", _type) as MapGenerator.Type),
				_data.size.x, _data.size.y, active, _slots]
		_status.add_theme_color_override("font_color", HudStyle.GOLD)
	else:
		# A MAP THAT FAILS VALIDATION CANNOT BE STARTED (2.4b's gate). Saying why beats
		# a greyed button with no explanation -- and every one of these reads as a
		# sentence because MapValidator writes them for a person.
		_status.text = "Unplayable map: %s" % String(problems[0])
		_status.add_theme_color_override("font_color", HealthDot.CRITICAL_COLOR)
	_refresh_start_button()
	_publish_lobby()


## Tell the people waiting what they are waiting for, whenever it changes.
##
## Called from every path that alters the match: a regenerated map, a colour, a role. A
## host who quietly changed the map under a player who had already agreed to it would be
## the exact failure the lobby channel exists to prevent -- so `broadcast_lobby_config`
## also cancels every agreement, and everyone has to say yes to the new thing.
func _publish_lobby() -> void:
	if _lobby == Lobby.HOSTING:
		Net.broadcast_lobby_config(build_config())


## The config this screen would start. Exactly a `MatchConfig`, with no translation.
func build_config() -> MatchConfig:
	var cfg := MatchConfig.new()
	cfg.player_ids = []
	cfg.colours = []
	cfg.ai_players = []
	# ONLY THE SLOTS SOMEBODY IS IN, numbered 1..N over those.
	#
	# Compacted rather than keeping the slot number as the player id, because `Net` hands
	# out the lowest free id to a joining peer and `MapGen.build_from` resolves a map's
	# player index by POSITION in `world.players` -- so a match whose ids skipped 3 and 4
	# would hand somebody else's base to the wrong player. Compaction keeps every one of
	# those assumptions true, and the closed slots have already done their job by the time
	# this runs: they set the size of the board.
	for i in _active_slots():
		cfg.player_ids.append(cfg.player_ids.size() + 1)
		cfg.colours.append(_colours[i])
		cfg.ai_players.append(_is_ai_role(_roles[i]))
		# Position for position with `ai_players`. Humans get a level too and it is
		# never read -- a hole here would misalign every bot after it.
		cfg.ai_levels.append(int(AI_ROLE_LEVELS.get(_roles[i], SimPlayer.AILevel.EASY)))
	cfg.seed = _seed
	cfg.map_type = _type
	cfg.map_data = _data
	cfg.map_size = _data.size if _data != null else MatchConfig.DEBUG_MAP_SIZE
	cfg.mode = _mode
	return cfg


func map_data() -> MapData:
	return _data


## Whether START would do anything. THREE rules now, and they all live here so the button
## and the handler can never disagree about it:
##
##   1. A validated map (2.4b's gate) -- an unplayable one is never launched.
##   2. Every advertised slot filled. Starting with an empty OPEN slot would launch a
##      match one player short of the one the host set up.
##   3. Not a joined client. Over there START belongs to the host, and the local button
##      would be a second, competing authority over when the match begins.
##   4. **Two players at least.** Closing slots is what makes this reachable: eight
##      slots with seven closed is one player and no match. Refused here rather than
##      left to the generator, which clamps a count of 1 up to 2 and would hand back a
##      map with a start nobody is standing on.
##   5. **Everybody has agreed.** A host who can start over a player who has not said
##      READY is a host who can drop somebody into a match they never got to look at,
##      which is the whole reason the lobby channel exists. Agreement is also cancelled
##      whenever a setting changes, so this cannot be satisfied by a stale yes.
func can_start() -> bool:
	if _data == null or not (_data.meta.get("problems", []) as Array).is_empty():
		return false
	if _lobby == Lobby.JOINED:
		return false
	if _active_slots().size() < _MIN_PLAYERS:
		return false
	if unfilled_slots() != 0:
		return false
	return Net.all_peers_ready()


func _refresh_start_button() -> void:
	if _start_button == null:
		return
	_start_button.disabled = not can_start()
	# The button says what it is FOR, because on this screen the same press means two
	# different things and the difference matters: one plays at once, the other commits
	# the people already waiting on it.
	_start_button.text = "START MATCH" if _lobby == Lobby.HOSTING else "START"


func status_text() -> String:
	return _status.text


func lobby_state() -> Lobby:
	return _lobby


func lobby_text() -> String:
	return _lobby_status.text


# ── handlers ────────────────────────────────────────────────────────────────

## More or fewer SLOTS, which is a bigger or smaller map. Rebuilds the rows and
## regenerates, because the board size follows this number directly.
func _on_count_selected(item: int) -> void:
	_slots = _count_picker.get_item_id(item)
	_rebuild_slot_rows()
	regenerate()
	_refresh_lobby()


## Slots with somebody or something in them: the actual players. CLOSED slots reserve
## their room on the board and hold nobody, which is the whole point of them.
func _active_slots() -> Array[int]:
	var out: Array[int] = []
	for i in range(_slots):
		if _roles[i] != Role.CLOSED:
			out.append(i)
	return out


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


## A COLOUR BUTTON OPENS THE PALETTE, showing only what is free.
##
## This used to be a cycle: a press stepped the slot to the next colour nobody else held.
## Cheap, and it made picking violet out of eight a matter of pressing five times and
## watching -- worse on a joined client, where every press was a round trip to the host, so
## the player was cycling blind through a list they could never see. The rule has not
## changed, only where it is expressed: taken colours are not on the grid at all rather
## than being skipped by the step. With colour the ONLY thing telling players apart (§1),
## a duplicate is not a cosmetic mistake, it is an unplayable match.
##
## YOUR COLOUR IS YOURS, on either device -- a joined client used to have every colour
## button disabled, so the one thing that tells players apart was assigned to them. What
## a joined client does NOT get is the authority: `_on_colour_chosen` asks rather than
## sets, because the no-duplicates rule belongs to whoever can see every slot.
func _on_colour_pressed(index: int) -> void:
	if _lobby == Lobby.JOINED and index != _local_slot():
		return                    # somebody else's identity, not yours to change
	_picking_slot = index
	_colour_picker.open_for("Player %d" % (index + 1), _colours[index],
			_taken_colours(index))


## What everybody ELSE holds, which is what the picker must not offer.
##
## ACTIVE slots only, never every slot. A closed slot holds no player, so its colour is
## nobody's -- counting it would leave two players on an eight-slot board with six colours
## spoken for by empty chairs and almost nothing left to choose from. That distinction was
## a real bug in the cycle it replaced and it is the same distinction here.
func _taken_colours(exclude_index: int) -> Array[int]:
	var taken: Array[int] = []
	for i in _active_slots():
		if i != exclude_index:
			taken.append(_colours[i])
	return taken


## A swatch was pressed. On the host this is the decision; on a joined client it is a
## request, and the host's re-broadcast is what actually moves the colour on this screen.
func _on_colour_chosen(colour_index: int) -> void:
	var slot := _picking_slot
	_picking_slot = -1
	if slot < 0 or slot >= _colours.size():
		return

	if _lobby == Lobby.JOINED:
		Net.request_colour(colour_index)
		return
	_set_colour(slot, colour_index)
	_publish_lobby()


## Give a slot a colour, refusing a collision. The host's rule, applied whether the host
## pressed the swatch or a joined player asked for it -- one function, because two copies
## of "is this colour free" is how the two come to disagree.
##
## Returns false and changes NOTHING on a collision rather than substituting some other
## colour: a client's idea of what was free can be a moment stale, and the re-broadcast
## that follows every lobby change is what corrects it. Silently handing them a different
## colour than the one they pressed would be worse than leaving them where they were.
func _set_colour(index: int, colour_index: int) -> bool:
	if index < 0 or index >= _colours.size():
		return false
	if colour_index < 0 or colour_index >= _palette_size():
		return false
	if _taken_colours(index).has(colour_index):
		return false
	_colours[index] = colour_index
	_refresh_colour_button(index)
	return true


## A joined player asked for a colour. Their slot is found from the PEER, so a client
## cannot ask on somebody else's behalf even if it wanted to.
##
## The re-broadcast cancels every agreement, including the asker's own -- consistent with
## every other change, and cheap: the player who just pressed the swatch is right there to
## press READY again. Skipped entirely when the request was refused, since nothing changed
## and cancelling everybody's consent over a no-op would be a hostile way to say no.
func _on_lobby_colour_requested(peer_id: int, colour_index: int) -> void:
	for slot in _slot_peers:
		if int(_slot_peers[slot]) != peer_id:
			continue
		if _set_colour(int(slot), colour_index):
			_publish_lobby()
			_refresh_lobby()
		return


## Changing a slot's role is what opens and closes the socket, because the OPEN role and
## a listening host are the same fact stated twice. There is no separate "host" button to
## forget to press, and no way to advertise a slot nobody can reach.
func _on_role_selected(item: int, index: int) -> void:
	var was_active := _active_slots().size()
	_roles[index] = (_slot_rows[index]["role"] as OptionButton).get_item_id(item) as Role

	# CLOSING OR REOPENING A SLOT CHANGES THE MAP, because the number of players is the
	# number of starts placed on it. Only when the ACTIVE count actually moved: swapping a
	# human for a bot is the same match on the same board, and regenerating there would
	# throw away the map somebody just picked over a change that did not touch it.
	#
	# Reopening returns you to the map you had, since the seed and both counts are back
	# where they were and generation is deterministic.
	if _active_slots().size() != was_active:
		regenerate()

	if _wants_peers() and _lobby == Lobby.LOCAL:
		var err := Net.host_open(host_port)
		if err != OK:
			# Put the slot back rather than leaving a screen that says it is waiting for
			# someone who can never arrive. This is how the missing Android INTERNET
			# permission presented at 0.7: nothing crashed, nothing said why.
			_roles[index] = Role.HUMAN
			(_slot_rows[index]["role"] as OptionButton).select(int(Role.HUMAN))
			_say("could not open a socket: %s" % error_string(err))
			return
		_lobby = Lobby.HOSTING
		# Logged on the TRANSITION, not from `_refresh_lobby_text`, which runs on every
		# refresh and would repeat itself. A terminal-driven host has nobody watching the
		# label, and "am I actually listening, and on what" is the first question a
		# bring-up asks.
		print("lobby: listening on port %d as player %d — dial %s"
				% [host_port, Net.local_player_id(), ", ".join(_own_addresses())])
	elif not _wants_peers() and _lobby == Lobby.HOSTING:
		# The last advertised slot just closed, so stop listening. Reachable only while
		# no peer has arrived -- a slot with somebody in it has its dropdown disabled.
		Net.leave()
		_lobby = Lobby.LOCAL
		_slot_peers.clear()
		# The host closed the slot itself, so `session_ended`'s "left" is not news.
		_say("")

	_publish_lobby()
	_refresh_lobby()


## Whether any slot is waiting for a person on another device.
func _wants_peers() -> bool:
	for i in range(_slots):
		if _roles[i] == Role.OPEN:
			return true
	return false


## Advertised slots that nobody is standing in yet. START waits on this reaching zero:
## starting with an empty OPEN slot would launch a match one player short of the one the
## host set up.
func unfilled_slots() -> int:
	var count := 0
	for i in range(_slots):
		if _roles[i] == Role.OPEN and not _slot_peers.has(i):
			count += 1
	return count


# ── lobby ───────────────────────────────────────────────────────────────────

func _on_join_pressed() -> void:
	var ip := _join_field.text.strip_edges()
	if ip.is_empty():
		_say("type the host's address first")
		return
	if _lobby != Lobby.LOCAL:
		_say("already in a session -- go Back to leave it")
		return

	var err := Net.join(ip, Net.PORT)
	if err != OK:
		_say("join failed: %s" % error_string(err))
		return
	_lobby = Lobby.JOINED
	_say("dialling %s:%d..." % [ip, Net.PORT])
	_refresh_lobby()


## A peer arrived. It takes a slot and is SHOWN taking it -- the host presses START, which
## is the whole difference between this screen and the throwaway (g) one that started the
## match the instant anybody connected.
func _on_peer_joined(peer_id: int) -> void:
	var pid: int = int(Net.peer_players().get(peer_id, 0))
	var slot := _slot_for(pid)
	if slot < 0:
		# Nowhere to put them. Only reachable if a peer beats a role change, and saying so
		# beats a screen that quietly ignores somebody who did connect.
		_say("a peer connected with no open slot to take")
		return
	_slot_peers[slot] = peer_id
	# Said BEFORE the refresh, not after: the refresh rebuilds the standing summary --
	# which lists this peer by name anyway -- and a `_say` afterwards would replace that
	# whole peer list with one line about one arrival. The log still gets both.
	_say("player %d joined slot %d (peer %d)" % [pid, slot + 1, peer_id])
	# THE FIRST THING A NEW ARRIVAL IS OWED. Until this call existed, a joining player
	# learned nothing about the match until it had already started.
	Net.broadcast_lobby_config(build_config())
	_refresh_lobby()

	_maybe_autostart()


## `--autostart`, re-checked on every event that could satisfy it. Peer arrival is not
## enough on its own any more: the lobby also waits on agreement, so the moment that
## makes a start legal is usually somebody pressing READY, not somebody connecting.
func _maybe_autostart() -> void:
	if _autostart and can_start():
		_say("autostart: lobby full and everyone agreed, starting")
		_on_start_pressed()


func _on_peer_left(peer_id: int) -> void:
	for slot in _slot_peers.keys():
		if _slot_peers[slot] == peer_id:
			_slot_peers.erase(slot)
			break
	_refresh_lobby()


## Which slot a joining player belongs in.
##
## Prefers the slot matching their player id, since `Net` hands out 1..N in join order and
## `build_config()` numbers slots the same way -- so on the two-player match this screen
## offers, player 2 lands in slot 2 and the peer list reads the way the rows do. Falls
## back to the first free advertised slot rather than refusing, because a mismatch here
## is a cosmetic disagreement and dropping a connected player is not.
func _slot_for(player_id: int) -> int:
	var preferred := player_id - 1
	if preferred >= 0 and preferred < _slots \
			and _roles[preferred] == Role.OPEN and not _slot_peers.has(preferred):
		return preferred
	for i in range(_slots):
		if _roles[i] == Role.OPEN and not _slot_peers.has(i):
			return i
	return -1


## THE HOST'S MATCH, ARRIVING WHILE THERE IS STILL TIME TO LOOK AT IT.
##
## Adopted into this screen's own fields rather than rendered through a second read-only
## path, so the joined screen literally IS the host's screen with the controls off: one
## set of widgets, one preview, no chance of the two drifting into disagreement about what
## a config means. Safe precisely because everything is disabled here -- nothing this
## device does can write back into it.
##
## And it resets this device's READY, because a new proposal is a new question. The host
## side cancels every agreement at the same moment (`broadcast_lobby_config`), so the two
## sides agree that consent does not survive a change.
func _on_lobby_config_received() -> void:
	var cfg := Net.lobby_config()
	if cfg == null:
		return

	_seed = cfg.seed
	_type = cfg.map_type
	_mode = cfg.mode
	_data = cfg.map_data

	# THE SLOT COUNT FIRST, and rebuild the rows to match it, because a host on eight
	# slots and a client still showing two would leave six of the host's players with no
	# row to appear in -- the joining player would be reading a two-player lobby for an
	# eight-player match.
	#
	# The wire carries the PLAYERS, not the slots, and the difference between them is
	# whatever the host closed. That gap cannot be recovered from the config and does not
	# need to be: a closed slot has nobody in it, so there is nobody for it to misdescribe.
	# What the joiner shows is one row per actual player.
	var incoming := maxi(cfg.player_ids.size(), _MIN_PLAYERS)
	if incoming != _slots:
		_slots = mini(incoming, _MAX_OFFERED_PLAYERS)
		_count_picker.select(_count_picker.get_item_index(_slots))
		_rebuild_slot_rows()

	for i in range(mini(_colours.size(), cfg.colours.size())):
		_colours[i] = cfg.colours[i]
		_refresh_colour_button(i)

	# THE ROLES TOO, which the first version of this forgot -- so a joined client kept its
	# own local defaults and showed Player 2 as "PlayTest AI" while the host showed the
	# same chair as "Open". The joining player was reading that about their own seat.
	#
	# `ai_players` is what the wire carries, and it is enough: a bot is a bot, and every
	# other chair holds a person. It cannot tell the host's own seat from a remote one and
	# does not need to -- which chair is YOURS comes from `local_player_id()`, and the row
	# label says so.
	#
	# The LEVEL rides along, so a joiner sees "AI (Passive)" where the host set one
	# rather than a generic bot. `ai_levels` may be shorter or absent -- from a host
	# built before difficulty existed -- and each bot then falls back to Easy, which is
	# the AI that host is actually running.
	for i in range(mini(_slot_rows.size(), cfg.ai_players.size())):
		if cfg.ai_players[i]:
			var level: int = int(cfg.ai_levels[i]) if i < cfg.ai_levels.size() \
					else SimPlayer.AILevel.EASY
			_roles[i] = _role_for_level(level)
		else:
			_roles[i] = Role.HUMAN
		var picker: OptionButton = _slot_rows[i]["role"]
		picker.select(picker.get_item_index(int(_roles[i])))

	_seed_box.set_value_no_signal(_seed)
	_type_picker.select(_type_picker.get_item_index(int(_type)))
	_mode_picker.select(_mode_picker.get_item_index(int(_mode)))
	if _data != null:
		_preview.show_map(_data)

	_am_ready = false
	_say("player %d — review the match, then press READY" % Net.local_player_id())
	_refresh_lobby()

	if _autoready:
		# The scripted side of a two-machine test agreeing on cue. It presses the real
		# button's handler, so it agrees to a proposal it has actually received -- which
		# is the whole rule, just without a thumb.
		_on_ready_pressed()


func _on_ready_pressed() -> void:
	_am_ready = not _am_ready
	Net.set_lobby_ready(_am_ready)
	_say("ready: %s" % _am_ready)
	_refresh_lobby()


## Somebody's answer changed, on the host. START may have just become available, or may
## have just stopped being.
func _on_lobby_ready_changed(_peer_id: int, _ready: bool) -> void:
	_refresh_lobby()
	_maybe_autostart()


## The host has described the match, so this client can draw it. Only ever fires on a
## JOINED screen: a host had the config in its hand when it pressed START.
func _on_match_configured() -> void:
	_say("match received -- entering")
	if is_inside_tree():
		get_tree().change_scene_to_file(_GAME_SCENE)


func _on_session_ended(reason: String) -> void:
	_lobby = Lobby.LOCAL
	_slot_peers.clear()
	_say("session ended: %s" % reason)
	_refresh_lobby()


## Puts every control into the state the current lobby mode calls for, and says what the
## screen is waiting for. One function so the modes cannot drift apart: every path that
## changes anything ends here.
func _refresh_lobby() -> void:
	var joined := _lobby == Lobby.JOINED

	# A joined client configures NOTHING. The host's settings are the match's settings, so
	# a live control here would be a lie about who decides. Every one of these was found
	# by LOOKING at the joined screen rather than by reasoning about it: Re-generate, the
	# player count and the victory picker were all still live in the first version.
	_seed_box.editable = not joined
	_type_picker.disabled = joined
	_reroll_button.disabled = joined
	_mode_picker.disabled = joined
	_count_picker.disabled = joined or _MAX_OFFERED_PLAYERS <= MapGenerator.MIN_PLAYERS

	# THE PREVIEW SHOWS THE HOST'S MAP, ONCE THERE IS ONE. A joined client used to
	# generate its own random map on the way in and show THAT -- a picture of a map it
	# will never play, captioned "ready" -- so the preview was hidden. Now the host sends
	# its config to the lobby and the client adopts it, so there is a real map to show;
	# it stays hidden only in the gap before the first one arrives, which is the only
	# moment this device genuinely does not know.
	_preview.visible = not joined or Net.lobby_config() != null

	# The joining player's answer, and only theirs.
	_ready_button.visible = joined
	_ready_button.disabled = joined and Net.lobby_config() == null
	_ready_button.text = "NOT READY" if _am_ready else "READY"
	for i in range(_slot_rows.size()):
		var role_picker: OptionButton = _slot_rows[i]["role"]
		# A slot somebody is standing in cannot be un-opened. Simpler than deciding what
		# happens to a connected player when their chair is taken away.
		role_picker.disabled = joined or _slot_peers.has(i)
		# Your own colour stays live on a joined client. Everyone else's is theirs.
		(_slot_rows[i]["colour"] as Button).disabled = joined and i != _local_slot()

	if joined:
		var cfg := Net.lobby_config()
		if cfg == null:
			_status.text = "Waiting for the host's settings"
		else:
			# What the joining player is being asked to agree TO, in words, next to the
			# map they can now see. The host's screen has these as live controls; here
			# they are the terms of the invitation.
			#
			# The RESOLVED type, not the requested one -- the same thing `regenerate()`
			# shows the host. `map_type` records what was asked for, so a random pick
			# reads as "Random" while the map in front of you is plainly a desert; on the
			# host's own screen that reads as "Desert". Telling the two sides different
			# things about one map is the last thing a consent screen should do.
			var resolved := cfg.map_type
			if cfg.map_data != null:
				resolved = cfg.map_data.meta.get("type", cfg.map_type) as MapGenerator.Type
			_status.text = "%s, %d x %d — seed %d — %s" % [
					MapGenerator.type_name(resolved),
					cfg.map_size.x, cfg.map_size.y, cfg.seed,
					MatchConfig.mode_name(cfg.mode)]
		_status.add_theme_color_override("font_color", HudStyle.GOLD)

	_join_field.editable = _lobby == Lobby.LOCAL
	_join_button.disabled = _lobby != Lobby.LOCAL

	_refresh_start_button()
	_refresh_slot_rows()
	_refresh_lobby_text()


func _refresh_lobby_text() -> void:
	match _lobby:
		Lobby.HOSTING:
			# JUST THE TRANSPORT. Who is in which chair is on the chairs now, in
			# `_refresh_slot_rows` -- this line is only the thing the rows cannot say,
			# which is where to dial to reach them.
			_lobby_status.text = "Waiting on port %d — dial %s" \
					% [host_port, ", ".join(_own_addresses())]
		_:
			# LEFT ALONE ON PURPOSE, rather than cleared. `Net.leave()` emits
			# `session_ended` synchronously, so this runs immediately after -- and
			# clearing here would wipe the reason a session ended at exactly the moment
			# the reason matters most, turning a dropped host into a screen that says
			# nothing. Whoever wants the line blank says so with `_say("")`.
			pass


## Which slot is this device's own player.
##
## `local_player_id()` is 0 until a session hands one out, and a plain skirmish never
## does -- but the human at this keyboard is player 1 there, so 0 reads as slot 0 rather
## than as "nobody".
func _local_slot() -> int:
	var pid := Net.local_player_id()
	return (pid - 1) if pid > 0 else 0


## THE PLAYER LIST. Rendered from the same fields on both devices, which is the whole
## point: the host's screen said Player 2 was "Open" while the joiner's said the same
## chair was a "PlayTest AI", and the joining player was reading that about themselves.
func _refresh_slot_rows() -> void:
	for i in range(_slot_rows.size()):
		var name_label: Label = _slot_rows[i]["name"]
		var status: Label = _slot_rows[i]["status"]

		# "(you)" goes on the NAME, never on the role dropdown. Identity on the identity
		# label, role in the role picker -- the same separation that got "Open (waiting)"
		# shortened to "Open". Nothing said which player you were before this.
		var mine := i == _local_slot() and _roles[i] != Role.PLAYTEST_AI
		name_label.text = "Player %d (you)" % (i + 1) if mine else "Player %d" % (i + 1)
		status.text = _slot_status(i, mine)


## What to say about one chair. Deliberately one function rather than a host version and
## a client version: two renderers is how the two devices came to disagree.
func _slot_status(index: int, mine: bool) -> String:
	if _roles[index] == Role.CLOSED:
		# Says what a closed slot is FOR, since leaving it blank reads as an oversight:
		# the room is still on the board, there is just nobody in it.
		return "empty — room kept on the map"
	if _roles[index] == Role.PLAYTEST_AI:
		return "bot"

	if _lobby == Lobby.JOINED:
		# A client knows its own answer and that player 1 is whoever it dialled. It does
		# NOT know whether a third player has readied -- the host is the only side
		# counting agreement -- so it says nothing rather than guessing.
		if mine:
			return "READY" if _am_ready else "reviewing..."
		return "host" if index == 0 else ""

	if _roles[index] == Role.OPEN:
		if not _slot_peers.has(index):
			return "waiting for a player"
		# READY IS THE PART THAT MATTERS. "Joined" only says a socket connected, and
		# START is held on agreement, so the host has to see which of the two it is
		# still waiting for.
		return "READY" if Net.is_peer_ready(int(_slot_peers[index])) else "reviewing..."

	return "this device" if mine else ""


## Every address this device answers on, so the other one knows what to dial.
##
## Three things are filtered out, and the third was found by photographing this screen:
## loopback and IPv6 are not what you type into another phone, and **169.254.x.x is
## link-local** -- the address an interface gives itself when DHCP failed, which nothing
## on the network can route to. A dev laptop has one per idle adapter, and the first
## version of this line offered NINE addresses of which five were unreachable, wrapped
## onto two rows, and pushed the rest of the screen down. This line exists to be read off
## one screen and typed into another, so a wrong candidate on it costs a failed attempt.
func _own_addresses() -> Array[String]:
	var out: Array[String] = []
	for a in IP.get_local_addresses():
		var s := String(a)
		if s.begins_with("127.") or s.begins_with("169.254.") or s.contains(":"):
			continue
		out.append(s)
	if out.is_empty():
		out.append("no network address")
	return out


func _say(text: String) -> void:
	if _lobby_status != null:
		_lobby_status.text = text
	# On stdout as well, because a scripted side of a two-machine test has nobody
	# watching the label -- the log is the only way to follow a bring-up. Same reason
	# the throwaway (g) screen did it. Clearing the line is not news, so it is not logged.
	if not text.is_empty():
		print("lobby: %s" % text)


# ── driving it from a terminal ───────────────────────────────────────────────
#
# Two devices, and only one of them has somebody standing at a keyboard -- so the other
# side has to be startable from a command line. The throwaway (g) screen established
# this; it is kept because the need did not go away with it.
#
#   Godot --path game res://scenes/menu/Skirmish.tscn -- --net host --autostart
#   Godot --path game res://scenes/menu/Skirmish.tscn -- --net join --ip 1.2.3.4 --autoready
#
# `--autostart` is HOST ONLY and presses START the moment the lobby is full and everyone
# has agreed. `--autoready` is JOINER ONLY and presses READY when the host's proposal
# arrives. Both automate the press, not the rule -- each still waits for exactly what a
# thumb would wait for, which is why the ready gate cannot be skipped by scripting it.
func _apply_cmdline() -> void:
	_autostart = _has_flag("--autostart")
	_autoready = _has_flag("--autoready")
	match _string_arg("--net", ""):
		"host":
			# Deferred so the node is in the tree first: opening a slot can reach
			# `get_tree()` by way of a start, and a peer could in principle be waiting.
			call_deferred("_host_from_cmdline")
		"join":
			_join_field.text = _string_arg("--ip", "127.0.0.1")
			call_deferred("_on_join_pressed")


## Advertise the LAST slot, which is the one a second player would take: slot 1 is this
## device's own human seat in every default this screen ships with.
func _host_from_cmdline() -> void:
	var index := _slots - 1
	var picker: OptionButton = _slot_rows[index]["role"]
	var item := picker.get_item_index(int(Role.OPEN))
	picker.select(item)
	picker.item_selected.emit(item)


func _has_flag(name: String) -> bool:
	return OS.get_cmdline_user_args().has(name)


func _string_arg(name: String, fallback: String) -> String:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		if args[i] == name:
			return String(args[i + 1])
	return fallback


## TWO WAYS TO START, because there are two kinds of match and only one of them has a
## session already running.
##
## A skirmish leaves the config on `Net.pending_match` and lets `GameScene._ready()` call
## `host_solo()`, which consumes it. A HOSTED match must not go that way: the socket has
## been open since the slot was advertised, so `GameScene` sees `has_session()` and
## deliberately does not host over the top of it -- meaning nothing would ever consume
## `pending_match` and the client would never be told what it is playing. `start_match()`
## is the call that settles the config and broadcasts it, so the host makes it HERE,
## before the scene change, exactly as the proven (g) path did.
func _on_start_pressed() -> void:
	if not can_start():
		return
	var cfg := build_config()
	start_requested.emit(cfg)

	if _lobby == Lobby.HOSTING:
		# The clock stays held until every joiner reports ready (12.1d), so starting the
		# world a moment before this device's own view exists loses nothing.
		Net.start_match(cfg)
	else:
		Net.pending_match = cfg
	get_tree().change_scene_to_file(_GAME_SCENE)


## Leaves the session on the way out. Without this the socket outlives the screen that
## opened it: the main menu would be sitting on a listening host, and the next PLAY would
## find `has_session()` true and never start a match at all.
func _on_back_pressed() -> void:
	if _lobby != Lobby.LOCAL:
		Net.leave()
		_lobby = Lobby.LOCAL
		_slot_peers.clear()
	back_requested.emit()
	get_tree().change_scene_to_file(_MAIN_MENU_SCENE)


## How many colours the palette has. Asked of the data rather than restated here: the
## palette IS `colours.json` (§9), its order is a contract pinned by tests, and a second
## copy of it in the UI is a copy that drifts.
func _palette_size() -> int:
	if GameDataRegistry == null:
		return 8
	return maxi(1, GameDataRegistry.colour_count())


## The slot's colour button, drawn AS the colour rather than as its name written in it.
##
## It used to be the name in coloured text on the default button background. That was
## legible enough at eight distinct hues and stopped being the right thing the moment the
## picker existed: the grid this button opens is flat blocks of colour, so a button that
## previewed the choice differently from the way the choice is made is one more thing to
## compare. Now the row and the grid draw a swatch the same way.
func _refresh_colour_button(index: int) -> void:
	var button: Button = _slot_rows[index]["colour"]
	var palette_index: int = _colours[index]
	if GameDataRegistry == null:
		button.text = "Colour %d" % (palette_index + 1)
		return

	var colour := GameDataRegistry.colour(palette_index)
	button.text = String(GameDataRegistry.colour_slug(palette_index)) \
			.trim_prefix("colour.").capitalize()

	var style := StyleBoxFlat.new()
	style.bg_color = colour
	style.border_color = Color(0.0, 0.0, 0.0, 0.6)
	style.set_border_width_all(1)
	style.set_content_margin_all(6)
	button.add_theme_stylebox_override("normal", style)
	var lit := style.duplicate() as StyleBoxFlat
	lit.bg_color = colour.lightened(0.15)
	button.add_theme_stylebox_override("hover", lit)
	button.add_theme_stylebox_override("pressed", lit)
	button.add_theme_stylebox_override("focus", style)
	# A DISABLED SWATCH STILL SHOWS ITS COLOUR, dimmed. Every colour button but your
	# own is disabled on a joined client (`_refresh_lobby`), and left to the theme's
	# default those rows would all go grey -- which on this screen means the player
	# list stops saying who is which colour, the one thing it exists to say.
	var dim := style.duplicate() as StyleBoxFlat
	dim.bg_color = Color(colour, 0.55)
	button.add_theme_stylebox_override("disabled", dim)

	# Black on yellow, white on blue: the palette deliberately spans L* 36 to 100
	# (colours.json's ladder), so one fixed ink colour is illegible at one end of it.
	var ink := Color.BLACK if colour.get_luminance() > 0.5 else Color.WHITE
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		button.add_theme_color_override(state, ink)
	button.add_theme_color_override("font_disabled_color", Color(ink, 0.7))
