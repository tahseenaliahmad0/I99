extends CabinSuite
## M6: the Deals of GDD 7.7: what the shady guy sells. (The arak flask, the
## fifth Deal, is a Habit and has its test with the Habits.)


# --- T-ITEM-FORGED-PAPERS ----------------------------------------------------

## T-ITEM-FORGED-PAPERS: Forged papers (7.7): passes the next checkpoint's
## Papers phase automatically; 60 cash; contraband until used.
func test_item_forged_papers() -> void:
	var record: Dictionary = _record("forged_papers")
	_check_deal("forged_papers", 60.0)
	check(GameData.as_bool(record.get("contraband")), "forged papers are contraband")
	check_eq(GameData.as_string(_params("forged_papers").get("passes")), "papers", "they pass the Papers phase")
	check(GameData.as_array(record.get("slots")).has("glovebox_a") and GameData.as_array(record.get("slots")).has("dash_1"), "kept on the dash or stowed in the glovebox")

	# They pass the next Papers phase, once.
	_new_sim()
	check(not _sim.use_forged_papers(), "(without them nothing passes the Papers phase for him)")
	_give("forged_papers")
	check(_item("forged_papers") != null, "(he has them)")
	check(_sim.use_forged_papers(), "with forged papers the Papers phase is passed for him")
	check(_item("forged_papers") == null, "and they are used up")
	check(not _sim.use_forged_papers(), "the checkpoint after that he is on his own again")

	# Contraband until used: on the dash the officer who fines him takes them.
	_pulled_over_with("forged_papers", "dash_2")
	var cash: float = _sim.cash
	_drag("dash_1", "driver_window")
	check(not _sim.pulled_over, "(he hands over his licence and drives on)")
	check(_sim.cash < cash, "(fined)")
	check(_item("forged_papers") == null, "forged papers lying on the dash are taken with the fine")
	check(GameData.as_array(_event("pulled_over").get("taken")).has("forged_papers"), "(as the officer's event says)")
	# Stowed in the glovebox they are not seen.
	_pulled_over_with("forged_papers", "glovebox_a")
	_drag("dash_1", "driver_window")
	check(not _sim.pulled_over, "(the same fine)")
	check(_item("forged_papers") != null, "stowed in the glovebox they are not found")
	# Used, there is nothing left to take.
	_pulled_over_with("forged_papers", "dash_2")
	_sim.use_forged_papers()
	_drag("dash_1", "driver_window")
	check(GameData.as_array(_event("pulled_over").get("taken")).is_empty(), "once used they are no contraband: there is nothing to take")

	# 60 cash, from the shady guy.
	_buy_from_the_shady_guy("forged_papers", 60.0, "dash_2")


# --- T-ITEM-TINTED-GLASS -----------------------------------------------------

## T-ITEM-TINTED-GLASS: Tinted glass (7.7): Suspicion gains halved; lamp
## capacity -1; night legs 20% darker.
func test_item_tinted_glass() -> void:
	_check_deal("tinted_glass", 0.0)
	check_near(_passive("tinted_glass", "suspicion_gain_mult"), 0.5, 0.000001, "Suspicion gains halved")
	check_near(_passive("tinted_glass", "lamp_capacity"), -1.0, 0.000001, "lamp capacity -1")
	check_near(_passive("tinted_glass", "night_darker"), 0.2, 0.000001, "night legs 20% darker")
	check_eq(GameData.as_array(_record("tinted_glass").get("slots")), [], "it is the car's own: it takes no slot")

	# Suspicion gains halved: a honk, a wrong gear, a lane line.
	var plain: Dictionary = _offences(false)
	var tinted: Dictionary = _offences(true)
	check_near(GameData.as_float(plain["honk"]), tuning.f("suspicion_honk"), 0.2, "(a honk in view of a patrol is +15)")
	check_near(GameData.as_float(tinted["honk"]), tuning.f("suspicion_honk") * 0.5, 0.2, "behind tinted glass it is half that")
	check_near(GameData.as_float(plain["gear"]), tuning.f("suspicion_gear_rate"), 0.2, "(fourth gear is +15 a second)")
	check_near(GameData.as_float(tinted["gear"]), tuning.f("suspicion_gear_rate") * 0.5, 0.2, "half that")
	check_near(GameData.as_float(plain["decay"]), -tuning.f("suspicion_decay"), 0.2, "(driving clean wears it off at 5 a second)")
	check_near(GameData.as_float(tinted["decay"]), -tuning.f("suspicion_decay"), 0.2, "which the glass does not slow")

	# Lamp capacity -1.
	var capacity: int = tuning.i("lamp_capacity")
	_new_sim()
	_give("tinted_glass")
	check_eq(_sim.faults.capacity, capacity - 1, "the car has room for one lamp fewer")
	_cruise(3, 1)
	for _hit: int in capacity - 2:
		_scrape_rail()
	check(not _sim.wrecked, "(three lamps are not a Wreck)")
	_scrape_rail()
	check(_sim.wrecked, "the fourth lamp is the Wreck")

	# Night legs 20% darker.
	_begin_quiet_leg("night", 2, 71)
	_run(0.5)
	var cone: float = _sim.visibility()
	_give("tinted_glass")
	check_near(_sim.visibility(), cone * 0.8, 0.000001, "at night he sees 20% less far")
	check_near(GameData.as_float(_sim.snapshot()["night_darker"]), 0.2, 0.000001, "(the snapshot's darkness)")
	_give("sunglasses")
	check_near(_sim.visibility(), cone * (1.0 - 0.2 - _passive("sunglasses", "night_darker")), 0.000001, "with the sunglasses on top: 35% in all")
	_begin_quiet_leg("open_road", 1, 5)
	var day: float = _sim.visibility()
	_give("tinted_glass")
	check_eq(_sim.visibility(), day, "by day it darkens nothing")

	_buy_from_the_shady_guy("tinted_glass", 0.0, "")


