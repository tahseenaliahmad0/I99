extends TestSuite
## M3: Nerves, the two-sided meter (GDD 5.8, 6.1).

const DT: float = DriveSim.DT

var _sim: DriveSim
var _input: DriveInput
## When set (0 to 100), Nerves are put back to this value before every step,
## so a test can hold him at a level while time passes.
var _pinned_nerves: float = -1.0


func before_each() -> void:
	_sim = DriveSim.new(fresh_data())
	_input = DriveInput.new()
	_pinned_nerves = -1.0


## T-NERVES-01: each threshold switches its impairment on and off; a Snap
## resets Nerves to 70.
func test_nerves_01() -> void:
	var tremor_from: float = tuning.f("tremor_from")
	var tunnel_from: float = tuning.f("tunnel_from")
	var pound_from: float = tuning.f("pound_from")
	var snap_at: float = tuning.f("snap_at")
	var max_amp: float = tuning.f("tremor_max_amplitude")

	# --- Tremor: the gripped wheel oscillates.
	_grip_wheel()
	_pinned_nerves = tremor_from - 1.0
	var swing: Vector2 = _wheel_swing(1.0)
	check_near(swing.y - swing.x, 0.0, 0.000001, "below tremor_from the gripped wheel is still")
	check_near(_sim.nerves.tremor_amplitude, 0.0, 0.000001, "and Tremor is off")

	var level: float = (tremor_from + snap_at) * 0.5
	_pinned_nerves = level
	var expected_amp: float = max_amp * (level - tremor_from) / (snap_at - tremor_from)
	swing = _wheel_swing(2.0)
	check_near((swing.y - swing.x) * 0.5, expected_amp, expected_amp * 0.02, "above tremor_from the gripped wheel swings by the Tremor amplitude")
	check_near(_sim.nerves.tremor_amplitude, expected_amp, 0.000001, "which grows in a straight line from tremor_from to snap_at")
	check_near(_zero_crossings_per_second(2.0), tuning.f("tremor_frequency") * 2.0, 0.6, "at tremor_frequency")

	_pinned_nerves = snap_at - 0.5
	_run(0.1)
	check_near(_sim.nerves.tremor_amplitude, max_amp * (snap_at - 0.5 - tremor_from) / (snap_at - tremor_from), 0.000001, "close to snap_at the amplitude is close to tremor_max_amplitude")

	_pinned_nerves = tremor_from - 1.0
	_run(0.5)
	swing = _wheel_swing(1.0)
	check_near(swing.y - swing.x, 0.0, 0.000001, "back below tremor_from the wheel is still again")

	# Not gripped: the wheel does not shake by itself.
	_input.clear()
	_pinned_nerves = level
	_run(2.0)
	swing = _wheel_swing(1.0)
	check_near(swing.y - swing.x, 0.0, 0.000001, "Tremor shakes the gripped wheel only")

	# --- Tunnel.
	_pinned_nerves = tunnel_from - 1.0
	_run(0.1)
	check_near(_sim.nerves.tunnel, 0.0, 0.000001, "below tunnel_from the view is whole")
	_pinned_nerves = (tunnel_from + snap_at) * 0.5
	_run(0.1)
	check_near(_sim.nerves.tunnel, 0.5, 0.000001, "half-way from tunnel_from to snap_at the view is half-way narrowed")
	check_near(_snapshot_float("tunnel"), 0.5, 0.000001, "the snapshot carries it for the post effect")
	_pinned_nerves = tunnel_from - 1.0
	_run(0.1)
	check_near(_sim.nerves.tunnel, 0.0, 0.000001, "and whole again below it")
	check(tuning.f("tunnel_min_view") < 1.0, "tunnel_min_view says how narrow the view gets at 100")

	# --- Pound: the hand slows.
	_pinned_nerves = pound_from - 1.0
	var normal: float = _hand_speed()
	check_near(normal, tuning.f("hand_speed"), 0.0001, "below pound_from the hand moves at hand_speed")
	check(not _sim.nerves.pound, "and Pound is off")
	_pinned_nerves = pound_from
	var pounding: float = _hand_speed()
	check_near(pounding / normal, tuning.f("hand_pound_mult"), 0.0001, "from pound_from the hand moves at hand_pound_mult of that")
	check(_sim.nerves.pound, "and Pound is on")
	_pinned_nerves = pound_from - 1.0
	check_near(_hand_speed(), normal, 0.0001, "and back to normal below it")

	# --- The thresholds are announced as they are crossed.
	_pinned_nerves = -1.0
	_sim = DriveSim.new(fresh_data())
	_sim.drain_events()
	_sim.nerves.value = pound_from + 1.0
	_sim.step(_input)
	var on: Array[String] = _crossings(true)
	check(on.has("tremor") and on.has("tunnel") and on.has("pound"), "going up, each threshold crossed is announced")
	_sim.nerves.value = tremor_from - 5.0
	_sim.step(_input)
	var off: Array[String] = _crossings(false)
	check(off.has("tremor") and off.has("tunnel") and off.has("pound"), "and again coming down")

	# --- Snap.
	_sim = DriveSim.new(fresh_data())
	_grip_wheel()
	_sim.drain_events()
	_sim.nerves.value = snap_at - 1.0
	_sim.nerves.add(5.0)
	check(_sim.nerves.snapped, "reaching snap_at is a Snap")
	check_eq(_sim.nerves.value, tuning.f("snap_reset"), "a Snap resets Nerves to snap_reset")
	check_near(tuning.f("snap_reset"), 70.0, 0.000001, "which GDD 15 sets at 70")
	check_near(_sim.nerves.snap_left, tuning.f("snap_duration"), 0.000001, "he leans on the horn for snap_duration")
	_sim.step(_input)

	# He can steer...
	_input.pointer_delta = Vector2(20.0, 0.0)
	_sim.step(_input)
	_input.pointer_delta = Vector2.ZERO
	_run(0.3)
	check(_sim.hand.gripping, "during a Snap he keeps the wheel")
	check(absf(_sim.wheel.command) > 1.0, "and can steer")

	# ...and cannot reach: a click on the horn does nothing.
	_sim = DriveSim.new(fresh_data())
	_sim.nerves.value = snap_at - 1.0
	_sim.nerves.add(5.0)
	_sim.drain_events()
	_input.clear()
	_input.pointer_is_absolute = true
	_input.pointer = _sim.hand.anchor_pointer(_sim.hand.anchor_index(&"horn"))
	var horn_ticks: int = int((tuning.f("snap_duration") - 0.3) / DT)
	for tick: int in horn_ticks:
		_input.lmb = tick % 30 < 4
		_sim.step(_input)
	check(not _completed("horn"), "during a Snap he cannot reach: a click on the horn does nothing")
	check_eq(_sim.hand.snap_index, HandSim.NO_ANCHOR, "the pointer snaps to nothing")
	_input.lmb = false
	_run(0.6)
	for tick: int in 120:
		_input.lmb = tick % 30 < 4
		_sim.step(_input)
	check(_completed("horn"), "after the Snap he can reach again")

	# The Snap is announced, with the horn.
	_sim = DriveSim.new(fresh_data())
	_sim.drain_events()
	_sim.nerves.value = snap_at - 0.01
	_sim.traffic.spawn(&"car", 1, _sim.car.s + 10.0, _sim.car.speed)
	_run(1.0)
	var kinds: Array[String] = []
	var horn: bool = false
	for event: Dictionary in _sim.drain_events():
		kinds.append(str(event.get("type")))
		if event.get("type") == "sfx_requested" and event.get("id") == "horn":
			horn = true
	check(kinds.has("snap"), "traffic alone can push him over: the Snap is announced as an event")
	check_eq(kinds.count("snap"), 1, "once")
	check(horn, "with the horn")
	check(_sim.nerves.value < snap_at - 20.0, "and Nerves have dropped back")


