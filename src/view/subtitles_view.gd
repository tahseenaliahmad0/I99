class_name SubtitlesView
extends CanvasLayer
## Subtitles (GDD 16.6, 13.5; 16.3: "Heckles and lines: subtitles with a
## speaker tag"). Bottom centre, at most two lines of 42 characters under the
## speaker's name, each held for the larger of 1.5 s and 0.06 s per
## character.
##
## The view listens to the Events bus. A `line_requested` (payload "id") is
## looked up in the line table and shown; a line asked for while another is
## showing waits its turn. SubtitleQueue holds the wrapping, the timing and
## the queue. A row of the line table that holds an exchange ("Guest, then
## Abu Noor" says "... / ...") is shown as what each of them says, one after
## the other, each under its own name.
##
## A `wreck` cuts off what was being said, as it cuts off the picture
## (GDD 3.2): what the Table says about the Wreck is asked for after it and
## is shown at once, and nothing said before the Wreck is left for the
## Telling that follows. clear() does the same for whoever else begins a
## Telling again.
##
## Speaker names are lines themselves (Lines.get_speaker_name). The labels'
## text direction is automatic, so right-to-left text runs the right way when
## Arabic lines arrive; they take the theme's font, whatever it comes to be.
##
## The two Subtitles settings of GDD 17.1 are read from Settings and applied
## the moment they change: `subtitle_size` (small, medium or large) and
## `subtitle_background` (on or off). Every size, margin and colour is in
## data/tuning.json (subtitles_view).
##
## The view changes nothing in the simulation and reads nothing from it: its
## clock is the frames it draws.

const SIZE_SETTING: String = "subtitle_size"
const BACKGROUND_SETTING: String = "subtitle_background"
## The size shown when the setting names one that tuning does not have
## (a settings file edited by hand): the default of GDD 17.1.
const DEFAULT_SIZE: String = "medium"

var _tuning: Tuning
var _serial: int = -1
var _queue: SubtitleQueue = SubtitleQueue.new()
var _shown: SubtitleQueue.Part
var _box: PanelContainer
var _rows: VBoxContainer
var _speaker: Label
var _text: Label


func setup(data: GameData) -> void:
	_tuning = data.tuning
	if _box != null:
		# Set up before: only the numbers are read again.
		_configure()
		return

	# The box hangs from a point at the bottom centre of the screen and
	# grows from there to fit what it holds: sideways both ways, and upward.
	_box = PanelContainer.new()
	_box.name = "Box"
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_box.visible = false
	add_child(_box)
	_rows = VBoxContainer.new()
	_rows.name = "Rows"
	_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(_rows)
	_speaker = _make_label("Speaker")
	_text = _make_label("Text")
	_configure()

	if not Events.line_requested.is_connected(_on_line_requested):
		Events.line_requested.connect(_on_line_requested)
	if not Events.wreck.is_connected(_on_wreck):
		Events.wreck.connect(_on_wreck)
	if not Settings.changed.is_connected(_on_setting_changed):
		Settings.changed.connect(_on_setting_changed)


## Shows a line of the line table by its id, after whatever is showing and
## waiting: what a `line_requested` on the Events bus does.
func say(line_id: String) -> void:
	if _tuning == null:
		return
	if not Lines.has_line(line_id):
		push_error("Subtitles: a line was asked for that the line table does not have: '%s'" % line_id)
		return
	for said: PackedStringArray in SubtitleQueue.exchange(Lines.get_speaker(line_id), Lines.get_text(line_id)):
		_queue.push(Lines.get_speaker_name(said[0]), said[1])


## Nothing is showing and nothing waits: a Telling begins again.
func clear() -> void:
	_queue.clear()
	_show(null)


## True while a subtitle is on screen.
func is_showing() -> bool:
	return _box != null and _box.visible


## The speaker tag on screen ("" when nothing is showing, or nobody is named).
func shown_speaker() -> String:
	if not is_showing() or not _speaker.visible:
		return ""
	return _speaker.text


## The lines on screen, as the label holds them (none when nothing is showing).
func shown_lines() -> PackedStringArray:
	if not is_showing():
		return PackedStringArray()
	return _text.text.split("\n")


## Subtitles showing and waiting.
func waiting() -> int:
	return _queue.size()


