extends CabinSuite
## M6: the Habits of GDD 7.4, each performed by the hand.


# --- T-ITEM-CIGARETTES -------------------------------------------------------

## T-ITEM-CIGARETTES: Cigarettes (7.4): HOLD 1.2 s lights one from a pack of
## 10; lit for 25 s gives no Tremor, Awake and -10 Nerves over the burn; Haze
## +2% per second while lit, clearing 3% per second after; it must be ashed
## once mid-burn (FLICK) or ash falls (+5 Nerves); Craving +8 Nerves once if
## another is not lit within 30 s; restock 15.
func test_item_cigarettes() -> void:
	var record: Dictionary = _record("cigarettes")
	var light: Dictionary = _ritual("cig_light")
	var hold_s: float = GameData.as_float(light.get("hold_s"))
	var burn: float = _give_duration("cigarettes", "lit")
	var calm: float = _give_amount("cigarettes", "nerves")
	var ash_by: float = GameData.as_float(_params("cigarettes").get("ash_by_s"))
	var ash_nerves: float = GameData.as_float(_params("cigarettes").get("ash_nerves"))
	var lapse: Dictionary = GameData.as_dict(record.get("lapse"))
	var crave_after: float = GameData.as_float(lapse.get("after"))
	var crave_nerves: float = GameData.as_float(lapse.get("amount"))
	var uses: int = GameData.as_int(_supply_spec("cigarettes").get("uses"))
	var haze_rate: float = 0.0
	for take: Variant in GameData.as_array(record.get("takes")):
		var entry: Dictionary = GameData.as_dict(take)
		if GameData.as_string(entry.get("effect")) == "haze_rate" and GameData.as_string(entry.get("while")) == "lit":
			haze_rate = GameData.as_float(entry.get("amount"))
	var clear_rate: float = tuning.f("haze_clear_rate")

	# The numbers of GDD 7.4.
	check_eq(GameData.as_string(record.get("kind")), "habit", "cigarettes are a Habit")
	check_eq(GameData.as_array(record.get("slots")), ["ashtray"], "kept at the ashtray")
	check_eq(GameData.as_string(light.get("gesture")), "HOLD", "lighting is a HOLD")
	check_near(hold_s, 1.2, 0.000001, "of 1.2 s")
	check_eq(GameData.as_string(_ritual("cig_ash").get("gesture")), "FLICK", "ashing is a FLICK")
	check_eq(uses, 10, "a pack holds 10")
	check_near(GameData.as_float(_supply_spec("cigarettes").get("restock")), 15.0, 0.000001, "restock 15")
	check_near(burn, 25.0, 0.000001, "one burns for 25 s")
	check_near(calm, -10.0, 0.000001, "and calms by 10")
	check_near(GameData.as_float(GameData.as_dict(GameData.as_array(record.get("gives"))[1]).get("over")), burn, 0.000001, "over the burn")
	check_near(haze_rate, 0.02, 0.000001, "Haze +2% per second while lit")
	check_near(clear_rate, 0.03, 0.000001, "clearing 3% per second")
	check_near(ash_nerves, 5.0, 0.000001, "fallen ash is +5 Nerves")
	check(ash_by > 0.0 and ash_by < burn, "it must be ashed mid-burn: before a moment inside the burn")
	check_near(crave_after, 30.0, 0.000001, "the Craving comes after 30 s")
	check_near(crave_nerves, 8.0, 0.000001, "and is +8 Nerves")
	check(GameData.as_bool(lapse.get("once")), "once")

	# HOLD 1.2 s lights one from a pack of 10.
	_new_sim()
	var pack: ItemSim.Item = _give("cigarettes")
	check_eq(pack.supply, uses, "a new pack is full")
	check(_reach("ashtray"), "the hand reaches the ashtray")
	_press(_ticks_in(hold_s))
	check(not _sim.effects.has(&"lit"), "a hold one tick short of 1.2 s lights nothing")
	check_eq(pack.supply, uses, "and uses nothing: releasing early cancels")
	_hold(hold_s)
	check(_sim.effects.has(&"lit"), "holding for 1.2 s lights one")
	check_eq(pack.supply, uses - 1, "from the pack")
	check_eq(_count_events("ritual_completed", "ritual", "cig_light"), 1, "the ritual is announced once")
	_hold(hold_s)
	check_eq(pack.supply, uses - 1, "he cannot light a second while one is lit")

	# Lit for 25 s: no Tremor, -10 Nerves over the burn, Haze +2% per second.
	_new_sim()
	pack = _item("cigarettes")
	_sim.nerves.set_value(70.0)
	_run(0.1)
	check(_sim.nerves.tremor_amplitude > 0.0, "(at Nerves 70 his hand shakes)")
	var nerves_0: float = _sim.nerves.value
	_hold_at("ashtray", hold_s)
	_flick(Vector2(0.0, tuning.f("flick_min_distance") * 1.5))
	check(pack.ashed, "a FLICK at the ashtray ashes it")
	_run(burn * 0.5)
	var burned: float = burn - _sim.effects.time_left(&"lit")
	check(burned > burn * 0.5 and burned < burn, "(mid-burn)")
	check_near(_sim.nerves.tremor_amplitude, 0.0, 0.000001, "lit: no Tremor, even at Nerves %d" % roundi(_sim.nerves.value))
	check_near(_sim.nerves.value, nerves_0 + calm * burned / burn, 0.01, "the calm comes evenly over the burn")
	check_near(_sim.items.haze, haze_rate * burned, 0.001, "Haze grows by 2% per second while lit")
	_run(burn - burned - 0.05)
	check(_sim.effects.has(&"lit"), "just short of 25 s it still burns")
	_run(0.1)
	check(not _sim.effects.has(&"lit"), "after 25 s it is out")
	check_near(_sim.nerves.value, nerves_0 + calm, 0.01, "having calmed him by 10 in all")
	# The calm is counted in whole ticks, like the burn: a quarter of one tick
	# of it is the tolerance, so a tick too many or too few is caught.
	check_near(_sim.nerves.value, nerves_0 + calm, absf(calm) / burn * DT * 0.25, "by 10 and not a tick of calm more: it ends with the burn")
	check(_sim.nerves.tremor_amplitude > 0.0, "and the Tremor is back")
	var haze_top: float = _sim.items.haze
	check_near(haze_top, haze_rate * burn, 0.003, "the Haze reached 2% x 25 s")
	_run(5.0)
	check_near(haze_top - _sim.items.haze, clear_rate * 5.0, 0.002, "afterwards it clears at 3% per second")

	# Lit: Awake.
	_new_sim()
	_sim.act = 2
	_sim.nerves.set_value(_sim.heavy_floor() - 5.0)
	_run(1.0)
	check(_sim.nerves.heavy and _sim.nerves.lids > 0.0, "(below the Heavy floor his lids close)")
	_hold_at("ashtray", hold_s)
	_flick(Vector2(0.0, tuning.f("flick_min_distance") * 1.5))
	_run(tuning.f("lids_close_time"))
	check(not _sim.nerves.heavy, "lit: Awake, though his Nerves are below the floor")
	check_near(_sim.nerves.lids, 0.0, 0.000001, "his lids are open")
	_run(burn)
	check(_sim.nerves.heavy, "when it is out he is Heavy again")

	# Left unashed, the ash falls: +5 Nerves, once.
	_new_sim()
	pack = _item("cigarettes")
	_hold_at("ashtray", hold_s)
	burned = burn - _sim.effects.time_left(&"lit")
	_run(ash_by - burned - 0.5)
	check(not pack.ash_fell, "before the middle of the burn nothing has fallen")
	var before: float = _sim.nerves.value
	_run(1.0)
	check(pack.ash_fell, "left unashed, the ash falls")
	check_near(_sim.nerves.value - before, ash_nerves + calm * 1.0 / burn, 0.01, "+5 Nerves")
	before = _sim.nerves.value
	_run(5.0)
	check_near(_sim.nerves.value - before, calm * 5.0 / burn, 0.01, "once")

	# Ashed in time by a FLICK: nothing falls. A slow swipe is not a FLICK.
	_new_sim()
	pack = _item("cigarettes")
	_reach("ashtray")
	_flick(Vector2(0.0, tuning.f("flick_min_distance") * 1.5))
	check(not pack.ashed and not _sim.effects.has(&"lit"), "unlit, a flick at the ashtray does nothing")
	_hold_at("ashtray", hold_s)
	_run(ash_by * 0.5)
	_flick(Vector2(0.0, tuning.f("flick_min_distance") * 1.5), _ticks_in(tuning.f("flick_max_time") * 2.0))
	check(not pack.ashed, "a swipe slower than flick_max_time does not ash it")
	_flick(Vector2(tuning.f("flick_min_distance") * 1.5, 0.0))
	check(pack.ashed, "a FLICK does (any way)")
	before = _sim.nerves.value
	burned = burn - _sim.effects.time_left(&"lit")
	_run(ash_by - burned + 1.0)
	check(not pack.ash_fell, "ashed once mid-burn, no ash falls")
	check(_sim.nerves.value < before, "and he only calms")

	# Craving: +8 once if another is not lit within 30 s.
	_run(_sim.effects.time_left(&"lit") + 0.05)
	check(not _sim.effects.has(&"lit"), "(the cigarette is out)")
	_run(crave_after - 1.0)
	before = _sim.nerves.value
	_run(1.5)
	check_near(_sim.nerves.value - before, crave_nerves, 0.000001, "30 s after it went out with none lit: the Craving, +8 Nerves")
	before = _sim.nerves.value
	_run(crave_after * 2.0)
	check_near(_sim.nerves.value - before, 0.0, 0.000001, "once")

	_new_sim()
	_hold_at("ashtray", hold_s)
	_flick(Vector2(0.0, tuning.f("flick_min_distance") * 1.5))
	_run(_sim.effects.time_left(&"lit") + 0.05)
	_run(crave_after * 0.5)
	_hold_at("ashtray", hold_s)
	_flick(Vector2(0.0, tuning.f("flick_min_distance") * 1.5))
	check(_sim.effects.has(&"lit"), "(another is lit within 30 s)")
	before = _sim.nerves.value
	_run(crave_after)
	check(_sim.nerves.value < before, "lighting another within 30 s: no Craving")

	_new_sim()
	before = _sim.nerves.value
	_run(crave_after * 2.0)
	check_near(_sim.nerves.value - before, 0.0, 0.000001, "and none before he has smoked")

	# Restock 15, at a fuel station: a pack of 10 again.
	_to_quiet_leg("fuel_station")
	_scrape()
	check_eq(_item("cigarettes").supply, _starting_supply("cigarettes"), "(he set out with part of a pack)")
	_into_stall()
	var refill: Dictionary = _offer(StopSim.RESTOCK, "cigarettes")
	if check(not refill.is_empty(), "the fuel station offers to restock the cigarettes"):
		check_near(GameData.as_float(refill["price"]), 15.0, 0.000001, "for 15")
		var cash: float = _sim.cash
		_tap_at(GameData.as_string(refill["anchor"]))
		check_near(cash - _sim.cash, 15.0, 0.000001, "a TAP pays 15")
		check_eq(_item("cigarettes").supply, uses, "for a pack of 10")
		_tap_at(GameData.as_string(refill["anchor"]))
		check_near(cash - _sim.cash, 15.0, 0.000001, "once: a full pack is not offered again")
	_leave_stop()
	_hold_at("ashtray", hold_s)
	check(_sim.effects.has(&"lit"), "on the road again he lights one")
	check_eq(_item("cigarettes").supply, uses - 1, "from the pack of 10")

	# A stop does not cancel the Craving. Burnt out before the stall: what is
	# left of its 30 s waits there with the night, and runs on down the road.
	_to_quiet_leg("fuel_station")
	_hold_at("ashtray", hold_s)
	_flick(Vector2(0.0, tuning.f("flick_min_distance") * 1.5))
	_run(_sim.effects.time_left(&"lit") + 0.05)
	_run(crave_after * 0.5)
	check(not _sim.effects.has(&"lit") and _item("cigarettes").lapse_left > 0.0, "(burnt out, and half the Craving's 30 s gone, he pulls in)")
	_into_stall()
	var owed: float = _item("cigarettes").lapse_left
	check(owed > crave_after * 0.4 and owed < crave_after * 0.5, "at the stop the rest of the 30 s is still owed (%s s)" % str(snappedf(owed, 0.01)))
	_run(crave_after)
	check_eq(_item("cigarettes").lapse_left, owed, "it waits there with the night, however long he shops")
	_leave_stop()
	# (His foot on the brake: he stands on the road, where the night goes on.)
	_input.rmb = true
	before = _sim.nerves.value
	_run(owed - 1.0)
	check_near(_sim.nerves.value - before, 0.0, 0.000001, "back on the road the wait runs on from where it stood")
	_run(1.5)
	check_near(_sim.nerves.value - before, crave_nerves, 0.000001, "and when its 30 s of road are up the Craving comes: +8 Nerves")
	_run(crave_after * 2.0)
	check_near(_sim.nerves.value - before, crave_nerves, 0.000001, "once")

	# A cigarette that the stop puts out starts its Craving there.
	_to_quiet_leg("fuel_station")
	_hold_at("ashtray", hold_s)
	_flick(Vector2(0.0, tuning.f("flick_min_distance") * 1.5))
	_run(burn * 0.4)
	check(_sim.effects.has(&"lit"), "(he pulls in with a cigarette burning)")
	_into_stall()
	check(not _sim.effects.has(&"lit"), "(the stop puts it out)")
	check_near(_item("cigarettes").lapse_left, crave_after, 0.000001, "a cigarette that a stop puts out starts its Craving there: 30 s are owed")
	_leave_stop()
	_input.rmb = true
	before = _sim.nerves.value
	_run(crave_after - 1.0)
	check_near(_sim.nerves.value - before, 0.0, 0.000001, "30 s of road after that stop")
	_run(1.5)
	check_near(_sim.nerves.value - before, crave_nerves, 0.000001, "the Craving comes: +8 Nerves")

	# Lighting another within what is left still answers it.
	_to_quiet_leg("fuel_station")
	_hold_at("ashtray", hold_s)
	_flick(Vector2(0.0, tuning.f("flick_min_distance") * 1.5))
	_run(burn * 0.4)
	_into_stall()
	_leave_stop()
	_hold_at("ashtray", hold_s)
	_flick(Vector2(0.0, tuning.f("flick_min_distance") * 1.5))
	check(_sim.effects.has(&"lit"), "(after the stop he lights another)")
	_input.rmb = true
	before = _sim.nerves.value
	_run(crave_after + 1.0)
	check(_sim.nerves.value < before, "another lit within the 30 s the stop left him: no Craving")


