"""Mutants of the prologue (GDD 10.1) and the finale (10.6) for
T-PROLOGUE-01 and T-FINALE-01.
    python3 tools/mutants.py T-PROLOGUE,T-FINALE tools/mutants/bookends.py
"""
D = 'src/core/drive_sim.gd'
F = 'src/core/finale_sim.gd'
G = 'src/game/game.gd'
P = 'src/core/prologue_sim.gd'
MUTANTS = [
 # The prologue's clock.
 (P, '\tif time >= _length - dt * 0.5:\n\t\tactive = false\n\t\tover = true', '\tif time >= _length * 0.5 - dt * 0.5:\n\t\tactive = false\n\t\tover = true', 'the prologue lasts half as long'),
 (P, '\tif step < _starts.size() and time >= _starts[step] - dt * 0.5:\n\t\t_begin_step(step + 1)', '\tif step < _starts.size() and (done or time >= _starts[step] - dt * 0.5):\n\t\t_begin_step(step + 1)', 'a step done hurries the next one on'),
 (P, '\tif step < _starts.size() and time >= _starts[step] - dt * 0.5:\n\t\t_begin_step(step + 1)', '\tif step < _starts.size() and done and time >= _starts[step] - dt * 0.5:\n\t\t_begin_step(step + 1)', 'a step not done holds the prologue up'),
 (P, '\tstep = number\n\tdone = false\n\tbegan = number', '\tstep = number\n\tbegan = number', 'a step done marks the next one done'),
 (P, 'if active and step >= 1 and step < RITUALS.size() and not RITUALS[step].is_empty() and RITUALS[step] == ritual_id:', 'if active and step >= 1 and step < RITUALS.size() and not RITUALS[step].is_empty():', 'any ritual does a step'),
 (P, '\tif (step == RADIO and radio_plays_music) or (step == SHIFT and gear == GEAR_TO):', '\tif (step == RADIO) or (step == SHIFT and gear == GEAR_TO):', 'the radio step is done by itself'),
 (P, '\tif (step == RADIO and radio_plays_music) or (step == SHIFT and gear == GEAR_TO):', '\tif (step == RADIO and radio_plays_music) or (step == SHIFT):', 'the gear step is done by itself'),
 (P, '\tif not active or done or step < 1 or step >= ANCHORS.size():\n\t\treturn ""', '\tif not active or step < 1 or step >= ANCHORS.size():\n\t\treturn ""', 'a step done goes on pulsing'),
 (P, 'const ANCHORS: PackedStringArray = ["", "radio", "@tea", "gear_lever", "horn", "wiper_stalk", "dash_1", ""]', 'const ANCHORS: PackedStringArray = ["", "radio", "@tea", "horn", "gear_lever", "wiper_stalk", "dash_1", ""]', 'the lever pulses for the horn\'s step'),
 (P, '\treturn active and step >= WIPERS', '\treturn active', 'it rains all morning'),
 (P, '\treturn active and step >= WIPERS', '\treturn false', 'it never rains'),
 (P, '\treturn clampf((time - step_start(LIFT)) / maxf(step_length(LIFT), 0.001), 0.0, 1.0)', '\treturn 1.0', 'the screen is white at once'),
 # The prologue in the car.
 (D, '\treturn prologue.active and not hand.gripping\n', '\treturn false\n', 'there is no left hand'),
 (D, '\treturn prologue.active and not hand.gripping\n', '\treturn prologue.active\n', 'the left hand takes the wheel from the right'),
 (D, '\t\twheel.hold_at(_lane_keeping_angle(_prologue_lane))', '\t\twheel.hold_at(wheel.angle)', 'the left hand holds the wheel where it is'),
 (D, '\tif not _standing() and not prologue.active:\n\t\t# (The prologue cannot be failed', '\tif not _standing():\n\t\t# (The prologue cannot be failed', 'things are hit in the prologue'),
 (D, '\t\tif prologue.active:\n\t\t\t# "Nothing it does has a cost" (GDD 10.1): he is as calm as he was.\n\t\t\tnerves.set_value(0.0)\n\t\telse:\n\t\t\t_feed_nerves()\n\t\t\tnerves.step(DT)', '\t\tif false:\n\t\t\tpass\n\t\telse:\n\t\t\t_feed_nerves()\n\t\t\tnerves.step(DT)', 'his Nerves move in the prologue'),
 (D, '\tif prologue.began > 0 and prologue.began < PrologueSim.LIFT:', '\tif prologue.began > 0:', 'the seventh step has a prompt'),
 (D, '\tif prologue.began > 0 and prologue.began < PrologueSim.LIFT:', '\tif false:', 'no subtitle names the action'),
 (D, '\t\t\titems.raining = true\n\t\t\tvar way: int', '\t\t\tvar way: int', 'the rain is not on the glass'),
 (D, '\t\t\titems.indicate(way)\n\t\t\t_prologue_lane += way', '\t\t\t_prologue_lane += way', 'the left hand does not indicate'),
 (D, '\t\t\titems.indicate(way)\n\t\t\t_prologue_lane += way', '\t\t\titems.indicate(way)', 'the car does not change lane'),
 (D, '\t\t\ttraffic.spawn(StringName(GameData.as_string(friend.get("vehicle"))), beside,\n\t\t\t\t\tcar.s - GameData.as_float(friend.get("behind_m")), car.speed + GameData.as_float(friend.get("faster_kmh")))', '\t\t\tpass', 'no friend passes'),
 (D, '\tif prologue.over:\n\t\t# "Cut to tonight. 22:00."\n\t\tbegin_telling(_prologue_table, _prologue_seed)', '\tif prologue.over:\n\t\t# "Cut to tonight. 22:00."\n\t\tbegin_telling("", _prologue_seed)', 'tonight is told to no Table'),
 (D, '\tif prologue.over:\n\t\t# "Cut to tonight. 22:00."\n\t\tbegin_telling(_prologue_table, _prologue_seed)', '\tif prologue.over:\n\t\t# "Cut to tonight. 22:00."\n\t\tbegin_telling(_prologue_table, _prologue_seed + 1)', 'tonight is another night than the seed\'s'),
 (D, '\t# His first words to the Table (GDD 3.6, 10.1): the night begins.\n\t_emit("line_requested", {"id": "narrator.start"})\n', '', 'the narrator says nothing'),
 (D, '\tgate.reset(PrologueSim.GEAR_FROM)\n\tcar.reset(car.lanes / 2, PrologueSim.GEAR_FROM)', '\tgate.reset(PrologueSim.GEAR_TO)\n\tcar.reset(car.lanes / 2, PrologueSim.GEAR_TO)', 'the morning begins in third gear'),
 (D, '\titems.flags[FLAG_PROLOGUE] = true\n\t_sync_anchors()', '\t_sync_anchors()', 'no photo lies on the dash'),
 (D, '\tif not _standing() and not parked and not prologue.active:\n\t\tclock.step(DT)', '\tif not _standing() and not parked:\n\t\tclock.step(DT)', 'tonight\'s Clock runs in the morning'),
 (D, '\tif prologue.changes_lane() and items.indicator != 0:\n\t\treturn "indicator_stalk"', '\tif false:\n\t\treturn "indicator_stalk"', 'the left hand is never shown at the stalk'),
 (D, '\tif prologue.step == PrologueSim.LIFT:\n\t\treturn "window_crank"', '\tif false:\n\t\treturn "window_crank"', 'the left hand is never shown lifting'),
 (G, '\treturn not GameData.as_bool(profile.get("prologue_seen")) and not args.has("skip-prologue")', '\treturn not args.has("skip-prologue")', 'the prologue plays at every launch'),
 (G, '\treturn not GameData.as_bool(profile.get("prologue_seen")) and not args.has("skip-prologue")', '\treturn not GameData.as_bool(profile.get("prologue_seen"))', '--skip-prologue skips nothing'),
 (G, '\tprofile["prologue_seen"] = true\n\twrite_save(saved_telling)', '\tprofile["prologue_seen"] = true', 'that the prologue was seen is not saved'),
 (G, '\treturn AppState.PROLOGUE if wants_prologue() else AppState.WEDDING', '\treturn AppState.WEDDING', 'the title never leads to the prologue'),
 # The finale.
 (F, '\t\t\tif pressed and on_palm:', '\t\t\tif pressed:', 'a TAP anywhere is a clap'),
 (F, '\t\t\tif pressed and on_palm:', '\t\t\tif down and on_palm:', 'a held hand claps every tick'),
 (F, '\t\t\t\tif claps >= _claps_needed:', '\t\t\t\tif claps >= _claps_needed - 1:', 'she takes his hand a clap early'),
 (F, '\t\t\t\t\tphase = WALKING\n\t\t\t\t\tholding = true', '\t\t\t\t\tphase = STANDING\n\t\t\t\t\tholding = true', 'there is no walk'),
 (F, '\t\t\tholding = down\n\t\t\tif holding:\n\t\t\t\twalked += dt', '\t\t\tholding = down\n\t\t\tif true:\n\t\t\t\twalked += dt', 'they walk whether he holds her hand or not'),
 (F, '\t\t\tholding = down\n\t\t\tif holding:', '\t\t\tholding = down\n\t\t\tif not down:\n\t\t\t\tphase = OVER\n\t\t\tif holding:', 'letting go on the way ends it'),
 (F, '\t\t\t\tif walked >= _walk - dt * 0.5:', '\t\t\t\tif walked >= _walk * 0.5 - dt * 0.5:', 'the walk takes half as long'),
 (F, '\t\t\tif not down:\n\t\t\t\t# "On release her hand goes to the groom\'s."\n\t\t\t\tholding = false\n\t\t\t\tphase = OVER', '\t\t\tif not down or stood >= 120.0:\n\t\t\t\t# "On release her hand goes to the groom\'s."\n\t\t\t\tholding = false\n\t\t\t\tphase = OVER', 'it ends by itself after two minutes'),
 (F, '\t\t\tif not down:\n\t\t\t\t# "On release her hand goes to the groom\'s."\n\t\t\t\tholding = false\n\t\t\t\tphase = OVER', '\t\t\tif false:\n\t\t\t\t# "On release her hand goes to the groom\'s."\n\t\t\t\tholding = false\n\t\t\t\tphase = OVER', 'letting go ends nothing'),
 (F, '\t\t\t\tevents.append({"type": "line_requested", "id": "finale.proverb"})\n', '', 'no proverb at the end'),
 (F, '\t\t\tif not said_baba and stood >= _baba - dt * 0.5:', '\t\t\tif not said_baba and time >= _baba - dt * 0.5:', '"Baba." by the finale\'s clock, not by the standing'),
 (F, '\t\t\tif not said_baba and stood >= _baba - dt * 0.5:', '\t\t\tif stood >= _baba - dt * 0.5:', 'she says "Baba." every tick'),
 (F, '\t\t\tif not clapping_again and stood >= _clap_again - dt * 0.5:', '\t\t\tif not clapping_again and stood >= _baba - dt * 0.5:', 'the room claps again with her word'),
 (F, '\tif phase == OVER:\n\t\treturn\n\ttime += dt', '\ttime += dt', 'the finale goes on after its end'),
 (F, '\treturn claps\n', '\treturn 0\n', 'the room\'s clapping never doubles'),
]
