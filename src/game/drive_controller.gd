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
var _bot: StandInBot = null

@onready var _camera: Camera3D = $Camera3D
@onready var _cabin: CabinView = $Cabin
@onready var _hand: HandView = $Cabin/Hand
@onready var _road: RoadView = $Road
@onready var _stop: StopView = $Cabin/Stop
@onready var _sky: SkyView = $Sky
@onready var _post_fx: PostFxView = $PostFX
@onready var _pointer: PointerView = $Overlay/Pointer
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
	sim.rng.reseed(int(str(Game.args.get("seed", "1"))))
	if Game.args.has("bot"):
		_bot = StandInBot.new(sim, data)
	if Game.args.has("continue") and not Game.saved_telling.is_empty() and sim.restore(Game.saved_telling):
		print("[drive] continuing the Telling of %s" % sim.run.table)
	elif Game.args.has("table"):
		# A Telling (GDD 11.1), from Baghdad.
		sim.begin_telling(str(Game.args["table"]), int(str(Game.args.get("seed", "1"))))
		print("[drive] a Telling for %s, seed %d" % [sim.run.table, sim.run.seed])
	elif Game.args.has("leg"):
		_leg_spec = str(Game.args["leg"])
		_begin_leg()
	elif Game.args.has("boss"):
		_boss_spec = str(Game.args["boss"])
		_begin_boss()
	else:
		sim.free_traffic_per_km = tuning.f("free_traffic_per_km")

	if Game.args.has("give"):
		for item_id: String in str(Game.args["give"]).split(",", false):
			if sim.give_item(StringName(item_id)) == null:
				push_error("Drive: --give names an item that cannot be put in the cabin: '%s'" % item_id)
	if Game.args.has("ride") and not sim.board(str(Game.args["ride"])):
		push_error("Drive: --ride names nobody who can get in: '%s'" % str(Game.args["ride"]))
	if Game.args.has("hud") and not _hud.visible:
		_hud.toggle()
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
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion != null:
		_pending_motion += motion.relative
	elif event.is_action_pressed("debug_hud"):
		_hud.toggle()


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
	if _bot != null:
		_bot.drive(_input)
	sim.step(_input)
	for event: Dictionary in sim.drain_events():
		var type: String = GameData.as_string(event.get("type"))
		Events.emit_event(type, event)
		if type == "stop_entered":
			# The game saves at every stop and after every boss (GDD 11.1).
			Game.write_save(sim.checkpoint)
			print("[drive] stop %s, saved (frame %d, clock %s)" % [str(event.get("stop")), _frames, sim.clock.text()])
		elif type == "boss_ended" or type == "pulled_over" or type == "call_resolved" or type == "wrecked":
			# What became of a set piece, for whoever reads the console.
			print("[drive] %s at %.1f s: %s" % [type, sim.seconds(), JSON.stringify(event)])
		if type == "arrived":
			print("[drive] arrived at %s (frame %d)" % [sim.clock.text(), _frames])
			# Whoever he carried all the way is a wedding guest from now on (GDD 11.5).
			if Game.add_guest(GameData.as_string(event.get("guest"))):
				print("[drive] a new guest: %s" % GameData.as_string(event.get("guest")))
				if not _boss_spec.is_empty():
					Game.write_save(Game.saved_telling)
		if type == "arrived" and _boss_spec.is_empty():
			# Until the wedding room exists (M9) the night simply begins again.
			Game.write_save({})
			sim.begin_telling(sim.run.table, sim.run.seed + 1)


func _process(delta: float) -> void:
	var snapshot: Dictionary = sim.snapshot()
	var cam_yaw: float = snapshot["cam_yaw"]
	var cam_pitch: float = snapshot["cam_pitch"]
	# Yaw toward the passenger (+X) is a negative turn about +Y. Sway rocks
	# the horizon (GDD 5.8): the camera rolls with the push.
	var sway: float = snapshot["sway"]
	_camera.rotation = Vector3(deg_to_rad(cam_pitch), -deg_to_rad(cam_yaw), deg_to_rad(sway * sim.tuning.f("sway_view_roll")))
	_cabin.apply(snapshot)
	_hand.apply(snapshot)
	_road.apply(snapshot, delta)
	_stop.apply(snapshot)
	_sky.apply(snapshot)
	_post_fx.apply(snapshot, delta)
	_pointer.apply(snapshot, _camera, _cabin)
	_hud.apply(snapshot)
	Audio.apply(snapshot)

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
	var leg_seed: int = int(str(Game.args.get("seed", "1"))) + _legs_begun
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
	var boss_seed: int = int(str(Game.args.get("seed", "1"))) + _legs_begun
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
