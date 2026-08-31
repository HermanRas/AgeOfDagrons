## Gaia animals that come at you (PLAN.md 4.13's hostile wolf, 6.1b's roaming).
##
## THIS IS THE ONLY AUTO-ACQUIRE IN THE GAME, and `CombatSystem`'s header rules the
## behaviour out in as many words -- "a unit fights what it was ORDERED to fight and
## nothing else". That rule is about PLAYER units and the reason it exists is that
## guessing on the player's behalf means every villager charging the first enemy who
## walks past. Nobody is playing the wolf. Its whole character is that it decides, so
## the thing 4.12 must not do for a swordsman is the only thing this has to do at all.
##
## It writes ONE field and then gets out of the way: `set_task_attack`, exactly as
## `AttackCommand.apply` would. Everything after that -- walking, standing at reach,
## striking on cooldown, re-acquiring when the target dies -- is `CombatSystem` doing
## what it already did, with no idea that nobody ordered this. That is why the hostile
## wolf needed no new combat code, only a new way into it.
##
## Ordering: before `CombatSystem` in `SimWorld.setup()`, so a wolf that picks a target
## bites on the same tick rather than a tick later.
class_name WildlifeSystem
extends SimSystem

## Ticks between scans. A wolf is not a targeting computer, and this runs a rect query
## per animal -- at 10 ticks/sec, twice a second is far quicker than anything can walk
## out of an aggro radius and an eighth of the work of doing it every tick.
const THINK_INTERVAL_TICKS := 5


## How long a frightened animal runs before it stops and looks around (6.1b).
##
## A BURST RATHER THAN AN ESCAPE, and that is the whole balance of hunting. A deer that
## outran its pursuer forever would be a food source that is not one; a deer that never
## gained ground would be scenery with extra steps. Running in bursts means a villager
## loses distance while it bolts and takes it back in the pause, so a hunt converges --
## slowly, and only if you commit more than one villager to it.
const FLEE_TICKS := 40

## How far it tries to get, in tiles, per burst.
const FLEE_DISTANCE := 7

## Ticks between wandering somewhere new, once settled. Deliberately long: an animal
## repathing every few ticks would eat PathService's per-tick budget (4.2) and visibly
## stall the villagers' own orders, which is the cost `CombatSystem._close_in` documents
## at length for exactly the same reason.
const ROAM_INTERVAL_TICKS := 90


## HOW CLOSE A PREDATOR MAY COME TO A BUILDING BEFORE IT TURNS AND LEAVES, in tiles
## (project owner, 2026-08-28: *"if a wolf, bear, boar gets within 15 tiles of a building
## it should retreat to a random spot opposite direction from the building and reset
## agro, so early game the player can manually run villagers back town to save them"*).
##
## **THIS IS A BALANCE FIX WEARING A BEHAVIOUR FIX'S CLOTHES, and the report says why:
## "at this stage 1 wolf eats 4 villagers before they get to kill it".** A wolf is 20
## damage against a 30 hp villager who deals 3, so a villager loses that fight in two
## bites and takes ten to win it. Nothing was wrong with the numbers; what was missing
## was the OUT. In every RTS the answer to a wolf is to run home, and there was no home
## to run to -- `_hunt` re-acquires the moment `CombatSystem` drops the task, so a wolf
## chased a fleeing villager into the town centre and kept eating.
##
## So the settlement is the sanctuary, and it is expressed as ground rather than as a
## rule about the villager: the predator leaves, whoever it was chasing. That also makes
## it legible from outside -- a player can see the wolf turn around, which they could not
## if this were a hidden modifier on the chase.
##
## 15 TILES IS A LONG WAY, and deliberately so at this radius: a town centre is 4x4 and
## `MapGenerator.START_CLEARANCE` is 6, so 15 covers the whole opening base and a good
## margin of the ground its villagers work. Measured from the FOOTPRINT, so a castle's
## sanctuary is 15 tiles beyond its 7x7 rather than 15 from its middle.
const SETTLEMENT_RADIUS := 15

