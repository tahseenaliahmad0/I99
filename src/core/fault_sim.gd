class_name FaultSim
extends RefCounted
## The Car (GDD 6.3): five warning lamps, each a specific fault. When lit
## lamps reach capacity the engine dies: a Wreck.
##
## M2 counts lamps only; the fault deck and each fault's effect arrive with M3.

var lamps: int = 0
var capacity: int = 0


func configure(tuning: Tuning) -> void:
	capacity = tuning.i("lamp_capacity")
	lamps = 0


func reset() -> void:
	lamps = 0


## Lights `count` more lamps, up to capacity. Returns how many were lit.
func light(count: int) -> int:
	var lit: int = mini(count, capacity - lamps)
	lamps += lit
	return lit


func is_wrecked() -> bool:
	return lamps >= capacity
