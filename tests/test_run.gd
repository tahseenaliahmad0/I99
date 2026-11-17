extends TestSuite
## M5: a whole Telling (GDD 9.5, 9.6, 11.1) and the Clock (GDD 6.4).

const DT: float = DriveSim.DT
const KMH_TO_MS: float = 1.0 / 3.6

## What the scripted driver does at an Exit.
const STOP: String = "stop"
const SKIP: String = "skip"

var _sim: DriveSim
var _input: DriveInput
var _events: Array[Dictionary] = []
var _checker: LegChecker
## The plan the checker's line was loaded from.
var _lined_plan: Dictionary = {}
## The scripted driver: the side taken at each fork and what he does at each
## Exit, in order; and how many of each he has met.
var _sides: Array[int] = []
var _exits: Array[String] = []
var _forks_met: int = 0
var _legs_met: int = 0
var _was_stage: int = RunState.Stage.NONE
## Legs (by number) whose passed Exit has been checked.
var _missed_checked: Dictionary = {}


func before_each() -> void:
	_sim = DriveSim.new(fresh_data())
	_input = DriveInput.new()
	_events = []
	_checker = LegChecker.new(data)
	_lined_plan = {}
	_sides = []
	_exits = []
	_forks_met = 0
	_legs_met = 0
	_was_stage = RunState.Stage.NONE
	_missed_checked = {}


