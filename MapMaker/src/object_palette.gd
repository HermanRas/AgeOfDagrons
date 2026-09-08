## The object palette (PLAN.md 16.3): what to place, who owns it, and how big.
##
## ## WHAT IT IS AND WHAT IT IS NOT
##
## It answers one question — **`selection()`**, a `{def_id, player, size_class}` the editor's
## PLACE tool puts on the map. Everything else here is how a person arrives at that answer:
## five category tabs, a search box, an owner picker, a colour picker for the icons and a size
## picker for resources.
##
## Built in code like every other screen in this tool, on `CampaignScreen`'s precedent: the
## lists are DATA, read live out of the game's `data/*.json`, so a scene file could not hold
## them even in principle without going stale the day a building is added.
##
## ## FIVE CATEGORIES, AND **AREA IS DELIBERATELY NOT ONE OF THEM**
##
## 16.3's row spells the dropdown *Unit / Building / Area / Terrain*, and the 2026-09-04
## amendment added **Resource** — without which no map in this game is playable, because
## `MapValidator` requires resources within reach of every start and every node is a
## `ResourceDef` placed as gaia.
##
## ⚠️ **AREA IS LEFT OUT BECAUSE `MapData` HAS NO FIELD FOR ONE UNTIL 16.5.** An Area category
## would let an author draw a region that `MapData.to_dict()` cannot write and `MapFile` then
## silently drops — work lost with a successful save on screen. Phase 15 settled exactly this
## shape and its wording transfers: *"inert is the safe direction for a mode nobody has
## selected; it is the wrong direction for the mode a PLAY button is about to select."* A tab
## in a palette is a thing a person selects. It arrives with 16.5, which is one entry in
## `CATEGORIES`.
##
## ## ⚠️ THE COLOUR PICKER CHANGES WHAT YOU SEE AND NOT WHAT YOU SAVE
##
## **A map file has no colour field.** `MapData`'s entities are `{def_id, player, x, y,
## size_class}` and nothing else; player colour is assigned by the LOBBY in join order out of
## `colours.json` (§4: that order is load-bearing because saves and replays index into it). So
## this control exists for one reason — the game tints unit art per player and
## `GameDataRegistry.atlas_for()` takes a colour, so an author checking that a colour reads
## against their terrain needs to be able to ask for it here.
##
## It is labelled **"icon tint"** rather than "colour" for that reason. Calling it the player's
## colour would be a promise the format cannot keep, and an author who set player 2 to red here
## and then found them blue in the match would be right to call it a bug.
##
## ## THE OWNER PICKER IS GAIA FIRST, AND THAT IS NOT ALPHABETICAL
##
## Every resource node in the game is gaia's (`player: 0`) — trees, mines, berries, fish, and
## the dragon's nest. So Gaia is the owner an author selects most often by a wide margin, and
## it is the DEFAULT the moment the Resource category is chosen. Placing a forest as player 1's
## property is not a thing anybody wants to do by accident.
class_name ObjectPalette
extends PanelContainer

## Emitted when the selected thing changes, so the editor can switch its tool and say what is
## about to be placed. Carries nothing: the editor asks `selection()`.
signal selection_changed

## Emitted when a tile-painting category is picked, with the terrain kind. The palette does not
## know what a brush is — `Editor` owns the tools — so Terrain is a category here and a
## `Tool.PAINT` there.
signal terrain_picked(kind: int)

## A non-terrain entry was CHOSEN, as opposed to the selection merely changing.
##
## ⚠️ **TWO SIGNALS BECAUSE ARMING A TOOL AND REFRESHING A LABEL ARE DIFFERENT EVENTS.**
## `selection_changed` also fires when the owner, the tint or the size class moves — and if
## that armed the PLACE tool, an author who had chosen `Place start` and then set the owner to
## P2 would silently be holding a different tool than the one they pressed. Only picking a
## thing off the grid arms placement.
signal entry_picked(def_id: StringName)

enum Category { BUILDING, UNIT, RESOURCE, TERRAIN }

## The tab order, which is placement order and not alphabetical: **a map is authored
## outside-in** — the ground, then the resources that decide where a base can go, then the
## bases, then whatever else. Buildings lead because a start's town centre is the first thing
## an author places by hand once 16.4's cursors exist.
const CATEGORIES := [
	{"id": Category.BUILDING, "label": "Buildings"},
	{"id": Category.UNIT, "label": "Units"},
	{"id": Category.RESOURCE, "label": "Resources"},
	{"id": Category.TERRAIN, "label": "Terrain"},
	# 16.5 adds {"id": Category.AREA, "label": "Areas"} here, and `MapData` gains the field in
	# the same change. See the class comment on why it is not here yet.
]

## Gaia. `MapData` writes `player: 0` for every resource node, and `StartLayout` relies on it.
const GAIA := 0

## The player start, as a palette entry rather than a toolbar tool (owner's ruling, 2026-09-08:
## *"can we add the start location as a building option ... we can use the same select and erase
## as normal buildings and remove duplicates"*).
##
## ## IT IS NOT A DEF, AND THE NAMESPACE IS WHAT KEEPS THAT HONEST
##
## ⚠️ **A START IS A `MapData.starts` ENTRY, NOT AN ENTITY** — it is *"the CENTRE tile of that
## player's start"* in a field of its own, and placing one runs `StartLayout` to lay down a town
## centre, five villagers, a scout and a ring of resources. So this id names a **tool**, and it
## is deliberately in a `start.` namespace that no roster file uses: `GameDataRegistry.building()`,
## `.resource_def()` and `.unit_raw()` all answer "unknown" for it, which is what stops it being
## mistaken for something placeable through `add_entity`.
##
## **`Editor.apply_tool` is the one place that branches on it.** Everything else treats it as an
## ordinary selection, which is the whole point of the owner's request: one PLACE tool, one
## ERASE tool, one Owner picker, instead of a second set of controls in the toolbar for the one
## thing that had them.
##
## 📝 **AND IT IS WHY THE PALETTE'S BUILDING TAB HAS ONE ROW THE ROSTER DOES NOT.** The
## alternative was a fifth category holding a single tile, which is a tab an author has to find
## to do the first thing they do on a new map. It goes LAST in the tab, after Wonder, because the
## list is sorted as text and appending is the only position that is not a lie about the sort.
const START_ID := &"start.player"

