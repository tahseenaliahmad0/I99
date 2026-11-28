class_name LegSim
extends RefCounted
## Runs one leg from its plan (GDD 9): puts the plan's traffic on the road as
## the player gets near, bends the road and blows the gusts, keeps the cones,
## potholes, sheep and melons, and knows when the leg is over.
##
## The plan comes from LegGenerator. Vehicles appear when the player passes
## their trigger, `ahead` metres in front of him, so a slow driver meets the
## same traffic later, not different traffic. DriveSim calls the four steps
## in the order of GDD 13.3:
##   step_road      before the car moves: the bend, gusts and their tells
##   step_traffic   spawns, planned lane changes, sheep and melons on the move
##   step_hazards   what the car ran over this tick
##   step_progress  the end of the leg

const KMH_TO_MS: float = 1.0 / 3.6

## Something lying, standing or rolling on the road that lights no lamp.
class Hazard:
	extends RefCounted
	var kind: StringName = &""
	var s: float = 0.0
	var x: float = 0.0
	var half_width: float = 0.0
	var half_length: float = 0.0
	var nerves: float = 0.0
	var suspicion: float = 0.0
	## Share of his speed a pothole takes (0 for the rest).
	var speed_loss: float = 0.0
	var pothole: bool = false
	## Sideways speed in m/s (sheep walk, melons roll).
	var drift: float = 0.0
	## Knocked over or run through: it does nothing more.
	var hit: bool = false
	## Off the road: no longer drawn or checked.
	var gone: bool = false


var plan: Dictionary = {}
## True from begin() until the car passes the end of the leg.
var active: bool = false
var finished: bool = false
## Seconds since the leg began.
var time: float = 0.0
var leg_id: String = ""
var length: float = 0.0
var par: float = 0.0
var raining: bool = false
var night: bool = false
## Dust haze (GDD 9.4): how fast the windscreen clouds with the window open,
## and how far he can see (INF: no dust).
var dust_rate: float = 0.0
var dust_visibility: float = INF
## What one sweep of the wipers smears across the glass (the Storm), as a
## share of the windscreen.
var wipe_haze: float = 0.0
## How hard this road's gusts push, in m/s.
var gust_push: float = 0.0
## Curve strength now: k of GDD 5.4, signed (+ pushes toward the right shoulder).
var curve_k: float = 0.0
## Seconds until the gust that has been announced (0: none announced).
var gust_tell_left: float = 0.0
var gust_tell_dir: int = 0

## Cones, potholes and everything else that stays where it is, by s.
var hazards: Array[Hazard] = []
## Sheep and melons.
var movers: Array[Hazard] = []

# --- What happened this tick -------------------------------------------------
## +1 or -1 in the tick a gust begins.
var gust_started: int = 0
var hazard_nerves: float = 0.0
var hazard_suspicion: float = 0.0
## The car's speed is multiplied by this (a pothole).
var speed_factor: float = 1.0
var hits: Array[StringName] = []
var events: Array[Dictionary] = []

var _data: GameData
var _car: CarSim
var _traffic: TrafficSim
var _par_ms: float = 0.0
var _curve_ramp: float = 0.0
var _gust_tell: float = 0.0
var _signal_time: float = 0.0
var _late_signal_time: float = 0.0
var _spawn_gap: float = 0.0
var _despawn_behind: float = 0.0
var _pothole_cooldown: float = 0.0
var _car_half_length: float = 0.0

