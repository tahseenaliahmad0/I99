extends CabinSuite
## M9c: endings and what persists (GDD 11.4, 11.5). T-END-01.

const KEY: String = "key"
const ORDER: PackedStringArray = ["children", "drivers", "uncles", "inlaws", "aunts", "groom", "noor"]


# --- Helpers -------------------------------------------------------------------

func _tell(table_id: String, telling_seed: int) -> void:
	_sim = DriveSim.new(fresh_data())
	# What the Tables say on the way is T-HECKLE-01's.
	_sim.heckling = false
	_events = []
	_keep_lane = true
	_input.clear()
	_sim.begin_telling(table_id, telling_seed)
	for event: Dictionary in _sim.drain_events():
		_events.append(event)


func _street() -> Dictionary:
	return GameData.as_dict(data.root("legs").get("arrival"))


## A whole night at `table_id`, its roads passed at once, to the bay in
## Basra: the key is turned `over` game minutes after the deadline (before
## it when negative), with the Call answered or not, and whoever boarded
## for the last of it beside him. Returns the "arrived" event.
func _park(table_id: String, over: float, call: bool, passenger: String = "") -> Dictionary:
	_tell(table_id, 7)
	_drive_on_to_act(RunGenerator.ACTS)
	_drive_on_to_boss()
	if not passenger.is_empty():
		check(_sim.board(passenger), "(%s gets in)" % passenger)
	_drive_on_to_boss_stop()
	_leave_stop()
	check_eq(_sim.run.stage, RunState.Stage.ARRIVAL, "(the street in Basra)")
	# (How the Call is answered is T-CALL-01's.)
	_sim.run.call_answered = call
	_sim.clock.minutes = _sim.clock.night_minutes() + over
	_sim.car.s = GameData.as_float(_street().get("length_m")) - GameData.as_float(_street().get("bay_m")) * 0.5
	_sim.car.speed = 0.0
	_input.rmb = true
	_ticks(3)
	_events = []
	_tap_at(KEY)
	var arrived: Dictionary = _event("arrived")
	check(not arrived.is_empty() and not _sim.run.active, "(the key is turned in the bay: the Telling is over)")
	return arrived


func _list(profile: Dictionary, key: String) -> PackedStringArray:
	var out: PackedStringArray = []
	for value: Variant in GameData.as_array(profile.get(key)):
		out.append(GameData.as_string(value))
	return out


# --- T-END-01 --------------------------------------------------------------------

## T-END-01: Endings and persistence of 11.4 and 11.5: a Wreck restarts the
## Telling; parking after 06:00 is Late and unlocks nothing; parking by 06:00
## unlocks the next Table; answering the Call and parking by 06:00 marks the
## Table told true and, at Noor's Table, starts the finale; passengers
## carried to Basra become wedding guests who add two heckles to the pool;
## the first win unlocks Commute mode and any Call ending unlocks Endless
## Night mode.
func test_end_01() -> void:
	_check_a_new_profile()
	_check_the_wreck()
	_check_late()
	_check_on_time()
	_check_the_call()
	_check_the_chain()
	_check_guests()
	_check_the_save_file()


## What a new player has: the first Table, and nothing else.
func _check_a_new_profile() -> void:
	var profile: Dictionary = Save.new_profile(data)
	check_eq(_list(profile, "tables_unlocked"), PackedStringArray(["children"]), "a new player has the Children's Table")
	check(_list(profile, "told_true").is_empty() and _list(profile, "guests").is_empty() and _list(profile, "modes").is_empty(),
			"no Table told true, no guests, no modes")
	check_eq(profile, Save.default_profile(), "(the profile a save that cannot be read falls back to is the same)")
	check_eq(tuning.s("clock_deadline"), "06:00", "GDD 11.4: the deadline is 06:00")


