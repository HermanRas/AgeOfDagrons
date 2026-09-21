## A full-screen page of action tiles: BUILD, UPGRADES and UNITS (board
## `8.x-build-menu-modal`; owner, 2026-09-20: *"for the building construction, upgrade
## tiles we are moving to a pop up modal like we have for voice chat"*).
##
## ## WHAT MOVED, AND WHAT DID NOT
##
## The **detail grid** moves here. The **action column** stays exactly where it is. Read
## off the owner's two screenshots: on a villager they boxed House, Lumber Camp, Mill,
## Mining Camp, Town Center, Archery Range, Barracks, Blacksmith, Dock, Field, Market and
## `>` — that is `SelectionActions.MAX_DETAILS` — and left move/stop/attack/hammer/mine/
## guard/destroy alone.
##
## ## ⛔ THE GRID IS FIXED AND THE TILE IS NOT — AND THE FIRST VERSION HAD THIS BACKWARDS
##
## Owner, 2026-09-21, on a screenshot of that first version: *"i meant the same layout,
## 4x4 grid, not the same in size — the entire point of moving to modal is to give better
## readability on cost to build and bigger buttons to tap."*
##
## Their earlier *"scale the icons exactly as is"* was read here as "keep the 72 px tile",
## and it meant "keep the grid's shape". The difference is the whole feature: a page of
## 72 px tiles is five small buttons adrift in a field of brown, which is bigger than the
## strip in no way a thumb or an eye can use. **So the COLUMNS and ROWS are fixed at 4x4,
## the strip's shape, and `ActionSlot.set_tile_size` grows the tile to fill the page.**
##
## ⚠️ **REUSING `ActionSlot` RATHER THAN DRAWING NEW TILES IS STILL THE LOAD-BEARING
## CHOICE**, and it survives the correction: a scaled `ActionSlot` keeps the proportions
## that were argued for at 72 px — the caption costing the sprite's foundation, the cost
## strip costing the sky above the roof — and it already solves the hazard this card was
## most likely to trip on, that *a `TextureRect` demands its texture's full size as a
## minimum*. That is the bug that broke 16.3's MapMaker palette: 32 building pictures in a
## grid with every caption pushed out of its tile. A hand-rolled page tile would have had
## to solve it again, at a size nothing had ever drawn it at.
##
## ## HOW THE SLOT COUNT REACHES THE PURE CODE
##
## `COLUMNS * ROWS` is a constant, so unlike the first version the count is not a
## measurement at all — but it is still **passed** to `SelectionActions.page_of()` rather
## than read from there. That file never sees a `Control.size` or a page: it is static and
## node-free precisely so the whole action model can be asserted headlessly, and the day
## this grid becomes responsive the argument is already in place.
##
## ⚠️ **A `Control` ADDED TO A TREE HAS SIZE `(0, 0)` FOR THE REST OF THAT FRAME**, so the
## TILE SIZE cannot be worked out in `_init` and is recomputed on every resize and on
## `open()`. Before the first layout the tile stands at `ActionSlot.SIZE`, which is the
## strip's own size and a legible page rather than a collapsed one.
##
## ## THE CLOCK KEEPS RUNNING
##
## Inherited from `HudPanel` rather than decided: *"the match carries on underneath, and
## closing the page does not resume anything."* That is right here — a build page that
## paused the match would be a pause button wearing a hammer, and in a network match a
## local pause was never a pause anyway.
class_name ActionPage
extends HudPanel

## A tile with a real action behind it was pressed. The page arrows never reach here —
## they turn the page and are swallowed, the same division `SelectionPanel` draws.
signal action_pressed(action: HudAction)

## THE STRIP'S SHAPE, which is what the owner asked to keep. Four across, and four down
## rather than the strip's three -- a page is taller than a corner panel, and 16 slots
## takes the age-4 build list from two pages to two shorter ones.
const COLUMNS := 4
const ROWS := 4

## Gap between tiles, as a fraction of the tile so it grows with them. At 72 px this is
## the 8 px the strip uses; at a page's 120 px it is 13, which keeps the grid reading as
## separate buttons rather than a sheet.
const GAP_FRACTION := 0.11

var _grid: GridContainer
var _slots: Array[ActionSlot] = []
var _all: Array[HudAction] = []
var _page := 0
## How big a tile is drawn right now. `ActionSlot.SIZE` until the page has been laid out
## once -- see the header on why it cannot be measured in `_init`.
var _tile := ActionSlot.SIZE


