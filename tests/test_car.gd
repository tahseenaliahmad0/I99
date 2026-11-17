extends TestSuite
## M2: the car in lane space (GDD 4.8, 5.1 to 5.4).

const DT: float = DriveSim.DT
const KMH_TO_MS: float = 1.0 / 3.6

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

	# The drift is toward the right shoulder, at crown_drift, at any speed.
	_car.reset(1, 1)
	var before: float = _car.x
	for _tick: int in int(1.0 / DT):
		_car.step(DT, 0.0, 1, false, 0.0)
	check_near(_car.x - before, tuning.f("crown_drift"), 0.001, "the crown pushes toward the right shoulder at crown_drift in any gear")


## T-CAR-02: full lock at 100 km/h settles at 5.0 m/s sideways.
func test_car_02() -> void:
	var expected: float = tuning.f("lat_per_kmh") * tuning.fi("gear_speeds", 2)
	check_near(expected, 5.0, 0.000001, "the tuning of GDD 15 gives 5.0 m/s at full lock in third")
	for lock: float in [1.0, -1.0]:
		_car.reset(1, 3)
		for _tick: int in int(1.5 / DT):
			_car.step(DT, lock, 3, false, 0.0)
			# Keep it on the road: this test is about sideways speed, not edges.
			_car.x = _car.lane_center(1)
		check_near(_car.v_lat, lock * 5.0, 0.001, "full lock (%s) at 100 km/h settles at 5.0 m/s sideways" % str(lock))

	# The table of GDD 5.2: sideways speed at full lock in every gear.
	for gear: int in [1, 2, 3, 4, 5]:
		_car.reset(1, gear)
		for _tick: int in int(1.5 / DT):
			_car.step(DT, 1.0, gear, false, 0.0)
			_car.x = _car.lane_center(1)
		check_near(_car.v_lat, tuning.f("lat_per_kmh") * tuning.fi("gear_speeds", gear - 1), 0.001, "full lock in gear %d" % gear)

	# The car follows the command with lat_follow_tau (first-order).
	var tau: float = tuning.f("lat_follow_tau")
	_car.reset(1, 3)
	var ticks: int = roundi(tau / DT)
	for _tick: int in ticks:
		_car.step(DT, 1.0, 3, false, 0.0)
	check_near(_car.v_lat / expected, 1.0 - exp(-float(ticks) * DT / tau), 0.001, "after one lat_follow_tau the car has 63% of its sideways speed")

	# Half lock is half the speed; the wheel at full lock is steer 1.
	_car.reset(1, 3)
	for _tick: int in int(1.5 / DT):
		_car.step(DT, 0.5, 3, false, 0.0)
		_car.x = _car.lane_center(1)
	check_near(_car.v_lat, expected * 0.5, 0.001, "half lock gives half the sideways speed")
	var wheel: WheelSim = WheelSim.new()
	wheel.configure(tuning)
	wheel.reset(tuning.f("wheel_max_angle"))
	check_near(wheel.steer(), 1.0, 0.000001, "the wheel at wheel_max_angle is full lock")


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


## T-CAR-05: speed changes, the road's edges and the drift sources.
func test_car_05() -> void:
	_check_speed_changes()
	_check_edges()
	_check_drifts()


func _check_speed_changes() -> void:
	var third: float = tuning.fi("gear_speeds", 2)
	var fourth: float = tuning.fi("gear_speeds", 3)

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