## T-NERVES-02: below the floor and not Awake, a blink of 0.3 s every 6 s with
## a tell 1 s before.
func test_nerves_02() -> void:
	var period: float = tuning.f("blink_period")
	var length: float = tuning.f("blink_length")
	var tell: float = tuning.f("blink_tell")
	check_near(period, 6.0, 0.000001, "GDD 15: a blink every 6 s")
	check_near(length, 0.3, 0.000001, "GDD 15: 0.3 s long")
	check_near(tell, 1.0, 0.000001, "GDD 15: the tell comes 1 s before")

	# Act 2: the floor is 15. At 10 he is Heavy but not deep enough to Nod.
	_sim.act = 2
	var floor_level: float = _sim.heavy_floor()
	_pinned_nerves = floor_level - 5.0
	var log: SleepLog = _watch_sleep(period * 4.0 + 2.0)
	check(_sim.nerves.heavy, "below the Heavy floor he is Heavy")
	check_eq(log.shut_starts.size(), 4, "in four periods the eyes shut four times")
	for index: int in log.shut_starts.size():
		check_near(log.shut_starts[index], period * float(index + 1), DT * 1.5, "blink %d starts at %s s" % [index + 1, str(period * float(index + 1))])
		check_near(log.shut_lengths[index], length, DT * 1.5, "blink %d lasts blink_length" % (index + 1))
	check_eq(log.yawns.size(), 4, "each blink has one yawn")
	for index: int in log.yawns.size():
		check_near(log.shut_starts[index] - log.yawns[index], tell, DT * 1.5, "yawn %d comes blink_tell before its blink" % (index + 1))
	check_eq(log.long_yawns.size(), 0, "there is no long yawn: this is not a Nod")
	check_eq(log.blink_events, 4, "each blink is announced as an event")

	# Lids: dark bars close to lids_max over lids_close_time, and stay.
	_sim = DriveSim.new(fresh_data())
	_sim.act = 2
	_pinned_nerves = floor_level - 5.0
	var close_time: float = tuning.f("lids_close_time")
	_run(close_time * 0.5)
	check_near(_sim.nerves.lids, tuning.f("lids_max") * 0.5, 0.005, "half-way through lids_close_time the bars are half closed")
	_run(close_time)
	check_near(_sim.nerves.lids, tuning.f("lids_max"), 0.000001, "they stop at lids_max of the screen each")
	check_near(_snapshot_float("lids"), tuning.f("lids_max"), 0.000001, "the snapshot carries the lids for the post effect")

	# At or above the floor: nothing.
	_pinned_nerves = floor_level
	log = _watch_sleep(period * 2.0 + 1.0)
	check_eq(log.shut_starts.size(), 0, "at the floor itself there is no blink")
	check_near(_sim.nerves.lids, 0.0, 0.000001, "and the lids have opened again")
	check_eq(log.yawns.size(), 0, "and no yawn")

	# Act 1: the floor is 0, so he is never Heavy.
	_sim = DriveSim.new(fresh_data())
	_sim.act = 1
	_pinned_nerves = 0.0
	log = _watch_sleep(period * 2.0 + 1.0)
	check_eq(log.shut_starts.size(), 0, "in Act 1 the floor is 0: no blink even at Nerves 0")
	check_near(_sim.nerves.lids, 0.0, 0.000001, "and no lids")

	# Awake: nothing either (each source is checked by T-NERVES-03).
	_sim = DriveSim.new(fresh_data())
	_sim.act = 2
	_pinned_nerves = floor_level - 5.0
	_sim.effects.add(&"awake", period * 3.0)
	log = _watch_sleep(period * 2.0 + 1.0)
	check_eq(log.shut_starts.size(), 0, "Awake, he does not blink")

	# The rhythm starts over when he becomes Heavy again.
	_sim = DriveSim.new(fresh_data())
	_sim.act = 2
	_pinned_nerves = floor_level - 5.0
	_run(period * 0.8)
	_pinned_nerves = floor_level + 5.0
	_run(1.0)
	_pinned_nerves = floor_level - 5.0
	log = _watch_sleep(period + 1.0)
	if check_eq(log.shut_starts.size(), 1, "after a spell above the floor the rhythm starts over"):
		check_near(log.shut_starts[0], period, DT * 1.5, "the first blink is a full period after he became Heavy again")


