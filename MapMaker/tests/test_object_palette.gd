## PLAN.md 16.3: the object palette, the icons it crops, and the placement its selection feeds.
##
## ## WHAT IS WORTH ASSERTING HERE AND WHAT IS NOT
##
## A palette is mostly a picture, and `dev/preview_editor.tscn` is what looks at it. **What a
## headless test can see is every place this row could be quietly wrong:**
##
##   - **the lists.** Sorted as text and not by `StringName` identity (§6: identity order is
##     not stable between runs, so a palette that reshuffles itself between launches looks
##     broken); the right roster per category; and **the Areas tab, whose rows come from the
##     DOCUMENT rather than from the roster** — the only tab that does, which makes it the only
##     one whose emptiness is a healthy state rather than an unreadable game project.
##   - **`size_class`.** 16.3's amendment: *"a placement that leaves it 0 silently authors the
##     small variant."* Nothing on screen distinguishes a small gold mine from a large one at
##     0.22x zoom.
##   - **gaia.** Every resource node in the game is `player: 0`, so an author who has to change
##     the owner per tree will author a forest belonging to player 1 — and the map will look
##     completely normal.
##   - **the crop reaching outside `res://` at all.** `load()` cannot open the game's atlases
##     from this project; if `_absolute()` were wrong every icon would be a lettered plate and
##     the palette would look *deliberate*.
##   - **placement refusals.** An overlap and a footprint running off the edge are the two
##     things a click cannot show.
##
## Fixtures never write into repo-root `maps/` or `scenarios/` — `test_map_document`'s rule.
extends TestCase

var palette: ObjectPalette = null
var icons: IconAtlas = null
var root: GameRoot = null


func before_each() -> void:
	root = GameRoot.resolve()
	GameDataRegistry.load_from(root)
	icons = IconAtlas.new()
	icons.load_from(root)
	palette = ObjectPalette.new()
	palette.setup(icons)


func after_each() -> void:
	if palette != null:
		palette.free()
		palette = null


## True when this machine has the game project. **Several tests below are about reading the
## GAME's files**, and a checkout without one is a legitimate state (`test_startup` is where
## that gets reported), so they skip rather than fail — the pattern `preview_saved_map`'s
## committed-fixture tests already use on the game side.
func _has_game() -> bool:
	return root != null and not root.path.is_empty()


## A resource an author is actually allowed to place.
##
## ⚠️ **NOT `resource_ids()[0]`, WHICH IS NOW A CARCASS.** Alphabetically first is
## `res.bear_carcass`, and the six carcasses are flagged unplaceable — so a fixture reaching for
## index 0 would exercise a placement the palette cannot make, which is §5's *"beware fixtures
## that agree with the bug"* pointed at a rule instead of at a defect.
func _a_placeable_resource() -> StringName:
	for id in GameDataRegistry.resource_ids():
		if GameDataRegistry.placeable(id):
			return id
	return &""


# ── the categories ──────────────────────────────────────────────────────────

## ⚠️ **THIS REPLACES `test_there_is_no_area_category_until_the_format_has_a_field_for_one`, AND
## THE OLD TEST DID ITS JOB.** It asserted `CATEGORIES` was four long AND that
## `MapData.to_dict()` had no `areas` key, with the message *"MapData has an areas field now --
## 16.5 has landed and the tab can be added"* — so deleting `Subject.AREA` from `_NOT_YET` and
## adding the field turned the suite red on the run it happened in, naming the reason. That is
## the shape worth copying: **a deferral is a test, not a comment.**
##
## What it becomes is the same claim inverted — the tab exists **and** the format can carry what
## it draws — because the failure it guarded against has not gone away, it has only changed
## direction: a tab whose output `MapFile` drops is still *work lost behind a successful save*,
## and that is now a thing a regression could reintroduce rather than a thing waiting to be
## built.
func test_the_areas_tab_exists_and_the_format_can_carry_what_it_draws() -> void:
	var labels: Array[String] = []
	for entry in ObjectPalette.CATEGORIES:
		labels.append(str(entry["label"]))
	assert_eq(labels.size(), 5, "got %s" % [labels])
	assert_true("Areas" in labels, "got %s" % [labels])
	# THE FORMAT HALF, asserted rather than described -- a tab with no field behind it is the
	# thing the old test existed to prevent, and this is what would notice it coming back.
	assert_true(MapData.create(Vector2i(48, 48)).to_dict().has("areas"),
			"the Areas tab has nothing to write into")


