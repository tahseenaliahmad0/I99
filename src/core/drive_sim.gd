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
var rng: Rng = Rng.new()

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
var in_encounter: bool = false
## Curve strength now: k of GDD 5.4, signed (+ pushes toward the right shoulder).
var curve_k: float = 0.0
## Sandbox only, until legs exist (M4): vehicles per km spawned ahead on an
## endless road. 0 switches it off; tests leave it off.
var free_traffic_per_km: float = 0.0

## Settings the simulation reads (GDD 17.1).
var steer_sensitivity: float = 1.0
var sequential_shift: bool = false

var _events: Array[Dictionary] = []
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
var _next_free_spawn_s: float = 0.0
var _forced_gear: int = 1
var _lane: int = 0
var _heavy_floors: PackedFloat64Array = PackedFloat64Array()
var _pound_mult: float = 1.0
var _shoulder_rate: float = 0.0
var _traffic_radius: float = 0.0
var _empty_radius: float = 0.0
var _rain_response: float = 1.0
## Lamps lit since the leg began (a clean leg lights none).
var _leg_lamps_lit: int = 0


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
	effects.configure(data)
	nerves.configure(tuning)
	faults.configure(data)
	items.configure(data, effects, nerves, traffic, car, faults)
	leg.configure(data, car, traffic)

	cash = tuning.f("cash_start")
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

	var start_gear: int = tuning.i("start_gear")
	wheel.reset()
	gate.reset(start_gear)
	car.reset(car.lanes / 2, start_gear)
	_lane = car.lane_of(car.x)
	_lever_anchor = hand.anchor_index(GEAR_LEVER)
	reseed(0)
	_sync_anchors()


## Sets the Telling seed: the four streams and the fault deck follow from it.
func reseed(telling_seed: int) -> void:
	rng.reseed(telling_seed)
	faults.shuffle_deck(rng)


func seconds() -> float:
	return float(tick) * DT


func step(input: DriveInput) -> void:
	gate.begin_tick()
	nerves.begin_tick()
	effects.begin_tick()
	items.begin_tick()
	leg.begin_tick()

	# 1. Gesture recogniser.
	gesture.step(DT, input.lmb, input.pointer_delta)

	# 2. Hand.
	hand.can_reach = nerves.snap_left <= 0.0
	hand.step(DT, input, wheel.angle, _pound_mult if nerves.pound else 1.0)

	# 3. Rituals.
	_resolve_gesture()
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
	car.step(DT, wheel.steer(), gate.gear, _braking, _extra_drift())
	var lane: int = car.lane_of(car.x)
	if lane != _lane:
		_lane = lane
		items.on_lane_line_crossed()

	# 6. Traffic.
	if free_traffic_per_km > 0.0:
		_step_free_traffic()
	leg.step_traffic(DT)
	traffic.step(DT, car.s, car.x, car.speed)

	# 7. Collisions and close calls.
	var lamps_before: int = faults.lamps
	collision.step(DT, car, traffic, gate.gear)
	_apply_collisions()
	_step_leg_hazards()
	_leg_lamps_lit += maxi(faults.lamps - lamps_before, 0)

	# 9. Effect timers, Nerves, faults.
	effects.step(DT)
	items.step(DT)
	_feed_nerves()
	nerves.step(DT)
	_report_nerves()
	_report_effects()
	cash = maxf(cash + items.cash_delta, 0.0)
	for event: Dictionary in items.events:
		_events.append(event)
	items.events.clear()

	# 12. Leg progress.
	if leg.step_progress():
		_end_leg()

	tick += 1


## Starts a leg from its plan (LegGenerator): the road, the car at the start
## in the plan's start lane, an empty road ahead, and the leg's weather.
func begin_leg(plan: Dictionary) -> void:
	set_road(GameData.as_int(plan.get("lanes"), 3), GameData.as_bool(plan.get("divided"), true))
	traffic.clear()
	collision.reset()
	car.reset(GameData.as_int(plan.get("start_lane")), gate.gear)
	_lane = car.lane_of(car.x)
	act = GameData.as_int(plan.get("act"), act)
	curve_k = 0.0
	items.begin_leg()
	leg.begin(plan)
	items.raining = leg.raining
	items.dust_rate = leg.dust_rate
	car.lat_tau_mult = _rain_response if leg.raining else 1.0
	_leg_lamps_lit = 0
	_emit("leg_started", {
		"leg": leg.leg_id,
		"modifier": GameData.as_string(plan.get("modifier")),
		"act": act,
		"par": leg.par,
	})