## "All lamps lit: the Table objects, he corrects himself, the Telling
## restarts in 3 s." A Wreck is no ending: nothing of it is kept.
func _check_the_wreck() -> void:
	check_near(tuning.f("wreck_to_wheel"), 3.0, 0.000001, "GDD 11.4: the Telling restarts in 3 s")
	_tell("drivers", 3)
	_into_next_quiet_leg()
	var told: int = _sim.run.seed
	_input.clear()
	var guard: int = _ticks_in(90.0)
	while not _sim.wrecked and guard > 0:
		guard -= 1
		_sim.car.x = _sim.car.guardrail_x()
		_sim.car.s = clampf(_sim.car.s, 50.0, _sim.leg.length - 400.0)
		_sim.step(_input)
		for event: Dictionary in _sim.drain_events():
			_events.append(event)
	check(_sim.wrecked and _sim.faults.is_wrecked(), "every lamp is lit: a Wreck")
	check_eq(_count_events("wreck"), 1, "it is announced once")
	check_eq(_count_events("arrived"), 0, "and is no arrival: there is nothing for the profile in it")
	var cut: int = 0
	guard = _ticks_in(10.0)
	while _sim.wrecked and guard > 0:
		guard -= 1
		cut += 1
		_sim.step(_input)
	check_near(float(cut) * DT, tuning.f("wreck_to_wheel"), DT * 1.5, "3 s later he is at the wheel again")
	check(_sim.run.active and _sim.run.stage == RunState.Stage.APPROACH and _sim.run.act == 1 and _sim.run.legs_done == 0,
			"the Telling is told again from Baghdad")
	check_eq(_sim.run.table, "drivers", "to the same Table")
	check(_sim.run.retellings == 1 and _sim.run.seed != told, "another night of it")
	check_eq(_sim.faults.lamps, 0, "with no lamp lit")
	check_eq(_sim.clock.text(), tuning.s("clock_start"), "at 22:00")


## "Parked after 06:00: she is already up. Nothing unlocks."
func _check_late() -> void:
	for call: bool in [false, true]:
		var arrived: Dictionary = _park("children", 1.0, call)
		check(GameData.as_bool(arrived.get("late")), "parked a minute after 06:00 (%s): late" % GameData.as_string(arrived.get("clock")))
		check_eq(Save.ending_of(arrived), Save.LATE, "the ending is Late%s" % (", though he answered the Call" if call else ""))
		var profile: Dictionary = Save.new_profile(data)
		var before: Dictionary = profile.duplicate(true)
		var result: Dictionary = Save.apply_ending(data, profile, arrived)
		check_eq(profile, before, "Late: nothing unlocks, nothing is marked")
		check(GameData.as_array(result["tables"]).is_empty() and GameData.as_array(result["modes"]).is_empty()
				and not GameData.as_bool(result["told_true"]) and not GameData.as_bool(result["finale"]), "(and the result says so)")
	# At Noor's Table too: no finale for a father who was late.
	var late_at_noor: Dictionary = _park("noor", 1.0, true)
	var profile_noor: Dictionary = Save.new_profile(data)
	check(not GameData.as_bool(Save.apply_ending(data, profile_noor, late_at_noor)["finale"]), "late at Noor's Table, the Call answered: no finale")
	check(_list(profile_noor, "told_true").is_empty(), "and it is not told true")


## "Parked by 06:00: the next Table unlocks." And the first win is the Commute.
func _check_on_time() -> void:
	var arrived: Dictionary = _park("children", -1.0, false)
	check(not GameData.as_bool(arrived.get("late")), "parked a minute before 06:00 (%s): on time" % GameData.as_string(arrived.get("clock")))
	check_eq(GameData.as_string(arrived.get("table")), "children", "(the event names the Table)")
	check_eq(Save.ending_of(arrived), Save.ON_TIME, "the ending is On time")
	var profile: Dictionary = Save.new_profile(data)
	var result: Dictionary = Save.apply_ending(data, profile, arrived)
	check_eq(_list(profile, "tables_unlocked"), PackedStringArray(["children", "drivers"]), "the next Table unlocks: the Drivers'")
	check_eq(result["tables"], PackedStringArray(["drivers"]), "(the result names it)")
	check_eq(_list(profile, "modes"), PackedStringArray([Save.COMMUTE]), "the first win unlocks Commute mode")
	check_eq(result["modes"], PackedStringArray([Save.COMMUTE]), "(the result names it)")
	check(_list(profile, "told_true").is_empty(), "without the Call the Table is not told true")
	check(not _list(profile, "modes").has(Save.ENDLESS_NIGHT), "and Endless Night stays locked")
	check(not GameData.as_bool(result["finale"]), "no finale")
	# Won again: nothing new, nothing twice.
	var again: Dictionary = Save.apply_ending(data, profile, arrived)
	check(GameData.as_array(again["tables"]).is_empty() and GameData.as_array(again["modes"]).is_empty(), "the same Table won again opens nothing new")
	check_eq(_list(profile, "tables_unlocked"), PackedStringArray(["children", "drivers"]), "(and the profile holds each Table once)")
	check_eq(_list(profile, "modes"), PackedStringArray([Save.COMMUTE]), "(and each mode once)")
	# On time at Noor's Table without the Call: a win, and no finale.
	var at_noor: Dictionary = _park("noor", -1.0, false)
	var profile_noor: Dictionary = Save.new_profile(data)
	var result_noor: Dictionary = Save.apply_ending(data, profile_noor, at_noor)
	check(not GameData.as_bool(result_noor["finale"]) and _list(profile_noor, "told_true").is_empty(), "on time at Noor's Table without the Call: no finale, not told true")
	check_eq(_list(profile_noor, "modes"), PackedStringArray([Save.COMMUTE]), "(a win all the same)")


