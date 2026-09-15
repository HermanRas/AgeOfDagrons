## A saved MATCH -- a half-built settlement with rubble in it (PLAN.md 12.4). Phase 12.4.
##
## ⛔ **THIS IS NOT A SAVED MAP, AND THE TWO MUST NEVER BE BLURRED.** A saved *map* (2.4c,
## `MapFile`) is the terrain and start layout a match was STARTED with; a saved *game* is
## where that match had got to. 11.3's third bullet has said so since it was written and the
## owner's ruling of 2026-09-04 reaffirms it.
##
## ## WHAT DEFINES THE FEATURE (the owner, 2026-09-04)
##
## *"Save Game - when a map is interupted by IRL so you can pick it back up with your friends
## or vs AI later."* So the case is a **multiplayer match resumed on another day**, not a solo
## autosave -- which means everything that makes the sim deterministic has to come back
## identical on **every** peer, or the match desyncs on the second tick of its second sitting.
##
## ## ⛔ THE ARCHITECTURE: REBUILD FROM THE CONFIG, THEN OVERWRITE WHAT MUTATED
##
## A load is `SimWorld.new()` -> `setup(cfg)` -> `MapGen.build(w, cfg)` -> `apply()`. That is
## the same path `SimHost.build()` runs, and using it is the whole safety argument rather than
## a convenience:
##
## **Everything a client derives from the `MatchConfig` is identical BY CONSTRUCTION and is
## deliberately not in the file** -- `mode`, `teams`, `objectives`, `objective_player_id`,
## `trophy_def_id`, `koth_zone`, `areas`, `named_units`, and each player's `colour`, `faction`,
## `team` and `ai_level`. That is not a saving of bytes; it is the same argument `state_hash()`
## makes for leaving those fields out of the hash (2.4a: every client builds its own world from
## the config). A save file that carried its own copy of them would be a second source of truth
## for facts two peers must agree on, and the fourth tracker this project has deleted for being
## exactly that.
##
## **What IS in the file is what MUTATED**, which is very nearly the set `state_hash()`
## enumerates -- plus the three things that mutate without being hashed and are named below.
##
## ## ⛔ ENTITIES ARE COPIED FIELD BY FIELD AND NEVER RE-SPAWNED FROM THEIR DEF
##
## The tempting shape is to call `spawn_unit(def_id, ...)` and patch what differs. It is wrong,
## and quietly: several fields are DERIVED from the roster at spawn and then **rewritten during
## the match**, so re-deriving them silently discards the match.
##
##   - `SiegeSystem` rewrites `SimUnit.speed` on every pack and unpack;
##   - 16.7's authored overrides rewrite `hp`, `max_hp` and a building's `attack_damage`;
##   - tech (9.3) moves numbers on entities already standing.
##
## A restored entity is therefore a LITERAL COPY. The def id rides along for what needs it, but
## nothing is recomputed from it.
##
## ## ⚠️ THREE THINGS MUTATE AND ARE NOT IN `state_hash()`. ALL THREE MUST BE SAVED
##
## The hash is the best available specification of "state two peers must agree on", so it is
## what this file was written against -- but it is not a complete specification of "state a
## match needs to continue", and the difference is exactly three things:
##
##   1. ⛔ **`SimWorld._next_id`.** The id counter. Restore it wrong and the next unit trained
##      is handed an id some living entity already holds -- two entities with one id, a
##      `removed[]` on the wire that deletes the wrong one, and a divergence with no cause
##      anywhere near it. It is private, it is never hashed, and it is the single most
##      dangerous omission available here.
##   2. **`SimMap`'s four arrays.** `map.state_hash()` is in the world hash, but the hash is a
##      number and a number cannot be restored from. Terrain is cut down, walls claim tiles,
##      and rubble releases them, so the live grid is not the generated one.
##   3. **`SimPlayer.vision`.** Cumulative -- `UNSEEN`/`EXPLORED`/`VISIBLE` -- so it is memory
##      and not a per-tick derivation. It IS hashed, and it would be lost without being saved.
##
## Everything else derived is rebuilt: `tech_mods` from `researched` (`TechMods.sum`, whole),
## the `SpatialHash` from the entities, and `VisionSystem._visible_last` by its own full-scan
## fallback.
##
## ## ⚠️ THE JSON TRAPS, BOTH OF WHICH THIS PROJECT HAS ALREADY PAID FOR ONCE
##
## `MapData._terrain_from`'s header is the account: **`JSON.stringify` renders a
## `PackedByteArray` as the TEXT `"[1, 2, 250]"`**, and assigning that String back to a typed
## `PackedByteArray` is a runtime error that abandons the rest of the parse -- undetected
## because the test written to catch it died on the same error and was counted as a pass.
## **And JSON numbers come back as floats**, so every integer is read through `int()`.
##
## ➡️ **PACKED ARRAYS RIDE AS BASE64 HERE, WHICH IS THE OPPOSITE OF `MapData`'s CHOICE AND FOR
## THE SAME REASON.** That class sends raw bytes because its transport is the binary RPC layer,
## where base64 would add a third for nothing. This one's transport is a JSON FILE, where a raw
## byte array becomes about four characters per byte -- so base64 is both smaller and exact,
## and the ambiguity about what a `PackedByteArray` decodes to never arises.
class_name SaveGame
extends RefCounted

