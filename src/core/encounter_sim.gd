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
## He was cut off (the Tailgater's stab at the brake in front of him).
var cut_off: bool = false

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
## Where the car has been: s and x, a sample every half metre, for whoever
## drives in his tracks.
var _trail_s: PackedFloat64Array = PackedFloat64Array()
var _trail_x: PackedFloat64Array = PackedFloat64Array()


func configure(data: GameData, car: CarSim, traffic: TrafficSim) -> void:
	_data = data
	_tuning = data.tuning
	_car = car
	_traffic = traffic
	_car_half_length = _tuning.f("car_length") * 0.5


## Starts the encounter of the plan's leg type, if it has one.
func begin(plan: Dictionary) -> void:
	var leg: Dictionary = _data.record("legs", GameData.as_string(plan.get("leg")))
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
	begin_tick()


func stop() -> void:
	kind = ""
	active = false
	police_lights = false


func begin_tick() -> void:
	watch_began = false
	watch_ended = false
	nerves_rate = 0.0
	cut_off = false


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
		nerves_rate += GameData.as_float(_special.get("nerves_per_s"))
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
