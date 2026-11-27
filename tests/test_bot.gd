extends TestSuite
## M11: the DriverBot (GDD 13.8) and the balance runner (GDD 12.5).
## T-BOT-01. How the bot plays and what the report holds is D-068.

const KMH_TO_MS: float = 1.0 / 3.6
const DT: float = DriveSim.DT
const SEED: int = 4200

var _sim: DriveSim
var _bot: DriverBot
var _input: DriveInput


# --- Helpers -------------------------------------------------------------------

## A leg with nothing on it and nothing to do but drive: no traffic, no
## hazards, no bends, no gusts; the bot of `skill` at the wheel in third.
func _on_an_empty_road(skill: String, lane: int = 1) -> void:
	var plan: Dictionary = LegGenerator.generate(data, "open_road", 1, SEED, "")
	for key: String in ["spawns", "hazards", "curves", "gusts", "zones"]:
		plan[key] = []
	plan["path"] = [[0.0, lane]]
	plan["start_lane"] = lane
	_sim = DriveSim.new(data)
	_sim.heckling = false
	_sim.in_encounter = true
	_sim.gate.reset(3)
	_sim.begin_leg(plan)
	_sim.car.reset(lane, 3)
	_bot = DriverBot.new(_sim, data, skill, SEED)
	_input = DriveInput.new()


func _tick() -> void:
	_input.clear()
	_bot.drive(_input)
	_sim.step(_input)


func _run(seconds: float) -> void:
	for _index: int in roundi(seconds / DT):
		_tick()


func _hits() -> int:
	var hits: int = 0
	for event: Dictionary in _sim.drain_events():
		if GameData.as_string(event.get("type")) == "hit":
			hits += 1
	return hits


# --- T-BOT-01 ------------------------------------------------------------------

## T-BOT-01: The balance runner completes and writes its report. It reports
## against section 12.5 and does not fail on the numbers.
func test_bot_01() -> void:
	_check_the_skills()
	_check_reaction()
	_check_lane_keeping()
	_check_the_hand_shifts()
	_check_the_policy()
	_check_one_telling_twice()
	_check_the_report()
	_check_the_run()


## GDD 13.8's table, in tuning.
func _check_the_skills() -> void:
	check_eq(DriverBot.SKILLS, PackedStringArray(["novice", "competent", "expert"]), "GDD 13.8: three skills")
	check_eq(tuning.a("bot_reaction_s"), [0.40, 0.25, 0.15], "reaction delay 0.40, 0.25, 0.15 s")
	check_eq(tuning.a("bot_lane_error_m"), [0.25, 0.12, 0.05], "lane-keeping error 0.25, 0.12, 0.05 m")
	check_eq(tuning.a("bot_let_go_margin_s"), [2.5, 1.5, 1.0], "safety margin before letting go 2.5, 1.5, 1.0 s")
	check_eq(tuning.a("bot_cruise_gear"), [3.0, 3.0, 4.0], "cruising gear 3, 3, and 4 for the expert")
	check(tuning.fi("bot_brake_ttc_s", 0) > tuning.fi("bot_brake_ttc_s", 1), "the novice brakes sooner than the others: 'braking often'")
	check_near(tuning.f("bot_ttc_change_s"), 3.0, 0.000001, "it changes lane when time to collision falls below 3 s")
	check(DriverBot.new(DriveSim.new(data), data, "nobody", 1).skill == "competent", "(a skill nobody has is the competent one)")


## What it sees it acts on a reaction later: a slow vehicle appears close
## ahead with a vehicle on either side, and the brake comes on after the
## skill's delay.
func _check_reaction() -> void:
	for index: int in DriverBot.SKILLS.size():
		var skill: String = DriverBot.SKILLS[index]
		_on_an_empty_road(skill)
		_run(3.0)
		check(_sim.hand.gripping and not _input.rmb, "%s: on an empty road its hand is on the wheel and its foot off the brake" % skill)
		for lane: int in [0, 2]:
			_sim.traffic.spawn(&"pickup", lane, _sim.car.s, _sim.car.speed)
		_sim.traffic.spawn(&"truck", 1, _sim.car.s + 35.0, 20.0)
		var ticks: int = 0
		var guard: int = roundi(2.0 / DT)
		while guard > 0:
			guard -= 1
			_tick()
			ticks += 1
			if _input.rmb:
				break
		check_near(float(ticks) * DT, tuning.fi("bot_reaction_s", index), 2.0 * DT, "%s: the brake comes on %.2f s after there is something to brake for (%.3f s)" % [skill, tuning.fi("bot_reaction_s", index), float(ticks) * DT])


