class_name RoadView
extends Node3D
## The road (GDD 13.5): the car stays at the origin and the world scrolls.
## Strips of road, shoulder, rumble strip and barrier are uniform along the
## road, so only what marks distance is recycled: lane dashes, guardrail
## pieces, roadside posts, the vehicles, and what a leg puts on the road
## (hazards, signs, a slip lane). Curves are drawn by the world-bend shader;
## the simulation road is always straight. Reads the snapshot; changes nothing.
##
## This node sits where road coordinates (x across, s along) have their
## origin relative to the car: a road point (x, s) is at local
## (x, 0, -(s - car_s)).

const VEHICLES_NODE: String = "Vehicles"
const NO_SLIP: Vector2 = Vector2(-1.0, -1.0)
## Lifts that keep flat things from fighting over the same height (m).
const LIFT_GROUND: float = -0.03
const LIFT_SLIP: float = 0.002
const LIFT_LINE: float = 0.004
const LIFT_DASH: float = 0.006
## Where a marker that is not drawn this frame is put.
const OUT_OF_SIGHT: float = -1000.0

var _factory: PlaceholderFactory
var _data: GameData

var _center_x: float = 0.0
var _center_z: float = 0.0
var _road_y: float = 0.0
var _ahead: float = 0.0
var _behind: float = 0.0
var _mesh_step: float = 1.0
var _ground_width: float = 0.0
var _line_width: float = 0.0
var _dash_period: float = 1.0
var _post_period: float = 1.0
var _post_offset: float = 0.0
var _rail_height: float = 0.0
var _rail_period: float = 1.0
var _barrier_height: float = 0.0
var _barrier_width: float = 0.0
var _bend_per_k: float = 0.0
var _bend_tau: float = 0.0
var _light_height: float = 0.0
var _blink_hz: float = 1.0
var _sign_inset: float = 0.0
var _sign_text_height: float = 0.0
var _vehicle_sign_lift: float = 0.0

var _lane_width: float = 0.0
var _rumble_width: float = 0.0
var _shoulder_width: float = 0.0
var _median_x: float = 0.0
var _left_rail_margin: float = 0.0

var _lanes: int = -1
var _divided: bool = true
var _strips: Node3D
var _dashes: MultiMeshInstance3D
var _posts: MultiMeshInstance3D
var _rails: MultiMeshInstance3D
var _dash_lines: PackedFloat64Array = PackedFloat64Array()
var _post_lines: PackedFloat64Array = PackedFloat64Array()
var _rail_lines: PackedFloat64Array = PackedFloat64Array()
var _rail_x: float = 0.0
var _vehicles: Node3D
## vehicle id -> VehicleView in use.
var _shown: Dictionary = {}
## type id -> Array of spare VehicleView.
var _spare: Dictionary = {}
var _type_records: Dictionary = {}
var _bend: float = 0.0
## The slip lane now drawn: from where to where along the leg.
var _slip: Vector2 = NO_SLIP
var _slip_node: Node3D
## hazard kind -> its record, and kind -> Array of Node3D (the first ones in use).
var _hazard_records: Dictionary = {}
var _hazard_pool: Dictionary = {}
var _hazards: Node3D
var _signs: Array[Node3D] = []
var _sign_nodes: Node3D
var _fork_sign_height: float = 0.0
## How far over the branches' texts the boss ahead is written.
var _boss_text_lift: float = 0.0
## Letter sizes (Label3D pixel sizes) of a roadside sign and of a fork's sign.
var _small_text: float = 0.01
var _large_text: float = 0.01
var _gore: Node3D
var _fork_bar: Node3D
var _stall: Node3D
var _stall_offset: Vector2 = Vector2.ZERO
var _set_piece: SetPieceView
var _gusts: GustView


