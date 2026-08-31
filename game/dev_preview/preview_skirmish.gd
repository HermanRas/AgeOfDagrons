## Dev check for the skirmish screen (PLAN.md 1.6): photograph the real screen, then
## start a real match from the config it built and photograph THAT.
##
## The second half is the point. A settings screen that looks right and hands the match
## a different map than it previewed is the worst failure available here, and it is
## invisible from either picture alone -- so this prints what the running world actually
## contains and compares it against what the screen was showing.
##
## Instantiates `Game.tscn` directly rather than letting the screen's own START call
## `change_scene_to_file()`, because that would replace THIS scene and take the preview
## with it. The config path -- `Net.pending_match`, consumed by `host_solo()` -- is
## exercised exactly as the button does it; only the scene swap is done by hand.
##
## Usage:
##   Godot --path game res://dev_preview/preview_skirmish.tscn
##       -- writes user://skirmish_screen.png and user://skirmish_match.png.
extends Node

const SHOT_DIR := "user://"
const SETTLE_FRAMES := 30
const MATCH_FRAMES := 45

## Frames to let the UI redraw between changing a lobby state and photographing it. A
## shot taken on the same frame as the change catches the screen as it was before.
const LOBBY_FRAMES := 10

var _screen: SkirmishScreen = null
var _game: Node = null
var _frames := 0
var _step := 0
var _resume_at := 0
var _expected: MapData = null


func _ready() -> void:
	_screen = load("res://scenes/menu/Skirmish.tscn").instantiate()
	add_child(_screen)


