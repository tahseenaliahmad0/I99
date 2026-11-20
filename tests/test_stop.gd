extends TestSuite
## M5: stops and the shop (GDD 9.6).
##
## Each stop is reached the way a player reaches it: a Telling, its first
## fork, a leg, the slip lane and the stall. The leg is a quiet one (its
## traffic and hazards taken out) so that the test is about the stop.

const DT: float = DriveSim.DT
const KMH_TO_MS: float = 1.0 / 3.6
const TABLE: String = "drivers"

var _sim: DriveSim
var _input: DriveInput
var _events: Array[Dictionary] = []
var _clock_at_stall: float = 0.0


func before_each() -> void:
	_sim = DriveSim.new(fresh_data())
	_input = DriveInput.new()
	_events = []


## T-STOP-01: Stops of 9.6: each stop charges its Clock minutes on entry and
## offers its service; a TAP on an offer buys it when cash allows (cash never
## goes below 0) and a DRAG_TO places it in a slot; gripping the wheel for
## 0.5 s leaves; the shady guy joins the next stop only after a leg with no
## lamp lit and adds 5 minutes when used; after a boss the player takes one
## free item out of 3 and one service at no Clock cost; shop rarity follows
## rarity_by_act.
func test_stop_01() -> void:
	_check_data()
	_check_fuel_station()
	_check_fitter()
	_check_tea_stall()
	_check_roadside_find()
	_check_roof_item()
	_check_hitcher()
	_check_shady_guy()
	_check_boss_stop()
	_check_only_the_shopping()
	_check_snap_at_a_stop()
	_check_rarity()


func _check_data() -> void:
	var minutes: Dictionary = tuning.d("stop_minutes")
	var weights: Dictionary = tuning.d("stop_weights")
	# GDD 9.6 and 15: minutes and weights of the five stops, and the shady guy's minutes.
	var table: Array = [
		["fuel_station", "fuel", 10.0, 30.0], ["fitter", "fitter", 15.0, 20.0], ["tea_stall", "tea", 20.0, 20.0],
		["roadside_find", "find", 5.0, 15.0], ["hitcher", "hitcher", 2.0, 15.0],
	]
	for entry: Variant in table:
		var row: Array = entry
		var stop: Dictionary = data.record("stops", str(row[0]))
		check_near(GameData.as_float(minutes.get(row[1])), GameData.as_float(row[2]), 0.000001, "GDD 9.6: %s costs %s game minutes" % [str(row[0]), str(row[2])])
		check_near(GameData.as_float(stop.get("clock_min")), GameData.as_float(row[2]), 0.000001, "and its record says so")
		check_near(GameData.as_float(weights.get(row[1])), GameData.as_float(row[3]), 0.000001, "GDD 15: its weight is %s" % str(row[3]))
		check_near(GameData.as_float(stop.get("weight")), GameData.as_float(row[3]), 0.000001, "in its record too")
	check_near(GameData.as_float(minutes.get("shady")), 5.0, 0.000001, "using the shady guy adds 5 minutes")
	check_near(tuning.f("repair_price"), 15.0, 0.000001, "a repair is 15 cash")
	check_near(tuning.f("repair_minutes"), 5.0, 0.000001, "and 5 game minutes")
	check_eq(data.records("items").size(), 32, "the catalogue holds the 32 items of GDD 7")
	var kinds: Dictionary = {}
	for record: Dictionary in data.records("items"):
		var kind: String = GameData.as_string(record.get("kind"))
		kinds[kind] = GameData.as_int(kinds.get(kind)) + 1
		var price: float = GameData.as_float(record.get("price"))
		var rarity: String = GameData.as_string(record.get("rarity"))
		# GDD 12.2: common 10 to 30, uncommon 35 to 50, rare 55 to 60.
		var wanted: String = "common" if price <= 30.0 else ("uncommon" if price <= 50.0 else "rare")
		check_eq(rarity, wanted, "%s at %s cash is %s (GDD 12.2)" % [str(record.get("id")), str(price), wanted])
	check_eq(GameData.as_int(kinds.get("keepsake")), 7, "seven Keepsakes")
	check_eq(GameData.as_int(kinds.get("adaptation")), 10, "ten Adaptations")
	check_eq(GameData.as_int(kinds.get("habit")) + GameData.as_int(kinds.get("deal")), 15, "eleven Habits and four Deals (the flask is a Habit sold as a Deal)")


# --- Fuel station ------------------------------------------------------------

