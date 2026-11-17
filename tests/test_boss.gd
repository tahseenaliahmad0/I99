extends CabinSuite
## The set pieces that end the acts (GDD 10.2 to 10.5).

const KMH_TO_MS: float = 1.0 / 3.6
const STORM: String = "storm"


func _storm() -> Dictionary:
	return GameData.as_dict(data.record("bosses", STORM).get("storm"))


# --- T-BOSS-02: the Storm (GDD 10.3) -----------------------------------------

func test_boss_02() -> void:
	_check_storm_is_measured_by_distance()
	_check_storm_dust_rhythm()
	_check_storm_gusts("")
	_check_storm_haze()
	_check_storm_standing()
	_check_storm_cramp()
	_check_storm_modifiers()
	_check_storm_tail_lights()
	_check_storm_in_a_telling()


## 2,000 m, by distance: a car that stands for longer than the whole drive
## takes is no nearer the end for it.
func _check_storm_is_measured_by_distance() -> void:
	var record: Dictionary = data.record("bosses", STORM)
	var length: float = GameData.as_float(record.get("length_m"))
	check_near(length, 2000.0, 0.000001, "GDD 10.3: the Storm is 2,000 m")
	check_eq(GameData.as_int(record.get("act")), 2, "it ends Act 2")
	check_near(GameData.as_float(record.get("par_s")), 100.0, 0.000001, "its par is 100 s")

	var plan: Dictionary = _begin_quiet_boss(STORM)
	check_near(GameData.as_float(plan.get("length")), length, 0.000001, "the Storm's road is as long as its record says")
	check_eq(_sim.boss.kind, STORM, "he is in the Storm")
	check_eq(GameData.as_string(_sim.snapshot()["boss"]), STORM, "(the snapshot says so)")
	# Straight through in third gear.
	var guard: int = _ticks_in(200.0)
	while _event("boss_ended").is_empty() and guard > 0:
		guard -= 1
		_tick()
	var through: float = _sim.seconds()
	check(not _event("boss_ended").is_empty(), "the Storm ends")
	check(_sim.car.s >= length and _sim.car.s < length + 1.0, "at 2,000 m (ended at %.2f m)" % _sim.car.s)
	check_near(through, length / (tuning.fi("gear_speeds", 2) * KMH_TO_MS), 0.1, "which third gear reaches in 72 s")
	check(not _sim.boss.active, "and then he is out of it")
	check(is_inf(_sim.visibility()), "(the dust is behind him)")
	_wipe()
	check_near(_sim.items.haze, 0.0, 0.000001, "(and his wipers smear nothing any more)")

	# The same road with a long halt on the shoulder, hazard lights on.
	_begin_quiet_boss(STORM)
	var halt_at: float = 500.0
	while _sim.car.s < halt_at:
		_tick()
	_stand_on_the_shoulder(true)
	var stood_at: float = _sim.car.s
	_ticks(_ticks_in(through * 2.0))
	check(_event("boss_ended").is_empty(), "standing for twice the time the drive takes does not end the Storm")
	check(_sim.boss.active and _sim.leg.active, "(he is still in it)")
	check_near(_sim.car.s, stood_at, 0.000001, "nor does it bring him a metre further")
	check_eq(_sim.faults.lamps, 0, "(nothing hit him there)")
	# On again: the end is where it was.
	_drive_on()
	guard = _ticks_in(200.0)
	var from_tick: int = _sim.tick
	while _event("boss_ended").is_empty() and guard > 0:
		guard -= 1
		_tick()
	check(_sim.car.s >= length and _sim.car.s < length + 1.0, "after the halt the Storm still ends at 2,000 m (ended at %.2f m)" % _sim.car.s)
	check_near(float(_sim.tick - from_tick) * DT, (length - stood_at) / (tuning.fi("gear_speeds", 2) * KMH_TO_MS), 0.1,
			"all the road that was left when he stopped was still to drive")


