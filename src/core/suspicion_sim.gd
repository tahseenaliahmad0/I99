class_name SuspicionSim
extends RefCounted
## Suspicion (GDD 6.5): 0 to suspicion_max. It exists only while a police car
## is behind (a Patrol) or at a checkpoint. Offences raise it, by the second
## or at once; a tick with no offence by the second is "driving clean" and
## lowers it by suspicion_decay per second. At the top he is pulled over.
##
## DriveSim feeds it each tick: add() for one-off offences, add_rate() for
## those that count by the second, then step().

var value: float = 0.0
## True while someone is watching: only then does anything count.
var watching: bool = false
## True in the tick Suspicion reaches the top.
var reached_max: bool = false
## What one-off offences added this tick.
var jumped: float = 0.0

var _max: float = 100.0
var _decay: float = 0.0
var _rate: float = 0.0


func configure(tuning: Tuning) -> void:
	_max = tuning.f("suspicion_max")
	_decay = tuning.f("suspicion_decay")


func maximum() -> float:
	return _max


## A police car is behind, or he is at a checkpoint: Suspicion starts at 0.
func begin_watch() -> void:
	watching = true
	value = 0.0


## Nobody is watching any more: Suspicion is gone.
func end_watch() -> void:
	watching = false
	value = 0.0


func begin_tick() -> void:
	reached_max = false
	jumped = 0.0
	_rate = 0.0


## A one-off offence.
func add(amount: float) -> void:
	if not watching:
		return
	value = clampf(value + amount, 0.0, _max)
	jumped += amount


## An offence that counts by the second, for this tick.
func add_rate(per_second: float) -> void:
	if watching:
		_rate += per_second


func step(dt: float) -> void:
	if not watching:
		return
	if value >= _max:
		# A one-off offence took it to the top: nothing wears that off.
		reached_max = true
		return
	if _rate > 0.0:
		value = minf(value + _rate * dt, _max)
	else:
		value = maxf(value - _decay * dt, 0.0)
	if value >= _max:
		reached_max = true
