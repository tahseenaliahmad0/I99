class_name HintView
extends Control
## Names, feedback and the gear gate's diagram (D-071), drawn over the cabin
## while its art is boxes: what the pointer is on and how it is worked, a
## word at a control when something was done there or was not, and the H of
## the gate with the lever in it while the hand is on the lever.
##
## Reads the snapshot and an ActionFeedback; changes nothing. Every size is
## in reference pixels (a 1080-line view) and scaled to the view; colours
## are the registry's (`ui_hint_*`, `ui_feedback_*`, `ui_gate_*`).

## The Mirrored cabin setting (GDD 17.1): the picture is reversed, so the
## places words are drawn at are too. The words are not.
var mirrored: bool = false

var _enabled: bool = true
var _reference_height: float = 1080.0
var _offset: Vector2 = Vector2.ZERO
var _toast_s: float = 1.0
var _toast_rise: float = 0.0
var _name_px: float = 24.0
var _how_px: float = 18.0
var _pad: Vector2 = Vector2.ZERO
var _corner: float = 0.0
var _text_color: Color = Color.WHITE
var _back_color: Color = Color.BLACK
var _ok_color: Color = Color.GREEN
var _fail_color: Color = Color.RED
var _channel_color: Color = Color.DIM_GRAY
var _slot_color: Color = Color.GRAY
var _lever_color: Color = Color.WHITE
var _gate_unit: float = 64.0
var _gate_lift: float = 0.0
var _gate_line: float = 4.0
var _gate_half_width: float = 0.25
var _gate_engage: float = 0.2
var _lever_at: Vector3 = Vector3.ZERO

var _plate: PanelContainer
var _plate_style: StyleBoxFlat
var _name: Label
var _how: Label
## What the thing under the pointer does (an item's effect), wrapped.
var _what: Label
var _what_width: float = 520.0
## What to do now (Guide), at the top of the view.
var _guide: PanelContainer
var _guide_text: Label
var _guide_width: float = 900.0
var _guide_top: float = 70.0
var _bribe: float = 0.0
var _time: float = 0.0
var _toasts: Array[Label] = []

# What is drawn this frame.
var _show_gate: bool = false
var _gate_centre: Vector2 = Vector2.ZERO
var _gate_lever: Vector2 = Vector2.ZERO
var _gate_gear: int = 0
var _gate_fifth: bool = false
var _gate_held: bool = false
var _gate_locked: bool = false
var _gate_ground: float = 0.0
## The gear the moment asks for (Guide.gear_wanted; 0 for none): its slot is
## ringed and the way to it through the gate is drawn.
var _gate_wanted: int = 0


func setup(data: GameData, factory: PlaceholderFactory) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tuning: Tuning = data.tuning
	_enabled = tuning.b("hints_enabled")
	_reference_height = tuning.f("reference_height")
	_offset = Vector2(tuning.fi("hint_offset_px", 0), tuning.fi("hint_offset_px", 1))
	_toast_s = tuning.f("toast_s")
	_toast_rise = tuning.f("toast_rise_px")
	_corner = tuning.f("hint_corner_px")
	_name_px = factory.size_of("ui_hint_text").x
	_how_px = factory.size_of("ui_hint_text").y
	_pad = Vector2(factory.size_of("ui_hint_back").x, factory.size_of("ui_hint_back").y)
	_text_color = factory.color_of("ui_hint_text")
	_back_color = Color(factory.color_of("ui_hint_back"), tuning.f("hint_back_alpha"))
	_ok_color = factory.color_of("ui_feedback_ok")
	_fail_color = factory.color_of("ui_feedback_fail")
	_channel_color = factory.color_of("ui_gate_channel")
	_slot_color = factory.color_of("ui_gate_slot")
	_lever_color = factory.color_of("ui_gate_lever")
	_gate_unit = tuning.f("gate_diagram_unit_px")
	_gate_lift = tuning.f("gate_diagram_lift_px")
	_gate_line = tuning.f("gate_diagram_line_px")
	_gate_half_width = tuning.f("gate_channel_half_width")
	_gate_engage = tuning.f("gate_engage_radius")
	for anchor: Dictionary in data.records("anchors"):
		if GameData.as_string(anchor.get("id")) == ActionFeedback.GEAR_LEVER:
			_lever_at = GameData.as_vec3(anchor.get("pos"))

	_plate = PanelContainer.new()
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate_style = StyleBoxFlat.new()
	_plate_style.bg_color = _back_color
	_plate.add_theme_stylebox_override("panel", _plate_style)
	var rows: VBoxContainer = VBoxContainer.new()
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_theme_constant_override("separation", 0)
	_name = Label.new()
	_how = Label.new()
	_name.add_theme_color_override("font_color", _text_color)
	_how.add_theme_color_override("font_color", Color(_text_color, 0.75))
	rows.add_child(_name)
	rows.add_child(_how)
	_what = Label.new()
	_what.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_what.add_theme_color_override("font_color", Color(_text_color, 0.9))
	rows.add_child(_what)
	_plate.add_child(rows)
	_plate.visible = false
	add_child(_plate)
	_what_width = tuning.f("hint_effect_width_px")
	_guide_width = tuning.f("guide_width_px")
	_guide_top = tuning.f("guide_top_px")
	_bribe = tuning.f("checkpoint_bribe")
	_guide = PanelContainer.new()
	_guide.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_guide.add_theme_stylebox_override("panel", _plate_style)
	_guide_text = Label.new()
	_guide_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_guide_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_guide_text.add_theme_color_override("font_color", _text_color)
	_guide.add_child(_guide_text)
	_guide.visible = false
	add_child(_guide)


