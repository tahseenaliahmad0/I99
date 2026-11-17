extends CabinSuite
## M6: the Phantom (GDD 7.9): the missing arm, present in two small, fixed ways.


## T-PHANTOM-01: The Phantom of 7.9: a cross-reach begun at Nerves 60 or more,
## or while Lids are active, leaves 0.25 s late with a ghost left hand as the
## tell; the weather cramp fires once per Rain leg, Night leg and Storm at a
## fixed point: after a 1.5 s hum the hand can neither let go nor take hold
## for 0.5 s, and +10 Nerves; painkillers counter both, an adaptation that
## removes a cross-reach removes its flinch, and the setting turns both off.
func test_phantom_01() -> void:
	check_near(tuning.f("phantom_flinch_from"), 60.0, 0.000001, "the flinch comes at Nerves 60 or more")
	check_near(tuning.f("phantom_flinch_delay"), 0.25, 0.000001, "the real hand leaves 0.25 s late")
	check_near(tuning.f("phantom_cramp_hum"), 1.5, 0.000001, "the cramp is announced by 1.5 s of hum")
	check_near(tuning.f("phantom_cramp_length"), 0.5, 0.000001, "and lasts 0.5 s")
	check_near(tuning.f("phantom_cramp_nerves"), 10.0, 0.000001, "+10 Nerves")
	check(tuning.f("phantom_cramp_at") > 0.0 and tuning.f("phantom_cramp_at") < 1.0, "at a fixed point of the leg")
	_check_flinch()
	_check_flinch_counters()
	_check_cramp()
	_check_cramp_counters()


# --- The wrong-hand flinch -----------------------------------------------------

func _check_flinch() -> void:
	var late: float = tuning.f("phantom_flinch_delay")
	var from: float = tuning.f("phantom_flinch_from")

	# Below 60 a cross-reach leaves at once; at 60 it leaves 0.25 s late.
	var calm: float = _cross_reach_time("indicator_stalk", from - 0.5, 1)
	check_near(calm, GameData.as_float(data.record("anchors", "indicator_stalk").get("time_s")), 0.02, "(under Nerves 60 the indicator is its 0.41 s away)")
	var frayed: float = _cross_reach_time("indicator_stalk", from, 1)
	check_near(frayed - calm, late, DT * 0.5, "a cross-reach begun at Nerves 60 leaves 0.25 s late")
	check_near(_cross_reach_time("window_crank", from + 10.0, 1) - _cross_reach_time("window_crank", from - 10.0, 1), late, DT * 0.5, "the same for any control across the wheel")

	# The tell: a ghost of his left hand goes for the control while the real one waits.
	_new_sim()
	_sim.nerves.set_value(from + 5.0)
	_run(0.2)
	_sim.hand.place_at(_sim.space.grip_reference)
	var start: Vector3 = _sim.hand.pos
	_input.clear()
	_input.pointer_is_absolute = true
	_input.pointer = _sim.hand.anchor_pointer(_sim.hand.anchor_index(&"indicator_stalk"))
	var progress: PackedFloat64Array = PackedFloat64Array()
	var moved_early: bool = false
	for _index: int in _ticks_in(late) - 1:
		_tick()
		progress.append(GameData.as_float(_sim.snapshot()["ghost_progress"]))
		check_eq(_sim.snapshot()["ghost_at"], &"indicator_stalk", "")
		if _sim.hand.pos.distance_to(start) > 0.000001:
			moved_early = true
	check(not moved_early, "for those 0.25 s the real hand does not move")
	var rising: bool = progress.size() > 2
	for index: int in range(1, progress.size()):
		if progress[index] <= progress[index - 1]:
			rising = false
	check(rising and progress[0] >= 0.0 and progress[progress.size() - 1] < 1.0 and progress[progress.size() - 1] > 0.8,
			"the ghost of his left hand goes for the control meanwhile (%s to %s of the way)" % [str(snappedf(progress[0], 0.01)), str(snappedf(progress[progress.size() - 1], 0.01))])
	_ticks(3)
	check_eq(_sim.snapshot()["ghost_at"], &"", "then the ghost is gone")
	check(_sim.hand.pos.distance_to(start) > 0.001, "and the real hand is on its way")

	# While Lids are active, whatever his Nerves.
	_new_sim()
	_sim.act = 2
	var floor_now: float = _sim.heavy_floor()
	check(floor_now < from, "(the Heavy floor is far below 60)")
	_sim.nerves.set_value(floor_now - 5.0)
	_run(1.0)
	check(_sim.nerves.lids > 0.0, "(his lids are closing)")
	var drowsy: float = _reach_time("indicator_stalk")
	check_near(drowsy - calm, late, DT * 0.5, "a cross-reach begun while Lids are active leaves 0.25 s late too")

	# Not a cross-reach: a control on his own side; a reach that is already across.
	check_near(_cross_reach_time("radio", from + 10.0, 1), _cross_reach_time("radio", from - 10.0, 1), 0.000001, "a control on his own side has no flinch")
	_new_sim()
	_sim.nerves.set_value(from - 10.0)
	_reach("indicator_stalk")
	var from_tick: int = _sim.tick
	_reach("headlight_knob")
	var across_calm: int = _sim.tick - from_tick
	_new_sim()
	_sim.nerves.set_value(from - 10.0)
	_reach("indicator_stalk")
	_sim.nerves.set_value(from + 10.0)
	_ticks(SETTLE)
	from_tick = _sim.tick
	_reach("headlight_knob")
	check_eq(_sim.tick - from_tick, across_calm, "a hand already across the wheel goes on to the next control without one")

	# Every cross-reach flinches afresh.
	var second: float = _cross_reach_time("indicator_stalk", from + 5.0, 2)
	check_near(second - calm, late, DT * 0.5, "the next cross-reach flinches again")


