class_name TouchInput
extends RefCounted
## Touch (GDD 4.1, 17.4). "Landscape only. The right thumb is the hand:
## lifting it is letting go. TAP rituals perform automatically when the
## hand arrives. HOLD, DRAG and CRANK need the gesture. The brake is a pedal
## zone at the bottom left for the left thumb. Tap targets are at least
## 9 mm across, even where the drawn object is smaller."
##
## It is fed what fingers do and fills each tick's DriveInput with it: the
## pointer where the thumb is, the button, the brake. Nothing here is the
## simulation's: a thumb plays the same game a mouse does.
##
##   - A finger that comes down in the pedal zone is his foot.
##   - A finger that comes down on the hotspot (top left) asks for the pause.
##   - Any other finger is the hand, if no finger is the hand already: the
##     pointer goes where it is and follows it.
##   - A finger beside the hand's, with the Thumb keypad fitted (GDD 7.6):
##     a tap is the horn, a swipe the wipers.
##
## The button is the thumb, with two differences from a mouse:
##   - on a TAP ritual's anchor the press is made by itself when the hand
##     arrives, though the thumb has long lifted;
##   - on any other anchor the press is made when the hand arrives with the
##     thumb still down: a HOLD is held from there, a DRAG dragged, a CRANK
##     cranked, the lever led. A thumb lifted on the way does nothing.

const MM_PER_INCH: float = 25.4
const NO_FINGER: int = -1

## A finger is on the glass, or has been: touch is how he plays.
var active: bool = false
## A tap on the hotspot: set until `take_pause()` is asked.
var pause_asked: bool = false

var _tuning: Tuning
var _hand: int = NO_FINGER
var _foot: int = NO_FINGER
var _pad: int = NO_FINGER
var _pad_from: Vector2 = Vector2.ZERO
var _pad_travel: float = 0.0
var _pad_horn_ticks: int = 0
var _pad_wiper: bool = false
## Where the thumb points (the pointer's own coordinates), and how far it
## has moved since the last tick (reference px).
var _pointer: Vector2 = Vector2.ZERO
var _has_pointer: bool = false
var _delta: Vector2 = Vector2.ZERO
var _down: bool = false
## A touch has begun and the simulation has not yet said what is under it.
var _fresh: bool = false
## The anchor a TAP waits to be made at, and ticks of the press still to go.
var _tap_at: int = HandSim.NO_ANCHOR
var _tap_ticks: int = 0
## The anchor at which the thumb's press has been made (a HOLD, a DRAG...).
var _pressed_at: int = HandSim.NO_ANCHOR


func _init(tuning: Tuning) -> void:
	_tuning = tuning


# --- The glass ------------------------------------------------------------------

## Pixels of a screen with `dpi` dots per inch that are `mm` long.
static func mm_to_px(mm: float, dpi: float) -> float:
	return mm / MM_PER_INCH * maxf(dpi, 1.0)


## The pedal zone: the bottom left of the view, touch_pedal_zone of it wide
## and high, and never less than the least tap target either way.
func pedal_zone(view: Vector2, dpi: float) -> Rect2:
	var least: float = mm_to_px(_tuning.f("touch_target_mm"), dpi)
	var size: Vector2 = Vector2(maxf(view.x * _tuning.fi("touch_pedal_zone", 0), least), maxf(view.y * _tuning.fi("touch_pedal_zone", 1), least))
	return Rect2(Vector2(0.0, view.y - size.y), size)


## The pause's hotspot (GDD 4.1): the top-left corner, a least tap target
## square, or touch_hotspot_px of the reference screen if that is more.
func hotspot(view: Vector2, dpi: float) -> Rect2:
	var side: float = maxf(mm_to_px(_tuning.f("touch_target_mm"), dpi), _tuning.f("touch_hotspot_px") * view.y / _tuning.f("reference_height"))
	return Rect2(Vector2.ZERO, Vector2(side, side))


## How near an anchor a thumb has to come down to mean it, in reference px:
## anchor_snap_radius, or half the least tap target if that is more on this
## screen (GDD 17.4: "even where the drawn object is smaller").
func snap_radius(view: Vector2, dpi: float) -> float:
	var half_target: float = mm_to_px(_tuning.f("touch_target_mm"), dpi) * 0.5 * _tuning.f("reference_height") / maxf(view.y, 1.0)
	return maxf(_tuning.f("anchor_snap_radius"), half_target)


# --- Fingers --------------------------------------------------------------------