## ⚠️ **AND THE KEY IS WRITTEN EVEN WHEN THERE ARE NO AREAS, WHICH IS NOT AN ACCIDENT.**
## `MapDocument._preserved_header()` filters an opened sidecar by asking `to_dict()` which keys
## it produces — so a key that vanished when the author deleted their last region would stop
## being filtered, the stale header's `areas` would be carried forward, and **the deletion would
## not reach the file**: the region would come back on reopen, after a save that reported
## success. `MapData`'s own field note carries the argument; this is what checks it.
func test_the_areas_key_is_written_even_for_a_map_with_none() -> void:
	var empty := MapData.create(Vector2i(48, 48))
	assert_true(empty.to_dict().has("areas"))
	assert_eq((empty.to_dict()["areas"] as Array).size(), 0)
	# AND THE FILTER IT EXISTS FOR REALLY DOES DROP IT. A header carrying somebody else's areas
	# must not survive a re-save of a map that has none.
	var doc := MapDocument.create(Vector2i(48, 48), "no regions")
	doc.header = {"areas": [{"name": "stale", "x": 0, "y": 0, "w": 4, "h": 4}], "seed": 7}
	var kept := doc._preserved_header()
	assert_false(kept.has("areas"), "a stale header's areas must not outlive the map's: %s" % [kept])
	assert_eq(int(kept.get("seed", 0)), 7, "and real provenance still survives")


## Resources are the category the original spec left out, and `MapValidator` fails a map with
## none within reach of a start. Without this tab no map authored in this tool is playable.
func test_resources_are_a_category() -> void:
	var ids: Array[int] = []
	for entry in ObjectPalette.CATEGORIES:
		ids.append(int(entry["id"]))
	assert_true(ids.has(int(ObjectPalette.Category.RESOURCE)))


func test_each_category_lists_its_own_roster() -> void:
	if not _has_game():
		return
	palette.set_category(ObjectPalette.Category.BUILDING)
	# ⚠️ **THE BUILDING TAB IS NOT ONE ROW PER DEF ANY MORE, AND THE ARITHMETIC IS WRITTEN OUT
	# RATHER THAN COUNTED.** Every def gets a row, **a directional def gets two** (16.4c: a wall
	# is offered per axis, because the map records one), and the player start adds one that is
	# not a def at all. Derived from the roster so it survives a building being added; the point
	# of the test is that nothing ELSE creeps in.
	var directional := 0
	for id in GameDataRegistry.building_ids():
		if GameDataRegistry.axis_variants(id):
			directional += 1
	assert_true(directional > 0, "no directional buildings -- has the flag gone from the data?")
	assert_eq(palette.listed_ids().size(),
			GameDataRegistry.building_ids().size() + directional + 1,
			"one row per building, two per directional one, plus the player start")
	palette.set_category(ObjectPalette.Category.UNIT)
	assert_eq(palette.listed_ids().size(), GameDataRegistry.unit_ids().size())
	palette.set_category(ObjectPalette.Category.TERRAIN)
	assert_eq(palette.listed_ids().size(), SimMap.Terrain.size())


## ── the player start as a palette entry (owner's ruling, 2026-09-08) ────────

## ⚠️ **IT IS IN THE BUILDING TAB AND IT IS NOT A DEF, and both halves matter.**
##
## `START_ID` is in a `start.` namespace no roster file uses, so every registry lookup answers
## "unknown" for it — which is what stops `Editor.apply_tool` from ever handing it to
## `add_entity()` and authoring an entity the game would spawn nothing for. A start is a
## `MapData.starts` slot, and placing one runs `StartLayout`.
func test_the_start_is_offered_in_the_building_tab_and_is_not_a_def() -> void:
	if not _has_game():
		return
	palette.set_category(ObjectPalette.Category.BUILDING)
	assert_true(ObjectPalette.START_ID in palette.listed_ids(),
			"the start has to be pickable or the toolbar's button was removed for nothing")
	# NOT A DEF, asserted through all three registry doors rather than described.
	assert_eq(GameDataRegistry.building(ObjectPalette.START_ID), null)
	assert_eq(GameDataRegistry.resource_def(ObjectPalette.START_ID), null)
	assert_true(GameDataRegistry.unit_raw(ObjectPalette.START_ID).is_empty())


## It goes LAST, where the owner's own sketch put it.
##
## The list is sorted as text and `START_ID` is not a def, so sorting it in among the buildings
## would put a tool between two of them and make the sort a lie about what the list is.
func test_the_start_is_the_last_row_of_the_building_tab() -> void:
	if not _has_game():
		return
	palette.set_category(ObjectPalette.Category.BUILDING)
	var ids := palette.listed_ids()
	assert_eq(ids[ids.size() - 1], ObjectPalette.START_ID)


## And it reaches `selection()`, which is what the PLACE tool reads.
##
## With the palette's own Owner box supplying the player — the deduplication the owner asked
## for, and the reason the toolbar's P1..P8 dropdown could go.
func test_picking_the_start_puts_it_in_the_selection_with_the_palettes_owner() -> void:
	if not _has_game():
		return
	palette.set_category(ObjectPalette.Category.BUILDING)
	palette.set_player(3)
	palette.pick(ObjectPalette.START_ID)
	var pick := palette.selection()
	assert_eq(StringName(pick["def_id"]), ObjectPalette.START_ID)
	assert_eq(int(pick["player"]), 3, "the palette's Owner box is now the only place whose")