# --- T-ITEM-TURBO ------------------------------------------------------------

## T-ITEM-TURBO: Turbo (7.7): gears 4 and 5 gain 15 km/h and close-call cash
## is x1.5; lamp capacity -1; braking 30% weaker.
func test_item_turbo() -> void:
	_check_deal("turbo", 0.0)
	check_near(_passive("turbo", "high_gear_bonus"), 15.0, 0.000001, "gears 4 and 5 gain 15 km/h")
	check_near(_passive("turbo", "close_call_mult"), 1.5, 0.000001, "close-call cash x1.5")
	check_near(_passive("turbo", "lamp_capacity"), -1.0, 0.000001, "lamp capacity -1")
	check_near(_passive("turbo", "brake_mult"), 0.7, 0.000001, "braking 30% weaker")

	# Gears 4 and 5 gain 15 km/h; the others do not.
	_new_sim()
	_give("turbo")
	_give("fifth_gear")
	for gear: int in [1, 2, 3, 4, 5]:
		_cruise(gear, 1)
		_run(3.0)
		var plain: float = tuning.fi("gear_speeds", gear - 1)
		check_near(_sim.car.speed, plain + (15.0 if gear >= 4 else 0.0), 0.000001, "gear %d cruises at %d km/h" % [gear, roundi(plain + (15.0 if gear >= 4 else 0.0))])

	# Close-call cash x1.5.
	var base: float = tuning.f("close_call_base_cash") * tuning.fi("gear_cash_mult", 2)
	_new_sim()
	_pass_closely("truck", tuning.f("close_call_min_closing") + 10.0)
	check_near(GameData.as_float(_event("close_call").get("cash")), base, 0.000001, "(a close call in third gear pays 2)")
	_give("turbo")
	_run(tuning.f("chain_window") + 0.5)
	_pass_closely("truck", tuning.f("close_call_min_closing") + 10.0)
	check_near(GameData.as_float(_event("close_call").get("cash")), base * 1.5, 0.000001, "with the turbo, 3")

	# Lamp capacity -1.
	var capacity: int = tuning.i("lamp_capacity")
	check_eq(_sim.faults.capacity, capacity - 1, "the car has room for one lamp fewer")
	_give("tinted_glass")
	check_eq(_sim.faults.capacity, capacity - 2, "(and with tinted glass too, two fewer)")
	_give("bull_bar")
	check_eq(_sim.faults.capacity, capacity - 1, "(a bull bar gives one back)")

	# Braking 30% weaker.
	_new_sim()
	var plain_loss: float = _speed_lost_braking()
	check_near(plain_loss, tuning.f("brake_decel"), 0.000001, "(the brake sheds 30 km/h in a second)")
	_new_sim()
	_give("turbo")
	check_near(_speed_lost_braking(), plain_loss * 0.7, 0.000001, "with the turbo, 30% less")

	_buy_from_the_shady_guy("turbo", 0.0, "")


