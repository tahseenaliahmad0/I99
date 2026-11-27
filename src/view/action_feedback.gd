class_name ActionFeedback
extends RefCounted
## What his hand has just done, kept for the views that show it (D-071):
## which control's gesture is being made, and a short list of pulses, one
## for each thing done ("ok") or let go of undone ("missed").
##
## It reads the snapshot and the events the simulation announces; it changes
## nothing. The controller steps it once a frame and passes the events on.
##
## No autoload is named here or in CabinView: the tools that build a cabin
## from a script of their own (post_fx_check) compile these before the
## autoloads exist. The words are HintView's business.

const GEAR_LEVER: String = "gear_lever"
const KIND_OK: String = "ok"
const KIND_MISSED: String = "missed"
## Something to know that is neither (the lever let go in neutral).
const KIND_NOTE: String = "note"
const WHAT_RITUAL: String = "ritual"
const WHAT_MISSED: String = "missed"
const WHAT_GEAR: String = "gear"
const WHAT_NEUTRAL: String = "neutral"
const WHAT_GRIND: String = "grind"

class Pulse:
	extends RefCounted
	var anchor: String = ""
	var kind: String = ""
	## What happened: WHAT_RITUAL (a ritual was completed: `hint` names it),
	## WHAT_MISSED (`hint` is the gesture that came to nothing), WHAT_GEAR
	## (`gear` was found), WHAT_NEUTRAL, WHAT_GRIND. The words for it are
	## HintView's: nothing here reads the lines.
	var what: String = ""
	var hint: Dictionary = {}
	var gear: int = 0
	var age: float = 0.0

## Every pulse still alive, oldest first.
var pulses: Array[Pulse] = []
## The anchor whose gesture is being made now ("" for none).
var pressed: String = ""
## Seconds the gear gate's diagram stays up after the lever was let go.
var gate_linger: float = 0.0

var _life: float = 1.0
var _linger: float = 1.0
var _was_pressed: String = ""
var _was_hint: Dictionary = {}
var _done: bool = false
var _gear: int = -1
var _ground: bool = false


func setup(tuning: Tuning) -> void:
	_life = maxf(tuning.f("toast_s"), maxf(tuning.f("feedback_pop_s"), tuning.f("feedback_fail_s")))
	_linger = tuning.f("gate_diagram_linger_s")


func reset() -> void:
	pulses.clear()
	pressed = ""
	_was_pressed = ""
	_was_hint = {}
	_done = false
	_gear = -1
	_ground = false
	gate_linger = 0.0


## An event the simulation announced.
func on_event(type: String, event: Dictionary) -> void:
	if type == "ritual_completed":
		var anchor: String = GameData.as_string(event.get("anchor"))
		if anchor == _was_pressed or anchor == pressed:
			_done = true
		# (A shift made by a flick is told by the gear it found, below.)
		if anchor != GEAR_LEVER:
			_add(anchor, KIND_OK, WHAT_RITUAL, {"ritual": GameData.as_string(event.get("ritual"))})
	elif type == "sfx_requested" and GameData.as_string(event.get("id")) == "grind":
		_ground = true
		_add(GEAR_LEVER, KIND_MISSED, WHAT_GRIND)


## Once a frame, with the snapshot of that frame.
func step(snapshot: Dictionary, delta: float) -> void:
	for pulse: Pulse in pulses:
		pulse.age += delta
	while not pulses.is_empty() and pulses[0].age > _life:
		pulses.remove_at(0)

	var held: bool = snapshot["lever_held"]
	var kind: int = snapshot["gesture_kind"]
	pressed = GEAR_LEVER if held else (str(snapshot["gesture_anchor"]) if kind != Gesture.Kind.NONE else "")
	if pressed != _was_pressed:
		if not _was_pressed.is_empty() and _was_pressed != GEAR_LEVER and not _done:
			# The gesture ended and nothing came of it.
			_add(_was_pressed, KIND_MISSED, WHAT_MISSED, _was_hint)
		if not pressed.is_empty():
			_done = false
	if not pressed.is_empty():
		_was_hint = snapshot["gesture_hint"]
	_was_pressed = pressed

	# The lever: a gear found, or let go between gears.
	var gear: int = snapshot["gear"]
	if _gear == -1:
		_gear = gear
	if not held and gear != _gear:
		if gear != 0:
			_add(GEAR_LEVER, KIND_OK, WHAT_GEAR, {}, gear)
		elif not _ground:
			_add(GEAR_LEVER, KIND_NOTE, WHAT_NEUTRAL)
		_gear = gear
		_ground = false
	if held:
		gate_linger = _linger
	else:
		gate_linger = maxf(gate_linger - delta, 0.0)


## The newest pulse at an anchor, or null.
func pulse_at(anchor: String) -> Pulse:
	for index: int in range(pulses.size() - 1, -1, -1):
		if pulses[index].anchor == anchor:
			return pulses[index]
	return null


func _add(anchor: String, kind: String, what: String, hint: Dictionary = {}, gear: int = 0) -> void:
	var pulse: Pulse = Pulse.new()
	pulse.anchor = anchor
	pulse.kind = kind
	pulse.what = what
	pulse.hint = hint
	pulse.gear = gear
	pulses.append(pulse)
