class_name StopSim
extends RefCounted
## A stop (GDD 9.6): what the vendor has on his tray and what the hand does
## with it.
##
## The tray lies at the passenger window in two rows of five, one offer at
## each of its anchors (offer_1 to offer_10): room for everything a stop can
## hold out at once. What does not fit waits and moves up as room is made. A TAP on an offer buys it when cash allows. An item that belongs in
## a slot is then his, still on the tray: a DRAG_TO from there to one of its
## slots puts it in (what was in the slot stays with the vendor). An
## adaptation goes straight into a free bay, and a deal that changes the car
## takes hold at once. Whatever he has paid for and not placed when he
## leaves is paid back.

const TRAY: PackedStringArray = [
	"offer_1", "offer_2", "offer_3", "offer_4", "offer_5",
	"offer_6", "offer_7", "offer_8", "offer_9", "offer_10",
]
const ITEM: StringName = &"item"
const RESTOCK: StringName = &"restock"
const REPAIR: StringName = &"repair"
const SERVICE: StringName = &"service"
## The rituals of the tray. They are not in rituals.json: they exist only
## while an offer lies at an anchor.
const BUY: String = "stop_buy"
const PLACE: String = "stop_place"
const SHADY_KEY: String = "shady"
const BOSS_SERVICE: String = "boss"

## One thing on the tray, or waiting for room on it.
class Offer:
	extends RefCounted
	var kind: StringName = &""
	## An item id (to buy or to restock), a fault id (to repair), or a stop id
	## (a service to choose at a boss stop).
	var id: String = ""
	var price: float = 0.0
	## One of a set of which he may take `picks_left` for nothing.
	var free_pick: bool = false
	## The shady guy's.
	var shady: bool = false
	## Paid for, and his to place.
	var bought: bool = false
	## The tray anchor it lies at; "" while it waits.
	var anchor: String = ""

var active: bool = false
var stop_id: String = ""
## What is on offer now. A boss stop takes on the service he chooses.
var service: String = ""
var offers: Array[Offer] = []
var picks_left: int = 0
## Nothing here costs Clock minutes (a boss stop).
var free_minutes: bool = false
## A boss stop's services are held out once his free pick is off the tray.
var _services_due: bool = false
var shady_used: bool = false
## What happened, for DriveSim to announce.
var events: Array[Dictionary] = []

var _data: GameData
var _tuning: Tuning
var _items: ItemSim
var _faults: FaultSim
var _nerves: NervesSim
var _clock: ClockSim
var _rng: Rng
var _act: int = 1
var _price_mult: float = 1.0


func configure(data: GameData, items: ItemSim, faults: FaultSim, nerves: NervesSim, clock: ClockSim, rng: Rng) -> void:
	_data = data
	_tuning = data.tuning
	_items = items
	_faults = faults
	_nerves = nerves
	_clock = clock
	_rng = rng


## He has stopped. `shady` when the shady guy has joined this stop.
## `price_mult` is the Table's (GDD 11.2).
func begin(id: String, act: int, shady: bool, price_mult: float = 1.0) -> void:
	active = true
	stop_id = id
	_act = act
	_price_mult = price_mult
	offers = []
	picks_left = 0
	shady_used = false
	_services_due = false
	events = []
	var record: Dictionary = _data.record("stops", id)
	service = GameData.as_string(record.get("service"))
	free_minutes = service == BOSS_SERVICE
	_lay_out(record)
	if shady:
		for item_id: String in _draw_items(GameData.as_dict(_data.record("stops", "shady_guy").get("stock"))):
			var deal: Offer = _item_offer(item_id)
			deal.shady = true
			offers.append(deal)
		_offer_restocks(true)
	_fill_tray()


func end() -> void:
	active = false
	offers = []
	picks_left = 0


# --- What the stop offers ----------------------------------------------------

