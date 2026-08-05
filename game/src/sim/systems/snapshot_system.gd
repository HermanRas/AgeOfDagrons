## Builds the per-player wire format described in PLAN.md 7.2:
## {tick, spawned[], updated[], removed[], player_state}.
##
## Not run as part of SimWorld._systems -- it doesn't mutate state, and
## broadcasting it crosses the sim/net boundary, so whoever hosts the match
## (SimHost) calls build() once after each world.step().
##
## Fog-of-war filtering (VisionSystem) doesn't exist yet, so every entity is
## sent as "updated" every tick rather than a real spawned/updated/removed
## delta against the last acknowledged tick -- correct but not bandwidth-
## efficient. player_id is already part of the signature so the real
## per-player filter slots in here without changing call sites.
class_name SnapshotSystem
extends RefCounted

static func build(w: SimWorld, _player_id: int) -> Dictionary:
	var updated: Array[Dictionary] = []
	for e in w.entities.values():
		if e.alive:
			updated.append(e.to_snapshot())

	var player_state: Dictionary = {}
	for p in w.players:
		player_state[p.id] = {
			"stock": p.stock,
			"pop_used": p.pop_used,
			"pop_cap": p.pop_cap,
			"age": p.age,
		}

	return {
		"tick": w.tick,
		"spawned": [],
		"updated": updated,
		"removed": [],
		"player_state": player_state,
	}
