## Client-side root of the view layer (PLAN.md 6.3, 8). Turns a snapshot
## Dictionary (PLAN.md 7.2) into pooled EntityView updates and drives their
## interpolation every frame. Never touches SimWorld -- everything it knows
## comes from apply_snapshot().
class_name GameView
extends Node2D

## What tapping something should lead to (PLAN.md 4.5): NONE clears the
## selection, SELECT reselects (own unit, or own building with nothing to send
## it), GATHER/BUILD/MOVE/ATTACK are the four orders a tap can issue.
enum TapAction { NONE, SELECT, GATHER, BUILD, MOVE, ATTACK }

## Forces a unit adjacent to a building to Y-sort after it (see
## apply_snapshot()), regardless of how the footprint-corner math alone would
## have compared them. Larger than any real building's own sort offset could
## ever be (the biggest MVP footprint, the wonder's 14x29, projects to a few
## hundred pixels at most), so it always wins rather than merely tilting the
## odds.
const _ADJACENT_TO_BUILDING_BONUS := 100000.0

var pool: EntityViewPool = EntityViewPool.new()
var terrain: TerrainLayer = TerrainLayer.new()
var fog: FogOverlay = FogOverlay.new()

## The fog this client works out for itself (12.1f), instead of being sent it every tick.
## Null until `build_terrain()` gives it a board -- a snapshot with no board draws unfogged,
## which is what an empty grid has always meant.
var client_fog: ClientFog = null

## Whose fog to compute. Set by `GameScene` from `Net.local_player_id()`; 0 means nobody's,
## which reveals nothing and is the right answer for a view with no session behind it.
var local_player_id: int = 0
var selection: Selection = Selection.new()

var _last_tick: int = -1

## What GAIA gets: no age skin and no player tint. Owner 0 is nobody, and
## colours.json's note is explicit that the tint must key off who owns a thing
## rather than off whether its art carries a playercolor mask -- 0 A.D.'s sheep
## declares one and is still nobody's sheep.
const _NEUTRAL_SKIN := {"age": 0, "colour": -1,
		"advancing_to": 0, "advance_ticks": 0, "advance_total_ticks": 0}

## owner_id -> {age, colour}, refreshed from every snapshot's `player_state`
## (SnapshotSystem carries both). This is the whole of PLAN.md 2.7.1's skin key
## on the client: age re-skins a standing building in place as its owner
## advances, and colour picks which of a unit's eight baked atlases to draw.
## Neither is sim state the view may reach for -- both arrive on the wire.
var _player_skins: Dictionary = {}

## owner_id -> {kind: amount}, from the same `player_state` block. The client's only
## knowledge of what it can afford; see `_read_player_skins`.
var _player_stock: Dictionary = {}

## Last known snapshot facts per entity, keyed by id: {tile, owner_id, def_id,
## hp, max_hp, footprint}. Kept because picking and the detail panel both need to
## answer questions about an entity that the *view* nodes do not carry -- who owns
## it, what it is called, how hurt it is -- and the view may not reach into the sim
## to ask (PLAN.md 4).
var _facts: Dictionary = {}


func _ready() -> void:
	# Terrain first: it is a sibling of the entity pool, not a parent, so draw
	# order between the two is tree order and the ground is always underneath.
	add_child(terrain)

	# Y-sort the entities among themselves (PLAN.md 3.1). The engine keys off each
	# child's position.y, which is why apply_snapshot() positions a view at its
	# FRONT tile and pushes the art back with draw_offset -- see
	# Iso.footprint_sort_offset for why a footprint cannot sort by its centre.
	pool.y_sort_enabled = true
	add_child(pool)

	# LAST, so it draws over the ground AND over the entities standing on it (2.5).
	# A remembered building in explored territory is dimmed by the same wash that
	# dims the grass it stands on, which is the whole look; putting the fog under the
	# pool would leave it bright and floating in the dark.
	add_child(fog)


## Hand the view the map to draw. Terrain bytes, not a SimMap: the view layer
## never holds a reference into the simulation (PLAN.md 4), and this is also the
## shape a networked client gets its map in.
func build_terrain(size: Vector2i, terrain_bytes: PackedByteArray) -> void:
	terrain.build(size, terrain_bytes)
	# Sized off the same grid, so the two can never disagree about where tile (0,0)
	# is -- both align themselves against Iso rather than against each other.
	fog.build(size)
	# And the fog this client COMPUTES (12.1f), on the same grid for the same reason.
	# Created here rather than at construction because this is the moment the board is
	# known, and a fog with no board is what "no fog" means.
	client_fog = ClientFog.new()
	client_fog.setup(size)