## Visibility: 8 s thin (40 m), 12 s thick (15 m), over and over, by the clock.
func _check_storm_dust_rhythm() -> void:
	var storm: Dictionary = _storm()
	var thin_s: float = GameData.as_float(storm.get("thin_s"))
	var thick_s: float = GameData.as_float(storm.get("thick_s"))
	var thin_m: float = GameData.as_float(storm.get("thin_m"))
	var thick_m: float = GameData.as_float(storm.get("thick_m"))
	check_near(thick_s, 12.0, 0.000001, "GDD 10.3: thick dust lasts 12 s")
	check_near(thin_s, 8.0, 0.000001, "thin dust 8 s")
	check_near(thick_m, 15.0, 0.000001, "in thick dust he sees 15 m")
	check_near(thin_m, 40.0, 0.000001, "in thin dust 40 m")

	for standing: bool in [false, true]:
		_begin_quiet_boss(STORM)
		if standing:
			_stand_on_the_shoulder(true)
		# How far he sees at each tick, as runs of the same distance.
		var reaches: Array[float] = []
		var lengths: Array[int] = []
		for _index: int in _ticks_in(2.0 * (thin_s + thick_s) + thin_s * 0.5):
			var reach: float = _sim.visibility()
			if reaches.is_empty() or reach != reaches[-1]:
				reaches.append(reach)
				lengths.append(0)
			lengths[-1] += 1
			_tick()
		var how: String = "standing" if standing else "driving"
		check_eq(reaches.size(), 5, "%s: the dust changes four times in 44 s" % how)
		if reaches.size() != 5:
			continue
		check_near(reaches[0], thin_m, 0.000001, "%s: the Storm opens thin (40 m)" % how)
		check_eq(lengths[0], _ticks_in(thin_s), "%s: for 8 s" % how)
		check_near(reaches[1], thick_m, 0.000001, "%s: then thick (15 m)" % how)
		check_eq(lengths[1], _ticks_in(thick_s), "%s: for 12 s" % how)
		check_near(reaches[2], thin_m, 0.000001, "%s: thin again" % how)
		check_eq(lengths[2], _ticks_in(thin_s), "%s: for 8 s again" % how)
		check_near(reaches[3], thick_m, 0.000001, "%s: thick again" % how)
		check_eq(lengths[3], _ticks_in(thick_s), "%s: for 12 s again: a fixed 20 s rhythm" % how)
		check_near(GameData.as_float(_sim.snapshot()["visibility"]), _sim.visibility(), 0.000001, "(the snapshot carries it)")
	# What the view needs for the dust's tell: thick or thin, and when it changes.
	_begin_quiet_boss(STORM)
	_ticks(_ticks_in(thin_s - 1.0))
	check(not GameData.as_bool(_sim.snapshot()["dust_thick"]), "(7 s in, the dust is thin)")
	check_near(GameData.as_float(_sim.snapshot()["dust_change_in"]), 1.0, DT, "(and thickens in 1 s)")
	_ticks(_ticks_in(1.0))
	check(GameData.as_bool(_sim.snapshot()["dust_thick"]), "(8 s in it is thick)")
	check_near(GameData.as_float(_sim.snapshot()["dust_change_in"]), thick_s, DT, "(for 12 s)")


