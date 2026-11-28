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
const FLAG_HAZARDS: StringName = &"hazards"
## Set while the prologue plays: the new photo lies on the dash (GDD 10.1).
const FLAG_PROLOGUE: StringName = &"prologue"
const PULLED_OVER: StringName = &"pulled_over"
const LAW: StringName = &"law"
## Statuses a set piece holds: the phone in his pocket rings (GDD 10.4); he
## stands in the bay (GDD 10.5).
const THE_CALL: StringName = &"the_call"
const IN_BAY: StringName = &"in_bay"
## The soldier is at his window with his sign up (GDD 10.2).
const AT_WINDOW: StringName = &"at_window"
const BANKNOTES: StringName = &"banknotes"
const SET_PIECE: StringName = &"set_piece"
const NOOR: String = "noor"
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
## What the tea is tagged (the Drummer passes it, GDD 8.2).
const TEA: String = ItemSim.TAG_TEA
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
## The set piece that ends the act, while he is in it (GDD 10).
var boss: BossSim = BossSim.new()
var suspicion: SuspicionSim = SuspicionSim.new()
var clock: ClockSim = ClockSim.new()
var rng: Rng = Rng.new()
## The Telling he is in, if any (GDD 11.1); the sandbox and single legs have none.
var run: RunState = RunState.new()
## The stop he is at (GDD 9.6).
var stop: StopSim = StopSim.new()
## Who rides in the seat (GDD 8).
var passengers: PassengerSim = PassengerSim.new()
## The key is turned in the bay (GDD 10.5): the engine is off, the car and
## the Clock stand. Any road begun anew starts it again.
var parked: bool = false

var tick: int = 0
## Thousands of dinars (GDD 6). Never below zero.
var cash: float = 0.0
## True once every lamp is lit: the Telling is over (GDD 6.3).
var wrecked: bool = false
## The act, 1 to 3: it sets the Heavy floor (GDD 6.1).
var act: int = 1
## Added to the Heavy floor (a Table's rule, painkillers).
var heavy_floor_bonus: float = 0.0
## The rules of the Table this Telling is told to (GDD 11.2); the base rules
## on a road that belongs to no Telling.
var table: TableRules = TableRules.new()
## Free rewinds he still has (GDD 11.2, the Children's Table): a Wreck then
## returns him to the start of the leg or boss he is on.
var rewinds_left: int = 0
## The Telling as it was when that leg or boss began ({} when no rewind is
## left to need it). It is kept in memory only: nothing is saved in a leg.
var _leg_start: Dictionary = {}
## The mode he is driving (GDD 11.5): Save.COMMUTE, Save.ENDLESS_NIGHT, or
## "" for a Telling and everything else.
var mode: String = ""
## The mode's road has ended: he arrived at the Commute's end, or wrecked.
var mode_over: bool = false
## Metres of Endless Night that are behind him in the legs he has finished.
var _mode_behind: float = 0.0
var _mode_seed: int = 0
var _mode_legs: int = 0
## The prologue's clock (GDD 10.1), while it plays.
var prologue: PrologueSim = PrologueSim.new()
## The Telling that begins when the prologue is over: tonight.
var _prologue_table: String = ""
var _prologue_seed: int = 0
## The lane the left hand keeps the car in.
var _prologue_lane: int = 0
## What the Table says while he tells it (GDD 11.3).
var heckles: HeckleDirector = HeckleDirector.new()
## False: nobody heckles (a road told to no Table: the modes of GDD 11.5; a
## test of something else).
var heckling: bool = true
## The passengers he has carried to Basra, who sit at the Tables now and
## heckle too (GDD 11.5). It is the profile's, and is set before a Telling
## begins.
var guests: PackedStringArray = []
## The Twist the leg he is on was laid out with ({} for none), for the save.
var _leg_twist: Dictionary = {}
## Which of the vehicles on the road were ahead of the car a tick ago, by id
## (kept while a heckle counts the ones he passes).
var _ahead_then: Dictionary = {}
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
## Brake assist (GDD 17.1): "Slows the car when a crash is certain."
var brake_assist: bool = false
## Steady start (GDD 17.1): "The wheel holds itself for the first 2 s after
## each stop."
var steady_start: bool = true
## Seconds of that hold which are left.
var _steady_left: float = 0.0
## True in a tick in which Brake assist is on the brake for him.
var assisted_brake: bool = false
## Grip mode: false = hold, true = click to grip, click to release.
var grip_toggle: bool = false:
	set(value):
		grip_toggle = value
		hand.grip_toggle = value