## It is labelled in words, not by its id.
##
## `GameDataRegistry.display_name()` would prettify `start.player` into "Player" — it strips the
## namespace as a prefix — which on the one tile an author hunts for first is worse than useless.
func test_the_start_is_labelled_player_start() -> void:
	if not _has_game():
		return
	palette.set_category(ObjectPalette.Category.BUILDING)
	assert_eq(palette._label_for(ObjectPalette.START_ID), ObjectPalette.START_LABEL)
	assert_true(ObjectPalette.START_LABEL.to_lower().contains("start"),
			"whatever it is called, an author has to be able to search for 'start'")
	# AND IT IS FINDABLE BY THAT WORD, which is `_matches`' job and the thing a label change
	# could silently break.
	palette.set_search("start")
	assert_true(ObjectPalette.START_ID in palette.listed_ids(),
			"searching 'start' has to find it")


# ── what an author may place ────────────────────────────────────────────────

## ⚠️ **A CARCASS IS WHAT HUNTING LEAVES, NOT A THING AN AUTHOR PLACES** (owner, 2026-09-08:
## *"no placement of carcasses is acceptable"*). `DeathSystem` spawns them and they decay, so
## six of the Resource tab's eleven rows were things nobody would ever put on a map.
##
## **Driven off the `placeable` flag in `resources.json`, never off the id spelling.** Matching
## `_carcass` inside the tool fails in both directions as the roster grows — a future
## `res.horse_carcass` filtered by luck, a `res.whale_meat` not filtered at all — and neither
## failure announces itself. So this test asserts the MECHANISM: everything the tab offers is
## flagged placeable, and everything the roster hides is flagged not.
func test_the_resource_tab_offers_only_what_the_roster_says_is_placeable() -> void:
	if not _has_game():
		return
	palette.set_category(ObjectPalette.Category.RESOURCE)
	var offered := palette.listed_ids()
	assert_true(offered.size() < GameDataRegistry.resource_ids().size(),
			"nothing is being filtered -- is the flag in resources.json?")
	for id in offered:
		assert_true(GameDataRegistry.placeable(id), "'%s' should not be offered" % id)
	for id in GameDataRegistry.resource_ids():
		if not GameDataRegistry.placeable(id):
			assert_false(offered.has(id), "'%s' is flagged unplaceable and is offered" % id)


## And the six are the carcasses, asserted by their flag rather than by counting to six: the
## number is data and would change the day a seventh animal is baked.
func test_every_carcass_in_the_roster_is_flagged_unplaceable() -> void:
	if not _has_game():
		return
	var carcasses := 0
	for id in GameDataRegistry.resource_ids():
		if not String(id).ends_with("_carcass"):
			continue
		carcasses += 1
		assert_false(GameDataRegistry.placeable(id), "'%s' is still placeable" % id)
	assert_true(carcasses > 0, "no carcasses in the roster -- the fixture proved nothing")


## ⚠️ **ABSENT MEANS PLACEABLE**, so nothing had to be edited for the other ten files. A flag
## that had to be spelled out everywhere is a flag somebody forgets on the next entry, and the
## failure would be a new building missing from the palette.
func test_absent_means_placeable() -> void:
	if not _has_game():
		return
	for id in GameDataRegistry.building_ids():
		assert_true(GameDataRegistry.placeable(id), "'%s' vanished from the palette" % id)
	assert_true(GameDataRegistry.placeable(&"nothing.at.all"),
			"an unknown id must not be hidden -- a typo would look like the flag working")


## ⚠️ **`resource_ids()` IS NOT FILTERED AND MUST NOT BE.** *What the roster holds* and *what an
## author may place* are two facts: `Boot`'s report says "resources 11" because there are
## eleven, and a report reading 5 would make a reader think six failed to load. Same split as
## the server browser's JOIN button, where one variable answering two questions shipped a
## control enabled with nothing to join.
##
## Asserted as a PROPERTY and not against the number eleven: §6's rule about a figure written
## into an assertion is that it fails the day the owner asks for a change, and a resource added
## to the roster is exactly that day.
func test_the_roster_count_still_reports_every_resource() -> void:
	if not _has_game():
		return
	var hidden := 0
	for id in GameDataRegistry.resource_ids():
		if not GameDataRegistry.placeable(id):
			hidden += 1
	assert_true(hidden > 0,
			"resource_ids() has been filtered -- Boot's report would under-count the roster")


## ⚠️ **SORTED AS TEXT.** `Array[StringName].sort()` orders by identity and not stably between
## runs (§6, and 16.3's row carries the warning). Asserted on the LIST the palette shows rather
## than on the registry, because that is the thing an author reads.
func test_the_list_is_in_text_order() -> void:
	if not _has_game():
		return
	palette.set_category(ObjectPalette.Category.BUILDING)
	var ids := palette.listed_ids()
	for i in range(1, ids.size()):
		assert_true(String(ids[i - 1]) < String(ids[i]),
				"'%s' came before '%s'" % [ids[i - 1], ids[i]])


