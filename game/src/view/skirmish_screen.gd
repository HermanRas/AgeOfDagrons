## The skirmish settings screen (PLAN.md 1.6), **and the multiplayer lobby**.
##
## The two differ only in what fills a player slot, so this is one screen with one
## dropdown per slot: Human (this device) / PlayTest AI / Open (waiting for a peer).
## All-local is a skirmish; an Open slot plus a listening host is a multiplayer match.
## That is the whole reason there is no second screen: the flow tested solo tonight is
## the flow that runs on two devices, rather than a parallel path that first executes
## on the day it matters.
##
## THE LOBBY HALF (12.1c). Setting a slot to Open IS opening the socket -- there is no
## separate host button to forget, and no way to advertise a slot nobody can dial. START
## then waits until every advertised slot has somebody in it, which is the difference
## between this and the throwaway (g) screen it replaces: that one launched the match the
## instant anybody connected, because it had no slots to speak of. The joining device runs
## this same screen in `Lobby.JOINED`, where it configures nothing and waits, because the
## host's settings are the match's settings.
##
## Everything it collects **is** a `MatchConfig`, which is what `build_config()`
## returns -- so the screen has no vocabulary of its own to translate out of, and a
## test can assert what it would start without touching a scene tree.
##
## Built in `_init()` rather than `_ready()`, the convention every widget here follows.
## Uses Godot's stock `OptionButton`/`SpinBox` rather than the dragon-pack art: this is
## the `ResourceHUD`-at-7.1 stage of the screen, where the job is the WIRING and the
## skin comes later, and a settings screen made of TextureButtons would need art for
## every dropdown state before it could be used at all.
class_name SkirmishScreen
extends Control

## What fills a player slot. `OPEN` is the multiplayer half: the slot is advertised and a
## joining peer takes it (12.1c).
##
## `CLOSED` is a slot with NOBODY in it, and it is what makes the player count and the map
## size two different things: eight slots with six closed is a two-player match on a map
## with eight players' worth of room. Its space on the map is still reserved -- the board
## is sized for every slot -- it simply holds no player, no base and no bot.
## The four AI roles past `PLAYTEST_AI` are APPENDED rather than slotted in beside it,
## which keeps HUMAN/PLAYTEST_AI/OPEN/CLOSED on the integers they have always had. The
## order the player SEES is the order `_add_role_items` lists them in and owes nothing
## to these numbers.
##
## `PLAYTEST_AI` keeps its name and is labelled **AI (Easy)** on screen (project owner,
## 2026-08-22). The name is what it IS -- the PlayTest AI of 12.2a, unchanged -- and the
## label is what it means to somebody choosing an opponent. Renaming the member would
## have churned a dozen tests to say the same thing.
enum Role { HUMAN, PLAYTEST_AI, OPEN, CLOSED, AI_PASSIVE, AI_NORMAL, AI_HARD, AI_UNFAIR }

## Role -> `SimPlayer.AILevel`, for the roles that are bots. Anything absent is not a
## bot, which is what `_is_ai_role` reads it for -- one table rather than a predicate
## and a mapping that could disagree about which roles are AI.
const AI_ROLE_LEVELS := {
	Role.AI_PASSIVE: SimPlayer.AILevel.PASSIVE,
	Role.PLAYTEST_AI: SimPlayer.AILevel.EASY,
	Role.AI_NORMAL: SimPlayer.AILevel.NORMAL,
	Role.AI_HARD: SimPlayer.AILevel.HARD,
	Role.AI_UNFAIR: SimPlayer.AILevel.UNFAIR,
}


static func _is_ai_role(role: Role) -> bool:
	return AI_ROLE_LEVELS.has(role)


## The inverse of `AI_ROLE_LEVELS`, for a joined client turning a host's config back
## into rows. Derived from the same table rather than written out again, so the two
## directions cannot disagree; an unknown level lands on Easy, which is also what
## `SimWorld.setup` falls back to.
static func _role_for_level(level: int) -> Role:
	for role in AI_ROLE_LEVELS:
		if int(AI_ROLE_LEVELS[role]) == level:
			return role
	return Role.PLAYTEST_AI

## Which side of a network match this screen is on, which is the third thing it is.
##
## `LOCAL` is a skirmish: nothing is listening and START plays at once. `HOSTING` is the
## same screen with a slot advertised and a socket open. `JOINED` is the screen on the
## OTHER device -- and it configures nothing, because the host's settings are the
## match's settings, so every control is disabled and it waits to be told to start.
enum Lobby { LOCAL, HOSTING, JOINED }

## Emitted with the assembled config. `GameScene` is reached through `Net.pending_match`
## rather than through this signal -- the signal is for tests and for whatever screen
## eventually wraps this one.
signal start_requested(cfg: MatchConfig)
signal back_requested()

const _GAME_SCENE := "res://scenes/game/Game.tscn"
const _MAIN_MENU_SCENE := "res://scenes/menu/MainMenu.tscn"
const _SEED_MAX := 999999

## THE LOBBY'S PROPORTIONS. **HALF AND HALF SINCE 2026-08-31** (project owner: *"srink
## the chat pannel to 50% and grow game setup and map setup to 50% so the 2 columns is
## hald and half"*), where the first spec was *"left 2/3rds of the screen CHAT, right
## 1/3rd of the screen setup's"*.
##
## IT BUYS BACK MOST OF THE FOLD, which is the thing the 2:1 split could not do. At
## 1152x648 the setup column went from roughly 435 px of width to about 545, and the two
## framed panels want ~700 px of HEIGHT between them -- but a wider column is a shorter
## one: the map picture is `KEEP_ASPECT_CENTERED` inside its own fixed height, and the
## slot rows stop wrapping their identity lines. It still scrolls at eight slots. See
## `_PREVIEW_HEIGHT` for why shrinking the picture is not the lever.
##
## Stretch ratios rather than pixel sizes or percentages of `size`, so the split holds
## at every viewport this game is ever laid out at -- `window/stretch/aspect` is
## `expand`, so the viewport genuinely does change shape between a phone and a desktop
## window, and a number computed once from `size` would be right on one of them.
##
## THE VERTICAL SPLIT IS NOT A RATIO AND USED TO BE. The owner's first spec said *"bottom
## 20% nav with buttons"*, so the strip was given a quarter of the body's stretch -- and
## once the footer became a single row of half-height buttons it was using about a third
## of what it had reserved, with the rest sitting empty above the screen edge while the
## setup column scrolled. It now takes the height it needs and **the two columns take
## everything else** (*"have the single row that looks really good hug the bottom of the
## screen, srink the footer and grow the tow main columns down"*).
const _CHAT_STRETCH := 1.0
const _SETUP_STRETCH := 1.0

## Inside a dragon-framed panel, clear of the moulding. Larger than
## `HudStyle.PANEL_ORNATE_MARGIN` would suggest is needed on the flat edges, and that is
## the point: the ornament is in the CORNERS, so content set to the edge inset still
## collides with a dragon at the ends of the first and last rows.
const _PANEL_INSET := 20

## Inside the plain plate around the map picture. `HudStyle.PANEL_MARGIN` is 12 and this
## clears it by two, which is all a plain moulding needs.
const _MAP_FRAME_INSET := 14

## The map picture's height. Width is whatever the setup column gives it: `MapPreview`
## is a `TextureRect` on `KEEP_ASPECT_CENTERED`, so it fits its box and the diamond
## stays a diamond. It was a fixed 320x320 square while the map column was half the
## screen; a third of the screen is narrower than that on a phone.
##
## ⚠️ **SHRINKING THIS DOES NOT MOVE THE FOLD**, which is worth knowing before anyone
## tries it again. The fold is where GAME SETUP ends, and that is fixed by ITS five
## rows; a smaller picture just leaves more empty panel below the picture. Measured at
## 1152x648: the two framed panels want about 700 px between them and the setup column
## is given roughly 435, so the column scrolls (see `_init`) and MAP SETUP is always
## partly below it. 190 -> 140 -> 112 changed nothing about that, so it is back at a
## size worth looking at once you have scrolled to it.
const _PREVIEW_HEIGHT := 150.0

## Both dropdowns on a slot row CLIP rather than sizing to their widest item.
##
## `OptionButton` inherits `Button`'s rule that the control is always wide enough for
## its text, and the widest role here is "AI (Normal) — as Easy" -- which on its own is
## more than half of what a third of a 1152 px viewport has left after the frame. With
## `clip_text` the list stays honest about what the placeholders do and the ROW stays
## inside the panel, which is the trade this screen wants: the list is read when it is
## open, and it opens at full width.
## A nav-strip button. See `_nav_button` for both numbers: 26 is half the old height and
## the width is what keeps START from resizing the row when its label grows.
const _NAV_BUTTON_MIN := Vector2(86.0, 26.0)

const _ROLE_MIN := Vector2(150.0, 0.0)
const _SWATCH_MIN := Vector2(76.0, 0.0)
const _PICKER_MIN := Vector2(140.0, 0.0)

## The team dropdown, beside the swatch (project owner, 2026-08-31: *"teams number
## [1,2,3,4] on the lobby a small 1 char drop down next to color"*).
##
## ONE CHARACTER PLUS THE ARROW. **62, AND 46 WAS MEASURED WRONG** -- an `OptionButton`
## draws its own indicator and the theme's content margins whatever the text is, and this
## project's theme is a painted nine-patch with a generous one. At 46 the arrow and the
## margins took the whole control and the render came back as an empty red box beside the
## colour swatch, which is a dropdown that has lost the only thing it displays.
##
## `fit_to_longest_item` is turned OFF -- it is on by default and would size this to the
## widest ITEM, the same rule `_ROLE_MIN`'s note describes fighting on the role picker.
## **And `clip_text` is deliberately NOT set here**, unlike on the two pickers beside it:
## every item is one character, so there is nothing to clip, and clipping is what hides
## the digit rather than the box when the arithmetic above is wrong again.
const _TEAM_MIN := Vector2(62.0, 0.0)

## How many sides a match may be split into, which is the owner's list exactly.
##
## FOUR IS A DESIGN NUMBER, NOT A LIMIT OF ANYTHING. `SimPlayer.team` is a plain int and
## `Diplomacy.allied` compares two of them, so nothing below this screen cares -- eight
## teams would work and would also be a free-for-all with extra steps.
const _TEAM_COUNT := 4

## The item id for "no team", which is `SimPlayer.team`'s 0 and is a real answer rather
## than a missing one -- see `MatchConfig.teams`.
##
## IT HAS TO BE OFFERED, and that is not a hedge. Eight slots cannot each have their own
## team out of four numbers, so a lobby that only offered 1-4 would have to default some
## pair of players into an alliance nobody asked for. Every slot opens unaligned instead,
## which is exactly the free-for-all this game has always played, and a team is something
## you deliberately do.
const _NO_TEAM := 0

## What `_NO_TEAM` looks like in a control one character wide.
const _NO_TEAM_LABEL := "–"

## Slot counts offered, which is the whole 2-8 the generator supports. Was pinned at 2
## while nothing else was tested; the generator has validated every type at every count
## since 2.4b, and CLOSED means a big board no longer forces a big match.
const _MAX_OFFERED_PLAYERS := MapGenerator.MAX_PLAYERS

## A match needs two sides. Fewer active slots than this is a lobby, not a game -- and
## `MapValidator` says the same thing from the other end ("a match needs at least 2
## starts"), so without this the generator would silently clamp up to 2 and hand back a
## map with a start nobody is standing on.
const _MIN_PLAYERS := MapGenerator.MIN_PLAYERS

