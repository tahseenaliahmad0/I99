extends TestSuite
## M4: the nine leg types, driven through DriveSim (GDD 9.1, 9.3).
##
## The car is held on the plan's line in third gear, so each test is about
## what the leg puts on the road, not about steering.

const DT: float = DriveSim.DT
const KMH_TO_MS: float = 1.0 / 3.6
const SAMPLE_SEEDS: int = 40

## What a drive saw.
class DriveLog:
	extends RefCounted
	var seconds: float = 0.0
	## The nearest any vehicle came, along the road, while the car was in a CALM beat.
	var nearest_in_calm: float = INF
	## How far ahead each vehicle was when it appeared (those after the start).
	var appeared_ahead: PackedFloat64Array = PackedFloat64Array()
	## Seconds each lane change was signalled, and seconds each took.
	var signal_seconds: PackedFloat64Array = PackedFloat64Array()
	var move_seconds: PackedFloat64Array = PackedFloat64Array()
	## Lane changes that ended in the lane the plan names.
	var changes_as_planned: int = 0
	var changes_seen: int = 0
	var cone_hits: int = 0
	var most_vehicles: int = 0


var _sim: DriveSim
var _input: DriveInput
var _checker: LegChecker
var _events: Array[Dictionary] = []


func before_each() -> void:
	_sim = DriveSim.new(fresh_data())
	_input = DriveInput.new()
	_checker = LegChecker.new(data)
	_events = []


## T-LEG-01: Open road: 3 lanes, light traffic and long empty stretches
## (CALM beats may be adjacent); par 90 s.
func test_leg_01() -> void:
	var leg: Dictionary = data.record("legs", "open_road")
	check_eq(GameData.as_int(leg.get("lanes")), 3, "GDD 9.1: the Open road has 3 lanes")
	check_near(GameData.as_float(leg.get("par_s")), 90.0, 0.000001, "its par is 90 s")
	check(GameData.as_bool(leg.get("calm_adjacent")), "its CALM beats may be adjacent (GDD 9.2 rule 2)")
	for other: Dictionary in data.records("legs"):
		check(GameData.as_float(other.get("density")) >= GameData.as_float(leg.get("density")),
				"no leg has lighter traffic than the Open road (%s)" % GameData.as_string(other.get("id")))

	# Long empty stretches: more CALM road than any other leg with traffic of
	# its own (on the Two-lane and behind the Motorcade the road is the
	# encounter's), and CALM beats side by side.
	var calm: Dictionary = _calm_metres()
	var open_calm: float = GameData.as_float(calm["open_road"])
	var compared: int = 0
	for id: Variant in calm:
		var kind: String = GameData.as_string(GameData.as_dict(data.record("legs", str(id)).get("special")).get("kind"))
		if str(id) == "open_road" or kind == "two_lane" or kind == "motorcade":
			continue
		compared += 1
		check(open_calm > GameData.as_float(calm[id]), "the Open road has more CALM road (%d m) than %s (%d m)" % [roundi(open_calm), str(id), roundi(GameData.as_float(calm[id]))])
	check_eq(compared, 6, "against the six other legs whose traffic comes from beats")
	check(open_calm >= 3.0 * tuning.f("calm_length"), "on average at least three CALM beats' worth (%d m)" % roundi(open_calm))
	var adjacent: int = 0
	for index: int in SAMPLE_SEEDS:
		if _has_adjacent_calms(LegGenerator.generate(data, "open_road", 1 + index % 3, 500 + index, "")):
			adjacent += 1
	check(adjacent > 0, "on the Open road CALM beats do stand side by side (%d of %d legs)" % [adjacent, SAMPLE_SEEDS])

	# Driven at par.
	var plan: Dictionary = _begin("open_road", 1, 4242)
	var started: Dictionary = _event("leg_started")
	check_eq(GameData.as_string(started.get("leg")), "open_road", "the leg announces itself")
	check_near(GameData.as_float(started.get("par")), 90.0, 0.000001, "with its par")
	var snapshot: Dictionary = _sim.snapshot()
	check_eq(GameData.as_int(snapshot["lanes"]), 3, "the road has 3 lanes")
	check(GameData.as_bool(snapshot["divided"]), "and a median")
	check_eq(_ordinary(plan), LegGenerator.density_target(data, "open_road", 1), "light traffic: 6 vehicles per km of beats in Act 1")
	check_eq(LegGenerator.density_target(data, "open_road", 1), 13, "that is 13 on 2.2 km")
	var cash_before: float = _sim.cash
	var log: DriveLog = _drive(plan)
	check(_sim.leg.finished and not _sim.leg.active, "the leg ends when the car has gone its length")
	check_near(log.seconds, tuning.f("leg_length") / (tuning.fi("gear_speeds", 2) * KMH_TO_MS), 0.05, "in third gear it takes 90 s: par")
	check_eq(_sim.faults.lamps, 0, "on the plan's line no lamp is lit")
	check(log.nearest_in_calm > tuning.f("car_length"), "in CALM beats nothing came level with the car (nearest %s m)" % str(snappedf(log.nearest_in_calm, 0.1)))
	check(log.appeared_ahead.size() >= 3, "traffic appeared along the way (%d vehicles)" % log.appeared_ahead.size())
	for ahead: float in log.appeared_ahead:
		check_near(ahead, tuning.f("spawn_ahead"), 1.0, "each vehicle appears spawn_ahead in front")
	var ended: Dictionary = _event("leg_ended")
	check_eq(GameData.as_string(ended.get("leg")), "open_road", "the end of the leg is announced")
	check_near(GameData.as_float(ended.get("time")), log.seconds, DT, "with the time it took")
	check(GameData.as_bool(ended.get("clean")), "a leg with no lamp lit is clean")
	check_near(GameData.as_float(ended.get("clean_bonus")), tuning.f("clean_leg_bonus"), 0.000001, "and pays the clean-leg bonus (GDD 12.1)")
	check_near(GameData.as_float(ended.get("par_bonus")), 0.0, 0.000001, "at par there is no bonus for time")
	check_near(_sim.cash - cash_before, tuning.f("clean_leg_bonus"), 0.000001, "the cash is his")

	# A clean leg also calms him at its end: -10 Nerves (GDD 6.1). A leg on
	# which a lamp was lit does not.
	check_near(tuning.f("clean_leg_nerves"), -10.0, 0.000001, "GDD 6.1: a clean leg is -10 Nerves at its end")
	for lamp_lit: bool in [false, true]:
		_begin_quiet("open_road", 1, 5)
		_sim.nerves.set_value(60.0)
		if lamp_lit:
			var guard: int = int(5.0 / DT)
			while _sim.faults.lamps == 0 and guard > 0:
				guard -= 1
				_sim.car.x = _sim.car.guardrail_x()
				_sim.step(_input)
			for _tick: int in int(1.5 / DT):
				_hold_lane_and_step(1)
			_sim.gate.reset(3)
		_sim.car.s = _sim.leg.length - 5.0
		var before: float = 0.0
		while _sim.leg.active:
			before = _sim.nerves.value
			_hold_lane_and_step(1)
		if lamp_lit:
			check(not GameData.as_bool(_event("leg_ended").get("clean")), "a leg on which a lamp was lit is not clean")
			check(absf(_sim.nerves.value - before) < 0.05, "and brings no relief at its end (%s)" % str(snappedf(_sim.nerves.value - before, 0.001)))
		else:
			check_near(_sim.nerves.value - before, tuning.f("clean_leg_nerves"), 0.05, "at the end of a clean leg his Nerves drop by 10 (%s)" % str(snappedf(_sim.nerves.value - before, 0.001)))


## T-LEG-02: Rush: heavy traffic with frequent merges; par 90 s.
func test_leg_02() -> void:
	var leg: Dictionary = data.record("legs", "rush")
	check_near(GameData.as_float(leg.get("par_s")), 90.0, 0.000001, "GDD 9.1: Rush has a par of 90 s")
	check_near(GameData.as_float(leg.get("density")), 16.0, 0.000001, "its traffic is heavy: 16 vehicles per km")
	for other: Dictionary in data.records("legs"):
		check(GameData.as_float(other.get("density")) <= GameData.as_float(leg.get("density")),
				"no leg has heavier traffic than Rush (%s)" % GameData.as_string(other.get("id")))

	# Frequent merges: more MERGE beats than any other leg type.
	var merges: Dictionary = {}
	for other: Dictionary in data.records("legs"):
		var id: String = GameData.as_string(other.get("id"))
		var acts: Array = GameData.as_array(other.get("acts"))
		var count: int = 0
		for index: int in SAMPLE_SEEDS:
			var plan: Dictionary = LegGenerator.generate(data, id, GameData.as_int(acts[index % acts.size()]), 900 + index, "")
			for entry: Variant in GameData.as_array(plan["beats"]):
				if GameData.as_string(GameData.as_dict(entry)["type"]) == "MERGE":
					count += 1
		merges[id] = float(count) / float(SAMPLE_SEEDS)
	var rush_merges: float = GameData.as_float(merges["rush"])
	check(rush_merges >= 2.0, "a Rush leg has at least two MERGE beats on average (%s)" % str(snappedf(rush_merges, 0.1)))
	for id: Variant in merges:
		if str(id) != "rush":
			check(rush_merges > GameData.as_float(merges[id]), "Rush merges more often (%s a leg) than %s (%s)" % [str(snappedf(rush_merges, 0.1)), str(id), str(snappedf(GameData.as_float(merges[id]), 0.1))])

	# A merge is a vehicle that signals and moves into his lane (GDD 9.2):
	# the lane the plan's line is in when the beat begins.
	var checked: int = 0
	for index: int in SAMPLE_SEEDS:
		var plan: Dictionary = LegGenerator.generate(data, "rush", 1 + index % 3, 900 + index, "")
		for entry: Variant in GameData.as_array(plan["spawns"]):
			var spawn: Dictionary = entry
			if GameData.as_int(spawn["change_to"]) == GameData.as_int(spawn["lane"]):
				continue
			checked += 1
			check_eq(absi(GameData.as_int(spawn["change_to"]) - GameData.as_int(spawn["lane"])), 1, "a merging vehicle moves one lane over")
			check(GameData.as_float(spawn["change_gap"]) >= tuning.f("car_length"), "it starts to signal while still ahead of him")
	check(checked >= SAMPLE_SEEDS, "enough merges were looked at (%d)" % checked)

	# Driven at par, Act 1 (no late signallers) and Act 3.
	for act: int in [1, 3]:
		_sim = DriveSim.new(fresh_data())
		_events = []
		var plan: Dictionary = _begin("rush", act, 7001 + act)
		check_eq(_ordinary(plan), LegGenerator.density_target(data, "rush", act), "act %d: %d vehicles on the leg" % [act, LegGenerator.density_target(data, "rush", act)])
		var log: DriveLog = _drive(plan)
		check_near(log.seconds, 90.0, 0.05, "act %d: in third gear the leg takes 90 s: par" % act)
		check_eq(_sim.faults.lamps, 0, "act %d: the plan's line lights no lamp" % act)
		check(log.changes_seen >= 1, "act %d: vehicles changed lane in front of him (%d)" % [act, log.changes_seen])
		check_eq(log.changes_as_planned, log.changes_seen, "act %d: each ended in the lane the beat names" % act)
		for seconds: float in log.signal_seconds:
			var normal: bool = absf(seconds - tuning.f("signal_time")) <= 2.0 * DT
			var late: bool = absf(seconds - tuning.f("late_signal_time")) <= 2.0 * DT
			if act == 1:
				check(normal, "act 1: every lane change is signalled for signal_time (%s s)" % str(snappedf(seconds, 0.01)))
			else:
				check(normal or late, "act 3: a lane change is signalled for signal_time or late_signal_time (%s s)" % str(snappedf(seconds, 0.01)))
		for seconds: float in log.move_seconds:
			check_near(seconds, tuning.f("lane_change_time"), 2.0 * DT, "the move itself takes lane_change_time")
		check(log.most_vehicles >= 6, "act %d: the road is busy (%d vehicles at once)" % [act, log.most_vehicles])
	check_eq(LegGenerator.density_target(data, "rush", 1), 35, "16 per km is 35 vehicles in Act 1")
	check_eq(LegGenerator.density_target(data, "rush", 3), 44, "and 20 per km, 44, in Act 3")


## T-LEG-03: Rain: the view blurs over 6 s without a wiper sweep and sideways
## response is 30% slower; par 95 s.
func test_leg_03() -> void:
	var leg: Dictionary = data.record("legs", "rain")
	check_near(GameData.as_float(leg.get("par_s")), 95.0, 0.000001, "GDD 9.1: Rain has a par of 95 s")
	check_eq(GameData.as_string(leg.get("condition")), "rain", "it rains on a Rain leg")
	check_near(tuning.f("wiper_clear_time"), 6.0, 0.000001, "the view blurs over 6 s")
	check_near(tuning.f("rain_response_mult"), 1.3, 0.000001, "sideways response is 30% slower")

	# Dry road first: no blur, the car's own response.
	var dry: Dictionary = _begin("open_road", 1, 31)
	check(not GameData.as_bool(_sim.snapshot()["raining"]), "it does not rain on the Open road")
	_drive_to(dry, 300.0)
	check_near(GameData.as_float(_sim.snapshot()["rain_blur"]), 0.0, 0.000001, "and nothing blurs the view")
	var dry_tau: float = _response_time()

	_sim = DriveSim.new(fresh_data())
	_events = []
	var plan: Dictionary = _begin("rain", 1, 31)
	check(GameData.as_bool(_sim.snapshot()["raining"]), "on a Rain leg it rains from the start")
	var wipers: Dictionary = data.record("rituals", "wipers")
	_sim.items.complete(wipers, Gesture.DIR_UP)
	check_near(GameData.as_float(_sim.snapshot()["rain_blur"]), 0.0, 0.000001, "a sweep clears the view")
	_drive_seconds(plan, 3.0)
	check_near(GameData.as_float(_sim.snapshot()["rain_blur"]), 0.5, 0.01, "3 s later it is half blurred")
	_drive_seconds(plan, 3.0)
	check_near(GameData.as_float(_sim.snapshot()["rain_blur"]), 1.0, 0.01, "6 s after the sweep it is fully blurred")
	_drive_seconds(plan, 2.0)
	check_near(GameData.as_float(_sim.snapshot()["rain_blur"]), 1.0, 0.000001, "and stays so until the next sweep")
	_sim.items.complete(wipers, Gesture.DIR_UP)
	check_near(GameData.as_float(_sim.snapshot()["rain_blur"]), 0.0, 0.000001, "which clears it again")

	check_near(_sim.car.lat_tau_mult, tuning.f("rain_response_mult"), 0.000001, "the rain slows the car's sideways response")
	var wet_tau: float = _response_time()
	check_near(wet_tau / dry_tau, 1.3, 0.005, "at full lock the car takes 30%% longer to answer (%s s against %s s)" % [str(snappedf(wet_tau, 0.001)), str(snappedf(dry_tau, 0.001))])
	check_near(dry_tau, tuning.f("lat_follow_tau"), 0.002, "on a dry road the response time is lat_follow_tau")

	# The whole leg at par: 5 s under par.
	_sim = DriveSim.new(fresh_data())
	_events = []
	plan = _begin("rain", 2, 77)
	var log: DriveLog = _drive(plan)
	check_near(log.seconds, 90.0, 0.05, "in third gear the leg takes 90 s")
	var ended: Dictionary = _event("leg_ended")
	check_near(GameData.as_float(ended.get("par")), 95.0, 0.000001, "against a par of 95 s")
	check_near(GameData.as_float(ended.get("par_bonus")), floorf((95.0 - log.seconds) * tuning.f("par_bonus_rate")), 0.000001, "5 s under par pays 1 cash per 2 s (GDD 12.1)")
	check(not GameData.as_bool(_sim.snapshot()["raining"]), "when the leg is over the rain is over")
	check_near(_sim.car.lat_tau_mult, 1.0, 0.000001, "and the car answers as on a dry road")
	check_near(GameData.as_float(_sim.snapshot()["rain_blur"]), 0.0, 0.000001, "with a clear view")


