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
## The lever is a point that moves only inside the channels: the neutral
## channel along y = 0 and one vertical channel per column, each
## gate_channel_half_width to either side of its centre line. Each tick the
## pointer motion is applied sideways and lengthways separately and stopped at
## the channel walls, so a stroke slides along a wall and turns the corner it
## leans into. Gear 5's channel is walled off unless Fifth gear is fitted.
##
## Press holds the lever. On release a gear engages if the lever is within
## gate_engage_radius of the end of that gear's slot; otherwise it springs
## back to neutral. A grind (noise, Nerves, a short lock) happens on a release
## between gate_grind_min and gate_grind_max along a vertical channel, and
## when the lever is pushed more than gate_wall_push into a wall. Pushing the
## lever home against the end of a gear's own slot is not pushing into a wall
## (DECISIONS D-018).

const NEUTRAL: int = 0
const MAX_GEAR: int = 5
const NO_COLUMN: int = -99
## A tick counts as a push into a wall when the wall takes more than this
## share of the motion asked for.
const PUSH_SHARE: float = 0.75
## Guards float comparisons at the edges of the bands.
const EDGE_EPSILON: float = 0.000001

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

## What the walls have swallowed of the current push, as a vector.
var _push: Vector2 = Vector2.ZERO


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
	_push = Vector2.ZERO
	_place(gear_number)


## A hit forces a gear (GDD 5.6): the lever jumps there, out of the hand.
func force_gear(gear_number: int) -> void:
	held = false
	_push = Vector2.ZERO
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
	_push = Vector2.ZERO


## The hand lets the knob go: engage, or spring back to neutral.
func release() -> void:
	if not held:
		return
	held = false
	_push = Vector2.ZERO
	var column: int = _column_at(lever.x)
	var along: float = absf(lever.y)
	if column != NO_COLUMN and along > _half_width:
		var slot_gear: int = _gear_at_column_end(column, lever.y)
		if slot_gear != NEUTRAL and 1.0 - along <= _engage_radius + EDGE_EPSILON:
			_place(slot_gear)
			engaged = true
			return
		if along >= _grind_min - EDGE_EPSILON and along <= _grind_max + EDGE_EPSILON:
			_grind()
	_place(NEUTRAL)


## Clears the per-tick flags. DriveSim calls this before press, release and step.
func begin_tick() -> void:
	ground = false
	engaged = false


## One tick. `pointer_delta` is pointer motion in reference pixels (y down)
## while the lever is held; `speed_mult` slows the lever (slipping clutch).
func step(dt: float, pointer_delta: Vector2, speed_mult: float = 1.0) -> void:
	if lock_left > 0.0:
		lock_left = maxf(lock_left - dt, 0.0)
		return
	if not held:
		return
	var move: Vector2 = Vector2(pointer_delta.x, -pointer_delta.y) * (speed_mult / _unit_px)
	if move == Vector2.ZERO:
		return
	var before: Vector2 = lever
	# The stronger part goes first, so a stroke turns the corner it leans into.
	if absf(move.x) >= absf(move.y):
		lever.x = _stop_x(lever.x + move.x, lever)
		lever.y = _stop_y(lever.y + move.y, lever)
	else:
		lever.y = _stop_y(lever.y + move.y, lever)
		lever.x = _stop_x(lever.x + move.x, lever)

	if gear != NEUTRAL and not _in_slot(gear):
		gear = NEUTRAL

	# Pushing into a wall. Pushing the lever home at the end of a gear's own
	# slot does not count; a lever that slides along a wall is forgiven by
	# as much as it travels.
	var asked: Vector2 = move
	if _at_slot_stop(before, move.y):
		asked.y = 0.0
	var asked_length: float = asked.length()
	if asked_length <= 0.0:
		return
	var moved: Vector2 = lever - before
	if moved.length() < (1.0 - PUSH_SHARE) * asked_length:
		_push += asked - moved
		if _push.length() > _wall_push + EDGE_EPSILON:
			_push = Vector2.ZERO
			_grind()
	else:
		_push = _push.limit_length(maxf(_push.length() - moved.length(), 0.0))


# --- The channels ------------------------------------------------------------

## Stops a sideways move at the channel walls. `at` is where the lever is.
func _stop_x(wanted: float, at: Vector2) -> float:
	if absf(at.y) <= _half_width + EDGE_EPSILON:
		# In the neutral channel: free from the first column to the last.
		return clampf(wanted, -1.0 - _half_width, _max_column() + _half_width)
	var column: int = _column_at(at.x)
	if column == NO_COLUMN:
		return at.x
	return clampf(wanted, float(column) - _half_width, float(column) + _half_width)


## Stops a lengthways move at the channel walls and the ends of the slots.
func _stop_y(wanted: float, at: Vector2) -> float:
	var column: int = _column_at(at.x)
	if column == NO_COLUMN:
		# Between two columns there is only the neutral channel.
		return clampf(wanted, -_half_width, _half_width)
	return clampf(wanted, _column_min_y(column), 1.0)


## The column whose channel holds this x, or NO_COLUMN.
func _column_at(x: float) -> int:
	var last: int = int(_max_column())
	for column: int in range(-1, last + 1):
		if absf(x - float(column)) <= _half_width + EDGE_EPSILON:
			return column
	return NO_COLUMN


func _max_column() -> float:
	return 1.0 if has_fifth else 0.0


## Gear 5's column only goes forward; there is no gear below it.
func _column_min_y(column: int) -> float:
	return -_half_width if column == 1 else -1.0


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


## True while the lever is near enough to the end of this gear's slot to
## stay in gear.
func _in_slot(gear_number: int) -> bool:
	var home: Vector2 = gear_position(gear_number)
	if _column_at(lever.x) != int(home.x):
		return false
	return signf(lever.y) == signf(home.y) and 1.0 - absf(lever.y) <= _engage_radius + EDGE_EPSILON


## True when the lever sits at the far end of a gear's slot and is pushed
## further into it: the place it belongs, not a wall.
func _at_slot_stop(at: Vector2, dy: float) -> bool:
	if dy == 0.0 or absf(at.y) < 1.0 - EDGE_EPSILON:
		return false
	var column: int = _column_at(at.x)
	if column == NO_COLUMN:
		return false
	return signf(dy) == signf(at.y) and _gear_at_column_end(column, at.y) != NEUTRAL


func _place(gear_number: int) -> void:
	gear = gear_number
	lever = gear_position(gear_number)


func _grind() -> void:
	grinds += 1
	ground = true
	lock_left = _grind_lock
