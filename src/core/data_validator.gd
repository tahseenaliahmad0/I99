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
const GESTURES: PackedStringArray = ["TAP", "HOLD", "FLICK", "DRAG", "DRAG_TO", "CRANK", "BEAD", "GATE"]
## A ritual's anchor may follow its item: "@slot" is wherever the item sits.
const SLOT_ANCHOR: String = "@slot"
## What a completed ritual may do (ItemSim runs these), "op" or "op:arg:arg".
const RITUAL_OPS: PackedStringArray = [
	"nerves", "cash", "add_effect", "remove_effect", "consume_supply", "give", "toggle",
	"horn", "wipe", "photo", "indicate", "window", "ash", "radio_step", "sfx", "line", "pay",
	"clear_haze", "flip", "answer", "refill", "hook", "call", "key", "hand", "stow", "unstow", "ask",
]
## The five passengers of GDD 8.2, what a passenger's Hand can be, and what
## a Weight can weigh on.
const PASSENGER_IDS: PackedStringArray = ["hajjiya", "conscript", "drummer", "student", "apprentice"]
const PASSENGER_HANDS: PackedStringArray = ["hold_wheel_straight", "hold_wheel", "cigarette", "pass_tea", "always"]
const WEIGHT_RESOURCES: PackedStringArray = ["nerves", "suspicion"]
## When a Weight bites. "ritual_tag:<tag>" (he uses a thing so tagged) and
## "gear>=<n>" (alone, or with "&rain") are checked apart from these.
const WEIGHT_WHENS: PackedStringArray = ["asleep", "scrape", "drumming&patrol"]
## The lines every passenger has (GDD 3.6).
const PASSENGER_LINES: PackedStringArray = ["name", "board", "leave"]
## What can be handed out of the driver's window (GDD 10.2).
const DOCUMENTS: PackedStringArray = ["licence", "id", "registration"]
const BANKNOTES: String = "banknotes"
## A DRAG_TO's destination: any free slot the thing carried fits in.
const HOME_ANCHOR: String = "@home"
## How the Call is taken at the pocket (GDD 10.4).
const CALL_WAYS: PackedStringArray = ["alone", "passenger"]
## Cabin switches a "toggle:" op may flip and a "flag:" condition may read.
const CABIN_FLAGS: PackedStringArray = ["hazards", "high_beam", "window_open", "glovebox_open", "passenger", "letter_aside"]
## Conditions that are not effect ids.
const CONDITION_WORDS: PackedStringArray = ["supply>0", "hot", "playing", "warbling", "ringing", "glovebox_room", "stowed"]
## Sources of Nerves a status can make him immune to (GDD 7.4, the seeds).
const NERVE_SOURCES: PackedStringArray = ["honk", "tailgater", "doubt"]
const REACHES: PackedStringArray = ["near", "mid", "far", "none"]
## Lanes a beat may name: relative to the lane the player is expected in.
const BEAT_LANES: PackedStringArray = ["player", "left_of_player", "right_of_player", "shoulder", "oncoming"]
const HAZARD_CLASSES: PackedStringArray = ["soft", "pothole"]
const LEG_CONDITIONS: PackedStringArray = ["clear", "rain", "night"]
const SPECIAL_KINDS: PackedStringArray = ["roadworks", "tailgater", "patrol", "two_lane", "motorcade"]
## The three set pieces that end the acts (GDD 10.2 to 10.4).
const BOSS_IDS: PackedStringArray = ["checkpoint", "storm", "dawn"]
## Content rows of GDD Part II that must exist as data (GDD 1.1), per record set.
const REQUIRED_RECORDS: Dictionary = {
	"legs": ["open_road", "rush", "rain", "night", "roadworks", "tailgater", "patrol", "two_lane", "motorcade"],
	"modifiers": ["crosswind", "potholes", "sheep", "wedding", "melon_truck", "dust_haze"],
	"vehicles": ["car", "taxi", "pickup", "minibus", "truck", "tanker", "tuk_tuk"],
	"faults": ["rattle", "cracked_windscreen", "dead_headlight", "pulling_steering", "slipping_clutch", "stuck_wiper", "cracked_mirror"],
	"stops": ["fuel_station", "fitter", "tea_stall", "roadside_find", "hitcher", "shady_guy", "boss_stop"],
	"bosses": ["checkpoint", "storm", "dawn"],
	"boss_modifiers": ["long_queue", "thorough", "crosswind", "night_storm", "market_day", "early_sun"],
	# The controls that are always in the car (GDD 4.6) and that the code names.
	"anchors": ["gear_lever", "horn", "wiper_stalk", "indicator_stalk", "headlight_knob", "hazard_button", "radio", "window_crank", "glovebox", "visor", "face"],
}
const BEAT_TYPES: PackedStringArray = ["CALM", "CLUSTER", "SLOWPOKE", "MERGE", "CURVE", "GUST", "HAZARD", "SPECIAL"]
const STOP_SERVICES: PackedStringArray = ["shop", "repair", "tea", "find", "passenger", "deals", "boss"]
## The stops of GDD 9.6 and the names GDD 15 gives their minutes and weights.
const STOP_TUNING_KEYS: Dictionary = {
	"fuel_station": "fuel", "fitter": "fitter", "tea_stall": "tea",
	"roadside_find": "find", "hitcher": "hitcher", "shady_guy": "shady",
}
const HECKLE_TYPES: PackedStringArray = ["TWIST", "DARE", "DOUBT", "QUESTION", "ORDER", "FIB"]
const FLICK_DIRS: PackedStringArray = ["up", "down", "left", "right"]
## What a ritual may block of the view while it is performed (GDD 7.4).
const VIEW_BLOCKS: PackedStringArray = ["lower_centre"]
const PLACEHOLDER_SHAPES: PackedStringArray = ["box", "cylinder", "capsule", "sphere", "quad", "label"]
const REQUIRED_POINTS: PackedStringArray = ["G", "W", "eye", "shoulder", "ear"]

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
	_check_record_set("effects", _effect_schema())
	_check_record_set("slots", _slot_schema())
	_check_record_set("vehicles", _vehicle_schema())
	_check_record_set("hazard_kinds", _hazard_kind_schema())
	_check_record_set("faults", _fault_schema())
	_check_record_set("rituals", _ritual_schema())
	_check_record_set("items", _item_schema())
	_check_record_set("modifiers", _modifier_schema())
	_check_record_set("beats", _beat_schema())
	_check_record_set("legs", _leg_schema())
	_check_record_set("boss_modifiers", _boss_modifier_schema())
	_check_record_set("bosses", _boss_schema())
	_check_bosses()
	_check_record_set("stops", _stop_schema())
	_check_stops()
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


