class_name LegGenerator
extends RefCounted
## Builds one leg from a seed (GDD 9.1, 9.2): the beats from 0 to
## leg_length - leg_tail and everything they put on the road.
##
## The plan is drawn up in the "par frame": the player driving third gear's
## cruise speed. Every vehicle holds its lane and speed, so its distance ahead
## of the player is a straight line in the player's own progress:
##     gap(p) = ahead - closing * (p - trigger)
## where `closing` is the share of his own speed at which he gains on it. From
## that the generator knows the stretch of his progress during which each
## vehicle is beside him (its "block"), and checks three things exactly:
##   - two vehicles in one lane never come within gen_spawn_clearance of each
##     other before he has passed both (so nothing has to brake, and the plan
##     stays true when it is driven);
##   - no block reaches into a CALM beat;
##   - a line through the leg exists that is never inside a block (rule 3).
##
## The rules of GDD 9.2 hold by construction or the draw is thrown away:
##   1. the first HAZARD, CLUSTER or SLOWPOKE begins within first_event_within
##   2. at least two CALM beats; no two adjacent except where the leg allows
##   3. at every point one lane is passable in third gear without a close call
##   4. no vehicle appears overlapping another
##   5. the same seed gives the same leg
##
## The result is a plain Dictionary (see `generate`), so it can be saved,
## compared byte for byte, and run by LegSim.

const EVENT_TYPES: PackedStringArray = ["HAZARD", "CLUSTER", "SLOWPOKE"]
## Salt of the draws that lay a road's leans (D-074).
const CAMBER_SALT: int = 7411
## Beats that put nothing beside the player.
const QUIET_TYPES: PackedStringArray = ["CALM", "CURVE", "GUST"]
const KMH_TO_MS: float = 1.0 / 3.6
## The modifiers that take a stretch of road of their own (GDD 9.4), and the
## role of the vehicles each puts on it ("" where it puts none).
const ZONE_KINDS: PackedStringArray = ["sheep", "wedding", "melon_truck"]
const TWIST_ROLES: Dictionary = {"sheep": "", "wedding": "wedding", "melon_truck": "melon_truck"}
## Lane index of the oncoming lane on an undivided road.
const ONCOMING_LANE: int = -1
## Lane index used for things parked on the shoulder.
const SHOULDER_LANE: int = 99
## More lane changes than any leg needs; the search stops there.
const MAX_CHANGES: int = 48
const EPSILON: float = 0.0001
## For a search that may end in any lane.
const ANY_LANE: int = -99
## The two ways the traffic of fourth gear's frame is worked out (rule 6).
const HELD: int = 0
const FREE: int = 1


## One vehicle of the plan, in the par frame.
class Planned:
	extends RefCounted
	var vehicle: String = ""
	var lane: int = 0
	var speed: float = 0.0
	var direction: int = 1
	var role: String = ""
	var change_to: int = 0
	var change_gap: float = 0.0
	var late: bool = false
	## The player's progress at which it appears, and how far ahead it is then.
	var trigger: float = 0.0
	var ahead: float = 0.0
	## Share of his own speed at which the player gains on it (0 or less: never).
	var closing: float = 0.0
	var half_length: float = 0.0
	var half_width: float = 0.0
	## Counts toward the leg's traffic density.
	var counted: bool = true
	## The stretches of the player's progress during which it is beside him:
	## Vector3(lane, from, to). Worked out when first asked for.
	var blocks: Array[Vector3] = []
	var blocks_known: bool = false
	## The vehicles queued behind this one, nearest first (held up by it).
	var queue: Array[Planned] = []
	## True for a vehicle that queues behind another.
	var queued: bool = false
	## One bit per lane it is ever in (for quick "do these two share a lane").
	var lanes_mask: int = 0
	## The player's progress at which it is behind him for good.
	var passed: float = 0.0
	## The same three for a player who holds fourth gear (rule 6): the share
	## of his speed at which he gains on it, its blocks, and where it is passed
	## if nothing holds it up.
	var skill_closing: float = 0.0
	var skill_blocks: Array[Vector3] = []
	var skill_blocks_known: bool = false
	var skill_passed: float = 0.0
	## In that frame it may come up behind a slower vehicle of its lane before
	## he reaches it: his progress when it does (INF: never), and the vehicle
	## it then stays behind. Twice: as far back as it can be (HELD) and as far
	## ahead (FREE); the two differ only where a vehicle that changes lane is
	## in the way of it for a while.
	var skill_catch: PackedFloat64Array = PackedFloat64Array([INF, INF])
	var skill_holder: Array[Planned] = [null, null]
	## It is part of the plan (not one being tried for a place in it).
	var placed: bool = false

	func gap_at(progress: float) -> float:
		return ahead - closing * (progress - trigger)

	## The share of his speed at which a player in third gear (or, with
	## `skill`, in fourth) gains on it.
	func closing_in(skill: bool) -> float:
		return skill_closing if skill else closing

	func passed_in(skill: bool) -> float:
		return skill_passed if skill else passed

	## How far ahead of him it is at `progress`, in either frame. It appears
	## `ahead` in front when he passes `trigger`, whatever his speed.
	func gap_in(progress: float, skill: bool) -> float:
		return ahead - closing_in(skill) * (progress - trigger)

	## His progress at which it is `gap` ahead. Only where he gains on it.
	func progress_in(gap: float, skill: bool) -> float:
		return trigger + (ahead - gap) / closing_in(skill)

	## The player's progress when he is level with it (INF: never).
	func meet() -> float:
		if closing <= 0.0:
			return INF
		return trigger + ahead / closing

	## The player's progress at which it is `gap` ahead. Only for closing > 0.
	func progress_at(gap: float) -> float:
		return trigger + (ahead - gap) / closing

	func changes_lane() -> bool:
		return change_to != lane


## A line through the leg, in the frame of the player it is drawn for:
## where each lane change starts and the lane it leads to.
class Line:
	extends RefCounted
	## True for the skill line: fourth gear's speed, its margin, its lane change.
	var skill: bool = false
	var s: PackedFloat64Array = PackedFloat64Array()
	var lane: PackedInt32Array = PackedInt32Array()
	## How far along the leg it has been searched.
	var target: float = 0.0
	## Metres of road in which both lanes must be free to change lane on it.
	var change: float = 0.0

	func take(path: Array) -> void:
		s = PackedFloat64Array()
		lane = PackedInt32Array()
		for entry: Variant in path:
			var pair: Array = entry
			s.append(GameData.as_float(pair[0]))
			lane.append(GameData.as_int(pair[1]))

	func to_path(digits: float) -> Array:
		var path: Array = []
		for index: int in s.size():
			path.append([snappedf(s[index], digits), lane[index]])
		return path


var _data: GameData
var _tuning: Tuning
var _random: RandomNumberGenerator = Rng.seeded(0)

var _leg: Dictionary = {}
var _modifier: Dictionary = {}
var _modifier_id: String = ""
## A Twist's modifier ({} for none) and where along the beats it goes.
var _twist: Dictionary = {}
var _twist_at: float = 0.5
var _twist_zone: Dictionary = {}
var _act: int = 1
var _lanes: int = 3
var _divided: bool = true
var _par: float = 0.0
## The widest vehicle the road lets through (INF: any): a road with barriers
## across it carries nothing wider than their gap.
var _max_width: float = INF
var _par_ms: float = 0.0
var _leg_length: float = 0.0
var _beats_end: float = 0.0
var _margin: float = 0.0
var _change_length: float = 0.0
var _clearance: float = 0.0
var _min_gap: float = 0.0
var _spawn_ahead: float = 0.0
var _spawn_ahead_oncoming: float = 0.0
var _car_length: float = 0.0
var _lane_width: float = 0.0
var _signal_time: float = 0.0
var _late_signal_time: float = 0.0
var _change_time: float = 0.0
var _start_lane: int = 0
var _sparse: bool = false
## True for the motorcade's side road: no beats, only the two-lane traffic.
var _detour: bool = false
## True for a road that is no leg (generate_road: a boss's).
var _own_road: bool = false

# --- One draw ----------------------------------------------------------------
var _beats: Array[Dictionary] = []
var _planned: Array[Planned] = []
var _hazards: Array[Dictionary] = []
var _curves: Array[Dictionary] = []
var _gusts: Array[Dictionary] = []
var _zones: Array[Dictionary] = []
var _flock: Dictionary = {}
var _melons: Dictionary = {}
var _motorcade: Dictionary = {}
## Blocks that are not vehicles (hazards, chicanes, the flock, melons): (lane, from, to).
var _fixed: Array[Vector3] = []
## The planned line of rule 3 (third gear) and the skill line of rule 6
## (fourth gear).
var _line: Line = Line.new()
var _skill_line: Line = Line.new()
## Rule 6 holds on this road: never a sealed wall in fourth (D-074). Not on
## the two-lane road nor behind the Motorcade, whose hold-up is the leg.
var _skill: bool = false
var _skill_pace: float = 0.0
var _skill_ms: float = 0.0
var _skill_margin: float = 0.0
var _follow_gap: float = 0.0
## The traffic of fourth gear's frame has to be worked out again (a vehicle
## was added, taken away or slowed), and whether it stands as planned.
var _skill_dirty: bool = true
var _skill_sound: bool = true
## One bit per lane whose traffic has changed since it was last worked out,
## the lanes as they were worked out (vehicles that keep their lane, in the
## order they appear), and which of them stand as the model has them.
var _skill_stale: int = 0
var _skill_lanes: Array[Array] = []
var _skill_lane_sound: PackedByteArray = PackedByteArray()
## Half the length of the longest vehicle there is, and half the width of
## the widest.
var _longest_half: float = 0.0
var _widest_half: float = 0.0
## Blocks that are not vehicles and differ between the frames (the melons lie
## where the truck was when he came near it): those of third gear, and those
## of fourth, which are worked out with its traffic.
var _par_fixed: Array[Vector3] = []
var _skill_fixed: Array[Vector3] = []
## Vehicles the leg should carry (beats may not exceed it).
var _density_goal: int = 0
## Vehicles slowed while fitting others in, and the speeds they had: undone
## when what caused it is taken back.
var _slowed: Array[Planned] = []
var _slowed_speed: PackedFloat64Array = PackedFloat64Array()
## Which lengths of road the leg's beat types can fill exactly.
var _fillable: PackedByteArray = PackedByteArray()
## The same, remembered by the set of beat types it was worked out for.
static var _fillable_tables: Dictionary = {}
var _type_low: Dictionary = {}
var _type_high: Dictionary = {}
var _weights: Dictionary = {}
## The templates this leg can use, by beat type.
var _templates: Dictionary = {}
var _first_within: float = 0.0
var _beat_shifts: PackedFloat64Array = PackedFloat64Array()
## Stretches kept for what a boss puts on its road (generate_road).
var _reserved: Array = []
var _late_share: float = 0.0


## Generates a leg. `modifier_id` may be "" for none. Returns:
##   { "leg", "act", "seed", "modifier", "lanes", "divided", "condition",
##     "par_s", "length", "beats_end", "start_lane", "attempts", "sparse",
##     "beats":   [ { "type", "template", "s", "length" } ],
##     "spawns":  [ { "vehicle", "lane", "speed", "direction", "role",
##                    "change_to", "change_gap", "late", "trigger_s", "ahead",
##                    "meet_s" } ]  by trigger_s; meet_s is -1 for a vehicle
##                    faster than third gear, which is never caught,
##     "hazards": [ { "kind", "s", "x" } ]  by s,
##     "curves":  [ { "s", "length", "k" } ],   k signed: + pushes right
##     "gusts":   [ { "s", "dir" } ],
##     "zones":   [ { "kind", "s", "length", ... } ],
##     "flock", "melons", "motorcade": {} or what that encounter needs,
##     "path":    [ [s, lane], ... ]  a line through the leg that meets nothing,
##     "skill_path": the same for a player who holds fourth gear from the
##                   start (rule 6, D-074): it touches nothing, but passes
##                   closer and changes lane in less road. [] on a road
##                   where the rule does not hold (two-lane, the Motorcade) }
##
## `twist` is a Twist a guest will throw in (GDD 11.3: "injects a modifier
## beat"): { "modifier": a modifier with a stretch of its own (sheep, the
## wedding, the melon truck), "at": where along the beats, 0 to 1 }. It is
## laid out like the leg's own, so every rule of the generator holds with it
## on the road, and the plan says where it is in "twist": { "modifier",
## "s", "length", "first_s" (the car's progress at which the first thing of
## it would come onto the road), "end_s" }. LegSim keeps it off the road
## until the heckle has been heard.
static func generate(data: GameData, leg_id: String, act: int, leg_seed: int, modifier_id: String = "", twist: Dictionary = {}) -> Dictionary:
	var generator: LegGenerator = LegGenerator.new()
	generator._setup(data, data.record("legs", leg_id), act, modifier_id)
	var twist_id: String = GameData.as_string(twist.get("modifier"))
	if not twist_id.is_empty() and twist_id != modifier_id and ZONE_KINDS.has(twist_id):
		generator._twist = data.record("modifiers", twist_id)
		generator._twist_at = GameData.as_float(twist.get("at"), 0.5)
	return generator._generate(leg_id, leg_seed)


## A road that is no leg (a boss's, GDD 10.4): `road` gives what a leg's
## record gives (lanes, divided, density, condition, par_s, beat_weights) and
## its own length_m and tail_m; density_mult scales its traffic. `reserved`
## are stretches { kind, s, length, lane } kept for what the boss puts there:
## no beat is laid in one, no vehicle is beside him in one, and the planned
## line runs through it in `lane`.
##
## Rule 6 is not kept on such a road, and its plan carries no skill line:
## the boss does with the traffic what it will (Dawn thins it, and has it
## wait at the last checkpoint), and the traffic of fourth gear's frame
## does not survive that as the planned line of third gear does.
static func generate_road(data: GameData, road: Dictionary, act: int, road_seed: int, reserved: Array = []) -> Dictionary:
	var generator: LegGenerator = LegGenerator.new()
	generator._setup(data, road, act, "")
	generator._reserved = reserved
	generator._own_road = true
	return generator._generate(GameData.as_string(road.get("id")), road_seed)