# --- T-ITEM-TEA-GLASS --------------------------------------------------------

## T-ITEM-TEA-GLASS: Tea glass (7.4): HOLD 0.6 s sips; 3 sips; a hot sip is
## -12 Nerves and Awake 40 s; cold after 40 s, a cold sip is -3 Nerves and no
## Awake; it spills in a crash; refill 2 cash at a fuel station, free at a
## tea stall.
func test_item_tea_glass() -> void:
	var record: Dictionary = _record("tea_glass")
	var sip: Dictionary = _ritual("tea_sip")
	var hold_s: float = GameData.as_float(sip.get("hold_s"))
	var uses: int = GameData.as_int(_supply_spec("tea_glass").get("uses"))
	var hot_for: float = GameData.as_float(_params("tea_glass").get("hot_for_s"))
	var hot_calm: float = _give_amount("tea_glass", "nerves", "hot")
	var cold_calm: float = _give_amount("tea_glass", "nerves", "!hot")
	var awake_for: float = _give_duration("tea_glass", "awake")

	# The numbers of GDD 7.4.
	check_eq(GameData.as_string(record.get("kind")), "habit", "the tea glass is a Habit")
	check_eq(GameData.as_array(record.get("slots")), ["cup_a", "cup_b"], "kept in a cup holder")
	check_eq(GameData.as_string(sip.get("gesture")), "HOLD", "a sip is a HOLD")
	check_near(hold_s, 0.6, 0.000001, "of 0.6 s")
	check_eq(uses, 3, "3 sips")
	check_near(hot_calm, -12.0, 0.000001, "a hot sip is -12 Nerves")
	check_near(awake_for, 40.0, 0.000001, "and Awake 40 s")
	check_near(hot_for, 40.0, 0.000001, "cold after 40 s")
	check_near(cold_calm, -3.0, 0.000001, "a cold sip is -3 Nerves")
	check_near(GameData.as_float(_supply_spec("tea_glass").get("restock")), 2.0, 0.000001, "refill 2 cash")

	# HOLD 0.6 s sips; a hot sip is -12 Nerves and Awake 40 s.
	_new_sim()
	var glass: ItemSim.Item = _item("tea_glass")
	check_eq(glass.supply, uses, "he sets out with a full glass")
	_sim.nerves.set_value(60.0)
	check(_reach("cup_a"), "the hand reaches the cup")
	_press(_ticks_in(hold_s))
	check_eq(glass.supply, uses, "a hold one tick short of 0.6 s is no sip")
	check_near(_sim.nerves.value, 60.0, 0.000001, "and does nothing")
	_hold(hold_s)
	check_eq(glass.supply, uses - 1, "holding for 0.6 s is a sip")
	check_near(_sim.nerves.value, 60.0 + hot_calm, 0.000001, "hot: -12 Nerves")
	# (The sip was taken on the last tick the button was down.)
	check_near(_sim.effects.time_left(&"awake"), awake_for - float(SETTLE + 1) * DT, 0.000001, "and Awake for 40 s")
	_run(awake_for - float(SETTLE + 1) * DT - 0.5)
	check(_sim.effects.has(&"awake"), "just short of 40 s he is still Awake")
	_run(1.0)
	check(not _sim.effects.has(&"awake"), "after 40 s no longer")

	# Awake means what it says.
	_new_sim()
	_sim.act = 2
	_sim.nerves.set_value(2.0)
	_run(1.0)
	check(_sim.nerves.heavy, "(with Nerves at the bottom he is Heavy)")
	_hold_at("cup_a", hold_s)
	_run(0.1)
	check(not _sim.nerves.heavy, "a hot sip keeps him from Heavy, however low his Nerves")

	# 3 sips, then the glass is empty.
	_new_sim()
	glass = _item("tea_glass")
	_sim.nerves.set_value(90.0)
	_reach("cup_a")
	for _sip: int in uses:
		_hold(hold_s)
	check_eq(glass.supply, 0, "3 sips empty the glass")
	check_near(_sim.nerves.value, 90.0 + hot_calm * float(uses), 0.000001, "each one hot")
	_hold(hold_s)
	check_near(_sim.nerves.value, 90.0 + hot_calm * float(uses), 0.000001, "an empty glass gives nothing")
	check_eq(_count_events("ritual_completed", "ritual", "tea_sip"), uses, "3 sips were taken, no more")

	# Cold after 40 s: -3 Nerves and no Awake.
	_new_sim()
	glass = _item("tea_glass")
	_sim.nerves.set_value(60.0)
	_reach("cup_a")
	_run(hot_for - 1.5)
	_hold(hold_s)
	check_near(_sim.nerves.value, 60.0 + hot_calm, 0.000001, "just short of 40 s the tea is still hot")
	_run(1.5)
	check_eq(glass.hot_left, 0.0, "after 40 s it is cold")
	_run(awake_for)
	_sim.nerves.set_value(60.0)
	_hold(hold_s)
	check_eq(glass.supply, uses - 2, "(a second sip)")
	check_near(_sim.nerves.value, 60.0 + cold_calm, 0.000001, "a cold sip is -3 Nerves")
	check(not _sim.effects.has(&"awake"), "and no Awake")

	# It spills in a crash, not in a scrape.
	_new_sim()
	_cruise(3, 1)
	glass = _item("tea_glass")
	_scrape()
	check_eq(_sim.faults.lamps, 1, "(a scrape along the rail)")
	check_eq(glass.supply, uses, "a scrape does not spill the tea")
	_cruise(3, 1)
	_sim.traffic.spawn(&"truck", 1, _sim.car.s + 30.0, tuning.fi("gear_speeds", 2) - 50.0)
	var guard: int = _ticks_in(10.0)
	while _sim.collision.hit == Collision.Hit.NONE and guard > 0:
		guard -= 1
		_tick()
	check_eq(_sim.collision.hit, Collision.Hit.CRASH, "(driving into a slow truck is a crash)")
	check_eq(glass.supply, 0, "a crash spills it")
	_ticks(SETTLE)
	_hold_at("cup_a", hold_s)
	check_eq(_count_events("ritual_completed", "ritual", "tea_sip"), 0, "there is nothing left to sip")

	# Spilled by a crash in the middle of a sip, the glass in his hand gives
	# nothing: a truck in his lane that he runs into half-way through the HOLD.
	_new_sim()
	_cruise(3, 1)
	glass = _item("tea_glass")
	_sim.nerves.set_value(40.0)
	_reach("cup_a")
	var closing: float = (tuning.f("scrape_max_closing") + tuning.f("crash_max_closing")) * 0.5
	var nose_to_tail: float = closing * CarSim.KMH_TO_MS * hold_s * 0.5
	_sim.traffic.spawn(&"truck", 1, _sim.car.s + _sim.car.length() * 0.5 + GameData.as_float(data.record("vehicles", "truck").get("length")) * 0.5 + nose_to_tail,
			tuning.fi("gear_speeds", 2) - closing)
	var spilled_at: int = -1
	var nerves_then: float = 0.0
	_input.lmb = true
	for index: int in _ticks_in(hold_s) + 1:
		_tick()
		if spilled_at < 0 and glass.supply == 0:
			spilled_at = index
			nerves_then = _sim.nerves.value
	_input.lmb = false
	_ticks(SETTLE)
	check_eq(GameData.as_int(_event("hit").get("kind")), Collision.Hit.CRASH, "(he runs into a slow truck while he sips)")
	check(spilled_at > 0 and spilled_at < _ticks_in(hold_s) - 1, "(the crash spills the glass in the middle of the HOLD: tick %d of %d)" % [spilled_at, _ticks_in(hold_s)])
	check_eq(_count_events("ritual_completed", "ritual", "tea_sip"), 0, "the sip he was taking when it spilled is no sip")
	check(_sim.nerves.value >= nerves_then, "it calms him by nothing")
	check(not _sim.effects.has(&"awake"), "and does not wake him")

	# Refill: 2 cash at a fuel station.
	_to_quiet_leg("fuel_station")
	_scrape()
	_hold_at("cup_a", hold_s)
	check_eq(_item("tea_glass").supply, uses - 1, "(a sip on the way)")
	_into_stall()
	var refill: Dictionary = _offer(StopSim.RESTOCK, "tea_glass")
	if check(not refill.is_empty(), "the fuel station offers to refill the tea"):
		check_near(GameData.as_float(refill["price"]), 2.0, 0.000001, "for 2 cash")
		var cash: float = _sim.cash
		_tap_at(GameData.as_string(refill["anchor"]))
		check_near(cash - _sim.cash, 2.0, 0.000001, "a TAP pays 2")
		check_eq(_item("tea_glass").supply, uses, "for a full glass")
		check_near(_item("tea_glass").hot_left, hot_for, 0.000001, "hot")

	# A full glass gone cold can be changed for a hot one too.
	_to_quiet_leg("fuel_station")
	_scrape()
	_run(hot_for + 1.0)
	check(_item("tea_glass").supply == uses and _item("tea_glass").hot_left == 0.0, "(a full glass, cold)")
	_into_stall()
	refill = _offer(StopSim.RESTOCK, "tea_glass")
	if check(not refill.is_empty(), "the fuel station offers hot tea for a glass gone cold"):
		_tap_at(GameData.as_string(refill["anchor"]))
		check_near(_item("tea_glass").hot_left, hot_for, 0.000001, "and it is hot again")

	# Free at a tea stall.
	_to_quiet_leg("tea_stall")
	_scrape()
	_hold_at("cup_a", hold_s)
	_run(hot_for)
	check(_item("tea_glass").supply == uses - 1 and _item("tea_glass").hot_left == 0.0, "(a sip gone, and the rest cold)")
	var cash_before: float = _sim.cash
	_into_stall()
	check_eq(_sim.run.stop, "tea_stall", "(a tea stall)")
	check_eq(_item("tea_glass").supply, uses, "a tea stall refills the glass")
	check_near(_item("tea_glass").hot_left, hot_for, 0.000001, "hot")
	check_near(_sim.cash, cash_before, 0.000001, "for nothing")
	check(_offer(StopSim.RESTOCK, "tea_glass").is_empty(), "there is nothing left to pay for")


# --- T-ITEM-BEADS ------------------------------------------------------------

## T-ITEM-BEADS: Worry beads (7.4): at the mirror, each BEAD tap is -2
## Nerves, at most 3 per second; no supply; price 30.
func test_item_beads() -> void:
	var record: Dictionary = _record("beads")
	var calm: float = _give_amount("beads", "nerves")
	var rate: int = tuning.i("bead_max_rate")

	# The numbers of GDD 7.4.
	check_eq(GameData.as_string(record.get("kind")), "habit", "worry beads are a Habit")
	check_eq(GameData.as_array(record.get("slots")), ["mirror"], "that hangs at the mirror")
	check_eq(GameData.as_string(_ritual("beads_count").get("gesture")), "BEAD", "counted by BEAD taps")
	check_near(calm, -2.0, 0.000001, "each bead is -2 Nerves")
	check_eq(rate, 3, "at most 3 per second")
	check(not record.has("supply"), "no supply")
	check_near(GameData.as_float(record.get("price")), 30.0, 0.000001, "price 30")

	# At the mirror, each tap is one bead: -2 Nerves.
	_new_sim()
	check(not _sim.hand.is_anchor_active(_sim.hand.anchor_index(&"mirror")), "(without beads the hand has nothing to do at the mirror)")
	var beads: ItemSim.Item = _give("beads")
	check_eq(_anchor_of("beads"), "mirror", "the beads hang at the mirror")
	check_eq(beads.supply, -1, "and are never used up")
	_sim.nerves.set_value(90.0)
	check(_reach("mirror"), "the hand reaches them")
	check(not _sim.hand.gripping, "with the beads in his hand he is not holding the wheel")
	_tap()
	check_near(_sim.nerves.value, 90.0 + calm, 0.000001, "one tap, one bead: -2 Nerves")
	check_eq(_count_events("ritual_completed", "ritual", "beads_count"), 1, "counted once")
	_run(1.0)
	for _bead: int in 3:
		_tap()
		_run(0.4)
	check_near(_sim.nerves.value, 90.0 + calm * 4.0, 0.000001, "taps a little apart: every one counts")
	_press(_ticks_in(tuning.f("tap_max_time")) + 6)
	check_near(_sim.nerves.value, 90.0 + calm * 4.0, 0.000001, "a press longer than a TAP is no bead")

	# At most 3 per second, however fast he taps: eight taps a second for 3 s.
	_new_sim()
	_give("beads")
	_sim.nerves.set_value(90.0)
	_reach("mirror")
	var counted_at: PackedInt32Array = PackedInt32Array()
	var taps: int = 0
	var gap: int = DriveSim.TICKS_PER_SECOND / 8
	for _tap_index: int in 24:
		var before: float = _sim.nerves.value
		_input.lmb = true
		_ticks(TAP_TICKS)
		_input.lmb = false
		_ticks(gap - TAP_TICKS)
		taps += 1
		if _sim.nerves.value < before:
			counted_at.append(_sim.tick)
	check_eq(taps, 24, "(24 taps in 3 s)")
	check_eq(counted_at.size(), rate * 3, "3 beads a second count, the rest do not")
	check_near(_sim.nerves.value, 90.0 + calm * float(rate * 3), 0.000001, "each of them -2 Nerves")
	var worst: int = 0
	for index: int in counted_at.size():
		var within: int = 0
		for other: int in counted_at.size():
			if counted_at[other] >= counted_at[index] and counted_at[other] - counted_at[index] < DriveSim.TICKS_PER_SECOND - gap:
				within += 1
		worst = maxi(worst, within)
	check(worst <= rate, "never more than 3 inside any one second (%d)" % worst)

	# No supply: he can go on all night. And calm leads to Heavy.
	_new_sim()
	_give("beads")
	_sim.act = 2
	_sim.nerves.set_value(_sim.heavy_floor() + 9.0)
	_reach("mirror")
	for _bead: int in 20:
		_tap()
		_run(0.4)
	check_near(_sim.nerves.value, 0.0, 0.000001, "twenty beads later they still calm him: all the way down")
	check(_sim.nerves.heavy, "and calm leads to Heavy")