func _process(_delta: float) -> void:
	_frames += 1
	if _frames < _resume_at:
		return
	match _step:
		0:
			if _frames < SETTLE_FRAMES:
				return
			_report_screen()
			_report_footer()
			_report_columns()
			_report_headings()
			_shoot("skirmish_screen")
		1:
			# EIGHT SLOTS, SIX CLOSED: two players on a board with eight players' worth of
			# room. The picker chooses the ROOM; the roles choose who is in it.
			_pick_slots(8)
		2:
			_report_slots()
			_shoot("skirmish_eight_slots")
		3:
			_pick_slots(2)
		4:
			# THE TECH TREE OVER THE LOBBY (project owner, 2026-08-30: *"TechTree (same
			# panel from minimap buttin ingame)"*). Pressed through the real nav button,
			# because "the panel opens" proves nothing about whether the button reaches it
			# -- the failure this project keeps meeting is a control wired to nothing that
			# draws exactly like one that works.
			_open_the_tech_tree()
		5:
			_report_tech_tree()
			_shoot("skirmish_tech_tree")
		6:
			_screen._tech_tree.close()
		7:
			# THE SERVER BROWSER (project owner, 2026-08-31). Through the real nav button
			# for the tech tree's reason -- and this one especially, since the button spent
			# most of its life disabled and "it is enabled now" is exactly the kind of
			# change that gets made without connecting anything to it.
			_screen._browser_button.pressed.emit()
			_hold(LOBBY_FRAMES)
		8:
			# THREE REAL BEACONS DOWN A REAL SOCKET. See `_send_sample_beacons` -- these
			# are not fixture rows, they are datagrams the page's own listener decodes,
			# and the picture is worthless without them: an empty table shows nothing
			# about the shape of a table, which is the whole thing being reviewed.
			_send_sample_beacons()
			_hold(LOBBY_FRAMES)
		9:
			_report_browser()
			_shoot("skirmish_server_browser")
		10:
			_screen._browser.close()
		11:
			# A 2v2, set through the real dropdowns. The picture is the point: four rows
			# each carrying a swatch and a one-character team box, in a column that is now
			# half the screen rather than a third.
			_make_it_two_v_two()
		12:
			_report_teams()
			# AT FOUR PLAYERS, not at two, and that is the whole reason both are measured
			# here as well: the chat's minimum width grows one tab per player, so the
			# split is only in danger once somebody has filled the lobby -- and the slot
			# grid is rebuilt from scratch on every count change, which is exactly when a
			# heading could come back in the wrong column or not at all.
			_report_columns()
			_report_headings()
			_shoot("skirmish_teams")
		13:
			_pick_slots(2)
		14:
			# THE COLOUR PICKER (2026-08-21), which replaced a cycle. Pressed through the
			# slot row's real Button, because what is in doubt is that a press on that row
			# opens the grid -- the handler on its own would pass with the button unwired.
			_open_the_colour_picker()
		15:
			_report_colour_picker()
			_shoot("skirmish_colour_picker")
		16:
			_pick_a_colour()
		17:
			_report_colours()
			_shoot("skirmish_colour_picked")
		18:
			# THE LOBBY (12.1c). Setting a slot to Open is what opens the socket, so this
			# is the hosting path and not a simulation of it.
			_open_a_slot()
		19:
			_report_lobby()
			# AND THE BEACON IT NOW PUTS ON THE WIRE. Opening a slot is what starts
			# advertising -- one act, as it is one act to open the socket -- so a lobby
			# waiting for somebody is exactly the state that has to be findable.
			_report_beacon()
			_shoot("skirmish_lobby_waiting")
		20:
			# A peer arriving. The connection itself is (g)'s ground already proven on two
			# devices; what is unproven is that this SCREEN shows the chair being taken
			# and lets START go ahead once it is.
			_screen._on_peer_joined(7777)
			_hold(LOBBY_FRAMES)
		21:
			_report_lobby()
			# THE CHAIR COUNT ON THE WIRE FOLLOWED THE CHAIR. `SLOTS` is what a browser
			# reads to decide whether a lobby is worth pressing, and it is derived in
			# `_refresh_beacon` -- so a peer arriving and the beacon still saying "1 / 2"
			# would be a full lobby advertising a free seat.
			_report_beacon()
			_shoot("skirmish_lobby_filled")
		22:
			# The JOINING device's view of the same screen -- the one state that cannot be
			# reached from here honestly, since a real one needs a second process dialling
			# in. FORCED, and labelled as forced: what it is worth is the LOOK of a screen
			# that configures nothing, which no test can judge. The control states
			# themselves are asserted in test_skirmish_screen.
			_join_someone_elses_match()
		23:
			_shoot("skirmish_lobby_joined")
		24:
			Net._lobby_config = null
			_screen._lobby = SkirmishScreen.Lobby.HOSTING
			# Back to a plain skirmish, so the solo path below is exercised exactly as it
			# was before this screen learned to host -- the regression that would matter
			# most here is the one where adding multiplayer broke playing alone.
			_close_the_slot()
		25:
			# THE BEACON HAS TO HAVE STOPPED WITH THE SLOT. A row in somebody's browser for
			# a lobby that is not listening is a row that fails when pressed, and this is
			# the cheapest place to notice it -- `_refresh_beacon` decides both ends.
			_report_beacon()
			_start_the_match()
		26:
			if _frames < SETTLE_FRAMES + MATCH_FRAMES:
				return
			_report_match()
			_shoot("skirmish_match")
		_:
			get_tree().quit()
			return
	_step += 1


## Hold the script for `frames` before the next step, so a UI change has actually been
## drawn by the time it is photographed.
func _hold(frames: int) -> void:
	_resume_at = _frames + frames


## WHERE EVERY FOOTER CONTROL ACTUALLY ENDS UP, in screen pixels.
##
## The owner asked for one row (*"half the size of the buttons so they fit in 1 row"*),
## and "fits" is a claim about pixels that a screenshot answers badly: a button whose
## last few pixels are off the edge looks very nearly like one that is not. This prints
## the rects and warns on anything past the viewport, so the answer is measured.
## ⚠️ **WHERE THE TWO COLUMNS ACTUALLY END UP, WHICH IS NOT WHAT THE STRETCH RATIOS SAY.**
##
## `_CHAT_STRETCH` and `_SETUP_STRETCH` are both 1.0 as of 2026-08-31, and a ratio only
## divides the space LEFT OVER after every child's minimum is honoured — so a column
## whose contents have a big minimum takes more than its share and the other one gets
## less than its own minimum and OVERFLOWS. That is not hypothetical: four chat tabs at
## `ChatBoard._TAB_MIN` made the CHAT column 670 px of a 1104 px body and ran the setup
## panels off the right-hand edge of the screen. Printed and warned about rather than
## eyeballed, because "half" is a claim about pixels.
func _report_columns() -> void:
	var edge := float(get_viewport().get_visible_rect().size.x)
	var c := _screen._chat_column.get_global_rect()
	var s := _screen._setup_column.get_global_rect()
	print("columns: chat %.0f..%.0f (%.0f wide), setup %.0f..%.0f (%.0f wide)"
			% [c.position.x, c.end.x, c.size.x, s.position.x, s.end.x, s.size.x])
	var share := c.size.x / maxf(1.0, c.size.x + s.size.x)
	print("    chat takes %.0f%% of the body (the owner asked for 50)" % (share * 100.0))
	# THE PANELS INSIDE THE COLUMN, not just the column. A `ScrollContainer` whose child
	# has a bigger minimum than it does draws that child past its own edge, so the column
	# can be exactly half the screen while the plates in it hang over the bezel -- which
	# is precisely what four chat tabs did on the first 50/50 render.
	for panel in _panels_in(_screen._setup_column):
		var r := panel.get_global_rect()
		if r.end.x > edge:
			push_warning("preview_skirmish: a setup panel runs %.0f px off the right edge"
					% (r.end.x - edge))
	if absf(share - 0.5) > 0.02:
		push_warning("preview_skirmish: the split is %.0f/%.0f, not half and half"
				% [share * 100.0, (1.0 - share) * 100.0])


