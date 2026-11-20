class_name BossSim
extends RefCounted
## The set piece that ends an act (GDD 10.2 to 10.4): the Checkpoint, the
## Storm, Dawn.
##
## A boss is a stretch of road with a plan, like a leg: BossSim.plan() makes
## it from the boss's record in legs.json, its modifier and a seed, and LegSim
## runs what a plan can say (the vehicles, the gusts). This class keeps the
## rest, by the clock of the road: the dust that thins and thickens, and what
## comes out of it behind a car that stands where it should not. DriveSim
## steps it and reads what it says, tick by tick.

const CHECKPOINT: String = "checkpoint"
const STORM: String = "storm"
const DAWN: String = "dawn"
## The street at the end of the road (GDD 10.5): no boss, but a set piece
## with a plan of its own, kept here with the others.
const ARRIVAL: String = "arrival"
const KMH_TO_MS: float = 1.0 / 3.6
## Keeps the plan's draws apart from the draw of the modifier.
const PLAN_SALT: int = 2
const THIN_SALT: int = 3
const NIGHT: String = "night"
const CORRIDOR: String = "corridor"

## Dawn's three phases (GDD 10.4). `phase` holds these in Dawn and the
## Checkpoint's at the Checkpoint.
const FALSE_DAWN: int = 1
const SUNRISE: int = 2
const THE_CALL: int = 3

## The Call (GDD 10.4): it has not come, it rings, he talks, it is over.
const CALL_NONE: String = ""
const CALL_RINGING: String = "ringing"
const CALL_TALKING: String = "talking"
const CALL_OVER: String = "over"
## How he took it: the phone at his own ear while he drives; held to his ear
## by a passenger; at his ear in a car that stands pulled over.
const TAKEN_ALONE: String = "alone"
const TAKEN_WITH_PASSENGER: String = "passenger"
const TAKEN_PARKED: String = "parked"

## The Checkpoint's phases (GDD 10.2): the queue; the soldier on his way to
## the window; the papers; let through.
const QUEUE: int = 1
const STOW: int = 2
const PAPERS: int = 3
const THROUGH: int = 4
## Vehicles of the queue, and one that has been waved on.
const QUEUE_ROLE: StringName = &"queue"
const WAVED_ON_ROLE: StringName = &"waved_on"

## The boss he is in ("" on any other road) and its modifier ("" for none).
var kind: String = ""
var modifier: String = ""
var active: bool = false
## Seconds of road since the boss began.
var time: float = 0.0

# --- The Storm (GDD 10.3) ----------------------------------------------------
## How far he sees into the dust, in metres (INF outside the Storm).
var visibility: float = INF
## True in thick dust.
var thick: bool = false
## Seconds until the dust thins or thickens.
var dust_change_in: float = 0.0
## Seconds until what is coming up behind his standing car reaches it
## (0: nothing is coming). Its lights in the mirror and its horn are the tell.
var rear_end_in: float = 0.0

# --- Dawn (GDD 10.4) ---------------------------------------------------------
## FALSE_DAWN, SUNRISE or THE_CALL (0 on any other road).
var phase: int = 0
## The low sun on his view, 0 to 1, before his visor and what he wears.
var glare: float = 0.0
## Where across his view the sun is, and the glow of the false dawn (burning
## gas from the oil fields): -1 the far left, 0 dead ahead, 1 the far right.
var sun_side: float = 0.0
var glow_side: float = 0.0
## How much of that glow there is, 0 to 1: all of it all through Dawn.
var glow: float = 0.0


## Where the sun stands in his view, in degrees to the right of dead ahead
## and above the horizon: `side_deg` to the side at sun_side 1, and from
## `rise_from` up to `rise_to` as its Glare comes on. One place for the
## disc in the sky and for the light that washes the glass.
func sun_position(side_deg: float, rise_from: float, rise_to: float) -> Vector2:
	var risen: float = clampf(glare / _glare_full, 0.0, 1.0) if _glare_full > 0.0 else 1.0
	return Vector2(sun_side * side_deg, lerpf(rise_from, rise_to, risen))
## The Call: CALL_NONE, CALL_RINGING, CALL_TALKING or CALL_OVER; the seconds
## left of the ring or of the talk; how it was taken; whether it was.
var call: String = CALL_NONE
var call_left: float = 0.0
var call_taken: String = ""
var call_answered: bool = false
## The share of the pointer's motion that steers while the phone is at his
## ear in his own hand.
var wrist_steer: float = 1.0

# --- The Checkpoint (GDD 10.2) -----------------------------------------------
## Where the bar is along the road (0 on any other road), and whether it is up.
var bar_at: float = 0.0
var released: bool = false
## Seconds until the soldier is at his window (the Stow phase).
var stow_left: float = 0.0
## The document the soldier's sign asks for now ("" when it asks for none),
## and the seconds since that sign went up.
var wanted: String = ""
var delay: float = 0.0

