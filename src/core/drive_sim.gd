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
##    4. Wheel
##    5. Car: gear, speed, sideways motion, drift
##    6. Traffic            7. Collisions and close calls
##    8. Encounters         9. Effect timers, Nerves, faults
##   10. Clock             11. Heckles and passengers
##   12. Leg progress

const TICKS_PER_SECOND: int = 120
const DT: float = 1.0 / TICKS_PER_SECOND

const GEAR_LEVER: StringName = &"gear_lever"
const TAPE_DECK: StringName = &"tape"

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
var nerves: NervesSim = NervesSim.new()
var faults: FaultSim = FaultSim.new()
var rng: Rng = Rng.new()

var tick: int = 0
## Thousands of dinars (GDD 6). Never below zero.
var cash: float = 0.0
## True once every lamp is lit: the Telling is over (GDD 6.3).
var wrecked: bool = false
## Curve strength now: k of GDD 5.4, signed (+ pushes toward the right shoulder).
var curve_k: float = 0.0

## Settings the simulation reads (GDD 17.1).
var steer_sensitivity: float = 1.0
var sequential_shift: bool = false

var _events: Array[Dictionary] = []
## anchor index -> ritual record performed there.
var _ritual_at: Dictionary = {}
var _active_ritual: Dictionary = {}
var _active_anchor: int = HandSim.NO_ANCHOR
var _lever_anchor: int = HandSim.NO_ANCHOR
var _lever_in_hand: bool = false
var _gust_left: float = 0.0
var _gust_push: float = 0.0
var _gust_strength: float = 0.0
var _gust_duration: float = 0.0
var _grind_nerves: float = 0.0
var _braking: bool = false
var _forced_gear: int = 1


func _init(game_data: GameData) -> void:
	data = game_data
	tuning = game_data.tuning
	space.configure(data)
	hand.configure(data, space)
	wheel.configure(tuning)
	gate.configure(tuning)
	gesture.configure(tuning)
	car.configure(tuning)
	traffic.configure(data)
	collision.configure(tuning)
	nerves.configure(tuning)
	faults.configure(tuning)
	cash = tuning.f("cash_start")
	_gust_strength = tuning.f("gust_push")
	_gust_duration = tuning.f("gust_duration")
	_grind_nerves = tuning.f("gate_grind_nerves")
	_forced_gear = tuning.i("hit_forced_gear")
	var start_gear: int = tuning.i("start_gear")
	wheel.reset()
	gate.reset(start_gear)
	car.reset(car.lanes / 2, start_gear)
	_lever_anchor = hand.anchor_index(GEAR_LEVER)
	# The tape deck shares the radio's place; it opens when a Mixtape is fitted (GDD 7.4).
	hand.set_anchor_active(hand.anchor_index(TAPE_DECK), false)
	for ritual: Dictionary in data.records("rituals"):
		var index: int = hand.anchor_index(StringName(GameData.as_string(ritual.get("anchor"))))
		if index != HandSim.NO_ANCHOR and not _ritual_at.has(index):
			_ritual_at[index] = ritual


func seconds() -> float:
	return float(tick) * DT


func step(input: DriveInput) -> void:
	gate.begin_tick()

	# 1. Gesture recogniser.
	gesture.step(DT, input.lmb, input.pointer_delta)

	# 2. Hand.
	hand.step(DT, input, wheel.angle, 1.0)

	# 3. Rituals.
	_resolve_gesture()
	if _lever_in_hand and not input.lmb:
		gate.release()
		_lever_in_hand = false
		hand.unpin()
	if hand.press_applied:
		_begin_at(hand.at_index)

	# 4. Wheel.
	if hand.took_grip:
		wheel.grip()
	if hand.let_go:
		wheel.release()
	wheel.step(DT, hand.steer_px, steer_sensitivity)

	# 5. Car: gear, speed, sideways motion, drift.
	gate.step(DT, input.pointer_delta if _lever_in_hand else Vector2.ZERO, 1.0)
	if gate.ground:
		nerves.add(_grind_nerves)
		_emit("sfx_requested", {"id": "grind"})
	_braking = input.rmb
	car.step(DT, wheel.steer(), gate.gear, _braking, _extra_drift())

	# 6. Traffic.
	traffic.step(DT, car.s, car.x, car.speed)

	# 7. Collisions and close calls.
	collision.step(DT, car, traffic, gate.gear)
	_apply_collisions()

	tick += 1


