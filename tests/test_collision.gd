extends TestSuite
## M2: collisions and close calls (GDD 5.6, 5.7), and the traffic they are
## judged against (GDD 5.5).

const DT: float = DriveSim.DT
const KMH_TO_MS: float = 1.0 / 3.6
const MAX_SECONDS: float = 60.0
## Rounding only: rectangles less than this far inside each other are touching.
const TOUCHING: float = 0.000001
## How far a scripted touch puts the car into a vehicle's side, for one tick.
const TOUCH_DEPTH: float = 0.05
## How long a scripted driver takes to brake after a hit (GDD 13.8: between
## the expert's 0.15 s and the novice's 0.40 s).
const REACTION: float = 0.3

## What one scripted pass earned.
class PassResult:
	extends RefCounted
	var close_calls: int = 0
	var cash: float = 0.0
	var nerves: float = 0.0
	var lamps: int = 0
	var judged_after_overlap: bool = false
	## Nerves added on the tick the two stopped overlapping along the road.
	var judged_nerves: float = 0.0
	## Hits taken on the way.
	var hits: int = 0
	## True when a scripted touch was made.
	var touched: bool = false
	## True when the car ended up ahead of the vehicle.
	var passed: bool = false
	## The vehicle that was passed.
	var vehicle_id: int = 0
	## Everything the simulation announced on the way.
	var events: Array[Dictionary] = []

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
	if not check(_run_until_hit(), "driving into a slower car hits it"):
		return
	check_eq(_sim.collision.hit, Collision.Hit.SCRAPE, "a closing speed of 20 km/h is a scrape")
	check_eq(_sim.faults.lamps, int(tuning.fi("hit_lamps", 0)), "a scrape lights 1 lamp")
	check_near(_hit_tick_nerves, tuning.fi("hit_nerves", 0), 0.01, "a scrape adds 10 Nerves")
	check_near(_sim.car.speed, third * (1.0 - tuning.f("scrape_speed_loss")), 0.5, "a scrape takes 20% off the speed")
	check_eq(_sim.gate.gear, 3, "a scrape does not force a gear")
	var gap: float = (ahead.s - ahead.half_length) - (_sim.car.s + _sim.car.length() * 0.5)
	check_near(gap, tuning.f("hit_pushback"), 0.01, "the car is pushed hit_pushback clear")
	check_near(_sim.collision.immunity_left, tuning.f("hit_immunity"), DT, "immunity starts")

	# What a view hears of it (GDD 13.6).
	var events: Array[Dictionary] = _sim.drain_events()
	var hit_events: Array[Dictionary] = _of_type(events, "hit")
	if check_eq(hit_events.size(), 1, "one scrape is one hit event"):
		_check_hit_event(hit_events[0], Collision.Hit.SCRAPE, int(tuning.fi("hit_lamps", 0)), ahead.id, "the scrape")
	var lamp_events: Array[Dictionary] = _of_type(events, "lamp_lit")
	if check_eq(lamp_events.size(), 1, "and one lamp_lit event"):
		check_eq(GameData.as_int(lamp_events[0].get("lamps"), -1), int(tuning.fi("hit_lamps", 0)), "lamp_lit says how many lamps are lit now")
		check_eq(GameData.as_int(lamp_events[0].get("lit"), -1), int(tuning.fi("hit_lamps", 0)), "and how many this hit lit")
		check_eq(GameData.as_array(lamp_events[0].get("faults")).size(), int(tuning.fi("hit_lamps", 0)), "with the fault each one stands for")
	check_eq(_of_type(events, "wreck").size(), 0, "one lamp is no wreck event")

	# During the immunity even a full overlap is not a second hit.
	var lamps: int = _sim.faults.lamps
	var lane_x: float = _sim.car.x
	ahead.s = _sim.car.s
	ahead.x = _sim.car.x
	ahead.speed = _sim.car.speed
	ahead.cruise = _sim.car.speed
	var immune_ticks: int = int(tuning.f("hit_immunity") / DT) - 2
	for _tick: int in immune_ticks:
		_sim.step(_input)
		_sim.car.x = lane_x
		ahead.s = _sim.car.s
		ahead.x = _sim.car.x
	check_eq(_sim.faults.lamps, lamps, "during hit_immunity the car cannot be hit again")
	# Once it is over it can. The car that hit him is still in the same contact
	# and cannot hit twice (one contact, one hit: _check_held_sideswipe), so it
	# makes way for another one.
	ahead.s = _sim.car.s + 60.0
	var second: TrafficSim.Vehicle = _sim.traffic.spawn(&"car", 1, _sim.car.s, _sim.car.speed)
	second.x = _sim.car.x
	var hit_by: int = 0
	for _tick: int in 6:
		_sim.step(_input)
		if _sim.collision.hit != Collision.Hit.NONE:
			hit_by = _sim.collision.hit_vehicle_id
		_sim.car.x = lane_x
		second.s = _sim.car.s
		second.x = _sim.car.x
	check(_sim.faults.lamps > lamps, "once hit_immunity is over it can")
	check_eq(hit_by, second.id, "by the car that is on him then")

	# A sideswipe pushes the car sideways, clear of the other.
	_start(3, 1)
	var beside: TrafficSim.Vehicle = _sim.traffic.spawn(&"truck", 2, 0.0, third - 15.0)
	_sim.car.x = beside.x - beside.half_width - _sim.car.half_width() + 0.2
	_sim.step(_input)
	check_eq(_sim.collision.hit, Collision.Hit.SCRAPE, "rubbing along a truck at 15 km/h closing is a scrape")
	var side_gap: float = (beside.x - beside.half_width) - (_sim.car.x + _sim.car.half_width())
	check_near(side_gap, tuning.f("hit_pushback"), 0.01, "a sideswipe pushes the car hit_pushback sideways")
	check_near(_sim.car.speed, third * (1.0 - tuning.f("scrape_speed_loss")), 0.01, "a sideswipe scrape takes 20% off the speed")

	# From the truck's other side he is pushed the other way: away from it.
	_start(3, 2)
	var on_his_left: TrafficSim.Vehicle = _sim.traffic.spawn(&"truck", 1, 0.0, third - 15.0)
	_sim.car.x = on_his_left.x + on_his_left.half_width + _sim.car.half_width() - 0.2
	_sim.step(_input)
	check_eq(_sim.collision.hit, Collision.Hit.SCRAPE, "rubbing along a truck on his left is a scrape too")
	side_gap = (_sim.car.x - _sim.car.half_width()) - (on_his_left.x + on_his_left.half_width)
	check_near(side_gap, tuning.f("hit_pushback"), 0.01, "with the car on the vehicle's right, a sideswipe pushes it hit_pushback to the right")

	# Where the 20% and the cap of running into a back differ: at 10 km/h
	# closing the car ahead does 90 and he is left at 80.
	_start(3, 1)
	var quicker: TrafficSim.Vehicle = _sim.traffic.spawn(&"car", 1, 40.0, third - 10.0)
	if check(_run_until_hit(), "driving into a car 10 km/h slower hits it"):
		check_eq(_sim.collision.hit, Collision.Hit.SCRAPE, "a closing speed of 10 km/h is a scrape")
		check_near(_sim.car.speed, third * (1.0 - tuning.f("scrape_speed_loss")), 0.01, "a rear-end scrape takes 20% off the speed, not just down to the other car's speed")
		check(_sim.car.speed < quicker.speed - 1.0, "which leaves him slower than the car he ran into")

	# The edge of the class: exactly scrape_max_closing is still a scrape.
	check_eq(_sim.collision.classify(tuning.f("scrape_max_closing"), false), Collision.Hit.SCRAPE, "a closing speed of exactly scrape_max_closing is a scrape")
	check_eq(_sim.collision.classify(tuning.f("scrape_max_closing") + 0.1, false), Collision.Hit.CRASH, "just over it is a crash")

	_check_edge_immunity()
	_check_held_sideswipe()
	_check_held_rear_end()
	_check_boxed_in()
	_check_two_at_once()
	_check_merge_beside_barrier()
	_check_sandwich()


## T-COL-02: a closing speed of 50 km/h gives a crash: 2 lamps, +20 Nerves,
## forced into first gear.
func test_col_02() -> void:
	var third: float = tuning.fi("gear_speeds", 2)
	_start(3, 1)
	var ahead: TrafficSim.Vehicle = _sim.traffic.spawn(&"truck", 1, 60.0, third - 50.0)
	if not check(_run_until_hit(), "driving into a much slower truck hits it"):
		return
	check_eq(_sim.collision.hit, Collision.Hit.CRASH, "a closing speed of 50 km/h is a crash")
	check_eq(_sim.faults.lamps, int(tuning.fi("hit_lamps", 1)), "a crash lights 2 lamps")
	check_near(_hit_tick_nerves, tuning.fi("hit_nerves", 1), 0.01, "a crash adds 20 Nerves")
	check_eq(_sim.gate.gear, tuning.i("hit_forced_gear"), "a crash forces first gear")
	check(_sim.gate.lever.is_equal_approx(GearGate.gear_position(1)), "the lever jumps to first")
	check(_sim.car.speed <= ahead.speed + 0.001, "having run into its back, he is no faster than the truck")
	check_eq(_sim.collision.classify(tuning.f("crash_max_closing"), false), Collision.Hit.CRASH, "a closing speed of exactly crash_max_closing is still a crash")
	check(not _sim.wrecked, "two lamps are not a Wreck")

	# The events a view hears.
	var events: Array[Dictionary] = _sim.drain_events()
	var kinds: Array[String] = []
	for event: Dictionary in events:
		kinds.append(str(event.get("type")))
	check(kinds.has("hit") and kinds.has("lamp_lit"), "the hit and the lamps are announced as events")
	var hit_events: Array[Dictionary] = _of_type(events, "hit")
	if check_eq(hit_events.size(), 1, "one crash is one hit event"):
		_check_hit_event(hit_events[0], Collision.Hit.CRASH, int(tuning.fi("hit_lamps", 1)), ahead.id, "the crash")
	var lamp_events: Array[Dictionary] = _of_type(events, "lamp_lit")
	if check_eq(lamp_events.size(), 1, "and one lamp_lit event for its two lamps"):
		check_eq(GameData.as_int(lamp_events[0].get("lit"), -1), int(tuning.fi("hit_lamps", 1)), "lamp_lit says this hit lit 2")
	check_eq(_of_type(events, "wreck").size(), 0, "two lamps are no wreck event")

	# A crash from the side: first gear all the same, but he is not behind
	# the truck, so its speed is not his.
	_start(3, 1)
	var beside: TrafficSim.Vehicle = _sim.traffic.spawn(&"truck", 2, 0.0, third - 40.0)
	_sim.car.x = beside.x - beside.half_width - _sim.car.half_width() + 0.2
	_sim.step(_input)
	check_eq(_sim.collision.hit, Collision.Hit.CRASH, "rubbing along a truck at 40 km/h closing is a crash")
	check_eq(_sim.gate.gear, tuning.i("hit_forced_gear"), "which forces first gear")
	check_near(_sim.car.speed, third, 0.000001, "and leaves him his speed: he did not run into its back")
	var side_gap: float = (beside.x - beside.half_width) - (_sim.car.x + _sim.car.half_width())
	check_near(side_gap, tuning.f("hit_pushback"), 0.01, "he is pushed hit_pushback sideways")


