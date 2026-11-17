extends CabinSuite
## M6: the Adaptations of GDD 7.6: real one-handed driving equipment, fitted
## into the car's three bays.

const BAYS: Array = ["bay_1", "bay_2", "bay_3"]


# --- T-ITEM-CROSSOVER-STALK --------------------------------------------------

## T-ITEM-CROSSOVER-STALK: Crossover stalk (7.6): the indicator moves to the
## right of the column, reach 0.10 s instead of 0.41 s; takes a bay; price 40.
func test_item_crossover_stalk() -> void:
	var record: Dictionary = _record("crossover_stalk")
	_check_adaptation("crossover_stalk", 40.0)
	check_near(GameData.as_float(data.record("anchors", "indicator_stalk").get("time_s")), 0.41, 0.000001, "(GDD 4.6: the indicator is 0.41 s away, a cross-reach)")
	check_eq(GameData.as_string(_params("crossover_stalk").get("moves_anchor")), "indicator_stalk", "the stalk moves the indicator")

	# Without it: left of the column, 0.41 s.
	_new_sim()
	var stalk: int = _sim.hand.anchor_index(&"indicator_stalk")
	check(_sim.hand.anchor_position(stalk).x < 0.0, "(the indicator is left of the column)")
	check_near(_reach_time("indicator_stalk"), 0.41, 0.02, "(and 0.41 s from the wheel)")

	# With it: right of the column, 0.10 s.
	_new_sim()
	var fitted: ItemSim.Item = _give("crossover_stalk")
	check(BAYS.has(String(fitted.slot)), "it takes a bay")
	check(_sim.hand.anchor_position(stalk).x > 0.0, "with the crossover stalk the indicator is right of the column")
	check_near(_reach_time("indicator_stalk"), 0.10, 0.02, "0.10 s from the wheel")
	var moves: Dictionary = _sim.snapshot()["anchor_moves"]
	check(moves.has("indicator_stalk"), "(the snapshot says where it is now)")
	# It is still the indicator: up for right, down for left.
	_flick(Vector2(0.0, -tuning.f("flick_min_distance") * 1.5))
	check_eq(_sim.items.indicator, 1, "a FLICK up there indicates right")
	_ticks(SETTLE)
	_flick(Vector2(0.0, tuning.f("flick_min_distance") * 1.5))
	check_eq(_sim.items.indicator, -1, "a FLICK down, left")
	# Taken out again, the indicator is back where it was.
	_sim.items.remove_item(_item("crossover_stalk"))
	_tick()
	check(_sim.hand.anchor_position(stalk).x < 0.0, "without it the indicator is back on the left")

	# Takes a bay: with all three taken the fitter cannot fit another.
	_to_quiet_leg("fitter")
	_scrape()
	_give("spinner_knob")
	_give("bull_bar")
	_give("fog_lamps")
	_into_stall()
	var offered: Dictionary = {}
	for offer: Dictionary in _offers():
		if offer["kind"] == StopSim.ITEM and GameData.as_string(_record(GameData.as_string(offer["id"])).get("kind")) == "adaptation":
			offered = offer
	if check(not offered.is_empty(), "(the fitter has an Adaptation for sale)"):
		_sim.cash = 200.0
		_tap_at(GameData.as_string(offered["anchor"]))
		check_near(_sim.cash, 200.0, 0.000001, "with three bays taken a fourth Adaptation cannot be bought")
		check(_item(GameData.as_string(offered["id"])) == null, "and is not fitted")


# --- T-ITEM-WINDOW-SWITCH ----------------------------------------------------

## T-ITEM-WINDOW-SWITCH: Console window switch (7.6): the window opens with
## HOLD 0.6 s at a Near anchor instead of a cross-reach and three turns;
## takes a bay; price 35.
func test_item_window_switch() -> void:
	var hold: Dictionary = _ritual("window_switch_hold")
	var hold_s: float = GameData.as_float(hold.get("hold_s"))
	var anchor: String = GameData.as_string(hold.get("anchor"))
	_check_adaptation("window_switch", 35.0)
	check_eq(GameData.as_string(hold.get("gesture")), "HOLD", "the switch is a HOLD")
	check_near(hold_s, 0.6, 0.000001, "of 0.6 s")
	# Near: no further than the furthest Near slot of GDD 7.1.
	var near: float = 0.0
	for slot: Dictionary in data.records("slots"):
		if GameData.as_string(slot.get("reach")) == "near":
			near = maxf(near, GameData.as_float(data.record("anchors", GameData.as_string(slot.get("anchor"))).get("time_s")))
	var away: float = GameData.as_float(data.record("anchors", anchor).get("time_s"))
	check(away <= near + 0.000001, "at a Near anchor (%s s; the furthest Near slot is %s s)" % [str(away), str(near)])
	check(GameData.as_vec3(data.record("anchors", anchor).get("pos")).x > 0.0, "on his side of the column: no cross-reach")
	check_eq(GameData.as_string(_ritual("window_crank").get("gesture")), "CRANK", "(the crank is a CRANK")
	check_near(GameData.as_float(_ritual("window_crank").get("turns")), 3.0, 0.000001, "of three turns)")

	# Without it there is no switch.
	_new_sim()
	check(not _sim.hand.is_anchor_active(_sim.hand.anchor_index(StringName(anchor))), "without the Adaptation there is no switch to reach")

	# With it: HOLD 0.6 s opens the window.
	_new_sim()
	var fitted: ItemSim.Item = _give("window_switch")
	check(BAYS.has(String(fitted.slot)), "it takes a bay")
	check_near(_reach_time(anchor), away, 0.02, "the switch is a Near reach from the wheel")
	check(_reach_time("window_crank") > away * 3.0, "(the crank is more than three times as far)")
	_reach(anchor)
	_press(_ticks_in(hold_s))
	check(not _sim.items.flag(&"window_open"), "a hold one tick short of 0.6 s opens nothing")
	_hold(hold_s)
	check(_sim.items.flag(&"window_open"), "holding the switch for 0.6 s opens the window")
	check_near(_sim.effects.time_left(&"awake"), tuning.f("window_awake") - float(SETTLE + 1) * DT, 0.000001, "with the Awake an opened window gives")
	_hold(hold_s)
	check(not _sim.items.flag(&"window_open"), "and again closes it")
	check_eq(_count_events("ritual_completed", "ritual", "window_switch_hold"), 2, "(twice the switch)")