## Gusts push at 2 m/s (3 with Crosswind), each announced 1 s ahead.
func _check_storm_gusts(modifier: String) -> void:
	var storm: Dictionary = _storm()
	var push: float = GameData.as_float(storm.get("gust_push"))
	if modifier.is_empty():
		check_near(push, 2.0, 0.000001, "GDD 10.3: a gust pushes at 2 m/s")
		check_near(tuning.f("gust_tell"), 1.0, 0.000001, "and is announced 1 s ahead")
	else:
		push *= GameData.as_float(data.record("boss_modifiers", modifier).get("gust_mult"))
	var who: String = "the Storm" if modifier.is_empty() else modifier
	var plan: Dictionary = _begin_quiet_boss(STORM, modifier)
	var planned: Array = GameData.as_array(plan.get("gusts"))
	var par_ms: float = tuning.fi("gear_speeds", 2) * KMH_TO_MS
	var every: float = GameData.as_float(storm.get("gust_every_s")) * par_ms
	check_eq(planned.size(), int(floorf((GameData.as_float(plan.get("length")) - 0.001) / every)), "%s: a gust every %d m of it" % [who, roundi(every)])
	for index: int in planned.size():
		check_near(GameData.as_float(GameData.as_dict(planned[index]).get("s")), every * float(index + 1), 0.01, "%s: gust %d is where the rhythm puts it" % [who, index + 1])

	var crown: float = tuning.f("crown_drift")
	# Tick by tick: when a tell begins, which way it points, and when and how
	# hard the car is pushed.
	var tell_began: Array[int] = []
	var tell_way: Array[int] = []
	var push_began: Array[int] = []
	var push_ended: Array[int] = []
	var pushes: Array[float] = []
	var telling: bool = false
	var pushing: bool = false
	var guard: int = _ticks_in(200.0)
	while _event("boss_ended").is_empty() and guard > 0:
		guard -= 1
		_tick()
		var shot: Dictionary = _sim.snapshot()
		var told: bool = GameData.as_float(shot["gust_tell"]) > 0.0
		if told and not telling:
			tell_began.append(_sim.tick)
			tell_way.append(GameData.as_int(shot["gust_dir"]))
		telling = told
		var sideways: float = _sim.car.drift - crown
		var pushed: bool = absf(sideways) > 0.001
		if pushed and not pushing:
			push_began.append(_sim.tick)
			pushes.append(sideways)
		elif pushed and not is_equal_approx(sideways, pushes[-1]):
			fail("%s: a gust's push changed while it blew (%.3f, then %.3f m/s)" % [who, pushes[-1], sideways])
		if pushing and not pushed:
			push_ended.append(_sim.tick)
		pushing = pushed
	check_eq(tell_began.size(), planned.size(), "%s: every gust is announced" % who)
	check_eq(push_began.size(), planned.size(), "%s: and every gust blows" % who)
	if tell_began.size() != planned.size() or push_began.size() != planned.size() or push_ended.size() != planned.size():
		return
	var lefts: int = 0
	for index: int in planned.size():
		var way: int = GameData.as_int(GameData.as_dict(planned[index]).get("dir"))
		lefts += 1 if way < 0 else 0
		check_eq(push_began[index] - tell_began[index], _ticks_in(tuning.f("gust_tell")), "%s: gust %d is announced 1 s before it pushes" % [who, index + 1])
		check_eq(tell_way[index], way, "%s: the streaks of gust %d point the way it will push" % [who, index + 1])
		check_near(pushes[index], push * float(way), 0.000001, "%s: gust %d pushes at %.1f m/s" % [who, index + 1, push])
		check_eq(push_ended[index] - push_began[index], _ticks_in(tuning.f("gust_duration")), "%s: for gust_duration" % who)
	if modifier.is_empty():
		# From either side: over a handful of seeds both ways come up.
		var rights: int = planned.size() - lefts
		for seed_value: int in range(2, 8):
			for entry: Variant in GameData.as_array(BossSim.plan(data, STORM, "", seed_value).get("gusts")):
				if GameData.as_int(GameData.as_dict(entry).get("dir")) < 0:
					lefts += 1
				else:
					rights += 1
		check(lefts > 0 and rights > 0, "gusts come from the left and from the right (%d and %d)" % [lefts, rights])
		check_eq(JSON.stringify(BossSim.plan(data, STORM, "", 5)), JSON.stringify(BossSim.plan(data, STORM, "", 5)), "the same seed gives the same Storm")
		check(JSON.stringify(BossSim.plan(data, STORM, "", 5)) != JSON.stringify(BossSim.plan(data, STORM, "", 6)), "another seed another")


## Each wiper sweep adds 10% Haze; an open window adds 5% per second.
func _check_storm_haze() -> void:
	var storm: Dictionary = _storm()
	var smear: float = GameData.as_float(storm.get("wipe_haze"))
	var window_rate: float = GameData.as_float(storm.get("window_haze_per_s"))
	check_near(smear, 0.10, 0.000001, "GDD 10.3: a wiper sweep adds 10% Haze")
	check_near(window_rate, 0.05, 0.000001, "an open window 5% per second")
	var clears: float = tuning.f("haze_clear_rate")
	var cap: float = tuning.f("haze_cap")

	_begin_quiet_boss(STORM)
	check_near(_sim.items.haze, 0.0, 0.000001, "(the glass is clear as he drives in)")
	_reach("wiper_stalk")
	for sweep: int in 3:
		var before: float = _sim.items.haze
		var from_tick: int = _sim.tick
		_events = []
		_flick(Vector2(0.0, -tuning.f("flick_min_distance") * 1.5))
		check_eq(_count_events("ritual_completed", "ritual", "wipers"), 1, "(sweep %d is made through the hand)" % (sweep + 1))
		# What cleared by itself while the hand made the sweep is the only slack.
		var slack: float = clears * float(_sim.tick - from_tick) * DT
		check(_sim.items.haze <= before + smear + 0.000001 and _sim.items.haze >= before + smear - slack - 0.000001,
				"sweep %d smears 10%% more Haze on the glass (%.4f to %.4f)" % [sweep + 1, before, _sim.items.haze])
	check_near(GameData.as_float(_sim.snapshot()["haze"]), _sim.items.haze, 0.000001, "(the snapshot carries the Haze)")
	for _sweep: int in 6:
		_flick(Vector2(0.0, -tuning.f("flick_min_distance") * 1.5))
	check(_sim.items.haze <= cap + 0.000001 and _sim.items.haze > cap - smear, "sweep after sweep clouds it no further than haze_cap (%.3f)" % _sim.items.haze)
	# The thumb keypad's wiper key smears just the same.
	_begin_quiet_boss(STORM)
	_give("thumb_keypad")
	_grip()
	_input.pad_wiper = true
	_tick()
	_input.pad_wiper = false
	_tick()
	check(_sim.items.haze > smear - clears * DT * 3.0 and _sim.items.haze <= smear + 0.000001, "a sweep from the thumb keypad smears as much")

	# Not on any other road.
	_new_sim()
	_wipe()
	check_near(_sim.items.haze, 0.0, 0.000001, "out of the Storm a sweep smears nothing")
	_begin_quiet_leg("rain", 1, 3)
	_wipe()
	check_near(_sim.items.haze, 0.0, 0.000001, "nor in the rain")

	# The window.
	_begin_quiet_boss(STORM)
	_run(2.0)
	check_near(_sim.items.haze, 0.0, 0.000001, "with the window shut the dust stays out")
	_sim.items.complete(_ritual("window_crank"), 0)
	check(_sim.items.flag(ItemSim.FLAG_WINDOW), "(the window is open)")
	var open_ticks: int = _ticks_in(4.0)
	_ticks(open_ticks)
	check_near(_sim.items.haze, window_rate * float(open_ticks) * DT, 0.000001, "an open window lets in 5% Haze a second (20% in 4 s)")
	_ticks(_ticks_in(cap / window_rate))
	check_near(_sim.items.haze, cap, 0.000001, "up to haze_cap")
	_sim.items.complete(_ritual("window_crank"), 0)
	var shut_ticks: int = _ticks_in(2.0)
	_ticks(shut_ticks)
	check_near(_sim.items.haze, cap - clears * float(shut_ticks) * DT, 0.000001, "shut again, the glass clears as ever")
	_new_sim()
	_sim.items.complete(_ritual("window_crank"), 0)
	_run(4.0)
	check_near(_sim.items.haze, 0.0, 0.000001, "out of the Storm an open window lets in none")


