class_name DriveSim
extends RefCounted
## The whole simulation of a drive (GDD 13.3).
##
## DriveSim owns every simulation object and exposes two things: step(input)
## and snapshot(). Views read the snapshot each frame and never change state.
## One step is one tick of 1/120 s. What happened is queued as plain
## dictionaries; the drive controller drains them onto the Events bus.
##
## Step order (GDD 13.3). Steps that do not exist yet are built in later
## milestones and slot in here:
##    1. Gesture recogniser
##    2. Hand: target, travel, grip, held object
##    3. Rituals in progress; completed rituals emit effects
##    4. Wheel: commanded angle, smoothing, Tremor, return
##    5. Car: gear, speed, sideways motion, drift
##    6. Traffic            7. Collisions and close calls
##    8. Encounters         9. Effect timers, Nerves, faults
##   10. Clock             11. Heckles and passengers
##   12. Leg progress

const TICKS_PER_SECOND: int = 120
const DT: float = 1.0 / TICKS_PER_SECOND

const GEAR_LEVER: StringName = &"gear_lever"
const AWAKE: StringName = &"awake"
const TREMOR_MUTE: StringName = &"tremor_mute"
const FAULT_RATTLE: StringName = &"rattle"
const FAULT_PULL: StringName = &"pulling_steering"
const FAULT_CLUTCH: StringName = &"slipping_clutch"
const FAULT_CRACKS: StringName = &"cracked_windscreen"
const FAULT_HEADLIGHT: StringName = &"dead_headlight"
const FAULT_MIRROR: StringName = &"cracked_mirror"
const FLAG_HIGH_BEAM: StringName = &"high_beam"
const PULLED_OVER: StringName = &"pulled_over"
const LAW: StringName = &"law"

const EXIT_NONE: int = 0
const EXIT_AHEAD: int = 1
## The slip lane is open on the right.
const EXIT_OPEN: int = 2
const EXIT_BEHIND: int = 3

var data: GameData
var tuning: Tuning
var space: CabinSpace = CabinSpace.new()
var hand: HandSim = HandSim.new()
var wheel: WheelSim = WheelSim.new()
var gate: GearGate = GearGate.new()
var gesture: Gesture = Gesture.new()
var car: CarSim = CarSim.new()
var traffic: TrafficSim = TrafficSim.new()
var collision: Collision = Collision.new()
var effects: EffectSystem = EffectSystem.new()
var nerves: NervesSim = NervesSim.new()
var faults: FaultSim = FaultSim.new()
var items: ItemSim = ItemSim.new()
var leg: LegSim = LegSim.new()
var encounter: EncounterSim = EncounterSim.new()
var suspicion: SuspicionSim = SuspicionSim.new()
var clock: ClockSim = ClockSim.new()
var rng: Rng = Rng.new()
## The Telling he is in, if any (GDD 11.1); the sandbox and single legs have none.
var run: RunState = RunState.new()
## The stop he is at (GDD 9.6).
var stop: StopSim = StopSim.new()

var tick: int = 0
## Thousands of dinars (GDD 6). Never below zero.
var cash: float = 0.0
## True once every lamp is lit: the Telling is over (GDD 6.3).
var wrecked: bool = false
## The act, 1 to 3: it sets the Heavy floor (GDD 6.1).
var act: int = 1
## Added to the Heavy floor (a Table's rule, painkillers).
var heavy_floor_bonus: float = 0.0
## True while an encounter is on: an empty road does not calm him then.
## (The leg's own encounter counts as well; this one is for set pieces.)
var in_encounter: bool = false
## True from the moment Suspicion reaches the top until he has handed the
## officer his licence or banknotes (GDD 6.5). The car stands on the shoulder.
var pulled_over: bool = false
## Game minutes his dealings with the law have cost (the Clock takes them).
var clock_minutes_owed: float = 0.0
## True while the car stands at a stop (GDD 9.6): the night waits.
var stopped: bool = false
## Curve strength now: k of GDD 5.4, signed (+ pushes toward the right shoulder).
var curve_k: float = 0.0
## Sandbox only, until legs exist (M4): vehicles per km spawned ahead on an
## endless road. 0 switches it off; tests leave it off.
var free_traffic_per_km: float = 0.0

## Settings the simulation reads (GDD 17.1).
var steer_sensitivity: float = 1.0
var sequential_shift: bool = false
## Grip mode: false = hold, true = click to grip, click to release.
var grip_toggle: bool = false:
	set(value):
		grip_toggle = value
		hand.grip_toggle = value

## When set, every tick's input is written to it (GDD 13.3): replaying the
## log into a simulation started the same way gives the same state hash.
var input_log: InputLog = null
## What the last stop saved: the Telling as the save file holds it (GDD 13.7).
## It changes only when the car comes to a stop, never during a leg.
var checkpoint: Dictionary = {}
var checkpoints: int = 0

var _events: Array[Dictionary] = []
var _active_ritual: Dictionary = {}
var _active_anchor: int = HandSim.NO_ANCHOR
var _lever_anchor: int = HandSim.NO_ANCHOR
var _lever_in_hand: bool = false
## The hand stays on a control after its gesture until the button comes up,
## so the rest of a long flick does not drag the pointer off it.
var _pinned_until_release: bool = false
## While something is carried: the anchors it may be released on.
var _drag_destinations: Array[int] = []
## Ticks the gust still has to push: a gust lasts a whole number of ticks.
var _gust_ticks_left: int = 0
var _gust_push: float = 0.0
var _gust_strength: float = 0.0
var _gust_duration: float = 0.0
var _grind_nerves: float = 0.0
var _braking: bool = false
var _next_free_spawn_s: float = 0.0
var _forced_gear: int = 1
var _lane: int = 0
var _heavy_floors: PackedFloat64Array = PackedFloat64Array()
var _pound_mult: float = 1.0
var _shoulder_rate: float = 0.0
var _traffic_radius: float = 0.0
var _empty_radius: float = 0.0
var _rain_response: float = 1.0
var _legal_gears: Array[int] = []
## A Snap happened last tick (Nerves step after Suspicion).
var _snapped: bool = false
## Lamps lit since the leg began (a clean leg lights none).
var _leg_lamps_lit: int = 0
## The Exit of the leg he is on (GDD 9.5): where its slip lane opens, where
## the stall is, and how far he is with it.
var _exit: int = EXIT_NONE
var _exit_at: float = 0.0
var _stall_at: float = 0.0
## Seconds the hand has held the wheel at a stop: stop_leave_grip of it leaves.
var _leave_grip: float = 0.0
## The hand has been off the wheel since he stopped: only then can a grip leave.
var _let_go_at_stop: bool = false
## The side of the last fork he took (RunState.LEFT or RIGHT).
var _side: int = RunState.RIGHT
## The shady guy is at the stop he stands at.
var _shady_here: bool = false
## Seconds until a wrecked Telling is told again.
var _wreck_left: float = 0.0


func _init(game_data: GameData) -> void:
	data = game_data
	tuning = game_data.tuning
	space.configure(data)
	_gust_strength = tuning.f("gust_push")
	_gust_duration = tuning.f("gust_duration")
	_grind_nerves = tuning.f("gate_grind_nerves")
	_forced_gear = tuning.i("hit_forced_gear")
	_heavy_floors = tuning.floats("heavy_floor")
	_pound_mult = tuning.f("hand_pound_mult")
	_shoulder_rate = tuning.f("shoulder_nerves_rate")
	_traffic_radius = tuning.f("traffic_radius")
	_empty_radius = tuning.f("empty_road_radius")
	_rain_response = tuning.f("rain_response_mult")
	for legal: Variant in tuning.a("suspicion_legal_gears"):
		_legal_gears.append(GameData.as_int(legal))
	_build()
	reseed(0)


