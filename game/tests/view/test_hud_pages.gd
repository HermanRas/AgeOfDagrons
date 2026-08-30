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


func test_the_chat_has_voice_toggles_and_they_are_all_dead() -> void:
	# Project owner, 2026-08-30: "voice toggles on the top with messanger contols at
	# the bottom". A live-looking MICROPHONE toggle is worse than a disabled one by
	# more than the SEND button is: a player who believes they are being heard and is
	# not has no way to find that out from this screen.
	var chat := ChatPanel.new()
	assert_true(chat.voice_toggles.size() >= 3, "got %s" % [chat.voice_toggles.keys()])
	for name in chat.voice_toggles:
		assert_true((chat.voice_toggles[name] as CheckButton).disabled,
				"%s is not wired to anything" % name)
	assert_false((chat.voice_toggles["Microphone"] as CheckButton).button_pressed,
			"nobody is joined to a voice channel they did not ask to be heard on")
	chat.free()


func test_the_chat_composer_is_at_the_bottom_and_unusable() -> void:
	# The field is a `TouchLineEdit` rather than a `LineEdit` even though it is
	# disabled: this project turns off mouse emulation from touch, so a plain field
	# never raises a keyboard -- and a wireframe built on the wrong class is one that
	# will be found not to work on the day it is wired up, which is what the lobby's
	# join field cost.
	var chat := ChatPanel.new()
	assert_true(chat._message_field is TouchLineEdit)
	assert_false(chat._message_field.editable)
	assert_true(chat._send_button.disabled)
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

func test_the_tech_tree_draws_one_row_per_age() -> void:
	# ROWS SINCE 2026-08-30, on the owner's ask: "age1 at the top with last age at the
	# bottom". It was one COLUMN per age, which put the last age off the right edge.
	var tree := TechTreePanel.new()
	assert_eq(tree._rows.get_child_count(), GameDataRegistry.age_count())
	tree.free()


func test_the_ages_run_top_to_bottom_in_order() -> void:
	# The whole point of the row layout, and the one thing about it a test can pin: row
	# N names age N. A reversed ladder would still draw four rows and look plausible.
	var tree := TechTreePanel.new()
	for age in range(1, GameDataRegistry.age_count() + 1):
		var heading := _heading_of(tree._rows.get_child(age - 1))
		assert_true(heading.contains(GameDataRegistry.age(age).name),
				"row %d names age %d -- got '%s'" % [age, age, heading])
	tree.free()


func test_the_tech_tree_names_the_ages_rather_than_numbering_them() -> void:
	# ages.json is explicit that the NAME belongs to the places with room for prose,
	# and that this page is one of them.
	var tree := TechTreePanel.new()
	var heading := _heading_of(tree._rows.get_child(0))
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
	# nothing to research before you have a blacksmith -- and an empty row has no
	# node to be lit or dim.
	var tree := TechTreePanel.new()
	tree.set_age(2)
	var second: Control = tree._rows.get_child(1)
	var last: Control = tree._rows.get_child(GameDataRegistry.age_count() - 1)
	assert_true(_has_lit_node(second), "age 2 is reachable")
	assert_false(_has_lit_node(last), "the last age is not")
	tree.free()


func test_an_age_with_no_technologies_draws_no_placeholders() -> void:
	# The lattice is all-or-nothing as of 9.3. It used to fill any empty row, which
	# was right while every row was empty and became a promise of an age-1 tier that
	# is never coming the moment one was not.
	var tree := TechTreePanel.new()
	tree.set_age(4)
	if not GameDataRegistry.tech_ids().is_empty():
		assert_eq(_node_count(tree._rows.get_child(0)), 0,
				"age 1 has no technologies and shows none")
		assert_true(_node_count(tree._rows.get_child(1)) > 0, "age 2 does")
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


