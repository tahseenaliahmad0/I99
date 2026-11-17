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
## The car's tracks are kept this far back, a sample every TRAIL_STEP metres.
const TRAIL_LENGTH: float = 150.0
const TRAIL_STEP: float = 0.5

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

# --- What happened this tick -------------------------------------------------
## Suspicion starts or ends.
var watch_began: bool = false
var watch_ended: bool = false
## Nerves per second the encounter adds this tick.
var nerves_rate: float = 0.0

var _data: GameData
var _tuning: Tuning
var _car: CarSim
var _traffic: TrafficSim
var _special: Dictionary = {}
var _police: TrafficSim.Vehicle = null
var _car_half_length: float = 0.0
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


func step(dt: float) -> void:
	if kind.is_empty():
		return
	time += dt
	_record_trail()
	if kind == "patrol":
		_step_patrol()


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
