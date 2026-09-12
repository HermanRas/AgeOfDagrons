## PLAN.md 16.7: per-entity overrides and named units — what a MAP says about ONE entity.
##
## ## WHAT THESE ARE ACTUALLY GUARDING
##
## Everything else on an entity is derived from a def that ships in the APK, or moved by a system
## both hosts run. These four fields are neither: they come out of a `map.json`, nothing
## recomputes them, and the failures are all quiet.
##
##   - **two hosts disagreeing about a hero's hp agree about every other field until somebody hits
##     him.** That is the row's own stated risk and the reason `state_hash()` had to change.
##   - **an unrecognised override key looks authored and is not.** A typo'd `"helth": 900` would
##     round-trip perfectly and leave an author certain their hero had 900 hp.
##   - **`named_unit == 0` has to mean "he died" and must not mean "nobody is called that"** —
##     `13.x-claim-dead-end`'s open trap, avoided here only because a map DECLARES its heroes.
##   - **a sentinel that swallows a real answer.** 0 attack and 0 speed are both things an author
##     may mean; 0 hp is not. The three fields do not share one sentinel for that reason.
extends TestCase

## A hero worth authoring: a def that can already fight, so an override can be told apart from the
## def's own figure in both directions.
const HERO := &"unit.militia"


# ── fixtures ────────────────────────────────────────────────────────────────

## A world built from a real `MapData` through the real `MapGen.build_from()`.
##
## ⛔ **THROUGH THE MAP AND NOT BY SPAWNING AND ASSIGNING.** Every field under test is applied by
## `build_from`, and a fixture that set `max_hp_override` by hand would pass with that function
## deleted — §5's *"beware fixtures that agree with the bug"*, pointed at the one step this row
## adds. `_world_with_area`'s shape, one row along.
func _world_with(records: Array) -> SimWorld:
	var data := MapData.create(Vector2i(48, 48), SimMap.Terrain.GRASS)
	for r in records:
		data.add_entity(
				StringName(r.get("def_id", HERE_IS_NOTHING)), int(r.get("player", 1)),
				r.get("tile", Vector2i(10, 10)), int(r.get("size_class", 0)),
				int(r.get("axis", MapData.AXIS_NONE)),
				StringName(str(r.get("name", ""))),
				r.get("overrides", {}))

	var cfg := MatchConfig.new()
	cfg.player_ids = [1, 2]
	cfg.teams = [0, 0]
	cfg.map_size = data.size
	cfg.map_data = data
	cfg.mode = MatchConfig.Mode.SCENARIO
	cfg.objective_player_id = 1
	var world := SimWorld.new()
	world.setup(cfg)
	MapGen.build_from(world, data)
	return world


## An id nothing in the roster answers to, so a record with no `def_id` fails loudly rather than
## spawning a placeholder somewhere and quietly changing a count.
const HERE_IS_NOTHING := "unit.__no_such_unit__"


## The first entity carrying `name`, or null.
func _named(w: SimWorld, name: StringName) -> SimEntity:
	for e in w.entities.values():
		if e.entity_name == name:
			return e
	return null


## The first entity of `def_id`, or null.
func _first(w: SimWorld, def_id: StringName) -> SimEntity:
	for e in w.entities.values():
		if e.def_id == def_id:
			return e
	return null


# ── the overrides reach the world ───────────────────────────────────────────

func test_a_map_can_give_one_unit_its_own_health() -> void:
	var w := _world_with([{"def_id": HERO, "overrides": {"hp": 900}}])
	var u := _first(w, HERO)
	assert_not_null(u)
	if u == null:
		return
	assert_eq(u.max_hp, 900)
	# FULL HEALTH, NOT THE DEF'S hp IN A 900 BAR. A scripted hero arrives whole; a map that wanted
	# him wounded would be saying so with a field it has not got.
	assert_eq(u.hp, 900, "an authored hero arrives at full health")


func test_a_map_can_give_one_unit_its_own_speed() -> void:
	var w := _world_with([{"def_id": HERO, "overrides": {"speed": 7}}])
	var u := _first(w, HERO) as SimUnit
	assert_not_null(u)
	if u == null:
		return
	assert_eq(u.speed, 7)


