class_name TrafficSim
extends RefCounted
## Traffic (GDD 5.5).
##
## Vehicles hold a lane at a set speed. Every lane change is scheduled by the
## beat that spawned the vehicle, or caused by the horn. A lane change is
## signalled for signal_time and takes lane_change_time, both counted in
## whole ticks. A vehicle that catches up with another in its lane, or with
## the player from behind, follows at its speed instead of driving through
## it (DECISIONS D-023). Oncoming vehicles follow each other the same way;
## they do not react to the player. Vehicles are removed despawn_behind
## metres behind the player.

class Vehicle:
	extends RefCounted
	var id: int = 0
	var type_id: StringName = &""
	var type_index: int = 0
	var half_width: float = 0.0
	var half_length: float = 0.0
	## Metres across the road and along the leg (centre of the vehicle).
	var x: float = 0.0
	var s: float = 0.0
	## km/h along its own direction of travel; `cruise` is what it wants.
	var speed: float = 0.0
	var cruise: float = 0.0
	## +1 with the player, -1 oncoming.
	var direction: int = 1
	var lane: int = 0
	var yields_to_horn: bool = false
	var honk_nerves: float = 0.0
	## Lane change in progress: -1 signalling left, +1 right, 0 none.
	var signalling: int = 0
	var signal_left: float = 0.0
	var change_left: float = 0.0
	var change_from_x: float = 0.0
	var change_to_x: float = 0.0
	var change_to_lane: int = 0
	var change_duration: float = 0.0
	var changing: bool = false
	## A scheduled lane change: starts signalling when the vehicle reaches plan_s.
	var has_plan: bool = false
	var plan_s: float = 0.0
	var plan_lane: int = 0
	var plan_signal: float = 0.0
	## Close-call bookkeeping (Collision).
	var cc_overlap: bool = false
	var cc_min_gap: float = INF
	var cc_contact: bool = false
	## True from the tick this vehicle hits the car until that contact is over
	## (Collision): one contact, one hit.
	var cc_hit: bool = false
	## Anything a leg wants to remember about this vehicle (police, motorcade...).
	var role: StringName = &""
	## Bookkeeping of TrafficSim.step: its place in the order along the road
	## and its s when the tick began, and whether it has been taken off the road.
	var rank: int = 0
	var s_then: float = 0.0
	var off_road: bool = false

	func closing_speed(player_speed: float) -> float:
		if direction < 0:
			return player_speed + speed
		return player_speed - speed

	func velocity() -> float:
		return speed * float(direction)

const KMH_TO_MS: float = 1.0 / 3.6

var vehicles: Array[Vehicle] = []
## Where barriers stand between the lanes (a checkpoint's corridors and the
## taper into them), from and to in metres along the road; ZERO for none.
## Nobody changes lane there. Whoever builds the road sets it.
var walled: Vector2 = Vector2.ZERO

var _type_ids: Array[StringName] = []
var _type_records: Array[Dictionary] = []
var _lane_width: float = 0.0
var _signal_time: float = 0.0
var _late_signal_time: float = 0.0
var _change_time: float = 0.0
var _despawn_behind: float = 0.0
var _follow_gap: float = 0.0
var _car_half_length: float = 0.0
var _car_half_width: float = 0.0
var _next_id: int = 1
## The vehicles in the order they stood along the road when the tick began
## (lowest s first), so that each looks only at what is just ahead of it.
var _order: Array[Vehicle] = []
var _order_stale: bool = true
## How far ahead, centre to centre at the start of a tick, another vehicle
## can be and still be within traffic_follow_gap: the gap and two half lengths.
var _reach: float = 0.0


func configure(data: GameData) -> void:
	var tuning: Tuning = data.tuning
	_lane_width = tuning.f("lane_width")
	_signal_time = tuning.f("signal_time")
	_late_signal_time = tuning.f("late_signal_time")
	_change_time = tuning.f("lane_change_time")
	_despawn_behind = tuning.f("despawn_behind")
	_follow_gap = tuning.f("traffic_follow_gap")
	_car_half_length = tuning.f("car_length") * 0.5
	_car_half_width = tuning.f("car_width") * 0.5
	_type_ids.clear()
	_type_records.clear()
	var longest: float = 0.0
	for record: Dictionary in data.records("vehicles"):
		_type_ids.append(StringName(GameData.as_string(record.get("id"))))
		_type_records.append(record)
		longest = maxf(longest, GameData.as_float(record.get("length")))
	_reach = _follow_gap + longest


