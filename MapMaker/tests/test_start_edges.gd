## A start near the edge of a small map, and the audit that reports one (PLAN.md 16.2, 16.4b).
##
## ## THE MAP THAT MADE THIS FILE
##
## The owner authored the first real map in the tool on 2026-09-04: 48x48 — `MIN_SIZE`, so a
## legal size — with starts at **(6,6)** and **(35,35)**. It saved without a murmur and it was
## unplayable:
##
## | | player 1 | player 2 |
## |---|---|---|
## | entities | **9 of 24** | 21 of 24 |
## | scout | **none** | 1 |
## | stone | **none** | 1 of 2 |
## | gold | 1 of 2 | **none** |
##
## Neither player could have climbed the age ladder. **Placing a start near a corner of a small
## map is a reasonable thing to do**, so this is the tool's fault twice over: the placement was
## fragile, and it said nothing.
##
## Two faults, and every test here is about one of them:
##
##   1. **off-map ring tiles were skipped and never replaced** — both starts sit within 15
##      tiles of an edge, and the outer rings reach (-9,-9) and (50,50);
##   2. **the ring was sampled rather than walked** — `step = ring.size() / wanted` gave two
##      gold mines exactly *two* attempts, and both missed.
extends TestCase

## The owner's map, reproduced exactly. Every test in the first half runs on this.
const SIDE := 48
const NEAR_CORNER := Vector2i(6, 6)
const FAR_CORNER := Vector2i(35, 35)

## What `StartLayout.place()` owes one player: a town centre, five villagers, a scout, and the
## four resource kinds. 24 entities. Written out rather than summed from the constants so a
## silent change to either is a failure here.
const WANTED := {
	&"building.town_center": 1,
	&"unit.villager": 5,
	&"unit.scout_cavalry": 1,
	&"res.berry_bush": 5,
	&"res.tree": 8,
	&"res.gold_mine": 2,
	&"res.stone": 2,
}

var doc: MapDocument = null


func before_each() -> void:
	GameDataRegistry.load_from(GameRoot.resolve())
	doc = MapDocument.create(Vector2i(SIDE, SIDE), "Edge Case")


## Everything attributed to `player`, by def id -- owned outright, or gaia and nearest.
func _tally(player: int) -> Dictionary:
	var got := {}
	for e in doc.data.entities:
		var owner_id := int(e.get("player", 0))
		# `tile` is the in-memory key; `x`/`y` appear only in the saved dictionary.
		var t: Vector2i = e.get("tile", Vector2i.ZERO)
		var mine := owner_id == player
		if owner_id == 0:
			mine = StartLayout._nearest_start(doc.data, t) == player
		if mine:
			var id := StringName(e["def_id"])
			got[id] = int(got.get(id, 0)) + 1
	return got


func _assert_whole(player: int) -> void:
	var got := _tally(player)
	for def_id in WANTED:
		assert_eq(int(got.get(def_id, 0)), int(WANTED[def_id]),
				"P%d's %s" % [player, def_id])


# ── the placement (fault 1 and 2) ───────────────────────────────────────────

## ⚠️ **THE ONE THAT REPRODUCES THE OWNER'S MAP.** A start six tiles from two edges: the unit
## ring reaches (-1,-1) and the stone ring reaches (-9,-9), so more than half of every ring is
## off the map. It must still get its whole opening.
func test_a_start_in_a_corner_still_gets_its_whole_opening() -> void:
	assert_true(doc.place_start(1, NEAR_CORNER))
	_assert_whole(1)


## The other half of that map. Player 2 lost its gold to a ring reaching (49,49) on a 48-wide
## map -- the maximum edge rather than the minimum, which is a different arithmetic slip and
## deserves its own test.
func test_a_start_near_the_far_edges_still_gets_its_whole_opening() -> void:
	assert_true(doc.place_start(1, FAR_CORNER))
	_assert_whole(1)


## ⚠️ **AND BOTH TOGETHER, WHICH IS THE ACTUAL MAP AND THE HARDEST CASE.** The two starts are
## 29 tiles apart, so their radius-14 and radius-15 rings intersect: player 2's first gold
## candidate was a tile player 1's cluster already held. Placing one start well is not the same
## as placing two.
func test_the_owners_map_gives_both_players_a_full_start() -> void:
	assert_true(doc.place_start(1, NEAR_CORNER))
	assert_true(doc.place_start(2, FAR_CORNER))
	_assert_whole(1)
	_assert_whole(2)
	assert_eq(doc.data.entities.size(), 48,
			"two whole starts is 48 entities; the owner's map had 30")
	assert_eq(doc.seats(), 2)


## The audit must agree with the placement. A map the tool fills correctly and then warns about
## is as bad as the reverse -- an author who is told to look at a fine map stops looking.
func test_a_full_map_produces_no_warnings() -> void:
	doc.place_start(1, NEAR_CORNER)
	doc.place_start(2, FAR_CORNER)
	assert_eq(StartLayout.audit(doc.data), [] as Array[String])