## Stopped on the shoulder with the hazard lights on he is always safe.
## Anywhere else, or dark, something may hit him from behind every 10 s.
func _check_storm_standing() -> void:
	var storm: Dictionary = _storm()
	var every: float = GameData.as_float(storm.get("rear_end_every_s"))
	var tell: float = GameData.as_float(storm.get("rear_end_tell_s"))
	var chance: float = GameData.as_float(storm.get("rear_end_chance"))
	check_near(every, 10.0, 0.000001, "GDD 10.3: the risk comes every 10 s")
	check(tell >= 1.0, "GDD 2.2, pillar 4: with a tell at least 1 s ahead")
	check(chance > 0.0 and chance < 1.0, "it is a risk: neither sure nor never (%.2f)" % chance)
	var periods: int = 30
	var crash_lamps: int = int(tuning.fi("hit_lamps", 1))

	# Safe: on the shoulder, hazard lights on. Thirty waits in each of three Storms.
	for seed_value: int in [1, 2, 3]:
		_begin_quiet_boss(STORM, "", seed_value)
		_sim.rng.reseed(seed_value)
		_stand_on_the_shoulder(true)
		_events = []
		_ticks(_ticks_in(every * float(periods)))
		check_eq(_count_events("hit"), 0, "on the shoulder with his hazard lights on nothing hits him (seed %d, %d s)" % [seed_value, roundi(every * float(periods))])
		check_eq(_sim.faults.lamps, 0, "(no lamp)")
		check_eq(_horns_behind(), 0, "(and nothing comes up behind him)")

	# Not safe, three ways: dark on the shoulder; lit in a lane; lit and half
	# on the shoulder.
	var unsafe: Array[String] = ["on the shoulder without his hazard lights", "in a lane with them on", "half on the shoulder with them on"]
	var total_hits: int = 0
	for way: int in unsafe.size():
		_begin_quiet_boss(STORM, "", 1)
		_sim.rng.reseed(11 + way)
		if way == 0:
			_stand_on_the_shoulder(false)
		elif way == 1:
			_stand_in_lane(true)
		else:
			_stand_on_the_shoulder(true)
			_sim.car.x = _sim.car.road_right() + _sim.car.half_width() - 0.3
		_events = []
		var began: int = _sim.tick
		var hits: Array[int] = []
		var tells: Array[int] = []
		var lamps: int = 0
		for _index: int in _ticks_in(every * float(periods)):
			var before: int = _events.size()
			var nerves_before: float = _sim.nerves.value
			var lamps_before: int = _sim.faults.lamps
			_tick()
			for index: int in range(before, _events.size()):
				var event: Dictionary = _events[index]
				if GameData.as_string(event.get("type")) == "hit":
					hits.append(_sim.tick - began)
					check_eq(GameData.as_int(event.get("kind")), Collision.Hit.CRASH, "%s: what hits him is a crash" % unsafe[way])
					check(GameData.as_bool(event.get("rear_end")), "(from behind)")
					if hits.size() == 1:
						check_eq(_sim.faults.lamps - lamps_before, crash_lamps, "(two lamps)")
						check(_sim.nerves.value - nerves_before >= tuning.fi("hit_nerves", 1) - 0.01, "(and a crash's Nerves)")
				elif GameData.as_string(event.get("type")) == "sfx_requested" and GameData.as_bool(event.get("behind")):
					tells.append(_sim.tick - began)
			lamps = _sim.faults.lamps
		total_hits += hits.size()
		check(hits.size() > 0 and hits.size() < periods, "%s: in %d waits of 10 s he is hit %d times: a risk each time" % [unsafe[way], periods, hits.size()])
		for at: int in hits:
			check_eq(at % _ticks_in(every), 0, "%s: a hit comes at a whole 10 s of standing (after %.2f s)" % [unsafe[way], float(at) * DT])
		check_eq(tells.size(), hits.size(), "%s: each hit is announced, and nothing else is" % unsafe[way])
		for index: int in mini(tells.size(), hits.size()):
			check_eq(hits[index] - tells[index], _ticks_in(tell), "%s: by a horn behind him %d s before" % [unsafe[way], roundi(tell)])
		check(lamps > 0, "(lamps were lit)")
	var mean: float = float(periods * unsafe.size()) * chance
	var spread: float = sqrt(float(periods * unsafe.size()) * chance * (1.0 - chance))
	check(absf(float(total_hits) - mean) <= 4.0 * spread, "about half the waits end in a hit (%d of %d)" % [total_hits, periods * unsafe.size()])

	# The tell is a second in which to save himself: by driving off...
	for remedy: int in 3:
		_begin_quiet_boss(STORM, "", 1)
		_sim.rng.reseed(11)
		_stand_on_the_shoulder(false)
		_events = []
		var guard: int = _ticks_in(every * float(periods))
		while _horns_behind() == 0 and guard > 0:
			guard -= 1
			_tick()
		check(guard > 0, "(something comes up behind him)")
		check(GameData.as_float(_sim.snapshot()["rear_end_in"]) > tell - 2.0 * DT, "(its lights are in the mirror: %d s away)" % roundi(tell))
		match remedy:
			0:
				# ...he stays: it hits him.
				pass
			1:
				_drive_on()
				_sim.gate.reset(1)
			2:
				# ...or by putting his hazard lights on, there on the shoulder.
				_tap_at("hazard_button")
				check(_sim.items.flag(DriveSim.FLAG_HAZARDS), "(his hazard lights are on)")
		_events = []
		_ticks(_ticks_in(tell + 1.0))
		var what: String = ["he stays as he is: it hits him", "he drives off: it misses him", "he puts his hazard lights on: it misses him"][remedy]
		check_eq(_count_events("hit"), 1 if remedy == 0 else 0, "the horn sounds and %s" % what)
		check_near(GameData.as_float(_sim.snapshot()["rear_end_in"]), 0.0, 0.000001, "(then nothing is behind him)")
		if remedy == 1:
			# Standing again is a new wait, from nothing.
			_stand_on_the_shoulder(false)
			_events = []
			var again: int = _sim.tick
			guard = _ticks_in(every * float(periods))
			while _count_events("hit") == 0 and guard > 0:
				guard -= 1
				_tick()
			var waited: int = _sim.tick - again
			check(waited >= _ticks_in(every) and waited % _ticks_in(every) == 0,
					"standing again, a hit comes no sooner than a whole 10 s on (it came after %.2f s)" % (float(waited) * DT))
			check_eq(_horns_behind(), 1, "(and is announced as ever)")

	# Slow is not stopped: at a crawl nothing comes.
	_begin_quiet_boss(STORM, "", 1)
	_sim.rng.reseed(11)
	_events = []
	var crawl: float = GameData.as_float(storm.get("stopped_kmh")) + 2.0
	for _index: int in _ticks_in(every * 6.0):
		_sim.car.speed = crawl
		_tick()
	check_eq(_count_events("hit"), 0, "a car that still rolls is not stopped: nothing hits it")
	# And on a leg that is no Storm a standing car is left alone.
	_begin_quiet_leg("open_road", 1, 3)
	_sim.rng.reseed(11)
	_stand_in_lane(false)
	_events = []
	_ticks(_ticks_in(every * 6.0))
	check_eq(_count_events("hit"), 0, "out of the Storm a standing car is not run into")


