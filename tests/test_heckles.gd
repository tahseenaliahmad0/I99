extends CabinSuite
## M9b: the heckles (GDD 11.3). T-HECKLE-01.
##
## How a record says what it does, and how the rules were read where the GDD
## leaves room, is D-061.

const KMH_TO_MS: float = 1.0 / 3.6
const QUIET: String = "open_road"

var _checker: LegChecker
## Every heckle event of the test so far, each with the tick it came in.
var _said: Array[Dictionary] = []
## The ticks of the close calls so far.
var _calls: PackedInt32Array = PackedInt32Array()


func before_each() -> void:
	super.before_each()
	_checker = LegChecker.new(data)
	_said = []


# --- Helpers -------------------------------------------------------------------

func _heckle(id: String) -> Dictionary:
	return data.record("heckles", id)


func _lead_ticks() -> int:
	return _ticks_in(tuning.f("heckle_lead"))


## A Telling for a Table, with whoever has been carried to Basra before.
func _tell(table_id: String, telling_seed: int, guests: PackedStringArray = PackedStringArray()) -> void:
	_sim = DriveSim.new(fresh_data())
	_sim.guests = guests
	_events = []
	_said = []
	_keep_lane = true
	_input.clear()
	_sim.begin_telling(table_id, telling_seed)
	_gather()


## One tick, the heckle events kept apart with their tick.
func _step() -> void:
	_tick()
	_gather()


func _steps(count: int) -> void:
	for _index: int in count:
		_step()


func _gather() -> void:
	for event: Dictionary in _sim.drain_events():
		_events.append(event)
	for event: Dictionary in _events:
		var type: String = GameData.as_string(event.get("type"))
		if (type == "heckle_started" or type == "heckle_resolved") and not event.has("tick"):
			event["tick"] = _sim.tick
			_said.append(event)
		elif type == "close_call" and not event.has("tick"):
			event["tick"] = _sim.tick
			_calls.append(_sim.tick)


func _last(type: String) -> Dictionary:
	for index: int in range(_said.size() - 1, -1, -1):
		if GameData.as_string(_said[index].get("type")) == type:
			return _said[index]
	return {}


## A quiet, straight leg of a Telling at `table_id` on which the next thing
## the Table says is `heckle_id`: at once, whatever the leg had planned.
func _quiet_leg_with(table_id: String, heckle_id: String, guests: PackedStringArray = PackedStringArray()) -> void:
	_tell(table_id, 1, guests)
	_into_quiet_leg()
	_sim.nerves.set_value(30.0)
	_plan(heckle_id)
	_events = []
	_said = []
	_calls = PackedInt32Array()


## Past the first fork onto a leg with nothing on its road, dry and by day
## whatever leg the fork gave, in third gear.
func _into_quiet_leg() -> void:
	_into_next_quiet_leg()
	var plan: Dictionary = _sim.leg.plan.duplicate(true)
	plan["leg"] = QUIET
	plan["condition"] = "clear"
	plan["modifier"] = ""
	_sim.begin_leg(plan)
	_sim.in_encounter = true
	_sim.heckles.end_leg()
	_sim.drain_events()


func _plan(heckle_id: String) -> void:
	var planned: Array[Dictionary] = [{"record": _heckle(heckle_id), "due_s": 0.0, "roll": 0.0}]
	_sim.heckles.planned = planned
	_sim.heckles.said = 0


## Steps until the heckle is said; then on to the tick its lead is over.
func _hear_it_out() -> bool:
	var guard: int = _ticks_in(2.0)
	while _last("heckle_started").is_empty() and guard > 0:
		guard -= 1
		_step()
	if _last("heckle_started").is_empty():
		return false
	_steps(_lead_ticks())
	return true


## Steps until the heckle has been resolved (or `seconds` have passed).
func _until_resolved(seconds: float) -> Dictionary:
	var guard: int = _ticks_in(seconds)
	while _last("heckle_resolved").is_empty() and guard > 0:
		guard -= 1
		_step()
	return _last("heckle_resolved")


## Seconds from the subtitle to the resolution.
func _took() -> float:
	return float(GameData.as_int(_last("heckle_resolved").get("tick")) - GameData.as_int(_last("heckle_started").get("tick"))) * DT


## One close call: a truck in the next lane is passed with half the gap.
func _close_pass(ahead: float = 12.0) -> void:
	var speed: float = tuning.fi("gear_speeds", 2)
	var other: TrafficSim.Vehicle = _sim.traffic.spawn(&"truck", 0, _sim.car.s + ahead, speed - tuning.f("close_call_min_closing") - 10.0)
	var beside: float = other.x + other.half_width + _sim.car.half_width() + tuning.f("close_call_gap") * 0.5
	var lane_x: float = _sim.car.x
	_keep_lane = false
	var guard: int = _ticks_in(30.0)
	while _sim.car.s < other.s + other.half_length + 8.0 and guard > 0:
		guard -= 1
		_sim.car.x = beside
		_step()
	_sim.car.x = lane_x
	_keep_lane = true
	_sim.traffic.clear()


## Slower vehicles in the lane beside him, `aheads` metres ahead of the car.
func _line_up(aheads: Array[float]) -> void:
	var speed: float = tuning.fi("gear_speeds", 2) - 40.0
	for ahead: float in aheads:
		_sim.traffic.spawn(&"truck", 0, _sim.car.s + ahead, speed)


func _resolved_as(outcome: String, what: String) -> void:
	check_eq(GameData.as_string(_last("heckle_resolved").get("outcome")), outcome, what)


# --- T-HECKLE-01 -----------------------------------------------------------------

## T-HECKLE-01: Heckles of 11.3: one per leg in Act 1 and two per leg after,
## never during an encounter or a boss; the subtitle appears heckle_lead
## before anything changes; each type resolves as its row states: Twist,
## Dare, Doubt, Question, Order and the Fib.
func test_heckle_01() -> void:
	_check_the_rows()
	_check_the_pool()
	_check_the_counts()
	_check_never_in_an_encounter()
	_check_the_lead()
	_check_dares()
	_check_the_doubt()
	_check_the_question()
	_check_orders()
	_check_the_fib()
	_check_twists()
	_check_twists_beside_a_modifier()
	_check_the_shower()
	_check_the_words()


