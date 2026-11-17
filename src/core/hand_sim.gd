class_name HandSim
extends RefCounted
## The hand (GDD 4.2, 4.3, 4.7).
##
## The pointer names a place; the hand is a physical thing that takes time to
## get there. The pointer snaps to the nearest active anchor within
## anchor_snap_radius. The hand travels at hand_speed with no easing, at
## hand_left_side_mult of that speed left of the hub, and crosses sides only
## through waypoint W. A press made up to input_buffer before the hand arrives
## at an anchor is applied on arrival. Holding the button with the pointer on
## the rim makes the hand fly there and grip; the gripped hand rides the wheel.
##
## HandSim knows nothing about rituals. It reports, each tick, where the hand
## is and whether a press was applied at an anchor; DriveSim decides what that
## press means.

const NO_ANCHOR: int = -1
## A hand never needs more than: here -> W -> target.
const MAX_SEGMENTS: int = 3

# --- State (read by DriveSim, the views and the tests) -----------------------
var pos: Vector3 = Vector3.ZERO
var target: Vector3 = Vector3.ZERO
var pointer: Vector2 = Vector2.ZERO
## Anchor the pointer is snapped to, or NO_ANCHOR.
var snap_index: int = NO_ANCHOR
## Anchor the hand rests at, or NO_ANCHOR.
var at_index: int = NO_ANCHOR
var gripping: bool = false
## The pointer is held still: the hand is on the wheel or busy with a gesture.
var pinned: bool = false
## The camera's glance, degrees (yaw toward the passenger, pitch downward < 0).
var cam_yaw: float = 0.0
var cam_pitch: float = 0.0
var time: float = 0.0

# --- What happened this tick -------------------------------------------------
var arrived: bool = false
var press_applied: bool = false
var took_grip: bool = false
var let_go: bool = false
## Sideways pointer motion that steers this tick (0 unless gripping all tick).
var steer_px: float = 0.0

# --- Inputs set by DriveSim --------------------------------------------------
## Grip mode of GDD 17.1: false = hold, true = click to grip, click to release.
## It may change mid-Telling (GDD 17.2); a click latched in the old mode is dropped.
var grip_toggle: bool = false:
	set(value):
		if value != grip_toggle:
			grip_toggle = value
			_grip_latched = gripping and value
## Eyes-down rituals force the pitch (GDD 4.7).
var eyes_down: bool = false
## False while he can steer and cannot reach for anything (a Snap, GDD 6.1).
var can_reach: bool = true
## True while the hand carries something (a DRAG_TO in progress): one thing
## fits in the hand, so it cannot take the wheel (GDD 4.2).
var carrying: bool = false
## True while the hand can neither let go nor take hold (the weather cramp).
var frozen: bool = false
## The Phantom's wrong-hand flinch (GDD 7.9). DriveSim says each tick whether
## a cross-reach begun now would flinch; the hand then leaves flinch_delay
## late. `flinch_left` is what is left of that wait and `ghost_anchor` the
## control the ghost of his left hand goes for (NO_ANCHOR when there is none).
var flinches: bool = false
var flinch_left: float = 0.0
var ghost_anchor: int = NO_ANCHOR

var _space: CabinSpace
var _speed: float = 0.0
var _left_mult: float = 1.0
var _snap_radius: float = 0.0
var _buffer: float = 0.0
var _arrive_epsilon: float = 0.0
var _flinch_delay: float = 0.0
## The left-side control the hand is on its way to (so that one reach
## flinches once).
var _cross_reach: int = NO_ANCHOR
var _glance_tau: float = 0.0
var _eyes_down_pitch: float = 0.0

var _anchor_ids: Array[StringName] = []
var _anchor_pos: PackedVector3Array = PackedVector3Array()
var _anchor_pointer: PackedVector2Array = PackedVector2Array()
var _anchor_active: PackedByteArray = PackedByteArray()