var _spawns: Array = []
var _next_spawn: int = 0
## Spawns whose place was taken when they were due: tried again each tick.
var _waiting: Array[Dictionary] = []
## Vehicles with a lane change still to come: [vehicle, to lane, gap, late].
var _changers: Array[Array] = []
var _curves: Array = []
## The stretches that lean (D-074), and whether the plan says how its road
## leans at all (a plan made by hand may not: DriveSim.road_camber).
var _cambers: Array = []
var says_camber: bool = false
var _camber_ramp: float = 0.0
var _gusts: Array = []
var _next_gust: int = 0
var _first_hazard: int = 0
var _pothole_wait: float = 0.0
var _flock: Dictionary = {}
var _flock_started: bool = false
var _melons: Dictionary = {}
var _melon_truck: TrafficSim.Vehicle = null
var _shed_left: float = -1.0
var _shed_wait: float = 0.0
## True while the car is on a side road (the Motorcade's detour): the main
## road's traffic, hazards, bends and gusts are not his then.
var on_side_road: bool = false
var _main_spawns: Array = []
var _main_next: int = 0
## Where the slip lane of a side road opens, or -1.
var _side_road_at: float = -1.0
## What a wedding car's honk does to his Nerves (the modifier's honk_nerves).
var _wedding_honk: float = 0.0

# --- A Twist (GDD 11.3) --------------------------------------------------------
## The plan's "twist" ({} for none): a stretch a guest throws into the story.
var twist: Dictionary = {}
## False until the heckle has been heard (HeckleDirector, by DriveSim): what
## belongs to the Twist is not on the road before that, and nothing shows it.
var twist_live: bool = true
## Seconds of a shower that are left (a Twist: "a 20 s shower"); 0 for none.
var shower_left: float = 0.0
## True in the tick the rain began or stopped in the middle of a leg.
var weather_changed: bool = false
var _twist_role: StringName = &""
var _twist_flock: bool = false
## The Twist's vehicles whose trigger the car passed before it was live.
var _held: Array[Dictionary] = []


func configure(data: GameData, car: CarSim, traffic: TrafficSim) -> void:
	_data = data
	_car = car
	_traffic = traffic
	var tuning: Tuning = data.tuning
	_par_ms = tuning.fi("gear_speeds", 2) * KMH_TO_MS
	_curve_ramp = tuning.f("curve_ramp")
	_camber_ramp = tuning.f("camber_ramp_m")
	_gust_tell = tuning.f("gust_tell")
	_signal_time = tuning.f("signal_time")
	_late_signal_time = tuning.f("late_signal_time")
	_spawn_gap = tuning.f("spawn_clearance")
	_despawn_behind = tuning.f("despawn_behind")
	_pothole_cooldown = tuning.f("pothole_cooldown")
	_car_half_length = tuning.f("car_length") * 0.5