## The table of GDD 11.3, row by row, as the records have it.
func _check_the_rows() -> void:
	check_near(tuning.f("heckle_lead"), 2.0, 0.000001, "GDD 11.3: the subtitle appears 2 s before anything changes")
	check_eq(tuning.a("heckles_per_leg"), [1.0, 2.0, 2.0], "one heckle per leg in Act 1, two per leg after (GDD 12.3)")
	var twists: PackedStringArray = []
	var dares: Dictionary = {}
	for heckle: Dictionary in data.records("heckles"):
		var id: String = GameData.as_string(heckle.get("id"))
		var gives: Dictionary = GameData.as_dict(heckle.get("pass"))
		var costs: Dictionary = GameData.as_dict(heckle.get("fail"))
		match GameData.as_string(heckle.get("type")):
			"TWIST":
				var what: String = GameData.as_string(heckle.get("twist"))
				if not twists.has(what):
					twists.append(what)
				if what == HeckleDirector.SHOWER:
					check_near(GameData.as_float(heckle.get("duration_s")), 20.0, 0.000001, "%s: a 20 s shower" % id)
			"DARE":
				check_near(GameData.as_float(heckle.get("window_s")), 15.0, 0.000001, "%s: a Dare has a 15 s window" % id)
				check(costs.is_empty() and not gives.has("nerves"), "%s: a Dare is optional: it costs nothing" % id)
				var answer: String = GameData.as_string(GameData.as_array(heckle.get("answer"))[0])
				dares[answer] = GameData.as_float(gives.get("cash"))
			"DOUBT":
				check_near(GameData.as_float(heckle.get("window_s")), 15.0, 0.000001, "%s: a Doubt bites after 15 s" % id)
				check_near(GameData.as_float(costs.get("nerves")), 10.0, 0.000001, "%s: +10 Nerves" % id)
				check_near(GameData.as_float(gives.get("nerves")), -10.0, 0.000001, "%s: answered, -10 instead" % id)
				check_eq(GameData.as_array(heckle.get("answer")), ["close_call", "gear4_5s"], "%s: answered with a close call or 5 s in fourth gear" % id)
			"QUESTION":
				check_near(GameData.as_float(heckle.get("window_s")), 15.0, 0.000001, "%s: a Question is for 15 s" % id)
				check_eq(GameData.as_array(heckle.get("keep")), ["nerves_under_50", "no_horn"], "%s: Nerves under 50 with no horn" % id)
				check_near(GameData.as_float(gives.get("nerves")), -10.0, 0.000001, "%s: -10 Nerves" % id)
				check_near(GameData.as_float(gives.get("cash")), 10.0, 0.000001, "%s: and +10 cash" % id)
			"ORDER":
				check_near(GameData.as_float(heckle.get("window_s")), 10.0, 0.000001, "%s: an Order is to be done within 10 s" % id)
				check_near(GameData.as_float(gives.get("nerves")), -8.0, 0.000001, "%s: -8 Nerves" % id)
				check_near(GameData.as_float(costs.get("nerves")), 6.0, 0.000001, "%s: ignored, +6" % id)
				check(data.has_record("rituals", GameData.as_string(heckle.get("ritual"))), "%s: it names a ritual" % id)
			"FIB":
				check_near(GameData.as_float(heckle.get("window_s")), 5.0, 0.000001, "%s: the ghost hand holds for 5 s" % id)
				check_eq(GameData.as_array(heckle.get("tables")), ["children"], "%s: Children only" % id)
	twists.sort()
	check_eq(twists, PackedStringArray(["melon_truck", "sheep", "shower", "wedding"]), "a Twist is sheep, a melon truck, a wedding motorcade or a shower")
	check_eq(dares, {"gear4_10s": 15.0, "close_call_x3": 20.0, "hands_off_3s": 10.0, "pass_x3_10s": 15.0},
			"the Dares: fourth gear for 10 s (+15), three close calls (+20), 3 s hands-off (+10), three vehicles in 10 s (+15)")


## Who says what (GDD 11.2, 11.5): a Table's types by its weights, a guest's
## two beside them, and at Noor's Table nobody.
func _check_the_pool() -> void:
	var weight: float = tuning.f("guest_heckle_weight")
	var none: PackedStringArray = []
	for table: Dictionary in data.records("tables"):
		var id: String = GameData.as_string(table.get("id"))
		var rules: TableRules = TableRules.of(data, id)
		var pool: Array[Dictionary] = HeckleDirector.pool(data, rules, none, weight)
		var by_type: Dictionary = {}
		for entry: Dictionary in pool:
			var type: String = GameData.as_string(GameData.as_dict(entry["record"]).get("type"))
			by_type[type] = GameData.as_float(by_type.get(type)) + GameData.as_float(entry["weight"])
		if id == "noor":
			check(pool.is_empty(), "nobody heckles at Noor's Table")
			check(HeckleDirector.pool(data, rules, PackedStringArray(["drummer", "student"]), weight).is_empty(), "nor do the guests there")
			continue
		check(not pool.is_empty(), "the %s Table has something to say" % id)
		for type: Variant in rules.heckle_weights:
			check_near(GameData.as_float(by_type.get(type)), GameData.as_float(rules.heckle_weights[type]), 0.000001,
					"%s: its %s records share that type's weight" % [id, str(type)])
		check_eq(by_type.size(), rules.heckle_types().size(), "%s: and no other type is said there" % id)
		var with_guest: Array[Dictionary] = HeckleDirector.pool(data, rules, PackedStringArray(["drummer"]), weight)
		check_eq(with_guest.size(), pool.size() + 2, "%s: a wedding guest adds two heckles to the pool" % id)
	# The weights are the rule, whatever the records list: a Table with no
	# weights is silent, guests and all; a Table says only the types it has
	# a weight for.
	var silent: TableRules = TableRules.new()
	silent.id = "drivers"
	check(HeckleDirector.pool(data, silent, PackedStringArray(["drummer"]), weight).is_empty(), "a Table with no heckle weights says nothing, whoever sits at it")
	var dares_only: TableRules = TableRules.of(data, "groom")
	dares_only.heckle_weights = {"DARE": 100}
	var other_types: int = 0
	for entry: Dictionary in HeckleDirector.pool(data, dares_only, none, weight):
		if GameData.as_string(GameData.as_dict(entry["record"]).get("type")) != "DARE":
			other_types += 1
	check_eq(other_types, 0, "a Table weighted for Dares alone has none of the Doubts and Orders its records list")
	# Drawn by those weights: over many legs told to the Children, about four
	# Twists to a Fib; to the Drivers, Dares only.
	var counts: Dictionary = {}
	_tell("children", 1)
	for leg_seed: int in 400:
		_sim.heckles.plan_leg(_sim.rng, _sim.table, none, 1, QUIET, "")
		for entry: Dictionary in _sim.heckles.planned:
			var type: String = GameData.as_string(GameData.as_dict(entry["record"]).get("type"))
			counts[type] = GameData.as_int(counts.get(type)) + 1
	var twists: int = GameData.as_int(counts.get("TWIST"))
	var fibs: int = GameData.as_int(counts.get("FIB"))
	check_eq(twists + fibs, 400, "400 legs of Act 1 told to the Children: 400 heckles, Twists and Fibs")
	check(absf(float(twists) / 400.0 - 0.8) < 0.06, "about 80 in 100 are Twists (%d of 400)" % twists)
	_tell("drivers", 1)
	var others: int = 0
	for leg_seed: int in 100:
		_sim.heckles.plan_leg(_sim.rng, _sim.table, none, 2, QUIET, "")
		check_eq(_sim.heckles.planned.size(), 2, "(two are planned for a leg of Act 2)") if leg_seed == 0 else true
		for entry: Dictionary in _sim.heckles.planned:
			if GameData.as_string(GameData.as_dict(entry["record"]).get("type")) != "DARE":
				others += 1
	check_eq(others, 0, "told to the Drivers, every heckle is a Dare")


# --- How many, and when --------------------------------------------------------------

## The leg's encounter is at him (D-061), read from what the encounter shows
## and not from what it says of itself: the Patrol's blue lights or its
## watching, the Tailgater from his tell until he is gone, the Motorcade's
## spotlight.
func _at_him() -> bool:
	var encounter: EncounterSim = _sim.encounter
	if encounter.police_lights or _sim.suspicion.watching:
		return true
	if encounter.tail_phase >= EncounterSim.TAIL_TELL and encounter.tail_phase < EncounterSim.TAIL_GONE:
		return true
	return encounter.glare > 0.0


