class_name SettingsView
extends Control
## The settings of GDD 17.1 on a screen: one row each, in the order of the
## GDD's table. A press of the left button on a row takes its next option,
## the right button the one before: pointer motion and two buttons, as
## everything is (GDD 17.2). A change is kept at once (the Settings
## autoload writes its file) and takes effect at once, in the middle of a
## Telling as anywhere.

signal closed

var _rows: VBoxContainer
var _buttons: Dictionary = {}
var _spec: SettingsSpec
var _scale: float = 1.0


## `leave_line`, when given, adds an entry under the rows that emits
## `closed` with it (the pause screen's "Back to the wedding").
func setup(back_line: String = "settings.back") -> void:
	_spec = Game.settings_spec
	_scale = get_viewport_rect().size.y / 1080.0
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	var tuning: Tuning = Game.data.tuning
	var shade: ColorRect = ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.0, 0.0, 0.0, 0.85)
	add_child(shade)
	_rows = VBoxContainer.new()
	_rows.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_rows.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_rows.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_rows)
	var heading: Label = Label.new()
	heading.text = Lines.get_text("settings.heading")
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", roundi(tuning.f("menu_heading_font_size") * 0.8 * _scale))
	_rows.add_child(heading)
	for id: String in _spec.ids():
		var button: Button = Button.new()
		button.flat = true
		button.focus_mode = Control.FOCUS_NONE
		button.button_mask = MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT
		button.add_theme_font_size_override("font_size", roundi(tuning.f("menu_font_size") * 0.85 * _scale))
		button.gui_input.connect(_on_row_input.bind(id))
		_rows.add_child(button)
		_buttons[id] = button
	var hint: Label = Label.new()
	hint.text = Lines.get_text("settings.hint")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", roundi(tuning.f("menu_font_size") * 0.6 * _scale))
	_rows.add_child(hint)
	var pause_hint: Label = Label.new()
	pause_hint.text = Lines.get_text("settings.hint.pause")
	pause_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_hint.add_theme_font_size_override("font_size", roundi(tuning.f("menu_font_size") * 0.6 * _scale))
	_rows.add_child(pause_hint)
	add_entry(back_line, "")
	refresh()


## An entry under the rows: pressed, the screen closes and says which.
func add_entry(line_id: String, answer: String) -> void:
	var button: Button = Button.new()
	button.text = Lines.get_text(line_id)
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", roundi(Game.data.tuning.f("menu_font_size") * _scale))
	button.pressed.connect(_close.bind(answer))
	_rows.add_child(button)


## What closing it was for ("" for going back to where it was opened).
var answer: String = ""


func _close(with: String) -> void:
	answer = with
	closed.emit()


func refresh() -> void:
	for id: Variant in _buttons:
		var button: Button = _buttons[id]
		button.text = "%s:  %s" % [Lines.get_text("settings.%s.name" % str(id)), value_text(_spec, str(id), Settings.get_value(str(id)))]


## A setting's value as the screen writes it.
static func value_text(spec: SettingsSpec, id: String, value: Variant) -> String:
	match spec.kind(id):
		SettingsSpec.RANGE:
			return Lines.format("settings.value.percent", [str(roundi(GameData.as_float(value)))])
		SettingsSpec.TOGGLE:
			return Lines.get_text("settings.value.on" if GameData.as_bool(value) else "settings.value.off")
	return Lines.get_text("settings.value.%s" % GameData.as_string(value))


## A press on a row: the left button takes the next option, the right one
## the option before.
func _on_row_input(event: InputEvent, id: String) -> void:
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click == null or not click.pressed:
		return
	if click.button_index == MOUSE_BUTTON_LEFT:
		change(id, 1)
	elif click.button_index == MOUSE_BUTTON_RIGHT:
		change(id, -1)


## Takes the setting's next option (`by` 1) or the one before (-1), keeps it
## and shows it.
func change(id: String, by: int) -> void:
	Settings.set_value(id, _spec.stepped(id, Settings.get_value(id), by))
	refresh()
