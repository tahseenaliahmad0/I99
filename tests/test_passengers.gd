extends CabinSuite
## M8: the five passengers of GDD 8. Each is met as a player meets them: at
## the roadside of a stop, let in by a TAP on the passenger door, asked for
## their Hand by a TAP on the shoulder, and carried as far as they ride.

const HITCHER_STOP: String = "hitcher"
const DOOR: String = "passenger_door"
const SHOULDER: String = "passenger_shoulder"
const BOARD_LINE: String = "board"
const ALL: PackedStringArray = ["hajjiya", "conscript", "drummer", "student", "apprentice"]


func _passenger(id: String) -> Dictionary:
	return data.record("passengers", id)


## The first Telling seed whose first leg ends (on the right branch) at a
## `stop_id` where `who` stands asking for a ride ("" for a stop with nobody).
func _telling_seed(who: String, stop_id: String = HITCHER_STOP) -> int:
	for candidate: int in range(1, 6000):
		if GameData.as_string(RunGenerator.fork(data, candidate, 1, 0)[RunState.RIGHT]["stop"]) == stop_id \
				and RunGenerator.hitcher(data, candidate, 1, 0, stop_id, "") == who:
			return candidate
	fail("no seed under 6000 whose first %s has '%s' at the roadside" % [stop_id, who])
	return 1


## A Telling of that seed on its first leg, with nothing on the road and the
## car in third gear.
func _to_first_leg(telling_seed: int) -> void:
	_sim = DriveSim.new(fresh_data())
	_events = []
	_keep_lane = true
	_input.clear()
	_sim.begin_telling(TABLE, telling_seed)
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


## He drives a Telling to the first stop, where `who` stands, and unlocks the
## passenger door.
func _pick_up(who: String, stop_id: String = HITCHER_STOP) -> void:
	_to_first_leg(_telling_seed(who, stop_id))
	_into_stall()
	_tap_at(DOOR)


## An empty endless road in a gear, with `who` in the seat ("" for nobody).
func _on_the_road(who: String, gear: int = 3) -> void:
	_new_sim()
	_cruise(gear, 1)
	if not who.is_empty():
		check(_sim.board(who), "(%s rides along)" % who)
	_events = []


## A TAP on the passenger's shoulder. Returns the tick in which it was made.
func _ask() -> int:
	_reach(SHOULDER)
	_input.lmb = true
	_ticks(TAP_TICKS)
	_input.lmb = false
	var guard: int = SETTLE * 2
	while _event("ritual_completed").is_empty() and guard > 0:
		guard -= 1
		_tick()
	var asked_at: int = _sim.tick
	_ticks(SETTLE)
	_input.clear()
	return asked_at


func _shot(key: String) -> Variant:
	return _sim.snapshot()[key]


## How much his Nerves change over `seconds` on the empty road.
func _nerves_over(seconds: float) -> float:
	var before: float = _sim.nerves.value
	_ticks(_ticks_in(seconds))
	return _sim.nerves.value - before


## To the stall of the leg he is on, and stopped there.
func _to_next_stop() -> void:
	_into_stall()


## Out of the stop and onto the next leg (the right branch), quiet.
func _on_to_next_leg() -> void:
	_leave_stop()
	_into_next_quiet_leg()


# --- What every passenger shares (GDD 8.1) -----------------------------------

## Boarding: a hitcher at the roadside, the passenger door, the seat.
func _check_boarding(who: String) -> void:
	var door: Dictionary = data.record("anchors", DOOR)
	check_near(GameData.as_float(door.get("time_s")), GameData.as_float(data.record("anchors", "glovebox").get("time_s")), 0.000001,
			"GDD 8.1: the passenger door is a glovebox-class Far reach")
	check_eq(GameData.as_string(data.record("stops", HITCHER_STOP).get("service")), "passenger", "a Hitcher stop offers one passenger")

	# Nobody at the roadside: the door is not there to be unlocked.
	_to_first_leg(_telling_seed("", "fuel_station"))
	_into_stall()
	check_eq(GameData.as_string(_shot("hitcher")), "", "(a fuel station with nobody at the roadside)")
	check(not _sim.hand.is_anchor_active(_sim.hand.anchor_index(StringName(DOOR))), "with nobody there the passenger door is not for unlocking")
	_events = []
	_tap_at(DOOR)
	check_eq(_count_events("passenger_boarded"), 0, "(and nobody gets in)")

	# At a Hitcher stop one stands and waits.
	_to_first_leg(_telling_seed(who))
	_give("thermos")
	check_eq(String(_item("thermos").slot), "seat", "(a thermos lies on the seat)")
	_into_stall()
	check_eq(_sim.run.stop, HITCHER_STOP, "(a Hitcher stop)")
	check_eq(GameData.as_string(_shot("hitcher")), who, "at a Hitcher stop a hitcher stands at the roadside")
	check_near(_sim.clock.minutes - _clock_at_stall, GameData.as_float(data.record("stops", HITCHER_STOP).get("clock_min")), 0.01, "the stop costs its 2 game minutes")
	check_eq(GameData.as_string(_shot("passenger")), "", "(the seat is empty)")
	check(not _sim.items.flag(PassengerSim.FLAG), "(nobody beside him)")
	check_near(_reach_time(DOOR), GameData.as_float(door.get("time_s")), 0.03, "he reaches across to the passenger door: a Far reach, 0.57 s from the wheel")
	_events = []
	_tap()
	check_eq(_count_events("ritual_completed", "ritual", StopSim.BOARD), 1, "a TAP unlocks it")
	check_eq(GameData.as_string(_event("passenger_boarded").get("passenger")), who, "and the hitcher gets in")
	check_eq(GameData.as_string(_shot("passenger")), who, "(the snapshot says who rides)")
	check(_sim.items.flag(PassengerSim.FLAG), "somebody is in the seat")
	check_eq(_count_events("line_requested", "id", "%s.%s" % [GameData.as_string(_passenger(who).get("line_prefix")), BOARD_LINE]), 1, "(with a word as they get in)")
	check_eq(GameData.as_string(_shot("hitcher")), "", "(nobody is left at the roadside)")
	check_eq(String(_item("thermos").slot), "back_seat", "they take the seat: what lay on it lies on the back seat")
	check_eq(_anchor_of("thermos"), "", "out of reach and out of use while they ride")
	check(not _sim.hand.is_anchor_active(_sim.hand.anchor_index(StringName(DOOR))), "at most one passenger: the door is not for unlocking again")
	check(_sim.stopped, "(he is still at the stop: boarding does not drive him off)")

	# Declining is leaving.
	_to_first_leg(_telling_seed(who))
	_into_stall()
	_events = []
	_leave_stop()
	check_eq(GameData.as_string(_shot("passenger")), "", "he declines by leaving: nobody rides")
	check_eq(_count_events("passenger_boarded"), 0, "(nobody got in)")

	# With somebody in the seat already, a hitcher stays at the roadside.
	_to_first_leg(_telling_seed(who))
	var other: String = "drummer" if who != "drummer" else "student"
	check(_sim.board(other), "(somebody rides already)")
	_into_stall()
	check(GameData.as_string(_shot("hitcher")) != "", "(a hitcher stands there all the same)")
	check(GameData.as_string(_shot("hitcher")) != other, "(never the one he carries)")
	check(not _sim.hand.is_anchor_active(_sim.hand.anchor_index(StringName(DOOR))), "with the seat taken the door stays locked")
	_events = []
	_tap_at(DOOR)
	check_eq(_count_events("passenger_boarded"), 0, "(nobody else gets in)")
	check(not _sim.board(who), "nobody can be put in a seat that is taken")
	check_eq(_count_events("passenger_boarded"), 0, "(nobody is)")
	check_eq(GameData.as_string(_shot("passenger")), other, "(the one he had rides on)")


## Where hitchers stand: always at a Hitcher stop, at hitcher_chance of the
## fuel stations and tea stalls, nowhere else; and all five of them somewhere.
func _check_where_hitchers_stand() -> void:
	var chance: float = tuning.f("hitcher_chance")
	check(chance > 0.0 and chance < 0.5, "GDD 8.1: hitchers stand sometimes at fuel stations and tea stalls (hitcher_chance = %.2f)" % chance)
	var met: Dictionary = {}
	var seen: Dictionary = {}
	var with_one: Dictionary = {}
	for candidate: int in range(1, 1501):
		var stop_id: String = GameData.as_string(RunGenerator.fork(data, candidate, 1, 0)[RunState.RIGHT]["stop"])
		var who: String = RunGenerator.hitcher(data, candidate, 1, 0, stop_id, "")
		seen[stop_id] = GameData.as_int(seen.get(stop_id)) + 1
		if not who.is_empty():
			with_one[stop_id] = GameData.as_int(with_one.get(stop_id)) + 1
			met[who] = GameData.as_int(met.get(who)) + 1
			check(ALL.has(who), "(seed %d: a hitcher is one of the five)" % candidate)
		check_eq(RunGenerator.hitcher(data, candidate, 1, 0, stop_id, ""), who, "(the same seed, the same hitcher)")
	check_eq(GameData.as_int(with_one.get(HITCHER_STOP)), GameData.as_int(seen.get(HITCHER_STOP)), "at every Hitcher stop one stands (%d of %d)" % [GameData.as_int(with_one.get(HITCHER_STOP)), GameData.as_int(seen.get(HITCHER_STOP))])
	check(GameData.as_int(seen.get(HITCHER_STOP)) > 50, "(and there are Hitcher stops)")
	for stop_id: String in ["fuel_station", "tea_stall"]:
		var stops: float = float(GameData.as_int(seen.get(stop_id)))
		var share: float = float(GameData.as_int(with_one.get(stop_id))) / maxf(stops, 1.0)
		check(absf(share - chance) <= 4.0 * sqrt(chance * (1.0 - chance) / maxf(stops, 1.0)), "at hitcher_chance of the %ss one stands (%.2f of %d)" % [stop_id, share, int(stops)])
	for stop_id: String in ["fitter", "roadside_find"]:
		check_eq(GameData.as_int(with_one.get(stop_id)), 0, "at a %s nobody stands" % stop_id)
	for who: String in ALL:
		check(GameData.as_int(met.get(who)) > 20, "the %s is met at the roadside (%d times in 1500 nights)" % [who, GameData.as_int(met.get(who))])
	check_eq(RunGenerator.hitcher(data, 5, 1, 0, "boss_stop", ""), "", "(and nobody at the stop after a boss)")
	# Whoever he carries does not stand at the roadside as well: another does.
	var would_be_them: int = 0
	for candidate: int in range(1, 201):
		var plain: String = RunGenerator.hitcher(data, candidate, 1, 0, HITCHER_STOP, "")
		for rider: String in ALL:
			var there: String = RunGenerator.hitcher(data, candidate, 1, 0, HITCHER_STOP, rider)
			check(there != rider and not there.is_empty(), "(seed %d: with the %s in the seat somebody else stands at a Hitcher stop)" % [candidate, rider])
			if plain == rider:
				would_be_them += 1
			else:
				check_eq(there, plain, "(seed %d: who stands there does not depend on who rides, unless it would be them)" % candidate)
	check(would_be_them > 100, "(the draw would have been the one he carries %d times in a thousand)" % would_be_them)


