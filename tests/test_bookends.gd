extends CabinSuite
## M9d: the two bookends (GDD 3.3): the prologue "Two Hands" (10.1) and the
## finale "One Hand" (10.6). T-PROLOGUE-01, T-FINALE-01.

const TABLE_TONIGHT: String = "children"

## Every line asked for so far, with the tick it was asked in.
var _lines: Array[Dictionary] = []


func before_each() -> void:
	super.before_each()
	_lines = []


# --- Helpers -------------------------------------------------------------------

## The prologue from its start, with the Children's Telling after it.
func _begin_prologue(telling_seed: int = 5) -> void:
	_sim = DriveSim.new(fresh_data())
	_events = []
	_lines = []
	_keep_lane = false
	_input.clear()
	_sim.begin_prologue(TABLE_TONIGHT, telling_seed)
	_gather()


func _step() -> void:
	_sim.step(_input)
	_gather()


func _steps(count: int) -> void:
	for _index: int in count:
		_step()


func _gather() -> void:
	for event: Dictionary in _sim.drain_events():
		_events.append(event)
		if GameData.as_string(event.get("type")) == "line_requested":
			_lines.append({"id": GameData.as_string(event.get("id")), "tick": _sim.tick})


func _line_tick(id: String) -> int:
	for line: Dictionary in _lines:
		if GameData.as_string(line["id"]) == id:
			return GameData.as_int(line["tick"])
	return -1


## Steps until the prologue's step `number` is on.
func _to_step(number: int) -> void:
	var guard: int = _ticks_in(80.0)
	while _sim.prologue.active and _sim.prologue.step < number and guard > 0:
		guard -= 1
		_step()


func _prompt() -> String:
	return GameData.as_string(_sim.snapshot()["prologue_prompt"])


## How far the car is from the middle of the lane the left hand keeps.
func _off_lane() -> float:
	return absf(_sim.car.x - _sim.car.lane_center(_sim._prologue_lane))


# --- T-PROLOGUE-01 ---------------------------------------------------------------

## T-PROLOGUE-01: The prologue of 10.1: it plays on first launch and can be
## replayed from the title; it lasts 75 s and cannot be failed; its seven
## steps run in order with the left hand holding the lane, so no reach has
## a cost; it then cuts to tonight at 22:00, rolling in first gear with the
## wheel unheld, and the narrator says narrator.start.
func test_prologue_01() -> void:
	_check_first_launch()
	_check_the_75_seconds()
	_check_the_steps_in_order()
	_check_each_step_is_done_by_its_action()
	_check_the_left_hand()
	_check_it_cannot_be_failed()
	_check_the_cut_to_tonight()


## It plays on first launch, once; and again whenever it is asked for.
func _check_first_launch() -> void:
	var kept_profile: Dictionary = Game.profile
	var kept_telling: Dictionary = Game.saved_telling
	var kept_args: Dictionary = Game.args
	Game.profile = Save.new_profile(data)
	Game.saved_telling = {}
	Game.args = {}
	check(not GameData.as_bool(Game.profile.get("prologue_seen")), "(a new player has not seen the prologue)")
	check(Game.wants_prologue(), "on first launch the prologue plays")
	check_eq(Game.after_title(), Game.AppState.PROLOGUE, "the title leads to it (GDD 13.4)")
	Game.args = {"skip-prologue": true}
	check_eq(Game.after_title(), Game.AppState.WEDDING, "(not with --skip-prologue, GDD 13.9)")
	Game.args = {}
	Game.prologue_played()
	check(not Game.wants_prologue(), "once played it does not play by itself again")
	check_eq(Game.after_title(), Game.AppState.WEDDING, "the title leads to the wedding")
	var read: Dictionary = Save.from_text(FileAccess.get_file_as_string(Game.save_path()))
	check(GameData.as_bool(GameData.as_dict(read.get("profile")).get("prologue_seen")), "the save file remembers")
	# Replayed from the title: the simulation plays it whenever it is begun,
	# whatever the profile says.
	_begin_prologue()
	check(_sim.prologue.active and _sim.prologue.step == 0, "asked for again, it begins again")
	_step()
	check_eq(GameData.as_int(_sim.snapshot()["prologue_step"]), 1, "from its first step")
	Game.profile = kept_profile
	Game.saved_telling = kept_telling
	Game.args = kept_args