## T-NERVES-03: every Awake source suppresses Lids, Blink and Nod for its duration.
func test_nerves_03() -> void:
	var tea: Dictionary = data.record("items", "tea_glass")
	var cigarettes: Dictionary = data.record("items", "cigarettes")
	var sources: Array[Dictionary] = [
		{"name": "hot tea", "ritual": "tea_sip", "seconds": _give_duration(tea, "awake")},
		{"name": "a lit cigarette", "ritual": "cig_light", "seconds": _give_duration(cigarettes, "lit")},
		{"name": "a slap", "ritual": "slap", "seconds": _op_duration("slap", "awake")},
		{"name": "opening the window", "ritual": "window_crank", "seconds": tuning.f("window_awake")},
		{"name": "the news station", "ritual": "radio_tune", "seconds": tuning.f("radio_drift_time"), "steps": 2},
	]
	check_near(_give_duration(tea, "awake"), 40.0, 0.000001, "GDD 6.1: hot tea is 40 s")
	check_near(_op_duration("slap", "awake"), 20.0, 0.000001, "GDD 6.1: a slap is 20 s")
	check_near(tuning.f("window_awake"), 30.0, 0.000001, "GDD 6.1: opening the window is 30 s")

	for source: Dictionary in sources:
		var name: String = source["name"]
		var seconds: float = source["seconds"]
		_sim = DriveSim.new(fresh_data())
		_sim.act = 3
		# Deep under the floor: without Awake he would Nod.
		_pinned_nerves = _sim.heavy_floor() - tuning.f("nod_depth") - 2.0
		_run(tuning.f("lids_close_time") + 0.5)
		check(_sim.nerves.deep and _sim.nerves.lids > 0.0, "%s: before it, he is nodding off" % name)

		var ritual: Dictionary = data.record("rituals", str(source["ritual"]))
		if source.has("steps"):
			for _step: int in int(GameData.as_float(source["steps"])):
				_sim.items.drag_step(ritual, 1)
			check_eq(_sim.items.radio, &"news", "the dial is on the news")
		else:
			_sim.items.complete(ritual, 0)

		var log: SleepLog = _watch_sleep(seconds - 0.2)
		check(log.always_awake, "%s: he is Awake for its duration (%s s)" % [name, str(seconds)])
		check_eq(log.shut_starts.size(), 0, "%s: no Blink and no Nod while it lasts" % name)
		check_eq(log.yawns.size() + log.long_yawns.size(), 0, "%s: no yawn while it lasts" % name)
		check_near(_sim.nerves.lids, 0.0, 0.000001, "%s: the lids are open" % name)

		_run(0.5)
		check(not _sim.nerves.awake, "%s: it ends after its duration" % name)
		_run(tuning.f("lids_close_time"))
		check(_sim.nerves.lids > 0.0, "%s: afterwards the lids close again" % name)

	# A cold tea does not wake him.
	_sim = DriveSim.new(fresh_data())
	_sim.act = 3
	_pinned_nerves = _sim.heavy_floor() - tuning.f("nod_depth") - 2.0
	_run(GameData.as_float(GameData.as_dict(tea.get("params")).get("hot_for_s")) + 1.0)
	_sim.items.complete(data.record("rituals", "tea_sip"), 0)
	_run(0.1)
	check(not _sim.nerves.awake, "a cold sip gives no Awake")

	# The longest source wins; they do not add up.
	_sim = DriveSim.new(fresh_data())
	_sim.effects.add(&"awake", 20.0)
	_sim.effects.add(&"awake", 5.0)
	check_near(_sim.effects.time_left(&"awake"), 20.0, 0.000001, "a shorter Awake does not shorten a longer one")
	_sim.effects.add(&"awake", 30.0)
	check_near(_sim.effects.time_left(&"awake"), 30.0, 0.000001, "a longer one extends it")