## The car passed the end of the leg: what it earned (GDD 12.1).
func _end_leg() -> void:
	var clean: bool = _leg_lamps_lit == 0
	var clean_bonus: float = tuning.f("clean_leg_bonus") if clean else 0.0
	var par_bonus: float = floorf(maxf(leg.par - leg.time, 0.0) * tuning.f("par_bonus_rate"))
	cash += clean_bonus + par_bonus
	items.raining = false
	items.dust_rate = 0.0
	car.lat_tau_mult = 1.0
	curve_k = 0.0
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
	if not leg.active:
		return
	leg.step_road(DT)
	curve_k = leg.curve_k
	if leg.gust_started != 0:
		start_gust(leg.gust_started)


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


## Starts one gust (GDD 5.4): gust_push for gust_duration. `direction` is +1
## toward the right shoulder, -1 toward the left. `strength` scales it.
func start_gust(direction: int, strength: float = 1.0) -> void:
	_gust_left = _gust_duration
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
		"visibility": visibility(),
		# Unlit things show only inside what he can see: at night they appear late.
		"hazards": leg.hazards_near(tuning.f("road_draw_behind"), minf(tuning.f("road_draw_ahead"), visibility())) if leg.active else [],
		"signs": leg.signs_near(minf(tuning.f("road_draw_ahead"), visibility())) if leg.active else [],
		"items": _item_snapshots(),
		"anchors_in_use": _anchors_in_use(),
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
		})
	return out


# --- Car ---------------------------------------------------------------------

## Every sideways push but the road's crown (GDD 5.4), m/s toward the right.
func _extra_drift() -> float:
	var push: float = car.curve_push(curve_k) - faults.param(FAULT_PULL, "drift_left", 0.0)
	if _gust_left > 0.0:
		_gust_left -= DT
		push += _gust_push
	return push


## Sandbox traffic: one vehicle every 1000 / free_traffic_per_km metres,
## spawn_ahead in front, in a lane and at a speed drawn from the road stream.
func _step_free_traffic() -> void:
	if car.s < _next_free_spawn_s:
		return
	_next_free_spawn_s = car.s + 1000.0 / free_traffic_per_km
	var types: PackedStringArray = data.record_ids("vehicles")
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
	nerves.add_rate(nerves.road_rate(near, nearest, in_encounter))
	if car.on_shoulder:
		nerves.add_rate(_shoulder_rate)
	nerves.add_rate(faults.param(FAULT_RATTLE, "nerves_per_s", 0.0))
	if car.on_rumble:
		nerves.jolt()


func _report_nerves() -> void:
	if nerves.snapped:
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
	var ritual: Dictionary = items.ritual_at(String(hand.anchor_id(anchor)))
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
	if kind != Gesture.Kind.DRAG_TO:
		hand.pin()


func _resolve_gesture() -> void:
	if gesture.phase == Gesture.Phase.ACTIVE:
		if gesture.kind != Gesture.Kind.DRAG_TO and hand.at_index != _active_anchor:
			gesture.cancel()
		else:
			_run_drag_steps()
			return
	if gesture.phase == Gesture.Phase.DONE:
		_run_drag_steps()
		_complete_ritual()
	if gesture.phase != Gesture.Phase.IDLE:
		gesture.reset()
		_active_ritual = {}
		_active_anchor = HandSim.NO_ANCHOR
		hand.eyes_down = false
		hand.unpin()
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
	else:
		items.complete(_active_ritual, gesture.direction)
	_emit("ritual_completed", {
		"ritual": ritual_id,
		"anchor": String(hand.anchor_id(_active_anchor)),
		"direction": gesture.direction,
	})


## The hand snaps only to anchors where something can be done now.
func _sync_anchors() -> void:
	for index: int in hand.anchor_count():
		hand.set_anchor_active(index, items.anchor_in_use(String(hand.anchor_id(index))))


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
	_events.append(payload)
