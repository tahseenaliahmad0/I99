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
## Sources of Nerves a status can make him immune to (GDD 7.4).
const SOURCE_HONK: StringName = &"honk"
const SOURCE_TAILGATER: StringName = &"tailgater"
const SOURCE_DOUBT: StringName = &"doubt"
## Numbers a status carries in the effects registry (EffectSystem.product, total).
const ROAD_SPEED: String = "road_speed"
const TREMOR_SCALE: String = "tremor_scale"
const HEAVY_FLOOR: String = "heavy_floor"
const MUTES_PHANTOM: String = "mutes_phantom"
const CASH_PER_STACK: String = "close_call_cash_per_stack"
const GAIN_PER_STACK: String = "nerves_gain_per_stack"
const HIDES_COURAGE: String = "hides_courage"
const COURAGE: StringName = &"courage"
const PAINKILLERS: StringName = &"painkillers"
## The two parts of the weather cramp (GDD 7.9).
const HUM: String = "hum"
const CRAMPED: String = "cramp"

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
## The Phantom setting (GDD 17.1): off, there is no flinch and no cramp.
var phantom_enabled: bool = true
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
## A DRAG_TO in progress: where the object was taken up, how far from there
## it has been carried (in all, and sideways), and how far its ritual wants.
var _carry_from: Vector3 = Vector3.ZERO
var _carry_out: float = 0.0
var _carry_across: float = 0.0
var _carry_out_needed: float = 0.0
var _carry_across_needed: float = 0.0
## The TAP that a HOLD begun at the same anchor turns into when the button
## is let go within a TAP's time (ItemSim.tap_alternative).
var _tap_instead: Dictionary = {}
## The tick's length for everything outside the cabin: the car, the road,
## traffic, encounters. Shorter than DT while he has Focus (GDD 7.4).
var _road_dt: float = DT
## Seconds he has swayed since Courage began (GDD 5.4), and this tick's push.
var _sway_time: float = 0.0
var _sway: float = 0.0
## Where each anchor is by the data, before anything in the cabin moves it.
var _anchor_home: PackedVector3Array = PackedVector3Array()
## The state of the cabin (ItemSim.cabin_serial) that the systems were last
## fitted to, and what was read from it then.
var _cabin_seen: int = -1
var _wheel_keys: bool = false
var _auto_indicate: bool = false
var _hook_keeps_lane: bool = false
var _pad_horn_was: bool = false
var _pad_wiper_was: bool = false
## Where the car was along the road when the tick began.
var _car_s_then: float = 0.0
var _close_call_mult: float = 1.0
var _lag_sources: float = 0.0
## The weather cramp (GDD 7.9): "" (none), "hum" (it is coming) or "cramp",
## and the seconds left of that.
var cramp: String = ""
var _cramp_left: float = 0.0
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
	items.configure(data, effects, nerves, traffic, car, faults, rng)
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
	_tap_instead = {}
	_road_dt = DT
	_sway_time = 0.0
	_sway = 0.0
	_pad_horn_was = false
	_pad_wiper_was = false
	_car_s_then = 0.0
	cramp = ""
	_cramp_left = 0.0
	_anchor_home = PackedVector3Array()
	for index: int in hand.anchor_count():
		_anchor_home.append(hand.anchor_position(index))
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
	_fit_cabin()


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

	# Focus (GDD 7.4): the road runs slower, the hand does not.
	_road_dt = DT * effects.product(ROAD_SPEED)
	_apply_statuses()

	# 1. Gesture recogniser.
	gesture.step(DT, input.lmb, input.pointer_delta)

	# 2. Hand.
	hand.can_reach = nerves.snap_left <= 0.0
	hand.flinches = phantom_enabled and not phantom_muted() and (nerves.value >= tuning.f("phantom_flinch_from") or nerves.lids > 0.0)
	hand.frozen = cramp == CRAMPED
	hand.step(DT, input, wheel.angle, _pound_mult if nerves.pound else 1.0)

	# 3. Rituals. A cramped hand can neither let go nor take hold (GDD 7.9).
	_resolve_gesture(input.lmb)
	if _lever_in_hand and not input.lmb and not hand.frozen:
		gate.release()
		_lever_in_hand = false
		hand.unpin()
	if hand.press_applied and hand.can_reach and not hand.frozen:
		_begin_at(hand.at_index, input.lmb)
	# His eyes are down while an eyes-down ritual is performed, and from the
	# first TAP of an answer for as long as his hand stays on the phone.
	hand.eyes_down = (gesture.is_active() and GameData.as_bool(_active_ritual.get("eyes_down"))) or _dialling_here()
	_step_wheel_keys(input)

	# 4. Wheel.
	if hand.let_go:
		wheel.release()
		if effects.has_own(ItemSim.HOOK_ARMED):
			# The hook, hung in its ring, takes the wheel as his hand leaves it
			# (GDD 7.6): for hook_lock_s at most.
			effects.hold(ItemSim.HOOK_ARMED, ItemSim.HOOK, false)
			effects.add(ItemSim.HOOK_SET, items.passive("hook_lock_s"))
	if hand.took_grip:
		wheel.grip()
		effects.remove(ItemSim.HOOK_SET)
	wheel.locked = effects.has_own(ItemSim.HOOK_SET)
	if wheel.locked and _hook_keeps_lane and curve_k == 0.0:
		wheel.hold_at(_lane_keeping_angle())
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
	_car_s_then = car.s
	if not _standing():
		car.step(_road_dt, wheel.steer(), gate.gear, _braking, _extra_drift())
	if _auto_indicate:
		_indicate_for_lane_change()
	_step_cramp()
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
		leg.step_traffic(_road_dt)
		traffic.step(_road_dt, car.s, car.x, car.speed)
		_step_oncoming()

	# 7. Collisions and close calls.
	var lamps_before: int = faults.lamps
	if not _standing():
		collision.step(_road_dt, car, traffic, gate.gear)
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
	var act_before: int = act
	act = GameData.as_int(plan.get("act"), act)
	if act != act_before:
		items.begin_act()
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
	leg.step_road(_road_dt, DT)
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
	items.finish_mending()
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
	items.finish_mending()
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
		"leg_state": items.leg_state(),
		"item_state": items.telling_state(),
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
		# What he did once this leg stays done, and what lasts to its end lasts.
		items.set_leg_state(GameData.as_dict(telling.get("leg_state")))
		# Whatever the leg's encounter was, it is behind him.
		encounter.stop()
	else:
		# At the end of the act's boss.
		var boss: Dictionary = run.boss_record()
		_set_stretch(RunGenerator.blank_plan(run.act, GameData.as_int(boss.get("lanes"), RunGenerator.ROAD_LANES),
				GameData.as_bool(boss.get("divided"), true), GameData.as_float(boss.get("length_m")), GameData.as_float(boss.get("par_s"))))
		car.s = leg.length
		leg.stop()
	# (After the stretch is set: a new act would otherwise seem to begin here.)
	items.set_telling_state(GameData.as_dict(telling.get("item_state")))
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
	encounter.tell_shift = items.passive("mirror_lead_s") - faults.param(FAULT_MIRROR, "mirror_tell_delay_s", 0.0)
	encounter.step(_road_dt, _braking, gate.gear)
	nerves.add_rate(encounter.nerves_rate - encounter.tail_nerves_rate)
	fray_rate(SOURCE_TAILGATER, encounter.tail_nerves_rate)
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
		suspicion.add(tuning.f("suspicion_honk") + items.passive("horn_suspicion_more"))
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
	leg.step_hazards(_road_dt)
	if leg.hits.is_empty():
		return
	nerves.add(leg.hazard_nerves)
	car.speed *= leg.speed_factor
	for kind: StringName in leg.hits:
		_emit("sfx_requested", {"id": "scrape", "hazard": String(kind)})


