extends TestSuite
## M11: the generator never builds a wall (GDD 9.2 rule 3, 12.4 rule 8).
## T-WALL-01. The driver is tests/support/ideal_driver.gd: third gear, the
## plan's own line, eyes shut. What the Tailgater and Dawn's last checkpoint
## had to learn for it is D-067.

const KMH_TO_MS: float = 1.0 / 3.6
const DT: float = DriveSim.DT
## Seeds are this test's own: any would do.
const SEED: int = 4100
## How many Tailgater legs are tried for one in which he goes by.
const TAIL_TRIES: int = 12
## How many seeds are tried for a leg that takes a Twist.
const TWIST_TRIES: int = 6

var _sim: DriveSim
var _driver: IdealDriver


# --- Helpers -------------------------------------------------------------------

func _new_sim(act: int) -> void:
	_sim = DriveSim.new(data)
	_sim.heckling = false
	_sim.act = act
	_driver = IdealDriver.new(_sim, data)


## A generated leg, the scripted driver at its start.
func _begin_leg(plan: Dictionary) -> void:
	_new_sim(GameData.as_int(plan.get("act"), 1))
	_sim.begin_leg(plan)
	_driver.begin(plan)


## Drives the stretch to its end (or to `until` metres). What happened:
## hits, hazards run over, close calls, Wrecks, pull-overs, searches, the
## Tailgater's cut-ins, ticks in which the Tailgater was inside another
## vehicle, times he pulled out to pass where the plan's line was about to
## move over, times he was left in the car's way after his stab at the
## brake, whether the stretch was finished and in how many seconds, and the
## first thing that went wrong, in words.
func _drive(until: float = INF, say_twist: bool = true) -> Dictionary:
	var out: Dictionary = {"hit": 0, "scrape": 0, "close_call": 0, "wreck": 0, "pulled_over": 0, "searched": 0, "cut_off": 0, "through": 0, "on_the_line": 0, "in_the_way": 0, "first": ""}
	var tail_phase: int = _sim.encounter.tail_phase
	var was_tail: TrafficSim.Vehicle = null
	# The least road his pass takes: by the car, in, and the stab (GDD 9.3's
	# numbers), at third gear's pace.
	var special: Dictionary = GameData.as_dict(data.record("legs", "tailgater").get("special"))
	var pass_m: float = ((tuning.f("car_length") + GameData.as_float(special.get("brake_gap_m")) + GameData.as_float(special.get("gap_m"))) / maxf(GameData.as_float(special.get("pass_speed_kmh")) * KMH_TO_MS, 0.001) \
			+ GameData.as_float(special.get("merge_s")) + GameData.as_float(special.get("brake_s"))) * tuning.fi("gear_speeds", IdealDriver.GEAR - 1) * KMH_TO_MS
	var input: DriveInput = DriveInput.new()
	var plan: Dictionary = _sim.leg.plan
	var twist_at: float = GameData.as_float(_sim.leg.twist.get("first_s"), INF)
	var guard: int = roundi((2.0 * GameData.as_float(plan.get("par_s"), 120.0) + 60.0) / DT)
	while _sim.leg.active and is_same(_sim.leg.plan, plan) and _sim.car.s < until and guard > 0:
		guard -= 1
		if say_twist and not _sim.leg.twist_live and _sim.car.s >= twist_at:
			# The guest says it (GDD 11.3): the Twist comes onto the road.
			_sim.leg.twist_begins()
		_driver.drive(input)
		_sim.step(input)
		for event: Dictionary in _sim.drain_events():
			var type: String = GameData.as_string(event.get("type"))
			if type == "sfx_requested" and event.has("hazard"):
				type = "scrape"
			if out.has(type):
				out[type] = GameData.as_int(out[type]) + 1
				if GameData.as_string(out["first"]).is_empty() and type != "close_call":
					out["first"] = "%s at %d m, %.1f s" % [type, roundi(_sim.car.s), _sim.seconds()]
		if _sim.boss.searched:
			out["searched"] = GameData.as_int(out["searched"]) + 1
		if _sim.encounter.cut_off:
			out["cut_off"] = GameData.as_int(out["cut_off"]) + 1
		var phase: int = _sim.encounter.tail_phase
		if phase == EncounterSim.TAIL_PASSING and tail_phase != EncounterSim.TAIL_PASSING and not _line_keeps(plan, _sim.car.s, _sim.car.s + pass_m):
			out["on_the_line"] = GameData.as_int(out["on_the_line"]) + 1
		if phase == EncounterSim.TAIL_GONE and tail_phase == EncounterSim.TAIL_LEAVING and was_tail != null:
			# Gone after his stab at the brake: out of the car's lane and
			# slower than the car, or he is in its way.
			if absf(was_tail.x - _sim.car.x) < was_tail.half_width + _sim.car.half_width() or was_tail.speed >= _sim.car.speed:
				out["in_the_way"] = GameData.as_int(out["in_the_way"]) + 1
		if phase == EncounterSim.TAIL_GONE and tail_phase == EncounterSim.TAIL_BRAKING:
			out["in_the_way"] = GameData.as_int(out["in_the_way"]) + 1
		tail_phase = phase
		if _sim.encounter.tailgater() != null:
			was_tail = _sim.encounter.tailgater()
		var tail: TrafficSim.Vehicle = _sim.encounter.tailgater()
		# (Not while he closes up or hangs back in the car's tracks: there
		# he can be drawn inside a vehicle the car has just cut in front
		# of, behind the car. D-067 leaves that open.)
		if tail != null and (_sim.encounter.tail_phase == EncounterSim.TAIL_ON_BUMPER or _sim.encounter.tail_phase >= EncounterSim.TAIL_PASSING):
			for other: TrafficSim.Vehicle in _sim.traffic.vehicles:
				if other != tail and absf(other.s - tail.s) < other.half_length + tail.half_length and absf(other.x - tail.x) < other.half_width + tail.half_width:
					out["through"] = GameData.as_int(out["through"]) + 1
	out["finished"] = not _sim.leg.active or not is_same(_sim.leg.plan, plan)
	out["seconds"] = _sim.seconds()
	return out