# --- T-ITEM-SEEDS ------------------------------------------------------------

## T-ITEM-SEEDS: Sunflower seeds (7.4): TAP 0.3 s starts 20 s of chewing:
## Awake, and immune to Nerves from honks, tailgaters and Doubts; 12
## handfuls, restock 5; price 10.
func test_item_seeds() -> void:
	var record: Dictionary = _record("seeds")
	var chew: Dictionary = _ritual("seeds_chew")
	var chew_for: float = _give_duration("seeds", "chewing")
	var uses: int = GameData.as_int(_supply_spec("seeds").get("uses"))
	var chewing: Dictionary = data.record("effects", "chewing")
	# GDD 6.1: an unanswered Doubt is +10 Nerves (heckles are M9).
	var doubt_nerves: float = 10.0

	# The numbers of GDD 7.4.
	check_eq(GameData.as_string(record.get("kind")), "habit", "sunflower seeds are a Habit")
	check_eq(GameData.as_array(record.get("slots")), ["dash_1", "dash_2"], "kept on the dash")
	check_eq(GameData.as_string(chew.get("gesture")), "TAP", "a handful is a TAP")
	check_near(GameData.as_float(chew.get("perform_s")), 0.3, 0.000001, "of 0.3 s")
	check_near(chew_for, 20.0, 0.000001, "chewing lasts 20 s")
	check(GameData.as_array(chewing.get("implies")).has("awake"), "chewing is Awake")
	for source: String in ["honk", "tailgater", "doubt"]:
		check(GameData.as_array(chewing.get("immune")).has(source), "chewing is immune to Nerves from a %s" % source)
	check_eq(uses, 12, "12 handfuls")
	check_near(GameData.as_float(_supply_spec("seeds").get("restock")), 5.0, 0.000001, "restock 5")
	check_near(GameData.as_float(record.get("price")), 10.0, 0.000001, "price 10")

	# A TAP starts 20 s of chewing.
	_new_sim()
	var seeds: ItemSim.Item = _give("seeds")
	var anchor: String = _anchor_of("seeds")
	check_eq(seeds.supply, uses, "a new bag is full")
	check(_reach(anchor), "the hand reaches the bag on the dash")
	_press(_ticks_in(tuning.f("tap_max_time")) + 6)
	check(not _sim.effects.has(&"chewing") and seeds.supply == uses, "a press longer than a TAP takes nothing")
	_tap()
	check(_sim.effects.has(&"chewing"), "a TAP and he is chewing")
	check_eq(seeds.supply, uses - 1, "one handful gone")
	check_near(_sim.effects.time_left(&"chewing"), chew_for - float(SETTLE) * DT, 0.000001, "for 20 s")
	_run(chew_for - float(SETTLE) * DT - 0.5)
	check(_sim.effects.has(&"chewing"), "just short of 20 s he still chews")
	_run(1.0)
	check(not _sim.effects.has(&"chewing"), "after 20 s no longer")

	# Awake.
	_new_sim()
	_give("seeds")
	_sim.act = 2
	_sim.nerves.set_value(2.0)
	_run(1.0)
	check(_sim.nerves.heavy, "(with Nerves at the bottom he is Heavy)")
	_tap_at(anchor)
	_run(0.1)
	check(not _sim.nerves.heavy, "chewing keeps him Awake")
	_run(chew_for)
	check(_sim.nerves.heavy, "until the handful is gone")

	# Immune to Nerves from honks: a taxi passed closely honks.
	var honk: float = GameData.as_float(data.record("vehicles", "taxi").get("honk_nerves"))
	check_near(honk, 5.0, 0.000001, "(GDD 6.1: honked at is +5 Nerves)")
	_new_sim()
	_give("seeds")
	var plain: float = _pass_a_taxi_closely()
	check_eq(_count_events("sfx_requested", "id", "horn"), 1, "(the taxi honks)")
	_new_sim()
	_give("seeds")
	_tap_at(anchor)
	var chewed: float = _pass_a_taxi_closely()
	check(_sim.effects.has(&"chewing"), "(he chews all through the pass)")
	check_eq(_count_events("sfx_requested", "id", "horn"), 1, "chewing, the taxi honks all the same")
	check_near(plain - chewed, honk, 0.000001, "but the honk's +5 Nerves do not reach him")
	check(plain > honk, "(not chewing, they do)")

	# Immune to Nerves from a tailgater.
	var special: Dictionary = GameData.as_dict(data.record("legs", "tailgater").get("special"))
	var tail_rate: float = GameData.as_float(special.get("nerves_per_s"))
	_begin_quiet_leg("tailgater", 2, 71)
	_give("seeds")
	var guard: int = _ticks_in(60.0)
	while _sim.encounter.tail_phase != EncounterSim.TAIL_ON_BUMPER and guard > 0:
		guard -= 1
		_tick()
	_run(1.0)
	_sim.nerves.set_value(40.0)
	_run(4.0)
	var bare_rate: float = (_sim.nerves.value - 40.0) / 4.0
	check_near(bare_rate, tail_rate + tuning.f("traffic_rate"), 0.001, "(a tailgater on his bumper: +1 Nerves a second, and what any vehicle so near adds)")
	_tap_at(anchor)
	_sim.nerves.set_value(40.0)
	_run(4.0)
	check(_sim.encounter.tail_phase == EncounterSim.TAIL_ON_BUMPER and _sim.effects.has(&"chewing"), "(still there, and he chews)")
	check_near((_sim.nerves.value - 40.0) / 4.0, tuning.f("traffic_rate"), 0.001, "chewing, the tailgater's +1 a second is gone; the traffic's is not")
	_run(chew_for)
	if _sim.encounter.tail_phase == EncounterSim.TAIL_ON_BUMPER:
		_sim.nerves.set_value(40.0)
		_run(2.0)
		check_near((_sim.nerves.value - 40.0) / 2.0, tail_rate + tuning.f("traffic_rate"), 0.001, "when the handful is gone the tailgater is felt again")
	else:
		fail("the tailgater left before the chewing ended")

	# Immune to Nerves from Doubts; other frights still reach him, and so does calm.
	_new_sim()
	_give("seeds")
	_sim.nerves.set_value(40.0)
	_sim.fray(DriveSim.SOURCE_DOUBT, doubt_nerves)
	check_near(_sim.nerves.value, 40.0 + doubt_nerves, 0.000001, "(not chewing, a Doubt's Nerves reach him)")
	_tap_at(anchor)
	_sim.nerves.set_value(40.0)
	_sim.fray(DriveSim.SOURCE_DOUBT, doubt_nerves)
	check_near(_sim.nerves.value, 40.0, 0.000001, "chewing, a Doubt's Nerves do not")
	_sim.fray(DriveSim.SOURCE_HONK, -honk)
	check_near(_sim.nerves.value, 40.0 - honk, 0.000001, "a happy honk still calms him")
	_sim.nerves.set_value(40.0)
	_sim.nerves.add(tuning.f("cut_off_nerves"))
	check_near(_sim.nerves.value, 40.0 + tuning.f("cut_off_nerves"), 0.000001, "and being cut off still frays him")

	# 12 handfuls.
	_new_sim()
	seeds = _give("seeds")
	_reach(anchor)
	for _handful: int in uses:
		_tap()
	check_eq(seeds.supply, 0, "12 handfuls empty the bag")
	_run(chew_for + 1.0)
	_tap()
	check(not _sim.effects.has(&"chewing"), "an empty bag gives nothing")

	# Restock 5, at a fuel station.
	_to_quiet_leg("fuel_station")
	_scrape()
	_give("seeds")
	_tap_at(anchor)
	_into_stall()
	var refill: Dictionary = _offer(StopSim.RESTOCK, "seeds")
	if check(not refill.is_empty(), "the fuel station offers to restock the seeds"):
		check_near(GameData.as_float(refill["price"]), 5.0, 0.000001, "for 5")
		var cash: float = _sim.cash
		_tap_at(GameData.as_string(refill["anchor"]))
		check_near(cash - _sim.cash, 5.0, 0.000001, "a TAP pays 5")
		check_eq(_item("seeds").supply, uses, "for a full bag")


# --- T-ITEM-TISSUE-BOX -------------------------------------------------------

## T-ITEM-TISSUE-BOX: Tissue box (7.4): one wipe (DRAG across the glass,
## 0.8 s) clears all Haze; 6 tissues, restock 5; price 15.
func test_item_tissue_box() -> void:
	var record: Dictionary = _record("tissue_box")
	var wipe: Dictionary = _ritual("tissue_wipe")
	var across: float = GameData.as_float(wipe.get("across_m"))
	var uses: int = GameData.as_int(_supply_spec("tissue_box").get("uses"))

	# The numbers of GDD 7.4.
	check_eq(GameData.as_string(record.get("kind")), "habit", "the tissue box is a Habit")
	check_eq(GameData.as_array(record.get("slots")), ["dash_1", "dash_2"], "kept on the dash")
	check_eq(GameData.as_string(wipe.get("gesture")), "DRAG_TO", "a wipe is a drag")
	check(across > 0.0 and not wipe.has("to"), "across the glass: a way sideways, to nowhere in particular")
	check_near(GameData.as_float(wipe.get("perform_s")), 0.8, 0.000001, "of 0.8 s")
	check_eq(uses, 6, "6 tissues")
	check_near(GameData.as_float(_supply_spec("tissue_box").get("restock")), 5.0, 0.000001, "restock 5")
	check_near(GameData.as_float(record.get("price")), 15.0, 0.000001, "price 15")

	# One wipe clears all Haze.
	_new_sim()
	var box: ItemSim.Item = _give("tissue_box")
	var anchor: String = _anchor_of("tissue_box")
	var from: Vector3 = _sim.hand.anchor_position(_sim.hand.anchor_index(StringName(anchor)))
	# Points in front of the glass: one a full wipe away, one short of it.
	var far: Vector3 = Vector3(from.x - across - 0.05, 0.25, 0.05)
	var near: Vector3 = Vector3(from.x - across * 0.6, 0.35, 0.05)
	_sim.items.haze = tuning.f("haze_cap")
	_carry(anchor, [near])
	check(_sim.items.haze > tuning.f("haze_cap") * 0.5, "a tissue carried only part of the way wipes nothing")
	check_eq(box.supply, uses, "and is not used up")
	_sim.items.haze = tuning.f("haze_cap")
	_carry(anchor, [far])
	check_near(_sim.items.haze, 0.0, 0.000001, "one wipe across the glass clears all Haze")
	check_eq(box.supply, uses - 1, "and uses one tissue")
	check_eq(_count_events("ritual_completed", "ritual", "tissue_wipe"), 1, "(one wipe)")
	check(not _sim.hand.gripping, "the wipe is the hand's: it is not on the wheel")

	# The smoke comes back: a wipe clears what is there, no more.
	var light_s: float = GameData.as_float(_ritual("cig_light").get("hold_s"))
	_hold_at("ashtray", light_s)
	_run(10.0)
	check(_sim.items.haze > 0.15, "(he smokes: Haze again)")
	_carry(anchor, [far])
	check_near(_sim.items.haze, 0.0, 0.01, "a wipe clears it")
	_run(2.0)
	check(_sim.items.haze > 0.0, "and the cigarette goes on clouding the glass")

	# 6 tissues.
	_new_sim()
	box = _give("tissue_box")
	for _tissue: int in uses:
		_carry(anchor, [far])
	check_eq(box.supply, 0, "6 wipes empty the box")
	_sim.items.haze = tuning.f("haze_cap")
	_carry(anchor, [far])
	check(_sim.items.haze > tuning.f("haze_cap") * 0.5, "an empty box wipes nothing")
	check_eq(_count_events("ritual_completed", "ritual", "tissue_wipe"), uses, "(6 wipes, no more)")

	# Restock 5, at a fuel station.
	_to_quiet_leg("fuel_station")
	_scrape()
	_give("tissue_box")
	_carry(anchor, [far])
	check_eq(_item("tissue_box").supply, uses - 1, "(a tissue used on the way)")
	_into_stall()
	var refill: Dictionary = _offer(StopSim.RESTOCK, "tissue_box")
	if check(not refill.is_empty(), "the fuel station offers to restock the tissues"):
		check_near(GameData.as_float(refill["price"]), 5.0, 0.000001, "for 5")
		var cash: float = _sim.cash
		_tap_at(GameData.as_string(refill["anchor"]))
		check_near(cash - _sim.cash, 5.0, 0.000001, "a TAP pays 5")
		check_eq(_item("tissue_box").supply, uses, "for a full box")


# --- T-ITEM-MIXTAPE ----------------------------------------------------------

