class_name WheelSim
extends RefCounted
## The steering wheel (GDD 4.3).
##
## Angles are degrees, positive clockwise as the driver sees it (a right turn),
## from -wheel_max_angle to +wheel_max_angle. While gripped, sideways pointer
## motion moves a commanded angle and the wheel follows it with
## wheel_smoothing. Released, it returns to centre at wheel_return_rate.
## Gripping never snaps the wheel: the hand takes it at the angle it has.

var angle: float = 0.0
var command: float = 0.0
var gripped: bool = false
## Degrees the Tremor adds to the gripped wheel right now (GDD 5.8); set by
## DriveSim before step().
var tremor: float = 0.0

## Multipliers that adaptations change (GDD 7.6, Spinner knob).
var turn_rate_mult: float = 1.0
var return_rate_mult: float = 1.0
## Seconds the car's steering lags behind the wheel (GDD 5.8, Lag); set by
## DriveSim before step(). Never more than lag_cap.
var lag: float = 0.0
## The hook holds the wheel (GDD 7.6, Wheel ring): let go, it stays at the
## angle it has instead of returning to centre. Set by DriveSim.
var locked: bool = false

var _max_angle: float = 0.0
var _deg_per_px: float = 0.0
var _smoothing_s: float = 0.0
var _return_rate: float = 0.0
## Where the hand holds the wheel, before the Tremor is added.
var _held: float = 0.0
var _lag_cap_s: float = 0.0
## The wheel's angle at the end of each of the last ticks (a ring: the
## newest is at _trail_at), far enough back for lag_cap; and the tick's length.
var _trail: PackedFloat64Array = PackedFloat64Array()
var _trail_at: int = 0
var _dt: float = 0.0


func configure(tuning: Tuning) -> void:
	_max_angle = tuning.f("wheel_max_angle")
	_deg_per_px = tuning.f("steer_deg_per_px")
	_smoothing_s = tuning.f("wheel_smoothing") * 0.001
	_return_rate = tuning.f("wheel_return_rate")
	_lag_cap_s = tuning.f("lag_cap") * 0.001


func reset(angle_deg: float = 0.0) -> void:
	angle = clampf(angle_deg, -_max_angle, _max_angle)
	command = angle
	_held = angle
	gripped = false
	_trail.fill(angle)


## The hand takes the wheel at the angle it has. If his hand is shaking, the
## shake starts from there: the wheel does not jump.
func grip() -> void:
	if not gripped:
		gripped = true
		_held = angle - tremor
		command = _held


func release() -> void:
	gripped = false


## `steer_px` is sideways pointer motion in reference pixels this tick;
## `sensitivity` is the steering sensitivity setting (1.0 = 100%).
func step(dt: float, steer_px: float, sensitivity: float) -> void:
	if gripped:
		command = clampf(command + steer_px * _deg_per_px * sensitivity * turn_rate_mult, -_max_angle, _max_angle)
		var blend: float = 1.0
		if _smoothing_s > 0.0:
			blend = 1.0 - exp(-dt / _smoothing_s)
		_held += (command - _held) * blend
		angle = clampf(_held + tremor, -_max_angle, _max_angle)
	elif locked:
		command = angle
		_held = angle
	else:
		angle = move_toward(angle, 0.0, _return_rate * return_rate_mult * dt)
		command = angle
		_held = angle
	_remember(dt)


## The hook turns the wheel to an angle (GDD 7.8: with a spinner knob it
## keeps the lane on a straight). Only while locked.
func hold_at(angle_deg: float) -> void:
	if locked and not gripped:
		angle = clampf(angle_deg, -_max_angle, _max_angle)
		command = angle
		_held = angle


## Steering input to the car: -1 (full left) to 1 (full right), GDD 5.3. It
## is the wheel's angle, Tremor and all, `lag` seconds ago.
func steer() -> float:
	return lagged_angle() / _max_angle


## The angle the car is steered by now: the wheel's, `lag` seconds ago.
func lagged_angle() -> float:
	if lag <= 0.0 or _trail.is_empty() or _dt <= 0.0:
		return angle
	var size: int = _trail.size()
	var ticks: float = minf(lag, _lag_cap_s) / _dt
	var whole: int = mini(int(floorf(ticks)), size - 2)
	var newer: float = _trail[posmod(_trail_at - whole, size)]
	var older: float = _trail[posmod(_trail_at - whole - 1, size)]
	return lerpf(newer, older, clampf(ticks - float(whole), 0.0, 1.0))


func _remember(dt: float) -> void:
	if _trail.is_empty() or dt != _dt:
		# As many ticks back as lag_cap is long, and one more to lean on.
		_dt = dt
		_trail.resize(int(ceilf(_lag_cap_s / dt)) + 2)
		_trail.fill(angle)
		_trail_at = 0
	_trail_at = (_trail_at + 1) % _trail.size()
	_trail[_trail_at] = angle


func max_angle() -> float:
	return _max_angle