## True if nothing was touched and nobody stopped him.
func _clear(drive: Dictionary) -> bool:
	return GameData.as_int(drive["hit"]) == 0 and GameData.as_int(drive["scrape"]) == 0 and GameData.as_int(drive["wreck"]) == 0 \
			and GameData.as_int(drive["pulled_over"]) == 0 and GameData.as_int(drive["searched"]) == 0


func _what(drive: Dictionary) -> String:
	var first: String = GameData.as_string(drive["first"])
	return first if not first.is_empty() else ("%d close call(s)" % GameData.as_int(drive["close_call"]) if GameData.as_int(drive["close_call"]) > 0 else "nothing")


## The lane the plan's line is in at `s`.
func _line_lane(plan: Dictionary, s: float) -> int:
	var lane: int = GameData.as_int(plan.get("start_lane"))
	for entry: Variant in GameData.as_array(plan["path"]):
		var pair: Array = GameData.as_array(entry)
		if GameData.as_float(pair[0]) <= s:
			lane = GameData.as_int(pair[1])
	return lane


## True if the plan's line keeps one lane from `from` to `to`.
func _line_keeps(plan: Dictionary, from: float, to: float) -> bool:
	var change: float = tuning.f("gen_lane_change")
	for entry: Variant in GameData.as_array(plan["path"]):
		var at: float = GameData.as_float(GameData.as_array(entry)[0])
		if at > from - change and at < to:
			return false
	return true


# --- T-WALL-01 -----------------------------------------------------------------

## T-WALL-01: A scripted ideal driver in gear 3 clears every generated leg
## with no contact.
func test_wall_01() -> void:
	_check_every_leg()
	_check_the_tailgater()
	_check_twists()
	_check_dawn()
	_check_the_commute()
	_check_failure_cases()