## A category change drops the selection, or `selection()` would keep naming a building while
## the Units tab was on screen — and the editor's status line would say so.
func test_changing_category_clears_the_selection() -> void:
	if not _has_game():
		return
	palette.set_category(ObjectPalette.Category.BUILDING)
	palette.pick(GameDataRegistry.building_ids()[0])
	assert_false(palette.selection().is_empty())
	palette.set_category(ObjectPalette.Category.UNIT)
	assert_true(palette.selection().is_empty(), "got %s" % [palette.selection()])


# ── the search ──────────────────────────────────────────────────────────────

## ⚠️ **IT MATCHES THE DISPLAY NAME *AND* THE ID.** An author knows a thing by two names and
## neither is reliably the one they type: "Archery Range" is what the palette prints and
## `building.archery_range` is what every note in this repo calls it.
func test_the_search_matches_the_label_and_the_id() -> void:
	if not _has_game():
		return
	palette.set_category(ObjectPalette.Category.BUILDING)
	var want := GameDataRegistry.building_ids()[0]
	var label := GameDataRegistry.display_name(want)

	palette.set_search(String(want))
	assert_true(palette.listed_ids().has(want), "the id did not match itself")

	palette.set_search(label.to_lower())
	assert_true(palette.listed_ids().has(want), "the display name '%s' did not match" % label)


func test_a_search_that_matches_nothing_lists_nothing_rather_than_everything() -> void:
	if not _has_game():
		return
	palette.set_category(ObjectPalette.Category.BUILDING)
	palette.set_search("zzzzz no such building")
	assert_true(palette.listed_ids().is_empty(), "got %s" % [palette.listed_ids()])


# ── the owner, and gaia ─────────────────────────────────────────────────────

## ⚠️ **EVERY RESOURCE NODE IN THE GAME IS GAIA'S**, so this is the most-used owner and not a
## special case. An author who has to set it per tree will forget, and a forest owned by
## player 1 looks exactly like a forest.
func test_the_resource_category_defaults_the_owner_to_gaia() -> void:
	if not _has_game():
		return
	palette.set_category(ObjectPalette.Category.BUILDING)
	palette.set_player(3)
	palette.set_category(ObjectPalette.Category.RESOURCE)
	palette.pick(_a_placeable_resource())
	assert_eq(int(palette.selection()["player"]), ObjectPalette.GAIA)


## And leaving it takes the owner off gaia, because a gaia BUILDING is a thing almost nobody
## wants — the dragon's nest is the one and it is placed by the generator.
func test_leaving_resources_takes_the_owner_off_gaia() -> void:
	if not _has_game():
		return
	palette.set_category(ObjectPalette.Category.RESOURCE)
	palette.set_category(ObjectPalette.Category.BUILDING)
	palette.pick(GameDataRegistry.building_ids()[0])
	assert_eq(int(palette.selection()["player"]), 1)


## ⚠️ **THE PANEL AND THE FIELD ARE ONE FACT, AND THEY CAME APART ON THE FIRST RENDER.** An
## `OptionButton` nobody has selected displays its **item 0**, and item 0 here is Gaia (it is
## first because every resource node in the game is gaia's) — so the palette showed *Gaia*
## while `selection()` returned *player 1*, and an author would have placed a house for a
## player they had not chosen. **Only the screenshot could see it**, which is why the reading is
## now a method and this is a test.
func test_the_owner_picker_shows_what_the_selection_will_actually_use() -> void:
	if not _has_game():
		return
	for c in [ObjectPalette.Category.BUILDING, ObjectPalette.Category.UNIT,
			ObjectPalette.Category.RESOURCE]:
		palette.set_category(c)
		var ids := palette.listed_ids()
		if ids.is_empty():
			continue
		palette.pick(ids[0])
		assert_eq(palette.shown_player(), int(palette.selection()["player"]),
				"the picker and the selection disagree in category %d" % int(c))


## ⚠️ **THE TINT PICKER WAS BLANK *AND* INERT, AND THE BLANKNESS HID THE INERTNESS.** Two
## faults reading as one: `OptionButton.add_item(text, -1)` means "assign the index as the id",
## so the natural id for "no colour" was never stored, `select()` deselected the control and it
## drew empty — while `item_selected` had not been connected to anything at all. That second
## half is §6's volume sliders: a control that answers nothing, shipped with every test green.
func test_the_tint_picker_is_populated_and_actually_changes_the_tint() -> void:
	if not _has_game():
		return
	assert_eq(palette.shown_tint(), -1, "it must start on 'none' and be SELECTED, not blank")
	assert_eq(palette.tint(), -1)

	var list := icons.colours()
	assert_eq(list.size(), 8, "colours.json declares eight; got %d" % list.size())

	palette.set_tint(3)
	assert_eq(palette.tint(), 3)
	assert_eq(palette.shown_tint(), 3, "the picker and the field disagree")


# ── size class ──────────────────────────────────────────────────────────────