func setup(data: GameData, factory: PlaceholderFactory) -> void:
	_data = data
	_factory = factory
	var tuning: Tuning = data.tuning
	_center_x = tuning.f("cabin_center_x")
	_center_z = tuning.f("cabin_center_z")
	_road_y = tuning.f("road_y")
	_ahead = tuning.f("road_draw_ahead")
	_behind = tuning.f("road_draw_behind")
	_mesh_step = tuning.f("road_mesh_step")
	_ground_width = tuning.f("ground_width")
	_line_width = tuning.f("line_width")
	_dash_period = tuning.f("dash_period")
	_post_period = tuning.f("post_period")
	_post_offset = tuning.f("post_offset")
	_rail_height = tuning.f("rail_height")
	_rail_period = tuning.f("rail_period")
	_barrier_height = tuning.f("barrier_height")
	_barrier_width = tuning.f("barrier_width")
	_bend_per_k = tuning.f("world_bend_per_k")
	_bend_tau = tuning.f("bend_smoothing")
	_light_height = tuning.f("vehicle_light_height")
	_blink_hz = tuning.f("signal_blink_hz")
	_sign_inset = tuning.f("sign_inset")
	_sign_text_height = tuning.f("sign_text_height")
	_vehicle_sign_lift = tuning.f("vehicle_sign_lift")
	_fork_sign_height = tuning.f("fork_sign_height")
	_boss_text_lift = tuning.f("fork_boss_text_lift")
	_small_text = factory.size_of("road_sign_text").x
	_large_text = factory.size_of("road_fork_text").x
	_stall_offset = Vector2(tuning.fi("stop_stall_offset", 0), tuning.fi("stop_stall_offset", 1))
	_lane_width = tuning.f("lane_width")
	_rumble_width = tuning.f("rumble_strip_width")
	_shoulder_width = tuning.f("shoulder_width")
	_median_x = tuning.f("median_barrier_x")
	_left_rail_margin = tuning.f("undivided_left_rail_margin")
	for record: Dictionary in data.records("vehicles"):
		_type_records[StringName(GameData.as_string(record.get("id")))] = record
	for record: Dictionary in data.records("hazard_kinds"):
		_hazard_records[StringName(GameData.as_string(record.get("id")))] = record

	_vehicles = get_node_or_null(VEHICLES_NODE) as Node3D
	if _vehicles == null:
		_vehicles = Node3D.new()
		_vehicles.name = VEHICLES_NODE
		add_child(_vehicles)
	_hazards = Node3D.new()
	_hazards.name = "Hazards"
	add_child(_hazards)
	_sign_nodes = Node3D.new()
	_sign_nodes.name = "Signs"
	add_child(_sign_nodes)
	# The gore of a fork, the bar its sign hangs from, and a stop's stall.
	_gore = factory.make_world("road_gore")
	_gore.visible = false
	add_child(_gore)
	_fork_bar = factory.make_world("road_fork_sign")
	_fork_bar.visible = false
	add_child(_fork_bar)
	_stall = factory.make_world("stop_stall")
	_stall.visible = false
	add_child(_stall)
	# What a set piece puts on the road, and the dust a gust sends ahead of it.
	_set_piece = SetPieceView.new()
	_set_piece.name = "SetPiece"
	add_child(_set_piece)
	_set_piece.setup(data, factory)
	_gusts = GustView.new()
	_gusts.name = "Gusts"
	add_child(_gusts)
	_gusts.setup(data, factory)


