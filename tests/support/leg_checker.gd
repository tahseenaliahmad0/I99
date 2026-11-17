class_name LegChecker
extends RefCounted
## Checks a generated leg against GDD 9.2 with arithmetic of its own: it
## shares no code with LegGenerator, only the plan's format.
##
##   check(plan)  every rule, worked out from the plan's numbers in the frame
##                of a player who holds third gear's speed
##   drive(plan)  the same leg run by the real LegSim, TrafficSim and
##                Collision, with a ghost car that follows the plan's line
##
## Both return a list of problems; an empty list means the leg is good.

const KMH_TO_MS: float = 1.0 / 3.6
const EVENT_TYPES: PackedStringArray = ["HAZARD", "CLUSTER", "SLOWPOKE"]
const SHOULDER_LANE: int = 99
const ONCOMING_LANE: int = -1
const MAX_PROBLEMS: int = 12

var problems: PackedStringArray = []

var _data: GameData
var _tuning: Tuning
var _par: float = 0.0
var _par_ms: float = 0.0
var _car_half_length: float = 0.0
var _car_half_width: float = 0.0
var _lane_width: float = 0.0
var _change_length: float = 0.0
var _close_gap: float = 0.0
var _signal_time: float = 0.0
var _late_signal_time: float = 0.0
var _change_time: float = 0.0
var _despawn_behind: float = 0.0

# --- The road being checked (the leg, or the motorcade's side road) ----------
var _lanes: int = 3
var _divided: bool = true
var _length: float = 0.0
var _spawns: Array = []
var _hazards: Array = []
var _zones: Array = []
var _flock: Dictionary = {}
var _path_s: PackedFloat64Array = PackedFloat64Array()
var _path_lane: PackedInt32Array = PackedInt32Array()
## The plan's vehicles as columns, so the checks do not look each number up again.
var _v_name: PackedStringArray = PackedStringArray()
var _v_trigger: PackedFloat64Array = PackedFloat64Array()
var _v_ahead: PackedFloat64Array = PackedFloat64Array()
var _v_closing: PackedFloat64Array = PackedFloat64Array()
var _v_half_length: PackedFloat64Array = PackedFloat64Array()
var _v_half_width: PackedFloat64Array = PackedFloat64Array()
var _v_lane: PackedInt32Array = PackedInt32Array()
var _v_direction: PackedInt32Array = PackedInt32Array()
var _v_from_x: PackedFloat64Array = PackedFloat64Array()
var _v_to_x: PackedFloat64Array = PackedFloat64Array()
## When each starts to move over and when it has arrived (INF: it keeps its lane).
var _v_move_from: PackedFloat64Array = PackedFloat64Array()
var _v_move_to: PackedFloat64Array = PackedFloat64Array()
## Chicanes as columns: start, end of the first straight, start of the last, end, and the two lane centres.
var _z: Array[PackedFloat64Array] = []
## Where the line starts or stops moving sideways.
var _line_moments: PackedFloat64Array = PackedFloat64Array()


func _init(data: GameData) -> void:
	_data = data
	_tuning = data.tuning
	_par = _tuning.fi("gear_speeds", 2)
	_par_ms = _par * KMH_TO_MS
	_car_half_length = _tuning.f("car_length") * 0.5
	_car_half_width = _tuning.f("car_width") * 0.5
	_lane_width = _tuning.f("lane_width")
	_change_length = _tuning.f("gen_lane_change")
	_close_gap = _tuning.f("close_call_gap")
	_signal_time = _tuning.f("signal_time")
	_late_signal_time = _tuning.f("late_signal_time")
	_change_time = _tuning.f("lane_change_time")
	_despawn_behind = _tuning.f("despawn_behind")


