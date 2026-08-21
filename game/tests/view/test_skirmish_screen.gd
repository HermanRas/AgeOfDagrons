## The skirmish settings screen (PLAN.md 1.6), which is also the multiplayer lobby.
##
## START and Back both call `get_tree()` unconditionally -- they are only ever pressed
## while on screen -- so those two are verified live, the same convention
## `test_pause_menu` and `test_result_screen` follow. What is asserted here is the
## state machine and, above all, **the config it would hand to a match**: that is the
## screen's entire output, and it is the one thing a wrong pixel cannot explain away.
extends TestCase

## Somewhere the game itself would never bind, so a running game and a test run do not
## contend for one port. See `before_each`.
const _TEST_PORT := 47015

var screen: SkirmishScreen


func before_each() -> void:
	screen = SkirmishScreen.new()
	# Not Net.PORT. Advertising a slot binds a real socket, so a suite on the game's own
	# port fights the game: these ten tests went red the first time the owner had this
	# screen open with a slot advertised while the suite ran.
	screen.host_port = _TEST_PORT


func after_each() -> void:
	# The lobby tests below open a REAL socket, because "set a slot to Open" and "start
	# listening" are the same act and faking one of them would test the fake. Closed here
	# rather than at the end of each test: a test that fails part way through would
	# otherwise leave port 27015 bound and take the rest of the file down with it.
	if Net.has_session():
		Net.leave()
	# The white-box pokes in the consent tests are undone here rather than in each test:
	# one that fails part way through would otherwise leave a fake peer registered and
	# take every later test with it.
	Net._peer_players.clear()
	Net._lobby_ready.clear()
	Net._lobby_config = null
	screen.free()


func test_it_opens_on_a_playable_random_map() -> void:
	# The default has to be one press from a match, or routing PLAY through this screen
	# has made the game harder to start rather than more configurable.
	assert_not_null(screen.map_data())
	assert_true(screen.can_start(), "opens ready: %s" % screen.status_text())
	assert_true(screen.status_text().contains("ready"))


func test_the_default_is_two_players_yellow_against_red_with_an_ai() -> void:
	var cfg := screen.build_config()
	assert_eq(cfg.player_ids, [1, 2] as Array[int])
	assert_eq(cfg.colours.size(), 2)
	assert_ne(cfg.colours[0], cfg.colours[1], "two players never share a colour")
	assert_eq(cfg.ai_players, [false, true] as Array[bool],
			"player 1 is the human, player 2 is the PlayTest AI")
	assert_eq(cfg.mode, MatchConfig.Mode.LAST_MAN_STANDING)


func test_the_config_it_builds_is_the_map_it_is_showing() -> void:
	# The screen's whole job. A preview of one map and a match on another would be the
	# worst possible failure here, and the cheapest to introduce.
	var cfg := screen.build_config()
	assert_eq(cfg.map_data, screen.map_data())
	assert_eq(cfg.map_size, screen.map_data().size)
	assert_eq(cfg.seed, int(screen.map_data().meta["seed"]))


func test_a_new_seed_produces_a_new_map() -> void:
	var first := screen.map_data()
	screen._on_seed_changed(4242.0)
	var second := screen.map_data()
	assert_ne(first.terrain, second.terrain)
	assert_eq(int(second.meta["seed"]), 4242)
	assert_eq(screen.build_config().seed, 4242, "and the config follows the box")


func test_the_same_seed_shows_the_same_map_again() -> void:
	# What makes a visible seed worth having: "I liked that map" has an answer.
	screen._on_seed_changed(77.0)
	var first := screen.map_data().terrain
	screen._on_seed_changed(5.0)
	screen._on_seed_changed(77.0)
	assert_eq(screen.map_data().terrain, first)


func test_picking_a_type_regenerates_at_that_type() -> void:
	# Driven through the handler rather than by setting the field, so an unwired
	# dropdown fails here rather than in play.
	for type in [MapGenerator.Type.ISLAND, MapGenerator.Type.DESERT] as Array[MapGenerator.Type]:
		var item := screen._type_picker.get_item_index(int(type))
		screen._on_type_selected(item)
		assert_eq(int(screen.map_data().meta["type"]), int(type),
				"picked %s" % MapGenerator.type_name(type))
		assert_eq(screen.build_config().map_type, type)