## Bumped only when an older file can no longer be read. Absent keys are tolerated, so adding
## a field does not move it -- `MapData`'s decision 7 rule, applied here.
const FORMAT_VERSION := 1

## What `kind` says, per entity class. Words rather than the class name so a rename in the
## engine's type system cannot invalidate saved files -- `PackDef.KIND_WORDS`' argument.
const KIND_UNIT := "unit"
const KIND_BUILDING := "building"
const KIND_NODE := "node"
const KIND_PROJECTILE := "projectile"


# ── capture ─────────────────────────────────────────────────────────────────

## The whole save, ready for `JSON.stringify`.
##
## ⚠️ **THE AI's RULE STATE IS FOUND HERE RATHER THAN PASSED IN, AND THAT IS DELIBERATE.** The
## first shape of this function took it as an argument, which makes every caller responsible
## for remembering it -- and a caller who forgets does not get an error, they get a save that
## reloads with every bot's mind wiped. Nothing about that is visible until somebody plays the
## reloaded match. `SaveGame` is itself in `src/sim`, so reaching for a sim system crosses no
## boundary; the one it would cross is `src/view`, and this is nowhere near it.
static func capture(world: SimWorld, cfg: MatchConfig) -> Dictionary:
	var entities: Array[Dictionary] = []
	# SORTED, and this is not tidiness. `Dictionary` iteration order is not guaranteed, and
	# `state_hash()` sorts its ids for exactly that reason -- an unsorted list would make two
	# saves of one world differ byte for byte, which is the first thing anybody diffing a save
	# file would (correctly) read as a bug.
	var ids := world.entities.keys()
	ids.sort()
	for id in ids:
		entities.append(_entity_to_dict(world.entities[id]))

	var players: Array[Dictionary] = []
	for p in world.players:
		players.append(_player_to_dict(p))

	return {
		"format_version": FORMAT_VERSION,
		# The config is the other half of the file and is what the world is REBUILT from.
		"config": cfg.to_dict() if cfg != null else {},
		"world": {
			"tick": world.tick,
			# ⛔ The id counter. See the class comment: the most dangerous omission here.
			"next_id": world._next_id,
			"match_over": world.match_over,
			"winner_id": world.winner_id,
			"winner_team": world.winner_team,
			"claim_owner": world.claim_owner,
			"claim_ticks_left": world.claim_ticks_left,
			"claim_total_ticks": world.claim_total_ticks,
			"koth_holder": world.koth_holder,
		},
		"map": _map_to_dict(world.map),
		"players": players,
		"entities": entities,
		"ai": _ai_to_dict(_ai_progress_of(world)),
	}


## `AISystem`'s live rule table, or an empty one in a match with no bots in it.
static func _ai_progress_of(world: SimWorld) -> Dictionary:
	var ai := _ai_system(world)
	return ai._progress if ai != null else {}


## The `AISystem` in this world's tick order, or null. Searched rather than held: the system
## list is built by `SimWorld.setup()` and a second reference to it would be a second thing to
## keep in step with a reordering.
static func _ai_system(world: SimWorld) -> AISystem:
	if world == null:
		return null
	for s in world._systems:
		if s is AISystem:
			return s
	return null


static func _map_to_dict(map: SimMap) -> Dictionary:
	if map == null:
		return {}
	return {
		"w": map.size.x, "h": map.size.y,
		"terrain": _to_b64(map.terrain),
		"move_cost": _to_b64(map.move_cost),
		"blocking": _to_b64(map.blocking),
		# `occupancy` is entity ids, so it is 32-bit and goes through its byte form. Storing it
		# as a JSON array of ints would be ~40 KB of text for a 96x96 map and would come back
		# as floats.
		"occupancy": _to_b64(map.occupancy.to_byte_array()),
	}


