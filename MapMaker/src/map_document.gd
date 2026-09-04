## The map being edited: a `MapData`, where it came from, and whether it has unsaved
## changes (PLAN.md 16.2).
##
## ## WHY THIS EXISTS RATHER THAN A BARE `MapData` ON THE EDITOR
##
## Three things want to be in one place, and none of them belongs on a `MapData` — which is
## a verbatim copy of the game's and must stay that way:
##
##   - **where it saves**, so Save is not a file dialog every time;
##   - **whether it is dirty**, so a tool can eventually refuse to lose work;
##   - **one funnel for every mutation.** Every change to the map goes through a method
##     here, which is what makes 16.2a's undo a list of inverted calls rather than an
##     archaeology exercise across the whole editor. `Command`/`validate()`/apply is the
##     same shape the sim uses for exactly this reason (PLAN.md §4).
##
## ⚠️ **SO: NOTHING OUTSIDE THIS CLASS MAY WRITE TO `data` DIRECTLY.** Reading it is fine and
## the canvas does nothing else. The day undo lands, a stray `document.data.set_terrain(...)`
## is a change the stack never saw and cannot take back — and it will look like undo being
## broken rather than like a missed call site.
class_name MapDocument
extends RefCounted

## Terrain a new map is filled with. Grass, because it is the kind you paint AWAY from and
## an author starting on rock or water would have to clear the whole board first.
const DEFAULT_FILL := SimMap.Terrain.GRASS

## The smallest map worth allowing. Under this, a single town centre (10x10) plus its
## clearance does not fit twice, so a two-player map could not be authored at all.
const MIN_SIZE := 48

## The largest. The game's own generator tops out around 192 for eight players, and a canvas
## this size is already 36,000 tiles -- past here the tool is slow for maps nobody asked for.
const MAX_SIZE := 256

var data: MapData = null

## Absolute directory this map saves to, or empty if it has never been saved.
var dir: String = ""

## The author's name for it, which becomes the sidecar's `name` and the picker's label.
var map_name: String = ""

## True when there are changes `save()` has not written.
var dirty := false


static func create(size: Vector2i, p_name: String) -> MapDocument:
	var doc := MapDocument.new()
	doc.data = MapData.create(_clamped(size), DEFAULT_FILL)
	doc.map_name = p_name.strip_edges()
	# A NEW MAP IS DIRTY FROM THE FIRST FRAME. It exists nowhere on disk, so "no unsaved
	# changes" would be a lie -- and the flag is what a "you have unsaved work" prompt will
	# read when one exists.
	doc.dirty = true
	return doc


static func _clamped(size: Vector2i) -> Vector2i:
	return Vector2i(clampi(size.x, MIN_SIZE, MAX_SIZE), clampi(size.y, MIN_SIZE, MAX_SIZE))


# ── mutation (the only writers) ─────────────────────────────────────────────

## Paint one tile. Returns true if anything actually changed.
##
## **THE RETURN VALUE IS THE POINT, not a courtesy.** Painting is a drag, so the same tile
## arrives dozens of times under one gesture; without this the canvas would redraw on every
## mouse-move and 16.2a's undo stack would fill with thousands of no-op entries for a single
## stroke. So the caller repaints and records only on a real change.
func paint(tile: Vector2i, kind: int) -> bool:
	if not data.in_bounds(tile) or data.terrain_at(tile) == kind:
		return false
	data.set_terrain(tile, kind)
	dirty = true
	return true


## Place player `player`'s start at `centre`: the marker AND the base behind it.
##
## ⚠️ **ONE GESTURE FOR BOTH, AND THAT IS DELIBERATE.** `MapData.starts` is only the centre
## tile, and `MapGen.build_from()` hands a player their town centre and units purely from the
## entities the map LISTS for their index -- it never derives a base from a start. So a start
## marker on its own authors a player who opens the match alive, owning nothing, and is
## eliminated on the first tick anything looks. That is the exact fault 16.0's `can_start()`
## rule 7 was written about, and the tool must not be able to create it by accident.
##
## **16.4 is where the two come apart** — a move cursor that drags a town centre without
## moving the start, or a start without its base — and it can, because both are recorded
## here. What this refuses to do is create the broken combination by DEFAULT.
func place_start(player: int, centre: Vector2i) -> bool:
	if player < 1 or not data.in_bounds(centre):
		return false
	remove_start(player)
	while data.starts.size() < player:
		data.starts.append(Vector2i(-1, -1))
	data.starts[player - 1] = centre
	StartLayout.place(data, player, centre)
	dirty = true
	return true