## ⛔ **A UNIT'S ATTACK IS NOT COPIED ONTO THE ENTITY**, deliberately, so that a tech researched
## mid-match reaches units already on the board. `CombatSystem.attack_base_of` is the one read, and
## it is what this asserts rather than a field.
func test_a_map_can_give_one_unit_its_own_attack() -> void:
	var w := _world_with([{"def_id": HERO, "overrides": {"attack": 60}}])
	var u := _first(w, HERO) as SimUnit
	assert_not_null(u)
	if u == null:
		return
	var def := w.unit_def(HERO)
	assert_eq(u.attack_override, 60)
	assert_eq(CombatSystem.attack_base_of(u, def), 60, "the override is the base")
	assert_ne(def.attack_damage, 60, "fixture: the def must differ, or this proves nothing")


## ⚠️ **THE OVERRIDE IS THE BASE AND NOT A CAP.** A hero authored at 60 whose owner researches a
## smithing upgrade hits for more than 60 — the override says what he IS, and the ladder is a
## thing his owner did. Asserted as an ORDERING rather than a figure, §6's rule: when one value is
## meant to be strictly stronger than another, the ordering is the rule and the numbers are inputs.
func test_an_overridden_attack_still_takes_its_owners_upgrades() -> void:
	var w := _world_with([{"def_id": HERO, "overrides": {"attack": 60}}])
	var u := _first(w, HERO) as SimUnit
	assert_not_null(u)
	if u == null:
		return
	var def := w.unit_def(HERO)
	var bonus := TechMods.for_unit(w.mods_of(u.owner_id), def, &"attack_damage")
	assert_true(bonus >= 0, "a mod table with nothing researched adds nothing")
	assert_eq(CombatSystem.attack_base_of(u, def) + bonus, 60 + bonus)


func test_a_unit_with_no_overrides_is_exactly_what_its_def_says() -> void:
	var w := _world_with([{"def_id": HERO}])
	var u := _first(w, HERO) as SimUnit
	assert_not_null(u)
	if u == null:
		return
	var def := w.unit_def(HERO)
	assert_eq(u.max_hp, def.hp)
	assert_eq(u.speed, def.speed)
	assert_eq(u.attack_override, -1, "-1 is 'the def decides'")
	assert_eq(CombatSystem.attack_base_of(u, def), def.attack_damage)
	assert_eq(u.entity_name, &"")


# ── the sentinels, which are three and not one ──────────────────────────────

## ⛔ **0 ATTACK IS A REAL ANSWER AND MUST NOT READ AS "UNSET".** An author disarming a unit
## deliberately is the case a truthiness test would silently discard — and `_process` reads
## `attack_base_of(...) <= 0` as *"this cannot fight"*, which is what a villager is.
func test_an_author_can_disarm_a_unit_and_it_is_not_read_as_unset() -> void:
	var w := _world_with([{"def_id": HERO, "overrides": {"attack": 0}}])
	var u := _first(w, HERO) as SimUnit
	assert_not_null(u)
	if u == null:
		return
	assert_eq(u.attack_override, 0)
	assert_eq(CombatSystem.attack_base_of(u, w.unit_def(HERO)), 0,
			"0 means disarmed, not 'ask the def'")


## And the mirror: an override ARMS as well as disarms, and the gate in `_process` reads the pair
## rather than the def — so a unit the roster gives a token blow to can be made a real threat.
##
## 📝 **THE STRONGER CASE — A DEF WITH NO ATTACK AT ALL — IS NOT DEMONSTRABLE WITH THIS ROSTER AND
## THAT IS WORTH RECORDING RATHER THAN FAKING.** Every unit in `units.json` carries an `attack`
## block (a villager's is 3, which is how it defends itself), so there is no civilian to arm. The
## mechanism is the same either way and it is what is asserted: `attack_base_of` answers the
## override, and the gate asks `attack_base_of` rather than the def. The day a unit ships with no
## attack, this covers it without an edit.
func test_an_override_arms_a_unit_beyond_what_its_def_carries() -> void:
	var w := _world_with([{"def_id": &"unit.villager", "overrides": {"attack": 25}}])
	var u := _first(w, &"unit.villager") as SimUnit
	assert_not_null(u)
	if u == null:
		return
	var def := w.unit_def(&"unit.villager")
	assert_true(def.attack_damage < 25, "fixture: the def must be weaker, or this proves nothing")
	assert_eq(CombatSystem.attack_base_of(u, def), 25)


## 0 speed is a deployed siege engine, which is a real thing on the board.
func test_an_author_can_pin_a_unit_in_place() -> void:
	var w := _world_with([{"def_id": HERO, "overrides": {"speed": 0}}])
	var u := _first(w, HERO) as SimUnit
	assert_not_null(u)
	if u == null:
		return
	assert_eq(u.speed_override, 0)
	assert_eq(u.speed, 0)