## The service of a stop record: its entry effect and its offers.
func _lay_out(record: Dictionary) -> void:
	var stock: Dictionary = GameData.as_dict(record.get("stock"))
	var free: int = GameData.as_int(stock.get("free"))
	match GameData.as_string(record.get("service")):
		"tea":
			# A tea stall sets his Nerves and fills the glass, hot.
			_nerves.set_value(GameData.as_float(record.get("nerves_to")))
			for tea: ItemSim.Item in _items.items:
				if GameData.as_array(tea.record.get("tags")).has("tea"):
					_items.restock(tea)
		"repair":
			for item_id: String in _draw_items(stock):
				offers.append(_item_offer(item_id))
			for fault: StringName in _faults.active:
				var repair: Offer = Offer.new()
				repair.kind = REPAIR
				repair.id = String(fault)
				repair.price = _tuning.f("repair_price")
				offers.append(repair)
		"boss":
			# After a boss: one free item out of those shown, then one service.
			picks_left = free
			for item_id: String in _draw_items(stock):
				var pick: Offer = _item_offer(item_id)
				pick.free_pick = true
				pick.price = 0.0
				offers.append(pick)
		_:
			picks_left = free
			for item_id: String in _draw_items(stock):
				var offer: Offer = _item_offer(item_id)
				if free > 0:
					offer.free_pick = true
					offer.price = 0.0
				offers.append(offer)
	if GameData.as_bool(record.get("restocks")):
		_offer_restocks(false)


## A restock offer for each thing he has used: what is lawful from a stop
## that restocks, contraband from the shady guy alone (the flask is "sold
## only as a Deal", GDD 7.4).
func _offer_restocks(contraband: bool) -> void:
	for owned: ItemSim.Item in _items.items:
		if GameData.as_bool(owned.record.get("contraband")) != contraband:
			continue
		var supply: Dictionary = GameData.as_dict(owned.record.get("supply"))
		var uses: int = GameData.as_int(supply.get("uses"))
		var restock: float = GameData.as_float(supply.get("restock"))
		if uses > 0 and restock > 0.0 and (owned.supply < uses or _items.gone_cold(owned)):
			var refill: Offer = Offer.new()
			refill.kind = RESTOCK
			refill.id = String(owned.id)
			refill.price = roundf(restock * _price_mult)
			refill.shady = contraband
			offers.append(refill)


func _item_offer(item_id: String) -> Offer:
	var offer: Offer = Offer.new()
	offer.kind = ITEM
	offer.id = item_id
	offer.price = roundf(GameData.as_float(_data.record("items", item_id).get("price")) * _price_mult)
	return offer


## The services a boss stop lets him choose from: every stop that can be at
## the end of a leg.
func _lay_out_services() -> void:
	for record: Dictionary in _data.records("stops"):
		if GameData.as_float(record.get("weight")) <= 0.0:
			continue
		var choice: Offer = Offer.new()
		choice.kind = SERVICE
		choice.id = GameData.as_string(record.get("id"))
		offers.append(choice)


## `count` different items from the stock's pools that he does not own: for
## each, a rarity by this act's shares (GDD 9.6), then any item of it. A
## rarity the pools do not have gives the nearest one that they do.
func _draw_items(stock: Dictionary) -> Array[String]:
	var drawn: Array[String] = []
	var pools: Array = GameData.as_array(stock.get("pools"))
	var count: int = GameData.as_int(stock.get("count"))
	if pools.is_empty() or count <= 0:
		return drawn
	var by_rarity: Array[Array] = [[], [], []]
	for record: Dictionary in _data.records("items"):
		var id: String = GameData.as_string(record.get("id"))
		if not pools.has(GameData.as_string(record.get("kind"))) or _items.item(StringName(id)) != null:
			continue
		var rarity: int = DataValidator.RARITIES.find(GameData.as_string(record.get("rarity"), "common"))
		by_rarity[maxi(rarity, 0)].append(id)
	var shares: PackedFloat64Array = PackedFloat64Array()
	for share: Variant in GameData.as_array(_tuning.a("rarity_by_act")[clampi(_act, 1, RunGenerator.ACTS) - 1]):
		shares.append(GameData.as_float(share))
	for _pick: int in count:
		var rarity: int = _rng.weighted_index(Rng.SHOP, shares)
		var from: Array = []
		# The rarity drawn, else the nearest: one step commoner, one rarer, two...
		for step: int in [0, -1, 1, -2, 2]:
			var tier: int = rarity + step
			if tier >= 0 and tier < by_rarity.size() and not by_rarity[tier].is_empty():
				from = by_rarity[tier]
				break
		if from.is_empty():
			break
		var which: int = _rng.range_i(Rng.SHOP, 0, from.size() - 1)
		drawn.append(GameData.as_string(from[which]))
		from.remove_at(which)
	return drawn


