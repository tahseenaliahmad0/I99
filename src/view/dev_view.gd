class_name DevView
extends Control
## The dev menu (D-073), over the title when the game is started with
## `--dev`: every part of the game one click away, with the cabin, the act,
## the seed and the driver it is to be tried with.
##
## It builds a DriveContext and hands it to Game.go, as the wedding room
## does for a Table; the drive scene reads from it what `--leg=`, `--boss=`,
## `--give=`, `--ride=` and `--bot=` give on the command line. Nothing here
## is for a player: it is drawn with the engine's own controls and typed in.

signal closed

const KEY_ACT: String = "act"
const KEY_BOT: String = "bot"
const KEY_SEED: String = "seed"
const KEY_GIVE: String = "give"
const KEY_RIDE: String = "ride"
const KEY_CASH: String = "cash"
const KEY_MODIFIER: String = "modifier"
const KEY_BOSS_MODIFIER: String = "boss_modifier"
## The Table a stop or a set piece is tried at.
const DEFAULT_TABLE: String = "drivers"

var _scale: float = 1.0
var _rows: VBoxContainer


func setup() -> void:
	_scale = get_viewport_rect().size.y / 1080.0
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var data: GameData = Game.data
	var shade: ColorRect = ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.05, 0.05, 0.07, 1.0)
	add_child(shade)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 60.0 * _scale
	scroll.offset_top = 30.0 * _scale
	scroll.offset_right = -60.0 * _scale
	scroll.offset_bottom = -30.0 * _scale
	add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", roundi(10.0 * _scale))
	scroll.add_child(_rows)

	_label(Lines.get_text("dev.heading"), 1.3)

	# What it is tried with.
	_label(Lines.get_text("dev.options"), 0.75)
	var options: HFlowContainer = _flow()
	_choice(options, "dev.option.act", KEY_ACT, ["1", "2", "3"], ["1", "2", "3"])
	var bots: PackedStringArray = [""]
	var bot_names: PackedStringArray = [Lines.get_text("dev.option.bot.off")]
	for skill: String in DriverBot.SKILLS:
		bots.append(skill)
		bot_names.append(skill)
	_choice(options, "dev.option.bot", KEY_BOT, bots, bot_names)
	var riders: PackedStringArray = [""]
	var rider_names: PackedStringArray = [Lines.get_text("dev.option.none")]
	for passenger: Dictionary in data.records("passengers"):
		riders.append(GameData.as_string(passenger.get("id")))
		rider_names.append(GameData.as_string(passenger.get("id")))
	_choice(options, "dev.option.ride", KEY_RIDE, riders, rider_names)
	var modifiers: PackedStringArray = [""]
	var modifier_names: PackedStringArray = [Lines.get_text("dev.option.none")]
	for modifier: Dictionary in data.records("modifiers"):
		modifiers.append(GameData.as_string(modifier.get("id")))
		modifier_names.append(GameData.as_string(modifier.get("id")))
	_choice(options, "dev.option.modifier", KEY_MODIFIER, modifiers, modifier_names)
	var boss_modifiers: PackedStringArray = [""]
	var boss_modifier_names: PackedStringArray = [Lines.get_text("dev.option.none")]
	for boss: Dictionary in data.records("bosses"):
		for modifier: Variant in GameData.as_array(boss.get("modifiers")):
			boss_modifiers.append(GameData.as_string(modifier))
			boss_modifier_names.append("%s (%s)" % [GameData.as_string(modifier), GameData.as_string(boss.get("id"))])
	_choice(options, "dev.option.boss_modifier", KEY_BOSS_MODIFIER, boss_modifiers, boss_modifier_names)
	_field(options, "dev.option.seed", KEY_SEED, 120.0)
	_field(options, "dev.option.cash", KEY_CASH, 100.0)
	_field(options, "dev.option.give", KEY_GIVE, 420.0)

	_label(Lines.get_text("dev.section.flow"), 0.9)
	var flow: HFlowContainer = _flow()
	_button(flow, Lines.get_text("dev.go.prologue"), _go_prologue)
	_button(flow, Lines.get_text("dev.go.wedding"), _go_wedding)

	_label(Lines.get_text("dev.section.tables"), 0.9)
	var tables: HFlowContainer = _flow()
	for table: Dictionary in data.records("tables"):
		var id: String = GameData.as_string(table.get("id"))
		_button(tables, id, _go.bind({"table": id}))

	_label(Lines.get_text("dev.section.legs"), 0.9)
	var legs: HFlowContainer = _flow()
	for leg: Dictionary in data.records("legs"):
		_button(legs, GameData.as_string(leg.get("id")), _go_leg.bind(GameData.as_string(leg.get("id"))))

	_label(Lines.get_text("dev.section.bosses"), 0.9)
	var bosses: HFlowContainer = _flow()
	for boss: Dictionary in data.records("bosses"):
		_button(bosses, GameData.as_string(boss.get("id")), _go_boss.bind(GameData.as_string(boss.get("id"))))
	_button(bosses, Lines.get_text("dev.go.arrival"), _go.bind({"boss": BossSim.ARRIVAL}))

	_label(Lines.get_text("dev.section.stops"), 0.9)
	var stops: HFlowContainer = _flow()
	for stop: Dictionary in data.records("stops"):
		var id: String = GameData.as_string(stop.get("id"))
		_button(stops, id, _go.bind({"stop": id, "table": DEFAULT_TABLE}))

	_label(Lines.get_text("dev.section.tools"), 0.9)
	var tools: HFlowContainer = _flow()
	_button(tools, Lines.get_text("dev.tuning"), _open_tuning)
	_button(tools, Lines.get_text("dev.back"), _close)
	var keys: Label = _label(Lines.get_text("dev.keys"), 0.65)
	keys.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	print("[dev] menu ready")