## When set, every tick's input is written to it (GDD 13.3): replaying the
## log into a simulation started the same way gives the same state hash.
var input_log: InputLog = null
## What the last stop saved: the Telling as the save file holds it (GDD 13.7).
## It changes only when the car comes to a stop, never during a leg; and it
## is empty again once the Telling is told again after a Wreck (GDD 11.4).
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
## The Heavy floor of the road he is on, where the road says its own (Dawn
## and the street of the Arrival, GDD 6.1); -1: the act's.
var _floor_of_road: float = -1.0
## His wrist is on the wheel (the Call taken alone).
var _wrist_on_wheel: bool = false
var _in_bay: bool = false
var _at_window: bool = false
## The weather cramp (GDD 7.9): "" (none), "hum" (it is coming) or "cramp",
## and the seconds left of that.
var cramp: String = ""
var _cramp_left: float = 0.0
## Seconds the gust still has to push, of the road's time (under Focus that is
## longer by his clock): a gust lasts a whole number of ticks.
var _gust_left: float = 0.0
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
## Where along the road he is on the car came onto it: its start, or the
## stall he pulled away from. (A sign that would stand before that place is
## one he has never been ahead of.)
var _road_from: float = 0.0
## Seconds the hand has held the wheel at a stop: stop_leave_grip of it leaves.
var _leave_grip: float = 0.0
## The hand has been off the wheel since he stopped: only then can a grip leave.
var _let_go_at_stop: bool = false
## The side of the last fork he took (RunState.LEFT or RIGHT).
var _side: int = RunState.RIGHT
## The shady guy is at the stop he stands at.
var _shady_here: bool = false
## The passenger who got out at the stop he stands at ("" for nobody): they
## do not stand at its roadside asking for a ride (GDD 8.1).
var _left_here: String = ""
## Seconds until a wrecked Telling is told again.
var _wreck_left: float = 0.0
## The angle the wheel had when his hand last let go of it, and the seconds
## for which a passenger asked to hold the wheel "at its current angle" still
## takes it back there (GDD 8.2; 0: no longer).
var _let_go_angle: float = 0.0
var _catch_left: float = 0.0


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
	boss = BossSim.new()
	suspicion = SuspicionSim.new()
	clock = ClockSim.new()
	run = RunState.new()
	stop = StopSim.new()
	passengers = PassengerSim.new()
	heckles = HeckleDirector.new()
	prologue = PrologueSim.new()
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
	boss.configure(data, car, rng, traffic)
	suspicion.configure(tuning)
	clock.configure(tuning)
	run.configure(data)
	stop.configure(data, items, faults, nerves, clock, rng)
	passengers.configure(data, effects, nerves, items, faults)
	heckles.configure(data, items)
	prologue.configure(tuning)
	_steady_left = 0.0
	assisted_brake = false
	mode = ""
	mode_over = false
	_mode_behind = 0.0
	_mode_legs = 0
	_leg_twist = {}
	_ahead_then = {}

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
	_floor_of_road = -1.0
	_wrist_on_wheel = false
	_in_bay = false
	_at_window = false
	cramp = ""
	_cramp_left = 0.0
	_anchor_home = PackedVector3Array()
	for index: int in hand.anchor_count():
		_anchor_home.append(hand.anchor_position(index))
	_gust_left = 0.0
	_gust_push = 0.0
	_braking = false
	_next_free_spawn_s = 0.0
	_snapped = false
	_leg_lamps_lit = 0
	_exit = EXIT_NONE
	_road_from = 0.0
	_leave_grip = 0.0
	_let_go_at_stop = false
	_side = RunState.RIGHT
	_shady_here = false
	_left_here = ""
	_wreck_left = 0.0
	_let_go_angle = 0.0
	_catch_left = 0.0
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
		if _can_rewind():
			_rewind()
		else:
			_retell()
	gate.begin_tick()
	nerves.begin_tick()
	effects.begin_tick()
	items.begin_tick()
	leg.begin_tick()
	encounter.begin_tick()
	boss.begin_tick()
	suspicion.begin_tick()
	suspicion.gain_mult = _suspicion_gain()
	passengers.begin_tick()
	heckles.begin_tick()
	prologue.begin_tick()

	# Focus (GDD 7.4): the road runs slower, the hand does not.
	_road_dt = DT * effects.product(ROAD_SPEED)
	_apply_statuses()

	# 1. Gesture recogniser.
	gesture.step(DT, input.lmb, input.pointer_delta)

	# 2. Hand. In a Snap, and while he talks on the phone, he can steer and
	# cannot reach (GDD 6.1, 10.4).
	hand.can_reach = nerves.snap_left <= 0.0 and not boss.talking()
	hand.at_ear = boss.phone_in_hand()
	hand.wrist_steer = boss.wrist_steer
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
	if _catch_left > 0.0:
		_catch_left -= DT
		if _catch_left < DT * 0.5:
			_catch_left = 0.0
	if hand.let_go:
		wheel.release()
		# From here it returns to its centre (GDD 4.3). A passenger who holds
		# the wheel "at its current angle" can be asked for this angle for a
		# moment yet (GDD 8.2; D-043 has the hook wait for the let-go for the
		# same reason).
		_let_go_angle = wheel.angle
		_catch_left = passengers.catch_time()
		if effects.has_own(ItemSim.HOOK_ARMED):
			# The hook, hung in its ring, takes the wheel as his hand leaves it
			# (GDD 7.6): for hook_lock_s at most.
			effects.hold(ItemSim.HOOK_ARMED, ItemSim.HOOK, false)
			effects.add(ItemSim.HOOK_SET, items.passive("hook_lock_s"))
	if hand.took_grip:
		wheel.grip()
		effects.remove(ItemSim.HOOK_SET)
		# Whoever held the wheel for him lets go of it.
		passengers.wheel_taken()
		# And a car that stood on after the Call is his to drive again.
		boss.wheel_taken()
	if hand.at_ear != _wrist_on_wheel:
		# The Call taken alone: his wrist is on the wheel while his hand holds
		# the phone to his ear (GDD 10.4).
		_wrist_on_wheel = hand.at_ear
		if _wrist_on_wheel:
			wheel.grip()
		elif not hand.gripping:
			wheel.release()
	if _steady_left > 0.0 and not _standing():
		_steady_left = maxf(_steady_left - DT, 0.0)
	wheel.locked = effects.has_own(ItemSim.HOOK_SET) or passengers.holds_wheel() or ghost_on_wheel() or left_hand_on_wheel() or steady_holds()
	if steady_holds():
		# Steady start (GDD 17.1): the wheel holds itself, straight.
		wheel.hold_at(_straight_angle())
	elif left_hand_on_wheel():
		# The prologue (GDD 10.1): "A solid left arm holds the wheel and
		# keeps the lane by itself."
		wheel.hold_at(_lane_keeping_angle(_prologue_lane))
	elif passengers.holds_straight():
		# Held dead straight for him (GDD 8.2): against the road's crown and
		# whatever else pulls steadily, so that on a straight the car keeps
		# its line. A curve or a gust still carries it off.
		wheel.hold_at(_straight_angle())
	elif passengers.holds_wheel():
		# Held for him at an angle (GDD 8.2): the one he was asked for.
		wheel.hold_at(passengers.held_angle)
	elif ghost_on_wheel():
		# The Fib (GDD 11.3): "A ghost left hand holds the lane", bends and
		# all, while his own hand is elsewhere.
		wheel.hold_at(_lane_keeping_angle())
	elif wheel.locked and _hook_keeps_lane and curve_k == 0.0:
		wheel.hold_at(_lane_keeping_angle())
	wheel.tremor = nerves.tremor_offset
	wheel.step(DT, hand.steer_px, steer_sensitivity)

	# 5. Car: gear, speed, sideways motion, drift.
	if passengers.blocks_lever() and _lever_in_hand:
		# He leans across the lever (GDD 8.2): the hand is off it.
		gate.release()
		_lever_in_hand = false
		hand.unpin()
	_step_leg_road()
	gate.step(DT, input.pointer_delta if _lever_in_hand else Vector2.ZERO,
			faults.param(FAULT_CLUTCH, "lever_speed_mult", 1.0))
	if gate.ground:
		nerves.add(_grind_nerves)
		_emit("sfx_requested", {"id": "grind"})
	assisted_brake = brake_assist and not input.rmb and _crash_is_certain()
	_braking = input.rmb or assisted_brake
	_car_s_then = car.s
	var walls: Vector2 = boss.walls(car.s, car.x)
	car.wall_left = walls.x
	car.wall_right = walls.y
	if boss.holds_car() or parked:
		# Pulled over for the Call, the car stands until he hangs up (GDD
		# 10.4); first in line at the Checkpoint, until he is let through;
		# and with the key turned in the bay it is parked (GDD 10.5).
		# A car that stands touches nothing: what it brushed in the last
		# tick it moved is not brushed again.
		car.speed = 0.0
		car.v_lat = 0.0
		car.edge_touched = CarSim.EDGE_NONE
		car.wall_touched = false
	elif not _standing():
		car.step(_road_dt, wheel.steer(), gate.gear, _braking, _extra_drift())
	_step_set_piece()
	if _auto_indicate:
		_indicate_for_lane_change()
	_step_cramp()
	var lane: int = car.lane_of(car.x)
	if lane != _lane:
		# Crossing a lane line without indicating that way (GDD 6.5): a row
		# of the Patrol's. At the Checkpoint he may choose his queue.
		if items.indicator != signi(lane - _lane) and boss.kind != BossSim.CHECKPOINT:
			suspicion.add(tuning.f("suspicion_lane_cross"))
		_lane = lane
		items.on_lane_line_crossed()

	# 6. Traffic.
	if free_traffic_per_km > 0.0:
		_step_free_traffic()
	if not stopped:
		# (At Dawn's last checkpoint the road waits for him: D-067.)
		var pace: float = boss.traffic_pace()
		leg.step_traffic(_road_dt * pace)
		traffic.step(_road_dt, car.s, car.x, car.speed, pace)
		boss.step_traffic(_road_dt * pace)
		_step_oncoming()

	# 7. Collisions and close calls.
	var lamps_before: int = faults.lamps
	if not _standing() and not prologue.active:
		# (The prologue cannot be failed, GDD 10.1: nothing is hit there.)
		collision.step(_road_dt, car, traffic, gate.gear)
		if boss.rear_end:
			# What came out of the dust behind his standing car (GDD 10.3).
			collision.strike(Collision.Hit.CRASH)
		if boss.wall_speed > 0.0:
			# The end of the street (GDD 10.5), at the speed he met it.
			collision.strike(collision.classify(boss.wall_speed, false))
		# At the Checkpoint touching a barrier is a scrape and Suspicion
		# (GDD 10.2); its lowered bar is a barrier too.
		var barrier: bool = car.wall_touched and collision.hit == Collision.Hit.SCRAPE and collision.hit_vehicle_id == 0
		if boss.bar_speed > 0.0 and collision.strike(Collision.Hit.SCRAPE):
			barrier = true
		if barrier and boss.kind == BossSim.CHECKPOINT:
			suspicion.add(_checkpoint_number("barrier_suspicion"))
		_apply_collisions()
		_step_leg_hazards()
	_leg_lamps_lit += maxi(faults.lamps - lamps_before, 0)

	# 8. Encounters and Suspicion.
	_step_encounter()
	_step_suspicion()

	# 9. Effect timers, Nerves, faults. At a stop, and while an officer waits
	# at his window, the night waits: nothing burns down, cools, rings, drifts
	# or calms (GDD 6.4). A Snap's seconds are the hand's own: they run on.
	if _standing():
		nerves.step_snap(DT)
	else:
		effects.step(DT)
		items.step(DT)
		_step_heckles()
		_step_passenger()
		if prologue.active:
			# "Nothing it does has a cost" (GDD 10.1): he is as calm as he was.
			nerves.set_value(0.0)
		else:
			_feed_nerves()
			nerves.step(DT)
	_report_nerves()
	var snap_said: bool = nerves.snapped
	_report_effects()
	cash = maxf(cash + items.cash_delta, 0.0)
	for event: Dictionary in items.events:
		_announce(event)
	items.events.clear()
	for event: Dictionary in stop.events:
		_announce(event)
	stop.events.clear()
	cash = maxf(cash + passengers.cash_delta, 0.0)
	_announce_passenger()
	if passengers.changed:
		_fit_cabin()

	# 10. Clock: it runs while he drives, not while he stands (GDD 6.4),
	# and it is read when the key is turned: not after.
	if not _standing() and not parked and not prologue.active:
		clock.step(DT)
	# The prologue's own clock; when it runs out, tonight begins.
	_step_prologue()

	# 12. Leg progress: Exit, Fork, boss and ending transitions.
	if run.active:
		_step_telling(input.lmb)
	elif leg.step_progress():
		if boss.active:
			_emit("boss_ended", {"boss": boss.kind, "act": act, "modifier": boss.modifier, "time": leg.time})
			boss.stop()
			_clear_weather()
		else:
			_end_leg()
			_mode_leg_done()
	# What leg progress brought after this tick's reports is said in the tick
	# it happened: the end of what a leg held to its end, at the gore, and a
	# Snap that a missed Exit took him to.
	_report_effects()
	if nerves.snapped and not snap_said:
		_report_snap()
		_announce_passenger()

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
## `renews` where a leg or a boss begins: what is once per leg (the photo,
## the charm's scrape, what lasts "for the leg") may be done again there,
## and nowhere else: not on the road to a fork, not on the street of the
## Arrival, not on the road he stands beside at a stop.
func _set_stretch(plan: Dictionary, renews: bool = true) -> void:
	parked = false
	set_road(GameData.as_int(plan.get("lanes"), 3), GameData.as_bool(plan.get("divided"), true))
	traffic.clear()
	collision.reset()
	car.reset(GameData.as_int(plan.get("start_lane")), gate.gear)
	_lane = car.lane_of(car.x)
	var act_before: int = act
	act = GameData.as_int(plan.get("act"), act)
	if act != act_before:
		items.begin_act()
	_floor_of_road = GameData.as_float(plan.get("heavy_floor"), -1.0)
	curve_k = 0.0
	if renews:
		items.begin_leg()
	leg.begin(plan)
	encounter.begin(plan)
	boss.begin(plan)
	if renews and (not leg.leg_id.is_empty() or boss.active):
		# A leg or a boss, not the road to a fork or the last street: what a
		# passenger does once per leg is new, as it is for the items.
		passengers.begin_leg()
	suspicion.end_watch()
	_release_from_pull_over()
	# At the Checkpoint he is watched from its start to the verdict, and
	# nothing wears off there (GDD 6.5, 10.2).
	suspicion.decays = boss.kind != BossSim.CHECKPOINT
	if boss.kind == BossSim.CHECKPOINT:
		suspicion.begin_watch()
		_emit("suspicion_changed", {"value": 0.0, "watching": true})
	_hold_at_window()
	items.raining = leg.raining
	items.dust_rate = leg.dust_rate
	items.wipe_haze = leg.wipe_haze
	car.lat_tau_mult = _rain_response if leg.raining else 1.0
	_leg_lamps_lit = 0
	_exit = EXIT_NONE
	_road_from = car.s


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
	_clear_weather()
	curve_k = 0.0
	encounter.stop()
	heckles.end_leg()
	_announce_heckles()
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


## The weather of the road he has left stays behind.
func _clear_weather() -> void:
	items.raining = false
	items.dust_rate = 0.0
	items.wipe_haze = 0.0
	car.lat_tau_mult = 1.0


## The leg's bend and gusts, before the car moves.
func _step_leg_road() -> void:
	if not leg.active or _standing():
		return
	leg.step_road(_road_dt, DT)
	curve_k = leg.curve_k
	if leg.gust_started != 0:
		_blow(leg.gust_started, leg.gust_push)
	boss.mirror_shift = items.passive("mirror_lead_s") - faults.param(FAULT_MIRROR, "mirror_tell_delay_s", 0.0)
	boss.step_road(_road_dt, DT, items.flag(FLAG_HAZARDS))
	if boss.rear_end_tell:
		# Its horn: the tell (GDD 2.2, pillar 4). Its lights in the mirror
		# come with it, or earlier or later as the mirror shows them.
		_emit("sfx_requested", {"id": "horn", "behind": true})
	_report_call()
	_report_soldier()


# --- A Telling (GDD 9.5, 11.1) -----------------------------------------------

## Starts a Telling of `table` from Baghdad: the starting cabin, 22:00, the
## car rolling in first gear toward the first fork with nobody at the wheel.
func begin_telling(table_id: String, telling_seed: int) -> void:
	_build()
	_tell(table_id, telling_seed)


## The Commute (GDD 11.5): "One seeded 5 km leg scored on cash." One road
## of commute_length, laid out like the leg tuning names (commute_leg), from
## a standing start with an empty band; where it ends he has arrived.
func begin_commute(commute_seed: int) -> void:
	_build()
	mode = Save.COMMUTE
	_mode_seed = commute_seed
	reseed(commute_seed)
	cash = 0.0
	var road: Dictionary = data.record("legs", tuning.s("commute_leg")).duplicate(true)
	var length: float = tuning.f("commute_length")
	# Par for its length, at the pace the leg's own par asks for.
	road["par_s"] = GameData.as_float(road.get("par_s")) * length / tuning.f("leg_length")
	road["length_m"] = length
	road["special"] = null
	begin_leg(LegGenerator.generate_road(data, road, 1, Rng.derive(commute_seed, 1)))


## Endless Night (GDD 11.5): "Legs without end, scored on distance." One
## leg after another with no fork, stall or boss between them, of any kind,
## harder as the acts of a Telling are (endless_legs_per_act legs to an
## act), until a Wreck.
func begin_endless(endless_seed: int) -> void:
	_build()
	mode = Save.ENDLESS_NIGHT
	_mode_seed = endless_seed
	reseed(endless_seed)
	begin_leg(_endless_leg())