## Where a plan's vehicles are for a player who holds fourth gear from the
## start, as rule 6 works it out (the plan itself carries only the line that
## was kept open through them): { "sound": the traffic stands as worked out,
## "blocks": for each of the plan's spawns, in their order, the stretches of
## his progress during which it is beside him, [ [lane, from, to], ... ] }.
## For tests and tools.
static func skill_blocks(data: GameData, plan: Dictionary) -> Dictionary:
	var generator: LegGenerator = LegGenerator.new()
	generator._setup(data, data.record("legs", GameData.as_string(plan.get("leg"))), GameData.as_int(plan.get("act"), 1), GameData.as_string(plan.get("modifier")))
	generator._skill = true
	generator._melons = GameData.as_dict(plan.get("melons"))
	for entry: Variant in GameData.as_array(plan.get("spawns")):
		var spawn: Dictionary = GameData.as_dict(entry)
		var planned: Planned = Planned.new()
		var type: Dictionary = data.record("vehicles", GameData.as_string(spawn.get("vehicle")))
		planned.vehicle = GameData.as_string(spawn.get("vehicle"))
		planned.lane = GameData.as_int(spawn.get("lane"))
		planned.change_to = GameData.as_int(spawn.get("change_to"), planned.lane)
		planned.change_gap = GameData.as_float(spawn.get("change_gap"))
		planned.late = GameData.as_bool(spawn.get("late"))
		planned.direction = GameData.as_int(spawn.get("direction"), 1)
		planned.role = GameData.as_string(spawn.get("role"))
		planned.half_length = GameData.as_float(type.get("length")) * 0.5
		planned.half_width = GameData.as_float(type.get("width")) * 0.5
		planned.speed = GameData.as_float(spawn.get("speed"))
		planned.closing = 1.0 - float(planned.direction) * planned.speed / generator._par
		planned.trigger = GameData.as_float(spawn.get("trigger_s"))
		planned.ahead = GameData.as_float(spawn.get("ahead"))
		planned.placed = true
		generator._refresh(planned)
		generator._planned.append(planned)
	generator._skill_all_stale()
	generator._resolve_skill()
	var blocks: Array = []
	for planned: Planned in generator._planned:
		var own: Array = []
		if generator._skill_sound:
			for block: Vector3 in generator._blocks_of(planned, true):
				own.append([int(block.x), block.y, block.z])
		blocks.append(own)
	return {"sound": generator._skill_sound, "blocks": blocks}


## The plan as text, the same for the same plan on every machine (T-GEN-02).
static func to_text(plan: Dictionary) -> String:
	return JSON.stringify(plan, "", true)


## Vehicles the leg should carry: its own density plus traffic_per_act for each
## act after the first, per km of beats (GDD 9.1, 12.3).
static func density_target(data: GameData, leg_id: String, act: int) -> int:
	var leg: Dictionary = data.record("legs", leg_id)
	var tuning: Tuning = data.tuning
	var per_km: float = GameData.as_float(leg.get("density")) + tuning.f("traffic_per_act") * float(act - 1)
	return roundi(per_km * (tuning.f("leg_length") - tuning.f("leg_tail")) / 1000.0)


func _setup(data: GameData, leg: Dictionary, act: int, modifier_id: String) -> void:
	_data = data
	_tuning = data.tuning
	_leg = leg
	_modifier_id = modifier_id
	_modifier = data.record("modifiers", modifier_id) if not modifier_id.is_empty() else {}
	_act = act
	_lanes = GameData.as_int(_leg.get("lanes"), 3)
	_divided = GameData.as_bool(_leg.get("divided"), true)
	_par = _tuning.fi("gear_speeds", 2)
	_max_width = GameData.as_float(_leg.get("max_vehicle_width"), INF)
	_par_ms = _par * KMH_TO_MS
	# A leg is leg_length long with leg_tail of it for the Exit; a road that
	# is no leg says its own.
	_leg_length = GameData.as_float(_leg.get("length_m"), _tuning.f("leg_length"))
	_beats_end = _leg_length - GameData.as_float(_leg.get("tail_m"), _tuning.f("leg_tail"))
	_margin = _tuning.f("gen_block_margin")
	_change_length = _tuning.f("gen_lane_change")
	_skill_pace = _tuning.fi("gear_speeds", _tuning.i("gen_skill_gear") - 1)
	_skill_ms = _skill_pace * KMH_TO_MS
	_skill_margin = _tuning.f("gen_skill_margin")
	_follow_gap = _tuning.f("traffic_follow_gap")
	_longest_half = 0.0
	_widest_half = 0.0
	for type: Dictionary in _data.records("vehicles"):
		_longest_half = maxf(_longest_half, GameData.as_float(type.get("length")) * 0.5)
		_widest_half = maxf(_widest_half, GameData.as_float(type.get("width")) * 0.5)
	_line = Line.new()
	_line.change = _change_length
	_skill_line = Line.new()
	_skill_line.skill = true
	_skill_line.change = _tuning.f("gen_skill_lane_change")
	_clearance = _tuning.f("gen_spawn_clearance")
	_min_gap = _tuning.f("gen_min_gap")
	_spawn_ahead = _tuning.f("spawn_ahead")
	_spawn_ahead_oncoming = _tuning.f("spawn_ahead_oncoming")
	_car_length = _tuning.f("car_length")
	_lane_width = _tuning.f("lane_width")
	_signal_time = _tuning.f("signal_time")
	_late_signal_time = _tuning.f("late_signal_time")
	_change_time = _tuning.f("lane_change_time")
	_start_lane = _lanes / 2
	_templates = {}
	_first_within = _tuning.f("first_event_within")
	_beat_shifts = _tuning.floats("gen_beat_shifts")
	_late_share = _tuning.fi("late_signaller_share", clampi(_act, 1, 3) - 1)


func _generate(leg_id: String, leg_seed: int) -> Dictionary:
	_prepare_beat_types()
	var kind: String = GameData.as_string(GameData.as_dict(_leg.get("special")).get("kind"))
	# Two-lane and Motorcade take their traffic from their encounter (GDD 9.3).
	_density_goal = 0 if kind == "two_lane" or kind == "motorcade" else _own_density()
	# Rule 6 is about traffic he can be stuck in. On those two roads the
	# hold-up is the encounter itself (the gap in what comes the other way;
	# the side road).
	_skill = kind != "two_lane" and kind != "motorcade" and not _own_road
	var attempts: int = _tuning.i("gen_max_attempts")
	var total: int = attempts + _tuning.i("gen_sparse_attempts")
	var attempt: int = 0
	var done: bool = false
	while not done and attempt < total:
		_sparse = attempt >= attempts
		_random.seed = Rng.derive(leg_seed, attempt + 1)
		done = _draw()
		attempt += 1
	if not done:
		push_error("LegGenerator: no leg '%s' for seed %d in %d draws" % [leg_id, leg_seed, total])
		_reset()
	return _to_plan(leg_id, leg_seed, attempt)


## Vehicles this road should carry (for a leg: density_target).
func _own_density() -> int:
	var per_km: float = GameData.as_float(_leg.get("density")) + _tuning.f("traffic_per_act") * float(_act - 1)
	return roundi(per_km * GameData.as_float(_leg.get("density_mult"), 1.0) * _beats_end / 1000.0)


func _to_plan(leg_id: String, leg_seed: int, attempts: int) -> Dictionary:
	var spawns: Array[Dictionary] = []
	for planned: Planned in _planned:
		var meet: float = planned.meet()
		spawns.append({
			"vehicle": planned.vehicle,
			"lane": planned.lane,
			"speed": _round(planned.speed),
			"direction": planned.direction,
			"role": planned.role,
			"change_to": planned.change_to,
			"change_gap": _round(planned.change_gap),
			"late": planned.late,
			"trigger_s": _round(planned.trigger),
			"ahead": _round(planned.ahead),
			"meet_s": -1.0 if meet == INF else _round(meet),
		})
	spawns.sort_custom(_by_trigger)
	_hazards.sort_custom(_by_s)
	_gusts.sort_custom(_by_s)
	var plan: Dictionary = _plan_of(leg_id, leg_seed, attempts, spawns, _line.to_path(0.001))
	if not _twist_zone.is_empty():
		plan["twist"] = _twist_in(spawns)
	return plan


## Where the Twist is: its stretch, and the car's progress at which the first
## thing of it would come onto the road (a vehicle's trigger, or the point
## from which the sheep walk).
func _twist_in(spawns: Array[Dictionary]) -> Dictionary:
	var id: String = GameData.as_string(_twist.get("id"))
	var zone_s: float = _twist_zone["s"]
	var zone_length: float = _twist_zone["length"]
	var first: float = zone_s
	if id == "sheep":
		first = minf(first, GameData.as_float(_flock.get("start_s")))
	var role: String = GameData.as_string(TWIST_ROLES.get(id))
	for spawn: Dictionary in spawns:
		if not role.is_empty() and GameData.as_string(spawn.get("role")) == role:
			first = minf(first, GameData.as_float(spawn.get("trigger_s")))
	return {
		"modifier": id,
		"s": zone_s,
		"length": zone_length,
		"first_s": _round(maxf(first, 0.0)),
		"end_s": zone_s + zone_length,
	}


func _plan_of(leg_id: String, leg_seed: int, attempts: int, spawns: Array[Dictionary], path: Array) -> Dictionary:
	return {
		"leg": leg_id,
		"act": _act,
		"seed": leg_seed,
		"modifier": _modifier_id,
		"lanes": _lanes,
		"divided": _divided,
		"condition": GameData.as_string(_leg.get("condition")),
		"par_s": GameData.as_float(_leg.get("par_s")),
		"length": _leg_length,
		"beats_end": _beats_end,
		"start_lane": _start_lane,
		"attempts": attempts,
		"sparse": _sparse,
		"beats": _beats,
		"spawns": spawns,
		"hazards": _hazards,
		"curves": _curves,
		"cambers": lay_cambers(_tuning, leg_seed, _leg_length, _leg_length, _reserved),
		"gusts": _gusts,
		"zones": _zones,
		"flock": _flock,
		"melons": _melons,
		"motorcade": _motorcade,
		"path": path,
		"skill_path": _skill_line.to_path(0.001) if _skill else [],
	}


## How a road leans, stretch by stretch (D-074): [ { "s", "length", "lean" } ],
## lean the share of crown_drift it pushes with, + toward the right. It
## begins flat for camber_lead_m; then stretches of camber_length_m follow
## one another, each flat, leaning right or leaning left by camber_weights,
## a leaning one by one of camber_leans; never two leans the same way in a
## row without a flat between; the road past `leans_end` and whatever a
## boss has reserved are flat.
##
## Drawn from the road's seed by itself, not from the generator's stream:
## the traffic of a seed is the traffic it was before roads leaned.
static func lay_cambers(tuning: Tuning, road_seed: int, length: float, leans_end: float, reserved: Array = []) -> Array:
	var out: Array = []
	var random: RandomNumberGenerator = Rng.seeded(Rng.derive(road_seed, CAMBER_SALT))
	var shortest: float = tuning.fi("camber_length_m", 0)
	var longest: float = tuning.fi("camber_length_m", 1)
	var weights: PackedFloat64Array = tuning.floats("camber_weights")
	var leans: PackedFloat64Array = tuning.floats("camber_leans")
	var total: float = 0.0
	for weight: float in weights:
		total += weight
	var at: float = tuning.f("camber_lead_m")
	var end: float = minf(leans_end, length)
	var last: float = 0.0
	while at < end and total > 0.0 and not leans.is_empty():
		var stretch: float = minf(random.randf_range(shortest, longest), end - at)
		var draw: float = random.randf() * total
		var side: float = 0.0
		if draw >= weights[0]:
			side = 1.0 if draw < weights[0] + weights[1] else -1.0
		var lean: float = side * leans[random.randi_range(0, leans.size() - 1)]
		if side != 0.0 and side == last:
			# The same way twice running would be one long lean: a flat between.
			lean = 0.0
		var kept: bool = lean != 0.0 and stretch >= shortest * 0.5
		for entry: Variant in reserved:
			var zone: Dictionary = GameData.as_dict(entry)
			var from: float = GameData.as_float(zone.get("s"))
			if at < from + GameData.as_float(zone.get("length")) and at + stretch > from:
				kept = false
		if kept:
			out.append({"s": snappedf(at, 0.001), "length": snappedf(stretch, 0.001), "lean": lean})
		last = signf(lean) if kept else 0.0
		at += stretch
	return out


static func _by_trigger(a: Dictionary, b: Dictionary) -> bool:
	var a_trigger: float = a["trigger_s"]
	var b_trigger: float = b["trigger_s"]
	if a_trigger != b_trigger:
		return a_trigger < b_trigger
	var a_ahead: float = a["ahead"]
	var b_ahead: float = b["ahead"]
	if a_ahead != b_ahead:
		return a_ahead < b_ahead
	var a_lane: int = a["lane"]
	var b_lane: int = b["lane"]
	return a_lane < b_lane


static func _by_s(a: Dictionary, b: Dictionary) -> bool:
	var a_s: float = a["s"]
	var b_s: float = b["s"]
	if a_s != b_s:
		return a_s < b_s
	if a.has("x") and b.has("x"):
		var a_x: float = a["x"]
		var b_x: float = b["x"]
		return a_x < b_x
	return false


