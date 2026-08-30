## The TECHNOLOGY TREE page behind the minimap's bottom-left corner button
## (PLAN.md 9.4).
##
## **ROWS, NOT COLUMNS, SINCE 2026-08-30**, on the project owner's ask: *"it reads left
## to right scrollable, age1 at the top with last age at the bottom"*. It was four age
## COLUMNS side by side, which put age 4 off the right of the page and made the ladder
## read across rather than down. Now each age is a row, the ages stack in order, and the
## long ages scroll sideways -- age 3 alone has eleven technologies, which no page is
## wide enough to show at once and which is why "scrollable" was part of the ask rather
## than an implementation detail.
##
## **IT IS STILL READ-ONLY, AND THAT IS THE DESIGN RATHER THAN THE SHORTCUT.** The
## project owner's rule: researching happens at the building that offers it, the way
## training does, and this page is where you go to find out what exists and what it
## needs. Tapping a node opens a DESCRIPTION, never a purchase -- so the page still asks
## the server for nothing and still cannot disagree with it about anything.
##
## THREE STATES: a node is RESEARCHED if the viewer holds it, AVAILABLE if its age has
## been reached, and LOCKED otherwise. It is the VIEWER's own set, not the selection's:
## this page is a reference about what you have and what you could have.
##
## The placeholder lattice below is what an empty `techs.json` draws. It is kept because
## it is still correct -- an empty page shows the owner nothing while they are drawing
## art against this layout -- and because it costs one branch.
class_name TechTreePanel
extends HudPanel

enum State { LOCKED, AVAILABLE, RESEARCHED }

## The lattice drawn when no techs are declared. Four per age so each row has the same
## length, which is what makes the grid read as a grid.
const _PLACEHOLDER_COLUMNS := 4

## One node. SMALLER AND SQUATTER than the 120x76 it was, and the detail box is what
## paid for it: the subtitle used to name the building and the prerequisites on the tile
## itself, which is why it needed the height. Both moved into the box that opens on a
## tap, so a node is now a name and a state -- and eleven of them across a row is that
## much less scrolling.
const _NODE_SIZE := Vector2(104.0, 58.0)

## The fixed-width heading at the left of each age row.
const _HEADING_WIDTH := 132.0

var _rows: VBoxContainer
var _legend: Label
var _detail: TechDetailBox

## Which age the local player has reached, so a row can be drawn as reached or not.
## 0 before the first snapshot, which draws everything locked.
var _age: int = 0

## Which technologies the viewer has bought (PLAN.md 9.3), `tech id -> true`. Empty
## before the first snapshot and for a player who has bought none -- the same answer
## for both, and the right one for both.
var _researched: Dictionary = {}


func _init() -> void:
	# The chrome, and it is not optional -- see `HudPanel._init`.
	super()
	set_title("TECHNOLOGY TREE")

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	body.add_child(column)

	# ONE SCROLL CONTAINER, BOTH WAYS, and the age headings live INSIDE it rather than
	# in a frozen left column. A frozen column would keep "Age III" on screen while you
	# scrolled right through its eleven nodes, which is nicer -- and it costs an exact
	# height agreement between two independent VBoxes, so every row would have to be
	# pinned to a fixed height and the page would break silently the day a node wrapped
	# onto a second line. The rows are far enough apart to be told from each other
	# without the label, and this way nothing has to agree with anything.
	#
	# VERTICAL SCROLLING IS NOT OPTIONAL EITHER, even though four rows fit today: a page
	# that grew past its own frame is the failure mode `ResourceHUD` records at length,
	# and here it would be silent -- the overflowing age simply would not be drawn.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 14)
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows)

	_legend = HudPanel.note_label("")
	column.add_child(_legend)

	# ADDED TO `body` AFTER the column, so it draws over the tree rather than under it.
	# A child of the scrolling rows would scroll away with them and be clipped by the
	# container the moment it was taller than a row.
	_detail = TechDetailBox.new()
	body.add_child(_detail)

	add_close_button()
	rebuild()


## Which age the viewer is in. Called by `GameScene` from the snapshot; rebuilds
## only when the number actually moves, since advancing an age is a once-a-match
## event and rebuilding on every tick would throw the page away ten times a second
## while somebody was reading it.
func set_age(age: int) -> void:
	if age == _age:
		return
	_age = age
	rebuild()