func _panels_in(node: Node) -> Array[PanelContainer]:
	var out: Array[PanelContainer] = []
	for child in node.get_children():
		if child is PanelContainer:
			out.append(child)
		out.append_array(_panels_in(child))
	return out


## ⚠️ **ARE THE COLUMN HEADINGS ACTUALLY OVER THEIR COLUMNS** (project owner,
## 2026-08-31: *"column labels are miss aligned"*).
##
## The first heading row mirrored `_build_slot_row`'s widths by reading the same three
## constants, and its own comment claimed that was enough. It was not: two rows built
## from identical minimums still part company when their TOTALS differ, because the one
## expanding child absorbs the difference. **It looked right in the code and wrong on the
## screen, and nothing but a screenshot said so** -- so the check is a measurement now.
## `_slot_box` is a `GridContainer` and the columns are shared by construction, which is
## the real fix; this is what would catch it going back.
func _report_headings() -> void:
	var grid := _screen._slot_box
	var titles := ["COLOUR", "TEAM", "TYPE"]
	var keys := ["colour", "team", "role"]
	for i in range(titles.size()):
		var heading: Label = null
		for child in grid.get_children():
			if child is Label and (child as Label).text == titles[i]:
				heading = child
				break
		if heading == null:
			push_warning("preview_skirmish: no %s heading on the slot grid" % titles[i])
			continue
		var control: Control = _screen._slot_rows[0][keys[i]]
		var h := heading.get_global_rect()
		var c := control.get_global_rect()
		var drift := (h.position.x + h.size.x * 0.5) - (c.position.x + c.size.x * 0.5)
		print("    heading %-7s centre %.0f, control centre %.0f, drift %.0f px"
				% [titles[i], h.position.x + h.size.x * 0.5,
				c.position.x + c.size.x * 0.5, drift])
		# A pixel or two is rounding in a container; anything a reader would notice is a
		# heading over the wrong column.
		if absf(drift) > 3.0:
			push_warning("preview_skirmish: the %s heading is %.0f px off its column"
					% [titles[i], drift])


func _report_footer() -> void:
	var edge := float(get_viewport().get_visible_rect().size.x)
	var controls: Array = [
		["join field", _screen._join_field], ["JOIN", _screen._join_button],
		["browser", _screen._browser_button], ["tech tree", _screen._tech_button],
		["START", _screen._start_button], ["BACK", _screen._back_button],
	]
	for entry in controls:
		var c: Control = entry[1]
		var rect := c.get_global_rect()
		print("  footer %-11s x %.0f..%.0f  y %.0f..%.0f"
				% [entry[0], rect.position.x, rect.end.x, rect.position.y, rect.end.y])
		if rect.end.x > edge:
			push_warning("preview_skirmish: %s runs %.0f px off the right edge"
					% [entry[0], rect.end.x - edge])


## Press the nav strip's real TECH TREE button, for `_pick_role`'s reason: calling
## `_on_tech_tree_pressed` directly would pass just as happily with the button connected
## to nothing, which is the failure this project keeps finding.
func _open_the_tech_tree() -> void:
	_screen._tech_button.pressed.emit()