## ⚠️ **AND `hp` USES 0 AS ITS SENTINEL FOR THE OPPOSITE REASON**: nothing alive has 0 max hp, so
## there is no answer for the sentinel to swallow.
func test_zero_health_is_the_hp_sentinel_and_changes_nothing() -> void:
	var w := _world_with([{"def_id": HERO, "overrides": {"hp": 0}}])
	var u := _first(w, HERO)
	assert_not_null(u)
	if u == null:
		return
	assert_eq(u.max_hp, w.unit_def(HERO).hp, "0 hp means 'the def decides'")
	assert_eq(u.max_hp_override, 0)


# ── the whitelist, because a map file is untrusted input ────────────────────

## ⛔ **A KEY NOTHING READS IS DROPPED RATHER THAN CARRIED.** Without this a typo'd `"helth": 900`
## is stored, written back out, survives a round trip, shows up in the tool's inspector as nothing
## at all, and leaves an author certain they gave their hero 900 hp.
func test_an_override_key_the_game_does_not_know_is_dropped() -> void:
	var data := MapData.create(Vector2i(16, 16))
	data.add_entity(HERO, 1, Vector2i(4, 4), 0, MapData.AXIS_NONE, &"Roland",
			{"helth": 900, "hp": 500})
	var record: Dictionary = data.entities[0]
	var overrides: Dictionary = record.get("overrides", {})
	assert_false(overrides.has("helth"), "%s" % [overrides])
	assert_eq(int(overrides.get("hp", 0)), 500, "and the key it DOES know survives beside it")


func test_an_entity_with_nothing_authored_carries_neither_key() -> void:
	var data := MapData.create(Vector2i(16, 16))
	data.add_entity(HERO, 1, Vector2i(4, 4))
	var record: Dictionary = data.entities[0]
	# ⚠️ **ABSENT AND NOT EMPTY.** A `name: ""` and an `overrides: {}` on every one of a map's 170
	# entities would treble the entity list to say "this one is ordinary" 170 times — and every
	# committed map would change on its next save with nothing having been authored.
	assert_false(record.has("name"), "%s" % [record])
	assert_false(record.has("overrides"), "%s" % [record])


# ── the round trip, which is where a format change actually lives ───────────

func test_a_name_and_an_override_survive_the_wire_and_the_file() -> void:
	var data := MapData.create(Vector2i(16, 16))
	data.add_entity(HERO, 1, Vector2i(4, 4), 0, MapData.AXIS_NONE, &"Sir Roland",
			{"hp": 900, "attack": 60})
	data.add_entity(&"unit.villager", 1, Vector2i(6, 6))

	var back := MapData.from_dict(data.to_dict())
	assert_eq(back.entities.size(), 2)
	var hero: Dictionary = back.entities[0]
	assert_eq(StringName(hero.get("name", &"")), &"Sir Roland")
	var overrides: Dictionary = hero.get("overrides", {})
	assert_eq(int(overrides.get("hp", 0)), 900)
	assert_eq(int(overrides.get("attack", -1)), 60)
	# AND THE ORDINARY ONE IS STILL ORDINARY, which is what says the keys are per-entity rather
	# than per-file.
	assert_false((back.entities[1] as Dictionary).has("name"))


## ⛔ **NEITHER `FORMAT_VERSION` MOVED, AND THAT IS DECISION 7 RATHER THAN LUCK.** `MapFile`
## refuses a version mismatch outright with no migration, and five committed `map.json` files plus
## a published pack are on version 1 — so an optional field is the difference between this row
## costing nothing and costing a re-download.
func test_a_map_with_nothing_authored_is_unchanged_by_this_row() -> void:
	var data := MapData.create(Vector2i(16, 16))
	data.add_entity(&"unit.villager", 1, Vector2i(4, 4))
	var wire := data.to_dict()
	var row: Dictionary = (wire["entities"] as Array)[0]
	assert_eq(row.keys().size(), 5, "def_id, player, x, y, size_class — and nothing else: %s"
			% [row.keys()])
	assert_eq(MapData.FORMAT_VERSION, 1, "an optional field is what keeps this at 1")


# ── the hash, which is the row's stated risk ────────────────────────────────

## ⛔ **THE CARD'S OWN SENTENCE: `state_hash()` MUST FOLD THEM IN "or two clients disagree about
## how much hp a scripted hero has".** Two worlds built from maps that differ only in an override
## must not hash the same.
func test_two_hosts_reading_different_health_do_not_hash_the_same() -> void:
	var plain := _world_with([{"def_id": HERO}])
	var authored := _world_with([{"def_id": HERO, "overrides": {"hp": 900}}])
	assert_ne(plain.state_hash(), authored.state_hash())


