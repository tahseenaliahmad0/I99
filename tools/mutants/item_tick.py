"""Mutants of what ItemSim keeps for the tick (read once when the cabin changes) for the item tests. All 22 are killed.
    python3 tools/mutants.py T-ITEM,T-SYN tools/mutants/item_tick.py
The tick's cost was cut without changing what it does; these show that the
tests of the items hold each kept value to what the record says.
"""
I = 'src/core/item_sim.gd'
MUTANTS = [
 (I, '\titem.side_s = _param(item, "side_s", INF)\n', '', 'a tape never warbles'),
 (I, '\titem.ash_by = _param(item, "ash_by_s", 0.0)\n', '', 'no smoke has an ash time'),
 (I, '\titem.is_phone = GameData.as_array(record.get("tags")).has(TAG_PHONE)\n', '', 'nothing takes calls'),
 (I, '\titem.synergies = GameData.as_array(record.get("synergies"))\n', '', 'no item has a synergy'),
 (I, '\titem.smokes = not (item.ash_by <= 0.0 or item.use_effect == &"")\n', '', 'nothing burns down'),
 (I, '\t_phone = handset\n', '', 'the cabin forgets its phone'),
 (I, '\t_tape = cassette\n', '', 'the cabin forgets its tape'),
 (I, '\t_keeps_warm = keeps_warm\n', '', 'chewing keeps nothing warm'),
 (I, '\t_haze_clear_mult = passive("haze_clear_mult")\n', '', 'the haze clears as if nothing hung in the car'),
 (I, '\t\t\thot -= dt\n', '\t\t\tpass\n', 'nothing cools'),
 (I, '\t\tcandidate.hot_left = hot\n', '', 'the cooling is not kept'),
 (I, '\t\tif hot < half_tick:\n\t\t\thot = 0.0\n', '', 'heat runs below nothing'),
 (I, '\t\tif candidate.smokes:\n\t\t\t_step_smoke(candidate, dt)', '\t\tif false:\n\t\t\t_step_smoke(candidate, dt)', 'no smoke burns'),
 (I, '\t\tif not (candidate.lapse_left < 0.0 or candidate.burning):\n\t\t\t_step_lapse(candidate, dt)', '\t\tif false:\n\t\t\t_step_lapse(candidate, dt)', 'no craving bites'),
 (I, '\tif window_open:\n\t\thaze_rate += dust_rate', '\tif false:\n\t\thaze_rate += dust_rate', 'an open window lets no dust in'),
 (I, '_haze_clear * _haze_clear_mult * (_window_haze_mult if window_open else 1.0)', '_haze_clear * _haze_clear_mult', 'an open window clears no faster'),
 (I, '(deck_mult if candidate.is_tape else 1.0)', '1.0', 'the window does not halve the tape'),
 (I, 'var deck_mult: float = _window_radio_mult if window_open else 1.0', 'var deck_mult: float = 1.0', 'the deck is as loud with the window open'),
 (I, 'met = owner != null and owner.is_tape and not (owner.side_time >= owner.side_s)', 'met = owner != null and owner.is_tape', 'a tape plays for ever'),
 (I, 'met = owner != null and owner.is_tape and owner.side_time >= owner.side_s', 'met = false', 'a tape never warbles (condition)'),
 (I, '_nerves.add_rate(_radio_music_rate * (_window_radio_mult if flag(FLAG_WINDOW) else 1.0))', '_nerves.add_rate(_radio_music_rate)', 'the window does not halve the radio\'s music'),
 (I, '\tvar ash_by: float = candidate.ash_by\n', '\tvar ash_by: float = candidate.ash_by * 2.0\n', 'the ash falls late'),
]