## The weather cramp fires once (GDD 7.9).
func _check_storm_cramp() -> void:
	var at: float = GameData.as_float(data.record("bosses", STORM).get("length_m")) * tuning.f("phantom_cramp_at")
	_begin_quiet_boss(STORM)
	var hums: int = 0
	var cramps: int = 0
	var hum_at: float = -1.0
	var was: String = ""
	var nerves_at_cramp: float = 0.0
	var guard: int = _ticks_in(200.0)
	while _event("boss_ended").is_empty() and guard > 0:
		guard -= 1
		var before: float = _sim.nerves.value
		_tick()
		if _sim.cramp != was:
			if _sim.cramp == DriveSim.HUM:
				hums += 1
				hum_at = _sim.car.s
			elif _sim.cramp == DriveSim.CRAMPED:
				cramps += 1
				nerves_at_cramp = _sim.nerves.value - before
			was = _sim.cramp
	check_eq(hums, 1, "the low hum comes once in the Storm")
	check_eq(cramps, 1, "and the cramp once")
	check(hum_at >= at and hum_at < at + 1.0, "at a fixed point of it: %d m (it began at %.1f m)" % [roundi(at), hum_at])
	check_near(nerves_at_cramp, tuning.f("phantom_cramp_nerves"), 0.01, "it costs phantom_cramp_nerves")
	# Switched off in the settings, it does not come.
	_begin_quiet_boss(STORM)
	_sim.phantom_enabled = false
	hums = 0
	guard = _ticks_in(200.0)
	while _event("boss_ended").is_empty() and guard > 0:
		guard -= 1
		_tick()
		hums += 1 if _sim.cramp != "" else 0
	check_eq(hums, 0, "with the Phantom switched off there is no cramp in the Storm")