## T-RUN-01: A Telling follows 11.1: Fork, Leg, Exit and Stop three times,
## then Boss and Boss stop, for three acts, then Arrival; the fork branch is
## decided by which side of the gore point the car is on; there is no fork
## after an act's third leg; an Exit needs the slip lane and exit_max_speed
## or less at 2,330 m, and a missed Exit adds 5 Nerves.
func test_run_01() -> void:
	var exit_at: float = tuning.f("leg_length") - tuning.f("leg_tail")
	var stall_at: float = exit_at + tuning.f("exit_slip_length")
	var third: float = tuning.fi("gear_speeds", 2)
	check_near(exit_at, 2200.0, 0.000001, "GDD 9.5: the Exit's slip lane opens at 2,200 m")
	check_near(stall_at, 2330.0, 0.000001, "and the stall is at 2,330 m")
	check_near(tuning.f("exit_max_speed"), 70.0, 0.000001, "to stop he must be at 70 km/h or less")
	check_near(tuning.f("missed_exit_nerves"), 5.0, 0.000001, "a missed Exit is +5 Nerves")
	check_near(tuning.f("slip_sign_lead"), 5.0, 0.000001, "the Exit is signed 5 s ahead")
	check_eq(RunGenerator.ACTS, 3, "GDD 11.1: three acts")
	check_eq(RunGenerator.LEGS_PER_ACT, 3, "of three legs")

	# A whole Telling: he stops at seven of the nine Exits, passes two, and
	# takes the left and the right branch in turn.
	var telling_seed: int = 4242
	_sides = [RunState.LEFT, RunState.RIGHT, RunState.RIGHT, RunState.LEFT, RunState.LEFT, RunState.RIGHT, RunState.LEFT, RunState.RIGHT, RunState.RIGHT]
	_exits = [STOP, SKIP, STOP, STOP, STOP, SKIP, STOP, STOP, STOP]
	_sim.begin_telling("drivers", telling_seed)
	check(_sim.run.active, "a Telling is under way")
	check_eq(_sim.run.stage, RunState.Stage.APPROACH, "it begins on the road to the first fork")
	check_eq(_sim.run.act, 1, "in Act 1")
	check_eq(_sim.gate.gear, tuning.i("start_gear"), "rolling in first gear")
	check_near(_sim.car.speed, tuning.fi("gear_speeds", 0), 0.000001, "at first gear's speed")
	check(not _sim.hand.gripping, "with nobody at the wheel (GDD 10.1)")
	check_eq(_sim.clock.text(), tuning.s("clock_start"), "at 22:00")
	check_eq(_sim.faults.lamps, 0, "no lamp lit")
	check_near(_sim.cash, tuning.f("cash_start"), 0.000001, "and cash_start in the band")

	var stages: PackedStringArray = []
	var driving_seconds: float = 0.0
	var stop_minutes: float = 0.0
	var forks_seen_signed: int = 0
	var exits_seen_signed: int = 0
	var signs_at_third_leg_tail: int = 0
	var slip_lanes: int = 0
	var slip_checked: int = 0
	var looked: Dictionary = {}
	var guard: int = int(1500.0 / DT)
	while _sim.run.active and guard > 0:
		guard -= 1
		var stage: int = _sim.run.stage
		var stood: bool = _sim.stopped
		var nerves_before: float = _sim.nerves.value
		_script_tick()
		_sim.step(_input)
		for event: Dictionary in _sim.drain_events():
			_events.append(event)
			var type: String = GameData.as_string(event.get("type"))
			if type in ["fork_taken", "leg_started", "leg_ended", "stop_entered", "stop_left", "boss_started", "boss_ended", "arrived"]:
				stages.append(type)
			if type == "stop_entered":
				stop_minutes += GameData.as_float(event.get("minutes"))
		if not stood and not _sim.stopped:
			driving_seconds += DT
		# What the road shows on the way: looked at once on each leg, 200 m
		# short of the Exit, beside its slip lane, and past the stall.
		if stage == RunState.Stage.LEG and not _sim.stopped:
			var s: float = _sim.car.s
			if s >= exit_at - 200.0 and not looked.has([_legs_met, 0]):
				looked[[_legs_met, 0]] = true
				if _has_sign("exit"):
					exits_seen_signed += 1
			if s >= exit_at + 60.0 and not looked.has([_legs_met, 1]):
				looked[[_legs_met, 1]] = true
				slip_checked += 1
				if _sim.car.lanes == GameData.as_int(_sim.leg.plan["lanes"]) + 1 and GameData.as_bool(_sim.snapshot()["slip_open"]):
					slip_lanes += 1
			if s >= stall_at + 20.0 and not looked.has([_legs_met, 2]):
				looked[[_legs_met, 2]] = true
				if _has_sign("fork"):
					forks_seen_signed += 1
					if _sim.run.legs_done == RunGenerator.LEGS_PER_ACT - 1:
						signs_at_third_leg_tail += 1
		# A passed Exit costs him: +5 Nerves on the tick he passes the stall.
		if stage == RunState.Stage.LEG and _legs_met > 0 and _exits[_legs_met - 1] == SKIP \
				and not _missed_checked.has(_legs_met) and _sim.car.s >= stall_at:
			_missed_checked[_legs_met] = true
			check_near(_sim.nerves.value - nerves_before, tuning.f("missed_exit_nerves"), 0.05,
					"leg %d: passing the stall in his lane at par is a missed Exit: +5 Nerves (%s)" % [_legs_met, str(snappedf(_sim.nerves.value - nerves_before, 0.001))])
	check(guard > 0, "the Telling comes to an end (%s)" % _sim.run.stage_name())

	# The order of GDD 11.1.
	var expected: PackedStringArray = []
	for act: int in RunGenerator.ACTS:
		for leg_index: int in RunGenerator.LEGS_PER_ACT:
			expected.append("fork_taken")
			expected.append("leg_started")
			if _exits[act * RunGenerator.LEGS_PER_ACT + leg_index] == STOP:
				expected.append("stop_entered")
				expected.append("stop_left")
			expected.append("leg_ended")
		expected.append_array(PackedStringArray(["boss_started", "boss_ended", "stop_entered", "stop_left"]))
	expected.append("arrived")
	check_eq(stages, expected, "Fork, Leg, Exit and Stop three times, then Boss and Boss stop, for three acts, then Arrival")
	check_eq(_sim.run.stage, RunState.Stage.ENDED, "after the Arrival the Telling is over")

	# Forks: the branch is the side of the gore the car is on.
	var forks: Array[Dictionary] = _events_named("fork_taken")
	var started: Array[Dictionary] = _events_named("leg_started")
	check_eq(forks.size(), 9, "nine forks: one before each leg")
	var sides_taken: Dictionary = {}
	for index: int in mini(forks.size(), 9):
		var act: int = index / RunGenerator.LEGS_PER_ACT + 1
		var leg_index: int = index % RunGenerator.LEGS_PER_ACT
		var branches: Array[Dictionary] = RunGenerator.fork(data, telling_seed, act, leg_index)
		var side: int = _sides[index]
		sides_taken[side] = true
		var fork: Dictionary = forks[index]
		check_eq(GameData.as_int(fork.get("side")), side, "fork %d: the car was on the %s of the gore" % [index + 1, "left" if side == RunState.LEFT else "right"])
		check_eq(GameData.as_int(fork.get("act")), act, "fork %d is in act %d" % [index + 1, act])
		check_eq(GameData.as_int(fork.get("leg_index")), leg_index, "before its leg %d" % (leg_index + 1))
		check_eq(GameData.as_string(fork.get("leg")), GameData.as_string(branches[side]["leg"]), "and took that side's branch (%s, not %s)" % [str(branches[side]["leg"]), str(branches[1 - side]["leg"])])
		check_eq(GameData.as_string(fork.get("modifier")), GameData.as_string(branches[side]["modifier"]), "with its modifier")
		check_eq(GameData.as_string(fork.get("stop")), GameData.as_string(branches[side]["stop"]), "and its stop")
		check(GameData.as_string(branches[0]["leg"]) != GameData.as_string(branches[1]["leg"]), "the two branches are different legs")
		if index < started.size():
			check_eq(GameData.as_string(started[index].get("leg")), GameData.as_string(branches[side]["leg"]), "which is the leg that then starts")
			check_eq(GameData.as_int(started[index].get("act")), act, "in its act")
	check_eq(sides_taken.size(), 2, "both sides were taken on the way")
	check_eq(forks_seen_signed, 6, "the fork ahead is signed in the last metres of the first two legs of each act")
	check_eq(signs_at_third_leg_tail, 0, "there is no fork after an act's third leg: the road leads into the boss")
	check_eq(exits_seen_signed, 9, "every leg's Exit is signed before its slip lane opens")
	check_eq(slip_checked, 9, "(every leg's Exit was looked at)")
	check_eq(slip_lanes, 9, "beside the slip lane the road is one lane wider")

	# Stops: at the stall in the slip lane at 70 km/h or less.
	var stops: Array[Dictionary] = _events_named("stop_entered")
	check_eq(stops.size(), 7 + RunGenerator.ACTS, "he stopped at the seven Exits he took and after each boss")
	var entered: int = 0
	for index: int in 9:
		if _exits[index] != STOP:
			continue
		var stop: Dictionary = stops[entered + index / RunGenerator.LEGS_PER_ACT]
		entered += 1
		var wanted: String = GameData.as_string(forks[index].get("stop"))
		check_eq(GameData.as_string(stop.get("stop")), wanted, "leg %d ends at the stop its branch named (%s)" % [index + 1, wanted])
		check_near(GameData.as_float(stop.get("minutes")), GameData.as_float(data.record("stops", wanted).get("clock_min")), 0.000001, "which charges its Clock minutes on entry")
	check_eq(_missed_checked.size(), 2, "(both passed Exits were looked at)")

	# Bosses: one at the end of each act, then its stop, then the next act.
	var bosses: Array[Dictionary] = _events_named("boss_started")
	check_eq(bosses.size(), 3, "three bosses")
	for index: int in mini(bosses.size(), 3):
		check_eq(GameData.as_string(bosses[index].get("boss")), GameData.as_string(RunGenerator.boss_of(data, index + 1).get("id")), "act %d ends in its boss" % (index + 1))
		check_eq(GameData.as_int(bosses[index].get("act")), index + 1, "in act %d" % (index + 1))

	# The Arrival reads the Clock: what he drove, at 20 game seconds a second, and what his stops cost.
	var arrived: Dictionary = _event("arrived")
	check_eq(GameData.as_string(arrived.get("table")), "drivers", "he arrives, at the Table he started from")
	var clock_expected: float = driving_seconds * tuning.f("clock_scale") / 60.0 + stop_minutes
	check_near(GameData.as_float(arrived.get("clock_minutes")), clock_expected, 0.05, "the Clock at the Arrival is his driving and his stops (%s min)" % str(snappedf(clock_expected, 0.1)))
	check_eq(GameData.as_bool(arrived.get("late")), clock_expected > 480.0, "and says whether he is late")
	check_eq(_sim.faults.lamps, 0, "(the scripted driver lit no lamp)")
	note("%d s of driving, %s game minutes of stops, parked at %s" % [roundi(driving_seconds), str(stop_minutes), GameData.as_string(arrived.get("clock"))])

	_check_exit_cases(exit_at, stall_at, third)
	_check_gore_line()


