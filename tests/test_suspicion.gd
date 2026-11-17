extends TestSuite
## M4: Suspicion (GDD 6.5), row by row, through the whole simulation.

const DT: float = DriveSim.DT
const START: float = 50.0

var _sim: DriveSim
var _input: DriveInput
var _events: Array[Dictionary] = []


func before_each() -> void:
	_new_sim(fresh_data())


## T-SUS-01: each row of section 6.5 changes Suspicion by its amount.
func test_sus_01() -> void:
	check_near(tuning.f("suspicion_gear_rate"), 15.0, 0.000001, "GDD 6.5: any gear but 2 or 3 is +15 per second")
	check_near(tuning.f("suspicion_lane_cross"), 20.0, 0.000001, "crossing a lane line without indicating is +20")
	check_near(tuning.f("suspicion_contraband"), 40.0, 0.000001, "using contraband in view is +40")
	check_near(tuning.f("suspicion_phone"), 30.0, 0.000001, "using the phone is +30")
	check_near(tuning.f("suspicion_snap"), 30.0, 0.000001, "a Snap is +30")
	check_near(tuning.f("suspicion_honk"), 15.0, 0.000001, "honking is +15")
	check_near(tuning.f("cone_suspicion"), 10.0, 0.000001, "each cone is +10")
	check_near(_sim.faults.param_of(&"dead_headlight", "patrol_suspicion_per_s", 0.0), 10.0, 0.000001, "a dead headlight at night is +10 per second")
	check_near(tuning.f("suspicion_decay"), 5.0, 0.000001, "driving clean is -5 per second")
	check_near(tuning.f("suspicion_max"), 100.0, 0.000001, "at 100 he is pulled over")

	_check_only_while_watched()
	_check_gears()
	_check_lane_lines()
	_check_honk()
	_check_snap()
	_check_contraband_and_phone()
	_check_cones()
	_check_headlight()
	_check_limits()


## Suspicion exists only while a police car is behind or at a checkpoint.
func _check_only_while_watched() -> void:
	_new_sim(fresh_data())
	_sim.gate.reset(4)
	_run(3.0)
	_click(&"horn")
	check_near(_sim.suspicion.value, 0.0, 0.000001, "with nobody watching, fourth gear and the horn raise no Suspicion")
	check(not _has_event("suspicion_changed"), "and nothing is announced")
	check(not GameData.as_bool(_sim.snapshot()["suspicion_watching"]), "the snapshot says nobody is watching")


func _check_gears() -> void:
	var rate: float = tuning.f("suspicion_gear_rate")
	var decay: float = tuning.f("suspicion_decay")
	var legal: Array = tuning.a("suspicion_legal_gears")
	check(legal.has(2.0) and legal.has(3.0) and legal.size() == 2, "the gears that do not raise Suspicion are 2 and 3")
	for gear: int in [1, 2, 3, 4, 5]:
		_watched(gear)
		_run(2.0)
		var expected: float = -decay * 2.0 if gear == 2 or gear == 3 else rate * 2.0
		check_near(_sim.suspicion.value - START, expected, 0.05, "2 s in gear %d change Suspicion by %s" % [gear, str(expected)])
	# The lever out of gear is no gear (DECISIONS D-031).
	_watched(0)
	_run(2.0)
	check_near(_sim.suspicion.value - START, -decay * 2.0, 0.05, "2 s with the lever in neutral count as driving clean")
	check_near(GameData.as_float(_sim.snapshot()["suspicion"]), _sim.suspicion.value, 0.000001, "the snapshot carries Suspicion")


