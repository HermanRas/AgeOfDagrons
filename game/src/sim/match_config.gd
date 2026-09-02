## What SimWorld.setup() needs to stand up a match: which players exist, what
## colour each of them is, and how big the map is. Colour, not faction: v1 is one
## shared civilisation (PLAN.md 1), and a faction picker only arrives with 9.5.
## Win conditions join this at the lobby (1.6), which is also what will fill
## `colours` from a picker rather than from a debug factory below;
## the actual terrain layout is 2.4a's job, not this class's -- `map_size` only
## says how much grid to allocate.
class_name MatchConfig
extends RefCounted

## How the match is won (PLAN.md 11.1/11.2). Chosen in the lobby once 1.6/11.3
## exist; until then every match is the default.
##
## TWO OF THE FOUR ARE IMPLEMENTED. Trophy and King of the Hill are declared here
## so the mode is a real axis rather than a boolean, and so the lobby has a list to
## show -- `WinConditionSystem` documents exactly what each of them still needs, and
## deliberately never ends a match in either. A mode that half-works would end
## matches for reasons the player cannot see; one that does nothing leaves a
## sandbox, which is what the debug map already is.
##
##   LAST_MAN_STANDING  own no units and no buildings and you are out; last
##                      player left wins. The classic conquest rule.
##   TROPHY             every player starts with a baby dragon; lose it and you
##                      are out.
##   KING_OF_THE_HILL   hold a zone on the map with more units than anybody else
##                      to score; first to WinConditionSystem.KOTH_TARGET_SCORE
##                      wins.
##   SCENARIO           an authored objective list decides it (15.2). Won by
##                      `objectives` below; LOST by elimination like every other
##                      mode, which is the half of conquest a scenario keeps.
##
## ⚠️ **`SCENARIO` IS APPENDED, NOT INSERTED, AND THAT IS A WIRE RULE.** `mode`
## travels as an int in `to_dict()` and is read back by `from_dict()`, so inserting a
## member would renumber TROPHY and KING_OF_THE_HILL and silently reinterpret every
## recorded config and every beacon row already in flight. New modes go on the end.
##
## **IT IS NOT A LOBBY CHOICE, and `SkirmishScreen` deliberately does not offer it.**
## That picker lists the three by name rather than iterating this enum, so adding a
## member here does not add a row there -- which is what should happen: a scenario's
## win condition comes out of `scenario.json`, and a Victory dropdown offering
## "Scenario" would be offering a mode with no objectives behind it, which is a match
## that can be lost and never won.
enum Mode { LAST_MAN_STANDING, TROPHY, KING_OF_THE_HILL, SCENARIO }


## A mode's name for a player to read (the skirmish screen, 1.6/11.3). Spelled out
## rather than derived from the enum name, so renaming a member is a change you make
## here too, in front of you, instead of silently retitling a menu entry.
static func mode_name(mode: Mode) -> String:
	match mode:
		Mode.TROPHY: return "Trophy"
		Mode.KING_OF_THE_HILL: return "King of the Hill"
		# Named for the RESULT SCREEN and the LAN beacon, not for a picker: nothing offers
		# this mode as a choice (see the enum). A beacon row for a hosted scenario would
		# otherwise show a blank rule, and "Last Man Standing" -- the old fallback -- would
		# be an outright wrong one.
		Mode.SCENARIO: return "Scenario"
		_: return "Last Man Standing"

## Deliberately small. PLAN.md 10's MVP is "one small map on a phone", and an 8x8
## town centre plus 5 villagers on 64x64 tiles is already a generous settlement's
## worth of room. 2.4b scales size with player count.
const DEBUG_MAP_SIZE := Vector2i(64, 64)

var player_ids: Array[int] = []
var map_size: Vector2i = DEBUG_MAP_SIZE

## PLAN.md 11.1. Part of the config for the same reason `colours` is: every
## client builds its own world (2.4a), and two of them running different victory
## rules would disagree about whether the match is over -- which `state_hash()`
## now catches, because the outcome is folded into it.
var mode: Mode = Mode.LAST_MAN_STANDING

## The map to play on (PLAN.md 2.4b), or null for the fixed debug map.
##
## Carried as DATA rather than as a seed plus a type, and that is deliberate. A seed
## only reproduces a map through the exact generator that made it, so a config holding
## one would silently mean a different map after any generator change -- and, worse,
## host and client would each run `FastNoiseLite` on different CPUs. The map travels
## as the map. `seed`/`map_type` below are kept alongside it as PROVENANCE, for the
## skirmish screen to display and for Re-generate to work from.
var map_data: MapData = null
var seed: int = 0
var map_type: MapGenerator.Type = MapGenerator.Type.RANDOM

