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

var tick: int = 0

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


func _init(game_data: GameData) -> void:
	data = game_data
	tuning = game_data.tuning
	space.configure(data)
	hand.configure(data, space)
	wheel.configure(tuning)
	gate.configure(tuning)
	gesture.configure(tuning)
	wheel.reset()
	gate.reset(1)
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

	# 5. Car: the gear lever.
	gate.step(DT, input.pointer_delta if _lever_in_hand else Vector2.ZERO, 1.0)
	if gate.ground:
		_emit("sfx_requested", {"id": "grind"})

	tick += 1


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
	}


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
