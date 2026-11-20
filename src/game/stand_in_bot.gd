class_name StandInBot
extends RefCounted
## The stand-in for the DriverBot of GDD 13.8 (M11), behind `--bot=`: it puts
## the car on a line and works the gear, the brake and the hand through the
## input, so that a leg, a set piece or a whole Telling can be looked at with
## nobody at the wheel. It is no player: it sets the car where it wants it,
## knows what the dust hides, and lets the Call ring out.

const KMH_TO_MS: float = 1.0 / 3.6
## Seconds it stands at a stop before it takes the wheel to leave.
const STOP_WAIT: float = 2.0
## How fast it lets the car slide across the road, m/s.
const SLIDE: float = 4.0
## A lane counts as blocked with less than this much free road in it (m); it
## moves over for a lane with this much more, and at least this much.
const LANE_ROOM: float = 80.0
const LANE_GAIN: float = 10.0
const LANE_LEAST: float = 30.0
## A vehicle this far behind its middle still fills the lane beside it (m).
const LANE_BEHIND: float = 15.0
## It brakes with less than this much room ahead (m), and this many seconds'
## worth of its speed.
const BRAKE_ROOM: float = 10.0
const BRAKE_TIME: float = 0.8
## In a queue: the room it keeps, and the time it allows itself to react.
const QUEUE_ROOM: float = 1.5
const QUEUE_TIME: float = 0.15
## Metres into the closing barriers at which it drops to second gear.
const SLOW_INTO_BARRIERS: float = 10.0
## Ticks the button is held or let go between the steps of the hand's work.
const TAP_TICKS: int = 4
const REST_TICKS: int = 6
const PICK_UP_TICKS: int = 12
const LET_GO_TICKS: int = 30
## The crank: degrees of a turn each tick, and how far the pointer goes with it.
const CRANK_STEP: float = 12.0
const CRANK_REACH: float = 6.5

var _sim: DriveSim
var _tuning: Tuning
var _data: GameData
var _plan: Dictionary = {}
## Seconds it has stood at a stop.
var _stood: float = 0.0
## What the hand still has to do: ["go", anchor], ["down", ticks], ["up",
## ticks], ["carry", anchor], ["crank"].
var _hand_steps: Array[Array] = []
var _crank_heading: float = 0.0
var _key_ticks: int = 0


func _init(sim: DriveSim, data: GameData) -> void:
	_sim = sim
	_data = data
	_tuning = data.tuning


## One tick of driving: what it does with the brake and the hand goes into
## `input`, the gear and the car's place across the road straight onto the car.
func drive(input: DriveInput) -> void:
	if _sim.stopped:
		# A moment at the stop, then the wheel is held until he is off.
		_stood += DriveSim.DT
		if _stood > STOP_WAIT:
			input.pointer_is_absolute = true
			input.pointer = _sim.space.point_to_pointer(_sim.space.grip_reference)
			input.lmb = true
		return
	_stood = 0.0
	if not _sim.leg.active or _sim.wrecked or _sim.leg.on_side_road:
		return
	if not is_same(_plan, _sim.leg.plan):
		_plan = _sim.leg.plan
		_hand_steps = []
	var car: CarSim = _sim.car
	if _sim.boss.active:
		_drive_set_piece(input)
		return
	if not _sim.run.active:
		car.x = _line_x(car.s)
		return
	var gear: int = 3
	var x: float = _line_x(car.s)
	var slip: Vector2 = _sim.exit_slip()
	if slip.x >= 0.0 and car.s >= slip.x:
		# Into the slip lane in second gear: he stops at every stop.
		gear = 2
		x = lerpf(x, car.lane_center(car.lanes - 1), clampf((car.s - slip.x) / (0.5 * (slip.y - slip.x)), 0.0, 1.0))
	elif _sim.run.fork_ahead() and _sim.leg.length - car.s < 120.0:
		# The left branch on even legs, the right on odd ones.
		var side: float = 0.25 if _sim.run.legs_done % 2 == 0 else 0.75
		x = lerpf(x, car.road_right() * side, clampf(1.0 - (_sim.leg.length - car.s - 40.0) / 80.0, 0.0, 1.0))
	if _sim.gate.gear != gear:
		_sim.gate.reset(gear)
	car.x = x


# --- Set pieces --------------------------------------------------------------

