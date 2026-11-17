class_name GearGate
extends RefCounted
## The four-speed H gate (GDD 4.5).
##
##    1     3     5
##    |     |     |
##    +--N--+-----+
##    |     |
##    2     4
##
## Lever coordinates are gate units: neutral is (0, 0), gear 1 (-1, +1),
## 2 (-1, -1), 3 (0, +1), 4 (0, -1), 5 (+1, +1). +y is forward, which is
## pointer motion toward the top of the screen. One unit is gate_unit pixels.
##
## The lever rides rails: the neutral channel (y = 0) and one vertical channel
## per column. It can leave a rail for another only within
## gate_channel_half_width of where they meet. Gear 5's channel is walled off
## unless Fifth gear is fitted.
##
## Press holds the lever; release engages a gear if the lever is within
## gate_engage_radius of it, and otherwise springs it back to neutral. A grind
## (noise, Nerves, a short lock) happens on a release between gate_grind_min
## and gate_grind_max along a vertical channel, and when the lever is pushed
## more than gate_wall_push into a wall. The stop at the far end of a gear's
## own slot is where the lever belongs and is not a wall (DECISIONS D-018).

const NEUTRAL: int = 0
const MAX_GEAR: int = 5
## Rail the lever is on.
enum Rail { NEUTRAL_CHANNEL, COLUMN }

## Engaged gear: 0 is neutral, 1 to 5.
var gear: int = NEUTRAL
## Lever position in gate units.
var lever: Vector2 = Vector2.ZERO
var held: bool = false
## Fifth gear adaptation fitted (GDD 7.6).
var has_fifth: bool = false
## Seconds the lever stays locked after a grind.
var lock_left: float = 0.0
## Total grinds since reset (the tests and the debug HUD read this).
var grinds: int = 0

# --- What happened since begin_tick() ----------------------------------------
var ground: bool = false
var engaged: bool = false

var _unit_px: float = 1.0
var _half_width: float = 0.0
var _engage_radius: float = 0.0
var _grind_min: float = 0.0
var _grind_max: float = 0.0
var _wall_push: float = 0.0
var _grind_lock: float = 0.0

var _rail: Rail = Rail.NEUTRAL_CHANNEL
var _column: int = 0
var _pushed: float = 0.0


func configure(tuning: Tuning) -> void:
	_unit_px = tuning.f("gate_unit")
	_half_width = tuning.f("gate_channel_half_width")
	_engage_radius = tuning.f("gate_engage_radius")
	_grind_min = tuning.f("gate_grind_min")
	_grind_max = tuning.f("gate_grind_max")
	_wall_push = tuning.f("gate_wall_push")
	_grind_lock = tuning.f("gate_grind_lock")


## Where a gear sits in the gate. Neutral is the origin.
static func gear_position(gear_number: int) -> Vector2:
	match gear_number:
		1:
			return Vector2(-1.0, 1.0)
		2:
			return Vector2(-1.0, -1.0)
		3:
			return Vector2(0.0, 1.0)
		4:
			return Vector2(0.0, -1.0)
		5:
			return Vector2(1.0, 1.0)
	return Vector2.ZERO


## Puts the lever in a gear with nothing in progress.
func reset(gear_number: int = NEUTRAL) -> void:
	held = false
	lock_left = 0.0
	grinds = 0
	ground = false
	engaged = false
	_pushed = 0.0
	_place(gear_number)


## A hit forces a gear (GDD 5.6): the lever jumps there, out of the hand.
func force_gear(gear_number: int) -> void:
	held = false
	_pushed = 0.0
	_place(gear_number)


## The assist setting (GDD 4.5, 17.1): sequential shifting, one gear per
## flick, never through neutral. Returns false at either end of the box.
func shift_sequential(step_by: int) -> bool:
	var top: int = MAX_GEAR if has_fifth else MAX_GEAR - 1
	var wanted: int = 1 if gear == NEUTRAL else clampi(gear + step_by, 1, top)
	if wanted == gear:
		return false
	_place(wanted)
	engaged = true
	return true


## The hand takes the knob.
func press() -> void:
	if held:
		return
	held = true
	_pushed = 0.0


## The hand lets the knob go: engage, or spring back to neutral.
func release() -> void:
	if not held:
		return
	held = false
	_pushed = 0.0
	if _rail == Rail.COLUMN:
		var target_gear: int = _gear_at_column_end(_column, lever.y)
		var along: float = absf(lever.y)
		if target_gear != NEUTRAL and lever.distance_to(gear_position(target_gear)) <= _engage_radius:
			_place(target_gear)
			engaged = true
			return
		if along >= _grind_min and along <= _grind_max:
			_grind()
	_place(NEUTRAL)


