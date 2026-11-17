class_name PointerView
extends Control
## The game's own pointer (GDD 4.1, 4.2): the mouse is captured, so the
## pointer is drawn here, at the spot of the cabin it points at. It hides
## while the hand is on the wheel or busy with a gesture, and shows the
## progress of a HOLD or CRANK as an arc. Reads the snapshot; changes nothing.

var _pointer_color: Color = Color.WHITE
var _progress_color: Color = Color.WHITE
var _pointer_radius: float = 0.0
var _progress_radius: float = 0.0
var _ring_width: float = 1.0

var _visible_pointer: bool = false
var _at: Vector2 = Vector2.ZERO
var _progress: float = 0.0
var _progress_at: Vector2 = Vector2.ZERO


func setup(data: GameData, factory: PlaceholderFactory) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pointer_color = factory.color_of("ui_pointer")
	_progress_color = factory.color_of("ui_progress")
	_pointer_radius = factory.size_of("ui_pointer").x * 0.5
	_progress_radius = factory.size_of("ui_progress").x * 0.5
	_ring_width = data.tuning.f("pointer_ring_width")


func apply(snapshot: Dictionary, camera: Camera3D, cabin: Node3D) -> void:
	var point: Vector3 = snapshot["pointer_point"]
	var world: Vector3 = cabin.to_global(point)
	_visible_pointer = snapshot["pointer_visible"] and not camera.is_position_behind(world)
	if _visible_pointer:
		_at = camera.unproject_position(world)
	_progress = snapshot["gesture_progress"]
	var hand: Vector3 = snapshot["hand_pos"]
	var hand_world: Vector3 = cabin.to_global(hand)
	if camera.is_position_behind(hand_world):
		_progress = 0.0
	else:
		_progress_at = camera.unproject_position(hand_world)
	queue_redraw()


func _draw() -> void:
	if _visible_pointer:
		draw_arc(_at, _pointer_radius, 0.0, TAU, 32, _pointer_color, _ring_width, true)
	if _progress > 0.0 and _progress < 1.0:
		draw_arc(_progress_at, _progress_radius, -PI * 0.5, -PI * 0.5 + TAU * _progress, 48, _progress_color, _ring_width * 2.0, true)