## T-CLOCK-01: 90 real seconds of driving is 30 game minutes.
func test_clock_01() -> void:
	var scale: float = tuning.f("clock_scale")
	check_near(scale, 20.0, 0.000001, "GDD 6.4: one real second of driving is 20 game seconds")
	check_eq(tuning.s("clock_start"), "22:00", "the night starts at 22:00")
	check_eq(tuning.s("clock_deadline"), "06:00", "and ends at 06:00")

	# Driving.
	_sim.gate.reset(3)
	_sim.car.reset(1, 3)
	check_near(_sim.clock.minutes, 0.0, 0.000001, "a Telling starts at clock_start")
	check_eq(_sim.clock.text(), "22:00", "which the dashboard clock shows")
	var lane_x: float = _sim.car.x
	for _tick: int in int(90.0 / DT):
		_sim.car.x = lane_x
		_sim.step(_input)
	check_near(_sim.clock.minutes, 30.0, scale * DT / 60.0, "90 real seconds of driving is 30 game minutes (%s)" % str(snappedf(_sim.clock.minutes, 0.001)))
	check_eq(_sim.clock.text(), "22:30", "the clock shows 22:30")
	check_near(GameData.as_float(_sim.snapshot()["clock_minutes"]), _sim.clock.minutes, 0.000001, "and the snapshot carries it")
	check_eq(GameData.as_string(_sim.snapshot()["clock"]), "22:30", "as minutes and as text")

	# A par leg: 30 game minutes, whatever the leg.
	_sim = DriveSim.new(fresh_data())
	var plan: Dictionary = LegGenerator.generate(data, "open_road", 1, 5, "")
	plan["spawns"] = []
	plan["hazards"] = []
	plan["curves"] = []
	plan["gusts"] = []
	_sim.gate.reset(3)
	_sim.begin_leg(plan)
	lane_x = _sim.car.x
	while _sim.leg.active:
		_sim.car.x = lane_x
		_sim.step(_input)
	check_near(_sim.leg.time, tuning.f("leg_length") / (tuning.fi("gear_speeds", 2) * KMH_TO_MS), 0.02, "(a leg in third gear takes 90 s)")
	check_near(_sim.clock.minutes, _sim.leg.time * scale / 60.0, 0.01, "a par leg of 90 s takes 30 game minutes")

	# The clock itself: minutes charged at once, the deadline, the day turning.
	var clock: ClockSim = ClockSim.new()
	clock.configure(tuning)
	check_near(clock.night_minutes(), 480.0, 0.000001, "the night is eight hours long")
	clock.add_minutes(GameData.as_float(tuning.d("stop_minutes").get("tea")))
	check_near(clock.minutes, 20.0, 0.000001, "a stop charges its game minutes at once")
	check_eq(clock.text(), "22:20", "22:20")
	clock.add_minutes(-5.0)
	check_near(clock.minutes, 20.0, 0.000001, "the Clock never runs backwards")
	clock.add_minutes(100.0)
	check_eq(clock.text(), "00:00", "it turns midnight")
	check_near(clock.time_of_day(), 0.0, 0.000001, "as minutes after midnight too")
	clock.add_minutes(359.0)
	check_eq(clock.text(), "05:59", "05:59")
	check(not clock.late(), "before 06:00 he is on time")
	check_near(clock.minutes_left(), 1.0, 0.000001, "with a minute to spare")
	clock.add_minutes(1.0)
	check_eq(clock.text(), "06:00", "06:00")
	check(not clock.late(), "parked by 06:00 is on time (GDD 11.4)")
	check_near(clock.night_share(), 1.0, 0.000001, "the night is over")
	clock.step(DT)
	check(clock.late(), "a moment after 06:00 he is Late")
	check(clock.minutes_left() < 0.0, "with nothing left")
	clock.reset()
	check_near(clock.minutes, 0.0, 0.000001, "a new Telling starts at 22:00 again")
	check_near(ClockSim.minutes_of("06:00"), 360.0, 0.000001, "(06:00 is 360 minutes after midnight)")

	# Standing still costs nothing: the Clock is the price of stopping, charged by the stop.
	_sim = DriveSim.new(fresh_data())
	plan = LegGenerator.generate(data, "patrol", 2, 71, "")
	_sim.gate.reset(3)
	_sim.begin_leg(plan)
	_sim.pulled_over = true
	var before: float = _sim.clock.minutes
	for _tick: int in int(5.0 / DT):
		_sim.step(_input)
	check_near(_sim.clock.minutes, before, 0.000001, "while he stands with the officer the Clock does not run")