# --- One draw ----------------------------------------------------------------

func _reset() -> void:
	_beats = []
	_planned = []
	_hazards = []
	_curves = []
	_gusts = []
	_zones = []
	_twist_zone = {}
	_flock = {}
	_melons = {}
	_motorcade = {}
	_fixed = []
	_par_fixed = []
	_skill_fixed = []
	_skill_all_stale()
	_slowed = []
	_slowed_speed = PackedFloat64Array()
	_line.take([[0.0, _start_lane]])
	_line.target = 0.0
	_skill_line.take([[0.0, _start_lane]])
	_skill_line.target = 0.0


func _draw() -> bool:
	_reset()
	var special: Dictionary = GameData.as_dict(_leg.get("special"))
	var kind: String = GameData.as_string(special.get("kind"))
	if _detour:
		if not _draw_two_lane(special):
			return false
	else:
		_keep_reserved()
		if kind == "roadworks":
			_reserve_chicanes(special)
		if not _reserve_zone(_modifier, -1.0):
			return false
		if not _twist.is_empty() and not _reserve_zone(_twist, _twist_at):
			return false
		if kind == "two_lane" and not _draw_two_lane(special):
			return false
		if not _lay_beats():
			return false
		_add_crosswind()
		if not _match_density(kind):
			return false
	# The whole leg once more, from scratch: rule 3, and rule 6.
	if not _whole_lines():
		return false
	if kind == "motorcade" and not _detour:
		if not _plan_motorcade(special):
			return false
	return true


# --- Beats: the layout (rules 1 and 2) ---------------------------------------

## Which beat types this leg can use, their shortest and longest lengths in
## whole metres, and which lengths of road they can fill exactly.
func _prepare_beat_types() -> void:
	_weights = GameData.as_dict(_leg.get("beat_weights")).duplicate()
	if GameData.as_string(_modifier.get("id")) == "potholes":
		# HAZARD beats doubled (GDD 9.4).
		_weights["HAZARD"] = maxf(GameData.as_float(_weights.get("HAZARD")), 1.0) * GameData.as_float(_modifier.get("hazard_mult"), 2.0)
	_type_low = {}
	_type_high = {}
	var types: PackedStringArray = []
	for key: Variant in _weights:
		types.append(str(key))
	if not types.has("HAZARD"):
		# Every leg can open with a hazard (rule 1), whatever its weights say.
		types.append("HAZARD")
	for type: String in types:
		var low: int = 1000000
		var high: int = 0
		for template: Dictionary in _templates_for(type):
			var span: Vector2i = _length_span(template)
			low = mini(low, span.x)
			high = maxi(high, span.y)
		if high > 0:
			_type_low[type] = low
			_type_high[type] = high
	# The table depends only on which types can be drawn and how long they
	# are, so it is worked out once for each such set.
	var size: int = int(_beats_end) + 1
	var table_key: String = str(size)
	for type_key: Variant in _type_low:
		if _weights.has(type_key) and GameData.as_float(_weights[type_key]) > 0.0:
			table_key += "|%s:%d-%d" % [str(type_key), GameData.as_int(_type_low[type_key]), GameData.as_int(_type_high[type_key])]
	if _fillable_tables.has(table_key):
		_fillable = _fillable_tables[table_key]
		return
	_fillable = PackedByteArray()
	_fillable.resize(size)
	var reachable: PackedInt32Array = PackedInt32Array()
	reachable.resize(size + 1)
	_fillable[0] = 1
	reachable[1] = 1
	for room: int in range(1, size):
		var fits: bool = false
		for key: Variant in _type_low:
			if not _weights.has(key) or GameData.as_float(_weights[key]) <= 0.0:
				continue
			var low: int = _type_low[key]
			var high: int = mini(GameData.as_int(_type_high[key]), room)
			if low > high:
				continue
			# Is any length from low to high followed by a fillable rest?
			if reachable[room - low + 1] - reachable[room - high] > 0:
				fits = true
				break
		_fillable[room] = 1 if fits else 0
		reachable[room + 1] = reachable[room] + (1 if fits else 0)
	_fillable_tables[table_key] = _fillable


func _length_span(template: Dictionary) -> Vector2i:
	var length: Variant = template.get("length_m")
	if length is Array:
		var span: Array = length
		return Vector2i(ceili(GameData.as_float(span[0])), floori(GameData.as_float(span[1])))
	var whole: int = roundi(GameData.as_float(length))
	return Vector2i(whole, whole)


func _templates_for(type: String) -> Array[Dictionary]:
	if _templates.has(type):
		var known: Array[Dictionary] = _templates[type]
		return known.duplicate()
	var out: Array[Dictionary] = []
	var potholes_only: bool = type == "HAZARD" and GameData.as_string(_modifier.get("id")) == "potholes"
	for beat: Dictionary in _data.records("beats"):
		if GameData.as_string(beat.get("type")) != type:
			continue
		if GameData.as_int(beat.get("min_lanes"), 1) > _lanes:
			continue
		if beat.has("acts") and not GameData.as_array(beat.get("acts")).has(float(_act)):
			continue
		if potholes_only and not _is_pothole_template(beat):
			continue
		out.append(beat)
	_templates[type] = out
	return out.duplicate()


func _is_pothole_template(template: Dictionary) -> bool:
	var hazards: Array = GameData.as_array(template.get("hazards"))
	if hazards.is_empty():
		return false
	for hazard: Variant in hazards:
		if GameData.as_string(GameData.as_dict(hazard).get("kind")) != "pothole":
			return false
	return true


## Lays the beats from 0 to beats_end, around any zone already reserved, and
## puts each beat's content on the road as it goes. A beat that does not fit
## where it is drawn is drawn again; the leg is thrown away only if nothing
## fits at all.
func _lay_beats() -> bool:
	var calm_adjacent: bool = GameData.as_bool(_leg.get("calm_adjacent"))
	var deadlines: Array = _tuning.a("gen_calm_deadlines")
	var calm_by: PackedFloat64Array = PackedFloat64Array()
	for deadline: Variant in deadlines:
		var span: Array = GameData.as_array(deadline)
		calm_by.append(_random.randf_range(GameData.as_float(span[0]), GameData.as_float(span[1])) * _beats_end)
	var first_within: float = _tuning.f("first_event_within")
	var calm_length: int = roundi(_tuning.f("calm_length"))

	var zones: Array[Dictionary] = _zones.duplicate()
	zones.sort_custom(_by_s)
	var s: int = 0
	var previous: String = ""
	var calms: int = 0
	var event_done: bool = false
	var segment: int = 0
	while segment <= zones.size():
		var segment_end: int = int(_beats_end)
		if segment < zones.size():
			segment_end = roundi(GameData.as_float(zones[segment]["s"]))
		while s < segment_end:
			var room: int = segment_end - s
			var calm_ok: bool = _type_low.has("CALM") and (previous != "CALM" or calm_adjacent)
			var calm_due: bool = event_done and calm_ok and calms < calm_by.size() and float(s) >= calm_by[calms]
			# What may come next, most wanted first: the event that opens the
			# leg; a CALM beat that is owed; quiet beats until the road has
			# cleared for it; anything the leg's weights allow.
			var placed: bool = false
			for tier: int in 4:
				var candidates: PackedStringArray = []
				var shares: PackedFloat64Array = []
				if not event_done:
					# Rule 1: the leg opens with an event, or with one gust and then an event.
					if tier == 0:
						var gust_low: int = GameData.as_int(_type_low.get("GUST"), 0)
						if s == 0 and gust_low > 0 and GameData.as_float(_weights.get("GUST")) > 0.0 \
								and float(gust_low) <= first_within and _random.randf() < _tuning.f("gen_opening_gust_chance"):
							candidates.append("GUST")
							shares.append(1.0)
					elif tier == 1:
						for type: String in EVENT_TYPES:
							if _type_low.has(type) and GameData.as_float(_weights.get(type)) > 0.0:
								candidates.append(type)
								shares.append(GameData.as_float(_weights.get(type)))
						if not candidates.has("HAZARD"):
							# A hazard can always open a leg.
							candidates.append("HAZARD")
							shares.append(0.5)
				elif tier == 0:
					if calm_due and room >= calm_length and _fillable[room - calm_length] != 0:
						candidates.append("CALM")
						shares.append(1.0)
				else:
					for key: Variant in _weights:
						var type: String = str(key)
						if not _type_low.has(type) or GameData.as_float(_weights[key]) <= 0.0:
							continue
						if type == "CALM" and not calm_ok:
							continue
						if tier == 1 and (not calm_due or not QUIET_TYPES.has(type)):
							continue
						if tier == 2 and calm_due and QUIET_TYPES.has(type):
							continue
						if tier == 3:
							continue
						candidates.append(type)
						shares.append(GameData.as_float(_weights[key]))
				while not placed and not candidates.is_empty():
					var pick: int = _weighted(shares)
					var type: String = candidates[pick]
					candidates.remove_at(pick)
					shares.remove_at(pick)
					placed = _lay_beat(type, s, room)
				if placed:
					break
			if not placed:
				return false
			var beat: Dictionary = _beats[_beats.size() - 1]
			var type_placed: String = beat["type"]
			s += GameData.as_int(beat["length"])
			previous = type_placed
			if type_placed == "CALM":
				calms += 1
			if EVENT_TYPES.has(type_placed):
				event_done = true
			elif not event_done and float(s) > first_within:
				return false
		if segment < zones.size():
			var zone: Dictionary = zones[segment]
			var zone_length: int = roundi(GameData.as_float(zone["length"]))
			_beats.append({"type": "SPECIAL", "template": GameData.as_string(zone["kind"]), "s": float(s), "length": float(zone_length)})
			s += zone_length
			previous = "SPECIAL"
		segment += 1
	return calms >= 2


## Adds one beat of `type` at `s`: a template of that type with a length that
## leaves a fillable rest of the `room`, whose content fits on the road there.
func _lay_beat(type: String, s: int, room: int) -> bool:
	var templates: Array[Dictionary] = _templates_for(type)
	while not templates.is_empty():
		var pick: int = _random.randi_range(0, templates.size() - 1)
		var template: Dictionary = templates[pick]
		templates.remove_at(pick)
		var span: Vector2i = _length_span(template)
		var lengths: PackedInt32Array = PackedInt32Array()
		for length: int in range(span.x, mini(span.y, room) + 1):
			if _fillable[room - length] != 0:
				lengths.append(length)
		if lengths.is_empty():
			continue
		var length: int = lengths[_random.randi_range(0, lengths.size() - 1)]
		if not _fill_beat(type, template, float(s), float(length)):
			continue
		_beats.append({"type": type, "template": GameData.as_string(template.get("id")), "s": float(s), "length": float(length)})
		return true
	return false


# --- Beats: the content ------------------------------------------------------

## Puts a beat's vehicles, hazards, curve or gust on the road. False if they
## do not fit there.
func _fill_beat(type: String, template: Dictionary, start: float, length: float) -> bool:
	if type == "CALM":
		return _stretch_clear(start, start + length)
	if template.has("curve"):
		var curve: Dictionary = GameData.as_dict(template.get("curve"))
		var k: float = _tuning.fi("curve_k", GameData.as_int(curve.get("k_index")))
		# A bend to the left pushes the car outward, to the right (+).
		var outward: float = 1.0 if GameData.as_string(curve.get("dir")) == "left" else -1.0
		_curves.append({"s": start, "length": length, "k": _round(k * outward)})
		return true
	if template.has("gust"):
		var gust: Dictionary = GameData.as_dict(template.get("gust"))
		var dir: int = -1 if GameData.as_string(gust.get("dir")) == "left" else 1
		_gusts.append({"s": _round(start + length * 0.5), "dir": dir})
		return true
	if not _sparse and _counted() + _template_count(template) > _density_goal:
		# The leg already carries its traffic.
		return false

	# Around the lane the planned line is in, one way round and then the other;
	# where the traffic of the beat before is still in the way, a little later.
	var focus: int = _lane_on_path(start)
	var mirror_first: bool = _random.randf() < 0.5
	var shifts: PackedFloat64Array = _beat_shifts
	if GameData.as_array(template.get("spawns")).is_empty():
		shifts = PackedFloat64Array([0.0])
	for shift: float in shifts:
		for flip: int in 2:
			var mirror: bool = mirror_first if flip == 0 else not mirror_first
			if not _template_fits(template, focus, mirror):
				continue
			var planned_before: int = _planned.size()
			var fixed_before: int = _fixed.size()
			var hazards_before: int = _hazards.size()
			var slowed_before: int = _slowed.size()
			if _place_template(template, start, shift, focus, mirror):
				var span: Vector2 = _blocks_span(planned_before, fixed_before)
				if (span.y <= span.x or _repair_path(_line, span.x, span.y, true)) and _skill_holds(true):
					return true
			_undo_slowing(slowed_before)
			for index: int in range(planned_before, _planned.size()):
				_planned[index].placed = false
				_skill_touch(_planned[index])
			_planned.resize(planned_before)
			_fixed.resize(fixed_before)
			_hazards.resize(hazards_before)
	return false


## Vehicles of a template that count toward the density.
func _template_count(template: Dictionary) -> int:
	var count: int = 0
	for spawn: Variant in GameData.as_array(template.get("spawns")):
		if GameData.as_string(GameData.as_dict(spawn).get("lane")) != "shoulder":
			count += 1
	return count


