class_name TuningPanel
extends Control
## F2 (GDD 13.9): "Live tuning panel for every value in tuning.json, with
## export." Every constant by group, its unit beside it, its value typed as
## JSON. A change is the session's: it is in the game's data until the game
## quits, the next drive scene is built from it, and data/tuning.json is
## not touched. Export writes the whole table, as the file is shaped, into
## the user folder.

signal closed

const EXPORT_NAME: String = "tuning_export.json"

## True once a value was changed while this panel was open.
var changed: bool = false

var _scale: float = 1.0
var _heading: Label
var _status: Label
var _list: VBoxContainer
## key -> its row, for the filter.
var _row_of: Dictionary = {}
## key -> its field.
var _field_of: Dictionary = {}


func setup() -> void:
	_scale = get_viewport_rect().size.y / 1080.0
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	var tuning: Tuning = Game.data.tuning
	var shade: ColorRect = ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.04, 0.04, 0.06, 1.0)
	add_child(shade)
	var column: VBoxContainer = VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 60.0 * _scale
	column.offset_top = 24.0 * _scale
	column.offset_right = -60.0 * _scale
	column.offset_bottom = -24.0 * _scale
	add_child(column)

	_heading = Label.new()
	_font(_heading, 1.0)
	column.add_child(_heading)
	var note: Label = Label.new()
	note.text = Lines.get_text("dev.tuning.note")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_font(note, 0.6)
	column.add_child(note)

	var bar: HBoxContainer = HBoxContainer.new()
	column.add_child(bar)
	var filter: LineEdit = LineEdit.new()
	filter.placeholder_text = Lines.get_text("dev.tuning.filter")
	filter.custom_minimum_size = Vector2(420.0 * _scale, 0.0)
	_font(filter, 0.7)
	filter.text_changed.connect(_filter)
	bar.add_child(filter)
	_bar_button(bar, Lines.format("dev.tuning.export", [EXPORT_NAME]), _export)
	_bar_button(bar, Lines.get_text("dev.tuning.reset"), _reset)
	_bar_button(bar, Lines.get_text("dev.tuning.close"), _close)
	_status = Label.new()
	_font(_status, 0.6)
	column.add_child(_status)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	for group: String in tuning.groups():
		for key: String in tuning.keys_in_group(group):
			_add_row(group, key)
	_refresh_heading()
	filter.grab_focus.call_deferred()


func _add_row(group: String, key: String) -> void:
	var tuning: Tuning = Game.data.tuning
	var row: HBoxContainer = HBoxContainer.new()
	var name_label: Label = Label.new()
	name_label.text = "%s . %s" % [group, key]
	name_label.custom_minimum_size = Vector2(560.0 * _scale, 0.0)
	_font(name_label, 0.6)
	row.add_child(name_label)
	var field: LineEdit = LineEdit.new()
	field.text = JSON.stringify(tuning.raw(key))
	field.custom_minimum_size = Vector2(420.0 * _scale, 0.0)
	_font(field, 0.6)
	field.text_submitted.connect(_take.bind(key))
	field.focus_exited.connect(func() -> void: _take(field.text, key))
	row.add_child(field)
	var unit: Label = Label.new()
	unit.text = tuning.unit_of(key)
	unit.modulate = Color(1.0, 1.0, 1.0, 0.55)
	unit.clip_text = true
	unit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_font(unit, 0.55)
	row.add_child(unit)
	_list.add_child(row)
	_row_of[key] = row
	_field_of[key] = field
	_mark(key)


## A field was left or Enter pressed in it: the constant takes what was typed.
func _take(text: String, key: String) -> void:
	var tuning: Tuning = Game.data.tuning
	var before: String = JSON.stringify(tuning.raw(key))
	if text.strip_edges() == before:
		return
	var json: JSON = JSON.new()
	if json.parse(text) != OK or typeof(json.data) != typeof(tuning.raw(key)):
		# Not a value, or another kind of value than the constant holds.
		_status.text = Lines.format("dev.tuning.bad", [text])
		var field: LineEdit = _field_of[key]
		field.text = before
		return
	if not Game.dev_tuning_original.has(key):
		Game.dev_tuning_original[key] = tuning.raw(key)
	tuning.set_value(key, json.data)
	var shown: LineEdit = _field_of[key]
	shown.text = JSON.stringify(json.data)
	changed = true
	_status.text = "%s = %s" % [key, JSON.stringify(json.data)]
	_mark(key)
	_refresh_heading()
	print("[dev] tuning %s = %s" % [key, JSON.stringify(json.data)])


## A constant that is not what the file says is shown so.
func _mark(key: String) -> void:
	var field: LineEdit = _field_of[key]
	var moved: bool = Game.dev_tuning_original.has(key) and JSON.stringify(Game.dev_tuning_original[key]) != JSON.stringify(Game.data.tuning.raw(key))
	field.modulate = Color(1.0, 0.85, 0.3) if moved else Color.WHITE


func _refresh_heading() -> void:
	var moved: int = 0
	for key: Variant in Game.dev_tuning_original:
		if JSON.stringify(Game.dev_tuning_original[key]) != JSON.stringify(Game.data.tuning.raw(str(key))):
			moved += 1
	_heading.text = Lines.format("dev.tuning.heading", [str(moved)])


func _filter(text: String) -> void:
	var wanted: String = text.strip_edges().to_lower()
	for key: Variant in _row_of:
		var row: Control = _row_of[key]
		var label: Label = row.get_child(0) as Label
		row.visible = wanted.is_empty() or label.text.to_lower().contains(wanted)


func _reset() -> void:
	for key: Variant in Game.dev_tuning_original:
		Game.data.tuning.set_value(str(key), Game.dev_tuning_original[key])
		var field: LineEdit = _field_of[str(key)]
		field.text = JSON.stringify(Game.dev_tuning_original[key])
	var keys: Array = Game.dev_tuning_original.keys()
	Game.dev_tuning_original.clear()
	for key: Variant in keys:
		_mark(str(key))
	changed = true
	_refresh_heading()


func _export() -> void:
	var path: String = Game.user_dir.path_join(EXPORT_NAME)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_status.text = error_string(FileAccess.get_open_error())
		return
	file.store_string(JSON.stringify(Game.data.tuning.to_root(), "  "))
	_status.text = Lines.format("dev.tuning.exported", [ProjectSettings.globalize_path(path)])
	print("[dev] tuning exported to %s" % ProjectSettings.globalize_path(path))


func _close() -> void:
	closed.emit()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("debug_tuning"):
		get_viewport().set_input_as_handled()
		_close()


func _bar_button(parent: Control, text: String, pressed: Callable) -> void:
	var button: Button = Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	_font(button, 0.65)
	button.pressed.connect(pressed)
	parent.add_child(button)


func _font(control: Control, size: float) -> void:
	control.add_theme_font_size_override("font_size", roundi(Game.data.tuning.f("menu_font_size") * size * _scale))