## T-RUN-02: Wreck and restart: when every lamp is lit the Telling ends in a
## Wreck; the Telling restarts from Baghdad with the starting cabin, wheel in
## hand within wreck_to_wheel.
func test_run_02() -> void:
	var cut: float = tuning.f("wreck_to_wheel")
	var capacity: int = tuning.i("lamp_capacity")
	check_near(cut, 3.0, 0.000001, "GDD 11.4: after a Wreck the Telling restarts in 3 s")
	check_eq(capacity, 5, "GDD 6.3: five lamps")

	for telling: int in 2:
		if telling == 0:
			_begin_quiet_leg()
		else:
			# The Telling that followed the first Wreck, driven on by itself into its first leg.
			_input.clear()
			var roll: int = int(60.0 / DT)
			while _sim.run.stage == RunState.Stage.APPROACH and roll > 0:
				roll -= 1
				_sim.step(_input)
			check_eq(_sim.run.stage, RunState.Stage.LEG, "the Telling told again is a Telling like any other: it rolls through its first fork")
			_sim.gate.reset(3)
		var first_seed: int = _sim.run.seed
		var retellings: int = _sim.run.retellings
		# He has made the night his own: an item, less cash, a later hour, frayed Nerves.
		_sim.items.add_item(&"beads", &"mirror")
		_sim.cash = 3.0
		_sim.clock.add_minutes(120.0)
		_events = []

		# Lamp by lamp, along the guardrail.
		for lamp: int in capacity - 1:
			_scrape()
		check_eq(_sim.faults.lamps, capacity - 1, "four lamps are lit")
		check(not _sim.wrecked and not _has_event("wreck"), "four lit lamps are not a Wreck")
		check_eq(_sim.run.stage, RunState.Stage.LEG, "the leg goes on")
		var guard: int = int(5.0 / DT)
		_input.clear()
		while not _sim.wrecked and guard > 0:
			guard -= 1
			_sim.car.x = _sim.car.guardrail_x()
			_sim.step(_input)
			_collect()
		check(_sim.wrecked, "when every lamp is lit the Telling ends in a Wreck")
		check_eq(_sim.faults.lamps, capacity, "all five are lit")
		check_eq(_events_named("wreck").size(), 1, "which is announced, once")
		check_eq(GameData.as_string(_event("wreck").get("table")), "drivers", "to the Table he is telling it to")
		check(GameData.as_bool(_sim.snapshot()["wrecked"]), "the snapshot says so")

		# From the Wreck on the player asks for the wheel: pointer on the rim, button down.
		_input.clear()
		_input.pointer_is_absolute = true
		_input.pointer = _sim.space.point_to_pointer(_sim.space.rim_point_at(PI * 0.75))
		_input.lmb = true
		var s_at_wreck: float = _sim.car.s
		var clock_at_wreck: float = _sim.clock.minutes
		var ticks: int = 0
		var moved: bool = false
		var early: bool = false
		while (_sim.wrecked or not _sim.hand.gripping) and ticks < int(10.0 / DT):
			_sim.step(_input)
			_collect()
			ticks += 1
			if _sim.wrecked and (not is_equal_approx(_sim.car.s, s_at_wreck) or not is_equal_approx(_sim.clock.minutes, clock_at_wreck)):
				moved = true
			if not _sim.wrecked and float(ticks) * DT < cut - DT * 1.5:
				early = true
		check(not moved, "while the Table objects nothing moves: not the car, not the Clock")
		check(not early, "the Telling does not restart before wreck_to_wheel")
		check(not _sim.wrecked and _sim.hand.gripping, "then he has the wheel in his hand again")
		check(float(ticks) * DT <= cut + DT * 0.5, "within wreck_to_wheel of the Wreck (%s s)" % str(snappedf(float(ticks) * DT, 0.001)))

		# From Baghdad, with the starting cabin.
		check(_sim.run.active, "a Telling is under way again")
		check_eq(_sim.run.table, "drivers", "at the same Table")
		check_eq(_sim.run.stage, RunState.Stage.APPROACH, "from Baghdad: on the road to the first fork")
		check_eq(_sim.run.act, 1, "in Act 1")
		check_eq(_sim.run.legs_done, 0, "with no leg behind him")
		check(_sim.car.s < 1.0, "at its very start")
		check_eq(_sim.run.retellings, retellings + 1, "told again once more")
		check(_sim.run.seed != first_seed, "and not the same night twice: another seed")
		check(_sim.clock.minutes < 0.01, "at 22:00")
		check_near(_sim.cash, tuning.f("cash_start"), 0.000001, "with cash_start")
		check_near(_sim.nerves.value, tuning.f("nerves_start"), 0.05, "and Nerves at their start")
		check_eq(_sim.faults.lamps, 0, "no lamp is lit")
		check_eq(_sim.faults.deck.size(), data.records("faults").size(), "and the fault deck is whole again")
		check(_sim.items.item(&"beads") == null, "what he had bought is not in the cabin")
		var cabin: Array = GameData.as_array(data.root("items").get("starting_cabin"))
		check_eq(_sim.items.items.size(), cabin.size(), "which is the starting cabin of GDD 7.3")
		for entry: Variant in cabin:
			var start: Dictionary = entry
			var item: ItemSim.Item = _sim.items.item(StringName(GameData.as_string(start.get("item"))))
			if check(item != null, "%s is there" % str(start.get("item"))):
				check_eq(item.supply, GameData.as_int(start.get("supply")), "with its starting supply")
				check_eq(String(item.slot), GameData.as_string(start.get("slot")), "in its place")
		check_eq(_sim.gate.gear, tuning.i("start_gear"), "the car rolls in first gear")
		check(_sim.car.speed <= tuning.fi("gear_speeds", 0) + 0.000001 and _sim.car.speed > 0.0, "at first gear's speed")
		check(not GameData.as_bool(_sim.snapshot()["wrecked"]), "the snapshot shows no Wreck")
		_input.clear()
		_sim.step(_input)

	# Outside a Telling a Wreck is the end of the drive: nothing restarts.
	_sim = DriveSim.new(fresh_data())
	_events = []
	_sim.gate.reset(3)
	_sim.car.reset(1, 3)
	var plain_guard: int = int(60.0 / DT)
	_input.clear()
	while not _sim.wrecked and plain_guard > 0:
		plain_guard -= 1
		_sim.car.x = _sim.car.guardrail_x()
		_sim.step(_input)
	check(_sim.wrecked, "(on a road that belongs to no Telling the fifth lamp is a Wreck too)")
	for _tick: int in int((cut + 1.0) / DT):
		_sim.step(_input)
	check(_sim.wrecked and _sim.faults.lamps == capacity, "and stays one: there is no Telling to tell again")