func apply(snapshot: Dictionary, delta: float) -> void:
	# Beside a slip lane the car's road is one lane wider; the road itself
	# is drawn as it is before and after, and the slip lane on top.
	var lanes: int = snapshot["lanes"]
	if snapshot["slip_open"]:
		lanes -= 1
	var divided: bool = snapshot["divided"]
	if lanes != _lanes or divided != _divided:
		_lanes = lanes
		_divided = divided
		_build_road()
		_slip = NO_SLIP
		_build_slip()
	var slip: Vector2 = snapshot["slip"]
	if slip != _slip:
		_slip = slip
		_build_slip()

	var car_x: float = snapshot["car_x"]
	var car_s: float = snapshot["car_s"]
	position = Vector3(_center_x - car_x, _road_y, _center_z)

	# A curve that pushes the car to the right is a bend to the left.
	var curve_k: float = snapshot["curve_k"]
	var want_bend: float = -curve_k * _bend_per_k
	var blend: float = 1.0
	if _bend_tau > 0.0:
		blend = 1.0 - exp(-delta / _bend_tau)
	_bend += (want_bend - _bend) * blend
	# The last thousandth of the way is taken in one step, so that a straight
	# road is drawn straight.
	if absf(want_bend - _bend) < _bend_per_k * 0.001:
		_bend = want_bend
	_factory.set_world_bend(_bend, _center_z)

	_place_markers(_dashes, _dash_lines, _dash_period, car_s, 0.0, LIFT_DASH, NO_SLIP)
	_place_markers(_posts, _post_lines, _post_period, car_s, 0.0, _factory.size_of("road_post").y * 0.5, NO_SLIP)
	_place_markers(_rails, _rail_lines, _rail_period, car_s, _rail_period * 0.5, _rail_height, _slip)
	_place_slip(car_s)

	var time: float = snapshot["time"]
	var vehicles: Array[Dictionary] = snapshot["vehicles"]
	var police_lights: bool = snapshot["police_lights"]
	_show_vehicles(vehicles, time, police_lights)
	var hazards: Array[Dictionary] = snapshot["hazards"]
	_show_hazards(hazards)
	var signs: Array[Dictionary] = snapshot["signs"]
	_show_signs(_sign_entries(signs))
	_set_piece.apply(snapshot, _lanes, delta)
	_gusts.apply(snapshot)

	# The gore: where the road parts (GDD 9.5).
	var gore_ahead: float = snapshot["gore_ahead"]
	_gore.visible = gore_ahead >= 0.0 and gore_ahead <= _ahead
	if _gore.visible:
		var gore_size: Vector3 = _factory.size_of("road_gore")
		_gore.position = Vector3(_lane_width * float(_lanes) * 0.5, gore_size.y * 0.5, -(gore_ahead + gore_size.z * 0.5))
	# At a stop: the stall beside the car.
	_stall.visible = snapshot["stopped"]
	if _stall.visible:
		_stall.position = Vector3(car_x + _stall_offset.x, _factory.size_of("stop_stall").y * 0.5, -_stall_offset.y)


# --- Building ----------------------------------------------------------------