## T-COL-03: a closing speed of 90 km/h, or any oncoming vehicle, gives a
## head-on: 3 lamps, +30 Nerves, forced into first gear.
func test_col_03() -> void:
	var fourth: float = tuning.fi("gear_speeds", 3)
	_start(4, 1)
	_sim.traffic.spawn(&"tuk_tuk", 1, 80.0, fourth - 90.0)
	if not check(_run_until_hit(), "fourth gear into a tuk-tuk hits it"):
		return
	check_eq(_sim.collision.hit, Collision.Hit.HEAD_ON, "a closing speed of 90 km/h is a head-on")
	check_eq(_sim.faults.lamps, int(tuning.fi("hit_lamps", 2)), "a head-on lights 3 lamps")
	check_near(_hit_tick_nerves, tuning.fi("hit_nerves", 2), 0.01, "a head-on adds 30 Nerves")
	check_eq(_sim.gate.gear, tuning.i("hit_forced_gear"), "a head-on forces first gear")
	check_eq(_sim.collision.classify(tuning.f("crash_max_closing") + 0.1, false), Collision.Hit.HEAD_ON, "just over crash_max_closing is a head-on")
	check_near(_sim.car.speed, fourth - 90.0, 0.000001, "into the back of a vehicle going his way it leaves him at that vehicle's speed, not at rest")

	# Any oncoming vehicle, however slow the meeting.
	_start(1, 0)
	_sim.set_road(1, false)
	_sim.car.speed = 5.0
	_sim.car.x = _sim.traffic.lane_center(-1)
	var oncoming: TrafficSim.Vehicle = _sim.traffic.spawn(&"car", -1, 12.0, 10.0, -1)
	check(oncoming.closing_speed(_sim.car.speed) < tuning.f("scrape_max_closing"), "the two close at under scrape_max_closing")
	if check(_run_until_hit(), "meeting an oncoming car in its lane hits it"):
		check_eq(_sim.collision.hit, Collision.Hit.HEAD_ON, "any oncoming vehicle is a head-on")
		check_eq(_sim.faults.lamps, int(tuning.fi("hit_lamps", 2)), "3 lamps")
		check_near(_hit_tick_nerves, tuning.fi("hit_nerves", 2), 0.01, "+30 Nerves")
		check_eq(_sim.car.speed, 0.0, "a head-on stops the car")

	# One oncoming vehicle is one head-on, however long it is.
	_check_single_head_on(&"truck")
	_check_single_head_on(&"tanker")

	# Lamps add up to a Wreck (the full rules arrive with T-FAULT-01).
	var capacity: int = tuning.i("lamp_capacity")
	var per_head_on: int = int(tuning.fi("hit_lamps", 2))
	var hit_ids: Array[int] = []
	_start(4, 1)
	var slow: TrafficSim.Vehicle = _sim.traffic.spawn(&"tuk_tuk", 1, 80.0, 30.0)
	_run_until_hit()
	hit_ids.append(_sim.collision.hit_vehicle_id)
	_sim.collision.immunity_left = 0.0
	_sim.gate.reset(4)
	_sim.car.speed = tuning.fi("gear_speeds", 3)
	_sim.traffic.spawn(&"tuk_tuk", 1, _sim.car.s + 60.0, 30.0)
	_run_until_hit()
	hit_ids.append(_sim.collision.hit_vehicle_id)
	check(_sim.faults.lamps >= tuning.i("lamp_capacity"), "two head-ons light every lamp")
	check(_sim.wrecked, "which is a Wreck")

	# A third hit after it, and what all three announced (GDD 13.6).
	_sim.collision.immunity_left = 0.0
	_sim.gate.reset(4)
	_sim.car.speed = tuning.fi("gear_speeds", 3)
	check(_run_until_hit(), "a wrecked car can still be hit")
	hit_ids.append(_sim.collision.hit_vehicle_id)
	check_eq(_sim.faults.lamps, capacity, "which lights no lamp beyond lamp_capacity")
	var events: Array[Dictionary] = _sim.drain_events()
	var hit_events: Array[Dictionary] = _of_type(events, "hit")
	check_eq(hit_ids[0], slow.id, "the first head-on is with the tuk-tuk ahead")
	if check_eq(hit_events.size(), 3, "three hits are three hit events"):
		var lit: Array[int] = [mini(per_head_on, capacity), mini(per_head_on, capacity - mini(per_head_on, capacity)), 0]
		for index: int in 3:
			_check_hit_event(hit_events[index], Collision.Hit.HEAD_ON, lit[index], hit_ids[index], "head-on %d" % (index + 1))
	var lamp_events: Array[Dictionary] = _of_type(events, "lamp_lit")
	if check_eq(lamp_events.size(), 2, "lamp_lit is announced for the two hits that lit lamps, not for the third"):
		check_eq(GameData.as_int(lamp_events[0].get("lamps"), -1), per_head_on, "after the first head-on 3 lamps are lit")
		check_eq(GameData.as_int(lamp_events[1].get("lamps"), -1), capacity, "after the second every lamp is")
	check_eq(_of_type(events, "wreck").size(), 1, "the Wreck is announced exactly once, however many hits follow")
	var order: PackedStringArray = []
	for event: Dictionary in events:
		var type: String = GameData.as_string(event.get("type"))
		if type == "hit" or type == "wreck":
			order.append(type)
	check_eq(",".join(order), "hit,hit,wreck,hit", "and it is announced with the hit that lit the last lamp")

	_check_bare_hits()


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
	var announced: Array[Dictionary] = _of_type(result.events, "close_call")
	if check_eq(announced.size(), 1, "one close call is one close_call event"):
		_check_close_call_event(announced[0], 1, base * tuning.fi("gear_cash_mult", 2), 1.0, 0, "the reference pass")
	check_eq(_of_type(result.events, "hit").size(), 0, "and no hit event")

	# Gear multipliers.
	result = _pass(4, &"truck", tuning.fi("gear_speeds", 3) - 60.0, gap_limit * 0.5, 1)
	check_near(result.cash, base * tuning.fi("gear_cash_mult", 3), 0.000001, "in fourth it pays x2")
	result = _pass(2, &"tuk_tuk", tuning.fi("gear_speeds", 1) - 30.0, gap_limit * 0.5, 1)
	check_near(result.cash, base * tuning.fi("gear_cash_mult", 1), 0.000001, "in second it pays x0.5")
	result = _pass(5, &"truck", tuning.fi("gear_speeds", 4) - 60.0, gap_limit * 0.5, 1)
	check_near(result.cash, base * tuning.fi("gear_cash_mult", 4), 0.000001, "in fifth it pays x3")

	# First gear: the pass counts and frays him, and pays nothing (GDD 5.2).
	result = _pass(1, &"tuk_tuk", tuning.fi("gear_speeds", 0) - 35.0, gap_limit * 0.5, 1)
	check_eq(result.close_calls, 1, "a close pass in first gear is a close call")
	check_near(tuning.fi("gear_cash_mult", 0), 0.0, 0.000001, "(first gear's close-call cash is x0)")
	check_near(result.cash, 0.0, 0.000001, "which pays nothing")
	check_near(result.nerves, tuning.f("close_call_nerves"), 0.01, "and still adds 2 Nerves")
	announced = _of_type(result.events, "close_call")
	if check_eq(announced.size(), 1, "it is announced like any other"):
		_check_close_call_event(announced[0], 1, 0.0, 1.0, 0, "the first-gear pass")

	# Not close calls.
	result = _pass(3, &"truck", third - 35.0, gap_limit + 0.1, 1)
	check_eq(result.close_calls, 0, "a pass with more than close_call_gap of gap is not a close call")
	check_near(result.cash, 0.0, 0.000001, "and pays nothing")
	check_eq(_of_type(result.events, "close_call").size(), 0, "and announces none")
	result = _pass(3, &"car", third - tuning.f("close_call_min_closing") + 5.0, gap_limit * 0.5, 1)
	check_eq(result.close_calls, 0, "a pass slower than close_call_min_closing is not a close call")
	result = _pass(3, &"truck", third - 35.0, -0.1, 1)
	check_eq(result.close_calls, 0, "a pass that touches is not a close call")
	check(result.lamps > 0, "it is a hit")

	# That one runs into the truck's back and never gets by. A pass that
	# touches: 0.3 m of air, one touch when the two are level, then on past it.
	result = _pass(3, &"truck", third - 35.0, gap_limit * 0.5, 1, true)
	check(result.touched and result.hits == 1, "touching the truck half-way along it is a hit")
	check(result.lamps > 0, "which lights lamps")
	check(result.passed, "and he goes on to pass it, as close and as fast as the reference pass")
	check_eq(result.close_calls, 0, "a pass with a contact in it is not a close call")
	check_near(result.cash, 0.0, 0.000001, "and pays nothing")
	check_eq(_of_type(result.events, "close_call").size(), 0, "and announces none")

	# The same touch inside hit_immunity: no hit, and still no close call.
	result = _pass(3, &"truck", third - 35.0, gap_limit * 0.5, 1, true, true)
	check(result.touched and result.passed, "the same pass with the touch inside hit_immunity")
	check_eq(result.hits, 0, "is no hit")
	check_eq(result.lamps, 0, "and lights no lamp")
	check_eq(result.close_calls, 0, "but a touch is a contact: still no close call")
	check_near(result.cash, 0.0, 0.000001, "and no cash")

	# The edge: exactly at the gap is not under it.
	result = _pass(3, &"truck", third - 35.0, gap_limit + 0.001, 1)
	check_eq(result.close_calls, 0, "a gap of close_call_gap is not under close_call_gap")
	result = _pass(3, &"truck", third - 35.0, gap_limit - 0.01, 1)
	check_eq(result.close_calls, 1, "just under it is")

	# Each pass is judged on its own: the same truck passed again, wide.
	_start(3, 1)
	var again: TrafficSim.Vehicle = _sim.traffic.spawn(&"truck", 2, 40.0, third - 35.0)
	var calls: int = 0
	for air: float in [gap_limit * 0.5, gap_limit + 0.5]:
		_sim.car.s = again.s - 40.0
		_held_x = again.x - again.half_width - _sim.car.half_width() - air
		for _tick: int in int(MAX_SECONDS / DT):
			_hold_x()
			_sim.step(_input)
			calls += _sim.collision.close_calls
			if _sim.car.s > again.s + 40.0:
				break
		if air < gap_limit:
			check_eq(calls, 1, "the truck passed closely: one close call")
		else:
			check_eq(calls, 1, "the same truck passed again with more than close_call_gap: no second one")

	# Oncoming: double.
	result = _pass(3, &"car", 100.0, gap_limit * 0.5, -1)
	check_eq(result.close_calls, 1, "passing an oncoming car closely is a close call")
	check_near(result.cash, base * tuning.fi("gear_cash_mult", 2) * tuning.f("close_call_oncoming_mult"), 0.000001, "an oncoming close call pays double")
	result = _pass(2, &"tuk_tuk", _type_speed(&"tuk_tuk", 0.0), gap_limit * 0.5, -1)
	check_eq(result.close_calls, 1, "passing a slow oncoming tuk-tuk closely in second gear is a close call")
	check_near(result.cash, base * tuning.fi("gear_cash_mult", 1) * tuning.f("close_call_oncoming_mult"), 0.000001, "it pays double because it is oncoming, however slow the meeting")

	# A taxi honks when passed closely.
	result = _pass(3, &"taxi", third - 35.0, gap_limit * 0.5, 1)
	var taxi: Dictionary = data.record("vehicles", "taxi")
	var honk: float = GameData.as_float(taxi.get("honk_nerves"))
	check_near(result.nerves, tuning.f("close_call_nerves") + GameData.as_float(taxi.get("honk_nerves")), 0.01, "a taxi passed closely honks: its honk_nerves on top")
	check_eq(result.close_calls, 1, "that pass is a close call as well")
	check_eq(_honks(result), 1, "and the honk is announced, once")

	# The honk is its own thing (GDD 5.5): fourth gear closes on a taxi in the
	# middle of its speed range (110 km/h) by 20, which is no close call, and
	# the taxi honks all the same.
	var fourth: float = tuning.fi("gear_speeds", 3)
	var taxi_speed: float = _type_speed(&"taxi", 0.5)
	check(honk > 0.0, "a taxi's honk frays him (GDD 5.5: +5 Nerves)")
	check(data.root("sfx").has("horn"), "there is a horn sound to announce it with")
	check(fourth > taxi_speed and fourth - taxi_speed < tuning.f("close_call_min_closing"), "fourth gear passes a taxi at its middle speed at under close_call_min_closing")
	result = _pass(4, &"taxi", taxi_speed, gap_limit * 0.5, 1)
	check(result.passed, "he does pass it")
	check_eq(result.close_calls, 0, "which is no close call")
	check_near(result.cash, 0.0, 0.000001, "and pays nothing")
	check_eq(_honks(result), 1, "but the taxi honks, once")
	check_near(result.judged_nerves, honk, 0.01, "and its honk adds honk_nerves, when the pass is judged")
	result = _pass(4, &"taxi", taxi_speed, gap_limit + 0.1, 1)
	check_eq(_honks(result), 0, "a taxi passed with more than close_call_gap does not honk")
	check_near(result.judged_nerves, 0.0, 0.01, "and adds nothing")
	result = _pass(4, &"taxi", taxi_speed, gap_limit * 0.5, 1, true)
	check(result.touched and result.passed and result.hits == 1, "a taxi touched on the way past is a hit")
	check_eq(_honks(result), 0, "and a contact is not a close pass: no honk")
	result = _pass(4, &"car", taxi_speed, gap_limit * 0.5, 1)
	check_eq(_honks(result), 0, "a car passed the same way does not honk: only taxis do")

	_check_wedding_honk()

	# Falling back from beside a vehicle is not passing it.
	_start(3, 1)
	var beside: TrafficSim.Vehicle = _sim.traffic.spawn(&"truck", 2, 4.0, third)
	_sim.car.x = beside.x - beside.half_width - _sim.car.half_width() - gap_limit * 0.5
	_input.rmb = true
	calls = 0
	for _tick: int in int(6.0 / DT):
		_hold_x()
		_sim.step(_input)
		calls += _sim.collision.close_calls
	_input.rmb = false
	check_eq(calls, 0, "dropping back from beside a vehicle is not a close call")

	# Nor does a taxi honk at a car that drops back from beside it.
	_start(3, 1)
	var cab: TrafficSim.Vehicle = _sim.traffic.spawn(&"taxi", 2, 2.0, third)
	_sim.car.x = cab.x - cab.half_width - _sim.car.half_width() - gap_limit * 0.5
	_input.rmb = true
	var nerves_at_parting: float = 0.0
	for _tick: int in int(6.0 / DT):
		_hold_x()
		var was_beside: bool = absf(cab.s - _sim.car.s) < cab.half_length + _sim.car.length() * 0.5
		var nerves_before: float = _sim.nerves.value
		_sim.step(_input)
		if was_beside and absf(cab.s - _sim.car.s) >= cab.half_length + _sim.car.length() * 0.5:
			nerves_at_parting = _sim.nerves.value - nerves_before
	_input.rmb = false
	check(_sim.car.s < cab.s - cab.half_length, "(he has dropped back behind the taxi)")
	check_eq(_honk_events(_sim.drain_events(), cab.id), 0, "a taxi he drops back from does not honk")
	check_near(nerves_at_parting, 0.0, 0.01, "and adds no Nerves")

	# Traffic has no test id of its own (GDD 5.5; DECISIONS D-005: a test may
	# check more than its text): its rules are held here.
	_check_lane_changes()
	_check_removal()
	_check_follow_rule()
	_check_sandbox_seeds()
	_check_bare_close_calls()
	_check_traffic_leftovers()


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

	# Each one is announced with what it paid and where the chain stands (GDD 13.6).
	var announced: Array[Dictionary] = _of_type(_sim.drain_events(), "close_call")
	if check_eq(announced.size(), count, "every close call of the row is a close_call event"):
		for index: int in count:
			_check_close_call_event(announced[index], 1, pays[index], minf(1.0 + step_by * float(index), cap), index, "close call %d of the chain" % (index + 1))

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
	announced = _of_type(_sim.drain_events(), "close_call")
	if check_eq(announced.size(), 1, "which is announced as the first of a new chain"):
		_check_close_call_event(announced[0], 1, base, 1.0, 0, "the close call after the pause")


