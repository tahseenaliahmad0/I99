extends TestSuite
## M3: the Car's lamps and faults (GDD 6.3).

const DT: float = DriveSim.DT

var _sim: DriveSim
var _input: DriveInput


func before_each() -> void:
	_sim = DriveSim.new(fresh_data())
	_input = DriveInput.new()


## T-FAULT-01: the fifth lamp is a Wreck; capacity changes apply.
func test_fault_01() -> void:
	var capacity: int = tuning.i("lamp_capacity")
	check_eq(capacity, 5, "GDD 15: five lamps")
	check_eq(_sim.faults.capacity, capacity, "the car starts with lamp_capacity lamps")
	check_eq(_sim.faults.lamps, 0, "all dark")

	# Scrape after scrape against the guardrail: one lamp each.
	var wreck_events: int = 0
	for lamp: int in capacity:
		check(not _sim.wrecked, "with %d lamps lit the car still runs" % lamp)
		_scrape_guardrail()
		check_eq(_sim.faults.lamps, lamp + 1, "scrape %d lights lamp %d" % [lamp + 1, lamp + 1])
		for event: Dictionary in _sim.drain_events():
			if event.get("type") == "wreck":
				wreck_events += 1
	check(_sim.wrecked, "the fifth lamp is a Wreck")
	check(_sim.faults.is_wrecked(), "the fault system agrees")
	check_eq(wreck_events, 1, "the Wreck is announced once")
	check_eq(_sim.snapshot()["wrecked"], true, "the snapshot shows the Wreck")

	# One more lamp (Bull bar): the fifth is survivable, the sixth is the Wreck.
	_sim = DriveSim.new(fresh_data())
	_sim.faults.set_capacity_bonus(1)
	check_eq(_sim.faults.capacity, capacity + 1, "a capacity bonus of 1 gives six lamps")
	for _lamp: int in capacity:
		_scrape_guardrail()
	check(not _sim.wrecked, "with six lamps, five lit is not a Wreck")
	_scrape_guardrail()
	check(_sim.wrecked, "the sixth is")

	# One fewer (Tinted glass or Turbo), and two fewer (both).
	for fewer: int in [1, 2]:
		_sim = DriveSim.new(fresh_data())
		_sim.faults.set_capacity_bonus(-fewer)
		check_eq(_sim.faults.capacity, capacity - fewer, "a capacity bonus of -%d gives %d lamps" % [fewer, capacity - fewer])
		for _lamp: int in capacity - fewer - 1:
			_scrape_guardrail()
		check(not _sim.wrecked, "one short of %d lamps is not a Wreck" % (capacity - fewer))
		_scrape_guardrail()
		check(_sim.wrecked, "lamp %d is" % (capacity - fewer))

	# A hit never lights more lamps than there are.
	_sim = DriveSim.new(fresh_data())
	_sim.faults.light(capacity - 1)
	var drawn: Array[StringName] = _sim.faults.light(3)
	check_eq(drawn.size(), 1, "a three-lamp hit with one lamp left lights one")
	check_eq(_sim.faults.lamps, capacity, "and the count stops at capacity")

	# Changing capacity with lamps lit applies at once.
	_sim = DriveSim.new(fresh_data())
	_sim.faults.light(capacity - 1)
	check(not _sim.faults.is_wrecked(), "four lamps of five")
	_sim.faults.set_capacity_bonus(-1)
	check(_sim.faults.is_wrecked(), "become four of four when a lamp is taken away")


