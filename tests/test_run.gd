extends TestSuite
## M5: a whole Telling (GDD 9.5, 9.6, 11.1) and the Clock (GDD 6.4).

const DT: float = DriveSim.DT
const KMH_TO_MS: float = 1.0 / 3.6

var _sim: DriveSim
var _input: DriveInput
var _events: Array[Dictionary] = []


func before_each() -> void:
	_sim = DriveSim.new(fresh_data())
	_input = DriveInput.new()
	_events = []


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
