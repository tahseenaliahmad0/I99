class_name DataValidator
extends RefCounted
## Validates every file under res://data (GDD 14, test T-DATA-01).
##
## Checks required keys, types, unique ids, and that every referenced id and
## line id exists. Returns a list of messages, each starting with a code:
##   [E_FILE] [E_JSON] [E_LINES] [E_DUP_ID] [E_ID] [E_MISSING] [E_TYPE]
##   [E_ENUM] [E_RANGE] [E_REF] [E_UNKNOWN_KEY] [E_TUNING] [E_RULE]
## An empty list means the data is valid. The validator never logs engine
## errors itself; callers decide how to report.
##
## A schema is a Dictionary: {"t": type, ...options}. Types:
##   any str num int bool enum ref list map obj color vec3 res clock
## Options: "opt" (field may be absent), "null" (value may be null),
##   "min"/"max", "values" (enum), "to" (ref target), "of" (list or map
##   element), "len"/"min_len" (list), "keys" (map key schema),
##   "fields"/"open" (obj), "non_empty" (str).

const ID_PATTERN: String = "^[a-z][a-z0-9_]*$"
const LINE_ID_PATTERN: String = "^[a-z0-9_]+(\\.[a-z0-9_]+)+$"

const ITEM_KINDS: PackedStringArray = ["habit", "keepsake", "adaptation", "deal", "fixture"]
const RARITIES: PackedStringArray = ["common", "uncommon", "rare"]
const GESTURES: PackedStringArray = ["TAP", "HOLD", "FLICK", "DRAG_TO", "CRANK", "BEAD", "GATE"]
const BEAT_TYPES: PackedStringArray = ["CALM", "CLUSTER", "SLOWPOKE", "MERGE", "CURVE", "GUST", "HAZARD", "SPECIAL"]
const HECKLE_TYPES: PackedStringArray = ["TWIST", "DARE", "DOUBT", "QUESTION", "ORDER", "FIB"]
const FLICK_DIRS: PackedStringArray = ["up", "down", "left", "right"]
const PLACEHOLDER_SHAPES: PackedStringArray = ["box", "cylinder", "capsule", "sphere", "quad", "label"]
const REQUIRED_POINTS: PackedStringArray = ["G", "W", "eye", "shoulder"]

var errors: PackedStringArray = []

var _data: GameData
var _id_regex: RegEx = RegEx.new()
var _line_id_regex: RegEx = RegEx.new()


static func validate(data: GameData) -> PackedStringArray:
	var validator: DataValidator = DataValidator.new()
	return validator.run(data)


func run(data: GameData) -> PackedStringArray:
	_data = data
	errors = data.errors.duplicate()
	_id_regex.compile(ID_PATTERN)
	_line_id_regex.compile(LINE_ID_PATTERN)

	for file: String in GameData.JSON_FILES:
		if not data.roots.has(file):
			if not _has_load_error_for(file):
				_err("E_FILE", "%s.json" % file, "", "file was not loaded")
	_check_tuning()
	_check_lines()
	_check_anchor_file()
	_check_registry("placeholders", _placeholder_schema())
	_check_registry("sfx", _sfx_schema())
	_check_record_set("slots", _slot_schema())
	_check_record_set("vehicles", _vehicle_schema())
	_check_record_set("faults", _fault_schema())
	_check_record_set("rituals", _ritual_schema())
	_check_record_set("items", _item_schema())
	_check_record_set("modifiers", _modifier_schema())
	_check_record_set("beats", _beat_schema())
	_check_record_set("legs", _leg_schema())
	_check_record_set("stops", _stop_schema())
	_check_record_set("passengers", _passenger_schema())
	_check_record_set("tables", _table_schema())
	_check_record_set("heckles", _heckle_schema())
	_check_cross_rules()
	return errors


# --- Schema builders ---------------------------------------------------------

static func _t(type_name: String) -> Dictionary:
	return {"t": type_name}


static func _str() -> Dictionary:
	return {"t": "str"}


static func _num(minimum: float = -INF, maximum: float = INF) -> Dictionary:
	return {"t": "num", "min": minimum, "max": maximum}