## Starts a leg. The road, the car and the traffic are set up by DriveSim.
func begin(leg_plan: Dictionary) -> void:
	plan = leg_plan
	active = true
	finished = false
	time = 0.0
	leg_id = GameData.as_string(plan.get("leg"))
	length = GameData.as_float(plan.get("length"))
	par = GameData.as_float(plan.get("par_s"))
	var condition: String = GameData.as_string(plan.get("condition"))
	raining = condition == "rain"
	night = condition == "night"
	# A plan may bring its own weather (a boss); a modifier brings its own.
	dust_rate = GameData.as_float(plan.get("window_haze_per_s"))
	dust_visibility = INF
	wipe_haze = GameData.as_float(plan.get("wipe_haze"))
	gust_push = GameData.as_float(plan.get("gust_push"), _data.tuning.f("gust_push"))
	_wedding_honk = 0.0
	var modifier_id: String = GameData.as_string(plan.get("modifier"))
	if not modifier_id.is_empty():
		var modifier: Dictionary = _data.record("modifiers", modifier_id)
		_wedding_honk = GameData.as_float(modifier.get("honk_nerves"))
		dust_rate = GameData.as_float(modifier.get("haze_per_s"), dust_rate)
		if modifier.has("visibility_m"):
			dust_visibility = GameData.as_float(modifier.get("visibility_m"))
	twist = GameData.as_dict(plan.get("twist"))
	twist_live = twist.is_empty()
	shower_left = 0.0
	_held = []
	var twist_id: String = GameData.as_string(twist.get("modifier"))
	_twist_role = StringName(GameData.as_string(LegGenerator.TWIST_ROLES.get(twist_id)))
	_twist_flock = twist_id == "sheep"
	if not twist_id.is_empty() and _data.record("modifiers", twist_id).has("honk_nerves"):
		_wedding_honk = GameData.as_float(_data.record("modifiers", twist_id).get("honk_nerves"))
	curve_k = 0.0
	gust_tell_left = 0.0
	gust_tell_dir = 0
	_spawns = GameData.as_array(plan.get("spawns"))
	_next_spawn = 0
	_waiting = []
	_changers = []
	_curves = GameData.as_array(plan.get("curves"))
	says_camber = plan.has("cambers")
	_cambers = GameData.as_array(plan.get("cambers"))
	_gusts = GameData.as_array(plan.get("gusts"))
	_next_gust = 0
	_first_hazard = 0
	_pothole_wait = 0.0
	hazards = []
	movers = []
	for entry: Variant in GameData.as_array(plan.get("hazards")):
		var record: Dictionary = GameData.as_dict(entry)
		hazards.append(_make_hazard(GameData.as_string(record.get("kind")), GameData.as_float(record.get("s")), GameData.as_float(record.get("x"))))
	_flock = GameData.as_dict(plan.get("flock"))
	_flock_started = false
	if not (_twist_flock and not twist_live):
		_stand_the_flock()
	_melons = GameData.as_dict(plan.get("melons"))
	_melon_truck = null
	_shed_left = -1.0
	_shed_wait = 0.0
	on_side_road = false
	_main_spawns = []
	_main_next = 0
	_side_road_at = -1.0
	var detour: Dictionary = GameData.as_dict(GameData.as_dict(plan.get("motorcade")).get("detour"))
	if not detour.is_empty():
		_side_road_at = GameData.as_float(detour.get("at"))
	begin_tick()


func stop() -> void:
	active = false


## The sheep, where they stand before they walk.
func _stand_the_flock() -> void:
	for x: Variant in GameData.as_array(_flock.get("xs")):
		movers.append(_make_hazard(GameData.as_string(_flock.get("kind")), GameData.as_float(_flock.get("s")), GameData.as_float(x)))


## The heckle has been heard (GDD 11.3): from now the Twist is on the road.
## Its sheep stand where they wait; its vehicles appear as their triggers
## come, and those whose trigger is behind the car where the plan has them
## by now.
func twist_begins() -> void:
	if twist_live:
		return
	twist_live = true
	if _twist_flock:
		_stand_the_flock()
	for spawn: Dictionary in _held:
		_waiting.append(spawn)
	_held = []


## A shower begins (a Twist): it rains for `seconds` of the road's time.
func begin_shower(seconds: float) -> void:
	shower_left = maxf(seconds, 0.0)
	var rains: bool = shower_left > 0.0 or GameData.as_string(plan.get("condition")) == "rain"
	weather_changed = weather_changed or rains != raining
	raining = rains


## Clears what happened last tick.
func begin_tick() -> void:
	weather_changed = false
	gust_started = 0
	hazard_nerves = 0.0
	hazard_suspicion = 0.0
	speed_factor = 1.0
	hits = []
	events = []


func _make_hazard(kind: String, s: float, x: float) -> Hazard:
	var record: Dictionary = _data.record("hazard_kinds", kind)
	var hazard: Hazard = Hazard.new()
	hazard.kind = StringName(kind)
	hazard.s = s
	hazard.x = x
	hazard.half_width = GameData.as_float(record.get("width")) * 0.5
	hazard.half_length = GameData.as_float(record.get("length")) * 0.5
	hazard.nerves = GameData.as_float(record.get("nerves"))
	hazard.suspicion = GameData.as_float(record.get("suspicion"))
	hazard.speed_loss = GameData.as_float(record.get("speed_loss"))
	hazard.pothole = GameData.as_string(record.get("class")) == "pothole"
	return hazard


