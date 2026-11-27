class_name PrologueSim
extends RefCounted
## The prologue, "Two Hands" (GDD 10.1): 75 s at dawn, 22 years ago.
##
##   "It lasts 75 s and cannot be failed. A solid left arm holds the wheel
##   and keeps the lane by itself. The pointer is the right hand, and
##   nothing it does has a cost. Each object pulses in turn and one short
##   subtitle names the action."
##
## This class is its clock: which of the seven steps is on, whether what it
## asks for has been done, and when it is over. The steps take their turns by
## the clock (prologue_step_s), done or not: nothing waits for the player
## and nothing can be missed for good. DriveSim drives the car under it,
## tells it what the right hand did, and has the left hand do its part.

## The seven steps (GDD 10.1), 1 to 7.
const RADIO: int = 1
const TEA: int = 2
const SHIFT: int = 3
const HONK: int = 4
const WIPERS: int = 5
const PHOTO: int = 6
const LIFT: int = 7
const STEPS: int = 7
## The ritual that does what a step asks ("" where it is no ritual: the
## radio is tuned until it plays music, the lever is put in third, and the
## last step asks nothing).
const RITUALS: PackedStringArray = ["", "", "tea_sip", "", "horn", "wipers", "photo_tuck", ""]
## Where the right hand goes for it: the anchor that pulses ("@tea" is
## wherever the tea glass stands).
const ANCHORS: PackedStringArray = ["", "radio", "@tea", "gear_lever", "horn", "wiper_stalk", "dash_1", ""]
const TEA_ANCHOR: String = "@tea"
## The gears of step 3: "Shift from 2nd to 3rd".
const GEAR_FROM: int = 2
const GEAR_TO: int = 3

var active: bool = false
## Seconds since it began.
var time: float = 0.0
## The step that is on, 1 to 7 (0 before it begins).
var step: int = 0
## What this step asks for has been done.
var done: bool = false

# --- What happened this tick -------------------------------------------------
## A step began: its number (0 for none).
var began: int = 0
## The step's action was done in this tick.
var done_now: bool = false
## The 75 s are over: tonight begins.
var over: bool = false

var _lengths: PackedFloat64Array = PackedFloat64Array()
var _starts: PackedFloat64Array = PackedFloat64Array()
var _length: float = 0.0


func configure(tuning: Tuning) -> void:
	_lengths = PackedFloat64Array()
	_starts = PackedFloat64Array()
	_length = 0.0
	for seconds: Variant in tuning.a("prologue_step_s"):
		_starts.append(_length)
		_lengths.append(GameData.as_float(seconds))
		_length += GameData.as_float(seconds)


func begin() -> void:
	active = true
	time = 0.0
	step = 0
	done = false
	begin_tick()


func stop() -> void:
	active = false
	step = 0
	done = false


func begin_tick() -> void:
	began = 0
	done_now = false
	over = false


## How long the whole of it lasts.
func length() -> float:
	return _length


## When step `number` (1 to 7) begins, in seconds from the start.
func step_start(number: int) -> float:
	return _starts[clampi(number, 1, _starts.size()) - 1]


func step_length(number: int) -> float:
	return _lengths[clampi(number, 1, _lengths.size()) - 1]


## One tick of its clock. A step begins in the tick its time has come; the
## prologue is over in the tick the last one has run out.
func step_clock(dt: float) -> void:
	if not active:
		return
	if step == 0:
		_begin_step(1)
	time += dt
	if time >= _length - dt * 0.5:
		active = false
		over = true
		return
	if step < _starts.size() and time >= _starts[step] - dt * 0.5:
		_begin_step(step + 1)


func _begin_step(number: int) -> void:
	step = number
	done = false
	began = number


## The right hand completed a ritual.
func ritual_done(ritual_id: String) -> void:
	if active and step >= 1 and step < RITUALS.size() and not RITUALS[step].is_empty() and RITUALS[step] == ritual_id:
		_mark_done()


## What the cabin is like now: whether the radio plays music, and the gear.
func see(radio_plays_music: bool, gear: int) -> void:
	if not active:
		return
	if (step == RADIO and radio_plays_music) or (step == SHIFT and gear == GEAR_TO):
		_mark_done()


func _mark_done() -> void:
	if not done:
		done = true
		done_now = true


## The anchor that pulses now ("" for none: the step is done, or asks for
## nothing).
func prompt() -> String:
	if not active or done or step < 1 or step >= ANCHORS.size():
		return ""
	return ANCHORS[step]


## How far the last step has run, 0 to 1: the left hand lifts off the wheel
## and the screen whites out.
func lift() -> float:
	if step != LIFT:
		return 0.0
	return clampf((time - step_start(LIFT)) / maxf(step_length(LIFT), 0.001), 0.0, 1.0)


## It rains from the fifth step on (GDD 10.1: "It rains: flick the wipers").
func raining() -> bool:
	return active and step >= WIPERS


## The left hand indicates and changes lane by itself (step 5).
func changes_lane() -> bool:
	return active and step == WIPERS