## Crosswind: gusts 50% stronger. Night storm: only the headlight cone.
func _check_storm_modifiers() -> void:
	var record: Dictionary = data.record("bosses", STORM)
	var listed: Array = GameData.as_array(record.get("modifiers"))
	check(listed.size() == 2 and listed.has("crosswind") and listed.has("night_storm"), "GDD 10.3: the Storm's modifiers are Crosswind and Night storm")
	check_near(GameData.as_float(data.record("boss_modifiers", "crosswind").get("gust_mult")), 1.5, 0.000001, "Crosswind: gusts 50% stronger")
	_check_storm_gusts("crosswind")
	# Crosswind changes the gusts and nothing else.
	var plain: Dictionary = BossSim.plan(data, STORM, "", 4)
	var windy: Dictionary = BossSim.plan(data, STORM, "crosswind", 4)
	check_near(GameData.as_float(windy.get("gust_push")), GameData.as_float(plain.get("gust_push")) * 1.5, 0.000001, "(the plan carries the stronger push)")
	check_eq(JSON.stringify(windy.get("gusts")), JSON.stringify(plain.get("gusts")), "(the same gusts in the same places)")
	check_eq(GameData.as_string(windy.get("condition")), "clear", "(by day)")

	# Night storm: it is night, and he sees no further than his headlights.
	var storm: Dictionary = _storm()
	var thin_m: float = GameData.as_float(storm.get("thin_m"))
	var thick_m: float = GameData.as_float(storm.get("thick_m"))
	_begin_quiet_boss(STORM, "night_storm")
	check_eq(_sim.boss.modifier, "night_storm", "(Night storm)")
	check(_sim.leg.night, "Night storm: the Storm is driven in the dark")
	check(GameData.as_bool(_sim.snapshot()["night"]), "(the snapshot says night: the view is the headlight cone)")
	var cone: float = _sim.headlight_cone()
	check_near(_sim.visibility(), minf(thin_m, cone), 0.000001, "in thin dust he sees the nearer of the dust and his headlights")
	# A dead headlight halves the cone: now the cone is the nearer.
	_sim.faults.active.append(DriveSim.FAULT_HEADLIGHT)
	var dim: float = _sim.headlight_cone()
	check(dim < thin_m and dim > thick_m, "(a dead headlight: a cone of %d m, between thick and thin)" % roundi(dim))
	check_near(_sim.visibility(), dim, 0.000001, "with one headlight he sees only as far as its cone, thin dust or not")
	_ticks(_ticks_in(GameData.as_float(storm.get("thin_s")) + 1.0))
	check_near(_sim.visibility(), thick_m, 0.000001, "and thick dust is nearer still")
	# By day the same fault changes nothing.
	_begin_quiet_boss(STORM)
	check(not _sim.leg.night, "(the plain Storm is by day)")
	_sim.faults.active.append(DriveSim.FAULT_HEADLIGHT)
	check_near(_sim.visibility(), thin_m, 0.000001, "by day a dead headlight does not shorten his view")
	# The gusts of a Night storm are the plain Storm's.
	check_near(GameData.as_float(BossSim.plan(data, STORM, "night_storm", 4).get("gust_push")), GameData.as_float(plain.get("gust_push")), 0.000001,
			"(a Night storm's gusts are no stronger)")
	# A modifier of another boss is not the Storm's.
	check_eq(GameData.as_string(BossSim.plan(data, STORM, "long_queue", 4).get("boss_modifier")), "", "another boss's modifier does nothing to the Storm")

	# Which Telling has which: by the seed, in boss_modifier_chance of them.
	var share: float = tuning.fi("boss_modifier_chance", 1)
	var counts: Dictionary = {"": 0, "crosswind": 0, "night_storm": 0}
	var tellings: int = 600
	for seed_value: int in range(1, tellings + 1):
		var drawn: String = RunGenerator.boss_modifier(data, seed_value, 2)
		check(counts.has(drawn), "a Storm has one of its own modifiers or none (seed %d: '%s')" % [seed_value, drawn])
		counts[drawn] = GameData.as_int(counts.get(drawn)) + 1
		check_eq(RunGenerator.boss_modifier(data, seed_value, 2), drawn, "(the same seed, the same modifier)")
	var modified: int = GameData.as_int(counts["crosswind"]) + GameData.as_int(counts["night_storm"])
	var spread: float = sqrt(float(tellings) * share * (1.0 - share))
	check(absf(float(modified) - float(tellings) * share) <= 4.0 * spread, "the Storm has a modifier in boss_modifier_chance of Tellings (%d of %d)" % [modified, tellings])
	check(absf(float(GameData.as_int(counts["crosswind"])) - float(modified) * 0.5) <= 4.0 * sqrt(float(modified) * 0.25),
			"Crosswind as often as Night storm (%d and %d)" % [GameData.as_int(counts["crosswind"]), GameData.as_int(counts["night_storm"])])


