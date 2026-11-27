extends TestSuite
## M1: gesture primitives (GDD 4.4), first on the recogniser alone, then
## through the whole pipeline: pointer, hand, anchor, ritual.

const DT: float = DriveSim.DT

var _gesture: Gesture
var _tap_max: float = 0.0
var _flick_px: float = 0.0
var _flick_max: float = 0.0


func before_each() -> void:
	_gesture = Gesture.new()
	_gesture.configure(tuning)
	_tap_max = tuning.f("tap_max_time")
	_flick_px = tuning.f("flick_min_distance")
	_flick_max = tuning.f("flick_max_time")


## T-GEST-01: each gesture primitive is recognised, and its failure case rejected.
func test_gest_01() -> void:
	_check_tap()
	_check_hold()
	_check_flick()
	_check_drag_to()
	_check_crank()
	_check_bead()
	_check_pipeline()
	_check_drag_to_pipeline()
	_check_limits_to_the_tick()
	_check_drag()


func _check_tap() -> void:
	_gesture.begin(Gesture.Kind.TAP)
	check_eq(_run(_tap_max - 0.05, true), Gesture.Phase.ACTIVE, "a TAP is still open while the button is down")
	check_eq(_run(DT, false), Gesture.Phase.DONE, "TAP: released within tap_max_time, it completes on release")

	_gesture.begin(Gesture.Kind.TAP)
	_run(_tap_max + 0.05, true)
	check_eq(_gesture.phase, Gesture.Phase.CANCELLED, "TAP: a press longer than tap_max_time is not a TAP")
	_run(DT, false)
	check(_gesture.phase != Gesture.Phase.DONE, "and releasing it late does not complete it")

	# A buffered tap: pressed and released before the hand arrived.
	_gesture.begin(Gesture.Kind.TAP)
	check_eq(_run(DT, false), Gesture.Phase.DONE, "TAP: a press already released when it is applied still counts")


func _check_hold() -> void:
	var hold: float = 0.6
	_gesture.begin(Gesture.Kind.HOLD, hold)
	_run(hold - 0.05, true)
	check_eq(_gesture.phase, Gesture.Phase.ACTIVE, "HOLD: not complete before its time")
	check_between(_gesture.progress, 0.85, 0.95, "HOLD: progress climbs toward 1")
	var ticks_to_done: int = _ticks_until_ended(true, Vector2.ZERO, 60)
	check_eq(_gesture.phase, Gesture.Phase.DONE, "HOLD(t): the button kept down for t completes it")
	check_near(_gesture.elapsed, hold, DT, "HOLD: it completes at t, not later")
	check(ticks_to_done > 0, "HOLD: it completes while the button is still down")

	_gesture.begin(Gesture.Kind.HOLD, hold)
	_run(hold - 0.1, true)
	_run(DT, false)
	check_eq(_gesture.phase, Gesture.Phase.CANCELLED, "HOLD: releasing early cancels")
	_run(hold, true)
	check_eq(_gesture.phase, Gesture.Phase.CANCELLED, "HOLD: and pressing again does not resume it")


