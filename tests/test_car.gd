extends TestSuite
## M2: the car in lane space (GDD 4.8, 5.1 to 5.4).

const DT: float = DriveSim.DT
const KMH_TO_MS: float = 1.0 / 3.6
## A sideways speed is left to settle for SETTLE seconds (many times
## wheel_smoothing plus lat_follow_tau), then measured from x over MEASURE seconds.
const SETTLE: float = 2.0
const MEASURE: float = 0.5

var _car: CarSim


func before_each() -> void:
	_car = CarSim.new()
	_car.configure(tuning)
	_car.set_road(3, true)


## T-CAR-01: from lane centre, straight, gear 3, hands off, the car edge
## reaches the lane line at 3.4 s, within 0.05 s.
func test_car_01() -> void:
	var lane_width: float = tuning.f("lane_width")
	var margin: float = (lane_width - tuning.f("car_width")) * 0.5
	var expected: float = margin / tuning.f("crown_drift")
	check_near(expected, 3.4, 0.000001, "the tuning of GDD 15 puts the lane line 3.4 s away (GDD 5.4, 12.5)")

	_car.reset(1, 3)
	var line: float = lane_width * 2.0
	var seconds: float = INF
	for tick: int in int(10.0 / DT):
		_car.step(DT, 0.0, 3, false, 0.0)
		if _car.x + _car.half_width() >= line:
			seconds = float(tick + 1) * DT
			break
	check_near(seconds, 3.4, 0.05, "hands off in gear 3 from lane centre, the car edge reaches the lane line")
	check_near(_car.speed, tuning.fi("gear_speeds", 2), 0.000001, "it is still at third gear's cruise speed")

	# The same through the whole simulation: nobody holds the wheel.
	var sim: DriveSim = DriveSim.new(fresh_data())
	sim.gate.reset(3)
	sim.car.reset(1, 3)
	var input: DriveInput = DriveInput.new()
	seconds = INF
	for tick: int in int(10.0 / DT):
		sim.step(input)
		if sim.car.x + sim.car.half_width() >= line:
			seconds = float(tick + 1) * DT
			break
	check_near(seconds, 3.4, 0.05, "the same in a full DriveSim with the wheel unheld")

	# The drift is toward the right shoulder, at crown_drift, in every gear. (It
	# fades only below drift_fade_speed, slower than any gear cruises: T-CAR-05.)
	_car.reset(1, 1)
	var before: float = _car.x
	for _tick: int in int(1.0 / DT):
		_car.step(DT, 0.0, 1, false, 0.0)
	check_near(_car.x - before, tuning.f("crown_drift"), 0.001, "the crown pushes toward the right shoulder at crown_drift in any gear")
	for gear: int in [2, 3, 4, 5]:
		_car.reset(1, gear)
		before = _car.x
		for _tick: int in int(1.0 / DT):
			_car.step(DT, 0.0, gear, false, 0.0)
		check_near(_car.x - before, tuning.f("crown_drift"), 0.001, "the crown pushes at crown_drift in gear %d as well" % gear)


## T-CAR-02: full lock at 100 km/h settles at 5.0 m/s sideways.
func test_car_02() -> void:
	var expected: float = tuning.f("lat_per_kmh") * tuning.fi("gear_speeds", 2)
	var crown: float = tuning.f("crown_drift")
	check_near(expected, 5.0, 0.000001, "the tuning of GDD 15 gives 5.0 m/s at full lock in third")
	for lock: float in [1.0, -1.0]:
		_car.reset(1, 3)
		for _tick: int in int(1.5 / DT):
			_car.step(DT, lock, 3, false, 0.0)
			# Keep it on the road: this test is about sideways speed, not edges.
			_car.x = _car.lane_center(1)
		check_near(_car.v_lat, lock * 5.0, 0.001, "full lock (%s) at 100 km/h settles at 5.0 m/s sideways" % str(lock))
		# The car really moves that fast: x says so, not only the field (GDD 5.3:
		# x += (v_lat + sum_of_drifts) * dt). The crown is the one drift here.
		check_near(_sideways_rate(lock, 3), lock * 5.0 + crown, 0.001, "at full lock (%s) the car moves 5.0 m/s sideways, plus the crown" % str(lock))

	# The table of GDD 5.2: sideways speed at full lock in every gear.
	for gear: int in [1, 2, 3, 4, 5]:
		_car.reset(1, gear)
		for _tick: int in int(1.5 / DT):
			_car.step(DT, 1.0, gear, false, 0.0)
			_car.x = _car.lane_center(1)
		check_near(_car.v_lat, tuning.f("lat_per_kmh") * tuning.fi("gear_speeds", gear - 1), 0.001, "full lock in gear %d" % gear)
		var full: float = tuning.f("lat_per_kmh") * tuning.fi("gear_speeds", gear - 1)
		check_near(_sideways_rate(1.0, gear), full + crown, 0.001, "at full right lock in gear %d the car moves that fast to the right, plus the crown" % gear)
		check_near(_sideways_rate(-1.0, gear), -full + crown, 0.001, "at full left lock in gear %d it moves as fast to the left, less the crown" % gear)

	# The car follows the command with lat_follow_tau (first-order).
	var tau: float = tuning.f("lat_follow_tau")
	_car.reset(1, 3)
	var ticks: int = roundi(tau / DT)
	for _tick: int in ticks:
		_car.step(DT, 1.0, 3, false, 0.0)
	check_near(_car.v_lat / expected, 1.0 - exp(-float(ticks) * DT / tau), 0.001, "after one lat_follow_tau the car has 63% of its sideways speed")

	# First-order all the way: tick by tick the response is the exponential. (One
	# sample at an even tick cannot tell a smooth rise from a ringing overshoot.)
	_car.reset(1, 3)
	var worst: float = 0.0
	var highest: float = 0.0
	for tick: int in roundi(3.0 * tau / DT):
		_car.step(DT, 1.0, 3, false, 0.0)
		_car.x = _car.lane_center(1)
		worst = maxf(worst, absf(_car.v_lat - expected * (1.0 - exp(-float(tick + 1) * DT / tau))))
		highest = maxf(highest, _car.v_lat)
	check_near(worst, 0.0, 0.000001, "tick by tick the sideways speed is the command x (1 - e^(-t / lat_follow_tau))")
	check(highest < expected, "and it never overshoots the command")

	# Half lock is half the speed; the wheel at full lock is steer 1.
	_car.reset(1, 3)
	for _tick: int in int(1.5 / DT):
		_car.step(DT, 0.5, 3, false, 0.0)
		_car.x = _car.lane_center(1)
	check_near(_car.v_lat, expected * 0.5, 0.001, "half lock gives half the sideways speed")
	check_near(_sideways_rate(0.5, 3), expected * 0.5 + crown, 0.001, "and moves the car half as fast, plus the crown")
	var wheel: WheelSim = WheelSim.new()
	wheel.configure(tuning)
	wheel.reset(tuning.f("wheel_max_angle"))
	check_near(wheel.steer(), 1.0, 0.000001, "the wheel at wheel_max_angle is full lock")

	# It is the car's speed that scales the command, not the lever (GDD 5.3:
	# steer * lat_per_kmh * speed_kmh). Off the cruise speed the two differ.
	var third: float = tuning.fi("gear_speeds", 2)
	_car.reset(1, 3)
	var slow_rate: float = _sideways_rate(1.0, 3, third * 0.5)
	check_near(_car.speed, third * 0.5, tuning.f("accel") * DT + 0.000001, "(the lever is in third and the car at half of third's speed)")
	check_near(slow_rate, tuning.f("lat_per_kmh") * _car.speed + crown, 0.001, "at half the speed full lock gives half the sideways speed, whatever the gear engaged")
	_car.reset(1, 3)
	var coasting_rate: float = _sideways_rate(-1.0, CarSim.NEUTRAL, third)
	check_near(_car.speed, third, tuning.f("neutral_coast") * DT + 0.000001, "(the lever is in neutral and the car still at third's speed)")
	check_near(coasting_rate, -tuning.f("lat_per_kmh") * _car.speed + crown, 0.001, "rolling in neutral the car steers by its speed all the same")

	_check_steering_in_sim()


