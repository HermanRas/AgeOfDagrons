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

## The same argument one port up, for discovery (2026-08-31). Both halves bind real
## sockets -- the beacon shouts at this and the browser binds it -- so a suite on
## `LanBeacon.PORT` would fight a game the owner has open, and worse, would be FOUND by
## one: a test lobby's beacon appearing in the owner's real server browser is a row for a
## host that exists for a hundredth of a second.
const _TEST_DISCOVERY_PORT := 47016

var screen: SkirmishScreen


func before_each() -> void:
	screen = SkirmishScreen.new()
	# Not Net.PORT. Advertising a slot binds a real socket, so a suite on the game's own
	# port fights the game: these ten tests went red the first time the owner had this
	# screen open with a slot advertised while the suite ran.
	screen.host_port = _TEST_PORT
	screen.discovery_port = _TEST_DISCOVERY_PORT


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


# ── teams (2026-08-31) ─────────────────────────────────────────────────────
#
# "teams number [1,2,3,4] on the lobby a small 1 char drop down next to color". Driven
# through the dropdown's own signal for `_pick_role`'s reason: the wiring is what is in
# doubt, and setting `_teams[i]` directly would pass with the picker unconnected.

func _pick_team(index: int, team: int) -> void:
	var picker: OptionButton = screen._slot_rows[index]["team"]
	var item := picker.get_item_index(team)
	assert_true(item >= 0, "team %d is on the list" % team)
	picker.select(item)
	picker.item_selected.emit(item)


func test_every_slot_opens_on_no_team_at_all() -> void:
	# The default has to be the free-for-all this game has always played -- and it also
	# has to BE representable, which is why 0 is on the list: eight slots cannot each
	# have their own side out of four numbers.
	_pick_slots(8)
	for i in range(8):
		assert_eq(screen._teams[i], 0, "slot %d starts unaligned" % (i + 1))
	assert_eq(screen.build_config().teams, [0, 0] as Array[int],
			"and the config says so for the two active slots")


func test_the_team_picker_offers_exactly_the_owners_four_and_a_way_out() -> void:
	var picker: OptionButton = screen._slot_rows[0]["team"]
	assert_eq(picker.item_count, 5, "four teams plus no-team")
	for n in range(1, 5):
		assert_true(picker.get_item_index(n) >= 0, "team %d is offered" % n)
	assert_true(picker.get_item_index(0) >= 0, "and so is leaving a team")


func test_picking_a_team_reaches_the_config() -> void:
	_pick_slots(4)
	for i in range(4):
		_pick_role(i, SkirmishScreen.Role.PLAYTEST_AI)
	_pick_team(0, 1)
	_pick_team(1, 1)
	_pick_team(2, 2)
	_pick_team(3, 2)
	assert_eq(screen.build_config().teams, [1, 1, 2, 2] as Array[int])


func test_a_closed_slot_takes_its_team_out_of_the_config_with_it() -> void:
	# Teams are compacted with everything else on the row. A team left behind by a closed
	# slot would misalign every player after it -- the same hole a hole in `ai_levels`
	# would leave, and the reason both are position-for-position.
	_pick_slots(4)
	for i in range(4):
		_pick_role(i, SkirmishScreen.Role.PLAYTEST_AI)
		_pick_team(i, 1 if i < 2 else 2)
	_pick_role(1, SkirmishScreen.Role.CLOSED)
	var cfg := screen.build_config()
	assert_eq(cfg.teams, [1, 2, 2] as Array[int])
	assert_eq(cfg.teams.size(), cfg.player_ids.size(),
			"one team per player, whatever was closed")


func test_everybody_on_one_team_is_not_a_match() -> void:
	# Two presses from the default, and `WinConditionSystem` would find exactly one
	# standing side on tick 1 -- a match won before anybody moved. Refused here rather
	# than started and instantly ended.
	assert_true(screen.can_start(), "the default is startable")
	_pick_team(0, 3)
	assert_true(screen.can_start(),
			"one aligned and one loose is still two sides -- 0 is not a team")
	_pick_team(1, 3)
	assert_false(screen.can_start(), "and now there is only one side")
	assert_true(screen.status_text().contains("two sides"),
			"and it says why rather than leaving a dead button: %s" % screen.status_text())
	_pick_team(1, 4)
	assert_true(screen.can_start(), "split them again and it is a match")


