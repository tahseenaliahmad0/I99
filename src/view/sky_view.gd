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


## The share of day in the sky, 0 (night) to 1 (day). In a Telling the sky
## follows the Clock (GDD 6.4): night until `dawn_from` of the night has
## gone, then lighter until the deadline. On Dawn's road (`dawn_phase` above
## 0, `along` it from 0 to 1) it is never darker than Dawn driven by itself:
## the real sun does not rise into a night sky (GDD 10.4), however far ahead
## of the Clock he is.
static func day_share(telling: bool, night_share: float, dawn_from: float, dawn_phase: int, along: float, boss_dawn: Vector2) -> float:
	var by_road: float = lerpf(boss_dawn.x, boss_dawn.y, clampf(along, 0.0, 1.0)) if dawn_phase > 0 else 0.0
	if not telling:
		return by_road
	var by_clock: float = clampf((night_share - dawn_from) / maxf(1.0 - dawn_from, 0.001), 0.0, 1.0)
	return maxf(by_clock, by_road)


func apply(snapshot: Dictionary) -> void:
	# What he is shown: through the dust's tell the thick dust closes in.
	var sight: float = snapshot["sight_shown"]
	var sky: Color = _day
	var dawn_phase: int = GameData.as_int(snapshot["dawn_phase"])
	var car_s: float = snapshot["car_s"]
	var length: float = snapshot["leg_length"]
	var along: float = clampf(car_s / maxf(length, 1.0), 0.0, 1.0)
	if snapshot["telling"]:
		# The sky follows the Clock (GDD 6.4): night until the last part of
		# it, then lighter until the deadline, when it is day; and on Dawn's
		# road no darker than that road makes it.
		var share: float = snapshot["night_share"]
		var dawn: float = day_share(true, share, _dawn_from, dawn_phase, along, _boss_dawn)
		sky = _night.lerp(_day, dawn)
		if snapshot["raining"]:
			sky = sky.lerp(_rain, 0.5 * dawn)
		elif is_finite(sight) and not snapshot["night"]:
			sky = sky.lerp(_dust, 0.5)
	elif dawn_phase > 0:
		# Dawn by itself: the sky lightens along its road.
		sky = _night.lerp(_day, day_share(false, 0.0, _dawn_from, dawn_phase, along, _boss_dawn))
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
