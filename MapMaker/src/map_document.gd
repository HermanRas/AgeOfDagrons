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
##     here, which is what makes 16.2a's undo a stack of recorded states rather than an
##     archaeology exercise across the whole editor. `Command`/`validate()`/apply is the
##     same shape the sim uses for exactly this reason (PLAN.md §4).
##
## ⚠️ **SO: NOTHING OUTSIDE THIS CLASS MAY WRITE TO `data` DIRECTLY.** Reading it is fine and
## the canvas does nothing else. Since 16.2a a stray `document.data.set_terrain(...)` is a
## change the undo stack never saw and cannot take back — and it will look like undo being
## broken rather than like a missed call site.
##
## **THE ONE OTHER WRITER IS `MapEdit`, and it is not an exception to the rule so much as the
## rule running in reverse:** it only ever restores bytes and lists that a mutation here
## recorded on the way past. Nothing hands it a change of its own.
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
##
## Set by every mutation and cleared by `save()`, as it always was — and since 16.2a also
## recomputed by `undo()`/`redo()` from `history.at_clean_point()`, because undoing back to
## the last save genuinely does make the map match its file again. See `UndoStack`.
var dirty := false

## Undo and redo (PLAN.md 16.2a). One stack per document: you cannot undo past "this is a
## different map", so `create()` and `open()` each start with an empty one.
var history := UndoStack.new()

## The step currently being recorded into, or null between acts.
##
## **A STEP IS OPENED AND CLOSED BY THE MUTATION ITSELF** unless a stroke is holding one open,
## which is what makes a drag one undo entry and a single call from a test or a `dev/` script
## also exactly one. See `_open()`.
var _step: MapEdit = null

## True while a mouse-drag is holding `_step` open. See `begin_stroke()`.
var _step_held := false

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

## Which entity the author has picked, as an index into `data.entities`, or -1 (PLAN.md 16.4).
##
## ## AN INDEX, AND THEREFORE SOMETHING THAT HAS TO BE INVALIDATED
##
## ⚠️ **A STALE INDEX EDITS THE WRONG ENTITY AND SAYS NOTHING.** Entities are appended and
## dropped, so any act that REBUILDS the list can leave this pointing at a different thing —
## erase, `remove_start` (which filters the whole list), and undo/redo (which replace it from a
## snapshot that may be a completely different shape). Every one of those clears it, and the
## clearing lives beside the mutation rather than in a `_validate()` somebody has to remember
## to call.
##
## **`add_entity` is the exception and it is safe by construction**: it appends, so every
## existing index still names what it named. That is worth stating because it looks like an
## oversight next to the others.
##
## The alternative was an id per entity, and it was rejected: `MapData`'s entity record is four
## keys the game reads, `MapFile` writes exactly those, and an id would either reach the file —
## a format change for a selection highlight — or be session-only metadata like
## `StartLayout.ORIGIN_KEY`, which is a second thing to strip. **A cleared selection is a
## visible, harmless failure; a stale one is an invisible, destructive one.**
var selected := -1

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
## it computes what to drop from `to_dict()` itself rather than from a written-out list.
##
## ✅ **THAT PAID OFF ON 2026-09-09 AND NOT QUITE FOR FREE.** 16.5's `areas` is a new key in
## `to_dict()` and this function needed no edit — but it is also the reason `MapData.to_dict()`
## writes `areas` **even when the list is empty**, unlike the per-entity `axis`: a key that
## vanished when the author deleted their last region would stop being filtered out of the stale
## header, so the deletion would not reach the file and the region would come back on reopen. The
## filter being derived is what makes that a property of one line in `MapData` rather than a
## remembered exception here.
var header: Dictionary = {}

## The map's authored win/lose conditions (PLAN.md 16.6), as the AUTHOR'S OWN RECORDS.
##
## ## ⚠️ RAW DICTIONARIES AND NOT `ObjectiveDef` OBJECTS, AND THE REASON IS THE WIRE
##
## `ObjectiveDef.to_dict()` is the **wire** form: every enum is an int, because the sim must
## never re-parse a `">="`. A `scenario.json` is the opposite — it holds the words an author
## typed (`"subject": "unit"`, `"compare": ">="`), and `from_dict` is what turns one into the
## other. **16.8 exports a `scenario.json`, so what has to survive here is the WORDS.** Storing
## parsed defs and writing `to_dict()` back out would emit a file of integers that
## `ObjectiveDef.from_dict` cannot read at all, and the mistake would not show up until the
## export row.
##
## So the records are stored verbatim and `ObjectiveDef.from_dict` is used to **validate** them,
## never to hold them. That is also what makes `problems()` exact: the tool reports what the
## game's own loader will say about this file, in the game's own words, rather than an imitation.
##
## ## WHERE THEY GO ON DISK, AND WHY IT IS THE SIDECAR HEADER AND NOT `MapData`
##
## ⛔ **`MapData` GAINS NOTHING, WHICH IS THE OPPOSITE OF 16.5's AREAS AND DELIBERATE.** A region
## is part of what a map IS — `MapGen.build_from()` puts it on `SimWorld.areas` and a rule counts
## what is standing in it. A win condition is about the MATCH played on the map: nothing in
## `game/src` reads it off a `map.json`, and `ScenarioDef` is where the game gets its objectives
## from. Putting them in `MapData` would add a field to a hash-copied format file that the game
## would have two sources for — **the two dialects this whole row exists to prevent**, arrived at
## from the storage side instead of the vocabulary side.
##
## `MapFile.save()` already merges an arbitrary `header` over what it derives, and
## `_preserved_header()` carries forward every key `to_dict()` does not produce — so `objectives`
## round-trips through Open → Save with no edit to either. That is the same mechanism `map_type`
## and `seed` already ride.
##
## ⛔ **AND THE TRAP 16.5 PAID FOR, WHICH APPLIES HERE THROUGH THE OTHER DOOR: `save()` WRITES
## THIS KEY EVEN WHEN THE LIST IS EMPTY.** `_preserved_header()` never filters `objectives` out,
## because `MapData.to_dict()` does not produce it — so if `save()` wrote the key only when the
## list had something in it, deleting the author's last condition would leave the OPENED file's
## conditions in the preserved header, and **the deletion would not reach the file**: the row
## comes back on reopen after a save that reported success. `MapData.to_dict()` writes `areas`
## unconditionally for the mirror image of this reason.
##
## ## IT IS INERT IN THE GAME UNTIL 16.8, AND THAT IS NOT 16.3's "SILENTLY DROPPED"
##
## Nothing in `game/` reads these yet: a saved map carries its conditions and a skirmish played
## from it is still decided by conquest. **The difference from the Area tab 16.3 refused to ship
## is that nothing is lost** — the records reach the file, survive a reopen, and are what 16.8
## writes into a `scenario.json`. What 16.3 forbade was work that vanished behind a successful
## save. Flagged on the card rather than assumed to be obvious.
var objectives: Array[Dictionary] = []