## Every rule of GDD 9.2 on one plan.
func check(plan: Dictionary) -> PackedStringArray:
	problems = []
	var leg: Dictionary = _data.record("legs", GameData.as_string(plan.get("leg")))
	if GameData.as_bool(plan.get("sparse")):
		_problem("the generator fell back to a sparse leg")
	if GameData.as_int(plan.get("attempts")) > _tuning.i("gen_max_attempts"):
		_problem("more draws than gen_max_attempts")
	_load_road(plan)
	_check_beats(plan, leg)
	_check_calm(plan)
	_check_line()
	_check_spawns()
	var motorcade: Dictionary = GameData.as_dict(plan.get("motorcade"))
	if not motorcade.is_empty():
		_load_road(GameData.as_dict(motorcade.get("detour")))
		_check_line()
		_check_spawns()
		_load_road(plan)
	return problems


func _problem(text: String) -> void:
	if problems.size() < MAX_PROBLEMS:
		problems.append(text)


func _load_road(road: Dictionary) -> void:
	_lanes = GameData.as_int(road.get("lanes"), 3)
	_divided = GameData.as_bool(road.get("divided"), true)
	_length = GameData.as_float(road.get("length"))
	_spawns = GameData.as_array(road.get("spawns"))
	_hazards = GameData.as_array(road.get("hazards"))
	_zones = GameData.as_array(road.get("zones"))
	_flock = GameData.as_dict(road.get("flock"))
	_path_s = PackedFloat64Array()
	_path_lane = PackedInt32Array()
	for entry: Variant in GameData.as_array(road.get("path")):
		var pair: Array = GameData.as_array(entry)
		_path_s.append(GameData.as_float(pair[0]))
		_path_lane.append(GameData.as_int(pair[1]))

	_z = []
	_line_moments = PackedFloat64Array()
	for index: int in range(1, _path_s.size()):
		_line_moments.append(_path_s[index])
		_line_moments.append(_path_s[index] + _change_length)
	for entry: Variant in _zones:
		var zone: Dictionary = GameData.as_dict(entry)
		if GameData.as_string(zone.get("kind")) != "chicane":
			continue
		var start: float = GameData.as_float(zone.get("s"))
		var length: float = GameData.as_float(zone.get("length"))
		var shift: float = GameData.as_float(zone.get("shift"))
		var straight: float = (length - shift) * 0.5
		_z.append(PackedFloat64Array([start, start + straight, start + straight + shift, start + length,
				_lane_x(GameData.as_int(zone.get("from_lane"))), _lane_x(GameData.as_int(zone.get("to_lane")))]))
		for at: float in [start, start + straight, start + straight + shift, start + length]:
			_line_moments.append(at)

	_v_name = PackedStringArray()
	_v_trigger = PackedFloat64Array()
	_v_ahead = PackedFloat64Array()
	_v_closing = PackedFloat64Array()
	_v_half_length = PackedFloat64Array()
	_v_half_width = PackedFloat64Array()
	_v_lane = PackedInt32Array()
	_v_direction = PackedInt32Array()
	_v_from_x = PackedFloat64Array()
	_v_to_x = PackedFloat64Array()
	_v_move_from = PackedFloat64Array()
	_v_move_to = PackedFloat64Array()
	for spawn: Variant in _spawns:
		var vehicle: Dictionary = GameData.as_dict(spawn)
		var record: Dictionary = _data.record("vehicles", GameData.as_string(vehicle.get("vehicle")))
		var direction: int = GameData.as_int(vehicle.get("direction"), 1)
		var closing: float = 1.0 - float(direction) * GameData.as_float(vehicle.get("speed")) / _par
		var trigger: float = GameData.as_float(vehicle.get("trigger_s"))
		var lane: int = GameData.as_int(vehicle.get("lane"))
		var change_to: int = GameData.as_int(vehicle.get("change_to"))
		_v_name.append(GameData.as_string(vehicle.get("vehicle")))
		_v_trigger.append(trigger)
		_v_ahead.append(GameData.as_float(vehicle.get("ahead")))
		_v_closing.append(closing)
		_v_half_length.append(GameData.as_float(record.get("length")) * 0.5)
		_v_half_width.append(GameData.as_float(record.get("width")) * 0.5)
		_v_lane.append(lane)
		_v_direction.append(direction)
		_v_from_x.append(_lane_x(lane))
		_v_to_x.append(_lane_x(change_to))
		var move_from: float = INF
		var move_to: float = INF
		if change_to != lane and closing > 0.0:
			# It signals when the gap has closed to change_gap, then moves over.
			var signal_from: float = maxf(trigger + (GameData.as_float(vehicle.get("ahead")) - GameData.as_float(vehicle.get("change_gap"))) / closing, trigger)
			var signal_time: float = _late_signal_time if GameData.as_bool(vehicle.get("late")) else _signal_time
			move_from = signal_from + signal_time * _par_ms
			move_to = signal_from + (signal_time + _change_time) * _par_ms
		_v_move_from.append(move_from)
		_v_move_to.append(move_to)