# --- T-RUN-01, in parts ------------------------------------------------------

## The Exit on a quiet leg: what stops him and what does not.
func _check_exit_cases(exit_at: float, stall_at: float, third: float) -> void:
	var max_speed: float = tuning.f("exit_max_speed")
	var second: float = tuning.fi("gear_speeds", 1)
	check_near(second, max_speed, 0.000001, "(second gear's speed is exit_max_speed)")
	# [what, in the slip lane, gear, speed at the stall, stops]
	var cases: Array = [
		["in the slip lane at exit_max_speed", true, 2, max_speed, true],
		["in the slip lane well under it", true, 1, tuning.fi("gear_speeds", 0), true],
		["in the slip lane a little too fast", true, 3, max_speed + 1.0, false],
		["in the slip lane at par", true, 3, third, false],
		["in the lane beside the slip lane, slow enough", false, 2, max_speed, false],
		["in the middle lane at par", false, 3, third, false],
	]
	for entry: Variant in cases:
		var case: Array = entry
		var what: String = case[0]
		var in_slip: bool = case[1]
		var gear: int = case[2]
		var speed: float = case[3]
		var stops: bool = case[4]
		_begin_quiet_leg()
		var main_lanes: int = _sim.car.lanes
		check_eq(_sim.exit_slip(), Vector2(exit_at, stall_at), "(the Exit is ahead: its slip lane runs from 2,200 m to 2,330 m)")
		_sim.car.s = stall_at - 20.0
		_sim.gate.reset(gear)
		var jump: float = 0.0
		var clock_before: float = _sim.clock.minutes
		var guard: int = int(10.0 / DT)
		while not _sim.stopped and _sim.car.s < stall_at + 5.0 and guard > 0:
			guard -= 1
			var lane: int = main_lanes if in_slip else main_lanes - 1
			if what.contains("middle"):
				lane = 1
			_sim.car.x = _sim.car.lane_center(lane)
			_sim.car.speed = speed
			var nerves_before: float = _sim.nerves.value
			clock_before = _sim.clock.minutes
			_input.clear()
			_sim.step(_input)
			jump = maxf(jump, _sim.nerves.value - nerves_before)
			for event: Dictionary in _sim.drain_events():
				_events.append(event)
		if stops:
			if not check(_sim.stopped, "%s: he stops" % what):
				continue
			check_eq(_sim.run.stage, RunState.Stage.STOP, "the Telling is at a stop")
			check_near(_sim.car.speed, 0.0, 0.000001, "the car stands")
			# (A tea stall sets his Nerves to its own number; nothing else moves them.)
			var tea: bool = GameData.as_string(data.record("stops", _sim.run.stop).get("service")) == "tea"
			check(jump < 0.01 or (tea and is_equal_approx(_sim.nerves.value, GameData.as_float(data.record("stops", _sim.run.stop).get("nerves_to")))),
					"and it costs him no Nerves")
			check_near(_sim.clock.minutes - clock_before, GameData.as_float(data.record("stops", _sim.run.stop).get("clock_min")), 0.01, "but the stop's game minutes")
			check_eq(_sim.exit_slip(), Vector2(-1.0, -1.0), "(the slip lane is behind him)")
			check_eq(GameData.as_string(_event("stop_entered").get("stop")), GameData.as_string(_sim.run.branch.get("stop")), "the stop his branch named")
		else:
			check(not _sim.stopped, "%s: he does not stop" % what)
			check_eq(_sim.run.stage, RunState.Stage.LEG, "the leg goes on")
			check_near(jump, tuning.f("missed_exit_nerves"), 0.01, "and the missed Exit is +5 Nerves")
			check(not _has_event("stop_entered"), "no stop is announced")
		check_eq(_sim.car.lanes, main_lanes, "past the stall the road has its own lanes again")

	# The stall is at 2,330 m: a car in the slip lane is not stopped before it.
	_begin_quiet_leg()
	var lanes: int = _sim.car.lanes
	_sim.car.s = exit_at + 1.0
	_sim.gate.reset(2)
	var stopped_at: float = -1.0
	var opened_at: float = -1.0
	for _tick: int in int(15.0 / DT):
		if _sim.stopped:
			break
		_sim.car.x = _sim.car.lane_center(lanes)
		_sim.car.speed = max_speed
		_input.clear()
		_sim.step(_input)
		if opened_at < 0.0 and _sim.car.lanes == lanes + 1:
			opened_at = _sim.car.s
		if _sim.stopped:
			stopped_at = _sim.car.s
	check(opened_at >= exit_at and opened_at < exit_at + 2.0, "the slip lane opens at 2,200 m")
	check(stopped_at >= stall_at and stopped_at < stall_at + max_speed * KMH_TO_MS * DT * 2.0, "and he is stopped at 2,330 m, not before (%s m)" % str(snappedf(stopped_at, 0.01)))

	# Leaving: gripping the wheel for stop_leave_grip.
	var leave: float = tuning.f("stop_leave_grip")
	check_near(leave, 0.5, 0.000001, "GDD 9.6: gripping the wheel for 0.5 s leaves")
	_input.clear()
	for _tick: int in int(2.0 / DT):
		_sim.step(_input)
	check(_sim.stopped, "he stays as long as he likes: nothing moves on")
	var gripped_for: float = _grip_until_left(leave * 0.6)
	check(_sim.stopped, "a grip of %s s does not leave" % str(snappedf(gripped_for, 0.01)))
	_input.clear()
	for _tick: int in int(0.5 / DT):
		_sim.step(_input)
	gripped_for = _grip_until_left(5.0)
	check(not _sim.stopped, "a longer one does")
	check_near(gripped_for, leave, DT * 1.5, "after %s s on the wheel" % str(leave))
	check_eq(_sim.run.stage, RunState.Stage.LEG, "he is back on the leg")
	check_near(_sim.car.s, stopped_at, 0.5, "beside the stall")
	check_near(_sim.car.x, _sim.car.lane_center(lanes - 1), 0.01, "in the road's right lane")
	check_eq(_sim.car.lanes, lanes, "the slip lane is gone")
	check_eq(_sim.gate.gear, tuning.i("start_gear"), "in first gear")
	check(_sim.car.speed < tuning.fi("gear_speeds", 0), "pulling away from rest")
	check(_has_event("stop_left"), "which is announced")

	# The grip he drove in with does not count: he must let go once.
	_begin_quiet_leg()
	lanes = _sim.car.lanes
	_sim.car.s = stall_at - 60.0
	_sim.gate.reset(2)
	_input.clear()
	_input.pointer_is_absolute = true
	_input.pointer = _sim.space.point_to_pointer(_sim.space.grip_reference)
	_input.lmb = true
	for _tick: int in int(8.0 / DT):
		if _sim.stopped:
			break
		_sim.car.x = _sim.car.lane_center(lanes)
		_sim.car.speed = max_speed
		_sim.step(_input)
	check(_sim.stopped, "(he drives up to the stall with the wheel in his hand)")
	for _tick: int in 3:
		_sim.step(_input)
	check(_sim.stopped and _sim.hand.gripping, "(and has it still: the button never came up)")
	for _tick: int in int(leave * 3.0 / DT):
		_sim.step(_input)
	check(_sim.stopped, "the grip he arrived with does not drive him off again")