func apply_snapshot(snap: Dictionary) -> void:
	_last_tick = int(snap.get("tick", _last_tick))
	var updated: Array = snap.get("updated", [])

	# BEFORE the entity loop, not after: an entity spawning this tick resolves its
	# atlas the first time it draws, and resolving it against a stale (or absent)
	# skin would render one frame of the wrong player's colour -- which, colour
	# being the only thing telling players apart, reads as the wrong player's unit.
	_read_player_skins(snap)

	# Gathered up front so a unit's adjacency check below (any tile order)
	# never depends on whether its own entry happened to arrive before or
	# after the building's in this snapshot.
	#
	# `phase` is what tells a BUILDING from anything else, not `footprint`. It used
	# to be footprint, which was true for exactly as long as buildings were the only
	# multi-tile thing -- resource nodes carry one too since 2026-08-17, and the
	# sort lift must stay buildings-only or a unit gets lifted in front of a rock.
	var building_rects: Array[Rect2i] = []
	# Occluders are a SUPERSET of those: buildings plus resource nodes, each with
	# how wide its art is (`Occlusion.column_pad_for`). The sort lift above must
	# stay buildings-only -- a one-tile tree sorts correctly on its own and lifting
	# units in front of it would put them on top of the canopy -- but a tree or a
	# 244 px gold seam hides whatever stands behind it just as a wall does, which is
	# the project owner's report of 2026-08-17.
	var occluders: Array[Dictionary] = []
	for entry in updated:
		# ASKED OF THE REGISTRY, not inferred from which fields the entry happens to have.
		# This used to test `entry.has("footprint")`, which stopped meaning anything the
		# moment 12.1f took `footprint` off the wire -- every entry then looked like a unit
		# and nothing occluded anything. The same reasoning `_facts`'s own `is_unit`
		# already gives for not guessing a kind from a snapshot's shape.
		if GameDataRegistry.unit(StringName(entry.get("def_id", &""))) != null:
			continue                  # a unit; it occludes nothing and lifts nothing
		var centre_tile: Vector2i = _sub_pos(entry) / SimWorld.SUBTILE
		var fp := _footprint_of(entry)
		var rect := Rect2i(centre_tile - fp / 2, fp)
		if entry.has("phase"):
			building_rects.append(rect)
			occluders.append({"rect": rect, "pad": 1, "reach": Occlusion.BEHIND_TILES})
		else:
			# Both numbers come off the node's own art. The band needs only whatever
			# OVERHANGS the footprint -- 1 for a fitted 4x4 seam, 3 for an oak, whose
			# canopy is 232 px above a trunk that really does stand on one tile --
			# and the reach is how far up-screen the sprite gets, which for the flat
			# gold seam is one tile and for a tree is the full five.
			var ph := GameDataRegistry.placeholder_for(_visual_id_of(entry))
			occluders.append({"rect": rect,
					"pad": Occlusion.column_pad_for(ph.footprint_m, fp),
					"reach": Occlusion.reach_for(ph.height_m)})

	# Ids mentioned by this snapshot, for the forget pass after the loop.
	var seen: Dictionary = {}

	for entry in updated:
		var id := int(entry.get("id", 0))
		seen[id] = true
		var view := pool.get_view(id)
		var is_new := view == null
		if is_new:
			view = pool.acquire(id, _visual_id_of(entry))
		else:
			# A building changes visual when its phase does -- foundation to complete
			# to rubble are three separate atlases (ASSET_MISSING.md 1.2), not states
			# inside one, so the view has to be re-pointed rather than just redrawn.
			var wanted := _visual_id_of(entry)
			if view.visual_id != wanted:
				view.visual_id = wanted

		var sub_pos := _sub_pos(entry)
		var def_id := StringName(entry.get("def_id", ""))

		# Set every snapshot rather than only on spawn: a player advancing an age
		# re-skins their standing buildings in place (PLAN.md 2.7 item 2), and the
		# only signal of that is this value changing. The setters no-op when it
		# has not, so this costs a comparison per entity per tick.
		var skin: Dictionary = _player_skins.get(int(entry.get("owner_id", 0)), _NEUTRAL_SKIN)
		view.set_skin(int(skin["age"]), int(skin["colour"]))

		# The node goes where the entity SORTS, the art goes where the entity IS.
		# For everything 1x1 those are the same point and the offset is zero.
		var sort_offset := Iso.footprint_sort_offset(_footprint_of(entry))
		# A single sort point per building (3.1, the building's own front
		# corner) only compares fairly against a unit standing right at that
		# corner. A worker beside the MIDDLE of a large building's long south
		# edge is, by that same point, several tiles short in projected depth --
		# not a tie, a genuine-looking gap -- so it sorts behind the whole
		# building despite plainly standing in front of it. Found live sending
		# the five starting villagers to gather by the town centre and watching
		# returners clip at drop-off.
		#
		# The first cure was a blanket one: ANY unit touching a footprint drew in
		# front of it. That fixed drop-off and produced something worse --
		# villagers on the far side standing on the roof, reported with a
		# screenshot 2026-08-16. The lift is now DIRECTIONAL: only a unit past
		# the building's east or south extent, the two directions that project
		# down-screen, is pulled in front. Everything behind sorts naturally, is
		# genuinely hidden, and gets an outline instead (see _refresh_occlusion).
		var tile := Vector2i(sub_pos / SimWorld.SUBTILE)
		if not entry.has("footprint") and _in_front_of_any(tile, building_rects):
			sort_offset.y += _ADJACENT_TO_BUILDING_BONUS
		# A CHANGE OF SORT OFFSET IS A DISCONTINUITY, NOT A MOVEMENT, and gliding
		# across one throws the sprite off the screen.
		#
		# `draw_offset` cancels `sort_offset` exactly -- but only the node's POSITION
		# is interpolated, while `draw_offset` applies the instant it is set. So on
		# the tick a villager steps into the band in front of a building, its target
		# position jumps by `_ADJACENT_TO_BUILDING_BONUS` while its draw offset has
		# already absorbed the whole 100,000 px. For one interpolation window the two
		# do not cancel, and the villager is drawn a screen and a half up before
		# sliding back down into place. That is the "villagers randomly teleport from
		# the outer edges of the screen" the project owner reported on 2026-08-20.
		#
		# Snapping costs one tick of glide on the single step that crosses the
		# boundary -- a tenth of a second over one tile -- against a sprite that
		# otherwise leaves the screen entirely.
		var offset := -sort_offset
		var jumped := not is_new and view.draw_offset != offset
		view.draw_offset = offset
		var target := Iso.sub_to_world(sub_pos) + sort_offset
		if is_new or jumped:
			view.snap_to(target)
		else:
			view.set_target_transform(target, _last_tick)

		var max_hp := float(entry.get("max_hp", 0))
		if max_hp > 0.0:
			view.set_health_dot(float(entry.get("hp", 0)) / max_hp)

		var alive := bool(entry.get("alive", true))
		view.set_dead(not alive)
		# Two kinds of remains count down to nothing: a unit's corpse over its
		# last 10 s (4.7) and a building's rubble over the last 10 s of the minute
		# it stands for (5.5, amended 2026-08-16). Each carries its own key, so
		# the wire format says WHICH it is rather than making a corpse of a
		# building, and both ride the same alpha ramp here.
		if entry.has("corpse_ticks_left") and int(entry["corpse_ticks_left"]) >= 0:
			view.set_corpse_fade(clampf(
					float(entry["corpse_ticks_left"]) / float(SimUnit.CORPSE_FADE_TICKS), 0.0, 1.0))
		elif entry.has("rubble_ticks_left") and int(entry["rubble_ticks_left"]) >= 0:
			view.set_corpse_fade(clampf(
					float(entry["rubble_ticks_left"]) / float(SimBuilding.RUBBLE_FADE_TICKS),
					0.0, 1.0))
		else:
			view.set_corpse_fade(1.0)
		if entry.has("anim"):
			# Iso.sim_facing_to_sprite, never the raw number -- see its header.
			view.play_anim(StringName(entry["anim"]),
					Iso.sim_facing_to_sprite(int(entry.get("facing", 0))))

		_facts[id] = {
			"id": id,
			"tile": Vector2i(sub_pos / SimWorld.SUBTILE),
			"owner_id": int(entry.get("owner_id", 0)),
			"def_id": def_id,
			"hp": int(entry.get("hp", 0)),
			"max_hp": int(max_hp),
			"alive": alive,
			"footprint": _footprint_of(entry),
			# Asked of the registry rather than guessed from the snapshot's shape.
			# Inferring "no phase field means a unit" would call a resource node a
			# unit, and 3.6 would then send move orders naming trees.
			"is_unit": GameDataRegistry.unit(def_id) != null,
			# Present only on units (SimUnit.to_snapshot); absent on a building or
			# resource node entry, where it defaults to IDLE and is never read since
			# _is_own_living_villager() has already filtered those out by is_unit.
			"task": int(entry.get("task", SimUnit.Task.IDLE)),
			# Present only on buildings (SimBuilding.to_snapshot); 0 elsewhere, which
			# reads correctly as "nothing queued" rather than needing its own guard.
			"queue_len": int(entry.get("queue_len", 0)),
			"queue_fraction": float(entry.get("queue_fraction", 0.0)),
			# The queued def ids, so each queue slot can crop that unit's own
			# portrait. Converted to StringName here rather than left as the
			# wire's Strings, because everything downstream compares against
			# StringName literals and a String never matches one.
			"queue": _names(entry.get("queue", [])),
			# Present only on buildings; SimBuilding.Phase.COMPLETE elsewhere, so a
			# unit or resource node always reads as "not something to build" without
			# its own guard (4.5's build-assist tap needs to tell a foundation from
			# a finished building).
			"phase": int(entry.get("phase", SimBuilding.Phase.COMPLETE)),
			# Fog of war (2.5): this is a static the player REMEMBERS rather than one
			# they can currently see, so the server sent it stripped of everything
			# live (SnapshotSystem._remembered). Carried into the facts so the panel
			# can say so -- hp arrives as 0/0, which SelectionPanel already reads as
			# "no health bar" without needing to know why.
			"remembered": bool(entry.get("remembered", false)),
		}
		# A corpse or rubble is unselectable (4.7, 5.5) even if it was selected
		# the tick it died -- `alive` wins over a selection built before this.
		view.set_selected(alive and selection.contains(id))

	# OUT OF SIGHT IS OUT OF MIND (2.5). Anything the view was holding that this
	# snapshot did not mention is something the server has stopped telling us about --
	# an enemy unit that walked back into the fog -- so its view is released and its
	# facts are dropped. Dropping the FACTS is the half that matters: a stale entry
	# left in `_facts` would still answer `pick()` and still draw a blip on the
	# minimap, which would make the fog a purely cosmetic overlay with the position
	# leaking out the side.
	#
	# ABSENCE IS THE SIGNAL because `updated` currently carries everything the player
	# may see, every tick (SnapshotSystem's own header). The obvious alternative --
	# the server naming what has become hidden -- is worse than it looks: a list of
	# hidden ids tells the client how many entities exist and which ids are taken, so
	# an enemy's unit COUNT could be read straight off the wire. That is the same class
	# of leak the filter exists to close. When 7.2's real delta lands, "not mentioned"
	# will start to mean "unchanged" and this needs a per-entity signal instead -- one
	# that says "you have lost sight of X" only for entities the client already knew
	# about, and never enumerates the rest.
	for known in _facts.keys():
		if not seen.has(known):
			pool.release(int(known))
			_facts.erase(known)

	for id in snap.get("removed", []):
		pool.release(int(id))
		_facts.erase(int(id))

	# A selection holding a unit that has just died -- or fully despawned --
	# would build an order naming an entity the sim rejects, and the player
	# would see nothing happen at all.
	var selectable: Array[int] = []
	for fid in _facts:
		if bool(_facts[fid].get("alive", true)):
			selectable.append(int(fid))
	selection.retain_only(selectable)

	# Last, over the finished facts: who is standing behind what depends on where
	# everything ENDED UP this snapshot, and doing it inside the entity loop would
	# test half the units against a stale set of occluders.
	_refresh_occlusion(occluders)

	# The fog itself (2.5), COMPUTED HERE rather than read off the wire (12.1f). Over the
	# finished facts, so it sees where everything ended up this snapshot -- the same
	# reason the occlusion pass above waits until now.
	#
	# `client_fog` stays null for a snapshot that has no board behind it: a unit test, or
	# a replay from before 2.5. Both then draw an unfogged map rather than a black one,
	# which is what an empty grid has always meant.
	# From `updated`, the raw wire entries -- NOT from `_facts`, which has already divided
	# `pos` down into whole tiles and dropped it. See `ClientFog.apply`.
	if client_fog != null:
		client_fog.apply(updated, local_player_id)
		fog.apply(client_fog.cells)


