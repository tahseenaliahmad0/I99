extends CabinSuite
## M6: the Keepsakes of GDD 7.5. They work on their own: what a test does
## with the hand here is only what the keepsake needs of it.


# --- T-ITEM-CHARM ------------------------------------------------------------

## T-ITEM-CHARM: Seven-eyed charm (7.5): the first scrape each leg lights no
## lamp; it hangs at the mirror; price 40.
func test_item_charm() -> void:
	var record: Dictionary = _record("charm")
	check_eq(GameData.as_string(record.get("kind")), "keepsake", "the charm is a Keepsake")
	check_eq(GameData.as_array(record.get("slots")), ["mirror"], "it hangs at the mirror")
	check_near(GameData.as_float(record.get("price")), 40.0, 0.000001, "price 40")
	check_eq(GameData.as_array(record.get("rituals")), [], "it works on its own")

	# Without it a scrape lights a lamp.
	_new_sim()
	_cruise(3, 1)
	var hit: Dictionary = _scrape_rail()
	check_eq(GameData.as_int(hit.get("kind")), Collision.Hit.SCRAPE, "(the guardrail is a scrape)")
	check_eq(_sim.faults.lamps, 1, "without the charm a scrape lights a lamp")

	# With it the first scrape of the leg lights none; the second does.
	_to_quiet_leg("fuel_station")
	_give("charm")
	check_eq(_anchor_of("charm"), "mirror", "the charm hangs at the mirror")
	var nerves: float = _sim.nerves.value
	hit = _scrape_rail()
	check_eq(GameData.as_int(hit.get("kind")), Collision.Hit.SCRAPE, "(a scrape)")
	check(GameData.as_bool(hit.get("spared")), "the charm turns the first scrape aside")
	check_eq(GameData.as_int(hit.get("lamps")), 0, "it lights no lamp")
	check_eq(_sim.faults.lamps, 0, "none is lit")
	check_eq(_count_events("lamp_lit"), 0, "and none is announced")
	check(_sim.nerves.value - nerves > tuning.fi("hit_nerves", 0) - 2.0, "the scrape still frays him")
	hit = _scrape_rail()
	check_eq(GameData.as_int(hit.get("lamps")), 1, "the second scrape of the leg lights its lamp")
	check_eq(_sim.faults.lamps, 1, "one lamp")

	# A leg whose only hit the charm turned aside is a clean leg.
	_to_quiet_leg("fuel_station")
	_give("charm")
	_scrape_rail()
	_into_stall()
	check(GameData.as_bool(_event("stop_entered").get("shady")), "a leg with only that scrape lit no lamp: the shady guy is at its stop")
	# The leg goes on after the stop: the charm is still spent.
	_leave_stop()
	hit = _scrape_rail()
	check_eq(GameData.as_int(hit.get("lamps")), 1, "after the stop it is the same leg: the next scrape lights a lamp")
	# The next leg: the first scrape is turned aside again.
	_into_next_quiet_leg()
	check_eq(_sim.run.legs_done, 1, "(the next leg)")
	hit = _scrape_rail()
	check_eq(GameData.as_int(hit.get("lamps")), 0, "on the next leg the first scrape lights none again")
	check_eq(_sim.faults.lamps, 1, "(the one lamp from before is all there is)")

	# A crash is not a scrape, and does not use the charm up.
	_new_sim()
	_give("charm")
	_cruise(3, 1)
	_sim.traffic.spawn(&"truck", 1, _sim.car.s + 30.0, tuning.fi("gear_speeds", 2) - 50.0)
	var guard: int = _ticks_in(10.0)
	while _sim.collision.hit == Collision.Hit.NONE and guard > 0:
		guard -= 1
		_tick()
	check_eq(_sim.collision.hit, Collision.Hit.CRASH, "(a crash)")
	check_eq(_sim.faults.lamps, int(tuning.fi("hit_lamps", 1)), "a crash lights its lamps, charm or no charm")
	_sim.traffic.clear()
	_ticks(_ticks_in(tuning.f("hit_immunity") + 0.2))
	_cruise(3, 1)
	hit = _scrape_rail()
	check_eq(GameData.as_int(hit.get("lamps")), 0, "and the charm still has its scrape")


