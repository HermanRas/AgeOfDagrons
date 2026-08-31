## THE SERVER BROWSER. **LIVE SINCE 2026-08-31** (project owner: *"we built out the
## wireframe for server browser, lets wire it up and make it live"*), having been a
## labelled wireframe for about a day. PLAN.md 12.1's open end, closed.
##
## It finds hosts on this network and joins one. `LanBrowser` is the socket and the
## rolling window; this is the table, the selection and the two decisions -- and it holds
## no copy of what a host is, so the day a beacon carries another field there is one
## place that knows how to draw it.
##
## ── WHAT THE WIREFRAME PROMISED, AND WHICH PART EACH PROMISE LANDED IN ──────
##
##   1. **A discovery transport, and LAN is the whole of v1.** `LanBeacon` -- a UDP
##      datagram at the broadcast address on `Net.PORT + 1`, once a second. No master
##      server, and the header of that file argues why there must not quietly become one.
##   2. **A payload that is a subset of `MatchConfig`.** `LanBeacon.payload_for`. The one
##      genuinely new field is `MatchConfig.host_name`, and it is a lobby setting in GAME
##      SETUP -- because a browser listing four IP addresses is a browser nobody can
##      choose from.
##   3. **A join that is the EXISTING join.** This page emits `join_requested`;
##      `SkirmishScreen` fills its own Join field and calls `_on_join_pressed`. There is
##      no second path into `Net.join`, so the failure cases the lobby already handles --
##      already in a session, a refused socket, the missing Android INTERNET permission --
##      are handled once.
##   4. **A refresh that is honest about time.** A host stays listed for
##      `LanBeacon.WINDOW_MSEC` after its last beacon and REFRESH starts that window
##      again rather than clearing the list. See `LanBrowser.restart`.
##
## ⚠️ **THE ONE THING THAT WAS GOING TO BITE, AND DID NOT.** `Net.has_session()` is true
## for a host the moment a slot is opened, and this page is reached FROM that screen -- so
## a host pressing JOIN would be dialling out of a session it is already running. The
## lobby's join answers that with *"already in a session -- go Back to leave it"*, which
## is right and arrives two taps too late. JOIN is greyed here instead, with `_note`
## saying which of the four reasons it is greyed for. **A disabled button that does not
## say why is the failure this whole page's history is about**, so there is no state in
## which JOIN is dead and the page is silent.
##
## ⚠️ **EVERY STRING IN A ROW WAS WRITTEN BY A STRANGER ON THE NETWORK.** They are capped
## and stripped in `LanBeacon._clean` before they reach here, and the address a press
## dials is the transport's `get_packet_ip()` rather than anything in the payload. Nothing
## on this page acts on a beacon; it displays one, and the player decides.
class_name ServerBrowserPanel
extends HudPanel

## A row was pressed and JOIN with it: dial this host. `SkirmishScreen` is the only
## listener and it routes straight into its own Join field -- see item 3 above.
signal join_requested(address: String, port: int)

## The columns, in order, with the width each needs and the icon that heads it.
##
## WIDTHS ARE PER COLUMN AND SHARED BY EVERY ROW, which is what makes this a table
## rather than a stack of unrelated lines -- the header and the rows are laid out by the
## same list, so a column cannot drift between them. A `GridContainer` was the
## alternative and was dropped for one reason: a row has to be PRESSABLE, and a grid's
## cells are separate controls with nothing to press.
##
## `icon` is a name under `assets/ui/icons/`, or `&""` for a column whose heading is
## short enough to speak for itself. All four `net_*.png` and the `lobby_*.png` set were
## drawn for this screen in [P8] and had been committed and referenced by nothing since
## 2026-08-30.
##
## ⚠️ **THE WIDTHS HAVE TO ADD UP TO LESS THAN THE PAGE, AND THAT IS ARITHMETIC RATHER
## THAN TASTE.** `HudPanel` gives a page `MARGIN_H` (120) off each edge and
## `CONTENT_MARGIN` (24) inside the border, so at 1152 the content is 864 px wide. These
## six plus their five separations come to 840. The first version came to 910 and the
## last column hung over the frame's right-hand edge — visible in the very first
## screenshot, invisible to every assertion.
##
## ⚠️ **THE LAST COLUMN IS "SEEN", AND IT USED TO SAY "PING".** A beacon is a one-way
## datagram: there is no round trip to time, so a latency figure here would have to be
## invented, on a page whose entire history is about not inventing things. Seconds since
## the last beacon is a real number, it is the number the rolling window turns on, and it
## answers the question a ping column is actually asked -- *is this host still there*.
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
	{"title": "SEEN", "width": 70.0, "icon": &""},
]