## Drives one leg of a Telling as the generator's line has it, past its
## Exit, and says what the Table did: { "said", "pressed" (ticks the leg's
## encounter was at him), "in_encounter" (heckles begun in such a tick),
## "open_at_end", "hits" }.
## With `spring`, the leg's own heckles are dropped and that one falls due in
## the tick the Patrol's lights come on.
func _drive_a_leg(table_id: String, act: int, leg_id: String, telling_seed: int, crowd_the_motorcade: bool = false, spring: String = "") -> Dictionary:
	_tell(table_id, telling_seed)
	if act > 1:
		_drive_on_to_act(act)
	# He comes to the fork as the generator has him: in third gear, at par.
	_sim.gate.reset(3)
	_sim.car.speed = tuning.fi("gear_speeds", 2)
	# Both branches of the fork ahead are this leg.
	for branch: Dictionary in _sim.run.branches:
		branch["leg"] = leg_id
		branch["modifier"] = ""
		branch["par_s"] = GameData.as_float(data.record("legs", leg_id).get("par_s"))
	_events = []
	_said = []
	_input.clear()
	_keep_lane = false
	var out: Dictionary = {"said": 0, "pressed": 0, "in_encounter": 0, "open_at_end": false, "hits": 0, "types": [], "after_exit": 0,
			"early": 0, "out_of_span": 0, "late_m": 0.0, "pressed_last": 0, "said_tick": 0}
	var sprung: bool = false
	var due: PackedFloat64Array = PackedFloat64Array()
	var span_from: float = tuning.fi("heckle_span", 0)
	var span_to: float = tuning.fi("heckle_span", 1)
	var on_leg: bool = false
	var ended: bool = false
	var exit_at: float = tuning.f("leg_length") - tuning.f("leg_tail")
	var gear: int = 2 if leg_id == "motorcade" and not crowd_the_motorcade else 3
	var guard: int = _ticks_in(400.0)
	while not ended and guard > 0:
		guard -= 1
		var car: CarSim = _sim.car
		if on_leg:
			car.x = _checker.line_x(minf(car.s, exit_at))
			if _sim.gate.gear != gear:
				_sim.gate.reset(gear)
		else:
			car.x = car.lane_center(car.lanes - 1)
		# He drives within the law, and is not the test's subject if he does not.
		_sim.suspicion.value = 0.0
		_sim.nerves.set_value(30.0)
		var seen: int = _said.size()
		var s_before: float = car.s
		_step()
		for event: Dictionary in _events:
			match GameData.as_string(event.get("type")):
				"leg_started":
					if not on_leg:
						on_leg = true
						_checker.load_plan(_sim.leg.plan)
						if not spring.is_empty():
							_sim.heckles.end_leg()
						# Where the Table means to speak: each place inside the
						# span of the leg's beats (a Twist's goes by its stretch).
						var beats_end: float = GameData.as_float(_sim.leg.plan.get("beats_end"))
						for entry: Dictionary in _sim.heckles.planned:
							var place: float = GameData.as_float(entry["due_s"])
							due.append(place)
							if not entry.has("stretch") and (place < span_from * beats_end - 0.001 or place > span_to * beats_end + 0.001):
								out["out_of_span"] = GameData.as_int(out["out_of_span"]) + 1
				"leg_ended":
					ended = on_leg
				"hit":
					out["hits"] = GameData.as_int(out["hits"]) + 1
		_events = []
		if not on_leg:
			continue
		if _at_him():
			out["pressed"] = GameData.as_int(out["pressed"]) + 1
			out["pressed_last"] = _sim.tick
		if not spring.is_empty() and not sprung and _sim.encounter.police_lights:
			# The Patrol's lights have just come on: a heckle falls due now.
			sprung = true
			_plan(spring)
		for index: int in range(seen, _said.size()):
			var event: Dictionary = _said[index]
			if GameData.as_string(event.get("type")) == "heckle_started":
				var nth: int = GameData.as_int(out["said"])
				if nth < due.size():
					# Not before the car is at its place; and, with nothing in
					# the way, as it gets there.
					if _sim.car.s < due[nth]:
						out["early"] = GameData.as_int(out["early"]) + 1
					if nth == 0:
						out["late_m"] = _sim.car.s - due[nth]
				out["said"] = nth + 1
				GameData.as_array(out["types"]).append(GameData.as_string(event.get("heckle")))
				out["said_tick"] = _sim.tick
				if _at_him() or _sim.boss.active or _sim.run.stage != RunState.Stage.LEG:
					out["in_encounter"] = GameData.as_int(out["in_encounter"]) + 1
				if s_before >= exit_at:
					out["after_exit"] = GameData.as_int(out["after_exit"]) + 1
			elif GameData.as_string(event.get("outcome")) == HeckleDirector.LAPSED:
				out["open_at_end"] = true
	_keep_lane = true
	check(ended, "(%s, Act %d: the leg is driven to its end)" % [leg_id, act])
	return out


## Every kind of leg, in every act it is met in, told to each Table in turn:
## one heckle in Act 1, two after; each begun on the leg, before its Exit,
## with the leg's encounter not at him.
func _check_the_counts() -> void:
	var tables: PackedStringArray = ["children", "drivers", "uncles", "inlaws", "aunts", "groom"]
	var per_leg: Array = tuning.a("heckles_per_leg")
	var turn: int = 0
	var pressed_legs: int = 0
	var seen_types: Dictionary = {}
	for leg: Dictionary in data.records("legs"):
		var leg_id: String = GameData.as_string(leg.get("id"))
		for act_value: Variant in GameData.as_array(leg.get("acts")):
			var act: int = GameData.as_int(act_value)
			var table_id: String = tables[turn % tables.size()]
			turn += 1
			var drive: Dictionary = _drive_a_leg(table_id, act, leg_id, 11 + turn)
			var where: String = "%s in Act %d, told to the %s Table" % [leg_id, act, table_id]
			check_eq(GameData.as_int(drive["said"]), GameData.as_int(per_leg[act - 1]), "%s: %d heckle(s)" % [where, GameData.as_int(per_leg[act - 1])])
			check_eq(GameData.as_int(drive["in_encounter"]), 0, "%s: none begun while its encounter was at him" % where)
			check_eq(GameData.as_int(drive["after_exit"]), 0, "%s: none begun after the Exit opened" % where)
			check_eq(GameData.as_int(drive["out_of_span"]), 0, "%s: each falls due inside heckle_span of the leg's beats" % where)
			check_eq(GameData.as_int(drive["early"]), 0, "%s: none is said before the car is at its place" % where)
			if GameData.as_int(drive["pressed"]) == 0:
				check(GameData.as_float(drive["late_m"]) < 1.0, "%s: the first is said as the car gets there (%.2f m past it)" % [where, GameData.as_float(drive["late_m"])])
			if leg_id != "tailgater":
				# (The Tailgater brakes in front of whoever will not make way:
				# that is his, not the Table's.)
				check_eq(GameData.as_int(drive["hits"]), 0, "%s: (the line the generator found meets nothing, heckles and all)" % where)
			if GameData.as_int(drive["pressed"]) > 0:
				pressed_legs += 1
			for type: Variant in GameData.as_array(drive["types"]):
				seen_types[type] = true
	check(pressed_legs >= 2, "(on %d of those legs an encounter was at him for a while)" % pressed_legs)
	check_eq(seen_types.size(), 6, "(all six types were said on the way: %s)" % ", ".join(PackedStringArray(seen_types.keys())))


