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
## anchor id -> where it is, for drawing items in their slots.
var _anchor_pos: Dictionary = {}
## slot id -> anchor id.
var _slot_anchor: Dictionary = {}
var _lamps_off: Array[Node3D] = []
var _lamps_on: Array[Node3D] = []
var _cash: Node3D
var _cash_per_note: float = 1.0
var _item_lift: float = 0.0
## item id -> its node; and the glowing tip shown while a smoke burns.
var _item_nodes: Dictionary = {}
var _lit_tip: Node3D
var _visor_down: Node3D
var _items: Node3D


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

	for anchor: Dictionary in data.records("anchors"):
		_anchor_pos[GameData.as_string(anchor.get("id"))] = GameData.as_vec3(anchor.get("pos"))
	for slot: Dictionary in data.records("slots"):
		_slot_anchor[GameData.as_string(slot.get("id"))] = GameData.as_string(slot.get("anchor"))
	_item_lift = tuning.f("item_lift")
	_items = _group("ItemMounts")

	# Five warning lamps on the dash (GDD 6.3, 16.3), one spare for a Bull bar.
	var dash: Node3D = _group("Dash")
	var first: Vector3 = Vector3(tuning.fi("lamp_row_pos", 0), tuning.fi("lamp_row_pos", 1), tuning.fi("lamp_row_pos", 2))
	for index: int in tuning.i("lamp_capacity") + 1:
		var at: Vector3 = first + Vector3(tuning.f("lamp_spacing") * float(index), 0.0, 0.0)
		var off: Node3D = factory.make("cabin_lamp_off")
		var on: Node3D = factory.make("cabin_lamp_on")
		off.position = at
		on.position = at
		on.visible = false
		dash.add_child(off)
		dash.add_child(on)
		_lamps_off.append(off)
		_lamps_on.append(on)

	# Cash: a stack of notes that shrinks and grows (GDD 16.3).
	_cash = factory.make("cabin_cash")
	_cash.position = Vector3(tuning.fi("cash_stack_pos", 0), tuning.fi("cash_stack_pos", 1), tuning.fi("cash_stack_pos", 2))
	_cash_per_note = tuning.f("cash_per_note")
	dash.add_child(_cash)

	_lit_tip = factory.make("item_cigarette_lit")
	_lit_tip.visible = false
	_items.add_child(_lit_tip)

	_visor_down = factory.make("cabin_visor_down")
	_visor_down.position = Vector3(tuning.fi("visor_down_pos", 0), tuning.fi("visor_down_pos", 1), tuning.fi("visor_down_pos", 2))
	_visor_down.visible = false
	_group("Visor").add_child(_visor_down)


func apply(snapshot: Dictionary) -> void:
	var wheel_angle: float = snapshot["wheel_angle"]
	# Clockwise for the driver, who looks along -Z, is a negative turn about +Z.
	_wheel.rotation.z = -deg_to_rad(wheel_angle)

	var lever: Vector2 = snapshot["lever"]
	if _lever_knob != null:
		_lever_knob.position = _lever_rest + Vector3(lever.x, 0.0, -lever.y) * _gate_scale

	# An anchor is drawn only while something can be done there.
	var in_use: Array[StringName] = snapshot["anchors_in_use"]
	for id: Variant in _markers:
		var marker_node: Node3D = _markers[id]
		marker_node.visible = in_use.has(StringName(str(id)))

	var capacity: int = snapshot["lamp_capacity"]
	var lit: int = snapshot["lamps"]
	for index: int in _lamps_off.size():
		_lamps_off[index].visible = index < capacity and index >= lit
		_lamps_on[index].visible = index < lit

	var cash: float = snapshot["cash"]
	_cash.scale.y = maxf(cash / _cash_per_note, 0.05)

	_visor_down.visible = snapshot["visor_down"]
	var items: Array[Dictionary] = snapshot["items"]
	_show_items(items)

	var snapped: String = str(snapshot["hand_snap"])
	if snapped != _snapped:
		_snapped = snapped
	if _markers.has(_snapped):
		var marker: Node3D = _markers[_snapped]
		_outline.visible = true
		_outline.global_position = marker.global_position
	else:
		_outline.visible = false


## Each item is drawn at its slot (GDD 7.1), from its own placeholder
## "item_<id>" (or "item_default"). An empty one is hidden.
func _show_items(items: Array[Dictionary]) -> void:
	var seen: Dictionary = {}
	var burning: bool = false
	for item: Dictionary in items:
		var id: String = str(item["id"])
		seen[id] = true
		var node: Node3D = null
		if _item_nodes.has(id):
			node = _item_nodes[id]
		else:
			var placeholder: String = "item_" + id
			node = _factory.make(placeholder if _factory.has(placeholder) else "item_default")
			_items.add_child(node)
			_item_nodes[id] = node
		var anchor: String = str(_slot_anchor.get(str(item["slot"]), ""))
		var supply: int = item["supply"]
		node.visible = _anchor_pos.has(anchor) and supply != 0
		if _anchor_pos.has(anchor):
			var at: Vector3 = _anchor_pos[anchor]
			node.position = at + Vector3(0.0, _item_lift, 0.0)
			if item["burning"]:
				burning = true
				_lit_tip.position = node.position + Vector3(0.03, 0.01, 0.0)
	_lit_tip.visible = burning
	for id: Variant in _item_nodes:
		if not seen.has(id):
			var gone: Node3D = _item_nodes[id]
			gone.visible = false


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