## Puts the leg where it is when the car has come to `s` after `seconds`
## (a Telling loaded from a save stands at the leg's stall): what the road
## held before that point is behind him and is not put back.
func fast_forward(s: float, seconds: float) -> void:
	time = seconds
	while _next_spawn < _spawns.size() and GameData.as_float(GameData.as_dict(_spawns[_next_spawn]).get("trigger_s")) <= s:
		_next_spawn += 1
	while _next_gust < _gusts.size() and GameData.as_float(GameData.as_dict(_gusts[_next_gust]).get("s")) - _gust_tell * _par_ms <= s:
		_next_gust += 1
	_waiting = []
	_held = []
	twist_live = true
	shower_left = 0.0
	raining = GameData.as_string(plan.get("condition")) == "rain"
	_changers = []
	movers = []
	_flock_started = true
	_melon_truck = null
	_shed_left = -1.0
	gust_tell_left = 0.0
	gust_tell_dir = 0


# --- Side roads --------------------------------------------------------------

## The car has left the main road for a side road that begins at `offset`
## metres into the leg: from here the side road's own traffic is spawned.
func enter_side_road(spawns: Array, offset: float) -> void:
	_main_spawns = _spawns
	_main_next = _next_spawn
	_spawns = []
	for entry: Variant in spawns:
		var spawn: Dictionary = GameData.as_dict(entry).duplicate()
		spawn["trigger_s"] = GameData.as_float(spawn.get("trigger_s")) + offset
		_spawns.append(spawn)
	_next_spawn = 0
	_waiting = []
	_changers = []
	# A gust that was announced on the main road blows there, not here.
	gust_tell_left = 0.0
	gust_tell_dir = 0
	on_side_road = true


## The car is back on the main road.
func leave_side_road() -> void:
	if not on_side_road:
		return
	_spawns = _main_spawns
	_next_spawn = _main_next
	# What the main road would have put in front of him meanwhile is not there.
	while _next_spawn < _spawns.size() and GameData.as_float(GameData.as_dict(_spawns[_next_spawn]).get("trigger_s")) <= _car.s:
		_next_spawn += 1
	_waiting = []
	_changers = []
	# Nor are the gusts he was not there for.
	while _next_gust < _gusts.size() and GameData.as_float(GameData.as_dict(_gusts[_next_gust]).get("s")) - _gust_tell * _par_ms <= _car.s:
		_next_gust += 1
	on_side_road = false


# --- 1. The road: bends and gusts --------------------------------------------

## Before the car moves: the leg's clock, the bend under the car, and gusts.
## A gust is announced when the car is gust_tell seconds short of it at par,
## and blows exactly gust_tell seconds later.
func step_road(dt: float, clock_dt: float = -1.0) -> void:
	if not active:
		curve_k = 0.0
		return
	# The leg's clock is his, not the road's: it does not slow with the road.
	time += clock_dt if clock_dt >= 0.0 else dt
	if on_side_road:
		curve_k = 0.0
		return
	curve_k = curve_at(_car.s)
	if gust_tell_left > 0.0:
		# The tell lasts a whole number of ticks: it is over when less than
		# half a tick of it is left (a bare countdown ran a tick over).
		gust_tell_left -= dt
		if gust_tell_left < dt * 0.5:
			gust_tell_left = 0.0
			gust_started = gust_tell_dir
	if gust_tell_left <= 0.0 and _next_gust < _gusts.size():
		var gust: Dictionary = GameData.as_dict(_gusts[_next_gust])
		if _car.s >= GameData.as_float(gust.get("s")) - _gust_tell * _par_ms:
			_next_gust += 1
			gust_tell_left = _gust_tell
			gust_tell_dir = GameData.as_int(gust.get("dir"))