static func _player_to_dict(p: SimPlayer) -> Dictionary:
	var stock := {}
	# Sorted for the reason the entity ids are, and as Strings because a StringName key does
	# not survive JSON (`&"x" == "x"` is false on the way back -- AGENT_GAME_CODER.md 6).
	var kinds := p.stock.keys()
	kinds.sort()
	for k in kinds:
		stock[String(k)] = int(p.stock[k])

	return {
		"id": p.id,
		# NOT colour, faction, team or ai_level: all four come from the config and are rebuilt
		# by `SimWorld.setup()`. See the class comment.
		"pop_used": p.pop_used, "pop_cap": p.pop_cap, "age": p.age,
		"advancing_to": p.advancing_to, "advance_ticks": p.advance_ticks,
		"advance_total_ticks": p.advance_total_ticks,
		"stock": stock,
		# `researched_ids()` is already sorted by CONTENT -- `Array[StringName].sort()` orders
		# by identity, which is not stable between runs, and that function exists to fix it.
		# `tech_mods` is deliberately absent: it is a pure function of this list and is rebuilt
		# by `TechMods.sum`, so writing it would be a second source of truth for one fact.
		"researched": p.researched_ids(),
		"control_groups": _groups_to_array(p.control_groups),
		"score": p.score, "koth_rate": p.koth_rate,
		"defeated": p.defeated, "defeat_reason": p.defeat_reason,
		"objective_progress": _ints_to_array(p.objective_progress),
		"objective_done": _to_b64(p.objective_done),
		# Cumulative fog. See the class comment's third item.
		"vision": _to_b64(p.vision),
	}


static func _entity_to_dict(e: SimEntity) -> Dictionary:
	var d := {
		"id": e.id, "def_id": String(e.def_id), "owner": e.owner_id,
		"pos": _v(e.pos), "hp": e.hp, "max_hp": e.max_hp, "alive": e.alive,
		"vision_range": e.vision_range, "last_attacker_owner": e.last_attacker_owner,
		"garrison_cap": e.garrison_cap, "garrison": _garrison_to_array(e.garrison),
		# 16.7's authored four. Written here on the COMMON line for the same reason
		# `state_hash()` folds them in there: they come out of a `map.json` rather than out of
		# the roster, so nothing recomputes them and a save that dropped them would hand back a
		# scripted hero with a militia's 40 hp.
		"entity_name": String(e.entity_name), "max_hp_override": e.max_hp_override,
		"attack_override": e.attack_override, "speed_override": e.speed_override,
	}
	if e is SimUnit:
		d["kind"] = KIND_UNIT
		d["unit"] = _unit_to_dict(e)
	elif e is SimBuilding:
		d["kind"] = KIND_BUILDING
		d["building"] = _building_to_dict(e)
	elif e is SimResourceNode:
		d["kind"] = KIND_NODE
		d["node"] = _node_to_dict(e)
	elif e is SimProjectile:
		d["kind"] = KIND_PROJECTILE
		d["projectile"] = _projectile_to_dict(e)
	return d


static func _unit_to_dict(u: SimUnit) -> Dictionary:
	return {
		"task": int(u.task), "stance": u.stance, "guard_post": _v(u.guard_post),
		"task_target_id": u.task_target_id, "task_target_tile": _v(u.task_target_tile),
		# The route itself, not just the progress. `state_hash()` hashes only `path.size()` and
		# `path_index` -- enough to CATCH a divergence, nowhere near enough to RESUME one: two
		# peers holding different routes of equal length agree on the hash and then walk two
		# different ways. A save has to carry the whole thing.
		"path": _path_to_array(u.path), "path_index": u.path_index,
		"path_pending": u.path_pending,
		# Rewritten by `SiegeSystem` on every pack and unpack, so it is match state and not a
		# roster lookup. See the class comment.
		"speed": u.speed,
		"facing": u.facing, "domain": u.domain, "pop_cost": u.pop_cost,
		"carry_kind": String(u.carry_kind), "carry_amount": u.carry_amount,
		"gather_cooldown": u.gather_cooldown, "gather_node_id": u.gather_node_id,
		"gather_node_tile": _v(u.gather_node_tile), "deposit_tile": _v(u.deposit_tile),
		"attack_cooldown": u.attack_cooldown, "ability_cooldown": u.ability_cooldown,
		"ability_target_tile": _v(u.ability_target_tile), "killed_by_id": u.killed_by_id,
		"anim": String(u.anim), "packs": u.packs, "packed": u.packed,
		"pack_ticks_left": u.pack_ticks_left, "roam_home": _v(u.roam_home),
		"roam_cooldown": u.roam_cooldown, "flee_ticks": u.flee_ticks, "last_hp": u.last_hp,
		"herded_by": u.herded_by, "garrisoned_in": u.garrisoned_in,
		"corpse_ticks_left": u.corpse_ticks_left,
	}


