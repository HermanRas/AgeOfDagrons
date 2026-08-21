## Buying or selling one lot of a resource for gold (PLAN.md 8.2b's TRADE page).
##
## ONE COMMAND FOR BOTH DIRECTIONS, distinguished by a bool, because they are the
## same transaction read backwards and every rule around them is shared: the same
## market building, the same lot size, the same price table. Two commands would be
## two `validate()`s to keep in agreement.
##
## THE PRICE IS NOT ON THE WIRE. A client says *what* it wants to trade and the
## server looks up what that costs -- if the price came from the client, a client
## could name its own. That is the same reason `TrainCommand` carries a unit id and
## not a cost. It also means the market page's labels are advisory: they read the
## same `GameDataRegistry` accessors, so they agree, but if they ever did not the
## server's number is the one that is charged.
##
## GOLD IS THE CURRENCY (market.json), so it is never `kind`: `market_buy_price`
## returns 0 for it, which `validate()` reads as "not for sale". A market that
## traded gold for gold would be a no-op at best and a rounding exploit at worst.
class_name MarketExchangeCommand
extends Command

## What is being bought or sold. Never the currency.
var kind: StringName = &""

## True to spend gold and receive a lot of `kind`; false to give a lot of `kind`
## and receive gold.
var buying: bool = false


func _init(p_player_id: int = 0, p_kind: StringName = &"", p_buying: bool = false,
		p_issued_tick: int = 0) -> void:
	player_id = p_player_id
	kind = p_kind
	buying = p_buying
	issued_tick = p_issued_tick


func to_dict() -> Dictionary:
	var d := super.to_dict()
	d["type"] = "market_exchange"
	d["kind"] = String(kind)
	d["buying"] = buying
	return d


static func from_dict(d: Dictionary) -> MarketExchangeCommand:
	var c := MarketExchangeCommand.new()
	c.player_id = int(d.get("player_id", 0))
	c.issued_tick = int(d.get("issued_tick", 0))
	c.kind = StringName(d.get("kind", ""))
	c.buying = bool(d.get("buying", false))
	return c


func validate(w: SimWorld) -> bool:
	if GameDataRegistry == null:
		return false
	var lot := GameDataRegistry.market_lot()
	var price := _price()
	# A price of 0 is how the data says "the market will not take this" -- for the
	# currency itself, for an unknown kind, and for a kind with no entry. Refusing
	# here rather than trading a lot for nothing is the difference between a dead
	# button and a free resource.
	if lot <= 0 or price <= 0:
		return false

	var p := w.player_for(player_id)
	if p == null or p.defeated:
		return false
	if not p.can_afford(_cost()):
		return false

	return w.has_completed_building(player_id, GameDataRegistry.market_building())


func apply(w: SimWorld) -> void:
	var p := w.player_for(player_id)
	if p == null:
		return
	# PAY FIRST AND BAIL ON FAILURE, for the reason `TributeCommand.apply` records:
	# several of these can be queued in one tick and all of them are validated
	# before any of them applies, so affordability at validation time is not
	# affordability at the moment the resources move.
	if not p.pay(_cost()):
		return
	if buying:
		p.add_resource(kind, GameDataRegistry.market_lot())
	else:
		p.add_resource(GameDataRegistry.market_currency(), _price())


## What this side of the trade charges, in the currency the payer holds. One
## function so `validate()`'s affordability test and `apply()`'s payment can never
## be asking about different amounts.
func _cost() -> Dictionary:
	if buying:
		return {GameDataRegistry.market_currency(): _price()}
	return {kind: GameDataRegistry.market_lot()}


## The gold on the other side of the trade. Buying pays it, selling receives it,
## and the spread between the two is the whole cost of using a market.
func _price() -> int:
	if buying:
		return GameDataRegistry.market_buy_price(kind)
	return GameDataRegistry.market_sell_price(kind)