func _place_template(template: Dictionary, start: float, shift: float, focus: int, mirror: bool) -> bool:
	for spawn: Variant in GameData.as_array(template.get("spawns")):
		var entry: Dictionary = GameData.as_dict(spawn)
		var lane: int = _resolve_lane(GameData.as_string(entry.get("lane")), focus, mirror)
		var direction: int = -1 if lane == ONCOMING_LANE else 1
		var speed: float = GameData.as_float(entry.get("speed_kmh"))
		var closing: float = 1.0 - float(direction) * speed / _par
		var s_offset: float = GameData.as_float(entry.get("s_offset"))
		var planned: Planned = _plan_vehicle(GameData.as_string(entry.get("vehicle")), lane, speed, start + shift + s_offset / closing, direction)
		var change: Dictionary = GameData.as_dict(entry.get("lane_change"))
		if not change.is_empty():
			planned.change_to = _resolve_lane(GameData.as_string(change.get("to")), focus, mirror)
			var at: float = GameData.as_float(change.get("at_s_offset"))
			# The gap to the player, at par, when the vehicle starts to signal.
			planned.change_gap = maxf(at - (at - s_offset) * _par / maxf(speed, 1.0), _car_length)
			planned.late = _random.randf() < _late_share
			_refresh(planned)
		if lane == SHOULDER_LANE or direction < 0:
			planned.counted = false
		if not _place(planned):
			return false
	for hazard: Variant in GameData.as_array(template.get("hazards")):
		var entry: Dictionary = GameData.as_dict(hazard)
		var lane: int = _resolve_lane(GameData.as_string(entry.get("lane")), focus, mirror)
		var side: float = -1.0 if mirror else 1.0
		var x: float = _lane_center(lane) + GameData.as_float(entry.get("x_offset")) * side
		if not _add_hazard(GameData.as_string(entry.get("kind")), start + GameData.as_float(entry.get("s_offset")), x, lane):
			return false
	return true


func _template_fits(template: Dictionary, focus: int, mirror: bool) -> bool:
	for list_key: String in ["spawns", "hazards"]:
		for entry: Variant in GameData.as_array(template.get(list_key)):
			var item: Dictionary = GameData.as_dict(entry)
			var lane: int = _resolve_lane(GameData.as_string(item.get("lane")), focus, mirror)
			if lane == SHOULDER_LANE:
				continue
			if lane == ONCOMING_LANE:
				if _divided:
					return false
			elif lane < 0 or lane >= _lanes:
				return false
			var change: Dictionary = GameData.as_dict(item.get("lane_change"))
			if not change.is_empty():
				var to: int = _resolve_lane(GameData.as_string(change.get("to")), focus, mirror)
				if to < 0 or to >= _lanes:
					return false
	return true


func _resolve_lane(word: String, focus: int, mirror: bool) -> int:
	match word:
		"player":
			return focus
		"left_of_player":
			return focus + (1 if mirror else -1)
		"right_of_player":
			return focus + (-1 if mirror else 1)
		"shoulder":
			return SHOULDER_LANE
		"oncoming":
			return ONCOMING_LANE
	return focus


func _lane_center(lane: int) -> float:
	if lane == SHOULDER_LANE:
		return _lane_width * float(_lanes) + _tuning.f("rumble_strip_width") + _tuning.f("shoulder_width") * 0.5
	return _lane_width * (float(lane) + 0.5)


# --- Vehicles in the par frame -----------------------------------------------

## A vehicle the player is level with at `meet`. If it would have to appear
## before the leg begins it is on the road from the start.
func _plan_vehicle(vehicle: String, lane: int, speed: float, meet: float, direction: int = 1) -> Planned:
	var planned: Planned = Planned.new()
	vehicle = _fitting(vehicle)
	planned.vehicle = vehicle
	planned.lane = lane
	planned.change_to = lane
	planned.direction = direction
	planned.half_length = GameData.as_float(_data.record("vehicles", vehicle).get("length")) * 0.5
	planned.half_width = GameData.as_float(_data.record("vehicles", vehicle).get("width")) * 0.5
	_set_speed(planned, speed, meet)
	return planned


func _set_speed(planned: Planned, speed: float, meet: float) -> void:
	planned.speed = speed
	planned.closing = 1.0 - float(planned.direction) * speed / _par
	var horizon: float = _spawn_ahead_oncoming if planned.direction < 0 else _spawn_ahead
	planned.trigger = meet - horizon / planned.closing
	planned.ahead = horizon
	if planned.trigger <= 0.0:
		planned.trigger = 0.0
		planned.ahead = planned.closing * meet
	_refresh(planned)


## Works out again what is remembered about a vehicle, after its lane, speed
## or place has been set.
func _refresh(planned: Planned) -> void:
	planned.blocks_known = false
	planned.skill_blocks_known = false
	if planned.placed:
		_skill_touch(planned)
	planned.lanes_mask = _lane_bit(planned.lane) | _lane_bit(planned.change_to)
	planned.passed = _leg_length
	if planned.closing > 0.0:
		planned.passed = planned.progress_at(-(planned.half_length + _car_length * 0.5 + _margin))
	planned.skill_closing = 1.0 - float(planned.direction) * planned.speed / _skill_pace
	planned.skill_passed = _leg_length
	if planned.skill_closing > 0.0:
		planned.skill_passed = planned.progress_in(-_reach(planned, true), true)


func _lane_bit(lane: int) -> int:
	return 1 << (40 if lane == SHOULDER_LANE else lane + 1)


## A vehicle faster than third gear: it appears `ahead` in front when the
## player passes `trigger` and pulls away.
func _plan_fast(vehicle: String, lane: int, speed: float, trigger: float, ahead: float) -> Planned:
	var planned: Planned = Planned.new()
	planned.vehicle = vehicle
	planned.lane = lane
	planned.change_to = lane
	planned.half_length = GameData.as_float(_data.record("vehicles", vehicle).get("length")) * 0.5
	planned.half_width = GameData.as_float(_data.record("vehicles", vehicle).get("width")) * 0.5
	planned.speed = speed
	planned.closing = 1.0 - speed / _par
	planned.trigger = trigger
	planned.ahead = ahead
	_refresh(planned)
	return planned


## Adds a vehicle to the plan if it fits: nothing in its lane within the
## clearance (holding up whichever of two is the faster where that cures
## it), no CALM beat in its reach, and past him before the beats end.
func _place(planned: Planned) -> bool:
	var mark: int = _slowed.size()
	if not _settle(planned):
		return false
	if _out_of_bounds(planned):
		_undo_slowing(mark)
		return false
	_planned.append(planned)
	planned.placed = true
	_skill_touch(planned)
	return true


## Makes a new vehicle fit among those already planned. Two vehicles in one
## lane must never come within the clearance of each other before the player
## has passed both. Where they would, the faster of the two is slowed to the
## other's speed (it is "held up"; its place when the player passes it stays),
## and whatever that upsets is slowed in turn. Slowing only shortens a
## vehicle's block, so the planned line stays good. False, with every speed
## put back, if the vehicle cannot be made to fit.
func _settle(planned: Planned) -> bool:
	var mark: int = _slowed.size()
	var queue: Array[Planned] = [planned]
	var fits: bool = true
	var guard: int = 0
	while fits and not queue.is_empty():
		var a: Planned = queue.pop_back()
		var again: bool = true
		while fits and again:
			again = false
			guard += 1
			if guard > 400:
				fits = false
				break
			for index: int in _planned.size() + 1:
				var b: Planned = planned if index == _planned.size() else _planned[index]
				if (a.lanes_mask & b.lanes_mask) == 0 or b == a or not _conflict(a, b):
					continue
				var faster: Planned = a if a.speed > b.speed else b
				var slower: Planned = b if a.speed > b.speed else a
				if a.speed == b.speed or not _can_slow(faster, slower):
					fits = false
					break
				_slowed.append(faster)
				_slowed_speed.append(faster.speed)
				_slow_to(faster, slower.speed)
				if faster == a:
					# Start over for `a` at its new speed.
					again = true
					break
				queue.append(faster)
	if not fits:
		_undo_slowing(mark)
	return fits


## Gives back the speeds of everything slowed since `mark`.
func _undo_slowing(mark: int) -> void:
	for index: int in range(_slowed.size() - 1, mark - 1, -1):
		_slow_to(_slowed[index], _slowed_speed[index])
	_slowed.resize(mark)
	_slowed_speed.resize(mark)


## Can `faster` be held up at the speed of `slower`? Only ordinary traffic
## that keeps its lane. One the player catches keeps its place when he
## passes it, so the two must then be far enough apart; one faster than
## third gear keeps the place where it appears, and may only be held to
## another that is also faster than third gear.
func _can_slow(faster: Planned, slower: Planned) -> bool:
	if not faster.role.is_empty() or faster.changes_lane() or faster.direction < 0:
		return false
	if faster.closing > 0.0:
		return absf(faster.meet() - slower.meet()) * slower.closing >= faster.half_length + slower.half_length + _clearance
	return slower.closing <= 0.0


## Changes a vehicle's speed where it stands in the plan: one the player
## catches is still passed at the same place; one he never catches still
## appears at the same place.
func _slow_to(planned: Planned, speed: float) -> void:
	if planned.closing > 0.0:
		_set_speed(planned, speed, planned.meet())
	else:
		planned.speed = speed
		planned.closing = 1.0 - speed / _par
		_refresh(planned)


## Do two vehicles come within the clearance of each other in a lane they
## share, at any time from the moment both are on the road until the player
## has passed both?
func _conflict(a: Planned, b: Planned) -> bool:
	if a.direction != b.direction:
		return false
	return _conflict_in(a, b, false)


## The same in either frame, for two vehicles that each run free.
func _conflict_in(a: Planned, b: Planned, skill: bool) -> bool:
	var need: float = a.half_length + b.half_length + _clearance
	var until: float = minf(maxf(a.passed_in(skill), b.passed_in(skill)), _leg_length)
	if a.lane == a.change_to and b.lane == b.change_to:
		# Both keep their lane.
		if a.lane != b.lane:
			return false
		return _too_close(a, b, maxf(a.trigger, b.trigger), until, need, skill)
	for pass_index: int in 2:
		if pass_index == 1 and a.lane == a.change_to:
			break
		var lane: int = a.lane if pass_index == 0 else a.change_to
		if b.lane != lane and b.change_to != lane:
			continue
		var from: float = maxf(_enters(a, lane, skill), _enters(b, lane, skill))
		var to: float = minf(until, minf(_leaves(a, lane, skill), _leaves(b, lane, skill)))
		if _too_close(a, b, from, to, need, skill):
			return true
	return false


## Are two vehicles within `need` metres of each other, centre to centre, at
## any time while the player goes from `from` to `to`? Two that are pulling
## apart need only gen_min_gap between them: the one behind is never held up.
func _too_close(a: Planned, b: Planned, from: float, to: float, need: float, skill: bool) -> bool:
	if from > to:
		return false
	var first: float = a.gap_in(from, skill) - b.gap_in(from, skill)
	var last: float = a.gap_in(to, skill) - b.gap_in(to, skill)
	var room: float = need
	if (first > 0.0) == (last > 0.0) and absf(last) > absf(first) + EPSILON:
		room = a.half_length + b.half_length + _min_gap
	return not ((first >= room and last >= room) or (first <= -room and last <= -room))


## The player's progress from which a vehicle is in `lane`.
func _enters(planned: Planned, lane: int, skill: bool) -> float:
	if lane == planned.lane:
		return planned.trigger
	return _change_start(planned, skill)


## The player's progress at which a vehicle has left `lane` (INF: never).
func _leaves(planned: Planned, lane: int, skill: bool) -> float:
	if lane == planned.change_to:
		return INF
	return _change_end(planned, skill)


## The player's progress when a lane-changing vehicle starts to signal.
func _change_start(planned: Planned, skill: bool = false) -> float:
	if planned.closing_in(skill) <= 0.0:
		return INF
	return maxf(planned.progress_in(planned.change_gap, skill), planned.trigger)


func _change_end(planned: Planned, skill: bool = false) -> float:
	var signal_time: float = _late_signal_time if planned.late else _signal_time
	return _change_start(planned, skill) + (signal_time + _change_time) * (_skill_ms if skill else _par_ms)


## Metres ahead of or behind the player within which a vehicle is beside
## him: on the skill line he passes closer.
func _reach(planned: Planned, skill: bool = false) -> float:
	return planned.half_length + _car_length * 0.5 + (_skill_margin if skill else _margin)


## The stretches of the player's progress during which a vehicle is beside
## him, per lane: Vector3(lane, from, to). With `skill`, for a player who
## holds fourth gear: he gains on it faster, so he is level with it sooner
## and for less road, and he reaches some that third gear never does.
func _blocks_of(planned: Planned, skill: bool = false) -> Array[Vector3]:
	if skill:
		if _skill_dirty:
			_resolve_skill()
		if planned.skill_blocks_known:
			return planned.skill_blocks
	elif planned.blocks_known:
		return planned.blocks
	var out: Array[Vector3] = []
	if skill:
		planned.skill_blocks = out
		planned.skill_blocks_known = true
		if _in_skill_lane(planned):
			# Where it can be for him: from where he is level with it if it
			# has been held up all it can be, to where he is past it if not.
			var from_held: float = _skill_reaches(planned, _reach(planned, true), HELD)
			var to_free: float = _skill_reaches(planned, -_reach(planned, true), FREE)
			if from_held < INF and to_free > from_held:
				out.append(Vector3(float(planned.lane), from_held, to_free))
			return out
	else:
		planned.blocks = out
		planned.blocks_known = true
	if planned.lane == SHOULDER_LANE or planned.closing_in(skill) <= 0.0:
		return out
	var reach: float = _reach(planned, skill)
	var from: float = planned.progress_in(reach, skill)
	var to: float = planned.progress_in(-reach, skill)
	if planned.direction < 0:
		# The oncoming lane must be left well before an oncoming vehicle arrives.
		var clear: float = ((_skill_ms if skill else _par_ms) + planned.speed * KMH_TO_MS) * _tuning.f("gen_oncoming_clear_time")
		from = planned.progress_in(reach + clear, skill)
	if planned.changes_lane():
		var change_from: float = _change_start(planned, skill)
		var change_to: float = _change_end(planned, skill)
		if skill:
			# The skill line may run where the vehicle is not: in the lane it
			# leaves once it is clear of a car in that lane's middle, and in
			# the lane it moves to until it is nearly beside one there. It
			# signals, then moves across steadily (TrafficSim).
			var signal_time: float = _late_signal_time if planned.late else _signal_time
			var moves_from: float = change_from + signal_time * _skill_ms
			var across: float = absf(_lane_center(planned.change_to) - _lane_center(planned.lane))
			var beside: float = planned.half_width + _tuning.f("car_width") * 0.5 + _tuning.f("gen_skill_side_margin")
			change_to = moves_from + clampf(beside / across, 0.0, 1.0) * _change_time * _skill_ms
			change_from = moves_from + clampf((across - beside) / across, 0.0, 1.0) * _change_time * _skill_ms
		if minf(to, change_to) > from:
			out.append(Vector3(float(planned.lane), from, minf(to, change_to)))
		out.append(Vector3(float(planned.change_to), maxf(from, change_from), to))
	else:
		out.append(Vector3(float(planned.lane), from, to))
	return out


