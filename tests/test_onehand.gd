extends CabinSuite
## M10: one hand, two buttons (GDD 17.2). T-ONEHAND-01. How the claim is
## held, and the pointer's way to the pause, is D-066.

## The gestures of GDD 4.6, each made with the left button and the pointer's
## motion and with nothing else; GATE is the gear lever's.
const GESTURES: PackedStringArray = ["TAP", "HOLD", "FLICK", "DRAG", "DRAG_TO", "CRANK", "BEAD", "GATE"]
## What the game is played with (GDD 13.1), and the two that are extras of
## the Thumb keypad: each repeats a ritual of the pointer's.
const PADS: Dictionary = {"pad_horn": "horn", "pad_wiper": "wipers"}


# --- Helpers -------------------------------------------------------------------

## The mouse buttons bound to an input action of the project.
func _mouse_buttons(action: String) -> PackedInt32Array:
	var out: PackedInt32Array = []
	for event: InputEvent in InputMap.action_get_events(action):
		var button: InputEventMouseButton = event as InputEventMouseButton
		if button != null:
			out.append(button.button_index)
	return out


## Nothing but the pointer and the two buttons is in the input.
func _only_two_buttons() -> bool:
	return not _input.pad_horn and not _input.pad_wiper


## A Telling under way on a quiet leg.
func _on_the_road() -> void:
	_new_sim()
	_sim.heckling = false
	_sim.begin_telling(TABLE, 3)
	_into_next_quiet_leg()
	_events = []


# --- T-ONEHAND-01 ----------------------------------------------------------------

## T-ONEHAND-01: Every menu and every in-game action is reachable with
## pointer motion and two buttons.
func test_onehand_01() -> void:
	_check_the_two_buttons()
	_check_every_ritual()
	_check_each_gesture_with_one_button()
	_check_the_brake_and_the_pads()
	_check_the_pause()
	_check_the_menus()


## The two buttons: the left one grips and does, the right one brakes.
func _check_the_two_buttons() -> void:
	check_eq(_mouse_buttons("grip"), PackedInt32Array([MOUSE_BUTTON_LEFT]), "the grip is the left mouse button")
	check(_mouse_buttons("brake").has(MOUSE_BUTTON_RIGHT), "the brake is the right mouse button")
	# Every action the game has: on one of the two buttons, or an extra that
	# repeats something the pointer does, or a builder's key.
	for action: StringName in InputMap.get_actions():
		var name: String = String(action)
		if name.begins_with("ui_") or name.begins_with("debug_"):
			# The engine's own, which nothing of the game listens to; and the
			# debug keys of GDD 13.9.
			continue
		if name == "grip" or name == "brake":
			continue
		if PADS.has(name):
			check(data.has_record("rituals", GameData.as_string(PADS[name])), "%s only repeats a ritual the pointer has: %s" % [name, GameData.as_string(PADS[name])])
		elif name == "pause":
			check(tuning.f("pause_hold_s") > 0.0, "pause (Esc) only repeats what the pointer can do: the left button held on nothing")
		else:
			fail("the input action '%s' has no way by pointer and two buttons" % name)
	var input: DriveInput = DriveInput.new()
	var fields: PackedStringArray = []
	for property: Dictionary in input.get_property_list():
		if GameData.as_int(property.get("usage")) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			fields.append(GameData.as_string(property.get("name")))
	fields.sort()
	check_eq(fields, PackedStringArray(["lmb", "pad_horn", "pad_wiper", "pointer", "pointer_delta", "pointer_is_absolute", "rmb"]),
			"the simulation is given the pointer, its motion, two buttons and the two pads, and nothing else (GDD 13.3)")


## Every ritual of the cabin: a gesture of the left button, at an anchor the
## pointer can be put on.
func _check_every_ritual() -> void:
	_new_sim()
	var kinds: Dictionary = {}
	for ritual: Dictionary in data.records("rituals"):
		var id: String = GameData.as_string(ritual.get("id"))
		var gesture: String = GameData.as_string(ritual.get("gesture"))
		kinds[gesture] = true
		check(GESTURES.has(gesture), "%s: its gesture (%s) is one of the left button's" % [id, gesture])
		var anchor: String = GameData.as_string(ritual.get("anchor"))
		if anchor == ItemSim.SLOT_ANCHOR:
			# Wherever its item stands: a slot's anchor (checked below).
			continue
		var index: int = _sim.hand.anchor_index(StringName(anchor))
		if not check(index != HandSim.NO_ANCHOR, "%s: its anchor (%s) is in the cabin" % [id, anchor]):
			continue
		var pointer: Vector2 = _sim.hand.anchor_pointer(index)
		check(_sim.space.clamp_pointer(pointer).is_equal_approx(pointer), "%s: the pointer can be put on %s" % [id, anchor])
	check_eq(kinds.size(), GESTURES.size(), "(all eight gestures are in use)")
	for slot: Dictionary in data.records("slots"):
		var anchor: String = GameData.as_string(slot.get("anchor"))
		if anchor.is_empty():
			continue
		var index: int = _sim.hand.anchor_index(StringName(anchor))
		var pointer: Vector2 = _sim.hand.anchor_pointer(index)
		check(index != HandSim.NO_ANCHOR and _sim.space.clamp_pointer(pointer).is_equal_approx(pointer), "the slot %s: the pointer can be put on its anchor" % GameData.as_string(slot.get("id")))