# --- T-PASS-HAJJIYA ----------------------------------------------------------

## T-PASS-HAJJIYA: The Hajjiya (8.2): on a tap she holds the wheel dead
## straight for up to 6 s; smoking or the flask adds 10 Nerves; in gear 4 or
## above she prays aloud, +3 Nerves per second; she rides 3 legs; on leaving,
## food once (-20 Nerves) and the first scrape after she leaves lights no
## lamp. She takes the seat and boards by a Far reach TAP on the passenger
## door (8.1).
func test_pass_hajjiya() -> void:
	var record: Dictionary = _passenger("hajjiya")
	var hand: Dictionary = GameData.as_dict(record.get("hand"))
	check_eq(GameData.as_string(hand.get("kind")), PassengerSim.HAND_STRAIGHT, "GDD 8.2: on a tap the Hajjiya holds the wheel dead straight")
	check_near(GameData.as_float(hand.get("duration_s")), 6.0, 0.000001, "for up to 6 s")
	check_eq(GameData.as_int(record.get("rides_legs")), 3, "she rides 3 legs")
	check_near(GameData.as_float(record.get("fare")), 0.0, 0.000001, "she pays no money")
	check_eq(GameData.as_array(record.get("on_leave")), ["nerves:-20", "add_effect:blessing"], "her fare is food once (-20 Nerves) and a blessing")
	var weights: Array = GameData.as_array(record.get("weights"))
	check_eq(weights.size(), 3, "(three Weights: smoking, the flask, her prayer)")
	_check_boarding("hajjiya")
	_check_where_hitchers_stand()
	_check_hajjiya_holds_the_wheel()
	_check_hajjiya_forbids()
	_check_hajjiya_prays()
	_check_hajjiya_rides_and_leaves()


func _check_hajjiya_holds_the_wheel() -> void:
	var seconds: float = GameData.as_float(GameData.as_dict(_passenger("hajjiya").get("hand")).get("duration_s"))
	# Hands off, the road's crown carries the car to the shoulder (GDD 5.4).
	_on_the_road("")
	_keep_lane = false
	var from_x: float = _sim.car.x
	_ticks(_ticks_in(seconds))
	var adrift: float = _sim.car.x - from_x
	check(adrift > 1.0, "hands off for 6 s, the car is carried %.2f m toward the shoulder" % adrift)

	# A TAP on her shoulder: she holds the wheel, and the car goes dead straight.
	_on_the_road("hajjiya")
	check_eq(GameData.as_int(_shot("wheel_held")), PassengerSim.HOLD_NONE, "(until she is asked she holds nothing)")
	check_near(_reach_time(SHOULDER), GameData.as_float(data.record("anchors", SHOULDER).get("time_s")), 0.03, "her shoulder is 0.53 s from the wheel")
	_events = []
	var asked_at: int = _ask()
	check_eq(_count_events("ritual_completed", "ritual", "passenger_ask"), 1, "a TAP on her shoulder asks for her Hand")
	check_eq(GameData.as_int(_shot("wheel_held")), PassengerSim.HOLD_STRAIGHT, "she holds the wheel")
	check_eq(_count_events("line_requested", "id", "passenger.hajjiya.hand"), 1, "(and says so)")
	_keep_lane = false
	_ticks(_ticks_in(0.5))
	from_x = _sim.car.x
	var widest: float = 0.0
	var guard: int = _ticks_in(seconds + 2.0)
	while GameData.as_int(_shot("wheel_held")) != PassengerSim.HOLD_NONE and guard > 0:
		guard -= 1
		_tick()
		widest = maxf(widest, absf(_sim.car.x - from_x))
	check(absi(_sim.tick - asked_at - _ticks_in(seconds)) <= 1, "for 6 s (%.3f s)" % (float(_sim.tick - asked_at) * DT))
	check(widest < 0.02, "dead straight: in those seconds the car moves %.3f m off its line" % widest)
	check(not _sim.hand.gripping, "(his own hand is off the wheel all the while)")
	# Then she lets go, and the road has him again.
	from_x = _sim.car.x
	_ticks(_ticks_in(2.0))
	check(_sim.car.x - from_x > 0.3, "after the 6 s she lets go: the car drifts again (%.2f m in 2 s)" % (_sim.car.x - from_x))

	# "Up to" 6 s: his own hand on the wheel ends it.
	_on_the_road("hajjiya")
	_ask()
	_ticks(_ticks_in(1.0))
	check_eq(GameData.as_int(_shot("wheel_held")), PassengerSim.HOLD_STRAIGHT, "(she holds it)")
	_grip()
	check_eq(GameData.as_int(_shot("wheel_held")), PassengerSim.HOLD_NONE, "when he takes the wheel himself she lets go: up to 6 s")
	check(_sim.wheel.gripped, "(the wheel is in his hand)")
	_release()

	# Straight is straight: a bend still carries the car out (GDD 5.4, D-051).
	_on_the_road("hajjiya")
	_ask()
	_keep_lane = false
	_sim.curve_k = 1.0
	from_x = _sim.car.x
	_ticks(_ticks_in(2.0))
	check(_sim.car.x - from_x > 0.5, "she holds it straight, she does not steer: a bend carries the car out all the same (%.2f m in 2 s)" % (_sim.car.x - from_x))

	# A steering that pulls is constant too (GDD 5.4): she holds against it as well.
	_on_the_road("hajjiya")
	_sim.faults.active.append(DriveSim.FAULT_PULL)
	_sim.faults.lamps = _sim.faults.active.size()
	_ask()
	_keep_lane = false
	_ticks(_ticks_in(0.5))
	from_x = _sim.car.x
	_ticks(_ticks_in(3.0))
	check(absf(_sim.car.x - from_x) < 0.02, "with a steering that pulls she holds the line all the same (%.3f m off it in 3 s)" % absf(_sim.car.x - from_x))

	# Nobody in the seat: there is no shoulder to tap.
	_on_the_road("")
	check(not _reach(SHOULDER), "with nobody in the seat there is no shoulder to tap")


## What a use does to his Nerves beyond what it does with nobody beside him.
func _dearer_with(who: String, item: String, slot: String, ritual: String) -> float:
	var changes: Array[float] = []
	for rider: String in ["", who]:
		_on_the_road(rider)
		if _item(item) == null:
			_give(item, slot)
		_sim.nerves.set_value(50.0)
		var anchor: String = _anchor_of(item)
		_reach(anchor)
		var before: float = _sim.nerves.value
		_hold(GameData.as_float(_ritual(ritual).get("hold_s")))
		check_eq(_count_events("ritual_completed", "ritual", ritual), 1, "(%s%s)" % [ritual, "" if rider.is_empty() else ", with her beside him"])
		changes.append(_sim.nerves.value - before)
	return changes[1] - changes[0]


func _check_hajjiya_forbids() -> void:
	var each: float = 0.0
	for entry: Variant in GameData.as_array(_passenger("hajjiya").get("weights")):
		var weight: Dictionary = GameData.as_dict(entry)
		if GameData.as_string(weight.get("when")) == "ritual_tag:smoke":
			each = GameData.as_float(weight.get("amount"))
	check_near(each, 10.0, 0.000001, "GDD 8.2: she forbids smoking and the flask: using either adds 10 Nerves")
	check_near(_dearer_with("hajjiya", "cigarettes", "ashtray", "cig_light"), each, 0.05, "lighting a cigarette beside her costs 10 Nerves more")
	check_eq(_count_events("line_requested", "id", "passenger.hajjiya.weight"), 1, "(she says what she thinks of it)")
	check_near(_dearer_with("hajjiya", "arak_flask", "cup_b", "flask_sip"), each, 0.05, "a sip from the flask beside her costs 10 Nerves more")
	check_near(_dearer_with("hajjiya", "tea_glass", "cup_a", "tea_sip"), 0.0, 0.05, "tea she does not mind")
	# Ashing the one that burns is not smoking another.
	_on_the_road("hajjiya")
	_hold_at("ashtray", GameData.as_float(_ritual("cig_light").get("hold_s")))
	_ticks(_ticks_in(1.0))
	_events = []
	var before: float = _sim.nerves.value
	_reach("ashtray")
	_flick(Vector2(0.0, tuning.f("flick_min_distance") * 1.5))
	check_eq(_count_events("ritual_completed", "ritual", "cig_ash"), 1, "(he ashes it)")
	check(_sim.nerves.value - before < 1.0, "ashing the cigarette that burns is not lighting another: no 10 Nerves")
	# She forbids it only while she is there.
	check_near(_dearer_with("student", "cigarettes", "ashtray", "cig_light"), 0.0, 0.05, "(another passenger does not mind a cigarette)")


func _check_hajjiya_prays() -> void:
	var rate: float = 0.0
	for entry: Variant in GameData.as_array(_passenger("hajjiya").get("weights")):
		var weight: Dictionary = GameData.as_dict(entry)
		if GameData.as_string(weight.get("when")) == "gear>=4":
			rate = GameData.as_float(weight.get("per_s"))
	check_near(rate, 3.0, 0.000001, "GDD 8.2: in gear 4 or above she prays aloud: +3 Nerves per second")
	var rise: Dictionary = {}
	for gear: int in [3, 4]:
		for rider: String in ["", "hajjiya"]:
			_on_the_road(rider, gear)
			_sim.nerves.set_value(40.0)
			rise["%d%s" % [gear, rider]] = _nerves_over(2.0)
			if gear == 4 and not rider.is_empty():
				check_eq(_count_events("line_requested", "id", "passenger.hajjiya.prayer"), 1, "(she is heard praying, once as she begins)")
			elif not rider.is_empty():
				check_eq(_count_events("line_requested", "id", "passenger.hajjiya.prayer"), 0, "(in third gear she is quiet)")
	check_near(GameData.as_float(rise["4hajjiya"]) - GameData.as_float(rise["4"]), rate * 2.0, 0.05, "in fourth gear her prayer adds 3 Nerves a second (6 in 2 s)")
	check_near(GameData.as_float(rise["3hajjiya"]) - GameData.as_float(rise["3"]), 0.0, 0.05, "in third gear it adds nothing")