func _check_fuel_station() -> void:
	_to_quiet_leg("fuel_station")
	_scrape()
	_into_stall()
	var entered: Dictionary = _event("stop_entered")
	check_eq(_sim.run.stop, "fuel_station", "he is at a fuel station")
	check_near(GameData.as_float(entered.get("minutes")), 10.0, 0.000001, "which charges 10 game minutes on entry")
	check_near(_sim.clock.minutes - _clock_at_stall, 10.0, 0.01, "at once, on the Clock")
	check(not GameData.as_bool(entered.get("shady")), "(a lamp was lit on the way: no shady guy)")
	var offers: Array[Dictionary] = _offers()
	var for_sale: Array[Dictionary] = _of_kind(offers, StopSim.ITEM)
	check_eq(for_sale.size(), 3, "it has three items for sale")
	var seen: Dictionary = {}
	for offer: Dictionary in for_sale:
		var record: Dictionary = data.record("items", GameData.as_string(offer["id"]))
		check(GameData.as_string(record.get("kind")) in ["habit", "keepsake"], "%s is a Habit or a Keepsake" % str(offer["id"]))
		check(_sim.items.item(StringName(GameData.as_string(offer["id"]))) == null, "that he does not have")
		check_near(GameData.as_float(offer["price"]), GameData.as_float(record.get("price")), 0.000001, "at its price")
		seen[offer["id"]] = true
	check_eq(seen.size(), 3, "three different ones")
	var restocks: Array[Dictionary] = _of_kind(offers, StopSim.RESTOCK)
	check_eq(restocks.size(), 1, "and a restock of what he has used: the cigarettes (5 of 10 at the start)")
	var anchors: Array = GameData.as_array(_sim.snapshot()["anchors_in_use"])
	for offer: Dictionary in offers:
		check(anchors.has(StringName(GameData.as_string(offer["anchor"]))), "the hand can reach %s on the vendor's tray" % str(offer["anchor"]))

	# A TAP buys when cash allows.
	var first: Dictionary = for_sale[0]
	var first_id: String = first["id"]
	var price: float = first["price"]
	_sim.cash = price + 7.0
	_events = []
	_tap(GameData.as_string(first["anchor"]))
	check_near(_sim.cash, 7.0, 0.000001, "a TAP on an offer buys it: its price leaves his cash")
	var bought: Dictionary = _event("item_bought")
	check_eq(GameData.as_string(bought.get("item")), first_id, "which is announced")
	check(GameData.as_bool(_offer_at(GameData.as_string(first["anchor"])).get("bought")), "it is his now, still on the tray")
	check(_sim.items.item(StringName(first_id)) == null, "and not yet in the cabin")
	_tap(GameData.as_string(first["anchor"]))
	check_near(_sim.cash, 7.0, 0.000001, "a second TAP does not charge him again")

	# A DRAG_TO places it in a slot.
	var slots: Array = GameData.as_array(data.record("items", first_id).get("slots"))
	var slot: String = GameData.as_string(slots[slots.size() - 1])
	var slot_anchor: String = _sim.items.anchor_of_slot(slot)
	_drag(GameData.as_string(first["anchor"]), slot_anchor)
	var placed: ItemSim.Item = _sim.items.item(StringName(first_id))
	if check(placed != null, "a DRAG_TO from the tray to one of its slots puts it in the cabin"):
		check_eq(_sim.items.anchor_of(placed), slot_anchor, "at the anchor it was carried to")
	check(_offer_with(first_id).is_empty(), "and it is off the tray")
	check_near(_sim.cash, 7.0, 0.000001, "placing costs nothing")

	# Cash never goes below zero.
	var second: Dictionary = for_sale[1]
	var second_price: float = second["price"]
	_sim.cash = second_price - 1.0
	_events = []
	_tap(GameData.as_string(second["anchor"]))
	check_near(_sim.cash, second_price - 1.0, 0.000001, "one cash short, a TAP buys nothing")
	check(not _has_event("item_bought"), "and nothing is announced")
	check(not GameData.as_bool(_offer_at(GameData.as_string(second["anchor"])).get("bought")), "the offer stays the vendor's")
	_sim.cash = second_price
	_tap(GameData.as_string(second["anchor"]))
	check_near(_sim.cash, 0.0, 0.000001, "with exactly its price he buys it and has nothing left: cash never goes below 0")

	# A restock.
	var pack: ItemSim.Item = _sim.items.item(&"cigarettes")
	var restock: Dictionary = restocks[0]
	check_eq(GameData.as_string(restock["id"]), "cigarettes", "(the restock is the cigarettes')")
	check_near(GameData.as_float(restock["price"]), GameData.as_float(GameData.as_dict(pack.record.get("supply")).get("restock")), 0.000001, "at the pack's restock price")
	_sim.cash = 20.0
	_tap(GameData.as_string(restock["anchor"]))
	check_eq(pack.supply, GameData.as_int(GameData.as_dict(pack.record.get("supply")).get("uses")), "a TAP on it fills the pack")
	check_near(_sim.cash, 20.0 - GameData.as_float(restock["price"]), 0.000001, "for its price")

	# Leaving: what he paid for and did not place is paid back.
	var cash_before: float = _sim.cash
	_leave()
	check(not _sim.stopped, "gripping the wheel leaves the stop")
	check_near(_sim.cash, cash_before + second_price, 0.000001, "what he bought and did not place is paid back")
	check(_sim.items.item(StringName(GameData.as_string(second["id"]))) == null, "and stays with the vendor")
	check(_offers().is_empty(), "the tray is gone")
	anchors = GameData.as_array(_sim.snapshot()["anchors_in_use"])
	check(not anchors.has(&"offer_1"), "and so are its anchors")

	# A slot that is taken: what was there stays with the vendor.
	_to_quiet_leg("fuel_station")
	_scrape()
	_into_stall()
	for offer: Dictionary in _of_kind(_offers(), StopSim.ITEM):
		var id: String = offer["id"]
		var its_slots: Array = GameData.as_array(data.record("items", id).get("slots"))
		if its_slots.size() != 1:
			continue
		# Something of his own already sits where it goes.
		var only: String = GameData.as_string(its_slots[0])
		var squatter: String = "air_freshener" if only == "mirror" else ("thermos" if only == "seat" else "")
		if squatter.is_empty() or squatter == id:
			continue
		_sim.items.add_item(StringName(squatter), StringName(only))
		_sim.cash = 100.0
		_tap(GameData.as_string(offer["anchor"]))
		_drag(GameData.as_string(offer["anchor"]), _sim.items.anchor_of_slot(only))
		var there: ItemSim.Item = _sim.items.item_in_slot(StringName(only))
		check(there != null and there.id == StringName(id), "%s takes the %s" % [id, only])
		check(_sim.items.item(StringName(squatter)) == null, "and what hung there stays with the vendor")
		break


# --- Fitter ------------------------------------------------------------------

