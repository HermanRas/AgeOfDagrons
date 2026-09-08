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

## What goes in the sidecar's `authored_by`. Read by nothing and written for a person, so it
## names the TOOL and not a phase — see `save()`.
const AUTHORED_BY := "MapMaker"

var data: MapData = null

## Absolute directory this map saves to, or empty if it has never been saved.
var dir: String = ""

## The author's name for it, which becomes the sidecar's `name` and the picker's label.
var map_name: String = ""

## True when there are changes `save()` has not written.
var dirty := false

## What was wrong with the map the last time it was SAVED — not what stopped it saving.
##
## ⚠️ **WARNINGS AND PROBLEMS ARE DIFFERENT THINGS AND THE DIFFERENCE IS THE FEATURE** (16.4b).
## `save()` returns *problems*: the map could not be written, and the author has lost nothing
## but has gained nothing either. These are the other case — **the file was written and it is
## worth looking at anyway.** Conflating them would mean either refusing to save a map an
## author deliberately hand-built (see `StartLayout.audit`) or saying nothing at all, and the
## second is what shipped an unplayable map on 2026-09-04.
##
## **TWO SOURCES, AND NEITHER CAN ANSWER THE OTHER'S QUESTION.** `StartLayout.audit` reports a
## start short of its opening — the half that would have caught the 48x48 map. `MapValidator`
## is the game's own gate (2.4b) and reports what this tool has no business holding a second
## opinion about: start-to-start connectivity, overlapping entities, resources within a WALK
## rather than within a radius, and the sea-map rules. Appended in that order, narrow to fatal.
var warnings: Array[String] = []

## The sidecar of the file this map was OPENED from, verbatim, or `{}` for a new map (16.4a).
##
## ## WHY A RE-SAVE MUST NOT SIMPLY FORGET IT
##
## `map.json` carries provenance nothing in `game/src` reads — `map_type`, `seed`,
## `authored_by`, `created`. It is there for a person: 2.4c's rule is that **the PNG is
## authoritative and the seed is provenance**, so a seed is the only record of how a map
## originally came to exist. Re-authoring the five How To Play maps (16.10) through a tool that
## dropped those keys would erase, one map at a time, the only note saying where they came
## from — and nothing would fail, which is what makes it worth defending against here.
##
## ⚠️ **AND THE TRAP ON THE OTHER SIDE, WHICH IS MUCH WORSE THAN LOSING PROVENANCE.**
## `MapFile.save()` merges its `header` argument **over** the fields it derives from the map,
## so handing this dictionary back unfiltered would write the OPENED file's `entities`,
## `starts`, `w`, `h` and `meta` on top of the edited ones: every change made in the tool
## silently discarded, in a save that reports success. `_preserved_header()` is the filter, and
## it computes what to drop from `to_dict()` itself rather than from a written-out list —
## 16.5's areas are a new key in there, and a list would have to be remembered on that day.
var header: Dictionary = {}


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


## Read a map back off disk (PLAN.md 16.4a). Null on anything it cannot trust, with the
## reason appended to `out_problems`.
##
## ## THE PROBLEMS ARE THE RETURN VALUE THAT MATTERS
##
## ⚠️ **A PARTIAL LOAD THAT SILENTLY SHOWS AN EMPTY CANVAS OVER SOMEBODY'S AUTHORED MAP IS HOW
## A FILE GETS OVERWRITTEN WITH NOTHING** — 16.4a's card says exactly that, and it is the one
## failure this function is arranged around. So there is no partial: `MapFile.load_map()`
## returns null on a version it cannot read, a PNG whose dimensions disagree with the sidecar,
## or a terrain byte outside the enum, and **null here leaves the caller's current document
## untouched**. `Editor.open_map()` puts the sentence on the notice line and keeps the dialog
## open; nothing replaces what is on the canvas until there is a map to replace it with.
##
## ## NOT DIRTY, AND THAT IS THE OPPOSITE OF `create()`
##
## A new map is dirty from the first frame because it exists nowhere on disk. An opened one is
## byte-for-byte what is in the file, so the honest answer is clean — and the flag is what an
## "unsaved work" prompt will read when one exists.
##
## `MapFile.load_map()` re-parses the sidecar `read_header()` reads a line later. That is one
## small JSON parse of a file measured in kilobytes, paid once per Open, and the alternative is
## a second entry point into `MapFile` — a hash-checked verbatim copy of the game's, which
## this tool does not get to add a method to.
static func open(dir_path: String, out_problems: Array[String]) -> MapDocument:
	var data := MapFile.load_map(dir_path, out_problems)
	if data == null:
		return null
	var doc := MapDocument.new()
	doc.data = data
	doc.dir = dir_path
	# READ AFTER `load_map` SUCCEEDED, so a bad sidecar is reported once rather than twice:
	# both functions share `_parse_sidecar`, and reaching here means it has already passed.
	doc.header = MapFile.read_header(dir_path, out_problems)
	doc.map_name = MapSources.map_name_in(doc.header, dir_path.get_file())
	doc.dirty = false
	return doc


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
	# CLEARED FIRST, so a stale warning from a previous save cannot outlive the fault it was
	# about -- the same reason the editor's notice line is rewritten rather than appended to.
	warnings = []
	if map_name.is_empty():
		problems.append("the map needs a name before it can be saved")
		return problems
	var target := dir if not dir.is_empty() else maps_dir.path_join(slug())
	if DirAccess.make_dir_recursive_absolute(target) != OK and not DirAccess.dir_exists_absolute(target):
		problems.append("could not create %s" % target)
		return problems

	# THE SIDECAR'S `name` IS THE AUTHOR'S, and `players` is what the map can really seat --
	# not how many starts were dropped. 16.0's picker labels its rows from these two.
	# PROVENANCE FIRST, THE TOOL'S OWN THREE KEYS OVER THE TOP. `_preserved_header()` explains
	# why the base is filtered and what happens if it is not.
	var side := _preserved_header()
	side["name"] = map_name
	side["players"] = seats()
	# ⚠️ **NOT A VERSION NUMBER, DELIBERATELY.** It used to read "MapMaker 16.2" and was
	# already a row out of date by 16.4a -- a hardcoded phase number in a written file is a
	# lie with a delay on it, and nothing reads this but a person wondering who wrote the map.
	side["authored_by"] = AUTHORED_BY
	problems = MapFile.save(data, target, side)
	if problems.is_empty():
		dir = target
		dirty = false
		# AUDITED AFTER A SUCCESSFUL WRITE, not before it. An author who has been told their
		# map is thin should still have the file: refusing to write is how you lose work over
		# an opinion, and 16.3's palette is where a deliberate hand-built economy stops
		# looking thin.
		warnings = StartLayout.audit(data)
		# ⚠️ **AND THEN THE GAME'S OWN GATE, WHICH IS THE OTHER HALF OF 16.4b AND THE HALF
		# THAT COULD NOT BE WRITTEN HERE.** `StartLayout.audit` knows whether a start got its
		# opening; it has no idea whether the two starts can REACH each other, whether two
		# entities are standing on the same ground, or whether a sea map's players can build
		# a dock. `MapValidator` is the gate 2.4b already puts in front of every generated
		# map, so the tool now runs the game's checks rather than an imitation of them --
		# which is why `format/map_validator.gd` exists and why `FormatGuard` hashes it.
		#
		# **THESE ARE THE SEVEREST WARNINGS IN THE TOOL AND THEY ARE STILL WARNINGS.** A map
		# that fails this one is a map the lobby will refuse to start, so the author has to be
		# told plainly -- and refusing to WRITE it would lose the work of an author who is
		# halfway through joining two halves of an island. Same rule the audit follows, for a
		# louder problem: the file is fine, the map is not.
		#
		# Appended after the audit rather than merged, so the order on the notice line goes
		# from "your start is short" to "nobody can reach anybody" -- narrow to fatal.
		warnings.append_array(MapValidator.problems(data))
	return problems


