class_name PrologueView
extends Control
## What the prologue adds to the picture (GDD 10.1): the pulse on the object
## whose turn it is, the white-out of its last step with the title card,
## and the card that says how long ago that was once tonight has begun.
## Also the black of a Wreck's cut (GDD 3.2: "the screen cuts to black").
##
## It reads the snapshot and draws; it changes nothing.

var _pulse_at: Vector2 = Vector2.ZERO
var _pulsing: bool = false
var _time: float = 0.0
var _white: float = 0.0
var _black: bool = false
var _card: Label
var _card_left: float = 0.0
var _was_prologue: bool = false
var _pulse_color: Color = Color.WHITE
var _pulse_radius: float = 0.0
var _pulse_period: float = 1.0
var _card_seconds: float = 0.0
var _anchor_pos: Dictionary = {}


func setup(data: GameData, factory: PlaceholderFactory) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tuning: Tuning = data.tuning
	_pulse_color = factory.color_of("prologue_pulse")
	_pulse_radius = factory.size_of("prologue_pulse").x
	_pulse_period = tuning.f("prologue_pulse_period")
	_card_seconds = tuning.f("prologue_card_s")
	for anchor: Dictionary in data.records("anchors"):
		_anchor_pos[GameData.as_string(anchor.get("id"))] = GameData.as_vec3(anchor.get("pos"))
	_card = Label.new()
	_card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_card.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_card.add_theme_font_size_override("font_size", tuning.i("title_card_font_size"))
	_card.visible = false
	add_child(_card)


func apply(snapshot: Dictionary, camera: Camera3D, cabin: Node3D, delta: float) -> void:
	_time += delta
	var step: int = GameData.as_int(snapshot["prologue_step"])
	var prompt: String = str(snapshot["prologue_prompt"])
	var moves: Dictionary = snapshot["anchor_moves"]
	_pulsing = step > 0 and not prompt.is_empty() and (_anchor_pos.has(prompt) or moves.has(prompt))
	if _pulsing:
		var at: Vector3 = GameData.as_vec3(moves[prompt]) if moves.has(prompt) else _anchor_pos[prompt]
		var world: Vector3 = cabin.to_global(at)
		_pulsing = not camera.is_position_behind(world)
		_pulse_at = camera.unproject_position(world)
	_white = GameData.as_float(snapshot["prologue_lift"]) if step > 0 else 0.0
	_black = GameData.as_bool(snapshot["wrecked"]) and GameData.as_bool(snapshot["telling"])
	if _was_prologue and step == 0:
		# The cut to tonight: how long ago that morning was.
		_card_left = _card_seconds
		_card.text = Lines.get_text("title.card.tonight")
		_card.add_theme_color_override("font_color", Color.WHITE)
	_was_prologue = step > 0
	if step > 0:
		# "The screen whites out. Title card."
		_card.text = Lines.get_text("title.card.prologue")
		_card.add_theme_color_override("font_color", Color(0.0, 0.0, 0.0, clampf((_white - 0.6) / 0.3, 0.0, 1.0)))
		_card.visible = _white > 0.6
	else:
		_card_left = maxf(_card_left - delta, 0.0)
		_card.visible = _card_left > 0.0
	queue_redraw()


func _draw() -> void:
	if _black:
		draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
		return
	if _pulsing:
		var beat: float = 0.5 + 0.5 * sin(TAU * _time / maxf(_pulse_period, 0.01))
		var radius: float = _pulse_radius * size.y * (1.0 + 0.5 * beat)
		draw_arc(_pulse_at, radius, 0.0, TAU, 48, Color(_pulse_color, 1.0 - 0.5 * beat), maxf(size.y * 0.005, 2.0), true)
	if _white > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1.0, 1.0, 1.0, _white))