## ⚠️ **16.3's AMENDMENT, AS A TEST**: *"a placement that leaves it 0 silently authors the
## small variant."* A small gold mine and a large one are the same def at different sizes.
func test_the_size_class_rides_the_selection_for_a_resource() -> void:
	if not _has_game():
		return
	palette.set_category(ObjectPalette.Category.RESOURCE)
	palette.pick(_a_placeable_resource())
	palette.set_size_class(2)
	assert_eq(int(palette.selection()["size_class"]), 2)


## And is zero for everything else, always. `size_class` means nothing to a building or a unit,
## and a stale value from the Resource tab riding a house's placement would reach
## `MapData.add_entity` as a fourth argument nobody set.
func test_the_size_class_is_zero_for_anything_that_is_not_a_resource() -> void:
	if not _has_game():
		return
	palette.set_category(ObjectPalette.Category.RESOURCE)
	palette.set_size_class(2)
	palette.set_category(ObjectPalette.Category.BUILDING)
	palette.pick(GameDataRegistry.building_ids()[0])
	assert_eq(int(palette.selection()["size_class"]), 0)


## ⚠️ **THE PICKER HAS AS MANY ROWS AS THE ROSTER HAS CLASSES, AND NOTHING ELSE CHECKS THAT.**
## `SIZE_LABELS` is a written-out list of three because `resources.json` declares three and
## the game names them nowhere. If that changes, the picker offers the wrong number of options
## and the failure is silent — an author picks "Large" and gets whatever index 2 means now.
func test_the_size_picker_offers_one_row_per_declared_size_class() -> void:
	if not _has_game():
		return
	var rd: ResourceDef = GameDataRegistry.resource_def(_a_placeable_resource())
	assert_not_null(rd)
	assert_eq(ObjectPalette.SIZE_LABELS.size(), rd.size_class_count(),
			"the labels and the roster disagree about how many size classes there are")


## ⚠️ **NOT ONE ENTRY IN `resources.json` HAS A `name` FIELD** (measured 2026-09-08), so the
## Resource tab was the only category in the tool labelled in code rather than in English —
## `res.bear_carcass` sitting beside a properly named Archery Range. `prettify()` formats the
## id; it does not invent a name, and a real `name` added to the data wins over it.
##
## **Found in a screenshot. No test could have had an opinion about it** — which is why the
## assertion here is about the FORMATTER and about the roster still lacking the field, not
## about any particular label.
func test_a_resource_with_no_name_in_the_roster_is_still_labelled_in_english() -> void:
	if not _has_game():
		return
	for id in GameDataRegistry.resource_ids():
		var label := GameDataRegistry.display_name(id)
		assert_false(label.begins_with("res."),
				"'%s' is labelled with its id" % label)
	# THE FORMATTER ITSELF, on the shapes that actually occur.
	assert_eq(GameDataRegistry.prettify(&"res.berry_bush"), "Berry Bush")
	assert_eq(GameDataRegistry.prettify(&"res.stone"), "Stone")
	assert_eq(GameDataRegistry.prettify(&"nodots"), "Nodots")


## A real `name` in the roster must beat the formatter, or adding one to the data would have no
## effect and somebody would come back and "fix" it in the tool instead.
##
## ⚠️ **ASSERTED AS A PROPERTY OVER THE WHOLE ROSTER, NOT ON A CHOSEN ID.** The first version
## picked `building.archery_range` and asserted the declared name DIFFERED from the formatted
## one — and it does not: `prettify("building.archery_range")` is *"Archery Range"*, exactly.
## A fixture whose two sides happen to agree proves nothing and fails while the code is right.
## `BuildingDef.name` is the declaration, so comparing against it needs no luck.
func test_a_declared_name_wins_over_the_formatter() -> void:
	if not _has_game():
		return
	var checked := 0
	for id in GameDataRegistry.building_ids():
		var bd: BuildingDef = GameDataRegistry.building(id)
		if bd == null or bd.name.is_empty():
			continue
		checked += 1
		assert_eq(GameDataRegistry.display_name(id), bd.name,
				"'%s' is not labelled with its declared name" % id)
	assert_true(checked > 0, "no building declares a name -- the fixture proved nothing")


# ── terrain ─────────────────────────────────────────────────────────────────

## Terrain places no entity, so `selection()` is empty and the editor arms a brush instead.
func test_the_terrain_category_selects_no_entity() -> void:
	palette.set_category(ObjectPalette.Category.TERRAIN)
	assert_true(palette.selection().is_empty())


## The tab arms a brush on its own rather than waiting for a second click: there is no "no
## terrain", and a tab that does nothing until clicked twice reads as broken.
func test_choosing_the_terrain_tab_emits_a_kind() -> void:
	var heard: Array[int] = []
	palette.terrain_picked.connect(func(kind: int) -> void: heard.append(kind))
	palette.set_category(ObjectPalette.Category.TERRAIN)
	assert_eq(heard.size(), 1, "got %s" % [heard])
	assert_eq(heard[0], SimMap.Terrain.GRASS)


