## The MARKET page behind the minimap's top-right corner button (PLAN.md 8.2b).
##
## THE ONE OF THE FOUR THAT IS A MECHANISM. Chat and the tech tree are wireframes
## because the systems under them do not exist yet; this has everything it needs --
## `SimPlayer.stock`, a market building in `buildings.json`, every player's id and
## colour on the snapshot already -- so it is wired end to end: a press becomes a
## `TributeCommand` or a `MarketExchangeCommand`, goes to the server like every
## other order, and the number on the resource counter moves when the next snapshot
## comes back. Nothing here touches the simulation directly.
##
## EMITS RATHER THAN SUBMITS, the same separation `SelectionPanel` keeps with its
## train button: this control knows what was pressed, `GameScene` knows how to send
## it. It means a test can assert what a press asks for without a session, and it
## means the page has no opinion about `Net`.
##
## EVERY LABEL COMES FROM `GameDataRegistry`, never from a number typed here, so a
## button cannot advertise a price the command will not charge. The commands read
## the same accessors. That does NOT make the labels authoritative -- the server
## re-checks everything (PLAN.md 5.1 step 4) -- it makes them honest.
##
## WHAT IS DELIBERATELY NOT SHOWN: the other players' stockpiles. The snapshot's
## `player_state` carries every player's `stock` to every client (see
## `SnapshotSystem.build`), so this page could print an opponent's gold, and a fog
## of war that hides their buildings while the HUD prints their bank balance would
## be a strange kind of secrecy. Drawing only names and colours keeps this page from
## being the thing that makes that leak matter. The leak itself is
## `SnapshotSystem`'s to close.
class_name MarketPanel
extends HudPanel

## `to_player_id` is the recipient; `kind` and `amount` are what leaves this
## player's stockpile, before tax. `GameScene` turns it into a `TributeCommand`.
signal tribute_requested(to_player_id: int, kind: StringName, amount: int)

## `buying` true spends the currency and receives a lot of `kind`; false is the
## other way round. One signal for both, because it is one command.
signal exchange_requested(kind: StringName, buying: bool)

const _ROW_LABEL_MIN := Vector2(150.0, 0.0)
const _TRADE_BUTTON_MIN := Vector2(104.0, 36.0)
const _TRIBUTE_BUTTON_MIN := Vector2(132.0, 36.0)
const _CHIP := 16.0
const _RESOURCE_ICON := 20.0

## The gap between the cells of a tribute or exchange row. A named constant since
## 2026-08-30 rather than the literal 8 it was in both places, because `_page_width()`
## has to count these and a gap that drifted would size the page wrong rather than
## visibly wrong.
const _ROW_SEP := 8

## Room for the scroll bar the body grows when the tribute list is long. Small and
## deliberate: without it the last tribute button is the thing the bar overlaps,
## which is the one control this whole width is measured from.
const _SCROLLBAR_ALLOWANCE := 16.0

var _tribute_box: VBoxContainer
var _exchange_box: VBoxContainer
var _gate_note: Label

## Last state applied, so a press can be validated against the same numbers the
## labels were drawn from and a test can read back what the page is showing.
var _stock: Dictionary = {}
var _has_market := false


func _init() -> void:
	# The chrome, and it is not optional -- see `HudPanel._init`.
	super()
	set_title("MARKET")

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)

	# THE PRECONDITION, said in words at the top rather than shown as a page of
	# greyed buttons. Closing a slot too many on the skirmish screen taught the same
	# lesson (`SkirmishScreen.regenerate`): a disabled control with no explanation is
	# impossible to diagnose from the outside.
	_gate_note = HudPanel.note_label("")
	column.add_child(_gate_note)

	column.add_child(_section_heading("TRIBUTE"))
	column.add_child(HudPanel.note_label(_tribute_terms()))
	_tribute_box = VBoxContainer.new()
	_tribute_box.add_theme_constant_override("separation", 6)
	column.add_child(_tribute_box)

	column.add_child(_section_heading("EXCHANGE"))
	column.add_child(HudPanel.note_label(_exchange_terms()))
	_exchange_box = VBoxContainer.new()
	_exchange_box.add_theme_constant_override("separation", 6)
	column.add_child(_exchange_box)

	add_close_button()
	_build_exchange_rows()
	max_page_width = _page_width()