## T-CAR-03: 2,500 m takes 90.0 s in gear 3 and 69.2 s in gear 4, within 0.5 s.
func test_car_03() -> void:
	var leg: float = tuning.f("leg_length")
	# The column "Time for 2.5 km (s)" of GDD 5.2, gears 1 to 5.
	var printed: PackedFloat64Array = [225.0, 129.0, 90.0, 69.2, 56.0]
	for gear: int in [3, 4, 1, 2, 5]:
		var seconds: float = _seconds_for(leg, gear)
		var expected: float = leg / (tuning.fi("gear_speeds", gear - 1) * KMH_TO_MS)
		check_near(seconds, expected, 0.5, "%s m in gear %d" % [str(leg), gear])
		check_near(expected, printed[gear - 1], 0.5, "which is the time GDD 5.2 prints for gear %d" % gear)


## T-CAR-04: braking from 100 km/h to rest takes 3.33 s.
func test_car_04() -> void:
	var expected: float = tuning.fi("gear_speeds", 2) / tuning.f("brake_decel")
	check_near(expected, 3.33, 0.01, "the tuning of GDD 15 stops the car from 100 km/h in 3.33 s")
	_car.reset(1, 3)
	var seconds: float = INF
	for tick: int in int(10.0 / DT):
		_car.step(DT, 0.0, 3, true, 0.0)
		_car.x = _car.lane_center(1)
		if _car.speed <= 0.0:
			seconds = float(tick + 1) * DT
			break
	check_near(seconds, expected, DT, "braking from 100 km/h to rest")
	for _tick: int in 30:
		_car.step(DT, 0.0, 3, true, 0.0)
	check_eq(_car.speed, 0.0, "held, the brake keeps the car at rest and never reverses it")

	# Half-way down the brake has shed half the speed: it is linear.
	_car.reset(1, 3)
	for _tick: int in roundi(expected * 0.5 / DT):
		_car.step(DT, 0.0, 3, true, 0.0)
	check_near(_car.speed, tuning.fi("gear_speeds", 2) * 0.5, tuning.f("brake_decel") * DT, "the brake sheds brake_decel per second")

	# "To rest" is about the road the car covers (s), not only the speed field.
	var start_ms: float = tuning.fi("gear_speeds", 2) * KMH_TO_MS
	var ideal: float = start_ms * start_ms / (2.0 * tuning.f("brake_decel") * KMH_TO_MS)
	_car.reset(1, 3)
	var summed: float = 0.0
	var rest_tick: int = -1
	for tick: int in int(10.0 / DT):
		var s_before: float = _car.s
		_car.step(DT, 0.0, 3, true, 0.0)
		_car.x = _car.lane_center(1)
		summed += _car.speed * KMH_TO_MS * DT
		if _car.s == s_before:
			rest_tick = tick
			break
	check_near(float(rest_tick + 1) * DT, expected, DT, "braked from 100 km/h the car stops covering ground after 3.33 s")
	check_near(_car.s, ideal, start_ms * DT, "having covered v squared over 2a metres (about 46 m), to within one tick of travel")
	check_near(_car.s, summed, 0.000001, "each tick it covers its speed times the tick: the distance is the sum of the per-tick speeds")
	var s_at_rest: float = _car.s
	for _tick: int in int(1.0 / DT):
		_car.step(DT, 0.0, 3, true, 0.0)
	check_eq(_car.s, s_at_rest, "at rest with the brake held it covers no more ground")

	_check_braking_in_sim(expected, ideal)


## T-CAR-05: speed changes, the road's edges and the drift sources.
func test_car_05() -> void:
	_check_speed_changes()
	_check_edges()
	_check_edges_in_sim()
	_check_strip_and_shoulder_in_sim()
	_check_drifts()
	_check_curve_in_sim()
	_check_drift_at_low_speed()


func _check_speed_changes() -> void:
	var third: float = tuning.fi("gear_speeds", 2)
	var fourth: float = tuning.fi("gear_speeds", 3)

	# Each gear cruises at its speed of GDD 5.2; neutral, and a gear the box
	# does not have, at none.
	var gears: int = tuning.floats("gear_speeds").size()
	for gear: int in range(1, gears + 1):
		check_near(_car.cruise_speed(gear), tuning.fi("gear_speeds", gear - 1), 0.000001, "gear %d cruises at its gear_speeds entry" % gear)
	check_eq(_car.cruise_speed(CarSim.NEUTRAL), 0.0, "neutral has no cruise speed")
	check_eq(_car.cruise_speed(gears + 1), 0.0, "nor has a gear beyond the last")

	# Releasing the brake: back up to cruise at accel.
	_car.reset(1, 3)
	_car.speed = third - 40.0
	_run_centered(1.0, 3, false)
	check_near(_car.speed, third - 40.0 + tuning.f("accel"), 0.01, "after the brake the car climbs at accel")
	_run_centered(10.0, 3, false)
	check_near(_car.speed, third, 0.000001, "and stops climbing at the gear's cruise speed")

	# A downshift: down to the new cruise speed at engine_brake.
	_car.reset(1, 4)
	check_near(_car.speed, fourth, 0.000001, "fourth gear cruises at its speed")
	_run_centered(1.0, 3, false)
	check_near(_car.speed, fourth - tuning.f("engine_brake"), 0.01, "after a downshift the car slows at engine_brake")
	_run_centered(5.0, 3, false)
	check_near(_car.speed, third, 0.000001, "down to the new gear's cruise speed")

	# Neutral: coasting.
	_car.reset(1, 3)
	_run_centered(2.0, CarSim.NEUTRAL, false)
	check_near(_car.speed, third - 2.0 * tuning.f("neutral_coast"), 0.01, "in neutral the car coasts down at neutral_coast")
	_run_centered(60.0, CarSim.NEUTRAL, false)
	check_eq(_car.speed, 0.0, "coasting ends at rest")

	# The brake is the brake whatever the lever does (GDD 4.8): in neutral it
	# sheds brake_decel, and neither coasting nor a downshift adds to it.
	_car.reset(1, 3)
	_run_centered(1.0, CarSim.NEUTRAL, true)
	check_near(_car.speed, third - tuning.f("brake_decel"), 0.01, "braking in neutral sheds brake_decel per second")
	_run_centered(10.0, CarSim.NEUTRAL, true)
	check_eq(_car.speed, 0.0, "down to a stop")
	_car.reset(1, 3)
	_run_centered(1.0, 1, true)
	check_near(_car.speed, third - tuning.f("brake_decel"), 0.01, "braking after a downshift sheds brake_decel per second, not engine_brake on top")