## ⚠️ **BY NAME AND NOT BY POSITION.** The index happens to match today, and
## `map_generator.gd`'s own header records what trusting that costs: a member inserted in the
## middle renumbers every one after it, and the byte in `map.png`'s red channel is the VALUE.
func test_every_terrain_tile_resolves_to_its_own_enum_value() -> void:
	var heard: Array[int] = []
	palette.terrain_picked.connect(func(kind: int) -> void: heard.append(kind))
	palette.set_category(ObjectPalette.Category.TERRAIN)
	heard.clear()
	for key in SimMap.Terrain.keys():
		palette.pick(StringName(key))
	assert_eq(heard.size(), SimMap.Terrain.size())
	for i in heard.size():
		assert_eq(heard[i], int(SimMap.Terrain.values()[i]),
				"'%s' resolved to %d" % [SimMap.Terrain.keys()[i], heard[i]])


# ── two signals, not one ────────────────────────────────────────────────────

## ⚠️ **ARMING A TOOL AND REFRESHING A LABEL ARE DIFFERENT EVENTS.** `selection_changed` fires
## when the owner, tint or size class moves; if the editor armed PLACE from it, an author who
## had pressed `Place start` and then set the owner to P2 would silently be holding a different
## tool than the button that is down.
func test_changing_the_owner_does_not_count_as_picking_something() -> void:
	if not _has_game():
		return
	var picked: Array[StringName] = []
	var changed: Array[int] = []
	palette.entry_picked.connect(func(id: StringName) -> void: picked.append(id))
	palette.selection_changed.connect(func() -> void: changed.append(1))

	palette.set_player(2)
	palette.set_tint(3)
	assert_true(picked.is_empty(), "the tool must not be re-armed by a dropdown: %s" % [picked])
	assert_true(changed.size() >= 2, "but the label must still refresh: %s" % [changed])


# ── the icons, which live in the OTHER project ──────────────────────────────

## ⚠️ **THE ONE-LINE HEART OF `IconAtlas`, AS A TEST.** `visuals.json` states its atlas paths
## as `res://assets/atlases/...` because the GAME reads them; from this project `res://` is
## `MapMaker/`. An unrewritten path resolves to a file inside the wrong project, every icon
## comes back missing, and **the palette looks deliberate** — a wall of lettered plates on a
## machine that has all 139 atlases staged.
func test_a_real_atlas_is_cropped_from_outside_this_project() -> void:
	if not _has_game() or int(icons.counts()["staged"]) == 0:
		return  # a clean clone has no staged art, which is the plate path's whole point
	var crop := icons.crop_for(&"unit.villager")
	assert_false(crop.is_empty(), "no crop for the villager: %s" % [icons.warnings])
	assert_not_null(crop["texture"], "the page did not decode")
	var rect: Rect2 = crop["rect"]
	assert_true(rect.size.x > 0.0 and rect.size.y > 0.0, "an empty frame rect: %s" % rect)


## ⚠️ **`ResourceLoader.exists()` ANSWERS TRUE FOR A FILE `load()` CANNOT OPEN, and this test
## exists because the first version of it assumed the opposite.** Measured on 4.7.1: the PNG is
## inside the GAME's `res://` and the game has imported it, so an `.import` sidecar DOES exist
## — and it redirects to `res://.godot/imported/<name>-<hash>.ctex`, which from this project
## means MapMaker's import cache, where there is no such file. `load()` therefore returns null
## after pushing three engine errors.
##
## So the guard `AtlasEntry.texture()` uses is not merely unhelpful here, it is **misleading**,
## and this is the assertion that stops somebody reinstating it as an optimisation.
## `load()` itself is deliberately NOT called: three ERRORs per attempt would land in an
## otherwise clean suite run, and `ScriptErrorSpy` does not catch them because they are ERRORs
## rather than SCRIPT ERRORs. `IconAtlas`'s header records the measurement.
func test_resource_loader_cannot_be_used_as_the_guard_here() -> void:
	if not _has_game() or int(icons.counts()["staged"]) == 0:
		return
	var page := root.path.path_join("assets/atlases/vis.villager_0.png")
	assert_true(FileAccess.file_exists(page), "fixture: %s is not staged" % page)
	assert_true(ResourceLoader.exists(page),
			"if this is false, the sidecar situation has changed -- re-measure load()")
	# THE ROUTE THAT ACTUALLY WORKS, asserted beside the one that does not, so the pair reads
	# as a decision rather than as a preference.
	var img := Image.load_from_file(page)
	assert_not_null(img, "Image.load_from_file is the whole basis of IconAtlas")
	assert_true(img.get_width() > 0 and img.get_height() > 0)


## An id with no visual resolves to nothing rather than to something wrong, and the palette
## draws a plate. **`{}` is an expected answer here, not a failure** — 16.3's row requires the
## tool to open with no atlases at all.
func test_an_unknown_id_crops_nothing_and_says_so_once() -> void:
	var crop := icons.crop_for(&"unit.no_such_thing")
	assert_true(crop.is_empty())