## How the road leans at `s` (D-074): the share of crown_drift it pushes
## with, + toward the right. A lean comes on and goes off over camber_ramp
## metres; between the leaning stretches the road is flat.
func camber_at(s: float) -> float:
	for entry: Variant in _cambers:
		var stretch: Dictionary = GameData.as_dict(entry)
		var start: float = GameData.as_float(stretch.get("s"))
		var end: float = start + GameData.as_float(stretch.get("length"))
		if s < start or s > end:
			continue
		var ramp: float = 1.0
		if _camber_ramp > 0.0:
			ramp = clampf(minf(s - start, end - s) / _camber_ramp, 0.0, 1.0)
		return GameData.as_float(stretch.get("lean")) * ramp
	return 0.0


## The curve strength at `s`: it comes on and goes off over curve_ramp metres.
func curve_at(s: float) -> float:
	for entry: Variant in _curves:
		var curve: Dictionary = GameData.as_dict(entry)
		var start: float = GameData.as_float(curve.get("s"))
		var end: float = start + GameData.as_float(curve.get("length"))
		if s < start or s > end:
			continue
		var ramp: float = 1.0
		if _curve_ramp > 0.0:
			ramp = clampf(minf(s - start, end - s) / _curve_ramp, 0.0, 1.0)
		return GameData.as_float(curve.get("k")) * ramp
	return 0.0


# --- 2. Traffic --------------------------------------------------------------

## Puts on the road every vehicle whose trigger the car has passed, starts
## the planned lane changes, and moves the sheep and the melons.
func step_traffic(dt: float) -> void:
	if not active:
		return
	var index: int = 0
	while index < _waiting.size():
		if _spawn(_waiting[index], dt):
			_waiting.remove_at(index)
		else:
			index += 1
	while _next_spawn < _spawns.size():
		var spawn: Dictionary = GameData.as_dict(_spawns[_next_spawn])
		if GameData.as_float(spawn.get("trigger_s")) > _car.s:
			break
		_next_spawn += 1
		if not twist_live and _twist_role != &"" and StringName(GameData.as_string(spawn.get("role"))) == _twist_role:
			# A Twist's vehicle, and nobody has said so yet.
			_held.append(spawn)
			continue
		if not _spawn(spawn, dt):
			# Its place is taken: it appears as soon as there is room, ahead of the car as it is then.
			var later: Dictionary = spawn.duplicate()
			later["waited"] = true
			_waiting.append(later)

	index = 0
	while index < _changers.size():
		var entry: Array = _changers[index]
		var vehicle: TrafficSim.Vehicle = entry[0]
		var gap: float = vehicle.s - _car.s
		if not _traffic.vehicles.has(vehicle):
			_changers.remove_at(index)
		elif gap <= GameData.as_float(entry[2]):
			var late: bool = entry[3]
			_traffic.begin_lane_change(vehicle, GameData.as_int(entry[1]), _late_signal_time if late else _signal_time)
			_changers.remove_at(index)
		else:
			index += 1

	_step_flock(dt)
	_step_melons(dt)
	if shower_left > 0.0:
		shower_left -= dt
		if shower_left < dt * 0.5:
			begin_shower(0.0)


