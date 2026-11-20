extends CabinSuite
## The set pieces that end the acts (GDD 10.2 to 10.5).

const KMH_TO_MS: float = 1.0 / 3.6
const CHECKPOINT: String = "checkpoint"
const STORM: String = "storm"
const DAWN: String = "dawn"
const POCKET: String = "pocket"
const KEY: String = "key"


func _storm() -> Dictionary:
	return GameData.as_dict(data.record("bosses", STORM).get("storm"))


# --- T-BOSS-01: the Checkpoint (GDD 10.2) -------------------------------------

func _checkpoint() -> Dictionary:
	return GameData.as_dict(data.record("bosses", CHECKPOINT).get("checkpoint"))


func _checkpoint_number(key: String) -> float:
	return GameData.as_float(_checkpoint().get(key))


func test_boss_01() -> void:
	_check_checkpoint_road()
	_check_checkpoint_queue()
	_check_checkpoint_barriers()
	_check_checkpoint_stow()
	_check_checkpoint_stowing_by_hand()
	_check_checkpoint_papers()
	_check_checkpoint_delay()
	_check_checkpoint_verdicts()
	_check_checkpoint_bribe()
	_check_checkpoint_forged_papers()
	_check_checkpoint_modifiers()
	_check_checkpoint_in_a_telling()
	_check_checkpoint_fine_print()
	_check_checkpoint_rows()


## The road, its numbers, and who is watching.
func _check_checkpoint_road() -> void:
	var record: Dictionary = data.record("bosses", CHECKPOINT)
	var corridor: Dictionary = GameData.as_dict(_checkpoint().get("corridor"))
	check_eq(GameData.as_int(record.get("act")), 1, "GDD 10.2: the Checkpoint ends Act 1")
	check_near(GameData.as_float(record.get("par_s")), 90.0, 0.000001, "about 90 s")
	check_near(GameData.as_float(corridor.get("gap_m")), 2.34, 0.000001, "its barriers are 2.34 m apart")
	check_near(GameData.as_float(corridor.get("gap_m")), tuning.f("car_width") * 1.3, 0.000001, "(1.3 car widths)")
	check_near(_checkpoint_number("barrier_suspicion"), 25.0, 0.000001, "touching a barrier is +25 Suspicion")
	check_near(_checkpoint_number("stow_s"), 10.0, 0.000001, "the soldier takes 10 s to reach the window")
	check_near(_checkpoint_number("contraband_suspicion"), 40.0, 0.000001, "each contraband item left out is +40")
	check_near(_checkpoint_number("courage_suspicion"), 15.0, 0.000001, "each Courage stack +15")
	check_near(_checkpoint_number("delay_every_s"), 5.0, 0.000001, "each 5 s of delay")
	check_near(_checkpoint_number("delay_suspicion"), 10.0, 0.000001, "is +10")
	check_near(_checkpoint_number("pass_under"), 50.0, 0.000001, "under 50 he passes")
	check_near(_checkpoint_number("turned_back_at"), 100.0, 0.000001, "at 100 he is turned back")
	check_near(_checkpoint_number("search_minutes"), 15.0, 0.000001, "a search is 15 game minutes")
	check_near(_checkpoint_number("turned_back_minutes"), 30.0, 0.000001, "being turned back 30")
	check_near(tuning.f("checkpoint_bribe"), 60.0, 0.000001, "GDD 15: the Checkpoint's bribe is 60 cash")
	var documents: Array = GameData.as_array(_checkpoint().get("documents"))
	check(documents.size() == 3 and documents.has("licence") and documents.has("id") and documents.has("registration"), "three documents: licence, ID, registration")

	var plan: Dictionary = _begin_checkpoint()
	check_eq(_sim.boss.kind, CHECKPOINT, "he is at the Checkpoint")
	check_near(GameData.as_float(plan.get("length")), GameData.as_float(record.get("length_m")), 0.000001, "(its road is as long as its record says)")
	check_near(_sim.heavy_floor(), 0.0, 0.000001, "GDD 6.1: at the Checkpoint he is never Heavy")
	_tick()
	var shot: Dictionary = _sim.snapshot()
	check_eq(GameData.as_int(shot["checkpoint_phase"]), BossSim.QUEUE, "it begins with the queue")
	check(GameData.as_bool(shot["suspicion_watching"]), "GDD 6.5: Suspicion exists at a checkpoint")
	check_eq(GameData.as_string(shot["suspicion_by"]), "checkpoint", "(the snapshot says who watches)")
	check_near(GameData.as_float(shot["suspicion"]), 0.0, 0.000001, "from 0")
	check_near(GameData.as_float(shot["bar_at"]), GameData.as_float(corridor.get("at_m")) + GameData.as_float(corridor.get("length_m")), 0.000001, "the bar stands where the barriers end")
	check(not GameData.as_bool(shot["bar_up"]), "and is down")
	var sign: Dictionary = _sign("checkpoint")
	check(not sign.is_empty(), "the Checkpoint is signed ahead")
	check_near(GameData.as_float(sign.get("limit")), 0.0, 0.000001, "(a checkpoint to stop at: its sign names no speed)")
	# Nothing wears off here, and the Patrol's rows do not count.
	_sim.suspicion.add(30.0)
	_run(4.0)
	check_near(_sim.suspicion.value, 30.0, 0.000001, "Suspicion does not wear off at the Checkpoint")
	_sim.gate.reset(4)
	_run(2.0)
	check_near(_sim.suspicion.value, 30.0, 0.000001, "the Patrol's rows are not the Checkpoint's: fourth gear adds nothing")
	_sim.gate.reset(1)
	_tap_at("horn")
	check_near(_sim.suspicion.value, 30.0, 0.000001, "nor does the horn")
	# At the top nobody pulls him over: the verdict comes at the window.
	_sim.suspicion.add(100.0)
	_run(1.0)
	check_near(_sim.suspicion.value, _sim.suspicion.maximum(), 0.000001, "(Suspicion at the top)")
	check(not _sim.pulled_over, "at 100 in the queue he is not pulled over: the verdict comes at the window")
	check_eq(_count_events("pulled_over"), 0, "(nothing is announced yet)")


## Stop and go, in every lane's corridor, at less than first gear's speed.
func _check_checkpoint_queue() -> void:
	var queue: Dictionary = GameData.as_dict(_checkpoint().get("queue"))
	var corridor: Dictionary = GameData.as_dict(_checkpoint().get("corridor"))
	var cars: int = GameData.as_int(queue.get("cars"))
	var gap: float = GameData.as_float(queue.get("gap_m"))
	var serve: float = GameData.as_float(queue.get("serve_s"))
	var plan: Dictionary = _begin_checkpoint("", 3)
	var lines: Array = GameData.as_array(plan.get("queue"))
	check_eq(lines.size(), 3, "every lane has its queue")
	var bar: float = _sim.boss.bar_at
	for lane: int in lines.size():
		var line: Array = GameData.as_array(lines[lane])
		check_eq(line.size(), cars, "lane %d: %d vehicles wait" % [lane, cars])
		check_eq(_sim.boss.queue_length(lane), cars, "(they are on the road)")
		# Nose to tail from the bar, in the lane's corridor.
		var standing: Array[TrafficSim.Vehicle] = []
		for vehicle: TrafficSim.Vehicle in _sim.traffic.vehicles:
			if vehicle.lane == lane and vehicle.role == BossSim.QUEUE_ROLE:
				standing.append(vehicle)
		standing.sort_custom(func(a: TrafficSim.Vehicle, b: TrafficSim.Vehicle) -> bool: return a.s > b.s)
		check_eq(standing.size(), cars, "(lane %d: all of them)" % lane)
		var nose: float = bar
		for index: int in standing.size():
			var vehicle: TrafficSim.Vehicle = standing[index]
			check_eq(String(vehicle.type_id), GameData.as_string(line[index]), "lane %d: vehicle %d is the plan's" % [lane, index + 1])
			check(GameData.as_array(queue.get("vehicles")).has(String(vehicle.type_id)), "(of the queue's kinds)")
			check_near(vehicle.s + vehicle.half_length, nose, 0.000001, "lane %d: vehicle %d stands %s" % [lane, index + 1, "at the bar" if index == 0 else "%.1f m behind the one ahead" % gap])
			check_near(vehicle.x, _sim.car.lane_center(lane), 0.000001, "(in the middle of its corridor)")
			check(vehicle.s - vehicle.half_length > GameData.as_float(corridor.get("at_m")), "(between the barriers)")
			check_near(vehicle.speed, 0.0, 0.000001, "(standing)")
			nose = vehicle.s - vehicle.half_length - gap

	# Watching the last vehicle of the middle lane: it goes and stops, once for
	# every vehicle that is waved on ahead of it, and never fast.
	var last: TrafficSim.Vehicle = null
	for vehicle: TrafficSim.Vehicle in _sim.traffic.vehicles:
		if vehicle.lane == 1 and vehicle.role == BossSim.QUEUE_ROLE and (last == null or vehicle.s < last.s):
			last = vehicle
	_stand_short_of_the_queue()
	var goes: int = 0
	var moving: bool = false
	var fastest: float = 0.0
	var left_at: Array[int] = []
	var waiting: int = _sim.boss.queue_length(1)
	var guard: int = _ticks_in(120.0)
	while _sim.boss.queue_length(1) > 0 and guard > 0:
		guard -= 1
		_tick()
		if last.role == BossSim.QUEUE_ROLE:
			fastest = maxf(fastest, last.speed)
			if last.speed > 2.0 and not moving:
				moving = true
				goes += 1
			elif last.speed < 0.5:
				moving = false
		if _sim.boss.queue_length(1) != waiting:
			waiting = _sim.boss.queue_length(1)
			left_at.append(_sim.tick)
	check_eq(left_at.size(), cars, "one by one the vehicles are waved on")
	check_eq(goes, cars - 1, "the last of them goes and stops %d times: stop and go" % (cars - 1))
	check(fastest > 5.0 and fastest <= GameData.as_float(queue.get("creep_kmh")) + 0.000001, "at a crawl: never more than %d km/h (%.1f)" % [roundi(GameData.as_float(queue.get("creep_kmh"))), fastest])
	check(GameData.as_float(queue.get("creep_kmh")) < tuning.fi("gear_speeds", 0), "which is less than first gear gives: he must use the brake")
	for index: int in range(1, left_at.size()):
		var apart: float = float(left_at[index] - left_at[index - 1]) * DT
		check(apart >= serve and apart <= serve + 6.0, "vehicle %d is waved on %.1f s after the one before: served %d s at the bar" % [index + 1, apart, roundi(serve)])
	check(_sim.boss.phase == BossSim.QUEUE, "(standing far back he is not yet first in line)")
	# While any of them waits ahead of him he is not first in line, however near he stands.
	_begin_checkpoint("", 3)
	var tail: TrafficSim.Vehicle = null
	for vehicle: TrafficSim.Vehicle in _sim.traffic.vehicles:
		if vehicle.lane == 1 and (tail == null or vehicle.s < tail.s):
			tail = vehicle
	_cruise(1, 1)
	_sim.car.s = tail.s - tail.half_length - _sim.car.length() * 0.5 - 1.0
	_sim.car.speed = 0.0
	_input.rmb = true
	_ticks(_ticks_in(1.0))
	check_eq(_sim.boss.phase, BossSim.QUEUE, "behind the queue he queues")
	check_eq(_count_events("hit"), 0, "(touching nobody)")

	# Through the queue behind them, braking: no touch, and then he is first.
	_begin_checkpoint("", 3)
	_events = []
	_follow_the_queue(1)
	check_eq(_sim.boss.phase, BossSim.STOW, "when the last one ahead is waved on and he stands at the bar, the soldier comes")
	check_eq(_count_events("hit"), 0, "driving the queue with the brake, he touches nothing")
	check_eq(_sim.faults.lamps, 0, "(no lamp)")
	check_near(_sim.suspicion.value, 0.0, 0.000001, "(and no Suspicion)")
	check_eq(_sim.boss.queue_length(1), 0, "(his lane's queue is gone)")
	check(_sim.boss.queue_length(0) <= 1 and _sim.boss.queue_length(2) <= 1, "(the other lanes' queues went as fast)")
	check(_sim.boss.bar_at - (_sim.car.s + _sim.car.length() * 0.5) <= _checkpoint_number("stop_zone_m"), "(he stands within stop_zone_m of the bar)")

	# The horn moves nobody over between barriers.
	_begin_checkpoint("", 3)
	_cruise(1, 1)
	_sim.car.s = tail.s - 30.0
	_sim.car.speed = 0.0
	_input.rmb = true
	_tick()
	_tap_at("horn")
	_input.rmb = true
	_ticks(_ticks_in(2.0))
	var moved_over: int = 0
	for vehicle: TrafficSim.Vehicle in _sim.traffic.vehicles:
		if vehicle.signalling != 0 or vehicle.changing or absf(vehicle.x - _sim.car.lane_center(vehicle.lane)) > 0.001:
			moved_over += 1
	check_eq(moved_over, 0, "a honk moves nobody out of the queue")


## Touching a barrier is a scrape and +25 Suspicion; the bar is one too.
func _check_checkpoint_barriers() -> void:
	var corridor: Dictionary = GameData.as_dict(_checkpoint().get("corridor"))
	var at: float = GameData.as_float(corridor.get("at_m"))
	var gap: float = GameData.as_float(corridor.get("gap_m"))
	var half_width: float = tuning.f("car_width") * 0.5
	var each: float = _checkpoint_number("barrier_suspicion")
	_begin_checkpoint("", 1, false)
	_cruise(1, 1)
	_sim.car.s = at + 10.0
	_tick()
	var middle: float = _sim.car.lane_center(1)
	check_near(_sim.car.wall_left, middle - gap * 0.5, 0.000001, "in the queue a barrier stands 1.17 m to his left")
	check_near(_sim.car.wall_right, middle + gap * 0.5, 0.000001, "and one 1.17 m to his right")
	_keep_lane = false
	_events = []
	_sim.car.x = middle + gap * 0.5 - half_width + 0.05
	_tick()
	check_eq(GameData.as_int(_event("hit").get("kind")), Collision.Hit.SCRAPE, "touching a barrier is a scrape")
	check_eq(_sim.faults.lamps, int(tuning.fi("hit_lamps", 0)), "(a lamp)")
	check_near(_sim.suspicion.value, each, 0.000001, "and +25 Suspicion")
	check_eq(GameData.as_string(_event("suspicion_changed").get("type")), "suspicion_changed", "(announced)")
	check(absf(_sim.car.x - middle) <= gap * 0.5 - half_width + 0.000001, "(he is put back between the barriers)")
	# While the scrape's immunity lasts another touch is no scrape and no Suspicion.
	_sim.car.x = middle - gap * 0.5 + half_width - 0.05
	_tick()
	check_eq(_count_events("hit"), 1, "a touch while he cannot be hit is not a scrape")
	check_near(_sim.suspicion.value, each, 0.000001, "and adds no Suspicion")
	_keep_lane = true
	_ticks(_ticks_in(tuning.f("hit_immunity") + 0.1))
	_keep_lane = false
	_sim.car.x = middle - gap * 0.5 + half_width - 0.05
	_tick()
	check_eq(_count_events("hit"), 2, "after it, the other barrier scrapes too")
	check_near(_sim.suspicion.value, each * 2.0, 0.000001, "+25 again: 50")

	# The lowered bar holds him; met at speed it is a barrier like the others.
	_begin_checkpoint("", 1, false)
	_cruise(1, 1)
	var bar: float = _sim.boss.bar_at
	_sim.car.s = bar - 12.0
	_events = []
	_ticks(_ticks_in(3.0))
	check_near(_sim.car.s + _sim.car.length() * 0.5, bar, 0.000001, "the bar is down: it holds him")
	check_near(_sim.car.speed, 0.0, 0.2, "(stopped against it)")
	check_eq(_count_events("hit"), 1, "run into in first gear it is a touch of a barrier: a scrape")
	check_eq(GameData.as_int(_event("hit").get("kind")), Collision.Hit.SCRAPE, "(a scrape)")
	check_near(_sim.suspicion.value, each, 0.000001, "and +25 Suspicion")
	_ticks(_ticks_in(3.0))
	check_near(_sim.car.s + _sim.car.length() * 0.5, bar, 0.000001, "(it keeps holding him)")
	check_eq(_count_events("hit"), 1, "(held against it, he is not scraped again)")
	# Rolled up to at a crawl, it only stops him.
	_begin_checkpoint("", 1, false)
	_cruise(1, 1)
	_sim.car.s = bar - _sim.car.length() * 0.5 - 0.5
	_events = []
	for _index: int in _ticks_in(2.0):
		_sim.car.speed = minf(_sim.car.speed, _checkpoint_number("bump_kmh") - 1.0)
		_tick()
	check_near(_sim.car.s + _sim.car.length() * 0.5, bar, 0.01, "rolled up to at a crawl, the bar only stops him")
	check_eq(_count_events("hit"), 0, "(no scrape)")
	check_near(_sim.suspicion.value, 0.0, 0.000001, "(no Suspicion)")

	# Running into the back of the queue: he is put behind it, between the barriers.
	_begin_checkpoint("", 3)
	var tail: TrafficSim.Vehicle = null
	for vehicle: TrafficSim.Vehicle in _sim.traffic.vehicles:
		if vehicle.lane == 1 and (tail == null or vehicle.s < tail.s):
			tail = vehicle
	_cruise(1, 1)
	_sim.car.s = tail.s - tail.half_length - _sim.car.length() * 0.5 - 6.0
	_events = []
	var guard: int = _ticks_in(5.0)
	while _event("hit").is_empty() and guard > 0:
		guard -= 1
		_tick()
	check_eq(GameData.as_int(_event("hit").get("vehicle")), tail.id, "into the back of the queue: he hits the last vehicle")
	check(_sim.car.s + _sim.car.length() * 0.5 <= tail.s - tail.half_length + 0.000001, "and is left behind it")
	check_near(_sim.car.x, _sim.car.lane_center(1), 0.3, "between the barriers, not pushed through one")
	check_near(_sim.suspicion.value, 0.0, 0.000001, "(a vehicle is no barrier: no Suspicion)")


## Stow: 10 s; each contraband item left out +40, each Courage stack +15.
func _check_checkpoint_stow() -> void:
	var stow_s: float = _checkpoint_number("stow_s")
	var per_item: float = _checkpoint_number("contraband_suspicion")
	var per_stack: float = _checkpoint_number("courage_suspicion")
	# Standing far from the bar, or rolling at it, the soldier does not come.
	_begin_checkpoint("", 1, false)
	_cruise(1, 1)
	_sim.car.s = _sim.boss.bar_at - _checkpoint_number("stop_zone_m") - _sim.car.length() * 0.5 - 3.0
	_sim.car.speed = 0.0
	_input.rmb = true
	_ticks(_ticks_in(2.0))
	check_eq(_sim.boss.phase, BossSim.QUEUE, "standing short of stop_zone_m from the bar, he is waved forward, not checked")
	_input.rmb = false
	for _index: int in 40:
		_sim.car.speed = 6.0
		_tick()
		if _sim.car.s + _sim.car.length() * 0.5 > _sim.boss.bar_at - 1.0:
			break
		check_eq(_sim.boss.phase, BossSim.QUEUE, "nor is a car that still rolls")

	# From the moment the soldier starts toward him the car stands, whatever
	# his foot does, until he is let through.
	_begin_checkpoint("", _seed_asking_for("licence"), false)
	_sim.items.flags[ItemSim.FLAG_WINDOW] = true
	_cruise(1, 1)
	_sim.car.s = _sim.boss.bar_at - _sim.car.length() * 0.5 - 5.0
	_sim.car.speed = 0.0
	_input.rmb = true
	check(_until_checkpoint_phase(BossSim.STOW, 2.0), "standing 5 m short of the bar, first in line, the soldier starts toward him")
	var stood_at: float = _sim.car.s
	_input.clear()
	check_eq(_sim.gate.gear, 1, "(first gear is engaged, and his foot is off the brake)")
	check(_until_checkpoint_phase(BossSim.PAPERS, stow_s + 1.0), "(the soldier arrives)")
	_ticks(_ticks_in(2.0))
	check_near(_sim.car.s, stood_at, 0.000001, "the car stands where it stopped through the Stow and the Papers, brake or no brake")
	check_near(_sim.car.speed, 0.0, 0.000001, "(at rest)")
	_hand_out_document("licence")
	check_eq(_sim.boss.phase, BossSim.THROUGH, "(let through)")
	_ticks(_ticks_in(2.0))
	check(_sim.car.s > stood_at + 1.0, "let through, it rolls on in gear")
	check_eq(_count_events("hit"), 0, "(under the raised bar, touching nothing)")

	# What the soldier sees when he arrives, case by case.
	var cases: Array[String] = ["nothing", "flask out", "papers out", "both out", "flask stowed", "two stacks", "three stacks and the flask", "two stacks and mints"]
	for case: String in cases:
		_begin_checkpoint("", 1, false)
		var expected: float = 0.0
		match case:
			"flask out":
				_give("arak_flask", "cup_b")
				expected = per_item
			"papers out":
				_give("forged_papers", "dash_2")
				expected = per_item
			"both out":
				_give("arak_flask", "cup_b")
				_give("forged_papers", "dash_2")
				expected = per_item * 2.0
			"flask stowed":
				var flask: ItemSim.Item = _give("arak_flask", "cup_b")
				flask.slot = &"glovebox_a"
			"two stacks":
				_sim.effects.add(DriveSim.COURAGE, 60.0)
				_sim.effects.add(DriveSim.COURAGE, 60.0)
				expected = per_stack * 2.0
			"three stacks and the flask":
				_give("arak_flask", "cup_b")
				for _stack: int in 3:
					_sim.effects.add(DriveSim.COURAGE, 60.0)
				expected = per_item + per_stack * 3.0
			"two stacks and mints":
				_sim.effects.add(DriveSim.COURAGE, 60.0)
				_sim.effects.add(DriveSim.COURAGE, 60.0)
				_sim.effects.add(&"minty", 120.0)
		check(_stand_at_the_bar(), "%s: standing at the bar, first in line, the soldier starts toward him" % case)
		var began: int = _sim.tick
		check_near(GameData.as_float(_sim.snapshot()["stow_left"]), stow_s, 0.000001, "(10 s away)")
		check_near(_sim.suspicion.value, 0.0, 0.000001, "(nothing is counted while he walks)")
		_ticks(_ticks_in(stow_s) - 1)
		check_eq(_sim.boss.phase, BossSim.STOW, "%s: a tick short of 10 s he is still on his way" % case)
		check_near(_sim.suspicion.value, 0.0, 0.000001, "(and nothing is counted yet)")
		_events = []
		_tick()
		check(_sim.boss.phase != BossSim.STOW, "%s: he is at the window after 10 s" % case)
		check_eq(_sim.tick - began, _ticks_in(stow_s), "(to the tick)")
		if case == "papers out" or case == "both out":
			# Forged papers pass the Papers at once: what was counted is in the verdict.
			check_near(GameData.as_float(_event("pulled_over").get("suspicion")), expected, 0.000001, "%s: +%d Suspicion" % [case, roundi(expected)])
		else:
			check_near(_sim.suspicion.value, expected, 0.000001, "%s: +%d Suspicion" % [case, roundi(expected)])
		if case == "two stacks":
			check_eq(_sim.courage(), 2, "(two stacks of Courage)")
		if case == "two stacks and mints":
			check_eq(_sim.courage(), 2, "(two stacks, but his breath does not tell)")