## Puts an item in the cabin outside a stop (debug key F5, a Table's starting
## cabin, a gift): in `slot`, or in the first free slot it fits, else in the
## first it fits. What was in the slot is taken out, and so is one he already
## has. Null when the item is unknown or does not fit the slot named.
func give_item(id: StringName, slot: StringName = &"") -> ItemSim.Item:
	if not data.has_record("items", String(id)):
		push_error("DriveSim: unknown item '%s'" % id)
		return null
	var slots: Array = GameData.as_array(data.record("items", String(id)).get("slots"))
	var place: StringName = slot
	if place == &"":
		for candidate: Variant in slots:
			if items.item_in_slot(StringName(GameData.as_string(candidate))) == null:
				place = StringName(GameData.as_string(candidate))
				break
		if place == &"" and not slots.is_empty():
			place = StringName(GameData.as_string(slots[0]))
	elif not slots.has(String(place)):
		return null
	items.remove_item(items.item(id))
	if place != &"":
		items.remove_item(items.item_in_slot(place))
	var given: ItemSim.Item = items.add_item(id, place)
	_fit_cabin()
	return given


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
	return _heavy_floors[index] + heavy_floor_bonus + effects.total(HEAVY_FLOOR)


## How far he can see along the road, in metres (GDD 9.1, 9.4): the
## headlight cone at night, the dust in a dust haze, else no limit (INF).
func visibility() -> float:
	if not leg.active:
		return INF
	var reach: float = leg.dust_visibility
	if leg.night:
		# What makes the night darker for him shortens what he sees of it
		# (GDD 7.5, 7.7: cracked sunglasses, tinted glass).
		reach = minf(reach, headlight_cone() * maxf(1.0 - items.passive("night_darker"), 0.0))
	# Fog lamps reach further into whatever limits his view (GDD 7.6).
	return reach * items.passive("visibility_mult") if reach < INF else reach


