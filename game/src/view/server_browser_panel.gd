## THE SERVER BROWSER, AS A WIREFRAME (project owner, 2026-08-31: *"lets build out a
## wireframe for server browser / server discovery"*). PLAN.md 12.1's open end.
##
## **NOTHING HERE DISCOVERS ANYTHING, AND THE PAGE SAYS SO ON ITS OWN FACE.** That is
## the standing rule on this project rather than a caveat: a control wired to nothing
## must not look like one that works. The selection panel's roster grid drew, took taps
## and played a click sound for the whole life of the project while doing nothing at
## all, and the chat page (8.4b) is the shape this follows -- every control disabled, a
## note at the top saying why, and `CheckButton`s over buttons wherever a disabled
## control still has to show its STATE.
##
## THE ROWS ARE A LAYOUT SAMPLE AND ARE LABELLED AS ONE. An empty list is the honest
## rendering of "discovery does not exist", and it is also a wireframe that shows
## nothing: the whole question this page is being asked is *what does a found server
## look like, and what do you need to read off it before you dial*. So it draws three
## rows under a heading that says they are not real, which is a different claim from
## three rows pretended into a live list.
##
## ── WHAT A REAL ONE NEEDS, in the order it needs it ──────────────────────────
##
##   1. **A DISCOVERY TRANSPORT, and LAN is the whole of v1.** `Net` is ENet over a
##      known port (`Net.PORT`) and the lobby's own dial line already prints this
##      device's addresses -- so discovery is a `PacketPeerUDP` broadcasting a small
##      "I am hosting" beacon on a second port and this page listening for it. It does
##      NOT need a master server, and it must not quietly become one: an internet
##      browser is a service somebody has to run and pay for, and PLAN.md's multiplayer
##      is two devices on a sofa.
##   2. **A BEACON PAYLOAD, which is a subset of `MatchConfig` and not a new format.**
##      Everything the columns below show is already in the config the host broadcasts
##      to its lobby (`Net.broadcast_lobby_config`): the map type and size, the victory
##      mode, the starting age, the player count. What is NOT in it is a HOST NAME --
##      today a host is an IP address, and a browser listing four of those is a browser
##      nobody can choose from. That is the one new field, and it wants to be a lobby
##      setting beside the seed.
##   3. **A JOIN THAT IS THE EXISTING JOIN.** Pressing a row must end in
##      `SkirmishScreen._on_join_pressed` with the address filled in, not in a second
##      path into `Net.join` -- the lobby's join already handles the failure cases
##      (already in a session, a refused socket, the missing Android INTERNET
##      permission) and a browser with its own copy would rediscover each of them.
##   4. **A REFRESH THAT IS HONEST ABOUT TIME.** A beacon is a datagram and datagrams
##      are lost; a list that clears itself and repopulates over two seconds reads as a
##      flicker. The pattern that works is a rolling window -- a host stays listed for
##      a few seconds after its last beacon -- and REFRESH means "start the window
##      again", not "clear the list".
##
## ⚠️ **THE ONE THING THAT WILL BITE.** `Net.has_session()` is true for a host the
## moment a slot is opened, and this page is reachable FROM that screen -- so a host
## browsing for other hosts and pressing JOIN would be dialling out of a session it is
## already running. The lobby's join says *"already in a session -- go Back to leave
## it"*, which is the right answer, and this page should grey JOIN for that reason
## rather than let the refusal come as a surprise two taps later.
class_name ServerBrowserPanel
extends HudPanel