func _drive_set_piece(input: DriveInput) -> void:
	var car: CarSim = _sim.car
	var boss: BossSim = _sim.boss
	var gear: int = 3
	var x: float = car.x
	match boss.kind:
		BossSim.DAWN:
			# The plan's line as far as the last checkpoint, in second gear
			# between its barriers; after it, wherever the road is clear.
			var barriers: Vector3 = boss.corridor()
			if car.s < barriers.z:
				x = _line_x(car.s)
			else:
				x = _clear_lane_x(input)
			if car.s > barriers.x + SLOW_INTO_BARRIERS and car.s < barriers.z:
				gear = 2
		BossSim.CHECKPOINT:
			# The middle lane's queue in first gear, on the brake behind
			# whatever is ahead and at the bar; then the window and whatever
			# the soldier's sign asks for.
			var lane: int = car.lanes / 2
			x = car.lane_center(lane)
			gear = 2 if boss.released else _tuning.i("start_gear")
			_brake_behind(lane, input)
			if boss.phase == BossSim.PAPERS and _hand_steps.is_empty():
				_plan_the_papers()
			_work_the_hand(input)
		BossSim.ARRIVAL:
			gear = _tuning.i("start_gear")
			x = car.lane_center(0)
			_park_and_turn_the_key(input)
		_:
			x = _clear_lane_x(input)
	if _sim.gate.gear != gear:
		_sim.gate.reset(gear)
	car.x = move_toward(car.x, x, SLIDE * DriveSim.DT)


## Where the road is clear: when what is ahead in his lane comes near he
## moves to a lane with clearly more room, beside him and ahead; where there
## is none he brakes behind what is in front of him.
func _clear_lane_x(input: DriveInput) -> float:
	var car: CarSim = _sim.car
	var lane: int = clampi(car.lane_of(car.x), 0, car.lanes - 1)
	var room: float = _room(lane, 0.0)
	if room < LANE_ROOM:
		for other: int in car.lanes:
			var there: float = _room(other, -LANE_BEHIND)
			if there > room + LANE_GAIN and there > LANE_LEAST:
				lane = other
				room = there
	if room < BRAKE_ROOM + car.speed * KMH_TO_MS * BRAKE_TIME:
		input.rmb = true
	return car.lane_center(lane)


## Metres of a lane that are free, bumper to bumper, counting the vehicles
## whose middle is more than `from` metres ahead of the car's.
func _room(lane: int, from: float) -> float:
	var car: CarSim = _sim.car
	var room: float = INF
	for vehicle: TrafficSim.Vehicle in _sim.traffic.vehicles:
		if absf(vehicle.x - car.lane_center(lane)) >= car.lane_width() * 0.5 + vehicle.half_width:
			continue
		var gap: float = vehicle.s - car.s
		if gap > from:
			room = minf(room, gap - vehicle.half_length - car.length() * 0.5)
	return room


## The brake goes on behind whatever is ahead in `lane`, and before the
## Checkpoint's bar while it is down.
func _brake_behind(lane: int, input: DriveInput) -> void:
	var car: CarSim = _sim.car
	var room: float = INF
	if not _sim.boss.released:
		room = _sim.boss.bar_at - (car.s + car.length() * 0.5)
	for vehicle: TrafficSim.Vehicle in _sim.traffic.vehicles:
		if absf(vehicle.x - car.lane_center(lane)) < car.lane_width() * 0.5 and vehicle.s > car.s:
			room = minf(room, vehicle.s - vehicle.half_length - car.s - car.length() * 0.5)
	var speed_ms: float = car.speed * KMH_TO_MS
	if room < QUEUE_ROOM + speed_ms * speed_ms / (2.0 * _tuning.f("brake_decel") * KMH_TO_MS) + speed_ms * QUEUE_TIME:
		input.rmb = true