## The plate is tinted from the art's own `PlaceholderSpec.color`, so a clone with no atlases
## gets green trees and pale houses rather than a wall of identical grey squares.
func test_a_plate_takes_its_colour_from_the_arts_own_placeholder() -> void:
	if not _has_game():
		return
	assert_ne(icons.plate_colour(&"unit.villager"), PlaceholderSpec.UNKNOWN_COLOR,
			"the villager has a declared colour and should not read as unknown")


## ⚠️ **AN ID WITH NO ENTRY AT ALL STAYS MAGENTA**, deliberately: it should look like a bug,
## because it is one. `PlaceholderSpec.unknown()`'s own comment says so, and **grey was the
## first answer and was wrong** — grey is indistinguishable from "declared, with no
## placeholder", so a typo'd def id would sit in the palette looking like ordinary missing art.
func test_an_id_with_no_visuals_entry_reads_as_the_loud_unknown() -> void:
	assert_eq(icons.plate_colour(&"vis.definitely_not_declared"),
			PlaceholderSpec.UNKNOWN_COLOR)


## `visuals.json` carries `_note` blocks like every other file in `game/data/`, including
## `_note_dragon_baby`. A reader that does not skip them makes one a visual entry whose atlas
## path is an array of sentences — the trap that cost a red test when `game_content.gd` was
## written.
func test_the_note_keys_in_visuals_json_are_not_visual_entries() -> void:
	if not _has_game():
		return
	for id in icons.declared_ids():
		assert_false(String(id).begins_with("_"), "'%s' is documentation, not a visual" % id)


## Two letters and not one, because `building.barracks` and `building.blacksmith` share a B and
## a palette reading B, B, C, C is no better than one of blanks.
func test_a_plate_carries_two_letters() -> void:
	assert_eq(ObjectPalette.initials_of("Archery Range"), "AR")
	assert_eq(ObjectPalette.initials_of("Barracks"), "BA")
	assert_eq(ObjectPalette.initials_of(""), "?")


## The plate colours come from `visuals.json` and run from `#FFEB00` to `#3f6b34`, so one fixed
## text colour would be invisible on about half the roster — and a plate whose letters cannot
## be read is the blank square the plate exists to avoid.
func test_plate_letters_flip_between_black_and_white_by_lightness() -> void:
	assert_eq(ObjectPalette.readable_on(Color("#FFEB00")).r < 0.5, true, "black on yellow")
	assert_eq(ObjectPalette.readable_on(Color("#0043D6")).r > 0.5, true, "white on blue")


# ── placement (the palette's output, applied) ───────────────────────────────

func test_placing_an_entity_puts_it_where_it_was_asked_for() -> void:
	if not _has_game():
		return
	var doc := MapDocument.create(Vector2i(48, 48), "Placing")
	var id := GameDataRegistry.building_ids()[0]
	assert_true(doc.add_entity(id, 1, Vector2i(20, 20)))
	assert_eq(doc.data.entities.size(), 1)
	assert_eq(doc.data.entities[0]["tile"], Vector2i(20, 20))
	assert_true(doc.dirty)


## ⚠️ **THE OVERLAP CHECK IS `claimed_tiles()`, NOT A SECOND OPINION** — 16.4's row: *"a third
## opinion about what is in the way is a map that validates and cannot be built."* A click that
## silently does nothing looks like a broken tool, which is why the editor says so out loud.
func test_a_second_building_on_the_same_ground_is_refused() -> void:
	if not _has_game():
		return
	var doc := MapDocument.create(Vector2i(48, 48), "Overlap")
	var id := StartLayout.TOWN_CENTRE
	assert_true(doc.add_entity(id, 1, Vector2i(20, 20)), "fixture: the first one must fit")
	# ONE TILE ACROSS, well inside a 10x10 town centre's footprint.
	assert_false(doc.add_entity(id, 1, Vector2i(21, 20)), "an overlap must be refused")
	assert_eq(doc.data.entities.size(), 1)


## ⚠️ **THE WHOLE FOOTPRINT MUST BE ON THE MAP, NOT JUST THE ORIGIN TILE.** A 10x10 town centre
## dropped two tiles from the edge would otherwise author a building whose claimed tiles run
## off the board — and `MapGen.build_from()` would place it, half in the void.
func test_a_footprint_running_off_the_edge_is_refused_even_though_its_origin_is_on_the_map() -> void:
	if not _has_game():
		return
	var doc := MapDocument.create(Vector2i(48, 48), "Edge")
	var bd: BuildingDef = GameDataRegistry.building(StartLayout.TOWN_CENTRE)
	assert_not_null(bd)
	assert_true(bd.footprint.x > 2, "fixture: needs a building wider than the margin below")
	var origin := Vector2i(48 - 2, 20)
	assert_true(doc.data.in_bounds(origin), "fixture: the ORIGIN must be on the map")
	assert_false(doc.add_entity(StartLayout.TOWN_CENTRE, 1, origin))
	assert_true(doc.data.entities.is_empty())


