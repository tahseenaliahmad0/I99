class_name NervesSim
extends RefCounted
## Nerves (GDD 6.1): one meter, 0 to 100. High is Frayed, low is Heavy.
##
## M2 holds the meter only; the thresholds, the Heavy floor, Awake and the
## impairments arrive with M3.

const MIN: float = 0.0
const MAX: float = 100.0

var value: float = 0.0

var _start: float = 0.0


func configure(tuning: Tuning) -> void:
	_start = tuning.f("nerves_start")
	value = _start


func reset() -> void:
	value = _start


func add(amount: float) -> void:
	value = clampf(value + amount, MIN, MAX)
