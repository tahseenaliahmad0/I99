class_name CarSim
extends RefCounted
## The car in lane space (GDD 5.1 to 5.4, 4.8).
##
## The car has a position across the road (x, metres) and a distance along
## the leg (s, metres). Nothing else is simulated. Our carriageway runs from
## x = 0 to lane_width * lanes; lane i (0 is leftmost) is centred at
## lane_width * (i + 0.5).
##
## Right side: a rumble strip, then a rough shoulder, then a guardrail.
## Left side: a median barrier on divided roads; on undivided roads the
## oncoming lane and then a rail.
##
##   steer         = wheel_angle / wheel_max_angle            (-1 to 1)
##   v_lat_command = steer * lat_per_kmh * speed_kmh          (m/s)
##   v_lat         = follow(v_lat_command, lat_follow_tau)    (car inertia)
##   x            += (v_lat + sum_of_drifts) * dt
##
## Drift needs forward speed, as steering does: the sum of drifts is scaled by
## speed / drift_fade_speed, up to 1. A car at rest is not pushed sideways at
## all, and from drift_fade_speed up (slower than any gear cruises) the
## numbers of GDD 5.4 are exact.

const KMH_TO_MS: float = 1.0 / 3.6
const NEUTRAL: int = 0
const EDGE_NONE: int = 0
const EDGE_LEFT: int = -1
const EDGE_RIGHT: int = 1

# --- Road --------------------------------------------------------------------
var lanes: int = 3
var divided: bool = true

# --- State -------------------------------------------------------------------
var x: float = 0.0
var s: float = 0.0
## km/h along the road.
var speed: float = 0.0
## m/s sideways from steering alone.
var v_lat: float = 0.0
## m/s sideways from drift this tick (crown, curve, gust and extras), as it
## reached the car: scaled down below drift_fade_speed.
var drift: float = 0.0

# --- Modifiers set by DriveSim (items, faults, weather) ----------------------
## Added to the cruise speed of gears 4 and 5 (Turbo).
var high_gear_bonus: float = 0.0
## Scales braking (Turbo weakens it).
var brake_mult: float = 1.0
## Scales sideways speed at a given lock (Bull bar).
var lat_speed_mult: float = 1.0
## Scales the time the car takes to respond sideways (Rain).
var lat_tau_mult: float = 1.0
## How the road leans where the car is (D-074): the share of crown_drift it
## pushes with, + toward the right shoulder, - toward the left, 0 on a flat
## stretch. Set by DriveSim from the leg's plan before step(). A car with
## no road under it is on one that leans fully right, as every road once did.
var camber: float = 1.0

## Barriers beside the car (a checkpoint's corridor, GDD 10.2): the x of the
## one on its left and of the one on its right; -INF and INF where there is
## none. Set by DriveSim before step().
var wall_left: float = -INF
var wall_right: float = INF

# --- What happened this tick -------------------------------------------------
var on_rumble: bool = false
var on_shoulder: bool = false
## EDGE_LEFT or EDGE_RIGHT when the car touched a barrier or guardrail.
var edge_touched: int = EDGE_NONE
## The touch was on a barrier of a corridor.
var wall_touched: bool = false

var _lane_width: float = 0.0
var _half_width: float = 0.0
var _length: float = 0.0
var _gear_speeds: PackedFloat64Array = PackedFloat64Array()
var _lat_per_kmh: float = 0.0
var _lat_tau: float = 0.0
var _accel: float = 0.0
var _engine_brake: float = 0.0
var _brake_decel: float = 0.0
var _neutral_coast: float = 0.0
var _crown: float = 0.0
var _drift_fade_speed: float = 0.0
var _curve_cap: float = 0.0
var _shoulder_cap: float = 0.0
var _rumble_width: float = 0.0
var _shoulder_width: float = 0.0
var _median_x: float = 0.0
var _left_rail_margin: float = 0.0
var _pushback: float = 0.0
var _high_gear_from: int = 4


func configure(tuning: Tuning) -> void:
	_lane_width = tuning.f("lane_width")
	_half_width = tuning.f("car_width") * 0.5
	_length = tuning.f("car_length")
	_gear_speeds = tuning.floats("gear_speeds")
	_lat_per_kmh = tuning.f("lat_per_kmh")
	_lat_tau = tuning.f("lat_follow_tau")
	_accel = tuning.f("accel")
	_engine_brake = tuning.f("engine_brake")
	_brake_decel = tuning.f("brake_decel")
	_neutral_coast = tuning.f("neutral_coast")
	_crown = tuning.f("crown_drift")
	_drift_fade_speed = tuning.f("drift_fade_speed")
	_curve_cap = tuning.f("curve_cap")
	_shoulder_cap = tuning.f("shoulder_speed_cap")
	_rumble_width = tuning.f("rumble_strip_width")
	_shoulder_width = tuning.f("shoulder_width")
	_median_x = tuning.f("median_barrier_x")
	_left_rail_margin = tuning.f("undivided_left_rail_margin")
	_pushback = tuning.f("hit_pushback")


func set_road(lane_count: int, is_divided: bool) -> void:
	lanes = lane_count
	divided = is_divided


## Puts the car in the middle of a lane at the cruise speed of a gear.
func reset(lane: int, gear: int) -> void:
	x = lane_center(lane)
	s = 0.0
	speed = cruise_speed(gear)
	v_lat = 0.0
	drift = 0.0
	on_rumble = false
	on_shoulder = false
	edge_touched = EDGE_NONE
	wall_touched = false
	wall_left = -INF
	wall_right = INF


