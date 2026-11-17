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
	_sky.setup(data)
	_pointer.setup(data, _factory)
	sim.rng.reseed(int(str(Game.args.get("seed", "1"))))
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
	_sky.apply(1.0)
	_pointer.apply(snapshot, _camera, _cabin)
	_hud.apply(snapshot)

	_frames += 1
	if not _shot_path.is_empty() and _frames == _shot_frame:
		_save_shot()


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