var _was_down: bool = false
var _wants_grip: bool = false
var _grip_latched: bool = false
## Angle of the grip point on the rim, in the wheel's own frame (radians).
var _grip_angle: float = 0.0
var _press_pending: bool = false
var _press_time: float = 0.0
var _press_anchor: int = NO_ANCHOR
## Pointer distance to the anchor found by the last _nearest_anchor().
var _snap_distance: float = 0.0


func configure(data: GameData, space: CabinSpace) -> void:
	_space = space
	var tuning: Tuning = data.tuning
	_speed = tuning.f("hand_speed")
	_left_mult = tuning.f("hand_left_side_mult")
	_snap_radius = tuning.f("anchor_snap_radius")
	_buffer = tuning.f("input_buffer")
	_arrive_epsilon = tuning.f("hand_arrive_epsilon")
	_flinch_delay = tuning.f("phantom_flinch_delay")
	_glance_tau = tuning.f("glance_smoothing") * 0.001
	_eyes_down_pitch = tuning.f("eyes_down_pitch")

	_anchor_ids.clear()
	_anchor_pos.clear()
	_anchor_pointer.clear()
	_anchor_active.clear()
	for anchor: Dictionary in data.records("anchors"):
		var position: Vector3 = GameData.as_vec3(anchor.get("pos"))
		_anchor_ids.append(StringName(GameData.as_string(anchor.get("id"))))
		_anchor_pos.append(position)
		_anchor_pointer.append(space.point_to_pointer(position))
		_anchor_active.append(1)
	reset_to_grip_reference()


## Puts the hand at G, off the wheel, with the pointer on it.
func reset_to_grip_reference() -> void:
	place_at(_space.grip_reference)


## Test and set-up helper: puts the hand at a point, at rest, pointer on it.
func place_at(point: Vector3) -> void:
	pos = point
	target = point
	pointer = _space.clamp_pointer(_space.point_to_pointer(point))
	snap_index = NO_ANCHOR
	at_index = NO_ANCHOR
	gripping = false
	pinned = false
	_wants_grip = false
	_grip_latched = false
	_press_pending = false
	_was_down = false
	flinch_left = 0.0
	ghost_anchor = NO_ANCHOR
	_cross_reach = NO_ANCHOR
	var glance: Vector2 = _space.glance_for(pos)
	cam_yaw = glance.x
	cam_pitch = glance.y


## Set-up helper: the hand starts on the wheel at G, gripping.
func start_gripping(wheel_angle_deg: float) -> void:
	place_at(_space.grip_reference)
	gripping = true
	pinned = true
	_was_down = not grip_toggle
	_grip_latched = grip_toggle
	_grip_angle = atan2(pos.y, pos.x) + deg_to_rad(wheel_angle_deg)


# --- Anchors -----------------------------------------------------------------

func anchor_count() -> int:
	return _anchor_ids.size()


func anchor_index(id: StringName) -> int:
	return _anchor_ids.find(id)


func anchor_id(index: int) -> StringName:
	if index < 0 or index >= _anchor_ids.size():
		return &""
	return _anchor_ids[index]


func anchor_position(index: int) -> Vector3:
	if not _is_anchor(index):
		return Vector3.ZERO
	return _anchor_pos[index]


## Where an anchor sits in pointer space.
func anchor_pointer(index: int) -> Vector2:
	if not _is_anchor(index):
		return Vector2.ZERO
	return _anchor_pointer[index]


func set_anchor_active(index: int, active: bool) -> void:
	if not _is_anchor(index):
		return
	_anchor_active[index] = 1 if active else 0


func is_anchor_active(index: int) -> bool:
	if not _is_anchor(index):
		return false
	return _anchor_active[index] != 0


## NO_ANCHOR (-1) is not an index: in an array it would be the last element.
func _is_anchor(index: int) -> bool:
	if index >= 0 and index < _anchor_ids.size():
		return true
	push_error("HandSim: %d is not an anchor index (0 to %d)" % [index, _anchor_ids.size() - 1])
	return false