func test_the_split_is_named_on_the_line_only_when_there_is_one() -> void:
	# "1v1v1v1" is a true description of every match this game has ever played, and four
	# characters of news per player.
	# "1v1", not "v" -- the map type is on this line too and the RIVER has a v in it.
	assert_false(screen.status_text().contains("1v1"),
			"a free-for-all says nothing: %s" % screen.status_text())
	_pick_slots(4)
	for i in range(4):
		_pick_role(i, SkirmishScreen.Role.PLAYTEST_AI)
		_pick_team(i, 1 if i < 2 else 2)
	assert_true(screen.status_text().contains("2v2"), "got %s" % screen.status_text())


func test_the_bigger_side_leads_the_summary() -> void:
	# The genre's convention, and the same "assert the ORDERING" rule the galleon's
	# volley is pinned by: 2v1, never 1v2.
	#
	# THE ARGUMENT IS ONE TEAM NUMBER PER PLAYER, not a list of group sizes -- which is
	# worth saying because the first version of this test read it the other way round and
	# expected "2v1v1" of a three-player lobby.
	assert_eq(SkirmishScreen._summarise_teams([1, 1, 2, 2]), " — 2v2")
	assert_eq(SkirmishScreen._summarise_teams([1, 2, 2, 2]), " — 3v1",
			"the bigger side leads, whichever number it was given")
	assert_eq(SkirmishScreen._summarise_teams([1, 1, 2, 0]), " — 2v1v1",
			"and an unaligned player is a side of one")
	assert_eq(SkirmishScreen._summarise_teams([0, 0, 0]), "", "nobody on a team, no suffix")


func test_a_joiner_adopts_the_hosts_teams_and_cannot_change_them() -> void:
	# A colour is your identity and is yours on either device; a team is the SHAPE of the
	# match, and a joiner who could put themselves on the host's side would be rewriting
	# a 1v1 into a 2v0 nobody agreed to.
	var host_side := SkirmishScreen.new()
	host_side._slots = 4
	for i in range(4):
		host_side._roles[i] = SkirmishScreen.Role.PLAYTEST_AI
		host_side._teams[i] = 1 if i < 2 else 2
	var proposal := host_side.build_config()
	host_side.free()

	Net._lobby_config = proposal
	screen._lobby = SkirmishScreen.Lobby.JOINED
	screen._on_lobby_config_received()
	assert_eq(screen._teams.slice(0, 4), [1, 1, 2, 2] as Array[int],
			"the rows show the host's teams")
	for i in range(4):
		assert_true((screen._slot_rows[i]["team"] as OptionButton).disabled,
				"including your own row: slot %d" % (i + 1))
	assert_true(screen.terms_text().contains("2v2"),
			"and the split is a term of the invitation: %s" % screen.terms_text())


func test_a_host_with_no_teams_reads_as_a_free_for_all_on_the_joiner() -> void:
	# A config from before the selector existed carries no `teams` at all, and the match
	# that host is running is a free-for-all. Same forward-compatibility shape as
	# `ai_levels` and `starting_age`.
	var proposal := MatchConfig.debug_generated(1, MapGenerator.Type.FOREST, 2)
	assert_true(proposal.teams.is_empty(), "the fixture names no teams")
	Net._lobby_config = proposal
	screen._lobby = SkirmishScreen.Lobby.JOINED
	screen._on_lobby_config_received()
	assert_eq(screen._teams[0], 0)
	assert_eq(screen._teams[1], 0)
	assert_false(screen.terms_text().contains("1v1"),
			"and nothing is claimed about sides: %s" % screen.terms_text())


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

	var terms := screen.terms_text()
	assert_true(terms.contains("seed"), "got %s" % terms)
	assert_true(terms.contains(MatchConfig.mode_name(MatchConfig.Mode.LAST_MAN_STANDING)),
			"the victory condition is a term of the invitation: %s" % terms)
	assert_true(terms.contains("READY"), "and it says what to do about them: %s" % terms)
	assert_eq(screen.status_text().contains("seed"), true,
			"still beside the map as well")


