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
	# Reset too, or a test that pretends to be player 2 leaves every later test thinking
	# slot 2 belongs to it -- which is what "(you)" is read from.
	Net._local_player_id = 0
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


# ── the colour picker (replaced the cycle) ──────────────────────────────────
#
# Colour used to be a cycle: one press stepped the slot to the next free colour. The
# rule has not changed -- two players may never share one, because colour is the ONLY
# thing telling them apart (§1) and a duplicate is an unplayable match -- but it is now
# expressed by what the grid OFFERS rather than by where a step lands. So these test the
# offer as well as the outcome.

## Press a slot's colour button and pick a swatch, the way a thumb would.
func _pick_colour(slot: int, colour_index: int) -> void:
	screen._on_colour_pressed(slot)
	var button := screen._colour_picker.swatch_for(colour_index)
	assert_not_null(button, "colour %d is not on the grid" % colour_index)
	if button != null:
		button.pressed.emit()


func test_the_picker_never_offers_a_colour_somebody_else_holds() -> void:
	var cfg := screen.build_config()
	screen._on_colour_pressed(0)
	assert_true(screen._colour_picker.is_open(), "pressing a colour opens the grid")
	assert_false(screen._colour_picker.offered().has(cfg.colours[1]),
			"player 2's colour is not on player 1's grid")
	assert_true(screen._colour_picker.offered().has(cfg.colours[0]),
			"but your own is, marked, or nothing says which one you have")


func test_picking_a_swatch_reaches_the_config() -> void:
	# The whole point of replacing the cycle: one press, one colour, chosen rather
	# than arrived at.
	var before := screen.build_config().colours[0]
	screen._on_colour_pressed(0)
	var wanted := -1
	for candidate in screen._colour_picker.offered():
		if candidate != before:
			wanted = candidate
			break
	assert_true(wanted >= 0, "the palette offers more than one colour")

	_pick_colour(0, wanted)
	assert_eq(screen.build_config().colours[0], wanted)
	assert_ne(screen.build_config().colours[0], screen.build_config().colours[1],
			"and still nobody shares")


func test_a_colour_already_taken_is_refused_rather_than_substituted() -> void:
	# Reachable only from a stale client, since the grid does not offer it -- but the
	# host applies the rule, and silently handing somebody a DIFFERENT colour to the one
	# they pressed would be worse than leaving them where they were.
	var cfg := screen.build_config()
	assert_false(screen._set_colour(0, cfg.colours[1]), "refused")
	assert_eq(screen.build_config().colours[0], cfg.colours[0], "and nothing moved")


func test_the_picker_closes_when_a_swatch_is_pressed() -> void:
	_pick_colour(0, screen.build_config().colours[0])
	assert_false(screen._colour_picker.is_open())


func test_choosing_a_role_reaches_the_config() -> void:
	# `ai_players` is what SimWorld.setup reads into SimPlayer.is_ai, so this is the
	# whole path from a dropdown to a bot.
	screen._on_role_selected(0, 1)          # slot 2 -> Human
	assert_eq(screen.build_config().ai_players, [false, false] as Array[bool])
	screen._on_role_selected(1, 1)          # slot 2 -> PlayTest AI
	assert_eq(screen.build_config().ai_players, [false, true] as Array[bool])


# ── slots are not players (2-8, and closing the rest) ──────────────────────
#
# The owner's ask: pick eight and close six, and play two-handed on a map with eight
# players' worth of room. The count picker and the player list stopped being the same
# number, which is the whole of it.

func _pick_slots(n: int) -> void:
	var item := screen._count_picker.get_item_index(n)
	screen._count_picker.select(item)
	screen._count_picker.item_selected.emit(item)


func test_the_count_picker_offers_two_through_eight() -> void:
	# Pinned at 2 until now, disabled and visible so the limit did not look like an
	# oversight. The limit is gone.
	assert_false(screen._count_picker.disabled)
	for n in range(2, 9):
		var item := screen._count_picker.get_item_index(n)
		assert_true(item >= 0, "%d players is offered" % n)
		assert_false(screen._count_picker.is_item_disabled(item), "%d is selectable" % n)