func _check_hajjiya_rides_and_leaves() -> void:
	var rides: int = GameData.as_int(_passenger("hajjiya").get("rides_legs"))
	_pick_up("hajjiya")
	check_eq(GameData.as_string(_shot("passenger")), "hajjiya", "(she got in at the first stop)")
	check_eq(GameData.as_int(_shot("passenger_legs")), 0, "(no leg ridden yet)")
	# The second and the third leg of Act 1: at their stalls she stays in.
	for leg: int in [1, 2]:
		_on_to_next_leg()
		check_eq(GameData.as_string(_shot("passenger")), "hajjiya", "on the next leg she is beside him")
		_events = []
		_to_next_stop()
		check_eq(GameData.as_int(_shot("passenger_legs")), leg, "at its stall she has ridden %d of her %d legs" % [leg, rides])
		check_eq(GameData.as_string(_shot("passenger")), "hajjiya", "and stays in")
		check_eq(_count_events("passenger_left"), 0, "(she has not got out)")
		check_eq(GameData.as_string(GameData.as_dict(_sim.checkpoint.get("passenger")).get("id")), "hajjiya", "(the save made there knows who rides)")
		check_eq(GameData.as_int(GameData.as_dict(_sim.checkpoint.get("passenger")).get("legs")), leg, "(and how far)")
	# The act's boss is no leg: through it and the stop after it she rides on.
	_events = []
	_drive_on_to_act(2)
	check_eq(GameData.as_string(_shot("passenger")), "hajjiya", "a boss is not a leg: she rides through it")
	check_eq(_count_events("passenger_left"), 0, "(and through the stop after it)")
	check_eq(GameData.as_int(_shot("passenger_legs")), 2, "(two legs ridden still)")
	# The third leg: at its stall she gets out.
	_into_next_quiet_leg()
	_give("thermos")
	check_eq(String(_item("thermos").slot), "back_seat", "(what is bought for the seat while she rides goes behind it)")
	_sim.nerves.set_value(70.0)
	var before: float = _sim.nerves.value
	var cash: float = _sim.cash
	_events = []
	_to_next_stop()
	var left: Dictionary = _event("passenger_left")
	check_eq(GameData.as_string(left.get("passenger")), "hajjiya", "at the stall of her third leg she gets out")
	check_eq(GameData.as_string(left.get("reason")), "ride_over", "(her ride is over)")
	check_eq(GameData.as_string(_shot("passenger")), "", "the seat is empty again")
	check(not _sim.items.flag(PassengerSim.FLAG), "(nobody beside him)")
	check_eq(String(_item("thermos").slot), "seat", "what lay on the back seat is on the seat again")
	# (Read from the save made as he stopped: a tea stall would set his Nerves afresh.)
	check_near(Save.from_exact(GameData.as_dict(_sim.checkpoint.get("exact")).get("nerves"), -1.0), before - 20.0, 0.5, "food, once: -20 Nerves")
	check_near(_sim.cash, cash, 0.000001, "she pays no money")
	check_eq(_count_events("line_requested", "id", "passenger.hajjiya.leave"), 1, "(with a word)")
	check(GameData.as_bool(_shot("blessed")), "and she leaves him her blessing")
	check(GameData.as_bool(GameData.as_dict(_sim.checkpoint.get("passenger")).get("blessed")), "(the save keeps it)")
	check_eq(GameData.as_string(GameData.as_dict(_sim.checkpoint.get("passenger")).get("id")), "", "(and knows the seat is empty)")
	# The first scrape after she has left lights no lamp; the one after it does.
	_on_to_next_leg()
	check(GameData.as_bool(_shot("blessed")), "(the blessing is with him on the road)")
	var lamps: int = _sim.faults.lamps
	_events = []
	var hit: Dictionary = _scrape_rail()
	check_eq(GameData.as_int(hit.get("kind")), Collision.Hit.SCRAPE, "(a scrape)")
	check(GameData.as_bool(hit.get("spared")), "the first scrape after she has left is turned aside")
	check_eq(_sim.faults.lamps, lamps, "it lights no lamp")
	check(not GameData.as_bool(_shot("blessed")), "(the blessing is spent)")
	hit = _scrape_rail()
	check(not GameData.as_bool(hit.get("spared")), "the next scrape is a scrape")
	check_eq(_sim.faults.lamps, lamps + 1, "and lights its lamp")
	# Once: no second helping at the next stop.
	_sim.nerves.set_value(70.0)
	_events = []
	_to_next_stop()
	check_eq(_count_events("passenger_left"), 0, "food once: nothing more at the next stop")

	# A stall he drives past is a leg ridden all the same, but nobody gets
	# out of a moving car: she gets out where he next stops.
	_pick_up("hajjiya")
	_leave_stop()
	for leg: int in rides:
		if leg == rides - 1:
			# (The last of the three is the first leg of Act 2.)
			_drive_on_to_act(2)
		_into_next_quiet_leg()
		_sim.car.s = _sim.leg.length - tuning.f("leg_tail") + tuning.f("exit_slip_length") - 5.0
		_ticks(_ticks_in(1.0))
		check(not _sim.stopped, "(he drives past the stall)")
	check_eq(GameData.as_int(_shot("passenger_legs")), rides, "three stalls driven past are three legs ridden")
	check_eq(GameData.as_string(_shot("passenger")), "hajjiya", "but nobody gets out of a moving car: she is still beside him")
	_into_next_quiet_leg()
	_events = []
	_to_next_stop()
	check_eq(GameData.as_string(_event("passenger_left").get("passenger")), "hajjiya", "where he next stops she gets out")


## Drives the Telling on, each stretch to its end at once and out of every
## stop, to the last street; stands the car in the bay and turns the key.
## Returns the `arrived` event ({} if he never arrived).
func _on_to_basra() -> Dictionary:
	var guard: int = 80000
	_input.clear()
	while _sim.run.stage != RunState.Stage.ARRIVAL and guard > 0:
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
	check_eq(_sim.run.stage, RunState.Stage.ARRIVAL, "(the last street)")
	var street: Dictionary = GameData.as_dict(data.root("legs").get("arrival"))
	_sim.car.s = _sim.leg.length - GameData.as_float(street.get("bay_m")) * 0.5
	_sim.car.speed = 0.0
	_input.clear()
	_input.rmb = true
	_input.pointer_is_absolute = true
	_input.pointer = _sim.hand.anchor_pointer(_sim.hand.anchor_index(&"key"))
	guard = _ticks_in(3.0)
	while _sim.hand.at_id() != &"key" and guard > 0:
		guard -= 1
		_tick()
	_input.lmb = true
	_ticks(TAP_TICKS)
	_input.lmb = false
	_ticks(SETTLE)
	return _event("arrived")


## What a honk adds to a Patrol's Suspicion with `who` beside him.
func _suspicion_of_a_honk(who: String) -> float:
	_on_the_road(who)
	_sim.suspicion.begin_watch()
	_tick()
	_reach("horn")
	var most: float = 0.0
	_input.lmb = true
	for _index: int in TAP_TICKS + SETTLE:
		if _index == TAP_TICKS:
			_input.lmb = false
		_tick()
		most = maxf(most, _sim.suspicion.value)
	return most


# --- T-PASS-CONSCRIPT --------------------------------------------------------