## How far PAST the sanctuary edge it walks, so arriving does not immediately trip the
## check again and leave the animal shuffling on the boundary forever.
const RETREAT_CLEARANCE := 5

## How long the retreat runs before the animal settles and looks around. Longer than
## `FLEE_TICKS` because it is a longer journey -- up to `SETTLEMENT_RADIUS +
## RETREAT_CLEARANCE` tiles rather than 7 -- and the retreat is only over when it has
## actually got somewhere.
const RETREAT_TICKS := 80

## How far off dead-opposite the retreat may aim, in radians. The owner asked for a
## RANDOM spot opposite the building, and the randomness earns its place: a pack that all
## ran along the same ray would re-converge and arrive as a wall, and a wolf driven off
## twice from the same corner would retrace exactly the same line both times.
const RETREAT_SPREAD_RAD := 0.9

## How many angles a retreat tries before giving up for this think. `_walk_to` refuses a
## tile that is out of bounds or in the sea, and a coastal settlement pushes half the arc
## into the water.
const RETREAT_ATTEMPTS := 4


func process_tick(w: SimWorld) -> void:
	# Sorted, because every decision below has to be identical on every machine running
	# this sim -- the same reason `AISystem` and `CombatSystem._reacquire` sort. Two
	# hosts disagreeing about where a deer ran is a desync.
	var ids := w.entities.keys()
	ids.sort()
	for id in ids:
		var e: Variant = w.entities.get(id)
		if not (e is SimUnit):
			continue
		var u := e as SimUnit
		if not u.alive or u.owner_id != 0:
			continue
		var def := w.unit_def(u.def_id)
		if def == null or not def.is_wildlife:
			continue
		_tick_animal(w, u, def)


## COUNTERS EVERY TICK, DECISIONS EVERY FIFTH. Fleeing has to be checked at full rate:
## its trigger is a drop in hp, and at one look in five a deer shot four times between
## looks would notice only one of them -- and a hit landing the tick after a look would
## leave the animal grazing for half a second with an arrow in it.
func _tick_animal(w: SimWorld, u: SimUnit, def: UnitDef) -> void:
	# Claimed on the first tick it is seen rather than lazily inside `_roam`, so that
	# "where does this animal consider home" has an answer from the start -- a bolt can
	# move it, and moving it from the (-1, -1) sentinel would mean nothing.
	if u.roam_home == Vector2i(-1, -1):
		u.roam_home = u.tile()
	if u.roam_cooldown > 0:
		u.roam_cooldown -= 1

	if _check_flee(w, u, def):
		return
	if u.flee_ticks > 0:
		u.flee_ticks -= 1
		if u.flee_ticks == 0:
			# RELOCATE, which is the second half of 6.1b's own name. Wherever the bolt
			# ended is home now, so a herd that gets hunted moves off rather than
			# drifting back to the clearing it was shot in.
			u.roam_home = u.tile()
			u.roam_cooldown = ROAM_INTERVAL_TICKS
		return

	if w.tick % THINK_INTERVAL_TICKS != 0:
		return

	# BEFORE `_hunt`, and that ordering is the whole fix. `_hunt` leaves an animal that
	# is already in a fight alone -- deliberately, so it does not oscillate between two
	# villagers -- so a check placed after it would never be reached by the wolf that
	# matters, the one already eating somebody in your town.
	if _check_settlement_retreat(w, u, def):
		return
	if def.aggro_radius > 0 and _hunt(w, u, def):
		return
	_roam(w, u, def)