## WHICH AGE EVERY PLAYER STARTS IN (project owner, 2026-08-30). 1 is the ladder from
## the bottom, which is what every match played before this existed and what every
## debug factory still wants.
##
## ONE NUMBER FOR EVERYBODY, not one per slot, and the owner asked for it that way --
## *"a starting age selector for all players"*. That is also the only version that is
## obviously fair: an age is a flat multiplier on what you may build and train, so a
## per-slot version is a handicap system, and a handicap system wants to be designed
## rather than fall out of a dropdown.
##
## IT IS PART OF THE CONFIG FOR `mode` AND `colours`' REASON. Every client builds its
## own world (2.4a) from these bytes, and two of them starting players in different
## ages would disagree about what is buildable, what a building's population cap is,
## and which skin every sprite wears -- and `age` IS folded into `state_hash()`, so
## this one would be caught, as a desync at tick 1 with no explanation attached.
##
## What it does NOT do is give you an age-3 town: `MapGen` still places one town
## centre and the starting villagers, because starting buildings are the MAP's business
## and not the age's. It unlocks the ladder, which is what an age is.
var starting_age: int = 1

## WHAT THIS HOST IS CALLED, for the server browser (2026-08-31).
##
## **THE ONE FIELD DISCOVERY NEEDED THAT NOTHING HAD.** Until this existed a host was an
## IP address, and a browser listing four addresses is a browser nobody can choose from.
##
## PROVENANCE, LIKE `seed` AND `map_type`, NOT SIMULATION. Nothing in `src/sim/` reads
## it, it is not in `state_hash()`, and two clients disagreeing about it changes nothing
## about the match -- which is precisely why it may live here: `to_dict()` is the one
## description of a session that already travels to both the lobby and the beacon, and a
## second channel carrying the host's name is a second thing that can say something
## different from the first.
##
## EMPTY IS LEGAL and means "nobody typed one", which is every debug factory, every test
## fixture and every config recorded before this existed. `LanBeacon.default_host_name()`
## is what the lobby fills it with; a browser showing an empty name falls back to the
## address, which is what a host was called before.
var host_name: String = ""

## Which slots are bots, position for position with `player_ids` (PLAN.md 12.2a).
## EMPTY means every player is human, which is what every debug factory here wants.
## Read by `SimWorld.setup()` into `SimPlayer.is_ai`.
var ai_players: Array[bool] = []

## How hard each bot plays, position for position with `player_ids`
## (`SimPlayer.AILevel`, 2026-08-22). Only meaningful where `ai_players` is true.
##
## SHORTER THAN `ai_players` IS LEGAL and means "the rest play at the default", which
## is what every debug factory and every older recorded config wants -- none of them
## names a level and all of them should keep getting the AI they always got. That is
## also why this is a separate array rather than a widening of `ai_players`: a config
## from before difficulty existed still deserializes into exactly the match it used to.
var ai_levels: Array[int] = []

## THE AUTHORED WIN CONDITION (PLAN.md 11.8, 15.2). Empty in every other mode, which
## is every skirmish and every debug factory.
##
## ONLY READ WHEN `mode == Mode.SCENARIO`. `ScenarioDef` refuses the two ways these can
## contradict the mode -- a `scenario` with no win row can never be won, and a
## `last_man_standing` carrying objectives would have them silently ignored -- so a
## config where the two disagree cannot come from a scenario file at all.
##
## IT IS IN THE CONFIG FOR `mode`'s REASON, and rather more sharply: every client builds
## its own world (2.4a) and `ObjectiveSystem` runs in each of them, so two clients
## holding different objective lists would disagree about whether the match has been WON
## -- which is the one question the match was asked. `state_hash()` folds the outcome in,
## so it would be caught, as a desync on the tick somebody won.
var objectives: Array[ObjectiveDef] = []