# --- Rules 1 and 2, and the beat table ---------------------------------------

func _check_beats(plan: Dictionary, leg: Dictionary) -> void:
	var beats: Array = GameData.as_array(plan.get("beats"))
	var beats_end: float = _tuning.f("leg_length") - _tuning.f("leg_tail")
	var lengths: Dictionary = _tuning.d("beat_lengths")
	var cursor: float = 0.0
	var calms: int = 0
	var first_event: float = INF
	var previous: String = ""
	for entry: Variant in beats:
		var beat: Dictionary = GameData.as_dict(entry)
		var type: String = GameData.as_string(beat.get("type"))
		var s: float = GameData.as_float(beat.get("s"))
		var length: float = GameData.as_float(beat.get("length"))
		if absf(s - cursor) > 0.001:
			_problem("beat %s at %s does not follow the one before it (expected %s)" % [type, str(s), str(cursor)])
		cursor = s + length
		if type != "SPECIAL":
			var template: String = GameData.as_string(beat.get("template"))
			if not _data.has_record("beats", template) or GameData.as_string(_data.record("beats", template).get("type")) != type:
				_problem("beat %s at %s names template '%s', which is not of its type" % [type, str(s), template])
			var span: Array = GameData.as_array(lengths.get(type))
			if span.size() != 2 or length < GameData.as_float(span[0]) - 0.001 or length > GameData.as_float(span[1]) + 0.001:
				_problem("beat %s at %s is %s m long, outside the table of GDD 9.2" % [type, str(s), str(length)])
		if type == "CALM":
			calms += 1
			if previous == "CALM" and not GameData.as_bool(leg.get("calm_adjacent")):
				_problem("rule 2: two CALM beats are adjacent at %s" % str(s))
		if EVENT_TYPES.has(type) and first_event == INF:
			first_event = s
		previous = type
	if absf(cursor - beats_end) > 0.001:
		_problem("the beats end at %s, not at %s" % [str(cursor), str(beats_end)])
	if first_event > _tuning.f("first_event_within"):
		_problem("rule 1: the first HAZARD, CLUSTER or SLOWPOKE begins at %s" % str(first_event))
	if calms < 2:
		_problem("rule 2: %d CALM beat(s)" % calms)


## A CALM beat has no vehicle or hazard in reach: nothing is level with the
## player, or within gen_block_margin of it, while he is in the beat.
func _check_calm(plan: Dictionary) -> void:
	var margin: float = _tuning.f("gen_block_margin")
	for entry: Variant in GameData.as_array(plan.get("beats")):
		var beat: Dictionary = GameData.as_dict(entry)
		if GameData.as_string(beat.get("type")) != "CALM":
			continue
		var from: float = GameData.as_float(beat.get("s"))
		var to: float = from + GameData.as_float(beat.get("length"))
		for index: int in _v_name.size():
			if _v_direction[index] < 0 or _v_lane[index] == SHOULDER_LANE:
				continue
			var level: Vector2 = _level(index, margin)
			if level.y > from + 0.001 and level.x < to - 0.001:
				_problem("CALM beat at %s: a %s is in reach from %s to %s" % [str(from), _v_name[index], str(level.x), str(level.y)])
		for hazard: Variant in _hazards:
			var record: Dictionary = GameData.as_dict(hazard)
			var s: float = GameData.as_float(record.get("s"))
			if s > from and s < to:
				_problem("CALM beat at %s: a %s lies in it at %s" % [str(from), GameData.as_string(record.get("kind")), str(s)])