# --- T-ITEM-GOOD-STUFF -------------------------------------------------------

## T-ITEM-GOOD-STUFF: The good stuff (7.7): the Courage cap rises to 5; 30
## cash; 40 ms of permanent Lag.
func test_item_good_stuff() -> void:
	_check_deal("good_stuff", 30.0)
	var cap: int = GameData.as_int(data.record("effects", "courage").get("max_stacks"))
	check_eq(cap + roundi(_passive("good_stuff", "courage_cap_more")), 5, "the Courage cap rises to 5")
	check_near(_passive("good_stuff", "lag_sources") * tuning.f("lag_per_source"), 40.0, 0.000001, "40 ms of permanent Lag")
	var sip_s: float = GameData.as_float(_ritual("flask_sip").get("hold_s"))
	var lag: float = tuning.f("lag_per_source") * 0.001

	# 40 ms of permanent Lag: sober, at once, for as long as he has it.
	_new_sim()
	_tick()
	check_near(_sim.wheel.lag, 0.0, 0.000001, "(without it, sober, there is no Lag)")
	_give("good_stuff")
	_tick()
	check_near(_sim.wheel.lag, lag, 0.000001, "with the good stuff the steering lags 40 ms, sober")
	_run(120.0)
	check_near(_sim.wheel.lag, lag, 0.000001, "and goes on lagging: it is permanent")
	# The car is steered by the wheel's angle of 40 ms ago.
	_cruise(3, 1)
	_grip()
	_ticks(_ticks_in(0.5))
	_input.pointer_is_absolute = false
	_input.pointer_delta = Vector2(3.0, 0.0)
	var angles: PackedFloat64Array = PackedFloat64Array()
	var worst: float = 0.0
	var behind: float = lag / DT
	var whole: int = int(floorf(behind))
	for index: int in 40:
		_tick()
		angles.append(_sim.wheel.angle)
		if index > whole + 1:
			worst = maxf(worst, absf(_sim.wheel.steer() * _sim.wheel.max_angle() - lerpf(angles[index - whole], angles[index - whole - 1], behind - float(whole))))
	check_near(worst, 0.0, 0.000000001, "the car answers the wheel's angle of 40 ms ago")
	_release()

	# The Courage cap rises to 5.
	_new_sim()
	_give("arak_flask")
	var cup: String = _anchor_of("arak_flask")
	_reach(cup)
	for _sip: int in 5:
		_hold(sip_s)
	check_eq(_sim.courage(), cap, "(without it five sips are 3 stacks)")
	_new_sim()
	_give("arak_flask")
	_give("good_stuff")
	_reach(cup)
	for sip: int in 5:
		_hold(sip_s)
		check_eq(_sim.courage(), sip + 1, "with the good stuff sip %d is stack %d" % [sip + 1, sip + 1])
	_hold(sip_s)
	check_eq(_sim.courage(), 5, "a sixth sip: still 5 stacks")
	# What five stacks do.
	_tick()
	check_near(_sim.wheel.lag, tuning.f("lag_cap") * 0.001, 0.000001, "five stacks and the good stuff would be 240 ms of Lag: it stops at the cap, 200 ms")
	_sim.nerves.set_value(30.0)
	_tap_at("face")
	check_near(_sim.nerves.value, 30.0, 0.000001, "at five stacks nothing frays him: a slap adds nothing")
	_run(tuning.f("chain_window") + 0.5)
	_pass_closely("truck", tuning.f("close_call_min_closing") + 10.0)
	check_eq(_sim.courage(), 5, "(still five)")
	var cash_up: float = GameData.as_float(data.record("effects", "courage").get("close_call_cash_per_stack"))
	check_near(GameData.as_float(_event("close_call").get("cash")), tuning.f("close_call_base_cash") * tuning.fi("gear_cash_mult", 2) * (1.0 + cash_up * 5.0), 0.000001, "and a close call pays three and a half times")

	_buy_from_the_shady_guy("good_stuff", 30.0, "")


# --- Helpers -----------------------------------------------------------------

