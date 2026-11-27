class_name BalanceRun
extends RefCounted
## The balance runner (GDD 12.5, 13.8): Tellings driven by the DriverBot,
## and what they add up to against the targets of GDD 12.5.
##
##   run(tables, skills, seeds)  drives seeds x skills x Tables and returns
##                               the report
##   tell(table, skill, seed)    one Telling: how it ended and why
##
## A Telling is driven until he arrives, wrecks, or has been on the road
## longer than any night lasts. A Wreck ends it: for the numbers a night
## that wrecks is a night lost, though the game would tell it again.
##
## The report is data, not a verdict: each measure has its target, what was
## measured and whether that is within the target. Nothing here fails on
## the numbers (GDD 18.1, T-BOT-01).

const KMH_TO_MS: float = 1.0 / 3.6
## Outcomes of a Telling.
const WON: String = "won"
const LATE: String = "late"
const WRECKED: String = "wrecked"
const TIMED_OUT: String = "timed_out"

var _data: GameData
var _tuning: Tuning
## Called after each Telling with its record (for a tool's progress line).
var on_telling: Callable = Callable()


func _init(data: GameData) -> void:
	_data = data
	_tuning = data.tuning


## One Telling at `table` by a bot of `skill`: its record.
##   { table, skill, seed, outcome, ending, act, stage, reached_checkpoint,
##     seconds, clock_minutes, hits, lamps, close_calls, nerves_peak,
##     road_ticks, hand_off_ticks, hand_off_act2, road_act2, stops, bought,
##     rituals, blind_ticks, last_hits, wreck_from_one_event, state }
## `max_seconds` cuts it short (a test's); `state` is the simulation's hash
## where it ended.
func tell(table: String, skill: String, telling_seed: int, buys: bool, max_seconds: float = -1.0) -> Dictionary:
	var sim: DriveSim = DriveSim.new(_data)
	sim.begin_telling(table, telling_seed)
	var bot: DriverBot = DriverBot.new(sim, _data, skill, Rng.derive(telling_seed, DriverBot.SEED_SALT))
	bot.buys = buys
	var input: DriveInput = DriveInput.new()
	var out: Dictionary = {
		"table": table, "skill": skill, "seed": telling_seed, "outcome": TIMED_OUT, "ending": "", "act": 1, "stage": "",
		"reached_checkpoint": false, "hits": 0, "close_calls": 0, "nerves_peak": 0.0, "pulled_over": 0, "snaps": 0,
		"last_hits": [], "wreck_from_one_event": false,
	}
	var hits: Array[Dictionary] = []
	var act2_road: int = 0
	var act2_off: int = 0
	var road_before: int = 0
	var off_before: int = 0
	var lamps_before_hit: int = 0
	var guard: int = roundi((max_seconds if max_seconds > 0.0 else _tuning.f("balance_max_seconds")) / DriveSim.DT)
	var done: bool = false
	while not done and guard > 0:
		guard -= 1
		input.clear()
		bot.drive(input)
		lamps_before_hit = sim.faults.lamps
		sim.step(input)
		if sim.run.act == 2 and sim.run.stage == RunState.Stage.LEG:
			act2_road += bot.road_ticks - road_before
			act2_off += bot.hand_off_ticks - off_before
		road_before = bot.road_ticks
		off_before = bot.hand_off_ticks
		out["nerves_peak"] = maxf(GameData.as_float(out["nerves_peak"]), sim.nerves.value)
		if sim.boss.active and sim.boss.kind == BossSim.CHECKPOINT:
			out["reached_checkpoint"] = true
		for event: Dictionary in sim.drain_events():
			match GameData.as_string(event.get("type")):
				"hit":
					out["hits"] = GameData.as_int(out["hits"]) + 1
					hits.append({"kind": GameData.as_int(event.get("kind")), "lamps": GameData.as_int(event.get("lamps")), "lamps_before": lamps_before_hit,
							"act": sim.run.act, "stage": sim.run.stage_name(), "leg": sim.leg.leg_id, "boss": sim.boss.kind if sim.boss.active else "",
							"seconds": snappedf(sim.seconds(), 0.1), "gripping": sim.hand.gripping, "speed": roundi(sim.car.speed), "task": bot.task()})
				"close_call":
					out["close_calls"] = GameData.as_int(out["close_calls"]) + 1
				"pulled_over":
					out["pulled_over"] = GameData.as_int(out["pulled_over"]) + 1
				"snap":
					out["snaps"] = GameData.as_int(out["snaps"]) + 1
				"wreck":
					out["outcome"] = WRECKED
					done = true
				"arrived":
					out["ending"] = Save.ending_of(event)
					out["outcome"] = LATE if GameData.as_string(out["ending"]) == Save.LATE else WON
					done = true
	out["act"] = sim.run.act
	out["stage"] = sim.run.stage_name()
	out["seconds"] = snappedf(sim.seconds(), 0.1)
	out["clock_minutes"] = snappedf(sim.clock.minutes, 0.1)
	out["lamps"] = sim.faults.lamps
	out["road_ticks"] = bot.road_ticks
	out["hand_off_ticks"] = bot.hand_off_ticks
	out["road_act2"] = act2_road
	out["hand_off_act2"] = act2_off
	out["stops"] = bot.stops
	out["bought"] = bot.bought
	out["rituals"] = bot.rituals.duplicate()
	out["blind_ticks"] = bot.blind_ticks
	out["state"] = sim.state_hash()
	out["last_hits"] = hits.slice(maxi(hits.size() - 3, 0))
	if GameData.as_string(out["outcome"]) == WRECKED and not hits.is_empty():
		# One event did it: the hit that wrecked him found no lamp lit.
		out["wreck_from_one_event"] = GameData.as_int(hits[hits.size() - 1].get("lamps_before")) == 0
	if on_telling.is_valid():
		on_telling.call(out)
	return out