func test_random_stays_random_in_the_config_but_resolves_in_the_map() -> void:
	# The config records what was ASKED for, so Re-generate keeps rolling new types;
	# the map records what it BECAME.
	assert_eq(screen.build_config().map_type, MapGenerator.Type.RANDOM)
	assert_ne(int(screen.map_data().meta["type"]), int(MapGenerator.Type.RANDOM))


func test_cycling_a_colour_never_lands_on_one_already_taken() -> void:
	# Colour is the ONLY thing telling players apart (§1), so a duplicate is not a
	# cosmetic slip -- it is an unplayable match.
	for i in range(12):
		screen._on_colour_pressed(0)
		var cfg := screen.build_config()
		assert_ne(cfg.colours[0], cfg.colours[1], "collided after %d presses" % (i + 1))


func test_a_colour_cycle_actually_moves() -> void:
	var before := screen.build_config().colours[0]
	screen._on_colour_pressed(0)
	assert_ne(screen.build_config().colours[0], before)


func test_choosing_a_role_reaches_the_config() -> void:
	# `ai_players` is what SimWorld.setup reads into SimPlayer.is_ai, so this is the
	# whole path from a dropdown to a bot.
	screen._on_role_selected(0, 1)          # slot 2 -> Human
	assert_eq(screen.build_config().ai_players, [false, false] as Array[bool])
	screen._on_role_selected(1, 1)          # slot 2 -> PlayTest AI
	assert_eq(screen.build_config().ai_players, [false, true] as Array[bool])


# ── the lobby half (12.1c) ─────────────────────────────────────────────────
#
# The screen's third state. These drive the real handlers and open a real socket, for
# the same reason the rest of this file drives dropdowns rather than setting fields:
# the wiring is what is in doubt.

## Pick a role the way a finger does: move the dropdown, then let its OWN signal carry
## the change. Calling `_on_role_selected` directly would leave the button showing its
## old choice and would pass with the signal unconnected -- which is how the preview
## first came out photographing a slot labelled "PlayTest AI" with a peer sitting in it.
func _pick_role(index: int, role: SkirmishScreen.Role) -> void:
	var picker: OptionButton = screen._slot_rows[index]["role"]
	var item := picker.get_item_index(int(role))
	picker.select(item)
	picker.item_selected.emit(item)


func _open_slot_two() -> void:
	_pick_role(1, SkirmishScreen.Role.OPEN)


func test_opening_a_slot_is_what_starts_listening() -> void:
	# There is no separate host button on purpose, so this IS the hosting path.
	assert_eq(screen.lobby_state(), SkirmishScreen.Lobby.LOCAL)
	_open_slot_two()
	assert_eq(screen.lobby_state(), SkirmishScreen.Lobby.HOSTING,
			"advertising a slot opened the socket: %s" % screen.lobby_text())
	assert_true(Net.has_session(), "and there really is a session behind it")


func test_an_advertised_slot_nobody_is_in_blocks_the_start() -> void:
	# Otherwise the host launches a two-player match one player short.
	_open_slot_two()
	assert_eq(screen.unfilled_slots(), 1)
	assert_false(screen.can_start(), "cannot start on an empty chair")
	assert_true(screen._start_button.disabled, "and the button agrees")


func test_a_peer_arriving_fills_the_slot_and_frees_the_start() -> void:
	_open_slot_two()
	screen._on_peer_joined(7777)
	assert_eq(screen.unfilled_slots(), 0)
	assert_true(screen.can_start(), "the match is now the one that was set up")
	assert_false(screen._start_button.disabled)
	assert_true(screen.lobby_text().contains("7777"), "and the peer is shown: %s"
			% screen.lobby_text())


func test_a_slot_with_somebody_in_it_cannot_be_taken_away() -> void:
	# Simpler than deciding what happens to a connected player whose chair vanishes.
	_open_slot_two()
	assert_false((screen._slot_rows[1]["role"] as OptionButton).disabled)
	screen._on_peer_joined(7777)
	assert_true((screen._slot_rows[1]["role"] as OptionButton).disabled)


func test_a_peer_leaving_empties_the_slot_again() -> void:
	_open_slot_two()
	screen._on_peer_joined(7777)
	screen._on_peer_left(7777)
	assert_eq(screen.unfilled_slots(), 1, "the chair is free again")
	assert_false(screen.can_start())


func test_closing_the_last_open_slot_stops_listening() -> void:
	_open_slot_two()
	_pick_role(1, SkirmishScreen.Role.PLAYTEST_AI)
	assert_eq(screen.lobby_state(), SkirmishScreen.Lobby.LOCAL)
	assert_false(Net.has_session(), "the socket went with the slot")
	assert_true(screen.can_start(), "and it is an ordinary skirmish again")


