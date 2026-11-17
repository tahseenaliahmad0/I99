extends TestSuite
## M1: the pointer, the hand and the eyes (GDD 4.2, 4.7, 16.2).

const DT: float = DriveSim.DT
const TRAVEL_TOLERANCE_S: float = 0.02
const MAX_TRAVEL_S: float = 3.0

var _space: CabinSpace
var _hand: HandSim
var _input: DriveInput


func before_each() -> void:
	_space = CabinSpace.new()
	_space.configure(data)
	_hand = HandSim.new()
	_hand.configure(data, _space)
	_input = DriveInput.new()


## T-HAND-01: travel time from G to every anchor matches GDD 16.2 within 0.02 s.
func test_hand_01() -> void:
	var worst: float = 0.0
	for anchor: Dictionary in data.records("anchors"):
		var id: String = GameData.as_string(anchor.get("id"))
		var expected: float = GameData.as_float(anchor.get("time_s"))
		var index: int = _hand.anchor_index(StringName(id))
		# Two anchors may share a place (the radio and its tape deck): measure one at a time.
		var twins: Array[int] = _twins_of(index)
		for twin: int in twins:
			_hand.set_anchor_active(twin, false)
		var out: float = _travel_time(_space.grip_reference, index)
		check_near(out, expected, TRAVEL_TOLERANCE_S, "G to %s" % id)
		worst = maxf(worst, absf(out - expected))
		# Reaching back costs the same: time off the wheel is reach + perform + reach back (GDD 4.6).
		_hand.place_at(_hand.anchor_position(index))
		var back: float = _time_to_grip_at(_space.grip_reference)
		check_near(back, expected, TRAVEL_TOLERANCE_S, "%s back to the wheel at G" % id)
		for twin: int in twins:
			_hand.set_anchor_active(twin, true)
	check_eq(data.records("anchors").size(), _hand.anchor_count(), "every anchor of anchors.json is known to the hand")
	note("%d anchors, worst error %.4f s" % [_hand.anchor_count(), worst])


## T-HAND-02: hand speed left of the hub is 70% of normal.
func test_hand_02() -> void:
	var normal: float = tuning.f("hand_speed")
	var left_mult: float = tuning.f("hand_left_side_mult")

	# Right of the hub: G to the wiper stalk.
	var right_speed: float = _cruise_speed(_space.grip_reference, _hand.anchor_index(&"wiper_stalk"))
	check_near(right_speed, normal, 0.0001, "speed right of the hub is hand_speed")

	# Left of the hub: W to the indicator stalk.
	var left_speed: float = _cruise_speed(_space.waypoint, _hand.anchor_index(&"indicator_stalk"))
	check_near(left_speed / right_speed, left_mult, 0.0001, "speed left of the hub is hand_left_side_mult of normal")

	# A cross-reach goes through W: every tick spent left of the hub is slow,
	# every tick right of it is at full speed, and the path touches W.
	_hand.place_at(_space.grip_reference)
	_aim_at(_hand.anchor_index(&"window_crank"))
	var touched_w: bool = false
	var slow_ticks: int = 0
	var fast_ticks: int = 0
	var wrong_ticks: int = 0
	var previous: Vector3 = _hand.pos
	for _tick: int in int(MAX_TRAVEL_S / DT):
		_hand.step(DT, _input, 0.0, 1.0)
		var moved: float = _hand.pos.distance_to(previous)
		if _point_segment_distance(_space.waypoint, previous, _hand.pos) <= normal * DT:
			touched_w = true
		elif previous.x >= 0.0 and _hand.pos.x >= 0.0 and moved > 0.0:
			fast_ticks += 1
			if absf(moved / DT - normal) > 0.0001:
				wrong_ticks += 1
		elif previous.x < 0.0 and _hand.pos.x < 0.0 and moved > 0.0 and _hand.at_index == HandSim.NO_ANCHOR:
			slow_ticks += 1
			if absf(moved / DT - normal * left_mult) > 0.0001:
				wrong_ticks += 1
		previous = _hand.pos
		if _hand.at_index != HandSim.NO_ANCHOR:
			break
	check(touched_w, "a reach to the left side passes through waypoint W")
	check(fast_ticks > 0 and slow_ticks > 0, "the cross-reach has a fast stretch and a slow stretch")
	check_eq(wrong_ticks, 0, "no tick of the cross-reach moves at any other speed")

	# The way back is slow on the left and fast on the right as well.
	var back_left: float = _cruise_speed(_hand.anchor_position(_hand.anchor_index(&"indicator_stalk")), _hand.anchor_index(&"horn"))
	check_near(back_left, normal * left_mult, 0.0001, "coming back, the stretch left of the hub is slow too")


## T-HAND-03: pointer snap, free target, input buffer, fly-and-grip, glance.
func test_hand_03() -> void:
	_check_pointer_map()
	_check_mouse_moves_the_pointer()
	_check_snap()
	_check_free_target()
	_check_buffer()
	_check_fly_and_grip()
	_check_rim_is_never_shadowed()
	_check_toggle_grip()
	_check_cannot_reach()
	_check_glance()
	_check_eyes_down_ritual()