## Sets the road the car is on: 1 to 3 lanes, divided or not (GDD 5.1).
func set_road(lanes: int, divided: bool) -> void:
	car.set_road(lanes, divided)


## Starts one gust (GDD 5.4): gust_push for gust_duration. `direction` is +1
## toward the right shoulder, -1 toward the left. `strength` scales it.
func start_gust(direction: int, strength: float = 1.0) -> void:
	_gust_left = _gust_duration
	_gust_push = _gust_strength * strength * float(direction)


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
		"lamps": faults.lamps,
		"lamp_capacity": faults.capacity,
		"cash": cash,
		"chain": collision.chain,
		"wrecked": wrecked,
		"vehicles": _vehicle_snapshots(),
	}


## One small dictionary per vehicle, positions relative to the car.
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


# --- Car ---------------------------------------------------------------------

## Every sideways push but the road's crown (GDD 5.4), m/s toward the right.
func _extra_drift() -> float:
	var push: float = car.curve_push(curve_k)
	if _gust_left > 0.0:
		_gust_left -= DT
		push += _gust_push
	return push


func _apply_collisions() -> void:
	if collision.hit != Collision.Hit.NONE:
		var lit: int = faults.light(collision.hit_lamps)
		nerves.add(collision.hit_nerves)
		if collision.hit_forces_gear:
			gate.force_gear(_forced_gear)
			if _lever_in_hand:
				_lever_in_hand = false
				hand.unpin()
		_emit("hit", {"kind": collision.hit, "lamps": lit, "vehicle": collision.hit_vehicle_id})
		if lit > 0:
			_emit("lamp_lit", {"lamps": faults.lamps, "lit": lit})
		if faults.is_wrecked() and not wrecked:
			wrecked = true
			_emit("wreck", {})
	if collision.close_calls > 0:
		cash += collision.close_call_cash
		nerves.add(collision.close_call_nerves + collision.honk_nerves)
		_emit("close_call", {
			"count": collision.close_calls,
			"cash": collision.close_call_cash,
			"mult": collision.close_call_mult,
			"chain": collision.chain,
		})


# --- Rituals -----------------------------------------------------------------

func _begin_at(anchor: int) -> void:
	if anchor == _lever_anchor and not sequential_shift:
		gate.press()
		_lever_in_hand = true
		hand.pin()
		return
	if not _ritual_at.has(anchor):
		return
	var ritual: Dictionary = _ritual_at[anchor]
	var kind: Gesture.Kind = _gesture_kind(ritual)
	if kind == Gesture.Kind.NONE:
		return
	_active_ritual = ritual
	_active_anchor = anchor
	gesture.begin(kind, _gesture_amount(ritual, kind), _gesture_dirs(ritual))
	if kind != Gesture.Kind.DRAG_TO:
		hand.pin()


func _resolve_gesture() -> void:
	if gesture.phase == Gesture.Phase.ACTIVE:
		if gesture.kind != Gesture.Kind.DRAG_TO and hand.at_index != _active_anchor:
			gesture.cancel()
		else:
			return
	if gesture.phase == Gesture.Phase.DONE:
		_complete_ritual()
	if gesture.phase != Gesture.Phase.IDLE:
		gesture.reset()
		_active_ritual = {}
		_active_anchor = HandSim.NO_ANCHOR
		hand.unpin()


func _complete_ritual() -> void:
	var ritual_id: String = GameData.as_string(_active_ritual.get("id"))
	if _active_anchor == _lever_anchor and sequential_shift:
		gate.shift_sequential(1 if gesture.direction == Gesture.DIR_UP else -1)
	_emit("ritual_completed", {
		"ritual": ritual_id,
		"anchor": String(hand.anchor_id(_active_anchor)),
		"direction": gesture.direction,
	})


func _gesture_kind(ritual: Dictionary) -> Gesture.Kind:
	match GameData.as_string(ritual.get("gesture")):
		"TAP":
			return Gesture.Kind.TAP
		"HOLD":
			return Gesture.Kind.HOLD
		"FLICK":
			return Gesture.Kind.FLICK
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
	_events.append(payload)