## "Never during an encounter or a boss": crowding the Motorcade, its
## spotlight is on him almost all leg, and the Table keeps quiet for as long;
## what it could not say is not kept for the boss.
func _check_never_in_an_encounter() -> void:
	var crowded: Dictionary = _drive_a_leg("drivers", 3, "motorcade", 5, true)
	var leg_ticks: int = _ticks_in(GameData.as_float(data.record("legs", "motorcade").get("par_s")))
	check(GameData.as_int(crowded["pressed"]) > leg_ticks / 2, "(crowding the Motorcade, the spotlight is on him for %d s)" % roundi(float(GameData.as_int(crowded["pressed"])) * DT))
	check_eq(GameData.as_int(crowded["in_encounter"]), 0, "no heckle begins while the Motorcade's spotlight is on him")
	check(GameData.as_int(crowded["said"]) < 2, "so fewer than two are said on that leg (%d)" % GameData.as_int(crowded["said"]))
	check(not GameData.as_bool(crowded["open_at_end"]) or GameData.as_int(crowded["said"]) == 1, "(nothing is said of the ones that found no room)")
	# A Patrol that holds him up: nothing while its lights are in the mirror
	# or it is watching; the heckle that fell due then is said when it leaves.
	var watched: Dictionary = _drive_a_leg("uncles", 2, "patrol", 3)
	check(GameData.as_int(watched["pressed"]) > _ticks_in(20.0), "(the Patrol is at him for %d s)" % roundi(float(GameData.as_int(watched["pressed"])) * DT))
	check_eq(GameData.as_int(watched["in_encounter"]), 0, "no heckle begins while the Patrol is behind him")
	check_eq(GameData.as_int(watched["said"]), 2, "and both of Act 2's are said, before it and after")
	# One that falls due as the blue lights come on waits out the lights and
	# the watching, and is said as the Patrol leaves.
	var sprung: Dictionary = _drive_a_leg("uncles", 2, "patrol", 3, false, "doubt_all_night")
	check_eq(GameData.as_int(sprung["said"]), 1, "(a heckle due in the tick the Patrol's lights come on is said once)")
	check_eq(GameData.as_int(sprung["in_encounter"]), 0, "not under its lights, nor while it watches")
	check(GameData.as_int(sprung["pressed"]) > _ticks_in(20.0), "(it was at him for %d s)" % roundi(float(GameData.as_int(sprung["pressed"])) * DT))
	var waited: int = GameData.as_int(sprung["said_tick"]) - GameData.as_int(sprung["pressed_last"])
	check(waited >= 1 and waited <= 2, "but in the tick after it has left (%d)" % waited)
	# The Exit's stretch is the Exit's: a heckle due just before the slip
	# lane opens is said; one due in it is not.
	var exit_at: float = tuning.f("leg_length") - tuning.f("leg_tail")
	for past: bool in [false, true]:
		_quiet_leg_with("drivers", "dare_gear4")
		var late: Array[Dictionary] = [{"record": _heckle("dare_gear4"), "due_s": exit_at + (2.0 if past else -20.0), "roll": 0.0}]
		_sim.heckles.planned = late
		_sim.car.s = exit_at - 30.0
		var guard: int = _ticks_in(8.0)
		while _sim.run.stage == RunState.Stage.LEG and _sim.car.s < exit_at + 120.0 and guard > 0:
			guard -= 1
			_step()
		if past:
			check(_last("heckle_started").is_empty(), "a heckle due after the Exit's slip lane has opened is not said")
		else:
			check(not _last("heckle_started").is_empty(), "(a heckle due 20 m before the Exit is said)")
	# A boss: a whole night's bosses pass without a word from the Table.
	_tell("uncles", 9)
	var in_boss: int = 0
	var bosses: int = 0
	for act: int in range(1, RunGenerator.ACTS + 1):
		_drive_on_to_boss()
		bosses += 1
		_gather()
		_events = []
		_said = []
		_plan("doubt_all_night")
		var guard: int = _ticks_in(40.0)
		while _sim.run.stage == RunState.Stage.BOSS and not _sim.stopped and guard > 0:
			guard -= 1
			_sim.suspicion.value = 0.0
			_step()
		for event: Dictionary in _said:
			if GameData.as_string(event.get("type")) == "heckle_started":
				in_boss += 1
		if act < RunGenerator.ACTS:
			_drive_on_to_act(act + 1)
	check_eq(bosses, 3, "(three bosses, 40 s of each)")
	check_eq(in_boss, 0, "no heckle begins in a boss, though one is due")


# --- The lead ------------------------------------------------------------------------

## "The subtitle appears 2 s before anything changes. That lead is the tell."
func _check_the_lead() -> void:
	var lead: int = _lead_ticks()
	# A challenge: the line, its ding and the event in one tick; for two
	# seconds nothing counts; then the window opens.
	_quiet_leg_with("drivers", "dare_gear4")
	_sim.gate.reset(4)
	_step()
	var started: Dictionary = _last("heckle_started")
	check_eq(GameData.as_string(started.get("id")), "dare_gear4", "the heckle that is due is said")
	var line: Dictionary = _event("line_requested")
	check_eq(GameData.as_string(line.get("id")), GameData.as_string(_heckle("dare_gear4").get("line_id")), "its line is asked for in that tick")
	check(GameData.as_bool(line.get("tell")), "as a tell: it is on the screen at once (D-058)")
	check_eq(_count_events("sfx_requested", "id", "heckle"), 1, "with the soft ding of GDD 16.5")
	check_near(GameData.as_float(started.get("lead")), tuning.f("heckle_lead"), 0.000001, "(the event says the lead)")
	check_eq(GameData.as_string(_sim.snapshot()["heckle_phase"]), "lead", "the snapshot: a heckle is being said")
	_steps(lead - 1)
	check_eq(GameData.as_string(_sim.snapshot()["heckle_phase"]), "lead", "one tick short of 2 s: still only said")
	_step()
	check_eq(GameData.as_string(_sim.snapshot()["heckle_phase"]), "open", "2 s after the subtitle: the challenge is on")
	check_near(GameData.as_float(_sim.snapshot()["heckle_left"]), 15.0, 0.000001, "with its whole window ahead")
	# He was in fourth gear all through the lead: none of it counted.
	var resolved: Dictionary = _until_resolved(20.0)
	check_eq(GameData.as_string(resolved.get("outcome")), HeckleDirector.PASSED, "(held on, the Dare is met)")
	check_near(_took(), tuning.f("heckle_lead") + 10.0, DT * 0.5, "10 s after the lead was over, not 10 s after the subtitle")

	# A change on the road: the same two seconds.
	_quiet_leg_with("children", "fib_both_hands")
	_step()
	_steps(lead - 1)
	check(not _sim.heckles.ghost_holds, "the Fib, one tick short of 2 s: no ghost hand yet")
	_step()
	check(_sim.heckles.ghost_holds, "at 2 s it has the wheel")
	_quiet_leg_with("children", "guest_student_twist", PackedStringArray(["student"]))
	_step()
	_steps(lead - 1)
	check(not _sim.leg.raining, "the shower, one tick short of 2 s: dry")
	_step()
	check(_sim.leg.raining, "at 2 s it rains")
	# One at a time: the second of a leg waits for the first to be over.
	_quiet_leg_with("drivers", "dare_gear4")
	var both: Array[Dictionary] = [
		{"record": _heckle("dare_gear4"), "due_s": 0.0, "roll": 0.0},
		{"record": _heckle("dare_hands_off"), "due_s": 0.0, "roll": 0.0},
	]
	_sim.heckles.planned = both
	_grip()
	_gather()
	_until_resolved(20.0)
	var first_over: int = GameData.as_int(_last("heckle_resolved").get("tick"))
	var starts: PackedInt32Array = []
	_steps(4)
	for event: Dictionary in _said:
		if GameData.as_string(event.get("type")) == "heckle_started":
			starts.append(GameData.as_int(event.get("tick")))
	check_eq(starts.size(), 2, "(two were due at once: both are said)")
	if starts.size() == 2:
		check(starts[1] > first_over, "the second only after the first is over")