## One ritual of each gesture, done on the road with the pointer and the
## left button and with nothing else in the input.
func _check_each_gesture_with_one_button() -> void:
	# TAP: the horn.
	_on_the_road()
	_tap_at("horn")
	check(_only_two_buttons() and _count_events("ritual_completed", "ritual", "horn") == 1, "TAP: the horn, with the left button")
	# HOLD: a sip of the tea.
	_on_the_road()
	_hold_at(_anchor_of("tea_glass"), GameData.as_float(_ritual("tea_sip").get("hold_s")) + 0.1)
	check(_only_two_buttons() and _count_events("ritual_completed", "ritual", "tea_sip") == 1, "HOLD: a sip of the tea")
	# FLICK: the wipers.
	_on_the_road()
	_wipe()
	check(_only_two_buttons() and _count_events("ritual_completed", "ritual", "wipers") == 1, "FLICK: the wipers")
	# DRAG: the radio's dial.
	_on_the_road()
	var station: StringName = _sim.items.radio
	_reach("radio")
	_input.pointer_is_absolute = false
	_input.lmb = true
	_input.pointer_delta = Vector2(tuning.f("radio_step_px") * 0.25, 0.0)
	_ticks(8)
	_input.pointer_delta = Vector2.ZERO
	_input.lmb = false
	_ticks(SETTLE)
	check(_only_two_buttons() and _sim.items.radio != station, "DRAG: the radio is tuned to another station")
	# DRAG_TO: the tea glass into the glovebox... the nearest of that kind:
	# his licence, to the officer's window (when he is pulled over).
	_on_the_road()
	_sim.suspicion.begin_watch()
	_sim.suspicion.add(tuning.f("suspicion_max"))
	var guard: int = _ticks_in(20.0)
	while not _sim.pulled_over and guard > 0:
		guard -= 1
		_tick()
	if check(_sim.pulled_over, "(pulled over)"):
		_ticks(_ticks_in(3.0))
		_events = []
		_drag("dash_1", "driver_window")
		check(_only_two_buttons() and _count_events("ritual_completed", "ritual", "hand_licence") == 1, "DRAG_TO: his licence carried to the window")
	# CRANK: the window.
	_on_the_road()
	_reach("window_crank")
	_crank(GameData.as_float(_ritual("window_crank").get("turns"), 1.0))
	check(_only_two_buttons() and _count_events("ritual_completed", "ritual", "window_crank") == 1, "CRANK: the window is wound")
	# BEAD: the prayer beads, a bead for a tap.
	_on_the_road()
	_give("beads")
	_events = []
	_reach(_anchor_of("beads"))
	_tap()
	check(_only_two_buttons() and _count_events("ritual_completed", "ritual", "beads_count") == 1, "BEAD: a bead is counted")
	# GATE: the lever, drawn straight back from first into second.
	_on_the_road()
	_sim.gate.reset(1)
	_reach("gear_lever")
	_input.pointer_is_absolute = false
	_input.lmb = true
	_input.pointer_delta = Vector2(0.0, 4.0)
	_ticks(20)
	_input.pointer_delta = Vector2.ZERO
	_input.lmb = false
	_ticks(SETTLE)
	check(_only_two_buttons() and _sim.gate.gear == 2, "GATE: the lever drawn from first into second")


func _check_the_brake_and_the_pads() -> void:
	_on_the_road()
	var speed: float = _sim.car.speed
	_input.clear()
	_input.rmb = true
	_ticks(_ticks_in(1.0))
	check(_sim.car.speed < speed - 5.0, "the right button is the brake: %d km/h after a second of it, from %d" % [roundi(_sim.car.speed), roundi(speed)])
	_input.clear()
	# The pads do nothing the pointer cannot: without the Thumb keypad they
	# do nothing at all.
	_on_the_road()
	_input.pad_horn = true
	_ticks(4)
	_input.clear()
	_ticks(SETTLE)
	check_eq(_count_events("ritual_completed"), 0, "the pad buttons are the Thumb keypad's: without it they are dead")


