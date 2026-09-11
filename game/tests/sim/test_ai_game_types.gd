## The AI plays the GAME TYPE it was put in (card 14a-ai-game-types).
##
## **THE OWNER'S INSTRUCTION, 2026-09-11:** *"for Trophy the ai must turtle, follow the same blue
## print for current AI but instead of attacking player get a guard command on dragon. and for
## koth, follow the same blue print for current ai but insread of attacking player move to area."*
##
## Until then a bot played conquest in every mode -- it marched on the nearest enemy whatever the
## match was about, which is why `11.x-koth` recorded that a solo King of the Hill match against a
## bot was a walkover, and why a Trophy bot would wander away from the one unit whose death loses
## it the game.
##
## ## ⚠️ WHY THESE ARE DECISION TESTS AND NOT MATCHES
##
## `test_ai_playtest`'s header is emphatic: the AI runs inside the tick, so *"every hundred ticks
## here is real seconds of suite time"* and it caps itself at 1200. What changed here is **one
## decision** -- where the army is sent when it commits -- so these build a world, ask the system
## that question directly, and read the command it queued. A full match would spend minutes to
## observe the same branch once, and would observe it through a fog of economy.
extends TestCase

var w: SimWorld


func before_each() -> void:
	w = null


## A two-player world in `mode`, with no map generation: these tests are about a branch, and
## `MapGen` costs a second a call. Player 1 is the bot.
func _world(mode: MatchConfig.Mode) -> SimWorld:
	var cfg := MatchConfig.new()
	cfg.player_ids = [1, 2]
	cfg.teams = [0, 0]
	cfg.map_size = Vector2i(64, 64)
	cfg.mode = mode
	cfg.ai_players = [true, false] as Array[bool]
	var world := SimWorld.new()
	world.setup(cfg)
	world.map.fill_terrain(SimMap.Terrain.GRASS)
	return world


func _ai(world: SimWorld) -> AISystem:
	for s in world._systems:
		if s is AISystem:
			return s as AISystem
	return null


## An army for the bot, and something of the enemy's to march on -- so "it attacked" and "it went
## to its station" are both reachable and a test cannot pass by there being nothing to do.
func _armies(world: SimWorld) -> Array[int]:
	world.spawn_unit(&"unit.villager", 2, Vector2i(60, 60))
	var army: Array[int] = []
	for i in range(3):
		army.append(world.spawn_unit(&"unit.swordsman", 1, Vector2i(4 + i, 4)).id)
	return army


## The last command the bot queued, or null.
func _last_command(world: SimWorld) -> Command:
	var pending := world.drain_pending_commands()
	return pending[-1] if not pending.is_empty() else null


# ── Trophy: turtle on the dragon ────────────────────────────────────────────

func test_a_trophy_bot_stations_its_army_on_its_own_trophy() -> void:
	w = _world(MatchConfig.Mode.TROPHY)
	_armies(w)
	# ARMED THE WAY `MapGen._place_trophies` arms it: the world field is what says a trophy
	# match actually placed them, and the roster flag only says which unit is the trophy.
	w.trophy_def_id = &"unit.dragon_baby"
	var trophy := w.spawn_unit(&"unit.dragon_baby", 1, Vector2i(20, 20))

	assert_true(_ai(w)._issue_attack(w, w.player_for(1)), "it committed")
	var cmd := _last_command(w)
	assert_true(cmd is MoveCommand, "a guard is a MOVE onto the ground, not an attack")
	assert_true(CombatSystem.tile_gap((cmd as MoveCommand).target_tile,
			Rect2i(trophy.tile() - Vector2i(1, 1), Vector2i(3, 3))) == 0,
			"and the ground it moves to is the trophy's own")


## ⚠️ **THE ENEMY IS RIGHT THERE AND IS NOT ATTACKED**, which is the whole of "turtle". Without
## this the test above would pass on a bot that happened to find no target.
func test_a_trophy_bot_does_not_march_on_a_reachable_enemy() -> void:
	w = _world(MatchConfig.Mode.TROPHY)
	_armies(w)
	w.trophy_def_id = &"unit.dragon_baby"
	w.spawn_unit(&"unit.dragon_baby", 1, Vector2i(20, 20))

	_ai(w)._issue_attack(w, w.player_for(1))
	assert_false(_last_command(w) is AttackCommand)


## ⛔ **AN UNARMED TROPHY MATCH FALLS BACK TO CONQUEST**, which is `_king_of_the_hill()`'s and
## `_trophy()`'s shared ruling: placement is all-or-nothing, and a match that failed to arm is
## decided by elimination. A bot that turtled anyway would be standing still in a match being
## decided by a rule it was ignoring.
func test_a_trophy_match_that_never_armed_still_attacks() -> void:
	w = _world(MatchConfig.Mode.TROPHY)
	_armies(w)
	# `trophy_def_id` left empty -- no trophy was placed.
	_ai(w)._issue_attack(w, w.player_for(1))
	assert_true(_last_command(w) is AttackCommand)


## ⚠️ **THE BOT GUARDS ITS OWN TROPHY AND NOT THE NEAREST ONE.** Reading the roster flag rather
## than ownership would send player 1's army to stand on player 2's dragon, which is a gift.
func test_a_trophy_bot_ignores_somebody_elses_trophy() -> void:
	w = _world(MatchConfig.Mode.TROPHY)
	_armies(w)
	w.trophy_def_id = &"unit.dragon_baby"
	w.spawn_unit(&"unit.dragon_baby", 2, Vector2i(6, 6))          # the ENEMY's, and close
	var mine := w.spawn_unit(&"unit.dragon_baby", 1, Vector2i(40, 40))

	_ai(w)._issue_attack(w, w.player_for(1))
	var cmd := _last_command(w)
	assert_true(cmd is MoveCommand)
	assert_eq((cmd as MoveCommand).target_tile, mine.tile(),
			"the far one that is ours, not the near one that is theirs")


