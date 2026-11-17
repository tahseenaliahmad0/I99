extends TestSuite
## M1: the steering wheel (GDD 4.3).

const DT: float = DriveSim.DT

var _wheel: WheelSim
var _space: CabinSpace
var _hand: HandSim
var _input: DriveInput


func before_each() -> void:
	_wheel = WheelSim.new()
	_wheel.configure(tuning)
	_space = CabinSpace.new()
	_space.configure(data)
	_hand = HandSim.new()
	_hand.configure(data, _space)
	_input = DriveInput.new()


## T-WHEEL-01: released at 135 degrees, the wheel reaches centre in 0.675 s.
func test_wheel_01() -> void:
	var max_angle: float = tuning.f("wheel_max_angle")
	var expected: float = max_angle / tuning.f("wheel_return_rate")
	for start: float in [max_angle, -max_angle]:
		_wheel.reset(start)
		var seconds: float = _seconds_to_centre()
		check_near(seconds, expected, DT, "released at %s degrees, the wheel reaches centre" % str(start))
	check_near(expected, 0.675, 0.000001, "with the tuning of GDD 15 that is 0.675 s")

	# The return is linear: half the angle takes half the time.
	_wheel.reset(max_angle * 0.5)
	check_near(_seconds_to_centre(), expected * 0.5, DT, "the return rate is constant")

	# It stops at centre and stays there.
	for _tick: int in 20:
		_wheel.step(DT, 0.0, 1.0)
	check_eq(_wheel.angle, 0.0, "the released wheel rests at centre")


## T-WHEEL-02: grip zone, no snap on grip, steering rate, clamp, smoothing.
func test_wheel_02() -> void:
	_check_grip_zone()
	_check_grip_does_not_snap()
	_check_steering_rate()
	_check_smoothing()


func _check_grip_zone() -> void:
	var radius: float = tuning.f("wheel_radius")
	var half_width: float = tuning.f("grip_zone_half_width")
	var margin: float = 0.002
	# Along the line from the hub through G, so no anchor is near.
	var out: Vector3 = Vector3(_space.grip_reference.x, _space.grip_reference.y, 0.0).normalized()
	check(_space.pointer_on_rim(_space.point_to_pointer(out * radius)), "the rim itself is in the grip zone")
	check(_space.pointer_on_rim(_space.point_to_pointer(out * (radius + half_width - margin))), "just inside the outer edge of the grip zone grips")
	check(not _space.pointer_on_rim(_space.point_to_pointer(out * (radius + half_width + margin))), "just outside the outer edge does not")
	check(_space.pointer_on_rim(_space.point_to_pointer(out * (radius - half_width + margin))), "just inside the inner edge grips")
	check(not _space.pointer_on_rim(_space.point_to_pointer(out * (radius - half_width - margin))), "just inside the rim's hole does not")

	# Aimed at the outer edge of the zone, the hand still takes the rim itself.
	_hand.place_at(_space.grip_reference + Vector3(0.1, 0.1, 0.1))
	_input.pointer_is_absolute = true
	_input.pointer = _space.point_to_pointer(out * (radius + half_width - margin))
	_input.lmb = true
	for _tick: int in int(1.0 / DT):
		_hand.step(DT, _input, 0.0, 1.0)
	check(_hand.gripping, "a press in the grip zone grips")
	check(_hand.pos.is_equal_approx(out * radius), "the hand grips the nearest rim point")

	# Outside the zone the hand goes to the free point and never grips.
	_hand.place_at(_space.grip_reference + Vector3(0.1, 0.1, 0.1))
	_input.pointer = _space.point_to_pointer(out * (radius + half_width + 0.03))
	for _tick: int in int(1.0 / DT):
		_hand.step(DT, _input, 0.0, 1.0)
	check(not _hand.gripping, "a press outside the grip zone does not grip")
	_input.clear()


