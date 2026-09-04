## PLAN.md 16.4b, second half: **the tool runs the game's own gate on the map it just saved.**
##
## ## WHY THIS IS A SEPARATE FILE FROM `test_start_edges`
##
## Because the two checks answer questions neither can ask on the other's behalf, and 16.4b
## needs both:
##
##   - `StartLayout.audit` knows whether a start got its OPENING — five villagers, a scout,
##     four resource kinds. That is the half that would have caught the 48x48 map the owner
##     authored on 2026-09-04, and it is tested next door.
##   - `MapValidator` knows whether the MAP works: can the starts reach each other, is
##     anything standing on anything else, is a start's gold reachable *by walking* rather
##     than merely nearby, and on a sea map can everybody build a dock. **None of that is
##     derivable from an entity list, and all of it decides whether the lobby will start.**
##
## ## THE DECISION THIS FILE STANDS ON
##
## `MapValidator` is now the eighth file in `format/`, hash-checked like the rest.
## `MapDocument.seats()`'s header records that pulling this arithmetic in was **rejected** —
## *"it is not part of the format, it is an opinion ABOUT a map, and putting it there would
## mean a hash check failing whenever the lobby's rule changed"* — and the owner overruled it
## (*"re-copying is fine"*, 2026-09-04). The trade, stated so nobody re-litigates it from
## memory: **a validator that disagrees with the game's is worse than one that occasionally
## needs re-copying.** A second implementation in here would pass maps the skirmish screen
## then refuses, which is 16.4b's own failure mode with an extra step. `test_format_guard`
## carries the drift half; this file carries the "it is actually wired in" half.
##
## ⚠️ **EVERY PROBLEM HERE ARRIVES AS A WARNING AND THE MAP IS STILL WRITTEN.** These are the
## severest warnings the tool has, and they are still warnings: refusing to write is how you
## lose the work of an author who is halfway through joining two halves of an island. Saving
## under `user://` only, like `test_map_document`.
extends TestCase

const SCRATCH := "user://test_map_validation"

## PRELOADED RATHER THAN NAMED. `editor.gd` carries no `class_name` -- it is the script on
## `Editor.tscn`'s root and nothing else refers to it by type -- and giving it one just to
## reach a static helper from a test would be the test changing the code's shape.
const EDITOR := preload("res://src/editor.gd")

## Big enough for two starts and their clearings, and the size `test_map_document` uses.
const SIDE := 96

var _n := 0
var doc: MapDocument = null


func before_each() -> void:
	_n += 1
	GameDataRegistry.load_from(GameRoot.resolve())
	doc = MapDocument.create(Vector2i(SIDE, SIDE), "Validated Map")


func _dir() -> String:
	return ProjectSettings.globalize_path("%s/case_%d" % [SCRATCH, _n])


## Two whole starts, far enough apart that neither cluster touches the other.
func _two_starts() -> void:
	doc.place_start(1, Vector2i(24, 24))
	doc.place_start(2, Vector2i(72, 72))


func _save() -> Array[String]:
	var problems := doc.save(_dir())
	assert_eq(problems, [] as Array[String], "the file is written whatever the map is like")
	return doc.warnings


## Whichever warning mentions `needle`, or "" -- so a test names the property it wants rather
## than the position of a sentence in a list.
func _warning_about(needle: String) -> String:
	for w in doc.warnings:
		if w.contains(needle):
			return w
	return ""


# ── the gate is really wired in ─────────────────────────────────────────────

func test_the_tool_can_run_the_games_validator_at_all() -> void:
	# ⚠️ **THE ONE THAT WOULD HAVE FAILED AT COMPILE TIME AND IS WORTH AN ASSERTION ANYWAY.**
	# The copy calls `GameDataRegistry.unit(id)` in two places, and this tool's registry keeps
	# units as raw dictionaries -- there was no `unit()` at all until 16.4b. It is `Variant`
	# rather than `UnitDef` on purpose (see `game_content.gd`): both call sites only ask
	# whether it is null.
	assert_not_null(GameDataRegistry.unit(&"unit.villager"), "a real unit resolves")
	assert_null(GameDataRegistry.unit(&"unit.nothing_like_this"), "and an invented one does not")
	assert_null(GameDataRegistry.unit(&"building.town_center"),
			"a building is not a unit, which is the distinction both call sites need")