# --- Dare ------------------------------------------------------------------------------

func _check_dares() -> void:
	var lead: float = tuning.f("heckle_lead")
	# Fourth gear for 10 s.
	_quiet_leg_with("drivers", "dare_gear4")
	var cash: float = _sim.cash
	_hear_it_out()
	_sim.gate.reset(4)
	_steps(_ticks_in(10.0) - 1)
	check(_last("heckle_resolved").is_empty(), "fourth gear, one tick short of 10 s: not yet")
	check_near(_sim.cash, cash, 0.000001, "(no cash yet)")
	_step()
	_resolved_as(HeckleDirector.PASSED, "fourth gear held for 10 s: the Dare is met")
	check_near(_sim.cash - cash, 15.0, 0.000001, "+15 cash")
	check_near(GameData.as_float(_last("heckle_resolved").get("cash")), 15.0, 0.000001, "(the event says so)")
	check_eq(GameData.as_string(_sim.snapshot()["heckle_phase"]), "", "and the heckle is over")
	# Nine seconds, a change down, and fourth again: the 10 s are in one piece.
	_quiet_leg_with("drivers", "dare_gear4")
	cash = _sim.cash
	var nerves: float = _sim.nerves.value
	_hear_it_out()
	_sim.gate.reset(4)
	_steps(_ticks_in(9.0))
	_sim.gate.reset(3)
	_step()
	_sim.gate.reset(4)
	_until_resolved(20.0)
	_resolved_as(HeckleDirector.FAILED, "fourth gear in two pieces of 9 s and 5 s: the Dare is not met")
	check_near(_took(), lead + 15.0, DT * 0.5, "it is over when its 15 s window is")
	check_near(_sim.cash, cash, 0.000001, "no cash")
	check(absf(_sim.nerves.value - nerves) < 1.0, "and a Dare let go costs nothing: it is optional")

	# Three close calls.
	_quiet_leg_with("drivers", "dare_close_calls")
	_hear_it_out()
	_close_pass()
	_close_pass()
	check(_last("heckle_resolved").is_empty(), "two close calls: not yet")
	cash = _sim.cash
	_close_pass()
	_resolved_as(HeckleDirector.PASSED, "the third close call in the window: the Dare is met")
	check_near(GameData.as_float(_last("heckle_resolved").get("cash")), 20.0, 0.000001, "+20 cash")
	check(_sim.cash - cash >= 20.0, "(in his band, beside what the close call itself pays)")
	_quiet_leg_with("drivers", "dare_close_calls")
	_step()
	var said_at: int = GameData.as_int(_last("heckle_started").get("tick"))
	_close_pass(-4.0)
	check(_calls.size() == 1 and _calls[0] - said_at < _lead_ticks(), "(a close call during the lead)")
	_steps(_lead_ticks())
	_close_pass()
	_close_pass()
	check_eq(_calls.size(), 3, "(and two more in the window)")
	_until_resolved(20.0)
	_resolved_as(HeckleDirector.FAILED, "one close call before the window and two in it: not three")

	# Three seconds hands-off on a straight.
	_quiet_leg_with("drivers", "dare_hands_off")
	_grip()
	_gather()
	_steps(_lead_ticks() + _ticks_in(1.0))
	check(_last("heckle_resolved").is_empty(), "(his hand on the wheel: nothing)")
	_release()
	_gather()
	var let_go: int = _sim.tick
	cash = _sim.cash
	_until_resolved(20.0)
	_resolved_as(HeckleDirector.PASSED, "three seconds with no hand on the wheel: the Dare is met")
	check(absf(float(GameData.as_int(_last("heckle_resolved").get("tick")) - let_go) * DT - 3.0) < 0.2, "3 s after he let go")
	check_near(_sim.cash - cash, 10.0, 0.000001, "+10 cash")
	# On a bend it is not "on a straight".
	_quiet_leg_with("drivers", "dare_hands_off")
	var bent: Dictionary = _sim.leg.plan.duplicate(true)
	bent["curves"] = [{"s": 0.0, "length": GameData.as_float(bent.get("length")), "k": 0.6}]
	_sim.begin_leg(bent)
	_sim.in_encounter = true
	_plan("dare_hands_off")
	_hear_it_out()
	check(_sim.curve_k != 0.0 and not _sim.hand.gripping, "(hands off, in a bend)")
	_until_resolved(20.0)
	_resolved_as(HeckleDirector.FAILED, "hands-off in a bend does not count: \"on a straight\"")

	# Three vehicles in 10 s.
	_quiet_leg_with("drivers", "dare_pass_three")
	_hear_it_out()
	cash = _sim.cash
	_line_up([15.0, 30.0])
	_steps(_ticks_in(5.0))
	check(_last("heckle_resolved").is_empty(), "two vehicles passed: not yet")
	_line_up([15.0])
	_until_resolved(20.0)
	_resolved_as(HeckleDirector.PASSED, "a third within 10 s of the first: the Dare is met")
	check_near(_sim.cash - cash, 15.0, 0.000001, "+15 cash")
	_quiet_leg_with("drivers", "dare_pass_three")
	_hear_it_out()
	_line_up([15.0, 30.0, 150.0])
	_until_resolved(20.0)
	_resolved_as(HeckleDirector.FAILED, "three in the window, the third 12 s after the first: not three in 10 s")
	# Oncoming traffic is met, not passed.
	_quiet_leg_with("drivers", "dare_pass_three")
	_hear_it_out()
	for ahead: float in [200.0, 300.0, 400.0]:
		_sim.traffic.spawn(&"truck", 0, _sim.car.s + ahead, 60.0, -1)
	_until_resolved(20.0)
	_resolved_as(HeckleDirector.FAILED, "three oncoming vehicles are no vehicles passed")


# --- Doubt -----------------------------------------------------------------------------

