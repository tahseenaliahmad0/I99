extends Node3D
## Drive (GDD 13.5): builds DriveInput, steps DriveSim, hands the snapshot to
## the views. One scene serves the prologue, legs, bosses, stops and modes;
## what it does is set by a DriveContext dictionary on Game.
##
## The simulation steps in _physics_process at 120 ticks per second. Views are
## refreshed in _process from DriveSim.snapshot() and never touch the
## simulation (GDD 1.3).

var sim: DriveSim

var _input: DriveInput = DriveInput.new()
var _pending_motion: Vector2 = Vector2.ZERO
var _factory: PlaceholderFactory
var _aim_anchor: int = HandSim.NO_ANCHOR
var _shot_path: String = ""
## The rendered frames to save: one, or several (`--shot-frame=a,b,c`), each
## then saved under the shot's name with its frame number added.
var _shot_frames: PackedInt32Array = PackedInt32Array()
var _frames: int = 0
## `--leg=<id>[,act[,modifier]]`: the leg being driven, and how many of it
## have been started (each with the next seed).
var _leg_spec: String = ""
var _legs_begun: int = 0
## `--boss=<id>[,modifier]`: the set piece being driven by itself, a boss of
## legs.json or "arrival" for the last street. It begins again with the next
## seed whenever it ends.
var _boss_spec: String = ""
## `--bot=`: until the DriverBot of GDD 13.8 is built (M11), any value puts a
## stand-in at the wheel, which is enough to look at a leg, a set piece or a
## whole Telling (null: the player drives).
var _bot: DriverBot = null
## What this scene is to do (GDD 13.4): Game.context when it was entered
## from the menus, else the command line's arguments.
var _context: Dictionary = {}
## Entered from the menus: when the night is over the wedding is next.
var _from_menu: bool = false
## The prologue was playing a tick ago.
var _in_prologue: bool = false
## Seconds until the scene is left for the wedding (0: it is not being left).
var _leave_in: float = 0.0
var _narration: Narration = Narration.new()
## Mirrored cabin (GDD 17.1): the picture and the pointer's sideways motion
## are reversed.
var _mirrored: bool = false
var _mirror: CanvasLayer
## Tremor and shake visuals (GDD 17.1), 0 to 1.
var _shake: float = 1.0
var _prologue_view: PrologueView

@onready var _camera: Camera3D = $Camera3D
@onready var _cabin: CabinView = $Cabin
@onready var _hand: HandView = $Cabin/Hand
@onready var _road: RoadView = $Road
@onready var _stop: StopView = $Cabin/Stop
@onready var _sky: SkyView = $Sky
@onready var _post_fx: PostFxView = $PostFX
@onready var _pointer: PointerView = $Overlay/Pointer
@onready var _subtitles: SubtitlesView = $Subtitles
@onready var _hud: DebugHud = $DebugHUD


