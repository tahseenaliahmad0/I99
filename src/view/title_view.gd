class_name TitleView
extends Control
## TITLE (GDD 13.4): the game's name and where to go from it. Every entry is
## clicked with the left button: the menus need one hand and no keyboard
## (GDD 17.4).
##
##   Begin / Continue   the prologue on first launch, else the wedding
##   The prologue       plays it again (GDD 10.1: "can be replayed from the
##                      title")
##   Options            the settings of GDD 17.1
##   Quit

var _entries: VBoxContainer


func _ready() -> void:
	Game.state = Game.AppState.TITLE
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var tuning: Tuning = Game.data.tuning
	var scale_by: float = get_viewport_rect().size.y / 1080.0

	var backdrop: ColorRect = ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color.BLACK
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	_entries = VBoxContainer.new()
	_entries.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_entries.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_entries.grow_vertical = Control.GROW_DIRECTION_BOTH
	_entries.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(_entries)

	var heading: Label = Label.new()
	heading.text = Lines.get_text("title.game_name")
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", roundi(tuning.f("menu_heading_font_size") * 1.5 * scale_by))
	_entries.add_child(heading)
	var under: Label = Label.new()
	under.text = Lines.get_text("title.subtitle")
	under.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	under.add_theme_font_size_override("font_size", roundi(tuning.f("menu_font_size") * scale_by))
	_entries.add_child(under)
	var gap: Control = Control.new()
	gap.custom_minimum_size = Vector2(0.0, tuning.f("menu_font_size") * 2.0 * scale_by)
	_entries.add_child(gap)

	var seen: bool = not Game.wants_prologue()
	_add_entry("title.continue" if seen else "title.begin", Game.begin, scale_by)
	if seen:
		_add_entry("title.prologue", Game.play_prologue, scale_by)
	_add_entry("title.options", _open_options, scale_by)
	_add_entry("title.quit", _quit, scale_by)
	print("[title] ready entries=%d first_launch=%s" % [_entries.get_child_count() - 3, str(not seen)])


func _add_entry(line_id: String, pressed: Callable, scale_by: float) -> void:
	var button: Button = Button.new()
	button.text = Lines.get_text(line_id)
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", roundi(Game.data.tuning.f("menu_font_size") * 1.3 * scale_by))
	button.pressed.connect(pressed)
	_entries.add_child(button)


## The settings of GDD 17.1, over the title; closed, the title is back.
func _open_options() -> void:
	var options: SettingsView = SettingsView.new()
	add_child(options)
	options.setup()
	options.closed.connect(options.queue_free)


func _quit() -> void:
	get_tree().quit()
