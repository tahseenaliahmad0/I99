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
	_gate.begin_tick()
	_gate.press()
	_drag(Vector2(1.0, 0.0))
	check(_gate.lever.x <= tuning.f("gate_channel_half_width") + 0.000001, "without Fifth gear the lever stops at the wall of the third column's channel")
	_drag(Vector2(0.0, 1.0))
	_gate.release()
	check(_gate.gear != 5, "without Fifth gear the path for gear 5 does not engage it")
	check(_gate.lever.x <= tuning.f("gate_channel_half_width") + 0.000001, "the lever never enters the walled-off column")

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

	# Straight strokes from 2nd at many slopes (from the horizontal): any that
	# leans across goes to 3rd, with or without Fifth gear; one that is nearly
	# straight forward goes to 1st.
	for fifth_fitted: bool in [false, true]:
		for slope: float in [30.0, 40.0, 50.0, 60.0]:
			check_eq(_diagonal_from(2, slope, fifth_fitted), 3, "from 2nd, a stroke %s degrees from the horizontal ends in 3rd (Fifth gear fitted: %s)" % [str(slope), str(fifth_fitted)])
		check_eq(_diagonal_from(2, 85.0, fifth_fitted), 1, "from 2nd, a stroke almost straight forward ends in 1st (Fifth gear fitted: %s)" % str(fifth_fitted))
	# A stroke that hugs the neutral channel crosses the 3/4 column before it
	# has risen out of the channel. With the fifth slot walled off it stops at
	# the wall and slides up into 3rd; with Fifth gear fitted the way is open
	# and it runs on into 5th ("nothing but temptation", GDD 7.6).
	check_eq(_diagonal_from(2, 20.0, false), 3, "from 2nd, a flat stroke stops at the wall and ends in 3rd without Fifth gear")
	check_eq(_diagonal_from(2, 20.0, true), 5, "with Fifth gear fitted the same flat stroke runs on into 5th")
	check_eq(_diagonal_from(4, 150.0, false), 1, "from 4th, a stroke up and to the left ends in 1st")

	# A slow, slightly crooked drag does not lose its way: whole-pixel motion
	# ten degrees off the axis, at 1 px and at half a px a tick.
	for px_per_tick: float in [1.0, 0.5]:
		var needed: float = _crooked_pull(3, 4, 10.0, px_per_tick)
		check(needed <= _unit * 2.0 * 1.25, "3rd to 4th pulled back %s px a tick, ten degrees crooked: arrives within 1.25 times the ideal travel (needed %s px)" % [str(px_per_tick), str(needed)])

	# The channel is gate_channel_half_width to each side: inside it the lever
	# can turn into a column, outside it cannot.
	var half_width: float = tuning.f("gate_channel_half_width")
	_gate.reset(GearGate.NEUTRAL)
	_gate.press()
	_drag(Vector2(-(1.0 - half_width + 0.05), 0.0))
	_drag(Vector2(0.0, 0.6))
	check_near(_gate.lever.y, 0.6, 0.000001, "within gate_channel_half_width of a column the lever can turn into it")
	_gate.reset(GearGate.NEUTRAL)
	_gate.press()
	_drag(Vector2(-(1.0 - half_width - 0.05), 0.0))
	_drag(Vector2(0.0, 0.6))
	check_near(_gate.lever.y, half_width, 0.000001, "further out than that it cannot: it stays in the neutral channel")

	# While held, the gear stays in until the lever leaves gate_engage_radius.
	_gate.reset(3)
	_gate.press()
	_drag(Vector2(0.0, -(engage - 0.05)))
	check_eq(_gate.gear, 3, "pulled less than gate_engage_radius from its slot, the gear is still in")
	_drag(Vector2(0.0, -0.1))
	check_eq(_gate.gear, GearGate.NEUTRAL, "pulled further, it is out")

	# A release just short of gate_engage_radius does not engage.
	_gate.reset(GearGate.NEUTRAL)
	_shift([Vector2(0.0, 1.0 - engage - 0.05)])
	check_eq(_gate.gear, GearGate.NEUTRAL, "a release just outside gate_engage_radius does not engage")

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
	_gate.reset(4)
	_gate.has_fifth = true
	check(_gate.shift_sequential(1) and _gate.gear == 5, "with Fifth gear, sequential up from 4 is 5")
	check(not _gate.shift_sequential(1), "and no further")
	_gate.has_fifth = false
	_gate.reset(GearGate.NEUTRAL)
	check(_gate.shift_sequential(-1) and _gate.gear == 1, "from neutral a flick finds first")


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

	# Pushed into a wall: toward the walled-off fifth gear. The lever first
	# crosses its own channel (half a channel width), then meets the wall.
	var half_width: float = tuning.f("gate_channel_half_width")
	_gate.reset(GearGate.NEUTRAL)
	_gate.press()
	_drag(Vector2(half_width + wall_push - 0.1, 0.0))
	check_eq(_gate.grinds, 0, "a push of less than gate_wall_push into a wall does not grind")
	_gate.reset(GearGate.NEUTRAL)
	_gate.press()
	_drag(Vector2(half_width + wall_push, 0.0))
	check_eq(_gate.grinds, 0, "a push of exactly gate_wall_push does not grind either")
	_gate.reset(GearGate.NEUTRAL)
	_gate.press()
	_drag(Vector2(half_width + wall_push + 0.2, 0.0))
	check_eq(_gate.grinds, 1, "a push of more than gate_wall_push into a wall produces one grind")
	check_near(_gate.lever.x, half_width, 0.000001, "the lever did not pass the wall")
	check_near(_gate.lock_left, lock, DT * 1.5, "a wall grind locks the lever for gate_grind_lock too")

	# Pushed sideways into the wall of a channel, half-way along it.
	_gate.reset(GearGate.NEUTRAL)
	_gate.press()
	_drag(Vector2(0.0, 0.6))
	_drag(Vector2(-(half_width + wall_push + 0.2), 0.0))
	check_eq(_gate.grinds, 1, "a sideways push into a channel wall produces one grind")
	check_near(_gate.lever.y, 0.6, 0.000001, "and does not move the lever along the channel")
	check_near(_gate.lever.x, -half_width, 0.000001, "nor through the wall")

	# The same at the other end of the neutral channel, and between two columns.
	_gate.reset(GearGate.NEUTRAL)
	_gate.press()
	_drag(Vector2(-1.0, 0.0))
	_drag(Vector2(-(half_width + wall_push + 0.2), 0.0))
	check_eq(_gate.grinds, 1, "pushing left past the first column grinds once")
	_gate.reset(GearGate.NEUTRAL)
	_gate.press()
	_drag(Vector2(-0.5, 0.0))
	_drag(Vector2(0.0, half_width + wall_push + 0.2))
	check_eq(_gate.grinds, 1, "pushing forward between two columns grinds once")
	check_near(_gate.lever.y, half_width, 0.000001, "the lever stays in the neutral channel")

	# A push a few degrees off the axis is still a push into the wall.
	_gate.reset(GearGate.NEUTRAL)
	_gate.press()
	_drag(Vector2(-0.5, 0.0))
	_drag(Vector2(0.17, 2.0))
	check_eq(_gate.grinds, 1, "a two-unit push five degrees off the axis grinds once")

	# The lock runs out whether or not the lever is held.
	_gate.reset(GearGate.NEUTRAL)
	_gate.press()
	_drag(Vector2(half_width + wall_push + 0.2, 0.0))
	_gate.release()
	for _tick: int in int(lock / DT) + 2:
		_gate.begin_tick()
		_gate.step(DT, Vector2.ZERO, 1.0)
	check_eq(_gate.lock_left, 0.0, "the lock runs out with the lever let go")

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

	# A lever home in its gear does not grind because the hand trembles.
	_gate.reset(3)
	_gate.press()
	for tick: int in int(2.0 / DT):
		_gate.begin_tick()
		var wobble: Vector2 = Vector2(2.0 if tick % 4 < 2 else -2.0, -1.0 if tick % 6 < 3 else 1.0)
		_gate.step(DT, wobble, 1.0)
	check_eq(_gate.grinds, 0, "a trembling hand on a lever that is home does not grind")
	check_eq(_gate.gear, 3, "and does not knock it out of gear")

	# Every column, both ways: the grind band and its edges.
	var columns: Array[Vector2] = [Vector2(-1.0, 1.0), Vector2(-1.0, -1.0), Vector2(0.0, 1.0), Vector2(0.0, -1.0), Vector2(1.0, 1.0)]
	var engage_radius: float = tuning.f("gate_engage_radius")
	for column: Vector2 in columns:
		var wants_fifth: bool = column.x > 0.5
		var name: String = "column %d %s" % [int(column.x), "forward" if column.y > 0.0 else "back"]
		for along: float in [grind_min + 0.05, mid, grind_max - 0.05, 1.0 - engage_radius - 0.05]:
			_gate.reset(GearGate.NEUTRAL)
			_gate.has_fifth = wants_fifth
			_gate.press()
			_drag(Vector2(column.x, 0.0))
			_drag(Vector2(0.0, column.y * along))
			_gate.release()
			check_eq(_gate.grinds, 1, "%s: a release %s along grinds once" % [name, str(along)])
			check_eq(_gate.gear, GearGate.NEUTRAL, "%s: and engages nothing" % name)
		for along: float in [grind_min - 0.03, 1.0 - engage_radius + 0.05, 1.0]:
			_gate.reset(GearGate.NEUTRAL)
			_gate.has_fifth = wants_fifth
			_gate.press()
			_drag(Vector2(column.x, 0.0))
			_drag(Vector2(0.0, column.y * along))
			_gate.release()
			check_eq(_gate.grinds, 0, "%s: a release %s along does not grind" % [name, str(along)])
	_gate.has_fifth = false

	# The grind is heard and felt: through the whole simulation it is a sound
	# and gate_grind_nerves.
	var sim: DriveSim = DriveSim.new(fresh_data())
	sim.in_encounter = true
	var input: DriveInput = DriveInput.new()
	input.pointer_is_absolute = true
	input.pointer = sim.hand.anchor_pointer(sim.hand.anchor_index(&"gear_lever"))
	for _tick: int in 80:
		sim.car.x = sim.car.lane_center(1)
		sim.step(input)
	input.pointer_is_absolute = false
	input.lmb = true
	input.pointer_delta = Vector2(0.0, 4.0)
	for _tick: int in 14:
		sim.step(input)
	input.pointer_delta = Vector2.ZERO
	sim.drain_events()
	var nerves_before: float = sim.nerves.value
	input.lmb = false
	sim.step(input)
	sim.step(input)
	check_eq(sim.gate.grinds, 1, "through the hand: letting the lever go half-way between first and second grinds")
	check_near(sim.nerves.value - nerves_before, tuning.f("gate_grind_nerves"), 0.000001, "a grind adds gate_grind_nerves")
	var heard: bool = false
	for event: Dictionary in sim.drain_events():
		if event.get("type") == "sfx_requested" and event.get("id") == "grind":
			heard = true
	check(heard, "and makes its noise")


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