# --- The Arrival (GDD 10.5) --------------------------------------------------
## Where the marked bay begins and ends along the street (both 0 elsewhere).
var bay_from: float = 0.0
var bay_to: float = 0.0
## He stands in the bay: the key can be turned.
var in_bay: bool = false

# --- What happened this tick -------------------------------------------------
## Something has come out of the dust behind him: it will hit him.
var rear_end_tell: bool = false
## It hit him.
var rear_end: bool = false
## The phone began to ring; it rang out unanswered; the talk ended.
var call_began: bool = false
var call_missed: bool = false
var call_ended: bool = false
## He came to the last checkpoint's barriers too fast: he is stopped and
## searched.
var searched: bool = false
## He ran into the end of the street at this speed, km/h (0: he did not).
var wall_speed: float = 0.0
## He ran into the lowered bar at this speed, km/h (0: he did not).
var bar_speed: float = 0.0
## The soldier has reached his window: what he sees is counted now.
var stow_ended: bool = false
## A sign went up (the first, or the next document of a thorough check).
var asked: bool = false
## One more delay_every_s has gone by with the sign up.
var delayed: bool = false
## Every document asked for has been handed over.
var papers_done: bool = false

var _data: GameData
var _car: CarSim
var _rng: Rng
var _traffic: TrafficSim
var _thin_s: float = 0.0
var _thin_m: float = 0.0
var _thick_s: float = 0.0
var _thick_m: float = 0.0
var _stopped_kmh: float = 0.0
var _rear_end_every: float = 0.0
var _rear_end_tell: float = 0.0
var _rear_end_chance: float = 0.0
## Seconds he has stood where he is not safe, since the last time something
## could have come.
var _stood: float = 0.0
## The draw for this wait has been made; and it came up a hit.
var _drawn: bool = false
var _coming: bool = false
var _length: float = 0.0
## A checkpoint's corridor (GDD 10.2, 10.4): where its barriers begin to
## close in, where they are corridor_gap apart, and where they end.
var _corridor_from: float = 0.0
var _corridor_at: float = 0.0
var _corridor_to: float = 0.0
var _corridor_half_gap: float = 0.0
var _corridor_max_kmh: float = INF
var _corridor_sign_at: float = -1.0
var _corridor_judged: bool = false
var _sunrise_at: float = 0.0
var _glare_from: float = 0.0
var _glare_full: float = 0.0
var _glare_ramp: float = 0.0
var _call_at: float = 0.0
var _ring_s: float = 0.0
var _talk_s: float = 0.0
var _bump_kmh: float = 0.0
## The Checkpoint's queue: for each lane the vehicles still waiting, the one
## at the bar first; the seconds that one has been served; and the vehicle
## last waved on, until it is gone.
var _queue: Array[Array] = []
var _served: PackedFloat64Array = PackedFloat64Array()
var _waved_on: Array[TrafficSim.Vehicle] = []
## How fast each of those is by now, km/h (TrafficSim sets a vehicle's own
## speed to its cruise every tick, and theirs is 0 for it).
var _waved_speed: PackedFloat64Array = PackedFloat64Array()
var _queue_plan: Array = []
var _queue_gap: float = 0.0
var _creep_ms: float = 0.0
var _pull_up_rate: float = 0.0
var _serve_s: float = 0.0
var _leave_kmh: float = 0.0
var _queue_clear: float = 0.0
var _settle_m: float = 0.0
var _leave_accel: float = 0.0
var _stop_zone: float = 0.0
var _stow_s: float = 0.0
var _delay_every: float = 0.0
## The documents the soldier will ask for, in order; those still to come; and
## how many delays have been counted against the sign that is up.
var _documents_plan: Array = []
var _documents: Array[String] = []
var _delays: int = 0


func configure(data: GameData, car: CarSim, rng: Rng, traffic: TrafficSim) -> void:
	_data = data
	_car = car
	_rng = rng
	_traffic = traffic


# --- The plan ----------------------------------------------------------------

## The road of a boss: a plan as LegSim runs it, with what belongs to the
## boss besides. The same boss, modifier and seed give the same plan. A
## modifier that is not one of the boss's own is left out.
static func plan(data: GameData, boss_id: String, modifier_id: String, boss_seed: int) -> Dictionary:
	var record: Dictionary = data.record("bosses", boss_id)
	var modifier: Dictionary = {}
	if not modifier_id.is_empty() and GameData.as_array(record.get("modifiers")).has(modifier_id):
		modifier = data.record("boss_modifiers", modifier_id)
	var out: Dictionary = RunGenerator.blank_plan(GameData.as_int(record.get("act"), 1),
			GameData.as_int(record.get("lanes"), RunGenerator.ROAD_LANES), GameData.as_bool(record.get("divided"), true),
			GameData.as_float(record.get("length_m")), GameData.as_float(record.get("par_s")))
	out["boss"] = boss_id
	out["boss_modifier"] = GameData.as_string(modifier.get("id"))
	out["seed"] = boss_seed
	var random: RandomNumberGenerator = Rng.seeded(Rng.derive(boss_seed, PLAN_SALT))
	match boss_id:
		CHECKPOINT:
			_plan_checkpoint(out, GameData.as_dict(record.get("checkpoint")), modifier, random)
		STORM:
			_plan_storm(data, out, GameData.as_dict(record.get("storm")), modifier, random)
		DAWN:
			_plan_dawn(data, out, GameData.as_dict(record.get("dawn")), modifier, boss_seed)
	return out