# --- T-ITEM-SPINNER-KNOB -----------------------------------------------------

## T-ITEM-SPINNER-KNOB: Spinner knob (7.6): the wheel turns 40% faster per
## pixel; self-centring is halved; takes a bay; price 50.
func test_item_spinner_knob() -> void:
	_check_adaptation("spinner_knob", 50.0)
	check_near(_passive("spinner_knob", "turn_rate_mult"), 1.4, 0.000001, "the wheel turns 40% faster per pixel")
	check_near(_passive("spinner_knob", "return_rate_mult"), 0.5, 0.000001, "self-centring is halved")

	var plain: Vector2 = _turn_and_let_go()
	check_near(plain.x, 100.0 * tuning.f("steer_deg_per_px"), 0.000001, "(without it 100 pixels turn the wheel 35 degrees)")
	check_near(plain.y, tuning.f("wheel_return_rate") * 0.1, 0.000001, "(and let go it returns at 200 degrees a second)")
	_new_sim()
	var fitted: ItemSim.Item = _give("spinner_knob")
	check(BAYS.has(String(fitted.slot)), "it takes a bay")
	var spun: Vector2 = _turn_and_let_go(false)
	check_near(spun.x, plain.x * 1.4, 0.000001, "with the knob the same 100 pixels turn it 40% further")
	check_near(spun.y, plain.y * 0.5, 0.000001, "and let go it returns half as fast")


# --- T-ITEM-WHEEL-RING -------------------------------------------------------

