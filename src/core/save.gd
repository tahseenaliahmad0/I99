class_name Save
extends RefCounted
## The save file (GDD 13.7): `user://save.json`, written at stops and after
## bosses, never during a leg. This class turns the profile and the Telling
## into its text and back; the Game autoload reads and writes the file.
##
##   { "version": 1,
##     "profile": { "tables_unlocked": [...], "told_true": [...], "guests": [...],
##                  "modes": [...], "prologue_seen": bool },
##     "telling": { ... what DriveSim.capture() gives ... } or null }

const VERSION: int = 1
const FILE_NAME: String = "save.json"
## Whole numbers up to this size survive JSON, which knows only doubles.
const JSON_INT_LIMIT: int = 9007199254740992


## What a player who has never played has.
static func default_profile() -> Dictionary:
	return {
		"tables_unlocked": ["children"],
		"told_true": [],
		"guests": [],
		"modes": [],
		"prologue_seen": false,
	}


## The file's text. `telling` is {} when no Telling is under way.
static func to_text(profile: Dictionary, telling: Dictionary) -> String:
	var root: Dictionary = {"version": VERSION, "profile": profile, "telling": null}
	if not telling.is_empty():
		root["telling"] = telling
	return JSON.stringify(_tidy(root), "  ", false)


## Whole numbers as whole numbers, so that a file read and written again is
## the same file (JSON has one kind of number and reads 3 as 3.0).
static func _tidy(value: Variant) -> Variant:
	if value is float:
		var number: float = value
		if is_finite(number) and floorf(number) == number and absf(number) < float(JSON_INT_LIMIT):
			return int(number)
		return number
	if value is Dictionary:
		var out: Dictionary = {}
		var source: Dictionary = value
		for key: Variant in source:
			out[key] = _tidy(source[key])
		return out
	if value is Array:
		var list: Array = []
		for entry: Variant in value as Array:
			list.append(_tidy(entry))
		return list
	return value


## A number as its exact bits. The readable numbers of a save are for people
## and are rounded; a text can lose the last bit of a float, and a Telling
## that goes on from a save must be the one that was saved, to the bit.
static func exact(number: float) -> String:
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0, number)
	return bytes.hex_encode()


## The number its exact bits stand for, or `fallback` when they are not
## sixteen hexadecimal digits.
static func from_exact(bits: Variant, fallback: float) -> float:
	if not bits is String or (bits as String).length() != 16 or not (bits as String).is_valid_hex_number():
		return fallback
	return (bits as String).hex_decode().decode_double(0)


## Reads the file's text: { "ok": bool, "error": String, "profile": Dictionary,
## "telling": Dictionary }. A file that cannot be read gives the default
## profile and no Telling, with the reason in "error".
static func from_text(text: String) -> Dictionary:
	var out: Dictionary = {"ok": false, "error": "", "profile": default_profile(), "telling": {}}
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		out["error"] = "not JSON: %s" % json.get_error_message()
		return out
	if not json.data is Dictionary:
		out["error"] = "the save is not an object"
		return out
	var root: Dictionary = json.data
	if GameData.as_int(root.get("version"), -1) != VERSION:
		out["error"] = "version %s is not %d" % [str(root.get("version")), VERSION]
		return out
	root = _tidy(root)
	var profile: Dictionary = default_profile()
	var stored: Dictionary = GameData.as_dict(root.get("profile"))
	for key: Variant in profile:
		if stored.has(key) and typeof(stored[key]) == typeof(profile[key]):
			profile[key] = stored[key]
	out["profile"] = profile
	out["telling"] = GameData.as_dict(root.get("telling"))
	out["ok"] = true
	return out


## A seed as JSON can hold it: a number while it fits, else its digits.
static func seed_out(seed_value: int) -> Variant:
	if absi(seed_value) < JSON_INT_LIMIT:
		return seed_value
	return str(seed_value)


static func seed_in(stored: Variant) -> int:
	if stored is String:
		return (stored as String).to_int()
	return GameData.as_int(stored)
