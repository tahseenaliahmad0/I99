extends CabinSuite
## M9: the seven Tables of GDD 11.2. "Each Table is its own ruleset on top of
## the base game. Rules do not stack from Table to Table." Each test tells
## the night to its Table and holds the Table's rule against the same night
## told to the Drivers, whose rules are the base rules.

const ORDER: PackedStringArray = ["children", "drivers", "uncles", "inlaws", "aunts", "groom", "noor"]
const BASE: String = "drivers"


func _table(id: String) -> Dictionary:
	return data.record("tables", id)


func _rules(id: String) -> Dictionary:
	return GameData.as_dict(_table(id).get("rules"))


## A Telling for `table_id` from Baghdad, on the road to its first fork.
func _tell(table_id: String, telling_seed: int) -> void:
	_sim = DriveSim.new(fresh_data())
	_events = []
	_keep_lane = true
	_input.clear()
	_sim.begin_telling(table_id, telling_seed)
	for event: Dictionary in _sim.drain_events():
		_events.append(event)


## The same, driven on into its first leg (the right branch), with nothing
## on that leg's road and the car in third gear.
func _tell_to_first_leg(table_id: String, telling_seed: int) -> void:
	_tell(table_id, telling_seed)
	_into_next_quiet_leg()


## What every Table's test asks of its record: its place in the chain of
## GDD 11.2 and who heckles there.
func _check_place(id: String, heckles: PackedStringArray) -> void:
	var place: int = ORDER.find(id)
	check(place >= 0 and data.has_record("tables", id), "(tables.json has the %s Table)" % id)
	var rules: TableRules = TableRules.of(data, id)
	var types: PackedStringArray = rules.heckle_types()
	types.sort()
	var wanted: PackedStringArray = heckles.duplicate()
	wanted.sort()
	check_eq(types, wanted, "%s: its guests heckle with %s" % [id, ", ".join(heckles) if not heckles.is_empty() else "nothing"])
	var fresh: Dictionary = Save.default_profile()
	if place == 0:
		check_eq(GameData.as_string(_table(id).get("unlock")), TableRules.UNLOCK_START, "%s: unlocked from the start" % id)
		check(TableRules.open_at_start(data).has(id), "(the data says so)")
		check(TableRules.unlocked(fresh, id), "a player who has never played can sit there")
		return
	var before: String = ORDER[place - 1]
	check_eq(GameData.as_string(_table(id).get("unlock")), TableRules.UNLOCK_WIN + before, "%s: unlocked by winning the %s Table on time" % [id, before])
	check(not TableRules.unlocked(fresh, id), "a player who has never played cannot sit there")
	check(not TableRules.open_at_start(data).has(id), "(it is not open from the start)")
	# Winning any other Table does not open it; winning the one before it does.
	for other: String in ORDER:
		if other == before:
			continue
		var profile: Dictionary = Save.default_profile()
		TableRules.win(data, profile, other)
		check(not TableRules.unlocked(profile, id), "winning the %s Table does not open the %s Table" % [other, id])
	var won: Dictionary = Save.default_profile()
	var opened: PackedStringArray = TableRules.win(data, won, before)
	check(TableRules.unlocked(won, id) and opened == PackedStringArray([id]), "winning the %s Table on time opens it, and it alone" % before)
	check(TableRules.win(data, won, before).is_empty() and GameData.as_array(won["tables_unlocked"]).count(id) == 1, "(won again, nothing more opens and it is listed once)")


## The ids of what is in the cabin, sorted.
func _cabin() -> PackedStringArray:
	var out: PackedStringArray = []
	for item: ItemSim.Item in _sim.items.items:
		out.append(String(item.id))
	out.sort()
	return out


## What the tray holds of one kind, as id -> price.
func _prices(kind: StringName) -> Dictionary:
	var out: Dictionary = {}
	for offer: Dictionary in _offers():
		if offer["kind"] == kind:
			out[GameData.as_string(offer["id"])] = GameData.as_float(offer["price"])
	return out


## The Checkpoint he is in, begun again with nobody waiting in its queues.
func _empty_the_queue() -> void:
	var plan: Dictionary = BossSim.plan(data, BossSim.CHECKPOINT, _sim.run.boss_modifier, RunGenerator.boss_seed(_sim.run.seed, _sim.run.act))
	var nobody: Array = []
	for _lane: int in GameData.as_int(plan.get("lanes")):
		nobody.append([])
	plan["queue"] = nobody
	_sim.gate.reset(3)
	_sim.begin_leg(plan)
	_sim.in_encounter = true
	_sim.drain_events()


## A Snap on the road, by a slap at the edge of it (GDD 4.6, 6.1).
func _snap() -> void:
	_sim.nerves.set_value(tuning.f("snap_at") - 1.0)
	_tap_at("face")


# --- T-TABLE-DRIVERS -----------------------------------------------------------

## T-TABLE-DRIVERS: The Drivers (11.2): base rules; heckles are Dares;
## unlocked by winning the Children's Table on time.
func test_table_drivers() -> void:
	_check_place("drivers", PackedStringArray(["DARE"]))
	check(_rules("drivers").is_empty(), "the Drivers' Table names no rule: its rules are the base rules")
	check_near(GameData.as_float(_table("drivers").get("depart_min")), 0.0, 0.000001, "he leaves at 22:00")
	var rules: TableRules = TableRules.of(data, "drivers")
	var none: TableRules = TableRules.new()
	check(rules.price_mult == none.price_mult and rules.free_rewinds == none.free_rewinds and rules.patrol_every_act == none.patrol_every_act
			and rules.checkpoint_suspicion_mult == none.checkpoint_suspicion_mult and rules.no_contraband == none.no_contraband
			and rules.no_deals == none.no_deals and rules.no_bribes == none.no_bribes and rules.snap_minutes == none.snap_minutes
			and rules.heavy_floor_add == none.heavy_floor_add and rules.start_items.is_empty() and rules.full_supplies.is_empty()
			and rules.boss_alone_nerves == none.boss_alone_nerves and rules.seed == TableRules.NO_SEED and not rules.fixed_road()
			and rules.stock_offered() and rules.deals_offered() and not rules.places_hitchers(),
			"read as rules, it changes nothing")

	# Told to the Drivers the night is the night of a road with no Table at all.
	var telling_seed: int = _seed_for("fuel_station")
	var hashes: PackedStringArray = []
	var cabins: Array[PackedStringArray] = []
	var prices: Array[Dictionary] = []
	for table_id: String in ["drivers", "nobody"]:
		_tell_to_first_leg(table_id, telling_seed)
		cabins.append(_cabin())
		_run(5.0)
		_into_stall()
		prices.append(_prices(StopSim.ITEM))
		_sim.run.table = ""
		hashes.append(_sim.state_hash())
	check_eq(cabins[0], cabins[1], "the cabin is the starting cabin")
	check_eq(cabins[0], PackedStringArray(["cigarettes", "tea_glass"]), "(cigarettes and tea)")
	check(not prices[0].is_empty() and prices[0] == prices[1], "prices are the prices of the items")
	for id: Variant in prices[0]:
		check_near(GameData.as_float(prices[0][id]), GameData.as_float(_record(str(id)).get("price")), 0.000001, "%s costs what its record says" % str(id))
	check_eq(hashes[0], hashes[1], "and the whole night, to the bit, is the one a road with no Table's rules gives")

	_tell("drivers", telling_seed)
	check_eq(_sim.clock.text(), "22:00", "the Drivers' night begins at 22:00")
	check_near(_sim.heavy_floor(), tuning.fi("heavy_floor", 0), 0.000001, "with Act 1's Heavy floor")
	check_eq(_sim.rewinds_left, 0, "and no rewind")