## T-ITEM-WHEEL-RING: Wheel ring (7.6): the hook hangs at the wheel; setting
## it (TAP, 0.3 s) locks the wheel at its current angle for up to 4 s, then
## a 6 s cooldown; it locks the angle, not the lane, so drift still applies;
## takes a bay; price 60.
func test_item_wheel_ring() -> void:
	var arm: Dictionary = _ritual("hook_arm")
	var lock_s: float = _passive("wheel_ring", "hook_lock_s")
	var cooldown: float = _passive("wheel_ring", "hook_cooldown_s")
	_check_adaptation("wheel_ring", 60.0)
	check_eq(GameData.as_string(arm.get("gesture")), "TAP", "setting the hook is a TAP")
	check_near(GameData.as_float(arm.get("perform_s")), 0.3, 0.000001, "of 0.3 s")
	check_near(lock_s, 4.0, 0.000001, "it locks the wheel for up to 4 s")
	check_near(cooldown, 6.0, 0.000001, "then a 6 s cooldown")
	var hook: Vector3 = GameData.as_vec3(data.record("anchors", "hook").get("pos"))
	check(Vector2(hook.x, hook.y).length() < tuning.f("wheel_radius") - tuning.f("grip_zone_half_width") and absf(hook.z) < 0.01, "the hook hangs at the wheel: inside its rim")

	# Without the ring there is no hook there, and a wheel let go returns.
	_new_sim()
	check(not _sim.hand.is_anchor_active(_sim.hand.anchor_index(&"hook")), "without the ring there is no hook at the wheel")
	_cruise(3, 1)
	_grip()
	_steer(90.0)
	_ticks(_ticks_in(0.5))
	var held: float = _sim.wheel.angle
	check(held > 25.0, "(the wheel is turned)")
	_release()
	_ticks(_ticks_in(0.5))
	check_near(_sim.wheel.angle, 0.0, 0.000001, "(let go, it returns to centre)")

	# Set, the hook locks the wheel at the angle it has when he lets go.
	_new_sim()
	var fitted: ItemSim.Item = _give("wheel_ring")
	check(BAYS.has(String(fitted.slot)), "it takes a bay")
	_cruise(3, 1)
	_tap_at("hook")
	check_eq(GameData.as_string(_sim.snapshot()["hook"]), "armed", "a TAP at the hook sets it")
	check_eq(_count_events("ritual_completed", "ritual", "hook_arm"), 1, "(once)")
	_tap()
	check_eq(_count_events("ritual_completed", "ritual", "hook_arm"), 1, "set, it cannot be set again")
	_grip()
	_steer(90.0)
	_ticks(_ticks_in(0.5))
	held = _sim.wheel.angle
	check(held > 25.0, "(he turns the wheel)")
	_input.clear()
	_tick()
	var let_go_tick: int = _sim.tick
	check_eq(GameData.as_string(_sim.snapshot()["hook"]), "set", "as he lets go the hook takes the wheel")
	_ticks(_ticks_in(lock_s) - 3)
	check_near(_sim.wheel.angle, held, 0.000001, "and holds it at that angle for 4 s")
	_ticks(6)
	check(_sim.wheel.angle < held, "after 4 s the wheel is free and returns")
	check_eq(GameData.as_string(_sim.snapshot()["hook"]), "cooling", "and the hook is out of its ring")
	check(_sim.tick - let_go_tick >= _ticks_in(lock_s), "(4 s on)")

	# The cooldown: 6 s before it can be set again.
	var free_tick: int = let_go_tick + _ticks_in(lock_s)
	_tap_at("hook")
	check_eq(_count_events("ritual_completed", "ritual", "hook_arm"), 1, "inside the cooldown a TAP sets nothing")
	_reach("hook")
	_ticks(free_tick + _ticks_in(cooldown) - _sim.tick - 3)
	_tap()
	check_eq(_count_events("ritual_completed", "ritual", "hook_arm"), 1, "just short of 6 s still nothing")
	_ticks(8)
	_tap()
	check_eq(_count_events("ritual_completed", "ritual", "hook_arm"), 2, "after 6 s it can be set again")

	# Up to 4 s: his hand back on the wheel ends it at once.
	_grip()
	_steer(90.0)
	_ticks(_ticks_in(0.5))
	_input.clear()
	_ticks(_ticks_in(1.0))
	check_eq(GameData.as_string(_sim.snapshot()["hook"]), "set", "(the hook holds)")
	_grip()
	check_eq(GameData.as_string(_sim.snapshot()["hook"]), "cooling", "taking the wheel again takes it off the hook, and the cooldown begins")
	_steer(-200.0)
	_ticks(_ticks_in(0.5))
	check(_sim.wheel.angle < 0.0, "the wheel follows his hand again")
	_release()

	# It locks the angle, not the lane: drift still applies.
	_new_sim()
	_give("wheel_ring")
	_cruise(3, 1)
	_run(1.0)
	_tap_at("hook")
	_grip()
	_ticks(_ticks_in(0.3))
	_input.clear()
	_tick()
	check_eq(GameData.as_string(_sim.snapshot()["hook"]), "set", "(the hook holds a straight wheel)")
	check_near(_sim.wheel.angle, 0.0, 0.01, "(at centre)")
	_keep_lane = false
	var x_from: float = _sim.car.x
	_ticks(_ticks_in(2.0))
	_keep_lane = true
	check_near(_sim.car.x - x_from, tuning.f("crown_drift") * 2.0, 0.01, "the wheel is held and the car still drifts with the crown: the angle is locked, not the lane")

	# Set and not yet used, it waits.
	_new_sim()
	_give("wheel_ring")
	_tap_at("hook")
	_run(30.0)
	check_eq(GameData.as_string(_sim.snapshot()["hook"]), "armed", "set and not yet needed, the hook waits in its ring")


# --- T-ITEM-THUMB-KEYPAD -----------------------------------------------------