static func _int(minimum: float = -INF, maximum: float = INF) -> Dictionary:
	return {"t": "int", "min": minimum, "max": maximum}


static func _bool() -> Dictionary:
	return {"t": "bool"}


static func _enum(values: PackedStringArray) -> Dictionary:
	return {"t": "enum", "values": values}


static func _ref(target: String) -> Dictionary:
	return {"t": "ref", "to": target}


static func _list(of: Dictionary, min_len: int = 0) -> Dictionary:
	return {"t": "list", "of": of, "min_len": min_len}


static func _list_n(of: Dictionary, length: int) -> Dictionary:
	return {"t": "list", "of": of, "len": length}


static func _map(of: Dictionary) -> Dictionary:
	return {"t": "map", "of": of}


static func _map_keyed(keys: Dictionary, of: Dictionary) -> Dictionary:
	return {"t": "map", "of": of, "keys": keys}


static func _obj(fields: Dictionary, open: bool = false) -> Dictionary:
	return {"t": "obj", "fields": fields, "open": open}


static func _opt(spec: Dictionary) -> Dictionary:
	var out: Dictionary = spec.duplicate()
	out["opt"] = true
	return out


static func _nullable(spec: Dictionary) -> Dictionary:
	var out: Dictionary = spec.duplicate()
	out["null"] = true
	return out


# --- Schemas (GDD 14) --------------------------------------------------------

func _item_schema() -> Dictionary:
	return _obj({
		"id": _str(),
		"kind": _enum(ITEM_KINDS),
		"slots": _list(_ref("slots")),
		"tags": _opt(_list(_str())),
		"rarity": _opt(_enum(RARITIES)),
		"price": _num(0.0),
		"contraband": _bool(),
		"supply": _opt(_nullable(_obj({"uses": _int(0.0), "restock": _num(0.0)}))),
		"rituals": _list(_ref("rituals")),
		"gives": _list(_obj({}, true)),
		"takes": _list(_obj({}, true)),
		"lapse": _opt(_nullable(_obj({}, true))),
		"synergies": _opt(_list(_obj({"with": _str(), "rule": _str(), "amount": _opt(_num())}, true))),
		"line_ids": _map(_ref("lines")),
	})


func _ritual_schema() -> Dictionary:
	return _obj({
		"id": _str(),
		"anchor": _ref("anchors"),
		"gesture": _enum(GESTURES),
		"hold_s": _opt(_num(0.0)),
		"flick_dirs": _opt(_list(_enum(FLICK_DIRS), 1)),
		"turns": _opt(_num(0.0)),
		"eyes_down": _bool(),
		"blocks_view": _opt(_nullable(_str())),
		"requires": _list(_str()),
		"on_complete": _list(_str()),
		"sfx": _opt(_nullable(_ref("sfx"))),
	}, true)


func _leg_schema() -> Dictionary:
	return _obj({
		"id": _str(),
		"acts": _list(_int(1.0, 3.0), 1),
		"lanes": _int(1.0, 3.0),
		"divided": _bool(),
		"density": _num(0.0),
		"condition": _str(),
		"par_s": _num(0.0),
		"beat_weights": _map_keyed(_enum(BEAT_TYPES), _num(0.0)),
		"special": _opt(_nullable(_obj({"kind": _str()}, true))),
		"modifiers_allowed": _list(_ref("modifiers")),
	}, true)


func _beat_schema() -> Dictionary:
	return _obj({
		"id": _str(),
		"type": _enum(BEAT_TYPES),
		"length_m": _num(0.0),
		"min_lanes": _opt(_int(1.0, 3.0)),
		"spawns": _list(_obj({"vehicle": _ref("vehicles")}, true)),
	}, true)


func _vehicle_schema() -> Dictionary:
	return _obj({"id": _str()}, true)


func _modifier_schema() -> Dictionary:
	return _obj({"id": _str()}, true)


func _stop_schema() -> Dictionary:
	return _obj({
		"id": _str(),
		"service": _str(),
		"stock": _opt(_nullable(_obj({"count": _int(0.0), "pools": _list(_enum(ITEM_KINDS))}, true))),
		"clock_min": _num(0.0),
		"weight": _num(0.0),
	}, true)