func _check_edges() -> void:
	var third: float = tuning.fi("gear_speeds", 2)
	var fourth: float = tuning.fi("gear_speeds", 3)
	var cap: float = tuning.f("shoulder_speed_cap")
	var crown: float = tuning.f("crown_drift")
	var road_right: float = tuning.f("lane_width") * 3.0
	var strip: float = tuning.f("rumble_strip_width")
	var half: float = _car.half_width()

	check_near(_car.road_right(), road_right, 0.000001, "three lanes are 3 x lane_width wide")
	check_near(_car.lane_center(0), tuning.f("lane_width") * 0.5, 0.000001, "lane 0 is centred half a lane from the left edge")
	check_near(_car.guardrail_x(), road_right + strip + tuning.f("shoulder_width"), 0.000001, "the guardrail stands beyond the strip and the shoulder")
	check_near(half * 2.0, tuning.f("car_width"), 0.000001, "the car is car_width wide")
	check_near(_car.length(), tuning.f("car_length"), 0.000001, "and car_length long")
	check_near(_car.lane_width(), tuning.f("lane_width"), 0.000001, "a lane is lane_width wide")
	for count: int in [1, 2]:
		_car.set_road(count, true)
		check_near(_car.road_right(), tuning.f("lane_width") * float(count), 0.000001, "a road of %d lane(s) is that many lane_widths wide" % count)
		check_near(_car.guardrail_x(), tuning.f("lane_width") * float(count) + strip + tuning.f("shoulder_width"), 0.000001, "and its guardrail stands beyond its own strip and shoulder")
	_car.set_road(3, true)

	# In lane: neither strip nor shoulder.
	_car.reset(2, 3)
	_car.step(DT, 0.0, 3, false, 0.0)
	check(not _car.on_rumble and not _car.on_shoulder, "centred in the right lane the car is on neither strip nor shoulder")

	# A wheel on the rumble strip.
	_car.reset(2, 3)
	_car.x = road_right - half + strip * 0.5
	_car.step(DT, 0.0, 3, false, -tuning.f("crown_drift"))
	check(_car.on_rumble and not _car.on_shoulder, "with its right edge on the strip the car is on the rumble strip only")

	# The strip is sound only (GDD 5.1): it never slows the car, in gear or out.
	for _tick: int in int(3.0 / DT):
		_car.step(DT, 0.0, 3, false, -crown)
	check(_car.on_rumble and not _car.on_shoulder, "held there for 3 s it is still on the strip only")
	check_near(_car.speed, third, 0.000001, "the rumble strip does not slow the car: it is still at third gear's cruise speed")
	_car.reset(2, 4)
	check(not _car.on_rumble, "reset() takes the car off the strip")
	_car.x = road_right - half + strip * 0.5
	for _tick: int in int(1.0 / DT):
		_car.step(DT, 0.0, CarSim.NEUTRAL, false, -crown)
	check(_car.on_rumble and not _car.on_shoulder, "(out of gear, still on the strip only)")
	check_near(_car.speed, fourth - tuning.f("neutral_coast"), 0.01, "out of gear on the strip the car only coasts, at neutral_coast")

	# On the rough shoulder: capped at shoulder_speed_cap.
	_car.reset(2, 3)
	_car.x = road_right + strip + half
	for _tick: int in int(3.0 / DT):
		_car.step(DT, 0.0, 3, false, -tuning.f("crown_drift"))
	check(_car.on_shoulder, "beyond the strip the car is on the shoulder")
	check_near(_car.speed, cap, 0.000001, "the shoulder caps speed at shoulder_speed_cap")
	check(third > cap, "which is below third gear's cruise speed")

	# The cap is reached at engine_brake (DECISIONS D-023), and then held.
	var shoulder_x: float = road_right + strip + tuning.f("shoulder_width") * 0.5
	var to_cap: float = (fourth - cap) / tuning.f("engine_brake")
	_put_on_shoulder(shoulder_x, fourth)
	check(_car.on_shoulder and not _car.on_rumble, "wholly beyond the strip the car is on the shoulder and off the strip")
	_hold_on_shoulder(to_cap * 0.5, 4, false)
	check_near(_car.speed, (fourth + cap) * 0.5, 0.01, "in gear on the shoulder the car slows at engine_brake while it is above the cap")
	_hold_on_shoulder(to_cap * 0.5 + 1.0, 4, false)
	check_near(_car.speed, cap, 0.000001, "and holds shoulder_speed_cap from then on")

	# The cap belongs to the surface, not to the lever: out of gear the car is
	# brought down to it at engine_brake all the same, and coasts on from there.
	_put_on_shoulder(shoulder_x, fourth)
	_hold_on_shoulder(to_cap * 0.5, CarSim.NEUTRAL, false)
	check_near(_car.speed, (fourth + cap) * 0.5, 0.01, "in neutral on the shoulder the car slows at engine_brake while it is above the cap")
	_hold_on_shoulder(to_cap * 0.5, CarSim.NEUTRAL, false)
	check_near(_car.speed, cap, 0.000001, "and is down to shoulder_speed_cap after (fourth - cap) / engine_brake seconds, lever in neutral")
	_hold_on_shoulder(1.0, CarSim.NEUTRAL, false)
	check_near(_car.speed, cap - tuning.f("neutral_coast"), 0.01, "from the cap down it only coasts, at neutral_coast")
	check(_car.on_shoulder and not _car.on_rumble, "(it was on the shoulder throughout)")
	_put_on_shoulder(shoulder_x, cap + tuning.f("engine_brake") * DT * 0.5)
	_hold_on_shoulder(DT, CarSim.NEUTRAL, false)
	check_near(_car.speed, cap, 0.000001, "half a tick of engine_brake above the cap, the next tick ends at the cap: the shoulder slows the car down to it, not below")

	# The foot: a brake stronger than engine_brake is not helped by the
	# shoulder, and one weaker than engine_brake does not hold the car above
	# the cap any longer than no brake at all would.
	_put_on_shoulder(shoulder_x, fourth)
	_hold_on_shoulder(1.0, 4, true)
	check_near(_car.speed, fourth - tuning.f("brake_decel"), 0.01, "braking on the shoulder sheds brake_decel per second, not engine_brake on top")
	_put_on_shoulder(shoulder_x, fourth)
	_car.brake_mult = tuning.f("engine_brake") / tuning.f("brake_decel") * 0.5
	_hold_on_shoulder(1.0, 4, true)
	check_near(_car.speed, fourth - tuning.f("engine_brake"), 0.01, "with a brake weaker than engine_brake the car above the cap still slows at engine_brake")
	_car.brake_mult = 1.0

	# The guardrail: a touch pushes the car hit_pushback back; Collision calls it a scrape.
	var collision: Collision = Collision.new()
	collision.configure(tuning)
	var traffic: TrafficSim = TrafficSim.new()
	traffic.configure(data)
	_car.reset(2, 3)
	_car.x = _car.guardrail_x() - half - 0.05
	var touched: bool = false
	var speed_before: float = 0.0
	# Where the car stood before the tick that touched, and the farthest a tick
	# can carry it sideways: an edge is touched when the car's side gets there,
	# not earlier and not after driving on through it.
	var x_before: float = 0.0
	var one_tick: float = (tuning.f("lat_per_kmh") * third + crown) * DT
	for _tick: int in int(2.0 / DT):
		speed_before = _car.speed
		x_before = _car.x
		_car.step(DT, 0.3, 3, false, 0.0)
		collision.step(DT, _car, traffic, 3)
		if _car.edge_touched != CarSim.EDGE_NONE:
			touched = true
			break
	if check(touched, "steering into the guardrail touches it"):
		check_eq(_car.edge_touched, CarSim.EDGE_RIGHT, "on the right")
		check_near(_car.x, _car.guardrail_x() - half - tuning.f("hit_pushback"), 0.000001, "the car is pushed hit_pushback back from the guardrail")
		check_eq(collision.hit, Collision.Hit.SCRAPE, "touching the guardrail is a scrape")
		check_eq(collision.hit_lamps, int(tuning.fi("hit_lamps", 0)), "a scrape lights one lamp")
		check_near(_car.speed, speed_before * (1.0 - tuning.f("scrape_speed_loss")), 0.5, "and takes scrape_speed_loss off the speed")
		check_near(collision.hit_nerves, tuning.fi("hit_nerves", 0), 0.000001, "it adds a scrape's Nerves")
		check(not collision.hit_forces_gear, "and forces no gear")
		check_eq(collision.hit_vehicle_id, 0, "no vehicle was hit: it was the rail")
		check_eq(_car.v_lat, 0.0, "the rail stops the car's sideways speed")
		var short_of_rail: float = _car.guardrail_x() - (x_before + half)
		check(short_of_rail > 0.0 and short_of_rail <= one_tick, "it touched as its right side got to the guardrail: the tick before, that side was short of it by less than a tick of travel")
		check(_car.on_shoulder, "(it is on the shoulder there)")
		# reset() gives a clean slate wherever the car was.
		_car.reset(1, 3)
		check(_car.edge_touched == CarSim.EDGE_NONE and not _car.on_shoulder and not _car.on_rumble, "reset() puts the car in a lane touching nothing, on neither strip nor shoulder")
		check_eq(_car.drift, 0.0, "with no drift on it yet")
		_car.step(DT, 0.0, 3, false, 0.0)
		check_near(_car.speed, third, 0.000001, "the shoulder's cap has not come along")

	# The median barrier on a divided road.
	_car.set_road(3, true)
	check_near(_car.left_limit_x(), tuning.f("median_barrier_x"), 0.000001, "on a divided road the left limit is the median barrier")
	_car.reset(0, 3)
	collision.reset()
	touched = false
	for _tick: int in int(3.0 / DT):
		x_before = _car.x
		_car.step(DT, -0.4, 3, false, 0.0)
		speed_before = _car.speed
		collision.step(DT, _car, traffic, 3)
		if _car.edge_touched != CarSim.EDGE_NONE:
			touched = true
			break
	if check(touched, "steering left on a divided road touches the median barrier"):
		check_eq(_car.edge_touched, CarSim.EDGE_LEFT, "on the left")
		check_near(_car.x, tuning.f("median_barrier_x") + half + tuning.f("hit_pushback"), 0.000001, "the car is pushed hit_pushback back from the barrier")
		check_eq(collision.hit, Collision.Hit.SCRAPE, "touching the median barrier is a scrape")
		check_eq(collision.hit_lamps, int(tuning.fi("hit_lamps", 0)), "which lights one lamp")
		check_near(collision.hit_nerves, tuning.fi("hit_nerves", 0), 0.000001, "adds a scrape's Nerves")
		check_near(_car.speed, speed_before * (1.0 - tuning.f("scrape_speed_loss")), 0.000001, "and takes scrape_speed_loss off the speed")
		check(not collision.hit_forces_gear, "and forces no gear")
		check_eq(_car.v_lat, 0.0, "the barrier stops the car's sideways speed")
		var short_of_barrier: float = (x_before - half) - tuning.f("median_barrier_x")
		check(short_of_barrier > 0.0 and short_of_barrier <= one_tick, "it touched as its left side got to the barrier: the tick before, that side was short of it by less than a tick of travel")
		_car.step(DT, 0.0, 3, false, 0.0)
		check_eq(_car.edge_touched, CarSim.EDGE_NONE, "a tick later the car, pushed clear, touches nothing")

	# An undivided road has the oncoming lane on the left instead.
	_car.set_road(1, false)
	_car.reset(0, 3)
	_car.x = -tuning.f("lane_width") * 0.5
	_car.step(DT, 0.0, 3, false, 0.0)
	check_eq(_car.edge_touched, CarSim.EDGE_NONE, "on an undivided road the oncoming lane can be driven in")
	check_eq(_car.lane_of(_car.x), -1, "it is lane -1")

	# Left of the oncoming lane stands a rail, undivided_left_rail_margin beyond
	# its edge (DECISIONS D-023): touching it is a scrape like any other.
	var rail_x: float = -tuning.f("lane_width") - tuning.f("undivided_left_rail_margin")
	check_near(_car.left_limit_x(), rail_x, 0.000001, "on an undivided road the left limit is a rail undivided_left_rail_margin beyond the oncoming lane")
	collision.reset()
	touched = false
	for _tick: int in int(3.0 / DT):
		x_before = _car.x
		_car.step(DT, -0.4, 3, false, 0.0)
		speed_before = _car.speed
		collision.step(DT, _car, traffic, 3)
		if _car.edge_touched != CarSim.EDGE_NONE:
			touched = true
			break
	if check(touched, "steering on to the left across the oncoming lane touches the rail beyond it"):
		check_eq(_car.edge_touched, CarSim.EDGE_LEFT, "on the left")
		check_near(_car.x, rail_x + half + tuning.f("hit_pushback"), 0.000001, "the car is pushed hit_pushback back from the rail")
		check_eq(collision.hit, Collision.Hit.SCRAPE, "touching the rail left of the oncoming lane is a scrape")
		check_eq(collision.hit_lamps, int(tuning.fi("hit_lamps", 0)), "which lights one lamp")
		check_near(_car.speed, speed_before * (1.0 - tuning.f("scrape_speed_loss")), 0.000001, "and takes scrape_speed_loss off the speed")
		var short_of_left_rail: float = (x_before - half) - rail_x
		check(short_of_left_rail > 0.0 and short_of_left_rail <= one_tick, "it touched as its left side got to the rail: the tick before, that side was short of it by less than a tick of travel")
	_car.set_road(3, true)