## "It lasts 75 s": to the tick, whatever he does or leaves undone.
func _check_the_75_seconds() -> void:
	check_near(tuning.f("prologue_length"), 75.0, 0.000001, "GDD 10.1: it lasts 75 s")
	var steps: Array = tuning.a("prologue_step_s")
	check_eq(steps.size(), PrologueSim.STEPS, "in seven steps")
	var total: float = 0.0
	for seconds: Variant in steps:
		total += GameData.as_float(seconds)
	check_near(total, 75.0, 0.000001, "which fill it exactly")
	_begin_prologue()
	check_near(_sim.prologue.length(), 75.0, 0.000001, "(the clock reads the same)")
	var ticks: int = 0
	var guard: int = _ticks_in(100.0)
	while _sim.prologue.active and guard > 0:
		guard -= 1
		ticks += 1
		_step()
	check_eq(ticks, _ticks_in(75.0), "with nothing done at all it is over after 75 s, to the tick")
	check(_sim.run.active, "and tonight has begun")


## "Each object pulses in turn and one short subtitle names the action."
func _check_the_steps_in_order() -> void:
	_begin_prologue()
	var anchors: PackedStringArray = ["radio", _anchor_of("tea_glass"), "gear_lever", "horn", "wiper_stalk", "dash_1", ""]
	var seen: PackedInt32Array = []
	var prompts: PackedStringArray = []
	var last: int = 0
	var guard: int = _ticks_in(80.0)
	while _sim.prologue.active and guard > 0:
		guard -= 1
		_step()
		var number: int = GameData.as_int(_sim.snapshot()["prologue_step"])
		if number != last and number > 0:
			last = number
			seen.append(number)
			prompts.append(_prompt())
	check_eq(seen, PackedInt32Array([1, 2, 3, 4, 5, 6, 7]), "the seven steps run in order")
	check_eq(prompts, anchors, "each pulses where the right hand is to go: the radio, the tea, the lever, the horn, the wiper stalk, the photo on the dash; the last asks for nothing")
	var start: float = 0.0
	for number: int in range(1, PrologueSim.STEPS + 1):
		var line: int = _line_tick("prologue.step.%d" % number)
		if number < PrologueSim.LIFT:
			check(data.has_line("prologue.step.%d" % number), "step %d has its subtitle" % number)
			check_near(float(line - 1) * DT, start, DT * 1.5, "step %d: its subtitle names the action as it begins, %d s in" % [number, roundi(start)])
		else:
			check_eq(line, -1, "the seventh has no prompt")
		check_near(_sim.prologue.step_start(number), start, 0.000001, "(step %d begins at %d s)" % [number, roundi(start)])
		start += GameData.as_float(tuning.a("prologue_step_s")[number - 1])
	# What the morning does by itself.
	_begin_prologue()
	check_eq(_sim.gate.gear, 2, "he is in second gear: \"Shift from 2nd to 3rd\" is still to come")
	check(not GameData.as_bool(_sim.snapshot()["raining"]), "(a dry dawn)")
	_to_step(PrologueSim.HONK)
	_steps(2)
	var friends: int = 0
	for vehicle: TrafficSim.Vehicle in _sim.traffic.vehicles:
		if vehicle.s < _sim.car.s and vehicle.speed > _sim.car.speed:
			friends += 1
	check_eq(friends, 1, "step 4: a friend comes up from behind to pass")
	_to_step(PrologueSim.WIPERS)
	_steps(2)
	check(GameData.as_bool(_sim.snapshot()["raining"]) and _sim.items.raining, "step 5: it rains")
	_to_step(PrologueSim.LIFT)
	_steps(_ticks_in(GameData.as_float(tuning.a("prologue_step_s")[PrologueSim.LIFT - 1]) * 0.5))
	var lift: float = GameData.as_float(_sim.snapshot()["prologue_lift"])
	check_near(lift, 0.5, 0.01, "step 7: half-way through it the left hand is half-way off the wheel, the screen half white")
	check_eq(GameData.as_string(_sim.snapshot()["left_hand"]), "window_crank", "it lifts toward the window crank")