func _process(delta: float) -> void:
	if _tuning == null:
		return
	if _tuning.changed_serial != _serial:
		_configure()
	_queue.advance(delta)
	_show(_queue.current())


func _show(part: SubtitleQueue.Part) -> void:
	if _box == null or is_same(part, _shown):
		return
	_shown = part
	_box.visible = part != null
	if part == null:
		return
	_speaker.text = part.speaker
	_speaker.visible = not part.speaker.is_empty()
	_text.text = "\n".join(part.lines)


func _make_label(node_name: String) -> Label:
	var label: Label = Label.new()
	label.name = node_name
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Right-to-left text runs the right way when Arabic lines arrive (GDD 16.6).
	label.text_direction = Control.TEXT_DIRECTION_AUTO
	_rows.add_child(label)
	return label


## Reads the numbers (again when the tuning panel has changed one) and
## dresses the box and its labels with them.
func _configure() -> void:
	_serial = _tuning.changed_serial
	_queue.configure(_tuning)
	var margin: float = _tuning.f("subtitle_bottom_margin")
	_box.offset_left = 0.0
	_box.offset_right = 0.0
	_box.offset_top = -margin
	_box.offset_bottom = -margin
	_rows.add_theme_constant_override("separation", _tuning.i("subtitle_speaker_gap"))
	_text.add_theme_constant_override("line_spacing", _tuning.i("subtitle_line_spacing"))
	_speaker.add_theme_color_override("font_color", Color.html(_tuning.s("subtitle_speaker_color")))
	_text.add_theme_color_override("font_color", Color.html(_tuning.s("subtitle_text_color")))
	var outline: Color = Color.html(_tuning.s("subtitle_outline_color"))
	_speaker.add_theme_color_override("font_outline_color", outline)
	_text.add_theme_color_override("font_outline_color", outline)
	_apply_settings()


## The Subtitles settings of GDD 17.1: the size of the letters, and whether
## they stand on a background.
func _apply_settings() -> void:
	var sizes: Dictionary = _tuning.d("subtitle_font_sizes")
	var size_name: String = GameData.as_string(Settings.get_value(SIZE_SETTING))
	if not sizes.has(size_name):
		push_warning("Subtitles: the setting '%s' names no size ('%s'); showing %s" % [SIZE_SETTING, size_name, DEFAULT_SIZE])
		size_name = DEFAULT_SIZE
	var text_size: int = GameData.as_int(sizes.get(size_name))
	var speaker_size: int = roundi(float(text_size) * _tuning.f("subtitle_speaker_scale"))
	var outline_share: float = _tuning.f("subtitle_outline_share")
	_text.add_theme_font_size_override("font_size", text_size)
	_text.add_theme_constant_override("outline_size", roundi(float(text_size) * outline_share))
	_speaker.add_theme_font_size_override("font_size", speaker_size)
	_speaker.add_theme_constant_override("outline_size", roundi(float(speaker_size) * outline_share))
	_box.add_theme_stylebox_override("panel", _background(GameData.as_bool(Settings.get_value(BACKGROUND_SETTING))))


## What the text stands on. The room around the text is the same with the
## background and without it: turning it off moves nothing.
func _background(shown: bool) -> StyleBox:
	var box: StyleBox = StyleBoxEmpty.new()
	if shown:
		var flat: StyleBoxFlat = StyleBoxFlat.new()
		var color: Color = Color.html(_tuning.s("subtitle_background_color"))
		color.a = _tuning.f("subtitle_background_alpha")
		flat.bg_color = color
		flat.set_corner_radius_all(_tuning.i("subtitle_corner_radius"))
		box = flat
	var sideways: float = _tuning.fi("subtitle_padding", 0)
	var upright: float = _tuning.fi("subtitle_padding", 1)
	box.content_margin_left = sideways
	box.content_margin_right = sideways
	box.content_margin_top = upright
	box.content_margin_bottom = upright
	return box


func _on_line_requested(data: Dictionary) -> void:
	say(GameData.as_string(data.get("id")))


func _on_wreck(_data: Dictionary) -> void:
	clear()


func _on_setting_changed(key: String, _value: Variant) -> void:
	if _tuning != null and (key == SIZE_SETTING or key == BACKGROUND_SETTING):
		_apply_settings()