func _check_fitter() -> void:
	_to_quiet_leg("fitter")
	_scrape()
	_scrape()
	check_eq(_sim.faults.lamps, 2, "(two lamps are lit on the way)")
	var lit: Array[StringName] = _sim.faults.active.duplicate()
	_into_stall()
	check_eq(_sim.run.stop, "fitter", "he is at a fitter's")
	check_near(_sim.clock.minutes - _clock_at_stall, 15.0, 0.01, "which charges 15 game minutes on entry")
	var offers: Array[Dictionary] = _offers()
	var fittings: Array[Dictionary] = _of_kind(offers, StopSim.ITEM)
	check_eq(fittings.size(), 2, "he has two things to fit")
	for offer: Dictionary in fittings:
		check_eq(GameData.as_string(data.record("items", GameData.as_string(offer["id"])).get("kind")), "adaptation", "%s is an Adaptation" % str(offer["id"]))
	var repairs: Array[Dictionary] = _of_kind(offers, StopSim.REPAIR)
	check_eq(repairs.size(), 2, "and offers to repair each lit fault")
	for repair: Dictionary in repairs:
		check(lit.has(StringName(GameData.as_string(repair["id"]))), "%s is one of them" % str(repair["id"]))
		check_near(GameData.as_float(repair["price"]), tuning.f("repair_price"), 0.000001, "for 15 cash")

	# A repair: the chosen fault and its lamp, 15 cash, 5 game minutes.
	var chosen: Dictionary = repairs[1]
	var clock_before: float = _sim.clock.minutes
	_sim.cash = 40.0
	_events = []
	_tap(GameData.as_string(chosen["anchor"]))
	check_eq(_sim.faults.lamps, 1, "a TAP on a repair puts that lamp out")
	check(not _sim.faults.has(StringName(GameData.as_string(chosen["id"]))), "the fault he chose is gone")
	check(_sim.faults.has(StringName(GameData.as_string(repairs[0]["id"]))), "and the other is still there")
	check_near(_sim.cash, 40.0 - tuning.f("repair_price"), 0.000001, "for 15 cash")
	check_near(_sim.clock.minutes - clock_before, tuning.f("repair_minutes"), 0.000001, "and 5 game minutes")
	check_eq(GameData.as_string(_event("fault_repaired").get("fault")), GameData.as_string(chosen["id"]), "which is announced")
	_sim.cash = tuning.f("repair_price") - 1.0
	_tap(GameData.as_string(_of_kind(_offers(), StopSim.REPAIR)[0]["anchor"]))
	check_eq(_sim.faults.lamps, 1, "without the cash there is no repair")

	# An adaptation goes straight into a bay; with no bay free it cannot be had.
	var fitting: Dictionary = fittings[0]
	_sim.cash = 100.0
	_tap(GameData.as_string(fitting["anchor"]))
	var fitted: ItemSim.Item = _sim.items.item(StringName(GameData.as_string(fitting["id"])))
	if check(fitted != null, "a TAP on an Adaptation fits it at once"):
		check_eq(fitted.slot, &"bay_1", "in the first free bay")
	check_near(_sim.cash, 100.0 - GameData.as_float(fitting["price"]), 0.000001, "for its price")
	var other: Dictionary = fittings[1]
	var fillers: Array[String] = []
	for record: Dictionary in data.records("items"):
		var id: String = GameData.as_string(record.get("id"))
		if GameData.as_string(record.get("kind")) == "adaptation" and id != GameData.as_string(other["id"]) and _sim.items.item(StringName(id)) == null:
			fillers.append(id)
	_sim.items.add_item(StringName(fillers[0]), &"bay_2")
	_sim.items.add_item(StringName(fillers[1]), &"bay_3")
	var cash_before: float = _sim.cash
	_tap(GameData.as_string(_offer_with(GameData.as_string(other["id"]))["anchor"]))
	check(_sim.items.item(StringName(GameData.as_string(other["id"]))) == null, "with all three bays taken a fourth Adaptation cannot be bought")
	check_near(_sim.cash, cash_before, 0.000001, "and costs nothing")


# --- Tea stall, roadside find, hitcher ---------------------------------------

func _check_tea_stall() -> void:
	_to_quiet_leg("tea_stall")
	_scrape()
	_sim.nerves.set_value(82.0)
	var glass: ItemSim.Item = _sim.items.item(&"tea_glass")
	glass.supply = 1
	glass.hot_left = 0.0
	_into_stall()
	# (A stop makes the simulation anew from what a save holds: look again.)
	glass = _sim.items.item(&"tea_glass")
	check_eq(_sim.run.stop, "tea_stall", "he is at a tea stall")
	check_near(_sim.clock.minutes - _clock_at_stall, 20.0, 0.01, "which charges 20 game minutes on entry")
	check_near(_sim.nerves.value, GameData.as_float(data.record("stops", "tea_stall").get("nerves_to")), 0.000001, "and sets his Nerves to 30")
	check_near(_sim.nerves.value, 30.0, 0.000001, "(30, GDD 9.6)")
	check_eq(glass.supply, GameData.as_int(GameData.as_dict(glass.record.get("supply")).get("uses")), "the tea is refilled")
	check(glass.hot_left > 0.0, "hot")
	check(_of_kind(_offers(), StopSim.ITEM).is_empty(), "it sells nothing")
	# Waiting calms nobody: the night stands still at a stop.
	_sim.nerves.set_value(70.0)
	var clock_before: float = _sim.clock.minutes
	_input.clear()
	for _tick: int in int(5.0 / DT):
		_sim.step(_input)
	check_near(_sim.nerves.value, 70.0, 0.000001, "standing at a stop does nothing to his Nerves")
	check_near(_sim.clock.minutes, clock_before, 0.000001, "nor to the Clock: a stop is untimed (GDD 6.4)")
	check(glass.hot_left > 0.0 and is_equal_approx(glass.hot_left, GameData.as_float(GameData.as_dict(glass.record.get("params")).get("hot_for_s"))), "and the tea does not go cold")