# --- T-TABLE-INLAWS ------------------------------------------------------------

## T-TABLE-INLAWS: The In-laws (11.2): no contraband, no Deals, no bribes;
## each Snap costs 15 game minutes; heckles are Questions; unlocked by
## winning the Uncles' Table on time.
func test_table_inlaws() -> void:
	_check_place("inlaws", PackedStringArray(["QUESTION"]))
	var rules: Dictionary = _rules("inlaws")
	check(GameData.as_bool(rules.get("no_contraband")) and GameData.as_bool(rules.get("no_deals")) and GameData.as_bool(rules.get("no_bribes")),
			"GDD 11.2: no contraband, no Deals, no bribes")
	var snap_minutes: float = GameData.as_float(rules.get("snap_minutes"))
	check_near(snap_minutes, 15.0, 0.000001, "each Snap costs 15 game minutes")

	# No Deals: after a leg that lit no lamp the shady guy is at the Drivers'
	# stop, and not at the In-laws'.
	var telling_seed: int = _seed_for("fuel_station")
	for table_id: String in [BASE, "inlaws"]:
		_tell_to_first_leg(table_id, telling_seed)
		_give("arak_flask", "cup_b")
		var flask: ItemSim.Item = _item("arak_flask")
		flask.supply = 1
		_events = []
		_into_stall()
		var entered: Dictionary = _event("stop_entered")
		var shady: int = 0
		var contraband: int = 0
		for offer: Dictionary in _offers():
			if GameData.as_bool(offer["shady"]):
				shady += 1
			if offer["kind"] != StopSim.SERVICE and offer["kind"] != StopSim.REPAIR and GameData.as_bool(_record(GameData.as_string(offer["id"])).get("contraband")):
				contraband += 1
		if table_id == BASE:
			check(GameData.as_bool(entered.get("shady")) and shady > 0, "(told to the Drivers, a clean leg brings the shady guy: %d things of his on the tray)" % shady)
			check(contraband > 0, "(and contraband with him: the flask's refill or a Deal)")
		else:
			check(not GameData.as_bool(entered.get("shady")), "told to the In-laws, the shady guy is not there after a clean leg")
			check_eq(shady, 0, "nothing of his is on the tray")
			check_eq(contraband, 0, "and no contraband is held out or refilled")
			check(not GameData.as_bool(_sim.checkpoint.get("shady")), "(nor does the save say he was)")

	# No contraband anywhere: every stop of forty nights' first acts, the
	# boss stop's free picks included.
	var stops_seen: int = 0
	var held_out: int = 0
	for night: int in range(1, 41):
		_tell_to_first_leg("inlaws", night)
		for _leg: int in RunGenerator.LEGS_PER_ACT:
			_into_stall()
			stops_seen += 1
			for offer: Dictionary in _offers():
				if GameData.as_bool(offer["shady"]) or (offer["kind"] == StopSim.ITEM and GameData.as_bool(_record(GameData.as_string(offer["id"])).get("contraband"))):
					held_out += 1
			_leave_stop()
			if _sim.run.legs_done < RunGenerator.LEGS_PER_ACT - 1 or _sim.run.fork_ahead():
				_into_next_quiet_leg()
		if night <= 10:
			_drive_on_to_boss()
			_drive_on_to_boss_stop()
			stops_seen += 1
			for offer: Dictionary in _offers():
				if GameData.as_bool(offer["shady"]) or (offer["kind"] == StopSim.ITEM and GameData.as_bool(_record(GameData.as_string(offer["id"])).get("contraband"))):
					held_out += 1
	check(stops_seen >= 120, "(%d stops of the In-laws' nights were looked at)" % stops_seen)
	check_eq(held_out, 0, "at none of them is contraband or a Deal held out")

	# No bribes: the officer of a Patrol does not take banknotes.
	for table_id: String in [BASE, "inlaws"]:
		_tell_to_first_leg(table_id, telling_seed)
		_sim.cash = 500.0
		_sim.suspicion.begin_watch()
		_sim.suspicion.add(_sim.suspicion.maximum())
		_events = []
		var guard: int = _ticks_in(20.0)
		while not _sim.pulled_over and guard > 0:
			guard -= 1
			_input.rmb = true
			_tick()
		_input.clear()
		if not check(_sim.pulled_over, "(%s: at the top of Suspicion he is pulled over)" % table_id):
			continue
		var asked: Dictionary = _event("pulled_over")
		var cash: float = _sim.cash
		_events = []
		_drag("cash", "driver_window")
		if table_id == BASE:
			check(GameData.as_bool(asked.get("can_bribe")), "(told to the Drivers, the officer can be bribed)")
			check(not _sim.pulled_over and _sim.cash < cash, "(and banknotes let him go)")
		else:
			check(not GameData.as_bool(asked.get("can_bribe")), "told to the In-laws, the officer cannot be bribed")
			check(_sim.pulled_over, "banknotes held out to him let nobody go")
			check_near(_sim.cash, cash, 0.000001, "and cost nothing")
			check(GameData.as_bool(_event("pulled_over").get("refused")), "(he refuses them)")
			_drag("dash_1", "driver_window")
			check(not _sim.pulled_over, "the licence, and its fine, do")

	# Nor does the soldier.
	for table_id: String in [BASE, "inlaws"]:
		_tell_to_first_leg(table_id, telling_seed)
		_drive_on_to_boss()
		check_eq(_sim.run.boss, BossSim.CHECKPOINT, "(%s: the Checkpoint)" % table_id)
		_empty_the_queue()
		_sim.items.flags[ItemSim.FLAG_WINDOW] = true
		_sim.cash = 500.0
		check(_stand_at_the_bar(), "(first in line)")
		_until_checkpoint_phase(BossSim.PAPERS, GameData.as_float(GameData.as_dict(data.record("bosses", "checkpoint").get("checkpoint")).get("stow_s")) + 1.0)
		var cash: float = _sim.cash
		_events = []
		_drag("cash", "driver_window")
		if table_id == BASE:
			check_eq(GameData.as_string(_event("pulled_over").get("paid")), "bribe", "(told to the Drivers, banknotes pass at the Checkpoint)")
			check(_sim.boss.released and _sim.cash < cash, "(the bar goes up, for a price)")
		else:
			check(not _sim.boss.released, "told to the In-laws, banknotes do not raise the bar")
			check_near(_sim.cash, cash, 0.000001, "and he keeps them")
			check(GameData.as_bool(_event("pulled_over").get("refused")), "(the soldier refuses them)")

	# Each Snap costs 15 game minutes.
	for table_id: String in [BASE, "inlaws"]:
		_tell_to_first_leg(table_id, telling_seed)
		var clock: float = _sim.clock.minutes
		var tick: int = _sim.tick
		_events = []
		_snap()
		var driven: float = float(_sim.tick - tick) * DT * tuning.f("clock_scale") / 60.0
		check_eq(_count_events("snap"), 1, "(%s: a Snap)" % table_id)
		if table_id == BASE:
			check_near(_sim.clock.minutes - clock, driven, 0.000001, "(told to the Drivers, a Snap costs the Clock nothing)")
		else:
			check_near(_sim.clock.minutes - clock, driven + snap_minutes, 0.000001, "told to the In-laws, a Snap puts the Clock on by 15 minutes")
			check_near(GameData.as_float(_event("snap").get("minutes")), snap_minutes, 0.000001, "(the event says so)")
			_ticks(_ticks_in(tuning.f("snap_duration") + 0.5))
			clock = _sim.clock.minutes
			tick = _sim.tick
			_snap()
			driven = float(_sim.tick - tick) * DT * tuning.f("clock_scale") / 60.0
			check_near(_sim.clock.minutes - clock, driven + snap_minutes, 0.000001, "and so does the next: each Snap")

	# The stall itself keeps him out: asked to let the shady guy in (a save
	# from another Table says he was there), it does so for the Drivers and
	# not for the In-laws.
	for table_id: String in [BASE, "inlaws"]:
		_sim.stop.begin("fuel_station", 1, true, 1.0, TableRules.of(data, table_id))
		var in_the_shade: int = 0
		for offer: Dictionary in _sim.stop.offers_view():
			if GameData.as_bool(offer["shady"]):
				in_the_shade += 1
		if table_id == BASE:
			check(in_the_shade > 0, "(a stall asked to let the shady guy in has his %d Deals)" % in_the_shade)
		else:
			check_eq(in_the_shade, 0, "at the In-laws' Table the stall does not let him in, whoever asks")

	# "No contraband" is a rule by itself: where the shady guy does stand, he
	# has none to sell and refills none.
	var dry: TableRules = TableRules.new()
	dry.no_contraband = true
	for strict: bool in [false, true]:
		_tell(BASE, 1)
		_give("arak_flask", "cup_b")
		_item("arak_flask").supply = 0
		_sim.stop.begin("fuel_station", 1, true, 1.0, dry if strict else TableRules.new())
		var contraband: int = 0
		var deals: int = 0
		for offer: Dictionary in _sim.stop.offers_view():
			if GameData.as_bool(offer["shady"]):
				deals += 1
			if offer["kind"] != StopSim.SERVICE and offer["kind"] != StopSim.REPAIR \
					and GameData.as_bool(data.record("items", GameData.as_string(offer["id"])).get("contraband")):
				contraband += 1
		if strict:
			check(deals > 0, "(with no contraband alone, the shady guy still has his %d Deals)" % deals)
			check_eq(contraband, 0, "no contraband, by itself: he sells none and refills none")
		else:
			check(contraband > 0, "(by the base rules he refills the empty flask: %d offers of contraband)" % contraband)
	# And what he has not got yet: over a dozen nights the shady guy of the
	# base rules holds contraband out, and under the rule never.
	for strict: bool in [false, true]:
		var sold: int = 0
		for night: int in range(1, 13):
			_tell(BASE, night)
			_sim.stop.begin("fuel_station", RunGenerator.ACTS, true, 1.0, dry if strict else TableRules.new())
			for offer: Dictionary in _sim.stop.offers_view():
				if offer["kind"] == StopSim.ITEM and GameData.as_bool(data.record("items", GameData.as_string(offer["id"])).get("contraband")):
					sold += 1
		if strict:
			check_eq(sold, 0, "under the rule nothing he holds out on twelve nights is contraband")
		else:
			check(sold > 0, "(by the base rules he holds contraband out %d times on twelve nights)" % sold)