func _ready() -> void:
	var data: GameData = Game.data
	sim = DriveSim.new(data)
	_factory = PlaceholderFactory.new(data)

	var tuning: Tuning = data.tuning
	_camera.position = sim.space.eye
	_camera.fov = tuning.f("camera_fov")
	_camera.near = tuning.f("camera_near")
	_camera.far = tuning.f("camera_far")
	_camera.current = true

	_cabin.setup(data, _factory)
	_hand.setup(data, _factory, sim.space)
	_road.setup(data, _factory)
	_stop.setup(data, _factory)
	_sky.setup(data, _factory)
	_post_fx.setup(data, _camera, _cabin)
	_pointer.setup(data, _factory)
	_pause_hold = PauseHold.new(data.tuning.f("pause_hold_s"))
	_touch = TouchInput.new(data.tuning)
	_feedback.setup(tuning)
	_cabin.feedback = _feedback
	_cabin.set_dash_words(Lines.format("dash.clock.due", [tuning.s("clock_deadline")]), Lines.get_text("hud.neutral"))
	_hints = HintView.new()
	$Overlay.add_child(_hints)
	$Overlay.move_child(_hints, 0)
	_hints.setup(data, _factory)
	_hints.mirrored = _mirrored
	_touch_view = TouchView.new()
	$Overlay.add_child(_touch_view)
	_touch_view.setup(_factory, _touch)
	_subtitles.setup(data)
	_narration.setup(data)
	_prologue_view = PrologueView.new()
	$Overlay.add_child(_prologue_view)
	_prologue_view.setup(data, _factory)
	_build_mirror()
	if not Settings.changed.is_connected(_on_setting_changed):
		Settings.changed.connect(_on_setting_changed)
	_apply_settings()
	_from_menu = not Game.context.is_empty()
	_context = Game.context if _from_menu else Game.args
	_from_dev = _from_menu and _context.has("dev")
	var seed_asked: int = int(str(_context.get("seed", "1")))
	sim.rng.reseed(seed_asked)
	if _context.has("bot") or Game.args.has("bot"):
		_take_the_wheel(GameData.as_string(_context.get("bot", Game.args.get("bot"))))
	_seat_the_guests()
	if _context.has("continue") and not Game.saved_telling.is_empty() and sim.restore(Game.saved_telling):
		print("[drive] continuing the Telling of %s" % sim.run.table)
	elif _context.has("prologue"):
		# "Two Hands" (GDD 10.1), and then tonight.
		sim.begin_prologue(str(_context.get("table", "children")), seed_asked)
		_in_prologue = true
		Game.state = Game.AppState.PROLOGUE
		print("[drive] the prologue, then a Telling for %s, seed %d" % [str(_context.get("table", "children")), seed_asked])
	elif _context.has("mode"):
		_begin_mode()
	elif _context.has("table"):
		# A Telling (GDD 11.1), from Baghdad.
		sim.begin_telling(str(_context["table"]), seed_asked)
		print("[drive] a Telling for %s, seed %d" % [sim.run.table, sim.run.seed])
	elif _context.has("leg"):
		_leg_spec = str(_context["leg"])
		_begin_leg()
	elif _context.has("boss"):
		_boss_spec = str(_context["boss"])
		_begin_boss()
	else:
		sim.free_traffic_per_km = tuning.f("free_traffic_per_km")

	if _context.has("stop") and not sim.dev_stop(str(_context["stop"])):
		push_error("Drive: no stop '%s' to begin at" % str(_context["stop"]))
	if _context.has("cash"):
		sim.cash = maxf(str(_context["cash"]).to_float(), 0.0)
	if _context.has("give"):
		for item_id: String in str(_context["give"]).split(",", false):
			item_id = item_id.strip_edges()
			if sim.give_item(StringName(item_id)) == null:
				push_error("Drive: --give names an item that cannot be put in the cabin: '%s'" % item_id)
	if _context.has("ride") and not sim.board(str(_context["ride"])):
		push_error("Drive: --ride names nobody who can get in: '%s'" % str(_context["ride"]))
	if Game.args.has("say"):
		# `--say=<line id>[,<line id>...]`: lines to look at, asked for as the simulation asks.
		for line_id: String in str(Game.args["say"]).split(",", false):
			Events.emit_event("line_requested", {"id": line_id})
	if Game.args.has("aim"):
		_aim_anchor = sim.hand.anchor_index(StringName(str(Game.args["aim"])))
		if _aim_anchor == HandSim.NO_ANCHOR:
			push_error("Drive: --aim names an unknown anchor '%s'" % str(Game.args["aim"]))
	if Game.args.has("shot"):
		_shot_path = str(Game.args["shot"])
		if Game.args.has("shot-frame"):
			for frame: String in str(Game.args["shot-frame"]).split(",", false):
				_shot_frames.append(maxi(1, frame.to_int()))
		if _shot_frames.is_empty():
			_shot_frames.append(tuning.i("screenshot_frame"))

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	print("[drive] ready anchors=%d rituals=%d" % [sim.hand.anchor_count(), data.records("rituals").size()])


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	# Fingers (GDD 4.1, 17.4): the thumb is the hand, the pedal zone the brake.
	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	if touch != null:
		if touch.pressed:
			_touch.finger_down(touch.index, touch.position, _pointer_under(touch.position), _view_size(), _dpi())
		else:
			_touch.finger_up(touch.index)
		return
	var drag: InputEventScreenDrag = event as InputEventScreenDrag
	if drag != null:
		_touch.finger_moved(drag.index, drag.position, _pointer_under(drag.position),
				sim.space.to_reference(PointerView.mirrored_motion(drag.relative, _mirrored), _view_size().y))
		return
	if _touch.active and event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
		# The mouse the engine makes up for a finger: the finger is heard already.
		return
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion != null:
		_pending_motion += PointerView.mirrored_motion(motion.relative, _mirrored)
	elif event.is_action_pressed("debug_hud"):
		_hud.toggle()
	elif event.is_action_pressed("debug_bot"):
		# F7 (GDD 13.9): the bot at the wheel, or off it again.
		if _bot == null:
			_take_the_wheel(DriverBot.SKILLS[DriverBot.SKILLS.size() - 1])
		else:
			_bot = null
		print("[drive] the bot is %s the wheel" % ("at" if _bot != null else "off"))
	elif Game.dev and _dev_key(event):
		pass
	elif event.is_action_pressed("pause") and _leave_in <= 0.0:
		_open_pause()


