class_name DriverBot
extends RefCounted
## The DriverBot (GDD 13.8, 12.5): it "plays through the simulation at the
## intent level: it sets the hand target, grip and gesture completion, with
## realistic durations. It does not synthesise mouse motion."
##
## It has one hand, like him. On the wheel, it steers; off it, the car goes
## where the road takes it. It sees what is on the road (as far as he can
## see), decides, and acts `reaction` seconds later.
##
##   Policy (GDD 13.8): keep the lane whose next obstacle is farthest;
##   change lane when time to collision falls below bot_ttc_change; let go
##   of the wheel only on a calm road with time for the most urgent pending
##   ritual plus the skill's margin.
##
## Three skills (tuning bot_*, in the order of SKILLS): reaction delay,
## lane-keeping error, the margin before letting go, the cruising gear.
## What the bot does with the brake and the hand goes into the DriveInput it
## is given; it changes nothing in the simulation but through that input,
## with one exception it says aloud: a gear is put in by `place_held` once
## the hand has held the lever for bot_shift_s (gesture completion).

const KMH_TO_MS: float = 1.0 / 3.6
const SKILLS: PackedStringArray = ["novice", "competent", "expert"]
const NO_LANE: int = -99
## What a Telling's seed is mixed with for the bot's own draws.
const SEED_SALT: int = 7700

var skill: String = "competent"
## Why it last wanted the brake, and what it saw (for a trace, with `debug`).
var why: String = ""
var view: String = ""
var debug: bool = false

# --- What it has done (for the balance runner) ---------------------------------
## Ticks on a road with the car moving, and those of them with no hand on the wheel.
var road_ticks: int = 0
var hand_off_ticks: int = 0
## Ticks on a road with his eyes shut or down.
var blind_ticks: int = 0
## Rituals done, by id; stops pulled in at; things bought.
var rituals: Dictionary = {}
var stops: int = 0
var bought: int = 0
## Whether it buys at stops (the runner sets it: GDD 12.5 "no purchases").
var buys: bool = true
## It pulls in at every stop, wanted or not (the smoke runs' driver).
var every_stop: bool = false

var _sim: DriveSim
var _data: GameData
var _tuning: Tuning
var _random: RandomNumberGenerator
var _index: int = 1

# The skill.
var _reaction_ticks: int = 0
var _lane_error: float = 0.0
var _margin: float = 0.0
var _cruise_gear: int = 3
var _brake_ttc: float = 0.0
## He reads the road: where the traffic leaves a way through (the plan's
## line), he takes that way when he can.
var _reads_road: bool = false
var _path_s: PackedFloat64Array = PackedFloat64Array()
var _path_lane: PackedInt32Array = PackedInt32Array()

# What it sees and decided; decisions wait in a ring for the reaction delay.
var _plan: Dictionary = {}
var _zones: Array[PackedFloat64Array] = []
var _target_lane: int = NO_LANE
var _lane_since: float = 0.0
var _room: PackedFloat64Array = PackedFloat64Array()
var _soon: PackedFloat64Array = PackedFloat64Array()
var _pace: PackedFloat64Array = PackedFloat64Array()
var _beside: PackedByteArray = PackedByteArray()
## The same, counting only what he would touch (for a move the way through
## asks for), and whether what is beside him is level with him or ahead.
var _tight: PackedByteArray = PackedByteArray()
var _beside_ahead: PackedByteArray = PackedByteArray()
var _ring_x: PackedFloat64Array = PackedFloat64Array()
var _ring_brake: PackedByteArray = PackedByteArray()
var _ring_at: int = 0
var _error: float = 0.0
var _want_gear: int = 3
var _fork_side: int = -1
var _takes_exit: bool = false
var _exit_decided: bool = false

# The hand: steps done one after the other; empty, it is on the wheel.
var _steps: Array[Array] = []
var _task: String = ""
var _crank_heading: float = 0.0
var _stood: float = 0.0
var _key_ticks: int = 0
var _shop_done: bool = false
var _stop_actions: int = 0
var _stop_tried: Dictionary = {}
var _horn_at: float = -INF
var _blind: bool = false
var _last_brake: bool = false
var _last_station: StringName = &""
## When each kind of task may be done again (seconds of the night).
var _not_before: Dictionary = {}
var _wiped_at: float = -INF


func _init(sim: DriveSim, data: GameData, skill_id: String = "competent", bot_seed: int = 1) -> void:
	_sim = sim
	_data = data
	_tuning = data.tuning
	skill = skill_id if SKILLS.has(skill_id) else "competent"
	_index = SKILLS.find(skill)
	_random = RandomNumberGenerator.new()
	_random.seed = bot_seed
	_reaction_ticks = maxi(roundi(_tuning.fi("bot_reaction_s", _index) / DriveSim.DT), 1)
	_lane_error = _tuning.fi("bot_lane_error_m", _index)
	_margin = _tuning.fi("bot_let_go_margin_s", _index)
	_cruise_gear = roundi(_tuning.fi("bot_cruise_gear", _index))
	_brake_ttc = _tuning.fi("bot_brake_ttc_s", _index)
	_reads_road = _tuning.fi("bot_reads_road", _index) > 0.5
	_ring_x.resize(_reaction_ticks)
	_ring_brake.resize(_reaction_ticks)


## What the hand is busy with ("" when it is on the wheel or free).
func task() -> String:
	return _task


# --- One tick ------------------------------------------------------------------