## Each step is done by its own action, in its own turn, and by no other.
func _check_each_step_is_done_by_its_action() -> void:
	# 1. Tune the radio to music.
	_begin_prologue()
	_steps(_ticks_in(2.0))
	check(_sim.items.radio != ItemSim.MUSIC and not _sim.prologue.done, "two seconds in, the radio not on music: step 1 is still to do")
	check_eq(_prompt(), "radio", "(and the radio pulses)")
	_sim.items.set_radio(ItemSim.MUSIC)
	_step()
	check(_sim.prologue.done, "step 1 is done when the radio plays music")
	check_eq(_prompt(), "", "and its pulse stops")
	check_eq(_sim.prologue.step, 1, "(the next step waits for its turn)")
	_to_step(PrologueSim.TEA)
	check(not _sim.prologue.done, "when its turn comes the next step is still to do")
	check_eq(_prompt(), _anchor_of("tea_glass"), "and pulses at the tea")
	# 2. Sip the tea.
	_begin_prologue()
	_to_step(PrologueSim.TEA)
	_tap_at("horn")
	_gather()
	check(not _sim.prologue.done, "the horn does not do step 2")
	_hold_at(_anchor_of("tea_glass"), GameData.as_float(_ritual("tea_sip").get("hold_s")) + 0.1)
	_gather()
	check(_sim.prologue.done and _sim.prologue.step == PrologueSim.TEA, "a sip of the tea does")
	# 3. Shift from 2nd to 3rd.
	_begin_prologue()
	_to_step(PrologueSim.SHIFT)
	_steps(_ticks_in(2.0))
	check(not _sim.prologue.done and _sim.gate.gear == 2, "two seconds into step 3, still in second: it is still to do")
	_sim.gate.reset(3)
	_step()
	check(_sim.prologue.done, "step 3 is done in third gear")
	# 4. Honk at a friend passing.
	_begin_prologue()
	_to_step(PrologueSim.HONK)
	_tap_at("horn")
	_gather()
	check(_sim.prologue.done, "step 4 is done by the horn")
	# 5. It rains: flick the wipers.
	_begin_prologue()
	_to_step(PrologueSim.WIPERS)
	_step()
	check(not _sim.prologue.done, "(the wipers are still)")
	_wipe()
	_gather()
	check(_sim.prologue.done, "step 5 is done by a flick of the wipers")
	# 6. Tuck the new photo into the visor.
	_begin_prologue()
	_to_step(PrologueSim.PHOTO)
	_step()
	check_eq(GameData.as_string(_sim._ritual_at("dash_1").get("id")), "photo_tuck", "the new photo lies on the dash")
	_drag("dash_1", "visor")
	_gather()
	check(_sim.prologue.done, "step 6 is done when it is tucked into the visor")
	check(_sim.items.flag(&"photo_tucked"), "(it is there)")
	check(_sim._ritual_at("dash_1").is_empty(), "(and not on the dash any more)")
	# A step not done is simply over when its time is: the next one comes.
	_begin_prologue()
	_to_step(PrologueSim.TEA)
	check(not _sim.prologue.done and _sim.items.radio != ItemSim.MUSIC, "a step he leaves undone passes all the same")
	# Tonight the photo is in the visor already, and nothing lies on the dash.
	_new_sim()
	_sim.begin_telling(TABLE_TONIGHT, 5)
	check(GameData.as_string(_sim._ritual_at("dash_1").get("id")) != "photo_tuck", "tonight there is no new photo to tuck")