## T-ITEM-THUMB-KEYPAD: Thumb keypad (7.6): horn and wipers work while
## gripping, by middle click and scroll; takes a bay; price 55.
func test_item_thumb_keypad() -> void:
	_check_adaptation("thumb_keypad", 55.0)
	# Middle click and scroll.
	var horn_buttons: Array[int] = _mouse_buttons("pad_horn")
	var wiper_buttons: Array[int] = _mouse_buttons("pad_wiper")
	check_eq(horn_buttons, [MOUSE_BUTTON_MIDDLE], "the horn key is the middle click")
	check(wiper_buttons.has(MOUSE_BUTTON_WHEEL_UP) and wiper_buttons.has(MOUSE_BUTTON_WHEEL_DOWN), "the wiper key is the scroll wheel, either way")

	# Without the keypad the keys do nothing.
	_new_sim()
	_cruise(3, 1)
	_sim.items.raining = true
	_run(1.0)
	_grip()
	_ticks(SETTLE)
	var nerves: float = _sim.nerves.value
	_input.pad_horn = true
	_input.pad_wiper = true
	_ticks(3)
	_input.pad_horn = false
	_input.pad_wiper = false
	_ticks(SETTLE)
	check_near(_sim.nerves.value, nerves, 0.000001, "without the keypad the horn key does nothing")
	check(_sim.items.rain_blur() > 0.1, "nor the wiper key")

	# With it, while gripping: the horn.
	_new_sim()
	var fitted: ItemSim.Item = _give("thumb_keypad")
	check(BAYS.has(String(fitted.slot)), "it takes a bay")
	_cruise(3, 1)
	_sim.items.raining = true
	_run(1.0)
	var ahead: TrafficSim.Vehicle = _sim.traffic.spawn(&"car", 1, _sim.car.s + tuning.f("horn_range") * 0.5, tuning.fi("gear_speeds", 2))
	_grip()
	_ticks(SETTLE)
	check(_sim.hand.gripping, "(he grips the wheel)")
	nerves = _sim.nerves.value
	var ambient: float = tuning.f("traffic_rate")
	_input.pad_horn = true
	_tick()
	check(_sim.items.horn_blown, "gripping, the horn key blows the horn")
	check_near(_sim.nerves.value - nerves, tuning.f("horn_nerves"), ambient * DT * 2.0, "with the horn's -3 Nerves")
	_ticks(_ticks_in(0.5))
	check_eq(_count_events("ritual_completed", "ritual", "horn"), 1, "a key held down is one honk")
	_input.pad_horn = false
	_ticks(_ticks_in(tuning.f("horn_yield_time") + 0.2))
	check(ahead.lane != 1, "and the car ahead moves over, as for any honk")
	check(_sim.hand.gripping, "his hand never left the wheel")
	# The wipers.
	check(_sim.items.rain_blur() > 0.1, "(rain has blurred the view)")
	_input.pad_wiper = true
	_tick()
	_input.pad_wiper = false
	check_near(_sim.items.rain_blur(), 0.0, 0.01, "gripping, the wiper key is one sweep")
	check_eq(_count_events("ritual_completed", "ritual", "wipers"), 1, "(announced)")

	# Not gripping, the keys do nothing: they are under the thumb that holds the wheel.
	_release()
	_run(tuning.f("horn_cooldown"))
	nerves = _sim.nerves.value
	var blur: float = _sim.items.rain_blur()
	_sim.traffic.clear()
	_input.pad_horn = true
	_input.pad_wiper = true
	_ticks(3)
	_input.pad_horn = false
	_input.pad_wiper = false
	check_near(_sim.nerves.value, nerves, 0.000001, "hand off the wheel, the horn key does nothing")
	check(_sim.items.rain_blur() >= blur, "nor the wiper key")


# --- T-ITEM-FIFTH-GEAR -------------------------------------------------------

## T-ITEM-FIFTH-GEAR: Fifth gear (7.6): unlocks gear 5 in the gate (160
## km/h, close-call cash x3); takes a bay; price 60.
func test_item_fifth_gear() -> void:
	_check_adaptation("fifth_gear", 60.0)
	check_near(tuning.fi("gear_speeds", 4), 160.0, 0.000001, "gear 5 is 160 km/h")
	check_near(tuning.fi("gear_cash_mult", 4), 3.0, 0.000001, "with close-call cash x3")

	# Without it gear 5 is walled off.
	_new_sim()
	_to_fifth()
	check(_sim.gate.gear != 5, "without the Adaptation the gate has no fifth gear")
	check(_sim.gate.lever.x < 0.5, "the lever does not go into its column")

	# With it: through the gate into fifth.
	_new_sim()
	var fitted: ItemSim.Item = _give("fifth_gear")
	check(BAYS.has(String(fitted.slot)), "it takes a bay")
	_to_fifth()
	check_eq(_sim.gate.gear, 5, "with it the lever goes right and forward into fifth")
	_input.clear()
	_run((tuning.fi("gear_speeds", 4) - tuning.fi("gear_speeds", 0)) / tuning.f("accel") + 1.0)
	check_near(_sim.car.speed, 160.0, 0.000001, "and the car climbs to 160 km/h")
	# Close-call cash x3.
	var slow: TrafficSim.Vehicle = _sim.traffic.spawn(&"truck", 0, _sim.car.s + 40.0, 60.0)
	var beside: float = slow.x + slow.half_width + _sim.car.half_width() + tuning.f("close_call_gap") * 0.5
	_keep_lane = false
	_events = []
	var guard: int = _ticks_in(20.0)
	while _sim.car.s < slow.s + slow.half_length + 10.0 and guard > 0:
		guard -= 1
		_sim.car.x = beside
		_tick()
	_keep_lane = true
	check_near(GameData.as_float(_event("close_call").get("cash")), tuning.f("close_call_base_cash") * 3.0, 0.000001, "where a close call pays three times the base")
	# The assist's sequential shifting reaches it too.
	_new_sim()
	_give("fifth_gear")
	_sim.gate.reset(4)
	check(_sim.gate.shift_sequential(1) and _sim.gate.gear == 5, "sequential shifting goes up from fourth into fifth")
	_new_sim()
	_sim.gate.reset(4)
	check(not _sim.gate.shift_sequential(1) and _sim.gate.gear == 4, "and without the Adaptation stops at fourth")


# --- T-ITEM-LOUD-HORN --------------------------------------------------------

