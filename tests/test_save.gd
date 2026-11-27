extends TestSuite
## M5: the save file (GDD 13.7) and the input log (GDD 13.3).

const DT: float = DriveSim.DT
const KMH_TO_MS: float = 1.0 / 3.6
const TABLE: String = "drivers"
## Under this process's own test folder (Smoke.test_user_root()).
var _save_dir: String = Smoke.test_user_root().path_join("t_save")

var _sim: DriveSim
var _input: DriveInput
var _events: Array[Dictionary] = []
## Saves and stops seen while stepping (a save belongs to a stop, tick for tick).
var _saves_seen: int = 0
var _stops_seen: int = 0
var _saves_off_stop: int = 0


func before_each() -> void:
	_sim = DriveSim.new(fresh_data())
	_input = DriveInput.new()
	_events = []
	_saves_seen = 0
	_stops_seen = 0
	_saves_off_stop = 0


## T-SAVE-01: The save file of 13.7 round-trips: a save made at a stop or
## after a boss, loaded again, restores table, seed, act, leg, clock, cash,
## Nerves, faults, items, adaptations, passenger, fault deck and RNG state
## exactly, and the Telling continued from it matches the uninterrupted one;
## nothing is written during a leg.
func test_save_01() -> void:
	var profile: Dictionary = Save.default_profile()
	profile["tables_unlocked"] = ["children", "drivers"]
	profile["guests"] = ["drummer"]
	profile["prologue_seen"] = true

	# A Telling with a history: a lamp lit on the first leg, something bought
	# and something fitted at its stop, a switch thrown; then the second leg
	# and its stop, where the game saves again.
	var telling_seed: int = _seed_for("fuel_station")
	_sim.begin_telling(TABLE, telling_seed)
	_roll_to_leg()
	_quiet_this_leg()
	check_eq(_sim.checkpoints, 0, "nothing is saved before the first stop")
	_scrape()
	var lit: StringName = _sim.faults.active[0]
	_into_stall()
	check_eq(_sim.checkpoints, 1, "the first stop saves")
	var bought: String = ""
	for offer: Dictionary in _offers():
		if offer["kind"] == StopSim.ITEM and GameData.as_float(offer["price"]) <= _sim.cash:
			bought = GameData.as_string(offer["id"])
			_tap(GameData.as_string(offer["anchor"]))
			var slots: Array = GameData.as_array(data.record("items", bought).get("slots"))
			_drag(GameData.as_string(offer["anchor"]), _sim.items.anchor_of_slot(GameData.as_string(slots[0])))
			break
	check(not bought.is_empty() and _sim.items.item(StringName(bought)) != null, "(he buys %s at the first stop and puts it in its place)" % bought)
	check(_sim.give_item(&"phone") != null and _sim.give_item(&"painkillers") != null, "(and has a phone and pills from there on)")
	_sim.items.add_item(&"fifth_gear", &"bay_2")
	_sim.items.flags[&"hazards"] = true
	_leave()
	_step_to_the_gore()
	check_eq(_sim.run.legs_done, 1, "(he is on the second leg)")
	_quiet_this_leg()
	# What this leg and the night will still owe him at its stop: a phone
	# whose next call is on its way, a look at the photo that is spent, a
	# pill that lasts to the leg's end.
	_sim.items.complete(data.record("rituals", "visor_photo"), Gesture.DIR_DOWN)
	_sim.items.complete(data.record("rituals", "painkillers_take"), 0)
	var saves_before_leg: int = _sim.checkpoints
	var saved_before_leg: Dictionary = _sim.checkpoint
	for _tick: int in int(20.0 / DT):
		_step()
	check_eq(_sim.checkpoints, saves_before_leg, "nothing is written during a leg")
	check(is_same(_sim.checkpoint, saved_before_leg), "what was saved at the last stop is untouched")
	# What he carries into the stop is what he has at it: a stop saves and
	# goes on from the save, and nothing of his may be lost on the way.
	_sim.items.item(&"cigarettes").supply = 3
	_sim.items.set_radio(&"music")
	_sim.cash += 0.625
	# (A cigarette burnt out a while ago: its Craving is some seconds away.)
	_sim.items.item(&"cigarettes").lapse_left = 100.0 / 7.0
	var cabin_before: Array[String] = _cabin(_sim)
	var cash_before: float = _sim.cash
	var lit_before: Array[StringName] = _sim.faults.active.duplicate()
	var deck_before: Array[StringName] = _sim.faults.deck.duplicate()
	var craving_before: float = _sim.items.item(&"cigarettes").lapse_left
	var call_before: float = _call_wait(_sim)
	check(call_before > 0.0, "(the next call is %s s away)" % str(snappedf(call_before, 0.01)))
	var tick_before: int = _sim.tick
	_into_stall()
	var into_stall: float = float(_sim.tick - tick_before) * DT
	var here: Dictionary = data.record("stops", _sim.run.stop)
	check_eq(_sim.checkpoints, 2, "the second stop saves again")
	# What is owed him is still owed at the stop, to the second he arrived
	# with: the stop cancels none of it.
	check_near(_sim.items.item(&"cigarettes").lapse_left, craving_before - into_stall, 0.000000001, "the seconds until the Craving he drove in with")
	check_near(_call_wait(_sim), call_before - into_stall, 0.000000001, "the seconds until the next call")
	check(_sim.items.photo_used, "that he has had this leg's look at the photo")
	check(_sim.phantom_muted() and _sim.effects.has(&"drowsy"), "and what the pill does for the rest of the leg")
	check(not _sim.effects.has(&"painkillers") and not _sim.effects.has(&"visor_down"), "(what runs by the clock ends at the stop)")
	var craving_at_stop: float = _sim.items.item(&"cigarettes").lapse_left
	var call_at_stop: float = _call_wait(_sim)
	if GameData.as_string(here.get("service")) != "tea":
		check_eq(_cabin(_sim), cabin_before, "at the stop he has what he drove in with: every item, its place, its supply")
	check_eq(_sim.items.item(&"cigarettes").supply, 3, "the three cigarettes he had left")
	check_eq(_sim.cash, cash_before, "his cash to the last fraction")
	check_eq(_sim.faults.active, lit_before, "the lamps that were lit")
	check_eq(_sim.faults.deck, deck_before, "the fault deck as it lay")
	check_eq(_sim.items.radio, &"music", "the station the radio was on")
	check(_sim.items.flag(&"hazards"), "and the switch he threw")
	check_eq(_saves_off_stop, 0, "every save was made on a tick that entered a stop")
	check_eq(_saves_seen, _stops_seen, "one save for each stop entered (%d)" % _stops_seen)

	# What the save holds (GDD 13.7).
	var saved: Dictionary = _sim.checkpoint
	check_eq(GameData.as_string(saved.get("table")), TABLE, "the save holds the Table")
	check_eq(Save.seed_in(saved.get("seed")), telling_seed, "the seed")
	check_eq(GameData.as_int(saved.get("act")), 1, "the act")
	check_eq(GameData.as_int(saved.get("leg")), 1, "the leg")
	check_eq(GameData.as_string(saved.get("stage")), "stop", "that he is at a stop")
	check_near(GameData.as_float(saved.get("clock_min")), _sim.clock.minutes, 0.001, "the Clock, with this stop's minutes on it")
	check_near(GameData.as_float(saved.get("cash")), _sim.cash, 0.001, "his cash")
	check_near(GameData.as_float(saved.get("nerves")), _sim.nerves.value, 0.001, "his Nerves")
	var bits: Dictionary = GameData.as_dict(saved.get("exact"))
	check_eq(Save.from_exact(bits.get("clock_min"), -1.0), _sim.clock.minutes, "and each of them to the bit as well: the Clock")
	check_eq(Save.from_exact(bits.get("cash"), -1.0), _sim.cash, "cash")
	check_eq(Save.from_exact(bits.get("nerves"), -1.0), _sim.nerves.value, "Nerves")
	check_eq(GameData.as_array(saved.get("faults")), [String(lit)], "the fault that is lit")
	check_eq(GameData.as_array(saved.get("fault_deck")).size(), data.records("faults").size() - 1, "the rest of the fault deck, in order")
	check(saved.has("passenger") and saved["passenger"] == null, "no passenger")
	check_eq(GameData.as_dict(saved.get("rng_state")).size(), Rng.STREAMS.size(), "and the state of the four seeded streams")
	var has_bought: bool = false
	for entry: Variant in GameData.as_array(saved.get("items")):
		var kept: Dictionary = entry
		if GameData.as_string(kept.get("id")) == bought:
			has_bought = true
			check(kept.has("slot") and kept.has("supply"), "an item is saved with its slot and its supply")
	check(has_bought, "his items, with the one he bought")
	check_eq(GameData.as_array(saved.get("adaptations")), [{"id": "fifth_gear", "slot": "bay_2"}], "his adaptations, each in its bay")
	# And what the stop does not cancel: what is owed him, and what he has
	# done once this leg.
	var kept_pack: Dictionary = {}
	for entry: Variant in GameData.as_array(saved.get("items")):
		if GameData.as_string(GameData.as_dict(entry).get("id")) == "cigarettes":
			kept_pack = GameData.as_dict(entry)
	check_eq(Save.from_exact(kept_pack.get("lapse"), -1.0), craving_at_stop, "the seconds until the Craving, to the bit")
	check_eq(Save.from_exact(GameData.as_dict(saved.get("item_state")).get("call_wait"), -1.0), call_at_stop, "the seconds until the next call, to the bit")
	var kept_leg: Dictionary = GameData.as_dict(saved.get("leg_state"))
	check(GameData.as_bool(kept_leg.get("photo")), "that the photo was looked at this leg")
	check(GameData.as_array(kept_leg.get("held")).has("drowsy") and GameData.as_array(kept_leg.get("held")).has("phantom_mute"), "and the statuses that last to the leg's end")

	# Through the file and back.
	var text: String = Save.to_text(profile, saved)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_save_dir))
	var path: String = _save_dir.path_join(Save.FILE_NAME)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if not check(file != null, "(the test can write %s)" % path):
		return
	file.store_string(text)
	file.close()
	var read: Dictionary = Save.from_text(FileAccess.get_file_as_string(path))
	check(GameData.as_bool(read.get("ok")), "the file reads back: %s" % GameData.as_string(read.get("error")))
	check_eq(Save.to_text(GameData.as_dict(read.get("profile")), GameData.as_dict(read.get("telling"))), text, "and written again it is the same file, to the letter")
	check_eq(GameData.as_dict(read.get("profile")), profile, "with the profile")
	check(text.contains("\"version\": 1"), "marked version 1")

	# Loaded into a fresh simulation: the same stop, exactly.
	var loaded: DriveSim = DriveSim.new(fresh_data())
	check(loaded.restore(GameData.as_dict(read.get("telling"))), "a fresh simulation takes the save")
	loaded.tick = _sim.tick
	check_eq(loaded.run.table, _sim.run.table, "loaded: the Table")
	check_eq(loaded.run.seed, _sim.run.seed, "the seed")
	check_eq(loaded.run.act, _sim.run.act, "the act")
	check_eq(loaded.run.legs_done, _sim.run.legs_done, "the leg")
	check_eq(loaded.run.stage, RunState.Stage.STOP, "at its stop")
	check_eq(loaded.run.stop, _sim.run.stop, "the same stop")
	check_eq(loaded.clock.minutes, _sim.clock.minutes, "the Clock, exactly")
	check_eq(loaded.cash, _sim.cash, "cash, exactly")
	check_eq(loaded.nerves.value, _sim.nerves.value, "Nerves, exactly")
	check_eq(loaded.faults.active, _sim.faults.active, "the lit faults")
	check_eq(loaded.faults.deck, _sim.faults.deck, "the fault deck in its order")
	check_eq(_cabin(loaded), _cabin(_sim), "every item and adaptation in its place with its supply")
	check_eq(loaded.rng.get_state(), _sim.rng.get_state(), "the state of the seeded streams")
	check(loaded.items.flag(&"hazards"), "the switch he threw")
	check_eq(loaded.items.item(&"cigarettes").lapse_left, craving_at_stop, "the seconds until the Craving, exactly")
	check_eq(_call_wait(loaded), call_at_stop, "the seconds until the next call, exactly")
	check(loaded.items.photo_used, "the look at the photo he has had this leg")
	check(loaded.phantom_muted() and loaded.heavy_floor() == _sim.heavy_floor(), "and the pill that lasts to its end")
	check_eq(_offer_ids(loaded), _offer_ids(_sim), "the vendor holds out the same things")
	check_eq(loaded.state_hash(), _sim.state_hash(), "the two simulations are the same to the bit")

	# The Telling continued from the save is the uninterrupted one.
	var script: Array[DriveInput] = _what_he_does_next(_sim)
	var differed_at: int = -1
	_collect()
	_events = []
	var loaded_rang: bool = false
	for index: int in script.size():
		_sim.step(script[index])
		loaded.step(script[index])
		loaded_rang = loaded_rang or loaded.items.caller != &""
		if index % 120 == 119 and differed_at < 0 and loaded.state_hash() != _sim.state_hash():
			differed_at = index
	check_eq(differed_at, -1, "given the same inputs for %d s they stay the same, second for second" % roundi(float(script.size()) * DT))
	check_eq(loaded.state_hash(), _sim.state_hash(), "and end the same")
	_collect()
	check(_has_event("call_started") and loaded_rang, "(in those seconds the call that was on its way came, in both)")
	check(_sim.items.item(&"cigarettes").lapse_left < 0.0 and loaded.items.item(&"cigarettes").lapse_left < 0.0, "(and so did the Craving)")
	check(not _sim.stopped and _sim.run.legs_done == 2, "(by then he has left the stop and is on the third leg)")
	check(_sim.car.s > 100.0, "(and well into it)")

	# A save that differs is another Telling. A save edited by hand has only
	# its readable numbers, and they are what is loaded then.
	var again: DriveSim = DriveSim.new(fresh_data())
	again.restore(GameData.as_dict(read.get("telling")))
	var by_hand: Dictionary = GameData.as_dict(read.get("telling")).duplicate(true)
	by_hand.erase("exact")
	var plain: DriveSim = DriveSim.new(fresh_data())
	check(plain.restore(by_hand), "a save without the exact bits still loads")
	check_near(plain.cash, again.cash, 0.001, "from its readable numbers: cash")
	check_near(plain.clock.minutes, again.clock.minutes, 0.001, "the Clock")
	check_near(plain.nerves.value, again.nerves.value, 0.001, "Nerves")
	by_hand["cash"] = GameData.as_float(by_hand.get("cash")) + 1.0
	var other: DriveSim = DriveSim.new(fresh_data())
	other.restore(by_hand)
	check_near(other.cash, again.cash + 1.0, 0.001, "one cash more in the save is one cash more in his hand")
	check(other.state_hash() != again.state_hash(), "and another state")
	# A save that says nothing of what is owed him owes him nothing.
	var silent: Dictionary = GameData.as_dict(read.get("telling")).duplicate(true)
	for entry: Variant in GameData.as_array(silent.get("items")):
		GameData.as_dict(entry).erase("lapse")
	GameData.as_dict(silent.get("item_state")).erase("call_wait")
	var unowed: DriveSim = DriveSim.new(fresh_data())
	check(unowed.restore(silent), "a save with no word of a Craving or of the next call still loads")
	check(unowed.items.item(&"cigarettes").lapse_left < 0.0, "with no Craving on its way")
	check(_call_wait(unowed) < 0.0, "and the wait for the next call still to be drawn")
	check(unowed.state_hash() != again.state_hash(), "(which is another state)")
	for exact_value: float in [0.0, -0.0, 1.0 / 3.0, 44.816666666666556, 0.15277777777777773, 1.0e-300, 123456789.12345679]:
		check_eq(Save.from_exact(Save.exact(exact_value), -1.0), exact_value, "%s survives as its bits" % str(exact_value))
		var through: Variant = JSON.parse_string(JSON.stringify({"v": Save.exact(exact_value)}))
		check_eq(Save.from_exact(GameData.as_dict(through).get("v"), -1.0), exact_value, "through the file too")
	check_eq(Save.from_exact("not bits", 7.5), 7.5, "what is not sixteen hexadecimal digits gives the fallback")
	check_eq(Save.from_exact(12, 7.5), 7.5, "and so does a number")

	# After a boss.
	_to_boss_stop()
	var boss_saved: Dictionary = _sim.checkpoint
	check_eq(GameData.as_string(boss_saved.get("stage")), "boss_stop", "after a boss the game saves too")
	check_eq(GameData.as_int(boss_saved.get("leg")), RunGenerator.LEGS_PER_ACT, "with the act's three legs behind him")
	# What he did once in the boss, and what lasts until the next leg begins,
	# the stop after it does not forget.
	var boss_leg: Dictionary = GameData.as_dict(boss_saved.get("leg_state"))
	check(GameData.as_bool(boss_leg.get("photo")), "that save holds the look at the photo he had in the boss")
	check(GameData.as_array(boss_leg.get("held")).has("drowsy") and GameData.as_array(boss_leg.get("held")).has("phantom_mute"), "and the pill he took there")
	check(_sim.items.photo_used and _sim.phantom_muted() and _sim.effects.has(&"drowsy"), "and so it is at the boss stop")
	var boss_read: Dictionary = Save.from_text(Save.to_text(profile, boss_saved))
	loaded = DriveSim.new(fresh_data())
	check(loaded.restore(GameData.as_dict(boss_read.get("telling"))), "that save loads")
	loaded.tick = _sim.tick
	check_eq(loaded.run.stage, RunState.Stage.BOSS_STOP, "at the boss stop")
	check(loaded.items.photo_used and loaded.phantom_muted() and loaded.heavy_floor() == _sim.heavy_floor(), "with the look spent and the pill at work")
	check_eq(_offer_ids(loaded), _offer_ids(_sim), "with the same three things held out")
	check_eq(loaded.state_hash(), _sim.state_hash(), "the same to the bit")
	script = _what_he_does_next(_sim)
	for index: int in script.size():
		_sim.step(script[index])
		loaded.step(script[index])
	check_eq(loaded.state_hash(), _sim.state_hash(), "and the Telling goes on the same from it")
	check_eq(_sim.run.act, 2, "(into Act 2)")

	# The game's own file: `save.json` in the user folder, written by the Game autoload.
	var kept_profile: Dictionary = Game.profile
	Game.profile = profile
	check(Game.save_path().ends_with(Save.FILE_NAME), "the game's save file is save.json")
	check(Game.write_save(saved), "the game writes it")
	check(FileAccess.file_exists(Game.save_path()), "it is on disk")
	Game.profile = Save.default_profile()
	Game.saved_telling = {}
	Game.read_save()
	check_eq(Game.profile, profile, "read again: the profile")
	check_eq(Save.to_text(Game.profile, Game.saved_telling), text, "and the Telling, as it was written")
	var from_game: DriveSim = DriveSim.new(fresh_data())
	check(from_game.restore(Game.saved_telling), "from which the Telling goes on")
	check_eq(from_game.run.stop, GameData.as_string(saved.get("stop"), from_game.run.stop), "at its stop")
	check_eq(from_game.clock.minutes, Save.from_exact(bits.get("clock_min"), -1.0), "at its hour, to the bit")
	check(Game.write_save({}), "with no Telling under way the file holds none")
	Game.read_save()
	check(Game.saved_telling.is_empty(), "and none is read")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.save_path()))
	Game.profile = kept_profile
	Game.read_save()

	# What is not a save made at a stop is not loaded.
	var untouched: DriveSim = DriveSim.new(fresh_data())
	var before: String = untouched.state_hash()
	var mid_leg: Dictionary = saved.duplicate(true)
	mid_leg["stage"] = "leg"
	check(not untouched.restore(mid_leg), "a save that claims to be made during a leg is refused")
	check(not untouched.restore({}), "and so is an empty one")
	check_eq(untouched.state_hash(), before, "and nothing is changed by it")

	# A file that cannot be read gives a new player's profile and no Telling.
	for broken: String in ["", "not a save", "[1, 2, 3]", "{\"version\": 2, \"profile\": {}, \"telling\": null}"]:
		var result: Dictionary = Save.from_text(broken)
		check(not GameData.as_bool(result.get("ok")) and not GameData.as_string(result.get("error")).is_empty(), "'%s' is not a save, and the reason is given" % broken.left(20))
		check_eq(GameData.as_dict(result.get("profile")), Save.default_profile(), "the profile is a new player's")
		check(GameData.as_dict(result.get("telling")).is_empty(), "and there is no Telling")
	var no_telling: Dictionary = Save.from_text(Save.to_text(profile, {}))
	check(GameData.as_bool(no_telling.get("ok")) and GameData.as_dict(no_telling.get("telling")).is_empty(), "a save with no Telling under way has none")
	check_eq(GameData.as_dict(no_telling.get("profile")), profile, "and keeps the profile")

	# Seeds too large for a JSON number survive as text.
	var large: int = Rng.derive(telling_seed, RunState.RETELLING_SALT + 1)
	for seed_value: int in [0, 7, 4242, large, 9007199254740993, -large]:
		var through: Variant = JSON.parse_string(JSON.stringify({"seed": Save.seed_out(seed_value)}, "", false, true))
		check_eq(Save.seed_in(GameData.as_dict(through).get("seed")), seed_value, "the seed %d comes back from the file" % seed_value)