## Seconds until the car's edge reaches the lane line: from lane centre, on
## a straight, in third gear, hands off (GDD 12.5, the first measure).
func hands_off_time() -> float:
	var sim: DriveSim = DriveSim.new(_data)
	sim.in_encounter = true
	sim.gate.reset(3)
	sim.car.reset(1, 3)
	var input: DriveInput = DriveInput.new()
	var line: float = sim.car.lane_center(1) + sim.car.lane_width() * 0.5
	var guard: int = roundi(60.0 / DriveSim.DT)
	while sim.car.x + sim.car.half_width() < line and sim.car.x - sim.car.half_width() > line - sim.car.lane_width() and guard > 0:
		guard -= 1
		sim.step(input)
	return sim.seconds()


## Drives `seeds` Tellings for each skill at each Table and reports.
## `first_seed` is the first Telling's seed; the rest follow it.
func run(tables: PackedStringArray, skills: PackedStringArray, seeds: int, first_seed: int = 1) -> Dictionary:
	var tellings: Array[Dictionary] = []
	for table: String in tables:
		for skill: String in skills:
			for index: int in seeds:
				tellings.append(tell(table, skill, first_seed + index, buys_as(table, skill)))
	return report(tellings, seeds)


## GDD 12.5: the expert is measured with no purchases, the competent bot
## buying sensibly; the novice buys as the competent one does.
func buys_as(_table: String, skill: String) -> bool:
	return skill != "expert"


