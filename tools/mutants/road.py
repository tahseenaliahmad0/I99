"""Mutants of what the owner decided in D-074 beside rule 6: a road that
leans by stretches, the wake of large vehicles, wipers that last 12 to 18 s
with a bent blur, and what the guide and the label say of the horn. For
T-CAR-05 (the road), T-LEG-03, T-FAULT-02 and T-ITEM-BASE (wipers, horn):
    python3 tools/mutants.py T-CAR-05,T-LEG-03,T-FAULT-02,T-ITEM-BASE tools/mutants/road.py
"""
C = 'src/core/car_sim.gd'
L = 'src/core/leg_sim.gd'
D = 'src/core/drive_sim.gd'
I = 'src/core/item_sim.gd'
G = 'src/core/leg_generator.gd'
V = 'src/view/guide.gd'
H = 'src/view/hint_view.gd'
MUTANTS = [
 # The road leans.
 (C, '\tdrift = (_crown * camber + extra_drift) * drift_share()', '\tdrift = (_crown + extra_drift) * drift_share()', 'every road leans fully right, whatever it says'),
 (C, '\treturn (_crown * camber + extra) * drift_share()', '\treturn (_crown + extra) * drift_share()', 'steady_drift takes every road to lean fully right'),
 (D, '\t\tcar.camber = camber_now()', '\t\tcar.camber = 1.0', 'the car is never told how the road leans'),
 (D, '\tif leg.active and leg.says_camber:\n\t\treturn leg.camber_at(car.s)\n\treturn road_camber', '\treturn road_camber', 'a leg\'s leans are never asked for'),
 (D, '\tif leg.active and leg.says_camber:\n\t\treturn leg.camber_at(car.s)\n\treturn road_camber', '\tif leg.active:\n\t\treturn leg.camber_at(car.s)\n\treturn road_camber', 'a plan that says nothing of its leans is a flat road'),
 (D, '\tif not is_nan(lean_everywhere):\n\t\treturn lean_everywhere\n', '', 'lean_everywhere is not heeded'),
 (L, '\t\t\tramp = clampf(minf(s - start, end - s) / _camber_ramp, 0.0, 1.0)', '\t\t\tramp = 1.0', 'a lean is there all at once: no ramp'),
 (L, '\t\t\tramp = clampf(minf(s - start, end - s) / _camber_ramp, 0.0, 1.0)', '\t\t\tramp = clampf((s - start) / _camber_ramp, 0.0, 1.0)', 'a lean comes on over the ramp and goes off at once'),
 (L, '\t\treturn GameData.as_float(stretch.get("lean")) * ramp', '\t\treturn absf(GameData.as_float(stretch.get("lean"))) * ramp', 'every lean is to the right'),
 (G, '\tvar at: float = tuning.f("camber_lead_m")', '\tvar at: float = 0.0', 'a leg leans from its first metre'),
 (G, '\t\tif side != 0.0 and side == last:', '\t\tif false:', 'two stretches running may lean the same way'),
 (G, '\t\t\tside = 1.0 if draw < weights[0] + weights[1] else -1.0', '\t\t\tside = 1.0', 'no road leans left'),
 (G, '\t\tvar lean: float = side * leans[random.randi_range(0, leans.size() - 1)]', '\t\tvar lean: float = side', 'every lean is a full one'),
 (G, '\tvar random: RandomNumberGenerator = Rng.seeded(Rng.derive(road_seed, CAMBER_SALT))', '\tvar random: RandomNumberGenerator = Rng.seeded(CAMBER_SALT)', 'every road leans as every other does'),
 (G, '\t\t\tif at < from + GameData.as_float(zone.get("length")) and at + stretch > from:\n\t\t\t\tkept = false', '\t\t\tif at < from + GameData.as_float(zone.get("length")) and at + stretch > from:\n\t\t\t\tpass', 'the road leans through what a boss has reserved'),
 # Wake.
 (D, '\t\ttotal += strength if car.x >= vehicle.x else -strength', '\t\ttotal += -strength if car.x >= vehicle.x else strength', 'a truck\'s wake pulls him in'),
 (D, '\t\tvar strength: float = vehicle.wake * (1.0 - gap / within)', '\t\tvar strength: float = vehicle.wake', 'the wake is as strong at arm\'s length as at none'),
 (D, '\t\t\tstrength *= clampf(absf(vehicle.closing_speed(car.speed)) / full, 0.0, 1.0)', '\t\t\tpass', 'a truck he keeps pace with pushes as one he flies past'),
 (D, '\t\t\tstrength *= clampf(absf(vehicle.closing_speed(car.speed)) / full, 0.0, 1.0)', '\t\t\tstrength *= clampf(vehicle.closing_speed(car.speed) / full, 0.0, 1.0)', 'a truck that passes him has no wake'),
 (D, '\t\t\tstrength *= 1.0 - along / reach', '\t\t\tpass', 'the wake is whole right up to wake_reach_m'),
 (D, '\t\tif gap < -WAKE_TOUCH or gap >= within:', '\t\tif gap >= within:', 'behind a truck in its own lane he is pushed too'),
 (D, '\t\tif vehicle.wake <= 0.0 or vehicle.cc_hit or collision.immunity_left > 0.0:', '\t\tif vehicle.wake <= 0.0:', 'a truck that has just hit him also pushes him with its wake'),
 (D, '\tpush += wake_push()', '\tpass', 'the wake never reaches the car'),
 # Wipers.
 (I, '\treturn pow(clampf(since_wipe / clear_time, 0.0, 1.0), _wiper_power)', '\treturn clampf(since_wipe / clear_time, 0.0, 1.0)', 'the rain comes back evenly'),
 (I, '\twiper_clear_now = _wiper_clear + (Rng.seeded(seed_value).randf() * 2.0 - 1.0) * _wiper_spread', '\twiper_clear_now = _wiper_clear', 'every sweep lasts the same'),
 (I, '\twiper_clear_now = _wiper_clear + (Rng.seeded(seed_value).randf() * 2.0 - 1.0) * _wiper_spread', '\twiper_clear_now = _wiper_clear + Rng.seeded(seed_value).randf() * 2.0 * _wiper_spread', 'a sweep lasts 15 to 21 s'),
 (I, '\t\t\twipes += 1\n\t\t\t_draw_wiper_clear()', '\t\t\twipes += 1', 'only the first sweep of a leg is drawn'),
 (I, '\treturn _faults.param(&"stuck_wiper", "wiper_clear_s", wiper_clear_now) * passive("visibility_mult")', '\treturn wiper_clear_now * passive("visibility_mult")', 'a stuck wiper sweeps as a good one'),
 # The horn, and what is said of it.
 (D, '\tif nearest == null or nearest.speed >= car.cruise_speed(gate.gear):', '\tif nearest == null:', 'what is as fast as his gear holds him up'),
 (D, '\tif nearest.changing or nearest.signalling != 0:\n\t\t# Already on its way out.\n\t\treturn HELD_NOT', '\tpass', 'a car that is moving over still holds him up'),
 (D, '\tif items.horn_lane_for(nearest) != ItemSim.NO_LANE:\n\t\treturn HELD_YIELDS', '\tif true:\n\t\treturn HELD_YIELDS', 'the guide says to sound the horn at a truck'),
 (D, '\treturn HELD_STAYS if car.speed <= nearest.speed + tuning.f("guide_stuck_kmh") else HELD_NOT', '\treturn HELD_STAYS', 'coming up on a truck at speed he is told he is stuck'),
 (D, '\treturn HELD_STAYS if car.speed <= nearest.speed + tuning.f("guide_stuck_kmh") else HELD_NOT', '\treturn HELD_STAYS if car.speed <= nearest.speed else HELD_NOT', 'only at the very speed of what is ahead is he stuck'),
 (D, '\t\t"horn_taught": items.horn_moved >= tuning.i("guide_horn_lessons"),', '\t\t"horn_taught": false,', 'the guide never tires of saying what the horn is for'),
 (I, '\t\t\t_traffic.begin_lane_change(vehicle, target, 0.0, _horn_yield_time)\n\t\t\thorn_moved += 1', '\t\t\t_traffic.begin_lane_change(vehicle, target, 0.0, _horn_yield_time)', 'the horn is never counted as having moved anybody'),
 (I, '\t\tif target != NO_LANE:\n\t\t\t_traffic.begin_lane_change(vehicle, target, 0.0, _horn_yield_time)\n\t\t\thorn_moved += 1', '\t\thorn_moved += 1\n\t\tif target != NO_LANE:\n\t\t\t_traffic.begin_lane_change(vehicle, target, 0.0, _horn_yield_time)', 'a honk at a truck counts as a lesson'),
 (D, '\t\tif items.horn_reaches(vehicle) and (nearest == null or vehicle.s < nearest.s):', '\t\tif items.horn_reaches(vehicle) and (nearest == null or vehicle.s > nearest.s):', 'the furthest vehicle the horn reaches is the one he is held up by'),
 (I, '\treturn gap >= 0.0 and gap <= _horn_range', '\treturn gap >= 0.0', 'the horn is heard at any distance'),
 (I, '\treturn gap >= 0.0 and gap <= _horn_range', '\treturn gap <= _horn_range', 'the horn is heard by what is behind him'),
 (I, '\tif not (vehicle.yields_to_horn or passive("horn_yields_all") > 0.0):\n\t\treturn NO_LANE', '\tif not vehicle.yields_to_horn:\n\t\treturn NO_LANE', 'the loud horn moves no truck'),
 (I, '\t\tif _traffic.lane_is_free(target, vehicle.s, _horn_clearance, vehicle):\n\t\t\treturn target', '\t\tif true:\n\t\t\treturn target', 'a car moves over for the horn into whoever is there'),
 (V, '\telif GameData.as_int(snapshot["held_up"]) == DriveSim.HELD_YIELDS and not GameData.as_bool(snapshot["horn_taught"]):', '\telif false:', 'the guide never says what the horn is for'),
 (V, '\telif GameData.as_int(snapshot["held_up"]) == DriveSim.HELD_STAYS:\n\t\tout.append(["guide.held_up.around", []])', '\telif GameData.as_int(snapshot["held_up"]) == DriveSim.HELD_STAYS:\n\t\tout.append(["guide.held_up.horn", []])', 'behind a truck the guide says to sound the horn'),
 (H, '\tif item.is_empty() and Lines.has_line("hint.effect." + ritual):', '\tif false:', 'the label says nothing of what a control of the car does'),
]