## Everything the simulation is made of, made new: nothing of an earlier
## drive is left in it. A Telling begins with this, and so does every stop,
## so that a Telling loaded from a save is the one that was saved.
func _build() -> void:
	hand = HandSim.new()
	wheel = WheelSim.new()
	gate = GearGate.new()
	gesture = Gesture.new()
	car = CarSim.new()
	traffic = TrafficSim.new()
	collision = Collision.new()
	effects = EffectSystem.new()
	nerves = NervesSim.new()
	faults = FaultSim.new()
	items = ItemSim.new()
	leg = LegSim.new()
	encounter = EncounterSim.new()
	suspicion = SuspicionSim.new()
	clock = ClockSim.new()
	run = RunState.new()
	stop = StopSim.new()
	hand.configure(data, space)
	wheel.configure(tuning)
	gate.configure(tuning)
	gesture.configure(tuning)
	car.configure(tuning)
	traffic.configure(data)
	collision.configure(tuning)
	effects.configure(data)
	nerves.configure(tuning)
	faults.configure(data)
	items.configure(data, effects, nerves, traffic, car, faults)
	leg.configure(data, car, traffic)
	encounter.configure(data, car, traffic, leg)
	suspicion.configure(tuning)
	clock.configure(tuning)
	run.configure(data)
	stop.configure(data, items, faults, nerves, clock, rng)

	cash = tuning.f("cash_start")
	wrecked = false
	act = 1
	heavy_floor_bonus = 0.0
	in_encounter = false
	pulled_over = false
	stopped = false
	clock_minutes_owed = 0.0
	curve_k = 0.0
	_active_ritual = {}
	_active_anchor = HandSim.NO_ANCHOR
	_lever_in_hand = false
	_pinned_until_release = false
	_drag_destinations = []
	_gust_ticks_left = 0
	_gust_push = 0.0
	_braking = false
	_next_free_spawn_s = 0.0
	_snapped = false
	_leg_lamps_lit = 0
	_exit = EXIT_NONE
	_leave_grip = 0.0
	_let_go_at_stop = false
	_side = RunState.RIGHT
	_shady_here = false
	_wreck_left = 0.0
	hand.grip_toggle = grip_toggle

	var start_gear: int = tuning.i("start_gear")
	wheel.reset()
	gate.reset(start_gear)
	car.reset(car.lanes / 2, start_gear)
	_lane = car.lane_of(car.x)
	_lever_anchor = hand.anchor_index(GEAR_LEVER)
	_sync_anchors()


## Sets the Telling seed: the four streams and the fault deck follow from it.
func reseed(telling_seed: int) -> void:
	rng.reseed(telling_seed)
	faults.shuffle_deck(rng)


func seconds() -> float:
	return float(tick) * DT


func step(input: DriveInput) -> void:
	if input_log != null:
		input_log.record(input)
	if wrecked and run.active:
		# The Wreck (GDD 11.4): nothing moves while the Table objects; then
		# the Telling is told again from Baghdad.
		_wreck_left -= DT
		hand.track_pointer(input)
		if _wreck_left > DT * 0.5:
			tick += 1
			return
		_retell()
	gate.begin_tick()
	nerves.begin_tick()
	effects.begin_tick()
	items.begin_tick()
	leg.begin_tick()
	encounter.begin_tick()
	suspicion.begin_tick()

	# 1. Gesture recogniser.
	gesture.step(DT, input.lmb, input.pointer_delta)

	# 2. Hand.
	hand.can_reach = nerves.snap_left <= 0.0
	hand.step(DT, input, wheel.angle, _pound_mult if nerves.pound else 1.0)

	# 3. Rituals.
	_resolve_gesture(input.lmb)
	if _lever_in_hand and not input.lmb:
		gate.release()
		_lever_in_hand = false
		hand.unpin()
	if hand.press_applied and hand.can_reach:
		_begin_at(hand.at_index, input.lmb)

	# 4. Wheel.
	if hand.let_go:
		wheel.release()
	if hand.took_grip:
		wheel.grip()
	wheel.tremor = nerves.tremor_offset
	wheel.step(DT, hand.steer_px, steer_sensitivity)

	# 5. Car: gear, speed, sideways motion, drift.
	_step_leg_road()
	gate.step(DT, input.pointer_delta if _lever_in_hand else Vector2.ZERO,
			faults.param(FAULT_CLUTCH, "lever_speed_mult", 1.0))
	if gate.ground:
		nerves.add(_grind_nerves)
		_emit("sfx_requested", {"id": "grind"})
	_braking = input.rmb
	if not _standing():
		car.step(DT, wheel.steer(), gate.gear, _braking, _extra_drift())
	var lane: int = car.lane_of(car.x)
	if lane != _lane:
		# Crossing a lane line without indicating that way (GDD 6.5).
		if items.indicator != signi(lane - _lane):
			suspicion.add(tuning.f("suspicion_lane_cross"))
		_lane = lane
		items.on_lane_line_crossed()

	# 6. Traffic.
	if free_traffic_per_km > 0.0:
		_step_free_traffic()
	if not stopped:
		leg.step_traffic(DT)
		traffic.step(DT, car.s, car.x, car.speed)

	# 7. Collisions and close calls.
	var lamps_before: int = faults.lamps
	if not _standing():
		collision.step(DT, car, traffic, gate.gear)
		_apply_collisions()
		_step_leg_hazards()
	_leg_lamps_lit += maxi(faults.lamps - lamps_before, 0)

	# 8. Encounters and Suspicion.
	_step_encounter()
	_step_suspicion()

	# 9. Effect timers, Nerves, faults. At a stop the night waits: nothing
	# burns down, cools, drifts or calms while he shops (GDD 6.4).
	if not stopped:
		effects.step(DT)
		items.step(DT)
		_feed_nerves()
		nerves.step(DT)
	_report_nerves()
	_report_effects()
	cash = maxf(cash + items.cash_delta, 0.0)
	for event: Dictionary in items.events:
		_announce(event)
	items.events.clear()
	for event: Dictionary in stop.events:
		_announce(event)
	stop.events.clear()

	# 10. Clock: it runs while he drives, not while he stands (GDD 6.4).
	if not _standing():
		clock.step(DT)

	# 12. Leg progress: Exit, Fork, boss and ending transitions.
	if run.active:
		_step_telling(input.lmb)
	elif leg.step_progress():
		_end_leg()

	tick += 1


## True while the car stands and the road does not move: with the officer,
## or at a stop.
func _standing() -> bool:
	return pulled_over or stopped


## Starts a leg from its plan (LegGenerator): the road, the car at the start
## in the plan's start lane, an empty road ahead, and the leg's weather.
func begin_leg(plan: Dictionary) -> void:
	_set_stretch(plan)
	_arm_exit()
	_announce_leg(plan)