## The next leg of Endless Night.
func _endless_leg() -> Dictionary:
	var of_act: int = mini(1 + _mode_legs / maxi(tuning.i("endless_legs_per_act"), 1), RunGenerator.ACTS)
	var kinds: PackedStringArray = []
	for record: Dictionary in data.records("legs"):
		if GameData.as_array(record.get("acts")).has(float(of_act)) or GameData.as_array(record.get("acts")).has(of_act):
			kinds.append(GameData.as_string(record.get("id")))
	var leg_id: String = kinds[rng.range_i(Rng.ROAD, 0, kinds.size() - 1)]
	var allowed: Array = GameData.as_array(data.record("legs", leg_id).get("modifiers_allowed"))
	var modifier: String = ""
	var roll: float = rng.unit(Rng.ROAD)
	var which: int = rng.range_i(Rng.ROAD, 0, maxi(allowed.size() - 1, 0))
	if roll < tuning.fi("modifier_chance", of_act - 1) and not allowed.is_empty():
		modifier = GameData.as_string(allowed[which])
	_mode_legs += 1
	return LegGenerator.generate(data, leg_id, of_act, Rng.derive(_mode_seed, _mode_legs), modifier)


## A leg of a mode has ended: the Commute is over; Endless Night goes on.
func _mode_leg_done() -> void:
	match mode:
		Save.COMMUTE:
			mode_over = true
			leg.stop()
			parked = true
			car.speed = 0.0
			car.v_lat = 0.0
			_emit("arrived", {"table": "", "mode": mode, "score": mode_score(), "clock": clock.text(), "late": false, "call": false, "guest": ""})
		Save.ENDLESS_NIGHT:
			_mode_behind += leg.length
			var plan: Dictionary = _endless_leg()
			_roll_into(plan)
			_announce_leg(plan)


## What the mode is scored on (GDD 11.5): the Commute on cash, Endless
## Night on distance, in metres. 0 outside a mode.
func mode_score() -> float:
	match mode:
		Save.COMMUTE:
			return cash
		Save.ENDLESS_NIGHT:
			return _mode_behind + (car.s if leg.active else 0.0)
	return 0.0


## "A guest objects, he answers" (GDD 3.2, 11.4): the Table's line at a
## Wreck, each of its lines in turn; at a rewind the line of that.
func _say_the_objection() -> void:
	if not run.active or run.table.is_empty():
		return
	var family: String = "rewind.%s" % run.table if _can_rewind() else "wreck.%s" % run.table
	var count: int = 0
	while data.has_line("%s.%d" % [family, count + 1]):
		count += 1
	if count == 0 and family.begins_with("rewind."):
		family = "wreck.%s" % run.table
		while data.has_line("%s.%d" % [family, count + 1]):
			count += 1
	if count > 0:
		_emit("line_requested", {"id": "%s.%d" % [family, 1 + run.retellings % count], "tell": true})


## The prologue (GDD 10.1), and after its 75 s the Telling for `table_id`:
## "Cut to tonight."
func begin_prologue(table_id: String, telling_seed: int) -> void:
	_build()
	_prologue_table = table_id
	_prologue_seed = telling_seed
	reseed(telling_seed)
	gate.reset(PrologueSim.GEAR_FROM)
	car.reset(car.lanes / 2, PrologueSim.GEAR_FROM)
	_lane = car.lane_of(car.x)
	_prologue_lane = _lane
	nerves.set_value(0.0)
	# The new photo lies on the dash, to be tucked into the visor.
	items.flags[FLAG_PROLOGUE] = true
	_sync_anchors()
	prologue.begin()


func _tell(table_id: String, telling_seed: int) -> void:
	table = TableRules.of(data, table_id)
	# A Table whose road is fixed tells the same night every time.
	var seed_told: int = table.seed if table.seed != TableRules.NO_SEED else telling_seed
	reseed(seed_told)
	run.rules = table
	run.begin(table_id, seed_told)
	_lay_the_table()
	_enter_approach()
	# His first words to the Table (GDD 3.6, 10.1): the night begins.
	_emit("line_requested", {"id": "narrator.start"})


## What a Table changes about how the night begins (GDD 11.2): when he
## leaves, and what the cabin holds besides its own.
func _lay_the_table() -> void:
	rewinds_left = table.free_rewinds
	_leg_start = {}
	clock.add_minutes(table.depart_min)
	for item_id: String in table.start_items:
		give_item(StringName(item_id))
	for item_id: String in table.full_supplies:
		give_item(StringName(item_id))


## The road to a fork: nothing on it but the sign and the split. It is no
## leg: what was done once in the boss behind it stays done to the gore.
func _enter_approach() -> void:
	var length: float = tuning.f("leg_tail") - tuning.f("exit_slip_length")
	_set_stretch(RunGenerator.blank_plan(run.act, RunGenerator.ROAD_LANES, true, length), false)


func _step_telling(button_down: bool) -> void:
	if wrecked:
		# The Wreck is where the Telling stops (GDD 11.4): in its tick he
		# neither pulls in at a stall nor passes a gore or the end of a road.
		return
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
		# The Arrival ends with the key, in the bay (GDD 10.5).


## The gore point (GDD 9.5): the branch is the side of the split the car is on.
func _take_fork() -> void:
	var side: int = RunState.LEFT if car.x < car.road_right() * 0.5 else RunState.RIGHT
	# On a fixed road the next leg simply begins: nothing was chosen.
	var forked: bool = run.splits_ahead()
	if not forked:
		side = RunState.LEFT
	_side = side
	var branch: Dictionary = run.take_branch(side)
	_keep_leg_start()
	var plan: Dictionary = _plan_the_leg(branch)
	if forked:
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
		# A leg's ride is counted where its stall is, stopped at or not.
		passengers.leg_ridden()
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


## Dev mode (D-073): the night stands at a stop of this kind, now. False
## when there is no night under way or no such stop.
func dev_stop(stop_id: String) -> bool:
	if not run.active or stopped or not data.has_record("stops", stop_id):
		return false
	_enter_stop()
	# The save point has put the night back as it was generated: the stop is
	# made the one asked for after it.
	run.stop = stop_id
	_open_stop(_shady_here)
	return true


## Dev mode, F3 (GDD 13.9: "Skip to the end of the leg"): the road is
## cleared and the car put `margin` metres short of the leg's end. At a
## checkpoint there is a bar and a soldier, not a distance: false there,
## and wherever he is not driving.
func dev_skip_leg(margin: float) -> bool:
	if not leg.active or stopped or pulled_over or boss.kind == BossSim.CHECKPOINT:
		return false
	traffic.remove_all()
	car.s = maxf(car.s, leg.length - margin)
	return true


func _enter_stop() -> void:
	run.enter_stop()
	heckles.end_leg()
	_announce_heckles()
	var minutes: float = GameData.as_float(data.record("stops", run.stop).get("clock_min")) if data.has_record("stops", run.stop) else 0.0
	clock.add_minutes(minutes)
	# The shady guy is there after a leg that lit no lamp (GDD 9.6), unless
	# the Table will have no Deals.
	_shady_here = _leg_lamps_lit == 0 and table.deals_offered()
	_let_passenger_out(false)
	_save_point()
	_emit("stop_entered", {"stop": run.stop, "minutes": minutes, "act": run.act, "leg_index": run.legs_done,
			"shady": _shady_here, "offers": stop.offers_view()})


## A passenger whose ride is over gets out where the car stands (GDD 8.1):
## at a stall, or at the stop after the act's boss. What they pay and leave
## him with is his before the stop is saved.
func _let_passenger_out(after_boss: bool) -> void:
	if not passengers.ride_over(after_boss):
		return
	_left_here = passengers.id
	passengers.leave("ride_over")
	cash = maxf(cash + passengers.cash_delta, 0.0)
	for event: Dictionary in passengers.events:
		_announce(event)
	passengers.begin_tick()
	_fit_cabin()


## A stop is where the game saves (GDD 11.1). What the save holds is taken
## and at once put back, so that the Telling which goes on from here is,
## to the bit, the one a player gets who loads that save. What the stop ends
## is settled, and said, before that.
func _save_point() -> void:
	items.come_to_a_stop()
	_announce_what_ends()
	checkpoint = capture()
	checkpoints += 1
	restore(checkpoint)


## What a stop ends is said before the simulation is made anew there (GDD
## 13.6): the mend of the fault the tape held and the end of a call that was
## ringing (ItemSim.come_to_a_stop), and the end of every status but those
## the leg holds to its end.
func _announce_what_ends() -> void:
	for event: Dictionary in items.events:
		_announce(event)
	items.events.clear()
	_report_effects()
	for id: StringName in effects.active_ids():
		if not items.held_for_leg(id):
			_emit("effect_expired", {"effect": String(id)})


func _open_stop(shady: bool) -> void:
	if data.has_record("stops", run.stop):
		stop.begin(run.stop, run.act, shady, table.price_mult, table)
		stop.hitcher = _hitcher_here()
	_sync_anchors()


## Who stands at the stop he is at, asking for a ride (GDD 8.1; "" for
## nobody): drawn from the Telling's seed for the stop it is now (the stop
## after a boss is the stop he chose there, GDD 9.6) and its place in the
## night. Never the one he carries, and never the one who has just got out
## here.
func _hitcher_here() -> String:
	if table.places_hitchers():
		# The Table says who waits where (GDD 11.2: Noor's), and nobody else
		# does. (The boss stop is none of an act's three stops: no entry
		# names it.)
		var waits: String = table.hitcher_at(run.act, run.legs_done)
		return "" if waits == passengers.id or waits == _left_here else waits
	return RunGenerator.hitcher(data, run.seed, run.act, run.legs_done, stop.id_now(), passengers.id, _left_here)


## The car stands; the road is gone until he leaves.
func _park() -> void:
	stopped = true
	# (What was left of a Steady start is over where he stops again.)
	_steady_left = 0.0
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
	_left_here = ""
	if stop.tea_served:
		# The next fork's sign also shows the modifier of the boss ahead (GDD 9.6).
		run.boss_on_sign = true
	cash = stop.leave(cash)
	stopped = false
	_leave_grip = 0.0
	# Steady start: for a moment after a stop the wheel holds itself.
	_steady_left = tuning.f("steady_start_s")
	gate.reset(tuning.i("start_gear"))
	if run.stage == RunState.Stage.BOSS_STOP:
		run.leave_boss_stop()
		if run.stage == RunState.Stage.ARRIVAL:
			_set_stretch(BossSim.arrival_plan(data, run.act), false)
		else:
			_enter_approach()
	else:
		# Back on the road beside the stall, in its right lane.
		run.leave_stop()
		car.x = car.lane_center(car.lanes - 1)
		_lane = car.lane_of(car.x)
		_road_from = car.s
	car.speed = 0.0
	_sync_anchors()


## The act's boss (GDD 10): the road leads into it from the third leg.
func _begin_boss() -> void:
	run.begin_boss()
	_keep_leg_start()
	_roll_into(BossSim.plan(data, run.boss, run.boss_modifier, RunGenerator.boss_seed(run.seed, run.act)))
	_meet_the_boss()


## What the start of a boss does to him, and its announcement.
func _meet_the_boss() -> void:
	if table.boss_alone_nerves != 0.0 and not passengers.aboard():
		# A boss begun with nobody beside him (GDD 11.2, the Groom's Table).
		nerves.add(table.boss_alone_nerves)
	_emit("boss_started", {"boss": run.boss, "act": run.act, "modifier": boss.modifier})


