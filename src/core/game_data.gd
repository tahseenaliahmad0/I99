class_name GameData
extends RefCounted
## Every file under res://data, loaded once (GDD 1.3, 13.2, 14).
##
## Pure: no Node, no autoload. The simulation, the views and the tests all read
## content through one instance of this class. Loading never fails loudly; it
## collects `errors` so the validator and the boot scene can report them all.

## Record sets: set name -> [file name, key of the array of records in that file].
## A record is an object with a unique "id". Most files hold one set; the road
## vocabulary (beats.json) also holds vehicles, anchors.json also holds the
## slots and the static props that dress the cabin, and items.json also holds
## the status effects that items and rituals name.
const RECORD_SETS: Dictionary = {
	"items": ["items", "items"],
	"effects": ["items", "effects"],
	"rituals": ["rituals", "rituals"],
	"legs": ["legs", "legs"],
	"bosses": ["legs", "bosses"],
	"beats": ["beats", "beats"],
	"vehicles": ["beats", "vehicles"],
	"hazard_kinds": ["beats", "hazard_kinds"],
	"modifiers": ["modifiers", "modifiers"],
	"stops": ["stops", "stops"],
	"passengers": ["passengers", "passengers"],
	"tables": ["tables", "tables"],
	"heckles": ["heckles", "heckles"],
	"faults": ["faults", "faults"],
	"anchors": ["anchors", "anchors"],
	"slots": ["anchors", "slots"],
	"props": ["anchors", "props"],
}
## The fourteen JSON files of GDD 13.2. placeholders and sfx are registries:
## the root object maps an id straight to its entry (GDD 14).
const JSON_FILES: PackedStringArray = [
	"tuning", "items", "rituals", "legs", "beats", "modifiers", "stops",
	"passengers", "tables", "heckles", "faults", "anchors", "placeholders", "sfx",
]
const REGISTRY_FILES: PackedStringArray = ["placeholders", "sfx"]
const LINE_LOCALES: PackedStringArray = ["en", "ar"]
const LINE_HEADER: PackedStringArray = ["id", "speaker", "text", "needs_writer"]
const DEFAULT_DIR: String = "res://data"

var dir: String = ""
var errors: PackedStringArray = []
## file name -> parsed JSON root (always a Dictionary once loaded).
var roots: Dictionary = {}
var tuning: Tuning = Tuning.new()
## locale -> { line id -> { "speaker": String, "text": String, "needs_writer": bool } }
var lines: Dictionary = {}
## locale -> line ids in file order.
var line_order: Dictionary = {}

var _index: Dictionary = {}


static func load_from(data_dir: String = DEFAULT_DIR) -> GameData:
	var data: GameData = GameData.new()
	data._load_dir(data_dir)
	return data


## Builds a GameData from already-parsed roots and lines (tests use this to
## validate deliberately broken data without touching the disk).
static func from_parts(json_roots: Dictionary, line_tables: Dictionary) -> GameData:
	var data: GameData = GameData.new()
	data.dir = "<memory>"
	data.roots = json_roots
	data.lines = line_tables
	for locale: Variant in line_tables:
		var table: Dictionary = line_tables[locale]
		var order: PackedStringArray = []
		for id: Variant in table:
			order.append(str(id))
		data.line_order[locale] = order
	data._finish()
	return data


func _load_dir(data_dir: String) -> void:
	dir = data_dir
	for file: String in JSON_FILES:
		var root: Variant = _read_json("%s/%s.json" % [dir, file])
		if root is Dictionary:
			roots[file] = root
	for locale: String in LINE_LOCALES:
		_read_lines(locale, "%s/lines_%s.csv" % [dir, locale])
	_finish()


func _finish() -> void:
	if roots.has("tuning"):
		var tuning_root: Dictionary = roots["tuning"]
		tuning = Tuning.from_root(tuning_root)
	for set_name: Variant in RECORD_SETS:
		var by_id: Dictionary = {}
		for entry: Dictionary in records(str(set_name)):
			if entry.has("id"):
				by_id[str(entry["id"])] = entry
		_index[set_name] = by_id


func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		errors.append("[E_FILE] %s: file is missing" % path)
		return null
	var text: String = FileAccess.get_file_as_string(path)
	var parser: JSON = JSON.new()
	var err: Error = parser.parse(text)
	if err != OK:
		errors.append("[E_JSON] %s:%d: %s" % [path, parser.get_error_line(), parser.get_error_message()])
		return null
	var root: Variant = parser.data
	if not root is Dictionary:
		errors.append("[E_JSON] %s: the top level must be an object" % path)
		return null
	return root