# --- Dev mode (D-073; the debug keys of GDD 13.9) ---------------------------------

## True when the event was one of the dev keys, and done.
func _dev_key(event: InputEvent) -> bool:
	var tuning: Tuning = sim.tuning
	if event.is_action_pressed("debug_tuning"):
		_open_tuning()
	elif event.is_action_pressed("debug_skip_leg"):
		print("[dev] skip to the end of the leg: %s" % str(sim.dev_skip_leg(tuning.f("dev_skip_margin_m"))))
	elif event.is_action_pressed("debug_cash"):
		sim.cash += tuning.f("dev_cash_step")
		print("[dev] cash %s" % str(sim.cash))
	elif event.is_action_pressed("debug_give_item"):
		_ask("dev.prompt.item", func(text: String) -> void:
			for item_id: String in text.split(",", false):
				print("[dev] give %s: %s" % [item_id.strip_edges(), str(sim.give_item(StringName(item_id.strip_edges())) != null)]))
	elif event.is_action_pressed("debug_set_nerves"):
		_ask("dev.prompt.nerves", func(text: String) -> void:
			if text.is_valid_float():
				sim.nerves.value = clampf(text.to_float(), 0.0, 100.0)
				print("[dev] Nerves %s" % str(sim.nerves.value)))
	elif event.is_action_pressed("debug_half_speed"):
		_half_speed = not _half_speed
		Engine.time_scale = Game.game_speed(Settings.get_value(SettingsSpec.GAME_SPEED)) * (tuning.f("dev_slow_share") if _half_speed else 1.0)
		print("[dev] time scale %s" % str(Engine.time_scale))
	else:
		return false
	return true


## F2: the tuning panel, with the game held. Closed after a change, the
## scene begins again: the simulation reads its numbers when it is built.
func _open_tuning() -> void:
	if _dev_panel != null or _pause != null:
		return
	var panel: TuningPanel = TuningPanel.new()
	_dev_panel = panel
	$Overlay.add_child(panel)
	panel.setup()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true
	panel.closed.connect(func() -> void:
		var again: bool = panel.changed
		panel.queue_free()
		_dev_panel = null
		get_tree().paused = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if again:
			print("[dev] tuning changed: the scene begins again")
			get_tree().reload_current_scene.call_deferred())


## A line of text asked for, with the game held (F5, F6).
func _ask(line_id: String, answered: Callable) -> void:
	if _dev_panel != null or _pause != null:
		return
	var box: PanelContainer = PanelContainer.new()
	box.process_mode = Node.PROCESS_MODE_ALWAYS
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	var rows: VBoxContainer = VBoxContainer.new()
	box.add_child(rows)
	var label: Label = Label.new()
	label.text = Lines.get_text(line_id)
	rows.add_child(label)
	var field: LineEdit = LineEdit.new()
	field.custom_minimum_size = Vector2(420.0, 0.0)
	rows.add_child(field)
	_dev_panel = box
	$Overlay.add_child(box)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true
	field.grab_focus.call_deferred()
	var done: Callable = func(text: String) -> void:
		box.queue_free()
		_dev_panel = null
		get_tree().paused = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if not text.strip_edges().is_empty():
			answered.call(text.strip_edges())
	field.text_submitted.connect(done)
	field.gui_input.connect(func(event: InputEvent) -> void:
		if event.is_action_pressed("pause"):
			done.call(""))