## The edges through the whole simulation, steered into with the mouse: each
## is a scrape (GDD 5.1, 5.6).
func _check_edges_in_sim() -> void:
	_scrape_edge_in_sim("the median barrier", 3, true, 0, -1.0)
	_scrape_edge_in_sim("the rail left of the oncoming lane", 1, false, 0, -1.0)
	_scrape_edge_in_sim("the guardrail", 3, true, 2, 1.0)


## The right side of GDD 5.1 through the whole simulation: the rumble strip is
## sound only; the rough shoulder caps the speed, whatever the lever, and
## frays him. An encounter silences the empty road's calm (GDD 6.1), so Nerves
## show the surface alone, as tests/test_nerves.gd does.
func _check_strip_and_shoulder_in_sim() -> void:
	var third: float = tuning.fi("gear_speeds", 2)
	var fourth: float = tuning.fi("gear_speeds", 3)
	var cap: float = tuning.f("shoulder_speed_cap")
	var strip: float = tuning.f("rumble_strip_width")
	var input: DriveInput = DriveInput.new()

	var sim: DriveSim = DriveSim.new(fresh_data())
	sim.in_encounter = true
	sim.gate.reset(3)
	sim.car.reset(2, 3)
	var strip_x: float = sim.car.road_right() - sim.car.half_width() + strip * 0.5
	var nerves_start: float = sim.nerves.value
	for _tick: int in int(3.0 / DT):
		sim.car.x = strip_x
		sim.step(input)
	check(sim.car.on_rumble and not sim.car.on_shoulder, "the whole simulation: the car is held with its right edge on the rumble strip")
	check_near(sim.car.speed, third, 0.000001, "3 s on the rumble strip have not slowed it")
	check_near(sim.nerves.value - nerves_start, 0.0, 0.000001, "nor frayed him: the strip is sound only")
	check_eq(sim.faults.lamps, 0, "and no lamp is lit")

	# The shoulder, with the lever out of gear and the car at fourth's speed.
	sim = DriveSim.new(fresh_data())
	sim.in_encounter = true
	sim.gate.reset(GearGate.NEUTRAL)
	sim.car.reset(2, 4)
	var shoulder_x: float = sim.car.road_right() + strip + tuning.f("shoulder_width") * 0.5
	sim.car.x = shoulder_x
	sim.step(input)
	sim.car.speed = fourth
	nerves_start = sim.nerves.value
	var to_cap: float = (fourth - cap) / tuning.f("engine_brake")
	var covered: float = sim.car.s
	for _tick: int in roundi(to_cap / DT):
		sim.car.x = shoulder_x
		sim.step(input)
	covered = sim.car.s - covered
	check(sim.car.on_shoulder and not sim.car.on_rumble, "the whole simulation: the car is held on the rough shoulder")
	check_eq(sim.gate.gear, GearGate.NEUTRAL, "with the lever in neutral")
	check_near(sim.car.speed, cap, 0.000001, "it is down to shoulder_speed_cap after (fourth - cap) / engine_brake seconds")
	check_near(covered, (fourth + cap) * 0.5 * KMH_TO_MS * to_cap, fourth * KMH_TO_MS * DT, "having covered the ground of a car slowing at engine_brake, not of one coasting")
	check_near(sim.nerves.value - nerves_start, tuning.f("shoulder_nerves_rate") * to_cap, 0.001, "the rough shoulder adds shoulder_nerves_rate per second")