# --- T-TABLE-AUNTS -------------------------------------------------------------

## T-TABLE-AUNTS: The Aunts (11.2): Heavy floor +10 all night; prices +25%;
## he starts with a Thermos and seeds; heckles are Orders; unlocked by
## winning the In-laws' Table on time.
func test_table_aunts() -> void:
	_check_place("aunts", PackedStringArray(["ORDER"]))
	var rules: Dictionary = _rules("aunts")
	var more: float = GameData.as_float(rules.get("heavy_floor_add"))
	var dearer: float = GameData.as_float(rules.get("price_mult"))
	check_near(more, 10.0, 0.000001, "GDD 11.2: Heavy floor +10")
	check_near(dearer, 1.25, 0.000001, "prices +25%")
	check_eq(GameData.as_array(rules.get("start_items")), ["thermos", "seeds"], "he starts with a Thermos and seeds")

	# The cabin.
	var telling_seed: int = _seed_for("fuel_station")
	_tell("aunts", telling_seed)
	check_eq(_cabin(), PackedStringArray(["cigarettes", "seeds", "tea_glass", "thermos"]), "the starting cabin, and a Thermos and seeds")
	for id: String in ["thermos", "seeds"]:
		var item: ItemSim.Item = _item(id)
		if check(item != null, "(%s is in the cabin)" % id):
			check(GameData.as_array(_record(id).get("slots")).has(String(item.slot)), "%s lies in a slot of its own (%s)" % [id, item.slot])
			check_eq(item.supply, GameData.as_int(_supply_spec(id).get("uses")), "(full)")
	_tell(BASE, telling_seed)
	check(_item("thermos") == null and _item("seeds") == null, "(told to the Drivers he has neither)")

	# Heavy floor +10 in every act.
	for table_id: String in [BASE, "aunts"]:
		_tell_to_first_leg(table_id, telling_seed)
		for act: int in range(1, RunGenerator.ACTS + 1):
			if act > 1:
				_drive_on_to_act(act)
				_into_next_quiet_leg()
			_tick()
			var floor_now: float = tuning.fi("heavy_floor", act - 1) + (more if table_id == "aunts" else 0.0)
			check_near(_sim.heavy_floor(), floor_now, 0.000001, "%s, Act %d: the Heavy floor is %d" % [table_id, act, roundi(floor_now)])
			check_near(_sim.nerves.heavy_floor, floor_now, 0.000001, "(his Nerves are measured against it)")
	# It bites: at Nerves 5 in Act 1 he is Heavy at the Aunts' Table and not at the Drivers'.
	for table_id: String in [BASE, "aunts"]:
		_tell_to_first_leg(table_id, telling_seed)
		_sim.nerves.set_value(more * 0.5)
		_ticks(3)
		check_eq(_sim.nerves.heavy, table_id == "aunts", "%s: at %d Nerves in Act 1 he is %s" % [table_id, roundi(more * 0.5), "Heavy" if table_id == "aunts" else "not Heavy"])

	# Prices +25%: what is sold, what is refilled, what is repaired.
	var seen: Dictionary = {}
	for table_id: String in [BASE, "aunts"]:
		_tell_to_first_leg(table_id, telling_seed)
		var pack: ItemSim.Item = _item("cigarettes")
		pack.supply = 1
		_into_stall()
		seen[table_id] = [_prices(StopSim.ITEM), _prices(StopSim.RESTOCK)]
	var plain: Array = seen[BASE]
	var theirs: Array = seen["aunts"]
	for kind: int in 2:
		var base_prices: Dictionary = plain[kind]
		var aunt_prices: Dictionary = theirs[kind]
		check(not base_prices.is_empty(), "(the fuel station has %s)" % ("things to sell" if kind == 0 else "a refill for the pack"))
		for id: Variant in base_prices:
			if aunt_prices.has(id):
				check_near(GameData.as_float(aunt_prices[id]), roundf(GameData.as_float(base_prices[id]) * dearer), 0.000001,
						"%s: %s for the Aunts, %s for the Drivers" % [str(id), str(aunt_prices[id]), str(base_prices[id])])
	var fitter_seed: int = _seed_for("fitter")
	for table_id: String in [BASE, "aunts"]:
		_tell_to_first_leg(table_id, fitter_seed)
		_scrape()
		_into_stall()
		var repairs: Dictionary = _prices(StopSim.REPAIR)
		if check_eq(repairs.size(), 1, "(%s: one lamp, one repair on offer)" % table_id):
			var price: float = tuning.f("repair_price") * (dearer if table_id == "aunts" else 1.0)
			check_near(GameData.as_float(repairs.values()[0]), roundf(price), 0.000001, "%s: a repair is %d" % [table_id, roundi(price)])

	# After a Wreck the night told again is the Aunts' night again.
	_tell_to_first_leg("aunts", telling_seed)
	_sim.items.remove_item(_item("thermos"))
	var guard: int = _ticks_in(60.0)
	while not _sim.wrecked and guard > 0:
		guard -= 1
		_sim.car.x = _sim.car.guardrail_x()
		_sim.car.s = minf(_sim.car.s, _sim.leg.length - 400.0)
		_sim.step(_input)
	guard = _ticks_in(10.0)
	while _sim.wrecked and guard > 0:
		guard -= 1
		_sim.step(_input)
	check(_sim.run.retellings == 1 and not _sim.wrecked, "(a Wreck: the Telling is told again)")
	check_eq(_cabin(), PackedStringArray(["cigarettes", "seeds", "tea_glass", "thermos"]), "told again, he has his Thermos and seeds again")
	check_near(_sim.heavy_floor(), tuning.fi("heavy_floor", 0) + more, 0.000001, "and the Heavy floor is the Aunts' again")