## A number greater than `minimum`: for what the code divides by.
static func _above(minimum: float = 0.0) -> Dictionary:
	return {"t": "num", "min": minimum, "max": INF, "open": true}


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
		# An item that is for one boss is sold only while that boss is ahead.
		"until_boss": _opt(_ref("bosses")),
		"supply": _opt(_nullable(_obj({"uses": _int(0.0), "restock": _num(0.0)}))),
		"rituals": _list(_ref("rituals")),
		"gives": _list(_obj({}, true)),
		"takes": _list(_obj({}, true)),
		"lapse": _opt(_nullable(_obj({}, true))),
		"synergies": _opt(_list(_obj({"with": _str(), "rule": _str(), "amount": _opt(_num())}, true))),
		"params": _opt(_map(_t("any"))),
		"line_ids": _map(_ref("lines")),
	})


func _effect_schema() -> Dictionary:
	return _obj({
		"id": _str(),
		"max_stacks": _opt(_int(1.0)),
		"implies": _opt(_list(_ref("effects"))),
		# Sources of Nerves he does not feel while the status is on.
		"immune": _opt(_list(_enum(NERVE_SOURCES))),
		# Numbers a status carries while it is on (EffectSystem.product, total).
		"road_speed": _opt(_num(0.1, 1.0)),
		"tremor_scale": _opt(_num(0.0)),
		"heavy_floor": _opt(_num()),
		"mutes_phantom": _opt(_bool()),
		"hides_courage": _opt(_bool()),
		"close_call_cash_per_stack": _opt(_num()),
		"nerves_gain_per_stack": _opt(_num()),
	})


func _ritual_schema() -> Dictionary:
	return _obj({
		"id": _str(),
		"anchor": _str(),
		"item": _opt(_ref("items")),
		# A ritual at "@slot" that several items list (stowing): it has no
		# item of its own.
		"shared": _opt(_bool()),
		"gesture": _enum(GESTURES),
		"hold_s": _opt(_num(0.0)),
		"flick_dirs": _opt(_list(_enum(FLICK_DIRS), 1)),
		"turns": _opt(_num(0.0)),
		# A DRAG_TO's destination: an anchor, or "@slot" for back where it was
		# taken from. `out_m`: how far it must be carried from there first.
		# `across_m`: how far sideways; with no "to", it is let go anywhere.
		"to": _opt(_str()),
		"out_m": _opt(_above()),
		"across_m": _opt(_above()),
		# What a practised player takes (GDD 7.4), for the bot.
		"perform_s": _opt(_above()),
		"over_items": _opt(_bool()),
		"eyes_down": _bool(),
		"blocks_view": _opt(_nullable(_enum(VIEW_BLOCKS))),
		"requires": _list(_str()),
		"on_complete": _list(_str()),
		"on_step": _opt(_list(_str())),
		"sfx": _opt(_nullable(_ref("sfx"))),
	}, true)


func _leg_schema() -> Dictionary:
	return _obj({
		"id": _str(),
		"acts": _list(_int(1.0, 3.0), 1),
		"lanes": _int(1.0, 3.0),
		"divided": _bool(),
		"density": _num(0.0),
		"condition": _enum(LEG_CONDITIONS),
		"par_s": _num(0.0),
		"beat_weights": _map_keyed(_enum(BEAT_TYPES), _num(0.0)),
		"calm_adjacent": _opt(_bool()),
		"special": _opt(_nullable(_obj({"kind": _enum(SPECIAL_KINDS)}, true))),
		"modifiers_allowed": _list(_ref("modifiers")),
	})


func _beat_schema() -> Dictionary:
	return _obj({
		"id": _str(),
		"type": _enum(BEAT_TYPES),
		"length_m": _t("any"),
		"min_lanes": _opt(_int(1.0, 3.0)),
		"acts": _opt(_list(_int(1.0, 3.0), 1)),
		"spawns": _opt(_list(_obj({
			"vehicle": _ref("vehicles"),
			"lane": _enum(BEAT_LANES),
			"s_offset": _num(),
			"speed_kmh": _num(0.0),
			"lane_change": _opt(_obj({"to": _enum(BEAT_LANES), "at_s_offset": _num()})),
		}))),
		"hazards": _opt(_list(_obj({
			"kind": _ref("hazard_kinds"),
			"lane": _enum(BEAT_LANES),
			"s_offset": _num(),
			"x_offset": _opt(_num()),
		}))),
		"curve": _opt(_obj({"k_index": _int(0.0, 2.0), "dir": _enum(PackedStringArray(["left", "right"]))})),
		"gust": _opt(_obj({"dir": _enum(PackedStringArray(["left", "right"]))})),
	})


func _vehicle_schema() -> Dictionary:
	return _obj({
		"id": _str(),
		"width": _num(0.1),
		"length": _num(0.1),
		"speed_kmh": _list_n(_num(0.0), 2),
		"yields_to_horn": _bool(),
		"honk_nerves": _num(0.0),
		"acts": _list(_int(1.0, 3.0), 1),
		"placeholder": _ref("placeholders"),
		"traffic": _opt(_bool()),
	})


func _hazard_kind_schema() -> Dictionary:
	return _obj({
		"id": _str(),
		"class": _enum(HAZARD_CLASSES),
		"width": _num(0.05),
		"length": _num(0.05),
		"nerves": _num(0.0),
		"suspicion": _opt(_num(0.0)),
		"speed_loss": _opt(_num(0.0, 1.0)),
		"placeholder": _ref("placeholders"),
	})


func _modifier_schema() -> Dictionary:
	return _obj({"id": _str(), "line_ids": _opt(_map(_ref("lines")))}, true)


func _stop_schema() -> Dictionary:
	return _obj({
		"id": _str(),
		"service": _enum(STOP_SERVICES),
		"stock": _opt(_nullable(_obj({"count": _int(0.0), "pools": _list(_enum(ITEM_KINDS)), "free": _opt(_int(0.0))}))),
		"restocks": _opt(_bool()),
		# A hitcher stands there: always, or at hitcher_chance of such stops (GDD 8.1).
		"hitcher": _opt(_enum(PackedStringArray(["always", "sometimes"]))),
		"nerves_to": _opt(_num(0.0, 100.0)),
		"clock_min": _num(0.0),
		"weight": _num(0.0),
		"line_ids": _opt(_map(_ref("lines"))),
	})


func _boss_schema() -> Dictionary:
	return _obj({
		"id": _str(),
		"act": _int(1.0, 3.0),
		"length_m": _above(0.0),
		"par_s": _above(0.0),
		"lanes": _int(1.0, 3.0),
		"divided": _bool(),
		"modifiers": _list(_ref("boss_modifiers")),
		"checkpoint": _opt(_checkpoint_schema()),
		"storm": _opt(_storm_schema()),
		"dawn": _opt(_dawn_schema()),
		"line_ids": _opt(_map(_ref("lines"))),
	})