# ── King of the Hill: go and stand on it ────────────────────────────────────

func test_a_koth_bot_sends_its_army_into_the_zone() -> void:
	w = _world(MatchConfig.Mode.KING_OF_THE_HILL)
	_armies(w)
	w.koth_zone = Rect2i(30, 30, 9, 9)

	assert_true(_ai(w)._issue_attack(w, w.player_for(1)))
	var cmd := _last_command(w)
	assert_true(cmd is MoveCommand, "the hill is ground to stand on, not a thing to kill")
	assert_eq(CombatSystem.tile_gap((cmd as MoveCommand).target_tile, w.koth_zone), 0,
			"and the tile it is sent to is INSIDE the zone -- §11.9 pays for occupancy")


func test_a_koth_bot_does_not_march_on_a_reachable_enemy() -> void:
	w = _world(MatchConfig.Mode.KING_OF_THE_HILL)
	_armies(w)
	w.koth_zone = Rect2i(30, 30, 9, 9)
	_ai(w)._issue_attack(w, w.player_for(1))
	assert_false(_last_command(w) is AttackCommand)


## ⛔ **A KotH MAP WITH NO HILL PLAYS AS CONQUEST AND SO MUST THE BOT.** `MapGen._place_koth_zone`
## leaves the rect empty when it cannot site one, and `_king_of_the_hill()` then falls through to
## last-man-standing by design -- *"a hang is not the safe direction, it is a slower way of being
## broken"*. The AI has to agree with the win condition or it stands still forever.
func test_a_koth_match_with_no_hill_still_attacks() -> void:
	w = _world(MatchConfig.Mode.KING_OF_THE_HILL)
	_armies(w)
	assert_eq(w.koth_zone, Rect2i(), "the premise: unarmed")
	_ai(w)._issue_attack(w, w.player_for(1))
	assert_true(_last_command(w) is AttackCommand)


# ── conquest is untouched ───────────────────────────────────────────────────

## The regression guard for the other three modes. One rule now has three terminal actions, and
## the way that goes wrong is the default arm being captured by a new branch.
func test_a_last_man_standing_bot_still_attacks() -> void:
	w = _world(MatchConfig.Mode.LAST_MAN_STANDING)
	_armies(w)
	# A hill and a trophy are present and must both be IGNORED: the mode is what decides, and
	# reading the fields instead would change conquest behaviour on any map carrying them --
	# which since 13.2a is every generated map.
	w.koth_zone = Rect2i(30, 30, 9, 9)
	w.trophy_def_id = &"unit.dragon_baby"
	w.spawn_unit(&"unit.dragon_baby", 1, Vector2i(20, 20))

	_ai(w)._issue_attack(w, w.player_for(1))
	assert_true(_last_command(w) is AttackCommand)


func test_a_scenario_bot_still_attacks() -> void:
	w = _world(MatchConfig.Mode.SCENARIO)
	_armies(w)
	_ai(w)._issue_attack(w, w.player_for(1))
	assert_true(_last_command(w) is AttackCommand)


# ── the standing order keeps them there ─────────────────────────────────────

## ⚠️ **THE HALF THAT WOULD HAVE UNDONE THE WHOLE FEATURE.** `_keep_busy` runs every
## `STANDING_ORDER_INTERVAL` ticks and used to throw every idle soldier at the nearest enemy. One
## `attack` rule sends the army to the hill; five ticks later the standing order would have sent
## it straight back out, and the bot would walk away from its station forever while every test
## above still passed.
func test_the_standing_order_sends_idle_soldiers_back_to_the_station() -> void:
	w = _world(MatchConfig.Mode.KING_OF_THE_HILL)
	var army := _armies(w)
	w.koth_zone = Rect2i(30, 30, 9, 9)

	_ai(w)._keep_busy(w, w.player_for(1), true)
	var cmd := _last_command(w)
	assert_true(cmd is MoveCommand, "not an attack")
	assert_eq(CombatSystem.tile_gap((cmd as MoveCommand).target_tile, w.koth_zone), 0)
	for id in (cmd as MoveCommand).unit_ids:
		assert_true(army.has(int(id)), "and it is the army being sent")


## ⚠️ **A SOLDIER ALREADY ON STATION IS NOT RE-ORDERED**, and this is a cost test rather than a
## behaviour one. A unit standing on the hill is idle by definition, so re-issuing the whole
## garrison every five ticks would be a command per soldier per interval for the rest of the
## match, each re-entering the path service -- `THINK_INTERVAL`'s pathological re-issue arriving
## through the other door.
func test_soldiers_already_on_station_are_left_alone() -> void:
	w = _world(MatchConfig.Mode.KING_OF_THE_HILL)
	w.koth_zone = Rect2i(30, 30, 9, 9)
	w.spawn_unit(&"unit.villager", 2, Vector2i(60, 60))
	for i in range(3):
		w.spawn_unit(&"unit.swordsman", 1, Vector2i(32 + i, 32))       # inside the zone

	_ai(w)._keep_busy(w, w.player_for(1), true)
	assert_null(_last_command(w), "nobody needed telling")
