class_name WeddingView
extends Node3D
## The wedding (GDD 3.2, 13.4): "The wedding party is the menu. It is a room
## of Tables. Walking the pointer to a Table and sitting starts a Telling
## under that Table's rules."
##
## One scene for four states of the application:
##   WEDDING   the room: the seven Tables, open or not, and the doors of the
##             two modes
##   ENDING    what the night he has just told left behind (GDD 11.4, 11.5)
##   FINALE    "One Hand" (GDD 10.6), driven by FinaleSim
##   CREDITS   after it
##
## Everything is done with the pointer and the left button (GDD 17.4).
## Started by itself, `--ending=` shows a state to look at (see Game).

const ROOM: int = 0
const ENDING: int = 1
const FINALE: int = 2
const PROVERB: int = 3
const CREDITS: int = 4

var _mode: int = ROOM
var _data: GameData
var _factory: PlaceholderFactory
var _camera: Camera3D
## Each place the pointer can go: { "kind": "table" or "mode", "id", "at":
## Vector3, "open": bool, "node": Node3D }.
var _places: Array[Dictionary] = []
var _hover: int = -1
var _greeted: Dictionary = {}
var _highlight: Node3D
var _heading: Label
var _panel: Label
var _card: Label
var _shade: ColorRect
var _back: Button
var _subtitles: SubtitlesView
var _pick_radius: float = 0.0
## Where the pointer is, as its last motion said (in the viewport's own
## coordinates).
var _pointer: Vector2 = Vector2.ZERO
var _scale: float = 1.0

# --- The finale ----------------------------------------------------------------
var _finale: FinaleSim
var _walkers: Node3D
var _noor: Node3D
var _palm: Node3D
var _groom: Node3D
var _walk_from: Vector3 = Vector3.ZERO
var _walk_to: Vector3 = Vector3.ZERO
var _palm_radius: float = 0.0
var _clap_left: float = 0.0
var _clap_period: float = 1.0
var _proverb_shown: float = 0.0


func _ready() -> void:
	_data = Game.data
	_factory = PlaceholderFactory.new(_data)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var tuning: Tuning = _data.tuning
	_scale = get_viewport().get_visible_rect().size.y / 1080.0
	_pick_radius = tuning.f("wedding_pick_radius")
	_palm_radius = tuning.f("finale_palm_radius")
	_clap_period = tuning.f("finale_clap_period")
	_build_room()
	_build_ui()

	var asked: String = str(Game.args.get("ending", ""))
	if asked == "finale":
		_begin_finale()
	elif asked == "credits":
		_show_credits()
	elif not asked.is_empty():
		# An ending to look at: as a first win at that Table would leave it.
		var table_id: String = str(Game.args.get("table", "children"))
		var looked_at: Dictionary = Save.new_profile(_data)
		var result: Dictionary = Save.apply_ending(_data, looked_at, {"table": table_id, "late": asked == Save.LATE, "call": asked == Save.THE_CALL, "guest": "drummer"})
		result["table"] = table_id
		result["clock"] = "05:41" if asked != Save.LATE else "06:20"
		_show_ending(result)
	elif not Game.last_ending.is_empty():
		_show_ending(Game.last_ending)
	else:
		_enter_room()
	print("[wedding] ready tables=%d open=%d state=%s" % [_data.records("tables").size(), _open_tables(), Game.state_name()])


# --- The room ---------------------------------------------------------------------