## What every Deal is: the shady guy's, at its price.
func _check_deal(item_id: String, price: float) -> void:
	var record: Dictionary = _record(item_id)
	check_eq(GameData.as_string(record.get("kind")), "deal", "%s is a Deal" % item_id)
	check_near(GameData.as_float(record.get("price")), price, 0.000001, "for %d cash" % roundi(price))
	for stop: Dictionary in data.records("stops"):
		var pools: Array = GameData.as_array(GameData.as_dict(stop.get("stock")).get("pools"))
		if GameData.as_string(stop.get("id")) != "shady_guy":
			check(not pools.has("deal"), "(%s sells no Deal)" % GameData.as_string(stop.get("id")))


## The amount an item's entries give a standing change.
func _passive(item_id: String, key: String) -> float:
	for list: String in ["gives", "takes"]:
		for listed: Variant in GameData.as_array(_record(item_id).get(list)):
			var entry: Dictionary = GameData.as_dict(listed)
			if GameData.as_string(entry.get("passive")) == key:
				return GameData.as_float(entry.get("amount"))
	return 0.0


## A quiet Patrol leg in which he has just been pulled over, with an item in
## a slot of the cabin.
func _pulled_over_with(item_id: String, slot: String) -> void:
	_begin_quiet_leg("patrol", 2, 71)
	_give(item_id, slot)
	var guard: int = _ticks_in(60.0)
	while not _sim.suspicion.watching and guard > 0:
		guard -= 1
		_tick()
	_sim.suspicion.add(_sim.suspicion.maximum())
	guard = _ticks_in(30.0)
	while not _sim.pulled_over and guard > 0:
		guard -= 1
		_tick()
	_ticks(_ticks_in(0.5))
	_events = []
	check(_sim.pulled_over, "(he is pulled over)")


## A quiet Patrol leg with the patrol watching: what a honk adds, what a
## second in fourth gear adds, and what a clean second takes off.
func _offences(tinted: bool) -> Dictionary:
	_begin_quiet_leg("patrol", 2, 71)
	if tinted:
		_give("tinted_glass")
	var guard: int = _ticks_in(60.0)
	while not _sim.suspicion.watching and guard > 0:
		guard -= 1
		_tick()
	_run(2.0)
	_reach("horn")
	var before: float = _sim.suspicion.value
	_tap()
	var honk: float = _sim.suspicion.value - before
	_sim.suspicion.value = 50.0
	_sim.gate.reset(4)
	before = _sim.suspicion.value
	_run(1.0)
	var gear: float = _sim.suspicion.value - before
	_sim.gate.reset(3)
	_sim.car.speed = tuning.fi("gear_speeds", 2)
	_sim.suspicion.value = 50.0
	_tick()
	before = _sim.suspicion.value
	_run(1.0)
	return {"honk": honk, "gear": gear, "decay": _sim.suspicion.value - before}


## Third gear at cruise, the brake held for a second: km/h lost.
func _speed_lost_braking() -> float:
	_cruise(3, 1)
	_run(0.5)
	var from: float = _sim.car.speed
	_input.clear()
	_input.rmb = true
	_ticks(DriveSim.TICKS_PER_SECOND)
	_input.rmb = false
	return from - _sim.car.speed


## The Deal is found on the shady guy's tray after a clean first leg, bought
## for its price and, if it goes in a slot, put there.
func _buy_from_the_shady_guy(item_id: String, price: float, slot_anchor: String) -> void:
	var bought: bool = false
	for skip: int in 16:
		_to_quiet_leg("fuel_station", skip)
		_into_stall()
		var deal: Dictionary = _offer(StopSim.ITEM, item_id)
		if deal.is_empty():
			continue
		check(GameData.as_bool(deal["shady"]), "%s is the shady guy's to sell" % item_id)
		check_near(GameData.as_float(deal["price"]), price, 0.000001, "for %d cash" % roundi(price))
		_sim.cash = price + 3.0
		var clock: float = _sim.clock.minutes
		_tap_at(GameData.as_string(deal["anchor"]))
		check_near(_sim.cash, 3.0, 0.000001, "a TAP buys it")
		check_near(_sim.clock.minutes - clock, GameData.as_float(tuning.d("stop_minutes").get("shady")), 0.000001, "and using him costs his 5 minutes")
		if not slot_anchor.is_empty():
			_drag(GameData.as_string(deal["anchor"]), slot_anchor)
		check(_item(item_id) != null, "it is his")
		bought = true
		break
	check(bought, "in sixteen clean first legs the shady guy has %s at least once" % item_id)