## The pause (GDD 13.1 gives it Esc): the pointer's way is the left button
## held where the hand has nothing to hold (D-066).
func _check_the_pause() -> void:
	var held: float = tuning.f("pause_hold_s")
	check(held > 2.0 * tuning.f("tap_max_time"), "the hold that pauses is no TAP (%.2f s)" % held)
	# The hold by itself.
	var hold: PauseHold = PauseHold.new(held)
	check_eq(_hold_for(hold, held - 0.1, true, true), 0, "held for less than that, nothing pauses")
	check(hold.progress > 0.5 and hold.progress < 1.0, "(its arc is on the way round: %.2f)" % hold.progress)
	check_eq(_hold_for(hold, 0.2, true, true), 1, "held for pause_hold_s, the game pauses")
	check_eq(_hold_for(hold, 3.0 * held, true, true), 0, "once for a press, however long it is held")
	check_near(hold.progress, 0.0, 0.000001, "(and the arc is gone)")
	_hold_for(hold, 0.05, false, true)
	check_eq(_hold_for(hold, held + 0.1, true, true), 1, "let go and held again, it pauses again")
	_hold_for(hold, 0.05, false, true)
	# The press has to begin where the hand is free.
	check_eq(_hold_for(hold, 0.2, true, false), 0, "a press where the hand has something to hold")
	check_eq(_hold_for(hold, 3.0 * held, true, true), 0, "that then finds itself in the air (a FLICK's end, a thing put down) pauses nothing")
	_hold_for(hold, 0.05, false, true)
	# And stay there.
	_hold_for(hold, held * 0.5, true, true)
	_hold_for(hold, 0.05, true, false)
	check_near(hold.progress, 0.0, 0.000001, "a hold that the pointer carries onto an anchor or the wheel is over")
	check_eq(_hold_for(hold, 3.0 * held, true, true), 0, "and does not begin again without a new press")
	# The press that closed the pause is no new hold.
	hold.reset(true)
	check_eq(_hold_for(hold, 3.0 * held, true, true), 0, "a button still down when the night goes on is no new press")

	# In the car: where the hand is free.
	_on_the_road()
	check(_to_the_air(), "on the road there is air to point at: no anchor, not the wheel")
	check(_sim.hand_is_free() and GameData.as_bool(_sim.snapshot()["hand_free"]), "there the hand has nothing to hold")
	_sim.hand.carrying = true
	check(not _sim.hand_is_free(), "(with something carried it has)")
	_sim.hand.carrying = false
	# The simulation makes nothing of a press there: the same night with it
	# and without.
	_input.lmb = false
	_ticks(_ticks_in(held + 0.5))
	var without: String = _sim.state_hash()
	_on_the_road()
	_to_the_air()
	hold.reset()
	var paused: int = 0
	_input.lmb = true
	for _tick_index: int in _ticks_in(held + 0.5):
		_tick()
		if hold.step(DT, _input.lmb, _sim.hand_is_free()):
			paused += 1
	check(_only_two_buttons() and paused == 1, "the left button held there: the game pauses, once")
	check_eq(_sim.state_hash(), without, "and the night is the same night to the bit: a press on nothing is nothing to the simulation")
	check_eq(_count_events("ritual_begun") + _count_events("ritual_completed"), 0, "(no ritual is begun by it)")
	# A TAP there is no pause.
	_input.lmb = false
	_tick()
	hold.step(DT, false, _sim.hand_is_free())
	paused = 0
	_input.lmb = true
	for _tick_index: int in _ticks_in(tuning.f("tap_max_time")):
		_tick()
		if hold.step(DT, true, _sim.hand_is_free()):
			paused += 1
	check_eq(paused, 0, "a TAP on nothing is no pause")
	# On the wheel, and on an anchor, the button is for those.
	_on_the_road()
	_grip()
	_tick()
	check(not _sim.hand_is_free(), "the pointer on the wheel's rim: the button grips")
	_input.lmb = true
	_ticks(_ticks_in(1.0))
	check(_sim.hand.gripping and not _sim.hand_is_free(), "(gripping)")
	_on_the_road()
	check(_reach("horn") and not _sim.hand_is_free(), "the pointer on an anchor: the button does what is there")

	# Wherever the car is: at a stall, with an officer at his window, on the
	# last street. (At each of them older rules keep the hand to its business
	# there; the air is nobody's business.)
	_new_sim()
	_sim.heckling = false
	_sim.begin_telling(TABLE, _seed_for("tea_stall"))
	_into_next_quiet_leg()
	_into_stall()
	check(_sim.stopped and _pauses_in_the_air(hold), "at a stall the left button held on nothing pauses")
	check(_sim.stopped, "(he has not left the stall for it)")
	_on_the_road()
	_sim.suspicion.begin_watch()
	_sim.suspicion.add(tuning.f("suspicion_max"))
	var guard: int = _ticks_in(20.0)
	while not _sim.pulled_over and guard > 0:
		guard -= 1
		_tick()
	_ticks(_ticks_in(3.0))
	check(_sim.pulled_over and _pauses_in_the_air(hold), "with an officer at his window too")
	check(_sim.pulled_over, "(the officer is still there)")
	_new_sim()
	_sim.act = 3
	_sim.begin_arrival()
	check(_sim.boss.kind == BossSim.ARRIVAL and _pauses_in_the_air(hold), "and on the last street, where the key is for parking")