func _build_room() -> void:
	var tuning: Tuning = _data.tuning
	_camera = Camera3D.new()
	_camera.fov = tuning.f("wedding_fov")
	add_child(_camera)
	_camera.position = _vec3(tuning.a("wedding_camera"))
	_camera.look_at(_vec3(tuning.a("wedding_look_at")))
	_camera.current = true
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55.0, 30.0, 0.0)
	add_child(light)
	var floor_node: Node3D = _factory.make("wedding_floor")
	floor_node.position = Vector3(0.0, -_factory.size_of("wedding_floor").y * 0.5, 0.0)
	add_child(floor_node)
	var wall: Node3D = _factory.make("wedding_wall")
	wall.position = Vector3(0.0, _factory.size_of("wedding_wall").y * 0.5, -_factory.size_of("wedding_floor").z * 0.5)
	add_child(wall)
	_highlight = _factory.make("wedding_highlight")
	_highlight.visible = false
	add_child(_highlight)

	var ring: float = tuning.f("wedding_guest_ring")
	var seats: int = tuning.i("wedding_guests_per_table")
	for table: Dictionary in _data.records("tables"):
		var id: String = GameData.as_string(table.get("id"))
		var spot: Array = GameData.as_array(table.get("room_pos"))
		var at: Vector3 = Vector3(GameData.as_float(spot[0]) if spot.size() > 0 else 0.0, 0.0, GameData.as_float(spot[1]) if spot.size() > 1 else 0.0)
		var open: bool = TableRules.unlocked(Game.profile, id)
		var top: Node3D = _factory.make("wedding_table" if open else "wedding_table_locked")
		top.position = at + Vector3(0.0, _factory.size_of("wedding_table").y * 0.5, 0.0)
		add_child(top)
		var guest_id: String = "wedding_guest_%s" % id if _factory.has("wedding_guest_%s" % id) else "wedding_guest"
		for seat: int in seats:
			# Guests sit around the far side of their Table, facing the room.
			var angle: float = PI + PI * (float(seat) + 0.5) / float(seats)
			var guest: Node3D = _factory.make(guest_id)
			guest.position = at + Vector3(cos(angle) * ring, _factory.size_of(guest_id).y * 0.5, sin(angle) * ring)
			add_child(guest)
		var sign: Label3D = Label3D.new()
		sign.text = Lines.get_text("table.%s.name" % id)
		sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sign.pixel_size = 0.006
		sign.modulate = Color.WHITE if open else Color(0.6, 0.6, 0.6)
		sign.position = at + Vector3(0.0, _factory.size_of("wedding_table").y + 1.4, 0.0)
		add_child(sign)
		_places.append({"kind": "table", "id": id, "at": at + Vector3(0.0, _factory.size_of("wedding_table").y, 0.0), "open": open})
	# Whoever he has carried to Basra stands with the party.
	var guests: Array = GameData.as_array(Game.profile.get("guests"))
	for index: int in guests.size():
		var carried: Node3D = _factory.make("wedding_guest")
		carried.position = Vector3(-2.0 + float(index) * 1.0, _factory.size_of("wedding_guest").y * 0.5, 4.2)
		add_child(carried)
	# The two modes are doors out of the room.
	var doors: Dictionary = tuning.d("wedding_mode_pos")
	for mode: String in [Save.COMMUTE, Save.ENDLESS_NIGHT]:
		var spot: Array = GameData.as_array(doors.get(mode))
		if spot.size() < 2:
			continue
		var at: Vector3 = Vector3(GameData.as_float(spot[0]), 0.0, GameData.as_float(spot[1]))
		var door: Node3D = _factory.make("wedding_door")
		door.position = at + Vector3(0.0, _factory.size_of("wedding_door").y * 0.5, 0.0)
		add_child(door)
		var open: bool = GameData.as_array(Game.profile.get("modes")).has(mode)
		var sign: Label3D = Label3D.new()
		sign.text = Lines.get_text("wedding.mode.%s" % mode)
		sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sign.pixel_size = 0.005
		sign.modulate = Color.WHITE if open else Color(0.6, 0.6, 0.6)
		sign.position = at + Vector3(0.0, _factory.size_of("wedding_door").y + 0.4, 0.0)
		add_child(sign)
		_places.append({"kind": "mode", "id": mode, "at": at + Vector3(0.0, _factory.size_of("wedding_door").y * 0.5, 0.0), "open": open})

	# Noor and the groom, for the finale: she in front of him, the groom
	# across the room.
	_walk_from = _vec3(tuning.a("finale_noor_pos"))
	_walk_to = _vec3(tuning.a("finale_groom_pos"))
	_walkers = Node3D.new()
	_walkers.visible = false
	add_child(_walkers)
	_noor = _factory.make("wedding_noor")
	_noor.position = Vector3(0.0, _factory.size_of("wedding_noor").y * 0.5, 0.0)
	_walkers.add_child(_noor)
	_palm = _factory.make("wedding_palm")
	_palm.position = _vec3(tuning.a("finale_palm"))
	_walkers.add_child(_palm)
	_groom = _factory.make("wedding_groom")
	_groom.position = _walk_to + Vector3(0.0, _factory.size_of("wedding_groom").y * 0.5, -0.9)
	_groom.visible = false
	add_child(_groom)