## `pointer_at` is where the pointer's ring is drawn (Vector2.INF while it is
## hidden); `cabin` gives where a control's marker is.
func apply(snapshot: Dictionary, feedback: ActionFeedback, camera: Camera3D, cabin: CabinView, pointer_at: Vector2, delta: float) -> void:
	visible = _enabled
	if not _enabled:
		return
	_time += delta
	var scale_px: float = size.y / _reference_height
	_size_text(scale_px)

	# What to do now, at the top.
	var told: PackedStringArray = []
	for row: Array in Guide.rows(snapshot, _bribe):
		var id: String = GameData.as_string(row[0])
		if Lines.has_line(id):
			told.append(Lines.format(id, GameData.as_array(row[1])) if not GameData.as_array(row[1]).is_empty() else Lines.get_text(id))
	_guide.visible = not told.is_empty()
	if _guide.visible:
		_guide_text.text = "\n".join(told)
		_guide_text.custom_minimum_size = Vector2(_guide_width * scale_px, 0.0)
		_guide.reset_size()
		_guide.position = Vector2((size.x - _guide.size.x) * 0.5, _guide_top * scale_px)
	_gate_wanted = Guide.gear_wanted(snapshot)

	# The label: what the pointer is on, or what the hand is busy with.
	var hint: Dictionary = snapshot["gesture_hint"]
	var at: Vector2 = Vector2.INF
	if not hint.is_empty():
		var busy_at: String = feedback.pressed
		if not busy_at.is_empty():
			at = _on_screen(camera, cabin.control_position(busy_at))
	elif pointer_at != Vector2.INF:
		hint = snapshot["hint"]
		at = pointer_at
		if hint.is_empty() and GameData.as_bool(snapshot["on_rim"]) and not GameData.as_bool(snapshot["stopped"]):
			hint = {"wheel": true}
	var named: String = name_of(hint)
	var how: String = how_of(hint)
	var what: String = effect_of(hint, snapshot)
	if hint.has("wheel"):
		named = Lines.get_text("hint.wheel")
		how = Lines.get_text("hint.wheel.how")
	_plate.visible = at != Vector2.INF and not (named.is_empty() and how.is_empty() and what.is_empty())
	if _plate.visible:
		_name.text = named
		_name.visible = not named.is_empty()
		_how.text = how
		_how.visible = not how.is_empty()
		_what.text = what
		_what.visible = not what.is_empty()
		_what.custom_minimum_size = Vector2(_what_width * scale_px if _what.visible else 0.0, 0.0)
		_plate.reset_size()
		_plate.position = _keep_inside(at + _offset * scale_px, _plate.size)

	# The gate, while the hand is at the lever or has just left it.
	var on_lever: bool = str(snapshot["hand_snap"]) == ActionFeedback.GEAR_LEVER or str(snapshot["hand_at"]) == ActionFeedback.GEAR_LEVER
	_gate_held = snapshot["lever_held"]
	_show_gate = not GameData.as_bool(snapshot["sequential_shift"]) and (on_lever or _gate_held or feedback.gate_linger > 0.0)
	if _show_gate:
		var lever_on_screen: Vector2 = _on_screen(camera, cabin.to_global(_lever_at))
		_show_gate = lever_on_screen != Vector2.INF
		_gate_fifth = snapshot["has_fifth"]
		var half: Vector2 = Vector2(1.9 if _gate_fifth else 1.6, 1.9) * _gate_unit * scale_px
		_gate_centre = _keep_inside(lever_on_screen - Vector2(0.0, _gate_lift * scale_px) - half, half * 2.0) + half
		_gate_lever = snapshot["lever"]
		_gate_gear = snapshot["gear"]
		_gate_locked = snapshot["lever_locked"]
	# A word at each control something has just happened at.
	var used: int = 0
	for pulse: ActionFeedback.Pulse in feedback.pulses:
		var said: String = text_of(pulse)
		if said.is_empty() or pulse.age > _toast_s:
			continue
		var where: Vector2 = _on_screen(camera, cabin.control_position(pulse.anchor))
		if pulse.anchor == ActionFeedback.GEAR_LEVER and _show_gate:
			# Over the diagram, not across it.
			where = _gate_centre - Vector2(0.0, 1.9 * _gate_unit * scale_px - _offset.y * scale_px)
		if where == Vector2.INF:
			continue
		var label: Label = _toast(used)
		used += 1
		var share: float = pulse.age / maxf(_toast_s, 0.001)
		var color: Color = _ok_color if pulse.kind == ActionFeedback.KIND_OK else (_fail_color if pulse.kind == ActionFeedback.KIND_MISSED else _text_color)
		label.text = said
		label.add_theme_color_override("font_color", Color(color, clampf((1.0 - share) * 3.0, 0.0, 1.0)))
		label.add_theme_font_size_override("font_size", maxi(roundi(_name_px * scale_px), 8))
		label.add_theme_constant_override("outline_size", maxi(roundi(_name_px * scale_px * 0.25), 2))
		label.reset_size()
		label.position = _keep_inside(where - Vector2(label.size.x * 0.5, label.size.y + (_offset.y + _toast_rise * share) * scale_px), label.size)
		label.visible = true
	for index: int in range(used, _toasts.size()):
		_toasts[index].visible = false

	var ground: ActionFeedback.Pulse = feedback.pulse_at(ActionFeedback.GEAR_LEVER)
	_gate_ground = 1.0 - ground.age / maxf(_toast_s, 0.001) if ground != null and ground.kind == ActionFeedback.KIND_MISSED else 0.0
	queue_redraw()


