## The market page (PLAN.md 8.2b), which is the one of the four corner pages that is
## a mechanism rather than a wireframe.
##
## What is asserted is the WIRING and the GATING, because those are the two things a
## screenshot cannot show: that a press asks for exactly the trade it is labelled
## with, and that a button the server would refuse is a button the page has already
## disabled. `test_market.gd` covers the commands themselves; nothing here touches a
## `SimWorld`.
extends TestCase

var panel: MarketPanel


func before_each() -> void:
	panel = MarketPanel.new()


func after_each() -> void:
	panel.free()


## `player_state`-shaped, which is what the snapshot carries: id -> {stock, colour,
## defeated, ...}. Deliberately built here rather than taken from a real snapshot, so
## a test can put the player in a state a match would take ten minutes to reach.
func _state(stock: Dictionary, others: int = 1) -> Dictionary:
	var out: Dictionary = {1: {"colour": 0, "stock": stock, "defeated": false}}
	for i in range(2, others + 2):
		out[i] = {"colour": i - 1, "stock": {}, "defeated": false}
	return out


func _rich() -> Dictionary:
	return {&"food": 9999, &"wood": 9999, &"stone": 9999, &"gold": 9999}


## Every button on a tribute row, in the order the row draws them.
func _tribute_buttons(row_index: int) -> Array[Button]:
	var out: Array[Button] = []
	var row: Control = panel._tribute_box.get_child(row_index)
	for child in row.get_children():
		if child is Button:
			out.append(child)
	return out


func _trade_button(kind: StringName, buying: bool) -> Button:
	for row in panel._exchange_box.get_children():
		for child in row.get_children():
			if child is Button and child.get_meta(&"kind", &"") == kind \
					and bool(child.get_meta(&"buying", false)) == buying:
				return child
	return null


# ── the gate ────────────────────────────────────────────────────────────────

func test_without_a_market_every_button_is_dead_and_the_page_says_why() -> void:
	# A disabled control with no explanation is impossible to diagnose from the
	# outside -- the same lesson closing one slot too many taught the skirmish screen.
	panel.show_state(_state(_rich()), 1, false)
	assert_false(panel.has_market())
	assert_true(panel._gate_note.visible)
	assert_true(panel._gate_note.text.to_lower().contains("market"),
			"got '%s'" % panel._gate_note.text)

	for button in _tribute_buttons(0):
		assert_true(button.disabled, "tribute is refused without a market")
	for kind in GameDataRegistry.market_kinds():
		assert_true(_trade_button(kind, true).disabled)
		assert_true(_trade_button(kind, false).disabled)


func test_with_a_market_and_the_resources_the_buttons_are_live() -> void:
	panel.show_state(_state(_rich()), 1, true)
	assert_true(panel.has_market())
	assert_false(panel._gate_note.visible, "and it stops nagging")
	for button in _tribute_buttons(0):
		assert_false(button.disabled)


# ── tribute ─────────────────────────────────────────────────────────────────

func test_a_row_per_other_player_and_never_one_for_yourself() -> void:
	# A self-tribute is a button that burns the tax off your own stockpile, and
	# `TributeCommand` refuses it -- so it must not be on the page either.
	panel.show_state(_state(_rich(), 3), 1, true)
	assert_eq(panel._tribute_box.get_child_count(), 3, "three others, three rows")


func test_a_defeated_player_gets_no_tribute_row() -> void:
	# The command refuses them, and unlike the market gate there is nothing the
	# player could do about it -- so the row would be four buttons that can never work.
	var state := _state(_rich(), 2)
	state[3]["defeated"] = true
	panel.show_state(state, 1, true)
	assert_eq(panel._tribute_box.get_child_count(), 1)


func test_pressing_tribute_asks_for_exactly_what_the_button_says() -> void:
	panel.show_state(_state(_rich()), 1, true)
	var asked: Array = []
	panel.tribute_requested.connect(func(to: int, kind: StringName, amount: int) -> void:
		asked.append([to, kind, amount]))

	_tribute_buttons(0)[0].pressed.emit()
	assert_eq(asked.size(), 1, "one press, one request")
	assert_eq(asked[0][0], 2, "to the player whose row it is on")
	assert_eq(asked[0][2], GameDataRegistry.tribute_increment(),
			"for the increment the data declares, not a number typed on the button")