func test_an_open_slot_is_a_person_not_a_bot() -> void:
	# `ai_players` drives SimPlayer.is_ai. An Open slot marked true would put a bot in
	# the chair a joining player is sitting in.
	_open_slot_two()
	assert_eq(screen.build_config().ai_players, [false, false] as Array[bool])


func test_a_joined_client_configures_nothing_and_cannot_start() -> void:
	# START belongs to the host over there; a live one here would be a second authority
	# over when the match begins.
	screen._lobby = SkirmishScreen.Lobby.JOINED
	screen._refresh_lobby()
	assert_false(screen.can_start())
	assert_true(screen._start_button.disabled)
	assert_false(screen._seed_box.editable, "the host chose the map, not this device")
	assert_true(screen._type_picker.disabled)
	assert_true(screen._reroll_button.disabled)
	assert_true(screen._mode_picker.disabled)
	assert_true(screen._count_picker.disabled)
	assert_true((screen._slot_rows[0]["role"] as OptionButton).disabled)


func test_a_joined_client_shows_no_map_until_it_has_the_hosts_map() -> void:
	# The worst thing on the joined screen before the lobby channel: a client generated
	# its own random map on the way in and showed it captioned "ready", while the map it
	# would actually play was on the host and did not arrive until the match started. A
	# convincing wrong picture is worse than no picture -- so in the one window where
	# this device genuinely does not know, between connecting and the host's first
	# broadcast, it shows nothing and says it is waiting. Once a proposal lands it shows
	# that, which `test_a_joiner_sees_the_hosts_map_rather_than_one_of_its_own` covers.
	assert_true(screen._preview.visible, "the host's own screen still previews")
	screen._lobby = SkirmishScreen.Lobby.JOINED
	screen._refresh_lobby()
	assert_false(screen._preview.visible, "nothing to show yet, so nothing shown")
	assert_true(screen.status_text().contains("Waiting for the host"),
			"and it says what it is waiting for, got: %s" % screen.status_text())


func test_why_a_session_ended_survives_the_refresh_that_follows_it() -> void:
	# `Net.leave()` emits `session_ended` SYNCHRONOUSLY, so the refresh runs immediately
	# after the message is written. A refresh that cleared the line would blank the
	# reason at exactly the moment it matters -- a dropped host reading as nothing at all.
	_open_slot_two()
	screen._on_session_ended("server disconnected")
	assert_true(screen.lobby_text().contains("server disconnected"),
			"kept the reason, got: %s" % screen.lobby_text())
	assert_eq(screen.lobby_state(), SkirmishScreen.Lobby.LOCAL)


# ── consent: the joiner gets to look, and gets to say no ───────────────────
#
# The gap the owner spotted after the PC-to-PC run: player 2 never clicked ready and
# never saw the map, because `_recv_match_config` is only sent from `start_match()` --
# so a joining player learned the terms at the same instant they were committed to them.

## Register a peer with Net the way a real connection would, so `all_peers_ready()` has
## somebody to wait for.
##
## Reaches into `Net._peer_players` on purpose: `peer_players()` hands back a COPY, and
## the alternative to a white-box poke here is not testing the consent gate at all.
## Undone in `after_each`.
func _register_peer(peer_id: int, player_id: int) -> void:
	Net._peer_players[peer_id] = player_id


func test_a_joined_player_cannot_be_started_over() -> void:
	_open_slot_two()
	_register_peer(7777, 2)
	screen._on_peer_joined(7777)

	assert_eq(screen.unfilled_slots(), 0, "the chair is filled")
	assert_false(screen.can_start(), "but nobody has agreed to anything yet")

	Net._lobby_ready[7777] = true
	assert_true(screen.can_start(), "now they have")


func test_changing_the_match_takes_back_everyones_agreement() -> void:
	# The rule worth having: whoever said yes said yes to the settings in front of them.
	# A host who swaps the map after they agreed no longer has their consent, and a start
	# gated on a stale yes is the bug the whole channel exists to prevent.
	_open_slot_two()
	_register_peer(7777, 2)
	screen._on_peer_joined(7777)
	Net._lobby_ready[7777] = true
	assert_true(screen.can_start())

	screen._on_seed_changed(9182.0)
	assert_false(Net.is_peer_ready(7777), "a new map is a new question")
	assert_false(screen.can_start(), "and it has not been answered")


