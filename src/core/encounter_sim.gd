class_name EncounterSim
extends RefCounted
## The leg's encounter (GDD 9.3): the Patrol that follows him, the Tailgater
## on his bumper, the Motorcade that fills the road.
##
## The encounter's vehicles are ordinary TrafficSim vehicles with a role;
## this class steers them and tells DriveSim, tick by tick, what the
## encounter does to him: whether someone is watching (Suspicion), what it
## adds to his Nerves, how bright the spotlight is.

const KMH_TO_MS: float = 1.0 / 3.6
const POLICE: StringName = &"police"

const PATROL_WAITING: int = 0
const PATROL_LIGHTS: int = 1
const PATROL_WATCHING: int = 2
const PATROL_OVER: int = 3

const TAILGATER: StringName = &"tailgater"
const TAIL_WAITING: int = 0
## Closing up, headlights flashing: the tell.
const TAIL_TELL: int = 1
const TAIL_ON_BUMPER: int = 2
## He has had enough of waiting: past him, in front of him, and a stab at the brake.
const TAIL_PASSING: int = 3
const TAIL_CUTTING_IN: int = 4
const TAIL_BRAKING: int = 5
const TAIL_GONE: int = 6
## The car's tracks are kept this far back, a sample every TRAIL_STEP metres.
const TRAIL_LENGTH: float = 150.0
const TRAIL_STEP: float = 0.5
## How far the ramming Tailgater is put into the car's rear, and how long
## after the hit's immunity he leaves it before he can ram again.
const RAM_OVERLAP: float = 0.3
const RAM_PAUSE: float = 1.0

const MOTORCADE: StringName = &"motorcade"
const ROAD_MARGIN: float = 5.0
const SIDE_ROAD_AHEAD: int = 0
## The slip lane is open on the right.
const SIDE_ROAD_OPEN: int = 1
const SIDE_ROAD_TAKEN: int = 2
const SIDE_ROAD_BEHIND: int = 3

var kind: String = ""
## True while the encounter is on: an empty road does not calm him then.
var active: bool = false
## Seconds since the leg began (the encounter's own clock; it stops while he
## is pulled over).
var time: float = 0.0

# --- Patrol ------------------------------------------------------------------
## Blue lights behind him: the tell, lights_lead_s before Suspicion starts.
var police_lights: bool = false
var patrol_phase: int = PATROL_WAITING

# --- Tailgater ---------------------------------------------------------------
var tail_phase: int = TAIL_WAITING

# --- What happened this tick -------------------------------------------------
## Suspicion starts or ends.
var watch_began: bool = false
var watch_ended: bool = false
## Nerves per second the encounter adds this tick.
var nerves_rate: float = 0.0
## The part of nerves_rate that is the tailgater on his bumper.
var tail_nerves_rate: float = 0.0
## He was cut off (the Tailgater's stab at the brake in front of him).
var cut_off: bool = false
## The road under the car changed (a slip lane opened or closed, the side
## road began or ended): DriveSim must look again at which lane the car is in.
var road_changed: bool = false

# --- Motorcade ---------------------------------------------------------------
## How bright the spotlight on his windscreen is now, 0 to 1.
var glare: float = 0.0
var side_road: int = SIDE_ROAD_AHEAD
## Where the last car of the motorcade is along the leg (also while the cars
## are out of sight on the main road).
var motorcade_s: float = 0.0

var _data: GameData
var _tuning: Tuning
var _car: CarSim
var _traffic: TrafficSim
var _special: Dictionary = {}
var _police: TrafficSim.Vehicle = null
var _car_half_length: float = 0.0
var _tail: TrafficSim.Vehicle = null
## The lane the Tailgater is in; he does not follow a lane change.
var _tail_lane: int = 0
## Metres his middle is ahead of the car's (negative: behind).
var _tail_ahead: float = 0.0
## Seconds the car has been out of his lane, and in a gear that loses him.
var _tail_away: float = 0.0
var _tail_outrun: float = 0.0
var _tail_since: float = 0.0
var _tail_from_x: float = 0.0
var _tail_speed: float = 0.0
var _ram_ready: float = 0.0
var _was_braking: bool = false
var _leg: LegSim
## The motorcade's cars in the order of the plan; null while one is too far
## from the car to be on the road.
var _convoy: Array[TrafficSim.Vehicle] = []
var _convoy_plan: Dictionary = {}
var _convoy_type: StringName = &""
var _convoy_half_length: float = 0.0
## How far the leading row is ahead of the last car.
var _convoy_longest: float = 0.0
var _keep_behind: float = 0.0
var _main_lanes: int = 3
var _main_divided: bool = true
## Where the car has been: s and x, a sample every half metre, for whoever
## drives in his tracks.
var _trail_s: PackedFloat64Array = PackedFloat64Array()
var _trail_x: PackedFloat64Array = PackedFloat64Array()


