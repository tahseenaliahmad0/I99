class_name FaultSim
extends RefCounted
## The Car (GDD 6.3). There is no health bar: five warning lamps, and each lit
## lamp is a specific fault.
##
## Each hit lights 1, 2 or 3 lamps and draws that many faults from the
## Telling's fault deck, a seeded shuffle of the faults in faults.json. When
## lit lamps reach capacity the engine dies: a Wreck. A fitter removes one
## chosen fault and its lamp.

## Faults lit now, in the order they were drawn.
var active: Array[StringName] = []
## Faults still in the deck, next to be drawn first.
var deck: Array[StringName] = []
## Lamp capacity now: lamp_capacity plus what the cabin adds or removes.
var capacity: int = 0
## Lit lamps (the same as active.size()).
var lamps: int = 0

var _base_capacity: int = 0
var _capacity_bonus: int = 0
## fault id -> its "params" object.
var _params: Dictionary = {}
var _order: Array[StringName] = []


func configure(data: GameData) -> void:
	_base_capacity = data.tuning.i("lamp_capacity")
	_params.clear()
	_order.clear()
	for record: Dictionary in data.records("faults"):
		var id: StringName = StringName(GameData.as_string(record.get("id")))
		_order.append(id)
		_params[id] = GameData.as_dict(record.get("params"))
	_capacity_bonus = 0
	reset()


## Empties the lamps and puts the deck back in file order (unshuffled).
func reset() -> void:
	active.clear()
	deck = _order.duplicate()
	lamps = 0
	capacity = _base_capacity + _capacity_bonus


## Shuffles a fresh deck for a Telling from the road stream (same seed, same order).
func shuffle_deck(rng: Rng) -> void:
	active.clear()
	lamps = 0
	deck = _order.duplicate()
	rng.shuffle_array(Rng.ROAD, deck)


## Lamp capacity changes with the cabin (Bull bar +1, Tinted glass -1, Turbo -1).
func set_capacity_bonus(bonus: int) -> void:
	_capacity_bonus = bonus
	capacity = maxi(_base_capacity + _capacity_bonus, 1)


## Lights `count` lamps: draws that many faults from the deck, as far as the
## capacity and the deck allow. Returns the faults drawn.
func light(count: int) -> Array[StringName]:
	var drawn: Array[StringName] = []
	for _draw: int in count:
		if lamps >= capacity or deck.is_empty():
			break
		var fault: StringName = deck.pop_front()
		active.append(fault)
		drawn.append(fault)
		lamps = active.size()
	return drawn


func is_wrecked() -> bool:
	return lamps >= capacity


func has(fault: StringName) -> bool:
	return active.has(fault)


## Removes one chosen fault and its lamp (GDD 6.3). The fault goes to the
## bottom of the deck. Returns false if it was not lit.
func repair(fault: StringName) -> bool:
	var index: int = active.find(fault)
	if index == -1:
		return false
	active.remove_at(index)
	deck.append(fault)
	lamps = active.size()
	return true


## A number from a lit fault's params, or `fallback` when the fault is not lit.
## e.g. param(&"pulling_steering", "drift_left", 0.0)
func param(fault: StringName, key: String, fallback: float) -> float:
	if not active.has(fault):
		return fallback
	return param_of(fault, key, fallback)


## A number from a fault's params whether it is lit or not.
func param_of(fault: StringName, key: String, fallback: float) -> float:
	if not _params.has(fault):
		return fallback
	var params: Dictionary = _params[fault]
	if not params.has(key):
		return fallback
	return GameData.as_float(params[key], fallback)


func fault_ids() -> Array[StringName]:
	return _order.duplicate()