## T-NERVES-04: the Nod, the ambient rates and the Heavy floor by act.
func test_nerves_04() -> void:
	var period: float = tuning.f("nod_period")
	var length: float = tuning.f("nod_length")
	var tell: float = tuning.f("nod_tell")
	var depth: float = tuning.f("nod_depth")
	var floors: PackedFloat64Array = tuning.floats("heavy_floor")

	# --- The Heavy floor follows the act.
	for act_number: int in [1, 2, 3]:
		_sim.act = act_number
		check_near(_sim.heavy_floor(), floors[act_number - 1], 0.000001, "the Heavy floor in Act %d" % act_number)
	_sim.heavy_floor_bonus = 10.0
	check_near(_sim.heavy_floor(), floors[2] + 10.0, 0.000001, "a bonus raises the floor")
	_sim.heavy_floor_bonus = 0.0

	# --- The Nod: nod_depth or more below the floor.
	_sim = DriveSim.new(fresh_data())
	_sim.act = 3
	_pinned_nerves = _sim.heavy_floor() - depth
	var log: SleepLog = _watch_sleep(period * 3.0 + 3.0)
	check(_sim.nerves.deep, "nod_depth below the floor he is deep enough to Nod")
	check_eq(log.shut_starts.size(), 3, "in three periods the eyes shut three times")
	for index: int in log.shut_starts.size():
		check_near(log.shut_starts[index], period * float(index + 1), DT * 1.5, "nod %d starts at %s s" % [index + 1, str(period * float(index + 1))])
		check_near(log.shut_lengths[index], length, DT * 1.5, "nod %d lasts nod_length" % (index + 1))
	check_eq(log.long_yawns.size(), 3, "each Nod has one long yawn")
	for index: int in log.long_yawns.size():
		check_near(log.shut_starts[index] - log.long_yawns[index], tell, DT * 1.5, "long yawn %d comes nod_tell before its Nod" % (index + 1))
	check_eq(log.nod_events, 3, "each Nod is announced as an event")

	# Just above nod depth: blinks, not nods.
	_sim = DriveSim.new(fresh_data())
	_sim.act = 3
	_pinned_nerves = _sim.heavy_floor() - depth + 1.0
	log = _watch_sleep(period + 2.0)
	check(not _sim.nerves.deep, "less than nod_depth below the floor is not a Nod")
	check_eq(log.long_yawns.size(), 0, "no long yawn there")
	check(log.yawns.size() > 0, "he blinks instead")

	# The rumble strip ends a Nod and adds nod_wake_nerves.
	_sim = DriveSim.new(fresh_data())
	_sim.act = 3
	_pinned_nerves = _sim.heavy_floor() - depth
	_run(period + length * 0.3)
	check(_sim.nerves.eyes_shut, "a third of the way into the Nod his eyes are shut")
	_pinned_nerves = -1.0
	_sim.nerves.value = _sim.heavy_floor() - depth
	var before: float = _sim.nerves.value
	_sim.car.x = _sim.car.road_right() - _sim.car.half_width() + tuning.f("rumble_strip_width") * 0.5
	_sim.step(_input)
	check(_sim.car.on_rumble, "the car is on the rumble strip")
	check(not _sim.nerves.eyes_shut, "the rumble strip ends the Nod")
	check_near(_sim.nerves.value - before, tuning.f("nod_wake_nerves"), 0.02, "and adds nod_wake_nerves")
	_sim.step(_input)
	check_near(_sim.nerves.value - before, tuning.f("nod_wake_nerves"), 0.03, "once, not every tick")

	# Any hit ends a Nod too.
	_sim = DriveSim.new(fresh_data())
	_sim.act = 3
	_sim.gate.reset(3)
	_sim.car.reset(1, 3)
	# A little deeper than the edge, so the car that appears beside him (and
	# frays him a little, as any traffic does) does not lift him out of the Nod.
	_pinned_nerves = _sim.heavy_floor() - depth - 2.0
	_run(period + length * 0.3)
	check(_sim.nerves.eyes_shut, "his eyes are shut in a Nod")
	# A slower car appears just ahead in his lane: he runs into it eyes shut.
	var ahead: TrafficSim.Vehicle = _sim.traffic.spawn(&"car", 1, 0.0, _sim.car.speed - 20.0)
	ahead.s = _sim.car.s + _sim.car.length() * 0.5 + ahead.half_length + 0.3
	var hit: bool = false
	var shut_before_hit: bool = false
	for _tick: int in int(length * 0.5 / DT):
		var eyes_were_shut: bool = _sim.nerves.eyes_shut
		_step()
		if _sim.collision.hit != Collision.Hit.NONE:
			hit = true
			shut_before_hit = eyes_were_shut
			break
	if check(hit and shut_before_hit, "the hit comes while his eyes are shut"):
		check(not _sim.nerves.eyes_shut, "the hit ends the Nod")
		check_near(_sim.nerves.value - _pinned_nerves, tuning.f("nod_wake_nerves") + tuning.fi("hit_nerves", 0), 0.05, "and adds nod_wake_nerves on top of the hit")

	# --- Ambient rates.
	_pinned_nerves = -1.0
	var radius: float = tuning.f("traffic_radius")
	var each: float = tuning.f("traffic_rate")
	check_near(_ambient_rate([radius * 0.5]), each, 0.002, "one vehicle within traffic_radius adds traffic_rate per second")
	check_near(_ambient_rate([radius * 0.5, radius * 0.6, radius * 0.7]), each * 3.0, 0.002, "three add three times that")
	var over_cap: int = int(tuning.f("traffic_rate_cap") / each) + 2
	var many: Array[float] = []
	for index: int in over_cap:
		many.append(radius * 0.3 + float(index))
	check_near(_ambient_rate(many), tuning.f("traffic_rate_cap"), 0.002, "however many, the sum is capped at traffic_rate_cap")
	var between: float = (radius + tuning.f("empty_road_radius")) * 0.5
	check_near(_ambient_rate([between]), 0.0, 0.002, "a vehicle beyond traffic_radius but within empty_road_radius changes nothing")
	check_near(_ambient_rate([]), tuning.f("empty_road_rate"), 0.002, "an empty road changes Nerves by empty_road_rate")
	check_near(_ambient_rate([tuning.f("empty_road_radius") + 20.0]), tuning.f("empty_road_rate"), 0.002, "a vehicle beyond empty_road_radius still leaves the road empty")
	_sim = DriveSim.new(fresh_data())
	_sim.in_encounter = true
	check_near(_measured_rate(), 0.0, 0.002, "during an encounter an empty road does not calm him")

	# The rough shoulder.
	_sim = DriveSim.new(fresh_data())
	_sim.in_encounter = true
	_sim.car.x = _sim.car.road_right() + tuning.f("rumble_strip_width") + _sim.car.half_width() + 0.5
	_run(0.1)
	check(_sim.car.on_shoulder, "the car is on the rough shoulder")
	var start: float = _sim.nerves.value
	var shoulder_x: float = _sim.car.x
	for _tick: int in int(1.0 / DT):
		_sim.car.x = shoulder_x
		_sim.step(_input)
	check_near(_sim.nerves.value - start, tuning.f("shoulder_nerves_rate"), 0.01, "the rough shoulder adds shoulder_nerves_rate per second")