const _ROW_HEIGHT := 38.0
const _ICON_PX := 20.0

## The list itself, and the one note under it that says why JOIN is off.
var _rows: VBoxContainer
var _empty_note: Label
var _note: Label
var _refresh_button: Button
var _join_button: Button
var _filter_button: CheckButton

## The socket and the window. A child so it is freed with the page and so `_process`
## reaches it; it is only listening while the page is open (see `open`/`close`), because
## a browser bound to the port while nobody is looking at it is a browser stopping the
## next process from binding for no reason at all.
var _browser: LanBrowser

## Which port to listen on. `LanBeacon.PORT` in the game, always -- settable for
## `SkirmishScreen.host_port`'s reason: this binds a REAL socket, faking it would test the
## fake, and a suite holding the game's own port fights the game the owner has open on the
## same machine. Ten lobby tests went red exactly that way once already.
var discovery_port := LanBeacon.PORT

## WHICH HOST IS PICKED, HELD AS AN ORIGIN AND NOT AS A ROW. The rows are rebuilt
## whenever the set of hosts changes, so a held Button is a Button that gets freed under
## the finger that pressed it -- the same trap `SkirmishScreen._colour_picker` records
## about a picker owned by a slot row.
var _selected := ""

## origin -> its row button, so a rebuild can put the tick back where it was.
var _row_buttons: Dictionary = {}
var _row_group := ButtonGroup.new()

## What was on screen last frame, so SEEN can tick without the table being rebuilt.
var _seen_labels: Dictionary = {}          # origin -> Label


func _init() -> void:
	# The chrome, and it is not optional -- see `HudPanel._init`.
	super()
	set_title("SERVER BROWSER")

	_browser = LanBrowser.new()
	_browser.changed.connect(_rebuild_rows)
	add_child(_browser)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	body.add_child(column)

	# WHAT THIS PAGE IS, first thing on it. In a VBox, which `note_label`'s own docstring
	# insists on: a wrapping Label in an HBox with nothing setting its width collapses to
	# one character per line, and it has shipped into a render twice.
	column.add_child(HudPanel.note_label(
			"Hosts on this network announce themselves once a second. A host stays "
			+ "listed for a few seconds after its last announcement, so a lost packet "
			+ "does not blink a row out. Nothing leaves this network — there is no "
			+ "master server.", 15))

	# A FILTER TOGGLE RATHER THAN A BUTTON, the chat page's rule: a control has to be able
	# to show its STATE, and a Button cannot say whether the thing it toggles is on. There
	# is exactly one filter worth having and it is this one -- a browser whose list is
	# mostly full lobbies is a browser you scroll past.
	_filter_button = CheckButton.new()
	_filter_button.text = "Only servers with a free slot"
	_filter_button.button_pressed = true
	_filter_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_filter_button.toggled.connect(_on_filter_toggled)
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

	# THE EMPTY STATE IS A REAL STATE AND MOST OF THE TIME IT IS THE ONLY ONE. A blank
	# panel is indistinguishable from a broken one, and "there are no hosts" and "this
	# device never opened a socket" want completely different things done about them --
	# see `_note_text`, which distinguishes them.
	_empty_note = HudPanel.note_label("", 15)
	_rows.add_child(_empty_note)

	# WHY JOIN IS OFF, under the list rather than beside the button. There are four
	# reasons and three of them are about this device rather than about the selection, so
	# a tooltip on the button would be the wrong place -- it is only read by somebody who
	# has already decided the button is broken.
	_note = HudPanel.note_label("", 14)
	column.add_child(_note)

	_refresh_button = add_button("REFRESH", _on_refresh_pressed)
	var refresh_icon := _icon(&"net_refresh")
	if refresh_icon != null:
		_refresh_button.icon = refresh_icon.texture
	_join_button = add_button("JOIN", _on_join_pressed)
	var join_icon := _icon(&"net_join")
	if join_icon != null:
		_join_button.icon = join_icon.texture
	add_close_button()

	_rebuild_rows()
	set_process(false)