## T-REPLAY-01: A recorded input log replays to the same final state hash.
func test_replay_01() -> void:
	var telling_seed: int = 4242
	var log: InputLog = InputLog.new()
	_sim.input_log = log
	_sim.begin_telling(TABLE, telling_seed)
	var checker: LegChecker = LegChecker.new(data)
	var lined: Dictionary = {}
	var seconds: float = 75.0
	var ticks: int = int(seconds / DT)
	var gripped_ticks: int = 0
	var steered: float = 0.0
	var lever: int = _sim.hand.anchor_index(DriveSim.GEAR_LEVER)
	var horn: int = _sim.hand.anchor_index(&"horn")
	var unit: float = tuning.f("gate_unit")
	for tick: int in ticks:
		var time: float = float(tick) * DT
		_input.clear()
		if time < 0.6:
			# The horn first: a TAP at the hub.
			_input.pointer_is_absolute = true
			_input.pointer = _sim.hand.anchor_pointer(horn)
			_input.lmb = time > 0.4 and time < 0.5
		elif time < 1.4:
			# First to second: straight back, two units.
			_input.pointer_is_absolute = time < 1.0
			_input.pointer = _sim.hand.anchor_pointer(lever)
			_input.lmb = time >= 1.0 and time < 1.35
			if time >= 1.05 and time < 1.25:
				_input.pointer_delta = Vector2(0.0, 2.2 * unit / (0.2 / DT))
		elif time < 2.6:
			# Second to third: forward, across, forward.
			_input.pointer_is_absolute = time < 1.9
			_input.pointer = _sim.hand.anchor_pointer(lever)
			_input.lmb = time >= 1.9 and time < 2.55
			if time >= 1.95 and time < 2.1:
				_input.pointer_delta = Vector2(0.0, -1.0 * unit / (0.15 / DT))
			elif time >= 2.1 and time < 2.25:
				_input.pointer_delta = Vector2(1.0 * unit / (0.15 / DT), 0.0)
			elif time >= 2.25 and time < 2.45:
				_input.pointer_delta = Vector2(0.0, -1.3 * unit / (0.2 / DT))
		else:
			# The wheel: held from here on, steered toward a line.
			_input.lmb = true
			if not _sim.hand.gripping:
				_input.pointer_is_absolute = true
				_input.pointer = _sim.space.point_to_pointer(_sim.space.grip_reference)
			else:
				gripped_ticks += 1
				var target_x: float = _sim.car.road_right() * 0.25
				if _sim.run.stage == RunState.Stage.LEG:
					if not is_same(lined, _sim.leg.plan):
						lined = _sim.leg.plan
						checker.load_plan(lined)
					target_x = checker.line_x(_sim.car.s)
				var want_v: float = clampf((target_x - _sim.car.x) * 1.5, -2.5, 2.5) + tuning.f("crown_drift") * -1.0
				var want_angle: float = _sim.wheel.max_angle() * want_v / (tuning.f("lat_per_kmh") * maxf(_sim.car.speed, 20.0))
				var px: float = clampf((want_angle - _sim.wheel.command) / tuning.f("steer_deg_per_px"), -60.0, 60.0)
				_input.pointer_delta = Vector2(px, 0.0)
				steered += absf(px)
			# A dab at the brake now and then, and the thumb keys.
			_input.rmb = fmod(time, 17.0) > 16.5
			_input.pad_horn = fmod(time, 23.0) > 22.9
			_input.pad_wiper = tick % 1900 == 0
		_sim.step(_input)
		_collect()
	var final_hash: String = _sim.state_hash()
	check_eq(log.size(), ticks, "the log holds one entry for each tick (%d)" % ticks)
	check_eq(_sim.gate.gear, 3, "(the session: he shifted from first to third with the lever)")
	check(_has_event("ritual_completed"), "(sounded the horn)")
	check(gripped_ticks > ticks / 2 and steered > 1000.0, "(and held and worked the wheel)")
	check_eq(_sim.run.stage, RunState.Stage.LEG, "(through the first fork and along a leg)")
	check(_sim.car.s > 1500.0, "(%s m of it)" % str(snappedf(_sim.car.s, 1.0)))
	note("%d ticks, %d lamps lit, %s m into the first leg" % [ticks, _sim.faults.lamps, str(snappedf(_sim.car.s, 1.0))])

	# The log replayed into a simulation started the same way.
	var replay: DriveSim = DriveSim.new(fresh_data())
	replay.begin_telling(TABLE, telling_seed)
	var input: DriveInput = DriveInput.new()
	var same_at_half: bool = false
	for index: int in log.size():
		log.read(index, input)
		replay.step(input)
		if index == log.size() / 2:
			same_at_half = replay.car.s > 0.0
	check(same_at_half, "(the replay drives)")
	check_eq(replay.state_hash(), final_hash, "a recorded input log replays to the same final state hash")
	check_eq(replay.car.s, _sim.car.s, "the car is at the same metre")
	check_eq(replay.nerves.value, _sim.nerves.value, "with the same Nerves")
	check_eq(replay.cash, _sim.cash, "and the same cash")

	# Through bytes (a file) and back.
	var bytes: PackedByteArray = log.to_bytes()
	var read: InputLog = InputLog.from_bytes(bytes)
	check_eq(read.size(), log.size(), "the log survives being written out and read back")
	replay = DriveSim.new(fresh_data())
	replay.begin_telling(TABLE, telling_seed)
	for index: int in read.size():
		read.read(index, input)
		replay.step(input)
	check_eq(replay.state_hash(), final_hash, "and replays to the same hash")
	check_eq(InputLog.from_bytes(PackedByteArray([1, 2, 3])).size(), 0, "bytes that are no log give an empty one")

	# The hash is of the whole state: another input, or another night, is another hash.
	replay = DriveSim.new(fresh_data())
	replay.begin_telling(TABLE, telling_seed)
	for index: int in log.size():
		log.read(index, input)
		if index == log.size() - 600:
			input.pointer_delta.x += 25.0
		replay.step(input)
	check(replay.state_hash() != final_hash, "one tick of different input, five seconds from the end, gives another hash")
	replay = DriveSim.new(fresh_data())
	replay.begin_telling(TABLE, telling_seed + 1)
	for index: int in log.size():
		log.read(index, input)
		replay.step(input)
	check(replay.state_hash() != final_hash, "the same inputs on another seed give another hash")
	replay = DriveSim.new(fresh_data())
	replay.begin_telling(TABLE, telling_seed)
	for index: int in log.size() - 1:
		log.read(index, input)
		replay.step(input)
	check(replay.state_hash() != final_hash, "and one tick short is another hash")

	# The hash is of everything the night still holds for him: what a stop
	# keeps for the road is part of it, to the second.
	var one: DriveSim = DriveSim.new(fresh_data())
	var other: DriveSim = DriveSim.new(fresh_data())
	one.items.item(&"cigarettes").lapse_left = 10.0
	other.items.item(&"cigarettes").lapse_left = 10.0
	check_eq(other.state_hash(), one.state_hash(), "(two simulations with the same Craving on its way have one hash)")
	other.items.item(&"cigarettes").lapse_left += DT
	check(other.state_hash() != one.state_hash(), "a Craving one tick further off is another hash")
	other = DriveSim.new(fresh_data())
	one = DriveSim.new(fresh_data())
	var waits: Dictionary = other.items.telling_state()
	waits["call_wait"] = Save.exact(10.0)
	other.items.set_telling_state(waits)
	check(other.state_hash() != one.state_hash(), "and so is a call that is on its way")
	other = DriveSim.new(fresh_data())
	other.items.photo_used = true
	check(other.state_hash() != one.state_hash(), "and a look at the photo that is spent")