## Start a bolt if this animal has just been hurt. True only when it STARTED one.
##
## NOT "true while it is running", which is what this said first and cost a test. The
## caller returns early on true, so reporting an ongoing bolt here short-circuited the
## very block that counts `flee_ticks` down -- and a deer hit once ran until something
## killed it, forever, never settling and never relocating.
##
## BY WATCHING HP rather than by being told. `SimEntity.take_damage` is handed a number
## and no attacker -- `CombatSystem` does not pass one -- so plumbing "who hit me"
## through it would mean changing the one call every damage source in the game shares,
## for one animal's benefit. A drop in hp is the same information for the price of a
## field, and it catches damage from sources that will never have an attacker at all.
func _check_flee(w: SimWorld, u: SimUnit, def: UnitDef) -> bool:
	var was := u.last_hp
	u.last_hp = u.hp
	if not def.flees:
		return false
	if was < 0 or u.hp >= was:
		return false
	# Hurt. Run directly away from whatever is nearest -- or just run, if whatever hit
	# it is beyond looking distance, because an animal shot by an archer it cannot see
	# still bolts.
	var threat := _nearest_threat(w, u)
	var away := u.tile() - threat if threat != Vector2i(-1, -1) else Vector2i.ONE
	if away == Vector2i.ZERO:
		away = Vector2i.ONE
	u.flee_ticks = FLEE_TICKS
	_walk_to(w, u, u.tile() + _scaled(away, FLEE_DISTANCE))
	return true


## Turn a predator around and send it out of the settlement it has wandered into. True
## when it did, in which case this tick is over: the animal is retreating and is not
## picking a fight on the way.
##
## PREDATORS ONLY (`aggro_radius > 0`), which is the same test `CombatSystem._is_at_war_with`
## uses to decide which animals a tower shoots. A deer grazing beside your granary is not a
## problem anybody has, and driving the herds off the map would take the food with them.
##
## **IT CLEARS THE TASK RATHER THAN JUST WALKING AWAY** -- `u.stop()` is the "reset agro"
## half of the request, and without it `CombatSystem` would keep the wolf's target and
## `_close_in` would walk it straight back. The retreat then rides `flee_ticks`, which
## already means "do not think, you are busy running": it makes the animal ignore
## `_hunt` for the whole journey, plays the `run` clip through `AnimationSystem`, and on
## expiry relocates `roam_home` to wherever it ended up -- so the wolf takes up residence
## outside rather than drifting back to the clearing it was driven out of. Three
## behaviours reused for one line each; none of them needed a flag saying which kind of
## running this is.
func _check_settlement_retreat(w: SimWorld, u: SimUnit, def: UnitDef) -> bool:
	if def.aggro_radius <= 0:
		return false
	var home := _nearest_settlement(w, u)
	if home == Vector2i(-1, -1):
		return false

	u.stop()
	u.flee_ticks = RETREAT_TICKS

	var away := Vector2(u.tile() - home)
	# Standing dead on the centre of a building is not reachable, but a tie in integer
	# tiles is: a diagonal is as good a way out as any other and beats normalising (0, 0).
	if away == Vector2.ZERO:
		away = Vector2.ONE
	away = away.normalized()
	var reach := float(SETTLEMENT_RADIUS + RETREAT_CLEARANCE)

	# Deterministic by construction rather than by a shared generator -- the same
	# argument `_roam` spells out: the order animals think in is "however many happened
	# to be alive", so a seeded rng would shift on one machine the moment a deer died a
	# tick earlier on it.
	var h := _hash(u.id * 2246822519 + w.tick)
	for attempt in range(RETREAT_ATTEMPTS):
		var spread := (float((h >> (attempt * 5)) % 1000) / 1000.0 - 0.5) * RETREAT_SPREAD_RAD
		var dir := away.rotated(spread)
		var dest := home + Vector2i(dir * reach)
		if _walk_to(w, u, dest):
			u.roam_home = dest
			return true
	# Nowhere to go -- pinned against the map edge or the sea. It still stopped and
	# still will not hunt for `RETREAT_TICKS`, which is the half of this that matters.
	return true