func _check_drifts() -> void:
	var cap: float = tuning.f("curve_cap")
	var ks: PackedFloat64Array = tuning.floats("curve_k")

	# Curve: k x (speed / 100) squared, outward, capped.
	_car.reset(1, 3)
	for k: float in ks:
		check_near(_car.curve_push(k), minf(k, cap), 0.000001, "at 100 km/h a curve of k %s pushes k m/s" % str(k))
		check_near(_car.curve_push(-k), -minf(k, cap), 0.000001, "and the other way for a curve the other way")
	_car.reset(1, 4)
	var ratio: float = tuning.fi("gear_speeds", 3) / 100.0
	check_near(_car.curve_push(ks[0]), ks[0] * ratio * ratio, 0.000001, "the push grows with the square of the speed")
	check_near(_car.curve_push(ks[2]), cap, 0.000001, "and is capped at curve_cap")
	check(ks[2] * ratio * ratio > cap, "(the sharpest curve in fourth would exceed the cap)")
	_car.reset(1, 2)
	ratio = tuning.fi("gear_speeds", 1) / 100.0
	check_near(_car.curve_push(ks[1]), ks[1] * ratio * ratio, 0.000001, "slower is gentler")

	# The push moves the car: with the crown cancelled, x moves by push x time.
	_car.reset(1, 3)
	var start: float = _car.x
	for _tick: int in int(1.0 / DT):
		_car.step(DT, 0.0, 3, false, _car.curve_push(ks[1]) - tuning.f("crown_drift"))
	check_near(_car.x - start, ks[1], 0.001, "a curve of k 1.0 at 100 km/h carries the car 1 m outward in a second")

	# A gust: gust_push for gust_duration, through DriveSim. The tolerance is a
	# quarter of one tick of push, so one tick too many or too few is caught.
	var calm: DriveSim = DriveSim.new(fresh_data())
	var gusty: DriveSim = DriveSim.new(fresh_data())
	var input: DriveInput = DriveInput.new()
	gusty.start_gust(-1)
	var ticks: int = int((tuning.f("gust_duration") + 1.0) / DT)
	var pushed_ticks: int = 0
	for _tick: int in ticks:
		var apart: float = gusty.car.x - calm.car.x
		calm.step(input)
		gusty.step(input)
		if absf(gusty.car.x - calm.car.x - apart) > 0.000000001:
			pushed_ticks += 1
	check_near(gusty.car.x - calm.car.x, -tuning.f("gust_push") * tuning.f("gust_duration"), tuning.f("gust_push") * DT * 0.25, "a gust pushes gust_push for gust_duration, then stops")
	check_eq(pushed_ticks, roundi(tuning.f("gust_duration") / DT), "it pushes for gust_duration in whole ticks, not one more")
	var half_way: DriveSim = DriveSim.new(fresh_data())
	half_way.start_gust(1)
	for _tick: int in int(tuning.f("gust_duration") * 0.5 / DT):
		half_way.step(input)
	check_near(half_way.car.drift, tuning.f("crown_drift") + tuning.f("gust_push"), 0.000001, "during the gust the drift is crown plus gust_push")

	# The other way, and stronger: start_gust's direction and strength.
	var strong_calm: DriveSim = DriveSim.new(fresh_data())
	var strong: DriveSim = DriveSim.new(fresh_data())
	strong.start_gust(1, 2.0)
	for _tick: int in ticks:
		strong_calm.step(input)
		strong.step(input)
	check_near(strong.car.x - strong_calm.car.x, 2.0 * tuning.f("gust_push") * tuning.f("gust_duration"), tuning.f("gust_push") * DT * 0.25, "a gust of strength 2 toward the right shoulder carries the car twice as far that way")

	# Other lengths are as exact. A gust lasts the nearest whole number of ticks
	# to its duration: three times gust_duration is three times the ticks, and a
	# duration between two ticks goes to the nearer one.
	var whole: int = roundi(tuning.f("gust_duration") / DT)
	check_eq(_gust_ticks(tuning.f("gust_duration") * 3.0), whole * 3, "a gust three times as long pushes for three times as many ticks, not one more")
	check_eq(_gust_ticks(tuning.f("gust_duration") + DT * 0.6), whole + 1, "a duration 0.6 of a tick longer is one tick longer")
	check_eq(_gust_ticks(tuning.f("gust_duration") + DT * 0.4), whole, "and one 0.4 of a tick longer is no longer")


