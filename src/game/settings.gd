extends Node
## Player settings (GDD 17.1), kept in `settings.json` in the user directory.
##
## A persisted key-value store. The setting definitions, their options and
## defaults arrive with the systems that read them (M1 onward) and the
## settings screen (M10); every setting can be changed mid-Telling (GDD 17.2).

signal changed(key: String, value: Variant)

const FILE_NAME: String = "settings.json"

var _values: Dictionary = {}
var _defaults: Dictionary = {}
var _user_dir: String = "user://"


func setup(user_dir: String, defaults: Dictionary) -> void:
	_user_dir = user_dir
	_defaults = defaults
	_values = defaults.duplicate(true)
	_load()


func has_setting(key: String) -> bool:
	return _defaults.has(key)


func get_value(key: String) -> Variant:
	if not _defaults.has(key):
		push_error("Settings: unknown setting '%s'" % key)
		return null
	return _values.get(key, _defaults[key])


func set_value(key: String, value: Variant) -> void:
	if not _defaults.has(key):
		push_error("Settings: unknown setting '%s'" % key)
		return
	if _values.get(key) == value:
		return
	_values[key] = value
	changed.emit(key, value)
	save()


func reset_to_defaults() -> void:
	for key: Variant in _defaults:
		set_value(str(key), _defaults[key])


func save() -> void:
	# The folder may have been cleared away since the game started.
	if _user_dir != "user://":
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_user_dir))
	var file: FileAccess = FileAccess.open(_path(), FileAccess.WRITE)
	if file == null:
		push_error("Settings: cannot write %s (%s)" % [_path(), error_string(FileAccess.get_open_error())])
		return
	file.store_string(JSON.stringify(_values, "  "))


func _load() -> void:
	if not FileAccess.file_exists(_path()):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(_path()))
	if not parsed is Dictionary:
		return
	var stored: Dictionary = parsed
	for key: Variant in stored:
		# Unknown keys are dropped; a type that does not match the default is
		# ignored. JSON knows one kind of number, so a whole-number setting
		# comes back as a float and is turned into what its default is.
		if not _defaults.has(key):
			continue
		var value: Variant = stored[key]
		var default_value: Variant = _defaults[key]
		if GameData.is_number(value) and GameData.is_number(default_value):
			if typeof(default_value) == TYPE_INT:
				_values[key] = GameData.as_int(value)
			else:
				_values[key] = GameData.as_float(value)
		elif typeof(value) == typeof(default_value):
			_values[key] = value


func _path() -> String:
	return _user_dir.path_join(FILE_NAME)
