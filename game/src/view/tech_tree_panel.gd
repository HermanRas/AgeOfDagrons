## The TECHNOLOGY TREE page behind the minimap's bottom-left corner button
## (PLAN.md 9.4).
##
## READ-ONLY, AND THAT IS THE DESIGN RATHER THAN THE SHORTCUT. The project owner's
## rule: researching happens at the building that offers it, the way training does,
## and this page is where you go to find out what exists and what it needs. So
## there is nothing to press here and no command behind it -- which also means the
## page can never disagree with the server about anything, because it asks for
## nothing.
##
## A WIREFRAME TODAY, because `techs.json` is deliberately empty until 9.3 (its own
## note says so). What is NOT a wireframe is the renderer: it walks
## `GameDataRegistry.tech_ids()` and lays each tech out in its age's column, with
## its prerequisites named and its state taken from the local player's age -- so on
## the day 9.3 fills the data in, this page fills in with it and nothing here
## changes. The placeholder lattice below is what it draws when that walk comes
## back empty, and it exists for one reason: the owner is drawing art against this
## layout and an empty page shows them nothing.
##
## THREE STATES, and they are all the page can honestly know. `SimPlayer` has no
## researched-tech field yet -- adding one would be 9.3's job, and a field the HUD
## reads that nothing writes is exactly the hole 4.11's population counter was
## before it was enforced. So a node is AVAILABLE if its age has been reached and
## LOCKED otherwise; RESEARCHED is drawn by the legend and never assigned, which is
## honest about the gap rather than faking a third state out of nothing.
class_name TechTreePanel
extends HudPanel

enum State { LOCKED, AVAILABLE, RESEARCHED }

## The lattice drawn when no techs are declared. Four rows so each age column has
## the same height, which is what makes the grid read as a grid.
const _PLACEHOLDER_ROWS := 4

const _NODE_SIZE := Vector2(74.0, 62.0)

var _columns: HBoxContainer
var _legend: Label

## Which age the local player has reached, so a column can be drawn as reached or
## not. 0 before the first snapshot, which draws everything locked.
var _age: int = 0


func _init() -> void:
	# The chrome, and it is not optional -- see `HudPanel._init`.
	super()
	set_title("TECHNOLOGY TREE")

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	body.add_child(column)

	# The four age columns SCROLL SIDEWAYS. Four fit today; a filled-in tree will
	# not, and a page that grew past its own frame is the failure mode `ResourceHUD`
	# records at length.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	_columns = HBoxContainer.new()
	_columns.add_theme_constant_override("separation", 18)
	_columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(_columns)

	_legend = HudPanel.note_label("")
	column.add_child(_legend)

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


## Public so a test and a preview can drive it without a snapshot.
func rebuild() -> void:
	for child in _columns.get_children():
		_columns.remove_child(child)
		child.queue_free()

	var by_age := _techs_by_age()
	var declared := 0
	for age in by_age:
		declared += (by_age[age] as Array).size()

	var ages := maxi(1, GameDataRegistry.age_count() if GameDataRegistry != null else 4)
	for age in range(1, ages + 1):
		_columns.add_child(_age_column(age, by_age.get(age, [])))

	if declared == 0:
		_legend.text = "Wireframe — no technologies are declared yet (techs.json is " \
				+ "empty until PLAN.md 9.3). The columns and states below are the layout; " \
				+ "the nodes are placeholders. Research happens at the building that " \
				+ "offers it, never on this page."
	else:
		_legend.text = "%d technologies. Research happens at the building that offers " \
				% declared + "it; this page is the reference. Reached ages are lit, " \
				+ "later ages are locked."


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
	return out


func _age_column(age: int, techs: Array) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)

	# THE AGE'S NAME, not its numeral. ages.json is explicit that this is one of the
	# three places with room for prose -- the HUD badge takes the numeral because it
	# has 648 px of height to spend and this page does not.
	var age_def: AgeDef = GameDataRegistry.age(age) if GameDataRegistry != null else null
	var heading := "%s. %s" % [
			age_def.numeral if age_def != null else str(age),
			age_def.name if age_def != null else "Age %d" % age]
	var header := HudPanel.text_label(heading, 16)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(header)

	var reached := age <= _age
	if techs.is_empty():
		for i in range(_PLACEHOLDER_ROWS):
			box.add_child(_node("?", "", State.AVAILABLE if reached else State.LOCKED))
	else:
		for t in techs:
			var def: TechDef = t
			box.add_child(_node(def.name, _requires_text(def),
					State.AVAILABLE if reached else State.LOCKED))

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)
	return box


## What a node needs before it, in words. The mockup draws prerequisites as lines
## between boxes; lines want a `_draw()` over a laid-out grid and this page is not
## worth that until there are real techs to connect, so the edge is named instead
## of drawn. It is the same information.
func _requires_text(def: TechDef) -> String:
	if def.requires.is_empty():
		return ""
	var names: Array[String] = []
	for id in def.requires:
		var req: TechDef = GameDataRegistry.tech(id)
		names.append(req.name if req != null else String(id))
	return "needs %s" % ", ".join(names)


## One node. Styled by state rather than labelled with it: a locked node is dimmed
## and a reachable one is lit, which is how every tech tree in the genre says this
## and needs no words at a size this small.
func _node(text: String, subtitle: String, state: State) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = _NODE_SIZE

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.35)
	style.set_border_width_all(1)
	style.set_content_margin_all(6)
	match state:
		State.RESEARCHED:
			style.border_color = HudStyle.GOLD
			style.border_width_bottom = 3
		State.AVAILABLE:
			style.border_color = Color(HudStyle.GOLD, 0.8)
		_:
			style.border_color = Color(HudStyle.GOLD, 0.25)
			panel.modulate = Color(1.0, 1.0, 1.0, 0.45)
	panel.add_theme_stylebox_override("panel", style)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 2)
	panel.add_child(rows)

	var label := HudPanel.text_label(text, 14)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(label)
	if not subtitle.is_empty():
		var sub := HudPanel.note_label(subtitle, 11)
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rows.add_child(sub)
	return panel