func configure(data: GameData, car: CarSim, traffic: TrafficSim, leg: LegSim) -> void:
	_data = data
	_tuning = data.tuning
	_car = car
	_traffic = traffic
	_leg = leg
	_car_half_length = _tuning.f("car_length") * 0.5
	# A little inside what TrafficSim keeps behind the car, so that it is this
	# class that takes the motorcade's cars off the road and puts them back.
	_keep_behind = _tuning.f("despawn_behind") - ROAD_MARGIN


## Starts the encounter of the plan's leg type, if it has one.
func begin(plan: Dictionary) -> void:
	# A stretch that is no leg (an approach, a boss) has no encounter of this kind.
	var leg_id: String = GameData.as_string(plan.get("leg"))
	var leg: Dictionary = _data.record("legs", leg_id) if not leg_id.is_empty() else {}
	_special = GameData.as_dict(leg.get("special"))
	kind = GameData.as_string(_special.get("kind"))
	active = false
	time = 0.0
	police_lights = false
	patrol_phase = PATROL_WAITING
	_police = null
	tail_phase = TAIL_WAITING
	_tail = null
	_tail_away = 0.0
	_tail_outrun = 0.0
	_ram_ready = 0.0
	_was_braking = false
	_trail_s = PackedFloat64Array()
	_trail_x = PackedFloat64Array()
	glare = 0.0
	side_road = SIDE_ROAD_AHEAD
	_convoy = []
	_convoy_plan = GameData.as_dict(plan.get("motorcade"))
	_main_lanes = GameData.as_int(plan.get("lanes"), 3)
	_main_divided = GameData.as_bool(plan.get("divided"), true)
	begin_tick()
	if kind == "motorcade" and not _convoy_plan.is_empty():
		_convoy_type = StringName(GameData.as_string(_convoy_plan.get("vehicle")))
		_convoy_half_length = GameData.as_float(_data.record("vehicles", String(_convoy_type)).get("length")) * 0.5
		_convoy_longest = 0.0
		for entry: Variant in GameData.as_array(_convoy_plan.get("cars")):
			_convoy_longest = maxf(_convoy_longest, GameData.as_float(GameData.as_dict(entry).get("ahead")))
		motorcade_s = _car.s + GameData.as_float(_convoy_plan.get("start_ahead"))
		_sync_convoy(GameData.as_float(_convoy_plan.get("speed")))
		active = true


func stop() -> void:
	kind = ""
	active = false
	police_lights = false


## Every vehicle was taken off the road (the car stands at a stop): the
## motorcade's cars are put back where they belong when the road moves again.
func road_cleared() -> void:
	_convoy.clear()


func begin_tick() -> void:
	watch_began = false
	watch_ended = false
	nerves_rate = 0.0
	tail_nerves_rate = 0.0
	cut_off = false
	road_changed = false


## One tick. `braking` is his foot on the brake, `gear` the engaged gear.
func step(dt: float, braking: bool, gear: int) -> void:
	if kind.is_empty():
		return
	time += dt
	_record_trail()
	if kind == "patrol":
		_step_patrol()
	elif kind == "tailgater":
		_step_tailgater(dt, braking, gear)
	elif kind == "motorcade":
		_step_motorcade(dt)
	_was_braking = braking


# --- In his tracks -----------------------------------------------------------

func _record_trail() -> void:
	var last: int = _trail_s.size() - 1
	if last >= 0 and _car.s < _trail_s[last] + TRAIL_STEP:
		return
	_trail_s.append(_car.s)
	_trail_x.append(_car.x)
	# Keep what a follower can still need.
	var keep_from: float = _car.s - TRAIL_LENGTH
	var drop: int = 0
	while drop < _trail_s.size() - 2 and _trail_s[drop + 1] < keep_from:
		drop += 1
	if drop > 64:
		_trail_s = _trail_s.slice(drop)
		_trail_x = _trail_x.slice(drop)