## Moves waiting offers onto free places of the tray, in order. At a boss
## stop the services are held out once the free pick has left the tray, so
## that all of them can be seen together.
func _fill_tray() -> void:
	if _services_due:
		var still_there: bool = false
		for offer: Offer in offers:
			if offer.bought:
				still_there = true
		if not still_there:
			_services_due = false
			_lay_out_services()
	var taken: Dictionary = {}
	for offer: Offer in offers:
		if not offer.anchor.is_empty():
			taken[offer.anchor] = true
	for offer: Offer in offers:
		if not offer.anchor.is_empty():
			continue
		for place: String in TRAY:
			if not taken.has(place):
				offer.anchor = place
				taken[place] = true
				break


# --- The hand ----------------------------------------------------------------

func offer_at(anchor: String) -> Offer:
	for offer: Offer in offers:
		if offer.anchor == anchor:
			return offer
	return null


func anchor_in_use(anchor: String) -> bool:
	return active and offer_at(anchor) != null


## The ritual a press at this anchor starts: a TAP that buys, or a DRAG_TO
## that carries what he has bought to one of its slots. {} for none.
func ritual_at(anchor: String) -> Dictionary:
	if not active:
		return {}
	var offer: Offer = offer_at(anchor)
	if offer == null:
		return {}
	if offer.bought:
		return {"id": PLACE, "anchor": anchor, "gesture": "DRAG_TO", "to_any": slot_anchors(offer.id)}
	return {"id": BUY, "anchor": anchor, "gesture": "TAP"}


## The anchors of the slots an item can go in.
func slot_anchors(item_id: String) -> Array[String]:
	var anchors: Array[String] = []
	for slot: Variant in GameData.as_array(_data.record("items", item_id).get("slots")):
		var anchor: String = _items.anchor_of_slot(GameData.as_string(slot))
		if not anchor.is_empty() and not anchors.has(anchor):
			anchors.append(anchor)
	return anchors