func _passenger_schema() -> Dictionary:
	return _obj({
		"id": _str(),
		"rides_legs": _opt(_int(1.0)),
		"rides_until": _opt(_enum(PackedStringArray(["act_end", "basra"]))),
		"fare": _num(0.0),
		"hand": _obj({"kind": _str()}, true),
		"weights": _list(_obj({}, true)),
		"on_leave": _opt(_list(_str())),
		"line_prefix": _ref("line_prefix"),
	}, true)


func _table_schema() -> Dictionary:
	return _obj({
		"id": _str(),
		"unlock": _str(),
		"depart_min": _num(0.0),
		"rules": _obj({}, true),
		"heckle_weights": _map_keyed(_enum(HECKLE_TYPES), _num(0.0)),
		"line_prefix": _ref("line_prefix"),
	}, true)


func _heckle_schema() -> Dictionary:
	return _obj({
		"id": _str(),
		"type": _enum(HECKLE_TYPES),
		"tables": _list(_ref("tables"), 1),
		"line_id": _ref("lines"),
		"window_s": _opt(_num(0.0)),
		"answer": _opt(_list(_str())),
		"pass": _opt(_obj({}, true)),
		"fail": _opt(_obj({}, true)),
	}, true)


func _fault_schema() -> Dictionary:
	return _obj({
		"id": _str(),
		"params": _map(_num()),
		"line_ids": _opt(_map(_ref("lines"))),
	})


func _slot_schema() -> Dictionary:
	return _obj({"id": _str()}, true)


func _anchor_schema() -> Dictionary:
	return _obj({
		"id": _str(),
		"pos": _t("vec3"),
		"time_s": _num(0.0),
		"via_w": _opt(_bool()),
	})


func _placeholder_schema() -> Dictionary:
	return _obj({
		"placeholder": _obj({
			"shape": _enum(PLACEHOLDER_SHAPES),
			"size": _list(_num(0.0), 1),
			"color": _t("color"),
		}, true),
		"scene": _nullable(_t("res")),
	})


func _sfx_schema() -> Dictionary:
	return _obj({
		"synth": _obj({}, true),
		"stream": _nullable(_t("res")),
	})


