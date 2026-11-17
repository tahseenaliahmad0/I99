extends TestSuite
## M2: collisions and close calls (GDD 5.6, 5.7).

const DT: float = DriveSim.DT
const MAX_SECONDS: float = 60.0

## What one scripted pass earned.
class PassResult:
	extends RefCounted
	var close_calls: int = 0
	var cash: float = 0.0
	var nerves: float = 0.0
	var lamps: int = 0
	var judged_after_overlap: bool = false

var _sim: DriveSim
var _input: DriveInput


func before_each() -> void:
	_sim = DriveSim.new(fresh_data())
	_input = DriveInput.new()


## T-COL-01: a closing speed of 20 km/h gives a scrape: 1 lamp, +10 Nerves,
## speed drops 20%; pushed hit_pushback clear; no second hit for hit_immunity.
func test_col_01() -> void:
	var third: float = tuning.fi("gear_speeds", 2)
	_start(3, 1)
	var ahead: TrafficSim.Vehicle = _sim.traffic.spawn(&"car", 1, 40.0, third - 20.0)
	var nerves_before: float = _sim.nerves.value
	if not check(_run_until_hit(), "driving into a slower car hits it"):
		return
	check_eq(_sim.collision.hit, Collision.Hit.SCRAPE, "a closing speed of 20 km/h is a scrape")
	check_eq(_sim.faults.lamps, int(tuning.fi("hit_lamps", 0)), "a scrape lights 1 lamp")
	check_near(_sim.nerves.value - nerves_before, tuning.fi("hit_nerves", 0), 0.01, "a scrape adds 10 Nerves")
	check_near(_sim.car.speed, third * (1.0 - tuning.f("scrape_speed_loss")), 0.5, "a scrape takes 20% off the speed")
	check_eq(_sim.gate.gear, 3, "a scrape does not force a gear")
	var gap: float = (ahead.s - ahead.half_length) - (_sim.car.s + _sim.car.length() * 0.5)
	check_near(gap, tuning.f("hit_pushback"), 0.01, "the car is pushed hit_pushback clear")
	check_near(_sim.collision.immunity_left, tuning.f("hit_immunity"), DT, "immunity starts")

	# During the immunity even a full overlap is not a second hit.
	var lamps: int = _sim.faults.lamps
	ahead.s = _sim.car.s
	ahead.x = _sim.car.x
	ahead.speed = _sim.car.speed
	ahead.cruise = _sim.car.speed
	var immune_ticks: int = int(tuning.f("hit_immunity") / DT) - 2
	for _tick: int in immune_ticks:
		_sim.step(_input)
		ahead.s = _sim.car.s
		ahead.x = _sim.car.x
	check_eq(_sim.faults.lamps, lamps, "during hit_immunity the car cannot be hit again")
	for _tick: int in 6:
		_sim.step(_input)
		ahead.s = _sim.car.s
		ahead.x = _sim.car.x
	check(_sim.faults.lamps > lamps, "once hit_immunity is over it can")

	# A sideswipe pushes the car sideways, clear of the other.
	_start(3, 1)
	var beside: TrafficSim.Vehicle = _sim.traffic.spawn(&"truck", 2, 0.0, third - 15.0)
	_sim.car.x = beside.x - beside.half_width - _sim.car.half_width() + 0.2
	_sim.step(_input)
	check_eq(_sim.collision.hit, Collision.Hit.SCRAPE, "rubbing along a truck at 15 km/h closing is a scrape")
	var side_gap: float = (beside.x - beside.half_width) - (_sim.car.x + _sim.car.half_width())
	check_near(side_gap, tuning.f("hit_pushback"), 0.01, "a sideswipe pushes the car hit_pushback sideways")

	# The edge of the class: exactly scrape_max_closing is still a scrape.
	check_eq(_sim.collision.classify(tuning.f("scrape_max_closing"), false), Collision.Hit.SCRAPE, "a closing speed of exactly scrape_max_closing is a scrape")
	check_eq(_sim.collision.classify(tuning.f("scrape_max_closing") + 0.1, false), Collision.Hit.CRASH, "just over it is a crash")