## T-LEG-04: Night blackout: the road is unlit, the view is the headlight cone
## (60 m, 100 m on high beam) and hazards appear late; par 90 s.
func test_leg_04() -> void:
	var leg: Dictionary = data.record("legs", "night")
	check_near(GameData.as_float(leg.get("par_s")), 90.0, 0.000001, "GDD 9.1: Night blackout has a par of 90 s")
	check_eq(GameData.as_string(leg.get("condition")), "night", "its road is unlit")
	check(not GameData.as_array(leg.get("acts")).has(1.0), "it is not driven in Act 1")
	var low: float = tuning.f("low_beam_cone")
	var high: float = tuning.f("high_beam_cone")
	check_near(low, 60.0, 0.000001, "GDD 4.6: the low beam reaches 60 m")
	check_near(high, 100.0, 0.000001, "the high beam 100 m")

	# By day everything ahead is in view.
	var day: Dictionary = _begin("open_road", 2, 5)
	check(not GameData.as_bool(_sim.snapshot()["night"]), "the Open road is lit")
	check(GameData.as_float(_sim.snapshot()["visibility"]) > tuning.f("road_draw_ahead"), "and he sees as far as the road is drawn")
	check(not day.is_empty(), "a day leg was generated")

	# A night leg with a hazard ahead of the start.
	_sim = DriveSim.new(fresh_data())
	_events = []
	var plan: Dictionary = _night_plan_with_hazard()
	var hazard_s: float = _first_hazard_s(plan)
	if not check(hazard_s > high + 20.0, "the leg has a hazard well beyond the high beam (at %s m)" % str(hazard_s)):
		return
	_sim.gate.reset(3)
	_sim.begin_leg(plan)
	_checker.load_plan(plan)
	var snapshot: Dictionary = _sim.snapshot()
	check(GameData.as_bool(snapshot["night"]), "on a Night leg the road is unlit")
	check_near(GameData.as_float(snapshot["visibility"]), low, 0.000001, "the view is the headlight cone: 60 m on low beam")
	check_near(GameData.as_float(snapshot["headlight_cone"]), low, 0.000001, "the snapshot carries the cone")
	check_eq(_hazards_in_view().size(), 0, "a hazard beyond the cone is not in view")

	# It comes into view only when the cone reaches it.
	_drive_to(plan, hazard_s - low - 5.0)
	check_eq(_hazards_in_view().size(), 0, "5 m before the cone reaches it, it is still dark")
	_drive_to(plan, hazard_s - low + 2.0)
	var seen: Array = _hazards_in_view()
	if check(seen.size() >= 1, "then it appears, late"):
		check(GameData.as_float(GameData.as_dict(seen[0])["ahead"]) <= low, "inside the cone (%s m ahead)" % str(snappedf(GameData.as_float(GameData.as_dict(seen[0])["ahead"]), 0.1)))

	# High beam reaches further; a dead headlight halves the cone.
	_sim = DriveSim.new(fresh_data())
	_events = []
	_sim.gate.reset(3)
	_sim.begin_leg(plan)
	_checker.load_plan(plan)
	_sim.items.complete(data.record("rituals", "headlights"), 0)
	check_near(GameData.as_float(_sim.snapshot()["visibility"]), high, 0.000001, "on high beam the cone is 100 m")
	_drive_to(plan, hazard_s - high + 2.0)
	check(_hazards_in_view().size() >= 1, "and the hazard shows from 100 m")
	_sim.items.complete(data.record("rituals", "headlights"), 0)
	check_near(GameData.as_float(_sim.snapshot()["visibility"]), low, 0.000001, "back on low beam: 60 m")
	_sim.faults.deck.erase(&"dead_headlight")
	_sim.faults.deck.push_front(&"dead_headlight")
	_sim.faults.light(1)
	var mult: float = _sim.faults.param_of(&"dead_headlight", "night_cone_mult", 1.0)
	check(mult < 1.0, "a dead headlight shortens the cone (GDD 6.3)")
	check_near(GameData.as_float(_sim.snapshot()["visibility"]), low * mult, 0.000001, "to %s m on low beam" % str(low * mult))

	# Hazards are what a Night leg is about: more HAZARD beats than by day.
	var night_hazards: int = 0
	var day_hazards: int = 0
	for index: int in SAMPLE_SEEDS:
		night_hazards += _beats_of(LegGenerator.generate(data, "night", 2 + index % 2, 300 + index, ""), "HAZARD")
		day_hazards += _beats_of(LegGenerator.generate(data, "open_road", 2 + index % 2, 300 + index, ""), "HAZARD")
	check(night_hazards > day_hazards, "Night legs have more HAZARD beats (%d against %d on the Open road)" % [night_hazards, day_hazards])

	# The whole leg at par.
	_sim = DriveSim.new(fresh_data())
	_events = []
	plan = _begin("night", 2, 88)
	var log: DriveLog = _drive(plan)
	check_near(log.seconds, 90.0, 0.05, "in third gear the leg takes 90 s: par")
	check_eq(_sim.faults.lamps, 0, "the plan's line lights no lamp in the dark either")
	check(is_inf(GameData.as_float(_sim.snapshot()["visibility"])), "when the leg is over the dark is over")


## T-LEG-05: Roadworks: three 150 m chicanes one lane wide (2.16 m) between
## cones; par 100 s.
func test_leg_05() -> void:
	var leg: Dictionary = data.record("legs", "roadworks")
	check_near(GameData.as_float(leg.get("par_s")), 100.0, 0.000001, "GDD 9.1: Roadworks has a par of 100 s")
	var special: Dictionary = GameData.as_dict(leg.get("special"))
	check_eq(GameData.as_int(special.get("chicanes")), 3, "three chicanes")
	check_near(GameData.as_float(special.get("length_m")), 150.0, 0.000001, "each 150 m long")
	check_near(GameData.as_float(special.get("width_m")), 2.16, 0.000001, "and 2.16 m wide")

	var cone: Dictionary = data.record("hazard_kinds", "cone")
	var cone_half_width: float = GameData.as_float(cone.get("width")) * 0.5
	var room: float = (GameData.as_float(special.get("width_m")) - tuning.f("car_width")) * 0.5
	for index: int in 8:
		var plan: Dictionary = LegGenerator.generate(data, "roadworks", 2 + index % 2, 60 + index, "")
		var zones: Array = GameData.as_array(plan["zones"])
		check_eq(zones.size(), 3, "seed %d: the leg has three chicanes" % (60 + index))
		var previous_end: float = 0.0
		for entry: Variant in zones:
			var zone: Dictionary = entry
			var start: float = GameData.as_float(zone["s"])
			var length: float = GameData.as_float(zone["length"])
			check_eq(GameData.as_string(zone["kind"]), "chicane", "a zone of a Roadworks leg is a chicane")
			check_near(length, 150.0, 0.000001, "150 m long")
			check(start >= previous_end, "chicanes do not overlap")
			check(start + length <= GameData.as_float(plan["beats_end"]), "and lie within the beats")
			check_eq(absi(GameData.as_int(zone["to_lane"]) - GameData.as_int(zone["from_lane"])), 1, "a chicane shifts the road by one lane")
			previous_end = start + length
			# Between the cones: 2.16 m of clear road where the corridor runs straight.
			var left: float = -INF
			var right: float = INF
			var cones: int = 0
			var centre: float = tuning.f("lane_width") * (float(GameData.as_int(zone["from_lane"])) + 0.5)
			var straight: float = (length - GameData.as_float(zone["shift"])) * 0.5
			for hazard: Variant in GameData.as_array(plan["hazards"]):
				var record: Dictionary = hazard
				var s: float = GameData.as_float(record["s"])
				if GameData.as_string(record["kind"]) != "cone" or s < start or s > start + length:
					continue
				cones += 1
				if s > start + straight - tuning.f("car_length"):
					continue
				var x: float = GameData.as_float(record["x"])
				if x < centre:
					left = maxf(left, x + cone_half_width)
				else:
					right = minf(right, x - cone_half_width)
			check(cones >= 2 * int(length / GameData.as_float(special.get("cone_spacing_m"))) - 2, "cones line both sides (%d)" % cones)
			check_near(right - left, GameData.as_float(special.get("width_m")), 0.001, "the corridor is one lane wide: 2.16 m between the cones")
			check_near((right + left) * 0.5, centre, 0.001, "and starts on a lane's centre")

	# Driven down the middle: no cone is touched. A little to one side: cones fly.
	var plan: Dictionary = _begin("roadworks", 2, 61)
	var log: DriveLog = _drive(plan)
	check_near(log.seconds, 90.0, 0.05, "in third gear the leg takes 90 s, 10 s under its par")
	check_eq(log.cone_hits, 0, "down the middle of the corridors no cone is touched")
	check_eq(_sim.faults.lamps, 0, "and no lamp is lit")
	check_near(GameData.as_float(_event("leg_ended").get("par_bonus")), floorf((100.0 - log.seconds) * tuning.f("par_bonus_rate")), 0.000001, "10 s under par pays 5 cash")

	_sim = DriveSim.new(fresh_data())
	_events = []
	plan = _begin("roadworks", 2, 61)
	_sim.in_encounter = true
	var first: Dictionary = GameData.as_array(plan["zones"])[0]
	_drive_to(plan, GameData.as_float(first["s"]) - 1.0)
	var nerves_before: float = _sim.nerves.value
	var lamps_before: int = _sim.faults.lamps
	var slipped: DriveLog = _drive_to(plan, GameData.as_float(first["s"]) + 40.0, room + 0.05)
	check(slipped.cone_hits >= 3, "%s m off the middle the car clips the cones on that side (%d)" % [str(room + 0.05), slipped.cone_hits])
	check_eq(_sim.faults.lamps, lamps_before, "cones light no lamp (GDD 5.6)")
	check_near(_sim.nerves.value - nerves_before, float(slipped.cone_hits) * tuning.f("cone_nerves"), 0.6, "each adds 3 Nerves")
	check_near(GameData.as_float(cone.get("nerves")), tuning.f("cone_nerves"), 0.000001, "the cone's data agrees with cone_nerves")
	var inside: DriveLog = _drive_to(plan, GameData.as_float(first["s"]) + 48.0, room - 0.05)
	check_eq(inside.cone_hits, 0, "%s m off the middle it still passes clean" % str(room - 0.05))