func _check_roadside_find() -> void:
	_to_quiet_leg("roadside_find")
	_scrape()
	_into_stall()
	check_eq(_sim.run.stop, "roadside_find", "he is at a roadside find")
	check_near(_sim.clock.minutes - _clock_at_stall, 5.0, 0.01, "which charges 5 game minutes on entry")
	var finds: Array[Dictionary] = _of_kind(_offers(), StopSim.ITEM)
	check_eq(finds.size(), 2, "two things lie there")
	for find: Dictionary in finds:
		check_eq(GameData.as_string(data.record("items", GameData.as_string(find["id"])).get("kind")), "keepsake", "%s is a Keepsake" % str(find["id"]))
		check(GameData.as_bool(find["free"]) and is_zero_approx(GameData.as_float(find["price"])), "and free")
	_sim.cash = 0.0
	_events = []
	_tap(GameData.as_string(finds[1]["anchor"]))
	check_near(_sim.cash, 0.0, 0.000001, "a TAP takes one, for nothing")
	check(GameData.as_bool(_event("item_bought").get("free")), "announced as free")
	var left: Array[Dictionary] = _of_kind(_offers(), StopSim.ITEM)
	check_eq(left.size(), 1, "the other is gone: one out of the two")
	check_eq(GameData.as_string(left[0]["id"]), GameData.as_string(finds[1]["id"]), "what is left on the tray is the one he took")
	var anchor: String = _sim.items.anchor_of_slot(GameData.as_string(GameData.as_array(data.record("items", GameData.as_string(finds[1]["id"])).get("slots"))[0]))
	if anchor.is_empty():
		check(_sim.items.item(StringName(GameData.as_string(finds[1]["id"]))) != null, "something for the roof is his at once")
	else:
		_drag(GameData.as_string(left[0]["anchor"]), anchor)
		check(_sim.items.item(StringName(GameData.as_string(finds[1]["id"]))) != null, "and he puts it in its place")


## What the hand cannot carry anywhere (the taxi sign goes on the roof) is
## his the moment he takes it.
func _check_roof_item() -> void:
	_sim = DriveSim.new(fresh_data())
	var found: bool = false
	for candidate: int in range(1, 400):
		_sim.reseed(candidate)
		_sim.stop.begin("roadside_find", 1, false)
		for offer: Dictionary in _sim.stop.offers_view():
			if GameData.as_string(offer["id"]) == "taxi_sign":
				found = true
				_sim.stop.buy(GameData.as_string(offer["anchor"]), 0.0)
		if found:
			break
	if not check(found, "(a roadside find with the taxi sign)"):
		return
	var sign_item: ItemSim.Item = _sim.items.item(&"taxi_sign")
	if check(sign_item != null, "the taxi sign is his at once: there is nowhere to carry it"):
		check_eq(sign_item.slot, &"roof", "it is on the roof")
	check(_sim.stop.offers_view().is_empty(), "and nothing is left on the tray")


func _check_hitcher() -> void:
	_to_quiet_leg("hitcher")
	_scrape()
	_into_stall()
	check_eq(_sim.run.stop, "hitcher", "he is where a hitcher stands")
	check_near(_sim.clock.minutes - _clock_at_stall, 2.0, 0.01, "which charges 2 game minutes on entry")
	check(_of_kind(_offers(), StopSim.ITEM).is_empty(), "nothing is for sale there")


# --- The shady guy -----------------------------------------------------------

func _check_shady_guy() -> void:
	# After a leg that lit no lamp he is at the stop as a second vendor.
	_to_quiet_leg("hitcher")
	check_eq(_sim.faults.lamps, 0, "(no lamp was lit on this leg)")
	_into_stall()
	check(GameData.as_bool(_event("stop_entered").get("shady")), "after a leg with no lamp lit the shady guy is at the stop")
	var deals: Array[Dictionary] = _of_kind(_offers(), StopSim.ITEM)
	check_eq(deals.size(), 2, "with two things")
	var seen: Dictionary = {}
	for deal: Dictionary in deals:
		check(GameData.as_bool(deal["shady"]), "his own")
		check_eq(GameData.as_string(data.record("items", GameData.as_string(deal["id"])).get("kind")), "deal", "%s is a Deal" % str(deal["id"]))
		seen[deal["id"]] = true
	check_eq(seen.size(), 2, "two different ones")
	# Using him adds 5 minutes, once.
	var clock_before: float = _sim.clock.minutes
	_sim.cash = 200.0
	_tap(GameData.as_string(deals[0]["anchor"]))
	check_near(_sim.cash, 200.0 - GameData.as_float(deals[0]["price"]), 0.000001, "a TAP buys a Deal for its price")
	check_near(_sim.clock.minutes - clock_before, GameData.as_float(tuning.d("stop_minutes").get("shady")), 0.000001, "and using him adds 5 minutes")
	var first: Dictionary = data.record("items", GameData.as_string(deals[0]["id"]))
	if GameData.as_array(first.get("slots")).is_empty():
		check(_sim.items.item(StringName(GameData.as_string(deals[0]["id"]))) != null, "a Deal that changes the car is his at once")
	else:
		check(GameData.as_bool(_offer_with(GameData.as_string(deals[0]["id"])).get("bought")), "a Deal that goes in a slot is his to place")
	_tap(GameData.as_string(_offer_with(GameData.as_string(deals[1]["id"]))["anchor"]))
	check_near(_sim.clock.minutes - clock_before, GameData.as_float(tuning.d("stop_minutes").get("shady")), 0.000001, "a second Deal adds no more minutes")
	check_near(_sim.cash, 200.0 - GameData.as_float(deals[0]["price"]) - GameData.as_float(deals[1]["price"]), 0.000001, "only its price")

	# Looking is free.
	_to_quiet_leg("hitcher")
	_into_stall()
	var looked_at: float = _sim.clock.minutes
	_leave()
	check_near(_sim.clock.minutes, looked_at, 0.01, "leaving without using him costs no minutes")

	# After a leg with a lamp lit he is not there.
	_to_quiet_leg("hitcher")
	_scrape()
	_into_stall()
	check(not GameData.as_bool(_event("stop_entered").get("shady")), "after a leg with a lamp lit there is no shady guy")
	check(_offers().is_empty(), "and no Deal")


# --- After a boss ------------------------------------------------------------