## What the palette calls it. `GameDataRegistry.display_name()` would prettify the id into
## "Player" — the namespace is stripped as a prefix — which is worse than useless on a tile whose
## whole job is to be recognised.
const START_LABEL := "Player Start"

## The two axes a wall can be laid on, as the author sees them on screen (PLAN.md 16.4c, owner
## 2026-09-08: *"add both direction options, ne-sw, nw-se as variants long, medium, short,
## gate"*).
##
## ⚠️ **THE SCREEN NAMES ARE DERIVED FROM `Iso._project`, NOT CHOSEN.** That function is
## `((x - y) * 32, (x + y) * 16)`, so **+x goes right-and-down (screen SE)** and **+y goes
## left-and-down (screen SW)**. A wall lying ALONG tile axis X therefore spans **NW–SE** on
## screen, and one along axis Y spans **NE–SW**. Getting these two labels the wrong way round
## would be a tool that offers both rotations and names them backwards — which is worse than
## offering one, because an author would trust the label. `dev/preview_editor.tscn` photographs
## both so the names can be checked against the picture rather than against this comment.
##
## **Keyed by `WallPlan.AXIS_X` / `AXIS_Y`**, which are what `MapData`'s `axis` key holds and
## what `MapGen.build_from()` reads. There is no third naming of an axis anywhere.
const AXIS_LABELS := {
	0: "NW-SE",                            # WallPlan.AXIS_X
	1: "NE-SW",                            # WallPlan.AXIS_Y
}

## Suffix on a wall variant's id, so the two rotations are two rows with one def behind them.
##
## ⚠️ **THE ID THE MAP SEES IS THE DEF ID WITH THIS STRIPPED OFF.** `selection()` returns the
## real `def_id` plus a separate `axis`, exactly as `MapData.add_entity()` takes them — the
## suffix never reaches the file. **That is the whole difference between this and adding twelve
## more defs to `buildings.json`**: the roster stays twelve walls, `WallPlan.lengths_of()` keeps
## keying them by `footprint.x` without a transposed entry collapsing three lengths into one, and
## a north-south wall has exactly one representation in the sim.
const AXIS_SUFFIX := "@axis"

## The "no tint" row's id in the tint picker.
##
## ⚠️ **IT IS 0 AND THE COLOUR INDICES ARE SHIFTED UP BY ONE, because `OptionButton` treats
## `add_item(text, -1)` as "assign the index as the id".** So an item added with the natural id
## for "no colour" — `-1`, the same value `atlas_for()` takes — silently gets id 0 instead,
## `get_item_index(-1)` finds nothing, `select(-1)` **deselects the control**, and the dropdown
## draws empty. That is what the first screenshot of this palette showed, and it looked like
## one fault rather than two: the box was blank *and* the control had never been connected.
const _TINT_NONE_ID := 0

## One tile in the icon grid. 96 wide rather than the game's 64, because this list carries a NAME
## under the picture and a control-group slot does not.
##
## ⚠️ **118 TALL AND NOT 104: THERE ARE TWO LABEL LINES, AND THE SECOND ONE IS NOT DECORATION.**
## 16.4c gives a wall two rows that share one icon — `_ICON_FACING` is south for every tile here,
## and `WallPlan`'s measurement says south is a diagonal bake no axis-aligned footprint can ask
## for, so **the two rows cannot be told apart by their picture at all.** Only the label
## distinguishes them.
##
## On one line it did not fit. `palette_walls.png` is the record: "Stone Wall (Medium) NW-SE" is
## 25 characters in an 88 px `clip_text` label, and centred clipping trims BOTH ends — so both
## medium rows read **"e Wall (Medium) N"** and the direction, the only thing that differed, was
## the part that got cut. Every test passed. So the direction gets a line of its own, where five
## characters fit with room to spare, and every tile reserves it (blank on the rows that have no
## direction) because a `GridContainer` row is as tall as its tallest child and ragged rows read
## as a broken layout.
const TILE := Vector2i(96, 118)

## How wide the panel wants to be. Three tiles plus the scrollbar, measured rather than
## guessed: at two per row a 32-building roster is sixteen rows of scrolling.
const PANEL_WIDTH := 330

const _TEXT := Color(0.82, 0.82, 0.86)
const _DIM := Color(0.55, 0.55, 0.60)
const _PANEL := Color(0.13, 0.13, 0.16)
const _TILE_BG := Color(0.17, 0.17, 0.21)
const _SELECTED := Color(0.95, 0.78, 0.35)

var _icons: IconAtlas = null

var _category: Category = Category.BUILDING
var _def_id: StringName = &""
var _player := 1
var _size_class := 0
var _tint := -1

var _tabs: Dictionary = {}                        # int -> Button
var _search: LineEdit = null
var _grid: GridContainer = null
var _owner_picker: OptionButton = null
var _tint_picker: OptionButton = null
var _owner_row: Control = null
var _tint_row: Control = null
var _size_row: Control = null
var _size_picker: OptionButton = null
var _count_label: Label = null

## def id -> the tile Button, so a selection change repaints two tiles rather than rebuilding
## the whole grid.
var _tiles: Dictionary = {}


## Hand over the icon reader and fill the panel.
##
## Separate from `_init()`, which builds the controls, because the controls exist before there
## is a roster to put in them: `Editor` builds its whole UI and only then knows whether
## `Startup` found a game project. The panel is therefore legible and empty rather than absent
## when there is nothing to show, which is the state a clean clone opens in.
func setup(icons: IconAtlas) -> void:
	_icons = icons
	_fill_tints()
	# EVERY PICKER SELECTED FROM ITS FIELD, not left to show item 0 and hope they agree. The
	# owner picker is the one this actually caught (see `set_category`), and these two agree
	# only by luck -- `_tint` is -1, which happens to be item 0, and `_size_class` is 0, which
	# happens to be item 0 as well. Luck is not a reason to leave two of three unassigned.
	_tint_picker.select(_tint_picker.get_item_index(_tint + 1))
	_size_picker.select(_size_class)
	# THROUGH `set_category` rather than straight to `_rebuild()`, so the default tab is
	# actually PRESSED and the owner picker starts on the right entry. A palette whose first
	# tab looks unselected reads as a palette that has not loaded.
	set_category(_category)


