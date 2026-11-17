class_name SkyView
extends Node3D
## The sky (GDD 13.5): a flat colour for the leg's weather and hour, and the
## haze that hides the distance: the dark beyond the headlights at night,
## dust by day. The sun, flares and the Clock's gradient arrive with the
## Telling and the post effects. Reads the snapshot; changes nothing.

var _environment: Environment
var _factory: PlaceholderFactory
var _day: Color = Color.WHITE
var _night: Color = Color.BLACK
var _rain: Color = Color.GRAY
var _dust: Color = Color.TAN
var _fog_near_share: float = 0.5


func setup(data: GameData, factory: PlaceholderFactory) -> void:
	_factory = factory
	var tuning: Tuning = data.tuning
	_day = Color.html(tuning.s("sky_color_day"))
	_night = Color.html(tuning.s("sky_color_night"))
	_rain = Color.html(tuning.s("sky_color_rain"))
	_dust = Color.html(tuning.s("sky_color_dust"))
	_fog_near_share = tuning.f("fog_near_share")
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
	if snapshot["night"]:
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
