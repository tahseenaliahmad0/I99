extends TestSuite
## M3: the base cabin (GDD 4.6, 6.2, 7.3, 7.4): horn, wipers, radio,
## cigarettes, tea, visor photo, slap and window.

const DT: float = DriveSim.DT

var _sim: DriveSim
var _input: DriveInput
## Nerves are read "per tick of interest", so the road's ambient rate is kept
## silent (as in an encounter) unless a check is about a rate.
var _quiet: bool = true


func before_each() -> void:
	_new_sim()
	_input = DriveInput.new()


## T-ITEM-BASE: the base cabin works as specified.
func test_item_base() -> void:
	_check_starting_cabin()
	_check_horn()
	_check_wipers()
	_check_radio()
	_check_cigarettes()
	_check_tea()
	_check_visor_photo()
	_check_slap()
	_check_window()
	_check_through_the_hand()


func _check_starting_cabin() -> void:
	var cigarettes: ItemSim.Item = _sim.items.item(&"cigarettes")
	var tea: ItemSim.Item = _sim.items.item(&"tea_glass")
	if not check(cigarettes != null and tea != null, "the starting cabin holds cigarettes and a tea glass"):
		return
	check_eq(cigarettes.slot, &"ashtray", "the cigarettes sit at the ashtray")
	check_eq(cigarettes.supply, 5, "five of them (GDD 7.3)")
	check_eq(tea.slot, &"cup_a", "the tea glass sits in cup_a")
	check_eq(tea.supply, 3, "full: three sips")
	check(tea.hot_left > 0.0, "and hot")
	check_eq(_sim.items.radio, ItemSim.STATIC, "the radio starts on static")
	check_near(_sim.cash, tuning.f("cash_start"), 0.000001, "he starts with cash_start")
	check_near(_sim.nerves.value, tuning.f("nerves_start"), 0.000001, "and Nerves at nerves_start")