## What the tree came up showing. Printed as well as photographed because the AGE is the
## whole reason this button is on the lobby and not just a copy of the in-game one: it
## should be the age the match would OPEN in, so the picker two panels up has somewhere
## to be checked against.
func _report_tech_tree() -> void:
	var tree: TechTreePanel = _screen._tech_tree
	print("tech tree: open %s, age %d, researched %d"
			% [tree.is_open(), tree._age, tree._researched.size()])
	if not tree.is_open():
		push_warning("preview_skirmish: the TECH TREE button did not open the panel")
	if tree._age != _screen._starting_age:
		push_warning("preview_skirmish: tree at age %d, lobby starts at age %d"
				% [tree._age, _screen._starting_age])


## THREE HOSTS, ANNOUNCED THE WAY A REAL ONE WOULD BE.
##
## ⚠️ **THESE ARE NOT FIXTURE ROWS AND THAT DISTINCTION IS THE WHOLE POINT.** The page has
## a real `LanBrowser` bound to a real socket; this opens a second socket and sends it
## three real datagrams, which it decodes with the same `LanBeacon.decode` a host on the
## next desk would go through. So the picture shows the table doing its job rather than a
## constant being drawn -- which is what the wireframe's `SAMPLE_ROWS` did, and what its
## own comment said had to be deleted the day discovery landed.
##
## THE ORIGINS ARE REWRITTEN, and that is the one thing here a real host would not do. A
## browser refuses its own process (`LanBrowser.include_self`), so a beacon carrying this
## process's origin would correctly be ignored -- and turning that rule off for the
## preview would be photographing a page with its safety catch off. Giving the three
## payloads other origins is the honest version: three strangers, one real rule.
##
## RFC 5737 documentation addresses, so nobody can mistake a row for somebody's machine.
func _send_sample_beacons() -> void:
	var socket := PacketPeerUDP.new()
	if socket.set_dest_address("127.0.0.1", LanBeacon.PORT) != OK:
		push_warning("preview_skirmish: could not aim the sample beacons")
		return
	var samples := [
		["Herman's table", MapGenerator.Type.FOREST, Vector2i(128, 128), 4, 2, 1],
		["Kitchen phone", MapGenerator.Type.ARCHIPELAGO, Vector2i(160, 160), 4, 3, 2],
		["Study desktop", MapGenerator.Type.RIVER, Vector2i(96, 96), 2, 2, 1],
	]
	for i in range(samples.size()):
		var s: Array = samples[i]
		socket.put_packet(LanBeacon.encode({
			"aod": LanBeacon.VERSION,
			"origin": "preview-%d" % i,
			"name": s[0], "map": int(s[1]),
			"w": (s[2] as Vector2i).x, "h": (s[2] as Vector2i).y,
			"mode": int(MatchConfig.Mode.LAST_MAN_STANDING),
			"age": s[5], "slots": s[3], "taken": s[4], "port": Net.PORT,
		}))
	socket.close()


## What came up behind the SERVERS button, and whether the network actually reached it.
##
## ⚠️ **AN EMPTY TABLE AND A DEAD SOCKET LOOK IDENTICAL IN A SCREENSHOT**, which is why
## the listening state and the bind error are printed rather than left to the picture --
## and why the page itself has an empty-state sentence distinguishing them. A run that
## finds nothing here is either a bug or another copy of the game holding port 27016, and
## the warning says which.
func _report_browser() -> void:
	var page: ServerBrowserPanel = _screen._browser
	var lan := page.browser()
	print("browser: open %s, listening %s (err %s), %d rows, join disabled %s"
			% [page.is_open(), lan.is_listening(), error_string(lan.listen_error()),
			page.row_count(), page.join_button().disabled])
	print("  note: %s" % ("(none)" if page.note_text().is_empty() else page.note_text()))
	for row in lan.hosts():
		print("  host %-16s %-16s %s %dx%d  %d/%d  age %d  seen %d s"
				% [row["name"], row["address"],
				MapGenerator.type_name(int(row["map"]) as MapGenerator.Type),
				(row["size"] as Vector2i).x, (row["size"] as Vector2i).y,
				row["taken"], row["slots"], row["age"], lan.seconds_since(row)])
	if not page.is_open():
		push_warning("preview_skirmish: the SERVERS button did not open the browser")
	if not lan.is_listening():
		push_warning("preview_skirmish: the browser never bound port %d (%s)"
				% [page.discovery_port, error_string(lan.listen_error())])
	elif page.row_count() == 0:
		push_warning("preview_skirmish: three beacons were sent and none was decoded")
	# THE FILTER HIDES A FULL LOBBY, and one of the three samples is full on purpose --
	# so a table showing all three is a filter that is not doing its job.
	if page.filter_button().button_pressed and page.row_count() != 2:
		push_warning("preview_skirmish: the free-slot filter passed %d of 3 rows, want 2"
				% page.row_count())