## Stowing is done with the hand, in the 10 s: glovebox open, DRAG the item in.
func _check_checkpoint_stowing_by_hand() -> void:
	_begin_checkpoint("", 1, false)
	_give("arak_flask", "cup_b")
	check(_stand_at_the_bar(), "(the soldier is on his way)")
	var began: int = _sim.tick
	# With the glovebox shut a press on the flask is a sip, as ever.
	_events = []
	_hold_at("cup_b", GameData.as_float(_ritual("flask_sip").get("hold_s")))
	check_eq(_count_events("ritual_completed", "ritual", "flask_sip"), 1, "with the glovebox shut, a press on the flask is a sip")
	check(not _sim.items.is_stowed(_item("arak_flask")), "(it is still in the cup holder)")
	_tap_at("glovebox")
	check(_sim.items.flag(ItemSim.FLAG_GLOVEBOX), "a TAP opens the glovebox")
	_events = []
	_drag("cup_b", "glovebox")
	check_eq(_count_events("ritual_completed", "ritual", "stow"), 1, "with it open, the flask is dragged to the glovebox")
	check(_sim.items.is_stowed(_item("arak_flask")), "and is stowed in one of its cells")
	check_eq(_sim.items.contraband_in_view(), 0, "nothing contraband is left out")
	check(float(_sim.tick - began) * DT < _checkpoint_number("stow_s"), "all within the 10 s (%.1f s)" % (float(_sim.tick - began) * DT))
	# Stowed, it is out of use.
	_events = []
	_hold_at("glovebox", GameData.as_float(_ritual("flask_sip").get("hold_s")))
	check_eq(_count_events("ritual_completed", "ritual", "flask_sip"), 0, "what is stowed cannot be used")
	check(_until_checkpoint_phase(BossSim.PAPERS, _checkpoint_number("stow_s") + 1.0), "(the soldier arrives)")
	check_near(_sim.suspicion.value, _checkpoint_number("courage_suspicion"), 0.000001, "the stowed flask is not counted: only the sip he took (+15)")

	# Out again: from the open glovebox to a place it fits; a short press still shuts the glovebox.
	_begin_checkpoint("", 1, false)
	var flask: ItemSim.Item = _give("arak_flask", "cup_b")
	flask.slot = &"glovebox_a"
	_sim.items.flags[ItemSim.FLAG_GLOVEBOX] = true
	_events = []
	_drag("glovebox", "cup_b")
	check_eq(_count_events("ritual_completed", "ritual", "unstow"), 1, "it is taken out by dragging it from the open glovebox to a free place of its own")
	check_eq(String(_item("arak_flask").slot), "cup_b", "(the cup holder)")
	_hold_at("cup_b", 0.1)
	_tap_at("glovebox")
	check(not _sim.items.flag(ItemSim.FLAG_GLOVEBOX), "(a TAP shuts the glovebox)")
	flask = _item("arak_flask")
	flask.slot = &"glovebox_b"
	_tap_at("glovebox")
	check(_sim.items.flag(ItemSim.FLAG_GLOVEBOX), "(open again, with the flask in it)")
	_tap_at("glovebox")
	check(not _sim.items.flag(ItemSim.FLAG_GLOVEBOX), "with something stowed in it, a short press still shuts the glovebox")
	check(_sim.items.is_stowed(_item("arak_flask")), "(and the flask stays in)")
	# Both cells taken: there is no room for a third thing.
	_begin_checkpoint("", 1, false)
	var first: ItemSim.Item = _give("arak_flask", "cup_b")
	first.slot = &"glovebox_a"
	_give("forged_papers", "glovebox_b")
	check_eq(_sim.items.free_cell(), "", "the glovebox has two cells")


## Papers: the signed document is found, the window cranked open, and the
## document dragged to the driver's window.
func _check_checkpoint_papers() -> void:
	for document: String in ["licence", "id", "registration"]:
		var boss_seed: int = _seed_asking_for(document)
		_begin_checkpoint("", boss_seed, false)
		check(_stand_at_the_bar(), "(first in line)")
		# Before the soldier is there, the papers are nobody's business.
		check(not _sim.effects.has(DriveSim.AT_WINDOW), "while he walks there is nobody to hand anything to")
		check(_until_checkpoint_phase(BossSim.PAPERS, _checkpoint_number("stow_s") + 1.0), "(the soldier arrives)")
		var shot: Dictionary = _sim.snapshot()
		check_eq(GameData.as_string(shot["wanted"]), document, "his sign shows one of the three documents: %s" % document)
		check(_sim.effects.has(DriveSim.AT_WINDOW), "(he waits at the window)")
		check_eq(_count_events("line_requested", "id", "soldier.window"), 1, "the window is shut: he taps on the glass")
		# Through the glass nothing can be handed out.
		_events = []
		_hand_out_document(document)
		check_eq(_count_events("pulled_over"), 0, "%s: with the window shut the document cannot be handed out" % document)
		check_eq(_sim.boss.wanted, document, "(he still waits for it)")
		# The window: a cross-reach and three turns of the crank.
		check(_reach("window_crank"), "he reaches across for the window crank")
		_crank(GameData.as_float(_ritual("window_crank").get("turns")))
		check(_sim.items.flag(ItemSim.FLAG_WINDOW), "three turns open the window")
		# The wrong document is refused.
		var wrong: String = "id" if document == "licence" else "licence"
		_events = []
		_hand_out_document(wrong)
		check_eq(_count_events("line_requested", "id", "soldier.wrong"), 1, "%s wanted, %s handed out: refused" % [document, wrong])
		check_eq(_count_events("pulled_over"), 0, "(no verdict)")
		check_eq(_sim.boss.wanted, document, "(the sign stays up)")
		# The right one, from where it is kept.
		if document == "registration":
			_events = []
			_tap_at("glovebox")
			check(_sim.items.flag(ItemSim.FLAG_GLOVEBOX), "(the glovebox is open)")
			_drag("glovebox", "driver_window")
			check_eq(_count_events("pulled_over"), 0, "the registration lies under the letter: it cannot be taken yet")
			_hold_at("glovebox", GameData.as_float(_ritual("letter_aside").get("hold_s")))
			check(_sim.items.flag(&"letter_aside"), "the letter is moved aside (0.4 s)")
			check_near(GameData.as_float(_ritual("letter_aside").get("hold_s")), 0.4, 0.000001, "(GDD 7.3)")
			_events = []
			_drag("glovebox", "driver_window")
		else:
			_events = []
			_hand_out_document(document)
		var verdict: Dictionary = _event("pulled_over")
		check(not verdict.is_empty(), "%s: found, and dragged to the driver's window: the papers are done" % document)
		check(GameData.as_bool(verdict.get("released")), "(he is let through)")
		check_eq(_count_events("ritual_completed", "ritual", "papers_" + document), 1, "(through the hand)")
		check_eq(_sim.boss.phase, BossSim.THROUGH, "(the bar goes up)")
		check(not _sim.effects.has(DriveSim.AT_WINDOW), "(the soldier steps back)")
		check(GameData.as_bool(_ritual("papers_" + document).get("eyes_down")), "(GDD 4.7: papers pull the eyes down)")

	# The licence is clipped where an item may sit: during the Papers it comes first.
	_begin_checkpoint("", _seed_asking_for("licence"), false)
	_give("tissue_box", "dash_1")
	_sim.items.flags[ItemSim.FLAG_WINDOW] = true
	_stand_at_the_bar()
	_until_checkpoint_phase(BossSim.PAPERS, _checkpoint_number("stow_s") + 1.0)
	_events = []
	_drag("dash_1", "driver_window")
	check_eq(_count_events("ritual_completed", "ritual", "papers_licence"), 1, "with something on the dash where the licence is clipped, the licence is still what he takes")
	check_eq(_count_events("line_requested", "id", "soldier.window"), 0, "(the window was open already: no tap on the glass)")
	# The window switch opens the window as well as the crank.
	_begin_checkpoint("", _seed_asking_for("id"), false)
	_give("window_switch")
	_stand_at_the_bar()
	_until_checkpoint_phase(BossSim.PAPERS, _checkpoint_number("stow_s") + 1.0)
	_hold_at("window_switch", GameData.as_float(_ritual("window_switch_hold").get("hold_s")))
	check(_sim.items.flag(ItemSim.FLAG_WINDOW), "(the window switch opens the window too)")
	_events = []
	_hand_out_document("id")
	check_eq(_count_events("pulled_over"), 1, "and the ID goes out through it")


## Each 5 s of delay is +10 Suspicion, counted from when the sign went up.
func _check_checkpoint_delay() -> void:
	var every: float = _checkpoint_number("delay_every_s")
	var each: float = _checkpoint_number("delay_suspicion")
	_begin_checkpoint("", _seed_asking_for("licence"), false)
	_sim.items.flags[ItemSim.FLAG_WINDOW] = true
	_stand_at_the_bar()
	_until_checkpoint_phase(BossSim.PAPERS, _checkpoint_number("stow_s") + 1.0)
	check_near(_sim.suspicion.value, 0.0, 0.000001, "(the sign goes up at 0)")
	_ticks(_ticks_in(every) - 1)
	check_near(_sim.suspicion.value, 0.0, 0.000001, "a tick short of 5 s of delay costs nothing")
	check_near(GameData.as_float(_sim.snapshot()["papers_delay"]), every - DT, 0.000001, "(the snapshot counts the delay)")
	_tick()
	check_near(_sim.suspicion.value, each, 0.000001, "5 s of delay: +10")
	_ticks(_ticks_in(every) - 1)
	check_near(_sim.suspicion.value, each, 0.000001, "(nothing more until the next 5 s are full)")
	_tick()
	check_near(_sim.suspicion.value, each * 2.0, 0.000001, "10 s: +20")
	_ticks(_ticks_in(every * 2.0))
	check_near(_sim.suspicion.value, each * 4.0, 0.000001, "20 s: +40")
	# Handing the document over stops the count.
	_events = []
	_hand_out_document("licence")
	var level: float = GameData.as_float(_event("pulled_over").get("suspicion"))
	check(level >= each * 4.0 and level < each * 6.0, "(he hands it over at last, with %d Suspicion)" % roundi(level))
	_ticks(_ticks_in(every * 2.0))
	check_near(_sim.suspicion.value, 0.0, 0.000001, "after the verdict nothing is counted any more")


## Under 50 he passes; from 50 to 99 he is searched; at 100 he is turned back.
func _check_checkpoint_verdicts() -> void:
	var search_minutes: float = _checkpoint_number("search_minutes")
	var back_minutes: float = _checkpoint_number("turned_back_minutes")
	var levels: Array[float] = [0.0, 49.0, 50.0, 99.0, 100.0]
	for level: float in levels:
		# (The one who will be turned back meets the real queue, both times.)
		_begin_checkpoint("", _seed_asking_for("licence"), level >= 100.0)
		var flask: ItemSim.Item = _give("arak_flask", "cup_b")
		flask.slot = &"glovebox_a"
		_give("cigarettes", "ashtray")
		_sim.items.flags[ItemSim.FLAG_WINDOW] = true
		if level >= 100.0:
			_follow_the_queue(1)
		else:
			_stand_at_the_bar()
		_until_checkpoint_phase(BossSim.PAPERS, _checkpoint_number("stow_s") + 1.0)
		check_near(_sim.suspicion.value, 0.0, 0.000001, "(nothing against him yet)")
		_sim.suspicion.add(level)
		var clock_before: float = _sim.clock.minutes
		var tick_before: int = _sim.tick
		_events = []
		_hand_out_document("licence")
		var verdict: Dictionary = _event("pulled_over")
		var driven: float = float(_sim.tick - tick_before) * DT * tuning.f("clock_scale") / 60.0
		# The delay that ran while the hand worked is his too.
		var counted: float = GameData.as_float(verdict.get("suspicion"))
		check(counted >= level and counted <= minf(level + _checkpoint_number("delay_suspicion"), 100.0), "(the verdict is given at %d Suspicion)" % roundi(counted))
		if counted < _checkpoint_number("pass_under"):
			check_eq(GameData.as_string(verdict.get("paid")), "pass", "at %d Suspicion he passes" % roundi(level))
			check(GameData.as_bool(verdict.get("released")), "(let through)")
			check_near(_sim.clock.minutes - clock_before, driven, 0.000001, "at no cost in time")
			check(_item("arak_flask") != null, "and keeps what he stowed")
		elif counted < _checkpoint_number("turned_back_at"):
			check_eq(GameData.as_string(verdict.get("paid")), "search", "at %d Suspicion he is searched" % roundi(level))
			check(GameData.as_bool(verdict.get("released")), "(and then let through)")
			check_near(GameData.as_float(verdict.get("minutes")), search_minutes, 0.000001, "which takes 15 game minutes")
			check_near(_sim.clock.minutes - clock_before, search_minutes + driven, 0.000001, "on the Clock at once")
			check(_item("arak_flask") == null, "contraband is taken, stowed or not")
			check(GameData.as_array(verdict.get("taken")).has("arak_flask"), "(the event names it)")
			check(_item("cigarettes") != null, "(what is no contraband he keeps)")
		else:
			check_eq(GameData.as_string(verdict.get("paid")), "turned_back", "at 100 Suspicion he is turned back")
			check(not GameData.as_bool(verdict.get("released")), "(not let through)")
			check_near(GameData.as_float(verdict.get("minutes")), back_minutes, 0.000001, "which takes 30 game minutes")
			check_near(_sim.clock.minutes - clock_before, back_minutes + driven, 0.000001, "on the Clock at once")
			check(_item("arak_flask") != null, "(he keeps what he has: nobody searched)")
		if counted < _checkpoint_number("turned_back_at"):
			check_eq(_sim.boss.phase, BossSim.THROUGH, "(the bar is up)")
			check(not _sim.suspicion.watching, "Suspicion is gone with the checkpoint")
			check_near(_sim.suspicion.value, 0.0, 0.000001, "(0)")
			# He drives through, to the end of the Checkpoint's road.
			_events = []
			var guard: int = _ticks_in(40.0)
			while _event("boss_ended").is_empty() and guard > 0:
				guard -= 1
				_tick()
			check(not _event("boss_ended").is_empty(), "and he drives on, out of the Checkpoint")
			check_eq(_count_events("hit"), 0, "(the bar does not touch him)")
			continue
		# Turned back: the queue again, from its end.
		check_eq(_sim.boss.phase, BossSim.QUEUE, "and the queue again")
		check(_sim.car.s < 10.0, "from its end (he is %.1f m into the Checkpoint's road)" % _sim.car.s)
		check_eq(_sim.gate.gear, tuning.i("start_gear"), "(in first gear)")
		check_eq(_sim.boss.queue_length(1), GameData.as_int(GameData.as_dict(_checkpoint().get("queue")).get("cars")), "with a whole queue ahead of him once more")
		check(_sim.suspicion.watching, "(he is watched again)")
		check_near(_sim.suspicion.value, 0.0, 0.000001, "with Suspicion begun anew")
		check(not GameData.as_bool(_sim.snapshot()["bar_up"]), "(the bar is down)")
		# And this time, clean, he gets through.
		_events = []
		_follow_the_queue(1)
		check_eq(_sim.boss.phase, BossSim.STOW, "(through the queue a second time)")
		_until_checkpoint_phase(BossSim.PAPERS, _checkpoint_number("stow_s") + 1.0)
		check_eq(_sim.boss.wanted, "licence", "(the same soldier wants the same document)")
		_hand_out_document("licence")
		check_eq(GameData.as_string(_event("pulled_over").get("paid")), "pass", "the second time, with nothing against him, he passes")
		check_eq(_count_events("hit"), 0, "(having touched nothing)")


## 60 cash through the window passes at any level.
func _check_checkpoint_bribe() -> void:
	var price: float = tuning.f("checkpoint_bribe")
	for level: float in [0.0, 70.0, 100.0]:
		_begin_checkpoint("", _seed_asking_for("registration"), false)
		var flask: ItemSim.Item = _give("arak_flask", "cup_b")
		flask.slot = &"glovebox_a"
		_sim.items.flags[ItemSim.FLAG_WINDOW] = true
		_sim.cash = price + 15.0
		_stand_at_the_bar()
		# Before the soldier is at the window there is nobody to pay.
		_events = []
		_drag("cash", "driver_window")
		check_eq(_count_events("pulled_over"), 0, "banknotes cannot be handed out before the soldier is there")
		_until_checkpoint_phase(BossSim.PAPERS, _checkpoint_number("stow_s") + 1.0)
		_sim.suspicion.add(level)
		var clock_before: float = _sim.clock.minutes
		var tick_before: int = _sim.tick
		_events = []
		_drag("cash", "driver_window")
		var verdict: Dictionary = _event("pulled_over")
		check_eq(GameData.as_string(verdict.get("paid")), "bribe", "at %d Suspicion, banknotes through the window: he passes" % roundi(level))
		check(GameData.as_bool(verdict.get("released")), "(let through)")
		check_near(GameData.as_float(verdict.get("cost")), price, 0.000001, "for 60 cash")
		check_near(_sim.cash, 15.0, 0.000001, "which he has paid")
		check_near(_sim.clock.minutes - clock_before, float(_sim.tick - tick_before) * DT * tuning.f("clock_scale") / 60.0, 0.000001, "at no cost in time")
		check(_item("arak_flask") != null, "and nothing is taken")
		check_eq(_count_events("ritual_completed", "ritual", "checkpoint_bribe"), 1, "(through the hand)")
		check_eq(_sim.boss.phase, BossSim.THROUGH, "(the bar is up)")
	# Without 60 he is not taken.
	_begin_checkpoint("", _seed_asking_for("registration"), false)
	_sim.items.flags[ItemSim.FLAG_WINDOW] = true
	_sim.cash = price - 1.0
	_stand_at_the_bar()
	_until_checkpoint_phase(BossSim.PAPERS, _checkpoint_number("stow_s") + 1.0)
	_events = []
	_drag("cash", "driver_window")
	var refused: Dictionary = _event("pulled_over")
	check(GameData.as_bool(refused.get("refused")) and not GameData.as_bool(refused.get("released")), "with less than 60 the banknotes are refused")
	check_near(_sim.cash, price - 1.0, 0.000001, "(he keeps them)")
	check_eq(_sim.boss.phase, BossSim.PAPERS, "(and the soldier still waits for the document)")
	# With the window shut they cannot be handed out either.
	_begin_checkpoint("", _seed_asking_for("registration"), false)
	_sim.cash = price
	_stand_at_the_bar()
	_until_checkpoint_phase(BossSim.PAPERS, _checkpoint_number("stow_s") + 1.0)
	_events = []
	_drag("cash", "driver_window")
	check_eq(_count_events("pulled_over"), 0, "nor through a shut window")