# --- Collisions: the longer cases ---------------------------------------------

## GDD 5.6: "cannot be hit again for 0.8 s" holds for the rails as it does for
## vehicles: a guardrail touched inside hit_immunity lights no lamp.
func _check_edge_immunity() -> void:
	var immunity: float = tuning.f("hit_immunity")
	var per_scrape: int = int(tuning.fi("hit_lamps", 0))
	_start(3, 2)
	_touch_guardrail()
	check_eq(_sim.collision.hit, Collision.Hit.SCRAPE, "touching the guardrail is a scrape")
	check_eq(_sim.faults.lamps, per_scrape, "which lights 1 lamp")
	check_near(_sim.collision.immunity_left, immunity, DT, "and starts the immunity")
	var since: int = 0
	for part: float in [0.5, 0.9]:
		var at: int = roundi(immunity * part / DT)
		while since < at - 1:
			_sim.step(_input)
			since += 1
		_touch_guardrail()
		since += 1
		check_eq(_sim.car.edge_touched, CarSim.EDGE_RIGHT, "(the car is against the guardrail again)")
		check_eq(_sim.collision.hit, Collision.Hit.NONE, "a guardrail touched %d%% of the way through hit_immunity is not a hit" % roundi(part * 100.0))
		check_eq(_sim.faults.lamps, per_scrape, "and lights no lamp")
	while since < roundi(immunity / DT) + 2:
		_sim.step(_input)
		since += 1
	_touch_guardrail()
	check_eq(_sim.collision.hit, Collision.Hit.SCRAPE, "once hit_immunity is over the guardrail scrapes again")
	check_eq(_sim.faults.lamps, per_scrape * 2, "and lights another lamp")


## GDD 5.6: the immunity keeps a hit from counting; it does not let the car
## into a vehicle. One contact is one hit, and no push is longer than
## hit_pushback plus one tick of motion.
func _check_held_sideswipe() -> void:
	var third: float = tuning.fi("gear_speeds", 2)
	var immunity: float = tuning.f("hit_immunity")
	var pushback: float = tuning.f("hit_pushback")
	# The furthest the car moves sideways in one tick by itself, at full lock.
	var own_step: float = (tuning.f("lat_per_kmh") * third + tuning.f("crown_drift")) * DT

	# He turns into the truck beside him and keeps the wheel at full lock for
	# two immunities and more.
	_start(3, 1)
	var beside: TrafficSim.Vehicle = _sim.traffic.spawn(&"truck", 2, 0.0, third)
	_take_wheel()
	var hits: int = 0
	var hit_at: int = -1
	var deepest: float = 0.0
	var longest: float = 0.0
	var crossed: bool = false
	var sideways_at_hit: float = INF
	var widest_late: float = 0.0
	var ticks: int = int((immunity * 2.0 + 1.5) / DT)
	for tick: int in ticks:
		_turn_wheel(1.0)
		# The truck stays level with him: this is a contact from the side only.
		beside.s = _sim.car.s
		beside.cruise = _sim.car.speed
		var x_before: float = _sim.car.x
		_sim.step(_input)
		longest = maxf(longest, absf(_sim.car.x - x_before))
		deepest = maxf(deepest, _inside(beside))
		if _sim.car.x > beside.x:
			crossed = true
		if _sim.collision.hit != Collision.Hit.NONE:
			hits += 1
			if hit_at < 0:
				hit_at = tick
				sideways_at_hit = _sim.car.v_lat
		if hit_at >= 0 and float(tick - hit_at) * DT > immunity * 1.5:
			widest_late = maxf(widest_late, (beside.x - beside.half_width) - (_sim.car.x + _sim.car.half_width()))
	check_near(_sim.wheel.steer(), 1.0, 0.05, "(the wheel is at full lock)")
	if check(hit_at >= 0, "turning into the truck beside him hits it"):
		check(float(ticks - hit_at) * DT > immunity * 2.0, "(and the wheel stays there for two immunities more)")
		check_eq(sideways_at_hit, 0.0, "the hit stops his sideways motion")
		check(widest_late <= TOUCHING, "kept at it, he slides along the truck's side: an overlap that is no hit is only undone, he is not thrown off again (widest gap %s m)" % str(widest_late))
	check_eq(hits, 1, "held against the truck that hit him he is not hit again: one contact, one hit")
	check_eq(_sim.faults.lamps, int(tuning.fi("hit_lamps", 0)), "one scrape, one lamp")
	check(not crossed, "at full lock through the immunity and after it, the car never crosses the truck")
	check(deepest <= TOUCHING, "and never ends a tick inside it")
	check(longest <= pushback + own_step + TOUCHING, "no push is longer than hit_pushback plus one tick of motion (longest sideways move in a tick: %s m)" % str(longest))

	# The same wheel against a truck that has not hit him, while he is immune
	# from something else: the hit waits for the immunity to run out, and then
	# pushes him back out the side he came from.
	_start(3, 1)
	beside = _sim.traffic.spawn(&"truck", 2, 0.0, third)
	_sim.car.x = beside.x - beside.half_width - _sim.car.half_width() - own_step
	_sim.collision.immunity_left = immunity
	_take_wheel()
	hits = 0
	hit_at = -1
	deepest = 0.0
	longest = 0.0
	crossed = false
	var lamps_while_immune: int = 0
	for tick: int in int((immunity + 1.0) / DT):
		_turn_wheel(1.0)
		beside.s = _sim.car.s
		beside.cruise = _sim.car.speed
		var x_before: float = _sim.car.x
		_sim.step(_input)
		longest = maxf(longest, absf(_sim.car.x - x_before))
		deepest = maxf(deepest, _inside(beside))
		if _sim.car.x > beside.x:
			crossed = true
		if _sim.collision.hit != Collision.Hit.NONE:
			hits += 1
			if hit_at < 0:
				hit_at = tick
		if hit_at < 0:
			lamps_while_immune = _sim.faults.lamps
	check_eq(lamps_while_immune, 0, "pressing on a truck during hit_immunity lights no lamp")
	check(deepest <= TOUCHING, "and the car is kept out of it all the while")
	check(not crossed, "so it never comes out of the far side")
	if check(hit_at >= 0, "when hit_immunity runs out the truck he is pressing on hits him"):
		check_near(float(hit_at) * DT, immunity, 2.0 * DT, "at that moment, not later")
	check_eq(hits, 1, "once")
	check(longest <= pushback + own_step + TOUCHING, "and that hit pushes him no further than hit_pushback plus one tick of motion (longest: %s m)" % str(longest))