func _draw() -> void:
	if not _show_gate:
		return
	var scale_px: float = size.y / _reference_height
	var unit: float = _gate_unit * scale_px
	var half: float = _gate_half_width * unit
	var columns: int = 3 if _gate_fifth else 2
	# Gate units to the screen: x toward fifth, y forward is up the screen.
	var middle: Vector2 = _gate_centre + Vector2(unit * (0.0 if _gate_fifth else 0.5), 0.0)
	var plate: Vector2 = Vector2(1.9 if _gate_fifth else 1.6, 1.9) * unit
	draw_rect(Rect2(_gate_centre - plate, plate * 2.0), _back_color)

	var channel: Color = _channel_color.lerp(_fail_color, clampf(_gate_ground, 0.0, 1.0))
	# The neutral channel, then a channel for every column.
	draw_rect(Rect2(middle + Vector2(-unit - half, -half), Vector2(unit * float(columns - 1) + half * 2.0, half * 2.0)), channel)
	for column: int in range(-1, columns - 1):
		var x: float = middle.x + float(column) * unit
		var down: float = half if column == 1 else unit
		draw_rect(Rect2(Vector2(x - half, middle.y - unit), Vector2(half * 2.0, unit + down)), channel)

	# The gears at the ends of their slots; the one engaged is lit.
	var font: Font = get_theme_default_font()
	var font_px: int = maxi(roundi(_name_px * scale_px), 8)
	for gear: int in range(1, (GearGate.MAX_GEAR if _gate_fifth else GearGate.MAX_GEAR - 1) + 1):
		var slot: Vector2 = GearGate.gear_position(gear)
		var at: Vector2 = middle + Vector2(slot.x, -slot.y) * unit
		var lit: bool = gear == _gate_gear
		# Where letting go still finds the gear.
		draw_arc(at, _gate_engage * unit, 0.0, TAU, 24, Color(_ok_color if lit else _slot_color, 0.9 if lit else 0.35), maxf(_gate_line * scale_px * 0.5, 1.0), true)
		var beyond: Vector2 = at + Vector2(0.0, -slot.y * (half + float(font_px) * 0.75))
		draw_string(font, beyond + Vector2(-unit * 0.5, float(font_px) * 0.35), str(gear), HORIZONTAL_ALIGNMENT_CENTER, unit, font_px, _ok_color if lit else _slot_color)
	# Neutral is the bar across: its letter sits on it, lit while he is in it.
	var neutral: Color = _ok_color if _gate_gear == GearGate.NEUTRAL and not _gate_held else _slot_color
	draw_string(font, middle + Vector2(-unit, float(font_px) * 0.35), Lines.get_text("hud.neutral"), HORIZONTAL_ALIGNMENT_CENTER, unit, font_px, neutral)

	# The gear the moment asks for: its slot ringed, beating, and the way
	# there from where the lever is, along the slots.
	if _gate_wanted != GearGate.NEUTRAL and _gate_wanted != _gate_gear:
		var goal: Vector2 = GearGate.gear_position(_gate_wanted)
		var way: PackedVector2Array = [_gate_lever]
		if not is_equal_approx(_gate_lever.x, goal.x):
			way.append(Vector2(_gate_lever.x, 0.0))
			way.append(Vector2(goal.x, 0.0))
		way.append(goal)
		var on_screen: PackedVector2Array = []
		for point: Vector2 in way:
			on_screen.append(middle + Vector2(point.x, -point.y) * unit)
		draw_polyline(on_screen, Color(_ok_color, 0.55), maxf(_gate_line * scale_px, 2.0), true)
		var beat: float = 0.5 + 0.5 * sin(TAU * _time * 1.2)
		draw_arc(middle + Vector2(goal.x, -goal.y) * unit, _gate_engage * unit * (1.2 + 0.5 * beat), 0.0, TAU, 32, Color(_ok_color, 1.0 - 0.4 * beat), maxf(_gate_line * scale_px * 0.8, 2.0), true)

	# The lever: where it is in the gate, ringed while it is in his hand,
	# red while a grind has locked it.
	var knob: Vector2 = middle + Vector2(_gate_lever.x, -_gate_lever.y) * unit
	var radius: float = half * 0.7
	draw_circle(knob, radius, _fail_color if _gate_locked else _lever_color)
	if _gate_held:
		draw_arc(knob, radius + _gate_line * scale_px, 0.0, TAU, 32, _ok_color, maxf(_gate_line * scale_px * 0.6, 1.5), true)