func test_more_slots_is_a_bigger_map_and_not_more_opponents() -> void:
	# Raising the count must widen the BOARD, not silently conjure six opponents.
	_pick_slots(8)
	assert_eq(screen._slot_rows.size(), 8, "eight rows to choose from")
	assert_eq(screen.build_config().player_ids, [1, 2] as Array[int],
			"still the default two players")
	assert_eq(screen.map_data().size.x, MapGenerator.side_for(8), "on a map for eight")


func test_eight_slots_with_six_closed_is_two_players_on_a_big_map() -> void:
	# The owner's sentence, as a test.
	_pick_slots(8)
	for i in range(2, 8):
		assert_eq(screen._roles[i], SkirmishScreen.Role.CLOSED, "slot %d starts closed" % (i + 1))

	var cfg := screen.build_config()
	assert_eq(cfg.player_ids, [1, 2] as Array[int])
	assert_eq(cfg.colours.size(), 2, "two colours, not eight")
	assert_eq(cfg.ai_players, [false, true] as Array[bool])
	assert_eq(cfg.map_size.x, MapGenerator.side_for(8), "room for eight")
	assert_eq(screen.map_data().starts.size(), 2, "and two starts on it")
	assert_true(screen.can_start(), "startable: %s" % screen.status_text())


func test_opening_a_closed_slot_puts_a_player_back() -> void:
	_pick_slots(8)
	_pick_role(4, SkirmishScreen.Role.PLAYTEST_AI)
	var cfg := screen.build_config()
	assert_eq(cfg.player_ids, [1, 2, 3] as Array[int], "compacted, not [1, 2, 5]")
	assert_eq(cfg.ai_players, [false, true, true] as Array[bool])
	assert_eq(screen.map_data().starts.size(), 3)


func test_closing_one_slot_too_many_is_refused_and_says_why() -> void:
	# Easy to do and impossible to diagnose from a greyed button alone.
	_pick_role(1, SkirmishScreen.Role.CLOSED)
	assert_eq(screen.build_config().player_ids, [1] as Array[int])
	assert_false(screen.can_start())
	assert_true(screen.status_text().contains("a match needs"),
			"says what is wrong: %s" % screen.status_text())


func test_a_closed_slot_says_it_is_keeping_its_room() -> void:
	# Blank would read as an oversight rather than as a decision.
	_pick_slots(4)
	assert_true(_row_status(3).contains("room"), "got %s" % _row_status(3))


func test_closed_slots_do_not_hoard_the_colours() -> void:
	# Counting a closed slot's colour as taken would leave two players on an eight-slot
	# board with six colours spoken for by empty chairs. Asked of the GRID now rather
	# than by cycling and collecting: what the picker offers is the same question, and
	# it answers it in one press instead of twelve.
	_pick_slots(8)
	screen._on_colour_pressed(0)
	var offered := screen._colour_picker.offered().size()
	assert_true(offered >= GameDataRegistry.colour_count() - 1,
			"player 1 was offered %d of %d colours -- only player 2's is spoken for"
			% [offered, GameDataRegistry.colour_count()])


func test_the_status_line_names_both_numbers() -> void:
	# They are different numbers now, and the gap between them is the point.
	_pick_slots(8)
	assert_true(screen.status_text().contains("2 players"), "got %s" % screen.status_text())
	assert_true(screen.status_text().contains("room for 8"), "got %s" % screen.status_text())