## The Checkpoint's plan (GDD 10.2): which vehicles stand in each lane's
## queue, the one at the bar first (half as many again in a Long queue), and
## which documents the soldier will ask for (two when he is Thorough, never
## the same one twice).
static func _plan_checkpoint(out: Dictionary, checkpoint: Dictionary, modifier: Dictionary, random: RandomNumberGenerator) -> void:
	var queue: Dictionary = GameData.as_dict(checkpoint.get("queue"))
	var types: Array = GameData.as_array(queue.get("vehicles"))
	var cars: int = roundi(GameData.as_float(queue.get("cars")) * GameData.as_float(modifier.get("queue_mult"), 1.0))
	var lines: Array = []
	for _lane: int in GameData.as_int(out.get("lanes")):
		var line: Array = []
		for _index: int in cars:
			if not types.is_empty():
				line.append(GameData.as_string(types[random.randi_range(0, types.size() - 1)]))
		lines.append(line)
	out["queue"] = lines
	var left: Array = GameData.as_array(checkpoint.get("documents")).duplicate()
	var asks: Array = []
	for _index: int in GameData.as_int(modifier.get("documents"), 1):
		if left.is_empty():
			break
		var pick: int = random.randi_range(0, left.size() - 1)
		asks.append(GameData.as_string(left[pick]))
		left.remove_at(pick)
	out["documents"] = asks


## The street of the Arrival (GDD 10.5): nothing on it but the bay at its end.
static func arrival_plan(data: GameData, act: int) -> Dictionary:
	var street: Dictionary = GameData.as_dict(data.root("legs").get("arrival"))
	var out: Dictionary = RunGenerator.blank_plan(act, GameData.as_int(street.get("lanes"), 1),
			GameData.as_bool(street.get("divided")), GameData.as_float(street.get("length_m")))
	out["boss"] = ARRIVAL
	out["heavy_floor"] = GameData.as_float(street.get("heavy_floor"))
	return out


## Dawn's road (GDD 10.4): rush traffic laid out as a leg's is, by the same
## generator and under the same rules, around the stretch the last
## checkpoint takes; then thinned toward the start, so that it builds: of
## what the generator put before sunrise, `builds_from` stays at the very
## start and all of it at sunrise.
static func _plan_dawn(data: GameData, out: Dictionary, dawn: Dictionary, modifier: Dictionary, boss_seed: int) -> void:
	var check: Dictionary = GameData.as_dict(dawn.get("checkpoint"))
	var road: Dictionary = GameData.as_dict(dawn.get("road")).duplicate(true)
	road["id"] = DAWN
	road["lanes"] = GameData.as_int(out.get("lanes"))
	road["divided"] = GameData.as_bool(out.get("divided"))
	road["condition"] = "clear"
	road["par_s"] = GameData.as_float(out.get("par_s"))
	road["length_m"] = GameData.as_float(out.get("length"))
	road["density_mult"] = GameData.as_float(modifier.get("traffic_mult"), 1.0)
	var taper: float = GameData.as_float(check.get("taper_m"))
	var zone: Dictionary = {
		"kind": CORRIDOR,
		"s": GameData.as_float(check.get("at_m")) - taper,
		"length": taper + GameData.as_float(check.get("length_m")),
		"lane": GameData.as_int(out.get("lanes")) / 2,
	}
	var made: Dictionary = LegGenerator.generate_road(data, road, GameData.as_int(out.get("act")), Rng.derive(boss_seed, PLAN_SALT), [zone])
	for key: String in ["beats_end", "start_lane", "attempts", "sparse", "beats", "hazards", "curves", "gusts", "zones", "path"]:
		out[key] = made[key]
	var random: RandomNumberGenerator = Rng.seeded(Rng.derive(boss_seed, THIN_SALT))
	var sunrise: float = GameData.as_float(dawn.get("sunrise_at_m"))
	var from: float = GameData.as_float(road.get("builds_from"), 1.0)
	var spawns: Array = []
	for entry: Variant in GameData.as_array(made.get("spawns")):
		var spawn: Dictionary = GameData.as_dict(entry)
		var met: float = GameData.as_float(spawn.get("meet_s"))
		var at: float = met if met >= 0.0 else GameData.as_float(spawn.get("trigger_s")) + GameData.as_float(spawn.get("ahead"))
		# The draw is made for every vehicle, so one does not shift the next.
		var roll: float = random.randf()
		if at >= sunrise or roll < lerpf(from, 1.0, clampf(at / sunrise, 0.0, 1.0)):
			spawns.append(spawn)
	out["spawns"] = spawns
	out["heavy_floor"] = GameData.as_float(dawn.get("heavy_floor"))
	if GameData.as_int(modifier.get("glare_from_phase"), SUNRISE) <= FALSE_DAWN:
		out["early_sun"] = true


