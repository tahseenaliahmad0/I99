class_name SetPieceView
extends Node3D
## What a set piece puts on the road (GDD 10.2 to 10.5, 16.1): the concrete
## barriers of a checkpoint and the bar across each of its lanes, the soldier
## and the sign he holds up, and the marked bay at the end of the last street.
## A child of RoadView: a road point (x, s) is at local (x, 0, -(s - car_s)).
## Reads the snapshot; changes nothing.

const NO_CORRIDOR: Vector3 = Vector3.ZERO
const NO_BAY: Vector2 = Vector2.ZERO
## Lifts that keep the bay's paint and its lines clear of the road's own.
const LIFT_PAINT: float = 0.003
const LIFT_LINE: float = 0.005

var _factory: PlaceholderFactory
var _lane_width: float = 0.0
var _line_width: float = 0.0
var _mesh_step: float = 1.0
var _ahead: float = 0.0
var _behind: float = 0.0
var _center_x: float = 0.0
var _center_z: float = 0.0
var _bar_height: float = 0.0
var _bar_raised: float = 0.0
var _bar_speed: float = 0.0
var _post_ahead: float = 0.0
var _stand: Vector2 = Vector2.ZERO
var _sign_offset: Vector2 = Vector2.ZERO
var _text_height: float = 0.0
var _stow_s: float = 0.0
var _clear: float = 0.0
## vehicle type id -> half its length (m).
var _half_length: Dictionary = {}

var _lanes: int = 0
var _corridor: Vector3 = NO_CORRIDOR
var _gap: float = 0.0
var _barriers: Node3D
var _bars: Node3D
var _bar_pivots: Array[Node3D] = []
var _bar_gap: float = 0.0
var _soldier: Node3D
var _sign: Label3D
## Where the soldier stood for the papers, as a road point (x, s).
var _stood: Vector2 = Vector2.ZERO
var _bay: Vector2 = NO_BAY
var _bay_node: Node3D


func setup(data: GameData, factory: PlaceholderFactory) -> void:
	_factory = factory
	var tuning: Tuning = data.tuning
	_lane_width = tuning.f("lane_width")
	_line_width = tuning.f("line_width")
	_mesh_step = tuning.f("road_mesh_step")
	_ahead = tuning.f("road_draw_ahead")
	_behind = tuning.f("road_draw_behind")
	_center_x = tuning.f("cabin_center_x")
	_center_z = tuning.f("cabin_center_z")
	_bar_height = tuning.f("checkpoint_bar_height")
	_bar_raised = deg_to_rad(tuning.f("checkpoint_bar_raised"))
	_bar_speed = deg_to_rad(tuning.f("checkpoint_bar_speed"))
	_post_ahead = tuning.f("soldier_post_ahead")
	_stand = Vector2(tuning.fi("soldier_stand", 0), tuning.fi("soldier_stand", 1))
	_sign_offset = Vector2(tuning.fi("soldier_sign_offset", 0), tuning.fi("soldier_sign_offset", 1))
	_text_height = tuning.f("street_text_height")
	var checkpoint: Dictionary = GameData.as_dict(data.record("bosses", BossSim.CHECKPOINT).get("checkpoint"))
	_stow_s = GameData.as_float(checkpoint.get("stow_s"))
	_clear = GameData.as_float(GameData.as_dict(checkpoint.get("queue")).get("clear_m"))
	for record: Dictionary in data.records("vehicles"):
		var placeholder: String = GameData.as_string(record.get("placeholder"))
		if factory.has(placeholder):
			_half_length[StringName(GameData.as_string(record.get("id")))] = factory.size_of(placeholder).z * 0.5

	_soldier = factory.make_world("road_soldier")
	_soldier.visible = false
	add_child(_soldier)
	_sign = factory.make("road_soldier_sign") as Label3D
	if _sign != null:
		# He holds it up to the driver, whichever way the driver looks at it.
		_sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_sign.visible = false
		add_child(_sign)