func _check_boss_stop() -> void:
	for service: String in ["fitter", "tea_stall"]:
		_to_boss_stop()
		check_eq(_sim.run.stage, RunState.Stage.BOSS_STOP, "after the boss he stands at its stop")
		check_eq(_sim.run.stop, "boss_stop", "the boss stop")
		check_near(GameData.as_float(_event("stop_entered").get("minutes")), 0.0, 0.000001, "which charges no Clock minutes")
		check_near(_sim.clock.minutes, _clock_at_stall, 0.01, "the Clock stands")
		var picks: Array[Dictionary] = _offers()
		check_eq(picks.size(), 3, "three items are held out")
		for pick: Dictionary in picks:
			check_eq(str(pick["kind"]), String(StopSim.ITEM), "(an item)")
			check(GameData.as_bool(pick["free"]) and is_zero_approx(GameData.as_float(pick["price"])), "%s is free" % str(pick["id"]))
		# One of the three.
		_sim.cash = 3.0
		var pick: Dictionary = picks[2]
		_tap(GameData.as_string(pick["anchor"]))
		check_near(_sim.cash, 3.0, 0.000001, "he takes one for nothing")
		var taken: bool = _sim.items.item(StringName(GameData.as_string(pick["id"]))) != null or GameData.as_bool(_offer_with(GameData.as_string(pick["id"])).get("bought"))
		check(taken, "it is his")
		for other: Dictionary in picks:
			if other["id"] != pick["id"]:
				check(_offer_with(GameData.as_string(other["id"])).is_empty(), "%s is taken away: one out of three" % str(other["id"]))
		# Then one service of his choice, once the pick is in its place.
		var pick_slots: Array = GameData.as_array(data.record("items", GameData.as_string(pick["id"])).get("slots"))
		if GameData.as_bool(_offer_with(GameData.as_string(pick["id"])).get("bought")):
			check(_of_kind(_offers(), StopSim.SERVICE).is_empty(), "(the services wait until his pick is off the tray)")
			_drag(GameData.as_string(_offer_with(GameData.as_string(pick["id"]))["anchor"]), _sim.items.anchor_of_slot(GameData.as_string(pick_slots[0])))
			check(_sim.items.item(StringName(GameData.as_string(pick["id"]))) != null, "he puts it in its place")
		var services: Array[Dictionary] = _of_kind(_offers(), StopSim.SERVICE)
		check_eq(services.size(), 5, "then the five services are his to choose from")
		check_eq(_offers().size(), 5, "and nothing else")
		var clock_before: float = _sim.clock.minutes
		_sim.nerves.set_value(77.0)
		_sim.cash = 50.0
		_tap(GameData.as_string(_offer_with(service)["anchor"]))
		check(_of_kind(_offers(), StopSim.SERVICE).is_empty(), "choosing one (%s) ends the choice: one service" % service)
		check_near(_sim.clock.minutes, clock_before, 0.000001, "at no Clock cost")
		if service == "tea_stall":
			check_near(_sim.nerves.value, 30.0, 0.000001, "tea: his Nerves are set to 30")
		else:
			var repairs: Array[Dictionary] = _of_kind(_offers(), StopSim.REPAIR)
			check_eq(repairs.size(), _sim.faults.lamps, "the fitter: a repair for each lit fault")
			if check(not repairs.is_empty(), "(a lamp was lit in the boss)"):
				var lamps: int = _sim.faults.lamps
				_tap(GameData.as_string(repairs[0]["anchor"]))
				check_eq(_sim.faults.lamps, lamps - 1, "a repair still costs its cash")
				check_near(_sim.cash, 50.0 - tuning.f("repair_price"), 0.000001, "15")
				check_near(_sim.clock.minutes, clock_before, 0.000001, "but no minutes: nothing at a boss stop costs the Clock")
		_leave()
		check_eq(_sim.run.stage, RunState.Stage.APPROACH, "gripping the wheel leaves for the next act's first fork")
		check_eq(_sim.run.act, 2, "in Act 2")


# --- Only the shopping -------------------------------------------------------

## The cabin's own rituals, in the order _work_the_cabin tries them.
const CABIN_RITUALS: Array = ["horn", "slap", "beads_count", "cig_light", "tea_sip", "visor_photo", "radio_tune"]


## At a stop the hand does the shopping and nothing else (GDD 9.6). The
## cabin's own rituals are the road's: done at the stall they would be calm
## and power for no time off the wheel (GDD 2.2, 12.4). They are not offered
## there, and their anchors are not in use.
func _check_only_the_shopping() -> void:
	_to_quiet_leg("fuel_station")
	_scrape()
	_sim.items.add_item(&"beads", &"mirror")
	_sim.items.add_item(&"thumb_keypad", &"bay_1")
	# On the road the cabin is his: the hand does every one of these.
	_sim.nerves.set_value(40.0)
	var road: Dictionary = _work_the_cabin()
	check_eq(GameData.as_array(road["rituals"]), CABIN_RITUALS, "(on the road the hand does all of it: the horn, a slap, a bead, a cigarette, a sip, the photo, the dial)")
	check(GameData.as_bool(road["lever"]), "(takes the gear lever)")
	check(GameData.as_bool(road["keypad"]), "(and honks with the thumb of the hand that grips)")
	check(_sim.effects.has(&"lit") and _sim.items.radio != ItemSim.STATIC, "(so that a cigarette burns and the radio plays)")

	_into_stall()
	var tray: Array[String] = []
	for offer: Dictionary in _offers():
		tray.append(GameData.as_string(offer["anchor"]))
	var in_use: Array[String] = []
	for anchor: Variant in GameData.as_array(_sim.snapshot()["anchors_in_use"]):
		in_use.append(str(anchor))
	tray.sort()
	in_use.sort()
	check(not tray.is_empty(), "(the vendor's tray is laid out)")
	check_eq(in_use, tray, "at a stop the hand has the vendor's tray to go to, and nothing of the cabin's")
	_sim.nerves.set_value(60.0)
	var before: Array = _cabin_state()
	var stall: Dictionary = _work_the_cabin()
	check_eq(GameData.as_array(stall["rituals"]), [], "at a stop none of the cabin's rituals is offered: not the horn, a slap, a bead, a cigarette, a sip, the photo or the dial")
	check(not GameData.as_bool(stall["lever"]), "the gear lever is not taken")
	check(not GameData.as_bool(stall["keypad"]), "and the thumb keypad does not honk")
	check_eq(_cabin_state(), before, "nothing in the cabin has changed: his Nerves, the pack, the glass, the radio, his statuses, the gear")
	check(_sim.stopped, "(he is still at the stop)")
	# The shopping itself is his as ever.
	var restock: Dictionary = _of_kind(_offers(), StopSim.RESTOCK)[0]
	_sim.cash = 50.0
	_tap(GameData.as_string(restock["anchor"]))
	check_near(_sim.cash, 50.0 - GameData.as_float(restock["price"]), 0.000001, "the tray is: a TAP still buys")
	# And on the road again, so is the cabin.
	_leave()
	check(not _sim.stopped, "(he leaves)")
	check(GameData.as_array(_sim.snapshot()["anchors_in_use"]).has(&"horn"), "back on the road the cabin is his again")
	_events = []
	_press_at("horn", tuning.f("tap_max_time") * 0.3)
	_press_at("mirror", tuning.f("tap_max_time") * 0.3)
	check_eq(_rituals_completed(), ["horn", "beads_count"], "and the hand does there what it could not at the stall")


