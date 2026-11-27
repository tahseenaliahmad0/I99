class_name RunGenerator
extends RefCounted
## The roads of a Telling (GDD 9.5, 11.1, 12.3): three acts of three legs.
## Before each leg the road forks, and each branch is a leg type with, from
## Act 2, perhaps a modifier. Everything follows from the Telling seed.

const ACTS: int = 3
const LEGS_PER_ACT: int = 3
const BRANCHES: int = 2
## The road between legs is the motorway of GDD 5.1: three lanes and a median.
const ROAD_LANES: int = 3
## Salts that keep the fork draws and the leg seeds apart from other uses of
## the Telling seed.
const FORK_SALT: int = 1000
const LEG_SALT: int = 2000
const BOSS_SALT: int = 3000
const HITCHER_SALT: int = 4000
## Where in each act a Table that wants a Patrol leg in every act has it.
const PATROL_SALT: int = 4500
const PATROL_LEG: String = "patrol"
## A stop's "hitcher": one stands there always, or at hitcher_chance of them.
const HITCHER_ALWAYS: String = "always"
const HITCHER_SOMETIMES: String = "sometimes"


## The leg types an act may draw (GDD 12.3): those whose data lists the act.
static func leg_pool(data: GameData, act: int) -> PackedStringArray:
	var pool: PackedStringArray = []
	for leg: Dictionary in data.records("legs"):
		if GameData.as_array(leg.get("acts")).has(float(act)):
			pool.append(GameData.as_string(leg.get("id")))
	return pool


## The two branches of the fork before leg `leg_index` (0 to 2) of `act`
## (1 to 3): [ { "leg", "modifier", "seed", "par_s", "stop" }, ... ], the left
## branch first. The two branches are different leg types. `modifier` is ""
## for none; `stop` is the stop at the leg's end.
##
## `rules` are the Table's (GDD 11.2). On a fixed road (Noor's) there is no
## fork: the list holds the one leg that comes next. At a Table that has a
## Patrol leg in every act, one place of each act (drawn from the Telling's
## seed) is a Patrol leg whichever way he goes.
static func fork(data: GameData, telling_seed: int, act: int, leg_index: int, rules: TableRules = null) -> Array[Dictionary]:
	if rules != null and rules.fixed_road():
		var fixed: Array[Dictionary] = []
		var only: String = rules.leg_at(act, leg_index)
		if data.has_record("legs", only):
			fixed.append({
				"leg": only,
				"modifier": "",
				"seed": leg_seed(telling_seed, act, leg_index, 0),
				"par_s": GameData.as_float(data.record("legs", only).get("par_s")),
				"stop": rules.stop_at(act, leg_index),
			})
		return fixed
	var slot: int = (act - 1) * LEGS_PER_ACT + leg_index
	var random: RandomNumberGenerator = Rng.seeded(Rng.derive(telling_seed, FORK_SALT + slot))
	var pool: PackedStringArray = leg_pool(data, act)
	var chance: float = data.tuning.fi("modifier_chance", clampi(act, 1, ACTS) - 1)
	var branches: Array[Dictionary] = []
	for branch: int in BRANCHES:
		if pool.is_empty():
			break
		var pick: int = random.randi_range(0, pool.size() - 1)
		var leg_id: String = pool[pick]
		if pool.size() > BRANCHES - branch - 1:
			pool.remove_at(pick)
		var leg: Dictionary = data.record("legs", leg_id)
		var modifier: String = ""
		var allowed: Array = GameData.as_array(leg.get("modifiers_allowed"))
		# The roll is always made, so a leg's modifier does not depend on what it allows.
		var roll: float = random.randf()
		var which: int = random.randi_range(0, maxi(allowed.size() - 1, 0))
		if roll < chance and not allowed.is_empty():
			modifier = GameData.as_string(allowed[which])
		branches.append({
			"leg": leg_id,
			"modifier": modifier,
			"seed": leg_seed(telling_seed, act, leg_index, branch),
			"par_s": GameData.as_float(leg.get("par_s")),
		})
	# The stop at the end of each branch (GDD 9.5), drawn after everything
	# else so that the legs of a Telling do not depend on its stops.
	for branch: Dictionary in branches:
		branch["stop"] = _draw_stop(data, random)
	if rules != null and rules.patrol_every_act and leg_index == patrol_place(telling_seed, act) and data.has_record("legs", PATROL_LEG):
		# Both roads are watched: the draws above are made all the same, so
		# that the stops and the other forks are those of any Table.
		var patrol: Dictionary = data.record("legs", PATROL_LEG)
		var allowed: Array = GameData.as_array(patrol.get("modifiers_allowed"))
		for branch: Dictionary in branches:
			branch["leg"] = PATROL_LEG
			branch["par_s"] = GameData.as_float(patrol.get("par_s"))
			if not allowed.has(branch["modifier"]):
				branch["modifier"] = ""
	return branches