## How wide this page has any use for, content plus the frame's own margins.
##
## MEASURED FROM THE ROWS RATHER THAN CHOSEN (project owner, 2026-08-30: *"bring in the
## right side just past the last button"*). Every cell in both kinds of row has a fixed
## minimum and none of them expands, so the widest row's width is arithmetic and not a
## guess -- and a number typed here instead would be a guess that stopped being right the
## first time a button's minimum changed.
##
## The TRIBUTE row is the wide one and its width depends on DATA: it draws one button per
## kind `market.json` allows to be tributed. So this is asked at build time rather than
## being a `const`, and a fifth tradeable resource widens the page instead of falling off
## the end of it.
##
## The two paragraphs above the rows wrap into whatever is left, which is the rest of what
## was asked for -- they were single lines running the full width of a desktop window
## before, and a line that long is hard to read back to the start of.
func _page_width() -> float:
	var kinds := maxi(_tribute_kinds().size(), 1)
	var tribute := _CHIP + _ROW_SEP + _ROW_LABEL_MIN.x + _ROW_SEP \
			+ kinds * _TRIBUTE_BUTTON_MIN.x + (kinds - 1) * _ROW_SEP
	var exchange := _RESOURCE_ICON + _ROW_SEP + _ROW_LABEL_MIN.x + _ROW_SEP \
			+ 2.0 * _TRADE_BUTTON_MIN.x + _ROW_SEP
	return maxf(tribute, exchange) + 2.0 * HudPanel.CONTENT_MARGIN + _SCROLLBAR_ALLOWANCE


# ── state ───────────────────────────────────────────────────────────────────

## Everything the page needs, from the snapshot `GameScene` already has in hand.
##
## `has_market` is ADVISORY. It comes from the client's own view of its buildings
## (`GameView.has_completed_building`), which is trustworthy for your OWN
## entities -- they are always sent, whatever the fog says -- but it is not what
## decides anything: both commands re-check it against the authoritative world. A
## wrong answer here costs a refusal, exactly as the placement ghost's does.
func show_state(player_state: Dictionary, local_id: int, has_market: bool) -> void:
	_stock = (player_state.get(local_id, {}) as Dictionary).get("stock", {})
	_has_market = has_market

	if has_market:
		_gate_note.text = ""
		_gate_note.visible = false
	else:
		var def: BuildingDef = GameDataRegistry.building(GameDataRegistry.market_building()) \
				if GameDataRegistry != null else null
		_gate_note.text = "You have no finished %s. Build one to trade — every button " \
				% (def.name if def != null else "Market") \
				+ "below stays refused until then, on this screen and on the server."
		_gate_note.visible = true

	_build_tribute_rows(player_state, local_id)
	_refresh_exchange_rows()


func has_market() -> bool:
	return _has_market


func stock_of(kind: StringName) -> int:
	return int(_stock.get(kind, 0))


# ── tribute ─────────────────────────────────────────────────────────────────