func test_a_peer_that_leaves_does_not_leave_its_yes_behind() -> void:
	_open_slot_two()
	_register_peer(7777, 2)
	screen._on_peer_joined(7777)
	Net._lobby_ready[7777] = true

	Net._on_peer_disconnected(7777)
	assert_false(Net.is_peer_ready(7777), "their agreement went with them")


func test_a_joiner_sees_the_hosts_map_rather_than_one_of_its_own() -> void:
	# Before the lobby channel this screen hid its preview when joined, because the only
	# map it had was one it generated itself and would never play. Now there is a real one.
	var host_cfg := SkirmishScreen.new()
	host_cfg._on_seed_changed(4242.0)
	var proposal := host_cfg.build_config()

	Net._lobby_config = proposal
	screen._lobby = SkirmishScreen.Lobby.JOINED
	screen._on_lobby_config_received()

	assert_eq(screen.map_data().terrain, proposal.map_data.terrain,
			"the joiner is looking at the host's actual map")
	assert_eq(screen.build_config().seed, 4242, "and its actual seed")
	assert_true(screen._preview.visible, "shown, not hidden")
	assert_true(screen.status_text().contains("4242"), "and stated: %s"
			% screen.status_text())
	# The RESOLVED type, the same thing the host's own screen says about this map. A
	# consent screen telling the two sides different things about one map is the last
	# thing it should do.
	var resolved: MapGenerator.Type = proposal.map_data.meta["type"]
	assert_true(screen.status_text().contains(MapGenerator.type_name(resolved)),
			"names the map it is showing, not the roll that picked it: %s"
			% screen.status_text())
	host_cfg.free()


func test_a_joiner_starts_out_not_ready_and_can_change_its_mind() -> void:
	Net._lobby_config = screen.build_config()
	screen._lobby = SkirmishScreen.Lobby.JOINED
	screen._on_lobby_config_received()

	assert_false(screen._am_ready, "agreement is never the default")
	assert_true(screen._ready_button.visible, "and there is a way to give it")
	assert_eq(screen._ready_button.text, "READY")

	screen._on_ready_pressed()
	assert_true(screen._am_ready)
	assert_eq(screen._ready_button.text, "NOT READY", "and a way to take it back")

	screen._on_ready_pressed()
	assert_false(screen._am_ready)


func test_a_joiner_with_no_proposal_yet_cannot_agree_to_one() -> void:
	# The one honest gap: between connecting and the host's first broadcast, this device
	# really does not know what it would be agreeing to.
	screen._lobby = SkirmishScreen.Lobby.JOINED
	screen._refresh_lobby()
	assert_true(screen._ready_button.disabled)
	assert_true(screen.status_text().contains("Waiting"), "and says so: %s"
			% screen.status_text())


func test_an_unplayable_map_cannot_be_started_and_says_why() -> void:
	# The gate 2.4b built, surfaced. Forced by handing the screen a map that fails
	# validation, since the generator will not produce one on purpose.
	screen._data = MapData.create(Vector2i(16, 16))
	screen._data.meta["problems"] = ["player 2 cannot reach player 1"]
	screen._start_button.disabled = true
	screen._status.text = "Unplayable map: player 2 cannot reach player 1"

	assert_false(screen.can_start())
	assert_true(screen._start_button.disabled, "START is refused")
	assert_true(screen.status_text().contains("cannot reach"), "and the reason is shown")


func test_regenerating_after_a_bad_map_re_enables_start() -> void:
	screen._data = MapData.create(Vector2i(16, 16))
	screen._data.meta["problems"] = ["nonsense"]
	assert_false(screen.can_start())

	screen.regenerate()
	assert_true(screen.can_start())
	assert_false(screen._start_button.disabled)


func test_the_preview_draws_the_map_it_was_given() -> void:
	var texture := screen._preview.texture
	assert_not_null(texture, "there is a picture")
	assert_eq(texture.get_size(), Vector2(screen.map_data().size),
			"one pixel per tile, at the map's own size")


func test_a_config_with_no_map_falls_back_rather_than_crashing() -> void:
	# `build_config()` is public and a caller may reach it before a map exists.
	screen._data = null
	var cfg := screen.build_config()
	assert_eq(cfg.map_size, MatchConfig.DEBUG_MAP_SIZE)
	assert_null(cfg.map_data)
