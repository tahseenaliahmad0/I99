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
## The modifier that boss has in this Telling ("" for none).
var boss_modifier: String = ""
## He has stopped for tea: the next fork's sign also shows the modifier of
## the boss ahead (GDD 9.6).
var boss_on_sign: bool = false
## He answered the Call (GDD 10.4, 11.4).
var call_answered: bool = false
## The stop he is at, else "".
var stop: String = ""

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
	boss_modifier = ""
	boss_on_sign = false
	call_answered = false
	stop = ""
	branch = {}
	_approach()


## The same Table, told again after a Wreck: another seed, from Baghdad.
func retell() -> void:
	retellings += 1
	begin(table, Rng.derive(seed, RETELLING_SALT + retellings))


## A Telling loaded from a save: he stands at a stop (`stage_id` is "stop",
## on the leg he took on `side` of the last fork, or "boss_stop").
func resume(table_id: String, telling_seed: int, told_again: int, in_act: int, legs_behind: int, stage_id: String, side: int) -> void:
	active = true
	table = table_id
	seed = telling_seed
	retellings = told_again
	act = clampi(in_act, 1, RunGenerator.ACTS)
	legs_done = clampi(legs_behind, 0, RunGenerator.LEGS_PER_ACT)
	boss = ""
	boss_modifier = ""
	stop = ""
	if stage_id == STAGE_NAMES[Stage.BOSS_STOP]:
		branch = {}
		branches = []
		boss = GameData.as_string(boss_record().get("id"))
		enter_boss_stop()
		return
	var fork: Array[Dictionary] = _fork(legs_done)
	branch = fork[clampi(side, 0, fork.size() - 1)] if not fork.is_empty() else {}
	branches = _fork(legs_done + 1)
	enter_stop()


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
	# The sign he has just passed was the one that showed it.
	boss_on_sign = false
	# The fork at the end of this leg, unless it is the act's third.
	branches = _fork(legs_done + 1)
	return branch


## The leg is behind him.
func leg_done() -> void:
	legs_done += 1


## The boss this act ends in, as data.
func boss_record() -> Dictionary:
	return RunGenerator.boss_of(_data, act)


func begin_boss() -> void:
	stage = Stage.BOSS
	boss = GameData.as_string(boss_record().get("id"))
	boss_modifier = modifier_ahead()
	branches = []


## The modifier of the boss this act ends in ("" for none).
func modifier_ahead() -> String:
	return RunGenerator.boss_modifier(_data, seed, act)


func enter_stop() -> void:
	stage = Stage.STOP
	stop = GameData.as_string(branch.get("stop"))


## Back on the road for the last metres of the leg.
func leave_stop() -> void:
	stage = Stage.LEG
	stop = ""


func enter_boss_stop() -> void:
	stage = Stage.BOSS_STOP
	stop = "boss_stop"


## After the boss stop: the next act's first fork, or the Arrival.
func leave_boss_stop() -> void:
	stop = ""
	boss = ""
	boss_modifier = ""
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