## The gore itself: a car on the split is on the right-hand road.
func _check_gore_line() -> void:
	for side: int in [RunState.LEFT, RunState.RIGHT]:
		for nudge: float in [0.01, 1.2]:
			_sim.begin_telling("drivers", 99)
			var branches: Array[Dictionary] = RunGenerator.fork(data, 99, 1, 0)
			var split: float = _sim.car.road_right() * 0.5
			var x: float = split - nudge if side == RunState.LEFT else split + nudge - 0.01
			var guard: int = int(60.0 / DT)
			while _sim.run.stage == RunState.Stage.APPROACH and guard > 0:
				guard -= 1
				_sim.car.x = x
				_input.clear()
				_sim.step(_input)
			check_eq(_sim.leg.leg_id, GameData.as_string(branches[side]["leg"]),
					"%s m %s of the split at the gore: the %s branch" % [str(nudge), "left" if side == RunState.LEFT else "right", "left" if side == RunState.LEFT else "right"])
	# In first gear and hands off, the car drifts to the right on the way: that too is a choice.
	_sim.begin_telling("drivers", 99)
	var first: Array[Dictionary] = RunGenerator.fork(data, 99, 1, 0)
	_input.clear()
	var ticks: int = 0
	while _sim.run.stage == RunState.Stage.APPROACH and ticks < int(60.0 / DT):
		ticks += 1
		_sim.step(_input)
	check_eq(_sim.run.stage, RunState.Stage.LEG, "left alone, the car rolls through the first fork by itself")
	check_eq(_sim.leg.leg_id, GameData.as_string(first[RunState.RIGHT]["leg"]), "drifting right, onto the right-hand branch")
	check_near(float(ticks) * DT, (tuning.f("leg_tail") - tuning.f("exit_slip_length")) / (tuning.fi("gear_speeds", 0) * KMH_TO_MS), 0.1,
			"the first fork is %s m from where the Telling starts" % str(tuning.f("leg_tail") - tuning.f("exit_slip_length")))