func _view_size() -> Vector2:
	return get_viewport().get_visible_rect().size


## Dots per inch of the glass, as far as the view's pixels go (a view drawn
## larger or smaller than the screen has that many fewer or more).
func _dpi() -> float:
	var window: Vector2 = Vector2(get_window().size)
	var scale: float = _view_size().y / maxf(window.y, 1.0)
	return float(DisplayServer.screen_get_dpi()) * scale


## The place in the cabin under a point of the glass, in the pointer's own
## coordinates: what a thumb there points at.
func _pointer_under(at: Vector2) -> Vector2:
	var seen: Vector2 = PointerView.shown_at(at, _view_size().x, _mirrored)
	var direction: Vector3 = _camera.project_ray_normal(seen)
	return sim.space.direction_to_pointer(_cabin.global_transform.basis.inverse() * direction)


## The DriverBot takes the wheel (GDD 13.8): `--bot=novice`, `competent` or
## `expert`. Any other word is the smoke runs' driver: the competent bot,
## pulling in at every stop so that a short run sees one.
func _take_the_wheel(skill: String) -> void:
	_bot = DriverBot.new(sim, Game.data, skill, Rng.derive(sim.run.seed, DriverBot.SEED_SALT))
	_bot.every_stop = not DriverBot.SKILLS.has(skill)


func _physics_process(_delta: float) -> void:
	_input.clear()
	var view_height: float = get_viewport().get_visible_rect().size.y
	_input.pointer_delta = sim.space.to_reference(_pending_motion, view_height)
	_pending_motion = Vector2.ZERO
	_input.lmb = Input.is_action_pressed("grip")
	_input.rmb = Input.is_action_pressed("brake")
	_input.pad_horn = Input.is_action_pressed("pad_horn")
	_input.pad_wiper = Input.is_action_just_pressed("pad_wiper")
	if _aim_anchor != HandSim.NO_ANCHOR:
		_input.pointer_is_absolute = true
		_input.pointer = sim.hand.anchor_pointer(_aim_anchor)
	if not _leg_spec.is_empty() and not sim.leg.active:
		_begin_leg()
	if not _boss_spec.is_empty() and not sim.leg.active:
		_begin_boss()
	if _touch.active and _bot == null:
		# A thumb's target is 9 mm across, also where the pointer's is less.
		sim.hand.set_snap_radius(_touch.snap_radius(_view_size(), _dpi()))
		_touch.apply(sim, _input)
	var to_the_pause: bool = _touch.take_pause()
	if not _touch.active and Input.is_action_just_pressed("grip") and _touch.hotspot(_view_size(), _dpi()).has_point(_pointer.shown()):
		# GDD 4.1: "Esc, or click the hotspot in the top-left corner."
		to_the_pause = true
	if to_the_pause and _leave_in <= 0.0:
		_open_pause.call_deferred()
	if _bot != null:
		_bot.drive(_input)
	sim.step(_input)
	# The pointer's way to the pause (D-066): the left button held where the
	# hand has nothing to hold. (His own hand's: not a bot's.)
	if _bot == null and _leave_in <= 0.0 and _pause_hold.step(DriveSim.DT, _input.lmb, sim.hand_is_free()):
		_open_pause.call_deferred()
	_pointer.pause_progress = _pause_hold.progress
	if _in_prologue and not sim.prologue.active:
		# The cut to tonight: the prologue has been seen.
		_in_prologue = false
		Game.prologue_played()
		Game.state = Game.AppState.TELLING
		_narration.reset()
		print("[drive] the prologue is over: tonight (frame %d)" % _frames)
	for event: Dictionary in sim.drain_events():
		var type: String = GameData.as_string(event.get("type"))
		Events.emit_event(type, event)
		_feedback.on_event(type, event)
		if not _in_prologue:
			# What he, the Table and the stalls say to it.
			var said: String = _narration.on_event(type, event, sim.seconds(), sim.run.table)
			if not said.is_empty():
				Events.emit_event("line_requested", {"id": said})
		if type == "stop_entered":
			# The game saves at every stop and after every boss (GDD 11.1).
			Game.write_save(sim.checkpoint)
			print("[drive] stop %s, saved (frame %d, clock %s)" % [str(event.get("stop")), _frames, sim.clock.text()])
		elif type == "boss_ended" or type == "pulled_over" or type == "call_resolved" or type == "wreck" \
				or type == "heckle_started" or type == "heckle_resolved":
			# What became of a set piece, and what the Table said, for whoever
			# reads the console.
			print("[drive] %s at %.1f s (frame %d): %s" % [type, sim.seconds(), _frames, JSON.stringify(event)])
		if type == "wreck" and sim.run.active and not GameData.as_bool(event.get("rewind")):
			# After a Wreck there is no saved Telling to continue (GDD 11.4): the
			# night is told again from Baghdad, and quitting during the cut must
			# not bring the wrecked one back. (Outside a Telling a Wreck ends
			# nothing that the file holds; nor does one that a free rewind
			# takes back, GDD 11.2.)
			Game.write_save({})
		if type == "arrived":
			print("[drive] arrived at %s (frame %d)" % [sim.clock.text(), _frames])
			if not _boss_spec.is_empty():
				# A set piece by itself: whoever he carried all the way is a
				# wedding guest from now on (GDD 11.5).
				if Game.add_guest(GameData.as_string(event.get("guest"))):
					print("[drive] a new guest: %s" % GameData.as_string(event.get("guest")))
					Game.write_save(Game.saved_telling)
		if type == "arrived" and _boss_spec.is_empty() and sim.mode.is_empty():
			# The ending (GDD 11.4): what it leaves behind is in the profile
			# and on disk.
			var ending: Dictionary = Game.end_telling(event)
			ending["table"] = GameData.as_string(event.get("table"))
			ending["clock"] = GameData.as_string(event.get("clock"))
			print("[drive] ending: %s" % JSON.stringify(ending))
			if _from_menu:
				# "A short scene follows per ending, then the party" (GDD 10.5).
				Game.last_ending = ending
				_leave_in = sim.tuning.f("ending_leave_s")
			else:
				# Started from the command line, the night simply begins again.
				_subtitles.clear()
				_narration.reset()
				_seat_the_guests()
				sim.begin_telling(sim.run.table, sim.run.seed + 1)
	if sim.mode_over and _leave_in <= 0.0 and not sim.mode.is_empty():
		# A mode's run is over (GDD 11.5): its score is kept.
		var run: Dictionary = Game.end_mode(sim.mode, sim.mode_score(), not sim.wrecked)
		print("[drive] mode over: %s" % JSON.stringify(run))
		if _from_menu:
			Game.last_ending = run
			_leave_in = sim.tuning.f("ending_leave_s")
		else:
			_context["seed"] = int(str(_context.get("seed", "1"))) + 1
			_begin_mode()
	if _leave_in > 0.0:
		_leave_in -= 1.0 / float(Engine.physics_ticks_per_second)
		if _leave_in <= 0.0:
			Game.go(Game.AppState.ENDING)