## "A solid left arm holds the wheel and keeps the lane by itself. The
## pointer is the right hand, and nothing it does has a cost."
func _check_the_left_hand() -> void:
	_begin_prologue()
	check(not _sim.hand.gripping, "(his right hand is not on the wheel)")
	check(_sim.left_hand_on_wheel(), "the left hand has it")
	check_eq(GameData.as_string(_sim.snapshot()["left_hand"]), "wheel", "(the snapshot shows it there)")
	var lane: int = _sim.car.lane_of(_sim.car.x)
	var worst: float = 0.0
	var nerves: float = _sim.nerves.value
	# Twenty seconds of reaching across the cabin: the radio, the glovebox.
	for anchor: String in ["radio", "glovebox", "mirror", "radio"]:
		_input.clear()
		_input.pointer_is_absolute = true
		_input.pointer = _sim.hand.anchor_pointer(_sim.hand.anchor_index(StringName(anchor)))
		for _index: int in _ticks_in(5.0):
			_step()
			worst = maxf(worst, _off_lane())
	check(worst < 0.3, "twenty seconds of reaching, nobody steering: the car keeps its lane (%.2f m off at most)" % worst)
	check_eq(_sim.car.lane_of(_sim.car.x), lane, "(the lane it began in)")
	check_near(_sim.nerves.value, nerves, 0.000001, "and his Nerves are where they were: no reach has a cost")
	check_near(_sim.clock.minutes, 0.0, 0.000001, "tonight's Clock does not run in that morning")
	check_eq(_sim.faults.lamps, 0, "(no lamp)")
	# The same twenty seconds tonight, with one hand: the car is gone.
	_new_sim()
	_keep_lane = false
	_sim.gate.reset(2)
	_sim.car.reset(1, 2)
	var drifted: float = 0.0
	_input.clear()
	_input.pointer_is_absolute = true
	_input.pointer = _sim.hand.anchor_pointer(_sim.hand.anchor_index(&"radio"))
	for _index: int in _ticks_in(20.0):
		_sim.step(_input)
		drifted = maxf(drifted, absf(_sim.car.x - _sim.car.lane_center(1)))
	_sim.drain_events()
	check(drifted > 1.0, "(tonight, with nobody at the wheel for as long, it drifts %.1f m)" % drifted)
	# Step 5: "The left hand indicates and changes lane by itself."
	_begin_prologue()
	_to_step(PrologueSim.WIPERS)
	var from_lane: int = _sim.car.lane_of(_sim.car.x)
	_steps(2)
	check(_sim.items.indicator != 0, "step 5: the left hand indicates")
	check_eq(GameData.as_string(_sim.snapshot()["left_hand"]), "indicator_stalk", "(it is at the stalk)")
	_steps(_ticks_in(6.0))
	var to_lane: int = _sim.car.lane_of(_sim.car.x)
	check_eq(absi(to_lane - from_lane), 1, "and the car changes lane by itself")
	check(_off_lane() < 0.3, "and settles in the middle of the new one (%.2f m off)" % _off_lane())
	# His right hand on the wheel is his: with it there, he steers.
	_begin_prologue()
	_grip()
	_gather()
	check(_sim.hand.gripping and not _sim.left_hand_on_wheel() and not _sim.wheel.locked, "with his right hand on the wheel he steers himself")
	_release()
	_gather()
	check(_sim.left_hand_on_wheel() and _sim.wheel.locked, "let go, the left hand has it again")