# --- The scripted driver -----------------------------------------------------

## Sets the car and the input for the next tick: on the plan's line in third
## gear, to the side of each fork the script names, into the slip lane in
## second gear where the script stops, and out of each stop again.
func _script_tick() -> void:
	var run: RunState = _sim.run
	var stage: int = run.stage
	_input.clear()
	if _sim.stopped:
		# One tick with the hand off the wheel, then hold it until he leaves.
		if _was_stage == stage:
			_input.pointer_is_absolute = true
			_input.pointer = _sim.space.point_to_pointer(_sim.space.grip_reference)
			_input.lmb = true
		_was_stage = stage
		return
	if stage == RunState.Stage.LEG and (_was_stage != RunState.Stage.LEG and _was_stage != RunState.Stage.STOP or _lined_plan != _sim.leg.plan):
		_legs_met += 1
		_lined_plan = _sim.leg.plan
		_checker.load_plan(_sim.leg.plan)
	_was_stage = stage
	var car: CarSim = _sim.car
	var gear: int = 3
	var x: float = car.x
	match stage:
		RunState.Stage.APPROACH:
			x = _side_x(_sides[_forks_met_now()])
		RunState.Stage.LEG:
			var exit_at: float = _sim.leg.length - tuning.f("leg_tail")
			var stall_at: float = exit_at + tuning.f("exit_slip_length")
			var decision: String = _exits[_legs_met - 1]
			if car.s < exit_at:
				x = _checker.line_x(car.s)
				_indicate_on_the_line()
			elif car.s < stall_at and car.lanes > GameData.as_int(_sim.leg.plan["lanes"]):
				if decision == STOP:
					gear = 2
					x = lerpf(_checker.line_x(exit_at), car.lane_center(car.lanes - 1), clampf((car.s - exit_at) / 70.0, 0.0, 1.0))
				else:
					x = _checker.line_x(exit_at)
			elif run.fork_ahead():
				var from_x: float = car.lane_center(car.lanes - 1) if decision == STOP else _checker.line_x(exit_at)
				x = lerpf(from_x, _side_x(_sides[_forks_met_now()]), clampf((car.s - stall_at) / 80.0, 0.0, 1.0))
			elif decision != STOP:
				x = _checker.line_x(exit_at)
		_:
			x = car.lane_center(car.lanes / 2)
	if _sim.gate.gear != gear:
		_sim.gate.reset(gear)
	car.x = x