## THE SOCKET'S LIFE IS THE PAGE'S LIFE. Bound on open and closed on close, rather than
## held for as long as the lobby exists: the port is a machine-wide resource and a second
## copy of the game cannot have it, so a browser nobody is looking at is a browser
## costing somebody else their discovery. See `LanBrowser.listen` on why that failure is
## the expected one rather than an exotic one.
func open() -> void:
	super()
	_browser.listen(discovery_port)
	_browser.poll()
	_rebuild_rows()
	set_process(true)


func close() -> void:
	set_process(false)
	_browser.stop()
	super()


## The seconds column, and the JOIN gate, once a frame.
##
## SEPARATE FROM THE REBUILD ON PURPOSE. `LanBrowser.changed` fires when the SET of hosts
## or their settings change, which is rarely; SEEN ticks every second on every row and a
## table rebuilt once a second is a table whose selected row is freed under a thumb
## travelling towards it. So the structure is rebuilt on news and the one live number is
## written in place.
func _process(_delta: float) -> void:
	for origin in _seen_labels:
		var row := _row_for(String(origin))
		if not row.is_empty():
			(_seen_labels[origin] as Label).text = _seen_text(row)
	_refresh_join()


## The list, from whatever the browser is holding right now.
func _rebuild_rows() -> void:
	for child in _rows.get_children():
		if child == _empty_note:
			continue
		_rows.remove_child(child)
		child.queue_free()
	_row_buttons.clear()
	_seen_labels.clear()

	var found := _visible_hosts()
	# A SELECTION THAT WALKED OFF THE NETWORK IS NOT A SELECTION. Dropped rather than
	# kept, because JOIN reads `_selected` to find an address and a host that has gone
	# quiet has no address worth dialling -- and a tick left on a row nobody can see is
	# the state where JOIN is enabled and does nothing.
	var still_here := false
	for row in found:
		if String(row["origin"]) == _selected:
			still_here = true
	if not still_here:
		_selected = ""

	for row in found:
		var button := _build_row(row)
		_rows.add_child(button)
		_row_buttons[row["origin"]] = button

	_empty_note.visible = found.is_empty()
	_empty_note.text = _empty_text()
	_refresh_join()


## Everything the browser has, less anything the filter is hiding.
func _visible_hosts() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row in _browser.hosts():
		# A HOST WITH NO FREE CHAIR CANNOT BE JOINED, so hiding it is hiding a row that
		# would only ever be a disappointment. It is a toggle rather than a rule because a
		# player waiting for a friend to close a slot wants to watch that lobby fill.
		if _filter_button.button_pressed and int(row["taken"]) >= int(row["slots"]):
			continue
		out.append(row)
	return out


## One host by origin, or {} if it has gone quiet since it was drawn. Straight to
## `LanBrowser.host`, which is a dictionary lookup -- this is called once per row per
## frame and `hosts()` sorts and duplicates the whole table on every call.
func _row_for(origin: String) -> Dictionary:
	return _browser.host(origin)