# ── what the editor asks ────────────────────────────────────────────────────

## What is about to be placed: `{def_id, player, size_class}`, or `{}` when the current
## category places no entity (Terrain) or nothing is chosen.
##
## ⚠️ **`size_class` IS ALWAYS PRESENT AND IS ONLY EVER NON-ZERO FOR A RESOURCE.** It is the
## fourth argument to `MapData.add_entity` and the input to `ResourceDef.footprint_for_size`,
## and 16.3's amendment names the trap plainly: *"a placement that leaves it 0 silently authors
## the small variant."* Returning it in every selection rather than as an optional extra is
## what stops a caller forgetting it exists.
func selection() -> Dictionary:
	if _category == Category.TERRAIN or _def_id.is_empty():
		return {}
	# ⚠️ **THE VARIANT SUFFIX IS SPLIT OFF HERE AND NOWHERE ELSE**, so the id the editor hands to
	# `MapData.add_entity()` is a real def id. A `def_id` of `building.wall_stone_long@axis1`
	# reaching the map would be an entity `GameDataRegistry` cannot resolve: no footprint, no
	# visual, and `MapGen.build_from()` would fall through to `spawn_resource_node()` and spawn
	# nothing. **`axis` rides beside it**, which is exactly the shape `add_entity` takes.
	var split := split_variant(_def_id)
	return {
		"def_id": split[0],
		"player": _player,
		"size_class": _size_class if _category == Category.RESOURCE else 0,
		"axis": int(split[1]),
	}


func category() -> Category:
	return _category


## The icon tint, as a `colours.json` index or -1. **Presentation only** — see the class
## comment. The editor reads it so the placement ghost matches the palette's picture.
func tint() -> int:
	return _tint


## What the TINT PICKER is displaying, as a colour index or -1. **Not `_tint`** — the same
## panel-versus-field split `shown_player()` exists for, and this control had both of that
## pair's faults at once: it was never connected to anything AND it rendered blank, so the
## inertness was invisible behind the emptiness. `_TINT_NONE_ID` has the mechanism.
func shown_tint() -> int:
	if _tint_picker == null or _tint_picker.selected < 0:
		return -99
	return _tint_picker.get_item_id(_tint_picker.selected) - 1


## What the OWNER PICKER is displaying, as a player id. **Not `_player`** — that is the field.
##
## ⚠️ **THE TWO ARE ONE FACT AND THEY CAME APART ON THE FIRST RENDER**, which is why this
## exists at all: `_player` was 1 while an unselected `OptionButton` displayed its item 0,
## which here is Gaia. The panel said one thing and `selection()` said another, and the only
## thing that could see it was a screenshot. `test_object_palette` now asserts they agree.
func shown_player() -> int:
	if _owner_picker == null or _owner_picker.selected < 0:
		return -1
	return _owner_picker.get_item_id(_owner_picker.selected)


## A sentence for the status line: what is selected, in the words the author picked it by.
func describe() -> String:
	if _category == Category.TERRAIN:
		return "brush: %s" % _terrain_label(_terrain_kind())
	if _def_id.is_empty():
		return "nothing selected"
	var who := "gaia" if _player == GAIA else "P%d" % _player
	var size := ""
	if _category == Category.RESOURCE:
		size = ", %s" % SIZE_LABELS[clampi(_size_class, 0, SIZE_LABELS.size() - 1)]
	# ⚠️ **`_label_for()` AND NOT `display_name()` DIRECTLY**, which is the one line the start
	# entry needed here and did not get first time: `display_name(&"start.player")` strips the
	# namespace as a prefix and prettifies what is left, so the status line read
	# **"place: Player (P3)"**. `_label_for` is the function that knows a start is called "Player
	# Start", and it is now the only route to a row's words — found by a preview print, because
	# nothing about it is wrong enough to fail a test.
	return "place: %s (%s%s)" % [_label_for(_def_id), who, size]


# ── choosing ────────────────────────────────────────────────────────────────

## Public so a test and `dev/` can drive the palette with no mouse. Every one of these ends in
## the same two calls, which is what keeps the panel and `selection()` from disagreeing.

func set_category(c: Category) -> void:
	_category = c
	for key in _tabs:
		(_tabs[key] as Button).button_pressed = (int(key) == int(c))
	# GAIA IS THE DEFAULT FOR RESOURCES AND ONLY FOR RESOURCES. Every node in the game is
	# gaia's, so an author who has to change the owner for each tree will eventually forget
	# and author a forest that belongs to player 1. See the class comment.
	#
	# ⚠️ **CALLED UNCONDITIONALLY, EVEN WHEN THE VALUE DOES NOT CHANGE.** The first version
	# only re-selected when the owner needed moving, which left the case nobody thinks about:
	# **at startup nothing had selected anything**, so `_player` was 1 while an `OptionButton`
	# with no selection displays its item 0 — and item 0 here is Gaia. The panel said Gaia,
	# `selection()` said player 1, and the first screenshot of this palette showed exactly
	# that. A control's value and the field behind it are one fact; assigning it only on a
	# change is how they come apart.
	if c == Category.RESOURCE:
		_select_owner(GAIA)
	else:
		_select_owner(1 if _player == GAIA else _player)
	_size_row.visible = (c == Category.RESOURCE)
	# ⚠️ **OWNER AND TINT MEAN NOTHING TO A TERRAIN TILE, so they go away with it.** Terrain is
	# a byte in `map.png`'s red channel and has no owner at all; leaving an Owner dropdown on
	# screen while painting grass invites somebody to set it and wonder why nothing happened.
	# Same rule the size row already follows: **a control that is present and inert is worse
	# than an absent one**, because its presence is a claim.
	var places_an_entity := (c != Category.TERRAIN)
	_owner_row.visible = places_an_entity
	_tint_row.visible = places_an_entity
	# THE SELECTION DOES NOT SURVIVE A CATEGORY CHANGE, deliberately: a def id from another
	# category would still be a legal `selection()` while the grid showed something else, and
	# the editor's status line would name a building under the Units tab.
	_def_id = &""
	_rebuild()
	if c == Category.TERRAIN:
		# The first terrain tile picks itself, so switching to Terrain arms a brush rather
		# than arming nothing -- there is no "no terrain" and a tab that does nothing until
		# clicked twice reads as broken.
		pick(StringName(SimMap.Terrain.keys()[SimMap.Terrain.GRASS]))
	else:
		selection_changed.emit()