## Facts about one entity, or {} if it is not currently in view.
func facts_for(id: int) -> Dictionary:
	return _facts.get(id, {})


## The skin a player's entities draw with, as {age, colour}. Gaia and any player
## not in the last snapshot get the neutral skin -- unaged and untinted -- rather
## than player 1's, which is what an `int` default of 0 would silently have meant.
func skin_for(owner_id: int) -> Dictionary:
	return _player_skins.get(owner_id, _NEUTRAL_SKIN)


## The local player's age, for the HUD and for gating the action menus (9.1,
## UI_Design.md). 1 when they are not in the snapshot yet, since age 1 is where
## every match starts and an unaged menu offers nothing at all.
func age_of(owner_id: int) -> int:
	return maxi(1, int(skin_for(owner_id).get("age", 1)))


## How far through an age advance a player is, 0.0 to 1.0, or 0.0 when they are
## not advancing. The ONE place the sim's int ticks become a float -- the ring is
## drawn from this and nothing else reads it, which is what keeps the fraction on
## the view side of the boundary (PLAN.md 7.1).
func age_progress_of(owner_id: int) -> float:
	var skin := skin_for(owner_id)
	if int(skin.get("advancing_to", 0)) <= 0:
		return 0.0
	var total := int(skin.get("advance_total_ticks", 0))
	if total <= 0:
		return 0.0
	return clampf(float(skin.get("advance_ticks", 0)) / float(total), 0.0, 1.0)