func _check_lane_lines() -> void:
	var cross: float = tuning.f("suspicion_lane_cross")
	var indicator: Dictionary = data.record("rituals", "indicator")
	# Without indicating.
	_watched(3)
	_cross(2)
	check_near(_sim.suspicion.value - START, cross, 0.1, "crossing a lane line without indicating is +20")
	check(_has_event("suspicion_changed"), "the change is announced")
	# Indicating the way he goes: up is right (GDD 4.6).
	_watched(3)
	_flick(&"indicator_stalk", Vector2(0.0, -8.0))
	check_eq(_sim.items.indicator, 1, "(the stalk up indicates right)")
	var before: float = _sim.suspicion.value
	_cross(2)
	check(_sim.suspicion.value <= before, "crossing to the right while indicating right raises nothing")
	check_eq(_sim.items.indicator, 0, "(the indicator cancels at the line)")
	# Indicating the wrong way.
	_watched(3)
	_flick(&"indicator_stalk", Vector2(0.0, 8.0))
	check_eq(_sim.items.indicator, -1, "(the stalk down indicates left)")
	before = _sim.suspicion.value
	_cross(2)
	check_near(_sim.suspicion.value - before, cross, 0.1, "crossing to the right while indicating left is +20 all the same")
	# To the left.
	_watched(3)
	_flick(&"indicator_stalk", Vector2(0.0, 8.0))
	before = _sim.suspicion.value
	_cross(0)
	check(_sim.suspicion.value <= before, "crossing to the left while indicating left raises nothing")
	check(not indicator.is_empty(), "the indicator is one of the cabin's controls")


func _check_honk() -> void:
	_watched(3)
	_click(&"horn")
	check_near(_sim.suspicion.value - _before_click, tuning.f("suspicion_honk") - tuning.f("suspicion_decay") * _clicked_seconds, 0.2, "honking is +15")


func _check_snap() -> void:
	# A slap on a face already at the edge: +12 Nerves take him over the top.
	_watched(3)
	_sim.nerves.set_value(tuning.f("snap_at") - 5.0)
	_click(&"face")
	check(_has_event("snap"), "(the slap took his Nerves to 100: a Snap)")
	check_near(_sim.suspicion.value - _before_click, tuning.f("suspicion_snap") - tuning.f("suspicion_decay") * _clicked_seconds, 0.2, "a Snap is +30")


func _check_contraband_and_phone() -> void:
	# A drink that is contraband and a phone, in a private copy of the data.
	var roots: Dictionary = data.roots.duplicate(true)
	var items: Array = GameData.as_array(GameData.as_dict(roots["items"])["items"])
	var phone: Dictionary = {}
	for entry: Variant in items:
		var item: Dictionary = entry
		if GameData.as_string(item["id"]) == "tea_glass":
			item["contraband"] = true
			phone = item.duplicate(true)
	phone["id"] = "test_phone"
	phone["slots"] = ["phone_mount"]
	phone["tags"] = ["phone"]
	phone["contraband"] = false
	phone["rituals"] = ["test_phone_answer"]
	items.append(phone)
	GameData.as_array(GameData.as_dict(roots["rituals"])["rituals"]).append({
		"id": "test_phone_answer", "anchor": "@slot", "item": "test_phone", "gesture": "TAP",
		"eyes_down": false, "requires": [], "on_complete": [],
	})
	var private: GameData = GameData.from_parts(roots, data.lines.duplicate(true))
	check(DataValidator.validate(private).is_empty(), "the contraband drink and the phone are valid data")

	_new_sim(private)
	_sim.items.add_item(&"test_phone", &"phone_mount")
	_sim.gate.reset(3)
	_sim.car.reset(1, 3)
	_sim.suspicion.begin_watch()
	_sim.suspicion.add(START)
	_step()
	# A sip of the contraband drink: HOLD at cup_a.
	_aim(&"cup_a")
	_run(1.0)
	var before: float = _sim.suspicion.value
	var supply: int = _sim.items.item(&"tea_glass").supply
	_input.lmb = true
	_run(GameData.as_float(data.record("rituals", "tea_sip").get("hold_s")) + 0.1)
	_input.lmb = false
	_run(0.1)
	check_eq(_sim.items.item(&"tea_glass").supply, supply - 1, "(he drank)")
	check_near(_sim.suspicion.value - before, tuning.f("suspicion_contraband"), 4.0, "using contraband in view is +40")
	check(_sim.suspicion.value - before > tuning.f("suspicion_phone") + 4.0, "(more than the phone's +30)")
	# The phone: a TAP at the mount.
	_sim.suspicion.add(-START)
	_aim(&"phone_mount")
	_run(1.0)
	before = _sim.suspicion.value
	_input.lmb = true
	_run(0.05)
	_input.lmb = false
	_run(0.1)
	check_near(_sim.suspicion.value - before, tuning.f("suspicion_phone"), 1.0, "using the phone is +30")

	# With nobody watching neither counts.
	_new_sim(private)
	_sim.items.add_item(&"test_phone", &"phone_mount")
	_aim(&"phone_mount")
	_run(1.0)
	_input.lmb = true
	_run(0.05)
	_input.lmb = false
	_run(0.1)
	check_near(_sim.suspicion.value, 0.0, 0.000001, "with nobody watching the phone raises nothing")