## T-ITEM-LOUD-HORN: Loud horn (7.6): every vehicle yields and the horn
## gives -5 Nerves; +15 extra Suspicion per honk; takes a bay; price 45.
func test_item_loud_horn() -> void:
	_check_adaptation("loud_horn", 45.0)
	check_near(tuning.f("horn_nerves") + _passive("loud_horn", "horn_nerves_more"), -5.0, 0.000001, "the horn gives -5 Nerves")
	check_near(_passive("loud_horn", "horn_suspicion_more"), 15.0, 0.000001, "+15 extra Suspicion per honk")
	var third: float = tuning.fi("gear_speeds", 2)
	var types: Array[String] = []
	for vehicle: Dictionary in data.records("vehicles"):
		if GameData.as_bool(vehicle.get("traffic"), true):
			types.append(GameData.as_string(vehicle.get("id")))
	check(types.has("truck") and types.has("minibus") and types.has("tanker"), "(traffic has trucks, buses and tankers, which ignore the base horn)")

	# Every vehicle yields.
	for type: String in types:
		var deaf: bool = not GameData.as_bool(data.record("vehicles", type).get("yields_to_horn"))
		for loud: bool in [false, true]:
			_new_sim()
			if loud:
				_give("loud_horn")
			_cruise(3, 1)
			var ahead: TrafficSim.Vehicle = _sim.traffic.spawn(StringName(type), 1, _sim.car.s + tuning.f("horn_range") * 0.5, third - 10.0)
			_tap_at("horn")
			_run(tuning.f("horn_yield_time") + 0.2)
			if loud:
				check(ahead.lane != 1, "the loud horn moves a %s over" % type)
			elif deaf:
				check_eq(ahead.lane, 1, "(a %s ignores the base horn)" % type)

	# -5 Nerves, still at most once per horn_cooldown.
	_new_sim()
	var fitted: ItemSim.Item = _give("loud_horn")
	check(BAYS.has(String(fitted.slot)), "it takes a bay")
	_sim.nerves.set_value(60.0)
	_tap_at("horn")
	check_near(_sim.nerves.value, 55.0, 0.000001, "a honk of the loud horn is -5 Nerves")
	_tap()
	check_near(_sim.nerves.value, 55.0, 0.000001, "once per cooldown, like the base horn")

	# The police and those he cannot move.
	_begin_quiet_leg("patrol", 2, 71)
	_give("loud_horn")
	var guard: int = _ticks_in(60.0)
	while not _sim.suspicion.watching and guard > 0:
		guard -= 1
		_tick()
	_run(2.0)
	check(_sim.suspicion.watching and _sim.suspicion.value < 1.0, "(a patrol is watching)")
	var police: TrafficSim.Vehicle = _sim.encounter.police()
	var police_lane: int = police.lane if police != null else -1
	_tap_at("horn")
	check_between(_sim.suspicion.value, tuning.f("suspicion_honk") + 15.0 - 1.0, tuning.f("suspicion_honk") + 15.0, "a honk in view of a patrol is the honk's +15 and 15 more")
	_run(tuning.f("horn_yield_time") + 0.2)
	check(police != null and police.lane == police_lane, "the police car behind him does not move over for it")
	# The motorcade holds every lane (GDD 9.3): there is nowhere for it to yield to.
	_begin_quiet_leg("motorcade", 3, 71)
	_give("loud_horn")
	guard = _ticks_in(180.0)
	var convoy: Array[TrafficSim.Vehicle] = []
	var nearest: float = INF
	while nearest > tuning.f("horn_range") * 0.8 and guard > 0:
		guard -= 1
		_tick()
		convoy = _sim.encounter.motorcade()
		nearest = INF
		for black: TrafficSim.Vehicle in convoy:
			if absf(black.x - _sim.car.x) < _sim.car.lane_width() * 0.5:
				nearest = minf(nearest, (black.s - black.half_length) - (_sim.car.s + _sim.car.length() * 0.5))
	check(not convoy.is_empty() and nearest < tuning.f("horn_range"), "(behind the motorcade, its last car within the horn's range: %s m)" % str(snappedf(nearest, 0.1)))
	_tap_at("horn")
	var moved: int = 0
	for black: TrafficSim.Vehicle in _sim.encounter.motorcade():
		if black.signalling != 0 or black.changing:
			moved += 1
	check_eq(moved, 0, "(so even the loud horn moves none of it)")

	# Without it: just the +15.
	_begin_quiet_leg("patrol", 2, 71)
	guard = _ticks_in(60.0)
	while not _sim.suspicion.watching and guard > 0:
		guard -= 1
		_tick()
	_run(2.0)
	_tap_at("horn")
	check_between(_sim.suspicion.value, tuning.f("suspicion_honk") - 1.0, tuning.f("suspicion_honk"), "(the base horn is +15)")


# --- T-ITEM-BULL-BAR ---------------------------------------------------------