## A TAP on the offer at `anchor`. Returns his cash afterwards.
func buy(anchor: String, cash: float) -> float:
	var offer: Offer = offer_at(anchor)
	if offer == null or offer.bought:
		return cash
	if offer.free_pick and picks_left <= 0:
		return cash
	if offer.price > cash:
		# Cash never goes below zero: he cannot have it.
		return cash
	match offer.kind:
		ITEM:
			var record: Dictionary = _data.record("items", offer.id)
			var slots: Array = GameData.as_array(record.get("slots"))
			var kind: String = GameData.as_string(record.get("kind"))
			if kind == "adaptation":
				var bay: String = _free_slot(slots)
				if bay.is_empty():
					# Every bay is taken (GDD 7.6: the car has three).
					return cash
				_pay(offer)
				_items.add_item(StringName(offer.id), StringName(bay))
				offers.erase(offer)
			elif slot_anchors(offer.id).is_empty():
				# Nothing the hand could carry it to: it is the car's own (the
				# roof, a deal that changes the car) and is his at once.
				var place_id: String = _free_slot(slots)
				if place_id.is_empty() and not slots.is_empty():
					place_id = GameData.as_string(slots[0])
					_items.remove_item(_items.item_in_slot(StringName(place_id)))
				_pay(offer)
				_items.add_item(StringName(offer.id), StringName(place_id))
				offers.erase(offer)
			else:
				_pay(offer)
				offer.bought = true
			events.append({"type": "item_bought", "item": offer.id, "price": offer.price, "free": offer.free_pick, "shady": offer.shady})
			if offer.free_pick:
				_pick_taken(offer)
		RESTOCK:
			var owned: ItemSim.Item = _items.item(StringName(offer.id))
			if owned == null:
				return cash
			_pay(offer)
			_items.restock(owned)
			offers.erase(offer)
			events.append({"type": "item_bought", "item": offer.id, "price": offer.price, "free": false, "shady": offer.shady, "restock": true})
		REPAIR:
			if not _faults.repair(StringName(offer.id)):
				return cash
			_pay(offer)
			if not free_minutes:
				_clock.add_minutes(_tuning.f("repair_minutes"))
			offers.erase(offer)
			events.append({"type": "fault_repaired", "fault": offer.id, "lamps": _faults.lamps, "price": offer.price})
		SERVICE:
			# The boss stop becomes the stop he chose, at no Clock cost.
			var chosen: Dictionary = _data.record("stops", offer.id)
			offers = []
			service = GameData.as_string(chosen.get("service"))
			_lay_out(chosen)
	_fill_tray()
	return cash - offer.price


func _pay(offer: Offer) -> void:
	if offer.shady and not shady_used:
		# Using the shady guy costs time, once (GDD 9.6).
		shady_used = true
		if not free_minutes:
			_clock.add_minutes(GameData.as_float(_tuning.d("stop_minutes").get(SHADY_KEY)))


## One of the free picks is his: when none is left to take, the others go,
## and a boss stop then offers its services (once the pick is in its place).
func _pick_taken(taken: Offer) -> void:
	picks_left -= 1
	if picks_left > 0:
		return
	var index: int = 0
	while index < offers.size():
		if offers[index].free_pick and offers[index] != taken:
			offers.remove_at(index)
		else:
			index += 1
	_services_due = service == BOSS_SERVICE


## The DRAG_TO from the tray ended on `to_anchor`: the item is in the slot
## there. False when it does not belong there.
func place(from_anchor: String, to_anchor: String) -> bool:
	var offer: Offer = offer_at(from_anchor)
	if offer == null or not offer.bought:
		return false
	var slots: Array = GameData.as_array(_data.record("items", offer.id).get("slots"))
	var here: Array = []
	for slot: Variant in slots:
		if _items.anchor_of_slot(GameData.as_string(slot)) == to_anchor:
			here.append(slot)
	if here.is_empty():
		return false
	var slot_id: String = _free_slot(here)
	if slot_id.is_empty():
		# The place is taken: what was there stays with the vendor.
		slot_id = GameData.as_string(here[0])
		_items.remove_item(_items.item_in_slot(StringName(slot_id)))
	_items.add_item(StringName(offer.id), StringName(slot_id))
	offers.erase(offer)
	_fill_tray()
	return true


func _free_slot(slots: Array) -> String:
	for slot: Variant in slots:
		if _items.item_in_slot(StringName(GameData.as_string(slot))) == null:
			return GameData.as_string(slot)
	return ""


## He leaves. What he paid for and did not place is paid back. Returns his cash.
func leave(cash: float) -> float:
	for offer: Offer in offers:
		if offer.bought:
			cash += offer.price
	end()
	return cash


# --- For the views -----------------------------------------------------------

func offers_view() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for offer: Offer in offers:
		if offer.anchor.is_empty():
			continue
		out.append({
			"anchor": offer.anchor,
			"kind": offer.kind,
			"id": offer.id,
			"price": offer.price,
			"free": offer.free_pick,
			"shady": offer.shady,
			"bought": offer.bought,
		})
	return out