# --- T-ITEM-AIR-FRESHENER ----------------------------------------------------

## T-ITEM-AIR-FRESHENER: Air freshener (7.5): Haze clears twice as fast; it
## hangs at the mirror; price 25.
func test_item_air_freshener() -> void:
	var record: Dictionary = _record("air_freshener")
	var clear: float = tuning.f("haze_clear_rate")
	check_eq(GameData.as_string(record.get("kind")), "keepsake", "the air freshener is a Keepsake")
	check_eq(GameData.as_array(record.get("slots")), ["mirror"], "it hangs at the mirror")
	check_near(GameData.as_float(record.get("price")), 25.0, 0.000001, "price 25")
	check_near(_passive("air_freshener", "haze_clear_mult"), 2.0, 0.000001, "Haze clears twice as fast")

	_new_sim()
	_sim.items.haze = 0.5
	_run(2.0)
	check_near(0.5 - _sim.items.haze, clear * 2.0, 0.000001, "(without it Haze clears at haze_clear_rate)")
	_give("air_freshener")
	check_eq(_anchor_of("air_freshener"), "mirror", "the air freshener hangs at the mirror")
	_sim.items.haze = 0.5
	_run(2.0)
	check_near(0.5 - _sim.items.haze, clear * 2.0 * 2.0, 0.000001, "with it Haze clears twice as fast")
	_sim.items.flags[&"window_open"] = true
	_sim.items.haze = 0.5
	_run(1.0)
	check_near(0.5 - _sim.items.haze, clear * 2.0 * tuning.f("window_haze_clear_mult"), 0.000001, "and twice as fast as an open window alone")
	_sim.items.flags[&"window_open"] = false
	_sim.items.remove_item(_item("air_freshener"))
	_sim.items.haze = 0.5
	_run(2.0)
	check_near(0.5 - _sim.items.haze, clear * 2.0, 0.000001, "taken down, it no longer does")


# --- T-ITEM-THERMOS ----------------------------------------------------------

## T-ITEM-THERMOS: Thermos (7.5): on the seat; Far reach and HOLD 1.0 s
## refills the tea, hot, on the road; 4 refills; price 30.
func test_item_thermos() -> void:
	var record: Dictionary = _record("thermos")
	var pour: Dictionary = _ritual("thermos_pour")
	var hold_s: float = GameData.as_float(pour.get("hold_s"))
	var uses: int = GameData.as_int(_supply_spec("thermos").get("uses"))
	var sip_s: float = GameData.as_float(_ritual("tea_sip").get("hold_s"))
	var tea_uses: int = GameData.as_int(_supply_spec("tea_glass").get("uses"))
	var hot_for: float = GameData.as_float(_params("tea_glass").get("hot_for_s"))

	check_eq(GameData.as_string(record.get("kind")), "keepsake", "the Thermos is a Keepsake")
	check_eq(GameData.as_array(record.get("slots")), ["seat"], "on the seat")
	check_eq(GameData.as_string(data.record("slots", "seat").get("reach")), "far", "a Far reach")
	check_eq(GameData.as_string(pour.get("gesture")), "HOLD", "poured with a HOLD")
	check_near(hold_s, 1.0, 0.000001, "of 1.0 s")
	check_eq(uses, 4, "4 refills")
	check_near(GameData.as_float(record.get("price")), 30.0, 0.000001, "price 30")

	# The glass emptied and gone cold on the road; a pour refills it, hot.
	_new_sim()
	var thermos: ItemSim.Item = _give("thermos")
	var glass: ItemSim.Item = _item("tea_glass")
	check_eq(_anchor_of("thermos"), "seat", "the Thermos lies on the seat")
	_reach("cup_a")
	for _sip: int in tea_uses:
		_hold(sip_s)
	_run(hot_for)
	check(glass.supply == 0 and glass.hot_left == 0.0, "(the glass is empty and whatever was in it cold)")
	_grip()
	_release()
	var from_tick: int = _sim.tick
	check(_reach("seat"), "the hand reaches the seat")
	check_near(float(_sim.tick - from_tick) * DT, GameData.as_float(data.record("anchors", "seat").get("time_s")), 0.03, "a Far reach: 0.6 s from the wheel")
	_press(_ticks_in(hold_s))
	check(glass.supply == 0 and thermos.supply == uses, "a hold one tick short of 1.0 s pours nothing")
	_hold(hold_s)
	check_eq(glass.supply, tea_uses, "holding for 1.0 s refills the tea")
	check_near(glass.hot_left, hot_for - float(SETTLE + 1) * DT, 0.000001, "hot")
	check_eq(thermos.supply, uses - 1, "one refill gone")
	check(not _sim.stopped and not _sim.run.active, "(on the road: no stop was needed)")
	_sim.nerves.set_value(60.0)
	_hold_at("cup_a", sip_s)
	check_near(_sim.nerves.value, 60.0 + _give_amount("tea_glass", "nerves", "hot"), 0.000001, "and the sip that follows is a hot one")

	# 4 refills.
	for _refill: int in uses - 1:
		_hold_at("seat", hold_s)
	check_eq(thermos.supply, 0, "4 refills empty the Thermos")
	_reach("cup_a")
	for _sip: int in tea_uses:
		_hold(sip_s)
	check_eq(glass.supply, 0, "(the glass is empty again)")
	_hold_at("seat", hold_s)
	check_eq(glass.supply, 0, "an empty Thermos refills nothing")

	# It is not restocked on the road.
	_to_quiet_leg("fuel_station")
	_scrape()
	_give("thermos")
	_hold_at("seat", hold_s)
	_into_stall()
	check_eq(_item("thermos").supply, uses - 1, "(a refill used)")
	check(_offer(StopSim.RESTOCK, "thermos").is_empty(), "the fuel station does not refill the Thermos: 4 refills are what it holds")