func test_a_joiner_with_no_proposal_is_told_so_on_the_nav_line_too() -> void:
	screen._lobby = SkirmishScreen.Lobby.JOINED
	screen._refresh_lobby()
	assert_true(screen.terms_text().contains("Waiting"), "got %s" % screen.terms_text())


func test_a_host_has_no_terms_line_at_all() -> void:
	# The footer is buttons and nothing else unless this device is the one being asked
	# to agree to something -- the owner cut it to one row to get the height back.
	assert_false(screen._terms_label.visible)
	_open_slot_two()
	assert_false(screen._terms_label.visible, "hosting is not being invited")


func test_the_server_browser_opens_and_binds_a_socket() -> void:
	# "lets build out a wireframe for server browser / server discovery", then "lets wire
	# it up and make it live" (2026-08-31). The button was a disabled placeholder before
	# either, on the rule that a control wired to nothing must not look like one that
	# works -- the selection panel's roster grid drew, took taps and played a click sound
	# for the life of the project while doing nothing.
	assert_false(screen._browser_button.disabled)
	assert_false(screen._browser.is_open())
	assert_false(screen._browser.browser().is_listening(),
			"a page nobody has opened must not hold the port -- another copy of the "
			+ "game cannot then have it")

	screen._browser_button.pressed.emit()
	assert_true(screen._browser.is_open(), "the press is wired to the page")
	assert_true(screen._browser.browser().is_listening(), "and the page really listens")
	assert_eq(screen._browser.browser().listen_error(), OK)

	screen._browser.close()
	assert_false(screen._browser.browser().is_listening(),
			"and gives the port back on the way out")


func test_the_server_browser_says_why_join_is_off_rather_than_only_greying_it() -> void:
	# A DISABLED BUTTON THAT DOES NOT SAY WHY is the failure this page's whole history is
	# about, and there are four ways JOIN is off. Two of them are asserted here because
	# they are the two a player will actually meet.
	screen._browser_button.pressed.emit()
	assert_true(screen._browser.join_button().disabled, "nothing found, nothing picked")
	assert_eq(screen._browser.row_count(), 0, "and no host has been invented to fill it")

	# THE ONE THE WIREFRAME'S HEADER PREDICTED. `Net.has_session()` is true for a host the
	# moment a slot is opened, and this page is reached FROM that screen -- so without the
	# check a host pressing JOIN would be dialling out of a session it is already running,
	# and the refusal would arrive from the lobby's join two taps later.
	_open_slot_two()
	screen._browser._refresh_join()
	assert_true(screen._browser.join_button().disabled)
	assert_true(screen._browser.note_text().to_lower().contains("already in a session"),
			"it says which of the four reasons: %s" % screen._browser.note_text())