## A straight stroke from a gear, `slope` degrees from the horizontal
## (0 is toward gear 5, 90 is forward), held until the lever comes to rest,
## then released. Returns the gear engaged.
func _diagonal_from(from_gear: int, slope: float, fifth_fitted: bool) -> int:
	_gate.reset(from_gear)
	_gate.has_fifth = fifth_fitted
	_gate.begin_tick()
	_gate.press()
	var direction: Vector2 = Vector2(cos(deg_to_rad(slope)), -sin(deg_to_rad(slope)))
	var still: int = 0
	for _tick: int in 400:
		var before: Vector2 = _gate.lever
		_gate.begin_tick()
		_gate.step(DT, direction * DRAG_PX_PER_TICK, 1.0)
		still = still + 1 if _gate.lever.is_equal_approx(before) else 0
		if still >= 3 or _gate.grinds > 0:
			break
	_gate.begin_tick()
	_gate.release()
	var out: int = _gate.gear
	_gate.has_fifth = false
	return out


## Pulls the lever from one gear straight toward another in the same column,
## along a line `crooked` degrees off the axis, in whole pixels, `px_per_tick`
## at a time. Returns the pointer travel it took to arrive (INF if it never did).
func _crooked_pull(from_gear: int, to_gear: int, crooked: float, px_per_tick: float) -> float:
	_gate.reset(from_gear)
	_gate.begin_tick()
	_gate.press()
	var home: Vector2 = GearGate.gear_position(to_gear)
	var along: float = signf(home.y - GearGate.gear_position(from_gear).y)
	# Pointer motion: y down the screen is backward in the gate.
	var direction: Vector2 = Vector2(sin(deg_to_rad(crooked)), -along * cos(deg_to_rad(crooked)))
	var travelled: Vector2 = Vector2.ZERO
	var sent: Vector2 = Vector2.ZERO
	for _tick: int in int(10.0 / DT):
		travelled += direction * px_per_tick
		var whole: Vector2 = Vector2(roundf(travelled.x), roundf(travelled.y)) - sent
		sent += whole
		_gate.begin_tick()
		_gate.step(DT, whole, 1.0)
		if absf(_gate.lever.y - home.y) < 0.000001:
			return travelled.length()
	return INF


## Drags the held lever by `units`, a few pixels per tick as a hand would.
func _drag(units: Vector2) -> void:
	var pixels: Vector2 = Vector2(units.x, -units.y) * _unit
	var steps: int = maxi(1, ceili(pixels.length() / DRAG_PX_PER_TICK))
	for _step: int in steps:
		_gate.begin_tick()
		_gate.step(DT, pixels / float(steps), 1.0)