## Puts one planned vehicle on the road. False if its place is taken (rule 4:
## nothing appears on top of anything else); it is tried again next tick.
func _spawn(spawn: Dictionary, dt: float) -> bool:
	var type_id: StringName = StringName(GameData.as_string(spawn.get("vehicle")))
	var lane: int = GameData.as_int(spawn.get("lane"))
	if lane == LegGenerator.SHOULDER_LANE:
		lane = _car.lanes
	var direction: int = GameData.as_int(spawn.get("direction"), 1)
	var speed: float = GameData.as_float(spawn.get("speed"))
	var at_s: float = _car.s + GameData.as_float(spawn.get("ahead"))
	if not spawn.has("waited"):
		# It was `ahead` in front when the car crossed its trigger, a moment
		# ago. The traffic moves once more this tick, after it has appeared.
		var trigger: float = GameData.as_float(spawn.get("trigger_s"))
		var since: float = maxf(_car.s - trigger, 0.0) / maxf(_car.speed * KMH_TO_MS, 1.0) - dt
		at_s = trigger + GameData.as_float(spawn.get("ahead")) + float(direction) * speed * KMH_TO_MS * since
	var record: Dictionary = _data.record("vehicles", String(type_id))
	var clearance: float = GameData.as_float(record.get("length")) * 0.5 + _spawn_gap
	if not _traffic.lane_is_free(lane, at_s, clearance, null):
		return false
	# A vehicle that keeps its distance (`apart_m`: the Storm's tail lights)
	# waits while another going its way is that near its place, in any lane.
	var apart: float = GameData.as_float(spawn.get("apart_m"))
	if apart > 0.0 and _traffic.someone_near(at_s, apart, direction):
		return false
	var vehicle: TrafficSim.Vehicle = _traffic.spawn(type_id, lane, at_s, speed, direction)
	if vehicle == null:
		return true
	if GameData.as_int(spawn.get("lane")) == LegGenerator.SHOULDER_LANE:
		vehicle.x = _car.road_right() + (_car.guardrail_x() - _car.road_right()) * 0.5 + _shoulder_inset()
	vehicle.role = StringName(GameData.as_string(spawn.get("role")))
	var change_to: int = GameData.as_int(spawn.get("change_to"), lane)
	if change_to != GameData.as_int(spawn.get("lane")):
		_changers.append([vehicle, change_to, GameData.as_float(spawn.get("change_gap")), GameData.as_bool(spawn.get("late"))])
	if vehicle.role == &"melon_truck":
		_melon_truck = vehicle
	elif vehicle.role == &"wedding":
		# A wedding car's honk is a happy one (GDD 9.4).
		vehicle.honk_nerves = _wedding_honk
	return true


## The shoulder's centre lies half a rumble strip to the right of the middle
## between the road's edge and the guardrail.
func _shoulder_inset() -> float:
	return _data.tuning.f("rumble_strip_width") * 0.5


## The flock (GDD 9.4) starts to walk when the car passes its start point.
func _step_flock(dt: float) -> void:
	if _flock.is_empty():
		return
	if not _flock_started and (twist_live or not _twist_flock) and _car.s >= GameData.as_float(_flock.get("start_s")):
		_flock_started = true
		for sheep: Hazard in movers:
			if sheep.kind == &"sheep":
				sheep.drift = GameData.as_float(_flock.get("speed"))
	_move(dt)


## The melon truck (GDD 9.4) sheds one melon every every_s for shed_s once
## the car is within shed_gap of it. Melons roll toward the right shoulder.
func _step_melons(dt: float) -> void:
	if _melons.is_empty():
		return
	if _melon_truck != null and _shed_left < 0.0 and _traffic.vehicles.has(_melon_truck):
		if _melon_truck.s - _car.s <= GameData.as_float(_melons.get("shed_gap")):
			_shed_left = GameData.as_float(_melons.get("shed_s"))
			_shed_wait = 0.0
	if _shed_left > 0.0 and _melon_truck != null and _traffic.vehicles.has(_melon_truck):
		_shed_left -= dt
		_shed_wait -= dt
		if _shed_wait <= 0.0:
			_shed_wait += GameData.as_float(_melons.get("every_s"))
			var melon: Hazard = _make_hazard(GameData.as_string(_melons.get("kind")),
					_melon_truck.s - _melon_truck.half_length, _melon_truck.x)
			melon.drift = GameData.as_float(_melons.get("roll_ms"))
			movers.append(melon)
		if _shed_left <= 0.0:
			_shed_left = 0.0
	if _flock.is_empty():
		_move(dt)


## Moves sheep and melons sideways. Past the guardrail, or far behind the
## car, they are gone.
func _move(dt: float) -> void:
	var rail: float = _car.guardrail_x()
	var index: int = 0
	while index < movers.size():
		var mover: Hazard = movers[index]
		mover.x += mover.drift * dt
		if mover.x - mover.half_width > rail or mover.s < _car.s - _despawn_behind:
			mover.gone = true
			movers.remove_at(index)
		else:
			index += 1