func test_picking_a_row_and_pressing_join_goes_through_the_lobbys_own_join() -> void:
	# ⚠️ **THE THIRD OF THE WIREFRAME'S FOUR PROMISES**, and the one worth a test: a
	# browser with its OWN copy of the join would rediscover every failure the lobby
	# already handles -- already in a session, a refused socket, the missing Android
	# INTERNET permission. So the press has to end in this screen's Join field and this
	# screen's button, which is what the last two assertions are about.
	screen._browser_button.pressed.emit()
	_hear_a_beacon("Study desktop", "127.0.0.1", _TEST_PORT)
	assert_eq(screen._browser.row_count(), 1, "the beacon was decoded into a row")
	assert_true(screen._browser.join_button().disabled, "nothing picked yet")
	assert_true(screen._browser.note_text().to_lower().contains("pick a server"),
			"and it says so: %s" % screen._browser.note_text())

	# THROUGH THE ROW BUTTON, not through the handler. A row wired to nothing draws and
	# takes taps exactly like one that works -- see the selection panel's roster grid,
	# inert for the whole life of the project.
	var row := _first_browser_row()
	assert_not_null(row)
	row.button_pressed = true
	row.pressed.emit()
	assert_false(screen._browser.join_button().disabled, "a picked row is joinable")
	assert_eq(screen._browser.note_text(), "", "and nothing is left to explain")

	screen._browser.join_button().pressed.emit()
	assert_false(screen._browser.is_open(),
			"the page closes first, or its own answer lands behind it")
	# THE PORT CAME WITH IT. A beacon carries the port its host actually bound, and this
	# one is not the default -- so a browser that could only dial `Net.PORT` would be one
	# that cannot reach the single host a test can stand up.
	assert_eq(screen._join_field.text, "127.0.0.1:%d" % _TEST_PORT)
	assert_eq(screen.lobby_state(), SkirmishScreen.Lobby.JOINED,
			"and the lobby's own join really ran: %s" % screen.lobby_text())


func test_advertising_a_slot_is_what_starts_the_beacon() -> void:
	# ONE ACT, exactly as opening the socket is one act -- there is no separate "make me
	# visible" button to forget, and no way to be listed without listening.
	assert_false(screen._beacon.is_advertising(), "a local skirmish tells nobody anything")
	_open_slot_two()
	assert_true(screen._beacon.is_advertising(), "an advertised slot is findable")

	# ⚠️ AND IT STOPS WITH THE SLOT. A row in somebody's browser for a lobby that is not
	# listening is a row that fails when it is pressed, and nothing on THIS machine would
	# ever show it -- so the only place the fault appears is the other player's screen.
	_pick_role(1, SkirmishScreen.Role.PLAYTEST_AI)
	assert_false(screen._beacon.is_advertising())


func test_the_beacon_counts_chairs_and_not_heads() -> void:
	# What a browser reads to decide whether a lobby is worth pressing. A CLOSED slot is
	# in neither number: it is room on the map and not a seat, which is what closing it
	# means -- so eight slots with six closed advertises "1 / 2" and not "1 / 8".
	_pick_count(8)
	_pick_role(1, SkirmishScreen.Role.OPEN)
	var cfg := screen.build_config()
	assert_eq(cfg.player_ids.size(), 2, "six of the eight are closed by default")
	assert_eq(screen.unfilled_slots(), 1, "and the open one is empty")

	var wire := LanBeacon.payload_for(cfg, screen.host_name(),
			cfg.player_ids.size() - screen.unfilled_slots(), screen.host_port)
	assert_eq(int(wire["slots"]), 2)
	assert_eq(int(wire["taken"]), 1, "the human; the open chair is not a head")


func test_the_host_name_is_never_blank_on_the_wire() -> void:
	# A host with an empty name is a browser row with nothing in its first column, and the
	# fallback there is the bare address -- which is what a host looked like before this
	# field existed and is worse than the machine name it started with. So the fallback
	# lives at the one place the name is READ, rather than in the field where it would
	# fight the player's own backspace.
	assert_ne(screen.host_name(), "", "it opens on the machine's own name")
	screen._name_field.text = "   "
	assert_eq(screen.host_name(), LanBeacon.default_host_name(),
			"a cleared field falls back rather than advertising nothing")
	screen._name_field.text = "Kitchen phone"
	assert_eq(screen.build_config().host_name, "Kitchen phone",
			"and it travels on the config, which is what the beacon reads")


func test_the_empty_list_distinguishes_quiet_from_broken() -> void:
	# A blank panel is indistinguishable from a broken page, and "there are no hosts" and
	# "this device never opened a socket" want completely different things done about them.
	screen._browser_button.pressed.emit()
	var said := ""
	for label in _labels_in(screen._browser):
		if label.text.to_lower().contains("listening for hosts"):
			said = label.text
	assert_ne(said, "", "the empty list says what it is waiting for")
	assert_true(said.to_lower().contains("join field"),
			"and names the way in that always works: %s" % said)