func _check_flick() -> void:
	var dirs: Dictionary = {
		Gesture.DIR_UP: Vector2(0.0, -1.0),
		Gesture.DIR_DOWN: Vector2(0.0, 1.0),
		Gesture.DIR_LEFT: Vector2(-1.0, 0.0),
		Gesture.DIR_RIGHT: Vector2(1.0, 0.0),
	}
	var names: Dictionary = {Gesture.DIR_UP: "up", Gesture.DIR_DOWN: "down", Gesture.DIR_LEFT: "left", Gesture.DIR_RIGHT: "right"}
	var quick: int = maxi(2, int(_flick_max * 0.5 / DT))
	for dir: int in dirs:
		var along: Vector2 = dirs[dir]
		# Far enough, fast enough.
		_gesture.begin(Gesture.Kind.FLICK, 0.0, dir)
		_move(along * (_flick_px + 2.0), quick)
		check_eq(_gesture.phase, Gesture.Phase.DONE, "FLICK %s: flick_min_distance within flick_max_time completes it" % names[dir])
		check_eq(_gesture.direction, dir, "FLICK %s: it reports its direction" % names[dir])
		# Too short.
		_gesture.begin(Gesture.Kind.FLICK, 0.0, dir)
		_move(along * (_flick_px - 5.0), quick)
		_run(_flick_max, true)
		check_eq(_gesture.phase, Gesture.Phase.CANCELLED, "FLICK %s: less than flick_min_distance is not a flick" % names[dir])
		# Too slow.
		_gesture.begin(Gesture.Kind.FLICK, 0.0, dir)
		_move(along * (_flick_px + 2.0), int((_flick_max + 0.15) / DT))
		check_eq(_gesture.phase, Gesture.Phase.CANCELLED, "FLICK %s: the same distance after flick_max_time is not a flick" % names[dir])
		# The wrong way.
		_gesture.begin(Gesture.Kind.FLICK, 0.0, dir)
		_move(-along * (_flick_px + 2.0), quick)
		_run(_flick_max, true)
		check_eq(_gesture.phase, Gesture.Phase.CANCELLED, "FLICK %s: the opposite direction is not this flick" % names[dir])
		# Mostly sideways: far enough in the direction, but five times as far across it.
		var across: Vector2 = Vector2(-along.y, along.x)
		for side: float in [-1.0, 1.0]:
			_gesture.begin(Gesture.Kind.FLICK, 0.0, dir)
			_move(along * (_flick_px + 2.0) + across * side * (_flick_px + 2.0) * 5.0, quick)
			_run(_flick_max, true)
			check_eq(_gesture.phase, Gesture.Phase.CANCELLED, "FLICK %s: a swipe that goes mostly sideways is not this flick" % names[dir])
			# Leaning a little is still the flick.
			_gesture.begin(Gesture.Kind.FLICK, 0.0, dir)
			_move(along * (_flick_px + 2.0) + across * side * (_flick_px + 2.0) * 0.4, quick)
			check_eq(_gesture.phase, Gesture.Phase.DONE, "FLICK %s: a swipe that leans a little to one side still counts" % names[dir])
			check_eq(_gesture.direction, dir, "FLICK %s: and reports its direction" % names[dir])

	# A ritual that accepts two directions reports which one was made.
	_gesture.begin(Gesture.Kind.FLICK, 0.0, Gesture.DIR_UP | Gesture.DIR_DOWN)
	_move(Vector2(0.0, _flick_px + 2.0), quick)
	check_eq(_gesture.direction, Gesture.DIR_DOWN, "FLICK up or down: a downward flick reports down")
	_gesture.begin(Gesture.Kind.FLICK, 0.0, Gesture.DIR_UP | Gesture.DIR_DOWN)
	_move(Vector2(0.0, -(_flick_px + 2.0)), quick)
	check_eq(_gesture.direction, Gesture.DIR_UP, "FLICK up or down: an upward flick reports up")

	# With every direction allowed, a swipe reports the way it mostly went.
	var every: int = Gesture.DIR_UP | Gesture.DIR_DOWN | Gesture.DIR_LEFT | Gesture.DIR_RIGHT
	_gesture.begin(Gesture.Kind.FLICK, 0.0, every)
	_move(Vector2((_flick_px + 2.0) * 5.0, -(_flick_px + 2.0)), quick)
	check_eq(_gesture.direction, Gesture.DIR_RIGHT, "FLICK any way: a swipe to the right that rises a little reports right, not up")

	# Released before the distance is made.
	_gesture.begin(Gesture.Kind.FLICK, 0.0, Gesture.DIR_UP)
	_move(Vector2(0.0, -_flick_px * 0.5), 2)
	_run(DT, false)
	check_eq(_gesture.phase, Gesture.Phase.CANCELLED, "FLICK: releasing before the distance is made cancels")


func _check_drag_to() -> void:
	_gesture.begin(Gesture.Kind.DRAG_TO)
	_run(0.4, true)
	check_eq(_gesture.phase, Gesture.Phase.ACTIVE, "DRAG_TO: carrying, with no time limit")
	_gesture.over_destination = true
	_run(DT, false)
	check_eq(_gesture.phase, Gesture.Phase.DONE, "DRAG_TO: released on another anchor, it completes")

	_gesture.begin(Gesture.Kind.DRAG_TO)
	_run(0.4, true)
	_gesture.over_destination = false
	_run(DT, false)
	check_eq(_gesture.phase, Gesture.Phase.CANCELLED, "DRAG_TO: released anywhere else, it is cancelled")