## The Storm's road: a gust every gust_every_s at par, from either side, and
## tail lights to follow, one vehicle at a time and never two in a row in
## one lane.
static func _plan_storm(data: GameData, out: Dictionary, storm: Dictionary, modifier: Dictionary, random: RandomNumberGenerator) -> void:
	var tuning: Tuning = data.tuning
	var length: float = GameData.as_float(out.get("length"))
	var lanes: int = GameData.as_int(out.get("lanes"))
	var par_ms: float = tuning.fi("gear_speeds", 2) * KMH_TO_MS
	if GameData.as_bool(modifier.get("night")):
		out["condition"] = NIGHT
	out["gust_push"] = GameData.as_float(storm.get("gust_push")) * GameData.as_float(modifier.get("gust_mult"), 1.0)
	out["wipe_haze"] = GameData.as_float(storm.get("wipe_haze"))
	out["window_haze_per_s"] = GameData.as_float(storm.get("window_haze_per_s"))

	var gusts: Array = []
	var every: float = GameData.as_float(storm.get("gust_every_s")) * par_ms
	var at: float = every
	while every > 0.0 and at < length:
		gusts.append({"s": snappedf(at, 0.01), "dir": 1 if random.randf() < 0.5 else -1})
		at += every
	out["gusts"] = gusts

	var lights: Dictionary = GameData.as_dict(storm.get("tail_lights"))
	var types: Array = GameData.as_array(lights.get("vehicles"))
	var gaps: Array = GameData.as_array(lights.get("gap_m"))
	var speeds: Array = GameData.as_array(lights.get("speed_kmh"))
	var horizon: float = tuning.f("spawn_ahead")
	var spawns: Array = []
	var lane: int = -1
	at = GameData.as_float(lights.get("first_m"))
	while not types.is_empty() and gaps.size() == 2 and speeds.size() == 2 and at < length:
		var next_lane: int = random.randi_range(0, lanes - 1)
		if next_lane == lane:
			next_lane = (next_lane + 1) % lanes
		lane = next_lane
		var trigger: float = maxf(at - horizon, 0.0)
		spawns.append({
			"vehicle": GameData.as_string(types[random.randi_range(0, types.size() - 1)]),
			"lane": lane,
			"speed": snappedf(random.randf_range(GameData.as_float(speeds[0]), GameData.as_float(speeds[1])), 0.1),
			"direction": 1,
			"role": "",
			"change_to": lane,
			"change_gap": 0.0,
			"late": false,
			"trigger_s": snappedf(trigger, 0.01),
			"ahead": snappedf(at - trigger, 0.01),
			"meet_s": -1.0,
		})
		at += random.randf_range(GameData.as_float(gaps[0]), GameData.as_float(gaps[1]))
	out["spawns"] = spawns


# --- The boss ----------------------------------------------------------------