## T-ITEM-BULL-BAR: Bull bar (7.6): lamp capacity +1; sideways speed -15%;
## takes a bay; price 55.
func test_item_bull_bar() -> void:
	_check_adaptation("bull_bar", 55.0)
	check_near(_passive("bull_bar", "lamp_capacity"), 1.0, 0.000001, "lamp capacity +1")
	check_near(_passive("bull_bar", "lat_speed_mult"), 0.85, 0.000001, "sideways speed -15%")
	var capacity: int = tuning.i("lamp_capacity")

	# Lamp capacity +1: the fifth lamp is not a Wreck, the sixth is.
	_new_sim()
	var fitted: ItemSim.Item = _give("bull_bar")
	check(BAYS.has(String(fitted.slot)), "it takes a bay")
	check_eq(_sim.faults.capacity, capacity + 1, "with the bull bar the car has room for one lamp more")
	check_eq(GameData.as_int(_sim.snapshot()["lamp_capacity"]), capacity + 1, "(as the snapshot says)")
	_cruise(3, 1)
	for _hit: int in capacity:
		_scrape_rail()
	check_eq(_sim.faults.lamps, capacity, "(five scrapes: five lamps)")
	check(not _sim.wrecked, "five lamps lit is not a Wreck")
	_scrape_rail()
	check(_sim.wrecked, "the sixth is")
	# Without it the fifth lamp is the Wreck.
	_new_sim()
	_cruise(3, 1)
	for _hit: int in capacity - 1:
		_scrape_rail()
	check(not _sim.wrecked, "(without it four lamps are not a Wreck)")
	_scrape_rail()
	check(_sim.wrecked, "(and the fifth is)")

	# Sideways speed -15%.
	var plain: float = _sideways_speed()
	check_near(plain, 0.5 * tuning.f("lat_per_kmh") * tuning.fi("gear_speeds", 2), 0.001, "(without it half lock in third gear moves the car 2.5 m/s sideways)")
	_new_sim()
	_give("bull_bar")
	check_near(_sideways_speed(false), plain * 0.85, 0.001, "with the bull bar the same wheel moves it 15% slower")


# --- T-ITEM-FOG-LAMPS --------------------------------------------------------

## T-ITEM-FOG-LAMPS: Fog lamps (7.6): visibility +40% in rain, dust and
## night; oncoming drivers flash back, +2 Nerves each; takes a bay; price 40.
func test_item_fog_lamps() -> void:
	_check_adaptation("fog_lamps", 40.0)
	check_near(_passive("fog_lamps", "visibility_mult"), 1.4, 0.000001, "visibility +40%")
	check_near(_passive("fog_lamps", "flash_back_nerves"), 2.0, 0.000001, "oncoming drivers flash back: +2 Nerves each")

	# Night.
	_begin_quiet_leg("night", 2, 71)
	_run(0.5)
	var cone: float = _sim.visibility()
	check_near(cone, tuning.f("low_beam_cone"), 0.000001, "(at night he sees 60 m)")
	var fitted: ItemSim.Item = _give("fog_lamps")
	check(BAYS.has(String(fitted.slot)), "it takes a bay")
	check_near(_sim.visibility(), cone * 1.4, 0.000001, "with fog lamps, 40% further")
	check_near(GameData.as_float(_sim.snapshot()["visibility"]), cone * 1.4, 0.000001, "(the snapshot's visibility)")

	# Dust.
	var dust: float = GameData.as_float(data.record("modifiers", "dust_haze").get("visibility_m"))
	var plan: Dictionary = LegGenerator.generate(data, "open_road", 2, 5, "dust_haze")
	for key: String in ["spawns", "hazards", "curves", "gusts", "zones"]:
		plan[key] = []
	_new_sim()
	_sim.gate.reset(3)
	_sim.begin_leg(plan)
	_run(0.5)
	check_near(_sim.visibility(), dust, 0.000001, "(in a dust haze he sees %d m)" % roundi(dust))
	_give("fog_lamps")
	check_near(_sim.visibility(), dust * 1.4, 0.000001, "with fog lamps, 40% further")

	# Rain: the view stays clear 40% longer after a sweep.
	var clear: float = tuning.f("wiper_clear_time")
	_new_sim()
	_sim.items.raining = true
	_reach("wiper_stalk")
	_flick(Vector2(0.0, -tuning.f("flick_min_distance") * 1.5))
	_run(clear * 0.5)
	var plain_blur: float = _sim.items.rain_blur()
	check_near(plain_blur, 0.5, 0.02, "(in rain the view is half blurred 3 s after a sweep)")
	_new_sim()
	_give("fog_lamps")
	_sim.items.raining = true
	_reach("wiper_stalk")
	_flick(Vector2(0.0, -tuning.f("flick_min_distance") * 1.5))
	_run(clear * 0.5)
	check_near(_sim.items.rain_blur(), plain_blur / 1.4, 0.02, "with fog lamps it blurs 40% more slowly")
	_run(clear * 0.9)
	check_near(_sim.items.rain_blur(), 1.0, 0.000001, "and is whole 8.4 s after the sweep")

	# In clear daylight there is nothing to see further into.
	_begin_quiet_leg("open_road", 1, 5)
	var day: float = _sim.visibility()
	_give("fog_lamps")
	check_eq(_sim.visibility(), day, "by day in clear air nothing changes")

	# Oncoming drivers flash back: +2 Nerves each.
	var plain_met: float = _meet_oncoming(false, false, 2)
	var lamps_met: float = _meet_oncoming(true, false, 2)
	check_near(lamps_met - plain_met, 2.0 * 2.0, 0.000001, "two oncoming vehicles met with fog lamps: +2 Nerves each")
	# The high beam's own rule (GDD 4.6) adds to it.
	var beam_met: float = _meet_oncoming(false, true, 2)
	check_near(beam_met - plain_met, tuning.f("high_beam_nerves") * 2.0, 0.000001, "(on high beam each oncoming vehicle met is +2 Nerves: GDD 4.6)")
	var both_met: float = _meet_oncoming(true, true, 1)
	var one_met: float = _meet_oncoming(false, false, 1)
	check_near(both_met - one_met, tuning.f("high_beam_nerves") + 2.0, 0.000001, "fog lamps and high beam together: both")
	# On a divided road nobody is met.
	_begin_quiet_leg("open_road", 1, 5)
	_give("fog_lamps")
	_run(1.0)
	var before: float = _sim.nerves.value
	var passing: TrafficSim.Vehicle = _sim.traffic.spawn(&"car", 0, _sim.car.s + 60.0, 100.0, -1)
	_run(2.0)
	check(passing.s < _sim.car.s, "(a vehicle going the other way passes)")
	check(_sim.nerves.value - before < 1.0, "on a divided road there are no oncoming drivers to flash back")