## Which technologies the viewer holds, `tech id -> true` (`GameView.researched_of`).
## Rebuilds only when the SET actually changes, for `set_age`'s reason: this is fed
## every tick the page is open and a rebuild per tick would throw the page away ten
## times a second under somebody's finger. A research lands once a minute at most.
func set_researched(held: Dictionary) -> void:
	if held == _researched:
		return
	_researched = held
	rebuild()


## Closes the detail box along with the page, so reopening the tree does not land on
## whatever node was last read. Overrides `HudPanel.close`.
func close() -> void:
	if _detail != null:
		_detail.hide_detail()
	super()


## Public so a test and a preview can drive it without a snapshot.
func rebuild() -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	# A REBUILD FREES THE NODE THE BOX IS DESCRIBING. It holds a `TechDef` rather than a
	# Control, so it would survive -- but an open box over a tree that has just changed
	# state under it is a box that may now be wrong about "available", and the honest
	# thing is to close it. Rebuilds are rare by construction (see `set_age`).
	if _detail != null:
		_detail.hide_detail()

	var by_age := _techs_by_age()
	var declared := 0
	for age in by_age:
		declared += (by_age[age] as Array).size()

	var ages := maxi(1, GameDataRegistry.age_count() if GameDataRegistry != null else 4)
	for age in range(1, ages + 1):
		# THE PLACEHOLDER LATTICE IS ALL-OR-NOTHING, and that changed with 9.3. It used
		# to fill any empty row, which was right while every row was empty and became a
		# lie the moment one was not: age 1 has no technologies by design -- there is
		# nothing to research before you have a blacksmith -- and four "?" boxes there
		# would promise an age-1 tier that is never coming.
		_rows.add_child(_age_row(age, by_age.get(age, []), declared == 0))

	if declared == 0:
		_legend.text = "Wireframe — no technologies are declared yet (techs.json is " \
				+ "empty until PLAN.md 9.3). The rows and states below are the layout; " \
				+ "the nodes are placeholders. Research happens at the building that " \
				+ "offers it, never on this page."
	else:
		_legend.text = "%d technologies — tap one to read what it does. " % declared \
				+ "Research happens at the building named in the description, never " \
				+ "here. Gold means researched, lit means available in your age, dim " \
				+ "means a later age."


## `age_required` -> the techs that want it. A tech with an age outside the ladder
## is dropped rather than clamped: a typo'd `age_required: 7` should show up as a
## missing node, which somebody notices, and not as a node in age 4, which nobody
## does. `GameDataRegistry.validate()` is where it would be reported.
func _techs_by_age() -> Dictionary:
	var out: Dictionary = {}
	if GameDataRegistry == null:
		return out
	for id in GameDataRegistry.tech_ids():
		var t: TechDef = GameDataRegistry.tech(id)
		if t == null:
			continue
		if not out.has(t.age_required):
			out[t.age_required] = []
		(out[t.age_required] as Array).append(t)
	# RE-SORTED BY DISPLAY NAME, because `tech_ids()` sorts an Array[StringName] and
	# that orders by StringName IDENTITY rather than by content -- arbitrary, and not
	# necessarily the same between two runs (the registry's own note, and
	# `_buildable_details` re-sorts for the same reason). A reference page whose rows
	# move every time you open it is worse than one in a dull order.
	for age in out:
		(out[age] as Array).sort_custom(func(a: TechDef, b: TechDef) -> bool:
			if a.name != b.name:
				return a.name < b.name
			return String(a.id) < String(b.id))
	return out