## It keeps its lane with the skill's error, and steers only with the wheel
## in its hand.
func _check_lane_keeping() -> void:
	var spreads: PackedFloat64Array = []
	for index: int in DriverBot.SKILLS.size():
		var skill: String = DriverBot.SKILLS[index]
		_on_an_empty_road(skill)
		_run(4.0)
		var centre: float = _sim.car.lane_center(1)
		var sum: float = 0.0
		var squares: float = 0.0
		var count: int = 0
		var steered_off: int = 0
		for _index: int in roundi(60.0 / DT):
			_tick()
			if not _sim.hand.gripping and absf(_input.pointer_delta.x) > 0.0 and not _input.lmb:
				steered_off += 1
			var off: float = _sim.car.x - centre
			sum += off
			squares += off * off
			count += 1
		var mean: float = sum / float(count)
		var spread: float = sqrt(maxf(squares / float(count) - mean * mean, 0.0))
		spreads.append(spread)
		var wanted: float = tuning.fi("bot_lane_error_m", index)
		check(spread > wanted * 0.4 and spread < wanted * 1.6, "%s: over a minute on a straight it is %.3f m off its line, standard deviation (the skill's is %.2f m)" % [skill, spread, wanted])
		check(absf(mean) < wanted, "%s: about the middle of its lane (mean %.3f m)" % [skill, mean])
		check_eq(steered_off, 0, "%s: it turns nothing without the wheel in its hand" % skill)
		check_eq(_sim.faults.lamps, 0, "%s: and touches nothing" % skill)
	check(spreads[0] > spreads[1] and spreads[1] > spreads[2], "the novice wanders most and the expert least (%.3f, %.3f, %.3f m)" % [spreads[0], spreads[1], spreads[2]])


## The gear is changed by the hand: off the wheel, to the lever, the lever
## held for bot_shift_s, back to the wheel. Never by itself.
func _check_the_hand_shifts() -> void:
	_on_an_empty_road("competent")
	_sim.gate.reset(tuning.i("start_gear"))
	_sim.car.speed = tuning.fi("gear_speeds", tuning.i("start_gear") - 1)
	var gear: int = _sim.gate.gear
	var changed_at_lever: int = 0
	var changed_elsewhere: int = 0
	var held: int = 0
	var off_wheel: int = 0
	var x_then: float = _sim.car.x
	var drifted: float = 0.0
	var guard: int = roundi(8.0 / DT)
	while guard > 0 and not (_sim.gate.gear == 3 and _sim.hand.gripping):
		guard -= 1
		var was_held: bool = _sim.gate.held
		_tick()
		if was_held:
			held += 1
		if not _sim.hand.gripping:
			off_wheel += 1
			drifted = maxf(drifted, absf(_sim.car.x - x_then))
		else:
			x_then = _sim.car.x
		if _sim.gate.gear != gear:
			gear = _sim.gate.gear
			if was_held and _sim.hand.at_id() == &"gear_lever":
				changed_at_lever += 1
			else:
				changed_elsewhere += 1
	check(_sim.gate.gear == 3 and _sim.hand.gripping, "from the starting gear it gets into third and has the wheel again")
	check_eq(changed_elsewhere, 0, "the gear changes nowhere but at the lever, in its hand")
	check(changed_at_lever >= 1, "(it changed there)")
	check(float(held) * DT >= tuning.f("bot_shift_s") - DT, "the lever is held for bot_shift_s (%.2f s)" % (float(held) * DT))
	check(float(off_wheel) * DT > tuning.f("bot_shift_s") + 0.2, "the hand is off the wheel for the shift and the way there and back (%.2f s)" % (float(off_wheel) * DT))
	check(drifted > 0.01, "and meanwhile the car goes where the road takes it (%.2f m)" % drifted)
	check_eq(GameData.as_int(_bot.rituals.get("gear_shift")), 1, "it counts one change of gear")
	check(_bot.hand_off_ticks >= off_wheel - 2 and _bot.road_ticks > _bot.hand_off_ticks, "and the ticks its hand was off the wheel (%d of %d)" % [_bot.hand_off_ticks, _bot.road_ticks])


