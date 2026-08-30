## The big text box that opens when you tap a technology (project owner, 2026-08-30:
## *"tapping a tech brings up the big text box, showing text explaining the upgrade"*).
##
## Its own class rather than a method on `TechTreePanel` because it is the half of that
## page with the real content in it: a name, what the upgrade does in prose, where it is
## bought, what it costs, how long it takes, what it needs first, and what it actually
## adds. `TechTreePanel` is a layout of buttons; this is what they are for.
##
## READ-ONLY LIKE THE PAGE AROUND IT. There is no BUY button and there is not going to
## be one: the owner's rule is that researching happens at the building that offers it,
## so this box NAMES the building instead. That is also why a LOCKED tech opens exactly
## the same box as an available one -- "what is Plate Mail and should I plan for it" is
## a question about a tech you do not have, and the box that refused to open would be
## answering it with silence.
##
## IT IS AN OVERLAY, not a pane in the layout. A fixed pane would cost the tree a third
## of its height permanently, for something a player looks at for five seconds; and the
## tree scrolls, so a box that lived among the rows would scroll away and be clipped.
##
## THE PROSE AND THE NUMBERS ARE DELIBERATELY SEPARATE. `TechDef.description` says what
## the upgrade is FOR -- what it stacks with, who it skips, whether it is worth the cost
## -- and the facts block underneath is generated from the same `effects` dictionary the
## sim reads. Writing "+1 melee attack" into the description would be the same fact
## twice and, worse, a second copy that can disagree with `techs.json`.
class_name TechDetailBox
extends PanelContainer

## The tech being described, or null when nothing is open. Held rather than read back
## out of the labels, so a test can ask what the box is showing without parsing text.
var tech: TechDef = null

var _title: Label
var _where: Label
var _blurb: Label
var _facts: VBoxContainer
var _state: Label


func _init() -> void:
	visible = false
	# Centred, two thirds wide and most of the body tall. THE HEIGHT IS NOT SPARE ROOM:
	# the fixed rows -- title, state, building, three fact lines and the button -- come
	# to about 230 px before the description has a single line, so a box trimmed to
	# "roughly the size of this text" squeezes the scrolling paragraph to nothing and
	# silently drops the one thing the box exists to show. That is exactly what 0.14 to
	# 0.72 did on its first render.
	#
	# Any slack left over sits INSIDE the scroll, under the text, where it reads as
	# padding; a longer description fills it and then scrolls.
	set_anchors_preset(Control.PRESET_CENTER)
	anchor_left = 0.17
	anchor_right = 0.83
	anchor_top = 0.06
	anchor_bottom = 0.86
	offset_left = 0.0
	offset_right = 0.0
	offset_top = 0.0
	offset_bottom = 0.0
	# STOP. It sits over a page of pressable nodes, and a box you can tap through is a
	# box that opens a different tech while you are reading this one.
	mouse_filter = Control.MOUSE_FILTER_STOP

	# The page's own plate, so the box reads as part of the tree rather than as a system
	# dialog -- but OPAQUE, which the page is not. `page_style` sits at 0.97 alpha
	# deliberately: it covers the running match, and a sliver of it showing through says
	# the clock has not stopped. This box covers a grid of tech names, and 3% of those
	# ghosting through a paragraph of text is just harder to read.
	var style := HudPanel.page_style()
	style.bg_color = Color(style.bg_color, 1.0)
	# 24 all round is right for a page and is a lot to spend on a box this size -- it
	# is 48 px of the height the description needs.
	style.set_content_margin_all(18)
	add_theme_stylebox_override("panel", style)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	add_child(column)

	_title = Label.new()
	UiFont.title(_title, 24)
	_title.add_theme_color_override("font_color", HudStyle.GOLD)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_title)

	_state = HudPanel.text_label("", 15)
	_state.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_state)

	_where = HudPanel.note_label("", 15)
	_where.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_where)

	# THE PROSE, and it is the biggest thing in the box because it is the thing the
	# owner asked for. Scrolls, because a description is free-form text out of a data
	# file and nothing stops the next one being four times as long as these.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	_blurb = HudPanel.text_label("", 17)
	_blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_blurb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_blurb)

	_facts = VBoxContainer.new()
	_facts.add_theme_constant_override("separation", 3)
	column.add_child(_facts)

	# "BACK TO THE TREE", not "CLOSE". The page underneath has a CLOSE of its own and
	# the two are a few centimetres apart; two buttons with the same word on them, one
	# of which leaves the match page entirely, is a press nobody should have to think
	# about. This one says where it goes.
	var close := Button.new()
	close.text = "BACK TO THE TREE"
	close.custom_minimum_size = Vector2(220.0, 42.0)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(hide_detail)
	column.add_child(close)


## Open the box on one technology. `state` and `viewer_age` come from the page, which
## already knows both -- recomputing them here would be a second copy of the rule that
## decides whether a node is lit.
func show_tech(def: TechDef, state: TechTreePanel.State, viewer_age: int) -> void:
	tech = def
	if def == null:
		hide_detail()
		return

	_title.text = def.name
	_state.text = _state_text(def, state, viewer_age)
	_state.add_theme_color_override("font_color",
			HudStyle.GOLD if state == TechTreePanel.State.RESEARCHED
			else Color(HudStyle.GOLD, 0.8))
	_where.text = _where_text(def)
	# A tech with no description still gets a box; it is simply less useful, and saying
	# so is better than an empty panel that looks like a failed load.
	_blurb.text = def.description if not def.description.is_empty() \
			else "No description has been written for this technology yet."

	for child in _facts.get_children():
		_facts.remove_child(child)
		child.queue_free()
	for line in fact_lines(def):
		_facts.add_child(HudPanel.note_label(line, 14))

	visible = true