## The Storm's numbers (GDD 10.3).
func _storm_schema() -> Dictionary:
	return _obj({
		"thin_s": _above(0.0),
		"thin_m": _above(0.0),
		"thick_s": _above(0.0),
		"thick_m": _above(0.0),
		"gust_push": _num(0.0),
		"gust_every_s": _above(0.0),
		"wipe_haze": _num(0.0, 1.0),
		"window_haze_per_s": _num(0.0, 1.0),
		"stopped_kmh": _num(0.0),
		"moved_off_kmh": _above(0.0),
		"rear_end_every_s": _above(0.0),
		"rear_end_tell_s": _num(0.0),
		"rear_end_chance": _num(0.0, 1.0),
		"tail_lights": _obj({
			"first_m": _num(0.0),
			"gap_m": _list_n(_above(0.0), 2),
			"speed_kmh": _list_n(_above(0.0), 2),
			"vehicles": _list(_ref("vehicles"), 1),
		}),
	})


## The Checkpoint's numbers (GDD 10.2).
func _checkpoint_schema() -> Dictionary:
	return _obj({
		"corridor": _corridor_schema({"sign_lead_s": _num(0.0)}),
		"barrier_suspicion": _num(0.0),
		"queue": _obj({
			"cars": _int(0.0),
			"gap_m": _above(0.0),
			"creep_kmh": _above(0.0),
			"pull_up_per_s": _above(0.0),
			"settle_m": _above(0.0),
			"serve_s": _above(0.0),
			"leave_kmh": _above(0.0),
			"clear_m": _num(0.0),
			"vehicles": _list(_ref("vehicles"), 1),
		}),
		"stop_zone_m": _above(0.0),
		"stopped_kmh": _num(0.0),
		"bump_kmh": _num(0.0),
		"stow_s": _above(0.0),
		"contraband_suspicion": _num(0.0),
		"courage_suspicion": _num(0.0),
		"documents": _list(_enum(DOCUMENTS), 1),
		"delay_every_s": _above(0.0),
		"delay_suspicion": _num(0.0),
		"pass_under": _num(0.0),
		"turned_back_at": _num(0.0),
		"search_minutes": _num(0.0),
		"turned_back_minutes": _num(0.0),
	})


## Dawn's numbers (GDD 10.4).
func _dawn_schema() -> Dictionary:
	return _obj({
		"heavy_floor": _num(0.0),
		"sunrise_at_m": _above(0.0),
		"glare": _num(0.0, 1.0),
		"glare_ramp_m": _above(0.0),
		# Where across his view the sun and the false dawn's glow are: -1 is
		# the far left, 0 dead ahead, 1 the far right.
		"sun_side": _num(-1.0, 1.0),
		"glow_side": _num(-1.0, 1.0),
		"road": _obj({
			"density": _num(0.0),
			"tail_m": _num(0.0),
			"builds_from": _num(0.0, 1.0),
			"beat_weights": _map_keyed(_enum(BEAT_TYPES), _num(0.0)),
		}),
		"checkpoint": _corridor_schema({"max_kmh": _above(0.0), "sign_lead_s": _num(0.0), "search_minutes": _num(0.0)}),
		"call": _obj({
			"from_end_m": _above(0.0),
			"ring_s": _above(0.0),
			"talk_s": _above(0.0),
			"wrist_steer": _num(0.0, 1.0),
			"stopped_kmh": _num(0.0),
		}),
	})


## A checkpoint's corridor between barriers (GDD 10.2, 10.4), with what else
## the checkpoint needs.
func _corridor_schema(more: Dictionary) -> Dictionary:
	var fields: Dictionary = {
		"at_m": _above(0.0),
		"length_m": _above(0.0),
		"taper_m": _above(0.0),
		"gap_m": _above(0.0),
	}
	fields.merge(more)
	return _obj(fields)


## The street of the Arrival (GDD 10.5).
func _arrival_schema() -> Dictionary:
	return _obj({
		"length_m": _above(0.0),
		"lanes": _int(1.0, 3.0),
		"divided": _bool(),
		"heavy_floor": _num(0.0),
		"bay_m": _above(0.0),
		"stopped_kmh": _num(0.0),
		"bump_kmh": _num(0.0),
	})


## What a boss's modifier changes (GDD 10.2 to 10.4): one number, for the
## boss it names.
func _boss_modifier_schema() -> Dictionary:
	return _obj({
		"id": _str(),
		"boss": _enum(BOSS_IDS),
		"queue_mult": _opt(_above(0.0)),
		"documents": _opt(_int(1.0, 3.0)),
		"gust_mult": _opt(_above(0.0)),
		"night": _opt(_bool()),
		"traffic_mult": _opt(_above(0.0)),
		"glare_from_phase": _opt(_int(1.0, 3.0)),
		"line_ids": _opt(_map(_ref("lines"))),
	})


## A tuning constant for a rule that spans files: `fallback` where the
## constant is missing or is no number (that is reported where tuning.json
## itself is checked; the rule then has nothing to compare with).
func _tuning_number(name: String, fallback: float) -> float:
	if _data.tuning.has(name) and GameData.is_number(_data.tuning.raw(name)):
		return GameData.as_float(_data.tuning.raw(name))
	return fallback


