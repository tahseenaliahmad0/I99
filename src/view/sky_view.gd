class_name SkyView
extends Node3D
## The sky (GDD 13.5): a flat colour that follows the Clock, from night to
## day. The sun, flares and the headlight cone arrive with the legs and the
## post effects. Reads the snapshot; changes nothing.

var _environment: Environment
var _day: Color = Color.WHITE
var _night: Color = Color.BLACK


func setup(data: GameData) -> void:
	_day = Color.html(data.tuning.s("sky_color_day"))
	_night = Color.html(data.tuning.s("sky_color_night"))
	_environment = Environment.new()
	_environment.background_mode = Environment.BG_COLOR
	_environment.background_color = _day
	var world: WorldEnvironment = WorldEnvironment.new()
	world.environment = _environment
	world.name = "WorldEnvironment"
	add_child(world)


## `daylight` is 0 at night and 1 in full day.
func apply(daylight: float) -> void:
	_environment.background_color = _night.lerp(_day, clampf(daylight, 0.0, 1.0))