## Forged papers pass the Papers phase by themselves, once (GDD 7.7).
func _check_checkpoint_forged_papers() -> void:
	_begin_checkpoint("", 2, false)
	_give("forged_papers", "glovebox_a")
	check(_stand_at_the_bar(), "(with forged papers in the glovebox)")
	_events = []
	check(_until_checkpoint_phase(BossSim.THROUGH, _checkpoint_number("stow_s") + 1.0), "with forged papers the Papers phase passes by itself")
	var verdict: Dictionary = _event("pulled_over")
	check_eq(GameData.as_string(verdict.get("paid")), "pass", "and he passes")
	check_near(GameData.as_float(verdict.get("suspicion")), 0.0, 0.000001, "(stowed, they cost no Suspicion)")
	check(_item("forged_papers") == null, "the papers are used up")
	check_eq(_count_events("line_requested", "id", "soldier.window"), 0, "(no sign went up: nobody taps on the glass)")
	check_eq(_sim.boss.wanted, "", "(he is asked for nothing)")
	# Left on the dash they are contraband like any other when the soldier arrives.
	_begin_checkpoint("", 2, false)
	_give("forged_papers", "dash_2")
	_stand_at_the_bar()
	_events = []
	_until_checkpoint_phase(BossSim.THROUGH, _checkpoint_number("stow_s") + 1.0)
	check_near(GameData.as_float(_event("pulled_over").get("suspicion")), _checkpoint_number("contraband_suspicion"), 0.000001, "left on the dash they are contraband: +40")
	check_eq(GameData.as_string(_event("pulled_over").get("paid")), "pass", "(under 50 he still passes)")
	# They do not make the verdict: with Suspicion he is searched all the same.
	_begin_checkpoint("", 2, false)
	_give("forged_papers", "glovebox_a")
	_stand_at_the_bar()
	_sim.suspicion.add(60.0)
	_events = []
	_until_checkpoint_phase(BossSim.THROUGH, _checkpoint_number("stow_s") + 1.0)
	check_eq(GameData.as_string(_event("pulled_over").get("paid")), "search", "they pass the Papers, not the verdict: at 60 Suspicion he is searched")


## Long queue: phase 1 is 50% longer. Thorough: two documents.
func _check_checkpoint_modifiers() -> void:
	var listed: Array = GameData.as_array(data.record("bosses", CHECKPOINT).get("modifiers"))
	check(listed.size() == 2 and listed.has("long_queue") and listed.has("thorough"), "GDD 10.2: the Checkpoint's modifiers are Long queue and Thorough")
	check_near(GameData.as_float(data.record("boss_modifiers", "long_queue").get("queue_mult")), 1.5, 0.000001, "Long queue: 50% longer")
	check_eq(GameData.as_int(data.record("boss_modifiers", "thorough").get("documents")), 2, "Thorough: two documents")
	var cars: int = GameData.as_int(GameData.as_dict(_checkpoint().get("queue")).get("cars"))

	# How long the queue takes: from the start until the last vehicle of the middle lane is waved on.
	var took: Dictionary = {}
	for modifier: String in ["", "long_queue"]:
		var plan: Dictionary = _begin_checkpoint(modifier, 3)
		var wanted_cars: int = roundi(float(cars) * (1.5 if modifier == "long_queue" else 1.0))
		for lane: int in 3:
			check_eq(GameData.as_array(GameData.as_array(plan.get("queue"))[lane]).size(), wanted_cars, "%s: %d vehicles in lane %d" % ["Long queue" if modifier != "" else "the plain Checkpoint", wanted_cars, lane])
		_stand_short_of_the_queue()
		var guard: int = _ticks_in(200.0)
		while _sim.boss.queue_length(1) > 0 and guard > 0:
			guard -= 1
			_tick()
		took[modifier] = _sim.seconds()
		check_eq(GameData.as_array(plan.get("documents")).size(), 1, "(one document)")
	var plain: float = GameData.as_float(took[""])
	var long: float = GameData.as_float(took["long_queue"])
	check(long / plain > 1.4 and long / plain < 1.65, "a Long queue takes half as long again: %.1f s against %.1f s" % [long, plain])

	# Thorough: two different documents, one after the other; the verdict after both.
	for boss_seed: int in [1, 2, 3, 4]:
		var plan: Dictionary = BossSim.plan(data, CHECKPOINT, "thorough", boss_seed)
		var asks: Array = GameData.as_array(plan.get("documents"))
		check_eq(asks.size(), 2, "Thorough (seed %d): two documents" % boss_seed)
		check(asks.size() == 2 and GameData.as_string(asks[0]) != GameData.as_string(asks[1]), "(not the same one twice)")
		check_eq(GameData.as_array(GameData.as_array(plan.get("queue"))[0]).size(), cars, "(and a queue of the usual length)")
	var thorough_seed: int = 0
	for candidate: int in range(1, 200):
		var asks: Array = GameData.as_array(BossSim.plan(data, CHECKPOINT, "thorough", candidate).get("documents"))
		if asks.size() == 2 and GameData.as_string(asks[0]) == "licence" and GameData.as_string(asks[1]) == "id":
			thorough_seed = candidate
			break
	check(thorough_seed > 0, "(a Thorough soldier who wants the licence, then the ID)")
	_begin_checkpoint("thorough", thorough_seed, false)
	_sim.items.flags[ItemSim.FLAG_WINDOW] = true
	_stand_at_the_bar()
	_until_checkpoint_phase(BossSim.PAPERS, _checkpoint_number("stow_s") + 1.0)
	check_eq(_sim.boss.wanted, "licence", "first the licence")
	_ticks(_ticks_in(_checkpoint_number("delay_every_s")))
	check_near(_sim.suspicion.value, _checkpoint_number("delay_suspicion"), 0.000001, "(5 s of delay: +10)")
	_events = []
	_hand_out_document("licence")
	check_eq(_count_events("pulled_over"), 0, "after the first document there is no verdict yet")
	check_eq(_sim.boss.wanted, "id", "then the ID")
	check(GameData.as_float(_sim.snapshot()["papers_delay"]) < 0.5, "(the delay is counted afresh for the second sign)")
	var before_second: float = _sim.suspicion.value
	_ticks(_ticks_in(_checkpoint_number("delay_every_s") - 1.0))
	check_near(_sim.suspicion.value, before_second, 0.000001, "(four seconds into the second sign: nothing more)")
	_hand_out_document("id")
	check_eq(_count_events("pulled_over"), 1, "after the second, the verdict")

	# Which Telling has which.
	var share: float = tuning.fi("boss_modifier_chance", 0)
	var counts: Dictionary = {"": 0, "long_queue": 0, "thorough": 0}
	var tellings: int = 600
	for seed_value: int in range(1, tellings + 1):
		var drawn: String = RunGenerator.boss_modifier(data, seed_value, 1)
		check(counts.has(drawn), "a Checkpoint has one of its own modifiers or none (seed %d: '%s')" % [seed_value, drawn])
		counts[drawn] = GameData.as_int(counts.get(drawn)) + 1
	var modified: int = GameData.as_int(counts["long_queue"]) + GameData.as_int(counts["thorough"])
	check(absf(float(modified) - float(tellings) * share) <= 4.0 * sqrt(float(tellings) * share * (1.0 - share)),
			"the Checkpoint has a modifier in boss_modifier_chance of Tellings (%d of %d)" % [modified, tellings])
	check(GameData.as_int(counts["long_queue"]) > 0 and GameData.as_int(counts["thorough"]) > 0, "(both come up)")


## The Checkpoint ends Act 1 of a Telling.
func _check_checkpoint_in_a_telling() -> void:
	_sim = DriveSim.new(fresh_data())
	_events = []
	_keep_lane = true
	_input.clear()
	_sim.begin_telling(TABLE, 5)
	_drive_to_the_boss()
	var started: Dictionary = _event("boss_started")
	check_eq(GameData.as_string(started.get("boss")), CHECKPOINT, "the third leg of Act 1 leads into the Checkpoint")
	check_eq(GameData.as_string(started.get("modifier")), RunGenerator.boss_modifier(data, 5, 1), "with the modifier its seed draws")
	check(_sim.suspicion.watching, "(where he is watched)")
	check_eq(_sim.boss.phase, BossSim.QUEUE, "(and queues)")
	# Driven for real: the queue, the window, the document, and on to the boss stop.
	_sim.items.flags[ItemSim.FLAG_WINDOW] = true
	_events = []
	_follow_the_queue(1)
	check(_until_checkpoint_phase(BossSim.PAPERS, _checkpoint_number("stow_s") + 1.0), "(the soldier comes to the window)")
	while _sim.boss.phase == BossSim.PAPERS:
		var wanted: String = _sim.boss.wanted
		if wanted == "registration":
			if not _sim.items.flag(ItemSim.FLAG_GLOVEBOX):
				_tap_at("glovebox")
			if not _sim.items.flag(&"letter_aside"):
				_hold_at("glovebox", GameData.as_float(_ritual("letter_aside").get("hold_s")))
		_hand_out_document(wanted)
		check(_sim.boss.wanted != wanted or _sim.boss.phase != BossSim.PAPERS, "(the %s is taken)" % wanted)
	check_eq(GameData.as_string(_event("pulled_over").get("paid")), "pass", "driven cleanly, he passes")
	var saves: int = _sim.checkpoints
	var guard: int = _ticks_in(60.0)
	while not _sim.stopped and guard > 0:
		guard -= 1
		_tick()
	check_eq(GameData.as_string(_event("boss_ended").get("boss")), CHECKPOINT, "the Checkpoint ends")
	check_eq(_sim.run.stage, RunState.Stage.BOSS_STOP, "at its boss stop")
	check_eq(_sim.checkpoints, saves + 1, "where the game saves")
	check_eq(_count_events("hit"), 0, "(having touched nothing)")
	check(not _sim.suspicion.watching, "(and nobody watches him any more)")


## The first boss seed whose soldier asks for `document`.
func _seed_asking_for(document: String) -> int:
	for candidate: int in range(1, 200):
		if GameData.as_string(GameData.as_array(BossSim.plan(data, CHECKPOINT, "", candidate).get("documents"))[0]) == document:
			return candidate
	fail("no seed under 200 asks for the %s" % document)
	return 1


## A document handed out of the driver's window from where it is kept. (The
## registration needs the glovebox open and the letter aside first.)
func _hand_out_document(document: String) -> void:
	var from: String = "dash_1"
	if document == "id":
		from = "pocket"
	elif document == "registration":
		from = "glovebox"
	_drag(from, "driver_window")


## The car stands in the middle lane far short of the queue, the brake held:
## the queue is only watched. He stands where the barriers begin: the queue
## is served once he has come to it (see _check_checkpoint_rows).
func _stand_short_of_the_queue() -> void:
	_cruise(1, 1)
	var mouth: Dictionary = GameData.as_dict(_checkpoint().get("corridor"))
	_sim.car.s = GameData.as_float(mouth.get("at_m")) - GameData.as_float(mouth.get("taper_m")) + 1.0
	_sim.car.speed = 0.0
	_input.clear()
	_input.rmb = true


## He drives the queue of `lane` the way it must be driven: first gear, the
## brake behind whatever is ahead and at the bar, until the soldier starts
## toward him.
func _follow_the_queue(lane: int) -> void:
	var guard: int = _ticks_in(240.0)
	_sim.gate.reset(1)
	while _sim.boss.phase == BossSim.QUEUE and guard > 0:
		guard -= 1
		_input.clear()
		var car: CarSim = _sim.car
		var room: float = _sim.boss.bar_at - (car.s + car.length() * 0.5)
		for vehicle: TrafficSim.Vehicle in _sim.traffic.vehicles:
			if absf(vehicle.x - car.lane_center(lane)) < car.lane_width() * 0.5 and vehicle.s > car.s:
				room = minf(room, vehicle.s - vehicle.half_length - car.s - car.length() * 0.5)
		var speed_ms: float = car.speed * KMH_TO_MS
		if room < 1.5 + speed_ms * speed_ms / (2.0 * tuning.f("brake_decel") * KMH_TO_MS) + speed_ms * 0.15:
			_input.rmb = true
		car.x = car.lane_center(lane)
		_tick()
	_input.clear()


## What a mutation run of the Checkpoint found unwatched
## (tools/mutants/checkpoint.py): each of these was a rule a wrong build
## could break with every other check still passing.
func _check_checkpoint_fine_print() -> void:
	var queue: Dictionary = GameData.as_dict(_checkpoint().get("queue"))
	var corridor: Dictionary = GameData.as_dict(_checkpoint().get("corridor"))
	var gap: float = GameData.as_float(queue.get("gap_m"))
	var width: float = GameData.as_float(corridor.get("gap_m"))
	var half_width: float = tuning.f("car_width") * 0.5

	# Thorough never asks for the same document twice, whatever the seed.
	var firsts: Dictionary = {}
	for boss_seed: int in range(1, 61):
		var asks: Array = GameData.as_array(BossSim.plan(data, CHECKPOINT, "thorough", boss_seed).get("documents"))
		check(asks.size() == 2 and GameData.as_string(asks[0]) != GameData.as_string(asks[1]), "Thorough, seed %d: two different documents" % boss_seed)
		if not asks.is_empty():
			firsts[GameData.as_string(asks[0])] = true
	check_eq(firsts.size(), 3, "(over the seeds each of the three documents is asked for first)")

	# Nobody in a queue drives into the one ahead: the vehicle that was waved
	# on keeps its gap like any other until it is clear of the bar.
	_begin_checkpoint("", 3)
	_stand_short_of_the_queue()
	var least: float = INF
	for _index: int in _ticks_in(30.0):
		_tick()
		for lane: int in 3:
			var line: Array[TrafficSim.Vehicle] = []
			for vehicle: TrafficSim.Vehicle in _sim.traffic.vehicles:
				if absf(vehicle.x - _sim.car.lane_center(lane)) < 0.01:
					line.append(vehicle)
			line.sort_custom(func(a: TrafficSim.Vehicle, b: TrafficSim.Vehicle) -> bool: return a.s > b.s)
			for index: int in range(1, line.size()):
				least = minf(least, (line[index - 1].s - line[index - 1].half_length) - (line[index].s + line[index].half_length))
	check(least >= gap - 0.001, "bumper to bumper the queue's vehicles are never nearer than gap_m, the one that drives off included (least %.2f m)" % least)

	# A queue with free road on either side of it: the horn still moves nobody
	# over. Its last vehicle is of a kind that would move over anywhere else.
	var horn_seed: int = 0
	for candidate: int in range(1, 60):
		var line: Array = GameData.as_array(GameData.as_array(BossSim.plan(data, CHECKPOINT, "", candidate).get("queue"))[1])
		if GameData.as_bool(data.record("vehicles", GameData.as_string(line[line.size() - 1])).get("yields_to_horn")):
			horn_seed = candidate
			break
	check(horn_seed > 0, "(a queue whose last vehicle is one that moves over for a horn on the open road)")
	_begin_checkpoint_with(_lone_queue(horn_seed))
	var tail: TrafficSim.Vehicle = _queue_tail(1)
	_cruise(1, 1)
	_sim.car.s = tail.s - tail.half_length - _sim.car.length() * 0.5 - 8.0
	_sim.car.speed = 0.0
	_input.rmb = true
	_tick()
	_events = []
	_tap_at("horn")
	_input.rmb = true
	_ticks(_ticks_in(2.0))
	check_eq(_count_events("ritual_completed", "ritual", "horn"), 1, "(he sounds the horn right behind the queue)")
	var moved_over: int = 0
	for vehicle: TrafficSim.Vehicle in _sim.traffic.vehicles:
		if vehicle.signalling != 0 or vehicle.changing or absf(vehicle.x - _sim.car.lane_center(1)) > 0.001:
			moved_over += 1
	check_eq(moved_over, 0, "with free road beside the queue a honk still moves nobody out of it: there are barriers between")

	# The window open when the sign goes up: he does not tap on the glass.
	_begin_checkpoint("", _seed_asking_for("licence"), false)
	_sim.items.flags[ItemSim.FLAG_WINDOW] = true
	_events = []
	check(_stand_at_the_bar(), "(first in line, the window open)")
	check(_until_checkpoint_phase(BossSim.PAPERS, _checkpoint_number("stow_s") + 1.0), "(the soldier arrives)")
	check_eq(_sim.boss.wanted, "licence", "(his sign is up)")
	check_eq(_count_events("line_requested", "id", "soldier.window"), 0, "the window is open when his sign goes up: he does not tap on the glass")

	# Rolled into at a crawl, the back of the queue is a scrape, and a vehicle
	# is no barrier: no Suspicion.
	_begin_checkpoint("", 3)
	tail = _queue_tail(1)
	_cruise(1, 1)
	_sim.car.s = tail.s - tail.half_length - _sim.car.length() * 0.5 - 1.0
	_events = []
	var guard: int = _ticks_in(5.0)
	while _event("hit").is_empty() and guard > 0:
		guard -= 1
		_sim.car.speed = tuning.f("scrape_max_closing") * 0.5
		_tick()
	check_eq(GameData.as_int(_event("hit").get("kind")), Collision.Hit.SCRAPE, "rolled into at a crawl, the back of the queue is a scrape")
	check_eq(GameData.as_int(_event("hit").get("vehicle")), tail.id, "(of its last vehicle)")
	check_near(_sim.suspicion.value, 0.0, 0.000001, "a scrape of a vehicle is no touch of a barrier: no Suspicion")

	# Whatever puts him inside a vehicle of the queue, he comes out of it
	# between his own barriers, even with free road beyond them.
	_begin_checkpoint_with(_lone_queue(horn_seed))
	tail = _queue_tail(1)
	_cruise(1, 1)
	_keep_lane = false
	var middle: float = _sim.car.lane_center(1)
	_sim.car.s = tail.s - 0.5
	_sim.car.x = middle + 0.1
	_sim.car.speed = 0.0
	_input.rmb = true
	_tick()
	check(absf(_sim.car.x - middle) <= width * 0.5 - half_width + 0.000001, "set down inside the queue's last vehicle, with free road beyond the barrier, he is not put through the barrier (%.2f m off the lane's middle)" % absf(_sim.car.x - middle))
	check(_sim.car.s + _sim.car.length() * 0.5 <= tail.s - tail.half_length + 0.000001, "(he is put behind the vehicle)")
	_keep_lane = true

	# Behind the shut door of the glovebox a stowed flask cannot be drunk from.
	_begin_checkpoint("", 1, false)
	var hidden: ItemSim.Item = _give("arak_flask", "cup_b")
	hidden.slot = &"glovebox_a"
	check(not _sim.items.flag(ItemSim.FLAG_GLOVEBOX), "(the glovebox is shut)")
	_events = []
	_hold_at("glovebox", GameData.as_float(_ritual("flask_sip").get("hold_s")))
	check_eq(_count_events("ritual_completed", "ritual", "flask_sip"), 0, "stowed behind the shut door of the glovebox, the flask cannot be drunk from")
	check_eq(_sim.courage(), 0, "(no Courage)")

	# With no cell free nothing more can be stowed (a glovebox of one cell).
	var small: GameData = fresh_data()
	var slots: Array = GameData.as_array(GameData.as_dict(small.roots["anchors"]).get("slots"))
	for index: int in range(slots.size() - 1, -1, -1):
		if GameData.as_string(GameData.as_dict(slots[index]).get("id")) == "glovebox_b":
			slots.remove_at(index)
	var quiet: Dictionary = BossSim.plan(data, CHECKPOINT, "", 1)
	quiet["queue"] = [[], [], []]
	_begin_checkpoint_with(quiet, small)
	_give("arak_flask", "cup_b")
	_give("forged_papers", "dash_1")
	_sim.items.flags[ItemSim.FLAG_GLOVEBOX] = true
	_drag("cup_b", "glovebox")
	check(_sim.items.is_stowed(_item("arak_flask")), "(a glovebox of one cell: the flask goes in)")
	check_eq(_sim.items.free_cell(), "", "(and it is full)")
	_events = []
	_drag("dash_1", "glovebox")
	check_eq(_count_events("ritual_completed", "ritual", "stow"), 0, "with no cell free, nothing more can be stowed")
	check_eq(String(_item("forged_papers").slot), "dash_1", "(the papers stay where they are)")
	check_eq(_sim.items.contraband_in_view(), 1, "(and in view)")