func _init() -> void:
	# The chrome, and it is not optional -- see `HudPanel._init`.
	super()
	set_title("BUILD")

	# CENTRED IN BOTH AXES. A grid pinned to the top-left of a wide page puts the tiles
	# under the title and leaves a field of empty brown below them; centred, a short list
	# reads as a deliberate panel rather than as a page that failed to fill.
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	body.add_child(centre)

	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	centre.add_child(_grid)
	_apply_tile_size()

	# ⛔ **`body.resized`, NOT THIS PAGE'S OWN `NOTIFICATION_RESIZED`.** The first version
	# hooked the page and came out at 72 px: the page is `PRESET_FULL_RECT` and has its
	# size from the moment it enters the tree, whereas `body` is `SIZE_EXPAND_FILL` inside
	# a VBox and gets its own only once the container has laid the title, the body and the
	# footer out -- a frame or more later. So the page's notification fires while `body` is
	# still (0, 0), `_remeasure` returns early, and nothing ever measures again.
	#
	# 📝 The symptom was diagnostic and worth recording: BUILD, opened first, drew at 72 px
	# while UNITS, opened several steps later, drew at 98 -- the same code giving two
	# answers is a timing bug, not an arithmetic one.
	body.resized.connect(_remeasure)

	add_close_button()


## Show `actions` under `title`. The WHOLE list, uncapped -- paging is this page's job, the
## same division `SelectionPanel` uses: `details_for()` returns everything and `page_of()`
## slices it, so nothing is ever silently dropped.
##
## Resets to page 0, because a caller opening a different list while holding page 2 of the
## old one would otherwise land mid-way through something else.
func show_actions(title: String, actions: Array[HudAction]) -> void:
	set_title(title)
	_all = actions
	_page = 0
	_refresh()


## Replace the list WITHOUT moving the viewer.
##
## ⛔ **KEEPS THE PAGE NUMBER, WHICH IS WHY IT IS NOT `show_actions`.** The clock runs under
## this page, so the list is re-read every snapshot to keep affordability greying honest --
## and a refresh that reset to page 0 ten times a second would make page 2 impossible to
## read. `show_actions` resets deliberately, because that is a different list arriving.
##
## The page number is still clamped, since the list can shrink under the viewer: an age-4
## build list on page 2 whose owner is somehow back to age 1 lands on the last real page
## rather than on an empty grid.
func update_actions(actions: Array[HudAction]) -> void:
	_all = actions
	_page = mini(_page, maxi(0, page_count() - 1))
	_refresh()


## How many tiles the page holds: `COLUMNS * ROWS`, the strip's shape one row taller.
##
## A constant rather than a measurement, since the owner's correction fixed the GRID and
## freed the tile. It is still handed to `page_of()` rather than read from there -- see the
## header.
func slot_count() -> int:
	return COLUMNS * ROWS


## How big each tile is being drawn. For the preview, which is the only thing that can
## judge whether "bigger" actually happened.
func tile_size() -> float:
	return _tile


func current_page() -> int:
	return _page


func page_count() -> int:
	return SelectionActions.page_count(_all.size(), slot_count())


## The tiles as they are drawn right now, for a test or a preview that wants to press one.
func slots() -> Array[ActionSlot]:
	return _slots


func open() -> void:
	super()
	# Sizes are valid by the time a page is opened in a real tree, but `open()` is also how
	# a preview and a test reach it -- and one that never entered a tree has no size at all.
	_remeasure()