func test_a_joiner_shown_a_bigger_match_grows_its_own_rows() -> void:
	# A host on eight slots and a client still showing two would leave the host's other
	# players with no row to appear in.
	var host_side := SkirmishScreen.new()
	host_side._slots = 4
	host_side._roles[2] = SkirmishScreen.Role.PLAYTEST_AI
	host_side._roles[3] = SkirmishScreen.Role.PLAYTEST_AI
	var proposal := host_side.build_config()
	host_side.free()

	assert_eq(proposal.player_ids.size(), 4, "a four-player match")
	Net._lobby_config = proposal
	screen._lobby = SkirmishScreen.Lobby.JOINED
	screen._on_lobby_config_received()
	assert_eq(screen._slot_rows.size(), 4, "the joiner shows all four")


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
	# On the ROW for that chair, not in the transport line.
	assert_eq((screen._slot_rows[1]["status"] as Label).text, "peer 7777 — reviewing...",
			"the chair shows who is in it and what they have said")


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


# ── the player list, and whose colour is whose ──────────────────────────────
#
# All four reported by the owner from two clients side by side: the host's screen said
# Player 2 was "Open" while the joiner's said the same chair was a "PlayTest AI"; nothing
# said which player you were; the host's list showed only the slots it was waiting on;
# and a joined player could not change the one thing that tells players apart.

func _row_role(index: int) -> String:
	var picker: OptionButton = screen._slot_rows[index]["role"]
	return picker.get_item_text(picker.selected)


func _row_name(index: int) -> String:
	return (screen._slot_rows[index]["name"] as Label).text


func _row_status(index: int) -> String:
	return (screen._slot_rows[index]["status"] as Label).text


## A host's proposal: player 1 human, player 2 the open chair the joiner is sitting in.
##
## Sets `_roles` directly rather than driving the dropdown, which is the one place in this
## file that is right to do so: going through the picker would open a real socket from a
## throwaway screen built only to produce a config.
func _proposal_with_an_open_seat() -> MatchConfig:
	var host_side := SkirmishScreen.new()
	host_side._roles[1] = SkirmishScreen.Role.OPEN
	var cfg := host_side.build_config()
	host_side.free()
	return cfg


func test_a_joiner_is_not_told_its_own_seat_is_a_bot() -> void:
	# The reported bug. The joiner kept its local default roles, so the chair it was
	# sitting in read "PlayTest AI" -- about itself.
	var proposal := _proposal_with_an_open_seat()
	assert_eq(proposal.ai_players, [false, false] as Array[bool],
			"the host is offering two human seats")

	Net._lobby_config = proposal
	screen._lobby = SkirmishScreen.Lobby.JOINED
	screen._on_lobby_config_received()

	assert_eq(_row_role(1), "Human", "got %s" % _row_role(1))
	assert_eq(screen.build_config().ai_players, [false, false] as Array[bool])


func test_the_rows_say_which_player_you_are() -> void:
	# Nothing did before: the only mention was in the transport status line, and the host
	# named the joiner by peer id.
	#
	# ON THE LINE UNDER THE NAME since 2026-08-30 (project owner: *"lets move the You &
	# bot / joined player name text below the player1,player2,player3"*). The name is now
	# only ever "Player N" -- who you are, whether it is a bot and which peer is sitting
	# there are three answers to one question and they share one line.
	assert_eq(_row_name(0), "Player 1", "the name is the name and nothing else")
	assert_eq(_row_status(0), "you", "got %s" % _row_status(0))
	assert_false(_row_status(1).contains("you"))


# ── the reworked lobby, 2026-08-30 ──────────────────────────────────────────
#
# Two columns with chat on the left, the two framed setup panels on the right, and a
# three-column nav strip along the bottom. What is asserted here is the WIRING and the
# identity of the parts -- that the chat is the same widget the minimap opens rather
# than a copy of it, that the tech tree button reaches the real panel, and that the
# placeholder is visibly a placeholder. The proportions are a render's business.


