class_name CabinSuite
extends TestSuite
## Base of the suites about what is in the cabin (GDD 7): a DriveSim with a
## hand on it, driven the way a player drives it. The pointer goes to an
## anchor, the hand follows, and the button makes the gesture.
##
## Nobody is steering in these tests, so the road is kept under the car: each
## tick the car is put back in the middle of its lane (`_keep_lane`).

const DT: float = DriveSim.DT
const TABLE: String = "drivers"
## Ticks after a release for the ritual to be resolved and the hand let free.
const SETTLE: int = 4
## Ticks a TAP keeps the button down.
const TAP_TICKS: int = 4

var _sim: DriveSim
var _input: DriveInput
var _events: Array[Dictionary] = []
## Each tick the car is put back in the middle of the lane it is in.
var _keep_lane: bool = true
## The Clock when he last drove (read at a stall, before the stop charges it).
var _clock_at_stall: float = 0.0


func before_each() -> void:
	_input = DriveInput.new()
	_new_sim()


# --- The simulation ----------------------------------------------------------

## A new simulation outside any Telling: the starting cabin on an endless,
## empty road, with the road's own calm kept out of the Nerves (as in an
## encounter) so that a check reads only what it is about.
func _new_sim() -> void:
	_sim = DriveSim.new(fresh_data())
	_sim.in_encounter = true
	_events = []
	_keep_lane = true
	_input.clear()


func _tick() -> void:
	if _keep_lane and not _sim.stopped:
		_sim.car.x = _sim.car.lane_center(clampi(_sim.car.lane_of(_sim.car.x), 0, _sim.car.lanes - 1))
	_sim.step(_input)
	for event: Dictionary in _sim.drain_events():
		_events.append(event)


func _ticks(count: int) -> void:
	for _index: int in count:
		_tick()


func _run(seconds: float) -> void:
	_ticks(roundi(seconds / DT))


## Whole ticks in a time.
func _ticks_in(seconds: float) -> int:
	return roundi(seconds / DT)


## Third gear (or another) at cruise in a lane.
func _cruise(gear: int, lane: int) -> void:
	_sim.gate.reset(gear)
	_sim.car.reset(lane, gear)


# --- The hand ----------------------------------------------------------------

## The pointer goes to an anchor and stays there; the hand follows until it
## rests on it. False when it never gets there (nothing to do at the anchor).
func _reach(anchor: String) -> bool:
	_input.clear()
	_input.pointer_is_absolute = true
	_input.pointer = _sim.hand.anchor_pointer(_sim.hand.anchor_index(StringName(anchor)))
	var guard: int = _ticks_in(3.0)
	while _sim.hand.at_id() != StringName(anchor) and guard > 0:
		guard -= 1
		_tick()
	return _sim.hand.at_id() == StringName(anchor)


## Seconds the hand takes from the grip reference on the wheel to an anchor.
func _reach_time(anchor: String) -> float:
	_input.clear()
	_ticks(SETTLE)
	_sim.hand.place_at(_sim.space.grip_reference)
	var from_tick: int = _sim.tick
	if not _reach(anchor):
		return INF
	return float(_sim.tick - from_tick) * DT


## Gripping: the pointer pulled sideways `pixels` in all, over `ticks` ticks.
func _steer(pixels: float, ticks: int = 10) -> void:
	_input.pointer_is_absolute = false
	_input.lmb = true
	_input.pointer_delta = Vector2(pixels / float(ticks), 0.0)
	_ticks(ticks)
	_input.pointer_delta = Vector2.ZERO


## The button down for `ticks` ticks, then up.
func _press(ticks: int) -> void:
	_input.lmb = true
	_ticks(ticks)
	_input.lmb = false
	_ticks(SETTLE)


## A TAP where the hand is.
func _tap() -> void:
	_press(TAP_TICKS)


## A TAP at an anchor.
func _tap_at(anchor: String) -> void:
	_reach(anchor)
	_tap()


## The button held for a HOLD ritual of `seconds`: one tick more than the
## time, since the ritual begins on the tick the button goes down.
func _hold(seconds: float) -> void:
	_press(_ticks_in(seconds) + 1)