## Starts the boss of the plan, if the plan is one; any other road ends it.
func begin(plan_of_road: Dictionary) -> void:
	stop()
	kind = GameData.as_string(plan_of_road.get("boss"))
	if kind.is_empty():
		return
	modifier = GameData.as_string(plan_of_road.get("boss_modifier"))
	active = true
	_length = GameData.as_float(plan_of_road.get("length"))
	if kind == ARRIVAL:
		var street: Dictionary = GameData.as_dict(_data.root("legs").get("arrival"))
		bay_to = _length
		bay_from = _length - GameData.as_float(street.get("bay_m"))
		_stopped_kmh = GameData.as_float(street.get("stopped_kmh"))
		_bump_kmh = GameData.as_float(street.get("bump_kmh"))
		return
	var record: Dictionary = _data.record("bosses", kind)
	if kind == CHECKPOINT:
		var checkpoint: Dictionary = GameData.as_dict(record.get("checkpoint"))
		var queue: Dictionary = GameData.as_dict(checkpoint.get("queue"))
		_set_corridor(GameData.as_dict(checkpoint.get("corridor")))
		bar_at = _corridor_to
		_queue_gap = GameData.as_float(queue.get("gap_m"))
		_creep_ms = GameData.as_float(queue.get("creep_kmh")) * KMH_TO_MS
		_pull_up_rate = GameData.as_float(queue.get("pull_up_per_s"))
		_serve_s = GameData.as_float(queue.get("serve_s"))
		_leave_kmh = GameData.as_float(queue.get("leave_kmh"))
		_queue_clear = GameData.as_float(queue.get("clear_m"))
		_settle_m = GameData.as_float(queue.get("settle_m"))
		_leave_accel = _data.tuning.f("accel")
		_stop_zone = GameData.as_float(checkpoint.get("stop_zone_m"))
		_stopped_kmh = GameData.as_float(checkpoint.get("stopped_kmh"))
		_bump_kmh = GameData.as_float(checkpoint.get("bump_kmh"))
		_stow_s = GameData.as_float(checkpoint.get("stow_s"))
		_delay_every = GameData.as_float(checkpoint.get("delay_every_s"))
		_queue_plan = GameData.as_array(plan_of_road.get("queue"))
		_documents_plan = GameData.as_array(plan_of_road.get("documents"))
		_begin_queue()
	if kind == DAWN:
		var dawn: Dictionary = GameData.as_dict(record.get("dawn"))
		var check: Dictionary = GameData.as_dict(dawn.get("checkpoint"))
		var ring: Dictionary = GameData.as_dict(dawn.get("call"))
		_set_corridor(check)
		_corridor_max_kmh = GameData.as_float(check.get("max_kmh"))
		_sunrise_at = GameData.as_float(dawn.get("sunrise_at_m"))
		_glare_from = 0.0 if GameData.as_bool(plan_of_road.get("early_sun")) else _sunrise_at
		_glare_full = GameData.as_float(dawn.get("glare"))
		_glare_ramp = GameData.as_float(dawn.get("glare_ramp_m"))
		sun_side = GameData.as_float(dawn.get("sun_side"))
		glow_side = GameData.as_float(dawn.get("glow_side"))
		glow = 1.0
		_call_at = _length - GameData.as_float(ring.get("from_end_m"))
		_ring_s = GameData.as_float(ring.get("ring_s"))
		_talk_s = GameData.as_float(ring.get("talk_s"))
		wrist_steer = GameData.as_float(ring.get("wrist_steer"), 1.0)
		_stopped_kmh = GameData.as_float(ring.get("stopped_kmh"))
		phase = FALSE_DAWN
	if kind == STORM:
		var storm: Dictionary = GameData.as_dict(record.get("storm"))
		_thin_s = GameData.as_float(storm.get("thin_s"))
		_thin_m = GameData.as_float(storm.get("thin_m"))
		_thick_s = GameData.as_float(storm.get("thick_s"))
		_thick_m = GameData.as_float(storm.get("thick_m"))
		_stopped_kmh = GameData.as_float(storm.get("stopped_kmh"))
		_rear_end_every = GameData.as_float(storm.get("rear_end_every_s"))
		_rear_end_tell = GameData.as_float(storm.get("rear_end_tell_s"))
		_rear_end_chance = GameData.as_float(storm.get("rear_end_chance"))
		visibility = _thin_m
		dust_change_in = _thin_s


func stop() -> void:
	kind = ""
	modifier = ""
	active = false
	time = 0.0
	visibility = INF
	thick = false
	dust_change_in = 0.0
	rear_end_in = 0.0
	_stood = 0.0
	_drawn = false
	_coming = false
	phase = 0
	glare = 0.0
	sun_side = 0.0
	glow_side = 0.0
	glow = 0.0
	wrist_steer = 1.0
	call = CALL_NONE
	call_left = 0.0
	call_taken = ""
	call_answered = false
	bay_from = 0.0
	bay_to = 0.0
	in_bay = false
	bar_at = 0.0
	released = false
	stow_left = 0.0
	wanted = ""
	delay = 0.0
	_queue = []
	_served = PackedFloat64Array()
	_waved_on = []
	_waved_speed = PackedFloat64Array()
	_documents = []
	_delays = 0
	_corridor_from = 0.0
	_corridor_at = 0.0
	_corridor_to = 0.0
	_corridor_max_kmh = INF
	_corridor_sign_at = -1.0
	_corridor_judged = false
	begin_tick()


## Clears what happened last tick.
func begin_tick() -> void:
	rear_end_tell = false
	rear_end = false
	call_began = false
	call_missed = false
	call_ended = false
	searched = false
	wall_speed = 0.0
	bar_speed = 0.0
	stow_ended = false
	asked = false
	delayed = false
	papers_done = false


## Before the car moves: the boss's own clock, and what goes by it. `dt` is
## the road's tick, `cabin_dt` his own (what rings in his pocket is his).
## `hazards_on` is the state of his hazard lights.
func step_road(dt: float, cabin_dt: float, hazards_on: bool) -> void:
	if not active:
		return
	time += dt
	if kind == STORM:
		_step_dust(dt)
		_step_standing(dt, hazards_on)
	elif kind == DAWN:
		_step_call(cabin_dt)
	elif kind == CHECKPOINT:
		_step_soldier(cabin_dt)