## What this device is putting on the wire, if anything.
##
## ⚠️ **THE STATE THAT MATTERS IS THE ONE WHERE IT SHOULD BE SILENT.** A beacon that
## outlives its advertised slot is a listing for a lobby nobody is listening on, and it is
## invisible from this machine -- the only place it shows up is somebody else's browser,
## pressing a row that fails. So both directions are warned about.
func _report_beacon() -> void:
	var hosting := _screen._lobby == SkirmishScreen.Lobby.HOSTING
	print("beacon: hosting %s, advertising %s, name \"%s\", %d of %d chairs taken"
			% [hosting, _screen._beacon.is_advertising(), _screen.host_name(),
			_screen.build_config().player_ids.size() - _screen.unfilled_slots(),
			_screen.build_config().player_ids.size()])
	if hosting != _screen._beacon.is_advertising():
		push_warning("preview_skirmish: hosting is %s and the beacon is %s"
				% [hosting, _screen._beacon.is_advertising()])


## Four slots, two a side, through the real dropdowns.
func _make_it_two_v_two() -> void:
	_pick_slots(4)
	for i in range(4):
		_pick_role(i, SkirmishScreen.Role.PLAYTEST_AI)
		var picker: OptionButton = _screen._slot_rows[i]["team"]
		var item := picker.get_item_index(1 if i < 2 else 2)
		picker.select(item)
		picker.item_selected.emit(item)
	_hold(LOBBY_FRAMES)


## THE SPLIT AND WHERE THE STARTS LANDED, because the second is the half a picture of a
## lobby cannot show. Allies are adjacent on the ring for free -- `_start_positions`
## spreads players evenly by index -- and "for free" is the kind of claim that stops
## being true the day somebody reorders the loop. Printed as distances: a teammate should
## be nearer than either opponent.
func _report_teams() -> void:
	var cfg := _screen.build_config()
	print("teams:  %s, startable %s" % [cfg.teams, _screen.can_start()])
	print("    status: %s" % _screen.status_text())
	var starts := _screen.map_data().starts
	if starts.size() != cfg.teams.size():
		push_warning("preview_skirmish: %d starts for %d players"
				% [starts.size(), cfg.teams.size()])
		return
	for i in range(starts.size()):
		var parts: Array[String] = []
		for j in range(starts.size()):
			if i == j:
				continue
			parts.append("p%d(t%d) %d" % [j + 1, cfg.teams[j],
					int(Vector2(starts[i]).distance_to(Vector2(starts[j])))])
		print("    player %d (team %d) -> %s" % [i + 1, cfg.teams[i], ", ".join(parts)])


func _report_screen() -> void:
	var cfg := _screen.build_config()
	var data := _screen.map_data()
	_expected = data
	print("screen: %s %dx%d seed %d, %d players, mode %s, startable %s"
			% [MapGenerator.type_name(data.meta.get("type", 0) as MapGenerator.Type),
			data.size.x, data.size.y, int(cfg.seed), cfg.player_ids.size(),
			MatchConfig.mode_name(cfg.mode), _screen.can_start()])
	print("    status: %s" % _screen.status_text())
	for i in range(cfg.player_ids.size()):
		print("    player %d: colour %d, ai %s"
				% [cfg.player_ids[i], cfg.colours[i], cfg.ai_players[i]])


