"""Mutants of the endings and what persists (GDD 11.4, 11.5) for T-END-01.
    python3 tools/mutants.py T-END tools/mutants/endings.py
"""
D = 'src/core/drive_sim.gd'
G = 'src/game/game.gd'
V = 'src/core/save.gd'
MUTANTS = [
 (V, '\tif GameData.as_bool(arrived.get("late")):\n\t\treturn LATE\n', '', 'nobody is ever late'),
 (V, '\treturn THE_CALL if GameData.as_bool(arrived.get("call")) else ON_TIME', '\treturn ON_TIME', 'the Call is no ending'),
 (V, '\treturn THE_CALL if GameData.as_bool(arrived.get("call")) else ON_TIME', '\treturn THE_CALL', 'every win is a Call ending'),
 (V, '\tif ending == LATE or table_id.is_empty():', '\tif table_id.is_empty():', 'a late night unlocks like any other'),
 (V, '\tout["tables"] = TableRules.win(data, profile, table_id)', '\tout["tables"] = PackedStringArray()', 'a win opens no Table'),
 (V, '\tif _add(profile, "modes", COMMUTE):\n\t\tmodes.append(COMMUTE)\n', '', 'the first win earns no Commute'),
 (V, '\tif _add(profile, "modes", COMMUTE):\n\t\tmodes.append(COMMUTE)\n', '\tif ending == THE_CALL and _add(profile, "modes", COMMUTE):\n\t\tmodes.append(COMMUTE)\n', 'only a Call ending earns the Commute'),
 (V, '\tif ending == THE_CALL:\n\t\tout["told_true"]', '\tif true:\n\t\tout["told_true"]', 'every win is told true'),
 (V, '\t\tout["told_true"] = _add(profile, "told_true", table_id)', '\t\tout["told_true"] = false', 'the Call marks nothing told true'),
 (V, '\t\tif _add(profile, "modes", ENDLESS_NIGHT):\n\t\t\tmodes.append(ENDLESS_NIGHT)\n', '', 'a Call ending earns no Endless Night'),
 (V, '\t\tout["finale"] = data.has_record("tables", table_id) and TableRules.opened_by(data, table_id).is_empty()', '\t\tout["finale"] = data.has_record("tables", table_id)', 'the finale follows the Call at any Table'),
 (V, '\t\tout["finale"] = data.has_record("tables", table_id) and TableRules.opened_by(data, table_id).is_empty()', '\t\tout["finale"] = false', 'there is no finale'),
 (V, '\tif not guest.is_empty() and _add(profile, "guests", guest):\n\t\tout["guest"] = guest\n', '', 'nobody becomes a wedding guest'),
 (V, '\tif not guest.is_empty() and _add(profile, "guests", guest):', '\tif not guest.is_empty() and ending != LATE and _add(profile, "guests", guest):', 'a passenger carried there late is no guest'),
 (V, '\tif not guest.is_empty() and _add(profile, "guests", guest):\n\t\tout["guest"] = guest\n', '\tif not guest.is_empty() and _add(profile, "guests", guest):\n\t\tpass\n', 'the result does not name the new guest'),
 (V, '\tif list.has(value):\n\t\treturn false\n', '', 'the profile holds things twice'),
 (V, '\tout["modes"] = modes\n', '', 'the result names no mode'),
 (V, '\tfor table_id: String in TableRules.open_at_start(data):', '\tfor table_id: String in data.record_ids("tables"):', 'a new player has every Table'),
 (G, '\tvar result: Dictionary = Save.apply_ending(data, profile, arrived)\n\twrite_save({})', '\tvar result: Dictionary = Save.apply_ending(data, profile, arrived)\n\twrite_save(saved_telling)', 'the Telling that is over stays on disk'),
 (G, '\tvar result: Dictionary = Save.apply_ending(data, profile, arrived)\n\twrite_save({})', '\tvar result: Dictionary = Save.apply_ending(data, profile, arrived)', 'the ending is not written to disk'),
 (G, '\tvar result: Dictionary = Save.apply_ending(data, profile, arrived)', '\tvar result: Dictionary = Save.apply_ending(data, profile.duplicate(true), arrived)', 'the ending never reaches the profile'),
 (D, '"late": clock.late(), "call": told_true,', '"late": false, "call": told_true,', 'the arrival never says he is late'),
 (D, '"late": clock.late(), "call": told_true,', '"late": clock.late(), "call": false,', 'the arrival never says he answered'),
 (D, '\t\t\t"guest": passengers.id})', '\t\t\t"guest": ""})', 'the arrival names nobody beside him'),
 (D, '\tif wrecked and run.active:\n\t\t# The Wreck (GDD 11.4): nothing moves while the Table objects; then\n\t\t# the Telling is told again from Baghdad.\n\t\t_wreck_left -= DT', '\tif wrecked and run.active:\n\t\t# The Wreck (GDD 11.4): nothing moves while the Table objects; then\n\t\t# the Telling is told again from Baghdad.\n\t\t_wreck_left -= DT * 2.0', 'the Table objects for half as long'),
]