# ── the table ───────────────────────────────────────────────────────────────

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
		if String(spec["title"]) == "SEEN":
			# The one heading a player cannot guess, so it says what it is. There is no
			# room on its face -- see `COLUMNS` on why this column is not a ping.
			cell.tooltip_text = "Seconds since this host last announced itself"
		row.add_child(cell)
	return row


## One found server, as a pressable row.
##
## A `Button` rather than a panel of labels, because a row is what you press to pick a
## server. In a `ButtonGroup` with `toggle_mode`, so exactly one is ever ticked and
## Godot does the un-ticking; the press handler only has to remember which.
##
## The labels are children of the button, which Godot draws over it happily; each is
## `MOUSE_FILTER_IGNORE` so the press lands on the row and not on a word.
func _build_row(row: Dictionary) -> Control:
	var button := Button.new()
	button.toggle_mode = true
	button.button_group = _row_group
	button.button_pressed = String(row["origin"]) == _selected
	button.custom_minimum_size = Vector2(0.0, _ROW_HEIGHT)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(_on_row_pressed.bind(String(row["origin"])))
	# The address is not in any column -- the HOST cell shows the name -- and it is the
	# thing a player wants to check before dialling somebody's machine.
	button.tooltip_text = "%s:%d" % [row["address"], row["port"]]

	var cells := HBoxContainer.new()
	cells.add_theme_constant_override("separation", 8)
	cells.set_anchors_preset(Control.PRESET_FULL_RECT)
	cells.offset_left = 10.0
	cells.offset_right = -10.0
	cells.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(cells)

	var values := _cells_for(row)
	for i in range(COLUMNS.size()):
		var label := HudPanel.text_label(values[i], 14)
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.clip_text = true
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.custom_minimum_size = Vector2(float(COLUMNS[i]["width"]), 0.0)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cells.add_child(label)
		if String(COLUMNS[i]["title"]) == "SEEN":
			# Held so `_process` can rewrite this one number without rebuilding the row.
			_seen_labels[String(row["origin"])] = label
	return button


## One beacon rendered into the six columns.
##
## ⚠️ **THE IDS ARE RESOLVED HERE, WITH THIS BUILD'S OWN TABLES.** `LanBeacon` sends the
## integers `MatchConfig` holds and this asks `MapGenerator`, `MatchConfig` and
## `GameDataRegistry` what they are called -- so a host cannot put arbitrary text in
## somebody's table, and a value from a newer build lands on the same fallback name every
## other unknown does rather than on a blank cell.
func _cells_for(row: Dictionary) -> Array[String]:
	var size := row["size"] as Vector2i
	# THE ADDRESS ALONE WHEN THERE IS NO NAME, which is what a host was called before
	# `MatchConfig.host_name` existed and is what an older build still looks like.
	var who := String(row["name"])
	who = String(row["address"]) if who.is_empty() \
			else "%s  %s" % [who, row["address"]]
	return [
		who,
		"%s %d×%d" % [MapGenerator.type_name(int(row["map"]) as MapGenerator.Type),
				size.x, size.y],
		MatchConfig.mode_name(int(row["mode"]) as MatchConfig.Mode),
		"%d / %d" % [row["taken"], row["slots"]],
		GameDataRegistry.age_label(int(row["age"])) if GameDataRegistry != null \
				else "Age %d" % int(row["age"]),
		_seen_text(row),
	]


## "now" for a beacon that has just landed, seconds otherwise. Worded rather than left as
## "0s" because zero seconds ago reads as a missing value, and this is the column a
## player checks to decide whether a host is still there.
func _seen_text(row: Dictionary) -> String:
	var seconds := _browser.seconds_since(row)
	return "now" if seconds <= 0 else "%d s" % seconds


# ── the two decisions ───────────────────────────────────────────────────────

func _on_row_pressed(origin: String) -> void:
	_selected = origin
	_refresh_join()


func _on_filter_toggled(_on: bool) -> void:
	_rebuild_rows()