## The Glare on his view now, 0 to 1 (GDD 5.8), after what he wears against it.
func glare() -> float:
	return encounter.glare * items.passive("glare_mult")


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
		"carrying": _carried(),
		"view_block": GameData.as_string(_active_ritual.get("blocks_view")) if gesture.is_active() else "",
		"courage": courage(),
		"cramp": cramp,
		"ghost_at": hand.anchor_id(hand.ghost_anchor),
		"ghost_progress": 1.0 - hand.flinch_left / maxf(tuning.f("phantom_flinch_delay"), 0.001) if hand.ghost_anchor != HandSim.NO_ANCHOR else 0.0,
		"hook": "set" if effects.has_own(ItemSim.HOOK_SET) else ("armed" if effects.has_own(ItemSim.HOOK_ARMED) else ("cooling" if effects.has_own(ItemSim.HOOK_COOLDOWN) else "")),
		"anchor_moves": items.anchor_moves(),
		"mirror_scale": items.passive("mirror_scale"),
		"mirror_shift": encounter.tell_shift,
		"caller": String(items.caller),
		"ring_left": items.ring_left,
		"call_taps": items.call_taps,
		"sway": _sway,
		"lag": wheel.lag,
		"steer_angle": wheel.lagged_angle(),
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
		"glare": glare(),
		"night_darker": items.passive("night_darker") if leg.active and leg.night else 0.0,
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


## True while he is answering the phone with his hand on it.
func _dialling_here() -> bool:
	if not items.dialling() or hand.at_index == HandSim.NO_ANCHOR:
		return false
	var handset: ItemSim.Item = items.phone()
	return handset != null and String(hand.anchor_id(hand.at_index)) == items.anchor_of(handset)


## What the hand is carrying in a DRAG_TO: an item's id, or the ritual's
## (his licence, banknotes); "" with an empty hand.
func _carried() -> String:
	if not hand.carrying:
		return ""
	if GameData.as_string(_active_ritual.get("id")) == StopSim.PLACE:
		var offer: StopSim.Offer = stop.offer_at(String(hand.anchor_id(_active_anchor)))
		return offer.id if offer != null else ""
	if _active_ritual.has("item"):
		return GameData.as_string(_active_ritual.get("item"))
	return GameData.as_string(_active_ritual.get("id"))


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
			"warbling": items.warbling(item),
			"contraband": GameData.as_bool(item.record.get("contraband")),
		})
	return out


# --- Car ---------------------------------------------------------------------