func test_two_hosts_reading_different_attack_do_not_hash_the_same() -> void:
	var plain := _world_with([{"def_id": HERO}])
	var authored := _world_with([{"def_id": HERO, "overrides": {"attack": 60}}])
	assert_ne(plain.state_hash(), authored.state_hash())


func test_two_hosts_reading_different_speed_do_not_hash_the_same() -> void:
	var plain := _world_with([{"def_id": HERO}])
	var authored := _world_with([{"def_id": HERO, "overrides": {"speed": 7}}])
	assert_ne(plain.state_hash(), authored.state_hash())


func test_two_hosts_reading_different_names_do_not_hash_the_same() -> void:
	var plain := _world_with([{"def_id": HERO, "name": "Roland"}])
	var other := _world_with([{"def_id": HERO, "name": "Rolande"}])
	assert_ne(plain.state_hash(), other.state_hash())


## And the other direction, which is what says the hash is a function of the state rather than a
## counter: the same map twice is the same hash.
func test_the_same_authored_map_hashes_the_same_twice() -> void:
	var a := _world_with([{"def_id": HERO, "name": "Roland", "overrides": {"hp": 900}}])
	var b := _world_with([{"def_id": HERO, "name": "Roland", "overrides": {"hp": 900}}])
	assert_eq(a.state_hash(), b.state_hash())


# ── named units: the subject 16.7 unlocks ──────────────────────────────────

func test_the_loader_no_longer_refuses_a_named_unit_row() -> void:
	# ⚠️ **THE OTHER HALF OF `_NOT_YET`'s CONTRACT.** Its comment says a subject leaves that map in
	# the same commit as its evaluator and that a test asserts it, so the two cannot land apart.
	var problems: Array[String] = []
	var o := ObjectiveDef.from_dict({
		"subject": "named_unit", "name": "Sir Roland", "owner": "self",
		"compare": ">=", "value": 1, "output": "lose",
	}, problems)
	assert_not_null(o, "%s" % [problems])
	if o == null:
		return
	assert_eq(o.unit_name, &"Sir Roland")
	assert_true(ObjectiveDef._NOT_YET.is_empty(), "every declared subject is evaluable now")


func test_a_named_unit_row_must_name_somebody() -> void:
	var problems: Array[String] = []
	assert_null(ObjectiveDef.from_dict({
		"subject": "named_unit", "owner": "self", "compare": ">=", "value": 1,
	}, problems))
	assert_true(" | ".join(problems).contains("must name the unit"), "%s" % [problems])


## `area`'s rule read a second time: a name on a subject that counts things means the author meant
## `named_unit` and did not say so, and ignoring the key ships the wrong objective.
func test_a_name_on_a_counting_subject_is_refused() -> void:
	var problems: Array[String] = []
	assert_null(ObjectiveDef.from_dict({
		"subject": "unit", "name": "Sir Roland", "owner": "self",
		"compare": ">=", "value": 1,
	}, problems))
	assert_true(" | ".join(problems).contains("named_unit"),
			"the message names the subject they meant: %s" % [problems])


func test_the_name_rides_the_wire() -> void:
	var problems: Array[String] = []
	var o := ObjectiveDef.from_dict({
		"subject": "named_unit", "name": "Sir Roland", "owner": "self",
		"compare": "==", "value": 0, "output": "lose",
	}, problems)
	assert_not_null(o)
	if o == null:
		return
	var back := ObjectiveDef.from_wire(o.to_dict())
	assert_eq(back.unit_name, &"Sir Roland")
	assert_eq(back.subject, ObjectiveDef.Subject.NAMED_UNIT)


## ⚠️ **WITHOUT THIS BRANCH THE TRACKER DRAWS A ROW ABOUT A PERSON AS A ROW ABOUT AN ARMY.** `id`
## is empty on every named-unit row, and `describe()`'s default word is "units".
func test_a_named_row_describes_itself_as_the_person() -> void:
	var problems: Array[String] = []
	var o := ObjectiveDef.from_dict({
		"subject": "named_unit", "name": "Sir Roland", "owner": "self",
		"compare": ">=", "value": 1,
	}, problems)
	assert_not_null(o)
	if o == null:
		return
	assert_true(o.describe().contains("Sir Roland"), o.describe())


# ── counting him, which is the whole distinction ───────────────────────────

