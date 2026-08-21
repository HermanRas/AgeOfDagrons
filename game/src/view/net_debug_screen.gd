## A DELIBERATELY THROWAWAY multiplayer entry point (PLAN.md 12.1g).
##
## The real screen is 12.1c -- the skirmish screen in lobby mode, with an Open slot, a
## listening host and a joined peer list. The plan puts (g) BEFORE (c) on purpose, to get
## a two-device match on real hardware before the polish, and that needs some way to say
## "host" or "join 192.168.x.y" from a phone. This is that way and nothing more.
##
## Built in code rather than authored as a `.tscn`, against this project's menu
## convention, precisely BECAUSE it is temporary: there is no layout here worth opening
## in the editor, and when 12.1c lands this file and its scene are deleted whole rather
## than untangled from a mockup.
##
## The one part worth keeping is the address list: a host has to tell the other device
## which IP to dial, and reading it off the screen beats `ipconfig` on a phone.
extends Control

const _GAME_SCENE := "res://scenes/game/Game.tscn"
const _MAIN_MENU_SCENE := "res://scenes/menu/MainMenu.tscn"

## The match a debug host starts. A generated map, because a hosted match must carry its
## terrain as data (12.1b) and the fixed debug map carries none.
const _SEED := 3

var _status: Label
var _address: LineEdit
var _host_button: Button
var _join_button: Button


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var panel := ColorRect.new()
	panel.color = Color(0.06, 0.05, 0.04)
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(panel)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override("separation", 18)
	box.offset_left = 40
	box.offset_right = -40
	box.offset_top = 40
	box.offset_bottom = -40
	add_child(box)

	box.add_child(_label("MULTIPLAYER (debug)", 40))
	box.add_child(_label("This device: %s" % ", ".join(_own_addresses()), 24))

	_status = _label("idle", 26)
	box.add_child(_status)

	_address = LineEdit.new()
	_address.placeholder_text = "host address, e.g. 192.168.0.12"
	_address.text = "127.0.0.1"
	_address.add_theme_font_size_override("font_size", 30)
	_address.custom_minimum_size = Vector2(0, 64)
	box.add_child(_address)

	_host_button = _button("HOST (wait for one player)")
	_host_button.pressed.connect(_on_host_pressed)
	box.add_child(_host_button)

	_join_button = _button("JOIN")
	_join_button.pressed.connect(_on_join_pressed)
	box.add_child(_join_button)

	var back := _button("BACK")
	back.pressed.connect(func() -> void:
		Net.leave()
		get_tree().change_scene_to_file(_MAIN_MENU_SCENE))
	box.add_child(back)

	Net.peer_joined.connect(_on_peer_joined)
	Net.match_configured.connect(_on_match_configured)
	Net.session_ended.connect(_on_session_ended)

	# `-- --net host` / `-- --net join --ip 192.168.0.12`, so the DESKTOP side can be
	# driven from a terminal. (g) is a two-device test and only one of the two devices
	# has somebody standing at a keyboard; the phone is the half that wants thumbs.
	# Deferred so the buttons exist and the tree is settled before anything fires.
	match _string_arg("--net", ""):
		"host":
			call_deferred("_on_host_pressed")
		"join":
			_address.text = _string_arg("--ip", "127.0.0.1")
			call_deferred("_on_join_pressed")


## Every address this device answers on, so the other one knows what to dial. Loopback
## and IPv6 are filtered out: neither is what you type into the other phone.
func _own_addresses() -> Array[String]:
	var out: Array[String] = []
	for a in IP.get_local_addresses():
		var s := String(a)
		if s.begins_with("127.") or s.contains(":"):
			continue
		out.append(s)
	if out.is_empty():
		out.append("no network address")
	return out


func _on_host_pressed() -> void:
	var err := Net.host_open()
	if err != OK:
		_status.text = "host_open failed: %s" % error_string(err)
		return
	_host_button.disabled = true
	_join_button.disabled = true
	_say("listening on port %d as player %d -- waiting for a player to join"
			% [Net.PORT, Net.local_player_id()])
	_say("  dial one of: %s" % ", ".join(_own_addresses()))


## Someone joined. Start the match and hand over to the real game scene.
##
## `start_match()` before the scene change, so `GameScene._ready()` finds the config
## already settled -- and the clock stays held until the joiner reports ready (12.1d), so
## nothing is missed by starting the world a moment before the view exists.
func _on_peer_joined(peer_id: int) -> void:
	var pid: int = int(Net.peer_players().get(peer_id, 0))
	_say("peer %d joined as player %d -- starting the match" % [peer_id, pid])
	Net.start_match(MatchConfig.debug_generated(_SEED, MapGenerator.Type.FOREST, 2))
	get_tree().change_scene_to_file(_GAME_SCENE)


func _on_join_pressed() -> void:
	var ip := _address.text.strip_edges()
	if ip.is_empty():
		_status.text = "enter the host's address first"
		return
	var err := Net.join(ip, Net.PORT)
	if err != OK:
		_status.text = "join failed: %s" % error_string(err)
		return
	_host_button.disabled = true
	_join_button.disabled = true
	_status.text = "dialling %s:%d..." % [ip, Net.PORT]


## The host has described the match, so this client can draw it. `GameScene` builds its
## terrain from `Net.match_config()` and acks by itself.
func _on_match_configured() -> void:
	_status.text = "match received -- entering"
	get_tree().change_scene_to_file(_GAME_SCENE)


func _on_session_ended(reason: String) -> void:
	_status.text = "session ended: %s" % reason
	_host_button.disabled = false
	_join_button.disabled = false


## On screen AND on stdout. The host is driven from a terminal (see `--net` in `_ready`),
## where the label is not visible and the log is the only way to watch a bring-up.
func _say(text: String) -> void:
	_status.text = text
	print("net-debug: %s" % text)


func _string_arg(name: String, fallback: String) -> String:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		if args[i] == name:
			return String(args[i + 1])
	return fallback


func _label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 30)
	# Thumb-sized: this is driven on a phone, which is the whole reason (g) exists.
	b.custom_minimum_size = Vector2(0, 88)
	return b
