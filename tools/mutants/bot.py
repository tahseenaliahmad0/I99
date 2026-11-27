"""Mutants of the DriverBot and the balance runner (GDD 13.8, 12.5, D-068)
for T-BOT-01.
    python3 tools/mutants.py T-BOT tools/mutants/bot.py

Not in the list: the bot asks whether the lever is in its hand before it
puts it in gear. It always is by then (it does not go for the lever when a
passenger leans across it), and GearGate.place_held refuses by itself.
"""
B = 'src/game/driver_bot.gd'
G = 'src/core/gear_gate.gd'
R = 'src/game/balance_run.gd'
MUTANTS = [
 (B, '\t_reaction_ticks = maxi(roundi(_tuning.fi("bot_reaction_s", _index) / DriveSim.DT), 1)', '\t_reaction_ticks = 1', 'it acts at once: no reaction delay'),
 (B, '\t_lane_error = _tuning.fi("bot_lane_error_m", _index)', '\t_lane_error = 0.0', 'it keeps its lane exactly'),
 (B, '\t_lane_error = _tuning.fi("bot_lane_error_m", _index)', '\t_lane_error = _tuning.fi("bot_lane_error_m", 0)', 'every skill wanders as the novice does'),
 (B, '\t_index = SKILLS.find(skill)', '\t_index = 1', 'every skill is the competent one'),
 (B, '\tif not _sim.hand.gripping:\n\t\treturn\n\tvar car: CarSim = _sim.car\n\tvar authority', '\tvar car: CarSim = _sim.car\n\tvar authority', 'it steers with no hand on the wheel'),
 (B, '\t\t\treturn [["go", "gear_lever"], ["shift", _ticks(_tuning.f("bot_shift_s")), _want_gear], ["up", 2]]', '\t\t\treturn [["go", "gear_lever"], ["shift", 1, _want_gear], ["up", 2]]', 'a change of gear takes no time at the lever'),
 (G, '\tif not held or lock_left > 0.0:\n\t\treturn\n\t_place(gear_number)', '\t_place(gear_number)', 'the lever goes into a gear without a hand on it'),
 (B, '\t\tif calm >= _task_time("shift"):', '\t\tif true:', 'it lets go for the lever whatever is ahead'),
 (B, '\t\t\tif beside[next] == 0 and soon[next] >= change_ttc:\n\t\t\t\twanted = next', '\t\t\tif false:\n\t\t\t\twanted = next', 'it never changes lane for a better one'),
 (B, '\t\tvar urgent: bool = soon[current] < change_ttc', '\t\tvar urgent: bool = false', 'time to collision under 3 s is nothing urgent'),
 (B, '\t\tif settled and gap < distance and closing > -1.0 and not rammed:', '\t\tif false:', 'it keeps no distance behind what it follows'),
 (B, '\t\t\tneeded = distance + closing * closing / (2.0 * decel) + closing * late', '\t\t\tneeded = 0.0', 'it does not brake for what it comes up on'),
 (R, '\treturn LATE if Save.ending_of(arrived) == Save.LATE else WON', '\treturn WON', 'a late night counts as won'),
 (R, '\t\tcell["win_share"] = snappedf(float(GameData.as_int(cell["won"])) / count, 0.001)', '\t\tcell["win_share"] = snappedf(float(GameData.as_int(cell["won"]) + GameData.as_int(cell["late"])) / count, 0.001)', 'the win share counts the late nights'),
 (R, '\tvar within: bool = value >= _tuning.fi(tuning_name, 0) - 0.0005 and value <= _tuning.fi(tuning_name, 1) + 0.0005', '\tvar within: bool = true', 'every share is within its target'),
 (R, '\tif cell == null:\n\t\treturn {"id": id, "measure": name, "target": target, "measured": null, "unit": "share", "within": false, "sample": 0}', '\tif cell == null:\n\t\treturn {"id": id, "measure": name, "target": target, "measured": 0.0, "unit": "share", "within": true, "sample": 0}', 'what was not run is reported as measured and within'),
 (R, '\t\t\tif GameData.as_bool(telling["wreck_from_one_event"]):\n\t\t\t\tfrom_one += 1', '\t\t\tif false:\n\t\t\t\tfrom_one += 1', 'no Wreck is ever counted as from one event'),
 (R, '\t\t\tfrom_one == 0, wrecks))', '\t\t\ttrue, wrecks))', 'Wrecks from one event are always within target'),
 (R, '\t\tcell["hand_off_share_act2"] = snappedf(float(GameData.as_int(cell["hand_off_act2"])) / maxf(float(GameData.as_int(cell["road_act2"])), 1.0), 0.001)', '\t\tcell["hand_off_share_act2"] = 0.3', 'the hand-off share is not measured'),
 (R, '\tvar bot: DriverBot = DriverBot.new(sim, _data, skill, Rng.derive(telling_seed, DriverBot.SEED_SALT))', '\tvar bot: DriverBot = DriverBot.new(sim, _data, skill, Time.get_ticks_usec())', 'the bot draws from the clock: no two Tellings alike'),
]