func _count(w: SimWorld, name: String) -> int:
	var problems: Array[String] = []
	var o := ObjectiveDef.from_dict({
		"subject": "named_unit", "name": name, "owner": "self",
		"compare": ">=", "value": 1,
	}, problems)
	if o == null:
		fail("fixture row refused: %s" % [problems])
		return -99
	return ObjectiveSystem._count(w, o, {}, {}, [1] as Array[int])


func test_a_living_hero_counts_one() -> void:
	var w := _world_with([{"def_id": HERO, "name": "Sir Roland"}])
	assert_true(w.named_units.has(&"Sir Roland"), "%s" % [w.named_units.keys()])
	assert_eq(_count(w, "Sir Roland"), 1)


## ⛔ **0 HAS TO BE A REAL ANSWER, because "protect Sir Roland" is `== 0, output: lose` and its
## whole point is the tick he dies.**
func test_a_dead_hero_counts_zero_rather_than_becoming_unmeasurable() -> void:
	var w := _world_with([{"def_id": HERO, "name": "Sir Roland"}])
	var hero := _named(w, &"Sir Roland")
	assert_not_null(hero)
	if hero == null:
		return
	hero.take_damage(hero.hp, 0, SimEntity.NO_ATTACKER)
	assert_false(hero.alive, "fixture: he has to actually die")
	assert_eq(_count(w, "Sir Roland"), 0, "dead is a count of nobody, not a refusal to count")
	# AND THE NAME IS STILL DECLARED, which is the only reason the 0 above is trustworthy.
	assert_true(w.named_units.has(&"Sir Roland"))


## ⛔ **AND A NAME THE MAP NEVER DECLARED IS -1 AND NOT 0**, which is `_count`'s *"-1, never 0"*
## rule: `== 0` against a nobody would otherwise defeat the player before they had moved.
func test_a_name_nobody_carries_is_unmeasurable_rather_than_zero() -> void:
	var w := _world_with([{"def_id": HERO, "name": "Sir Roland"}])
	assert_eq(_count(w, "Sir Rolande"), -1, "a near miss must not read as 'he is dead'")
	assert_eq(_count(w, "Nobody At All"), -1)


## ⚠️ **THE OWNER AXIS STILL APPLIES.** A hero of the enemy's is not a hero of yours, and a row
## that counted both would make *"protect Sir Roland"* satisfiable by the opponent's hero.
func test_a_hero_is_counted_for_whoever_owns_him() -> void:
	var w := _world_with([{"def_id": HERO, "name": "Sir Roland", "player": 2}])
	assert_eq(_count(w, "Sir Roland"), 0, "player 1 does not have him")


## A world reused between matches must not keep the last scenario's heroes — `setup()` clears the
## set for `areas`' reason, and without it a skirmish could measure a map nobody is playing.
func test_a_reused_world_forgets_the_last_scenarios_heroes() -> void:
	var w := _world_with([{"def_id": HERO, "name": "Sir Roland"}])
	assert_true(w.named_units.has(&"Sir Roland"))
	var cfg := MatchConfig.new()
	cfg.player_ids = [1, 2]
	cfg.teams = [0, 0]
	cfg.map_size = Vector2i(48, 48)
	w.setup(cfg)
	assert_true(w.named_units.is_empty(), "%s" % [w.named_units.keys()])


## ⛔ **A HERO BELONGING TO A PLAYER THIS MATCH HAS NOT GOT IS UNMEASURABLE, NOT DEAD.**
##
## `build_from` skips an entity whose player index is past the match's size — *"a 4-player map in a
## 2-player match"* — and the name is declared AFTER that skip, deliberately. The alternative was
## declaring it first, and it is worse in a way that is easy to miss: the hero would then be
## **measurable and absent**, so `named_unit == 0, output: lose` would defeat the human on tick 1
## because somebody else's hero is not in a match he was never in.
##
## -1 makes such a scenario merely unwinnable, which is the safe direction this vocabulary keeps
## choosing, and it matches what the skip already means: that entity is not part of this match.
func test_a_hero_of_a_player_this_match_has_not_got_is_unmeasurable() -> void:
	var w := _world_with([
		{"def_id": HERO, "name": "Ours", "player": 1},
		{"def_id": HERO, "name": "Theirs", "player": 4},
	])
	assert_true(w.named_units.has(&"Ours"))
	assert_false(w.named_units.has(&"Theirs"),
			"player 4 is not in a 2-player match: %s" % [w.named_units.keys()])
	assert_eq(_count(w, "Theirs"), -1, "unmeasurable, and emphatically not 'he is dead'")