## A boss lists its own modifiers, and has the numbers of its set piece.
func _check_bosses() -> void:
	if _data.roots.has("legs"):
		var street: Variant = _data.root("legs").get("arrival")
		if street == null:
			_err("E_MISSING", "legs.json", "arrival", "the street of the Arrival is missing (GDD 10.5)")
		else:
			_check(street, _arrival_schema(), "legs.json", "arrival")
			var arrival: Dictionary = GameData.as_dict(street)
			if GameData.is_number(arrival.get("bay_m")) and GameData.is_number(arrival.get("length_m")) \
					and (GameData.as_float(arrival.get("bay_m")) < _tuning_number("car_length", 0.0) or GameData.as_float(arrival.get("bay_m")) > GameData.as_float(arrival.get("length_m"))):
				_err("E_RANGE", "legs.json", "arrival.bay_m", "the bay must hold the car and fit in the street")
	for boss: Dictionary in _data.records("bosses"):
		var id: String = GameData.as_string(boss.get("id"))
		var label: String = "bosses[%s]" % id
		for listed: Variant in GameData.as_array(boss.get("modifiers")):
			var modifier_id: String = GameData.as_string(listed)
			if _data.has_record("boss_modifiers", modifier_id) \
					and GameData.as_string(_data.record("boss_modifiers", modifier_id).get("boss")) != id:
				_err("E_RULE", "legs.json", "%s.modifiers" % label, "'%s' is a modifier of another boss" % modifier_id)
		if id == "storm" and not boss.has("storm"):
			_err("E_MISSING", "legs.json", "%s.storm" % label, "the Storm needs its numbers")
		if id == "dawn" and not boss.has("dawn"):
			_err("E_MISSING", "legs.json", "%s.dawn" % label, "Dawn needs its numbers")
		if id == "checkpoint" and not boss.has("checkpoint"):
			_err("E_MISSING", "legs.json", "%s.checkpoint" % label, "the Checkpoint needs its numbers")
		var storm: Dictionary = GameData.as_dict(boss.get("storm"))
		if GameData.is_number(storm.get("moved_off_kmh")) and GameData.is_number(storm.get("stopped_kmh")):
			if GameData.as_float(storm.get("moved_off_kmh")) <= GameData.as_float(storm.get("stopped_kmh")):
				_err("E_RANGE", "legs.json", "%s.storm.moved_off_kmh" % label, "must be above stopped_kmh: driving off is more than rolling")
			# The horn behind him is a tell he can act on (GDD 2.2, pillar 4).
			if GameData.as_float(storm.get("moved_off_kmh")) / maxf(_tuning_number("accel", 1.0), 0.001) >= GameData.as_float(storm.get("rear_end_tell_s")):
				_err("E_RANGE", "legs.json", "%s.storm.rear_end_tell_s" % label, "must leave time to reach moved_off_kmh from rest")
		var checkpoint: Dictionary = GameData.as_dict(boss.get("checkpoint"))
		if not checkpoint.is_empty():
			var corridor: Dictionary = GameData.as_dict(checkpoint.get("corridor"))
			var queue: Dictionary = GameData.as_dict(checkpoint.get("queue"))
			if GameData.is_number(corridor.get("at_m")) and GameData.is_number(corridor.get("length_m")):
				# The taper begins on the road and the bar stands short of its end.
				if GameData.as_float(corridor.get("at_m")) - GameData.as_float(corridor.get("taper_m")) < 0.0 \
						or GameData.as_float(corridor.get("at_m")) + GameData.as_float(corridor.get("length_m")) >= GameData.as_float(boss.get("length_m")):
					_err("E_RANGE", "legs.json", "%s.checkpoint.corridor" % label, "the corridor and its taper must lie on the Checkpoint's road, with road left after the bar")
				if GameData.as_float(corridor.get("gap_m")) <= _tuning_number("car_width", 0.0) or GameData.as_float(corridor.get("gap_m")) > _tuning_number("lane_width", INF):
					_err("E_RANGE", "legs.json", "%s.checkpoint.corridor.gap_m" % label, "must be wider than the car and no wider than a lane")
				# The longest queue of the longest vehicles must fit in the corridor.
				var longest: float = 0.0
				for type: Variant in GameData.as_array(queue.get("vehicles")):
					if _data.has_record("vehicles", GameData.as_string(type)):
						longest = maxf(longest, GameData.as_float(_data.record("vehicles", GameData.as_string(type)).get("length")))
				var most: float = GameData.as_float(queue.get("cars"))
				for listed: Variant in GameData.as_array(boss.get("modifiers")):
					if _data.has_record("boss_modifiers", GameData.as_string(listed)):
						most = maxf(most, GameData.as_float(queue.get("cars")) * GameData.as_float(_data.record("boss_modifiers", GameData.as_string(listed)).get("queue_mult"), 1.0))
				if roundf(most) * (longest + GameData.as_float(queue.get("gap_m"))) > GameData.as_float(corridor.get("length_m")):
					_err("E_RANGE", "legs.json", "%s.checkpoint.queue.cars" % label, "the queue at its longest does not fit between the barriers")
			if GameData.is_number(checkpoint.get("pass_under")) and GameData.is_number(checkpoint.get("turned_back_at")) \
					and GameData.as_float(checkpoint.get("pass_under")) > GameData.as_float(checkpoint.get("turned_back_at")):
				_err("E_RANGE", "legs.json", "%s.checkpoint.pass_under" % label, "must not be above turned_back_at")
			var seen: Dictionary = {}
			for document: Variant in GameData.as_array(checkpoint.get("documents")):
				if seen.has(document):
					_err("E_DUP_ID", "legs.json", "%s.checkpoint.documents" % label, "'%s' is listed twice" % GameData.as_string(document))
				seen[document] = true
		var dawn: Dictionary = GameData.as_dict(boss.get("dawn"))
		var length: float = GameData.as_float(boss.get("length_m"))
		var check: Dictionary = GameData.as_dict(dawn.get("checkpoint"))
		var call: Dictionary = GameData.as_dict(dawn.get("call"))
		if not dawn.is_empty() and GameData.is_number(check.get("at_m")) and GameData.is_number(call.get("from_end_m")):
			# False dawn, then sunrise with the last checkpoint in it, then the Call.
			var sunrise: float = GameData.as_float(dawn.get("sunrise_at_m"))
			var corridor_from: float = GameData.as_float(check.get("at_m")) - GameData.as_float(check.get("taper_m"))
			var corridor_to: float = GameData.as_float(check.get("at_m")) + GameData.as_float(check.get("length_m"))
			var call_at: float = length - GameData.as_float(call.get("from_end_m"))
			if not (sunrise < corridor_from and corridor_to < call_at and call_at < length):
				_err("E_RULE", "legs.json", "%s.dawn" % label, "the order along the road must be: sunrise, the last checkpoint, the Call, the end")
			if GameData.as_float(check.get("gap_m")) <= _tuning_number("car_width", 0.0) or GameData.as_float(check.get("gap_m")) > _tuning_number("lane_width", INF):
				_err("E_RANGE", "legs.json", "%s.dawn.checkpoint.gap_m" % label, "must be wider than the car and no wider than a lane")
		var gaps: Array = GameData.as_array(GameData.as_dict(storm.get("tail_lights")).get("gap_m"))
		if gaps.size() == 2 and GameData.as_float(gaps[0]) > GameData.as_float(gaps[1]):
			_err("E_RANGE", "legs.json", "%s.storm.tail_lights.gap_m" % label, "must be [least, most]")
		var speeds: Array = GameData.as_array(GameData.as_dict(storm.get("tail_lights")).get("speed_kmh"))
		if speeds.size() == 2 and GameData.as_float(speeds[0]) > GameData.as_float(speeds[1]):
			_err("E_RANGE", "legs.json", "%s.storm.tail_lights.speed_kmh" % label, "must be [least, most]")


## A stop's minutes and weight are those GDD 15 gives (tuning stop_minutes and
## stop_weights): the two tables may not drift apart.
func _check_stops() -> void:
	if not _data.tuning.has("stop_minutes") or not _data.tuning.has("stop_weights"):
		return
	var minutes: Dictionary = _data.tuning.d("stop_minutes")
	var weights: Dictionary = _data.tuning.d("stop_weights")
	for stop: Dictionary in _data.records("stops"):
		var id: String = GameData.as_string(stop.get("id"))
		if not STOP_TUNING_KEYS.has(id):
			continue
		var key: String = STOP_TUNING_KEYS[id]
		if minutes.has(key) and GameData.is_number(stop.get("clock_min")) \
				and not is_equal_approx(GameData.as_float(stop.get("clock_min")), GameData.as_float(minutes[key])):
			_err("E_RULE", "stops.json", "stops[%s].clock_min" % id, "must equal stop_minutes.%s in tuning.json (GDD 15)" % key)
		if weights.has(key) and GameData.is_number(stop.get("weight")) \
				and not is_equal_approx(GameData.as_float(stop.get("weight")), GameData.as_float(weights[key])):
			_err("E_RULE", "stops.json", "stops[%s].weight" % id, "must equal stop_weights.%s in tuning.json (GDD 15)" % key)
	# One boss for each act.
	var acts: Dictionary = {}
	for boss: Dictionary in _data.records("bosses"):
		var act: int = GameData.as_int(boss.get("act"))
		if acts.has(act):
			_err("E_RULE", "legs.json", "bosses[%s].act" % GameData.as_string(boss.get("id")), "act %d already has a boss" % act)
		acts[act] = true