# --- T-TABLE-GROOM -------------------------------------------------------------

## T-TABLE-GROOM: The Groom (11.2): he leaves at 22:45; any boss begun
## without a passenger starts with +20 Nerves; heckles are Dares, Doubts and
## Orders; unlocked by winning the Aunts' Table on time.
func test_table_groom() -> void:
	_check_place("groom", PackedStringArray(["DARE", "DOUBT", "ORDER"]))
	var late: float = GameData.as_float(_table("groom").get("depart_min"))
	var alone: float = GameData.as_float(_rules("groom").get("boss_alone_nerves"))
	check_near(late, 45.0, 0.000001, "GDD 11.2: he leaves at 22:45")
	check_near(alone, 20.0, 0.000001, "a boss begun without a passenger: +20 Nerves")

	var telling_seed: int = 11
	_tell("groom", telling_seed)
	check_eq(_sim.clock.text(), "22:45", "the Groom's night begins at 22:45")
	check_near(_sim.clock.minutes, late, 0.000001, "(45 game minutes of the night are gone)")
	check_near(GameData.as_float(_sim.snapshot()["night_share"]), late / _sim.clock.night_minutes(), 0.000001, "(the sky and the dashboard clock say so)")
	_tell(BASE, telling_seed)
	check_eq(_sim.clock.text(), "22:00", "(the Drivers' at 22:00)")

	# Every boss, with nobody in the seat and with somebody.
	for table_id: String in [BASE, "groom"]:
		for with_passenger: bool in [false, true]:
			_tell_to_first_leg(table_id, telling_seed)
			for act: int in range(1, RunGenerator.ACTS + 1):
				if act > 1:
					_drive_on_to_boss_stop()
					_leave_stop()
				if with_passenger and not _sim.passengers.aboard():
					_sim.board("drummer")
					_sim.passengers.drumming = false
				# At the end of the act's last leg, a tick before the boss.
				var guard: int = 40000
				_input.clear()
				var before: float = 0.0
				while _sim.run.stage != RunState.Stage.BOSS and guard > 0:
					guard -= 1
					if _sim.stopped:
						_leave_stop()
						continue
					_sim.car.x = _sim.car.lane_center(1)
					if _sim.leg.active and _sim.car.s < _sim.leg.length - 2.0:
						_sim.car.s = _sim.leg.length - 1.0
					_sim.nerves.set_value(40.0)
					before = _sim.nerves.value
					_sim.step(_input)
				_sim.in_encounter = true
				var gained: float = _sim.nerves.value - before
				var boss_id: String = _sim.run.boss
				# (The leg that ends there was a clean one: its own -10.)
				var wanted: float = alone if table_id == "groom" and not with_passenger else 0.0
				check_near(gained - tuning.f("clean_leg_nerves"), wanted, 0.000001, "%s, %s, %s: the boss begins with %+d Nerves" % [
						table_id, boss_id, "somebody beside him" if with_passenger else "alone", roundi(wanted)])
	# Told again after a Wreck, he leaves at 22:45 again.
	_tell_to_first_leg("groom", telling_seed)
	var guard: int = _ticks_in(60.0)
	while not _sim.wrecked and guard > 0:
		guard -= 1
		_sim.car.x = _sim.car.guardrail_x()
		_sim.car.s = minf(_sim.car.s, _sim.leg.length - 400.0)
		_sim.step(_input)
	guard = _ticks_in(10.0)
	while _sim.wrecked and guard > 0:
		guard -= 1
		_sim.step(_input)
	check(_sim.run.retellings == 1, "(a Wreck: the Telling is told again)")
	check(_sim.clock.minutes >= late and _sim.clock.minutes < late + 0.5, "told again, the night begins at 22:45 again (%s)" % _sim.clock.text())


# --- T-TABLE-CHILDREN ----------------------------------------------------------

## Along the guardrail, kept well inside the stretch, until every lamp is lit.
func _wreck() -> void:
	_input.clear()
	var guard: int = _ticks_in(90.0)
	while not _sim.wrecked and guard > 0:
		guard -= 1
		_sim.car.x = _sim.car.guardrail_x()
		_sim.car.s = clampf(_sim.car.s, 50.0, maxf(_sim.leg.length - 400.0, 50.0))
		_sim.step(_input)
		for event: Dictionary in _sim.drain_events():
			_events.append(event)
	check(_sim.wrecked, "(every lamp is lit: a Wreck)")


## The Table objects for wreck_to_wheel; then the Telling goes on.
func _sit_out_the_cut() -> int:
	_input.clear()
	var ticks: int = 0
	var guard: int = _ticks_in(10.0)
	while _sim.wrecked and guard > 0:
		guard -= 1
		ticks += 1
		_sim.step(_input)
		for event: Dictionary in _sim.drain_events():
			_events.append(event)
	_sim.in_encounter = true
	return ticks