# --- Getting there -----------------------------------------------------------

func _seed_for(stop_id: String) -> int:
	for candidate: int in range(1, 2000):
		if GameData.as_string(RunGenerator.fork(data, candidate, 1, 0)[RunState.RIGHT]["stop"]) == stop_id:
			return candidate
	fail("no seed under 2000 leads to a %s" % stop_id)
	return 1


func _roll_to_leg() -> void:
	_input.clear()
	var guard: int = int(60.0 / DT)
	while _sim.run.stage == RunState.Stage.APPROACH and guard > 0:
		guard -= 1
		_step()


## The leg he is on, without its traffic, hazards, bends and gusts.
func _quiet_this_leg() -> void:
	var plan: Dictionary = RunGenerator.plan(data, _sim.run.branch, _sim.run.act)
	for key: String in ["spawns", "hazards", "curves", "gusts", "zones"]:
		plan[key] = []
	for key: String in ["flock", "melons", "motorcade"]:
		plan[key] = {}
	_sim.gate.reset(3)
	_sim.begin_leg(plan)


func _scrape() -> void:
	var lamps: int = _sim.faults.lamps
	var lane_x: float = _sim.car.x
	var guard: int = int(5.0 / DT)
	_input.clear()
	while _sim.faults.lamps == lamps and guard > 0:
		guard -= 1
		_sim.car.x = _sim.car.guardrail_x()
		_step()
	for _tick: int in int((tuning.f("hit_immunity") + 0.2) / DT):
		_sim.car.x = lane_x
		_step()
	_sim.gate.reset(3)