func _hold_at(anchor: String, seconds: float) -> void:
	_reach(anchor)
	_hold(seconds)


## A FLICK where the hand is: the button down and the pointer swept `travel`
## reference pixels over `ticks` ticks (y is downward).
func _flick(travel: Vector2, ticks: int = 10) -> void:
	_input.pointer_is_absolute = false
	_input.lmb = true
	_input.pointer_delta = travel / float(ticks)
	_ticks(ticks)
	_input.pointer_delta = Vector2.ZERO
	_input.lmb = false
	_ticks(SETTLE)


## A DRAG_TO: pressed at one anchor, carried to another, let go there.
func _drag(from: String, to: String) -> void:
	_reach(from)
	_input.lmb = true
	_ticks(_ticks_in(0.1))
	_input.pointer = _sim.hand.anchor_pointer(_sim.hand.anchor_index(StringName(to)))
	_ticks(_ticks_in(2.5))
	_input.lmb = false
	_ticks(_ticks_in(0.3))
	_input.clear()


## Pressed at an anchor, carried to each point in turn (free points of the
## cabin, where no anchor is), then to an anchor if one is named, and let go.
func _carry(from: String, points: Array[Vector3], to: String = "") -> void:
	_reach(from)
	_input.lmb = true
	_ticks(_ticks_in(0.1))
	for point: Vector3 in points:
		_input.pointer = _sim.space.point_to_pointer(point)
		_tick()
		var guard: int = _ticks_in(3.0)
		while _sim.hand.pos.distance_to(_sim.hand.target) > 0.001 and guard > 0:
			guard -= 1
			_tick()
		_ticks(SETTLE)
	if not to.is_empty():
		_input.pointer = _sim.hand.anchor_pointer(_sim.hand.anchor_index(StringName(to)))
		_tick()
		var guard: int = _ticks_in(3.0)
		while _sim.hand.at_id() != StringName(to) and guard > 0:
			guard -= 1
			_tick()
		_ticks(SETTLE)
	_input.lmb = false
	_ticks(SETTLE)


## A quiet leg outside a Telling: the leg's own encounter, and nothing else
## on the road. The car is in third gear in the plan's start lane.
func _begin_quiet_leg(leg_id: String, act: int, leg_seed: int) -> Dictionary:
	_sim = DriveSim.new(fresh_data())
	_events = []
	_keep_lane = true
	_input.clear()
	var plan: Dictionary = LegGenerator.generate(data, leg_id, act, leg_seed, "")
	for key: String in ["spawns", "hazards", "curves", "gusts", "zones"]:
		plan[key] = []
	_sim.gate.reset(3)
	_sim.begin_leg(plan)
	_sim.drain_events()
	return plan


## A boss by itself, outside a Telling, with no vehicle of its plan on the
## road: the car in third gear in the middle lane at the start of its road.
## Returns the plan.
func _begin_quiet_boss(boss_id: String, modifier: String = "", boss_seed: int = 1) -> Dictionary:
	_sim = DriveSim.new(fresh_data())
	_events = []
	_keep_lane = true
	_input.clear()
	var plan: Dictionary = BossSim.plan(data, boss_id, modifier, boss_seed)
	for key: String in ["spawns", "hazards", "curves"]:
		plan[key] = []
	_sim.gate.reset(3)
	_sim.begin_leg(plan)
	_sim.in_encounter = true
	_sim.drain_events()
	return plan


## The Checkpoint by itself (GDD 10.2), rolling in from its start in third
## gear in the middle lane; without its queue when `with_queue` is false.
## Returns the plan.
func _begin_checkpoint(modifier: String = "", boss_seed: int = 1, with_queue: bool = true) -> Dictionary:
	_sim = DriveSim.new(fresh_data())
	_events = []
	_keep_lane = true
	_input.clear()
	var plan: Dictionary = BossSim.plan(data, BossSim.CHECKPOINT, modifier, boss_seed)
	if not with_queue:
		var empty: Array = []
		for _lane: int in GameData.as_int(plan.get("lanes")):
			empty.append([])
		plan["queue"] = empty
	_sim.gate.reset(3)
	_sim.begin_leg(plan)
	_sim.in_encounter = true
	_sim.drain_events()
	return plan