## Every leg type in every act it has, and with every modifier it allows.
func _check_every_leg() -> void:
	var third: float = tuning.fi("gear_speeds", IdealDriver.GEAR - 1)
	var driven: int = 0
	var bad: int = 0
	var close_calls: int = 0
	var slowest: float = 0.0
	var modifiers_seen: Dictionary = {}
	for leg: Dictionary in data.records("legs"):
		var id: String = GameData.as_string(leg.get("id"))
		var acts: Array = GameData.as_array(leg.get("acts"))
		var modifiers: Array = GameData.as_array(leg.get("modifiers_allowed"))
		# Each act with no modifier; then each modifier, in the acts that
		# have them (GDD 9.4: from Act 2), turn about.
		var cases: Array[Array] = []
		for act_value: Variant in acts:
			cases.append([GameData.as_int(act_value), ""])
		var late: Array[int] = []
		for act_value: Variant in acts:
			if GameData.as_int(act_value) >= 2:
				late.append(GameData.as_int(act_value))
		for index: int in modifiers.size():
			if not late.is_empty():
				cases.append([late[index % late.size()], GameData.as_string(modifiers[index])])
		for index: int in cases.size():
			var act: int = GameData.as_int(cases[index][0])
			var modifier: String = GameData.as_string(cases[index][1])
			var leg_seed: int = SEED + 31 * driven
			var plan: Dictionary = LegGenerator.generate(data, id, act, leg_seed, modifier)
			if not GameData.as_dict(GameData.as_dict(plan.get("motorcade")).get("detour")).is_empty():
				# The Motorcade holds every lane (GDD 9.3). Behind it the
				# line is open at the motorcade's pace and no faster...
				var convoy_kmh: float = GameData.as_float(GameData.as_dict(leg.get("special")).get("speed_kmh"))
				_begin_leg(plan)
				var behind: Dictionary = _drive()
				check(_clear(behind) and GameData.as_bool(behind["finished"]) and GameData.as_int(behind["close_call"]) == 0,
						"%s, '%s': behind the motorcade for the whole leg nothing is touched (%s)" % [id, modifier, _what(behind)])
				check_near(_sim.car.speed, convoy_kmh, 0.5, "and third gear does the motorcade's %d km/h there" % roundi(convoy_kmh))
				check(GameData.as_float(behind["seconds"]) > GameData.as_float(plan.get("par_s")), "which is slower than par (%.0f s)" % GameData.as_float(behind["seconds"]))
				# ...and the way through at third gear's own is its side road.
				_begin_leg(plan)
				_driver.takes_side_road = true
			else:
				_begin_leg(plan)
			var drive: Dictionary = _drive()
			driven += 1
			modifiers_seen[modifier] = true
			close_calls += GameData.as_int(drive["close_call"])
			slowest = maxf(slowest, GameData.as_float(drive["seconds"]) - GameData.as_float(plan.get("par_s")))
			if not _clear(drive) or not GameData.as_bool(drive["finished"]) or GameData.as_int(drive["through"]) > 0:
				bad += 1
				if bad <= 3:
					fail("%s, act %d, modifier '%s', seed %d: %s%s" % [id, act, modifier, leg_seed, _what(drive), "" if GameData.as_bool(drive["finished"]) else " (and he never got to its end)"])
			check_near(_sim.car.speed, third, 0.5, "%s, act %d, '%s': he is still doing third gear's %d km/h at its end" % [id, act, modifier, roundi(third)])
			check_eq(_sim.faults.lamps, 0, "%s, act %d, '%s': no lamp is lit" % [id, act, modifier])
	check_eq(data.records("legs").size(), 9, "GDD 9.1: nine leg types")
	check(driven >= 9 + data.records("modifiers").size(), "(%d legs were driven)" % driven)
	check_eq(modifiers_seen.size(), data.records("modifiers").size() + 1, "with every modifier and with none")
	check_eq(bad, 0, "third gear, the plan's line, eyes shut: every generated leg is cleared with no contact")
	check_eq(close_calls, 0, "and without a close call (GDD 9.2 rule 3)")
	check(slowest <= 0.5, "none took longer than its par (the slowest by %.1f s)" % slowest)
	note("%d legs driven in the real simulation" % driven)