func _check_horn() -> void:
	var range_m: float = tuning.f("horn_range")
	var yield_time: float = tuning.f("horn_yield_time")
	var third: float = tuning.fi("gear_speeds", 2)

	# A car and a taxi ahead in his lane move over; a truck and a minibus do not.
	for type: String in ["car", "taxi", "truck", "minibus", "pickup", "tanker", "tuk_tuk"]:
		_new_sim()
		_cruise(3, 1)
		var ahead: TrafficSim.Vehicle = _sim.traffic.spawn(StringName(type), 1, _sim.car.s + range_m * 0.5, third - 10.0)
		_complete("horn")
		_run(yield_time + 0.1)
		var yields: bool = GameData.as_bool(data.record("vehicles", type).get("yields_to_horn"))
		if yields:
			check(ahead.lane != 1, "a %s within horn_range ahead moves over" % type)
			check_near(ahead.x, _sim.traffic.lane_center(ahead.lane), 0.000001, "and is in the next lane within horn_yield_time")
		else:
			check_eq(ahead.lane, 1, "a %s ignores the horn" % type)
			check_near(ahead.x, _sim.traffic.lane_center(1), 0.000001, "and stays where it is")
	check(GameData.as_bool(data.record("vehicles", "car").get("yields_to_horn")), "cars yield (GDD 4.6)")
	check(GameData.as_bool(data.record("vehicles", "taxi").get("yields_to_horn")), "taxis yield")
	check(not GameData.as_bool(data.record("vehicles", "truck").get("yields_to_horn")), "trucks do not")
	check(not GameData.as_bool(data.record("vehicles", "minibus").get("yields_to_horn")), "buses do not")

	# Beyond horn_range, in another lane, or behind: nothing.
	_new_sim()
	_cruise(3, 1)
	var far: TrafficSim.Vehicle = _sim.traffic.spawn(&"car", 1, _sim.car.s + range_m + 15.0, third)
	var beside: TrafficSim.Vehicle = _sim.traffic.spawn(&"car", 0, _sim.car.s + 20.0, third)
	var behind: TrafficSim.Vehicle = _sim.traffic.spawn(&"car", 1, _sim.car.s - 20.0, third)
	_complete("horn")
	_run(yield_time + 0.1)
	check_eq(far.lane, 1, "a car beyond horn_range does not move")
	check_eq(beside.lane, 0, "a car in another lane does not move")
	check_eq(behind.lane, 1, "a car behind him does not move")

	# Only if the next lane is free.
	_new_sim()
	_cruise(3, 1)
	var boxed: TrafficSim.Vehicle = _sim.traffic.spawn(&"car", 1, _sim.car.s + 20.0, third)
	_sim.traffic.spawn(&"truck", 0, _sim.car.s + 20.0, third)
	_sim.traffic.spawn(&"truck", 2, _sim.car.s + 20.0, third)
	_complete("horn")
	_run(yield_time + 0.1)
	check_eq(boxed.lane, 1, "a car with both next lanes taken stays put")

	# It calms him by horn_nerves, at most once per horn_cooldown.
	_new_sim()
	var before: float = _sim.nerves.value
	_complete("horn")
	check_near(_sim.nerves.value - before, tuning.f("horn_nerves"), 0.000001, "the horn changes Nerves by horn_nerves")
	check(_sim.items.horn_blown, "and is flagged for that tick")
	_run(tuning.f("horn_cooldown") * 0.5)
	before = _sim.nerves.value
	_complete("horn")
	check_near(_sim.nerves.value - before, 0.0, 0.000001, "a second honk within horn_cooldown does not calm him again")
	_run(tuning.f("horn_cooldown") * 0.5 + 0.1)
	before = _sim.nerves.value
	_complete("horn")
	check_near(_sim.nerves.value - before, tuning.f("horn_nerves"), 0.000001, "after horn_cooldown it does")
	check_near(tuning.f("horn_nerves"), -3.0, 0.000001, "GDD 4.6: -3 Nerves")
	check_near(tuning.f("horn_cooldown"), 10.0, 0.000001, "GDD 4.6: at most once per 10 s")


func _check_wipers() -> void:
	_new_sim()
	var clear: float = tuning.f("wiper_clear_time")
	check_near(clear, 6.0, 0.000001, "GDD 4.6: a sweep keeps the rain clear for 6 s")
	_run(clear + 1.0)
	check_near(_sim.items.rain_blur(), 1.0, 0.000001, "with no sweep the view is fully blurred")
	_complete("wipers", Gesture.DIR_UP)
	check_near(_sim.items.rain_blur(), 0.0, 0.000001, "one sweep clears it")
	_run(clear * 0.5)
	check_near(_sim.items.rain_blur(), 0.5, 0.01, "the blur comes back over wiper_clear_time: half at half")
	_run(clear * 0.5)
	check_near(_sim.items.rain_blur(), 1.0, 0.01, "and whole at the end")
	check_near(GameData.as_float(_sim.snapshot()["rain_blur"]), _sim.items.rain_blur(), 0.000001, "the snapshot carries it for the post effect")