## Choose one entry by its id. For Terrain the id is the enum key name (`"GRASS"`); for
## everything else it is a def id.
func pick(id: StringName) -> void:
	if _category == Category.TERRAIN:
		_def_id = id
		_repaint_tiles()
		terrain_picked.emit(_terrain_kind())
		selection_changed.emit()
		return
	_def_id = id
	_repaint_tiles()
	entry_picked.emit(id)
	selection_changed.emit()


func set_search(text: String) -> void:
	if _search != null and _search.text != text:
		_search.text = text
	_rebuild()


func set_player(p: int) -> void:
	_select_owner(p)
	selection_changed.emit()


func set_size_class(sc: int) -> void:
	_size_class = maxi(0, sc)
	if _size_picker != null:
		_size_picker.select(_size_class)
	# THE ICONS CHANGE WITH IT, because `ResourceDef.visual_for_size` gives a large mine and a
	# small one different art. A size picker that did not repaint would be a control with no
	# visible effect until something is placed.
	_rebuild()
	selection_changed.emit()


func set_tint(colour: int) -> void:
	_tint = colour
	# THE CONTROL MOVES WITH THE FIELD, so a caller that is not the control itself -- a test,
	# `dev/`, or a future keyboard shortcut -- cannot leave the panel showing the old value.
	# `set_player` and `set_size_class` both already did this; this one did not, which is the
	# third instance of the same split in one file.
	if _tint_picker != null:
		var at := _tint_picker.get_item_index(colour + 1)
		if at >= 0:
			_tint_picker.select(at)
	_rebuild()
	selection_changed.emit()


## The entries the grid is currently showing, in order. Public because it is the half of this
## row a headless test can judge: the right things, sorted as text, filtered by the search.
func listed_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	var needle := _search.text.strip_edges().to_lower() if _search != null else ""
	for id in available_ids():
		if needle.is_empty() or _matches(id, needle):
			out.append(id)
	return out


## Everything this category OFFERS, before the search box narrows it.
##
## ⚠️ **THE `placeable` FLAG IS HONOURED HERE AND NOWHERE ELSE**, which is why
## `GameDataRegistry.resource_ids()` still returns all eleven: the roster's SIZE and what an
## author may place are two different facts, and `Boot`'s report wants the first — a report
## reading "resources 5" would make somebody think six failed to load.
##
## The flag is false on the six carcasses (owner, 2026-09-08: *"no placement of carcasses is
## acceptable"*) — a carcass is what hunting LEAVES, so it is a runtime spawn wearing a
## `ResourceDef`'s clothes.
##
## **Two totals, not one, and that is the reason this is a separate function**: the count line
## under the grid says *"none of 5 match"* rather than *"none of 11"*, because 11 would name a
## filter the author did not set and send them looking for six missing rows.
##
## Terrain is exempt: its ids are enum key names rather than roster entries, so asking the
## registry about "GRASS" would search three JSON files and land on the unknown-id answer —
## true, and for the wrong reason.
func available_ids() -> Array[StringName]:
	if _category == Category.TERRAIN:
		return _ids_for(_category)
	var out: Array[StringName] = []
	for id in _ids_for(_category):
		if not GameDataRegistry.placeable(id):
			continue
		# ⚠️ **A WALL IS TWO ROWS, ONE PER AXIS** (16.4c). The def itself is NOT offered: it
		# carries no orientation, and a row that placed one without an axis would write the
		# entity the game builds ninety degrees wrong. So the plain id is replaced by its two
		# variants rather than joined by them -- an author must choose a direction, because the
		# map has to record one.
		if _is_directional(id):
			for axis in [WallPlan.AXIS_X, WallPlan.AXIS_Y]:
				out.append(variant_id(id, axis))
			continue
		out.append(id)
	# THE START GOES LAST IN THE BUILDING TAB. Appended after the roster rather than sorted into
	# it: the list is ordered as text and `START_ID` is not a def, so inserting it alphabetically
	# would put a tool between two buildings and make the sort a lie. See `START_ID`.
	if _category == Category.BUILDING:
		out.append(START_ID)
	return out


## Does this def need the author to choose a direction?
##
## ⚠️ **ASKED OF THE ROSTER, NOT OF THE FOOTPRINT AND NOT OF THE ID's SPELLING.**
## `GameDataRegistry.axis_variants()` has the full argument and the measurement behind it: a
## non-square test offered rotations to **twenty** buildings rather than twelve — an archery
## range, a dock, a field and a mill are all oblong and none of them has art that rotates — and
## an id-spelling test is the second opinion about the roster that 16.3 ruled out. The flag is
## `axis_variants: true` in `game/data/buildings.json`, on the twelve walls and gates.
static func _is_directional(id: StringName) -> bool:
	return GameDataRegistry.axis_variants(id)


## `building.wall_stone_long` + `AXIS_Y` -> `building.wall_stone_long@axis1`.
##
## A palette row's identity, and nothing else's: `selection()` splits it again. See `AXIS_SUFFIX`.
static func variant_id(def_id: StringName, axis: int) -> StringName:
	return StringName("%s%s%d" % [def_id, AXIS_SUFFIX, axis])