# --- Geometry ----------------------------------------------------------------

func lane_center(lane: int) -> float:
	return _lane_width * (float(lane) + 0.5)


## The lane the car's centre is in; -1 is the oncoming lane, `lanes` the shoulder.
func lane_of(position_x: float) -> int:
	return int(floorf(position_x / _lane_width))


func road_right() -> float:
	return _lane_width * float(lanes)


func guardrail_x() -> float:
	return road_right() + _rumble_width + _shoulder_width


func left_limit_x() -> float:
	if divided:
		return _median_x
	return -_lane_width - _left_rail_margin


func half_width() -> float:
	return _half_width


func length() -> float:
	return _length


func lane_width() -> float:
	return _lane_width


func cruise_speed(gear: int) -> float:
	if gear <= NEUTRAL or gear > _gear_speeds.size():
		return 0.0
	var cruise: float = _gear_speeds[gear - 1]
	if gear >= _high_gear_from:
		cruise += high_gear_bonus
	return cruise


## Sideways speed a full lock commands at the speed it has now, m/s (GDD 5.3).
func lat_authority() -> float:
	return _lat_per_kmh * speed * lat_speed_mult


## Curve drift (GDD 5.4): k times (speed / 100) squared, outward, capped.
## `k` carries the sign of the push (+ toward the right shoulder).
func curve_push(k: float) -> float:
	var push: float = absf(k) * (speed / 100.0) * (speed / 100.0)
	return signf(k) * minf(push, _curve_cap)


## The share of every sideways drift that reaches the car at its speed: none
## at rest, all of it from drift_fade_speed up. Without this a stopped car
## would slide down the crown into the guardrail with no way to steer back
## (steering authority is lat_per_kmh times the speed, nothing at rest).
func drift_share() -> float:
	if _drift_fade_speed <= 0.0:
		return 1.0
	return clampf(speed / _drift_fade_speed, 0.0, 1.0)


## The sideways push that is always there (GDD 5.4), m/s toward the right:
## the road's crown and `extra` (a steering that pulls), as the car feels
## them at the speed it has.
func steady_drift(extra: float) -> float:
	return (_crown * camber + extra) * drift_share()


# --- The tick ----------------------------------------------------------------

## `steer` is -1 to 1 (WheelSim.steer, after Tremor and Lag). `gear` is 0 for
## neutral. `extra_drift` is every sideways push but the road's crown: curve,
## gust, a pulling fault, sway (m/s, + toward the right shoulder). The crown
## and the extras reach the car in proportion to its speed below
## drift_fade_speed (see drift_share).
func step(dt: float, steer: float, gear: int, braking: bool, extra_drift: float) -> void:
	_step_speed(dt, gear, braking)

	var command: float = steer * _lat_per_kmh * speed * lat_speed_mult
	var tau: float = _lat_tau * lat_tau_mult
	var blend: float = 1.0
	if tau > 0.0:
		blend = 1.0 - exp(-dt / tau)
	v_lat += (command - v_lat) * blend
	drift = (_crown * camber + extra_drift) * drift_share()
	x += (v_lat + drift) * dt
	s += speed * KMH_TO_MS * dt

	_step_edges()


func _step_speed(dt: float, gear: int, braking: bool) -> void:
	var before: float = speed
	var target: float = cruise_speed(gear)
	if on_shoulder:
		target = minf(target, _shoulder_cap)
	if braking:
		speed = maxf(speed - _brake_decel * brake_mult * dt, 0.0)
	elif gear == NEUTRAL:
		speed = maxf(speed - _neutral_coast * dt, 0.0)
	elif speed < target:
		speed = minf(speed + _accel * dt, target)
	elif speed > target:
		speed = maxf(speed - _engine_brake * dt, target)
	# The shoulder's cap belongs to the surface, not to the lever or the foot:
	# above it the car slows at engine_brake at least, down to the cap, also in
	# neutral and under a brake weaker than that. The rumble strip slows nothing.
	if on_shoulder and before > _shoulder_cap:
		speed = minf(speed, maxf(before - _engine_brake * dt, _shoulder_cap))


func _step_edges() -> void:
	edge_touched = EDGE_NONE
	wall_touched = false
	var right_edge: float = x + _half_width
	var left_edge: float = x - _half_width
	var strip_from: float = road_right()
	var strip_to: float = strip_from + _rumble_width
	on_rumble = right_edge > strip_from and left_edge < strip_to
	on_shoulder = right_edge > strip_to
	if right_edge >= guardrail_x():
		edge_touched = EDGE_RIGHT
		x = guardrail_x() - _half_width - _pushback
		v_lat = 0.0
	elif left_edge <= left_limit_x():
		edge_touched = EDGE_LEFT
		x = left_limit_x() + _half_width + _pushback
		v_lat = 0.0
	elif right_edge >= wall_right or left_edge <= wall_left:
		# A corridor's barrier: pushed clear of it, but never into the other
		# one: at most to the middle of what room the two leave him.
		var slack: float = maxf((wall_right - wall_left) * 0.5 - _half_width, 0.0)
		var push: float = minf(_pushback, slack)
		wall_touched = true
		if right_edge >= wall_right:
			edge_touched = EDGE_RIGHT
			x = wall_right - _half_width - push
		else:
			edge_touched = EDGE_LEFT
			x = wall_left + _half_width + push
		v_lat = 0.0