## The nearest tile of a player's building within `SETTLEMENT_RADIUS`, or (-1, -1).
##
## ANY player's and any phase's. A foundation is a claim on ground with villagers
## standing on it, which is exactly the situation this protects, and "whose building"
## cannot matter to an animal -- `Diplomacy` is not consulted anywhere here for the same
## reason a wolf does not take sides.
##
## Gaia's own structures are excluded by `owner_id == 0`, which today means nothing at
## all: there are none. It is there so that the day a map carries ruins or a neutral
## market, they do not silently become wolf sanctuaries.
##
## Lowest id breaks a tie, as everywhere else in this file -- determinism, not fairness.
func _nearest_settlement(w: SimWorld, u: SimUnit) -> Vector2i:
	var here := u.tile()
	var span := SETTLEMENT_RADIUS * 2 + 1
	var rect := Rect2i(here - Vector2i(SETTLEMENT_RADIUS, SETTLEMENT_RADIUS),
			Vector2i(span, span))

	var best := Vector2i(-1, -1)
	var best_gap := 1 << 30
	var best_id := 0
	for e in w.entities_in_rect(rect):
		if not (e is SimBuilding) or not e.alive or e.owner_id == 0:
			continue
		var b: SimBuilding = e
		# From the FOOTPRINT, so a castle's sanctuary is measured from its wall and not
		# from a point three tiles inside it. Same call the towers use to decide reach.
		var gap := CombatSystem.tile_gap(here, b.footprint_rect())
		if gap > SETTLEMENT_RADIUS:
			continue          # the rect is square; the radius is meant to be too
		if best_id != 0 and (gap > best_gap or (gap == best_gap and int(b.id) > best_id)):
			continue
		best_gap = gap
		best_id = int(b.id)
		best = b.tile()
	return best


## Pick a fight if there is one within reach. True if it did, or is already in one.
func _hunt(w: SimWorld, u: SimUnit, def: UnitDef) -> bool:
	# ALREADY BUSY IS LEFT ALONE. A wolf mid-chase must not re-target every five ticks
	# onto whoever is momentarily nearest, or it oscillates between two villagers and
	# reaches neither. `CombatSystem` drops it back to IDLE when its target dies or
	# gets away, and that is when this looks again.
	if u.task == SimUnit.Task.ATTACK and w.get_entity(u.task_target_id) != null:
		return true
	var prey := _nearest_prey(w, u, def.aggro_radius)
	if prey == 0:
		return false
	var tile: Vector2i = w.get_entity(prey).tile()
	u.set_task_attack(prey, tile)
	# The path request is not optional, for the reason `CombatSystem._reacquire` spells
	# out at length: `set_task_attack` raises `path_pending`, `_close_in` reads that as
	# "already on the way", and a wolf that skipped it would stand and stare from three
	# tiles off forever.
	if w.paths != null:
		w.paths.request(u.id, tile)
	return true


## Wander somewhere new within `roam_radius` of home, if it is idle and due.
func _roam(w: SimWorld, u: SimUnit, def: UnitDef) -> void:
	if def.roam_radius <= 0:
		return
	if u.task != SimUnit.Task.IDLE or u.roam_cooldown > 0 or u.path_pending:
		return

	# DETERMINISTIC BY CONSTRUCTION, not by sharing a generator. A seeded rng would work
	# only while every host drew from it in the same order, and the order here is
	# "however many animals happened to be alive and idle" -- so one deer dying a tick
	# earlier on one machine would shift every subsequent roll on it. Hashing the id and
	# the tick has no order to get wrong.
	var h := _hash(u.id * 2654435761 + w.tick)
	var angle := float(h % 3600) / 3600.0 * TAU
	var radius := 1.0 + float((h >> 12) % maxi(1, def.roam_radius))
	u.roam_cooldown = ROAM_INTERVAL_TICKS
	_walk_to(w, u, u.roam_home + Vector2i(Vector2(cos(angle), sin(angle)) * radius))