## Every constant of GDD 15, with its shape. tuning.json may hold more; each
## extra constant must still be a number, boolean, string, or a list or object
## of those.
func _tuning_schema() -> Dictionary:
	var n: Dictionary = _num()
	var pos: Dictionary = _num(0.0)
	return {
		# Hand and wheel
		"hand_speed": pos, "hand_left_side_mult": pos, "hand_pound_mult": pos,
		"anchor_snap_radius": pos, "input_buffer": pos, "grip_zone_half_width": pos,
		"wheel_max_angle": pos, "steer_deg_per_px": pos, "wheel_smoothing": pos,
		"wheel_return_rate": pos, "gate_unit": pos, "gate_channel_half_width": pos,
		"glance_start": pos, "glance_gain": pos, "glance_max_yaw": pos,
		"glance_max_pitch": pos, "eyes_down_pitch": pos,
		# Car
		"lane_width": pos, "car_width": pos, "car_length": pos,
		"leg_length": pos, "leg_tail": pos,
		"gear_speeds": _list_n(pos, 5), "lat_per_kmh": pos, "lat_follow_tau": pos,
		"gear_cash_mult": _list_n(pos, 5),
		"accel": pos, "engine_brake": pos, "brake_decel": pos, "neutral_coast": pos,
		"crown_drift": pos, "curve_k": _list_n(pos, 3), "curve_cap": pos,
		"gust_push": pos, "gust_duration": pos,
		"shoulder_speed_cap": pos, "exit_max_speed": pos,
		# Collisions and close calls
		"scrape_max_closing": pos, "crash_max_closing": pos, "hit_immunity": pos,
		"hit_pushback": pos, "close_call_gap": pos, "close_call_min_closing": pos,
		"close_call_base_cash": pos, "chain_window": pos, "chain_step": pos, "chain_cap": pos,
		# Nerves
		"nerves_start": _num(0.0, 100.0),
		"tremor_from": _num(0.0, 100.0), "tunnel_from": _num(0.0, 100.0),
		"pound_from": _num(0.0, 100.0), "snap_at": _num(0.0, 100.0), "snap_reset": _num(0.0, 100.0),
		"heavy_floor": _list_n(_num(0.0, 100.0), 3), "nod_depth": pos,
		"tremor_frequency": pos, "tremor_max_amplitude": pos,
		"blink_period": pos, "blink_length": pos, "blink_tell": pos,
		"nod_period": pos, "nod_length": pos, "nod_tell": pos,
		"lids_close_time": pos, "lids_max": _num(0.0, 0.5),
		"empty_road_radius": pos, "empty_road_rate": n,
		"traffic_radius": pos, "traffic_rate": pos, "traffic_rate_cap": pos,
		"sway_per_stack": pos, "sway_frequency": pos,
		"lag_per_source": pos, "lag_cap": pos, "haze_cap": _num(0.0, 1.0),
		# Car faults, cash, clock, law
		"lamp_capacity": _int(1.0), "repair_price": pos, "repair_minutes": pos,
		"cash_start": pos, "clean_leg_bonus": pos, "par_bonus_rate": pos,
		"clock_start": _t("clock"), "clock_deadline": _t("clock"), "clock_scale": pos,
		"patrol_duration": pos, "suspicion_decay": pos,
		"fine_share": _num(0.0, 1.0), "fine_min": pos, "fine_minutes": pos,
		"bribe_base": pos, "bribe_per_act": pos, "bribe_minutes": pos,
		"checkpoint_bribe": pos,
		# Structure
		"spawn_ahead": pos, "spawn_ahead_oncoming": pos, "despawn_behind": pos,
		"signal_time": pos, "late_signal_time": pos, "lane_change_time": pos,
		"calm_length": pos, "first_event_within": pos, "heckle_lead": pos,
		"stop_minutes": _obj({"fuel": pos, "fitter": pos, "tea": pos, "find": pos, "hitcher": pos, "shady": pos}),
		"stop_weights": _obj({"fuel": pos, "fitter": pos, "tea": pos, "find": pos, "hitcher": pos}),
		"rarity_by_act": _list_n(_list_n(pos, 3), 3),
		"wreck_to_wheel": pos,
	}


# --- File checks -------------------------------------------------------------

func _check_tuning() -> void:
	if not _data.roots.has("tuning"):
		return
	var tuning: Tuning = _data.tuning
	for problem: String in tuning.problems:
		_err("E_TUNING", "tuning.json", "", problem)
	var schema: Dictionary = _tuning_schema()
	for key: Variant in schema:
		var name: String = str(key)
		if not tuning.has(name):
			_err("E_MISSING", "tuning.json", name, "required constant is missing (GDD 15)")
			continue
		var spec: Dictionary = schema[key]
		_check(tuning.raw(name), spec, "tuning.json", name)
	for name: String in tuning.keys():
		if schema.has(name):
			continue
		if not _is_plain_value(tuning.raw(name), 0):
			_err("E_TYPE", "tuning.json", name, "must be a number, boolean, string, or a list or object of those")
	var root: Dictionary = _data.root("tuning")
	if root.has("_units"):
		var units: Variant = root["_units"]
		if units is Dictionary:
			var unit_map: Dictionary = units
			for key: Variant in unit_map:
				if not tuning.has(str(key)):
					_err("E_REF", "tuning.json", "_units.%s" % str(key), "unit given for a constant that does not exist")
		else:
			_err("E_TYPE", "tuning.json", "_units", "must be an object")
	# Rarity shares are percentages.
	if tuning.has("rarity_by_act") and tuning.raw("rarity_by_act") is Array:
		var acts: Array = tuning.raw("rarity_by_act")
		for act_index: int in acts.size():
			var total: float = 0.0
			for share: Variant in GameData.as_array(acts[act_index]):
				total += GameData.as_float(share)
			if not is_equal_approx(total, 100.0):
				_err("E_RULE", "tuning.json", "rarity_by_act[%d]" % act_index, "shares must add up to 100, found %s" % str(total))