## After the traffic has moved: the Checkpoint's queue, which this class
## moves itself (stop and go, nose to tail).
func step_traffic(dt: float) -> void:
	if active and kind == CHECKPOINT:
		_step_queue(dt)


## After the car has moved, from `s_then` to where it is now.
func step_after_car(s_then: float) -> void:
	if not active:
		return
	if kind == DAWN:
		phase = THE_CALL if _car.s >= _call_at else (SUNRISE if _car.s >= _sunrise_at else FALSE_DAWN)
		# The sun comes up over glare_ramp_m of road: it is seen before it blinds.
		glare = _glare_full * clampf((_car.s - _glare_from) / maxf(_glare_ramp, 0.001), 0.0, 1.0)
		if call == CALL_NONE and _car.s >= _call_at:
			call = CALL_RINGING
			call_left = _ring_s
			call_began = true
		# The soldiers wave through whoever comes to the barriers at
		# corridor_max_kmh or less (GDD 10.4). Anyone faster is stopped.
		if not _corridor_judged and s_then < _corridor_at and _car.s >= _corridor_at:
			_corridor_judged = true
			searched = _car.speed > _corridor_max_kmh + 0.001
	elif kind == CHECKPOINT:
		var nose: float = _car.length() * 0.5
		if not released and s_then + nose <= bar_at + 0.001 and _car.s + nose > bar_at:
			# The bar is down: it holds him. (A car beyond it already is not held.)
			bar_speed = _car.speed if _car.speed > _bump_kmh else 0.0
			_car.s = bar_at - nose
			_car.speed = 0.0
		if phase == QUEUE and _first_in_line():
			phase = STOW
			stow_left = _stow_s
	elif kind == ARRIVAL:
		var half_length: float = _car.length() * 0.5
		if _car.s + half_length >= _length:
			# The street ends here.
			wall_speed = _car.speed if _car.speed > _bump_kmh else 0.0
			_car.s = _length - half_length
			_car.speed = 0.0
		in_bay = _car.speed <= _stopped_kmh and _car.s - half_length >= bay_from


# --- The Checkpoint ----------------------------------------------------------

## Puts the queue on the road: in each lane its vehicles nose to tail, the
## first at the bar. The phases begin again with it.
func _begin_queue() -> void:
	for line: Array in _queue:
		for waiting: Variant in line:
			var vehicle: TrafficSim.Vehicle = waiting
			_traffic.remove(vehicle)
	for gone: TrafficSim.Vehicle in _waved_on:
		if gone != null:
			_traffic.remove(gone)
	_queue = []
	_waved_on = []
	_waved_speed = PackedFloat64Array()
	_served = PackedFloat64Array()
	for lane: int in _queue_plan.size():
		var line: Array = []
		var nose: float = bar_at
		for type: Variant in GameData.as_array(_queue_plan[lane]):
			var vehicle: TrafficSim.Vehicle = _traffic.spawn(StringName(GameData.as_string(type)), lane, nose, 0.0)
			if vehicle == null:
				continue
			vehicle.s = nose - vehicle.half_length
			vehicle.cruise = 0.0
			vehicle.speed = 0.0
			vehicle.role = QUEUE_ROLE
			# Between barriers nobody can move over for a horn.
			vehicle.yields_to_horn = false
			nose = vehicle.s - vehicle.half_length - _queue_gap
			line.append(vehicle)
		_queue.append(line)
		_served.append(0.0)
		_waved_on.append(null)
		_waved_speed.append(0.0)
	phase = QUEUE
	released = false
	stow_left = 0.0
	wanted = ""
	delay = 0.0
	_delays = 0
	_documents = []
	for document: Variant in _documents_plan:
		_documents.append(GameData.as_string(document))