## T-PASS-CONSCRIPT: The Conscript (8.2): his uniform halves all Suspicion
## gains; he sleeps and his snoring lowers Nerves by 0.5 per second; a tap or
## the horn wakes him for 20 s, and only then does a tap make him light a
## cigarette and hand it over with no ritual time; he rides to the end of the
## act; fare 10.
func test_pass_conscript() -> void:
	var record: Dictionary = _passenger("conscript")
	var sleeps: Dictionary = GameData.as_dict(record.get("sleeps"))
	var awake_s: float = GameData.as_float(sleeps.get("awake_s"))
	check_near(GameData.as_float(GameData.as_dict(record.get("always")).get("suspicion_gain_mult")), 0.5, 0.000001, "GDD 8.2: his uniform halves all Suspicion gains")
	check_near(awake_s, 20.0, 0.000001, "woken, he is awake for 20 s")
	check(GameData.as_bool(sleeps.get("horn_wakes")), "the horn wakes him too")
	check_eq(GameData.as_string(GameData.as_dict(record.get("hand")).get("kind")), PassengerSim.HAND_CIGARETTE, "his Hand is a cigarette, lit and handed over")
	check_eq(GameData.as_string(record.get("rides_until")), PassengerSim.RIDES_ACT_END, "he rides to the end of the act")
	check_near(GameData.as_float(record.get("fare")), 10.0, 0.000001, "fare 10")
	var snore: float = GameData.as_float(GameData.as_dict(GameData.as_array(record.get("weights"))[0]).get("per_s"))
	check_eq(GameData.as_string(GameData.as_dict(GameData.as_array(record.get("weights"))[0]).get("when")), "asleep", "(his Weight: he sleeps)")
	check_near(snore, -0.5, 0.000001, "his snoring lowers Nerves by 0.5 per second")

	# The uniform: every gain of Suspicion is half of what it is without him.
	var honk: float = tuning.f("suspicion_honk")
	check_near(_suspicion_of_a_honk(""), honk, 0.05, "(a honk under a Patrol's eyes: +15 Suspicion)")
	check_near(_suspicion_of_a_honk("conscript"), honk * 0.5, 0.05, "with him beside the driver the same honk is +7.5")
	var by_gear: Array[float] = []
	for rider: String in ["", "conscript"]:
		_on_the_road(rider, 4)
		_sim.suspicion.begin_watch()
		_ticks(_ticks_in(2.0))
		by_gear.append(_sim.suspicion.value)
	check_near(by_gear[0], tuning.f("suspicion_gear_rate") * 2.0, 0.2, "(fourth gear under a Patrol's eyes: 15 Suspicion a second)")
	check_near(by_gear[1], by_gear[0] * 0.5, 0.1, "with him, half of that: what counts by the second is halved too")
	# At a checkpoint as well: a barrier touched.
	var at_barrier: Array[float] = []
	for rider: String in ["", "conscript"]:
		_begin_checkpoint("", 1, false)
		if not rider.is_empty():
			_sim.board(rider)
		_cruise(1, 1)
		var corridor: Dictionary = GameData.as_dict(GameData.as_dict(data.record("bosses", BossSim.CHECKPOINT).get("checkpoint")).get("corridor"))
		_sim.car.s = GameData.as_float(corridor.get("at_m")) + 10.0
		_tick()
		_keep_lane = false
		_sim.car.x = _sim.car.lane_center(1) + GameData.as_float(corridor.get("gap_m")) * 0.5 - tuning.f("car_width") * 0.5 + 0.05
		_tick()
		at_barrier.append(_sim.suspicion.value)
		_keep_lane = true
	check(at_barrier[0] > 0.0, "(a barrier touched at the Checkpoint: Suspicion)")
	check_near(at_barrier[1], at_barrier[0] * 0.5, 0.000001, "all Suspicion gains: the Checkpoint's are halved too")

	# He sleeps, and snores.
	_on_the_road("")
	_sim.nerves.set_value(60.0)
	var alone: float = _nerves_over(4.0)
	_on_the_road("conscript")
	check(GameData.as_bool(_shot("passenger_asleep")), "he gets in and falls asleep")
	_sim.nerves.set_value(60.0)
	check_near(_nerves_over(4.0) - alone, snore * 4.0, 0.05, "his snoring lowers Nerves by 0.5 a second (2 in 4 s)")

	# Asleep, his Hand does not work: a tap only wakes him.
	var pack: int = _item("cigarettes").supply
	_events = []
	var woken_at: int = _ask()
	check_eq(_count_events("ritual_completed", "ritual", "passenger_ask"), 1, "(a TAP on his shoulder)")
	check(not GameData.as_bool(_shot("passenger_asleep")), "a tap wakes him")
	check_near(GameData.as_float(_shot("passenger_awake_left")), awake_s, float(SETTLE + 2) * DT, "for 20 s")
	check_eq(_count_events("line_requested", "id", "passenger.conscript.wake"), 1, "(he says he was awake)")
	check(not _item("cigarettes").burning and not _sim.effects.has_own(&"lit"), "the tap that wakes him lights nothing: only then does his Hand work")
	# Awake he does not snore.
	_sim.nerves.set_value(60.0)
	check_near(_nerves_over(2.0) - alone * 0.5, 0.0, 0.05, "awake, he does not snore")
	# Now a tap is a cigarette, lit and in the ashtray at once.
	_events = []
	var nerves_then: float = _sim.nerves.value
	var asked_at: int = _ask()
	check(_item("cigarettes").burning and _sim.effects.has_own(&"lit"), "awake, a tap makes him light a cigarette and hand it over")
	check_eq(_item("cigarettes").supply, pack, "it is his cigarette: the driver's pack is as full as it was")
	check_eq(_count_events("ritual_completed", "ritual", "cig_light"), 0, "with no ritual: the driver's hand lit nothing")
	check(float(_sim.tick - asked_at) * DT < 0.1, "and no ritual time: it burns from the tap, not after the lighter's %.1f s" % GameData.as_float(_ritual("cig_light").get("hold_s")))
	check_eq(_count_events("line_requested", "id", "passenger.conscript.hand"), 1, "(with a word)")
	check(_sim.effects.has(DriveSim.AWAKE), "(a lit cigarette keeps the driver awake, as his own does)")
	_ticks(_ticks_in(5.0))
	var calm: float = GameData.as_float(GameData.as_dict(GameData.as_array(_record("cigarettes").get("gives"))[1]).get("amount"))
	var burn: float = GameData.as_float(GameData.as_dict(GameData.as_array(_record("cigarettes").get("gives"))[1]).get("over"))
	check_near(_sim.nerves.value - nerves_then, calm * 5.0 / burn, 0.3, "and calms as his own does: -10 Nerves over its burn (-2 in 5 s)")
	# While it burns he has no second one to hand over.
	_events = []
	_ask()
	check_eq(_count_events("line_requested", "id", "passenger.conscript.hand"), 0, "while that one burns he hands over no second")
	# 20 s after the tap that woke him he is asleep again.
	var guard: int = _ticks_in(awake_s + 2.0)
	while not GameData.as_bool(_shot("passenger_asleep")) and guard > 0:
		guard -= 1
		_tick()
	check(absi(_sim.tick - woken_at - _ticks_in(awake_s)) <= 1, "20 s after he was woken he sleeps again (%.3f s)" % (float(_sim.tick - woken_at) * DT))

	# The horn wakes him as well.
	_on_the_road("conscript")
	_events = []
	_tap_at("horn")
	check_eq(_count_events("ritual_completed", "ritual", "horn"), 1, "(the horn)")
	check(not GameData.as_bool(_shot("passenger_asleep")), "the horn wakes him")
	check_near(GameData.as_float(_shot("passenger_awake_left")), awake_s, float(SETTLE + 2) * DT, "for 20 s")
	_ask()
	check(_item("cigarettes").burning, "and woken by the horn his Hand works")
	# Nothing else does: a wiper, a gear change.
	_on_the_road("conscript")
	_wipe()
	_sim.gate.reset(4)
	_ticks(_ticks_in(1.0))
	check(GameData.as_bool(_shot("passenger_asleep")), "the wipers and the gears do not wake him")

	# He rides to the end of the act, and pays 10.
	var cash_without: float = 0.0
	for takes_him: bool in [false, true]:
		_to_first_leg(_telling_seed("conscript"))
		_into_stall()
		if takes_him:
			_tap_at(DOOR)
			check_eq(GameData.as_string(_shot("passenger")), "conscript", "(he gets in at the first stop of Act 1)")
		for _leg: int in 2:
			_on_to_next_leg()
			_events = []
			_to_next_stop()
			if takes_him:
				check_eq(GameData.as_string(_shot("passenger")), "conscript", "at the stalls of the act's legs he sleeps on")
				check_eq(_count_events("passenger_left"), 0, "(he does not get out)")
		_events = []
		_drive_on_to_act(2)
		if not takes_him:
			cash_without = _sim.cash
			continue
		var left: Dictionary = _event("passenger_left")
		check_eq(GameData.as_string(left.get("passenger")), "conscript", "at the stop after the act's boss he gets out: the end of the act")
		check_near(GameData.as_float(left.get("fare")), 10.0, 0.000001, "and pays his fare")
		check_eq(_count_events("passenger_left"), 1, "(once)")
		check_eq(GameData.as_string(_shot("passenger")), "", "the seat is empty in Act 2")
		check_near(_sim.cash - cash_without, 10.0, 0.000001, "fare 10: the night is 10 richer than the same night without him")
		check_near(_sim.suspicion.gain_mult, 1.0, 0.000001, "(and his uniform has gone with him)")

	# What the review of M8 found (RULES-04, -05, -08, -09).
	_check_a_snap_wakes_him()


## The number of a ritual's "nerves:<n>" op.
func _nerves_of(ritual_id: String) -> float:
	for op: Variant in GameData.as_array(_ritual(ritual_id).get("on_complete")):
		if GameData.as_string(op).begins_with("nerves:"):
			return GameData.as_string(op).substr(7).to_float()
	return 0.0


## A Snap is two seconds of his horn (GDD 6.1: "he leans on the horn for
## 2 s"), and the horn wakes the soldier (GDD 8.2). On the road: where the
## night waits nothing of a passenger runs, and the horn's own TAP is not
## offered either.
func _check_a_snap_wakes_him() -> void:
	var awake_s: float = GameData.as_float(GameData.as_dict(_passenger("conscript").get("sleeps")).get("awake_s"))
	var slap: float = _nerves_of("slap")
	_on_the_road("conscript")
	check(GameData.as_bool(_shot("passenger_asleep")), "(he sleeps)")
	_sim.nerves.set_value(tuning.f("snap_at") - slap * 0.5)
	_reach("face")
	_events = []
	_tap()
	check_eq(_count_events("snap"), 1, "(a slap too many: a Snap)")
	check_eq(_count_events("sfx_requested", "id", "horn"), 1, "(he leans on the horn)")
	check_eq(_count_events("ritual_completed", "ritual", "horn"), 0, "(not by a TAP on it)")
	check(not GameData.as_bool(_shot("passenger_asleep")), "the two seconds of horn of a Snap wake the soldier")
	check_near(GameData.as_float(_shot("passenger_awake_left")), awake_s, float(TAP_TICKS + SETTLE + 2) * DT, "for his 20 s")
	check_eq(_count_events("line_requested", "id", "passenger.conscript.wake"), 1, "(and he says he was awake)")
	# When the Snap lets his hand go, one tap is a cigarette: the horn did the waking.
	_ticks(_ticks_in(tuning.f("snap_duration")))
	check(not GameData.as_bool(_shot("snap")), "(the Snap is over)")
	_events = []
	_ask()
	check(_item("cigarettes").burning, "woken by the Snap, the first tap on his shoulder is a cigarette")
	check_eq(_count_events("line_requested", "id", "passenger.conscript.wake"), 0, "(not a second waking)")
	# With an officer at his window the night waits for the soldier too. A
	# Snap can still begin there: the weather cramp is the hand's and runs on
	# (D-055), and its Nerves can be the last. That Snap wakes nobody.
	_begin_quiet_leg("rain", 1, 3)
	check(_sim.board("conscript"), "(he rides along on a Rain leg)")
	_sim.car.s = _sim.leg.length * tuning.f("phantom_cramp_at") - 1.0
	var guard: int = _ticks_in(2.0)
	while GameData.as_string(_shot("cramp")) != DriveSim.HUM and guard > 0:
		guard -= 1
		_tick()
	check_eq(GameData.as_string(_shot("cramp")), DriveSim.HUM, "(the hum of the weather cramp)")
	_sim.suspicion.begin_watch()
	# (His uniform halves what is added: twice the top takes it to the top.)
	_sim.suspicion.add(tuning.f("suspicion_max") / _sim.suspicion.gain_mult)
	_tick()
	check(GameData.as_bool(_shot("pulled_over")), "(and in the same breath he is pulled over)")
	check(GameData.as_bool(_shot("passenger_asleep")), "(the soldier sleeps)")
	_sim.nerves.set_value(tuning.f("snap_at") - tuning.f("phantom_cramp_nerves") * 0.5)
	_events = []
	_ticks(_ticks_in(tuning.f("phantom_cramp_hum")) + 2)
	check_eq(_count_events("snap"), 1, "(the cramp bites while the officer waits: a Snap)")
	check(GameData.as_bool(_shot("pulled_over")), "(the officer is still at his window)")
	check(GameData.as_bool(_shot("passenger_asleep")), "with the officer at the window a Snap does not wake him: nothing of a passenger runs there")
	check_eq(_count_events("line_requested", "id", "passenger.conscript.wake"), 0, "(and he says nothing)")


# --- T-PASS-DRUMMER ----------------------------------------------------------