func test_a_tribute_you_cannot_afford_is_already_disabled() -> void:
	# The server refuses it anyway (PLAN.md 5.1 step 4). This is so it does not have to.
	panel.show_state(_state({&"food": 0, &"gold": 0, &"wood": 0, &"stone": 0}), 1, true)
	for button in _tribute_buttons(0):
		assert_true(button.disabled)


func test_the_page_advertises_the_tax_the_command_charges() -> void:
	# One arithmetic, in `GameDataRegistry.tribute_received`, so the label and the
	# transfer cannot round differently.
	var amount := GameDataRegistry.tribute_increment()
	assert_true(panel._tribute_terms().contains(str(amount)),
			"names what is sent: '%s'" % panel._tribute_terms())
	assert_true(panel._tribute_terms().contains(str(GameDataRegistry.tribute_received(amount))),
			"and what arrives: '%s'" % panel._tribute_terms())


func test_a_lone_survivor_is_told_there_is_nobody_to_send_to() -> void:
	panel.show_state(_state(_rich(), 0), 1, true)
	var said := ""
	for child in panel._tribute_box.get_children():
		if child is Label:
			said = (child as Label).text
	assert_true(said.to_lower().contains("nobody"), "got '%s'" % said)


# ── the exchange ────────────────────────────────────────────────────────────

func test_one_buy_and_one_sell_per_priced_kind() -> void:
	for kind in GameDataRegistry.market_kinds():
		assert_not_null(_trade_button(kind, true), "%s can be bought" % kind)
		assert_not_null(_trade_button(kind, false), "%s can be sold" % kind)


func test_the_currency_has_no_row() -> void:
	# Gold buys the other three; trading it for itself is a no-op at best.
	assert_null(_trade_button(GameDataRegistry.market_currency(), true))


func test_a_buy_button_says_its_price() -> void:
	var kind := GameDataRegistry.market_kinds()[0]
	var button := _trade_button(kind, true)
	assert_true(button.text.contains(str(GameDataRegistry.market_buy_price(kind))),
			"got '%s'" % button.text)


func test_pressing_buy_asks_to_buy_that_kind() -> void:
	panel.show_state(_state(_rich()), 1, true)
	var asked: Array = []
	panel.exchange_requested.connect(func(kind: StringName, buying: bool) -> void:
		asked.append([kind, buying]))

	var wanted := GameDataRegistry.market_kinds()[0]
	_trade_button(wanted, true).pressed.emit()
	_trade_button(wanted, false).pressed.emit()
	assert_eq(asked.size(), 2)
	assert_eq(asked[0], [wanted, true])
	assert_eq(asked[1], [wanted, false])


func test_buying_needs_the_gold_and_selling_needs_the_goods() -> void:
	var kind := GameDataRegistry.market_kinds()[0]
	var currency := GameDataRegistry.market_currency()

	# Gold and nothing else: you may buy, you may not sell.
	panel.show_state(_state({currency: 100_000}), 1, true)
	assert_false(_trade_button(kind, true).disabled, "can buy")
	assert_true(_trade_button(kind, false).disabled, "nothing to sell")

	# The goods and no gold: the other way round.
	panel.show_state(_state({kind: 100_000}), 1, true)
	assert_true(_trade_button(kind, true).disabled, "cannot afford to buy")
	assert_false(_trade_button(kind, false).disabled, "can sell")


func test_the_exchange_rows_are_not_rebuilt_on_every_snapshot() -> void:
	# They are enabled and disabled, never replaced. Ten rebuilds a second on a touch
	# screen means a press landing on a button that has just been freed.
	panel.show_state(_state(_rich()), 1, true)
	var before := _trade_button(GameDataRegistry.market_kinds()[0], true)
	panel.show_state(_state(_rich()), 1, true)
	assert_eq(_trade_button(GameDataRegistry.market_kinds()[0], true), before,
			"the same Button object survived the refresh")


func test_the_resources_read_in_the_order_the_hud_lists_them() -> void:
	# Declaration order in a JSON object is whatever somebody typed; the resource
	# counter's order is the one the player has already learned.
	var order := panel._market_kinds()
	var hud_positions: Array[int] = []
	for kind in order:
		hud_positions.append(ResourceHUD.DISPLAY_ORDER.find(kind))
	var sorted := hud_positions.duplicate()
	sorted.sort()
	assert_eq(hud_positions, sorted, "got %s" % [order])
