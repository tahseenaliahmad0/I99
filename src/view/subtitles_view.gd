class_name SubtitlesView
extends CanvasLayer
## Subtitles (GDD 16.6, 13.5; 16.3: "Heckles and lines: subtitles with a
## speaker tag"). Bottom centre, at most two lines of 42 characters under the
## speaker's name, each held for the larger of 1.5 s and 0.06 s per
## character.
##
## The view listens to the Events bus. A `line_requested` (payload "id") is
## looked up in the line table and shown; a line asked for while another is
## showing waits its turn. A line that is showing or waiting already is not
## queued again, and no more than `subtitle_max_waiting` lines wait: for one
## more, the one that has waited longest gives way. SubtitleQueue holds the
## wrapping, the timing and the queue. A row of the line table that holds an
## exchange ("Guest, then Abu Noor" says "... / ...") is shown as what each
## of them says, one after the other, each under its own name.
##
## A `wreck` cuts off what was being said, as it cuts off the picture
## (GDD 3.2): what the Table says about the Wreck is asked for after it and
## is shown at once, and nothing said before the Wreck is left for the
## Telling that follows. clear() does the same for whoever else begins a
## Telling again.
##
## Speaker names are lines themselves (Lines.get_speaker_name). The labels'
## text direction is automatic, so right-to-left text runs the right way when
## Arabic lines arrive, on both lines of a subtitle (LINE_BREAK).
##
## The two Subtitles settings of GDD 17.1 are read from Settings and applied
## the moment they change: `subtitle_size` (small, medium or large) and
## `subtitle_background` (on or off). So is the font slot of the language
## the lines are in (GDD 17.3: `font_en`, `font_ar`); while a slot is empty
## the labels take the theme's font. Every size, margin and colour is in
## data/tuning.json (subtitles_view).
##
## The view changes nothing in the simulation and reads nothing from it: its
## clock is the frames it draws.

const SIZE_SETTING: String = "subtitle_size"
const BACKGROUND_SETTING: String = "subtitle_background"
## A font slot for each language (GDD 17.3): this and the locale's code
## (`font_en`, `font_ar`). The setting holds the path of a font of the
## project for the lines of that language; "" is the theme's own font.
const FONT_SETTING: String = "font_"
## The size shown when the setting names one that tuning does not have
## (a settings file edited by hand): the default of GDD 17.1.
const DEFAULT_SIZE: String = "medium"
## What stands between the two lines of a subtitle in its label: the line
## separator (U+2028). The label breaks the line there and keeps both lines
## in one paragraph. A line end would begin a new paragraph, which takes its
## direction from its own first letter: a right-to-left sentence whose
## second line begins with a Latin word would run the wrong way from there.
const LINE_BREAK: String = "\u2028"

var _tuning: Tuning
var _serial: int = -1
var _queue: SubtitleQueue = SubtitleQueue.new()
## The events this view listens for because a line was to last until them.
var _until_heard: Dictionary = {}
var _shown: SubtitleQueue.Part
var _box: PanelContainer
var _rows: VBoxContainer
var _speaker: Label
var _text: Label
## What the font slot held when it was last read, and the font it named
## (null for the theme's own).
var _font_path: String = ""
var _font: Font


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
	if not Lines.locale_changed.is_connected(_on_locale_changed):
		Lines.locale_changed.connect(_on_locale_changed)


## Shows a line of the line table by its id, after whatever is showing and
## waiting: what a `line_requested` on the Events bus does. `until` names an
## event of the bus that ends the line before its time (the payload's
## "until": a ring written out is over when the call is). A tell (the
## payload's "tell": what announces something a moment ahead, GDD 2.2 pillar
## 4) is shown at once, in front of whatever is showing and waiting.
func say(line_id: String, until: String = "", tell: bool = false) -> void:
	if _tuning == null:
		return
	if not _begin(line_id):
		return
	if not until.is_empty() and not _listen_for(until):
		until = ""
	for said: PackedStringArray in SubtitleQueue.exchange(Lines.get_speaker(line_id), Lines.get_text(line_id)):
		_queue.push(Lines.get_speaker_name(said[0]), said[1], until, tell)


## Listens for an event that ends lines early; false if the bus has none of
## that name (the line then simply runs its time).
func _listen_for(event_name: String) -> bool:
	if _until_heard.has(event_name):
		return true
	if not Events.NAMES.has(event_name):
		push_error("Subtitles: a line is to last until '%s', which is not a signal on the bus (GDD 13.6)" % event_name)
		return false
	Events.connect(event_name, _on_until.bind(event_name))
	_until_heard[event_name] = true
	return true


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
	return _text.text.split(LINE_BREAK)


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


## Whether a line that is asked for is to be said: not one the line table
## does not have (an error), and not one that is showing or waiting already.
## A line that is makes room for itself among those that wait
## (SubtitleQueue.begin_line).
func _begin(line_id: String) -> bool:
	if not Lines.has_line(line_id):
		push_error("Subtitles: a line was asked for that the line table does not have: '%s'" % line_id)
		return false
	return _queue.begin_line(line_id)


func _show(part: SubtitleQueue.Part) -> void:
	if _box == null or is_same(part, _shown):
		return
	_shown = part
	_box.visible = part != null
	if part == null:
		return
	_speaker.text = part.speaker
	_speaker.visible = not part.speaker.is_empty()
	_text.text = LINE_BREAK.join(part.lines)


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
	_apply_font()


## The font slot of the language the lines are in (GDD 17.3): both labels
## take the font it names. An empty slot leaves them the theme's font, and
## so does one that names no font.
func _apply_font() -> void:
	var face: Font = _slot_font(FONT_SETTING + Lines.locale)
	for label: Label in [_speaker, _text]:
		if face == null:
			label.remove_theme_font_override("font")
		else:
			label.add_theme_font_override("font", face)


## The font a font slot names, null for the theme's own. The theme's font
## stands behind it for the letters it does not have: a line the writer has
## not come to yet is shown in English, whatever the font of the language.
func _slot_font(slot: String) -> Font:
	var path: String = GameData.as_string(Settings.get_value(slot)) if Settings.has_setting(slot) else ""
	if path == _font_path:
		return _font
	_font_path = path
	_font = null
	if path.is_empty():
		return null
	var font: Font = load(path) as Font if ResourceLoader.exists(path, "Font") else null
	if font == null:
		push_warning("Subtitles: the setting '%s' names no font ('%s'); showing the theme's" % [slot, path])
		return null
	var behind: Array[Font] = [_text.get_theme_default_font()]
	var face: FontVariation = FontVariation.new()
	face.base_font = font
	face.fallbacks = behind
	_font = face
	return _font


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
	say(GameData.as_string(data.get("id")), GameData.as_string(data.get("until")), GameData.as_bool(data.get("tell")))


## What was to last until this event is over now.
func _on_until(_data: Dictionary, event_name: String) -> void:
	_queue.drop(event_name)
	_show(_queue.current())


func _on_wreck(_data: Dictionary) -> void:
	clear()


func _on_setting_changed(key: String, _value: Variant) -> void:
	if _tuning != null and (key == SIZE_SETTING or key == BACKGROUND_SETTING or key.begins_with(FONT_SETTING)):
		_apply_settings()


func _on_locale_changed(_locale: String) -> void:
	if _tuning != null:
		_apply_font()