## The car is set down standing with its nose at the Checkpoint's bar in
## `lane`, in first gear (the bar holds it), and waits there until the
## soldier starts toward it (the Stow phase). False when he never does.
func _stand_at_the_bar(lane: int = 1) -> bool:
	_cruise(1, lane)
	_sim.car.s = _sim.boss.bar_at - _sim.car.length() * 0.5
	_sim.car.speed = 0.0
	_input.clear()
	return _until_checkpoint_phase(BossSim.STOW, 3.0)


## Ticks until the Checkpoint is in `phase` (at most `seconds`). False when it never is.
func _until_checkpoint_phase(phase: int, seconds: float) -> bool:
	var guard: int = _ticks_in(seconds)
	while _sim.boss.phase != phase and guard > 0:
		guard -= 1
		_tick()
	return _sim.boss.phase == phase


## One sweep of the wipers, through the hand: a FLICK up on the stalk.
func _wipe() -> void:
	_reach("wiper_stalk")
	_flick(Vector2(0.0, -tuning.f("flick_min_distance") * 1.5))


## A CRANK where the hand is: the pointer led round in circles, `turns` and a
## little more, with the button down.
func _crank(turns: float) -> void:
	_input.pointer_is_absolute = false
	_input.lmb = true
	var heading: float = 0.0
	var step: float = deg_to_rad(12.0)
	for _index: int in ceili((turns + 0.6) * TAU / step):
		heading += step
		_input.pointer_delta = Vector2(cos(heading), sin(heading)) * 6.5
		_tick()
	_input.pointer_delta = Vector2.ZERO
	_input.lmb = false
	_ticks(SETTLE)


## A vehicle in the next lane passed with half of close_call_gap to spare, at
## `closing_kmh` more than its speed, in third gear with nobody steering.
## Returns the change in his Nerves over the pass; what happened is in _events.
func _pass_closely(type: String, closing_kmh: float) -> float:
	_cruise(3, 1)
	_sim.traffic.clear()
	_keep_lane = false
	_input.clear()
	var speed: float = tuning.fi("gear_speeds", 2)
	var other: TrafficSim.Vehicle = _sim.traffic.spawn(StringName(type), 0, _sim.car.s + 12.0, speed - closing_kmh)
	var beside: float = other.x + other.half_width + _sim.car.half_width() + tuning.f("close_call_gap") * 0.5
	_events = []
	var before: float = _sim.nerves.value
	var guard: int = _ticks_in(30.0)
	while _sim.car.s < other.s + other.half_length + 8.0 and guard > 0:
		guard -= 1
		_sim.car.x = beside
		_tick()
	_keep_lane = true
	_sim.traffic.clear()
	return _sim.nerves.value - before


## The hand on the wheel, gripping, with the button held.
func _grip() -> void:
	_input.clear()
	_input.pointer_is_absolute = true
	_input.pointer = _sim.space.point_to_pointer(_sim.space.grip_reference)
	_input.lmb = true
	var guard: int = _ticks_in(3.0)
	while not _sim.hand.gripping and guard > 0:
		guard -= 1
		_tick()


## Lets go of whatever the button holds.
func _release() -> void:
	_input.clear()
	_ticks(SETTLE)


# --- Items -------------------------------------------------------------------

## Puts an item in the cabin (as debug key F5 does), in a slot or in the
## first free one it fits.
func _give(item_id: String, slot: String = "") -> ItemSim.Item:
	var given: ItemSim.Item = _sim.give_item(StringName(item_id), StringName(slot))
	if given == null:
		fail("'%s' could not be put in the cabin" % item_id)
	return given


func _item(item_id: String) -> ItemSim.Item:
	return _sim.items.item(StringName(item_id))


## The anchor where an item's rituals are performed.
func _anchor_of(item_id: String) -> String:
	var owned: ItemSim.Item = _item(item_id)
	return _sim.items.anchor_of(owned) if owned != null else ""


func _record(item_id: String) -> Dictionary:
	return data.record("items", item_id)


func _ritual(ritual_id: String) -> Dictionary:
	return data.record("rituals", ritual_id)


func _params(item_id: String) -> Dictionary:
	return GameData.as_dict(_record(item_id).get("params"))


