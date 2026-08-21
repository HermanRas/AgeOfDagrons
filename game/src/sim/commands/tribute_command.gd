## Sending resources to another player (PLAN.md 8.2b's TRADE page).
##
## THE TAX IS WHY THIS IS A COMMAND AND NOT TWO. A tribute is not a transfer: the
## sender pays `amount` and the recipient receives less than that
## (`GameDataRegistry.tribute_received`), so the resources are destroyed in the
## middle. Splitting it into a debit and a credit would put the two halves on
## different ticks and give a moment where the resources exist nowhere -- and one
## where a failed second half loses them for good.
##
## WHO IS SENDING IS NOT ON THE WIRE, and that is the security property. `Net`
## overwrites `player_id` with the id it knows the sender owns (`_recv_command`),
## exactly as with `ResignCommand`, so `to_player_id` is the only party this can
## name and a client cannot make somebody else's stockpile pay.
##
## THE MARKET IS THE PRECONDITION, not the age. The building is named by
## `market.json` rather than here, so this and `MarketExchangeCommand` cannot end
## up gated on different things -- and because `building.market` is age-gated in
## `buildings.json`, requiring the building requires the age transitively and
## states the rule once. The market page greys its buttons on the same test
## (`MarketPanel`), which is what the trust-boundary rule wants: the HUD hides it
## AND the command refuses it (PLAN.md 5.1 step 4).
class_name TributeCommand
extends Command

var to_player_id: int = 0
var kind: StringName = &""
var amount: int = 0


func _init(p_player_id: int = 0, p_to_player_id: int = 0, p_kind: StringName = &"",
		p_amount: int = 0, p_issued_tick: int = 0) -> void:
	player_id = p_player_id
	to_player_id = p_to_player_id
	kind = p_kind
	amount = p_amount
	issued_tick = p_issued_tick


func to_dict() -> Dictionary:
	var d := super.to_dict()
	d["type"] = "tribute"
	d["to_player_id"] = to_player_id
	d["kind"] = String(kind)
	d["amount"] = amount
	return d


static func from_dict(d: Dictionary) -> TributeCommand:
	var c := TributeCommand.new()
	c.player_id = int(d.get("player_id", 0))
	c.issued_tick = int(d.get("issued_tick", 0))
	c.to_player_id = int(d.get("to_player_id", 0))
	# StringName, because everything off the wire is a String and
	# `&"food" == "food"` is FALSE -- the gotcha that has bitten this codebase
	# before (AGENT_GAME_CODER.md 6). Converted at the boundary, once.
	c.kind = StringName(d.get("kind", ""))
	c.amount = int(d.get("amount", 0))
	return c


func validate(w: SimWorld) -> bool:
	if amount <= 0:
		return false
	# NOT TO YOURSELF. A self-tribute is a button that burns 10% of your own
	# stockpile, which nobody means to press -- and it is the one target that would
	# make the pay-then-credit order below matter.
	if to_player_id == player_id:
		return false
	if GameDataRegistry == null or not GameDataRegistry.can_tribute(kind):
		return false

	var from := w.player_for(player_id)
	if from == null or from.defeated or not from.can_afford({kind: amount}):
		return false
	# A DEFEATED PLAYER IS NOT A DESTINATION. Their stock still exists on the host
	# (`ResignCommand` leaves everything standing), so without this a match could be
	# drained into somebody who is already out of it.
	var to := w.player_for(to_player_id)
	if to == null or to.defeated:
		return false

	return w.has_completed_building(player_id, GameDataRegistry.market_building())


func apply(w: SimWorld) -> void:
	var from := w.player_for(player_id)
	var to := w.player_for(to_player_id)
	if from == null or to == null:
		return
	# PAY FIRST, and bail if the payment fails. `validate()` ran on this tick's
	# world, but two tributes queued in the same tick are both validated before
	# either applies -- so the second one can be affordable when it is checked and
	# not when it lands. `pay()` is the only test that is true at the moment the
	# resources move.
	if not from.pay({kind: amount}):
		return
	to.add_resource(kind, GameDataRegistry.tribute_received(amount))