func test_all_three_panels_wear_the_dragon_frame() -> void:
	# "GAME SETUP Panel with 9 patch border, the dragon one", the map panel in "the same
	# 9 patch panel stile from resources panel" -- the same plate, since `ResourceHUD`
	# passes `ornate` too -- and, since the owner's second pass, the chat: *"chat pannel
	# is missing its border, it needs the same border as game and map setup"*.
	var framed := 0
	for panel in _panels_in(screen):
		for child in panel.get_children():
			if child is NinePatchRect \
					and (child as NinePatchRect).texture.resource_path \
					== HudStyle.PANEL_ORNATE_PATH:
				framed += 1
	assert_eq(framed, 3, "chat, game setup and map setup, and nothing else on the page")


func test_the_map_picture_wears_a_plain_plate_turned_to_hug_the_diamond() -> void:
	# "rotate it 45 so it hugs the mini map diamond, not a big square". The PLAIN plate,
	# deliberately, inside the ornate one: a second set of dragons nested in the first
	# reads as a mistake.
	var frame := screen._map_frame
	assert_not_null(frame, "the plate loaded")
	assert_eq(frame.texture.resource_path, HudStyle.PANEL_BG_PATH)
	assert_almost_eq(frame.rotation, PI * 0.25, 0.0001)
	assert_eq(frame.get_parent(), screen._preview.get_parent(),
			"it is laid over the picture, not around it -- containers ignore rotation")


func test_the_turned_plate_is_sized_from_the_diamonds_own_geometry() -> void:
	# `to_diamond` inscribes the diamond in a square, touching the edge midpoints, so
	# the diamond's SIDE is the square's side over root two -- and that, plus the inset,
	# is exactly what a square frame turned 45° needs to sit on it. Asserted rather than
	# eyeballed, because a frame that is close but wrong reads as a frame that is right.
	var box: Control = screen._preview.get_parent()
	box.size = Vector2(260.0, 180.0)
	screen._fit_map_frame()

	var expected := 180.0 / sqrt(2.0) + 2.0 * SkirmishScreen._MAP_FRAME_INSET
	assert_almost_eq(screen._map_frame.size.x, expected, 0.01,
			"sized off the SHORT side, which is the square the picture is drawn in")
	assert_almost_eq(screen._map_frame.size.y, expected, 0.01, "and square")
	assert_almost_eq(screen._map_frame.pivot_offset.x, expected * 0.5, 0.01,
			"turning about its own middle, or it leaves the picture entirely")


## Every PanelContainer under `node`, depth first.
## Put a host in the browser's table the way an arriving datagram would.
##
## THROUGH `LanBeacon.encode`/`decode`, not by hand, so the row under test is the shape a
## real beacon produces -- including the cap and the strip. What is skipped is only the
## socket, which `tests/net/test_lan_discovery.gd` covers with two real ones.
func _hear_a_beacon(host: String, address: String, port: int) -> void:
	var lan := screen._browser.browser()
	var row := LanBeacon.decode(LanBeacon.encode({
		"aod": LanBeacon.VERSION, "origin": "test-%s" % address, "name": host,
		"map": int(MapGenerator.Type.FOREST), "w": 96, "h": 96,
		"mode": int(MatchConfig.Mode.LAST_MAN_STANDING), "age": 1,
		"slots": 2, "taken": 1, "port": port,
	}), address)
	row["at"] = Time.get_ticks_msec()
	lan._hosts[row["origin"]] = row
	lan.poll()


func _first_browser_row() -> Button:
	for child in screen._browser._rows.get_children():
		if child is Button:
			return child
	return null


func _labels_in(node: Node) -> Array[Label]:
	var out: Array[Label] = []
	for child in node.get_children():
		if child is Label:
			out.append(child)
		out.append_array(_labels_in(child))
	return out


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


