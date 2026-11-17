class_name RoadView
extends Node3D
## The road (GDD 13.5): the car stays at the origin and the world scrolls.
## Strips of road, shoulder, rumble strip, rails and barrier are uniform along
## the road, so only what marks distance is recycled: lane dashes, roadside
## posts and the vehicles. Curves are drawn by the world-bend shader; the
## simulation road is always straight. Reads the snapshot; changes nothing.
##
## This node sits where road coordinates (x across, s along) have their
## origin relative to the car: a road point (x, s) is at local
## (x, 0, -(s - car_s)).

const VEHICLES_NODE: String = "Vehicles"

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
var _dash_length: float = 0.0
var _dash_period: float = 1.0
var _post_period: float = 1.0
var _post_offset: float = 0.0
var _rail_height: float = 0.0
var _barrier_height: float = 0.0
var _barrier_width: float = 0.0
var _bend_per_k: float = 0.0
var _bend_tau: float = 0.0
var _light_height: float = 0.0
var _blink_hz: float = 1.0

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
var _dash_lines: PackedFloat64Array = PackedFloat64Array()
var _post_lines: PackedFloat64Array = PackedFloat64Array()
var _vehicles: Node3D
## vehicle id -> VehicleView in use.
var _shown: Dictionary = {}
## type id -> Array of spare VehicleView.
var _spare: Dictionary = {}
var _type_records: Dictionary = {}
var _bend: float = 0.0


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
	_dash_length = tuning.f("dash_length")
	_dash_period = tuning.f("dash_period")
	_post_period = tuning.f("post_period")
	_post_offset = tuning.f("post_offset")
	_rail_height = tuning.f("rail_height")
	_barrier_height = tuning.f("barrier_height")
	_barrier_width = tuning.f("barrier_width")
	_bend_per_k = tuning.f("world_bend_per_k")
	_bend_tau = tuning.f("bend_smoothing")
	_light_height = tuning.f("vehicle_light_height")
	_blink_hz = tuning.f("signal_blink_hz")
	_lane_width = tuning.f("lane_width")
	_rumble_width = tuning.f("rumble_strip_width")
	_shoulder_width = tuning.f("shoulder_width")
	_median_x = tuning.f("median_barrier_x")
	_left_rail_margin = tuning.f("undivided_left_rail_margin")
	for record: Dictionary in data.records("vehicles"):
		_type_records[StringName(GameData.as_string(record.get("id")))] = record

	_vehicles = get_node_or_null(VEHICLES_NODE) as Node3D
	if _vehicles == null:
		_vehicles = Node3D.new()
		_vehicles.name = VEHICLES_NODE
		add_child(_vehicles)


func apply(snapshot: Dictionary, delta: float) -> void:
	var lanes: int = snapshot["lanes"]
	var divided: bool = snapshot["divided"]
	if lanes != _lanes or divided != _divided:
		_lanes = lanes
		_divided = divided
		_build_road()

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
	_factory.set_world_bend(_bend, _center_z)

	_place_markers(_dashes, _dash_lines, _dash_period, car_s, 0.0, 0.006)
	_place_markers(_posts, _post_lines, _post_period, car_s, 0.0, _factory.size_of("road_post").y * 0.5)

	var time: float = snapshot["time"]
	var blink_on: bool = fmod(time * _blink_hz, 1.0) < 0.5
	var vehicles: Array[Dictionary] = snapshot["vehicles"]
	_show_vehicles(vehicles, blink_on)


# --- Building ----------------------------------------------------------------

func _build_road() -> void:
	if _strips != null:
		_strips.queue_free()
	_strips = Node3D.new()
	_strips.name = "Strips"
	add_child(_strips)

	var road_right: float = _lane_width * float(_lanes)
	var strip_end: float = road_right + _rumble_width
	var rail_x: float = strip_end + _shoulder_width
	var left_x: float = _median_x if _divided else -_lane_width - _left_rail_margin

	_add_strip("ground", -_ground_width * 0.5, _ground_width * 0.5, -0.03)
	_add_strip("road_asphalt", left_x, road_right, 0.0)
	_add_strip("road_rumble", road_right, strip_end, 0.0)
	_add_strip("road_shoulder", strip_end, rail_x, 0.0)
	_add_strip("road_line", road_right - _line_width, road_right, 0.004)
	_add_strip("road_line", 0.0 if _divided else left_x + _line_width, (0.0 if _divided else left_x + _line_width) + _line_width, 0.004)

	var rail_size: Vector3 = _factory.size_of("road_rail")
	_add_wall("road_rail", rail_x + rail_size.x * 0.5, _rail_height, rail_size.x, rail_size.y)
	if _divided:
		_add_wall("road_barrier", _median_x - _barrier_width * 0.5, _barrier_height * 0.5, _barrier_width, _barrier_height)
	else:
		_add_wall("road_rail", left_x - rail_size.x * 0.5, _rail_height, rail_size.x, rail_size.y)

	# Lane lines: one dashed line between each pair of lanes, and the centre
	# line of an undivided road.
	_dash_lines = PackedFloat64Array()
	for lane: int in range(1, _lanes):
		_dash_lines.append(_lane_width * float(lane) - _line_width * 0.5)
	if not _divided:
		_dash_lines.append(-_line_width * 0.5)
	_post_lines = PackedFloat64Array([rail_x + _post_offset, left_x - _post_offset - (_barrier_width if _divided else 0.0)])

	if _dashes != null:
		_dashes.queue_free()
	if _posts != null:
		_posts.queue_free()
	_dashes = _make_markers("road_dash", _dash_lines.size(), _dash_period)
	_posts = _make_markers("road_post", _post_lines.size(), _post_period)


