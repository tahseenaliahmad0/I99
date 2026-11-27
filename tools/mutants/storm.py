"""Mutants of the Storm (GDD 10.3) for T-BOSS-02.
    python3 tools/mutants.py T-BOSS-02 tools/mutants/storm.py
"""
B = 'src/core/boss_sim.gd'
D = 'src/core/drive_sim.gd'
L = 'src/core/leg_sim.gd'
I = 'src/core/item_sim.gd'
G = 'src/core/run_generator.gd'
MUTANTS = [
 (B, 'thick = at >= _thin_s', 'thick = at < _thin_s', 'dust opens thick'),
 (B, 'visibility = _thick_m if thick else _thin_m', 'visibility = _thin_m if thick else _thick_m', 'thick and thin swapped'),
 (B, 'var at: float = fposmod(time + dt * 0.5, cycle)', 'var at: float = fposmod(time + dt * 1.5, cycle)', 'dust changes a tick early'),
 (B, 'var cycle: float = _thin_s + _thick_s', 'var cycle: float = _thin_s + _thick_s + 1.0', 'cycle a second long'),
 (B, 'dust_change_in = maxf((cycle if thick else _thin_s) - at + dt * 0.5, 0.0)', 'dust_change_in = maxf(_thin_s - at + dt * 0.5, 0.0)', 'change_in wrong in thick dust'),
 (B, '\tif driving or (hazards_on and off_the_lanes):', '\tif driving or hazards_on:', 'hazards alone are safe'),
 (B, '\tif driving or (hazards_on and off_the_lanes):', '\tif driving or off_the_lanes:', 'shoulder alone is safe'),
 (B, 'var off_the_lanes: bool = _car.x - _car.half_width() >= _car.road_right()', 'var off_the_lanes: bool = _car.x >= _car.road_right()', 'half on the shoulder counts'),
 (B, 'var driving: bool = _car.speed >= _moved_off_kmh if waiting else _car.speed > _stopped_kmh', 'var driving: bool = _car.speed >= _moved_off_kmh if waiting else _car.speed > _stopped_kmh + 5.0', 'a crawl counts as stopped'),
 (B, '\tif _coming and not _horned and _stood >= _rear_end_every - _rear_end_tell - dt * 0.5:', '\tif _coming and not _horned and _stood >= _rear_end_every - dt * 0.5:', 'no tell before the hit'),
 (B, '\t\trear_end = _coming\n', '\t\trear_end = true\n', 'every wait ends in a hit'),
 (B, '_coming = _rng.chance(Rng.ROAD, _rear_end_chance)', '_coming = true', 'chance is certainty'),
 (B, '_coming = _rng.chance(Rng.ROAD, _rear_end_chance)', '_coming = _rng.chance(Rng.ROAD, _rear_end_chance * 0.1)', 'a tenth of the chance'),
 (B, 'func _end_the_wait() -> void:\n\t_stood = 0.0\n\t_drawn = false\n\t_coming = false\n', 'func _end_the_wait() -> void:\n\t_stood = 0.0\n', 'what was coming still comes after he moved'),
 (B, '\trear_end_in = left if _horned else 0.0', '\trear_end_in = 0.0', 'nothing is coming by the snapshot'),
 (B, 'if _stood >= _rear_end_every - dt * 0.5:', 'if _stood >= _rear_end_every * 0.5 - dt * 0.5:', 'hit after 5 s'),
 (B, 'out["gust_push"] = GameData.as_float(storm.get("gust_push")) * GameData.as_float(modifier.get("gust_mult"), 1.0)', 'out["gust_push"] = GameData.as_float(storm.get("gust_push"))', 'crosswind no stronger'),
 (B, '\tif GameData.as_bool(modifier.get("night")):\n\t\tout["condition"] = NIGHT\n', '', 'night storm by day'),
 (B, '\t\tif next_lane == lane:\n\t\t\tnext_lane = (next_lane + 1) % lanes\n', '', 'two tail lights in a row in one lane'),
 (B, 'gusts.append({"s": snappedf(at, 0.01), "dir": 1 if random.randf() < 0.5 else -1})', 'gusts.append({"s": snappedf(at, 0.01), "dir": 1})', 'gusts only from one side'),
 (B, '\tif not modifier_id.is_empty() and GameData.as_array(record.get("modifiers")).has(modifier_id):', '\tif not modifier_id.is_empty():', 'another boss\'s modifier taken'),
 (D, '\t\t\tcollision.strike(Collision.Hit.CRASH)', '\t\t\tcollision.strike(Collision.Hit.SCRAPE)', 'rear-end is a scrape'),
 (D, '"rear_end": boss.rear_end})', '"rear_end": false})', 'hit event does not say rear-end'),
 (D, '\t\t_blow(leg.gust_started, leg.gust_push)', '\t\tstart_gust(leg.gust_started)', 'storm gusts at the usual push'),
 (D, 'var reach: float = minf(leg.dust_visibility, dust)', 'var reach: float = leg.dust_visibility', 'dust does not limit his view'),
 (D, 'if not leg.active or not (leg.raining or leg.night or boss.kind == BossSim.STORM) or _standing():', 'if not leg.active or not (leg.raining or leg.night) or _standing():', 'no cramp in the Storm'),
 (D, '\t_roll_into(BossSim.plan(data, run.boss, run.boss_modifier, RunGenerator.boss_seed(run.seed, run.act)))', '\t_roll_into(BossSim.plan(data, run.boss, "", RunGenerator.boss_seed(run.seed, run.act)))', 'the Telling\'s modifier dropped'),
 (D, '\t\t"dust_thick": boss.thick,', '\t\t"dust_thick": false,', 'snapshot never thick'),
 (D, '\t\t\tboss.stop()\n\t\t\t_clear_weather()\n', '\t\t\tboss.stop()\n', 'weather kept after a boss by itself'),
 (D, '\tboss.step_road(_road_dt, DT, items.flag(FLAG_HAZARDS))', '\tboss.step_road(_road_dt, DT, false)', 'hazard lights not passed on'),
 (L, '\tdust_rate = GameData.as_float(plan.get("window_haze_per_s"))', '\tdust_rate = 0.0', 'open window lets no dust in'),
 (L, '\twipe_haze = GameData.as_float(plan.get("wipe_haze"))', '\twipe_haze = 0.0', 'wipers smear nothing'),
 (L, '\t\tif gust_tell_left < dt * 0.5:', '\t\tif gust_tell_left <= 0.0:', 'tell runs a tick over'),
 (I, '\t\t\t\thaze = minf(haze + wipe_haze, _haze_cap)', '\t\t\t\thaze = haze + wipe_haze', 'smear beyond the cap'),
 (I, '\t\t\t\thaze = minf(haze + wipe_haze, _haze_cap)', '\t\t\t\thaze = minf(haze + wipe_haze * 0.5, _haze_cap)', 'half a smear'),
 (G, '\tif allowed.is_empty() or roll >= data.tuning.fi("boss_modifier_chance", clampi(act, 1, ACTS) - 1):', '\tif allowed.is_empty():', 'every boss has a modifier'),
 (G, '\treturn GameData.as_string(allowed[which])', '\treturn GameData.as_string(allowed[0])', 'always the first modifier'),
 (G, '\tif allowed.is_empty() or roll >= data.tuning.fi("boss_modifier_chance", clampi(act, 1, ACTS) - 1):', '\tif allowed.is_empty() or roll >= data.tuning.fi("boss_modifier_chance", 0):', 'act 1\'s share for every act'),
 # the dust's tell (pillar 4, GDD 17.2)
 (B, 'dust_closing = clampf(1.0 - dust_change_in / _dust_tell, 0.0, 1.0) if not thick and _dust_tell > 0.0 else 0.0', 'dust_closing = clampf(1.0 - dust_change_in / _dust_tell, 0.0, 1.0) if _dust_tell > 0.0 else 0.0', 'thick dust closes in on itself before it thins'),
 (B, 'dust_closing = clampf(1.0 - dust_change_in / _dust_tell, 0.0, 1.0) if not thick and _dust_tell > 0.0 else 0.0', 'dust_closing = clampf(dust_change_in / _dust_tell, 0.0, 1.0) if not thick and _dust_tell > 0.0 else 0.0', 'the closing runs backwards'),
 (B, '\treturn _thick_m if kind == STORM and active else INF', '\treturn _thin_m if kind == STORM and active else INF', 'it closes in to the thin dust'),
 (D, '\t\tsight = lerpf(sight, _sight_in(boss.thick_visibility()), boss.dust_closing)', '\t\tsight = _sight_in(boss.thick_visibility())', 'shown thick from the first tick of the tell'),
 (D, '\tif boss.dust_closing > 0.0 and is_finite(sight):', '\tif false:', 'nothing is shown closing in'),
 (D, '\t\t"sight_shown": sight_shown(),', '\t\t"sight_shown": visibility(),', 'the snapshot shows what he sees'),
 (D, '\t\t"dust_closing": boss.dust_closing,', '\t\t"dust_closing": 0.0,', 'the snapshot never says the dust closes in'),
 (B, '\t\t_dust_tell = GameData.as_float(storm.get("dust_tell_s"))', '\t\t_dust_tell = GameData.as_float(storm.get("dust_tell_s")) * 0.5', 'half the tell'),
]