## While a free rewind is left, the Telling as it stands where a leg or a
## boss begins is kept, to return to.
func _keep_leg_start() -> void:
	_leg_start = capture() if rewinds_left > 0 else {}


func _can_rewind() -> bool:
	return rewinds_left > 0 and not _leg_start.is_empty()


## A free rewind (GDD 11.2: "the first Wreck returns to the start of that
## leg"): the Telling is as it was when the leg, or the boss, he wrecked on
## began, and he drives it again from its start. What the last stop saved
## is still the night he is telling.
func _rewind() -> void:
	var from: Dictionary = _leg_start
	var left: int = rewinds_left - 1
	var saved: Dictionary = checkpoint
	var pointer: Vector2 = hand.pointer
	_put_back(from)
	checkpoint = saved
	rewinds_left = left
	_leg_start = {}
	_side = GameData.as_int(from.get("side"), RunState.RIGHT)
	_left_here = ""
	run.resume_on_road(GameData.as_string(from.get("table")), Save.seed_in(from.get("seed")), GameData.as_int(from.get("retellings")),
			GameData.as_int(from.get("act"), 1), GameData.as_int(from.get("leg")), GameData.as_string(from.get("stage")), _side)
	run.boss_on_sign = false
	run.call_answered = GameData.as_bool(from.get("call_answered"))
	if run.stage == RunState.Stage.BOSS:
		_set_stretch(BossSim.plan(data, run.boss, run.boss_modifier, RunGenerator.boss_seed(run.seed, run.act)))
		items.set_telling_state(GameData.as_dict(from.get("item_state")))
		_meet_the_boss()
	else:
		var plan: Dictionary = _plan_the_leg(run.branch)
		_set_stretch(plan)
		items.set_telling_state(GameData.as_dict(from.get("item_state")))
		_arm_exit()
		_announce_leg(plan)
	effects.begin_tick()
	if space.pointer_on_rim(pointer):
		hand.place_at(space.rim_point(pointer))
	else:
		hand.pointer = pointer


## Starts a boss by itself, from the start of its road in the middle lane (a
## test, `--boss=`). In a Telling the end of the act's third leg starts it.
func begin_boss(boss_id: String, modifier_id: String = "", boss_seed: int = 0) -> void:
	if not data.has_record("bosses", boss_id):
		push_error("DriveSim: unknown boss '%s'" % boss_id)
		return
	_set_stretch(BossSim.plan(data, boss_id, modifier_id, boss_seed))
	_emit("boss_started", {"boss": boss.kind, "act": act, "modifier": boss.modifier})


func _end_boss() -> void:
	# Whoever is on the phone hangs up as he pulls in.
	boss.hang_up()
	_report_call()
	if suspicion.watching:
		suspicion.end_watch()
		_emit("suspicion_changed", {"value": 0.0, "watching": false})
	_emit("boss_ended", {"boss": run.boss, "act": run.act, "modifier": boss.modifier, "time": leg.time})
	boss.stop()
	_clear_weather()
	run.enter_boss_stop()
	_shady_here = false
	_let_passenger_out(true)
	_save_point()
	_emit("stop_entered", {"stop": run.stop, "minutes": 0.0, "act": run.act, "leg_index": run.legs_done,
			"shady": false, "offers": stop.offers_view()})


## The street of the Arrival by itself (a test, `--boss=arrival`).
func begin_arrival() -> void:
	_set_stretch(BossSim.arrival_plan(data, act), false)


## What a set piece does once the car has moved: the last checkpoint's
## soldiers, the phone in his pocket, the bay.
func _step_set_piece() -> void:
	boss.step_after_car(_car_s_then)
	if boss.stow_began:
		# First in line (GDD 10.2): the soldier whistles as he sets off toward
		# the car, so that the Stow's tell is heard as well as seen (GDD 17.2).
		_emit("sfx_requested", {"id": "soldier_whistle"})
	if boss.call_began:
		effects.hold(THE_CALL, SET_PIECE, true)
		_emit("call_started", {"caller": NOOR})
		_emit("sfx_requested", {"id": "phone_ring"})
		# His pocket is out of his sight: the ring is written out as well
		# (GDD 17.2: every tell has both a sound and a visual).
		# (Until the Call is resolved: answered, the ring is over at once.)
		_emit("line_requested", {"id": "call.noor.rings", "until": "call_resolved", "tell": true})
		_sync_anchors()
	if boss.searched:
		_search_at_the_barriers()
	if boss.in_bay != _in_bay:
		_in_bay = boss.in_bay
		effects.hold(IN_BAY, SET_PIECE, _in_bay)
		_sync_anchors()


## The Call rang out unanswered: nothing is lost but the true ending (GDD 10.4).
func _report_call() -> void:
	if boss.call_missed:
		effects.hold(THE_CALL, SET_PIECE, false)
		_emit("call_resolved", {"caller": NOOR, "answered": false, "taken": ""})
		_sync_anchors()
	if boss.call_ending:
		# The end of the talk has its tell (GDD 2.2, pillar 4; 17.2): her
		# last words, and the phone's two notes.
		_emit("line_requested", {"id": "noor.call.bye", "tell": true})
		_emit("sfx_requested", {"id": "phone_ring"})


## He took the phone from his pocket (GDD 10.4): a TAP answers it alone, and
## pulled over with his hazard lights on he takes it standing; handed to a
## passenger, they hold it to his ear.
func _take_the_call(way: StringName) -> void:
	var how: String = BossSim.TAKEN_WITH_PASSENGER if way == &"passenger" else BossSim.TAKEN_ALONE
	if how == BossSim.TAKEN_ALONE and boss.pulled_over_safely(items.flag(FLAG_HAZARDS)):
		how = BossSim.TAKEN_PARKED
	if not boss.answer(how):
		return
	effects.hold(THE_CALL, SET_PIECE, false)
	run.call_answered = true
	_emit("call_resolved", {"caller": NOOR, "answered": true, "taken": how})


## He came to the last checkpoint's barriers faster than they wave through
## (GDD 10.4): he is stopped and searched, as at the Checkpoint (GDD 10.2).
func _search_at_the_barriers() -> void:
	var minutes: float = GameData.as_float(GameData.as_dict(GameData.as_dict(data.record("bosses", boss.kind).get(boss.kind)).get("checkpoint")).get("search_minutes"))
	car.speed = 0.0
	car.v_lat = 0.0
	clock_minutes_owed += minutes
	clock.add_minutes(minutes)
	# A search finds everything, stowed or not, as at the Checkpoint.
	var taken_ids: Array[String] = []
	for id: StringName in items.take_all_contraband():
		taken_ids.append(String(id))
	_fit_cabin()
	_emit("pulled_over", {"released": true, "paid": "search", "cost": 0.0, "minutes": minutes, "taken": taken_ids})
	_emit("line_requested", {"id": "soldier.search"})


# --- The Checkpoint (GDD 10.2) -----------------------------------------------

## A number of the Checkpoint's record.
func _checkpoint_number(key: String) -> float:
	return GameData.as_float(GameData.as_dict(data.record("bosses", BossSim.CHECKPOINT).get("checkpoint")).get(key))


## The status the papers' rituals ask for is on while the soldier stands at
## his window with a sign up.
func _hold_at_window() -> void:
	var waiting: bool = boss.kind == BossSim.CHECKPOINT and boss.phase == BossSim.PAPERS and not boss.wanted.is_empty()
	if waiting == _at_window:
		return
	_at_window = waiting
	effects.hold(AT_WINDOW, SET_PIECE, waiting)
	_sync_anchors()


## What the soldier did this tick: he reached the window, put up a sign,
## counted another delay.
func _report_soldier() -> void:
	if boss.kind != BossSim.CHECKPOINT:
		return
	if boss.stow_ended:
		# What he sees as he comes up: each contraband item left out, and
		# each stack of Courage he can smell.
		suspicion.add(_checkpoint_number("contraband_suspicion") * float(items.contraband_in_view()))
		suspicion.add(_checkpoint_number("courage_suspicion") * float(courage_noticed()))
		# Forged papers pass the Papers phase by themselves, once (GDD 7.7):
		# on the visit that gets him through. At the top of Suspicion he is
		# turned back as he comes, and they stay in the cabin for the next.
		if items.has_pass("papers") and suspicion.value >= _checkpoint_number("turned_back_at"):
			_turn_back(suspicion.value)
			return
		if use_forged_papers():
			boss.papers_passed()
	if boss.delayed:
		suspicion.add(_checkpoint_number("delay_suspicion"))
	if boss.asked and not boss.papers_done:
		# A sign goes up: he raps on the door for it (GDD 17.2).
		_emit("sfx_requested", {"id": "soldier_knock"})
		if not items.flag(ItemSim.FLAG_WINDOW):
			# He cannot be handed anything through the glass.
			_emit("line_requested", {"id": "soldier.window"})
	_hold_at_window()
	if boss.papers_done:
		_give_the_verdict()


## He handed something out of the driver's window while the soldier waits.
func _hand_out(what: StringName) -> void:
	if boss.kind != BossSim.CHECKPOINT or boss.phase != BossSim.PAPERS:
		return
	if what == BANKNOTES:
		# Banknotes pass at any level (GDD 10.2), if he has them, and if the
		# Table has bribes at all.
		var price: float = tuning.f("checkpoint_bribe")
		if cash < price or table.no_bribes:
			_emit("pulled_over", {"released": false, "refused": true, "paid": "bribe", "cost": price})
			return
		cash -= price
		_let_through("bribe", price, 0.0, [])
		return
	if not boss.hand_over(String(what)):
		_emit("line_requested", {"id": "soldier.wrong"})
		return
	_hold_at_window()
	if boss.papers_done:
		_give_the_verdict()


## The papers are done: by his Suspicion he passes, is searched, or is
## turned back (GDD 10.2).
func _give_the_verdict() -> void:
	if boss.phase != BossSim.PAPERS:
		# Given already (this tick's report comes after the hand's).
		return
	var level: float = suspicion.value
	if level >= _checkpoint_number("turned_back_at"):
		_turn_back(level)
	elif level >= _checkpoint_number("pass_under"):
		# A search finds everything, stowed or not.
		var taken: Array[String] = []
		for id: StringName in items.take_all_contraband():
			taken.append(String(id))
		_fit_cabin()
		_let_through("search", 0.0, _checkpoint_number("search_minutes"), taken)
	else:
		_let_through("pass", 0.0, 0.0, [])


## The bar goes up.
func _let_through(how: String, cost: float, minutes: float, taken: Array[String]) -> void:
	var level: float = suspicion.value
	clock_minutes_owed += minutes
	clock.add_minutes(minutes)
	boss.release()
	suspicion.end_watch()
	_hold_at_window()
	_emit("pulled_over", {"released": true, "paid": how, "cost": cost, "minutes": minutes, "taken": taken, "suspicion": level})
	# The verdict is said (GDD 16.3: what he is told, he reads).
	_emit("line_requested", {"id": "soldier.%s" % how})
	_emit("suspicion_changed", {"value": 0.0, "watching": false})