# --- T-ITEM-DUCT-TAPE --------------------------------------------------------

## T-ITEM-DUCT-TAPE: Duct tape (7.5): the first fault each act repairs
## itself after 10 s; price 35.
func test_item_duct_tape() -> void:
	var record: Dictionary = _record("duct_tape")
	var after: float = _passive("duct_tape", "self_repair_s")
	check_eq(GameData.as_string(record.get("kind")), "keepsake", "duct tape is a Keepsake")
	check_eq(GameData.as_array(record.get("slots")), ["dash_1", "dash_2"], "kept on the dash")
	check_near(after, 10.0, 0.000001, "a fault repairs itself after 10 s")
	check_near(GameData.as_float(record.get("price")), 35.0, 0.000001, "price 35")

	# Without it a fault stays.
	_new_sim()
	_cruise(3, 1)
	_scrape_rail()
	_run(after * 2.0)
	check_eq(_sim.faults.lamps, 1, "without the tape a lit lamp stays lit")

	# The first fault of the act repairs itself after 10 s.
	_to_quiet_leg("fuel_station")
	_give("duct_tape")
	var hit: Dictionary = _scrape_rail()
	var lit_tick: int = _sim.tick - _ticks_in(tuning.f("hit_immunity") + 0.2)
	check_eq(_sim.faults.lamps, 1, "(a scrape: one lamp)")
	var fault: StringName = _sim.faults.active[0]
	check_eq(GameData.as_int(hit.get("lamps")), 1, "(lit)")
	_ticks(lit_tick + _ticks_in(after) - _sim.tick - 2)
	check(_sim.faults.has(fault), "just short of 10 s the fault is still there")
	_events = []
	_ticks(4)
	check(not _sim.faults.has(fault), "after 10 s it has repaired itself")
	check_eq(_sim.faults.lamps, 0, "and its lamp is out")
	var mended: Dictionary = _event("fault_repaired")
	check_eq(GameData.as_string(mended.get("fault")), String(fault), "(announced)")
	check_near(GameData.as_float(mended.get("price")), 0.0, 0.000001, "for nothing")

	# Only the first fault of the act.
	_scrape_rail()
	check_eq(_sim.faults.lamps, 1, "(another scrape: a lamp)")
	_run(after * 2.0)
	check_eq(_sim.faults.lamps, 1, "the second fault of the act stays")

	# The next act: the first fault repairs itself again.
	_drive_on_to_act(2)
	var lamps: int = _sim.faults.lamps
	_into_next_quiet_leg()
	_scrape_rail()
	check_eq(_sim.faults.lamps, lamps + 1, "(a scrape in Act 2)")
	_run(after + 0.5)
	check_eq(_sim.faults.lamps, lamps, "in the next act the first fault repairs itself again")
	# And it is spent for that act, also after a stop.
	_into_stall()
	_leave_stop()
	_scrape_rail()
	check_eq(_sim.faults.lamps, lamps + 1, "(a scrape after the stop)")
	_run(after + 0.5)
	check_eq(_sim.faults.lamps, lamps + 1, "the act's second fault stays, stop or no stop")

	# Two lamps at once: the first of them.
	_new_sim()
	_give("duct_tape")
	_cruise(3, 1)
	_sim.traffic.spawn(&"truck", 1, _sim.car.s + 30.0, tuning.fi("gear_speeds", 2) - 50.0)
	var guard: int = _ticks_in(10.0)
	while _sim.collision.hit == Collision.Hit.NONE and guard > 0:
		guard -= 1
		_tick()
	check_eq(_sim.faults.lamps, 2, "(a crash: two lamps)")
	var first: StringName = _sim.faults.active[0]
	var second: StringName = _sim.faults.active[1]
	_sim.traffic.clear()
	_run(after + 0.5)
	check(not _sim.faults.has(first) and _sim.faults.has(second), "of two faults lit at once the first repairs itself, the other stays")

	# Reaching a stop before the 10 s are up: the tape has held.
	_to_quiet_leg("fuel_station")
	_give("duct_tape")
	_scrape_rail()
	check_eq(_sim.faults.lamps, 1, "(a scrape just before the Exit)")
	_into_stall()
	check_eq(_sim.faults.lamps, 0, "a fault the tape is holding is repaired by the time he stands at a stop")
	check(not GameData.as_bool(_event("stop_entered").get("shady")), "(the leg was not a clean one all the same)")


