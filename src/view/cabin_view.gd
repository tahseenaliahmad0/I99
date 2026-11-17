class_name CabinView
extends Node3D
## The cabin (GDD 13.5, 16.1, 16.2): placeholder meshes built from
## placeholders.json and anchors.json. Reads the snapshot; changes nothing.
##
## Cabin frame: origin at the wheel hub, +X toward the passenger, +Y up,
## +Z toward the driver. This node sits at the hub.

const WHEEL_NODE: String = "Wheel"
const GEAR_LEVER_NODE: String = "GearLever"
const GEAR_LEVER_ANCHOR: String = "gear_lever"

var _factory: PlaceholderFactory
var _wheel: Node3D
var _lever_knob: Node3D
var _lever_rest: Vector3 = Vector3.ZERO
var _gate_scale: float = 0.0
var _outline: Node3D
## anchor id -> its marker node.
var _markers: Dictionary = {}
var _snapped: String = ""


func setup(data: GameData, factory: PlaceholderFactory) -> void:
	_factory = factory
	var tuning: Tuning = data.tuning
	_gate_scale = tuning.f("gate_view_scale")

	var props: Node3D = _group("Props")
	for prop: Dictionary in data.records("props"):
		var node: Node3D = factory.make(GameData.as_string(prop.get("placeholder")))
		node.name = GameData.as_string(prop.get("id"))
		node.position = GameData.as_vec3(prop.get("pos"))
		node.rotation_degrees = GameData.as_vec3(prop.get("rot"))
		props.add_child(node)

	_build_wheel(tuning)

	var anchors: Node3D = _group("Anchors")
	var default_marker: String = tuning.s("anchor_marker_default")
	for anchor: Dictionary in data.records("anchors"):
		var id: String = GameData.as_string(anchor.get("id"))
		# "placeholder": null means the anchor has nothing to draw (his own face).
		if anchor.has("placeholder") and anchor["placeholder"] == null:
			continue
		var marker: Node3D = factory.make(GameData.as_string(anchor.get("placeholder"), default_marker))
		marker.name = id
		marker.position = GameData.as_vec3(anchor.get("pos"))
		if id == GEAR_LEVER_ANCHOR:
			var lever: Node3D = _group(GEAR_LEVER_NODE)
			lever.add_child(marker)
			_lever_knob = marker
			_lever_rest = marker.position
		else:
			anchors.add_child(marker)
		_markers[id] = marker

	_outline = factory.make("anchor_outline")
	_outline.name = "SnapOutline"
	_outline.visible = false
	add_child(_outline)


func apply(snapshot: Dictionary) -> void:
	var wheel_angle: float = snapshot["wheel_angle"]
	# Clockwise for the driver, who looks along -Z, is a negative turn about +Z.
	_wheel.rotation.z = -deg_to_rad(wheel_angle)

	var lever: Vector2 = snapshot["lever"]
	if _lever_knob != null:
		_lever_knob.position = _lever_rest + Vector3(lever.x, 0.0, -lever.y) * _gate_scale

	var snapped: String = str(snapshot["hand_snap"])
	if snapped != _snapped:
		_snapped = snapped
	if _markers.has(_snapped):
		var marker: Node3D = _markers[_snapped]
		_outline.visible = true
		_outline.global_position = marker.global_position
	else:
		_outline.visible = false


## Where an anchor's marker is drawn, in world space (for overlays).
func marker_position(id: String) -> Vector3:
	if not _markers.has(id):
		return global_position
	var marker: Node3D = _markers[id]
	return marker.global_position


func _group(group_name: String) -> Node3D:
	var node: Node3D = get_node_or_null(group_name) as Node3D
	if node == null:
		node = Node3D.new()
		node.name = group_name
		add_child(node)
	return node


func _build_wheel(tuning: Tuning) -> void:
	_wheel = _group(WHEEL_NODE)
	# The disc's axis is the column: turn the cylinder to face the driver.
	var disc: Node3D = _factory.make("cabin_wheel")
	disc.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	_wheel.add_child(disc)
	var spoke: Node3D = _factory.make("cabin_wheel_spoke")
	spoke.position = Vector3(0.0, 0.0, _factory.size_of("cabin_wheel").y)
	_wheel.add_child(spoke)
	# A mark at twelve o'clock so the wheel's angle can be read.
	var mark: Node3D = _factory.make("cabin_wheel_mark")
	mark.position = Vector3(0.0, tuning.f("wheel_radius"), _factory.size_of("cabin_wheel").y)
	_wheel.add_child(mark)