## T-LEG-06: Tailgater: a driver sits on the bumper for 40 s, adds 1 Nerves
## per second and rams (a scrape from behind) if the player brakes; he leaves
## when the player changes lane and holds it for 3 s, then passes and brakes
## hard in front once; fourth gear for 10 s also loses him.
func test_leg_06() -> void:
	var leg: Dictionary = data.record("legs", "tailgater")
	var special: Dictionary = GameData.as_dict(leg.get("special"))
	var at: float = GameData.as_float(special.get("at_s"))
	var tell: float = GameData.as_float(special.get("tell_s"))
	var duration: float = GameData.as_float(special.get("duration_s"))
	var gap: float = GameData.as_float(special.get("gap_m"))
	check_near(GameData.as_float(leg.get("par_s")), 90.0, 0.000001, "GDD 9.1: Tailgater has a par of 90 s")
	check_near(duration, 40.0, 0.000001, "a driver sits on the bumper for 40 s")
	check_near(GameData.as_float(special.get("nerves_per_s")), 1.0, 0.000001, "GDD 6.1: a Tailgater behind is +1 Nerves per second")
	check_near(GameData.as_float(special.get("lane_hold_s")), 3.0, 0.000001, "GDD 9.3: a lane change held for 3 s loses him")
	check_eq(GameData.as_int(special.get("gear")), 4, "so does fourth gear")
	check_near(GameData.as_float(special.get("gear_hold_s")), 10.0, 0.000001, "held for 10 s")
	check(not GameData.as_array(leg.get("acts")).has(1.0), "there is no Tailgater in Act 1")

	# Doing nothing: he arrives, sits there for 40 s, and gives up.
	_begin_quiet("tailgater", 2, 71)
	var seen_from: float = -1.0
	var on_from: float = -1.0
	var gone_at: float = -1.0
	var worst_gap: float = 0.0
	var on_ticks: int = 0
	var nerves_at_20: float = 0.0
	var nerves_at_50: float = 0.0
	var appeared_behind: float = 0.0
	while _sim.leg.active and _sim.leg.time < at + duration + 8.0:
		_hold_lane_and_step(1)
		var now: float = _sim.leg.time
		var driver: TrafficSim.Vehicle = _sim.encounter.tailgater()
		if driver != null and seen_from < 0.0:
			seen_from = now
			appeared_behind = _sim.car.s - driver.s
		if _sim.encounter.tail_phase == EncounterSim.TAIL_ON_BUMPER:
			if on_from < 0.0:
				on_from = now
			on_ticks += 1
			if driver != null:
				var behind: float = (_sim.car.s - _sim.car.length() * 0.5) - (driver.s + driver.half_length)
				worst_gap = maxf(worst_gap, absf(behind - gap))
		if _sim.encounter.tail_phase == EncounterSim.TAIL_GONE and gone_at < 0.0:
			gone_at = now
		if absf(now - 20.0) < DT * 0.5:
			nerves_at_20 = _sim.nerves.value
		if absf(now - 50.0) < DT * 0.5:
			nerves_at_50 = _sim.nerves.value
	check_near(seen_from, at - tell, 2.0 * DT, "he shows up %s s before he is on the bumper (%s s)" % [str(tell), str(snappedf(seen_from, 0.01))])
	check_near(appeared_behind, GameData.as_float(special.get("spawn_behind_m")), 2.0, "well behind, where the mirror shows him")
	check_near(on_from, at, 2.0 * DT, "he is on the bumper %s s into the leg" % str(at))
	check_near(gone_at - on_from, duration, 2.0 * DT, "and sits there for 40 s (%s s)" % str(snappedf(gone_at - on_from, 0.01)))
	check(worst_gap < 0.2, "%s m behind his bumper, in his tracks (never more than %s m off)" % [str(gap), str(snappedf(worst_gap, 0.01))])
	var per_second: float = (nerves_at_50 - nerves_at_20) / 30.0
	check_near(per_second, GameData.as_float(special.get("nerves_per_s")) + tuning.f("traffic_rate"), 0.01,
			"he adds 1 Nerves per second, on top of what any vehicle that near adds (%s a second)" % str(snappedf(per_second, 0.001)))
	check_eq(_sim.faults.lamps, 0, "left alone, he never touches the car")
	check(not _sim.encounter.active, "then the encounter is over")
	check(not _has_event_named("hit"), "with no hit")

	# He brakes: a scrape from behind.
	_begin_quiet("tailgater", 2, 71)
	_drive_quiet_until(20.0, 1)
	var driver: TrafficSim.Vehicle = _sim.encounter.tailgater()
	if not check(driver != null and _sim.encounter.tail_phase == EncounterSim.TAIL_ON_BUMPER, "(at 20 s he is on the bumper)"):
		return
	var driver_id: int = driver.id
	_events = []
	var nerves_before: float = _sim.nerves.value
	_input.rmb = true
	_drive_quiet_until(20.25, 1)
	_input.rmb = false
	_drive_quiet_until(20.5, 1)
	var hits: Array[Dictionary] = _events_named("hit")
	if check_eq(hits.size(), 1, "a touch of the brake and he rams: one hit"):
		check_eq(GameData.as_int(hits[0].get("kind")), int(Collision.Hit.SCRAPE), "a scrape")
		check_eq(GameData.as_int(hits[0].get("vehicle")), driver_id, "by the driver behind")
	check_eq(_sim.faults.lamps, int(tuning.fi("hit_lamps", 0)), "one lamp")
	check(_sim.nerves.value - nerves_before >= tuning.fi("hit_nerves", 0), "and +10 Nerves")
	driver = _sim.encounter.tailgater()
	check(driver != null and driver.s < _sim.car.s, "it came from behind: he is still behind the car")
	_drive_quiet_until(23.5, 1)
	check_eq(_sim.encounter.tail_phase, EncounterSim.TAIL_ON_BUMPER, "afterwards he is back on the bumper")
	_input.rmb = true
	_drive_quiet_until(23.7, 1)
	_input.rmb = false
	_drive_quiet_until(24.5, 1)
	check_eq(_sim.faults.lamps, 2 * int(tuning.fi("hit_lamps", 0)), "braking again is rammed again")
	# Slowing down without the brake is not braking.
	_begin_quiet("tailgater", 2, 71)
	_drive_quiet_until(20.0, 1)
	_sim.gate.reset(2)
	_drive_quiet_until(26.0, 1)
	check_eq(_sim.faults.lamps, 0, "dropping to second gear is not braking: he does not ram")
	check_eq(_sim.encounter.tail_phase, EncounterSim.TAIL_ON_BUMPER, "and he stays on the bumper")

	# A lane change that is not held does not lose him.
	_begin_quiet("tailgater", 2, 71)
	_drive_quiet_until(20.0, 1)
	_drive_quiet_until(22.0, 2)
	driver = _sim.encounter.tailgater()
	check(driver != null and absf(driver.x - _sim.traffic.lane_center(1)) < 0.01, "when he changes lane the driver behind keeps his own")
	check_near(_sim.encounter.nerves_rate, 0.0, 0.000001, "and is no longer on his bumper: nothing is added to his Nerves")
	_drive_quiet_until(25.0, 1)
	check_eq(_sim.encounter.tail_phase, EncounterSim.TAIL_ON_BUMPER, "back in the lane after 2 s, he has him on the bumper again")
	# Held for 3 s: he passes, cuts in and brakes hard once.
	_events = []
	var changed_at: float = _sim.leg.time
	var passing_from: float = -1.0
	var braking_from: float = -1.0
	var cut_offs: int = 0
	var slowest: float = INF
	var speed_at_brake: float = 0.0
	var gap_at_brake: float = 0.0
	var nearest: float = INF
	var nerves_cut: float = 0.0
	while _sim.encounter.active and _sim.leg.time < changed_at + 20.0:
		var nerves_tick: float = _sim.nerves.value
		_hold_lane_and_step(2)
		driver = _sim.encounter.tailgater()
		if _sim.encounter.tail_phase == EncounterSim.TAIL_PASSING and passing_from < 0.0:
			passing_from = _sim.leg.time
		if _sim.encounter.cut_off:
			cut_offs += 1
			nerves_cut = _sim.nerves.value - nerves_tick
		if _sim.encounter.tail_phase == EncounterSim.TAIL_BRAKING and driver != null:
			if braking_from < 0.0:
				braking_from = _sim.leg.time
				speed_at_brake = _sim.car.speed
				gap_at_brake = (driver.s - driver.half_length) - (_sim.car.s + _sim.car.length() * 0.5)
				check(absf(driver.x - _sim.car.x) < 0.01, "he is in the player's lane when he brakes")
			slowest = minf(slowest, driver.speed)
			nearest = minf(nearest, (driver.s - driver.half_length) - (_sim.car.s + _sim.car.length() * 0.5))
	check_near(passing_from - changed_at, GameData.as_float(special.get("lane_hold_s")), 3.0 * DT, "3 s after the lane change he pulls out to pass (%s s)" % str(snappedf(passing_from - changed_at, 0.01)))
	check(braking_from > passing_from, "he passes, and then brakes in front")
	check_near(gap_at_brake, GameData.as_float(special.get("brake_gap_m")), 0.5, "%s m ahead of his bumper" % str(GameData.as_float(special.get("brake_gap_m"))))
	check_near(speed_at_brake - slowest, GameData.as_float(special.get("brake_drop_kmh")), 1.0, "hard: he sheds 40 km/h")
	check_eq(cut_offs, 1, "once")
	check_near(nerves_cut, tuning.f("cut_off_nerves"), 0.05, "being cut off is +5 Nerves (GDD 6.1)")
	check(nearest > 0.5, "a driver who holds third gear is not hit (nearest %s m)" % str(snappedf(nearest, 0.1)))
	check_eq(_sim.faults.lamps, 0, "no lamp is lit")
	check(not _sim.encounter.active and _sim.encounter.tail_phase == EncounterSim.TAIL_GONE, "and then he is gone")
	check(_sim.encounter.tailgater() == null, "nobody is on the bumper any more")

	# Fourth gear for 10 s also loses him; 9 s do not.
	_begin_quiet("tailgater", 2, 71)
	_drive_quiet_until(20.0, 1)
	_sim.gate.reset(4)
	_drive_quiet_until(29.0, 1)
	check_eq(_sim.encounter.tail_phase, EncounterSim.TAIL_ON_BUMPER, "after 9 s of fourth gear he is still there")
	_drive_quiet_until(30.2, 1)
	check_eq(_sim.encounter.tail_phase, EncounterSim.TAIL_GONE, "after 10 s he is lost")
	check(not _sim.encounter.cut_off and not _has_event_named("hit"), "without a pass, a brake or a touch")
	_begin_quiet("tailgater", 2, 71)
	_drive_quiet_until(20.0, 1)
	_sim.gate.reset(4)
	_drive_quiet_until(29.0, 1)
	_sim.gate.reset(3)
	_drive_quiet_until(31.0, 1)
	_sim.gate.reset(4)
	_drive_quiet_until(40.0, 1)
	check_eq(_sim.encounter.tail_phase, EncounterSim.TAIL_ON_BUMPER, "the 10 s must be unbroken: 9 s, third, and 9 s more do not lose him")

	# Other legs have no Tailgater; the whole leg at par with its traffic lights no lamp.
	_sim = DriveSim.new(fresh_data())
	_events = []
	var plan: Dictionary = _begin("tailgater", 3, 72)
	var log: DriveLog = _drive(plan)
	check_near(log.seconds, 90.0, 0.05, "in third gear on the plan's line the leg takes 90 s: par")
	check_eq(_sim.faults.lamps, 0, "and lights no lamp, Tailgater and all")
	_sim = DriveSim.new(fresh_data())
	_begin("open_road", 2, 72)
	_drive_to(LegGenerator.generate(data, "open_road", 2, 72, ""), 900.0)
	check(_sim.encounter.tailgater() == null and not _sim.encounter.active, "the Open road has no Tailgater")

	_check_tailgater_in_traffic(special)


## The Tailgater among other vehicles (D-067): he drives through nobody and
## keeps off the road the leg needs.
func _check_tailgater_in_traffic(special: Dictionary) -> void:
	var hold: float = GameData.as_float(special.get("lane_hold_s"))
	var merge: float = GameData.as_float(special.get("merge_s"))
	var follow: float = tuning.f("traffic_follow_gap")
	var end: float = GameData.as_float(special.get("at_s")) + GameData.as_float(special.get("duration_s"))

	# A slow truck in his lane when the car leaves it: he cannot keep level,
	# and swerves in behind the car again.
	_begin_quiet_straight("tailgater", 2, 71)
	_drive_quiet_until(20.0, 1)
	var truck: TrafficSim.Vehicle = _sim.traffic.spawn(&"truck", 1, _sim.car.s + 30.0, 60.0)
	var driver: TrafficSim.Vehicle = _sim.encounter.tailgater()
	if not check(truck != null and driver != null and _sim.encounter.tail_phase == EncounterSim.TAIL_ON_BUMPER, "(on the bumper at 20 s, a truck 30 m ahead in the lane)"):
		return
	var driver_id: int = driver.id
	var changed_at: float = _sim.leg.time
	var through: int = 0
	var level_ticks: int = 0
	var came_in_at: float = -1.0
	while _sim.leg.time < changed_at + hold - 2.0 * DT:
		_hold_lane_and_step(2)
		driver = _sim.encounter.tailgater()
		if driver == null:
			break
		through += _inside_another(driver)
		if absf(driver.x - _sim.traffic.lane_center(1)) < 0.01:
			level_ticks += 1
		elif came_in_at < 0.0:
			came_in_at = _sim.leg.time
	check(level_ticks > 0, "the car changes lane: at first he keeps his own")
	check(came_in_at > changed_at and came_in_at < changed_at + hold - merge, "with the truck %d m in front of him he swerves in behind the car (%.2f s after the change)" % [roundi(follow), came_in_at - changed_at])
	if check(driver != null and _sim.encounter.tail_phase == EncounterSim.TAIL_ON_BUMPER, "he is on the bumper again: passing a slow vehicle does not lose him"):
		check(absf(driver.x - _sim.car.x) < 0.01, "in the car's lane, behind it")
		check(_sim.encounter.nerves_rate > 0.0, "and on his Nerves again")
	# The lane change is held for 3 s all the same: off the bumper for good.
	_drive_quiet_until(changed_at + hold + 2.0 * DT, 2)
	check_eq(_sim.encounter.tail_phase, EncounterSim.TAIL_HANGING_BACK, "3 s after the change he is off the bumper: he hangs back (the truck is still beside the car)")
	check_near(_sim.encounter.nerves_rate, 0.0, 0.000001, "and adds nothing to his Nerves")
	# He goes by when the lane beside the car is clear of the truck.
	var passing_from: float = -1.0
	var pass_x: float = 0.0
	var cut_offs: int = 0
	var gap_at_brake: float = -1.0
	var nearest: float = INF
	var behind_when_passing: float = 0.0
	var truck_behind_when_passing: float = 0.0
	while _sim.encounter.active and _sim.leg.time < changed_at + 30.0:
		_hold_lane_and_step(2)
		driver = _sim.encounter.tailgater()
		if driver == null:
			break
		through += _inside_another(driver)
		var gap: float = (driver.s - driver.half_length) - (_sim.car.s + _sim.car.length() * 0.5)
		if _sim.encounter.tail_phase == EncounterSim.TAIL_HANGING_BACK:
			behind_when_passing = (_sim.car.s - _sim.car.length() * 0.5) - (driver.s + driver.half_length)
			truck_behind_when_passing = _sim.car.s - truck.s
		if _sim.encounter.tail_phase == EncounterSim.TAIL_PASSING and passing_from < 0.0:
			passing_from = _sim.leg.time
		if _sim.encounter.tail_phase == EncounterSim.TAIL_CUTTING_IN and pass_x == 0.0:
			pass_x = driver.x
		if _sim.encounter.cut_off:
			cut_offs += 1
		if _sim.encounter.tail_phase == EncounterSim.TAIL_BRAKING:
			if gap_at_brake < 0.0:
				gap_at_brake = gap
			nearest = minf(nearest, gap)
	check_near(behind_when_passing, follow, 0.3, "hanging back he is traffic_follow_gap behind the bumper (%.1f m)" % behind_when_passing)
	check(passing_from > changed_at + hold, "he pulls out when there is room beside the car (%.1f s after the change)" % (passing_from - changed_at))
	check(truck_behind_when_passing > follow + truck.half_length, "the truck is well behind by then (%.0f m)" % truck_behind_when_passing)
	check_near(pass_x, _sim.traffic.lane_center(1), 0.01, "he goes by in the lane beside the car")
	check_eq(cut_offs, 1, "cuts in once")
	check_near(gap_at_brake, GameData.as_float(special.get("brake_gap_m")), 0.5, "%d m ahead of his bumper" % roundi(GameData.as_float(special.get("brake_gap_m"))))
	check(nearest > 0.5 and _sim.faults.lamps == 0, "and a driver who holds third gear is not touched (nearest %.1f m)" % nearest)
	check_eq(_sim.encounter.tail_phase, EncounterSim.TAIL_GONE, "then he is gone")
	check_eq(through, 0, "in all of it he was never inside another vehicle")
	# Where he went: out of the car's lane, slower than the car, falling behind.
	var gone: TrafficSim.Vehicle = null
	for vehicle: TrafficSim.Vehicle in _sim.traffic.vehicles:
		if vehicle.id == driver_id:
			gone = vehicle
	if check(gone != null, "(he is still on the road)"):
		check(absf(gone.x - _sim.car.x) >= gone.half_width + _sim.car.half_width(), "after his stab at the brake he is out of the car's lane")
		check(gone.speed < _sim.car.speed, "and slower than the car")
		_drive_quiet_until(_sim.leg.time + 4.0, 2)
		check(gone.s + gone.half_length < _sim.car.s - _sim.car.length() * 0.5, "4 s on he is behind it: he takes no road ahead of the car")

	# Somebody close ahead in the car's own lane: there is no room to cut in.
	# He hangs back until his 40 s are over, and goes without a pass.
	_begin_quiet_straight("tailgater", 2, 71)
	_drive_quiet_until(20.0, 1)
	_events = []
	_sim.traffic.spawn(&"pickup", 2, _sim.car.s + 25.0, _sim.car.speed)
	changed_at = _sim.leg.time
	_drive_quiet_until(changed_at + hold + 2.0 * DT, 2)
	check_eq(_sim.encounter.tail_phase, EncounterSim.TAIL_HANGING_BACK, "with a vehicle 25 m ahead in the car's lane he does not pass: he hangs back")
	_drive_quiet_until(40.0, 2)
	check_eq(_sim.encounter.tail_phase, EncounterSim.TAIL_HANGING_BACK, "and is still hanging back at 40 s")
	# No ramming from back there.
	_input.rmb = true
	_drive_quiet_until(40.3, 2)
	_input.rmb = false
	_drive_quiet_until(end + 1.0, 2)
	check(_events_named("hit").is_empty() and _sim.faults.lamps == 0, "a touch of the brake while he hangs back: nobody rams")
	check(_sim.encounter.tail_phase == EncounterSim.TAIL_GONE and not _has_event_named("close_call"), "when his 40 s are over he falls back, without a pass")

	# The plan's line is about to move over: he waits until it has.
	var plan: Dictionary = _begin_quiet_straight("tailgater", 2, 71)
	var third_ms: float = tuning.fi("gear_speeds", 2) * KMH_TO_MS
	var change_at: float = (20.0 + hold + 1.5) * third_ms
	GameData.as_array(plan["path"]).append([change_at, 0])
	_sim.begin_leg(plan)
	_drive_quiet_until(20.0, 1)
	changed_at = _sim.leg.time
	passing_from = -1.0
	var s_at_pass: float = 0.0
	while _sim.encounter.active and _sim.leg.time < changed_at + 30.0:
		_hold_lane_and_step(2)
		if _sim.encounter.tail_phase == EncounterSim.TAIL_PASSING and passing_from < 0.0:
			passing_from = _sim.leg.time
			s_at_pass = _sim.car.s
	check(passing_from > changed_at + hold + 1.0, "with the plan's line moving over 1.5 s after the 3 s are up, he does not pass at once")
	check(s_at_pass >= change_at + tuning.f("gen_lane_change") - 1.0, "he pulls out when the line has moved over (%d m after it began to)" % roundi(s_at_pass - change_at))
	check(s_at_pass < change_at + tuning.f("gen_lane_change") + 3.0, "and no later")
	check_eq(_sim.encounter.tail_phase, EncounterSim.TAIL_GONE, "(and goes by, and is gone)")