# --- T-ITEM-LUCKY-NOTE -------------------------------------------------------

## T-ITEM-LUCKY-NOTE: Lucky note (7.5): +1 cash per close call; price 35.
func test_item_lucky_note() -> void:
	var record: Dictionary = _record("lucky_note")
	var bonus: float = _passive("lucky_note", "close_call_bonus")
	check_eq(GameData.as_string(record.get("kind")), "keepsake", "the lucky note is a Keepsake")
	check_eq(GameData.as_array(record.get("slots")), ["dash_1", "dash_2"], "kept on the dash")
	check_near(bonus, 1.0, 0.000001, "+1 cash per close call")
	check_near(GameData.as_float(record.get("price")), 35.0, 0.000001, "price 35")

	var base: float = tuning.f("close_call_base_cash") * tuning.fi("gear_cash_mult", 2)
	_new_sim()
	var cash: float = _sim.cash
	_pass_closely("truck", tuning.f("close_call_min_closing") + 10.0)
	check_near(_sim.cash - cash, base, 0.000001, "(without it a close call in third gear pays its 2)")
	_give("lucky_note")
	_run(tuning.f("chain_window") + 0.5)
	cash = _sim.cash
	_pass_closely("truck", tuning.f("close_call_min_closing") + 10.0)
	check_near(_sim.cash - cash, base + bonus, 0.000001, "with it, 1 more")
	check_near(GameData.as_float(_event("close_call").get("cash")), base + bonus, 0.000001, "(as the event says)")
	# Per close call, flat: the next one within the chain window pays the chain on the base, and 1.
	cash = _sim.cash
	_pass_closely("truck", tuning.f("close_call_min_closing") + 10.0)
	var chain: float = GameData.as_float(_event("close_call").get("mult"))
	check(chain > 1.0, "(a chained close call)")
	check_near(_sim.cash - cash, base * chain + bonus, 0.000001, "the chain multiplies the close call, not the note's 1")
	# In first gear a close call pays nothing but the note.
	_run(tuning.f("chain_window") + 0.5)
	cash = _sim.cash
	_sim.gate.reset(1)
	_sim.car.reset(1, 1)
	_keep_lane = false
	var slow: TrafficSim.Vehicle = _sim.traffic.spawn(&"tuk_tuk", 0, _sim.car.s + 6.0, 0.0)
	var beside: float = slow.x + slow.half_width + _sim.car.half_width() + tuning.f("close_call_gap") * 0.5
	_events = []
	var guard: int = _ticks_in(20.0)
	while _sim.car.s < slow.s + 10.0 and guard > 0:
		guard -= 1
		_sim.car.x = beside
		_tick()
	_keep_lane = true
	check_eq(_count_events("close_call"), 1, "(a close call in first gear)")
	check_near(_sim.cash - cash, bonus, 0.000001, "pays the note's 1 and nothing else")
	_sim.items.remove_item(_item("lucky_note"))
	_sim.traffic.clear()
	_run(tuning.f("chain_window") + 0.5)
	cash = _sim.cash
	_pass_closely("truck", tuning.f("close_call_min_closing") + 10.0)
	check_near(_sim.cash - cash, base, 0.000001, "without the note again: just the 2")


