## Client-side root of the view layer (PLAN.md 6.3, 8). Turns a snapshot
## Dictionary (PLAN.md 7.2) into pooled EntityView updates and drives their
## interpolation every frame. Never touches SimWorld -- everything it knows
## comes from apply_snapshot().
class_name GameView
extends Node2D

## What tapping something should lead to (PLAN.md 4.5): NONE clears the
## selection, SELECT reselects (own unit, or own building with nothing to send
## it), GATHER/BUILD/MOVE/ATTACK are the four orders a tap can issue.
enum TapAction { NONE, SELECT, GATHER, BUILD, MOVE, ATTACK, GARRISON, WAYPOINT }

## Forces a unit adjacent to a building to Y-sort after it (see
## apply_snapshot()), regardless of how the footprint-corner math alone would
## have compared them. Larger than any real building's own sort offset could
## ever be (the biggest MVP footprint, the wonder's 14x29, projects to a few
## hundred pixels at most), so it always wins rather than merely tilting the
## odds.
const _ADJACENT_TO_BUILDING_BONUS := 100000.0

## How far a tap that hit BARE GROUND may reach for a one-tile resource node, measured
## in LOCAL pixels from the middle of that node's artwork (PLAN.md 4.3, added
## 2026-08-23). See the fallback at the end of `pick()`.
##
## 24 px is chosen against the tile, not by feel. Adjacent tile centres are 35.8 px
## apart, so the reach can never cross into the neighbour's centre and steal a tap
## that was unambiguously somewhere else; and the tile diamond is only 16 px tall,
## so up and down -- the two directions where a tile gives the least room and the
## isometric art leans hardest -- it is where the whole gain is.
##
## IN LOCAL SPACE, so it is a fixed WORLD distance and shrinks on screen as the camera
## zooms out. That is the price of `pick()` not knowing a camera exists, which is a
## property worth more than the last few pixels; if zoomed-out tapping is still hard,
## the fix is for `GameScene` to scale this, not for picking to grow a camera.
const TAP_REACH_PX := 24.0

var pool: EntityViewPool = EntityViewPool.new()
var terrain: TerrainLayer = TerrainLayer.new()
var fog: FogOverlay = FogOverlay.new()

## Where shots have landed, for a few seconds each (project owner, 2026-08-28). Pure
## decoration and pure view: see `SpentProjectiles`, which explains why litter that
## nothing can touch has no business being an entity.
var spent: SpentProjectiles = SpentProjectiles.new()

## The fog this client works out for itself (12.1f), instead of being sent it every tick.
## Null until `build_terrain()` gives it a board -- a snapshot with no board draws unfogged,
## which is what an empty grid has always meant.
var client_fog: ClientFog = null

## Whose fog to compute. Set by `GameScene` from `Net.local_player_id()`; 0 means nobody's,
## which reveals nothing and is the right answer for a view with no session behind it.
var local_player_id: int = 0
var selection: Selection = Selection.new()