## HOW MANY SLOTS, WHICH IS HOW BIG THE MAP IS -- not how many people are playing.
##
## The two used to be one number, and separating them is the whole of this feature: eight
## slots with six CLOSED is a request for eight players' worth of room with two people in
## it. `_active_slots()` is the other number, and every place that used to say `_players`
## now has to say which one it meant.
var _slots: int = 2

var _seed: int = 1
var _type: MapGenerator.Type = MapGenerator.Type.RANDOM
var _mode: MatchConfig.Mode = MatchConfig.Mode.LAST_MAN_STANDING

## Which age everybody opens in (project owner, 2026-08-30). ONE setting for the whole
## match, not one per slot -- see `MatchConfig.starting_age` for why.
var _starting_age: int = 1

## Sized for the maximum, so raising the slot count never has to grow them mid-change.
## Slots past `_slots` are simply not looked at.
var _roles: Array[Role] = []
var _colours: Array[int] = []

## Whose side each slot is on, 0 for nobody's. Sized like `_colours` and seeded to
## `_NO_TEAM` for the same reason: raising the slot count must never conjure an
## alliance that was not asked for.
var _teams: Array[int] = []

var _data: MapData = null

var _lobby: Lobby = Lobby.LOCAL

## Host only, from `--autostart`: press START as soon as the lobby is full and everyone
## has agreed. See `_apply_cmdline`.
var _autostart := false

## Joiner only, from `--autoready`: press READY as soon as the host's proposal arrives.
var _autoready := false

## The port advertising a slot binds. `Net.PORT` in the game, always.
##
## Settable because opening a slot binds a REAL socket -- that is the behaviour, and a
## faked one would test the fake -- and a fixed port makes the suite fight anything else
## on the machine holding it. Found the honest way: ten lobby tests went red while the
## owner had this very screen open with a slot advertised, because the game had 27015 and
## the tests could not have it. The suite now hosts somewhere nobody else would.
var host_port: int = Net.PORT

## Slot index -> the peer id standing in it. Only ever holds OPEN slots.
##
## Kept here rather than asked of `Net.peer_players()` on demand because that map is
## keyed the other way and knows nothing about SLOTS -- it maps a peer to the player id
## the server handed out, and which slot on this screen that fills is this screen's
## business.
var _slot_peers: Dictionary = {}

var _preview: MapPreview
var _status: Label
var _seed_box: SpinBox
var _type_picker: OptionButton
var _start_button: Button
var _slot_rows: Array[Dictionary] = []      # {role: OptionButton, colour: Button}
var _join_field: TouchLineEdit
var _join_button: Button
var _lobby_status: Label
var _reroll_button: Button
var _count_picker: OptionButton
var _mode_picker: OptionButton
var _age_picker: OptionButton
var _ready_button: Button
var _slot_box: VBoxContainer
var _back_button: Button

## THE SAME CHAT WIDGET THE MINIMAP'S CORNER BUTTON OPENS (project owner, 2026-08-30:
## *"left side of the screen duplicate chat panel from mini map button"*) -- the same
## `ChatBoard` class, not a second layout that looks like it. Its player tabs are fed
## from the SLOT ROWS here rather than from a snapshot, because before a match there is
## no snapshot; `ChatBoard.show_players` takes the shape both callers can produce.
var _chat: ChatBoard

## The two halves of the body, held so their rects can be measured. See `_init`.
var _chat_column: PanelContainer
var _setup_column: ScrollContainer

## The in-game technology tree, opened over the lobby by the nav button (project owner:
## *"TechTree (same panel from minimap buttin ingame)"*). The same `TechTreePanel`, set
## to the age the match would OPEN in -- which is the question worth asking here, since
## the starting-age picker is two panels away and this is what it buys you.
var _tech_tree: TechTreePanel
var _tech_button: Button

## The server browser wireframe (2026-08-31), opened over the lobby by the nav button.
## Held for the tech tree's reason: a preview and a test both want to open it without
## walking the child list looking for it.
var _browser: ServerBrowserPanel
var _browser_button: Button

## The plate around the map picture, turned 45° to sit on the diamond. Held because its
## size is recomputed from the box's `resized` -- see `_fit_map_frame`.
var _map_frame: NinePatchRect

## What a joining player is agreeing to, on the nav strip beside READY. Its own label
## rather than sharing `_lobby_status`, which moved into the chat frame when the footer
## was cut to one row: the dial addresses can live over there, the terms of an invitation
## cannot be two feet from the button that accepts them.
var _terms_label: Label

## The palette grid a colour button opens. ONE instance for the whole screen rather
## than one per slot row: the rows are torn down and rebuilt whenever the slot count
## changes, and a picker owned by a row would be freed underneath the finger that
## opened it. `_picking_slot` is which row it was opened for.
var _colour_picker: ColourPickerPopup
var _picking_slot: int = -1

## This device's own answer, on a joined client. Reset to false whenever a new proposal
## arrives, because agreeing to one match is not agreeing to the next one.
var _am_ready := false


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var backdrop := ColorRect.new()
	backdrop.color = HudStyle.DARK_BG
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 24)
	add_child(margin)

	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 12)
	margin.add_child(page)

	# Before any row is built, since a row reads the role and colour it is showing.
	_seed_slot_defaults()

	# WHAT SCREEN THIS IS, said once at the top. Static text: it is the same screen for
	# a solo skirmish and a hosted match (see the class header), and a title that
	# changed with the lobby state would be a fourth thing claiming to describe it
	# alongside the join row, the slot rows and the START button.
	page.add_child(_heading("MULTIPLAYER — SKIRMISH"))

	# THE ONLY THING ON THE PAGE THAT EXPANDS. The heading takes its line and the nav
	# strip takes its row; everything left over is the two columns, which is what makes
	# the footer hug the bottom edge -- see `_CHAT_STRETCH` for the history.
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(body)

	_chat = ChatBoard.new()
	# HELD, both of them, because "is the split actually half and half" is a question
	# about these two rects and nothing else -- and the answer is not the stretch ratios,
	# which only divide what is left after every minimum is honoured. Walking the tree
	# for them found a chat tab's `PanelContainer` instead, which is how the first
	# version of `preview_skirmish._report_columns` reported a 36/64 split of a lobby
	# that was already exactly even.
	_chat_column = _framed("CHAT", _build_chat_column(), true)
	_chat_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat_column.size_flags_stretch_ratio = _CHAT_STRETCH
	body.add_child(_chat_column)

	# ⚠️ THE SETUP COLUMN SCROLLS, AND IT IS NOT OPTIONAL. This screen offers up to eight
	# slots and each is a two-line block: at eight, the GAME SETUP panel alone is taller
	# than a 648 px viewport, so MAP SETUP and the whole nav strip were simply off the
	# bottom of the screen with no indication they existed. A `VBoxContainer` does not
	# clip or compress past its children's minimum sizes -- it overflows, silently and
	# off the edge. Found in the render; every structural test passed.
	_setup_column = ScrollContainer.new()
	_setup_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_setup_column.size_flags_stretch_ratio = _SETUP_STRETCH
	# Vertical only. Sideways scrolling would let the panels be narrower than the column
	# and hide a dropdown off to the right, which is the same failure in the other axis.
	_setup_column.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(_setup_column)

	var setups := VBoxContainer.new()
	setups.add_theme_constant_override("separation", 12)
	setups.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_setup_column.add_child(setups)
	# MAP FIRST (project owner, 2026-08-30: *"swap map and game setup"*). It also puts the
	# panel that fits above the fold at the top of a column that scrolls -- see `_init`'s
	# note on the scroll and `_PREVIEW_HEIGHT` on why the fold is where it is.
	setups.add_child(_build_map_setup())
	setups.add_child(_build_game_setup())

	page.add_child(_build_nav())

	# THE TECHNOLOGY TREE, over the whole screen. Added before the colour picker so the
	# picker still draws on top -- the two are never open together, but "last child
	# wins" is the only thing keeping either of them visible, and an ordering that is
	# only correct by accident is one a later insertion breaks silently.
	_tech_tree = TechTreePanel.new()
	add_child(_tech_tree)

	# AND THE SERVER BROWSER, over the same page. Neither it nor the tech tree can be
	# open at the same time as the other -- both are reached from the one nav row -- so
	# the order between THEM is arbitrary; what is not arbitrary is that both go in
	# before the colour picker, which must draw over everything. See the note above.
	_browser = ServerBrowserPanel.new()
	add_child(_browser)

	# LAST CHILD, so it draws over the page it covers. Added to the screen rather
	# than to a slot row for the reason `_colour_picker`'s own note gives.
	_colour_picker = ColourPickerPopup.new()
	_colour_picker.colour_chosen.connect(_on_colour_chosen)
	_colour_picker.cancelled.connect(func() -> void: _picking_slot = -1)
	add_child(_colour_picker)

	regenerate()

	Net.peer_joined.connect(_on_peer_joined)
	Net.peer_left.connect(_on_peer_left)
	Net.match_configured.connect(_on_match_configured)
	Net.lobby_config_received.connect(_on_lobby_config_received)
	Net.lobby_ready_changed.connect(_on_lobby_ready_changed)
	Net.lobby_colour_requested.connect(_on_lobby_colour_requested)
	Net.session_ended.connect(_on_session_ended)
	_refresh_lobby()
	_apply_cmdline()


# ── layout ──────────────────────────────────────────────────────────────────

## THE BOTTOM STRIP, three groups of it (project owner, 2026-08-30). Join on the left,
## the two side doors in the middle, and the two decisions -- go, or go back -- on the
## right, which is where a thumb finishes.
##
## ONE ROW SINCE THE SECOND PASS (*"please half the size of the buttons so they fit in 1
## row"*). It was two stacked rows per group, at 44 px each; they are half that now and
## side by side, which gives the strip back about 60 px -- and the strip is 20% of a page
## whose right-hand column was already scrolling, so that height is worth having.
##
## The one thing left under the row is `_terms_label`, and only on a joined client. See
## its declaration for why it did not go to the chat box with the dial addresses.
func _build_nav() -> Control:
	# SHRINK_END, not EXPAND_FILL. The strip takes exactly the height of its one row and
	# the columns above take the rest, which is what puts it against the bottom edge.
	var nav := VBoxContainer.new()
	nav.add_theme_constant_override("separation", 6)
	nav.size_flags_vertical = Control.SIZE_SHRINK_END

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.add_child(_build_join_column())
	row.add_child(_build_doors_column())
	row.add_child(_build_go_column())
	nav.add_child(row)

	_terms_label = HudPanel.note_label("", 13)
	_terms_label.visible = false
	nav.add_child(_terms_label)
	return nav