func _check_radio() -> void:
	_new_sim()
	var stations: Array = tuning.a("radio_stations")
	check_eq(stations, ["music", "news", "callin"], "the dial holds music, news and the call-in show")
	var ritual: Dictionary = data.record("rituals", "radio_tune")
	check_eq(_sim.items.ritual_at("radio").get("id"), "radio_tune", "the radio anchor offers the dial")

	_sim.items.drag_step(ritual, 1)
	check_eq(_sim.items.radio, &"music", "from static, one step right finds music")
	_sim.items.drag_step(ritual, 1)
	check_eq(_sim.items.radio, &"news", "the next is the news")
	_sim.items.drag_step(ritual, 1)
	check_eq(_sim.items.radio, &"callin", "then the call-in show")
	_sim.items.drag_step(ritual, 1)
	check_eq(_sim.items.radio, &"music", "and round to music again")
	_sim.items.drag_step(ritual, -1)
	check_eq(_sim.items.radio, &"callin", "a step left goes back")

	# Station effects (GDD 6.2), per second.
	check_near(_radio_rate(&"music", false), tuning.f("radio_music_rate"), 0.002, "music changes Nerves by radio_music_rate per second")
	check_near(tuning.f("radio_music_rate"), -0.5, 0.000001, "GDD 6.2: -0.5")
	check_near(_radio_rate(&"news", false), tuning.f("radio_news_rate"), 0.002, "the news changes Nerves by radio_news_rate per second")
	check_near(tuning.f("radio_news_rate"), 0.5, 0.000001, "GDD 6.2: +0.5")
	check(_sim.nerves.awake, "and the news keeps him Awake")
	check_near(_radio_rate(&"callin", false), 0.0, 0.002, "the call-in show has no effect")
	check(not _sim.nerves.awake, "and does not keep him Awake")
	check_near(_radio_rate(ItemSim.STATIC, false), 0.0, 0.002, "static has no effect")
	check_near(_radio_rate(&"music", true), tuning.f("radio_music_rate") * tuning.f("window_radio_mult"), 0.002, "with the window open the radio's effect is halved")

	# Every station drifts to static after radio_drift_time.
	_new_sim()
	_sim.items.drag_step(ritual, 1)
	_run(tuning.f("radio_drift_time") - 0.5)
	check_eq(_sim.items.radio, &"music", "just before radio_drift_time the station still plays")
	_run(1.0)
	check_eq(_sim.items.radio, ItemSim.STATIC, "after radio_drift_time it has drifted to static")
	check_near(tuning.f("radio_drift_time"), 40.0, 0.000001, "GDD 4.6: every 40 s")
	_sim.items.drag_step(ritual, 1)
	check_eq(_sim.items.radio, &"news", "retuning to the right finds the station after the one lost")
	_sim.items.drag_step(ritual, -1)
	check_eq(_sim.items.radio, &"music", "and to the left the one lost")