## True while an advance is in flight, which is NOT the same as progress > 0 --
## the first tick of a 100-tick research is progress 0.01, but the tick it starts
## it is exactly 0.0 and the badge still has to stop offering another advance.
func is_advancing(owner_id: int) -> bool:
	return int(skin_for(owner_id).get("advancing_to", 0)) > 0


func _read_player_skins(snap: Dictionary) -> void:
	var state: Dictionary = snap.get("player_state", {})
	if state.is_empty():
		return          # not every snapshot in a test carries one; keep the last
	for pid in state:
		var ps: Dictionary = state[pid]
		_player_skins[int(pid)] = {
			"age": int(ps.get("age", 1)),
			"colour": int(ps.get("colour", 0)),
			# Advancement rides here too rather than in its own map: it is
			# per-player state arriving in the same block, and keeping one
			# dictionary means there is one place a player's row can go stale.
			"advancing_to": int(ps.get("advancing_to", 0)),
			"advance_ticks": int(ps.get("advance_ticks", 0)),
			"advance_total_ticks": int(ps.get("advance_total_ticks", 0)),
		}
		# Stock is kept apart from the skin because it is not one: the skin is two
		# axes that decide which atlas to draw, and this is the treasury. Cached at
		# all because a CLIENT has no `SimWorld` to ask what it can afford, and the
		# placement ghost has to answer that question (PLAN.md 12.1b).
		_player_stock[int(pid)] = (ps.get("stock", {}) as Dictionary).duplicate()