## Pick a role on slot `index` the way a finger does: move the dropdown, then let its own
## signal carry the change.
##
## `select()` AND `item_selected.emit()`, not the handler on its own. Calling the handler
## directly leaves the OptionButton still showing its old choice, so the first version of
## this photographed a lobby whose Player 2 row read "PlayTest AI" while the peer list
## below it said somebody had joined that slot -- and it would have passed just as
## happily with the signal unconnected. Same reason `preview_match` presses the real
## cancel Button rather than calling `_exit_placement`.
func _pick_role(index: int, role: SkirmishScreen.Role) -> void:
	var picker: OptionButton = _screen._slot_rows[index]["role"]
	var item := picker.get_item_index(int(role))
	picker.select(item)
	picker.item_selected.emit(item)


## Choose how much ROOM the map has, through the picker's own signal.
func _pick_slots(n: int) -> void:
	var item := _screen._count_picker.get_item_index(n)
	_screen._count_picker.select(item)
	_screen._count_picker.item_selected.emit(item)
	_hold(LOBBY_FRAMES)


func _report_slots() -> void:
	var cfg := _screen.build_config()
	print("slots: %d rows, %d players, map %dx%d (room for %d), %d starts, startable %s"
			% [_screen._slot_rows.size(), cfg.player_ids.size(),
			cfg.map_size.x, cfg.map_size.y, _screen._slots,
			_screen.map_data().starts.size(), _screen.can_start()])
	print("    status: %s" % _screen.status_text())
	var starts := _screen.map_data().starts
	if starts.size() == 2:
		# The reason the two counts are separate: two players on a big board must not be
		# crammed into one corner of it.
		var apart := Vector2(starts[0]).distance_to(Vector2(starts[1]))
		print("    the two starts are %d tiles apart on a %d board"
				% [int(apart), _screen.map_data().size.x])
	if _screen._slot_rows.size() != _screen._slots:
		push_warning("preview_skirmish: %d rows for %d slots"
				% [_screen._slot_rows.size(), _screen._slots])


## Press slot 1's colour swatch, which is what opens the grid.
##
## The REAL Button on the row, not `_on_colour_pressed` -- the same reason `_pick_role`
## goes through the dropdown's own signal, and the same reason `preview_match` presses
## the real cancel-build button. A press is what is in doubt.
func _open_the_colour_picker() -> void:
	var button: Button = _screen._slot_rows[0]["colour"]
	print("colour: slot 1 button '%s', rect %s, disabled %s"
			% [button.text, button.get_global_rect(), button.disabled])
	button.pressed.emit()
	_hold(LOBBY_FRAMES)


func _report_colour_picker() -> void:
	var picker: ColourPickerPopup = _screen._colour_picker
	var taken := _screen.build_config().colours
	print("colour: grid open %s, offering %s, taken by others %s"
			% [picker.is_open(), picker.offered(), [taken[1]]])
	if not picker.is_open():
		push_warning("preview_skirmish: the colour button did not open the grid")
	# THE WHOLE RULE, checked rather than eyeballed: a colour somebody else holds is
	# not on the grid at all.
	if picker.offered().has(int(taken[1])):
		push_warning("preview_skirmish: the grid offers player 2's colour to player 1")


## Take a colour off the grid, through its own swatch button.
func _pick_a_colour() -> void:
	var picker: ColourPickerPopup = _screen._colour_picker
	var current := int(_screen.build_config().colours[0])
	for index in picker.offered():
		if index == current:
			continue
		print("colour: pressing swatch %d (was %d)" % [index, current])
		picker.swatch_for(index).pressed.emit()
		_hold(LOBBY_FRAMES)
		return
	push_warning("preview_skirmish: nothing else on the grid to pick")


func _report_colours() -> void:
	var cfg := _screen.build_config()
	print("colour: now %s, grid open %s" % [cfg.colours, _screen._colour_picker.is_open()])
	if _screen._colour_picker.is_open():
		push_warning("preview_skirmish: the grid stayed up after a swatch was pressed")
	if cfg.colours[0] == cfg.colours[1]:
		push_warning("preview_skirmish: two players share a colour")


func _open_a_slot() -> void:
	_pick_role(1, SkirmishScreen.Role.OPEN)
	_hold(LOBBY_FRAMES)


func _close_the_slot() -> void:
	# Through _on_peer_left first: a slot with somebody in it cannot be un-opened, which
	# is the rule, so the peer has to go before the chair can.
	_screen._on_peer_left(7777)
	_pick_role(1, SkirmishScreen.Role.PLAYTEST_AI)
	print("lobby: closed -- state %d, session %s, startable %s"
			% [_screen.lobby_state(), Net.has_session(), _screen.can_start()])
	_hold(LOBBY_FRAMES)