func _supply_spec(item_id: String) -> Dictionary:
	return GameData.as_dict(_record(item_id).get("supply"))


## How long an item's "gives" say a status lasts.
func _give_duration(item_id: String, effect: String) -> float:
	for give: Variant in GameData.as_array(_record(item_id).get("gives")):
		var entry: Dictionary = GameData.as_dict(give)
		if GameData.as_string(entry.get("effect")) == effect:
			return GameData.as_float(entry.get("duration"))
	return 0.0


## The amount of the first "gives" entry on a resource (and under a
## condition, if one is named).
func _give_amount(item_id: String, resource: String, condition: String = "") -> float:
	for give: Variant in GameData.as_array(_record(item_id).get("gives")):
		var entry: Dictionary = GameData.as_dict(give)
		if GameData.as_string(entry.get("resource")) != resource:
			continue
		if GameData.as_string(entry.get("while")) == condition:
			return GameData.as_float(entry.get("amount"))
	return 0.0


# --- Events ------------------------------------------------------------------

func _event(type: String) -> Dictionary:
	for index: int in range(_events.size() - 1, -1, -1):
		if GameData.as_string(_events[index].get("type")) == type:
			return _events[index]
	return {}


func _count_events(type: String, key: String = "", value: String = "") -> int:
	var count: int = 0
	for event: Dictionary in _events:
		if GameData.as_string(event.get("type")) != type:
			continue
		if key.is_empty() or GameData.as_string(event.get(key)) == value:
			count += 1
	return count


# --- A Telling and its stops -------------------------------------------------

## The first seed whose first fork has a `stop_id` at the end of its right
## branch (or the one after `skip` such seeds).
func _seed_for(stop_id: String, skip: int = 0) -> int:
	for candidate: int in range(1, 4000):
		if GameData.as_string(RunGenerator.fork(data, candidate, 1, 0)[RunState.RIGHT]["stop"]) == stop_id:
			if skip == 0:
				return candidate
			skip -= 1
	fail("no seed under 4000 leads to a %s" % stop_id)
	return 1


## A Telling on its first leg, the one that ends at a `stop_id`, with nothing
## on the road and the car in third gear.
func _to_quiet_leg(stop_id: String, skip: int = 0) -> void:
	_sim = DriveSim.new(fresh_data())
	_events = []
	_keep_lane = true
	_input.clear()
	_sim.begin_telling(TABLE, _seed_for(stop_id, skip))
	var guard: int = _ticks_in(60.0)
	while _sim.run.stage == RunState.Stage.APPROACH and guard > 0:
		guard -= 1
		_sim.step(_input)
	var plan: Dictionary = RunGenerator.plan(data, _sim.run.branch, _sim.run.act)
	for key: String in ["spawns", "hazards", "curves", "gusts", "zones"]:
		plan[key] = []
	for key: String in ["flock", "melons", "motorcade"]:
		plan[key] = {}
	_sim.gate.reset(3)
	_sim.begin_leg(plan)
	_sim.in_encounter = true
	_sim.drain_events()


## Lights one lamp on the way: a scrape along the guardrail.
func _scrape() -> void:
	var lamps: int = _sim.faults.lamps
	var lane_x: float = _sim.car.x
	var guard: int = _ticks_in(5.0)
	_input.clear()
	while _sim.faults.lamps == lamps and guard > 0:
		guard -= 1
		_sim.car.x = _sim.car.guardrail_x()
		_sim.step(_input)
	# Back in his lane, and past the hit's immunity.
	for _index: int in _ticks_in(tuning.f("hit_immunity") + 0.2):
		_sim.car.x = lane_x
		_sim.step(_input)
	_sim.gate.reset(3)
	for event: Dictionary in _sim.drain_events():
		_events.append(event)