## T-PASS-DRUMMER: The Drummer (8.2): while he drums, the music effect
## without the radio, and Awake; a tap toggles the drumming; on a tap he
## passes the tea so sipping becomes an at-wheel reach; his drum blocks the
## right 10% of the view; drumming during a Patrol adds 10 Suspicion per
## second; he rides to Basra and pays nothing.
func test_pass_drummer() -> void:
	var record: Dictionary = _passenger("drummer")
	var music_rate: float = tuning.f("radio_music_rate")
	check_eq(GameData.as_array(GameData.as_dict(record.get("drums")).get("effects")), ["music", "awake"], "GDD 8.2: while he drums, music and Awake")
	check_eq(GameData.as_string(GameData.as_dict(record.get("hand")).get("kind")), PassengerSim.HAND_TEA, "on a tap he passes the tea")
	check_near(GameData.as_float(record.get("view_block_right")), 0.10, 0.000001, "his drum blocks the right 10% of the view")
	check_eq(GameData.as_string(record.get("rides_until")), PassengerSim.RIDES_BASRA, "he rides to Basra")
	check_near(GameData.as_float(record.get("fare")), 0.0, 0.000001, "and pays nothing")
	var patrol: Dictionary = GameData.as_dict(GameData.as_array(record.get("weights"))[0])
	check_eq(GameData.as_string(patrol.get("when")), "drumming&patrol", "(his Weight: the drum under a Patrol's ears)")
	check_near(GameData.as_float(patrol.get("per_s")), 10.0, 0.000001, "drumming during a Patrol adds 10 Suspicion per second")

	# He gets in drumming: music without the radio, and Awake.
	_on_the_road("")
	_sim.nerves.set_value(60.0)
	var alone: float = _nerves_over(4.0)
	check(not _sim.effects.has(ItemSim.MUSIC) and not _sim.effects.has(DriveSim.AWAKE), "(alone on a silent road: no music, nothing to keep him awake)")
	_on_the_road("drummer")
	check(GameData.as_bool(_shot("passenger_drumming")), "he gets in drumming")
	check_eq(_sim.items.radio, ItemSim.STATIC, "(the radio is silent)")
	check(_sim.effects.has(ItemSim.MUSIC), "while he drums there is music without the radio")
	check(_sim.effects.has(DriveSim.AWAKE), "and the driver is Awake")
	_sim.nerves.set_value(60.0)
	check_near(_nerves_over(4.0) - alone, music_rate * 4.0, 0.05, "the music effect: it calms as the radio's music does (-0.5 a second)")
	# Music is music once: with the radio on music as well, no more than that.
	_sim.items.set_radio(ItemSim.MUSIC)
	_sim.nerves.set_value(60.0)
	check_near(_nerves_over(4.0) - alone, music_rate * 4.0, 0.05, "with the radio on music too it is still one music")
	# The beads answer to his drum as they do to the radio (GDD 7.8).
	_on_the_road("drummer")
	_give("beads")
	check(not _sim.items.pair("bead_calm").is_empty(), "what answers to music answers to his drum (the beads)")

	# A tap stops the drum: no music, no Awake, and the tea is held out to him.
	_on_the_road("drummer")
	var tea_anchor: String = _anchor_of("tea_glass")
	var far: float = _reach_time(tea_anchor)
	check_near(far, GameData.as_float(data.record("anchors", tea_anchor).get("time_s")), 0.03, "(the tea is in its cup holder, %.2f s from the wheel)" % far)
	_events = []
	_ask()
	check(not GameData.as_bool(_shot("passenger_drumming")), "a tap stops the drumming")
	check(not _sim.effects.has(ItemSim.MUSIC) and not _sim.effects.has(DriveSim.AWAKE), "and with it the music and Awake")
	check_eq(_count_events("line_requested", "id", "passenger.drummer.hand"), 1, "(he passes the tea, with a word)")
	_sim.nerves.set_value(60.0)
	check_near(_nerves_over(4.0) - alone, 0.0, 0.05, "(no music: no calm)")
	var moves: Dictionary = _shot("anchor_moves")
	check_eq(GameData.as_vec3(moves.get(tea_anchor)), GameData.as_vec3(GameData.as_dict(record.get("hand")).get("at")), "the tea is held out to him beside the wheel")
	var near: float = _reach_time(tea_anchor)
	check(near < GameData.as_float(data.record("anchors", "horn").get("time_s")), "sipping becomes an at-wheel reach: %.2f s, nearer than the horn" % near)
	check(near < far * 0.5, "(from %.2f s)" % far)
	_events = []
	_hold(GameData.as_float(_ritual("tea_sip").get("hold_s")))
	check_eq(_count_events("ritual_completed", "ritual", "tea_sip"), 1, "and he sips it there")
	# The next tap: the tea goes back, the drum begins again.
	_events = []
	_ask()
	check(GameData.as_bool(_shot("passenger_drumming")), "a tap toggles the drumming: he drums again")
	check(_sim.effects.has(ItemSim.MUSIC) and _sim.effects.has(DriveSim.AWAKE), "(music and Awake again)")
	check(not GameData.as_dict(_shot("anchor_moves")).has(tea_anchor), "and the tea is back in its holder")
	check_near(_reach_time(tea_anchor), far, 0.03, "(as far away as it was)")

	# The drum is in the way whether he plays it or not.
	_on_the_road("")
	check_near(GameData.as_float(_shot("view_block_right")), 0.0, 0.000001, "(alone, nothing blocks his view)")
	_on_the_road("drummer")
	check_near(GameData.as_float(_shot("view_block_right")), 0.10, 0.000001, "his drum blocks the right 10% of the view")
	_ask()
	check_near(GameData.as_float(_shot("view_block_right")), 0.10, 0.000001, "silent or not")

	# Under a Patrol's ears: 10 Suspicion a second while he drums.
	_on_the_road("drummer")
	_sim.suspicion.begin_watch()
	_ticks(_ticks_in(2.0))
	check_near(_sim.suspicion.value, GameData.as_float(patrol.get("per_s")) * 2.0, 0.2, "drumming during a Patrol adds 10 Suspicion a second (20 in 2 s)")
	_ask()
	var silent_from: float = _sim.suspicion.value
	_ticks(_ticks_in(2.0))
	check(_sim.suspicion.value <= silent_from, "silent, he adds none")
	_on_the_road("drummer")
	_ticks(_ticks_in(2.0))
	check_near(_sim.suspicion.value, 0.0, 0.000001, "with no Patrol there is nobody to mind")

	# He rides to Basra: through every stop of the night, and is a guest there.
	_pick_up("drummer")
	check_eq(GameData.as_string(_shot("passenger")), "drummer", "(he gets in at the first stop)")
	var cash: float = _sim.cash
	_events = []
	var arrived: Dictionary = _on_to_basra()
	check_eq(_count_events("passenger_left"), 0, "he gets out at no stop of the night")
	check(not arrived.is_empty(), "(the night ends in Basra)")
	check_eq(GameData.as_string(arrived.get("guest")), "drummer", "he rides to Basra: he is a wedding guest (GDD 8.1)")
	_pick_up("drummer")
	_leave_stop()
	check_near(_sim.cash, cash, 0.000001, "he pays nothing")
	# Nobody carried: no guest.
	_to_first_leg(_telling_seed("drummer"))
	check_eq(GameData.as_string(_on_to_basra().get("guest")), "", "(with nobody in the seat at the end there is no guest)")

	# What the review of M8 found (RULES-05, -10, -11).
	_check_one_music()
	_check_tea_only_where_there_is_tea()


## He passes the tea, and says so, only when a tea glass stands in a cup
## holder; with none the tap stops and starts the drum and nothing else.
func _check_tea_only_where_there_is_tea() -> void:
	var tea_line: String = "passenger.drummer.hand"
	var drum_line: String = "passenger.drummer.drum"
	# Another drink has taken the tea's place: there is no tea in the car.
	_on_the_road("drummer")
	_give("energy_drink", "cup_a")
	check(_item("tea_glass") == null, "(an energy drink stands where the tea stood: no tea in the car)")
	_events = []
	_ask()
	check(not GameData.as_bool(_shot("passenger_drumming")), "with no tea in the car a tap still stops the drum")
	check_eq(_count_events("line_requested", "id", tea_line), 0, "but he does not say \"your tea\" over a tea that is not there")
	check(not GameData.as_bool(_shot("tea_passed")), "and nothing is said to be held out")
	check(GameData.as_dict(_shot("anchor_moves")).is_empty(), "(no drink is moved: the can stays in its holder)")
	_events = []
	_ask()
	check(GameData.as_bool(_shot("passenger_drumming")), "the next tap starts the drum again")
	check_eq(_count_events("line_requested", "id", drum_line), 1, "(and that is said)")
	check_eq(_count_events("line_requested", "id", tea_line), 0, "(still no word of tea)")
	# A tea in the other cup holder is a tea to pass.
	_on_the_road("drummer")
	_give("tea_glass", "cup_b")
	check_eq(_anchor_of("tea_glass"), "cup_b", "(the tea stands in the far cup holder)")
	_events = []
	_ask()
	check_eq(_count_events("line_requested", "id", tea_line), 1, "a tea in either cup holder he passes, with his word")
	check(GameData.as_bool(_shot("tea_passed")), "(it is held out)")
	check_eq(GameData.as_vec3(GameData.as_dict(_shot("anchor_moves")).get("cup_b")), GameData.as_vec3(GameData.as_dict(_passenger("drummer").get("hand")).get("at")), "(beside the wheel)")
	# The tea is taken away while he holds it out (the can put in its place): he holds out nothing.
	_give("energy_drink", "cup_b")
	_tick()
	check(not GameData.as_bool(_shot("tea_passed")), "when the tea is gone from the car he holds out nothing")
	check(GameData.as_dict(_shot("anchor_moves")).is_empty(), "(and the can that took its place stays in the holder)")


## Nerves by the second on the empty road with what plays: his drum, the
## radio tuned to music by the dial, a mixtape in the deck; the window wound
## down by its crank.
func _music_calm(drums: bool, radio: bool, tape: bool, window: bool) -> float:
	_on_the_road("drummer" if drums else "")
	if tape:
		_give("mixtape")
	if window:
		_reach("window_crank")
		_crank(GameData.as_float(_ritual("window_crank").get("turns")))
		check(_sim.items.flag(ItemSim.FLAG_WINDOW), "(he winds the window down)")
	if radio:
		_tune(tuning.a("radio_stations").find("music") + 1)
		check_eq(_sim.items.radio, ItemSim.MUSIC, "(he tunes the radio to music)")
	_ticks(2)
	_sim.nerves.set_value(60.0)
	return _nerves_over(4.0) / 4.0


## The drum is "the music effect without the radio" (GDD 8.2): one music with
## whatever else plays, never weaker for the radio being on (an open window
## halves what comes out of the dash, GDD 4.6, not a drum), never a second
## music beside a tape.
func _check_one_music() -> void:
	var music: float = tuning.f("radio_music_rate")
	var open: float = tuning.f("window_radio_mult")
	var tape: float = 0.0
	for give: Variant in GameData.as_array(_record("mixtape").get("gives")):
		var entry: Dictionary = GameData.as_dict(give)
		if GameData.as_string(entry.get("resource")) == "nerves" and GameData.as_string(entry.get("while")) == "playing":
			tape = GameData.as_float(entry.get("per_s"))
	check(tape < music and music < 0.0 and open < 1.0, "(a tape calms more than the radio's music, and an open window lets some of either out)")
	var silent: float = _music_calm(false, false, false, false)
	check_near(_music_calm(true, false, false, false) - silent, music, 0.01, "his drum alone is the music effect: %.2f Nerves a second" % music)
	check_near(_music_calm(true, true, false, false) - silent, music, 0.01, "his drum and the radio's music are one music")
	check_near(_music_calm(true, false, false, true) - silent, music, 0.01, "an open window lets none of his drum out")
	check_near(_music_calm(false, true, false, true) - silent, music * open, 0.01, "(the radio's music through an open window is %.2f)" % (music * open))
	check_near(_music_calm(true, true, false, true) - silent, music, 0.01, "the drum is never weaker for the radio being on: with the window open the two are still the drum's %.2f" % music)
	check_near(_music_calm(false, false, true, false) - silent, tape, 0.01, "(a mixtape alone is %.2f)" % tape)
	check_near(_music_calm(true, false, true, false) - silent, tape, 0.01, "beside a tape the drum is no second music: the stronger of the two, not their sum")
	check_near(_music_calm(false, false, true, true) - silent, tape * open, 0.01, "(the tape through an open window is %.2f)" % (tape * open))
	check_near(_music_calm(true, false, true, true) - silent, minf(tape * open, music), 0.01, "the tape through an open window and his drum: one music still, the stronger")