## Which of visuals.json's `variant_pools` this map draws from -- palms on an island,
## dead wood in the desert. Set by `GameScene` from the map's own `meta.type`, through
## `MapGenerator.pool_name()`.
##
## EMPTY IS A REAL AND COMMON STATE, not a missing setup step: the fixed debug map has
## no `MapData` and every preview and test stands this view up directly. `variant_of()`
## answers those with the general `variants` mix, so nothing has to check.
##
## It is a VIEW fact and it never rides the wire. Every client already knows which map
## it is on, and the tile seed underneath is a pure function of position, so two clients
## agree on which tree stands where without a byte being sent -- the same argument
## `_variant_seed` makes for the seed itself.
var variant_pool: StringName = &""

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

	# BETWEEN the ground and the entities, and NOT y-sorted. A spent arrow is a mark on
	# the dirt: it belongs over the grass and under everything standing on it, including
	# the villager who walks across it. Sorting it among the entities would have arrows
	# drawing over the feet of anyone standing further up the screen, which reads as an
	# arrow stuck in them rather than one lying beyond them.
	add_child(spent)

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
		#
		# A POSITIVE TEST as of 4.13, where it used to be "not a unit". Only a building
		# or a resource node occludes; a unit never did, and the world now contains a
		# third thing -- a projectile -- which the old phrasing would have swept into
		# the else branch below and made an occluder of. Every arrow in flight would
		# have been a one-tile column hiding whatever stood behind it, flickering on
		# and off at the rate the archers were firing.
		var entry_def := StringName(entry.get("def_id", &""))
		if GameDataRegistry.building(entry_def) == null \
				and GameDataRegistry.resource_def(entry_def) == null:
			continue
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
		var footprint := _footprint_of(entry)
		var sort_offset := Iso.footprint_sort_offset(footprint)
		view.ground_m = _ring_ground_m(entry, footprint)
		# A BUILDING'S SELECTION RING TRACES ITS FOOTPRINT (owner, 2026-08-29). Asked
		# of the registry here rather than inferred in the view, which holds a VISUAL
		# id and has no way to tell a house from a deer.
		view.ring_square = GameDataRegistry.building(
				StringName(entry.get("def_id", &""))) != null
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
		# UNITS ONLY, ASKED OF THE REGISTRY. This said `not entry.has("footprint")` and
		# had been dead since 12.1f took `footprint` off the wire -- the same defect, in
		# the same file, that the occluder loop above was fixed for and whose comment
		# says exactly this. Every entry looked like a unit, so every BUILDING was asking
		# `_in_front_of_any` about itself.
		#
		# It stayed harmless only because of the bug immediately below it: a building's
		# own tile is inside its own rect, and the unreachable `has_point` branch meant
		# that answered false. Fixing that made three sort tests fail at once, which is
		# how this one surfaced -- two dead guards had been cancelling out.
		var tile := Vector2i(sub_pos / SimWorld.SUBTILE)
		if GameDataRegistry.unit(def_id) != null and _in_front_of_any(tile, building_rects):
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
		elif entry.has("phase"):
			# A BUILDING, AND SINCE WALLS IT CAN BE TURNED (PLAN.md 5.8). Buildings
			# send no `anim` -- they have one, `static` -- so nothing here used to
			# call `play_anim` for them at all, and their `EntityView` sat on facing 0
			# forever. That was right while every building atlas was `directions: 1`;
			# a wall is baked at eight, and a wall drawn at facing 0 whichever way it
			# was dragged is a wall lying across half its own footprint.
			#
			# Through the SAME conversion a unit uses, so there is still exactly one
			# place that knows the sim and sprite tables run opposite ways.
			view.play_anim(_building_anim(entry),
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
			# WHERE A TAP MAY LAND, which is not the same question as what ground the
			# entity holds -- see ResourceDef.pick_footprints. Read by `_covers` and by
			# nothing else; occlusion, depth sort, the selection ring and placement
			# advice all keep reading `footprint` above, and must, because each of them
			# is asking about the ground.
			"pick_footprint": _pick_footprint_of(entry),
			# Ground point -> middle of the artwork, for the tap fallback in `pick()`.
			"pick_lift": _pick_lift_of(entry),
			# Asked of the registry rather than guessed from the snapshot's shape.
			# Inferring "no phase field means a unit" would call a resource node a
			# unit, and 3.6 would then send move orders naming trees.
			"is_unit": GameDataRegistry.unit(def_id) != null,
			# Who may order this animal about, or 0 (6.5). `SimUnit.to_snapshot` sends it
			# only for a claimed herdable, so everything else defaults to nobody's.
			"herded_by": int(entry.get("herded_by", 0)),
			# SOMETHING TO LOOK AT RATHER THAN SOMETHING IN THE GAME (4.13). True for
			# an arrow in flight and nothing else today. It is in `_facts` at all only
			# because the forget pass below reads `_facts` to release pooled views --
			# leave it out and every projectile leaks a view.
			#
			# A POSITIVE test against the three def tables, so anything the data does
			# not know as a gameplay entity is an effect BY DEFAULT rather than by
			# being listed here. Read by `pick()` (you cannot tap an arrow) and by the
			# minimap (an arrow is not a blip).
			"is_effect": GameDataRegistry.unit(def_id) == null
					and GameDataRegistry.building(def_id) == null
					and GameDataRegistry.resource_def(def_id) == null,
			# Present only on units (SimUnit.to_snapshot); absent on a building or
			# resource node entry, where it defaults to IDLE and is never read since
			# _is_own_living_villager() has already filtered those out by is_unit.
			"task": int(entry.get("task", SimUnit.Task.IDLE)),
			# WHAT IT STARTS ON ITS OWN (4.12), sent on every unit every tick. The
			# default here is PASSIVE and it is doing real work rather than being a
			# formality: a building or a resource node has no stance, and PASSIVE is the
			# reading that makes `SelectionActions` show nothing surprising for one.
			"stance": int(entry.get("stance", SimUnit.Stance.PASSIVE)),
			# Ticks left before the special ability may be used again (4.10). Sent only
			# while it is running, so 0 -- ready -- is the default for a unit with an
			# ability and the permanent state of everything without one. The action
			# slot greys itself off exactly this.
			"ability_cooldown": int(entry.get("ability_cooldown", 0)),
			# Present only on buildings (SimBuilding.to_snapshot); 0 elsewhere, which
			# reads correctly as "nothing queued" rather than needing its own guard.
			"queue_len": int(entry.get("queue_len", 0)),
			"queue_fraction": float(entry.get("queue_fraction", 0.0)),
			# The queued def ids, so each queue slot can crop that unit's own
			# portrait. Converted to StringName here rather than left as the
			# wire's Strings, because everything downstream compares against
			# StringName literals and a String never matches one.
			"queue": _names(entry.get("queue", [])),
			# WHO IS GARRISONED (4.8). `garrison_count` is what the Ungarrison button's
			# badge reads, and it survives the fog strip's removal of the roster -- a
			# remembered enemy tower reports neither, which reads as an empty one.
			# 0 on resource nodes and on every unit but the TRANSPORT SHIP, which since
			# 2026-08-29 sends both (2.4d) -- so a boat's cargo reaches the badge and the
			# portraits through the same two fields a castle's does, and `GarrisonUI`
			# never learns that a carrier can float.
			"garrison_count": int(entry.get("garrison_count", 0)),
			# The occupants' def ids, so each garrison slot can crop that unit's own
			# portrait -- the same reason `queue` above carries them, and through the
			# same String -> StringName conversion, because everything downstream
			# compares against StringName literals and a String never matches one.
			#
			# DEF IDS AND NOT ENTITY IDS, and that is a wire decision rather than an
			# oversight: a garrisoned unit is not in the snapshot, so sending its id
			# would tell a client about an entity it is otherwise not being told about.
			# `UngarrisonCommand` therefore names a SLOT.
			"garrison": _names(entry.get("garrison", [])),
			# The rally point, for the flag (`WaypointFlag`). `SimBuilding.NO_WAYPOINT`
			# for a building that has none, and for **every** building that is not the
			# local player's -- the server blanks it rather than sending it, so this
			# never has an enemy's rally point to leak in the first place.
			"waypoint": entry.get("waypoint", SimBuilding.NO_WAYPOINT) as Vector2i,
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
			# Which way a wall piece is turned, and whether a gate is shut (5.8).
			# `facing` is here as well as being fed to the view above because
			# `_footprint_of` derives a transposed footprint from it, and the panel
			# needs `gate_locked` to label the button Open or Close.
			"facing": int(entry.get("facing", 0)),
			"gate_locked": bool(entry.get("gate_locked", false)),
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
	# THE EXPLICIT DESPAWNS GO FIRST, AND THE ORDER IS LOAD-BEARING as of 2026-08-28.
	# A despawned entity is also absent from `updated`, so the forget pass below would
	# reach it too -- and having already dropped its facts and released its view, there
	# would be nothing left here to tell "it landed" from "it walked into the fog". The
	# two lists really do mean different things (see `SpentProjectiles`) and only this
	# one is a despawn; running it second threw that distinction away every time.
	for id in snap.get("removed", []):
		# Before the release, which is the only moment the sprite's own position and
		# facing are still available.
		_leave_spent(int(id))
		pool.release(int(id))
		_facts.erase(int(id))

	for known in _facts.keys():
		if not seen.has(known):
			pool.release(int(known))
			_facts.erase(known)

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


## Whether `owner` has a FINISHED building of `def_id`, from snapshot facts alone.
##
## THE CLIENT-SIDE TWIN of `SimWorld.has_completed_building`, and advisory in exactly
## the way `PlacementGhost` is: it exists so the market page can grey a button the
## server would refuse, not so anything can be decided here. Trustworthy for the one
## question it is asked -- "do *I* have a market" -- because a player's own entities
## are always sent whatever the fog says (`SnapshotSystem._entry_for`). For anybody
## else's buildings it would be answering out of what the fog last showed, which is
## why nothing asks it that.
##
## `phase` is COMPLETE for a unit or a resource node (see `_facts`), so this leans on
## the `def_id` match to mean "a building" rather than testing the kind separately.
func has_completed_building(owner: int, def_id: StringName) -> bool:
	for f in _facts.values():
		if int(f.get("owner_id", -1)) != owner or not bool(f.get("alive", true)):
			continue
		if StringName(f.get("def_id", &"")) == def_id \
				and int(f.get("phase", -1)) == SimBuilding.Phase.COMPLETE:
			return true
	return false


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
##
## AND THE THING WHOSE REAL GROUND YOU TAPPED BEATS ONE THAT ONLY REACHED. Two trees
## a tile apart have overlapping 2x2 pick boxes, so a tap on tree B's own tile was
## once free to answer with tree A -- whichever the Dictionary happened to yield
## first. That is the "clicking one tree gathers a completely different tree" the
## project owner reported on 2026-08-23, and it is a wrong answer rather than a
## missed one, which makes it much the worse failure of the two.
##
## WHEN THE TILE HOLDS NOTHING there is a second pass -- see `_nearest_small_node`.
## The paragraph above is still the rule and this is still not bounds-picking: the
## tile always answers first, and the fallback only runs where the answer was "bare
## ground", which is the one case that cannot be a wrong pick of something else.
func pick(local: Vector2, owner: int = 0) -> int:
	var tile := Iso.tile_at(local)
	var best := 0
	var best_is_unit := false
	var best_on_ground := false
	# Sorted so that two candidates the ranking cannot separate resolve the same way
	# every time, rather than by whatever order the Dictionary happened to hold.
	var ids := _facts.keys()
	ids.sort()
	for id in ids:
		var f: Dictionary = _facts[id]
		if not bool(f.get("alive", true)):
			continue          # a corpse or rubble is unselectable (4.7, 5.5)
		if bool(f.get("is_effect", false)):
			continue          # an arrow in flight is scenery, not a target (4.13)
		if owner != 0 and int(f["owner_id"]) != owner:
			continue
		if not _covers(f, tile):
			continue
		var is_unit: bool = f["is_unit"]
		# Whether the tap landed on ground this entity actually HOLDS, as opposed to
		# ground its pick box merely reaches over. Ranked below `is_unit` and above
		# nothing else -- see the header.
		var on_ground: bool = Rect2i(f["tile"] - f["footprint"] / 2,
				f["footprint"]).has_point(tile)
		if best == 0 \
				or (is_unit and not best_is_unit) \
				or (is_unit == best_is_unit and on_ground and not best_on_ground):
			best = int(id)
			best_is_unit = is_unit
			best_on_ground = on_ground
	if best != 0:
		return best
	return _nearest_small_node(local, owner)


## The one-tile resource node whose ARTWORK the tap came nearest, or 0 (2026-08-23).
## Only ever called by `pick()`, and only when the tile under the finger was empty.
##
## THE PROBLEM IT SOLVES is that a tile is 64x32 px and a berry bush is smaller than a
## fingertip. Tapping the picture of a bush misses it -- not because the pick is wrong
## but because the picture is drawn ABOVE the ground point that answers taps, and a
## 3.4 m bush lifts its own middle a whole tile up-screen. The player is aiming at the
## art, so the art is what this measures to: `pick_lift` is the ground point raised by
## half the visual's height, i.e. the middle of the blob you can see.
##
## ONE-TILE NODES ONLY, and resource nodes only. Both limits are the same caution.
## A 4x4 gold seam or a 2x2 tree is already the size of a fingertip and does not need
## this; letting one reach out another 24 px would only start eating taps that meant
## the grass beside it. And keeping it to resource nodes keeps the cost of a mistake
## at "gathered the wrong thing" -- had it caught units too, a tap meant to retreat
## from a fight would have become an attack order on whatever stood nearest, which is
## a far worse trade than a hard-to-tap sheep.
func _nearest_small_node(local: Vector2, owner: int) -> int:
	var nearest := 0
	var nearest_d := TAP_REACH_PX
	# Sorted for the reason `units_in_box` sorts: two nodes at the same distance
	# should resolve the same way every time, not by Dictionary insertion order.
	var ids := _facts.keys()
	ids.sort()
	for id in ids:
		var f: Dictionary = _facts[id]
		if not bool(f.get("alive", true)):
			continue
		if owner != 0 and int(f["owner_id"]) != owner:
			continue
		if f["pick_footprint"] != Vector2i.ONE:
			continue
		if GameDataRegistry.resource_def(f["def_id"]) == null:
			continue
		var art: Vector2 = Iso.tile_centre_to_world(f["tile"]) + f["pick_lift"]
		var d := local.distance_to(art)
		if d < nearest_d:
			nearest_d = d
			nearest = int(id)
	return nearest


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
		# BARE GROUND WITH ONE OF YOUR OWN BUILDINGS SELECTED SETS ITS RALLY POINT
		# (project owner, 2026-08-27), the genre-standard gesture. It costs nothing: that
		# tap previously did nothing but clear the selection, and clearing still has
		# right-click on desktop and 8.8's [X] button coming on mobile.
		#
		# **After the movable test, and that ordering is the whole safety of it.** With
		# any unit in hand a ground tap is a MOVE and must stay one, so this can only
		# fire for a selection of exactly one owned building -- which is what
		# `waypoint_target()` answers. No mixed selection can reach it.
		if has_movable_selection:
			return TapAction.MOVE
		return TapAction.WAYPOINT if waypoint_target(owner) != 0 else TapAction.NONE

	var f := facts_for(id)
	if f.is_empty():
		return TapAction.MOVE if has_movable_selection else TapAction.NONE

	if int(f["owner_id"]) == owner:
		if bool(f["is_unit"]):
			# YOUR OWN TRANSPORT WITH ROOM IN IT IS A THING TO BOARD (2.4d), and it is
			# the first time tapping one of your own UNITS has ever been an order rather
			# than a reselect. Same shape and same guard as the tower below -- room is
			# checked, not merely capacity, because a refused command is invisible.
			#
			# It cannot fire on the boat itself: `_has_garrison_room` reads the cap off
			# the def, and `GarrisonCommand.validate` refuses a passenger that is itself
			# a carrier, so tapping a transport with a transport selected reselects.
			if has_movable_selection and _has_garrison_room(f):
				return TapAction.GARRISON
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
		# A TOWER OR CASTLE WITH ROOM IN IT is a thing to go inside (4.8), and with
		# units in hand tapping it garrisons them -- the same shape as the field
		# immediately above, and the reason IDEA.md 4.8 asks for "the garrison action
		# flash" rather than a button: the order is issued by the tap and `ActionFlash`
		# says which one fired.
		#
		# ROOM IS CHECKED, not just capacity, and that is the rule this file already
		# follows for `Diplomacy` a few lines down: never offer an order the sim will
		# refuse, because a refused command is invisible -- the player taps, nothing
		# happens, and nothing says why. A FULL tower reselects instead, which is also
		# how the player gets at its Ungarrison button.
		if has_movable_selection and _has_garrison_room(f):
			return TapAction.GARRISON
		return TapAction.SELECT

	if has_movable_selection and not bool(f["is_unit"]) \
			and GameDataRegistry.resource_def(StringName(f["def_id"])) != null:
		return TapAction.GATHER

	# Somebody else's, or gaia's WILDLIFE: tapping it attacks it (4.13). Checked
	# AFTER the resource branch, so a tree stays a thing to chop rather than a
	# thing to shoot -- gaia owns both, and only the resource def tells them
	# apart. With nothing selected it still just reselects, so an enemy's panel
	# and health stay readable without an army in hand.
	#
	# THROUGH `Diplomacy`, sharing the sim's answer rather than keeping the view's
	# own. When these two drift the player taps an enemy, the tap offers an attack,
	# `AttackCommand.validate` refuses it, and nothing happens with nothing said.
	if Diplomacy.is_enemy_fact(f, owner):
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


## Whether these facts describe something with a free garrison slot (PLAN.md 4.8) --
## a COMPLETE building, or since 2026-08-29 a TRANSPORT SHIP (2.4d). False for 28 of the
## 31 buildings and for every unit but the transport, because `garrison_cap` is 0 on all
## of them: that is how "walls hold nobody", "a house is not a shelter" and "a knight is
## not a ferry" reach the tap without any of them being named here.
##
## THE CAP COMES FROM THE DEF AND THE COUNT FROM THE WIRE, which is the same division
## `_is_gatherable_building` above draws: the snapshot carries what is true right now
## and the registry answers what a thing is capable of. Sending the cap as well would
## be one more int per entity per tick to say something the client already has.
func _has_garrison_room(f: Dictionary) -> bool:
	var def_id := StringName(f.get("def_id", &""))
	var cap := 0
	if bool(f.get("is_unit", false)):
		var ud: UnitDef = GameDataRegistry.unit(def_id)
		cap = ud.garrison_cap if ud != null else 0
	else:
		# A FOUNDATION IS A HOLE IN THE GROUND, which is the building's own extra rule
		# and mirrors `SimBuilding.has_garrison_room`. A unit has no phase to check.
		if int(f.get("phase", -1)) != SimBuilding.Phase.COMPLETE:
			return false
		var bd: BuildingDef = GameDataRegistry.building(def_id)
		cap = bd.garrison_cap if bd != null else 0
	if cap <= 0:
		return false
	return int(f.get("garrison_count", 0)) < cap


## The building whose rally point a ground tap should set, or 0 for none.
##
## EXACTLY ONE, ALIVE, `owner`'s OWN. One because a rally point belongs to a building
## and a group tap would have to pick which -- and a player who box-selected their whole
## base and tapped the ground would otherwise flag every building they own at once.
##
## Not gated on the building being COMPLETE, and not on it training or holding anything:
## `SetWaypointCommand.validate` accepts any owned building for the reason recorded
## there, so a flag on a house is allowed and simply does nothing. A tap that is silently
## ignored is worse than a flag that turns out to be pointless.
func waypoint_target(owner: int) -> int:
	if selection.size() != 1:
		return 0
	var id := selection.primary()
	var f: Dictionary = _facts.get(id, {})
	if f.is_empty() or not bool(f.get("alive", true)):
		return 0
	if bool(f.get("is_unit", false)) or int(f.get("owner_id", 0)) != owner:
		return 0
	# A resource node is not a unit and not owned by a player, so the owner test above
	# already excludes it -- this is the positive check that it really is a building,
	# asked of the registry the same way `_is_gatherable_building` asks.
	if GameDataRegistry.building(StringName(f.get("def_id", &""))) == null:
		return 0
	return id


## The selected entities that can actually be given a move order (PLAN.md 3.6).
##
## Filtered rather than passed whole: `MoveCommand.validate()` rejects the ENTIRE
## command if any id is not a unit, so a selection containing the town centre would
## silently cancel the move for the villagers selected alongside it.
func movable_selection() -> Array[int]:
	var movable: Array[int] = []
	for id in selection.current():
		var f: Dictionary = _facts.get(id, {})
		if not bool(f.get("is_unit", false)):
			continue
		# GAIA'S ANIMALS ARE MOVABLE ONLY IF WE ARE HERDING THEM (6.5). Without this
		# the client would offer an order `MoveCommand.validate` then refused, and a
		# refused command is invisible -- the player taps, nothing happens, and nothing
		# says why. `herded_by` rides the snapshot for exactly this test.
		if int(f.get("owner_id", 0)) == 0 \
				and int(f.get("herded_by", 0)) != local_player_id:
			continue
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


## THE PICK footprint, not the ground one. For everything but the tree they are the
## same value; where they differ, this is the question being asked -- may a tap land
## here -- and the ground footprint is the answer to a different one.
##
## Note what `centre - footprint / 2` does for an even box: integer division floors,
## so a 2x2 centred on a tile covers that tile and its three UP-SCREEN neighbours,
## which is exactly where a tall sprite's art is drawn. Nothing had to be added to
## bias it; the existing rounding already leans the right way.
func _covers(f: Dictionary, tile: Vector2i) -> bool:
	var footprint: Vector2i = f["pick_footprint"]
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


## How big to draw the selection ring, in metres, or `Vector2.ZERO` for "ask the
## visual's own placeholder".
##
## EVERY BUILDING IS SIZED FROM ITS FOOTPRINT, and the placeholder answers for
## everything else. The two halves of that split are two different questions, and
## which one is right depends on what the ring is drawn AS:
##
##   - A UNIT, a tree, an animal: an ellipse around a thing standing at a point. The
##     right size is the ground the ART covers, which is what the placeholder
##     records (`vis.villager` is a measured 0.6 m). Its gameplay footprint is one
##     whole tile and a ring that size would be three times too big.
##   - A BUILDING: the footprint square itself (`EntityView.ring_square`), which is
##     an exact rect and must be the SIM's rect -- the tiles it stands on, refuses to
##     be built over, and was shown as a placement ghost on. Drawing the mesh's
##     measured extent instead would put the outline a metre inside the tiles the
##     building actually holds, which is precisely the mismatch a traced square is
##     for showing.
##
## Until 2026-08-29 this returned the footprint for ONE building case -- a
## NORTH-SOUTH WALL, whose art is baked east-west (`vis.wall_wood_gate` is authored
## [18, 4] metres) while `_footprint_of` transposes the real footprint to [4, 18], so
## a selected north-south gate drew a fat ellipse sprawling eighteen metres east
## across open grass. That case is now simply the general rule.
func _ring_ground_m(entry: Dictionary, footprint: Vector2i) -> Vector2:
	if GameDataRegistry.building(StringName(entry.get("def_id", &""))) == null:
		return Vector2.ZERO
	return Vector2(footprint) * Iso.METRES_PER_TILE


func _footprint_of(entry: Dictionary) -> Vector2i:
	var def_id := StringName(entry.get("def_id", &""))
	var building := GameDataRegistry.building(def_id)
	if building != null:
		# A NORTH-SOUTH WALL IS ITS DEF'S FOOTPRINT TRANSPOSED (PLAN.md 5.8), and it
		# is DERIVED here rather than sent. Sending it would be the first building
		# field 12.1f took OFF the wire coming straight back, and it does not need to:
		# `facing` is already there and already says which axis the piece lies on.
		# Without this a north-south wall hit-tests, occludes and blips as though it
		# lay east-west -- nine tiles in the wrong direction.
		#
		# FACING IS THE FLAG, with no "is this a wall" test beside it, because
		# `PlaceWallCommand` is the only thing in the game that sets a building's
		# facing at all: every other building is baked at one direction and stays at 0
		# forever (SimBuilding's header). The square-footprint guard costs nothing --
		# a square transposes to itself -- and is there so that giving some future
		# building a facing cannot silently rotate its footprint too.
		if building.footprint.x != building.footprint.y \
				and int(entry.get("facing", 0)) == WallPlan.FACING_FOR_AXIS[WallPlan.AXIS_Y]:
			return Vector2i(building.footprint.y, building.footprint.x)
		return building.footprint
	var res := GameDataRegistry.resource_def(def_id)
	if res != null:
		return res.footprint_for_size(int(entry.get("size_class", 0)))
	return Vector2i.ONE


## The tap box, which only a resource node can widen (`ResourceDef.pick_footprints`).
##
## BUILDINGS DELIBERATELY GO THROUGH `_footprint_of` UNCHANGED, transpose and all. A
## building already covers the ground it looks like it covers, so there is nothing to
## fix; and a building's footprint is the same rect the sim refuses to build on, so a
## pick box wider than it would let the player tap a house on tiles where placement
## advice is simultaneously drawing "you cannot build here".
func _pick_footprint_of(entry: Dictionary) -> Vector2i:
	var res := GameDataRegistry.resource_def(StringName(entry.get("def_id", &"")))
	if res == null:
		return _footprint_of(entry)
	return res.pick_footprint_for_size(int(entry.get("size_class", 0)))


## Ground point -> the middle of the sprite, in local pixels: straight up the screen by
## half the visual's authored height. Only resource nodes get one, because only
## `_nearest_small_node` reads it and it considers nothing else.
##
## HALF the height, not all of it. The art stands ON the tile and reaches up from it,
## so its midpoint is half a height above the ground point -- and the midpoint is what
## a player aims at when they mean "that bush", not its top leaf.
func _pick_lift_of(entry: Dictionary) -> Vector2:
	if GameDataRegistry.resource_def(StringName(entry.get("def_id", &""))) == null:
		return Vector2.ZERO
	return Iso.height_to_world(GameDataRegistry.placeholder_for(_visual_id_of(entry)).height_m * 0.5)


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
		# STANDING ON IT COUNTS, AND THIS LINE USED TO BE UNREACHABLE. It sat below the
		# `is_in_front` guard, and `is_in_front` is `tile.x >= r.end.x or tile.y >=
		# r.end.y` -- which is false for every tile INSIDE the rect. So the one case it
		# was written for was the one case it could never answer.
		#
		# It only shows on a building a unit can stand inside, which means a WALKABLE
		# one: a field, or an open gate. The project owner found it as *"wolf renders
		# behind the field i am unable to target it for attack"* (2026-08-28) -- and the
		# targeting half is downstream of the drawing half, because `pick()` already
		# prefers units and answers by tile. A wolf you cannot see is a wolf you cannot
		# aim at.
		#
		# `Occlusion.hides()` deliberately returns false for the same case, so the wolf
		# did not even get an outline: standing inside a footprint is not being hidden
		# BY it. That stays right -- the fix is to draw the unit in front, which is what
		# standing on top of something looks like.
		if r.has_point(tile):
			return true
		if not Occlusion.is_in_front(tile, r):
			continue
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


## Which clip a BUILDING draws: `static` for all 31 of them, and `open` for a gate
## that is standing open (PLAN.md 5.8, art delivered 2026-08-28 -- the project owner
## asked for it on 2026-08-27, wired to the locked flag).
##
## **`is_gate` is read off the DEF, not off the wire, and that is deliberate.**
## `gate_locked` already rides every building entry and defaults false, so
## `not gate_locked` alone would ask every house in the game for an `open` clip;
## `def_id` is on the wire already and the registry answers the rest. 12.1f spent a
## pass removing per-entity field names from the snapshot and a second gate flag
## would put one back to say something two facts already say.
##
## **COMPLETE only.** A gate under construction resolves to a `vis.foundation_*`
## atlas, which has no `open` clip -- `resolve_anim` would fall back and draw the
## right thing anyway, but a half-built gate is not open, it is a building site, and
## saying so here beats relying on the fallback to mean it.
func _building_anim(entry: Dictionary) -> StringName:
	if int(entry.get("phase", -1)) != SimBuilding.Phase.COMPLETE:
		return AtlasEntry.STATIC_ANIM
	if bool(entry.get("gate_locked", false)):
		return AtlasEntry.STATIC_ANIM
	var def: BuildingDef = GameDataRegistry.building(StringName(entry.get("def_id", &"")))
	return AtlasEntry.OPEN_ANIM if def != null and def.is_gate else AtlasEntry.STATIC_ANIM


## Leave a mark on the ground where a despawned EFFECT ended, or do nothing.
##
## Effects and nothing else: `is_effect` is a positive test against the three def tables
## (see `_facts`), so this covers the projectiles and would cover whatever else the sim
## invents that is there to be looked at rather than played with. A unit dying leaves a
## corpse the sim itself keeps for a while, and a building leaves rubble; neither wants a
## decal and neither is an effect.
##
## READ OFF THE VIEW rather than off `_facts`, deliberately. The view holds the exact
## world position the sprite reached and the SPRITE facing it was drawn at -- already
## converted by `Iso.sim_facing_to_sprite` -- where `_facts` holds a tile, which would put
## every arrow in a tile's centre, and a sim facing, which would need converting a second
## time somewhere else.
func _leave_spent(id: int) -> void:
	var f: Dictionary = _facts.get(id, {})
	if f.is_empty() or not bool(f.get("is_effect", false)):
		return
	var view := pool.get_view(id)
	if view == null:
		return
	# The entity id as the scatter seed: unique per shot, so the eight arrows of one
	# volley do not come to rest on the same pixel.
	spent.add(view.visual_id, view.position, view.facing, id)


## A WALL UNDER CONSTRUCTION SHOWS ITS FOUNDATION, like every other building
## (project owner, 2026-08-28: *"leave it the way it was with foundations, the problem
## was never the construction phase"*).
##
## This briefly drew the finished wall at 0.4 alpha instead, on a misreading of *"wall
## drag to build is very broken"*: a nine-tile foundation is 0 A.D.'s construction site
## and three in a row do read as debris, so it looked like a sufficient explanation for
## the report. It was not the report. The wall was being laid NINETY DEGREES ACROSS THE
## DRAG (`WallPlan.FACING_FOR_AXIS`), foundations included, and dimming the wrong wall
## would have hidden the evidence rather than fixed it -- the owner had to send a third
## screenshot, of the selection ring sitting square across the finished art, to say so.
##
## Kept as a comment because the mistake is the useful part: a screenshot of a broken
## thing has more than one thing wrong with it, and the presentational explanation is
## the tempting one because it is the one that needs no measurement.
func _visual_id_of(entry: Dictionary) -> StringName:
	var def_id := StringName(entry.get("def_id", ""))
	# `phase` is present only for buildings, `size_class` only for resource nodes and
	# `packed` only for a siege engine that currently is (their own to_snapshot); -1 or
	# absent in each case means "no preference". The three are per entity kind and never
	# both apply -- see `visual_for`'s header.
	var vis := GameDataRegistry.visual_for(def_id, int(entry.get("phase", -1)),
			int(entry.get("size_class", -1)), bool(entry.get("packed", false)))
	# Interchangeable looks (visuals.json `variants`) -- four field plots and, since
	# 2026-08-28, a tree species set per map type. Unconditional and free for
	# everything else: an id with no variants returns itself, so this needs no list
	# of which visuals have them and no list of which ones have pools.
	return GameDataRegistry.variant_of(vis, _variant_seed(entry), variant_pool)


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