## One tick of driving, before the simulation's.
func drive(input: DriveInput) -> void:
	var car: CarSim = _sim.car
	if _sim.stopped:
		_at_a_stop(input)
		return
	_stood = 0.0
	_shop_done = false
	_stop_actions = 0
	_stop_tried = {}
	if _sim.wrecked or not _sim.leg.active or _sim.prologue.active:
		# (The prologue is his own, with both hands: GDD 10.1.)
		return
	if not is_same(_plan, _sim.leg.plan):
		_new_stretch()
	if _sim.pulled_over:
		_with_the_officer(input)
		return
	if car.speed > 1.0:
		road_ticks += 1
		if not _sim.hand.gripping and not _sim.left_hand_on_wheel():
			hand_off_ticks += 1

	# What he would do now...
	var want_x: float = car.x
	var brake: bool = false
	_want_gear = _cruise_gear_now()
	var boss: BossSim = _sim.boss
	if boss.active and boss.kind == BossSim.ARRIVAL:
		_want_gear = _tuning.i("start_gear")
		want_x = car.lane_center(0)
		_park_and_turn_the_key(input)
		_steer(input, want_x)
		if not _steps.is_empty() or boss.in_bay:
			return
		_hand(input)
		return
	if boss.active and boss.kind == BossSim.CHECKPOINT:
		_at_the_checkpoint(input)
		return
	# With his eyes shut (a blink, a nod) or down on what his hand is doing,
	# he sees nothing new: what he last meant to do stands, and the wheel
	# stays where it is.
	_blind = _sim.nerves.eyes_shut or _sim.hand.eyes_down
	if _blind:
		blind_ticks += 1
		input.rmb = _last_brake
		_hand(input)
		return
	var decided: Vector2 = _decide()
	want_x = decided.x
	brake = decided.y > 0.5
	# ...is what he does a reaction later.
	var then_x: float = _ring_x[_ring_at]
	var then_brake: bool = _ring_brake[_ring_at] != 0
	_ring_x[_ring_at] = want_x
	_ring_brake[_ring_at] = 1 if brake else 0
	_ring_at = (_ring_at + 1) % _reaction_ticks
	input.rmb = then_brake
	_last_brake = then_brake
	_steer(input, then_x)
	_hand(input)


## A new stretch of road: nothing decided yet.
func _new_stretch() -> void:
	_plan = _sim.leg.plan
	_target_lane = NO_LANE
	_lane_since = -INF
	_fork_side = -1
	_exit_decided = false
	_takes_exit = false
	for index: int in _reaction_ticks:
		_ring_x[index] = _sim.car.x
		_ring_brake[index] = 0
	_path_s = PackedFloat64Array()
	_path_lane = PackedInt32Array()
	for entry: Variant in GameData.as_array(_plan.get("path")):
		var pair: Array = GameData.as_array(entry)
		_path_s.append(GameData.as_float(pair[0]))
		_path_lane.append(GameData.as_int(pair[1]))
	_zones = []
	var lane_width: float = _sim.car.lane_width()
	for entry: Variant in GameData.as_array(_plan.get("zones")):
		var zone: Dictionary = GameData.as_dict(entry)
		if GameData.as_string(zone.get("kind")) != "chicane":
			continue
		var start: float = GameData.as_float(zone.get("s"))
		var length: float = GameData.as_float(zone.get("length"))
		var shift: float = GameData.as_float(zone.get("shift"))
		var straight: float = (length - shift) * 0.5
		_zones.append(PackedFloat64Array([start, start + straight, start + straight + shift, start + length,
				lane_width * (float(GameData.as_int(zone.get("from_lane"))) + 0.5), lane_width * (float(GameData.as_int(zone.get("to_lane"))) + 0.5)]))


# --- Seeing and deciding --------------------------------------------------------

## Where across the road he wants the car, and whether he wants the brake
## (y > 0.5): Vector2(x, brake).
func _decide() -> Vector2:
	var car: CarSim = _sim.car
	var now: float = _sim.seconds()
	var lanes: int = car.lanes
	var lane: int = clampi(car.lane_of(car.x), 0, lanes - 1)
	if _target_lane == NO_LANE or _target_lane >= lanes:
		_target_lane = lane
	# A slip lane is no lane to drive in: it is for whoever takes the Exit.
	var through: int = mini(lanes, GameData.as_int(_plan.get("lanes"), lanes)) if not _sim.leg.on_side_road else lanes
	var look: float = _sight()
	var speed_ms: float = car.speed * KMH_TO_MS

	# Between cones there is one way through.
	for zone: PackedFloat64Array in _zones:
		if car.s >= zone[0] - look * 0.5 and car.s <= zone[3]:
			var x: float = lerpf(zone[4], zone[5], clampf((car.s - zone[1]) / maxf(zone[2] - zone[1], 0.001), 0.0, 1.0))
			_target_lane = clampi(car.lane_of(x), 0, lanes - 1)
			return Vector2(x, 1.0 if _must_brake(x, look) else 0.0)
	# Dawn's barriers: the middle lane, at their pace.
	var boss: BossSim = _sim.boss
	if boss.active and boss.kind == BossSim.DAWN:
		var corridor: Vector3 = boss.corridor()
		if corridor.z > corridor.x and car.s > corridor.x - look and car.s < corridor.z:
			var middle: float = car.lane_center(lanes / 2)
			_target_lane = lanes / 2
			return Vector2(middle, 1.0 if _must_brake(middle, look) or _over_the_limit() else 0.0)

	# The lanes: how far the next thing in each is, and how soon.
	_scan(look)
	var room: PackedFloat64Array = _room
	var soon: PackedFloat64Array = _soon
	var beside: PackedByteArray = _beside
	var line: int = _line_lane(car.s + speed_ms * _tuning.f("bot_line_lead_s"))

	# The oncoming lane (GDD 9.3, Two-lane): out when the way through goes
	# out and nobody comes for as long as the pass takes; back when it comes
	# back, or sooner if somebody comes.
	if not car.divided and _reads_road:
		var back_in: float = (_line_back_at(car.s) - car.s) / maxf(speed_ms, 1.0)
		var coming: float = _oncoming_in()
		if _target_lane == -1:
			if (line != -1 or coming < back_in + _tuning.f("bot_oncoming_margin_s")) and beside[0] == 0:
				_target_lane = 0
				_lane_since = now
			var out_x: float = car.lane_center(_target_lane)
			return Vector2(out_x, 1.0 if _must_brake(out_x, look) else 0.0)
		if line == -1 and _target_lane == 0 and coming > back_in + _tuning.f("bot_oncoming_margin_s") and car.speed >= _tuning.fi("gear_speeds", 2) - 5.0:
			_target_lane = -1
			_lane_since = now
			return Vector2(car.lane_center(-1), 0.0)

	# The Exit and the fork have the last word on the lane.
	var forced: int = _lane_for_the_road_ahead(lanes)
	if forced == NO_LANE and _target_lane >= through:
		forced = through - 1
	var current: int = _target_lane
	var change_ttc: float = _tuning.f("bot_ttc_change_s")
	var gain: float = _tuning.f("bot_lane_gain_s")
	var wanted: int = current
	var waiting: bool = false
	if forced != NO_LANE:
		wanted = current + signi(forced - current)
		if wanted != current and (beside[wanted] != 0 or soon[wanted] < change_ttc):
			# Somebody is there: he lets them by first.
			waiting = _beside_ahead[wanted] != 0 or soon[wanted] < change_ttc
			wanted = current
	elif line != NO_LANE and line >= 0 and line < through and line != current and soon[current] >= _brake_ttc \
			and _tight[current + signi(line - current)] == 0 and soon[current + signi(line - current)] >= _brake_ttc:
		# He reads the road: the way through moves over, and so does he.
		wanted = current + signi(line - current)
	else:
		# "Keep the lane whose next obstacle is farthest": farthest in time,
		# at the pace he means to keep, of all the lanes and not only the
		# next one. He goes for a lane that gives him bot_lane_gain_s more
		# once the thing ahead is within bot_lane_look_s, and at once, for
		# any that is better, when the time to collision is under
		# bot_ttc_change_s. On the way through he stays unless he must go.
		var cruise: float = _tuning.fi("gear_speeds", clampi(_want_gear, 1, 5) - 1)
		var urgent: bool = soon[current] < change_ttc
		var own_time: float = _time_to(current, cruise)
		var best: int = current
		var best_time: float = own_time
		for other: int in through:
			if other == current:
				continue
			var time: float = _time_to(other, cruise)
			if time > best_time + (0.0 if urgent else gain):
				best = other
				best_time = time
		if best != current and (urgent or (own_time < _tuning.f("bot_lane_look_s") and line != current)) \
				and (urgent or now - _lane_since >= _tuning.f("bot_lane_hold_s")):
			var next: int = current + signi(best - current)
			if beside[next] == 0 and soon[next] >= change_ttc:
				wanted = next
			elif own_time < _tuning.f("bot_lane_wait_s") and _beside_ahead[next] != 0:
				# Boxed in: he drops back behind what is beside him.
				waiting = true
	if debug:
		view = "line %d cur %d want %d forced %d room %s soon %s beside %s" % [line, current, wanted, forced, str(room), str(soon), str(beside)]
	if wanted != _target_lane:
		_target_lane = wanted
		_lane_since = now
		_wants_to_indicate(wanted - current)
	var x: float = car.lane_center(_target_lane)
	why = ""
	# He keeps his distance behind what he means to stay behind; what the
	# way through is about to take him round, he only does not hit.
	var settled: bool = _target_lane == lane and (line == NO_LANE or _line_lane(car.s + _tuning.f("bot_line_ahead_m")) == lane)
	var brake: bool = _must_brake(x, look, settled)
	if not brake and settled and soon[lane] < _brake_ttc:
		brake = true
		why = "ttc %.1f" % soon[lane]
	# Waiting for a lane he has to have, he drops behind what is in it.
	if waiting and car.speed > _tuning.fi("gear_speeds", 0):
		brake = true
		why = "waiting for a lane"
	# Into a stall at exit_max_speed or less (GDD 9.5).
	var slip: Vector2 = _sim.exit_slip()
	if _takes_exit and slip.x >= 0.0 and car.s >= slip.x and car.speed > _tuning.f("exit_max_speed") - 2.0:
		brake = true
	if speed_ms <= 0.0:
		brake = false
	return Vector2(x, 1.0 if brake else 0.0)


