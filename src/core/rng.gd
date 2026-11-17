class_name Rng
extends RefCounted
## The simulation's randomness (GDD 1.3, 13.3): four seeded streams derived
## from the Telling seed. Same seed and same draws give the same numbers on
## every machine. Nothing in src/core may use the global random functions.
##
##   road    the road ahead: legs, beats, traffic, the fault deck
##   shop    what the stalls offer
##   heckle  what the Table says
##   bot     the driver bot's imperfections

const ROAD: StringName = &"road"
const SHOP: StringName = &"shop"
const HECKLE: StringName = &"heckle"
const BOT: StringName = &"bot"
const STREAMS: Array[StringName] = [ROAD, SHOP, HECKLE, BOT]
## Spreads small salts (1, 2, 3...) across the seed's bits.
const SALT_SPREAD: int = 0x9E3779B1

var telling_seed: int = 0

var _streams: Dictionary = {}


func _init(seed_value: int = 0) -> void:
	reseed(seed_value)


func reseed(seed_value: int) -> void:
	telling_seed = seed_value
	_streams.clear()
	for index: int in STREAMS.size():
		var generator: RandomNumberGenerator = RandomNumberGenerator.new()
		generator.seed = derive(seed_value, index + 1)
		_streams[STREAMS[index]] = generator


## A new seed from a seed and a salt, the same on every machine. Used for the
## four streams and for anything that needs its own repeatable sequence (one
## leg of a Telling, the daily Commute).
static func derive(seed_value: int, salt: int) -> int:
	var deriver: RandomNumberGenerator = RandomNumberGenerator.new()
	deriver.seed = seed_value
	deriver.seed = (int(deriver.randi()) << 31) ^ int(deriver.randi()) ^ (salt * SALT_SPREAD)
	return (int(deriver.randi()) << 31) ^ int(deriver.randi())


func stream(stream_name: StringName) -> RandomNumberGenerator:
	if not _streams.has(stream_name):
		push_error("Rng: unknown stream '%s'" % stream_name)
		return RandomNumberGenerator.new()
	var generator: RandomNumberGenerator = _streams[stream_name]
	return generator


## A float in [0, 1).
func unit(stream_name: StringName) -> float:
	return stream(stream_name).randf()


## A float in [low, high].
func range_f(stream_name: StringName, low: float, high: float) -> float:
	return stream(stream_name).randf_range(low, high)


## A whole number in [low, high].
func range_i(stream_name: StringName, low: int, high: int) -> int:
	return stream(stream_name).randi_range(low, high)


## True with the given probability.
func chance(stream_name: StringName, probability: float) -> bool:
	return stream(stream_name).randf() < probability


## An index picked in proportion to the weights. -1 if every weight is zero.
func weighted_index(stream_name: StringName, weights: PackedFloat64Array) -> int:
	var total: float = 0.0
	for weight: float in weights:
		total += maxf(weight, 0.0)
	if total <= 0.0:
		return -1
	var roll: float = stream(stream_name).randf() * total
	for index: int in weights.size():
		roll -= maxf(weights[index], 0.0)
		if roll < 0.0:
			return index
	return weights.size() - 1


## Shuffles in place (Fisher-Yates) with this stream.
func shuffle(stream_name: StringName, items: Array) -> void:
	var generator: RandomNumberGenerator = stream(stream_name)
	for index: int in range(items.size() - 1, 0, -1):
		var other: int = generator.randi_range(0, index)
		var held: Variant = items[index]
		items[index] = items[other]
		items[other] = held


## For the save file (GDD 13.7): stream name -> [seed, state].
func get_state() -> Dictionary:
	var out: Dictionary = {}
	for stream_name: StringName in STREAMS:
		var generator: RandomNumberGenerator = _streams[stream_name]
		out[String(stream_name)] = [str(generator.seed), str(generator.state)]
	return out


func set_state(state: Dictionary) -> void:
	for stream_name: StringName in STREAMS:
		var key: String = String(stream_name)
		if not state.has(key):
			continue
		var pair: Array = GameData.as_array(state[key])
		if pair.size() != 2:
			continue
		var generator: RandomNumberGenerator = _streams[stream_name]
		generator.seed = GameData.as_string(pair[0]).to_int()
		generator.state = GameData.as_string(pair[1]).to_int()
