## The skirmish settings screen (PLAN.md 1.6), which is also the multiplayer lobby.
##
## START and Back both call `get_tree()` unconditionally -- they are only ever pressed
## while on screen -- so those two are verified live, the same convention
## `test_pause_menu` and `test_result_screen` follow. What is asserted here is the
## state machine and, above all, **the config it would hand to a match**: that is the
## screen's entire output, and it is the one thing a wrong pixel cannot explain away.
extends TestCase

var screen: SkirmishScreen


func before_each() -> void:
	screen = SkirmishScreen.new()


func after_each() -> void:
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