## In a Telling every leg ends in an Exit (GDD 9.5): the slip lane opens
## leg_tail short of the leg's end and the stall is exit_slip_length on.
func _arm_exit() -> void:
	if not run.active or run.stage != RunState.Stage.LEG:
		return
	_exit = EXIT_AHEAD
	_exit_at = leg.length - tuning.f("leg_tail")
	_stall_at = _exit_at + tuning.f("exit_slip_length")


func _announce_leg(plan: Dictionary) -> void:
	_emit("leg_started", {
		"leg": leg.leg_id,
		"modifier": GameData.as_string(plan.get("modifier")),
		"act": act,
		"par": leg.par,
	})


## Puts the car at the start of a stretch of road: a leg, or a blank plan.
func _set_stretch(plan: Dictionary) -> void:
	set_road(GameData.as_int(plan.get("lanes"), 3), GameData.as_bool(plan.get("divided"), true))
	traffic.clear()
	collision.reset()
	car.reset(GameData.as_int(plan.get("start_lane")), gate.gear)
	_lane = car.lane_of(car.x)
	act = GameData.as_int(plan.get("act"), act)
	curve_k = 0.0
	items.begin_leg()
	leg.begin(plan)
	encounter.begin(plan)
	suspicion.end_watch()
	_release_from_pull_over()
	items.raining = leg.raining
	items.dust_rate = leg.dust_rate
	car.lat_tau_mult = _rain_response if leg.raining else 1.0
	_leg_lamps_lit = 0
	_exit = EXIT_NONE


## The same for a car that drives on from one stretch into the next: it
## keeps its speed and its place across its lane.
func _roll_into(plan: Dictionary) -> void:
	var speed: float = car.speed
	var off_centre: float = car.x - car.lane_center(clampi(car.lane_of(car.x), 0, car.lanes - 1))
	_set_stretch(plan)
	var room: float = (car.lane_width() - tuning.f("car_width")) * 0.5
	car.speed = speed
	car.x += clampf(off_centre, -room, room)
	_lane = car.lane_of(car.x)


## The car passed the end of the leg: what it earned (GDD 12.1).
func _end_leg() -> void:
	var clean: bool = _leg_lamps_lit == 0
	var clean_bonus: float = tuning.f("clean_leg_bonus") if clean else 0.0
	var par_bonus: float = floorf(maxf(leg.par - leg.time, 0.0) * tuning.f("par_bonus_rate"))
	cash += clean_bonus + par_bonus
	# A clean leg also lets him breathe (GDD 6.1: -10 Nerves at the leg's end).
	if clean:
		nerves.add(tuning.f("clean_leg_nerves"))
	items.raining = false
	items.dust_rate = 0.0
	car.lat_tau_mult = 1.0
	curve_k = 0.0
	encounter.stop()
	if suspicion.watching:
		suspicion.end_watch()
		_emit("suspicion_changed", {"value": 0.0, "watching": false})
	_emit("leg_ended", {
		"leg": leg.leg_id,
		"time": leg.time,
		"par": leg.par,
		"clean": clean,
		"clean_bonus": clean_bonus,
		"par_bonus": par_bonus,
		"cash": cash,
	})


## The leg's bend and gusts, before the car moves.
func _step_leg_road() -> void:
	if not leg.active or _standing():
		return
	leg.step_road(DT)
	curve_k = leg.curve_k
	if leg.gust_started != 0:
		start_gust(leg.gust_started)


# --- A Telling (GDD 9.5, 11.1) -----------------------------------------------

## Starts a Telling of `table` from Baghdad: the starting cabin, 22:00, the
## car rolling in first gear toward the first fork with nobody at the wheel.
func begin_telling(table: String, telling_seed: int) -> void:
	_build()
	reseed(telling_seed)
	run.begin(table, telling_seed)
	_enter_approach()


## The road to a fork: nothing on it but the sign and the split.
func _enter_approach() -> void:
	var length: float = tuning.f("leg_tail") - tuning.f("exit_slip_length")
	_set_stretch(RunGenerator.blank_plan(run.act, RunGenerator.ROAD_LANES, true, length))


func _step_telling(button_down: bool) -> void:
	if stopped:
		_step_stop(button_down)
		return
	match run.stage:
		RunState.Stage.APPROACH:
			if leg.step_progress():
				_take_fork()
		RunState.Stage.LEG:
			_step_exit()
			if not stopped and leg.step_progress():
				_end_leg()
				run.leg_done()
				if run.fork_ahead():
					_take_fork()
				else:
					_begin_boss()
		RunState.Stage.BOSS:
			if leg.step_progress():
				_end_boss()
		RunState.Stage.ARRIVAL:
			if leg.step_progress():
				_arrive()


## The gore point (GDD 9.5): the branch is the side of the split the car is on.
func _take_fork() -> void:
	var side: int = RunState.LEFT if car.x < car.road_right() * 0.5 else RunState.RIGHT
	_side = side
	var branch: Dictionary = run.take_branch(side)
	var plan: Dictionary = RunGenerator.plan(data, branch, run.act)
	_emit("fork_taken", {
		"act": run.act,
		"leg_index": run.legs_done,
		"side": side,
		"leg": GameData.as_string(branch.get("leg")),
		"modifier": GameData.as_string(branch.get("modifier")),
		"stop": GameData.as_string(branch.get("stop")),
		"par": GameData.as_float(branch.get("par_s")),
	})
	_roll_into(plan)
	_arm_exit()
	_announce_leg(plan)


## The Exit (GDD 9.5): a slip lane opens on the right; a car in it at the
## stall, at exit_max_speed or less, stops. Any other car has missed it.
func _step_exit() -> void:
	if _exit == EXIT_AHEAD and car.s >= _exit_at:
		_exit = EXIT_OPEN
		car.set_road(car.lanes + 1, car.divided)
		_lane = car.lane_of(car.x)
	elif _exit == EXIT_OPEN and car.s >= _stall_at:
		_exit = EXIT_BEHIND
		var in_slip_lane: bool = car.lane_of(car.x) >= car.lanes - 1
		car.set_road(car.lanes - 1, car.divided)
		_lane = car.lane_of(car.x)
		if in_slip_lane and car.speed <= tuning.f("exit_max_speed"):
			_enter_stop()
		else:
			nerves.add(tuning.f("missed_exit_nerves"))


## Where the Exit's slip lane runs while it is ahead of the car or beside
## it; Vector2(-1, -1) otherwise.
func exit_slip() -> Vector2:
	if not run.active or run.stage != RunState.Stage.LEG or stopped or _exit == EXIT_NONE or _exit == EXIT_BEHIND:
		return Vector2(-1.0, -1.0)
	return Vector2(_exit_at, _stall_at)


func _enter_stop() -> void:
	run.enter_stop()
	var minutes: float = GameData.as_float(data.record("stops", run.stop).get("clock_min")) if data.has_record("stops", run.stop) else 0.0
	clock.add_minutes(minutes)
	# The shady guy is there after a leg that lit no lamp (GDD 9.6).
	_shady_here = _leg_lamps_lit == 0
	_save_point()
	_emit("stop_entered", {"stop": run.stop, "minutes": minutes, "act": run.act, "leg_index": run.legs_done,
			"shady": _shady_here, "offers": stop.offers_view()})


## A stop is where the game saves (GDD 11.1). What the save holds is taken
## and at once put back, so that the Telling which goes on from here is,
## to the bit, the one a player gets who loads that save.
func _save_point() -> void:
	checkpoint = capture()
	checkpoints += 1
	restore(checkpoint)


