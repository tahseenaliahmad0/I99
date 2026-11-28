extends TestSuite
## M4: the leg generator and the roads of a Telling (GDD 9.1, 9.2, 9.4, 12.3).

const SEEDS: int = 500
## A driven leg steps the real traffic at this rate; rectangles are metres
## long, so nothing is missed at it.
const DRIVE_DT: float = 1.0 / 30.0
const TELLINGS: int = 400
const PLANNED_TELLINGS: int = 40
## Legs of each kind driven in fourth gear along their skill line (T-GEN-04).
const SKILL_SEEDS: int = 40

var _checker: LegChecker


func before_each() -> void:
	_checker = LegChecker.new(data)


## T-GEN-01: for 500 seeds and all nine leg types, every rule in section 9.2 holds.
func test_gen_01() -> void:
	var legs: Array[Dictionary] = data.records("legs")
	check_eq(legs.size(), 9, "GDD 9.1 has nine leg types")
	var total: int = 0
	var with_modifier: int = 0
	var worst_attempts: int = 0
	for leg: Dictionary in legs:
		var id: String = GameData.as_string(leg.get("id"))
		var acts: Array = GameData.as_array(leg.get("acts"))
		var modifiers: Array = GameData.as_array(leg.get("modifiers_allowed"))
		var bad: int = 0
		for index: int in SEEDS:
			var act: int = GameData.as_int(acts[index % acts.size()])
			var modifier: String = ""
			# From Act 2 a leg may carry a modifier: every third seed does, each in turn.
			if act >= 2 and index % 3 == 0 and not modifiers.is_empty():
				modifier = GameData.as_string(modifiers[(index / 3) % modifiers.size()])
				with_modifier += 1
			var plan: Dictionary = LegGenerator.generate(data, id, act, _seed(id, index), modifier)
			total += 1
			worst_attempts = maxi(worst_attempts, GameData.as_int(plan.get("attempts")))
			var problems: PackedStringArray = _checker.check(plan)
			if not problems.is_empty():
				bad += 1
				if bad <= 2:
					fail("%s, seed %d, act %d, modifier '%s': %s" % [id, _seed(id, index), act, modifier, problems[0]])
		check_eq(bad, 0, "%s: every rule of GDD 9.2 holds for %d seeds" % [id, SEEDS])
	check_eq(total, SEEDS * 9, "500 seeds for each of the nine leg types were generated")
	check(with_modifier > 500, "legs with every kind of modifier were among them")
	check(worst_attempts <= tuning.i("gen_max_attempts"), "no leg needed more draws than gen_max_attempts")
	note("%d legs, at most %d draws for one" % [total, worst_attempts])

	_check_driven()
	_check_checker_catches()


## The plan is only as good as the arithmetic behind it. A sample of legs is
## run by the real traffic with a ghost car on the plan's line: no hit, no
## close call, nothing run over, nothing appearing on top of anything, and
## every vehicle met where the plan says.
func _check_driven() -> void:
	var driven: int = 0
	for leg: Dictionary in data.records("legs"):
		var id: String = GameData.as_string(leg.get("id"))
		var acts: Array = GameData.as_array(leg.get("acts"))
		var act: int = GameData.as_int(acts[acts.size() - 1])
		var plan: Dictionary = LegGenerator.generate(data, id, act, _seed(id, 9001), "")
		var problems: PackedStringArray = _checker.drive(plan, DRIVE_DT)
		check(problems.is_empty(), "%s, driven at par along its line: %s" % [id, _first(problems)])
		driven += 1
	# Each modifier once, on a leg that allows it.
	for modifier: Dictionary in data.records("modifiers"):
		var modifier_id: String = GameData.as_string(modifier.get("id"))
		for leg: Dictionary in data.records("legs"):
			if not GameData.as_array(leg.get("modifiers_allowed")).has(modifier_id):
				continue
			var id: String = GameData.as_string(leg.get("id"))
			var acts: Array = GameData.as_array(leg.get("acts"))
			var plan: Dictionary = LegGenerator.generate(data, id, maxi(GameData.as_int(acts[0]), 2), _seed(id, 9002), modifier_id)
			check(_checker.check(plan).is_empty(), "%s with %s: every rule holds: %s" % [id, modifier_id, _first(_checker.problems)])
			var problems: PackedStringArray = _checker.drive(plan, DRIVE_DT)
			check(problems.is_empty(), "%s with %s, driven at par along its line: %s" % [id, modifier_id, _first(problems)])
			driven += 1
			break
	check_eq(driven, 9 + data.records("modifiers").size(), "every leg type and every modifier was driven")