func _build_road() -> void:
	if _strips != null:
		_strips.queue_free()
	_strips = Node3D.new()
	_strips.name = "Strips"
	add_child(_strips)

	var length: float = _ahead + _behind
	var middle: float = -(_ahead - _behind) * 0.5
	var road_right: float = _lane_width * float(_lanes)
	var strip_end: float = road_right + _rumble_width
	_rail_x = strip_end + _shoulder_width
	var left_x: float = _median_x if _divided else -_lane_width - _left_rail_margin
	# The left edge line: beside the median, or at the oncoming lane's edge.
	var left_line: float = 0.0 if _divided else -_lane_width

	_add_strip(_strips, "ground", -_ground_width * 0.5, _ground_width * 0.5, LIFT_GROUND, length, middle)
	_add_strip(_strips, "road_asphalt", left_x, road_right, 0.0, length, middle)
	_add_strip(_strips, "road_rumble", road_right, strip_end, 0.0, length, middle)
	_add_strip(_strips, "road_shoulder", strip_end, _rail_x, 0.0, length, middle)
	_add_strip(_strips, "road_line", road_right - _line_width, road_right, LIFT_LINE, length, middle)
	_add_strip(_strips, "road_line", left_line, left_line + _line_width, LIFT_LINE, length, middle)

	var rail_size: Vector3 = _factory.size_of("road_rail")
	_rail_lines = PackedFloat64Array([_rail_x + rail_size.x * 0.5])
	if _divided:
		_add_wall(_strips, "road_barrier", _median_x - _barrier_width * 0.5, _barrier_height * 0.5, _barrier_width, _barrier_height, length, middle)
	else:
		_rail_lines.append(left_x - rail_size.x * 0.5)

	# Lane lines: one dashed line on each boundary between two lanes, and the
	# centre line of an undivided road.
	_dash_lines = PackedFloat64Array()
	for lane: int in range(1, _lanes):
		_dash_lines.append(_lane_width * float(lane))
	if not _divided:
		_dash_lines.append(0.0)
	_post_lines = PackedFloat64Array([_rail_x + _post_offset, left_x - _post_offset - (_barrier_width if _divided else 0.0)])

	for old: MultiMeshInstance3D in [_dashes, _posts, _rails]:
		if old != null:
			old.queue_free()
	_dashes = _make_markers("road_dash", _factory.size_of("road_dash"), _dash_lines.size(), _dash_period)
	_posts = _make_markers("road_post", _factory.size_of("road_post"), _post_lines.size(), _post_period)
	_rails = _make_markers("road_rail", Vector3(rail_size.x, rail_size.y, _rail_period), _rail_lines.size(), _rail_period)


## The slip lane (an Exit, a side road): one more lane on the right from
## _slip.x to _slip.y, with its own edge line, rumble strip, shoulder and rail.
func _build_slip() -> void:
	if _slip_node != null:
		_slip_node.queue_free()
		_slip_node = null
	if _slip.x < 0.0 or _slip.y <= _slip.x:
		return
	_slip_node = Node3D.new()
	_slip_node.name = "Slip"
	add_child(_slip_node)
	var length: float = _slip.y - _slip.x
	var from: float = _lane_width * float(_lanes)
	var to: float = from + _lane_width
	var strip_end: float = to + _rumble_width
	var rail_x: float = strip_end + _shoulder_width
	var rail_size: Vector3 = _factory.size_of("road_rail")
	_add_strip(_slip_node, "road_asphalt", from, to, LIFT_SLIP, length, 0.0)
	_add_strip(_slip_node, "road_rumble", to, strip_end, LIFT_SLIP, length, 0.0)
	_add_strip(_slip_node, "road_shoulder", strip_end, rail_x, LIFT_SLIP, length, 0.0)
	_add_strip(_slip_node, "road_line", to - _line_width, to, LIFT_LINE, length, 0.0)
	_add_wall(_slip_node, "road_rail", rail_x + rail_size.x * 0.5, _rail_height, rail_size.x, rail_size.y, length, 0.0)


func _place_slip(car_s: float) -> void:
	if _slip_node == null:
		return
	_slip_node.position = Vector3(0.0, 0.0, -((_slip.x + _slip.y) * 0.5 - car_s))
	_slip_node.visible = _slip.y > car_s - _behind and _slip.x < car_s + _ahead


## A flat strip from x = from to x = to, `length` long, its middle at local z.
func _add_strip(parent: Node3D, id: String, from: float, to: float, lift: float, length: float, z: float) -> void:
	var mesh: PlaneMesh = PlaneMesh.new()
	mesh.size = Vector2(to - from, length)
	mesh.subdivide_depth = int(length / _mesh_step)
	var strip: MeshInstance3D = MeshInstance3D.new()
	strip.mesh = mesh
	strip.material_override = _factory.world_material_for(_factory.color_of(id))
	strip.position = Vector3((from + to) * 0.5, lift, z)
	strip.name = id
	parent.add_child(strip)