static func _building_to_dict(b: SimBuilding) -> Dictionary:
	var queue: Array[Dictionary] = []
	for entry in b.queue:
		queue.append({
			"def_id": String(entry.get("def_id", &"")),
			"progress": int(entry.get("progress", 0)),
			"ready": bool(entry.get("ready", false)),
		})
	return {
		"phase": int(b.phase), "footprint": _v(b.footprint), "facing": b.facing,
		"is_gate": b.is_gate, "gate_locked": b.gate_locked,
		"build_progress": b.build_progress, "build_total": b.build_total,
		"rubble_ticks_left": b.rubble_ticks_left, "leaves_rubble": b.leaves_rubble,
		"claim_owner": b.claim_owner, "claim_ticks_left": b.claim_ticks_left,
		"claim_baby_id": b.claim_baby_id,
		"gather_kind": String(b.gather_kind), "gather_amount": b.gather_amount,
		"gather_slots": b.gather_slots, "provides_pop": b.provides_pop,
		# Carries 16.7's override on this end, because a building's attack is copied at spawn.
		"attack_damage": b.attack_damage, "attack_type": String(b.attack_type),
		"attack_range": b.attack_range, "attack_cooldown_ticks": b.attack_cooldown_ticks,
		"attack_projectile": String(b.attack_projectile), "attack_volley": b.attack_volley,
		"waypoint": _v(b.waypoint), "attack_cooldown": b.attack_cooldown,
		"queue": queue,
	}


static func _node_to_dict(n: SimResourceNode) -> Dictionary:
	return {
		"kind": String(n.kind), "amount": n.amount, "starting_amount": n.starting_amount,
		"size_class": n.size_class, "gather_slots": n.gather_slots,
		"footprint": _v(n.footprint), "is_wildlife": n.is_wildlife,
	}


static func _projectile_to_dict(p: SimProjectile) -> Dictionary:
	return {
		"origin_pos": _v(p.origin_pos), "target_pos": _v(p.target_pos),
		"total_ticks": p.total_ticks, "elapsed_ticks": p.elapsed_ticks, "facing": p.facing,
	}


## `AISystem._progress` -- per-player rule state (12.2b). Keys are player ids, which JSON turns
## into strings and `int()` turns back.
##
## ⚠️ **WITHOUT THIS THE OWNER'S OWN SENTENCE IS NOT SATISFIED.** *"pick it back up with your
## friends or vs AI later"*: a bot reloaded with an empty progress table starts its build order
## again from the top, in a town it already built, which is not the match anybody saved.
static func _ai_to_dict(progress: Dictionary) -> Dictionary:
	var out := {}
	var keys := progress.keys()
	keys.sort()
	for k in keys:
		out[str(k)] = progress[k]
	return out


# ── restore ─────────────────────────────────────────────────────────────────

## Overwrite `world` with what `d` says. The world must already have been built from the same
## config -- see the class comment -- and this never reads the config half.
##
## Returns the complaints. Empty means everything in the file was understood; a non-empty list
## means the world is NOT the saved one and the caller must not start a match on it. Nothing
## here throws, on `PackDef.from_dict`'s precedent: a save file is a file a player can edit.
static func apply(world: SimWorld, d: Dictionary) -> Array[String]:
	var problems: Array[String] = []
	if world == null:
		problems.append("there is no world to restore into")
		return problems

	var version := int(d.get("format_version", 0))
	if version <= 0:
		problems.append("this file does not say what format it is in")
		return problems
	if version > FORMAT_VERSION:
		problems.append("the file is format %d and this build reads up to %d"
				% [version, FORMAT_VERSION])
		return problems

	_apply_world(world, d.get("world", {}), problems)
	_apply_map(world.map, d.get("map", {}), problems)
	_apply_players(world, d.get("players", []), problems)
	_apply_entities(world, d.get("entities", []), problems)
	_apply_ai(world, d)
	return problems


## Put each bot's mind back where it was. A world with no bots has nothing to restore and an
## empty table is the correct state for one.
static func _apply_ai(world: SimWorld, d: Dictionary) -> void:
	var ai := _ai_system(world)
	if ai == null:
		return
	ai._progress = ai_progress_from(d)