## Running into a back and staying on it is one contact: one hit. Held behind
## the car ahead he is no faster than it is, so what follows him sees his true
## speed and does not ram him (DECISIONS D-023).
func _check_held_rear_end() -> void:
	var third: float = tuning.fi("gear_speeds", 2)
	_start(3, 1)
	var ahead: TrafficSim.Vehicle = _sim.traffic.spawn(&"car", 1, 40.0, third - 25.0)
	var behind: TrafficSim.Vehicle = _sim.traffic.spawn(&"taxi", 1, -20.0, _type_speed(&"taxi", 1.0))
	if not check(_run_until_hit(), "driving into a car 25 km/h slower hits it"):
		return
	check_eq(_sim.collision.hit_vehicle_id, ahead.id, "(it is the car ahead that he hits)")
	check_near(_sim.car.speed, ahead.speed, 0.000001, "which leaves him at its speed")
	# He keeps third gear for four seconds more.
	var lane_x: float = _sim.car.x
	var more_hits: int = 0
	var deepest: float = 0.0
	var pressed: int = 0
	var faster_by: float = 0.0
	var closest: float = INF
	for _tick: int in int(4.0 / DT):
		_sim.car.x = lane_x
		_sim.step(_input)
		if _sim.collision.hit != Collision.Hit.NONE:
			more_hits += 1
		deepest = maxf(deepest, _deepest_inside())
		closest = minf(closest, (_sim.car.s - _sim.car.length() * 0.5) - (behind.s + behind.half_length))
		if (ahead.s - ahead.half_length) - (_sim.car.s + _sim.car.length() * 0.5) <= TOUCHING:
			pressed += 1
			faster_by = maxf(faster_by, _sim.car.speed - ahead.speed)
	check(pressed > int(2.0 / DT), "(in third gear he is back on its bumper and stays there)")
	check_eq(more_hits, 0, "pressing on the car he ran into is the same contact: no second hit")
	check(deepest <= TOUCHING, "he is never left inside it")
	check(faster_by <= 0.000001, "held behind it he is no faster than it is")
	check(closest >= 0.0, "and the taxi behind him never touches him")
	check_near(behind.speed, ahead.speed, tuning.f("accel") * DT + 0.000001, "it takes his true speed: that of the car he is held behind")


## A push along the road ends clear as well. With a vehicle right behind him
## he stops against it if he fits between the two; either way he is never
## left inside one.
func _check_boxed_in() -> void:
	var third: float = tuning.fi("gear_speeds", 2)
	for room: float in [0.3, 0.01]:
		_start(3, 1)
		var ahead: TrafficSim.Vehicle = _sim.traffic.spawn(&"car", 1, 40.0, third - 20.0)
		var follower: TrafficSim.Vehicle = _sim.traffic.spawn(&"car", 1, 0.0, third)
		# He drives a little right of the car ahead and the follower a little
		# right of him: it is behind him and takes his speed, not the speed of
		# the car beyond him.
		_sim.car.x = ahead.x + ahead.half_width
		follower.x = ahead.x + ahead.half_width + follower.half_width + 0.1
		follower.s = _sim.car.s - _sim.car.length() * 0.5 - follower.half_length - room
		var what: String = "with a car %s m behind him" % str(room)
		if not check(_run_until_hit(), "%s, driving into a slower car hits it" % what):
			continue
		check_eq(_sim.collision.hit_vehicle_id, ahead.id, "%s: (it is the car ahead that he hits)" % what)
		check_near(follower.speed, third, 0.000001, "%s: (which had kept up with him)" % what)
		check(_deepest_inside() <= TOUCHING, "%s: the push leaves him inside neither car (deepest %s m)" % [what, str(_deepest_inside())])
		if room > tuning.f("hit_pushback") * 0.5:
			check(_sim.car.s > follower.s and _sim.car.s < ahead.s, "%s: he fits between the two and stays there" % what)
			var behind_him: float = (_sim.car.s - _sim.car.length() * 0.5) - (follower.s + follower.half_length)
			check(absf(behind_him) <= TOUCHING, "%s: against the car behind him (%s m from it)" % [what, str(behind_him)])
		var deepest: float = 0.0
		var lane_x: float = _sim.car.x
		for _tick: int in int(tuning.f("hit_immunity") * 0.5 / DT):
			_sim.car.x = lane_x
			_sim.step(_input)
			deepest = maxf(deepest, _deepest_inside())
		check(deepest <= TOUCHING, "%s: nor in the ticks that follow (deepest %s m)" % [what, str(deepest)])


## Two vehicles at once. Held behind a minibus he drifts into the side of a
## tanker in the next lane: each is dealt with in its own right. The tanker
## hits him and pushes him back out sideways; nothing throws him along the
## road, past either of them.
func _check_two_at_once() -> void:
	var third: float = tuning.fi("gear_speeds", 2)
	_start(3, 1)
	var minibus: TrafficSim.Vehicle = _sim.traffic.spawn(&"minibus", 1, 40.0, third - 20.0)
	var tanker: TrafficSim.Vehicle = _sim.traffic.spawn(&"tanker", 2, 0.0, _type_speed(&"tanker", 0.0))
	# He straddles the line: 0.3 m short of the tanker's lane position.
	var beside_tanker: float = tanker.x - tanker.half_width - _sim.car.half_width()
	_sim.car.x = beside_tanker - 0.3
	if not check(_run_until_hit(), "driving into the minibus hits it"):
		return
	check_eq(_sim.collision.hit_vehicle_id, minibus.id, "(it is the minibus that he hits)")
	# Back on its bumper, the tanker beside him, he drifts right.
	var lane_x: float = _sim.car.x
	var hit_by: Array[int] = []
	var kinds: Array[int] = []
	var pushed_to: float = INF
	var thrown: float = 0.0
	var deepest: float = 0.0
	var calls: int = 0
	for tick: int in int(3.0 / DT):
		if tick >= int(1.0 / DT) and hit_by.is_empty():
			lane_x += 0.01
		_sim.car.x = lane_x
		tanker.s = _sim.car.s
		var behind_before: float = minibus.s - _sim.car.s
		_sim.step(_input)
		thrown = maxf(thrown, absf((minibus.s - _sim.car.s) - behind_before))
		deepest = maxf(deepest, _deepest_inside())
		calls += _sim.collision.close_calls
		if _sim.collision.hit != Collision.Hit.NONE:
			hit_by.append(_sim.collision.hit_vehicle_id)
			kinds.append(int(_sim.collision.hit))
			pushed_to = _sim.car.x
			lane_x = _sim.car.x
	check_eq(hit_by.size(), 1, "drifting into the tanker beside him while held behind the minibus is one more hit")
	if hit_by.size() == 1:
		check_eq(hit_by[0], tanker.id, "by the tanker")
		check_eq(kinds[0], int(_sim.collision.classify(absf(tanker.closing_speed(minibus.speed)), false)), "of the class their speeds make it")
	check_near(pushed_to, beside_tanker - tuning.f("hit_pushback"), 0.01, "which pushes him hit_pushback back out sideways")
	check(_sim.car.s < minibus.s, "he is still behind the minibus")
	check(thrown <= tuning.f("hit_pushback") + 0.1, "nothing throws him along the road (largest move against the minibus in a tick: %s m)" % str(thrown))
	check(deepest <= TOUCHING, "and he is never left inside either")
	check_eq(calls, 0, "nor is any of it a close call")


## GDD 5.6 "pushed 0.5 m clear", 5.1 and 9.2 (MERGE): a vehicle that changes
## into the lane he is in, beside the median barrier, hits him once. He is
## never put through the barrier and never left inside a vehicle.
func _check_merge_beside_barrier() -> void:
	for type: StringName in [&"truck", &"tanker", &"minibus"]:
		for slower_by: float in [35.0, 20.0, 0.0]:
			_check_one_merge(type, slower_by, 0.0)
	# The same with the truck's middle 6 m ahead of his and 6 m behind it when
	# its side reaches him.
	var put_in_front: int = 0
	for lead: float in [6.0, -6.0]:
		for slower_by: float in [35.0, 20.0, 0.0]:
			if _check_one_merge(&"truck", slower_by, lead):
				put_in_front += 1
	check(put_in_front > 0, "(with the truck's middle behind his and no room beside it, he is put in front of it)")


## One vehicle, `slower_by` km/h slower than he is, changes from lane 1 into
## lane 0, where he is; its middle is `lead` metres ahead of his when its
## side reaches him. He holds his line and does nothing else for 8 s.
## Returns true when he was put in front of the vehicle on the way.
func _check_one_merge(type: StringName, slower_by: float, lead: float) -> bool:
	var third: float = tuning.fi("gear_speeds", 2)
	_start(3, 0)
	_sim.set_road(3, true)
	var merging: TrafficSim.Vehicle = _sim.traffic.spawn(type, 1, 0.0, third - slower_by)
	var air: float = absf(merging.x - _sim.car.x) - merging.half_width - _sim.car.half_width()
	var until_contact: float = tuning.f("signal_time") + tuning.f("lane_change_time") * air / tuning.f("lane_width")
	merging.s = _sim.car.s + lead + slower_by * KMH_TO_MS * until_contact
	_sim.traffic.plan_lane_change(merging, merging.s, 0)
	var barrier: float = _sim.car.left_limit_x()
	var hits: int = 0
	var left_most: float = INF
	var deepest: float = 0.0
	var put_in_front: bool = false
	var nearest_behind: float = INF
	for _tick: int in int(8.0 / DT):
		_cancel_crown()
		var s_before: float = _sim.car.s
		var faster: float = _sim.car.speed
		_sim.step(_input)
		if _sim.collision.hit != Collision.Hit.NONE:
			hits += 1
		left_most = minf(left_most, _sim.car.x - _sim.car.half_width())
		deepest = maxf(deepest, _deepest_inside())
		# Further along the road than his own driving took him: put in front.
		faster = maxf(faster, _sim.car.speed)
		if _sim.car.s - s_before > faster * KMH_TO_MS * DT + tuning.f("hit_pushback"):
			put_in_front = true
		# From then on: how far behind his bumper the vehicle is.
		if put_in_front:
			nearest_behind = minf(nearest_behind, (_sim.car.s - _sim.car.length() * 0.5) - (merging.s + merging.half_length))
	var what: String = "a %s %d km/h slower changing into his lane beside the barrier, %d m ahead of him" % [type, roundi(slower_by), roundi(lead)]
	check_eq(merging.lane, 0, "%s: (it ends up in lane 0)" % what)
	if put_in_front:
		check(nearest_behind >= tuning.f("hit_pushback") - TOUCHING, "%s: put in front of it he is hit_pushback clear of its bumper, so it follows him and does not push him on (nearest %s m)" % [what, str(nearest_behind)])
	check_eq(hits, 1, "%s hits him once" % what)
	check_eq(_of_type(_sim.drain_events(), "hit").size(), 1, "%s: one hit event" % what)
	check(left_most > barrier, "%s: he is never pushed through the median barrier (left edge %s, barrier %s)" % [what, str(left_most), str(barrier)])
	check(left_most >= barrier + tuning.f("hit_pushback") - TOUCHING, "%s: nor left nearer to it than a touch of the barrier itself would leave him (%s m from it)" % [what, str(left_most - barrier)])
	check(deepest <= TOUCHING, "%s: he is never left inside a vehicle (deepest %s m)" % [what, str(deepest)])
	check(not _sim.wrecked, "%s: and it is no Wreck" % what)
	return put_in_front


## The same with a truck where the barrier was: he is between a truck on his
## left and one that changes into his lane from the right.
func _check_sandwich() -> void:
	var truck_speed: float = _type_speed(&"truck", 0.5)
	for gear: int in [2, 3]:
		for brakes: bool in [true, false]:
			_start(gear, 1)
			var on_left: TrafficSim.Vehicle = _sim.traffic.spawn(&"truck", 0, 0.0, truck_speed)
			var merging: TrafficSim.Vehicle = _sim.traffic.spawn(&"truck", 2, 0.0, truck_speed)
			var air: float = absf(merging.x - _sim.car.x) - merging.half_width - _sim.car.half_width()
			var until_contact: float = tuning.f("signal_time") + tuning.f("lane_change_time") * air / tuning.f("lane_width")
			# At first contact he is 4 m behind the middle of the two trucks.
			var start_s: float = _sim.car.s + 4.0 + (_sim.car.speed - truck_speed) * KMH_TO_MS * until_contact
			on_left.s = start_s
			merging.s = start_s
			_sim.traffic.plan_lane_change(merging, merging.s, 1)
			var hits: int = 0
			var first_hit: int = -1
			var by_left_truck: int = 0
			var deepest: float = 0.0
			for tick: int in int(12.0 / DT):
				_cancel_crown()
				_input.rmb = brakes and first_hit >= 0 and float(tick - first_hit) * DT >= REACTION
				_sim.step(_input)
				if _sim.collision.hit != Collision.Hit.NONE:
					hits += 1
					if first_hit < 0:
						first_hit = tick
					if _sim.collision.hit_vehicle_id == on_left.id:
						by_left_truck += 1
				deepest = maxf(deepest, _deepest_inside())
			_input.rmb = false
			var what: String = "in gear %d between a truck and one changing into his lane, %s" % [gear, "braking after the hit" if brakes else "doing nothing"]
			check_eq(merging.lane, 1, "%s: (the truck ends up in his lane)" % what)
			check_eq(hits, 1, "%s: he is hit once" % what)
			check_eq(by_left_truck, 0, "%s: he is never thrown into the truck that holds its lane" % what)
			check(deepest <= TOUCHING, "%s: no push leaves him inside either truck (deepest %s m)" % [what, str(deepest)])
			check(not _sim.wrecked, "%s: and it is no Wreck" % what)