# --- T-PASS-STUDENT ----------------------------------------------------------

## T-PASS-STUDENT: The Student (8.2): she answers every call for him (the
## cash without the hand); fork signs show 5 s earlier; she talks: Awake;
## each scrape adds 5 Nerves; gear 4 in rain adds 2 Nerves per second; she
## rides 3 legs; fare 20.
func test_pass_student() -> void:
	var record: Dictionary = _passenger("student")
	var always: Dictionary = GameData.as_dict(record.get("always"))
	check(GameData.as_bool(always.get("answers_calls")), "GDD 8.2: she answers every call for him")
	check_near(GameData.as_float(always.get("fork_sign_lead_s")), 5.0, 0.000001, "fork signs show 5 s earlier")
	check_eq(GameData.as_array(always.get("effects")), ["awake"], "she talks: Awake")
	check_eq(GameData.as_int(record.get("rides_legs")), 3, "she rides 3 legs")
	check_near(GameData.as_float(record.get("fare")), 20.0, 0.000001, "fare 20")
	var scrape: float = 0.0
	var rain: float = 0.0
	for entry: Variant in GameData.as_array(record.get("weights")):
		var weight: Dictionary = GameData.as_dict(entry)
		if GameData.as_string(weight.get("when")) == "scrape":
			scrape = GameData.as_float(weight.get("amount"))
		elif GameData.as_string(weight.get("when")) == "gear>=4&rain":
			rain = GameData.as_float(weight.get("per_s"))
	check_near(scrape, 5.0, 0.000001, "each scrape adds 5 Nerves")
	check_near(rain, 2.0, 0.000001, "gear 4 in rain adds 2 Nerves per second")

	# Calls: with her beside him every call is answered as it rings.
	var phone: Dictionary = GameData.as_dict(_record("phone").get("params"))
	var every: int = GameData.as_int(phone.get("family_every"))
	_on_the_road("student")
	_give("phone")
	_sim.suspicion.begin_watch()
	var cash: float = _sim.cash
	var rang: int = 0
	var guard: int = _ticks_in(400.0)
	_events = []
	while rang < every and guard > 0:
		guard -= 1
		var before: float = _sim.nerves.value
		_tick()
		if _count_events("call_started") > rang:
			rang += 1
			var resolved: Dictionary = _event("call_resolved")
			check_eq(_count_events("call_resolved"), rang, "call %d: answered in the tick it rings" % rang)
			check(GameData.as_bool(resolved.get("answered")) and GameData.as_bool(resolved.get("for_him")), "(by her, for him)")
			check_eq(GameData.as_string(_shot("caller")), "", "(the phone is silent again)")
			if rang < every:
				check_near(GameData.as_float(resolved.get("cash")), GameData.as_float(phone.get("dispatcher_cash")), 0.000001, "the dispatcher's fare is his: +10")
			else:
				check_eq(GameData.as_string(resolved.get("caller")), String(ItemSim.CALLER_FAMILY), "(every fourth call is his family)")
				check_near(_sim.nerves.value - before, GameData.as_float(phone.get("family_nerves")), 0.2, "and that call's calm is his too: -8 Nerves")
	check_eq(rang, every, "(four calls came)")
	check_near(_sim.cash - cash, GameData.as_float(phone.get("dispatcher_cash")) * float(every - 1), 0.000001, "the cash without the hand: 30 from three fares")
	check_eq(_count_events("ritual_completed", "ritual", "phone_answer"), 0, "his hand never touched the phone")
	check_near(_sim.suspicion.value, 0.0, 0.000001, "and a Patrol saw no phone in it: no Suspicion")
	# Without her the phone rings out.
	_on_the_road("")
	_give("phone")
	_events = []
	guard = _ticks_in(120.0)
	while _count_events("call_resolved") == 0 and guard > 0:
		guard -= 1
		_tick()
	check(not GameData.as_bool(_event("call_resolved").get("answered")), "without her a call nobody answers is missed")
	# The Call is his own to take (GDD 10.4): she holds the phone only if he hands it to her.
	_begin_quiet_boss(BossSim.DAWN)
	_sim.board("student")
	_sim.car.s = GameData.as_float(data.record("bosses", BossSim.DAWN).get("length_m")) - GameData.as_float(GameData.as_dict(GameData.as_dict(data.record("bosses", BossSim.DAWN).get("dawn")).get("call")).get("from_end_m")) - 2.0
	guard = _ticks_in(5.0)
	while _sim.boss.call != BossSim.CALL_RINGING and guard > 0:
		guard -= 1
		_tick()
	_ticks(_ticks_in(1.0))
	check_eq(_sim.boss.call, BossSim.CALL_RINGING, "Noor's call she does not answer for him: it rings until he takes it")
	_events = []
	_drag("pocket", SHOULDER)
	check_eq(GameData.as_string(_event("call_resolved").get("taken")), BossSim.TAKEN_WITH_PASSENGER, "handed to her, she holds it to his ear (GDD 8.1: any passenger can)")

	# She talks: Awake, all the time she rides.
	_on_the_road("")
	check(not _sim.effects.has(DriveSim.AWAKE), "(alone: nothing keeps him awake)")
	_on_the_road("student")
	check(_sim.effects.has(DriveSim.AWAKE), "she talks: he is Awake")
	_ticks(_ticks_in(60.0))
	check(_sim.effects.has(DriveSim.AWAKE), "(a minute on, still)")

	# She watches the road: each scrape is 5 Nerves more.
	var frayed: Array[float] = []
	for rider: String in ["", "student"]:
		_on_the_road(rider)
		_sim.nerves.set_value(30.0)
		var before: float = _sim.nerves.value
		var hit: Dictionary = _scrape_rail()
		check_eq(GameData.as_int(hit.get("kind")), Collision.Hit.SCRAPE, "(a scrape)")
		frayed.append(_sim.nerves.value - before)
		if not rider.is_empty():
			check_eq(_count_events("line_requested", "id", "passenger.student.weight"), 1, "(and she says so)")
			before = _sim.nerves.value
			_scrape_rail()
			check_near(_sim.nerves.value - before, frayed[1], 0.3, "each scrape: the next one too")
	check_near(frayed[1] - frayed[0], scrape, 0.2, "with her beside him a scrape frays him 5 Nerves more")

	# Fourth gear in the rain: 2 Nerves a second.
	var rise: Dictionary = {}
	for wet: bool in [false, true]:
		for gear: int in [3, 4]:
			for rider: String in ["", "student"]:
				if wet:
					_begin_quiet_leg("rain", 1, 3)
					if not rider.is_empty():
						_sim.board(rider)
					_cruise(gear, 1)
				else:
					_on_the_road(rider, gear)
				if wet:
					check(GameData.as_bool(_shot("raining")), "(it rains)")
				_sim.nerves.set_value(40.0)
				rise["%s%d%s" % ["wet" if wet else "dry", gear, rider]] = _nerves_over(2.0)
	check_near(GameData.as_float(rise["wet4student"]) - GameData.as_float(rise["wet4"]), rain * 2.0, 0.05, "fourth gear in the rain: with her, 2 Nerves a second more (4 in 2 s)")
	check_near(GameData.as_float(rise["wet3student"]) - GameData.as_float(rise["wet3"]), 0.0, 0.05, "third gear in the rain: nothing")
	check_near(GameData.as_float(rise["dry4student"]) - GameData.as_float(rise["dry4"]), 0.0, 0.05, "fourth gear on a dry road: nothing")

	# Fork signs stand 5 s further ahead of the fork.
	var lead: float = GameData.as_float(always.get("fork_sign_lead_s")) * tuning.fi("gear_speeds", 2) / 3.6
	var ahead: Array[float] = []
	for rider: String in ["", "student"]:
		_to_first_leg(_telling_seed("student"))
		if not rider.is_empty():
			_sim.board(rider)
		_sim.car.s = _sim.leg.length - 400.0
		_tick()
		var found: float = -1.0
		var signs: Array[Dictionary] = _shot("signs")
		for road_sign: Dictionary in signs:
			if GameData.as_string(road_sign.get("kind")) == "fork":
				found = GameData.as_float(road_sign.get("ahead"))
		check(found >= 0.0, "(the fork's sign is ahead%s)" % ("" if rider.is_empty() else ", with her"))
		ahead.append(found)
	check_near(ahead[0] - ahead[1], lead, 0.01, "with her the fork's sign stands 5 s of road earlier (%.0f m)" % lead)

	# She rides 3 legs and pays 20.
	_pick_up("student")
	check_eq(GameData.as_string(_shot("passenger")), "student", "(she gets in at the first stop)")
	for leg: int in [1, 2]:
		_on_to_next_leg()
		_events = []
		_to_next_stop()
		check_eq(GameData.as_int(_shot("passenger_legs")), leg, "at the next stall she has ridden %d" % leg)
		check_eq(_count_events("passenger_left"), 0, "and rides on")
	_events = []
	_drive_on_to_act(2)
	check_eq(_count_events("passenger_left"), 0, "the boss is no leg: she rides through it")
	_into_next_quiet_leg()
	var before_stop: float = _sim.cash
	_events = []
	_to_next_stop()
	var left: Dictionary = _event("passenger_left")
	check_eq(GameData.as_string(left.get("passenger")), "student", "at the stall of her third leg she gets out")
	check_near(GameData.as_float(left.get("fare")), 20.0, 0.000001, "fare 20")
	check_near(_sim.cash - before_stop, 20.0, 0.000001, "(in his hand)")
	check(not _sim.effects.has(DriveSim.AWAKE) or _sim.run.stop == "tea_stall", "(and nobody talks him awake any more)")
	check(not _sim.items.answered_for_him, "(nor answers his phone)")

	# What the review of M8 found (RULES-05, -06, -10).
	_check_her_word_for_the_call()


