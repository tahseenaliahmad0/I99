class_name HandView
extends Node3D
## The hand and the right arm (GDD 13.5, 16.1): two capsules and a box,
## solved analytically. The shoulder is fixed; for targets beyond reach it
## slides toward the target by up to shoulder_slide_max. No Skeleton3D, no
## engine IK. Reads the snapshot; changes nothing.

## What is drawn in his hand while he holds his own phone to his ear.
const PHONE: String = "phone"

var _shoulder: Vector3 = Vector3.ZERO
var _upper_length: float = 0.0
var _forearm_length: float = 0.0
var _slide_max: float = 0.0
var _pole: Vector3 = Vector3.DOWN
var _gate_scale: float = 0.0

var _upper: MeshInstance3D
var _forearm: MeshInstance3D
var _hand: Node3D
var _upper_mesh: CapsuleMesh
var _forearm_mesh: CapsuleMesh
var _factory: PlaceholderFactory
## What the hand carries: item id -> its node (GDD 4.4, DRAG_TO).
var _carried: Dictionary = {}
var _carried_lift: float = 0.0
## The Phantom's ghost (GDD 7.9): a faint left arm and hand from the sleeve.
var _ghost_arm: MeshInstance3D
var _ghost_arm_mesh: CapsuleMesh
var _ghost_hand: Node3D
var _ghost_from: Vector3 = Vector3.ZERO
## anchor id -> where it is.
var _anchor_pos: Dictionary = {}


func setup(data: GameData, factory: PlaceholderFactory, space: CabinSpace) -> void:
	var tuning: Tuning = data.tuning
	_shoulder = space.shoulder
	_upper_length = tuning.f("arm_upper_length")
	_forearm_length = tuning.f("arm_forearm_length")
	_slide_max = tuning.f("shoulder_slide_max")
	_gate_scale = tuning.f("gate_view_scale")
	_pole = Vector3(tuning.fi("arm_pole", 0), tuning.fi("arm_pole", 1), tuning.fi("arm_pole", 2)).normalized()

	_factory = factory
	_carried_lift = tuning.f("item_lift")
	for anchor: Dictionary in data.records("anchors"):
		_anchor_pos[GameData.as_string(anchor.get("id"))] = GameData.as_vec3(anchor.get("pos"))
	for prop: Dictionary in data.records("props"):
		if GameData.as_string(prop.get("id")) == "left_sleeve":
			_ghost_from = GameData.as_vec3(prop.get("pos"))
	_ghost_arm = factory.make("ghost_arm") as MeshInstance3D
	_ghost_hand = factory.make("ghost_hand")
	var faint: float = tuning.f("ghost_alpha")
	if _ghost_arm != null:
		_ghost_arm_mesh = _ghost_arm.mesh.duplicate() as CapsuleMesh
		_ghost_arm.mesh = _ghost_arm_mesh
		_make_faint(_ghost_arm, faint)
		_ghost_arm.visible = false
		add_child(_ghost_arm)
	_make_faint(_ghost_hand as MeshInstance3D, faint)
	_ghost_hand.visible = false
	add_child(_ghost_hand)

	_upper = factory.make("arm_upper") as MeshInstance3D
	_forearm = factory.make("arm_forearm") as MeshInstance3D
	_hand = factory.make("hand")
	if _upper != null:
		# Each arm owns its mesh: its length changes as the arm stretches.
		_upper_mesh = _upper.mesh.duplicate() as CapsuleMesh
		_upper.mesh = _upper_mesh
		add_child(_upper)
	if _forearm != null:
		_forearm_mesh = _forearm.mesh.duplicate() as CapsuleMesh
		_forearm.mesh = _forearm_mesh
		add_child(_forearm)
	add_child(_hand)


func apply(snapshot: Dictionary) -> void:
	var hand: Vector3 = snapshot["hand_pos"]
	# On the gear lever the hand is on the knob, which moves with the lever
	# (CabinView draws the knob the same way).
	if snapshot["hand_at"] == CabinView.GEAR_LEVER_ANCHOR:
		var lever: Vector2 = snapshot["lever"]
		hand += Vector3(lever.x, 0.0, -lever.y) * _gate_scale
	# Lag (GDD 5.8): the hand trails the wheel. It is drawn where the wheel
	# was when the car last answered it.
	if snapshot["hand_gripping"]:
		var wheel_angle: float = snapshot["wheel_angle"]
		var steer_angle: float = snapshot["steer_angle"]
		hand = hand.rotated(Vector3.BACK, deg_to_rad(wheel_angle - steer_angle))
	var solved: Dictionary = solve(_shoulder, hand, _upper_length, _forearm_length, _slide_max, _pole)
	var shoulder: Vector3 = solved["shoulder"]
	var elbow: Vector3 = solved["elbow"]
	_place_capsule(_upper, _upper_mesh, shoulder, elbow)
	_place_capsule(_forearm, _forearm_mesh, elbow, hand)
	var along: Vector3 = hand - elbow
	if along.length_squared() > 0.0:
		_hand.transform = Transform3D(_basis_along(along, Vector3.UP), hand)
	else:
		_hand.position = hand
	var carrying: String = str(snapshot["carrying"])
	if carrying.is_empty() and snapshot["at_ear"]:
		# The Call (GDD 10.4): his own phone, held to his ear.
		carrying = PHONE
	_show_carried(carrying, hand)
	var moves: Dictionary = snapshot["anchor_moves"]
	var ghost_progress: float = snapshot["ghost_progress"]
	_show_ghost(str(snapshot["ghost_at"]), ghost_progress, moves)


