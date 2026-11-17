class_name RunState
extends RefCounted
## A Telling (GDD 11.1): where he is in the night.
##
##   Fork > Leg > Exit/Stop  (x3)  > Boss > Boss stop      = one act
##   three acts, then the Arrival
##
## The road is driven in stretches: the approach to a fork, a leg (whose last
## 300 m hold the Exit and the next fork), a boss, the street of the Arrival.
## This class knows which stretch comes next; DriveSim drives them.

enum Stage { NONE, APPROACH, LEG, STOP, BOSS, BOSS_STOP, ARRIVAL, ENDED }
const STAGE_NAMES: PackedStringArray = ["none", "approach", "leg", "stop", "boss", "boss_stop", "arrival", "ended"]
const LEFT: int = 0
const RIGHT: int = 1
## Keeps the seed of a Telling told again after a Wreck apart from the first.
const RETELLING_SALT: int = 3000

var active: bool = false
var table: String = ""
## The Telling seed: the roads, the shops, the fault deck follow from it.
var seed: int = 0
## How often this Telling has been told again after a Wreck.
var retellings: int = 0
## 1 to 3.
var act: int = 1
## Legs of this act that are behind him, 0 to 3.
var legs_done: int = 0
var stage: Stage = Stage.NONE
## The fork ahead: its left and right branch; empty when the road does not fork.
var branches: Array[Dictionary] = []
## The leg he is on (or was on last): { leg, modifier, seed, par_s, stop }.
var branch: Dictionary = {}
## The boss of this act once he is in it, else "".
var boss: String = ""
## The stop he is at, else "".
var stop: String = ""
## True after a leg with no lamp lit: the shady guy is at the next stop (GDD 9.6).
var shady_next: bool = false

var _data: GameData


func configure(data: GameData) -> void:
	_data = data


## Starts a Telling at its first fork.
func begin(table_id: String, telling_seed: int) -> void:
	active = true
	table = table_id
	seed = telling_seed
	act = 1
	legs_done = 0
	boss = ""
	stop = ""
	branch = {}
	shady_next = false
	_approach()


## The same Table, told again after a Wreck: another seed, from Baghdad.
func retell() -> void:
	retellings += 1
	begin(table, Rng.derive(seed, RETELLING_SALT + retellings))


func stage_name() -> String:
	return STAGE_NAMES[stage]


func fork_ahead() -> bool:
	return not branches.is_empty() and (stage == Stage.APPROACH or stage == Stage.LEG)


## The car is at the gore: it takes the branch on its side. Returns the leg.
func take_branch(side: int) -> Dictionary:
	if branches.is_empty():
		push_error("RunState: there is no fork here")
		return {}
	branch = branches[clampi(side, 0, branches.size() - 1)]
	stage = Stage.LEG
	stop = ""
	# The fork at the end of this leg, unless it is the act's third.
	branches = _fork(legs_done + 1)
	return branch


## The leg is behind him. `clean` when it lit no lamp.
func leg_done(clean: bool) -> void:
	legs_done += 1
	shady_next = clean


## The boss this act ends in, as data.
func boss_record() -> Dictionary:
	return RunGenerator.boss_of(_data, act)


func begin_boss() -> void:
	stage = Stage.BOSS
	boss = GameData.as_string(boss_record().get("id"))
	branches = []


func enter_stop() -> void:
	stage = Stage.STOP
	stop = GameData.as_string(branch.get("stop"))


## Back on the road for the last metres of the leg.
func leave_stop() -> void:
	stage = Stage.LEG
	stop = ""
	shady_next = false


func enter_boss_stop() -> void:
	stage = Stage.BOSS_STOP
	stop = "boss_stop"


## After the boss stop: the next act's first fork, or the Arrival.
func leave_boss_stop() -> void:
	stop = ""
	boss = ""
	shady_next = false
	if act >= RunGenerator.ACTS:
		stage = Stage.ARRIVAL
		branches = []
		return
	act += 1
	legs_done = 0
	_approach()


func arrive() -> void:
	stage = Stage.ENDED
	active = false


func _approach() -> void:
	stage = Stage.APPROACH
	branches = _fork(legs_done)


## The fork before leg `index` of this act: none after the act's third leg.
func _fork(index: int) -> Array[Dictionary]:
	if index >= RunGenerator.LEGS_PER_ACT:
		var none: Array[Dictionary] = []
		return none
	return RunGenerator.fork(_data, seed, act, index)