## One age: its heading, then its technologies left to right.
func _age_row(age: int, techs: Array, placeholder: bool = false) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	# THE AGE'S NAME, not its numeral. ages.json is explicit that this is one of the
	# three places with room for prose -- the HUD badge takes the numeral because it
	# has 648 px of height to spend and this page does not.
	var age_def: AgeDef = GameDataRegistry.age(age) if GameDataRegistry != null else null
	var heading := HudPanel.text_label("%s. %s" % [
			age_def.numeral if age_def != null else str(age),
			age_def.name if age_def != null else "Age %d" % age], 16)
	heading.custom_minimum_size = Vector2(_HEADING_WIDTH, _NODE_SIZE.y)
	heading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# Wrapping is safe HERE and nowhere else in this row, because the minimum width
	# above gives it something to wrap inside -- see the empty-row note below for what
	# an unconstrained autowrapping label in an HBox does.
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# A row the viewer has not reached is dimmed WHOLE, heading included, so the ladder
	# reads at a glance from across the page rather than node by node.
	if age > _age:
		heading.modulate = Color(1.0, 1.0, 1.0, 0.5)
	row.add_child(heading)

	var reached := age <= _age
	if placeholder:
		for i in range(_PLACEHOLDER_COLUMNS):
			row.add_child(_node(null, State.AVAILABLE if reached else State.LOCKED))
	else:
		for t in techs:
			var def: TechDef = t
			row.add_child(_node(def, _state_of(def, reached)))

	if not placeholder and techs.is_empty():
		# AGE 1 IS EMPTY BY DESIGN and an empty row reads as a bug. Says so.
		#
		# AUTOWRAP OFF, and this is not a detail. `HudPanel.note_label` turns it on --
		# right for the legend, wrong for anything in an HBox, because a wrapping label
		# with no minimum width collapses to its narrowest possible box and Godot
		# obligingly wraps it to ONE CHARACTER PER LINE. That is not a hypothetical: it
		# is what the first render of this row did, and the resulting 400 px column of
		# single letters pushed ages 2 to 4 off the bottom of the page.
		var empty := HudPanel.note_label("nothing to research yet", 13)
		empty.autowrap_mode = TextServer.AUTOWRAP_OFF
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(empty)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)
	return row


## RESEARCHED beats everything, then the age gate. A tech the viewer holds is drawn as
## held whatever else is true of it -- which matters at all only because an age can
## never go backwards, so the two can in fact never disagree; stating the precedence
## anyway is what stops the next state added here from being ordered by accident.
func _state_of(def: TechDef, reached: bool) -> State:
	if bool(_researched.get(def.id, false)):
		return State.RESEARCHED
	return State.AVAILABLE if reached else State.LOCKED


## One node. A BUTTON since 2026-08-30, where it used to be a `PanelContainer`.
##
## Styled by state rather than labelled with it: a locked node is dimmed and a
## reachable one is lit, which is how every tech tree in the genre says this and needs
## no words at a size this small.
##
## A LOCKED NODE IS STILL PRESSABLE, deliberately. The description is the reason you
## would tap a locked one at all -- "what is Plate Mail and is it worth planning for"
## is a question about a tech you do not have yet, and disabling the node would answer
## it with silence. Nothing is bought here, so there is nothing to refuse.
##
## `def` null draws the placeholder lattice's "?" and does nothing on a tap.
func _node(def: TechDef, state: State) -> Control:
	var button := Button.new()
	button.custom_minimum_size = _NODE_SIZE
	button.text = def.name if def != null else "?"
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.add_theme_font_size_override("font_size", 13)
	button.focus_mode = Control.FOCUS_NONE

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.35)
	style.set_border_width_all(1)
	style.set_content_margin_all(6)
	style.set_corner_radius_all(3)
	match state:
		State.RESEARCHED:
			style.border_color = HudStyle.GOLD
			style.border_width_bottom = 3
		State.AVAILABLE:
			style.border_color = Color(HudStyle.GOLD, 0.8)
		_:
			style.border_color = Color(HudStyle.GOLD, 0.25)
			button.modulate = Color(1.0, 1.0, 1.0, 0.45)
	# EVERY STATE, or the theme's own plate shows through on hover and press -- the
	# `aod_theme.tres` Button style is a painted nine-patch, and one of these nodes
	# wearing it would read as a completely different control from its neighbours.
	for name in ["normal", "hover", "pressed", "disabled"]:
		button.add_theme_stylebox_override(name, style)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	if def != null:
		button.pressed.connect(_on_node_pressed.bind(def, state))
	return button


func _on_node_pressed(def: TechDef, state: State) -> void:
	_detail.show_tech(def, state, _age)


## The box currently open, or null. For a test and a preview -- pressing the real
## button and then asking what it opened is the check worth having here.
func detail_box() -> TechDetailBox:
	return _detail