## T-ITEM-MIXTAPE: Mixtape (7.4): music that never drifts, -1 Nerves per
## second; it must be flipped every 60 s (DRAG out and in, 0.8 s) or it
## warbles, +0.5 Nerves per second; price 25.
func test_item_mixtape() -> void:
	var record: Dictionary = _record("mixtape")
	var flip: Dictionary = _ritual("tape_flip")
	var side: float = GameData.as_float(_params("mixtape").get("side_s"))
	var out: float = GameData.as_float(flip.get("out_m"))
	var play_rate: float = 0.0
	var warble_rate: float = 0.0
	for list: String in ["gives", "takes"]:
		for listed: Variant in GameData.as_array(record.get(list)):
			var entry: Dictionary = GameData.as_dict(listed)
			if entry.has("per_s") and GameData.as_string(entry.get("while")) == "playing":
				play_rate = GameData.as_float(entry.get("per_s"))
			if entry.has("per_s") and GameData.as_string(entry.get("while")) == "warbling":
				warble_rate = GameData.as_float(entry.get("per_s"))

	# The numbers of GDD 7.4.
	check_eq(GameData.as_string(record.get("kind")), "habit", "the mixtape is a Habit")
	check_eq(GameData.as_array(record.get("slots")), ["tape"], "that goes in the deck")
	check_near(play_rate, -1.0, 0.000001, "-1 Nerves per second")
	check_near(side, 60.0, 0.000001, "a side lasts 60 s")
	check_near(warble_rate, 0.5, 0.000001, "then it warbles: +0.5 Nerves per second")
	check_eq(GameData.as_string(flip.get("gesture")), "DRAG_TO", "flipping is a drag")
	check(GameData.as_string(flip.get("to")) == "@slot" and out > 0.0, "out of the deck and in again")
	check_near(GameData.as_float(flip.get("perform_s")), 0.8, 0.000001, "of 0.8 s")
	check(not record.has("supply"), "no supply")
	check_near(GameData.as_float(record.get("price")), 25.0, 0.000001, "price 25")

	# Music at -1 Nerves per second that never drifts.
	_new_sim()
	var tape: ItemSim.Item = _give("mixtape")
	check_eq(_anchor_of("mixtape"), "tape", "the tape is in the deck")
	_sim.nerves.set_value(90.0)
	_run(10.0)
	check_near(_sim.nerves.value, 90.0 + play_rate * 10.0, 0.000001, "it plays: -1 Nerves per second")
	check(_sim.effects.has(&"music"), "and it is music")
	check(side > tuning.f("radio_drift_time") + 5.0, "(a side is longer than the radio holds a station)")
	_run(tuning.f("radio_drift_time") - 10.0 + 5.0)
	check(_sim.effects.has(&"music"), "after the time a station takes to drift it still plays")
	_sim.nerves.set_value(90.0)
	_run(5.0)
	check_near(_sim.nerves.value, 90.0 + play_rate * 5.0, 0.000001, "as calming as ever")

	# Unflipped after 60 s it warbles.
	_run(side - tape.side_time - 0.5)
	check(_sim.effects.has(&"music"), "just short of 60 s it still plays")
	_run(1.0)
	check(not _sim.effects.has(&"music"), "after 60 s unflipped it is music no longer")
	_sim.nerves.set_value(50.0)
	_run(10.0)
	check_near(_sim.nerves.value, 50.0 + warble_rate * 10.0, 0.000001, "it warbles: +0.5 Nerves per second")
	var shown: Array[Dictionary] = _sim.snapshot()["items"]
	check(GameData.as_bool(shown[shown.size() - 1].get("warbling")), "(the snapshot says so)")

	# Flipped: out of the deck and in again.
	var deck: Vector3 = _sim.hand.anchor_position(_sim.hand.anchor_index(&"tape"))
	var out_far: Vector3 = Vector3(deck.x, 0.35, 0.05)
	var out_near: Vector3 = Vector3(deck.x, 0.12, 0.05)
	check(out_far.distance_to(deck) > out and out_near.distance_to(deck) < out, "(one point far enough out of the deck, one not)")
	_carry("tape", [out_far])
	check(not _sim.effects.has(&"music"), "taken out and let go in mid-air, it is not flipped")
	_carry("tape", [out_near], "tape")
	check(not _sim.effects.has(&"music"), "nor pulled only part of the way out")
	_carry("tape", [out_far], "tape")
	check_eq(_count_events("ritual_completed", "ritual", "tape_flip"), 1, "out and in again: flipped")
	_run(0.1)
	check(_sim.effects.has(&"music"), "and it plays again")
	_sim.nerves.set_value(90.0)
	_run(10.0)
	check_near(_sim.nerves.value, 90.0 + play_rate * 10.0, 0.000001, "-1 Nerves per second")
	_run(side - tape.side_time - 0.5)
	check(_sim.effects.has(&"music"), "for another 60 s")
	_run(1.0)
	check(not _sim.effects.has(&"music"), "and then it wants flipping again")

	# A flip before the side is out starts the 60 s again.
	_new_sim()
	tape = _give("mixtape")
	_run(side * 0.5)
	_carry("tape", [out_far], "tape")
	check(tape.side_time < 1.0, "flipped early, the side starts again")
	_run(side - 2.0)
	check(_sim.effects.has(&"music"), "and plays its 60 s from there")

	# Bought for 25 at a fuel station and carried to the deck: the radio's dial
	# is at the same place and gives way to the tape in his hand.
	var price: float = GameData.as_float(record.get("price"))
	var sold: Dictionary = _to_fuel_station_selling("mixtape")
	if check(not sold.is_empty(), "one of the first fuel stations of forty Tellings sells a mixtape"):
		check_near(GameData.as_float(sold["price"]), price, 0.000001, "for its 25")
		_sim.cash = price + 5.0
		_tap_at(GameData.as_string(sold["anchor"]))
		check(GameData.as_bool(_offer(StopSim.ITEM, "mixtape").get("bought")), "a TAP buys it")
		check_near(_sim.cash, 5.0, 0.000001, "for 25")
		_drag(GameData.as_string(sold["anchor"]), "tape")
		check(_item("mixtape") != null and _anchor_of("mixtape") == "tape", "a DRAG from the tray puts it in the deck, where the radio's dial was")
		check(_offer(StopSim.ITEM, "mixtape").is_empty(), "and it is off the tray")
		_leave_stop()
		check_near(_sim.cash, 5.0, 0.000001, "nothing is paid back when he leaves: the tape is in its place")
		_run(0.5)
		check(_sim.effects.has(&"music"), "and on the road it plays")
		check(not _sim.hand.is_anchor_active(_sim.hand.anchor_index(&"radio")) and _sim.hand.is_anchor_active(_sim.hand.anchor_index(&"tape")),
				"the deck has taken the dial's place")

	# On the road the dial gives way to a tape in his hand too. At a stop the
	# dial is not in use at all, and nothing in the cabin as it is sold is
	# carried to the deck on the road: so this tape is one that may be stowed
	# (a private copy of the data). With the tape in the glovebox the dial is
	# the hand's again; taken out, the tape still goes back into the deck.
	var cabin: GameData = fresh_data()
	cabin.record("items", "mixtape")["rituals"] = ["stow", "tape_flip"]
	if check(DataValidator.validate(cabin).is_empty(), "(a mixtape that may be stowed validates)"):
		_sim = DriveSim.new(cabin)
		_sim.in_encounter = true
		_events = []
		_input.clear()
		_give("mixtape")
		var dial: int = _sim.hand.anchor_index(&"radio")
		var slot: int = _sim.hand.anchor_index(&"tape")
		_tap_at("glovebox")
		_drag("tape", "glovebox")
		check(_item("mixtape") != null and _sim.items.is_stowed(_item("mixtape")), "(on the road, the tape is stowed in the glovebox)")
		check(_sim.hand.is_anchor_active(dial) and not _sim.hand.is_anchor_active(slot), "(with the deck empty the dial is the hand's again)")
		# Taken out and let go in mid-air: nothing has moved, the dial least of all.
		_carry("glovebox", [out_far])
		check(_item("mixtape") != null and _sim.items.is_stowed(_item("mixtape")), "(let go in mid-air, the tape stays in the glovebox)")
		check(_sim.hand.is_anchor_active(dial) and not _sim.hand.is_anchor_active(slot), "and when the carry is over the dial is back")
		# Taken out and carried to the deck.
		_reach("glovebox")
		_input.lmb = true
		_ticks(_ticks_in(0.1))
		check(_sim.hand.carrying, "(he takes the tape out of the glovebox)")
		check(not _sim.hand.is_anchor_active(dial) and _sim.hand.is_anchor_active(slot), "while the tape is in his hand the dial gives way to the deck")
		_input.pointer = _sim.hand.anchor_pointer(slot)
		_ticks(_ticks_in(2.5))
		check_eq(_sim.hand.at_id(), &"tape", "the hand comes to rest on the deck, not on the dial")
		_input.lmb = false
		_ticks(_ticks_in(0.3))
		_input.clear()
		check(_item("mixtape") != null and _anchor_of("mixtape") == "tape", "and the tape goes back into the deck, on the road as at a stop")

	# The deck plays the tape, not the radio.
	_new_sim()
	_sim.items.drag_step(_ritual("radio_tune"), 1)
	_sim.items.drag_step(_ritual("radio_tune"), 1)
	_run(0.1)
	check(_sim.items.radio == &"news" and _sim.effects.has(&"news"), "(the radio is on the news)")
	_give("mixtape")
	_run(0.1)
	check_eq(_sim.items.radio, ItemSim.STATIC, "with a tape in the deck the radio is silent")
	check(not _sim.effects.has(&"news"), "and its station's effect is gone")
	check(not _sim.hand.is_anchor_active(_sim.hand.anchor_index(&"radio")), "the dial is not offered to the hand")
	check(_reach("tape"), "the tape is, at the same place")
	_sim.nerves.set_value(90.0)
	_run(10.0)
	check_near(_sim.nerves.value, 90.0 + play_rate * 10.0, 0.000001, "the tape alone plays: -1 a second, not the radio's too")

	# An open window halves what comes out of the deck.
	_sim.items.flags[&"window_open"] = true
	_sim.nerves.set_value(90.0)
	_run(10.0)
	check_near(_sim.nerves.value, 90.0 + play_rate * tuning.f("window_radio_mult") * 10.0, 0.000001, "with the window open the tape calms half as much")


# --- T-ITEM-ENERGY-DRINK -----------------------------------------------------