## True if a vehicle would be beside the player during a CALM beat, or still
## beside him when the beats end. Oncoming traffic keeps its own side of the
## road and is never in reach.
func _out_of_bounds(planned: Planned) -> bool:
	if planned.direction < 0:
		return false
	for block: Vector3 in _blocks_of(planned):
		if block.z > _beats_end or _in_calm(block.y, block.z) or _in_reserved(block.y, block.z):
			return true
	return false


## True where a boss has kept the road for itself.
func _in_reserved(from: float, to: float) -> bool:
	for entry: Variant in _reserved:
		var zone: Dictionary = GameData.as_dict(entry)
		var start: float = GameData.as_float(zone.get("s"))
		if to > start and from < start + GameData.as_float(zone.get("length")):
			return true
	return false


## The reserved stretches become zones of the plan: the planned line runs
## through each in its lane and in no other.
func _keep_reserved() -> void:
	for entry: Variant in _reserved:
		var zone: Dictionary = GameData.as_dict(entry).duplicate(true)
		var start: float = GameData.as_float(zone.get("s"))
		var length: float = GameData.as_float(zone.get("length"))
		_zones.append(zone)
		for other: int in _lanes:
			if other != GameData.as_int(zone.get("lane"), _start_lane):
				_fixed.append(Vector3(float(other), start, start + length))


func _in_calm(from: float, to: float) -> bool:
	for beat: Dictionary in _beats:
		if beat["type"] != "CALM":
			continue
		var start: float = beat["s"]
		var length: float = beat["length"]
		if to > start and from < start + length:
			return true
	return false


func _in_zone(from: float, to: float) -> bool:
	for zone: Dictionary in _zones:
		var start: float = zone["s"]
		var length: float = zone["length"]
		if to > start and from < start + length:
			return true
	return false


## True if nothing is beside the player's lane or any other from `from` to
## `to`: the stretch can be a CALM beat.
func _stretch_clear(from: float, to: float) -> bool:
	for planned: Planned in _planned:
		if planned.direction < 0:
			continue
		for block: Vector3 in _blocks_of(planned):
			if block.z > from and block.y < to:
				return false
	for block: Vector3 in _fixed:
		if block.z > from and block.y < to:
			return false
	for block: Vector3 in _par_fixed:
		if block.z > from and block.y < to:
			return false
	return true


## From the first start to the last end of the blocks added since the given
## sizes: Vector2(from, to). Nothing added: from is greater than to.
func _blocks_span(planned_from: int, fixed_from: int) -> Vector2:
	var span: Vector2 = Vector2(INF, -INF)
	for index: int in range(planned_from, _planned.size()):
		for block: Vector3 in _blocks_of(_planned[index]):
			span.x = minf(span.x, block.y)
			span.y = maxf(span.y, block.z)
	for index: int in range(fixed_from, _fixed.size()):
		span.x = minf(span.x, _fixed[index].y)
		span.y = maxf(span.y, _fixed[index].z)
	return span


func _hazard_reach(kind: String) -> float:
	var record: Dictionary = _data.record("hazard_kinds", kind)
	return GameData.as_float(record.get("length")) * 0.5 + _car_length * 0.5 + _margin


## Adds a hazard that closes `lane` around `s`. False if it reaches a CALM beat.
func _add_hazard(kind: String, s: float, x: float, lane: int) -> bool:
	var reach: float = _hazard_reach(kind)
	if _in_calm(s - reach, s + reach):
		return false
	_hazards.append({"kind": kind, "s": _round(s), "x": _round(x)})
	if lane != SHOULDER_LANE:
		_fixed.append(Vector3(float(lane), s - reach, s + reach))
	return true


# --- Zones: roadworks and the modifiers that need a stretch of road ----------

## Roadworks (GDD 9.1): chicanes one lane wide between cones. Each is a
## corridor that starts in one lane and shifts to its neighbour.
func _reserve_chicanes(special: Dictionary) -> void:
	var count: int = GameData.as_int(special.get("chicanes"))
	var length: float = GameData.as_float(special.get("length_m"))
	var width: float = GameData.as_float(special.get("width_m"))
	var spacing: float = GameData.as_float(special.get("cone_spacing_m"))
	var shift: float = GameData.as_float(special.get("shift_m"))
	var first_free: float = _tuning.f("first_event_within") + _tuning.f("calm_length")
	var slot: float = (_beats_end - first_free) / float(count)
	var lane: int = _start_lane
	for index: int in count:
		var s: float = roundf(first_free + slot * float(index) + _random.randf_range(0.0, maxf(slot - length - _tuning.f("calm_length"), 0.0)))
		var to_lane: int = lane + (1 if _random.randf() < 0.5 else -1)
		if to_lane < 0 or to_lane >= _lanes:
			to_lane = lane + (lane - to_lane)
		_zones.append({
			"kind": "chicane", "s": s, "length": length, "width": width,
			"from_lane": lane, "to_lane": to_lane, "shift": shift,
		})
		# Cones on both sides of the corridor: `width` of clear road between
		# them, clear of the corridor's two ends by the reach of a car's nose
		# and tail. The car does not turn as the corridor shifts, so there the
		# cones stand back by what its length sweeps sideways.
		var cone: Dictionary = _data.record("hazard_kinds", "cone")
		var half: float = width * 0.5 + GameData.as_float(cone.get("width")) * 0.5
		var straight: float = (length - shift) * 0.5
		var reach: float = _hazard_reach("cone") - _margin
		var slope: float = absf(_lane_center(to_lane) - _lane_center(lane)) / maxf(shift, 1.0)
		var count_cones: int = int((length - 2.0 * reach) / spacing) + 1
		for index_cone: int in count_cones:
			var along: float = reach + float(index_cone) * spacing
			var t: float = clampf((along - straight) / maxf(shift, 1.0), 0.0, 1.0)
			var center: float = lerpf(_lane_center(lane), _lane_center(to_lane), t)
			var outside: float = maxf(maxf(straight - along, along - straight - shift), 0.0)
			var swept: float = slope * clampf(reach - outside, 0.0, reach)
			_hazards.append({"kind": "cone", "s": _round(s + along), "x": _round(center - half - swept)})
			_hazards.append({"kind": "cone", "s": _round(s + along), "x": _round(center + half + swept)})
		# Inside a chicane only its corridor can be driven.
		for other: int in _lanes:
			if other != lane and other != to_lane:
				_fixed.append(Vector3(float(other), s, s + length))
		_fixed.append(Vector3(float(to_lane), s, s + straight))
		_fixed.append(Vector3(float(lane), s + straight + shift, s + length))
		lane = to_lane


## Sheep, the wedding and the melon truck each take a stretch of road of
## their own, laid out as a SPECIAL beat, with what belongs in it. `modifier`
## is the leg's own or a Twist's; `twist_at` (0 to 1) is where a Twist's goes
## instead of the modifier's own place.
func _reserve_zone(modifier: Dictionary, twist_at: float) -> bool:
	var id: String = GameData.as_string(modifier.get("id"))
	var kind: String = ""
	var length: float = 0.0
	var at: float = 0.0
	match id:
		"sheep":
			var flock: Dictionary = GameData.as_dict(modifier.get("flock"))
			kind = "flock"
			length = GameData.as_float(flock.get("zone_m"))
			at = GameData.as_float(flock.get("at"))
		"wedding":
			kind = "wedding"
			length = GameData.as_float(modifier.get("zone_m"))
			at = GameData.as_float(modifier.get("at"))
		"melon_truck":
			kind = "melon"
			length = _melon_zone_length(modifier)
			at = GameData.as_float(modifier.get("at"))
		_:
			return true
	if twist_at >= 0.0:
		at = twist_at
	var s: float = roundf(clampf(at * _beats_end + _random.randf_range(-60.0, 60.0),
			_tuning.f("first_event_within") + _tuning.f("calm_length"), _beats_end - length - _tuning.f("calm_length")))
	var zone: Dictionary = {"kind": kind, "s": s, "length": ceilf(length)}
	# Two stretches (the leg's own and a Twist's) keep a CALM beat's length
	# apart. A Twist asked for where there is no such room is left out of
	# this draw: the leg stands without it, and the plan names none.
	if twist_at >= 0.0 and _in_zone(s - _tuning.f("calm_length"), s + ceilf(length) + _tuning.f("calm_length")):
		return true
	_zones.append(zone)
	if twist_at >= 0.0:
		_twist_zone = zone
	match kind:
		"flock":
			return _place_flock(zone, modifier)
		"wedding":
			return _place_wedding(zone, modifier)
	return _place_melon_truck(zone, modifier)


## Sheep (GDD 9.4): a row across the road with one gap, walking toward the
## right. The gap is at a lane's centre when the player arrives at par.
func _place_flock(zone: Dictionary, modifier: Dictionary) -> bool:
	var flock: Dictionary = GameData.as_dict(modifier.get("flock"))
	var zone_s: float = zone["s"]
	var zone_length: float = zone["length"]
	var s: float = zone_s + zone_length * 0.5
	var speed: float = GameData.as_float(flock.get("speed_ms"))
	var approach: float = GameData.as_float(flock.get("approach_s"))
	var gap: float = GameData.as_float(flock.get("gap_m"))
	var pitch: float = GameData.as_float(flock.get("pitch_m"))
	var count: int = GameData.as_int(flock.get("count"))
	var sheep: Dictionary = _data.record("hazard_kinds", "sheep")
	var half_width: float = GameData.as_float(sheep.get("width")) * 0.5
	var gap_lane: int = _random.randi_range(0, _lanes - 1)
	var walked: float = speed * approach
	# Where the sheep stand before they start to walk.
	var gap_center: float = _lane_center(gap_lane) - walked
	var road_right: float = _lane_width * float(_lanes)
	var rail: float = road_right + _tuning.f("rumble_strip_width") + _tuning.f("shoulder_width")
	var car_width: float = _tuning.f("car_width")
	var xs: PackedFloat64Array = PackedFloat64Array()
	# To the right of the gap, as far as the shoulder stays closed on arrival.
	var x: float = gap_center + gap * 0.5 + half_width
	while xs.size() < count and x + walked + half_width < rail - car_width:
		xs.append(x)
		x += pitch
	if xs.size() < count:
		xs.append(x)
	# The rest to the left: the trailing end, which keeps the road closed longest.
	x = gap_center - gap * 0.5 - half_width
	while xs.size() < count:
		xs.append(x)
		x -= pitch
	xs.sort()
	var rounded: Array = []
	for value: float in xs:
		rounded.append(_round(value))
	_flock = {
		"kind": "sheep",
		"s": _round(s),
		"start_s": _round(s - approach * _par_ms),
		"speed": speed,
		"gap_lane": gap_lane,
		"xs": rounded,
	}
	var reach: float = _hazard_reach("sheep")
	for lane: int in _lanes:
		if lane != gap_lane:
			_fixed.append(Vector3(float(lane), s - reach, s + reach))
	return true


## The wedding (GDD 9.4): slow decorated cars, two abreast, in two lanes.
func _place_wedding(zone: Dictionary, modifier: Dictionary) -> bool:
	var cars: int = GameData.as_int(modifier.get("cars"))
	var across: int = clampi(GameData.as_int(modifier.get("lanes")), 1, _lanes - 1)
	var speed: float = GameData.as_float(modifier.get("speed_kmh"))
	var zone_s: float = zone["s"]
	var first_lane: int = _random.randi_range(0, _lanes - across)
	var closing: float = 1.0 - speed / _par
	var type: Dictionary = _data.record("vehicles", "wedding_car")
	var length: float = GameData.as_float(type.get("length"))
	var reach: float = (length * 0.5 + _car_length * 0.5 + _margin) / closing
	var row_step: float = (length + _clearance + 1.0) / closing
	for index: int in cars:
		var row: int = index / across
		var lane: int = first_lane + index % across
		var planned: Planned = _plan_vehicle("wedding_car", lane, speed, zone_s + reach + 2.0 + row_step * float(row))
		planned.role = "wedding"
		planned.counted = false
		if not _place(planned):
			return false
	return true


func _melon_zone_length(modifier: Dictionary) -> float:
	var speed: float = GameData.as_float(modifier.get("truck_speed_kmh"))
	var closing: float = 1.0 - speed / _par
	var type: Dictionary = _data.record("vehicles", "melon_truck")
	var reach: float = (GameData.as_float(type.get("length")) * 0.5 + _car_length * 0.5 + _margin) / closing
	var shed_gap: float = GameData.as_float(modifier.get("shed_gap_m"))
	# From the first melon to the truck itself.
	return (shed_gap / closing + reach) - (shed_gap - _hazard_reach("melon")) + 4.0


