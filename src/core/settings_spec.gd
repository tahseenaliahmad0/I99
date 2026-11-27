class_name SettingsSpec
extends RefCounted
## The settings of GDD 17.1 as the data defines them (tuning "settings"):
## which exist, what each may be, and what it is when nobody has chosen.
##
##   kind "range"   a percentage from min to max in steps
##   kind "choice"  one of its options
##   kind "toggle"  on or off
##
## The Settings autoload keeps the player's values; DriveSim.apply_settings
## and the views read them. "Every setting can be changed mid-Telling"
## (GDD 17.2): nothing here is read once and kept.

const RANGE: String = "range"
const CHOICE: String = "choice"
const TOGGLE: String = "toggle"

const STEERING: String = "steering_sensitivity"
const GRIP_MODE: String = "grip_mode"
const SHIFTING: String = "shifting"
const GAME_SPEED: String = "game_speed"
const BRAKE_ASSIST: String = "brake_assist"
const STEADY_START: String = "steady_start"
const PHANTOM: String = "phantom"
const SHAKE_VISUALS: String = "shake_visuals"
const NUMERIC_HUD: String = "numeric_hud"
const SUBTITLE_SIZE: String = "subtitle_size"
const SUBTITLE_BACKGROUND: String = "subtitle_background"
const MIRRORED: String = "mirrored_cabin"

const GRIP_TOGGLE: String = "toggle"
const SHIFT_SEQUENTIAL: String = "sequential"

var _spec: Dictionary = {}


func _init(tuning: Tuning) -> void:
	_spec = tuning.d("settings")


## The settings, in the order of GDD 17.1.
func ids() -> PackedStringArray:
	var out: PackedStringArray = []
	for id: Variant in _spec:
		out.append(str(id))
	return out


func has(id: String) -> bool:
	return _spec.has(id)


func kind(id: String) -> String:
	return GameData.as_string(GameData.as_dict(_spec.get(id)).get("kind"))


func default_of(id: String) -> Variant:
	return GameData.as_dict(_spec.get(id)).get("default")


## Every setting at its default.
func defaults() -> Dictionary:
	var out: Dictionary = {}
	for id: String in ids():
		out[id] = default_of(id)
	return out


## What the setting may be: each step of a range, each option of a choice,
## off and on.
func options(id: String) -> Array:
	var record: Dictionary = GameData.as_dict(_spec.get(id))
	match kind(id):
		RANGE:
			var out: Array = []
			var step: float = maxf(GameData.as_float(record.get("step")), 1.0)
			var value: float = GameData.as_float(record.get("min"))
			while value <= GameData.as_float(record.get("max")) + 0.0001:
				out.append(value)
				value += step
			return out
		CHOICE:
			return GameData.as_array(record.get("options")).duplicate()
		TOGGLE:
			return [false, true]
	return []


## Whether `value` is one the setting may have.
func allows(id: String, value: Variant) -> bool:
	var record: Dictionary = GameData.as_dict(_spec.get(id))
	match kind(id):
		RANGE:
			return (value is float or value is int) and GameData.as_float(value) >= GameData.as_float(record.get("min")) - 0.0001 \
					and GameData.as_float(value) <= GameData.as_float(record.get("max")) + 0.0001
		CHOICE:
			return value is String and GameData.as_array(record.get("options")).has(value)
		TOGGLE:
			return value is bool
	return false


## `value` if the setting allows it, else its default (a settings file from
## another version, or written by hand).
func sane(id: String, value: Variant) -> Variant:
	return value if allows(id, value) else default_of(id)


## The option after `value` (`by` 1) or before it (-1): a range stops at its
## ends, a choice and a toggle go round.
func stepped(id: String, value: Variant, by: int) -> Variant:
	var all: Array = options(id)
	if all.is_empty():
		return value
	var at: int = 0
	if kind(id) == RANGE:
		var nearest: float = INF
		for index: int in all.size():
			var off: float = absf(GameData.as_float(all[index]) - GameData.as_float(value))
			if off < nearest:
				nearest = off
				at = index
		return all[clampi(at + by, 0, all.size() - 1)]
	at = maxi(all.find(value), 0)
	return all[posmod(at + by, all.size())]


## A range's percentage as the share the simulation works with.
static func share(percent: Variant) -> float:
	return GameData.as_float(percent, 100.0) / 100.0