## One scrape along the guardrail, whether or not it lights a lamp; then
## back in his lane, in third gear, past the hit's immunity. Returns the hit.
func _scrape_rail() -> Dictionary:
	var lane_x: float = _sim.car.x
	var hit: Dictionary = {}
	var guard: int = _ticks_in(5.0)
	_input.clear()
	while hit.is_empty() and guard > 0:
		guard -= 1
		_sim.car.x = _sim.car.guardrail_x()
		_sim.step(_input)
		for event: Dictionary in _sim.drain_events():
			_events.append(event)
			if GameData.as_string(event.get("type")) == "hit":
				hit = event
	for _index: int in _ticks_in(tuning.f("hit_immunity") + 0.2):
		_sim.car.x = lane_x
		_sim.step(_input)
	_sim.gate.reset(3)
	for event: Dictionary in _sim.drain_events():
		_events.append(event)
	return hit


## Drives the Telling on, each stretch to its end at once and through every
## stop, until `act` has begun.
func _drive_on_to_act(act: int) -> void:
	var guard: int = 40000
	_input.clear()
	while _sim.run.act < act and guard > 0:
		guard -= 1
		if _sim.stopped:
			_leave_stop()
			continue
		_sim.car.x = _sim.car.lane_center(1 if _sim.car.lanes > 1 else 0)
		if _sim.leg.active and _sim.car.s < _sim.leg.length - 2.0:
			_sim.car.s = _sim.leg.length - 1.0
		_sim.step(_input)
	for event: Dictionary in _sim.drain_events():
		_events.append(event)
	check_eq(_sim.run.act, act, "(act %d)" % act)


## Drives on past the next fork into the leg behind it (the right branch),
## with nothing on that leg's road.
func _into_next_quiet_leg() -> void:
	var guard: int = _ticks_in(120.0)
	var legs_done: int = _sim.run.legs_done
	var on_approach: bool = _sim.run.stage == RunState.Stage.APPROACH
	_input.clear()
	while not (_sim.run.stage == RunState.Stage.LEG and (on_approach or _sim.run.legs_done > legs_done)) and guard > 0:
		guard -= 1
		_sim.car.x = _sim.car.lane_center(_sim.car.lanes - 1)
		if _sim.leg.active and _sim.car.s < _sim.leg.length - 2.0:
			_sim.car.s = _sim.leg.length - 1.0
		_sim.step(_input)
	var plan: Dictionary = RunGenerator.plan(data, _sim.run.branch, _sim.run.act)
	for key: String in ["spawns", "hazards", "curves", "gusts", "zones"]:
		plan[key] = []
	for key: String in ["flock", "melons", "motorcade"]:
		plan[key] = {}
	_sim.gate.reset(3)
	_sim.begin_leg(plan)
	_sim.in_encounter = true
	_sim.drain_events()


## Into the slip lane and to the stall in second gear: he stops. (A stop
## makes the simulation anew from what a save holds: look items up again.)
func _into_stall() -> void:
	var stall: float = _sim.leg.length - tuning.f("leg_tail") + tuning.f("exit_slip_length")
	var lanes: int = _sim.car.lanes
	_sim.car.s = stall - 20.0
	_sim.gate.reset(2)
	_input.clear()
	var guard: int = _ticks_in(10.0)
	while not _sim.stopped and guard > 0:
		guard -= 1
		_sim.car.x = _sim.car.lane_center(lanes)
		_sim.car.speed = tuning.f("exit_max_speed")
		_clock_at_stall = _sim.clock.minutes
		_sim.step(_input)
	for event: Dictionary in _sim.drain_events():
		_events.append(event)
	check(_sim.stopped, "(he stops at the stall)")


## Grips the wheel until he has left the stop.
func _leave_stop() -> void:
	_input.clear()
	_ticks(_ticks_in(0.2))
	_input.pointer_is_absolute = true
	_input.pointer = _sim.space.point_to_pointer(_sim.space.grip_reference)
	_input.lmb = true
	var guard: int = _ticks_in(5.0)
	while _sim.stopped and guard > 0:
		guard -= 1
		_tick()
	_input.clear()
	_tick()
	_sim.in_encounter = true


## What lies on the vendor's tray.
func _offers() -> Array[Dictionary]:
	var offers: Array[Dictionary] = _sim.snapshot()["offers"]
	return offers


## The offer of a kind for an id ({} when there is none).
func _offer(kind: StringName, id: String) -> Dictionary:
	for offer: Dictionary in _offers():
		if offer["kind"] == kind and GameData.as_string(offer["id"]) == id:
			return offer
	return {}
