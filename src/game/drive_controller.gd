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
var _shot_frame: int = 0
var _frames: int = 0
## `--leg=<id>[,act[,modifier]]`: the leg being driven, and how many of it
## have been started (each with the next seed).
var _leg_spec: String = ""
var _legs_begun: int = 0
var _plan: Dictionary = {}
## `--bot=`: until the DriverBot of GDD 13.8 is built (M11), any value holds
## the car on the plan's line, which is enough to look at a leg.
var _bot: bool = false

@onready var _camera: Camera3D = $Camera3D
@onready var _cabin: CabinView = $Cabin
@onready var _hand: HandView = $Cabin/Hand
@onready var _road: RoadView = $Road
@onready var _sky: SkyView = $Sky
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
	_sky.setup(data, _factory)
	_pointer.setup(data, _factory)
	sim.rng.reseed(int(str(Game.args.get("seed", "1"))))
	_bot = Game.args.has("bot")
	if Game.args.has("leg"):
		_leg_spec = str(Game.args["leg"])
		_begin_leg()
	else:
		sim.free_traffic_per_km = tuning.f("free_traffic_per_km")

	if Game.args.has("aim"):
		_aim_anchor = sim.hand.anchor_index(StringName(str(Game.args["aim"])))
		if _aim_anchor == HandSim.NO_ANCHOR:
			push_error("Drive: --aim names an unknown anchor '%s'" % str(Game.args["aim"]))
	if Game.args.has("shot"):
		_shot_path = str(Game.args["shot"])
		_shot_frame = tuning.i("screenshot_frame")
		if Game.args.has("shot-frame"):
			_shot_frame = maxi(1, str(Game.args["shot-frame"]).to_int())

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
	if _bot and sim.leg.active and not sim.leg.on_side_road:
		sim.car.x = _line_x(sim.car.s)
	sim.step(_input)
	for event: Dictionary in sim.drain_events():
		Events.emit_event(GameData.as_string(event.get("type")), event)


func _process(delta: float) -> void:
	var snapshot: Dictionary = sim.snapshot()
	var cam_yaw: float = snapshot["cam_yaw"]
	var cam_pitch: float = snapshot["cam_pitch"]
	# Yaw toward the passenger (+X) is a negative turn about +Y.
	_camera.rotation = Vector3(deg_to_rad(cam_pitch), -deg_to_rad(cam_yaw), 0.0)
	_cabin.apply(snapshot)
	_hand.apply(snapshot)
	_road.apply(snapshot, delta)
	_sky.apply(snapshot)
	_pointer.apply(snapshot, _camera, _cabin)
	_hud.apply(snapshot)

	_frames += 1
	if not _shot_path.is_empty() and _frames == _shot_frame:
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
	_plan = LegGenerator.generate(data, leg_id, act, leg_seed, modifier)
	sim.gate.reset(3)
	sim.begin_leg(_plan)
	print("[drive] leg %s act %d seed %d modifier '%s'" % [leg_id, act, leg_seed, modifier])


## Where across the road the plan's line is at `s`: the middle of the lane
## the plan drives in, moving over during gen_lane_change metres.
func _line_x(s: float) -> float:
	var path: Array = GameData.as_array(_plan.get("path"))
	if path.is_empty():
		return sim.car.x
	var change: float = Game.data.tuning.f("gen_lane_change")
	var x: float = _lane_x(GameData.as_int(GameData.as_array(path[0])[1]))
	for index: int in range(1, path.size()):
		var at: Array = GameData.as_array(path[index])
		var from_s: float = GameData.as_float(at[0])
		if s < from_s:
			break
		var before: Array = GameData.as_array(path[index - 1])
		x = lerpf(_lane_x(GameData.as_int(before[1])), _lane_x(GameData.as_int(at[1])), clampf((s - from_s) / change, 0.0, 1.0))
	return x


func _lane_x(lane: int) -> float:
	if lane == LegGenerator.SHOULDER_LANE:
		return (sim.car.road_right() + sim.car.guardrail_x()) * 0.5
	return sim.car.lane_center(lane)


## Saves one rendered frame and quits (needs a real renderer; see DECISIONS D-015).
func _save_shot() -> void:
	var texture: ViewportTexture = get_viewport().get_texture()
	var image: Image = texture.get_image() if texture != null else null
	if image == null or image.is_empty():
		print("[drive] no image to save: this renderer draws nothing")
	else:
		var err: Error = image.save_png(_shot_path)
		print("[drive] shot %s (%s)" % [_shot_path, error_string(err)])
	get_tree().quit()