func _check_crank() -> void:
	var turns: float = 3.0
	var radius: float = 30.0
	var per_tick: float = deg_to_rad(12.0)

	_gesture.begin(Gesture.Kind.CRANK, turns)
	var angle: float = _circle(radius, per_tick, turns - 0.25, 1.0, 0.0)
	check_eq(_gesture.phase, Gesture.Phase.ACTIVE, "CRANK(3): not complete a quarter turn short of three turns")
	check_between(_gesture.progress, 0.85, 0.95, "CRANK: progress follows the cumulative angle")
	_circle(radius, per_tick, 0.4, 1.0, angle)
	check_eq(_gesture.phase, Gesture.Phase.DONE, "CRANK(n): n full turns in one direction complete it")
	check_eq(_gesture.crank_sign, 1, "CRANK: it reports the direction (clockwise)")

	_gesture.begin(Gesture.Kind.CRANK, turns)
	_circle(radius, per_tick, turns + 0.15, -1.0, 0.0)
	check_eq(_gesture.phase, Gesture.Phase.DONE, "CRANK: the other way round works as well")
	check_eq(_gesture.crank_sign, -1, "CRANK: and reports counter-clockwise")

	# The size of the circle does not matter: it counts angle, not distance.
	_gesture.begin(Gesture.Kind.CRANK, turns)
	_circle(radius * 3.0, per_tick, turns + 0.15, 1.0, 0.0)
	check_eq(_gesture.phase, Gesture.Phase.DONE, "CRANK: a wider circle needs the same three turns")

	# Reversing unwinds: the angle is cumulative in one direction.
	_gesture.begin(Gesture.Kind.CRANK, turns)
	angle = _circle(radius, per_tick, 2.0, 1.0, 0.0)
	_circle(radius, per_tick, 2.0, -1.0, angle)
	check_eq(_gesture.phase, Gesture.Phase.ACTIVE, "CRANK: two turns one way and two back are not three turns")

	# Moving in a straight line is not cranking.
	_gesture.begin(Gesture.Kind.CRANK, turns)
	_move(Vector2(2000.0, 0.0), 200)
	check_eq(_gesture.phase, Gesture.Phase.ACTIVE, "CRANK: a long straight drag turns nothing")

	# Doubling back is not turning. Short of three turns and then back a
	# little, at several speeds: never complete.
	for degrees: float in [7.0, 11.0, 13.0, 17.0, 23.0]:
		for short: float in [2.55, 2.75, 2.9]:
			_gesture.begin(Gesture.Kind.CRANK, turns)
			angle = _circle(radius, deg_to_rad(degrees), short, 1.0, 0.0)
			_circle(radius, deg_to_rad(degrees), 0.08, -1.0, angle)
			check_eq(_gesture.phase, Gesture.Phase.ACTIVE, "CRANK: %s turns at %d degrees a tick and a slip back are not three turns" % [str(short), int(degrees)])
	# A slip back and on again costs what it unwound, no more and no less.
	_gesture.begin(Gesture.Kind.CRANK, turns)
	angle = _circle(radius, per_tick, 1.5, 1.0, 0.0)
	angle = _circle(radius, per_tick, 0.1, -1.0, angle)
	angle = _circle(radius, per_tick, 1.45, 1.0, angle)
	check_eq(_gesture.phase, Gesture.Phase.ACTIVE, "CRANK: after a slip back, 2.85 net turns are still not three")
	_circle(radius, per_tick, 0.3, 1.0, angle)
	check_eq(_gesture.phase, Gesture.Phase.DONE, "CRANK: and a little over three net turns complete it")
	# Scrubbing left and right, with a stray pixel sideways on each stroke.
	_gesture.begin(Gesture.Kind.CRANK, turns)
	for stroke: int in 60:
		var way: float = 1.0 if stroke % 2 == 0 else -1.0
		_move(Vector2(way * 80.0, 1.0 if stroke % 3 == 0 else -1.0), 8)
	check_eq(_gesture.phase, Gesture.Phase.ACTIVE, "CRANK: scrubbing left and right is not cranking")

	_gesture.begin(Gesture.Kind.CRANK, turns)
	_circle(radius, per_tick, 2.5, 1.0, 0.0)
	_run(DT, false)
	check_eq(_gesture.phase, Gesture.Phase.CANCELLED, "CRANK: releasing before the last turn cancels")