# --- T-ITEM-SUNGLASSES -------------------------------------------------------

## T-ITEM-SUNGLASSES: Cracked sunglasses (7.5): Glare -70%; night legs 15%
## darker; price 25.
func test_item_sunglasses() -> void:
	var record: Dictionary = _record("sunglasses")
	var glare_left: float = _passive("sunglasses", "glare_mult")
	var darker: float = _passive("sunglasses", "night_darker")
	check_eq(GameData.as_string(record.get("kind")), "keepsake", "the sunglasses are a Keepsake")
	check_eq(GameData.as_array(record.get("slots")), ["dash_1", "dash_2"], "kept on the dash")
	check_near(glare_left, 0.3, 0.000001, "Glare -70%")
	check_near(darker, 0.15, 0.000001, "night legs 15% darker")
	check_near(GameData.as_float(record.get("price")), 25.0, 0.000001, "price 25")

	# Glare: the motorcade's spotlight.
	var spot: float = GameData.as_float(GameData.as_dict(data.record("legs", "motorcade").get("special")).get("glare"))
	_begin_quiet_leg("motorcade", 3, 71)
	var guard: int = _ticks_in(120.0)
	while _sim.encounter.glare <= 0.0 and guard > 0:
		guard -= 1
		_tick()
	check_near(_sim.glare(), spot, 0.000001, "(inside the motorcade's keep-back distance: the spotlight, Glare 80%)")
	check_near(GameData.as_float(_sim.snapshot()["glare"]), spot, 0.000001, "(in the snapshot)")
	_give("sunglasses")
	_tick()
	check_near(_sim.glare(), spot * glare_left, 0.000001, "with the sunglasses the Glare is 70% less")
	check_near(GameData.as_float(_sim.snapshot()["glare"]), spot * glare_left, 0.000001, "which is what the view is given")

	# Night legs 15% darker: he sees 15% less far.
	_begin_quiet_leg("night", 2, 71)
	_run(0.5)
	var cone: float = _sim.visibility()
	check_near(cone, tuning.f("low_beam_cone"), 0.000001, "(at night he sees as far as the low beam: 60 m)")
	check_near(GameData.as_float(_sim.snapshot()["night_darker"]), 0.0, 0.000001, "(and the night is as dark as it is)")
	_give("sunglasses")
	check_near(_sim.visibility(), cone * (1.0 - darker), 0.000001, "with the sunglasses the night is 15% darker: he sees 15% less far")
	check_near(GameData.as_float(_sim.snapshot()["visibility"]), cone * (1.0 - darker), 0.000001, "(the snapshot's visibility)")
	check_near(GameData.as_float(_sim.snapshot()["night_darker"]), darker, 0.000001, "(and its darkness, for the picture)")
	_sim.items.flags[&"high_beam"] = true
	check_near(_sim.visibility(), tuning.f("high_beam_cone") * (1.0 - darker), 0.000001, "on high beam too")

	# By day they darken nothing.
	_begin_quiet_leg("open_road", 1, 5)
	var day: float = _sim.visibility()
	_give("sunglasses")
	check_eq(_sim.visibility(), day, "by day he sees as far as ever")
	check_near(GameData.as_float(_sim.snapshot()["night_darker"]), 0.0, 0.000001, "and nothing is darker")