## Take a player's start and everything placed for them back off the map.
##
## **BY OWNER, AND BY THE TAG `StartLayout` LEAVES — never by proximity.** Two rules because
## a start has two kinds of thing in it:
##
##   - the base and its units are `player`-owned, so the owner is enough;
##   - **every resource node is gaia (`player: 0`)** and is indistinguishable from a tree an
##     author placed deliberately. `StartLayout.ORIGIN_KEY` says which start put it there.
##
## A test caught what happens without the second rule: placing a start twice left the first
## cluster behind and the entity count went 24 → 40, so a mis-clicked start littered the map
## permanently — and 16.2 has no delete tool to clean it up with. Deleting "gaia things near
## the start" instead is the tempting alternative and is worse: it would eat the author's own
## trees the moment 16.3 lets them place any.
func remove_start(player: int) -> void:
	if player >= 1 and player <= data.starts.size():
		data.starts[player - 1] = Vector2i(-1, -1)
	var kept: Array[Dictionary] = []
	for e in data.entities:
		var owned := int(e.get("player", 0)) == player
		var from_this_start := int(e.get(StartLayout.ORIGIN_KEY, 0)) == player
		if not owned and not from_this_start:
			kept.append(e)
	data.entities = kept
	# TRAILING PLACEHOLDERS TRIMMED, so `player_count()` -- which IS `starts.size()` -- does
	# not count a slot nobody is in. An untrimmed tail would make a two-player map claim four
	# and the picker would offer seats that lead nowhere.
	while not data.starts.is_empty() and data.starts[data.starts.size() - 1] == Vector2i(-1, -1):
		data.starts.resize(data.starts.size() - 1)
	dirty = true


func fill_all(kind: int) -> void:
	data.fill_terrain(kind)
	dirty = true


# ── how many players this map can really seat ───────────────────────────────

## The same arithmetic `SavedMaps._players_in()` does on the game side, so the number the
## tool shows is the number the lobby will enforce.
##
## ⚠️ **DUPLICATED ON PURPOSE, AND IT IS THE ONE DUPLICATION IN THIS TOOL.** The game's copy
## reads a saved sidecar; this one reads a live `MapData`, and neither can call the other
## across two projects. Pulling it into `format/` was the alternative and was rejected: it is
## not part of the format, it is an opinion ABOUT a map, and putting it there would mean a
## hash check failing whenever the lobby's rule changed. **If the two ever disagree, the
## GAME's is right** — it is the one that refuses to start a match.
func seats() -> int:
	var starts := 0
	for s in data.starts:
		if s.x >= 0:
			starts += 1
	var highest := 0
	for e in data.entities:
		highest = maxi(highest, int(e.get("player", 0)))
	return mini(starts, highest) if starts > 0 and highest > 0 else 0


# ── saving ──────────────────────────────────────────────────────────────────

## Write to `maps_dir/<slug>`. Problems back as sentences; empty means written.
##
## PLAN.md §16 decision 4: **repo-root `maps/` and nothing else.** Never inside `game/`,
## which is `res://` and read-only once exported, and never into `user://`, because
## installing content is the game's job.
func save(maps_dir: String) -> Array[String]:
	var problems: Array[String] = []
	if map_name.is_empty():
		problems.append("the map needs a name before it can be saved")
		return problems
	var target := dir if not dir.is_empty() else maps_dir.path_join(slug())
	if DirAccess.make_dir_recursive_absolute(target) != OK and not DirAccess.dir_exists_absolute(target):
		problems.append("could not create %s" % target)
		return problems

	# THE SIDECAR'S `name` IS THE AUTHOR'S, and `players` is what the map can really seat --
	# not how many starts were dropped. 16.0's picker labels its rows from these two.
	problems = MapFile.save(data, target, {
		"name": map_name,
		"players": seats(),
		"authored_by": "MapMaker 16.2",
	})
	if problems.is_empty():
		dir = target
		dirty = false
	return problems


## A directory name from the map's name: lower case, underscores, nothing exotic.
##
## **A PATH IS NOT A LABEL.** The name is the author's and may hold spaces, punctuation or
## anything else they type; a folder carrying it verbatim is a folder that breaks on one
## machine and not another. The sidecar keeps the real name, so nothing is lost.
func slug() -> String:
	var out := ""
	for i in map_name.to_lower().length():
		var c := map_name.to_lower()[i]
		out += c if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") else "_"
	while out.contains("__"):
		out = out.replace("__", "_")
	out = out.strip_edges().trim_prefix("_").trim_suffix("_")
	return out if not out.is_empty() else "untitled_map"