func _build_ui() -> void:
	var tuning: Tuning = _data.tuning
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	_shade = ColorRect.new()
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shade.color = Color(0.0, 0.0, 0.0, 0.0)
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_shade)
	_heading = _label(layer, tuning.f("menu_heading_font_size"), Control.PRESET_CENTER_TOP)
	_heading.position.y += 24.0 * _scale
	_panel = _label(layer, tuning.f("menu_font_size"), Control.PRESET_CENTER_BOTTOM)
	_panel.position.y -= 250.0 * _scale
	_card = _label(layer, tuning.f("menu_font_size") * 1.2, Control.PRESET_CENTER)
	_back = Button.new()
	_back.text = Lines.get_text("wedding.back")
	_back.flat = true
	_back.focus_mode = Control.FOCUS_NONE
	_back.add_theme_font_size_override("font_size", roundi(tuning.f("menu_font_size") * 0.8 * _scale))
	_back.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_back.position = Vector2(16.0, 12.0) * _scale
	_back.pressed.connect(_to_title)
	layer.add_child(_back)
	_subtitles = SubtitlesView.new()
	add_child(_subtitles)
	_subtitles.setup(_data)


func _label(layer: CanvasLayer, font_size: float, preset: Control.LayoutPreset) -> Label:
	var label: Label = Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", roundi(font_size * _scale))
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", roundi(6.0 * _scale))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.set_anchors_and_offsets_preset(preset)
	label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	label.grow_vertical = Control.GROW_DIRECTION_BOTH
	layer.add_child(label)
	return label


func _open_tables() -> int:
	var count: int = 0
	for place: Dictionary in _places:
		if place["kind"] == "table" and GameData.as_bool(place["open"]):
			count += 1
	return count


func _enter_room() -> void:
	_mode = ROOM
	Game.state = Game.AppState.WEDDING
	Game.last_ending = {}
	_shade.color = Color(0.0, 0.0, 0.0, 0.0)
	_card.text = ""
	_heading.text = Lines.get_text("wedding.heading")
	_back.visible = true
	_walkers.visible = false
	_groom.visible = false
	var tuning: Tuning = _data.tuning
	_camera.position = _vec3(tuning.a("wedding_camera"))
	_camera.look_at(_vec3(tuning.a("wedding_look_at")))
	_hover = -1
	_show_hover()


func _to_title() -> void:
	Game.go(Game.AppState.TITLE)


## The place the pointer is at (-1 for none): the nearest on the screen
## within the pick radius.
func _place_under(pointer: Vector2) -> int:
	var best: int = -1
	var best_distance: float = _pick_radius * get_viewport().get_visible_rect().size.y
	for index: int in _places.size():
		var at: Vector3 = _places[index]["at"]
		if _camera.is_position_behind(at):
			continue
		var distance: float = _camera.unproject_position(at).distance_to(pointer)
		if distance < best_distance:
			best_distance = distance
			best = index
	return best


func _show_hover() -> void:
	_highlight.visible = _hover >= 0
	if _hover < 0:
		_panel.text = ""
		return
	var place: Dictionary = _places[_hover]
	var id: String = GameData.as_string(place["id"])
	var at: Vector3 = place["at"]
	_highlight.position = Vector3(at.x, 0.02, at.z)
	var rows: PackedStringArray = []
	if place["kind"] == "table":
		rows.append(Lines.get_text("table.%s.name" % id))
		rows.append(Lines.get_text("table.%s.rule" % id))
		if not GameData.as_bool(place["open"]):
			var before: String = GameData.as_string(_data.record("tables", id).get("unlock")).trim_prefix(TableRules.UNLOCK_WIN)
			rows.append(Lines.format("wedding.locked", [Lines.get_text("table.%s.name" % before)]))
		else:
			if GameData.as_array(Game.profile.get("told_true")).has(id):
				rows.append(Lines.get_text("wedding.told_true"))
			var saved: bool = not Game.saved_telling.is_empty() and GameData.as_string(Game.saved_telling.get("table")) == id
			rows.append(Lines.get_text("wedding.continue" if saved else "wedding.sit"))
			if not _greeted.has(id):
				# The Table greets him, once a visit.
				_greeted[id] = true
				_subtitles.say("table.%s.greeting" % id)
	else:
		rows.append(Lines.get_text("wedding.mode.%s" % id))
		rows.append(Lines.get_text("wedding.mode.%s.rule" % id))
		if not GameData.as_bool(place["open"]):
			rows.append(Lines.get_text("wedding.mode.locked.%s" % id))
		else:
			var stats: Dictionary = GameData.as_dict(Game.profile.get("stats"))
			if stats.has("%s_best" % id):
				rows.append(Lines.format("wedding.best.%s" % id, [_score_text(id, GameData.as_float(stats.get("%s_best" % id)))]))
	_panel.text = "\n".join(rows)


