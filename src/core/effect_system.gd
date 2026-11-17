class_name EffectSystem
extends RefCounted
## Timed statuses by id (GDD 13.3): awake, lit, courage, focus, chewing and so
## on, with stack counts and expiry. Items never change other systems
## directly: they add, remove or query statuses here and emit resource changes.
##
## A status is active while it has time left, or while something holds it
## ("while lit", "while tuned to the news"). Stacks are separate timers: each
## Courage sip lasts its own 45 s.

## Statuses that began or ended since begin_tick(); DriveSim turns them into
## effect_added and effect_expired events.
var added: Array[StringName] = []
var expired: Array[StringName] = []

## id -> PackedFloat64Array of seconds left, one entry per stack.
var _timers: Dictionary = {}
## id -> { holder: true }.
var _holds: Dictionary = {}
## id -> Array[StringName] of statuses that imply it ("lit" implies "awake").
var _implied_by: Dictionary = {}
## id -> most stacks it can have.
var _max_stacks: Dictionary = {}
## Numbers a status carries in the registry ("tremor_scale", "road_speed",
## "heavy_floor"...): key -> { id: value }.
var _numbers: Dictionary = {}
## source of Nerves ("honk", "tailgater", "doubt") -> Array[StringName] of the
## statuses that make him immune to it.
var _immune: Dictionary = {}


## Reads the effect registry of items.json: which statuses imply which, and
## how many stacks each may have.
func configure(data: GameData) -> void:
	_implied_by.clear()
	_max_stacks.clear()
	_numbers.clear()
	_immune.clear()
	for record: Dictionary in data.records("effects"):
		var id: StringName = StringName(GameData.as_string(record.get("id")))
		_max_stacks[id] = maxi(GameData.as_int(record.get("max_stacks"), 1), 1)
		for implied: Variant in GameData.as_array(record.get("implies")):
			var target: StringName = StringName(GameData.as_string(implied))
			var sources: Array = _implied_by.get(target, [])
			sources.append(id)
			_implied_by[target] = sources
		for source: Variant in GameData.as_array(record.get("immune")):
			var source_id: StringName = StringName(GameData.as_string(source))
			var shields: Array = _immune.get(source_id, [])
			shields.append(id)
			_immune[source_id] = shields
		for key: Variant in record:
			if GameData.is_number(record[key]) and str(key) != "max_stacks":
				var carriers: Dictionary = _numbers.get(str(key), {})
				carriers[id] = GameData.as_float(record[key])
				_numbers[str(key)] = carriers


func max_stacks(id: StringName) -> int:
	return GameData.as_int(_max_stacks.get(id), 1)


func clear() -> void:
	_timers.clear()
	_holds.clear()
	added.clear()
	expired.clear()


func begin_tick() -> void:
	added.clear()
	expired.clear()


## Adds a timed status. With one stack a new dose replaces the old one only if
## it lasts longer. With more (the registry's max_stacks, or `stack_cap`), each
## dose is its own stack; at the cap the stack with the least time left is
## refreshed.
func add(id: StringName, duration: float, stack_cap: int = 0) -> void:
	if duration <= 0.0:
		return
	var max_stacks: int = stack_cap if stack_cap > 0 else max_stacks(id)
	var was_active: bool = has_own(id)
	var stacks: PackedFloat64Array = _timers.get(id, PackedFloat64Array())
	if max_stacks <= 1:
		if stacks.is_empty():
			stacks.append(duration)
		else:
			stacks[0] = maxf(stacks[0], duration)
	elif stacks.size() < max_stacks:
		stacks.append(duration)
	else:
		var shortest: int = 0
		for index: int in stacks.size():
			if stacks[index] < stacks[shortest]:
				shortest = index
		stacks[shortest] = maxf(stacks[shortest], duration)
	_timers[id] = stacks
	if not was_active:
		added.append(id)


## Holds a status on for as long as `holder` says so ("while" sources).
func hold(id: StringName, holder: StringName, on: bool) -> void:
	var was_active: bool = has_own(id)
	var holders: Dictionary = _holds.get(id, {})
	if on:
		holders[holder] = true
	else:
		holders.erase(holder)
	_holds[id] = holders
	var is_active: bool = has_own(id)
	if is_active and not was_active:
		added.append(id)
	elif was_active and not is_active:
		expired.append(id)


## Ends a status now, whatever its timers and holders.
func remove(id: StringName) -> void:
	if not has_own(id):
		return
	_timers.erase(id)
	_holds.erase(id)
	expired.append(id)