## A quiet Tailgater leg whose plan's line keeps one lane.
func _begin_quiet_straight(leg_id: String, act: int, leg_seed: int) -> Dictionary:
	var plan: Dictionary = _begin_quiet(leg_id, act, leg_seed)
	plan["path"] = [[0.0, GameData.as_int(plan.get("start_lane"))]]
	_sim = DriveSim.new(fresh_data())
	_sim.gate.reset(3)
	_sim.begin_leg(plan)
	_checker.load_plan(plan)
	_events = []
	return plan


## 1 if the vehicle overlaps another one, else 0.
func _inside_another(vehicle: TrafficSim.Vehicle) -> int:
	for other: TrafficSim.Vehicle in _sim.traffic.vehicles:
		if other != vehicle and absf(other.s - vehicle.s) < other.half_length + vehicle.half_length and absf(other.x - vehicle.x) < other.half_width + vehicle.half_width:
			return 1
	return 0


## T-LEG-07: Patrol: a police car follows for patrol_duration; blue lights
## show in the mirror 3 s before Suspicion starts, about 20 s into the leg; at
## 100 Suspicion he is pulled over and pays by licence (fine) or banknotes
## (bribe) as 6.5 states.
func test_leg_07() -> void:
	var leg: Dictionary = data.record("legs", "patrol")
	var special: Dictionary = GameData.as_dict(leg.get("special"))
	var at: float = GameData.as_float(special.get("at_s"))
	var lead: float = GameData.as_float(special.get("lights_lead_s"))
	var duration: float = tuning.f("patrol_duration")
	var gap: float = GameData.as_float(special.get("gap_m"))
	check_near(GameData.as_float(leg.get("par_s")), 90.0, 0.000001, "GDD 9.1: Patrol has a par of 90 s")
	check_near(at, 20.0, 0.000001, "GDD 9.3: Suspicion starts about 20 s into the leg")
	check_near(lead, 3.0, 0.000001, "the blue lights show 3 s before")
	check_near(duration, 35.0, 0.000001, "GDD 9.1: the police car follows for 35 s")
	check(not GameData.as_array(leg.get("acts")).has(1.0), "there is no Patrol in Act 1")

	# A clean drive: third gear, indicating before every lane change.
	var plan: Dictionary = _begin("patrol", 2, 555)
	var lights_from: float = -1.0
	var lights_to: float = -1.0
	var watch_from: float = -1.0
	var watch_to: float = -1.0
	var police_from: float = -1.0
	var most_suspicion: float = 0.0
	var watched_ticks: int = 0
	var in_place: int = 0
	var in_lane: int = 0
	var ahead_of_him: int = 0
	var appeared_behind: float = 0.0
	var guard: int = int(200.0 / DT)
	while _sim.leg.active and guard > 0:
		guard -= 1
		_keep_to_the_line(true)
		_sim.step(_input)
		_collect()
		var now: float = _sim.leg.time
		var police: TrafficSim.Vehicle = _sim.encounter.police()
		if police != null and police_from < 0.0:
			police_from = now
			appeared_behind = _sim.car.s - police.s
		if _sim.encounter.police_lights and lights_from < 0.0:
			lights_from = now
		if not _sim.encounter.police_lights and lights_from >= 0.0 and lights_to < 0.0:
			lights_to = now
		if _sim.suspicion.watching and watch_from < 0.0:
			watch_from = now
		if not _sim.suspicion.watching and watch_from >= 0.0 and watch_to < 0.0:
			watch_to = now
		most_suspicion = maxf(most_suspicion, _sim.suspicion.value)
		if police != null:
			if police.s >= _sim.car.s:
				ahead_of_him += 1
			if _sim.suspicion.watching and now > at + 5.0:
				watched_ticks += 1
				var behind: float = (_sim.car.s - _sim.car.length() * 0.5) - (police.s + police.half_length)
				if behind >= gap - 3.0 and behind <= gap + 8.0:
					in_place += 1
				if absf(police.x - _sim.car.x) < tuning.f("lane_width") * 0.5:
					in_lane += 1
	check(_sim.leg.finished, "the leg was driven to its end")
	check_near(lights_from, at - lead, 2.0 * DT, "the blue lights come on 3 s before Suspicion starts (%s s)" % str(snappedf(lights_from, 0.01)))
	check_near(police_from, lights_from, 2.0 * DT, "that is when the police car appears")
	check_near(appeared_behind, tuning.f("patrol_spawn_behind"), 2.0, "behind him, where the mirror shows it")
	check_near(watch_from, at, 2.0 * DT, "Suspicion starts 20 s into the leg (%s s)" % str(snappedf(watch_from, 0.01)))
	check_near(watch_to - watch_from, duration, 2.0 * DT, "the police car follows for patrol_duration (%s s)" % str(snappedf(watch_to - watch_from, 0.01)))
	check_near(lights_to, watch_to, 2.0 * DT, "then the lights go out")
	check_eq(ahead_of_him, 0, "the police car is never ahead of him")
	if check(watched_ticks > 0, "the police car was there while it watched"):
		check(float(in_place) / float(watched_ticks) >= 0.9, "it keeps its place behind his bumper (%d%% of the time)" % roundi(100.0 * float(in_place) / float(watched_ticks)))
		check(float(in_lane) / float(watched_ticks) >= 0.75, "and follows him from lane to lane (%d%% of the time in his lane)" % roundi(100.0 * float(in_lane) / float(watched_ticks)))
	check_near(most_suspicion, 0.0, 0.000001, "third gear and an indicator before each lane change: no Suspicion at all")
	check_eq(_sim.faults.lamps, 0, "and the police car never touched him")
	check(_sim.encounter.police() == null, "after the Patrol the police car is no longer behind him")
	var changes: Array[Dictionary] = []
	for event: Dictionary in _events:
		if GameData.as_string(event.get("type")) == "suspicion_changed":
			changes.append(event)
	if check_eq(changes.size(), 2, "a clean Patrol announces its beginning and its end only"):
		check(GameData.as_bool(changes[0].get("watching")) and not GameData.as_bool(changes[1].get("watching")), "watching, then not")
	check(not _has_event_named("pulled_over"), "and he is not pulled over")

	# The same drive without indicating: every lane line costs 20.
	_sim = DriveSim.new(fresh_data())
	_events = []
	plan = _begin("patrol", 2, 555)
	var crossings: int = 0
	var lane_before: int = _sim.car.lane_of(_sim.car.x)
	most_suspicion = 0.0
	guard = int(200.0 / DT)
	while _sim.leg.active and guard > 0 and not _sim.pulled_over:
		guard -= 1
		_keep_to_the_line(false)
		_sim.step(_input)
		var lane_now: int = _sim.car.lane_of(_sim.car.x)
		if lane_now != lane_before and _sim.suspicion.watching:
			crossings += 1
		lane_before = lane_now
		most_suspicion = maxf(most_suspicion, _sim.suspicion.value)
	check(crossings >= 1, "(the line through this leg changes lane while he is watched: %d times)" % crossings)
	check(most_suspicion >= tuning.f("suspicion_lane_cross") - 1.0, "without the indicator the same drive raises Suspicion (to %s)" % str(snappedf(most_suspicion, 0.1)))

	# First gear from the moment he is watched: +15 a second, pulled over at 100.
	_sim = DriveSim.new(fresh_data())
	_events = []
	plan = _begin("patrol", 2, 555)
	_sim.cash = 100.0
	guard = int(60.0 / DT)
	var offended_from: float = -1.0
	while not _sim.pulled_over and guard > 0:
		guard -= 1
		_keep_to_the_line(true)
		if _sim.suspicion.watching and offended_from < 0.0:
			offended_from = _sim.leg.time
			_sim.gate.reset(1)
		_sim.step(_input)
		_collect()
	if not check(_sim.pulled_over, "in first gear under a police car's eyes he is pulled over"):
		return
	check_near(_sim.leg.time - offended_from, tuning.f("suspicion_max") / tuning.f("suspicion_gear_rate"), 0.1, "after 100 / 15 seconds")
	var stopped: Dictionary = _event("pulled_over")
	check(not GameData.as_bool(stopped.get("released")), "the stop is announced")
	check_near(GameData.as_float(stopped.get("fine")), 25.0, 0.000001, "with the fine it would cost: 25% of his 100")
	check_near(GameData.as_float(stopped.get("bribe")), tuning.f("bribe_base") + 2.0 * tuning.f("bribe_per_act"), 0.000001, "and the bribe: 40 plus 10 per act, 60 in Act 2")
	check(GameData.as_bool(stopped.get("can_bribe")), "which he can pay")
	check_near(_sim.car.speed, 0.0, 0.000001, "the car stands")
	check(_sim.car.x > _sim.car.road_right(), "on the shoulder")
	check(GameData.as_bool(_sim.snapshot()["pulled_over"]), "the snapshot says so")
	var police: TrafficSim.Vehicle = _sim.encounter.police()
	if check(police != null, "the police car is still there"):
		check(police.s < _sim.car.s and is_equal_approx(police.x, _sim.car.x) and police.speed == 0.0, "parked behind him")
	var anchors: Array = GameData.as_array(_sim.snapshot()["anchors_in_use"])
	check(anchors.has(&"dash_1") and anchors.has(&"cash"), "his licence on the dash and the banknotes can be reached")
	check_eq(anchors.size(), 2, "and nothing else: with the officer at his window the hand does only what he is there for")
	# Nothing moves on while the officer waits.
	var leg_time: float = _sim.leg.time
	var s_before: float = _sim.car.s
	var clock_before: float = _sim.clock.minutes
	_input.clear()
	_input.rmb = false
	for _tick: int in int(3.0 / DT):
		_sim.step(_input)
	check_near(_sim.leg.time, leg_time, 0.000001, "the leg's clock stands while he is pulled over")
	check_near(_sim.clock.minutes, clock_before, 0.000001, "and so does the Clock: he is not driving")
	check_near(_sim.car.s, s_before, 0.000001, "and so does the car, whatever gear it is in")
	check(_sim.pulled_over, "waiting changes nothing")

	# His licence: a fine.
	_hand_over(&"dash_1")
	check(not _sim.pulled_over, "handing over his licence ends the stop")
	var released: Dictionary = _event("pulled_over")
	check(GameData.as_bool(released.get("released")), "which is announced")
	check_eq(GameData.as_string(released.get("paid")), "fine", "as a fine")
	check_near(_sim.cash, 75.0, 0.000001, "the fine is 25% of his cash")
	check_near(_sim.clock_minutes_owed, tuning.f("fine_minutes"), 0.000001, "and 20 game minutes")
	check(_sim.clock.minutes - clock_before >= tuning.f("fine_minutes") and _sim.clock.minutes - clock_before < tuning.f("fine_minutes") + 0.5,
			"which the Clock takes at once (%s min)" % str(snappedf(_sim.clock.minutes - clock_before, 0.01)))
	check(not _sim.suspicion.watching and not _sim.encounter.police_lights, "the Patrol is over")
	check_near(_sim.suspicion.value, 0.0, 0.000001, "Suspicion is gone")
	check(_has_event_named("ritual_completed"), "the hand did it: a ritual was completed")
	_sim.gate.reset(1)
	for _tick: int in int(3.0 / DT):
		_sim.step(_input)
	check(_sim.car.speed > 20.0 and _sim.car.s > s_before + 5.0, "and he drives on")
	check(_sim.leg.time > leg_time + 2.0, "the leg's clock runs again")

	# The fine has a floor, and he cannot pay what he does not have.
	check_near(_fine_with(40.0), 20.0, 0.000001, "25% of 40 is under the minimum: the fine is 20")
	check_near(_fine_with(200.0), 50.0, 0.000001, "25% of 200 is 50")
	check_near(_fine_with(12.0), 12.0, 0.000001, "with 12 to his name the fine takes it all")

	# Banknotes: a bribe.
	_pull_over_with(fresh_data(), 100.0)
	_hand_over(&"cash")
	check(not _sim.pulled_over, "handing over banknotes ends the stop")
	check_eq(GameData.as_string(_event("pulled_over").get("paid")), "bribe", "as a bribe")
	check_near(_sim.cash, 100.0 - (tuning.f("bribe_base") + 2.0 * tuning.f("bribe_per_act")), 0.000001, "the bribe is 40 plus 10 per act")
	check_near(_sim.clock_minutes_owed, tuning.f("bribe_minutes"), 0.000001, "and 5 game minutes")
	_pull_over_with(fresh_data(), 50.0)
	check(not GameData.as_bool(_event("pulled_over").get("can_bribe")), "with 50 he cannot pay a bribe of 60")
	_hand_over(&"cash")
	check(_sim.pulled_over, "banknotes he does not have do not end the stop")
	check_near(_sim.cash, 50.0, 0.000001, "and cost nothing")
	_hand_over(&"dash_1")
	check(not _sim.pulled_over, "his licence still does")

	# What the officer sees he takes with the fine; with a bribe he keeps everything.
	var roots: Dictionary = data.roots.duplicate(true)
	for entry: Variant in GameData.as_array(GameData.as_dict(roots["items"])["items"]):
		var item: Dictionary = entry
		if GameData.as_string(item["id"]) == "tea_glass":
			item["contraband"] = true
			GameData.as_array(item["slots"]).append("glovebox_a")
	var private: GameData = GameData.from_parts(roots, data.lines.duplicate(true))
	_pull_over_with(private, 100.0)
	_sim.items.add_item(&"tea_glass", &"glovebox_a")
	check_eq(_contraband_count(), 2, "(contraband in the cup holder and in the glovebox)")
	_hand_over(&"dash_1")
	check_eq(_contraband_count(), 1, "with the fine the officer takes the contraband he can see")
	check(_sim.items.item_in_slot(&"glovebox_a") != null, "what is in the glovebox stays")
	check_eq(GameData.as_array(_event("pulled_over").get("taken")).size(), 1, "the event names what was taken")
	_pull_over_with(private, 100.0)
	_sim.items.add_item(&"tea_glass", &"glovebox_a")
	_hand_over(&"cash")
	check_eq(_contraband_count(), 2, "with a bribe he keeps everything")

	_check_the_night_waits_for_the_officer()