## Failure cases: a leg broken by hand is caught, rule by rule.
func _check_checker_catches() -> void:
	var plan: Dictionary = LegGenerator.generate(data, "rain", 2, _seed("rain", 77), "")
	check(_checker.check(plan).is_empty(), "the leg used for the failure cases is good as generated")

	# Rule 1: no event within first_event_within.
	var late: Dictionary = plan.duplicate(true)
	for entry: Variant in GameData.as_array(late["beats"]):
		var beat: Dictionary = entry
		if LegChecker.EVENT_TYPES.has(GameData.as_string(beat["type"])) and GameData.as_float(beat["s"]) <= tuning.f("first_event_within"):
			beat["type"] = "CURVE"
			beat["template"] = "curve_gentle_left"
	check(_caught(late, "rule 1"), "a leg whose first event comes late is caught (rule 1)")

	# Rule 2: fewer than two CALM beats; two CALM beats side by side.
	var restless: Dictionary = plan.duplicate(true)
	var calms_left: int = 0
	for entry: Variant in GameData.as_array(restless["beats"]):
		var beat: Dictionary = entry
		if GameData.as_string(beat["type"]) == "CALM":
			calms_left += 1
			if calms_left > 1:
				beat["type"] = "GUST"
				beat["template"] = "gust_left"
	check(_caught(restless, "rule 2"), "a leg with one CALM beat is caught (rule 2)")
	var doubled: Dictionary = plan.duplicate(true)
	var beats: Array = GameData.as_array(doubled["beats"])
	for index: int in range(1, beats.size()):
		var beat: Dictionary = beats[index]
		var before: Dictionary = beats[index - 1]
		if GameData.as_string(before["type"]) == "CALM":
			beat["type"] = "CALM"
			beat["template"] = "calm"
			break
	check(_caught(doubled, "adjacent"), "two CALM beats side by side are caught off the Open road (rule 2)")

	# The beat table: a gap between beats, a beat too long for its type.
	var gapped: Dictionary = plan.duplicate(true)
	var second: Dictionary = GameData.as_array(gapped["beats"])[1]
	second["s"] = GameData.as_float(second["s"]) + 10.0
	check(_caught(gapped, "does not follow"), "beats that do not join up are caught")
	var long_calm: Dictionary = plan.duplicate(true)
	for entry: Variant in GameData.as_array(long_calm["beats"]):
		var beat: Dictionary = entry
		if GameData.as_string(beat["type"]) == "CALM":
			beat["length"] = GameData.as_float(beat["length"]) + 30.0
			break
	check(_caught(long_calm, "outside the table"), "a beat longer than its type allows is caught")

	# Rule 3: a vehicle put on the plan's line.
	var walled: Dictionary = plan.duplicate(true)
	var spawns: Array = GameData.as_array(walled["spawns"])
	var blocker: Dictionary = {}
	for entry: Variant in spawns:
		var spawn: Dictionary = entry
		if GameData.as_float(spawn["meet_s"]) > 400.0 and GameData.as_int(spawn["change_to"]) == GameData.as_int(spawn["lane"]):
			blocker = spawn
			break
	if check(not blocker.is_empty(), "the leg has a vehicle to move onto the line"):
		var meet: float = GameData.as_float(blocker["meet_s"])
		var line_lane: int = GameData.as_int(plan["start_lane"])
		for entry: Variant in GameData.as_array(plan["path"]):
			var step: Array = entry
			if GameData.as_float(step[0]) <= meet:
				line_lane = GameData.as_int(step[1])
		blocker["lane"] = line_lane
		blocker["change_to"] = line_lane
		check(_caught(walled, "rule 3"), "a vehicle on the line through the leg is caught (rule 3)")
		var driven: PackedStringArray = _checker.drive(walled, DRIVE_DT)
		check(not driven.is_empty(), "and driving that leg along its line ends in a hit or a close call")

	# Rule 3: a hazard put on the line.
	var strewn: Dictionary = plan.duplicate(true)
	GameData.as_array(strewn["hazards"]).append({"kind": "cone", "s": 1000.0, "x": _line_x_at(plan, 1000.0)})
	check(_caught(strewn, "rule 3"), "a cone on the line is caught (rule 3)")

	# Rule 4: a vehicle that appears on top of another.
	var stacked: Dictionary = plan.duplicate(true)
	var copy: Dictionary = GameData.as_dict(GameData.as_array(stacked["spawns"])[0]).duplicate(true)
	GameData.as_array(stacked["spawns"]).append(copy)
	check(_caught(stacked, "rule 4"), "two vehicles in one place are caught (rule 4)")

	# CALM: something in reach.
	var uneasy: Dictionary = plan.duplicate(true)
	for entry: Variant in GameData.as_array(uneasy["beats"]):
		var beat: Dictionary = entry
		if GameData.as_string(beat["type"]) == "CALM":
			GameData.as_array(uneasy["hazards"]).append({"kind": "pothole", "s": GameData.as_float(beat["s"]) + 70.0, "x": 20.0})
			break
	check(_caught(uneasy, "CALM"), "a hazard in a CALM beat is caught")