## WHOSE VIEWPOINT `objectives` ARE WRITTEN FROM (15.2). 0 means nobody, which is every
## non-scenario match. `ScenarioDef.build_config` sets it to 1, the human.
##
## ## THE OBJECTIVES NEED A VIEWPOINT AND THIS IS IT
##
## `ObjectiveDef.Owner` is `self` / `enemy` / `ally` / an index, and three of those four
## are RELATIVE terms. A relative term with no viewpoint is not a rule, so the viewpoint
## is carried rather than derived.
##
## ⚠️ **DERIVING IT WOULD HAND THE TUTORIAL TO THE BOT.** The obvious derivation is "the
## first player who is not an AI", and the failure is immediate: scenario 1 is won by
## reaching ten villagers, the Passive opponent runs its whole economy and trains
## villagers from its town centre, so evaluating "self" for every player means the AI
## completes the economy lesson first and the human watches it happen. Objectives are
## evaluated for this player and nobody else.
##
## ONE INT AND NOT A LIST, deliberately. A co-op scenario does not want the objectives
## evaluated once per protagonist -- that is two separate verdicts about one shared goal
## -- it wants them evaluated once for a SIDE, which is what `Owner.ALLY` already
## expresses from this player's viewpoint ("your side owns 10 houses"). A list would look
## like it handled co-op while promising something else.
var objective_player_id: int = 0

## WHAT THE SCENARIO SAYS BEFORE THE FIRST ORDER (PLAN.md 15.6). Empty means no modal,
## which is every skirmish.
##
## PROVENANCE, LIKE `host_name`, `seed` AND `map_type` -- NOT SIMULATION. Nothing in
## `src/sim/` reads it, it is not in `state_hash()`, and two clients disagreeing about it
## changes nothing about the match. That is precisely why it may live here: `to_dict()`
## is the one description of a session that already travels to every client, and a second
## channel carrying the briefing is a second thing that can say something different from
## the first.
##
## SHARED WITH SKIRMISH BY THE OWNER'S SPEC, which is why it is on the config rather than
## reached for through `ScenarioDef`: the match HUD shows it, and the HUD has never heard
## of a campaign.
var scenario_message: String = ""

## WHICH CAMPAIGN MISSION THIS IS (PLAN.md 15.7), or `""`/-1 for a match that is not one --
## which is every skirmish and every debug factory.
##
## PROVENANCE, like `scenario_message` and `host_name`: nothing in `src/sim/` reads either,
## neither is in `state_hash()`, and two clients disagreeing about them changes nothing
## about the match.
##
## **THEY ARE HERE SO THAT WINNING CAN BE RECORDED WITHOUT THE HUD LEARNING WHAT A CAMPAIGN
## IS.** `GameScene` already detects the win -- it reads `match_over` and `winner_id` off
## the snapshot to raise `ResultScreen` -- and this is the smallest thing that lets the same
## moment write `user://campaign_progress.json`. The alternative was a second channel from
## the scenario screen to the match, which is a second thing that can disagree with the
## config about which mission is being played.
##
## BOTH, because neither is enough: the folder is the key progress is stored under and the
## index is what the completion COUNT comes from (`index + 1`).
var campaign_folder: String = ""
var scenario_index: int = -1

## WHOSE SIDE EACH PLAYER IS ON, position for position with `player_ids` (the lobby's
## team selector, 2026-08-31). Read by `SimWorld.setup()` into `SimPlayer.team`.
##
## **SHORTER OR EMPTY IS LEGAL AND MEANS A FREE-FOR-ALL**, which is what every debug
## factory, every test fixture and every recorded config from before the selector
## existed wants -- and it is why 0 rather than 1 is the "no team" value: an absent
## entry and an unaligned player are the same thing and read the same way. Same
## forward-compatibility shape as `ai_levels` above and for its reason.
##
## IT IS IN THE CONFIG FOR `colours`' AND `starting_age`'s REASON. Every client builds
## its own world (2.4a), and two of them disagreeing about who is allied with whom would
## have one player's tower shooting a unit the other's tower is protecting -- a
## divergence in hp several seconds after the cause, which is the worst kind to read.
var teams: Array[int] = []


## A generated skirmish: two players, yellow against red, on a real procedural map.
##
## The config a `Skirmish.tscn` (1.6) will build once it exists, and what the tests and
## `dev_preview` use to exercise a generated map today.
static func debug_generated(p_seed: int = 1,
		type: MapGenerator.Type = MapGenerator.Type.RANDOM, players: int = 2) -> MatchConfig:
	var c := MatchConfig.new()
	c.player_ids = []
	c.colours = []
	var palette := [&"colour.yellow", &"colour.red", &"colour.blue", &"colour.cyan",
			&"colour.green", &"colour.violet", &"colour.orange", &"colour.white"]
	for i in range(clampi(players, MapGenerator.MIN_PLAYERS, MapGenerator.MAX_PLAYERS)):
		c.player_ids.append(i + 1)
		c.colours.append(_colour(palette[i % palette.size()]))

	c.seed = p_seed
	c.map_type = type
	c.map_data = MapGenerator.generate(p_seed, type, c.player_ids.size())
	c.map_size = c.map_data.size
	return c