# --- Helpers ------------------------------------------------------------------

class SleepLog:
	extends RefCounted
	var shut_starts: Array[float] = []
	var shut_lengths: Array[float] = []
	var yawns: Array[float] = []
	var long_yawns: Array[float] = []
	var blink_events: int = 0
	var nod_events: int = 0
	var always_awake: bool = true


## One tick. While Nerves are pinned, everything that would move them or
## wake him by itself is kept out: the road's ambient rate is silenced (as in
## an encounter) and the car is held in its lane, off the rumble strip.
func _step() -> void:
	if _pinned_nerves >= 0.0:
		_sim.nerves.value = _pinned_nerves
		_sim.in_encounter = true
		_sim.car.x = _sim.car.lane_center(1)
	_sim.step(_input)


func _run(seconds: float) -> void:
	for _tick: int in roundi(seconds / DT):
		_step()


## Runs for `seconds` and notes when the eyes shut, for how long, and the yawns.
## Times are seconds from the start of the watch.
func _watch_sleep(seconds: float) -> SleepLog:
	var log: SleepLog = SleepLog.new()
	_sim.drain_events()
	var was_shut: bool = false
	var shut_at: float = 0.0
	for tick: int in roundi(seconds / DT):
		_step()
		var now: float = float(tick + 1) * DT
		if not _sim.nerves.awake:
			log.always_awake = false
		if _sim.nerves.eyes_shut and not was_shut:
			shut_at = now
			log.shut_starts.append(now)
		elif was_shut and not _sim.nerves.eyes_shut:
			log.shut_lengths.append(now - shut_at)
		was_shut = _sim.nerves.eyes_shut
		for event: Dictionary in _sim.drain_events():
			var type: String = str(event.get("type"))
			if type == "sfx_requested" and event.get("id") == "yawn":
				log.yawns.append(now)
			elif type == "sfx_requested" and event.get("id") == "yawn_long":
				log.long_yawns.append(now)
			elif type == "blink":
				log.blink_events += 1
			elif type == "nod":
				log.nod_events += 1
	return log


