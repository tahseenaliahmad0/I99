class_name HandView
extends Node3D
## The hand and the right arm (GDD 13.5, 16.1): two capsules and a box,
## solved analytically. The shoulder is fixed; for targets beyond reach it
## slides toward the target by up to shoulder_slide_max. No Skeleton3D, no
## engine IK. Reads the snapshot; changes nothing.

var _shoulder: Vector3 = Vector3.ZERO
var _upper_length: float = 0.0
var _forearm_length: float = 0.0
var _slide_max: float = 0.0
var _pole: Vector3 = Vector3.DOWN

var _upper: MeshInstance3D
var _forearm: MeshInstance3D
var _hand: Node3D
var _upper_mesh: CapsuleMesh
var _forearm_mesh: CapsuleMesh


func setup(data: GameData, factory: PlaceholderFactory, space: CabinSpace) -> void:
	var tuning: Tuning = data.tuning
	_shoulder = space.shoulder
	_upper_length = tuning.f("arm_upper_length")
	_forearm_length = tuning.f("arm_forearm_length")
	_slide_max = tuning.f("shoulder_slide_max")
	_pole = Vector3(tuning.fi("arm_pole", 0), tuning.fi("arm_pole", 1), tuning.fi("arm_pole", 2)).normalized()

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