func _check_bead() -> void:
	var rate: float = tuning.f("bead_max_rate")
	# Ten taps in one second: only bead_max_rate of them count.
	var counted: int = 0
	for _tap: int in 10:
		counted += 1 if _one_bead_tap(0.1) else 0
	check_eq(counted, int(rate), "BEAD: of ten taps in one second, only bead_max_rate count")

	# Unhurried taps all count.
	_gesture = Gesture.new()
	_gesture.configure(tuning)
	counted = 0
	for _tap: int in 4:
		counted += 1 if _one_bead_tap(0.5) else 0
	check_eq(counted, 4, "BEAD: taps slower than the limit each count as one bead")

	# At or above the limit the beads come at the limit, not at half of it.
	for per_second: float in [4.0, 6.0, 10.0]:
		_gesture = Gesture.new()
		_gesture.configure(tuning)
		counted = 0
		var taps: int = roundi(per_second * 5.0)
		for _tap: int in taps:
			counted += 1 if _one_bead_tap(1.0 / per_second) else 0
		check_between(float(counted), rate * 5.0 - 1.0, rate * 5.0 + 1.0, "BEAD: %d taps in 5 s (%s a second) give bead_max_rate beads a second (%d)" % [taps, str(per_second), counted])
	# A hair faster than the limit loses a tap now and then, never half of them.
	_gesture = Gesture.new()
	_gesture.configure(tuning)
	counted = 0
	for _tap: int in 20:
		counted += 1 if _one_bead_tap(39.0 * DT) else 0
	check(counted >= 14 and counted <= 20, "BEAD: 20 taps at 3.08 a second give at least 14 beads (%d)" % counted)
	# Never more than bead_max_rate in any one second.
	_gesture = Gesture.new()
	_gesture.configure(tuning)
	var stamps: Array[float] = []
	var clock: float = 0.0
	for _tap: int in 40:
		if _one_bead_tap(0.125):
			stamps.append(clock)
		clock += 0.125
	var worst: int = 0
	for index: int in stamps.size():
		var within: int = 0
		for other: float in stamps:
			if other >= stamps[index] and other < stamps[index] + 1.0 - DT:
				within += 1
		worst = maxi(worst, within)
	check_eq(worst, int(rate), "BEAD: no second ever holds more than bead_max_rate beads")

	# A bead is a TAP: a long press is not one.
	_gesture.begin(Gesture.Kind.BEAD)
	_run(_tap_max + 0.1, true)
	_run(DT, false)
	check(_gesture.phase != Gesture.Phase.DONE, "BEAD: a long press is not a bead")