func test_a_whole_two_player_map_warns_about_nothing() -> void:
	# THE ASSERTION THE REST DEPEND ON. A checker that flags a good map is worse than none:
	# an author told to look at a fine map stops looking, and then the real warning arrives
	# on a line they have learned to ignore.
	_two_starts()
	assert_eq(_save(), [] as Array[String], "a good map is quiet")


func test_a_map_with_one_start_says_a_match_needs_two() -> void:
	# The first thing an author does is place one start, and this is what the tool says while
	# they are still working. Useful rather than pedantic: `MapDocument.seats()` reports 1 and
	# 16.0's picker will not offer the map at all.
	doc.place_start(1, Vector2i(24, 24))
	_save()
	assert_true(_warning_about("at least 2 starts") != "",
			"got %s" % [doc.warnings])


# ── what only the game's validator knows ────────────────────────────────────

func test_two_starts_walled_off_from_each_other_are_reported() -> void:
	# ⚠️ **THE HALF `StartLayout.audit` CANNOT SEE, AND THE WHOLE REASON THE COPY IS WORTH
	# EIGHT FILES.** Both starts here have every unit and every resource kind the audit asks
	# for -- it reports nothing at all -- and the map is unplayable: a channel of deep water
	# across the board means neither player can ever reach the other, so nobody can win.
	#
	# 2.4b's header says why this matters more than it sounds: *"a player walled in behind
	# water looks exactly like a normal map until you have spent two minutes discovering
	# it."* An authored map can do it in one brush stroke.
	_two_starts()
	assert_eq(StartLayout.audit(doc.data), [] as Array[String],
			"the audit is happy, which is the point of this test")
	for x in range(SIDE):
		doc.paint(Vector2i(x, 48), SimMap.Terrain.WATER_DEEP)

	_save()
	assert_true(_warning_about("cannot reach") != "",
			"a channel across the map must be reported: %s" % [doc.warnings])


func test_a_start_whose_resources_are_across_the_water_is_reported() -> void:
	# NOT "is there gold on the map" but "can THIS player walk to gold", which is the
	# distinction `MapValidator` measures as a flood fill and nothing in this tool could.
	# `StartLayout` places a start's ore on a ring by distance, so a ring the author has
	# since painted a moat through still looks correct by every measure the tool owns.
	_two_starts()
	# A FILLED ANNULUS AND NOT A CIRCLE OF SAMPLED ANGLES, which is what this test tried
	# first and it reported nothing: `MapValidator._flood` is 8-directional to match the
	# pathfinder, so a one-tile wall with a diagonal gap in it is a wall a villager walks
	# through. Radius 11 to 13 -- outside the berry ring at 10 and inside the ore, which
	# `StartLayout` puts at 15.
	for y in range(24 - 14, 24 + 15):
		for x in range(24 - 14, 24 + 15):
			var d := Vector2(Vector2i(x, y) - Vector2i(24, 24)).length()
			if d >= 11.0 and d <= 13.0:
				doc.paint(Vector2i(x, y), SimMap.Terrain.WATER_DEEP)

	_save()
	assert_true(_warning_about("reachable") != "",
			"a moat between a base and its own ore must be reported: %s" % [doc.warnings])


func test_the_report_names_the_player_so_an_author_knows_where_to_look() -> void:
	# A 96x96 map is 9,216 tiles. "This map is broken" is not actionable on one; the game's
	# own sentences say which player, which is why they are surfaced verbatim rather than
	# summarised into a count.
	_two_starts()
	for x in range(SIDE):
		doc.paint(Vector2i(x, 48), SimMap.Terrain.WATER_DEEP)
	_save()
	var said := _warning_about("cannot reach")
	assert_true(said.contains("player 1") or said.contains("player 2"), said)