## A Snap's two seconds are the hand's own, not the night's (GDD 6.1): at a
## stop, where nothing else of him moves on, they still run down, and then
## the tray is his to reach.
func _check_snap_at_a_stop() -> void:
	var snap_ticks: int = roundi(tuning.f("snap_duration") / DT)
	# On the road.
	_to_quiet_leg("fuel_station")
	_scrape()
	_sim.nerves.add(tuning.f("snap_at"))
	check(_sim.nerves.snap_left > 0.0, "(Nerves at the top: a Snap)")
	check_eq(_ticks_until_snap_ends(), snap_ticks, "(on the road a Snap lasts snap_duration)")
	# At a stop.
	_into_stall()
	var offer: Dictionary = _of_kind(_offers(), StopSim.ITEM)[0]
	var price: float = offer["price"]
	_sim.cash = price + 5.0
	_sim.nerves.add(tuning.f("snap_at"))
	check(_sim.nerves.snap_left > 0.0, "(a Snap at the stop)")
	# While it lasts he cannot reach the tray.
	_input.clear()
	_input.pointer_is_absolute = true
	_input.pointer = _sim.hand.anchor_pointer(_sim.hand.anchor_index(StringName(GameData.as_string(offer["anchor"]))))
	var tried: int = snap_ticks - roundi(0.5 / DT)
	for tick: int in tried:
		_input.lmb = tick % 30 < 4
		_sim.step(_input)
	_input.lmb = false
	check(GameData.as_bool(_sim.snapshot()["snap"]), "(half a second short of snap_duration the Snap is still on)")
	check_eq(_sim.hand.snap_index, HandSim.NO_ANCHOR, "in a Snap at a stop the pointer snaps to nothing")
	check_near(_sim.cash, price + 5.0, 0.000001, "and his clicks at the tray buy nothing")
	check_eq(tried + _ticks_until_snap_ends(), snap_ticks, "the Snap runs down at a stop as on the road: after snap_duration it is over")
	check(_sim.stopped, "(he is still at the stop)")
	_tap(GameData.as_string(offer["anchor"]))
	check_near(_sim.cash, 5.0, 0.000001, "and the tray is his again: a TAP buys")


## Everything the cabin offers him on the road, tried once by the hand: the
## horn, a slap, a bead, a cigarette lit, a sip of tea, the photo, the
## radio's dial; then the gear lever, and the horn under the thumb of the
## hand that grips (the thumb keypad). Returns the rituals that were
## completed ("rituals"), whether the lever was in his hand ("lever") and
## whether the keypad honked ("keypad").
func _work_the_cabin() -> Dictionary:
	_collect()
	_events = []
	var tap: float = tuning.f("tap_max_time") * 0.3
	var flick: float = tuning.f("flick_max_time") * 0.4
	var flick_ticks: float = float(roundi(flick / DT))
	_press_at("horn", tap)
	_press_at("face", tap)
	_press_at("mirror", tap)
	_press_at("ashtray", GameData.as_float(data.record("rituals", "cig_light").get("hold_s")) + 0.1)
	_press_at("cup_a", GameData.as_float(data.record("rituals", "tea_sip").get("hold_s")) + 0.1)
	_press_at("visor", flick, Vector2(0.0, tuning.f("flick_min_distance") * 1.5 / flick_ticks))
	_press_at("radio", flick, Vector2(tuning.f("radio_step_px") * 1.5 / flick_ticks, 0.0))
	var rituals: Array = _rituals_completed()
	# The gear lever: taken in hand, and let go where it is.
	_input.clear()
	_input.pointer_is_absolute = true
	_input.pointer = _sim.hand.anchor_pointer(_sim.hand.anchor_index(DriveSim.GEAR_LEVER))
	_steps(1.0)
	_input.lmb = true
	_steps(0.1)
	var lever: bool = GameData.as_bool(_sim.snapshot()["lever_held"])
	_input.clear()
	_steps(0.3)
	# The thumb keypad: the wheel taken (for less than it takes to leave a
	# stop) and the horn pressed under the thumb.
	_events = []
	_input.pointer_is_absolute = true
	_input.pointer = _sim.space.point_to_pointer(_sim.space.grip_reference)
	_input.lmb = true
	var guard: int = int(2.0 / DT)
	while not _sim.hand.gripping and guard > 0:
		guard -= 1
		_steps(DT)
	_input.pad_horn = true
	_steps(3.0 * DT)
	_input.clear()
	_steps(0.3)
	var keypad: bool = false
	for event: Dictionary in _events:
		if GameData.as_string(event.get("type")) == "ritual_completed" and GameData.as_bool(event.get("keypad")):
			keypad = true
	return {"rituals": rituals, "lever": lever, "keypad": keypad}