func _open_stop(shady: bool) -> void:
	if data.has_record("stops", run.stop):
		stop.begin(run.stop, run.act, shady)
	_sync_anchors()


## The car stands; the road is gone until he leaves.
func _park() -> void:
	stopped = true
	car.speed = 0.0
	car.v_lat = 0.0
	traffic.remove_all()
	encounter.road_cleared()
	_leave_grip = 0.0
	_let_go_at_stop = false


## At a stop: gripping the wheel for stop_leave_grip leaves (GDD 9.6). The
## grip he drove in with does not count: the hand must have been off the wheel.
func _step_stop(button_down: bool) -> void:
	if not hand.gripping:
		# Off the wheel, and with the button up: a button held since he drove
		# in would otherwise take the wheel again and drive him off.
		if not button_down:
			_let_go_at_stop = true
		_leave_grip = 0.0
		return
	if not _let_go_at_stop:
		return
	_leave_grip += DT
	if _leave_grip >= tuning.f("stop_leave_grip") - DT * 0.5:
		_leave_stop()


func _leave_stop() -> void:
	_emit("stop_left", {"stop": run.stop})
	cash = stop.leave(cash)
	stopped = false
	_leave_grip = 0.0
	gate.reset(tuning.i("start_gear"))
	if run.stage == RunState.Stage.BOSS_STOP:
		run.leave_boss_stop()
		if run.stage == RunState.Stage.ARRIVAL:
			_set_stretch(RunGenerator.blank_plan(run.act, RunGenerator.ROAD_LANES, true, tuning.f("arrival_length")))
		else:
			_enter_approach()
	else:
		# Back on the road beside the stall, in its right lane.
		run.leave_stop()
		car.x = car.lane_center(car.lanes - 1)
		_lane = car.lane_of(car.x)
	car.speed = 0.0
	_sync_anchors()


## The act's boss. Until the bosses are built (M7) it is an empty road of the
## boss's length.
func _begin_boss() -> void:
	run.begin_boss()
	var boss: Dictionary = run.boss_record()
	_roll_into(RunGenerator.blank_plan(run.act, GameData.as_int(boss.get("lanes"), RunGenerator.ROAD_LANES),
			GameData.as_bool(boss.get("divided"), true), GameData.as_float(boss.get("length_m")), GameData.as_float(boss.get("par_s"))))
	_emit("boss_started", {"boss": run.boss, "act": run.act})


func _end_boss() -> void:
	_emit("boss_ended", {"boss": run.boss, "act": run.act, "time": leg.time})
	run.enter_boss_stop()
	_shady_here = false
	_save_point()
	_emit("stop_entered", {"stop": run.stop, "minutes": 0.0, "act": run.act, "leg_index": run.legs_done,
			"shady": false, "offers": stop.offers_view()})


## The end of the road (GDD 10.5): the Clock is read. Until the Arrival is
## built (M7) the end of the street is the bay.
func _arrive() -> void:
	run.arrive()
	_emit("arrived", {"table": run.table, "clock": clock.text(), "clock_minutes": clock.minutes, "late": clock.late()})


# --- Wreck, save and replay --------------------------------------------------

## The Telling is told again from Baghdad (GDD 11.4): the same Table, another
## seed, the starting cabin, 22:00. The pointer stays where the player has it,
## so a hand that is asking for the wheel has it at once.
func _retell() -> void:
	var table: String = run.table
	var telling_seed: int = run.seed
	var retellings: int = run.retellings
	var pointer: Vector2 = hand.pointer
	_build()
	run.table = table
	run.seed = telling_seed
	run.retellings = retellings
	run.retell()
	reseed(run.seed)
	_enter_approach()
	if space.pointer_on_rim(pointer):
		hand.place_at(space.rim_point(pointer))
	else:
		hand.pointer = pointer


## The Telling as the save file holds it (GDD 13.7): where he is, what he
## has and what the night has cost, and the state of the seeded streams.
func capture() -> Dictionary:
	var kept: Array = []
	var fitted: Array = []
	for item: ItemSim.Item in items.items:
		if GameData.as_string(item.record.get("kind")) == "adaptation":
			fitted.append({"id": String(item.id), "slot": String(item.slot)})
		else:
			kept.append({"id": String(item.id), "slot": String(item.slot), "supply": item.supply, "hot": Save.exact(item.hot_left)})
	var lit: Array = []
	for fault: StringName in faults.active:
		lit.append(String(fault))
	var deck: Array = []
	for fault: StringName in faults.deck:
		deck.append(String(fault))
	var switches: Dictionary = {}
	for key: Variant in items.flags:
		switches[str(key)] = GameData.as_bool(items.flags[key])
	return {
		"table": run.table,
		"seed": Save.seed_out(run.seed),
		"retellings": run.retellings,
		"act": run.act,
		"leg": run.legs_done,
		"stage": run.stage_name(),
		"side": _side,
		"leg_lamps": _leg_lamps_lit,
		"shady": _shady_here,
		# For people: rounded. What is loaded are the exact bits below.
		"clock_min": snappedf(clock.minutes, 0.001),
		"cash": snappedf(cash, 0.001),
		"nerves": snappedf(nerves.value, 0.001),
		"exact": {
			"clock_min": Save.exact(clock.minutes),
			"cash": Save.exact(cash),
			"nerves": Save.exact(nerves.value),
			"leg_time": Save.exact(leg.time),
		},
		"faults": lit,
		"fault_deck": deck,
		"items": kept,
		"adaptations": fitted,
		"passenger": null,
		"radio": String(items.radio),
		"switches": switches,
		"rng_state": rng.get_state(),
	}