## In thick dust he follows tail lights: the plan always has some ahead.
func _check_storm_tail_lights() -> void:
	var lights: Dictionary = GameData.as_dict(_storm().get("tail_lights"))
	var gaps: Array = GameData.as_array(lights.get("gap_m"))
	var speeds: Array = GameData.as_array(lights.get("speed_kmh"))
	var types: Array = GameData.as_array(lights.get("vehicles"))
	for seed_value: int in [1, 2, 3]:
		var plan: Dictionary = BossSim.plan(data, STORM, "", seed_value)
		var spawns: Array = GameData.as_array(plan.get("spawns"))
		var length: float = GameData.as_float(plan.get("length"))
		check(spawns.size() >= int(floorf(length / GameData.as_float(gaps[1]))) - 1, "seed %d: there are tail lights all along the Storm (%d vehicles)" % [seed_value, spawns.size()])
		var last_at: float = -INF
		var last_lane: int = -1
		for entry: Variant in spawns:
			var spawn: Dictionary = GameData.as_dict(entry)
			var at: float = GameData.as_float(spawn.get("trigger_s")) + GameData.as_float(spawn.get("ahead"))
			var lane: int = GameData.as_int(spawn.get("lane"))
			var speed: float = GameData.as_float(spawn.get("speed"))
			check(types.has(GameData.as_string(spawn.get("vehicle"))), "(a vehicle of the Storm's list)")
			check(speed >= GameData.as_float(speeds[0]) - 0.05 and speed <= GameData.as_float(speeds[1]) + 0.05, "(slower than he is in third: %.1f km/h)" % speed)
			check(lane >= 0 and lane < GameData.as_int(plan.get("lanes")), "(in a lane)")
			check(lane != last_lane, "seed %d: no two in a row are in one lane: there is always a way past" % seed_value)
			if last_at > -INF:
				check(at - last_at >= GameData.as_float(gaps[0]) - 0.02 and at - last_at <= GameData.as_float(gaps[1]) + 0.02, "(the next is %d m on)" % roundi(at - last_at))
			last_at = at
			last_lane = lane
		check(last_at > length - GameData.as_float(gaps[1]) - 0.02, "seed %d: the last is near the end" % seed_value)
	# On the road they are there to be seen and followed: lit vehicles ahead, going his way.
	_sim = DriveSim.new(fresh_data())
	_events = []
	_sim.gate.reset(2)
	_sim.begin_boss(STORM, "", 1)
	check_eq(GameData.as_string(_event_of(_sim.drain_events(), "boss_started").get("boss")), STORM, "(begin_boss announces the Storm)")
	_input.clear()
	var seen_ahead: int = 0
	for _index: int in _ticks_in(20.0):
		# Kept on the shoulder side of the right lane's middle, clear of nobody: just looking.
		_sim.car.x = _sim.car.road_right() + 1.5
		_sim.step(_input)
		for vehicle: TrafficSim.Vehicle in _sim.traffic.vehicles:
			if vehicle.direction > 0 and vehicle.s > _sim.car.s:
				seen_ahead += 1
	check(seen_ahead > 0, "driving in, there are vehicles ahead of him going his way")