## Save this map as a NEW one in `maps_dir`, leaving whatever it was opened from alone
## (PLAN.md 16.4a).
##
## ## WHY OPEN NEEDED THIS, AND WHY IT IS NOT JUST `save()` WITH THE DIRECTORY CLEARED
##
## Before Open existed, `dir` was only ever a directory this tool had written, so `save()`
## re-using it was simply Save. Open makes `dir` point at **files the author did not create**
## — the shipped campaign's five maps most of all — and re-using it is then a replace. That is
## exactly what 16.10 wants and exactly what an author looking at a map does not, so the two
## intentions need two buttons. The rule the tool teaches is one sentence: **Open then Save
## replaces; Save As creates.**
##
## ⚠️ **IT REFUSES TO LAND ON AN EXISTING MAP RATHER THAN REPLACING ONE.**
## `dev/author_map.tscn` already draws this line (*"an authored map is content under version
## control, and a silent re-roll would replace something somebody may have balanced a scenario
## against"*) and a GUI has no `--force` to offer. So: a name that is already taken is
## reported, nothing is written, and the author changes the name — and replacing a map on
## purpose is Open followed by Save, which is the sentence above read the other way. **Without
## this the field an author types a title into would be a delete button**, and 16.2a's undo
## does not exist yet and would not cover the filesystem when it does.
func save_as(maps_dir: String) -> Array[String]:
	if map_name.is_empty():
		return ["the map needs a name before it can be saved"] as Array[String]
	var target := maps_dir.path_join(slug())
	if target != dir and MapFile.exists_in(target):
		return ["there is already a map in %s — change the name" % target] as Array[String]
	# CLEARED, so `save()` derives the target from the name. Restored on failure: a Save As
	# that could not write must not have quietly detached the document from its own file.
	var was := dir
	dir = ""
	var problems := save(maps_dir)
	if not problems.is_empty():
		dir = was
	return problems


## The sidecar's provenance keys and nothing the map itself decides.
##
## ⚠️ **THE FILTER IS COMPUTED FROM `to_dict()`, NOT WRITTEN OUT**, and that is the point.
## `MapFile.save()` merges a header **over** the fields it derives, so any key both sides
## carry would be written from the OPENED file rather than from the edited map — `entities`
## and `starts` most destructively, `w`/`h` in a way that makes the sidecar disagree with the
## PNG and the map unloadable. Asking `to_dict()` what it produces means the day 16.5 adds
## areas to the wire form, this drops them from the stale header with no edit here.
##
## `format_version` and `created` are the two `MapFile.save()` sets itself, so they are named:
## carrying an old `format_version` forward would label a file written in the new shape with
## the old number, which is decision 7's checklist defeated by a copied dictionary.
func _preserved_header() -> Dictionary:
	var out: Dictionary = {}
	var derived := data.to_dict()
	for k in header:
		if derived.has(k) or k == "format_version" or k == "created":
			continue
		out[k] = header[k]
	return out


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