func _on_refresh_pressed() -> void:
	# NOT A CLEAR. See `LanBrowser.restart` -- it re-opens the socket, which is the only
	# way back from a bind that lost to another copy of the game, and starts the window
	# again over what is already listed.
	_browser.restart()
	_browser.poll()
	_rebuild_rows()


## THE EXISTING JOIN, REACHED THE EXISTING WAY. This emits and stops; `SkirmishScreen`
## puts the address in its own field and presses its own button, so every failure the
## lobby already knows how to report is reported once, in the place that reports it.
func _on_join_pressed() -> void:
	var row := _row_for(_selected)
	if row.is_empty():
		return
	join_requested.emit(String(row["address"]), int(row["port"]))


## JOIN's state and the sentence explaining it.
##
## ⚠️ **TWO QUESTIONS, NOT ONE, AND THE FIRST VERSION ASKED ONLY THE SECOND.** It set
## `disabled` from "is there a sentence to print", which is wrong in exactly the state the
## page spends most of its life in: an empty list needs no sentence -- the list says so
## itself, in its own words, in the middle of the page -- so JOIN came out ENABLED with
## nothing to join. A control's reason for being off and its being off are separate facts
## and only one of them is always expressible.
func _refresh_join() -> void:
	var why := _note_text()
	# A PICKED HOST THAT IS STILL THERE. `_row_for` asks the browser rather than reading
	# the list, so a row that aged out of the window between the press and the frame is
	# not joinable -- which is the same instant `_rebuild_rows` drops the tick.
	_join_button.disabled = not why.is_empty() or _row_for(_selected).is_empty()
	_note.text = why


## Why JOIN is off, or "" when there is nothing worth saying. Note that "" does NOT mean
## JOIN is on -- see `_refresh_join`.
##
## Checked in the order the reasons matter: a device that is already hosting cannot join
## anything whatever it has picked, so telling it "pick a server" first would be advice
## that leads nowhere.
func _note_text() -> String:
	if Net.has_session():
		# ⚠️ THE ONE THE WIREFRAME'S HEADER PREDICTED. `Net.has_session()` is true for a
		# host the moment a slot is opened and this page is reached from that screen, so
		# without this the refusal arrives from the lobby's own join two taps later.
		return "This device is already in a session — go Back and leave it before " \
				+ "joining another host."
	if _browser.listen_error() != OK:
		return "Cannot listen on port %d: %s. Another copy of the game may have it. " \
				% [discovery_port, error_string(_browser.listen_error())] \
				+ "Press REFRESH to try again."
	# SILENT WHEN THERE IS NOTHING LISTED. The empty-state text in the middle of the page
	# is already saying what is going on at far greater length, and a second sentence
	# under it telling the player to pick one of no rows reads as a broken page.
	if _selected.is_empty() and not _visible_hosts().is_empty():
		return "Pick a server to join."
	return ""


## What the list says when it has nothing in it, which distinguishes the three ways that
## happens. A blank panel would be indistinguishable from a broken page.
func _empty_text() -> String:
	if _browser.listen_error() != OK:
		return "Not listening — see below."
	if _filter_button.button_pressed and not _browser.hosts().is_empty():
		return "Every host found is full. Untick the filter above to see them."
	return "Listening for hosts on this network… none yet. A host appears here a second "\
			+ "or so after it opens a slot in its lobby. If it never does, type its "\
			+ "address into the Join field on the lobby's bottom row instead."


# ── for the test and the preview ────────────────────────────────────────────

## How many hosts the list is showing. Counts BUTTONS, so the empty note is never
## mistaken for a row.
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


func filter_button() -> CheckButton:
	return _filter_button


func browser() -> LanBrowser:
	return _browser


## Which host is ticked, as its origin, or "" for none.
func selected() -> String:
	return _selected


## The sentence under the list. Exposed so a test asserts the REASON JOIN is off rather
## than only that it is off -- the two came apart once already on this page, when a
## disabled control said nothing about itself.
func note_text() -> String:
	return _note.text


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