## Flies the hand to the rim and holds the wheel.
func _grip_wheel() -> void:
	_input.clear()
	_input.pointer_is_absolute = true
	_input.pointer = _sim.space.point_to_pointer(_sim.space.grip_reference)
	_input.lmb = true
	for _tick: int in 120:
		_sim.step(_input)
	_input.pointer_is_absolute = false


## (lowest, highest) wheel angle over `seconds`.
func _wheel_swing(seconds: float) -> Vector2:
	var low: float = INF
	var high: float = -INF
	for _tick: int in roundi(seconds / DT):
		_step()
		low = minf(low, _sim.wheel.angle)
		high = maxf(high, _sim.wheel.angle)
	return Vector2(low, high)


func _zero_crossings_per_second(seconds: float) -> float:
	var crossings: int = 0
	var centre: float = _sim.wheel.command
	var previous: float = _sim.wheel.angle - centre
	for _tick: int in roundi(seconds / DT):
		_step()
		var now: float = _sim.wheel.angle - centre
		if (now > 0.0) != (previous > 0.0):
			crossings += 1
		previous = now
	return float(crossings) / seconds


## Speed of the free hand on a straight stretch right of the hub.
func _hand_speed() -> float:
	_sim.hand.place_at(_sim.space.grip_reference)
	_input.clear()
	_input.pointer_is_absolute = true
	_input.pointer = _sim.hand.anchor_pointer(_sim.hand.anchor_index(&"glovebox"))
	_step()
	var start: Vector3 = _sim.hand.pos
	for _tick: int in 10:
		_step()
	var speed: float = _sim.hand.pos.distance_to(start) / (DT * 10.0)
	_input.clear()
	return speed