## "It cannot be failed": whatever the right hand does.
func _check_it_cannot_be_failed() -> void:
	_begin_prologue(9)
	var ticks: int = 0
	var wrecks: int = 0
	var hits: int = 0
	var lamps: int = 0
	var worst_nerves: float = 0.0
	var guard: int = _ticks_in(100.0)
	while _sim.prologue.active and guard > 0:
		guard -= 1
		# A hand that will not behave: on the wheel and hauling it left and
		# right, off it, on the brake, in every gear, on the horn.
		var second: int = ticks / 120
		_input.clear()
		_input.pointer_is_absolute = true
		if second % 9 < 5:
			_input.pointer = _sim.space.point_to_pointer(_sim.space.grip_reference)
			_input.lmb = true
			_input.pointer_delta = Vector2(60.0 if second % 2 == 0 else -60.0, 0.0)
		else:
			_input.pointer = _sim.hand.anchor_pointer(_sim.hand.anchor_index(&"glovebox"))
		_input.rmb = second % 7 == 3
		_input.pad_horn = second % 5 == 1
		if ticks % 600 == 0:
			_sim.gate.reset(1 + (ticks / 600) % 5)
		ticks += 1
		_step()
		if _sim.prologue.active:
			worst_nerves = maxf(worst_nerves, _sim.nerves.value)
			lamps = maxi(lamps, _sim.faults.lamps)
	wrecks = _count_events("wreck")
	hits = _count_events("hit")
	check_eq(ticks, _ticks_in(75.0), "flailing at everything for the whole of it: it still lasts 75 s to the tick")
	check_eq(wrecks, 0, "there is no Wreck in it")
	check_eq(hits, 0, "nothing is hit")
	check_eq(lamps, 0, "no lamp is lit")
	check_near(worst_nerves, 0.0, 0.000001, "and his Nerves never rise")
	check_eq(_count_events("pulled_over") + _count_events("snap"), 0, "(nobody stops him, nothing snaps)")
	check(_sim.run.active, "and tonight begins after it as it would have")
	# Even what stands in his way: a truck crawling in his own lane, and the
	# left hand keeping that lane. Nothing is hit; the morning goes on.
	_begin_prologue(9)
	_sim.traffic.spawn(&"truck", _sim.car.lane_of(_sim.car.x), _sim.car.s + 30.0, 20.0)
	_input.clear()
	_steps(_ticks_in(8.0))
	check_eq(_count_events("hit"), 0, "a truck crawling in his lane is not hit either")
	check_eq(_sim.faults.lamps, 0, "(no lamp)")
	check(_sim.prologue.active and not _sim.wrecked, "(and the prologue goes on)")


## "Cut to tonight. 22:00. The car is rolling in first gear with the wheel
## unheld, drifting right. The narrator says narrator.start."
func _check_the_cut_to_tonight() -> void:
	_begin_prologue(5)
	_sim.items.set_radio(ItemSim.MUSIC)
	_sim.gate.reset(3)
	var guard: int = _ticks_in(100.0)
	while _sim.prologue.active and guard > 0:
		guard -= 1
		_step()
	var cut: int = _sim.tick
	check_eq(_line_tick("narrator.start"), cut, "in the tick the prologue ends the narrator says narrator.start")
	check(data.has_line("narrator.start"), "(a line of GDD 3.6)")
	check(_sim.run.active and _sim.run.table == TABLE_TONIGHT, "tonight: a Telling, at the Table it was begun for")
	check_eq(_sim.run.stage, RunState.Stage.APPROACH, "from Baghdad")
	check_eq(_sim.clock.text(), "22:00", "at 22:00")
	check_eq(_sim.gate.gear, tuning.i("start_gear"), "in first gear, whatever gear the morning ended in")
	check_near(_sim.car.speed, tuning.fi("gear_speeds", 0), 0.000001, "rolling")
	check(not _sim.hand.gripping and not _sim.left_hand_on_wheel() and not _sim.wheel.locked, "with the wheel unheld: there is no left hand any more")
	check_eq(GameData.as_string(_sim.snapshot()["left_hand"]), "", "(the snapshot shows none)")
	check_eq(GameData.as_int(_sim.snapshot()["prologue_step"]), 0, "(and no prologue)")
	check(_sim.items.radio != ItemSim.MUSIC, "the cabin is tonight's, not the morning's")
	check(not _sim.items.flag(&"prologue") and not GameData.as_bool(_sim.snapshot()["raining"]), "(no photo on the dash, no rain)")
	# Twenty-two years on: the same seed tells the same night as a Telling
	# begun without the prologue.
	var after_prologue: String = _sim.state_hash()
	var plain: DriveSim = DriveSim.new(fresh_data())
	plain.begin_telling(TABLE_TONIGHT, 5)
	plain.tick = _sim.tick
	check_eq(after_prologue, plain.state_hash(), "it is the night a Telling begun by itself would be, to the bit")
	# And it drifts: nobody tells him to take the wheel.
	var x: float = _sim.car.x
	_input.clear()
	_steps(_ticks_in(4.0))
	check(_sim.car.x > x + 0.05, "left alone it drifts right (%.2f m in 4 s)" % (_sim.car.x - x))
	# Every Telling begins with those words, the prologue before it or not.
	_new_sim()
	_lines = []
	_sim.begin_telling("drivers", 3)
	_gather()
	check(_line_tick("narrator.start") >= 0, "(a Telling begun from the wedding room starts with the same line)")