# --- Rule 3: never a wall ----------------------------------------------------

## The plan's line must be drivable at par: it stays on the road, changes one
## lane at a time with room to do it, and is never level with a vehicle or a
## hazard with less than close_call_gap of sideways room.
func _check_line() -> void:
	if _path_s.is_empty():
		_problem("rule 3: the plan has no line through the leg")
		return
	if absf(_path_s[0]) > 0.001:
		_problem("rule 3: the line does not begin at the start")
	for index: int in _path_s.size():
		var lane: int = _path_lane[index]
		if lane >= _lanes or lane < ONCOMING_LANE or (lane == ONCOMING_LANE and _divided):
			_problem("rule 3: the line leaves the road (lane %d) at %s" % [lane, str(_path_s[index])])
		if index == 0:
			continue
		if absi(lane - _path_lane[index - 1]) != 1:
			_problem("rule 3: the line jumps from lane %d to lane %d at %s" % [_path_lane[index - 1], lane, str(_path_s[index])])
		var room_before: float = _path_s[index] - _path_s[index - 1]
		if index > 1 and room_before < _change_length - 0.001:
			_problem("rule 3: lane changes at %s and %s overlap" % [str(_path_s[index - 1]), str(_path_s[index])])
	if _path_s[_path_s.size() - 1] + _change_length > _length + 0.001 and _path_s.size() > 1:
		_problem("rule 3: the last lane change does not finish before the leg ends")

	for index: int in _v_name.size():
		if _v_lane[index] == SHOULDER_LANE and absf(_v_closing[index] - 1.0) > 0.000001:
			_problem("a moving vehicle is planned on the shoulder")
		var level: Vector2 = _level(index, 0.0)
		if level.y <= level.x:
			continue
		var worst: float = INF
		var worst_at: float = 0.0
		for at: float in _moments(level.x, level.y, _v_move_from[index], _v_move_to[index]):
			var room: float = absf(_line_x(at) - _vehicle_x(index, at)) - _v_half_width[index] - _car_half_width
			if room < worst:
				worst = room
				worst_at = at
		if worst < _close_gap - 0.001:
			_problem("rule 3: the line passes a %s with %s m of room at %s" % [_v_name[index], str(snappedf(worst, 0.01)), str(snappedf(worst_at, 0.1))])

	var kinds: Dictionary = {}
	for hazard: Variant in _hazards:
		var record: Dictionary = GameData.as_dict(hazard)
		var kind_id: String = GameData.as_string(record.get("kind"))
		if not kinds.has(kind_id):
			var kind: Dictionary = _data.record("hazard_kinds", kind_id)
			kinds[kind_id] = Vector2(GameData.as_float(kind.get("length")) * 0.5 + _car_half_length, GameData.as_float(kind.get("width")) * 0.5)
		var size: Vector2 = kinds[kind_id]
		var s: float = GameData.as_float(record.get("s"))
		var x: float = GameData.as_float(record.get("x"))
		for at: float in _moments(s - size.x, s + size.x, INF, INF):
			if absf(_line_x(at) - x) - size.y - _car_half_width < -0.001:
				_problem("rule 3: the line runs over a %s at %s" % [kind_id, str(s)])
				break

	if not _flock.is_empty():
		var kind: Dictionary = _data.record("hazard_kinds", GameData.as_string(_flock.get("kind")))
		var s: float = GameData.as_float(_flock.get("s"))
		var reach: float = GameData.as_float(kind.get("length")) * 0.5 + _car_half_length
		var half_width: float = GameData.as_float(kind.get("width")) * 0.5
		for at: float in [s - reach, s, s + reach]:
			# The flock has walked since the car passed its start point.
			var walked: float = GameData.as_float(_flock.get("speed")) * maxf(at - GameData.as_float(_flock.get("start_s")), 0.0) / _par_ms
			for x: Variant in GameData.as_array(_flock.get("xs")):
				var room: float = absf(_line_x(at) - (GameData.as_float(x) + walked)) - half_width - _car_half_width
				if room < -0.001:
					_problem("rule 3: the line runs into the flock at %s" % str(at))