## A curve through the whole simulation: DriveSim.curve_k bends the road, and
## the push carries a car nobody steers outward, on top of the crown (GDD 5.4).
func _check_curve_in_sim() -> void:
	var crown: float = tuning.f("crown_drift")
	var cap: float = tuning.f("curve_cap")
	var input: DriveInput = DriveInput.new()
	for gear: int in [3, 4]:
		var ratio: float = tuning.fi("gear_speeds", gear - 1) / 100.0
		for k: float in tuning.floats("curve_k"):
			for side: float in [1.0, -1.0]:
				var sim: DriveSim = DriveSim.new(fresh_data())
				sim.gate.reset(gear)
				sim.car.reset(1, gear)
				sim.curve_k = side * k
				var start: float = sim.car.x
				var ticks: int = roundi(0.5 / DT)
				for _tick: int in ticks:
					sim.step(input)
				var rate: float = (sim.car.x - start) / (float(ticks) * DT)
				var push: float = side * minf(k * ratio * ratio, cap)
				check_near(rate, crown + push, 0.000001, "hands off in gear %d with curve_k %s the car moves at the crown and the curve's push of %s m/s" % [gear, str(side * k), str(push)])


## Drift and forward speed (DECISIONS: drift at rest). All sideways drift is
## scaled by speed / drift_fade_speed, up to 1: a car at rest is not pushed
## sideways at all, and from drift_fade_speed up nothing changes.
func _check_drift_at_low_speed() -> void:
	var crown: float = tuning.f("crown_drift")
	var gust: float = tuning.f("gust_push")
	var fade: float = tuning.f("drift_fade_speed")
	var lat: float = tuning.f("lat_per_kmh")
	var coast_tick: float = tuning.f("neutral_coast") * DT
	check(fade > 0.0 and fade <= tuning.fi("gear_speeds", 0), "drift_fade_speed is no more than first gear's cruise speed: in every gear the drift of GDD 5.4 is whole")
	check(crown / fade < lat, "below it the crown grows more slowly with speed than full lock does: steering always beats the crown")

	# At rest nothing pushes the car sideways.
	_car.reset(1, 3)
	check_eq(_sideways_rate(0.0, CarSim.NEUTRAL, 0.0), 0.0, "at rest the crown does not move the car")
	check_eq(_car.speed, 0.0, "(it is at rest)")
	check_eq(_sideways_rate(0.0, CarSim.NEUTRAL, 0.0, gust), 0.0, "nor does a gust or a curve to the right")
	check_eq(_sideways_rate(0.0, CarSim.NEUTRAL, 0.0, -gust), 0.0, "or to the left")
	check_eq(_sideways_rate(-1.0, CarSim.NEUTRAL, 0.0), 0.0, "and with the wheel at full lock a car at rest stays where it is")
	check_eq(_car.drift, 0.0, "the drift it reports is zero")

	# Rolling slower than drift_fade_speed, every drift is in proportion to the speed.
	# (In neutral a tick takes neutral_coast x DT off the speed it starts with.)
	check_near(_sideways_rate(0.0, CarSim.NEUTRAL, fade * 0.5 + coast_tick), crown * 0.5, 0.000001, "at half of drift_fade_speed the crown pushes half as hard")
	check_near(_car.speed, fade * 0.5, 0.000001, "(it rolls at half of drift_fade_speed)")
	check_near(_sideways_rate(0.0, CarSim.NEUTRAL, fade * 0.5 + coast_tick, gust), (crown + gust) * 0.5, 0.000001, "and a gust on top of it half as hard as well")
	check_near(_sideways_rate(0.0, CarSim.NEUTRAL, fade * 0.25 + coast_tick, -gust), (crown - gust) * 0.25, 0.000001, "at a quarter of it, a quarter")

	# From drift_fade_speed up the drift is whole.
	check_near(_sideways_rate(0.0, CarSim.NEUTRAL, fade + coast_tick), crown, 0.000001, "at drift_fade_speed the crown is whole")
	check_near(_car.speed, fade, 0.000001, "(it rolls at drift_fade_speed)")
	check_near(_sideways_rate(0.0, CarSim.NEUTRAL, fade + coast_tick, -gust), crown - gust, 0.000001, "and so is a gust")
	check_near(_sideways_rate(0.0, CarSim.NEUTRAL, fade * 1.5), crown, 0.000001, "above it nothing changes")

	# So full left lock beats the crown at any speed, down to a crawl.
	for share: float in [0.05, 0.25, 0.5, 1.0]:
		var rate: float = _sideways_rate(-1.0, CarSim.NEUTRAL, fade * share + coast_tick)
		check_near(rate, -lat * _car.speed + crown * share, 0.001, "at %s km/h full left lock moves the car left: steering less the crown's share" % str(fade * share))
		check(rate < 0.0, "at %s km/h the car answers the wheel, not the crown" % str(fade * share))

	# A drift_fade_speed of 0 switches the fade off (and divides nothing by zero).
	var plain_data: GameData = fresh_data()
	plain_data.tuning.set_value("drift_fade_speed", 0.0)
	var plain: CarSim = CarSim.new()
	plain.configure(plain_data.tuning)
	plain.set_road(3, true)
	plain.reset(1, 3)
	plain.speed = 0.0
	var plain_x: float = plain.x
	for _tick: int in int(1.0 / DT):
		plain.step(DT, 0.0, CarSim.NEUTRAL, false, 0.0)
	check_near(plain.x - plain_x, crown, 0.000001, "with drift_fade_speed 0 there is no fade: the crown is whole even at rest")

	# The whole simulation: a parked car is moved neither by a gust nor by a curve.
	var input: DriveInput = DriveInput.new()
	var parked: DriveSim = DriveSim.new(fresh_data())
	parked.gate.reset(GearGate.NEUTRAL)
	parked.car.reset(1, 3)
	parked.car.speed = 0.0
	parked.curve_k = tuning.fi("curve_k", 2)
	parked.start_gust(-1)
	var parked_x: float = parked.car.x
	for _tick: int in int((tuning.f("gust_duration") + 1.0) / DT):
		parked.step(input)
	check_eq(parked.car.x, parked_x, "in the whole simulation a parked car is moved neither by a gust nor by a curve")
	check_eq(parked.car.s, 0.0, "(it is parked)")


# --- Through the whole simulation, with real input -------------------------------