## Turned back: the time it costs, and the queue again from its end, in
## first gear, with Suspicion begun anew.
func _turn_back(level: float) -> void:
	var minutes: float = _checkpoint_number("turned_back_minutes")
	clock_minutes_owed += minutes
	clock.add_minutes(minutes)
	boss.turn_back()
	var start_gear: int = tuning.i("start_gear")
	gate.reset(start_gear)
	if _lever_in_hand:
		_lever_in_hand = false
		hand.unpin()
	car.reset(car.lanes / 2, start_gear)
	_lane = car.lane_of(car.x)
	_car_s_then = car.s
	collision.reset()
	suspicion.begin_watch()
	_hold_at_window()
	_emit("pulled_over", {"released": false, "paid": "turned_back", "cost": 0.0, "minutes": minutes, "taken": [], "suspicion": level})
	_emit("line_requested", {"id": "soldier.turned_back"})
	_emit("suspicion_changed", {"value": 0.0, "watching": true})


## The key is turned in the bay (GDD 10.5): the Clock is read at that moment.
func _turn_the_key() -> void:
	if boss.kind != BossSim.ARRIVAL or not boss.in_bay:
		return
	_arrive()


## The end of the road (GDD 10.5): the Clock is read.
func _arrive() -> void:
	var table: String = run.table
	var told_true: bool = run.call_answered
	if run.active:
		run.arrive()
	effects.hold(IN_BAY, SET_PIECE, false)
	_in_bay = false
	boss.stop()
	leg.stop()
	# The key is turned: the engine is off and the car stays where it is.
	parked = true
	car.speed = 0.0
	car.v_lat = 0.0
	_sync_anchors()
	# Whoever he carried to Basra is a wedding guest from now on (GDD 8.1, 11.5).
	_emit("arrived", {"table": table, "clock": clock.text(), "clock_minutes": clock.minutes, "late": clock.late(), "call": told_true,
			"guest": passengers.id})


# --- Wreck, save and replay --------------------------------------------------

## The Telling is told again from Baghdad (GDD 11.4): the same Table, another
## seed, the starting cabin, 22:00. The pointer stays where the player has it,
## so a hand that is asking for the wheel has it at once.
func _retell() -> void:
	var table_id: String = run.table
	var telling_seed: int = run.seed
	var retellings: int = run.retellings
	var pointer: Vector2 = hand.pointer
	_build()
	# After a Wreck there is no saved Telling to continue: what the last stop
	# saved was the night that wrecked, and this one starts from Baghdad.
	checkpoint = {}
	run.rules = table
	run.table = table_id
	run.seed = telling_seed
	run.retellings = retellings
	run.retell()
	reseed(run.seed)
	_lay_the_table()
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
			var entry: Dictionary = {"id": String(item.id), "slot": String(item.slot), "supply": item.supply, "hot": Save.exact(item.hot_left)}
			if item.lapse_left >= 0.0:
				# What neglect still owes him (the craving): the seconds until it bites.
				entry["lapse"] = Save.exact(item.lapse_left)
			kept.append(entry)
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
		"left_here": _left_here,
		"boss_sign": run.boss_on_sign,
		"call_answered": run.call_answered,
		"rewinds": rewinds_left,
		"twist": _leg_twist,
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
		"passenger": passengers.state(),
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
	_put_back(telling)
	_side = GameData.as_int(telling.get("side"), RunState.RIGHT)
	_shady_here = GameData.as_bool(telling.get("shady"))
	_left_here = GameData.as_string(telling.get("left_here"))
	run.resume(GameData.as_string(telling.get("table")), Save.seed_in(telling.get("seed")), GameData.as_int(telling.get("retellings")),
			GameData.as_int(telling.get("act"), 1), GameData.as_int(telling.get("leg")), stage, _side)
	run.boss_on_sign = GameData.as_bool(telling.get("boss_sign"))
	run.call_answered = GameData.as_bool(telling.get("call_answered"))
	_stand_at_the_stop(telling)
	return true


## What a captured Telling holds of the car, the cabin and the night, put
## into a simulation made anew: everything but where on the road he is.
func _put_back(telling: Dictionary) -> void:
	_build()
	table = TableRules.of(data, GameData.as_string(telling.get("table")))
	run.rules = table
	rewinds_left = GameData.as_int(telling.get("rewinds"))
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
			item.lapse_left = Save.from_exact(kept.get("lapse"), item.lapse_left)
	for entry: Variant in GameData.as_array(telling.get("adaptations")):
		var fitted: Dictionary = GameData.as_dict(entry)
		items.add_item(StringName(GameData.as_string(fitted.get("id"))), StringName(GameData.as_string(fitted.get("slot"))))
	var switches: Dictionary = GameData.as_dict(telling.get("switches"))
	for key: Variant in switches:
		items.flags[StringName(str(key))] = GameData.as_bool(switches[key])
	items.set_radio(StringName(GameData.as_string(telling.get("radio"), String(ItemSim.STATIC))))
	passengers.set_state(telling.get("passenger"))
	passengers.begin_tick()


## The car stands at the stop a save was made at (see restore).
func _stand_at_the_stop(telling: Dictionary) -> void:
	var bits: Dictionary = GameData.as_dict(telling.get("exact"))
	if run.stage == RunState.Stage.STOP:
		# At the stall of the leg he is on.
		# (Laid out with the Twist it had: the same road he drove to here.)
		_leg_twist = GameData.as_dict(telling.get("twist"))
		_set_stretch(RunGenerator.plan(data, run.branch, run.act, _leg_twist), false)
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
				GameData.as_bool(boss.get("divided"), true), GameData.as_float(boss.get("length_m")), GameData.as_float(boss.get("par_s"))), false)
		car.s = leg.length
		leg.stop()
	# What he did once this leg, or in this boss, stays done at its stop, and
	# what lasts to the leg's end lasts.
	items.set_leg_state(GameData.as_dict(telling.get("leg_state")))
	# (After the stretch is set: a new act would otherwise seem to begin here.)
	items.set_telling_state(GameData.as_dict(telling.get("item_state")))
	_park()
	_open_stop(_shady_here)
	# What the save put back did not begin here: it is not said again.
	effects.begin_tick()


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
		car.s, car.x, car.speed, car.v_lat, car.drift, wheel.angle, _let_go_angle, _catch_left, _road_from, gate.gear, gate.lever,
		hand.pos, hand.target, hand.pointer, hand.gripping, nerves.value, nerves.snap_left,
		collision.chain, collision.immunity_left, leg.time, clock.minutes, suspicion.value, cash,
		_steady_left, heckles.phase, heckles.said, heckles.lead_left, heckles.window_left,
		prologue.step, prologue.time, mode, _mode_behind, _mode_legs,
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
## What every gain of Suspicion is multiplied by: what the cabin and the one
## beside him make of it, and at the Checkpoint what the Table does (GDD
## 11.2: the Uncles).
func _suspicion_gain() -> float:
	var gain: float = items.passive("suspicion_gain_mult") * passengers.suspicion_mult()
	if boss.kind == BossSim.CHECKPOINT:
		gain *= table.checkpoint_suspicion_mult
	return gain


