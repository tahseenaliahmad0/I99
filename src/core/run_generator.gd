class_name RunGenerator
extends RefCounted
## The roads of a Telling (GDD 9.5, 11.1, 12.3): three acts of three legs.
## Before each leg the road forks, and each branch is a leg type with, from
## Act 2, perhaps a modifier. Everything follows from the Telling seed.

const ACTS: int = 3
const LEGS_PER_ACT: int = 3
const BRANCHES: int = 2
## Salts that keep the fork draws and the leg seeds apart from other uses of
## the Telling seed.
const FORK_SALT: int = 1000
const LEG_SALT: int = 2000


## The leg types an act may draw (GDD 12.3): those whose data lists the act.
static func leg_pool(data: GameData, act: int) -> PackedStringArray:
	var pool: PackedStringArray = []
	for leg: Dictionary in data.records("legs"):
		if GameData.as_array(leg.get("acts")).has(float(act)):
			pool.append(GameData.as_string(leg.get("id")))
	return pool


## The two branches of the fork before leg `leg_index` (0 to 2) of `act`
## (1 to 3): [ { "leg", "modifier", "seed", "par_s" }, ... ]. The two branches
## are different leg types. `modifier` is "" for none.
static func fork(data: GameData, telling_seed: int, act: int, leg_index: int) -> Array[Dictionary]:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	var slot: int = (act - 1) * LEGS_PER_ACT + leg_index
	random.seed = Rng.derive(telling_seed, FORK_SALT + slot)
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
	return branches


## The seed of one leg of a Telling.
static func leg_seed(telling_seed: int, act: int, leg_index: int, branch: int) -> int:
	var slot: int = ((act - 1) * LEGS_PER_ACT + leg_index) * BRANCHES + branch
	return Rng.derive(telling_seed, LEG_SALT + slot)


## The plan of one branch of a fork.
static func plan(data: GameData, branch: Dictionary, act: int) -> Dictionary:
	return LegGenerator.generate(data, GameData.as_string(branch.get("leg")), act,
			GameData.as_int(branch.get("seed")), GameData.as_string(branch.get("modifier")))