## The melon truck (GDD 9.4): it sheds melons for shed_s once the player is
## shed_gap_m behind it. They roll toward the right shoulder, so the lanes to
## the truck's left stay clear.
func _place_melon_truck(zone: Dictionary, modifier: Dictionary) -> bool:
	var speed: float = GameData.as_float(modifier.get("truck_speed_kmh"))
	var closing: float = 1.0 - speed / _par
	var shed_gap: float = GameData.as_float(modifier.get("shed_gap_m"))
	var shed_time: float = GameData.as_float(modifier.get("shed_s"))
	var zone_s: float = zone["s"]
	var melon_reach: float = _hazard_reach("melon")
	# The player's progress when the first melon falls, shed_gap ahead of him.
	var shed_from: float = zone_s + 2.0 - (shed_gap - melon_reach)
	var lane: int = _random.randi_range(1, _lanes - 1)
	var planned: Planned = _plan_vehicle("melon_truck", lane, speed, shed_from + shed_gap / closing)
	planned.role = "melon_truck"
	planned.counted = false
	if not _place(planned):
		return false
	var shed_to: float = shed_from + shed_time * _par_ms
	var last_gap: float = maxf(shed_gap - closing * (shed_to - shed_from), 0.0)
	# (Where they lie for a player in fourth gear: _resolve_skill.)
	for strewn: int in range(lane, _lanes):
		_par_fixed.append(Vector3(float(strewn), shed_from + shed_gap - melon_reach, shed_to + last_gap + melon_reach))
	_melons = {
		"kind": "melon",
		"shed_gap": shed_gap,
		"shed_s": shed_time,
		"every_s": GameData.as_float(modifier.get("melon_every_s")),
		"roll_ms": GameData.as_float(modifier.get("roll_ms")),
		"lane": lane,
	}
	return true


## Crosswind (GDD 9.4): a gust every gust_every_s at par.
func _add_crosswind() -> void:
	if GameData.as_string(_modifier.get("id")) != "crosswind":
		return
	var every: float = GameData.as_float(_modifier.get("gust_every_s")) * _par_ms
	var s: float = every
	while s < _beats_end:
		if not _in_calm(s - 1.0, s + 1.0):
			_gusts.append({"s": _round(s), "dir": -1 if _random.randf() < 0.5 else 1})
		s += every


# --- Two-lane (GDD 9.3) ------------------------------------------------------

## Oncoming vehicles every few seconds; slow trucks ahead in his lane, each
## met in the middle of a gap in the oncoming traffic long enough to pass it.
func _draw_two_lane(special: Dictionary) -> bool:
	var truck: String = GameData.as_string(special.get("truck"))
	var truck_speed: float = GameData.as_float(special.get("truck_speed_kmh"))
	var truck_every: Array = GameData.as_array(special.get("truck_every_m"))
	var oncoming_every: Array = GameData.as_array(special.get("oncoming_every_s"))
	var oncoming_speed: Array = GameData.as_array(special.get("oncoming_speed_kmh"))
	var every_low: float = GameData.as_float(oncoming_every[0]) * _par_ms
	var every_high: float = GameData.as_float(oncoming_every[1]) * _par_ms
	var types: Array[Dictionary] = _traffic_types()
	if types.is_empty():
		return false

	# Oncoming traffic, by where the player meets each vehicle.
	var free_from: PackedFloat64Array = PackedFloat64Array([0.0])
	var free_to: PackedFloat64Array = PackedFloat64Array()
	var meet: float = _random.randf_range(every_low, every_high)
	while meet < _leg_length:
		var type: Dictionary = types[_random.randi_range(0, types.size() - 1)]
		var speed: float = roundf(_random.randf_range(GameData.as_float(oncoming_speed[0]), GameData.as_float(oncoming_speed[1])))
		var planned: Planned = _plan_vehicle(GameData.as_string(type.get("id")), ONCOMING_LANE, speed, meet, -1)
		planned.counted = false
		if not _place(planned):
			return false
		var blocks: Array[Vector3] = _blocks_of(planned)
		free_to.append(blocks[0].y)
		free_from.append(blocks[0].z)
		meet += _random.randf_range(every_low, every_high)
	free_to.append(_leg_length)

	# Trucks, each in the middle of a gap.
	var closing: float = 1.0 - truck_speed / _par
	var truck_type: Dictionary = _data.record("vehicles", truck)
	var reach: float = (GameData.as_float(truck_type.get("length")) * 0.5 + _car_length * 0.5 + _margin) / closing
	var need: float = 2.0 * (reach + _change_length) + 2.0
	var last_end: float = _beats_end if not _detour else _leg_length - _change_length
	var next_from: float = _random.randf_range(GameData.as_float(truck_every[0]) * 0.5, GameData.as_float(truck_every[0]))
	for gap: int in free_from.size():
		var from: float = free_from[gap]
		var to: float = free_to[gap]
		var center: float = (from + to) * 0.5
		if to - from < need or center < next_from or center + reach + _change_length > last_end:
			continue
		var planned: Planned = _plan_vehicle(truck, 0, truck_speed, center)
		planned.counted = false
		if not _place(planned):
			continue
		next_from = center + _random.randf_range(GameData.as_float(truck_every[0]), GameData.as_float(truck_every[1]))
	return true


# --- Motorcade (GDD 9.3) -----------------------------------------------------

## Five cars that fill the road, and the side road that goes around them.
func _plan_motorcade(special: Dictionary) -> bool:
	var count: int = GameData.as_int(special.get("cars"))
	var row_gap: float = GameData.as_float(special.get("row_gap_m"))
	# Rows of two in the outer lanes, then the last car alone in the middle.
	# "ahead" is how far each car is in front of that last one.
	var cars: Array = []
	var rows: int = (count - 1) / 2
	for row: int in rows:
		var ahead: float = row_gap * float(rows - row)
		cars.append({"lane": 0, "ahead": _round(ahead)})
		cars.append({"lane": _lanes - 1, "ahead": _round(ahead)})
	while cars.size() < count - 1:
		cars.append({"lane": _lanes / 2, "ahead": _round(row_gap * float(rows + 1))})
	cars.append({"lane": _lanes / 2, "ahead": 0.0})

	var two_lane: Dictionary = _data.record("legs", "two_lane")
	var side: LegGenerator = LegGenerator.new()
	side._setup(_data, two_lane, _act, "")
	side._detour = true
	side._leg_length = GameData.as_float(special.get("detour_length_m"))
	side._beats_end = side._leg_length
	var side_seed: int = int(_random.randi())
	var attempt: int = 0
	var drawn: bool = false
	while not drawn and attempt < _tuning.i("gen_max_attempts"):
		side._random.seed = Rng.derive(side_seed, attempt + 1)
		drawn = side._draw()
		attempt += 1
	if not drawn:
		return false
	var side_plan: Dictionary = side._to_plan("two_lane", 0, attempt)
	_motorcade = {
		"vehicle": "motorcade_car",
		"speed": GameData.as_float(special.get("speed_kmh")),
		"start_ahead": GameData.as_float(special.get("start_ahead_m")),
		"keep_back": GameData.as_float(special.get("keep_back_m")),
		"cars": cars,
		"detour": {
			"at": GameData.as_float(special.get("detour_at_m")),
			"slip": GameData.as_float(special.get("detour_slip_m")),
			"length": side._leg_length,
			"lanes": side._lanes,
			"divided": side._divided,
			"spawns": side_plan["spawns"],
			"path": side_plan["path"],
		},
	}
	return true


# --- Density -----------------------------------------------------------------

func _counted() -> int:
	var count: int = 0
	for planned: Planned in _planned:
		if planned.counted:
			count += 1
	return count


## Adds single vehicles until the leg carries its density (GDD 9.1): some
## slow ones on their own, some queued behind a slow one, and the rest faster
## than third gear, which he never catches.
func _match_density(kind: String) -> bool:
	if _sparse or kind == "two_lane" or kind == "motorcade":
		# A sparse draw gives up on density; these two legs' traffic is their encounter.
		return true
	var count: int = _counted()
	if count > _density_goal:
		return false
	if not _whole_lines():
		return false
	var types: Array[Dictionary] = _traffic_types()
	if types.is_empty():
		return count == _density_goal
	var shares: PackedFloat64Array = _tuning.floats("gen_filler_shares")
	var missing: int = _density_goal - count
	var tries_each: int = _tuning.i("gen_filler_tries")

	# Slow vehicles on their own.
	var wanted: int = roundi(float(missing) * shares[1])
	var tries: int = tries_each * wanted
	while wanted > 0 and tries > 0:
		tries -= 1
		var planned: Planned = _draw_slow(types)
		if planned != null and _add_filler(planned):
			wanted -= 1
			count += 1

	# Queues: one more vehicle behind each slow one in turn, while any fits.
	wanted = roundi(float(missing) * shares[0])
	var queue_max: int = _tuning.i("gen_queue_max")
	var added: bool = true
	while wanted > 0 and added:
		added = false
		var leaders: Array[Planned] = []
		for planned: Planned in _planned:
			if not planned.queued and planned.direction > 0 and planned.lane >= 0 and planned.lane < _lanes \
					and not planned.changes_lane() and planned.closing > 0.0 and planned.role.is_empty() \
					and planned.queue.size() + 1 < queue_max:
				leaders.append(planned)
		while wanted > 0 and not leaders.is_empty():
			var pick: int = _random.randi_range(0, leaders.size() - 1)
			var leader: Planned = leaders[pick]
			leaders.remove_at(pick)
			var follower: Planned = _draw_follower(types, leader)
			if follower != null and _add_filler(follower):
				follower.queued = true
				leader.queue.append(follower)
				wanted -= 1
				count += 1
				added = true

	# The rest, and whatever could not be placed, pull away from him.
	tries = tries_each * (_density_goal - count)
	while count < _density_goal and tries > 0:
		tries -= 1
		var planned: Planned = _draw_fast(types)
		if planned != null and _add_filler(planned):
			count += 1
	return count == _density_goal


## Adds a vehicle drawn for density if it fits: room in its lane, no CALM
## beat or zone in its reach, and still a line through the leg.
func _add_filler(planned: Planned) -> bool:
	var mark: int = _slowed.size()
	if not _settle(planned):
		return false
	var allowed: bool = not _out_of_bounds(planned)
	var on_path: bool = false
	for block: Vector3 in _blocks_of(planned):
		if _in_zone(block.y, block.z):
			allowed = false
		if _path_uses(_line, int(block.x), block.y, block.z):
			on_path = true
	if not allowed:
		_undo_slowing(mark)
		return false
	_planned.append(planned)
	planned.placed = true
	_skill_touch(planned)
	var kept: bool = true
	if on_path:
		# It is on the planned line: keep it only if the line can go around it.
		var span: Vector2 = _blocks_span(_planned.size() - 1, _fixed.size())
		kept = _repair_path(_line, span.x, span.y, false)
	# And only if fourth gear still has a way through (rule 6).
	if not kept or not _skill_holds(false):
		_planned.pop_back()
		planned.placed = false
		_skill_touch(planned)
		_undo_slowing(mark)
		return false
	return true


## The vehicle a template names, or, on a road with a place it is too wide
## for (barriers across it), the widest of this act's traffic that fits: at
## the same place and speed, so the beat is what it was.
func _fitting(vehicle: String) -> String:
	if GameData.as_float(_data.record("vehicles", vehicle).get("width")) <= _max_width:
		return vehicle
	var best: String = vehicle
	var widest: float = -1.0
	for type: Dictionary in _traffic_types():
		var width: float = GameData.as_float(type.get("width"))
		if width > widest:
			widest = width
			best = GameData.as_string(type.get("id"))
	return best


## Ordinary traffic of this act.
func _traffic_types() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for type: Dictionary in _data.records("vehicles"):
		if type.has("traffic") and not GameData.as_bool(type.get("traffic")):
			continue
		if not GameData.as_array(type.get("acts")).has(float(_act)):
			continue
		if GameData.as_float(type.get("width")) > _max_width:
			# The road has a place it does not fit through (barriers).
			continue
		out.append(type)
	return out


## A vehicle queued behind `leader` and whatever already queues there, at the
## leader's speed.
func _draw_follower(types: Array[Dictionary], leader: Planned) -> Planned:
	if leader == null:
		return null
	var type: Dictionary = types[_random.randi_range(0, types.size() - 1)]
	var speeds: Array = GameData.as_array(type.get("speed_kmh"))
	if GameData.as_float(speeds[1]) < leader.speed:
		# It could not keep up, let alone be held up.
		return null
	var last: Planned = leader if leader.queue.is_empty() else leader.queue[leader.queue.size() - 1]
	var half_length: float = GameData.as_float(type.get("length")) * 0.5
	var behind: float = last.half_length + half_length + _clearance + 1.0
	var meet: float = last.meet() - behind / last.closing
	if meet < _first_within:
		return null
	return _plan_vehicle(GameData.as_string(type.get("id")), leader.lane, last.speed, meet)


## A vehicle on its own that the player catches in third gear. Most are put
## where the planned line is not.
func _draw_slow(types: Array[Dictionary]) -> Planned:
	var type: Dictionary = types[_random.randi_range(0, types.size() - 1)]
	var speeds: Array = GameData.as_array(type.get("speed_kmh"))
	var low: float = GameData.as_float(speeds[0])
	var high: float = minf(GameData.as_float(speeds[1]), _tuning.f("gen_filler_max_speed"))
	if low > high:
		return null
	var speed: float = roundf(_random.randf_range(low, high))
	var meet: float = _random.randf_range(_first_within, _beats_end)
	var lane: int = _random.randi_range(0, _lanes - 1)
	if _random.randf() >= _tuning.f("gen_path_filler_share"):
		var reach: float = (GameData.as_float(type.get("length")) * 0.5 + _car_length * 0.5 + _margin) / (1.0 - speed / _par)
		var free: PackedInt32Array = PackedInt32Array()
		for candidate: int in _lanes:
			if not _path_uses(_line, candidate, meet - reach, meet + reach):
				free.append(candidate)
		if not free.is_empty():
			lane = free[_random.randi_range(0, free.size() - 1)]
	return _plan_vehicle(GameData.as_string(type.get("id")), lane, speed, meet)