## She is the only one who tells him what the call was (GDD 8): the line of
## her Hand is the dispatcher's fare, so it is said for his calls and for no
## other; the call of his family has a word of its own.
func _check_her_word_for_the_call() -> void:
	var every: int = GameData.as_int(_params("phone").get("family_every"))
	var fare_line: String = "passenger.student.hand"
	var family_line: String = "passenger.student.family"
	check(data.has_line(fare_line, "en") and data.has_line(fare_line, "ar"), "(the line of her Hand is in both line files)")
	check(data.has_line(family_line, "en") and data.has_line(family_line, "ar"), "(and so is her word for a call from his family)")
	_on_the_road("student")
	_give("phone")
	var fares: int = 0
	var family: int = 0
	var unasked: int = 0
	var guard: int = _ticks_in(400.0)
	while fares + family < every and guard > 0:
		guard -= 1
		_events = []
		_tick()
		if _count_events("call_started") == 0:
			unasked += _count_events("line_requested", "id", fare_line) + _count_events("line_requested", "id", family_line)
			continue
		if GameData.as_string(_event("call_resolved").get("caller")) == String(ItemSim.CALLER_DISPATCHER):
			fares += 1
			check_eq(_count_events("line_requested", "id", fare_line), 1, "the dispatcher's call: she tells him the fare in the tick she takes it")
			check_eq(_count_events("line_requested", "id", family_line), 0, "(and nothing else)")
		else:
			family += 1
			check_eq(_count_events("line_requested", "id", fare_line), 0, "Um Noor's call is no fare: she does not say what the dispatcher offers")
			check_eq(_count_events("line_requested", "id", family_line), 1, "it has her word of its own")
	check(fares == every - 1 and family == 1, "(of %d calls one was his family's)" % every)
	check_eq(unasked, 0, "between the calls she has nothing to pass on")


# --- T-PASS-APPRENTICE -------------------------------------------------------

## T-PASS-APPRENTICE: The Apprentice (8.2): he repairs one fault per leg,
## leaning across the gear lever for 3 s, announced 2 s ahead, during which
## no shift is possible; on a tap he holds the wheel at its current angle for
## 3 s; he retunes the radio to static every 30 s; he rides to Basra and pays
## nothing.
func test_pass_apprentice() -> void:
	var record: Dictionary = _passenger("apprentice")
	var repairs: Dictionary = GameData.as_dict(record.get("repairs"))
	var announce: float = GameData.as_float(repairs.get("announce_s"))
	var lean: float = GameData.as_float(repairs.get("lean_s"))
	var hold: float = GameData.as_float(GameData.as_dict(record.get("hand")).get("duration_s"))
	var every: float = GameData.as_float(GameData.as_dict(record.get("retunes")).get("every_s"))
	check_eq(GameData.as_int(repairs.get("per_leg")), 1, "GDD 8.2: he repairs one fault per leg")
	check_near(announce, 2.0, 0.000001, "announced 2 s ahead")
	check_near(lean, 3.0, 0.000001, "leaning across the gear lever for 3 s")
	check_eq(GameData.as_string(GameData.as_dict(record.get("hand")).get("kind")), PassengerSim.HAND_HOLD, "on a tap he holds the wheel at its current angle")
	check_near(hold, 3.0, 0.000001, "for 3 s")
	check_near(every, 30.0, 0.000001, "he retunes the radio every 30 s")
	check_eq(GameData.as_string(GameData.as_dict(record.get("retunes")).get("to")), "static", "to static")
	check_eq(GameData.as_string(record.get("rides_until")), PassengerSim.RIDES_BASRA, "he rides to Basra")
	check_near(GameData.as_float(record.get("fare")), 0.0, 0.000001, "and pays nothing")

	# With no fault there is nothing to announce.
	_to_quiet_leg("fuel_station")
	_sim.board("apprentice")
	_events = []
	_ticks(_ticks_in(5.0))
	check_eq(GameData.as_int(_shot("passenger_repair")), PassengerSim.REPAIR_IDLE, "with no lamp lit he has nothing to repair")
	check_eq(_count_events("line_requested", "id", "passenger.apprentice.repair"), 0, "(and says nothing)")
	# A lamp lights: he says so, and 2 s later he is across the lever.
	_scrape()
	check_eq(_sim.faults.lamps, 1, "(a scrape lights a lamp)")
	var fault: String = String(_sim.faults.active[0])
	var said: int = 0
	for index: int in _events.size():
		if GameData.as_string(_events[index].get("id")) == "passenger.apprentice.repair":
			said += 1
	check_eq(said, 1, "a fault is lit: he announces the repair")
	# (The scrape helper has driven on past the hit's immunity: start again with a fresh fault to time it.)
	_to_quiet_leg("fuel_station")
	_sim.board("apprentice")
	_sim.faults.light(1)
	fault = String(_sim.faults.active[0])
	_events = []
	_tick()
	var announced_at: int = _sim.tick
	check_eq(GameData.as_int(_shot("passenger_repair")), PassengerSim.REPAIR_ANNOUNCED, "he announces it the moment a lamp is lit")
	check_near(GameData.as_float(_shot("passenger_repair_left")), announce, 2.0 * DT, "2 s ahead")
	check(not GameData.as_bool(_shot("lever_blocked")), "until then the lever is his")
	# In those 2 s he can still shift.
	check(_reach("gear_lever"), "(his hand goes to the lever)")
	_input.lmb = true
	_ticks(3)
	check(_sim.gate.held, "in the 2 s of warning he can still take the lever")
	# He holds on to it: when the boy leans across, the hand is off it.
	var guard: int = _ticks_in(announce + 1.0)
	while not GameData.as_bool(_shot("lever_blocked")) and guard > 0:
		guard -= 1
		_tick()
	check(absi(_sim.tick - announced_at - _ticks_in(announce)) <= 1, "2 s after the warning he leans across the gear lever (%.3f s)" % (float(_sim.tick - announced_at) * DT))
	check_eq(GameData.as_int(_shot("passenger_repair")), PassengerSim.REPAIR_LEANING, "(he is repairing)")
	_tick()
	check(not _sim.gate.held, "the lever is taken out of his hand")
	_input.clear()
	_ticks(SETTLE)
	# No shift is possible while he leans.
	var gear: int = _sim.gate.gear
	_reach("gear_lever")
	_input.lmb = true
	_ticks(3)
	check(not _sim.gate.held, "while he leans across it the lever cannot be taken")
	_input.pointer_is_absolute = false
	_input.pointer_delta = Vector2(0.0, 40.0)
	_ticks(10)
	_input.clear()
	check_eq(_sim.gate.gear, gear, "no shift is possible")
	# Nor with the lever set to shift by a flick (GDD 17.1).
	_sim.sequential_shift = true
	_reach("gear_lever")
	_flick(Vector2(0.0, -tuning.f("flick_min_distance") * 1.5))
	check_eq(_sim.gate.gear, gear, "nor by a flick, with sequential shifting on")
	check_eq(_sim.faults.lamps, 1, "(the lamp is still lit while he works)")
	guard = _ticks_in(lean + 1.0)
	while GameData.as_bool(_shot("lever_blocked")) and guard > 0:
		guard -= 1
		_tick()
	check(absi(_sim.tick - announced_at - _ticks_in(announce + lean)) <= 1, "for 3 s (done %.3f s after the warning)" % (float(_sim.tick - announced_at) * DT))
	check_eq(_sim.faults.lamps, 0, "then the fault is repaired: the lamp is out")
	var mended: Dictionary = _event("fault_repaired")
	check_eq(GameData.as_string(mended.get("fault")), fault, "(the fault that was lit)")
	check_eq(GameData.as_string(mended.get("by")), "apprentice", "(by him)")
	check(_reach("gear_lever"), "and the lever is the driver's again")
	# (The hand never left the lever: one tick puts the pointer back on it.)
	_tick()
	_flick(Vector2(0.0, -tuning.f("flick_min_distance") * 1.5))
	check_eq(_sim.gate.gear, gear + 1, "(the same flick shifts now)")
	_sim.sequential_shift = false
	_reach("gear_lever")
	_input.lmb = true
	_ticks(3)
	check(_sim.gate.held, "(and he can take it in his hand)")
	_input.clear()
	_ticks(SETTLE)
	# One per leg: a second fault stays lit until the next leg.
	_sim.faults.light(1)
	_events = []
	_ticks(_ticks_in(announce + lean + 3.0))
	check_eq(_sim.faults.lamps, 1, "one fault per leg: a second one on the same leg stays lit")
	check_eq(_count_events("line_requested", "id", "passenger.apprentice.repair"), 0, "(he does not start on it)")
	_into_next_quiet_leg()
	_events = []
	_ticks(_ticks_in(announce + lean + 0.5))
	check_eq(_sim.faults.lamps, 0, "on the next leg he repairs it")
	check_eq(_count_events("fault_repaired"), 1, "(one repair)")
	# Without him a fault stays a fault.
	_to_quiet_leg("fuel_station")
	_sim.faults.light(1)
	_ticks(_ticks_in(announce + lean + 1.0))
	check_eq(_sim.faults.lamps, 1, "(with nobody in the seat a lit lamp stays lit)")

	# A tap: he holds the wheel where it is for 3 s.
	_on_the_road("")
	_sim.wheel.reset(30.0)
	_ticks(_ticks_in(1.0))
	check(absf(_sim.wheel.angle) < 1.0, "(let go at 30 degrees, the wheel is back at the centre within a second)")
	_on_the_road("apprentice")
	_reach(SHOULDER)
	_sim.wheel.reset(30.0)
	_events = []
	_input.lmb = true
	_ticks(TAP_TICKS)
	_input.lmb = false
	guard = SETTLE * 2
	while _event("ritual_completed").is_empty() and guard > 0:
		guard -= 1
		_tick()
	var asked_at: int = _sim.tick
	var held_at: float = _sim.wheel.angle
	check(held_at > 5.0, "(the wheel is at %.1f degrees when he is asked)" % held_at)
	check_eq(GameData.as_int(_shot("wheel_held")), PassengerSim.HOLD_ANGLE, "on a tap he holds the wheel")
	check_eq(_count_events("line_requested", "id", "passenger.apprentice.hand"), 1, "(and says so)")
	var moved: float = 0.0
	guard = _ticks_in(hold + 1.0)
	while GameData.as_int(_shot("wheel_held")) != PassengerSim.HOLD_NONE and guard > 0:
		guard -= 1
		_tick()
		if GameData.as_int(_shot("wheel_held")) != PassengerSim.HOLD_NONE:
			moved = maxf(moved, absf(_sim.wheel.angle - held_at))
	check(absi(_sim.tick - asked_at - _ticks_in(hold)) <= 1, "for 3 s (%.3f s)" % (float(_sim.tick - asked_at) * DT))
	check(moved < 0.001, "at its current angle: it does not move (%.4f degrees)" % moved)
	_ticks(_ticks_in(1.0))
	check(absf(_sim.wheel.angle) < 1.0, "then he lets go and it returns to the centre")
	# The driver's own hand ends it.
	_on_the_road("apprentice")
	_ask()
	check_eq(GameData.as_int(_shot("wheel_held")), PassengerSim.HOLD_ANGLE, "(he holds it)")
	_grip()
	check_eq(GameData.as_int(_shot("wheel_held")), PassengerSim.HOLD_NONE, "when the driver takes the wheel the boy lets go")
	_release()

	# The radio: to static every 30 s.
	_on_the_road("apprentice")
	var boarded_at: int = _sim.tick
	_ticks(_ticks_in(every - 5.0))
	_sim.items.set_radio(ItemSim.MUSIC)
	_tick()
	check_eq(_sim.items.radio, ItemSim.MUSIC, "(25 s in, the driver tunes to music)")
	_events = []
	guard = _ticks_in(10.0)
	while _sim.items.radio == ItemSim.MUSIC and guard > 0:
		guard -= 1
		_tick()
	check_eq(_sim.items.radio, ItemSim.STATIC, "he retunes the radio to static")
	check(absi(_sim.tick - boarded_at - _ticks_in(every)) <= 2, "30 s after he got in (%.3f s)" % (float(_sim.tick - boarded_at) * DT))
	check(every < tuning.f("radio_drift_time"), "(sooner than the signal drifts by itself)")
	check_eq(_count_events("line_requested", "id", "passenger.apprentice.radio"), 1, "(his hand on the dial)")
	_sim.items.set_radio(ItemSim.MUSIC)
	guard = _ticks_in(every + 5.0)
	var again_from: int = _sim.tick
	while _sim.items.radio == ItemSim.MUSIC and guard > 0:
		guard -= 1
		_tick()
	check(absi(_sim.tick - boarded_at - _ticks_in(every * 2.0)) <= 2, "and again every 30 s (%.1f s after the last)" % (float(_sim.tick - again_from) * DT))
	# Without him the music plays on for the radio's own 40 s.
	_on_the_road("")
	_sim.items.set_radio(ItemSim.MUSIC)
	_ticks(_ticks_in(every + 5.0))
	check_eq(_sim.items.radio, ItemSim.MUSIC, "(without him the station holds for more than 30 s)")

	# He rides to Basra and pays nothing.
	_pick_up("apprentice")
	check_eq(GameData.as_string(_shot("passenger")), "apprentice", "(he gets in at the first stop)")
	var cash_then: float = _sim.cash
	_leave_stop()
	check_near(_sim.cash, cash_then, 0.000001, "he pays nothing")
	_events = []
	var arrived: Dictionary = _on_to_basra()
	check_eq(_count_events("passenger_left"), 0, "he gets out at no stop of the night")
	check_eq(GameData.as_string(arrived.get("guest")), "apprentice", "he rides to Basra: he is a wedding guest")

	# What the review of M8 found (RULES-01, -02, -03, -05, -07, -10).
	_check_retune_ends_the_station()
	_check_radio_line_only_when_playing()
	_check_tape_and_apprentice()


