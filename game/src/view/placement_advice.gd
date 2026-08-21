## Whether a placement LOOKS legal, from what a client can actually see (PLAN.md 12.1b).
##
## **Advisory by design, and that is the whole point.** The authoritative answer lives in
## `SimWorld`, which a host can simply ask -- and `PlaceBuildingCommand.validate()` still
## asks it for every placement, from either side. A remote client has the map but not what
## anyone has built since, so this reads occupancy off snapshot facts instead. Being wrong
## therefore costs a REFUSAL, never a desync, which is the trade PLAN.md 12.1b makes
## explicitly: "the server already validates, so a wrong ghost costs a refusal".
##
## Where it is deliberately less strict than the server, and why:
##
## - **Completeness.** The real adjacency rule wants a FINISHED mill; snapshot facts carry
##   no phase, so a foundation mill will colour a field green and the host will refuse it.
## - **The per-host cap.** Four fields to a mill at the top age (4.14) needs counting what
##   is already attached; not worth reconstructing for a hint.
##
## Both err toward green, which is the right direction for a hint: a red ghost over legal
## ground stops a player doing something allowed, where a green one over illegal ground
## costs them one tap and a toast.
class_name PlacementAdvice
extends RefCounted


## The ground, plus everything the viewer can see standing on it.
##
## `map` may be null, in which case only the facts are consulted -- a client that has the
## config always has the map, so that is for tests and for the tick before it arrives.
static func can_place(map: SimMap, facts: Dictionary, rect: Rect2i) -> bool:
	if map != null and not map.can_place_building(rect):
		return false
	for f in facts.values():
		if not _occupies(f):
			continue
		if _rect_of(f).intersects(rect):
			return false
	return true


## The adjacency half (a field must abut its mill). True for everything that declares no
## `requires_adjacent`, which is every building but the field.
static func adjacency_allows(def_id: StringName, owner_id: int, origin: Vector2i,
		facts: Dictionary) -> bool:
	var bd: BuildingDef = GameDataRegistry.building(def_id)
	if bd == null or bd.requires_adjacent.is_empty():
		return true

	var rect := SimMap.footprint_rect(origin, bd.footprint)
	for f in facts.values():
		if not bool(f.get("alive", true)) or int(f.get("owner_id", 0)) != owner_id:
			continue
		if not bd.requires_adjacent.has(f.get("def_id", &"")):
			continue
		# grow(1) then intersect is "shares an edge or a corner with", the same shape
		# `SimWorld.adjacency_allows()` measures.
		if _rect_of(f).grow(1).intersects(rect):
			return true
	return false


## Whether the player can afford it, from the stock the snapshot reported.
static func can_afford(cost: Dictionary, stock: Dictionary) -> bool:
	for kind in cost:
		if int(stock.get(kind, 0)) < int(cost[kind]):
			return false
	return true


## Anything that claims ground: a building or a resource node, alive, of any phase.
##
## Units do not -- a placement goes ahead over villagers and steps them aside
## (`SimWorld._evict_from_footprint`) -- and a corpse or rubble does not either, because
## `alive` is false by then and building over rubble clears it (5.5).
static func _occupies(f: Dictionary) -> bool:
	return bool(f.get("alive", true)) and not bool(f.get("is_unit", false))


## A fact's footprint as tiles. `tile` is the CENTRE for anything multi-tile, which is
## the convention `GameView` records and `SimBuilding.centre_of` produces, so the origin
## has to be derived back out of it exactly the way `GameView` does for its occluders.
static func _rect_of(f: Dictionary) -> Rect2i:
	var fp: Vector2i = f.get("footprint", Vector2i.ONE)
	if fp.x < 1 or fp.y < 1:
		fp = Vector2i.ONE
	return Rect2i(Vector2i(f.get("tile", Vector2i.ZERO)) - fp / 2, fp)