## The columns, in order, with the width each needs and the icon that heads it.
##
## WIDTHS ARE PER COLUMN AND SHARED BY EVERY ROW, which is what makes this a table
## rather than a stack of unrelated lines -- the header and the rows are laid out by the
## same list, so a column cannot drift between them. A `GridContainer` was the
## alternative and was dropped for one reason: a row has to become PRESSABLE (see the
## header, item 3), and a grid's cells are separate controls with nothing to press.
##
## `icon` is a name under `assets/ui/icons/`, or `&""` for a column whose heading is
## short enough to speak for itself. All four `net_*.png` and the `lobby_*.png` set were
## drawn for this screen in [P8] and have been committed and referenced by nothing since
## 2026-08-30 -- see AGENT_GAME_CODER §7's list of unused chrome.
## ⚠️ **THE WIDTHS HAVE TO ADD UP TO LESS THAN THE PAGE, AND THAT IS ARITHMETIC RATHER
## THAN TASTE.** `HudPanel` gives a page `MARGIN_H` (120) off each edge and
## `CONTENT_MARGIN` (24) inside the border, so at 1152 the content is 864 px wide. These
## six plus their five separations come to 840. The first version came to 910 and the
## PING column hung over the frame's right-hand edge — visible in the very first
## screenshot, invisible to every assertion.
const COLUMNS := [
	{"title": "HOST", "width": 210.0, "icon": &"net_host"},
	{"title": "MAP", "width": 160.0, "icon": &"lobby_mapsize"},
	{"title": "VICTORY", "width": 160.0, "icon": &"lobby_victory"},
	# "SLOTS", not "PLAYERS", and it is the shorter word that made the header legible:
	# at 90 px less an icon, "PLAYERS" ran straight into the next column's heading with
	# no gap at all. It is also the more accurate of the two -- the cell reads "2 / 4",
	# which is chairs taken out of chairs, not a headcount.
	{"title": "SLOTS", "width": 90.0, "icon": &"lobby_team"},
	{"title": "AGE", "width": 110.0, "icon": &""},
	{"title": "PING", "width": 70.0, "icon": &""},
]

## Three rows of what a found host looks like. **NOT DATA AND NEVER TO BECOME DATA** --
## when discovery lands, this constant is deleted and the rows are built from beacons.
## It is here so the page can be reviewed by screenshot, which is how this project's UI
## is reviewed, and every value in it is one the beacon can actually carry (see the
## header's item 2). The addresses are RFC 5737 documentation addresses on purpose, so
## nobody can mistake one for somebody's real machine.
const SAMPLE_ROWS := [
	["Herman's table  192.0.2.11", "Forest 128×128", "Last Man Standing", "2 / 4",
			"I. Age of Ash", "4 ms"],
	["Kitchen phone  192.0.2.24", "Archipelago 160×160", "Last Man Standing", "3 / 4",
			"II. Ember", "11 ms"],
	["Study desktop  192.0.2.7", "River 96×96", "Last Man Standing", "1 / 2",
			"I. Age of Ash", "6 ms"],
]

const _ROW_HEIGHT := 38.0
const _ICON_PX := 20.0

## The list itself, held so the day a beacon arrives has one place to put it.
var _rows: VBoxContainer
var _refresh_button: Button
var _join_button: Button
var _filter_button: CheckButton


func _init() -> void:
	# The chrome, and it is not optional -- see `HudPanel._init`.
	super()
	set_title("SERVER BROWSER")

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	body.add_child(column)

	# WHAT THIS PAGE IS, first thing on it. In a VBox, which `note_label`'s own docstring
	# insists on: a wrapping Label in an HBox with nothing setting its width collapses to
	# one character per line, and it has shipped into a render twice.
	column.add_child(HudPanel.note_label(
			"Wireframe — this build does not discover anything yet. "
			+ "To reach a host now, type its address into the Join field on the lobby's "
			+ "bottom row. See this page's script for what a real one needs.", 15))

	# A FILTER TOGGLE RATHER THAN A BUTTON, the chat page's rule: a disabled control has
	# to be able to show its STATE, and a greyed-out Button cannot say whether the thing
	# it toggles is on. There is exactly one filter worth having and it is this one -- a
	# browser whose list is mostly full lobbies is a browser you scroll past.
	_filter_button = CheckButton.new()
	_filter_button.text = "Only servers with a free slot"
	_filter_button.button_pressed = true
	_filter_button.disabled = true
	_filter_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var filter_row := HBoxContainer.new()
	filter_row.add_theme_constant_override("separation", 8)
	var filter_icon := _icon(&"net_filter")
	if filter_icon != null:
		filter_row.add_child(filter_icon)
	filter_row.add_child(_filter_button)
	column.add_child(filter_row)

	column.add_child(_build_header())

	# ⚠️ **THE LIST SCROLLS AND THAT IS NOT OPTIONAL**, for the reason the lobby's setup
	# column does: a `VBoxContainer` does not clip or compress past its children's
	# minimums, it OVERFLOWS -- silently, off the bottom of the page. The row count here
	# is whatever the network hands over, which is the definition of user-controlled.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Sideways scrolling would let a column slide off the right edge where nothing says
	# it exists. The table is narrower than the page it is on; if it ever is not, the
	# columns shrink.
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 4)
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows)

	# SAID ABOVE THE SAMPLE, not below it. A reader who has already taken the rows for
	# real does not go looking for a disclaimer afterwards.
	_rows.add_child(HudPanel.note_label(
			"↓ layout sample — these three are not real servers ↓", 13))
	for sample in SAMPLE_ROWS:
		_rows.add_child(_build_row(sample))

	_refresh_button = add_button("REFRESH", Callable())
	_refresh_button.disabled = true
	var refresh_icon := _icon(&"net_refresh")
	if refresh_icon != null:
		_refresh_button.icon = refresh_icon.texture
	_join_button = add_button("JOIN", Callable())
	_join_button.disabled = true
	var join_icon := _icon(&"net_join")
	if join_icon != null:
		_join_button.icon = join_icon.texture
	add_close_button()


