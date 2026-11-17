class_name Gesture
extends RefCounted
## Recognises one gesture at a time from the button and pointer motion
## (GDD 4.4). GATE is not here: the gear lever has its own class, GearGate.
##
##   TAP        press and release within tap_max_time; completes on release
##   HOLD(t)    keep the button down for t seconds; an early release cancels
##   FLICK(dir) press, then move flick_min_distance in an allowed direction
##              within flick_max_time
##   DRAG_TO    press on the object, carry it, release over a destination
##   CRANK(n)   press, then circle the pointer for n full turns one way;
##              counts cumulative heading change
##   BEAD       a TAP, counted at most bead_max_rate times per second
##
## DriveSim calls begin() when a press is applied at an anchor and step() every
## tick. When the phase is DONE or CANCELLED it reads the result and calls
## reset(). Pointer motion is in reference pixels, y downward.

enum Kind { NONE, TAP, HOLD, FLICK, DRAG_TO, CRANK, BEAD }
enum Phase { IDLE, ACTIVE, DONE, CANCELLED }

## Direction flags for FLICK. Up is toward the top of the screen.
const DIR_UP: int = 1
const DIR_DOWN: int = 2
const DIR_LEFT: int = 4
const DIR_RIGHT: int = 8

var kind: Kind = Kind.NONE
var phase: Phase = Phase.IDLE
## Seconds since the gesture began.
var elapsed: float = 0.0
## 0 to 1 for HOLD and CRANK; 0 or 1 for the others.
var progress: float = 0.0
## FLICK: the direction flag that completed it.
var direction: int = 0
## CRANK: +1 clockwise on screen, -1 counter-clockwise, once it completes.
var crank_sign: int = 0
## DRAG_TO: set by DriveSim each tick; true while the hand rests on a destination.
var over_destination: bool = false

var _tap_max: float = 0.0
var _flick_distance: float = 0.0
var _flick_max: float = 0.0
var _bead_interval: float = 0.0
var _crank_min_step: float = 0.0

var _amount: float = 0.0
var _dirs: int = 0
var _travel: Vector2 = Vector2.ZERO
var _crank_pending: Vector2 = Vector2.ZERO
var _crank_heading: float = 0.0
var _crank_has_heading: bool = false
var _crank_turned: float = 0.0
var _clock: float = 0.0
var _last_bead: float = -INF


func configure(tuning: Tuning) -> void:
	_tap_max = tuning.f("tap_max_time")
	_flick_distance = tuning.f("flick_min_distance")
	_flick_max = tuning.f("flick_max_time")
	_bead_interval = 1.0 / tuning.f("bead_max_rate")
	_crank_min_step = tuning.f("crank_min_step")


## Starts a gesture at the moment a press is applied.
## `amount` is the HOLD time in seconds or the CRANK turns.
## `dirs` is the set of DIR_* flags a FLICK accepts.
func begin(gesture_kind: Kind, amount: float = 0.0, dirs: int = 0) -> void:
	kind = gesture_kind
	phase = Phase.ACTIVE if gesture_kind != Kind.NONE else Phase.IDLE
	elapsed = 0.0
	progress = 0.0
	direction = 0
	crank_sign = 0
	over_destination = false
	_amount = amount
	_dirs = dirs
	_travel = Vector2.ZERO
	_crank_pending = Vector2.ZERO
	_crank_has_heading = false
	_crank_turned = 0.0


func reset() -> void:
	kind = Kind.NONE
	phase = Phase.IDLE
	elapsed = 0.0
	progress = 0.0


func cancel() -> void:
	if phase == Phase.ACTIVE:
		phase = Phase.CANCELLED
		progress = 0.0


func is_active() -> bool:
	return phase == Phase.ACTIVE


## One tick. `down` is the button; `delta` is pointer motion this tick.
func step(dt: float, down: bool, delta: Vector2) -> void:
	_clock += dt
	if phase != Phase.ACTIVE:
		return
	elapsed += dt
	match kind:
		Kind.TAP:
			_step_tap(down)
		Kind.BEAD:
			_step_tap(down)
			if phase == Phase.DONE:
				if _clock - _last_bead < _bead_interval - dt * 0.5:
					phase = Phase.CANCELLED
					progress = 0.0
				else:
					_last_bead = _clock
		Kind.HOLD:
			if elapsed >= _amount - dt * 0.5 and down:
				_finish()
			elif not down:
				cancel()
			elif _amount > 0.0:
				progress = clampf(elapsed / _amount, 0.0, 1.0)
		Kind.FLICK:
			_step_flick(down, delta, dt)
		Kind.CRANK:
			_step_crank(down, delta)
		Kind.DRAG_TO:
			if not down:
				if over_destination:
					_finish()
				else:
					cancel()


func _finish() -> void:
	phase = Phase.DONE
	progress = 1.0


func _step_tap(down: bool) -> void:
	if elapsed > _tap_max + 0.000001 and down:
		cancel()
	elif not down:
		if elapsed <= _tap_max + 0.000001:
			_finish()
		else:
			cancel()


func _step_flick(down: bool, delta: Vector2, dt: float) -> void:
	if not down:
		cancel()
		return
	_travel += delta
	var best: int = 0
	var best_distance: float = 0.0
	if _dirs & DIR_UP and -_travel.y > best_distance:
		best = DIR_UP
		best_distance = -_travel.y
	if _dirs & DIR_DOWN and _travel.y > best_distance:
		best = DIR_DOWN
		best_distance = _travel.y
	if _dirs & DIR_LEFT and -_travel.x > best_distance:
		best = DIR_LEFT
		best_distance = -_travel.x
	if _dirs & DIR_RIGHT and _travel.x > best_distance:
		best = DIR_RIGHT
		best_distance = _travel.x
	if best != 0 and best_distance >= _flick_distance and elapsed <= _flick_max + dt * 0.5:
		direction = best
		_finish()
	elif elapsed > _flick_max:
		cancel()


func _step_crank(down: bool, delta: Vector2) -> void:
	if not down:
		cancel()
		return
	_crank_pending += delta
	if _crank_pending.length() < _crank_min_step:
		return
	var heading: float = _crank_pending.angle()
	_crank_pending = Vector2.ZERO
	if _crank_has_heading:
		_crank_turned += angle_difference(_crank_heading, heading)
	_crank_heading = heading
	_crank_has_heading = true
	var needed: float = _amount * TAU
	if needed > 0.0:
		progress = clampf(absf(_crank_turned) / needed, 0.0, 1.0)
	if absf(_crank_turned) >= needed:
		crank_sign = 1 if _crank_turned > 0.0 else -1
		_finish()