func _is_plain_value(v: Variant, depth: int) -> bool:
	if v is float or v is int or v is bool or v is String:
		return true
	if depth >= 3:
		return false
	if v is Array:
		var arr: Array = v
		for entry: Variant in arr:
			if not _is_plain_value(entry, depth + 1):
				return false
		return true
	if v is Dictionary:
		var dict: Dictionary = v
		for key: Variant in dict:
			if not _is_plain_value(dict[key], depth + 1):
				return false
		return true
	return false


func _check_lines() -> void:
	var en_ids: PackedStringArray = _data.line_ids("en")
	for id: String in en_ids:
		if _line_id_regex.search(id) == null:
			_err("E_ID", "lines_en.csv", id, "line ids are lower-case words joined by dots")
		var entry: Dictionary = _data.line(id, "en")
		if GameData.as_string(entry.get("text")).strip_edges().is_empty():
			_err("E_LINES", "lines_en.csv", id, "English text is empty")
	for id: String in en_ids:
		if not _data.has_line(id, "ar"):
			_err("E_LINES", "lines_ar.csv", id, "line id is missing (both files carry the same ids)")
	for id: String in _data.line_ids("ar"):
		if not _data.has_line(id, "en"):
			_err("E_LINES", "lines_ar.csv", id, "line id does not exist in lines_en.csv")


func _check_anchor_file() -> void:
	if not _data.roots.has("anchors"):
		return
	var root: Dictionary = _data.root("anchors")
	var points: Variant = root.get("points")
	if points is Dictionary:
		var point_map: Dictionary = points
		for name: String in REQUIRED_POINTS:
			if not point_map.has(name):
				_err("E_MISSING", "anchors.json", "points.%s" % name, "required point is missing (GDD 16.2)")
		for key: Variant in point_map:
			_check(point_map[key], _t("vec3"), "anchors.json", "points.%s" % str(key))
	else:
		_err("E_MISSING", "anchors.json", "points", "required object is missing")
	_check_record_set("anchors", _anchor_schema())


func _check_registry(file: String, schema: Dictionary) -> void:
	if not _data.roots.has(file):
		return
	var root: Dictionary = _data.root(file)
	for key: Variant in root:
		var id: String = str(key)
		if _id_regex.search(id) == null:
			_err("E_ID", "%s.json" % file, id, "ids are lower-case letters, digits and underscores")
		_check(root[key], schema, "%s.json" % file, id)


func _check_record_set(set_name: String, schema: Dictionary) -> void:
	var where: Array = GameData.RECORD_SETS[set_name]
	var file: String = where[0]
	var key: String = where[1]
	if not _data.roots.has(file):
		return
	var file_label: String = "%s.json" % file
	var root: Dictionary = _data.root(file)
	if not root.has(key):
		_err("E_MISSING", file_label, key, "required list is missing")
		return
	var list: Variant = root[key]
	if not list is Array:
		_err("E_TYPE", file_label, key, "must be a list of records")
		return
	var entries: Array = list
	var seen: Dictionary = {}
	for index: int in entries.size():
		var entry: Variant = entries[index]
		var label: String = "%s[%d]" % [key, index]
		if entry is Dictionary:
			var record: Dictionary = entry
			if record.has("id") and record["id"] is String:
				var id: String = record["id"]
				label = "%s[%s]" % [key, id]
				if _id_regex.search(id) == null:
					_err("E_ID", file_label, label, "ids are lower-case letters, digits and underscores")
				if seen.has(id):
					_err("E_DUP_ID", file_label, label, "duplicate id")
				seen[id] = true
		_check(entry, schema, file_label, label)


