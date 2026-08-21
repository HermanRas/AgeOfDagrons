## Tribute and the market exchange (PLAN.md 8.2b's TRADE page).
##
## Two commands with one gate and one arithmetic hazard between them. The gate is a
## finished market -- without it every player could trade from tick 1, which is the
## kind of thing a UI can hide and a server must refuse. The hazard is that both of
## them create and destroy resources rather than moving entities around, so a wrong
## sign or a missing affordability check is a resource generator, and this file's
## whole job is to be the thing that notices.
extends TestCase

var world: SimWorld


func before_each() -> void:
	var cfg := MatchConfig.debug_skirmish()
	world = SimWorld.new()
	world.setup(cfg)
	MapGen.build(world, cfg)


# ── fixtures ────────────────────────────────────────────────────────────────

## Give `owner` a finished market, `force`d in because the debug map's start areas
## are already occupied and where it stands is not what any of this is about.
func _give_market(owner: int) -> SimBuilding:
	var corner := Vector2i(2, 2) if owner == 1 else Vector2i(
			world.map.size.x - 12, world.map.size.y - 12)
	return world.spawn_building(GameDataRegistry.market_building(), owner, corner,
			SimBuilding.Phase.COMPLETE, true)


func _stock(owner: int, kind: StringName, amount: int) -> void:
	world.player_for(owner).stock[kind] = amount


func _run(cmd: Command) -> bool:
	if not cmd.validate(world):
		return false
	world.queue_command(cmd)
	world.step()
	return true


func _held(owner: int, kind: StringName) -> int:
	return int(world.player_for(owner).stock.get(kind, 0))


# ── tribute ─────────────────────────────────────────────────────────────────

func test_a_tribute_moves_resources_and_the_tax_is_lost() -> void:
	# The tax is the point. A tribute is not a transfer: the sender pays in full and
	# the recipient gets less, so the total in the match GOES DOWN.
	_give_market(1)
	_stock(1, &"food", 500)
	_stock(2, &"food", 0)
	var amount := GameDataRegistry.tribute_increment()

	assert_true(_run(TributeCommand.new(1, 2, &"food", amount)))
	assert_eq(_held(1, &"food"), 500 - amount, "the sender pays in full")
	assert_eq(_held(2, &"food"), GameDataRegistry.tribute_received(amount),
			"the recipient gets what the tax leaves")
	assert_true(_held(2, &"food") < amount, "and that is less than was sent")


func test_the_tax_the_command_charges_is_the_one_the_page_advertises() -> void:
	# `MarketPanel` labels its buttons from `tribute_received()`, and this is the
	# command's own arithmetic. One function, so a button cannot promise a number the
	# server will not honour.
	var amount := GameDataRegistry.tribute_increment()
	var tax := GameDataRegistry.tribute_tax_percent()
	assert_eq(GameDataRegistry.tribute_received(amount), amount * (100 - tax) / 100)


func test_no_market_no_tribute() -> void:
	_stock(1, &"food", 500)
	var cmd := TributeCommand.new(1, 2, &"food", GameDataRegistry.tribute_increment())
	assert_false(cmd.validate(world), "refused without a market")


func test_a_foundation_is_not_a_market() -> void:
	# `is_complete()` is the same test `TrainCommand` applies to a building it is
	# queueing at: a hole in the ground trades nothing.
	world.spawn_building(GameDataRegistry.market_building(), 1, Vector2i(2, 2),
			SimBuilding.Phase.FOUNDATION, true)
	_stock(1, &"food", 500)
	var cmd := TributeCommand.new(1, 2, &"food", GameDataRegistry.tribute_increment())
	assert_false(cmd.validate(world))


func test_you_cannot_tribute_what_you_do_not_have() -> void:
	_give_market(1)
	_stock(1, &"gold", 10)
	var cmd := TributeCommand.new(1, 2, &"gold", 100)
	assert_false(cmd.validate(world))


func test_you_cannot_tribute_to_yourself() -> void:
	# It would be a button that burns the tax off your own stockpile for nothing.
	_give_market(1)
	_stock(1, &"food", 500)
	assert_false(TributeCommand.new(1, 1, &"food", 100).validate(world))


func test_you_cannot_tribute_to_a_defeated_player() -> void:
	# Their stock still exists on the host -- `ResignCommand` leaves everything
	# standing -- so without this a match could be drained into somebody who is out.
	_give_market(1)
	_stock(1, &"food", 500)
	world.player_for(2).defeated = true
	assert_false(TributeCommand.new(1, 2, &"food", 100).validate(world))