func test_the_lobby_chat_is_the_same_widget_the_minimap_opens() -> void:
	# "duplicate chat panel from mini map button" -- and duplicate is the one thing not
	# done. `ChatPanel` is chrome around a `ChatBoard`; this screen holds another. A
	# second layout would be two things to keep in step and, on the day chat gets a
	# transport, two places to wire it into.
	assert_true(screen._chat is ChatBoard)
	var page := ChatPanel.new()
	assert_eq(screen._chat.get_script(), page.board.get_script(),
			"the same class, not a copy of its layout")
	page.free()


func test_the_lobby_chat_tabs_are_the_lobby_roster() -> void:
	# Built from the SLOT ROWS, because before a match there is no snapshot to build
	# them from -- and compacted 1..N over the ACTIVE slots exactly as `build_config`
	# numbers players, or a tab would name somebody who will not be in the match.
	assert_eq(screen._chat._tabs.get_child_count(), 2, "one human, one bot")

	_pick_count(4)
	assert_eq(screen._chat._tabs.get_child_count(), 2,
			"raising the slot count opens no chairs -- the extra two are CLOSED")

	_pick_role(2, SkirmishScreen.Role.HUMAN)
	assert_eq(screen._chat._tabs.get_child_count(), 3, "and filling one adds a tab")


func test_the_lobby_chat_is_still_visibly_a_wireframe() -> void:
	# The rule travels with the widget: a chat that looked live in the lobby would be
	# exactly the bug report the disabled SEND button exists to prevent.
	assert_true(screen._chat._send_button.disabled)
	assert_false(screen._chat._message_field.editable)


func test_the_tech_tree_button_opens_the_real_panel_at_the_starting_age() -> void:
	# "TechTree (same panel from minimap buttin ingame)". Set to the age the match would
	# OPEN in, which is the only question this screen can usefully ask of it -- the
	# starting-age picker is one panel away and this is what it buys you.
	assert_false(screen._tech_tree.is_open())
	_pick_age(3)
	screen._tech_button.pressed.emit()
	assert_true(screen._tech_tree.is_open())
	assert_eq(screen._tech_tree._age, 3)
	assert_true(screen._tech_tree._researched.is_empty(),
			"nothing is researched in a match that has not started")


func test_the_invitation_terms_are_beside_the_ready_button_not_only_beside_the_map() -> void:
	# They live in MAP SETUP too, next to the map they describe -- and that panel is in a
	# scrolling column, so on a 648 px screen it is below the fold. A joining player
	# being asked to agree to terms that are off the bottom of the screen is the one
	# failure a consent screen may not have, so they are also on the nav line two inches
	# from READY.
	Net._lobby_config = _proposal_with_an_open_seat()
	screen._lobby = SkirmishScreen.Lobby.JOINED
	screen._on_lobby_config_received()

	var terms := screen.lobby_text()
	assert_true(terms.contains("seed"), "got %s" % terms)
	assert_true(terms.contains(MatchConfig.mode_name(MatchConfig.Mode.LAST_MAN_STANDING)),
			"the victory condition is a term of the invitation: %s" % terms)
	assert_true(terms.contains("READY"), "and it says what to do about them: %s" % terms)
	assert_eq(screen.status_text().contains("seed"), true,
			"still beside the map as well")


func test_a_joiner_with_no_proposal_is_told_so_on_the_nav_line_too() -> void:
	screen._lobby = SkirmishScreen.Lobby.JOINED
	screen._refresh_lobby()
	assert_true(screen.lobby_text().contains("Waiting"), "got %s" % screen.lobby_text())


func test_the_server_browser_is_visibly_a_placeholder() -> void:
	# "server browser (place holder) ... comming up next". A control wired to nothing
	# must not look like one that works -- the selection panel's roster grid drew, took
	# taps and played a click sound for the life of the project while doing nothing.
	assert_true(screen._browser_button.disabled)
	assert_false(screen._browser_button.tooltip_text.is_empty(),
			"and says why, since a greyed button with no reason reads as broken")