## Steps a hold for `seconds`; how many times it said to pause.
func _hold_for(hold: PauseHold, seconds: float, down: bool, free: bool) -> int:
	var fired: int = 0
	for _index: int in _ticks_in(seconds):
		if hold.step(DT, down, free):
			fired += 1
	return fired


## Puts the pointer where there is nothing: the place of its range farthest
## from every anchor that is off the wheel's rim. False if there is none.
func _to_the_air() -> bool:
	var space: CabinSpace = _sim.space
	var best: Vector2 = Vector2.ZERO
	var best_distance: float = -1.0
	var steps: int = 24
	for row: int in steps + 1:
		for column: int in steps + 1:
			var at: Vector2 = Vector2(lerpf(space.pointer_min.x, space.pointer_max.x, float(column) / float(steps)),
					lerpf(space.pointer_min.y, space.pointer_max.y, float(row) / float(steps)))
			if space.pointer_on_rim(at):
				continue
			var nearest: float = INF
			for index: int in _sim.hand.anchor_count():
				nearest = minf(nearest, at.distance_to(_sim.hand.anchor_pointer(index)))
			if nearest > best_distance:
				best_distance = nearest
				best = at
	if best_distance < 0.0:
		return false
	_input.clear()
	_input.pointer_is_absolute = true
	_input.pointer = best
	_ticks(_ticks_in(1.5))
	_events = []
	return _sim.hand.snap_index == HandSim.NO_ANCHOR and not space.pointer_on_rim(_sim.hand.pointer)


## The pointer put on nothing and the left button held there for the
## pause's time and a little: true if the game pauses, once.
func _pauses_in_the_air(hold: PauseHold) -> bool:
	if not _to_the_air():
		return false
	hold.reset()
	var paused: int = 0
	_input.lmb = true
	for _index: int in _ticks_in(hold.hold_s + 0.3):
		_tick()
		if hold.step(DT, _input.lmb, _sim.hand_is_free()):
			paused += 1
	_input.lmb = false
	_tick()
	return paused == 1 and _only_two_buttons()


## The menus: a walk through all of them with mouse events and nothing else,
## in a build of its own.
func _check_the_menus() -> void:
	var captured: Array = []
	var args: PackedStringArray = ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--fixed-fps", "60", "--script", "res://tools/onehand_walk.gd"]
	var exit_code: int = OS.execute(OS.get_executable_path(), args, captured, true)
	var output: String = ""
	for chunk: Variant in captured:
		output += str(chunk)
	output = Smoke.strip_ansi(output)
	var steps: int = 0
	var failed: PackedStringArray = []
	var errors: PackedStringArray = []
	for raw: String in output.split("\n"):
		var line: String = raw.strip_edges()
		if line.begins_with("WALK ok:"):
			steps += 1
		elif line.begins_with("WALK FAIL:"):
			failed.append(line)
		for prefix: String in Smoke.ERROR_PREFIXES:
			if line.begins_with(prefix):
				errors.append(line)
	check_eq(exit_code, 0, "the walk through the menus with the mouse alone ends well")
	check(output.contains("WALK DONE"), "it reaches its end")
	check(failed.is_empty(), "no step of it fails; first: %s" % ("(none)" if failed.is_empty() else failed[0]))
	check(errors.is_empty(), "with no error output; first: %s" % ("(none)" if errors.is_empty() else errors[0]))
	check(steps >= 25, "(%d steps: the title, its options, the wedding and a Table, the pause in the car, the way back, an ending, the finale, the proverb, the credits)" % steps)
	for what: String in ["a press on Options", "the left button on a row takes its next option", "the right button the one before", "he sits, and the night begins",
			"the left button held on nothing: the night waits", "the wedding room again", "the title again", "a press: the finale",
			"the button let go: the proverb's card", "a press: the credits", "a press: the wedding room"]:
		check(output.contains("WALK ok: ") and output.contains(what), "the walk: %s" % what)