## The report of a set of Tellings (also of several runs put together).
func report(tellings: Array[Dictionary], seeds: int) -> Dictionary:
	var cells: Dictionary = {}
	var wrecks: int = 0
	var from_one: int = 0
	var wreck_where: Dictionary = {}
	for telling: Dictionary in tellings:
		var key: String = "%s/%s" % [GameData.as_string(telling["table"]), GameData.as_string(telling["skill"])]
		if not cells.has(key):
			cells[key] = {"table": telling["table"], "skill": telling["skill"], "tellings": 0, "won": 0, "late": 0, "wrecked": 0, "timed_out": 0,
					"reached_checkpoint": 0, "the_call": 0, "hits": 0, "seconds": 0.0, "road_ticks": 0, "hand_off_ticks": 0, "road_act2": 0, "hand_off_act2": 0,
					"stops": 0, "bought": 0, "pulled_over": 0, "snaps": 0, "nerves_peak": 0.0, "wrecked_in_act": [0, 0, 0]}
		var cell: Dictionary = cells[key]
		var outcome: String = GameData.as_string(telling["outcome"])
		cell["tellings"] = GameData.as_int(cell["tellings"]) + 1
		cell[outcome] = GameData.as_int(cell[outcome]) + 1
		if GameData.as_bool(telling["reached_checkpoint"]):
			cell["reached_checkpoint"] = GameData.as_int(cell["reached_checkpoint"]) + 1
		if GameData.as_string(telling["ending"]) == Save.THE_CALL:
			cell["the_call"] = GameData.as_int(cell["the_call"]) + 1
		for sum: String in ["hits", "road_ticks", "hand_off_ticks", "road_act2", "hand_off_act2", "stops", "bought", "pulled_over", "snaps"]:
			cell[sum] = GameData.as_int(cell[sum]) + GameData.as_int(telling[sum])
		cell["seconds"] = GameData.as_float(cell["seconds"]) + GameData.as_float(telling["seconds"])
		cell["nerves_peak"] = GameData.as_float(cell["nerves_peak"]) + GameData.as_float(telling["nerves_peak"])
		if outcome == WRECKED:
			wrecks += 1
			var in_act: Array = GameData.as_array(cell["wrecked_in_act"])
			var act: int = clampi(GameData.as_int(telling["act"]), 1, 3)
			in_act[act - 1] = GameData.as_int(in_act[act - 1]) + 1
			if GameData.as_bool(telling["wreck_from_one_event"]):
				from_one += 1
			var last: Array = GameData.as_array(telling["last_hits"])
			if not last.is_empty():
				var hit: Dictionary = GameData.as_dict(last[last.size() - 1])
				var where: String = GameData.as_string(hit.get("boss")) if not GameData.as_string(hit.get("boss")).is_empty() else GameData.as_string(hit.get("leg"))
				if where.is_empty():
					where = GameData.as_string(hit.get("stage"))
				wreck_where[where] = GameData.as_int(wreck_where.get(where)) + 1
	var rows: Array[Dictionary] = []
	for key: Variant in cells:
		var cell: Dictionary = cells[key]
		var count: float = maxf(float(GameData.as_int(cell["tellings"])), 1.0)
		cell["win_share"] = snappedf(float(GameData.as_int(cell["won"])) / count, 0.001)
		cell["checkpoint_share"] = snappedf(float(GameData.as_int(cell["reached_checkpoint"])) / count, 0.001)
		cell["hand_off_share"] = snappedf(float(GameData.as_int(cell["hand_off_ticks"])) / maxf(float(GameData.as_int(cell["road_ticks"])), 1.0), 0.001)
		cell["hand_off_share_act2"] = snappedf(float(GameData.as_int(cell["hand_off_act2"])) / maxf(float(GameData.as_int(cell["road_act2"])), 1.0), 0.001)
		cell["seconds"] = snappedf(GameData.as_float(cell["seconds"]) / count, 0.1)
		cell["nerves_peak"] = snappedf(GameData.as_float(cell["nerves_peak"]) / count, 0.1)
		rows.append(cell)
	var hands_off: float = hands_off_time()
	var measures: Array[Dictionary] = []
	measures.append(_measure("hands_off_time", "Hands-off time from lane centre, straight, gear 3", "3.4 s (exact)", hands_off, "s",
			absf(hands_off - _tuning.f("balance_hands_off_s")) <= DriveSim.DT * 0.5 + 0.05, 1))
	measures.append(_share("hand_off_share", "Hand off the wheel with a mid-game cabin (the competent bot's Act 2 legs)", "25% to 40% of leg time",
			cells.get("drivers/competent"), "hand_off_share_act2", "balance_hand_off_share"))
	measures.append(_share("expert_drivers", "Expert bot, Drivers' Table, no purchases", "Wins 40% to 60% of seeds",
			cells.get("drivers/expert"), "win_share", "balance_expert_wins"))
	measures.append(_share("competent_drivers", "Competent bot, Drivers' Table, buying sensibly", "Wins 15% to 30%",
			cells.get("drivers/competent"), "win_share", "balance_competent_wins"))
	measures.append(_share("novice_children", "Novice bot, Children's Table", "Reaches the Checkpoint in 50% or more",
			cells.get("children/novice"), "checkpoint_share", "balance_novice_checkpoint"))
	var one_share: float = float(from_one) / float(wrecks) if wrecks > 0 else 0.0
	measures.append(_measure("one_event_wrecks", "Share of Wrecks from one unavoidable event", "0%", snappedf(one_share, 0.001), "share",
			from_one == 0, wrecks))
	return {
		"gdd": "12.5",
		"seeds_per_cell": seeds,
		"tellings": tellings.size(),
		"measures": measures,
		"cells": rows,
		"wrecks": {"count": wrecks, "from_one_event": from_one, "where": wreck_where},
	}


func _measure(id: String, name: String, target: String, measured: float, unit: String, within: bool, sample: int) -> Dictionary:
	return {"id": id, "measure": name, "target": target, "measured": measured, "unit": unit, "within": within, "sample": sample}


## A measure that is a share of a cell's Tellings, against the two ends of
## its target in tuning ([low, high]). Not measured when the cell was not run.
func _share(id: String, name: String, target: String, cell: Variant, key: String, tuning_name: String) -> Dictionary:
	if cell == null:
		return {"id": id, "measure": name, "target": target, "measured": null, "unit": "share", "within": false, "sample": 0}
	var record: Dictionary = GameData.as_dict(cell)
	var value: float = GameData.as_float(record.get(key))
	var within: bool = value >= _tuning.fi(tuning_name, 0) - 0.0005 and value <= _tuning.fi(tuning_name, 1) + 0.0005
	return _measure(id, name, target, value, "share", within, GameData.as_int(record.get("tellings")))