## Rules that span fields or files.
func _check_cross_rules() -> void:
	for table: Dictionary in _data.records("tables"):
		var unlock: String = GameData.as_string(table.get("unlock"))
		var label: String = "tables[%s].unlock" % GameData.as_string(table.get("id"), "?")
		if unlock == "start":
			continue
		if unlock.begins_with("win:"):
			var target: String = unlock.substr(4)
			if not _data.has_record("tables", target):
				_err("E_REF", "tables.json", label, "unknown table id '%s'" % target)
		elif table.has("unlock") and table["unlock"] is String:
			_err("E_ENUM", "tables.json", label, "must be \"start\" or \"win:<table id>\"")
	for passenger: Dictionary in _data.records("passengers"):
		var has_legs: bool = passenger.has("rides_legs")
		var has_until: bool = passenger.has("rides_until")
		if has_legs == has_until:
			_err("E_RULE", "passengers.json", "passengers[%s]" % GameData.as_string(passenger.get("id"), "?"),
					"needs exactly one of rides_legs and rides_until")
	for ritual: Dictionary in _data.records("rituals"):
		var needs: String = ""
		match GameData.as_string(ritual.get("gesture")):
			"HOLD":
				needs = "hold_s"
			"FLICK":
				needs = "flick_dirs"
			"CRANK":
				needs = "turns"
		if not needs.is_empty() and not ritual.has(needs):
			_err("E_RULE", "rituals.json", "rituals[%s]" % GameData.as_string(ritual.get("id"), "?"),
					"a %s ritual needs \"%s\"" % [GameData.as_string(ritual.get("gesture")), needs])
	for item: Dictionary in _data.records("items"):
		var item_id: String = GameData.as_string(item.get("id"), "?")
		var synergies: Array = GameData.as_array(item.get("synergies"))
		for index: int in synergies.size():
			var synergy: Dictionary = GameData.as_dict(synergies[index])
			var with: String = GameData.as_string(synergy.get("with"))
			if with.is_empty():
				continue
			if not _data.has_record("items", with) and not _synergy_tokens().has(with):
				_err("E_REF", "items.json", "items[%s].synergies[%d].with" % [item_id, index],
						"unknown item id or synergy token '%s'" % with)


## Things a synergy can pair with that are not items (GDD 7.8: music, the photo).
func _synergy_tokens() -> PackedStringArray:
	var out: PackedStringArray = []
	var root: Dictionary = _data.root("items")
	for token: Variant in GameData.as_array(root.get("synergy_tokens")):
		out.append(str(token))
	return out


# --- The schema engine -------------------------------------------------------