func _passenger_schema() -> Dictionary:
	var effects: Dictionary = _opt(_list(_ref("effects")))
	return _obj({
		"id": _str(),
		"rides_legs": _opt(_int(1.0)),
		"rides_until": _opt(_enum(PackedStringArray(["act_end", "basra"]))),
		"fare": _num(0.0),
		# What they do when asked with a TAP on the shoulder (GDD 8.1).
		"hand": _obj({
			"kind": _enum(PASSENGER_HANDS),
			"on": _opt(_enum(PackedStringArray(["tap", "always"]))),
			"duration_s": _opt(_num(0.0)),
			# Where a thing that is passed to him is held, in the cabin frame.
			"at": _opt(_t("vec3")),
		}),
		# What they do all the time they ride.
		"always": _opt(_obj({
			"suspicion_gain_mult": _opt(_num(0.0, 1.0)),
			"fork_sign_lead_s": _opt(_num(0.0)),
			"answers_calls": _opt(_bool()),
			"effects": effects,
		})),
		"sleeps": _opt(_obj({"awake_s": _num(0.0), "horn_wakes": _bool()})),
		"drums": _opt(_obj({"effects": effects})),
		"repairs": _opt(_obj({"per_leg": _int(1.0), "announce_s": _num(0.0), "lean_s": _num(0.0)})),
		"retunes": _opt(_obj({"every_s": _num(0.0), "to": _str()})),
		"view_block_right": _opt(_num(0.0, 1.0)),
		"weights": _list(_obj({
			"when": _str(),
			"resource": _enum(WEIGHT_RESOURCES),
			"amount": _opt(_num()),
			"per_s": _opt(_num()),
		})),
		"on_leave": _opt(_list(_str())),
		"line_prefix": _ref("line_prefix"),
	})


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
	return _obj({
		"id": _str(),
		"anchor": _opt(_nullable(_ref("anchors"))),
		"reach": _opt(_enum(REACHES)),
		"holds": _opt(_list(_str())),
	})


func _anchor_schema() -> Dictionary:
	return _obj({
		"id": _str(),
		"pos": _t("vec3"),
		"time_s": _num(0.0),
		"via_w": _opt(_bool()),
		"placeholder": _opt(_nullable(_ref("placeholders"))),
		# Where its marker is drawn, relative to the anchor: for an anchor
		# that lies inside a prop (the horn in the hub, the glovebox in the dash).
		"marker_offset": _opt(_t("vec3")),
		# The anchor whose place this one takes while something sits here (the
		# tape deck is the radio: GDD 16.2 gives both one position).
		"over": _opt(_ref("anchors")),
	})


func _prop_schema() -> Dictionary:
	# A prop may show a cabin switch: it is drawn only while every one of its
	# `flags` is as written ("!" before a switch that must be off), and with
	# `blink` it comes and goes at the indicators' rate. `alpha` makes it
	# see-through (glass).
	var switches: PackedStringArray = PackedStringArray()
	for flag: String in CABIN_FLAGS:
		switches.append(flag)
		switches.append("!" + flag)
	return _obj({
		"id": _str(),
		"placeholder": _ref("placeholders"),
		"pos": _t("vec3"),
		"rot": _opt(_t("vec3")),
		"flags": _opt(_list(_enum(switches))),
		"blink": _opt(_bool()),
		"alpha": _opt(_num(0.0, 1.0)),
	})