## Every sideways push but the road's crown (GDD 5.4), m/s toward the right.
func _extra_drift() -> float:
	var push: float = car.curve_push(curve_k) - faults.param(FAULT_PULL, "drift_left", 0.0)
	if _gust_ticks_left > 0:
		_gust_ticks_left -= 1
		push += _gust_push
	# Sway (GDD 5.4): sway_per_stack per Courage stack, swinging at
	# sway_frequency from the moment Courage began.
	var stacks: int = courage()
	if stacks > 0:
		_sway = tuning.f("sway_per_stack") * float(stacks) * sin(TAU * tuning.f("sway_frequency") * _sway_time)
		_sway_time += DT
	else:
		_sway = 0.0
		_sway_time = 0.0
	return push + _sway


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
		# The charm turns the first scrape of a leg aside: no lamp (GDD 7.5).
		var spared: bool = collision.hit == Collision.Hit.SCRAPE and items.absorbs_scrape()
		var drawn: Array[StringName] = faults.light(0 if spared else collision.hit_lamps)
		nerves.jolt()
		nerves.add(collision.hit_nerves)
		items.on_hit(collision.hit)
		items.on_faults_lit(drawn)
		if collision.hit_forces_gear:
			gate.force_gear(_forced_gear)
			if _lever_in_hand:
				_lever_in_hand = false
				hand.unpin()
		_emit("hit", {"kind": collision.hit, "lamps": drawn.size(), "vehicle": collision.hit_vehicle_id, "spared": spared})
		if not drawn.is_empty():
			_emit("lamp_lit", {"lamps": faults.lamps, "lit": drawn.size(), "faults": drawn})
		if faults.is_wrecked() and not wrecked:
			wrecked = true
			_wreck_left = tuning.f("wreck_to_wheel")
			_emit("wreck", {"table": run.table, "act": run.act, "retellings": run.retellings})
	# A vehicle passed closely honks (a taxi), close call or not (GDD 5.5).
	if not collision.honk_vehicle_ids.is_empty():
		nerves.add(collision.honk_nerves - collision.honk_frights)
		fray(SOURCE_HONK, collision.honk_frights)
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
	nerves.tremor_scale = effects.product(TREMOR_SCALE)

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


## Reads what the things in the cabin change by being there into the
## systems they change (GDD 7.5 to 7.7), and puts every anchor where the
## cabin now has it. Runs whenever the cabin has changed.
func _fit_cabin() -> void:
	_cabin_seen = items.cabin_serial
	wheel.turn_rate_mult = items.passive("turn_rate_mult")
	wheel.return_rate_mult = items.passive("return_rate_mult")
	car.lat_speed_mult = items.passive("lat_speed_mult")
	gate.has_fifth = items.passive("fifth_gear") > 0.0
	faults.set_capacity_bonus(roundi(items.passive("lamp_capacity")))
	collision.cash_bonus = items.passive("close_call_bonus")
	car.high_gear_bonus = items.passive("high_gear_bonus")
	car.brake_mult = items.passive("brake_mult")
	suspicion.gain_mult = items.passive("suspicion_gain_mult")
	_close_call_mult = items.passive("close_call_mult")
	_lag_sources = items.passive("lag_sources")
	_wheel_keys = items.passive("wheel_keys") > 0.0
	_auto_indicate = not items.pair("auto_indicate").is_empty()
	_hook_keeps_lane = not items.pair("hook_holds_lane").is_empty()
	var moves: Dictionary = items.anchor_moves()
	for index: int in hand.anchor_count():
		var id: String = String(hand.anchor_id(index))
		hand.set_anchor_position(index, GameData.as_vec3(moves[id]) if moves.has(id) else _anchor_home[index])
	_sync_anchors()


## The thumb keypad (GDD 7.6): the horn and the wipers under the thumb of
## the hand that grips. Each press is one honk or one sweep.
func _step_wheel_keys(input: DriveInput) -> void:
	if _wheel_keys and hand.gripping and nerves.snap_left <= 0.0:
		if input.pad_horn and not _pad_horn_was:
			_use_control("horn", 0)
		if input.pad_wiper and not _pad_wiper_was:
			_use_control("wipers", Gesture.DIR_UP)
	_pad_horn_was = input.pad_horn
	_pad_wiper_was = input.pad_wiper


## A control used without the hand going to it.
func _use_control(ritual_id: String, direction: int) -> void:
	var ritual: Dictionary = data.record("rituals", ritual_id)
	items.complete(ritual, direction)
	_emit("ritual_completed", {"ritual": ritual_id, "anchor": GameData.as_string(ritual.get("anchor")), "direction": direction, "keypad": true})