static func _apply_world(world: SimWorld, raw: Variant, problems: Array[String]) -> void:
	if not raw is Dictionary:
		problems.append("the file has no world state")
		return
	var w: Dictionary = raw
	world.tick = int(w.get("tick", 0))
	# ⛔ THE ID COUNTER. A file that does not carry it is not merely incomplete: continuing
	# with the default 1 hands the next trained unit an id that a living entity already holds.
	# Refused rather than guessed at -- and `maxi` against what was actually restored is the
	# belt to that braces, in `_apply_entities`.
	if not w.has("next_id"):
		problems.append("the file does not carry the entity id counter")
	world._next_id = maxi(int(w.get("next_id", 1)), 1)
	world.match_over = bool(w.get("match_over", false))
	world.winner_id = int(w.get("winner_id", 0))
	world.winner_team = int(w.get("winner_team", 0))
	world.claim_owner = int(w.get("claim_owner", 0))
	world.claim_ticks_left = int(w.get("claim_ticks_left", -1))
	world.claim_total_ticks = int(w.get("claim_total_ticks", 0))
	world.koth_holder = int(w.get("koth_holder", 0))


static func _apply_map(map: SimMap, raw: Variant, problems: Array[String]) -> void:
	if map == null or not raw is Dictionary:
		problems.append("the file has no map state")
		return
	var m: Dictionary = raw
	var want := Vector2i(int(m.get("w", 0)), int(m.get("h", 0)))
	# ⚠️ THE SIZE IS CHECKED AND NOT ASSIGNED. The world was just built from the config, so a
	# disagreement here means the file and the config describe different matches -- a map
	# regenerated by a changed generator, or a save moved onto another campaign. Resizing the
	# grid to fit the file would produce a world in which the config's start positions, areas
	# and koth zone all point somewhere else.
	if want != map.size:
		problems.append("the save is %dx%d and the match built %dx%d"
				% [want.x, want.y, map.size.x, map.size.y])
		return

	var count := map.size.x * map.size.y
	var terrain := _bytes_from(m.get("terrain", ""))
	var move_cost := _bytes_from(m.get("move_cost", ""))
	var blocking := _bytes_from(m.get("blocking", ""))
	var occupancy := _bytes_from(m.get("occupancy", "")).to_int32_array()
	for pair in [["terrain", terrain.size()], ["move_cost", move_cost.size()],
			["blocking", blocking.size()], ["occupancy", occupancy.size()]]:
		if int(pair[1]) != count:
			problems.append("the map's `%s` is %d tiles, wanted %d" % [pair[0], pair[1], count])
			return
	map.terrain = terrain
	map.move_cost = move_cost
	map.blocking = blocking
	map.occupancy = occupancy


static func _apply_players(world: SimWorld, raw: Variant, problems: Array[String]) -> void:
	if not raw is Array:
		problems.append("the file has no players")
		return
	for entry in raw:
		if not entry is Dictionary:
			continue
		var row: Dictionary = entry
		var id := int(row.get("id", 0))
		var p := world.player_for(id)
		if p == null:
			# The config built a different set of seats than the file was written with.
			problems.append("the save has a player %d that this match has not seated" % id)
			continue
		p.pop_used = int(row.get("pop_used", 0))
		p.pop_cap = int(row.get("pop_cap", 0))
		p.age = int(row.get("age", 1))
		p.advancing_to = int(row.get("advancing_to", 0))
		p.advance_ticks = int(row.get("advance_ticks", 0))
		p.advance_total_ticks = int(row.get("advance_total_ticks", 0))

		p.stock = {}
		var stock: Variant = row.get("stock", {})
		if stock is Dictionary:
			for k in (stock as Dictionary):
				# Back to a StringName at the boundary: everything off JSON is a String, and
				# `&"wood" == "wood"` is false.
				p.stock[StringName(str(k))] = int((stock as Dictionary)[k])

		p.researched = {}
		for t in _as_array(row.get("researched", [])):
			p.researched[StringName(str(t))] = true
		# Rebuilt whole rather than read from the file -- `researched` is the one source of
		# truth and `TechMods.sum` is the one function that reads it.
		p.tech_mods = TechMods.sum(p.researched)

		p.control_groups = _groups_from(row.get("control_groups", []))
		p.score = int(row.get("score", 0))
		p.koth_rate = int(row.get("koth_rate", 0))
		p.defeated = bool(row.get("defeated", false))
		p.defeat_reason = int(row.get("defeat_reason", 0))
		p.objective_progress = _ints_from(row.get("objective_progress", []))
		p.objective_done = _bytes_from(row.get("objective_done", ""))
		p.vision = _bytes_from(row.get("vision", ""))