## Which rows of Suspicion are the Checkpoint's (found by the review of M7):
## choosing a queue is free, a Snap is not, and a car that stands touches
## nothing.
func _check_checkpoint_rows() -> void:
	# Before the barriers he may choose his queue: crossing a lane line with
	# no indicator is a row of the Patrol's (GDD 6.5), not of the Checkpoint.
	_begin_checkpoint("", 1, false)
	var taper_from: float = GameData.as_float(GameData.as_dict(_checkpoint().get("corridor")).get("at_m")) - GameData.as_float(GameData.as_dict(_checkpoint().get("corridor")).get("taper_m"))
	_tick()
	check(_sim.suspicion.watching and _sim.car.s < taper_from, "(he is watched from the Checkpoint's start, and the barriers are still ahead)")
	check_eq(_sim.items.indicator, 0, "(no indicator)")
	_keep_lane = false
	for lane: int in [0, 1, 2, 1]:
		_sim.car.x = _sim.car.lane_center(lane)
		_tick()
	_keep_lane = true
	check(_sim.car.s < taper_from, "(four lane lines crossed before the taper)")
	check_near(_sim.suspicion.value, 0.0, 0.000001, "changing lane before the barriers costs no Suspicion: which queue he joins is his to choose")

	# A Snap is charged wherever the law is watching (GDD 6.1: "Suspicion
	# +30"; 6.5: Suspicion exists "at a checkpoint" too).
	_begin_checkpoint("", 1, false)
	check(_stand_at_the_bar(), "(first in line: the soldier sets out)")
	check_near(_sim.suspicion.value, 0.0, 0.000001, "(a clean cabin: no Suspicion yet)")
	_events = []
	_sim.nerves.set_value(tuning.f("snap_at") - 1.0)
	_tap_at("face")
	check_eq(_count_events("snap"), 1, "(a slap with his Nerves at the top: a Snap, with the soldier on his way)")
	check_near(_sim.suspicion.value, tuning.f("suspicion_snap"), 0.000001, "a Snap at the Checkpoint is +30 Suspicion")
	_ticks(_ticks_in(tuning.f("snap_duration") + 0.5))
	check_near(_sim.suspicion.value, tuning.f("suspicion_snap"), 0.000001, "(once: the two seconds of horn add nothing more)")

	# The car stands from the Stow to the verdict: a car that stands touches
	# nothing. (A barrier brushed in the last tick it moved left its touch
	# on the car; held, the car counted that one touch again every 0.8 s.)
	_begin_checkpoint("", 1, false)
	check(_stand_at_the_bar(), "(first in line)")
	check(_sim.boss.holds_car(), "(the car is held)")
	_sim.car.edge_touched = CarSim.EDGE_RIGHT
	_sim.car.wall_touched = true
	var lamps: int = _sim.faults.lamps
	_events = []
	_ticks(_ticks_in(tuning.f("hit_immunity") * 4.0 + 0.5))
	check_eq(_count_events("hit"), 0, "a barrier brushed as he came to the bar is not hit again while the car stands")
	check_eq(_sim.faults.lamps, lamps, "(no lamp)")
	check_near(_sim.suspicion.value, 0.0, 0.000001, "(and no Suspicion)")

	# Forged papers pass the Papers of the visit that gets him through. A
	# visit that turns him back does not spend them (GDD 7.7: 60 cash).
	_begin_checkpoint("", 2, false)
	_give("forged_papers", "glovebox_a")
	check(_stand_at_the_bar(), "(first in line, forged papers stowed)")
	_sim.suspicion.add(_checkpoint_number("turned_back_at"))
	_events = []
	var guard: int = _ticks_in(_checkpoint_number("stow_s") + 1.0)
	while _event("pulled_over").is_empty() and guard > 0:
		guard -= 1
		_tick()
	check_eq(GameData.as_string(_event("pulled_over").get("paid")), "turned_back", "at the top of Suspicion he is turned back, forged papers or not")
	check(_item("forged_papers") != null, "and the papers are not spent on the visit that turned him back")
	check_eq(_sim.boss.wanted, "", "(no document was asked for)")
	check(_stand_at_the_bar(), "(the queue again: first in line once more)")
	_events = []
	check(_until_checkpoint_phase(BossSim.THROUGH, _checkpoint_number("stow_s") + 1.0), "on the next visit they pass the Papers by themselves")
	check_eq(GameData.as_string(_event("pulled_over").get("paid")), "pass", "(and he passes)")
	check(_item("forged_papers") == null, "(now they are used up)")

	# Focus (GDD 7.4): the road runs at 85% speed, the hand at full speed.
	# The soldier is of the road: his walk and his patience take longer of
	# the hand's time, which is what Focus is bought for.
	var road_speed: float = GameData.as_float(data.record("effects", "focus").get("road_speed"))
	check(road_speed > 0.0 and road_speed < 1.0, "(Focus slows the road)")
	for focused: bool in [false, true]:
		_begin_checkpoint("", _seed_asking_for("licence"), false)
		_sim.items.flags[ItemSim.FLAG_WINDOW] = true
		if focused:
			_sim.effects.add(&"focus", 600.0)
		check(_stand_at_the_bar(), "(first in line)")
		var from_tick: int = _sim.tick
		check(_until_checkpoint_phase(BossSim.PAPERS, _checkpoint_number("stow_s") / road_speed + 1.0), "(the soldier arrives)")
		var walk: float = float(_sim.tick - from_tick) * DT
		var wanted_walk: float = _checkpoint_number("stow_s") / (road_speed if focused else 1.0)
		check_near(walk, wanted_walk, 2.0 * DT, "%s the soldier's walk takes %.2f s of the hand's time" % ["with Focus" if focused else "without Focus", wanted_walk])
		from_tick = _sim.tick
		guard = _ticks_in(_checkpoint_number("delay_every_s") / road_speed + 1.0)
		while _sim.suspicion.value <= 0.0 and guard > 0:
			guard -= 1
			_tick()
		var patience: float = float(_sim.tick - from_tick) * DT
		var wanted_patience: float = _checkpoint_number("delay_every_s") / (road_speed if focused else 1.0)
		check_near(patience, wanted_patience, 2.0 * DT, "and his first +10 for the delay comes after %.2f s" % wanted_patience)

	# The law at his window is no empty road (GDD 6.1: "no vehicle within
	# 60 m and no encounter"): until he is let through, standing at the
	# Checkpoint does not calm him.
	_begin_checkpoint("", _seed_asking_for("licence"), false)
	_sim.in_encounter = false
	check(_stand_at_the_bar(), "(first in line, nobody else on the road)")
	_sim.nerves.set_value(50.0)
	_ticks(_ticks_in(4.0))
	check_near(_sim.nerves.value, 50.0, 0.000001, "with the soldier on his way his Nerves do not fall as on an empty road")
	_sim.items.flags[ItemSim.FLAG_WINDOW] = true
	check(_until_checkpoint_phase(BossSim.PAPERS, _checkpoint_number("stow_s") + 1.0), "(the soldier is at his window)")
	_sim.nerves.set_value(50.0)
	_ticks(_ticks_in(2.0))
	check_near(_sim.nerves.value, 50.0, 0.000001, "nor with him at the window")
	_drag("dash_1", "driver_window")
	check(_until_checkpoint_phase(BossSim.THROUGH, 1.0), "(his licence handed out: he is let through)")
	_sim.nerves.set_value(50.0)
	_input.clear()
	_input.rmb = true
	_ticks(_ticks_in(4.0))
	check_near(_sim.nerves.value, 50.0 + 4.0 * tuning.f("empty_road_rate"), 0.05, "let through, an empty road is an empty road again")
	check(tuning.f("empty_road_rate") < 0.0, "(which calms)")

	# The queue is served once he has come to it. Short of the barriers
	# there is nothing to wait out: phase 1 is his to drive (GDD 10.2).
	var plan: Dictionary = _begin_checkpoint("", 3)
	var taper: float = GameData.as_float(GameData.as_dict(_checkpoint().get("corridor")).get("at_m")) - GameData.as_float(GameData.as_dict(_checkpoint().get("corridor")).get("taper_m"))
	var waiting: Array[int] = []
	for lane: int in GameData.as_int(plan.get("lanes")):
		waiting.append(_sim.boss.queue_length(lane))
	_cruise(1, 1)
	_sim.car.s = taper - 10.0
	_sim.car.speed = 0.0
	_input.clear()
	_input.rmb = true
	_ticks(_ticks_in(_checkpoint_number_of_queue("serve_s") * 3.0 + 1.0))
	var after: Array[int] = []
	for lane: int in GameData.as_int(plan.get("lanes")):
		after.append(_sim.boss.queue_length(lane))
	check(_sim.car.s < taper and _sim.car.speed < 0.01, "(he stands on the brake short of the barriers)")
	check_eq(after, waiting, "while he waits short of the barriers no queue gets shorter: there is nothing to wait out")
	_sim.car.s = taper + 1.0
	_ticks(_ticks_in(_checkpoint_number_of_queue("serve_s") + 0.5))
	var served: int = 0
	for lane: int in GameData.as_int(plan.get("lanes")):
		served += waiting[lane] - _sim.boss.queue_length(lane)
	check_eq(served, GameData.as_int(plan.get("lanes")), "once he is between the barriers each lane's first vehicle is waved on after its %s s" % str(_checkpoint_number_of_queue("serve_s")))

	# The Checkpoint's sign can be read: rolling in at par it is ahead of
	# him for two seconds and more, and it stands before the barriers begin.
	# (It stood 1 m into the road: in view for five ticks.)
	_begin_checkpoint("", 1, false)
	var par_ms: float = tuning.fi("gear_speeds", 2) * KMH_TO_MS
	_tick()
	var sign: Dictionary = _sign("checkpoint")
	check(not sign.is_empty(), "as the Checkpoint begins its sign is in view")
	var sign_ahead: float = GameData.as_float(sign.get("ahead"))
	check(sign_ahead >= 2.0 * par_ms, "it is two seconds or more ahead of him at par (%.1f m, %.2f s)" % [sign_ahead, sign_ahead / par_ms])
	check(_sim.car.s + sign_ahead < taper, "and it stands before the barriers begin (at %.1f m; they begin at %.1f m)" % [_sim.car.s + sign_ahead, taper])
	check_near(GameData.as_float(sign.get("limit")), 0.0, 0.000001, "(a checkpoint to stop at: its sign names no speed)")
	var seen_ticks: int = 0
	guard = _ticks_in(10.0)
	while not _sign("checkpoint").is_empty() and guard > 0:
		guard -= 1
		seen_ticks += 1
		_tick()
	check(float(seen_ticks) * DT >= 2.0, "driving up at par he has it in view for %.2f s" % (float(seen_ticks) * DT))

	# Whoever is waved on drives off down the road and leaves it at its
	# end: nobody vanishes in front of him. (Each lane kept one: the one
	# before was taken off the road, 66 m past the bar, when the next left.)
	plan = _begin_checkpoint("", 3)
	var road_end: float = GameData.as_float(plan.get("length"))
	_stand_short_of_the_queue()
	var last_seen: Dictionary = {}
	var vanished_at: Array[float] = []
	guard = _ticks_in(150.0)
	while (_sim.boss.queue_length(1) > 0 or not last_seen.is_empty()) and guard > 0:
		guard -= 1
		_tick()
		var on_road: Dictionary = {}
		for vehicle: TrafficSim.Vehicle in _sim.traffic.vehicles:
			if vehicle.lane == 1 and vehicle.role == BossSim.WAVED_ON_ROLE:
				on_road[vehicle.id] = vehicle.s - vehicle.half_length
		for id: Variant in last_seen.keys():
			if not on_road.has(id):
				vanished_at.append(GameData.as_float(last_seen[id]))
				last_seen.erase(id)
		for id: Variant in on_road:
			last_seen[id] = on_road[id]
	check_eq(vanished_at.size(), GameData.as_int(GameData.as_dict(_checkpoint().get("queue")).get("cars")), "(every vehicle of the middle lane's queue was waved on and has left the road)")
	var earliest: float = INF
	for at: float in vanished_at:
		earliest = minf(earliest, at)
	check(earliest >= road_end - 1.0, "each drove to the road's end before it was gone (the first to go was last seen %.1f m along; the road ends at %.1f m)" % [earliest, road_end])


## A number of the Checkpoint's queue (data/legs.json).
func _checkpoint_number_of_queue(key: String) -> float:
	return GameData.as_float(GameData.as_dict(_checkpoint().get("queue")).get(key))


## The Checkpoint's plan for `boss_seed` with a queue in the middle lane only.
func _lone_queue(boss_seed: int) -> Dictionary:
	var plan: Dictionary = BossSim.plan(data, CHECKPOINT, "", boss_seed)
	plan["queue"] = [[], GameData.as_array(GameData.as_array(plan.get("queue"))[1]), []]
	return plan


## The Checkpoint by itself with a plan of the test's own making (and, if
## given, data of its own making), rolling in as _begin_checkpoint has it.
func _begin_checkpoint_with(plan: Dictionary, changed: GameData = null) -> void:
	_sim = DriveSim.new(changed if changed != null else fresh_data())
	_events = []
	_keep_lane = true
	_input.clear()
	_sim.gate.reset(3)
	_sim.begin_leg(plan)
	_sim.in_encounter = true
	_sim.drain_events()


## The last vehicle of a lane's queue.
func _queue_tail(lane: int) -> TrafficSim.Vehicle:
	var tail: TrafficSim.Vehicle = null
	for vehicle: TrafficSim.Vehicle in _sim.traffic.vehicles:
		if vehicle.lane == lane and vehicle.role == BossSim.QUEUE_ROLE and (tail == null or vehicle.s < tail.s):
			tail = vehicle
	return tail


# --- T-BOSS-02: the Storm (GDD 10.3) -----------------------------------------

func test_boss_02() -> void:
	_check_storm_is_measured_by_distance()
	_check_storm_dust_rhythm()
	_check_storm_gusts("")
	_check_storm_haze()
	_check_storm_standing()
	_check_storm_cramp()
	_check_storm_modifiers()
	_check_storm_tail_lights()
	_check_storm_in_a_telling()


## 2,000 m, by distance: a car that stands for longer than the whole drive
## takes is no nearer the end for it.
func _check_storm_is_measured_by_distance() -> void:
	var record: Dictionary = data.record("bosses", STORM)
	var length: float = GameData.as_float(record.get("length_m"))
	check_near(length, 2000.0, 0.000001, "GDD 10.3: the Storm is 2,000 m")
	check_eq(GameData.as_int(record.get("act")), 2, "it ends Act 2")
	check_near(GameData.as_float(record.get("par_s")), 100.0, 0.000001, "its par is 100 s")

	var plan: Dictionary = _begin_quiet_boss(STORM)
	check_near(GameData.as_float(plan.get("length")), length, 0.000001, "the Storm's road is as long as its record says")
	check_eq(_sim.boss.kind, STORM, "he is in the Storm")
	check_eq(GameData.as_string(_sim.snapshot()["boss"]), STORM, "(the snapshot says so)")
	# Straight through in third gear.
	var guard: int = _ticks_in(200.0)
	while _event("boss_ended").is_empty() and guard > 0:
		guard -= 1
		_tick()
	var through: float = _sim.seconds()
	check(not _event("boss_ended").is_empty(), "the Storm ends")
	check(_sim.car.s >= length and _sim.car.s < length + 1.0, "at 2,000 m (ended at %.2f m)" % _sim.car.s)
	check_near(through, length / (tuning.fi("gear_speeds", 2) * KMH_TO_MS), 0.1, "which third gear reaches in 72 s")
	check(not _sim.boss.active, "and then he is out of it")
	check(is_inf(_sim.visibility()), "(the dust is behind him)")
	_wipe()
	check_near(_sim.items.haze, 0.0, 0.000001, "(and his wipers smear nothing any more)")

	# The same road with a long halt on the shoulder, hazard lights on.
	_begin_quiet_boss(STORM)
	var halt_at: float = 500.0
	while _sim.car.s < halt_at:
		_tick()
	_stand_on_the_shoulder(true)
	var stood_at: float = _sim.car.s
	_ticks(_ticks_in(through * 2.0))
	check(_event("boss_ended").is_empty(), "standing for twice the time the drive takes does not end the Storm")
	check(_sim.boss.active and _sim.leg.active, "(he is still in it)")
	check_near(_sim.car.s, stood_at, 0.000001, "nor does it bring him a metre further")
	check_eq(_sim.faults.lamps, 0, "(nothing hit him there)")
	# On again: the end is where it was.
	_drive_on()
	guard = _ticks_in(200.0)
	var from_tick: int = _sim.tick
	while _event("boss_ended").is_empty() and guard > 0:
		guard -= 1
		_tick()
	check(_sim.car.s >= length and _sim.car.s < length + 1.0, "after the halt the Storm still ends at 2,000 m (ended at %.2f m)" % _sim.car.s)
	check_near(float(_sim.tick - from_tick) * DT, (length - stood_at) / (tuning.fi("gear_speeds", 2) * KMH_TO_MS), 0.1,
			"all the road that was left when he stopped was still to drive")


## Visibility: 8 s thin (40 m), 12 s thick (15 m), over and over, by the clock.
func _check_storm_dust_rhythm() -> void:
	var storm: Dictionary = _storm()
	var thin_s: float = GameData.as_float(storm.get("thin_s"))
	var thick_s: float = GameData.as_float(storm.get("thick_s"))
	var thin_m: float = GameData.as_float(storm.get("thin_m"))
	var thick_m: float = GameData.as_float(storm.get("thick_m"))
	check_near(thick_s, 12.0, 0.000001, "GDD 10.3: thick dust lasts 12 s")
	check_near(thin_s, 8.0, 0.000001, "thin dust 8 s")
	check_near(thick_m, 15.0, 0.000001, "in thick dust he sees 15 m")
	check_near(thin_m, 40.0, 0.000001, "in thin dust 40 m")

	for standing: bool in [false, true]:
		_begin_quiet_boss(STORM)
		if standing:
			_stand_on_the_shoulder(true)
		# How far he sees at each tick, as runs of the same distance.
		var reaches: Array[float] = []
		var lengths: Array[int] = []
		for _index: int in _ticks_in(2.0 * (thin_s + thick_s) + thin_s * 0.5):
			var reach: float = _sim.visibility()
			if reaches.is_empty() or reach != reaches[-1]:
				reaches.append(reach)
				lengths.append(0)
			lengths[-1] += 1
			_tick()
		var how: String = "standing" if standing else "driving"
		check_eq(reaches.size(), 5, "%s: the dust changes four times in 44 s" % how)
		if reaches.size() != 5:
			continue
		check_near(reaches[0], thin_m, 0.000001, "%s: the Storm opens thin (40 m)" % how)
		check_eq(lengths[0], _ticks_in(thin_s), "%s: for 8 s" % how)
		check_near(reaches[1], thick_m, 0.000001, "%s: then thick (15 m)" % how)
		check_eq(lengths[1], _ticks_in(thick_s), "%s: for 12 s" % how)
		check_near(reaches[2], thin_m, 0.000001, "%s: thin again" % how)
		check_eq(lengths[2], _ticks_in(thin_s), "%s: for 8 s again" % how)
		check_near(reaches[3], thick_m, 0.000001, "%s: thick again" % how)
		check_eq(lengths[3], _ticks_in(thick_s), "%s: for 12 s again: a fixed 20 s rhythm" % how)
		check_near(GameData.as_float(_sim.snapshot()["visibility"]), _sim.visibility(), 0.000001, "(the snapshot carries it)")
	# What the view needs for the dust's tell: thick or thin, and when it changes.
	_begin_quiet_boss(STORM)
	_ticks(_ticks_in(thin_s - 1.0))
	check(not GameData.as_bool(_sim.snapshot()["dust_thick"]), "(7 s in, the dust is thin)")
	check_near(GameData.as_float(_sim.snapshot()["dust_change_in"]), 1.0, DT, "(and thickens in 1 s)")
	_ticks(_ticks_in(1.0))
	check(GameData.as_bool(_sim.snapshot()["dust_thick"]), "(8 s in it is thick)")
	check_near(GameData.as_float(_sim.snapshot()["dust_change_in"]), thick_s, DT, "(for 12 s)")


## Gusts push at 2 m/s (3 with Crosswind), each announced 1 s ahead.
func _check_storm_gusts(modifier: String) -> void:
	var storm: Dictionary = _storm()
	var push: float = GameData.as_float(storm.get("gust_push"))
	if modifier.is_empty():
		check_near(push, 2.0, 0.000001, "GDD 10.3: a gust pushes at 2 m/s")
		check_near(tuning.f("gust_tell"), 1.0, 0.000001, "and is announced 1 s ahead")
	else:
		push *= GameData.as_float(data.record("boss_modifiers", modifier).get("gust_mult"))
	var who: String = "the Storm" if modifier.is_empty() else modifier
	var plan: Dictionary = _begin_quiet_boss(STORM, modifier)
	var planned: Array = GameData.as_array(plan.get("gusts"))
	var par_ms: float = tuning.fi("gear_speeds", 2) * KMH_TO_MS
	var every: float = GameData.as_float(storm.get("gust_every_s")) * par_ms
	check_eq(planned.size(), int(floorf((GameData.as_float(plan.get("length")) - 0.001) / every)), "%s: a gust every %d m of it" % [who, roundi(every)])
	for index: int in planned.size():
		check_near(GameData.as_float(GameData.as_dict(planned[index]).get("s")), every * float(index + 1), 0.01, "%s: gust %d is where the rhythm puts it" % [who, index + 1])

	var crown: float = tuning.f("crown_drift")
	# Tick by tick: when a tell begins, which way it points, and when and how
	# hard the car is pushed.
	var tell_began: Array[int] = []
	var tell_way: Array[int] = []
	var push_began: Array[int] = []
	var push_ended: Array[int] = []
	var pushes: Array[float] = []
	var telling: bool = false
	var pushing: bool = false
	var guard: int = _ticks_in(200.0)
	while _event("boss_ended").is_empty() and guard > 0:
		guard -= 1
		_tick()
		var shot: Dictionary = _sim.snapshot()
		var told: bool = GameData.as_float(shot["gust_tell"]) > 0.0
		if told and not telling:
			tell_began.append(_sim.tick)
			tell_way.append(GameData.as_int(shot["gust_dir"]))
		telling = told
		var sideways: float = _sim.car.drift - crown
		var pushed: bool = absf(sideways) > 0.001
		if pushed and not pushing:
			push_began.append(_sim.tick)
			pushes.append(sideways)
		elif pushed and not is_equal_approx(sideways, pushes[-1]):
			fail("%s: a gust's push changed while it blew (%.3f, then %.3f m/s)" % [who, pushes[-1], sideways])
		if pushing and not pushed:
			push_ended.append(_sim.tick)
		pushing = pushed
	check_eq(tell_began.size(), planned.size(), "%s: every gust is announced" % who)
	check_eq(push_began.size(), planned.size(), "%s: and every gust blows" % who)
	if tell_began.size() != planned.size() or push_began.size() != planned.size() or push_ended.size() != planned.size():
		return
	var lefts: int = 0
	for index: int in planned.size():
		var way: int = GameData.as_int(GameData.as_dict(planned[index]).get("dir"))
		lefts += 1 if way < 0 else 0
		check_eq(push_began[index] - tell_began[index], _ticks_in(tuning.f("gust_tell")), "%s: gust %d is announced 1 s before it pushes" % [who, index + 1])
		check_eq(tell_way[index], way, "%s: the streaks of gust %d point the way it will push" % [who, index + 1])
		check_near(pushes[index], push * float(way), 0.000001, "%s: gust %d pushes at %.1f m/s" % [who, index + 1, push])
		check_eq(push_ended[index] - push_began[index], _ticks_in(tuning.f("gust_duration")), "%s: for gust_duration" % who)
	if modifier.is_empty():
		# From either side: over a handful of seeds both ways come up.
		var rights: int = planned.size() - lefts
		for seed_value: int in range(2, 8):
			for entry: Variant in GameData.as_array(BossSim.plan(data, STORM, "", seed_value).get("gusts")):
				if GameData.as_int(GameData.as_dict(entry).get("dir")) < 0:
					lefts += 1
				else:
					rights += 1
		check(lefts > 0 and rights > 0, "gusts come from the left and from the right (%d and %d)" % [lefts, rights])
		check_eq(JSON.stringify(BossSim.plan(data, STORM, "", 5)), JSON.stringify(BossSim.plan(data, STORM, "", 5)), "the same seed gives the same Storm")
		check(JSON.stringify(BossSim.plan(data, STORM, "", 5)) != JSON.stringify(BossSim.plan(data, STORM, "", 6)), "another seed another")