## The pointer map, pinned with numbers worked out here from GDD 16.2 (not
## taken from CabinSpace): forward is the centre of the view; one pixel at the
## centre is 1 / k radians with k = (height / 2) / tan(fov / 2); +x is toward
## the passenger and -y is up.
func _check_pointer_map() -> void:
	var width: float = tuning.f("reference_width")
	var height: float = tuning.f("reference_height")
	var k: float = (height * 0.5) / tan(deg_to_rad(tuning.f("camera_fov")) * 0.5)
	var centre: Vector2 = Vector2(width, height) * 0.5
	check_near(tuning.f("camera_fov"), 75.0, 0.000001, "GDD 16.2: the vertical field of view is 75 degrees")
	check(_space.pointer_to_direction(centre).is_equal_approx(Vector3(0.0, 0.0, -1.0)), "the centre of the view is straight ahead (-Z)")
	var right: Vector3 = _space.pointer_to_direction(centre + Vector2(k * PI / 6.0, 0.0))
	check(right.is_equal_approx(Vector3(0.5, 0.0, -sqrt(3.0) * 0.5)), "30 degrees of pixels to the right points 30 degrees toward the passenger (+X)")
	var up: Vector3 = _space.pointer_to_direction(centre + Vector2(0.0, -k * PI / 6.0))
	check(up.is_equal_approx(Vector3(0.0, 0.5, -sqrt(3.0) * 0.5)), "30 degrees of pixels upward points 30 degrees up (+Y)")
	var left: Vector3 = _space.pointer_to_direction(centre + Vector2(-k * PI / 2.0, 0.0))
	check(left.is_equal_approx(Vector3(-1.0, 0.0, 0.0)), "90 degrees of pixels to the left points at the driver's window (-X)")

	# And back: a point of the cabin to its pointer position.
	var eye: Vector3 = GameData.as_vec3(GameData.as_dict(data.root("anchors").get("points")).get("eye"))
	check(_space.point_to_pointer(eye + Vector3(0.0, 0.0, -2.0)).is_equal_approx(centre), "a point straight ahead of the eye is at the centre")
	var beside: Vector2 = _space.point_to_pointer(eye + Vector3(1.0, 0.0, 0.0))
	check(beside.is_equal_approx(centre + Vector2(k * PI / 2.0, 0.0)), "a point beside the eye, 90 degrees to the right, is k x pi/2 pixels right of centre")
	var below: Vector2 = _space.point_to_pointer(eye + Vector3(0.0, -1.0, -1.0))
	check(below.is_equal_approx(centre + Vector2(0.0, k * PI / 4.0)), "a point 45 degrees below is k x pi/4 pixels below centre")

	# The range.
	var limit_right: float = centre.x + k * deg_to_rad(tuning.f("pointer_yaw_max"))
	var limit_left: float = centre.x + k * deg_to_rad(tuning.f("pointer_yaw_min"))
	var limit_down: float = centre.y - k * deg_to_rad(tuning.f("pointer_pitch_min"))
	var limit_up: float = centre.y - k * deg_to_rad(tuning.f("pointer_pitch_max"))
	var far: Vector2 = _space.clamp_pointer(Vector2(100000.0, 100000.0))
	check(far.is_equal_approx(Vector2(limit_right, limit_down)), "the pointer stops at pointer_yaw_max and pointer_pitch_min")
	far = _space.clamp_pointer(Vector2(-100000.0, -100000.0))
	check(far.is_equal_approx(Vector2(limit_left, limit_up)), "and at pointer_yaw_min and pointer_pitch_max")
	for anchor: Dictionary in data.records("anchors"):
		var at: Vector2 = _space.point_to_pointer(GameData.as_vec3(anchor.get("pos")))
		var inside: bool = at.x > limit_left and at.x < limit_right and at.y > limit_up and at.y < limit_down
		check(inside, "the anchor %s lies inside the pointer's range" % GameData.as_string(anchor.get("id")))