## Where across the road the line is when the player is at `s`. A lane
## change moves it steadily over gen_lane_change metres; inside a chicane it
## follows the corridor between the cones.
func _line_x(s: float) -> float:
	for zone: PackedFloat64Array in _z:
		if s >= zone[0] and s <= zone[3]:
			return lerpf(zone[4], zone[5], clampf((s - zone[1]) / (zone[2] - zone[1]), 0.0, 1.0))
	var x: float = _lane_x(_path_lane[0])
	for index: int in range(1, _path_s.size()):
		if s < _path_s[index]:
			break
		var share: float = clampf((s - _path_s[index]) / _change_length, 0.0, 1.0)
		x = lerpf(_lane_x(_path_lane[index - 1]), _lane_x(_path_lane[index]), share)
	return x


func _lane_x(lane: int) -> float:
	if lane == SHOULDER_LANE:
		return _lane_width * float(_lanes) + _tuning.f("rumble_strip_width") + _tuning.f("shoulder_width") * 0.5
	return _lane_width * (float(lane) + 0.5)


## The player's progress from which to which vehicle `index` is level with
## him, with `extra` metres added at both ends: Vector2(from, to). A vehicle
## he never reaches gives from > to.
func _level(index: int, extra: float) -> Vector2:
	var closing: float = _v_closing[index]
	if closing <= 0.0:
		return Vector2(INF, -INF)
	var reach: float = _v_half_length[index] + _car_half_length + extra
	return Vector2(maxf(_v_trigger[index] + (_v_ahead[index] - reach) / closing, 0.0),
			minf(_v_trigger[index] + (_v_ahead[index] + reach) / closing, _length))


## How far ahead of the player vehicle `index` is when he is at `s`.
func _gap(index: int, s: float) -> float:
	return _v_ahead[index] - _v_closing[index] * (s - _v_trigger[index])


## Where across the road vehicle `index` is when the player is at `s`: in its
## lane until it starts to move over, then steadily across.
func _vehicle_x(index: int, s: float) -> float:
	if s <= _v_move_from[index]:
		return _v_from_x[index]
	return lerpf(_v_from_x[index], _v_to_x[index], clampf((s - _v_move_from[index]) / (_v_move_to[index] - _v_move_from[index]), 0.0, 1.0))


## The points between `from` and `to` at which a sideways distance can be
## smallest: the ends, and every point where the line or the vehicle starts
## or stops moving sideways.
func _moments(from: float, to: float, move_from: float, move_to: float) -> PackedFloat64Array:
	var out: PackedFloat64Array = PackedFloat64Array([from, to])
	for at: float in _line_moments:
		if at > from and at < to:
			out.append(at)
	if move_from > from and move_from < to:
		out.append(move_from)
	if move_to > from and move_to < to:
		out.append(move_to)
	return out


# --- Rule 4: no vehicle appears overlapping another --------------------------

func _check_spawns() -> void:
	var count: int = _v_name.size()
	for first: int in count:
		for second: int in range(first + 1, count):
			if _v_direction[first] != _v_direction[second]:
				continue
			# The moment the later of the two appears.
			var at: float = maxf(_v_trigger[first], _v_trigger[second])
			var first_gap: float = _gap(first, at)
			var second_gap: float = _gap(second, at)
			if absf(first_gap - second_gap) >= _v_half_length[first] + _v_half_length[second]:
				continue
			if minf(first_gap, second_gap) < -_despawn_behind:
				# One of them is gone by then.
				continue
			if absf(_vehicle_x(first, at) - _vehicle_x(second, at)) < _v_half_width[first] + _v_half_width[second]:
				_problem("rule 4: a %s and a %s overlap when the later one appears at %s" % [_v_name[first], _v_name[second], str(at)])


# --- The same leg, driven ----------------------------------------------------

