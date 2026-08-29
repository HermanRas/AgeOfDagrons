## The three full-screen pages behind the minimap's corner buttons (PLAN.md 8.2b):
## CHAT, TECHNOLOGY TREE and their shared chrome.
##
## The market is big enough to have its own file. What is asserted here is the part
## the three have in common -- that a page opens, closes, and can always be closed --
## plus the one property that makes a wireframe honest rather than a lie: that it
## says it is one, and that its unwired buttons are visibly unwired.
extends TestCase


# ── shared chrome ───────────────────────────────────────────────────────────

func test_a_page_starts_closed() -> void:
	var page := ChatPanel.new()
	assert_false(page.is_open())
	assert_false(page.visible)
	page.free()


func test_opening_and_closing_a_page() -> void:
	var page := ChatPanel.new()
	page.open()
	assert_true(page.is_open())
	page.close()
	assert_false(page.is_open())
	page.free()


func test_closing_emits_closed() -> void:
	var page := ChatPanel.new()
	# Array, not an int local: GDScript closures capture primitives by value, so
	# `count += 1` inside the lambda would mutate a copy (test_input_router hit this
	# first, and test_pause_menu records it too).
	var seen: Array[int] = []
	page.closed.connect(func() -> void: seen.append(1))
	page.open()
	page.close()
	assert_eq(seen.size(), 1)
	page.free()


func test_every_page_can_be_closed_from_the_page() -> void:
	# A PHONE HAS NO ESCAPE KEY. A page with no close button is a page you cannot
	# leave, which is the same dead end the build-mode cancel button exists to fix
	# (BUGS.md) -- so this asserts the button exists and that pressing it works,
	# for all three.
	for page in [ChatPanel.new(), TechTreePanel.new(), MarketPanel.new()] as Array[HudPanel]:
		page.open()
		var button := page.close_button()
		assert_not_null(button, "%s has a close button" % page.title())
		if button != null:
			button.pressed.emit()
			assert_false(page.is_open(), "%s closed" % page.title())
		page.free()


func test_a_page_blocks_the_taps_that_land_on_it() -> void:
	# `InputRouter` reaches the world through `_unhandled_input`, which never asks a
	# Control's filter anything -- so a page that did not STOP would let an order go
	# out to whatever unit happened to be under the panel.
	var page := ChatPanel.new()
	assert_eq(page.mouse_filter, Control.MOUSE_FILTER_STOP)
	page.free()


# ── chat (wireframe) ────────────────────────────────────────────────────────

func _player_state(count: int) -> Dictionary:
	var out: Dictionary = {}
	for i in range(1, count + 1):
		out[i] = {"colour": i - 1, "stock": {}, "age": 1, "defeated": false}
	return out


func test_the_chat_tabs_are_the_real_players() -> void:
	# The messages are invented; the players are not. That is what makes this a
	# wireframe of the right shape rather than a picture -- four players is four tabs
	# and the row is the width it will really be.
	var chat := ChatPanel.new()
	chat.show_players(_player_state(4), 2)
	assert_eq(chat._tabs.get_child_count(), 4)
	chat.free()


func test_the_chat_says_which_tab_is_yours() -> void:
	var chat := ChatPanel.new()
	chat.show_players(_player_state(3), 2)
	var labels: Array[String] = []
	for tab in chat._tabs.get_children():
		for row in tab.get_children():
			for node in row.get_children():
				if node is Label:
					labels.append((node as Label).text)
	assert_true(labels.has("Player 2 (you)"), "got %s" % [labels])
	assert_true(labels.has("Player 1"))
	chat.free()


func test_the_chat_send_and_clear_are_visibly_unwired() -> void:
	# A wireframe whose buttons worked LOCALLY would be worse than one whose buttons
	# do not: a message that appears on your own screen and nowhere else is a bug
	# report waiting to happen. Disabled says which half is missing.
	var chat := ChatPanel.new()
	assert_true(chat._send_button.disabled, "SEND is not wired to anything")
	assert_true(chat._clear_button.disabled)
	chat.free()


func test_the_chat_admits_it_is_a_wireframe() -> void:
	var chat := ChatPanel.new()
	chat.show_players(_player_state(2), 1)
	var said := ""
	for child in chat._log.get_children():
		if child is Label:
			said += (child as Label).text + "\n"
	assert_true(said.to_lower().contains("sample"),
			"the log marks itself as samples, or a screenshot of it is indistinguishable "
			+ "from a working chat: %s" % said)
	chat.free()


# ── the tech tree (wireframe, and a real renderer with no data) ─────────────

func test_the_tech_tree_draws_one_column_per_age() -> void:
	var tree := TechTreePanel.new()
	assert_eq(tree._columns.get_child_count(), GameDataRegistry.age_count())
	tree.free()