## Clears the per-tick flags. DriveSim calls this before press, release and step.
func begin_tick() -> void:
	ground = false
	engaged = false


## One tick. `pointer_delta` is pointer motion in reference pixels (y down)
## while the lever is held; `speed_mult` slows the lever (slipping clutch).
##
## The lever follows the stronger component of the motion along its rail. If
## that way is shut it slides the other way instead, as a real lever slides
## along a gate wall. Only a push that moves nothing at all counts as pushing
## into a wall.
func step(dt: float, pointer_delta: Vector2, speed_mult: float = 1.0) -> void:
	if lock_left > 0.0:
		lock_left = maxf(lock_left - dt, 0.0)
		return
	if not held:
		return
	var move: Vector2 = Vector2(pointer_delta.x, -pointer_delta.y) * (speed_mult / _unit_px)
	if move == Vector2.ZERO:
		return
	var sideways_first: bool = absf(move.x) >= absf(move.y)
	var moved: float = 0.0
	if sideways_first:
		moved = _move_sideways(move.x)
		if moved <= 0.0:
			moved = _move_along(move.y)
	else:
		moved = _move_along(move.y)
		if moved <= 0.0:
			moved = _move_sideways(move.x)
	if moved > 0.0:
		_pushed = 0.0
		if gear != NEUTRAL and lever.distance_to(gear_position(gear)) > _engage_radius:
			gear = NEUTRAL
		return
	if not sideways_first and _at_slot_stop(move.y):
		return
	_pushed += maxf(absf(move.x), absf(move.y))
	if _pushed > _wall_push:
		_pushed = 0.0
		_grind()


# --- Movement on the rails ---------------------------------------------------

const NO_COLUMN: int = -99


## Moves along the neutral channel. Returns the distance moved; 0 means a wall.
func _move_sideways(dx: float) -> float:
	if dx == 0.0:
		return 0.0
	if _rail == Rail.COLUMN and absf(lever.y) > _half_width:
		return 0.0
	var wanted: float = clampf(lever.x + dx, -1.0, _max_x())
	var moved: float = absf(wanted - lever.x)
	if moved <= 0.0:
		return 0.0
	_rail = Rail.NEUTRAL_CHANNEL
	lever = Vector2(wanted, 0.0)
	return moved


## Moves along a column. Returns the distance moved; 0 means a wall or a stop.
func _move_along(dy: float) -> float:
	if dy == 0.0:
		return 0.0
	var column: int = _column if _rail == Rail.COLUMN else _column_near(lever.x)
	if column == NO_COLUMN:
		return 0.0
	var wanted: float = clampf(lever.y + dy, _column_min_y(column), 1.0)
	var moved: float = absf(wanted - lever.y)
	if moved <= 0.0:
		return 0.0
	_column = column
	lever = Vector2(float(column), wanted)
	_rail = Rail.NEUTRAL_CHANNEL if wanted == 0.0 else Rail.COLUMN
	return moved


## True when the lever sits at the far end of a gear's slot and is pushed
## further into it: the place it belongs, not a wall.
func _at_slot_stop(dy: float) -> bool:
	if _rail != Rail.COLUMN or absf(lever.y) < 1.0:
		return false
	return signf(dy) == signf(lever.y) and _gear_at_column_end(_column, lever.y) != NEUTRAL


func _column_near(x: float) -> int:
	var last: int = 1 if has_fifth else 0
	for column: int in range(-1, last + 1):
		if absf(x - float(column)) <= _half_width:
			return column
	return NO_COLUMN


func _max_x() -> float:
	return 1.0 if has_fifth else 0.0


## Gear 5's column only goes forward; there is no gear below it.
func _column_min_y(column: int) -> float:
	return 0.0 if column == 1 else -1.0


func _gear_at_column_end(column: int, y: float) -> int:
	if y > 0.0:
		match column:
			-1:
				return 1
			0:
				return 3
			1:
				return 5 if has_fifth else NEUTRAL
	elif y < 0.0:
		match column:
			-1:
				return 2
			0:
				return 4
	return NEUTRAL


func _place(gear_number: int) -> void:
	gear = gear_number
	lever = gear_position(gear_number)
	if gear_number == NEUTRAL:
		_rail = Rail.NEUTRAL_CHANNEL
		_column = 0
	else:
		_rail = Rail.COLUMN
		_column = int(lever.x)


func _grind() -> void:
	grinds += 1
	ground = true
	lock_left = _grind_lock