## How far he sees the road, m: as far as he looks, less where less can be
## seen (night, dust), and less again through what is on the glass and in
## his eyes: Haze, rain between two sweeps of the wipers, Glare, his Lids
## (GDD 5.8). Never less than bot_sight_min_m.
func _sight() -> float:
	var clear: float = (1.0 - _sim.items.haze) * (1.0 - _sim.items.rain_blur() * _tuning.f("bot_blur_blinds")) \
			* (1.0 - _sim.glare() * _tuning.f("bot_glare_blinds")) * (1.0 - 2.0 * _sim.nerves.lids)
	return maxf(minf(_tuning.f("bot_look_ahead_m"), _sim.visibility()) * clampf(clear, 0.0, 1.0), _tuning.f("bot_sight_min_m"))


## Fills, for each lane, the road that is clear ahead in it (m), the time
## until he would be at what is in it (s), how fast that is going (km/h),
## and whether something is beside him there.
func _scan(look: float) -> void:
	var car: CarSim = _sim.car
	var lanes: int = car.lanes
	_room.resize(lanes)
	_soon.resize(lanes)
	_pace.resize(lanes)
	_beside.resize(lanes)
	_tight.resize(lanes)
	_beside_ahead.resize(lanes)
	for index: int in lanes:
		_room[index] = look
		_soon[index] = INF
		_pace[index] = INF
		_beside[index] = 0
		_tight[index] = 0
		_beside_ahead[index] = 0
	var room: PackedFloat64Array = _room
	var soon: PackedFloat64Array = _soon
	var beside: PackedByteArray = _beside
	var half_lane: float = car.lane_width() * 0.5
	var car_half: float = car.length() * 0.5
	var side_room: float = _tuning.f("bot_side_clear_m")
	for vehicle: TrafficSim.Vehicle in _sim.traffic.vehicles:
		if vehicle.off_road:
			continue
		for index: int in lanes:
			var centre: float = car.lane_center(index)
			var in_lane: bool = absf(vehicle.x - centre) < half_lane + vehicle.half_width - 0.3
			if not in_lane and (vehicle.changing or vehicle.signalling != 0):
				in_lane = absf(vehicle.change_to_x - centre) < half_lane
			if not in_lane:
				continue
			var gap: float = vehicle.s - car.s
			var closing: float = (car.speed - float(vehicle.direction) * vehicle.speed) * KMH_TO_MS
			var reach: float = vehicle.half_length + car_half
			if gap > reach:
				# Ahead of him: so much road, and so soon.
				var clear: float = gap - reach
				if clear < room[index]:
					room[index] = clear
					_pace[index] = float(vehicle.direction) * vehicle.speed
				if closing > 0.0:
					soon[index] = minf(soon[index], clear / closing)
			if gap > -reach - side_room - maxf(-closing, 0.0) * _tuning.f("bot_ttc_change_s") and gap <= reach + side_room:
				# Level with him, just ahead, or behind and coming up.
				beside[index] = 1
				if gap > -reach:
					_beside_ahead[index] = 1
				if absf(gap) < reach + _tuning.f("bot_tight_m"):
					_tight[index] = 1
	var speed_ms: float = maxf(car.speed * KMH_TO_MS, 0.1)
	for hazard: Dictionary in _sim.leg.hazards_near(0.0, look):
		var x: float = GameData.as_float(hazard.get("x"))
		var ahead: float = GameData.as_float(hazard.get("ahead"))
		if GameData.as_bool(hazard.get("hit")) or _in_a_zone(car.s + ahead):
			continue
		for index: int in lanes:
			if absf(x - car.lane_center(index)) < half_lane:
				if maxf(ahead - car_half, 0.0) < room[index]:
					_pace[index] = 0.0
				room[index] = minf(room[index], maxf(ahead - car_half, 0.0))
				soon[index] = minf(soon[index], maxf(ahead - car_half, 0.0) / speed_ms)