## Each wiper sweep adds 10% Haze; an open window adds 5% per second.
func _check_storm_haze() -> void:
	var storm: Dictionary = _storm()
	var smear: float = GameData.as_float(storm.get("wipe_haze"))
	var window_rate: float = GameData.as_float(storm.get("window_haze_per_s"))
	check_near(smear, 0.10, 0.000001, "GDD 10.3: a wiper sweep adds 10% Haze")
	check_near(window_rate, 0.05, 0.000001, "an open window 5% per second")
	var clears: float = tuning.f("haze_clear_rate")
	var cap: float = tuning.f("haze_cap")

	_begin_quiet_boss(STORM)
	check_near(_sim.items.haze, 0.0, 0.000001, "(the glass is clear as he drives in)")
	_reach("wiper_stalk")
	for sweep: int in 3:
		var before: float = _sim.items.haze
		var from_tick: int = _sim.tick
		_events = []
		_flick(Vector2(0.0, -tuning.f("flick_min_distance") * 1.5))
		check_eq(_count_events("ritual_completed", "ritual", "wipers"), 1, "(sweep %d is made through the hand)" % (sweep + 1))
		# What cleared by itself while the hand made the sweep is the only slack.
		var slack: float = clears * float(_sim.tick - from_tick) * DT
		check(_sim.items.haze <= before + smear + 0.000001 and _sim.items.haze >= before + smear - slack - 0.000001,
				"sweep %d smears 10%% more Haze on the glass (%.4f to %.4f)" % [sweep + 1, before, _sim.items.haze])
	check_near(GameData.as_float(_sim.snapshot()["haze"]), _sim.items.haze, 0.000001, "(the snapshot carries the Haze)")
	for _sweep: int in 6:
		_flick(Vector2(0.0, -tuning.f("flick_min_distance") * 1.5))
	check(_sim.items.haze <= cap + 0.000001 and _sim.items.haze > cap - smear, "sweep after sweep clouds it no further than haze_cap (%.3f)" % _sim.items.haze)
	# The thumb keypad's wiper key smears just the same.
	_begin_quiet_boss(STORM)
	_give("thumb_keypad")
	_grip()
	_input.pad_wiper = true
	_tick()
	_input.pad_wiper = false
	_tick()
	check(_sim.items.haze > smear - clears * DT * 3.0 and _sim.items.haze <= smear + 0.000001, "a sweep from the thumb keypad smears as much")

	# Not on any other road.
	_new_sim()
	_wipe()
	check_near(_sim.items.haze, 0.0, 0.000001, "out of the Storm a sweep smears nothing")
	_begin_quiet_leg("rain", 1, 3)
	_wipe()
	check_near(_sim.items.haze, 0.0, 0.000001, "nor in the rain")

	# The window.
	_begin_quiet_boss(STORM)
	_run(2.0)
	check_near(_sim.items.haze, 0.0, 0.000001, "with the window shut the dust stays out")
	_sim.items.complete(_ritual("window_crank"), 0)
	check(_sim.items.flag(ItemSim.FLAG_WINDOW), "(the window is open)")
	var open_ticks: int = _ticks_in(4.0)
	_ticks(open_ticks)
	check_near(_sim.items.haze, window_rate * float(open_ticks) * DT, 0.000001, "an open window lets in 5% Haze a second (20% in 4 s)")
	_ticks(_ticks_in(cap / window_rate))
	check_near(_sim.items.haze, cap, 0.000001, "up to haze_cap")
	_sim.items.complete(_ritual("window_crank"), 0)
	var shut_ticks: int = _ticks_in(2.0)
	_ticks(shut_ticks)
	check_near(_sim.items.haze, cap - clears * float(shut_ticks) * DT, 0.000001, "shut again, the glass clears as ever")
	_new_sim()
	_sim.items.complete(_ritual("window_crank"), 0)
	_run(4.0)
	check_near(_sim.items.haze, 0.0, 0.000001, "out of the Storm an open window lets in none")


## Stopped on the shoulder with the hazard lights on he is always safe.
## Anywhere else, or dark, something may hit him from behind every 10 s.
func _check_storm_standing() -> void:
	var storm: Dictionary = _storm()
	var every: float = GameData.as_float(storm.get("rear_end_every_s"))
	var tell: float = GameData.as_float(storm.get("rear_end_tell_s"))
	var chance: float = GameData.as_float(storm.get("rear_end_chance"))
	check_near(every, 10.0, 0.000001, "GDD 10.3: the risk comes every 10 s")
	check(tell >= 1.0, "GDD 2.2, pillar 4: with a tell at least 1 s ahead")
	check(chance > 0.0 and chance < 1.0, "it is a risk: neither sure nor never (%.2f)" % chance)
	var periods: int = 30
	var crash_lamps: int = int(tuning.fi("hit_lamps", 1))

	# Safe: on the shoulder, hazard lights on. Thirty waits in each of three Storms.
	for seed_value: int in [1, 2, 3]:
		_begin_quiet_boss(STORM, "", seed_value)
		_sim.rng.reseed(seed_value)
		_stand_on_the_shoulder(true)
		_events = []
		_ticks(_ticks_in(every * float(periods)))
		check_eq(_count_events("hit"), 0, "on the shoulder with his hazard lights on nothing hits him (seed %d, %d s)" % [seed_value, roundi(every * float(periods))])
		check_eq(_sim.faults.lamps, 0, "(no lamp)")
		check_eq(_horns_behind(), 0, "(and nothing comes up behind him)")

	# Not safe, three ways: dark on the shoulder; lit in a lane; lit and half
	# on the shoulder.
	var unsafe: Array[String] = ["on the shoulder without his hazard lights", "in a lane with them on", "half on the shoulder with them on"]
	var total_hits: int = 0
	for way: int in unsafe.size():
		_begin_quiet_boss(STORM, "", 1)
		_sim.rng.reseed(11 + way)
		if way == 0:
			_stand_on_the_shoulder(false)
		elif way == 1:
			_stand_in_lane(true)
		else:
			_stand_on_the_shoulder(true)
			_sim.car.x = _sim.car.road_right() + _sim.car.half_width() - 0.3
		_events = []
		var began: int = _sim.tick
		var hits: Array[int] = []
		var tells: Array[int] = []
		var lamps: int = 0
		for _index: int in _ticks_in(every * float(periods)):
			var before: int = _events.size()
			var nerves_before: float = _sim.nerves.value
			var lamps_before: int = _sim.faults.lamps
			_tick()
			for index: int in range(before, _events.size()):
				var event: Dictionary = _events[index]
				if GameData.as_string(event.get("type")) == "hit":
					hits.append(_sim.tick - began)
					check_eq(GameData.as_int(event.get("kind")), Collision.Hit.CRASH, "%s: what hits him is a crash" % unsafe[way])
					check(GameData.as_bool(event.get("rear_end")), "(from behind)")
					if hits.size() == 1:
						check_eq(_sim.faults.lamps - lamps_before, crash_lamps, "(two lamps)")
						check(_sim.nerves.value - nerves_before >= tuning.fi("hit_nerves", 1) - 0.01, "(and a crash's Nerves)")
				elif GameData.as_string(event.get("type")) == "sfx_requested" and GameData.as_bool(event.get("behind")):
					tells.append(_sim.tick - began)
			lamps = _sim.faults.lamps
		total_hits += hits.size()
		check(hits.size() > 0 and hits.size() < periods, "%s: in %d waits of 10 s he is hit %d times: a risk each time" % [unsafe[way], periods, hits.size()])
		for at: int in hits:
			check_eq(at % _ticks_in(every), 0, "%s: a hit comes at a whole 10 s of standing (after %.2f s)" % [unsafe[way], float(at) * DT])
		check_eq(tells.size(), hits.size(), "%s: each hit is announced, and nothing else is" % unsafe[way])
		for index: int in mini(tells.size(), hits.size()):
			check_eq(hits[index] - tells[index], _ticks_in(tell), "%s: by a horn behind him %d s before" % [unsafe[way], roundi(tell)])
		check(lamps > 0, "(lamps were lit)")
	var mean: float = float(periods * unsafe.size()) * chance
	var spread: float = sqrt(float(periods * unsafe.size()) * chance * (1.0 - chance))
	check(absf(float(total_hits) - mean) <= 4.0 * spread, "about half the waits end in a hit (%d of %d)" % [total_hits, periods * unsafe.size()])

	# The tell is a second in which to save himself: by driving off...
	for remedy: int in 3:
		_begin_quiet_boss(STORM, "", 1)
		_sim.rng.reseed(11)
		_stand_on_the_shoulder(false)
		_events = []
		var guard: int = _ticks_in(every * float(periods))
		while _horns_behind() == 0 and guard > 0:
			guard -= 1
			_tick()
		check(guard > 0, "(something comes up behind him)")
		check(GameData.as_float(_sim.snapshot()["rear_end_in"]) > tell - 2.0 * DT, "(its lights are in the mirror: %d s away)" % roundi(tell))
		match remedy:
			0:
				# ...he stays: it hits him.
				pass
			1:
				_drive_on()
				_sim.gate.reset(1)
			2:
				# ...or by putting his hazard lights on, there on the shoulder.
				_tap_at("hazard_button")
				check(_sim.items.flag(DriveSim.FLAG_HAZARDS), "(his hazard lights are on)")
		_events = []
		_ticks(_ticks_in(tell + 1.0))
		var what: String = ["he stays as he is: it hits him", "he drives off: it misses him", "he puts his hazard lights on: it misses him"][remedy]
		check_eq(_count_events("hit"), 1 if remedy == 0 else 0, "the horn sounds and %s" % what)
		check_near(GameData.as_float(_sim.snapshot()["rear_end_in"]), 0.0, 0.000001, "(then nothing is behind him)")
		if remedy == 1:
			# Standing again is a new wait, from nothing.
			_stand_on_the_shoulder(false)
			_events = []
			var again: int = _sim.tick
			guard = _ticks_in(every * float(periods))
			while _count_events("hit") == 0 and guard > 0:
				guard -= 1
				_tick()
			var waited: int = _sim.tick - again
			check(waited >= _ticks_in(every) and waited % _ticks_in(every) == 0,
					"standing again, a hit comes no sooner than a whole 10 s on (it came after %.2f s)" % (float(waited) * DT))
			check_eq(_horns_behind(), 1, "(and is announced as ever)")

	# Slow is not stopped: at a crawl nothing comes.
	_begin_quiet_boss(STORM, "", 1)
	_sim.rng.reseed(11)
	_events = []
	var crawl: float = GameData.as_float(storm.get("stopped_kmh")) + 2.0
	for _index: int in _ticks_in(every * 6.0):
		_sim.car.speed = crawl
		_tick()
	check_eq(_count_events("hit"), 0, "a car that still rolls is not stopped: nothing hits it")
	# And on a leg that is no Storm a standing car is left alone.
	_begin_quiet_leg("open_road", 1, 3)
	_sim.rng.reseed(11)
	_stand_in_lane(false)
	_events = []
	_ticks(_ticks_in(every * 6.0))
	check_eq(_count_events("hit"), 0, "out of the Storm a standing car is not run into")


## The weather cramp fires once (GDD 7.9).
func _check_storm_cramp() -> void:
	var at: float = GameData.as_float(data.record("bosses", STORM).get("length_m")) * tuning.f("phantom_cramp_at")
	_begin_quiet_boss(STORM)
	var hums: int = 0
	var cramps: int = 0
	var hum_at: float = -1.0
	var was: String = ""
	var nerves_at_cramp: float = 0.0
	var guard: int = _ticks_in(200.0)
	while _event("boss_ended").is_empty() and guard > 0:
		guard -= 1
		var before: float = _sim.nerves.value
		_tick()
		if _sim.cramp != was:
			if _sim.cramp == DriveSim.HUM:
				hums += 1
				hum_at = _sim.car.s
			elif _sim.cramp == DriveSim.CRAMPED:
				cramps += 1
				nerves_at_cramp = _sim.nerves.value - before
			was = _sim.cramp
	check_eq(hums, 1, "the low hum comes once in the Storm")
	check_eq(cramps, 1, "and the cramp once")
	check(hum_at >= at and hum_at < at + 1.0, "at a fixed point of it: %d m (it began at %.1f m)" % [roundi(at), hum_at])
	check_near(nerves_at_cramp, tuning.f("phantom_cramp_nerves"), 0.01, "it costs phantom_cramp_nerves")
	# Switched off in the settings, it does not come.
	_begin_quiet_boss(STORM)
	_sim.phantom_enabled = false
	hums = 0
	guard = _ticks_in(200.0)
	while _event("boss_ended").is_empty() and guard > 0:
		guard -= 1
		_tick()
		hums += 1 if _sim.cramp != "" else 0
	check_eq(hums, 0, "with the Phantom switched off there is no cramp in the Storm")


## Crosswind: gusts 50% stronger. Night storm: only the headlight cone.
func _check_storm_modifiers() -> void:
	var record: Dictionary = data.record("bosses", STORM)
	var listed: Array = GameData.as_array(record.get("modifiers"))
	check(listed.size() == 2 and listed.has("crosswind") and listed.has("night_storm"), "GDD 10.3: the Storm's modifiers are Crosswind and Night storm")
	check_near(GameData.as_float(data.record("boss_modifiers", "crosswind").get("gust_mult")), 1.5, 0.000001, "Crosswind: gusts 50% stronger")
	_check_storm_gusts("crosswind")
	# Crosswind changes the gusts and nothing else.
	var plain: Dictionary = BossSim.plan(data, STORM, "", 4)
	var windy: Dictionary = BossSim.plan(data, STORM, "crosswind", 4)
	check_near(GameData.as_float(windy.get("gust_push")), GameData.as_float(plain.get("gust_push")) * 1.5, 0.000001, "(the plan carries the stronger push)")
	check_eq(JSON.stringify(windy.get("gusts")), JSON.stringify(plain.get("gusts")), "(the same gusts in the same places)")
	check_eq(GameData.as_string(windy.get("condition")), "clear", "(by day)")

	# Night storm: it is night, and he sees no further than his headlights.
	var storm: Dictionary = _storm()
	var thin_m: float = GameData.as_float(storm.get("thin_m"))
	var thick_m: float = GameData.as_float(storm.get("thick_m"))
	_begin_quiet_boss(STORM, "night_storm")
	check_eq(_sim.boss.modifier, "night_storm", "(Night storm)")
	check(_sim.leg.night, "Night storm: the Storm is driven in the dark")
	check(GameData.as_bool(_sim.snapshot()["night"]), "(the snapshot says night: the view is the headlight cone)")
	var cone: float = _sim.headlight_cone()
	check_near(_sim.visibility(), minf(thin_m, cone), 0.000001, "in thin dust he sees the nearer of the dust and his headlights")
	# A dead headlight halves the cone: now the cone is the nearer.
	_sim.faults.active.append(DriveSim.FAULT_HEADLIGHT)
	var dim: float = _sim.headlight_cone()
	check(dim < thin_m and dim > thick_m, "(a dead headlight: a cone of %d m, between thick and thin)" % roundi(dim))
	check_near(_sim.visibility(), dim, 0.000001, "with one headlight he sees only as far as its cone, thin dust or not")
	_ticks(_ticks_in(GameData.as_float(storm.get("thin_s")) + 1.0))
	check_near(_sim.visibility(), thick_m, 0.000001, "and thick dust is nearer still")
	# By day the same fault changes nothing.
	_begin_quiet_boss(STORM)
	check(not _sim.leg.night, "(the plain Storm is by day)")
	_sim.faults.active.append(DriveSim.FAULT_HEADLIGHT)
	check_near(_sim.visibility(), thin_m, 0.000001, "by day a dead headlight does not shorten his view")
	# The gusts of a Night storm are the plain Storm's.
	check_near(GameData.as_float(BossSim.plan(data, STORM, "night_storm", 4).get("gust_push")), GameData.as_float(plain.get("gust_push")), 0.000001,
			"(a Night storm's gusts are no stronger)")
	# A modifier of another boss is not the Storm's.
	check_eq(GameData.as_string(BossSim.plan(data, STORM, "long_queue", 4).get("boss_modifier")), "", "another boss's modifier does nothing to the Storm")

	# Which Telling has which: by the seed, in boss_modifier_chance of them.
	var share: float = tuning.fi("boss_modifier_chance", 1)
	var counts: Dictionary = {"": 0, "crosswind": 0, "night_storm": 0}
	var tellings: int = 600
	for seed_value: int in range(1, tellings + 1):
		var drawn: String = RunGenerator.boss_modifier(data, seed_value, 2)
		check(counts.has(drawn), "a Storm has one of its own modifiers or none (seed %d: '%s')" % [seed_value, drawn])
		counts[drawn] = GameData.as_int(counts.get(drawn)) + 1
		check_eq(RunGenerator.boss_modifier(data, seed_value, 2), drawn, "(the same seed, the same modifier)")
	var modified: int = GameData.as_int(counts["crosswind"]) + GameData.as_int(counts["night_storm"])
	var spread: float = sqrt(float(tellings) * share * (1.0 - share))
	check(absf(float(modified) - float(tellings) * share) <= 4.0 * spread, "the Storm has a modifier in boss_modifier_chance of Tellings (%d of %d)" % [modified, tellings])
	check(absf(float(GameData.as_int(counts["crosswind"])) - float(modified) * 0.5) <= 4.0 * sqrt(float(modified) * 0.25),
			"Crosswind as often as Night storm (%d and %d)" % [GameData.as_int(counts["crosswind"]), GameData.as_int(counts["night_storm"])])


## In thick dust he follows tail lights: the plan always has some ahead.
func _check_storm_tail_lights() -> void:
	var lights: Dictionary = GameData.as_dict(_storm().get("tail_lights"))
	var gaps: Array = GameData.as_array(lights.get("gap_m"))
	var speeds: Array = GameData.as_array(lights.get("speed_kmh"))
	var types: Array = GameData.as_array(lights.get("vehicles"))
	for seed_value: int in [1, 2, 3]:
		var plan: Dictionary = BossSim.plan(data, STORM, "", seed_value)
		var spawns: Array = GameData.as_array(plan.get("spawns"))
		var length: float = GameData.as_float(plan.get("length"))
		check(spawns.size() >= int(floorf(length / GameData.as_float(gaps[1]))) - 1, "seed %d: there are tail lights all along the Storm (%d vehicles)" % [seed_value, spawns.size()])
		var last_at: float = -INF
		var last_lane: int = -1
		for entry: Variant in spawns:
			var spawn: Dictionary = GameData.as_dict(entry)
			var at: float = GameData.as_float(spawn.get("trigger_s")) + GameData.as_float(spawn.get("ahead"))
			var lane: int = GameData.as_int(spawn.get("lane"))
			var speed: float = GameData.as_float(spawn.get("speed"))
			check(types.has(GameData.as_string(spawn.get("vehicle"))), "(a vehicle of the Storm's list)")
			check(speed >= GameData.as_float(speeds[0]) - 0.05 and speed <= GameData.as_float(speeds[1]) + 0.05, "(slower than he is in third: %.1f km/h)" % speed)
			check(lane >= 0 and lane < GameData.as_int(plan.get("lanes")), "(in a lane)")
			check(lane != last_lane, "seed %d: no two in a row are in one lane: there is always a way past" % seed_value)
			if last_at > -INF:
				check(at - last_at >= GameData.as_float(gaps[0]) - 0.02 and at - last_at <= GameData.as_float(gaps[1]) + 0.02, "(the next is %d m on)" % roundi(at - last_at))
			last_at = at
			last_lane = lane
		check(last_at > length - GameData.as_float(gaps[1]) - 0.02, "seed %d: the last is near the end" % seed_value)
	# On the road they are there to be seen and followed: lit vehicles ahead, going his way.
	_sim = DriveSim.new(fresh_data())
	_events = []
	_sim.gate.reset(2)
	_sim.begin_boss(STORM, "", 1)
	check_eq(GameData.as_string(_event_of(_sim.drain_events(), "boss_started").get("boss")), STORM, "(begin_boss announces the Storm)")
	_input.clear()
	var seen_ahead: int = 0
	for _index: int in _ticks_in(20.0):
		# Kept on the shoulder side of the right lane's middle, clear of nobody: just looking.
		_sim.car.x = _sim.car.road_right() + 1.5
		_sim.step(_input)
		for vehicle: TrafficSim.Vehicle in _sim.traffic.vehicles:
			if vehicle.direction > 0 and vehicle.s > _sim.car.s:
				seen_ahead += 1
	check(seen_ahead > 0, "driving in, there are vehicles ahead of him going his way")