## Stands the car at the stop a save was made at. False (and nothing
## changed) when the save is not one made at a stop.
func restore(telling: Dictionary) -> bool:
	var stage: String = GameData.as_string(telling.get("stage"))
	if stage != RunState.STAGE_NAMES[RunState.Stage.STOP] and stage != RunState.STAGE_NAMES[RunState.Stage.BOSS_STOP]:
		# A save is made at a stop and nowhere else: this is not one.
		return false
	_build()
	rng.set_state(GameData.as_dict(telling.get("rng_state")))
	# The exact bits where the save has them; a save written by hand has
	# only the readable numbers.
	var bits: Dictionary = GameData.as_dict(telling.get("exact"))
	clock.minutes = maxf(Save.from_exact(bits.get("clock_min"), GameData.as_float(telling.get("clock_min"))), 0.0)
	cash = maxf(Save.from_exact(bits.get("cash"), GameData.as_float(telling.get("cash"))), 0.0)
	nerves.set_value(Save.from_exact(bits.get("nerves"), GameData.as_float(telling.get("nerves"))))
	faults.active.clear()
	for fault: Variant in GameData.as_array(telling.get("faults")):
		faults.active.append(StringName(GameData.as_string(fault)))
	faults.deck.clear()
	for fault: Variant in GameData.as_array(telling.get("fault_deck")):
		faults.deck.append(StringName(GameData.as_string(fault)))
	faults.lamps = faults.active.size()
	items.empty_cabin()
	for entry: Variant in GameData.as_array(telling.get("items")):
		var kept: Dictionary = GameData.as_dict(entry)
		var item: ItemSim.Item = items.add_item(StringName(GameData.as_string(kept.get("id"))),
				StringName(GameData.as_string(kept.get("slot"))), GameData.as_int(kept.get("supply"), -1))
		if item != null:
			item.hot_left = Save.from_exact(kept.get("hot"), item.hot_left)
	for entry: Variant in GameData.as_array(telling.get("adaptations")):
		var fitted: Dictionary = GameData.as_dict(entry)
		items.add_item(StringName(GameData.as_string(fitted.get("id"))), StringName(GameData.as_string(fitted.get("slot"))))
	var switches: Dictionary = GameData.as_dict(telling.get("switches"))
	for key: Variant in switches:
		items.flags[StringName(str(key))] = GameData.as_bool(switches[key])
	items.set_radio(StringName(GameData.as_string(telling.get("radio"), String(ItemSim.STATIC))))

	_side = GameData.as_int(telling.get("side"), RunState.RIGHT)
	_shady_here = GameData.as_bool(telling.get("shady"))
	run.resume(GameData.as_string(telling.get("table")), Save.seed_in(telling.get("seed")), GameData.as_int(telling.get("retellings")),
			GameData.as_int(telling.get("act"), 1), GameData.as_int(telling.get("leg")), stage, _side)
	if run.stage == RunState.Stage.STOP:
		# At the stall of the leg he is on.
		_set_stretch(RunGenerator.plan(data, run.branch, run.act))
		_exit = EXIT_BEHIND
		_exit_at = leg.length - tuning.f("leg_tail")
		_stall_at = _exit_at + tuning.f("exit_slip_length")
		car.s = _stall_at
		car.x = car.lane_center(car.lanes - 1)
		_lane = car.lane_of(car.x)
		leg.fast_forward(car.s, maxf(Save.from_exact(bits.get("leg_time"), 0.0), 0.0))
		_leg_lamps_lit = GameData.as_int(telling.get("leg_lamps"))
		# Whatever the leg's encounter was, it is behind him.
		encounter.stop()
	else:
		# At the end of the act's boss.
		var boss: Dictionary = run.boss_record()
		_set_stretch(RunGenerator.blank_plan(run.act, GameData.as_int(boss.get("lanes"), RunGenerator.ROAD_LANES),
				GameData.as_bool(boss.get("divided"), true), GameData.as_float(boss.get("length_m")), GameData.as_float(boss.get("par_s"))))
		car.s = leg.length
		leg.stop()
	_park()
	_open_stop(_shady_here)
	return true


## A fingerprint of the whole simulation (GDD 13.3): two simulations that
## were started the same way and given the same inputs have the same one.
func state_hash() -> String:
	var context: HashingContext = HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(var_to_bytes(state()))
	return context.finish().hex_encode()


## Everything the hash is made of, in a fixed order (for telling two
## simulations apart when their hashes differ).
func state() -> Array:
	var vehicles: Array = []
	for vehicle: TrafficSim.Vehicle in traffic.vehicles:
		vehicles.append([vehicle.id, vehicle.type_id, vehicle.s, vehicle.x, vehicle.speed, vehicle.cruise,
				vehicle.direction, vehicle.lane, vehicle.signalling, vehicle.changing, vehicle.role])
	return [
		tick, snapshot(), capture(), effects.get_state(), vehicles,
		car.s, car.x, car.speed, car.v_lat, car.drift, wheel.angle, gate.gear, gate.lever,
		hand.pos, hand.target, hand.pointer, hand.gripping, nerves.value, nerves.snap_left,
		collision.chain, collision.immunity_left, leg.time, clock.minutes, suspicion.value, cash,
	]


# --- Encounters and the law --------------------------------------------------

## The leg's encounter: what it does to him this tick.
func _step_encounter() -> void:
	if _standing() or not leg.active:
		return
	encounter.step(DT, _braking, gate.gear)
	nerves.add_rate(encounter.nerves_rate)
	if encounter.cut_off:
		nerves.add(tuning.f("cut_off_nerves"))
	if encounter.road_changed:
		# A slip lane or a side road: the same car, another lane count.
		_lane = car.lane_of(car.x)
	if encounter.watch_began:
		suspicion.begin_watch()
		_emit("suspicion_changed", {"value": 0.0, "watching": true})
	if encounter.watch_ended:
		suspicion.end_watch()
		_emit("suspicion_changed", {"value": 0.0, "watching": false})


## Suspicion (GDD 6.5): what he did this tick that the police saw.
func _step_suspicion() -> void:
	if not suspicion.watching or pulled_over:
		_snapped = false
		return
	var before: float = suspicion.value
	if gate.gear != GearGate.NEUTRAL and not _legal_gears.has(gate.gear):
		suspicion.add_rate(tuning.f("suspicion_gear_rate"))
	if leg.active and leg.night:
		suspicion.add_rate(faults.param(FAULT_HEADLIGHT, "patrol_suspicion_per_s", 0.0))
	if items.horn_blown:
		suspicion.add(tuning.f("suspicion_honk"))
	if items.contraband_used:
		suspicion.add(tuning.f("suspicion_contraband"))
	if items.phone_used:
		suspicion.add(tuning.f("suspicion_phone"))
	if _snapped:
		suspicion.add(tuning.f("suspicion_snap"))
	_snapped = false
	suspicion.add(leg.hazard_suspicion)
	suspicion.step(DT)
	if suspicion.jumped != 0.0 or floorf(suspicion.value) != floorf(before):
		_emit("suspicion_changed", {"value": suspicion.value, "watching": true})
	if suspicion.reached_max:
		_pull_over()


## At the top of Suspicion he is pulled over (GDD 6.5): the car stands on the
## shoulder, the police car behind it, and the officer waits at the window
## for his licence (a fine) or banknotes (a bribe).
func _pull_over() -> void:
	pulled_over = true
	effects.hold(PULLED_OVER, LAW, true)
	car.speed = 0.0
	car.v_lat = 0.0
	car.x = car.road_right() + (car.guardrail_x() - car.road_right()) * 0.5 + tuning.f("rumble_strip_width") * 0.5
	_lane = car.lane_of(car.x)
	encounter.park_police_behind()
	if gesture.is_active():
		gesture.cancel()
	_emit("pulled_over", {
		"released": false,
		"fine": fine(),
		"bribe": bribe(),
		"can_bribe": cash >= bribe(),
	})
	_sync_anchors()


## What the licence costs him: fine_share of his cash, fine_min at least, and
## never more than he has (GDD 6.5, 12.2).
func fine() -> float:
	return minf(maxf(roundf(cash * tuning.f("fine_share")), tuning.f("fine_min")), cash)


## What banknotes cost him: bribe_base plus bribe_per_act for each act.
func bribe() -> float:
	return tuning.f("bribe_base") + tuning.f("bribe_per_act") * float(act)


## He handed the officer something. A bribe he cannot pay is not taken.
func _pay_the_officer(how: StringName) -> void:
	if not pulled_over:
		return
	var cost: float = 0.0
	var minutes: float = 0.0
	var taken: Array[StringName] = []
	if how == &"bribe":
		cost = bribe()
		if cash < cost:
			_emit("pulled_over", {"released": false, "refused": true, "fine": fine(), "bribe": cost, "can_bribe": false})
			return
		minutes = tuning.f("bribe_minutes")
	else:
		cost = fine()
		minutes = tuning.f("fine_minutes")
		taken = items.take_visible_contraband()
	cash = maxf(cash - cost, 0.0)
	clock_minutes_owed += minutes
	clock.add_minutes(minutes)
	suspicion.end_watch()
	encounter.end_patrol()
	_release_from_pull_over()
	var taken_ids: Array[String] = []
	for id: StringName in taken:
		taken_ids.append(String(id))
	_emit("pulled_over", {"released": true, "paid": String(how), "cost": cost, "minutes": minutes, "taken": taken_ids})
	_emit("suspicion_changed", {"value": 0.0, "watching": false})