func _check_cigarettes() -> void:
	var record: Dictionary = data.record("items", "cigarettes")
	var params: Dictionary = GameData.as_dict(record.get("params"))
	var burn: float = _give_duration(record, "lit")
	var ash_by: float = GameData.as_float(params.get("ash_by_s"))
	var lapse: Dictionary = GameData.as_dict(record.get("lapse"))
	check_near(burn, 25.0, 0.000001, "GDD 7.4: lit for 25 s")
	check_near(GameData.as_float(lapse.get("after")), 30.0, 0.000001, "GDD 7.4: the craving comes after 30 s")
	check_near(GameData.as_float(lapse.get("amount")), 8.0, 0.000001, "GDD 7.4: and is +8 Nerves")
	check_near(GameData.as_float(data.record("rituals", "cig_light").get("hold_s")), 1.2, 0.000001, "GDD 7.4: lighting is HOLD 1.2 s")

	_new_sim()
	var pack: ItemSim.Item = _sim.items.item(&"cigarettes")
	check_eq(_sim.items.ritual_at("ashtray").get("id"), "cig_light", "unlit, the ashtray offers lighting")
	_sim.nerves.value = 70.0
	_complete("cig_light")
	check_eq(pack.supply, 4, "lighting uses one cigarette")
	check(_sim.effects.has(&"lit"), "he is smoking")
	_run(0.1)
	check_eq(_sim.items.ritual_at("ashtray").get("id"), "cig_ash", "lit, the ashtray offers ashing")
	check(_sim.nerves.awake, "a lit cigarette keeps him Awake")
	check_near(_sim.nerves.tremor_amplitude, 0.0, 0.000001, "and stops the Tremor, even at Nerves 70")
	check_near(_sim.effects.time_left(&"lit"), burn - 0.1, 0.02, "the burn lasts as long as the item says")

	# -10 Nerves over the burn; +2% haze per second.
	_new_sim()
	_sim.nerves.value = 70.0
	_complete("cig_light")
	_complete("cig_ash", Gesture.DIR_DOWN)
	_run(10.0)
	check_near(_sim.nerves.value, 70.0 - 10.0 * (10.0 / burn), 0.02, "ten seconds in, the cigarette has calmed him by 10 x 10/25")
	check_near(_sim.items.haze, 0.02 * 10.0, 0.005, "and the haze has grown by 2% per second")
	_run(burn - 10.0 + 0.2)
	check(not _sim.effects.has(&"lit"), "after the burn it is out")
	check_near(_sim.nerves.value, 60.0, 0.03, "having calmed him by 10 in all")
	check_near(_sim.items.haze, 0.02 * burn, 0.01, "the haze reached 2% x the burn")
	var haze_after: float = _sim.items.haze
	_run(5.0)
	check_near(haze_after - _sim.items.haze, tuning.f("haze_clear_rate") * 5.0, 0.005, "afterwards the haze clears at haze_clear_rate")
	check_near(tuning.f("haze_clear_rate"), 0.03, 0.000001, "GDD 7.4: 3% per second")

	# Haze never passes haze_cap.
	_new_sim()
	_sim.items.haze = tuning.f("haze_cap") - 0.01
	_complete("cig_light")
	_run(5.0)
	check_near(_sim.items.haze, tuning.f("haze_cap"), 0.000001, "haze stops at haze_cap")
	check_near(GameData.as_float(_sim.snapshot()["haze"]), tuning.f("haze_cap"), 0.000001, "the snapshot carries it for the post effect")

	# Ash: once, before ash_by_s, or it falls.
	_new_sim()
	_complete("cig_light")
	_run(ash_by - 0.5)
	var before: float = _sim.nerves.value
	_run(1.0)
	check_near(_sim.nerves.value - before, GameData.as_float(params.get("ash_nerves")) - 10.0 / burn, 0.02, "left unashed, the ash falls at ash_by_s: +5 Nerves")
	before = _sim.nerves.value
	_run(burn - ash_by)
	check(_sim.nerves.value - before < 0.0, "it falls once, not again")

	_new_sim()
	_complete("cig_light")
	_run(ash_by * 0.5)
	_complete("cig_ash", Gesture.DIR_LEFT)
	before = _sim.nerves.value
	_run(ash_by)
	check(_sim.nerves.value - before < 0.0, "ashed in time, no ash falls")

	# Craving: +8 once if another is not lit within 30 s of the last.
	_new_sim()
	_complete("cig_light")
	_complete("cig_ash", Gesture.DIR_DOWN)
	_run(burn + 0.2)
	var after: float = GameData.as_float(lapse.get("after"))
	_run(after - 1.0)
	before = _sim.nerves.value
	_run(1.5)
	check_near(_sim.nerves.value - before, GameData.as_float(lapse.get("amount")), 0.000001, "30 s after the last one with none lit: the craving, +8 Nerves")
	before = _sim.nerves.value
	_run(after * 2.0)
	check_near(_sim.nerves.value - before, 0.0, 0.000001, "once")

	_new_sim()
	_complete("cig_light")
	_complete("cig_ash", Gesture.DIR_DOWN)
	_run(burn + 0.2)
	_run(after * 0.5)
	_complete("cig_light")
	_complete("cig_ash", Gesture.DIR_DOWN)
	before = _sim.nerves.value
	_run(after)
	check(_sim.nerves.value - before < 0.0, "lighting another within 30 s: no craving")

	# No craving before the first cigarette of the Telling.
	_new_sim()
	before = _sim.nerves.value
	_run(after * 2.0)
	check_near(_sim.nerves.value - before, 0.0, 0.000001, "he does not crave before he has smoked")

	# Cannot light a second while one is lit; cannot light from an empty pack.
	_new_sim()
	_complete("cig_light")
	var offered: String = GameData.as_string(_sim.items.ritual_at("ashtray").get("id"))
	check(offered != "cig_light", "while one is lit he cannot light another")
	_new_sim()
	_sim.items.item(&"cigarettes").supply = 0
	check(_sim.items.ritual_at("ashtray").is_empty(), "an empty pack offers nothing")