## The same gestures through DriveSim: pointer to the anchor, the hand
## travels, the press is applied on arrival, the ritual completes.
func _check_pipeline() -> void:
	var sim: DriveSim = DriveSim.new(fresh_data())
	var input: DriveInput = DriveInput.new()

	# TAP on the horn: click while the hand is still on its way (buffered).
	_aim(sim, input, &"horn")
	input.lmb = true
	_steps(sim, input, 4)
	input.lmb = false
	_steps(sim, input, 60)
	check(_completed(sim, "horn"), "pipeline: a click on the horn completes the horn ritual")

	# FLICK up on the wiper stalk.
	_aim(sim, input, &"wiper_stalk")
	_steps(sim, input, 40)
	input.pointer_is_absolute = false
	input.lmb = true
	input.pointer_delta = Vector2(0.0, -6.0)
	_steps(sim, input, 10)
	input.pointer_delta = Vector2.ZERO
	input.lmb = false
	_steps(sim, input, 5)
	check(_completed(sim, "wipers"), "pipeline: a flick up on the stalk completes the wipers ritual")
	check_eq(sim.hand.at_id(), &"wiper_stalk", "pipeline: the hand stays on the stalk during the flick")

	# FLICK down on the wiper stalk is the wrong way.
	input.lmb = true
	input.pointer_delta = Vector2(0.0, 6.0)
	_steps(sim, input, 10)
	input.pointer_delta = Vector2.ZERO
	input.lmb = false
	_steps(sim, input, 40)
	check(not _completed(sim, "wipers"), "pipeline: a flick down on the wiper stalk does nothing")

	# A long flick, and a second one without aiming again: the hand stays on
	# the stalk until the button comes up, so the rest of the swipe does not
	# drag the pointer off it.
	for length: float in [150.0, 220.0]:
		_aim(sim, input, &"wiper_stalk")
		_steps(sim, input, 40)
		input.pointer_is_absolute = false
		for flick: int in 2:
			sim.drain_events()
			input.lmb = true
			input.pointer_delta = Vector2(0.0, -length / 10.0)
			_steps(sim, input, 10)
			input.pointer_delta = Vector2.ZERO
			input.lmb = false
			_steps(sim, input, 30)
			check(_completed(sim, "wipers"), "pipeline: flick %d of %d px on the stalk works the wipers" % [flick + 1, int(length)])
			check_eq(sim.hand.at_id(), &"wiper_stalk", "pipeline: after a flick of %d px the hand is still on the stalk" % int(length))

	# CRANK(3) at the window, across the cabin.
	_aim(sim, input, &"window_crank")
	_steps(sim, input, 120)
	check_eq(sim.hand.at_id(), &"window_crank", "pipeline: the hand reaches the window crank")
	input.pointer_is_absolute = false
	input.lmb = true
	var heading: float = 0.0
	for _tick: int in 110:
		heading += deg_to_rad(12.0)
		input.pointer_delta = Vector2(cos(heading), sin(heading)) * 6.5
		sim.step(input)
	input.pointer_delta = Vector2.ZERO
	input.lmb = false
	_steps(sim, input, 5)
	check(_completed(sim, "window_crank"), "pipeline: three turns at the crank complete the window ritual")

	# GATE: the gear lever through the hand. The Telling starts in first.
	check_eq(sim.gate.gear, 1, "pipeline: the car starts in first gear")
	_aim(sim, input, &"gear_lever")
	_steps(sim, input, 160)
	check_eq(sim.hand.at_id(), &"gear_lever", "pipeline: the hand reaches the gear lever")
	input.pointer_is_absolute = false
	input.lmb = true
	input.pointer_delta = Vector2(0.0, 4.0)
	_steps(sim, input, 20)
	input.pointer_delta = Vector2.ZERO
	input.lmb = false
	_steps(sim, input, 3)
	check_eq(sim.gate.gear, 2, "pipeline: dragging the lever straight back from first engages second")
	check_eq(sim.hand.at_id(), &"gear_lever", "pipeline: the hand stays on the lever while it shifts")

	# The assist setting replaces the gate with flicks.
	sim.sequential_shift = true
	input.lmb = true
	input.pointer_delta = Vector2(0.0, -6.0)
	_steps(sim, input, 10)
	input.pointer_delta = Vector2.ZERO
	input.lmb = false
	_steps(sim, input, 5)
	check_eq(sim.gate.gear, 3, "pipeline: with sequential shifting a flick up goes from second to third")
	# Three long flicks in a row, without aiming again, are three shifts.
	sim.gate.has_fifth = true
	sim.gate.force_gear(1)
	var gears: Array[int] = []
	for _flick: int in 3:
		input.lmb = true
		input.pointer_delta = Vector2(0.0, -11.0)
		_steps(sim, input, 10)
		input.pointer_delta = Vector2.ZERO
		input.lmb = false
		_steps(sim, input, 20)
		gears.append(sim.gate.gear)
	check_eq(gears, [2, 3, 4] as Array[int], "pipeline: three long flicks up on the assisted lever go through three gears")
	input.lmb = true
	input.pointer_delta = Vector2(0.0, 11.0)
	_steps(sim, input, 10)
	input.pointer_delta = Vector2.ZERO
	input.lmb = false
	_steps(sim, input, 20)
	check_eq(sim.gate.gear, 3, "pipeline: and a flick down comes back one")
	sim.gate.has_fifth = false
	sim.sequential_shift = false

	# Grip and steer.
	input.clear()
	input.pointer_is_absolute = true
	input.pointer = sim.space.point_to_pointer(sim.space.grip_reference)
	input.lmb = true
	_steps(sim, input, 80)
	check(sim.hand.gripping and sim.wheel.gripped, "pipeline: holding the button on the rim grips the wheel")
	input.pointer_is_absolute = false
	input.pointer_delta = Vector2(10.0, 0.0)
	_steps(sim, input, 10)
	input.pointer_delta = Vector2.ZERO
	_steps(sim, input, 60)
	check_near(sim.wheel.angle, 100.0 * tuning.f("steer_deg_per_px"), 0.05, "pipeline: 100 px of motion while gripping turns the wheel")
	var snapshot: Dictionary = sim.snapshot()
	check_eq(snapshot["hand_gripping"], true, "pipeline: the snapshot shows the grip")
	check_eq(snapshot["pointer_visible"], false, "pipeline: the pointer is hidden while gripping")
	input.lmb = false
	_steps(sim, input, int(1.5 / DT))
	check(not sim.wheel.gripped, "pipeline: releasing the button lets go")
	check_near(sim.wheel.angle, 0.0, 0.000001, "pipeline: and the wheel returns to centre")