## GDD 13.8's policy: the lane whose next obstacle is farthest; a change of
## lane when time to collision falls below 3 s; behind a wall of vehicles,
## the brake; the wheel let go only with time for it.
func _check_the_policy() -> void:
	for skill: String in DriverBot.SKILLS:
		# A slow truck ahead in its lane, the lanes beside it free.
		_on_an_empty_road(skill)
		_run(2.0)
		var truck: TrafficSim.Vehicle = _sim.traffic.spawn(&"truck", 1, _sim.car.s + 150.0, 60.0)
		var lane_passing: int = 1
		var hits: int = 0
		var guard: int = roundi(30.0 / DT)
		while guard > 0 and _sim.car.s < truck.s + 30.0:
			guard -= 1
			_tick()
			hits += _hits()
			if absf(_sim.car.s - truck.s) < 1.0:
				lane_passing = _sim.car.lane_of(_sim.car.x)
		check(_sim.car.s >= truck.s + 30.0, "%s: a truck doing 60 km/h in its lane with the lanes beside it free: it goes by" % skill)
		check(lane_passing != 1 and hits == 0, "%s: in another lane, touching nothing" % skill)

		# Three abreast: no lane is better. It stays behind them.
		_on_an_empty_road(skill)
		_run(2.0)
		var wall: Array[TrafficSim.Vehicle] = []
		for lane: int in 3:
			wall.append(_sim.traffic.spawn(&"truck", lane, _sim.car.s + 150.0, 60.0))
		hits = 0
		var nearest: float = INF
		for _index: int in roundi(25.0 / DT):
			_tick()
			hits += _hits()
			nearest = minf(nearest, (wall[1].s - wall[1].half_length) - (_sim.car.s + _sim.car.length() * 0.5))
		check(hits == 0 and nearest > 1.0, "%s: three trucks abreast at 60 km/h: it brakes and stays behind them (never nearer than %.1f m)" % [skill, nearest])
		check(_sim.car.speed < 75.0 and _sim.car.s < wall[1].s, "%s: at their pace (%d km/h)" % [skill, roundi(_sim.car.speed)])

	# Letting go: with a gear to change it lets go on an empty road, and not
	# with something coming up in its lane.
	_on_an_empty_road("competent")
	_sim.gate.reset(2)
	_run(1.5)
	check(not _sim.hand.gripping or _sim.gate.gear == 3, "second gear on an empty road: within 1.5 s its hand is on its way to the lever")
	_on_an_empty_road("competent")
	_run(2.0)
	_sim.gate.force_gear(2)
	# (Trucks 2 s ahead at the pace they close: less than the change of
	# gear takes with the competent bot's margin. It brakes; the hand goes
	# when braking has bought the time, and not before.)
	var closing_ms: float = (_sim.car.speed - 50.0) * KMH_TO_MS
	var needs: float = 2.0 * tuning.f("bot_reach_s") + tuning.f("bot_shift_s") + tuning.fi("bot_let_go_margin_s", 1)
	check(needs > 2.0, "(a change of gear with its margin takes the competent bot %.1f s)" % needs)
	var trucks: Array[TrafficSim.Vehicle] = []
	for lane: int in 3:
		trucks.append(_sim.traffic.spawn(&"truck", lane, _sim.car.s + 2.0 * closing_ms + 7.5, 50.0))
	var let_go_at: float = -1.0
	var time_then: float = INF
	var braked: int = 0
	for index: int in roundi(4.0 / DT):
		var gap: float = (trucks[1].s - trucks[1].half_length) - (_sim.car.s + _sim.car.length() * 0.5)
		var closing: float = (_sim.car.speed - trucks[1].speed) * KMH_TO_MS
		_tick()
		if _input.rmb:
			braked += 1
		if let_go_at < 0.0 and not _sim.hand.gripping:
			let_go_at = float(index) * DT
			time_then = gap / closing if closing > 0.0 else INF
	check(braked > 0, "second gear with trucks two seconds ahead and closing: it brakes")
	check(let_go_at < 0.0 or let_go_at > 0.5, "and its hand stays on the wheel while they are two seconds away")
	check(let_go_at < 0.0 or time_then >= needs - 0.1, "it lets go only when there is time for the lever and its margin (%.1f s to the trucks when it did)" % time_then)
	check_eq(_hits(), 0, "and touches nothing")