## While the officer waits at his window the night waits, as it does at a
## stop (GDD 6.4, 6.5): nothing burns down, cools, rings or calms, and the
## hand does only what the officer is there for. Standing there earns and
## mends nothing. A Snap's seconds are the hand's own and run on; and the
## night does not stop on a man with his eyes shut.
func _check_the_night_waits_for_the_officer() -> void:
	var phone: Dictionary = GameData.as_dict(data.record("items", "phone").get("params"))
	var longest_gap: float = GameData.as_float(GameData.as_array(phone.get("call_gap_s"))[1])
	var burn: float = 0.0
	for give: Variant in GameData.as_array(data.record("items", "cigarettes").get("gives")):
		if GameData.as_string(GameData.as_dict(give).get("effect")) == "lit":
			burn = GameData.as_float(GameData.as_dict(give).get("duration"))

	# A cabin full of what runs by the second: a tape that calms, a phone
	# that is due to ring, a cigarette burning, tea going cold, Awake from a slap.
	_until_watched(100.0)
	_sim.give_item(&"mixtape")
	_sim.give_item(&"phone")
	_sim.give_item(&"beads")
	_sim.give_item(&"thumb_keypad")
	_sim.items.complete(data.record("rituals", "cig_light"), 0)
	_sim.items.complete(data.record("rituals", "slap"), 0)
	var lit_before: float = _sim.effects.time_left(&"lit")
	var hot_before: float = _sim.items.item(&"tea_glass").hot_left
	var nerves_before: float = _sim.nerves.value
	_drive_clean(1.0)
	check_near(lit_before - _sim.effects.time_left(&"lit"), 1.0, 0.000001, "(on the road the cigarette burns down)")
	check_near(hot_before - _sim.items.item(&"tea_glass").hot_left, 1.0, 0.000001, "(the tea cools)")
	check(_sim.nerves.value < nerves_before - 0.5 and _sim.effects.has(&"music"), "(and the tape calms him)")

	_pull_over_now()
	var nerves: float = _sim.nerves.value
	var lit_left: float = _sim.effects.time_left(&"lit")
	var awake_left: float = _sim.effects.time_left(&"awake")
	var hot_left: float = _sim.items.item(&"tea_glass").hot_left
	var haze: float = _sim.items.haze
	var side: float = _sim.items.item(&"mixtape").side_time
	var cash: float = _sim.cash
	var clock: float = _sim.clock.minutes
	_events = []
	_input.clear()
	for _tick: int in int((longest_gap + burn) / DT):
		_sim.step(_input)
	_collect()
	check(_sim.pulled_over, "(he waits with the officer for over a minute)")
	check_eq(_sim.nerves.value, nerves, "while the officer waits his Nerves stand: the tape does not calm him, nor the cigarette, nor the quiet")
	check_eq(_sim.effects.time_left(&"lit"), lit_left, "the cigarette does not burn down")
	check_eq(_sim.effects.time_left(&"awake"), awake_left, "no status runs out")
	check_eq(_sim.items.item(&"tea_glass").hot_left, hot_left, "the tea does not cool")
	check_eq(_sim.items.haze, haze, "the smoke stands in the air")
	check_eq(_sim.items.item(&"mixtape").side_time, side, "the tape's side does not run")
	check(not _has_event_named("call_started"), "no call comes in, however long he waits: the phone earns nothing there")
	check_eq(_sim.cash, cash, "his cash is what it was")
	check_eq(_sim.clock.minutes, clock, "and the Clock stands with all the rest")

	# The hand does only what the officer is there for.
	var anchors: Array = GameData.as_array(_sim.snapshot()["anchors_in_use"])
	check(anchors.size() == 2 and anchors.has(&"dash_1") and anchors.has(&"cash"),
			"with beads, a tape and a phone aboard the hand still has his licence and the banknotes to go to, and nothing else")
	check_eq(_try_what_calms(), [], "what calms him is not offered there: not a bead, not the horn, not the horn under his thumb")
	check_eq(_sim.nerves.value, nerves, "and his Nerves are as they were")

	# A Snap's seconds are the hand's: they run down while the officer waits.
	_sim.nerves.add(tuning.f("snap_at"))
	check(_sim.nerves.snap_left > 0.0, "(a Snap, with the officer at his window)")
	_hand_over(&"dash_1")
	check(_sim.pulled_over, "in a Snap he cannot reach for his licence")
	check(not GameData.as_bool(_sim.snapshot()["snap"]), "but the Snap runs down while the officer waits")
	_hand_over(&"dash_1")
	check(not _sim.pulled_over, "and then he hands it over")

	# Let go, the night goes on from where it stood.
	_events = []
	check_eq(_try_what_calms(), ["beads_count", "horn", "horn (keypad)"], "on the road again the cabin is his: a bead, the horn, the horn under his thumb")
	_drive_clean(longest_gap)
	check(_has_event_named("call_started"), "the phone rings again")
	check(not _sim.effects.has(&"lit"), "and the cigarette burns down")

	# Pulled over in the middle of a blink, he is not left with his eyes shut.
	_until_watched(100.0)
	var guard: int = int(tuning.f("blink_period") * 2.0 / DT)
	while not _sim.nerves.eyes_shut and guard > 0:
		guard -= 1
		_sim.nerves.set_value(_sim.heavy_floor() * 0.5)
		_keep_to_the_line(true)
		_sim.step(_input)
	check(_sim.nerves.eyes_shut and _sim.nerves.lids > 0.0, "(Heavy under the eyes of the police: his lids droop and he blinks)")
	_pull_over_now()
	check(not _sim.nerves.eyes_shut, "pulled over in the middle of a blink, his eyes are open")
	check_eq(_sim.nerves.lids, 0.0, "and so are his lids, as at a stop")
	_events = []
	var dozed: bool = false
	_input.clear()
	for _tick: int in int(tuning.f("blink_period") * 2.0 / DT):
		_sim.step(_input)
		dozed = dozed or _sim.nerves.eyes_shut or _sim.nerves.lids > 0.0
	_collect()
	check(not dozed and not _has_event_named("blink"), "and he does not doze while the officer waits")
	# Let go, the rhythm of his blinking starts anew, as after a stop.
	var paid_at: int = -1
	_input.clear()
	_input.pointer_is_absolute = true
	_input.pointer = _sim.hand.anchor_pointer(_sim.hand.anchor_index(&"dash_1"))
	for _tick: int in int(1.5 / DT):
		_sim.step(_input)
	_input.lmb = true
	for _tick: int in int(0.1 / DT):
		_sim.step(_input)
	_input.pointer = _sim.hand.anchor_pointer(_sim.hand.anchor_index(&"driver_window"))
	for _tick: int in int(2.5 / DT):
		_sim.step(_input)
	_input.clear()
	var shut_at: int = -1
	guard = int(tuning.f("blink_period") * 2.0 / DT)
	while shut_at < 0 and guard > 0:
		guard -= 1
		_sim.nerves.set_value(_sim.heavy_floor() * 0.5)
		_keep_to_the_line(true)
		_sim.step(_input)
		if paid_at < 0 and not _sim.pulled_over:
			paid_at = _sim.tick
		if paid_at >= 0 and _sim.nerves.eyes_shut:
			shut_at = _sim.tick
	check(paid_at >= 0, "(he hands his licence over and is let go)")
	check_near(float(shut_at - paid_at) * DT, tuning.f("blink_period"), 2.0 * DT, "on the road again, as Heavy as before, his next blink comes a whole blink_period after he is let go")