## A finger comes down at `at` (view px). `pointer` is the place under it in
## the pointer's own coordinates.
func finger_down(finger: int, at: Vector2, pointer: Vector2, view: Vector2, dpi: float) -> void:
	active = true
	if hotspot(view, dpi).has_point(at):
		pause_asked = true
		return
	if _foot == NO_FINGER and pedal_zone(view, dpi).has_point(at):
		_foot = finger
		return
	if _hand == NO_FINGER:
		_hand = finger
		_pointer = pointer
		_has_pointer = true
		_delta = Vector2.ZERO
		_down = true
		_fresh = true
		_tap_at = HandSim.NO_ANCHOR
		_pressed_at = HandSim.NO_ANCHOR
		return
	if _pad == NO_FINGER:
		_pad = finger
		_pad_from = at
		_pad_travel = 0.0


## A finger moves to `at`; `pointer` as for finger_down, `motion` what it
## moved by in reference px (as a mouse's motion is given).
func finger_moved(finger: int, at: Vector2, pointer: Vector2, motion: Vector2) -> void:
	if finger == _hand:
		_pointer = pointer
		_delta += motion
	elif finger == _pad:
		_pad_travel = maxf(_pad_travel, at.distance_to(_pad_from))


func finger_up(finger: int) -> void:
	if finger == _foot:
		_foot = NO_FINGER
	elif finger == _hand:
		_hand = NO_FINGER
		_down = false
	elif finger == _pad:
		_pad = NO_FINGER
		# A tap is the horn, a swipe the wipers (GDD 7.6, Thumb keypad).
		if _pad_travel >= _tuning.f("flick_min_distance"):
			_pad_wiper = true
		else:
			_pad_horn_ticks = _ticks(_tuning.f("touch_tap_s"))


## True once after the hotspot was tapped.
func take_pause() -> bool:
	var asked: bool = pause_asked
	pause_asked = false
	return asked


func braking() -> bool:
	return _foot != NO_FINGER


func thumb_down() -> bool:
	return _down


# --- One tick -------------------------------------------------------------------

## Fills `input` for the tick about to be stepped.
func apply(sim: DriveSim, input: DriveInput) -> void:
	input.rmb = _foot != NO_FINGER
	input.lmb = false
	input.pad_horn = _pad_horn_ticks > 0
	_pad_horn_ticks = maxi(_pad_horn_ticks - 1, 0)
	input.pad_wiper = _pad_wiper
	_pad_wiper = false
	if not _has_pointer:
		return
	input.pointer_is_absolute = true
	input.pointer = _pointer
	input.pointer_delta = _delta
	_delta = Vector2.ZERO
	var hand: HandSim = sim.hand
	var snap: int = hand.snap_index
	if _fresh:
		# The simulation has not seen this touch yet: next tick it will say
		# what is under the thumb. Until then nothing is pressed.
		_fresh = false
		input.lmb = false
		_awaiting = true
		return
	if _awaiting:
		_awaiting = false
		if snap != HandSim.NO_ANCHOR and sim.gesture_at(snap) == "TAP":
			_tap_at = snap
	if _tap_ticks > 0:
		# The press of a TAP that is being made.
		_tap_ticks -= 1
		input.lmb = _tap_ticks > 0
		if _tap_ticks == 0:
			_tap_at = HandSim.NO_ANCHOR
		return
	if _tap_at != HandSim.NO_ANCHOR:
		# A TAP performs by itself when the hand arrives (GDD 17.4), unless
		# the thumb has gone on to something else meanwhile.
		if snap != _tap_at:
			_tap_at = HandSim.NO_ANCHOR
		elif hand.at_index == _tap_at:
			_tap_ticks = _ticks(_tuning.f("touch_tap_s"))
			input.lmb = true
			return
		else:
			return
	if hand.gripping or hand.pinned or snap == HandSim.NO_ANCHOR:
		# The wheel, a gesture under way, or nothing at all: the button is
		# the thumb. Lifting it is letting go.
		input.lmb = _down
		if not _down:
			_pressed_at = HandSim.NO_ANCHOR
		return
	# Any other anchor: the press is made when the hand arrives with the
	# thumb still down, and lasts as long as the thumb does.
	if not _down:
		_pressed_at = HandSim.NO_ANCHOR
		input.lmb = false
		return
	if _pressed_at == snap or hand.at_index == snap:
		_pressed_at = snap
		input.lmb = true


var _awaiting: bool = false


func _ticks(seconds: float) -> int:
	return maxi(roundi(seconds / DriveSim.DT), 2)