# --- T-FINALE-01 -----------------------------------------------------------------

func _finale() -> FinaleSim:
	var finale: FinaleSim = FinaleSim.new()
	finale.configure(tuning)
	finale.begin()
	return finale


## A TAP on her palm: the button down for a moment, and up.
func _clap(finale: FinaleSim) -> void:
	finale.step(DT, true, true)
	finale.step(DT, true, true)
	finale.step(DT, false, true)
	finale.step(DT, false, true)


func _finale_events(finale: FinaleSim, into: Array[Dictionary]) -> void:
	for event: Dictionary in finale.events:
		into.append(event)


## T-FINALE-01: The finale ends only when the grip input is released; it
## runs 5 simulated minutes without ending otherwise.
func test_finale_01() -> void:
	check_eq(tuning.i("finale_claps"), 8, "GDD 10.6: after 8 claps she takes his hand")
	check_near(tuning.f("finale_walk_s"), 10.0, 0.000001, "the walk to the groom takes 10 s")
	check_near(tuning.f("finale_baba_s"), 20.0, 0.000001, "at 20 s she says \"Baba.\"")
	check_near(tuning.f("finale_clap_again_s"), 90.0, 0.000001, "at 90 s the room claps softly again")
	check(data.has_line("finale.baba") and data.has_line("finale.proverb"), "(her word and the proverb are lines)")

	# Clapping: only a TAP on her palm is a clap; nothing else does anything,
	# for as long as he likes.
	var finale: FinaleSim = _finale()
	var said: Array[Dictionary] = []
	for _index: int in _ticks_in(300.0):
		finale.step(DT, false, false)
	check(finale.phase == FinaleSim.CLAPPING and not finale.over(), "five minutes with his hand at his side: she waits, palm raised")
	finale.step(DT, true, false)
	finale.step(DT, false, false)
	check_eq(finale.claps, 0, "a TAP beside her palm is no clap")
	for held: int in 600:
		finale.step(DT, true, true)
	check_eq(finale.claps, 1, "a hand held against her palm is one clap, not many")
	finale.step(DT, false, true)
	for number: int in range(2, tuning.i("finale_claps")):
		_clap(finale)
		_finale_events(finale, said)
		check_eq(finale.claps, number, "clap %d" % number) if number == 2 or number == 7 else true
		check_eq(finale.room_doublings(), number, "(the room's clapping has doubled %d times)" % number) if number == 7 else true
	check(finale.phase == FinaleSim.CLAPPING and not finale.holding, "seven claps: her palm is still raised")
	finale.step(DT, true, true)
	check_eq(finale.claps, 8, "the eighth clap")
	check(finale.phase == FinaleSim.WALKING and finale.holding, "and she takes his hand")

	# The walk: 10 s of holding. Let go on the way, she waits; nothing ends.
	for _index: int in _ticks_in(4.0):
		finale.step(DT, true, true)
	check_near(finale.walk_share(), 0.4, 0.01, "4 s of holding her hand: 4 tenths of the way to the groom")
	for _index: int in _ticks_in(300.0):
		finale.step(DT, false, false)
	check(not finale.over() and finale.phase == FinaleSim.WALKING, "let go on the way, for five minutes: it does not end")
	check(not finale.holding, "(her hand is held out, waiting)")
	check_near(finale.walk_share(), 0.4, 0.01, "(and they have not moved)")
	var walk_left: int = _ticks_in(6.0)
	for _index: int in walk_left - 1:
		finale.step(DT, true, false)
	check_eq(finale.phase, FinaleSim.WALKING, "taken again: one tick short of the 10 s they are still walking")
	finale.step(DT, true, false)
	check(finale.phase == FinaleSim.STANDING and finale.walk_share() == 1.0, "after 10 s of holding in all they stand in front of the groom")

	# Standing there: "Nothing happens until the player releases the button.
	# There is no prompt and no timer."
	said = []
	var baba_at: int = -1
	var again_at: int = -1
	var five_minutes: int = _ticks_in(300.0)
	for tick: int in five_minutes:
		finale.step(DT, true, false)
		for event: Dictionary in finale.events:
			said.append(event)
			if GameData.as_string(event.get("id")) == "finale.baba":
				baba_at = tick + 1
			if GameData.as_bool(event.get("soft")):
				again_at = tick + 1
		if finale.over():
			break
	check(not finale.over(), "T-FINALE-01: held for 5 simulated minutes, it has not ended")
	check_eq(finale.phase, FinaleSim.STANDING, "they stand there still")
	check_near(finale.stood, 300.0, 0.001, "(for 300 s)")
	check_eq(baba_at, _ticks_in(20.0), "at 20 s she says \"Baba.\"")
	check_eq(again_at, _ticks_in(90.0), "at 90 s the room starts clapping softly again")
	check_eq(said.size(), 2, "and that is all that happens: once each")
	check(finale.holding and finale.said_baba and finale.clapping_again, "(her hand is in his)")
	# Only letting go ends it.
	finale.step(DT, false, false)
	check(finale.over(), "T-FINALE-01: the grip is released, and it ends")
	check(not finale.holding, "her hand goes to the groom's")
	check_eq(GameData.as_string(finale.events[0].get("id")) if not finale.events.is_empty() else "", "finale.proverb", "cut to the title card with finale.proverb")
	check_eq(GameData.as_string(finale.snapshot()["phase"]), "over", "(the snapshot says so)")
	var time: float = finale.time
	finale.step(DT, true, true)
	check(finale.over() and finale.events.is_empty() and finale.time == time, "and nothing after it brings it back")

	# Let go at once: it ends before she has said a word.
	var short: FinaleSim = _finale()
	for _index: int in tuning.i("finale_claps") - 1:
		_clap(short)
	for _index: int in _ticks_in(10.0) + 1:
		short.step(DT, true, true)
	check_eq(short.phase, FinaleSim.STANDING, "(eight claps and the walk in one hold)")
	short.step(DT, false, true)
	check(short.over() and not short.said_baba, "let go the moment they arrive: it ends there, with nothing said")
	# It cannot be failed or hurried: no number of claps, no wait, ends it.
	var idle: FinaleSim = _finale()
	for tick: int in _ticks_in(120.0):
		idle.step(DT, tick % 30 < 2, tick % 60 < 30)
	check(not idle.over(), "a hundred TAPs in two minutes, on her palm and off it: no ending without the walk and the letting go")