## Work out the grid from the room the page actually has.
##
## ⚠️ **MEASURED OFF `body`, NOT OFF THE PAGE.** The page is the full screen; `body` is
## what is left inside the frame once `HudPanel`'s margins, border, title and footer have
## taken theirs. Measuring the screen would promise columns that do not exist and the last
## one would be drawn under the gold edge.
func _remeasure() -> void:
	if body == null or _grid == null:
		return
	var room := body.size
	if room.x <= 0.0 or room.y <= 0.0:
		return                        # no layout yet; the fallback tile stands

	# How big a tile can be so that COLUMNS x ROWS of them, with the gaps between, fit the
	# room the frame actually left. Solved for the tile rather than for the count, which is
	# the correction: `t * n + gap * (n - 1) <= room`, with `gap = t * GAP_FRACTION`.
	#
	# ⚠️ **THE WIDTH COMES FROM THE SCREEN, NOT FROM `body`, AND THAT IS TO BREAK A LOOP.**
	# `_apply_page_width` below narrows the frame to hug the grid, which narrows `body`,
	# which would narrow the tile, which would narrow the frame again. Measuring the width
	# the page COULD have makes the tile independent of the cap it then sets. The height is
	# safe to read off `body` because nothing here ever changes it.
	var full_width := maxf(0.0, size.x - 2.0 * MARGIN_H - 2.0 * CONTENT_MARGIN)
	var across := _fit(full_width, COLUMNS)
	var down := _fit(room.y, ROWS)
	# The tighter axis wins, or the grid would be taller than the page on a wide window.
	var tile := minf(across, down)

	# ⛔ **NEVER SMALLER THAN THE STRIP.** A page whose tiles came out below
	# `ActionSlot.SIZE` would be a modal that made the thing it replaced harder to read,
	# which is the opposite of why it exists. On a viewport too small to give 4x4 at that
	# size the tiles stay put and the grid is allowed to overflow -- visibly, rather than
	# by silently shrinking past legibility.
	tile = maxf(tile, ActionSlot.SIZE)
	if is_equal_approx(tile, _tile):
		return
	_tile = tile
	_apply_tile_size()


## The largest tile for which `n` of them plus their gaps fit inside `room`.
func _fit(room: float, n: int) -> float:
	if n <= 0:
		return ActionSlot.SIZE
	return room / (float(n) + GAP_FRACTION * float(n - 1))


func _apply_tile_size() -> void:
	var gap := int(roundf(_tile * GAP_FRACTION))
	_grid.add_theme_constant_override("h_separation", gap)
	_grid.add_theme_constant_override("v_separation", gap)
	for slot in _slots:
		slot.set_tile_size(_tile)

	# PULL THE FRAME IN TO THE GRID. The market's precedent, and its exact argument: past
	# the width its content needs, a page grows nothing but empty brown -- and on a wide
	# desktop window that is most of it, because `window/stretch/aspect` is `expand`.
	#
	# ⚠️ **A CAP, NOT A WIDTH.** `_apply_page_width` takes `maxf` against the margin, so on
	# a screen too narrow to grant it the layout is exactly what it would have been. And
	# the slack is split between BOTH edges, so the page stays centred -- the owner
	# reported the first version of the market as *"off centre"* when it was not.
	var grid_width := _tile * COLUMNS + float(gap) * float(COLUMNS - 1)
	max_page_width = grid_width + 2.0 * CONTENT_MARGIN


func _refresh() -> void:
	var shown := SelectionActions.page_of(_all, _page, slot_count())
	_ensure_slots(shown.size())
	for i in range(_slots.size()):
		_slots[i].set_action(shown[i] if i < shown.size() else null)


## Slots are made on demand and reused in place, never freed -- `SelectionPanel`'s
## convention, and for its reason: a page refreshed on every snapshot would otherwise churn
## dozens of nodes a tick, and hiding rather than freeing keeps a headless test's counts
## stable without waiting for a frame.
func _ensure_slots(n: int) -> void:
	while _slots.size() < n:
		var slot := ActionSlot.new()
		# SIZED AS IT IS BORN. A slot made after the page was last measured would
		# otherwise come out at `ActionSlot.SIZE` among its grown siblings -- which is
		# every slot on page 2, since the grid is filled on demand.
		slot.set_tile_size(_tile)
		slot.action_pressed.connect(_on_slot_pressed)
		_grid.add_child(slot)
		_slots.append(slot)


## ⛔ **THE ARROWS ARE SWALLOWED AND EVERYTHING ELSE IS PASSED UP.** Checked first so a nav
## slot can never be mistaken for one carrying a payload, which is exactly what
## `SelectionPanel._on_detail_pressed` does -- and the page number is clamped there rather
## than trusted, because `page_of` clamps too and a number that only LOOKS valid would
## survive unnoticed.
func _on_slot_pressed(action: HudAction) -> void:
	if action == null:
		return
	if action.id == SelectionActions.PAGE_NEXT:
		_page = mini(_page + 1, maxi(0, page_count() - 1))
		_refresh()
		return
	if action.id == SelectionActions.PAGE_PREV:
		_page = maxi(0, _page - 1)
		_refresh()
		return
	action_pressed.emit(action)