## T-LEG-08: Two-lane: an undivided road; trucks ahead hold 60 km/h; oncoming
## vehicles arrive every 6 to 10 s; each gap is long enough to pass one truck
## in gear 4; par 100 s.
func test_leg_08() -> void:
	var leg: Dictionary = data.record("legs", "two_lane")
	var special: Dictionary = GameData.as_dict(leg.get("special"))
	var truck_speed: float = GameData.as_float(special.get("truck_speed_kmh"))
	var every: Array = GameData.as_array(special.get("oncoming_every_s"))
	var oncoming_speeds: Array = GameData.as_array(special.get("oncoming_speed_kmh"))
	var third: float = tuning.fi("gear_speeds", 2)
	var fourth: float = tuning.fi("gear_speeds", 3)
	check_near(GameData.as_float(leg.get("par_s")), 100.0, 0.000001, "GDD 9.1: Two-lane has a par of 100 s")
	check_eq(GameData.as_int(leg.get("lanes")), 1, "one lane his way")
	check(not GameData.as_bool(leg.get("divided")), "and no median: the other lane is oncoming traffic's")
	check_near(truck_speed, 60.0, 0.000001, "GDD 9.3: trucks ahead hold 60 km/h")
	check_near(GameData.as_float(every[0]), 6.0, 0.000001, "oncoming vehicles arrive every 6 s at the least")
	check_near(GameData.as_float(every[1]), 10.0, 0.000001, "and every 10 s at the most")
	check_eq(GameData.as_array(leg.get("acts")), [3.0], "it is an Act 3 road")

	# The plans: trucks at 60 ahead, oncoming every 6 to 10 s at par, and every
	# gap wide enough for a pass in fourth gear.
	var truck: Dictionary = data.record("vehicles", GameData.as_string(special.get("truck")))
	var margin: float = GameData.as_float(special.get("pass_margin_m"))
	# Fourth gear: out, past the truck with pass_margin_m at both ends, and back.
	var lane_change_s: float = tuning.f("lane_width") / (tuning.f("lat_per_kmh") * fourth)
	var pass_s: float = (2.0 * margin + GameData.as_float(truck.get("length")) + tuning.f("car_length")) / ((fourth - truck_speed) * KMH_TO_MS) + 2.0 * lane_change_s
	var trucks: int = 0
	var gaps: int = 0
	var tightest: float = INF
	for index: int in SAMPLE_SEEDS:
		var plan: Dictionary = LegGenerator.generate(data, "two_lane", 3, 800 + index, "")
		var meets: Array[float] = []
		var speeds: Array[float] = []
		for entry: Variant in GameData.as_array(plan["spawns"]):
			var spawn: Dictionary = entry
			if GameData.as_int(spawn["direction"]) < 0:
				check_eq(GameData.as_int(spawn["lane"]), LegGenerator.ONCOMING_LANE, "an oncoming vehicle is in the oncoming lane")
				var speed: float = GameData.as_float(spawn["speed"])
				check(speed >= GameData.as_float(oncoming_speeds[0]) and speed <= GameData.as_float(oncoming_speeds[1]), "at a speed the leg allows (%s)" % str(speed))
				meets.append(GameData.as_float(spawn["meet_s"]))
				speeds.append(speed)
			elif GameData.as_int(spawn["lane"]) == 0:
				trucks += 1
				check_eq(GameData.as_string(spawn["vehicle"]), GameData.as_string(special.get("truck")), "what is ahead in his lane is a truck")
				check_near(GameData.as_float(spawn["speed"]), truck_speed, 0.000001, "holding 60 km/h")
		check(meets.size() >= 8, "seed %d: oncoming traffic all along the leg (%d vehicles)" % [800 + index, meets.size()])
		if meets.is_empty():
			continue
		check(meets[0] / (third * KMH_TO_MS) <= GameData.as_float(every[1]) + 0.001, "the first comes within 10 s")
		for pair: int in range(1, meets.size()):
			var seconds: float = (meets[pair] - meets[pair - 1]) / (third * KMH_TO_MS)
			check(seconds >= GameData.as_float(every[0]) - 0.001 and seconds <= GameData.as_float(every[1]) + 0.001,
					"at third gear's speed oncoming vehicles arrive 6 to 10 s apart (%s s)" % str(snappedf(seconds, 0.01)))
			# The same two vehicles, met in fourth gear: the road between them
			# is covered at his speed plus theirs.
			var road_between: float = (meets[pair] - meets[pair - 1]) * (1.0 + speeds[pair] / third)
			var seconds_in_fourth: float = road_between / ((fourth + speeds[pair]) * KMH_TO_MS)
			tightest = minf(tightest, seconds_in_fourth)
			gaps += 1
	check(trucks >= 3 * SAMPLE_SEEDS, "every leg has trucks to pass (%d in %d legs)" % [trucks, SAMPLE_SEEDS])
	check(gaps > 0 and tightest >= pass_s, "each gap is long enough to pass one truck in gear 4: the tightest of %d is %s s, a pass takes %s s" % [gaps, str(snappedf(tightest, 0.01)), str(snappedf(pass_s, 0.01))])

	# The tightest gap the leg allows, driven: fourth gear, out behind the
	# truck as one oncoming vehicle goes by, back in before the next arrives.
	_sim = DriveSim.new(fresh_data())
	_events = []
	_sim.set_road(1, false)
	_sim.gate.reset(4)
	_sim.car.reset(0, 4)
	var slow: TrafficSim.Vehicle = _sim.traffic.spawn(StringName(GameData.as_string(special.get("truck"))), 0,
			_sim.car.s + _sim.car.length() * 0.5 + margin + GameData.as_float(truck.get("length")) * 0.5, truck_speed)
	var fastest_oncoming: float = GameData.as_float(oncoming_speeds[1])
	var between: float = GameData.as_float(every[0]) * (third + GameData.as_float(oncoming_speeds[0])) * KMH_TO_MS
	_sim.traffic.spawn(&"car", LegGenerator.ONCOMING_LANE, _sim.car.s, fastest_oncoming, -1)
	var next: TrafficSim.Vehicle = _sim.traffic.spawn(&"car", LegGenerator.ONCOMING_LANE, _sim.car.s + between, fastest_oncoming, -1)
	var lane_x: float = _sim.car.lane_center(0)
	var out_x: float = _sim.traffic.lane_center(LegGenerator.ONCOMING_LANE)
	var x: float = lane_x
	var back_at: float = -1.0
	var seconds: float = 0.0
	var passed: bool = false
	while seconds < 12.0 and next.s > _sim.car.s - 30.0:
		var clear_of_truck: bool = _sim.car.s - _sim.car.length() * 0.5 > slow.s + slow.half_length + margin
		var target: float = lane_x if clear_of_truck else out_x
		x = move_toward(x, target, tuning.f("lat_per_kmh") * fourth * DT)
		if clear_of_truck and is_equal_approx(x, lane_x) and back_at < 0.0:
			back_at = seconds
			passed = next.s > _sim.car.s
		_sim.car.x = x
		_sim.step(_input)
		seconds += DT
	check(back_at > 0.0 and passed, "in fourth gear he is past the truck and back in his lane (after %s s) before the next oncoming vehicle arrives" % str(snappedf(back_at, 0.01)))
	check_eq(_sim.faults.lamps, 0, "with no lamp lit")
	check_near(slow.speed, truck_speed, 0.000001, "and the truck held 60 km/h throughout")

	# A whole leg on the plan's line in third gear: the oncoming lane is used
	# to pass, and oncoming vehicles go by every 6 to 10 s.
	_sim = DriveSim.new(fresh_data())
	_events = []
	var plan: Dictionary = _begin("two_lane", 3, 801)
	var snapshot: Dictionary = _sim.snapshot()
	check_eq(GameData.as_int(snapshot["lanes"]), 1, "driven: the road has one lane")
	check(not GameData.as_bool(snapshot["divided"]), "and is undivided")
	var arrivals: Array[float] = []
	var met: Dictionary = {}
	var in_oncoming_lane: float = 0.0
	var trucks_passed: int = 0
	var trucks_slow: int = 0
	while _sim.leg.active:
		_sim.car.x = _checker.line_x(_sim.car.s)
		if _sim.car.x < 0.0:
			in_oncoming_lane += DT
		_sim.step(_input)
		_collect()
		for vehicle: TrafficSim.Vehicle in _sim.traffic.vehicles:
			if met.has(vehicle.id) or vehicle.s > _sim.car.s:
				continue
			met[vehicle.id] = true
			if vehicle.direction < 0:
				arrivals.append(_sim.leg.time)
			elif vehicle.x < _sim.car.road_right():
				# (A hulk on the shoulder is not traffic.)
				trucks_passed += 1
				if not is_equal_approx(vehicle.speed, truck_speed):
					trucks_slow += 1
	check_near(_sim.leg.time, tuning.f("leg_length") / (third * KMH_TO_MS), 0.05, "in third gear the leg takes 90 s, 10 s under its par")
	check_eq(_sim.faults.lamps, 0, "on the plan's line no lamp is lit")
	check(trucks_passed >= 3, "trucks were passed (%d)" % trucks_passed)
	check_eq(trucks_slow, 0, "each still doing 60 km/h when he passed it")
	check(in_oncoming_lane > 5.0, "by way of the oncoming lane (%s s in it)" % str(snappedf(in_oncoming_lane, 0.1)))
	check(arrivals.size() >= 8, "oncoming vehicles went by (%d)" % arrivals.size())
	for pair: int in range(1, arrivals.size()):
		var apart: float = arrivals[pair] - arrivals[pair - 1]
		check(apart >= GameData.as_float(every[0]) - 0.1 and apart <= GameData.as_float(every[1]) + 0.1, "driven: %s s between two oncoming vehicles" % str(snappedf(apart, 0.01)))
	check_near(GameData.as_float(_event("leg_ended").get("par_bonus")), floorf((100.0 - _sim.leg.time) * tuning.f("par_bonus_rate")), 0.000001, "10 s under par pays 5 cash")
	check(not plan.is_empty(), "(the plan was generated)")