func _caught(plan: Dictionary, word: String) -> bool:
	for problem: String in _checker.check(plan):
		if problem.contains(word):
			return true
	return false


## The lane centre of the plan's line at `s` (away from its lane changes).
func _line_x_at(plan: Dictionary, s: float) -> float:
	var lane: int = GameData.as_int(plan["start_lane"])
	for entry: Variant in GameData.as_array(plan["path"]):
		var step: Array = entry
		if GameData.as_float(step[0]) + tuning.f("gen_lane_change") <= s:
			lane = GameData.as_int(step[1])
	return tuning.f("lane_width") * (float(lane) + 0.5)


func _first(problems: PackedStringArray) -> String:
	return "ok" if problems.is_empty() else problems[0]


func _seed(id: String, index: int) -> int:
	return index * 7919 + int(id.hash() % 100000)


## T-GEN-04: never a sealed wall in fourth (the owner's rule, DECISIONS D-074).
func test_gen_04() -> void:
	var pace_gear: int = tuning.i("gen_skill_gear")
	check_eq(pace_gear, 4, "the skill line is drawn for fourth gear")
	check(tuning.f("gen_skill_margin") < tuning.f("gen_block_margin"), "it passes closer than the planned line does")
	check(tuning.f("gen_skill_lane_change") < tuning.f("gen_lane_change"), "and changes lane in less road")
	check_near(tuning.f("gen_skill_lane_change"), 0.75 * tuning.fi("gear_speeds", 3) / 3.6, 0.1, "in what fourth gear covers in 0.75 s")

	# A ghost in fourth gear on the plan's skill line, through the real
	# traffic: it touches nothing, on every kind of leg the rule holds on.
	var driven: int = 0
	var modifiers_driven: Dictionary = {}
	var flocks: int = 0
	for leg: Dictionary in data.records("legs"):
		var id: String = GameData.as_string(leg.get("id"))
		var kind: String = GameData.as_string(GameData.as_dict(leg.get("special")).get("kind"))
		var acts: Array = GameData.as_array(leg.get("acts"))
		var modifiers: Array = GameData.as_array(leg.get("modifiers_allowed"))
		if kind == "two_lane" or kind == "motorcade":
			# There the hold-up is the leg itself (GDD 9.3): no promise.
			var encounter: Dictionary = LegGenerator.generate(data, id, GameData.as_int(acts[0]), _seed(id, 4001), "")
			check(GameData.as_array(encounter.get("skill_path")).is_empty(), "%s: the rule does not hold, and the plan carries no skill line" % id)
			check(_checker.check(encounter).is_empty(), "%s: and is a good leg without one: %s" % [id, _first(_checker.problems)])
			continue
		var bad: int = 0
		for index: int in SKILL_SEEDS:
			var act: int = GameData.as_int(acts[index % acts.size()])
			var modifier: String = ""
			if act >= 2 and index % 2 == 0 and not modifiers.is_empty():
				modifier = GameData.as_string(modifiers[(index / 2) % modifiers.size()])
			var plan: Dictionary = LegGenerator.generate(data, id, act, _seed(id, 4100 + index), modifier)
			var problems: PackedStringArray = _checker.drive_skill(plan, DRIVE_DT)
			driven += 1
			if not modifier.is_empty():
				modifiers_driven[modifier] = true
			if not GameData.as_dict(plan.get("flock")).is_empty():
				flocks += 1
			if not problems.is_empty():
				bad += 1
				if bad <= 2:
					fail("%s, seed %d, act %d, modifier '%s': %s" % [id, _seed(id, 4100 + index), act, modifier, problems[0]])
		check_eq(bad, 0, "%s: a ghost in fourth gear on the skill line touches nothing, for %d seeds" % [id, SKILL_SEEDS])
	check_eq(driven, SKILL_SEEDS * 7, "seven kinds of leg carry ordinary traffic, and each was driven")
	check_eq(modifiers_driven.size(), data.records("modifiers").size(), "with every modifier among them")
	check(flocks > 0, "(the legs with sheep as far as the flock: its gap is timed for third gear)")

	_check_skill_line_is_needed()
	_check_skill_checker_catches()