## The Storm ends Act 2 of a Telling, with the modifier its seed draws.
func _check_storm_in_a_telling() -> void:
	var wanted: Array[String] = ["", "crosswind", "night_storm"]
	for want: String in wanted:
		var telling_seed: int = 0
		for candidate: int in range(1, 400):
			if RunGenerator.boss_modifier(data, candidate, 2) == want:
				telling_seed = candidate
				break
		check(telling_seed > 0, "(a seed whose Storm has '%s')" % want)
		_sim = DriveSim.new(fresh_data())
		_events = []
		_input.clear()
		_sim.begin_telling(TABLE, telling_seed)
		_drive_on_to_act(2)
		var guard: int = 40000
		while _sim.run.stage != RunState.Stage.BOSS and guard > 0:
			guard -= 1
			if _sim.stopped:
				_leave_stop()
				continue
			_sim.car.x = _sim.car.lane_center(1)
			if _sim.leg.active and _sim.car.s < _sim.leg.length - 2.0:
				_sim.car.s = _sim.leg.length - 1.0
			_sim.step(_input)
		for event: Dictionary in _sim.drain_events():
			_events.append(event)
		var started: Dictionary = _event("boss_started")
		check_eq(GameData.as_string(started.get("boss")), STORM, "the third leg of Act 2 leads into the Storm")
		check_eq(GameData.as_string(started.get("modifier")), want, "with the modifier its seed draws ('%s')" % want)
		check_eq(_sim.boss.kind, STORM, "(he is in it)")
		check_eq(_sim.boss.modifier, want, "(so modified)")
		check_near(_sim.leg.length, GameData.as_float(data.record("bosses", STORM).get("length_m")), 0.000001, "(2,000 m of it)")
		check_near(_sim.heavy_floor(), tuning.fi("heavy_floor", 1), 0.000001, "GDD 6.1: the Storm's Heavy floor is Act 2's")
		check_eq(_sim.leg.night, want == "night_storm", "(night only in a Night storm)")
		# To its end: the boss stop, where the game saves.
		var saves: int = _sim.checkpoints
		guard = 40000
		while not _sim.stopped and guard > 0:
			guard -= 1
			_sim.car.x = _sim.car.lane_center(1)
			if _sim.car.s < _sim.leg.length - 2.0:
				_sim.car.s = _sim.leg.length - 1.0
			_sim.step(_input)
		for event: Dictionary in _sim.drain_events():
			_events.append(event)
		check_eq(GameData.as_string(_event("boss_ended").get("boss")), STORM, "the Storm ends")
		check_eq(_sim.run.stage, RunState.Stage.BOSS_STOP, "at the boss stop")
		check_eq(_sim.checkpoints, saves + 1, "where the game saves")
		check(not _sim.boss.active and is_inf(_sim.visibility()), "(the dust is behind him)")
		check_near(_sim.items.wipe_haze, 0.0, 0.000001, "(and his wipers smear nothing any more)")


# --- T-BOSS-03: Dawn and the Arrival (GDD 10.4, 10.5) --------------------------

func _dawn() -> Dictionary:
	return GameData.as_dict(data.record("bosses", DAWN).get("dawn"))


func _street() -> Dictionary:
	return GameData.as_dict(data.root("legs").get("arrival"))


func test_boss_03() -> void:
	_check_dawn_phases()
	_check_dawn_traffic_builds()
	_check_dawn_glare()
	_check_where_the_sun_stands()
	_check_last_checkpoint()
	_check_call_rings()
	_check_dawn_modifiers()
	_check_arrival()
	_check_dawn_in_a_telling()


## False dawn, sunrise, the Call: by where he is along the 3,333 m.
func _check_dawn_phases() -> void:
	var record: Dictionary = data.record("bosses", DAWN)
	var dawn: Dictionary = _dawn()
	var length: float = GameData.as_float(record.get("length_m"))
	var sunrise: float = GameData.as_float(dawn.get("sunrise_at_m"))
	var ramp: float = GameData.as_float(dawn.get("glare_ramp_m"))
	var call_at: float = length - GameData.as_float(GameData.as_dict(dawn.get("call")).get("from_end_m"))
	check_eq(GameData.as_int(record.get("act")), 3, "GDD 10.4: Dawn ends Act 3")
	check_near(GameData.as_float(record.get("par_s")), 120.0, 0.000001, "about 120 s")
	check_near(length / (tuning.fi("gear_speeds", 2) * KMH_TO_MS), 120.0, 0.05, "(which is its length in third gear)")
	check_near(GameData.as_float(dawn.get("heavy_floor")), 0.0, 0.000001, "GDD 6.1: Dawn's Heavy floor is 0")
	check(tuning.fi("heavy_floor", 2) > 0.0, "(Act 3's is not)")

	var plan: Dictionary = _begin_quiet_boss(DAWN)
	check_near(GameData.as_float(plan.get("length")), length, 0.000001, "Dawn's road is as long as its record says")
	_tick()
	var shot: Dictionary = _sim.snapshot()
	check_eq(GameData.as_string(shot["boss"]), DAWN, "he is in Dawn")
	check_near(_sim.heavy_floor(), 0.0, 0.000001, "in Dawn he is never Heavy, though it is Act 3")
	check_eq(GameData.as_int(shot["act"]), 3, "(Act 3)")
	check_eq(GameData.as_int(shot["dawn_phase"]), BossSim.FALSE_DAWN, "it begins with the false dawn")
	check_near(GameData.as_float(shot["glow"]), 1.0, 0.000001, "an orange glow fills the horizon")
	check(GameData.as_float(shot["glow_side"]) > 0.0, "on the right")
	check_near(_sim.glare(), 0.0, 0.000001, "and nothing blinds him yet")
	check_eq(GameData.as_string(shot["call"]), BossSim.CALL_NONE, "(his phone is quiet)")
	# Up to the sunrise.
	_sim.car.s = sunrise - 2.0
	_tick()
	check_eq(_sim.boss.phase, BossSim.FALSE_DAWN, "false dawn lasts to %d m" % roundi(sunrise))
	check_near(_sim.glare(), 0.0, 0.000001, "(still no Glare)")
	_sim.car.s = sunrise + ramp * 0.5
	_tick()
	shot = _sim.snapshot()
	check_eq(GameData.as_int(shot["dawn_phase"]), BossSim.SUNRISE, "then the real sun rises")
	check(_sim.glare() > 0.0 and _sim.glare() < GameData.as_float(dawn.get("glare")), "it is seen before it blinds: half way up it is %.2f" % _sim.glare())
	check(GameData.as_float(shot["sun_side"]) < 0.0 and GameData.as_float(shot["sun_side"]) > -1.0, "ahead and to the left")
	check(GameData.as_float(shot["glow_side"]) > 0.0, "(the false dawn still glows on the right)")
	_sim.car.s = sunrise + ramp + 1.0
	_tick()
	check_near(_sim.glare(), 0.6, 0.000001, "GDD 10.4: Glare 60%")
	check_near(_sim.glare(), GameData.as_float(dawn.get("glare")), 0.000001, "(as its record says)")
	# To the Call.
	_sim.car.s = call_at - 2.0
	_tick()
	check_eq(_sim.boss.phase, BossSim.SUNRISE, "the sunrise lasts until 833 m from the end")
	check_eq(_sim.boss.call, BossSim.CALL_NONE, "(no call yet)")
	_ticks(12)
	check_eq(_sim.boss.phase, BossSim.THE_CALL, "where the Call begins")
	check_near(_sim.glare(), GameData.as_float(dawn.get("glare")), 0.000001, "(the sun is still in his eyes)")
	check_near(_sim.heavy_floor(), 0.0, 0.000001, "(and the floor is still 0)")


## Rush traffic builds: thin at the start, whole at sunrise.
func _check_dawn_traffic_builds() -> void:
	var dawn: Dictionary = _dawn()
	var road: Dictionary = GameData.as_dict(dawn.get("road"))
	var sunrise: float = GameData.as_float(dawn.get("sunrise_at_m"))
	var rush: Dictionary = data.record("legs", "rush")
	check_eq(JSON.stringify(road.get("beat_weights")), JSON.stringify(rush.get("beat_weights")), "Dawn's road is laid out as a Rush leg is")
	var per_km: float = GameData.as_float(road.get("density")) + tuning.f("traffic_per_act") * 2.0
	check_near(per_km, GameData.as_float(rush.get("density")), 0.000001, "and carries heavy traffic: 16 vehicles per km")
	var from: float = GameData.as_float(road.get("builds_from"))
	check(from > 0.0 and from < 0.5, "it builds from a quarter of that")

	# Where the vehicles of thirty Dawns are met.
	var seeds: int = 30
	var early: float = 0.0
	var later: float = 0.0
	var after: float = 0.0
	var late_from: float = sunrise
	var late_to: float = sunrise + 500.0
	for seed_value: int in range(1, seeds + 1):
		var plan: Dictionary = BossSim.plan(data, DAWN, "", seed_value)
		check(not GameData.as_bool(plan.get("sparse")), "(seed %d: the road carries its traffic)" % seed_value)
		for entry: Variant in GameData.as_array(plan.get("spawns")):
			var at: float = _met_at(GameData.as_dict(entry))
			if at < sunrise * 0.5:
				early += 1.0
			elif at < sunrise:
				later += 1.0
			elif at >= late_from and at < late_to:
				after += 1.0
	early /= float(seeds) * sunrise * 0.5 / 1000.0
	later /= float(seeds) * sunrise * 0.5 / 1000.0
	after /= float(seeds) * (late_to - late_from) / 1000.0
	check(early < later and later < after, "traffic builds through the false dawn: %.1f, then %.1f, then %.1f vehicles per km" % [early, later, after])
	check(early < after * 0.6, "it begins well under what it becomes")
	check(early > 0.0, "(but the road is not empty)")
	check(later > after * 0.5, "and through the second half of the false dawn more than half of it is there (%.1f of %.1f per km)" % [later, after])
	check(absf(after - per_km) < per_km * 0.35, "after sunrise it is the rush's: about %d per km (%.1f)" % [roundi(per_km), after])
	check_eq(JSON.stringify(BossSim.plan(data, DAWN, "", 5)), JSON.stringify(BossSim.plan(data, DAWN, "", 5)), "the same seed gives the same Dawn")
	check(JSON.stringify(BossSim.plan(data, DAWN, "", 5)) != JSON.stringify(BossSim.plan(data, DAWN, "", 6)), "another seed another")
	# Between the last checkpoint's barriers nobody is beside him: the plan
	# has him meet no vehicle there, as it has him meet them just before.
	var barriers: Dictionary = GameData.as_dict(dawn.get("checkpoint"))
	var closed_from: float = GameData.as_float(barriers.get("at_m")) - GameData.as_float(barriers.get("taper_m"))
	var closed_to: float = GameData.as_float(barriers.get("at_m")) + GameData.as_float(barriers.get("length_m"))
	var met_between: int = 0
	var met_before: int = 0
	for seed_value: int in range(1, seeds + 1):
		for entry: Variant in GameData.as_array(BossSim.plan(data, DAWN, "", seed_value).get("spawns")):
			var met: float = GameData.as_float(GameData.as_dict(entry).get("meet_s"), -1.0)
			if GameData.as_int(GameData.as_dict(entry).get("direction")) < 0 or met < 0.0:
				continue
			if met >= closed_from and met <= closed_to:
				met_between += 1
			elif met >= closed_from - (closed_to - closed_from) and met < closed_from:
				met_before += 1
	check_eq(met_between, 0, "between the last checkpoint's barriers he meets no vehicle, in any of %d Dawns" % seeds)
	check(met_before > seeds, "(on as long a stretch before them he meets %d)" % met_before)
	# Nor is one beside him there: a vehicle slower than par is beside him
	# from gen_block_margin before its bumper to as far behind it, and no
	# such stretch reaches in between the barriers (he slows down there, and
	# what the plan timed at par must not be near).
	var par_kmh: float = tuning.fi("gear_speeds", 2)
	var beside: int = 0
	var slower: int = 0
	for seed_value: int in range(1, 21):
		for modifier: String in ["", "market_day"]:
			for entry: Variant in GameData.as_array(BossSim.plan(data, DAWN, modifier, seed_value).get("spawns")):
				var spawn: Dictionary = GameData.as_dict(entry)
				var met: float = GameData.as_float(spawn.get("meet_s"), -1.0)
				var speed: float = GameData.as_float(spawn.get("speed"))
				if GameData.as_int(spawn.get("direction")) < 0 or met < 0.0 or speed >= par_kmh:
					continue
				slower += 1
				var reach: float = GameData.as_float(data.record("vehicles", GameData.as_string(spawn.get("vehicle"))).get("length")) * 0.5 \
						+ tuning.f("car_length") * 0.5 + tuning.f("gen_block_margin")
				var along: float = reach / (1.0 - speed / par_kmh)
				if met + along > closed_from and met - along < closed_to:
					beside += 1
	check_eq(beside, 0, "and none of the %d slower vehicles of forty Dawns is beside him between the barriers" % slower)
	# The line the generator found through it still meets nothing (GDD 9.2, rule 3).
	var checker: LegChecker = LegChecker.new(data)
	for seed_value: int in [1, 2, 3]:
		var plan: Dictionary = BossSim.plan(data, DAWN, "", seed_value)
		var problems: PackedStringArray = checker.drive(plan, DT)
		check(problems.is_empty(), "seed %d: driven at par, the plan's line through Dawn meets nothing%s" % [seed_value, "" if problems.is_empty() else ": " + problems[0]])


## Where along the road a planned vehicle is met (or stands, if it never is).
func _met_at(spawn: Dictionary) -> float:
	var met: float = GameData.as_float(spawn.get("meet_s"))
	if met >= 0.0:
		return met
	return GameData.as_float(spawn.get("trigger_s")) + GameData.as_float(spawn.get("ahead"))


## The sun has one place, said by the simulation, for the disc in the sky
## and for the light on the glass: ahead and to the left, climbing as its
## Glare comes on to where the lowered visor covers it (D-053).
func _check_where_the_sun_stands() -> void:
	var dawn: Dictionary = _dawn()
	var sunrise: float = GameData.as_float(dawn.get("sunrise_at_m"))
	var ramp: float = GameData.as_float(dawn.get("glare_ramp_m"))
	var side: float = GameData.as_float(dawn.get("sun_side")) * tuning.fi("sun_position", 0)
	var low: float = tuning.f("sun_rise_from")
	var high: float = tuning.fi("sun_position", 1)
	check(side < 0.0 and high > low, "(the data put the sun to the left, and higher risen than rising)")

	_begin_quiet_boss(DAWN)
	_sim.car.s = sunrise - 2.0
	_tick()
	check(_sim.snapshot()["glare_position"] == null, "before the sunrise the snapshot names no place for a sun")
	_sim.car.s = sunrise + ramp * 0.5
	_tick()
	var at: Variant = _sim.snapshot()["glare_position"]
	check(at is Vector2, "as it rises the snapshot says where it stands")
	if at is Vector2:
		var half: Vector2 = at
		check_near(half.x, side, 0.000001, "to the left, as far as its record and tuning say (%.1f degrees)" % half.x)
		check(half.y > low and half.y < high, "half way up its Glare it is between the horizon and its place (%.1f degrees)" % half.y)
		check_near(half.y, lerpf(low, high, _sim.boss.glare / GameData.as_float(dawn.get("glare"))), 0.000001, "(as high as its Glare has come on)")
	_sim.car.s = sunrise + ramp + 1.0
	_tick()
	at = _sim.snapshot()["glare_position"]
	check(at is Vector2 and (at as Vector2).is_equal_approx(Vector2(side, high)), "risen, it stands at its place: %s" % str(at))
	# The visor takes the Glare, not the sun: it is still where it was.
	_reach("visor")
	_flick(Vector2(0.0, tuning.f("flick_min_distance") * 1.5))
	check_near(_sim.glare(), 0.0, 0.000001, "(the visor is down: no Glare)")
	at = _sim.snapshot()["glare_position"]
	check(at is Vector2 and (at as Vector2).is_equal_approx(Vector2(side, high)), "behind the lowered visor the sun stands where it stood")
	# No sun on another road.
	_begin_quiet_boss(STORM)
	_tick()
	check(_sim.snapshot()["glare_position"] == null, "and no road but Dawn's has one")


## Glare 60%, blocked for 3 s by flipping the visor.
func _check_dawn_glare() -> void:
	var dawn: Dictionary = _dawn()
	var full: float = GameData.as_float(dawn.get("glare"))
	var sunrise: float = GameData.as_float(dawn.get("sunrise_at_m"))
	var visor_time: float = tuning.f("visor_time")
	check_near(visor_time, 3.0, 0.000001, "GDD 10.4: the visor blocks the sun for 3 s")

	_begin_quiet_boss(DAWN)
	_sim.car.s = sunrise + GameData.as_float(dawn.get("glare_ramp_m")) + 1.0
	_tick()
	check_near(GameData.as_float(_sim.snapshot()["glare"]), full, 0.000001, "the snapshot carries the Glare")
	check_near(GameData.as_float(_sim.snapshot()["sun"]), full, 0.000001, "(and the sun behind it)")
	# The visor, through the hand: a FLICK down.
	_reach("visor")
	var nerves_before: float = _sim.nerves.value
	_events = []
	_input.pointer_is_absolute = false
	_input.lmb = true
	_input.pointer_delta = Vector2(0.0, tuning.f("flick_min_distance") * 1.5 / 10.0)
	var blocked: int = 0
	var flicked_at: int = -1
	for index: int in _ticks_in(visor_time + 2.0):
		if index == 10:
			_input.clear()
		_tick()
		if flicked_at < 0 and _count_events("ritual_completed", "ritual", "visor_photo") > 0:
			flicked_at = index
		if _sim.glare() == 0.0:
			blocked += 1
			check(GameData.as_bool(_sim.snapshot()["visor_down"]), "(the visor is down)")
			check_near(GameData.as_float(_sim.snapshot()["sun"]), full, 0.000001, "(the sun is still there behind it)")
	check(flicked_at >= 0, "(the visor is flipped down through the hand)")
	check(absi(blocked - _ticks_in(visor_time)) <= 1, "flipping the visor blocks the sun for 3 s (%d ticks)" % blocked)
	check_near(_sim.glare(), full, 0.000001, "and then it is back")
	check(_sim.nerves.value - nerves_before < tuning.f("visor_nerves") * 0.5, "it is the visor of the photo: looking at it calmed him (%.1f)" % (_sim.nerves.value - nerves_before))
	# Before sunrise there is nothing for it to block.
	_begin_quiet_boss(DAWN)
	_tick()
	check_near(_sim.glare(), 0.0, 0.000001, "(in the false dawn there is no Glare to block)")
	# What he wears against Glare works on the sun too.
	_begin_quiet_boss(DAWN)
	_give("sunglasses")
	_sim.car.s = sunrise + GameData.as_float(dawn.get("glare_ramp_m")) + 1.0
	_tick()
	var worn: float = _sim.items.passive("glare_mult")
	check(worn < 1.0, "(sunglasses cut Glare)")
	check_near(_sim.glare(), full * worn, 0.000001, "sunglasses cut the sun's Glare as they cut any")
	# A spotlight is not the sun: the visor does not block it (GDD 4.6).
	_new_sim()
	_sim.encounter.glare = 0.8
	check_near(_sim.glare(), 0.8, 0.000001, "(a spotlight on his windscreen)")
	_sim.effects.add(ItemSim.VISOR_DOWN, visor_time)
	check_near(_sim.glare(), 0.8, 0.000001, "the visor blocks sun glare, not the motorcade's spotlight")


