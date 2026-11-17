class_name VehicleView
extends Node3D
## One vehicle on the road (GDD 16.1): a flat box with head and tail quads,
## and indicator quads that blink while it signals a lane change. Pooled by
## RoadView. Reads the snapshot; changes nothing.

var type_id: StringName = &""

var _signals_left: Array[Node3D] = []
var _signals_right: Array[Node3D] = []


func setup(type_record: Dictionary, factory: PlaceholderFactory, light_height: float) -> void:
	type_id = StringName(GameData.as_string(type_record.get("id")))
	var body_id: String = GameData.as_string(type_record.get("placeholder"))
	var size: Vector3 = factory.size_of(body_id)
	var body: Node3D = factory.make_world(body_id)
	body.position = Vector3(0.0, size.y * 0.5, 0.0)
	add_child(body)

	var half_w: float = size.x * 0.5
	var half_l: float = size.z * 0.5
	var inset: float = factory.size_of("veh_taillight").x * 0.5 + 0.08
	var proud: float = 0.02
	for side: float in [-1.0, 1.0]:
		var x: float = side * (half_w - inset)
		# Tail lights and rear indicators face the driver behind (+Z).
		_add_quad(factory, "veh_taillight", Vector3(x, light_height, half_l + proud), false)
		var rear: Node3D = _add_quad(factory, "veh_signal", Vector3(x, light_height + 0.2, half_l + proud), false)
		# Headlights and front indicators face the way it drives (-Z).
		_add_quad(factory, "veh_headlight", Vector3(x, light_height, -half_l - proud), true)
		var front: Node3D = _add_quad(factory, "veh_signal", Vector3(x, light_height + 0.2, -half_l - proud), true)
		rear.visible = false
		front.visible = false
		if side < 0.0:
			_signals_left.append(rear)
			_signals_left.append(front)
		else:
			_signals_right.append(rear)
			_signals_right.append(front)


## `blink_on` is the shared indicator phase.
func apply(vehicle: Dictionary, local_position: Vector3, blink_on: bool) -> void:
	position = local_position
	var direction: int = vehicle["direction"]
	# An oncoming vehicle faces the other way; its left is then on our right.
	rotation.y = PI if direction < 0 else 0.0
	var signalling: int = vehicle["signalling"]
	var toward_right: bool = signalling * direction > 0
	for quad: Node3D in _signals_left:
		quad.visible = blink_on and signalling != 0 and not toward_right
	for quad: Node3D in _signals_right:
		quad.visible = blink_on and signalling != 0 and toward_right


func _add_quad(factory: PlaceholderFactory, id: String, at: Vector3, facing_forward: bool) -> Node3D:
	var quad: Node3D = factory.make_world(id)
	quad.position = at
	if facing_forward:
		quad.rotation.y = PI
	add_child(quad)
	return quad