## The lane the way through the traffic is in at `s` (NO_LANE: he does not
## read the road, or it has none).
func _line_lane(s: float) -> int:
	if not _reads_road or _path_s.is_empty() or _sim.leg.on_side_road:
		return NO_LANE
	# The way through is where the traffic leaves room at third gear's
	# pace. Much faster than that, he is on his own.
	if _sim.car.speed > _tuning.fi("gear_speeds", 2) + _tuning.f("bot_line_over_kmh"):
		return NO_LANE
	var lane: int = _path_lane[0]
	for index: int in _path_s.size():
		if _path_s[index] <= s:
			lane = _path_lane[index]
	return lane


## Where the way through comes back from the oncoming lane, after `s`.
func _line_back_at(s: float) -> float:
	for index: int in _path_s.size():
		if _path_s[index] > s and _path_lane[index] >= 0:
			return _path_s[index] + _tuning.f("gen_lane_change")
	return s


## Seconds until the next oncoming vehicle is at the car (INF: none in sight).
func _oncoming_in() -> float:
	var car: CarSim = _sim.car
	var least: float = INF
	for vehicle: TrafficSim.Vehicle in _sim.traffic.vehicles:
		if vehicle.direction >= 0 or vehicle.off_road or vehicle.s <= car.s:
			continue
		var gap: float = vehicle.s - car.s - vehicle.half_length - car.length() * 0.5
		least = minf(least, maxf(gap, 0.0) / maxf((car.speed + vehicle.speed) * KMH_TO_MS, 0.1))
	return least


## Seconds until he would be at the next thing in a lane, at `cruise` km/h
## (never more than bot_lane_far_s: beyond that a lane is as good as clear).
func _time_to(lane: int, cruise: float) -> float:
	var far: float = _tuning.f("bot_lane_far_s")
	var closing: float = (cruise - _pace[lane]) * KMH_TO_MS
	if closing <= 0.1:
		return far
	return minf(_room[lane] / closing, far)


func _in_a_zone(s: float) -> bool:
	for zone: PackedFloat64Array in _zones:
		if s >= zone[0] - 1.0 and s <= zone[3] + 1.0:
			return true
	return false


## True when what is ahead where he is going is nearer than he needs to
## slow to its speed.
func _must_brake(x: float, look: float, settled: bool = true) -> bool:
	var car: CarSim = _sim.car
	var decel: float = _tuning.f("brake_decel") * KMH_TO_MS
	var keep: float = _tuning.f("bot_keep_gap_m")
	var late: float = float(_reaction_ticks) * DriveSim.DT
	# A Tailgater on the bumper rams whoever brakes (GDD 9.3).
	var rammed: bool = _sim.encounter.tail_phase == EncounterSim.TAIL_ON_BUMPER
	for vehicle: TrafficSim.Vehicle in _sim.traffic.vehicles:
		if vehicle.off_road or vehicle.direction < 0 or vehicle.s <= car.s:
			continue
		var beside_now: bool = absf(vehicle.x - car.x) >= vehicle.half_width + car.half_width() + 0.2
		var beside_then: bool = absf(vehicle.x - x) >= vehicle.half_width + car.half_width() + 0.2
		if (vehicle.changing or vehicle.signalling != 0) and absf(vehicle.change_to_x - car.x) < vehicle.half_width + car.half_width() + 0.2:
			# It is coming into his lane.
			beside_now = false
		if beside_now and beside_then:
			continue
		var gap: float = vehicle.s - vehicle.half_length - car.s - car.length() * 0.5
		if gap > look:
			continue
		var closing: float = (car.speed - vehicle.speed) * KMH_TO_MS
		if gap < keep and closing > -2.0:
			why = "close to %d" % vehicle.id
			return true
		# He keeps his distance behind what he follows (the brake stays on
		# until the gap is opening again), and brakes in time for what he
		# comes up on.
		var distance: float = keep + car.speed * KMH_TO_MS * _tuning.fi("bot_headway_s", _index)
		if settled and gap < distance and closing > -1.0 and not rammed:
			why = "behind %d (%s) gap %.0f keeps %.0f" % [vehicle.id, vehicle.type_id, gap, distance]
			return true
		if closing <= 0.0:
			continue
		var needed: float = keep + closing * closing / (2.0 * decel) + closing * late
		if settled:
			needed = distance + closing * closing / (2.0 * decel) + closing * late
		if gap < needed and not (rammed and gap > keep):
			why = "behind %d (%s) gap %.0f need %.0f closing %.1f" % [vehicle.id, vehicle.type_id, gap, needed, closing]
			return true
	return false


func _over_the_limit() -> bool:
	var boss: BossSim = _sim.boss
	var corridor: Vector3 = boss.corridor()
	var limit: float = _tuning.fi("gear_speeds", 1)
	var car: CarSim = _sim.car
	if car.speed <= limit:
		return false
	var over: float = (car.speed * car.speed - limit * limit) * KMH_TO_MS / (2.0 * _tuning.f("brake_decel"))
	return corridor.y - car.s <= over + car.speed * KMH_TO_MS * (float(_reaction_ticks) + 2.0) * DriveSim.DT


## The lane the road ahead asks for: the slip lane of an Exit he takes, the
## side of a fork he chose. NO_LANE when it asks for none.
func _lane_for_the_road_ahead(lanes: int) -> int:
	var car: CarSim = _sim.car
	var run: RunState = _sim.run
	_fork_side = -1
	if not run.active:
		return NO_LANE
	var slip: Vector2 = _sim.exit_slip()
	if slip.x >= 0.0:
		if not _exit_decided and car.s >= slip.x - _tuning.f("bot_look_ahead_m"):
			_exit_decided = true
			_takes_exit = _wants_the_stop()
		if _takes_exit and car.s >= slip.x:
			return lanes - 1
		if _takes_exit and car.s >= slip.x - _tuning.f("bot_look_ahead_m") * 0.5:
			return maxi(lanes - 2, 0)
		return NO_LANE
	if run.splits_ahead() and _sim.leg.length - car.s < _tuning.f("bot_look_ahead_m") * 0.5:
		_fork_side = _side_of_the_fork()
		return 0 if _fork_side == RunState.LEFT else lanes - 1
	return NO_LANE