## Starts the mode the context names (GDD 11.5).
func _begin_mode() -> void:
	var mode: String = str(_context.get("mode", ""))
	var mode_seed: int = int(str(_context.get("seed", "1")))
	sim.heckling = false
	_narration.reset()
	match mode:
		Save.COMMUTE:
			sim.begin_commute(mode_seed)
		Save.ENDLESS_NIGHT:
			sim.begin_endless(mode_seed)
		_:
			push_error("Drive: unknown mode '%s'" % mode)
			return
	print("[drive] mode %s, seed %d" % [mode, mode_seed])


# --- The settings (GDD 17.1) -------------------------------------------------------

var _pause: SettingsView = null
var _pause_hold: PauseHold = null
## Fingers on the glass (GDD 4.1, 17.4), and what is drawn for them.
var _touch: TouchInput = null
var _touch_view: TouchView = null
## Names, feedback and the gate's diagram (D-071), and what they show.
var _hints: HintView = null
## Started from the dev menu (D-073): leaving leads back to it.
var _from_dev: bool = false
var _half_speed: bool = false
var _dev_panel: Control = null
var _feedback: ActionFeedback = ActionFeedback.new()


## The night waits (the tree is paused) and the settings are on the screen:
## every one of them can be changed in the middle of a Telling (GDD 17.2).
## From there he drives on, or goes back to the wedding, where what the
## last stop saved is waiting.
func _open_pause() -> void:
	if _pause != null:
		return
	_pause = SettingsView.new()
	$Overlay.add_child(_pause)
	_pause.setup("settings.resume")
	if _from_dev:
		_pause.add_entry("dev.leave", "leave")
	elif _from_menu:
		_pause.add_entry("settings.leave", "leave")
	_pause.closed.connect(_close_pause)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true