func test_the_tech_tree_names_the_ages_rather_than_numbering_them() -> void:
	# ages.json is explicit that the NAME belongs to the places with room for prose,
	# and that this page is one of them.
	var tree := TechTreePanel.new()
	var first: Control = tree._columns.get_child(0)
	var heading := ""
	for child in first.get_children():
		if child is Label:
			heading = (child as Label).text
			break
	assert_true(heading.contains(GameDataRegistry.age(1).name), "got '%s'" % heading)
	tree.free()


func test_the_tech_tree_says_it_has_no_data_yet() -> void:
	# `techs.json` is deliberately empty until 9.3. An empty page that said nothing
	# would read as broken; this is the difference between "unfinished" and "wrong".
	var tree := TechTreePanel.new()
	if GameDataRegistry.tech_ids().is_empty():
		assert_true(tree._legend.text.to_lower().contains("wireframe"),
				"got '%s'" % tree._legend.text)
	else:
		assert_false(tree._legend.text.to_lower().contains("wireframe"),
				"once techs are declared it stops calling itself a wireframe")
	tree.free()


func test_ages_you_have_not_reached_are_locked() -> void:
	# Age 2 rather than age 1, because 9.3's roster has nothing in age 1 -- there is
	# nothing to research before you have a blacksmith -- and an empty column has no
	# node to be lit or dim.
	var tree := TechTreePanel.new()
	tree.set_age(2)
	var second: Control = tree._columns.get_child(1)
	var last: Control = tree._columns.get_child(GameDataRegistry.age_count() - 1)
	assert_true(_has_lit_node(second), "age 2 is reachable")
	assert_false(_has_lit_node(last), "the last age is not")
	tree.free()


func test_an_age_with_no_technologies_draws_no_placeholders() -> void:
	# The lattice is all-or-nothing as of 9.3. It used to fill any empty column, which
	# was right while every column was empty and became a promise of an age-1 tier that
	# is never coming the moment one was not.
	var tree := TechTreePanel.new()
	tree.set_age(4)
	if not GameDataRegistry.tech_ids().is_empty():
		assert_eq(_node_count(tree._columns.get_child(0)), 0,
				"age 1 has no technologies and shows none")
		assert_true(_node_count(tree._columns.get_child(1)) > 0, "age 2 does")
	tree.free()


func test_a_researched_technology_is_drawn_as_researched() -> void:
	# The third state, which this page's header spent a paragraph explaining it could
	# not honestly draw while `SimPlayer.researched` was a field nothing wrote.
	var tree := TechTreePanel.new()
	tree.set_age(4)
	var before := _node_count_by_border(tree, HudStyle.GOLD)
	tree.set_researched({&"tech.forging": true})
	assert_eq(_node_count_by_border(tree, HudStyle.GOLD), before + 1,
			"exactly one more node is drawn in full gold")
	tree.free()


func test_a_node_names_the_building_it_is_bought_at() -> void:
	# The owner's ruling of 2026-08-29: the page is "only a visual guide letting you
	# know what buildings hold what upgrades". Without this line it is a list of names
	# with nothing to do about any of them.
	var tree := TechTreePanel.new()
	tree.set_age(2)
	var said := ""
	for column in tree._columns.get_children():
		for node in column.get_children():
			if node is PanelContainer:
				said += _text_of(node) + "\n"
	assert_true(said.contains("Blacksmith"),
			"Forging says where it is bought -- got: %s" % said)
	tree.free()


## Whether any node in a column is drawn at full opacity -- which is how `_node`
## distinguishes reachable from locked.
func _has_lit_node(column: Control) -> bool:
	for child in column.get_children():
		if child is PanelContainer and is_equal_approx(child.modulate.a, 1.0):
			return true
	return false


func _node_count(column: Control) -> int:
	var n := 0
	for child in column.get_children():
		if child is PanelContainer:
			n += 1
	return n


## Nodes whose border is the FULL gold, which `_node` uses for RESEARCHED alone --
## available draws it at 0.8 alpha and locked at 0.25.
func _node_count_by_border(tree: TechTreePanel, colour: Color) -> int:
	var n := 0
	for column in tree._columns.get_children():
		for node in column.get_children():
			if not (node is PanelContainer):
				continue
			var style := (node as PanelContainer).get_theme_stylebox("panel") as StyleBoxFlat
			if style != null and style.border_color == colour:
				n += 1
	return n


func _text_of(node: Control) -> String:
	var out := ""
	for child in node.get_children():
		if child is Label:
			out += (child as Label).text + " "
		elif child is Control:
			out += _text_of(child as Control)
	return out