## T-FAULT-02: the fault deck, each fault's effect, and repairs.
func test_fault_02() -> void:
	var all: Array[StringName] = _sim.faults.fault_ids()
	check_eq(all.size(), 7, "GDD 6.3 lists seven faults")
	for id: String in ["rattle", "cracked_windscreen", "dead_headlight", "pulling_steering", "slipping_clutch", "stuck_wiper", "cracked_mirror"]:
		check(all.has(StringName(id)), "the fault '%s' exists as data" % id)

	# --- The deck is a seeded shuffle.
	var first: Array[StringName] = _deck_for(4242)
	var again: Array[StringName] = _deck_for(4242)
	check_eq(first, again, "the same seed gives the same fault deck")
	check_eq(first.size(), all.size(), "the deck holds every fault once")
	var sorted_deck: Array[StringName] = first.duplicate()
	var sorted_all: Array[StringName] = all.duplicate()
	sorted_deck.sort()
	sorted_all.sort()
	check_eq(sorted_deck, sorted_all, "nothing is missing and nothing is doubled")
	var different: int = 0
	for other_seed: int in [1, 2, 3, 4, 5, 6]:
		if _deck_for(other_seed) != first:
			different += 1
	check(different >= 5, "other seeds give other decks")

	# --- Each hit draws as many faults as it lights lamps, from the top.
	_sim = DriveSim.new(fresh_data())
	_sim.reseed(99)
	var deck: Array[StringName] = _sim.faults.deck.duplicate()
	var one: Array[StringName] = _sim.faults.light(1)
	check_eq(one, deck.slice(0, 1), "a scrape draws the top fault")
	var two: Array[StringName] = _sim.faults.light(2)
	check_eq(two, deck.slice(1, 3), "a crash draws the next two")
	check_eq(_sim.faults.active, deck.slice(0, 3), "the lit faults are those drawn, in order")
	check_eq(_sim.faults.lamps, 3, "one lamp per fault")
	check_eq(_sim.faults.deck, deck.slice(3), "and they have left the deck")

	# Through a real hit: the lamp_lit event names the faults.
	_sim = DriveSim.new(fresh_data())
	_sim.reseed(99)
	_sim.drain_events()
	_scrape_guardrail()
	var named: Array = []
	for event: Dictionary in _sim.drain_events():
		if event.get("type") == "lamp_lit":
			named = GameData.as_array(event.get("faults"))
	check_eq(named.size(), 1, "a scrape's lamp_lit event names one fault")
	if named.size() == 1:
		check_eq(named[0], deck[0], "the top of the deck")

	# --- Effects, one fault at a time.
	_check_rattle()
	_check_cracked_windscreen()
	_check_dead_headlight()
	_check_pulling_steering()
	_check_slipping_clutch()
	_check_stuck_wiper()
	_check_cracked_mirror()

	# --- Repair: the chosen fault and its lamp go.
	_sim = DriveSim.new(fresh_data())
	_sim.reseed(99)
	_sim.faults.light(3)
	var lit: Array[StringName] = _sim.faults.active.duplicate()
	check(_sim.faults.repair(lit[1]), "a lit fault can be repaired")
	check_eq(_sim.faults.lamps, 2, "its lamp goes dark")
	check(not _sim.faults.has(lit[1]), "the chosen fault is gone")
	check(_sim.faults.has(lit[0]) and _sim.faults.has(lit[2]), "the others stay")
	check(not _sim.faults.repair(lit[1]), "a fault that is not lit cannot be repaired")
	check_eq(_sim.faults.deck.back(), lit[1], "the repaired fault goes to the bottom of the deck")


func _check_rattle() -> void:
	var rate: float = _sim.faults.param_of(&"rattle", "nerves_per_s", 0.0)
	check_near(rate, 0.2, 0.000001, "GDD 6.3: the rattle is +0.2 Nerves per second")
	var quiet: float = _nerves_per_second(&"")
	var rattling: float = _nerves_per_second(&"rattle")
	check_near(rattling - quiet, rate, 0.002, "a rattle adds its nerves_per_s every second")


func _check_cracked_windscreen() -> void:
	_light(&"cracked_windscreen")
	check_near(GameData.as_float(_sim.snapshot()["cracks"]), _sim.faults.param_of(&"cracked_windscreen", "cracks", 0.0), 0.000001, "a cracked windscreen covers its share of the view")
	check_near(_sim.faults.param_of(&"cracked_windscreen", "cracks", 0.0), 0.2, 0.000001, "GDD 6.3: 20% of the view")
	_sim.faults.repair(&"cracked_windscreen")
	check_near(GameData.as_float(_sim.snapshot()["cracks"]), 0.0, 0.000001, "repaired, the view is whole")


func _check_dead_headlight() -> void:
	_sim = DriveSim.new(fresh_data())
	var low: float = tuning.f("low_beam_cone")
	check_near(_sim.headlight_cone(), low, 0.000001, "both headlights reach low_beam_cone")
	_light(&"dead_headlight")
	var mult: float = _sim.faults.param_of(&"dead_headlight", "night_cone_mult", 1.0)
	check_near(mult, 0.5, 0.000001, "GDD 6.3: the night view cone is halved")
	check_near(_sim.headlight_cone(), low * mult, 0.000001, "with a dead headlight the cone is halved")
	_sim.items.flags[&"high_beam"] = true
	check_near(_sim.headlight_cone(), tuning.f("high_beam_cone") * mult, 0.000001, "on high beam too")
	check_near(_sim.faults.param_of(&"dead_headlight", "patrol_suspicion_per_s", 0.0), 10.0, 0.000001, "GDD 6.3: +10 Suspicion per second in a night Patrol (applied with Suspicion)")


func _check_pulling_steering() -> void:
	_sim = DriveSim.new(fresh_data())
	_sim.step(_input)
	var straight: float = _sim.car.drift
	_light(&"pulling_steering")
	_sim.step(_input)
	var pull: float = _sim.faults.param_of(&"pulling_steering", "drift_left", 0.0)
	check_near(pull, 0.4, 0.000001, "GDD 6.3: 0.4 m/s to the left")
	check_near(_sim.car.drift - straight, -pull, 0.000001, "pulling steering drifts the car to the left")
	var x_before: float = _sim.car.x
	for _tick: int in int(1.0 / DT):
		_sim.step(_input)
	check_near(_sim.car.x - x_before, tuning.f("crown_drift") - pull, 0.001, "over a second that is the crown minus the pull")