# --- Going somewhere --------------------------------------------------------------

## The DriveContext: what was chosen above, and `extra` on top of it.
func context(extra: Dictionary) -> Dictionary:
	var out: Dictionary = {"dev": true, "seed": _option(KEY_SEED, "1")}
	for key: String in [KEY_BOT, KEY_GIVE, KEY_RIDE, KEY_CASH]:
		var value: String = _option(key, "")
		if not value.is_empty():
			out[key] = value
	out.merge(extra, true)
	return out


func _go(extra: Dictionary) -> void:
	Game.dev_return = true
	Game.go(Game.AppState.TELLING, context(extra))


func _go_leg(leg_id: String) -> void:
	var spec: String = "%s,%s" % [leg_id, _option(KEY_ACT, "1")]
	var modifier: String = _option(KEY_MODIFIER, "")
	if not modifier.is_empty():
		spec += "," + modifier
	_go({"leg": spec})


func _go_boss(boss_id: String) -> void:
	var spec: String = boss_id
	var modifier: String = _option(KEY_BOSS_MODIFIER, "")
	if not modifier.is_empty() and GameData.as_array(Game.data.record("bosses", boss_id).get("modifiers")).has(modifier):
		spec += "," + modifier
	_go({"boss": spec})


func _go_prologue() -> void:
	Game.dev_return = true
	var first: PackedStringArray = TableRules.open_at_start(Game.data)
	Game.go(Game.AppState.PROLOGUE, context({"prologue": true, "table": first[0] if not first.is_empty() else DEFAULT_TABLE}))


func _go_wedding() -> void:
	Game.dev_return = false
	Game.go(Game.AppState.WEDDING)


func _open_tuning() -> void:
	var panel: TuningPanel = TuningPanel.new()
	add_child(panel)
	panel.setup()
	panel.closed.connect(panel.queue_free)


func _close() -> void:
	Game.dev_return = false
	closed.emit()


# --- The controls -------------------------------------------------------------------

func _option(key: String, fallback: String) -> String:
	return GameData.as_string(Game.dev_options.get(key), fallback)


func _label(text: String, size: float) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", roundi(Game.data.tuning.f("menu_font_size") * size * _scale))
	_rows.add_child(label)
	return label


func _flow() -> HFlowContainer:
	var flow: HFlowContainer = HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", roundi(14.0 * _scale))
	flow.add_theme_constant_override("v_separation", roundi(8.0 * _scale))
	_rows.add_child(flow)
	return flow


func _font(control: Control, size: float = 0.75) -> void:
	control.add_theme_font_size_override("font_size", roundi(Game.data.tuning.f("menu_font_size") * size * _scale))


func _button(parent: Control, text: String, pressed: Callable) -> void:
	var button: Button = Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	_font(button)
	button.pressed.connect(pressed)
	parent.add_child(button)


func _choice(parent: Control, line_id: String, key: String, values: PackedStringArray, names: PackedStringArray) -> void:
	var box: HBoxContainer = HBoxContainer.new()
	var label: Label = Label.new()
	label.text = Lines.get_text(line_id)
	_font(label, 0.65)
	box.add_child(label)
	var pick: OptionButton = OptionButton.new()
	pick.focus_mode = Control.FOCUS_NONE
	_font(pick, 0.65)
	for index: int in values.size():
		pick.add_item(names[index])
		if values[index] == _option(key, values[0]):
			pick.select(index)
	pick.item_selected.connect(func(index: int) -> void: Game.dev_options[key] = values[index])
	box.add_child(pick)
	parent.add_child(box)


func _field(parent: Control, line_id: String, key: String, width: float) -> void:
	var box: HBoxContainer = HBoxContainer.new()
	var label: Label = Label.new()
	label.text = Lines.get_text(line_id)
	_font(label, 0.65)
	box.add_child(label)
	var edit: LineEdit = LineEdit.new()
	edit.text = _option(key, "")
	edit.custom_minimum_size = Vector2(width * _scale, 0.0)
	_font(edit, 0.65)
	edit.text_changed.connect(func(text: String) -> void: Game.dev_options[key] = text.strip_edges())
	box.add_child(edit)
	parent.add_child(box)
