extends CabinSuite
## M6: the synergies of GDD 7.8: what two things in the cabin do together.


## T-SYN-TEA-CIGARETTES: Tea + Cigarettes (7.8): a sip while lit makes that
## cigarette burn 10 s longer.
func test_syn_tea_cigarettes() -> void:
	var synergy: Dictionary = _synergy("cigarettes", "tea_glass")
	var longer: float = GameData.as_float(synergy.get("amount"))
	var burn: float = _give_duration("cigarettes", "lit")
	var light_s: float = GameData.as_float(_ritual("cig_light").get("hold_s"))
	var sip_s: float = GameData.as_float(_ritual("tea_sip").get("hold_s"))
	check_eq(GameData.as_string(synergy.get("rule")), "sip_extends_burn", "cigarettes and tea have a synergy")
	check_near(longer, 10.0, 0.000001, "of 10 s")

	# A sip while lit: that cigarette burns 10 s longer.
	_new_sim()
	_hold_at("ashtray", light_s)
	_flick(Vector2(0.0, tuning.f("flick_min_distance") * 1.5))
	_reach("cup_a")
	var before: float = _sim.effects.time_left(&"lit")
	_hold(sip_s)
	var spent: float = sip_s + float(SETTLE + 1) * DT
	check_near(_sim.effects.time_left(&"lit"), before - spent + longer, 0.000001, "a sip while lit: the cigarette has 10 s more to burn")
	var haze_before: float = _sim.items.haze
	_run(_sim.effects.time_left(&"lit") - 0.5)
	check(_sim.effects.has(&"lit"), "it burns on to the end of the longer time")
	check(_sim.items.haze > haze_before, "clouding the glass as it goes")
	_run(1.0)
	check(not _sim.effects.has(&"lit"), "and then goes out")
	# In all: 25 s and 10 more.
	check_near(float(_sim.tick) * DT, light_s + burn + longer, 1.5, "(35 s after he lit it, give or take the reaches)")

	# Each sip counts.
	_new_sim()
	_hold_at("ashtray", light_s)
	_flick(Vector2(0.0, tuning.f("flick_min_distance") * 1.5))
	_reach("cup_a")
	before = _sim.effects.time_left(&"lit")
	_hold(sip_s)
	_hold(sip_s)
	check_near(_sim.effects.time_left(&"lit"), before - 2.0 * spent + 2.0 * longer, 0.000001, "a second sip adds 10 s more")

	# Unlit, a sip lights nothing and lengthens nothing.
	_new_sim()
	_hold_at("cup_a", sip_s)
	check(not _sim.effects.has(&"lit"), "with nothing lit a sip is only a sip")
	_hold_at("ashtray", light_s)
	check_near(_sim.effects.time_left(&"lit"), burn - float(SETTLE + 1) * DT, 0.000001, "and the next cigarette burns its plain 25 s")

	# The calm of the cigarette is still 10 in all.
	_new_sim()
	_sim.nerves.set_value(90.0)
	_hold_at("ashtray", light_s)
	_flick(Vector2(0.0, tuning.f("flick_min_distance") * 1.5))
	_hold_at("cup_a", sip_s)
	_run(burn + longer + 1.0)
	check_near(_sim.nerves.value, 90.0 + _give_amount("cigarettes", "nerves") + _give_amount("tea_glass", "nerves", "hot"), 0.01, "the longer burn calms no more than a cigarette does")


## T-SYN-CIGARETTES-FRESHENER: Cigarettes + Air freshener (7.8): no Haze
## from smoke.
func test_syn_cigarettes_freshener() -> void:
	var synergy: Dictionary = _synergy("cigarettes", "air_freshener")
	var light_s: float = GameData.as_float(_ritual("cig_light").get("hold_s"))
	check_eq(GameData.as_string(synergy.get("rule")), "no_smoke_haze", "cigarettes and the air freshener have a synergy")

	_new_sim()
	_hold_at("ashtray", light_s)
	_run(5.0)
	check(_sim.items.haze > 0.05, "(without the freshener a cigarette clouds the glass)")
	_new_sim()
	_give("air_freshener")
	_hold_at("ashtray", light_s)
	check(_sim.effects.has(&"lit"), "(he smokes)")
	_run(5.0)
	check_near(_sim.items.haze, 0.0, 0.000001, "with the freshener hanging there, smoke makes no Haze")
	_run(_sim.effects.time_left(&"lit") + 1.0)
	check_near(_sim.items.haze, 0.0, 0.000001, "not to the end of the burn")
	# Other Haze is still Haze.
	_begin_quiet_leg("open_road", 2, 5)
	_give("air_freshener")
	_sim.items.dust_rate = 0.01
	_sim.items.flags[&"window_open"] = true
	_run(5.0)
	check(_sim.items.haze > 0.03, "dust through an open window still clouds it")
	# Taken down, the smoke is back.
	_new_sim()
	_give("air_freshener")
	_hold_at("ashtray", light_s)
	_sim.items.remove_item(_item("air_freshener"))
	_run(5.0)
	check(_sim.items.haze > 0.05, "without it the same cigarette clouds the glass again")


