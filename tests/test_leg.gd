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