func test_a_resources_size_class_reaches_the_map() -> void:
	if not _has_game():
		return
	var doc := MapDocument.create(Vector2i(48, 48), "Sizes")
	var id := _a_placeable_resource()
	assert_true(doc.add_entity(id, ObjectPalette.GAIA, Vector2i(10, 10), 2))
	assert_eq(int(doc.data.entities[0]["size_class"]), 2)


## ⚠️ **ERASING MATCHES CLAIMED TILES, NOT THE ORIGIN.** An author clicking the middle of a
## 10x10 town centre is pointing at the town centre; a delete that only matched the origin
## would do nothing nine times out of ten.
func test_erasing_hits_anything_whose_footprint_covers_the_tile() -> void:
	if not _has_game():
		return
	var doc := MapDocument.create(Vector2i(48, 48), "Erasing")
	assert_true(doc.add_entity(StartLayout.TOWN_CENTRE, 1, Vector2i(20, 20)))
	assert_eq(doc.remove_entity_at(Vector2i(24, 24)), 1,
			"a click inside the footprint must reach it")
	assert_true(doc.data.entities.is_empty())


## ⚠️ **A START'S CLUSTER IS `remove_start()`'s AND NOT THE ERASER'S.** That function deletes
## by owner AND by the `StartLayout.ORIGIN_KEY` tag precisely so a base and its opening
## resources go together; picking one villager out would leave a cluster the tag no longer
## describes — the state that took the entity count 24 → 40 the first time it was got wrong.
func test_the_eraser_will_not_pick_a_start_apart() -> void:
	if not _has_game():
		return
	var doc := MapDocument.create(Vector2i(48, 48), "Start")
	assert_true(doc.place_start(1, Vector2i(20, 20)))
	var before := doc.data.entities.size()
	assert_true(before > 1, "fixture: a start places a base and its opening")
	assert_eq(doc.remove_entity_at(Vector2i(20, 20)), 0, "the start must be untouched")
	assert_eq(doc.data.entities.size(), before)


## And an author's own tree standing next to a start is still theirs to erase — the tag is what
## separates the two, not proximity. `remove_start()`'s header makes the same point in reverse.
func test_a_hand_placed_node_beside_a_start_is_still_erasable() -> void:
	if not _has_game():
		return
	var doc := MapDocument.create(Vector2i(48, 48), "Beside")
	assert_true(doc.place_start(1, Vector2i(20, 20)))
	var before := doc.data.entities.size()
	var id := _a_placeable_resource()
	var free_tile := Vector2i(40, 40)
	assert_true(doc.add_entity(id, ObjectPalette.GAIA, free_tile), "fixture placement failed")
	assert_eq(doc.remove_entity_at(free_tile), 1)
	assert_eq(doc.data.entities.size(), before)


# ── the guard's new list ────────────────────────────────────────────────────

## ⚠️ **A DRIFTED ICON READER MUST NOT DISABLE SAVING**, and this is the assertion that says so.
## `FormatGuard.PRESENTATION` carries the argument: a map written by a tool with a drifted
## `atlas_entry.gd` is byte-identical to one written without, and 16.3's own row already allows
## the *stronger* failure — no atlases at all — to be survivable. Refusing to save for a wrong
## picture would be the check that cries wolf and therefore gets disabled.
func test_drifted_icon_copies_are_a_note_and_not_a_refusal() -> void:
	var g := FormatGuard.new()
	g.results = [{"name": "src/sim/map_data.gd", "status": int(FormatGuard.Status.OK),
			"detail": "matches"}]
	g.presentation_results = [{"name": "src/view/atlas_entry.gd",
			"status": int(FormatGuard.Status.DRIFTED), "detail": "differs"}]
	assert_true(g.passed(), "saving must stay enabled")
	assert_false(g.presentation_ok(), "and the drift must still be reported")
	assert_true(g.presentation_note().contains("atlas_entry.gd"),
			"the note must name the file: '%s'" % g.presentation_note())


## The other direction: a drifted FORMAT copy still refuses, whatever the icons say. This is
## the property `PRESENTATION` must not have weakened.
func test_a_drifted_format_copy_still_refuses_whatever_the_icons_say() -> void:
	var g := FormatGuard.new()
	g.results = [{"name": "src/sim/map_data.gd", "status": int(FormatGuard.Status.DRIFTED),
			"detail": "differs"}]
	g.presentation_results = [{"name": "src/view/atlas_entry.gd",
			"status": int(FormatGuard.Status.OK), "detail": "matches"}]
	assert_false(g.passed())
	assert_true(g.presentation_ok())


## Both icon copies are actually checked. A list nobody populated would pass every assertion
## above and check nothing at all.
func test_the_icon_copies_are_both_in_the_guard() -> void:
	if not _has_game():
		return
	var g := FormatGuard.check(root)
	assert_eq(g.presentation_results.size(), FormatGuard.PRESENTATION.size())
	assert_eq(g.presentation_results.size(), 2)