func test_a_negative_tribute_is_not_a_withdrawal() -> void:
	# The one that would be a resource generator: sending -100 credits the sender and
	# debits the target.
	_give_market(1)
	_stock(1, &"food", 500)
	_stock(2, &"food", 500)
	assert_false(TributeCommand.new(1, 2, &"food", -100).validate(world))
	assert_false(TributeCommand.new(1, 2, &"food", 0).validate(world))


func test_a_tribute_of_something_that_is_not_a_resource_is_refused() -> void:
	_give_market(1)
	world.player_for(1).stock[&"dragons"] = 500
	assert_false(TributeCommand.new(1, 2, &"dragons", 100).validate(world))


func test_two_tributes_in_one_tick_cannot_overdraw() -> void:
	# BOTH are validated before EITHER applies, so the second one is affordable when
	# it is checked and not when it lands. `apply()` pays first and bails, which is the
	# only test that is true at the moment the resources move.
	_give_market(1)
	var amount := GameDataRegistry.tribute_increment()
	_stock(1, &"wood", amount)          # enough for exactly one
	_stock(2, &"wood", 0)

	var first := TributeCommand.new(1, 2, &"wood", amount)
	var second := TributeCommand.new(1, 2, &"wood", amount)
	assert_true(first.validate(world))
	assert_true(second.validate(world), "both validate against the same tick")
	world.queue_command(first)
	world.queue_command(second)
	world.step()

	assert_eq(_held(1, &"wood"), 0, "the sender is empty, not overdrawn")
	assert_eq(_held(2, &"wood"), GameDataRegistry.tribute_received(amount),
			"and only one tribute arrived")


func test_the_sender_cannot_tribute_from_somebody_elses_stockpile() -> void:
	# Not a property of this command but of the boundary: `Net._recv_command` overwrites
	# `player_id` with the id it knows the sender owns. Asserted here because forging it
	# would mean emptying an opponent's bank into your own -- the most valuable lie
	# available on this page.
	_give_market(2)
	_stock(1, &"gold", 1000)
	_stock(2, &"gold", 1000)

	# Player 2 claims the tribute comes FROM player 1.
	var forged := TributeCommand.new(1, 1, &"gold", 100)
	forged.player_id = 2          # what the server rewrites it to, from the peer id
	assert_true(_run(forged), "it is a legal tribute once the sender is corrected")
	assert_eq(_held(2, &"gold"), 900, "it came out of the sender's own pocket")
	assert_true(_held(1, &"gold") > 1000, "and the player they named RECEIVED it")


func test_a_tribute_survives_the_wire() -> void:
	var back := Command.from_dict(TributeCommand.new(3, 5, &"stone", 250, 42).to_dict())
	assert_not_null(back, "the dispatch table knows the type")
	assert_true(back is TributeCommand)
	assert_eq(back.player_id, 3)
	assert_eq(back.to_player_id, 5)
	# StringName, not String. `&"stone" == "stone"` is FALSE, and everything off the
	# wire is a String -- so the conversion at `from_dict` is load-bearing.
	assert_eq(back.kind, &"stone")
	assert_eq(back.amount, 250)
	assert_eq(back.issued_tick, 42)


# ── the exchange ────────────────────────────────────────────────────────────

func _tradeable() -> StringName:
	var kinds := GameDataRegistry.market_kinds()
	return kinds[0] if not kinds.is_empty() else &""


func test_buying_spends_gold_and_delivers_a_lot() -> void:
	_give_market(1)
	var kind := _tradeable()
	var currency := GameDataRegistry.market_currency()
	var price := GameDataRegistry.market_buy_price(kind)
	_stock(1, currency, price)
	_stock(1, kind, 0)

	assert_true(_run(MarketExchangeCommand.new(1, kind, true)))
	assert_eq(_held(1, currency), 0, "the gold is gone")
	assert_eq(_held(1, kind), GameDataRegistry.market_lot(), "and a lot arrived")


func test_selling_gives_up_a_lot_and_pays_gold() -> void:
	_give_market(1)
	var kind := _tradeable()
	var currency := GameDataRegistry.market_currency()
	var lot := GameDataRegistry.market_lot()
	_stock(1, kind, lot)
	_stock(1, currency, 0)

	assert_true(_run(MarketExchangeCommand.new(1, kind, false)))
	assert_eq(_held(1, kind), 0)
	assert_eq(_held(1, currency), GameDataRegistry.market_sell_price(kind))