func _close_pause() -> void:
	var leave: bool = _pause.answer == "leave"
	_pause.queue_free()
	_pause = null
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# The press that closed it is no new hold.
	_pause_hold.reset(Input.is_action_pressed("grip"))
	if leave:
		Game.go(Game.AppState.TITLE if _from_dev else Game.AppState.WEDDING)


## The layer that shows the picture reversed (shaders/mirror.gdshader): after
## the post effects, before the subtitles.
func _build_mirror() -> void:
	_mirror = CanvasLayer.new()
	_mirror.name = "Mirror"
	_mirror.layer = _post_fx.layer
	var rect: ColorRect = ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = load("res://shaders/mirror.gdshader") as Shader
	rect.material = material
	_mirror.add_child(rect)
	_mirror.visible = false
	add_child(_mirror)
	move_child(_mirror, _post_fx.get_index() + 1)


## Every setting, as it is now: the simulation's own, and what the views
## draw. Called at the start and whenever one is changed (GDD 17.2: "Every
## setting can be changed mid-Telling").
func _apply_settings() -> void:
	var values: Dictionary = Game.setting_values()
	sim.apply_settings(values)
	_shake = SettingsSpec.share(values[SettingsSpec.SHAKE_VISUALS])
	_cabin.shake_visuals = _shake
	_hand.shake_visuals = _shake
	_mirrored = GameData.as_bool(values[SettingsSpec.MIRRORED])
	_mirror.visible = _mirrored
	_pointer.mirrored = _mirrored
	if _hints != null:
		_hints.mirrored = _mirrored
	_prologue_view.mirrored = _mirrored
	_hud.visible = GameData.as_bool(values[SettingsSpec.NUMERIC_HUD]) or Game.args.has("hud")
	print("[drive] settings: steering=%.2f grip=%s shifting=%s speed=%.2f assist=%s steady=%s phantom=%s shake=%.2f hud=%s mirrored=%s" % [
		sim.steer_sensitivity, "toggle" if sim.grip_toggle else "hold", "sequential" if sim.sequential_shift else "gate", Engine.time_scale,
		str(sim.brake_assist), str(sim.steady_start), str(sim.phantom_enabled), _shake, str(_hud.visible), str(_mirrored)])


func _on_setting_changed(key: String, _value: Variant) -> void:
	if Game.settings_spec.has(key):
		_apply_settings()


## Whoever he has carried to Basra sits at the Tables from then on, and
## heckles with them (GDD 11.5).
func _seat_the_guests() -> void:
	var guests: PackedStringArray = []
	for guest: Variant in GameData.as_array(Game.profile.get("guests")):
		guests.append(GameData.as_string(guest))
	sim.guests = guests


func _process(delta: float) -> void:
	var snapshot: Dictionary = sim.snapshot()
	var cam_yaw: float = snapshot["cam_yaw"]
	var cam_pitch: float = snapshot["cam_pitch"]
	# Yaw toward the passenger (+X) is a negative turn about +Y. Sway rocks
	# the horizon (GDD 5.8): the camera rolls with the push.
	var sway: float = snapshot["sway"]
	# A road that leans is seen to lean (D-074): the horizon tilts with it,
	# whatever the shake setting (it is what the road says, not a shake).
	var lean: float = GameData.as_float(snapshot["camber"]) * sim.tuning.f("camber_view_roll")
	_camera.rotation = Vector3(deg_to_rad(cam_pitch), -deg_to_rad(cam_yaw), deg_to_rad(sway * sim.tuning.f("sway_view_roll") * _shake - lean))
	_feedback.step(snapshot, delta)
	_cabin.apply(snapshot)
	_hand.apply(snapshot)
	_road.apply(snapshot, delta)
	_stop.apply(snapshot)
	_sky.apply(snapshot)
	_post_fx.apply(snapshot, delta)
	_pointer.apply(snapshot, _camera, _cabin)
	_hints.apply(snapshot, _feedback, _camera, _cabin, _pointer.shown(), delta)
	_touch_view.dpi = _dpi()
	_hud.apply(snapshot)
	_prologue_view.apply(snapshot, _camera, _cabin, delta)
	Audio.apply(snapshot)
	if not _in_prologue:
		# The radio, and Noor on the phone, in their own time.
		var aloud: String = _narration.on_time(sim.seconds(), str(snapshot["radio"]), str(snapshot["heckle"]) != "", GameData.as_bool(snapshot["call_talking"]))
		if not aloud.is_empty():
			Events.emit_event("line_requested", {"id": aloud})

	_frames += 1
	if not _shot_path.is_empty() and _shot_frames.has(_frames):
		_save_shot()