## `lanes` is how many lanes the road is drawn with.
func apply(snapshot: Dictionary, lanes: int, delta: float) -> void:
	var car_s: float = snapshot["car_s"]
	var car_x: float = snapshot["car_x"]
	var corridor: Vector3 = snapshot["corridor"]
	var gap: float = snapshot["corridor_gap"]
	if corridor != _corridor or gap != _gap or lanes != _lanes:
		_corridor = corridor
		_gap = gap
		_lanes = lanes
		_build_barriers()
	if _barriers != null:
		_barriers.position = Vector3(0.0, 0.0, -(_corridor.x - car_s))
		_barriers.visible = _corridor.z > car_s - _behind and _corridor.x < car_s + _ahead
	_show_bars(snapshot, car_s, car_x, delta)
	_show_soldier(snapshot, car_s, car_x)
	var bay: Vector2 = snapshot["bay"]
	if bay != _bay:
		_bay = bay
		_build_bay()
	if _bay_node != null:
		_bay_node.position = Vector3(0.0, 0.0, -(_bay.x - car_s))
		_bay_node.visible = _bay.x < car_s + _ahead


func _lane_of(x: float) -> int:
	return clampi(int(floorf(x / _lane_width)), 0, maxi(_lanes - 1, 0))


# --- Barriers ----------------------------------------------------------------

## A checkpoint's barriers (GDD 10.2, 10.4): every lane has a corridor of its
## own. From _corridor.x the barriers close in from the lane's own lines, at
## _corridor.y they are _gap apart, and so they stay to _corridor.z. Built
## with its start at this node's z = 0.
func _build_barriers() -> void:
	if _barriers != null:
		_barriers.queue_free()
		_barriers = null
	if _corridor.z <= _corridor.x or _lanes <= 0 or _gap <= 0.0:
		return
	_barriers = Node3D.new()
	_barriers.name = "Barriers"
	add_child(_barriers)
	var size: Vector3 = _factory.size_of("road_checkpoint_barrier")
	var taper: float = _corridor.y - _corridor.x
	var straight: float = _corridor.z - _corridor.y
	# Between two corridors, and outside the first and the last, the concrete
	# is one block: as wide as what the corridors leave of a lane.
	var block: float = _lane_width - _gap
	# Every barrier has a lighter cap, so that its top edge can be told from
	# its face in flat colours.
	var cap: float = _factory.size_of("road_checkpoint_cap").y
	if straight > 0.0 and block > 0.0:
		for line: int in _lanes + 1:
			var middle_z: float = -(taper + straight * 0.5)
			_add_box(_barriers, "road_checkpoint_barrier", Vector3(block, size.y, straight),
					Vector3(_lane_width * float(line), size.y * 0.5, middle_z), 0.0)
			_add_box(_barriers, "road_checkpoint_cap", Vector3(block, cap, straight),
					Vector3(_lane_width * float(line), size.y + cap * 0.5, middle_z), 0.0)
	if taper <= 0.0:
		return
	for lane: int in _lanes:
		var middle: float = _lane_width * (float(lane) + 0.5)
		for side: float in [-1.0, 1.0]:
			var from_x: float = middle + side * _lane_width * 0.5
			var to_x: float = middle + side * _gap * 0.5
			# The face toward the lane runs from the lane's line to the
			# corridor's mouth; the wall itself lies outside that face.
			var length: float = Vector2(to_x - from_x, taper).length()
			var at: Vector3 = Vector3((from_x + to_x) * 0.5 + side * size.x * 0.5, size.y * 0.5, -taper * 0.5)
			var turn: float = atan2(from_x - to_x, taper)
			_add_box(_barriers, "road_checkpoint_barrier", Vector3(size.x, size.y, length), at, turn)
			_add_box(_barriers, "road_checkpoint_cap", Vector3(size.x, cap, length), Vector3(at.x, size.y + cap * 0.5, at.z), turn)