# ── warnings, never refusals ────────────────────────────────────────────────

func test_an_unplayable_map_is_still_written_to_disk() -> void:
	# ⚠️ **THE RULE FOR THE WHOLE FEATURE.** An author joining two halves of an island has an
	# unplayable map on the way to a playable one, and a tool that refused to save it would
	# lose the work -- so this warns and writes. `MapDocument.warnings`' header has the
	# argument; refusing is decision 3's job and nothing else's.
	_two_starts()
	for x in range(SIDE):
		doc.paint(Vector2i(x, 48), SimMap.Terrain.WATER_DEEP)

	var problems := doc.save(_dir())
	assert_eq(problems, [] as Array[String], "nothing stopped the write")
	assert_false(doc.dir.is_empty(), "and the map is on disk")
	assert_false(doc.dirty, "and counts as saved, so the author does not lose it")
	assert_false(doc.warnings.is_empty(), "but they were told")


func test_the_audit_comes_first_and_the_gate_second() -> void:
	# Narrow to fatal on the notice line, which is `MapDocument.save()`'s stated order: "your
	# start is short two berries" ahead of "nobody can reach anybody". Both sources have to
	# be present at once, which is what this really pins -- an earlier draft replaced the
	# audit with the validator instead of appending to it, and the 48x48 map that started
	# 16.4b would have gone back to saving silently.
	doc.place_start(1, Vector2i(24, 24))
	var kept: Array[Dictionary] = []
	for e in doc.data.entities:
		if int(e.get("player", 0)) != 0:
			kept.append(e)          # strip the economy, the way 16.3's author would
	doc.data.entities = kept

	_save()
	assert_true(doc.warnings.size() >= 2, "both sources spoke: %s" % [doc.warnings])
	assert_true(doc.warnings[0].contains("P1"),
			"the audit's sentence is first: %s" % doc.warnings[0])
	assert_true(_warning_about("at least 2 starts") != "",
			"and the game's gate is in there too: %s" % [doc.warnings])


func test_the_notice_line_shows_the_worst_of_it_and_says_how_much_more() -> void:
	# ⚠️ **A CLIPPED WARNING IS A WARNING NOBODY READ.** `Editor._notice_label` is one
	# unwrapped Label; the audit gives one sentence per start and `MapValidator` one per
	# problem per player, so a broken eight-player map can hand it a dozen. Past ~200
	# characters the text is off screen, and the author does not get to choose which
	# sentence survives.
	#
	# The COUNT is the load-bearing half of the tail: "and 9 more" is what tells somebody
	# this is a broken map and not a rough edge.
	var many: Array[String] = []
	for i in range(5):
		many.append("problem %d" % i)
	var line: String = EDITOR._summarised(many)
	assert_true(line.begins_with("problem 0; problem 1"), line)
	assert_true(line.contains("and 3 more"), line)
	assert_true(line.length() < 200, "and it fits on the line: %d chars" % line.length())

	assert_eq(EDITOR._summarised(["only this"] as Array[String]), "only this",
			"one warning gets no tail")
	assert_eq(EDITOR._summarised([] as Array[String]), "",
			"and none is empty rather than a stray count")


func test_a_second_save_does_not_keep_the_first_ones_warnings() -> void:
	# `save()` clears them at entry, for the reason the notice line is rewritten rather than
	# appended to: a stale warning outliving the fault it was about is worse than none, since
	# the author fixes the map and is told it is still broken.
	_two_starts()
	for x in range(SIDE):
		doc.paint(Vector2i(x, 48), SimMap.Terrain.WATER_DEEP)
	_save()
	assert_false(doc.warnings.is_empty(), "broken to begin with")

	for x in range(SIDE):
		doc.paint(Vector2i(x, 48), SimMap.Terrain.GRASS)
	assert_eq(_save(), [] as Array[String], "and quiet once it is mended")
