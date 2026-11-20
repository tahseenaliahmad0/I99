class_name SkyView
extends Node3D
## The sky (GDD 13.5): a flat colour for the leg's weather and hour, and the
## haze that hides the distance: the dark beyond the headlights at night,
## dust by day. At Dawn (GDD 10.4) the glow of the oil fields lies along the
## horizon and the sun comes up. The flare of the sun on his view is the post
## effects'. Reads the snapshot; changes nothing.

var _environment: Environment
var _factory: PlaceholderFactory
var _day: Color = Color.WHITE
var _night: Color = Color.BLACK
var _rain: Color = Color.GRAY
var _dust: Color = Color.TAN
var _fog_near_share: float = 0.5
var _dawn_from: float = 1.0
## Dawn outside a Telling: the share of day in the sky at its start and end.
var _boss_dawn: Vector2 = Vector2.ZERO
var _sun: Node3D
var _glow: Node3D
var _eye: Vector3 = Vector3.ZERO
var _distance: float = 0.0
var _side_deg: float = 0.0
var _glow_deg: float = 0.0


func setup(data: GameData, factory: PlaceholderFactory) -> void:
	_factory = factory
	var tuning: Tuning = data.tuning
	_day = Color.html(tuning.s("sky_color_day"))
	_night = Color.html(tuning.s("sky_color_night"))
	_rain = Color.html(tuning.s("sky_color_rain"))
	_dust = Color.html(tuning.s("sky_color_dust"))
	_fog_near_share = tuning.f("fog_near_share")
	_dawn_from = tuning.f("sky_dawn_from")
	_boss_dawn = Vector2(tuning.fi("sky_boss_dawn", 0), tuning.fi("sky_boss_dawn", 1))
	_distance = tuning.f("sky_distance")
	_side_deg = tuning.f("sky_side_deg")
	_glow_deg = tuning.f("sky_glow_deg")
	_eye = GameData.as_vec3(GameData.as_dict(data.root("anchors").get("points")).get("eye"))
	_glow = factory.make("sky_glow")
	_glow.visible = false
	add_child(_glow)
	_sun = factory.make("sky_sun")
	_sun.visible = false
	add_child(_sun)
	_environment = Environment.new()
	_environment.background_mode = Environment.BG_COLOR
	_environment.background_color = _day
	var world: WorldEnvironment = WorldEnvironment.new()
	world.environment = _environment
	world.name = "WorldEnvironment"
	add_child(world)


func apply(snapshot: Dictionary) -> void:
	var sight: float = snapshot["visibility"]
	var sky: Color = _day
	if snapshot["telling"]:
		# The sky follows the Clock (GDD 6.4): night until the last part of
		# it, then lighter until the deadline, when it is day.
		var share: float = snapshot["night_share"]
		var dawn: float = clampf((share - _dawn_from) / maxf(1.0 - _dawn_from, 0.001), 0.0, 1.0)
		sky = _night.lerp(_day, dawn)
		if snapshot["raining"]:
			sky = sky.lerp(_rain, 0.5 * dawn)
		elif is_finite(sight) and not snapshot["night"]:
			sky = sky.lerp(_dust, 0.5)
	elif GameData.as_int(snapshot["dawn_phase"]) > 0:
		# Dawn by itself: the sky lightens along its road.
		var car_s: float = snapshot["car_s"]
		var length: float = snapshot["leg_length"]
		sky = _night.lerp(_day, lerpf(_boss_dawn.x, _boss_dawn.y, clampf(car_s / maxf(length, 1.0), 0.0, 1.0)))
	elif snapshot["night"]:
		sky = _night
	elif snapshot["raining"]:
		sky = _rain
	elif is_finite(sight):
		sky = _dust
	_environment.background_color = sky
	if is_finite(sight):
		_factory.set_world_fog(sky, sight * _fog_near_share, sight)
	else:
		_factory.set_world_fog(sky, PlaceholderFactory.NO_FOG, PlaceholderFactory.NO_FOG * 2.0)

	# Dawn: the glow of burning gas along the horizon, and the sun, which
	# climbs as its Glare comes on.
	var glow: float = snapshot["glow"]
	_glow.visible = glow > 0.0
	if _glow.visible:
		var glow_side: float = snapshot["glow_side"]
		_place(_glow, glow_side * _side_deg, _glow_deg)
	# The sun stands where the simulation says the light is: the place the
	# post effects wash the glass from, and his lowered visor covers.
	var sun_at: Variant = snapshot.get("glare_position")
	_sun.visible = sun_at is Vector2
	if sun_at is Vector2:
		var at: Vector2 = sun_at
		_place(_sun, at.x, at.y)


## Puts something in the sky: `yaw` degrees to the right of dead ahead and
## `elevation` degrees above the horizon, facing his eye.
func _place(node: Node3D, yaw: float, elevation: float) -> void:
	var turn: float = deg_to_rad(yaw)
	var lift: float = deg_to_rad(elevation)
	node.position = _eye + Vector3(sin(turn) * cos(lift), sin(lift), -cos(turn) * cos(lift)) * _distance
	node.rotation = Vector3(0.0, -turn, 0.0)