## One tick of the queue. The vehicle at the bar is served for serve_s and
## waved on; the rest pull up behind it, each at room x pull_up_per_s and
## never faster than creep_kmh. TrafficSim leaves them where they are (their
## cruise is 0): its follow gap would spread the queue out.
func _step_queue(dt: float) -> void:
	for lane: int in _queue.size():
		var line: Array = _queue[lane]
		var nose: float = bar_at
		var gone: TrafficSim.Vehicle = _waved_on[lane]
		if gone != null:
			_waved_speed[lane] = minf(_waved_speed[lane] + _leave_accel * dt, _leave_kmh)
			gone.speed = _waved_speed[lane]
			gone.s += gone.speed * KMH_TO_MS * dt
			gone.cruise = 0.0
			if gone.s - gone.half_length < bar_at + _queue_clear:
				# Not yet clear of the bar: the next one waits behind it.
				nose = minf(nose, gone.s - gone.half_length - _queue_gap)
			elif gone.s - gone.half_length > _length:
				_traffic.remove(gone)
				_waved_on[lane] = null
		for waiting: Variant in line:
			var vehicle: TrafficSim.Vehicle = waiting
			var room: float = nose - vehicle.half_length - vehicle.s
			var speed_ms: float = clampf(room * _pull_up_rate, 0.0, _creep_ms)
			vehicle.s += minf(speed_ms * dt, maxf(room, 0.0))
			vehicle.speed = speed_ms / KMH_TO_MS
			vehicle.cruise = 0.0
			nose = vehicle.s - vehicle.half_length - _queue_gap
		if line.is_empty():
			continue
		var first: TrafficSim.Vehicle = line[0]
		if bar_at - (first.s + first.half_length) > _settle_m:
			continue
		_served[lane] += dt
		if _served[lane] >= _serve_s - dt * 0.5:
			_served[lane] = 0.0
			line.remove_at(0)
			first.role = WAVED_ON_ROLE
			if _waved_on[lane] != null:
				_traffic.remove(_waved_on[lane])
			_waved_on[lane] = first
			_waved_speed[lane] = 0.0


## True when nothing of the queue is left ahead of him in his lane and he
## stands within stop_zone_m of the bar.
func _first_in_line() -> bool:
	var lane: int = clampi(_car.lane_of(_car.x), 0, _car.lanes - 1)
	if lane >= _queue.size() or not _queue[lane].is_empty():
		return false
	var gone: TrafficSim.Vehicle = _waved_on[lane]
	if gone != null and gone.s - gone.half_length < bar_at + _queue_clear:
		return false
	var nose: float = _car.s + _car.length() * 0.5
	return _car.speed <= _stopped_kmh and nose <= bar_at + 0.001 and bar_at - nose <= _stop_zone


## The vehicles still waiting in a lane's queue (for the views and the tests).
func queue_length(lane: int) -> int:
	return _queue[lane].size() if lane >= 0 and lane < _queue.size() else 0


## The soldier: on his way to the window for stow_s, then at it with his sign
## up, counting the delay.
func _step_soldier(dt: float) -> void:
	if phase == STOW:
		stow_left -= dt
		if stow_left < dt * 0.5:
			stow_left = 0.0
			stow_ended = true
			phase = PAPERS
			_ask_next()
	elif phase == PAPERS and not wanted.is_empty():
		delay += dt
		if delay >= float(_delays + 1) * _delay_every - dt * 0.5:
			_delays += 1
			delayed = true


## The sign for the next document goes up; with none left, the papers are done.
func _ask_next() -> void:
	delay = 0.0
	_delays = 0
	if _documents.is_empty():
		wanted = ""
		papers_done = true
		return
	wanted = _documents[0]
	_documents.remove_at(0)
	asked = true


## He handed a document out of the window. True when it was the one the sign
## asks for; anything else is refused.
func hand_over(document: String) -> bool:
	if kind != CHECKPOINT or phase != PAPERS or wanted.is_empty() or document != wanted:
		return false
	_ask_next()
	return true


## The Papers phase is passed by itself (forged papers, GDD 7.7).
func papers_passed() -> void:
	if kind == CHECKPOINT and phase == PAPERS:
		_documents = []
		_ask_next()


## The bar goes up: he may drive on.
func release() -> void:
	if kind != CHECKPOINT:
		return
	released = true
	phase = THROUGH
	wanted = ""
	delay = 0.0


## Turned back (GDD 10.2): the queue again, from its end.
func turn_back() -> void:
	if kind == CHECKPOINT:
		_begin_queue()


# --- Corridors ---------------------------------------------------------------

func _set_corridor(check: Dictionary) -> void:
	_corridor_at = GameData.as_float(check.get("at_m"))
	_corridor_from = _corridor_at - GameData.as_float(check.get("taper_m"))
	_corridor_to = _corridor_at + GameData.as_float(check.get("length_m"))
	_corridor_half_gap = GameData.as_float(check.get("gap_m")) * 0.5
	_corridor_sign_at = maxf(_corridor_from - GameData.as_float(check.get("sign_lead_s")) * _data.tuning.fi("gear_speeds", 2) * KMH_TO_MS, 0.0)
	_corridor_judged = false


## The barriers beside a car at `s` whose middle is at `x` (GDD 10.2, 10.4),
## as Vector2(left, right) in x; (-INF, INF) where there are none. Every lane
## has a corridor of its own, corridor_gap wide about the lane's middle; over
## the taper before it the barriers close in from the lane's own lines.
func walls(s: float, x: float) -> Vector2:
	if not active or _corridor_to <= _corridor_from or s < _corridor_from or s > _corridor_to:
		return Vector2(-INF, INF)
	var half: float = _corridor_half_gap
	if s < _corridor_at:
		half = lerpf(_car.lane_width() * 0.5, _corridor_half_gap, (s - _corridor_from) / (_corridor_at - _corridor_from))
	var middle: float = _car.lane_center(clampi(_car.lane_of(x), 0, _car.lanes - 1))
	return Vector2(middle - half, middle + half)