## The rituals announced as completed since _events was last emptied, in order.
func _rituals_completed() -> Array:
	var rituals: Array = []
	for event: Dictionary in _events:
		if GameData.as_string(event.get("type")) == "ritual_completed":
			rituals.append(GameData.as_string(event.get("ritual")))
	return rituals


## What the cabin's rituals would change, read off the simulation.
func _cabin_state() -> Array:
	return [
		_sim.nerves.value, _sim.items.item(&"cigarettes").supply, _sim.items.item(&"tea_glass").supply,
		String(_sim.items.radio), _sim.effects.active_ids().size(), _sim.items.photo_used, _sim.gate.gear,
		_sim.items.haze, _sim.clock.minutes, _sim.cash,
	]


## The hand goes to an anchor, if it may, and the button is held there for
## `seconds` while the pointer moves `motion` a tick; then it is let go.
func _press_at(anchor: String, seconds: float, motion: Vector2 = Vector2.ZERO) -> void:
	_input.clear()
	_input.pointer_is_absolute = true
	_input.pointer = _sim.hand.anchor_pointer(_sim.hand.anchor_index(StringName(anchor)))
	_steps(1.0)
	_input.lmb = true
	if motion != Vector2.ZERO:
		_input.pointer_is_absolute = false
		_input.pointer_delta = motion
	_steps(seconds)
	_input.clear()
	_steps(0.3)


## Steps for `seconds`; on the road the car is kept in the middle of its lane.
func _steps(seconds: float) -> void:
	for _tick: int in roundi(seconds / DT):
		if not _sim.stopped:
			_sim.car.x = _sim.car.lane_center(clampi(_sim.car.lane_of(_sim.car.x), 0, _sim.car.lanes - 1))
		_sim.step(_input)
	_collect()


## Ticks until the Snap he is in is over (the snapshot says so).
func _ticks_until_snap_ends() -> int:
	var ticks: int = 0
	_input.clear()
	while GameData.as_bool(_sim.snapshot()["snap"]) and ticks < int(10.0 / DT):
		ticks += 1
		if not _sim.stopped:
			_sim.car.x = _sim.car.lane_center(clampi(_sim.car.lane_of(_sim.car.x), 0, _sim.car.lanes - 1))
		_sim.step(_input)
	_collect()
	return ticks


# --- Rarity ------------------------------------------------------------------

func _check_rarity() -> void:
	var shares: Array = tuning.a("rarity_by_act")
	check_eq(GameData.as_array(shares[0]), [60.0, 30.0, 10.0], "GDD 9.6: shop rarity is 60, 30 and 10% in Act 1")
	check_eq(GameData.as_array(shares[2]), [45.0, 35.0, 20.0], "moving to 45, 35 and 20% by Act 3")
	var samples: int = 3000
	_sim = DriveSim.new(fresh_data())
	for act: int in [1, 2, 3]:
		# The first thing held out after a boss: its pool has every rarity.
		var counts: Array[int] = [0, 0, 0]
		var doubles: int = 0
		for sample: int in samples:
			_sim.reseed(1000 * act + sample)
			_sim.stop.begin("boss_stop", act, false)
			var offers: Array[Dictionary] = _sim.stop.offers_view()
			var rarity: int = DataValidator.RARITIES.find(GameData.as_string(data.record("items", GameData.as_string(offers[0]["id"])).get("rarity")))
			counts[rarity] += 1
			var ids: Dictionary = {}
			for offer: Dictionary in offers:
				ids[offer["id"]] = true
			if ids.size() != offers.size():
				doubles += 1
		for rarity: int in 3:
			var share: float = float(counts[rarity]) / float(samples)
			var wanted: float = GameData.as_float(GameData.as_array(shares[act - 1])[rarity]) / 100.0
			check_near(share, wanted, 0.03, "act %d: %s items are %d%% of what is offered (%s%%)" % [act, DataValidator.RARITIES[rarity], roundi(wanted * 100.0), str(snappedf(share * 100.0, 0.1))])
		check_eq(doubles, 0, "act %d: no shop offers the same item twice" % act)
	# A fuel station has nothing rare: a rare draw gives the nearest rarity it has.
	var common: int = 0
	var rare: int = 0
	for sample: int in samples:
		_sim.reseed(5000 + sample)
		_sim.stop.begin("fuel_station", 1, false)
		var rarity: String = GameData.as_string(data.record("items", GameData.as_string(_sim.stop.offers_view()[0]["id"])).get("rarity"))
		if rarity == "common":
			common += 1
		elif rarity == "rare":
			rare += 1
	check_eq(rare, 0, "a fuel station has no rare Habit or Keepsake to offer")
	check_near(float(common) / float(samples), GameData.as_float(GameData.as_array(shares[0])[0]) / 100.0, 0.03, "its common share is still Act 1's 60%% (%s%%)" % str(snappedf(100.0 * float(common) / float(samples), 0.1)))


# --- Getting there -----------------------------------------------------------

## A seed whose first fork has `stop_id` at the end of its right-hand
## branch: the one a car left alone rolls onto.
func _seed_for(stop_id: String) -> int:
	for candidate: int in range(1, 2000):
		if GameData.as_string(RunGenerator.fork(data, candidate, 1, 0)[RunState.RIGHT]["stop"]) == stop_id:
			return candidate
	fail("no seed under 2000 leads to a %s" % stop_id)
	return 1


