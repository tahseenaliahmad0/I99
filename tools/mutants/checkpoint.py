"""Mutants of the Checkpoint (GDD 10.2) for T-BOSS-01.
    python3 tools/mutants.py T-BOSS-01 tools/mutants/checkpoint.py
"""
B = 'src/core/boss_sim.gd'
D = 'src/core/drive_sim.gd'
I = 'src/core/item_sim.gd'
S = 'src/core/suspicion_sim.gd'
C = 'src/core/collision.gd'
MUTANTS = [
 # the queue
 (B, 'var cars: int = roundi(GameData.as_float(queue.get("cars")) * GameData.as_float(modifier.get("queue_mult"), 1.0))', 'var cars: int = roundi(GameData.as_float(queue.get("cars")))', 'long queue no longer'),
 (B, '\tfor _index: int in GameData.as_int(modifier.get("documents"), 1):', '\tfor _index: int in 1:', 'thorough asks once'),
 (B, '\t\tasks.append(GameData.as_string(left[pick]))\n\t\tleft.remove_at(pick)\n', '\t\tasks.append(GameData.as_string(left[pick]))\n', 'the same document twice'),
 (B, '\t\t\tnose = vehicle.s - vehicle.half_length - _queue_gap\n\t\t\tline.append(vehicle)', '\t\t\tnose = vehicle.s - vehicle.half_length - _queue_gap * 2.0\n\t\t\tline.append(vehicle)', 'queue twice as loose'),
 (B, '\t\t\tvehicle.yields_to_horn = false\n', '', 'queue yields to the horn'),
 (B, '\t\t\tvar speed_ms: float = clampf(room * _pull_up_rate, 0.0, _creep_ms)', '\t\t\tvar speed_ms: float = clampf(room * _pull_up_rate, 0.0, _creep_ms * 4.0)', 'queue pulls up fast'),
 (B, '\t\tif _served[lane] >= _serve_s - dt * 0.5:', '\t\tif _served[lane] >= _serve_s * 0.25 - dt * 0.5:', 'served in a second'),
 (B, '\t\tif bar_at - (first.s + first.half_length) > _settle_m:\n\t\t\tcontinue\n', '', 'served before it is at the bar'),
 (B, '\t\tif gone != null and gone.s - gone.half_length < bar_at + _queue_clear:\n\t\t\t# Not yet clear of the bar: the next one waits behind it.', '\t\tif false:\n\t\t\t# Not yet clear of the bar: the next one waits behind it.', 'next one drives into the leaver'),
 # first in line, stow
 (B, '\tif lane >= _queue.size() or not _queue[lane].is_empty():\n\t\treturn false', '\tif lane >= _queue.size():\n\t\treturn false', 'first in line behind the queue'),
 (B, '\treturn _car.speed <= _stopped_kmh and nose <= bar_at + 0.001 and bar_at - nose <= _stop_zone', '\treturn nose <= bar_at + 0.001 and bar_at - nose <= _stop_zone', 'first in line while rolling'),
 (B, '\treturn _car.speed <= _stopped_kmh and nose <= bar_at + 0.001 and bar_at - nose <= _stop_zone', '\treturn _car.speed <= _stopped_kmh and nose <= bar_at + 0.001', 'first in line from afar'),
 (B, '\t\t\tstow_left = _stow_s\n', '\t\t\tstow_left = _stow_s * 0.5\n', 'the soldier comes in 5 s'),
 (B, '\t\tif not released and s_then + nose <= bar_at + 0.001 and _car.s + nose > bar_at:', '\t\tif false:', 'no bar'),
 (B, '\t\t\tbar_speed = _car.speed if _car.speed > _bump_kmh else 0.0\n\t\t\t_car.s = bar_at - nose', '\t\t\tbar_speed = 0.0\n\t\t\t_car.s = bar_at - nose', 'the bar never scrapes'),
 (B, '\t\t\tbar_speed = _car.speed if _car.speed > _bump_kmh else 0.0\n\t\t\t_car.s = bar_at - nose', '\t\t\tbar_speed = _car.speed\n\t\t\t_car.s = bar_at - nose', 'the bar scrapes at a crawl'),
 (B, '\tif kind == CHECKPOINT:\n\t\treturn phase == STOW or phase == PAPERS', '\tif kind == CHECKPOINT:\n\t\treturn false', 'the car is not held'),
 # papers
 (B, '\t\tif delay >= float(_delays + 1) * _delay_every - dt * 0.5:', '\t\tif delay >= float(_delays + 1) * _delay_every * 2.0 - dt * 0.5:', 'delay counted every 10 s'),
 (B, '\tdelay = 0.0\n\t_delays = 0\n\tif _documents.is_empty():', '\tif _documents.is_empty():', 'delay not counted afresh'),
 (B, '\tif kind != CHECKPOINT or phase != PAPERS or wanted.is_empty() or document != wanted:\n\t\treturn false', '\tif kind != CHECKPOINT or phase != PAPERS or wanted.is_empty():\n\t\treturn false', 'any document will do'),
 (B, '\treleased = true\n\tphase = THROUGH', '\tphase = THROUGH', 'the bar stays down'),
 (D, 'var waiting: bool = boss.kind == BossSim.CHECKPOINT and boss.phase == BossSim.PAPERS and not boss.wanted.is_empty()', 'var waiting: bool = boss.kind == BossSim.CHECKPOINT', 'papers can be handed over any time'),
 (D, '\t\tsuspicion.add(_checkpoint_number("contraband_suspicion") * float(items.contraband_in_view()))', '\t\tsuspicion.add(_checkpoint_number("contraband_suspicion") * float(mini(items.contraband_in_view(), 1)))', 'contraband counted once'),
 (D, '\t\tsuspicion.add(_checkpoint_number("courage_suspicion") * float(courage_noticed()))', '\t\tsuspicion.add(_checkpoint_number("courage_suspicion") * float(courage()))', 'mints hide nothing at the Checkpoint'),
 (D, '\t\tsuspicion.add(_checkpoint_number("courage_suspicion") * float(courage_noticed()))', '\t\tsuspicion.add(_checkpoint_number("courage_suspicion") * float(mini(courage_noticed(), 1)))', 'Courage counted once'),
 (D, '\t\tif use_forged_papers():\n\t\t\tboss.papers_passed()', '\t\tif false:\n\t\t\tboss.papers_passed()', 'forged papers pass nothing'),
 (D, '\tif boss.delayed:\n\t\tsuspicion.add(_checkpoint_number("delay_suspicion"))', '\tif boss.delayed:\n\t\tpass', 'delay costs nothing'),
 (D, '\t\tif not items.flag(ItemSim.FLAG_WINDOW):\n\t\t\t# He cannot be handed anything through the glass.', '\t\tif true:\n\t\t\t# He cannot be handed anything through the glass.', 'he taps on an open window'),
 (D, '\t\tif cash < price or table.no_bribes:\n\t\t\t_emit("pulled_over", {"released": false, "refused": true, "paid": "bribe", "cost": price})\n\t\t\treturn\n', '\t\tif table.no_bribes:\n\t\t\t_emit("pulled_over", {"released": false, "refused": true, "paid": "bribe", "cost": price})\n\t\t\treturn\n', 'a bribe he cannot pay is taken'),
 (D, '\t\tcash -= price\n\t\t_let_through("bribe", price, 0.0, [])', '\t\t_let_through("bribe", price, 0.0, [])', 'the bribe is free'),
 (D, '\tif not boss.hand_over(String(what)):\n\t\t_emit("line_requested", {"id": "soldier.wrong"})\n\t\treturn', '\tif not boss.hand_over(String(what)):\n\t\treturn', 'no shake of the head'),
 (D, '\tif level >= _checkpoint_number("turned_back_at"):\n\t\t_turn_back(level)', '\tif level > _checkpoint_number("turned_back_at"):\n\t\t_turn_back(level)', 'never turned back'),
 (D, '\telif level >= _checkpoint_number("pass_under"):', '\telif level > _checkpoint_number("pass_under"):', 'fifty passes'),
 (D, '\t\tfor id: StringName in items.take_all_contraband():\n\t\t\ttaken.append(String(id))\n\t\t_fit_cabin()\n\t\t_let_through("search"', '\t\tfor id: StringName in items.take_visible_contraband():\n\t\t\ttaken.append(String(id))\n\t\t_fit_cabin()\n\t\t_let_through("search"', 'a search misses what is stowed'),
 (D, '\tvar level: float = suspicion.value\n\tclock_minutes_owed += minutes\n\tclock.add_minutes(minutes)\n\tboss.release()', '\tvar level: float = suspicion.value\n\tclock_minutes_owed += minutes\n\tboss.release()', 'a search costs no time'),
 (D, '\tboss.release()\n\tsuspicion.end_watch()\n', '\tboss.release()\n', 'watched after the verdict'),
 (D, '\tvar minutes: float = _checkpoint_number("turned_back_minutes")\n\tclock_minutes_owed += minutes\n\tclock.add_minutes(minutes)\n\tboss.turn_back()', '\tvar minutes: float = _checkpoint_number("turned_back_minutes")\n\tclock_minutes_owed += minutes\n\tboss.turn_back()', 'turned back costs no time'),
 (D, '\tclock.add_minutes(minutes)\n\tboss.turn_back()\n', '\tclock.add_minutes(minutes)\n', 'turned back without a new queue'),
 (D, '\tcar.reset(car.lanes / 2, start_gear)\n\t_lane = car.lane_of(car.x)\n\t_car_s_then = car.s\n\tcollision.reset()\n\tsuspicion.begin_watch()', '\t_lane = car.lane_of(car.x)\n\t_car_s_then = car.s\n\tcollision.reset()\n\tsuspicion.begin_watch()', 'turned back but left at the bar'),
 (D, '\tcollision.reset()\n\tsuspicion.begin_watch()\n\t_hold_at_window()', '\tcollision.reset()\n\t_hold_at_window()', 'turned back with his Suspicion kept'),
 (D, '\t\tif barrier and boss.kind == BossSim.CHECKPOINT:\n\t\t\tsuspicion.add(_checkpoint_number("barrier_suspicion"))', '\t\tif barrier and boss.kind == BossSim.CHECKPOINT:\n\t\t\tpass', 'barriers cost no Suspicion'),
 (D, 'var barrier: bool = car.wall_touched and collision.hit == Collision.Hit.SCRAPE and collision.hit_vehicle_id == 0', 'var barrier: bool = car.wall_touched', 'Suspicion for a touch that is no scrape'),
 (D, 'var barrier: bool = car.wall_touched and collision.hit == Collision.Hit.SCRAPE and collision.hit_vehicle_id == 0', 'var barrier: bool = collision.hit == Collision.Hit.SCRAPE', 'Suspicion for scraping a vehicle'),
 (D, '\t\tif boss.bar_speed > 0.0 and collision.strike(Collision.Hit.SCRAPE):\n\t\t\tbarrier = true', '\t\tif boss.bar_speed > 0.0 and collision.strike(Collision.Hit.SCRAPE):\n\t\t\tbarrier = false', 'the bar costs no Suspicion'),
 (D, '\tsuspicion.decays = boss.kind != BossSim.CHECKPOINT\n', '', 'Suspicion wears off at the Checkpoint'),
 (D, '\tif boss.kind == BossSim.CHECKPOINT:\n\t\tsuspicion.begin_watch()\n\t\t_emit("suspicion_changed", {"value": 0.0, "watching": true})', '\tif false:\n\t\tsuspicion.begin_watch()', 'nobody watches at the Checkpoint'),
 (D, '\tif boss.kind == BossSim.CHECKPOINT:\n\t\t# At the Checkpoint only its own rows count', '\tif false:\n\t\t# At the Checkpoint only its own rows count', 'the Patrol\'s rows at the Checkpoint'),
 (D, '\t\tif ritual_id == ItemSim.UNSTOW:\n\t\t\titems.unstow_to(String(hand.anchor_id(hand.at_index)))', '\t\tif ritual_id == ItemSim.UNSTOW:\n\t\t\tpass', 'nothing comes out of the glovebox'),
 (S, '\telif decays:\n', '\telse:\n', 'decay switch ignored'),
 (C, '\tif x - car.half_width() <= car.wall_left or x + car.half_width() >= car.wall_right:\n\t\treturn false\n', '', 'pushed through a barrier by a vehicle'),
 # items
 (I, '\t\tif anchor_of(candidate) != anchor or is_stowed(candidate):\n\t\t\tcontinue', '\t\tif anchor_of(candidate) != anchor:\n\t\t\tcontinue', 'stowed things can be used'),
 (I, '\t\t\tmet = not free_cell().is_empty()', '\t\t\tmet = true', 'stowing into a full glovebox'),
 (I, '\t\tif GameData.as_bool(candidate.record.get("contraband")) and not is_stowed(candidate):\n\t\t\tcount += 1', '\t\tif GameData.as_bool(candidate.record.get("contraband")):\n\t\t\tcount += 1', 'stowed contraband still counts'),
 (I, '\t\tif id.begins_with(GLOVEBOX) and item_in_slot(StringName(id)) == null:\n\t\t\treturn id', '\t\tif id.begins_with(GLOVEBOX):\n\t\t\treturn id', 'a cell holds two things'),
 # the soldier is heard (GDD 17.2)
 (B, '\t\t\tstow_left = _stow_s\n\t\t\tstow_began = true\n', '\t\t\tstow_left = _stow_s\n', 'he sets off without a whistle'),
 (D, '\tif boss.stow_began:\n', '\tif boss.stow_ended:\n', 'he whistles as he arrives, not as he sets off'),
 (D, '\tif boss.asked and not boss.papers_done:\n\t\t# A sign goes up', '\tif boss.asked:\n\t\t# A sign goes up', 'a rap with nothing wanted'),
 (D, '\t\t_emit("sfx_requested", {"id": "soldier_knock"})\n\t\tif not items.flag(ItemSim.FLAG_WINDOW):\n', '\t\tif not items.flag(ItemSim.FLAG_WINDOW):\n\t\t\t_emit("sfx_requested", {"id": "soldier_knock"})\n', 'he raps only on a shut window'),
 (B, '\tstow_began = false\n\tstow_ended = false\n', '\tstow_ended = false\n', 'he whistles for as long as he walks'),
]