## The column headings, laid out by `COLUMNS` exactly as every row below is.
func _build_header() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	for spec in COLUMNS:
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 6)
		cell.custom_minimum_size = Vector2(float(spec["width"]), 0.0)
		var icon := _icon(spec["icon"] as StringName)
		# The two columns with no icon give the whole cell to their heading, and a column
		# whose art is missing does too -- `_icon` returns null rather than a placeholder,
		# the "leave it out rather than fake it" convention this directory follows.
		var spent := 0.0 if icon == null else _ICON_PX + 6.0
		if icon != null:
			cell.add_child(icon)
		var label := HudPanel.text_label(String(spec["title"]), 14)
		# AUTOWRAP OFF, explicitly. `text_label` does not wrap, but every heading here is
		# one word in a fixed-width box in a ROW, which is precisely the arrangement
		# `note_label` warns about -- and the next person to reach for `note_label` for
		# a dimmer heading would find out the hard way.
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		# ⚠️ **`clip_text` TAKES A LABEL'S MINIMUM WIDTH TO ZERO**, which is the whole
		# point of it and is also how the first version of this header came out as a row
		# of icons with no words at all: the CELL carried the width and the label inside
		# it, free to be zero, obligingly was. Every clipped label in this file therefore
		# carries its own minimum. The sample rows had one from the start and rendered
		# correctly, which is exactly why the fault looked like a missing header rather
		# than a layout rule.
		label.custom_minimum_size = Vector2(float(spec["width"]) - spent, 0.0)
		label.clip_text = true
		cell.add_child(label)
		row.add_child(cell)
	return row


## One server, as the table will draw it.
##
## A `Button` rather than a panel of labels, and DISABLED rather than merely inert: a
## row is what you press to pick a server, so the wireframe should show a row-shaped
## target -- and a target that answers a press by doing nothing is the failure this
## whole page's header is about. Disabled, it is visibly not ready, and the day beacons
## arrive the only change is dropping the flag and giving it a `ButtonGroup`.
##
## The labels are children of the button, which Godot draws over it happily; each is
## `MOUSE_FILTER_IGNORE` so the press lands on the row and not on a word.
func _build_row(values: Array) -> Control:
	var button := Button.new()
	button.disabled = true
	button.toggle_mode = true
	button.custom_minimum_size = Vector2(0.0, _ROW_HEIGHT)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var cells := HBoxContainer.new()
	cells.add_theme_constant_override("separation", 8)
	cells.set_anchors_preset(Control.PRESET_FULL_RECT)
	cells.offset_left = 10.0
	cells.offset_right = -10.0
	cells.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(cells)

	for i in range(COLUMNS.size()):
		var label := HudPanel.text_label(
				String(values[i]) if i < values.size() else "", 14)
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.clip_text = true
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.custom_minimum_size = Vector2(float(COLUMNS[i]["width"]), 0.0)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cells.add_child(label)
	return button


## How many rows the list is showing, sample or otherwise. For the test and the preview,
## which cannot ask a `VBoxContainer` a question this simple without counting the note
## label in with them.
func row_count() -> int:
	var n := 0
	for child in _rows.get_children():
		if child is Button:
			n += 1
	return n


func refresh_button() -> Button:
	return _refresh_button


func join_button() -> Button:
	return _join_button


## An icon by name, or null when the art is not there -- the "leave it out rather than
## fake it" convention every optional asset load in this directory follows.
static func _icon(name: StringName) -> TextureRect:
	if name == &"":
		return null
	var path := "res://assets/ui/icons/%s.png" % name
	if not ResourceLoader.exists(path):
		return null
	var icon := TextureRect.new()
	icon.texture = load(path)
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# Without this the pack's own 100x100 becomes the control's minimum size whatever is
	# asked for below -- the bug that ballooned `ResourceHUD` off the bottom of the
	# viewport, and the reason `HudPanel.resource_icon` carries the same line.
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.custom_minimum_size = Vector2(_ICON_PX, _ICON_PX)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon
