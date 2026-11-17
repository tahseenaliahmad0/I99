extends TestSuite
## M1: the gear gate (GDD 4.5).

const DT: float = DriveSim.DT
## Pointer travel per tick while dragging the lever, in reference pixels.
const DRAG_PX_PER_TICK: float = 4.0

var _gate: GearGate
var _unit: float = 0.0


func before_each() -> void:
	_gate = GearGate.new()
	_gate.configure(tuning)
	_gate.reset(GearGate.NEUTRAL)
	_unit = tuning.f("gate_unit")


## T-GATE-01: scripted lever paths engage gears 1 to 4, and 5 only with Fifth gear.
func test_gate_01() -> void:
	# From neutral, the H pattern: [sideways, forward] in gate units.
	var paths: Dictionary = {
		1: [Vector2(-1.0, 0.0), Vector2(0.0, 1.0)],
		2: [Vector2(-1.0, 0.0), Vector2(0.0, -1.0)],
		3: [Vector2(0.0, 1.0)],
		4: [Vector2(0.0, -1.0)],
	}
	for gear: int in [1, 2, 3, 4]:
		_gate.reset(GearGate.NEUTRAL)
		var legs: Array = paths[gear]
		_shift(legs)
		check_eq(_gate.gear, gear, "the path for gear %d engages it" % gear)
		check(_gate.lever.is_equal_approx(GearGate.gear_position(gear)), "and the lever rests at gear %d" % gear)
		check_eq(_gate.grinds, 0, "a clean shift into gear %d does not grind" % gear)

	# Gear 5: right along the neutral channel, then forward.
	var fifth: Array = [Vector2(1.0, 0.0), Vector2(0.0, 1.0)]
	_gate.reset(GearGate.NEUTRAL)
	_gate.has_fifth = false
	_shift(fifth)
	check(_gate.gear != 5, "without Fifth gear the path for gear 5 does not engage it")
	check(_gate.lever.x <= 0.0, "the lever never enters the walled-off column")

	_gate.reset(GearGate.NEUTRAL)
	_gate.has_fifth = true
	_shift(fifth)
	check_eq(_gate.gear, 5, "with Fifth gear fitted the same path engages gear 5")
	check_eq(_gate.grinds, 0, "cleanly")
	_gate.has_fifth = false

	# Through the box in order, as a driver does: 1 > 2 > 3 > 4 and back to 3.
	_gate.reset(1)
	_shift([Vector2(0.0, -2.0)])
	check_eq(_gate.gear, 2, "1 to 2: straight back")
	_shift([Vector2(0.0, 1.0), Vector2(1.0, 0.0), Vector2(0.0, 1.0)])
	check_eq(_gate.gear, 3, "2 to 3: forward to neutral, across, forward")
	_shift([Vector2(0.0, -2.0)])
	check_eq(_gate.gear, 4, "3 to 4: straight back")
	_shift([Vector2(0.0, 2.0)])
	check_eq(_gate.gear, 3, "4 to 3: straight forward")
	check_eq(_gate.grinds, 0, "none of it grinds")

	# While the lever is between gears the car is in neutral.
	_gate.reset(3)
	_gate.press()
	_drag(Vector2(0.0, -1.0))
	check_eq(_gate.gear, GearGate.NEUTRAL, "with the lever held between gears, no gear is engaged")
	_gate.release()
	check_eq(_gate.gear, GearGate.NEUTRAL, "released at the neutral channel it stays in neutral")
	check(_gate.lever.is_equal_approx(Vector2.ZERO), "and the lever springs to the centre of the gate")

	# Engage radius: a release within gate_engage_radius of the gear engages it.
	var engage: float = tuning.f("gate_engage_radius")
	_gate.reset(GearGate.NEUTRAL)
	_shift([Vector2(0.0, 1.0 - engage + 0.05)])
	check_eq(_gate.gear, 3, "a release just inside gate_engage_radius engages")

	# A sloppy diagonal still finds the gate: the lever slides along the wall.
	_gate.reset(2)
	_gate.press()
	for _tick: int in 40:
		_gate.begin_tick()
		_gate.step(DT, Vector2(3.0, -2.5), 1.0)
	_gate.release()
	check_eq(_gate.gear, 3, "a diagonal stroke from 2 slides through the gate into 3")

	# One unit is gate_unit pixels of pointer travel.
	_gate.reset(GearGate.NEUTRAL)
	_gate.press()
	_gate.begin_tick()
	_gate.step(DT, Vector2(0.0, -_unit * 0.5), 1.0)
	check_near(_gate.lever.y, 0.5, 0.000001, "half of gate_unit of pointer travel moves the lever half a unit")
	_gate.reset(GearGate.NEUTRAL)
	_gate.press()
	_gate.begin_tick()
	_gate.step(DT, Vector2(0.0, -_unit * 0.5), 0.5)
	check_near(_gate.lever.y, 0.25, 0.000001, "at half lever speed the same travel moves it half as far")

	# The assist: sequential shifting, never through neutral.
	_gate.reset(1)
	check(_gate.shift_sequential(1) and _gate.gear == 2, "sequential up from 1 is 2")
	_gate.shift_sequential(1)
	_gate.shift_sequential(1)
	check_eq(_gate.gear, 4, "then 3 and 4")
	check(not _gate.shift_sequential(1) and _gate.gear == 4, "and no further without Fifth gear")
	_gate.shift_sequential(-1)
	check_eq(_gate.gear, 3, "sequential down from 4 is 3")
	check_eq(_gate.grinds, 0, "sequential shifting never grinds")


## T-GATE-02: a release mid-channel and a push into a wall each produce one grind.
func test_gate_02() -> void:
	var grind_min: float = tuning.f("gate_grind_min")
	var grind_max: float = tuning.f("gate_grind_max")
	var wall_push: float = tuning.f("gate_wall_push")
	var lock: float = tuning.f("gate_grind_lock")
	var mid: float = (grind_min + grind_max) * 0.5

	# Released mid-channel.
	_gate.reset(GearGate.NEUTRAL)
	_gate.press()
	_drag(Vector2(0.0, mid))
	check_eq(_gate.grinds, 0, "dragging along a channel does not grind by itself")
	_gate.begin_tick()
	_gate.release()
	check_eq(_gate.grinds, 1, "a release mid-channel produces one grind")
	check(_gate.ground, "and flags it for that tick")
	check_eq(_gate.gear, GearGate.NEUTRAL, "the gear does not engage")
	check(_gate.lever.is_equal_approx(Vector2.ZERO), "the lever springs back to neutral")
	check_near(_gate.lock_left, lock, 0.000001, "the lever locks for gate_grind_lock")

	# The same going backward, and from a gear.
	_gate.reset(3)
	_gate.press()
	_drag(Vector2(0.0, -(1.0 + mid)))
	_gate.release()
	check_eq(_gate.grinds, 1, "a release mid-channel on the way to another gear grinds once")
	check_eq(_gate.gear, GearGate.NEUTRAL, "and leaves the car in neutral")

	# The edges of the grind band.
	_gate.reset(GearGate.NEUTRAL)
	_gate.press()
	_drag(Vector2(0.0, grind_min - 0.05))
	_gate.release()
	check_eq(_gate.grinds, 0, "a release below gate_grind_min springs back without a grind")
	check_eq(_gate.gear, GearGate.NEUTRAL, "into neutral")
	_gate.reset(GearGate.NEUTRAL)
	_gate.press()
	_drag(Vector2(0.0, grind_max + 0.05))
	_gate.release()
	check_eq(_gate.grinds, 0, "a release beyond gate_grind_max is close enough to engage")
	check_eq(_gate.gear, 3, "and engages")

	# While locked, the lever does not move.
	_gate.reset(GearGate.NEUTRAL)
	_gate.press()
	_drag(Vector2(0.0, mid))
	_gate.release()
	_gate.press()
	_gate.begin_tick()
	_gate.step(DT, Vector2(0.0, -_unit), 1.0)
	check(_gate.lever.is_equal_approx(Vector2.ZERO), "a locked lever ignores the hand")
	for _tick: int in int(lock / DT) + 2:
		_gate.begin_tick()
		_gate.step(DT, Vector2.ZERO, 1.0)
	_gate.begin_tick()
	_gate.step(DT, Vector2(0.0, -_unit * 0.5), 1.0)
	check_near(_gate.lever.y, 0.5, 0.000001, "after gate_grind_lock it moves again")

	# Pushed into a wall: toward the walled-off fifth gear.
	_gate.reset(GearGate.NEUTRAL)
	_gate.press()
	_drag(Vector2(wall_push - 0.1, 0.0))
	check_eq(_gate.grinds, 0, "a push of less than gate_wall_push into a wall does not grind")
	_gate.reset(GearGate.NEUTRAL)
	_gate.press()
	_drag(Vector2(wall_push + 0.2, 0.0))
	check_eq(_gate.grinds, 1, "a push of more than gate_wall_push into a wall produces one grind")
	check(_gate.lever.is_equal_approx(Vector2.ZERO), "the lever did not pass the wall")

	# Pushed sideways into the wall of a channel, half-way along it.
	_gate.reset(GearGate.NEUTRAL)
	_gate.press()
	_drag(Vector2(0.0, 0.6))
	_drag(Vector2(-(wall_push + 0.2), 0.0))
	check_eq(_gate.grinds, 1, "a sideways push into a channel wall produces one grind")
	check_near(_gate.lever.y, 0.6, 0.000001, "and does not move the lever")

	# The stop at the end of a gear's own slot is not a wall.
	_gate.reset(GearGate.NEUTRAL)
	_gate.press()
	_drag(Vector2(0.0, 1.0 + wall_push * 2.0))
	check_eq(_gate.grinds, 0, "pushing the lever home past its gear does not grind")
	_gate.release()
	check_eq(_gate.gear, 3, "it just engages")

	# Sliding along a wall is not pushing into it.
	_gate.reset(2)
	_gate.press()
	for _tick: int in 9:
		_gate.begin_tick()
		_gate.step(DT, Vector2(2.0, -4.0), 1.0)
	check_eq(_gate.grinds, 0, "a lever that slides along a wall is not pushing into it")


# --- Helpers ------------------------------------------------------------------

## Press, drag each leg (gate units: x toward gear 5, y forward), release.
func _shift(legs: Array) -> void:
	_gate.begin_tick()
	_gate.press()
	for leg: Variant in legs:
		var move: Vector2 = leg
		_drag(move)
	_gate.begin_tick()
	_gate.release()


## Drags the held lever by `units`, a few pixels per tick as a hand would.
func _drag(units: Vector2) -> void:
	var pixels: Vector2 = Vector2(units.x, -units.y) * _unit
	var steps: int = maxi(1, ceili(pixels.length() / DRAG_PX_PER_TICK))
	for _step: int in steps:
		_gate.begin_tick()
		_gate.step(DT, pixels / float(steps), 1.0)