## What he carries goes with the hand: the item's own placeholder, or a
## plain box for what has none (his licence, banknotes).
func _show_carried(id: String, hand: Vector3) -> void:
	for key: Variant in _carried:
		var other: Node3D = _carried[key]
		other.visible = key == id
	if id.is_empty():
		return
	if not _carried.has(id):
		var placeholder: String = "item_" + id
		var node: Node3D = _factory.make(placeholder if _factory.has(placeholder) else "hand_carried")
		add_child(node)
		_carried[id] = node
	var carried: Node3D = _carried[id]
	carried.visible = true
	carried.position = hand + Vector3(0.0, _carried_lift, 0.0)


## The ghost of his left hand goes from the pinned sleeve toward the control
## and through it (GDD 7.9), faint.
func _show_ghost(anchor: String, progress: float, moves: Dictionary) -> void:
	var showing: bool = not anchor.is_empty() and _anchor_pos.has(anchor)
	_ghost_hand.visible = showing
	if _ghost_arm != null:
		_ghost_arm.visible = showing
	if not showing:
		return
	var to: Vector3 = GameData.as_vec3(moves[anchor]) if moves.has(anchor) else _anchor_pos[anchor]
	# It passes through the control: a little beyond it at the end.
	var at: Vector3 = _ghost_from.lerp(to, progress * 1.15)
	_place_capsule(_ghost_arm, _ghost_arm_mesh, _ghost_from, at)
	var along: Vector3 = at - _ghost_from
	if along.length_squared() > 0.0:
		_ghost_hand.transform = Transform3D(_basis_along(along, Vector3.UP), at)


## Makes a placeholder see-through: its own material, with an alpha.
func _make_faint(node: MeshInstance3D, alpha: float) -> void:
	if node == null:
		return
	var material: StandardMaterial3D = null
	if node.material_override is StandardMaterial3D:
		material = (node.material_override as StandardMaterial3D).duplicate() as StandardMaterial3D
	elif node.mesh != null and node.mesh.surface_get_material(0) is StandardMaterial3D:
		material = (node.mesh.surface_get_material(0) as StandardMaterial3D).duplicate() as StandardMaterial3D
	if material == null:
		return
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color.a = alpha
	node.material_override = material


## Two-bone solve. Returns { "shoulder": Vector3, "elbow": Vector3 }.
## Pure and static so it can be checked without a scene.
static func solve(shoulder: Vector3, hand: Vector3, upper: float, forearm: float,
		slide_max: float, pole: Vector3) -> Dictionary:
	var root: Vector3 = shoulder
	var to_hand: Vector3 = hand - root
	var distance: float = to_hand.length()
	var reach: float = upper + forearm
	if distance > reach and distance > 0.0:
		# Beyond reach: he leans. The shoulder slides toward the target.
		root += to_hand / distance * minf(distance - reach, slide_max)
		to_hand = hand - root
		distance = to_hand.length()
	if distance <= 0.0:
		return {"shoulder": root, "elbow": root + pole * upper}
	var direction: Vector3 = to_hand / distance
	if distance >= reach:
		# Still beyond reach: a straight arm; the forearm is drawn longer.
		return {"shoulder": root, "elbow": root + direction * upper}
	# Triangle with sides upper, forearm, distance.
	var along: float = (upper * upper - forearm * forearm + distance * distance) / (2.0 * distance)
	var out: float = sqrt(maxf(upper * upper - along * along, 0.0))
	var side: Vector3 = pole - direction * pole.dot(direction)
	if side.length_squared() <= 0.000001:
		side = direction.cross(Vector3.RIGHT)
	side = side.normalized()
	return {"shoulder": root, "elbow": root + direction * along + side * out}


func _place_capsule(node: MeshInstance3D, mesh: CapsuleMesh, from: Vector3, to: Vector3) -> void:
	if node == null or mesh == null:
		return
	var along: Vector3 = to - from
	var length: float = along.length()
	if length <= 0.0:
		node.visible = false
		return
	node.visible = true
	mesh.height = maxf(length + mesh.radius * 2.0, mesh.radius * 2.0)
	node.transform = Transform3D(_basis_along(along, Vector3.FORWARD), (from + to) * 0.5)


## A basis whose Y axis runs along `direction`.
func _basis_along(direction: Vector3, hint: Vector3) -> Basis:
	var y: Vector3 = direction.normalized()
	var x: Vector3 = y.cross(hint)
	if x.length_squared() <= 0.000001:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z: Vector3 = x.cross(y)
	return Basis(x, y, z)
