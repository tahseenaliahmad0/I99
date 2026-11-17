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


# --- Helpers -----------------------------------------------------------------

## The supply an item has in the starting cabin (GDD 7.3).
func _starting_supply(item_id: String) -> int:
	for entry: Variant in GameData.as_array(data.root("items").get("starting_cabin")):
		var start: Dictionary = GameData.as_dict(entry)
		if GameData.as_string(start.get("item")) == item_id:
			return GameData.as_int(start.get("supply"), -1)
	return -1