func snap_id() -> StringName:
	return anchor_id(snap_index)


func at_id() -> StringName:
	return anchor_id(at_index)


## Moves an anchor (an adaptation that relocates a control).
func set_anchor_position(index: int, position: Vector3) -> void:
	_anchor_pos[index] = position
	_anchor_pointer[index] = _space.point_to_pointer(position)


# --- Pinning (used by DriveSim while a gesture holds the hand) ---------------

func pin() -> void:
	pinned = true


func unpin() -> void:
	if not gripping:
		pinned = false


# --- The tick ----------------------------------------------------------------

## `wheel_angle_deg` is the wheel's angle (clockwise positive); the gripped
## hand rides it. `speed_mult` scales hand speed (Pound, GDD 4.2).
## Only the pointer follows the player (the cut after a Wreck): the hand
## stays where it is, but where he points is known when the cut ends.
func track_pointer(input: DriveInput) -> void:
	if input.pointer_is_absolute:
		pointer = _space.clamp_pointer(input.pointer)
	else:
		pointer = _space.clamp_pointer(pointer + input.pointer_delta)


func step(dt: float, input: DriveInput, wheel_angle_deg: float, speed_mult: float) -> void:
	time += dt
	arrived = false
	press_applied = false
	took_grip = false
	let_go = false
	steer_px = 0.0

	var down: bool = input.lmb
	var pressed: bool = down and not _was_down
	_was_down = down

	if gripping:
		var release: bool = (pressed if _grip_latched else not down) and not frozen
		if release:
			_let_go()
			pressed = false
		else:
			pos = _space.rim_point_at(_grip_angle - deg_to_rad(wheel_angle_deg))
			target = pos
			pointer = _space.clamp_pointer(_space.point_to_pointer(pos))
			steer_px = input.pointer_delta.x
			_update_glance(dt)
			return

	if not pinned:
		if input.pointer_is_absolute:
			pointer = _space.clamp_pointer(input.pointer)
		else:
			pointer = _space.clamp_pointer(pointer + input.pointer_delta)
		_choose_target(down, pressed)

	if pressed:
		_press_pending = snap_index != NO_ANCHOR
		_press_time = time
		_press_anchor = snap_index
	if _press_pending and snap_index != _press_anchor:
		_press_pending = false

	_step_flinch(dt)
	if flinch_left <= 0.0:
		_travel(dt, speed_mult)

	var resting_at: int = NO_ANCHOR
	if snap_index != NO_ANCHOR and pos.is_equal_approx(_anchor_pos[snap_index]):
		resting_at = snap_index
	if resting_at != at_index:
		at_index = resting_at
		arrived = at_index != NO_ANCHOR

	if _press_pending:
		if at_index != NO_ANCHOR and at_index == _press_anchor and time - _press_time <= _buffer + dt * 0.5:
			press_applied = true
			_press_pending = false
		elif time - _press_time > _buffer:
			_press_pending = false

	if _wants_grip and not frozen and pos.is_equal_approx(target) and _wants_wheel(down):
		gripping = true
		pinned = true
		took_grip = true
		_wants_grip = false
		_grip_angle = atan2(pos.y, pos.x) + deg_to_rad(wheel_angle_deg)

	_update_glance(dt)


## A cross-reach begins when the hand, on his side of the hub, is sent to a
## control on the far side. If the Phantom flinches then, the hand waits
## flinch_delay before it leaves, and the ghost goes for the control.
func _step_flinch(dt: float) -> void:
	var across: bool = snap_index != NO_ANCHOR and _anchor_pos[snap_index].x < 0.0
	if not across:
		_cross_reach = NO_ANCHOR
		flinch_left = 0.0
		ghost_anchor = NO_ANCHOR
		return
	if snap_index != _cross_reach:
		_cross_reach = snap_index
		flinch_left = 0.0
		ghost_anchor = NO_ANCHOR
		if flinches and pos.x >= 0.0:
			flinch_left = _flinch_delay
			ghost_anchor = snap_index
	elif flinch_left > 0.0:
		flinch_left -= dt
		if flinch_left < dt * 0.5:
			flinch_left = 0.0
			ghost_anchor = NO_ANCHOR