## Whether he pulls in at the stop this leg ends at.
func _wants_the_stop() -> bool:
	var stop_id: String = GameData.as_string(_sim.run.branch.get("stop"))
	if not _data.has_record("stops", stop_id):
		return false
	if every_stop:
		return true
	# The Clock (GDD 6.4): no stop he has not the minutes for. What is still
	# to drive is the legs and bosses ahead at their pars.
	var record: Dictionary = _data.record("stops", stop_id)
	if _minutes_in_hand() < GameData.as_float(record.get("clock_min")) + _tuning.f("bot_clock_reserve_min"):
		return false
	var service: String = GameData.as_string(record.get("service"))
	match service:
		"tea":
			return _sim.nerves.value >= _tuning.f("bot_tea_nerves") or _sim.nerves.value < _sim.heavy_floor()
		"repair":
			return _sim.faults.lamps > 0 and _sim.cash >= _tuning.f("repair_price")
		"shop":
			return buys and _sim.cash >= _tuning.f("bot_shop_cash")
		"find":
			return buys
	return false


## Game minutes he can still spend standing: what is left of the night less
## what is left of the road, at par (three legs and a boss to an act, the
## boss counted as a leg and a half).
func _minutes_in_hand() -> float:
	var run: RunState = _sim.run
	var legs_left: float = float((RunGenerator.ACTS - run.act) * 3 + maxi(2 - run.legs_done, 0)) + 1.5 * float(RunGenerator.ACTS - run.act + 1)
	var par_minutes: float = _tuning.f("leg_length") / (_tuning.fi("gear_speeds", 2) * KMH_TO_MS) * _tuning.f("clock_scale") / 60.0
	return _sim.clock.minutes_left() - legs_left * par_minutes


## The side of the fork he takes: toward the stop he needs, else the leg
## with nothing extra on it, else the left.
func _side_of_the_fork() -> int:
	var best: int = RunState.LEFT
	var best_score: float = -INF
	for side: int in _sim.run.branches.size():
		var branch: Dictionary = _sim.run.branches[side]
		var score: float = 0.0
		var stop_id: String = GameData.as_string(branch.get("stop"))
		var service: String = GameData.as_string(_data.record("stops", stop_id).get("service")) if _data.has_record("stops", stop_id) else ""
		if service == "repair" and _sim.faults.lamps > 0:
			score += 3.0
		if service == "tea" and _sim.nerves.value >= _tuning.f("bot_tea_nerves"):
			score += 2.0
		if not GameData.as_string(branch.get("modifier")).is_empty():
			score -= 1.0
		var leg: Dictionary = _data.record("legs", GameData.as_string(branch.get("leg"))) if _data.has_record("legs", GameData.as_string(branch.get("leg"))) else {}
		if leg.get("special") != null:
			score -= 1.0
		if score > best_score:
			best_score = score
			best = side
	return best


## The gear he wants to be in now.
func _cruise_gear_now() -> int:
	var car: CarSim = _sim.car
	var boss: BossSim = _sim.boss
	var gear: int = mini(_cruise_gear, 3)
	if _cruise_gear >= 4 and _sim.nerves.value <= _tuning.f("bot_fourth_nerves") and not _sim.suspicion.watching \
			and not _sim.leg.raining and _sim.visibility() >= _tuning.f("bot_look_ahead_m") and not boss.active:
		# Fourth on a road that is clear as far as he sees; back to third
		# when something in his lane is within bot_lane_look_s.
		var lane: int = clampi(car.lane_of(car.x), 0, car.lanes - 1)
		var own: float = _time_to(lane, _tuning.fi("gear_speeds", 3)) if lane < _room.size() else 0.0
		if own >= _tuning.f("bot_lane_far_s") or (_sim.gate.gear == 4 and own >= _tuning.f("bot_lane_look_s")):
			gear = 4
	if boss.active and boss.kind == BossSim.DAWN:
		var corridor: Vector3 = boss.corridor()
		if corridor.z > corridor.x and car.s > corridor.y - 60.0 and car.s < corridor.z:
			gear = 2
	var slip: Vector2 = _sim.exit_slip()
	if _takes_exit and slip.x >= 0.0 and car.s >= slip.x - 60.0:
		gear = 2
	if _sim.encounter.kind == "motorcade" and _sim.encounter.glare > 0.0:
		gear = 2
	return gear


# --- The wheel ------------------------------------------------------------------

## With his hand on the wheel he turns it toward where he wants the car: the
## angle that takes it there within bot_settle_s against whatever carries
## it sideways, off by his lane-keeping error.
func _steer(input: DriveInput, want_x: float) -> void:
	# The error wanders (a slow random walk about zero with the skill's spread).
	var pull: float = DriveSim.DT / maxf(_tuning.f("bot_error_tau_s"), 0.001)
	_error += -_error * pull + _lane_error * sqrt(2.0 * pull) * _random.randfn(0.0, 1.0)
	if not _sim.hand.gripping:
		return
	var car: CarSim = _sim.car
	var authority: float = car.lat_authority()
	if authority <= 0.0:
		return
	# (At a crawl he places the car as exactly as he likes.)
	var error: float = _error * clampf(car.speed / _tuning.fi("gear_speeds", 2), _tuning.f("bot_error_slow"), 1.0)
	var wanted: float = (want_x + error - car.x) / maxf(_tuning.f("bot_settle_s"), 0.001) - car.drift
	var angle: float = clampf(wanted / authority, -1.0, 1.0) * _sim.wheel.max_angle()
	var per_px: float = _tuning.f("steer_deg_per_px") * maxf(_sim.steer_sensitivity, 0.01)
	input.pointer_delta.x = (angle - _sim.wheel.command) / per_px


# --- The hand -------------------------------------------------------------------

## The hand: at work on its steps, or on the wheel; and from the wheel, the
## next thing it has to do, when the road allows letting go.
func _hand(input: DriveInput) -> void:
	if _steps.is_empty():
		var next: Array[Array] = _next_task()
		if not next.is_empty():
			if _sim.seconds() < GameData.as_float(_not_before.get(_task), -INF):
				# He has only just done that.
				_task = ""
			else:
				_not_before[_task] = _sim.seconds() + _tuning.f("bot_task_gap_s")
				_steps = next
	if _steps.is_empty():
		_hold_the_wheel(input)
		return
	_work(input)