func _check_cones() -> void:
	# A roadworks leg, watched from the start, driven a hand's breadth off the corridor's middle.
	_new_sim(fresh_data())
	var plan: Dictionary = LegGenerator.generate(data, "roadworks", 2, 61, "")
	var checker: LegChecker = LegChecker.new(data)
	checker.load_plan(plan)
	_sim.gate.reset(3)
	_sim.begin_leg(plan)
	_sim.suspicion.begin_watch()
	var zone: Dictionary = GameData.as_array(plan["zones"])[0]
	var offset: float = (GameData.as_float(zone["width"]) - tuning.f("car_width")) * 0.5 + 0.05
	var cones: int = 0
	var jumps: float = 0.0
	while _sim.car.s < GameData.as_float(zone["s"]) + 40.0:
		var inside: bool = _sim.car.s > GameData.as_float(zone["s"]) - 3.0
		_sim.car.x = checker.line_x(_sim.car.s) + (offset if inside else 0.0)
		if not inside and _sim.items.indicator == 0:
			# He indicates wherever the line changes lane, so only the cones count.
			_sim.items.indicator = signi(roundi(checker.line_x(_sim.car.s + 40.0) - checker.line_x(_sim.car.s)))
		var before: float = _sim.suspicion.value
		_sim.step(_input)
		if not _sim.leg.hits.is_empty():
			cones += _sim.leg.hits.size()
			jumps += _sim.suspicion.value - before
	if check(cones >= 3, "the car clipped cones (%d)" % cones):
		check_near(jumps / float(cones), tuning.f("cone_suspicion"), 0.1, "each cone is +10")
	check_near(GameData.as_float(data.record("hazard_kinds", "cone").get("suspicion")), tuning.f("cone_suspicion"), 0.000001, "the cone's data agrees with cone_suspicion")
	check_near(GameData.as_float(data.record("hazard_kinds", "melon").get("suspicion")), tuning.f("cone_suspicion"), 0.000001, "and a melon counts like a cone (GDD 5.6)")


func _check_headlight() -> void:
	var rate: float = _sim.faults.param_of(&"dead_headlight", "patrol_suspicion_per_s", 0.0)
	var decay: float = tuning.f("suspicion_decay")
	for condition: String in ["night", "clear"]:
		for dead: bool in [true, false]:
			_new_sim(fresh_data())
			var plan: Dictionary = LegGenerator.generate(data, "night" if condition == "night" else "open_road", 2, 12, "")
			var checker: LegChecker = LegChecker.new(data)
			checker.load_plan(plan)
			_sim.gate.reset(3)
			_sim.begin_leg(plan)
			if dead:
				_sim.faults.deck.erase(&"dead_headlight")
				_sim.faults.deck.push_front(&"dead_headlight")
				_sim.faults.light(1)
			_sim.suspicion.begin_watch()
			_sim.suspicion.add(START)
			var lane_x: float = _sim.car.x
			for _tick: int in int(2.0 / DT):
				_sim.car.x = lane_x
				_sim.step(_input)
			var expected: float = rate * 2.0 if dead and condition == "night" else -decay * 2.0
			check_near(_sim.suspicion.value - START, expected, 0.1, "2 s %s with %s headlight change Suspicion by %s" % [
					"at night" if condition == "night" else "by day", "a dead" if dead else "no dead", str(expected)])


