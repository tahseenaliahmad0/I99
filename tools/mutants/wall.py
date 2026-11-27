"""Mutants of what keeps the generator's line open (GDD 9.2 rule 3, D-067)
for T-WALL-01, with the Tailgater's own test:
    python3 tools/mutants.py T-WALL,T-LEG-06 tools/mutants/wall.py
"""
B = 'src/core/boss_sim.gd'
T = 'src/core/traffic_sim.gd'
D = 'src/core/drive_sim.gd'
E = 'src/core/encounter_sim.gd'
MUTANTS = [
 (T, '\t\t\t\town = maxf(pace, minf(vehicle.speed, player_speed) / vehicle.speed)', '\t\t\t\town = pace', 'what he follows waits on him too: the brake does not open the gap'),
 (B, '\treturn _car.speed / _par_kmh', '\treturn 1.0', 'Dawn\'s road does not wait at the last checkpoint'),
 (D, '\t\tvar pace: float = boss.traffic_pace()', '\t\tvar pace: float = 1.0', 'the traffic\'s time step ignores the checkpoint'),
 (B, 'or _car.s < _corridor_sign_at or _car.s >= _corridor_clear_at:', 'or _car.s < _corridor_at or _car.s >= _corridor_clear_at:', 'the road waits only from the barriers\' mouth, not from the sign'),
 (B, 'or _car.s < _corridor_sign_at or _car.s >= _corridor_clear_at:', 'or _car.s < _corridor_sign_at or _car.s >= _corridor_to:', 'the road stops waiting where the barriers end, before he is back at par'),
 (E, '\tvar seconds: float = _tail_pass_time(driver, behind, from_behind)\n', '\tvar seconds: float = _tail_pass_time(driver, behind, from_behind)\n\tif seconds > 0.0:\n\t\treturn true\n', 'the Tailgater passes whether there is room or not'),
 (E, '\tfor at: float in _line_changes:\n\t\tif at > _car.s - _change_length and at < _car.s + car_ms * seconds:\n\t\t\treturn false', '\tfor at: float in _line_changes:\n\t\tif at > _car.s - _change_length and at < _car.s + car_ms * seconds:\n\t\t\tpass', 'he passes where the plan\'s line is about to move over'),
 (E, '\t\tif maxf(now, then) + near > -back and minf(now, then) - near < reach:\n\t\t\treturn false', '\t\tif maxf(now, then) + near > -back and minf(now, then) - near < reach:\n\t\t\tpass', 'he passes with vehicles in the two lanes'),
 (E, '\t\tvar then: float = now - (_car.speed - other.speed) * KMH_TO_MS * seconds', '\t\tvar then: float = now', 'he counts on the vehicles ahead staying where they are'),
 (E, '\t\t\t\tif _tail_slot_free(driver.s, _tail_pass_x, driver):', '\t\t\t\tif false:', 'after his stab at the brake he stays in front of the car'),
 (E, '\t\tif _tail_away < GameData.as_float(_special.get("lane_hold_s")) and _tail_room(driver) < _follow_gap:', '\t\tif false:', 'level with the car he drives through whatever is in his lane'),
 (E, '\t\t\tif _tail_slot_free(_car.s - _tail_place(driver), _car.x, driver):\n\t\t\t\t_tail_lane = car_lane\n\t\t\t\t_tail_rejoin_from', '\t\t\tif true:\n\t\t\t\t_tail_lane = car_lane\n\t\t\t\t_tail_rejoin_from', 'he swerves in behind the car into whoever is there'),
 (E, '\t\tif _tail_left_for == car_lane:\n\t\t\t# He came after the car into the lane it changed to, and the car\n\t\t\t# is still holding it.\n\t\t\t_tail_away += dt', '\t\tif _tail_left_for == car_lane:\n\t\t\t_tail_away = 0.0', 'having swerved in behind, he is never left: the 3 s start again'),
 (E, '\t_tail_behind = minf(_tail_behind + GameData.as_float(_special.get("pass_speed_kmh")) * KMH_TO_MS * dt, far)', '\t_tail_behind = _tail_place(driver)', 'hanging back he stays on the bumper'),
 (E, '\t\tfor side: int in [-1, 1]:\n\t\t\tvar lane: int = car_lane + side\n\t\t\tif lane >= 0 and lane < _car.lanes and _tail_can_pass(driver, car_lane, lane, _tail_behind, true):', '\t\tfor side: int in [-1, 1]:\n\t\t\tvar lane: int = car_lane + side\n\t\t\tif false:', 'hanging back he never passes'),
 (E, '\t\t\tif out >= 1.0:\n\t\t\t\t_tail_ahead = minf(', '\t\t\tif true:\n\t\t\t\t_tail_ahead = minf(', 'pulling out from behind he drives forward through the car'),
 (E, '\t\t\tdriver.x = lerpf(_tail_from_x, _tail_pass_x, share)\n\t\t\tdriver.lane = clampi(_car.lane_of(driver.x), 0, _car.lanes - 1)\n\t\t\tif share >= 1.0:\n\t\t\t\t_tail_falls_back(driver, driver.speed)', '\t\t\tif share >= 1.0:\n\t\t\t\t_tail_falls_back(driver, driver.speed)', 'leaving, he stays in the car\'s lane, slow'),
]