## The mouse is captured: the pointer is kept from relative motion (GDD 4.1).
func _check_mouse_moves_the_pointer() -> void:
	_hand.place_at(_space.grip_reference)
	_input.clear()
	var start: Vector2 = _hand.pointer
	_input.pointer_delta = Vector2(12.0, -7.0)
	_hand.step(DT, _input, 0.0, 1.0)
	check(_hand.pointer.is_equal_approx(start + Vector2(12.0, -7.0)), "mouse motion moves the pointer by the same number of pixels")
	_input.pointer_delta = Vector2.ZERO
	_hand.step(DT, _input, 0.0, 1.0)
	check(_hand.pointer.is_equal_approx(start + Vector2(12.0, -7.0)), "and with no motion it stays where it is")

	# Motion to the right moves the hand toward the passenger; motion up, up.
	# (On the open windscreen, where no anchor is near.)
	_hand.place_at(_space.free_target(_space.center + Vector2(-150.0, -40.0)))
	_input.pointer_delta = Vector2.ZERO
	_hand.step(DT, _input, 0.0, 1.0)
	check_eq(_hand.snap_index, HandSim.NO_ANCHOR, "the open windscreen has no anchor under the pointer")
	var before: Vector3 = _hand.target
	_input.pointer_delta = Vector2(60.0, 0.0)
	_hand.step(DT, _input, 0.0, 1.0)
	check(_hand.target.x > before.x + 0.02, "moving the mouse right moves the hand's target toward the passenger")
	check(absf(_hand.target.y - before.y) < 0.005, "and hardly up or down")
	before = _hand.target
	_input.pointer_delta = Vector2(0.0, -60.0)
	_hand.step(DT, _input, 0.0, 1.0)
	check(_hand.target.y > before.y + 0.02, "moving the mouse up moves the hand's target up")
	check(absf(_hand.target.x - before.x) < 0.005, "and hardly sideways")

	# Reaching an anchor with the mouse alone: from G to the gear lever.
	_hand.place_at(_space.grip_reference)
	_input.clear()
	var lever: int = _hand.anchor_index(&"gear_lever")
	var travel: Vector2 = _hand.anchor_pointer(lever) - _hand.pointer
	var moves: int = 12
	for _move: int in moves:
		_input.pointer_delta = travel / float(moves)
		_hand.step(DT, _input, 0.0, 1.0)
	_input.pointer_delta = Vector2.ZERO
	check_eq(_hand.snap_index, lever, "moving the mouse onto the gear lever snaps the pointer to it")
	for _tick: int in int(MAX_TRAVEL_S / DT):
		_hand.step(DT, _input, 0.0, 1.0)
	check_eq(_hand.at_index, lever, "and the hand follows and arrives")

	# The pointer cannot be pushed out of its range.
	_input.pointer_delta = Vector2(900.0, 0.0)
	for _tick: int in 20:
		_hand.step(DT, _input, 0.0, 1.0)
	check_near(_hand.pointer.x, _space.pointer_max.x, 0.000001, "pushed far to the right, the pointer stops at the edge of its range")
	_input.pointer_delta = Vector2(0.0, -900.0)
	for _tick: int in 20:
		_hand.step(DT, _input, 0.0, 1.0)
	check_near(_hand.pointer.y, _space.pointer_min.y, 0.000001, "and at the top")
	_input.clear()


## Anchors near the wheel must not take any part of the rim away: a press
## anywhere on the rim grips (GDD 4.1, 4.2).
func _check_rim_is_never_shadowed() -> void:
	var sim: DriveSim = DriveSim.new(fresh_data())
	var input: DriveInput = DriveInput.new()
	var failed: PackedStringArray = []
	for degrees: int in range(0, 360, 10):
		var rim: Vector3 = sim.space.rim_point_at(deg_to_rad(float(degrees)))
		sim.hand.place_at(Vector3(0.3, 0.25, 0.3))
		input.clear()
		input.pointer_is_absolute = true
		input.pointer = sim.space.point_to_pointer(rim)
		input.lmb = true
		for _tick: int in int(1.5 / DT):
			_step_in_lane(sim, input)
		if not sim.hand.gripping or not sim.hand.pos.is_equal_approx(rim):
			failed.append(str(degrees))
		input.lmb = false
		_step_in_lane(sim, input)
	check(failed.is_empty(), "a press on the rim grips at every angle of the wheel; failed at: %s" % ", ".join(failed))

	# Grip at G, steer right, let go, press again without moving: he takes the
	# wheel again. (The hidden pointer was left on the rim near his face.)
	sim = DriveSim.new(fresh_data())
	input.clear()
	input.pointer_is_absolute = true
	input.pointer = sim.space.point_to_pointer(sim.space.grip_reference)
	input.lmb = true
	for _tick: int in 60:
		_step_in_lane(sim, input)
	input.pointer_is_absolute = false
	for _tick: int in 10:
		input.pointer_delta = Vector2(10.0, 0.0)
		_step_in_lane(sim, input)
	input.pointer_delta = Vector2.ZERO
	for _tick: int in 60:
		_step_in_lane(sim, input)
	check_near(sim.wheel.angle, 100.0 * tuning.f("steer_deg_per_px"), 0.1, "the wheel is turned 35 degrees to the right")
	input.lmb = false
	for _tick: int in 30:
		_step_in_lane(sim, input)
	sim.drain_events()
	input.lmb = true
	for _tick: int in 60:
		_step_in_lane(sim, input)
	check(sim.hand.gripping, "letting go after a right turn and pressing again takes the wheel again")
	var rituals: int = 0
	for event: Dictionary in sim.drain_events():
		if event.get("type") == "ritual_completed":
			rituals += 1
	check_eq(rituals, 0, "and does nothing else (it is not a slap)")

	# The anchors keep the ground around their own place.
	input.clear()
	_step_in_lane(sim, input)
	_step_in_lane(sim, input)
	for id: StringName in [&"wiper_stalk", &"indicator_stalk", &"horn"]:
		var index: int = sim.hand.anchor_index(id)
		input.pointer_is_absolute = true
		input.pointer = sim.hand.anchor_pointer(index)
		_step_in_lane(sim, input)
		check_eq(sim.hand.snap_index, index, "pointing at the %s itself still snaps to it" % id)