## T-SYN-BEADS-MUSIC: Beads + music, radio or tape (7.8): each bead is -4
## Nerves.
func test_syn_beads_music() -> void:
	var synergy: Dictionary = _synergy("beads", "music")
	var plain: float = _give_amount("beads", "nerves")
	var with_music: float = GameData.as_float(synergy.get("amount"))
	check_eq(GameData.as_string(synergy.get("rule")), "bead_calm", "beads and music have a synergy")
	check_near(with_music, -4.0, 0.000001, "each bead is -4 Nerves")
	check(with_music < plain, "(more than a bead's own -2)")

	# The radio on music.
	_new_sim()
	_give("beads")
	_reach("mirror")
	_sim.nerves.set_value(90.0)
	_tap()
	check_near(_sim.nerves.value, 90.0 + plain, 0.000001, "(in silence a bead is -2)")
	_tune_to("music")
	_reach("mirror")
	_sim.nerves.set_value(90.0)
	_tap()
	check_near(_bead_drop(90.0), with_music, 0.000001, "with music on the radio a bead is -4")
	# Not the news, not the call-in show, not static.
	for station: String in ["news", "callin"]:
		_tune_to(station)
		_reach("mirror")
		_sim.nerves.set_value(90.0)
		_tap()
		check_near(_bead_drop(90.0), plain, 0.000001, "with the %s on it is -2" % station)
	_tune_to("music")
	_run(tuning.f("radio_drift_time") + 1.0)
	check_eq(_sim.items.radio, ItemSim.STATIC, "(the station has drifted to static)")
	_reach("mirror")
	_sim.nerves.set_value(90.0)
	_tap()
	check_near(_bead_drop(90.0), plain, 0.000001, "when the music has drifted to static a bead is -2 again")

	# The tape.
	_new_sim()
	_give("beads")
	var tape: ItemSim.Item = _give("mixtape")
	_reach("mirror")
	_run(1.0)
	_sim.nerves.set_value(90.0)
	_tap()
	check_near(_bead_drop(90.0), with_music, 0.000001, "with the tape playing a bead is -4")
	_run(GameData.as_float(_params("mixtape").get("side_s")) - tape.side_time + 1.0)
	check(not _sim.effects.has(&"music"), "(the tape warbles)")
	_sim.nerves.set_value(50.0)
	_tap()
	check_near(_bead_drop(50.0), plain, 0.000001, "a warbling tape is not music: -2")