## Send it walking, if the tile is somewhere it could actually stand. An animal that
## asked for a route into the sea would sit with `path_pending` raised and never roam
## again, since `_roam` skips anything already waiting on a path.
##
## Returns whether it took, which `_check_settlement_retreat` uses to try another angle:
## a settlement on a shoreline puts half the arc out of a wolf's reach.
func _walk_to(w: SimWorld, u: SimUnit, tile: Vector2i) -> bool:
	if w.paths == null:
		return false
	if not w.map.in_bounds(tile) or not w.map.is_passable(tile, u.domain):
		return false
	u.set_task_move(tile)
	w.paths.request(u.id, tile)
	return true


## Where the nearest thing worth running from is standing, or (-1, -1).
##
## A WIDER LOOK THAN `aggro_radius`, and prey has no aggro radius at all -- this is the
## only distance a deer knows. A deer that noticed an attacker only once it was on the
## next tile would already be dead.
func _nearest_threat(w: SimWorld, u: SimUnit) -> Vector2i:
	var span := FLEE_DISTANCE * 2 + 1
	var rect := Rect2i(u.tile() - Vector2i(FLEE_DISTANCE, FLEE_DISTANCE),
			Vector2i(span, span))
	var best := Vector2i(-1, -1)
	var best_gap := 1 << 30
	var best_id := 0
	for e in w.entities_in_rect(rect):
		if not (e is SimUnit) or not Diplomacy.is_enemy(e, u.owner_id, w.teams):
			continue
		var gap := CombatSystem.tile_gap(u.tile(), Rect2i(e.tile(), Vector2i.ONE))
		# Lowest id breaks a tie, as everywhere else here: determinism, not fairness.
		if best_id == 0 or gap < best_gap or (gap == best_gap and int(e.id) < best_id):
			best_gap = gap
			best_id = int(e.id)
			best = e.tile()
	return best


## `v` pointing the same way but about `length` tiles long. Integer, so a diagonal comes
## out slightly longer than a straight run, which nothing here cares about.
static func _scaled(v: Vector2i, length: int) -> Vector2i:
	var f := Vector2(v).normalized() * float(length)
	return Vector2i(roundi(f.x), roundi(f.y))


## A cheap integer scramble. It only has to be stable and well spread -- it decides
## which way a deer wanders, and `randi()` would have done if determinism allowed it.
static func _hash(n: int) -> int:
	var x := n & 0x7FFFFFFF
	x = (x ^ (x >> 15)) * 0x2545F491
	x = (x ^ (x >> 13)) * 0x27220A95
	return (x ^ (x >> 16)) & 0x7FFFFFFF


## The nearest thing this animal is willing to bite, or 0.
##
## THROUGH `Diplomacy` FROM THE WOLF'S OWN SIDE -- `is_enemy(e, 0)` -- which is what
## makes a pack not eat itself: another wolf is owner 0 and so is this one, and the
## first clause in there sends that home as "not an enemy" with nothing said specially.
## Everything a player owns comes back true, villagers and town centres alike.
##
## BUILDINGS ARE FILTERED OUT HERE, though, and deliberately: `Diplomacy` answers "may
## this be attacked", and a town centre may. A wolf gnawing the corner of a granary is
## not what anybody means by wildlife, and it would also park the animal permanently on
## a target that cannot flee and takes four hundred bites to fell.
func _nearest_prey(w: SimWorld, u: SimUnit, radius: int) -> int:
	var here := u.tile()
	var span := radius * 2 + 1
	var rect := Rect2i(here - Vector2i(radius, radius), Vector2i(span, span))

	var best := 0
	var best_gap := 0
	for e in w.entities_in_rect(rect):
		if not (e is SimUnit):
			continue
		if not Diplomacy.is_enemy(e, u.owner_id, w.teams):
			continue
		var gap := CombatSystem.tile_gap(here, Rect2i(e.tile(), Vector2i.ONE))
		if gap > radius:
			continue          # the rect is square; the radius is meant to be too
		# Nearest wins, lowest id breaks a tie -- `CombatSystem._reacquire`'s rule,
		# and for its reason: determinism, not fairness.
		if best == 0 or gap < best_gap or (gap == best_gap and int(e.id) < best):
			best = int(e.id)
			best_gap = gap
	return best