## Grip mode "toggle" (GDD 17.1): click to grip, click to release.
func _check_toggle_grip() -> void:
	var sim: DriveSim = DriveSim.new(fresh_data())
	var input: DriveInput = DriveInput.new()
	sim.hand.grip_toggle = true
	sim.hand.place_at(Vector3(0.3, 0.2, 0.2))
	input.pointer_is_absolute = true
	input.pointer = sim.space.point_to_pointer(sim.space.grip_reference)
	var in_step: bool = true
	var both_events: bool = false
	# One click on the rim.
	for tick: int in 60:
		input.lmb = tick < 4
		_step_in_lane(sim, input)
		in_step = in_step and sim.hand.gripping == sim.wheel.gripped
		both_events = both_events or (sim.hand.took_grip and sim.hand.let_go)
	check(sim.hand.gripping, "toggle: one click on the rim makes the hand fly there and grip")
	check(not input.lmb, "toggle: the button is up, and the grip holds")
	input.pointer_is_absolute = false
	input.pointer_delta = Vector2(10.0, 0.0)
	for _tick: int in 10:
		_step_in_lane(sim, input)
	input.pointer_delta = Vector2.ZERO
	check_near(sim.wheel.command, 100.0 * tuning.f("steer_deg_per_px"), 0.000001, "toggle: he steers with the button up")

	# The next press lets go, on that tick, and holding it does not re-grip.
	input.lmb = true
	_step_in_lane(sim, input)
	check(sim.hand.let_go and not sim.hand.gripping, "toggle: the next press lets go on that tick")
	in_step = in_step and sim.hand.gripping == sim.wheel.gripped
	both_events = both_events or (sim.hand.took_grip and sim.hand.let_go)
	for _tick: int in 40:
		_step_in_lane(sim, input)
		in_step = in_step and sim.hand.gripping == sim.wheel.gripped
		both_events = both_events or (sim.hand.took_grip and sim.hand.let_go)
	check(not sim.hand.gripping, "toggle: holding that press does not take the wheel again")
	check(not sim.wheel.gripped, "toggle: and the wheel is free")
	input.lmb = false
	for _tick: int in 10:
		_step_in_lane(sim, input)
	check(not sim.hand.gripping, "toggle: releasing it changes nothing")
	check(in_step, "toggle: the hand and the wheel agree on the grip every tick")
	check(not both_events, "toggle: no tick both takes and lets go")

	# In hold mode a click is not enough.
	sim = DriveSim.new(fresh_data())
	sim.hand.place_at(Vector3(0.3, 0.2, 0.2))
	input.clear()
	input.pointer_is_absolute = true
	input.pointer = sim.space.point_to_pointer(sim.space.grip_reference)
	for tick: int in 60:
		input.lmb = tick < 4
		_step_in_lane(sim, input)
	check(not sim.hand.gripping, "hold mode: a click on the rim does not grip; the button must be held")

	# Changing the mode mid-drive (GDD 17.2).
	sim = DriveSim.new(fresh_data())
	input.clear()
	input.pointer_is_absolute = true
	input.pointer = sim.space.point_to_pointer(sim.space.grip_reference)
	input.lmb = true
	for _tick: int in 60:
		_step_in_lane(sim, input)
	sim.hand.grip_toggle = true
	input.lmb = false
	_step_in_lane(sim, input)
	check(sim.hand.gripping, "switching to toggle while holding: letting the button up keeps the grip")
	sim.hand.grip_toggle = false
	_step_in_lane(sim, input)
	check(not sim.hand.gripping, "switching back to hold with the button up: he lets go")


## A Snap: he can steer and cannot reach (GDD 6.1).
func _check_cannot_reach() -> void:
	_hand.place_at(_space.grip_reference)
	_hand.can_reach = false
	_aim_at(_hand.anchor_index(&"glovebox"))
	_hand.step(DT, _input, 0.0, 1.0)
	check_eq(_hand.snap_index, HandSim.NO_ANCHOR, "while he cannot reach, the pointer snaps to no anchor")

	# He can still take the wheel...
	_input.clear()
	_input.pointer_is_absolute = true
	_input.pointer = _space.point_to_pointer(_space.grip_reference)
	_input.lmb = true
	for _tick: int in 60:
		_hand.step(DT, _input, 0.0, 1.0)
	check(_hand.gripping, "but he can still take the wheel")

	# ...and steer it.
	_input.pointer_is_absolute = false
	_input.pointer_delta = Vector2(5.0, 0.0)
	_hand.step(DT, _input, 0.0, 1.0)
	check_near(_hand.steer_px, 5.0, 0.000001, "and steer")
	_hand.can_reach = true
	_input.clear()
	_hand.step(DT, _input, 0.0, 1.0)

	# The cramp: he can neither let go nor take hold.
	_hand.start_gripping(0.0)
	_hand.frozen = true
	_input.clear()
	_hand.step(DT, _input, 0.0, 1.0)
	check(_hand.gripping, "frozen, he cannot let go")
	_hand.frozen = false
	_hand.step(DT, _input, 0.0, 1.0)
	check(not _hand.gripping, "unfrozen with the button up, he lets go")
	_hand.frozen = true
	_input.pointer_is_absolute = true
	_input.pointer = _space.point_to_pointer(_space.grip_reference)
	_input.lmb = true
	for _tick: int in 60:
		_hand.step(DT, _input, 0.0, 1.0)
	check(not _hand.gripping, "frozen, he cannot take hold")
	_hand.frozen = false
	_hand.step(DT, _input, 0.0, 1.0)
	check(_hand.gripping, "unfrozen, he does")
	_input.clear()
	_hand.step(DT, _input, 0.0, 1.0)


