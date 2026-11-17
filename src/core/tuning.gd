class_name Tuning
extends RefCounted
## Typed, fail-loud access to data/tuning.json (GDD 15).
##
## The file groups constants for the human who tunes them; code sees one flat
## namespace, so `tuning.f("hand_speed")` works whatever group the key sits in.
## A missing key or a wrong type is an error, never a silent default (GDD 1.3:
## no tuning literals in code). Simulation classes read their values once when
## they are configured and again when `changed_serial` moves (F2 live tuning).

const META_KEYS: PackedStringArray = ["version", "_units", "_notes"]

var changed_serial: int = 0
var problems: PackedStringArray = []

var _values: Dictionary = {}
var _group_of: Dictionary = {}
var _group_order: PackedStringArray = []
var _units: Dictionary = {}
var _version: int = 1


static func from_root(root: Dictionary) -> Tuning:
	var t: Tuning = Tuning.new()
	t._load_root(root)
	return t


func _load_root(root: Dictionary) -> void:
	if root.has("version"):
		_version = int(GameData.as_float(root["version"], 1.0))
	if root.has("_units") and root["_units"] is Dictionary:
		_units = root["_units"]
	for group_key: Variant in root:
		var group_name: String = str(group_key)
		if META_KEYS.has(group_name):
			continue
		var group_value: Variant = root[group_key]
		if not group_value is Dictionary:
			problems.append("group '%s' must be an object of constants" % group_name)
			continue
		_group_order.append(group_name)
		var group: Dictionary = group_value
		for key: Variant in group:
			var name: String = str(key)
			if _values.has(name):
				problems.append("constant '%s' is defined in both '%s' and '%s'" % [name, _group_of[name], group_name])
				continue
			_values[name] = group[key]
			_group_of[name] = group_name


func has(key: String) -> bool:
	return _values.has(key)


func keys() -> PackedStringArray:
	var out: PackedStringArray = []
	for key: Variant in _values:
		out.append(str(key))
	return out


func groups() -> PackedStringArray:
	return _group_order.duplicate()


func group_of(key: String) -> String:
	return str(_group_of.get(key, ""))


func keys_in_group(group_name: String) -> PackedStringArray:
	var out: PackedStringArray = []
	for key: Variant in _values:
		if _group_of[key] == group_name:
			out.append(str(key))
	return out


func unit_of(key: String) -> String:
	return str(_units.get(key, ""))


func raw(key: String) -> Variant:
	if not _values.has(key):
		push_error("Tuning: missing constant '%s'" % key)
		return null
	return _values[key]


## A number.
func f(key: String) -> float:
	var v: Variant = raw(key)
	if GameData.is_number(v):
		return GameData.as_float(v)
	push_error("Tuning: '%s' is not a number" % key)
	return 0.0


## A whole number.
func i(key: String) -> int:
	var v: float = f(key)
	if not is_equal_approx(v, roundf(v)):
		push_error("Tuning: '%s' is not a whole number" % key)
	return int(roundf(v))


func b(key: String) -> bool:
	var v: Variant = raw(key)
	if v is bool:
		return v
	push_error("Tuning: '%s' is not a boolean" % key)
	return false


func s(key: String) -> String:
	var v: Variant = raw(key)
	if v is String:
		return v
	push_error("Tuning: '%s' is not a string" % key)
	return ""


func a(key: String) -> Array:
	var v: Variant = raw(key)
	if v is Array:
		return v
	push_error("Tuning: '%s' is not an array" % key)
	return []


func d(key: String) -> Dictionary:
	var v: Variant = raw(key)
	if v is Dictionary:
		return v
	push_error("Tuning: '%s' is not an object" % key)
	return {}


## An array of numbers, e.g. gear_speeds.
func floats(key: String) -> PackedFloat64Array:
	var out: PackedFloat64Array = []
	for v: Variant in a(key):
		if GameData.is_number(v):
			out.append(GameData.as_float(v))
		else:
			push_error("Tuning: '%s' holds a non-number" % key)
			out.append(0.0)
	return out


## One number out of an array constant, e.g. fi("gear_speeds", 2) for third gear.
func fi(key: String, index: int) -> float:
	var arr: Array = a(key)
	if index < 0 or index >= arr.size():
		push_error("Tuning: '%s' has no index %d" % [key, index])
		return 0.0
	var v: Variant = arr[index]
	if GameData.is_number(v):
		return GameData.as_float(v)
	push_error("Tuning: '%s[%d]' is not a number" % [key, index])
	return 0.0


## One number out of an object constant, e.g. fk("stop_minutes", "fuel").
func fk(key: String, field: String) -> float:
	var obj: Dictionary = d(key)
	if not obj.has(field):
		push_error("Tuning: '%s' has no field '%s'" % [key, field])
		return 0.0
	var v: Variant = obj[field]
	if GameData.is_number(v):
		return GameData.as_float(v)
	push_error("Tuning: '%s.%s' is not a number" % [key, field])
	return 0.0


## A clock constant written "HH:MM", as minutes after midnight.
func clock_minutes(key: String) -> int:
	var text: String = s(key)
	var parts: PackedStringArray = text.split(":")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		push_error("Tuning: '%s' is not a clock time HH:MM" % key)
		return 0
	return parts[0].to_int() * 60 + parts[1].to_int()


## Debug tuning panel (F2): replace a value in memory. Never used by gameplay.
func set_value(key: String, value: Variant) -> void:
	if not _values.has(key):
		push_error("Tuning: cannot set unknown constant '%s'" % key)
		return
	_values[key] = value
	changed_serial += 1


## The file shape again, for the F2 panel's export.
func to_root() -> Dictionary:
	var root: Dictionary = {"version": _version}
	for group_name: String in _group_order:
		var group: Dictionary = {}
		for key: Variant in _values:
			if _group_of[key] == group_name:
				group[key] = _values[key]
		root[group_name] = group
	root["_units"] = _units
	return root
