class_name VehicleView
extends Node3D
## One vehicle on the road (GDD 16.1): a flat box with head and tail quads,
## and indicator quads that blink while it signals a lane change. A police
## car carries a beacon; the last car of the motorcade carries a sign.
## Pooled by RoadView. Reads the snapshot; changes nothing.

var type_id: StringName = &""

var _signals_left: Array[Node3D] = []
var _signals_right: Array[Node3D] = []
## Snapshot time at which the signal now showing began, or -1.
var _signal_since: float = -1.0
var _beacon: Node3D = null
var _sign: Label3D = null
var _sign_at: Vector3 = Vector3.ZERO
var _factory: PlaceholderFactory


func setup(type_record: Dictionary, factory: PlaceholderFactory, light_height: float, sign_lift: float) -> void:
	_factory = factory
	type_id = StringName(GameData.as_string(type_record.get("id")))
	var body_id: String = GameData.as_string(type_record.get("placeholder"))
	var size: Vector3 = factory.size_of(body_id)
	var body: Node3D = factory.make_world(body_id)
	body.position = Vector3(0.0, size.y * 0.5, 0.0)
	add_child(body)

	var half_w: float = size.x * 0.5
	var half_l: float = size.z * 0.5
	var lamp: Vector3 = factory.size_of("veh_taillight")
	var signal_lamp: Vector3 = factory.size_of("veh_signal")
	# The lamps sit half their own width in from the body's side, and the
	# indicators just above them.
	var inset: float = lamp.x
	var proud: float = lamp.y * 0.1
	var signal_height: float = light_height + (lamp.y + signal_lamp.y) * 0.5
	for side: float in [-1.0, 1.0]:
		var x: float = side * (half_w - inset)
		# Tail lights and rear indicators face the driver behind (+Z).
		_add_quad(factory, "veh_taillight", Vector3(x, light_height, half_l + proud), false)
		var rear: Node3D = _add_quad(factory, "veh_signal", Vector3(x, signal_height, half_l + proud), false)
		# Headlights and front indicators face the way it drives (-Z).
		_add_quad(factory, "veh_headlight", Vector3(x, light_height, -half_l - proud), true)
		var front: Node3D = _add_quad(factory, "veh_signal", Vector3(x, signal_height, -half_l - proud), true)
		rear.visible = false
		front.visible = false
		if side < 0.0:
			_signals_left.append(rear)
			_signals_left.append(front)
		else:
			_signals_right.append(rear)
			_signals_right.append(front)
	if type_id == EncounterSim.POLICE:
		_beacon = factory.make_world_light("veh_police_light")
		_beacon.position = Vector3(0.0, size.y + factory.size_of("veh_police_light").y * 0.5, 0.0)
		_beacon.visible = false
		add_child(_beacon)
	_sign_at = Vector3(0.0, size.y + sign_lift, half_l)


## Back to the pool: whoever takes this view next starts afresh.
func reset() -> void:
	_signal_since = -1.0
	if _beacon != null:
		_beacon.visible = false
	if _sign != null:
		_sign.visible = false


## `time` is the snapshot's clock and `blink_hz` the indicator rate: a signal
## is lit from its first frame. `beacon` lights a police car's beacon, which
## blinks at the same rate. `sign_text` is what the vehicle's sign says ("" for
## none) and `bend_shift` how far the bend of the road moves the vehicle
## sideways on screen, which a text does not follow by itself.
func apply(vehicle: Dictionary, local_position: Vector3, time: float, blink_hz: float,
		beacon: bool, sign_text: String, bend_shift: float) -> void:
	position = local_position
	var direction: int = vehicle["direction"]
	# An oncoming vehicle faces the other way; its left is then on our right.
	rotation.y = PI if direction < 0 else 0.0
	var signalling: int = vehicle["signalling"]
	if signalling == 0:
		_signal_since = -1.0
	elif _signal_since < 0.0:
		_signal_since = time
	var blink_on: bool = signalling != 0 and fmod((time - _signal_since) * blink_hz, 1.0) < 0.5
	var toward_right: bool = signalling * direction > 0
	for quad: Node3D in _signals_left:
		quad.visible = blink_on and not toward_right
	for quad: Node3D in _signals_right:
		quad.visible = blink_on and toward_right
	if _beacon != null:
		_beacon.visible = beacon and fmod(time * blink_hz, 1.0) < 0.5
	if sign_text.is_empty():
		if _sign != null:
			_sign.visible = false
		return
	if _sign == null:
		_sign = _factory.make("road_sign_text") as Label3D
		if _sign == null:
			return
		add_child(_sign)
	_sign.visible = true
	_sign.text = sign_text
	_sign.position = _sign_at + Vector3(bend_shift * float(direction), 0.0, 0.0)


func _add_quad(factory: PlaceholderFactory, id: String, at: Vector3, facing_forward: bool) -> Node3D:
	var quad: Node3D = factory.make_world_light(id)
	quad.position = at
	if facing_forward:
		quad.rotation.y = PI
	add_child(quad)
	return quad