## T-COL-02: a closing speed of 50 km/h gives a crash: 2 lamps, +20 Nerves,
## forced into first gear.
func test_col_02() -> void:
	var third: float = tuning.fi("gear_speeds", 2)
	_start(3, 1)
	var ahead: TrafficSim.Vehicle = _sim.traffic.spawn(&"truck", 1, 60.0, third - 50.0)
	var nerves_before: float = _sim.nerves.value
	if not check(_run_until_hit(), "driving into a much slower truck hits it"):
		return
	check_eq(_sim.collision.hit, Collision.Hit.CRASH, "a closing speed of 50 km/h is a crash")
	check_eq(_sim.faults.lamps, int(tuning.fi("hit_lamps", 1)), "a crash lights 2 lamps")
	check_near(_sim.nerves.value - nerves_before, tuning.fi("hit_nerves", 1), 0.01, "a crash adds 20 Nerves")
	check_eq(_sim.gate.gear, tuning.i("hit_forced_gear"), "a crash forces first gear")
	check(_sim.gate.lever.is_equal_approx(GearGate.gear_position(1)), "the lever jumps to first")
	check(_sim.car.speed <= ahead.speed + 0.001, "having run into its back, he is no faster than the truck")
	check_eq(_sim.collision.classify(tuning.f("crash_max_closing"), false), Collision.Hit.CRASH, "a closing speed of exactly crash_max_closing is still a crash")
	check(not _sim.wrecked, "two lamps are not a Wreck")

	# The events a view hears.
	var kinds: Array[String] = []
	for event: Dictionary in _sim.drain_events():
		kinds.append(str(event.get("type")))
	check(kinds.has("hit") and kinds.has("lamp_lit"), "the hit and the lamps are announced as events")


## T-COL-03: a closing speed of 90 km/h, or any oncoming vehicle, gives a
## head-on: 3 lamps, +30 Nerves, forced into first gear.
func test_col_03() -> void:
	var fourth: float = tuning.fi("gear_speeds", 3)
	_start(4, 1)
	_sim.traffic.spawn(&"tuk_tuk", 1, 80.0, fourth - 90.0)
	var nerves_before: float = _sim.nerves.value
	if not check(_run_until_hit(), "fourth gear into a tuk-tuk hits it"):
		return
	check_eq(_sim.collision.hit, Collision.Hit.HEAD_ON, "a closing speed of 90 km/h is a head-on")
	check_eq(_sim.faults.lamps, int(tuning.fi("hit_lamps", 2)), "a head-on lights 3 lamps")
	check_near(_sim.nerves.value - nerves_before, tuning.fi("hit_nerves", 2), 0.01, "a head-on adds 30 Nerves")
	check_eq(_sim.gate.gear, tuning.i("hit_forced_gear"), "a head-on forces first gear")
	check_eq(_sim.collision.classify(tuning.f("crash_max_closing") + 0.1, false), Collision.Hit.HEAD_ON, "just over crash_max_closing is a head-on")

	# Any oncoming vehicle, however slow the meeting.
	_start(1, 0)
	_sim.set_road(1, false)
	_sim.car.speed = 5.0
	_sim.car.x = _sim.traffic.lane_center(-1)
	var oncoming: TrafficSim.Vehicle = _sim.traffic.spawn(&"car", -1, 12.0, 10.0, -1)
	check(oncoming.closing_speed(_sim.car.speed) < tuning.f("scrape_max_closing"), "the two close at under scrape_max_closing")
	nerves_before = _sim.nerves.value
	if check(_run_until_hit(), "meeting an oncoming car in its lane hits it"):
		check_eq(_sim.collision.hit, Collision.Hit.HEAD_ON, "any oncoming vehicle is a head-on")
		check_eq(_sim.faults.lamps, int(tuning.fi("hit_lamps", 2)), "3 lamps")
		check_near(_sim.nerves.value - nerves_before, tuning.fi("hit_nerves", 2), 0.01, "+30 Nerves")
		check_eq(_sim.car.speed, 0.0, "a head-on stops the car")

	# Lamps add up to a Wreck (the full rules arrive with T-FAULT-01).
	_start(4, 1)
	_sim.traffic.spawn(&"tuk_tuk", 1, 80.0, 30.0)
	_run_until_hit()
	_sim.collision.immunity_left = 0.0
	_sim.gate.reset(4)
	_sim.car.speed = tuning.fi("gear_speeds", 3)
	_sim.traffic.spawn(&"tuk_tuk", 1, _sim.car.s + 60.0, 30.0)
	_run_until_hit()
	check(_sim.faults.lamps >= tuning.i("lamp_capacity"), "two head-ons light every lamp")
	check(_sim.wrecked, "which is a Wreck")


