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

## Multipliers that adaptations change (GDD 7.6, Spinner knob).
var turn_rate_mult: float = 1.0
var return_rate_mult: float = 1.0

var _max_angle: float = 0.0
var _deg_per_px: float = 0.0
var _smoothing_s: float = 0.0
var _return_rate: float = 0.0


func configure(tuning: Tuning) -> void:
	_max_angle = tuning.f("wheel_max_angle")
	_deg_per_px = tuning.f("steer_deg_per_px")
	_smoothing_s = tuning.f("wheel_smoothing") * 0.001
	_return_rate = tuning.f("wheel_return_rate")


func reset(angle_deg: float = 0.0) -> void:
	angle = clampf(angle_deg, -_max_angle, _max_angle)
	command = angle
	gripped = false


func grip() -> void:
	if not gripped:
		gripped = true
		command = angle


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
		angle += (command - angle) * blend
	else:
		angle = move_toward(angle, 0.0, _return_rate * return_rate_mult * dt)
		command = angle


## Steering input to the car: -1 (full left) to 1 (full right), GDD 5.3.
func steer() -> float:
	return angle / _max_angle


func max_angle() -> float:
	return _max_angle
