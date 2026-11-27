class_name CabinSpace
extends RefCounted
## The geometry of the cabin as the pointer and the hand see it
## (GDD 4.2, 4.3, 4.7, 16.2).
##
## Cabin frame: origin at the wheel hub, +X toward the passenger, +Y up,
## +Z toward the driver. Forward is -Z. Units are metres.
##
## The pointer is a direction from the eye into the cabin, kept as a 2D
## position in reference pixels. At the centre of the view one pointer pixel
## is one screen pixel; the map is angular, so it also covers what lies
## beside and below the driver, where a flat screen map cannot reach
## (the passenger's shoulder is 90 degrees off the forward axis). The pointer
## does not move when the eyes glance: it stays on the same spot in the cabin.
## See docs/DECISIONS.md D-017.

## Guards against dividing by zero for rays that run along a plane.
const RAY_EPSILON: float = 0.02

var eye: Vector3 = Vector3.ZERO
var grip_reference: Vector3 = Vector3.ZERO
var waypoint: Vector3 = Vector3.ZERO
var shoulder: Vector3 = Vector3.ZERO
## Where his hand holds a phone to his ear (GDD 10.4).
var ear: Vector3 = Vector3.ZERO

var center: Vector2 = Vector2.ZERO
var px_per_rad: float = 1.0
var pointer_min: Vector2 = Vector2.ZERO
var pointer_max: Vector2 = Vector2.ZERO

var hand_plane_z: float = 0.0
var free_min: Vector2 = Vector2.ZERO
var free_max: Vector2 = Vector2.ZERO

var wheel_radius: float = 0.0
var grip_zone_half_width: float = 0.0

var glance_start: float = 0.0
var glance_gain: float = 0.0
var glance_max_yaw: float = 0.0
var glance_max_pitch: float = 0.0


func configure(data: GameData) -> void:
	var tuning: Tuning = data.tuning
	var points: Dictionary = GameData.as_dict(data.root("anchors").get("points"))
	eye = GameData.as_vec3(points.get("eye"))
	grip_reference = GameData.as_vec3(points.get("G"))
	waypoint = GameData.as_vec3(points.get("W"))
	shoulder = GameData.as_vec3(points.get("shoulder"))
	ear = GameData.as_vec3(points.get("ear"))

	var ref_w: float = tuning.f("reference_width")
	var ref_h: float = tuning.f("reference_height")
	center = Vector2(ref_w, ref_h) * 0.5
	px_per_rad = (ref_h * 0.5) / tan(deg_to_rad(tuning.f("camera_fov")) * 0.5)
	pointer_min = direction_angles_to_pointer(deg_to_rad(tuning.f("pointer_yaw_min")), deg_to_rad(tuning.f("pointer_pitch_max")))
	pointer_max = direction_angles_to_pointer(deg_to_rad(tuning.f("pointer_yaw_max")), deg_to_rad(tuning.f("pointer_pitch_min")))

	hand_plane_z = eye.z - tuning.f("hand_plane_distance")
	free_min = Vector2(tuning.fi("hand_free_bounds_min", 0), tuning.fi("hand_free_bounds_min", 1))
	free_max = Vector2(tuning.fi("hand_free_bounds_max", 0), tuning.fi("hand_free_bounds_max", 1))

	wheel_radius = tuning.f("wheel_radius")
	grip_zone_half_width = tuning.f("grip_zone_half_width")

	glance_start = tuning.f("glance_start")
	glance_gain = tuning.f("glance_gain")
	glance_max_yaw = tuning.f("glance_max_yaw")
	glance_max_pitch = tuning.f("glance_max_pitch")


# --- Reference pixels --------------------------------------------------------

## Scales real pointer motion to reference pixels (GDD 4.3: steering is quoted
## at 1080p and scaled by window height). `view_height` is the height of the
## view the motion was measured in.
func to_reference(motion: Vector2, view_height: float) -> Vector2:
	if view_height <= 0.0:
		return motion
	return motion * (center.y * 2.0 / view_height)


# --- Pointer <-> direction ---------------------------------------------------

## Yaw is positive toward +X (the passenger); pitch is positive upward.
func direction_angles_to_pointer(yaw: float, pitch: float) -> Vector2:
	return Vector2(center.x + yaw * px_per_rad, center.y - pitch * px_per_rad)


func pointer_to_direction(pointer: Vector2) -> Vector3:
	var yaw: float = (pointer.x - center.x) / px_per_rad
	var pitch: float = -(pointer.y - center.y) / px_per_rad
	var flat: float = cos(pitch)
	return Vector3(sin(yaw) * flat, sin(pitch), -cos(yaw) * flat)


func direction_to_pointer(direction: Vector3) -> Vector2:
	var length: float = direction.length()
	if length <= 0.0:
		return center
	var yaw: float = atan2(direction.x, -direction.z)
	var pitch: float = asin(clampf(direction.y / length, -1.0, 1.0))
	return direction_angles_to_pointer(yaw, pitch)