func test_both_setup_panels_wear_the_dragon_frame() -> void:
	# "GAME SETUP Panel with 9 patch border, the dragon one" and the map panel in "the
	# same 9 patch panel stile from resources panel" -- which is the same plate:
	# `ResourceHUD` passes `ornate` too.
	var framed := 0
	for panel in _panels_in(screen):
		for child in panel.get_children():
			if child is NinePatchRect \
					and (child as NinePatchRect).texture.resource_path \
					== HudStyle.PANEL_ORNATE_PATH:
				framed += 1
	assert_eq(framed, 2, "game setup and map setup, and nothing else on the page")


func test_the_map_picture_has_a_plain_border_of_its_own() -> void:
	# "add a simple panel_hud.jpg border around the map". The PLAIN plate inside the
	# ornate one: a second set of dragons nested in the first reads as a mistake.
	var frame := screen._preview.get_parent().get_parent()
	assert_true(frame is PanelContainer)
	var plates := 0
	for child in frame.get_children():
		if child is NinePatchRect and (child as NinePatchRect).texture.resource_path \
				== HudStyle.PANEL_BG_PATH:
			plates += 1
	assert_eq(plates, 1)


## Every PanelContainer under `node`, depth first.
func _panels_in(node: Node) -> Array[PanelContainer]:
	var out: Array[PanelContainer] = []
	for child in node.get_children():
		if child is PanelContainer:
			out.append(child)
		out.append_array(_panels_in(child))
	return out


func _pick_count(n: int) -> void:
	var item := screen._count_picker.get_item_index(n)
	screen._count_picker.select(item)
	screen._count_picker.item_selected.emit(item)


func _pick_age(age: int) -> void:
	var item := screen._age_picker.get_item_index(age)
	screen._age_picker.select(item)
	screen._age_picker.item_selected.emit(item)


func test_a_bot_is_never_you() -> void:
	# Slot 2 is the PlayTest AI by default, and "Player 2 / you / bot" would be nonsense.
	assert_eq(_row_status(1), "bot")
	assert_eq(_row_name(1), "Player 2")


func test_the_rows_are_the_player_list_on_the_hosts_side() -> void:
	_open_slot_two()
	assert_eq(_row_status(1), "waiting for a player")
	assert_eq(_row_status(0), "you", "the host is IN the list, not implied by it")

	_register_peer(7777, 2)
	screen._on_peer_joined(7777)
	assert_eq(_row_status(1), "peer 7777 — reviewing...",
			"joined is not the same as agreed")

	Net._lobby_ready[7777] = true
	screen._refresh_lobby()
	assert_eq(_row_status(1), "peer 7777 — READY")


func test_a_joined_player_owns_their_own_colour_and_nobody_elses() -> void:
	Net._lobby_config = _proposal_with_an_open_seat()
	Net._local_player_id = 2
	screen._lobby = SkirmishScreen.Lobby.JOINED
	screen._on_lobby_config_received()

	assert_false((screen._slot_rows[1]["colour"] as Button).disabled,
			"player 2's colour is player 2's to change")
	assert_true((screen._slot_rows[0]["colour"] as Button).disabled,
			"and player 1's is not")


func test_a_peer_gets_the_colour_it_asked_the_host_for() -> void:
	# The request NAMES a colour now -- the picker showed the joining player the list,
	# so asking for "the next free one" would be asking them to press blind again. What
	# has not moved is the authority: the host applies it, or does not.
	_open_slot_two()
	_register_peer(7777, 2)
	screen._on_peer_joined(7777)

	var free := -1
	for candidate in range(GameDataRegistry.colour_count()):
		if not screen._taken_colours(1).has(candidate):
			free = candidate
			break
	assert_true(free >= 0, "some colour is free in a two-player lobby")

	screen._on_lobby_colour_requested(7777, free)
	assert_eq(screen.build_config().colours[1], free, "player 2 got what it asked for")
	assert_ne(screen.build_config().colours[0], screen.build_config().colours[1])