## The same Telling by the same bot is the same Telling.
func _check_one_telling_twice() -> void:
	var runner: BalanceRun = BalanceRun.new(data)
	var first: Dictionary = runner.tell("drivers", "competent", SEED, true, 90.0)
	var again: Dictionary = runner.tell("drivers", "competent", SEED, true, 90.0)
	var other: Dictionary = runner.tell("drivers", "competent", SEED + 1, true, 90.0)
	check_eq(GameData.as_string(first["outcome"]), BalanceRun.TIMED_OUT, "(a Telling cut short after 90 s counts as timed out)")
	check_eq(GameData.as_string(again["state"]), GameData.as_string(first["state"]), "the same Table, skill and seed twice: the same night to the bit")
	check_eq(GameData.as_int(again["road_ticks"]), GameData.as_int(first["road_ticks"]), "(and the same count of ticks on the road)")
	check(GameData.as_string(other["state"]) != GameData.as_string(first["state"]), "another seed is another night")
	check(GameData.as_int(first["road_ticks"]) > roundi(60.0 / DT), "(it drove: %d ticks on the road)" % GameData.as_int(first["road_ticks"]))


## The report's arithmetic, on Tellings made up for it: each measure of GDD
## 12.5 with its target, what was measured and whether that is within.
func _check_the_report() -> void:
	var runner: BalanceRun = BalanceRun.new(data)
	var tellings: Array[Dictionary] = []
	# Ten nights by the expert at the Drivers' Table: five won, one late,
	# four wrecked, one of those by a single hit on a car with no lamp lit.
	for index: int in 10:
		var outcome: String = BalanceRun.WON if index < 5 else (BalanceRun.LATE if index == 5 else BalanceRun.WRECKED)
		tellings.append(_telling("drivers", "expert", index, outcome, index == 9))
	# Ten by the competent bot: two won.
	for index: int in 10:
		tellings.append(_telling("drivers", "competent", index, BalanceRun.WON if index < 2 else BalanceRun.LATE, false))
	var report: Dictionary = runner.report(tellings, 10)
	check_eq(GameData.as_string(report["gdd"]), "12.5", "the report says what it reports against: GDD 12.5")
	check_eq(GameData.as_int(report["tellings"]), 20, "and how many Tellings it is of")
	var measures: Dictionary = {}
	for entry: Variant in GameData.as_array(report["measures"]):
		measures[GameData.as_string(GameData.as_dict(entry)["id"])] = GameData.as_dict(entry)
	# GDD 12.5's table, row by row.
	var rows: Array[Array] = [
		["hands_off_time", "Hands-off time from lane centre, straight, gear 3", "3.4 s (exact)"],
		["hand_off_share", "Hand off the wheel with a mid-game cabin", "25% to 40% of leg time"],
		["expert_drivers", "Expert bot, Drivers' Table, no purchases", "Wins 40% to 60% of seeds"],
		["competent_drivers", "Competent bot, Drivers' Table, buying sensibly", "Wins 15% to 30%"],
		["novice_children", "Novice bot, Children's Table", "Reaches the Checkpoint in 50% or more"],
		["one_event_wrecks", "Share of Wrecks from one unavoidable event", "0%"],
	]
	check_eq(measures.size(), rows.size(), "six measures, as GDD 12.5 has")
	for row: Array in rows:
		var id: String = GameData.as_string(row[0])
		if not check(measures.has(id), "the report has the measure '%s'" % id):
			continue
		var measure: Dictionary = measures[id]
		check(GameData.as_string(measure["measure"]).begins_with(GameData.as_string(row[1])), "%s: named as in GDD 12.5 (%s)" % [id, GameData.as_string(measure["measure"])])
		check_eq(GameData.as_string(measure["target"]), GameData.as_string(row[2]), "%s: with GDD 12.5's target" % id)
		check(measure.has("measured") and measure.has("within") and measure.has("sample"), "%s: what was measured, whether it is within, and of how many" % id)
	if measures.size() != rows.size():
		return
	check_near(GameData.as_float(measures["hands_off_time"]["measured"]), 3.4, 0.05, "hands off in third gear the lane line is 3.4 s away")
	check(GameData.as_bool(measures["hands_off_time"]["within"]), "which is within its target")
	check_near(GameData.as_float(measures["expert_drivers"]["measured"]), 0.5, 0.0001, "five wins in ten are 50%")
	check(GameData.as_bool(measures["expert_drivers"]["within"]), "within 40% to 60%")
	check_eq(GameData.as_int(measures["expert_drivers"]["sample"]), 10, "(of ten Tellings)")
	check_near(GameData.as_float(measures["competent_drivers"]["measured"]), 0.2, 0.0001, "two wins in ten are 20%: a late night is no win")
	check(GameData.as_bool(measures["competent_drivers"]["within"]), "within 15% to 30%")
	check_near(GameData.as_float(measures["hand_off_share"]["measured"]), 0.3, 0.0001, "the hand off the wheel for 300 of 1,000 ticks of Act 2's legs is 30%")
	check(GameData.as_bool(measures["hand_off_share"]["within"]), "within 25% to 40%")
	check(measures["novice_children"]["measured"] == null and not GameData.as_bool(measures["novice_children"]["within"]) and GameData.as_int(measures["novice_children"]["sample"]) == 0,
			"what was not run is not measured, and is not called within")
	check_near(GameData.as_float(measures["one_event_wrecks"]["measured"]), 0.25, 0.0001, "one Wreck in four from a single hit is 25%")
	check(not GameData.as_bool(measures["one_event_wrecks"]["within"]), "which is outside 0%")
	check_eq(GameData.as_int(GameData.as_dict(report["wrecks"])["count"]), 4, "(four Wrecks in all)")
	# Outside a target is a number in the report and nothing else.
	var poor: Array[Dictionary] = []
	for index: int in 10:
		poor.append(_telling("drivers", "expert", index, BalanceRun.WRECKED, false))
	var grim: Dictionary = runner.report(poor, 10)
	for entry: Variant in GameData.as_array(grim["measures"]):
		var measure: Dictionary = GameData.as_dict(entry)
		if GameData.as_string(measure["id"]) == "expert_drivers":
			check_near(GameData.as_float(measure["measured"]), 0.0, 0.0001, "ten Wrecks in ten are 0% won")
			check(not GameData.as_bool(measure["within"]), "the report says so: outside its target")
	# The cells: a row for each Table and skill that was run.
	var cells: Array = GameData.as_array(report["cells"])
	check_eq(cells.size(), 2, "one row for each Table and skill that was run")
	for entry: Variant in cells:
		var cell: Dictionary = GameData.as_dict(entry)
		check_eq(GameData.as_int(cell["won"]) + GameData.as_int(cell["late"]) + GameData.as_int(cell["wrecked"]) + GameData.as_int(cell["timed_out"]), GameData.as_int(cell["tellings"]),
				"%s/%s: its outcomes add up to its Tellings" % [GameData.as_string(cell["table"]), GameData.as_string(cell["skill"])])