## A mode's score as it is read: cash as it is, distance in km.
func _score_text(mode: String, score: float) -> String:
	return "%.1f" % (score / 1000.0) if mode == Save.ENDLESS_NIGHT else "%d" % roundi(score)


func _sit(index: int) -> void:
	var place: Dictionary = _places[index]
	if not GameData.as_bool(place["open"]):
		return
	if place["kind"] == "table":
		Game.sit_at(GameData.as_string(place["id"]))
	else:
		Game.play_mode(GameData.as_string(place["id"]))


# --- The ending (GDD 11.4, 11.5) ------------------------------------------------------

func _show_ending(result: Dictionary) -> void:
	_mode = ENDING
	Game.state = Game.AppState.ENDING
	_back.visible = false
	_highlight.visible = false
	_panel.text = Lines.get_text("ending.continue")
	_shade.color = Color(0.0, 0.0, 0.0, 0.55)
	var rows: PackedStringArray = []
	if result.has("mode"):
		# A mode's run.
		var mode: String = GameData.as_string(result.get("mode"))
		_heading.text = Lines.get_text("wedding.mode.%s" % mode)
		rows.append(Lines.format("mode.over.%s" % mode, [_score_text(mode, GameData.as_float(result.get("score")))]))
		if GameData.as_bool(result.get("best")):
			rows.append(Lines.get_text("mode.over.best"))
		_card.text = "\n".join(rows)
		return
	var ending: String = GameData.as_string(result.get("ending"))
	var table_id: String = GameData.as_string(result.get("table"))
	_heading.text = Lines.get_text("ending.heading.%s" % ending)
	rows.append(Lines.get_text("table.%s.name" % table_id))
	rows.append(Lines.format("ending.clock", [GameData.as_string(result.get("clock"))]))
	rows.append("")
	var gained: int = 0
	for opened: Variant in _strings(result.get("tables")):
		rows.append(Lines.format("ending.unlocked.table", [Lines.get_text("table.%s.name" % str(opened))]))
		gained += 1
	if GameData.as_bool(result.get("told_true")):
		rows.append(Lines.get_text("ending.told_true"))
		gained += 1
	for mode: Variant in _strings(result.get("modes")):
		rows.append(Lines.format("ending.unlocked.mode", [Lines.get_text("wedding.mode.%s" % str(mode))]))
		gained += 1
	var guest: String = GameData.as_string(result.get("guest"))
	if not guest.is_empty():
		rows.append(Lines.format("ending.guest", [_guest_name(guest)]))
	if gained == 0 and ending == Save.LATE:
		rows.append(Lines.get_text("ending.nothing"))
	_card.text = "\n".join(rows)
	# "A short scene follows per ending": he says how he parked, the Table
	# answers, and a guest he carried says a word.
	_subtitles.say("ending.parked.%s" % ending)
	_subtitles.say("ending.%s.%s" % [ending, table_id])
	if not guest.is_empty():
		_subtitles.say("guest.%s.seated" % guest)


## A passenger's name as the subtitles give it: the speaker of his first line.
func _guest_name(passenger_id: String) -> String:
	var speaker: String = Lines.get_speaker_name(Lines.get_speaker("guest.%s.seated" % passenger_id))
	return speaker if not speaker.is_empty() else passenger_id


func _strings(value: Variant) -> PackedStringArray:
	var out: PackedStringArray = []
	if value is PackedStringArray:
		return value
	for entry: Variant in GameData.as_array(value):
		out.append(GameData.as_string(entry))
	return out


func _leave_ending() -> void:
	var finale: bool = GameData.as_bool(Game.last_ending.get("finale")) or (str(Game.args.get("ending", "")) == Save.THE_CALL and str(Game.args.get("table", "")) == "noor")
	_subtitles.clear()
	if finale:
		_begin_finale()
	else:
		_enter_room()