## An eyes-down ritual forces the pitch while it is performed (GDD 4.7).
func _check_eyes_down_ritual() -> void:
	var cabin: GameData = fresh_data()
	var ritual: Dictionary = cabin.record("rituals", "glovebox_toggle")
	ritual["gesture"] = "HOLD"
	ritual["hold_s"] = 1.5
	ritual["eyes_down"] = true
	if not check(DataValidator.validate(cabin).is_empty(), "a HOLD ritual with eyes_down validates"):
		return
	var sim: DriveSim = DriveSim.new(cabin)
	var input: DriveInput = DriveInput.new()
	input.pointer_is_absolute = true
	input.pointer = sim.hand.anchor_pointer(sim.hand.anchor_index(&"glovebox"))
	for _tick: int in int(1.2 / DT):
		sim.step(input)
	var glance_pitch: float = sim.hand.cam_pitch
	check(glance_pitch > -tuning.f("eyes_down_pitch") + 5.0, "at the glovebox the glance alone does not reach eyes_down_pitch")
	input.lmb = true
	for _tick: int in int(1.3 / DT):
		sim.step(input)
	check(sim.hand.eyes_down, "while an eyes-down ritual is performed the eyes are down")
	check_near(sim.hand.cam_pitch, -tuning.f("eyes_down_pitch"), 0.05, "the pitch is forced to eyes_down_pitch")
	for _tick: int in int(0.4 / DT):
		sim.step(input)
	input.lmb = false
	for _tick: int in int(1.5 / DT):
		sim.step(input)
	check(not sim.hand.eyes_down, "when the ritual is over the eyes come back up")
	check_near(sim.hand.cam_pitch, glance_pitch, 0.05, "to the glance")


func _check_snap() -> void:
	var radius: float = tuning.f("anchor_snap_radius")
	# An anchor with no neighbour within three radii, so the edge of its zone is clean.
	var lonely: int = HandSim.NO_ANCHOR
	for index: int in _hand.anchor_count():
		var nearest: float = INF
		for other: int in _hand.anchor_count():
			if other != index:
				nearest = minf(nearest, _hand.anchor_pointer(index).distance_to(_hand.anchor_pointer(other)))
		if nearest > radius * 3.0:
			lonely = index
			break
	if not check(lonely != HandSim.NO_ANCHOR, "some anchor stands alone in pointer space"):
		return
	var at: Vector2 = _hand.anchor_pointer(lonely)
	_point(at + Vector2(radius - 1.0, 0.0))
	check_eq(_hand.snap_index, lonely, "the pointer snaps to an anchor just inside anchor_snap_radius")
	check(_hand.target.is_equal_approx(_hand.anchor_position(lonely)), "the hand's target is the snapped anchor")
	_point(at + Vector2(radius + 1.0, 0.0))
	check_eq(_hand.snap_index, HandSim.NO_ANCHOR, "the pointer does not snap just outside anchor_snap_radius")
	_point(at + Vector2(0.0, -(radius - 1.0)))
	check_eq(_hand.snap_index, lonely, "the snap zone is a circle: it reaches as far upward")

	# Between two anchors whose zones overlap, the nearer one wins.
	var radio: int = _hand.anchor_index(&"radio")
	var hazard: int = _hand.anchor_index(&"hazard_button")
	_hand.set_anchor_active(_hand.anchor_index(&"tape"), false)
	var a: Vector2 = _hand.anchor_pointer(radio)
	var b: Vector2 = _hand.anchor_pointer(hazard)
	if check(a.distance_to(b) < radius * 2.0, "the radio and the hazard button have overlapping snap zones"):
		_point(a.lerp(b, 0.4))
		check_eq(_hand.snap_index, radio, "between two anchors the pointer snaps to the nearer (radio)")
		_point(a.lerp(b, 0.6))
		check_eq(_hand.snap_index, hazard, "between two anchors the pointer snaps to the nearer (hazard button)")

	# An inactive anchor attracts nothing.
	_hand.set_anchor_active(lonely, false)
	_point(at)
	check_eq(_hand.snap_index, HandSim.NO_ANCHOR, "an inactive anchor does not snap")
	_hand.set_anchor_active(lonely, true)