func test_a_round_trip_always_loses() -> void:
	# THE ONE THAT MATTERS. If buying back what you sold ever cost less than you got
	# for it, the market is an infinite resource generator and a finger on one button
	# beats every economy in the game. `GameDataRegistry.validate()` asserts the same
	# thing against the data; this asserts it against the transaction.
	_give_market(1)
	var kind := _tradeable()
	var currency := GameDataRegistry.market_currency()
	var lot := GameDataRegistry.market_lot()
	_stock(1, kind, lot)
	_stock(1, currency, 10_000)
	var before := _held(1, currency)

	assert_true(_run(MarketExchangeCommand.new(1, kind, false)), "sell")
	assert_true(_run(MarketExchangeCommand.new(1, kind, true)), "buy it back")

	assert_eq(_held(1, kind), lot, "the same lot is back")
	assert_true(_held(1, currency) < before,
			"and it cost gold: %d -> %d" % [before, _held(1, currency)])


func test_the_currency_cannot_be_traded_for_itself() -> void:
	_give_market(1)
	var currency := GameDataRegistry.market_currency()
	_stock(1, currency, 10_000)
	assert_false(MarketExchangeCommand.new(1, currency, true).validate(world))
	assert_false(MarketExchangeCommand.new(1, currency, false).validate(world))


func test_an_unpriced_kind_is_refused_rather_than_traded_for_nothing() -> void:
	_give_market(1)
	world.player_for(1).stock[&"dragons"] = 10_000
	assert_false(MarketExchangeCommand.new(1, &"dragons", false).validate(world))
	assert_false(MarketExchangeCommand.new(1, &"dragons", true).validate(world))


func test_no_market_no_exchange() -> void:
	var kind := _tradeable()
	_stock(1, GameDataRegistry.market_currency(), 10_000)
	_stock(1, kind, 10_000)
	assert_false(MarketExchangeCommand.new(1, kind, true).validate(world))
	assert_false(MarketExchangeCommand.new(1, kind, false).validate(world))


func test_you_cannot_buy_without_the_gold_or_sell_without_the_goods() -> void:
	_give_market(1)
	var kind := _tradeable()
	_stock(1, GameDataRegistry.market_currency(), 0)
	_stock(1, kind, 0)
	assert_false(MarketExchangeCommand.new(1, kind, true).validate(world))
	assert_false(MarketExchangeCommand.new(1, kind, false).validate(world))


func test_two_buys_in_one_tick_cannot_overdraw() -> void:
	_give_market(1)
	var kind := _tradeable()
	var currency := GameDataRegistry.market_currency()
	var price := GameDataRegistry.market_buy_price(kind)
	_stock(1, currency, price)          # enough for exactly one
	_stock(1, kind, 0)

	var first := MarketExchangeCommand.new(1, kind, true)
	var second := MarketExchangeCommand.new(1, kind, true)
	assert_true(first.validate(world))
	assert_true(second.validate(world))
	world.queue_command(first)
	world.queue_command(second)
	world.step()

	assert_eq(_held(1, currency), 0, "not overdrawn")
	assert_eq(_held(1, kind), GameDataRegistry.market_lot(), "and only one lot bought")


func test_an_exchange_survives_the_wire() -> void:
	var back := Command.from_dict(
			MarketExchangeCommand.new(4, &"wood", true, 9).to_dict())
	assert_not_null(back, "the dispatch table knows the type")
	assert_true(back is MarketExchangeCommand)
	assert_eq(back.player_id, 4)
	assert_eq(back.kind, &"wood")
	assert_true(back.buying)
	assert_eq(back.issued_tick, 9)


# ── the gate itself ─────────────────────────────────────────────────────────

func test_a_market_is_only_yours() -> void:
	# `has_completed_building` is asked per owner, and an opponent's market must not
	# license your trades -- the failure would be silent and completely invisible on a
	# map where somebody else has built one.
	_give_market(2)
	assert_true(world.has_completed_building(2, GameDataRegistry.market_building()))
	assert_false(world.has_completed_building(1, GameDataRegistry.market_building()))


func test_a_destroyed_market_stops_licensing_trades() -> void:
	var market := _give_market(1)
	assert_true(world.has_completed_building(1, GameDataRegistry.market_building()))
	market.alive = false
	assert_false(world.has_completed_building(1, GameDataRegistry.market_building()),
			"rubble trades nothing")