## The Storm ends Act 2 of a Telling, with the modifier its seed draws.
func _check_storm_in_a_telling() -> void:
	var wanted: Array[String] = ["", "crosswind", "night_storm"]
	for want: String in wanted:
		var telling_seed: int = 0
		for candidate: int in range(1, 400):
			if RunGenerator.boss_modifier(data, candidate, 2) == want:
				telling_seed = candidate
				break
		check(telling_seed > 0, "(a seed whose Storm has '%s')" % want)
		_sim = DriveSim.new(fresh_data())
		_events = []
		_input.clear()
		_sim.begin_telling(TABLE, telling_seed)
		_drive_on_to_act(2)
		var guard: int = 40000
		while _sim.run.stage != RunState.Stage.BOSS and guard > 0:
			guard -= 1
			if _sim.stopped:
				_leave_stop()
				continue
			_sim.car.x = _sim.car.lane_center(1)
			if _sim.leg.active and _sim.car.s < _sim.leg.length - 2.0:
				_sim.car.s = _sim.leg.length - 1.0
			_sim.step(_input)
		for event: Dictionary in _sim.drain_events():
			_events.append(event)
		var started: Dictionary = _event("boss_started")
		check_eq(GameData.as_string(started.get("boss")), STORM, "the third leg of Act 2 leads into the Storm")
		check_eq(GameData.as_string(started.get("modifier")), want, "with the modifier its seed draws ('%s')" % want)
		check_eq(_sim.boss.kind, STORM, "(he is in it)")
		check_eq(_sim.boss.modifier, want, "(so modified)")
		check_near(_sim.leg.length, GameData.as_float(data.record("bosses", STORM).get("length_m")), 0.000001, "(2,000 m of it)")
		check_near(_sim.heavy_floor(), tuning.fi("heavy_floor", 1), 0.000001, "GDD 6.1: the Storm's Heavy floor is Act 2's")
		check_eq(_sim.leg.night, want == "night_storm", "(night only in a Night storm)")
		# To its end: the boss stop, where the game saves.
		var saves: int = _sim.checkpoints
		guard = 40000
		while not _sim.stopped and guard > 0:
			guard -= 1
			_sim.car.x = _sim.car.lane_center(1)
			if _sim.car.s < _sim.leg.length - 2.0:
				_sim.car.s = _sim.leg.length - 1.0
			_sim.step(_input)
		for event: Dictionary in _sim.drain_events():
			_events.append(event)
		check_eq(GameData.as_string(_event("boss_ended").get("boss")), STORM, "the Storm ends")
		check_eq(_sim.run.stage, RunState.Stage.BOSS_STOP, "at the boss stop")
		check_eq(_sim.checkpoints, saves + 1, "where the game saves")
		check(not _sim.boss.active and is_inf(_sim.visibility()), "(the dust is behind him)")
		check_near(_sim.items.wipe_haze, 0.0, 0.000001, "(and his wipers smear nothing any more)")


# --- Helpers -----------------------------------------------------------------

## The car stands wholly on the shoulder, the brake held, the hazard lights
## as told. From here the car is no longer put back in its lane.
func _stand_on_the_shoulder(hazards: bool) -> void:
	_keep_lane = false
	_input.clear()
	_input.rmb = true
	_sim.car.x = (_sim.car.road_right() + _sim.car.guardrail_x()) * 0.5
	_sim.car.speed = 0.0
	_sim.car.v_lat = 0.0
	_sim.items.flags[DriveSim.FLAG_HAZARDS] = hazards


## The car stands in the middle of its lane, the brake held.
func _stand_in_lane(hazards: bool) -> void:
	_keep_lane = true
	_input.clear()
	_input.rmb = true
	_sim.car.speed = 0.0
	_sim.car.v_lat = 0.0
	_sim.items.flags[DriveSim.FLAG_HAZARDS] = hazards


## Off the brake, back in the middle lane, in third gear at its speed.
func _drive_on() -> void:
	_input.clear()
	_keep_lane = true
	_sim.gate.reset(3)
	_sim.car.x = _sim.car.lane_center(1)
	_sim.car.speed = tuning.fi("gear_speeds", 2)


## How often something has sounded its horn behind him (the tell of a
## rear-end crash).
func _horns_behind() -> int:
	var count: int = 0
	for event: Dictionary in _events:
		if GameData.as_string(event.get("type")) == "sfx_requested" and GameData.as_bool(event.get("behind")):
			count += 1
	return count


func _event_of(events: Array[Dictionary], type: String) -> Dictionary:
	for event: Dictionary in events:
		if GameData.as_string(event.get("type")) == type:
			return event
	return {}