# --- The finale (GDD 10.6) ----------------------------------------------------------------

func _begin_finale() -> void:
	_mode = FINALE
	Game.state = Game.AppState.FINALE
	Game.last_ending = {}
	_finale = FinaleSim.new()
	_finale.configure(_data.tuning)
	_finale.begin()
	_back.visible = false
	_highlight.visible = false
	_heading.text = ""
	_panel.text = ""
	_card.text = ""
	_shade.color = Color(0.0, 0.0, 0.0, 0.0)
	_walkers.visible = true
	_groom.visible = true
	_clap_left = _clap_period
	_place_walkers()
	_subtitles.say("finale.noor.palm")


## Noor, her palm and his eyes, as far along the walk as they are.
func _place_walkers() -> void:
	var share: float = _finale.walk_share() if _finale != null else 0.0
	_walkers.position = _walk_from.lerp(_walk_to, share)
	_camera.position = _walkers.position + _vec3(_data.tuning.a("finale_eye"))
	_camera.look_at(_walkers.position + Vector3(0.0, _palm.position.y, 0.0))
	# Her hand is raised until she has taken his; then it is down, in his.
	_palm.visible = _finale == null or _finale.phase == FinaleSim.CLAPPING or not _finale.holding


func _on_palm() -> bool:
	var at: Vector3 = _palm.global_position
	if _camera.is_position_behind(at):
		return false
	return _camera.unproject_position(at).distance_to(_pointer) <= _palm_radius * get_viewport().get_visible_rect().size.y


func _physics_process(delta: float) -> void:
	if _mode != FINALE or _finale == null:
		return
	_finale.step(delta, Input.is_action_pressed("grip"), _on_palm())
	for event: Dictionary in _finale.events:
		var type: String = GameData.as_string(event.get("type"))
		if type == "sfx_requested":
			Audio.play(GameData.as_string(event.get("id")))
		elif GameData.as_string(event.get("id")) != "finale.proverb":
			Events.emit_event(type, event)
	# The guests' steady rhythm; after 90 s of standing it is back, softly.
	if _finale.phase == FinaleSim.CLAPPING or _finale.clapping_again:
		_clap_left -= delta
		if _clap_left <= 0.0:
			_clap_left += _clap_period
			Audio.play("clap")
	_place_walkers()
	if _finale.over():
		_show_proverb()


## "Cut to a title card with finale.proverb."
func _show_proverb() -> void:
	_mode = PROVERB
	_proverb_shown = 0.0
	_subtitles.clear()
	_shade.color = Color.BLACK
	_heading.text = Lines.get_text("title.card.finale")
	_card.text = Lines.get_text("finale.proverb").replace(" / ", "\n\n")
	_panel.text = ""


func _show_credits() -> void:
	_mode = CREDITS
	Game.state = Game.AppState.CREDITS
	_back.visible = false
	_highlight.visible = false
	_shade.color = Color.BLACK
	_heading.text = ""
	var rows: PackedStringArray = []
	var number: int = 1
	while Lines.has_line("credits.%d" % number):
		rows.append(Lines.get_text("credits.%d" % number))
		number += 1
	_card.text = "\n\n".join(rows)
	_panel.text = Lines.get_text("credits.continue")


# --- The pointer --------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _mode == PROVERB:
		_proverb_shown += delta
	if _mode != ROOM:
		return
	var hover: int = _place_under(_pointer)
	if hover != _hover:
		_hover = hover
		_show_hover()


func _input(event: InputEvent) -> void:
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion != null:
		_pointer = motion.position


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and _mode == ROOM:
		_to_title()
		return
	if not event.is_action_pressed("grip"):
		return
	match _mode:
		ROOM:
			if _hover >= 0:
				_sit(_hover)
		ENDING:
			_leave_ending()
		PROVERB:
			# The card stays a moment: the click that let her hand go is not
			# the click that turns it over.
			if _proverb_shown > 1.0:
				_show_credits()
		CREDITS:
			_enter_room()


func _vec3(values: Array) -> Vector3:
	return Vector3(GameData.as_float(values[0]), GameData.as_float(values[1]), GameData.as_float(values[2])) if values.size() >= 3 else Vector3.ZERO