## Steering with the mouse (GDD 4.1, 4.3, 5.3): hold the left button with the
## hand on the rim (it starts there), then move left and right.
func _check_steering_in_sim() -> void:
	var third: float = tuning.fi("gear_speeds", 2)
	var full: float = tuning.f("lat_per_kmh") * third
	var crown: float = tuning.f("crown_drift")
	var lock_px: float = tuning.f("wheel_max_angle") / tuning.f("steer_deg_per_px")
	var sim: DriveSim = DriveSim.new(fresh_data())
	sim.gate.reset(3)
	sim.car.reset(1, 3)
	var input: DriveInput = DriveInput.new()
	input.lmb = true
	sim.step(input)
	if not check(sim.hand.gripping, "in the whole simulation, holding the left button with the hand on the rim grips the wheel"):
		return
	check_near(_sim_sideways_rate(sim, input), crown, 0.001, "gripped and not turned, the wheel is straight: the car moves with the crown alone")
	_drag(sim, input, lock_px * 1.2)
	check_near(_sim_sideways_rate(sim, input), full + crown, 0.001, "the mouse dragged right to full lock at 100 km/h: the car moves 5.0 m/s to the right, plus the crown")
	check_near(sim.car.v_lat, full, 0.001, "and its v_lat has settled at lat_per_kmh x speed")
	_drag(sim, input, -lock_px * 2.4)
	check_near(_sim_sideways_rate(sim, input), -full + crown, 0.001, "dragged left to full lock: it moves 5.0 m/s to the left, less the crown")
	check_near(sim.car.v_lat, -full, 0.001, "with v_lat settled the other way")
	_drag(sim, input, lock_px * 1.5)
	check_near(_sim_sideways_rate(sim, input), full * 0.5 + crown, 0.001, "dragged back to half right lock: half as fast to the right (steer = wheel_angle / wheel_max_angle)")
	check(sim.hand.gripping, "(the hand held the wheel throughout)")
	input.lmb = false
	check_near(_sim_sideways_rate(sim, input), crown, 0.001, "the button released, the wheel returns to centre and the car moves by drift alone")
	check_near(sim.car.speed, third, 0.000001, "all of it at third gear's cruise speed")
	check_eq(sim.faults.lamps, 0, "and without touching anything")


## Braking with the right button (GDD 4.1, 4.8), and what the car does at rest:
## nothing. `expected` is the stopping time and `ideal` the stopping distance.
func _check_braking_in_sim(expected: float, ideal: float) -> void:
	var third: float = tuning.fi("gear_speeds", 2)
	var sim: DriveSim = DriveSim.new(fresh_data())
	sim.gate.reset(3)
	sim.car.reset(1, 3)
	var input: DriveInput = DriveInput.new()
	input.rmb = true
	var rest_tick: int = -1
	for tick: int in int(10.0 / DT):
		var s_before: float = sim.car.s
		sim.step(input)
		if sim.car.s == s_before:
			rest_tick = tick
			break
	check_near(float(rest_tick + 1) * DT, expected, DT, "in the whole simulation, holding the right button from third gear brings the car to rest in 3.33 s")
	check_near(sim.car.s, ideal, third * KMH_TO_MS * DT, "in the same distance")
	check_eq(sim.car.speed, 0.0, "its speed reads zero")
	check_eq(sim.gate.gear, 3, "(the lever is still in third)")

	# Braked to rest and left alone, hands off: the car stays where it stopped.
	# It does not slide down the crown into the guardrail (GDD 4.8, 5.1, 10.3).
	var x_rest: float = sim.car.x
	var s_rest: float = sim.car.s
	sim.drain_events()
	for _tick: int in int(30.0 / DT):
		sim.step(input)
	check_eq(sim.car.x, x_rest, "braked to rest, hands off, brake held for 30 s: the car has not moved sideways")
	check_eq(sim.car.s, s_rest, "nor along the road")
	check(not sim.car.on_rumble and not sim.car.on_shoulder and sim.car.lane_of(sim.car.x) == 1, "it is still in its lane")
	check_eq(sim.faults.lamps, 0, "no lamp is lit")
	check_eq(_count_events(sim, "hit"), 0, "nothing was hit")
	check(not sim.wrecked, "and the car is no Wreck")

	# Out of gear with the brake released it is parked just the same.
	sim.gate.reset(GearGate.NEUTRAL)
	input.rmb = false
	for _tick: int in int(5.0 / DT):
		sim.step(input)
	check_eq(sim.car.x, x_rest, "parked in neutral with the brake released it stays put as well")
	check_eq(sim.car.s, s_rest, "(it has not rolled)")

	# Back in gear it pulls away at accel, and the crown returns with the speed.
	sim.gate.reset(3)
	for _tick: int in int(1.0 / DT):
		sim.step(input)
	var accel_ms: float = tuning.f("accel") * KMH_TO_MS
	check_near(sim.car.s - s_rest, accel_ms * 0.5, accel_ms * DT, "in gear with the brake released the car pulls away at accel")
	var crept: float = sim.car.x - x_rest
	check(crept > 0.0 and crept < tuning.f("crown_drift"), "and as it gathers speed the crown begins to carry it right again, more gently than at speed")
	check_eq(sim.faults.lamps, 0, "still with no lamp lit")