## T-TABLE-CHILDREN: The Children (11.2): one free rewind, the first Wreck
## returns to the start of that leg; prices -25%; heckles are Twists and the
## Fib; unlocked from the start.
func test_table_children() -> void:
	_check_place("children", PackedStringArray(["TWIST", "FIB"]))
	var rules: Dictionary = _rules("children")
	var cheaper: float = GameData.as_float(rules.get("price_mult"))
	check_eq(GameData.as_int(rules.get("free_rewinds")), 1, "GDD 11.2: one free rewind")
	check_near(cheaper, 0.75, 0.000001, "prices -25%")
	check_eq(GameData.as_array(Save.default_profile()["tables_unlocked"]), Array(TableRules.open_at_start(data)), "(a new profile has open what the data opens from the start)")

	# Prices -25%: what is sold, what is refilled, what is repaired.
	var telling_seed: int = _seed_for("fuel_station")
	var seen: Dictionary = {}
	for table_id: String in [BASE, "children"]:
		_tell_to_first_leg(table_id, telling_seed)
		var pack: ItemSim.Item = _item("cigarettes")
		pack.supply = 1
		_into_stall()
		seen[table_id] = [_prices(StopSim.ITEM), _prices(StopSim.RESTOCK)]
	var plain: Array = seen[BASE]
	var theirs: Array = seen["children"]
	for kind: int in 2:
		var base_prices: Dictionary = plain[kind]
		var child_prices: Dictionary = theirs[kind]
		check(not base_prices.is_empty(), "(the fuel station has %s)" % ("things to sell" if kind == 0 else "a refill for the pack"))
		for id: Variant in base_prices:
			if child_prices.has(id):
				check_near(GameData.as_float(child_prices[id]), roundf(GameData.as_float(base_prices[id]) * cheaper), 0.000001,
						"%s: %s for the Children, %s for the Drivers" % [str(id), str(child_prices[id]), str(base_prices[id])])
	var fitter_seed: int = _seed_for("fitter")
	_tell_to_first_leg("children", fitter_seed)
	_scrape()
	_into_stall()
	var repairs: Dictionary = _prices(StopSim.REPAIR)
	if check_eq(repairs.size(), 1, "(one lamp, one repair on offer)"):
		check_near(GameData.as_float(repairs.values()[0]), roundf(tuning.f("repair_price") * cheaper), 0.000001, "a repair is %d" % roundi(tuning.f("repair_price") * cheaper))

	# The free rewind, on the second leg of the night, after a stop.
	_tell_to_first_leg("children", telling_seed)
	check_eq(_sim.rewinds_left, 1, "the Children's night begins with one rewind")
	_scrape()
	_into_stall()
	var saved: Dictionary = _sim.checkpoint
	check_eq(GameData.as_int(saved.get("rewinds"), -1), 1, "(the save at a stop says it is still his)")
	_leave_stop()
	_into_next_quiet_leg()
	var seed_then: int = _sim.run.seed
	var leg_then: String = _sim.leg.leg_id
	var legs_then: int = _sim.run.legs_done
	var cash_then: float = _sim.cash
	var clock_then: float = _sim.clock.minutes
	var nerves_then: float = _sim.nerves.value
	var lamps_then: int = _sim.faults.lamps
	var faults_then: Array[StringName] = _sim.faults.active.duplicate()
	var cabin_then: PackedStringArray = _cabin()
	var pack_then: int = _item("cigarettes").supply
	check(lamps_then == 1 and legs_then == 1, "(he is on the night's second leg with one lamp lit)")
	# He makes a mess of it.
	_run(8.0)
	_sim.cash += 23.0
	_item("cigarettes").supply = 0
	_give("beads")
	_events = []
	_wreck()
	var objection: Dictionary = _event("wreck")
	check_eq(GameData.as_string(objection.get("table")), "children", "the Table objects")
	check(GameData.as_bool(objection.get("rewind")), "(and the Wreck says it will be taken back)")
	var cut: int = _sit_out_the_cut()
	check(absi(cut - _ticks_in(tuning.f("wreck_to_wheel"))) <= 1, "within wreck_to_wheel (%.2f s)" % (float(cut) * DT))
	check(not _sim.wrecked and _sim.run.active, "the Telling goes on")
	check_eq(_sim.run.retellings, 0, "it is not told again from Baghdad")
	check_eq(_sim.run.seed, seed_then, "(the same night)")
	check(_sim.run.stage == RunState.Stage.LEG and _sim.run.legs_done == legs_then and _sim.leg.leg_id == leg_then, "he is on the same leg (%s)" % leg_then)
	check(_sim.car.s < 20.0, "at its start (%.1f m in)" % _sim.car.s)
	check_eq(_sim.faults.lamps, lamps_then, "with the lamps that were lit when it began")
	check_eq(_sim.faults.active, faults_then, "(the same faults)")
	check_near(_sim.cash, cash_then, 0.000001, "the cash he had then")
	check_near(_sim.clock.minutes, clock_then, tuning.f("clock_scale") / 60.0 * float(cut + 2) * DT + 0.01, "the hour it was then (%s)" % _sim.clock.text())
	check(_sim.clock.minutes < clock_then + 0.2, "(not the hour of the Wreck)")
	check_near(_sim.nerves.value, nerves_then, 0.5, "his Nerves as they were")
	check_eq(_cabin(), cabin_then, "and the cabin as it was")
	check_eq(_item("cigarettes").supply, pack_then, "(the pack as full as it was)")
	check_eq(_count_events("leg_started", "leg", leg_then), 1, "the leg is announced again")
	check_eq(_sim.rewinds_left, 0, "the rewind is spent")
	check(_sim.checkpoint == saved, "what the last stop saved is still the night he is telling")
	# Driven on, it is the same road: its stall saves a night with no rewind left.
	var plan: Dictionary = RunGenerator.plan(data, _sim.run.branch, _sim.run.act)
	check_eq(GameData.as_string(plan.get("leg")), leg_then, "(the same leg of the same fork)")
	_into_stall()
	check_eq(GameData.as_int(_sim.checkpoint.get("rewinds"), -1), 0, "the next stop's save says the rewind is spent")
	var loaded: DriveSim = DriveSim.new(fresh_data())
	check(loaded.restore(_sim.checkpoint) and loaded.rewinds_left == 0, "and a night loaded from it has none")
	var early: DriveSim = DriveSim.new(fresh_data())
	check(early.restore(saved) and early.rewinds_left == 1, "(one loaded from the earlier save still has it)")
	# The second Wreck is told again from Baghdad, like anybody's.
	_leave_stop()
	_into_next_quiet_leg()
	_events = []
	_wreck()
	check(not GameData.as_bool(_event("wreck").get("rewind")), "the second Wreck is not taken back")
	_sit_out_the_cut()
	check(_sim.run.retellings == 1 and _sim.run.seed != seed_then and _sim.run.stage == RunState.Stage.APPROACH and _sim.faults.lamps == 0,
			"it is told again from Baghdad")
	check_eq(_sim.rewinds_left, 1, "and the night told again has its one rewind")

	# In a boss the rewind returns to the start of the boss.
	_tell_to_first_leg("children", telling_seed)
	_drive_on_to_boss()
	var boss_then: String = _sim.run.boss
	var boss_cash: float = _sim.cash
	_run(5.0)
	_sim.cash += 11.0
	_events = []
	_wreck()
	check(GameData.as_bool(_event("wreck").get("rewind")), "a Wreck in the boss, with the rewind unspent, is taken back")
	_sit_out_the_cut()
	check(_sim.run.stage == RunState.Stage.BOSS and _sim.run.boss == boss_then and _sim.boss.active and _sim.run.retellings == 0, "he is at the %s again" % boss_then)
	check(_sim.car.s < 20.0 and _sim.faults.lamps == 0, "at its start, with no lamp lit")
	check_near(_sim.cash, boss_cash, 0.000001, "and the cash he came to it with")
	check_eq(_count_events("boss_started", "boss", boss_then), 1, "(the boss is announced again)")

	# Before any leg has begun there is nothing to return to: Baghdad.
	_tell("children", telling_seed)
	_events = []
	_wreck()
	check(not GameData.as_bool(_event("wreck").get("rewind")), "a Wreck on the road out of Baghdad, before the first fork, is told again from Baghdad")
	_sit_out_the_cut()
	check(_sim.run.retellings == 1 and _sim.rewinds_left == 1, "(and the rewind is still his)")

	# Told to the Drivers, the first Wreck is Baghdad again.
	_tell_to_first_leg(BASE, telling_seed)
	_into_stall()
	_leave_stop()
	_into_next_quiet_leg()
	_events = []
	_wreck()
	check(not GameData.as_bool(_event("wreck").get("rewind")), "told to the Drivers, no Wreck is taken back")
	_sit_out_the_cut()
	check(_sim.run.retellings == 1 and _sim.run.stage == RunState.Stage.APPROACH, "(Baghdad again)")