func _into_stall() -> void:
	var stall: float = _sim.leg.length - tuning.f("leg_tail") + tuning.f("exit_slip_length")
	var lanes: int = _sim.car.lanes
	_sim.car.s = stall - 20.0
	_sim.gate.reset(2)
	_input.clear()
	var guard: int = int(10.0 / DT)
	while not _sim.stopped and guard > 0:
		guard -= 1
		_sim.car.x = _sim.car.lane_center(lanes)
		_sim.car.speed = tuning.f("exit_max_speed")
		_step()
	check(_sim.stopped, "(he stops at the stall)")


## From beside the stall to the gore and onto the next leg.
func _step_to_the_gore() -> void:
	var legs: int = _sim.run.legs_done
	_sim.gate.reset(3)
	_sim.car.s = _sim.leg.length - 1.0
	_input.clear()
	var guard: int = int(20.0 / DT)
	while _sim.run.legs_done == legs and guard > 0:
		guard -= 1
		_step()


func _to_boss_stop() -> void:
	_sim = DriveSim.new(fresh_data())
	_events = []
	_input.clear()
	_sim.begin_telling(TABLE, 31)
	var guard: int = 4000
	var in_boss: bool = false
	while not (_sim.stopped and _sim.run.stage == RunState.Stage.BOSS_STOP) and guard > 0:
		guard -= 1
		if _sim.stopped:
			_leave()
			continue
		if _sim.run.stage == RunState.Stage.BOSS and not in_boss:
			# In the boss: a look at the photo, and a pill for the rest of it.
			in_boss = true
			_sim.give_item(&"painkillers")
			_sim.items.complete(data.record("rituals", "visor_photo"), Gesture.DIR_DOWN)
			_sim.items.complete(data.record("rituals", "painkillers_take"), 0)
		_sim.car.x = _sim.car.lane_center(1 if _sim.car.lanes > 1 else 0)
		if _sim.leg.active and _sim.car.s < _sim.leg.length - 2.0:
			_sim.car.s = _sim.leg.length - 1.0
		_step()
	check(_sim.stopped, "(he reaches the boss stop)")