func _check_flinch_counters() -> void:
	var late: float = tuning.f("phantom_flinch_delay")
	var from: float = tuning.f("phantom_flinch_from")
	var calm: float = _cross_reach_time("indicator_stalk", from - 10.0, 1)
	var pill_s: float = GameData.as_float(_ritual("painkillers_take").get("hold_s"))

	# Painkillers.
	_new_sim()
	_give("painkillers")
	_hold_at("face", pill_s)
	check(_sim.phantom_muted(), "(a pill mutes the Phantom)")
	_sim.nerves.set_value(from + 10.0)
	_run(0.2)
	check_near(_reach_time("indicator_stalk"), calm, 0.000001, "on painkillers a cross-reach at Nerves 70 leaves at once")
	check_eq(_sim.snapshot()["ghost_at"], &"", "with no ghost")

	# An Adaptation that removes the cross-reach removes its flinch.
	_new_sim()
	_give("crossover_stalk")
	_sim.nerves.set_value(from + 10.0)
	_run(0.2)
	var moved: float = _reach_time("indicator_stalk")
	_new_sim()
	_give("crossover_stalk")
	_sim.nerves.set_value(from - 10.0)
	_run(0.2)
	check_near(moved, _reach_time("indicator_stalk"), 0.000001, "with the crossover stalk the indicator is no cross-reach: no flinch at Nerves 70")
	_sim.nerves.set_value(from + 10.0)
	_run(0.2)
	check_near(_reach_time("headlight_knob") - GameData.as_float(data.record("anchors", "headlight_knob").get("time_s")), late, 0.03, "(the headlight knob still is one, and still flinches)")
	_new_sim()
	_give("window_switch")
	_sim.nerves.set_value(from + 10.0)
	_run(0.2)
	var switch_frayed: float = _reach_time("window_switch")
	_sim.nerves.set_value(from - 10.0)
	_run(0.2)
	check_near(switch_frayed, _reach_time("window_switch"), 0.000001, "the console switch opens the window with no cross-reach, so with no flinch")

	# The setting.
	_new_sim()
	_sim.phantom_enabled = false
	_sim.nerves.set_value(from + 10.0)
	_run(0.2)
	check_near(_reach_time("indicator_stalk"), calm, 0.000001, "with the Phantom switched off there is no flinch")
	check_eq(_sim.snapshot()["ghost_at"], &"", "and no ghost")


