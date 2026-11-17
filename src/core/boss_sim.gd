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
const KMH_TO_MS: float = 1.0 / 3.6
## Keeps the plan's draws apart from the draw of the modifier.
const PLAN_SALT: int = 2
const NIGHT: String = "night"

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

# --- What happened this tick -------------------------------------------------
## Something has come out of the dust behind him: it will hit him.
var rear_end_tell: bool = false
## It hit him.
var rear_end: bool = false

var _data: GameData
var _car: CarSim
var _rng: Rng
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


func configure(data: GameData, car: CarSim, rng: Rng) -> void:
	_data = data
	_car = car
	_rng = rng


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
		STORM:
			_plan_storm(data, out, GameData.as_dict(record.get("storm")), modifier, random)
	return out


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
	var record: Dictionary = _data.record("bosses", kind)
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
	begin_tick()


## Clears what happened last tick.
func begin_tick() -> void:
	rear_end_tell = false
	rear_end = false


## Before the car moves: the boss's own clock, and what goes by it.
## `hazards_on` is the state of his hazard lights.
func step_road(dt: float, hazards_on: bool) -> void:
	if not active:
		return
	time += dt
	if kind == STORM:
		_step_dust(dt)
		_step_standing(dt, hazards_on)


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