## The check is one that can fail: the line of third gear, driven in fourth,
## does not get through; nor does a skill line with something put on it.
func _check_skill_line_is_needed() -> void:
	var blocked: int = 0
	var tried: int = 0
	for id: String in ["open_road", "rush", "rain"]:
		for index: int in 8:
			var plan: Dictionary = LegGenerator.generate(data, id, 1 + index % 3, _seed(id, 4500 + index), "")
			plan["skill_path"] = plan["path"]
			tried += 1
			if not _checker.drive_skill(plan, DRIVE_DT).is_empty():
				blocked += 1
	check(blocked >= tried - 2, "the line of third gear, driven in fourth, runs into traffic on nearly every leg (%d of %d)" % [blocked, tried])


func _check_skill_checker_catches() -> void:
	var plan: Dictionary = LegGenerator.generate(data, "rain", 2, _seed("rain", 77), "")
	check(_checker.check(plan).is_empty(), "the leg used for the failure cases is good as generated")
	check(_checker.drive_skill(plan, DRIVE_DT).is_empty(), "and its skill line is clear in fourth")

	# No skill line where the rule holds; one where it does not.
	var bare: Dictionary = plan.duplicate(true)
	bare["skill_path"] = []
	check(_caught(bare, "rule 5"), "a leg of ordinary traffic without a skill line is caught (rule 5)")
	check(not _checker.drive_skill(bare, DRIVE_DT).is_empty(), "and cannot be driven along one")
	var two_lane: Dictionary = LegGenerator.generate(data, "two_lane", 3, _seed("two_lane", 77), "")
	two_lane["skill_path"] = [[0.0, 0]]
	check(_caught(two_lane, "rule 5"), "a skill line on the two-lane road is caught: the rule does not hold there")

	# Its shape: a jump of two lanes, a start in another lane, a change that does not finish.
	var jumping: Dictionary = plan.duplicate(true)
	jumping["skill_path"] = [[0.0, 0], [400.0, 2]]
	check(_caught(jumping, "rule 5"), "a skill line that jumps two lanes or starts elsewhere is caught")
	var late: Dictionary = plan.duplicate(true)
	late["skill_path"] = [[0.0, GameData.as_int(plan["start_lane"])], [GameData.as_float(plan["length"]) - 5.0, GameData.as_int(plan["start_lane"]) - 1]]
	check(_caught(late, "does not finish"), "a skill line whose last lane change runs past the end is caught")

	# A cone on it.
	var strewn: Dictionary = plan.duplicate(true)
	_checker.load_plan(plan, true)
	GameData.as_array(strewn["hazards"]).append({"kind": "cone", "s": 1000.0, "x": _checker.line_x(1000.0)})
	# (The road lays its hazards out in the order they come.)
	GameData.as_array(strewn["hazards"]).sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return GameData.as_float(a["s"]) < GameData.as_float(b["s"]))
	var caught_as_rule_5: bool = false
	for problem: String in _checker.check(strewn):
		if problem.begins_with("rule 5") and problem.contains("cone"):
			caught_as_rule_5 = true
	check(caught_as_rule_5, "a cone on the skill line is caught (rule 5)")
	check(not _checker.drive_skill(strewn, DRIVE_DT).is_empty(), "and the ghost in fourth runs over it")

	# A wreck standing on it.
	var walled: Dictionary = plan.duplicate(true)
	var lane: int = GameData.as_int(plan["start_lane"])
	for entry: Variant in GameData.as_array(plan["skill_path"]):
		var step: Array = entry
		if GameData.as_float(step[0]) <= 1500.0:
			lane = GameData.as_int(step[1])
	GameData.as_array(walled["spawns"]).append({
		"vehicle": "hulk", "lane": lane, "speed": 0.0, "direction": 1, "role": "", "change_to": lane,
		"change_gap": 0.0, "late": false, "trigger_s": 1500.0 - tuning.f("spawn_ahead"), "ahead": tuning.f("spawn_ahead"), "meet_s": 1500.0,
	})
	GameData.as_array(walled["spawns"]).sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return GameData.as_float(a["trigger_s"]) < GameData.as_float(b["trigger_s"]))
	var struck: PackedStringArray = _checker.drive_skill(walled, DRIVE_DT)
	check(not struck.is_empty() and struck[0].contains("hit"), "a wreck standing on the skill line is hit by the ghost in fourth: %s" % _first(struck))


