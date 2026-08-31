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
## MOBILE IS ASKED OF THE ENTITY (`SimEntity.is_mobile`), not tested as `e is SimUnit`.
## It was the type test until 4.13 gave the world a second moving thing: an arrow in
## flight would have taken the static branch and been sent REMEMBERED to anyone who had
## ever explored the tile it was over, which is a live commentary on where a battle is
## happening, drawn through the fog.
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
		# A GARRISONED UNIT IS NOT ON THE WIRE AT ALL (PLAN.md 4.8), not even to its own
		# owner. That is what "removed from the world map" means in IDEA.md 4.8, and
		# doing it here rather than in the view buys three things for one line:
		# `GameView`'s forget pass releases the sprite, its `retain_only` pass drops the
		# unit from the selection, and `ClientFog` stops lighting a circle around a unit
		# that is indoors. A view-side "draw it invisibly" would have had to do all three
		# by hand and would have left it tappable.
		#
		# The building reports it instead -- `garrison_count` and `garrison` on
		# `SimBuilding.to_snapshot()` -- which is also the only way the client could
		# learn about it, since it has no entity to attach the fact to.
		if e is SimUnit and (e as SimUnit).garrisoned_in != 0:
			continue
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
			# WHOSE SIDE THEY ARE ON (2026-08-31). Sent for the same reason `colour` is
			# and read for a harder one: the client decides what a tap on an entity
			# OFFERS, and `Diplomacy.is_enemy_fact` needs the same team numbers the sim
			# refuses the order by. Out of `state_hash()` beside colour -- fixed at
			# setup, never written again.
			#
			# EVERY PLAYER'S, not just the viewer's. Who is allied with whom is public:
			# it was chosen in a lobby everyone could read, and a client has to know
			# whether the two units fighting in front of it are enemies to draw the
			# question its tap will ask.
			"team": p.team,
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
			# WHAT THIS PLAYER HAS RESEARCHED (9.3), sorted ids. Read by the action
			# panel, to ring a tech that is already bought and drop one whose
			# prerequisite is not, and by the tech-tree page for its third state --
			# which that page's header records as the one thing it could not honestly
			# draw while nothing wrote this field.
			#
			# SENT TO EVERYBODY, not filtered to the owner. It is not a secret: an
			# opponent's upgrades are visible the moment their units land a blow, and
			# every RTS in the genre shows them. Filtering it would also break the
			# single `player_state` shape for no gain.
			"researched": p.researched_ids(),
			# PLAN.md 11.1. Per-player rather than derivable from `winner_id` below:
			# in a match of three or more, a player is knocked out while the match
			# goes on, and this is the only thing that says so.
			"defeated": p.defeated,
			# WHY they are out, as a `SimPlayer.Defeat` (2026-08-30). `defeated` alone
			# told a client the FACT of a forfeit and nothing about it, so the survivors
			# were shown the conquest sentence about an opponent who had unplugged --
			# BUGS.md's "a forfeit is announced as an elimination" -- and were told
			# nothing at all at the moment it happened. One int on a block that is
			# already per-player, rather than a second channel beside `winner_id`.
			"defeat_reason": p.defeat_reason,
		}

	return {
		"tick": w.tick,
		"spawned": [],
		"updated": updated,
		"removed": w.removed_this_tick.duplicate(),
		"player_state": player_state,
		# THE FOG GRID IS NO LONGER SENT (12.1f). It was one byte per tile of the whole
		# board, to every player, every tick -- 36,872 bytes and 68% of the packet on the
		# 8-player board, and a function of the MAP rather than of the match, so no other
		# saving would ever have shrunk it. Half of them were byte-for-byte repeats, since
		# `VisionSystem.VISION_INTERVAL` recomputes every second tick.
		#
		# `ClientFog` computes it instead, from the client's own entities and the map it
		# already has. The SECURITY property does not move: it was never this grid, it is
		# `_entry_for` above, and that still runs here on the server. The grid was only
		# ever a bitmap to paint. `ClientFog`'s header records what that costs and the
		# reliable-delta alternative that was not taken.
		# The outcome (PLAN.md 11.1), which is about the MATCH and not about any one
		# player, so it sits beside `tick` rather than in `player_state`.
		# `match_over` without a `winner_id` is the draw; see SimWorld's own fields.
		# `mode` rides along so the result screen can name the rule that decided it
		# (11.3) without the client having to remember what the lobby picked.
		"mode": int(w.mode),
		"match_over": w.match_over,
		"winner_id": w.winner_id,
		# WHICH SIDE WON (2026-08-31), 0 in a free-for-all. Beside `winner_id` rather
		# than derived from it on the client: a player knocked out early has no way to
		# look up the winner's team, since `player_state` carries a team per player but
		# a defeated client is still being sent one snapshot per tick and should not
		# have to join two fields to learn whether it won.
		"winner_team": w.winner_team,
	}