func _release_from_pull_over() -> void:
	if not pulled_over and not effects.has(PULLED_OVER):
		return
	pulled_over = false
	effects.hold(PULLED_OVER, LAW, false)
	_sync_anchors()


## Cones, melons, sheep and potholes (GDD 5.6, 9.4): Nerves, and for a
## pothole a share of his speed. No lamp.
func _step_leg_hazards() -> void:
	leg.step_hazards(DT)
	if leg.hits.is_empty():
		return
	nerves.add(leg.hazard_nerves)
	car.speed *= leg.speed_factor
	for kind: StringName in leg.hits:
		_emit("sfx_requested", {"id": "scrape", "hazard": String(kind)})


## Sets the road the car is on: 1 to 3 lanes, divided or not (GDD 5.1).
func set_road(lanes: int, divided: bool) -> void:
	car.set_road(lanes, divided)
	_lane = car.lane_of(car.x)


## Starts one gust (GDD 5.4): gust_push for gust_duration, which is counted in
## whole ticks (a float countdown ran one tick over). `direction` is +1 toward
## the right shoulder, -1 toward the left. `strength` scales it.
func start_gust(direction: int, strength: float = 1.0) -> void:
	_gust_ticks_left = roundi(_gust_duration * float(TICKS_PER_SECOND))
	_gust_push = _gust_strength * strength * float(direction)


## The Heavy floor now (GDD 6.1): by act, plus what the Table or a pill adds.
func heavy_floor() -> float:
	var index: int = clampi(act, 1, _heavy_floors.size()) - 1
	return _heavy_floors[index] + heavy_floor_bonus


## How far he can see along the road, in metres (GDD 9.1, 9.4): the
## headlight cone at night, the dust in a dust haze, else no limit (INF).
func visibility() -> float:
	if not leg.active:
		return INF
	var reach: float = leg.dust_visibility
	if leg.night:
		reach = minf(reach, headlight_cone())
	return reach


## How far the headlights reach at night, in metres (GDD 4.6, 6.3).
func headlight_cone() -> float:
	var cone: float = tuning.f("high_beam_cone") if items.flag(FLAG_HIGH_BEAM) else tuning.f("low_beam_cone")
	return cone * faults.param(FAULT_HEADLIGHT, "night_cone_mult", 1.0)


## What happened since the last call, oldest first.
func drain_events() -> Array[Dictionary]:
	var out: Array[Dictionary] = _events
	_events = []
	return out


## Everything a view needs to draw this instant. Views never keep references
## into the simulation; they read this.
func snapshot() -> Dictionary:
	var pointer_point: Vector3 = hand.target
	if hand.snap_index != HandSim.NO_ANCHOR:
		pointer_point = hand.anchor_position(hand.snap_index)
	return {
		"tick": tick,
		"time": seconds(),
		"hand_pos": hand.pos,
		"hand_target": hand.target,
		"hand_gripping": hand.gripping,
		"hand_at": hand.at_id(),
		"hand_snap": hand.snap_id(),
		"pointer": hand.pointer,
		"pointer_point": pointer_point,
		"pointer_visible": not hand.pinned,
		"cam_yaw": hand.cam_yaw,
		"cam_pitch": hand.cam_pitch,
		"wheel_angle": wheel.angle,
		"gear": gate.gear,
		"lever": gate.lever,
		"lever_held": gate.held,
		"gesture_kind": gesture.kind,
		"gesture_progress": gesture.progress,
		"gesture_anchor": hand.anchor_id(_active_anchor),
		"car_x": car.x,
		"car_s": car.s,
		"speed": car.speed,
		"v_lat": car.v_lat,
		"drift": car.drift,
		"lanes": car.lanes,
		"divided": car.divided,
		"on_rumble": car.on_rumble,
		"on_shoulder": car.on_shoulder,
		"braking": _braking,
		"nerves": nerves.value,
		"heavy_floor": nerves.heavy_floor,
		"awake": nerves.awake,
		"tremor": nerves.tremor_amplitude,
		"tunnel": nerves.tunnel,
		"pound": nerves.pound,
		"lids": nerves.lids,
		"eyes_shut": nerves.eyes_shut,
		"snap": nerves.snap_left > 0.0,
		"haze": items.haze,
		"rain_blur": items.rain_blur(),
		"visor_down": effects.has(ItemSim.VISOR_DOWN),
		"radio": items.radio,
		"indicator": items.indicator,
		"flags": items.flags.duplicate(),
		"effects": effects.active_ids(),
		"lamps": faults.lamps,
		"lamp_capacity": faults.capacity,
		"faults": faults.active.duplicate(),
		"cracks": faults.param(FAULT_CRACKS, "cracks", 0.0),
		"headlight_cone": headlight_cone(),
		"mirror_delay": faults.param(FAULT_MIRROR, "mirror_tell_delay_s", 0.0),
		"cash": cash,
		"clock": clock.text(),
		"clock_minutes": clock.minutes,
		"night_share": clock.night_share(),
		"late": clock.late(),
		"chain": collision.chain,
		"wrecked": wrecked,
		"curve_k": curve_k,
		"leg": leg.leg_id,
		"leg_active": leg.active,
		"leg_time": leg.time,
		"leg_par": leg.par,
		"leg_length": leg.length,
		"raining": leg.active and leg.raining,
		"night": leg.active and leg.night,
		"gust_tell": leg.gust_tell_left,
		"gust_dir": leg.gust_tell_dir,
		"suspicion": suspicion.value,
		"suspicion_watching": suspicion.watching,
		"police_lights": encounter.police_lights,
		"tailgater": encounter.tail_phase if encounter.kind == "tailgater" else 0,
		"glare": encounter.glare,
		"side_road": encounter.side_road if encounter.kind == "motorcade" else 0,
		"slip": _slip_in_view(),
		"slip_open": _exit == EXIT_OPEN or (encounter.kind == "motorcade" and encounter.side_road == EncounterSim.SIDE_ROAD_OPEN),
		"telling": run.active,
		"table": run.table,
		"stage": run.stage_name(),
		"act": run.act if run.active else act,
		"legs_done": run.legs_done,
		"stop": run.stop,
		"stopped": stopped,
		"gore_ahead": leg.length - car.s if run.active and run.fork_ahead() and leg.active else -1.0,
		"offers": _offers_in_view(),
		"boss": run.boss,
		"pulled_over": pulled_over,
		"visibility": visibility(),
		# Unlit things show only inside what he can see: at night they appear late.
		"hazards": _hazards_in_view(),
		"signs": _signs_in_view(),
		"items": _item_snapshots(),
		"anchors_in_use": _anchors_in_use(),
		"vehicles": _vehicle_snapshots(),
	}


## One small dictionary per vehicle, positions relative to the car.
func _offers_in_view() -> Array[Dictionary]:
	if not stopped:
		var none: Array[Dictionary] = []
		return none
	return stop.offers_view()