func _check_slipping_clutch() -> void:
	_sim = DriveSim.new(fresh_data())
	var travel: float = _lever_travel()
	_sim = DriveSim.new(fresh_data())
	_light(&"slipping_clutch")
	var slipped: float = _lever_travel()
	var mult: float = _sim.faults.param_of(&"slipping_clutch", "lever_speed_mult", 1.0)
	check_near(mult, 0.5, 0.000001, "GDD 6.3: the lever moves at half pointer speed")
	check(travel > 0.0, "the lever follows the hand")
	check_near(slipped / travel, mult, 0.01, "with a slipping clutch the same drag moves it half as far")


func _check_stuck_wiper() -> void:
	_sim = DriveSim.new(fresh_data())
	# (D-074, the owner: a sweep lasts 12 to 18 s and the blur comes back
	# slowly at first. A stuck wiper's sweep is 7 s, about half a good one.)
	var clear: float = _sim.items.wiper_clear_time()
	var power: float = tuning.f("wiper_blur_power")
	var good_least: float = tuning.f("wiper_clear_time") - tuning.f("wiper_clear_spread")
	_sim.items.since_wipe = clear * 0.5
	check_near(_sim.items.rain_blur(), 0.0, 0.000001, "in dry weather the wiper has nothing to clear")
	_sim.items.raining = true
	check_near(_sim.items.rain_blur(), pow(0.5, power), 0.000001, "in the rain, half-way through the sweep's time the blur is a half to wiper_blur_power")
	check(_sim.items.rain_blur() < 0.25, "which is under a quarter: it comes back slowly at first")
	_light(&"stuck_wiper")
	var stuck: float = _sim.faults.param_of(&"stuck_wiper", "wiper_clear_s", clear)
	check_near(stuck, 7.0, 0.000001, "a stuck wiper's sweep clears rain for 7 s")
	check(stuck <= good_least * 0.6, "which is well under the shortest good sweep (%s s)" % str(good_least))
	check_near(_sim.items.wiper_clear_time(), stuck, 0.000001, "with the fault lit the sweep's time is the stuck wiper's")
	_sim.items.since_wipe = stuck * 0.5
	check_near(_sim.items.rain_blur(), pow(0.5, power), 0.000001, "with a stuck wiper the same curve runs over 7 s")
	_sim.items.since_wipe = stuck
	check_near(_sim.items.rain_blur(), 1.0, 0.000001, "and at 7 s the view is fully blurred")


func _check_cracked_mirror() -> void:
	_sim = DriveSim.new(fresh_data())
	check_near(GameData.as_float(_sim.snapshot()["mirror_delay"]), 0.0, 0.000001, "a whole mirror shows its tells on time")
	_light(&"cracked_mirror")
	check_near(GameData.as_float(_sim.snapshot()["mirror_delay"]), 2.0, 0.000001, "GDD 6.3: with a cracked mirror they arrive 2 s later")


# --- Helpers ------------------------------------------------------------------

## Lights one chosen fault, as if it had been on top of the deck.
func _light(fault: StringName) -> void:
	_sim.faults.deck.erase(fault)
	_sim.faults.deck.push_front(fault)
	_sim.faults.light(1)


func _deck_for(telling_seed: int) -> Array[StringName]:
	var sim: DriveSim = DriveSim.new(fresh_data())
	sim.reseed(telling_seed)
	return sim.faults.deck.duplicate()


## Puts the car against the guardrail for one scrape, then back in its lane
## with the immunity over.
func _scrape_guardrail() -> void:
	_sim.car.x = _sim.car.guardrail_x() - _sim.car.half_width() + 0.01
	_sim.collision.immunity_left = 0.0
	_sim.step(_input)
	_sim.car.x = _sim.car.lane_center(1)
	_sim.collision.immunity_left = 0.0


## Nerves per second on a quiet road in an encounter (no ambient rate), with
## one fault lit (or none for &"").
func _nerves_per_second(fault: StringName) -> float:
	_sim = DriveSim.new(fresh_data())
	_sim.in_encounter = true
	if fault != &"":
		_light(fault)
	var start: float = _sim.nerves.value
	for _tick: int in int(1.0 / DT):
		_sim.car.x = _sim.car.lane_center(1)
		_sim.step(_input)
	return _sim.nerves.value - start


## Takes the gear lever and drags it back by half a gate unit of pointer
## travel; returns how far the lever moved.
func _lever_travel() -> float:
	_input.clear()
	_input.pointer_is_absolute = true
	_input.pointer = _sim.hand.anchor_pointer(_sim.hand.anchor_index(&"gear_lever"))
	for _tick: int in 80:
		_sim.step(_input)
	_input.pointer_is_absolute = false
	_input.lmb = true
	_sim.step(_input)
	_sim.step(_input)
	var start: Vector2 = _sim.gate.lever
	var pixels: float = tuning.f("gate_unit") * 0.5
	for _tick: int in 10:
		_input.pointer_delta = Vector2(0.0, pixels / 10.0)
		_sim.step(_input)
	_input.pointer_delta = Vector2.ZERO
	var moved: float = _sim.gate.lever.distance_to(start)
	_input.clear()
	return moved