func _check_the_doubt() -> void:
	var lead: float = tuning.f("heckle_lead")
	# Unanswered.
	_quiet_leg_with("uncles", "doubt_all_night")
	_hear_it_out()
	_steps(_ticks_in(15.0) - 1)
	check(_last("heckle_resolved").is_empty(), "a Doubt, one tick short of 15 s: nothing yet")
	var nerves: float = _sim.nerves.value
	_step()
	_resolved_as(HeckleDirector.FAILED, "unanswered for 15 s")
	check_near(_sim.nerves.value - nerves, 10.0, 0.05, "+10 Nerves")
	check_near(_took(), lead + 15.0, DT * 0.5, "(15 s after the lead)")
	# Answered with 5 s in fourth gear.
	_quiet_leg_with("uncles", "doubt_all_night")
	_hear_it_out()
	_steps(_ticks_in(3.0))
	_sim.gate.reset(4)
	_steps(_ticks_in(5.0) - 1)
	check(_last("heckle_resolved").is_empty(), "fourth gear, one tick short of 5 s: not yet")
	nerves = _sim.nerves.value
	_step()
	_resolved_as(HeckleDirector.PASSED, "5 s in fourth gear answer it")
	check_near(_sim.nerves.value - nerves, -10.0, 0.05, "-10 Nerves instead")
	nerves = _sim.nerves.value
	_steps(_ticks_in(10.0))
	check(_sim.nerves.value - nerves < 5.0, "and the +10 never comes")
	check_eq(_said.size(), 2, "(said once, resolved once)")
	# Answered with a close call.
	_quiet_leg_with("uncles", "doubt_one_hand")
	_hear_it_out()
	_close_pass()
	_resolved_as(HeckleDirector.PASSED, "a close call answers it")
	check_near(GameData.as_float(_last("heckle_resolved").get("nerves")), -10.0, 0.000001, "-10 Nerves")
	# Third gear is no answer.
	_quiet_leg_with("uncles", "doubt_all_night")
	_hear_it_out()
	_until_resolved(20.0)
	_resolved_as(HeckleDirector.FAILED, "15 s in third gear, passing nobody, do not")


# --- Question --------------------------------------------------------------------------

func _check_the_question() -> void:
	var lead: float = tuning.f("heckle_lead")
	_quiet_leg_with("inlaws", "question_calm")
	_sim.nerves.set_value(40.0)
	_hear_it_out()
	_steps(_ticks_in(15.0) - 1)
	check(_last("heckle_resolved").is_empty(), "a Question, one tick short of 15 s: nothing yet")
	var nerves: float = _sim.nerves.value
	var cash: float = _sim.cash
	check(nerves < 50.0, "(his Nerves stayed under 50: %.1f)" % nerves)
	_step()
	_resolved_as(HeckleDirector.PASSED, "Nerves under 50 and no horn for 15 s")
	check_near(_sim.nerves.value - nerves, -10.0, 0.05, "-10 Nerves")
	check_near(_sim.cash - cash, 10.0, 0.000001, "and +10 cash")
	check_near(_took(), lead + 15.0, DT * 0.5, "(15 s after the lead)")
	# The horn.
	_quiet_leg_with("inlaws", "question_calm")
	_hear_it_out()
	_steps(_ticks_in(4.0))
	nerves = _sim.nerves.value
	cash = _sim.cash
	_tap_at("horn")
	_gather()
	_resolved_as(HeckleDirector.FAILED, "the horn within the 15 s: it is lost at once")
	_steps(_ticks_in(15.0))
	check_near(_sim.cash, cash, 0.000001, "no cash")
	check(_sim.nerves.value - nerves > -5.0, "and no -10")
	check_eq(_said.size(), 2, "(and nothing more is said of it)")
	# Nerves at 50.
	_quiet_leg_with("inlaws", "question_horn")
	_hear_it_out()
	_steps(_ticks_in(4.0))
	check(_last("heckle_resolved").is_empty(), "(calm so far)")
	_sim.nerves.set_value(50.0)
	_step()
	_resolved_as(HeckleDirector.FAILED, "Nerves at 50: not under 50")
	# The horn during the lead is before the Question.
	_quiet_leg_with("inlaws", "question_calm")
	_step()
	_tap_at("horn")
	_gather()
	check_eq(GameData.as_string(_sim.snapshot()["heckle_phase"]), "lead", "(the horn while the Question is still being asked)")
	_until_resolved(20.0)
	_resolved_as(HeckleDirector.PASSED, "counts for nothing: the 15 s begin after the lead")


# --- Order -----------------------------------------------------------------------------

func _check_orders() -> void:
	var lead: float = tuning.f("heckle_lead")
	# Done.
	_quiet_leg_with("aunts", "order_tea")
	check(_sim.items.can_perform("tea_sip"), "(there is tea in the glass)")
	_hear_it_out()
	_steps(_ticks_in(2.0))
	var nerves: float = _sim.nerves.value
	_hold_at(_anchor_of("tea_glass"), GameData.as_float(_ritual("tea_sip").get("hold_s")) + 0.1)
	_gather()
	_resolved_as(HeckleDirector.PASSED, "\"Drink your tea\": a sip within 10 s")
	check_near(GameData.as_float(_last("heckle_resolved").get("nerves")), -8.0, 0.000001, "-8 Nerves")
	check(_sim.nerves.value < nerves - 8.0 + 1.0, "(beside what the tea itself does)")
	# Ignored.
	_quiet_leg_with("aunts", "order_tea")
	_hear_it_out()
	_steps(_ticks_in(10.0) - 1)
	check(_last("heckle_resolved").is_empty(), "an Order, one tick short of 10 s: nothing yet")
	nerves = _sim.nerves.value
	_step()
	_resolved_as(HeckleDirector.FAILED, "ignored for 10 s")
	check_near(_sim.nerves.value - nerves, 6.0, 0.05, "+6 Nerves")
	check_near(_took(), lead + 10.0, DT * 0.5, "(10 s after the lead)")
	# Another ritual is not the one named.
	_quiet_leg_with("aunts", "order_tea")
	_hear_it_out()
	_tap_at("horn")
	_gather()
	check(_last("heckle_resolved").is_empty(), "the horn is not what she asked for")
	_until_resolved(20.0)
	_resolved_as(HeckleDirector.FAILED, "(and the Order runs out)")
	# Too late is not done.
	_quiet_leg_with("aunts", "order_wipers")
	_hear_it_out()
	_until_resolved(20.0)
	_wipe()
	_gather()
	check_eq(_said.size(), 2, "the wipers after the 10 s change nothing")
	# What he cannot do is not asked of him: with an empty glass the Aunts
	# order something else that he can.
	_tell("aunts", 1)
	_into_next_quiet_leg()
	_item("tea_glass").supply = 0
	check(not _sim.items.can_perform("tea_sip"), "(the glass is empty)")
	_sim.heckles.plan_leg(_sim.rng, _sim.table, PackedStringArray(), 1, QUIET, "")
	_plan("order_tea")
	_events = []
	_said = []
	_step()
	var instead: Dictionary = _heckle(GameData.as_string(_last("heckle_started").get("id")))
	check_eq(GameData.as_string(instead.get("type")), "ORDER", "with an empty glass another Order is given")
	check(GameData.as_string(instead.get("ritual")) != "tea_sip" and _sim.items.can_perform(GameData.as_string(instead.get("ritual"))),
			"one he can obey: %s" % GameData.as_string(instead.get("ritual")))
	check_eq(GameData.as_string(_event("line_requested").get("id")), GameData.as_string(instead.get("line_id")), "and it is that one's line that is said")


# --- The Fib ---------------------------------------------------------------------------

## How far the car is from the middle of the middle lane.
func _off_centre() -> float:
	return absf(_sim.car.x - _sim.car.lane_center(1))


