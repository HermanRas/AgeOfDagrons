## Decides when a match is over and who won (PLAN.md 11.1). Writes exactly three
## things and nothing else: `SimPlayer.defeated`, `SimWorld.match_over` and
## `SimWorld.winner_id`. All three ride the snapshot, so the result screen is a
## reader of sim state rather than a client-side guess -- the same division
## `ResourceHUD` keeps for the population.
##
## Runs LAST, after `PopulationSystem`, which is itself after `DeathSystem`. The
## whole tick has to have happened first: elimination is read off what is still
## alive, and a player whose last building fell THIS tick has lost as of this tick,
## not the next one. PLAN.md 5.1's tick diagram puts it in the same place.
##
## ONE OF THE THREE MODES IS BUILT. `MatchConfig.Mode` declares all three because
## the lobby (1.6/11.3) needs a list and because a mode axis with one value on it
## invites the next mode to be bolted on as a boolean. `_trophy()` and
## `_king_of_the_hill()` end no matches at all, and each says what it is still
## missing -- the safe direction to be unfinished in. The unsafe direction is a
## half-built rule: "you lose when your trophy is gone" evaluated on a map with no
## trophies on it defeats everybody on tick 1.
##
## Once `match_over` is set nothing here runs again, so a result cannot be
## overwritten by the corpses and rubble settling in the seconds after it.
class_name WinConditionSystem
extends SimSystem

## King of the Hill: the score to reach, and how big the contested zone is.
## PLACEHOLDER -- see `_king_of_the_hill()`. Here rather than in `MatchConfig`
## because they are rules, not per-match settings; the zone's PLACE on the map is
## the part that will have to become map data.
const KOTH_TARGET_SCORE := 1000
const KOTH_ZONE_RADIUS_TILES := 6

## Trophy: what losing loses you. PLACEHOLDER -- see `_trophy()`. `unit.dragon` is
## the nearest thing that exists in units.json; the mode wants the BABY dragon of
## PLAN.md 13.2, which has no def, no bake and no way onto a map.
const TROPHY_DEF_ID := &"unit.dragon"


func process_tick(w: SimWorld) -> void:
	if w.match_over:
		return
	match w.mode:
		MatchConfig.Mode.LAST_MAN_STANDING:
			_last_man_standing(w)
		MatchConfig.Mode.TROPHY:
			_trophy(w)
		MatchConfig.Mode.KING_OF_THE_HILL:
			_king_of_the_hill(w)


## Own nothing and you are out; the last player left wins (PLAN.md 11.1's
## conquest mode). The only mode that decides anything today, and the one the
## debug map is set up for: the skirmish opponent owns two soldiers, so killing
## both of them wins the match.
##
## A ONE-PLAYER WORLD IS NEVER DECIDED. "Last man standing" is trivially true of
## somebody with no opponents, and `MatchConfig.debug_single_player()` plus most of
## the test suite is exactly that -- declaring victory on tick 1 of a solo sandbox
## would be technically correct and useless. Two players is the floor for a match
## that can be won.
func _last_man_standing(w: SimWorld) -> void:
	if w.players.size() < 2:
		return
	if not _world_is_populated(w):
		return

	# ONE pass for every player, not `_owns_anything()` per player. Per-player was
	# O(players x entities), which on an 8-player generated map is eight walks of a
	# thousand entities every tick -- part of the same measurement that caught
	# VisionSystem's full-grid decay.
	var owners := _owners_with_anything(w)
	var standing: Array[int] = []
	for p in w.players:
		# `not p.defeated` is what makes RESIGNING mean anything (12.1e). Owning something
		# used to be the whole test, so a player who conceded -- or whose device vanished,
		# which `Net` turns into the same command -- went on counting as standing while
		# their abandoned base sat there, and the match could never resolve. Safe to read
		# here precisely because the flag is one-way: it is set below and by
		# `ResignCommand`, and never cleared by anything.
		if owners.has(p.id) and not p.defeated:
			standing.append(p.id)
		else:
			# ONE WAY ONLY, never cleared. A player with no units and no buildings
			# cannot build, train or gather, so there is no path back -- and a flag
			# that could flicker off would take the defeat screen with it.
			p.defeated = true

	if standing.size() > 1:
		return

	w.match_over = true
	# 0 when the last two fell on the SAME tick: a draw. Barely reachable in play
	# (it needs simultaneous mutual annihilation) but reachable instantly in a test
	# that steps a world with no entities in it, and the alternative is a match
	# flagged as over with a winner nobody can name.
	w.winner_id = standing[0] if standing.size() == 1 else 0


