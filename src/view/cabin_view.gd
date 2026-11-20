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
const MIRROR_ANCHOR: String = "mirror"
## What a slot that takes the tea holds.
const DRINK: String = "drink"
const POCKET_ANCHOR: String = "pocket"
## Who watches him, as the snapshot's "suspicion_by" names a Patrol.
const PATROL: String = "patrol"
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
var _ring_bob: float = 0.0
var _ring_hz: float = 0.0
## Props that show a cabin switch: [node, the flags it is drawn under, whether it blinks].
var _switch_props: Array[Array] = []
var _blink_hz: float = 1.0
## The mirror's glass; in it, the lights of what comes up behind him in the
## dust (GDD 10.3) and the blue of a Patrol that has him in view (GDD 16.3).
var _mirror_glass: Node3D
var _mirror_lights: Array[Node3D] = []
var _mirror_blue: Node3D
var _mirror_at: Vector3 = Vector3.ZERO
var _mirror_proud: float = 0.0
var _light_grow: Vector2 = Vector2.ONE
var _light_spread: Vector2 = Vector2.ZERO
var _rear_end_tell: float = 1.0
var _suspicion_max: float = 100.0
## The glovebox's cells, in order, and where their middle is on its open door.
var _cells: PackedStringArray = PackedStringArray()
var _cell_pos: Vector3 = Vector3.ZERO
var _cell_spread: float = 0.0
## His own phone, seen at his pocket while it rings (GDD 10.4).
var _pocket_phone: Node3D
## Whoever rides in the seat (GDD 8, 16.1): a purple capsule; the arm they
## reach out with (to the wheel, across the lever, with the tea); the drum.
var _passenger: Node3D
var _passenger_at: Vector3 = Vector3.ZERO
var _passenger_arm: MeshInstance3D
var _arm_from: Vector3 = Vector3.ZERO
var _sleep_tilt: float = 0.0
var _drum: Node3D
var _drum_at: Vector3 = Vector3.ZERO
var _drum_bob: float = 0.0
var _drum_hz: float = 0.0
var _grip_point: Vector3 = Vector3.ZERO
## The anchors of the cup holders: where the tea stands, and so the anchors a
## passenger moves when he holds it out.
var _held_out: PackedStringArray = PackedStringArray()


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
		if prop.has("alpha"):
			PlaceholderFactory.set_alpha(node, GameData.as_float(prop.get("alpha")))
		var conditions: Array = GameData.as_array(prop.get("flags"))
		var blinks: bool = GameData.as_bool(prop.get("blink"))
		if not conditions.is_empty() or blinks:
			_switch_props.append([node, conditions, blinks])
	_blink_hz = tuning.f("signal_blink_hz")
	_mirror_glass = props.get_node_or_null("mirror_glass") as Node3D

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
		if GameData.as_string(slot.get("id")).begins_with(ItemSim.GLOVEBOX):
			_cells.append(GameData.as_string(slot.get("id")))
		if GameData.as_array(slot.get("holds")).has(DRINK):
			_held_out.append(GameData.as_string(slot.get("anchor")))
	_cell_pos = Vector3(tuning.fi("glovebox_cell_pos", 0), tuning.fi("glovebox_cell_pos", 1), tuning.fi("glovebox_cell_pos", 2))
	_cell_spread = tuning.f("glovebox_cell_spread")
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
	_ring_bob = tuning.f("phone_ring_bob")
	_ring_hz = tuning.f("phone_ring_hz")

	# In the mirror: two lights that come nearer, and the Patrol's blue.
	var mirror: Node3D = _group("Mirror")
	_mirror_at = _anchor_pos.get("mirror", Vector3.ZERO)
	_mirror_proud = factory.size_of("cabin_mirror").z
	_light_grow = Vector2(tuning.fi("mirror_light_grow", 0), tuning.fi("mirror_light_grow", 1))
	_light_spread = Vector2(tuning.fi("mirror_light_spread", 0), tuning.fi("mirror_light_spread", 1))
	_rear_end_tell = GameData.as_float(GameData.as_dict(data.record("bosses", BossSim.STORM).get("storm")).get("rear_end_tell_s"), 1.0)
	_suspicion_max = tuning.f("suspicion_max")
	_mirror_blue = factory.make("cabin_mirror_blue")
	_mirror_blue.position = _mirror_at + Vector3(0.0, 0.0, _mirror_proud)
	_mirror_blue.visible = false
	mirror.add_child(_mirror_blue)
	for _side: int in 2:
		var light: Node3D = factory.make("cabin_mirror_light")
		light.visible = false
		mirror.add_child(light)
		_mirror_lights.append(light)

	_pocket_phone = factory.make("cabin_pocket_phone")
	_pocket_phone.visible = false
	_items.add_child(_pocket_phone)

	var seat: Node3D = _group("Seat")
	_passenger_at = Vector3(tuning.fi("passenger_pos", 0), tuning.fi("passenger_pos", 1), tuning.fi("passenger_pos", 2))
	_arm_from = Vector3(tuning.fi("passenger_arm_from", 0), tuning.fi("passenger_arm_from", 1), tuning.fi("passenger_arm_from", 2))
	_sleep_tilt = deg_to_rad(tuning.f("passenger_sleep_tilt"))
	_drum_at = Vector3(tuning.fi("drum_pos", 0), tuning.fi("drum_pos", 1), tuning.fi("drum_pos", 2))
	_drum_bob = tuning.f("drum_bob")
	_drum_hz = tuning.f("drum_hz")
	_grip_point = GameData.as_vec3(GameData.as_dict(data.root("anchors").get("points")).get("G"))
	_passenger = factory.make("cabin_passenger")
	_passenger.position = _passenger_at
	_passenger.visible = false
	seat.add_child(_passenger)
	_passenger_arm = factory.make("cabin_passenger_arm") as MeshInstance3D
	if _passenger_arm != null:
		_passenger_arm.visible = false
		seat.add_child(_passenger_arm)
	_drum = factory.make("cabin_drum")
	_drum.position = _drum_at
	_drum.visible = false
	seat.add_child(_drum)

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
	_show_mirror(snapshot)
	_show_passenger(snapshot, moves)

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
	var flags: Dictionary = snapshot["flags"]
	_show_switches(flags, time)
	# Noor's call rings in his pocket (GDD 10.4); any other on the mount.
	var caller: String = str(snapshot["caller"])
	var his_own: bool = caller == DriveSim.NOOR
	_show_items(items, moves, caller != "" and not his_own, time, GameData.as_bool(flags.get(ItemSim.FLAG_GLOVEBOX)))
	_pocket_phone.visible = his_own and _anchor_pos.has(POCKET_ANCHOR)
	if _pocket_phone.visible:
		var pocket: Vector3 = _anchor_pos[POCKET_ANCHOR]
		_pocket_phone.position = pocket + Vector3(0.0, _item_lift + _ring_bob * (0.5 + 0.5 * sin(TAU * _ring_hz * time)), 0.0)

	var snapped: String = str(snapshot["hand_snap"])
	if snapped != _snapped:
		_snapped = snapped
	if _markers.has(_snapped):
		var marker: Node3D = _markers[_snapped]
		_outline.visible = true
		_outline.global_position = marker.global_position
	else:
		_outline.visible = false