func _check_grip_does_not_snap() -> void:
	# The wheel is on its way back to centre when the hand takes it.
	_wheel.reset(80.0)
	for _tick: int in 12:
		_wheel.step(DT, 0.0, 1.0)
	var angle_before: float = _wheel.angle
	check(angle_before > 0.0 and angle_before < 80.0, "the released wheel is mid-return")
	_wheel.grip()
	check_eq(_wheel.angle, angle_before, "gripping does not change the wheel's angle")
	_wheel.step(DT, 0.0, 1.0)
	check_near(_wheel.angle, angle_before, 0.000001, "and with no pointer motion the gripped wheel holds that angle")
	for _tick: int in 60:
		_wheel.step(DT, 0.0, 1.0)
	check_near(_wheel.angle, angle_before, 0.000001, "a gripped wheel does not return to centre")


func _check_steering_rate() -> void:
	var per_px: float = tuning.f("steer_deg_per_px")
	var max_angle: float = tuning.f("wheel_max_angle")

	_wheel.reset(0.0)
	_wheel.grip()
	_wheel.step(DT, 100.0, 1.0)
	check_near(_wheel.command, 100.0 * per_px, 0.000001, "100 px to the right commands 100 x steer_deg_per_px")
	_wheel.step(DT, -250.0, 1.0)
	check_near(_wheel.command, -150.0 * per_px, 0.000001, "motion to the left turns the other way")

	_wheel.reset(0.0)
	_wheel.grip()
	_wheel.step(DT, 100.0, 2.0)
	check_near(_wheel.command, 200.0 * per_px, 0.000001, "the sensitivity setting scales the rate")
	_wheel.reset(0.0)
	_wheel.grip()
	_wheel.step(DT, 100.0, 0.5)
	check_near(_wheel.command, 50.0 * per_px, 0.000001, "down to 50%")

	# Window height: motion is scaled to reference pixels before it steers.
	var ref_height: float = tuning.f("reference_height")
	check_near(_space.to_reference(Vector2(100.0, 0.0), ref_height * 2.0).x, 50.0, 0.000001, "in a view twice as tall, the same motion is half as many reference pixels")
	check_near(_space.to_reference(Vector2(100.0, 0.0), ref_height).x, 100.0, 0.000001, "at 1080p motion is already in reference pixels")

	_wheel.reset(0.0)
	_wheel.grip()
	_wheel.step(DT, 100000.0, 1.0)
	check_eq(_wheel.command, max_angle, "the commanded angle is clamped at +wheel_max_angle")
	_wheel.step(DT, -1000000.0, 1.0)
	check_eq(_wheel.command, -max_angle, "and at -wheel_max_angle")
	for _tick: int in int(1.0 / DT):
		_wheel.step(DT, -50.0, 1.0)
	check(_wheel.angle >= -max_angle - 0.000001, "the wheel itself never passes the stop")
	check_near(_wheel.steer(), -1.0, 0.001, "full lock is steer -1")

	# Without a grip, pointer motion does not turn the wheel.
	_wheel.reset(0.0)
	_wheel.step(DT, 500.0, 1.0)
	check_eq(_wheel.angle, 0.0, "pointer motion does nothing to a wheel nobody holds")


func _check_smoothing() -> void:
	var tau: float = tuning.f("wheel_smoothing") * 0.001
	var per_px: float = tuning.f("steer_deg_per_px")
	_wheel.reset(0.0)
	_wheel.grip()
	_wheel.step(DT, 200.0, 1.0)
	var goal: float = 200.0 * per_px
	var ticks: int = 1
	var worst: float = 0.0
	var checked_tau: bool = false
	while float(ticks) * DT < tau * 6.0:
		var expected: float = goal * (1.0 - exp(-float(ticks) * DT / tau))
		worst = maxf(worst, absf(_wheel.angle - expected))
		if not checked_tau and float(ticks) * DT >= tau:
			checked_tau = true
			check_near(_wheel.angle / goal, 1.0 - exp(-float(ticks) * DT / tau), 0.0001, "after one wheel_smoothing the wheel has covered 63% of a step")
		_wheel.step(DT, 0.0, 1.0)
		ticks += 1
	check(worst < goal * 0.0001, "the wheel follows the commanded angle as a first-order lag (worst error %s degrees)" % str(worst))
	check_near(_wheel.angle, goal, goal * 0.005, "and settles on it")


func _seconds_to_centre() -> float:
	for tick: int in int(5.0 / DT):
		_wheel.step(DT, 0.0, 1.0)
		if _wheel.angle == 0.0:
			return float(tick + 1) * DT
	return INF