## T-CC-01: a close call is a pass with under close_call_gap of sideways gap
## and at least close_call_min_closing, without contact, judged when the two
## stop overlapping along the road; it pays base x gear, double for oncoming,
## and adds 2 Nerves.
func test_cc_01() -> void:
	var gap_limit: float = tuning.f("close_call_gap")
	var base: float = tuning.f("close_call_base_cash")
	var third: float = tuning.fi("gear_speeds", 2)

	# The reference pass: third gear, a truck one lane over, 0.3 m of air.
	var result: PassResult = _pass(3, &"truck", third - 35.0, gap_limit * 0.5, 1)
	check_eq(result.close_calls, 1, "passing with under close_call_gap of gap at 35 km/h closing is one close call")
	check_near(result.cash, base * tuning.fi("gear_cash_mult", 2), 0.000001, "in third it pays close_call_base_cash x1")
	check_near(result.nerves, tuning.f("close_call_nerves"), 0.01, "and adds 2 Nerves")
	check_eq(result.lamps, 0, "without contact")
	check(result.judged_after_overlap, "it is judged when the two stop overlapping along the road, not before")

	# Gear multipliers.
	result = _pass(4, &"truck", tuning.fi("gear_speeds", 3) - 60.0, gap_limit * 0.5, 1)
	check_near(result.cash, base * tuning.fi("gear_cash_mult", 3), 0.000001, "in fourth it pays x2")
	result = _pass(2, &"tuk_tuk", tuning.fi("gear_speeds", 1) - 30.0, gap_limit * 0.5, 1)
	check_near(result.cash, base * tuning.fi("gear_cash_mult", 1), 0.000001, "in second it pays x0.5")
	result = _pass(5, &"truck", tuning.fi("gear_speeds", 4) - 60.0, gap_limit * 0.5, 1)
	check_near(result.cash, base * tuning.fi("gear_cash_mult", 4), 0.000001, "in fifth it pays x3")

	# Not close calls.
	result = _pass(3, &"truck", third - 35.0, gap_limit + 0.1, 1)
	check_eq(result.close_calls, 0, "a pass with more than close_call_gap of gap is not a close call")
	check_near(result.cash, 0.0, 0.000001, "and pays nothing")
	result = _pass(3, &"car", third - tuning.f("close_call_min_closing") + 5.0, gap_limit * 0.5, 1)
	check_eq(result.close_calls, 0, "a pass slower than close_call_min_closing is not a close call")
	result = _pass(3, &"truck", third - 35.0, -0.1, 1)
	check_eq(result.close_calls, 0, "a pass that touches is not a close call")
	check(result.lamps > 0, "it is a hit")

	# The edge: exactly at the gap is not under it.
	result = _pass(3, &"truck", third - 35.0, gap_limit + 0.001, 1)
	check_eq(result.close_calls, 0, "a gap of close_call_gap is not under close_call_gap")
	result = _pass(3, &"truck", third - 35.0, gap_limit - 0.01, 1)
	check_eq(result.close_calls, 1, "just under it is")

	# Oncoming: double.
	result = _pass(3, &"car", 100.0, gap_limit * 0.5, -1)
	check_eq(result.close_calls, 1, "passing an oncoming car closely is a close call")
	check_near(result.cash, base * tuning.fi("gear_cash_mult", 2) * tuning.f("close_call_oncoming_mult"), 0.000001, "an oncoming close call pays double")

	# A taxi honks when passed closely.
	result = _pass(3, &"taxi", third - 35.0, gap_limit * 0.5, 1)
	var taxi: Dictionary = data.record("vehicles", "taxi")
	check_near(result.nerves, tuning.f("close_call_nerves") + GameData.as_float(taxi.get("honk_nerves")), 0.01, "a taxi passed closely honks: its honk_nerves on top")

	# Falling back from beside a vehicle is not passing it.
	_start(3, 1)
	var beside: TrafficSim.Vehicle = _sim.traffic.spawn(&"truck", 2, 4.0, third)
	_sim.car.x = beside.x - beside.half_width - _sim.car.half_width() - gap_limit * 0.5
	_input.rmb = true
	var calls: int = 0
	for _tick: int in int(6.0 / DT):
		_hold_x()
		_sim.step(_input)
		calls += _sim.collision.close_calls
	_input.rmb = false
	check_eq(calls, 0, "dropping back from beside a vehicle is not a close call")