## The angle at which the wheel keeps the car in the middle of its lane on a
## straight: against whatever carries it sideways, and back toward the
## middle within hook_settle_time (GDD 7.8, Wheel ring + Spinner knob).
func _lane_keeping_angle() -> float:
	var authority: float = car.lat_authority()
	if authority <= 0.0:
		return wheel.angle
	var lane: int = clampi(car.lane_of(car.x), 0, car.lanes - 1)
	var wanted: float = (car.lane_center(lane) - car.x) / tuning.f("hook_settle_time") - car.drift
	return clampf(wanted / authority, -1.0, 1.0) * wheel.max_angle()


## Crossover stalk + Thumb keypad (GDD 7.8): he indicates as a lane change
## begins: when the side of the car is over a lane line, with a lane beyond
## it, and the car is moving that way.
func _indicate_for_lane_change() -> void:
	var lane: int = clampi(car.lane_of(car.x), 0, car.lanes - 1)
	var off: float = car.x - car.lane_center(lane)
	var room: float = car.lane_width() * 0.5 - car.half_width()
	var moving: float = car.v_lat + car.drift
	var way: int = 0
	if off > room and moving > 0.0:
		way = 1
	elif off < -room and moving < 0.0:
		way = -1
	if way == 0 or items.indicator == way or lane + way < 0 or lane + way >= car.lanes:
		return
	items.indicate(way)
	_emit("sfx_requested", {"id": "indicator_tick"})


## Oncoming vehicles met this tick (GDD 4.6, 7.6): each one adds Nerves when
## he drives on high beam, and flashes back at his fog lamps.
func _step_oncoming() -> void:
	if car.divided:
		return
	var each: float = (tuning.f("high_beam_nerves") if items.flag(FLAG_HIGH_BEAM) else 0.0) + items.passive("flash_back_nerves")
	if each <= 0.0:
		return
	for vehicle: TrafficSim.Vehicle in traffic.vehicles:
		if vehicle.direction < 0 and vehicle.s_then >= _car_s_then and vehicle.s < car.s:
			nerves.add(each)


## What his statuses do to the other systems this tick (GDD 7.4, Courage):
## each stack pays close calls better, dulls what frays him, and makes one
## more source of Lag.
func _apply_statuses() -> void:
	if items.cabin_serial != _cabin_seen:
		_fit_cabin()
	nerves.gain_mult = maxf(1.0 + effects.total(GAIN_PER_STACK, true), 0.0)
	collision.cash_mult = (1.0 + effects.total(CASH_PER_STACK, true)) * _close_call_mult
	var lag_ms: float = tuning.f("lag_per_source") * (float(courage()) + _lag_sources)
	# Flask + Painkillers (GDD 7.8): with Courage on top of the pills, Lag
	# doubles and close-call cash doubles.
	if courage() > 0 and effects.has_own(PAINKILLERS):
		var numb: Dictionary = items.pair("numb_courage")
		if not numb.is_empty():
			lag_ms *= GameData.as_float(numb.get("amount"))
			collision.cash_mult *= GameData.as_float(numb.get("amount"))
	wheel.lag = minf(lag_ms, tuning.f("lag_cap")) * 0.001


## Courage stacks now (GDD 7.4).
func courage() -> int:
	return effects.stacks(COURAGE)


## The Courage a policeman notices: none while something hides it (breath
## mints), else every stack (GDD 7.4, 10.2).
func courage_noticed() -> int:
	return 0 if effects.total(HIDES_COURAGE) > 0.0 else courage()


## The Papers phase of a checkpoint (GDD 10.2, 7.7): forged papers pass it by
## themselves, once. True when he had them; they are gone then.
func use_forged_papers() -> bool:
	if not items.use_pass("papers"):
		return false
	_fit_cabin()
	return true