## The Tailgater (GDD 9.3) is on the road after the plan was made: he must
## not take the way the plan kept open. Legs are driven until he has gone
## by in one of them.
func _check_the_tailgater() -> void:
	var special: Dictionary = GameData.as_dict(data.record("legs", "tailgater").get("special"))
	var acts: Array = GameData.as_array(data.record("legs", "tailgater").get("acts"))
	var tried: int = 0
	var cut_in: int = 0
	var bad: int = 0
	var through: int = 0
	var on_the_line: int = 0
	var in_the_way: int = 0
	var on_bumper: int = 0
	while tried < TAIL_TRIES and cut_in == 0:
		var plan: Dictionary = LegGenerator.generate(data, "tailgater", GameData.as_int(acts[tried % acts.size()]), SEED + 7000 + 13 * tried, "")
		_begin_leg(plan)
		var drive: Dictionary = _drive(GameData.as_float(special.get("at_s")) * tuning.fi("gear_speeds", IdealDriver.GEAR - 1) * KMH_TO_MS + 1.0)
		if _sim.encounter.tail_phase == EncounterSim.TAIL_ON_BUMPER:
			on_bumper += 1
		var rest: Dictionary = _drive()
		tried += 1
		cut_in += GameData.as_int(rest["cut_off"])
		through += GameData.as_int(drive["through"]) + GameData.as_int(rest["through"])
		on_the_line += GameData.as_int(rest["on_the_line"])
		in_the_way += GameData.as_int(rest["in_the_way"])
		if not _clear(drive) or not _clear(rest) or GameData.as_int(rest["close_call"]) > 0 or not GameData.as_bool(rest["finished"]):
			bad += 1
			fail("Tailgater leg %d: %s" % [tried, _what(rest) if _clear(drive) else _what(drive)])
		check_eq(_sim.encounter.tail_phase, EncounterSim.TAIL_GONE, "Tailgater leg %d: by the end of the leg he is gone" % tried)
	check_eq(on_bumper, tried, "in each of them he was on the bumper %d s in" % roundi(GameData.as_float(special.get("at_s"))))
	check(cut_in >= 1, "within %d Tailgater legs he has gone by, cut in and braked in front of the driver (%d tried)" % [TAIL_TRIES, tried])
	check_eq(bad, 0, "and the driver, who does not brake for him, was never touched nor run close")
	check_eq(through, 0, "nor did he ever drive through another vehicle to do it")
	check_eq(on_the_line, 0, "he pulled out only where the plan's line keeps its lane for as long as his pass takes")
	check_eq(in_the_way, 0, "and when he was gone he was out of the car's lane and slower than the car")


## A Twist (GDD 11.3) is a stretch laid into the leg with it: sheep, the
## wedding, the melon truck. Said or not said, the line is open.
func _check_twists() -> void:
	var laid: int = 0
	for kind: String in LegGenerator.ZONE_KINDS:
		var done: bool = false
		for index: int in TWIST_TRIES:
			if done:
				break
			for leg: Dictionary in data.records("legs"):
				var id: String = GameData.as_string(leg.get("id"))
				if not GameData.as_array(leg.get("modifiers_allowed")).has(kind):
					continue
				var act: int = maxi(GameData.as_int(GameData.as_array(leg.get("acts"))[0]), 2)
				var plan: Dictionary = LegGenerator.generate(data, id, act, SEED + 9000 + 17 * index, "", {"modifier": kind, "at": 0.5})
				if GameData.as_dict(plan.get("twist")).is_empty():
					continue
				for said: bool in [true, false]:
					_begin_leg(plan)
					var drive: Dictionary = _drive(INF, said)
					check(_clear(drive) and GameData.as_bool(drive["finished"]) and GameData.as_int(drive["close_call"]) == 0,
							"%s with a Twist of %s, %s: cleared with no contact (%s)" % [id, kind, "said" if said else "never said", _what(drive)])
					check_eq(_sim.leg.twist_live, said, "(the Twist %s)" % ("came onto the road" if said else "stayed off it"))
				laid += 1
				done = true
				break
	check_eq(laid, LegGenerator.ZONE_KINDS.size(), "a leg with each kind of Twist was driven")