## "Answered the Call and parked by 06:00: the Table is marked told true. At
## Noor's Table it starts the finale." Any Call ending is Endless Night.
func _check_the_call() -> void:
	var arrived: Dictionary = _park("drivers", -1.0, true)
	check(GameData.as_bool(arrived.get("call")) and not GameData.as_bool(arrived.get("late")), "(the Call answered, parked by 06:00)")
	check_eq(Save.ending_of(arrived), Save.THE_CALL, "the ending is the Call")
	var profile: Dictionary = Save.new_profile(data)
	var result: Dictionary = Save.apply_ending(data, profile, arrived)
	check_eq(_list(profile, "told_true"), PackedStringArray(["drivers"]), "the Table is marked told true")
	check(GameData.as_bool(result["told_true"]), "(the result says so)")
	check_eq(_list(profile, "modes"), PackedStringArray([Save.COMMUTE, Save.ENDLESS_NIGHT]), "a Call ending unlocks Endless Night (and, a first win, the Commute)")
	check(_list(profile, "tables_unlocked").has("uncles"), "it is a win: the next Table unlocks too")
	check(not GameData.as_bool(result["finale"]), "at the Drivers' Table there is no finale")
	var again: Dictionary = Save.apply_ending(data, profile, arrived)
	check(not GameData.as_bool(again["told_true"]) and _list(profile, "told_true").size() == 1, "(told true once)")
	# At Noor's Table.
	var at_noor: Dictionary = _park("noor", -1.0, true)
	var result_noor: Dictionary = Save.apply_ending(data, profile, at_noor)
	check(GameData.as_bool(result_noor["finale"]), "the Call at Noor's Table starts the finale")
	check(_list(profile, "told_true").has("noor"), "and her Table is told true")
	check(GameData.as_array(result_noor["tables"]).is_empty(), "(there is no Table after hers)")


## "A Table unlocks by winning the one before it on time": the seven in a
## row, each win opening exactly the next.
func _check_the_chain() -> void:
	var profile: Dictionary = Save.new_profile(data)
	for place: int in ORDER.size():
		var table_id: String = ORDER[place]
		check(TableRules.unlocked(profile, table_id), "the %s Table is open when its turn comes" % table_id)
		if place + 1 < ORDER.size():
			check(not TableRules.unlocked(profile, ORDER[place + 1]), "(the %s Table is not, yet)" % ORDER[place + 1])
		var result: Dictionary = Save.apply_ending(data, profile, {"table": table_id, "late": false, "call": false, "guest": ""})
		var opened: PackedStringArray = result["tables"]
		if place + 1 < ORDER.size():
			check_eq(opened, PackedStringArray([ORDER[place + 1]]), "winning the %s Table on time opens the %s Table" % [table_id, ORDER[place + 1]])
		else:
			check(opened.is_empty(), "winning Noor's Table opens no other")
	check_eq(_list(profile, "tables_unlocked"), ORDER, "seven wins: seven Tables")
	# A Table that is not his to tell yet stays shut by a late night.
	var shut: Dictionary = Save.new_profile(data)
	Save.apply_ending(data, shut, {"table": "children", "late": true, "call": true, "guest": ""})
	check_eq(_list(shut, "tables_unlocked"), PackedStringArray(["children"]), "a late night opens nothing")