func _check_free_target() -> void:
	# Straight ahead through the windscreen: far from every anchor.
	var pointer: Vector2 = _space.center + Vector2(-150.0, -40.0)
	_hand.place_at(_space.grip_reference)
	_point(pointer)
	if not check_eq(_hand.snap_index, HandSim.NO_ANCHOR, "the windscreen has no anchor under the pointer"):
		return
	for _tick: int in int(MAX_TRAVEL_S / DT):
		_hand.step(DT, _input, 0.0, 1.0)
	var plane_z: float = _space.eye.z - tuning.f("hand_plane_distance")
	check_near(_hand.pos.z, plane_z, 0.000001, "with no anchor in range the hand rests on the plane in front of the eye")
	var ray: Vector3 = _space.pointer_to_direction(pointer)
	var to_hand: Vector3 = (_hand.pos - _space.eye).normalized()
	check_near(ray.dot(to_hand), 1.0, 0.000001, "and at the point under the pointer on that plane")
	check_eq(_hand.at_index, HandSim.NO_ANCHOR, "a free point is not an anchor")


func _check_buffer() -> void:
	var buffer: float = tuning.f("input_buffer")
	var anchor: int = _hand.anchor_index(&"dash_2")
	var travel_ticks: int = roundi(_travel_time(_space.grip_reference, anchor) / DT)
	if not check(float(travel_ticks) * DT > buffer + 0.05, "the reach used for the buffer test is longer than input_buffer"):
		return
	var click_ticks: int = 4

	# Steps are numbered from 0; the hand arrives during step `arrival`.
	var arrival: int = travel_ticks - 1

	# Pressed (and released again) exactly input_buffer before arrival: applied on arrival.
	var buffer_ticks: int = roundi(buffer / DT)
	var inside: int = arrival - buffer_ticks
	var applied_step: int = _reach_with_click(anchor, inside, click_ticks, arrival + 10)
	check_eq(applied_step, arrival, "a press made exactly input_buffer before arrival is applied on arrival")
	applied_step = _reach_with_click(anchor, arrival - 3, click_ticks, arrival + 10)
	check_eq(applied_step, arrival, "and so is one made just before arrival")

	# Pressed one tick earlier than that: forgotten.
	var outside: int = arrival - buffer_ticks - 1
	applied_step = _reach_with_click(anchor, outside, click_ticks, arrival + 10)
	check_eq(applied_step, -1, "a press made one tick earlier than input_buffer before arrival is not applied")
	applied_step = _reach_with_click(anchor, outside - 20, click_ticks, arrival + 10)
	check_eq(applied_step, -1, "nor one made long before")

	# Pressed when the hand is already there: applied at once.
	applied_step = _reach_with_click(anchor, arrival + 5, click_ticks, arrival + 10)
	check_eq(applied_step, arrival + 5, "a press made with the hand at the anchor is applied that tick")

	# A buffered press aimed at one anchor is not handed to another.
	_hand.place_at(_space.grip_reference)
	_aim_at(anchor)
	var other: int = _hand.anchor_index(&"dash_1")
	var applied: bool = false
	for tick: int in arrival + 40:
		_input.lmb = tick >= inside and tick < inside + click_ticks
		if tick == inside + click_ticks:
			_input.pointer = _hand.anchor_pointer(other)
		_hand.step(DT, _input, 0.0, 1.0)
		applied = applied or _hand.press_applied
	check(not applied, "a buffered press is dropped when the pointer moves to another anchor")
	check_eq(_hand.at_index, other, "the hand went to the other anchor instead")
	_input.clear()


func _check_fly_and_grip() -> void:
	var far: Vector3 = _hand.anchor_position(_hand.anchor_index(&"glovebox"))
	var rim_pointer: Vector2 = _space.point_to_pointer(_space.grip_reference)
	check(_space.pointer_on_rim(rim_pointer), "the grip reference G lies in the grip zone")

	# Button held with the pointer on the rim: the hand flies there and grips.
	_hand.place_at(far)
	_input.pointer_is_absolute = true
	_input.pointer = rim_pointer
	_input.lmb = true
	var grips: int = 0
	var grip_tick: int = -1
	for tick: int in int(MAX_TRAVEL_S / DT):
		_hand.step(DT, _input, 0.0, 1.0)
		if _hand.took_grip:
			grips += 1
			grip_tick = tick
	check(_hand.gripping, "holding the button with the pointer on the rim ends in a grip")
	check_eq(grips, 1, "the grip is taken exactly once")
	var expected: float = far.distance_to(_space.grip_reference) / tuning.f("hand_speed")
	check_near(float(grip_tick + 1) * DT, expected, TRAVEL_TOLERANCE_S, "the hand flew to the rim at hand speed")
	check_near(Vector2(_hand.pos.x, _hand.pos.y).length(), tuning.f("wheel_radius"), 0.000001, "the gripped hand is on the rim")
	check_near(_hand.pos.z, 0.0, 0.000001, "in the plane of the wheel")
	check(_hand.pinned, "while gripping, the pointer is pinned to the hand")

	# The gripped hand rides the wheel.
	var before: Vector3 = _hand.pos
	_hand.step(DT, _input, 90.0, 1.0)
	check(_hand.pos.is_equal_approx(Vector3(before.y, -before.x, 0.0)), "the gripped hand turns with the wheel (90 degrees clockwise)")
	check(_hand.pointer.is_equal_approx(_space.point_to_pointer(_hand.pos)), "and the pointer stays on it")

	# Releasing the button lets go; the hand stays where it was.
	_input.lmb = false
	_input.pointer_is_absolute = false
	_hand.step(DT, _input, 90.0, 1.0)
	check(_hand.let_go and not _hand.gripping, "releasing the button lets go")
	check(not _hand.pinned, "and frees the pointer")

	# Without the button the hand does not take the wheel.
	_hand.place_at(far)
	_input.pointer_is_absolute = true
	_input.pointer = rim_pointer
	_input.lmb = false
	for _tick: int in int(MAX_TRAVEL_S / DT):
		_hand.step(DT, _input, 0.0, 1.0)
	check(not _hand.gripping, "with the button up the hand never grips")
	_input.clear()