func _check(value: Variant, spec: Dictionary, file_label: String, where: String) -> void:
	if value == null:
		if not GameData.as_bool(spec.get("null")):
			_err("E_TYPE", file_label, where, "must not be null")
		return
	var type_name: String = spec["t"]
	match type_name:
		"any":
			pass
		"str":
			if not value is String:
				_err("E_TYPE", file_label, where, "must be a string")
		"num":
			if not GameData.is_number(value):
				_err("E_TYPE", file_label, where, "must be a number")
			else:
				_check_range(GameData.as_float(value), spec, file_label, where)
		"int":
			if not GameData.is_number(value):
				_err("E_TYPE", file_label, where, "must be a whole number")
			else:
				var number: float = GameData.as_float(value)
				if not is_equal_approx(number, roundf(number)):
					_err("E_TYPE", file_label, where, "must be a whole number")
				_check_range(number, spec, file_label, where)
		"bool":
			if not value is bool:
				_err("E_TYPE", file_label, where, "must be true or false")
		"enum":
			var values: PackedStringArray = spec["values"]
			if not value is String:
				_err("E_TYPE", file_label, where, "must be one of %s" % ", ".join(values))
			elif not values.has(str(value)):
				_err("E_ENUM", file_label, where, "'%s' is not one of %s" % [str(value), ", ".join(values)])
		"ref":
			var target: String = spec["to"]
			if not value is String:
				_err("E_TYPE", file_label, where, "must be a %s id" % target)
			elif not _exists(target, str(value)):
				_err("E_REF", file_label, where, "unknown %s id '%s'" % [target, str(value)])
		"list":
			if not value is Array:
				_err("E_TYPE", file_label, where, "must be a list")
			else:
				var list: Array = value
				if spec.has("len") and list.size() != GameData.as_int(spec["len"]):
					_err("E_RANGE", file_label, where, "must hold exactly %d entries, found %d" % [GameData.as_int(spec["len"]), list.size()])
				if list.size() < GameData.as_int(spec.get("min_len")):
					_err("E_RANGE", file_label, where, "must hold at least %d entries" % GameData.as_int(spec.get("min_len")))
				var of: Dictionary = spec["of"]
				for index: int in list.size():
					_check(list[index], of, file_label, "%s[%d]" % [where, index])
		"map":
			if not value is Dictionary:
				_err("E_TYPE", file_label, where, "must be an object")
			else:
				var map: Dictionary = value
				var of: Dictionary = spec["of"]
				for key: Variant in map:
					if spec.has("keys"):
						var key_spec: Dictionary = spec["keys"]
						_check(str(key), key_spec, file_label, "%s.<key %s>" % [where, str(key)])
					_check(map[key], of, file_label, "%s.%s" % [where, str(key)])
		"obj":
			if not value is Dictionary:
				_err("E_TYPE", file_label, where, "must be an object")
			else:
				var obj: Dictionary = value
				var fields: Dictionary = spec["fields"]
				for field: Variant in fields:
					var field_spec: Dictionary = fields[field]
					var field_name: String = str(field)
					if not obj.has(field_name):
						if not GameData.as_bool(field_spec.get("opt")):
							_err("E_MISSING", file_label, "%s.%s" % [where, field_name], "required key is missing")
						continue
					_check(obj[field_name], field_spec, file_label, "%s.%s" % [where, field_name])
				if not GameData.as_bool(spec.get("open")):
					for key: Variant in obj:
						if not fields.has(str(key)):
							_err("E_UNKNOWN_KEY", file_label, "%s.%s" % [where, str(key)], "unknown key")
		"color":
			if not value is String or not _is_color(str(value)):
				_err("E_TYPE", file_label, where, "must be a colour written #RRGGBB")
		"vec3":
			var ok: bool = false
			if value is Array:
				var arr: Array = value
				ok = arr.size() == 3 and GameData.is_number(arr[0]) and GameData.is_number(arr[1]) and GameData.is_number(arr[2])
			if not ok:
				_err("E_TYPE", file_label, where, "must be [x, y, z]")
		"res":
			if not value is String:
				_err("E_TYPE", file_label, where, "must be a res:// path or null")
			elif not ResourceLoader.exists(str(value)) and not FileAccess.file_exists(str(value)):
				_err("E_REF", file_label, where, "file '%s' does not exist" % str(value))
		"clock":
			var valid: bool = false
			if value is String:
				var parts: PackedStringArray = str(value).split(":")
				if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
					var hours: int = parts[0].to_int()
					var minutes: int = parts[1].to_int()
					valid = hours >= 0 and hours <= 23 and minutes >= 0 and minutes <= 59
			if not valid:
				_err("E_TYPE", file_label, where, "must be a clock time written HH:MM")
		_:
			_err("E_TYPE", file_label, where, "validator bug: unknown schema type '%s'" % type_name)


func _check_range(number: float, spec: Dictionary, file_label: String, where: String) -> void:
	var minimum: float = GameData.as_float(spec.get("min"), -INF)
	var maximum: float = GameData.as_float(spec.get("max"), INF)
	if number < minimum or number > maximum:
		_err("E_RANGE", file_label, where, "%s is outside %s to %s" % [str(number), str(minimum), str(maximum)])


func _exists(target: String, id: String) -> bool:
	if GameData.RECORD_SETS.has(target):
		return _data.has_record(target, id)
	match target:
		"lines":
			return _data.has_line(id, "en")
		"line_prefix":
			var prefix: String = id + "."
			for line_id: String in _data.line_ids("en"):
				if line_id.begins_with(prefix):
					return true
			return false
		"tuning":
			return _data.tuning.has(id)
		"sfx", "placeholders":
			return _data.root(target).has(id)
	return false


func _is_color(text: String) -> bool:
	if text.length() != 7 or not text.begins_with("#"):
		return false
	return text.substr(1).is_valid_hex_number(false)


func _has_load_error_for(file: String) -> bool:
	var needle: String = "/%s.json" % file
	for message: String in _data.errors:
		if message.contains(needle):
			return true
	return false


func _err(code: String, file_label: String, where: String, problem: String) -> void:
	if where.is_empty():
		errors.append("[%s] %s: %s" % [code, file_label, problem])
	else:
		errors.append("[%s] %s: %s: %s" % [code, file_label, where, problem])