## T-CC-02: chained close calls multiply by 1.25 steps and cap at 3.
func test_cc_02() -> void:
	var window: float = tuning.f("chain_window")
	var step_by: float = tuning.f("chain_step")
	var cap: float = tuning.f("chain_cap")
	var base: float = tuning.f("close_call_base_cash")
	var third: float = tuning.fi("gear_speeds", 2)
	var gap: float = tuning.f("close_call_gap") * 0.5

	# The multipliers themselves.
	check_near(_sim.collision.chain_multiplier(0), 1.0, 0.000001, "the first close call pays x1")
	check_near(_sim.collision.chain_multiplier(1), 1.0 + step_by, 0.000001, "the second in a chain pays x1.25")
	check_near(_sim.collision.chain_multiplier(2), 1.0 + step_by * 2.0, 0.000001, "the third pays x1.5")
	var links_to_cap: int = roundi((cap - 1.0) / step_by)
	check_near(_sim.collision.chain_multiplier(links_to_cap), cap, 0.000001, "it reaches the cap after %d links" % links_to_cap)
	check_near(_sim.collision.chain_multiplier(links_to_cap + 5), cap, 0.000001, "and never passes chain_cap")

	# A row of slow cars passed one after another, each within chain_window.
	_start(3, 1)
	var count: int = links_to_cap + 3
	var slow: float = third - 40.0
	var spacing: float = 28.0
	for index: int in count:
		_sim.traffic.spawn(&"car", 2, 30.0 + spacing * float(index), slow)
	_sim.car.x = _sim.traffic.lane_center(2) - _sim.car.half_width() * 2.0 - gap
	var pays: Array[float] = []
	var times: Array[float] = []
	for tick: int in int(MAX_SECONDS / DT):
		_hold_x()
		_sim.step(_input)
		if _sim.collision.close_calls > 0:
			pays.append(_sim.collision.close_call_cash)
			times.append(float(tick) * DT)
		if pays.size() == count:
			break
	if not check_eq(pays.size(), count, "every car in the row is passed as a close call"):
		return
	var in_window: bool = true
	for index: int in range(1, count):
		if times[index] - times[index - 1] > window:
			in_window = false
	check(in_window, "each pass comes within chain_window of the last")
	for index: int in count:
		var expected: float = base * minf(1.0 + step_by * float(index), cap)
		check_near(pays[index], expected, 0.000001, "close call %d of the chain pays x%s" % [index + 1, str(minf(1.0 + step_by * float(index), cap))])
	check_eq(_sim.faults.lamps, 0, "all without contact")
	check_near(_sim.cash, tuning.f("cash_start") + _sum(pays), 0.000001, "the cash is his")

	# A pause longer than chain_window breaks the chain.
	for _tick: int in int((window + 0.5) / DT):
		_hold_x()
		_sim.step(_input)
	_sim.traffic.spawn(&"car", 2, _sim.car.s + 30.0, slow)
	var after_pause: float = -1.0
	for _tick: int in int(10.0 / DT):
		_hold_x()
		_sim.step(_input)
		if _sim.collision.close_calls > 0:
			after_pause = _sim.collision.close_call_cash
			break
	check_near(after_pause, base, 0.000001, "after more than chain_window without one, the chain starts again at x1")