## A prop that shows a cabin switch (the window's glass, the hazard lamp, the
## glovebox's door and what lies in it) is drawn while every flag it names is
## as it names it; one that blinks comes and goes at the indicators' rate.
func _show_switches(flags: Dictionary, time: float) -> void:
	var blink_on: bool = fmod(time * _blink_hz, 1.0) < 0.5
	for entry: Array in _switch_props:
		var node: Node3D = entry[0]
		var shown: bool = blink_on or not GameData.as_bool(entry[2])
		for condition: Variant in GameData.as_array(entry[1]):
			var word: String = str(condition)
			var wants_off: bool = word.begins_with("!")
			if GameData.as_bool(flags.get(StringName(word.trim_prefix("!")))) == wants_off:
				shown = false
		node.visible = shown


## The mirror (GDD 16.3): as wide as what is fitted makes it; the lights of
## what comes up behind him in the dust, nearer and wider apart until it is
## on him; and the blue of a Patrol, brighter the more it suspects.
func _show_mirror(snapshot: Dictionary) -> void:
	var mirror_scale: float = snapshot["mirror_scale"]
	if _mirror_glass != null:
		_mirror_glass.scale = Vector3(mirror_scale, 1.0, 1.0)
	if _markers.has(MIRROR_ANCHOR):
		var marker: Node3D = _markers[MIRROR_ANCHOR]
		marker.scale = Vector3(mirror_scale, 1.0, 1.0)
	var rear_end_in: float = snapshot["rear_end_in"]
	var near: float = clampf(1.0 - rear_end_in / maxf(_rear_end_tell, 0.001), 0.0, 1.0)
	for index: int in _mirror_lights.size():
		var light: Node3D = _mirror_lights[index]
		light.visible = rear_end_in > 0.0
		var side: float = -1.0 if index == 0 else 1.0
		light.position = _mirror_at + Vector3(side * lerpf(_light_spread.x, _light_spread.y, near), 0.0, _mirror_proud * 1.5)
		light.scale = Vector3.ONE * lerpf(_light_grow.x, _light_grow.y, near)
	var suspicion: float = snapshot["suspicion"]
	_mirror_blue.visible = str(snapshot["suspicion_by"]) == PATROL and suspicion > 0.0
	if _mirror_blue.visible:
		PlaceholderFactory.set_alpha(_mirror_blue, suspicion / maxf(_suspicion_max, 1.0))