## A vehicle faster than third gear: it appears ahead and pulls away.
func _draw_fast(types: Array[Dictionary]) -> Planned:
	var span: PackedFloat64Array = _tuning.floats("gen_fast_speed")
	var able: Array[Dictionary] = []
	for candidate: Dictionary in types:
		var range_kmh: Array = GameData.as_array(candidate.get("speed_kmh"))
		if GameData.as_float(range_kmh[1]) >= span[0]:
			able.append(candidate)
	if able.is_empty():
		return null
	var type: Dictionary = able[_random.randi_range(0, able.size() - 1)]
	var speeds: Array = GameData.as_array(type.get("speed_kmh"))
	var low: float = maxf(GameData.as_float(speeds[0]), span[0])
	var high: float = minf(GameData.as_float(speeds[1]), span[1])
	if low > high:
		return null
	var speed: float = roundf(_random.randf_range(low, high))
	var lane: int = _random.randi_range(0, _lanes - 1)
	var trigger: float = _random.randf_range(0.0, _beats_end - _spawn_ahead)
	return _plan_fast(GameData.as_string(type.get("id")), lane, speed, trigger, _spawn_ahead)


# --- Rule 3: never a wall ----------------------------------------------------

## Both lines over the whole leg, from scratch. False if either has no way
## through: a wall in third (rule 3) or a sealed wall in fourth (rule 6).
func _whole_lines() -> bool:
	var path: Array = _search(_line, 0.0, _start_lane, _leg_length, ANY_LANE)
	if path.is_empty():
		return false
	_line.take(path)
	_line.target = _leg_length
	if _skill:
		if _skill_dirty:
			_resolve_skill()
		if not _skill_sound:
			return false
		var skill_path: Array = _search(_skill_line, 0.0, _start_lane, _leg_length, ANY_LANE)
		if skill_path.is_empty():
			return false
		_skill_line.take(skill_path)
		_skill_line.target = _leg_length
	return true


# --- Rule 6: never a sealed wall in fourth (D-074) ---------------------------
#
# A player who holds fourth gear meets the plan's vehicles at other places,
# and meets some that third gear never reaches: the ones faster than third
# gear. Those do not stay where a plan of free-running vehicles has them:
# with him gaining on them slowly, most come up behind a slower vehicle of
# their lane before he is there, and queue behind it (TrafficSim: a vehicle
# within traffic_follow_gap of the one ahead takes its speed). So the
# traffic of his frame is worked out lane by lane, as it will stand.
#
#   - A vehicle appears `ahead` in front of him when he passes its trigger
#     and runs free at its own speed.
#   - From the moment it is traffic_follow_gap behind the vehicle ahead of
#     it in its lane it keeps that distance, whatever that one does.
#   - Nothing overtakes within a lane, so the order in a lane is the order
#     in which its vehicles stood when the later of each two appeared.
#
# A vehicle that changes lane holds up what is behind it only until it has
# left. Rather than follow each vehicle through that, every lane is worked
# out twice: HELD, with those vehicles taken to stay in the lane they leave,
# and FREE, with them taken never to be there. More in the way only ever
# holds a vehicle further back, so each is somewhere between the two, and
# its block runs from where he is level with it in the one to where he is
# past it in the other.
#
# In the lane it moves into, such a vehicle joins the queue where it comes
# across (HELD; in FREE it is not there): what is behind it there may be
# held up by it.
#
# What that does not cover is kept from happening: no vehicle may appear
# within the clearance of where another can be then, nor move over into
# one; and one that changes lane must itself run free until he is past it.

## True for a vehicle that keeps its lane, going his way.
func _in_skill_lane(planned: Planned) -> bool:
	return planned.direction > 0 and planned.lane >= 0 and planned.lane < _lanes and not planned.changes_lane()


## Centre to centre, how far behind `holder` a vehicle it holds up stays.
func _held_back(planned: Planned, holder: Planned) -> float:
	return planned.half_length + holder.half_length + _follow_gap


## How far ahead of a player in fourth gear a vehicle is at `progress`, held
## up or not, in the HELD or the FREE working-out.
func _skill_gap(planned: Planned, progress: float, model: int) -> float:
	var offset: float = 0.0
	var vehicle: Planned = planned
	while vehicle.skill_holder[model] != null and progress >= vehicle.skill_catch[model]:
		offset += _held_back(vehicle, vehicle.skill_holder[model])
		vehicle = vehicle.skill_holder[model]
	return vehicle.gap_in(progress, true) - offset


## His progress in fourth gear at which a vehicle is first no more than
## `gap` ahead of him (INF: never). It runs free until it is held up, then
## moves as its holder does, and so on up the queue.
func _skill_reaches(planned: Planned, gap: float, model: int) -> float:
	var offset: float = 0.0
	var vehicle: Planned = planned
	var piece_from: float = planned.trigger
	while true:
		var piece_to: float = vehicle.skill_catch[model] if vehicle.skill_holder[model] != null else INF
		if piece_to > piece_from:
			if vehicle.skill_closing > 0.0:
				var at: float = maxf(vehicle.progress_in(gap + offset, true), piece_from)
				if at < piece_to:
					return at
			elif vehicle.gap_in(piece_from, true) - offset <= gap:
				return piece_from
		if vehicle.skill_holder[model] == null:
			break
		offset += _held_back(vehicle, vehicle.skill_holder[model])
		piece_from = maxf(piece_from, piece_to)
		vehicle = vehicle.skill_holder[model]
	return INF


## Where, from `from` on, `follower` comes up behind `leader`, the vehicle
## ahead of it in its lane.
func _skill_catch_up(follower: Planned, leader: Planned, from: float, model: int) -> void:
	follower.skill_catch[model] = _skill_catch_at(follower, leader, from, model)
	follower.skill_holder[model] = leader if follower.skill_catch[model] < INF else null


## His progress, from `from` on, at which `follower` is first _held_back
## behind where `leader` is (INF: never).
func _skill_catch_at(follower: Planned, leader: Planned, from: float, model: int) -> float:
	var offset: float = _held_back(follower, leader)
	var vehicle: Planned = leader
	var piece_from: float = maxf(from, maxf(follower.trigger, leader.trigger))
	while true:
		var piece_to: float = vehicle.skill_catch[model] if vehicle.skill_holder[model] != null else INF
		# On this piece the leader moves as `vehicle` does, `offset` less
		# what holds the follower back behind `vehicle`.
		var gaining: float = vehicle.skill_closing - follower.skill_closing
		if gaining > EPSILON and piece_to > piece_from:
			var at: float = (vehicle.ahead + vehicle.skill_closing * vehicle.trigger - offset
					- follower.ahead - follower.skill_closing * follower.trigger) / gaining
			at = maxf(at, piece_from)
			if at < piece_to:
				return at
		if vehicle.skill_holder[model] == null:
			break
		offset += _held_back(vehicle, vehicle.skill_holder[model])
		piece_from = maxf(piece_from, piece_to)
		vehicle = vehicle.skill_holder[model]
	return INF


## Entries of a lane's queue, [progress at which it is there, how far ahead
## it is then, the vehicle, true if it comes in from the next lane]: in the
## order they come.
static func _by_entry(a: Array, b: Array) -> bool:
	var a_at: float = a[0]
	var b_at: float = b[0]
	if a_at != b_at:
		return a_at < b_at
	var a_gap: float = a[1]
	var b_gap: float = b[1]
	return a_gap > b_gap


## His progress in fourth gear from which a vehicle that changes lane is in
## the way of the vehicles of the lane it moves into: when it has moved far
## enough across to be in front of the widest of them (INF: it never moves).
func _skill_joins_at(changer: Planned) -> float:
	var change_from: float = _change_start(changer, true)
	if change_from == INF:
		return INF
	var signal_time: float = _late_signal_time if changer.late else _signal_time
	var across: float = absf(_lane_center(changer.change_to) - _lane_center(changer.lane))
	var share: float = clampf((across - changer.half_width - _widest_half) / across, 0.0, 1.0)
	return change_from + (signal_time + share * _change_time) * _skill_ms


## The traffic of the lanes a vehicle is ever in has changed.
func _skill_touch(planned: Planned) -> void:
	_skill_dirty = true
	for lane: int in [planned.lane, planned.change_to]:
		if lane >= 0 and lane < _lanes:
			_skill_stale |= 1 << lane


func _skill_all_stale() -> void:
	_skill_dirty = true
	_skill_stale = (1 << _lanes) - 1


## Works out the traffic of fourth gear's frame, in the lanes where it has
## changed: who is held up behind whom and from where; and where the melons
## fall. _skill_sound is false if the plan's traffic would not stand as
## worked out.
func _resolve_skill() -> void:
	_skill_dirty = false
	if _skill_lanes.size() != _lanes:
		_skill_lanes = []
		_skill_lane_sound = PackedByteArray()
		for _lane: int in _lanes:
			_skill_lanes.append([])
			_skill_lane_sound.append(1)
		_skill_stale = (1 << _lanes) - 1
	var stale: int = _skill_stale
	_skill_stale = 0
	for lane: int in _lanes:
		if (stale & (1 << lane)) != 0:
			_skill_lanes[lane] = []
	var changers: Array[Planned] = []
	for planned: Planned in _planned:
		if planned.direction < 0 or planned.lane < 0 or planned.lane >= _lanes:
			continue
		if planned.changes_lane():
			changers.append(planned)
		if (stale & (1 << planned.lane)) != 0:
			planned.skill_catch[HELD] = INF
			planned.skill_catch[FREE] = INF
			planned.skill_holder[HELD] = null
			planned.skill_holder[FREE] = null
			planned.skill_blocks_known = false
			_skill_lanes[planned.lane].append(planned)
	_skill_sound = true
	for lane: int in _lanes:
		if (stale & (1 << lane)) != 0:
			_skill_lane_sound[lane] = 1 if _resolve_skill_lane(lane, changers) else 0
		if _skill_lane_sound[lane] == 0:
			_skill_sound = false
	_skill_fixed = []
	if not _skill_sound:
		return
	for index: int in changers.size():
		for other_index: int in range(index + 1, changers.size()):
			if (changers[index].lanes_mask & changers[other_index].lanes_mask) != 0 and _conflict_in(changers[index], changers[other_index], true):
				_skill_sound = false
				return

	# The melons lie from where the truck is when he comes within shed_gap of
	# it to where it is when the last has fallen (if he is not past it by then).
	if not _melons.is_empty():
		for planned: Planned in _planned:
			if planned.role != "melon_truck":
				continue
			var shed_gap: float = _melons["shed_gap"]
			var shed_time: float = _melons["shed_s"]
			var soonest: float = _skill_reaches(planned, shed_gap, HELD)
			var latest: float = _skill_reaches(planned, shed_gap, FREE)
			if soonest == INF or latest == INF:
				continue
			var melon_reach: float = _hazard_reach("melon")
			var first: float = soonest + shed_gap - planned.half_length
			var last: float = latest + shed_gap + planned.half_length + planned.speed * KMH_TO_MS * shed_time
			for strewn: int in range(planned.lane, _lanes):
				_skill_fixed.append(Vector3(float(strewn), first - melon_reach, last + melon_reach))


## One lane of fourth gear's frame: the vehicles that begin in it, and those
## of `changers` that move into it. False if one would appear on top of
## where another can be then, or too near it, or move over into one; or if
## one that changes lane would not run free until he is past it.
func _resolve_skill_lane(lane: int, changers: Array[Planned]) -> bool:
	var members: Array = _skill_lanes[lane]
	var joiners: Array[Planned] = []
	for changer: Planned in changers:
		if changer.change_to == lane and _skill_joins_at(changer) < changer.skill_passed:
			joiners.append(changer)
	var leaving: bool = false
	for entry: Variant in members:
		var member: Planned = entry
		if member.changes_lane():
			leaving = true
	var nobody: Array[Planned] = []
	if not _skill_queue(members, nobody, FREE):
		return false
	if not leaving and joiners.is_empty():
		# Nothing leaves this lane or comes into it: it can stand one way only.
		for entry: Variant in members:
			var member: Planned = entry
			member.skill_catch[HELD] = member.skill_catch[FREE]
			member.skill_holder[HELD] = member.skill_holder[FREE]
		return true
	if not _skill_queue(members, joiners, HELD):
		return false
	for entry: Variant in members:
		var member: Planned = entry
		if member.changes_lane() and member.skill_holder[HELD] != null \
				and member.skill_catch[HELD] < minf(member.skill_passed, _change_end(member, true)):
			return false
	return true