## Where across the road the car was when it was at `s`.
func _trail_x_at(s: float) -> float:
	var count: int = _trail_s.size()
	if count == 0:
		return _car.x
	if s <= _trail_s[0]:
		return _trail_x[0]
	var low: int = 0
	var high: int = count - 1
	if s >= _trail_s[high]:
		return _car.x if s >= _car.s else lerpf(_trail_x[high], _car.x, (s - _trail_s[high]) / maxf(_car.s - _trail_s[high], 0.001))
	while high - low > 1:
		var middle: int = (low + high) / 2
		if _trail_s[middle] <= s:
			low = middle
		else:
			high = middle
	return lerpf(_trail_x[low], _trail_x[high], (s - _trail_s[low]) / maxf(_trail_s[high] - _trail_s[low], 0.001))


## Puts a vehicle `behind` metres behind the car's centre, in his tracks, at
## his speed. It goes where he went, so it gets through the traffic he got
## through and never touches him.
func _shadow(vehicle: TrafficSim.Vehicle, behind: float) -> void:
	vehicle.s = _car.s - behind
	vehicle.x = _trail_x_at(vehicle.s)
	vehicle.speed = _car.speed
	vehicle.cruise = _car.speed
	vehicle.lane = clampi(_car.lane_of(vehicle.x), 0, _car.lanes - 1)
	vehicle.signalling = 0
	vehicle.changing = false
	vehicle.has_plan = false


# --- Patrol (GDD 9.3, 6.5) ---------------------------------------------------

## The police car that is behind him, or null.
func police() -> TrafficSim.Vehicle:
	if _police != null and not _traffic.vehicles.has(_police):
		_police = null
	return _police


## Blue lights show lights_lead_s before Suspicion starts, at_s into the leg;
## the police car then follows for patrol_duration.
func _step_patrol() -> void:
	var at: float = GameData.as_float(_special.get("at_s"))
	var lead: float = GameData.as_float(_special.get("lights_lead_s"))
	match patrol_phase:
		PATROL_WAITING:
			if time >= at - lead and _spawn_police():
				patrol_phase = PATROL_LIGHTS
				police_lights = true
				active = true
		PATROL_LIGHTS:
			_follow()
			if time >= at:
				patrol_phase = PATROL_WATCHING
				watch_began = true
		PATROL_WATCHING:
			_follow()
			if time >= at + _tuning.f("patrol_duration"):
				watch_ended = true
				end_patrol()


## The Patrol is over: the lights go out and the police car falls back.
func end_patrol() -> void:
	if kind != "patrol" or patrol_phase == PATROL_OVER:
		return
	patrol_phase = PATROL_OVER
	police_lights = false
	active = false
	var car: TrafficSim.Vehicle = police()
	if car != null:
		car.role = &""
		car.cruise = maxf(car.cruise - _tuning.f("patrol_catch_up"), 0.0)
	_police = null


## He has been pulled over: the police car stops behind him.
func park_police_behind() -> void:
	var car: TrafficSim.Vehicle = police()
	if car == null:
		return
	car.cruise = 0.0
	car.speed = 0.0
	car.signalling = 0
	car.changing = false
	car.x = _car.x
	car.s = _car.s - _car_half_length - car.half_length - GameData.as_float(_special.get("gap_m"))


func _spawn_police() -> bool:
	_police = _traffic.spawn(POLICE, clampi(_car.lane_of(_car.x), 0, _car.lanes - 1), _car.s - _tuning.f("patrol_spawn_behind"), _car.speed)
	if _police == null:
		return false
	_police.role = POLICE
	_shadow(_police, _tuning.f("patrol_spawn_behind"))
	return true


## The police car closes up from where it appeared to gap_m behind his rear
## bumper while its lights announce it, and stays there, in his tracks.
func _follow() -> void:
	var car: TrafficSim.Vehicle = police()
	if car == null:
		return
	var at: float = GameData.as_float(_special.get("at_s"))
	var lead: float = GameData.as_float(_special.get("lights_lead_s"))
	var place: float = _car_half_length + GameData.as_float(_special.get("gap_m")) + car.half_length
	var closed: float = clampf((time - (at - lead)) / maxf(lead, 0.001), 0.0, 1.0)
	_shadow(car, lerpf(_tuning.f("patrol_spawn_behind"), place, closed))