# --- T-ITEM-WIDE-MIRROR ------------------------------------------------------

## T-ITEM-WIDE-MIRROR: Wide mirror (7.6): mirror tells arrive 5 s earlier;
## the mirror covers more of the windscreen; takes a bay; price 35.
func test_item_wide_mirror() -> void:
	_check_adaptation("wide_mirror", 35.0)
	var lead: float = _passive("wide_mirror", "mirror_lead_s")
	check_near(lead, 5.0, 0.000001, "mirror tells arrive 5 s earlier")
	check(_passive("wide_mirror", "mirror_scale") > 1.0, "the mirror covers more of the windscreen")

	# The Patrol's blue lights.
	var patrol: Dictionary = GameData.as_dict(data.record("legs", "patrol").get("special"))
	var at: float = GameData.as_float(patrol.get("at_s"))
	var lights: float = GameData.as_float(patrol.get("lights_lead_s"))
	var plain: Vector2 = _patrol_times(false, false)
	check_near(plain.x, at - lights, 2.0 * DT, "(the blue lights show 3 s before Suspicion starts)")
	check_near(plain.y, at, 2.0 * DT, "(which is %s s into the leg)" % str(at))
	var wide: Vector2 = _patrol_times(true, false)
	check_near(wide.x, at - lights - lead, 2.0 * DT, "with the wide mirror they show 5 s earlier")
	check_near(wide.y, at, 2.0 * DT, "Suspicion starts when it always did")
	# A cracked mirror is 2 s late; a wide one that is cracked is 3 s early.
	var delay: float = GameData.as_float(GameData.as_dict(data.record("faults", "cracked_mirror").get("params")).get("mirror_tell_delay_s"))
	var cracked: Vector2 = _patrol_times(false, true)
	check_near(cracked.x, at - lights + delay, 2.0 * DT, "(a cracked mirror shows them 2 s later)")
	var both: Vector2 = _patrol_times(true, true)
	check_near(both.x, at - lights - lead + delay, 2.0 * DT, "a wide mirror that is cracked: 5 s earlier and 2 s later")

	# The Tailgater.
	var special: Dictionary = GameData.as_dict(data.record("legs", "tailgater").get("special"))
	var tail_at: float = GameData.as_float(special.get("at_s"))
	var tell: float = GameData.as_float(special.get("tell_s"))
	var plain_tail: Vector2 = _tailgater_times(false)
	check_near(plain_tail.x, tail_at - tell, 2.0 * DT, "(the tailgater shows up %s s before he is on the bumper)" % str(tell))
	var wide_tail: Vector2 = _tailgater_times(true)
	check_near(wide_tail.x, tail_at - tell - lead, 2.0 * DT, "with the wide mirror he is seen 5 s earlier")
	check_near(wide_tail.y, plain_tail.y, 2.0 * DT, "and is on the bumper when he always was")

	# The mirror covers more of the windscreen.
	_new_sim()
	check_near(GameData.as_float(_sim.snapshot()["mirror_scale"]), 1.0, 0.000001, "(the plain mirror)")
	var fitted: ItemSim.Item = _give("wide_mirror")
	check(BAYS.has(String(fitted.slot)), "it takes a bay")
	check_near(GameData.as_float(_sim.snapshot()["mirror_scale"]), _passive("wide_mirror", "mirror_scale"), 0.000001, "the snapshot gives the view a bigger mirror")


# --- Helpers -----------------------------------------------------------------

## What every Adaptation is: fitted in a bay, at its price.
func _check_adaptation(item_id: String, price: float) -> void:
	var record: Dictionary = _record(item_id)
	check_eq(GameData.as_string(record.get("kind")), "adaptation", "%s is an Adaptation" % item_id)
	check_eq(GameData.as_array(record.get("slots")), BAYS, "that takes one of the three bays")
	check_near(GameData.as_float(record.get("price")), price, 0.000001, "price %d" % roundi(price))
	for bay: Variant in BAYS:
		check_eq(GameData.as_string(data.record("slots", GameData.as_string(bay)).get("reach")), "none", "(%s is no place for the hand)" % GameData.as_string(bay))