func _hazards_in_view() -> Array[Dictionary]:
	if not leg.active:
		var none: Array[Dictionary] = []
		return none
	return leg.hazards_near(tuning.f("road_draw_behind"), minf(tuning.f("road_draw_ahead"), visibility()))


func _signs_in_view() -> Array[Dictionary]:
	if not leg.active:
		var none: Array[Dictionary] = []
		return none
	var ahead: float = minf(tuning.f("road_draw_ahead"), visibility())
	var signs: Array[Dictionary] = leg.signs_near(ahead)
	if not run.active:
		return signs
	var par_ms: float = tuning.fi("gear_speeds", 2) / 3.6
	# The Exit is signed slip_sign_lead seconds ahead (GDD 9.5).
	if run.stage == RunState.Stage.LEG and _exit == EXIT_AHEAD:
		var to_exit: float = _exit_at - tuning.f("slip_sign_lead") * par_ms - car.s
		if to_exit >= 0.0 and to_exit <= ahead:
			signs.append({"kind": "exit", "ahead": to_exit, "stop": GameData.as_string(run.branch.get("stop"))})
	# The fork's overhead sign: for each branch its leg, modifier, stop and par.
	if run.fork_ahead():
		var to_fork: float = maxf(leg.length - tuning.f("fork_sign_lead") * par_ms, 0.0) - car.s
		if to_fork >= 0.0 and to_fork <= ahead:
			signs.append({"kind": "fork", "ahead": to_fork, "left": run.branches[RunState.LEFT], "right": run.branches[RunState.RIGHT]})
	return signs


## The slip lane the road view draws: the Exit's, or the side road's.
func _slip_in_view() -> Vector2:
	var slip: Vector2 = exit_slip()
	if slip.x >= 0.0:
		return slip
	return encounter.slip()


func _vehicle_snapshots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for vehicle: TrafficSim.Vehicle in traffic.vehicles:
		out.append({
			"id": vehicle.id,
			"type": vehicle.type_id,
			"x": vehicle.x,
			"ahead": vehicle.s - car.s,
			"direction": vehicle.direction,
			"signalling": vehicle.signalling,
			"role": vehicle.role,
		})
	return out


func _anchors_in_use() -> Array[StringName]:
	var out: Array[StringName] = []
	for index: int in hand.anchor_count():
		if hand.is_anchor_active(index):
			out.append(hand.anchor_id(index))
	return out


func _item_snapshots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for item: ItemSim.Item in items.items:
		out.append({
			"id": item.id,
			"slot": item.slot,
			"supply": item.supply,
			"hot": item.hot_left > 0.0,
			"burning": item.burning,
			"ash_fell": item.ash_fell,
			"craving": item.lapse_left >= 0.0,
		})
	return out


# --- Car ---------------------------------------------------------------------

## Every sideways push but the road's crown (GDD 5.4), m/s toward the right.
func _extra_drift() -> float:
	var push: float = car.curve_push(curve_k) - faults.param(FAULT_PULL, "drift_left", 0.0)
	if _gust_ticks_left > 0:
		_gust_ticks_left -= 1
		push += _gust_push
	return push


## Sandbox traffic: one vehicle every 1000 / free_traffic_per_km metres,
## spawn_ahead in front, in a lane and at a speed drawn from the road stream.
func _step_free_traffic() -> void:
	if car.s < _next_free_spawn_s:
		return
	_next_free_spawn_s = car.s + 1000.0 / free_traffic_per_km
	# Ordinary traffic only: not the police, a motorcade car or a hulk.
	var types: PackedStringArray = PackedStringArray()
	for candidate: Dictionary in data.records("vehicles"):
		if GameData.as_bool(candidate.get("traffic"), true):
			types.append(GameData.as_string(candidate.get("id")))
	if types.is_empty():
		return
	var record: Dictionary = data.record("vehicles", types[rng.range_i(Rng.ROAD, 0, types.size() - 1)])
	var speeds: Array = GameData.as_array(record.get("speed_kmh"))
	var lane: int = rng.range_i(Rng.ROAD, 0, car.lanes - 1)
	var at_s: float = car.s + tuning.f("spawn_ahead")
	if not traffic.lane_is_free(lane, at_s, tuning.f("free_traffic_clearance"), null):
		return
	var speed: float = rng.range_f(Rng.ROAD, GameData.as_float(speeds[0]), GameData.as_float(speeds[1]))
	traffic.spawn(StringName(GameData.as_string(record.get("id"))), lane, at_s, speed)


func _apply_collisions() -> void:
	if collision.hit != Collision.Hit.NONE:
		var drawn: Array[StringName] = faults.light(collision.hit_lamps)
		nerves.jolt()
		nerves.add(collision.hit_nerves)
		items.on_hit(collision.hit)
		if collision.hit_forces_gear:
			gate.force_gear(_forced_gear)
			if _lever_in_hand:
				_lever_in_hand = false
				hand.unpin()
		_emit("hit", {"kind": collision.hit, "lamps": drawn.size(), "vehicle": collision.hit_vehicle_id})
		if not drawn.is_empty():
			_emit("lamp_lit", {"lamps": faults.lamps, "lit": drawn.size(), "faults": drawn})
		if faults.is_wrecked() and not wrecked:
			wrecked = true
			_wreck_left = tuning.f("wreck_to_wheel")
			_emit("wreck", {"table": run.table, "act": run.act, "retellings": run.retellings})
	# A vehicle passed closely honks (a taxi), close call or not (GDD 5.5).
	if not collision.honk_vehicle_ids.is_empty():
		nerves.add(collision.honk_nerves)
		for vehicle_id: int in collision.honk_vehicle_ids:
			_emit("sfx_requested", {"id": "horn", "vehicle": vehicle_id})
	if collision.close_calls > 0:
		cash += collision.close_call_cash
		nerves.add(collision.close_call_nerves)
		_emit("close_call", {
			"count": collision.close_calls,
			"cash": collision.close_call_cash,
			"mult": collision.close_call_mult,
			"chain": collision.chain,
		})


# --- Nerves ------------------------------------------------------------------

## Everything that raises or lowers Nerves by the second (GDD 6.1), and what
## the meter needs to know before it steps.
func _feed_nerves() -> void:
	nerves.heavy_floor = heavy_floor()
	nerves.awake = effects.has(AWAKE)
	nerves.tremor_muted = effects.has(TREMOR_MUTE)

	var near: int = 0
	var nearest: float = INF
	for vehicle: TrafficSim.Vehicle in traffic.vehicles:
		var distance: float = Vector2(vehicle.s - car.s, vehicle.x - car.x).length()
		nearest = minf(nearest, distance)
		if distance <= _traffic_radius:
			near += 1
	nerves.add_rate(nerves.road_rate(near, nearest, in_encounter or encounter.active or pulled_over))
	if car.on_shoulder:
		nerves.add_rate(_shoulder_rate)
	nerves.add_rate(faults.param(FAULT_RATTLE, "nerves_per_s", 0.0))
	if car.on_rumble:
		nerves.jolt()


