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
enum Role { HUMAN, PLAYTEST_AI, OPEN }

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

var _lobby: Lobby = Lobby.LOCAL

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
	page.add_child(_build_join_row())

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(columns)
	columns.add_child(_build_map_column())
	columns.add_child(_build_match_column())

	regenerate()

	Net.peer_joined.connect(_on_peer_joined)
	Net.peer_left.connect(_on_peer_left)
	Net.match_configured.connect(_on_match_configured)
	Net.session_ended.connect(_on_session_ended)
	_refresh_lobby()


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
	count_row.add_child(_count_picker)
	column.add_child(count_row)

	for i in range(_players):
		column.add_child(_build_slot_row(i))

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
	# "Open", not "Open (waiting)". A dropdown lists the CHOICES; whether the chair is
	# still empty is status, and the lobby line below already says. The longer label read
	# as a contradiction the moment somebody was sitting in it -- a slot showing "Open
	# (waiting)" directly above "Player 2: peer 7777 joined".
	role.add_item("Open", int(Role.OPEN))
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
	_refresh_start_button()


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


## Whether START would do anything. THREE rules now, and they all live here so the button
## and the handler can never disagree about it:
##
##   1. A validated map (2.4b's gate) -- an unplayable one is never launched.
##   2. Every advertised slot filled. Starting with an empty OPEN slot would launch a
##      match one player short of the one the host set up.
##   3. Not a joined client. Over there START belongs to the host, and the local button
##      would be a second, competing authority over when the match begins.
func can_start() -> bool:
	if _data == null or not (_data.meta.get("problems", []) as Array).is_empty():
		return false
	if _lobby == Lobby.JOINED:
		return false
	return unfilled_slots() == 0


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


## Changing a slot's role is what opens and closes the socket, because the OPEN role and
## a listening host are the same fact stated twice. There is no separate "host" button to
## forget to press, and no way to advertise a slot nobody can reach.
func _on_role_selected(item: int, index: int) -> void:
	_roles[index] = (_slot_rows[index]["role"] as OptionButton).get_item_id(item) as Role

	if _wants_peers() and _lobby == Lobby.LOCAL:
		var err := Net.host_open()
		if err != OK:
			# Put the slot back rather than leaving a screen that says it is waiting for
			# someone who can never arrive. This is how the missing Android INTERNET
			# permission presented at 0.7: nothing crashed, nothing said why.
			_roles[index] = Role.HUMAN
			(_slot_rows[index]["role"] as OptionButton).select(int(Role.HUMAN))
			_say("could not open a socket: %s" % error_string(err))
			return
		_lobby = Lobby.HOSTING
	elif not _wants_peers() and _lobby == Lobby.HOSTING:
		# The last advertised slot just closed, so stop listening. Reachable only while
		# no peer has arrived -- a slot with somebody in it has its dropdown disabled.
		Net.leave()
		_lobby = Lobby.LOCAL
		_slot_peers.clear()
		# The host closed the slot itself, so `session_ended`'s "left" is not news.
		_say("")

	_refresh_lobby()


## Whether any slot is waiting for a person on another device.
func _wants_peers() -> bool:
	for i in range(_players):
		if _roles[i] == Role.OPEN:
			return true
	return false


## Advertised slots that nobody is standing in yet. START waits on this reaching zero:
## starting with an empty OPEN slot would launch a match one player short of the one the
## host set up.
func unfilled_slots() -> int:
	var count := 0
	for i in range(_players):
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
	_refresh_lobby()


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
	if preferred >= 0 and preferred < _players \
			and _roles[preferred] == Role.OPEN and not _slot_peers.has(preferred):
		return preferred
	for i in range(_players):
		if _roles[i] == Role.OPEN and not _slot_peers.has(i):
			return i
	return -1


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

	# AND THE PREVIEW GOES, which is the one that actually mattered. A joined client had
	# generated its own random map on the way in and was showing THAT -- a picture of a
	# map it will never play, captioned "ready", while the map it is really waiting for
	# lives on the host and does not arrive until the match starts. A blank panel that
	# says who chooses is worth more than a convincing wrong one.
	_preview.visible = not joined
	for i in range(_slot_rows.size()):
		var role_picker: OptionButton = _slot_rows[i]["role"]
		# A slot somebody is standing in cannot be un-opened. Simpler than deciding what
		# happens to a connected player when their chair is taken away.
		role_picker.disabled = joined or _slot_peers.has(i)
		(_slot_rows[i]["colour"] as Button).disabled = joined

	if joined:
		_status.text = "The host chooses the map"
		_status.add_theme_color_override("font_color", HudStyle.GOLD)

	_join_field.editable = _lobby == Lobby.LOCAL
	_join_button.disabled = _lobby != Lobby.LOCAL

	_refresh_start_button()
	_refresh_lobby_text()


func _refresh_lobby_text() -> void:
	match _lobby:
		Lobby.HOSTING:
			var lines: Array[String] = []
			lines.append("Waiting on port %d — dial %s"
					% [Net.PORT, ", ".join(_own_addresses())])
			for i in range(_players):
				if _roles[i] == Role.OPEN:
					lines.append("  Player %d: %s" % [i + 1,
							"peer %d joined" % int(_slot_peers[i]) if _slot_peers.has(i)
							else "waiting..."])
			_lobby_status.text = "\n".join(lines)
		_:
			# LEFT ALONE ON PURPOSE, rather than cleared. `Net.leave()` emits
			# `session_ended` synchronously, so this runs immediately after -- and
			# clearing here would wipe the reason a session ended at exactly the moment
			# the reason matters most, turning a dropped host into a screen that says
			# nothing. Whoever wants the line blank says so with `_say("")`.
			pass


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