## Joining someone else's match: an address and a button, and nothing more.
##
## ⚠️ **IT MOVED TO THE BOTTOM OF THE PAGE AND THAT IS A KNOWN RISK.** It used to be the
## first row on the screen, for a measured reason: a landscape Android keyboard covers
## roughly the bottom two thirds, so a field any lower is one you type into blind
## (BUGS.md). The owner asked for a three-column nav strip along the bottom with join in
## it, which is a layout decision that overrides a layout constraint -- so this needs
## RE-CHECKING ON THE DEVICE, and if the keyboard does bury it the fix is to scroll the
## page or lift the strip while the field has focus, not to move the field back.
##
## A `TouchLineEdit`, not a `LineEdit`: this project turns off mouse emulation from
## touch, so a plain field never takes focus from a finger and never raises a keyboard
## at all. That is the bug that blocked this whole screen.
func _build_join_column() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# NOT `_label()`, whose 96 px minimum is sized for the settings column. Seven
	# controls share one row here and every minimum in it is spent twice: the first
	# one-row footer came out 24 px wider than the page and pushed BACK off the edge.
	var join_label := Label.new()
	join_label.text = "Join"
	join_label.add_theme_color_override("font_color", HudStyle.GOLD)
	join_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(join_label)

	_join_field = TouchLineEdit.new()
	_join_field.placeholder_text = "host address, e.g. 192.168.0.12"
	_join_field.custom_minimum_size = Vector2(90.0, 0.0)
	_join_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_join_field.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_join_field)

	_join_button = _nav_button("JOIN", _on_join_pressed)
	row.add_child(_join_button)
	return row


## The two side doors: somewhere to find a host, and something to read while waiting.
##
## SERVER BROWSER OPENS A WIREFRAME (project owner, 2026-08-31: *"lets build out a
## wireframe for server browser / server discovery"*). It was a disabled placeholder,
## on the standing rule that a control wired to nothing must not look like one that
## works -- and that rule has not been relaxed, it has been satisfied differently:
## the button now opens a page, and the PAGE is what says it discovers nothing.
## `ServerBrowserPanel`'s header carries what a real one needs, in order.
func _build_doors_column() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# "SERVERS", not "SERVER BROWSER". Six of them share one row now and the longer
	# label came out as "SERVER BROWSE" -- `clip_text` cuts, it does not shrink, so a
	# label that does not fit is a label with a letter missing rather than a smaller one.
	_browser_button = _nav_button("SERVERS", _on_browser_pressed)
	_browser_button.tooltip_text = "Server browser — a wireframe; discovery is not built yet"
	row.add_child(_browser_button)

	_tech_button = _nav_button("TECH TREE", _on_tech_tree_pressed)
	row.add_child(_tech_button)
	return row


## START, READY and Back. The three that leave this screen.
##
## START IS SIZED FOR "START MATCH", which is the longer of the two labels it wears --
## it says "START" for a plain skirmish and "START MATCH" once a slot is open, because
## the press means two different things and the second one commits people who are
## waiting. `_NAV_BUTTON_MIN` holds that width, so the row does not reshuffle under a
## thumb the moment a slot is opened.
func _build_go_column() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_start_button = _nav_button("START", _on_start_pressed)
	row.add_child(_start_button)

	# The joining player's say. Only visible to them -- a host readies by pressing START,
	# and two buttons meaning the same thing on one screen would be one too many.
	_ready_button = _nav_button("READY", _on_ready_pressed)
	_ready_button.visible = false
	row.add_child(_ready_button)

	_back_button = _nav_button("BACK", _on_back_pressed)
	row.add_child(_back_button)
	return row


## Open the tech tree over the lobby, showing what the match's STARTING AGE unlocks.
##
## `set_age(_starting_age)` rather than 1: the age picker is in the panel above and this
## is the only place on the screen that answers "and what does that get me". Nothing is
## researched yet, which is exactly true of a match that has not begun -- so the tree
## reads as the whole ladder with the first age lit, which is what it is.
func _on_tech_tree_pressed() -> void:
	_tech_tree.set_age(_starting_age)
	_tech_tree.set_researched({})
	_tech_tree.open()


## Open the server browser over the lobby (2026-08-31). Nothing is passed to it because
## it reads nothing yet -- see `ServerBrowserPanel`, which is a wireframe and says so.
func _on_browser_pressed() -> void:
	_browser.open()


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	UiFont.title(label, 28)
	label.add_theme_color_override("font_color", HudStyle.GOLD)
	return label


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", HudStyle.GOLD)
	# THE FLOOR THE IDENTITY BLOCK WRAPS AGAINST, as well as the width of a setting's
	# name. `_build_slot_row` stacks a wrapping status label under one of these, and this
	# minimum is the only thing giving that label a width to wrap into -- see the note
	# there, and `HudPanel.note_label` for what a wrapping label with no width does.
	label.custom_minimum_size = Vector2(96.0, 0.0)
	return label


## A heading inside one of the framed panels. Smaller than the page title above it and
## in the same gold, so the two read as a hierarchy rather than as two titles.
func _section_heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	UiFont.title(label, 20)
	label.add_theme_color_override("font_color", HudStyle.GOLD)
	return label


## Wrap `content` in the dragon-cornered plate, with `heading` above it (project owner,
## 2026-08-30: *"GAME SETUP Panel with 9 patch border, the dragon one"*, and the map
## panel in *"the same 9 patch panel stile from resources panel"* -- which is this one:
## `ResourceHUD` passes `ornate` too).
##
## The content is built first and wrapped after, rather than the frame handing back a
## box to fill, because the two panels want different vertical behaviour inside the same
## frame and threading that through a builder is more argument than it is worth.
## The chat frame's insides: the board, and under it the line that says what the session
## is doing.
##
## THE DIAL ADDRESSES LIVE HERE NOW (project owner, 2026-08-30: *"text printing ip is
## shown in footer, rather put it in chat box. to save sapce"*). They are the one thing
## on this screen that is genuinely a message about the session rather than a setting, so
## a chat box is a reasonable place for them -- and the footer got its height back.
func _build_chat_column() -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)

	_chat.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_chat)

	_lobby_status = Label.new()
	_lobby_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lobby_status.add_theme_font_size_override("font_size", 14)
	_lobby_status.add_theme_color_override("font_color", HudStyle.GOLD)
	column.add_child(_lobby_status)
	return column


## Wrap `content` in the dragon-cornered plate, with `heading` above it.
##
## `expand` is for a panel that should take the height it is given rather than the height
## it needs -- the chat, which has a scrolling log in it. The two setup panels want the
## opposite, because they sit in a scrolling column where "fill the space" has no meaning.
func _framed(heading: String, content: Control, expand: bool = false) -> PanelContainer:
	var panel := PanelContainer.new()
	HudStyle.add_panel_background(panel, true)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, _PANEL_INSET)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)
	column.add_child(_section_heading(heading))
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL if expand \
			else Control.SIZE_SHRINK_BEGIN
	column.add_child(content)
	return panel


## One setting: its name along the left, its control against the right edge (project
## owner, 2026-08-30: *"text align left - input align right"*).
##
## Per ROW rather than a two-column `GridContainer`, and the difference shows on the
## slot rows: a grid ties every row to one column width, so the widest dropdown in the
## panel would set the left margin of the "Players" label as well. Shrink-to-end on each
## control lines the right edges up, which is what was asked for, without coupling the
## left ones.
## THE CONTROL TAKES THE SLACK, the label does not. Both give the same right edge, and
## the first version handed the slack to the LABEL -- which left every dropdown at its
## bare minimum and clipped "Last Man Standing" to "Last Man Standi" in a panel with
## ninety spare pixels sitting in the gap beside it. It also lines the controls up on
## their left edges, which a column of settings wants anyway.
func _setting_row(text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var label := _label(text)
	label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row


func _build_map_setup() -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)

	_preview = MapPreview.new()
	_preview.custom_minimum_size = Vector2(0.0, _PREVIEW_HEIGHT)
	# A SIMPLE BORDER AROUND THE MAP (project owner: *"add a simple panel_hud.jpg border
	# around the map"*). The PLAIN plate, deliberately, inside the ornate one: a second
	# set of dragons nested in the first would read as a mistake, and this frame's job is
	# only to say where the picture stops.
	column.add_child(_framed_preview())

	_type_picker = OptionButton.new()
	_type_picker.custom_minimum_size = _PICKER_MIN
	_type_picker.clip_text = true
	# RANDOM first and selected, per 1.6: a random map is the default, and picking a
	# type is the deliberate act.
	# FROM `real_types()` rather than written out again. This list used to name the four
	# by hand, `MapGenerator.generate` indexed a second copy and `pool_names()` held a
	# third -- so adding a fifth type had three places to remember and no failure if you
	# missed one: the map would simply never be offered, silently.
	_type_picker.add_item(MapGenerator.type_name(MapGenerator.Type.RANDOM),
			int(MapGenerator.Type.RANDOM))
	for type in MapGenerator.real_types():
		_type_picker.add_item(MapGenerator.type_name(type), int(type))
	_type_picker.item_selected.connect(_on_type_selected)
	column.add_child(_setting_row("Map", _type_picker))

	# THE SEED IS VISIBLE AND EDITABLE. Without it "I liked that map" has no answer but
	# a saved file, and two people cannot compare notes on the same layout.
	var seed_controls := HBoxContainer.new()
	seed_controls.add_theme_constant_override("separation", 6)
	_seed_box = SpinBox.new()
	_seed_box.min_value = 0
	_seed_box.max_value = _SEED_MAX
	_seed_box.value = _seed
	_seed_box.value_changed.connect(_on_seed_changed)
	seed_controls.add_child(_seed_box)
	_reroll_button = _button("Re-roll", _on_reroll_pressed)
	seed_controls.add_child(_reroll_button)
	column.add_child(_setting_row("Seed", seed_controls))

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status)
	return _framed("MAP SETUP", column)


## The map picture inside a frame TURNED 45° TO HUG IT (project owner, 2026-08-30: *"the
## mini map border is not what i wanted, i need you to rotate it 45 so it hugs the mini
## map diamond, not a big square"*).
##
## THE GEOMETRY IS EXACT AND WORTH WRITING DOWN. `MapPreview.to_diamond` renders a
## `w x h` map into a SQUARE image of side `w + h`, with the diamond inscribed so its
## four points sit on the midpoints of that square's edges. A diamond inscribed that way
## in a square of side P has a side length of `P / sqrt(2)` -- so a SQUARE frame of that
## side, rotated 45° about its own centre and centred on the picture, has its edges lying
## exactly along the diamond's. `_MAP_FRAME_INSET` is then added to push the moulding
## clear of the terrain rather than through it.
##
## LAID OUT BY HAND, in a plain `Control` rather than a container, because **Godot's
## containers size and place children as though `rotation` were zero** -- a rotated child
## in a `MarginContainer` is positioned by its unrotated rect and then spun, which puts
## it somewhere else entirely. So the frame is centre-anchored, its pivot moved to its
## own middle, and its side recomputed from `resized`.
func _framed_preview() -> Control:
	var box := Control.new()
	box.custom_minimum_size = Vector2(0.0, _PREVIEW_HEIGHT)

	# ⚠️ **THE PLATE GOES UNDER THE PICTURE, AND IT WAS OVER IT FIRST.** `panel_hud` is a
	# PANEL: its middle is a filled recess, not a hole. Added after the preview it drew
	# a turned brown square exactly where the map should be and the map vanished --
	# `HudStyle.add_panel_background` avoids this with a `move_child(bg, 0)` and this
	# hand-built frame has to do the same thing for itself. The diamond image's corners
	# are transparent, so the border shows through them and the plate's fill backs the
	# picture, which is what it is for.
	if ResourceLoader.exists(HudStyle.PANEL_BG_PATH):
		_map_frame = NinePatchRect.new()
		_map_frame.texture = load(HudStyle.PANEL_BG_PATH)
		_map_frame.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		_map_frame.patch_margin_left = HudStyle.PANEL_MARGIN
		_map_frame.patch_margin_right = HudStyle.PANEL_MARGIN
		_map_frame.patch_margin_top = HudStyle.PANEL_MARGIN
		_map_frame.patch_margin_bottom = HudStyle.PANEL_MARGIN
		_map_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_map_frame.rotation = PI * 0.25
		# CENTRE-ANCHORED so the offsets below are measured from the middle of the box,
		# which is the one point the rotation leaves fixed.
		_map_frame.anchor_left = 0.5
		_map_frame.anchor_right = 0.5
		_map_frame.anchor_top = 0.5
		_map_frame.anchor_bottom = 0.5
		box.add_child(_map_frame)

	_preview.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.add_child(_preview)

	box.resized.connect(_fit_map_frame)
	_fit_map_frame()
	return box