func _check_the_fib() -> void:
	# A bend, hands off: without the Fib the car leaves its lane; with it the
	# ghost of his left hand holds the lane for 5 s, and then lets go.
	var drift: Array[float] = []
	for fibbed: bool in [false, true]:
		_quiet_leg_with("children", "fib_both_hands")
		var bent: Dictionary = _sim.leg.plan.duplicate(true)
		bent["curves"] = [{"s": 0.0, "length": GameData.as_float(bent.get("length")), "k": 0.6}]
		_sim.begin_leg(bent)
		_sim.in_encounter = true
		if fibbed:
			_plan("fib_both_hands")
		else:
			_sim.heckles.end_leg()
		_hear_it_out() if fibbed else _steps(_lead_ticks() + 1)
		_keep_lane = false
		_sim.car.x = _sim.car.lane_center(1)
		var worst: float = 0.0
		var held: int = 0
		for _index: int in _ticks_in(5.0) - 1:
			_step()
			worst = maxf(worst, _off_centre())
			if GameData.as_bool(_sim.snapshot()["ghost_on_wheel"]):
				held += 1
		drift.append(worst)
		if fibbed:
			check_eq(held, _ticks_in(5.0) - 1, "the Fib: a ghost left hand is on the wheel, for the snapshot too")
			check(_last("heckle_resolved").is_empty(), "one tick short of 5 s it still holds")
			_step()
			_resolved_as(HeckleDirector.OVER, "after 5 s it is over")
			check(not _sim.heckles.ghost_holds and not GameData.as_bool(_sim.snapshot()["ghost_on_wheel"]), "and the ghost hand is gone")
			var after: float = _off_centre()
			_steps(_ticks_in(3.0))
			check(_off_centre() > after + 0.5, "(let go, the bend carries the car off again)")
		_keep_lane = true
	check(drift[0] > _sim.car.lane_width() * 0.5, "(hands off in a bend for 5 s, the car leaves its lane: %.2f m off)" % drift[0])
	check(drift[1] < 0.5, "with the ghost hand it holds the lane through the bend (%.2f m off at most)" % drift[1])
	# His own hand on the wheel is his own: the ghost holds only what he lets go.
	_quiet_leg_with("children", "fib_both_hands")
	_grip()
	_gather()
	_steps(_lead_ticks() + 2)
	check(_sim.heckles.ghost_holds, "(the Fib is on)")
	check(not _sim.ghost_on_wheel() and not _sim.wheel.locked, "while he grips the wheel it is his")
	_release()
	_gather()
	check(_sim.ghost_on_wheel() and _sim.wheel.locked, "let go within the 5 s, the ghost has it")


# --- Twists ----------------------------------------------------------------------------

## What of a Twist is on the road: sheep, melons, wedding cars, the truck.
func _twist_things(modifier: String) -> int:
	var count: int = 0
	for hazard: LegSim.Hazard in _sim.leg.movers:
		if hazard.kind == &"sheep" or hazard.kind == &"melon":
			count += 1
	var role: StringName = StringName(GameData.as_string(LegGenerator.TWIST_ROLES.get(modifier)))
	for vehicle: TrafficSim.Vehicle in _sim.traffic.vehicles:
		if role != &"" and vehicle.role == role:
			count += 1
	return count


func _check_twists() -> void:
	var lead: int = _lead_ticks()
	var top_ms: float = tuning.fi("gear_speeds", 4) * KMH_TO_MS
	for heckle_id: String in ["twist_sheep", "twist_melons", "guest_drummer_twist"]:
		var modifier: String = GameData.as_string(_heckle(heckle_id).get("twist"))
		# The generator lays the Twist out with every rule of GDD 9.2 kept.
		var problems: int = 0
		var with_twist: int = 0
		for leg_seed: int in range(1, 13):
			var plan: Dictionary = LegGenerator.generate(data, QUIET, 1, leg_seed, "", {"modifier": modifier, "at": 0.5})
			if plan.has("twist"):
				with_twist += 1
			problems += _checker.check(plan).size()
		check_eq(with_twist, 12, "%s: twelve legs are laid out with the Twist's stretch" % modifier)
		check_eq(problems, 0, "%s: and each keeps every rule of the generator" % modifier)
		check(not LegGenerator.generate(data, QUIET, 1, 1, "").has("twist"), "(a leg with no Twist says nothing of one)") if heckle_id == "twist_sheep" else true

		# Driven on the generator's line: before the heckle and through its
		# lead nothing of the Twist is on the road; then it is, and he meets
		# it; when its stretch is behind him the heckle is over.
		var guests: PackedStringArray = ["drummer"] if heckle_id.begins_with("guest_") else PackedStringArray()
		for telling: String in ["heard", "late", "unsaid"]:
			var heard: bool = telling != "unsaid"
			_tell("children", 1, guests)
			_into_next_quiet_leg()
			var plan: Dictionary = LegGenerator.generate(data, QUIET, 1, 3, "", {"modifier": modifier, "at": 0.5})
			var twist: Dictionary = GameData.as_dict(plan.get("twist"))
			_sim.gate.reset(3)
			_sim.begin_leg(plan)
			_sim.in_encounter = true
			_sim.heckles.end_leg()
			if heard:
				var planned: Array[Dictionary] = [{"record": _heckle(heckle_id), "share": 0.3, "roll": 0.0, "stretch": true}]
				_sim.heckles.planned = planned
				_sim.heckles.begin_leg(plan)
				check_near(GameData.as_float(_sim.heckles.planned[0]["due_s"]), maxf(GameData.as_float(twist.get("first_s")) - tuning.f("heckle_lead") * top_ms, 0.0), 0.01,
						"%s: it falls due 2 s at top speed before the first of it would show" % modifier)
			_checker.load_plan(plan)
			_events = []
			_said = []
			_keep_lane = false
			# Told late: the Table cannot get a word in until the car is well
			# past the point where the first of the Twist would have shown.
			var first_s: float = GameData.as_float(twist.get("first_s"))
			_sim.heckling = telling != "late"
			var before: int = 0
			var in_lead: int = 0
			var after: int = 0
			var hits: int = 0
			var said_at: int = -1
			var live_at: int = -1
			var end_s: float = GameData.as_float(twist.get("end_s"))
			var guard: int = _ticks_in(90.0)
			while _sim.car.s < end_s + 200.0 and guard > 0:
				guard -= 1
				_sim.car.x = _checker.line_x(_sim.car.s)
				if telling == "late" and _sim.car.s > first_s + 40.0:
					_sim.heckling = true
				_step()
				hits += _count_events("hit")
				_events = []
				if said_at < 0 and not _last("heckle_started").is_empty():
					said_at = _sim.tick
				if live_at < 0 and _sim.leg.twist_live:
					live_at = _sim.tick
				var things: int = _twist_things(modifier)
				if said_at < 0:
					before = maxi(before, things)
				elif _sim.tick - said_at < lead:
					in_lead = maxi(in_lead, things)
				else:
					after = maxi(after, things)
			_keep_lane = true
			if telling == "late":
				check(said_at > 0 and GameData.as_float(_last("heckle_started").get("tick")) > 0.0, "%s, said late: it is said when the Table can" % modifier)
				check_eq(before + in_lead, 0, "%s, said late: still nothing of it before the subtitle and its 2 s" % modifier)
				check_eq(live_at - said_at, lead, "%s, said late: then it comes onto the road" % modifier)
				check(after > 0, "%s, said late: with what the plan has there by now, though its moment has passed (%d things)" % [modifier, after])
				check_eq(hits, 0, "%s, said late: (and where the plan has it: the line still meets none of it)" % modifier)
			elif heard:
				check(said_at > 0, "%s: the heckle is said on the way" % modifier)
				check_eq(before, 0, "%s: before it is said nothing of it is on the road" % modifier)
				check_eq(in_lead, 0, "%s: nor for the 2 s after the subtitle" % modifier)
				check_eq(live_at - said_at, lead, "%s: at 2 s it comes onto the road" % modifier)
				check(after > 0, "%s: and he meets it (%d things at once)" % [modifier, after])
				check_eq(hits, 0, "%s: (on the line the generator found he touches none of it)" % modifier)
				_resolved_as(HeckleDirector.OVER, "%s: its stretch behind him, the heckle is over" % modifier)
			else:
				check_eq(before + in_lead + after, 0, "%s: on the same leg with nobody to say it, none of it ever is" % modifier)
				check(not _sim.leg.twist_live, "(the stretch stays as the story had it before: empty)")