## One tick, with the bookkeeping of saves against stops.
func _step() -> void:
	var saves: int = _sim.checkpoints
	_sim.step(_input)
	var entered: bool = false
	for event: Dictionary in _sim.drain_events():
		_events.append(event)
		if GameData.as_string(event.get("type")) == "stop_entered":
			entered = true
			_stops_seen += 1
	if _sim.checkpoints != saves:
		_saves_seen += _sim.checkpoints - saves
		if not entered:
			_saves_off_stop += 1


# --- The hand ----------------------------------------------------------------

func _tap(anchor: String) -> void:
	_input.clear()
	_input.pointer_is_absolute = true
	_input.pointer = _sim.hand.anchor_pointer(_sim.hand.anchor_index(StringName(anchor)))
	for _tick: int in int(1.5 / DT):
		_step()
	_input.lmb = true
	for _tick: int in int(0.08 / DT):
		_step()
	_input.lmb = false
	for _tick: int in int(0.3 / DT):
		_step()
	_input.clear()


func _drag(from: String, to: String) -> void:
	_input.clear()
	_input.pointer_is_absolute = true
	_input.pointer = _sim.hand.anchor_pointer(_sim.hand.anchor_index(StringName(from)))
	for _tick: int in int(1.5 / DT):
		_step()
	_input.lmb = true
	for _tick: int in int(0.1 / DT):
		_step()
	_input.pointer = _sim.hand.anchor_pointer(_sim.hand.anchor_index(StringName(to)))
	for _tick: int in int(2.5 / DT):
		_step()
	_input.lmb = false
	for _tick: int in int(0.3 / DT):
		_step()
	_input.clear()