## DRAG_TO through DriveSim (GDD 4.4): press on the object, carry it to the
## anchor the ritual names, release. One thing fits in the hand: while it
## carries, it cannot take the wheel.
func _check_drag_to_pipeline() -> void:
	var roots: Dictionary = data.roots.duplicate(true)
	var rituals: Array = GameData.as_array(GameData.as_dict(roots["rituals"])["rituals"])
	rituals.append({
		"id": "hand_over_test", "anchor": "ashtray", "gesture": "DRAG_TO", "to": "cup_b",
		"eyes_down": false, "requires": ["!lit"], "on_complete": ["nerves:-1"],
	})
	var private: GameData = GameData.from_parts(roots, data.lines.duplicate(true))
	check(DataValidator.validate(private).is_empty(), "DRAG_TO: a ritual that names where the object goes is valid data")
	var sim: DriveSim = DriveSim.new(private)
	# The cigarettes sit in the ashtray: take them out so the test ritual is the one offered there.
	sim.items.remove_item(sim.items.item(&"cigarettes"))
	var input: DriveInput = DriveInput.new()
	var cases: Array = [[&"cup_b", true], [&"radio", false], [&"ashtray", false]]
	for entry: Variant in cases:
		var case: Array = entry
		var release_at: StringName = case[0]
		var expected: bool = case[1]
		sim.drain_events()
		_aim(sim, input, &"ashtray")
		_steps(sim, input, 60)
		input.lmb = true
		_steps(sim, input, 3)
		check_eq(sim.gesture.kind, Gesture.Kind.DRAG_TO, "DRAG_TO: pressing on the object picks it up")
		check(sim.hand.carrying, "DRAG_TO: the hand carries it")
		input.pointer = sim.hand.anchor_pointer(sim.hand.anchor_index(release_at))
		_steps(sim, input, 120)
		if release_at != &"ashtray":
			check(sim.hand.at_id() != &"ashtray", "DRAG_TO: the carried object moves with the hand")
		input.lmb = false
		_steps(sim, input, 5)
		check_eq(_completed(sim, "hand_over_test"), expected,
				"DRAG_TO: released at '%s' it %s" % [release_at, "completes" if expected else "does not complete"])
		check(not sim.hand.carrying, "DRAG_TO: after the release the hand is empty")
	# Released in the open.
	sim.drain_events()
	_aim(sim, input, &"ashtray")
	_steps(sim, input, 60)
	input.lmb = true
	_steps(sim, input, 3)
	input.pointer = sim.space.point_to_pointer(sim.space.grip_reference) + Vector2(0.0, 200.0)
	_steps(sim, input, 120)
	input.lmb = false
	_steps(sim, input, 5)
	check(not _completed(sim, "hand_over_test"), "DRAG_TO: released in the open it does not complete")
	# The carrying hand cannot take the wheel.
	_aim(sim, input, &"ashtray")
	_steps(sim, input, 60)
	input.lmb = true
	_steps(sim, input, 3)
	input.pointer = sim.space.point_to_pointer(sim.space.grip_reference)
	_steps(sim, input, 120)
	check(sim.hand.carrying, "DRAG_TO: with the pointer on the rim the hand still carries")
	check(not sim.hand.gripping and not sim.wheel.gripped, "DRAG_TO: a hand that carries something does not grip the wheel (GDD 4.2)")
	input.lmb = false
	_steps(sim, input, 5)
	input.lmb = true
	_steps(sim, input, 80)
	check(sim.hand.gripping and sim.wheel.gripped, "DRAG_TO: once it has let go, it can")
	input.lmb = false
	_steps(sim, input, 5)


# --- What the M1 review asked for (2026-11-17), put as checks ------------------