## A last checkpoint waves him through at 70 km/h between barriers.
func _check_last_checkpoint() -> void:
	var check_data: Dictionary = GameData.as_dict(_dawn().get("checkpoint"))
	var at: float = GameData.as_float(check_data.get("at_m"))
	var corridor_length: float = GameData.as_float(check_data.get("length_m"))
	var taper: float = GameData.as_float(check_data.get("taper_m"))
	var gap: float = GameData.as_float(check_data.get("gap_m"))
	var limit: float = GameData.as_float(check_data.get("max_kmh"))
	var minutes: float = GameData.as_float(check_data.get("search_minutes"))
	var half_width: float = tuning.f("car_width") * 0.5
	check_near(limit, 70.0, 0.000001, "GDD 10.4: the last checkpoint waves him through at 70 km/h")
	check_near(gap, 2.34, 0.000001, "GDD 10.2: the barriers are 2.34 m apart")
	check_near(gap, tuning.f("car_width") * 1.3, 0.000001, "(1.3 car widths)")
	check_near(minutes, 15.0, 0.000001, "GDD 10.2: a search is 15 game minutes")

	# It is signed before its barriers begin.
	_begin_quiet_boss(DAWN)
	var sign_at: float = at - taper - GameData.as_float(check_data.get("sign_lead_s")) * tuning.fi("gear_speeds", 2) * KMH_TO_MS
	_sim.car.s = sign_at - 100.0
	_tick()
	var sign: Dictionary = _sign("checkpoint")
	check(not sign.is_empty(), "the checkpoint is signed ahead of its barriers")
	check_near(GameData.as_float(sign.get("limit")), limit, 0.000001, "the sign says 70")
	check_near(GameData.as_float(sign.get("ahead")), 100.0, 1.0, "(it stands sign_lead_s short of them at par)")
	var barriers: Vector3 = _sim.snapshot()["corridor"]
	check_eq(barriers, Vector3(at - taper, at, at + corridor_length), "the snapshot says where the barriers are")
	check_near(GameData.as_float(_sim.snapshot()["corridor_gap"]), gap, 0.000001, "(and how far apart)")

	# Through it at 70 km/h, in each lane's corridor: nothing touches him.
	for lane: int in 3:
		_begin_quiet_boss(DAWN)
		_cruise(2, lane)
		_sim.car.s = at - taper - 30.0
		_events = []
		var middle: float = _sim.car.lane_center(lane)
		var walls_seen: bool = false
		var guard: int = _ticks_in(40.0)
		while _sim.car.s < at + corridor_length + 20.0 and guard > 0:
			guard -= 1
			_tick()
			if _sim.car.s >= at + 1.0 and _sim.car.s <= at + corridor_length - 1.0:
				walls_seen = true
				check_near(_sim.car.wall_left, middle - gap * 0.5, 0.000001, "lane %d: a barrier 1.17 m to his left" % lane)
				check_near(_sim.car.wall_right, middle + gap * 0.5, 0.000001, "lane %d: and one 1.17 m to his right" % lane)
		check(walls_seen, "(lane %d has a corridor)" % lane)
		check_near(_sim.car.speed, limit, 0.000001, "(second gear is 70 km/h)")
		check_eq(_count_events("hit"), 0, "lane %d: at 70 km/h in the middle of the corridor nothing touches him" % lane)
		check_eq(_count_events("pulled_over"), 0, "lane %d: and he is waved through" % lane)
		check(is_inf(_sim.car.wall_right) and is_inf(_sim.car.wall_left), "(past the checkpoint the road is open again)")

	# The barriers close in over the taper, from the lane's own lines.
	_begin_quiet_boss(DAWN)
	check_eq(_sim.boss.walls(at - taper - 1.0, _sim.car.lane_center(1)), Vector2(-INF, INF), "before the taper there are no barriers")
	var lane_half: float = tuning.f("lane_width") * 0.5
	check_eq(_sim.boss.walls(at - taper, _sim.car.lane_center(1)), Vector2(_sim.car.lane_center(1) - lane_half, _sim.car.lane_center(1) + lane_half), "they begin at the lane's lines")
	var half_way: Vector2 = _sim.boss.walls(at - taper * 0.5, _sim.car.lane_center(1))
	check_near(half_way.y - half_way.x, (tuning.f("lane_width") + gap) * 0.5, 0.000001, "and close in evenly")
	check_eq(_sim.boss.walls(at + corridor_length + 1.0, _sim.car.lane_center(1)), Vector2(-INF, INF), "after the corridor there are none")

	# Touching a barrier is a scrape, and it does not let him through.
	for side: int in [-1, 1]:
		_begin_quiet_boss(DAWN)
		_cruise(2, 1)
		_sim.car.s = at + 20.0
		_keep_lane = false
		_events = []
		var middle: float = _sim.car.lane_center(1)
		_sim.car.x = middle + float(side) * (gap * 0.5 - half_width + 0.05)
		var lamps: int = _sim.faults.lamps
		_tick()
		var hit: Dictionary = _event("hit")
		check_eq(GameData.as_int(hit.get("kind")), Collision.Hit.SCRAPE, "touching the %s barrier is a scrape" % ("left" if side < 0 else "right"))
		check_eq(_sim.faults.lamps, lamps + int(tuning.fi("hit_lamps", 0)), "(a lamp)")
		check(absf(_sim.car.x - middle) <= gap * 0.5 - half_width + 0.000001, "he is put back between the barriers (%.3f m off the middle)" % (_sim.car.x - middle))
		check_near(_sim.car.x, middle, 0.02, "at most to the middle of the corridor, not into the other barrier")
		_ticks(_ticks_in(1.0))
		check_eq(_count_events("hit"), 1, "(one touch, one scrape)")
		check_eq(_sim.car.lane_of(_sim.car.x), 1, "(still in his corridor)")

	# Faster than 70 at the barriers he is stopped and searched.
	for speed: float in [limit, limit + 1.0, 100.0]:
		_begin_quiet_boss(DAWN)
		_give("arak_flask", "cup_b")
		_give("forged_papers", "glovebox_a")
		# Second gear holds 70; in third the car is held just under each speed
		# (the tick itself adds a tenth of a km/h).
		_cruise(2 if speed <= limit else 3, 1)
		_sim.car.s = at - 3.0
		_events = []
		var clock_before: float = _sim.clock.minutes
		var ticks: int = 0
		while _sim.car.s < at + 1.0 and _event("pulled_over").is_empty() and ticks < 240:
			ticks += 1
			if speed > limit:
				_sim.car.speed = speed - tuning.f("accel") * DT
			_tick()
		var verdict: Dictionary = _event("pulled_over")
		if speed <= limit:
			check(verdict.is_empty(), "at exactly 70 km/h he is waved through")
			check(_item("arak_flask") != null, "(and keeps what he has)")
			check_near(_sim.clock.minutes - clock_before, float(ticks) * DT * tuning.f("clock_scale") / 60.0, 0.000001, "(the Clock only runs)")
			continue
		check_eq(GameData.as_string(verdict.get("paid")), "search", "at %d km/h he is stopped and searched" % roundi(speed))
		check_near(GameData.as_float(verdict.get("minutes")), minutes, 0.000001, "which costs 15 game minutes")
		check_near(_sim.clock.minutes - clock_before, minutes + float(ticks) * DT * tuning.f("clock_scale") / 60.0, 0.000001, "on the Clock, at once")
		check_near(_sim.car.speed, 0.0, 0.000001, "the car is stopped")
		check(_item("arak_flask") == null, "contraband in view is taken")
		check(GameData.as_array(verdict.get("taken")).has("arak_flask"), "(the event names it)")
		check(_item("forged_papers") == null, "and so is what is stowed: a search finds everything (GDD 10.2, D-048)")
		# Once: he drives on, and nothing more happens to him there.
		_events = []
		_run(3.0)
		check_eq(_count_events("pulled_over"), 0, "(searched once, he drives on)")
		check(_sim.car.speed > 0.0, "(the car moves again)")


## The Call starts 833 m from the end and rings for 8 s.
func _check_call_rings() -> void:
	var record: Dictionary = data.record("bosses", DAWN)
	var ring: Dictionary = GameData.as_dict(_dawn().get("call"))
	var from_end: float = GameData.as_float(ring.get("from_end_m"))
	var ring_s: float = GameData.as_float(ring.get("ring_s"))
	var call_at: float = GameData.as_float(record.get("length_m")) - from_end
	check_near(from_end, 833.0, 0.000001, "GDD 10.4: the Call comes 833 m from the end")
	check_near(ring_s, 8.0, 0.000001, "and rings for 8 s")

	_begin_quiet_boss(DAWN)
	_sim.car.s = call_at - 10.0
	_events = []
	check(not _sim.hand.is_anchor_active(_sim.hand.anchor_index(&"pocket")), "before it rings there is nothing to do at his pocket")
	var guard: int = _ticks_in(5.0)
	while _event("call_started").is_empty() and guard > 0:
		guard -= 1
		_tick()
	check(not _event("call_started").is_empty(), "the phone in his pocket rings")
	check(_sim.car.s >= call_at and _sim.car.s < call_at + 0.5, "at 833 m from the end (%.2f m)" % (GameData.as_float(record.get("length_m")) - _sim.car.s))
	check_eq(GameData.as_string(_event("call_started").get("caller")), "noor", "it is Noor")
	check_eq(_count_events("sfx_requested", "id", "phone_ring"), 1, "(it is heard)")
	check_eq(_count_events("line_requested", "id", "call.noor.rings"), 1, "(and written out: his pocket is out of his sight)")
	check(data.has_line("call.noor.rings"), "(a line that exists)")
	var shot: Dictionary = _sim.snapshot()
	check_eq(GameData.as_string(shot["caller"]), "noor", "(the snapshot says who)")
	check_eq(GameData.as_string(shot["call"]), BossSim.CALL_RINGING, "(and that it rings)")
	check_near(GameData.as_float(shot["ring_left"]), ring_s, 0.000001, "(for 8 s)")
	check(_sim.hand.is_anchor_active(_sim.hand.anchor_index(&"pocket")), "while it rings his pocket is something to reach for")
	check(_sim.effects.has(DriveSim.THE_CALL), "(the status the pocket's rituals ask for)")
	# It rings for 8 s, to the tick.
	var rang: int = 0
	guard = _ticks_in(ring_s + 2.0)
	while _sim.boss.call == BossSim.CALL_RINGING and guard > 0:
		guard -= 1
		rang += 1
		_tick()
	check_eq(rang, _ticks_in(ring_s), "it rings for 8 s")
	check_eq(_count_events("call_started"), 1, "(once)")
	check_eq(_sim.boss.call, BossSim.CALL_OVER, "then it is over")
	check(not _sim.hand.is_anchor_active(_sim.hand.anchor_index(&"pocket")), "and his pocket is quiet again")
	_run(3.0)
	check_eq(_count_events("call_started"), 1, "it does not ring a second time")


## Market day: traffic +30%. Early sun: Glare from phase 1.
func _check_dawn_modifiers() -> void:
	var listed: Array = GameData.as_array(data.record("bosses", DAWN).get("modifiers"))
	check(listed.size() == 2 and listed.has("market_day") and listed.has("early_sun"), "GDD 10.4: Dawn's modifiers are Market day and Early sun")
	check_near(GameData.as_float(data.record("boss_modifiers", "market_day").get("traffic_mult")), 1.3, 0.000001, "Market day: traffic +30%")
	check_eq(GameData.as_int(data.record("boss_modifiers", "early_sun").get("glare_from_phase")), BossSim.FALSE_DAWN, "Early sun: Glare from phase 1")

	var plain: float = 0.0
	var market: float = 0.0
	var seeds: int = 12
	for seed_value: int in range(1, seeds + 1):
		plain += float(GameData.as_array(BossSim.plan(data, DAWN, "", seed_value).get("spawns")).size())
		var busy: Dictionary = BossSim.plan(data, DAWN, "market_day", seed_value)
		market += float(GameData.as_array(busy.get("spawns")).size())
		check(not GameData.as_bool(busy.get("sparse")), "(seed %d: a Market day's road carries its traffic)" % seed_value)
		check_eq(GameData.as_string(busy.get("boss_modifier")), "market_day", "(the plan says Market day)")
	check_near(market / plain, 1.3, 0.05, "on a Market day the road carries 30%% more (%.1f against %.1f vehicles)" % [market / float(seeds), plain / float(seeds)])
	check(not BossSim.plan(data, DAWN, "market_day", 3).has("early_sun"), "(and the sun rises when it does)")

	var dawn: Dictionary = _dawn()
	var full: float = GameData.as_float(dawn.get("glare"))
	var ramp: float = GameData.as_float(dawn.get("glare_ramp_m"))
	_begin_quiet_boss(DAWN, "early_sun")
	check_eq(_sim.boss.modifier, "early_sun", "(Early sun)")
	_sim.car.s = ramp + 1.0
	_tick()
	check_eq(_sim.boss.phase, BossSim.FALSE_DAWN, "(in the false dawn)")
	check_near(_sim.glare(), full, 0.000001, "with Early sun the Glare is there from phase 1")
	_sim.car.s = GameData.as_float(dawn.get("sunrise_at_m")) + ramp + 1.0
	_tick()
	check_near(_sim.glare(), full, 0.000001, "and stays")
	check_eq(JSON.stringify(BossSim.plan(data, DAWN, "early_sun", 4).get("spawns")), JSON.stringify(BossSim.plan(data, DAWN, "", 4).get("spawns")),
			"(Early sun changes the light, not the traffic)")

	# Which Telling has which.
	var share: float = tuning.fi("boss_modifier_chance", 2)
	var counts: Dictionary = {"": 0, "market_day": 0, "early_sun": 0}
	var tellings: int = 600
	for seed_value: int in range(1, tellings + 1):
		var drawn: String = RunGenerator.boss_modifier(data, seed_value, 3)
		check(counts.has(drawn), "Dawn has one of its own modifiers or none (seed %d: '%s')" % [seed_value, drawn])
		counts[drawn] = GameData.as_int(counts.get(drawn)) + 1
	var modified: int = GameData.as_int(counts["market_day"]) + GameData.as_int(counts["early_sun"])
	check(absf(float(modified) - float(tellings) * share) <= 4.0 * sqrt(float(tellings) * share * (1.0 - share)),
			"Dawn has a modifier in boss_modifier_chance of Tellings (%d of %d)" % [modified, tellings])
	check(GameData.as_int(counts["market_day"]) > 0 and GameData.as_int(counts["early_sun"]) > 0, "(both come up)")


## The Arrival: he brakes to a stop in the marked bay and a TAP on the key
## reads the Clock.
func _check_arrival() -> void:
	var street: Dictionary = _street()
	var length: float = GameData.as_float(street.get("length_m"))
	var bay: float = GameData.as_float(street.get("bay_m"))
	var half_length: float = tuning.f("car_length") * 0.5
	var key_anchor: int = DriveSim.new(data).hand.anchor_index(&"key")
	check(key_anchor != HandSim.NO_ANCHOR, "GDD 10.5: there is a key to turn")
	check_eq(GameData.as_string(_ritual("key_turn").get("gesture")), "TAP", "with a TAP")

	# Rolling up the street in first gear and braking into the bay.
	_arrive_at_the_street()
	check_near(_sim.leg.length, length, 0.000001, "the road ends in a street")
	check_eq(_sim.boss.kind, BossSim.ARRIVAL, "(the Arrival)")
	check_near(_sim.heavy_floor(), GameData.as_float(street.get("heavy_floor")), 0.000001, "(it is dawn there too: the Heavy floor is 0)")
	var marked: Vector2 = _sim.snapshot()["bay"]
	check_eq(marked, Vector2(length - bay, length), "the bay is marked at its end")
	check(not _sim.hand.is_anchor_active(key_anchor), "rolling, the key is not for turning")
	# The brake goes on where the car will stop with its tail just in the bay.
	var speed_ms: float = _sim.car.speed * KMH_TO_MS
	var stopping: float = speed_ms * speed_ms / (2.0 * tuning.f("brake_decel") * KMH_TO_MS)
	var brake_at: float = length - bay + half_length + 1.0 - stopping
	while _sim.car.s < brake_at:
		_tick()
	check(not GameData.as_bool(_sim.snapshot()["in_bay"]), "(not yet in the bay)")
	_input.rmb = true
	var guard: int = _ticks_in(10.0)
	while _sim.car.speed > 0.0 and guard > 0:
		guard -= 1
		_tick()
	check(_sim.car.s - half_length >= length - bay and _sim.car.s + half_length <= length, "he brakes to a stop in the bay (%.2f m of the street)" % _sim.car.s)
	check_eq(_count_events("hit"), 0, "(touching nothing)")
	_tick()
	check(GameData.as_bool(_sim.snapshot()["in_bay"]), "the snapshot says he stands in it")
	check(_sim.hand.is_anchor_active(key_anchor), "and now the key can be turned")
	check_eq(_count_events("arrived"), 0, "stopping is not arriving: the Clock is not read yet")
	# He sits a moment. The Clock runs until the key is turned.
	var stopped_at: float = _sim.clock.minutes
	_run(5.0)
	_events = []
	_tap_at(KEY)
	var arrived: Dictionary = _event("arrived")
	check(not arrived.is_empty(), "a TAP on the key: he has arrived")
	check_eq(_count_events("ritual_completed", "ritual", "key_turn"), 1, "(the key is turned through the hand)")
	check(GameData.as_float(arrived.get("clock_minutes")) > stopped_at + 5.0 * tuning.f("clock_scale") / 60.0 - 0.001, "the Clock is read at that moment, not when he stopped")
	check(GameData.as_float(arrived.get("clock_minutes")) <= _sim.clock.minutes + 0.000001 and GameData.as_float(arrived.get("clock_minutes")) > _sim.clock.minutes - 0.05, "(%s)" % GameData.as_string(arrived.get("clock")))
	check_eq(GameData.as_bool(arrived.get("late")), _sim.clock.late(), "(and whether that is late)")
	check(not GameData.as_bool(arrived.get("call")), "(he did not answer the Call)")
	_events = []
	_tap_at(KEY)
	check_eq(_count_events("arrived"), 0, "he arrives once")

	# Stopped short of the bay, the key does nothing.
	_arrive_at_the_street()
	while _sim.car.s < length - bay - 20.0:
		_tick()
	_input.rmb = true
	guard = _ticks_in(10.0)
	while _sim.car.speed > 0.0 and guard > 0:
		guard -= 1
		_tick()
	_tick()
	check(_sim.car.s + half_length < length - bay, "(stopped short of the bay)")
	check(not _sim.hand.is_anchor_active(key_anchor), "short of the bay the key is not for turning")
	_events = []
	_sim.items.complete(_ritual("key_turn"), 0)
	_tick()
	check_eq(_count_events("arrived"), 0, "and turning it would not be arriving")
	# Half in the bay is not in it.
	_arrive_at_the_street()
	_sim.car.s = length - bay
	_sim.car.speed = 0.0
	_input.rmb = true
	_ticks(3)
	check(not _sim.boss.in_bay, "a car half in the bay is not in it")
	# Rolling through the bay is not standing in it.
	_arrive_at_the_street()
	_sim.car.s = length - bay + half_length + 0.5
	_ticks(2)
	check(_sim.car.speed > GameData.as_float(street.get("stopped_kmh")), "(rolling)")
	check(not _sim.boss.in_bay, "nor is a car that still rolls")

	# The street ends: who does not brake meets its end.
	_arrive_at_the_street()
	_sim.car.s = length - 30.0
	_events = []
	guard = _ticks_in(20.0)
	while _event("hit").is_empty() and guard > 0:
		guard -= 1
		_tick()
	var hit: Dictionary = _event("hit")
	check_eq(GameData.as_int(hit.get("kind")), Collision.Hit.CRASH, "into the end of the street in first gear is a crash")
	check_near(_sim.car.s + half_length, length, 0.000001, "the car stands at the street's end")
	check_near(_sim.car.speed, 0.0, 0.000001, "stopped")
	_ticks(_ticks_in(1.0))
	_input.rmb = true
	_tick()
	check(_sim.boss.in_bay, "which is in the bay: he can still turn the key")
	_events = []
	_tap_at(KEY)
	check_eq(_count_events("arrived"), 1, "and arrive, lamps and all")
	# Slowly enough, the end of the street is only where he stops.
	_arrive_at_the_street()
	_sim.car.s = length - half_length - 0.5
	_events = []
	for _index: int in _ticks_in(2.0):
		_sim.car.speed = minf(_sim.car.speed, GameData.as_float(street.get("bump_kmh")) - 1.0)
		_tick()
	check_eq(_count_events("hit"), 0, "rolled up to at a crawl, the end of the street is no hit")
	check_near(_sim.car.s + half_length, length, 0.01, "(he stands against it)")


## Dawn ends Act 3 of a Telling; then the street, the bay and the key.
func _check_dawn_in_a_telling() -> void:
	var telling_seed: int = 0
	for candidate: int in range(1, 400):
		if RunGenerator.boss_modifier(data, candidate, 3) == "early_sun":
			telling_seed = candidate
			break
	_sim = DriveSim.new(fresh_data())
	_events = []
	_input.clear()
	_sim.begin_telling(TABLE, telling_seed)
	_drive_on_to_act(3)
	_drive_to_the_boss()
	var started: Dictionary = _event("boss_started")
	check_eq(GameData.as_string(started.get("boss")), DAWN, "the third leg of Act 3 leads into Dawn")
	check_eq(GameData.as_string(started.get("modifier")), "early_sun", "with the modifier its seed draws")
	check_near(_sim.heavy_floor(), 0.0, 0.000001, "where the Heavy floor is 0")
	# Through it (the scripted driver jumps to its end), to the boss stop.
	_events = []
	var saves: int = _sim.checkpoints
	var guard: int = 40000
	while not _sim.stopped and guard > 0:
		guard -= 1
		_sim.car.x = _sim.car.lane_center(1)
		if _sim.car.s < _sim.leg.length - 2.0:
			_sim.car.s = _sim.leg.length - 1.0
		_sim.step(_input)
	for event: Dictionary in _sim.drain_events():
		_events.append(event)
	check_eq(GameData.as_string(_event("boss_ended").get("boss")), DAWN, "Dawn ends")
	check_eq(_sim.run.stage, RunState.Stage.BOSS_STOP, "at its boss stop")
	check_eq(_sim.checkpoints, saves + 1, "where the game saves")
	check_near(_sim.glare(), 0.0, 0.000001, "(the sun is out of his eyes there)")
	# Then the street.
	_leave_stop()
	check_eq(_sim.run.stage, RunState.Stage.ARRIVAL, "after Dawn's stop comes the Arrival")
	check_eq(_sim.boss.kind, BossSim.ARRIVAL, "(its street)")
	check_near(_sim.leg.length, GameData.as_float(_street().get("length_m")), 0.000001, "(300 m of it)")
	check_eq(_sim.car.lanes, GameData.as_int(_street().get("lanes")), "(a street, not a motorway)")
	_events = []
	_sim.car.s = _sim.leg.length - GameData.as_float(_street().get("bay_m")) * 0.5
	_sim.car.speed = 0.0
	_input.rmb = true
	_ticks(3)
	check(_sim.run.active, "standing in the bay the Telling is not over")
	_tap_at(KEY)
	check_eq(_count_events("arrived"), 1, "the key ends it")
	check_eq(_sim.run.stage, RunState.Stage.ENDED, "the Telling is over")
	check(not _sim.run.active, "(nothing more is told)")
	check_eq(GameData.as_string(_event("arrived").get("table")), TABLE, "(at the Table it was told to)")


