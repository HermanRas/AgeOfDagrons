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
## **NO LONGER A WIREFRAME, 2026-08-29.** `techs.json` filled in with 9.3 and this page
## fills in with it -- which is what the note replaced here predicted, and the whole
## reason the renderer was written before the data: it walks
## `GameDataRegistry.tech_ids()` and lays each tech out in its age's column, with its
## prerequisites named. The placeholder lattice is still below and still correct: it is
## what an empty `techs.json` draws, and an empty page shows the owner nothing while
## they are drawing art against this layout.
##
## THREE STATES, and the third one finally exists. RESEARCHED was drawn by the legend
## and never assigned, because `SimPlayer.researched` was a field the HUD read that
## nothing wrote -- the same hole 4.11's population counter was in. `SimWorld.grant_tech`
## writes it now and `player_state` carries it, so a node is RESEARCHED if the viewer
## holds it, AVAILABLE if its age has been reached, and LOCKED otherwise.
##
## It is the VIEWER's own set, not the selection's: this page is a reference about what
## you have and what you could have, and there is nothing on it to press.
class_name TechTreePanel
extends HudPanel

enum State { LOCKED, AVAILABLE, RESEARCHED }

## The lattice drawn when no techs are declared. Four rows so each age column has
## the same height, which is what makes the grid read as a grid.
const _PLACEHOLDER_ROWS := 4

## Widened and heightened for 9.3's real data: a node's subtitle now names the
## BUILDING that offers it, which is the whole point of the page and does not fit in
## 74 px beside "Gold Shaft Mining". The columns scroll both ways, so the cost of
## being wrong here is a scroll rather than clipped text.
const _NODE_SIZE := Vector2(120.0, 76.0)

var _columns: HBoxContainer
var _legend: Label

## Which age the local player has reached, so a column can be drawn as reached or
## not. 0 before the first snapshot, which draws everything locked.
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

	# The four age columns SCROLL, and as of 9.3 they scroll BOTH WAYS. Sideways was
	# always the plan; vertical became necessary the moment the data landed, because
	# the blacksmith alone puts twelve technologies in the tree and age 3's column is
	# eleven nodes tall -- roughly 750 px against a page that has less. A page that
	# grew past its own frame is the failure mode `ResourceHUD` records at length, and
	# it would have been silent here: the overflowing nodes simply would not be drawn.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
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


## Which technologies the viewer holds, `tech id -> true` (`GameView.researched_of`).
## Rebuilds only when the SET actually changes, for `set_age`'s reason: this is fed
## every tick the page is open and a rebuild per tick would throw the page away ten
## times a second under somebody's finger. A research lands once a minute at most.
func set_researched(held: Dictionary) -> void:
	if held == _researched:
		return
	_researched = held
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
		# THE PLACEHOLDER LATTICE IS ALL-OR-NOTHING, and that changed with 9.3. It used
		# to fill any empty column, which was right while every column was empty and
		# became a lie the moment one was not: age 1 has no technologies by design --
		# there is nothing to research before you have a blacksmith -- and four "?"
		# boxes there would promise an age-1 tier that is never coming.
		_columns.add_child(_age_column(age, by_age.get(age, []), declared == 0))

	if declared == 0:
		_legend.text = "Wireframe — no technologies are declared yet (techs.json is " \
				+ "empty until PLAN.md 9.3). The columns and states below are the layout; " \
				+ "the nodes are placeholders. Research happens at the building that " \
				+ "offers it, never on this page."
	else:
		_legend.text = "%d technologies. " % declared \
				+ "Research happens at the building named under each one, never here " \
				+ "-- this page is the guide to what is where. Gold means researched, " \
				+ "lit means available in your age, dim means a later age."


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


func _age_column(age: int, techs: Array, placeholder: bool = false) -> Control:
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
	if placeholder:
		for i in range(_PLACEHOLDER_ROWS):
			box.add_child(_node("?", "", State.AVAILABLE if reached else State.LOCKED))
	else:
		for t in techs:
			var def: TechDef = t
			box.add_child(_node(def.name, _subtitle_for(def), _state_of(def, reached)))

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)
	return box


## RESEARCHED beats everything, then the age gate. A tech the viewer holds is drawn as
## held whatever else is true of it -- which matters at all only because an age can
## never go backwards, so the two can in fact never disagree; stating the precedence
## anyway is what stops the next state added here from being ordered by accident.
func _state_of(def: TechDef, reached: bool) -> State:
	if bool(_researched.get(def.id, false)):
		return State.RESEARCHED
	return State.AVAILABLE if reached else State.LOCKED


## The line under a node's name: WHERE IT IS BOUGHT, and what it needs first.
##
## The building is the point of this whole page. The project owner's ruling of
## 2026-08-29 — *"tech tree on mini map is only a visual guide letting you know what
## buildings hold what upgrades"* — is what this line delivers, and without it the page
## is a list of names with nothing to do about any of them. Research happens at the
## building, so telling you which building IS the reference.
func _subtitle_for(def: TechDef) -> String:
	var parts: Array[String] = []
	var where := _researched_at_text(def)
	if not where.is_empty():
		parts.append(where)
	var needs := _requires_text(def)
	if not needs.is_empty():
		parts.append(needs)
	return "\n".join(parts)


## Where a tech is bought, by the building's display name. Several is legal in the
## schema and none exists today; joined with "or" rather than a comma, because a list
## of buildings reads as "all of these" otherwise and it means "any of these".
func _researched_at_text(def: TechDef) -> String:
	var names: Array[String] = []
	for id in def.researched_at:
		var bd: BuildingDef = GameDataRegistry.building(id)
		names.append(bd.name if bd != null and not bd.name.is_empty() else String(id))
	return " or ".join(names)


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