func _hold_the_wheel(input: DriveInput) -> void:
	if _sim.hand.gripping:
		input.lmb = true
		return
	input.pointer_is_absolute = true
	input.pointer = _sim.space.point_to_pointer(_sim.space.grip_reference)
	input.lmb = true


## What the hand should do next, as steps; empty for nothing now.
func _next_task() -> Array[Array]:
	var none: Array[Array] = []
	if not _sim.hand.gripping or not _sim.hand.can_reach:
		return none
	var calm: float = _calm_for()
	# The gear: the most urgent thing a hand can do.
	if _sim.gate.gear != _want_gear and not _sim.passengers.blocks_lever():
		if calm >= _task_time("shift"):
			_task = "gear_shift"
			return [["go", "gear_lever"], ["shift", _ticks(_tuning.f("bot_shift_s")), _want_gear], ["up", 2]]
		return none
	# Rain: a sweep before the glass is blind.
	if _sim.items.raining and _sim.items.rain_blur() >= _tuning.f("bot_wipe_at_blur") and calm >= _task_time("flick"):
		_task = "wipers"
		# Up the screen (y grows downward): the wipers are a FLICK up (GDD 4.6).
		return [["go", "wiper_stalk"], _pause("bot_flick_s", 6), ["flick", 6, 0.0, -1.0], ["up", 2]]
	# Night: the high beam shows him more road.
	if _sim.visibility() < _tuning.f("bot_look_ahead_m") * 0.5 and _sim.headlight_cone() > 0.0 and not _sim.items.flag(DriveSim.FLAG_HIGH_BEAM) and calm >= _task_time("tap"):
		_task = "headlights"
		return [["go", "headlight_knob"], _pause("bot_tap_s", 4), ["down", 4], ["up", 2]]
	var nerves: float = _sim.nerves.value
	# The radio: music while his Nerves are up, the news to stay awake.
	var station: StringName = _sim.items.radio
	if station != ItemSim.STATIC:
		_last_station = station
	var want: StringName = &""
	if (nerves < _sim.heavy_floor() + _tuning.f("bot_heavy_margin")) and _sim.heavy_floor() > 0.0:
		want = &"news"
	elif nerves >= _tuning.f("bot_music_nerves"):
		want = &"music"
	if want != &"" and station != want and calm >= _task_time("drag"):
		var way: int = _dial_way(station, want)
		if way != 0:
			_task = "radio_tune"
			# One station: a little over one step of the dial, and the tick
			# the press is taken in does not count.
			return [["go", "radio"], _pause("bot_drag_s", 10), ["flick", 10, float(way) * _tuning.f("radio_step_px") * 0.14 / maxf(_tuning.f("bot_flick_px"), 0.001), 0.0], ["up", 2]]
	# Falling asleep: a slap.
	if (_sim.nerves.heavy or nerves < _sim.heavy_floor()) and not _sim.nerves.awake and calm >= _task_time("tap"):
		_task = "slap"
		return [["go", "face"], _pause("bot_tap_s", 4), ["down", 4], ["up", 2]]
	# Frayed: the photo once a leg, then the horn.
	if nerves >= _tuning.fi("bot_calm_nerves", _index):
		if not _sim.items.photo_used and calm >= _task_time("flick"):
			_task = "visor_photo"
			return [["go", "visor"], _pause("bot_flick_s", 6), ["flick", 6, 0.0, 1.0], ["up", 2]]
		if not _sim.suspicion.watching and _sim.seconds() - _horn_at >= _tuning.f("horn_cooldown") and calm >= _task_time("tap"):
			_task = "horn"
			_horn_at = _sim.seconds()
			return [["go", "horn"], _pause("bot_tap_s", 4), ["down", 4], ["up", 2]]
	return none


## Which way to turn the dial from `station` toward `want`: +1 right, -1
## left, 0 when the radio has no such station. (One station per step, in
## the order of radio_stations; from static, right finds the one after the
## last heard and left the one before.)
func _dial_way(station: StringName, want: StringName) -> int:
	var stations: Array = _tuning.a("radio_stations")
	var count: int = stations.size()
	var to: int = stations.find(String(want))
	if to == -1 or count == 0:
		return 0
	var from: int = stations.find(String(station if station != ItemSim.STATIC else _last_station))
	if from == -1:
		return 1
	var right: int = posmod(to - from, count)
	var left: int = posmod(from - to, count)
	return 1 if right <= left else -1


## A pause with the hand at its anchor before the gesture, so that the
## whole of it takes what GDD 7.4 gives a gesture of its kind (a TAP 0.3 s,
## a FLICK 0.4 s, a DRAG 0.8 s): "realistic durations" (GDD 13.8). `ticks`
## are those the gesture itself takes.
func _pause(duration: String, ticks: int) -> Array:
	return ["up", maxi(_ticks(_tuning.f(duration)) - ticks, 1)]


## Seconds a task takes from letting go of the wheel to having it again.
func _task_time(kind: String) -> float:
	var reach: float = 2.0 * _tuning.f("bot_reach_s")
	match kind:
		"shift":
			return reach + _tuning.f("bot_shift_s") + _margin
		"flick":
			return reach + _tuning.f("bot_flick_s") + _margin
		"tap":
			return reach + _tuning.f("bot_tap_s") + _margin
		"drag":
			return reach + _tuning.f("bot_drag_s") + _margin
	return reach + 1.0 + _margin


