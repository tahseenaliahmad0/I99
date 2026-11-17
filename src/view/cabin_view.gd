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
## Anchors whose marker hangs on a node of its own (GDD 13.5).
const NAMED_NODES: Dictionary = {"mirror": "Mirror", "visor": "Visor", "seat": "Seat", "glovebox": "Glovebox"}

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
var _clock: Label3D
## anchor id -> where its marker is drawn when nothing has moved the anchor,
## and how far that is from the anchor itself.
var _marker_home: Dictionary = {}
var _marker_offset: Dictionary = {}
## Things fitted to the car: [item id, node] for each (GDD 7.6).
var _fittings: Array[Array] = []
## item id -> the magenta tag on it while it is contraband (GDD 16.1).
var _tags: Dictionary = {}
var _mirror: Node3D
var _ring_bob: float = 0.0
var _ring_hz: float = 0.0


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
		# An anchor inside a prop shows its marker on the prop's surface.
		marker.position = GameData.as_vec3(anchor.get("pos")) + GameData.as_vec3(anchor.get("marker_offset"))
		if id == GEAR_LEVER_ANCHOR:
			var lever: Node3D = _group(GEAR_LEVER_NODE)
			lever.add_child(marker)
			_lever_knob = marker
			_lever_rest = marker.position
		elif NAMED_NODES.has(id):
			# The nodes GDD 13.5 names: later milestones hang the mirror image,
			# the visor's flip and the glovebox door on them.
			_group(GameData.as_string(NAMED_NODES[id])).add_child(marker)
		else:
			anchors.add_child(marker)
		_markers[id] = marker
		_marker_home[id] = marker.position
		_marker_offset[id] = GameData.as_vec3(anchor.get("marker_offset"))

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

	# The dashboard clock (GDD 6.4, 16.3).
	_clock = factory.make("cabin_clock_text") as Label3D
	if _clock != null:
		_clock.position = Vector3(tuning.fi("dash_clock_pos", 0), tuning.fi("dash_clock_pos", 1), tuning.fi("dash_clock_pos", 2))
		dash.add_child(_clock)

	# What is fitted to the car shows where it is fitted, on the wheel or off it.
	var fitted: Node3D = _group("Fittings")
	for fitting: Dictionary in data.records("fittings"):
		var node: Node3D = factory.make(GameData.as_string(fitting.get("placeholder")))
		node.name = GameData.as_string(fitting.get("id"))
		node.position = GameData.as_vec3(fitting.get("pos"))
		node.visible = false
		if GameData.as_bool(fitting.get("on_wheel")):
			_wheel.add_child(node)
		else:
			fitted.add_child(node)
		_fittings.append([GameData.as_string(fitting.get("item")), node])
	_mirror = get_node_or_null("Mirror") as Node3D
	_ring_bob = tuning.f("phone_ring_bob")
	_ring_hz = tuning.f("phone_ring_hz")

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

	# An anchor is drawn only while something can be done there, and where it
	# is now: an Adaptation may have moved it (the crossover stalk).
	var in_use: Array[StringName] = snapshot["anchors_in_use"]
	var moves: Dictionary = snapshot["anchor_moves"]
	for id: Variant in _markers:
		var marker_node: Node3D = _markers[id]
		marker_node.visible = in_use.has(StringName(str(id)))
		var home: Vector3 = _marker_home[id]
		var offset: Vector3 = _marker_offset[id]
		marker_node.position = (GameData.as_vec3(moves[str(id)]) + offset) if moves.has(str(id)) else home
	if _mirror != null:
		var mirror_scale: float = snapshot["mirror_scale"]
		_mirror.scale = Vector3(mirror_scale, 1.0, 1.0)

	var capacity: int = snapshot["lamp_capacity"]
	var lit: int = snapshot["lamps"]
	for index: int in _lamps_off.size():
		_lamps_off[index].visible = index < capacity and index >= lit
		_lamps_on[index].visible = index < lit

	var cash: float = snapshot["cash"]
	_cash.scale.y = maxf(cash / _cash_per_note, 0.05)
	if _clock != null:
		_clock.text = str(snapshot["clock"])

	_visor_down.visible = snapshot["visor_down"]
	var items: Array[Dictionary] = snapshot["items"]
	var time: float = snapshot["time"]
	_show_items(items, moves, str(snapshot["caller"]) != "", time)

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
func _show_items(items: Array[Dictionary], moves: Dictionary, ringing: bool, time: float) -> void:
	var seen: Dictionary = {}
	var burning: bool = false
	for fitting: Array in _fittings:
		var fitted: Node3D = fitting[1]
		fitted.visible = false
	for item: Dictionary in items:
		var id: String = str(item["id"])
		seen[id] = true
		for fitting: Array in _fittings:
			if fitting[0] == id:
				var fitted: Node3D = fitting[1]
				fitted.visible = true
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
			var at: Vector3 = GameData.as_vec3(moves[anchor]) if moves.has(anchor) else _anchor_pos[anchor]
			node.position = at + Vector3(0.0, _item_lift, 0.0)
			if ringing and id == "phone":
				# The ringing phone shakes on its mount, slowly enough to be no flash (GDD 16.4).
				node.position.y += _ring_bob * (0.5 + 0.5 * sin(TAU * _ring_hz * time))
			if item["burning"]:
				burning = true
				_lit_tip.position = node.position + Vector3(0.03, 0.01, 0.0)
		# Contraband wears a magenta tag (GDD 16.1).
		if item["contraband"]:
			var tag: Node3D = null
			if _tags.has(id):
				tag = _tags[id]
			else:
				tag = _factory.make("item_contraband_tag")
				_items.add_child(tag)
				_tags[id] = tag
			tag.visible = node.visible
			tag.position = node.position + Vector3(0.0, _factory.size_of("item_contraband_tag").y * 2.5, 0.0)
	_lit_tip.visible = burning
	for id: Variant in _item_nodes:
		if not seen.has(id):
			var gone: Node3D = _item_nodes[id]
			gone.visible = false
	for id: Variant in _tags:
		if not seen.has(id):
			var loose: Node3D = _tags[id]
			loose.visible = false


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