## The `scenario.json` these conditions belong to, or `""` when they live in the map's sidecar.
##
## ⛔ **THIS FIELD IS THE CORRECTION THE OWNER FOUND ON 2026-09-12, AND IT IS WORTH KEEPING THE
## MISTAKE.** 16.6 shipped storing conditions in the map sidecar full stop — which is right for a
## standalone map and **wrong for the five shipped campaign maps**, the first thing anybody would
## try. `scenarios/HowToPlay/scenario_1/` holds `map.json` and `scenario.json` side by side and
## the conditions are in the second; the panel therefore announced *"no conditions"* for a
## scenario with two win rows, and a row added there would have gone into `map.json` where
## **nothing in `game/src` reads it.** Two sources for one fact, created for the case that
## matters most, by the design that was arguing against two sources.
##
## ⚠️ **RESOLVED ONCE, FROM WHERE THE MAP IS SAVED — NOT FROM WHERE IT WAS OPENED.** `save_as()`
## into `maps/` genuinely moves the conditions into the new map's sidecar, because the new
## location has no scenario beside it; `save()` re-resolves for the same reason. A field fixed at
## open would write a scenario's objectives into a copy's `scenario.json` that is not there.
var scenario_path: String = ""

## What that scenario says decides it (`"scenario"` / `"last_man_standing"`), or `""`.
##
## Read only so `objective_problems()` can warn about the one combination `ScenarioDef` refuses at
## load: a `last_man_standing` scenario carrying objectives, whose rows *"would never be read"*.
## **Scenario 3 is exactly that shape**, so an author adding a condition to it would author a
## campaign mission that refuses to start — and the tool is where there is somebody to tell.
var scenario_mode: String = ""


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
	# ⛔ **THE SCENARIO FILE WINS WHEN THERE IS ONE, AND THAT IS A FALLBACK CHAIN RATHER THAN TWO
	# SOURCES.** See `objectives` for the whole argument: a map in
	# `scenarios/<campaign>/<scenario>/` keeps its conditions in the `scenario.json` beside it,
	# because that is the file the GAME reads them from. A map without one parks them in its own
	# sidecar until 16.8 promotes it into a scenario. They never both apply.
	doc.scenario_path = ScenarioFile.path_beside(dir_path)
	if doc.scenario_path.is_empty():
		doc.objectives = _objectives_in(doc.header)
	else:
		var scenario := ScenarioFile.read(doc.scenario_path, out_problems)
		doc.objectives = ScenarioFile.objectives_in(scenario)
		doc.scenario_mode = ScenarioFile.mode_in(scenario)
	doc.dirty = false
	# THE FILE IS THE CLEAN POINT, at depth zero. Without this an author who opens a map, makes
	# two edits and undoes both is told the map is still unsaved -- true of the flag's old
	# meaning ("has anything been done") and false of the one that matters.
	doc.history.mark_clean()
	return doc