func _read_lines(locale: String, path: String) -> void:
	var table: Dictionary = {}
	var order: PackedStringArray = []
	lines[locale] = table
	line_order[locale] = order
	if not FileAccess.file_exists(path):
		errors.append("[E_FILE] %s: file is missing" % path)
		return
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		errors.append("[E_FILE] %s: cannot open (%s)" % [path, error_string(FileAccess.get_open_error())])
		return
	var header: PackedStringArray = file.get_csv_line()
	if header != LINE_HEADER:
		errors.append("[E_LINES] %s: header must be %s" % [path, ",".join(LINE_HEADER)])
		return
	var row_number: int = 1
	while not file.eof_reached():
		var row: PackedStringArray = file.get_csv_line()
		row_number += 1
		if row.size() == 1 and row[0].strip_edges().is_empty():
			continue
		if row.size() != LINE_HEADER.size():
			errors.append("[E_LINES] %s:%d: expected %d columns, found %d" % [path, row_number, LINE_HEADER.size(), row.size()])
			continue
		var id: String = row[0].strip_edges()
		var flag: String = row[3].strip_edges().to_lower()
		if id.is_empty():
			errors.append("[E_LINES] %s:%d: empty line id" % [path, row_number])
			continue
		if table.has(id):
			errors.append("[E_DUP_ID] %s:%d: duplicate line id '%s'" % [path, row_number, id])
			continue
		if flag != "true" and flag != "false":
			errors.append("[E_LINES] %s:%d: needs_writer must be true or false" % [path, row_number])
		table[id] = {"speaker": row[1], "text": row[2], "needs_writer": flag == "true"}
		order.append(id)


# --- Records -----------------------------------------------------------------

## The records of one set, e.g. records("items"). Non-objects are skipped.
func records(set_name: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not RECORD_SETS.has(set_name):
		push_error("GameData: unknown record set '%s'" % set_name)
		return out
	var where: Array = RECORD_SETS[set_name]
	var file: String = where[0]
	var key: String = where[1]
	if not roots.has(file):
		return out
	var file_root: Dictionary = roots[file]
	var list: Variant = file_root.get(key)
	if list is Array:
		var entries: Array = list
		for entry: Variant in entries:
			if entry is Dictionary:
				out.append(entry)
	return out


func has_record(set_name: String, id: String) -> bool:
	if not _index.has(set_name):
		return false
	var by_id: Dictionary = _index[set_name]
	return by_id.has(id)


## One record by id. Asking for an id that does not exist is a programming error.
func record(set_name: String, id: String) -> Dictionary:
	if not has_record(set_name, id):
		push_error("GameData: no '%s' record with id '%s'" % [set_name, id])
		return {}
	var by_id: Dictionary = _index[set_name]
	return by_id[id]


func record_ids(set_name: String) -> PackedStringArray:
	var out: PackedStringArray = []
	for entry: Dictionary in records(set_name):
		if entry.has("id"):
			out.append(str(entry["id"]))
	return out


## The root object of a file, e.g. root("anchors") or root("placeholders").
func root(file: String) -> Dictionary:
	if not roots.has(file):
		return {}
	return roots[file]


# --- Lines -------------------------------------------------------------------

func has_line(id: String, locale: String = "en") -> bool:
	if not lines.has(locale):
		return false
	var table: Dictionary = lines[locale]
	return table.has(id)


func line(id: String, locale: String = "en") -> Dictionary:
	if not has_line(id, locale):
		return {}
	var table: Dictionary = lines[locale]
	return table[id]


func line_ids(locale: String = "en") -> PackedStringArray:
	if not line_order.has(locale):
		return PackedStringArray()
	return line_order[locale]


# --- Typed readers for parsed JSON -------------------------------------------

static func is_number(v: Variant) -> bool:
	return v is float or v is int


static func as_float(v: Variant, fallback: float = 0.0) -> float:
	if v is float or v is int:
		var number: float = v
		return number
	return fallback


static func as_int(v: Variant, fallback: int = 0) -> int:
	if v is float or v is int:
		var number: float = v
		return int(roundf(number))
	return fallback


static func as_string(v: Variant, fallback: String = "") -> String:
	if v is String:
		return v
	return fallback


static func as_bool(v: Variant, fallback: bool = false) -> bool:
	if v is bool:
		return v
	return fallback


static func as_dict(v: Variant) -> Dictionary:
	if v is Dictionary:
		return v
	return {}


static func as_array(v: Variant) -> Array:
	if v is Array:
		return v
	return []


## [x, y, z] -> Vector3; a Vector3 is itself. Anything else is Vector3.ZERO.
static func as_vec3(v: Variant) -> Vector3:
	if v is Vector3:
		return v
	if v is Array:
		var arr: Array = v
		if arr.size() == 3 and is_number(arr[0]) and is_number(arr[1]) and is_number(arr[2]):
			return Vector3(as_float(arr[0]), as_float(arr[1]), as_float(arr[2]))
	return Vector3.ZERO