func _check_edges() -> void:
	var third: float = tuning.fi("gear_speeds", 2)
	var cap: float = tuning.f("shoulder_speed_cap")
	var road_right: float = tuning.f("lane_width") * 3.0
	var strip: float = tuning.f("rumble_strip_width")
	var half: float = _car.half_width()

	check_near(_car.road_right(), road_right, 0.000001, "three lanes are 3 x lane_width wide")
	check_near(_car.lane_center(0), tuning.f("lane_width") * 0.5, 0.000001, "lane 0 is centred half a lane from the left edge")
	check_near(_car.guardrail_x(), road_right + strip + tuning.f("shoulder_width"), 0.000001, "the guardrail stands beyond the strip and the shoulder")

	# In lane: neither strip nor shoulder.
	_car.reset(2, 3)
	_car.step(DT, 0.0, 3, false, 0.0)
	check(not _car.on_rumble and not _car.on_shoulder, "centred in the right lane the car is on neither strip nor shoulder")

	# A wheel on the rumble strip.
	_car.reset(2, 3)
	_car.x = road_right - half + strip * 0.5
	_car.step(DT, 0.0, 3, false, -tuning.f("crown_drift"))
	check(_car.on_rumble and not _car.on_shoulder, "with its right edge on the strip the car is on the rumble strip only")

	# On the rough shoulder: capped at shoulder_speed_cap.
	_car.reset(2, 3)
	_car.x = road_right + strip + half
	for _tick: int in int(3.0 / DT):
		_car.step(DT, 0.0, 3, false, -tuning.f("crown_drift"))
	check(_car.on_shoulder, "beyond the strip the car is on the shoulder")
	check_near(_car.speed, cap, 0.000001, "the shoulder caps speed at shoulder_speed_cap")
	check(third > cap, "which is below third gear's cruise speed")

	# The guardrail: a touch pushes the car hit_pushback back; Collision calls it a scrape.
	var collision: Collision = Collision.new()
	collision.configure(tuning)
	var traffic: TrafficSim = TrafficSim.new()
	traffic.configure(data)
	_car.reset(2, 3)
	_car.x = _car.guardrail_x() - half - 0.05
	var touched: bool = false
	var speed_before: float = 0.0
	for _tick: int in int(2.0 / DT):
		speed_before = _car.speed
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

	# The median barrier on a divided road.
	_car.set_road(3, true)
	_car.reset(0, 3)
	touched = false
	for _tick: int in int(3.0 / DT):
		_car.step(DT, -0.4, 3, false, 0.0)
		if _car.edge_touched != CarSim.EDGE_NONE:
			touched = true
			break
	if check(touched, "steering left on a divided road touches the median barrier"):
		check_eq(_car.edge_touched, CarSim.EDGE_LEFT, "on the left")
		check_near(_car.x, tuning.f("median_barrier_x") + half + tuning.f("hit_pushback"), 0.000001, "the car is pushed hit_pushback back from the barrier")

	# An undivided road has the oncoming lane on the left instead.
	_car.set_road(1, false)
	_car.reset(0, 3)
	_car.x = -tuning.f("lane_width") * 0.5
	_car.step(DT, 0.0, 3, false, 0.0)
	check_eq(_car.edge_touched, CarSim.EDGE_NONE, "on an undivided road the oncoming lane can be driven in")
	check_eq(_car.lane_of(_car.x), -1, "it is lane -1")
	_car.set_road(3, true)


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

	# A gust: gust_push for gust_duration, through DriveSim.
	var calm: DriveSim = DriveSim.new(fresh_data())
	var gusty: DriveSim = DriveSim.new(fresh_data())
	var input: DriveInput = DriveInput.new()
	gusty.start_gust(-1)
	var ticks: int = int((tuning.f("gust_duration") + 1.0) / DT)
	for _tick: int in ticks:
		calm.step(input)
		gusty.step(input)
	check_near(gusty.car.x - calm.car.x, -tuning.f("gust_push") * tuning.f("gust_duration"), 0.02, "a gust pushes gust_push for gust_duration, then stops")
	var half_way: DriveSim = DriveSim.new(fresh_data())
	half_way.start_gust(1)
	for _tick: int in int(tuning.f("gust_duration") * 0.5 / DT):
		half_way.step(input)
	check_near(half_way.car.drift, tuning.f("crown_drift") + tuning.f("gust_push"), 0.000001, "during the gust the drift is crown plus gust_push")


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