## The condition rows out of an opened sidecar (16.6). `[]` for a map that has none, which is
## every map written before this row existed.
##
## ## ⚠️ IT TAKES WHAT IT IS GIVEN AND DOES NOT VALIDATE
##
## A row that will not parse is **kept and reported**, never dropped. `objective_problems()` and
## the Conditions panel are where an author is told; silently discarding one would mean opening a
## hand-written scenario's map, saving it, and finding the condition gone — 16.4a's *"every change
## made in the tool silently discarded, in a save that reports success"* running the other way.
## `MapFile` already refuses a sidecar it cannot trust as a whole, so what arrives here is JSON
## that parsed.
##
## ⚠️ **A NON-OBJECT ENTRY IS THE ONE THING DROPPED**, because everything downstream indexes it
## as a Dictionary and a bare string in that list would crash the panel rather than be reported
## by it. A map file is untrusted input (`MapFile`'s own header), so this is the boundary.
##
## 📝 **JSON GIVES BACK FLOATS AND THAT IS HARMLESS HERE, WHICH IS WORTH SAYING BECAUSE IT
## USUALLY IS NOT.** `"value": 5` returns as `5.0`, and `ObjectiveDef.from_dict` calls `int()` on
## it at its own boundary — the conversion is the game's, in the game's file, so the tool does not
## need a second one. What it does mean is that a re-saved map writes `"value": 5.0`, the same
## float-widening `16.x-slow-place` found in the preserved `meta` block and flagged for 16.10.
static func _objectives_in(header: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var raw: Variant = header.get("objectives", [])
	if not raw is Array:
		return out
	for entry in (raw as Array):
		if entry is Dictionary:
			out.append((entry as Dictionary).duplicate())
	return out


# ── undo (PLAN.md 16.2a) ────────────────────────────────────────────────────

## Begin a gesture: everything until `end_stroke()` becomes ONE undo step.
##
## ⚠️ **THIS IS THE HALF OF UNDO THAT MAKES IT USABLE RATHER THAN MERELY PRESENT.** A stroke
## across a coastline is hundreds of `paint()` calls; one step each means taking back a
## mis-drag is hundreds of Ctrl+Z presses, and `UndoStack.LIMIT` holds less than one gesture.
## The card's own example — *"a mis-drag across a painted coastline is otherwise
## unrecoverable"* — is unrecoverable in exactly that way.
##
## **IT CLOSES ANY STROKE ALREADY OPEN FIRST**, so a mouse-release that never arrives (the
## pointer leaving the window, a dialog stealing the button) costs one over-large undo step
## rather than a step that grows for the rest of the session.
##
## No label: the first mutation inside names the step. See `_open()`.
func begin_stroke() -> void:
	end_stroke()
	_step = MapEdit.new("")
	_step_held = true


## End the gesture and put it on the stack. Idempotent — see `begin_stroke()`.
func end_stroke() -> void:
	_step_held = false
	_flush()


## Take the last step back. Returns what it undid, or "" when there was nothing.
##
## **THE OPEN STROKE IS CLOSED FIRST.** A keyboard event can arrive with the mouse button
## still down — Ctrl+Z mid-drag — and undoing the step *before* the one still accumulating
## would interleave the two: the open step lands on the stack afterwards, on top of a map it
## was not recorded against.
func undo() -> String:
	end_stroke()
	var step := history.take_undo()
	if step == null:
		return ""
	# THE CONDITIONS COME BACK AS A RETURN VALUE, because they are the one list that is not on
	# `MapData` -- see `objectives` and `MapEdit.undo_into()`. A step that recorded no lists hands
	# `objectives` straight back, so a paint step leaves the conditions alone.
	objectives = step.undo_into(data, objectives)
	# ⚠️ **THE SELECTION GOES, because a step replaces the entity list from a snapshot** that may
	# be a different length and a different order. Keeping the index would point the inspector at
	# whatever now sits at that position -- and the author's next owner change would land on it,
	# silently. Losing a highlight is the cheap failure of the two. See `selected`.
	clear_selection()
	dirty = not history.at_clean_point()
	return step.describe()


func redo() -> String:
	end_stroke()
	var step := history.take_redo()
	if step == null:
		return ""
	objectives = step.redo_into(data, objectives)
	clear_selection()                     # same reason as `undo()`
	dirty = not history.at_clean_point()
	return step.describe()


## Open a step for `p_label`, or join whichever is already open.
##
## Returns true when the CALLER owns the step and must `_flush()` it — false when a stroke or
## an outer mutation is holding it, in which case that one will. `place_start()` calls
## `remove_start()` inside its own step and relies on the second answer; a drag relies on the
## first being false for every tile after the press.
##
## **THE FIRST ACT IN A STEP NAMES IT.** A stroke is opened by a mouse-press that does not yet
## know whether the author is about to paint sand or place a dock, so the labels live in the
## mutations — one place — rather than being computed a second time next to the tool enum.
func _open(p_label: String) -> bool:
	if _step != null:
		if _step.label.is_empty():
			_step.label = p_label
		return false
	_step = MapEdit.new(p_label)
	return true


## Close the open step and push it, unless a stroke is still holding it.
func _flush() -> void:
	if _step == null or _step_held:
		return
	var step := _step
	_step = null
	# SEALED HERE AND NOWHERE ELSE -- `MapEdit.close()` explains why the "after" snapshot cannot
	# be left to the six mutations to remember.
	step.close(data, objectives)
	if step.changes_anything():
		history.push(step)


## `SimMap.Terrain`'s name for a kind, for a label a person reads.
##
## Shared with the editor's status line rather than written twice: `keys()` is indexed by the
## enum's value, so a kind from outside it would be an out-of-bounds read — hence the guard,
## which is also the only thing that makes this safe to call on a byte read from a file.
static func terrain_name(kind: int) -> String:
	var keys := SimMap.Terrain.keys()
	if kind < 0 or kind >= keys.size():
		return "terrain %d" % kind
	return str(keys[kind]).capitalize()


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
	# RECORDED BEFORE THE WRITE, obviously, but note that the early return above is what keeps
	# the record honest as well as cheap: a repaint of the same kind never reaches here, so a
	# step cannot fill with no-op diffs and `MapEdit`'s reverse-order rule has nothing to undo.
	var mine := _open("paint %s" % terrain_name(kind))
	_step.terrain_change(data.index_of(tile), data.terrain_at(tile), kind)
	data.set_terrain(tile, kind)
	dirty = true
	if mine:
		_flush()
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
	# ONE STEP FOR BOTH HALVES, which is the undo side of the same argument the comment above
	# makes: `remove_start()` records into this step rather than opening its own, so taking back
	# a re-placed start restores the cluster that was there instead of leaving the map with
	# neither. `MapEdit.lists_before()`'s guard is what makes the nesting safe.
	var mine := _open("place P%d's start" % player)
	_step.lists_before(data, objectives)
	remove_start(player)
	while data.starts.size() < player:
		data.starts.append(Vector2i(-1, -1))
	data.starts[player - 1] = centre
	StartLayout.place(data, player, centre)
	dirty = true
	if mine:
		_flush()
	return true


## Take a player's start and everything placed for them back off the map.
##
## **BY THE TAG `StartLayout` LEAVES, AND BY OWNER *WITHIN THE CLUSTER'S REACH*.** Two rules
## because a start has two kinds of thing in it:
##
##   - the base and its units are `player`-owned, so the owner finds them — **but only near the
##     start**, see the ⛔ below;
##   - **every resource node is gaia (`player: 0`)** and is indistinguishable from a tree an
##     author placed deliberately. `StartLayout.ORIGIN_KEY` says which start put it there.
##
## A test caught what happens without the second rule: placing a start twice left the first
## cluster behind and the entity count went 24 → 40, so a mis-clicked start littered the map
## permanently. Deleting "gaia things near the start" instead is the tempting alternative and is
## worse: it would eat the author's own trees the moment 16.3 lets them place any.
##
## ⛔ **THE OWNER CLAUSE HAD NO BOUND AND THAT WIPED THE MAP. THE PROJECT OWNER FOUND IT IN THE
## TOOL, 2026-09-09:** *"the start wipes the entire map when placed, even a wall on the opposite
## side of the map?"* It did, and `place_start()` calls this first, so **placing P1's start deleted
## every P1-owned entity anywhere on the map.**
##
## ⚠️ **THE RULE WAS RIGHT WHEN IT WAS WRITTEN AND 16.3 EXPIRED IT.** "Owned by P1" meant "part of
## P1's start" only while a start was the *only* way a player-owned entity could reach a map. The
## palette's **Owner** dropdown broke that premise and nothing came back to re-read the rule
## resting on it. The bound is `StartLayout.owned_reach()`, derived from the ring the units are
## actually placed on, so this is now **a strict subset of what it deleted before**: everything it
## used to take within the cluster it still takes, and nothing outside it.
##
## ⚠️ **A FIRST PLACEMENT NOW SWEEPS NOTHING OWNED AT ALL**, which is the strongest form of the fix
## rather than a special case: there is no previous centre to measure from, so the owner clause
## does not apply. The old code never consulted position, so a first start on a decorated map was
## the exact gesture that wiped it.
##
## 📝 **WHAT IS LEFT, AND WHY IT IS THE RIGHT RESIDUE.** `MapFile` drops `ORIGIN_KEY` on save, so
## on a REOPENED map the tag is gone and the owner clause is all there is — which is exactly why it
## cannot simply be deleted in favour of the tag. The two residual cases are both visible and both
## undoable, which is the trade this project keeps making: an author's own P1 building **inside**
## the cluster goes with the start (deliberate: re-placing a start is an act on that ground), and a
## start's villager the author has since dragged **outside** the reach survives a re-place on a
## reopened map as one stray unit. `StartLayout.audit()` reports the second. Silent destruction of
## work sixty tiles away is not in that category.
func remove_start(player: int) -> void:
	var mine := _open("clear P%d's start" % player)
	_step.lists_before(data, objectives)
	# ⚠️ **READ BEFORE IT IS CLEARED.** The centre below is the OLD one — what the owner clause
	# measures distance from — and the next three lines are what erase it. `place_start()` writes
	# the new centre only after this function returns, so this is the one window it is readable in.
	var was := Vector2i(-1, -1)
	if player >= 1 and player <= data.starts.size():
		was = data.starts[player - 1]
		data.starts[player - 1] = Vector2i(-1, -1)
	var reach := StartLayout.owned_reach()
	var kept: Array[Dictionary] = []
	for e in data.entities:
		var from_this_start := int(e.get(StartLayout.ORIGIN_KEY, 0)) == player
		var owned_near := false
		if not from_this_start and int(e.get("player", 0)) == player and was.x >= 0:
			# ⚠️ `tile`, NOT `x`/`y`. An in-memory entity carries a `Vector2i` under `tile`; `x`
			# and `y` exist only in the SAVED dictionary. `StartLayout._tally` has the scar: it
			# read `x`, got 0 for everything, and attributed every gaia node to whichever start
			# was nearest (0,0).
			var t: Vector2i = e.get("tile", Vector2i.ZERO)
			# CHEBYSHEV, which is the metric the whole cluster is laid out on and the one the sim
			# measures range in. Euclidean here would spare the corners of a ring built as a square.
			owned_near = maxi(absi(t.x - was.x), absi(t.y - was.y)) <= reach
		if not owned_near and not from_this_start:
			kept.append(e)
	data.entities = kept
	# THE LIST WAS FILTERED, so every index past the first removal now names something else.
	# See `selected`: this is one of the three acts that can leave it stale.
	clear_selection()
	# TRAILING PLACEHOLDERS TRIMMED, so `player_count()` -- which IS `starts.size()` -- does
	# not count a slot nobody is in. An untrimmed tail would make a two-player map claim four
	# and the picker would offer seats that lead nowhere.
	while not data.starts.is_empty() and data.starts[data.starts.size() - 1] == Vector2i(-1, -1):
		data.starts.resize(data.starts.size() - 1)
	dirty = true
	if mine:
		# **NOTHING IS PUSHED WHEN NOTHING WENT.** `Clear start` on a player who never had one
		# still runs every line above, and `MapEdit.changes_anything()` is what stops that
		# becoming an undo step the author cannot see the effect of taking back.
		_flush()


## Repaint the whole map. Not on a button today — `dev/author_map.gd` and the tests use it.
##
## The diff is the tiles that actually differ rather than the whole buffer, so a fill over a
## map that is already mostly grass records almost nothing. On the largest map with the most
## varied terrain it records 65,536 changes, which is 393 KB and one loop over the buffer —
## paid on a deliberate act nothing calls in a drag.
func fill_all(kind: int) -> void:
	var mine := _open("fill with %s" % terrain_name(kind))
	for i in data.terrain.size():
		if data.terrain[i] != kind:
			_step.terrain_change(i, data.terrain[i], kind)
	data.fill_terrain(kind)
	dirty = true
	if mine:
		_flush()


## Put one thing on the map at `tile` (PLAN.md 16.3). Returns true if it went down.
##
## ## IT ASKS `claimed_tiles()` AND NEVER A SECOND OPINION
##
## ⚠️ 16.4's row is explicit: *"use `MapData.claimed_tiles()` and `footprint_rect_of()` rather
## than writing a second collision test — they are what the generator and the validator already
## agree on, and a third opinion about what is in the way is a map that validates and cannot be
## built."* So the overlap check here is those two functions and nothing else, which also means
## it uses the **sim's** footprint rather than the visual's measured extent: §6's row explains
## that they are two different rects and both are right, and the one that decides whether a
## thing can be built is the sim's.
##
## ## WHAT IT REFUSES, AND WHY EACH REFUSAL IS NOT A VALIDATOR RULE
##
## Off the map and on top of something else — those are the two a *placement* can be sure
## about. **Everything else is `MapValidator`'s and stays there** (16.4b): whether a start can
## reach another start, whether a player has resources in walking distance, whether a sea map's
## players can build a dock. Deciding any of that here would be the second opinion decision 3
## exists to prevent, and it would refuse work an author is halfway through.
##
## ⚠️ **IT DOES NOT REFUSE IMPASSABLE GROUND, AND THAT IS DELIBERATE.** A dock belongs on
## water, a fish is in it, and `StartLayout` already declines to put *units* on ground they
## cannot stand on. A placement tool that second-guessed the author about terrain would make
## the two things this game most needs on a coast unplaceable.
func add_entity(def_id: StringName, player: int, tile: Vector2i, size_class := 0,
		axis := MapData.AXIS_NONE) -> bool:
	if def_id.is_empty() or not data.in_bounds(tile):
		return false
	# ⚠️ **THE PROBE CARRIES THE AXIS, or a wall laid north-south is collision-checked against
	# the footprint of one laid east-west.** `footprint_rect_of()` transposes on this key, so
	# leaving it out here would test `[9, 2]` and then write an entity the world builds as
	# `[2, 9]` — a placement the tool accepted, on ground it never looked at. Same key, same
	# function, one opinion.
	var wanted := MapData.footprint_rect_of({
		"def_id": def_id, "tile": tile, "size_class": size_class, "axis": axis,
	})
	var claimed := data.claimed_tiles()
	for t in wanted:
		# THE WHOLE FOOTPRINT MUST BE ON THE MAP, not just its origin tile. A 10x10 town centre
		# dropped two tiles from the edge would otherwise author a building whose claimed tiles
		# run off the board -- and `MapGen.build_from()` would place it, half in the void.
		if not data.in_bounds(t) or claimed.has(t):
			return false
	# OPENED AFTER THE REFUSALS, so a click on occupied ground records nothing at all rather
	# than an empty step -- the author's next Ctrl+Z should reach the last thing that landed,
	# not the last thing they tried.
	var mine := _open("place %s" % GameDataRegistry.display_name(def_id))
	_step.lists_before(data, objectives)
	data.add_entity(def_id, player, tile, size_class, axis)
	dirty = true
	if mine:
		_flush()
	return true


## Take whatever is standing on `tile` back off the map. Returns how many entries went.
##
## **BY CLAIMED TILES AND NOT BY ORIGIN**, because an author clicking the middle of a 10x10
## town centre is pointing at the town centre — a delete that only matched the origin tile
## would do nothing nine times out of ten and read as a broken tool.
##
## ⚠️ **IT REFUSES TO TOUCH A START'S OWN CLUSTER**, and `remove_start()` is why: that function
## deletes by the `StartLayout.ORIGIN_KEY` tag and by owner within the cluster's reach, precisely
## so a start's base and its opening resources go together. Letting this pick one villager out of a start would leave
## a cluster the tag no longer describes, which is the state that took the entity count 24 → 40
## the first time it was got wrong. Clearing a start is `Clear start`.
func remove_entity_at(tile: Vector2i) -> int:
	var kept: Array[Dictionary] = []
	var removed := 0
	for e in data.entities:
		if int(e.get(StartLayout.ORIGIN_KEY, 0)) > 0:
			kept.append(e)
			continue
		var covers := false
		for t in MapData.footprint_rect_of(e):
			if t == tile:
				covers = true
				break
		if covers:
			removed += 1
		else:
			kept.append(e)
	if removed > 0:
		# THE SNAPSHOT IS TAKEN HERE, after `kept` is built and before it is assigned, which is
		# the only window in which `data.entities` still holds the state to restore.
		var mine := _open("erase %d thing%s" % [removed, "" if removed == 1 else "s"])
		_step.lists_before(data, objectives)
		data.entities = kept
		clear_selection()                 # the list shrank; see `selected`
		dirty = true
		if mine:
			_flush()
	return removed


# ── areas: named regions (PLAN.md 16.5) ─────────────────────────────────────

## Add one rectangle to the region called `name`. True when it went down.
##
## ## AN AREA IS NOT AN ENTITY, AND EVERY DIFFERENCE FALLS OUT OF THAT
##
## It claims no tiles, so it collides with nothing: **regions may overlap each other, entities
## and the map's own furniture freely**, which is not a slip — *"the crossing"* and *"the north
## bank"* genuinely share ground, and a region drawn over a town centre is how *"hold the base"*
## is asked. `add_entity()`'s overlap test therefore has no counterpart here, and
## `MapData.claimed_tiles()` is untouched by areas on purpose.
##
## ## WHAT IT DOES REFUSE, AND WHY THE BOUNDS CHECK IS HERE RATHER THAN IN `MapData`
##
## Off the map, unnamed, and empty. `MapData.add_area()` already refuses the last two — it is the
## format's own definition of a region — and deliberately does **not** refuse the first, because
## a loaded file may carry a region hanging off the edge of a map somebody later shrank and
## dropping it on load would silently change what a scenario counts. **The tool is where there is
## a person to tell**, so this is the layer that says no. Same division `add_entity()` makes: the
## whole footprint must be on the map, checked where a notice can be shown.
##
## ⚠️ **THE NAME IS TAKEN VERBATIM.** `ObjectiveSystem` matches it against an objective's `area`
## with no folding at either end, so trimming here and not there — or lower-casing in the tool and
## not in the game — would author a region the scenario can never find. Whitespace is stripped
## because a trailing space is invisible in a text field and is otherwise a different region; that
## strip is the one normalisation, it happens in `MapData.add_area()`'s own refusal test too, and
## `ObjectiveDef._read_area` strips the objective's end identically.
func add_area(name: StringName, rect: Rect2i) -> bool:
	var clean := StringName(String(name).strip_edges())
	if clean.is_empty() or rect.size.x <= 0 or rect.size.y <= 0:
		return false
	# THE WHOLE RECTANGLE ON THE MAP. `end` is exclusive, so the last tile is `end - ONE`.
	if not data.in_bounds(rect.position) or not data.in_bounds(rect.end - Vector2i.ONE):
		return false
	var mine := _open("area %s" % clean)
	_step.lists_before(data, objectives)
	if not data.add_area(clean, rect):
		# UNREACHABLE THROUGH THE GUARDS ABOVE, and it still puts the step back rather than
		# leaving one open: `_flush()` on an empty step pushes nothing (`changes_anything()`),
		# so this is the same shape as `add_entity()` refusing before it opens.
		if mine:
			_flush()
		return false
	dirty = true
	if mine:
		_flush()
	return true


## Take the region rectangle under `tile` off the map. Returns how many entries went.
##
## **THE TOPMOST ONE ONLY, WHICH IS ONE RECTANGLE AND NOT A WHOLE REGION.** `entity_index_at()`'s
## rule — the last match wins, because that is the one drawn over the others — and the reason it
## is one rather than all is the same reason an area is a flat list: an author who mis-drags the
## fourth rectangle of a five-rectangle region wants that rectangle back, not the region deleted.
## Clearing a whole region is as many clicks as it has parts, which is visible; deleting four
## rectangles the author still wanted is not.
func remove_area_at(tile: Vector2i) -> int:
	var at := area_index_at(tile)
	if at < 0:
		return 0
	var mine := _open("erase area %s" % data.areas[at].get("name", &""))
	_step.lists_before(data, objectives)
	data.areas.remove_at(at)
	dirty = true
	if mine:
		_flush()
	return 1


## Which region rectangle covers `tile`, or -1.
##
## **THE LAST MATCH WINS**, `entity_index_at()`'s rule and for its reason: `MapCanvas` draws the
## list in order, so a later rectangle is painted over an earlier one and a picker returning the
## first would hand back the region underneath the one the author can see. Regions overlapping is
## normal here rather than a fault, which makes this matter more than it does for entities.
func area_index_at(tile: Vector2i) -> int:
	var found := -1
	for i in data.areas.size():
		var rect: Rect2i = data.areas[i].get("rect", Rect2i())
		if rect.has_point(tile):
			found = i
	return found


## Every region name on the map, in first-appearance order. What the palette's Areas tab lists.
func area_names() -> Array[StringName]:
	return data.area_names()


# ── conditions: the authored win/lose vocabulary (PLAN.md 16.6) ─────────────

## Add one condition row. False and a sentence in `out_problems` when it will not parse.
##
## ## ⚠️ IT IS VALIDATED BY THE GAME'S OWN LOADER, WHICH IS THE WHOLE POINT OF THE ROW
##
## `format/objective_def.gd` is a hash-checked verbatim copy, so what refuses a bad row here is
## the exact function that will read the exported `scenario.json` — same messages, same edge
## cases, same refusals. PLAN.md 11.8a's requirement is *"one language, written down once"*, and
## a tool that validated with its own imitation of that parser would be the second dialect the
## requirement forbids, written in the one place nobody would look for it.
##
## ## WHY A PARSE FAILURE IS REFUSED HERE AND "NO WIN ROW" IS ONLY WARNED ABOUT ON SAVE
##
## 16.4b's rule, applied to a third thing: **a row that cannot parse is a corrupt record and a
## list with no win row is an unfinished map.** A record `ObjectiveDef` rejects can never mean
## anything to anybody, and there is a person standing right here to tell — `add_entity()`
## refusing an overlap is the same call. Whereas an author who adds their lose row before their
## win row has a perfectly ordinary half-finished list, and a tool that refused it would be
## refusing to let them work. That one is `objective_problems()`, reported by `save()` beside
## `MapValidator`'s.
##
## ⚠️ **THE REGION ON AN `area` ROW IS NOT CHECKED HERE EITHER, AND THAT IS NOT AN OVERSIGHT.**
## `ObjectiveDef` has never seen a map and says so at length; an author may also legitimately
## write the condition before dragging the region. It is `objective_problems()`.
func add_objective(record: Dictionary, out_problems: Array[String]) -> bool:
	if not _parses(record, out_problems):
		return false
	# OPENED AFTER THE REFUSAL, `add_entity()`'s rule: a rejected row records nothing at all,
	# so the author's next Ctrl+Z reaches the last thing that actually landed.
	var mine := _open("add %s condition" % _output_word(record))
	_step.lists_before(data, objectives)
	objectives.append(record.duplicate())
	dirty = true
	if mine:
		_flush()
	return true


## Replace row `at`. False and a sentence when the new record will not parse.
##
## ⚠️ **IT CALLS `mark_changed()`, FOR `move_selected()`'s REASON EXACTLY.** This edits a row in
## place: same list length, same everything else, different fields — and `MapEdit.close()`'s test
## is a SIZE comparison, which cannot see it. Without this the step is discarded as a no-op and
## an edited condition cannot be taken back. That file's own 📝 note predicted this row would owe
## it.
##
## **THE LIVE RECORD IS REPLACED RATHER THAN MUTATED**, so a caller holding the old dictionary
## cannot write through it afterwards and reach the map behind the undo stack — `selected_entity()`
## hands out a live dictionary deliberately and this deliberately does not, because a condition
## row has no inspector reading fields off it frame by frame.
func set_objective(at: int, record: Dictionary, out_problems: Array[String]) -> bool:
	if at < 0 or at >= objectives.size():
		return false
	if not _parses(record, out_problems):
		return false
	if objectives[at] == record:
		# NOT A STEP AND NOT A FAILURE, `move_selected()`'s rule: re-confirming a dialog without
		# changing anything must not put an invisible entry on the stack.
		return true
	var mine := _open("edit %s condition" % _output_word(record))
	_step.lists_before(data, objectives)
	objectives[at] = record.duplicate()
	_step.mark_changed()
	dirty = true
	if mine:
		_flush()
	return true


## Take row `at` off the map. Returns how many went (0 or 1).
func remove_objective(at: int) -> int:
	if at < 0 or at >= objectives.size():
		return 0
	var mine := _open("remove %s condition" % _output_word(objectives[at]))
	_step.lists_before(data, objectives)
	objectives.remove_at(at)
	dirty = true
	if mine:
		_flush()
	return 1


## Would the game's loader accept this record? The reason goes in `out_problems`.
##
## `ObjectiveDef.from_dict` appends every complaint it has rather than returning one, which is
## why this passes the caller's array straight through — an author fixing one typo per attempt is
## an author pressing Add five times.
static func _parses(record: Dictionary, out_problems: Array[String]) -> bool:
	return ObjectiveDef.from_dict(record, out_problems) != null


## `win` / `lose` / `alert` for a step label, defaulting the way `ObjectiveDef` does.
static func _output_word(record: Dictionary) -> String:
	return str(record.get("output", "win")).to_lower()


## How many rows end the match in the author's favour. `ScenarioDef` refuses a `scenario` with
## none, so this is the figure the Conditions panel puts in front of a person.
func win_count() -> int:
	var n := 0
	for r in objectives:
		if _output_word(r) == "win":
			n += 1
	return n


## What is wrong with the condition list as a whole. Empty is the healthy answer.
##
## ## THESE ARE WARNINGS, NOT REFUSALS — `MapDocument.warnings`' distinction, a third time
##
## Both checks below describe an unfinished map rather than a corrupt file, and 16.4b's rule is
## that the tool must not refuse to WRITE over an opinion about the map. An author who closes the
## tool with one lose row drafted has lost nothing; an author refused a save has lost the session.
##
## ## ⚠️ THE FIRST CHECK IS THE CARD'S, AND WHAT IT DELIBERATELY DOES NOT ASK FOR IS A LOSE ROW
##
## PLAN.md 16.6: *"it validates that there is at least one WIN and does not ask for a lose — the
## README's 'at least one lose condition' requirement is dropped, because owning nothing is
## defeat on every map in this game whatever it declares."* So a map with **no conditions at all**
## is silent here: its answer is *"beat them"*, which is what `LAST_MAN_STANDING` already means,
## and `ScenarioDef` refuses a `last_man_standing` scenario that carries objectives. A list that
## has rows but no win row is the one shape that can never be won.
##
## ## ⚠️ AND THE SECOND IS THE ONE ONLY THIS TOOL CAN MAKE EARLY
##
## An `area` row naming a region the map has not got counts **0 forever** — `ObjectiveDef`'s own
## header calls it the `stock.get(&"foood", 0)` failure wearing a place, an unwinnable scenario
## whose only symptom is that nothing happens. `ScenarioDef.build_config()` already refuses it at
## launch, which is the defence that reaches a player. **This is the one that reaches the
## AUTHOR**, at the moment they can still fix it, and it is possible here for the one reason it
## is impossible in `ObjectiveDef`: this is the only place in either project where the conditions
## and the map are open in front of the same person.
##
## It asks `MapData.has_area()` — the same function `build_config()` asks — so it is one opinion
## reached from two places rather than a second implementation.
func objective_problems() -> Array[String]:
	var out: Array[String] = []
	# ⛔ **THE THIRD CHECK, AND IT ONLY EXISTS ONCE THE CONDITIONS LIVE IN A SCENARIO** (2026-09-12).
	# `ScenarioDef._read_objectives` refuses a `last_man_standing` scenario that carries objectives
	# outright — *"its objective(s) would never be read"* — so adding one to such a file authors a
	# campaign mission that will not start. **Scenario 3 is exactly that shape**, and it is one of
	# the five this tool exists to re-author, so this is a trap an author walks into by doing the
	# obvious thing. The tool cannot fix it (the `mode` is the scenario's, not the map's, and
	# changing it would rewrite what decides the mission) so it says so.
	if not objectives.is_empty() and scenario_mode == "last_man_standing":
		out.append("%s says mode 'last_man_standing', which is decided by conquest"
				% scenario_path.get_file()
				+ " -- these %d condition(s) would never be read," % objectives.size()
				+ " and the scenario will refuse to start. Change its mode to 'scenario'")
	# ⚠️ **AND THE MIRROR OF IT, WHICH IS THE ONE CASE WHERE AN EMPTY LIST IS NOT HEALTHY.**
	# `ScenarioDef` refuses BOTH directions — a `last_man_standing` carrying rows, and a
	# `scenario` with no win row, which *"can never be won"*. So "no conditions is fine" is true
	# of a map and of a conquest scenario, and false of a scenario that declares it is decided by
	# objectives. Without this the tool would cheerfully report *"won by conquest"* about a file
	# the front door will not open.
	#
	# ⚠️ **THE TWO ARE EXCLUSIVE, AND THE SCENARIO ONE WINS BECAUSE IT KNOWS MORE.** Both describe
	# "there is no way to win", and a map beside a `scenario.json` can satisfy both at once — two
	# sentences for one fault is how a warning list stops being read. The scenario version names
	# the file and says it will refuse to START, which is the fact that changes what the author
	# does next; the generic one is what a standalone map gets.
	if win_count() == 0 and scenario_mode == "scenario":
		out.append("%s says mode 'scenario', which is decided by its objectives"
				% scenario_path.get_file()
				+ " -- with no win condition it can never be won, and it will refuse to start."
				+ " Add one, or change its mode to 'last_man_standing'")
	elif not objectives.is_empty() and win_count() == 0:
		out.append("this map has %d condition(s) and none of them is a win"
				% objectives.size()
				+ " -- a scenario with no win row can never be won."
				+ " Add one, or remove them all to mean 'beat them'")
	for i in objectives.size():
		var record: Dictionary = objectives[i]
		if str(record.get("subject", "")).to_lower() != "area":
			continue
		# STRIPPED THE WAY `ObjectiveDef._read_area` STRIPS IT, and matched verbatim after that.
		# Folding or trimming differently at either end would author a region the scenario can
		# never find -- `MapDocument.add_area()`'s note is the other half of this rule.
		var name := StringName(str(record.get("area", "")).strip_edges())
		if data.has_area(name):
			continue
		var names := data.area_names()
		var have := "this map declares no regions at all"
		if not names.is_empty():
			have = "this map declares %s" % ", ".join(_as_strings(names))
		out.append("condition %d counts things in '%s' and %s" % [i + 1, name, have])
	return out


## `Array[StringName]` as plain strings, for `join`. `PackedStringArray` will not take
## StringNames directly.
static func _as_strings(names: Array[StringName]) -> PackedStringArray:
	var out := PackedStringArray()
	for n in names:
		out.append(String(n))
	return out


# ── select, move, edit: the three cursors (PLAN.md 16.4) ────────────────────

## Which entity is standing on `tile`, or -1.
##
## **BY CLAIMED TILES AND NOT BY ORIGIN**, `remove_entity_at()`'s rule and for its reason: an
## author clicking the middle of a 10x10 town centre is pointing at the town centre, and a
## picker that only matched the origin tile would miss it ninety-nine times in a hundred.
##
## ⚠️ **THE LAST MATCH WINS, WHICH IS THE ONE DRAWN ON TOP.** `_draw_entities` walks the list in
## order, so a later entity is painted over an earlier one — and a picker that returned the
## first match would hand back the thing underneath the thing the author can see. Overlaps are
## not supposed to happen (`add_entity` refuses them and `MapValidator` reports them) but an
## OPENED map can carry them, because 16.4b's rule is that a bad map still saves.
func entity_index_at(tile: Vector2i) -> int:
	var found := -1
	for i in data.entities.size():
		for t in MapData.footprint_rect_of(data.entities[i]):
			if t == tile:
				found = i
				break
	return found


## Which player's start marker is on `tile`, or inside the base standing there. 0 for none.
##
## ## WHY ERASE NEEDS THIS AND `entity_index_at()` IS NOT ENOUGH
##
## The owner's ruling of 2026-09-08 made the start a palette entry placed with PLACE and cleared
## with ERASE, which retired the toolbar's `Place start` / `Clear start` pair. So ERASE has to
## recognise a start — and a start is **not an entity**: it is a `MapData.starts` slot, and the
## thing an author can actually see and click is the **town centre `StartLayout` put on it**.
##
## Two lookups, because there are two ways to be pointing at one:
##
##   1. the marker tile itself, for a start whose base has been erased or was never there
##      (`place_start` always lays one down, but `MapFile` can load a map that has none);
##   2. **any tile of the base that carries it**, which is the case that matters — a 10x10 town
##      centre is what fills the screen, and `starts` holds its CENTRE, so a click three tiles
##      from the middle is a click on the start and matches neither tile directly.
##
## **1-based, because `starts` is indexed by player number - 1** and `place_start`/`remove_start`
## both take the player. Zero means none, which is also gaia's owner id and cannot collide here:
## there is no player 0 with a start.
func start_owner_at(tile: Vector2i) -> int:
	for i in data.starts.size():
		if data.starts[i] == tile:
			return i + 1
	var at := entity_index_at(tile)
	if at < 0:
		return 0
	var e := data.entities[at]
	if not _is_town_centre(e):
		return 0
	var inside := _starts_inside(e)
	return inside[0] + 1 if not inside.is_empty() else 0


## The selected entity's record, or `{}`.
##
## Returns the LIVE dictionary rather than a copy, deliberately: the editor's inspector reads
## fields off it to fill its controls, and a copy would go stale the moment anything moved.
## Nothing outside this class writes through it — that is `set_selected_*` below, which have to
## record an undo step.
func selected_entity() -> Dictionary:
	if selected < 0 or selected >= data.entities.size():
		return {}
	return data.entities[selected]


## Pick whatever is on `tile`. Returns true when the selection CHANGED.
##
## **A CLICK ON EMPTY GROUND CLEARS IT**, which is the behaviour every editor has and the only
## one that lets an author get *out* of a selection without another tool. It is not an undo
## step: selecting is not a change to the map, so `dirty` is untouched and Ctrl+Z reaches past
## it to the last real act.
func select_at(tile: Vector2i) -> bool:
	var was := selected
	selected = entity_index_at(tile)
	return selected != was


func clear_selection() -> void:
	selected = -1


## Move the selected entity so its footprint's origin lands on `to`. True if it moved.
##
## ## THE OVERLAP CHECK SKIPS THE THING BEING MOVED, AND THAT IS THE WHOLE DIFFICULTY
##
## `data.claimed_tiles()` includes the mover's own tiles, so asking it directly means a building
## can never be nudged one tile — it collides with where it already is. The tempting fix is to
## take the full set and `erase()` the mover's tiles from it, and that is subtly wrong: on a map
## with a pre-existing overlap (an opened map may have one) erasing frees tiles a DIFFERENT
## entity still claims, so the move lands on top of it.
##
## So the set is built from the other entities. ⚠️ **THAT IS NOT A SECOND FOOTPRINT TEST** —
## 16.4's row forbids one and it would be right to — because every rect still comes from
## `MapData.footprint_rect_of()`, the function the generator and the validator agree on. What is
## re-walked is the LIST, not the arithmetic.
##
## ⚠️ **IT CALLS `mark_changed()`, WHICH 16.2a's ROW REQUIRES IN SO MANY WORDS.** This is the
## first act in the tool that edits an entry **in place**: same entity count, same starts,
## different tile. `MapEdit.close()`'s size test cannot see that, so the step would be discarded
## as a no-op and **a dragged building could not be dragged back.**
func move_selected(to: Vector2i) -> bool:
	var e := selected_entity()
	if e.is_empty() or not data.in_bounds(to):
		return false
	var from: Vector2i = e.get("tile", Vector2i.ZERO)
	if from == to:
		# NOT A STEP AND NOT A FAILURE. A drag delivers the same tile many times over; recording
		# each one would fill the stack with acts whose effect nobody can see.
		return false
	if not _fits(e, to, selected):
		return false

	# ⚠️ **WHICH STARTS THIS ENTITY CARRIES, WORKED OUT BEFORE IT MOVES.** See `_starts_inside()`:
	# a start is the footprint's CENTRE and an entity's `tile` is its ORIGIN, so the two are only
	# equal for a 1x1 thing — the first version of this compared them directly and could never
	# match a town centre, which is a five-tile error and exactly the one `preview_saved_map`'s
	# second red run is the record of. Found by `test_cursors`.
	var carried := _starts_inside(e) if _is_town_centre(e) else ([] as Array[int])

	var mine := _open("move %s" % GameDataRegistry.display_name(e.get("def_id", &"")))
	_step.lists_before(data, objectives)
	# THE LIVE DICTIONARY IS EDITED IN PLACE, which is safe only because `MapEdit._copied()`
	# duplicates each entity DICTIONARY and not just the array. Without that the snapshot and
	# the map would share this dictionary and undo would restore the building to where it had
	# just been dragged -- `test_undo` performs exactly this edit against the guard.
	e["tile"] = to
	# ⚠️ **A START MOVES WITH ITS OWN TOWN CENTRE.** `MapData.starts` is a separate field and
	# `MapGen.build_from()` never derives a base from a start, so dragging a town centre off its
	# marker authors a player whose start is bare ground -- 16.0's `can_start()` rule 7 exactly.
	#
	# **SHIFTED BY THE SAME DELTA rather than set to the new origin**, so a marker that sat
	# off-centre inside the footprint stays where it was relative to the building. Only a town
	# centre carries a start: an author dragging a villager out of the opening is doing something
	# ordinary and must not drag the player's whole beginning with it.
	for i in carried:
		data.starts[i] = data.starts[i] + (to - from)
	_step.mark_changed()
	dirty = true
	if mine:
		_flush()
	return true


## Change who owns the selected entity. True if it changed.
##
## **GAIA (0) IS A LEGITIMATE OWNER AND NOT A CLEAR.** Every resource node on every map is
## gaia's, and so is the dragon and her nest (13.2), so an owner picker that treated 0 as
## "none" could not author half the things a map needs.
func set_selected_owner(player: int) -> bool:
	var e := selected_entity()
	if e.is_empty() or player < 0 or player > 8:
		return false
	if int(e.get("player", 0)) == player:
		return false
	var mine := _open("owner of %s" % GameDataRegistry.display_name(e.get("def_id", &"")))
	_step.lists_before(data, objectives)
	e["player"] = player
	# IN PLACE AGAIN, so the same rule as `move_selected` applies: the size test is blind to it.
	_step.mark_changed()
	dirty = true
	if mine:
		_flush()
	return true


## Change the selected entity's size class — the resource axis. True if it changed.
##
## ⚠️ **SIZE IS A FOOTPRINT, SO THIS CAN BE REFUSED FOR THE SAME REASON A PLACEMENT CAN.**
## `ResourceDef.footprint_for_size` makes a large gold mine bigger than a small one, so growing
## one can run off the map or into a neighbour — and a size change that silently overlapped
## would author exactly the map `MapValidator` refuses. Checked with `_fits()`, the same test
## the move uses.
func set_selected_size_class(size_class: int) -> bool:
	var e := selected_entity()
	if e.is_empty() or size_class < 0:
		return false
	if int(e.get("size_class", 0)) == size_class:
		return false
	# ASKED OF A COPY, because `_fits` reads `size_class` to work out the footprint and the whole
	# question is whether the NEW one fits. Editing the live record first and undoing it on
	# refusal would leave a step half-open.
	var probe := e.duplicate()
	probe["size_class"] = size_class
	if not _fits(probe, e.get("tile", Vector2i.ZERO), selected):
		return false
	var mine := _open("size of %s" % GameDataRegistry.display_name(e.get("def_id", &"")))
	_step.lists_before(data, objectives)
	e["size_class"] = size_class
	_step.mark_changed()
	dirty = true
	if mine:
		_flush()
	return true


## Would `e`'s footprint, placed with its origin at `origin`, be on the map and on clear ground?
##
## `skip` is an index in `data.entities` to ignore — the entity being moved or resized. See
## `move_selected()` for why the set is built rather than taken from `claimed_tiles()` and
## reduced.
##
## **IT DOES NOT REFUSE IMPASSABLE GROUND**, `add_entity()`'s rule: a dock belongs on water and
## a fish is in it.
func _fits(e: Dictionary, origin: Vector2i, skip: int) -> bool:
	var probe := e.duplicate()
	probe["tile"] = origin
	var claimed: Dictionary = {}
	for i in data.entities.size():
		if i == skip:
			continue
		for t in MapData.footprint_rect_of(data.entities[i]):
			claimed[t] = true
	for t in MapData.footprint_rect_of(probe):
		# THE WHOLE FOOTPRINT ON THE MAP, not just the origin -- `add_entity()`'s comment has
		# the argument: a 10x10 building dropped two tiles from the edge would otherwise be
		# placed half in the void by `MapGen.build_from()`.
		if not data.in_bounds(t) or claimed.has(t):
			return false
	return true


## Which player indices have their start marker standing on `e`'s footprint.
##
## ⚠️ **A START IS A CENTRE AND AN ENTITY'S `tile` IS AN ORIGIN, AND CONFUSING THE TWO IS A
## FIVE-TILE ERROR.** `MapData.starts` is documented as *"the CENTRE tile of that player's
## start"*; every entity record holds the minimum corner of its footprint. For a villager those
## coincide and for a 10x10 town centre they are five tiles apart — which is why this asks
## `footprint_rect_of()` whether the marker is INSIDE the building rather than comparing the two
## tiles. `preview_saved_map`'s second red run is this project's standing record of that
## distinction being expensive; `test_cursors` caught it here.
func _starts_inside(e: Dictionary) -> Array[int]:
	var out: Array[int] = []
	var tiles := MapData.footprint_rect_of(e)
	for i in data.starts.size():
		var s: Vector2i = data.starts[i]
		if s.x < 0:
			continue
		if tiles.has(s):
			out.append(i)
	return out


## Whether this entity is the thing a start marker sits inside.
##
## **AGAINST `StartLayout.TOWN_CENTRE` and not against "is it a building with a big
## footprint"**, because the identity is what matters: `StartLayout.place()` is what put the
## marker and the town centre on the same tile, so that constant is the one fact tying them
## together. A castle dragged onto a start is not the start's base.
static func _is_town_centre(e: Dictionary) -> bool:
	return StringName(e.get("def_id", &"")) == StartLayout.TOWN_CENTRE


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
	# ⚠️ **AN OPEN STROKE IS CLOSED BEFORE ANYTHING IS WRITTEN.** Save is reachable from the
	# keyboard and from a button, so it can arrive with the mouse still down mid-drag -- and
	# the tiles painted so far are about to be in the file. Leaving the step open would put
	# them on the stack AFTER the save point, so the first Ctrl+Z would take back changes that
	# are already saved while the tool reported no unsaved work.
	end_stroke()
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
	# ⛔ **WRITTEN EVEN WHEN EMPTY, AND THE SAVE IS WRONG WITHOUT THAT.** `_preserved_header()`
	# filters out what `MapData.to_dict()` derives, and it never derives `objectives` -- so the
	# OPENED file's conditions are sitting in `side` right now. Writing this key only when the
	# list had something in it would mean deleting the author's last condition never reached the
	# file: the stale row would be written straight back and would return on reopen, after a save
	# that reported success. See the `objectives` field, and `MapData.to_dict()`'s `areas`, which
	# is unconditional for the mirror image of this reason.
	# ⛔ **RE-RESOLVED FROM `target`, NOT FROM THE FIELD SET AT OPEN.** `save_as()` into `maps/`
	# moves the map somewhere with no scenario beside it, and its conditions genuinely become the
	# new map's own; keeping the opened path would write a copy's objectives into the ORIGINAL
	# scenario, which is a save that edits a file the author did not open.
	scenario_path = ScenarioFile.path_beside(target)
	if scenario_path.is_empty():
		side["objectives"] = objectives
	else:
		# ⚠️ **ERASED, NOT MERELY LEFT OUT.** `_preserved_header()` carries forward every key
		# `to_dict()` does not derive, and `objectives` is one of them — so a map whose sidecar
		# picked one up (a standalone map later given a scenario, or one saved by 16.6's first
		# cut before this correction) would keep writing a stale second copy beside the
		# authoritative one. One home at a time is the whole rule.
		side.erase("objectives")
	problems = MapFile.save(data, target, side)
	if problems.is_empty():
		# ⚠️ **THE SCENARIO IS WRITTEN AFTER THE MAP AND ONLY IF THE MAP WROTE.** A scenario whose
		# objectives were updated beside a `map.png` that failed to write is the two files
		# disagreeing about the same save — and of the two orders, this one leaves the pair
		# consistent on the failure that actually happens (a full disk, a read-only directory).
		#
		# ⚠️ **A FAILURE HERE IS A WARNING AND NOT A `problems` ENTRY**, which is deliberate and is
		# 16.4b's line again: the MAP was written, so the author has not lost their terrain, their
		# entities or their regions. Reporting this as a failed save would tell them the opposite
		# of what happened. What they need to know is that their CONDITIONS did not land, in the
		# amber "SAVED, BUT LOOK" state that exists for exactly this shape.
		#
		# ⛔ **HELD IN A LOCAL AND APPENDED BELOW, NOT PUT ON `warnings` HERE.**
		# `warnings = StartLayout.audit(data)` a few lines down **REPLACES** the array, so an
		# append made at this point is silently thrown away — a save that dropped the author's
		# conditions and then reported no warning at all. Found by reading the order rather than
		# by a test, because the only symptom is an absence.
		var lost_conditions := ""
		if not scenario_path.is_empty():
			var wrote: Array[String] = []
			if not ScenarioFile.write_objectives(scenario_path, objectives, wrote):
				lost_conditions = "the map saved but its conditions did not reach %s -- %s" \
						% [scenario_path.get_file(), " | ".join(PackedStringArray(wrote))]
		dir = target
		dirty = false
		# WHERE THE FILE NOW SITS ON THE STACK. The history is deliberately NOT cleared: an
		# author can still take back what they just saved, which is the point of undo surviving
		# a save at all -- they save, look at it, and change their mind. `UndoStack` explains
		# what happens to this mark when the branch holding it is discarded.
		history.mark_clean()
		# AUDITED AFTER A SUCCESSFUL WRITE, not before it. An author who has been told their
		# map is thin should still have the file: refusing to write is how you lose work over
		# an opinion, and 16.3's palette is where a deliberate hand-built economy stops
		# looking thin.
		warnings = StartLayout.audit(data)
		# ⛔ **FIRST, BECAUSE IT IS THE ONLY ONE THAT IS ABOUT THE SAVE ITSELF.** Everything else
		# in this list is an opinion about the map; this says a file the author asked to be
		# written was not. See where it is computed, and why it could not be appended there.
		if not lost_conditions.is_empty():
			warnings.append(lost_conditions)
		# THE CONDITIONS GO BETWEEN THE TWO, which is where they sit on the narrow-to-fatal run
		# this list is ordered by: an unwinnable scenario is worse than a thin start and better
		# than a map the lobby will not start at all. See `objective_problems()` for why these
		# are warnings.
		warnings.append_array(objective_problems())
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
## PNG and the map unloadable. Asking `to_dict()` what it produces meant that when 16.5 added
## `areas` to the wire form, this dropped them from the stale header with no edit here — ✅ which
## it did, on 2026-09-09, and see the `header` field's note for the one line in `MapData` that
## the promise turned out to rest on.
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