## Seconds the road leaves him alone for: nothing within reach in his lane
## or coming into it, no bend and no gust before then, no lane to change.
func _calm_for() -> float:
	var car: CarSim = _sim.car
	var speed_ms: float = maxf(car.speed * KMH_TO_MS, 1.0)
	var lane: int = clampi(car.lane_of(car.x), 0, car.lanes - 1)
	if _target_lane != lane or absf(car.x - car.lane_center(lane)) > _tuning.f("bot_centre_m"):
		return 0.0
	var look: float = _sight()
	var calm: float = look / speed_ms
	_scan(look)
	calm = minf(calm, _soon[lane])
	for entry: Variant in GameData.as_array(_plan.get("curves")):
		var curve: Dictionary = GameData.as_dict(entry)
		var from: float = GameData.as_float(curve.get("s"))
		var to: float = from + GameData.as_float(curve.get("length"))
		if car.s < to and from - car.s < look:
			calm = minf(calm, maxf(from - car.s, 0.0) / speed_ms)
	for entry: Variant in GameData.as_array(_plan.get("gusts")):
		var at: float = GameData.as_float(GameData.as_dict(entry).get("s"))
		if at >= car.s - 30.0 and at - car.s < look:
			calm = minf(calm, maxf(at - car.s, 0.0) / speed_ms)
	for zone: PackedFloat64Array in _zones:
		if car.s <= zone[3] and zone[0] - car.s < look:
			calm = minf(calm, maxf(zone[0] - car.s, 0.0) / speed_ms)
	var slip: Vector2 = _sim.exit_slip()
	if _takes_exit and slip.x >= 0.0:
		calm = minf(calm, maxf(slip.x - car.s - look * 0.5, 0.0) / speed_ms)
	if _sim.boss.active and _sim.boss.kind == BossSim.STORM:
		calm = minf(calm, 2.0 * _tuning.f("bot_reach_s") + 0.5)
	if _sim.boss.active and _sim.boss.kind == BossSim.DAWN:
		# Between the last checkpoint's barriers both hands would be too few.
		var corridor: Vector3 = _sim.boss.corridor()
		if corridor.z > corridor.x and car.s < corridor.z:
			calm = minf(calm, maxf(corridor.x - look - car.s, 0.0) / speed_ms)
	return calm


func _ticks(seconds: float) -> int:
	return maxi(roundi(seconds / DriveSim.DT), 1)


## One tick of the hand's work. Steps: "go" (the pointer on an anchor until
## the hand rests there), "down" and "up" (the button, for so many ticks),
## "carry" (the button down, the pointer on another anchor until the hand
## is there), "crank" (the button down, the pointer led round until the
## window is open), "flick" (the button down and the pointer thrown),
## "shift" (the lever held for so many ticks, then in the gear).
func _work(input: DriveInput) -> void:
	var step: Array = _steps[0]
	var what: String = GameData.as_string(step[0])
	match what:
		"go", "carry":
			var anchor: StringName = StringName(GameData.as_string(step[1]))
			var index: int = _sim.hand.anchor_index(anchor)
			if index == HandSim.NO_ANCHOR or not _sim.hand.is_anchor_active(index) and what == "go":
				# Nothing to do there now.
				_steps = []
				return
			input.pointer_is_absolute = true
			input.pointer = _sim.hand.anchor_pointer(index)
			input.lmb = what == "carry"
			if _sim.hand.at_id() == anchor:
				_steps.remove_at(0)
		"down", "up":
			input.lmb = what == "down"
			step[1] = GameData.as_int(step[1]) - 1
			if GameData.as_int(step[1]) <= 0:
				_steps.remove_at(0)
		"flick":
			input.lmb = true
			input.pointer_delta = Vector2(GameData.as_float(step[2]), GameData.as_float(step[3])) * _tuning.f("bot_flick_px")
			step[1] = GameData.as_int(step[1]) - 1
			if GameData.as_int(step[1]) <= 0:
				_steps.remove_at(0)
		"shift":
			input.lmb = true
			step[1] = GameData.as_int(step[1]) - 1
			if GameData.as_int(step[1]) <= 0:
				if _sim.gate.held:
					_sim.gate.place_held(GameData.as_int(step[2]))
				_steps.remove_at(0)
		"crank":
			_crank_heading += deg_to_rad(_tuning.f("bot_crank_deg"))
			input.lmb = true
			input.pointer_delta = Vector2(cos(_crank_heading), sin(_crank_heading)) * _tuning.f("bot_crank_px")
			if _sim.items.flag(ItemSim.FLAG_WINDOW):
				_steps.remove_at(0)
	if _steps.is_empty() and not _task.is_empty():
		rituals[_task] = GameData.as_int(rituals.get(_task)) + 1
		_task = ""


## Under a Patrol's eye a lane line crossed without the indicator is
## noticed (GDD 6.5). He indicates first when the hand is free for it.
func _wants_to_indicate(way: int) -> void:
	if way == 0 or not _sim.suspicion.watching or not _steps.is_empty() or not _sim.hand.gripping:
		return
	if _sim.items.indicator == way:
		return
	_task = "indicator"
	_steps = [["go", "indicator_stalk"], _pause("bot_flick_s", 6), ["flick", 6, 0.0, float(-way)], ["up", 2]]


# --- Where the night waits ------------------------------------------------------

## At a stop: what he came for, then the wheel is held until he is off.
func _at_a_stop(input: DriveInput) -> void:
	if _stood <= 0.0:
		stops += 1
	_stood += DriveSim.DT
	if not _shop_done and _steps.is_empty():
		_steps = _next_purchase()
		if _steps.is_empty():
			_shop_done = true
	if not _steps.is_empty():
		_work(input)
		return
	if _stood > _tuning.f("bot_stop_wait_s"):
		input.pointer_is_absolute = true
		input.pointer = _sim.space.point_to_pointer(_sim.space.grip_reference)
		input.lmb = true


