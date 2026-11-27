class_name TouchView
extends Control
## What touch draws on the glass (GDD 4.1, 17.4): the pause's hotspot in the
## top-left corner, always (a mouse can click it too), and the brake's pedal
## zone at the bottom left once a finger has been on the glass. Reads the
## touch input; changes nothing.

var _touch: TouchInput
var _color: Color = Color.WHITE
## Dots per inch of the glass in the view's own pixels (the drive scene says).
var dpi: float = 96.0


func setup(factory: PlaceholderFactory, touch: TouchInput) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_touch = touch
	_color = factory.color_of("ui_pointer")
	dpi = float(DisplayServer.screen_get_dpi())


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if _touch == null:
		return
	var faint: Color = Color(_color, 0.35)
	# The hotspot: two bars, as a pause is drawn.
	var hotspot: Rect2 = _touch.hotspot(size, dpi)
	var bar: Vector2 = Vector2(hotspot.size.x * 0.12, hotspot.size.y * 0.4)
	var centre: Vector2 = hotspot.get_center()
	draw_rect(Rect2(centre + Vector2(-bar.x * 1.6, -bar.y * 0.5), bar), faint)
	draw_rect(Rect2(centre + Vector2(bar.x * 0.6, -bar.y * 0.5), bar), faint)
	if not _touch.active:
		return
	# The pedal zone: an outline, filled while his foot is on it.
	var zone: Rect2 = _touch.pedal_zone(size, dpi)
	draw_rect(zone, Color(_color, 0.25 if _touch.braking() else 0.08))
	draw_rect(zone, faint, false, 2.0)