## The joining device's screen, holding a real proposal from a host.
##
## A DIFFERENT SEED ON PURPOSE. The point of the lobby channel is that the joiner reviews
## the HOST'S map rather than one of its own, and the two are only distinguishable in a
## picture if they are different maps -- a shot where both sides generated seed 1 would
## look identical whether the channel worked or not.
##
## The lobby state is forced, since a real one needs a second process dialling in (that
## part is verified by running two of them). What the picture is worth is the LOOK of a
## screen being asked to agree to something, which no test can judge.
func _join_someone_elses_match() -> void:
	var host_side := SkirmishScreen.new()
	host_side._on_seed_changed(4242.0)
	var proposal := host_side.build_config()
	host_side.free()

	Net._lobby_config = proposal
	_screen._lobby = SkirmishScreen.Lobby.JOINED
	_screen._on_lobby_config_received()
	print("joined: reviewing seed %d, %dx%d, %s — ready %s, can start %s"
			% [proposal.seed, proposal.map_size.x, proposal.map_size.y,
			MatchConfig.mode_name(proposal.mode), _screen._am_ready, _screen.can_start()])
	if _screen.map_data() != proposal.map_data:
		push_warning("preview_skirmish: the joiner is not showing the host's map")
	_hold(LOBBY_FRAMES)


func _report_lobby() -> void:
	print("lobby: state %d, session %s, unfilled %d, startable %s"
			% [_screen.lobby_state(), Net.has_session(), _screen.unfilled_slots(),
			_screen.can_start()])
	for line in _screen.lobby_text().split("\n"):
		print("    %s" % line)
	if _screen.lobby_state() != SkirmishScreen.Lobby.HOSTING:
		push_warning("preview_skirmish: setting a slot to Open did not start hosting")


## Exactly what START does, minus the scene change.
func _start_the_match() -> void:
	_resume_at = 0                   # the match step re-bases _frames; drop any stale hold
	# Re-read what the screen is showing AT THE MOMENT OF COMMIT, which is what this
	# comparison is actually about: a config that builds a different world than the screen
	# previewed. Captured at step 0 originally, and that broke the moment the lobby steps
	# were added -- the JOINED excursion adopts a host's map into this same screen, so the
	# shot from six steps ago is no longer what is being started.
	_expected = _screen.map_data()
	Net.pending_match = _screen.build_config()
	_screen.queue_free()
	_screen = null
	_frames = SETTLE_FRAMES          # re-base the frame gate for the match's own settle
	_game = load("res://scenes/game/Game.tscn").instantiate()
	add_child(_game)


## What the match ACTUALLY got, against what the screen was showing.
func _report_match() -> void:
	var host := Net.host()
	if host == null or host.world == null:
		push_warning("preview_skirmish: no host -- the match never started")
		return
	var world: SimWorld = host.world

	var counts: Dictionary = {}
	for e in world.entities.values():
		var key := String(e.def_id)
		counts[key] = int(counts.get(key, 0)) + 1

	print("match:  %dx%d, %d entities, tick %d"
			% [world.map.size.x, world.map.size.y, world.entities.size(), world.tick])
	for p in world.players:
		print("    player %d: colour %d, ai %s, stock %s"
				% [p.id, p.colour, p.is_ai, p.stock])

	# The comparison this preview exists for.
	if _expected != null:
		var same_size := world.map.size == _expected.size
		var same_terrain := true
		for y in range(world.map.size.y):
			for x in range(world.map.size.x):
				var t := Vector2i(x, y)
				if world.map.terrain_at(t) != _expected.terrain_at(t):
					same_terrain = false
					break
			if not same_terrain:
				break
		print("    matches the preview: size %s, terrain %s" % [same_size, same_terrain])

	var keys := counts.keys()
	keys.sort()
	var parts: Array[String] = []
	for k in keys:
		parts.append("%s x%d" % [k, counts[k]])
	print("    ", ", ".join(parts))
	print("    pending_match cleared: %s" % (Net.pending_match == null))


func _shoot(name: String) -> void:
	var path := SHOT_DIR + name + ".png"
	get_viewport().get_texture().get_image().save_png(path)
	print("wrote ", ProjectSettings.globalize_path(path))