## Size the turned frame to whatever square the picture is currently drawn in.
##
## `MapPreview` keeps the texture's aspect and centres it, so the diamond's bounding
## square is `min(width, height)` of the box -- not the box itself, which is usually
## wider than it is tall.
func _fit_map_frame() -> void:
	if _map_frame == null:
		return
	var box: Control = _map_frame.get_parent()
	var picture := minf(box.size.x, box.size.y)
	var side := picture / sqrt(2.0) + 2.0 * _MAP_FRAME_INSET
	_map_frame.offset_left = -side * 0.5
	_map_frame.offset_right = side * 0.5
	_map_frame.offset_top = -side * 0.5
	_map_frame.offset_bottom = side * 0.5
	# The pivot follows the size, or the frame spins about its top-left corner and
	# leaves the picture entirely.
	_map_frame.pivot_offset = Vector2(side, side) * 0.5


func _build_game_setup() -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)

	_count_picker = OptionButton.new()
	_count_picker.custom_minimum_size = _PICKER_MIN
	for n in range(MapGenerator.MIN_PLAYERS, MapGenerator.MAX_PLAYERS + 1):
		_count_picker.add_item(str(n), n)
		if n > _MAX_OFFERED_PLAYERS:
			_count_picker.set_item_disabled(_count_picker.item_count - 1, true)
	_count_picker.select(0)
	_count_picker.disabled = _MAX_OFFERED_PLAYERS <= MapGenerator.MIN_PLAYERS
	_count_picker.item_selected.connect(_on_count_selected)
	column.add_child(_setting_row("Players", _count_picker))

	# The rows live in their own box so changing the slot count can rebuild just them,
	# without disturbing the count picker above or the victory row below.
	_slot_box = VBoxContainer.new()
	_slot_box.add_theme_constant_override("separation", 10)
	column.add_child(_slot_box)
	_rebuild_slot_rows()

	_mode_picker = OptionButton.new()
	_mode_picker.custom_minimum_size = _PICKER_MIN
	_mode_picker.clip_text = true
	# Trophy and King of the Hill are DECLARED and inert (11.2), so they are listed and
	# disabled -- a mode that silently decided nothing would be worse than one greyed.
	for mode in [MatchConfig.Mode.LAST_MAN_STANDING, MatchConfig.Mode.TROPHY,
			MatchConfig.Mode.KING_OF_THE_HILL]:
		_mode_picker.add_item(MatchConfig.mode_name(mode), int(mode))
		if mode != MatchConfig.Mode.LAST_MAN_STANDING:
			_mode_picker.set_item_disabled(_mode_picker.item_count - 1, true)
	_mode_picker.select(0)
	column.add_child(_setting_row("Victory", _mode_picker))

	# WHICH AGE EVERYBODY OPENS IN (project owner, 2026-08-30).
	#
	# One row rather than one per slot: the owner asked for it "for all players", and it
	# is the only version that is obviously fair -- an age is a flat multiplier on what
	# you may build and train, so per-slot ages are a handicap system, which wants
	# designing rather than falling out of a dropdown.
	#
	# LISTED FROM ages.json, numeral and name both, which is what that file says this
	# kind of place is for: the HUD badge takes the numeral because it has no room for
	# words, and the lobby is named in `ages.json`'s own note as one of the three places
	# with room for prose. Every age is selectable -- unlike the victory picker beside
	# it, there is no half-built one to grey out, because starting in age 3 is the same
	# machinery as advancing into it.
	_age_picker = OptionButton.new()
	_age_picker.custom_minimum_size = _PICKER_MIN
	_age_picker.clip_text = true
	for age in range(1, _age_count() + 1):
		_age_picker.add_item(_age_label(age), age)
	_age_picker.select(_age_picker.get_item_index(_starting_age))
	_age_picker.item_selected.connect(_on_starting_age_selected)
	column.add_child(_setting_row("Start age", _age_picker))

	return _framed("GAME SETUP", column)


## Default roles and colours for as many slots as could ever be shown.
##
## Slot 1 is the human at this device, slot 2 the PlayTest AI -- the owner's default, and
## the one press-to-play skirmish 1.6 exists to protect. Everything past that starts
## CLOSED: raising the count to eight should widen the BOARD, not silently conjure six
## opponents nobody asked for.
func _seed_slot_defaults() -> void:
	_roles.clear()
	_colours.clear()
	_teams.clear()
	for i in range(_MAX_OFFERED_PLAYERS):
		_roles.append(Role.HUMAN if i == 0 else (
				Role.PLAYTEST_AI if i == 1 else Role.CLOSED))
		# EVERY SLOT UNALIGNED. See `_NO_TEAM`: four numbers cannot give eight slots a
		# side each, and the default this game has always played is a free-for-all.
		_teams.append(_NO_TEAM)
	# Yellow against red first, the owner's default; the rest take whatever is left, since
	# two players sharing a colour is an unplayable match (§1) at any count.
	var preferred := [2, 1]
	for i in range(_MAX_OFFERED_PLAYERS):
		if i < preferred.size():
			_colours.append(int(preferred[i]))
			continue
		for candidate in range(_palette_size()):
			if not _colours.has(candidate):
				_colours.append(candidate)
				break
	while _colours.size() < _MAX_OFFERED_PLAYERS:
		_colours.append(0)          # a palette smaller than the slot count; last resort


## Tear the rows down and build exactly `_slots` of them.
##
## Rebuilt rather than shown and hidden: a hidden row still holds a role that
## `build_config()` would read, and the bug that would produce -- a player in the match
## who is not on the screen -- is the worst kind available here.
func _rebuild_slot_rows() -> void:
	for child in _slot_box.get_children():
		_slot_box.remove_child(child)
		child.queue_free()
	_slot_rows.clear()
	for i in range(_slots):
		_slot_box.add_child(_build_slot_row(i))