## A flat strip of road from x = from to x = to, the whole drawn length.
func _add_strip(id: String, from: float, to: float, lift: float) -> void:
	var length: float = _ahead + _behind
	var mesh: PlaneMesh = PlaneMesh.new()
	mesh.size = Vector2(to - from, length)
	mesh.subdivide_depth = int(length / _mesh_step)
	var strip: MeshInstance3D = MeshInstance3D.new()
	strip.mesh = mesh
	strip.material_override = _factory.world_material_for(_factory.color_of(id))
	strip.position = Vector3((from + to) * 0.5, lift, -(_ahead - _behind) * 0.5)
	strip.name = id
	_strips.add_child(strip)


## An upright wall along the road (guardrail, barrier), the whole drawn length.
func _add_wall(id: String, x: float, y: float, width: float, height: float) -> void:
	var length: float = _ahead + _behind
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = Vector3(width, height, length)
	mesh.subdivide_depth = int(length / _mesh_step)
	var wall: MeshInstance3D = MeshInstance3D.new()
	wall.mesh = mesh
	wall.material_override = _factory.world_material_for(_factory.color_of(id))
	wall.position = Vector3(x, y, -(_ahead - _behind) * 0.5)
	wall.name = id
	_strips.add_child(wall)


## Recycled markers (dashes, posts): `lines` rows of one mesh, every `period` metres.
func _make_markers(id: String, lines: int, period: float) -> MultiMeshInstance3D:
	var per_line: int = int((_ahead + _behind) / period) + 2
	var size: Vector3 = _factory.size_of(id)
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


func _place_markers(node: MultiMeshInstance3D, lines: PackedFloat64Array, period: float,
		car_s: float, offset_s: float, lift: float) -> void:
	if node == null or lines.is_empty():
		return
	var multi: MultiMesh = node.multimesh
	var per_line: int = multi.instance_count / lines.size()
	var first_s: float = floorf((car_s - _behind) / period) * period + offset_s
	var index: int = 0
	for line_x: float in lines:
		for step: int in per_line:
			var s: float = first_s + float(step) * period
			multi.set_instance_transform(index, Transform3D(Basis.IDENTITY, Vector3(line_x, lift, -(s - car_s))))
			index += 1


# --- Vehicles ----------------------------------------------------------------

func _show_vehicles(vehicles: Array[Dictionary], blink_on: bool) -> void:
	var seen: Dictionary = {}
	for vehicle: Dictionary in vehicles:
		var id: int = vehicle["id"]
		seen[id] = true
		var view: VehicleView = null
		if _shown.has(id):
			view = _shown[id]
		else:
			var type_id: StringName = vehicle["type"]
			view = _take_view(type_id)
			_shown[id] = view
		var x: float = vehicle["x"]
		var ahead: float = vehicle["ahead"]
		view.apply(vehicle, Vector3(x, 0.0, -ahead), blink_on)
	for id: Variant in _shown.keys():
		if not seen.has(id):
			var gone: VehicleView = _shown[id]
			gone.visible = false
			var spare: Array = _spare.get(gone.type_id, [])
			spare.append(gone)
			_spare[gone.type_id] = spare
			_shown.erase(id)


func _take_view(type_id: StringName) -> VehicleView:
	var spare: Array = _spare.get(type_id, [])
	if not spare.is_empty():
		var reused: VehicleView = spare.pop_back()
		reused.visible = true
		return reused
	var view: VehicleView = VehicleView.new()
	var record: Dictionary = _type_records.get(type_id, {})
	view.setup(record, _factory, _light_height)
	_vehicles.add_child(view)
	return view