## T-ITEM-ENERGY-DRINK: Energy drink (7.4): HOLD 0.6 s; Focus for 30 s (the
## road runs at 85% speed while the hand runs at full speed) and Awake 60 s;
## +10 Nerves at once, then Tremor amplitude +50% for 20 s; 3 cans, restock
## 10; price 30.
func test_item_energy_drink() -> void:
	var record: Dictionary = _record("energy_drink")
	var sip: Dictionary = _ritual("energy_drink_sip")
	var hold_s: float = GameData.as_float(sip.get("hold_s"))
	var focus_for: float = _give_duration("energy_drink", "focus")
	var awake_for: float = _give_duration("energy_drink", "awake")
	var road_speed: float = GameData.as_float(data.record("effects", "focus").get("road_speed"))
	var jolt: float = 0.0
	var jitters_for: float = 0.0
	for take: Variant in GameData.as_array(record.get("takes")):
		var entry: Dictionary = GameData.as_dict(take)
		if GameData.as_string(entry.get("resource")) == "nerves":
			jolt = GameData.as_float(entry.get("amount"))
		if GameData.as_string(entry.get("effect")) == "jitters":
			jitters_for = GameData.as_float(entry.get("duration"))
	var shake: float = GameData.as_float(data.record("effects", "jitters").get("tremor_scale"))
	var uses: int = GameData.as_int(_supply_spec("energy_drink").get("uses"))

	# The numbers of GDD 7.4.
	check_eq(GameData.as_string(record.get("kind")), "habit", "the energy drink is a Habit")
	check_eq(GameData.as_array(record.get("slots")), ["cup_a", "cup_b"], "kept in a cup holder")
	check_eq(GameData.as_string(sip.get("gesture")), "HOLD", "drunk with a HOLD")
	check_near(hold_s, 0.6, 0.000001, "of 0.6 s")
	check_near(focus_for, 30.0, 0.000001, "Focus for 30 s")
	check_near(road_speed, 0.85, 0.000001, "in which the road runs at 85% speed")
	check_near(awake_for, 60.0, 0.000001, "Awake 60 s")
	check_near(jolt, 10.0, 0.000001, "+10 Nerves at once")
	check_near(shake, 1.5, 0.000001, "Tremor amplitude +50%")
	check_near(jitters_for, 20.0, 0.000001, "for 20 s")
	check_eq(uses, 3, "3 cans")
	check_near(GameData.as_float(_supply_spec("energy_drink").get("restock")), 10.0, 0.000001, "restock 10")
	check_near(GameData.as_float(record.get("price")), 30.0, 0.000001, "price 30")

	# HOLD 0.6 s: +10 Nerves at once, Focus, Awake.
	_new_sim()
	var cans: ItemSim.Item = _give("energy_drink")
	var cup: String = _anchor_of("energy_drink")
	check_eq(cup, "cup_b", "(the tea has the first cup holder: the cans go in the second)")
	check_eq(cans.supply, uses, "three cans")
	_sim.nerves.set_value(40.0)
	check(_reach(cup), "the hand reaches the can")
	_press(_ticks_in(hold_s))
	check(cans.supply == uses and not _sim.effects.has(&"focus"), "a hold one tick short of 0.6 s drinks nothing")
	_hold(hold_s)
	check_eq(cans.supply, uses - 1, "holding for 0.6 s drinks one")
	check_near(_sim.nerves.value, 40.0 + jolt, 0.000001, "+10 Nerves at once")
	check(_sim.effects.has(&"focus"), "he has Focus")
	check_near(_sim.effects.time_left(&"focus"), focus_for - float(SETTLE + 1) * DT, 0.000001, "for 30 s")
	check_near(_sim.effects.time_left(&"awake"), awake_for - float(SETTLE + 1) * DT, 0.000001, "and is Awake for 60 s")

	# Focus: the road runs at 85% speed...
	_begin_quiet_leg("open_road", 1, 5)
	_give("energy_drink")
	var plain: Dictionary = _a_second_of_road()
	check_near(GameData.as_float(plain["leg_time"]), 1.0, 0.000001, "(a second is a second on the leg's clock)")
	check_near(GameData.as_float(plain["car"]), tuning.fi("gear_speeds", 2) / 3.6, 0.0001, "(without Focus third gear covers 27.8 m a second)")
	var gust_carry: float = tuning.f("gust_push") * tuning.f("gust_duration")
	var plain_gust: Dictionary = _a_gust(tuning.f("gust_duration") * 2.0)
	check_eq(GameData.as_int(plain_gust["ticks"]), _ticks_in(tuning.f("gust_duration")), "(without Focus a gust blows for gust_duration)")
	check_near(GameData.as_float(plain_gust["carried"]), gust_carry, tuning.f("gust_push") * DT * 0.25, "(and carries the car gust_push x gust_duration)")
	_hold_at(cup, hold_s)
	var focused: Dictionary = _a_second_of_road()
	check_near(GameData.as_float(focused["car"]), GameData.as_float(plain["car"]) * road_speed, 0.0001, "with Focus the car covers 85% of the road in a second")
	check_near(GameData.as_float(focused["truck"]), GameData.as_float(plain["truck"]) * road_speed, 0.0001, "and so does the traffic")
	check_near(GameData.as_float(focused["sideways"]), GameData.as_float(plain["sideways"]) * road_speed, 0.0001, "and the drift that carries him sideways")
	check_near(_sim.car.speed, tuning.fi("gear_speeds", 2), 0.000001, "(the speedometer still reads the gear's speed)")
	# ...while the hand, and his own time, run at full speed.
	check_eq(GameData.as_int(focused["reach_ticks"]), GameData.as_int(plain["reach_ticks"]), "the hand takes as long as ever to reach across")
	check_near(GameData.as_float(focused["wheel"]), GameData.as_float(plain["wheel"]), 0.000001, "the wheel turns as fast as ever under it")
	check_near(GameData.as_float(focused["clock"]), GameData.as_float(plain["clock"]), 0.000001, "and the Clock does not slow")
	check_near(GameData.as_float(focused["leg_time"]), GameData.as_float(plain["leg_time"]), 0.000001, "nor does the leg's")
	# A gust is the road's: with Focus it blows for gust_duration of the road's
	# time, longer by his clock, and carries the car as far as ever (to half a
	# tick of its push: it lasts a whole number of ticks).
	var focused_gust: Dictionary = _a_gust(tuning.f("gust_duration") / road_speed * 2.0)
	check(_sim.effects.has(&"focus"), "(he still has Focus)")
	check_eq(GameData.as_int(focused_gust["ticks"]), roundi(tuning.f("gust_duration") / (DT * road_speed)), "with Focus a gust blows for gust_duration of the road's time: longer by his clock")
	check(GameData.as_int(focused_gust["ticks"]) > GameData.as_int(plain_gust["ticks"]), "(%d ticks in place of %d)" % [GameData.as_int(focused_gust["ticks"]), GameData.as_int(plain_gust["ticks"])])
	check_near(GameData.as_float(focused_gust["carried"]), gust_carry, tuning.f("gust_push") * DT * road_speed * 0.5, "and carries the car as far as it does without")
	# For 30 s.
	_run(_sim.effects.time_left(&"focus") - 0.5)
	check(_sim.effects.has(&"focus"), "just short of 30 s he still has Focus")
	_run(1.0)
	check(not _sim.effects.has(&"focus"), "after 30 s no longer")
	var after: Dictionary = _a_second_of_road()
	check_near(GameData.as_float(after["car"]), GameData.as_float(plain["car"]), 0.0001, "and the road runs at full speed again")

	# Awake 60 s.
	_new_sim()
	_give("energy_drink")
	_sim.act = 3
	_sim.nerves.set_value(0.0)
	_run(1.0)
	check(_sim.nerves.heavy, "(at the bottom of his Nerves he is Heavy)")
	_hold_at(cup, hold_s)
	check(_sim.nerves.value < _sim.heavy_floor(), "(the can's +10 leaves him under the floor of Act 3)")
	_run(awake_for - float(SETTLE + 1) * DT - 0.5)
	_sim.nerves.set_value(0.0)
	_run(0.1)
	check(not _sim.nerves.heavy, "just short of 60 s he is still Awake")
	_run(1.0)
	check(_sim.nerves.heavy, "after 60 s no longer")

	# Then Tremor amplitude +50% for 20 s.
	_new_sim()
	_give("energy_drink")
	_hold_at(cup, hold_s)
	_sim.nerves.set_value(70.0)
	_run(1.0)
	var base: float = tuning.f("tremor_max_amplitude") * (70.0 - tuning.f("tremor_from")) / (tuning.f("snap_at") - tuning.f("tremor_from"))
	check_near(_sim.nerves.tremor_amplitude, base * shake, 0.000001, "after the can his Tremor is half as big again")
	_run(jitters_for - float(SETTLE + 1) * DT - 1.0 - 0.5)
	check_near(_sim.nerves.tremor_amplitude, base * shake, 0.000001, "until just short of 20 s")
	_run(1.0)
	check_near(_sim.nerves.tremor_amplitude, base, 0.000001, "after 20 s it is its plain size again")

	# 3 cans.
	_new_sim()
	cans = _give("energy_drink")
	_reach(cup)
	for _can: int in uses:
		_hold(hold_s)
	check_eq(cans.supply, 0, "3 cans and they are gone")
	_sim.nerves.set_value(40.0)
	_hold(hold_s)
	check_near(_sim.nerves.value, 40.0, 0.000001, "an empty can gives nothing")

	# Restock 10, at a fuel station.
	_to_quiet_leg("fuel_station")
	_scrape()
	_give("energy_drink")
	_hold_at(cup, hold_s)
	_into_stall()
	var refill: Dictionary = _offer(StopSim.RESTOCK, "energy_drink")
	if check(not refill.is_empty(), "the fuel station offers to restock the cans"):
		check_near(GameData.as_float(refill["price"]), 10.0, 0.000001, "for 10")
		var cash: float = _sim.cash
		_tap_at(GameData.as_string(refill["anchor"]))
		check_near(cash - _sim.cash, 10.0, 0.000001, "a TAP pays 10")
		check_eq(_item("energy_drink").supply, uses, "for three cans")
	check(not _sim.effects.has(&"focus"), "(and the Focus he drove in with is gone: a stop ends every timer)")
	# What the stop ends it says: each status of the can began once and is announced as over once.
	for give: Variant in GameData.as_array(record.get("gives")) + GameData.as_array(record.get("takes")):
		var entry: Dictionary = GameData.as_dict(give)
		if not entry.has("effect") or not entry.has("duration"):
			continue
		var status: String = GameData.as_string(entry.get("effect"))
		check(not _sim.effects.has(StringName(status)), "(%s is over at the stop)" % status)
		check_eq(_count_events("effect_added", "effect", status), 1, "(%s began with the can)" % status)
		check_eq(_count_events("effect_expired", "effect", status), 1, "the stop that ends %s announces its end" % status)
	var entered_at: int = _events.find(_event("stop_entered"))
	check(entered_at >= 0 and _events.find(_event("effect_expired")) < entered_at, "before the stop itself is announced")


# --- T-ITEM-PAINKILLERS ------------------------------------------------------

## T-ITEM-PAINKILLERS: Painkillers (7.4): HOLD 1.2 s at the face; Tremor
## halved for 60 s and the Phantom muted for the leg; Heavy floor +15 for
## the rest of the leg; the hand at his face blocks the lower-centre view; 6
## pills, restock 15; price 40.
func test_item_painkillers() -> void:
	var record: Dictionary = _record("painkillers")
	var take: Dictionary = _ritual("painkillers_take")
	var hold_s: float = GameData.as_float(take.get("hold_s"))
	var numb_for: float = _give_duration("painkillers", "painkillers")
	var halved: float = GameData.as_float(data.record("effects", "painkillers").get("tremor_scale"))
	var floor_up: float = GameData.as_float(data.record("effects", "drowsy").get("heavy_floor"))
	var uses: int = GameData.as_int(_supply_spec("painkillers").get("uses"))
	var slap_nerves: float = 0.0
	for op: Variant in GameData.as_array(_ritual("slap").get("on_complete")):
		if GameData.as_string(op).begins_with("nerves:"):
			slap_nerves = GameData.as_string(op).substr(7).to_float()

	# The numbers of GDD 7.4.
	check_eq(GameData.as_string(record.get("kind")), "habit", "painkillers are a Habit")
	check_eq(GameData.as_array(record.get("slots")), ["dash_1", "dash_2"], "kept on the dash")
	check_eq(GameData.as_string(take.get("anchor")), "face", "taken at his face")
	check_eq(GameData.as_string(take.get("gesture")), "HOLD", "with a HOLD")
	check_near(hold_s, 1.2, 0.000001, "of 1.2 s")
	check_eq(GameData.as_string(take.get("blocks_view")), "lower_centre", "which blocks the lower-centre view")
	check_near(halved, 0.5, 0.000001, "Tremor halved")
	check_near(numb_for, 60.0, 0.000001, "for 60 s")
	check_near(floor_up, 15.0, 0.000001, "Heavy floor +15")
	check(GameData.as_bool(data.record("effects", "phantom_mute").get("mutes_phantom")), "the Phantom muted")
	var for_leg: int = 0
	for list: String in ["gives", "takes"]:
		for listed: Variant in GameData.as_array(record.get(list)):
			if GameData.as_string(GameData.as_dict(listed).get("for")) == "leg":
				for_leg += 1
	check_eq(for_leg, 2, "both of those for the leg")
	check_eq(uses, 6, "6 pills")
	check_near(GameData.as_float(_supply_spec("painkillers").get("restock")), 15.0, 0.000001, "restock 15")
	check_near(GameData.as_float(record.get("price")), 40.0, 0.000001, "price 40")

	# HOLD 1.2 s at the face.
	_new_sim()
	var pills: ItemSim.Item = _give("painkillers")
	var dash: String = _anchor_of("painkillers")
	check(_sim.items.ritual_at(dash).is_empty(), "the bottle on the dash is not where they are taken")
	_sim.nerves.set_value(70.0)
	check(_reach("face"), "the hand goes to his face")
	_press(_ticks_in(hold_s))
	check(pills.supply == uses and not _sim.effects.has(&"painkillers"), "a hold one tick short of 1.2 s takes nothing")
	check_near(_sim.nerves.value, 70.0, 0.000001, "and is no slap either")
	_input.lmb = true
	_ticks(_ticks_in(hold_s) / 2)
	check_eq(GameData.as_string(_sim.snapshot()["view_block"]), "lower_centre", "while he holds the bottle to his teeth the lower-centre view is blocked")
	_ticks(_ticks_in(hold_s) - _ticks_in(hold_s) / 2 + 1)
	_input.lmb = false
	_ticks(SETTLE)
	check_eq(pills.supply, uses - 1, "holding for 1.2 s takes one")
	check(_sim.effects.has(&"painkillers"), "and it works")
	check_eq(GameData.as_string(_sim.snapshot()["view_block"]), "", "the view is clear again")
	var face: Vector2 = _sim.hand.anchor_pointer(_sim.hand.anchor_index(&"face"))
	var width: float = tuning.f("reference_width")
	var height: float = tuning.f("reference_height")
	check(face.x > width / 3.0 and face.x < width * 2.0 / 3.0 and face.y > height * 0.5, "(his face is in the lower centre of the view: that is where the hand is)")

	# A TAP at his face is still a slap.
	_sim.nerves.set_value(20.0)
	_tap()
	check_near(_sim.nerves.value, 20.0 + slap_nerves, 0.000001, "with pills aboard a TAP at his face is still a slap")
	check_eq(pills.supply, uses - 1, "and takes no pill")
	_sim.nerves.set_value(20.0)
	_press(_ticks_in(tuning.f("tap_max_time")) + 6)
	check_near(_sim.nerves.value, 20.0, 0.000001, "a press longer than a TAP and shorter than the HOLD is neither")
	check_eq(pills.supply, uses - 1, "(no pill, no slap)")

	# Tremor halved for 60 s.
	_new_sim()
	_give("painkillers")
	_sim.nerves.set_value(70.0)
	_run(0.5)
	var base: float = tuning.f("tremor_max_amplitude") * (70.0 - tuning.f("tremor_from")) / (tuning.f("snap_at") - tuning.f("tremor_from"))
	check_near(_sim.nerves.tremor_amplitude, base, 0.000001, "(at Nerves 70 his hand shakes)")
	_hold_at("face", hold_s)
	_run(1.0)
	check_near(_sim.nerves.tremor_amplitude, base * halved, 0.000001, "a pill halves the Tremor")
	_run(numb_for - float(SETTLE + 1) * DT - 1.0 - 0.5)
	check_near(_sim.nerves.tremor_amplitude, base * halved, 0.000001, "until just short of 60 s")
	_run(1.0)
	check_near(_sim.nerves.tremor_amplitude, base, 0.000001, "after 60 s it is whole again")

	# The Phantom muted, and the Heavy floor +15, for the rest of the leg.
	_to_quiet_leg("fuel_station")
	_scrape()
	_give("painkillers")
	var floor_before: float = _sim.heavy_floor()
	check(not _sim.phantom_muted(), "(the Phantom is not muted)")
	_sim.nerves.set_value(floor_before + floor_up - 5.0)
	_run(0.5)
	check(not _sim.nerves.heavy, "(above the floor he is not Heavy)")
	_hold_at("face", hold_s)
	check_near(_sim.heavy_floor(), floor_before + floor_up, 0.000001, "a pill raises the Heavy floor by 15")
	check(_sim.phantom_muted(), "and mutes the Phantom")
	_sim.nerves.set_value(floor_before + floor_up - 5.0)
	_run(0.5)
	check(_sim.nerves.heavy, "Nerves that were fine are now under the floor: he is Heavy")
	_hold(hold_s)
	check_eq(_item("painkillers").supply, uses - 2, "(a second pill)")
	check_near(_sim.heavy_floor(), floor_before + floor_up, 0.000001, "a second pill does not raise the floor again")
	_run(numb_for + 5.0)
	check(not _sim.effects.has(&"painkillers"), "(the Tremor's 60 s are over)")
	check_near(_sim.heavy_floor(), floor_before + floor_up, 0.000001, "the floor stays up")
	check(_sim.phantom_muted(), "and the Phantom stays muted")
	_into_stall()
	check_near(_sim.heavy_floor(), floor_before + floor_up, 0.000001, "through the leg's stop")
	check(_sim.phantom_muted(), "(the Phantom too)")
	_leave_stop()
	_run(1.0)
	check_near(_sim.heavy_floor(), floor_before + floor_up, 0.000001, "and on to the leg's end")
	var guard: int = _ticks_in(120.0)
	while _sim.run.legs_done == 0 and guard > 0:
		guard -= 1
		if _sim.car.s < _sim.leg.length - 5.0:
			_sim.car.s = _sim.leg.length - 5.0
		_tick()
	check_eq(_sim.run.legs_done, 1, "(the next leg)")
	check_near(_sim.heavy_floor(), floor_before, 0.000001, "on the next leg the floor is where it was")
	check(not _sim.phantom_muted(), "and the Phantom is back")
	# What the leg held to its end is announced as over at the gore, once:
	# not at the leg's stop, which it passed through, and not begun anew there.
	for list: String in ["gives", "takes"]:
		for listed: Variant in GameData.as_array(record.get(list)):
			var entry: Dictionary = GameData.as_dict(listed)
			if GameData.as_string(entry.get("for")) != "leg":
				continue
			var status: String = GameData.as_string(entry.get("effect"))
			check_eq(_count_events("effect_added", "effect", status), 1, "(%s began once, with the first pill)" % status)
			check_eq(_count_events("effect_expired", "effect", status), 1, "the end of %s is announced once" % status)
			var ended_at: int = -1
			var left_at: int = -1
			for index: int in _events.size():
				var type: String = GameData.as_string(_events[index].get("type"))
				if type == "effect_expired" and GameData.as_string(_events[index].get("effect")) == status:
					ended_at = index
				elif type == "stop_left":
					left_at = index
			check(left_at >= 0 and ended_at > left_at, "at the gore, after the leg's stop")

	# 6 pills.
	_new_sim()
	pills = _give("painkillers")
	_reach("face")
	for _pill: int in uses:
		_hold(hold_s)
	check_eq(pills.supply, 0, "6 pills and the bottle is empty")
	_sim.nerves.set_value(20.0)
	_hold(hold_s)
	check_eq(_count_events("ritual_completed", "ritual", "painkillers_take"), uses, "an empty bottle gives nothing")
	check_near(_sim.nerves.value, 20.0, 0.000001, "and holding his hand to his face is no slap")
	_tap()
	check_near(_sim.nerves.value, 20.0 + slap_nerves, 0.000001, "(a TAP still is)")

	# Restock 15, at a fuel station.
	_to_quiet_leg("fuel_station")
	_scrape()
	_give("painkillers")
	_hold_at("face", hold_s)
	_into_stall()
	var refill: Dictionary = _offer(StopSim.RESTOCK, "painkillers")
	if check(not refill.is_empty(), "the fuel station offers to restock the pills"):
		check_near(GameData.as_float(refill["price"]), 15.0, 0.000001, "for 15")
		var cash: float = _sim.cash
		_tap_at(GameData.as_string(refill["anchor"]))
		check_near(cash - _sim.cash, 15.0, 0.000001, "a TAP pays 15")
		check_eq(_item("painkillers").supply, uses, "for a full bottle")

	# Taken in a boss, "for the leg" is until the next leg begins: through the
	# boss stop and along the road to the fork, which are no leg of their own.
	var floors: PackedFloat64Array = tuning.floats("heavy_floor")
	_to_quiet_leg("fuel_station")
	_give("painkillers")
	_drive_on_to_boss()
	var floor_in_boss: float = _sim.heavy_floor()
	_hold_at("face", hold_s)
	check_near(_sim.heavy_floor(), floor_in_boss + floor_up, 0.000001, "(a pill in the boss raises the Heavy floor by 15)")
	_drive_on_to_boss_stop()
	check_near(_sim.heavy_floor(), floor_in_boss + floor_up, 0.000001, "a pill taken in a boss holds through the boss stop")
	check(_sim.phantom_muted(), "(the Phantom stays muted there)")
	_leave_stop()
	check_eq(_sim.run.stage, RunState.Stage.APPROACH, "(the road to the next act's first fork)")
	check_near(_sim.heavy_floor(), floors[_sim.run.act - 1] + floor_up, 0.000001, "and along the road to the fork: that act's floor and the pill's 15")
	check(_sim.phantom_muted(), "(the Phantom too)")
	_into_next_quiet_leg()
	check_near(_sim.heavy_floor(), floors[_sim.run.act - 1], 0.000001, "the leg that begins at the gore ends it")
	check(not _sim.phantom_muted(), "and the Phantom is back")