## The amount an item's entries give a standing change.
func _passive(item_id: String, key: String) -> float:
	for list: String in ["gives", "takes"]:
		for listed: Variant in GameData.as_array(_record(item_id).get(list)):
			var entry: Dictionary = GameData.as_dict(listed)
			if GameData.as_string(entry.get("passive")) == key:
				return GameData.as_float(entry.get("amount"))
	return 0.0


## Grips, pulls the wheel 100 pixels in one tick, then lets go for a tenth
## of a second. Returns (degrees the commanded angle moved, degrees the
## wheel came back in that tenth).
func _turn_and_let_go(fresh: bool = true) -> Vector2:
	if fresh:
		_new_sim()
	_cruise(3, 1)
	_grip()
	_ticks(_ticks_in(0.3))
	var from: float = _sim.wheel.command
	_steer(100.0, 1)
	var turned: float = _sim.wheel.command - from
	_ticks(_ticks_in(0.5))
	var held: float = _sim.wheel.angle
	_input.clear()
	_ticks(_ticks_in(0.1))
	return Vector2(turned, held - _sim.wheel.angle)


## The mouse buttons bound to an input action.
func _mouse_buttons(action: String) -> Array[int]:
	var buttons: Array[int] = []
	var setting: Dictionary = GameData.as_dict(ProjectSettings.get_setting("input/" + action))
	for event: Variant in GameData.as_array(setting.get("events")):
		if event is InputEventMouseButton:
			var button: InputEventMouseButton = event
			buttons.append(int(button.button_index))
	return buttons


## The lever from neutral to where fifth gear is: right, then forward.
func _to_fifth() -> void:
	_sim.gate.reset(GearGate.NEUTRAL)
	_reach("gear_lever")
	_input.pointer_is_absolute = false
	_input.lmb = true
	_ticks(2)
	var unit: float = tuning.f("gate_unit")
	_input.pointer_delta = Vector2(unit / 10.0, 0.0)
	_ticks(10)
	_input.pointer_delta = Vector2(0.0, -unit / 10.0)
	_ticks(10)
	_input.pointer_delta = Vector2.ZERO
	_ticks(2)
	_input.lmb = false
	_ticks(SETTLE)


## The car's sideways speed with the wheel held at half lock in third gear.
func _sideways_speed(fresh: bool = true) -> float:
	if fresh:
		_new_sim()
	_cruise(3, 1)
	_grip()
	_ticks(_ticks_in(0.3))
	var half_lock: float = _sim.wheel.max_angle() * 0.5
	_steer(half_lock / (tuning.f("steer_deg_per_px") * _sim.wheel.turn_rate_mult), 20)
	_ticks(_ticks_in(1.5))
	check_near(_sim.wheel.angle, half_lock, 0.01, "(the wheel at half lock)")
	return _sim.car.v_lat


## A quiet Two-lane leg in which `count` oncoming cars are met, one after the
## other: the change in his Nerves from the first appearing to the last gone.
func _meet_oncoming(fog_lamps: bool, high_beam: bool, count: int) -> float:
	_begin_quiet_leg("two_lane", 3, 71)
	_sim.traffic.clear()
	if fog_lamps:
		_give("fog_lamps")
	_sim.items.flags[&"high_beam"] = high_beam
	_run(1.0)
	var before: float = _sim.nerves.value
	for _car: int in count:
		var other: TrafficSim.Vehicle = _sim.traffic.spawn(&"car", -1, _sim.car.s + 150.0, 100.0, -1)
		var guard: int = _ticks_in(10.0)
		while other.s > _sim.car.s - 40.0 and guard > 0:
			guard -= 1
			_tick()
	return _sim.nerves.value - before


## A quiet Patrol leg: when the blue lights came on and when Suspicion began
## (seconds into the leg).
func _patrol_times(wide_mirror: bool, cracked: bool) -> Vector2:
	_begin_quiet_leg("patrol", 2, 71)
	if wide_mirror:
		_give("wide_mirror")
	if cracked:
		_sim.faults.active.append(&"cracked_mirror")
		_sim.faults.deck.erase(&"cracked_mirror")
		_sim.faults.lamps = _sim.faults.active.size()
	var lights_at: float = -1.0
	var watch_at: float = -1.0
	var guard: int = _ticks_in(60.0)
	while watch_at < 0.0 and guard > 0:
		guard -= 1
		_tick()
		if lights_at < 0.0 and _sim.encounter.police_lights:
			lights_at = _sim.leg.time
		if _sim.suspicion.watching:
			watch_at = _sim.leg.time
	return Vector2(lights_at, watch_at)


## A quiet Tailgater leg: when he was first there to be seen and when he was
## on the bumper (seconds into the leg).
func _tailgater_times(wide_mirror: bool) -> Vector2:
	_begin_quiet_leg("tailgater", 2, 71)
	if wide_mirror:
		_give("wide_mirror")
	var seen_at: float = -1.0
	var on_at: float = -1.0
	var guard: int = _ticks_in(60.0)
	while on_at < 0.0 and guard > 0:
		guard -= 1
		_tick()
		if seen_at < 0.0 and _sim.encounter.tailgater() != null:
			seen_at = _sim.leg.time
		if _sim.encounter.tail_phase == EncounterSim.TAIL_ON_BUMPER:
			on_at = _sim.leg.time
	return Vector2(seen_at, on_at)