## A leg with a stretch of its own (its modifier's) takes a Twist's beside
## it, a CALM beat's length apart; never the same thing twice, and never one
## on top of the other.
func _check_twists_beside_a_modifier() -> void:
	var calm: float = tuning.f("calm_length")
	_tell("children", 1)
	for own: String in ["sheep", "melon_truck"]:
		var asked: int = 0
		var laid: int = 0
		var same: int = 0
		var too_near: int = 0
		var problems: int = 0
		for leg_seed: int in range(1, 41):
			var twist: Dictionary = _sim.heckles.plan_leg(_sim.rng, _sim.table, PackedStringArray(), 2, QUIET, own)
			if twist.is_empty():
				continue
			asked += 1
			if GameData.as_string(twist.get("modifier")) == own:
				same += 1
			var plan: Dictionary = LegGenerator.generate(data, QUIET, 2, leg_seed, own, twist)
			if not plan.has("twist"):
				continue
			laid += 1
			problems += _checker.check(plan).size()
			var zones: Array = GameData.as_array(plan.get("zones"))
			if zones.size() == 2:
				var first: Dictionary = zones[0] if GameData.as_float(GameData.as_dict(zones[0]).get("s")) < GameData.as_float(GameData.as_dict(zones[1]).get("s")) else zones[1]
				var second: Dictionary = zones[1] if first == zones[0] else zones[0]
				if GameData.as_float(second.get("s")) - (GameData.as_float(first.get("s")) + GameData.as_float(first.get("length"))) < calm - 0.001:
					too_near += 1
			else:
				too_near += 1
		check(asked > 5, "a leg with %s of its own, told to the Children: a Twist is thrown in on %d of 40" % [own, asked])
		check_eq(same, 0, "%s: never the same thing again" % own)
		check_eq(laid, asked, "%s: each is laid out beside the leg's own stretch" % own)
		check_eq(too_near, 0, "%s: a CALM beat's length away from it, at the least" % own)
		check_eq(problems, 0, "%s: with every rule of the generator kept" % own)
	# Asked for on top of the leg's own stretch, the Twist is left out: the
	# leg stands as it would without it.
	var wedding_at: float = GameData.as_float(data.record("modifiers", "wedding").get("at"))
	var on_top: int = 0
	var broken: int = 0
	for leg_seed: int in range(1, 13):
		var plan: Dictionary = LegGenerator.generate(data, QUIET, 2, leg_seed, "wedding", {"modifier": "sheep", "at": wedding_at})
		if plan.has("twist"):
			on_top += 1
		broken += _checker.check(plan).size()
	check_eq(on_top, 0, "a Twist asked for where the leg's own stretch lies is left out of the leg")
	check_eq(broken, 0, "(and the leg is a good leg without it)")


func _check_the_shower() -> void:
	var guests: PackedStringArray = ["student"]
	_quiet_leg_with("drivers", "guest_student_twist", guests)
	check(not _sim.leg.raining and not GameData.as_bool(_sim.snapshot()["raining"]), "(a dry leg)")
	var response: float = _sim.car.lat_tau_mult
	_hear_it_out()
	check(_sim.leg.raining and GameData.as_bool(_sim.snapshot()["raining"]), "the shower: it rains")
	check(_sim.items.raining, "on the glass")
	check_near(_sim.car.lat_tau_mult, tuning.f("rain_response_mult"), 0.000001, "and on the road: the car answers as in the rain")
	_steps(_ticks_in(20.0) - 1)
	check(_sim.leg.raining and _last("heckle_resolved").is_empty(), "one tick short of 20 s it still rains")
	_step()
	check(not _sim.leg.raining and not _sim.items.raining, "after 20 s it is dry again")
	check_near(_sim.car.lat_tau_mult, response, 0.000001, "and the car answers as before")
	_resolved_as(HeckleDirector.OVER, "and the heckle is over")
	# Where it rains already nobody adds a shower; and one Twist's stretch
	# to a leg.
	_tell("children", 1, guests)
	var showers: int = 0
	var stretches_most: int = 0
	for leg_seed: int in 200:
		_sim.heckles.plan_leg(_sim.rng, _sim.table, guests, 2, "rain", "")
		var stretches: int = 0
		for entry: Dictionary in _sim.heckles.planned:
			var record: Dictionary = entry["record"]
			if GameData.as_string(record.get("twist")) == HeckleDirector.SHOWER:
				showers += 1
			elif GameData.as_string(record.get("type")) == "TWIST":
				stretches += 1
		stretches_most = maxi(stretches_most, stretches)
	check_eq(showers, 0, "on 200 Rain legs told with the Student at the Table, no shower is thrown in")
	check_eq(stretches_most, 1, "and never two stretches on one leg")
	var on_patrol: int = 0
	for leg_seed: int in 200:
		if not _sim.heckles.plan_leg(_sim.rng, _sim.table, guests, 2, "patrol", "").is_empty():
			on_patrol += 1
	check_eq(on_patrol, 0, "a leg that takes no sheep or melons as a modifier takes none as a Twist")


## The words of a record: what the director understands, and what it refuses.
func _check_the_words() -> void:
	check_eq(HeckleDirector.parse_answer("close_call"), {"kind": "close_call", "count": 1}, "\"close_call\": one close call")
	check_eq(HeckleDirector.parse_answer("close_call_x3"), {"kind": "close_call", "count": 3}, "\"close_call_x3\": three")
	check_eq(HeckleDirector.parse_answer("gear4_5s"), {"kind": "gear", "gear": 4, "seconds": 5.0}, "\"gear4_5s\": fourth gear for 5 s")
	check_eq(HeckleDirector.parse_answer("hands_off_3s"), {"kind": "hands_off", "seconds": 3.0}, "\"hands_off_3s\"")
	check_eq(HeckleDirector.parse_answer("pass_x3_10s"), {"kind": "pass", "count": 3, "seconds": 10.0}, "\"pass_x3_10s\": three within 10 s")
	for wrong: String in ["", "gear4", "gear_5s", "close_call_5s", "hands_off", "pass_x3", "wave_x2", "close_calls"]:
		check(HeckleDirector.parse_answer(wrong).is_empty(), "\"%s\" is no answer" % wrong)
	check_eq(HeckleDirector.parse_keep("nerves_under_50"), {"kind": "nerves_under", "value": 50.0}, "\"nerves_under_50\"")
	check_eq(HeckleDirector.parse_keep("no_horn"), {"kind": "no_horn"}, "\"no_horn\"")
	for wrong: String in ["", "nerves_under", "nerves_over_50", "horn"]:
		check(HeckleDirector.parse_keep(wrong).is_empty(), "\"%s\" is nothing to keep" % wrong)
