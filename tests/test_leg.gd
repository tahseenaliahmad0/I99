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
	# Nothing moves on while the officer waits.
	var leg_time: float = _sim.leg.time
	var s_before: float = _sim.car.s
	_input.clear()
	_input.rmb = false
	for _tick: int in int(3.0 / DT):
		_sim.step(_input)
	check_near(_sim.leg.time, leg_time, 0.000001, "the leg's clock stands while he is pulled over")
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