## A box of the placeholder's colour that bends with the road: `size` with
## its middle at `at`, turned by `turn` about the upright.
func _add_box(parent: Node3D, id: String, size: Vector3, at: Vector3, turn: float) -> MeshInstance3D:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	mesh.subdivide_depth = int(size.z / _mesh_step)
	var box: MeshInstance3D = MeshInstance3D.new()
	box.mesh = mesh
	box.material_override = _factory.world_material_for(_factory.color_of(id))
	box.position = at
	box.rotation.y = turn
	box.name = id
	parent.add_child(box)
	return box


## A flat strip of the placeholder's colour from x = from to x = to, `length`
## long, its middle at local z.
func _add_flat(parent: Node3D, id: String, from: float, to: float, lift: float, length: float, z: float) -> void:
	var mesh: PlaneMesh = PlaneMesh.new()
	mesh.size = Vector2(to - from, length)
	mesh.subdivide_depth = int(length / _mesh_step)
	var strip: MeshInstance3D = MeshInstance3D.new()
	strip.mesh = mesh
	strip.material_override = _factory.world_material_for(_factory.color_of(id))
	strip.position = Vector3((from + to) * 0.5, lift, z)
	strip.name = id
	parent.add_child(strip)


# --- The bar and the soldier -------------------------------------------------

## The Checkpoint's bars (GDD 10.2): one across each lane's corridor, hinged
## on its left. A lane's bar is up while a vehicle that was waved on drives
## under it, and his own once he is let through.
func _show_bars(snapshot: Dictionary, car_s: float, car_x: float, delta: float) -> void:
	var bar_at: float = snapshot["bar_at"]
	if bar_at <= 0.0 or _lanes <= 0 or _gap <= 0.0:
		if _bars != null:
			_bars.visible = false
		return
	if _bars == null or _bar_pivots.size() != _lanes or _bar_gap != _gap:
		_build_bars()
	var to_bar: float = bar_at - car_s
	_bars.visible = to_bar > -_behind and to_bar < _ahead
	_bars.position = Vector3(0.0, _bar_height, -to_bar)
	var up: Array[bool] = []
	up.resize(_lanes)
	up.fill(false)
	if snapshot["bar_up"]:
		up[_lane_of(car_x)] = true
	var vehicles: Array[Dictionary] = snapshot["vehicles"]
	for vehicle: Dictionary in vehicles:
		var role: StringName = vehicle["role"]
		if role != BossSim.WAVED_ON_ROLE:
			continue
		var type_id: StringName = vehicle["type"]
		var half: float = GameData.as_float(_half_length.get(type_id))
		var ahead: float = vehicle["ahead"]
		if ahead + half > to_bar - _clear and ahead - half < to_bar + _clear:
			var x: float = vehicle["x"]
			up[_lane_of(x)] = true
	for lane: int in _lanes:
		var pivot: Node3D = _bar_pivots[lane]
		pivot.rotation.z = move_toward(pivot.rotation.z, _bar_raised if up[lane] else 0.0, _bar_speed * delta)


func _build_bars() -> void:
	if _bars != null:
		_bars.queue_free()
	_bars = Node3D.new()
	_bars.name = "Bars"
	add_child(_bars)
	_bar_pivots = []
	_bar_gap = _gap
	var size: Vector3 = _factory.size_of("road_checkpoint_bar")
	for lane: int in _lanes:
		var pivot: Node3D = Node3D.new()
		pivot.position = Vector3(_lane_width * (float(lane) + 0.5) - _gap * 0.5, 0.0, 0.0)
		_bars.add_child(pivot)
		_add_box(pivot, "road_checkpoint_bar", Vector3(_gap, size.y, size.z), Vector3(_gap * 0.5, 0.0, 0.0), 0.0)
		_bar_pivots.append(pivot)