func test_tapping_a_node_opens_a_box_that_names_the_building() -> void:
	# The owner's ruling of 2026-08-29: the page is "only a visual guide letting you
	# know what buildings hold what upgrades". That used to be a subtitle on the tile;
	# since 2026-08-30 it is in the box a tap opens, which is where the room is.
	#
	# Presses the REAL button rather than calling the handler, for the reason
	# `GameScene.corner_buttons` records: on these screens a control wired to nothing
	# has looked exactly like a working one more than once.
	var tree := TechTreePanel.new()
	tree.set_age(2)
	var node := _find_node(tree, "Forging")
	assert_not_null(node, "the tree draws a Forging node")
	if node != null:
		node.pressed.emit()
	var box := tree.detail_box()
	assert_true(box.is_showing(), "a tap opens the box")
	assert_true(_text_of(box).contains("Blacksmith"),
			"the box says where Forging is bought -- got: %s" % _text_of(box))
	tree.free()


func test_the_box_explains_the_upgrade_in_words_and_not_only_in_numbers() -> void:
	# The whole ask: "showing text explaining the upgrade". A box that listed
	# "+1 melee attack" and nothing else would pass every structural check here and
	# still not answer the question a player opened it with.
	var tree := TechTreePanel.new()
	tree.set_age(4)
	var node := _find_node(tree, "Forging")
	if node != null:
		node.pressed.emit()
	var said := _text_of(tree.detail_box())
	assert_true(said.contains(GameDataRegistry.tech(&"tech.forging").description),
			"the box carries the tech's own description -- got: %s" % said)
	assert_true(said.contains("melee"), "and its effect in words -- got: %s" % said)
	tree.free()


func test_a_locked_technology_still_opens_its_description() -> void:
	# Deliberate: "what is Plate Mail and should I plan for it" is a question about a
	# tech you do not have, and a node that refused to open would answer it with
	# silence. Nothing is bought here, so there is nothing to refuse.
	var tree := TechTreePanel.new()
	tree.set_age(1)
	var node := _find_node(tree, "Plate Mail")
	assert_not_null(node, "the tree draws a Plate Mail node even in age 1")
	if node != null:
		node.pressed.emit()
	assert_true(tree.detail_box().is_showing(), "a locked node still opens its box")
	assert_true(_text_of(tree.detail_box()).to_lower().contains("needs"),
			"and says what it is waiting for")
	tree.free()


func test_closing_the_page_closes_the_description() -> void:
	# Or reopening the tree lands on whatever node was last read, over a page the
	# player has not looked at yet.
	var tree := TechTreePanel.new()
	tree.set_age(4)
	var node := _find_node(tree, "Forging")
	if node != null:
		node.pressed.emit()
	tree.open()
	tree.close()
	assert_false(tree.detail_box().is_showing())
	tree.free()


func test_an_effect_the_sim_reads_has_words_for_it() -> void:
	# `TechMods.KNOWN_EFFECTS` is the closed list of what the sim actually applies. An
	# effect with no sentence here falls back to printing its own key, which is a tech
	# that says "armor_melee.all: +1" to a player -- so this pins the two together.
	for key in TechMods.KNOWN_EFFECTS:
		var said := TechDetailBox.effect_text(key, 1)
		assert_false(said.contains(String(key)),
				"%s falls through to naming itself: '%s'" % [key, said])


## The node button for a technology by its display name, or null.
func _find_node(tree: TechTreePanel, tech_name: String) -> Button:
	for row in tree._rows.get_children():
		for node in row.get_children():
			if node is Button and (node as Button).text == tech_name:
				return node as Button
	return null


## Whether any node in a row is drawn at full opacity -- which is how `_node`
## distinguishes reachable from locked.
func _has_lit_node(row: Control) -> bool:
	for child in row.get_children():
		if child is Button and is_equal_approx(child.modulate.a, 1.0):
			return true
	return false


func _node_count(row: Control) -> int:
	var n := 0
	for child in row.get_children():
		if child is Button:
			n += 1
	return n


## The age heading, which is the row's first Label.
func _heading_of(row: Control) -> String:
	for child in row.get_children():
		if child is Label:
			return (child as Label).text
	return ""


## Nodes whose border is the FULL gold, which `_node` uses for RESEARCHED alone --
## available draws it at 0.8 alpha and locked at 0.25.
func _node_count_by_border(tree: TechTreePanel, colour: Color) -> int:
	var n := 0
	for row in tree._rows.get_children():
		for node in row.get_children():
			if not (node is Button):
				continue
			var style := (node as Button).get_theme_stylebox("normal") as StyleBoxFlat
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