# --- Tailgater (GDD 9.3) -----------------------------------------------------

## The driver on his bumper, or null.
func tailgater() -> TrafficSim.Vehicle:
	if _tail != null and not _traffic.vehicles.has(_tail):
		_tail = null
	return _tail


## A driver sits on his bumper from at_s for duration_s: +nerves_per_s while
## he is behind, a ram (a scrape from behind) if he touches the brake. He
## leaves when the player changes lane and holds it for lane_hold_s, then
## passes and brakes hard in front once. gear_hold_s in a gear of `gear` or
## higher, or the end of his patience, also lose him.
func _step_tailgater(dt: float, braking: bool, gear: int) -> void:
	var at: float = GameData.as_float(_special.get("at_s"))
	var tell: float = GameData.as_float(_special.get("tell_s"))
	var car_lane: int = clampi(_car.lane_of(_car.x), 0, _car.lanes - 1)
	var driver: TrafficSim.Vehicle = tailgater()
	if tail_phase != TAIL_WAITING and tail_phase != TAIL_GONE and driver == null:
		_tail_gone()
		return
	match tail_phase:
		TAIL_WAITING:
			if time >= at - tell:
				_tail = _traffic.spawn(StringName(GameData.as_string(_special.get("vehicle"), "tailgater_car")), car_lane,
						_car.s - GameData.as_float(_special.get("spawn_behind_m")), _car.speed)
				if _tail != null:
					_tail.role = TAILGATER
					_shadow(_tail, GameData.as_float(_special.get("spawn_behind_m")))
					tail_phase = TAIL_TELL
					active = true
		TAIL_TELL:
			var closed: float = clampf((time - (at - tell)) / maxf(tell, 0.001), 0.0, 1.0)
			_shadow(driver, lerpf(GameData.as_float(_special.get("spawn_behind_m")), _tail_place(driver), closed))
			if time >= at:
				tail_phase = TAIL_ON_BUMPER
				_tail_lane = driver.lane
				_tail_away = 0.0
				_tail_outrun = 0.0
		TAIL_ON_BUMPER:
			_tail_on_bumper(dt, driver, car_lane, braking, gear)
		TAIL_PASSING:
			# Past him in the lane he left, to brake_gap_m in front of his bumper.
			var front: float = _car_half_length + GameData.as_float(_special.get("brake_gap_m")) + driver.half_length
			_tail_ahead = minf(_tail_ahead + GameData.as_float(_special.get("pass_speed_kmh")) * KMH_TO_MS * dt, front)
			_tail_hold(driver, _traffic.lane_center(_tail_lane))
			if _tail_ahead >= front:
				tail_phase = TAIL_CUTTING_IN
				_tail_since = time
				_tail_from_x = driver.x
				_tail_lane = car_lane
		TAIL_CUTTING_IN:
			var share: float = clampf((time - _tail_since) / maxf(GameData.as_float(_special.get("merge_s")), 0.001), 0.0, 1.0)
			_tail_hold(driver, lerpf(_tail_from_x, _traffic.lane_center(_tail_lane), share))
			if share >= 1.0:
				tail_phase = TAIL_BRAKING
				_tail_since = time
				_tail_speed = _car.speed
				cut_off = true
		TAIL_BRAKING:
			# A stab at the brake, then away.
			var since: float = time - _tail_since
			var brake_time: float = GameData.as_float(_special.get("brake_s"))
			var drop: float = GameData.as_float(_special.get("brake_drop_kmh"))
			var speed: float = _tail_speed - drop * clampf(since / maxf(brake_time, 0.001), 0.0, 1.0)
			if since > brake_time:
				speed += GameData.as_float(_special.get("recover_kmh_per_s")) * (since - brake_time)
			driver.cruise = maxf(speed, 0.0)
			driver.speed = driver.cruise
			if speed >= _tail_speed + GameData.as_float(_special.get("pass_speed_kmh")):
				driver.role = &""
				_tail = null
				_tail_gone()