## T-GEN-02: the same seed gives a byte-identical leg.
func test_gen_02() -> void:
	var cases: int = 0
	for leg: Dictionary in data.records("legs"):
		var id: String = GameData.as_string(leg.get("id"))
		var acts: Array = GameData.as_array(leg.get("acts"))
		var modifiers: Array = GameData.as_array(leg.get("modifiers_allowed"))
		for index: int in 4:
			var act: int = GameData.as_int(acts[index % acts.size()])
			var modifier: String = ""
			if act >= 2 and index >= 2 and not modifiers.is_empty():
				modifier = GameData.as_string(modifiers[index % modifiers.size()])
			var first: String = LegGenerator.to_text(LegGenerator.generate(data, id, act, _seed(id, index), modifier))
			# Other legs are generated in between: nothing may carry over.
			var other: String = LegGenerator.to_text(LegGenerator.generate(data, id, act, _seed(id, index) + 1, modifier))
			LegGenerator.generate(data, "rush", 1, index, "")
			var second: String = LegGenerator.to_text(LegGenerator.generate(data, id, act, _seed(id, index), modifier))
			cases += 1
			if not check(first == second, "%s, act %d, seed %d, modifier '%s': the same seed gives the same leg, byte for byte" % [id, act, _seed(id, index), modifier]):
				note(_first_difference(first, second))
			check(first.length() > 400, "%s: the leg's text holds a whole plan (%d bytes)" % [id, first.length()])
			check(first != other, "%s: the next seed gives a different leg" % id)
	check_eq(cases, 36, "every leg type was generated twice from four seeds")

	# A Telling's forks follow from its seed alone.
	for telling: int in 5:
		for act: int in [1, 2, 3]:
			for leg_index: int in RunGenerator.LEGS_PER_ACT:
				var once: String = JSON.stringify(RunGenerator.fork(data, telling * 31 + 7, act, leg_index))
				var again: String = JSON.stringify(RunGenerator.fork(data, telling * 31 + 7, act, leg_index))
				check(once == again, "the fork before leg %d of act %d is the same for the same Telling seed" % [leg_index + 1, act])
	var forks_a: String = JSON.stringify(RunGenerator.fork(data, 1, 2, 0)) + JSON.stringify(RunGenerator.fork(data, 1, 2, 1)) + JSON.stringify(RunGenerator.fork(data, 1, 3, 2))
	var forks_b: String = JSON.stringify(RunGenerator.fork(data, 2, 2, 0)) + JSON.stringify(RunGenerator.fork(data, 2, 2, 1)) + JSON.stringify(RunGenerator.fork(data, 2, 3, 2))
	check(forks_a != forks_b, "another Telling seed gives other forks")


func _first_difference(a: String, b: String) -> String:
	for index: int in mini(a.length(), b.length()):
		if a[index] != b[index]:
			return "first difference at byte %d: '%s' against '%s'" % [index, a.substr(maxi(index - 30, 0), 60), b.substr(maxi(index - 30, 0), 60)]
	return "lengths differ: %d against %d" % [a.length(), b.length()]