# --- T-ITEM-ARAK-FLASK -------------------------------------------------------

## T-ITEM-ARAK-FLASK: Arak flask (7.4, contraband): HOLD 0.7 s sips; each
## sip is -5 Nerves and one Courage stack, up to 3, 45 s each; per stack
## +50% close-call cash and -30% Nerves gains, with Sway and 40 ms of Lag; 6
## sips, restock 20; sold only as a Deal for 45.
func test_item_arak_flask() -> void:
	var record: Dictionary = _record("arak_flask")
	var sip: Dictionary = _ritual("flask_sip")
	var hold_s: float = GameData.as_float(sip.get("hold_s"))
	var calm: float = _give_amount("arak_flask", "nerves")
	var stack_for: float = _give_duration("arak_flask", "courage")
	var courage: Dictionary = data.record("effects", "courage")
	var cap: int = GameData.as_int(courage.get("max_stacks"))
	var cash_up: float = GameData.as_float(courage.get("close_call_cash_per_stack"))
	var gain_down: float = GameData.as_float(courage.get("nerves_gain_per_stack"))
	var uses: int = GameData.as_int(_supply_spec("arak_flask").get("uses"))
	var sway: float = tuning.f("sway_per_stack")
	var sway_hz: float = tuning.f("sway_frequency")
	var lag_ms: float = tuning.f("lag_per_source")

	# The numbers of GDD 7.4, 5.4 and 5.8.
	check(GameData.as_bool(record.get("contraband")), "the arak flask is contraband")
	check_eq(GameData.as_string(record.get("kind")), "deal", "and a Deal")
	check_near(GameData.as_float(record.get("price")), 45.0, 0.000001, "for 45")
	check_eq(GameData.as_array(record.get("slots")), ["cup_a", "cup_b"], "kept in a cup holder")
	check_eq(GameData.as_string(sip.get("gesture")), "HOLD", "a sip is a HOLD")
	check_near(hold_s, 0.7, 0.000001, "of 0.7 s")
	check_near(calm, -5.0, 0.000001, "each sip is -5 Nerves")
	check_eq(cap, 3, "Courage stacks up to 3")
	check_near(stack_for, 45.0, 0.000001, "45 s each")
	check_near(cash_up, 0.5, 0.000001, "+50% close-call cash per stack")
	check_near(gain_down, -0.3, 0.000001, "-30% Nerves gains per stack")
	check_near(sway, 0.3, 0.000001, "Sway: 0.3 m/s per stack (GDD 5.4)")
	check_near(sway_hz, 0.4, 0.000001, "swinging at 0.4 Hz")
	check_near(lag_ms, 40.0, 0.000001, "40 ms of Lag per stack")
	check_eq(uses, 6, "6 sips")
	check_near(GameData.as_float(_supply_spec("arak_flask").get("restock")), 20.0, 0.000001, "restock 20")
	for stop: Dictionary in data.records("stops"):
		var pools: Array = GameData.as_array(GameData.as_dict(stop.get("stock")).get("pools"))
		check_eq(pools.has("deal"), GameData.as_string(stop.get("id")) == "shady_guy", "only the shady guy deals (%s)" % GameData.as_string(stop.get("id")))

	# A sip: HOLD 0.7 s, -5 Nerves, one Courage stack.
	_new_sim()
	var flask: ItemSim.Item = _give("arak_flask")
	var cup: String = _anchor_of("arak_flask")
	_sim.nerves.set_value(60.0)
	check(_reach(cup), "the hand reaches the flask")
	check_eq(_sim.courage(), 0, "(sober)")
	_press(_ticks_in(hold_s))
	check(flask.supply == uses and _sim.courage() == 0, "a hold one tick short of 0.7 s is no sip")
	_hold(hold_s)
	check_eq(flask.supply, uses - 1, "holding for 0.7 s is a sip")
	check_near(_sim.nerves.value, 60.0 + calm, 0.000001, "-5 Nerves")
	check_eq(_sim.courage(), 1, "and one Courage stack")
	check_near(_sim.effects.time_left(&"courage"), stack_for - float(SETTLE + 1) * DT, 0.000001, "of 45 s")
	check_eq(GameData.as_int(_sim.snapshot()["courage"]), 1, "(the snapshot counts it)")

	# Up to 3 stacks, 45 s each, each on its own clock.
	_new_sim()
	flask = _give("arak_flask")
	_reach(cup)
	var sipped_at: PackedInt32Array = PackedInt32Array()
	for index: int in 3:
		_hold(hold_s)
		sipped_at.append(_sim.tick - SETTLE - 1)
		check_eq(_sim.courage(), index + 1, "sip %d: %d stack(s)" % [index + 1, index + 1])
		_run(10.0)
	_hold(hold_s)
	var fourth_at: int = _sim.tick - SETTLE - 1
	check_eq(_sim.courage(), cap, "a fourth sip: still 3 stacks")
	check_eq(flask.supply, uses - 4, "(though it is drunk)")
	# The fourth sip renewed the oldest stack: the next to end is the second.
	var stack_ticks: int = _ticks_in(stack_for)
	_ticks(sipped_at[1] + stack_ticks - _sim.tick - 2)
	check_eq(_sim.courage(), 3, "the second sip's stack lasts its 45 s")
	_ticks(4)
	check_eq(_sim.courage(), 2, "and then ends")
	_ticks(sipped_at[2] + stack_ticks - _sim.tick - 2)
	check_eq(_sim.courage(), 2, "the third's lasts 45 s from its own sip")
	_ticks(4)
	check_eq(_sim.courage(), 1, "and ends")
	_ticks(fourth_at + stack_ticks - _sim.tick - 2)
	check_eq(_sim.courage(), 1, "the one the fourth sip renewed lasts 45 s from that sip")
	_ticks(4)
	check_eq(_sim.courage(), 0, "and then he is sober")

	# Per stack: +50% close-call cash, -30% Nerves gains.
	var base_cash: float = tuning.f("close_call_base_cash") * tuning.fi("gear_cash_mult", 2)
	var slap_nerves: float = 0.0
	for op: Variant in GameData.as_array(_ritual("slap").get("on_complete")):
		if GameData.as_string(op).begins_with("nerves:"):
			slap_nerves = GameData.as_string(op).substr(7).to_float()
	var tea_calm: float = _give_amount("tea_glass", "nerves", "hot")
	_new_sim()
	_give("arak_flask")
	for stacks: int in cap + 1:
		if stacks > 0:
			_hold_at(cup, hold_s)
		check_eq(_sim.courage(), stacks, "(%d stack(s))" % stacks)
		# (Past the chain window, so that each close call is paid on its own.)
		_run(tuning.f("chain_window") + 0.5)
		_pass_closely("truck", tuning.f("close_call_min_closing") + 10.0)
		var call: Dictionary = _event("close_call")
		check_near(GameData.as_float(call.get("mult")), 1.0, 0.000001, "(no chain)")
		check_near(GameData.as_float(call.get("cash")), base_cash * (1.0 + cash_up * float(stacks)), 0.000001, "with %d stack(s) a close call pays %s" % [stacks, str(base_cash * (1.0 + cash_up * float(stacks)))])
		var felt: float = maxf(1.0 + gain_down * float(stacks), 0.0)
		_sim.nerves.set_value(30.0)
		_tap_at("face")
		check_near(_sim.nerves.value, 30.0 + slap_nerves * felt, 0.000001, "and a slap frays him by %s" % str(slap_nerves * felt))
	check_eq(_sim.courage(), cap, "(still 3 stacks)")
	_sim.nerves.set_value(60.0)
	_hold_at("cup_a", GameData.as_float(_ritual("tea_sip").get("hold_s")))
	check_near(_sim.nerves.value, 60.0 + tea_calm, 0.000001, "what calms him is not dulled")

	# Sway: 0.3 m/s per stack, swinging at 0.4 Hz, from the first sip.
	_new_sim()
	_give("arak_flask")
	_cruise(3, 1)
	_run(1.0)
	check_near(_sim.car.drift, tuning.f("crown_drift"), 0.000001, "(sober, the car drifts with the crown only)")
	_hold_at(cup, hold_s)
	var first: float = GameData.as_float(_sim.snapshot()["sway"])
	check(first > 0.0 and first < sway * 0.1, "the Sway begins at nothing when Courage does, to the right first")
	_hold(hold_s)
	check_eq(_sim.courage(), 2, "(2 stacks)")
	var samples: PackedFloat64Array = PackedFloat64Array()
	for _index: int in _ticks_in(2.0 / sway_hz):
		_tick()
		samples.append(_sim.car.drift - tuning.f("crown_drift"))
	var most: float = 0.0
	var least: float = 0.0
	var rises: PackedInt32Array = PackedInt32Array()
	for index: int in samples.size():
		most = maxf(most, samples[index])
		least = minf(least, samples[index])
		if index > 0 and samples[index - 1] < 0.0 and samples[index] >= 0.0:
			rises.append(index)
	check_near(most, sway * 2.0, sway * 0.002, "with 2 stacks the car is pushed up to 0.6 m/s one way")
	check_near(least, -sway * 2.0, sway * 0.002, "and as much the other")
	if check(rises.size() >= 2, "(the push swings)"):
		check_near(float(rises[1] - rises[0]) * DT, 1.0 / sway_hz, DT * 1.5, "once every 2.5 s: 0.4 Hz")
	check_near(GameData.as_float(_sim.snapshot()["sway"]), samples[samples.size() - 1], 0.000001, "(the snapshot carries the push, for the rocking horizon)")
	_run(stack_for + 1.0)
	check_eq(_sim.courage(), 0, "(sober again)")
	check_near(_sim.car.drift, tuning.f("crown_drift"), 0.000001, "sober, the Sway is gone")
	_hold_at(cup, hold_s)
	var again: float = GameData.as_float(_sim.snapshot()["sway"])
	check(again > 0.0 and again < sway * 0.1, "and the next sip's Sway begins at nothing again")

	# Lag: the car is steered by where the wheel was 40 ms ago, per stack.
	for stacks: int in cap + 1:
		_new_sim()
		_give("arak_flask")
		for _sip: int in stacks:
			_hold_at(cup, hold_s)
		_cruise(3, 1)
		_grip()
		_ticks(_ticks_in(0.5))
		_input.pointer_is_absolute = false
		_input.pointer_delta = Vector2(3.0, 0.0)
		var angles: PackedFloat64Array = PackedFloat64Array()
		var worst: float = 0.0
		var behind: float = lag_ms * 0.001 * float(stacks) / DT
		var whole: int = int(floorf(behind))
		for index: int in 60:
			_tick()
			angles.append(_sim.wheel.angle)
			if index > whole + 1:
				var was: float = lerpf(angles[index - whole], angles[index - whole - 1], behind - float(whole))
				worst = maxf(worst, absf(_sim.wheel.steer() * _sim.wheel.max_angle() - was))
		check_near(worst, 0.0, 0.000000001, "with %d stack(s) the steering is the wheel's angle of %d ms ago" % [stacks, roundi(lag_ms * float(stacks))])
		check_near(GameData.as_float(_sim.snapshot()["lag"]), lag_ms * 0.001 * float(stacks), 0.000001, "(the snapshot carries the Lag)")
		if stacks > 0:
			check(_sim.wheel.steer() * _sim.wheel.max_angle() < _sim.wheel.angle - 0.1, "the car is behind the wheel he is turning")
		_release()

	# Contraband: a sip in view of a patrol.
	_begin_quiet_leg("patrol", 2, 71)
	_give("arak_flask")
	var guard: int = _ticks_in(60.0)
	while not _sim.suspicion.watching and guard > 0:
		guard -= 1
		_tick()
	_run(2.0)
	check(_sim.suspicion.watching and _sim.suspicion.value < 1.0, "(a patrol is watching and has nothing on him)")
	_hold_at(cup, hold_s)
	check_between(_sim.suspicion.value, tuning.f("suspicion_contraband") - 1.0, tuning.f("suspicion_contraband"), "a sip in its view is contraband used: Suspicion +40")

	# 6 sips.
	_new_sim()
	flask = _give("arak_flask")
	_reach(cup)
	for _sip: int in uses:
		_hold(hold_s)
	check_eq(flask.supply, 0, "6 sips empty the flask")
	_sim.nerves.set_value(60.0)
	_hold(hold_s)
	check_near(_sim.nerves.value, 60.0, 0.000001, "an empty flask gives nothing")

	# Restock 20: from the shady guy, who is there after a clean leg.
	_to_quiet_leg("fuel_station")
	_give("arak_flask")
	_hold_at(cup, hold_s)
	_into_stall()
	var refill: Dictionary = _offer(StopSim.RESTOCK, "arak_flask")
	if check(not refill.is_empty(), "after a clean leg the shady guy offers to refill the flask"):
		check(GameData.as_bool(refill["shady"]), "(it is his offer)")
		check_near(GameData.as_float(refill["price"]), 20.0, 0.000001, "for 20")
		var cash: float = _sim.cash
		var clock: float = _sim.clock.minutes
		_tap_at(GameData.as_string(refill["anchor"]))
		check_near(cash - _sim.cash, 20.0, 0.000001, "a TAP pays 20")
		check_eq(_item("arak_flask").supply, uses, "for a full flask")
		check_near(_sim.clock.minutes - clock, GameData.as_float(tuning.d("stop_minutes").get("shady")), 0.000001, "and using him costs his 5 minutes")
	_to_quiet_leg("fuel_station")
	_scrape()
	_give("arak_flask")
	_hold_at(cup, hold_s)
	_into_stall()
	check(_offer(StopSim.RESTOCK, "arak_flask").is_empty(), "the fuel station itself does not refill a flask")
	check(not _offer(StopSim.RESTOCK, "cigarettes").is_empty(), "(it restocks what is lawful)")

	# Sold only as a Deal for 45: on the shady guy's tray, some nights.
	var bought: bool = false
	for skip: int in 12:
		_to_quiet_leg("fuel_station", skip)
		_into_stall()
		var deal: Dictionary = _offer(StopSim.ITEM, "arak_flask")
		for offer: Dictionary in _offers():
			if offer["kind"] == StopSim.ITEM and not GameData.as_bool(offer["shady"]):
				check(GameData.as_string(_record(GameData.as_string(offer["id"])).get("kind")) != "deal", "the station's own shelf has no Deal on it")
		if deal.is_empty():
			continue
		check(GameData.as_bool(deal["shady"]), "the flask is the shady guy's to sell")
		check_near(GameData.as_float(deal["price"]), 45.0, 0.000001, "for 45")
		_sim.cash = 50.0
		_tap_at(GameData.as_string(deal["anchor"]))
		_drag(GameData.as_string(deal["anchor"]), "cup_b")
		check(_item("arak_flask") != null and _anchor_of("arak_flask") == "cup_b", "bought and put in a cup holder")
		check_near(_sim.cash, 5.0, 0.000001, "45 paid")
		bought = true
		break
	check(bought, "in a dozen clean first legs the shady guy has a flask at least once")