## The real def id behind a palette row, and the axis it asked for.
##
## Returns `[def_id, axis]` with `axis` = `MapData.AXIS_NONE` for every ordinary row — which is
## what `add_entity()` wants for anything that has no orientation, so the caller never has to
## branch on whether a row was a variant.
static func split_variant(id: StringName) -> Array:
	var text := String(id)
	var at := text.rfind(AXIS_SUFFIX)
	if at < 0:
		return [id, MapData.AXIS_NONE]
	return [StringName(text.substr(0, at)),
			int(text.substr(at + AXIS_SUFFIX.length()))]


## ⚠️ **SORTED AS TEXT BY `GameDataRegistry`, AND NEVER RE-SORTED HERE.**
## `Array[StringName].sort()` orders by identity rather than spelling and **not stably between
## runs** (§6, and 16.3's row carries the warning). `game_content.gd`'s `_sorted_keys` casts to
## String first; this function's job is only to pick which list.
func _ids_for(c: Category) -> Array[StringName]:
	match c:
		Category.BUILDING: return GameDataRegistry.building_ids()
		Category.UNIT: return GameDataRegistry.unit_ids()
		Category.RESOURCE: return GameDataRegistry.resource_ids()
		Category.TERRAIN: return GameDataRegistry.terrain_kinds()
	return [] as Array[StringName]


## The search matches the DISPLAY NAME and the ID, not one or the other.
##
## Both, because an author knows a thing by two names and neither is reliably the one they
## type: *"Archery Range"* is what the palette says, and `building.archery_range` is what
## `buildings.json` and every note in this repo call it. Matching only the label would make the
## id searchable nowhere; matching only the id would make the search useless to anybody who has
## not read the data files.
func _matches(id: StringName, needle: String) -> bool:
	if String(id).to_lower().contains(needle):
		return true
	return _label_for(id).to_lower().contains(needle)


func _label_for(id: StringName) -> String:
	if id == START_ID:
		return START_LABEL
	if _category == Category.TERRAIN:
		return _terrain_label(_kind_of(id))
	var split := split_variant(id)
	if int(split[1]) != MapData.AXIS_NONE:
		# THE DIRECTION IS THE HALF THAT DISTINGUISHES THE ROW, so it goes on the end where the
		# label is clipped from -- `_tile_for()` sets `clip_text`, and the tile is 88 px wide.
		# ⚠️ Which is why the DEF's own name had to grow a length: "Stone Wall NW-SE" three times
		# over would have been three identical rows again with a direction stuck on.
		return "%s %s" % [GameDataRegistry.display_name(split[0]),
				str(AXIS_LABELS.get(int(split[1]), "?"))]
	return GameDataRegistry.display_name(id)


# ── the grid ────────────────────────────────────────────────────────────────

func _rebuild() -> void:
	if _grid == null:
		return
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	_tiles.clear()

	var ids := listed_ids()
	for id in ids:
		var tile := _tile_for(id)
		_tiles[id] = tile
		_grid.add_child(tile)

	if _count_label != null:
		# THE COUNT AND THE REASON THERE IS NOTHING ARE TWO FACTS -- §6's row about the server
		# browser's JOIN button, which shipped enabled with nothing to join because one
		# variable answered both. An empty grid under a search says something different from
		# an empty grid under an unread roster.
		_count_label.text = _count_text(ids.size())
		_count_label.add_theme_color_override("font_color",
				_DIM if ids.size() > 0 else _SELECTED)
	_repaint_tiles()


func _count_text(shown: int) -> String:
	# AGAINST WHAT THE CATEGORY OFFERS, not against the whole roster -- `available_ids()` has
	# the argument. The Resource tab offers 5 of 11 and the other 6 are not a filter the
	# author set.
	var total := available_ids().size()
	if total == 0:
		# NAMES THE ROSTER, not the search. "0 of 0" under an unloaded roster would send
		# somebody to clear a search box that is already empty.
		return "  the roster has no %s — is the game project readable?" \
				% str(CATEGORIES[int(_category)]["label"]).to_lower()
	if shown == 0:
		return "  none of %d match \"%s\"" % [total, _search.text.strip_edges()]
	return "  %d of %d" % [shown, total] if shown < total else "  %d" % total


## One 96x104 tile: a picture (or a lettered plate) and a name under it.
##
## A `Button` for free hit-testing, with a custom-drawn face — `ControlGroupSlot`'s pattern.
## The picture is a `TextureRect` with `STRETCH_KEEP_ASPECT_CENTERED` and **that is not a
## style choice**: §6's row says `draw_texture_rect_region` has no keep-aspect mode and two
## hand-drawn slots in the game stretched their portraits independently before anybody noticed.
## A `TextureRect` gets the fitting from the engine, which is why the action tiles never had
## the bug.
func _tile_for(id: StringName) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(TILE)
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	# THE FULL NAME AND THE ID, because the label under the picture is clipped and the tooltip
	# is where the thing an author is hunting for can be read in full.
	b.tooltip_text = "%s\n%s" % [_label_for(id), id]
	b.pressed.connect(func() -> void: pick(id))

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	b.add_child(column)

	column.add_child(_picture_for(id))

	# THE NAME, WITHOUT THE DIRECTION. `_label_for()` is the full row name and is what the search
	# and the status line use; the tile splits it over two lines because the direction is the half
	# that must survive clipping. See `TILE`.
	var label := Label.new()
	label.text = _name_line(id)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", _TEXT)
	label.add_theme_font_size_override("font_size", 11)
	# ⚠️ **`clip_text` WITH AN EXPLICIT MINIMUM**, which is §6's fix and not a belt-and-braces
	# habit: clipping takes a Label's minimum width to ZERO, and a zero-minimum label in a
	# fixed-size tile came out in the game as a row of icons with no words at all.
	label.clip_text = true
	label.custom_minimum_size = Vector2(TILE.x - 8, 0)
	column.add_child(label)

	# ⚠️ **THE DIRECTION, ON ITS OWN LINE, AND PRESENT EVEN WHEN EMPTY.** Two rows of a wall share
	# one picture, so this is the only thing that tells them apart — and a tile that omitted the
	# line when there is no direction would be shorter than its neighbours, which in a
	# `GridContainer` means the whole row grows to the tallest and the pictures stop lining up.
	var axis_line := Label.new()
	axis_line.text = _axis_line(id)
	axis_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# BRIGHTER THAN THE NAME, not dimmer: it is the distinguishing half, and `_DIM` here would
	# make the one word an author is scanning for the hardest one to read.
	axis_line.add_theme_color_override("font_color", _SELECTED)
	axis_line.add_theme_font_size_override("font_size", 11)
	axis_line.clip_text = true
	axis_line.custom_minimum_size = Vector2(TILE.x - 8, 14)
	column.add_child(axis_line)
	return b


