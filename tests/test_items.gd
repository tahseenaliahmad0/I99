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


# --- Helpers -----------------------------------------------------------------

## A taxi passed closely, too slowly for a close call: the change in his
## Nerves over the pass.
func _pass_a_taxi_closely() -> float:
	_cruise(3, 1)
	_keep_lane = false
	var speed: float = tuning.fi("gear_speeds", 2)
	var taxi: TrafficSim.Vehicle = _sim.traffic.spawn(&"taxi", 0, _sim.car.s + 12.0, speed - tuning.f("close_call_min_closing") * 0.6)
	var beside: float = taxi.x + taxi.half_width + _sim.car.half_width() + tuning.f("close_call_gap") * 0.5
	_events = []
	var before: float = _sim.nerves.value
	var guard: int = _ticks_in(20.0)
	while _sim.car.s < taxi.s + 12.0 and guard > 0:
		guard -= 1
		_sim.car.x = beside
		_tick()
	_keep_lane = true
	return _sim.nerves.value - before


## The supply an item has in the starting cabin (GDD 7.3).
func _starting_supply(item_id: String) -> int:
	for entry: Variant in GameData.as_array(data.root("items").get("starting_cabin")):
		var start: Dictionary = GameData.as_dict(entry)
		if GameData.as_string(start.get("item")) == item_id:
			return GameData.as_int(start.get("supply"), -1)
	return -1