## What a player holds, as the last snapshot reported it. Empty for a player not in it.
##
## A copy: the placement ghost reads this every time the finger moves and must not be
## able to spend the view's own bookkeeping.
func stock_of(owner_id: int) -> Dictionary:
	return (_player_stock.get(owner_id, {}) as Dictionary).duplicate()


## Every entity's facts, keyed by id. A copy, for the same reason
## `Selection.current()` hands one out -- the minimap (8.2a) redraws its
## blips from this every snapshot and must not be able to mutate the view's
## own bookkeeping while doing it.
func all_facts() -> Dictionary:
	return _facts.duplicate()


## World position of `owner`'s first alive entity matching `def_id`, or null
## if they have none (PLAN.md 3.4: double-tap-minimap centres on the
## player's own Town Centre). Sorted by id, same determinism reason as
## `SimWorld.nearest_drop_off()` -- two clients must pick the same one.
func owned_entity_position(owner: int, def_id: StringName) -> Variant:
	var ids := _facts.keys()
	ids.sort()
	for id in ids:
		var f: Dictionary = _facts[id]
		if int(f.get("owner_id", -1)) == owner and StringName(f.get("def_id", &"")) == def_id \
				and bool(f.get("alive", true)):
			return Iso.tile_centre_to_world(f["tile"])
	return null


## Replace the selection and repaint the rings.
func select(ids: Array[int]) -> void:
	for id in selection.current():
		var previous := pool.get_view(id)
		if previous != null:
			previous.set_selected(false)
	for id in selection.set_selection(ids):
		var view := pool.get_view(id)
		if view != null:
			view.set_selected(true)


## The entity at a point in this node's LOCAL space, or 0 (PLAN.md 4.3).
##
## Local, not screen: the caller undoes the camera once, and picking does not have
## to know a camera exists.
##
## Picks by tile rather than by sprite bounds. A tap is a fingertip, not a
## pixel, and the tall art makes bounds misleading -- a 10 m tree's sprite covers
## the six tiles behind it, so bounds-picking would select the tree when the player
## clearly tapped the ground in front of it. The tile under the finger is what the
## player is pointing at, and it is also what an order is expressed in.
##
## `owner` restricts the pick to one player's things; pass 0 to pick anything.
## Units win ties, because a villager standing on a tree's tile is the thing worth
## tapping and the tree is not going anywhere.
func pick(local: Vector2, owner: int = 0) -> int:
	var tile := Iso.tile_at(local)
	var best := 0
	var best_is_unit := false
	for id in _facts:
		var f: Dictionary = _facts[id]
		if not bool(f.get("alive", true)):
			continue          # a corpse or rubble is unselectable (4.7, 5.5)
		if owner != 0 and int(f["owner_id"]) != owner:
			continue
		if not _covers(f, tile):
			continue
		var is_unit: bool = f["is_unit"]
		if best == 0 or (is_unit and not best_is_unit):
			best = int(id)
			best_is_unit = is_unit
	return best


## Every unit of `owner` standing inside a box, in LOCAL space (PLAN.md 8.3).
##
## **Units only, and only the owner's.** Dragging a box across your settlement and
## catching the town centre, four trees and a deer in it is not what anyone means
## by a box select; every RTS filters this way and the player expects it.
##
## Tested against each unit's ground point rather than its sprite, for the same
## reason picking goes by tile: a sprite is mostly air above the tile it stands on,
## so a box drawn over empty grass would catch whatever tall thing was leaning into
## it from behind.
func units_in_box(box: Rect2, owner: int) -> Array[int]:
	var found: Array[int] = []
	var ids := _facts.keys()
	# Sorted so a box that catches more than MAX_SELECTED takes the same units on
	# every machine, rather than whichever the Dictionary happened to yield first.
	ids.sort()
	for id in ids:
		var f: Dictionary = _facts[id]
		if not bool(f.get("alive", true)):
			continue          # a corpse is unselectable (4.7)
		if not bool(f["is_unit"]) or int(f["owner_id"]) != owner:
			continue
		if box.has_point(Iso.tile_centre_to_world(f["tile"])):
			found.append(int(id))
	return found