## Placement stays deterministic, because two people authoring the same map must produce the
## same file (PLAN.md 11.3) -- `_spread` uses integer arithmetic for this reason.
func test_the_same_start_twice_places_the_same_things() -> void:
	doc.place_start(1, NEAR_CORNER)
	# Typed by hand: a Dictionary subscript is untyped, so `:=` cannot infer it.
	var first: Variant = doc.data.to_dict()["entities"]
	var other := MapDocument.create(Vector2i(SIDE, SIDE), "Edge Case")
	other.place_start(1, NEAR_CORNER)
	assert_eq(other.data.to_dict()["entities"], first)


## The spread survives. If everything simply piled into the first free arc the start would be
## whole and would play badly -- six villagers in a huddle and every tree on one side.
func test_the_opening_is_spread_around_the_start_not_clumped() -> void:
	doc.place_start(1, Vector2i(24, 24))          # middle of the map, nothing in the way
	var quadrants := {}
	for e in doc.data.entities:
		if StringName(e["def_id"]) != &"res.tree":
			continue
		var t: Vector2i = e.get("tile", Vector2i.ZERO)
		var dx := t.x - 24
		var dy := t.y - 24
		quadrants["%d%d" % [signi(dx), signi(dy)]] = true
	assert_true(quadrants.size() >= 4,
			"eight trees should reach at least four directions, got %s" % [quadrants.keys()])


# ── the audit (16.4b) ───────────────────────────────────────────────────────

## ⚠️ **A WARNING, NEVER A REFUSAL.** `_ECONOMY`'s header tells an author to delete the cluster
## and place their own, so a checker that blocked the save would fight the tool's own advice.
## The file must be on disk and the warning must be in hand.
func test_a_thin_map_is_saved_and_reported_rather_than_refused() -> void:
	doc.place_start(1, Vector2i(24, 24))
	# Strip the economy the way an author about to place their own would.
	var kept: Array[Dictionary] = []
	for e in doc.data.entities:
		if int(e.get("player", 0)) != 0:
			kept.append(e)
	doc.data.entities = kept

	var problems := doc.save(ProjectSettings.globalize_path("user://test_start_edges"))
	assert_eq(problems, [] as Array[String], "the map still saves")
	assert_false(doc.dir.is_empty(), "and it is on disk")
	assert_false(doc.warnings.is_empty(), "and the author is told it is thin")
	assert_true(doc.warnings[0].contains("P1"), doc.warnings[0])


## The wording is the deliverable here: a start that is MISSING a kind cannot reach an age,
## while a short one is merely poorer, and "no stone" says which.
func test_a_missing_kind_reads_differently_from_a_short_one() -> void:
	doc.place_start(1, Vector2i(24, 24))
	var kept: Array[Dictionary] = []
	var berries := 0
	for e in doc.data.entities:
		var id := StringName(e.get("def_id", &""))
		if id == &"res.stone":
			continue                          # take every stone: a missing kind
		if id == &"res.berry_bush":
			berries += 1
			if berries > 2:
				continue                      # leave 2 of 5: a short kind
		kept.append(e)
	doc.data.entities = kept

	var said := StartLayout.audit(doc.data)
	assert_eq(said.size(), 1, str(said))
	assert_true(said[0].contains("no "), "a missing kind is named as absent: " + said[0])
	assert_true(said[0].contains("2 of 5"), "a short kind carries its count: " + said[0])


## Every start is audited, not just the first -- the owner's map was short at BOTH ends and a
## checker that stopped after one would have reported half the problem.
func test_every_start_is_audited() -> void:
	doc.place_start(1, Vector2i(14, 14))
	doc.place_start(2, Vector2i(34, 34))
	doc.data.entities = [] as Array[Dictionary]
	var said := StartLayout.audit(doc.data)
	assert_eq(said.size(), 2, str(said))
	assert_true(said[0].contains("P1") and said[1].contains("P2"), str(said))


## An empty slot in `starts` is not a start. `MapDocument.remove_start` leaves `(-1, -1)`
## behind for any player below the highest, and auditing one would invent a warning about a
## player who is not on the map.
func test_a_cleared_start_slot_is_not_audited() -> void:
	doc.place_start(1, Vector2i(14, 14))
	doc.place_start(2, Vector2i(34, 34))
	doc.remove_start(1)
	assert_eq(doc.data.starts[0], Vector2i(-1, -1), "slot 1 is empty but still there")
	var said := StartLayout.audit(doc.data)
	for s in said:
		assert_false(s.contains("P1"), "nobody is at P1's start: " + s)


## The audit reads the map, not the session. `MapFile` drops `ORIGIN_KEY` on save, so an audit
## keyed off the tag would report a reloaded map as empty -- which is exactly the map 16.4a
## will hand it.
func test_the_audit_works_without_the_session_tag() -> void:
	doc.place_start(1, Vector2i(24, 24))
	for e in doc.data.entities:
		e.erase(StartLayout.ORIGIN_KEY)
	assert_eq(StartLayout.audit(doc.data), [] as Array[String],
			"a whole start is whole with or without the tag")