## The dial dragged `steps` stations to the right, through the hand.
func _tune(steps: int) -> void:
	_reach("radio")
	_input.pointer_is_absolute = false
	_input.lmb = true
	_input.pointer_delta = Vector2(tuning.f("radio_step_px") * (float(steps) + 0.2) / 20.0, 0.0)
	_ticks(20)
	_input.pointer_delta = Vector2.ZERO
	_input.lmb = false
	_ticks(SETTLE)
	_input.clear()


## Duct tape and the boy do not mend the same fault (GDD 7.5: the act's first
## fault "repairs itself"; 8.2: he repairs one fault per leg): he takes the
## oldest fault that the tape is not mending, and keeps his repair while the
## tape's is the only one lit.
func _check_tape_and_apprentice() -> void:
	var repairs: Dictionary = GameData.as_dict(_passenger("apprentice").get("repairs"))
	var his: float = GameData.as_float(repairs.get("announce_s")) + GameData.as_float(repairs.get("lean_s"))
	var after: float = 0.0
	for give: Variant in GameData.as_array(_record("duct_tape").get("gives")):
		if GameData.as_string(GameData.as_dict(give).get("passive")) == "self_repair_s":
			after = GameData.as_float(GameData.as_dict(give).get("amount"))
	check(after > his, "(the tape takes longer over a fault than he does: %.0f s against %.0f s)" % [after, his])
	var say: String = "passenger.apprentice.repair"

	# A crash, the act's first hit: two lamps. The tape has the first; he takes the other.
	_on_the_road("apprentice")
	_give("duct_tape")
	_sim.traffic.spawn(&"truck", 1, _sim.car.s + 30.0, tuning.fi("gear_speeds", 2) - 50.0)
	_events = []
	var guard: int = _ticks_in(10.0)
	while _sim.collision.hit == Collision.Hit.NONE and guard > 0:
		guard -= 1
		_tick()
	var hit_at: int = _sim.tick
	_sim.traffic.clear()
	if check_eq(_sim.faults.lamps, 2, "(a crash into a slow truck: two lamps)"):
		var first: String = String(_sim.faults.active[0])
		var second: String = String(_sim.faults.active[1])
		check_eq(String(_sim.items.mending), first, "(the tape has taken hold of the first of them)")
		check_eq(_count_events("line_requested", "id", say), 1, "with two lamps lit and one in the tape, he announces a repair")
		_ticks(hit_at + _ticks_in(his) + 2 - _sim.tick)
		var mended: Dictionary = _event("fault_repaired")
		check_eq(GameData.as_string(mended.get("by")), "apprentice", "after his 5 s a fault is mended by him")
		check_eq(GameData.as_string(mended.get("fault")), second, "the one the tape is not mending")
		check(_sim.faults.has(StringName(first)) and _sim.faults.lamps == 1, "(the tape's fault is still lit)")
		_events = []
		_ticks(hit_at + _ticks_in(after) + 2 - _sim.tick)
		mended = _event("fault_repaired")
		check_eq(GameData.as_string(mended.get("by")), "duct_tape", "after the tape's 10 s its fault has repaired itself")
		check_eq(GameData.as_string(mended.get("fault")), first, "(the act's first)")
		check_eq(_sim.faults.lamps, 0, "two repairs, two lamps out: neither was spent on the other's fault")

	# One scrape, the act's first fault: it is the tape's. He keeps his repair
	# for the next fault of the leg.
	_on_the_road("apprentice")
	_give("duct_tape")
	_events = []
	_scrape_rail()
	hit_at = _sim.tick - _ticks_in(tuning.f("hit_immunity") + 0.2)
	check_eq(_sim.faults.lamps, 1, "(a scrape: one lamp)")
	check_eq(String(_sim.items.mending), String(_sim.faults.active[0]), "(the tape has taken hold of it)")
	_ticks(hit_at + _ticks_in(his) + 2 - _sim.tick)
	check_eq(_count_events("line_requested", "id", say), 0, "the only lamp lit is in the tape: he does not start on it")
	check_eq(_sim.faults.lamps, 1, "(after his 5 s it is still lit)")
	_ticks(hit_at + _ticks_in(after) + 2 - _sim.tick)
	check_eq(GameData.as_string(_event("fault_repaired").get("by")), "duct_tape", "it repairs itself after the tape's 10 s")
	check_eq(_sim.faults.lamps, 0, "(the lamp is out)")
	_events = []
	_scrape_rail()
	check_eq(_sim.faults.lamps, 1, "(another scrape on the same leg: the act's second fault, not the tape's)")
	check_eq(_count_events("line_requested", "id", say), 1, "his one repair of the leg is still his: he announces it")
	_ticks(_ticks_in(his))
	check_eq(GameData.as_string(_event("fault_repaired").get("by")), "apprentice", "and mends it")
	check_eq(_sim.faults.lamps, 0, "the tape did not cost him his repair")


## "(he turns the dial)" is said when he turns a station off, not every 30 s
## over a radio that is silent anyway or a deck that plays a tape.
func _check_radio_line_only_when_playing() -> void:
	var every: float = GameData.as_float(GameData.as_dict(_passenger("apprentice").get("retunes")).get("every_s"))
	var line: String = "passenger.apprentice.radio"
	_on_the_road("apprentice")
	_events = []
	_ticks(_ticks_in(every * 2.0 + 1.0))
	check_eq(_sim.items.radio, ItemSim.STATIC, "(the radio is silent all along)")
	check_eq(_count_events("line_requested", "id", line), 0, "over a silent radio he has no dial to turn: nothing is said")
	# A station that plays is turned off, and that is said, each time.
	var stations: Array = tuning.a("radio_stations")
	for round: int in 2:
		_tune(stations.find("music") + 1)
		check_eq(_sim.items.radio, ItemSim.MUSIC, "(the driver tunes to music)")
		_events = []
		var guard: int = _ticks_in(every + 1.0)
		while _sim.items.radio != ItemSim.STATIC and guard > 0:
			guard -= 1
			_tick()
		check_eq(_count_events("line_requested", "id", line), 1, "a station that plays he turns off, and that is said (%d)" % (round + 1))
	# A tape in the deck plays on: the dial behind it is not his to turn.
	_on_the_road("apprentice")
	_give("mixtape")
	_events = []
	_ticks(_ticks_in(every * 1.5))
	check(_sim.effects.has(ItemSim.MUSIC), "a tape in the deck plays on past his 30 s")
	check_eq(_count_events("line_requested", "id", line), 0, "and he says nothing of a dial")


## When the boy turns the dial to static, what the station held on ends as it
## does when the dial itself goes there (GDD 6.2: "Static: no effect"; 6.1:
## the news keeps him awake "while tuned"; 7.8: the beads answer to music).
func _check_retune_ends_the_station() -> void:
	var every: float = GameData.as_float(GameData.as_dict(_passenger("apprentice").get("retunes")).get("every_s"))
	var stations: Array = tuning.a("radio_stations")
	for station: String in ["news", "music"]:
		_on_the_road("apprentice")
		_give("beads")
		_tune(stations.find(station) + 1)
		_ticks(2)
		check_eq(String(_sim.items.radio), station, "(he drags the dial to the %s)" % station)
		check(_sim.effects.has(StringName(station)), "(while it plays, its status is on)")
		if station == "news":
			check(_sim.effects.has(DriveSim.AWAKE), "(the news keeps him awake while it is tuned)")
		else:
			check(not _sim.items.pair("bead_calm").is_empty(), "(the beads answer to the radio's music)")
		_events = []
		var guard: int = _ticks_in(every + 1.0)
		while _sim.items.radio != ItemSim.STATIC and guard > 0:
			guard -= 1
			_tick()
		check_eq(_sim.items.radio, ItemSim.STATIC, "(the boy turns it to static)")
		check(not _sim.effects.has(StringName(station)), "static has no effect: what the %s held on ends when he turns the dial away" % station)
		check_eq(_count_events("effect_expired", "effect", station), 1, "and its end is said in the tick he turned it")
		if station == "news":
			check(not _sim.effects.has(DriveSim.AWAKE), "a silent radio keeps nobody awake")
		else:
			check(_sim.items.pair("bead_calm").is_empty(), "and the beads have no music to answer to")
		_ticks(_ticks_in(every * 0.5))
		check(not _sim.effects.has(StringName(station)), "(nor does it come back by itself)")