## The tile's first line: the row's name with the direction taken off it.
##
## Not `static`, because `_label_for()` reads the category to name a terrain kind — and every
## other row on every other tab goes through this too, so it has to answer for all of them and
## not just for a wall.
func _name_line(id: StringName) -> String:
	var split := split_variant(id)
	if int(split[1]) != MapData.AXIS_NONE:
		return GameDataRegistry.display_name(split[0])
	return _label_for(id)


## The tile's second line: the direction, or nothing.
static func _axis_line(id: StringName) -> String:
	var axis := int(split_variant(id)[1])
	return str(AXIS_LABELS.get(axis, "")) if axis != MapData.AXIS_NONE else ""


## The picture, or the lettered plate that stands in for one.
##
## ⚠️ **A PALETTE THAT FINDS NO ATLASES MUST DRAW LETTERED PLATES AND CARRY ON** — 16.3's row,
## `atlas_for()`'s totality rule, and the reason is concrete: `game/assets/atlases/` is
## gitignored staged art, so it is present on the owner's machine and **absent in a clean
## clone**. A tool that will not open without it is a tool that cannot be handed to anybody.
##
## The plate is tinted from the art's own `PlaceholderSpec.color` (see `IconAtlas.plate_colour`)
## rather than from a guess, so a clone with no art gets green trees and pale houses instead of
## a wall of grey squares.
func _picture_for(id: StringName) -> Control:
	# TWO LABEL LINES BELOW IT NOW, not one -- see `TILE`. Derived from the tile rather than
	# written out, so the picture and the caption cannot both claim the same pixels.
	var box := Vector2(TILE.x - 8, TILE.y - 42)
	# ⚠️ **THE START'S TILE IS THE COLOUR THE MARKER IS DRAWN IN ON THE CANVAS**, which is the
	# same argument the terrain swatches make one branch down: an author matching what they picked
	# to what appeared has to be able to do it by colour. It is NOT a lettered plate — that path
	# ends in `PlaceholderSpec.UNKNOWN_COLOR`, which is magenta and means *"this is a bug"*, and a
	# deliberate tool drawn in the bug colour is the one thing worse than no icon.
	if id == START_ID:
		return _swatch(MapCanvas.START_COLOUR, box)
	# ⚠️ **A VARIANT ROW ASKS FOR ITS DEF's PICTURE, and the split has to happen before the
	# crop.** `IconAtlas.visual_for()` would answer `&""` for `...@axis1` — no building, no
	# resource, no unit, not a declared visual — and every wall row would come out as a **magenta
	# UNKNOWN plate**, which is the colour reserved for *"this is a bug"*. It would have looked
	# like the atlases had stopped resolving rather than like an id with a suffix on it.
	#
	# 📝 **BOTH ROWS OF A WALL SHOW THE SAME PICTURE**, and that is honest rather than lazy:
	# `_ICON_FACING` is 0 (south) for every icon in this palette, and `WallPlan`'s measurement
	# says S and N are the two **diagonal** wall bakes, which no axis-aligned footprint can ever
	# ask for. So neither row's icon is the sprite that will be drawn, the LABEL is what
	# distinguishes them, and cropping facing 6 for one row would show a picture that is only
	# arguably more right while implying the other is wrong.
	if _category == Category.TERRAIN:
		# TERRAIN HAS NO SPRITE IN THIS TOOL AND SHOULD NOT PRETEND TO. `MapCanvas` draws flat
		# diamonds in its own presentational colours (its header is emphatic that they are
		# neither the file's nor the game's art), so a swatch in the SAME colours is the honest
		# picture -- an author matching a brush to what they see on the canvas.
		return _swatch(MapCanvas.TERRAIN_COLOURS.get(_kind_of(id), Color.MAGENTA), box)

	# THE REAL DEF, so a variant row crops its own def's art. See the comment above.
	var def_id: StringName = split_variant(id)[0]
	var crop := _icons.crop_for(def_id, 0, _tint, _size_class) if _icons != null else {}
	if crop.is_empty():
		# ⚠️ **THE PLATE TAKES THE VARIANT ID AND NOT THE DEF ID**, deliberately and unlike the
		# crop: its letters come from `_label_for()`, and on a clean clone with no atlases both
		# rows of a wall would otherwise be the same two letters with no way to tell them apart.
		return _plate(id, box)

	var rect: Rect2 = crop["rect"]
	var picture := TextureRect.new()
	var atlas := AtlasTexture.new()
	atlas.atlas = crop["texture"]
	atlas.region = rect
	picture.texture = atlas
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# ⚠️ **`EXPAND_IGNORE_SIZE`, AND WITHOUT IT THE FIRST RENDER OF THIS PALETTE WAS A MESS.**
	# A `TextureRect`'s minimum size defaults to its TEXTURE's size (`EXPAND_KEEP_SIZE`), and
	# these regions are baked battle sprites — a town centre's frame is several hundred pixels
	# square. So every tile demanded hundreds of pixels, the `VBoxContainer` round it
	# **overflowed** (§6: it does not clip, scroll or compress past its children's minimums),
	# the pictures spilled over each other and **the name label was pushed clean out of the
	# tile** — 32 buildings with one visible caption between them.
	#
	# `STRETCH_KEEP_ASPECT_CENTERED` alone does not fix it: the stretch mode says how to draw
	# inside the rect, and the expand mode is what decides how big the rect is allowed to be.
	# The two are needed together and only one of them is the famous one.
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.custom_minimum_size = box
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return picture


