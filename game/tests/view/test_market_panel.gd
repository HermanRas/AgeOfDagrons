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


# ── how wide the page is ────────────────────────────────────────────────────

func test_the_page_asks_for_no_more_width_than_its_widest_row_needs() -> void:
	# "bring in the right side just past the last button" (project owner, 2026-08-30).
	# The widest row is a tribute row, and every cell in it has a fixed minimum.
	var kinds := panel._tribute_kinds().size()
	assert_true(kinds > 0, "market.json declares something tributable")

	var row := MarketPanel._CHIP + MarketPanel._ROW_SEP \
			+ MarketPanel._ROW_LABEL_MIN.x + MarketPanel._ROW_SEP \
			+ kinds * MarketPanel._TRIBUTE_BUTTON_MIN.x + (kinds - 1) * MarketPanel._ROW_SEP
	assert_eq(panel.max_page_width,
			row + 2.0 * HudPanel.CONTENT_MARGIN + MarketPanel._SCROLLBAR_ALLOWANCE,
			"the cap is the widest row plus the frame's margins, and nothing else")


## The frame's width, for a page laid out `available` wide. The frame is anchored to
## both edges, so its width is what the two offsets leave between them.
##
## Driven through `_apply_page_width` rather than by assigning `panel.size`, and the
## function's own header records why: a `PRESET_FULL_RECT` Control cannot be given a
## size, and outside a tree the assignment raises no `NOTIFICATION_RESIZED` at all.
func _frame_width(available: float) -> float:
	panel._apply_page_width(available)
	return (available + panel._frame.offset_right) - panel._frame.offset_left


func test_a_wide_window_shrinks_the_page_and_a_narrow_one_does_not() -> void:
	# The cap is a CAP: past it the page stops growing, and below it the screen margin
	# wins so a narrow screen lays out exactly as it did before the cap existed.
	var cap: float = panel.max_page_width
	var wide := cap + 4.0 * HudPanel.MARGIN_H

	assert_eq(_frame_width(wide), cap, "capped on a wide window")

	var narrow := HudPanel.MARGIN_H * 2.0 + 200.0
	assert_eq(_frame_width(narrow), 200.0,
			"too narrow for the cap, so the margin decides and nothing is clipped")


func test_a_capped_page_stays_centred_on_the_screen() -> void:
	# Reported the day after the cap landed: *"market panel is off centre"*. Taking the
	# slack off the right edge alone is what "bring in the right side" asks for
	# literally, and it leaves a narrow page pinned to the left of a wide screen.
	var wide: float = panel.max_page_width + 4.0 * HudPanel.MARGIN_H
	panel._apply_page_width(wide)

	var left: float = panel._frame.offset_left
	var right: float = -panel._frame.offset_right
	assert_eq(left, right, "the same gap on both sides")
	assert_true(left > HudPanel.MARGIN_H,
			"and both are wider than the margin, since there was slack to split")


func test_a_page_with_no_cap_fills_the_width_it_is_given() -> void:
	# The default, and what chat and the tech tree stay on.
	panel.max_page_width = 0.0
	assert_eq(_frame_width(2000.0), 2000.0 - 2.0 * HudPanel.MARGIN_H)


func test_the_other_pages_are_not_capped() -> void:
	# Chat and the tech tree lay out content that uses whatever width it is given --
	# the tech tree literally scrolls sideways -- so a cap there would be a loss.
	var chat := ChatPanel.new()
	var tree := TechTreePanel.new()
	assert_eq(chat.max_page_width, 0.0)
	assert_eq(tree.max_page_width, 0.0)
	chat.free()
	tree.free()