# --- The weather cramp ----------------------------------------------------------

func _check_cramp() -> void:
	var hum: float = tuning.f("phantom_cramp_hum")
	var length: float = tuning.f("phantom_cramp_length")
	var share: float = tuning.f("phantom_cramp_at")

	# A Rain leg: the hum at the fixed point, the cramp 1.5 s later, +10 Nerves.
	for leg_id: String in ["rain", "night"]:
		var act: int = 1 if leg_id == "rain" else 2
		var first: Dictionary = _drive_through_cramp(leg_id, act, 71, "")
		check_near(GameData.as_float(first["hum_s"]), GameData.as_float(first["length"]) * share, 0.5, "in a %s leg the hum begins at the fixed point" % leg_id)
		check_eq(GameData.as_int(first["hums"]), 1, "once (heard as phantom_hum)")
		check_near(GameData.as_float(first["cramp_after"]), hum, DT * 0.5, "the cramp comes 1.5 s after the hum begins")
		check_near(GameData.as_float(first["nerves_jump"]), tuning.f("phantom_cramp_nerves"), 0.05, "with +10 Nerves")
		check_near(GameData.as_float(first["cramp_for"]), length, DT * 0.5, "and lasts 0.5 s")
		var other: Dictionary = _drive_through_cramp(leg_id, act, 205, "")
		check_near(GameData.as_float(other["hum_s"]), GameData.as_float(first["hum_s"]), 0.5, "at the same point of another %s leg: it is fixed" % leg_id)

	# For those 0.5 s a hand on the wheel cannot let go.
	var holding: Dictionary = _drive_through_cramp("rain", 1, 71, "grip")
	check(GameData.as_bool(holding["gripped_through"]), "a hand that is on the wheel cannot let go: the button up, it still grips")
	check(GameData.as_bool(holding["free_after"]), "when the cramp is over it lets go")
	# And a hand off the wheel cannot take hold of it, or of anything.
	var reaching: Dictionary = _drive_through_cramp("rain", 1, 71, "reach")
	check(not GameData.as_bool(reaching["gripped_through"]), "a hand that is off the wheel cannot take hold of it: the button down on the rim, it does not grip")
	check(GameData.as_bool(reaching["free_after"]), "when the cramp is over it grips")
	var honking: Dictionary = _drive_through_cramp("rain", 1, 71, "horn")
	check_eq(GameData.as_int(honking["honks_during"]), 0, "nor can it work a control: a TAP at the horn during the cramp is nothing")
	check_eq(GameData.as_int(honking["honks_after"]), 1, "(after it, the horn works)")

	# No weather, no cramp.
	var dry: Dictionary = _drive_through_cramp("open_road", 1, 5, "")
	check_eq(GameData.as_int(dry["hums"]), 0, "a clear day leg has no cramp")
	check_near(GameData.as_float(dry["nerves_jump"]), 0.0, 0.05, "and nothing frays him at that point")


func _check_cramp_counters() -> void:
	# Painkillers taken before the point: none in that leg.
	var numbed: Dictionary = _drive_through_cramp("rain", 1, 71, "pill")
	check_eq(GameData.as_int(numbed["hums"]), 0, "on painkillers the leg has no cramp")
	check_near(GameData.as_float(numbed["nerves_jump"]), 0.0, 0.05, "and no +10 Nerves")
	# The setting.
	var off: Dictionary = _drive_through_cramp("night", 2, 71, "off")
	check_eq(GameData.as_int(off["hums"]), 0, "with the Phantom switched off there is no cramp")
	check_near(GameData.as_float(off["nerves_jump"]), 0.0, 0.05, "and no +10 Nerves")


# --- Helpers -------------------------------------------------------------------