## Dawn's road (GDD 10.4) is laid out by the same generator around its last
## checkpoint, where nobody keeps par: 70 km/h between the barriers. The
## driver's script has the limit in it. What he loses there the road waits
## for (D-067): he drives out onto the road that was planned.
func _check_dawn() -> void:
	var dawn: Dictionary = GameData.as_dict(data.record("bosses", "dawn").get("dawn"))
	var check: Dictionary = GameData.as_dict(dawn.get("checkpoint"))
	var limit: float = GameData.as_float(check.get("max_kmh"))
	var third: float = tuning.fi("gear_speeds", IdealDriver.GEAR - 1)
	check(limit < third, "GDD 10.4: the last checkpoint's %d km/h is less than third gear's %d" % [roundi(limit), roundi(third)])
	var modifiers: PackedStringArray = [""]
	for modifier: Dictionary in GameData.as_array(data.root("legs").get("boss_modifiers")):
		if GameData.as_string(modifier.get("boss")) == "dawn":
			modifiers.append(GameData.as_string(modifier.get("id")))
	check_eq(modifiers.size(), 3, "Dawn has two modifiers")
	for index: int in modifiers.size():
		_begin_dawn(modifiers[index], SEED + index, false)
		var drive: Dictionary = _drive()
		check(_clear(drive) and GameData.as_bool(drive["finished"]), "Dawn%s: second gear between the barriers, third again behind them, and nothing is touched (%s)" % ["" if modifiers[index].is_empty() else " on " + modifiers[index], _what(drive)])
		check_eq(GameData.as_int(drive["close_call"]), 0, "nor run close")

	# The same Dawn for one who loses seconds more: second gear from the
	# checkpoint's sign. Where he is back at par the road is the same
	# road, vehicle for vehicle.
	var corridor_end: float = GameData.as_float(check.get("at_m")) + GameData.as_float(check.get("length_m"))
	var back_at_par: float = corridor_end + (third * third - limit * limit) / (2.0 * tuning.f("accel")) * KMH_TO_MS
	var at: float = back_at_par + 1.0
	_begin_dawn("market_day", SEED + 40, false)
	_drive(at)
	var quick_seconds: float = _sim.seconds()
	var quick: Dictionary = _road_ahead()
	check_near(_sim.car.speed, third, 1.0, "the scripted driver is back at par %d m behind the barriers" % roundi(back_at_par - corridor_end))
	# It is the road that was planned: a vehicle that keeps its lane is as
	# far ahead of him as the plan has it for a driver who never left par.
	var planned: int = 0
	var found: int = 0
	for entry: Variant in GameData.as_array(_sim.leg.plan["spawns"]):
		var spawn: Dictionary = GameData.as_dict(entry)
		var lane: int = GameData.as_int(spawn.get("lane"))
		var trigger: float = GameData.as_float(spawn.get("trigger_s"))
		if GameData.as_int(spawn.get("direction")) != 1 or lane < 0 or lane != GameData.as_int(spawn.get("change_to")) or trigger > corridor_end:
			continue
		var ahead: float = GameData.as_float(spawn.get("ahead")) - (1.0 - GameData.as_float(spawn.get("speed")) / third) * (_sim.car.s - trigger)
		if ahead < 20.0 or ahead > tuning.f("spawn_ahead"):
			continue
		planned += 1
		for id: Variant in quick:
			var where: Vector2 = quick[id]
			if absf(where.y - _sim.car.lane_center(lane)) < 0.1 and absf(where.x - ahead) < 1.0:
				found += 1
				break
	check(planned >= 2, "(the plan has vehicles ahead of him there that keep their lane: %d)" % planned)
	check_eq(found, planned, "each of them is within a metre of where the plan has it")
	var quick_rest: Dictionary = _drive()
	_begin_dawn("market_day", SEED + 40, true)
	_drive(at)
	var slow_seconds: float = _sim.seconds()
	var slow: Dictionary = _road_ahead()
	var slow_rest: Dictionary = _drive()
	check(slow_seconds > quick_seconds + 2.0, "second gear from the sign costs him %.1f s more" % (slow_seconds - quick_seconds))
	check(quick.size() >= 3, "(there is traffic ahead of him there: %d vehicles)" % quick.size())
	check_eq(slow.size(), quick.size(), "and he comes out among the same vehicles")
	var worst: float = 0.0
	for id: Variant in quick:
		if not slow.has(id):
			fail("vehicle %s is ahead of the quick driver and not of the slow one" % str(id))
			continue
		var a: Vector2 = quick[id]
		var b: Vector2 = slow[id]
		worst = maxf(worst, (a - b).length())
	check(worst < 1.0, "each where the plan has it: the road waited for him (the furthest off by %.2f m)" % worst)
	check(_clear(quick_rest) and _clear(slow_rest), "and both reach the end of the road untouched (%s; %s)" % [_what(quick_rest), _what(slow_rest)])
	check_eq(GameData.as_int(slow_rest["close_call"]), 0, "the slow one, too, without a close call: no wall in the stretch of the Call")


## Dawn begun, the scripted driver at its start with the checkpoint's limit
## in his script: from the barriers' mouth, or (`early`) from the sign.
func _begin_dawn(modifier: String, boss_seed: int, early: bool) -> void:
	_new_sim(3)
	_sim.begin_boss("dawn", modifier, boss_seed)
	_driver.begin(_sim.leg.plan)
	var check: Dictionary = GameData.as_dict(GameData.as_dict(data.record("bosses", "dawn").get("dawn")).get("checkpoint"))
	var corridor: Vector3 = _sim.boss.corridor()
	var from: float = corridor.y
	var limit: float = GameData.as_float(check.get("max_kmh"))
	if early:
		# The brake goes on at the sign: nobody slows for a checkpoint he
		# has not been told of.
		var third: float = tuning.fi("gear_speeds", IdealDriver.GEAR - 1)
		var sign_at: float = corridor.x - GameData.as_float(check.get("sign_lead_s")) * third * KMH_TO_MS
		from = sign_at + (third * third - limit * limit) * KMH_TO_MS / (2.0 * tuning.f("brake_decel")) + 1.0
	_driver.limit(from, corridor.z, limit)