static func _apply_entities(world: SimWorld, raw: Variant, problems: Array[String]) -> void:
	if not raw is Array:
		problems.append("the file has no entities")
		return

	# EVERYTHING THE BUILD PUT THERE GOES. The world was rebuilt from the config, so it is
	# standing at tick 0 with a full starting settlement on it; what the file describes is the
	# match. The spatial index goes with them -- it is derived, and a stale entry would answer
	# a radius query with an entity that no longer exists.
	world.entities.clear()
	world.spatial = SpatialHash.new()
	world.removed_this_tick.clear()

	var highest := 0
	for entry in raw:
		if not entry is Dictionary:
			continue
		var e := _entity_from_dict(entry as Dictionary)
		if e == null:
			problems.append("the file has an entity of a kind this build does not know ('%s')"
					% str((entry as Dictionary).get("kind", "")))
			continue
		world.entities[e.id] = e
		highest = maxi(highest, e.id)
		# The spatial index carries what can be FOUND on the ground. A garrisoned unit is
		# deliberately absent from it -- `SimWorld`'s own mechanism is `spatial.remove()`
		# without a despawn -- and so is anything dead. Projectiles are never in it.
		if e.alive and not (e is SimProjectile):
			var inside := e is SimUnit and (e as SimUnit).garrisoned_in != 0
			if not inside:
				world.spatial.insert(e.id, e.tile())

	# ⛔ THE BELT TO `next_id`'s BRACES. A file whose counter was edited, lost, or written by a
	# older build must still never hand out a live id. This cannot make the counter right, but
	# it does make it SAFE, which is the property that matters.
	if world._next_id <= highest:
		problems.append("the id counter (%d) is not past the highest entity (%d); advanced it"
				% [world._next_id, highest])
		world._next_id = highest + 1


static func _entity_from_dict(d: Dictionary) -> SimEntity:
	var kind := str(d.get("kind", ""))
	var e: SimEntity = null
	match kind:
		KIND_UNIT:
			e = _unit_from(d.get("unit", {}))
		KIND_BUILDING:
			e = _building_from(d.get("building", {}))
		KIND_NODE:
			e = _node_from(d.get("node", {}))
		KIND_PROJECTILE:
			e = _projectile_from(d.get("projectile", {}))
		_:
			return null

	e.id = int(d.get("id", 0))
	e.def_id = StringName(str(d.get("def_id", "")))
	e.owner_id = int(d.get("owner", 0))
	e.pos = _to_v(d.get("pos", []))
	e.hp = int(d.get("hp", 0))
	e.max_hp = int(d.get("max_hp", 0))
	e.alive = bool(d.get("alive", true))
	e.vision_range = int(d.get("vision_range", 0))
	e.last_attacker_owner = int(d.get("last_attacker_owner", SimEntity.NO_ATTACKER))
	e.garrison_cap = int(d.get("garrison_cap", 0))
	e.garrison = _garrison_from(d.get("garrison", []))
	e.entity_name = StringName(str(d.get("entity_name", "")))
	e.max_hp_override = int(d.get("max_hp_override", 0))
	e.attack_override = int(d.get("attack_override", -1))
	e.speed_override = int(d.get("speed_override", -1))
	return e


static func _unit_from(raw: Variant) -> SimUnit:
	var u := SimUnit.new()
	if not raw is Dictionary:
		return u
	var d: Dictionary = raw
	u.task = int(d.get("task", 0)) as SimUnit.Task
	u.stance = int(d.get("stance", 0))
	u.guard_post = _to_v(d.get("guard_post", []), SimUnit.NO_POST)
	u.task_target_id = int(d.get("task_target_id", 0))
	u.task_target_tile = _to_v(d.get("task_target_tile", []))
	u.path = _path_from(d.get("path", []))
	u.path_index = int(d.get("path_index", 0))
	u.path_pending = bool(d.get("path_pending", false))
	u.speed = int(d.get("speed", 0))
	u.facing = int(d.get("facing", 0))
	u.domain = int(d.get("domain", SimMap.Domain.LAND))
	u.pop_cost = int(d.get("pop_cost", 1))
	u.carry_kind = StringName(str(d.get("carry_kind", "")))
	u.carry_amount = int(d.get("carry_amount", 0))
	u.gather_cooldown = int(d.get("gather_cooldown", 0))
	u.gather_node_id = int(d.get("gather_node_id", 0))
	u.gather_node_tile = _to_v(d.get("gather_node_tile", []))
	u.deposit_tile = _to_v(d.get("deposit_tile", []), Vector2i(-1, -1))
	u.attack_cooldown = int(d.get("attack_cooldown", 0))
	u.ability_cooldown = int(d.get("ability_cooldown", 0))
	u.ability_target_tile = _to_v(d.get("ability_target_tile", []))
	u.killed_by_id = int(d.get("killed_by_id", 0))
	u.anim = StringName(str(d.get("anim", "idle")))
	u.packs = bool(d.get("packs", false))
	u.packed = bool(d.get("packed", false))
	u.pack_ticks_left = int(d.get("pack_ticks_left", 0))
	u.roam_home = _to_v(d.get("roam_home", []), Vector2i(-1, -1))
	u.roam_cooldown = int(d.get("roam_cooldown", 0))
	u.flee_ticks = int(d.get("flee_ticks", 0))
	u.last_hp = int(d.get("last_hp", -1))
	u.herded_by = int(d.get("herded_by", 0))
	u.garrisoned_in = int(d.get("garrisoned_in", 0))
	u.corpse_ticks_left = int(d.get("corpse_ticks_left", -1))
	return u