## A Telling's record, made up.
func _telling(table: String, skill: String, index: int, outcome: String, one_hit: bool) -> Dictionary:
	return {
		"table": table, "skill": skill, "seed": index, "outcome": outcome, "ending": Save.ON_TIME if outcome == BalanceRun.WON else (Save.LATE if outcome == BalanceRun.LATE else ""),
		"act": 3, "stage": "ended", "reached_checkpoint": true, "seconds": 1200.0, "clock_minutes": 400.0, "hits": 5 if outcome == BalanceRun.WRECKED else 1,
		"lamps": 5 if outcome == BalanceRun.WRECKED else 1, "close_calls": 3, "nerves_peak": 60.0, "pulled_over": 0, "snaps": 0, "road_ticks": 1000, "hand_off_ticks": 200,
		"road_act2": 100, "hand_off_act2": 30, "stops": 3, "bought": 1, "rituals": {}, "blind_ticks": 0,
		"last_hits": [{"kind": 1, "lamps": 1, "lamps_before": 0 if one_hit else 4, "act": 3, "stage": "leg", "leg": "rush", "boss": "", "seconds": 1000.0, "gripping": true, "speed": 80, "task": ""}],
		"wreck_from_one_event": outcome == BalanceRun.WRECKED and one_hit,
	}