func _tail_on_bumper(dt: float, driver: TrafficSim.Vehicle, car_lane: int, braking: bool, gear: int) -> void:
	var at: float = GameData.as_float(_special.get("at_s"))
	if car_lane == _tail_lane:
		_tail_away = 0.0
		tail_nerves_rate = GameData.as_float(_special.get("nerves_per_s"))
		nerves_rate += tail_nerves_rate
		if braking and not _was_braking and time >= _ram_ready:
			# He brakes: the driver behind does not. A scrape from behind.
			driver.s = _car.s - _car_half_length - driver.half_length + RAM_OVERLAP
			driver.x = _car.x
			driver.speed = _car.speed + GameData.as_float(_special.get("ram_closing_kmh"))
			driver.cruise = driver.speed
			_ram_ready = time + _tuning.f("hit_immunity") + RAM_PAUSE
			return
		_shadow(driver, _tail_place(driver))
	else:
		# He has left the lane: the driver keeps his own, level with where he was.
		_tail_away += dt
		_tail_ahead = -_tail_place(driver)
		_tail_hold(driver, _traffic.lane_center(_tail_lane))
		if _tail_away >= GameData.as_float(_special.get("lane_hold_s")):
			tail_phase = TAIL_PASSING
			return
	if gear >= GameData.as_int(_special.get("gear")):
		_tail_outrun += dt
	else:
		_tail_outrun = 0.0
	if _tail_outrun >= GameData.as_float(_special.get("gear_hold_s")) or time >= at + GameData.as_float(_special.get("duration_s")):
		# Lost, or out of patience: he falls back.
		driver.role = &""
		driver.cruise = maxf(_car.speed - GameData.as_float(_special.get("pass_speed_kmh")), 0.0)
		_tail = null
		_tail_gone()


## Metres between the car's middle and the Tailgater's when he is on the bumper.
func _tail_place(driver: TrafficSim.Vehicle) -> float:
	return _car_half_length + GameData.as_float(_special.get("gap_m")) + driver.half_length


## Keeps the Tailgater _tail_ahead metres from the car's middle at `x`, at the car's speed.
func _tail_hold(driver: TrafficSim.Vehicle, x: float) -> void:
	driver.s = _car.s + _tail_ahead
	driver.x = x
	driver.speed = _car.speed
	driver.cruise = _car.speed
	driver.lane = clampi(_car.lane_of(x), 0, _car.lanes - 1)
	driver.signalling = 0
	driver.changing = false


func _tail_gone() -> void:
	tail_phase = TAIL_GONE
	active = false


# --- Motorcade (GDD 9.3) -----------------------------------------------------

## Five cars fill the road at a steady speed. Within keep_back_m of the last
## one a spotlight is on his windscreen: Glare and Nerves by the second.
## Nothing else ever happens: the motorcade never touches him, because the
## car cannot come nearer than hold_gap_m to it (and it comes no nearer than
## that to him when it is behind him). One side road, mid-leg, goes around it.
func _step_motorcade(dt: float) -> void:
	glare = 0.0
	if _convoy_plan.is_empty():
		return
	var speed: float = GameData.as_float(_convoy_plan.get("speed"))
	var hold_gap: float = GameData.as_float(_special.get("hold_gap_m"))
	motorcade_s += speed * KMH_TO_MS * dt
	_step_side_road()
	if side_road == SIDE_ROAD_TAKEN:
		# He is on the side road; the motorcade goes on along the main road.
		active = false
		return
	if _car.s > motorcade_s:
		# He is ahead of it (after the side road): it is traffic behind him
		# now, and it does not push.
		active = false
		var limit: float = _car.s - _car_half_length - hold_gap - _convoy_half_length - _convoy_longest
		if motorcade_s > limit:
			motorcade_s = limit
			speed = minf(speed, _car.speed)
		_sync_convoy(speed)
		return
	active = true
	# The wall: he cannot come nearer than hold_gap_m to the last car.
	var rear: float = motorcade_s - _convoy_half_length
	var nearest: float = rear - hold_gap - _car_half_length
	if _car.s > nearest:
		_car.s = nearest
		_car.speed = minf(_car.speed, speed)
	_sync_convoy(speed)
	# The spotlight.
	if rear - (_car.s + _car_half_length) < GameData.as_float(_convoy_plan.get("keep_back")):
		glare = GameData.as_float(_special.get("glare"))
		nerves_rate += GameData.as_float(_special.get("nerves_per_s"))