func _size_text(scale_px: float) -> void:
	_name.add_theme_font_size_override("font_size", maxi(roundi(_name_px * scale_px), 8))
	_how.add_theme_font_size_override("font_size", maxi(roundi(_how_px * scale_px), 8))
	_what.add_theme_font_size_override("font_size", maxi(roundi(_how_px * scale_px), 8))
	_guide_text.add_theme_font_size_override("font_size", maxi(roundi(_name_px * scale_px), 8))
	_plate_style.set_corner_radius_all(roundi(_corner * scale_px))
	_plate_style.content_margin_left = _pad.x * scale_px
	_plate_style.content_margin_right = _pad.x * scale_px
	_plate_style.content_margin_top = _pad.y * scale_px
	_plate_style.content_margin_bottom = _pad.y * scale_px


func _toast(index: int) -> Label:
	while _toasts.size() <= index:
		var label: Label = Label.new()
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_color_override("font_outline_color", Color(_back_color, 1.0))
		label.visible = false
		add_child(label)
		_toasts.append(label)
	return _toasts[index]


## Where a point of the world is on the screen (Vector2.INF behind the eye).
func _on_screen(camera: Camera3D, world: Vector3) -> Vector2:
	if camera.is_position_behind(world):
		return Vector2.INF
	return PointerView.shown_at(camera.unproject_position(world), size.x, mirrored)


