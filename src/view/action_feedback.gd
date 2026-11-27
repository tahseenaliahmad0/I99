class_name ActionFeedback
extends RefCounted
## What his hand has just done, kept for the views that show it (D-071):
## which control's gesture is being made, and a short list of pulses, one
## for each thing done ("ok") or let go of undone ("missed").
##
## It reads the snapshot and the events the simulation announces; it changes
## nothing. The controller steps it once a frame and passes the events on.

const GEAR_LEVER: String = "gear_lever"
const KIND_OK: String = "ok"
const KIND_MISSED: String = "missed"
## Something to know that is neither (the lever let go in neutral).
const KIND_NOTE: String = "note"

class Pulse:
	extends RefCounted
	var anchor: String = ""
	var kind: String = ""
	## What to say at the control, already through Lines.
	var text: String = ""
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
			_add(anchor, KIND_OK, name_of({"ritual": GameData.as_string(event.get("ritual"))}))
	elif type == "sfx_requested" and GameData.as_string(event.get("id")) == "grind":
		_ground = true
		_add(GEAR_LEVER, KIND_MISSED, Lines.get_text("hint.gear.grind"))


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
			_add(_was_pressed, KIND_MISSED, Lines.format("hint.missed", [how_of(_was_hint)]))
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
			_add(GEAR_LEVER, KIND_OK, Lines.format("hint.gear", [str(gear)]))
		elif not _ground:
			_add(GEAR_LEVER, KIND_NOTE, Lines.get_text("hint.gear.neutral"))
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


func _add(anchor: String, kind: String, text: String) -> void:
	var pulse: Pulse = Pulse.new()
	pulse.anchor = anchor
	pulse.kind = kind
	pulse.text = text
	pulses.append(pulse)


# --- The words (shared with the label under the pointer) ----------------------

## What a control is called: its ritual's own line, or the name of the item
## the ritual belongs to; "" when neither is written.
static func name_of(hint: Dictionary) -> String:
	var ritual: String = GameData.as_string(hint.get("ritual"))
	if not ritual.is_empty() and Lines.has_line("hint.ritual." + ritual):
		return Lines.get_text("hint.ritual." + ritual)
	var item: String = GameData.as_string(hint.get("item"))
	if not item.is_empty() and Lines.has_line("item.%s.name" % item):
		return Lines.get_text("item.%s.name" % item)
	return ""


## How it is worked, in words: the gesture, with its time, turns or ways.
static func how_of(hint: Dictionary) -> String:
	var gesture: String = GameData.as_string(hint.get("gesture"))
	if gesture.is_empty():
		return ""
	var id: String = "hint.gesture." + gesture.to_lower()
	if not Lines.has_line(id):
		return ""
	match gesture:
		"HOLD":
			return Lines.format(id, [_number(GameData.as_float(hint.get("amount")))])
		"CRANK":
			return Lines.format(id, [_number(GameData.as_float(hint.get("amount")))])
		"FLICK":
			var ways: PackedStringArray = []
			for dir: Variant in GameData.as_array(hint.get("dirs")):
				ways.append(Lines.get_text("hint.dir." + GameData.as_string(dir)))
			return Lines.format(id, [Lines.get_text("hint.dir.or").join(ways)])
	return Lines.get_text(id)


## 3 for 3.0, 1.2 for 1.2.
static func _number(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(roundi(value))
	return str(snappedf(value, 0.1))