## The corridor for the view: Vector3(where the barriers begin to close in,
## where they are narrowest, where they end) along the road, and the gap.
func corridor() -> Vector3:
	return Vector3(_corridor_from, _corridor_at, _corridor_to)


func corridor_gap() -> float:
	return _corridor_half_gap * 2.0


## The checkpoint's sign, while it is ahead of the car within `ahead` metres.
func signs_near(ahead: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if active and _corridor_to > _corridor_from and _corridor_sign_at >= 0.0:
		var gap: float = _corridor_sign_at - _car.s
		if gap >= 0.0 and gap <= ahead:
			# A limit of 0: the checkpoint is one to stop at.
			out.append({"kind": "checkpoint", "ahead": gap, "limit": _corridor_max_kmh if _corridor_max_kmh < INF else 0.0})
	return out


# --- The Call ----------------------------------------------------------------

## He took the phone from his pocket while it rang (GDD 10.4). `how` is one
## of the TAKEN_ words. False when there is no call to take.
func answer(how: String) -> bool:
	if call != CALL_RINGING:
		return false
	call = CALL_TALKING
	call_left = _talk_s
	call_taken = how
	call_answered = true
	return true


## True for a car that is pulled over as GDD 4.6 asks: stopped, wholly off
## the lanes, hazard lights on.
func pulled_over_safely(hazards_on: bool) -> bool:
	return hazards_on and _car.speed <= _stopped_kmh and _car.x - _car.half_width() >= _car.road_right()


## True while the car stands whatever his foot does: for a call taken pulled
## over (GDD 10.4), and at the Checkpoint from the moment the soldier starts
## toward him until he is let through (GDD 10.2).
func holds_car() -> bool:
	if kind == CHECKPOINT:
		return phase == STOW or phase == PAPERS
	return call == CALL_TALKING and call_taken == TAKEN_PARKED


## True while the phone is at his ear in his own hand.
func phone_in_hand() -> bool:
	return call == CALL_TALKING and call_taken != TAKEN_WITH_PASSENGER


## True while he talks and so can reach for nothing.
func talking() -> bool:
	return call == CALL_TALKING


## The road is behind him: whoever is on the phone hangs up.
func hang_up() -> void:
	if call == CALL_TALKING:
		call = CALL_OVER
		call_left = 0.0
		call_ended = true
	elif call == CALL_RINGING:
		call = CALL_OVER
		call_left = 0.0
		call_missed = true


func _step_call(dt: float) -> void:
	if call != CALL_RINGING and call != CALL_TALKING:
		return
	call_left -= dt
	if call_left >= dt * 0.5:
		return
	call_left = 0.0
	if call == CALL_RINGING:
		call_missed = true
	else:
		call_ended = true
	call = CALL_OVER


## The dust (GDD 10.3) on its fixed rhythm: thin_s of thin dust, then thick_s
## of thick, over and over. It goes by the clock, not by the road: standing
## still does not wait it out.
func _step_dust(dt: float) -> void:
	var cycle: float = _thin_s + _thick_s
	# Each change is on the tick whose time is nearest to it.
	var at: float = fposmod(time + dt * 0.5, cycle)
	thick = at >= _thin_s
	visibility = _thick_m if thick else _thin_m
	dust_change_in = maxf((cycle if thick else _thin_s) - at + dt * 0.5, 0.0)


## A car that stands in the Storm (GDD 10.3) is safe wholly off the lanes
## with its hazard lights on. Anywhere else, or dark, something may come out
## of the dust behind it every rear_end_every_s: the draw is made
## rear_end_tell_s before, and what it brings shows its lights and sounds its
## horn for that long before it hits. A car that has moved off or made itself
## safe by then is missed.
func _step_standing(dt: float, hazards_on: bool) -> void:
	var off_the_lanes: bool = _car.x - _car.half_width() >= _car.road_right()
	if _car.speed > _stopped_kmh or (hazards_on and off_the_lanes):
		_stood = 0.0
		_drawn = false
		_coming = false
		rear_end_in = 0.0
		return
	_stood += dt
	if not _drawn and _stood >= _rear_end_every - _rear_end_tell - dt * 0.5:
		_drawn = true
		_coming = _rng.chance(Rng.ROAD, _rear_end_chance)
		rear_end_tell = _coming
	rear_end_in = maxf(_rear_end_every - _stood, 0.0) if _coming else 0.0
	if _stood >= _rear_end_every - dt * 0.5:
		rear_end = _coming
		_stood = 0.0
		_drawn = false
		_coming = false
		rear_end_in = 0.0