## Runs the plan with the real LegSim, TrafficSim and Collision. A ghost car
## holds third gear's speed along the plan's line. Problems: a hit, a close
## call, a hazard run over, two vehicles overlapping when one appears, or a
## vehicle that is not where the plan says when the ghost comes level with it.
func drive(plan: Dictionary, dt: float) -> PackedStringArray:
	problems = []
	_load_road(plan)
	var car: CarSim = CarSim.new()
	car.configure(_tuning)
	car.set_road(_lanes, _divided)
	var traffic: TrafficSim = TrafficSim.new()
	traffic.configure(_data)
	var collision: Collision = Collision.new()
	collision.configure(_tuning)
	var leg: LegSim = LegSim.new()
	leg.configure(_data, car, traffic)
	car.reset(GameData.as_int(plan.get("start_lane")), 3)
	car.speed = _par
	leg.begin(plan)

	# Where each planned vehicle should be level with the ghost, by vehicle id.
	var seen: Dictionary = {}
	var met: Dictionary = {}
	var planned_meets: PackedFloat64Array = PackedFloat64Array()
	for spawn: Variant in _spawns:
		var meet: float = GameData.as_float(GameData.as_dict(spawn).get("meet_s"))
		if meet >= 0.0 and meet < _length and GameData.as_int(GameData.as_dict(spawn).get("lane")) != SHOULDER_LANE:
			planned_meets.append(meet)
	var actual_meets: PackedFloat64Array = PackedFloat64Array()

	var known: int = 0
	var guard: int = int(_length / (_par_ms * dt)) + 10
	while car.s < _length and guard > 0:
		guard -= 1
		leg.begin_tick()
		leg.step_road(dt)
		car.s += _par_ms * dt
		car.x = _line_x(car.s)
		car.speed = _par
		leg.step_traffic(dt)
		traffic.step(dt, car.s, car.x, car.speed)
		collision.step(dt, car, traffic, 3)
		if collision.hit != Collision.Hit.NONE:
			_problem("driven: the ghost hit vehicle %d at %s" % [collision.hit_vehicle_id, str(snappedf(car.s, 0.1))])
			break
		if collision.close_calls > 0:
			_problem("driven: a close call at %s" % str(snappedf(car.s, 0.1)))
		leg.step_hazards(dt)
		for kind: StringName in leg.hits:
			_problem("driven: the ghost ran over a %s at %s" % [kind, str(snappedf(car.s, 0.1))])
		# Rule 4, when something has just appeared.
		if traffic.vehicles.size() != known:
			known = traffic.vehicles.size()
			for vehicle: TrafficSim.Vehicle in traffic.vehicles:
				if seen.has(vehicle.id):
					continue
				seen[vehicle.id] = true
				for other: TrafficSim.Vehicle in traffic.vehicles:
					if other == vehicle:
						continue
					if absf(other.s - vehicle.s) < other.half_length + vehicle.half_length \
							and absf(other.x - vehicle.x) < other.half_width + vehicle.half_width:
						_problem("driven: a %s appeared on top of a %s at %s" % [vehicle.type_id, other.type_id, str(snappedf(car.s, 0.1))])
		for vehicle: TrafficSim.Vehicle in traffic.vehicles:
			if not met.has(vehicle.id) and vehicle.s <= car.s and vehicle.x < car.road_right():
				met[vehicle.id] = true
				actual_meets.append(car.s)
	leg.step_progress()
	if not leg.finished:
		_problem("driven: the leg did not end")

	# Every vehicle is met where the plan says (within what one tick and a
	# lane change can shift it).
	planned_meets.sort()
	actual_meets.sort()
	if planned_meets.size() != actual_meets.size():
		_problem("driven: %d vehicles planned to be met, %d met" % [planned_meets.size(), actual_meets.size()])
	else:
		for index: int in planned_meets.size():
			if absf(planned_meets[index] - actual_meets[index]) > 3.0 * _par_ms * dt + 1.0:
				_problem("driven: a vehicle planned to be met at %s was met at %s" % [str(planned_meets[index]), str(snappedf(actual_meets[index], 0.1))])
				break
	return problems