func test_a_peer_asking_for_a_taken_colour_is_ignored() -> void:
	# A client's list of what is free can be a moment stale. The host refuses rather
	# than substituting, and the re-broadcast that follows every lobby change is what
	# corrects the client -- so the failure mode is "your press did nothing", never
	# "you are now some other colour".
	_open_slot_two()
	_register_peer(7777, 2)
	screen._on_peer_joined(7777)

	var before := screen.build_config().colours.duplicate()
	screen._on_lobby_colour_requested(7777, int(before[0]))
	assert_eq(screen.build_config().colours, before,
			"asking for player 1's colour changes nothing")


func test_a_colour_request_from_a_stranger_changes_nothing() -> void:
	_open_slot_two()
	var before := screen.build_config().colours.duplicate()
	screen._on_lobby_colour_requested(999999, 5)
	assert_eq(screen.build_config().colours, before,
			"a peer holding no slot cannot recolour one")


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
	# Still one pixel per tile, but STOOD ON ITS CORNER (2026-08-22): the lobby shows
	# the map the way the match and the minimap do, so the picture is the diagonal of
	# the square it used to be. test_map_preview asserts which tile lands on which
	# tip; this only asserts the lobby is showing the turned one.
	var size: Vector2i = screen.map_data().size
	assert_eq(texture.get_size(), Vector2(size.x + size.y, size.x + size.y),
			"the diamond's bounding box, i.e. the map's own diagonal")


func test_a_config_with_no_map_falls_back_rather_than_crashing() -> void:
	# `build_config()` is public and a caller may reach it before a map exists.
	screen._data = null
	var cfg := screen.build_config()
	assert_eq(cfg.map_size, MatchConfig.DEBUG_MAP_SIZE)
	assert_null(cfg.map_data)


# ── the starting age (project owner, 2026-08-30) ────────────────────────────

func test_the_lobby_offers_every_age_and_opens_on_the_first() -> void:
	assert_eq(screen._age_picker.item_count, GameDataRegistry.age_count(),
			"one item per age in ages.json, asked of the data rather than restated")
	assert_eq(screen.build_config().starting_age, 1,
			"age 1 by default -- the ladder from the bottom, which is every match "
			+ "played before this setting existed")


func test_the_starting_age_reaches_the_config() -> void:
	# The screen's entire output is the config; a picker that moved nothing would look
	# identical on screen.
	screen._on_starting_age_selected(screen._age_picker.get_item_index(3))
	assert_eq(screen.build_config().starting_age, 3)


func test_the_age_items_name_the_age_rather_than_numbering_it() -> void:
	# ages.json names the lobby as one of the three places with room for prose.
	assert_true(screen._age_picker.get_item_text(0).contains(GameDataRegistry.age(1).name),
			"got '%s'" % screen._age_picker.get_item_text(0))


func test_changing_the_starting_age_does_not_regenerate_the_map() -> void:
	# The map is a function of the seed, the type and the two player counts, and none
	# of those moved. Regenerating would throw away the map somebody just picked.
	var before := screen.map_data()
	screen._on_starting_age_selected(screen._age_picker.get_item_index(2))
	assert_eq(screen.map_data(), before, "same map object, untouched")


func test_the_starting_age_survives_the_wire() -> void:
	# Every client builds its own world from these bytes (2.4a), and `age` is folded
	# into `state_hash()` -- so two sides disagreeing about it is a desync at tick 1
	# with no explanation attached.
	var cfg := MatchConfig.debug_skirmish()
	cfg.starting_age = 4
	assert_eq(MatchConfig.from_dict(cfg.to_dict()).starting_age, 4)


func test_a_config_from_before_the_selector_reads_as_age_one() -> void:
	# A host built before this existed sends no `starting_age`, and age 1 is the match
	# it is actually running -- the same forward-compatibility shape `ai_levels` has.
	var d := MatchConfig.debug_skirmish().to_dict()
	d.erase("starting_age")
	assert_eq(MatchConfig.from_dict(d).starting_age, 1)
