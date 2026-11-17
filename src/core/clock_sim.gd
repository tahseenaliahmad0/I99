class_name ClockSim
extends RefCounted
## The Clock (GDD 6.4): the night from clock_start to clock_deadline.
##
## One real second of driving is clock_scale game seconds. Stops are untimed
## in real time: each charges a fixed number of game minutes instead, and so
## do a fine, a bribe and a repair.

const MINUTES_PER_DAY: float = 1440.0
## Thousands of ticks of driving add up to a whole minute less a rounding
## error: this much (in game minutes, far less than one tick) is forgiven.
const ROUNDING: float = 1.0e-6

## Game minutes since clock_start.
var minutes: float = 0.0

var _start: float = 0.0
var _night: float = 0.0
var _scale: float = 0.0


func configure(tuning: Tuning) -> void:
	_start = minutes_of(tuning.s("clock_start"))
	var deadline: float = minutes_of(tuning.s("clock_deadline"))
	# The deadline is the next time the clock shows it: 06:00 after 22:00.
	_night = fposmod(deadline - _start, MINUTES_PER_DAY)
	_scale = tuning.f("clock_scale")
	minutes = 0.0


## "HH:MM" as minutes after midnight.
static func minutes_of(text: String) -> float:
	var parts: PackedStringArray = text.split(":")
	if parts.size() != 2:
		return 0.0
	return float(parts[0].to_int()) * 60.0 + float(parts[1].to_int())


func reset() -> void:
	minutes = 0.0


## One tick of driving.
func step(dt: float) -> void:
	minutes += dt * _scale / 60.0


## A stop, a fine, a bribe, a repair: game minutes that pass at once.
func add_minutes(amount: float) -> void:
	minutes += maxf(amount, 0.0)


## How long the night is, in game minutes (clock_start to clock_deadline).
func night_minutes() -> float:
	return _night


## Game minutes left until the deadline; negative once it has passed.
func minutes_left() -> float:
	return _night - minutes


## True after the deadline: parked now, he is Late (GDD 11.4). At the
## deadline to the minute he is still on time.
func late() -> bool:
	return minutes > _night + ROUNDING


## Share of the night gone, 0 at clock_start and 1 at the deadline (it goes on past 1).
func night_share() -> float:
	if _night <= 0.0:
		return 0.0
	return minutes / _night


## Minutes after midnight that the clock shows now.
func time_of_day() -> float:
	return fposmod(_start + minutes, MINUTES_PER_DAY)


## What the dashboard clock shows: "HH:MM".
func text() -> String:
	var whole: int = int(floorf(fposmod(_start + minutes + ROUNDING, MINUTES_PER_DAY)))
	return "%02d:%02d" % [whole / 60, whole % 60]