## One chair: who it is on the left, what fills it on the right.
##
## THE IDENTITY TEXT SITS UNDER THE NAME (project owner, 2026-08-30: *"lets move the You
## & bot / joined player name text below the player1,player2,player3"*). It was a 220 px
## label at the far right of the row, which worked while this panel had half the screen
## and does not now that it has a third: the name, the swatch, the role dropdown and a
## sentence do not fit one line at that width. Stacked, the left half is a two-line
## identity block and the right half is the two controls -- and the sentence gets a whole
## line to itself, which "waiting for a player" wanted anyway.
func _build_slot_row(index: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var identity := VBoxContainer.new()
	identity.add_theme_constant_override("separation", 0)
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(identity)

	var name_label := _label("Player %d" % (index + 1))
	identity.add_child(name_label)

	# WHO IS ACTUALLY IN THIS CHAIR, on the row for that chair.
	#
	# Occupancy used to live in a separate block of text below the whole list, naming
	# only the Open slots -- so the host had a list of what it was waiting for rather
	# than a list of players, and the two could disagree with the rows above them. On the
	# row is the one place it cannot: there is exactly one player list now and both
	# devices render it from the same fields.
	# IT WRAPS RATHER THAN CLIPPING, and this is the one place on this screen where that
	# is safe. `HudPanel.note_label`'s warning is about a wrapping Label in an HBox with
	# nothing setting its width -- it collapses to one character per line. Here it is in
	# a VBox whose sibling is `name_label`, which carries an 84 px minimum, so the block
	# always has a width to wrap into. Clipping was tried first and lost the end of
	# "empty — room kept on the map" and "peer 7777 — reviewing...", which are the two
	# statuses that actually say something.
	var status := HudPanel.note_label("", 13)
	identity.add_child(status)

	var colour := Button.new()
	colour.custom_minimum_size = _SWATCH_MIN
	colour.clip_text = true
	colour.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	colour.pressed.connect(_on_colour_pressed.bind(index))
	row.add_child(colour)

	# WHOSE SIDE, RIGHT BESIDE WHAT COLOUR (project owner, 2026-08-31). The two are the
	# same kind of fact -- who this player IS, as against what fills the chair -- so they
	# sit together and the role dropdown stays on the end of the row.
	#
	# NO COLUMN HEADING, because there is no room for one on a row this wide and because
	# a one-character control with a number in it wants explaining in words rather than
	# in a heading. The tooltip is that explanation, and it says what a team DOES: the
	# only reason to set this is that allies stop being able to shoot each other.
	var team := OptionButton.new()
	team.custom_minimum_size = _TEAM_MIN
	team.fit_to_longest_item = false
	team.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	team.tooltip_text = "Team — players on the same team cannot attack each other, " \
			+ "and win or lose together. %s is no team at all." % _NO_TEAM_LABEL
	team.add_item(_NO_TEAM_LABEL, _NO_TEAM)
	for n in range(1, _TEAM_COUNT + 1):
		team.add_item(str(n), n)
	team.select(team.get_item_index(_teams[index]))
	team.item_selected.connect(_on_team_selected.bind(index))
	row.add_child(team)

	var role := OptionButton.new()
	role.custom_minimum_size = _ROLE_MIN
	# See `_ROLE_MIN`: the list keeps its honest placeholder labels and the CONTROL
	# clips, rather than the widest of them setting the width of the panel.
	role.clip_text = true
	role.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	role.add_item("Human", int(Role.HUMAN))
	# THE AI LADDER, easiest first, with the placeholders SAYING SO on screen. Listing
	# them before they work is deliberate (project owner, 2026-08-22): it shows the
	# shape of the choice, and it means the list does not renumber under a player's
	# muscle memory when 12.2b fills them in. All three placeholders play as Easy.
	role.add_item("AI (Passive)", int(Role.AI_PASSIVE))
	role.add_item("AI (Easy)", int(Role.PLAYTEST_AI))
	role.add_item("AI (Normal) — as Easy", int(Role.AI_NORMAL))
	role.add_item("AI (Hard) — as Easy", int(Role.AI_HARD))
	role.add_item("AI (Unfair) — as Easy", int(Role.AI_UNFAIR))
	# "Open", not "Open (waiting)". A dropdown lists the CHOICES; whether the chair is
	# still empty is status, and the lobby line below already says. The longer label read
	# as a contradiction the moment somebody was sitting in it -- a slot showing "Open
	# (waiting)" directly above "Player 2: peer 7777 joined".
	role.add_item("Open", int(Role.OPEN))
	role.add_item("Closed", int(Role.CLOSED))
	role.select(role.get_item_index(int(_roles[index])))
	role.item_selected.connect(_on_role_selected.bind(index))
	row.add_child(role)

	_slot_rows.append({"role": role, "colour": colour, "team": team,
			"name": name_label, "status": status})
	_refresh_colour_button(index)
	return row


func _button(text: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	if on_pressed.is_valid():
		b.pressed.connect(on_pressed)
	return b


## A button in the bottom nav strip.
##
## HALF THE HEIGHT IT WAS (project owner, 2026-08-30: *"please half the size of the
## buttons so they fit in 1 row"*). 44 was the touch floor this project has used since
## the HUD overhaul and 22 is below it -- so this sits at 26, which is half the old
## BUTTON including its separation and still a target a thumb can find. The strip is a
## lobby, pressed once per match, not a HUD pressed under time pressure.
##
## The width minimum is what stops the row reshuffling: START becomes "START MATCH" when
## a slot is opened, and a row that re-laid itself at that moment would move BACK under
## a thumb already travelling to it.
func _nav_button(text: String, on_pressed: Callable) -> Button:
	var b := _button(text, on_pressed)
	b.custom_minimum_size = _NAV_BUTTON_MIN
	b.clip_text = true
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return b


# ── state ───────────────────────────────────────────────────────────────────

## Generate from the current settings and refresh the preview and the Start button.
##
## Public because it is the whole behaviour of the screen and a test wants to drive it
## without pressing anything.
func regenerate() -> void:
	# TWO COUNTS. The map is SIZED for every slot and POPULATED for the players actually
	# in them, which is what makes "eight players, six closed" a big empty board for two
	# rather than two starts crammed into one corner of it.
	_data = MapGenerator.generate(_seed, _type, _active_slots().size(), _slots)
	_preview.show_map(_data)
	_refresh_status()
	_refresh_start_button()
	_publish_lobby()


## What the MAP SETUP panel says about the match as it stands: the board, the counts,
## the team split, or whichever of the three rules is being broken.
##
## SPLIT OUT OF `regenerate()` ON 2026-08-31, because a team change moves this line and
## does not move the map. Every figure in it that comes from the map is read off `_data`
## rather than recomputed, so calling it on its own is free -- and calling `regenerate()`
## for a setting the generator does not take would throw the map away and build the
## identical one back, which is what `_on_starting_age_selected` already refuses to do.
func _refresh_status() -> void:
	if _data == null:
		return
	var problems: Array = _data.meta.get("problems", [])
	var active := _active_slots().size()
	if active < _MIN_PLAYERS:
		# Said rather than shown as a dead button. Closing one slot too many is easy to do
		# and impossible to diagnose from a greyed START.
		#
		# BEFORE THE ONE-SIDE TEST BELOW, and the order is not cosmetic: one player is
		# also one side, so the team message would fire for a lobby whose real problem is
		# that it is empty -- and it indexes `_active_slots()[0]`, which does not exist.
		_status.text = "%d player — close fewer slots, a match needs %d" % [active, _MIN_PLAYERS]
		_status.add_theme_color_override("font_color", HealthDot.CRITICAL_COLOR)
	elif _sides() < 2:
		# ONE SIDE IS NOT A MATCH, and it is two presses away: put both players on team 1
		# and `WinConditionSystem` finds exactly one standing side on tick 1, so the game
		# is won before anybody has moved. Said rather than shown as a dead START, for
		# the reason immediately above -- a greyed button for a rule the player has just
		# invented is impossible to diagnose.
		_status.text = "everybody is on team %d — a match needs two sides" \
				% _teams[_active_slots()[0]]
		_status.add_theme_color_override("font_color", HealthDot.CRITICAL_COLOR)
	elif problems.is_empty():
		# The player count AND the size, because they are now different numbers and the
		# whole point of closing a slot is the gap between them.
		# The team split rides on the END of this line and only when there is one, so a
		# free-for-all reads exactly as it always has -- see `_summarise_teams`.
		_status.text = "%s, %d x %d — %d players on room for %d — ready%s" % [
				MapGenerator.type_name(_data.meta.get("type", _type) as MapGenerator.Type),
				_data.size.x, _data.size.y, active, _slots, _team_suffix()]
		_status.add_theme_color_override("font_color", HudStyle.GOLD)
	else:
		# A MAP THAT FAILS VALIDATION CANNOT BE STARTED (2.4b's gate). Saying why beats
		# a greyed button with no explanation -- and every one of these reads as a
		# sentence because MapValidator writes them for a person.
		_status.text = "Unplayable map: %s" % String(problems[0])
		_status.add_theme_color_override("font_color", HealthDot.CRITICAL_COLOR)


## Tell the people waiting what they are waiting for, whenever it changes.
##
## Called from every path that alters the match: a regenerated map, a colour, a role. A
## host who quietly changed the map under a player who had already agreed to it would be
## the exact failure the lobby channel exists to prevent -- so `broadcast_lobby_config`
## also cancels every agreement, and everyone has to say yes to the new thing.
func _publish_lobby() -> void:
	if _lobby == Lobby.HOSTING:
		Net.broadcast_lobby_config(build_config())


## The config this screen would start. Exactly a `MatchConfig`, with no translation.
func build_config() -> MatchConfig:
	var cfg := MatchConfig.new()
	cfg.player_ids = []
	cfg.colours = []
	cfg.ai_players = []
	# ONLY THE SLOTS SOMEBODY IS IN, numbered 1..N over those.
	#
	# Compacted rather than keeping the slot number as the player id, because `Net` hands
	# out the lowest free id to a joining peer and `MapGen.build_from` resolves a map's
	# player index by POSITION in `world.players` -- so a match whose ids skipped 3 and 4
	# would hand somebody else's base to the wrong player. Compaction keeps every one of
	# those assumptions true, and the closed slots have already done their job by the time
	# this runs: they set the size of the board.
	for i in _active_slots():
		cfg.player_ids.append(cfg.player_ids.size() + 1)
		cfg.colours.append(_colours[i])
		cfg.ai_players.append(_is_ai_role(_roles[i]))
		# Position for position with `ai_players`. Humans get a level too and it is
		# never read -- a hole here would misalign every bot after it.
		cfg.ai_levels.append(int(AI_ROLE_LEVELS.get(_roles[i], SimPlayer.AILevel.EASY)))
		# WHOSE SIDE (2026-08-31), compacted with everything else on the row -- a closed
		# slot's team is nobody's, exactly as its colour is.
		cfg.teams.append(_teams[i])
	cfg.seed = _seed
	cfg.map_type = _type
	cfg.map_data = _data
	cfg.map_size = _data.size if _data != null else MatchConfig.DEBUG_MAP_SIZE
	cfg.mode = _mode
	cfg.starting_age = _starting_age
	return cfg


func map_data() -> MapData:
	return _data


## Whether START would do anything. THREE rules now, and they all live here so the button
## and the handler can never disagree about it:
##
##   1. A validated map (2.4b's gate) -- an unplayable one is never launched.
##   2. Every advertised slot filled. Starting with an empty OPEN slot would launch a
##      match one player short of the one the host set up.
##   3. Not a joined client. Over there START belongs to the host, and the local button
##      would be a second, competing authority over when the match begins.
##   4. **Two players at least.** Closing slots is what makes this reachable: eight
##      slots with seven closed is one player and no match. Refused here rather than
##      left to the generator, which clamps a count of 1 up to 2 and would hand back a
##      map with a start nobody is standing on.
##   5. **Everybody has agreed.** A host who can start over a player who has not said
##      READY is a host who can drop somebody into a match they never got to look at,
##      which is the whole reason the lobby channel exists. Agreement is also cancelled
##      whenever a setting changes, so this cannot be satisfied by a stale yes.
##   6. **Two SIDES at least** (2026-08-31), which is rule 4 restated for teams and is
##      not implied by it: four players all on team 1 is four active slots and one side,
##      and `WinConditionSystem` would declare that match won on tick 1. Refused here
##      rather than started and instantly ended, and `regenerate()` says which team
##      everybody is on rather than leaving a dead button to explain itself.
func can_start() -> bool:
	if _data == null or not (_data.meta.get("problems", []) as Array).is_empty():
		return false
	if _lobby == Lobby.JOINED:
		return false
	if _active_slots().size() < _MIN_PLAYERS:
		return false
	if _sides() < 2:
		return false
	if unfilled_slots() != 0:
		return false
	return Net.all_peers_ready()


func _refresh_start_button() -> void:
	if _start_button == null:
		return
	_start_button.disabled = not can_start()
	# The button says what it is FOR, because on this screen the same press means two
	# different things and the difference matters: one plays at once, the other commits
	# the people already waiting on it.
	_start_button.text = "START MATCH" if _lobby == Lobby.HOSTING else "START"


func status_text() -> String:
	return _status.text


func lobby_state() -> Lobby:
	return _lobby


func lobby_text() -> String:
	return _lobby_status.text


## What a joining player is being asked to agree to, as shown beside READY. Empty on a
## host, which has nothing to agree to.
func terms_text() -> String:
	return _terms_label.text if _terms_label.visible else ""


# ── handlers ────────────────────────────────────────────────────────────────

## More or fewer SLOTS, which is a bigger or smaller map. Rebuilds the rows and
## regenerates, because the board size follows this number directly.
func _on_count_selected(item: int) -> void:
	_slots = _count_picker.get_item_id(item)
	_rebuild_slot_rows()
	regenerate()
	_refresh_lobby()


## HOW MANY SIDES THE ACTIVE SLOTS MAKE UP, which is the number a match is won over --
## `WinConditionSystem._last_man_standing` counts exactly this and the two must agree.
##
## An unaligned player is their own side; a team is one however many are on it. So a
## free-for-all of five is five sides and a 2v2 is two, which is what makes this the
## same rule for both and lets `can_start` ask one question.
func _sides() -> int:
	var seen: Dictionary = {}
	for i in _active_slots():
		# The NEGATIVE of the slot index for an unaligned player, so it can never collide
		# with a real team number. `WinConditionSystem` keys the same way, on the player
		# id -- same trick, and the comment there says why.
		seen[_teams[i] if _teams[i] > 0 else -(i + 1)] = true
	return seen.size()


## Slots with somebody or something in them: the actual players. CLOSED slots reserve
## their room on the board and hold nobody, which is the whole point of them.
func _active_slots() -> Array[int]:
	var out: Array[int] = []
	for i in range(_slots):
		if _roles[i] != Role.CLOSED:
			out.append(i)
	return out


## The starting age changed. NO `regenerate()` -- the map is a function of the seed, the
## type and the two player counts, and none of those moved. It still publishes, because
## a joined player has agreed to a match that opens in age 1 and this is a different one.
func _on_starting_age_selected(index: int) -> void:
	_starting_age = _age_picker.get_item_id(index)
	_publish_lobby()
	_refresh_lobby()


## How many ages the ladder has. Asked of the data for `_palette_size`'s reason:
## `ages.json` is the authority on its own length and a second copy here would drift.
func _age_count() -> int:
	if GameDataRegistry == null:
		return 4
	return maxi(1, GameDataRegistry.age_count())


## "II. Ember" -- the numeral and the name, which is exactly what `ages.json` says a
## place with room for prose should show.
func _age_label(age: int) -> String:
	var def: AgeDef = GameDataRegistry.age(age) if GameDataRegistry != null else null
	if def == null:
		return "Age %d" % age
	return "%s. %s" % [def.numeral, def.name]


func _on_type_selected(index: int) -> void:
	_type = _type_picker.get_item_id(index) as MapGenerator.Type
	regenerate()


func _on_seed_changed(value: float) -> void:
	_seed = int(value)
	regenerate()


## A new seed AND a regenerate, so the button is one press rather than "type a number,
## then press the other button".
##
## `randi()` is fine here: this is the view choosing what to ask for, not the sim
## deciding anything -- and whatever it picks is then visible in the box, which is the
## point of showing the seed at all.
func _on_reroll_pressed() -> void:
	_seed = randi() % (_SEED_MAX + 1)
	_seed_box.set_value_no_signal(_seed)
	regenerate()


## A COLOUR BUTTON OPENS THE PALETTE, showing only what is free.
##
## This used to be a cycle: a press stepped the slot to the next colour nobody else held.
## Cheap, and it made picking violet out of eight a matter of pressing five times and
## watching -- worse on a joined client, where every press was a round trip to the host, so
## the player was cycling blind through a list they could never see. The rule has not
## changed, only where it is expressed: taken colours are not on the grid at all rather
## than being skipped by the step. With colour the ONLY thing telling players apart (§1),
## a duplicate is not a cosmetic mistake, it is an unplayable match.
##
## YOUR COLOUR IS YOURS, on either device -- a joined client used to have every colour
## button disabled, so the one thing that tells players apart was assigned to them. What
## a joined client does NOT get is the authority: `_on_colour_chosen` asks rather than
## sets, because the no-duplicates rule belongs to whoever can see every slot.
func _on_colour_pressed(index: int) -> void:
	if _lobby == Lobby.JOINED and index != _local_slot():
		return                    # somebody else's identity, not yours to change
	_picking_slot = index
	_colour_picker.open_for("Player %d" % (index + 1), _colours[index],
			_taken_colours(index))


## What everybody ELSE holds, which is what the picker must not offer.
##
## ACTIVE slots only, never every slot. A closed slot holds no player, so its colour is
## nobody's -- counting it would leave two players on an eight-slot board with six colours
## spoken for by empty chairs and almost nothing left to choose from. That distinction was
## a real bug in the cycle it replaced and it is the same distinction here.
func _taken_colours(exclude_index: int) -> Array[int]:
	var taken: Array[int] = []
	for i in _active_slots():
		if i != exclude_index:
			taken.append(_colours[i])
	return taken


## A swatch was pressed. On the host this is the decision; on a joined client it is a
## request, and the host's re-broadcast is what actually moves the colour on this screen.
func _on_colour_chosen(colour_index: int) -> void:
	var slot := _picking_slot
	_picking_slot = -1
	if slot < 0 or slot >= _colours.size():
		return

	if _lobby == Lobby.JOINED:
		Net.request_colour(colour_index)
		return
	_set_colour(slot, colour_index)
	_publish_lobby()


## Give a slot a colour, refusing a collision. The host's rule, applied whether the host
## pressed the swatch or a joined player asked for it -- one function, because two copies
## of "is this colour free" is how the two come to disagree.
##
## Returns false and changes NOTHING on a collision rather than substituting some other
## colour: a client's idea of what was free can be a moment stale, and the re-broadcast
## that follows every lobby change is what corrects it. Silently handing them a different
## colour than the one they pressed would be worse than leaving them where they were.
func _set_colour(index: int, colour_index: int) -> bool:
	if index < 0 or index >= _colours.size():
		return false
	if colour_index < 0 or colour_index >= _palette_size():
		return false
	if _taken_colours(index).has(colour_index):
		return false
	_colours[index] = colour_index
	_refresh_colour_button(index)
	return true


## A joined player asked for a colour. Their slot is found from the PEER, so a client
## cannot ask on somebody else's behalf even if it wanted to.
##
## The re-broadcast cancels every agreement, including the asker's own -- consistent with
## every other change, and cheap: the player who just pressed the swatch is right there to
## press READY again. Skipped entirely when the request was refused, since nothing changed
## and cancelling everybody's consent over a no-op would be a hostile way to say no.
func _on_lobby_colour_requested(peer_id: int, colour_index: int) -> void:
	for slot in _slot_peers:
		if int(_slot_peers[slot]) != peer_id:
			continue
		if _set_colour(int(slot), colour_index):
			_publish_lobby()
			_refresh_lobby()
		return


## Changing a slot's role is what opens and closes the socket, because the OPEN role and
## a listening host are the same fact stated twice. There is no separate "host" button to
## forget to press, and no way to advertise a slot nobody can reach.
func _on_role_selected(item: int, index: int) -> void:
	var was_active := _active_slots().size()
	_roles[index] = (_slot_rows[index]["role"] as OptionButton).get_item_id(item) as Role

	# CLOSING OR REOPENING A SLOT CHANGES THE MAP, because the number of players is the
	# number of starts placed on it. Only when the ACTIVE count actually moved: swapping a
	# human for a bot is the same match on the same board, and regenerating there would
	# throw away the map somebody just picked over a change that did not touch it.
	#
	# Reopening returns you to the map you had, since the seed and both counts are back
	# where they were and generation is deterministic.
	if _active_slots().size() != was_active:
		regenerate()

	if _wants_peers() and _lobby == Lobby.LOCAL:
		var err := Net.host_open(host_port)
		if err != OK:
			# Put the slot back rather than leaving a screen that says it is waiting for
			# someone who can never arrive. This is how the missing Android INTERNET
			# permission presented at 0.7: nothing crashed, nothing said why.
			_roles[index] = Role.HUMAN
			(_slot_rows[index]["role"] as OptionButton).select(int(Role.HUMAN))
			_say("could not open a socket: %s" % error_string(err))
			return
		_lobby = Lobby.HOSTING
		# Logged on the TRANSITION, not from `_refresh_lobby_text`, which runs on every
		# refresh and would repeat itself. A terminal-driven host has nobody watching the
		# label, and "am I actually listening, and on what" is the first question a
		# bring-up asks.
		print("lobby: listening on port %d as player %d — dial %s"
				% [host_port, Net.local_player_id(), ", ".join(_own_addresses())])
	elif not _wants_peers() and _lobby == Lobby.HOSTING:
		# The last advertised slot just closed, so stop listening. Reachable only while
		# no peer has arrived -- a slot with somebody in it has its dropdown disabled.
		Net.leave()
		_lobby = Lobby.LOCAL
		_slot_peers.clear()
		# The host closed the slot itself, so `session_ended`'s "left" is not news.
		_say("")

	_publish_lobby()
	_refresh_lobby()


## WHOSE SIDE A SLOT IS ON CHANGED (2026-08-31).
##
## NO `regenerate()`, for `_on_starting_age_selected`'s reason: the map is a function of
## the seed, the type and the two player counts, and a team is none of those. **The ring
## of starts is already team-shaped without doing anything** -- `_start_positions`
## spreads players evenly by index, so teams 1,1,2,2 land at 0°/90° against 180°/270° and
## allies are adjacent for free. The one map type that is NOT is the river, whose banks
## alternate by `i % 2` and so split a pair; that is flagged and not fixed here, because
## teams would have to be threaded through `MapGenerator.generate` for one map type.
##
## It publishes, because a player who agreed to a duel is being asked to play a 2v1.
func _on_team_selected(item: int, index: int) -> void:
	_teams[index] = (_slot_rows[index]["team"] as OptionButton).get_item_id(item)
	# The MAP panel's line carries the split and the one-side refusal, and neither of
	# them is the map -- see `_refresh_status`.
	_refresh_status()
	_publish_lobby()
	_refresh_lobby()


## Whether any slot is waiting for a person on another device.
func _wants_peers() -> bool:
	for i in range(_slots):
		if _roles[i] == Role.OPEN:
			return true
	return false


## Advertised slots that nobody is standing in yet. START waits on this reaching zero:
## starting with an empty OPEN slot would launch a match one player short of the one the
## host set up.
func unfilled_slots() -> int:
	var count := 0
	for i in range(_slots):
		if _roles[i] == Role.OPEN and not _slot_peers.has(i):
			count += 1
	return count


# ── lobby ───────────────────────────────────────────────────────────────────

func _on_join_pressed() -> void:
	var ip := _join_field.text.strip_edges()
	if ip.is_empty():
		_say("type the host's address first")
		return
	if _lobby != Lobby.LOCAL:
		_say("already in a session -- go Back to leave it")
		return

	var err := Net.join(ip, Net.PORT)
	if err != OK:
		_say("join failed: %s" % error_string(err))
		return
	_lobby = Lobby.JOINED
	_say("dialling %s:%d..." % [ip, Net.PORT])
	_refresh_lobby()


## A peer arrived. It takes a slot and is SHOWN taking it -- the host presses START, which
## is the whole difference between this screen and the throwaway (g) one that started the
## match the instant anybody connected.
func _on_peer_joined(peer_id: int) -> void:
	var pid: int = int(Net.peer_players().get(peer_id, 0))
	var slot := _slot_for(pid)
	if slot < 0:
		# Nowhere to put them. Only reachable if a peer beats a role change, and saying so
		# beats a screen that quietly ignores somebody who did connect.
		_say("a peer connected with no open slot to take")
		return
	_slot_peers[slot] = peer_id
	# Said BEFORE the refresh, not after: the refresh rebuilds the standing summary --
	# which lists this peer by name anyway -- and a `_say` afterwards would replace that
	# whole peer list with one line about one arrival. The log still gets both.
	_say("player %d joined slot %d (peer %d)" % [pid, slot + 1, peer_id])
	# THE FIRST THING A NEW ARRIVAL IS OWED. Until this call existed, a joining player
	# learned nothing about the match until it had already started.
	Net.broadcast_lobby_config(build_config())
	_refresh_lobby()

	_maybe_autostart()


## `--autostart`, re-checked on every event that could satisfy it. Peer arrival is not
## enough on its own any more: the lobby also waits on agreement, so the moment that
## makes a start legal is usually somebody pressing READY, not somebody connecting.
func _maybe_autostart() -> void:
	if _autostart and can_start():
		_say("autostart: lobby full and everyone agreed, starting")
		_on_start_pressed()


func _on_peer_left(peer_id: int) -> void:
	for slot in _slot_peers.keys():
		if _slot_peers[slot] == peer_id:
			_slot_peers.erase(slot)
			break
	_refresh_lobby()


## Which slot a joining player belongs in.
##
## Prefers the slot matching their player id, since `Net` hands out 1..N in join order and
## `build_config()` numbers slots the same way -- so on the two-player match this screen
## offers, player 2 lands in slot 2 and the peer list reads the way the rows do. Falls
## back to the first free advertised slot rather than refusing, because a mismatch here
## is a cosmetic disagreement and dropping a connected player is not.
func _slot_for(player_id: int) -> int:
	var preferred := player_id - 1
	if preferred >= 0 and preferred < _slots \
			and _roles[preferred] == Role.OPEN and not _slot_peers.has(preferred):
		return preferred
	for i in range(_slots):
		if _roles[i] == Role.OPEN and not _slot_peers.has(i):
			return i
	return -1


## THE HOST'S MATCH, ARRIVING WHILE THERE IS STILL TIME TO LOOK AT IT.
##
## Adopted into this screen's own fields rather than rendered through a second read-only
## path, so the joined screen literally IS the host's screen with the controls off: one
## set of widgets, one preview, no chance of the two drifting into disagreement about what
## a config means. Safe precisely because everything is disabled here -- nothing this
## device does can write back into it.
##
## And it resets this device's READY, because a new proposal is a new question. The host
## side cancels every agreement at the same moment (`broadcast_lobby_config`), so the two
## sides agree that consent does not survive a change.
func _on_lobby_config_received() -> void:
	var cfg := Net.lobby_config()
	if cfg == null:
		return

	_seed = cfg.seed
	_type = cfg.map_type
	_mode = cfg.mode
	_starting_age = cfg.starting_age
	_data = cfg.map_data

	# THE SLOT COUNT FIRST, and rebuild the rows to match it, because a host on eight
	# slots and a client still showing two would leave six of the host's players with no
	# row to appear in -- the joining player would be reading a two-player lobby for an
	# eight-player match.
	#
	# The wire carries the PLAYERS, not the slots, and the difference between them is
	# whatever the host closed. That gap cannot be recovered from the config and does not
	# need to be: a closed slot has nobody in it, so there is nobody for it to misdescribe.
	# What the joiner shows is one row per actual player.
	var incoming := maxi(cfg.player_ids.size(), _MIN_PLAYERS)
	if incoming != _slots:
		_slots = mini(incoming, _MAX_OFFERED_PLAYERS)
		_count_picker.select(_count_picker.get_item_index(_slots))
		_rebuild_slot_rows()

	for i in range(mini(_colours.size(), cfg.colours.size())):
		_colours[i] = cfg.colours[i]
		_refresh_colour_button(i)

	# THE TEAMS, which the joining player is agreeing to as much as they are agreeing to
	# the map. A host on an older build sends no `teams` at all and this leaves every row
	# unaligned -- the free-for-all that host is actually running.
	#
	# Guarded on the item existing, `starting_age`'s guard and for its reason: the number
	# arrives off the wire, and a host offering more sides than this build lists would
	# otherwise select nothing and silently show `–`.
	for i in range(mini(_slot_rows.size(), cfg.teams.size())):
		_teams[i] = int(cfg.teams[i])
		var picker: OptionButton = _slot_rows[i]["team"]
		var item := picker.get_item_index(_teams[i])
		if item >= 0:
			picker.select(item)

	# THE ROLES TOO, which the first version of this forgot -- so a joined client kept its
	# own local defaults and showed Player 2 as "PlayTest AI" while the host showed the
	# same chair as "Open". The joining player was reading that about their own seat.
	#
	# `ai_players` is what the wire carries, and it is enough: a bot is a bot, and every
	# other chair holds a person. It cannot tell the host's own seat from a remote one and
	# does not need to -- which chair is YOURS comes from `local_player_id()`, and the row
	# label says so.
	#
	# The LEVEL rides along, so a joiner sees "AI (Passive)" where the host set one
	# rather than a generic bot. `ai_levels` may be shorter or absent -- from a host
	# built before difficulty existed -- and each bot then falls back to Easy, which is
	# the AI that host is actually running.
	for i in range(mini(_slot_rows.size(), cfg.ai_players.size())):
		if cfg.ai_players[i]:
			var level: int = int(cfg.ai_levels[i]) if i < cfg.ai_levels.size() \
					else SimPlayer.AILevel.EASY
			_roles[i] = _role_for_level(level)
		else:
			_roles[i] = Role.HUMAN
		var picker: OptionButton = _slot_rows[i]["role"]
		picker.select(picker.get_item_index(int(_roles[i])))

	_seed_box.set_value_no_signal(_seed)
	_type_picker.select(_type_picker.get_item_index(int(_type)))
	_mode_picker.select(_mode_picker.get_item_index(int(_mode)))
	# Guarded, unlike the two above: `starting_age` comes off the wire and a host on a
	# longer ages.json than this build would name an age with no item to select.
	var age_item := _age_picker.get_item_index(_starting_age)
	if age_item >= 0:
		_age_picker.select(age_item)
	if _data != null:
		_preview.show_map(_data)

	_am_ready = false
	_say("player %d — review the match, then press READY" % Net.local_player_id())
	_refresh_lobby()

	if _autoready:
		# The scripted side of a two-machine test agreeing on cue. It presses the real
		# button's handler, so it agrees to a proposal it has actually received -- which
		# is the whole rule, just without a thumb.
		_on_ready_pressed()


func _on_ready_pressed() -> void:
	_am_ready = not _am_ready
	Net.set_lobby_ready(_am_ready)
	_say("ready: %s" % _am_ready)
	_refresh_lobby()


## Somebody's answer changed, on the host. START may have just become available, or may
## have just stopped being.
func _on_lobby_ready_changed(_peer_id: int, _ready: bool) -> void:
	_refresh_lobby()
	_maybe_autostart()


## The host has described the match, so this client can draw it. Only ever fires on a
## JOINED screen: a host had the config in its hand when it pressed START.
func _on_match_configured() -> void:
	_say("match received -- entering")
	if is_inside_tree():
		get_tree().change_scene_to_file(_GAME_SCENE)


func _on_session_ended(reason: String) -> void:
	_lobby = Lobby.LOCAL
	_slot_peers.clear()
	_say("session ended: %s" % reason)
	_refresh_lobby()


## Puts every control into the state the current lobby mode calls for, and says what the
## screen is waiting for. One function so the modes cannot drift apart: every path that
## changes anything ends here.
func _refresh_lobby() -> void:
	var joined := _lobby == Lobby.JOINED

	# A joined client configures NOTHING. The host's settings are the match's settings, so
	# a live control here would be a lie about who decides. Every one of these was found
	# by LOOKING at the joined screen rather than by reasoning about it: Re-generate, the
	# player count and the victory picker were all still live in the first version.
	_seed_box.editable = not joined
	_type_picker.disabled = joined
	_reroll_button.disabled = joined
	_mode_picker.disabled = joined
	_age_picker.disabled = joined
	_count_picker.disabled = joined or _MAX_OFFERED_PLAYERS <= MapGenerator.MIN_PLAYERS

	# THE PREVIEW SHOWS THE HOST'S MAP, ONCE THERE IS ONE. A joined client used to
	# generate its own random map on the way in and show THAT -- a picture of a map it
	# will never play, captioned "ready" -- so the preview was hidden. Now the host sends
	# its config to the lobby and the client adopts it, so there is a real map to show;
	# it stays hidden only in the gap before the first one arrives, which is the only
	# moment this device genuinely does not know.
	_preview.visible = not joined or Net.lobby_config() != null

	# The joining player's answer, and only theirs.
	_ready_button.visible = joined
	_ready_button.disabled = joined and Net.lobby_config() == null
	_ready_button.text = "NOT READY" if _am_ready else "READY"
	for i in range(_slot_rows.size()):
		var role_picker: OptionButton = _slot_rows[i]["role"]
		# A slot somebody is standing in cannot be un-opened. Simpler than deciding what
		# happens to a connected player when their chair is taken away.
		role_picker.disabled = joined or _slot_peers.has(i)
		# Your own colour stays live on a joined client. Everyone else's is theirs.
		(_slot_rows[i]["colour"] as Button).disabled = joined and i != _local_slot()
		# TEAMS ARE THE HOST'S, INCLUDING YOUR OWN -- unlike the swatch two lines up,
		# and the difference is what the two settings ARE. A colour is your identity and
		# affects nobody else; a team is the SHAPE OF THE MATCH, and a joiner who could
		# put themselves on the host's side would be rewriting a 1v1 into a 2v0 that
		# nobody agreed to. It is a term of the invitation, so it arrives with the rest
		# of them and READY is how you answer it.
		(_slot_rows[i]["team"] as OptionButton).disabled = joined

	if joined:
		var cfg := Net.lobby_config()
		_status.text = "Waiting for the host's settings" if cfg == null \
				else _invitation_terms(cfg)
		_status.add_theme_color_override("font_color", HudStyle.GOLD)

	_join_field.editable = _lobby == Lobby.LOCAL
	_join_button.disabled = _lobby != Lobby.LOCAL

	_refresh_start_button()
	_refresh_slot_rows()
	_refresh_chat_players()
	_refresh_lobby_text()


## Put the lobby's roster into the chat board's player tabs.
##
## BUILT FROM THE SLOTS, not from a snapshot, because before a match there is no
## snapshot -- and the shape is the same `player_state` dictionary `SnapshotSystem`
## sends, so `ChatBoard` needs no second entry point. Only ACTIVE slots and numbered
## 1..N over them, exactly as `build_config()` compacts them, or a chat tab would name a
## player who will not be in the match.
##
## Called from `_refresh_lobby`, which every path that changes anything ends at, so a
## colour change or a closed slot moves the tabs with the rows.
func _refresh_chat_players() -> void:
	if _chat == null:
		return
	var state: Dictionary = {}
	var local_id := 1
	var active := _active_slots()
	for n in range(active.size()):
		var slot: int = active[n]
		state[n + 1] = {"colour": _colours[slot], "defeated": false}
		if slot == _local_slot():
			local_id = n + 1
	_chat.show_players(state, local_id)


## What the joining player is being asked to agree TO, in one line. The host's screen
## has these as live controls; here they are the terms of the invitation.
##
## The RESOLVED type, not the requested one -- the same thing `regenerate()` shows the
## host. `map_type` records what was ASKED FOR, so a random pick reads as "Random" while
## the map in front of you is plainly a desert; on the host's own screen that reads as
## "Desert". Telling the two sides different things about one map is the last thing a
## consent screen should do.
##
## The starting age is on this line for the same reason the victory mode is: it is a
## term of the invitation, the joining device cannot change it, and its picker is greyed
## out -- so if it is not written here the joiner is agreeing to a match whose opening
## age they were never told.
func _invitation_terms(cfg: MatchConfig) -> String:
	var resolved := cfg.map_type
	if cfg.map_data != null:
		resolved = cfg.map_data.meta.get("type", cfg.map_type) as MapGenerator.Type
	# THE TEAM SPLIT IS A TERM OF THE INVITATION and one of the more important ones: a
	# player who presses READY on what they read as a duel and lands in a 2v1 has agreed
	# to something else. Built from the CONFIG rather than from `_teams`, like every
	# other figure on this line, so a joiner reads what the host sent.
	return "%s, %d x %d — seed %d — %s — from %s%s" % [
			MapGenerator.type_name(resolved), cfg.map_size.x, cfg.map_size.y, cfg.seed,
			MatchConfig.mode_name(cfg.mode), _age_label(cfg.starting_age),
			_summarise_teams(cfg.teams)]


## The team split of the slots as they stand, for the host's own status line.
func _team_suffix() -> String:
	var sides: Array[int] = []
	for i in _active_slots():
		sides.append(_teams[i])
	return _summarise_teams(sides)


## " — 2v2", or nothing at all when nobody is on a team.
##
## SILENT IN A FREE-FOR-ALL, deliberately: "1v1v1v1" is a true description of every
## match this game has ever played and adding it to the line would be four characters
## of news per player. The suffix appears when somebody has actually made a team, which
## is also the moment it starts being worth reading.
##
## Sizes descending, so "2v1" rather than "1v2" -- the bigger side leads, the same
## convention the genre uses and the same one `UnitDef.attack_volley` was pinned as an
## ORDERING for. Unaligned players are each their own side, which is what they are.
static func _summarise_teams(sides: Array) -> String:
	var counts: Dictionary = {}
	var loose := 0
	for i in range(sides.size()):
		var t := int(sides[i])
		if t <= 0:
			loose += 1
			continue
		counts[t] = int(counts.get(t, 0)) + 1
	if counts.is_empty():
		return ""
	var group_sizes: Array[int] = []
	for t in counts:
		group_sizes.append(int(counts[t]))
	for i in range(loose):
		group_sizes.append(1)
	group_sizes.sort()
	group_sizes.reverse()
	var parts: Array[String] = []
	for n in group_sizes:
		parts.append(str(n))
	return " — %s" % "v".join(parts)


func _refresh_lobby_text() -> void:
	# ⚠️ **THE TERMS HAVE TO BE WHERE THE READY BUTTON IS.** They are also in the MAP
	# SETUP panel, beside the map they describe -- which was their only home until
	# 2026-08-30, and the rework put that panel in a scrolling column where it sits
	# below the fold. A joining player was being asked to agree to a match whose terms
	# were off the bottom of the screen, which is the one failure a consent screen may
	# not have.
	#
	# ITS OWN LABEL rather than `_lobby_status`, which moved into the chat frame when
	# the footer was cut to one row. The dial addresses are fine over there; the terms
	# of an invitation are not, because they belong beside the button that accepts them.
	# Hidden entirely otherwise, so a host's footer is buttons and nothing else.
	_terms_label.visible = _lobby == Lobby.JOINED
	if _terms_label.visible:
		var terms_cfg := Net.lobby_config()
		_terms_label.text = "Waiting for the host's settings" if terms_cfg == null \
				else "%s — press READY to agree" % _invitation_terms(terms_cfg)

	match _lobby:
		Lobby.HOSTING:
			# JUST THE TRANSPORT. Who is in which chair is on the chairs now, in
			# `_refresh_slot_rows` -- this line is only the thing the rows cannot say,
			# which is where to dial to reach them.
			_lobby_status.text = "Waiting on port %d — dial %s" \
					% [host_port, ", ".join(_own_addresses())]
		_:
			# LEFT ALONE ON PURPOSE, rather than cleared. `Net.leave()` emits
			# `session_ended` synchronously, so this runs immediately after -- and
			# clearing here would wipe the reason a session ended at exactly the moment
			# the reason matters most, turning a dropped host into a screen that says
			# nothing. Whoever wants the line blank says so with `_say("")`.
			pass


## Which slot is this device's own player.
##
## `local_player_id()` is 0 until a session hands one out, and a plain skirmish never
## does -- but the human at this keyboard is player 1 there, so 0 reads as slot 0 rather
## than as "nobody".
func _local_slot() -> int:
	var pid := Net.local_player_id()
	return (pid - 1) if pid > 0 else 0


## THE PLAYER LIST. Rendered from the same fields on both devices, which is the whole
## point: the host's screen said Player 2 was "Open" while the joiner's said the same
## chair was a "PlayTest AI", and the joining player was reading that about themselves.
func _refresh_slot_rows() -> void:
	for i in range(_slot_rows.size()):
		var name_label: Label = _slot_rows[i]["name"]
		var status: Label = _slot_rows[i]["status"]

		# THE NAME IS JUST THE NAME NOW. "(you)" used to be appended to it; since
		# 2026-08-30 the identity line under it carries that, along with "bot" and
		# whichever peer is sitting here -- the owner asked for the three to share one
		# place, and they are three answers to the same question. Role still lives only
		# in the role picker, which is the separation that got "Open (waiting)"
		# shortened to "Open".
		var mine := i == _local_slot() and _roles[i] != Role.PLAYTEST_AI
		name_label.text = "Player %d" % (i + 1)
		status.text = _slot_status(i, mine)


## What to say about one chair. Deliberately one function rather than a host version and
## a client version: two renderers is how the two devices came to disagree.
func _slot_status(index: int, mine: bool) -> String:
	if _roles[index] == Role.CLOSED:
		# Says what a closed slot is FOR, since leaving it blank reads as an oversight:
		# the room is still on the board, there is just nobody in it.
		#
		# TWO WORDS, cut down from "empty — room kept on the map" on 2026-08-30. The line
		# is now an 84 px column under the name and it wraps, so the long version was four
		# lines per closed slot and an eight-slot lobby was mostly this sentence. The word
		# "empty" went with it because the dropdown two inches to the right already says
		# "Closed" -- what it did not say, and this does, is that the ROOM is still there.
		return "room kept"
	if _roles[index] == Role.PLAYTEST_AI:
		return "bot"

	if _lobby == Lobby.JOINED:
		# A client knows its own answer and that player 1 is whoever it dialled. It does
		# NOT know whether a third player has readied -- the host is the only side
		# counting agreement -- so it says nothing rather than guessing.
		if mine:
			return "you — READY" if _am_ready else "you — reviewing..."
		return "host" if index == 0 else ""

	if _roles[index] == Role.OPEN:
		if not _slot_peers.has(index):
			return "waiting for a player"
		# READY IS THE PART THAT MATTERS. "Joined" only says a socket connected, and
		# START is held on agreement, so the host has to see which of the two it is
		# still waiting for.
		return "peer %d — READY" % int(_slot_peers[index]) \
				if Net.is_peer_ready(int(_slot_peers[index])) \
				else "peer %d — reviewing..." % int(_slot_peers[index])

	return "you" if mine else ""


## Every address this device answers on, so the other one knows what to dial.
##
## Three things are filtered out, and the third was found by photographing this screen:
## loopback and IPv6 are not what you type into another phone, and **169.254.x.x is
## link-local** -- the address an interface gives itself when DHCP failed, which nothing
## on the network can route to. A dev laptop has one per idle adapter, and the first
## version of this line offered NINE addresses of which five were unreachable, wrapped
## onto two rows, and pushed the rest of the screen down. This line exists to be read off
## one screen and typed into another, so a wrong candidate on it costs a failed attempt.
func _own_addresses() -> Array[String]:
	var out: Array[String] = []
	for a in IP.get_local_addresses():
		var s := String(a)
		if s.begins_with("127.") or s.begins_with("169.254.") or s.contains(":"):
			continue
		out.append(s)
	if out.is_empty():
		out.append("no network address")
	return out


func _say(text: String) -> void:
	if _lobby_status != null:
		_lobby_status.text = text
	# On stdout as well, because a scripted side of a two-machine test has nobody
	# watching the label -- the log is the only way to follow a bring-up. Same reason
	# the throwaway (g) screen did it. Clearing the line is not news, so it is not logged.
	if not text.is_empty():
		print("lobby: %s" % text)


# ── driving it from a terminal ───────────────────────────────────────────────
#
# Two devices, and only one of them has somebody standing at a keyboard -- so the other
# side has to be startable from a command line. The throwaway (g) screen established
# this; it is kept because the need did not go away with it.
#
#   Godot --path game res://scenes/menu/Skirmish.tscn -- --net host --autostart
#   Godot --path game res://scenes/menu/Skirmish.tscn -- --net join --ip 1.2.3.4 --autoready
#
# `--autostart` is HOST ONLY and presses START the moment the lobby is full and everyone
# has agreed. `--autoready` is JOINER ONLY and presses READY when the host's proposal
# arrives. Both automate the press, not the rule -- each still waits for exactly what a
# thumb would wait for, which is why the ready gate cannot be skipped by scripting it.
func _apply_cmdline() -> void:
	_autostart = _has_flag("--autostart")
	_autoready = _has_flag("--autoready")
	match _string_arg("--net", ""):
		"host":
			# Deferred so the node is in the tree first: opening a slot can reach
			# `get_tree()` by way of a start, and a peer could in principle be waiting.
			call_deferred("_host_from_cmdline")
		"join":
			_join_field.text = _string_arg("--ip", "127.0.0.1")
			call_deferred("_on_join_pressed")


## Advertise the LAST slot, which is the one a second player would take: slot 1 is this
## device's own human seat in every default this screen ships with.
func _host_from_cmdline() -> void:
	var index := _slots - 1
	var picker: OptionButton = _slot_rows[index]["role"]
	var item := picker.get_item_index(int(Role.OPEN))
	picker.select(item)
	picker.item_selected.emit(item)


func _has_flag(name: String) -> bool:
	return OS.get_cmdline_user_args().has(name)


func _string_arg(name: String, fallback: String) -> String:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		if args[i] == name:
			return String(args[i + 1])
	return fallback


## TWO WAYS TO START, because there are two kinds of match and only one of them has a
## session already running.
##
## A skirmish leaves the config on `Net.pending_match` and lets `GameScene._ready()` call
## `host_solo()`, which consumes it. A HOSTED match must not go that way: the socket has
## been open since the slot was advertised, so `GameScene` sees `has_session()` and
## deliberately does not host over the top of it -- meaning nothing would ever consume
## `pending_match` and the client would never be told what it is playing. `start_match()`
## is the call that settles the config and broadcasts it, so the host makes it HERE,
## before the scene change, exactly as the proven (g) path did.
func _on_start_pressed() -> void:
	if not can_start():
		return
	var cfg := build_config()
	start_requested.emit(cfg)

	if _lobby == Lobby.HOSTING:
		# The clock stays held until every joiner reports ready (12.1d), so starting the
		# world a moment before this device's own view exists loses nothing.
		Net.start_match(cfg)
	else:
		Net.pending_match = cfg
	get_tree().change_scene_to_file(_GAME_SCENE)


## Leaves the session on the way out. Without this the socket outlives the screen that
## opened it: the main menu would be sitting on a listening host, and the next PLAY would
## find `has_session()` true and never start a match at all.
func _on_back_pressed() -> void:
	if _lobby != Lobby.LOCAL:
		Net.leave()
		_lobby = Lobby.LOCAL
		_slot_peers.clear()
	back_requested.emit()
	get_tree().change_scene_to_file(_MAIN_MENU_SCENE)


## How many colours the palette has. Asked of the data rather than restated here: the
## palette IS `colours.json` (§9), its order is a contract pinned by tests, and a second
## copy of it in the UI is a copy that drifts.
func _palette_size() -> int:
	if GameDataRegistry == null:
		return 8
	return maxi(1, GameDataRegistry.colour_count())


## The slot's colour button, drawn AS the colour rather than as its name written in it.
##
## It used to be the name in coloured text on the default button background. That was
## legible enough at eight distinct hues and stopped being the right thing the moment the
## picker existed: the grid this button opens is flat blocks of colour, so a button that
## previewed the choice differently from the way the choice is made is one more thing to
## compare. Now the row and the grid draw a swatch the same way.
func _refresh_colour_button(index: int) -> void:
	var button: Button = _slot_rows[index]["colour"]
	var palette_index: int = _colours[index]
	if GameDataRegistry == null:
		button.text = "Colour %d" % (palette_index + 1)
		return

	var colour := GameDataRegistry.colour(palette_index)
	button.text = String(GameDataRegistry.colour_slug(palette_index)) \
			.trim_prefix("colour.").capitalize()

	var style := StyleBoxFlat.new()
	style.bg_color = colour
	style.border_color = Color(0.0, 0.0, 0.0, 0.6)
	style.set_border_width_all(1)
	style.set_content_margin_all(6)
	button.add_theme_stylebox_override("normal", style)
	var lit := style.duplicate() as StyleBoxFlat
	lit.bg_color = colour.lightened(0.15)
	button.add_theme_stylebox_override("hover", lit)
	button.add_theme_stylebox_override("pressed", lit)
	button.add_theme_stylebox_override("focus", style)
	# A DISABLED SWATCH STILL SHOWS ITS COLOUR, dimmed. Every colour button but your
	# own is disabled on a joined client (`_refresh_lobby`), and left to the theme's
	# default those rows would all go grey -- which on this screen means the player
	# list stops saying who is which colour, the one thing it exists to say.
	var dim := style.duplicate() as StyleBoxFlat
	dim.bg_color = Color(colour, 0.55)
	button.add_theme_stylebox_override("disabled", dim)

	# Black on yellow, white on blue: the palette deliberately spans L* 36 to 100
	# (colours.json's ladder), so one fixed ink colour is illegible at one end of it.
	var ink := Color.BLACK if colour.get_luminance() > 0.5 else Color.WHITE
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		button.add_theme_color_override(state, ink)
	button.add_theme_color_override("font_disabled_color", Color(ink, 0.7))