## The whole simulation on a road of `lanes`, steered with the mouse from the
## middle of `lane` to full lock toward `side` (-1 left, 1 right) until the
## car meets the edge of the road. The touch must be a scrape (GDD 5.1, 5.6).
func _scrape_edge_in_sim(edge: String, lanes: int, divided: bool, lane: int, side: float) -> void:
	var sim: DriveSim = DriveSim.new(fresh_data())
	sim.set_road(lanes, divided)
	sim.gate.reset(3)
	sim.car.reset(lane, 3)
	var input: DriveInput = DriveInput.new()
	input.lmb = true
	sim.step(input)
	_drag(sim, input, side * 1.2 * tuning.f("wheel_max_angle") / tuning.f("steer_deg_per_px"))
	sim.drain_events()
	var touched: bool = false
	var nerves_before: float = 0.0
	var speed_before: float = 0.0
	var x_before: float = 0.0
	for _tick: int in int(5.0 / DT):
		nerves_before = sim.nerves.value
		speed_before = sim.car.speed
		x_before = sim.car.x
		sim.step(input)
		if sim.car.edge_touched != CarSim.EDGE_NONE:
			touched = true
			break
	if not check(touched, "%s: steered there with the mouse at full lock, the car touches it" % edge):
		return
	var pushback: float = tuning.f("hit_pushback")
	var pushed_to: float = sim.car.left_limit_x() + sim.car.half_width() + pushback
	var short_of_it: float = (x_before - sim.car.half_width()) - sim.car.left_limit_x()
	if side > 0.0:
		pushed_to = sim.car.guardrail_x() - sim.car.half_width() - pushback
		short_of_it = sim.car.guardrail_x() - (x_before + sim.car.half_width())
	var one_tick: float = (tuning.f("lat_per_kmh") * tuning.fi("gear_speeds", 2) + tuning.f("crown_drift")) * DT
	check_eq(sim.car.edge_touched, CarSim.EDGE_RIGHT if side > 0.0 else CarSim.EDGE_LEFT, "%s: on its side of the road" % edge)
	check(short_of_it > 0.0 and short_of_it <= one_tick, "%s: the car touched it as its side got there: the tick before, it was short of it by less than a tick of travel" % edge)
	check_near(sim.car.x, pushed_to, 0.000001, "%s: the car is pushed hit_pushback back from it" % edge)
	check_eq(sim.collision.hit, Collision.Hit.SCRAPE, "%s: touching it is a scrape" % edge)
	check_eq(sim.faults.lamps, int(tuning.fi("hit_lamps", 0)), "%s: one lamp is lit" % edge)
	check_near(sim.nerves.value - nerves_before, tuning.fi("hit_nerves", 0), 0.02, "%s: a scrape's Nerves are added" % edge)
	check_near(sim.car.speed, speed_before * (1.0 - tuning.f("scrape_speed_loss")), tuning.f("engine_brake") * DT, "%s: scrape_speed_loss comes off the speed" % edge)
	check_eq(sim.gate.gear, 3, "%s: a scrape forces no gear" % edge)
	var hit_events: int = 0
	var rail_events: int = 0
	for event: Dictionary in sim.drain_events():
		if GameData.as_string(event.get("type")) == "hit":
			hit_events += 1
			if GameData.as_int(event.get("vehicle"), -1) == 0:
				rail_events += 1
	check(hit_events == 1 and rail_events == 1, "%s: the scrape is announced once, as a hit on no vehicle" % edge)

	# Held against it at full lock the car is back at once, but it cannot be hit
	# again for hit_immunity (GDD 5.6); the first touch after that is a scrape.
	var lamps: int = sim.faults.lamps
	var touches: int = 0
	for _tick: int in int(tuning.f("hit_immunity") / DT) - 2:
		sim.step(input)
		if sim.car.edge_touched != CarSim.EDGE_NONE:
			touches += 1
	check(touches > 0, "%s: held at full lock the car is against it again within hit_immunity" % edge)
	check_eq(sim.faults.lamps, lamps, "%s: but it cannot be hit again for hit_immunity" % edge)
	var again: bool = false
	for _tick: int in int(1.0 / DT):
		sim.step(input)
		if sim.collision.hit != Collision.Hit.NONE:
			again = true
			break
	check(again and sim.faults.lamps == lamps + int(tuning.fi("hit_lamps", 0)), "%s: once hit_immunity is over the next touch is a scrape again" % edge)


# --- Helpers ------------------------------------------------------------------

## Steps the car for `seconds`, held in the middle of lane 1.
func _run_centered(seconds: float, gear: int, braking: bool) -> void:
	for _tick: int in roundi(seconds / DT):
		_car.step(DT, 0.0, gear, braking, 0.0)
		_car.x = _car.lane_center(1)


## Seconds to cover `distance` in a gear, steering just enough to hold the lane.
func _seconds_for(distance: float, gear: int) -> float:
	_car.reset(1, gear)
	var target: float = _car.lane_center(1)
	for tick: int in int(400.0 / DT):
		var steer: float = clampf((target - _car.x) * 0.5, -1.0, 1.0)
		_car.step(DT, steer, gear, false, 0.0)
		if _car.s >= distance:
			if not _car.on_rumble and not _car.on_shoulder:
				return float(tick + 1) * DT
			return INF
	return INF


## Metres per second the bare car really moves sideways, measured from x over
## MEASURE seconds after SETTLE seconds, at `steer` with the lever in `gear`.
## The car is put back in the middle of lane 1 before every tick. With
## `rolling_at` (km/h) the speed is put back before every tick too; the tick
## then changes it as the lever dictates, and _car.speed afterwards is the
## speed the car moved at.
func _sideways_rate(steer: float, gear: int, rolling_at: float = -1.0, extra_drift: float = 0.0) -> float:
	var centre: float = _car.lane_center(1)
	var settle_ticks: int = roundi(SETTLE / DT)
	var measure_ticks: int = roundi(MEASURE / DT)
	var travel: float = 0.0
	for tick: int in settle_ticks + measure_ticks:
		_car.x = centre
		if rolling_at >= 0.0:
			_car.speed = rolling_at
		_car.step(DT, steer, gear, false, extra_drift)
		if tick >= settle_ticks:
			travel += _car.x - centre
	_car.x = centre
	return travel / (float(measure_ticks) * DT)


## The same for the car of a whole simulation in lane 1, with `input` held.
func _sim_sideways_rate(sim: DriveSim, input: DriveInput) -> float:
	var centre: float = sim.car.lane_center(1)
	var settle_ticks: int = roundi(SETTLE / DT)
	var measure_ticks: int = roundi(MEASURE / DT)
	var travel: float = 0.0
	for tick: int in settle_ticks + measure_ticks:
		sim.car.x = centre
		sim.step(input)
		if tick >= settle_ticks:
			travel += sim.car.x - centre
	sim.car.x = centre
	return travel / (float(measure_ticks) * DT)


## Moves the mouse `px` reference pixels sideways within one tick, then holds it still.
func _drag(sim: DriveSim, input: DriveInput, px: float) -> void:
	input.pointer_delta = Vector2(px, 0.0)
	sim.step(input)
	input.pointer_delta = Vector2.ZERO


## Puts the bare car on the rough shoulder at `x`, knowing it is there, at `speed`.
func _put_on_shoulder(x: float, speed: float) -> void:
	_car.reset(2, 4)
	_car.x = x
	_car.step(DT, 0.0, CarSim.NEUTRAL, false, -tuning.f("crown_drift"))
	_car.speed = speed


## Steps the bare car for `seconds` where it is: the crown is cancelled.
func _hold_on_shoulder(seconds: float, gear: int, braking: bool) -> void:
	for _tick: int in roundi(seconds / DT):
		_car.step(DT, 0.0, gear, braking, -tuning.f("crown_drift"))


## Ticks during which a gust pushes the car of a whole simulation whose
## gust_duration is `duration`, counted from the car's movement against a calm
## twin. Also checks that the gust carried the car gust_push x that many ticks.
func _gust_ticks(duration: float) -> int:
	var gust_data: GameData = fresh_data()
	gust_data.tuning.set_value("gust_duration", duration)
	var calm: DriveSim = DriveSim.new(fresh_data())
	var gusty: DriveSim = DriveSim.new(gust_data)
	var input: DriveInput = DriveInput.new()
	gusty.start_gust(-1)
	var pushed_ticks: int = 0
	for _tick: int in int((duration + 1.0) / DT):
		var apart: float = gusty.car.x - calm.car.x
		calm.step(input)
		gusty.step(input)
		if absf(gusty.car.x - calm.car.x - apart) > 0.000000001:
			pushed_ticks += 1
	check_near(gusty.car.x - calm.car.x, -tuning.f("gust_push") * float(pushed_ticks) * DT, 0.000001, "a gust of %s s carries the car gust_push for every tick it lasts" % str(duration))
	return pushed_ticks


## How many events of one type the simulation queued since the last drain.
func _count_events(sim: DriveSim, type: String) -> int:
	var count: int = 0
	for event: Dictionary in sim.drain_events():
		if GameData.as_string(event.get("type")) == type:
			count += 1
	return count