## The time limits to the tick, and the lean a FLICK allows, from both sides
## (M1 review: "loose brackets on timing limits", "FLICK time and direction
## limits", "CRANK angle-not-distance").
func _check_limits_to_the_tick() -> void:
	# TAP: the release must come within tap_max_time.
	var tap_ticks: int = roundi(_tap_max / DT)
	_gesture.begin(Gesture.Kind.TAP)
	for _tick: int in tap_ticks - 1:
		_gesture.step(DT, true, Vector2.ZERO)
	_gesture.step(DT, false, Vector2.ZERO)
	check_eq(_gesture.phase, Gesture.Phase.DONE, "TAP: released at tap_max_time exactly, it is a TAP")
	_gesture.begin(Gesture.Kind.TAP)
	for _tick: int in tap_ticks:
		_gesture.step(DT, true, Vector2.ZERO)
	check_eq(_gesture.phase, Gesture.Phase.ACTIVE, "TAP: down for tap_max_time, it is still open")
	_gesture.step(DT, false, Vector2.ZERO)
	check_eq(_gesture.phase, Gesture.Phase.CANCELLED, "TAP: released one tick after tap_max_time, it is not a TAP")

	# FLICK: the distance must be made within flick_max_time.
	var flick_ticks: int = roundi(_flick_max / DT)
	var dirs: Dictionary = {
		Gesture.DIR_UP: Vector2(0.0, -1.0),
		Gesture.DIR_DOWN: Vector2(0.0, 1.0),
		Gesture.DIR_LEFT: Vector2(-1.0, 0.0),
		Gesture.DIR_RIGHT: Vector2(1.0, 0.0),
	}
	for dir: int in dirs:
		var along: Vector2 = dirs[dir]
		# The last pixel on the last tick allowed, and on the tick after it.
		_gesture.begin(Gesture.Kind.FLICK, 0.0, dir)
		_move(along * (_flick_px - 2.0), flick_ticks - 1)
		check_eq(_gesture.phase, Gesture.Phase.ACTIVE, "FLICK %d: two pixels short, it is still open" % dir)
		_gesture.step(DT, true, along * 3.0)
		check_eq(_gesture.phase, Gesture.Phase.DONE, "FLICK %d: the distance made on the last tick of flick_max_time counts" % dir)
		_gesture.begin(Gesture.Kind.FLICK, 0.0, dir)
		_move(along * (_flick_px - 2.0), flick_ticks)
		_gesture.step(DT, true, along * 3.0)
		check_eq(_gesture.phase, Gesture.Phase.CANCELLED, "FLICK %d: made one tick later, it does not" % dir)
		# Well inside and well outside the limit (a fifth either way).
		_gesture.begin(Gesture.Kind.FLICK, 0.0, dir)
		_move(along * (_flick_px - 2.0), roundi(float(flick_ticks) * 0.85))
		_gesture.step(DT, true, along * 3.0)
		check_eq(_gesture.phase, Gesture.Phase.DONE, "FLICK %d: made at 85%% of flick_max_time, it counts" % dir)
		_gesture.begin(Gesture.Kind.FLICK, 0.0, dir)
		_move(along * (_flick_px - 2.0), roundi(float(flick_ticks) * 1.1))
		_gesture.step(DT, true, along * 3.0)
		check_eq(_gesture.phase, Gesture.Phase.CANCELLED, "FLICK %d: made at 110%% of it, it does not" % dir)
		# The lean: more its own way than across it, by a little.
		var across: Vector2 = Vector2(-along.y, along.x)
		for side: float in [-1.0, 1.0]:
			_gesture.begin(Gesture.Kind.FLICK, 0.0, dir)
			_move(along * (_flick_px + 2.0) + across * side * (_flick_px + 2.0) * 0.8, 10)
			check_eq(_gesture.phase, Gesture.Phase.DONE, "FLICK %d: a swipe that goes 0.8 as far across as along is this flick" % dir)
			check_eq(_gesture.direction, dir, "FLICK %d: and reports its direction" % dir)
			_gesture.begin(Gesture.Kind.FLICK, 0.0, dir)
			_move(along * (_flick_px + 2.0) + across * side * (_flick_px + 2.0) * 1.25, 10)
			_run(_flick_max, true)
			check_eq(_gesture.phase, Gesture.Phase.CANCELLED, "FLICK %d: one that goes 1.25 as far across as along is not" % dir)

	# CRANK counts angle, not distance: a circle three times as wide and one
	# a third as wide need the same three turns, no fewer and no more.
	for radius: float in [10.0, 30.0, 90.0]:
		_gesture.begin(Gesture.Kind.CRANK, 3.0)
		var angle: float = _circle(radius, deg_to_rad(12.0), 2.8, 1.0, 0.0)
		check_eq(_gesture.phase, Gesture.Phase.ACTIVE, "CRANK: 2.8 turns of a circle of radius %s are not three" % str(radius))
		_circle(radius, deg_to_rad(12.0), 0.3, 1.0, angle)
		check_eq(_gesture.phase, Gesture.Phase.DONE, "CRANK: 3.1 turns of it are")
	# A slow hand that rests a tick between every two moves turns the crank
	# as far as one that does not (a tick with no motion is no heading).
	_gesture.begin(Gesture.Kind.CRANK, 3.0)
	var slow: float = 0.0
	var steps: int = roundi(3.1 * TAU / deg_to_rad(12.0))
	var short_of: int = roundi(2.8 * TAU / deg_to_rad(12.0))
	for step: int in steps:
		var before: Vector2 = Vector2(cos(slow), sin(slow)) * 30.0
		slow += deg_to_rad(12.0)
		_gesture.step(DT, true, Vector2(cos(slow), sin(slow)) * 30.0 - before)
		_gesture.step(DT, true, Vector2.ZERO)
		if step == short_of:
			check_eq(_gesture.phase, Gesture.Phase.ACTIVE, "CRANK with rests: not complete at 2.8 turns")
	check_eq(_gesture.phase, Gesture.Phase.DONE, "CRANK with rests: complete at 3.1 turns")


## DRAG (a dial, D-021): one step per `amount` pixels of sideways travel,
## either way, while the button is down; it ends on release.
func _check_drag() -> void:
	var amount: float = 30.0
	_gesture.begin(Gesture.Kind.DRAG, amount)
	_move(Vector2(amount * 3.0 + 5.0, 0.0), 12)
	check_eq(_gesture.phase, Gesture.Phase.ACTIVE, "DRAG: it goes on while the button is down")
	check_eq(_gesture.take_drag_steps(), 3, "DRAG: 95 px to the right at 30 px a step are three steps")
	check_eq(_gesture.take_drag_steps(), 0, "DRAG: taken once, the steps are not there again")
	_move(Vector2(-(amount * 2.0 + 10.0), 0.0), 12)
	check_eq(_gesture.take_drag_steps(), -2, "DRAG: 70 px back are two steps the other way (the 5 px left over from before count against them)")
	_move(Vector2(-(amount - 6.0), 0.0), 6)
	check_eq(_gesture.take_drag_steps(), 0, "DRAG: a pixel short of a step is no step")
	_move(Vector2(-2.0, 0.0), 1)
	check_eq(_gesture.take_drag_steps(), -1, "DRAG: the next two pixels make it")
	_move(Vector2(0.0, amount * 4.0), 8)
	check_eq(_gesture.take_drag_steps(), 0, "DRAG: up and down turns nothing")
	_run(1.0, true)
	check_eq(_gesture.phase, Gesture.Phase.ACTIVE, "DRAG: there is no time limit")
	_run(DT, false)
	check_eq(_gesture.phase, Gesture.Phase.DONE, "DRAG: it ends when the button comes up")


# --- Helpers ------------------------------------------------------------------

## Runs the recogniser for `seconds` with the button up or down.
func _run(seconds: float, down: bool) -> Gesture.Phase:
	for _tick: int in maxi(1, roundi(seconds / DT)):
		_gesture.step(DT, down, Vector2.ZERO)
	return _gesture.phase


## Moves the pointer by `total` over `ticks` ticks with the button down.
func _move(total: Vector2, ticks: int) -> void:
	for _tick: int in ticks:
		_gesture.step(DT, true, total / float(ticks))


func _ticks_until_ended(down: bool, delta: Vector2, limit: int) -> int:
	for tick: int in limit:
		if _gesture.phase != Gesture.Phase.ACTIVE:
			return tick
		_gesture.step(DT, down, delta)
	return limit


## Circles the pointer for `turns` turns, `direction` +1 clockwise on screen.
## Returns the angle reached, so the next circle can carry on from it.
func _circle(radius: float, per_tick: float, turns: float, direction: float, from: float) -> float:
	var angle: float = from
	var ticks: int = roundi(turns * TAU / per_tick)
	for _tick: int in ticks:
		var before: Vector2 = Vector2(cos(angle), sin(angle)) * radius
		angle += per_tick * direction
		var after: Vector2 = Vector2(cos(angle), sin(angle)) * radius
		_gesture.step(DT, true, after - before)
	return angle


## One tap lasting 0.05 s, then idle until `period` has passed. True if it counted.
func _one_bead_tap(period: float) -> bool:
	_gesture.begin(Gesture.Kind.BEAD)
	var ticks: int = roundi(period / DT)
	var down_ticks: int = roundi(0.05 / DT)
	var counted: bool = false
	for tick: int in ticks:
		_gesture.step(DT, tick < down_ticks, Vector2.ZERO)
		if _gesture.phase == Gesture.Phase.DONE:
			counted = true
			_gesture.reset()
		elif _gesture.phase == Gesture.Phase.CANCELLED:
			_gesture.reset()
	return counted


func _aim(sim: DriveSim, input: DriveInput, anchor: StringName) -> void:
	input.clear()
	input.pointer_is_absolute = true
	input.pointer = sim.hand.anchor_pointer(sim.hand.anchor_index(anchor))


func _steps(sim: DriveSim, input: DriveInput, count: int) -> void:
	for _tick: int in count:
		sim.step(input)


## True if a ritual_completed event for this ritual is waiting; drains the queue.
func _completed(sim: DriveSim, ritual: String) -> bool:
	var found: bool = false
	for event: Dictionary in sim.drain_events():
		if event.get("type") == "ritual_completed" and event.get("ritual") == ritual:
			found = true
	return found