static func _building_from(raw: Variant) -> SimBuilding:
	var b := SimBuilding.new()
	if not raw is Dictionary:
		return b
	var d: Dictionary = raw
	b.phase = int(d.get("phase", 0)) as SimBuilding.Phase
	b.footprint = _to_v(d.get("footprint", []), Vector2i.ONE)
	b.facing = int(d.get("facing", 0))
	b.is_gate = bool(d.get("is_gate", false))
	b.gate_locked = bool(d.get("gate_locked", false))
	b.build_progress = int(d.get("build_progress", 0))
	b.build_total = int(d.get("build_total", 0))
	b.rubble_ticks_left = int(d.get("rubble_ticks_left", -1))
	b.leaves_rubble = bool(d.get("leaves_rubble", true))
	b.claim_owner = int(d.get("claim_owner", 0))
	b.claim_ticks_left = int(d.get("claim_ticks_left", -1))
	b.claim_baby_id = int(d.get("claim_baby_id", 0))
	b.gather_kind = StringName(str(d.get("gather_kind", "")))
	b.gather_amount = int(d.get("gather_amount", 0))
	b.gather_slots = int(d.get("gather_slots", 0))
	b.provides_pop = int(d.get("provides_pop", 0))
	b.attack_damage = int(d.get("attack_damage", 0))
	b.attack_type = StringName(str(d.get("attack_type", "melee")))
	b.attack_range = int(d.get("attack_range", 0))
	b.attack_cooldown_ticks = int(d.get("attack_cooldown_ticks", 0))
	b.attack_projectile = StringName(str(d.get("attack_projectile", "")))
	b.attack_volley = int(d.get("attack_volley", 1))
	b.waypoint = _to_v(d.get("waypoint", []), SimBuilding.NO_WAYPOINT)
	b.attack_cooldown = int(d.get("attack_cooldown", 0))
	var queue: Array[Dictionary] = []
	for entry in _as_array(d.get("queue", [])):
		if not entry is Dictionary:
			continue
		var row: Dictionary = entry
		queue.append({
			"def_id": StringName(str(row.get("def_id", ""))),
			"progress": int(row.get("progress", 0)),
			"ready": bool(row.get("ready", false)),
		})
	b.queue = queue
	return b


static func _node_from(raw: Variant) -> SimResourceNode:
	var n := SimResourceNode.new()
	if not raw is Dictionary:
		return n
	var d: Dictionary = raw
	n.kind = StringName(str(d.get("kind", "")))
	n.amount = int(d.get("amount", 0))
	n.starting_amount = int(d.get("starting_amount", 0))
	n.size_class = int(d.get("size_class", 0))
	n.gather_slots = int(d.get("gather_slots", 1))
	n.footprint = _to_v(d.get("footprint", []), Vector2i.ONE)
	n.is_wildlife = bool(d.get("is_wildlife", false))
	return n


static func _projectile_from(raw: Variant) -> SimProjectile:
	var p := SimProjectile.new()
	if not raw is Dictionary:
		return p
	var d: Dictionary = raw
	p.origin_pos = _to_v(d.get("origin_pos", []))
	p.target_pos = _to_v(d.get("target_pos", []))
	p.total_ticks = int(d.get("total_ticks", 1))
	p.elapsed_ticks = int(d.get("elapsed_ticks", 0))
	p.facing = int(d.get("facing", 0))
	return p


## `AISystem._progress`, with its player-id keys turned back into ints. JSON has string keys
## only, so a table keyed by player id comes back keyed by `"2"` and every lookup misses --
## silently, leaving each bot with a fresh mind in an old town.
static func ai_progress_from(d: Dictionary) -> Dictionary:
	var out := {}
	var raw: Variant = d.get("ai", {})
	if not raw is Dictionary:
		return out
	for k in (raw as Dictionary):
		out[int(str(k))] = (raw as Dictionary)[k]
	return out