## T-SYN-FLASK-PHOTO: Flask + Photo (7.8): looking at the photo with Courage
## gives -40 Nerves, and all stacks are lost.
func test_syn_flask_photo() -> void:
	var synergy: Dictionary = _synergy("arak_flask", "photo")
	var calm: float = GameData.as_float(synergy.get("amount"))
	var sip_s: float = GameData.as_float(_ritual("flask_sip").get("hold_s"))
	var sip_calm: float = _give_amount("arak_flask", "nerves")
	check_eq(GameData.as_string(synergy.get("rule")), "photo_sobers", "the flask and the photo have a synergy")
	check_near(calm, -40.0, 0.000001, "-40 Nerves")

	# Sober, the photo is its -20.
	_new_sim()
	_give("arak_flask")
	var cup: String = _anchor_of("arak_flask")
	_sim.nerves.set_value(90.0)
	_look_at_photo()
	check_near(_sim.nerves.value, 90.0 + tuning.f("visor_nerves"), 0.000001, "(sober, the photo is -20)")

	# With Courage: -40, and all stacks are lost.
	_new_sim()
	_give("arak_flask")
	_hold_at(cup, sip_s)
	_hold(sip_s)
	check_eq(_sim.courage(), 2, "(two sips: 2 stacks)")
	_sim.nerves.set_value(90.0)
	_look_at_photo()
	check_near(_sim.nerves.value, 90.0 + calm, 0.000001, "looking at the photo with Courage gives -40 Nerves")
	check_eq(_sim.courage(), 0, "and all stacks are lost")
	check(_sim.effects.has(&"visor_down"), "(the visor is down as ever)")
	_run(1.0)
	check_near(_sim.wheel.lag, 0.0, 0.000001, "with them the Lag")
	check_near(GameData.as_float(_sim.snapshot()["sway"]), 0.0, 0.000001, "and the Sway")

	# Once per leg, like the photo itself; but the Courage goes every time.
	_run(tuning.f("visor_time") + 0.5)
	_hold_at(cup, sip_s)
	check_eq(_sim.courage(), 1, "(another sip)")
	_sim.nerves.set_value(90.0)
	_look_at_photo()
	check_near(_sim.nerves.value, 90.0, 0.000001, "a second look in the same leg calms nothing")
	check_eq(_sim.courage(), 0, "but takes the Courage all the same")

	# Without the flask in the car there is no such synergy.
	_new_sim()
	_give("arak_flask")
	_hold_at(cup, sip_s)
	_sim.items.remove_item(_item("arak_flask"))
	_sim.nerves.set_value(90.0)
	_look_at_photo()
	check_near(_sim.nerves.value, 90.0 + tuning.f("visor_nerves"), 0.000001, "the flask gone, the photo is its plain -20")
	check_eq(_sim.courage(), 1, "and the Courage he has stays")
	check(sip_calm < 0.0, "(a sip calms too)")


## T-SYN-FLASK-PAINKILLERS: Flask + Painkillers (7.8): Lag doubles and
## close-call cash doubles.
func test_syn_flask_painkillers() -> void:
	var synergy: Dictionary = _synergy("arak_flask", "painkillers")
	var double: float = GameData.as_float(synergy.get("amount"))
	var sip_s: float = GameData.as_float(_ritual("flask_sip").get("hold_s"))
	var pill_s: float = GameData.as_float(_ritual("painkillers_take").get("hold_s"))
	var lag: float = tuning.f("lag_per_source") * 0.001
	var cash_up: float = GameData.as_float(data.record("effects", "courage").get("close_call_cash_per_stack"))
	var base: float = tuning.f("close_call_base_cash") * tuning.fi("gear_cash_mult", 2)
	check_eq(GameData.as_string(synergy.get("rule")), "numb_courage", "the flask and the painkillers have a synergy")
	check_near(double, 2.0, 0.000001, "that doubles")

	_new_sim()
	_give("arak_flask")
	_give("painkillers")
	var cup: String = _anchor_of("arak_flask")
	# Courage alone.
	_hold_at(cup, sip_s)
	_tick()
	check_near(_sim.wheel.lag, lag, 0.000001, "(one stack: 40 ms of Lag)")
	_pass_closely("truck", tuning.f("close_call_min_closing") + 10.0)
	check_near(GameData.as_float(_event("close_call").get("cash")), base * (1.0 + cash_up), 0.000001, "(and close calls at +50%)")
	# Courage on top of a pill.
	_hold_at("face", pill_s)
	_tick()
	check(_sim.courage() == 1 and _sim.effects.has(&"painkillers"), "(Courage, and a pill working)")
	check_near(_sim.wheel.lag, lag * double, 0.000001, "with a pill working the Lag doubles")
	_run(tuning.f("chain_window") + 0.5)
	_pass_closely("truck", tuning.f("close_call_min_closing") + 10.0)
	check_near(GameData.as_float(_event("close_call").get("cash")), base * (1.0 + cash_up) * double, 0.000001, "and close-call cash doubles")
	# The pills alone do neither.
	_run(GameData.as_float(_give_duration("arak_flask", "courage")))
	_hold_at("face", pill_s)
	_tick()
	check(_sim.courage() == 0 and _sim.effects.has(&"painkillers"), "(sober, a pill working)")
	check_near(_sim.wheel.lag, 0.0, 0.000001, "sober, the pills make no Lag")
	_run(tuning.f("chain_window") + 0.5)
	_pass_closely("truck", tuning.f("close_call_min_closing") + 10.0)
	check_near(GameData.as_float(_event("close_call").get("cash")), base, 0.000001, "and pay nothing more")
	# When the pill wears off, Courage is single again.
	_hold_at(cup, sip_s)
	_run(GameData.as_float(_give_duration("painkillers", "painkillers")) - 30.0)
	_hold_at(cup, sip_s)
	_run(31.0)
	check(_sim.courage() > 0 and not _sim.effects.has(&"painkillers"), "(Courage, the pill worn off)")
	check_near(_sim.wheel.lag, lag * float(_sim.courage()), 0.000001, "the pill worn off, the Lag is single again")
	# The Lag never passes its cap.
	check(lag * 3.0 * double > tuning.f("lag_cap") * 0.001, "(three stacks doubled would be 240 ms)")
	_new_sim()
	_give("arak_flask")
	_give("painkillers")
	for _sip: int in 3:
		_hold_at(cup, sip_s)
	_hold_at("face", pill_s)
	_tick()
	check_eq(_sim.courage(), 3, "(three stacks and a pill)")
	check_near(_sim.wheel.lag, tuning.f("lag_cap") * 0.001, 0.000001, "the Lag stops at its cap: 200 ms")