## How many forks are behind him: the index of the one ahead.
func _forks_met_now() -> int:
	return (_sim.run.act - 1) * RunGenerator.LEGS_PER_ACT + _sim.run.legs_done + (1 if _sim.run.stage == RunState.Stage.LEG else 0)


## Where across the road he drives to be on that side of the gore.
func _side_x(side: int) -> float:
	return _sim.car.road_right() * (0.25 if side == RunState.LEFT else 0.75)


## He works the indicator before each lane change of the line, as the law asks
## (a Patrol leg stops a driver who does not).
func _indicate_on_the_line() -> void:
	if _sim.items.indicator != 0:
		return
	var here: int = _sim.car.lane_of(_checker.line_x(_sim.car.s))
	var soon: int = _sim.car.lane_of(_checker.line_x(_sim.car.s + 45.0))
	if soon != here:
		_sim.items.complete(data.record("rituals", "indicator"), Gesture.DIR_UP if soon > here else Gesture.DIR_DOWN)


## A Telling at the start of its first leg, with nothing on the road: the
## leg of the right-hand branch without its traffic, hazards, bends and gusts.
func _begin_quiet_leg() -> void:
	_sim = DriveSim.new(fresh_data())
	_events = []
	_sim.begin_telling("drivers", 7)
	var guard: int = int(60.0 / DT)
	_input.clear()
	while _sim.run.stage == RunState.Stage.APPROACH and guard > 0:
		guard -= 1
		_sim.step(_input)
	var plan: Dictionary = RunGenerator.plan(data, _sim.run.branch, _sim.run.act)
	plan["spawns"] = []
	plan["hazards"] = []
	plan["curves"] = []
	plan["gusts"] = []
	plan["zones"] = []
	plan["flock"] = {}
	plan["melons"] = {}
	plan["motorcade"] = {}
	_sim.gate.reset(3)
	_sim.begin_leg(plan)
	_sim.drain_events()


## Grips the wheel until he has left the stop or `seconds` of grip have
## passed, then lets go. Returns how long the hand held the wheel.
func _grip_until_left(seconds: float) -> float:
	_input.clear()
	_input.pointer_is_absolute = true
	_input.pointer = _sim.space.point_to_pointer(_sim.space.grip_reference)
	_input.lmb = true
	var held: float = 0.0
	var guard: int = int(10.0 / DT)
	while _sim.stopped and held < seconds - DT * 0.5 and guard > 0:
		guard -= 1
		_sim.step(_input)
		for event: Dictionary in _sim.drain_events():
			_events.append(event)
		if _sim.hand.gripping or not _sim.stopped:
			held += DT
	_input.clear()
	_sim.step(_input)
	return held


## Lights one lamp: a scrape along the guardrail, then back into the lane
## and past the hit's immunity.
func _scrape() -> void:
	var lamps: int = _sim.faults.lamps
	var lane_x: float = _sim.car.lane_center(1)
	var guard: int = int(5.0 / DT)
	_input.clear()
	while _sim.faults.lamps == lamps and guard > 0:
		guard -= 1
		_sim.car.x = _sim.car.guardrail_x()
		_sim.step(_input)
	for _tick: int in int((tuning.f("hit_immunity") + 0.2) / DT):
		_sim.car.x = lane_x
		_sim.step(_input)
	_sim.gate.reset(3)
	_collect()


func _collect() -> void:
	for event: Dictionary in _sim.drain_events():
		_events.append(event)


func _has_sign(kind: String) -> bool:
	var signs: Array[Dictionary] = _sim.snapshot()["signs"]
	for road_sign: Dictionary in signs:
		if GameData.as_string(road_sign.get("kind")) == kind:
			return true
	return false


func _events_named(type: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for event: Dictionary in _events:
		if GameData.as_string(event.get("type")) == type:
			out.append(event)
	return out


func _event(type: String) -> Dictionary:
	for index: int in range(_events.size() - 1, -1, -1):
		if GameData.as_string(_events[index].get("type")) == type:
			return _events[index]
	return {}


func _has_event(type: String) -> bool:
	return not _event(type).is_empty()