# --- 3. Hazards --------------------------------------------------------------

## What the car ran over this tick (GDD 5.6, 9.4). Cones, melons and sheep
## light no lamp: each adds its Nerves once, and its Suspicion while a police
## car is watching. A pothole adds Nerves and takes a share of his speed.
func step_hazards(dt: float) -> void:
	if not active or on_side_road:
		return
	_pothole_wait = maxf(_pothole_wait - dt, 0.0)
	var car_half_width: float = _car.half_width()
	while _first_hazard < hazards.size() and hazards[_first_hazard].s + hazards[_first_hazard].half_length < _car.s - _car_half_length:
		_first_hazard += 1
	var index: int = _first_hazard
	while index < hazards.size():
		var hazard: Hazard = hazards[index]
		if hazard.s - hazard.half_length > _car.s + _car_half_length:
			break
		_touch(hazard, car_half_width)
		index += 1
	for mover: Hazard in movers:
		# A sheep that has not yet come through the median is not on the road.
		if mover.x + mover.half_width < _car.left_limit_x():
			continue
		if absf(mover.s - _car.s) <= mover.half_length + _car_half_length:
			_touch(mover, car_half_width)


func _touch(hazard: Hazard, car_half_width: float) -> void:
	if absf(hazard.x - _car.x) >= hazard.half_width + car_half_width:
		return
	if hazard.pothole:
		if _pothole_wait > 0.0:
			return
		_pothole_wait = _pothole_cooldown
		speed_factor *= 1.0 - hazard.speed_loss
	elif hazard.hit:
		return
	hazard.hit = true
	hazard_nerves += hazard.nerves
	hazard_suspicion += hazard.suspicion
	hits.append(hazard.kind)


# --- 4. Progress -------------------------------------------------------------

## True in the tick the car passes the end of the leg.
func step_progress() -> bool:
	if not active or _car.s < length:
		return false
	active = false
	finished = true
	return true


# --- For the views -----------------------------------------------------------

## Hazards from `behind` metres behind the car to `ahead` metres in front, as
## small dictionaries with positions relative to the car's s.
func hazards_near(behind: float, ahead: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if on_side_road:
		return out
	for hazard: Hazard in hazards:
		var gap: float = hazard.s - _car.s
		if gap < -behind:
			continue
		if gap > ahead:
			break
		out.append({"kind": hazard.kind, "ahead": gap, "x": hazard.x, "hit": hazard.hit})
	var left: float = _car.left_limit_x()
	for mover: Hazard in movers:
		var gap: float = mover.s - _car.s
		if gap < -behind or gap > ahead or mover.x + mover.half_width < left:
			continue
		out.append({"kind": mover.kind, "ahead": gap, "x": mover.x, "hit": mover.hit})
	return out


## Road signs between the car and `ahead` metres in front: each curve sign
## stands curve_sign_lead seconds before its bend at par, the side road's
## slip_sign_lead seconds before its slip lane.
func signs_near(ahead: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if on_side_road:
		return out
	var lead: float = _data.tuning.f("curve_sign_lead") * _par_ms
	for entry: Variant in _curves:
		var curve: Dictionary = GameData.as_dict(entry)
		var gap: float = GameData.as_float(curve.get("s")) - lead - _car.s
		if gap >= 0.0 and gap <= ahead:
			out.append({"kind": "curve", "ahead": gap, "k": GameData.as_float(curve.get("k"))})
	if _side_road_at >= 0.0:
		# The side road is signed like an Exit: slip_sign_lead seconds ahead.
		var before: float = _side_road_at - _data.tuning.f("slip_sign_lead") * _par_ms - _car.s
		if before >= 0.0 and before <= ahead:
			out.append({"kind": "side_road", "ahead": before})
	return out