## The runner itself, in a build of its own: two Tellings, a report written
## where it is told to, and an exit code that does not depend on the numbers.
func _check_the_run() -> void:
	var folder: String = "user://test_runs_%d/balance" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var out: String = folder + "/balance.json"
	var captured: Array = []
	var args: PackedStringArray = ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://tools/run_balance.gd", "--",
			"--seeds=1", "--first=%d" % SEED, "--cells=children/novice,drivers/expert", "--out=" + ProjectSettings.globalize_path(out)]
	var exit_code: int = OS.execute(OS.get_executable_path(), args, captured, true)
	var output: String = ""
	for chunk: Variant in captured:
		output += str(chunk)
	output = Smoke.strip_ansi(output)
	var errors: PackedStringArray = []
	for raw: String in output.split("\n"):
		for prefix: String in Smoke.ERROR_PREFIXES:
			if raw.strip_edges().begins_with(prefix):
				errors.append(raw.strip_edges())
	check_eq(exit_code, 0, "the balance runner completes")
	check(errors.is_empty(), "with no error output; first: %s" % ("(none)" if errors.is_empty() else errors[0]))
	check(output.contains("run_balance: 2 Tellings") and output.contains("report written"), "it drove its two Tellings and says where the report is")
	if not check(FileAccess.file_exists(out), "and wrote its report"):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(out))
	if not check(parsed is Dictionary, "the report is one JSON object"):
		return
	var report: Dictionary = GameData.as_dict(parsed)
	check_eq(GameData.as_string(report.get("gdd")), "12.5", "against GDD 12.5")
	check_eq(GameData.as_int(report.get("tellings")), 2, "of the two Tellings")
	check_eq(GameData.as_array(report.get("measures")).size(), 6, "with its six measures")
	var outside: int = 0
	for entry: Variant in GameData.as_array(report.get("measures")):
		var measure: Dictionary = GameData.as_dict(entry)
		var id: String = GameData.as_string(measure.get("id"))
		if id == "expert_drivers" or id == "novice_children":
			check(measure.get("measured") != null and GameData.as_int(measure.get("sample")) == 1, "%s was measured, on one Telling" % id)
			var value: float = GameData.as_float(measure.get("measured"))
			check(is_equal_approx(value, 0.0) or is_equal_approx(value, 1.0), "(one Telling is 0%% or 100%%: %s)" % str(value))
		if id == "competent_drivers":
			check(measure.get("measured") == null, "the competent bot was not run, and its measure says so")
		if not GameData.as_bool(measure.get("within")):
			outside += 1
	check(outside >= 1, "measures outside their targets (%d of 6) and an exit code of 0: it does not fail on the numbers" % outside)
	for entry: Variant in GameData.as_array(report.get("cells")):
		var cell: Dictionary = GameData.as_dict(entry)
		check(GameData.as_int(cell.get("road_ticks")) > 0, "%s/%s: the bot was on the road" % [GameData.as_string(cell.get("table")), GameData.as_string(cell.get("skill"))])
	# What is kept in the repository: the script of GDD 13.8 and the report
	# of the last run made with it.
	check(FileAccess.file_exists("res://tools/run_balance.sh"), "GDD 13.8: tools/run_balance.sh is there")
	check(FileAccess.get_file_as_string("res://tools/run_balance.sh").contains("run_balance.gd"), "and runs the balance runner")
	if check(FileAccess.file_exists("res://artifacts/balance.json"), "GDD 13.8: artifacts/balance.json is there"):
		var kept: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://artifacts/balance.json"))
		if check(kept is Dictionary, "it is a report"):
			var kept_report: Dictionary = GameData.as_dict(kept)
			check_eq(GameData.as_array(kept_report.get("measures")).size(), 6, "with the six measures of GDD 12.5")
			var cells_kept: int = GameData.as_array(kept_report.get("cells")).size()
			check_eq(cells_kept, data.records("tables").size() * DriverBot.SKILLS.size(), "of every skill at every Table (%d cells)" % cells_kept)
			var measured: int = 0
			for entry: Variant in GameData.as_array(kept_report.get("measures")):
				if GameData.as_dict(entry).get("measured") != null:
					measured += 1
			check_eq(measured, 6, "each of them measured")