## The top-left corner that keeps a box of `box` wholly in the view.
func _keep_inside(at: Vector2, box: Vector2) -> Vector2:
	return Vector2(clampf(at.x, 0.0, maxf(size.x - box.x, 0.0)), clampf(at.y, 0.0, maxf(size.y - box.y, 0.0)))

# --- The words ------------------------------------------------------------------

## What a pulse says at its control.
static func text_of(pulse: ActionFeedback.Pulse) -> String:
	match pulse.what:
		ActionFeedback.WHAT_RITUAL:
			return name_of(pulse.hint)
		ActionFeedback.WHAT_MISSED:
			return Lines.format("hint.missed", [how_of(pulse.hint)])
		ActionFeedback.WHAT_GEAR:
			return Lines.format("hint.gear", [str(pulse.gear)])
		ActionFeedback.WHAT_NEUTRAL:
			return Lines.get_text("hint.gear.neutral")
		ActionFeedback.WHAT_GRIND:
			return Lines.get_text("hint.gear.grind")
	return ""


## What the thing does: the effect of the item a ritual belongs to, of the
## item that sits there by itself, or of what a stop offers there.
static func effect_of(hint: Dictionary, snapshot: Dictionary) -> String:
	var item: String = GameData.as_string(hint.get("item"))
	var ritual: String = GameData.as_string(hint.get("ritual"))
	if ritual == StopSim.BUY or ritual == StopSim.PLACE:
		var at: String = str(snapshot["hand_snap"])
		var offers: Array[Dictionary] = snapshot["offers"]
		for offer: Dictionary in offers:
			var kind: StringName = offer["kind"]
			if GameData.as_string(offer["anchor"]) == at and (kind == StopSim.ITEM or kind == StopSim.RESTOCK):
				item = GameData.as_string(offer["id"])
	if item.is_empty() and Lines.has_line("hint.effect." + ritual):
		# A control that is always in the car and does more than its name says.
		return Lines.get_text("hint.effect." + ritual)
	if item.is_empty() or not Lines.has_line("item.%s.effect" % item):
		return ""
	var effect: String = Lines.get_text("item.%s.effect" % item)
	if (ritual == StopSim.BUY or ritual == StopSim.PLACE) and Lines.has_line("item.%s.name" % item):
		# The label's first row says "Buy this": say what "this" is.
		return Lines.format("hint.item.effect", [Lines.get_text("item.%s.name" % item), effect])
	return effect


## What a control is called: its ritual's own line, or the name of the item
## the ritual belongs to; "" when neither is written.
static func name_of(hint: Dictionary) -> String:
	var ritual: String = GameData.as_string(hint.get("ritual"))
	if not ritual.is_empty() and Lines.has_line("hint.ritual." + ritual):
		return Lines.get_text("hint.ritual." + ritual)
	var item: String = GameData.as_string(hint.get("item"))
	if not item.is_empty() and Lines.has_line("item.%s.name" % item):
		return Lines.get_text("item.%s.name" % item)
	return ""


## How it is worked, in words: the gesture, with its time, turns or ways.
static func how_of(hint: Dictionary) -> String:
	var gesture: String = GameData.as_string(hint.get("gesture"))
	if gesture.is_empty():
		return ""
	var id: String = "hint.gesture." + gesture.to_lower()
	if not Lines.has_line(id):
		return ""
	match gesture:
		"HOLD":
			return Lines.format(id, [_number(GameData.as_float(hint.get("amount")))])
		"CRANK":
			return Lines.format(id, [_number(GameData.as_float(hint.get("amount")))])
		"FLICK":
			var ways: PackedStringArray = []
			for dir: Variant in GameData.as_array(hint.get("dirs")):
				ways.append(Lines.get_text("hint.dir." + GameData.as_string(dir)))
			return Lines.format(id, [Lines.get_text("hint.dir.or").join(ways)])
	return Lines.get_text(id)


## 3 for 3.0, 1.2 for 1.2.
static func _number(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(roundi(value))
	return str(snappedf(value, 0.1))