## Puts each car of the motorcade in its place: on the road while it is
## within what the road keeps behind the car (despawn_behind), off it beyond.
func _sync_convoy(speed: float) -> void:
	var cars: Array = GameData.as_array(_convoy_plan.get("cars"))
	if _convoy.size() != cars.size():
		_convoy.resize(cars.size())
	for index: int in cars.size():
		var place: Dictionary = GameData.as_dict(cars[index])
		var s: float = motorcade_s + GameData.as_float(place.get("ahead"))
		var vehicle: TrafficSim.Vehicle = _convoy[index]
		if s + _convoy_half_length <= _car.s - _keep_behind:
			if vehicle != null:
				_traffic.remove(vehicle)
				_convoy[index] = null
			continue
		if vehicle == null:
			vehicle = _traffic.spawn(_convoy_type, GameData.as_int(place.get("lane")), s, speed)
			if vehicle == null:
				continue
			vehicle.role = MOTORCADE
			_convoy[index] = vehicle
		vehicle.s = s
		vehicle.speed = speed
		vehicle.cruise = speed


## From where to where along the leg the side road's slip lane runs, while it
## is ahead of the car or beside it; Vector2(-1, -1) otherwise.
func slip() -> Vector2:
	var detour: Dictionary = GameData.as_dict(_convoy_plan.get("detour"))
	if kind != "motorcade" or detour.is_empty() or side_road > SIDE_ROAD_OPEN:
		return Vector2(-1.0, -1.0)
	var at: float = GameData.as_float(detour.get("at"))
	return Vector2(at, at + GameData.as_float(detour.get("slip")))


## The cars of the motorcade that are on the road now.
func motorcade() -> Array[TrafficSim.Vehicle]:
	var out: Array[TrafficSim.Vehicle] = []
	for vehicle: TrafficSim.Vehicle in _convoy:
		if vehicle != null:
			out.append(vehicle)
	return out


## The side road (GDD 9.3): a slip lane opens on the right at `at`; a car in
## it where it ends is on a Two-lane road for `length` metres and rejoins
## ahead of the motorcade.
func _step_side_road() -> void:
	var detour: Dictionary = GameData.as_dict(_convoy_plan.get("detour"))
	if detour.is_empty():
		return
	var at: float = GameData.as_float(detour.get("at"))
	var gore: float = at + GameData.as_float(detour.get("slip"))
	var end: float = gore + GameData.as_float(detour.get("length"))
	match side_road:
		SIDE_ROAD_AHEAD:
			if _car.s >= at:
				side_road = SIDE_ROAD_OPEN
				_car.set_road(_main_lanes + 1, _main_divided)
				road_changed = true
		SIDE_ROAD_OPEN:
			if _car.s < gore:
				return
			road_changed = true
			if _car.lane_of(_car.x) < _main_lanes:
				# He stayed on the main road: the slip lane is behind him.
				side_road = SIDE_ROAD_BEHIND
				_car.set_road(_main_lanes, _main_divided)
				return
			side_road = SIDE_ROAD_TAKEN
			var across: float = _car.x - _car.lane_center(_main_lanes)
			_car.set_road(GameData.as_int(detour.get("lanes"), 1), GameData.as_bool(detour.get("divided")))
			_car.x = _car.lane_center(0) + across
			_traffic.remove_all()
			_convoy = []
			_leg.enter_side_road(GameData.as_array(detour.get("spawns")), gore)
		SIDE_ROAD_TAKEN:
			if _car.s < end:
				return
			side_road = SIDE_ROAD_BEHIND
			road_changed = true
			var across: float = _car.x - _car.lane_center(0)
			_car.set_road(_main_lanes, _main_divided)
			var room: float = (_car.lane_width() - _tuning.f("car_width")) * 0.5
			_car.x = _car.lane_center(_main_lanes - 1) + clampf(across, -room, room)
			_traffic.remove_all()
			_leg.leave_side_road()
			# The side road rejoins ahead of the motorcade, however long he took.
			motorcade_s = minf(motorcade_s, _car.s - GameData.as_float(_special.get("rejoin_behind_m")) - _convoy_longest)