# --- T-CALL-01: the four responses to the Call (GDD 10.4) ---------------------

func test_call_01() -> void:
	var ring: Dictionary = GameData.as_dict(_dawn().get("call"))
	check_near(GameData.as_float(ring.get("talk_s")), 30.0, 0.000001, "GDD 10.4: the Call lasts 30 s")
	check_near(GameData.as_float(ring.get("wrist_steer")), 0.4, 0.000001, "alone, he steers with his wrist at 40%")
	check_near(GameData.as_float(ring.get("talk_s")) * tuning.f("clock_scale") / 60.0, 10.0, 0.000001, "30 s standing is 10 game minutes")
	_check_call_ignored()
	_check_call_alone()
	_check_call_and_the_eyes()
	_check_call_with_a_passenger()
	_check_call_pulled_over()
	_check_call_and_the_ending()


## Dawn at the moment the phone begins to ring, on an empty road.
func _to_the_call(passenger: bool = false) -> void:
	_begin_quiet_boss(DAWN)
	_sim.items.flags[&"passenger"] = passenger
	_sim.car.s = GameData.as_float(data.record("bosses", DAWN).get("length_m")) - GameData.as_float(GameData.as_dict(_dawn().get("call")).get("from_end_m")) - 2.0
	var guard: int = _ticks_in(5.0)
	while _sim.boss.call != BossSim.CALL_RINGING and guard > 0:
		guard -= 1
		_tick()
	_events = []


## How far a pull of the pointer turns the wheel, in degrees, with the wheel
## in the hand (or under the wrist): the pull, then a moment to settle.
func _pull(pixels: float) -> float:
	var before: float = _sim.wheel.angle
	_input.pointer_is_absolute = false
	_input.pointer_delta = Vector2(pixels / 20.0, 0.0)
	_ticks(20)
	_input.pointer_delta = Vector2.ZERO
	_ticks(_ticks_in(0.6))
	return _sim.wheel.angle - before


## 1. Ignore it: no cost. The true ending is lost.
func _check_call_ignored() -> void:
	var ring_s: float = GameData.as_float(GameData.as_dict(_dawn().get("call")).get("ring_s"))
	_to_the_call()
	var nerves: float = _sim.nerves.value
	var cash: float = _sim.cash
	var clock: float = _sim.clock.minutes
	var ticks: int = _ticks_in(ring_s + 1.0)
	_ticks(ticks)
	var resolved: Dictionary = _event("call_resolved")
	check_eq(GameData.as_string(resolved.get("caller")), "noor", "ignored, the Call rings out")
	check(not GameData.as_bool(resolved.get("answered")), "unanswered")
	check_eq(_count_events("call_resolved"), 1, "(once)")
	check_near(_sim.nerves.value, nerves, 0.01, "ignoring it costs no Nerves (a missed call from the dispatcher costs %d)" % roundi(tuning.f("missed_call_nerves") if tuning.has("missed_call_nerves") else 4.0))
	check_near(_sim.cash, cash, 0.000001, "no cash")
	check_near(_sim.clock.minutes - clock, float(ticks) * DT * tuning.f("clock_scale") / 60.0, 0.000001, "and no time")
	check_eq(_sim.faults.lamps, 0, "(nor a lamp)")
	check(not _sim.boss.call_answered and not _sim.run.call_answered, "but the Call was not answered: the true ending is lost")
	check(_reach("horn"), "(his hand is his own)")
	check(not GameData.as_bool(_sim.snapshot()["at_ear"]), "(nothing at his ear)")


## 2. Answer alone: TAP the pocket. For 30 s the hand holds the phone to his
## ear; he steers with his wrist at 40% and cannot reach anything.
func _check_call_alone() -> void:
	var ring: Dictionary = GameData.as_dict(_dawn().get("call"))
	var talk: float = GameData.as_float(ring.get("talk_s"))
	var wrist: float = GameData.as_float(ring.get("wrist_steer"))
	# What a pull of 100 px does with the wheel in his hand.
	_to_the_call()
	_grip()
	var in_hand: float = _pull(100.0)
	check_near(in_hand, 100.0 * tuning.f("steer_deg_per_px"), 0.05, "(gripping, 100 px of pointer turn the wheel 35 degrees)")

	_to_the_call()
	_grip()
	_release()
	check(_reach(POCKET), "he lets go of the wheel and reaches for his pocket")
	_input.lmb = true
	_ticks(TAP_TICKS)
	_input.lmb = false
	var guard: int = SETTLE * 2
	while _event("call_resolved").is_empty() and guard > 0:
		guard -= 1
		_tick()
	var answered_at: int = _sim.tick
	var resolved: Dictionary = _event("call_resolved")
	check(GameData.as_bool(resolved.get("answered")), "a TAP on his pocket answers the Call")
	check_eq(GameData.as_string(resolved.get("taken")), BossSim.TAKEN_ALONE, "alone")
	check_eq(_count_events("ritual_completed", "ritual", "call_answer"), 1, "(through the hand)")
	check(_sim.boss.call_answered and _sim.run.call_answered, "the Call is answered")
	var shot: Dictionary = _sim.snapshot()
	check_eq(GameData.as_string(shot["call"]), BossSim.CALL_TALKING, "(he talks)")
	check_near(GameData.as_float(shot["call_left"]), talk, 2.0 * DT, "(for 30 s)")
	check_eq(GameData.as_string(shot["caller"]), "", "(it no longer rings)")
	# The hand goes to his ear and stays there.
	_input.clear()
	_ticks(_ticks_in(0.6))
	check(GameData.as_bool(_sim.snapshot()["at_ear"]), "his hand holds the phone to his ear")
	check(_sim.hand.pos.is_equal_approx(_sim.space.ear), "(at his ear)")
	check(not _reach("horn"), "he cannot reach the horn")
	check(not _reach("gear_lever"), "nor the gear lever")
	check(not _reach("visor"), "nor the visor, sun or no sun")
	check(_sim.hand.pos.is_equal_approx(_sim.space.ear), "(the hand has not left his ear)")
	_grip()
	check(not _sim.hand.gripping, "nor take the wheel in his hand")
	_input.clear()
	# But his wrist is on it: the pointer steers, at 40%, with no button held.
	var with_wrist: float = _pull(100.0)
	check_near(with_wrist, in_hand * wrist, 0.05, "he steers with his wrist at 40%%: 100 px turn the wheel %.1f degrees, not %.1f" % [with_wrist, in_hand])
	var held: float = _sim.wheel.angle
	_ticks(_ticks_in(1.0))
	check_near(_sim.wheel.angle, held, 0.001, "(the wheel stays where his wrist holds it)")
	check_near(_pull(-100.0), -in_hand * wrist, 0.05, "(and back the same way)")
	# The car answers the wheel.
	_keep_lane = false
	var x_before: float = _sim.car.x
	_pull(60.0)
	_ticks(_ticks_in(0.5))
	check(_sim.car.x > x_before + 0.2, "and the car goes where the wheel says")
	_pull(-60.0)
	_keep_lane = true
	# For 30 s, to the tick.
	guard = _ticks_in(talk + 2.0)
	while _sim.boss.call == BossSim.CALL_TALKING and guard > 0:
		guard -= 1
		if _sim.car.s > _sim.leg.length - 100.0:
			_sim.car.s -= 400.0
		_tick()
	check(absi(_sim.tick - answered_at - _ticks_in(talk)) <= 1, "for 30 s (%.3f s)" % (float(_sim.tick - answered_at) * DT))
	_ticks(2)
	check(not GameData.as_bool(_sim.snapshot()["at_ear"]), "then he puts the phone away")
	check(not _sim.wheel.gripped, "(his wrist is off the wheel)")
	check(_reach("horn"), "and can reach again")
	_grip()
	check(_sim.hand.gripping, "(and take the wheel)")
	check_near(_pull(100.0), in_hand, 0.05, "(with all of his steering)")
	_release()


## Answered alone, his hand is at his ear for 30 s, but his eyes are on the
## road: the Glance (GDD 4.7) follows a reach, and this is none (D-050).
func _check_call_and_the_eyes() -> void:
	check(absf(_sim.space.glance_for(_sim.space.ear).x) > tuning.f("glance_max_yaw") * 0.5, "(a hand at his ear is far off the forward axis: a Glance would turn his view well away)")
	_to_the_call()
	_reach(POCKET)
	_input.lmb = true
	_ticks(TAP_TICKS)
	_input.lmb = false
	_ticks(SETTLE * 2)
	_input.clear()
	check_eq(_sim.boss.call, BossSim.CALL_TALKING, "(he answered alone)")
	var most: float = 0.0
	for index: int in _ticks_in(5.0):
		_tick()
		if index >= _ticks_in(1.0):
			most = maxf(most, maxf(absf(_sim.hand.cam_yaw), absf(_sim.hand.cam_pitch)))
	check(GameData.as_bool(_sim.snapshot()["at_ear"]), "(the phone is at his ear)")
	check(most < 0.5, "with the phone at his ear his eyes stay on the road (%.1f degrees off it at most)" % most)


## 3. Answer with a passenger: DRAG the phone to them. They hold it to his
## ear. Steering is normal. He cannot reach anything for 30 s.
func _check_call_with_a_passenger() -> void:
	var talk: float = GameData.as_float(GameData.as_dict(_dawn().get("call")).get("talk_s"))
	_to_the_call()
	_grip()
	var in_hand: float = _pull(100.0)

	_to_the_call(true)
	_drag(POCKET, "passenger_shoulder")
	var resolved: Dictionary = _event("call_resolved")
	check(GameData.as_bool(resolved.get("answered")), "the phone dragged to a passenger: the Call is answered")
	check_eq(GameData.as_string(resolved.get("taken")), BossSim.TAKEN_WITH_PASSENGER, "with them")
	check_eq(_count_events("ritual_completed", "ritual", "call_hand_over"), 1, "(through the hand)")
	check(_sim.run.call_answered, "(answered)")
	var answered_at: int = _sim.tick
	_ticks(2)
	check(not GameData.as_bool(_sim.snapshot()["at_ear"]), "they hold it to his ear: his hand is free of it")
	# Steering is normal.
	_grip()
	check(_sim.hand.gripping, "he takes the wheel in his hand")
	check_near(_pull(100.0), in_hand, 0.05, "steering is normal")
	_pull(-100.0)
	# He cannot reach anything.
	_release()
	check(not _reach("horn"), "but he cannot reach the horn")
	check(not _reach("gear_lever"), "nor the gear lever")
	check(not _reach("hazard_button"), "nor anything else")
	_grip()
	check(_sim.hand.gripping, "(the wheel he can always take)")
	var guard: int = _ticks_in(talk + 2.0)
	while _sim.boss.call == BossSim.CALL_TALKING and guard > 0:
		guard -= 1
		if _sim.car.s > _sim.leg.length - 100.0:
			_sim.car.s -= 400.0
		_tick()
	check(absi(_sim.tick - answered_at - _ticks_in(talk)) <= _ticks_in(0.35), "for 30 s from when they took it (%.2f s)" % (float(_sim.tick - answered_at) * DT))
	_release()
	check(_reach("horn"), "then he can reach again")

	# With nobody beside him there is nobody to hand it to.
	_to_the_call(false)
	_drag(POCKET, "passenger_shoulder")
	check_eq(_count_events("call_resolved"), 0, "without a passenger the phone cannot be handed over")
	check_eq(_sim.boss.call, BossSim.CALL_RINGING, "(it still rings)")
	# With a passenger there, a TAP still answers it alone.
	_to_the_call(true)
	_tap_at(POCKET)
	check_eq(GameData.as_string(_event("call_resolved").get("taken")), BossSim.TAKEN_ALONE, "with a passenger beside him a TAP on the pocket still answers alone")
	check_eq(_count_events("ritual_completed", "ritual", "call_answer"), 1, "(the TAP, not the DRAG)")
	# Carried off and let go nowhere, the phone goes back: it still rings.
	_to_the_call(true)
	_carry(POCKET, [_sim.hand.anchor_position(_sim.hand.anchor_index(&"cup_a"))])
	check_eq(_count_events("call_resolved"), 0, "let go anywhere but at the passenger, nothing is answered")
	check_eq(_sim.boss.call, BossSim.CALL_RINGING, "(it still rings)")


## 4. Pull over, hazards on, then answer: the car is stopped for 30 s: 10
## game minutes.
func _check_call_pulled_over() -> void:
	var talk: float = GameData.as_float(GameData.as_dict(_dawn().get("call")).get("talk_s"))
	_to_the_call()
	_stand_on_the_shoulder(true)
	var clock: float = _sim.clock.minutes
	var began: int = _sim.tick
	var answered_at: int = _answer_with_the_brake_held()
	var resolved: Dictionary = _event("call_resolved")
	check(GameData.as_bool(resolved.get("answered")), "pulled over with his hazard lights on, he answers")
	check_eq(GameData.as_string(resolved.get("taken")), BossSim.TAKEN_PARKED, "standing")
	check(_sim.run.call_answered, "(answered)")
	# The Clock at the answer: what it was, and what ran while he reached.
	clock += float(answered_at - began) * DT * tuning.f("clock_scale") / 60.0
	var stood_at: float = _sim.car.s
	check(_sim.gate.gear == 3, "(third gear is still engaged)")
	# He takes his foot off the brake: the car does not move until he hangs up.
	_input.clear()
	var moved: bool = false
	var guard: int = _ticks_in(talk + 2.0)
	while _sim.boss.call == BossSim.CALL_TALKING and guard > 0:
		guard -= 1
		_tick()
		if _sim.boss.call == BossSim.CALL_TALKING:
			moved = moved or _sim.car.speed != 0.0 or _sim.car.s != stood_at
	check(not moved, "the car is stopped for the whole call, foot on the brake or not")
	check(absi(_sim.tick - answered_at - _ticks_in(talk)) <= 1, "for 30 s (%.3f s)" % (float(_sim.tick - answered_at) * DT))
	check_near(_sim.clock.minutes - clock, 10.0, 0.01, "which is 10 game minutes on the Clock (%.3f)" % (_sim.clock.minutes - clock))
	check_eq(_sim.faults.lamps, 0, "(and nothing else: no lamp)")
	_ticks(_ticks_in(1.0))
	check(_sim.car.speed > 0.0, "then the car moves off again")

	# During it the phone is in his hand.
	_to_the_call()
	_stand_on_the_shoulder(true)
	_answer_with_the_brake_held()
	_ticks(_ticks_in(0.6))
	check(GameData.as_bool(_sim.snapshot()["at_ear"]), "(the phone is at his ear)")
	check(not _reach("horn"), "(and he can reach for nothing)")

	# Not pulled over as GDD 4.6 asks, it is a call taken alone: the car is free.
	var cases: Array[String] = ["without his hazard lights", "stopped in a lane", "still rolling on the shoulder"]
	for case: int in cases.size():
		_to_the_call()
		match case:
			0:
				_stand_on_the_shoulder(false)
			1:
				_stand_in_lane(true)
			2:
				_stand_on_the_shoulder(true)
		_answer_with_the_brake_held(10.0 if case == 2 else 0.0)
		check_eq(GameData.as_string(_event("call_resolved").get("taken")), BossSim.TAKEN_ALONE, "%s it is a call taken alone" % cases[case])
		_input.clear()
		_ticks(_ticks_in(1.5))
		check(_sim.car.speed > 5.0, "%s: off the brake, the car rolls" % cases[case])


## The pocket is reached and tapped with the brake held all the while. With
## `rolling` above zero the car is kept at that speed until the answer.
## Returns the tick in which the Call was answered.
func _answer_with_the_brake_held(rolling: float = 0.0) -> int:
	_input.pointer_is_absolute = true
	_input.pointer = _sim.hand.anchor_pointer(_sim.hand.anchor_index(&"pocket"))
	_input.rmb = true
	var guard: int = _ticks_in(3.0)
	while _sim.hand.at_id() != &"pocket" and guard > 0:
		guard -= 1
		_sim.car.speed = rolling
		_tick()
	_input.lmb = true
	for _index: int in TAP_TICKS:
		_sim.car.speed = rolling
		_tick()
	_input.lmb = false
	var answered_at: int = -1
	for _index: int in SETTLE:
		_sim.car.speed = rolling
		_tick()
		if answered_at < 0 and not _event("call_resolved").is_empty():
			answered_at = _sim.tick
	return answered_at


## However he answered, he answered: the Arrival knows (GDD 11.4), through a
## stop and its save.
func _check_call_and_the_ending() -> void:
	for answers: bool in [true, false]:
		_sim = DriveSim.new(fresh_data())
		_events = []
		_keep_lane = true
		_input.clear()
		_sim.begin_telling(TABLE, 3)
		_drive_on_to_act(3)
		_drive_to_the_boss()
		check_eq(_sim.boss.kind, DAWN, "(Dawn, in a Telling)")
		_sim.car.s = _sim.leg.length - GameData.as_float(GameData.as_dict(_dawn().get("call")).get("from_end_m")) - 2.0
		var guard: int = _ticks_in(5.0)
		while _sim.boss.call != BossSim.CALL_RINGING and guard > 0:
			guard -= 1
			_tick()
		check_eq(_sim.boss.call, BossSim.CALL_RINGING, "(the phone rings)")
		if answers:
			_tap_at(POCKET)
			check_eq(_sim.boss.call, BossSim.CALL_TALKING, "(he answers)")
		# To the end of Dawn: whoever is on the phone hangs up as he pulls in.
		_sim.traffic.clear()
		guard = 40000
		while not _sim.stopped and guard > 0:
			guard -= 1
			_sim.car.x = _sim.car.lane_center(1)
			if _sim.car.s < _sim.leg.length - 2.0:
				_sim.car.s = _sim.leg.length - 1.0
			_sim.step(_input)
		check_eq(_sim.run.stage, RunState.Stage.BOSS_STOP, "(Dawn's stop)")
		check_eq(GameData.as_bool(_sim.checkpoint.get("call_answered")), answers, "the save made there knows whether he answered")
		_ticks(3)
		check(not GameData.as_bool(_sim.snapshot()["at_ear"]), "at the stop the phone is put away")
		# (At a stop the hand goes to the vendor's tray, and to nothing else.)
		check(not _offers().is_empty() and _reach(GameData.as_string(_offers()[0]["anchor"])), "(his hand is free for the stop)")
		_leave_stop()
		_sim.car.s = _sim.leg.length - GameData.as_float(_street().get("bay_m")) * 0.5
		_sim.car.speed = 0.0
		_input.rmb = true
		_ticks(3)
		_events = []
		_tap_at(KEY)
		check_eq(GameData.as_bool(_event("arrived").get("call")), answers,
				"he parks having answered the Call" if answers else "he parks without having answered: the true ending is lost")


## A Telling is driven on, each stretch to its end at once, until its boss begins.
func _drive_to_the_boss() -> void:
	var guard: int = 40000
	_input.clear()
	while _sim.run.stage != RunState.Stage.BOSS and guard > 0:
		guard -= 1
		if _sim.stopped:
			_leave_stop()
			continue
		_sim.car.x = _sim.car.lane_center(1)
		if _sim.leg.active and _sim.car.s < _sim.leg.length - 2.0:
			_sim.car.s = _sim.leg.length - 1.0
		_sim.step(_input)
	for event: Dictionary in _sim.drain_events():
		_events.append(event)


## The street of the Arrival by itself: rolling in first gear from its start.
func _arrive_at_the_street() -> void:
	_sim = DriveSim.new(fresh_data())
	_events = []
	_keep_lane = true
	_input.clear()
	_sim.act = 3
	_sim.begin_arrival()
	_sim.in_encounter = true
	_sim.drain_events()


## The road sign of a kind that the snapshot shows ({}: none).
func _sign(kind: String) -> Dictionary:
	var signs: Array[Dictionary] = _sim.snapshot()["signs"]
	for sign: Dictionary in signs:
		if GameData.as_string(sign.get("kind")) == kind:
			return sign
	return {}


# --- Helpers -----------------------------------------------------------------

## The car stands wholly on the shoulder, the brake held, the hazard lights
## as told. From here the car is no longer put back in its lane.
func _stand_on_the_shoulder(hazards: bool) -> void:
	_keep_lane = false
	_input.clear()
	_input.rmb = true
	_sim.car.x = (_sim.car.road_right() + _sim.car.guardrail_x()) * 0.5
	_sim.car.speed = 0.0
	_sim.car.v_lat = 0.0
	_sim.items.flags[DriveSim.FLAG_HAZARDS] = hazards


## The car stands in the middle of its lane, the brake held.
func _stand_in_lane(hazards: bool) -> void:
	_keep_lane = true
	_input.clear()
	_input.rmb = true
	_sim.car.speed = 0.0
	_sim.car.v_lat = 0.0
	_sim.items.flags[DriveSim.FLAG_HAZARDS] = hazards


## Off the brake, back in the middle lane, in third gear at its speed.
func _drive_on() -> void:
	_input.clear()
	_keep_lane = true
	_sim.gate.reset(3)
	_sim.car.x = _sim.car.lane_center(1)
	_sim.car.speed = tuning.fi("gear_speeds", 2)


## How often something has sounded its horn behind him (the tell of a
## rear-end crash).
func _horns_behind() -> int:
	var count: int = 0
	for event: Dictionary in _events:
		if GameData.as_string(event.get("type")) == "sfx_requested" and GameData.as_bool(event.get("behind")):
			count += 1
	return count


func _event_of(events: Array[Dictionary], type: String) -> Dictionary:
	for event: Dictionary in events:
		if GameData.as_string(event.get("type")) == type:
			return event
	return {}