## Every vehicle on the road ahead of the car: where it is from the car
## (metres ahead, metres across), by its id.
func _road_ahead() -> Dictionary:
	var out: Dictionary = {}
	for vehicle: TrafficSim.Vehicle in _sim.traffic.vehicles:
		if vehicle.s > _sim.car.s:
			out[vehicle.id] = Vector2(vehicle.s - _sim.car.s, vehicle.x)
	return out


## The Commute's road (GDD 11.5) is a generated road too.
func _check_the_commute() -> void:
	_new_sim(1)
	_sim.begin_commute(SEED)
	_driver.begin(_sim.leg.plan)
	check_near(_sim.leg.length, tuning.f("commute_length"), 0.001, "the Commute is one road of commute_length")
	var drive: Dictionary = _drive()
	check(_clear(drive) and GameData.as_bool(drive["finished"]) and GameData.as_int(drive["close_call"]) == 0, "and it is cleared with no contact (%s)" % _what(drive))


## The driver looks at nothing: what is put in his way by hand, he hits.
func _check_failure_cases() -> void:
	# A slow vehicle moved onto the line.
	var plan: Dictionary = {}
	var moved: bool = false
	for index: int in TWIST_TRIES:
		plan = LegGenerator.generate(data, "open_road", 1, SEED + 300 + index, "").duplicate(true)
		var spawns: Array = GameData.as_array(plan["spawns"])
		for entry: Variant in spawns:
			var spawn: Dictionary = GameData.as_dict(entry)
			var meet: float = GameData.as_float(spawn.get("meet_s"))
			var lane: int = GameData.as_int(spawn.get("lane"))
			if GameData.as_int(spawn.get("direction")) != 1 or lane < 0 or lane != GameData.as_int(spawn.get("change_to")) or meet < 300.0 \
					or meet > GameData.as_float(plan["length"]) - 300.0 or not _line_keeps(plan, meet - 200.0, meet + 200.0):
				continue
			var line_lane: int = _line_lane(plan, meet)
			if line_lane == lane:
				continue
			spawn["lane"] = line_lane
			spawn["change_to"] = line_lane
			moved = true
			break
		if moved:
			break
	if check(moved, "(a leg with a slow vehicle beside a straight piece of the line)"):
		_begin_leg(plan)
		var drive: Dictionary = _drive()
		check(GameData.as_int(drive["hit"]) >= 1, "a vehicle moved onto his line by hand is hit: he does not look (%s)" % _what(drive))
		check(_sim.faults.lamps >= 1, "and a lamp is lit")
	# A pothole on the line.
	plan = LegGenerator.generate(data, "open_road", 1, SEED + 400, "").duplicate(true)
	var middle: float = GameData.as_float(plan["length"]) * 0.5
	_begin_leg(plan)
	GameData.as_array(plan["hazards"]).append({"kind": "pothole", "s": middle, "x": _driver.line_x(middle)})
	GameData.as_array(plan["hazards"]).sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return GameData.as_float(a.get("s")) < GameData.as_float(b.get("s")))
	_begin_leg(plan)
	var holed: Dictionary = _drive()
	check(GameData.as_int(holed["scrape"]) >= 1, "a pothole dug into his line is run over (%s)" % _what(holed))
	# One lane off his line he is in the traffic the line goes round.
	var struck: int = 0
	for index: int in 3:
		var rush: Dictionary = LegGenerator.generate(data, "rush", 2, SEED + 500 + index, "")
		_begin_leg(rush)
		_driver.offset = tuning.f("lane_width") * (1.0 if GameData.as_int(rush.get("start_lane")) == 0 else -1.0)
		var off: Dictionary = _drive()
		struck += GameData.as_int(off["hit"]) + GameData.as_int(off["scrape"]) + GameData.as_int(off["close_call"])
	check(struck >= 1, "a lane's width off the line, on three Rush legs, something is hit or run close (%d times): the line is what is open, not the road" % struck)
	# Dawn without the limit: the soldiers stop him.
	_new_sim(3)
	_sim.begin_boss("dawn", "", SEED)
	_driver.begin(_sim.leg.plan)
	var fast: Dictionary = _drive()
	check(GameData.as_int(fast["searched"]) >= 1, "at Dawn's last checkpoint in third gear he is stopped and searched: the limit belongs in the script")