func _check_limits() -> void:
	# Clean driving wears it down to nothing, and no further.
	_watched(3)
	_sim.suspicion.add(-START + 4.0)
	_run(2.0)
	check_near(_sim.suspicion.value, 0.0, 0.000001, "driving clean takes Suspicion down to 0 and no lower")
	# It stops at the top, where he is pulled over.
	_watched(4)
	_sim.suspicion.add(45.0)
	_events = []
	_run(1.0)
	check_near(_sim.suspicion.value, tuning.f("suspicion_max"), 0.000001, "Suspicion stops at 100")
	check(_sim.pulled_over, "and at 100 he is pulled over")
	check(_has_event("pulled_over"), "which is announced")
	check_near(_sim.car.speed, 0.0, 0.000001, "the car stands")
	check(_sim.car.x > _sim.car.road_right(), "on the shoulder")


# --- Helpers -----------------------------------------------------------------

var _clicked_seconds: float = 0.0
## Suspicion just before the last click was made (the hand had arrived).
var _before_click: float = 0.0


func _new_sim(game_data: GameData) -> void:
	_sim = DriveSim.new(game_data)
	_input = DriveInput.new()
	_events = []


## A fresh simulation in `gear`, in the middle lane, with someone watching
## and Suspicion at START.
func _watched(gear: int) -> void:
	_new_sim(fresh_data())
	_sim.gate.reset(gear)
	_sim.car.reset(1, maxi(gear, 1))
	_sim.suspicion.begin_watch()
	_sim.suspicion.add(START)
	_events = []


func _hold_lane() -> void:
	if _sim.pulled_over:
		return
	_sim.car.x = _sim.car.lane_center(clampi(_sim.car.lane_of(_sim.car.x), 0, _sim.car.lanes - 1))


func _step() -> void:
	_hold_lane()
	_sim.step(_input)
	for event: Dictionary in _sim.drain_events():
		_events.append(event)


func _run(seconds: float) -> void:
	for _tick: int in roundi(seconds / DT):
		_step()


func _has_event(type: String) -> bool:
	for event: Dictionary in _events:
		if GameData.as_string(event.get("type")) == type:
			return true
	return false


## Puts the car in `lane` at once: it crosses the line between.
func _cross(lane: int) -> void:
	_sim.car.x = _sim.car.lane_center(lane)
	_sim.step(_input)
	for event: Dictionary in _sim.drain_events():
		_events.append(event)


func _aim(anchor: StringName) -> void:
	_input.clear()
	_input.pointer_is_absolute = true
	_input.pointer = _sim.hand.anchor_pointer(_sim.hand.anchor_index(anchor))


## A click at an anchor, the hand travelling there first.
func _click(anchor: StringName) -> void:
	_aim(anchor)
	_run(1.0)
	_before_click = _sim.suspicion.value
	_input.lmb = true
	_run(0.05)
	_input.lmb = false
	_run(0.1)
	_clicked_seconds = float(roundi(0.05 / DT) + roundi(0.1 / DT)) * DT
	_input.clear()


## A flick at an anchor: `per_tick` pointer motion for ten ticks with the button down.
func _flick(anchor: StringName, per_tick: Vector2) -> void:
	_aim(anchor)
	_run(1.2)
	_input.pointer_is_absolute = false
	_input.lmb = true
	_input.pointer_delta = per_tick
	_run(10.0 * DT)
	_input.pointer_delta = Vector2.ZERO
	_input.lmb = false
	_run(0.1)
	_input.clear()