# --- T-ITEM-TAXI-SIGN --------------------------------------------------------

## T-ITEM-TAXI-SIGN: Taxi sign (7.5): on the roof; calls pay 5 more and come
## twice as often; price 40.
func test_item_taxi_sign() -> void:
	var record: Dictionary = _record("taxi_sign")
	var more: float = _passive("taxi_sign", "call_cash_bonus")
	var gap_mult: float = _passive("taxi_sign", "call_gap_mult")
	var params: Dictionary = _params("phone")
	var gap: Array = GameData.as_array(params.get("call_gap_s"))
	var pay: float = GameData.as_float(params.get("dispatcher_cash"))
	var taps: int = GameData.as_int(params.get("answer_taps"))
	var every: int = GameData.as_int(params.get("family_every"))
	var synergy: Dictionary = GameData.as_dict(GameData.as_array(_record("phone").get("synergies"))[0])
	var row_every: int = GameData.as_int(synergy.get("every"))
	var row_bonus: float = GameData.as_float(synergy.get("amount"))
	check_eq(GameData.as_string(record.get("kind")), "keepsake", "the taxi sign is a Keepsake")
	check_eq(GameData.as_array(record.get("slots")), ["roof"], "on the roof")
	check_eq(GameData.as_string(data.record("slots", "roof").get("reach")), "none", "where the hand does not reach")
	check_near(more, 5.0, 0.000001, "calls pay 5 more")
	check_near(gap_mult, 0.5, 0.000001, "and come twice as often")
	check_near(GameData.as_float(record.get("price")), 40.0, 0.000001, "price 40")

	# On the roof.
	_new_sim()
	var sign: ItemSim.Item = _give("taxi_sign")
	check_eq(sign.slot, &"roof", "the sign goes on the roof")
	check_eq(_sim.items.anchor_of(sign), "", "there is nothing there for the hand")
	# Without a phone there are no calls for it to change.
	_run(GameData.as_float(gap[1]) * 1.5)
	check_eq(_count_events("call_started"), 0, "without a phone the sign brings no calls")

	# With a phone: twice as often, 5 more.
	_give("phone")
	var mount: String = _anchor_of("phone")
	_reach(mount)
	var since: int = _sim.tick
	var shortest: float = INF
	var longest: float = 0.0
	for call: int in every:
		var rang: bool = false
		var guard: int = _ticks_in(GameData.as_float(gap[1]) + 5.0)
		while _sim.items.caller == &"" and guard > 0:
			guard -= 1
			_tick()
			rang = _sim.items.caller != &""
		if not check(rang, "(call %d)" % (call + 1)):
			break
		var waited: float = float(_sim.tick - since) * DT
		shortest = minf(shortest, waited)
		longest = maxf(longest, waited)
		var cash: float = _sim.cash
		for _index: int in taps:
			_tap()
		if (call + 1) % every == 0:
			check_near(_sim.cash, cash, 0.000001, "Um Noor's call pays nothing, sign or no sign")
		else:
			# (Phone + Taxi sign: every third call answered in a row pays a bonus too.)
			var in_a_row: float = row_bonus if (call + 1) % row_every == 0 else 0.0
			check_near(_sim.cash - cash - in_a_row, pay + more, 0.000001, "the dispatcher's call %d pays 15" % (call + 1))
		since = _sim.tick
	check(shortest >= GameData.as_float(gap[0]) * gap_mult - DT and longest <= GameData.as_float(gap[1]) * gap_mult + DT,
			"calls come 12.5 to 20 s apart: twice as often (%s to %s s)" % [str(snappedf(shortest, 0.01)), str(snappedf(longest, 0.01))])


# --- Helpers -----------------------------------------------------------------

## The amount an item's entries give a standing change.
func _passive(item_id: String, key: String) -> float:
	for list: String in ["gives", "takes"]:
		for listed: Variant in GameData.as_array(_record(item_id).get(list)):
			var entry: Dictionary = GameData.as_dict(listed)
			if GameData.as_string(entry.get("passive")) == key:
				return GameData.as_float(entry.get("amount"))
	return 0.0