## The next thing he does at the vendor's tray, as steps; empty when he is
## done. What he has paid for goes to its place first. Repairs come before
## anything else. Then, if he buys (GDD 12.5: the expert is measured with
## no purchases): the free pick, and "sensibly", which here means what
## works on its own (a Keepsake, an Adaptation), dearest first, as long as
## the price of a repair stays in his pocket. A Habit needs a hand he has
## no time for, and a Deal is the shady guy's.
func _next_purchase() -> Array[Array]:
	var none: Array[Array] = []
	var stop: StopSim = _sim.stop
	_stop_actions += 1
	if _stop_actions > _tuning.i("bot_stop_actions"):
		return none
	var offers: Array[Dictionary] = stop.offers_view()
	for offer: Dictionary in offers:
		if not GameData.as_bool(offer.get("bought")) or _kind_of(offer) != StopSim.ITEM:
			continue
		var anchor: String = GameData.as_string(offer.get("anchor"))
		for slot: String in stop.slot_anchors(GameData.as_string(offer.get("id"))):
			var key: String = "%s>%s" % [anchor, slot]
			if _stop_tried.has(key):
				continue
			_stop_tried[key] = true
			return [["go", anchor], ["down", 12], ["carry", slot], ["up", 30]]
	for offer: Dictionary in offers:
		if GameData.as_bool(offer.get("bought")) or _kind_of(offer) != StopSim.REPAIR:
			continue
		if GameData.as_float(offer.get("price")) <= _sim.cash:
			bought += 1
			return [["go", GameData.as_string(offer.get("anchor"))], ["down", 4], ["up", 12]]
	# After a boss: one service of his choice (GDD 9.6): the fitter with a
	# lamp lit, the tea with his Nerves up.
	for offer: Dictionary in offers:
		if GameData.as_bool(offer.get("bought")) or _kind_of(offer) != StopSim.SERVICE:
			continue
		var service: String = GameData.as_string(_data.record("stops", GameData.as_string(offer.get("id"))).get("service")) if _data.has_record("stops", GameData.as_string(offer.get("id"))) else ""
		if (service == "repair" and _sim.faults.lamps > 0) or (service == "tea" and _sim.faults.lamps == 0 and _sim.nerves.value >= _tuning.f("bot_tea_nerves")):
			return [["go", GameData.as_string(offer.get("anchor"))], ["down", 4], ["up", 12]]
	if not buys:
		return none
	var best: Dictionary = {}
	for offer: Dictionary in offers:
		if GameData.as_bool(offer.get("bought")) or GameData.as_bool(offer.get("shady")) or _kind_of(offer) != StopSim.ITEM:
			continue
		var id: String = GameData.as_string(offer.get("id"))
		var kind: String = GameData.as_string(_data.record("items", id).get("kind")) if _data.has_record("items", id) else ""
		if kind != "keepsake" and kind != "adaptation":
			continue
		if stop.slot_anchors(id).is_empty() or _stop_tried.has("buy>" + id):
			continue
		var price: float = GameData.as_float(offer.get("price"))
		var free: bool = GameData.as_bool(offer.get("free")) and stop.picks_left > 0
		if not free and price > _sim.cash - _tuning.f("repair_price"):
			continue
		var worth: float = GameData.as_float(_data.record("items", id).get("price")) + (1000.0 if free else 0.0)
		if best.is_empty() or worth > GameData.as_float(best.get("worth")):
			best = {"anchor": GameData.as_string(offer.get("anchor")), "id": id, "worth": worth}
	if best.is_empty():
		return none
	_stop_tried["buy>" + GameData.as_string(best["id"])] = true
	bought += 1
	return [["go", GameData.as_string(best["anchor"])], ["down", 4], ["up", 12]]


## What an offer on the tray is: an item, a restock, a repair, a service.
func _kind_of(offer: Dictionary) -> StringName:
	var kind: Variant = offer.get("kind")
	if kind is StringName:
		return kind
	return StringName(GameData.as_string(kind))


## An officer at his window (GDD 6.5): his licence across.
func _with_the_officer(input: DriveInput) -> void:
	if _steps.is_empty():
		_task = "hand_licence"
		_steps = [["go", "dash_1"], ["down", 12], ["carry", "driver_window"], ["up", 30]]
	_work(input)


## The Checkpoint (GDD 10.2): the middle lane's queue in first gear, on the
## brake behind whatever is ahead and at the bar; then the window and
## whatever the soldier's sign asks for.
func _at_the_checkpoint(input: DriveInput) -> void:
	var car: CarSim = _sim.car
	var boss: BossSim = _sim.boss
	var lane: int = car.lanes / 2
	var gear: int = 2 if boss.released else _tuning.i("start_gear")
	if _sim.gate.gear != gear and not _sim.gate.held:
		_sim.gate.force_gear(gear)
	var room: float = INF
	if not boss.released:
		room = boss.bar_at - (car.s + car.length() * 0.5)
	for vehicle: TrafficSim.Vehicle in _sim.traffic.vehicles:
		if absf(vehicle.x - car.lane_center(lane)) < car.lane_width() * 0.5 and vehicle.s > car.s:
			room = minf(room, vehicle.s - vehicle.half_length - car.s - car.length() * 0.5)
	var speed_ms: float = car.speed * KMH_TO_MS
	if room < _tuning.f("bot_queue_gap_m") + speed_ms * speed_ms / (2.0 * _tuning.f("brake_decel") * KMH_TO_MS) + speed_ms * float(_reaction_ticks) * DriveSim.DT:
		input.rmb = true
	if boss.phase == BossSim.PAPERS and _steps.is_empty():
		_plan_the_papers()
	if _steps.is_empty():
		_hold_the_wheel(input)
		_steer(input, car.lane_center(lane))
	else:
		_work(input)


## What the hand must do for the soldier: the window, if it is shut; then
## the document his sign asks for, from where it is kept.
func _plan_the_papers() -> void:
	if not _sim.items.flag(ItemSim.FLAG_WINDOW):
		_steps = [["go", "window_crank"], ["crank"], ["up", 6]]
		return
	var from: String = "dash_1"
	match _sim.boss.wanted:
		"id":
			from = "pocket"
		"registration":
			from = ItemSim.GLOVEBOX
			if not _sim.items.flag(ItemSim.FLAG_GLOVEBOX):
				_steps = [["go", from], ["down", 4], ["up", 6]]
				return
			if not _sim.items.flag(&"letter_aside"):
				var hold: float = GameData.as_float(_data.record("rituals", "letter_aside").get("hold_s"))
				_steps = [["go", from], ["down", _ticks(hold) + 2], ["up", 6]]
				return
	_steps = [["go", from], ["down", 12], ["carry", "driver_window"], ["up", 30]]


## The Arrival (GDD 10.5): the brake goes on in time to stop in the middle
## of the bay; standing there, the hand goes to the key and taps it.
func _park_and_turn_the_key(input: DriveInput) -> void:
	var car: CarSim = _sim.car
	var boss: BossSim = _sim.boss
	if _sim.gate.gear != _tuning.i("start_gear") and not _sim.gate.held:
		_sim.gate.force_gear(_tuning.i("start_gear"))
	var speed_ms: float = car.speed * KMH_TO_MS
	var stopping: float = speed_ms * speed_ms / (2.0 * _tuning.f("brake_decel") * KMH_TO_MS)
	if car.s + stopping >= (boss.bay_from + boss.bay_to) * 0.5:
		input.rmb = true
	if not boss.in_bay:
		_key_ticks = 0
		_hold_the_wheel(input)
		return
	var key: int = _sim.hand.anchor_index(&"key")
	input.pointer_is_absolute = true
	input.pointer = _sim.hand.anchor_pointer(key)
	input.lmb = false
	if _sim.hand.at_index == key:
		_key_ticks += 1
		input.lmb = _key_ticks <= 4