func _report_nerves() -> void:
	if nerves.snapped:
		_snapped = true
		_emit("snap", {"nerves": nerves.value})
		_emit("sfx_requested", {"id": "horn"})
		if gesture.is_active():
			gesture.cancel()
		if _lever_in_hand:
			gate.release()
			_lever_in_hand = false
			hand.unpin()
	for name: String in nerves.crossed:
		_emit("nerves_threshold_crossed", {"threshold": name.substr(1), "on": name.begins_with("+")})
	if nerves.yawned:
		_emit("sfx_requested", {"id": "yawn"})
	if nerves.yawned_long:
		_emit("sfx_requested", {"id": "yawn_long"})
	if nerves.blinked:
		_emit("blink", {})
	if nerves.nodded:
		_emit("nod", {})


func _report_effects() -> void:
	for id: StringName in effects.added:
		_emit("effect_added", {"effect": String(id)})
	for id: StringName in effects.expired:
		_emit("effect_expired", {"effect": String(id)})


# --- Rituals -----------------------------------------------------------------

## A press was applied at an anchor. `button_down` is false for a buffered
## click that was already released when the hand arrived.
func _begin_at(anchor: int, button_down: bool) -> void:
	if anchor == _lever_anchor and not sequential_shift:
		# The lever is held only by a button that is still down: a click that
		# ended during the reach must not take it and knock it out of gear.
		if button_down:
			gate.press()
			_lever_in_hand = true
			hand.pin()
		return
	# At a stop the vendor's tray comes first; the cabin is his as ever.
	var ritual: Dictionary = stop.ritual_at(String(hand.anchor_id(anchor))) if stopped else {}
	if ritual.is_empty():
		ritual = items.ritual_at(String(hand.anchor_id(anchor)))
	if ritual.is_empty():
		return
	var kind: Gesture.Kind = _gesture_kind(ritual)
	if kind == Gesture.Kind.NONE:
		return
	_active_ritual = ritual
	_active_anchor = anchor
	gesture.begin(kind, _gesture_amount(ritual, kind), _gesture_dirs(ritual))
	# Eyes-down rituals pull the eyes off the road while performed (GDD 4.7).
	hand.eyes_down = GameData.as_bool(ritual.get("eyes_down"))
	if kind == Gesture.Kind.DRAG_TO:
		# The object goes with the hand to the anchor the ritual names, or to
		# any of several (the slots a bought item can go in).
		hand.carrying = true
		_drag_destinations = []
		if ritual.has("to"):
			_drag_destinations.append(hand.anchor_index(StringName(GameData.as_string(ritual.get("to")))))
		for to: Variant in GameData.as_array(ritual.get("to_any")):
			var index: int = hand.anchor_index(StringName(GameData.as_string(to)))
			if index != HandSim.NO_ANCHOR:
				_drag_destinations.append(index)
		_sync_anchors()
	else:
		hand.pin()


func _resolve_gesture(button_down: bool) -> void:
	if _pinned_until_release and not button_down:
		_pinned_until_release = false
		hand.unpin()
	if gesture.phase == Gesture.Phase.ACTIVE:
		if gesture.kind == Gesture.Kind.DRAG_TO:
			# Released with the hand resting on the destination, the object is handed over.
			gesture.over_destination = hand.at_index != HandSim.NO_ANCHOR and _drag_destinations.has(hand.at_index)
			return
		if hand.at_index != _active_anchor:
			gesture.cancel()
		else:
			_run_drag_steps()
			return
	if gesture.phase == Gesture.Phase.DONE:
		_run_drag_steps()
		_complete_ritual()
	if gesture.phase != Gesture.Phase.IDLE:
		var carried: bool = gesture.kind == Gesture.Kind.DRAG_TO
		gesture.reset()
		_active_ritual = {}
		_active_anchor = HandSim.NO_ANCHOR
		hand.eyes_down = false
		hand.carrying = false
		_drag_destinations = []
		if carried or not button_down:
			hand.unpin()
		else:
			_pinned_until_release = true
		_sync_anchors()


func _run_drag_steps() -> void:
	if gesture.kind != Gesture.Kind.DRAG:
		return
	var steps: int = gesture.take_drag_steps()
	for _step: int in absi(steps):
		items.drag_step(_active_ritual, signi(steps))


func _complete_ritual() -> void:
	var ritual_id: String = GameData.as_string(_active_ritual.get("id"))
	if _active_anchor == _lever_anchor and sequential_shift:
		gate.shift_sequential(1 if gesture.direction == Gesture.DIR_UP else -1)
	elif ritual_id == StopSim.BUY:
		cash = stop.buy(String(hand.anchor_id(_active_anchor)), cash)
	elif ritual_id == StopSim.PLACE:
		stop.place(String(hand.anchor_id(_active_anchor)), String(hand.anchor_id(hand.at_index)))
	else:
		items.complete(_active_ritual, gesture.direction)
		if items.paid != &"":
			_pay_the_officer(items.paid)
	_emit("ritual_completed", {
		"ritual": ritual_id,
		"anchor": String(hand.anchor_id(_active_anchor)),
		"direction": gesture.direction,
	})


## The hand snaps only to anchors where something can be done now.
func _sync_anchors() -> void:
	for index: int in hand.anchor_count():
		var anchor: String = String(hand.anchor_id(index))
		var in_use: bool = items.anchor_in_use(anchor) or (stopped and stop.anchor_in_use(anchor))
		# What is carried can be put down where its ritual says.
		hand.set_anchor_active(index, in_use or (hand.carrying and _drag_destinations.has(index)))


func _gesture_kind(ritual: Dictionary) -> Gesture.Kind:
	match GameData.as_string(ritual.get("gesture")):
		"TAP":
			return Gesture.Kind.TAP
		"HOLD":
			return Gesture.Kind.HOLD
		"FLICK":
			return Gesture.Kind.FLICK
		"DRAG":
			return Gesture.Kind.DRAG
		"DRAG_TO":
			return Gesture.Kind.DRAG_TO
		"CRANK":
			return Gesture.Kind.CRANK
		"BEAD":
			return Gesture.Kind.BEAD
		"GATE":
			return Gesture.Kind.FLICK if sequential_shift else Gesture.Kind.NONE
	return Gesture.Kind.NONE


func _gesture_amount(ritual: Dictionary, kind: Gesture.Kind) -> float:
	if kind == Gesture.Kind.HOLD:
		return GameData.as_float(ritual.get("hold_s"))
	if kind == Gesture.Kind.CRANK:
		return GameData.as_float(ritual.get("turns"))
	if kind == Gesture.Kind.DRAG:
		return tuning.f("radio_step_px")
	return 0.0


func _gesture_dirs(ritual: Dictionary) -> int:
	if GameData.as_string(ritual.get("gesture")) == "GATE":
		return Gesture.DIR_UP | Gesture.DIR_DOWN
	var flags: int = 0
	for dir: Variant in GameData.as_array(ritual.get("flick_dirs")):
		match GameData.as_string(dir):
			"up":
				flags |= Gesture.DIR_UP
			"down":
				flags |= Gesture.DIR_DOWN
			"left":
				flags |= Gesture.DIR_LEFT
			"right":
				flags |= Gesture.DIR_RIGHT
	return flags


func _emit(type: String, payload: Dictionary) -> void:
	payload["type"] = type
	_announce(payload)


## Every event leaves the simulation through here, and only under a name the
## Events bus has (GDD 13.6).
func _announce(event: Dictionary) -> void:
	var type: String = GameData.as_string(event.get("type"))
	if not EventNames.ALL.has(type):
		push_error("DriveSim: '%s' is not a signal on the Events bus (GDD 13.6)" % type)
		return
	_events.append(event)