func _check_tea() -> void:
	var record: Dictionary = data.record("items", "tea_glass")
	var hot_for: float = GameData.as_float(GameData.as_dict(record.get("params")).get("hot_for_s"))
	check_near(hot_for, 40.0, 0.000001, "GDD 7.4: the tea is cold after 40 s")
	check_near(GameData.as_float(data.record("rituals", "tea_sip").get("hold_s")), 0.6, 0.000001, "GDD 7.4: a sip is HOLD 0.6 s")

	# A hot sip.
	_new_sim()
	var glass: ItemSim.Item = _sim.items.item(&"tea_glass")
	_sim.nerves.value = 60.0
	check_eq(_sim.items.ritual_at("cup_a").get("id"), "tea_sip", "the cup offers a sip")
	_complete("tea_sip")
	check_near(_sim.nerves.value, 60.0 - 12.0, 0.000001, "a hot sip is -12 Nerves")
	check_eq(glass.supply, 2, "and one sip fewer")
	check_near(_sim.effects.time_left(&"awake"), 40.0, 0.000001, "with Awake for 40 s")

	# A cold sip.
	_new_sim()
	glass = _sim.items.item(&"tea_glass")
	_run(hot_for - 0.5)
	check(glass.hot_left > 0.0, "just before 40 s the tea is still hot")
	_run(1.0)
	check_eq(glass.hot_left, 0.0, "after 40 s it is cold")
	_sim.nerves.value = 60.0
	_complete("tea_sip")
	check_near(_sim.nerves.value, 60.0 - 3.0, 0.000001, "a cold sip is -3 Nerves")
	check(not _sim.effects.has(&"awake"), "and gives no Awake")
	var shown: Array[Dictionary] = _sim.snapshot()["items"]
	check_eq(shown[1]["hot"], false, "the snapshot shows the tea is cold")

	# Three sips, then nothing.
	_new_sim()
	glass = _sim.items.item(&"tea_glass")
	for _sip: int in 3:
		_complete("tea_sip")
	check_eq(glass.supply, 0, "three sips empty the glass")
	check(_sim.items.ritual_at("cup_a").is_empty(), "an empty glass offers nothing")

	# It spills in a crash, not in a scrape.
	_new_sim()
	glass = _sim.items.item(&"tea_glass")
	_sim.items.on_hit(Collision.Hit.SCRAPE)
	check_eq(glass.supply, 3, "a scrape does not spill the tea")
	_sim.items.on_hit(Collision.Hit.CRASH)
	check_eq(glass.supply, 0, "a crash spills it")

	# Through a real crash.
	_new_sim()
	_cruise(3, 1)
	glass = _sim.items.item(&"tea_glass")
	_sim.traffic.spawn(&"truck", 1, _sim.car.s + 30.0, tuning.fi("gear_speeds", 2) - 50.0)
	for _tick: int in int(10.0 / DT):
		_sim.car.x = _sim.car.lane_center(1)
		_sim.step(_input)
		if _sim.collision.hit != Collision.Hit.NONE:
			break
	check_eq(_sim.collision.hit, Collision.Hit.CRASH, "driving into a slow truck is a crash")
	check_eq(glass.supply, 0, "and the tea is on the floor")