## Adds time to every stack of an active status (a sip that lengthens a burn).
func extend(id: StringName, seconds: float) -> void:
	if not _timers.has(id):
		return
	var stacks: PackedFloat64Array = _timers[id]
	for index: int in stacks.size():
		stacks[index] += seconds
	_timers[id] = stacks


## True while the status is on: by its own timers or holders, or because a
## status that implies it is on.
func has(id: StringName) -> bool:
	if has_own(id):
		return true
	if _implied_by.has(id):
		var sources: Array = _implied_by[id]
		for source: Variant in sources:
			var source_id: StringName = source
			if has_own(source_id):
				return true
	return false


## True while the status is on in its own right (not merely implied).
func has_own(id: StringName) -> bool:
	if _timers.has(id):
		var timers: PackedFloat64Array = _timers[id]
		if not timers.is_empty():
			return true
	if _holds.has(id):
		var holders: Dictionary = _holds[id]
		return not holders.is_empty()
	return false


## The product of a number the registry gives statuses ("tremor_scale"),
## over the statuses that are on in their own right; 1 when none carries it.
func product(key: String) -> float:
	var out: float = 1.0
	if not _numbers.has(key):
		return out
	var carriers: Dictionary = _numbers[key]
	for id: Variant in carriers:
		var name: StringName = id
		if has_own(name):
			out *= GameData.as_float(carriers[id])
	return out


## The sum of such a number ("heavy_floor"); with `per_stack`, each stack of
## a status counts ("nerves_gain_per_stack").
func total(key: String, per_stack: bool = false) -> float:
	var out: float = 0.0
	if not _numbers.has(key):
		return out
	var carriers: Dictionary = _numbers[key]
	for id: Variant in carriers:
		var name: StringName = id
		if has_own(name):
			out += GameData.as_float(carriers[id]) * (float(stacks(name)) if per_stack else 1.0)
	return out


## True while a status that is on makes him immune to Nerves from `source`
## (GDD 7.4: chewing seeds, to honks, tailgaters and Doubts).
func immune_to(source: StringName) -> bool:
	if not _immune.has(source):
		return false
	var shields: Array = _immune[source]
	for shield: Variant in shields:
		var name: StringName = shield
		if has_own(name):
			return true
	return false


## Number of timed stacks (a held status with no timer counts as one).
func stacks(id: StringName) -> int:
	var count: int = 0
	if _timers.has(id):
		var timers: PackedFloat64Array = _timers[id]
		count = timers.size()
	if count == 0 and has_own(id):
		return 1
	return count


## Seconds until the longest stack ends; INF while held; 0 when inactive.
func time_left(id: StringName) -> float:
	if _holds.has(id):
		var holders: Dictionary = _holds[id]
		if not holders.is_empty():
			return INF
	var longest: float = 0.0
	if _timers.has(id):
		var timers: PackedFloat64Array = _timers[id]
		for seconds: float in timers:
			longest = maxf(longest, seconds)
	return longest


func active_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for id: Variant in _timers:
		var name: StringName = id
		if has_own(name):
			out.append(name)
	for id: Variant in _holds:
		var name: StringName = id
		if has_own(name) and not out.has(name):
			out.append(name)
	return out


func step(dt: float) -> void:
	for id: Variant in _timers.keys():
		var name: StringName = id
		var timers: PackedFloat64Array = _timers[name]
		var left: PackedFloat64Array = PackedFloat64Array()
		for seconds: float in timers:
			# Counted in whole ticks: a timer is over when less than half a
			# tick of it would be left, whatever rounding did to the rest.
			if seconds - dt >= dt * 0.5:
				left.append(seconds - dt)
		if left.is_empty():
			_timers.erase(name)
			if not has_own(name):
				expired.append(name)
		else:
			_timers[name] = left


## For the save file: id -> list of seconds left. Holds are not saved; their
## owners set them again.
func get_state() -> Dictionary:
	var out: Dictionary = {}
	for id: Variant in _timers:
		var timers: PackedFloat64Array = _timers[id]
		out[str(id)] = Array(timers)
	return out


func set_state(state: Dictionary) -> void:
	_timers.clear()
	for key: Variant in state:
		var timers: PackedFloat64Array = PackedFloat64Array()
		for seconds: Variant in GameData.as_array(state[key]):
			timers.append(GameData.as_float(seconds))
		if not timers.is_empty():
			_timers[StringName(str(key))] = timers
