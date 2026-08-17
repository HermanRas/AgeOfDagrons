## Builds the per-player wire format described in PLAN.md 7.2:
## {tick, spawned[], updated[], removed[], player_state}.
##
## Not run as part of SimWorld._systems -- it doesn't mutate state, and
## broadcasting it crosses the sim/net boundary, so whoever hosts the match
## (SimHost) calls build() once after each world.step().
##
## FOG FILTERING IS A SECURITY PROPERTY, not a rendering one (PLAN.md 5.1 step 6:
## "the server must not send a client entities it cannot see"). It is done HERE, at
## the point the data leaves the server, rather than by the view choosing what to
## draw -- a client that filtered its own snapshot is a client that could choose not
## to, and map hacks in every RTS that ever shipped one are exactly that bug.
## `VisionSystem` computes the vision; this is what spends it.
##
## Four categories, and the line between them is MOBILE versus STATIC:
##
##   your own          always sent, whatever the fog says. You always know where your
##                     own things are, and a unit walking into an unexplored corner
##                     must not vanish from its owner.
##   currently visible sent in full.
##   explored, static  sent REMEMBERED (see `_remembered`) -- a building or a tree
##                     does not move, so telling you it is there gives away nothing
##                     that will have changed by the time you look again. This is
##                     what makes an explored hillside keep its forest.
##   anything else     not sent at all. In particular an enemy UNIT out of vision is
##                     absent, which is the whole point: its position is exactly the
##                     thing that changes while you cannot see it.
##
## KNOWN SIMPLIFICATION: a remembered static is only sent while it is ALIVE, so an
## enemy building destroyed behind the fog disappears from your screen rather than
## leaving the stale ghost AoE would leave. Leaving the ghost means the server
## keeping a per-player copy of every static as it was last seen; the position it
## takes today leaks "that building is gone" and never leaks anything live.
##
## `updated` deliberately includes dead entities still hanging around --
## a unit's corpse (4.7) and a building's rubble (5.5) are `alive == false` but
## must keep rendering until DeathSystem actually despawns them. `removed` is a
## real list, unlike `updated`: it is SimWorld.removed_this_tick, so the view can
## tell "still here, just dead" from "actually gone" and free the pooled view only
## for the latter.
##
## `removed` is NOT fog-filtered, and that is a considered exception rather than an
## oversight. It carries bare integers -- no position, no kind, no owner -- so what
## it discloses is "some entity ceased to exist", which is not a fact about anywhere
## on the map. Filtering it properly would mean remembering per player which ids they
## had been sent, since the entity is already gone from `entities` by the time this
## runs and there is nothing left to ask the fog about.
##
## Still not a real delta: everything a player may see is sent every tick rather
## than only what changed since their last acknowledged one. Correct, and not
## bandwidth-efficient. The view now treats ABSENCE from `updated` as "I cannot see
## that any more" (GameView.apply_snapshot), which a true delta would have to
## express some other way -- there is a note on that in GameView.
class_name SnapshotSystem
extends RefCounted

static func build(w: SimWorld, player_id: int) -> Dictionary:
	var viewer := w.player_for(player_id)
	var updated: Array[Dictionary] = []
	for e in w.entities.values():
		var entry := _entry_for(w, viewer, e)
		if not entry.is_empty():
			updated.append(entry)

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
			# PLAN.md 11.1. Per-player rather than derivable from `winner_id` below:
			# in a match of three or more, a player is knocked out while the match
			# goes on, and this is the only thing that says so.
			"defeated": p.defeated,
		}

	return {
		"tick": w.tick,
		"spawned": [],
		"updated": updated,
		"removed": w.removed_this_tick.duplicate(),
		"player_state": player_state,
		# ONLY THE VIEWER'S OWN FOG, never everybody's: the grid is what the filter
		# above was applied with, and shipping another player's copy would hand the
		# client the very map the filter exists to withhold. Raw bytes with the map
		# size, the same shape the terrain itself is sent in (`GameView.build_terrain`)
		# -- and empty when the world has no fog, which the view reads as "draw none".
		"vision": viewer.vision.duplicate() if viewer != null else PackedByteArray(),
		# The outcome (PLAN.md 11.1), which is about the MATCH and not about any one
		# player, so it sits beside `tick` rather than in `player_state`.
		# `match_over` without a `winner_id` is the draw; see SimWorld's own fields.
		# `mode` rides along so the result screen can name the rule that decided it
		# (11.3) without the client having to remember what the lobby picked.
		"mode": int(w.mode),
		"match_over": w.match_over,
		"winner_id": w.winner_id,
	}


## What `viewer` is told about `e` this tick: its full snapshot, a remembered
## version of it, or {} for "not sent".
static func _entry_for(w: SimWorld, viewer: SimPlayer, e: SimEntity) -> Dictionary:
	if viewer == null or viewer.vision.is_empty():
		return e.to_snapshot()          # no fog in this world; see SimPlayer.vision
	if e.owner_id == viewer.id:
		return e.to_snapshot()

	var rect := _rect_of(e)
	if VisionSystem.can_see_rect(w, viewer, rect):
		return e.to_snapshot()
	if e is SimUnit:
		return {}                       # mobile: its position is what it would leak
	if not e.alive:
		return {}                       # see the header's known simplification
	if VisionSystem.has_explored_rect(w, viewer, rect):
		return _remembered(e)
	return {}


## A static entity as the player REMEMBERS it: where it is, what it is, and whose
## it is -- and nothing that changes.
##
## Built by stripping the full snapshot rather than by assembling a new dictionary
## from scratch, so a field added to `to_snapshot()` cannot silently start leaking
## through here. The removals are the point:
##
##   hp / max_hp   whether an enemy town centre is being burned down while you are
##                 not looking is live information. Dropping both also makes the
##                 view do the right thing for free -- SelectionPanel already hides
##                 the health bar when max_hp is 0.
##   queue         what they are training, and how far along, is the most valuable
##                 thing on the wire.
##   amount        how much wood is left in a forest you last saw an hour ago is a
##                 running commentary on somebody else's economy.
##   build_fraction  a foundation going up is live. `phase` STAYS, because the view
##                 picks the sprite from it and a remembered building has to draw as
##                 something; the residue is that you learn a foundation eventually
##                 finished, without learning when.
##   anim          a mill's idle loop is harmless; a unit's is not, and this stays a
##                 whitelist-by-deletion rather than a judgement per field.
##
## `remembered` is set so the view can dim it and the panel can say so, and so this
## is visible in a packet capture rather than being inferred from missing fields.
static func _remembered(e: SimEntity) -> Dictionary:
	var d := e.to_snapshot()
	for key in ["hp", "max_hp", "queue", "queue_len", "queue_fraction", "anim",
			"carry_kind", "carry_amount", "task", "amount", "build_fraction"]:
		d.erase(key)
	d["remembered"] = true
	return d


## The tiles an entity covers, for asking the fog about it. A unit is its own tile;
## a footprint is all of it, so a town centre counts as seen from any corner.
static func _rect_of(e: SimEntity) -> Rect2i:
	if e is SimBuilding:
		return (e as SimBuilding).footprint_rect()
	if e is SimResourceNode:
		return (e as SimResourceNode).footprint_rect()
	return Rect2i(e.tile(), Vector2i.ONE)