# ── the JSON boundary ───────────────────────────────────────────────────────

## `Vector2i` is not JSON. A two-element array rather than `{"x":..,"y":..}` because an entity
## carries eight of these and the object form triples the file for no gain; `MapData` uses the
## object form where there is one tile per row and it reads better there.
static func _v(v: Vector2i) -> Array:
	return [v.x, v.y]


static func _to_v(raw: Variant, fallback: Vector2i = Vector2i.ZERO) -> Vector2i:
	if not raw is Array or (raw as Array).size() < 2:
		return fallback
	var a: Array = raw
	return Vector2i(int(a[0]), int(a[1]))


## A route, flattened. `PackedVector2Array` does not survive JSON, and pairs of numbers do.
static func _path_to_array(path: PackedVector2Array) -> Array:
	var out: Array = []
	for p in path:
		out.append(p.x)
		out.append(p.y)
	return out


static func _path_from(raw: Variant) -> PackedVector2Array:
	var out := PackedVector2Array()
	if not raw is Array:
		return out
	var a: Array = raw
	var i := 0
	# Pairs, so an odd tail is dropped rather than read as half a point.
	while i + 1 < a.size():
		out.append(Vector2(float(a[i]), float(a[i + 1])))
		i += 2
	return out


## Bytes out as base64, with the empty case handled rather than passed on.
##
## ⚠️ **`Marshalls.raw_to_base64` PRINTS AN ENGINE ERROR FOR AN EMPTY ARRAY** -- `Condition
## "ret.is_empty()" is true` out of `core_bind.cpp` -- and empty is not a rare case here: a
## skirmish has no objectives, so `objective_done` is empty for every player in it, and this
## fired several times per save. Nothing was WRONG (the value round-trips), which is what makes
## it worth a guard rather than a shrug: a save that prints engine errors trains everybody
## reading a log to scroll past them, and `run_tests.gd`'s script-error spy is watching.
static func _to_b64(bytes: PackedByteArray) -> String:
	return "" if bytes.is_empty() else Marshalls.raw_to_base64(bytes)


## Base64 in, bytes out -- and tolerant of the shapes a hand-edited or older file could carry,
## on `MapData._terrain_from`'s precedent. An Array of numbers is what somebody editing a save
## by hand would most naturally write.
static func _bytes_from(raw: Variant) -> PackedByteArray:
	if raw is PackedByteArray:
		return raw
	if raw is String:
		# The empty string is the empty array, and is not handed to the decoder for the reason
		# `_to_b64` does not hand it the empty array.
		return PackedByteArray() if (raw as String).is_empty() \
				else Marshalls.base64_to_raw(raw)
	if raw is Array:
		var out := PackedByteArray()
		for v in (raw as Array):
			out.append(int(v) & 255)
		return out
	return PackedByteArray()


static func _ints_to_array(values: Array[int]) -> Array:
	var out: Array = []
	for v in values:
		out.append(v)
	return out


static func _ints_from(raw: Variant) -> Array[int]:
	var out: Array[int] = []
	for v in _as_array(raw):
		out.append(int(v))
	return out


static func _groups_to_array(groups: Array) -> Array:
	var out: Array = []
	for g in groups:
		out.append(_ints_to_array(g as Array[int]) if g is Array[int] else _ints_from(g))
	return out


## Always the declared number of slots, whatever the file says. `SimPlayer.control_groups` is
## indexed by slot everywhere it is read, so a short array from a truncated or older file would
## be an out-of-bounds read on the first press of a number key.
static func _groups_from(raw: Variant) -> Array:
	var out: Array = [[], [], [], [], []]
	var a := _as_array(raw)
	for i in mini(a.size(), out.size()):
		out[i] = _ints_from(a[i])
	return out


static func _garrison_to_array(garrison: Array[Dictionary]) -> Array:
	var out: Array = []
	for entry in garrison:
		out.append({"id": int(entry.get("id", 0)),
				"def_id": String(entry.get("def_id", &""))})
	return out


## Ids AND def ids, in insertion order -- `state_hash()`'s note says why both: the set decides
## what a tower's shot is worth, and the eject-by-index command makes the ORDER load-bearing.
static func _garrison_from(raw: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in _as_array(raw):
		if not entry is Dictionary:
			continue
		var row: Dictionary = entry
		out.append({"id": int(row.get("id", 0)),
				"def_id": StringName(str(row.get("def_id", "")))})
	return out


static func _as_array(v: Variant) -> Array:
	return v if v is Array else []