# --- T-ITEM-PHONE ------------------------------------------------------------

## T-ITEM-PHONE: Phone (7.4): a call every 25 to 40 s; three TAPs within 5 s
## of the first ring answer it, eyes-down; a dispatcher call pays 10 cash;
## one call in four is Um Noor: -8 Nerves; a missed call is +4 Nerves; using
## it in a Patrol is +30 Suspicion; price 35.
func test_item_phone() -> void:
	var record: Dictionary = _record("phone")
	var answer: Dictionary = _ritual("phone_answer")
	var params: Dictionary = _params("phone")
	var gap: Array = GameData.as_array(params.get("call_gap_s"))
	var gap_min: float = GameData.as_float(gap[0])
	var gap_max: float = GameData.as_float(gap[1])
	var ring_s: float = GameData.as_float(params.get("ring_s"))
	var taps: int = GameData.as_int(params.get("answer_taps"))
	var pay: float = GameData.as_float(params.get("dispatcher_cash"))
	var every: int = GameData.as_int(params.get("family_every"))
	var family: float = GameData.as_float(params.get("family_nerves"))
	var missed: float = GameData.as_float(params.get("missed_nerves"))

	# The numbers of GDD 7.4.
	check_eq(GameData.as_string(record.get("kind")), "habit", "the phone is a Habit")
	check_eq(GameData.as_array(record.get("slots")), ["phone_mount"], "on its mount")
	check_near(gap_min, 25.0, 0.000001, "a call every 25")
	check_near(gap_max, 40.0, 0.000001, "to 40 s")
	check_eq(GameData.as_string(answer.get("gesture")), "TAP", "answered with TAPs")
	check_eq(taps, 3, "three of them")
	check_near(ring_s, 5.0, 0.000001, "within 5 s of the first ring")
	check(GameData.as_bool(answer.get("eyes_down")), "eyes-down")
	check_near(GameData.as_float(answer.get("perform_s")), 1.2, 0.000001, "(1.2 s for a practised hand)")
	check_near(pay, 10.0, 0.000001, "a dispatcher call pays 10 cash")
	check_eq(every, 4, "one call in four is Um Noor")
	check_near(family, -8.0, 0.000001, "-8 Nerves")
	check_near(missed, 4.0, 0.000001, "a missed call is +4 Nerves")
	check_near(tuning.f("suspicion_phone"), 30.0, 0.000001, "using it in a Patrol is +30 Suspicion")
	check(not record.has("supply"), "no supply")
	check_near(GameData.as_float(record.get("price")), 35.0, 0.000001, "price 35")

	# No phone, no calls.
	_new_sim()
	_run(gap_max * 2.5)
	check_eq(_count_events("call_started"), 0, "without a phone nobody calls")

	# A call every 25 to 40 s: left to ring out, each is +4 Nerves.
	var gaps: PackedFloat64Array = _call_gaps(0, 6)
	if check_eq(gaps.size(), 6, "(six calls)"):
		var shortest: float = gaps[0]
		var longest: float = gaps[0]
		for seconds: float in gaps:
			shortest = minf(shortest, seconds)
			longest = maxf(longest, seconds)
		check(shortest >= gap_min - DT and longest <= gap_max + DT, "every call comes 25 to 40 s after the last ended (%s to %s s)" % [str(snappedf(shortest, 0.01)), str(snappedf(longest, 0.01))])
		check(longest - shortest > 1.0, "and not always after the same time")
		var rang_out: int = 0
		for event: Dictionary in _events:
			if GameData.as_string(event.get("type")) == "call_resolved" and not GameData.as_bool(event.get("answered")):
				rang_out += 1
		check_eq(rang_out, 6, "(all six rang out)")
		check_near(_sim.nerves.value, tuning.f("nerves_start") + missed * 6.0, 0.000001, "each missed call was +4 Nerves")
		check_eq(_call_gaps(0, 3), gaps.slice(0, 3), "the same Telling seed gives the same calls")
		check(_call_gaps(77, 3) != gaps.slice(0, 3), "another seed gives others")

	# Three TAPs answer it, eyes-down; a dispatcher call pays 10 cash.
	_new_sim()
	_give("phone")
	var mount: String = _anchor_of("phone")
	check_eq(mount, "phone_mount", "the phone sits on its mount")
	check(_reach(mount), "the hand rests on it")
	_tap()
	check(_sim.items.call_taps == 0 and _count_events("ritual_completed") == 0, "a silent phone has nothing to answer")
	check(_await_ring(), "it rings")
	check_eq(GameData.as_string(_event("call_started").get("caller")), "dispatcher", "the dispatcher")
	check_eq(_count_events("sfx_requested", "id", "phone_ring"), 1, "(heard as phone_ring)")
	check_eq(GameData.as_string(_sim.snapshot()["caller"]), "dispatcher", "(and in the snapshot)")
	check(not _sim.hand.eyes_down, "with his hand on it and no TAP yet his eyes are on the road")
	var cash: float = _sim.cash
	_tap()
	check(_sim.hand.eyes_down, "from the first TAP his eyes are down")
	_tap()
	check_eq(_sim.items.call_taps, taps - 1, "two TAPs")
	check(_sim.items.caller != &"" and _sim.cash == cash, "do not answer it")
	_ticks(_ticks_in(0.3))
	check(_sim.hand.eyes_down, "his eyes stay down between the TAPs")
	check_near(_sim.hand.cam_pitch, -tuning.f("eyes_down_pitch"), 2.0, "the camera pitched down at the phone")
	_tap()
	check_eq(_sim.items.caller, &"", "the third answers it")
	var resolved: Dictionary = _event("call_resolved")
	check(GameData.as_bool(resolved.get("answered")), "(announced as answered)")
	check_near(_sim.cash - cash, pay, 0.000001, "a dispatcher call pays 10 cash")
	_ticks(SETTLE)
	check(not _sim.hand.eyes_down, "and his eyes come up again")
	check_eq(_count_events("ritual_completed", "ritual", "phone_answer"), taps, "(three TAPs in all)")

	# Within 5 s of the first ring: just in time, and just too late.
	_new_sim()
	_give("phone")
	_reach(mount)
	_await_ring()
	_ticks(_ticks_in(ring_s) - 3 * (TAP_TICKS + SETTLE) - 4)
	cash = _sim.cash
	for _index: int in taps:
		_tap()
	check_near(_sim.cash - cash, pay, 0.000001, "three TAPs that end just inside 5 s answer it")
	_await_ring()
	_ticks(_ticks_in(ring_s) - 2 * (TAP_TICKS + SETTLE) - 2)
	cash = _sim.cash
	var nerves: float = _sim.nerves.value
	for _index: int in taps:
		_tap()
	check_near(_sim.cash, cash, 0.000001, "a third TAP after 5 s is too late")
	check_near(_sim.nerves.value - nerves, missed, 0.000001, "the call is missed: +4 Nerves")
	check(not GameData.as_bool(_event("call_resolved").get("answered")), "(announced as missed)")
	check(not _sim.hand.eyes_down, "and his eyes are back on the road")

	# A TAP that ends after the phone has rung out answers nothing, and to a
	# patrol that watches it is no use of the phone: the button goes down with
	# two ticks of ringing left and comes up after them. Once as the only TAP
	# of the call, once as its second.
	for tapped_in_time: bool in [false, true]:
		_begin_quiet_leg("patrol", 2, 71)
		_give("phone")
		_reach(mount)
		if not check(_await_ring() and _sim.suspicion.watching, "(a call in view of a patrol)"):
			continue
		if tapped_in_time:
			_tap()
			check_eq(_sim.items.call_taps, 1, "(one TAP in time: the phone has been seen in his hand)")
		while _sim.items.caller != &"" and _sim.items.ring_left > 2.5 * DT:
			_tick()
		var seen: float = _sim.suspicion.value
		var announced: int = _count_events("ritual_completed", "ritual", "phone_answer")
		_input.lmb = true
		_tick()
		check(_sim.gesture.is_active() and _sim.items.caller != &"", "(the TAP begins while it still rings)")
		_ticks(TAP_TICKS - 1)
		check(_sim.gesture.is_active() and _sim.items.caller == &"", "(and the ringing stops under his finger)")
		_input.lmb = false
		_ticks(SETTLE)
		check(not GameData.as_bool(_event("call_resolved").get("answered")), "the call is missed")
		check_eq(_count_events("ritual_completed", "ritual", "phone_answer"), announced, "a TAP that ends after the ringing answers nothing")
		check(_sim.suspicion.value <= seen, "and is no use of the phone: the patrol has seen nothing new (%s, then %s)" % [str(snappedf(seen, 0.01)), str(snappedf(_sim.suspicion.value, 0.01))])

	# One call in four is Um Noor: -8 Nerves.
	_new_sim()
	_give("phone")
	_reach(mount)
	var callers: PackedStringArray = PackedStringArray()
	for call: int in every + 1:
		if not _await_ring():
			break
		callers.append(String(_sim.items.caller))
		cash = _sim.cash
		_sim.nerves.set_value(50.0)
		for _index: int in taps:
			_tap()
		if (call + 1) % every == 0:
			check_near(_sim.nerves.value, 50.0 + family, 0.000001, "call %d is Um Noor: answered, -8 Nerves" % (call + 1))
			check_near(_sim.cash, cash, 0.000001, "and no cash")
		else:
			check_near(_sim.cash - cash, pay, 0.000001, "call %d is the dispatcher: 10 cash" % (call + 1))
			check_near(_sim.nerves.value, 50.0, 0.000001, "and nothing for his Nerves")
	var expected: PackedStringArray = PackedStringArray()
	for call: int in every + 1:
		expected.append("um_noor" if (call + 1) % every == 0 else "dispatcher")
	check_eq(callers, expected, "the fourth call is hers; those before and the one after are the dispatcher's")

	# Using it in a Patrol is +30 Suspicion: once for the call, not per TAP.
	_begin_quiet_leg("patrol", 2, 71)
	_give("phone")
	_reach(mount)
	if check(_await_ring(), "(a call during the patrol leg)"):
		check(_sim.suspicion.watching, "(the patrol is watching when it rings)")
		var before: float = _sim.suspicion.value
		_tap()
		check_between(_sim.suspicion.value - before, tuning.f("suspicion_phone") - 1.0, tuning.f("suspicion_phone"), "the phone in his hand in view of a patrol: Suspicion +30")
		before = _sim.suspicion.value
		_tap()
		_tap()
		check(_sim.items.caller == &"" and _sim.suspicion.value <= before, "the other TAPs of the same call add nothing")

	# "Every 25 to 40 s" is of the road: a stop does not start the wait for
	# the next call again, and no call comes in while he stands there.
	var road_gap: int = _ticks_to_next_ring(false)
	var stop_gap: int = _ticks_to_next_ring(true)
	check(road_gap >= _ticks_in(gap_min) and road_gap <= _ticks_in(gap_max) + 1, "(with no stop the next call comes 25 to 40 s after the last was answered: %s s)" % str(snappedf(float(road_gap) * DT, 0.01)))
	check_eq(stop_gap, road_gap, "with a stop on the way it comes after the same seconds of road: the wait passes through the stop")

	# A call still ringing when he pulls in is dropped: unanswered, and at no
	# cost to his Nerves or to his row of answered calls. It is announced.
	_to_quiet_leg("fuel_station")
	_give("phone")
	_reach(mount)
	_await_ring()
	for _index: int in taps:
		_tap()
	check_eq(_sim.items.answered_run, 1, "(one call answered)")
	_input.rmb = true
	check(_await_ring(), "(the next one rings, and he pulls in with it ringing)")
	_events = []
	var nerves_ringing: float = _sim.nerves.value
	_into_stall()
	check_eq(_sim.items.caller, &"", "at the stop the phone is silent")
	check_eq(_count_events("call_resolved"), 1, "the call that was ringing is announced as over")
	var dropped: Dictionary = _event("call_resolved")
	check(not GameData.as_bool(dropped.get("answered")) and GameData.as_bool(dropped.get("dropped")), "unanswered: dropped")
	check_near(GameData.as_float(dropped.get("nerves")), 0.0, 0.000001, "at no cost")
	# (But for the tick the slip lane takes to open under him: a tick of rough shoulder.)
	check_near(_sim.nerves.value, nerves_ringing, tuning.f("shoulder_nerves_rate") * DT * 1.5, "his Nerves are what they were (a missed call would be +4)")
	check_eq(_sim.items.answered_run, 1, "and his row of answered calls stands")
	check(_events.find(dropped) < _events.find(_event("stop_entered")), "(announced before the stop is)")
	_leave_stop()
	_input.rmb = true
	var left_at: int = _sim.tick
	check(_await_ring(), "(the phone rings again down the road)")
	check_between(float(_sim.tick - left_at) * DT, gap_min - 2.0 * DT, gap_max + 2.0 * DT, "the wait for the next call is counted from the end of the one the stop dropped")