## Where a point of the cabin sits in pointer space.
func point_to_pointer(point: Vector3) -> Vector2:
	return direction_to_pointer(point - eye)


func clamp_pointer(pointer: Vector2) -> Vector2:
	return Vector2(clampf(pointer.x, pointer_min.x, pointer_max.x), clampf(pointer.y, pointer_min.y, pointer_max.y))


# --- Where the hand goes -----------------------------------------------------

## With no anchor in range: the point under the pointer on the plane in front
## of the eye (GDD 4.2), kept inside the box the hand can roam.
func free_target(pointer: Vector2) -> Vector3:
	var direction: Vector3 = pointer_to_direction(pointer)
	var forward: float = maxf(-direction.z, RAY_EPSILON)
	var reach: float = (eye.z - hand_plane_z) / forward
	var x: float = clampf(eye.x + direction.x * reach, free_min.x, free_max.x)
	var y: float = clampf(eye.y + direction.y * reach, free_min.y, free_max.y)
	return Vector3(x, y, hand_plane_z)


## A point of the cabin the pointer points at: on its ray from the eye, as
## far out as the plane the free hand moves in is ahead. Unlike free_target
## it is not kept in the hand's box, and it exists for every direction.
func pointed_at(pointer: Vector2) -> Vector3:
	return eye + pointer_to_direction(pointer) * (eye.z - hand_plane_z)


## The point under the pointer on the plane of the wheel (z = 0).
## Returns Vector3.INF when the pointer does not look at that plane.
func wheel_plane_point(pointer: Vector2) -> Vector3:
	var direction: Vector3 = pointer_to_direction(pointer)
	if -direction.z < RAY_EPSILON:
		return Vector3.INF
	var reach: float = eye.z / -direction.z
	return Vector3(eye.x + direction.x * reach, eye.y + direction.y * reach, 0.0)


## True when the pointer is on the rim: within the grip zone (GDD 4.3).
func pointer_on_rim(pointer: Vector2) -> bool:
	var point: Vector3 = wheel_plane_point(pointer)
	if point == Vector3.INF:
		return false
	var radius: float = Vector2(point.x, point.y).length()
	return absf(radius - wheel_radius) <= grip_zone_half_width


## The rim point nearest to the pointer. Call only when pointer_on_rim().
func rim_point(pointer: Vector2) -> Vector3:
	var point: Vector3 = wheel_plane_point(pointer)
	var flat: Vector2 = Vector2(point.x, point.y)
	if flat.length() <= 0.0:
		return Vector3(wheel_radius, 0.0, 0.0)
	flat = flat.normalized() * wheel_radius
	return Vector3(flat.x, flat.y, 0.0)


## A rim point by its angle (radians, counter-clockwise from +X, seen by the driver).
func rim_point_at(angle: float) -> Vector3:
	return Vector3(cos(angle) * wheel_radius, sin(angle) * wheel_radius, 0.0)


# --- The eyes ----------------------------------------------------------------

## How far a point is off the forward axis, in degrees, seen from the eye.
func off_axis_degrees(point: Vector3) -> float:
	var direction: Vector3 = point - eye
	var length: float = direction.length()
	if length <= 0.0:
		return 0.0
	return rad_to_deg(acos(clampf(-direction.z / length, -1.0, 1.0)))


## The glance (GDD 4.7): when the hand is more than glance_start off the
## forward axis, the camera turns toward it by glance_gain of the excess, up to
## glance_max_yaw of yaw and glance_max_pitch of downward pitch.
## Returns (yaw, pitch) in degrees; yaw is positive toward the passenger and
## pitch is zero or negative (the eyes never glance upward).
func glance_for(hand: Vector3) -> Vector2:
	var direction: Vector3 = hand - eye
	var length: float = direction.length()
	if length <= 0.0:
		return Vector2.ZERO
	direction /= length
	var off_axis: float = acos(clampf(-direction.z, -1.0, 1.0))
	var start: float = deg_to_rad(glance_start)
	if off_axis <= start:
		return Vector2.ZERO
	var turn: float = minf(glance_gain * (off_axis - start), off_axis)
	var forward: Vector3 = Vector3(0.0, 0.0, -1.0)
	var sin_off: float = sin(off_axis)
	var look: Vector3 = direction
	if sin_off > 0.0:
		look = forward * (sin(off_axis - turn) / sin_off) + direction * (sin(turn) / sin_off)
	var yaw: float = rad_to_deg(atan2(look.x, -look.z))
	var pitch: float = rad_to_deg(asin(clampf(look.y, -1.0, 1.0)))
	return Vector2(clampf(yaw, -glance_max_yaw, glance_max_yaw), clampf(pitch, -glance_max_pitch, 0.0))