## What a tap on `id` (0 for empty ground) should do (PLAN.md 4.5), given who is
## tapping and whether they have units that could be sent somewhere.
## `GameScene` turns the answer into the actual command and flash; kept here
## because it is pure fact lookup over `_facts`, the same division of labour as
## `pick()` and `movable_selection()`.
##
## An own UNIT always wins over an order, so re-selecting can never accidentally
## send the current selection walking onto the very unit being picked. An own
## INCOMPLETE building is the one case that inverts that: with builders
## selected, the tap sends them to help rather than reselecting the
## foundation, since that is the whole reason to tap it while builders are
## selected -- with nothing selected it still just selects, so the panel and
## its training row stay reachable when there is nothing to send.
func tap_action(id: int, owner: int, has_movable_selection: bool) -> TapAction:
	if id == 0:
		return TapAction.MOVE if has_movable_selection else TapAction.NONE

	var f := facts_for(id)
	if f.is_empty():
		return TapAction.MOVE if has_movable_selection else TapAction.NONE

	if int(f["owner_id"]) == owner:
		if bool(f["is_unit"]):
			return TapAction.SELECT
		if has_movable_selection and int(f["phase"]) != SimBuilding.Phase.COMPLETE:
			return TapAction.BUILD
		# A FIELD is our own building and is still a thing to harvest (6.5). With
		# workers in hand, tapping it sends them to farm it -- which is the whole
		# point of having built it, and what the project owner expected and did
		# not get (2026-08-16: "clicking them with a villager selected selects the
		# field instead of gathering on it"). With nothing selected it reselects,
		# so its panel and health stay reachable.
		if has_movable_selection and _is_gatherable_building(f):
			return TapAction.GATHER
		return TapAction.SELECT

	if has_movable_selection and not bool(f["is_unit"]) \
			and GameDataRegistry.resource_def(StringName(f["def_id"])) != null:
		return TapAction.GATHER

	# Somebody else's, and not gaia's: tapping it attacks it (4.13). Checked
	# AFTER the resource branch, so a tree stays a thing to chop rather than a
	# thing to shoot -- gaia owns both, and only the resource def tells them
	# apart. With nothing selected it still just reselects, so an enemy's panel
	# and health stay readable without an army in hand.
	if int(f["owner_id"]) != 0:
		return TapAction.ATTACK if has_movable_selection else TapAction.SELECT

	return TapAction.MOVE if has_movable_selection else TapAction.NONE


## Whether these facts describe a COMPLETE building that yields something -- a
## field, and nothing else today. Asked of the registry rather than inferred from
## the snapshot, the same division `_facts`'s own `is_unit` already draws: the
## wire carries what a thing IS, and the seam answers what it can do.
func _is_gatherable_building(f: Dictionary) -> bool:
	if int(f.get("phase", -1)) != SimBuilding.Phase.COMPLETE:
		return false
	var bd: BuildingDef = GameDataRegistry.building(StringName(f.get("def_id", &"")))
	return bd != null and bd.is_gatherable()


## The selected entities that can actually be given a move order (PLAN.md 3.6).
##
## Filtered rather than passed whole: `MoveCommand.validate()` rejects the ENTIRE
## command if any id is not a unit, so a selection containing the town centre would
## silently cancel the move for the villagers selected alongside it.
func movable_selection() -> Array[int]:
	var movable: Array[int] = []
	for id in selection.current():
		if bool(_facts.get(id, {}).get("is_unit", false)):
			movable.append(id)
	return movable


## Currently alive members of a control group (PLAN.md 10.1/10.5) -- membership
## itself is server-authoritative (`SimPlayer.control_groups`), but whether a
## given member is still alive and in view is exactly what `_facts` already
## answers for ordinary selection, so control groups reuse it rather than
## asking the sim again.
func control_group_alive_members(member_ids: Array) -> Array[int]:
	var alive: Array[int] = []
	for id in member_ids:
		if bool(_facts.get(int(id), {}).get("alive", false)):
			alive.append(int(id))
	return alive


## Icon def_id (most-represented among currently alive members, 10.4) and live
## count for a control group. Icon is `&""` once every member has died --
## `ControlGroupsHud` reads that as "draw an empty circle" rather than needing
## a separate emptied signal.
func control_group_summary(member_ids: Array) -> Dictionary:
	var tally: Dictionary = {}          # StringName def_id -> int count
	var alive_count := 0
	for id in member_ids:
		var f: Dictionary = _facts.get(int(id), {})
		if f.is_empty() or not bool(f.get("alive", true)):
			continue
		alive_count += 1
		var def_id: StringName = f.get("def_id", &"")
		tally[def_id] = int(tally.get(def_id, 0)) + 1

	var best_def: StringName = &""
	var best_n := 0
	var keys := tally.keys()
	keys.sort()          # deterministic tie-break, same convention as nearest_drop_off
	for def_id in keys:
		if int(tally[def_id]) > best_n:
			best_def = def_id
			best_n = int(tally[def_id])

	return {"icon": best_def, "count": alive_count}


## World-space centre of a control group's currently alive members, or null if
## none are left. "Centre on the area with most units" (10.5) is just their
## average position for MVP's scale -- a group clustered in one spot centres
## there, and real clustering is not worth building until a group can actually
## be split across two fights at once.
func control_group_centre(member_ids: Array) -> Variant:
	var sum := Vector2.ZERO
	var n := 0
	for id in member_ids:
		var f: Dictionary = _facts.get(int(id), {})
		if f.is_empty() or not bool(f.get("alive", true)):
			continue
		sum += Iso.tile_centre_to_world(f["tile"])
		n += 1
	return sum / float(n) if n > 0 else null


