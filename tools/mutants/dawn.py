"""Mutants of Dawn, the Call and the Arrival (GDD 10.4, 10.5) for T-BOSS-03 and T-CALL-01.
    python3 tools/mutants.py T-BOSS-03,T-CALL-01 tools/mutants/dawn.py
All 73 have been run. Those that live make no difference to play: the
once-only flag of the speed check (the car crosses the barriers once); no
hanging up at the road's end (nobody is still ringing there, and the stop
that follows builds everything anew); the held car's speed (it is held only
once it stands, and does not move either way); the key's own guard (its
ritual already asks for the bay).
"""
B = 'src/core/boss_sim.gd'
D = 'src/core/drive_sim.gd'
C = 'src/core/car_sim.gd'
H = 'src/core/hand_sim.gd'
I = 'src/core/item_sim.gd'
G = 'src/core/leg_generator.gd'
MUTANTS = [
 # Dawn's phases and light
 (B, 'phase = THE_CALL if _car.s >= _call_at else (SUNRISE if _car.s >= _sunrise_at else FALSE_DAWN)', 'phase = THE_CALL if _car.s >= _call_at else SUNRISE', 'no false dawn'),
 (B, 'glare = _glare_full * clampf((_car.s - _glare_from) / maxf(_glare_ramp, 0.001), 0.0, 1.0)', 'glare = _glare_full', 'glare from the start'),
 (B, 'glare = _glare_full * clampf((_car.s - _glare_from) / maxf(_glare_ramp, 0.001), 0.0, 1.0)', 'glare = _glare_full if _car.s >= _glare_from else 0.0', 'the sun blinds at once'),
 (B, '_glare_from = 0.0 if GameData.as_bool(plan_of_road.get("early_sun")) else _sunrise_at', '_glare_from = _sunrise_at', 'early sun is no earlier'),
 (B, '\t\tglow = 1.0\n', '\t\tglow = 0.0\n', 'no glow'),
 (B, '\t\tglow_side = GameData.as_float(dawn.get("glow_side"))\n', '\t\tglow_side = -GameData.as_float(dawn.get("glow_side"))\n', 'glow on the left'),
 (B, '\t\tsun_side = GameData.as_float(dawn.get("sun_side"))\n', '\t\tsun_side = -GameData.as_float(dawn.get("sun_side"))\n', 'sun on the right'),
 (D, 'var sun: float = 0.0 if effects.has(ItemSim.VISOR_DOWN) else boss.glare', 'var sun: float = boss.glare', 'visor blocks nothing'),
 (D, '\treturn maxf(encounter.glare, sun) * items.passive("glare_mult")', '\treturn (0.0 if effects.has(ItemSim.VISOR_DOWN) else maxf(encounter.glare, boss.glare)) * items.passive("glare_mult")', 'visor blocks the spotlight too'),
 (D, '\treturn maxf(encounter.glare, sun) * items.passive("glare_mult")', '\treturn maxf(encounter.glare * items.passive("glare_mult"), sun)', 'sunglasses do nothing against the sun'),
 (D, 'var base: float = _floor_of_road if _floor_of_road >= 0.0 else _heavy_floors[index]', 'var base: float = _heavy_floors[index]', 'Dawn has act 3\'s floor'),
 # traffic
 (B, 'if at >= sunrise or roll < lerpf(from, 1.0, clampf(at / sunrise, 0.0, 1.0)):', 'if true:', 'traffic does not build'),
 (B, 'if at >= sunrise or roll < lerpf(from, 1.0, clampf(at / sunrise, 0.0, 1.0)):', 'if at >= sunrise or roll < from:', 'traffic does not rise through the false dawn'),
 (B, 'road["density_mult"] = GameData.as_float(modifier.get("traffic_mult"), 1.0)', 'road["density_mult"] = 1.0', 'market day no busier'),
 (G, 'if block.z > _beats_end or _in_calm(block.y, block.z) or _in_reserved(block.y, block.z):', 'if block.z > _beats_end or _in_calm(block.y, block.z):', 'vehicles beside him in the corridor'),
 # corridor
 (B, 'var middle: float = _car.lane_center(clampi(_car.lane_of(x), 0, _car.lanes - 1))', 'var middle: float = _car.lane_center(_car.lanes / 2)', 'only the middle lane has a corridor'),
 (B, '\tif not active or _corridor_to <= _corridor_from or s < _corridor_from or s > _corridor_to:\n\t\treturn Vector2(-INF, INF)', '\tif not active or _corridor_to <= _corridor_from or s < _corridor_at or s > _corridor_to:\n\t\treturn Vector2(-INF, INF)', 'no taper'),
 (B, 'half = lerpf(_car.lane_width() * 0.5, _corridor_half_gap, (s - _corridor_from) / (_corridor_at - _corridor_from))', 'half = _corridor_half_gap', 'taper as narrow as the corridor'),
 (B, '_corridor_half_gap = GameData.as_float(check.get("gap_m")) * 0.5', '_corridor_half_gap = GameData.as_float(check.get("gap_m"))', 'barriers twice as far apart'),
 (B, 'searched = _car.speed > _corridor_max_kmh + 0.001', 'searched = _car.speed > _corridor_max_kmh + 10.0', 'ten over is waved through'),
 (B, 'searched = _car.speed > _corridor_max_kmh + 0.001', 'searched = _car.speed >= _corridor_max_kmh - 0.001', 'seventy is too fast'),
 (B, '\t\t\t_corridor_judged = true\n\t\t\tsearched', '\t\t\tsearched', 'judged again and again'),
 (B, "out.append({\"kind\": \"checkpoint\", \"ahead\": gap, \"limit\": _corridor_max_kmh if _corridor_max_kmh < INF else 0.0})", "pass", 'no sign'),
 (C, '\t\tvar push: float = minf(_pushback, slack)\n', '\t\tvar push: float = _pushback\n', 'pushed into the other barrier'),
 (C, '\telif right_edge >= wall_right or left_edge <= wall_left:', '\telif false:', 'barriers are air'),
 (C, '\t\tif right_edge >= wall_right:\n\t\t\tedge_touched = EDGE_RIGHT\n\t\t\tx = wall_right - _half_width - push', '\t\tif right_edge >= wall_right:\n\t\t\tedge_touched = EDGE_RIGHT\n\t\t\tx = wall_right + _half_width + push', 'through the right barrier'),
 (D, '\tcar.speed = 0.0\n\tcar.v_lat = 0.0\n\tclock_minutes_owed += minutes\n\tclock.add_minutes(minutes)\n\t# A search finds everything', '\tcar.v_lat = 0.0\n\tclock_minutes_owed += minutes\n\tclock.add_minutes(minutes)\n\t# A search finds everything', 'searched without stopping'),
 (D, '\tclock_minutes_owed += minutes\n\tclock.add_minutes(minutes)\n\t# A search finds everything', '\tclock_minutes_owed += minutes\n\t# A search finds everything', 'a search costs no time'),
 (D, '\tfor id: StringName in items.take_all_contraband():\n\t\ttaken_ids.append(String(id))\n\t_fit_cabin()\n\t_emit("pulled_over", {"released": true, "paid": "search", "cost": 0.0, "minutes": minutes, "taken": taken_ids})', '\t_fit_cabin()\n\t_emit("pulled_over", {"released": true, "paid": "search", "cost": 0.0, "minutes": minutes, "taken": taken_ids})', 'a search takes nothing'),
 # the Call
 (B, '\t\tif call == CALL_NONE and _car.s >= _call_at:', '\t\tif call == CALL_NONE and _car.s >= _call_at + 100.0:', 'the Call comes 100 m late'),
 (B, '\t\t\tcall_left = _ring_s\n', '\t\t\tcall_left = _ring_s * 0.5\n', 'rings half as long'),
 (B, '\tcall = CALL_TALKING\n\tcall_left = _talk_s\n', '\tcall = CALL_TALKING\n\tcall_left = _talk_s * 0.5\n', 'talks half as long'),
 (B, '\tcall_taken = how\n\tcall_answered = true\n', '\tcall_taken = how\n', 'boss forgets he answered'),
 (B, '\treturn call == CALL_TALKING and call_taken == TAKEN_PARKED', '\treturn false', 'parked call does not hold the car'),
 (B, '\treturn call == CALL_TALKING and call_taken != TAKEN_WITH_PASSENGER', '\treturn call == CALL_TALKING', 'passenger call still fills his hand'),
 (B, '\treturn call == CALL_TALKING and call_taken != TAKEN_WITH_PASSENGER', '\treturn call == CALL_TALKING and call_taken == TAKEN_ALONE', 'parked call leaves his hand free'),
 (B, 'func talking() -> bool:\n\treturn call == CALL_TALKING', 'func talking() -> bool:\n\treturn false', 'he can reach while he talks'),
 (B, '\treturn hazards_on and _car.speed <= _stopped_kmh and _car.x - _car.half_width() >= _car.road_right()', '\treturn _car.speed <= _stopped_kmh and _car.x - _car.half_width() >= _car.road_right()', 'parked without hazard lights'),
 (B, '\treturn hazards_on and _car.speed <= _stopped_kmh and _car.x - _car.half_width() >= _car.road_right()', '\treturn hazards_on and _car.speed <= _stopped_kmh', 'parked in a lane'),
 (B, '\treturn hazards_on and _car.speed <= _stopped_kmh and _car.x - _car.half_width() >= _car.road_right()', '\treturn hazards_on and _car.x - _car.half_width() >= _car.road_right()', 'parked while rolling'),
 (B, '\t\twrist_steer = GameData.as_float(ring.get("wrist_steer"), 1.0)\n', '', 'wrist steers fully'),
 (D, '\tif how == BossSim.TAKEN_ALONE and boss.pulled_over_safely(items.flag(FLAG_HAZARDS)):\n\t\thow = BossSim.TAKEN_PARKED\n', '', 'never a parked call'),
 (D, '\trun.call_answered = true\n\t_emit("call_resolved", {"caller": NOOR, "answered": true, "taken": how})', '\t_emit("call_resolved", {"caller": NOOR, "answered": true, "taken": how})', 'the Telling forgets he answered'),
 (D, '\t\t_emit("call_resolved", {"caller": NOOR, "answered": false, "taken": ""})\n', '\t\t_emit("call_resolved", {"caller": NOOR, "answered": false, "taken": ""})\n\t\tnerves.add(4.0)\n', 'ignoring costs Nerves'),
 (D, '\t\teffects.hold(THE_CALL, SET_PIECE, false)\n\t\t_emit("call_resolved", {"caller": NOOR, "answered": false', '\t\t_emit("call_resolved", {"caller": NOOR, "answered": false', 'pocket stays live after the ring'),
 (D, '\t\t"call_answered": run.call_answered,\n', '', 'the save forgets he answered'),
 (D, '\t# Whoever is on the phone hangs up as he pulls in.\n\tboss.hang_up()\n\t_report_call()\n', '', 'no hanging up at the end'),
 (D, '\t\tif _wrist_on_wheel:\n\t\t\twheel.grip()', '\t\tif _wrist_on_wheel:\n\t\t\tpass', 'wrist not on the wheel'),
 (D, '\t\telif not hand.gripping:\n\t\t\twheel.release()', '\t\telif false:\n\t\t\twheel.release()', 'wrist never leaves the wheel'),
 (D, '\thand.can_reach = nerves.snap_left <= 0.0 and not boss.talking()', '\thand.can_reach = nerves.snap_left <= 0.0', 'reach while a passenger holds the phone'),
 (H, '\t\tsteer_px = input.pointer_delta.x * wrist_steer', '\t\tsteer_px = 0.0', 'no steering on the phone'),
 (H, '\t\ttarget = _space.ear\n', '\t\ttarget = pos\n', 'hand does not go to his ear'),
 (I, '\tif gesture != "HOLD" and gesture != "DRAG_TO":', '\tif gesture != "HOLD":', 'no TAP beside the DRAG'),
 (D, 'and (gesture.kind == Gesture.Kind.HOLD or gesture.kind == Gesture.Kind.DRAG_TO) \\', 'and gesture.kind == Gesture.Kind.HOLD \\', 'DRAG let go is never a TAP'),
 (D, '\t\tcar.speed = 0.0\n\t\tcar.v_lat = 0.0\n\telif not _standing():', '\t\tpass\n\telif not _standing():', 'held car keeps its speed'),
 # the Arrival
 (B, '\t\tin_bay = _car.speed <= _stopped_kmh and _car.s - half_length >= bay_from', '\t\tin_bay = _car.s - half_length >= bay_from', 'rolling counts as in the bay'),
 (B, '\t\tin_bay = _car.speed <= _stopped_kmh and _car.s - half_length >= bay_from', '\t\tin_bay = _car.speed <= _stopped_kmh and _car.s + half_length >= bay_from', 'half in the bay counts'),
 (B, '\t\tin_bay = _car.speed <= _stopped_kmh and _car.s - half_length >= bay_from', '\t\tin_bay = _car.speed <= _stopped_kmh', 'stopped anywhere counts'),
 (B, '\t\t\twall_speed = _car.speed if _car.speed > _bump_kmh else 0.0', '\t\t\twall_speed = 0.0', 'the end of the street is soft'),
 (B, '\t\t\twall_speed = _car.speed if _car.speed > _bump_kmh else 0.0', '\t\t\twall_speed = _car.speed', 'a crawl into the end is a hit'),
 (B, '\t\t\t_car.s = _length - half_length\n\t\t\t_car.speed = 0.0', '\t\t\t_car.speed = 0.0', 'the car goes through the end'),
 (D, '\t\t\tcollision.strike(collision.classify(boss.wall_speed, false))', '\t\t\tcollision.strike(Collision.Hit.SCRAPE)', 'the end is always a scrape'),
 (D, '\tif boss.kind != BossSim.ARRIVAL or not boss.in_bay:\n\t\treturn\n\t_arrive()', '\t_arrive()', 'the key works anywhere'),
 (D, '\teffects.hold(IN_BAY, SET_PIECE, false)\n\t_in_bay = false\n\tboss.stop()\n', '', 'he can arrive twice'),
 (D, '"late": clock.late(), "call": told_true})', '"late": clock.late(), "call": false})', 'arrival never knows of the Call'),
 (D, '\t\t\t_set_stretch(BossSim.arrival_plan(data, run.act))', '\t\t\t_set_stretch(RunGenerator.blank_plan(run.act, RunGenerator.ROAD_LANES, true, 300.0))', 'no street after Dawn'),
 # D-050: his eyes during the Call; the ring written out
 (H, '\tif at_ear:\n\t\t# A phone held to his ear is no reach: his eyes stay on the road.\n\t\twant = Vector2.ZERO\n', '', 'his eyes follow the phone to his ear'),
 (D, '\t\t_emit("line_requested", {"id": "call.noor.rings", "until": "call_resolved"})\n', '', 'the ring is not written out'),
 # D-053: the sun's one place
 (B, 'return Vector2(sun_side * side_deg, lerpf(rise_from, rise_to, risen))', 'return Vector2(-sun_side * side_deg, lerpf(rise_from, rise_to, risen))', 'the light is on the other side'),
 (B, 'return Vector2(sun_side * side_deg, lerpf(rise_from, rise_to, risen))', 'return Vector2(sun_side * side_deg, rise_to)', 'the sun does not climb'),
 (B, 'return Vector2(sun_side * side_deg, lerpf(rise_from, rise_to, risen))', 'return Vector2(sun_side * side_deg, lerpf(rise_to, rise_from, risen))', 'the sun sets as it comes on'),
 (D, 'tuning.fi("sun_position", 1)) if boss.glare > 0.0 else null,', 'tuning.fi("sun_position", 1)),', 'a sun on every road'),
 (D, 'tuning.fi("sun_position", 1)) if boss.glare > 0.0 else null,', 'tuning.fi("sun_position", 1)) if glare() > 0.0 else null,', 'the visor takes the sun away'),
]
