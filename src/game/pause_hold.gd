class_name PauseHold
extends RefCounted
## The pointer's way to the pause (GDD 17.2: "Every function works with
## pointer motion and two buttons"; GDD 13.1 gives the pause one key, Esc).
##
## The left button held where the hand has nothing to hold: the pointer on
## no anchor and off the wheel, nothing carried, no gesture begun. A press
## there does nothing in the car, so holding it can mean this and nothing
## else, wherever the car is: on the road, at a stall, with an officer at
## the window, on the last street (D-066). It belongs to the game, not to
## the simulation, which knows nothing of pauses and plays the same.
##
## The press has to begin where the hand is free and stay there: a FLICK
## that ends in the air, or a hand that has let go of something, pauses
## nothing.

## Seconds the button is held (tuning `pause_hold_s`).
var hold_s: float = 1.0
## How far along the hold is, 0 to 1 (drawn round the pointer).
var progress: float = 0.0

var _held: float = 0.0
var _armed: bool = false
var _was_down: bool = false


func _init(seconds: float = 1.0) -> void:
	hold_s = seconds


## Starts again. A button that is down now (the press that closed the pause)
## is not a new press.
func reset(down: bool = false) -> void:
	_held = 0.0
	_armed = false
	_was_down = down
	progress = 0.0


## One tick. `down` is the left button; `free` whether the hand has nothing
## to hold where the pointer is (`DriveSim.hand_is_free()`). True in the
## tick the hold is complete, once for a press.
func step(dt: float, down: bool, free: bool) -> bool:
	var pressed: bool = down and not _was_down
	_was_down = down
	if not down or not free:
		_armed = false
		_held = 0.0
		progress = 0.0
		return false
	if pressed:
		_armed = true
		_held = 0.0
	if not _armed:
		return false
	_held += dt
	progress = clampf(_held / hold_s, 0.0, 1.0) if hold_s > 0.0 else 1.0
	if _held >= hold_s - dt * 0.5:
		_armed = false
		_held = 0.0
		progress = 0.0
		return true
	return false