# --- T-TABLE-UNCLES ------------------------------------------------------------

## T-TABLE-UNCLES: The Uncles (11.2): a Patrol leg in every act; Checkpoint
## Suspicion gains x1.25; heckles are Doubts; unlocked by winning the
## Drivers' Table on time.
func test_table_uncles() -> void:
	_check_place("uncles", PackedStringArray(["DOUBT"]))
	var rules: Dictionary = _rules("uncles")
	var harder: float = GameData.as_float(rules.get("checkpoint_suspicion_mult"))
	check(GameData.as_bool(rules.get("patrol_every_act")), "GDD 11.2: a Patrol leg in every act")
	check_near(harder, 1.25, 0.000001, "Checkpoint Suspicion gains x1.25")
	var uncles: TableRules = TableRules.of(data, "uncles")
	var patrol: String = RunGenerator.PATROL_LEG
	check(data.has_record("legs", patrol), "(a Patrol leg is a leg of legs.json)")

	# Whichever way he goes at the forks, every act has a Patrol leg; told to
	# the Drivers, most acts need not.
	var without: int = 0
	var places: Dictionary = {}
	for telling_seed: int in range(1, 61):
		for act: int in range(1, RunGenerator.ACTS + 1):
			var place: int = RunGenerator.patrol_place(telling_seed, act)
			places[place] = true
			var theirs: Array = []
			var plain: Array = []
			for leg_index: int in RunGenerator.LEGS_PER_ACT:
				theirs.append(RunGenerator.fork(data, telling_seed, act, leg_index, uncles))
				plain.append(RunGenerator.fork(data, telling_seed, act, leg_index))
			var sure: bool = true
			var plain_sure: bool = true
			for ways: int in 8:
				var met: bool = false
				var plain_met: bool = false
				for leg_index: int in RunGenerator.LEGS_PER_ACT:
					var side: int = (ways >> leg_index) & 1
					met = met or GameData.as_string(GameData.as_dict(GameData.as_array(theirs[leg_index])[side]).get("leg")) == patrol
					plain_met = plain_met or GameData.as_string(GameData.as_dict(GameData.as_array(plain[leg_index])[side]).get("leg")) == patrol
				sure = sure and met
				plain_sure = plain_sure and plain_met
			if not sure:
				fail("seed %d, act %d: there is a way through the act with no Patrol leg" % [telling_seed, act])
			if not plain_sure:
				without += 1
			# Nothing else about the night is different: the other forks are
			# the Drivers', and at the Patrol's fork the stops and the seeds.
			for leg_index: int in RunGenerator.LEGS_PER_ACT:
				if leg_index != place:
					if JSON.stringify(theirs[leg_index]) != JSON.stringify(plain[leg_index]):
						fail("seed %d, act %d, fork %d: a fork without the Patrol differs from the Drivers'" % [telling_seed, act, leg_index])
					continue
				for side: int in RunGenerator.BRANCHES:
					var branch: Dictionary = GameData.as_dict(GameData.as_array(theirs[leg_index])[side])
					var base: Dictionary = GameData.as_dict(GameData.as_array(plain[leg_index])[side])
					if branch["leg"] != patrol or branch["stop"] != base["stop"] or branch["seed"] != base["seed"]:
						fail("seed %d, act %d: the Patrol's fork must keep the Drivers' stops and seeds" % [telling_seed, act])
					if not is_equal_approx(GameData.as_float(branch["par_s"]), GameData.as_float(data.record("legs", patrol).get("par_s"))):
						fail("seed %d, act %d: the Patrol leg must have a Patrol leg's par" % [telling_seed, act])
					var modifier: String = GameData.as_string(branch["modifier"])
					if not modifier.is_empty() and not GameData.as_array(data.record("legs", patrol).get("modifiers_allowed")).has(modifier):
						fail("seed %d, act %d: the Patrol leg has a modifier a Patrol leg may not have (%s)" % [telling_seed, act, modifier])
	check(true, "in 60 nights every way through every act passes a Patrol leg")
	check_eq(places.size(), RunGenerator.LEGS_PER_ACT, "(its place in the act is drawn: first, second or third)")
	check(without >= 60, "told to the Drivers, %d of those 180 acts can be driven without one" % without)

	# Driven: each act's Patrol leg is a Patrol leg, the police on it.
	for act: int in range(1, RunGenerator.ACTS + 1):
		_tell("uncles", 7)
		if act > 1:
			_drive_on_to_act(act)
		var watched: bool = false
		var met: bool = false
		for _leg: int in RunGenerator.LEGS_PER_ACT:
			_into_next_quiet_leg()
			if _sim.leg.leg_id != patrol:
				continue
			met = true
			# The leg as it was generated, with its police.
			_sim.begin_leg(RunGenerator.plan(data, _sim.run.branch, _sim.run.act))
			var guard: int = _ticks_in(60.0)
			while not _sim.suspicion.watching and _sim.car.s < _sim.leg.length - 600.0 and guard > 0:
				guard -= 1
				_tick()
			watched = _sim.suspicion.watching
			break
		check(met, "Act %d of a night told to the Uncles has a Patrol leg on the road he takes" % act)
		check(watched, "and its police watch him")

	# The Checkpoint: every gain of Suspicion is a quarter more.
	var numbers: Dictionary = GameData.as_dict(data.record("bosses", "checkpoint").get("checkpoint"))
	var left_out: float = GameData.as_float(numbers.get("contraband_suspicion"))
	var delay: float = GameData.as_float(numbers.get("delay_suspicion"))
	for table_id: String in [BASE, "uncles"]:
		var mult: float = harder if table_id == "uncles" else 1.0
		_tell_to_first_leg(table_id, 7)
		_tick()
		check_near(_sim.suspicion.gain_mult, 1.0, 0.000001, "%s: on a leg Suspicion gains are plain" % table_id)
		_drive_on_to_boss()
		_empty_the_queue()
		_tick()
		check_near(_sim.suspicion.gain_mult, mult, 0.000001, "%s: at the Checkpoint they are x%s" % [table_id, str(mult)])
		_give("arak_flask", "cup_b")
		check(_stand_at_the_bar(), "(first in line)")
		_until_checkpoint_phase(BossSim.PAPERS, GameData.as_float(numbers.get("stow_s")) + 1.0)
		check_near(_sim.suspicion.value, left_out * mult, 0.000001, "%s: a flask left out is +%s" % [table_id, str(left_out * mult)])
		_ticks(_ticks_in(GameData.as_float(numbers.get("delay_every_s")) + 0.1))
		check_near(_sim.suspicion.value, minf((left_out + delay) * mult, _sim.suspicion.maximum()), 0.000001, "%s: and 5 s of delay +%s" % [table_id, str(delay * mult)])
	# With the Conscript's uniform both count.
	_tell_to_first_leg("uncles", 7)
	_sim.board("conscript")
	_drive_on_to_boss()
	_empty_the_queue()
	_tick()
	check_near(_sim.suspicion.gain_mult, harder * GameData.as_float(GameData.as_dict(data.record("passengers", "conscript").get("always")).get("suspicion_gain_mult")), 0.000001,
			"the Conscript's uniform halves what the Uncles' Table has made of it")