## Palette index (colours.json) per entry in `player_ids`, position for position.
## EMPTY means "derive from join order", which is what every player got before
## anything wanted to name its own colour, and what the lobby (1.6) will replace
## by filling this in from the picker.
##
## Part of the config rather than of SimWorld because it must be identical on
## every client: each builds its own world (2.4a), and two of them disagreeing
## about who is yellow is not a desync the state hash would ever catch -- colour
## does not enter it -- but it is the one difference players read the board by.
var colours: Array[int] = []


## THE MATCH CONFIG ON THE WIRE (PLAN.md 12.1b/d).
##
## Sent once, by the host, when a match starts: every client builds its own world from
## it (2.4a), so anything the two sides could disagree about has to be in here. That is
## why `mode` and `colours` travel -- two clients running different victory rules would
## disagree about whether the match is over, and two disagreeing about who is yellow is
## the one difference players read the board by.
##
## **The map travels as the map, not as a seed.** 2.4b's generator uses `FastNoiseLite`,
## whose float maths is not guaranteed identical between an ARM phone and an x86 desktop,
## so a host and client regenerating from a shared seed can disagree about where the
## water is -- a desync before the first order, and the one kind `state_hash()` reports
## without being able to say why. 20-40 KB once, for certainty (corrected 2026-08-17).
##
## `seed`/`map_type` ride along as PROVENANCE only, for the lobby to display and for
## Re-generate to work from; nothing rebuilds the map out of them.
func to_dict() -> Dictionary:
	return {
		"player_ids": player_ids,
		"colours": colours,
		"ai_players": ai_players,
		"ai_levels": ai_levels,
		"teams": teams,
		"map_size": {"x": map_size.x, "y": map_size.y},
		"mode": int(mode),
		"seed": seed,
		"map_type": int(map_type),
		"starting_age": starting_age,
		"host_name": host_name,
		# THE AUTHORED WIN CONDITION (15.2), already normalised. `ObjectiveDef.to_dict`
		# writes the PARSED form -- enums as ints, the comparison already decided -- so the
		# sim end never re-parses the author's `">="`: a comparison that arrived as a string
		# is a comparison two builds could disagree about.
		"objectives": _objectives_to_wire(),
		"objective_player_id": objective_player_id,
		"scenario_message": scenario_message,
		"campaign_folder": campaign_folder,
		"scenario_index": scenario_index,
		# null for the fixed debug map, which is integer code and identical everywhere.
		"map_data": map_data.to_dict() if map_data != null else null,
	}


func _objectives_to_wire() -> Array:
	var out: Array = []
	for o in objectives:
		out.append(o.to_dict())
	return out