## GDD 5.6 and 6: one oncoming vehicle met head-on is one hit of 3 lamps,
## however long it is and however long it goes on pushing. Never a Wreck.
func _check_single_head_on(type: StringName) -> void:
	var per_head_on: int = int(tuning.fi("hit_lamps", 2))
	_start(3, 0)
	_sim.set_road(1, false)
	_sim.car.x = _sim.traffic.lane_center(-1)
	var oncoming: TrafficSim.Vehicle = _sim.traffic.spawn(type, -1, 90.0, _type_speed(type, 1.0), -1)
	if not check(_run_until_hit(), "meeting an oncoming %s in its lane hits it" % type):
		return
	check_eq(_sim.collision.hit, Collision.Hit.HEAD_ON, "an oncoming %s is a head-on" % type)
	check_eq(_sim.faults.lamps, per_head_on, "an oncoming %s: 3 lamps" % type)

	# He stays in its way for two seconds more.
	var lane_x: float = _sim.car.x
	var more_hits: int = 0
	var deepest: float = 0.0
	var driven_through: bool = false
	for _tick: int in int(2.0 / DT):
		_sim.car.x = lane_x
		_sim.step(_input)
		if _sim.collision.hit != Collision.Hit.NONE:
			more_hits += 1
		deepest = maxf(deepest, _inside(oncoming))
		if _sim.car.s > oncoming.s:
			driven_through = true
	check_eq(more_hits, 0, "the %s that hit him does not hit him again as it drives on" % type)
	check_eq(_sim.faults.lamps, per_head_on, "one head-on with an oncoming %s is 3 lamps, two seconds later too" % type)
	check(not _sim.wrecked, "a single head-on with a %s is never a Wreck" % type)
	check(deepest <= TOUCHING, "the car is never left inside the %s" % type)
	check(not driven_through, "and the %s never drives through it" % type)

	# Then he gets out of its way and it goes by.
	lane_x = oncoming.x + oncoming.half_width + _sim.car.half_width() + tuning.f("close_call_gap") * 0.5
	for _tick: int in int(4.0 / DT):
		_sim.car.x = lane_x
		_sim.step(_input)
		if _sim.car.s > oncoming.s + 40.0:
			break
	var events: Array[Dictionary] = _sim.drain_events()
	check(_sim.car.s > oncoming.s + oncoming.half_length, "(the %s has gone by)" % type)
	check_eq(_of_type(events, "hit").size(), 1, "from the head-on until the %s is gone: exactly one hit event" % type)
	check_eq(_sim.faults.lamps, per_head_on, "and still 3 lamps")
	check_eq(_of_type(events, "wreck").size(), 0, "and no wreck event")
	check_eq(_of_type(events, "close_call").size(), 0, "a %s that hit him is no close call as it goes by" % type)


# --- Traffic (GDD 5.5) --------------------------------------------------------

## A lane change starts where the beat planned it, is signalled for
## signal_time (late signallers: late_signal_time), takes lane_change_time and
## ends in the middle of the new lane.
func _check_lane_changes() -> void:
	var signal_ticks: int = roundi(tuning.f("signal_time") / DT)
	var late_ticks: int = roundi(tuning.f("late_signal_time") / DT)
	var move_ticks: int = roundi(tuning.f("lane_change_time") / DT)
	check(late_ticks < signal_ticks, "late signallers signal for less time than the others")
	var plan_at: float = 10.0
	for late: bool in [false, true]:
		for to_lane: int in [0, 2]:
			var traffic: TrafficSim = TrafficSim.new()
			traffic.configure(data)
			var mover: TrafficSim.Vehicle = traffic.spawn(&"car", 1, 0.0, _type_speed(&"car", 0.0))
			traffic.plan_lane_change(mover, plan_at, to_lane, late)
			var from_x: float = mover.x
			var to_x: float = traffic.lane_center(to_lane)
			var signal_tick: int = -1
			var move_tick: int = -1
			var done_tick: int = -1
			var on_time: bool = false
			var signalled: int = 0
			var half_way_x: float = INF
			var strayed: bool = false
			for tick: int in int(10.0 / DT):
				var s_before: float = mover.s
				var x_before: float = mover.x
				# The player is far behind and out of every lane: nothing to follow.
				traffic.step(DT, -2000.0, -100.0, 0.0)
				if signal_tick < 0 and mover.signalling != 0:
					signal_tick = tick
					signalled = mover.signalling
					on_time = s_before < plan_at and mover.s >= plan_at
				if move_tick < 0 and mover.x != from_x:
					move_tick = tick
				if move_tick >= 0 and (mover.x - x_before) * (to_x - from_x) < 0.0:
					strayed = true
				if move_tick >= 0 and tick - move_tick + 1 == move_ticks / 2:
					half_way_x = mover.x
				if signal_tick >= 0 and mover.signalling == 0:
					done_tick = tick
					break
			var what: String = "a %slane change from lane 1 to lane %d" % ["late-signalled " if late else "", to_lane]
			if not check(signal_tick >= 0 and move_tick >= 0 and done_tick >= 0, "%s is signalled, made and finished" % what):
				continue
			check(on_time, "%s: the signal starts as the vehicle reaches the place the beat planned" % what)
			check_eq(signalled, signi(to_lane - 1), "%s: it signals to the side it will move to" % what)
			check_eq(move_tick - signal_tick, late_ticks if late else signal_ticks, "%s: ticks of signal before it moves" % what)
			check_eq(done_tick - move_tick + 1, move_ticks, "%s: ticks the move takes" % what)
			check_near(half_way_x, (from_x + to_x) * 0.5, 0.000001, "%s: half-way through the time it is half-way across" % what)
			check(not strayed, "%s: it only ever moves toward the new lane" % what)
			check_eq(mover.lane, to_lane, "%s: it ends in the new lane" % what)
			check_near(mover.x, to_x, 0.000001, "%s: in the middle of it" % what)
			check(not mover.changing and mover.signalling == 0, "%s: with the signal off" % what)

	# Nothing is planned, nothing happens.
	var quiet: TrafficSim = TrafficSim.new()
	quiet.configure(data)
	var holder: TrafficSim.Vehicle = quiet.spawn(&"car", 1, 0.0, _type_speed(&"car", 0.0))
	for _tick: int in int(5.0 / DT):
		quiet.step(DT, -2000.0, -100.0, 0.0)
	check(holder.lane == 1 and holder.x == quiet.lane_center(1) and holder.signalling == 0, "a vehicle with no lane change planned holds its lane")


## Vehicles are removed despawn_behind behind the player: not before the
## whole vehicle is that far back, and at once when it is. Both directions.
func _check_removal() -> void:
	var behind: float = tuning.f("despawn_behind")
	var third: float = tuning.fi("gear_speeds", 2)
	for direction: int in [1, -1]:
		var traffic: TrafficSim = TrafficSim.new()
		traffic.configure(data)
		var lane: int = 1 if direction > 0 else -1
		var left_behind: TrafficSim.Vehicle = traffic.spawn(&"truck", lane, 30.0, _type_speed(&"truck", 0.0), direction)
		var far_ahead: TrafficSim.Vehicle = traffic.spawn(&"truck", lane, 5000.0, 0.0, direction)
		# How much further back one tick takes it.
		var one_tick: float = (third - left_behind.speed * float(direction)) * KMH_TO_MS * DT
		var player_s: float = 0.0
		var removed_at: float = -1.0
		var kept_beyond: bool = false
		for _tick: int in int(30.0 / DT):
			player_s += third * KMH_TO_MS * DT
			traffic.step(DT, player_s, -100.0, third)
			# How far its nearest end is behind the player's middle.
			var back: float = player_s - (left_behind.s + left_behind.half_length)
			if not traffic.vehicles.has(left_behind):
				removed_at = back
				break
			if back > behind:
				kept_beyond = true
				break
		var what: String = "a vehicle going his way" if direction > 0 else "an oncoming vehicle"
		check(not kept_beyond, "%s is not kept once the whole of it is more than despawn_behind behind him" % what)
		if check(removed_at >= 0.0, "%s is removed when it has fallen behind" % what):
			check(removed_at > behind and removed_at <= behind + one_tick, "%s is removed at despawn_behind, not before (it went at %s m)" % [what, str(removed_at)])
		check(traffic.vehicles.has(far_ahead), "a vehicle ahead of him is never removed")


## DECISIONS D-023: traffic never rams. A vehicle that catches another in its
## lane, or the player from behind, takes its speed within traffic_follow_gap.
## Oncoming vehicles do the same among themselves; they do not react to him.
func _check_follow_rule() -> void:
	var follow_gap: float = tuning.f("traffic_follow_gap")
	var slow: float = _type_speed(&"truck", 0.0)
	var fast: float = _type_speed(&"taxi", 1.0)
	for direction: int in [1, -1]:
		var traffic: TrafficSim = TrafficSim.new()
		traffic.configure(data)
		var lane: int = 1 if direction > 0 else -1
		var heading: float = float(direction)
		# The taxi starts 100 m behind the truck, along their own way.
		var truck: TrafficSim.Vehicle = traffic.spawn(&"truck", lane, 500.0, slow, direction)
		var chaser: TrafficSim.Vehicle = traffic.spawn(&"taxi", lane, 500.0 - 100.0 * heading, fast, direction)
		var beside: TrafficSim.Vehicle = traffic.spawn(&"taxi", lane + direction, 500.0 - 100.0 * heading, fast, direction)
		var overlapping: int = 0
		var least: float = INF
		var free_speed: float = 0.0
		for tick: int in int(20.0 / DT):
			# The player is far behind them all and out of every lane.
			traffic.step(DT, -2000.0, -100.0, 0.0)
			var air: float = (truck.s - chaser.s) * heading - truck.half_length - chaser.half_length
			least = minf(least, air)
			if air < 0.0:
				overlapping += 1
			if tick == int(1.0 / DT):
				free_speed = chaser.speed
		var what: String = "going his way" if direction > 0 else "oncoming"
		check_near(free_speed, fast, 0.000001, "%s: a vehicle with a clear road ahead holds its set speed" % what)
		check_eq(overlapping, 0, "%s: a faster vehicle never drives into the slower one ahead in its lane" % what)
		check_near(chaser.speed, truck.speed, 0.000001, "%s: it takes the slower one's speed" % what)
		check(least >= 0.0 and least < follow_gap, "%s: and stays within traffic_follow_gap behind it (%s m)" % [what, str(least)])
		check_near(truck.speed, slow, 0.000001, "%s: the one ahead keeps its own speed" % what)
		check_near(beside.speed, fast, 0.000001, "%s: a vehicle in the next lane is not held up" % what)
		check((beside.s - truck.s) * heading > 0.0, "%s: and goes by" % what)

	# The player, braking to a stop in front of a taxi: it takes his speed and never touches him.
	_start(3, 1)
	var behind: TrafficSim.Vehicle = _sim.traffic.spawn(&"taxi", 1, -30.0, fast)
	var lane_x: float = _sim.car.x
	var hits: int = 0
	var closest: float = INF
	for tick: int in int(8.0 / DT):
		_input.rmb = tick >= int(1.0 / DT)
		_sim.car.x = lane_x
		_sim.step(_input)
		closest = minf(closest, (_sim.car.s - _sim.car.length() * 0.5) - (behind.s + behind.half_length))
		if _sim.collision.hit != Collision.Hit.NONE:
			hits += 1
	_input.rmb = false
	check_eq(_sim.car.speed, 0.0, "(he has braked to a stop)")
	check_eq(hits, 0, "a taxi behind the braking player never rams him")
	check(closest >= 0.0 and closest < follow_gap, "it closes to within traffic_follow_gap and no nearer than his bumper (%s m)" % str(closest))
	check_near(behind.speed, _sim.car.speed, 0.000001, "and takes his speed: it has stopped too")

	# An oncoming vehicle does not react to the player: it has its own lane.
	var road: TrafficSim = TrafficSim.new()
	road.configure(data)
	var oncoming: TrafficSim.Vehicle = road.spawn(&"car", -1, 30.0, _type_speed(&"car", 0.0), -1)
	var gap_to_him: float = INF
	for _tick: int in int(0.7 / DT):
		road.step(DT, 0.0, road.lane_center(-1), 0.0)
		gap_to_him = (oncoming.s - oncoming.half_length) - _sim.car.length() * 0.5
	check(gap_to_him > 0.0 and gap_to_him < follow_gap, "(an oncoming car is within traffic_follow_gap of the player standing in its lane)")
	check_near(oncoming.speed, _type_speed(&"car", 0.0), 0.000001, "an oncoming vehicle does not slow for the player")