# --- T-TABLE-NOOR --------------------------------------------------------------

## Drives on to the end of the stretch he is on and into what follows, in
## the lane on `side` of the road (0 left, 1 right), until a leg or a boss
## has begun; a leg is begun again with nothing on its road.
func _on_to_the_next(side: int) -> void:
	var legs_done: int = _sim.run.legs_done
	var was: int = _sim.run.stage
	var act: int = _sim.run.act
	var guard: int = _ticks_in(120.0)
	_input.clear()
	while guard > 0:
		guard -= 1
		var stage: int = _sim.run.stage
		if stage == RunState.Stage.BOSS and was != RunState.Stage.BOSS:
			break
		if stage == RunState.Stage.LEG and (was != RunState.Stage.LEG or _sim.run.legs_done > legs_done or _sim.run.act != act):
			break
		_sim.car.x = _sim.car.lane_center(0 if side == 0 else _sim.car.lanes - 1)
		if _sim.leg.active and _sim.car.s < _sim.leg.length - 2.0:
			_sim.car.s = _sim.leg.length - 1.0
		_sim.step(_input)
		for event: Dictionary in _sim.drain_events():
			_events.append(event)
	if _sim.run.stage == RunState.Stage.LEG:
		var plan: Dictionary = RunGenerator.plan(data, _sim.run.branch, _sim.run.act)
		for key: String in ["spawns", "hazards", "curves", "gusts", "zones"]:
			plan[key] = []
		for key: String in ["flock", "melons", "motorcade"]:
			plan[key] = {}
		_sim.gate.reset(3)
		_sim.begin_leg(plan)
	_sim.in_encounter = true
	for event: Dictionary in _sim.drain_events():
		_events.append(event)


## Ticks of the road from where he is to the end of the stretch on which the
## snapshot shows a fork ahead: its gore, or its sign.
func _ticks_with_a_fork_shown() -> int:
	var shown: int = 0
	var guard: int = _ticks_in(200.0)
	var stage: int = _sim.run.stage
	var legs_done: int = _sim.run.legs_done
	_input.clear()
	while _sim.run.stage == stage and _sim.run.legs_done == legs_done and guard > 0:
		guard -= 1
		var shot: Dictionary = _sim.snapshot()
		var signed: bool = false
		var signs: Array[Dictionary] = shot["signs"]
		for sign: Dictionary in signs:
			signed = signed or GameData.as_string(sign.get("kind")) == "fork"
		if signed or GameData.as_float(shot["gore_ahead"]) >= 0.0:
			shown += 1
		_sim.car.x = _sim.car.lane_center(1)
		_sim.step(_input)
	_sim.drain_events()
	return shown