# --- T-ITEM-BREATH-MINTS -----------------------------------------------------

## T-ITEM-BREATH-MINTS: Breath mints (7.4): TAP 0.3 s; police ignore Courage
## for 60 s; 5 mints, restock 5; price 15.
func test_item_breath_mints() -> void:
	var record: Dictionary = _record("breath_mints")
	var take: Dictionary = _ritual("mints_take")
	var minty_for: float = _give_duration("breath_mints", "minty")
	var uses: int = GameData.as_int(_supply_spec("breath_mints").get("uses"))
	var sip_s: float = GameData.as_float(_ritual("flask_sip").get("hold_s"))

	# The numbers of GDD 7.4.
	check_eq(GameData.as_string(record.get("kind")), "habit", "breath mints are a Habit")
	check_eq(GameData.as_array(record.get("slots")), ["dash_1", "dash_2"], "kept on the dash")
	check_eq(GameData.as_string(take.get("gesture")), "TAP", "one is a TAP")
	check_near(GameData.as_float(take.get("perform_s")), 0.3, 0.000001, "of 0.3 s")
	check_near(minty_for, 60.0, 0.000001, "it works for 60 s")
	check(GameData.as_bool(data.record("effects", "minty").get("hides_courage")), "and hides Courage")
	check_eq(uses, 5, "5 mints")
	check_near(GameData.as_float(_supply_spec("breath_mints").get("restock")), 5.0, 0.000001, "restock 5")
	check_near(GameData.as_float(record.get("price")), 15.0, 0.000001, "price 15")

	# Police ignore Courage for 60 s.
	_new_sim()
	var mints: ItemSim.Item = _give("breath_mints")
	var dash: String = _anchor_of("breath_mints")
	_give("arak_flask")
	var cup: String = _anchor_of("arak_flask")
	check_eq(_sim.courage_noticed(), 0, "(sober, there is no Courage to notice)")
	_hold_at(cup, sip_s)
	_hold(sip_s)
	check_eq(_sim.courage(), 2, "(two sips: 2 stacks)")
	check_eq(_sim.courage_noticed(), 2, "a policeman would notice both")
	_reach(dash)
	_press(_ticks_in(tuning.f("tap_max_time")) + 6)
	check(mints.supply == uses and _sim.courage_noticed() == 2, "a press longer than a TAP takes no mint")
	_tap()
	check_eq(mints.supply, uses - 1, "a TAP takes one")
	check_eq(_sim.courage_noticed(), 0, "and the police ignore his Courage")
	check_eq(_sim.courage(), 2, "which is still there, with all it does")
	check_near(_sim.effects.time_left(&"minty"), minty_for - float(SETTLE) * DT, 0.000001, "for 60 s")
	# Keep some Courage going past the mint's end: a sip 30 s in.
	_run(30.0)
	_hold_at(cup, sip_s)
	_run(_sim.effects.time_left(&"minty") - 0.5)
	check(_sim.courage() > 0 and _sim.courage_noticed() == 0, "just short of 60 s they still ignore it")
	_run(1.0)
	check(_sim.courage() > 0, "(he still has Courage)")
	check_eq(_sim.courage_noticed(), _sim.courage(), "after 60 s they notice it again")

	# At the Checkpoint itself (GDD 10.2): the soldier who comes to his window
	# counts each stack of Courage, unless a mint hides it.
	var per_stack: float = GameData.as_float(GameData.as_dict(data.record("bosses", BossSim.CHECKPOINT).get("checkpoint")).get("courage_suspicion"))
	for minted: bool in [false, true]:
		_begin_checkpoint("", 1, false)
		_give("breath_mints")
		var flask: ItemSim.Item = _give("arak_flask")
		_hold_at(_anchor_of("arak_flask"), sip_s)
		_hold(sip_s)
		check_eq(_sim.courage(), 2, "(two sips before the Checkpoint)")
		# The flask itself is put out of sight: only his breath is left to tell.
		flask.slot = &"glovebox_a"
		check(_stand_at_the_bar(), "(first in line at the Checkpoint)")
		if minted:
			_tap_at(_anchor_of("breath_mints"))
			check(_sim.effects.has(&"minty"), "(a mint, while the soldier walks up)")
		check(_until_checkpoint_phase(BossSim.PAPERS, 11.0), "(the soldier is at the window)")
		if minted:
			check_near(_sim.suspicion.value, 0.0, 0.000001, "at the Checkpoint, with a mint, the soldier does not count his Courage")
		else:
			check_near(_sim.suspicion.value, per_stack * 2.0, 0.000001, "at the Checkpoint, without one, each stack is +15 Suspicion")

	# 5 mints.
	_new_sim()
	mints = _give("breath_mints")
	_reach(dash)
	for _mint: int in uses:
		_tap()
	check_eq(mints.supply, 0, "5 mints and the tin is empty")
	_run(minty_for + 1.0)
	_tap()
	check(not _sim.effects.has(&"minty"), "an empty tin gives nothing")

	# Restock 5, at a fuel station.
	_to_quiet_leg("fuel_station")
	_scrape()
	_give("breath_mints")
	_tap_at(dash)
	_into_stall()
	var refill: Dictionary = _offer(StopSim.RESTOCK, "breath_mints")
	if check(not refill.is_empty(), "the fuel station offers to restock the mints"):
		check_near(GameData.as_float(refill["price"]), 5.0, 0.000001, "for 5")
		var cash: float = _sim.cash
		_tap_at(GameData.as_string(refill["anchor"]))
		check_near(cash - _sim.cash, 5.0, 0.000001, "a TAP pays 5")
		check_eq(_item("breath_mints").supply, uses, "for a full tin")


# --- Helpers -----------------------------------------------------------------

## One second in third gear with a truck on the road and nobody steering:
## how far the car and the truck go and how far the car is carried sideways;
## how many ticks the hand takes from the wheel to the glovebox; how far a
## gripped wheel turns for a given pull; what the Clock and the leg's clock count.
func _a_second_of_road() -> Dictionary:
	_cruise(3, 1)
	_sim.traffic.clear()
	var truck: TrafficSim.Vehicle = _sim.traffic.spawn(&"truck", 0, _sim.car.s + 200.0, 60.0)
	_input.clear()
	_keep_lane = false
	var car_from: float = _sim.car.s
	var truck_from: float = truck.s
	var x_from: float = _sim.car.x
	var clock_from: float = _sim.clock.minutes
	var leg_from: float = _sim.leg.time
	for _index: int in DriveSim.TICKS_PER_SECOND:
		_sim.step(_input)
	var out: Dictionary = {
		"car": _sim.car.s - car_from,
		"truck": truck.s - truck_from,
		"sideways": _sim.car.x - x_from,
		"clock": _sim.clock.minutes - clock_from,
		"leg_time": _sim.leg.time - leg_from,
	}
	_keep_lane = true
	# The hand: from the wheel to the glovebox.
	_grip()
	_release()
	var from_tick: int = _sim.tick
	_reach("glovebox")
	out["reach_ticks"] = _sim.tick - from_tick
	# The wheel: a pull of 100 pixels, and where it is three ticks later
	# (still on its way: wheel_smoothing is longer than that).
	_grip()
	_ticks(_ticks_in(0.5))
	var angle_from: float = _sim.wheel.angle
	_input.pointer_is_absolute = false
	_input.pointer_delta = Vector2(100.0, 0.0)
	_tick()
	_input.pointer_delta = Vector2.ZERO
	_ticks(3)
	out["wheel"] = _sim.wheel.angle - angle_from
	_release()
	_sim.wheel.reset()
	_sim.traffic.clear()
	return out


## One gust toward the right shoulder in third gear with nobody steering,
## watched for `seconds`: the ticks of his time it pushes the car for, and how
## far it carries it (against the same stretch driven without a gust).
func _a_gust(seconds: float) -> Dictionary:
	var crown: float = tuning.f("crown_drift")
	var pushed: int = 0
	var sideways: PackedFloat64Array = PackedFloat64Array()
	_input.clear()
	_keep_lane = false
	for gusty: bool in [false, true]:
		_cruise(3, 1)
		if gusty:
			_sim.start_gust(1)
		var x_from: float = _sim.car.x
		for _index: int in _ticks_in(seconds):
			_sim.step(_input)
			if _sim.car.drift > crown + tuning.f("gust_push") * 0.5:
				pushed += 1
		sideways.append(_sim.car.x - x_from)
	_keep_lane = true
	_cruise(3, 1)
	return {"ticks": pushed, "carried": sideways[1] - sideways[0]}


## Steps until the phone rings (at most a little over the longest gap).
func _await_ring() -> bool:
	var guard: int = _ticks_in(GameData.as_float(GameData.as_array(_params("phone").get("call_gap_s"))[1]) + 10.0)
	while _sim.items.caller == &"" and guard > 0:
		guard -= 1
		_tick()
	return _sim.items.caller != &""


## A Telling's first leg with a phone: the first call is answered, and then
## he waits for the next with his foot on the brake. Returns the ticks of
## road (ticks in which the night went on) from the answer to the next ring.
## With `stops`, he pulls into the leg's stop part of the way through the
## wait and stands there longer than any wait lasts.
func _ticks_to_next_ring(stops: bool) -> int:
	var params: Dictionary = _params("phone")
	var gap: Array = GameData.as_array(params.get("call_gap_s"))
	_to_quiet_leg("fuel_station")
	_give("phone")
	_reach(_anchor_of("phone"))
	if not check(_await_ring(), "(a first call)"):
		return -1
	for _index: int in GameData.as_int(params.get("answer_taps")):
		_tap()
	check_eq(_sim.items.answered_run, 1, "(answered)")
	var answered_at: int = _sim.tick
	var stood: int = 0
	_input.rmb = true
	if stops:
		_run(GameData.as_float(gap[0]) * 0.4)
		check_eq(_sim.items.caller, &"", "(the next call has not come when he pulls in)")
		_into_stall()
		var entered_at: int = _sim.tick
		_events = []
		_run(GameData.as_float(gap[1]) + GameData.as_float(params.get("ring_s")))
		check_eq(_count_events("call_started"), 0, "no call comes in while he stands at a stop")
		_leave_stop()
		# (Every tick since he stopped but the last, which is of the road again.)
		stood = _sim.tick - entered_at - 1
		_input.rmb = true
	if not check(_await_ring(), "(the next call)"):
		return -1
	return _sim.tick - answered_at - stood


## A new simulation on a Telling seed with a phone and nobody answering it:
## the seconds from the end of each call (or from the start) to the next ring.
func _call_gaps(telling_seed: int, count: int) -> PackedFloat64Array:
	_new_sim()
	_sim.reseed(telling_seed)
	_give("phone")
	var gaps: PackedFloat64Array = PackedFloat64Array()
	var since: int = _sim.tick
	for _call: int in count:
		if not _await_ring():
			break
		# (The ring is announced on the tick it begins.)
		gaps.append(float(_sim.tick - since) * DT)
		while _sim.items.caller != &"":
			_tick()
		since = _sim.tick
	return gaps


## A taxi passed closely, too slowly for a close call: the change in his
## Nerves over the pass.
func _pass_a_taxi_closely() -> float:
	return _pass_closely("taxi", tuning.f("close_call_min_closing") * 0.6)


## The supply an item has in the starting cabin (GDD 7.3).
func _starting_supply(item_id: String) -> int:
	for entry: Variant in GameData.as_array(data.root("items").get("starting_cabin")):
		var start: Dictionary = GameData.as_dict(entry)
		if GameData.as_string(start.get("item")) == item_id:
			return GameData.as_int(start.get("supply"), -1)
	return -1


## A Telling's first leg driven to a fuel station that sells `item_id`: the
## first of forty Tellings whose first stop is one and has it on the tray.
## Returns the offer; {} when none of them sells it.
func _to_fuel_station_selling(item_id: String) -> Dictionary:
	for skip: int in 40:
		_to_quiet_leg("fuel_station", skip)
		_scrape()
		_into_stall()
		var sold: Dictionary = _offer(StopSim.ITEM, item_id)
		if not sold.is_empty():
			return sold
	return {}