## Starts the leg named by `--leg=<id>[,act[,modifier]]` in third gear; each
## time it is called the leg has the next seed.
func _begin_leg() -> void:
	var data: GameData = Game.data
	var parts: PackedStringArray = _leg_spec.split(",")
	var leg_id: String = parts[0]
	if not data.has_record("legs", leg_id):
		push_error("Drive: --leg names an unknown leg '%s'" % leg_id)
		_leg_spec = ""
		return
	var acts: Array = GameData.as_array(data.record("legs", leg_id).get("acts"))
	var act: int = GameData.as_int(acts[0], 1) if not acts.is_empty() else 1
	if parts.size() > 1:
		act = clampi(parts[1].to_int(), 1, RunGenerator.ACTS)
	var modifier: String = parts[2] if parts.size() > 2 else ""
	if not modifier.is_empty() and not data.has_record("modifiers", modifier):
		push_error("Drive: --leg names an unknown modifier '%s'" % modifier)
		modifier = ""
	var leg_seed: int = int(str(_context.get("seed", "1"))) + _legs_begun
	_legs_begun += 1
	sim.gate.reset(3)
	sim.begin_leg(LegGenerator.generate(data, leg_id, act, leg_seed, modifier))
	print("[drive] leg %s act %d seed %d modifier '%s'" % [leg_id, act, leg_seed, modifier])


## Starts the set piece named by `--boss=<id>[,modifier]`: a boss of
## legs.json in third gear, or the last street ("arrival") in first; each
## time it is called it has the next seed.
func _begin_boss() -> void:
	var data: GameData = Game.data
	var parts: PackedStringArray = _boss_spec.split(",")
	var boss_id: String = parts[0]
	var boss_seed: int = int(str(_context.get("seed", "1"))) + _legs_begun
	_legs_begun += 1
	if boss_id == BossSim.ARRIVAL:
		sim.gate.reset(data.tuning.i("start_gear"))
		sim.begin_arrival()
		print("[drive] the arrival")
		return
	if not data.has_record("bosses", boss_id):
		push_error("Drive: --boss names an unknown boss '%s'" % boss_id)
		_boss_spec = ""
		return
	var modifier: String = parts[1] if parts.size() > 1 else ""
	if not modifier.is_empty() and not GameData.as_array(data.record("bosses", boss_id).get("modifiers")).has(modifier):
		push_error("Drive: --boss names a modifier that is not this boss's: '%s'" % modifier)
		modifier = ""
	sim.gate.reset(3)
	sim.begin_boss(boss_id, modifier, boss_seed)
	print("[drive] boss %s seed %d modifier '%s'" % [boss_id, boss_seed, modifier])


## Saves one rendered frame and quits (needs a real renderer; see DECISIONS D-015).
func _save_shot() -> void:
	var texture: ViewportTexture = get_viewport().get_texture()
	var image: Image = texture.get_image() if texture != null else null
	if image == null or image.is_empty():
		print("[drive] no image to save: this renderer draws nothing")
	else:
		var path: String = _shot_path
		if _shot_frames.size() > 1:
			path = "%s_%d.%s" % [_shot_path.get_basename(), _frames, _shot_path.get_extension()]
		var err: Error = image.save_png(path)
		print("[drive] shot %s (%s)" % [path, error_string(err)])
	# The last one asked for ends the run.
	var last: int = 0
	for frame: int in _shot_frames:
		last = maxi(last, frame)
	if _frames >= last:
		get_tree().quit()
