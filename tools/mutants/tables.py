"""Mutants of the seven Tables' rules (GDD 11.2) for the T-TABLE tests.
    python3 tools/mutants.py T-TABLE tools/mutants/tables.py
"""
D = 'src/core/drive_sim.gd'
G = 'src/core/run_generator.gd'
R = 'src/core/run_state.gd'
S = 'src/core/stop_sim.gd'
T = 'src/core/table_rules.gd'
MUTANTS = [
 (D, '\tclock.add_minutes(table.depart_min)\n', '', 'every Table leaves at 22:00'),
 (D, '\tfor item_id: String in table.start_items:\n\t\tgive_item(StringName(item_id))\n', '', 'no Table adds to the cabin'),
 (D, '\tfor item_id: String in table.full_supplies:\n\t\tgive_item(StringName(item_id))\n', '', 'no pack starts full'),
 (D, '\trewinds_left = table.free_rewinds\n', '\trewinds_left = 0\n', 'nobody has a rewind'),
 (D, '\t\tif _can_rewind():\n\t\t\t_rewind()\n\t\telse:\n\t\t\t_retell()\n', '\t\t_retell()\n', 'a rewind is Baghdad again'),
 (D, '\tvar left: int = rewinds_left - 1\n', '\tvar left: int = rewinds_left\n', 'the rewind is never spent'),
 (D, '\tcheckpoint = saved\n\trewinds_left = left\n', '\tcheckpoint = {}\n\trewinds_left = left\n', 'a rewind forgets the last save'),
 # Not a mutant: keeping the leg's start with no rewind left changes nothing
 # (_can_rewind asks for a rewind too); the condition only saves the work.
 (D, '\t\t"rewinds": rewinds_left,\n', '', 'the save does not hold the rewind'),
 (D, '\trewinds_left = GameData.as_int(telling.get("rewinds"))\n', '\trewinds_left = table.free_rewinds\n', 'a loaded night has its rewind back'),
 (D, '"rewind": run.active and _can_rewind()})', '"rewind": false})', 'the Wreck never says it is taken back'),
 (D, '\treturn base + heavy_floor_bonus + table.heavy_floor_add + effects.total(HEAVY_FLOOR)', '\treturn base + heavy_floor_bonus + effects.total(HEAVY_FLOOR)', 'no Table raises the Heavy floor'),
 (D, '\t\tstop.begin(run.stop, run.act, shady, table.price_mult, table)\n', '\t\tstop.begin(run.stop, run.act, shady, 1.0, table)\n', 'every Table pays the same prices'),
 (D, '\t\tstop.begin(run.stop, run.act, shady, table.price_mult, table)\n', '\t\tstop.begin(run.stop, run.act, shady, table.price_mult)\n', 'the stop does not know the Table'),
 (D, '\t_shady_here = _leg_lamps_lit == 0 and table.deals_offered()', '\t_shady_here = _leg_lamps_lit == 0', 'the shady guy comes to every Table'),
 (D, '\t\tif cash < price or table.no_bribes:\n', '\t\tif cash < price:\n', 'the soldier takes banknotes at every Table'),
 (D, '\t\tif cash < cost or table.no_bribes:\n', '\t\tif cash < cost:\n', 'the officer takes banknotes at every Table'),
 (D, '"can_bribe": cash >= bribe() and not table.no_bribes,', '"can_bribe": cash >= bribe(),', 'the officer always says he can be bribed'),
 (D, '\t\tclock_minutes_owed += table.snap_minutes\n\t\tclock.add_minutes(table.snap_minutes)\n', '\t\tclock_minutes_owed += table.snap_minutes\n', 'a Snap costs the Clock nothing'),
 (D, '\tif table.boss_alone_nerves != 0.0 and not passengers.aboard():', '\tif table.boss_alone_nerves != 0.0:', 'a boss with a passenger frays him too'),
 (D, '\t\tnerves.add(table.boss_alone_nerves)\n', '\t\tpass\n', 'a boss alone costs nothing'),
 (D, '\t\tgain *= table.checkpoint_suspicion_mult\n', '\t\tgain *= 1.0\n', 'the Checkpoint is as lenient at every Table'),
 (D, '\tif boss.kind == BossSim.CHECKPOINT:\n\t\tgain *= table.checkpoint_suspicion_mult\n', '\tgain *= table.checkpoint_suspicion_mult\n', 'the Uncles make every Patrol harder too'),
 (D, '"gore_ahead": leg.length - car.s if run.active and run.splits_ahead() and leg.active else -1.0,', '"gore_ahead": leg.length - car.s if run.active and run.fork_ahead() and leg.active else -1.0,', 'a gore is drawn on a fixed road'),
 (D, '\tif forked:\n\t\t_emit("fork_taken", {', '\tif true:\n\t\t_emit("fork_taken", {', 'a fork is taken on a fixed road'),
 (D, '\tif table.places_hitchers():\n', '\tif false:\n', 'hitchers are drawn at Noor\'s Table'),
 (D, '\tvar seed_told: int = table.seed if table.seed != TableRules.NO_SEED else telling_seed', '\tvar seed_told: int = telling_seed', 'a fixed road takes the seed asked for'),
 (G, '\tif rules != null and rules.fixed_road():', '\tif false:', 'a fixed road forks'),
 (G, '\t\t\t\t"modifier": "",\n\t\t\t\t"seed": leg_seed(telling_seed, act, leg_index, 0),', '\t\t\t\t"modifier": "potholes",\n\t\t\t\t"seed": leg_seed(telling_seed, act, leg_index, 0),', 'a fixed road has modifiers'),
 (G, '\t\t\t\t"stop": rules.stop_at(act, leg_index),', '\t\t\t\t"stop": "fuel_station",', 'a fixed road ends its legs at fuel stations'),
 (G, 'if rules != null and rules.patrol_every_act and leg_index == patrol_place(telling_seed, act) and data.has_record("legs", PATROL_LEG):', 'if false:', 'no Patrol leg is put in'),
 (G, '\t\tfor branch: Dictionary in branches:\n\t\t\tbranch["leg"] = PATROL_LEG', '\t\tfor branch: Dictionary in branches.slice(0, 1):\n\t\t\tbranch["leg"] = PATROL_LEG', 'only the left road is the Patrol\'s'),
 (G, '\treturn Rng.seeded(Rng.derive(telling_seed, PATROL_SALT + act)).randi_range(0, LEGS_PER_ACT - 1)', '\treturn 0', 'the Patrol leg is always the first'),
 (G, '\t\t\tif not allowed.has(branch["modifier"]):\n\t\t\t\tbranch["modifier"] = ""\n', '', 'the Patrol leg keeps another leg\'s modifier'),
 (R, '\treturn fork_ahead() and branches.size() > 1', '\treturn fork_ahead()', 'one leg ahead counts as a fork'),
 (S, '\tif shady and _rules.deals_offered():', '\tif shady:', 'the stop lets the shady guy in at any Table'),
 (S, '\tif not _rules.stock_offered():\n\t\t# A Table that names its services has no shops: nothing is held out.\n\t\tstock = {}\n', '', 'Noor\'s stops sell their stock'),
 (S, '\tif GameData.as_bool(record.get("restocks")) and _rules.stock_offered():', '\tif GameData.as_bool(record.get("restocks")):', 'Noor\'s stops refill'),
 (S, '\tif contraband and _rules.no_contraband:\n\t\treturn\n', '', 'contraband is refilled at the In-laws\' Table'),
 (S, '\t\tif _rules.no_contraband and GameData.as_bool(record.get("contraband")):\n\t\t\tcontinue\n', '', 'contraband is in the stock at the In-laws\' Table'),
 (S, '\t\tif not _rules.allows_service(GameData.as_string(record.get("service"))):\n\t\t\tcontinue\n', '', 'a boss stop offers every service at Noor\'s Table'),
 (S, '\t\t\tif offers.is_empty():\n\t\t\t\t# Nothing to pick (a Table without shops): the services at once.\n\t\t\t\tpicks_left = 0\n\t\t\t\t_lay_out_services()\n', '', 'a boss stop with nothing to pick offers no service'),
 (S, 'repair.price = roundf(_tuning.f("repair_price") * _price_mult)', 'repair.price = _tuning.f("repair_price")', 'a repair costs the same at every Table'),
 (T, '\treturn not no_deals and stock_offered()', '\treturn not no_deals', 'Deals at a Table without shops'),
 (T, '\t\tif GameData.as_int(entry.get("act")) == act and GameData.as_int(entry.get("stop")) == leg_index + 1:', '\t\tif GameData.as_int(entry.get("act")) == act and GameData.as_int(entry.get("stop")) == leg_index:', 'the hitcher waits one stop late'),
 (T, '\tfor next: String in opened_by(data, table_id):\n\t\tif not open.has(next):', '\tfor next: String in data.record_ids("tables"):\n\t\tif not open.has(next):', 'a win opens every Table'),
 (T, '\t\tif GameData.as_string(table.get("unlock")) == UNLOCK_WIN + table_id:', '\t\tif GameData.as_string(table.get("unlock")).begins_with(UNLOCK_WIN):', 'any win opens every later Table'),
 (R, '\tbegin(table, rules.seed if rules.seed != TableRules.NO_SEED else Rng.derive(seed, RETELLING_SALT + retellings))', '\tbegin(table, Rng.derive(seed, RETELLING_SALT + retellings))', 'a Wreck at Noor\'s Table draws another night'),
 (R, '\tbegin(table, rules.seed if rules.seed != TableRules.NO_SEED else Rng.derive(seed, RETELLING_SALT + retellings))', '\tbegin(table, seed)', 'a Wreck never draws another night'),
]