## The place (0 to 2) of the Patrol leg in `act` at a Table that has one in
## every act.
static func patrol_place(telling_seed: int, act: int) -> int:
	return Rng.seeded(Rng.derive(telling_seed, PATROL_SALT + act)).randi_range(0, LEGS_PER_ACT - 1)


## One stop, by the weights of GDD 15. Stops with no weight (the shady guy,
## the boss stop) are never at the end of a leg.
static func _draw_stop(data: GameData, random: RandomNumberGenerator) -> String:
	var total: float = 0.0
	for stop: Dictionary in data.records("stops"):
		total += maxf(GameData.as_float(stop.get("weight")), 0.0)
	if total <= 0.0:
		return ""
	var roll: float = random.randf() * total
	var last: String = ""
	for stop: Dictionary in data.records("stops"):
		var weight: float = maxf(GameData.as_float(stop.get("weight")), 0.0)
		if weight <= 0.0:
			continue
		last = GameData.as_string(stop.get("id"))
		if roll < weight:
			return last
		roll -= weight
	return last


## The boss that ends an act (GDD 11.1), or {}.
static func boss_of(data: GameData, act: int) -> Dictionary:
	for boss: Dictionary in data.records("bosses"):
		if GameData.as_int(boss.get("act")) == act:
			return boss
	return {}


## The seed of an act's boss.
static func boss_seed(telling_seed: int, act: int) -> int:
	return Rng.derive(telling_seed, BOSS_SALT + act)


## The modifier the act's boss has in this Telling (GDD 10.2 to 10.4), or "":
## in boss_modifier_chance of Tellings one of the boss's own, each as likely
## as the other.
static func boss_modifier(data: GameData, telling_seed: int, act: int) -> String:
	var allowed: Array = GameData.as_array(boss_of(data, act).get("modifiers"))
	var random: RandomNumberGenerator = Rng.seeded(Rng.derive(boss_seed(telling_seed, act), 1))
	# Both draws are always made, so the one does not depend on the other.
	var roll: float = random.randf()
	var which: int = random.randi_range(0, maxi(allowed.size() - 1, 0))
	if allowed.is_empty() or roll >= data.tuning.fi("boss_modifier_chance", clampi(act, 1, ACTS) - 1):
		return ""
	return GameData.as_string(allowed[which])


## The hitcher who stands at a stop (GDD 8.1), or "": always one at a Hitcher
## stop, and one at hitcher_chance of the fuel stations and tea stalls. Who
## it is, is drawn by the Telling seed and where in the night the stop is
## (the stop after a boss is leg LEGS_PER_ACT of its act); never the
## passenger he already carries (`aboard`), nor the one who has just got out
## at this stop (`left_here`): the next of them stands there instead.
static func hitcher(data: GameData, telling_seed: int, act: int, leg_index: int, stop_id: String, aboard: String, left_here: String = "") -> String:
	var stands: String = GameData.as_string(data.record("stops", stop_id).get("hitcher")) if data.has_record("stops", stop_id) else ""
	var random: RandomNumberGenerator = Rng.seeded(Rng.derive(Rng.derive(telling_seed, HITCHER_SALT + act), leg_index))
	# Both draws are always made, so the one does not depend on the other.
	var roll: float = random.randf()
	var ids: PackedStringArray = data.record_ids("passengers")
	var which: int = random.randi_range(0, maxi(ids.size() - 1, 0))
	if ids.is_empty():
		return ""
	if stands != HITCHER_ALWAYS and (stands != HITCHER_SOMETIMES or roll >= data.tuning.f("hitcher_chance")):
		return ""
	for _next: int in ids.size():
		if ids[which] != aboard and ids[which] != left_here:
			return ids[which]
		which = (which + 1) % ids.size()
	return ""


## A stretch of road with nothing planned on it: the approach to a fork, the
## street of the Arrival; a boss's road begins as one.
static func blank_plan(act: int, lanes: int, divided: bool, length: float, par: float = 0.0) -> Dictionary:
	return {
		"leg": "", "act": act, "seed": 0, "modifier": "", "lanes": lanes, "divided": divided,
		"condition": "clear", "par_s": par, "length": length, "beats_end": length,
		"start_lane": lanes / 2, "attempts": 0, "sparse": false,
		"beats": [], "spawns": [], "hazards": [], "curves": [], "gusts": [], "zones": [],
		"flock": {}, "melons": {}, "motorcade": {}, "path": [[0.0, lanes / 2]],
	}


## The seed of one leg of a Telling.
static func leg_seed(telling_seed: int, act: int, leg_index: int, branch: int) -> int:
	var slot: int = ((act - 1) * LEGS_PER_ACT + leg_index) * BRANCHES + branch
	return Rng.derive(telling_seed, LEG_SALT + slot)


## The plan of one branch of a fork; `twist` is the Twist a guest throws
## into it ({} for none: see LegGenerator.generate).
static func plan(data: GameData, branch: Dictionary, act: int, twist: Dictionary = {}) -> Dictionary:
	return LegGenerator.generate(data, GameData.as_string(branch.get("leg")), act,
			GameData.as_int(branch.get("seed")), GameData.as_string(branch.get("modifier")), twist)