func _check_visor_photo() -> void:
	_new_sim()
	check_near(tuning.f("visor_nerves"), -20.0, 0.000001, "GDD 4.6: the photo is -20 Nerves")
	check_near(tuning.f("visor_time"), 3.0, 0.000001, "GDD 4.6: the visor stays down 3 s")
	_sim.nerves.value = 60.0
	_complete("visor_photo", Gesture.DIR_DOWN)
	check_near(_sim.nerves.value, 60.0 + tuning.f("visor_nerves"), 0.000001, "flipping the visor down shows the photo: visor_nerves")
	check(_sim.effects.has(&"visor_down"), "the visor is down")
	check_eq(_sim.snapshot()["visor_down"], true, "the snapshot shows it (it blocks the top of the view)")
	_run(tuning.f("visor_time") - 0.2)
	check(_sim.effects.has(&"visor_down"), "it stays down for visor_time")
	_run(0.4)
	check(not _sim.effects.has(&"visor_down"), "and goes back up")

	# Once per leg.
	_sim.nerves.value = 60.0
	_complete("visor_photo", Gesture.DIR_DOWN)
	check_near(_sim.nerves.value, 60.0, 0.000001, "a second look in the same leg does not calm him")
	check(_sim.effects.has(&"visor_down"), "though the visor still comes down against the sun")
	_sim.items.begin_leg()
	_complete("visor_photo", Gesture.DIR_DOWN)
	check_near(_sim.nerves.value, 60.0 + tuning.f("visor_nerves"), 0.000001, "in the next leg it does again")


func _check_slap() -> void:
	_new_sim()
	_sim.nerves.value = 20.0
	_complete("slap")
	check_near(_sim.nerves.value, 32.0, 0.000001, "a slap is +12 Nerves")
	check_near(_sim.effects.time_left(&"awake"), 20.0, 0.000001, "and Awake for 20 s")
	check_eq(_sim.items.ritual_at("face").get("id"), "slap", "his face offers the slap")


func _check_window() -> void:
	_new_sim()
	check(not _sim.items.flag(&"window_open"), "the window starts closed")
	_complete("window_crank")
	check(_sim.items.flag(&"window_open"), "cranking opens it")
	check_near(_sim.effects.time_left(&"awake"), tuning.f("window_awake"), 0.000001, "opening gives Awake for window_awake")
	var shown_flags: Dictionary = _sim.snapshot()["flags"]
	check_eq(shown_flags.get(&"window_open"), true, "the snapshot shows the open window")
	check_near(GameData.as_float(data.record("rituals", "window_crank").get("turns")), 3.0, 0.000001, "GDD 4.6: CRANK(3)")

	# While open: haze clears window_haze_clear_mult times faster.
	_sim.items.haze = 0.5
	_run(2.0)
	check_near(0.5 - _sim.items.haze, tuning.f("haze_clear_rate") * tuning.f("window_haze_clear_mult") * 2.0, 0.005, "while it is open, haze clears three times faster")

	# Closing: no Awake.
	_run(tuning.f("window_awake"))
	_complete("window_crank")
	check(not _sim.items.flag(&"window_open"), "cranking again closes it")
	check(not _sim.effects.has(&"awake"), "closing gives no Awake")
	_sim.items.haze = 0.5
	_run(2.0)
	check_near(0.5 - _sim.items.haze, tuning.f("haze_clear_rate") * 2.0, 0.005, "closed, haze clears at the plain rate")