func clear() -> void:
	vehicles.clear()
	_order_stale = true
	_next_id = 1
	walled = Vector2.ZERO


## Takes every vehicle off the road in the middle of a leg (the car has
## turned onto another road). Ids go on counting, so no later vehicle is
## mistaken for one of these.
func remove_all() -> void:
	vehicles.clear()
	_order_stale = true


func remove(vehicle: Vehicle) -> void:
	vehicles.erase(vehicle)
	_order_stale = true


func lane_center(lane: int) -> float:
	return _lane_width * (float(lane) + 0.5)


## Adds a vehicle. `lane` -1 is the oncoming lane. Unknown types are an error.
func spawn(type_id: StringName, lane: int, s: float, speed_kmh: float, direction: int = 1) -> Vehicle:
	var type_index: int = _type_ids.find(type_id)
	if type_index == -1:
		push_error("TrafficSim: unknown vehicle type '%s'" % type_id)
		return null
	var record: Dictionary = _type_records[type_index]
	var vehicle: Vehicle = Vehicle.new()
	vehicle.id = _next_id
	_next_id += 1
	vehicle.type_id = type_id
	vehicle.type_index = type_index
	vehicle.half_width = GameData.as_float(record.get("width")) * 0.5
	vehicle.half_length = GameData.as_float(record.get("length")) * 0.5
	vehicle.yields_to_horn = GameData.as_bool(record.get("yields_to_horn"))
	vehicle.honk_nerves = GameData.as_float(record.get("honk_nerves"))
	vehicle.lane = lane
	vehicle.x = lane_center(lane)
	vehicle.s = s
	vehicle.speed = speed_kmh
	vehicle.cruise = speed_kmh
	vehicle.direction = direction
	vehicles.append(vehicle)
	_order_stale = true
	return vehicle


## Schedules one lane change: the vehicle starts signalling when it reaches
## `at_s`, signals for signal_time (late_signal_time when `late`), then moves
## over during lane_change_time.
func plan_lane_change(vehicle: Vehicle, at_s: float, to_lane: int, late: bool = false) -> void:
	vehicle.has_plan = true
	vehicle.plan_s = at_s
	vehicle.plan_lane = to_lane
	vehicle.plan_signal = _late_signal_time if late else _signal_time


## Starts a lane change now. `duration` is how long the move itself takes
## (0 means lane_change_time); the horn asks for a quicker one. Nobody
## changes lane where barriers stand between the lanes, nor begins a change
## that would still be going on when they are reached.
func begin_lane_change(vehicle: Vehicle, to_lane: int, signal_time: float, duration: float = 0.0) -> void:
	if vehicle.changing or vehicle.signalling != 0 or to_lane == vehicle.lane:
		return
	var took: float = signal_time + (duration if duration > 0.0 else _change_time)
	if _between_walls(vehicle, took):
		return
	vehicle.signalling = 1 if to_lane > vehicle.lane else -1
	vehicle.signal_left = signal_time
	vehicle.change_to_lane = to_lane
	vehicle.change_duration = duration if duration > 0.0 else _change_time


## True when a vehicle going `direction`'s way is within `reach` metres of
## `s` along the road, in any lane.
func someone_near(s: float, reach: float, direction: int) -> bool:
	for vehicle: Vehicle in vehicles:
		if vehicle.direction == direction and absf(vehicle.s - s) < reach:
			return true
	return false


## True when any of a vehicle's next `seconds` of road, at the speed it has,
## lies where barriers stand between the lanes.
func _between_walls(vehicle: Vehicle, seconds: float) -> bool:
	if walled.y <= walled.x:
		return false
	var from: float = vehicle.s - vehicle.half_length
	var to: float = vehicle.s + vehicle.half_length
	var travel: float = vehicle.velocity() * KMH_TO_MS * seconds
	return maxf(to, to + travel) >= walled.x and minf(from, from + travel) <= walled.y


func step(dt: float, player_s: float, player_x: float, player_speed: float) -> void:
	_rank()
	var index: int = 0
	while index < vehicles.size():
		var vehicle: Vehicle = vehicles[index]
		_step_speed(vehicle, player_s, player_x, player_speed)
		vehicle.s += vehicle.velocity() * KMH_TO_MS * dt
		_step_lane_change(vehicle, dt)
		if vehicle.s + vehicle.half_length < player_s - _despawn_behind:
			vehicle.off_road = true
			vehicles.remove_at(index)
			_order_stale = true
		else:
			index += 1