## T-TABLE-NOOR: Noor (11.2): one fixed road with no forks, in the order
## Open road, Rush, Rain, Checkpoint; Night blackout, Patrol, Roadworks,
## Storm; Tailgater, Two-lane, Motorcade, Dawn; the starting cabin plus beads
## and a full pack; no shops but tea and repairs; no heckles; the Student
## waits at the second stop of Act 2; unlocked by winning the Groom's Table
## on time.
func test_table_noor() -> void:
	_check_place("noor", PackedStringArray())
	var rules: Dictionary = _rules("noor")
	var order: Array = [["open_road", "rush", "rain"], ["night", "patrol", "roadworks"], ["tailgater", "two_lane", "motorcade"]]
	var bosses: PackedStringArray = ["checkpoint", "storm", "dawn"]
	check_eq(GameData.as_array(rules.get("road")), order, "GDD 11.2: Open road, Rush, Rain; Night blackout, Patrol, Roadworks; Tailgater, Two-lane, Motorcade")
	for act: int in range(1, RunGenerator.ACTS + 1):
		check_eq(GameData.as_string(RunGenerator.boss_of(data, act).get("id")), bosses[act - 1], "Act %d ends in the %s" % [act, bosses[act - 1]])
	var noor: TableRules = TableRules.of(data, "noor")
	check(noor.fixed_road() and noor.seed != TableRules.NO_SEED, "(the road is fixed, and so is its seed)")

	# One road, whatever is asked for.
	var seeds: Array[int] = []
	for asked: int in [1, 2, 987654]:
		_tell("noor", asked)
		seeds.append(_sim.run.seed)
		check_eq(_sim.run.branches.size(), 1, "(asked for seed %d: one leg lies ahead, not two)" % asked)
	check(seeds[0] == noor.seed and seeds[1] == noor.seed and seeds[2] == noor.seed, "whatever seed is asked for, the night is the one night")

	# No fork is shown, on the road out of Baghdad or at a leg's end; told
	# to the Drivers one is.
	for table_id: String in [BASE, "noor"]:
		_tell(table_id, 5)
		var on_the_way: int = _ticks_with_a_fork_shown()
		_sim.car.s = _sim.leg.length - 800.0
		var at_legs_end: int = _ticks_with_a_fork_shown()
		if table_id == BASE:
			check(on_the_way > 0 and at_legs_end > 0, "(told to the Drivers a fork is signed and its gore drawn: %d and %d ticks)" % [on_the_way, at_legs_end])
		else:
			check_eq(on_the_way + at_legs_end, 0, "told to Noor, no fork is signed and no gore is drawn")

	# The whole night, twice, on either side of the road: the same legs in
	# the fixed order, with no modifier, and the three bosses.
	var nights: Array[PackedStringArray] = []
	var leg_seeds: Array[Array] = []
	for night: int in 2:
		_tell("noor", 100 + night)
		_events = []
		var met: PackedStringArray = []
		var their_seeds: Array = []
		for act: int in range(1, RunGenerator.ACTS + 1):
			for leg_index: int in RunGenerator.LEGS_PER_ACT:
				_on_to_the_next((leg_index + night) % 2)
				met.append(_sim.leg.leg_id)
				their_seeds.append(GameData.as_int(_sim.run.branch.get("seed")))
				if night == 0:
					check_eq(GameData.as_string(_sim.run.branch.get("modifier")), "", "(%s: no modifier)" % _sim.leg.leg_id)
			_on_to_the_next(night)
			met.append(_sim.run.boss)
			_drive_on_to_boss_stop()
			_leave_stop()
		nights.append(met)
		leg_seeds.append(their_seeds)
		check_eq(_count_events("fork_taken"), 0, "(night %d: no fork was taken: there is none)" % (night + 1))
		check_eq(_sim.run.stage, RunState.Stage.ARRIVAL, "(night %d: then the Arrival)" % (night + 1))
	var fixed: PackedStringArray = []
	for act: int in RunGenerator.ACTS:
		for leg_id: Variant in GameData.as_array(order[act]):
			fixed.append(str(leg_id))
		fixed.append(bosses[act])
	check_eq(nights[0], fixed, "the night is %s" % ", ".join(fixed))
	check_eq(nights[1], fixed, "on the other side of the road, and asked for under another seed, it is the same night")
	check_eq(leg_seeds[0], leg_seeds[1], "(the same legs to the seed)")

	# The cabin: what was really there.
	_tell("noor", 1)
	check_eq(_cabin(), PackedStringArray(["beads", "cigarettes", "tea_glass"]), "the starting cabin plus beads")
	var uses: int = GameData.as_int(_supply_spec("cigarettes").get("uses"))
	check_eq(_item("cigarettes").supply, uses, "and a full pack (%d)" % uses)
	_tell(BASE, 1)
	check(_item("cigarettes").supply < uses and _item("beads") == null, "(told to the Drivers: a pack of %d and no beads)" % _item("cigarettes").supply)

	# Every stop of the night: tea or repairs, nothing sold, nobody in the
	# shade, and at the second stop of Act 2 the Student.
	var stops: Array = GameData.as_array(rules.get("stops"))
	_tell("noor", 1)
	var sold: int = 0
	var shady: int = 0
	var teas: int = 0
	var repairs: int = 0
	var waiting: PackedStringArray = []
	for act: int in range(1, RunGenerator.ACTS + 1):
		for leg_index: int in RunGenerator.LEGS_PER_ACT:
			_on_to_the_next(1)
			var stop_id: String = GameData.as_string(GameData.as_array(stops[act - 1])[leg_index])
			var service: String = GameData.as_string(data.record("stops", stop_id).get("service"))
			check(service == "tea" or service == "repair", "(Act %d, stop %d is a %s: tea or repairs)" % [act, leg_index + 1, stop_id])
			if service == "repair":
				_scrape()
			_sim.nerves.set_value(80.0)
			_events = []
			_into_stall()
			check_eq(_sim.run.stop, stop_id, "Act %d, stop %d: the %s" % [act, leg_index + 1, stop_id])
			if GameData.as_bool(_event("stop_entered").get("shady")):
				shady += 1
			for offer: Dictionary in _offers():
				if offer["kind"] == StopSim.ITEM or offer["kind"] == StopSim.RESTOCK or GameData.as_bool(offer["shady"]):
					sold += 1
			if service == "tea":
				teas += 1
				check_near(_sim.nerves.value, GameData.as_float(data.record("stops", stop_id).get("nerves_to")), 0.000001, "(tea: his Nerves are set to 30)")
			else:
				repairs += 1
				var mend: Dictionary = {}
				for offer: Dictionary in _offers():
					if offer["kind"] == StopSim.REPAIR:
						mend = offer
				if check(not mend.is_empty(), "(the fitter offers to mend the lamp that is lit)"):
					_sim.cash = 100.0
					_tap_at(GameData.as_string(mend["anchor"]))
					check_eq(_sim.faults.lamps, 0, "(and mends it)")
			var who: String = GameData.as_string(_sim.snapshot()["hitcher"])
			if not who.is_empty():
				waiting.append("%d.%d %s" % [act, leg_index + 1, who])
				_tap_at("passenger_door")
				check_eq(_sim.passengers.id, who, "(a TAP on the door: she gets in)")
			_leave_stop()
		_on_to_the_next(1)
		_drive_on_to_boss_stop()
		var picks: int = 0
		var services: PackedStringArray = []
		for offer: Dictionary in _offers():
			if offer["kind"] == StopSim.SERVICE:
				services.append(GameData.as_string(offer["id"]))
			elif offer["kind"] == StopSim.ITEM or offer["kind"] == StopSim.RESTOCK:
				picks += 1
		services.sort()
		check_eq(picks, 0, "after the %s: nothing to pick" % bosses[act - 1])
		check_eq(services, PackedStringArray(["fitter", "tea_stall"]), "and the services he may choose from are tea and repairs")
		check(GameData.as_string(_sim.snapshot()["hitcher"]).is_empty(), "(nobody waits there)")
		_leave_stop()
	check(teas > 0 and repairs > 0 and teas + repairs == RunGenerator.ACTS * RunGenerator.LEGS_PER_ACT, "(nine stops: %d tea stalls and %d fitters)" % [teas, repairs])
	check_eq(sold, 0, "at no stop of Noor's night is anything sold or refilled")
	check_eq(shady, 0, "and the shady guy is at none of them")
	check_eq(waiting, PackedStringArray(["2.2 student"]), "the Student waits at the second stop of Act 2, and nobody anywhere else")
	check_eq(GameData.as_array(rules.get("hitchers")).size(), 1, "(the Table names her alone)")

	# A Wreck on the true night: Baghdad again (no rewind is hers to give),
	# and the same road, to the seed. "A fixed course to master."
	_tell_to_first_leg("noor", 1)
	var first_leg: Dictionary = _sim.run.branch.duplicate(true)
	_wreck()
	_sit_out_the_cut()
	check_eq(_sim.run.retellings, 1, "a Wreck at Noor's Table: the night is told again from Baghdad")
	check_eq(_sim.run.seed, noor.seed, "and it is the same night: its seed is the Table's")
	_into_next_quiet_leg()
	check_eq(_sim.run.branch, first_leg, "(its first leg is the same leg, to the seed)")
	_tell_to_first_leg(BASE, 1)
	var told_first: int = _sim.run.seed
	_wreck()
	_sit_out_the_cut()
	check(_sim.run.seed != told_first, "(told to the Drivers, a Wreck draws another night)")

	# The stall keeps Noor's rule itself: a stop that restocks, asked for at
	# her Table, holds nothing out and refills nothing, though his pack is
	# half empty.
	for table_id: String in [BASE, "noor"]:
		_tell(table_id, 1)
		_item("cigarettes").supply = 1
		_sim.stop.begin("fuel_station", 1, false, 1.0, TableRules.of(data, table_id))
		var held_out: int = 0
		for offer: Dictionary in _sim.stop.offers_view():
			if offer["kind"] == StopSim.ITEM or offer["kind"] == StopSim.RESTOCK:
				held_out += 1
		if table_id == BASE:
			check(held_out > 0, "(told to the Drivers a fuel station holds out %d things, the refill among them)" % held_out)
		else:
			check_eq(held_out, 0, "at Noor's Table even a fuel station sells nothing and refills nothing")