## Whether `f` is one of `owner`'s living VILLAGERS -- what the idle badge counts
## and walks (PLAN.md 7.1).
##
## Villagers, not units. This counted any unit until the project owner corrected
## it (2026-08-17): the age header's badge is idle villagers, and the resource
## panel's bottom row is units-on-map against the population limit. Those are two
## different questions with two different readers, and the old shared
## `villager_counts()` answered neither of them properly -- it reported
## idle-vs-total units to both.
##
## "Villager" is `UnitDef.is_worker()`, i.e. a unit with a gather rate, rather
## than `def_id == &"unit.villager"`. Same reason `_is_gatherable_building()`
## asks the def instead of naming the field: the asset seam is the only place
## filenames live, and this is the same rule applied to ids.
func _is_own_living_villager(f: Dictionary, owner: int) -> bool:
	if not bool(f.get("alive", true)):
		return false          # a corpse (4.7) is not a villager to count any more
	if not bool(f.get("is_unit", false)) or int(f.get("owner_id", 0)) != owner:
		return false
	var ud: UnitDef = GameDataRegistry.unit(StringName(f.get("def_id", &"")))
	return ud != null and ud.is_worker()


## How many of `owner`'s villagers are standing idle, for the badge's number.
func idle_villager_count(owner: int) -> int:
	return idle_villager_ids(owner).size()


## `owner`'s idle villagers, in ascending id order.
##
## Sorted by id, the same determinism `owned_entity_position()` and
## `SimWorld.nearest_drop_off()` keep: the walk through them has to visit the
## same villagers in the same order every tap, and `_facts` is a Dictionary whose
## key order is insertion order -- i.e. whatever order entities happened to
## first appear in a snapshot.
func idle_villager_ids(owner: int) -> Array[int]:
	var ids: Array[int] = []
	for id in _facts:
		var f: Dictionary = _facts[id]
		if _is_own_living_villager(f, owner) and int(f.get("task", -1)) == SimUnit.Task.IDLE:
			ids.append(int(id))
	ids.sort()
	return ids


## The idle villager after `after_id`, wrapping round to the first, or 0 when
## `owner` has none at all (PLAN.md 7.1 -- tap the badge to walk them).
##
## Takes the previous id rather than an index into the list, because the list
## itself changes under the player between taps: a villager they visited five
## seconds ago may have been given a job, and an index would then point at a
## different unit than the one it was recorded for. An id is stable, and asking
## for "the next one after it" still lands in the right PLACE in the order even
## once that villager has dropped out of the list entirely.
func next_idle_villager(owner: int, after_id: int) -> int:
	var ids := idle_villager_ids(owner)
	if ids.is_empty():
		return 0
	for id in ids:
		if id > after_id:
			return id
	return ids[0]


func _covers(f: Dictionary, tile: Vector2i) -> bool:
	var footprint: Vector2i = f["footprint"]
	var centre: Vector2i = f["tile"]
	# A footprint's `tile` is its centre; recover the rect it actually holds.
	var origin := centre - footprint / 2
	return Rect2i(origin, footprint).has_point(tile)


## Snapshots carry the entity's DEFINITION id (`unit.villager`); the asset seam is
## keyed by VISUAL id (`vis.villager`). Translating between them is exactly what
## GameDataRegistry is for -- passing def_id straight to the seam resolves to the
## magenta unknown and renders a whole match in placeholder colours without
## reporting anything (found at 2.6).
## `footprint` is present only for buildings (SimBuilding.to_snapshot); units and
## resource nodes stand on one tile, so the default is right for them rather than
## merely safe.
## DERIVED FROM `def_id`, NOT SENT (12.1f). A footprint was 68 bytes of every building and
## resource entry, every tick -- and it is static content the client already has, exactly
## like `vision_range`. A building's comes straight off its def; a resource's is
## `footprint_for_size`, and `size_class` is on the wire already because the view needs it
## to pick a sprite.
##
## Falls back to one tile, which is what a unit is and what an unknown def should look like
## rather than a crash.
## An entry's sub-tile position. One place, because `pos` became a `Vector2i` on the wire
## in 12.1f and three separate readers were unpacking it as `{"x": .., "y": ..}` by hand.
##
## Tolerates the old dictionary shape so a replay or a fixture written against the previous
## format still loads rather than silently reading (0, 0) -- which is precisely the failure
## `ClientFog` shipped with for an afternoon.
func _sub_pos(entry: Dictionary) -> Vector2i:
	var p: Variant = entry.get("pos", Vector2i.ZERO)
	if p is Vector2i:
		return p
	if p is Dictionary:
		return Vector2i(int((p as Dictionary).get("x", 0)), int((p as Dictionary).get("y", 0)))
	return Vector2i.ZERO


func _footprint_of(entry: Dictionary) -> Vector2i:
	var def_id := StringName(entry.get("def_id", &""))
	var building := GameDataRegistry.building(def_id)
	if building != null:
		return building.footprint
	var res := GameDataRegistry.resource_def(def_id)
	if res != null:
		return res.footprint_for_size(int(entry.get("size_class", 0)))
	return Vector2i.ONE