func _check_glance() -> void:
	var start: float = tuning.f("glance_start")
	var gain: float = tuning.f("glance_gain")
	var max_yaw: float = tuning.f("glance_max_yaw")
	var max_pitch: float = tuning.f("glance_max_pitch")

	check(_space.glance_for(_at_angles(start - 1.0, 0.0)).is_equal_approx(Vector2.ZERO),
			"a hand within glance_start of the forward axis does not turn the eyes")

	var side: float = start + 20.0
	var glance: Vector2 = _space.glance_for(_at_angles(side, 0.0))
	check_near(glance.x, gain * (side - start), 0.0001, "past glance_start the eyes turn by glance_gain of the excess")
	check_near(glance.y, 0.0, 0.0001, "a sideways reach does not pitch the eyes")
	check_near(_space.glance_for(_at_angles(-side, 0.0)).x, -gain * (side - start), 0.0001, "and the same to the left")

	glance = _space.glance_for(_at_angles(120.0, 0.0))
	check_near(glance.x, max_yaw, 0.0001, "the yaw is capped at glance_max_yaw")

	var down: float = start + 20.0
	glance = _space.glance_for(_at_angles(0.0, -down))
	check_near(glance.y, -gain * (down - start), 0.0001, "a low reach pitches the eyes down by glance_gain of the excess")
	glance = _space.glance_for(_at_angles(0.0, -85.0))
	check_near(glance.y, -max_pitch, 0.0001, "the downward pitch is capped at glance_max_pitch")
	glance = _space.glance_for(_at_angles(0.0, start + 30.0))
	check_near(glance.y, 0.0, 0.0001, "the eyes never glance upward")

	check_near(_space.off_axis_degrees(_at_angles(side, 0.0)), side, 0.0001, "off-axis angle is measured from the forward axis at the eye")

	# Off both axes at once, as every real control is. The rule is about the
	# angle off the forward axis, not about yaw and pitch separately.
	for angles: Vector2 in [Vector2(20.0, -20.0), Vector2(40.0, -40.0), Vector2(-30.0, -15.0)]:
		var yaw: float = deg_to_rad(angles.x)
		var pitch: float = deg_to_rad(angles.y)
		var off_axis: float = rad_to_deg(acos(cos(yaw) * cos(pitch)))
		var turn: float = gain * (off_axis - start)
		glance = _space.glance_for(_at_angles(angles.x, angles.y))
		var turned: float = rad_to_deg(acos(cos(deg_to_rad(glance.x)) * cos(deg_to_rad(glance.y))))
		check_near(turned, turn, 0.001, "hand at yaw %s pitch %s: the eyes turn by glance_gain of the angle beyond glance_start" % [str(angles.x), str(angles.y)])
		# ...toward the hand: along the arc from straight ahead to the hand.
		var to_hand: Vector3 = Vector3(sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
		var look: Vector3 = Vector3(sin(deg_to_rad(glance.x)) * cos(deg_to_rad(glance.y)), sin(deg_to_rad(glance.y)), -cos(deg_to_rad(glance.x)) * cos(deg_to_rad(glance.y)))
		var normal: Vector3 = Vector3(0.0, 0.0, -1.0).cross(to_hand).normalized()
		check_near(look.dot(normal), 0.0, 0.00001, "and they turn toward the hand, not off to one side")
	check_near(_space.glance_for(_at_angles(20.0, -20.0)).x, 1.229, 0.002, "worked example: hand at yaw 20, pitch -20 gives yaw 1.229")
	check_near(_space.glance_for(_at_angles(20.0, -20.0)).y, -1.308, 0.002, "and pitch -1.308")

	# The camera follows the glance smoothed over glance_smoothing (first-order).
	var tau: float = tuning.f("glance_smoothing") * 0.001
	var point: Vector3 = _at_angles(side, 0.0)
	var goal: float = gain * (side - start)
	_hand.place_at(_space.grip_reference)
	_hand.cam_yaw = 0.0
	_hand.cam_pitch = 0.0
	_hand.pos = point
	_hand.target = point
	_hand.pin()
	var ticks: int = roundi(tau / DT)
	for _tick: int in ticks:
		_hand.step(DT, _input, 0.0, 1.0)
	if check(_hand.pos.is_equal_approx(point), "the hand stays where the glance test put it"):
		check_near(_hand.cam_yaw / goal, 1.0 - exp(-float(ticks) * DT / tau), 0.001, "after one time constant the camera has covered 63% of the turn")
		for _tick: int in int(1.5 / DT):
			_hand.step(DT, _input, 0.0, 1.0)
		check_near(_hand.cam_yaw, goal, 0.001, "and it settles on the glance")

	# Eyes-down rituals force the pitch.
	_hand.eyes_down = true
	for _tick: int in int(1.5 / DT):
		_hand.step(DT, _input, 0.0, 1.0)
	check_near(_hand.cam_pitch, -tuning.f("eyes_down_pitch"), 0.01, "an eyes-down ritual forces the pitch to eyes_down_pitch")
	_hand.eyes_down = false
	_hand.unpin()


# --- Helpers ------------------------------------------------------------------

## One tick of a whole DriveSim with the car held in the middle of its lane,
## so a long scenario about the hand is not interrupted by the guardrail.
func _step_in_lane(sim: DriveSim, input: DriveInput) -> void:
	sim.car.x = sim.car.lane_center(1)
	sim.step(input)


## A point half a metre from the eye, `yaw` degrees toward the passenger and
## `pitch` degrees upward of the forward axis.
func _at_angles(yaw: float, pitch: float) -> Vector3:
	var y: float = deg_to_rad(yaw)
	var p: float = deg_to_rad(pitch)
	return _space.eye + Vector3(sin(y) * cos(p), sin(p), -cos(y) * cos(p)) * 0.5


func _aim_at(anchor: int) -> void:
	_input.clear()
	_input.pointer_is_absolute = true
	_input.pointer = _hand.anchor_pointer(anchor)


## Moves the pointer somewhere and lets one tick pass.
func _point(pointer: Vector2) -> void:
	_input.clear()
	_input.pointer_is_absolute = true
	_input.pointer = pointer
	_hand.step(DT, _input, 0.0, 1.0)


func _travel_time(from: Vector3, anchor: int) -> float:
	_hand.place_at(from)
	_aim_at(anchor)
	for tick: int in int(MAX_TRAVEL_S / DT):
		_hand.step(DT, _input, 0.0, 1.0)
		if _hand.at_index == anchor:
			return float(tick + 1) * DT
	return INF


## Time for the hand to fly to the rim at a point and grip (button held).
func _time_to_grip_at(rim_point: Vector3) -> float:
	_input.clear()
	_input.pointer_is_absolute = true
	_input.pointer = _space.point_to_pointer(rim_point)
	_input.lmb = true
	for tick: int in int(MAX_TRAVEL_S / DT):
		_hand.step(DT, _input, 0.0, 1.0)
		if _hand.gripping:
			_input.clear()
			return float(tick + 1) * DT
	_input.clear()
	return INF


## Other anchors at exactly the same place as this one.
func _twins_of(index: int) -> Array[int]:
	var out: Array[int] = []
	for other: int in _hand.anchor_count():
		if other != index and _hand.anchor_position(other).is_equal_approx(_hand.anchor_position(index)):
			out.append(other)
	return out


## Distance covered per second on the first full tick of a trip.
func _cruise_speed(from: Vector3, anchor: int) -> float:
	_hand.place_at(from)
	_aim_at(anchor)
	_hand.step(DT, _input, 0.0, 1.0)
	var start: Vector3 = _hand.pos
	_hand.step(DT, _input, 0.0, 1.0)
	return _hand.pos.distance_to(start) / DT


## Reaches for an anchor from G and clicks once at step `press_tick`.
## Returns the step (from 0) during which the press was applied, or -1.
func _reach_with_click(anchor: int, press_tick: int, click_ticks: int, total_ticks: int) -> int:
	_hand.place_at(_space.grip_reference)
	_aim_at(anchor)
	var applied_tick: int = -1
	for tick: int in total_ticks:
		_input.lmb = tick >= press_tick and tick < press_tick + click_ticks
		_hand.step(DT, _input, 0.0, 1.0)
		if _hand.press_applied and applied_tick == -1:
			applied_tick = tick
	_input.clear()
	return applied_tick


func _point_segment_distance(point: Vector3, a: Vector3, b: Vector3) -> float:
	var ab: Vector3 = b - a
	var length_squared: float = ab.length_squared()
	if length_squared <= 0.0:
		return point.distance_to(a)
	var t: float = clampf((point - a).dot(ab) / length_squared, 0.0, 1.0)
	return point.distance_to(a + ab * t)