## An upright wall along the road (guardrail, barrier), `length` long.
func _add_wall(parent: Node3D, id: String, x: float, y: float, width: float, height: float, length: float, z: float) -> void:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = Vector3(width, height, length)
	mesh.subdivide_depth = int(length / _mesh_step)
	var wall: MeshInstance3D = MeshInstance3D.new()
	wall.mesh = mesh
	wall.material_override = _factory.world_material_for(_factory.color_of(id))
	wall.position = Vector3(x, y, z)
	wall.name = id
	parent.add_child(wall)


## Recycled markers (dashes, posts, rail pieces): `lines` rows of one box,
## every `period` metres.
func _make_markers(id: String, size: Vector3, lines: int, period: float) -> MultiMeshInstance3D:
	var per_line: int = int((_ahead + _behind) / period) + 2
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	var multi: MultiMesh = MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = maxi(lines, 0) * per_line
	var node: MultiMeshInstance3D = MultiMeshInstance3D.new()
	node.multimesh = multi
	node.material_override = _factory.world_material_for(_factory.color_of(id))
	node.name = id
	add_child(node)
	return node


## Puts each marker at its place along the road. The first line's markers
## whose middle lies within `gap` (a slip lane) are left out.
func _place_markers(node: MultiMeshInstance3D, lines: PackedFloat64Array, period: float,
		car_s: float, offset_s: float, lift: float, gap: Vector2) -> void:
	if node == null or lines.is_empty():
		return
	var multi: MultiMesh = node.multimesh
	var per_line: int = multi.instance_count / lines.size()
	var first_s: float = floorf((car_s - _behind) / period) * period + offset_s
	var index: int = 0
	for line: int in lines.size():
		var line_x: float = lines[line]
		for step: int in per_line:
			var s: float = first_s + float(step) * period
			var y: float = lift
			if line == 0 and gap.x >= 0.0 and s > gap.x - period * 0.5 and s < gap.y + period * 0.5:
				y = OUT_OF_SIGHT
			multi.set_instance_transform(index, Transform3D(Basis.IDENTITY, Vector3(line_x, y, -(s - car_s))))
			index += 1


# --- Vehicles ----------------------------------------------------------------

func _show_vehicles(vehicles: Array[Dictionary], time: float, police_lights: bool) -> void:
	# The last car of a motorcade carries its sign (GDD 9.3).
	var last_of_motorcade: int = -1
	var least_ahead: float = INF
	for vehicle: Dictionary in vehicles:
		var role: StringName = vehicle["role"]
		var ahead: float = vehicle["ahead"]
		if role == EncounterSim.MOTORCADE and ahead < least_ahead:
			least_ahead = ahead
			last_of_motorcade = vehicle["id"]

	var seen: Dictionary = {}
	for vehicle: Dictionary in vehicles:
		var id: int = vehicle["id"]
		var type_id: StringName = vehicle["type"]
		seen[id] = true
		var view: VehicleView = null
		if _shown.has(id):
			view = _shown[id]
			if view.type_id != type_id:
				# Another vehicle under an id seen before (a new leg).
				_put_back(view)
				view = null
		if view == null:
			view = _take_view(type_id)
			_shown[id] = view
		var x: float = vehicle["x"]
		var ahead: float = vehicle["ahead"]
		var role: StringName = vehicle["role"]
		var sign_text: String = ""
		if id == last_of_motorcade:
			sign_text = Lines.get_text("sign.motorcade.keep_back")
		view.apply(vehicle, Vector3(x, 0.0, -ahead), time, _blink_hz,
				police_lights and role == EncounterSim.POLICE, sign_text, _bend_shift(ahead))
	for id: Variant in _shown.keys():
		if not seen.has(id):
			var gone: VehicleView = _shown[id]
			_put_back(gone)
			_shown.erase(id)


func _put_back(view: VehicleView) -> void:
	view.visible = false
	view.reset()
	var spare: Array = _spare.get(view.type_id, [])
	spare.append(view)
	_spare[view.type_id] = spare