## A Telling on its first leg, the one that ends at a `stop_id`, with nothing
## on the road.
func _to_quiet_leg(stop_id: String) -> void:
	_sim = DriveSim.new(fresh_data())
	_events = []
	_input.clear()
	_sim.begin_telling(TABLE, _seed_for(stop_id))
	var guard: int = int(60.0 / DT)
	while _sim.run.stage == RunState.Stage.APPROACH and guard > 0:
		guard -= 1
		_sim.step(_input)
	var plan: Dictionary = RunGenerator.plan(data, _sim.run.branch, _sim.run.act)
	for key: String in ["spawns", "hazards", "curves", "gusts", "zones"]:
		plan[key] = []
	for key: String in ["flock", "melons", "motorcade"]:
		plan[key] = {}
	_sim.gate.reset(3)
	_sim.begin_leg(plan)
	_sim.drain_events()


## Lights one lamp on the way: a scrape along the guardrail.
func _scrape() -> void:
	var lamps: int = _sim.faults.lamps
	var lane_x: float = _sim.car.x
	var guard: int = int(5.0 / DT)
	while _sim.faults.lamps == lamps and guard > 0:
		guard -= 1
		_sim.car.x = _sim.car.guardrail_x()
		_input.clear()
		_sim.step(_input)
	# Back in his lane, and past the hit's immunity.
	for _tick: int in int((tuning.f("hit_immunity") + 0.2) / DT):
		_sim.car.x = lane_x
		_sim.step(_input)
	_sim.gate.reset(3)
	_collect()


## Into the slip lane and to the stall in second gear: he stops.
func _into_stall() -> void:
	var stall: float = _sim.leg.length - tuning.f("leg_tail") + tuning.f("exit_slip_length")
	var lanes: int = _sim.car.lanes
	_sim.car.s = stall - 20.0
	_sim.gate.reset(2)
	_input.clear()
	var guard: int = int(10.0 / DT)
	while not _sim.stopped and guard > 0:
		guard -= 1
		_sim.car.x = _sim.car.lane_center(lanes)
		_sim.car.speed = tuning.f("exit_max_speed")
		_clock_at_stall = _sim.clock.minutes
		_sim.step(_input)
	_collect()
	check(_sim.stopped, "(he stops at the stall)")


## Through Act 1 to its boss stop: every stretch is driven to its end at once,
## with one scrape in the boss so that a lamp is lit.
func _to_boss_stop() -> void:
	_sim = DriveSim.new(fresh_data())
	_events = []
	_input.clear()
	_sim.begin_telling(TABLE, 31)
	var guard: int = 4000
	var scraped: bool = false
	while not _sim.stopped and guard > 0:
		guard -= 1
		if _sim.run.stage == RunState.Stage.BOSS and not scraped:
			scraped = true
			_scrape()
		_sim.car.x = _sim.car.lane_center(1 if _sim.car.lanes > 1 else 0)
		if _sim.leg.active and _sim.car.s < _sim.leg.length - 2.0:
			_sim.car.s = _sim.leg.length - 1.0
		_clock_at_stall = _sim.clock.minutes
		_sim.step(_input)
		_collect()
	check(_sim.stopped, "(he reaches the boss stop)")


# --- The hand ----------------------------------------------------------------

## A TAP at an anchor: the pointer goes there, the hand follows, one short press.
func _tap(anchor: String) -> void:
	_input.clear()
	_input.pointer_is_absolute = true
	_input.pointer = _sim.hand.anchor_pointer(_sim.hand.anchor_index(StringName(anchor)))
	for _tick: int in int(1.5 / DT):
		_sim.step(_input)
	_input.lmb = true
	for _tick: int in int(0.08 / DT):
		_sim.step(_input)
	_input.lmb = false
	for _tick: int in int(0.3 / DT):
		_sim.step(_input)
	_input.clear()
	_collect()


## A DRAG_TO: pressed at one anchor, carried to another, let go there.
func _drag(from: String, to: String) -> void:
	_input.clear()
	_input.pointer_is_absolute = true
	_input.pointer = _sim.hand.anchor_pointer(_sim.hand.anchor_index(StringName(from)))
	for _tick: int in int(1.5 / DT):
		_sim.step(_input)
	_input.lmb = true
	for _tick: int in int(0.1 / DT):
		_sim.step(_input)
	_input.pointer = _sim.hand.anchor_pointer(_sim.hand.anchor_index(StringName(to)))
	for _tick: int in int(2.5 / DT):
		_sim.step(_input)
	_input.lmb = false
	for _tick: int in int(0.3 / DT):
		_sim.step(_input)
	_input.clear()
	_collect()


## Grips the wheel until he has left the stop.
func _leave() -> void:
	_input.clear()
	for _tick: int in int(0.2 / DT):
		_sim.step(_input)
	_input.pointer_is_absolute = true
	_input.pointer = _sim.space.point_to_pointer(_sim.space.grip_reference)
	_input.lmb = true
	var guard: int = int(5.0 / DT)
	while _sim.stopped and guard > 0:
		guard -= 1
		_sim.step(_input)
	_input.clear()
	_sim.step(_input)
	_collect()


# --- Looking -----------------------------------------------------------------

func _offers() -> Array[Dictionary]:
	var offers: Array[Dictionary] = _sim.snapshot()["offers"]
	return offers


func _of_kind(offers: Array[Dictionary], kind: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for offer: Dictionary in offers:
		if offer["kind"] == kind:
			out.append(offer)
	return out


func _offer_at(anchor: String) -> Dictionary:
	for offer: Dictionary in _offers():
		if offer["anchor"] == anchor:
			return offer
	return {}


func _offer_with(id: String) -> Dictionary:
	for offer: Dictionary in _offers():
		if offer["id"] == id:
			return offer
	return {}


func _collect() -> void:
	for event: Dictionary in _sim.drain_events():
		_events.append(event)


func _event(type: String) -> Dictionary:
	_collect()
	for index: int in range(_events.size() - 1, -1, -1):
		if GameData.as_string(_events[index].get("type")) == type:
			return _events[index]
	return {}


func _has_event(type: String) -> bool:
	return not _event(type).is_empty()