## T-GEN-03: act rules of 9.1, 9.4 and 12.3 hold in generated Tellings.
func test_gen_03() -> void:
	# The leg pool of each act (GDD 12.3).
	var pools: Array[PackedStringArray] = [
		PackedStringArray(["open_road", "rush", "rain"]),
		PackedStringArray(["open_road", "rush", "rain", "night", "roadworks", "tailgater", "patrol"]),
		PackedStringArray(["open_road", "rush", "rain", "night", "roadworks", "tailgater", "patrol", "two_lane", "motorcade"]),
	]
	for act: int in [1, 2, 3]:
		var pool: PackedStringArray = RunGenerator.leg_pool(data, act)
		var wanted: PackedStringArray = pools[act - 1]
		check_eq(pool.size(), wanted.size(), "act %d draws from %d leg types" % [act, wanted.size()])
		for id: String in wanted:
			check(pool.has(id), "act %d may draw %s" % [act, id])

	var chances: PackedFloat64Array = tuning.floats("modifier_chance")
	check_near(chances[0], 0.0, 0.000001, "GDD 12.3: no leg carries a modifier in Act 1")
	check_near(chances[1], 1.0 / 3.0, 0.001, "GDD 12.3: one leg in three in Act 2")
	check_near(chances[2], 2.0 / 3.0, 0.001, "GDD 12.3: two in three in Act 3")

	var branches: PackedInt32Array = PackedInt32Array([0, 0, 0])
	var modified: PackedInt32Array = PackedInt32Array([0, 0, 0])
	var seen_legs: Dictionary = {}
	var seen_modifiers: Dictionary = {}
	var out_of_pool: int = 0
	var not_allowed: int = 0
	var same_branches: int = 0
	for telling: int in TELLINGS:
		for act: int in [1, 2, 3]:
			var pool: PackedStringArray = RunGenerator.leg_pool(data, act)
			for leg_index: int in RunGenerator.LEGS_PER_ACT:
				var fork: Array[Dictionary] = RunGenerator.fork(data, telling * 104729 + 17, act, leg_index)
				if fork.size() != RunGenerator.BRANCHES:
					fail("the fork before leg %d of act %d has %d branches" % [leg_index + 1, act, fork.size()])
					continue
				if GameData.as_string(fork[0]["leg"]) == GameData.as_string(fork[1]["leg"]):
					same_branches += 1
				for branch: Dictionary in fork:
					var leg_id: String = GameData.as_string(branch["leg"])
					var modifier: String = GameData.as_string(branch["modifier"])
					branches[act - 1] += 1
					seen_legs[leg_id] = true
					if not pool.has(leg_id):
						out_of_pool += 1
					if modifier.is_empty():
						continue
					modified[act - 1] += 1
					seen_modifiers[modifier] = true
					if not GameData.as_array(data.record("legs", leg_id).get("modifiers_allowed")).has(modifier):
						not_allowed += 1
	check_eq(out_of_pool, 0, "every branch of every fork is a leg type of its act's pool")
	check_eq(same_branches, 0, "the two branches of a fork are different leg types")
	check_eq(not_allowed, 0, "a leg carries only a modifier it allows")
	check_eq(seen_legs.size(), 9, "all nine leg types turn up in %d Tellings" % TELLINGS)
	check_eq(seen_modifiers.size(), data.records("modifiers").size(), "and all six modifiers")
	check_eq(modified[0], 0, "no leg of Act 1 carries a modifier")
	for act: int in [2, 3]:
		var share: float = float(modified[act - 1]) / float(branches[act - 1])
		check_near(share, chances[act - 1], 0.04, "act %d: about %d legs in three carry a modifier (%d of %d)" % [act, act - 1, modified[act - 1], branches[act - 1]])

	# Late signallers and traffic density, on the legs of generated Tellings.
	var late_share: PackedFloat64Array = tuning.floats("late_signaller_share")
	check_near(late_share[0], 0.0, 0.000001, "GDD 12.3: no late signallers in Act 1")
	check_near(late_share[1], 0.15, 0.000001, "GDD 12.3: 15% in Act 2")
	check_near(late_share[2], 0.30, 0.000001, "GDD 12.3: 30% in Act 3")
	check_near(tuning.f("traffic_per_act"), 2.0, 0.000001, "GDD 9.1: each act adds 2 vehicles per km")
	var beats_km: float = (tuning.f("leg_length") - tuning.f("leg_tail")) / 1000.0
	var changers: PackedInt32Array = PackedInt32Array([0, 0, 0])
	var late: PackedInt32Array = PackedInt32Array([0, 0, 0])
	var density_wrong: int = 0
	var density_checked: int = 0
	var encounter_legs: int = 0
	for telling: int in PLANNED_TELLINGS:
		for act: int in [1, 2, 3]:
			for leg_index: int in RunGenerator.LEGS_PER_ACT:
				var fork: Array[Dictionary] = RunGenerator.fork(data, telling * 104729 + 17, act, leg_index)
				var branch: Dictionary = fork[(telling + leg_index) % fork.size()]
				var plan: Dictionary = RunGenerator.plan(data, branch, act)
				var leg_id: String = GameData.as_string(plan["leg"])
				var leg: Dictionary = data.record("legs", leg_id)
				var kind: String = GameData.as_string(GameData.as_dict(leg.get("special")).get("kind"))
				var ordinary: int = 0
				for entry: Variant in GameData.as_array(plan["spawns"]):
					var spawn: Dictionary = entry
					if GameData.as_int(spawn["change_to"]) != GameData.as_int(spawn["lane"]):
						changers[act - 1] += 1
						if GameData.as_bool(spawn["late"]):
							late[act - 1] += 1
					elif GameData.as_bool(spawn["late"]):
						fail("%s: a vehicle that keeps its lane is marked as a late signaller" % leg_id)
					if GameData.as_int(spawn["direction"]) > 0 and GameData.as_int(spawn["lane"]) < GameData.as_int(plan["lanes"]) \
							and GameData.as_string(spawn["role"]).is_empty():
						ordinary += 1
						if kind == "two_lane" and (GameData.as_string(spawn["vehicle"]) != GameData.as_string(GameData.as_dict(leg.get("special")).get("truck")) \
								or not is_equal_approx(GameData.as_float(spawn["speed"]), GameData.as_float(GameData.as_dict(leg.get("special")).get("truck_speed_kmh")))):
							fail("two_lane: traffic ahead that is not one of its trucks")
				if kind == "two_lane" or kind == "motorcade":
					# These two legs take their traffic from their encounter (GDD 9.3;
					# DECISIONS D-027): T-LEG-08 and T-LEG-09 hold them to it.
					encounter_legs += 1
					if kind == "motorcade" and ordinary != 0:
						fail("motorcade: ordinary traffic on a road the motorcade fills")
					continue
				density_checked += 1
				var per_km: float = GameData.as_float(leg.get("density")) + tuning.f("traffic_per_act") * float(act - 1)
				if ordinary != roundi(per_km * beats_km):
					density_wrong += 1
					if density_wrong <= 3:
						fail("%s, act %d: %d vehicles on a leg that should carry %d (%s per km)" % [leg_id, act, ordinary, roundi(per_km * beats_km), str(per_km)])
	check_eq(density_wrong, 0, "traffic density is the leg's base plus 2 per act after the first, on %d legs" % density_checked)
	check(density_checked >= 200, "enough legs were counted (%d)" % density_checked)
	check(encounter_legs > 0, "Two-lane and Motorcade legs were among them (%d)" % encounter_legs)
	check_eq(late[0], 0, "Act 1 has no late signallers (%d lane changes)" % changers[0])
	check(changers[0] >= 30 and changers[1] >= 60 and changers[2] >= 60, "enough lane changes were planned to judge (%d, %d, %d)" % [changers[0], changers[1], changers[2]])
	for act: int in [2, 3]:
		var share: float = float(late[act - 1]) / float(maxi(changers[act - 1], 1))
		check_near(share, late_share[act - 1], 0.1, "act %d: about %d%% of lane changes are signalled late (%d of %d)" % [act, roundi(late_share[act - 1] * 100.0), late[act - 1], changers[act - 1]])
	# Light, medium and heavy (GDD 9.1), and the base traffic of GDD 12.3.
	check_near(GameData.as_float(data.record("legs", "open_road").get("density")), 6.0, 0.000001, "GDD 9.1: light traffic is 6 vehicles per km")
	check_near(GameData.as_float(data.record("legs", "rain").get("density")), 10.0, 0.000001, "medium is 10")
	check_near(GameData.as_float(data.record("legs", "rush").get("density")), 16.0, 0.000001, "heavy is 16")