## The sandbox road draws its traffic from the Telling seed (GDD 1.3, 13.3).
func _check_sandbox_seeds() -> void:
	var first: String = _sandbox_traffic(1)
	check(first.count("\n") >= 2, "the sandbox road spawns traffic")
	check_eq(_sandbox_traffic(1), first, "the same seed gives the same traffic")
	check(_sandbox_traffic(2) != first, "another seed gives different traffic")


## The vehicles on the sandbox road after 20 s in third gear, one per line.
func _sandbox_traffic(telling_seed: int) -> String:
	var sim: DriveSim = DriveSim.new(fresh_data())
	sim.reseed(telling_seed)
	sim.free_traffic_per_km = tuning.f("free_traffic_per_km")
	sim.gate.reset(3)
	sim.car.reset(1, 3)
	var input: DriveInput = DriveInput.new()
	var lane_x: float = sim.car.x
	for _tick: int in int(20.0 / DT):
		sim.car.x = lane_x
		sim.step(input)
	var out: String = ""
	for vehicle: TrafficSim.Vehicle in sim.traffic.vehicles:
		out += "%s lane %d at %.6f m doing %.6f\n" % [vehicle.type_id, vehicle.lane, vehicle.s, vehicle.cruise]
	return out


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
var _hit_tick_nerves: float = 0.0


## Call before each step: cancels the crown so a pass is made at a constant
## sideways gap. The step adds one tick of crown drift before it looks for
## collisions, so the car is set that much to the left of where it is held.
func _hold_x() -> void:
	if _held_x == INF:
		_held_x = _sim.car.x
	_sim.car.x = _held_x - _crown_this_tick()


## Call before each step: takes this tick's crown drift off beforehand. Unlike
## _hold_x it keeps what a push did: a driver who holds his line, wherever
## the last hit left him.
func _cancel_crown() -> void:
	_sim.car.x -= _crown_this_tick()


## How far the crown moves the car in one tick at its speed: all of
## crown_drift from drift_fade_speed up, less below it, nothing at rest
## (DECISIONS D-028).
func _crown_this_tick() -> float:
	return tuning.f("crown_drift") * _sim.car.drift_share() * DT


## Drives straight on until something is hit. `_hit_tick_nerves` is then what
## that one tick added to Nerves: the hit itself, give or take one tick of
## the ambient rates of GDD 6.1 (under a hundredth of a point).
func _run_until_hit() -> bool:
	for _tick: int in int(MAX_SECONDS / DT):
		var lane_x: float = _sim.car.x
		var nerves_before: float = _sim.nerves.value
		_sim.step(_input)
		if _sim.collision.hit != Collision.Hit.NONE:
			_hit_tick_nerves = _sim.nerves.value - nerves_before
			return true
		_sim.car.x = lane_x
	return false


## Passes one vehicle with `gap` metres of air between the two (negative
## overlaps). `direction` -1 is an oncoming vehicle. Returns what it earned.
## With `touch` the car is put TOUCH_DEPTH into the vehicle's side for one
## tick when the two are level (`immune`: inside hit_immunity), and the gear
## and speed a hit took are given back, so that only the contact differs
## from a clean pass.
func _pass(gear: int, type: StringName, vehicle_speed: float, gap: float, direction: int, touch: bool = false, immune: bool = false) -> PassResult:
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
	var result: PassResult = PassResult.new()
	result.vehicle_id = vehicle.id
	var judged_after_overlap: bool = true
	var was_along: bool = false
	for _tick: int in int(MAX_SECONDS / DT):
		_hold_x()
		if touch and not result.touched and absf(vehicle.s - _sim.car.s) < 1.0:
			result.touched = true
			if immune:
				_sim.collision.immunity_left = tuning.f("hit_immunity")
			_sim.car.x -= side * (gap + TOUCH_DEPTH)
		var nerves_before: float = _sim.nerves.value
		_sim.step(_input)
		var along: bool = absf(vehicle.s - _sim.car.s) < vehicle.half_length + _sim.car.length() * 0.5
		if was_along and not along:
			result.judged_nerves = _sim.nerves.value - nerves_before
		was_along = along
		if _sim.collision.hit != Collision.Hit.NONE:
			result.hits += 1
			if touch:
				_sim.gate.reset(gear)
				_sim.car.speed = _sim.car.cruise_speed(gear)
		if _sim.collision.close_calls > 0:
			# What this one tick added: the close call, give or take one tick
			# of the ambient rates of GDD 6.1 (under a hundredth of a point).
			result.nerves += _sim.nerves.value - nerves_before
			result.close_calls += _sim.collision.close_calls
			if along:
				judged_after_overlap = false
		if _sim.car.s > vehicle.s + 40.0:
			break
	result.cash = _sim.cash - cash_before
	result.lamps = _sim.faults.lamps
	result.judged_after_overlap = judged_after_overlap and result.close_calls > 0
	result.passed = _sim.car.s > vehicle.s
	result.events = _sim.drain_events()
	return result


## The hand on the wheel from the first tick (a set-up, as GDD 4.3 grips it).
func _take_wheel() -> void:
	_sim.hand.start_gripping(0.0)
	_sim.wheel.grip()
	_input.lmb = true


## Call before each step: moves the pointer so that the wheel is turned to
## `lock` of full lock (-1 to 1) and stays there.
func _turn_wheel(lock: float) -> void:
	var wanted: float = _sim.wheel.max_angle() * lock
	_input.pointer_delta = Vector2((wanted - _sim.wheel.command) / tuning.f("steer_deg_per_px"), 0.0)


## One tick with the car set against the guardrail.
func _touch_guardrail() -> void:
	_sim.car.x = _sim.car.guardrail_x() - _sim.car.half_width() + 0.01
	_sim.step(_input)


## How far the car's rectangle is inside a vehicle's, in metres (0 when the
## two are clear of each other).
func _inside(vehicle: TrafficSim.Vehicle) -> float:
	var depth_s: float = vehicle.half_length + _sim.car.length() * 0.5 - absf(vehicle.s - _sim.car.s)
	var depth_x: float = vehicle.half_width + _sim.car.half_width() - absf(vehicle.x - _sim.car.x)
	return maxf(minf(depth_s, depth_x), 0.0)


## The deepest the car is inside any vehicle on the road.
func _deepest_inside() -> float:
	var deepest: float = 0.0
	for vehicle: TrafficSim.Vehicle in _sim.traffic.vehicles:
		deepest = maxf(deepest, _inside(vehicle))
	return deepest


## A speed out of a vehicle type's own range (GDD 5.5): 0 its slowest, 1 its
## fastest.
func _type_speed(type: StringName, share: float) -> float:
	var speeds: Array = GameData.as_array(data.record("vehicles", String(type)).get("speed_kmh"))
	return lerpf(GameData.as_float(speeds[0]), GameData.as_float(speeds[1]), share)