# ── the wire form (PLAN.md 12.1f) ───────────────────────────────────────────
#
# THE SAME FACTS WITHOUT PAYING FOR THE FIELD NAMES ONCE PER ENTITY.
#
# `var_to_bytes` writes a dictionary key as a length-prefixed string every time it
# appears, and half of every entry was its own field names -- 248 bytes of a town centre's
# 472, measured with `dev_preview/preview_wire_size.tscn -- --fields`. Only 36 entities are
# visible on an 8-player board, so the cost was never the entity count; it was 36 copies of
# the same dozen words.
#
# Entities come in a handful of SHAPES -- a unit, a building, a resource node, and the
# remembered variants with their live fields stripped -- so the names go once per shape per
# snapshot instead of once per entity.
#
# AT THE TRANSPORT BOUNDARY, NOT IN `build()`. The simulation produces a snapshot of
# readable dictionaries and `Net` decides how to encode it. That keeps every other reader
# -- the view, the tests, the previews, the AI -- working in dictionaries, and leaves
# exactly one pair of functions that knows the packing exists. The cost is that a packet
# capture shows a table rather than a self-describing entry per entity; the field names are
# still in it, once.

## Pack for sending. `updated` becomes `tables`, a distinct key so unpacking never has to
## guess which form it is looking at.
static func to_wire(snap: Dictionary) -> Dictionary:
	var entries: Variant = snap.get("updated", null)
	if not (entries is Array):
		return snap                       # nothing to pack, or already packed

	var shapes: Dictionary = {}
	for e in (entries as Array):
		var entry: Dictionary = e
		var keys: Array = entry.keys()
		# SORTED, so one shape always packs to one table rather than to several that
		# differ only in the order their fields happened to be written.
		keys.sort()
		var signature := ",".join(keys)
		if not shapes.has(signature):
			shapes[signature] = {"keys": keys, "rows": []}
		var row: Array = []
		for k in keys:
			row.append(entry[k])
		(shapes[signature]["rows"] as Array).append(row)

	var out := snap.duplicate()
	out.erase("updated")
	out["tables"] = shapes.values()
	return out


## Unpack on arrival. A snapshot with no `tables` is passed through untouched, so a test or
## a preview can hand a plain one straight to `snapshot_received` without going through the
## transport at all.
static func from_wire(snap: Dictionary) -> Dictionary:
	if not snap.has("tables"):
		return snap

	var updated: Array[Dictionary] = []
	for t in (snap["tables"] as Array):
		var table: Dictionary = t
		var keys: Array = table.get("keys", [])
		for r in (table.get("rows", []) as Array):
			var row: Array = r
			var entry: Dictionary = {}
			for i in range(mini(keys.size(), row.size())):
				entry[keys[i]] = row[i]
			updated.append(entry)

	var out := snap.duplicate()
	out.erase("tables")
	out["updated"] = updated
	return out


## What `viewer` is told about `e` this tick: its full snapshot, a remembered
## version of it, or {} for "not sent".
static func _entry_for(w: SimWorld, viewer: SimPlayer, e: SimEntity) -> Dictionary:
	if viewer == null or viewer.vision.is_empty():
		return e.to_snapshot()          # no fog in this world; see SimPlayer.vision
	if e.owner_id == viewer.id:
		return e.to_snapshot()

	var rect := _rect_of(e)
	if VisionSystem.can_see_rect(w, viewer, rect):
		return _without_the_rally_point(e.to_snapshot())
	if e.is_mobile():
		return {}                       # mobile: its position is what it would leak
	if not e.alive:
		return {}                       # see the header's known simplification
	if VisionSystem.has_explored_rect(w, viewer, rect):
		return _remembered(e)
	return {}


## A building's rally point BLANKED, for an entry going to anybody but its owner.
##
## Where an enemy is massing their army is not a fact about the world -- it is their
## INTENTION, and the one piece of information on the wire that is. Everything else
## `_entry_for` sends about a visible enemy building is something you could see by
## looking at it; a flag on a tile three screens away is not.
##
## BLANKED RATHER THAN ERASED, which is the whole reason this is a function and not a
## `d.erase()`. Erasing would give own buildings and enemy buildings different field
## sets, and `to_wire`'s shape tables (12.1f) group `updated` by sorted field names --
## so every building in the game would split into two shapes and cost more than the
## Vector2i it saved. `SimBuilding.to_snapshot`'s own note records that trade for
## `facing`.
##
## Not applied to `_remembered` below, which erases the key outright: a remembered entry
## is already its own shape, having dropped a dozen other fields.
static func _without_the_rally_point(d: Dictionary) -> Dictionary:
	if d.has("waypoint"):
		d["waypoint"] = SimBuilding.NO_WAYPOINT
	return d


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
##   garrison / garrison_count
##                 how many units are in the enemy castle you last saw an hour ago,
##                 and which units they are, is the same class of fact as their
##                 production queue and a better one to have: it is the difference
##                 between a tower worth walking past and one that will shoot for 18.
##                 Both go, not just the roster -- a headcount alone still prices the
##                 shot, because the bonus is per occupant.
##   waypoint      an enemy's rally point is their INTENTION, and the only such thing on
##                 the wire. Erased here and *blanked* for a visible enemy building
##                 (`_without_the_rally_point`) -- two mechanisms because a remembered
##                 entry is already its own wire shape and a live one must not become
##                 a second one.
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
			"carry_kind", "carry_amount", "task", "amount", "build_fraction",
			"garrison", "garrison_count", "waypoint"]:
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