## Up to two letters of the name on a plate in the art's own colour.
##
## Two letters and not one: `building.barracks` and `building.blacksmith` share a B, and a
## palette of thirty-two plates reading B, B, C, C is no better than thirty-two blanks. The
## initials of the display name where there are two words, else the first two characters.
func _plate(id: StringName, box: Vector2) -> Control:
	var plate := PanelContainer.new()
	var style := StyleBoxFlat.new()
	# TOTAL, so there is no second drawing path here -- `IconAtlas.plate_colour` always
	# answers, and the fallback below is only for the no-roster case where there is no
	# `IconAtlas` at all.
	# THE DEF's COLOUR, split off the variant suffix -- `plate_colour` reads `visuals.json`, which
	# knows nothing about a palette row's identity and would answer the loud magenta for a
	# suffixed id. The LETTERS come from the variant's label, one line down, so the two rows of a
	# wall are still tellable apart on a clone with no atlases.
	var colour_id: StringName = split_variant(id)[0]
	style.bg_color = _icons.plate_colour(colour_id, _size_class) if _icons != null else _TILE_BG
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	plate.add_theme_stylebox_override("panel", style)
	plate.custom_minimum_size = box
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var letters := Label.new()
	letters.text = initials_of(_label_for(id))
	letters.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	letters.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	letters.add_theme_font_size_override("font_size", 26)
	# ⚠️ **BLACK OR WHITE BY THE PLATE'S OWN LIGHTNESS**, because these colours come from
	# `visuals.json` and range from `#FFEB00` to `#3f6b34`. One fixed text colour would be
	# invisible on roughly half the roster, and a plate whose letters cannot be read is the
	# blank square this whole function exists to avoid.
	letters.add_theme_color_override("font_color", readable_on(style.bg_color))
	plate.add_child(letters)
	return plate


## Up to two letters for a name: the initials of the first two words, else the first two
## characters. Upper case, because these are read as a monogram and not as a word.
static func initials_of(label: String) -> String:
	var words := label.strip_edges().split(" ", false)
	if words.size() >= 2:
		return (str(words[0]).substr(0, 1) + str(words[1]).substr(0, 1)).to_upper()
	if words.is_empty():
		return "?"
	return str(words[0]).substr(0, 2).to_upper()


## Black on a light plate, white on a dark one, by perceived lightness rather than by the raw
## average — `colours.json`'s own argument, one layer down: the yellow in that palette is at
## L* 92 and the green at 59, and an average would put them on the same side of the line.
static func readable_on(bg: Color) -> Color:
	var luma := 0.2126 * bg.r + 0.7152 * bg.g + 0.0722 * bg.b
	return Color(0.06, 0.06, 0.08) if luma > 0.45 else Color(0.95, 0.95, 0.96)


func _swatch(colour: Color, box: Vector2) -> Control:
	var rect := ColorRect.new()
	rect.color = colour
	rect.custom_minimum_size = box
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


## Mark the chosen tile. **Two tiles repainted rather than the grid rebuilt**, because a
## rebuild on every click would drop and re-create up to 363 controls and re-crop every icon.
func _repaint_tiles() -> void:
	for id in _tiles:
		var b := _tiles[id] as Button
		b.button_pressed = (id == _def_id)


# ── ui ──────────────────────────────────────────────────────────────────────

func _init() -> void:
	custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = _PANEL
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	add_theme_stylebox_override("panel", style)
	_build()