## Seconds from the wheel to a control at the given Nerves; `reaches` > 1
## makes the same reach that many times and times the last.
func _cross_reach_time(anchor: String, nerves: float, reaches: int) -> float:
	_new_sim()
	_sim.nerves.set_value(nerves)
	_run(0.2)
	var seconds: float = 0.0
	for _reach_index: int in reaches:
		seconds = _reach_time(anchor)
	return seconds


## A quiet leg driven in third gear from a little before the cramp's point to
## well past it. `doing` is what he does about it: "" nothing; "grip" holds
## the wheel and lets the button go when the cramp begins; "reach" has his
## hand off the wheel and presses on the rim when it begins; "horn" taps the
## horn during it and after; "pill" takes a painkiller first; "off" has the
## Phantom switched off.
func _drive_through_cramp(leg_id: String, act: int, leg_seed: int, doing: String) -> Dictionary:
	_begin_quiet_leg(leg_id, act, leg_seed)
	_sim.in_encounter = true
	if doing == "off":
		_sim.phantom_enabled = false
	if doing == "pill":
		_give("painkillers")
		_hold_at("face", GameData.as_float(_ritual("painkillers_take").get("hold_s")))
		_input.clear()
	var point: float = _sim.leg.length * tuning.f("phantom_cramp_at")
	_sim.car.s = point - 40.0
	if doing == "grip":
		_grip()
	elif doing == "horn":
		_reach("horn")
	_events = []
	var hum_s: float = -1.0
	var hum_tick: int = -1
	var cramp_tick: int = -1
	var end_tick: int = -1
	var jump: float = 0.0
	var gripped_through: bool = doing == "grip"
	var free_after: bool = false
	var honks_during: int = 0
	var honks_after: int = 0
	var guard: int = _ticks_in(12.0)
	var before: float = _sim.nerves.value
	while _sim.car.s < point + 120.0 and guard > 0:
		guard -= 1
		_tick()
		jump = maxf(jump, _sim.nerves.value - before)
		before = _sim.nerves.value
		if hum_tick < 0 and _sim.cramp == DriveSim.HUM:
			hum_tick = _sim.tick
			hum_s = _sim.car.s
		if cramp_tick < 0 and _sim.cramp == DriveSim.CRAMPED:
			cramp_tick = _sim.tick
			if doing == "grip":
				_input.clear()
			elif doing == "reach":
				_input.clear()
				_input.pointer_is_absolute = true
				_input.pointer = _sim.space.point_to_pointer(_sim.space.grip_reference)
				_input.lmb = true
			elif doing == "horn":
				_input.lmb = true
		if cramp_tick >= 0 and end_tick < 0:
			if _sim.cramp == DriveSim.CRAMPED:
				if doing == "grip" and not _sim.hand.gripping:
					gripped_through = false
				if doing == "reach" and _sim.hand.gripping:
					gripped_through = true
				if doing == "horn":
					# Tap after tap.
					_input.lmb = (_sim.tick - cramp_tick) % 8 < 4
					honks_during = _count_events("ritual_completed", "ritual", "horn")
			else:
				end_tick = _sim.tick
				if doing == "horn":
					_input.lmb = false
					_ticks(SETTLE)
					_tap()
					honks_after = _count_events("ritual_completed", "ritual", "horn") - honks_during
		if end_tick >= 0 and _sim.tick == end_tick + 30:
			free_after = (not _sim.hand.gripping) if doing == "grip" else _sim.hand.gripping
	_input.clear()
	return {
		"length": _sim.leg.length,
		"hum_s": hum_s,
		"hums": _count_events("sfx_requested", "id", "phantom_hum"),
		"cramp_after": float(cramp_tick - hum_tick) * DT if cramp_tick >= 0 else -1.0,
		"cramp_for": float(end_tick - cramp_tick) * DT if end_tick >= 0 else -1.0,
		"nerves_jump": jump,
		"gripped_through": gripped_through,
		"free_after": free_after,
		"honks_during": honks_during,
		"honks_after": honks_after,
	}