## The soldier (GDD 10.2, 16.1): he waits beyond the bar on the driver's side
## of the lane; during the Stow he walks to the driver's window, and there he
## holds up the sign of the document he wants. At Dawn's last checkpoint he
## stands by the barriers and waves the cars through.
func _show_soldier(snapshot: Dictionary, car_s: float, car_x: float) -> void:
	var phase: int = snapshot["checkpoint_phase"]
	var bar_at: float = snapshot["bar_at"]
	var height: float = _factory.size_of("road_soldier").y
	var lane: int = _lane_of(car_x)
	if _sign != null:
		_sign.visible = false
	if phase <= 0 or bar_at <= 0.0 or _lanes <= 0:
		# No Checkpoint. Where there are barriers all the same (Dawn), he
		# stands at their mouth, between two lanes.
		_soldier.visible = _barriers != null and _barriers.visible
		if _soldier.visible:
			_soldier.position = Vector3(_lane_width * float(_lanes / 2), height * 0.5, -(_corridor.y - car_s))
		return
	var post: Vector3 = Vector3(_lane_width * float(lane), height * 0.5, -(bar_at - car_s) - _post_ahead)
	var at: Vector3 = post
	if phase == BossSim.STOW or phase == BossSim.PAPERS:
		# The car stands: where he stands beside it is a place on the road.
		_stood = Vector2(car_x + _stand.x - _center_x, car_s - (_stand.y - _center_z))
	if phase == BossSim.STOW:
		var stow_left: float = snapshot["stow_left"]
		at = post.lerp(_beside(car_s, height), clampf(1.0 - stow_left / maxf(_stow_s, 0.001), 0.0, 1.0))
	elif phase >= BossSim.PAPERS:
		at = _beside(car_s, height)
	_soldier.visible = true
	_soldier.position = at
	var wanted: String = str(snapshot["wanted"])
	if _sign != null and phase == BossSim.PAPERS and not wanted.is_empty():
		_sign.visible = true
		_sign.text = Lines.get_text("sign.document.%s" % wanted)
		_sign.position = Vector3(at.x + _sign_offset.x, _sign_offset.y, at.z)


## Where he stood for the papers, seen from where the car is now.
func _beside(car_s: float, height: float) -> Vector3:
	return Vector3(_stood.x, height * 0.5, -(_stood.y - car_s))


# --- The bay -----------------------------------------------------------------

## The end of the last street (GDD 10.5): the bay marked on the lane from
## _bay.x to _bay.y, and what the street ends at. Built with the bay's start
## at this node's z = 0.
func _build_bay() -> void:
	if _bay_node != null:
		_bay_node.queue_free()
		_bay_node = null
	if _bay.y <= _bay.x:
		return
	_bay_node = Node3D.new()
	_bay_node.name = "Bay"
	add_child(_bay_node)
	var length: float = _bay.y - _bay.x
	_add_flat(_bay_node, "road_bay", 0.0, _lane_width, LIFT_PAINT, length, -length * 0.5)
	_add_flat(_bay_node, "road_line", 0.0, _line_width, LIFT_LINE, length, -length * 0.5)
	_add_flat(_bay_node, "road_line", _lane_width - _line_width, _lane_width, LIFT_LINE, length, -length * 0.5)
	_add_flat(_bay_node, "road_line", 0.0, _lane_width, LIFT_LINE, _line_width, -_line_width * 0.5)
	_add_flat(_bay_node, "road_line", 0.0, _lane_width, LIFT_LINE, _line_width, -(length - _line_width * 0.5))
	var end: Vector3 = _factory.size_of("road_street_end")
	var house: Node3D = _factory.make_world("road_street_end")
	house.position = Vector3(_lane_width * 0.5, end.y * 0.5, -(length + end.z * 0.5))
	_bay_node.add_child(house)
	var text: Label3D = _factory.make("road_street_text") as Label3D
	if text != null:
		text.text = Lines.get_text("sign.arrival")
		# Just clear of the wall it is written on.
		text.position = Vector3(_lane_width * 0.5, _text_height, -(length - LIFT_LINE))
		_bay_node.add_child(text)