func _leave() -> void:
	_input.clear()
	for _tick: int in int(0.2 / DT):
		_step()
	_input.pointer_is_absolute = true
	_input.pointer = _sim.space.point_to_pointer(_sim.space.grip_reference)
	_input.lmb = true
	var guard: int = int(5.0 / DT)
	while _sim.stopped and guard > 0:
		guard -= 1
		_step()
	_input.clear()
	_step()


## What a player might do from a stop on, as a fixed list of inputs: a TAP
## on the first thing on the tray, the wheel taken and held, and half a
## minute of driving with the wheel worked to and fro and the brake touched.
func _what_he_does_next(sim: DriveSim) -> Array[DriveInput]:
	var script: Array[DriveInput] = []
	var tray: Vector2 = sim.hand.anchor_pointer(sim.hand.anchor_index(&"offer_1"))
	var rim: Vector2 = sim.space.point_to_pointer(sim.space.grip_reference)
	for tick: int in int(42.0 / DT):
		var time: float = float(tick) * DT
		var input: DriveInput = DriveInput.new()
		if time < 2.0:
			input.pointer_is_absolute = true
			input.pointer = tray
			input.lmb = time > 1.6 and time < 1.7
		elif time < 2.4:
			pass
		elif time < 3.2:
			input.pointer_is_absolute = true
			input.pointer = rim
			input.lmb = time > 2.6
		else:
			input.lmb = true
			# To and fro a little, more to the left than to the right: the crown pushes right.
			# The wheel a little to the left against the road's crown, then to and fro.
			if time < 3.3:
				input.pointer_delta = Vector2(-4.0, 0.0)
			else:
				input.pointer_delta = Vector2(0.9 * sin(time * 1.7), 0.0)
			input.rmb = time > 30.0 and time < 30.4
		script.append(input)
	return script