## "Each passenger carried to Basra sits at a Table from then on and adds
## two heckles to the pool."
func _check_guests() -> void:
	var arrived: Dictionary = _park("children", -1.0, false, "drummer")
	check_eq(GameData.as_string(arrived.get("guest")), "drummer", "the Drummer was beside him when he turned the key")
	var profile: Dictionary = Save.new_profile(data)
	var result: Dictionary = Save.apply_ending(data, profile, arrived)
	check_eq(_list(profile, "guests"), PackedStringArray(["drummer"]), "carried to Basra, he is a wedding guest")
	check_eq(GameData.as_string(result["guest"]), "drummer", "(the result names him)")
	check_eq(GameData.as_string(Save.apply_ending(data, profile, arrived)["guest"]), "", "(carried again, he is no new guest)")
	check_eq(_list(profile, "guests").size(), 1, "(and sits there once)")
	# Carried there late, he is at the wedding all the same.
	var late: Dictionary = _park("children", 1.0, false, "apprentice")
	Save.apply_ending(data, profile, late)
	check_eq(_list(profile, "guests"), PackedStringArray(["drummer", "apprentice"]), "a passenger carried to Basra after 06:00 is a guest too: he was carried there")
	check_eq(_list(profile, "tables_unlocked"), PackedStringArray(["children", "drivers"]), "(the late night itself opened nothing more)")
	# Nobody beside him: no guest.
	var alone: Dictionary = _park("children", -1.0, false)
	check_eq(GameData.as_string(alone.get("guest")), "", "(alone in the car: nobody to seat)")
	# At the wedding they heckle: two more in the pool each, at every Table
	# that heckles, and they are heard on the road.
	var weight: float = tuning.f("guest_heckle_weight")
	var guests: PackedStringArray = _list(profile, "guests")
	for table_id: String in ORDER:
		var rules: TableRules = TableRules.of(data, table_id)
		var without: int = HeckleDirector.pool(data, rules, PackedStringArray(), weight).size()
		var with_one: int = HeckleDirector.pool(data, rules, PackedStringArray(["drummer"]), weight).size()
		var with_both: int = HeckleDirector.pool(data, rules, guests, weight).size()
		if table_id == "noor":
			check_eq(with_both, 0, "at Noor's Table nobody heckles, guests or not")
		else:
			check_eq(with_one - without, 2, "%s: one guest adds two heckles to the pool" % table_id)
			check_eq(with_both - without, 4, "%s: two guests add four" % table_id)
	_sim = DriveSim.new(fresh_data())
	_sim.guests = guests
	_sim.begin_telling("drivers", 5)
	var theirs: Dictionary = {}
	for leg: int in 300:
		_sim.heckles.plan_leg(_sim.rng, _sim.table, _sim.guests, 2, "open_road", "")
		for entry: Dictionary in _sim.heckles.planned:
			var guest: String = GameData.as_string(GameData.as_dict(entry["record"]).get("guest"))
			if not guest.is_empty():
				theirs[guest] = GameData.as_int(theirs.get(guest)) + 1
	check(GameData.as_int(theirs.get("drummer")) > 0 and GameData.as_int(theirs.get("apprentice")) > 0,
			"on the next night told to the Drivers both of them are heard (%d and %d heckles on 300 legs)" % [GameData.as_int(theirs.get("drummer")), GameData.as_int(theirs.get("apprentice"))])
	check_eq(theirs.size(), 2, "and nobody who was not carried")


## The game keeps it: the ending goes into the profile on disk, and the
## Telling that is over is not there to continue.
func _check_the_save_file() -> void:
	var arrived: Dictionary = _park("children", -1.0, true, "drummer")
	var kept_profile: Dictionary = Game.profile
	var kept_telling: Dictionary = Game.saved_telling
	Game.profile = Save.new_profile(data)
	Game.saved_telling = _sim.checkpoint.duplicate(true)
	check(not Game.saved_telling.is_empty(), "(a Telling was on disk to continue)")
	var result: Dictionary = Game.end_telling(arrived)
	check_eq(GameData.as_string(result["ending"]), Save.THE_CALL, "the game ends the Telling: the Call")
	var read: Dictionary = Save.from_text(FileAccess.get_file_as_string(Game.save_path()))
	check(GameData.as_bool(read.get("ok")), "the save file is written")
	var on_disk: Dictionary = GameData.as_dict(read.get("profile"))
	check_eq(_list(on_disk, "tables_unlocked"), PackedStringArray(["children", "drivers"]), "on disk: the next Table")
	check_eq(_list(on_disk, "told_true"), PackedStringArray(["children"]), "on disk: told true")
	check_eq(_list(on_disk, "modes"), PackedStringArray([Save.COMMUTE, Save.ENDLESS_NIGHT]), "on disk: both modes")
	check_eq(_list(on_disk, "guests"), PackedStringArray(["drummer"]), "on disk: the guest")
	check(GameData.as_dict(read.get("telling")).is_empty() and Game.saved_telling.is_empty(), "and no Telling to continue: it is over")
	Game.profile = kept_profile
	Game.saved_telling = kept_telling