## Whether `tile` is touching a building AND on its camera-facing side, which is
## what earns the sort lift. Touching alone used to be enough and put villagers
## on the roof; `Occlusion.is_in_front` is the direction half of the test.
##
## Orthogonal adjacency only -- a purely diagonal corner touch does not count.
## Sharing an EDGE is what "standing beside it, working on it" looks like, and
## the drop-off clipping this bonus exists for is always an edge case in the
## literal sense.
func _in_front_of_any(tile: Vector2i, rects: Array[Rect2i]) -> bool:
	for r in rects:
		if not Occlusion.is_in_front(tile, r):
			continue
		if r.has_point(tile):
			return true
		var in_x_span := tile.x >= r.position.x and tile.x < r.end.x
		var in_y_span := tile.y >= r.position.y and tile.y < r.end.y
		if in_x_span and (tile.y == r.position.y - 1 or tile.y == r.end.y):
			return true          # touches the north or south edge
		if in_y_span and (tile.x == r.position.x - 1 or tile.x == r.end.x):
			return true          # touches the west or east edge
	return false


## Mark every unit a building is standing in front of, so `EntityView` can draw
## its rim over that building (PLAN.md 3.1). Runs once per snapshot over the
## facts already gathered, rather than per frame: occlusion changes when things
## MOVE, and things move on snapshots.
##
## O(units x buildings), which on this map is a few hundred integer comparisons
## ten times a second. A spatial query would be faster and less obvious; if the
## entity count ever makes this matter, `SimWorld.spatial` is the tool.
##
## Corpses and rubble are skipped: a dead thing behind a building is not
## information the player needs, and outlining the fallen would make a cleared
## battlefield look occupied.
func _refresh_occlusion(occluders: Array[Dictionary]) -> void:
	if occluders.is_empty():
		for id in _facts:
			var v := pool.get_view(int(id))
			if v != null:
				v.occluded = false
		return

	for id in _facts:
		var f: Dictionary = _facts[id]
		var view := pool.get_view(int(id))
		if view == null:
			continue
		if not bool(f.get("is_unit", false)) or not bool(f.get("alive", true)):
			view.occluded = false
			continue

		var tile: Vector2i = f["tile"]
		var hidden := false
		for o in occluders:
			if Occlusion.hides(o["rect"], tile, int(o["pad"]), int(o["reach"])):
				hidden = true
				break
		view.occluded = hidden
		if hidden:
			view.outline_colour = _outline_colour_for(int(f.get("owner_id", 0)))


## The rim colour for an owner: their player colour, so the outline says WHOSE
## unit is back there and not merely that one is. Gaia gets white -- it owns no
## units today, and a wildlife outline in nobody's colour is the honest answer.
func _outline_colour_for(owner_id: int) -> Color:
	var colour := int(skin_for(owner_id).get("colour", -1))
	return GameDataRegistry.colour(colour) if colour >= 0 else Color.WHITE


## A wire list of def ids as StringNames. JSON has no StringName, so anything
## arriving over the network is a String -- and `&"unit.villager" == "unit.villager"`
## is false, so a missed conversion here is a lookup that silently finds nothing.
func _names(raw: Variant) -> Array[StringName]:
	var out: Array[StringName] = []
	if raw is Array:
		for v in raw:
			out.append(StringName(v))
	return out


func _visual_id_of(entry: Dictionary) -> StringName:
	var def_id := StringName(entry.get("def_id", ""))
	# `phase` is present only for buildings and `size_class` only for resource
	# nodes (their own to_snapshot); -1 in either case means "no preference".
	var vis := GameDataRegistry.visual_for(def_id, int(entry.get("phase", -1)),
			int(entry.get("size_class", -1)))
	# Interchangeable looks (visuals.json `variants`) -- four field plots today.
	# Unconditional and free for everything else: an id with no variants returns
	# itself, so this needs no list of which visuals have them.
	return GameDataRegistry.variant_of(vis, _variant_seed(entry))


## Which of an entity's interchangeable looks it gets, as a seed for
## `GameDataRegistry.variant_of()`. Derived from the TILE it stands on, so:
##
##   - it is stable for the entity's whole life, since a building never moves --
##     a `randi()` at spawn would re-roll every time a pooled view was recycled,
##     and a field would change crop by walking the camera away and back;
##   - every client agrees without the choice being sent, because the tile is a
##     fact they all have already. Nothing new rides the snapshot and nothing new
##     enters `state_hash()`;
##   - two neighbouring plots differ, which is the whole point.
##
## The mix is written out in integers rather than calling `hash()`: `hash()` is an
## engine implementation detail, and this has to give the same answer on a phone
## and on a desktop in the same match. The two constants are the usual large odd
## primes from spatial hashing; nothing about them is special beyond being coprime
## with small variant counts.
func _variant_seed(entry: Dictionary) -> int:
	var tile: Vector2i = _sub_pos(entry) / SimWorld.SUBTILE
	return absi(tile.x * 73856093 ^ tile.y * 19349663)


func _process(delta: float) -> void:
	pool.advance_all(delta)