## Puts the vehicles in the order they stand along the road now. The order
## barely changes from one tick to the next, so this is a pass over a list
## that is already nearly sorted.
func _rank() -> void:
	if _order_stale or _order.size() != vehicles.size():
		_order.assign(vehicles)
		_order_stale = false
	var count: int = _order.size()
	for place: int in range(1, count):
		var moving: Vehicle = _order[place]
		var s: float = moving.s
		var before: int = place - 1
		while before >= 0 and _order[before].s > s:
			_order[before + 1] = _order[before]
			before -= 1
		_order[before + 1] = moving
	for place: int in count:
		var vehicle: Vehicle = _order[place]
		vehicle.rank = place
		vehicle.s_then = vehicle.s


## True when the two lanes' worth of road beside `s` in `lane` is clear of
## other vehicles for `clearance` metres each way (for horn yields).
func lane_is_free(lane: int, s: float, clearance: float, ignore: Vehicle) -> bool:
	var center: float = lane_center(lane)
	for other: Vehicle in vehicles:
		if other == ignore:
			continue
		if absf(other.x - center) < _lane_width * 0.5 and absf(other.s - s) < clearance + other.half_length:
			return false
	return true


func _step_speed(vehicle: Vehicle, player_s: float, player_x: float, player_speed: float) -> void:
	var wanted: float = vehicle.cruise
	# Follow whatever is just ahead in the same lane and going the same way:
	# another vehicle... Only what stood ahead of it along the road when the
	# tick began, and no further than _reach, can be within the gap: nothing
	# moves backwards, and nothing moves a half length in one tick.
	var direction: int = vehicle.direction
	var x: float = vehicle.x
	var half_width: float = vehicle.half_width
	var s_then: float = vehicle.s_then
	var count: int = _order.size()
	var place: int = vehicle.rank + direction
	while place >= 0 and place < count:
		var other: Vehicle = _order[place]
		place += direction
		if absf(other.s_then - s_then) > _reach:
			break
		if other.off_road or other.direction != direction:
			continue
		if absf(other.x - x) >= half_width + other.half_width:
			continue
		var gap: float = _gap_ahead(vehicle, other)
		if gap >= 0.0 and gap < _follow_gap:
			wanted = minf(wanted, other.speed)
	# ...or the player, so ordinary traffic never rams him from behind. An
	# oncoming vehicle does not react to him.
	if vehicle.direction > 0 and absf(player_x - vehicle.x) < vehicle.half_width + _car_half_width:
		var gap_to_player: float = (player_s - _car_half_length) - (vehicle.s + vehicle.half_length)
		if gap_to_player >= 0.0 and gap_to_player < _follow_gap:
			wanted = minf(wanted, player_speed)
	vehicle.speed = wanted


## Metres of road between `vehicle` and `other`, measured along the way the
## vehicle is going: positive when `other` is ahead of it, negative when the
## two overlap along the road or `other` is behind.
func _gap_ahead(vehicle: Vehicle, other: Vehicle) -> float:
	if vehicle.direction > 0:
		return (other.s - other.half_length) - (vehicle.s + vehicle.half_length)
	return (vehicle.s - vehicle.half_length) - (other.s + other.half_length)


func _step_lane_change(vehicle: Vehicle, dt: float) -> void:
	if vehicle.has_plan and vehicle.s * float(vehicle.direction) >= vehicle.plan_s * float(vehicle.direction):
		vehicle.has_plan = false
		begin_lane_change(vehicle, vehicle.plan_lane, vehicle.plan_signal)
	# Both times are counted in whole ticks: a countdown is over when less
	# than half a tick of it is left, whatever rounding did to the rest.
	var over: float = dt * 0.5
	if vehicle.signalling != 0 and not vehicle.changing:
		if vehicle.signal_left < over:
			vehicle.changing = true
			vehicle.change_left = vehicle.change_duration
			vehicle.change_from_x = vehicle.x
			vehicle.change_to_x = lane_center(vehicle.change_to_lane)
		else:
			vehicle.signal_left -= dt
	if vehicle.changing:
		vehicle.change_left -= dt
		var done: float = 1.0 - clampf(vehicle.change_left / vehicle.change_duration, 0.0, 1.0)
		vehicle.x = lerpf(vehicle.change_from_x, vehicle.change_to_x, done)
		if vehicle.change_left < over:
			vehicle.x = vehicle.change_to_x
			vehicle.lane = vehicle.change_to_lane
			vehicle.changing = false
			vehicle.signalling = 0