func hide_detail() -> void:
	tech = null
	visible = false


func is_showing() -> bool:
	return visible


## "Researched" / "Available now" / "Needs the Ember Age".
##
## The locked case NAMES THE AGE rather than saying "locked", because that is the only
## version a player can act on: what they want to know is how far away it is.
func _state_text(def: TechDef, state: TechTreePanel.State, viewer_age: int) -> String:
	match state:
		TechTreePanel.State.RESEARCHED:
			return "Researched"
		TechTreePanel.State.AVAILABLE:
			return "Available in your age"
		_:
			var age_def: AgeDef = GameDataRegistry.age(def.age_required) \
					if GameDataRegistry != null else null
			if age_def == null:
				return "Needs age %d — you are in age %d" % [def.age_required, viewer_age]
			return "Needs the %s Age" % age_def.name


## Where it is bought, by the building's display name -- the point of the whole page.
##
## Several is legal in the schema and none exists today; joined with "or" rather than a
## comma, because a list of buildings reads as "all of these" otherwise and it means
## "any of these".
func _where_text(def: TechDef) -> String:
	var names: Array[String] = []
	for id in def.researched_at:
		var bd: BuildingDef = GameDataRegistry.building(id) if GameDataRegistry != null \
				else null
		names.append(bd.name if bd != null and not bd.name.is_empty() else String(id))
	if names.is_empty():
		return "Researched at no building — this is a data error"
	return "Researched at the %s" % " or the ".join(names)


## Cost, time, prerequisites and effect, one line each and only where there is something
## to say. Static and public so a test can assert on the sentences without building a
## tree, and so `SelectionActions` can borrow the effect wording for the action tile the
## day that is wanted.
static func fact_lines(def: TechDef) -> Array[String]:
	var out: Array[String] = []

	var costs: Array[String] = []
	# In the counter's own order (stone, gold, wood, food), not the dictionary's, which
	# is insertion order out of JSON and so differs per tech. The player has already
	# learned one order from the resource panel; a second one here is a second thing to
	# read rather than recognise.
	for kind in ResourceHUD.DISPLAY_ORDER:
		if def.cost.has(kind):
			costs.append("%d %s" % [int(def.cost[kind]), kind])
	for kind in def.cost:
		if not ResourceHUD.DISPLAY_ORDER.has(kind):
			costs.append("%d %s" % [int(def.cost[kind]), kind])
	if not costs.is_empty():
		out.append("Costs %s" % ", ".join(costs))

	if def.research_time_ticks > 0:
		# In SECONDS, because ticks are an implementation detail no player has a feel
		# for. `SimClock.TICK_HZ` rather than a literal 10, so this follows the clock.
		out.append("Takes %d seconds to research"
				% int(round(float(def.research_time_ticks) / float(SimClock.TICK_HZ))))

	if not def.requires.is_empty():
		var names: Array[String] = []
		for id in def.requires:
			var req: TechDef = GameDataRegistry.tech(id) if GameDataRegistry != null \
					else null
			names.append(req.name if req != null else String(id))
		out.append("Requires %s first" % ", ".join(names))

	for key in def.effects:
		out.append(effect_text(StringName(key), int(def.effects[key])))
	return out


## One `stat.scope` effect in words.
##
## KEYED OFF THE WHOLE `stat.scope` STRING, matching `TechMods.KNOWN_EFFECTS` exactly.
## Splitting it and describing the two halves separately was tried and reads badly: the
## audience of `attack_damage.melee` is "melee soldiers" but the audience of
## `armor_melee.all` is every soldier against melee damage -- the same word `melee`
## meaning the target in one and the damage type in the other. Twelve sentences is fewer
## moving parts than a grammar that has to know that.
##
## An unknown key falls back to naming itself rather than being dropped.
## `GameDataRegistry.validate()` refuses one against `TechMods.KNOWN_EFFECTS`, so this
## branch means somebody has added an effect the sim reads and this file has not caught
## up -- which is a sentence a reader can act on, unlike a silently missing line.
static func effect_text(key: StringName, value: int) -> String:
	match key:
		&"attack_damage.melee":
			return "+%d attack for melee soldiers (not villagers)" % value
		&"attack_damage.pierce":
			return "+%d attack for archers and other ranged units" % value
		&"attack_range.pierce":
			return "+%d tile of range for ranged units" % value
		&"armor_melee.all":
			return "+%d armour against melee attacks, for every soldier" % value
		&"armor_pierce.all":
			return "+%d armour against ranged attacks, for every soldier" % value
		&"carry_cap.all":
			return "+%d carrying capacity for villagers" % value
		&"gather_rate.food", &"gather_rate.wood", &"gather_rate.gold", \
				&"gather_rate.stone":
			return "+%d%% %s gathering rate" % [value, String(key).split(".")[1]]
		&"ability_amount.heal":
			return "+%d healing per use" % value
		&"ability_amount.damage":
			return "+%d damage per ability use" % value
	return "%s: %+d" % [key, value]
