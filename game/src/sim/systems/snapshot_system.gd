## Builds the per-player wire format described in PLAN.md 7.2:
## {tick, spawned[], updated[], removed[], player_state}.
##
## Not run as part of SimWorld._systems -- it doesn't mutate state, and
## broadcasting it crosses the sim/net boundary, so whoever hosts the match
## (SimHost) calls build() once after each world.step().
##
## Fog-of-war filtering (VisionSystem) doesn't exist yet, so every entity still
## in `entities` is sent as "updated" every tick rather than a real
## spawned/updated delta against the last acknowledged tick -- correct but not
## bandwidth-efficient. player_id is already part of the signature so the real
## per-player filter slots in here without changing call sites.
##
## `updated` deliberately includes dead entities still hanging around --
## a unit's corpse (4.7) and a building's rubble (5.5) are `alive == false` but
## must keep rendering until DeathSystem actually despawns them. `removed` is a
## real list, unlike `updated`: it is SimWorld.removed_this_tick, so the view can
## tell "still here, just dead" from "actually gone" and free the pooled view only
## for the latter.
class_name SnapshotSystem
extends RefCounted

static func build(w: SimWorld, _player_id: int) -> Dictionary:
	var updated: Array[Dictionary] = []
	for e in w.entities.values():
		updated.append(e.to_snapshot())

	var player_state: Dictionary = {}
	for p in w.players:
		player_state[p.id] = {
			"stock": p.stock,
			"pop_used": p.pop_used,
			"pop_cap": p.pop_cap,
			"age": p.age,
			# PLAN.md 1/A.6: the client needs this to tint anything, and it is the
			# only per-player difference in v1. Not in state_hash() -- it is derived
			# from join order and never mutates, so it cannot diverge the way stock
			# or control groups can.
			"colour": p.colour,
			# Age advancement in flight (9.2), as INT TICKS rather than a
			# fraction -- the sim carries no floats, and the ring the HUD draws
			# from these is a view concern. 0/0/0 when nothing is being
			# researched, which the badge reads as "no ring".
			"advancing_to": p.advancing_to,
			"advance_ticks": p.advance_ticks,
			"advance_total_ticks": p.advance_total_ticks,
			# PLAN.md 10.6: persisted sim state, not view state, so it rides the
			# same snapshot every other per-player fact does rather than a
			# separate channel.
			"control_groups": p.control_groups,
		}

	return {
		"tick": w.tick,
		"spawned": [],
		"updated": updated,
		"removed": w.removed_this_tick.duplicate(),
		"player_state": player_state,
	}