func _let_go() -> void:
	gripping = false
	pinned = false
	let_go = true
	_grip_latched = false
	_wants_grip = false
	target = pos
	pointer = _space.clamp_pointer(_space.point_to_pointer(pos))


func _choose_target(down: bool, pressed: bool) -> void:
	snap_index = _nearest_anchor()
	var on_rim: bool = _space.pointer_on_rim(pointer) and not carrying
	if snap_index != NO_ANCHOR and on_rim:
		# The rim is a place to point at too. Where the pointer is nearer to
		# the rim's centre line than to the anchor, the wheel wins: otherwise
		# an anchor near the wheel (his own face, the stalks) would take a
		# sector of the rim away, and a press there would not grip.
		var rim_distance: float = pointer.distance_to(_space.point_to_pointer(_space.rim_point(pointer)))
		if rim_distance < _snap_distance:
			snap_index = NO_ANCHOR
	if snap_index != NO_ANCHOR:
		target = _anchor_pos[snap_index]
		_wants_grip = false
		_grip_latched = false
		return
	if on_rim and grip_toggle and pressed:
		_grip_latched = true
	if not on_rim:
		_grip_latched = false
	if on_rim and _wants_wheel(down):
		target = _space.rim_point(pointer)
		_wants_grip = true
	else:
		target = _space.free_target(pointer)
		_wants_grip = false


## Whether the player is asking for the wheel: the button held (hold mode), or
## the latch set by a click on the rim (toggle mode, GDD 17.1).
func _wants_wheel(down: bool) -> bool:
	return _grip_latched if grip_toggle else down


func _nearest_anchor() -> int:
	if not can_reach:
		return NO_ANCHOR
	var best: int = NO_ANCHOR
	var best_distance: float = _snap_radius
	for index: int in _anchor_pointer.size():
		if _anchor_active[index] == 0:
			continue
		var distance: float = pointer.distance_to(_anchor_pointer[index])
		if distance <= best_distance and (best == NO_ANCHOR or distance < best_distance):
			best = index
			best_distance = distance
	_snap_distance = best_distance
	return best


## Straight lines at constant speed; sides are changed only through W, and any
## stretch left of the hub runs at hand_left_side_mult (GDD 4.2).
func _travel(dt: float, speed_mult: float) -> void:
	var remaining: float = dt
	for _segment: int in MAX_SEGMENTS:
		if remaining <= 0.0:
			return
		var goal: Vector3 = target
		var crossing: bool = (pos.x < 0.0) != (target.x < 0.0)
		if crossing and pos.distance_to(_space.waypoint) > _arrive_epsilon:
			goal = _space.waypoint
		var speed: float = _speed * speed_mult
		if pos.x < 0.0 or goal.x < 0.0:
			speed *= _left_mult
		if speed <= 0.0:
			return
		var distance: float = pos.distance_to(goal)
		var reach: float = speed * remaining
		if distance > reach:
			pos += (goal - pos) * (reach / distance)
			return
		pos = goal
		remaining -= distance / speed
		if goal == target:
			return


func _update_glance(dt: float) -> void:
	var want: Vector2 = _space.glance_for(pos)
	if eyes_down:
		want.y = -_eyes_down_pitch
	var blend: float = 1.0
	if _glance_tau > 0.0:
		blend = 1.0 - exp(-dt / _glance_tau)
	cam_yaw += (want.x - cam_yaw) * blend
	cam_pitch += (want.y - cam_pitch) * blend