## Queues the vehicles of a lane behind one another as they come into it.
## FREE leaves out those that change lane; HELD takes those that leave it to
## stay, and takes in the `joiners` where each comes across.
func _skill_queue(members: Array, joiners: Array[Planned], model: int) -> bool:
	var entries: Array[Array] = []
	for entry: Variant in members:
		var member: Planned = entry
		if model == HELD or not member.changes_lane():
			entries.append([member.trigger, member.ahead, member, false])
	for joiner: Planned in joiners:
		var joins_at: float = _skill_joins_at(joiner)
		entries.append([joins_at, joiner.gap_in(joins_at, true), joiner, true])
	entries.sort_custom(_by_entry)
	# The vehicles of the lane as they stand, the one furthest ahead first;
	# and which of them came in from the next lane.
	var order: Array[Planned] = []
	var joined: Array[Planned] = []
	for entry: Array in entries:
		var since: float = entry[0]
		var ahead: float = entry[1]
		var joining: Planned = entry[2]
		var joins: bool = entry[3]
		var at: int = order.size()
		for index: int in order.size():
			var other: Planned = order[index]
			# One that appears keeps the clearance of the plan; one that
			# moves over must only not move over into another.
			var need: float = other.half_length + joining.half_length + (_min_gap if joins else _clearance)
			var gap: float = _skill_gap(other, since, model)
			# (In HELD the other may be anywhere up to where FREE has it.)
			var gap_free: float = gap if model == FREE else _skill_gap(other, since, FREE)
			if ahead > gap - need and ahead < gap_free + need:
				return false
			if at == order.size() and gap < ahead:
				at = index
			if gap_free < ahead - (joining.half_length + _longest_half + _clearance):
				# This one is well behind it, and the rest are behind this one.
				break
		order.insert(at, joining)
		if joins:
			joined.append(joining)
		# It, and what is behind it and not yet held up, may now be held up
		# sooner: front to back, each against the one ahead of it. One that
		# never comes up behind the one ahead, before or now, moves as it
		# did, and so does everything behind it.
		for index: int in range(maxi(at, 1), order.size()):
			var follower: Planned = order[index]
			if joined.has(follower):
				# One that has moved over must run free until he is past it:
				# then it moves as it did, whatever is ahead of it.
				if _skill_catch_at(follower, order[index - 1], since, model) < follower.skill_passed:
					return false
				if index > at:
					break
				continue
			if follower.skill_catch[model] <= since:
				continue
			var held_before: bool = follower.skill_holder[model] != null
			_skill_catch_up(follower, order[index - 1], since, model)
			if index > at and not held_before and follower.skill_holder[model] == null:
				break
	return true


## Rule 6 after the traffic has changed: it stands as the model has it, and
## the skill line is clear of it, or can be led around what now stands on it.
## False, with the line untouched, if not.
func _skill_holds(try_whole: bool) -> bool:
	if not _skill:
		return true
	if _skill_dirty:
		_resolve_skill()
	if not _skill_sound:
		return false
	var span: Vector2 = Vector2(INF, -INF)
	for planned: Planned in _planned:
		for block: Vector3 in _blocks_of(planned, true):
			if _path_uses(_skill_line, int(block.x), block.y, block.z):
				span.x = minf(span.x, block.y)
				span.y = maxf(span.y, block.z)
	for block: Vector3 in _fixed:
		if _path_uses(_skill_line, int(block.x), block.y, block.z):
			span.x = minf(span.x, block.y)
			span.y = maxf(span.y, block.z)
	for block: Vector3 in _skill_fixed:
		if _path_uses(_skill_line, int(block.x), block.y, block.z):
			span.x = minf(span.x, block.y)
			span.y = maxf(span.y, block.z)
	if span.y <= span.x:
		return true
	return _repair_path(_skill_line, span.x, span.y, try_whole)


## The lane the planned line is in at `s` (the lane it is moving to, during a change).
func _lane_on_path(s: float) -> int:
	var lane: int = _start_lane
	for index: int in _line.s.size():
		if _line.s[index] <= s:
			lane = _line.lane[index]
	return lane


## True if `line` is in `lane` anywhere from `from` to `to`.
func _path_uses(line: Line, lane: int, from: float, to: float) -> bool:
	for index: int in line.s.size():
		if line.lane[index] != lane:
			continue
		var held_from: float = line.s[index]
		var held_to: float = INF
		if index + 1 < line.s.size():
			held_to = line.s[index + 1] + line.change
		if to > held_from and from < held_to:
			return true
	return false


## Everything that closes a lane between `from` and `to`, as sorted and
## merged stretches per row: from, to, from, to... Row 0 is the oncoming
## lane, row 1 lane 0, and so on. With `skill`, for a player in fourth gear:
## the vehicles are where he meets them; what stands still is where it is.
func _closed_rows(skill: bool, from: float, to: float) -> Array[PackedFloat64Array]:
	var rows: Array[PackedVector2Array] = []
	for _row: int in _lanes + 1:
		rows.append(PackedVector2Array())
	for planned: Planned in _planned:
		for block: Vector3 in _blocks_of(planned, skill):
			var lane: int = int(block.x)
			if lane >= ONCOMING_LANE and lane < _lanes and block.z > block.y and block.z > from and block.y < to:
				rows[lane + 1].append(Vector2(block.y, block.z))
	for block: Vector3 in _fixed:
		var lane: int = int(block.x)
		if lane >= ONCOMING_LANE and lane < _lanes and block.z > block.y and block.z > from and block.y < to:
			rows[lane + 1].append(Vector2(block.y, block.z))
	for block: Vector3 in (_skill_fixed if skill else _par_fixed):
		var lane: int = int(block.x)
		if lane >= ONCOMING_LANE and lane < _lanes and block.z > block.y and block.z > from and block.y < to:
			rows[lane + 1].append(Vector2(block.y, block.z))
	var out: Array[PackedFloat64Array] = []
	for row: PackedVector2Array in rows:
		row.sort()
		var merged: PackedFloat64Array = PackedFloat64Array()
		for block: Vector2 in row:
			var last: int = merged.size() - 1
			if last >= 1 and block.x <= merged[last]:
				merged[last] = maxf(merged[last], block.y)
			else:
				merged.append(block.x)
				merged.append(block.y)
		out.append(merged)
	return out


## Makes a line good again after blocks were added between `from` and `to`.
## Only the part of the line around them is searched anew; if that fails and
## `try_whole` is set, the whole line. False, with the line untouched, if no
## line was found.
func _repair_path(line: Line, from: float, to: float, try_whole: bool) -> bool:
	# Through any zone that begins where the blocks end: its way in must stay open.
	var reach_to: float = to
	for zone: Dictionary in _zones:
		var zone_s: float = zone["s"]
		var zone_length: float = zone["length"]
		if zone_s <= to + 2.0 * line.change and zone_s + zone_length > reach_to:
			reach_to = zone_s + zone_length
	var target: float = minf(maxf(line.target, reach_to), _leg_length)
	# The last point before the blocks at which the line is settled in a lane.
	var first: int = 0
	for index: int in range(1, line.s.size()):
		if line.s[index] + line.change > from:
			break
		first = index
	var origin: float = 0.0 if first == 0 else line.s[first] + line.change
	# The first lane change that begins after the blocks.
	var last: int = -1
	for index: int in range(first + 1, line.s.size()):
		if line.s[index] >= to:
			last = index
			break
	var middle: Array = []
	if origin <= from:
		if last == -1:
			middle = _search(line, origin, line.lane[first], target, ANY_LANE)
		else:
			middle = _search(line, origin, line.lane[first], line.s[last], line.lane[last - 1])
	if middle.is_empty():
		if not try_whole:
			return false
		var whole: Array = _search(line, 0.0, _start_lane, target, ANY_LANE)
		if whole.is_empty():
			return false
		line.take(whole)
		line.target = target
		return true
	var path_s: PackedFloat64Array = line.s.slice(0, first + 1)
	var path_lane: PackedInt32Array = line.lane.slice(0, first + 1)
	for index: int in range(1, middle.size()):
		var entry: Array = middle[index]
		path_s.append(GameData.as_float(entry[0]))
		path_lane.append(GameData.as_int(entry[1]))
	if last != -1:
		path_s.append_array(line.s.slice(last))
		path_lane.append_array(line.lane.slice(last))
	line.s = path_s
	line.lane = path_lane
	line.target = target
	return true


## A line from `origin` in `origin_lane` to `target` that is never inside a
## block, ending in `goal_lane` (or ANY_LANE), with as few lane changes as
## possible, each made as late as it can be: [[s, lane], ...], the first
## entry the origin, then one where each lane change starts. Empty if there
## is none. A lane change needs both lanes free for the line's own length
## of one (gen_lane_change; gen_skill_lane_change on the skill line), and
## the blocks are those of the line's own frame.
func _search(line: Line, origin: float, origin_lane: int, target: float, goal_lane: int) -> Array:
	var closed: Array[PackedFloat64Array] = _closed_rows(line.skill, origin, target)
	var rows: int = _lanes + 1
	# The free stretches of each row are the nodes.
	var node_row: PackedInt32Array = PackedInt32Array()
	var node_from: PackedFloat64Array = PackedFloat64Array()
	var node_to: PackedFloat64Array = PackedFloat64Array()
	var row_first: PackedInt32Array = PackedInt32Array()
	for row: int in rows:
		row_first.append(node_row.size())
		if row == 0 and _divided:
			continue
		var blocks: PackedFloat64Array = closed[row]
		var cursor: float = origin
		var index: int = 0
		while index < blocks.size() and cursor < target:
			var from: float = blocks[index]
			var to: float = blocks[index + 1]
			if from > cursor + EPSILON:
				node_row.append(row)
				node_from.append(cursor)
				node_to.append(minf(from, target))
			cursor = maxf(cursor, to)
			index += 2
		if cursor < target:
			node_row.append(row)
			node_from.append(cursor)
			node_to.append(target)
	row_first.append(node_row.size())
	var count: int = node_row.size()

	var start: int = -1
	for node: int in range(row_first[origin_lane + 1], row_first[origin_lane + 2]):
		if node_from[node] <= origin + EPSILON:
			start = node
	if start == -1:
		return []

	# Pairs of free stretches in neighbouring rows long enough to change lane in.
	var edge_a: PackedInt32Array = PackedInt32Array()
	var edge_b: PackedInt32Array = PackedInt32Array()
	for row: int in rows - 1:
		var a: int = row_first[row]
		var b: int = row_first[row + 1]
		var a_end: int = row_first[row + 1]
		var b_end: int = row_first[row + 2]
		while a < a_end and b < b_end:
			if minf(node_to[a], node_to[b]) - maxf(node_from[a], node_from[b]) >= line.change - EPSILON:
				edge_a.append(a)
				edge_b.append(b)
			if node_to[a] < node_to[b]:
				a += 1
			else:
				b += 1

	# Earliest arrival in each stretch with at most k lane changes.
	var arrive: Array[PackedFloat64Array] = []
	var came_from: Array[PackedInt32Array] = []
	var first: PackedFloat64Array = PackedFloat64Array()
	first.resize(count)
	first.fill(INF)
	first[start] = origin
	var no_change: PackedInt32Array = PackedInt32Array()
	no_change.resize(count)
	no_change.fill(-1)
	arrive.append(first)
	came_from.append(no_change)
	var goal: int = -1
	var changes: int = 0
	while true:
		var now: PackedFloat64Array = arrive[changes]
		for node: int in count:
			if now[node] == INF or node_to[node] < target - EPSILON:
				continue
			if goal_lane != ANY_LANE:
				if node_row[node] == goal_lane + 1:
					goal = node
			elif goal == -1 or _goal_rank(node_row[node]) < _goal_rank(node_row[goal]):
				# His own side of the road first, then the lane nearest the start lane.
				goal = node
		if goal != -1 or changes >= MAX_CHANGES:
			break
		var next: PackedFloat64Array = now.duplicate()
		var via: PackedInt32Array = no_change.duplicate()
		var improved: bool = false
		for edge: int in edge_a.size():
			for way: int in 2:
				var from_node: int = edge_a[edge] if way == 0 else edge_b[edge]
				var to_node: int = edge_b[edge] if way == 0 else edge_a[edge]
				var ready: float = now[from_node]
				if ready == INF:
					continue
				var begin: float = maxf(maxf(node_from[from_node], node_from[to_node]), ready)
				var end: float = minf(node_to[from_node], node_to[to_node])
				if end - begin < line.change - EPSILON:
					continue
				if begin + line.change < next[to_node] - EPSILON:
					next[to_node] = begin + line.change
					via[to_node] = from_node
					improved = true
		if not improved:
			break
		arrive.append(next)
		came_from.append(via)
		changes += 1
	if goal == -1:
		return []

	# The stretches along the way, first to last.
	var chain: PackedInt32Array = PackedInt32Array([goal])
	var node: int = goal
	var layer: int = changes
	while layer > 0:
		var previous: int = came_from[layer][node]
		if previous != -1:
			chain.insert(0, previous)
			node = previous
		layer -= 1
	if chain[0] != start:
		return []

	# Each lane change as late as it can be made.
	var starts: PackedFloat64Array = PackedFloat64Array()
	starts.resize(chain.size())
	var limit: float = target
	for index: int in range(chain.size() - 1, 0, -1):
		var from_node: int = chain[index - 1]
		var to_node: int = chain[index]
		var window_from: float = maxf(node_from[from_node], node_from[to_node])
		var window_to: float = minf(minf(node_to[from_node], node_to[to_node]), limit)
		starts[index] = maxf(window_to - line.change, window_from)
		limit = starts[index]
	var path: Array = [[origin, node_row[chain[0]] - 1]]
	for index: int in range(1, chain.size()):
		path.append([starts[index], node_row[chain[index]] - 1])
	return path


func _goal_rank(row: int) -> int:
	if row == 0:
		return 1000
	return absi(row - 1 - _start_lane)


# --- Small things ------------------------------------------------------------

func _weighted(weights: PackedFloat64Array) -> int:
	var total: float = 0.0
	for weight: float in weights:
		total += weight
	var roll: float = _random.randf() * total
	for index: int in weights.size():
		roll -= weights[index]
		if roll < 0.0:
			return index
	return weights.size() - 1


## Millimetres are enough; rounding keeps the plan's text stable.
func _round(value: float) -> float:
	return snappedf(value, 0.001)