## One row per OTHER player. Rebuilt rather than shown and hidden, for the reason
## `SkirmishScreen._rebuild_slot_rows` records: a hidden row still holds a target,
## and a button that tributes to a player who is no longer in the row list is the
## worst bug available on this page.
func _build_tribute_rows(player_state: Dictionary, local_id: int) -> void:
	for child in _tribute_box.get_children():
		_tribute_box.remove_child(child)
		child.queue_free()

	var ids: Array = player_state.keys()
	# Sorted: dictionary order is not guaranteed, and rows that reshuffled between
	# snapshots would move a target out from under a thumb already moving toward it.
	ids.sort()

	var others := 0
	for id in ids:
		var pid := int(id)
		if pid == local_id:
			continue
		var entry: Dictionary = player_state[id]
		# A defeated player is dropped, not dimmed. `TributeCommand` refuses them, so
		# a row here would be four buttons that cannot work -- and unlike the market
		# gate, there is nothing the player could do about it.
		if bool(entry.get("defeated", false)):
			continue
		others += 1
		_tribute_box.add_child(_tribute_row(pid, int(entry.get("colour", 0))))

	if others == 0:
		_tribute_box.add_child(HudPanel.note_label(
				"Nobody to send anything to — you are the only player left standing."))


func _tribute_row(to_player_id: int, colour_index: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", _ROW_SEP)

	row.add_child(HudPanel.colour_chip(colour_index, _CHIP))

	var name_label := HudPanel.text_label("Player %d" % to_player_id, 15)
	name_label.custom_minimum_size = _ROW_LABEL_MIN
	row.add_child(name_label)

	var amount := GameDataRegistry.tribute_increment() if GameDataRegistry != null else 0
	for kind in _tribute_kinds():
		var button := _resource_button(kind, str(amount))
		# CAN THIS PRESS SUCCEED. Disabled for the two reasons the command refuses --
		# no market, and not enough in the bank -- so the page and the server say the
		# same thing, which is what the trust-boundary rule asks for. A press that got
		# through anyway would be refused; this is so it does not have to be.
		button.disabled = not _has_market or amount <= 0 or stock_of(kind) < amount
		button.pressed.connect(func() -> void:
			tribute_requested.emit(to_player_id, kind, amount))
		row.add_child(button)
	return row


func _tribute_kinds() -> Array[StringName]:
	var out: Array[StringName] = []
	if GameDataRegistry == null:
		return out
	# Declared in `market.json`; filtered through the display order the resource
	# counter already uses, so the four buttons on a tribute row read in the same
	# order as the four numbers in the corner of the screen.
	for kind in ResourceHUD.DISPLAY_ORDER:
		if GameDataRegistry.can_tribute(kind):
			out.append(kind)
	return out


func _tribute_terms() -> String:
	if GameDataRegistry == null:
		return ""
	var amount := GameDataRegistry.tribute_increment()
	var tax := GameDataRegistry.tribute_tax_percent()
	return "One press sends %d. The recipient receives %d — %d%% is lost in transit." \
			% [amount, GameDataRegistry.tribute_received(amount), tax]


# ── exchange ────────────────────────────────────────────────────────────────

## Built ONCE, in declaration order, and only re-enabled afterwards. The tradeable
## kinds come from data and cannot change mid-match, so rebuilding these on every
## snapshot would throw six live buttons away ten times a second -- which on a
## touch screen means a press landing on a button that has just been freed.
func _build_exchange_rows() -> void:
	for kind in _market_kinds():
		_exchange_box.add_child(_exchange_row(kind))
	if _exchange_box.get_child_count() == 0:
		_exchange_box.add_child(HudPanel.note_label(
				"No exchange rates are declared — see data/market.json."))


func _exchange_row(kind: StringName) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", _ROW_SEP)

	var icon := HudPanel.resource_icon(kind, _RESOURCE_ICON)
	if icon != null:
		row.add_child(icon)

	var lot := GameDataRegistry.market_lot()
	var name_label := HudPanel.text_label(
			"%s %d" % [String(kind).capitalize(), lot], 15)
	name_label.custom_minimum_size = _ROW_LABEL_MIN
	row.add_child(name_label)

	# BUY spends the currency, SELL earns it, and both say which way round in gold
	# on the button -- the spread is the entire cost of using a market, so hiding it
	# behind a tooltip on a touch screen would hide the only thing worth knowing.
	row.add_child(_trade_button(kind, true))
	row.add_child(_trade_button(kind, false))
	return row


func _trade_button(kind: StringName, buying: bool) -> Button:
	var price := GameDataRegistry.market_buy_price(kind) if buying \
			else GameDataRegistry.market_sell_price(kind)
	var button := Button.new()
	button.text = "%s %d%s" % ["BUY" if buying else "SELL", price,
			_currency_suffix()]
	button.custom_minimum_size = _TRADE_BUTTON_MIN
	button.add_theme_font_size_override("font_size", 14)
	button.pressed.connect(func() -> void: exchange_requested.emit(kind, buying))
	# Held on the button itself so `_refresh_exchange_rows` can re-test affordability
	# without re-deriving which kind and direction each button was built for -- and so
	# a test can find the button for one particular trade.
	button.set_meta(&"kind", kind)
	button.set_meta(&"buying", buying)
	return button


## Re-test every trade button against the current stockpile. Enabling and disabling
## only, never rebuilding: see `_build_exchange_rows`.
func _refresh_exchange_rows() -> void:
	var lot := GameDataRegistry.market_lot() if GameDataRegistry != null else 0
	var currency := GameDataRegistry.market_currency() if GameDataRegistry != null else &""
	for row in _exchange_box.get_children():
		for child in row.get_children():
			if not child is Button:
				continue
			var button := child as Button
			var kind: StringName = button.get_meta(&"kind", &"")
			var buying: bool = bool(button.get_meta(&"buying", false))
			var price := GameDataRegistry.market_buy_price(kind) if buying \
					else GameDataRegistry.market_sell_price(kind)
			var affordable := (stock_of(currency) >= price) if buying \
					else (stock_of(kind) >= lot)
			button.disabled = not _has_market or price <= 0 or lot <= 0 or not affordable


func _market_kinds() -> Array[StringName]:
	var out: Array[StringName] = []
	if GameDataRegistry == null:
		return out
	# Same reordering as the tribute row, and for the same reason: declaration order
	# in a JSON object is whatever somebody typed, and the resource counter's order
	# is the one the player has already learned.
	var declared := GameDataRegistry.market_kinds()
	for kind in ResourceHUD.DISPLAY_ORDER:
		if declared.has(kind):
			out.append(kind)
	# Anything priced but not in the counter's four, so a new kind cannot be
	# silently unreachable just because this display order predates it.
	for kind in declared:
		if not out.has(kind):
			out.append(kind)
	return out


func _exchange_terms() -> String:
	if GameDataRegistry == null:
		return ""
	return "Bought and sold in lots of %d, priced in %s. Buying back what you sold " \
			% [GameDataRegistry.market_lot(), GameDataRegistry.market_currency()] \
			+ "always costs more than you got for it — that spread is what using a " \
			+ "market costs."


func _currency_suffix() -> String:
	var currency := String(GameDataRegistry.market_currency()) if GameDataRegistry != null \
			else ""
	return " %s" % currency if not currency.is_empty() else ""


# ── shared ──────────────────────────────────────────────────────────────────

func _section_heading(text: String) -> Label:
	var label := HudPanel.text_label(text, 19)
	return label


## A button naming a resource and an amount, with the resource's icon on it.
##
## THE NAME IS ON IT, and the first version left it off: four icons and four
## identical "100"s, on the theory that the icon says which resource. It does not --
## the pack's four resource icons are near-identical green roundels at 20 px
## (photographed, 2026-08-21), so a tribute row was four indistinguishable buttons
## that each gave away 100 of something. The icon stays as the thing the eye finds
## first once the art improves; the word is what makes it usable today.
func _resource_button(kind: StringName, text: String) -> Button:
	var button := Button.new()
	button.text = "%s %s" % [String(kind).capitalize(), text]
	button.icon = HudPanel.resource_texture(kind)
	button.expand_icon = true
	button.custom_minimum_size = _TRIBUTE_BUTTON_MIN
	button.add_theme_font_size_override("font_size", 14)
	return button