# --- Looking -----------------------------------------------------------------

func _offers() -> Array[Dictionary]:
	var offers: Array[Dictionary] = _sim.snapshot()["offers"]
	return offers


func _offer_ids(sim: DriveSim) -> Array[String]:
	var ids: Array[String] = []
	var offers: Array[Dictionary] = sim.snapshot()["offers"]
	for offer: Dictionary in offers:
		ids.append("%s %s at %s" % [str(offer["kind"]), str(offer["id"]), str(offer["anchor"])])
	return ids


## The seconds until the phone rings next, as a save of this moment would
## hold them (negative while the wait is not drawn).
func _call_wait(sim: DriveSim) -> float:
	return Save.from_exact(GameData.as_dict(sim.capture().get("item_state")).get("call_wait"), -1.0)


## Everything in the cabin, as text, in order.
func _cabin(sim: DriveSim) -> Array[String]:
	var out: Array[String] = []
	for item: ItemSim.Item in sim.items.items:
		out.append("%s in %s with %d" % [item.id, item.slot, item.supply])
	return out


func _collect() -> void:
	for event: Dictionary in _sim.drain_events():
		_events.append(event)


func _has_event(type: String) -> bool:
	for event: Dictionary in _events:
		if GameData.as_string(event.get("type")) == type:
			return true
	return false