# --- Helpers ------------------------------------------------------------------

## A fresh simulation cruising in `gear` in `lane`, nothing on the road.
func _start(gear: int, lane: int) -> void:
	_sim = DriveSim.new(fresh_data())
	_sim.gate.has_fifth = gear == 5
	_sim.gate.reset(gear)
	_sim.car.reset(lane, gear)
	_input.clear()
	_held_x = INF


var _held_x: float = INF


## Call before each step: cancels the crown so a pass is made at a constant
## sideways gap. The step adds one tick of crown drift before it looks for
## collisions, so the car is set that much to the left of where it is held.
func _hold_x() -> void:
	if _held_x == INF:
		_held_x = _sim.car.x
	_sim.car.x = _held_x - tuning.f("crown_drift") * DT


func _run_until_hit() -> bool:
	for _tick: int in int(MAX_SECONDS / DT):
		var lane_x: float = _sim.car.x
		_sim.step(_input)
		if _sim.collision.hit != Collision.Hit.NONE:
			return true
		_sim.car.x = lane_x
	return false


## Passes one vehicle with `gap` metres of air between the two (negative
## overlaps). `direction` -1 is an oncoming vehicle. Returns what it earned.
func _pass(gear: int, type: StringName, vehicle_speed: float, gap: float, direction: int) -> PassResult:
	_start(gear, 1)
	var lane: int = 2
	var start_s: float = 40.0
	if direction < 0:
		_sim.set_road(1, false)
		_sim.car.reset(0, gear)
		lane = -1
		start_s = 120.0
	var vehicle: TrafficSim.Vehicle = _sim.traffic.spawn(type, lane, start_s, vehicle_speed, direction)
	var side: float = -1.0 if direction > 0 else 1.0
	_sim.car.x = vehicle.x + side * (vehicle.half_width + _sim.car.half_width() + gap)
	var cash_before: float = _sim.cash
	var nerves_before: float = _sim.nerves.value
	var result: PassResult = PassResult.new()
	var judged_after_overlap: bool = true
	for _tick: int in int(MAX_SECONDS / DT):
		_hold_x()
		_sim.step(_input)
		if _sim.collision.close_calls > 0:
			result.close_calls += _sim.collision.close_calls
			var along: float = absf(vehicle.s - _sim.car.s)
			if along < vehicle.half_length + _sim.car.length() * 0.5:
				judged_after_overlap = false
		if _sim.car.s > vehicle.s + 40.0:
			break
	result.cash = _sim.cash - cash_before
	result.nerves = _sim.nerves.value - nerves_before - _hit_nerves()
	result.lamps = _sim.faults.lamps
	result.judged_after_overlap = judged_after_overlap and result.close_calls > 0
	return result


## Nerves that came from hits in this pass (so close-call Nerves can be told apart).
func _hit_nerves() -> float:
	var total: float = 0.0
	for event: Dictionary in _sim.drain_events():
		if event.get("type") == "hit":
			var kind: int = event["kind"]
			total += tuning.fi("hit_nerves", kind - 1)
	return total


func _sum(values: Array[float]) -> float:
	var total: float = 0.0
	for value: float in values:
		total += value
	return total