## T-SYN-PHONE-TAXI-SIGN: Phone + Taxi sign (7.8): three calls answered in a
## row pay a 20 cash bonus.
func test_syn_phone_taxi_sign() -> void:
	var synergy: Dictionary = _synergy("phone", "taxi_sign")
	var bonus: float = GameData.as_float(synergy.get("amount"))
	var every: int = GameData.as_int(synergy.get("every"))
	var params: Dictionary = _params("phone")
	var taps: int = GameData.as_int(params.get("answer_taps"))
	var pay: float = GameData.as_float(params.get("dispatcher_cash"))
	var sign_pay: float = 0.0
	for give: Variant in GameData.as_array(_record("taxi_sign").get("gives")):
		if GameData.as_string(GameData.as_dict(give).get("passive")) == "call_cash_bonus":
			sign_pay = GameData.as_float(GameData.as_dict(give).get("amount"))
	check_eq(GameData.as_string(synergy.get("rule")), "calls_in_a_row", "the phone and the taxi sign have a synergy")
	check_eq(every, 3, "three calls answered in a row")
	check_near(bonus, 20.0, 0.000001, "pay a 20 cash bonus")

	# With the sign: the third answered in a row pays the bonus.
	_new_sim()
	_give("phone")
	_give("taxi_sign")
	_reach(_anchor_of("phone"))
	for call: int in every:
		_await_ring()
		var cash: float = _sim.cash
		for _index: int in taps:
			_tap()
		var paid: float = _sim.cash - cash
		if call < every - 1:
			check_near(paid, pay + sign_pay, 0.000001, "call %d answered: its pay" % (call + 1))
		else:
			check_near(paid, pay + sign_pay + bonus, 0.000001, "the third answered in a row pays 20 more")
	# A missed call breaks the row.
	_new_sim()
	_give("phone")
	_give("taxi_sign")
	_reach(_anchor_of("phone"))
	var paid_out: PackedFloat64Array = PackedFloat64Array()
	for call: int in every + 2:
		_await_ring()
		var cash: float = _sim.cash
		if call == 1:
			while _sim.items.caller != &"":
				_tick()
		else:
			for _index: int in taps:
				_tap()
		paid_out.append(_sim.cash - cash)
	check_near(paid_out[1], 0.0, 0.000001, "(the second call rings out)")
	check_near(paid_out[3], 0.0, 0.000001, "(the fourth is Um Noor: no cash, but answered)")
	check_near(paid_out[2], pay + sign_pay, 0.000001, "after a missed call the row starts again: no bonus two calls later")
	check_near(paid_out[4], pay + sign_pay + bonus, 0.000001, "the bonus comes with the third answered since")

	# Without the sign there is no bonus.
	_new_sim()
	_give("phone")
	_reach(_anchor_of("phone"))
	for call: int in every:
		_await_ring()
		var cash: float = _sim.cash
		for _index: int in taps:
			_tap()
		check_near(_sim.cash - cash, pay, 0.000001, "without the sign call %d pays 10 and no more" % (call + 1))