## What the hand must do for the soldier (GDD 10.2): the window, if it is
## shut; then the document his sign asks for, from where it is kept.
func _plan_the_papers() -> void:
	if not _sim.items.flag(ItemSim.FLAG_WINDOW):
		_hand_steps.append(["go", "window_crank"])
		_hand_steps.append(["crank"])
		_hand_steps.append(["up", REST_TICKS])
		return
	var from: String = "dash_1"
	match _sim.boss.wanted:
		"id":
			from = "pocket"
		"registration":
			from = ItemSim.GLOVEBOX
			if not _sim.items.flag(ItemSim.FLAG_GLOVEBOX):
				# A TAP opens the glovebox.
				_hand_steps.append(["go", from])
				_hand_steps.append(["down", TAP_TICKS])
				_hand_steps.append(["up", REST_TICKS])
				return
			if not _sim.items.flag(&"letter_aside"):
				# The letter lies on top: it is held aside.
				var hold: float = GameData.as_float(_data.record("rituals", "letter_aside").get("hold_s"))
				_hand_steps.append(["go", from])
				_hand_steps.append(["down", int(hold / DriveSim.DT) + 2])
				_hand_steps.append(["up", REST_TICKS])
				return
	_hand_steps.append(["go", from])
	_hand_steps.append(["down", PICK_UP_TICKS])
	_hand_steps.append(["carry", "driver_window"])
	_hand_steps.append(["up", LET_GO_TICKS])


## One tick of the hand's work: "go" (the pointer on an anchor until the hand
## rests there), "down" and "up" (the button, for so many ticks), "carry"
## (the button down, the pointer on another anchor until the hand is there),
## "crank" (the button down, the pointer led round until the window is open).
func _work_the_hand(input: DriveInput) -> void:
	if _hand_steps.is_empty():
		return
	var step: Array = _hand_steps[0]
	var what: String = step[0]
	match what:
		"go", "carry":
			var anchor: StringName = StringName(GameData.as_string(step[1]))
			input.pointer_is_absolute = true
			input.pointer = _sim.hand.anchor_pointer(_sim.hand.anchor_index(anchor))
			input.lmb = what == "carry"
			if _sim.hand.at_id() == anchor:
				_hand_steps.remove_at(0)
		"down", "up":
			input.lmb = what == "down"
			step[1] = GameData.as_int(step[1]) - 1
			if GameData.as_int(step[1]) <= 0:
				_hand_steps.remove_at(0)
		"crank":
			_crank_heading += deg_to_rad(CRANK_STEP)
			input.lmb = true
			input.pointer_delta = Vector2(cos(_crank_heading), sin(_crank_heading)) * CRANK_REACH
			if _sim.items.flag(ItemSim.FLAG_WINDOW):
				_hand_steps.remove_at(0)


## The Arrival (GDD 10.5): the brake goes on in time to stop in the middle of
## the bay; standing there, the hand goes to the key and taps it.
func _park_and_turn_the_key(input: DriveInput) -> void:
	var car: CarSim = _sim.car
	var boss: BossSim = _sim.boss
	var speed_ms: float = car.speed * KMH_TO_MS
	var stopping: float = speed_ms * speed_ms / (2.0 * _tuning.f("brake_decel") * KMH_TO_MS)
	if car.s + stopping >= (boss.bay_from + boss.bay_to) * 0.5:
		input.rmb = true
	if not boss.in_bay:
		_key_ticks = 0
		return
	var key: int = _sim.hand.anchor_index(&"key")
	input.pointer_is_absolute = true
	input.pointer = _sim.hand.anchor_pointer(key)
	if _sim.hand.at_index == key:
		_key_ticks += 1
		input.lmb = _key_ticks <= TAP_TICKS


# --- The plan's line ---------------------------------------------------------

## Where across the road the plan's line is at `s`: the middle of the lane
## the plan drives in, moving over during gen_lane_change metres.
func _line_x(s: float) -> float:
	var path: Array = GameData.as_array(_plan.get("path"))
	if path.is_empty():
		return _sim.car.x
	var change: float = _tuning.f("gen_lane_change")
	var x: float = _lane_x(GameData.as_int(GameData.as_array(path[0])[1]))
	for index: int in range(1, path.size()):
		var at: Array = GameData.as_array(path[index])
		var from_s: float = GameData.as_float(at[0])
		if s < from_s:
			break
		var before: Array = GameData.as_array(path[index - 1])
		x = lerpf(_lane_x(GameData.as_int(before[1])), _lane_x(GameData.as_int(at[1])), clampf((s - from_s) / change, 0.0, 1.0))
	return x


func _lane_x(lane: int) -> float:
	if lane == LegGenerator.SHOULDER_LANE:
		return (_sim.car.road_right() + _sim.car.guardrail_x()) * 0.5
	return _sim.car.lane_center(lane)