## Whether there is a match here to decide at all: does the world hold anybody's
## unit or building, ALIVE OR DEAD.
##
## `SimWorld.setup()` allocates an empty grid and `MapGen` fills it afterwards, so
## an empty world is one that has not been stood up yet -- which is also what every
## sim test and harness that skips MapGen is working with. Read literally, an empty
## world is every player eliminated on tick 1 and a match drawn before the first
## order, and `match_over` latching means that verdict would then stick for the rest
## of the run.
##
## DEAD COUNTS, and that is what keeps the guard from swallowing a real result. When
## the last two players annihilate each other, their corpses (4.7) and rubble (5.5)
## are still in `entities` for up to a minute -- so on the tick it happens this is
## still true, the draw below is recorded, and nothing after it is evaluated. The
## only way past this guard is entities leaving the world without dying first, which
## is `despawn()` called by hand.
static func _world_is_populated(w: SimWorld) -> bool:
	for e in w.entities.values():
		if e is SimUnit or e is SimBuilding:
			return true
	return false


## True while `player_id` still has a unit or a building.
##
## ALIVE, not merely present: a corpse (4.7) and rubble (5.5) stay in `entities`
## for up to a minute after they fall, and a player whose last building is
## smouldering has lost -- the same `alive` filter `PopulationSystem` counts by.
##
## A FOUNDATION COUNTS. It is a building the player owns, it holds ground, and any
## villager they have left can still raise it. `PopulationSystem` excludes
## foundations from the pop CAP, which is a different question -- what a building
## provides, versus whether the player is still in the game.
##
## Resource nodes are excluded by TYPE rather than by owner. They carry owner_id 0
## today, so an owner check would happen to work; keying off the type instead means
## a mode that ever gives nodes a real owner (a claimed dragon nest, 13.2) cannot
## accidentally keep a wiped-out player alive on the strength of a berry bush.
static func _owns_anything(w: SimWorld, player_id: int) -> bool:
	return _owners_with_anything(w).has(player_id)


## The set of owner ids with at least one living unit or building, in one pass. See
## `_owns_anything()` above for what counts and why.
static func _owners_with_anything(w: SimWorld) -> Dictionary:
	var owners: Dictionary = {}
	for e in w.entities.values():
		if not e.alive:
			continue
		if e is SimUnit or e is SimBuilding:
			owners[e.owner_id] = true
	return owners


## PLACEHOLDER (11.2). Every player would start with a baby dragon and lose the
## moment it dies -- regicide with a nicer mascot.
##
## Deliberately decides nothing, because the piece it needs is not a rule but a
## UNIT. It wants:
##
##   1. A `unit.dragon_baby` def (units.json) -- PLAN.md 13.2 describes it as what
##      hatches from a claimed nest on a 360 s timer, so the mode and the nest want
##      the same new unit.
##   2. `MapGen` giving one to every player at their start position, which the debug
##      map cannot do for a second player at all: it has ONE start position, and
##      everyone after the first gets the skirmish squad instead (2.4b is where real
##      per-player starts live).
##   3. A `is_trophy` flag or a config field naming the def, so the rule reads
##      "lose your trophy" rather than hardcoding a unit id in a system.
##
## Until then this is inert on purpose. The rule itself is four lines -- defeated
## when `_owns_none_of(TROPHY_DEF_ID)` -- and running those four lines today would
## defeat every player on tick 1, since nobody has a dragon to lose.
func _trophy(_w: SimWorld) -> void:
	pass


## PLACEHOLDER (11.2). A zone on the map, ringed on the minimap; whoever has the
## most units inside it scores each tick, and the first to KOTH_TARGET_SCORE wins.
##
## Deliberately decides nothing. What it needs, in the order it needs it:
##
##   1. WHERE THE ZONE IS. That is map data, not a rule -- it belongs beside the
##      start positions in `MapGen`/`SimMap`, and a hill hardcoded at the centre of
##      the debug map would be a promise this system cannot keep for any other map.
##      `KOTH_ZONE_RADIUS_TILES` is the shape; the centre is the missing half.
##   2. A per-player score on `SimPlayer`, in `state_hash()` and the snapshot. NOT
##      added yet, on purpose: an unwritten field that reaches the HUD is precisely
##      the hole 4.11's counter was, and one field nothing writes is how it starts.
##   3. The minimap ring (view side, `Minimap`). A scored zone the player cannot see
##      is a rule they can only lose to.
##
## The scoring rule itself is the easy part and is worth stating so it is not
## re-litigated: MOST units in the zone scores, not merely presence, so a contested
## hill pays nobody and one unit is enough to hold an empty one.
func _king_of_the_hill(_w: SimWorld) -> void:
	pass