static func from_dict(d: Dictionary) -> MatchConfig:
	var c := MatchConfig.new()

	# Rebuilt element by element rather than assigned wholesale: everything off the wire
	# is an untyped Array of Variants, and these fields are typed. Assigning one straight
	# across fails at runtime, and `ai_players` in particular would silently become an
	# array of nulls -- which reads as "nobody is a bot" and quietly turns the AI off.
	var ids: Array[int] = []
	for v in d.get("player_ids", []):
		ids.append(int(v))
	c.player_ids = ids

	var cols: Array[int] = []
	for v in d.get("colours", []):
		cols.append(int(v))
	c.colours = cols

	var bots: Array[bool] = []
	for v in d.get("ai_players", []):
		bots.append(bool(v))
	c.ai_players = bots

	# Absent on the wire from a client built before difficulty existed, which leaves
	# this empty and every bot at the default -- see the field's own note.
	var levels: Array[int] = []
	for v in d.get("ai_levels", []):
		levels.append(int(v))
	c.ai_levels = levels

	# Absent from a host built before the team selector existed, which leaves this empty
	# and every player unaligned -- a free-for-all, which is the match that host is
	# actually running. See the field's own note.
	var sides: Array[int] = []
	for v in d.get("teams", []):
		sides.append(int(v))
	c.teams = sides

	var ms: Dictionary = d.get("map_size", {})
	c.map_size = Vector2i(int(ms.get("x", DEBUG_MAP_SIZE.x)), int(ms.get("y", DEBUG_MAP_SIZE.y)))
	c.mode = int(d.get("mode", Mode.LAST_MAN_STANDING)) as Mode
	c.seed = int(d.get("seed", 0))
	c.map_type = int(d.get("map_type", MapGenerator.Type.RANDOM)) as MapGenerator.Type
	# Absent from a host built before the selector existed, which reads as age 1 -- the
	# match that host is actually running. Same forward-compatibility shape as
	# `ai_levels` above, and for the same reason.
	c.starting_age = int(d.get("starting_age", 1))
	# Absent from a host built before the browser existed, which reads as "nobody typed
	# one" -- and that is exactly what such a host is. Same forward-compatibility shape as
	# `ai_levels` and `teams` above, and for the same reason.
	c.host_name = String(d.get("host_name", ""))

	# THE AUTHORED WIN CONDITION (15.2). Absent from a host built before objectives
	# existed, which reads as an empty list -- and an empty list is exactly what every
	# match that host can run carries, because it has no SCENARIO mode to select either.
	# Same forward-compatibility shape as `ai_levels` and `teams` above.
	#
	# THROUGH `from_wire` AND NOT `from_dict`: this is the normalised form coming BACK,
	# not an author's file going in. `from_dict` validates spellings, refuses the three
	# unevaluable subjects and appends complaints -- all of which happened on the host,
	# before the config was sent. Re-running it here would mean a client could reject one
	# row of a list the host is already simulating, and then run a different rule.
	var objectives: Array[ObjectiveDef] = []
	for v in d.get("objectives", []):
		if v is Dictionary:
			objectives.append(ObjectiveDef.from_wire(v as Dictionary))
	c.objectives = objectives
	c.objective_player_id = int(d.get("objective_player_id", 0))
	# Absent means no briefing, which is every skirmish and every older recorded config.
	c.scenario_message = String(d.get("scenario_message", ""))
	# Absent means "not a campaign mission", which is what every skirmish and every config
	# recorded before 15.7 actually is. -1 rather than 0, because 0 is a real scenario index.
	c.campaign_folder = String(d.get("campaign_folder", ""))
	c.scenario_index = int(d.get("scenario_index", -1))

	var md = d.get("map_data")
	if md != null and md is Dictionary:
		c.map_data = MapData.from_dict(md)
		# The map is the authority on its own size; a config that disagreed with the
		# map it carries would build a world the wrong shape.
		c.map_size = c.map_data.size
	return c


## The MVP session model (PLAN.md 1.1): one human, hosted on loopback.
static func debug_single_player() -> MatchConfig:
	var c := MatchConfig.new()
	c.player_ids = [1]
	c.colours = [_colour(&"colour.yellow")]
	c.map_size = DEBUG_MAP_SIZE
	return c


## The debug map with a hostile on it: the local player's usual start, plus a
## second player who owns nothing but MapGen.DEBUG_ENEMY_SQUAD -- a couple of
## soldiers a short way to the right of the town centre. What it buys is
## something on screen that is not ours: enemy tint, an enemy selection panel,
## and the target combat will need once it exists (there is no AttackCommand
## yet, so today they simply stand there).
##
## Not a second BASE. Both starts would land on the same tile -- `_start_origin`
## takes no player into account and 2.4b is where real start positions live --
## and a forced overlapping town centre is a worse lie than an army with no home.
##
## YELLOW against RED because the project owner picked them, and they are the two
## the palette separates furthest by lightness after blue (colours.json's L*
## ladder). It was originally a workaround -- for a day, red and yellow were the
## only two colour bakes that were current, the other six being stale rather than
## absent and rendering perfectly happily in the wrong shape. All eight are
## correct as of the 2026-08-16 rebake, so this is now a choice rather than a
## constraint, and any pair would work.
##
## THIS IS THE ONLY CONFIG 11.1 CAN ACTUALLY DECIDE, and that is what makes the
## win condition demoable at all: two players, so Last Man Standing has somebody
## to outlast. The opponent owns two soldiers and nothing else, so killing both of
## them ENDS THE MATCH in victory -- the intended demo, and also the thing to
## remember before wondering why a long sandbox session stopped. Nothing can
## attack the local player back yet (no AI, 12.2a), so defeat is only reachable by
## debug-destroying your own town centre and villagers.
static func debug_skirmish() -> MatchConfig:
	var c := MatchConfig.new()
	c.player_ids = [1, 2]
	c.colours = [_colour(&"colour.yellow"), _colour(&"colour.red")]
	c.map_size = DEBUG_MAP_SIZE
	return c


## A palette index by name, falling back to join order (-1 is what
## SimWorld.setup reads as "no preference") if the palette has no such colour.
## The fallback is never expected to fire -- test_match_config pins both names --
## and exists so a mistyped colour costs a debug match its tint rather than its
## players.
static func _colour(id: StringName) -> int:
	return GameDataRegistry.colour_index(id) if GameDataRegistry != null else -1