## The events of one type among `events`, oldest first.
func _of_type(events: Array[Dictionary], type: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for event: Dictionary in events:
		if GameData.as_string(event.get("type")) == type:
			out.append(event)
	return out


## How often a vehicle's horn was announced: sfx_requested events with the
## horn sound's id and the id of the vehicle that sounded it.
func _honk_events(events: Array[Dictionary], vehicle_id: int) -> int:
	var count: int = 0
	for event: Dictionary in _of_type(events, "sfx_requested"):
		if GameData.as_string(event.get("id")) == "horn" and GameData.as_int(event.get("vehicle"), -1) == vehicle_id:
			count += 1
	return count


func _honks(result: PassResult) -> int:
	return _honk_events(result.events, result.vehicle_id)


## The payload of a hit event (GDD 13.6): its class, the lamps it lit and the
## vehicle (0 for a rail).
## GDD 9.4: passing a car of a wedding motorcade closely earns a happy honk:
## -5 Nerves instead of the close call's +2.
func _check_wedding_honk() -> void:
	var modifier: Dictionary = data.record("modifiers", "wedding")
	var happy: float = GameData.as_float(modifier.get("honk_nerves"))
	check_near(happy, -5.0, 0.000001, "GDD 9.4: a happy honk is -5 Nerves")
	var gap_limit: float = tuning.f("close_call_gap")
	var speed: float = GameData.as_float(modifier.get("speed_kmh"))
	var third: float = tuning.fi("gear_speeds", 2)
	check(third - speed >= tuning.f("close_call_min_closing"), "(third gear passes a wedding car fast enough for a close call)")
	for air: float in [gap_limit * 0.5, gap_limit + 0.1]:
		_start(3, 1)
		_sim.begin_leg({
			"leg": "open_road", "act": 2, "seed": 1, "modifier": "wedding", "lanes": 3, "divided": true,
			"condition": "clear", "par_s": 90.0, "length": tuning.f("leg_length"), "start_lane": 1,
			"beats": [], "hazards": [], "curves": [], "gusts": [], "zones": [], "path": [[0.0, 1]],
			"spawns": [{"vehicle": "wedding_car", "lane": 2, "speed": speed, "direction": 1, "role": "wedding",
					"change_to": 2, "change_gap": 0.0, "late": false, "trigger_s": 0.0, "ahead": 40.0, "meet_s": 0.0}],
		})
		_sim.step(_input)
		var guest: TrafficSim.Vehicle = null
		for vehicle: TrafficSim.Vehicle in _sim.traffic.vehicles:
			if vehicle.role == &"wedding":
				guest = vehicle
		if not check(guest != null, "the leg's wedding car is on the road"):
			return
		check_near(guest.honk_nerves, happy, 0.000001, "a wedding car's honk is the happy one")
		_held_x = guest.x - guest.half_width - _sim.car.half_width() - air
		_sim.drain_events()
		var cash_before: float = _sim.cash
		var judged: float = 0.0
		var calls: int = 0
		var honks: int = 0
		var was_along: bool = false
		for _tick: int in int(MAX_SECONDS / DT):
			_hold_x()
			var nerves_before: float = _sim.nerves.value
			_sim.step(_input)
			calls += _sim.collision.close_calls
			var along: bool = absf(guest.s - _sim.car.s) < guest.half_length + _sim.car.length() * 0.5
			if was_along and not along:
				judged = _sim.nerves.value - nerves_before
			was_along = along
			honks += _honk_events(_sim.drain_events(), guest.id)
			if _sim.car.s > guest.s + 20.0:
				break
		if air < gap_limit:
			check_eq(calls, 1, "a wedding car passed closely is a close call")
			check_near(_sim.cash - cash_before, tuning.f("close_call_base_cash") * tuning.fi("gear_cash_mult", 2), 0.000001, "which pays as any other")
			check_eq(honks, 1, "it honks, once")
			check_near(judged, happy, 0.01, "and the happy honk is -5 Nerves instead of the close call's +2 (%s)" % str(snappedf(judged, 0.001)))
		else:
			check_eq(calls, 0, "a wedding car passed with more than close_call_gap is no close call")
			check_eq(honks, 0, "and it does not honk")
			check_near(judged, 0.0, 0.01, "nor does his Nerves change")
		check_eq(_sim.faults.lamps, 0, "no lamp is lit")


func _check_hit_event(event: Dictionary, kind: Collision.Hit, lamps: int, vehicle_id: int, what: String) -> void:
	check_eq(GameData.as_int(event.get("kind"), -1), int(kind), "%s: the hit event carries its class" % what)
	check_eq(GameData.as_int(event.get("lamps"), -1), lamps, "%s: the lamps it lit" % what)
	check_eq(GameData.as_int(event.get("vehicle"), -1), vehicle_id, "%s: and the vehicle that was hit" % what)


## The payload of a close_call event (GDD 13.6).
func _check_close_call_event(event: Dictionary, count: int, cash: float, mult: float, chain: int, what: String) -> void:
	check_eq(GameData.as_int(event.get("count"), -1), count, "%s: the close_call event carries how many" % what)
	check_near(GameData.as_float(event.get("cash"), -1.0), cash, 0.000001, "%s: what they paid" % what)
	check_near(GameData.as_float(event.get("mult"), -1.0), mult, 0.000001, "%s: the chain multiplier" % what)
	check_eq(GameData.as_int(event.get("chain"), -1), chain, "%s: and the chain's links" % what)


func _sum(values: Array[float]) -> float:
	var total: float = 0.0
	for value: float in values:
		total += value
	return total


# --- What was left of the M2 review's test findings (2026-11-17) -----------------
#
# These go at the rules with nothing else of the simulation round them: a
# car, a road's traffic and the collision rules, stepped by hand. The car
# goes straight on where it is put.

var _bare_car: CarSim
var _bare_traffic: TrafficSim
var _bare: Collision


func _bare_start(gear: int, lane: int, lanes: int = 3, divided: bool = true) -> void:
	_bare_car = CarSim.new()
	_bare_car.configure(tuning)
	_bare_car.set_road(lanes, divided)
	_bare_car.reset(lane, gear)
	_bare_traffic = TrafficSim.new()
	_bare_traffic.configure(data)
	_bare = Collision.new()
	_bare.configure(tuning)
	_bare.reset()


## One tick: the car moves on at the speed it has, the traffic moves, the
## rules judge. (The order DriveSim steps them in.)
func _bare_tick(gear: int) -> void:
	_bare_car.s += _bare_car.speed * KMH_TO_MS * DT
	_bare_traffic.step(DT, _bare_car.s, _bare_car.x, _bare_car.speed)
	_bare.step(DT, _bare_car, _bare_traffic, gear)


## A vehicle the car has just left behind, with `min_gap` as the least air
## there was between them: the next tick judges the pass.
func _bare_passed(type: StringName, min_gap: float, speed: float, direction: int = 1) -> TrafficSim.Vehicle:
	var lane: int = 2 if direction > 0 else -1
	var vehicle: TrafficSim.Vehicle = _bare_traffic.spawn(type, lane, _bare_car.s - 20.0, speed, direction)
	vehicle.cc_overlap = true
	vehicle.cc_min_gap = min_gap
	return vehicle


## Passes `vehicle` from 30 m behind it at `gap` metres of air, straight on.
## `after_level` is the gap from the moment the car's middle is past the
## vehicle's (NAN: the same). Returns the close calls counted on the way.
func _bare_pass(vehicle: TrafficSim.Vehicle, gear: int, gap: float, after_level: float = NAN) -> int:
	var side: float = -1.0 if vehicle.direction > 0 else 1.0
	var counted: int = 0
	_bare_car.x = vehicle.x + side * (vehicle.half_width + _bare_car.half_width() + gap)
	for _tick: int in int(MAX_SECONDS / DT):
		if not is_nan(after_level) and _bare_car.s > vehicle.s:
			_bare_car.x = vehicle.x + side * (vehicle.half_width + _bare_car.half_width() + after_level)
		_bare_tick(gear)
		counted += _bare.close_calls
		if _bare_car.s > vehicle.s + 30.0:
			break
	return counted


func _check_bare_hits() -> void:
	var first: float = tuning.fi("gear_speeds", 0)
	var third: float = tuning.fi("gear_speeds", 2)
	var immunity: float = tuning.f("hit_immunity")
	var pushback: float = tuning.f("hit_pushback")

	# It is the closing speed that classes a hit, whoever is the faster: a
	# car doing 50 km/h more than he is, touched on its side as it goes by,
	# is a crash; one doing 90 more, the worst kind.
	for case: Array in [[50.0, Collision.Hit.CRASH, 1], [90.0, Collision.Hit.HEAD_ON, 2], [20.0, Collision.Hit.SCRAPE, 0]]:
		var faster: float = GameData.as_float(case[0])
		_bare_start(1, 1)
		var quick: TrafficSim.Vehicle = _bare_traffic.spawn(&"car", 2, -30.0, first + faster)
		var kind: Collision.Hit = Collision.Hit.NONE
		var lamps: int = 0
		for _tick: int in int(10.0 / DT):
			if absf(quick.s - _bare_car.s) < 1.0:
				_bare_car.x = quick.x - (quick.half_width + _bare_car.half_width()) + TOUCH_DEPTH
			_bare_tick(1)
			if _bare.hit != Collision.Hit.NONE:
				kind = _bare.hit
				lamps = _bare.hit_lamps
				break
		check_eq(kind, GameData.as_int(case[1]), "touched by a car going %s km/h faster than he is: the class of a closing speed of %s" % [str(faster), str(faster)])
		check_eq(lamps, int(tuning.fi("hit_lamps", GameData.as_int(case[2]))), "and its lamps")

	# A hit from outside the traffic (Collision.strike): once a tick, and
	# not while he cannot be hit.
	_bare_start(3, 1)
	_bare_tick(3)
	check(not _bare.strike(Collision.Hit.NONE), "a strike of no kind is no hit")
	check(_bare.strike(Collision.Hit.CRASH), "a strike lands on a car that can be hit")
	check_eq(_bare.hit, Collision.Hit.CRASH, "as the hit it is")
	check_eq(_bare.hit_lamps, int(tuning.fi("hit_lamps", 1)), "with a crash's lamps")
	check(_bare.hit_forces_gear, "forcing the lever")
	check_near(_bare.immunity_left, immunity, 0.000001, "and beginning hit_immunity")
	check(not _bare.strike(Collision.Hit.HEAD_ON), "a second strike on the same tick does not land")
	check_eq(_bare.hit, Collision.Hit.CRASH, "and changes nothing")
	var immune_ticks: int = roundi(immunity / DT)
	var landed: int = 0
	for _tick: int in immune_ticks - 1:
		_bare_tick(3)
		landed += 1 if _bare.strike(Collision.Hit.SCRAPE) else 0
	check_eq(landed, 0, "no strike lands during hit_immunity")
	_bare_tick(3)
	check(_bare.strike(Collision.Hit.SCRAPE), "the tick it is over, one does")
	check_eq(_bare.hit_lamps, int(tuning.fi("hit_lamps", 0)), "a scrape: one lamp")

	# Between a corridor's barriers there is no room beside anything: a
	# sideswipe there is undone along the road, not into the barrier.
	_bare_start(3, 1)
	var room: float = 0.3
	_bare_car.wall_left = _bare_car.x - _bare_car.half_width() - room
	_bare_car.wall_right = _bare_car.x + _bare_car.half_width() + room
	var beside: TrafficSim.Vehicle = _bare_traffic.spawn(&"car", 1, _bare_car.s + 1.0, third)
	beside.x = _bare_car.x - (beside.half_width + _bare_car.half_width()) + TOUCH_DEPTH
	var x_before: float = _bare_car.x
	_bare_tick(3)
	check(_bare.hit != Collision.Hit.NONE, "(a car overlapping his side between the barriers is a hit)")
	check_eq(_bare_car.x, x_before, "between barriers a hit does not push him sideways")
	check(_bare_car.x + _bare_car.half_width() < _bare_car.wall_right and _bare_car.x - _bare_car.half_width() > _bare_car.wall_left, "he is inside the corridor still")
	check_near(beside.s - _bare_car.s, beside.half_length + _bare_car.length() * 0.5 + pushback, 0.000001, "he is put hit_pushback behind it instead")
	# The same touch with no barriers pushes him sideways.
	_bare_start(3, 1)
	beside = _bare_traffic.spawn(&"car", 1, _bare_car.s + 1.0, third)
	beside.x = _bare_car.x - (beside.half_width + _bare_car.half_width()) + TOUCH_DEPTH
	x_before = _bare_car.x
	_bare_tick(3)
	check_near(_bare_car.x - x_before, TOUCH_DEPTH + pushback, 0.000001, "with no barriers the same hit pushes him hit_pushback clear, sideways")

	# "Behind a vehicle going his way he is no faster than it is": going his
	# way. Undone out of an oncoming truck while he cannot be hit, he keeps
	# the speed he has.
	_bare_start(3, 0, 1, false)
	_bare_car.x = _bare_car.lane_center(-1)
	_bare.immunity_left = immunity
	var lorry: TrafficSim.Vehicle = _bare_traffic.spawn(&"truck", -1, _bare_car.s + _lorry_reach(), _type_speed(&"truck", 0.0), -1)
	_bare_tick(3)
	check_eq(_bare.hit, Collision.Hit.NONE, "(immune, the oncoming truck he is inside is no hit)")
	check(absf(lorry.s - _bare_car.s) >= lorry.half_length + _bare_car.length() * 0.5 - TOUCHING, "he is moved out of it")
	check_near(_bare_car.speed, third, 0.000001, "and is not held to the speed of a vehicle coming the other way")
	# Out of one going his way, slower than he is, he is.
	_bare_start(3, 1)
	_bare.immunity_left = immunity
	var slowpoke: TrafficSim.Vehicle = _bare_traffic.spawn(&"truck", 1, _bare_car.s + _lorry_reach(), _type_speed(&"truck", 0.0))
	_bare_tick(3)
	check_near(_bare_car.speed, slowpoke.speed, 0.000001, "behind a truck going his way he is held to its speed")


## How far ahead of him a truck's middle is when its rear end is 0.3 m
## inside his nose.
func _lorry_reach() -> float:
	return GameData.as_float(data.record("vehicles", "truck").get("length")) * 0.5 + tuning.f("car_length") * 0.5 - 0.3


func _check_bare_close_calls() -> void:
	var third: float = tuning.fi("gear_speeds", 2)
	var gap: float = tuning.f("close_call_gap")
	var base: float = tuning.f("close_call_base_cash")
	var gear_mult: float = tuning.fi("gear_cash_mult", 2)
	var slow: float = _type_speed(&"truck", 0.0)

	# It is the least air of the whole pass that is judged: close beside the
	# tail, wide by the time he is clear of the nose, is a close call.
	_bare_start(3, 1)
	var truck: TrafficSim.Vehicle = _bare_traffic.spawn(&"truck", 2, 30.0, slow)
	check_eq(_bare_pass(truck, 3, gap * 0.5, gap * 2.0), 1, "close at first and wide at the end of the pass: a close call")
	_bare_start(3, 1)
	truck = _bare_traffic.spawn(&"truck", 2, 30.0, slow)
	check_eq(_bare_pass(truck, 3, gap * 2.0, gap * 0.5), 1, "wide at first and close at the end: a close call too")
	_bare_start(3, 1)
	truck = _bare_traffic.spawn(&"truck", 2, 30.0, slow)
	check_eq(_bare_pass(truck, 3, gap * 2.0), 0, "wide all the way: none")

	# "Under 0.6 m": at close_call_gap exactly it is not one.
	_bare_start(3, 1)
	_bare_passed(&"truck", gap, slow)
	_bare_tick(3)
	check_eq(_bare.close_calls, 0, "a pass with exactly close_call_gap of air is not a close call")
	_bare_start(3, 1)
	_bare_passed(&"truck", gap - 0.000001, slow)
	_bare_tick(3)
	check_eq(_bare.close_calls, 1, "a hair under it is")
	check_near(_bare.close_call_cash, base * gear_mult, 0.000001, "and pays close_call_base_cash x the gear")

	# A contact spoils the pass it was made in, not the next one.
	_bare_start(3, 1)
	truck = _bare_traffic.spawn(&"truck", 2, 30.0, slow)
	_bare.immunity_left = 1000.0
	check_eq(_bare_pass(truck, 3, -TOUCH_DEPTH), 0, "a pass in which he touched the truck is no close call")
	_bare_car.s = truck.s - 30.0
	_bare.immunity_left = 0.0
	check_eq(_bare_pass(truck, 3, gap * 0.5), 1, "passing it again without a touch is one")

	# A vehicle that honks at a close pass: an angry honk frays him, a happy
	# one does not, and neither is changed by the other.
	for honk: float in [5.0, -4.0]:
		_bare_start(3, 1)
		var honker: TrafficSim.Vehicle = _bare_passed(&"car", gap * 0.5, slow)
		honker.honk_nerves = honk
		_bare_tick(3)
		check_near(_bare.honk_nerves, honk, 0.000001, "a honk of %s Nerves is owed as that" % str(honk))
		check_near(_bare.honk_frights, maxf(honk, 0.0), 0.000001, "and frays him by %s" % str(maxf(honk, 0.0)))
		check_eq(_bare.honk_vehicle_ids.size(), 1, "it is one honk")

	# The chain: a close call within chain_window of the last is a link, one
	# tick later it is not. (480 ticks are 4 s.)
	var window_ticks: int = roundi(tuning.f("chain_window") / DT)
	for case: Array in [[window_ticks, 1], [window_ticks + 1, 0], [window_ticks - 1, 1], [roundi(float(window_ticks) * 1.1), 0]]:
		_bare_start(3, 1)
		_bare_passed(&"truck", gap * 0.5, slow)
		_bare_tick(3)
		check_eq(_bare.close_calls, 1, "(a first close call)")
		for _tick: int in GameData.as_int(case[0]) - 1:
			_bare_tick(3)
		_bare_passed(&"truck", gap * 0.5, slow)
		_bare_tick(3)
		check_eq(_bare.close_calls, 1, "(a second, %d ticks after the first)" % GameData.as_int(case[0]))
		check_eq(_bare.chain, GameData.as_int(case[1]), "a close call %d ticks after the last: chain %d" % [GameData.as_int(case[0]), GameData.as_int(case[1])])
		check_near(_bare.close_call_mult, 1.0 + tuning.f("chain_step") * float(GameData.as_int(case[1])), 0.000001, "and its multiplier")

	# What the cabin may add (GDD 7): a share of the pay, and a note on top
	# of each close call, which the share does not touch.
	_bare_start(3, 1)
	_bare.cash_mult = 2.0
	_bare.cash_bonus = 5.0
	_bare_passed(&"truck", gap * 0.5, slow)
	_bare_tick(3)
	check_near(_bare.close_call_cash, base * gear_mult * 2.0 + 5.0, 0.000001, "close-call cash x 2 and 5 more a close call: twice the pay, plus 5")

	# An oncoming vehicle closes at his speed and its own together: crawling
	# at 20 km/h past one that comes at 60 is a close call, and pays double.
	_bare_start(1, 0, 1, false)
	_bare_car.speed = 20.0
	var coming: TrafficSim.Vehicle = _bare_traffic.spawn(&"car", -1, 40.0, 60.0, -1)
	_bare_car.x = coming.x + coming.half_width + _bare_car.half_width() + gap * 0.5
	var counted: int = 0
	var paid: float = 0.0
	for _tick: int in int(10.0 / DT):
		_bare_tick(1)
		counted += _bare.close_calls
		paid += _bare.close_call_cash
	check(20.0 < tuning.f("close_call_min_closing") and 80.0 >= tuning.f("close_call_min_closing"), "(20 km/h alone is under close_call_min_closing; 80 is not)")
	check_eq(counted, 1, "an oncoming car passed closely at 20 km/h is a close call")
	check_near(paid, base * tuning.fi("gear_cash_mult", 0) * tuning.f("close_call_oncoming_mult"), 0.000001, "paid for first gear, doubled for an oncoming vehicle")


func _check_traffic_leftovers() -> void:
	var follow_gap: float = tuning.f("traffic_follow_gap")
	var signal_ticks: int = roundi(tuning.f("signal_time") / DT)
	var move_ticks: int = roundi(tuning.f("lane_change_time") / DT)
	var slow: float = _type_speed(&"truck", 0.0)
	var fast: float = _type_speed(&"taxi", 1.0)

	# A lane change that has begun is finished before another can begin.
	for interrupt_at: int in [signal_ticks / 2, signal_ticks + move_ticks / 2]:
		var traffic: TrafficSim = TrafficSim.new()
		traffic.configure(data)
		var mover: TrafficSim.Vehicle = traffic.spawn(&"car", 1, 0.0, fast)
		traffic.begin_lane_change(mover, 2, tuning.f("signal_time"))
		var done_tick: int = -1
		for tick: int in signal_ticks + move_ticks + 240:
			if tick == interrupt_at:
				traffic.begin_lane_change(mover, 0, tuning.f("signal_time"))
			traffic.step(DT, -2000.0, -100.0, 0.0)
			if done_tick < 0 and mover.signalling == 0:
				done_tick = tick
		check_eq(done_tick + 1, signal_ticks + move_ticks, "a lane change asked for %d ticks into another does not delay it" % interrupt_at)
		check_eq(mover.lane, 2, "nor turn it round")
		check_near(mover.x, traffic.lane_center(2), 0.000001, "the vehicle ends in the lane it set out for")

	# The horn's quicker move: no signal, and the time that was asked for.
	var road: TrafficSim = TrafficSim.new()
	road.configure(data)
	var yielding: TrafficSim.Vehicle = road.spawn(&"car", 1, 0.0, fast)
	road.begin_lane_change(yielding, 2, 0.0, 0.5)
	var ticks: int = 0
	for _tick: int in move_ticks * 2:
		road.step(DT, -2000.0, -100.0, 0.0)
		ticks += 1
		if yielding.signalling == 0:
			break
	check_eq(ticks, roundi(0.5 / DT), "a lane change asked to take 0.5 s with no signal takes 0.5 s")
	check_eq(yielding.lane, 2, "and ends in the new lane")

	# The gap at which a vehicle takes the speed of the one ahead is
	# traffic_follow_gap, bumper to bumper, whatever their lengths.
	for leader: StringName in [&"truck", &"tuk_tuk"]:
		road = TrafficSim.new()
		road.configure(data)
		var ahead: TrafficSim.Vehicle = road.spawn(leader, 1, 500.0, slow * 0.5)
		var chaser: TrafficSim.Vehicle = road.spawn(&"taxi", 1, 400.0, fast)
		var closing: float = (fast - slow * 0.5) * KMH_TO_MS * DT
		var gap_when_slowed: float = INF
		for _tick: int in int(30.0 / DT):
			road.step(DT, -2000.0, -100.0, 0.0)
			if chaser.speed < fast:
				gap_when_slowed = (ahead.s - ahead.half_length) - (chaser.s + chaser.half_length)
				break
		check(gap_when_slowed < follow_gap and gap_when_slowed > follow_gap - closing * 2.0,
				"behind a %s a taxi slows when the air between them falls under traffic_follow_gap (at %s m)" % [leader, str(gap_when_slowed)])

	# It follows what is ahead and going its way: not a vehicle it overlaps,
	# and not one coming the other way.
	road = TrafficSim.new()
	road.configure(data)
	var through: TrafficSim.Vehicle = road.spawn(&"taxi", 1, 98.0, fast)
	road.spawn(&"truck", 1, 100.0, slow)
	road.step(DT, -2000.0, -100.0, 0.0)
	check_near(through.speed, fast, 0.000001, "a vehicle that overlaps another in its lane does not take its speed")
	road = TrafficSim.new()
	road.configure(data)
	var overtaker: TrafficSim.Vehicle = road.spawn(&"taxi", -1, 0.0, fast)
	var coming: TrafficSim.Vehicle = road.spawn(&"truck", -1, 0.0, slow, -1)
	coming.s = overtaker.half_length + coming.half_length + follow_gap * 0.5
	road.step(DT, -2000.0, -100.0, 0.0)
	check_near(overtaker.speed, fast, 0.000001, "a vehicle in the oncoming lane does not follow a truck coming at it")
	check_near(coming.speed, slow, 0.000001, "nor the truck it")

	# An oncoming vehicle that has gone by the standing player keeps going.
	road = TrafficSim.new()
	road.configure(data)
	var gone_by: TrafficSim.Vehicle = road.spawn(&"car", -1, 0.0, _type_speed(&"car", 0.0), -1)
	gone_by.s = -(tuning.f("car_length") * 0.5 + gone_by.half_length + follow_gap * 0.5)
	road.step(DT, 0.0, road.lane_center(-1), 0.0)
	check_near(gone_by.speed, _type_speed(&"car", 0.0), 0.000001, "an oncoming car just past the player standing in its lane does not stop for him")

	# An oncoming vehicle's planned lane change begins where it was planned,
	# counted along its own way.
	road = TrafficSim.new()
	road.configure(data)
	var planner: TrafficSim.Vehicle = road.spawn(&"car", -1, 100.0, 60.0, -1)
	road.plan_lane_change(planner, 50.0, 0)
	var began_at: float = INF
	var before: float = planner.s
	for _tick: int in int(10.0 / DT):
		before = planner.s
		road.step(DT, -2000.0, -100.0, 0.0)
		if planner.signalling != 0:
			began_at = planner.s
			break
	check(before > 50.0 and began_at <= 50.0, "an oncoming vehicle's planned change begins as it reaches the place (it began at %s m)" % str(began_at))

	# A lane is free of a vehicle from its bumpers, not from its middle.
	road = TrafficSim.new()
	road.configure(data)
	var long: TrafficSim.Vehicle = road.spawn(&"truck", 2, 100.0, slow)
	var clearance: float = 5.0
	check(not road.lane_is_free(2, 100.0 + long.half_length + clearance - 0.5, clearance, null), "a lane is not free within the clearance of a truck's bumper")
	check(road.lane_is_free(2, 100.0 + long.half_length + clearance + 0.5, clearance, null), "it is free beyond it")
	check(not road.lane_is_free(2, 100.0 - long.half_length - clearance + 0.5, clearance, null), "the same behind the truck")
	check(road.lane_is_free(2, 100.0, clearance, long), "a vehicle is not in its own way")
	check(road.lane_is_free(1, 100.0, clearance, null), "and the next lane is free of it")