func _snapshot_float(key: String) -> float:
	return GameData.as_float(_sim.snapshot().get(key), -1.0)


## Thresholds announced as crossed upward (`on`) or downward since the last drain.
func _crossings(on: bool) -> Array[String]:
	var out: Array[String] = []
	for event: Dictionary in _sim.drain_events():
		if event.get("type") == "nerves_threshold_crossed" and event.get("on") == on:
			out.append(str(event.get("threshold")))
	return out


func _completed(ritual: String) -> bool:
	var found: bool = false
	for event: Dictionary in _sim.drain_events():
		if event.get("type") == "ritual_completed" and event.get("ritual") == ritual:
			found = true
	return found


## Seconds an item's "gives" keep a status on.
func _give_duration(item: Dictionary, effect: String) -> float:
	for give: Variant in GameData.as_array(item.get("gives")):
		var entry: Dictionary = GameData.as_dict(give)
		if entry.get("effect") == effect:
			return GameData.as_float(entry.get("duration"))
	return 0.0


## Seconds a ritual's "add_effect:<effect>:<seconds>" op gives.
func _op_duration(ritual_id: String, effect: String) -> float:
	for op: Variant in GameData.as_array(data.record("rituals", ritual_id).get("on_complete")):
		var parts: PackedStringArray = GameData.as_string(op).split(":")
		if parts.size() == 3 and parts[0] == "add_effect" and parts[1] == effect:
			return parts[2].to_float()
	return 0.0


## Nerves per second with vehicles held at these distances ahead.
func _ambient_rate(distances: Array) -> float:
	_sim = DriveSim.new(fresh_data())
	var vehicles: Array[TrafficSim.Vehicle] = []
	for distance: Variant in distances:
		# Spread across lanes so they do not follow one another.
		var lane: int = vehicles.size() % 3
		var ahead: float = GameData.as_float(distance)
		var side: float = _sim.traffic.lane_center(lane) - _sim.car.x
		var along: float = sqrt(maxf(ahead * ahead - side * side, 0.0))
		vehicles.append(_sim.traffic.spawn(&"tuk_tuk", lane, _sim.car.s + along, _sim.car.speed))
	return _measured_rate(vehicles)


## Nerves per second over one second, with the given vehicles kept in place
## relative to the car and the car kept in its lane.
func _measured_rate(vehicles: Array[TrafficSim.Vehicle] = []) -> float:
	var offsets: Array[float] = []
	for vehicle: TrafficSim.Vehicle in vehicles:
		offsets.append(vehicle.s - _sim.car.s)
	var lane_x: float = _sim.car.x
	var start: float = _sim.nerves.value
	for _tick: int in int(1.0 / DT):
		_sim.car.x = lane_x
		for index: int in vehicles.size():
			vehicles[index].s = _sim.car.s + offsets[index]
			vehicles[index].speed = _sim.car.speed
			vehicles[index].cruise = _sim.car.speed
		_sim.step(_input)
	return _sim.nerves.value - start