## T-SYN-SEEDS-TEA: Seeds + Tea (7.8): the tea does not go cold while he
## chews.
func test_syn_seeds_tea() -> void:
	var synergy: Dictionary = _synergy("seeds", "tea_glass")
	var hot_for: float = GameData.as_float(_params("tea_glass").get("hot_for_s"))
	var chew_for: float = _give_duration("seeds", "chewing")
	check_eq(GameData.as_string(synergy.get("rule")), "chewing_keeps_warm", "seeds and tea have a synergy")

	_new_sim()
	_give("seeds")
	var glass: ItemSim.Item = _item("tea_glass")
	var dash: String = _anchor_of("seeds")
	_run(5.0)
	check_near(glass.hot_left, hot_for - 5.0, 0.000001, "(not chewing, the tea cools)")
	_tap_at(dash)
	var at_chew: float = glass.hot_left
	_run(10.0)
	check(_sim.effects.has(&"chewing"), "(he chews)")
	check_near(glass.hot_left, at_chew, 0.02, "while he chews the tea does not go cold")
	_run(_sim.effects.time_left(&"chewing") + 0.1)
	var after_chew: float = glass.hot_left
	check_near(after_chew, at_chew, 0.2, "not for the whole handful")
	_run(5.0)
	check_near(glass.hot_left, after_chew - 5.0, 0.000001, "when the handful is gone it cools again")
	# Chewing on and on, it is still hot long after it would have been cold.
	_new_sim()
	_give("seeds")
	glass = _item("tea_glass")
	_reach(dash)
	for _handful: int in 4:
		_tap()
		_run(chew_for - 0.1)
	check(float(_sim.tick) * DT > hot_for + 20.0, "(80 s on)")
	check(glass.hot_left > 0.0, "handful after handful, the tea is still hot")
	# Without the seeds in the car, chewing is not his to do, and the tea cools.
	_new_sim()
	glass = _item("tea_glass")
	_run(hot_for + 1.0)
	check_eq(glass.hot_left, 0.0, "with no seeds the tea goes cold in its 40 s")


# --- Helpers -----------------------------------------------------------------

## The synergy an item has with a partner ({} when it has none).
func _synergy(item_id: String, with: String) -> Dictionary:
	for listed: Variant in GameData.as_array(_record(item_id).get("synergies")):
		var synergy: Dictionary = GameData.as_dict(listed)
		if GameData.as_string(synergy.get("with")) == with:
			return synergy
	return {}


## The radio's dial turned by the hand until it is on a station.
func _tune_to(station: String) -> void:
	_reach("radio")
	var guard: int = 12
	while String(_sim.items.radio) != station and guard > 0:
		guard -= 1
		_input.pointer_is_absolute = false
		_input.lmb = true
		# One step of the dial (the tick the button goes down does not count).
		_input.pointer_delta = Vector2(tuning.f("radio_step_px") * 1.5 / 10.0, 0.0)
		_ticks(11)
		_input.pointer_delta = Vector2.ZERO
		_input.lmb = false
		_ticks(SETTLE)
	check_eq(String(_sim.items.radio), station, "(the radio is on %s)" % station)
	_run(0.1)


## What the last bead did to his Nerves, the station's own rate over the
## tap's few ticks taken out.
func _bead_drop(from: float) -> float:
	var rate: float = 0.0
	if _sim.items.radio == &"music":
		rate = tuning.f("radio_music_rate")
	elif _sim.items.radio == &"news":
		rate = tuning.f("radio_news_rate")
	var tape: ItemSim.Item = _sim.items.tape()
	if tape != null:
		rate = -1.0 if not _sim.items.warbling(tape) else 0.5
	return _sim.nerves.value - from - rate * float(TAP_TICKS + SETTLE) * DT


## Flips the visor down: FLICK down at the visor.
func _look_at_photo() -> void:
	_reach("visor")
	_flick(Vector2(0.0, tuning.f("flick_min_distance") * 1.5))


## Steps until the phone rings.
func _await_ring() -> bool:
	var guard: int = _ticks_in(GameData.as_float(GameData.as_array(_params("phone").get("call_gap_s"))[1]) + 10.0)
	while _sim.items.caller == &"" and guard > 0:
		guard -= 1
		_tick()
	return _sim.items.caller != &""