## Something fitted to the car that the cabin shows while its item is there.
func _fitting_schema() -> Dictionary:
	return _obj({
		"id": _str(),
		"item": _ref("items"),
		"placeholder": _ref("placeholders"),
		"pos": _t("vec3"),
		# It sits on the wheel and turns with it.
		"on_wheel": _opt(_bool()),
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
	# What the code divides by, or takes as a rate: never zero.
	var above: Dictionary = _above(0.0)
	return {
		# Hand and wheel
		"hand_speed": above, "hand_left_side_mult": pos, "hand_pound_mult": pos,
		"anchor_snap_radius": pos, "input_buffer": pos, "grip_zone_half_width": pos,
		"wheel_max_angle": above, "steer_deg_per_px": pos, "wheel_smoothing": pos,
		"wheel_return_rate": pos, "gate_unit": above, "gate_channel_half_width": pos,
		"glance_start": pos, "glance_gain": pos, "glance_max_yaw": pos,
		"glance_max_pitch": pos, "eyes_down_pitch": pos,
		# The hand, the pointer, gestures and the gate as built (M1)
		"hand_plane_distance": above, "hand_free_bounds_min": _list_n(n, 2), "hand_free_bounds_max": _list_n(n, 2),
		"hand_arrive_epsilon": above, "wheel_radius": above, "glance_smoothing": pos,
		"camera_fov": _num(1.0, 179.0), "reference_width": above, "reference_height": above,
		"pointer_yaw_min": n, "pointer_yaw_max": n, "pointer_pitch_min": n, "pointer_pitch_max": n,
		"tap_max_time": above, "flick_min_distance": above, "flick_max_time": above,
		"bead_max_rate": above, "crank_min_step": above,
		"gate_engage_radius": above, "gate_grind_min": pos, "gate_grind_max": pos,
		"gate_wall_push": pos, "gate_grind_nerves": pos, "gate_grind_lock": pos,
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
		# The road between legs (M5)
		"exit_slip_length": above, "missed_exit_nerves": pos, "stop_leave_grip": pos,
		"fork_sign_lead": pos,
		# Bosses (M7)
		"boss_modifier_chance": _list_n(_num(0.0, 1.0), 3),
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
		# Whoever speaks has a name the subtitles can show, and a writer can
		# translate, once: a line of its own (GDD 16.6, 17.3).
		for speaker: String in GameData.speakers_of(GameData.as_string(entry.get("speaker"))):
			var name_id: String = GameData.speaker_line_id(speaker)
			if not name_id.is_empty() and not _data.has_line(name_id, "en"):
				_err("E_REF", "lines_en.csv", id, "speaker '%s' has no line '%s' for the name" % [speaker, name_id])
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
	_check_record_set("props", _prop_schema())
	_check_record_set("fittings", _fitting_schema())


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
	_check_required_records()
	_check_beats()
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
		var label: String = "passengers[%s]" % GameData.as_string(passenger.get("id"), "?")
		if has_legs == has_until:
			_err("E_RULE", "passengers.json", label, "needs exactly one of rides_legs and rides_until")
		_check_passenger(passenger, label)
	for required: String in PASSENGER_IDS:
		if _data.roots.has("passengers") and not _data.has_record("passengers", required):
			_err("E_MISSING", "passengers.json", "passengers[%s]" % required, "required record is missing (GDD 8.2)")
	for ritual: Dictionary in _data.records("rituals"):
		var ritual_label: String = "rituals[%s]" % GameData.as_string(ritual.get("id"), "?")
		var anchor: String = GameData.as_string(ritual.get("anchor"))
		if anchor == SLOT_ANCHOR:
			if not ritual.has("item") and not GameData.as_bool(ritual.get("shared")):
				_err("E_RULE", "rituals.json", ritual_label, "a ritual at \"@slot\" needs the \"item\" it belongs to")
			if ritual.has("item") and GameData.as_bool(ritual.get("shared")):
				_err("E_RULE", "rituals.json", ritual_label, "a shared ritual belongs to every item that lists it: it names no \"item\"")
		elif ritual.has("anchor") and ritual["anchor"] is String and not _data.has_record("anchors", anchor):
			_err("E_REF", "rituals.json", ritual_label + ".anchor", "unknown anchors id '%s'" % anchor)
		for key: String in ["on_complete", "on_step"]:
			var ops: Array = GameData.as_array(ritual.get(key))
			for index: int in ops.size():
				_check_op(GameData.as_string(ops[index]), "rituals.json", "%s.%s[%d]" % [ritual_label, key, index])
		var conditions: Array = GameData.as_array(ritual.get("requires"))
		for index: int in conditions.size():
			_check_condition(GameData.as_string(conditions[index]), "rituals.json", "%s.requires[%d]" % [ritual_label, index])
		var needs: String = ""
		match GameData.as_string(ritual.get("gesture")):
			"HOLD":
				needs = "hold_s"
			"FLICK":
				needs = "flick_dirs"
			"CRANK":
				needs = "turns"
			"DRAG_TO":
				if not ritual.has("across_m"):
					needs = "to"
		var to: String = GameData.as_string(ritual.get("to"))
		if ritual.has("to") and ritual["to"] is String and to != SLOT_ANCHOR and to != HOME_ANCHOR and not _data.has_record("anchors", to):
			_err("E_REF", "rituals.json", ritual_label + ".to", "unknown anchors id '%s'" % to)
		if to == SLOT_ANCHOR and anchor != SLOT_ANCHOR:
			_err("E_RULE", "rituals.json", ritual_label + ".to", "\"@slot\" is where an item's own ritual began: the ritual must be at \"@slot\" too")
		if not needs.is_empty() and not ritual.has(needs):
			_err("E_RULE", "rituals.json", "rituals[%s]" % GameData.as_string(ritual.get("id"), "?"),
					"a %s ritual needs \"%s\"" % [GameData.as_string(ritual.get("gesture")), needs])
	for passenger: Dictionary in _data.records("passengers"):
		var leave_ops: Array = GameData.as_array(passenger.get("on_leave"))
		for index: int in leave_ops.size():
			_check_op(GameData.as_string(leave_ops[index]), "passengers.json",
					"passengers[%s].on_leave[%d]" % [GameData.as_string(passenger.get("id"), "?"), index])
	var items_root: Dictionary = _data.root("items")
	var starting: Array = GameData.as_array(items_root.get("starting_cabin"))
	for index: int in starting.size():
		var entry: Dictionary = GameData.as_dict(starting[index])
		var where: String = "starting_cabin[%d]" % index
		var entry_item: String = GameData.as_string(entry.get("item"))
		var entry_slot: String = GameData.as_string(entry.get("slot"))
		if not _data.has_record("items", entry_item):
			_err("E_REF", "items.json", where + ".item", "unknown items id '%s'" % entry_item)
		elif not GameData.as_array(_data.record("items", entry_item).get("slots")).has(entry_slot):
			_err("E_RULE", "items.json", where + ".slot", "'%s' does not fit in slot '%s'" % [entry_item, entry_slot])
		if not _data.has_record("slots", entry_slot):
			_err("E_REF", "items.json", where + ".slot", "unknown slots id '%s'" % entry_slot)
		if entry.has("supply") and not GameData.is_number(entry["supply"]):
			_err("E_TYPE", "items.json", where + ".supply", "must be a whole number")
	for item: Dictionary in _data.records("items"):
		var item_id: String = GameData.as_string(item.get("id"), "?")
		var tags: Array = GameData.as_array(item.get("tags"))
		for index: int in tags.size():
			if tags[index] is String and not _item_tags().has(GameData.as_string(tags[index])):
				_err("E_REF", "items.json", "items[%s].tags[%d]" % [item_id, index],
						"'%s' is not a tag of items.json (%s)" % [GameData.as_string(tags[index]), ", ".join(_item_tags())])
		for ritual_id: Variant in GameData.as_array(item.get("rituals")):
			var listed: String = GameData.as_string(ritual_id)
			if _data.has_record("rituals", listed):
				var owner: String = GameData.as_string(_data.record("rituals", listed).get("item"))
				if not owner.is_empty() and owner != item_id:
					_err("E_RULE", "items.json", "items[%s].rituals" % item_id,
							"ritual '%s' belongs to item '%s'" % [listed, owner])
		for list: String in ["gives", "takes"]:
			var entries: Array = GameData.as_array(item.get(list))
			for index: int in entries.size():
				_check_entry(item, GameData.as_dict(entries[index]), "items[%s].%s[%d]" % [item_id, list, index])
		# An item that moves a control says which anchor and where to.
		var params: Dictionary = GameData.as_dict(item.get("params"))
		if params.has("moves_anchor") or params.has("moves_to"):
			if not _data.has_record("anchors", GameData.as_string(params.get("moves_anchor"))):
				_err("E_REF", "items.json", "items[%s].params.moves_anchor" % item_id,
						"unknown anchors id '%s'" % GameData.as_string(params.get("moves_anchor")))
			_check(params.get("moves_to"), _t("vec3"), "items.json", "items[%s].params.moves_to" % item_id)
		var synergies: Array = GameData.as_array(item.get("synergies"))
		for index: int in synergies.size():
			var synergy: Dictionary = GameData.as_dict(synergies[index])
			var with: String = GameData.as_string(synergy.get("with"))
			var rule: String = GameData.as_string(synergy.get("rule"))
			if synergy.has("rule") and synergy["rule"] is String and not ItemSim.SYNERGY_RULES.has(rule):
				_err("E_ENUM", "items.json", "items[%s].synergies[%d].rule" % [item_id, index],
						"'%s' is not a synergy rule (%s)" % [rule, ", ".join(ItemSim.SYNERGY_RULES)])
			if with.is_empty():
				continue
			if not _data.has_record("items", with) and not _synergy_tokens().has(with):
				_err("E_REF", "items.json", "items[%s].synergies[%d].with" % [item_id, index],
						"unknown item id or synergy token '%s'" % with)


## Every content row of Part II that a finished milestone owes (GDD 1.1).
## A record set that is still empty is not owed yet.
func _check_required_records() -> void:
	for set_name: Variant in REQUIRED_RECORDS:
		var set_id: String = str(set_name)
		if _data.records(set_id).is_empty():
			continue
		var where: Array = GameData.RECORD_SETS[set_id]
		var required: Array = REQUIRED_RECORDS[set_name]
		for id: Variant in required:
			if not _data.has_record(set_id, str(id)):
				_err("E_MISSING", "%s.json" % str(where[0]), "%s[%s]" % [str(where[1]), str(id)], "this row of the GDD is missing")


## Beat templates: lengths, speeds below par, lane changes ahead of the vehicle.
func _check_beats() -> void:
	var par: float = INF
	if _data.tuning.has("gear_speeds") and _data.tuning.raw("gear_speeds") is Array and _data.tuning.a("gear_speeds").size() >= 3:
		par = _data.tuning.fi("gear_speeds", 2)
	var typed: Dictionary = {}
	for beat: Dictionary in _data.records("beats"):
		var label: String = "beats[%s]" % GameData.as_string(beat.get("id"), "?")
		typed[GameData.as_string(beat.get("type"))] = true
		var length: Variant = beat.get("length_m")
		var length_ok: bool = GameData.is_number(length) and GameData.as_float(length) > 0.0
		if length is Array:
			var span: Array = length
			length_ok = span.size() == 2 and GameData.is_number(span[0]) and GameData.is_number(span[1]) \
					and GameData.as_float(span[0]) > 0.0 and GameData.as_float(span[1]) >= GameData.as_float(span[0])
		if not length_ok:
			_err("E_TYPE", "beats.json", label + ".length_m", "must be a length in metres or [shortest, longest]")
		elif _data.tuning.has("beat_lengths"):
			# Each template keeps to the length of its type (GDD 9.2).
			var allowed: Array = GameData.as_array(_data.tuning.d("beat_lengths").get(GameData.as_string(beat.get("type"))))
			var shortest: float = GameData.as_float(length)
			var longest: float = shortest
			if length is Array:
				var own: Array = length
				shortest = GameData.as_float(own[0])
				longest = GameData.as_float(own[1])
			if allowed.size() == 2 and (shortest < GameData.as_float(allowed[0]) or longest > GameData.as_float(allowed[1])):
				_err("E_RULE", "beats.json", label + ".length_m", "a %s beat is %s to %s m long (GDD 9.2)" % [
						GameData.as_string(beat.get("type")), str(allowed[0]), str(allowed[1])])
		var spawns: Array = GameData.as_array(beat.get("spawns"))
		for index: int in spawns.size():
			var spawn: Dictionary = GameData.as_dict(spawns[index])
			var where: String = "%s.spawns[%d]" % [label, index]
			if GameData.as_string(spawn.get("lane")) != "oncoming" and GameData.as_float(spawn.get("speed_kmh")) >= par:
				_err("E_RULE", "beats.json", where + ".speed_kmh", "a vehicle to be met in third gear must be slower than third gear (%s km/h)" % str(par))
			var change: Dictionary = GameData.as_dict(spawn.get("lane_change"))
			if change.has("at_s_offset") and GameData.as_float(change.get("at_s_offset")) <= GameData.as_float(spawn.get("s_offset")):
				_err("E_RULE", "beats.json", where + ".lane_change.at_s_offset", "must lie ahead of the vehicle's s_offset")
	if not _data.records("beats").is_empty():
		for type: String in BEAT_TYPES:
			if type != "SPECIAL" and not typed.has(type):
				_err("E_MISSING", "beats.json", "beats", "no beat of type %s" % type)


## One entry of an item's "gives" or "takes" (see ItemSim): a status, or a
## change to a resource, with the keys that kind of entry has.
func _check_entry(item: Dictionary, entry: Dictionary, where: String) -> void:
	const ENTRY_KEYS: PackedStringArray = ["effect", "duration", "for", "resource", "amount", "over", "per_s", "while", "synergy", "passive"]
	for key: Variant in entry:
		if not ENTRY_KEYS.has(str(key)):
			_err("E_UNKNOWN_KEY", "items.json", where, "unknown key '%s' (%s)" % [str(key), ", ".join(ENTRY_KEYS)])
	for key: String in ["duration", "amount", "over", "per_s"]:
		if entry.has(key) and not GameData.is_number(entry[key]):
			_err("E_TYPE", "items.json", "%s.%s" % [where, key], "must be a number")
	if entry.has("for") and (GameData.as_string(entry.get("for")) != "leg" or entry.has("duration") or not entry.has("effect")):
		_err("E_RULE", "items.json", where + ".for", "\"for\" is \"leg\", on a status with no duration")
	if entry.has("passive"):
		var key: String = GameData.as_string(entry.get("passive"))
		if not ItemSim.PASSIVES.has(key):
			_err("E_ENUM", "items.json", where + ".passive", "'%s' is not a standing change (%s)" % [key, ", ".join(ItemSim.PASSIVES.keys())])
		if not entry.has("amount") or entry.size() != 2:
			_err("E_RULE", "items.json", where, "a passive entry is {\"passive\": key, \"amount\": number}")
		return
	if entry.has("effect") == entry.has("resource"):
		_err("E_RULE", "items.json", where, "needs exactly one of \"effect\" and \"resource\"")
	if entry.has("effect"):
		var effect: String = GameData.as_string(entry.get("effect"))
		if effect == ItemSim.HAZE_RATE:
			if not entry.has("amount"):
				_err("E_RULE", "items.json", where, "a haze_rate entry needs \"amount\" (share per second)")
		elif not _data.has_record("effects", effect):
			_err("E_REF", "items.json", where + ".effect", "unknown effects id '%s'" % effect)
	if entry.has("resource"):
		var resource: String = GameData.as_string(entry.get("resource"))
		if resource != "nerves" and resource != "cash":
			_err("E_ENUM", "items.json", where + ".resource", "must be nerves or cash, not '%s'" % resource)
		if entry.has("amount") == entry.has("per_s"):
			_err("E_RULE", "items.json", where, "a resource entry needs exactly one of \"amount\" and \"per_s\"")
	if entry.has("while"):
		_check_condition(GameData.as_string(entry.get("while")), "items.json", where + ".while")
	if entry.has("synergy"):
		var rule: String = GameData.as_string(entry.get("synergy"))
		var found: bool = false
		for synergy: Variant in GameData.as_array(item.get("synergies")):
			if GameData.as_string(GameData.as_dict(synergy).get("rule")) == rule:
				found = true
		if not found:
			_err("E_REF", "items.json", where + ".synergy", "the item has no synergy with the rule '%s'" % rule)


## One ritual op: "op" or "op:arg:arg". The op must be known, and the ids it
## names must exist.
func _check_op(op: String, file_label: String, where: String) -> void:
	var parts: PackedStringArray = op.split(":")
	var head: String = parts[0]
	if not RITUAL_OPS.has(head):
		_err("E_ENUM", file_label, where, "'%s' is not a ritual op (%s)" % [head, ", ".join(RITUAL_OPS)])
		return
	var argument: String = parts[1] if parts.size() > 1 else ""
	match head:
		"add_effect", "remove_effect":
			if not _data.has_record("effects", argument):
				_err("E_REF", file_label, where, "unknown effects id '%s'" % argument)
			if parts.size() > 2 and not parts[2].is_valid_float():
				_err("E_TYPE", file_label, where, "the duration '%s' is not a number" % parts[2])
		"nerves", "cash":
			if not argument.is_valid_float():
				_err("E_TYPE", file_label, where, "'%s' needs a number" % head)
		"pay":
			if argument != "fine" and argument != "bribe":
				_err("E_ENUM", file_label, where, "'pay' takes fine or bribe, not '%s'" % argument)
		"call":
			if not CALL_WAYS.has(argument):
				_err("E_ENUM", file_label, where, "'call' takes %s, not '%s'" % [" or ".join(CALL_WAYS), argument])
		"hand":
			if not DOCUMENTS.has(argument) and argument != BANKNOTES:
				_err("E_ENUM", file_label, where, "'hand' takes %s or %s, not '%s'" % [", ".join(DOCUMENTS), BANKNOTES, argument])
		"refill":
			if not _item_tags().has(argument):
				_err("E_REF", file_label, where, "'refill' takes an item tag; '%s' is not a tag of items.json" % argument)
		"toggle":
			if not CABIN_FLAGS.has(argument):
				_err("E_ENUM", file_label, where, "'%s' is not a cabin switch (%s)" % [argument, ", ".join(CABIN_FLAGS)])
		"sfx":
			if not _data.root("sfx").has(argument):
				_err("E_REF", file_label, where, "unknown sfx id '%s'" % argument)
		"line":
			if not _data.has_line(argument, "en"):
				_err("E_REF", file_label, where, "unknown lines id '%s'" % argument)


## What the schema cannot say of a passenger: a Hand that lasts needs its
## time, a passed thing its place, each Weight a moment it bites and either
## an amount or a rate, and the passenger the lines every passenger has.
func _check_passenger(passenger: Dictionary, label: String) -> void:
	var hand: Dictionary = GameData.as_dict(passenger.get("hand"))
	var kind: String = GameData.as_string(hand.get("kind"))
	if (kind == "hold_wheel_straight" or kind == "hold_wheel") and GameData.as_float(hand.get("duration_s")) <= 0.0:
		_err("E_RULE", "passengers.json", label + ".hand", "a hand that holds the wheel needs a \"duration_s\" above 0")
	if kind == "pass_tea" and not hand.has("at"):
		_err("E_RULE", "passengers.json", label + ".hand", "a hand that passes something needs \"at\": where it is held")
	if kind == "pass_tea" and not passenger.has("drums"):
		_err("E_RULE", "passengers.json", label + ".hand", "passing the tea is what a drummer does between drumming: it needs \"drums\"")
	if kind == "cigarette" and not passenger.has("sleeps"):
		_err("E_RULE", "passengers.json", label + ".hand", "the cigarette is handed over by one who has been woken: it needs \"sleeps\"")
	var weights: Array = GameData.as_array(passenger.get("weights"))
	for index: int in weights.size():
		var weight: Dictionary = GameData.as_dict(weights[index])
		var where: String = "%s.weights[%d]" % [label, index]
		var when: String = GameData.as_string(weight.get("when"))
		var by_the_second: bool = true
		if when.begins_with("ritual_tag:"):
			by_the_second = false
			if not _item_tags().has(when.substr(11)):
				_err("E_REF", "passengers.json", where + ".when", "'%s' is not a tag of items.json" % when.substr(11))
		elif when.begins_with("gear>="):
			var rest: String = when.substr(6)
			if not rest.trim_suffix("&rain").is_valid_int():
				_err("E_ENUM", "passengers.json", where + ".when", "\"gear>=<n>\" or \"gear>=<n>&rain\", not '%s'" % when)
		elif when == "scrape":
			by_the_second = false
		elif not WEIGHT_WHENS.has(when):
			_err("E_ENUM", "passengers.json", where + ".when", "'%s' is not a moment a Weight bites (ritual_tag:<tag>, gear>=<n>, gear>=<n>&rain, %s)" % [when, ", ".join(WEIGHT_WHENS)])
		if weight.has("amount") == weight.has("per_s"):
			_err("E_RULE", "passengers.json", where, "needs exactly one of \"amount\" and \"per_s\"")
		elif weight.has("per_s") != by_the_second:
			_err("E_RULE", "passengers.json", where, "'%s' weighs %s" % [when, "by the second: it needs \"per_s\"" if by_the_second else "once each time: it needs \"amount\""])
		if when == "drumming&patrol" and not passenger.has("drums"):
			_err("E_RULE", "passengers.json", where + ".when", "only a passenger with \"drums\" drums")
		if when == "asleep" and not passenger.has("sleeps"):
			_err("E_RULE", "passengers.json", where + ".when", "only a passenger with \"sleeps\" sleeps")
	var retunes: Dictionary = GameData.as_dict(passenger.get("retunes"))
	if passenger.has("retunes"):
		var station: String = GameData.as_string(retunes.get("to"))
		if station != "static" and not GameData.as_array(_data.tuning.a("radio_stations") if _data.tuning.has("radio_stations") else []).has(station):
			_err("E_REF", "passengers.json", label + ".retunes.to", "'%s' is neither static nor a station of radio_stations" % station)
		if GameData.as_float(retunes.get("every_s")) <= 0.0:
			_err("E_RULE", "passengers.json", label + ".retunes.every_s", "must be above 0")
	var prefix: String = GameData.as_string(passenger.get("line_prefix"))
	for line: String in PASSENGER_LINES:
		if not prefix.is_empty() and not _data.has_line("%s.%s" % [prefix, line], "en"):
			_err("E_REF", "passengers.json", label + ".line_prefix", "the line '%s.%s' is missing" % [prefix, line])


## One ritual condition: an effect id, "supply>0", "hot" or "flag:<switch>",
## each optionally negated with "!".
func _check_condition(condition: String, file_label: String, where: String) -> void:
	var word: String = condition.trim_prefix("!")
	if CONDITION_WORDS.has(word):
		return
	if word.begins_with("flag:"):
		if not CABIN_FLAGS.has(word.substr(5)):
			_err("E_ENUM", file_label, where, "'%s' is not a cabin switch" % word.substr(5))
		return
	if word.begins_with("tag:"):
		if not _item_tags().has(word.substr(4)):
			_err("E_REF", file_label, where, "'%s' is not a tag of items.json" % word.substr(4))
		return
	if not _data.has_record("effects", word):
		_err("E_REF", file_label, where, "'%s' is neither a condition word nor an effects id" % word)


## The tags an item may carry and a slot may hold (items.json "tags").
func _item_tags() -> PackedStringArray:
	var out: PackedStringArray = []
	for tag: Variant in GameData.as_array(_data.root("items").get("tags")):
		out.append(str(tag))
	return out


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
	elif GameData.as_bool(spec.get("open")) and number <= minimum:
		_err("E_RANGE", file_label, where, "%s must be more than %s" % [str(number), str(minimum)])


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