## T-LEG-09: Motorcade: five black cars hold all lanes at 70 km/h; within
## 100 m a spotlight gives Glare 80% and +2 Nerves per second; the motorcade
## never touches him; staying behind for the whole leg takes 129 s; one side
## road mid-leg is a Two-lane detour that rejoins ahead of the motorcade;
## par 110 s.
func test_leg_09() -> void:
	var leg: Dictionary = data.record("legs", "motorcade")
	var special: Dictionary = GameData.as_dict(leg.get("special"))
	var two_lane: Dictionary = GameData.as_dict(data.record("legs", "two_lane").get("special"))
	var speed: float = GameData.as_float(special.get("speed_kmh"))
	var keep_back: float = GameData.as_float(special.get("keep_back_m"))
	var hold_gap: float = GameData.as_float(special.get("hold_gap_m"))
	var par: float = GameData.as_float(leg.get("par_s"))
	var second: float = tuning.fi("gear_speeds", 1)
	var third: float = tuning.fi("gear_speeds", 2)
	var leg_length: float = tuning.f("leg_length")
	check_near(par, 110.0, 0.000001, "GDD 9.1: the Motorcade has a par of 110 s")
	check_eq(GameData.as_int(leg.get("lanes")), 3, "three lanes")
	check(GameData.as_bool(leg.get("divided")), "with a median")
	check_eq(GameData.as_array(leg.get("acts")), [3.0], "it is an Act 3 road")
	check_eq(GameData.as_int(special.get("cars")), 5, "GDD 9.3: five cars")
	check_near(speed, 70.0, 0.000001, "at 70 km/h")
	check_near(keep_back, 100.0, 0.000001, "the spotlight reaches 100 m")
	check_near(GameData.as_float(special.get("glare")), 0.8, 0.000001, "Glare 80%")
	check_near(GameData.as_float(special.get("nerves_per_s")), 2.0, 0.000001, "+2 Nerves per second")
	var black: Dictionary = data.record("vehicles", "motorcade_car")
	var look: Dictionary = GameData.as_dict(GameData.as_dict(data.root("placeholders").get(GameData.as_string(black.get("placeholder")))).get("placeholder"))
	var colour: Color = Color.html(GameData.as_string(look.get("color")))
	check(maxf(colour.r, maxf(colour.g, colour.b)) < 0.1, "the cars are black (%s)" % GameData.as_string(look.get("color")))
	check(not GameData.as_bool(black.get("yields_to_horn")) and is_zero_approx(GameData.as_float(black.get("honk_nerves"))),
			"they do not answer the horn and have none: the motorcade never speaks")
	check(not GameData.as_bool(black.get("traffic"), true), "and they are never ordinary traffic")

	# The plans: five cars over all three lanes, nothing else on the main
	# road, and one side road mid-leg that is a Two-lane road.
	for index: int in SAMPLE_SEEDS:
		var plan: Dictionary = LegGenerator.generate(data, "motorcade", 3, 900 + index, "")
		var convoy: Dictionary = GameData.as_dict(plan.get("motorcade"))
		var cars: Array = GameData.as_array(convoy.get("cars"))
		check_eq(cars.size(), 5, "seed %d: five cars" % (900 + index))
		var lanes_held: Dictionary = {}
		for entry: Variant in cars:
			lanes_held[GameData.as_int(GameData.as_dict(entry).get("lane"))] = true
		check_eq(lanes_held.size(), GameData.as_int(plan["lanes"]), "holding every lane")
		check_eq(GameData.as_string(convoy.get("vehicle")), "motorcade_car", "all of them the black car")
		check_near(GameData.as_float(convoy.get("speed")), speed, 0.000001, "at 70 km/h")
		check_eq(_ordinary(plan), 0, "no other traffic is in the lanes they fill")
		var detour: Dictionary = GameData.as_dict(convoy.get("detour"))
		var at: float = GameData.as_float(detour.get("at"))
		var rejoin: float = at + GameData.as_float(detour.get("slip")) + GameData.as_float(detour.get("length"))
		check(at >= 0.4 * leg_length and at <= 0.6 * leg_length, "the side road is mid-leg (at %s m)" % str(at))
		check(rejoin <= GameData.as_float(plan["beats_end"]), "and is back on the main road before the Exit (%s m)" % str(rejoin))
		check_eq(GameData.as_int(detour.get("lanes")), 1, "it is a Two-lane road: one lane his way")
		check(not GameData.as_bool(detour.get("divided"), true), "and no median")
		var trucks: int = 0
		var meets: Array[float] = []
		for entry: Variant in GameData.as_array(detour.get("spawns")):
			var spawn: Dictionary = entry
			if GameData.as_int(spawn["direction"]) < 0:
				check_eq(GameData.as_int(spawn["lane"]), LegGenerator.ONCOMING_LANE, "its oncoming traffic is in the oncoming lane")
				meets.append(GameData.as_float(spawn["meet_s"]))
			else:
				trucks += 1
				check_eq(GameData.as_string(spawn["vehicle"]), GameData.as_string(two_lane.get("truck")), "what is ahead on it is a truck")
				check_near(GameData.as_float(spawn["speed"]), GameData.as_float(two_lane.get("truck_speed_kmh")), 0.000001, "holding 60 km/h")
		check(trucks >= 1, "with a truck to pass (%d)" % trucks)
		var every: Array = GameData.as_array(two_lane.get("oncoming_every_s"))
		check(meets.size() >= 2, "and oncoming traffic (%d vehicles)" % meets.size())
		for pair: int in range(1, meets.size()):
			var apart: float = (meets[pair] - meets[pair - 1]) / (third * KMH_TO_MS)
			check(apart >= GameData.as_float(every[0]) - 0.001 and apart <= GameData.as_float(every[1]) + 0.001,
					"arriving 6 to 10 s apart, as on any Two-lane road (%s s)" % str(snappedf(apart, 0.01)))

	# Staying behind, at the motorcade's own speed, for the whole leg.
	_sim = DriveSim.new(fresh_data())
	_events = []
	var plan: Dictionary = LegGenerator.generate(data, "motorcade", 3, 901, "")
	var detour: Dictionary = GameData.as_dict(GameData.as_dict(plan["motorcade"]).get("detour"))
	var at: float = GameData.as_float(detour.get("at"))
	var gore: float = at + GameData.as_float(detour.get("slip"))
	var rejoin: float = gore + GameData.as_float(detour.get("length"))
	_sim.gate.reset(2)
	_sim.begin_leg(plan)
	_checker.load_plan(plan)
	_collect()
	check_near(_sim.car.speed, second, 0.000001, "(second gear is the motorcade's speed)")
	check_near(second, speed, 0.000001, "(70 km/h)")
	var convoy: Array[TrafficSim.Vehicle] = _sim.encounter.motorcade()
	check_eq(convoy.size(), 5, "driven: five cars are on the road from the start")
	var held: Dictionary = {}
	var last: TrafficSim.Vehicle = null
	for vehicle: TrafficSim.Vehicle in convoy:
		check_eq(vehicle.type_id, &"motorcade_car", "each a black car")
		check_eq(vehicle.role, EncounterSim.MOTORCADE, "of the motorcade")
		held[vehicle.lane] = true
		if last == null or vehicle.s < last.s:
			last = vehicle
	check_eq(held.size(), 3, "across all three lanes")
	if not check(last != null, "(there is a last car)"):
		return
	var half_car: float = _sim.car.length() * 0.5
	var start_gap: float = (last.s - last.half_length) - (_sim.car.s + half_car)
	check(start_gap > keep_back, "it starts out of the spotlight's reach, where the sign can be read (%s m ahead)" % str(snappedf(start_gap, 0.1)))
	check(_sim.encounter.active, "it is the leg's encounter")
	var last_from: float = last.s
	var off_speed: float = 0.0
	var brightest: float = 0.0
	var lanes_in_slip: int = 0
	var lanes_after: int = 0
	var sign_ahead: float = -1.0
	var nerves_most: float = _sim.nerves.value
	while _sim.leg.active:
		_sim.car.x = _checker.line_x(_sim.car.s)
		_sim.step(_input)
		_collect()
		for vehicle: TrafficSim.Vehicle in convoy:
			off_speed = maxf(off_speed, absf(vehicle.speed - speed))
		brightest = maxf(brightest, _sim.encounter.glare)
		nerves_most = maxf(nerves_most, _sim.nerves.value)
		if sign_ahead < 0.0 and _sim.car.s < at:
			for road_sign: Dictionary in _sim.leg.signs_near(tuning.f("road_draw_ahead")):
				if GameData.as_string(road_sign.get("kind")) == "side_road":
					sign_ahead = at - _sim.car.s
		if _sim.car.s > at + 1.0 and _sim.car.s < gore - 1.0:
			lanes_in_slip = _sim.car.lanes
		if _sim.car.s > gore + 1.0:
			lanes_after = _sim.car.lanes
	var behind_time: float = _sim.leg.time
	check_near(behind_time, leg_length / (speed * KMH_TO_MS), 0.05, "staying behind for the whole leg takes the leg's length at 70 km/h")
	check_eq(roundi(behind_time), 129, "GDD 9.3: 129 s")
	check(behind_time > par, "which is %s s over par" % str(snappedf(behind_time - par, 0.1)))
	check_near(GameData.as_float(_event("leg_ended").get("par_bonus")), 0.0, 0.000001, "so par pays nothing")
	check(off_speed < 0.000001, "the five cars held 70 km/h throughout")
	check_near(last.s - last_from, speed * KMH_TO_MS * behind_time, 0.05, "the last car covered what 70 km/h covers in that time")
	check(is_zero_approx(brightest), "kept back, the spotlight never reached him")
	check(nerves_most <= tuning.f("nerves_start") + 0.000001, "and the motorcade did nothing to his Nerves")
	check_eq(_sim.faults.lamps, 0, "no lamp is lit")
	check(sign_ahead > 0.0, "the side road is signed before its slip lane opens")
	check_near(sign_ahead, tuning.f("road_draw_ahead") + tuning.f("slip_sign_lead") * third * KMH_TO_MS, 1.0, "its sign stands slip_sign_lead seconds short of the slip lane")
	check_eq(lanes_in_slip, 4, "beside the slip lane the road is one lane wider")
	check_eq(lanes_after, 3, "and three lanes again after it, for a car that stayed")
	check_eq(_sim.encounter.side_road, EncounterSim.SIDE_ROAD_BEHIND, "the side road is behind him")

	# Third gear, straight at it: the spotlight, then the wall.
	_begin_quiet("motorcade", 3, 902)
	convoy = _sim.encounter.motorcade()
	last = convoy[convoy.size() - 1] if not convoy.is_empty() else null
	for vehicle: TrafficSim.Vehicle in convoy:
		if vehicle.s < last.s:
			last = vehicle
	if not check(last != null, "(quiet road: the motorcade is there)"):
		return
	var lit_at: float = -1.0
	var lit_gap: float = 0.0
	var dark_gap: float = INF
	var nerves_lit: float = 0.0
	var nerves_dark: float = 0.0
	var nerves_later: float = 0.0
	var window: float = 6.0
	var glare_seen: float = 0.0
	var glare_snapshot: float = -1.0
	var nearest: float = INF
	var fastest_at_wall: float = 0.0
	while _sim.leg.active:
		var nerves_before: float = _sim.nerves.value
		_hold_lane_and_step(1)
		var gap: float = (last.s - last.half_length) - (_sim.car.s + half_car)
		nearest = minf(nearest, gap)
		if gap < hold_gap + 0.01:
			fastest_at_wall = maxf(fastest_at_wall, _sim.car.speed)
		if _sim.encounter.glare > 0.0:
			if lit_at < 0.0:
				lit_at = _sim.leg.time
				lit_gap = gap
				nerves_dark = nerves_before
				nerves_lit = _sim.nerves.value
				glare_snapshot = GameData.as_float(_sim.snapshot()["glare"])
			glare_seen = maxf(glare_seen, _sim.encounter.glare)
			if absf(_sim.leg.time - (lit_at + window)) < DT * 0.5:
				nerves_later = _sim.nerves.value
		elif lit_at < 0.0:
			dark_gap = minf(dark_gap, gap)
	var closing_per_tick: float = (third - speed) * KMH_TO_MS * DT
	check(lit_at > 0.0, "driven in third gear, the spotlight comes on")
	check(lit_gap < keep_back and lit_gap > keep_back - 2.0 * closing_per_tick, "when he is within 100 m of the last car (%s m)" % str(snappedf(lit_gap, 0.01)))
	check(dark_gap >= keep_back - 0.000001, "and not before (%s m)" % str(snappedf(dark_gap, 0.01)))
	check_near(nerves_dark, tuning.f("nerves_start"), 0.000001, "until then the motorcade did nothing to his Nerves")
	check_near(glare_seen, GameData.as_float(special.get("glare")), 0.000001, "Glare is 80%")
	check_near(glare_snapshot, GameData.as_float(special.get("glare")), 0.000001, "and the snapshot says so")
	check_near((nerves_later - nerves_lit) / window, GameData.as_float(special.get("nerves_per_s")), 0.01,
			"in the spotlight his Nerves rise 2 a second (%s)" % str(snappedf((nerves_later - nerves_lit) / window, 0.001)))
	check_near(nearest, hold_gap, 0.001, "he can come no nearer than %s m to the last car (%s m)" % [str(hold_gap), str(snappedf(nearest, 0.001))])
	check(fastest_at_wall <= speed + 0.000001, "and there he is held to its speed (%s km/h)" % str(snappedf(fastest_at_wall, 0.01)))
	check_eq(_sim.faults.lamps, 0, "the motorcade never touches him: no lamp")
	check(not _has_event_named("hit"), "no hit")
	check(_sim.leg.time > par and _sim.leg.time < behind_time, "however close he follows, the main road does not make par (%s s)" % str(snappedf(_sim.leg.time, 0.1)))

	# Fourth gear at every part of the road: there is no way through.
	var rail: float = _sim.car.road_right() + tuning.f("rumble_strip_width") + tuning.f("shoulder_width") * 0.5
	for x: float in [_sim.car.lane_center(0), _sim.car.lane_center(1), _sim.car.lane_center(2), _sim.car.lane_width(), 2.0 * _sim.car.lane_width(), rail]:
		_begin_quiet("motorcade", 3, 903)
		_sim.gate.reset(4)
		convoy = _sim.encounter.motorcade()
		last = convoy[0]
		for vehicle: TrafficSim.Vehicle in convoy:
			if vehicle.s < last.s:
				last = vehicle
		var least: float = INF
		while _sim.leg.active and _sim.leg.time < 30.0:
			_sim.car.x = x
			_sim.step(_input)
			_collect()
			least = minf(least, (last.s - last.half_length) - (_sim.car.s + half_car))
		check(least >= hold_gap - 0.001, "in fourth gear at x = %s m he comes no nearer than %s m (%s m)" % [str(snappedf(x, 0.01)), str(hold_gap), str(snappedf(least, 0.001))])
		check(not _has_event_named("hit") and not _has_event_named("close_call"), "with no hit and no close call there")
		check_eq(_sim.faults.lamps, 0, "and no lamp")

	# The side road, taken at par: a Two-lane detour that rejoins ahead of the
	# motorcade.
	_sim = DriveSim.new(fresh_data())
	_events = []
	plan = LegGenerator.generate(data, "motorcade", 3, 901, "")
	_sim.gate.reset(2)
	_sim.begin_leg(plan)
	_checker.load_plan(plan)
	_collect()
	var side: LegChecker = LegChecker.new(data)
	side.load_plan(detour)
	var half_black: float = GameData.as_float(black.get("length")) * 0.5
	var longest: float = 0.0
	for entry: Variant in GameData.as_array(GameData.as_dict(plan["motorcade"]).get("cars")):
		longest = maxf(longest, GameData.as_float(GameData.as_dict(entry).get("ahead")))
	var slip_x: float = _sim.car.lane_center(3)
	var right_x: float = _sim.car.lane_center(2)
	var shift_at: float = _shift_up_at(at, gore, speed, third, GameData.as_float(special.get("start_ahead_m")))
	var on_side: float = 0.0
	var side_lanes: int = 0
	var side_divided: bool = true
	var oncoming_met: int = 0
	var trucks_passed: int = 0
	var met: Dictionary = {}
	var entered_at: float = -1.0
	var entry_speed: float = 0.0
	var rejoined_at: float = -1.0
	var rejoin_x: float = 0.0
	var behind_at_rejoin: float = 0.0
	var seen_ahead_after: int = 0
	var was_taken: bool = false
	var black_on_side: int = 0
	while _sim.leg.active:
		if _sim.car.s >= shift_at and _sim.gate.gear == 2:
			_sim.gate.reset(3)
		var taken: bool = _sim.encounter.side_road == EncounterSim.SIDE_ROAD_TAKEN
		if taken:
			_sim.car.x = side.line_x(_sim.car.s - gore)
		elif _sim.encounter.side_road == EncounterSim.SIDE_ROAD_BEHIND:
			_sim.car.x = right_x
		elif _sim.car.s >= at:
			_sim.car.x = lerpf(_checker.line_x(_sim.car.s), slip_x, clampf((_sim.car.s - at) / (0.5 * (gore - at)), 0.0, 1.0))
		else:
			_sim.car.x = _checker.line_x(_sim.car.s)
		_sim.step(_input)
		_collect()
		taken = _sim.encounter.side_road == EncounterSim.SIDE_ROAD_TAKEN
		if taken and not was_taken:
			entered_at = _sim.car.s
			entry_speed = _sim.car.speed
			side_lanes = _sim.car.lanes
			side_divided = _sim.car.divided
		if was_taken and not taken:
			rejoined_at = _sim.car.s
			rejoin_x = _sim.car.x
			behind_at_rejoin = _sim.car.s - half_car - (_sim.encounter.motorcade_s + longest + half_black)
		was_taken = taken
		if taken:
			on_side += DT
			for vehicle: TrafficSim.Vehicle in _sim.traffic.vehicles:
				if vehicle.role == EncounterSim.MOTORCADE:
					black_on_side += 1
				if met.has(vehicle.id) or vehicle.s > _sim.car.s:
					continue
				met[vehicle.id] = true
				if vehicle.direction < 0:
					oncoming_met += 1
				else:
					trucks_passed += 1
		elif rejoined_at >= 0.0:
			for vehicle: TrafficSim.Vehicle in _sim.traffic.vehicles:
				if vehicle.s > _sim.car.s:
					seen_ahead_after += 1
	check(entered_at >= gore and entered_at < gore + 1.0, "a car in the slip lane where it ends is on the side road (at %s m)" % str(snappedf(entered_at, 0.1)))
	check_near(entry_speed, third, 0.5, "(the test's driver is in third gear by then: %s km/h)" % str(snappedf(entry_speed, 0.1)))
	check_eq(side_lanes, 1, "driven: the side road has one lane his way")
	check(not side_divided, "and no median")
	check_eq(black_on_side, 0, "no car of the motorcade is on it")
	check(trucks_passed >= 1, "he passes its trucks (%d)" % trucks_passed)
	check(oncoming_met >= 2, "between its oncoming traffic (%d)" % oncoming_met)
	check(rejoined_at >= rejoin and rejoined_at < rejoin + 1.0, "and after %s m he is back on the main road (at %s m)" % [str(rejoin - gore), str(snappedf(rejoined_at, 0.1))])
	check_eq(_sim.car.lanes, 3, "three lanes")
	check(_sim.car.divided, "and a median again")
	check_near(rejoin_x, right_x, 0.05, "in its right lane, as far off its middle as he was off the side road's")
	check(behind_at_rejoin > 0.0, "ahead of the motorcade: its leading cars are %s m behind him" % str(snappedf(behind_at_rejoin, 0.1)))
	check_eq(seen_ahead_after, 0, "with nothing between him and the end of the leg")
	check_eq(_sim.faults.lamps, 0, "no lamp is lit")
	check(_sim.leg.time < par, "by the side road he is under par (%s s)" % str(snappedf(_sim.leg.time, 0.1)))
	check(not _sim.encounter.active, "and the encounter is over")
	check_near(GameData.as_float(_event("leg_ended").get("par_bonus")), floorf((par - _sim.leg.time) * tuning.f("par_bonus_rate")), 0.000001, "which pays the par bonus")

	# The side road, taken slowly: he still rejoins ahead of the motorcade,
	# and from behind it never touches him either.
	_sim = DriveSim.new(fresh_data())
	_events = []
	plan = LegGenerator.generate(data, "motorcade", 3, 901, "")
	_sim.gate.reset(2)
	_sim.begin_leg(plan)
	_checker.load_plan(plan)
	_collect()
	was_taken = false
	var closest_behind: float = INF
	var followers: int = 0
	var follower_speed: float = 0.0
	var pushed: float = 0.0
	while _sim.leg.active:
		var taken: bool = _sim.encounter.side_road == EncounterSim.SIDE_ROAD_TAKEN
		if taken:
			_sim.car.x = _sim.car.lane_center(0)
			if _sim.gate.gear != 1:
				_sim.gate.reset(1)
		elif _sim.encounter.side_road == EncounterSim.SIDE_ROAD_BEHIND:
			_sim.car.x = right_x
		elif _sim.car.s >= at:
			_sim.car.x = lerpf(_checker.line_x(_sim.car.s), slip_x, clampf((_sim.car.s - at) / (0.5 * (gore - at)), 0.0, 1.0))
		else:
			_sim.car.x = _checker.line_x(_sim.car.s)
		var speed_before: float = _sim.car.speed
		_sim.step(_input)
		_collect()
		if _sim.encounter.side_road == EncounterSim.SIDE_ROAD_BEHIND:
			followers = maxi(followers, _sim.encounter.motorcade().size())
			for vehicle: TrafficSim.Vehicle in _sim.encounter.motorcade():
				closest_behind = minf(closest_behind, (_sim.car.s - half_car) - (vehicle.s + vehicle.half_length))
				follower_speed = vehicle.speed
			pushed = maxf(pushed, _sim.car.speed - maxf(speed_before, _sim.car.cruise_speed(_sim.gate.gear)))
	check(_sim.leg.time > behind_time, "(crawling along the side road in first gear takes longer than staying behind: %s s)" % str(snappedf(_sim.leg.time, 0.1)))
	check_eq(followers, 5, "however long he took, the motorcade is behind him when he rejoins: all five cars")
	check(closest_behind >= hold_gap - 0.001, "it comes no nearer than %s m to his bumper (%s m)" % [str(hold_gap), str(snappedf(closest_behind, 0.001))])
	check_near(follower_speed, _sim.car.speed, 0.01, "holding his speed behind him")
	check(pushed <= 0.000001, "it does not push him")
	check_eq(_sim.faults.lamps, 0, "and no lamp is lit")
	check(not _has_event_named("hit"), "the motorcade never touches him")


# --- Driving -----------------------------------------------------------------

func _begin(leg_id: String, act: int, leg_seed: int, modifier: String = "") -> Dictionary:
	var plan: Dictionary = LegGenerator.generate(data, leg_id, act, leg_seed, modifier)
	_sim.gate.reset(3)
	_sim.begin_leg(plan)
	_checker.load_plan(plan)
	_collect()
	return plan