func _build() -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	add_child(column)

	# ── the tabs ──
	var tabs := HFlowContainer.new()
	# `HFlowContainer` AND NOT AN `HBoxContainer`: its minimum width is the widest single
	# child rather than the sum, so four tabs in a 330 px column wrap instead of forcing the
	# panel wider. §6's row about the lobby's voice row is the same fix for the same reason.
	column.add_child(tabs)
	for entry in CATEGORIES:
		var b := Button.new()
		b.text = str(entry["label"])
		b.toggle_mode = true
		var id: int = int(entry["id"])
		b.pressed.connect(func() -> void: set_category(id as Category))
		_tabs[id] = b
		tabs.add_child(b)

	# ── search ──
	_search = LineEdit.new()
	_search.placeholder_text = "search"
	_search.clear_button_enabled = true
	# ⚠️ **A PLAIN `LineEdit`, WHICH IS CORRECT HERE AND NOWHERE IN THE GAME.** PLAN.md §16
	# decision 6: this tool is mouse and keyboard only, so `TouchLineEdit` and the whole
	# `emulate_mouse_from_touch` hazard do not apply.
	#
	# 📝 **BUT IT IS THE FIELD 16.2a's CARD WARNS ABOUT.** A focused `LineEdit` swallows
	# `Ctrl+Z`, so undo must not be a `_input` handler on the canvas when it lands. Same class
	# as the HUD `Control` that ate three build buttons.
	_search.text_changed.connect(func(_t: String) -> void: _rebuild())
	column.add_child(_search)

	# ── owner and tint ──
	var owner_row := HBoxContainer.new()
	_owner_row = owner_row
	owner_row.add_theme_constant_override("separation", 4)
	owner_row.add_child(_label("Owner"))
	_owner_picker = OptionButton.new()
	# GAIA FIRST, then the eight the lobby can seat. See the class comment: every resource
	# node in the game is gaia's, which makes this the most-used entry and not a special case.
	_owner_picker.add_item("Gaia", GAIA)
	for p in range(1, 9):
		_owner_picker.add_item("P%d" % p, p)
	_owner_picker.item_selected.connect(func(at: int) -> void:
			set_player(_owner_picker.get_item_id(at)))
	owner_row.add_child(_owner_picker)
	column.add_child(owner_row)

	var tint_row := HBoxContainer.new()
	_tint_row = tint_row
	tint_row.add_theme_constant_override("separation", 4)
	# "ICON TINT" AND NOT "COLOUR". The map file has no colour field -- the class comment has
	# the argument, and the label is where it stops being a trap for the person using it.
	tint_row.add_child(_label("Icon tint"))
	_tint_picker = OptionButton.new()
	# ⚠️ **IDS ARE THE COLOUR INDEX PLUS ONE, AND THAT IS NOT FUSSINESS.**
	# `OptionButton.add_item(text, id)` treats **id = -1 as "assign the index as the id"**, so
	# the first version's `add_item("none", -1)` did not create an item with id -1 — it created
	# one with id 0, `get_item_index(-1)` then found nothing, `select(-1)` deselected the
	# control, and the dropdown rendered **blank**. Shifting by one keeps every id a
	# non-negative number the API will store verbatim.
	_tint_picker.add_item("none", _TINT_NONE_ID)
	# AND IT WAS NOT CONNECTED AT ALL, which the blank box hid: an inert control that also
	# looks empty reads as one fault. Same family as §6's volume sliders, which were dead
	# under a thumb from the day they landed with every test green.
	_tint_picker.item_selected.connect(func(at: int) -> void:
			set_tint(_tint_picker.get_item_id(at) - 1))
	tint_row.add_child(_tint_picker)
	column.add_child(tint_row)

	# ── size class, resources only ──
	_size_row = HBoxContainer.new()
	(_size_row as HBoxContainer).add_theme_constant_override("separation", 4)
	_size_row.add_child(_label("Size"))
	_size_picker = OptionButton.new()
	for i in SIZE_LABELS.size():
		_size_picker.add_item(str(SIZE_LABELS[i]), i)
	_size_picker.item_selected.connect(func(at: int) -> void: set_size_class(at))
	_size_row.add_child(_size_picker)
	# HIDDEN UNTIL THE RESOURCE TAB IS CHOSEN, because `size_class` means nothing to a building
	# or a unit and a control that is present and inert invites somebody to set it.
	_size_row.visible = false
	column.add_child(_size_row)

	_count_label = Label.new()
	_count_label.add_theme_color_override("font_color", _DIM)
	_count_label.add_theme_font_size_override("font_size", 11)
	_count_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_count_label)

	# ── the icon grid ──
	var scroll := ScrollContainer.new()
	# ⚠️ **A `GridContainer` OVERFLOWS -- it does not clip, scroll or compress** (§6), so a
	# roster the tool does not control the size of MUST have a `ScrollContainer` round it. The
	# game's lobby learned this at eight player slots, with every structural test passing.
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_grid)
	column.add_child(scroll)


## Filled once the roster and `colours.json` are readable — `_build()` runs from `_init()`,
## before `setup()` has handed over an `IconAtlas`.
func _fill_tints() -> void:
	if _tint_picker == null or _icons == null:
		return
	# REBUILT FROM ITEM 1, so calling this twice does not stack eight colours twice. "none" is
	# item 0 and is not a colour.
	while _tint_picker.item_count > 1:
		_tint_picker.remove_item(_tint_picker.item_count - 1)
	var list := _icons.colours()
	for i in list.size():
		# `i + 1`: see `_TINT_NONE_ID` on why no id here may be negative.
		_tint_picker.add_item(str(list[i]["name"]), i + 1)
		# THE SWATCH IS THE POINT of listing them: eight names is a list, eight coloured dots
		# is a palette. `colours.json`'s own note argues these are a legibility requirement.
		_tint_picker.set_item_icon(_tint_picker.item_count - 1, _dot(list[i]["colour"]))


## A small solid square, for the tint picker's rows.
static func _dot(colour: Color) -> ImageTexture:
	var img := Image.create(14, 14, false, Image.FORMAT_RGBA8)
	img.fill(colour)
	return ImageTexture.create_from_image(img)


func _select_owner(p: int) -> void:
	_player = p
	if _owner_picker == null:
		return
	for i in _owner_picker.item_count:
		if _owner_picker.get_item_id(i) == p:
			_owner_picker.select(i)
			return


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", _TEXT)
	return l


# ── terrain, which is a category rather than an entity ──────────────────────

## `Small / Medium / Large`, the three `ResourceDef` size classes. **Read off the def rather
## than written out** would be better and is not possible: `size_class` is an index into
## `ResourceDef`'s own arrays and the game names the classes nowhere. Three because
## `resources.json` declares three; if that changes, `_size_picker` shows the wrong number of
## rows and the trap is silent, so `test_object_palette` asserts the count against the roster.
## 📝 **PUBLIC SINCE 16.4, because the inspector needs the same three words.** An entity's size
## class is editable after the fact (`MapDocument.set_selected_size_class`), and a panel that
## called them 0/1/2 while the palette called them Small/Medium/Large would be two vocabularies
## for one field — §6's *"mirroring a layout is not sharing one"* with a label instead of a
## width. One list, two readers.
const SIZE_LABELS := ["Small", "Medium", "Large"]


## The enum value behind a terrain tile's id (`"GRASS"` -> `SimMap.Terrain.GRASS`).
##
## **BY NAME AND NOT BY POSITION.** `GameDataRegistry.terrain_kinds()` builds its list from
## `SimMap.Terrain.keys()`, so the index happens to match today — and `map_generator.gd`'s own
## header records what trusting that costs: an enum member inserted in the middle renumbers
## every one after it. The byte in `map.png`'s red channel is the enum VALUE.
func _kind_of(id: StringName) -> int:
	var at: int = SimMap.Terrain.keys().find(String(id))
	return int(SimMap.Terrain.values()[at]) if at >= 0 else SimMap.Terrain.GRASS


func _terrain_kind() -> int:
	return _kind_of(_def_id) if not _def_id.is_empty() else SimMap.Terrain.GRASS


static func _terrain_label(kind: int) -> String:
	return str(SimMap.Terrain.keys()[kind]).capitalize()