# ── saved maps in the picker (16.0) ─────────────────────────────────────────
#
# Against the repo's own `maps/` folder, read through `SavedMaps`' dev override --
# `test_campaign_screen`'s arrangement, and for its reason: the discovery rules and the seat
# arithmetic are covered over scratch directories in `test_saved_maps`, and what is left to
# assert here is that THIS SCREEN wires them to the picker, the seed box and `can_start()`.
#
# `dev_preview/preview_saved_map.tscn` authors `maps/sample_duel` and its output is
# committed, so these run on a clean clone.

## The sample map's row, or `{}` if the folder has gone. Every test below skips rather than
## fails when there is no saved map at all: the alternative is a file whose whole section
## goes red the day somebody deletes a sample, which reads as a broken feature.
func _sample_row() -> Dictionary:
	for entry in screen._saved_maps:
		if str(entry.get("folder", "")) == "sample_duel":
			return entry
	return {}


func _pick_sample() -> bool:
	var row := _sample_row()
	if row.is_empty():
		return false
	for i in screen._type_picker.item_count:
		var saved := SkirmishScreen._saved_index_of(screen._type_picker.get_item_id(i))
		if saved >= 0 and screen._saved_maps[saved] == row:
			screen._type_picker.select(i)
			screen._on_type_selected(i)
			return true
	return false


func test_the_committed_sample_map_reaches_the_picker() -> void:
	var row := _sample_row()
	assert_false(row.is_empty(), "maps/sample_duel should be discovered through the dev override")
	if row.is_empty():
		return
	assert_eq(int(row["players"]), 2)
	# The seat count is in the LABEL, because it is the one fact that decides whether the
	# lobby you have set up can start on this map -- learning it by picking the map and
	# reading a red line is worse.
	assert_true(SkirmishScreen._saved_item_label(row).contains("(2p)"),
			"the row says what it seats: " + SkirmishScreen._saved_item_label(row))


## THE ONE THAT WOULD CATCH THE FEATURE BEING A LIE: the screen must show the FILE, not a
## generated map that happens to be the same size.
func test_picking_a_saved_map_shows_the_file_and_not_a_generated_map() -> void:
	if not _pick_sample():
		return
	var shown := screen.map_data()
	assert_not_null(shown)
	if shown == null:
		return
	var problems: Array[String] = []
	var from_file := MapFile.load_map(str(_sample_row()["dir"]), problems)
	assert_eq(problems, [] as Array[String])
	assert_not_null(from_file)
	if from_file == null:
		return
	assert_eq(shown.terrain, from_file.terrain, "the screen is showing the file's terrain")
	assert_eq(shown.starts, from_file.starts)


## And it reaches the MATCH, which is the screen's entire output.
func test_the_config_carries_the_saved_map():
	if not _pick_sample():
		return
	var cfg := screen.build_config()
	assert_not_null(cfg.map_data)
	if cfg.map_data == null:
		return
	assert_eq(cfg.map_data.terrain, screen.map_data().terrain)
	# The map is the authority on its own size -- a config that disagreed with the map it
	# carries would build a world the wrong shape.
	assert_eq(cfg.map_size, cfg.map_data.size)


## A SEED MEANS NOTHING TO A FILE. Left live, the box would invite a change that either does
## nothing -- reading as a broken control -- or throws the chosen map away.
func test_a_saved_map_locks_the_seed_controls() -> void:
	if not _pick_sample():
		return
	assert_false(screen._seed_box.editable, "the seed does not describe a file")
	assert_true(screen._reroll_button.disabled)


## And switching back gives them straight back, with the seed you had. `_type` is
## deliberately never overwritten by a saved pick, which is what makes this true.
func test_going_back_to_a_generated_map_restores_the_seed_controls() -> void:
	if not _pick_sample():
		return
	var seed_before := screen.build_config().seed
	var item := screen._type_picker.get_item_index(int(MapGenerator.Type.RIVER))
	screen._type_picker.select(item)
	screen._on_type_selected(item)
	assert_true(screen._seed_box.editable)
	assert_false(screen._reroll_button.disabled)
	assert_eq(screen.build_config().seed, seed_before, "the seed you had is the seed you get")
	assert_eq(screen.build_config().map_type, MapGenerator.Type.RIVER)