## Drives the whole leg on the plan's line in third gear.
func _drive(plan: Dictionary) -> DriveLog:
	return _drive_to(plan, GameData.as_float(plan["length"]) + 1.0)


## Drives on the plan's line, `offset` metres to its right, until the car has
## gone `to_s` or the leg has ended.
func _drive_to(plan: Dictionary, to_s: float, offset: float = 0.0) -> DriveLog:
	var log: DriveLog = DriveLog.new()
	var calms: Array[Vector2] = []
	for entry: Variant in GameData.as_array(plan["beats"]):
		var beat: Dictionary = entry
		if GameData.as_string(beat["type"]) == "CALM":
			calms.append(Vector2(GameData.as_float(beat["s"]), GameData.as_float(beat["s"]) + GameData.as_float(beat["length"])))
	var planned_lane: Dictionary = {}
	var known: Dictionary = {}
	var signalling_since: Dictionary = {}
	var moving_since: Dictionary = {}
	var first_tick: bool = _sim.leg.time <= 0.0
	var ticks: int = 0
	var guard: int = int(400.0 / DT)
	while _sim.car.s < to_s and _sim.leg.active and guard > 0:
		guard -= 1
		_sim.car.x = _checker.line_x(_sim.car.s) + offset
		_sim.step(_input)
		ticks += 1
		for event: Dictionary in _sim.drain_events():
			_events.append(event)
			if GameData.as_string(event.get("type")) == "sfx_requested" and GameData.as_string(event.get("hazard")) == "cone":
				log.cone_hits += 1
		log.most_vehicles = maxi(log.most_vehicles, _sim.traffic.vehicles.size())
		var in_calm: bool = false
		for calm: Vector2 in calms:
			if _sim.car.s >= calm.x and _sim.car.s <= calm.y:
				in_calm = true
		for vehicle: TrafficSim.Vehicle in _sim.traffic.vehicles:
			if not known.has(vehicle.id):
				known[vehicle.id] = true
				if not first_tick:
					log.appeared_ahead.append(absf(vehicle.s - _sim.car.s))
			if in_calm and vehicle.direction > 0 and vehicle.x < _sim.car.road_right():
				log.nearest_in_calm = minf(log.nearest_in_calm, absf(vehicle.s - _sim.car.s))
			if vehicle.signalling != 0 and not vehicle.changing and not signalling_since.has(vehicle.id):
				signalling_since[vehicle.id] = ticks
				planned_lane[vehicle.id] = vehicle.change_to_lane
			if vehicle.changing and not moving_since.has(vehicle.id):
				moving_since[vehicle.id] = ticks
				if signalling_since.has(vehicle.id):
					log.signal_seconds.append(float(ticks - GameData.as_int(signalling_since[vehicle.id])) * DT)
			if moving_since.has(vehicle.id) and not vehicle.changing and vehicle.signalling == 0:
				log.move_seconds.append(float(ticks - GameData.as_int(moving_since[vehicle.id])) * DT)
				log.changes_seen += 1
				if vehicle.lane == GameData.as_int(planned_lane.get(vehicle.id, -9)) and is_equal_approx(vehicle.x, _sim.traffic.lane_center(vehicle.lane)):
					log.changes_as_planned += 1
				moving_since.erase(vehicle.id)
				signalling_since.erase(vehicle.id)
		first_tick = false
	log.seconds = float(ticks) * DT
	return log


func _drive_seconds(plan: Dictionary, seconds: float) -> void:
	_drive_to(plan, _sim.car.s + seconds * _sim.car.speed * KMH_TO_MS - 0.001)


func _collect() -> void:
	for event: Dictionary in _sim.drain_events():
		_events.append(event)


## The last event of a type, or {}.
func _event(type: String) -> Dictionary:
	_collect()
	for index: int in range(_events.size() - 1, -1, -1):
		if GameData.as_string(_events[index].get("type")) == type:
			return _events[index]
	return {}


## The time constant of the car's sideways response, in seconds, measured at
## full lock: from how far its sideways speed has come after 0.2 s.
func _response_time() -> float:
	var car: CarSim = _sim.car
	var x: float = car.x
	var v_lat: float = car.v_lat
	car.v_lat = 0.0
	var target: float = tuning.f("lat_per_kmh") * car.speed
	var ticks: int = roundi(0.2 / DT)
	for _tick: int in ticks:
		car.step(DT, 1.0, 3, false, 0.0)
	var reached: float = car.v_lat / (tuning.f("lat_per_kmh") * car.speed)
	car.x = x
	car.v_lat = v_lat
	if not check(target > 0.0 and reached > 0.0 and reached < 1.0, "the car answers the wheel (%s of full sideways speed after 0.2 s)" % str(snappedf(reached, 0.001))):
		return 1.0
	return -(float(ticks) * DT) / log(1.0 - reached)


# --- Encounters on an empty road ---------------------------------------------

## Starts a leg with nothing on the road but its encounter: no traffic, no
## hazards, no bends, no gusts.
func _begin_quiet(leg_id: String, act: int, leg_seed: int) -> Dictionary:
	_sim = DriveSim.new(fresh_data())
	_input = DriveInput.new()
	_events = []
	var plan: Dictionary = LegGenerator.generate(data, leg_id, act, leg_seed, "")
	plan["spawns"] = []
	plan["hazards"] = []
	plan["curves"] = []
	plan["gusts"] = []
	plan["zones"] = []
	_sim.gate.reset(3)
	_sim.begin_leg(plan)
	_checker.load_plan(plan)
	_collect()
	return plan


func _hold_lane_and_step(lane: int) -> void:
	_sim.car.x = _sim.car.lane_center(lane)
	_sim.step(_input)
	_collect()


## Steps until the leg's clock reads `seconds`, the car held in `lane`.
func _drive_quiet_until(seconds: float, lane: int) -> void:
	var guard: int = int(300.0 / DT)
	while _sim.leg.time < seconds - DT * 0.5 and _sim.leg.active and guard > 0:
		guard -= 1
		_hold_lane_and_step(lane)


func _events_named(type: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for event: Dictionary in _events:
		if GameData.as_string(event.get("type")) == type:
			out.append(event)
	return out


## How far into the leg a driver who starts in second gear behind the
## motorcade must change up to third so as to reach the end of the slip lane
## at third gear's speed without having met the motorcade's wall: as late as
## the acceleration allows, and no earlier than keeps him clear of it.
func _shift_up_at(at: float, gore: float, slow: float, fast: float, start_ahead: float) -> float:
	# Changing up at X he closes (gore - X) * (1 - slow / fast) on the last
	# car, which is start_ahead in front of him until then.
	var may_close: float = start_ahead * 0.5
	var from: float = gore - may_close / (1.0 - slow / fast)
	check(from < at, "(the test's driver changes up before the slip lane, at %s m)" % str(snappedf(from, 0.1)))
	return from

# --- The law -----------------------------------------------------------------

## Puts the car on the plan's line for the next tick. With `indicating` he
## works the indicator before each lane change, as the law asks.
func _keep_to_the_line(indicating: bool) -> void:
	_sim.car.x = _checker.line_x(_sim.car.s)
	if not indicating or _sim.items.indicator != 0:
		return
	var here: int = _sim.car.lane_of(_checker.line_x(_sim.car.s))
	var soon: int = _sim.car.lane_of(_checker.line_x(_sim.car.s + 45.0))
	if soon != here:
		_sim.items.complete(data.record("rituals", "indicator"), Gesture.DIR_UP if soon > here else Gesture.DIR_DOWN)


## A Patrol leg in which he has just been pulled over, with `cash` to his name.
func _pull_over_with(game_data: GameData, cash: float) -> void:
	_sim = DriveSim.new(game_data)
	_events = []
	var plan: Dictionary = _begin("patrol", 2, 555)
	_sim.cash = cash
	var guard: int = int(60.0 / DT)
	while not _sim.suspicion.watching and guard > 0:
		guard -= 1
		_keep_to_the_line(true)
		_sim.step(_input)
	_sim.suspicion.add(_sim.suspicion.maximum())
	_keep_to_the_line(true)
	_sim.step(_input)
	_collect()
	check(_sim.pulled_over and not plan.is_empty(), "(pulled over with %s cash)" % str(cash))


## A Patrol leg driven clean until the police car watches him, with `cash`
## to his name.
func _until_watched(cash: float) -> void:
	_sim = DriveSim.new(fresh_data())
	_events = []
	_input.clear()
	_begin("patrol", 2, 555)
	_sim.cash = cash
	var guard: int = int(60.0 / DT)
	while not _sim.suspicion.watching and guard > 0:
		guard -= 1
		_keep_to_the_line(true)
		_sim.step(_input)
	_collect()
	check(_sim.suspicion.watching, "(the police car watches him)")


## Suspicion is put at the top: on the next tick he is pulled over.
func _pull_over_now() -> void:
	_sim.suspicion.add(_sim.suspicion.maximum())
	_keep_to_the_line(true)
	_sim.step(_input)
	_collect()
	check(_sim.pulled_over, "(he is pulled over)")


## Steps for `seconds`, the car on the plan's line while it is not standing
## with the officer.
func _ticks_on_the_line(seconds: float) -> void:
	for _tick: int in roundi(seconds / DT):
		if not _sim.pulled_over:
			_keep_to_the_line(true)
		_sim.step(_input)
	_collect()


## Drives on the plan's line, indicating, with his hand left alone.
func _drive_clean(seconds: float) -> void:
	_input.clear()
	_ticks_on_the_line(seconds)


## What calms him for a click, each tried by the hand: a bead at the mirror,
## the horn at the hub, and the horn under the thumb of the hand that grips
## (the thumb keypad). Returns the rituals that were completed, in order.
func _try_what_calms() -> Array:
	_collect()
	_events = []
	for anchor: StringName in [&"mirror", &"horn"]:
		_input.clear()
		_input.pointer_is_absolute = true
		_input.pointer = _sim.hand.anchor_pointer(_sim.hand.anchor_index(anchor))
		_ticks_on_the_line(1.0)
		_input.lmb = true
		_ticks_on_the_line(tuning.f("tap_max_time") * 0.3)
		_input.clear()
		_ticks_on_the_line(0.3)
	_input.pointer_is_absolute = true
	_input.pointer = _sim.space.point_to_pointer(_sim.space.grip_reference)
	_input.lmb = true
	_ticks_on_the_line(1.0)
	_input.pad_horn = true
	_ticks_on_the_line(3.0 * DT)
	_input.clear()
	_ticks_on_the_line(0.3)
	var done: Array = []
	for event: Dictionary in _events:
		if GameData.as_string(event.get("type")) == "ritual_completed":
			done.append(GameData.as_string(event.get("ritual")) + (" (keypad)" if GameData.as_bool(event.get("keypad")) else ""))
	return done


## The fine his licence costs with `cash` to his name.
func _fine_with(cash: float) -> float:
	_pull_over_with(fresh_data(), cash)
	_hand_over(&"dash_1")
	return cash - _sim.cash


## Carries what is at `from` to the driver's window and lets go (DRAG_TO).
func _hand_over(from: StringName) -> void:
	_input.clear()
	_input.pointer_is_absolute = true
	_input.pointer = _sim.hand.anchor_pointer(_sim.hand.anchor_index(from))
	for _tick: int in int(1.5 / DT):
		_sim.step(_input)
	_input.lmb = true
	for _tick: int in int(0.1 / DT):
		_sim.step(_input)
	_input.pointer = _sim.hand.anchor_pointer(_sim.hand.anchor_index(&"driver_window"))
	for _tick: int in int(2.5 / DT):
		_sim.step(_input)
	_input.lmb = false
	for _tick: int in int(0.2 / DT):
		_sim.step(_input)
	_input.clear()
	_collect()


func _contraband_count() -> int:
	var count: int = 0
	for item: ItemSim.Item in _sim.items.items:
		if GameData.as_bool(item.record.get("contraband")):
			count += 1
	return count


func _has_event_named(type: String) -> bool:
	for event: Dictionary in _events:
		if GameData.as_string(event.get("type")) == type:
			return true
	return false


# --- Plans -------------------------------------------------------------------

## Vehicles of a plan that count toward its density.
func _ordinary(plan: Dictionary) -> int:
	var count: int = 0
	for entry: Variant in GameData.as_array(plan["spawns"]):
		var spawn: Dictionary = entry
		if GameData.as_int(spawn["direction"]) > 0 and GameData.as_int(spawn["lane"]) < GameData.as_int(plan["lanes"]) \
				and GameData.as_string(spawn["role"]).is_empty():
			count += 1
	return count


func _beats_of(plan: Dictionary, type: String) -> int:
	var count: int = 0
	for entry: Variant in GameData.as_array(plan["beats"]):
		if GameData.as_string(GameData.as_dict(entry)["type"]) == type:
			count += 1
	return count


func _has_adjacent_calms(plan: Dictionary) -> bool:
	var previous: String = ""
	for entry: Variant in GameData.as_array(plan["beats"]):
		var type: String = GameData.as_string(GameData.as_dict(entry)["type"])
		if type == "CALM" and previous == "CALM":
			return true
		previous = type
	return false


## Average metres of CALM beats per leg, by leg type.
func _calm_metres() -> Dictionary:
	var out: Dictionary = {}
	for leg: Dictionary in data.records("legs"):
		var id: String = GameData.as_string(leg.get("id"))
		var acts: Array = GameData.as_array(leg.get("acts"))
		var metres: float = 0.0
		for index: int in SAMPLE_SEEDS:
			var plan: Dictionary = LegGenerator.generate(data, id, GameData.as_int(acts[index % acts.size()]), 500 + index, "")
			for entry: Variant in GameData.as_array(plan["beats"]):
				var beat: Dictionary = entry
				if GameData.as_string(beat["type"]) == "CALM":
					metres += GameData.as_float(beat["length"])
		out[id] = metres / float(SAMPLE_SEEDS)
	return out


## A Night leg whose first hazard lies well beyond the high beam's reach.
func _night_plan_with_hazard() -> Dictionary:
	for leg_seed: int in range(200, 260):
		var plan: Dictionary = LegGenerator.generate(data, "night", 2, leg_seed, "")
		var s: float = _first_hazard_s(plan)
		if s > tuning.f("high_beam_cone") + 20.0 and s < 600.0:
			return plan
	return {}


func _first_hazard_s(plan: Dictionary) -> float:
	var hazards: Array = GameData.as_array(plan.get("hazards"))
	if hazards.is_empty():
		return -1.0
	return GameData.as_float(GameData.as_dict(hazards[0])["s"])


func _hazards_in_view() -> Array:
	return GameData.as_array(_sim.snapshot()["hazards"])