func _step_suspicion() -> void:
	if not suspicion.watching or pulled_over:
		_snapped = false
		return
	if boss.kind == BossSim.CHECKPOINT:
		# At the Checkpoint only its own rows count (GDD 10.2: added where
		# they happen), and a Snap, which is charged wherever the law is
		# watching (GDD 6.1); nothing wears off, and nobody is pulled over.
		if _snapped:
			suspicion.add(tuning.f("suspicion_snap"))
		_snapped = false
		suspicion.step(DT)
		if suspicion.jumped != 0.0:
			_emit("suspicion_changed", {"value": suspicion.value, "watching": true})
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
	# What a passenger does that a Patrol hears (the drum, GDD 8.2).
	suspicion.add_rate(passengers.suspicion_rate())
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
	# The night waits from here as it does at a stop, and finds him as a stop
	# does: with his eyes open.
	nerves.rouse()
	if gesture.is_active():
		gesture.cancel()
	_emit("pulled_over", {
		"released": false,
		"fine": fine(),
		"bribe": bribe(),
		"can_bribe": cash >= bribe() and not table.no_bribes,
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
		if cash < cost or table.no_bribes:
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


## Puts a passenger in the seat (GDD 8.1): the hitcher he unlocked the door
## for; a test; a debug key. False when the seat is taken or nobody is
## called that.
func board(passenger_id: String) -> bool:
	if not passengers.board(passenger_id):
		return false
	_announce_passenger()
	_fit_cabin()
	return true


## What whoever rides with him has said or done since this was last asked:
## each is announced once.
func _announce_passenger() -> void:
	for event: Dictionary in passengers.events:
		_announce(event)
	passengers.events.clear()


## Sets the road the car is on: 1 to 3 lanes, divided or not (GDD 5.1).
func set_road(lanes: int, divided: bool) -> void:
	car.set_road(lanes, divided)
	_lane = car.lane_of(car.x)


## Starts one gust (GDD 5.4): gust_push for gust_duration of the road's time,
## which is counted in whole ticks (see _extra_drift). `direction` is +1 toward
## the right shoulder, -1 toward the left. `strength` scales it.
func start_gust(direction: int, strength: float = 1.0) -> void:
	_blow(direction, _gust_strength * strength)


## One gust that pushes at `push` m/s.
func _blow(direction: int, push: float) -> void:
	_gust_left = _gust_duration
	_gust_push = push * float(direction)


## The Heavy floor now (GDD 6.1): by act, plus what the Table or a pill adds.
func heavy_floor() -> float:
	var index: int = clampi(act, 1, _heavy_floors.size()) - 1
	var base: float = _floor_of_road if _floor_of_road >= 0.0 else _heavy_floors[index]
	return base + heavy_floor_bonus + table.heavy_floor_add + effects.total(HEAVY_FLOOR)


## How far he can see along the road, in metres (GDD 9.1, 9.4): the
## headlight cone at night, the dust in a dust haze, else no limit (INF).
func visibility() -> float:
	return _sight_in(boss.visibility)


## How far the views show him the road, m: what he sees, but through the
## dust's tell the Storm's thick dust is already closing in (GDD 2.2 pillar
## 4: an impairment has a tell). Nothing in the rules goes by this.
func sight_shown() -> float:
	var sight: float = visibility()
	if boss.dust_closing > 0.0 and is_finite(sight):
		sight = lerpf(sight, _sight_in(boss.thick_visibility()), boss.dust_closing)
	return sight


## How far he would see with the set piece's dust at `dust` metres.
func _sight_in(dust: float) -> float:
	if not leg.active:
		return INF
	var reach: float = minf(leg.dust_visibility, dust)
	if leg.night:
		# What makes the night darker for him shortens what he sees of it
		# (GDD 7.5, 7.7: cracked sunglasses, tinted glass).
		reach = minf(reach, headlight_cone() * maxf(1.0 - items.passive("night_darker"), 0.0))
	# Fog lamps reach further into whatever limits his view (GDD 7.6).
	return reach * items.passive("visibility_mult") if reach < INF else reach


## The Glare on his view now, 0 to 1 (GDD 5.8), after what he wears against it.
func glare() -> float:
	# The visor, while it is down, blocks the sun (GDD 4.6): not a spotlight.
	var sun: float = 0.0 if effects.has(ItemSim.VISOR_DOWN) else boss.glare
	return maxf(encounter.glare, sun) * items.passive("glare_mult")


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
	# Where the pointer points, for the ring that shows it: the anchor it has
	# snapped to, or the spot under it. Not the hand's target, which is kept
	# inside the box the free hand can roam: the ring would stop at the edge
	# of the box while the pointer went on.
	var pointer_point: Vector3 = space.pointed_at(hand.pointer)
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
		# A press has been made and waits for the hand to get there.
		"press_pending": hand.press_pending(),
		"cam_yaw": hand.cam_yaw,
		"cam_pitch": hand.cam_pitch,
		"wheel_angle": wheel.angle,
		"gear": gate.gear,
		"lever": gate.lever,
		"lever_held": gate.held,
		"gesture_kind": gesture.kind,
		"gesture_progress": gesture.progress,
		"gesture_anchor": hand.anchor_id(_active_anchor),
		# For the label that names a control and says how it is worked: what
		# a press where the pointer is would begin, and what is being made now.
		"hint": hint_at(hand.snap_index),
		"gesture_hint": _hint_in_hand(),
		# The pointer is on the wheel's rim, with nothing else under it.
		"on_rim": not hand.pinned and hand.snap_index == HandSim.NO_ANCHOR and space.pointer_on_rim(hand.pointer),
		"has_fifth": gate.has_fifth,
		"lever_locked": gate.lock_left > 0.0,
		"sequential_shift": sequential_shift,
		"carrying": _carried(),
		"view_block": GameData.as_string(_active_ritual.get("blocks_view")) if gesture.is_active() else "",
		"courage": courage(),
		"cramp": cramp,
		"ghost_at": hand.anchor_id(hand.ghost_anchor),
		"ghost_progress": 1.0 - hand.flinch_left / maxf(tuning.f("phantom_flinch_delay"), 0.001) if hand.ghost_anchor != HandSim.NO_ANCHOR else 0.0,
		"hook": "set" if effects.has_own(ItemSim.HOOK_SET) else ("armed" if effects.has_own(ItemSim.HOOK_ARMED) else ("cooling" if effects.has_own(ItemSim.HOOK_COOLDOWN) else "")),
		"anchor_moves": _anchor_moves(),
		"mirror_scale": items.passive("mirror_scale"),
		"mirror_shift": encounter.tell_shift,
		"caller": NOOR if boss.call == BossSim.CALL_RINGING else String(items.caller),
		"ring_left": boss.call_left if boss.call == BossSim.CALL_RINGING else items.ring_left,
		# The phone on its mount by itself: it can ring while Noor's does.
		"mount_caller": String(items.caller),
		"mount_ring_left": items.ring_left,
		"call": boss.call,
		"call_talking": boss.talking(),
		"call_left": boss.call_left,
		"call_taken": boss.call_taken,
		"at_ear": hand.at_ear,
		"dawn_phase": boss.phase if boss.kind == BossSim.DAWN else 0,
		"checkpoint_phase": boss.phase if boss.kind == BossSim.CHECKPOINT else 0,
		"stow_left": boss.stow_left,
		# The vehicles of the queue still ahead of him in his lane.
		"queue_ahead": boss.queue_length(clampi(car.lane_of(car.x), 0, car.lanes - 1)) if boss.kind == BossSim.CHECKPOINT else 0,
		"boss_now": boss.kind if boss.active else "",
		"wanted": boss.wanted,
		"papers_delay": boss.delay,
		"bar_at": boss.bar_at,
		"bar_up": boss.released,
		"suspicion_by": "checkpoint" if boss.kind == BossSim.CHECKPOINT else ("patrol" if suspicion.watching else ""),
		# False once the key is turned in the bay (GDD 10.5): the car is parked.
		"engine_on": not parked,
		"sun": boss.glare,
		"sun_side": boss.sun_side,
		# Where the light behind the Glare is, while the sun is up (degrees
		# right of dead ahead, degrees above the horizon); null otherwise.
		"glare_position": boss.sun_position(tuning.fi("sun_position", 0), tuning.f("sun_rise_from"), tuning.fi("sun_position", 1)) if boss.glare > 0.0 else null,
		"glow": boss.glow,
		"glow_side": boss.glow_side,
		"corridor": boss.corridor(),
		"corridor_gap": boss.corridor_gap(),
		# The road's own limits across it: what ends it on the left (the
		# median barrier, or the rail beyond the oncoming lane) and the
		# guardrail on the right. A checkpoint's outermost barriers close in
		# from them, and the bay of the Arrival lies between them.
		"road_limits": Vector2(car.left_limit_x(), car.guardrail_x()),
		"bay": Vector2(boss.bay_from, boss.bay_to),
		"in_bay": boss.in_bay,
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
		# (The morning of the prologue has its own hour on the dash.)
		"clock": tuning.s("prologue_clock") if prologue.active else clock.text(),
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
		"raining": (leg.active and leg.raining) or prologue.raining(),
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
		"gore_ahead": leg.length - car.s if run.active and run.splits_ahead() and leg.active else -1.0,
		"offers": _offers_in_view(),
		"passenger": passengers.id,
		"passenger_legs": passengers.legs_ridden,
		"passenger_asleep": passengers.asleep(),
		"passenger_aloud": passengers.aloud(),
		# The Table (GDD 11.3): the heckle being said ("lead") or running
		# ("open"), how far he has come with it, and the Fib's ghost hand.
		"heckle": GameData.as_string(heckles.record.get("id")),
		"heckle_type": GameData.as_string(heckles.record.get("type")),
		"heckle_phase": heckles.phase_name(),
		"heckle_left": heckles.window_left if heckles.phase == HeckleDirector.OPEN and heckles.window_left != INF else 0.0,
		"heckle_progress": heckles.progress(),
		# The prologue (GDD 10.1): the step that is on (0: it is not playing),
		# the anchor that pulses, whether the step is done, how far the left
		# hand has lifted off the wheel (and the screen whited out), and where
		# the left hand is.
		# A mode (GDD 11.5): which, whether it is over, and its score so far.
		"mode": mode,
		"mode_over": mode_over,
		"mode_score": mode_score(),
		"prologue_step": prologue.step if prologue.active else 0,
		"prologue_prompt": _prologue_prompt(),
		"prologue_done": prologue.done,
		"prologue_lift": prologue.lift(),
		"left_hand": _left_hand_at(),
		# The wheel's part of the Tremor (GDD 17.1: its visuals can be turned
		# down; "the mechanical effect stays"), and the settings' own hands.
		"wheel_tremor": wheel.tremor,
		"steady_holds": steady_holds(),
		"hand_free": hand_is_free(),
		"assisted_brake": assisted_brake,
		"ghost_hand": heckles.ghost_holds,
		"ghost_on_wheel": ghost_on_wheel(),
		"passenger_awake_left": passengers.awake_left,
		"passenger_drumming": passengers.drumming,
		"tea_passed": passengers.passes_tea(),
		"passenger_repair": passengers.repair,
		"passenger_repair_left": passengers.repair_left,
		"wheel_held": passengers.hold,
		"wheel_held_left": passengers.hold_left,
		"lever_blocked": passengers.blocks_lever(),
		"view_block_right": passengers.view_block_right(),
		"blessed": passengers.blessed,
		"hitcher": stop.hitcher if stopped else "",
		"boss": run.boss if run.active else boss.kind,
		"boss_modifier": boss.modifier,
		"boss_time": boss.time,
		"dust_thick": boss.thick,
		"dust_change_in": boss.dust_change_in,
		"dust_closing": boss.dust_closing,
		"rear_end_in": boss.rear_end_in,
		"rear_end_lights_in": boss.rear_end_lights_in,
		"pulled_over": pulled_over,
		"visibility": visibility(),
		"sight_shown": sight_shown(),
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
	if GameData.as_string(_active_ritual.get("id")) == ItemSim.UNSTOW:
		var stowed: ItemSim.Item = items.stowed_with_a_home()
		return String(stowed.id) if stowed != null else ""
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
	signs.append_array(boss.signs_near(ahead))
	if not run.active:
		return signs
	var par_ms: float = tuning.fi("gear_speeds", 2) / 3.6
	# The Exit is signed slip_sign_lead seconds ahead (GDD 9.5).
	if run.stage == RunState.Stage.LEG and _exit == EXIT_AHEAD:
		var to_exit: float = _exit_at - tuning.f("slip_sign_lead") * par_ms - car.s
		if to_exit >= 0.0 and to_exit <= ahead:
			signs.append({"kind": "exit", "ahead": to_exit, "stop": GameData.as_string(run.branch.get("stop"))})
	# The fork's overhead sign: for each branch its leg, modifier, stop and par.
	if run.splits_ahead():
		var fork_sign_at: float = maxf(leg.length - tuning.f("fork_sign_lead") * par_ms, 0.0)
		# One who reads the road has the sign earlier (GDD 8.2), where the
		# road he came onto still has that place ahead of him. Where it does
		# not (he pulled away from a stall that lies beyond it; the short
		# road to an act's first fork), the sign stands where it always does.
		var early_at: float = fork_sign_at - passengers.fork_sign_lead() * par_ms
		if early_at > _road_from:
			fork_sign_at = early_at
		var to_fork: float = fork_sign_at - car.s
		if to_fork >= 0.0 and to_fork <= ahead:
			var sign: Dictionary = {"kind": "fork", "ahead": to_fork, "left": run.branches[RunState.LEFT], "right": run.branches[RunState.RIGHT]}
			if run.boss_on_sign:
				# After tea the sign also shows what the boss ahead has in store (GDD 9.6).
				sign["boss"] = GameData.as_string(run.boss_record().get("id"))
				sign["boss_modifier"] = run.modifier_ahead()
			signs.append(sign)
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
	if not hand.can_reach:
		# The talk of the Call, a Snap: the hand goes nowhere (GDD 10.4, 6.1),
		# so nothing in the cabin is his to use.
		return out
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
	# A gust is the road's: it blows for gust_duration of the road's time, so
	# under Focus it lasts longer by his clock and carries the car as far as
	# ever (GDD 7.4). It pushes for a whole number of ticks: for this one while
	# at least half a tick of it is left.
	if _gust_left >= _road_dt * 0.5:
		_gust_left -= _road_dt
		push += _gust_push
	else:
		_gust_left = 0.0
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
		var spared: bool = collision.hit == Collision.Hit.SCRAPE and (items.absorbs_scrape() or passengers.absorbs_scrape())
		var drawn: Array[StringName] = faults.light(0 if spared else collision.hit_lamps)
		nerves.jolt()
		nerves.add(collision.hit_nerves)
		if collision.hit == Collision.Hit.SCRAPE:
			passengers.on_scrape()
		items.on_hit(collision.hit)
		items.on_faults_lit(drawn)
		if collision.hit_forces_gear:
			gate.force_gear(_forced_gear)
			if _lever_in_hand:
				_lever_in_hand = false
				hand.unpin()
		_emit("hit", {"kind": collision.hit, "lamps": drawn.size(), "vehicle": collision.hit_vehicle_id, "spared": spared, "rear_end": boss.rear_end})
		if not drawn.is_empty():
			_emit("lamp_lit", {"lamps": faults.lamps, "lit": drawn.size(), "faults": drawn})
		if faults.is_wrecked() and not wrecked:
			wrecked = true
			_wreck_left = tuning.f("wreck_to_wheel")
			_emit("wreck", {"table": run.table, "act": run.act, "retellings": run.retellings, "rewind": run.active and _can_rewind(),
					"mode": mode, "score": mode_score()})
			_say_the_objection()
			if not mode.is_empty():
				# A mode has no Table to tell it again to: it is over.
				mode_over = true
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
	# (The law at the Checkpoint is an encounter like a Patrol: no empty
	# road calms him under its eyes.)
	nerves.add_rate(nerves.road_rate(near, nearest, in_encounter or encounter.active or boss.watching()))
	if car.on_shoulder and car.speed > 0.0:
		# The shoulder is rough to drive on (GDD 5.1). A car at rest is
		# shaken by nothing: the Storm's safe place and the Call taken
		# pulled over cost his Nerves no more than standing anywhere.
		nerves.add_rate(_shoulder_rate)
	nerves.add_rate(faults.param(FAULT_RATTLE, "nerves_per_s", 0.0))
	if car.on_rumble:
		nerves.jolt()


## Reads what the things in the cabin change by being there into the
## systems they change (GDD 7.5 to 7.7), and puts every anchor where the
## cabin now has it. Runs whenever the cabin has changed.
func _fit_cabin() -> void:
	_cabin_seen = items.cabin_serial
	# What has left the cabin has left his hand: a gesture on a thing that
	# is gone (a search took the flask he was carrying) is over.
	if gesture.is_active() and _active_ritual.has("item") and items.owner_of(_active_ritual) == null:
		gesture.cancel()
	wheel.turn_rate_mult = items.passive("turn_rate_mult")
	wheel.return_rate_mult = items.passive("return_rate_mult")
	car.lat_speed_mult = items.passive("lat_speed_mult")
	gate.has_fifth = items.passive("fifth_gear") > 0.0
	faults.set_capacity_bonus(roundi(items.passive("lamp_capacity")))
	collision.cash_bonus = items.passive("close_call_bonus")
	car.high_gear_bonus = items.passive("high_gear_bonus")
	car.brake_mult = items.passive("brake_mult")
	suspicion.gain_mult = _suspicion_gain()
	_close_call_mult = items.passive("close_call_mult")
	_lag_sources = items.passive("lag_sources")
	_wheel_keys = items.passive("wheel_keys") > 0.0
	_auto_indicate = not items.pair("auto_indicate").is_empty()
	_hook_keeps_lane = not items.pair("hook_holds_lane").is_empty()
	var moves: Dictionary = _anchor_moves()
	for index: int in hand.anchor_count():
		var id: String = String(hand.anchor_id(index))
		hand.set_anchor_position(index, GameData.as_vec3(moves[id]) if moves.has(id) else _anchor_home[index])
	_sync_anchors()


## Anchors that something has moved: by what is fitted to the cabin, and the
## tea, held out to him beside the wheel by a passenger (GDD 8.2).
func _anchor_moves() -> Dictionary:
	var moves: Dictionary = items.anchor_moves()
	if passengers.passes_tea():
		moves[items.anchor_of(items.in_reach(TEA))] = passengers.tea_at()
	return moves


## The leg of a Telling he is taking, laid out: with the Twist a guest will
## throw in, if this leg's heckles hold one (GDD 11.3).
func _plan_the_leg(branch: Dictionary) -> Dictionary:
	_leg_twist = {}
	_ahead_then = {}
	if not heckling:
		heckles.end_leg()
		return RunGenerator.plan(data, branch, run.act)
	_leg_twist = heckles.plan_leg(rng, table, guests, run.act, GameData.as_string(branch.get("leg")), GameData.as_string(branch.get("modifier")))
	var plan: Dictionary = RunGenerator.plan(data, branch, run.act, _leg_twist)
	heckles.begin_leg(plan)
	return plan


## Steady start has the wheel (GDD 17.1): in the first seconds after a stop,
## while the setting is on and his own hand is not on it.
func steady_holds() -> bool:
	return steady_start and _steady_left > 0.0 and not hand.gripping


## Brake assist (GDD 17.1): a crash is certain when something the car's
## width overlaps is ahead of it, and at the speed they are closing there is
## less than brake_assist_time to it.
func _crash_is_certain() -> bool:
	var within: float = tuning.f("brake_assist_time")
	var front: float = car.s + car.length() * 0.5
	for vehicle: TrafficSim.Vehicle in traffic.vehicles:
		if absf(vehicle.x - car.x) >= vehicle.half_width + car.half_width():
			continue
		var gap: float = vehicle.s - vehicle.half_length - front
		if gap < 0.0:
			continue
		var closing: float = (car.speed - float(vehicle.direction) * vehicle.speed) / 3.6
		if closing > 0.0 and gap < closing * within:
			return true
	return false


## What the settings of GDD 17.1 mean to the simulation; the rest of them
## are the views'. `values` maps a setting's id to its value (SettingsSpec);
## what it does not hold stays as it is. Every one can be changed at any
## tick (GDD 17.2).
func apply_settings(values: Dictionary) -> void:
	if values.has(SettingsSpec.STEERING):
		steer_sensitivity = SettingsSpec.share(values[SettingsSpec.STEERING])
	if values.has(SettingsSpec.GRIP_MODE):
		grip_toggle = GameData.as_string(values[SettingsSpec.GRIP_MODE]) == SettingsSpec.GRIP_TOGGLE
	if values.has(SettingsSpec.SHIFTING):
		sequential_shift = GameData.as_string(values[SettingsSpec.SHIFTING]) == SettingsSpec.SHIFT_SEQUENTIAL
	if values.has(SettingsSpec.BRAKE_ASSIST):
		brake_assist = GameData.as_bool(values[SettingsSpec.BRAKE_ASSIST])
	if values.has(SettingsSpec.STEADY_START):
		steady_start = GameData.as_bool(values[SettingsSpec.STEADY_START])
	if values.has(SettingsSpec.PHANTOM):
		phantom_enabled = GameData.as_bool(values[SettingsSpec.PHANTOM])


## The prologue's left hand has the wheel (GDD 10.1): whenever the right
## one, which is all the player has, is not on it.
func left_hand_on_wheel() -> bool:
	return prologue.active and not hand.gripping


## One tick of the prologue (GDD 10.1): what the right hand has done, the
## step whose turn it is, what the left hand and the morning do by
## themselves, and at the end of it the cut to tonight.
func _step_prologue() -> void:
	if not prologue.active:
		return
	prologue.see(items.radio == ItemSim.MUSIC, gate.gear)
	prologue.step_clock(DT)
	if prologue.began > 0 and prologue.began < PrologueSim.LIFT:
		# "One short subtitle names the action."
		_emit("line_requested", {"id": "prologue.step.%d" % prologue.began})
	match prologue.began:
		PrologueSim.HONK:
			# "Honk at a friend passing": he comes up from behind, a lane over.
			var friend: Dictionary = tuning.d("prologue_friend")
			var beside: int = _prologue_lane - 1 if _prologue_lane > 0 else _prologue_lane + 1
			traffic.spawn(StringName(GameData.as_string(friend.get("vehicle"))), beside,
					car.s - GameData.as_float(friend.get("behind_m")), car.speed + GameData.as_float(friend.get("faster_kmh")))
		PrologueSim.WIPERS:
			# "It rains: flick the wipers. The left hand indicates and changes
			# lane by itself."
			items.raining = true
			var way: int = 1 if _prologue_lane + 1 < car.lanes else -1
			items.indicate(way)
			_prologue_lane += way
	if prologue.over:
		# "Cut to tonight. 22:00."
		begin_telling(_prologue_table, _prologue_seed)


## The anchor the prologue's prompt pulses at ("" for none).
func _prologue_prompt() -> String:
	var anchor: String = prologue.prompt()
	if anchor == PrologueSim.TEA_ANCHOR:
		return items.anchor_of(items.in_reach(TEA)) if items.in_reach(TEA) != null else ""
	return anchor


## Where the prologue's left hand is: on the wheel, at the indicator while
## it changes lane, lifting toward the window crank at the end; "" when he
## has none.
func _left_hand_at() -> String:
	if not prologue.active:
		return ""
	if prologue.step == PrologueSim.LIFT:
		return "window_crank"
	if prologue.changes_lane() and items.indicator != 0:
		return "indicator_stalk"
	return "wheel"


## The Fib's ghost hand has the wheel: while it holds (GDD 11.3) and his own
## hand, or his wrist, does not.
func ghost_on_wheel() -> bool:
	return heckles.ghost_holds and not hand.gripping and not _wrist_on_wheel


## A heckle may begin now (GDD 11.3: "Never during an encounter or a
## boss"): on a leg of a Telling before its Exit opens (an Exit lies ahead
## on a Telling's leg and nowhere else: not on the road to a fork, not in a
## boss), while the leg's encounter is not at him (D-061).
func _heckle_free() -> bool:
	return heckling and _exit == EXIT_AHEAD and not wrecked and not pulled_over and not encounter.pressing()


## One tick of the Table (GDD 13.3, step 11), before the Nerves are stepped:
## what it has seen him do, what it says, and what that does.
func _step_heckles() -> void:
	if not run.active or not leg.active or boss.active:
		return
	heckles.in_gear = gate.gear
	heckles.in_gripping = hand.gripping
	heckles.in_straight = curve_k == 0.0
	heckles.in_nerves = nerves.value
	heckles.in_close_calls = collision.close_calls
	heckles.in_horn = items.horn_blown
	heckles.in_passed = _count_passed()
	heckles.step(DT, car.s, _heckle_free())
	if heckles.twist_begins:
		leg.twist_begins()
	if heckles.shower_begins > 0.0:
		leg.begin_shower(heckles.shower_begins)
	if leg.weather_changed:
		# A shower has begun or ended: the rain is on the glass and the road.
		items.raining = leg.raining
		car.lat_tau_mult = _rain_response if leg.raining else 1.0
	nerves.add(heckles.nerves)
	cash = maxf(cash + heckles.cash, 0.0)
	_announce_heckles()


func _announce_heckles() -> void:
	for event: Dictionary in heckles.events:
		_announce(event)
	heckles.events = []


## The vehicles going his way that the car has passed since the last tick.
func _count_passed() -> int:
	var passed: int = 0
	var ahead_now: Dictionary = {}
	for vehicle: TrafficSim.Vehicle in traffic.vehicles:
		if vehicle.direction < 0:
			continue
		var ahead: bool = vehicle.s > car.s
		ahead_now[vehicle.id] = ahead
		if not ahead and GameData.as_bool(_ahead_then.get(vehicle.id)):
			passed += 1
	_ahead_then = ahead_now
	return passed


## One tick of whoever rides with him (GDD 13.3, step 11), before the Nerves
## are stepped: what they make of what he has just done, and their own time.
func _step_passenger() -> void:
	if items.asked:
		passengers.ask(_angle_asked_for())
	if items.horn_blown:
		passengers.on_horn()
	if items.taken_for_him != &"":
		passengers.on_call_taken(items.taken_for_him)
	if not items.used_tags.is_empty():
		passengers.on_used(items.used_tags)
	passengers.step(DT, gate.gear, leg.active and leg.raining)


## The angle a passenger asked to hold the wheel "at its current angle" is
## to hold it at (GDD 8.2): the wheel as it is; or, asked within the catch
## time of the driver's hand leaving a wheel that nothing else took, the
## wheel as it was let go. (What the hook has taken, it has where it is.)
func _angle_asked_for() -> float:
	if _catch_left > 0.0 and not effects.has_own(ItemSim.HOOK_SET):
		return _let_go_angle
	return wheel.angle


## The wheel angle that holds the car on a straight line where the road is
## straight: against the crown and a steering that pulls (the drifts that
## are always there, GDD 5.4), and nothing else.
func _straight_angle() -> float:
	var authority: float = car.lat_authority()
	if authority <= 0.0:
		return 0.0
	var steady: float = car.steady_drift(-faults.param(FAULT_PULL, "drift_left", 0.0))
	return clampf(-steady / authority, -1.0, 1.0) * wheel.max_angle()


## The thumb keypad (GDD 7.6): the horn and the wipers under the thumb of
## the hand that grips. Each press is one honk or one sweep. They are the
## road's: not at a stop, and not with an officer at his window.
func _step_wheel_keys(input: DriveInput) -> void:
	if _wheel_keys and hand.gripping and nerves.snap_left <= 0.0 and not _standing():
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
	heckles.in_ritual = StringName(ritual_id)
	prologue.ritual_done(ritual_id)
	_emit("ritual_completed", {"ritual": ritual_id, "anchor": GameData.as_string(ritual.get("anchor")), "direction": direction, "keypad": true})


## The angle at which the wheel keeps the car in the middle of its lane on a
## straight: against whatever carries it sideways, and back toward the
## middle within hook_settle_time (GDD 7.8, Wheel ring + Spinner knob).
func _lane_keeping_angle(to_lane: int = -1) -> float:
	var authority: float = car.lat_authority()
	if authority <= 0.0:
		return wheel.angle
	var lane: int = clampi(car.lane_of(car.x) if to_lane < 0 else to_lane, 0, car.lanes - 1)
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


## The weather cramp (GDD 7.9): once in a Rain leg, in a Night leg and in the
## Storm, as the car passes a fixed point of it. A hum for phantom_cramp_hum, then for
## phantom_cramp_length the hand can neither let go nor take hold, and
## phantom_cramp_nerves. Muted or switched off, nothing happens.
func _step_cramp() -> void:
	if cramp == "":
		if not leg.active or not (leg.raining or leg.night or boss.kind == BossSim.STORM) or _standing():
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
		_report_snap()
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


## A Snap (GDD 6.1): he leans on the horn, and whatever his hand was at is over.
func _report_snap() -> void:
	_snapped = true
	if table.snap_minutes > 0.0:
		# At a Table that counts them, each Snap costs the Clock (GDD 11.2).
		clock_minutes_owed += table.snap_minutes
		clock.add_minutes(table.snap_minutes)
	_emit("snap", {"nerves": nerves.value, "minutes": table.snap_minutes})
	_emit("sfx_requested", {"id": "horn"})
	if not _standing():
		# Two seconds of his horn wake one who sleeps (GDD 8.2) as its TAP
		# does: on the road. Where the night waits, nothing of a passenger runs.
		passengers.on_horn()
	if gesture.is_active():
		gesture.cancel()
	if _lever_in_hand:
		gate.release()
		_lever_in_hand = false
		hand.unpin()


## Statuses that began or ended since this was last asked: each is said once.
func _report_effects() -> void:
	if effects.expired.has(ItemSim.HOOK_SET):
		# The hook is out of its ring: it cannot be set again for a while.
		effects.add(ItemSim.HOOK_COOLDOWN, items.passive("hook_cooldown_s"))
	for id: StringName in effects.added:
		_emit("effect_added", {"effect": String(id)})
	for id: StringName in effects.expired:
		_emit("effect_expired", {"effect": String(id)})
	effects.added.clear()
	effects.expired.clear()


# --- Rituals -----------------------------------------------------------------

## A press was applied at an anchor. `button_down` is false for a buffered
## click that was already released when the hand arrived.
func _begin_at(anchor: int, button_down: bool) -> void:
	if anchor == _lever_anchor and passengers.blocks_lever():
		# His passenger leans across it (GDD 8.2): no shifting.
		return
	if anchor == _lever_anchor and not sequential_shift:
		# The lever is held only by a button that is still down: a click that
		# ended during the reach must not take it and knock it out of gear.
		if button_down:
			gate.press()
			_lever_in_hand = true
			hand.pin()
		return
	var ritual: Dictionary = _ritual_at(String(hand.anchor_id(anchor)))
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
		elif GameData.as_string(ritual.get("to")) == ItemSim.HOME_ANCHOR:
			# Out of the glovebox: to any free place it fits.
			for home: String in items.unstow_destinations():
				_drag_destinations.append(hand.anchor_index(StringName(home)))
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
	elif gesture.phase == Gesture.Phase.CANCELLED and (gesture.kind == Gesture.Kind.HOLD or gesture.kind == Gesture.Kind.DRAG_TO) \
			and not _tap_instead.is_empty() and not button_down and hand.at_index == _active_anchor \
			and gesture.elapsed <= tuning.f("tap_max_time") + DT * 0.5:
		# Let go within a TAP's time, the hand still there: it was the TAP that
		# is offered there too.
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
		var stop_was: String = stop.id_now()
		cash = stop.buy(String(hand.anchor_id(_active_anchor)), cash)
		if stop.id_now() != stop_was:
			# The stop after a boss has become the stop he chose (GDD 9.6):
			# whoever stands at such a stop stands here.
			stop.hitcher = _hitcher_here()
	elif ritual_id == StopSim.PLACE:
		stop.place(String(hand.anchor_id(_active_anchor)), String(hand.anchor_id(hand.at_index)))
	elif ritual_id == StopSim.BOARD:
		# He unlocks the passenger door: the hitcher gets in (GDD 8.1).
		if board(stop.hitcher):
			stop.hitcher = ""
	else:
		# What the ritual requires may have gone while the gesture was made (a
		# crash spilled the glass, the phone rang out): then it is not done,
		# and nothing is announced.
		if not items.complete(_active_ritual, gesture.direction):
			return
		if items.paid != &"":
			_pay_the_officer(items.paid)
		if items.call_taken != &"":
			_take_the_call(items.call_taken)
		if items.key_turned:
			_turn_the_key()
		if items.handed != &"":
			_hand_out(items.handed)
		if ritual_id == ItemSim.UNSTOW:
			items.unstow_to(String(hand.anchor_id(hand.at_index)))
	heckles.in_ritual = StringName(ritual_id)
	prologue.ritual_done(ritual_id)
	_emit("ritual_completed", {
		"ritual": ritual_id,
		"anchor": String(hand.anchor_id(_active_anchor)),
		"direction": gesture.direction,
	})


## The ritual a press at an anchor begins now ({} for none). Where the night
## waits the hand does only what it is there for: at a stop the shopping
## (GDD 9.6: the vendor's tray, then the place of what he bought), and with
## an officer at his window what he hands him (GDD 6.5: his licence, or
## banknotes). The cabin's own rituals are the road's: what calms or loads
## him takes the hand off a wheel that matters (GDD 2.2, 12.4).
func _ritual_at(anchor: String) -> Dictionary:
	if stopped:
		return stop.ritual_at(anchor)
	if pulled_over:
		return items.ritual_for(PULLED_OVER, anchor)
	return items.ritual_at(anchor)


## True when the hand has something to do at an anchor now: on the road
## wherever a control or an item is, and where the night waits only where
## a ritual is offered it.
func _anchor_in_use(anchor: String) -> bool:
	if _standing():
		return not _ritual_at(anchor).is_empty()
	return items.anchor_in_use(anchor)


## What a press at an anchor would begin now, for the label that names it:
## the ritual's id; its gesture as the player makes it ("GATE" is a FLICK up
## or down while shifting is assisted); the ways a FLICK may go; the seconds
## of a HOLD or the turns of a CRANK; the item it belongs to. {} where there
## is nothing to do.
func hint_at(anchor: int) -> Dictionary:
	if anchor == HandSim.NO_ANCHOR:
		return {}
	var at: String = String(hand.anchor_id(anchor))
	var ritual: Dictionary = _ritual_at(at)
	if ritual.is_empty():
		# Nothing to do there now, but something may sit there that works by
		# itself (a keepsake): it is named all the same.
		for candidate: ItemSim.Item in items.items:
			if items.anchor_of(candidate) == at and not items.is_stowed(candidate):
				return {"ritual": "", "gesture": "", "dirs": [], "amount": 0.0, "item": String(candidate.id)}
		return {}
	return _hint_of(ritual)


func _hint_of(ritual: Dictionary) -> Dictionary:
	if ritual.is_empty():
		return {}
	var made: String = GameData.as_string(ritual.get("gesture"))
	var dirs: Array = GameData.as_array(ritual.get("flick_dirs")).duplicate()
	if made == "GATE" and sequential_shift:
		made = "FLICK"
		dirs = ["up", "down"]
	var amount: float = 0.0
	if made == "HOLD":
		amount = GameData.as_float(ritual.get("hold_s"))
	elif made == "CRANK":
		amount = GameData.as_float(ritual.get("turns"))
	return {
		"ritual": GameData.as_string(ritual.get("id")),
		"gesture": made,
		"dirs": dirs,
		"amount": amount,
		"item": GameData.as_string(ritual.get("item")),
	}


## The same for what his hand is busy with: the gesture being made, or the
## gear lever while he holds it.
func _hint_in_hand() -> Dictionary:
	if _lever_in_hand:
		return _hint_of(_ritual_at(String(hand.anchor_id(_lever_anchor))))
	if gesture.is_active():
		return _hint_of(_active_ritual)
	return {}


## The gesture a press at an anchor would begin now: "TAP", "HOLD", "FLICK",
## "DRAG", "DRAG_TO", "CRANK", "BEAD", "GATE" for the gear lever, "" where
## there is nothing to do. (For touch, GDD 17.4: a TAP performs by itself
## when the hand arrives; the others need the thumb.)
func gesture_at(anchor: int) -> String:
	if anchor == HandSim.NO_ANCHOR:
		return ""
	if anchor == _lever_anchor and not sequential_shift:
		return "GATE"
	return GameData.as_string(_ritual_at(String(hand.anchor_id(anchor))).get("gesture"))


## True while a press of the left button would take hold of nothing: the
## pointer on no anchor and off the wheel's rim, nothing carried, nothing
## held, no gesture begun. (A view's question: the game takes the button
## held there for its pause, D-066. Nothing in the simulation asks it.)
func hand_is_free() -> bool:
	return hand.snap_index == HandSim.NO_ANCHOR and not hand.gripping and not hand.pinned and not hand.carrying \
			and not gesture.is_active() and not _lever_in_hand and not space.pointer_on_rim(hand.pointer)


## The hand snaps only to anchors where something can be done now.
func _sync_anchors() -> void:
	for index: int in hand.anchor_count():
		var in_use: bool = _anchor_in_use(String(hand.anchor_id(index)))
		# What is carried can be put down where its ritual says.
		hand.set_anchor_active(index, in_use or (hand.carrying and _drag_destinations.has(index)))
	if not hand.carrying:
		return
	# Another anchor at the same place gives way to it (the radio's dial to the
	# tape deck, GDD 16.2): the pointer could not tell the two apart, and the
	# hand would rest on the one where the thing cannot be put down.
	for destination: int in _drag_destinations:
		if destination == HandSim.NO_ANCHOR:
			continue
		for index: int in hand.anchor_count():
			if not _drag_destinations.has(index) and hand.anchor_pointer(index).is_equal_approx(hand.anchor_pointer(destination)):
				hand.set_anchor_active(index, false)


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