## The same rituals reached and performed by the hand, from the wheel.
func _check_through_the_hand() -> void:
	_new_sim()
	_sim.nerves.value = 60.0
	var pack: ItemSim.Item = _sim.items.item(&"cigarettes")

	# Light a cigarette: reach, HOLD 1.2 s.
	_aim(&"ashtray")
	_steps(60)
	check_eq(_sim.hand.at_id(), &"ashtray", "the hand reaches the ashtray")
	_input.lmb = true
	_steps(int(1.0 / DT))
	check(not _sim.effects.has(&"lit"), "a second of holding is not enough")
	_steps(int(0.3 / DT))
	check(_sim.effects.has(&"lit"), "1.2 s of holding lights it")
	check_eq(pack.supply, 4, "one cigarette used")
	_input.lmb = false
	_steps(5)

	# Ash it: FLICK.
	_input.pointer_is_absolute = false
	_input.lmb = true
	_input.pointer_delta = Vector2(0.0, 7.0)
	_steps(10)
	_input.pointer_delta = Vector2.ZERO
	_input.lmb = false
	_steps(5)
	check(pack.ashed, "a flick at the ashtray ashes it")

	# Sip the tea: reach, HOLD 0.6 s.
	_aim(&"cup_a")
	_steps(60)
	_input.lmb = true
	_steps(int(0.7 / DT))
	_input.lmb = false
	_steps(5)
	check_eq(_sim.items.item(&"tea_glass").supply, 2, "holding at the cup for 0.6 s is a sip")

	# Tune the radio: DRAG the dial two steps to the right.
	_aim(&"radio")
	_steps(60)
	_input.pointer_is_absolute = false
	_input.lmb = true
	_input.pointer_delta = Vector2(tuning.f("radio_step_px") * 2.2 / 20.0, 0.0)
	_steps(20)
	_input.pointer_delta = Vector2.ZERO
	_input.lmb = false
	_steps(5)
	check_eq(_sim.items.radio, &"news", "dragging the dial two steps right finds the news")
	check_eq(_sim.hand.at_id(), &"radio", "the hand stayed on the dial")

	# Slap: his own face.
	_sim.nerves.value = 20.0
	_aim(&"face")
	_steps(80)
	_input.lmb = true
	_steps(4)
	_input.lmb = false
	_steps(10)
	check(_sim.nerves.value > 31.0, "a click at his face is a slap")

	# Anchors with nothing to do are not offered to the hand.
	var pocket: int = _sim.hand.anchor_index(&"pocket")
	check(not _sim.hand.is_anchor_active(pocket), "an anchor with nothing to do does not attract the hand")
	check(_sim.hand.is_anchor_active(_sim.hand.anchor_index(&"cup_a")), "an anchor with an item does")
	check(not _sim.hand.is_anchor_active(_sim.hand.anchor_index(&"cup_b")), "an empty cup holder does not")


# --- Helpers ------------------------------------------------------------------

func _new_sim() -> void:
	_sim = DriveSim.new(fresh_data())
	_sim.in_encounter = _quiet


func _cruise(gear: int, lane: int) -> void:
	_sim.gate.reset(gear)
	_sim.car.reset(lane, gear)


## Completes a ritual as if its gesture had just been made.
func _complete(ritual_id: String, direction: int = 0) -> void:
	_sim.items.complete(data.record("rituals", ritual_id), direction)


func _run(seconds: float) -> void:
	for _tick: int in roundi(seconds / DT):
		_sim.car.x = _sim.car.lane_center(_sim.car.lane_of(_sim.car.x))
		_sim.step(_input)


func _steps(count: int) -> void:
	for _tick: int in count:
		_sim.car.x = _sim.car.lane_center(1)
		_sim.step(_input)


func _aim(anchor: StringName) -> void:
	_input.clear()
	_input.pointer_is_absolute = true
	_input.pointer = _sim.hand.anchor_pointer(_sim.hand.anchor_index(anchor))


func _give_duration(item: Dictionary, effect: String) -> float:
	for give: Variant in GameData.as_array(item.get("gives")):
		var entry: Dictionary = GameData.as_dict(give)
		if entry.get("effect") == effect:
			return GameData.as_float(entry.get("duration"))
	return 0.0


## Nerves per second with the radio on a station (window open or closed).
func _radio_rate(station: StringName, window_open: bool) -> float:
	_new_sim()
	var ritual: Dictionary = data.record("rituals", "radio_tune")
	var stations: Array = tuning.a("radio_stations")
	if station != ItemSim.STATIC:
		for _step: int in stations.find(String(station)) + 1:
			_sim.items.drag_step(ritual, 1)
	if window_open:
		_sim.items.flags[&"window_open"] = true
	_run(0.1)
	var start: float = _sim.nerves.value
	_run(1.0)
	return _sim.nerves.value - start