func _take_view(type_id: StringName) -> VehicleView:
	var spare: Array = _spare.get(type_id, [])
	if not spare.is_empty():
		var reused: VehicleView = spare.pop_back()
		reused.visible = true
		return reused
	var view: VehicleView = VehicleView.new()
	var record: Dictionary = _type_records.get(type_id, {})
	view.setup(record, _factory, _light_height, _vehicle_sign_lift)
	_vehicles.add_child(view)
	return view


## How far the bend of the road moves something `ahead` metres in front to
## the side: what the world shader does to a mesh and a text needs done by hand.
func _bend_shift(ahead: float) -> float:
	var bent: float = maxf(ahead, 0.0)
	return _bend * bent * bent


# --- Hazards and signs -------------------------------------------------------

## Cones, potholes, sheep and melons, where the snapshot says they are. One
## that was hit lies on its side.
func _show_hazards(hazards: Array[Dictionary]) -> void:
	var used: Dictionary = {}
	for hazard: Dictionary in hazards:
		var kind: StringName = hazard["kind"]
		if not _hazard_records.has(kind):
			continue
		var pool: Array = _hazard_pool.get(kind, [])
		var index: int = used.get(kind, 0)
		used[kind] = index + 1
		var placeholder: String = GameData.as_string(GameData.as_dict(_hazard_records[kind]).get("placeholder"))
		var node: Node3D = null
		if index < pool.size():
			node = pool[index]
		else:
			node = _factory.make_world(placeholder)
			_hazards.add_child(node)
			pool.append(node)
			_hazard_pool[kind] = pool
		var size: Vector3 = _factory.size_of(placeholder)
		var height: float = size.y if size.z > 0.0 else size.x * 2.0
		var x: float = hazard["x"]
		var ahead: float = hazard["ahead"]
		var fallen: bool = hazard["hit"] and height > size.x
		node.visible = true
		node.rotation.z = PI * 0.5 if fallen else 0.0
		node.position = Vector3(x, (size.x if fallen else height) * 0.5, -ahead)
	for kind: Variant in _hazard_pool:
		var pool: Array = _hazard_pool[kind]
		for index: int in range(GameData.as_int(used.get(kind, 0)), pool.size()):
			var spare: Node3D = pool[index]
			spare.visible = false


## What the snapshot's signs are to draw: where each text hangs and what it
## says. A fork's sign is two texts over the road, one for each branch.
func _sign_entries(signs: Array[Dictionary]) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var road_right: float = _lane_width * float(_lanes)
	var fork_shown: bool = false
	for road_sign: Dictionary in signs:
		var ahead: float = road_sign["ahead"]
		match GameData.as_string(road_sign.get("kind")):
			"curve":
				# A curve that pushes the car to the right is a bend to the left.
				entries.append({"ahead": ahead, "x": _rail_x - _sign_inset, "height": _sign_text_height, "post": true,
						"text": Lines.get_text("sign.curve.left" if GameData.as_float(road_sign.get("k")) > 0.0 else "sign.curve.right")})
			"side_road":
				entries.append({"ahead": ahead, "x": _rail_x - _sign_inset, "height": _sign_text_height, "post": true,
						"text": Lines.get_text("sign.side_road")})
			"exit":
				entries.append({"ahead": ahead, "x": _rail_x - _sign_inset, "height": _sign_text_height, "post": true,
						"text": Lines.format("sign.exit", [Lines.get_text("stop.%s.name" % GameData.as_string(road_sign.get("stop")))])})
			"fork":
				fork_shown = true
				_fork_bar.position = Vector3(road_right * 0.5, _fork_sign_height + 0.6, -ahead)
				entries.append({"ahead": ahead, "x": road_right * 0.22, "height": _fork_sign_height, "post": false, "large": true,
						"text": _branch_text(GameData.as_dict(road_sign.get("left")))})
				entries.append({"ahead": ahead, "x": road_right * 0.78, "height": _fork_sign_height, "post": false, "large": true,
						"text": _branch_text(GameData.as_dict(road_sign.get("right")))})
				# After tea: the boss ahead and what it has in store (GDD 9.6),
				# over the two branches.
				var boss: String = GameData.as_string(road_sign.get("boss"))
				if not boss.is_empty():
					entries.append({"ahead": ahead, "x": road_right * 0.5, "height": _fork_sign_height + _boss_text_lift, "post": false, "large": true,
							"text": _boss_text(boss, GameData.as_string(road_sign.get("boss_modifier")))})
			"checkpoint":
				# A limit to take the barriers at, or none: this one is to stop at.
				var limit: float = GameData.as_float(road_sign.get("limit"))
				entries.append({"ahead": ahead, "x": _rail_x - _sign_inset, "height": _sign_text_height, "post": true,
						"text": Lines.format("sign.checkpoint", ["%d" % roundi(limit) if limit > 0.0 else Lines.get_text("sign.checkpoint.stop")])})
	_fork_bar.visible = fork_shown
	return entries