## The weather cramp (GDD 7.9): once in a Rain leg and in a Night leg, as
## the car passes a fixed point of it. A hum for phantom_cramp_hum, then for
## phantom_cramp_length the hand can neither let go nor take hold, and
## phantom_cramp_nerves. Muted or switched off, nothing happens.
func _step_cramp() -> void:
	if cramp == "":
		if not leg.active or not (leg.raining or leg.night) or _standing():
			return
		var point: float = leg.length * tuning.f("phantom_cramp_at")
		if _car_s_then < point and car.s >= point and phantom_enabled and not phantom_muted():
			cramp = HUM
			_cramp_left = tuning.f("phantom_cramp_hum")
			_emit("sfx_requested", {"id": "phantom_hum"})
		return
	if not phantom_enabled or phantom_muted():
		cramp = ""
		_cramp_left = 0.0
		return
	_cramp_left -= DT
	if _cramp_left >= DT * 0.5:
		return
	if cramp == HUM:
		cramp = CRAMPED
		_cramp_left = tuning.f("phantom_cramp_length")
		nerves.add(tuning.f("phantom_cramp_nerves"))
	else:
		cramp = ""
		_cramp_left = 0.0


## True while something he took mutes the Phantom (GDD 7.9: painkillers,
## for the leg).
func phantom_muted() -> bool:
	return effects.total(MUTES_PHANTOM) > 0.0


## Nerves from a named source (a honk, a tailgater, a Doubt): a gain is not
## felt while a status makes him immune to that source (GDD 7.4).
func fray(source: StringName, amount: float) -> void:
	if amount > 0.0 and effects.immune_to(source):
		return
	nerves.add(amount)


## The same for a source that works by the second.
func fray_rate(source: StringName, per_second: float) -> void:
	if per_second > 0.0 and effects.immune_to(source):
		return
	nerves.add_rate(per_second)


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
	if effects.expired.has(ItemSim.HOOK_SET):
		# The hook is out of its ring: it cannot be set again for a while.
		effects.add(ItemSim.HOOK_COOLDOWN, items.passive("hook_cooldown_s"))
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
	_tap_instead = items.tap_alternative(String(hand.anchor_id(anchor)), ritual)
	gesture.begin(kind, _gesture_amount(ritual, kind), _gesture_dirs(ritual))
	# Eyes-down rituals pull the eyes off the road while performed (GDD 4.7).
	hand.eyes_down = GameData.as_bool(ritual.get("eyes_down"))
	if kind == Gesture.Kind.DRAG_TO:
		# The object goes with the hand to the anchor the ritual names, or to
		# any of several (the slots a bought item can go in).
		hand.carrying = true
		_drag_destinations = []
		_carry_from = hand.anchor_position(anchor)
		_carry_out = 0.0
		_carry_across = 0.0
		_carry_out_needed = GameData.as_float(ritual.get("out_m"))
		_carry_across_needed = GameData.as_float(ritual.get("across_m"))
		if GameData.as_string(ritual.get("to")) == ItemSim.SLOT_ANCHOR:
			# Out and back in: it goes back where it was taken from.
			_drag_destinations.append(anchor)
		elif ritual.has("to"):
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
			# Released with the hand resting on the destination, the object is
			# handed over: once it has been carried as far as its ritual wants
			# (a tape out of the deck, a tissue across the glass). A ritual
			# with no destination is done wherever the hand lets go.
			_carry_out = maxf(_carry_out, hand.pos.distance_to(_carry_from))
			_carry_across = maxf(_carry_across, absf(hand.pos.x - _carry_from.x))
			var there: bool = _drag_destinations.is_empty() or (hand.at_index != HandSim.NO_ANCHOR and _drag_destinations.has(hand.at_index))
			gesture.over_destination = there and _carry_out >= _carry_out_needed and _carry_across >= _carry_across_needed
			return
		if hand.at_index != _active_anchor:
			gesture.cancel()
		else:
			_run_drag_steps()
			return
	if gesture.phase == Gesture.Phase.DONE:
		_run_drag_steps()
		_complete_ritual()
	elif gesture.phase == Gesture.Phase.CANCELLED and gesture.kind == Gesture.Kind.HOLD and not _tap_instead.is_empty() \
			and not button_down and hand.at_index == _active_anchor and gesture.elapsed <= tuning.f("tap_max_time") + DT * 0.5:
		# Let go within a TAP's time: it was the TAP that is offered there too.
		_active_ritual = _tap_instead
		_complete_ritual()
	if gesture.phase != Gesture.Phase.IDLE:
		var carried: bool = gesture.kind == Gesture.Kind.DRAG_TO
		gesture.reset()
		_active_ritual = {}
		_active_anchor = HandSim.NO_ANCHOR
		_tap_instead = {}
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