## ⚠️ THE CORRECTNESS GATE, and it is not cosmetic. `MapGen.build_from()` gives a player a
## town centre and villagers only by spawning the entities the map LISTS for their index --
## it never falls back to `_start_origin()` the way the debug map does -- so a fourth player
## on a two-seat map opens the match alive, owning nothing, and is eliminated on the first
## tick anything looks.
func test_more_players_than_a_saved_map_seats_cannot_start() -> void:
	if not _pick_sample():
		return
	assert_true(screen.can_start(), "two on a two-seat map is fine: " + screen.status_text())
	_seat_players(4)
	assert_eq(screen.build_config().player_ids.size(), 4, "four players are really in it")
	assert_false(screen.can_start(), "four on a two-seat map must be refused")
	# SAID, not shown as a dead button: the fix is closing a slot, and naming both numbers
	# is what makes that obvious.
	assert_true(screen.status_text().contains("seats 2"),
			"the refusal names the number: " + screen.status_text())


## The generated case is EXEMPT, and this is what stops rule 7 from breaking every existing
## lobby: the generator builds starts for whatever count it is handed.
func test_a_generated_map_has_no_seat_limit() -> void:
	_seat_players(8)
	assert_eq(screen.build_config().player_ids.size(), 8)
	assert_true(screen.can_start(), "eight on a generated map: " + screen.status_text())


## ⚠️ **RAISING THE SLOT COUNT ADDS ROOM, NOT PLAYERS** -- new slots default to CLOSED, which
## is the whole point of `_slots` versus `_active_slots()`. So seating N players means
## setting N-1 roles as well, and a test that only moved the count picker would assert
## against a two-player lobby on a bigger board and pass for the wrong reason.
##
## This cost the 16.0 preview a red run before it cost this file one, which is the preview
## doing its job: `can_start()` was correct and the way of exercising it was not.
func _seat_players(n: int) -> void:
	var item := screen._count_picker.get_item_index(n)
	screen._count_picker.select(item)
	screen._on_count_selected(item)
	for i in range(1, n):
		var picker: OptionButton = screen._slot_rows[i]["role"]
		var role_item := picker.get_item_index(int(SkirmishScreen.Role.AI_PASSIVE))
		picker.select(role_item)
		screen._on_role_selected(role_item, i)


## A joined client never has the host's file, and the map travels as data -- so clearing the
## local selection is the whole of what it has to do. Without this the client would name its
## OWN saved map, and that map's seat count, on a screen showing the host's board.
func test_a_joined_client_forgets_its_own_saved_map() -> void:
	if not _pick_sample():
		return
	var cfg := MatchConfig.debug_skirmish()
	cfg.map_data = MapGenerator.generate(99, MapGenerator.Type.ISLAND, 2, 2)
	cfg.map_size = cfg.map_data.size
	Net._lobby_config = cfg
	screen._on_lobby_config_received()
	assert_eq(screen._saved_dir, "", "the host's map is not a file on this machine")
	assert_eq(screen.map_data().terrain, cfg.map_data.terrain, "and it shows the host's map")


## An id collision would not fail -- it would select a map TYPE, silently, and the picker
## would look right while showing the wrong board. Pinned because the guard is a constant
## somebody could reasonably decide to tidy.
func test_saved_ids_cannot_collide_with_a_map_type() -> void:
	for type in MapGenerator.Type.values():
		assert_eq(SkirmishScreen._saved_index_of(int(type)), -1,
				"map type %d must not decode as a saved map" % int(type))
	assert_eq(SkirmishScreen._saved_index_of(SkirmishScreen._SAVED_ITEM_ID_BASE), 0)
	assert_eq(SkirmishScreen._saved_index_of(SkirmishScreen._SAVED_ITEM_ID_BASE + 3), 3)