## Whoever rides (GDD 8.2): in the seat; leaning toward the door while they
## sleep; an arm out to the wheel they hold, across the gear lever they block,
## or with the tea they hold out; and a drummer's drum on the right of the
## dash, moving while it is played.
func _show_passenger(snapshot: Dictionary, moves: Dictionary) -> void:
	var riding: bool = str(snapshot["passenger"]) != ""
	_passenger.visible = riding
	var block: float = snapshot["view_block_right"]
	_drum.visible = riding and block > 0.0
	if _passenger_arm != null:
		_passenger_arm.visible = false
	if not riding:
		return
	_passenger.rotation = Vector3(0.0, 0.0, -_sleep_tilt if snapshot["passenger_asleep"] else 0.0)
	var time: float = snapshot["time"]
	if _drum.visible:
		var beat: float = sin(TAU * _drum_hz * time) if snapshot["passenger_drumming"] else 0.0
		_drum.position = _drum_at + Vector3(0.0, _drum_bob * beat, 0.0)
	# Where the arm goes, if it goes anywhere.
	var to: Vector3 = _arm_from
	var held: int = snapshot["wheel_held"]
	if held != PassengerSim.HOLD_NONE:
		to = _grip_point
	elif snapshot["lever_blocked"] and _anchor_pos.has(GEAR_LEVER_ANCHOR):
		to = _anchor_pos[GEAR_LEVER_ANCHOR]
	elif snapshot["tea_passed"]:
		for id: Variant in moves:
			# What he holds out stood in a cup holder: it is where his arm ends.
			if _held_out.has(str(id)):
				to = GameData.as_vec3(moves[id])
	var along: Vector3 = to - _arm_from
	if _passenger_arm == null or along.length() < 0.001:
		return
	_passenger_arm.visible = true
	_passenger_arm.transform = Transform3D(Basis.looking_at(along.normalized(), Vector3.UP), (_arm_from + to) * 0.5)
	_passenger_arm.scale = Vector3(1.0, 1.0, along.length())


## Each item is drawn at its slot (GDD 7.1), from its own placeholder
## "item_<id>" (or "item_default"). An empty one is hidden; so is one stowed
## in the glovebox, unless the glovebox is open: then it lies in its cell.
func _show_items(items: Array[Dictionary], moves: Dictionary, ringing: bool, time: float, glovebox_open: bool) -> void:
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
		var cell: int = _cells.find(str(item["slot"]))
		if cell >= 0:
			node.visible = node.visible and glovebox_open
			node.position = _cell_pos + Vector3((float(cell) * 2.0 - float(_cells.size() - 1)) * _cell_spread, _item_lift, 0.0)
		elif _anchor_pos.has(anchor):
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