## "[RUSH / WEDDING / FUEL / 90]": a branch's leg, its modifier if it has
## one, the stop at its end, and its par (GDD 9.5, 16.1).
func _branch_text(branch: Dictionary) -> String:
	var parts: PackedStringArray = [Lines.get_text("leg.%s.name" % GameData.as_string(branch.get("leg")))]
	var modifier: String = GameData.as_string(branch.get("modifier"))
	if not modifier.is_empty():
		parts.append(Lines.get_text("modifier.%s.name" % modifier))
	var stop: String = GameData.as_string(branch.get("stop"))
	if not stop.is_empty():
		parts.append(Lines.get_text("stop.%s.name" % stop))
	parts.append("%d" % roundi(GameData.as_float(branch.get("par_s"))))
	# One thing to a line, so that the letters can be large enough to read
	# from the lead the sign is given.
	return Lines.format("sign.fork", [" /\n".join(parts)])


## "[CHECKPOINT / LONG QUEUE]": the boss ahead, and its modifier if it has one.
func _boss_text(boss: String, modifier: String) -> String:
	var boss_name: String = Lines.get_text("boss.%s.name" % boss)
	if modifier.is_empty():
		return Lines.format("sign.fork", [boss_name])
	return Lines.format("sign.boss", [boss_name, Lines.get_text("sign.boss_modifier.%s" % modifier)])


## Road signs (GDD 16.1): a text in square brackets, on a post inside the
## guardrail or hung over the road.
func _show_signs(signs: Array[Dictionary]) -> void:
	var post_height: float = _factory.size_of("road_sign").y
	for index: int in signs.size():
		var road_sign: Dictionary = signs[index]
		if index >= _signs.size():
			var made: Node3D = Node3D.new()
			var post: Node3D = _factory.make_world("road_sign")
			post.name = "Post"
			post.position = Vector3(0.0, post_height * 0.5, 0.0)
			made.add_child(post)
			var text: Node3D = _factory.make("road_sign_text")
			text.name = "Text"
			made.add_child(text)
			_sign_nodes.add_child(made)
			_signs.append(made)
		var node: Node3D = _signs[index]
		var ahead: float = road_sign["ahead"]
		var x: float = road_sign["x"]
		var height: float = road_sign["height"]
		node.visible = true
		node.position = Vector3(x, 0.0, -ahead)
		var post_node: Node3D = node.get_node_or_null("Post") as Node3D
		if post_node != null:
			post_node.visible = road_sign["post"]
		var label: Label3D = node.get_node_or_null("Text") as Label3D
		if label != null:
			label.text = GameData.as_string(road_sign.get("text"))
			label.position = Vector3(_bend_shift(ahead), height, 0.0)
			label.pixel_size = _large_text if GameData.as_bool(road_sign.get("large")) else _small_text
	for index: int in range(signs.size(), _signs.size()):
		_signs[index].visible = false
