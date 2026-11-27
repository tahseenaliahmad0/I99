"""Mutants of what happens at a stop, while pulled over and at the seams
between stretches (the M6 review's findings on those; decisions D-a to D-f
of that work).

    python3 tools/mutants.py T-STOP,T-LEG-07,T-SAVE,T-REPLAY,T-RUN-01,T-NERVES-01,T-ITEM-BASE,T-ITEM-CIGARETTES,T-ITEM-PHONE,T-ITEM-PAINKILLERS,T-ITEM-ENERGY-DRINK,T-ITEM-CHARM,T-ITEM-DUCT-TAPE tools/mutants/seams.py

All 42 are killed. (Each group needs only the tests of its rule: the night
waits: T-STOP,T-LEG-07,T-NERVES-01; once per leg: T-ITEM-BASE,T-ITEM-CHARM,
T-ITEM-PAINKILLERS,T-SAVE; what is owed: T-ITEM-CIGARETTES,T-ITEM-PHONE,
T-SAVE,T-REPLAY; the first scrape: T-ITEM-CHARM,T-ITEM-DUCT-TAPE; what a
stop ends: T-ITEM-DUCT-TAPE,T-ITEM-PHONE,T-ITEM-ENERGY-DRINK,
T-ITEM-PAINKILLERS,T-RUN-01,T-NERVES-01.)
"""
D = 'src/core/drive_sim.gd'
I = 'src/core/item_sim.gd'
N = 'src/core/nerves_sim.gd'

WAITS = '\tif _standing():\n\t\tnerves.step_snap(DT)\n\telse:\n\t\teffects.step(DT)\n'
IN_USE = '\tif _standing():\n\t\treturn not _ritual_at(anchor).is_empty()\n\treturn items.anchor_in_use(anchor)\n'

MUTANTS = [
 # --- The night waits: a stop, and an officer at his window (D-a, D-b).
 (D, WAITS, WAITS.replace('\t\tnerves.step_snap(DT)\n', '\t\tpass\n'), 'a Snap never ends where the night waits'),
 (D, WAITS, WAITS.replace('if _standing():', 'if stopped:'), 'the night goes on while he is pulled over'),
 (D, WAITS, WAITS.replace('\t\tnerves.step_snap(DT)\n', '\t\tnerves.step_snap(DT)\n\t\teffects.step(DT)\n'), 'effect timers run where the night waits'),
 (D, WAITS, WAITS.replace('\t\tnerves.step_snap(DT)\n', '\t\tnerves.step_snap(DT)\n\t\titems.step(DT)\n'), 'items step where the night waits'),
 (D, WAITS, WAITS.replace('\t\tnerves.step_snap(DT)\n', '\t\tnerves.step(DT)\n'), 'he dozes where the night waits'),
 (N, '\tsnap_left -= dt\n\tif snap_left < dt * 0.5:', '\tsnap_left -= dt * 0.5\n\tif snap_left < dt * 0.5:', 'a Snap lasts twice as long'),
 (D, IN_USE, IN_USE.replace('if _standing():', 'if pulled_over:').replace('\treturn items.anchor_in_use(anchor)\n', '\treturn items.anchor_in_use(anchor) or stop.anchor_in_use(anchor)\n'),
  'at a stop the cabin\'s anchors are in use beside the tray\'s (as before)'),
 (D, IN_USE, IN_USE.replace('if _standing():', 'if stopped:'), 'pulled over, the cabin\'s anchors are in use (as before)'),
 (D, '\tif stopped:\n\t\treturn stop.ritual_at(anchor)\n\tif pulled_over:', '\tif stopped and stop.anchor_in_use(anchor):\n\t\treturn stop.ritual_at(anchor)\n\tif pulled_over:',
  'at a stop the cabin\'s rituals are offered beside the tray (as before)'),
 (D, '\tif pulled_over:\n\t\treturn items.ritual_for(PULLED_OVER, anchor)\n', '', 'pulled over, the cabin\'s rituals are offered (as before)'),
 (I, 'if GameData.as_array(control.get("requires")).has(String(status)) and _requirements_hold(control, null):', 'if _requirements_hold(control, null):',
  'every control counts as the officer\'s'),
 (D, 'nerves.snap_left <= 0.0 and not _standing():', 'nerves.snap_left <= 0.0:', 'the thumb keypad works where the night waits'),
 (D, 'nerves.snap_left <= 0.0 and not _standing():', 'nerves.snap_left <= 0.0 and not stopped:', 'the thumb keypad works while he is pulled over'),
 (D, 'nerves.snap_left <= 0.0 and not _standing():', 'nerves.snap_left <= 0.0 and not pulled_over:', 'the thumb keypad works at a stop'),
 (D, '\tnerves.rouse()\n', '', 'pulled over in a blink, his eyes stay shut'),
 (N, '\tlids = 0.0\n\teyes_shut = false\n\t_blink_clock = 0.0\n', '\teyes_shut = false\n\t_blink_clock = 0.0\n', 'his lids stay down while the officer waits'),
 (N, '\teyes_shut = false\n\t_blink_clock = 0.0\n\t_nod_clock = 0.0\n\t_nod_cancelled = false\n\n\nfunc _snap', '\teyes_shut = false\n\n\nfunc _snap',
  'let go, he picks the blink up where it stopped'),
 # --- Once per leg (D-c).
 (D, 'RunGenerator.blank_plan(run.act, RunGenerator.ROAD_LANES, true, length), false)', 'RunGenerator.blank_plan(run.act, RunGenerator.ROAD_LANES, true, length))',
  'the road to a fork renews what is once per leg'),
 (D, '\t\t\t_set_stretch(BossSim.arrival_plan(data, run.act), false)', '\t\t\t_set_stretch(BossSim.arrival_plan(data, run.act))',
  'the street of the Arrival renews what is once per leg'),
 (D, '\titems.set_leg_state(GameData.as_dict(telling.get("leg_state")))\n',
  '\tif run.stage == RunState.Stage.STOP:\n\t\titems.set_leg_state(GameData.as_dict(telling.get("leg_state")))\n', 'a boss stop forgets what was done once in the boss'),
 (D, '\titems.set_leg_state(GameData.as_dict(telling.get("leg_state")))\n',
  '\tif run.stage != RunState.Stage.STOP:\n\t\titems.set_leg_state(GameData.as_dict(telling.get("leg_state")))\n', 'a leg\'s stop forgets what was done once on the leg'),
 (D, '\t_set_stretch(plan)\n\tvar room: float', '\t_set_stretch(plan, run.stage != RunState.Stage.BOSS)\n\tvar room: float', 'a boss does not renew what is once per leg'),
 (D, '\t_set_stretch(plan)\n\tvar room: float', '\t_set_stretch(plan, run.stage == RunState.Stage.BOSS)\n\tvar room: float', 'a leg does not renew it at the gore'),
 # --- What is owed passes through a stop (D-d).
 (D, '\t\t\tif item.lapse_left >= 0.0:\n', '\t\t\tif false:\n', 'the save does not hold the craving'),
 (D, '\t\t\titem.lapse_left = Save.from_exact(kept.get("lapse"), item.lapse_left)\n', '', 'the craving is not read from the save'),
 (I, '\t\tif candidate.burning:\n\t\t\t_burn_out(candidate)', '\t\tif false:\n\t\t\t_burn_out(candidate)', 'a cigarette the stop puts out leaves no craving'),
 (I, '"call_wait": Save.exact(_call_wait), ', '"call_wait": Save.exact(-1.0), ', 'the save does not hold the wait for the next call'),
 (I, '\t_call_wait = Save.from_exact(state.get("call_wait"), -1.0)\n', '', 'the wait for the next call is not read from the save'),
 # --- The first scrape, the first fault (D-e).
 (I, '\tvar first: bool = not scrape_spared\n\tscrape_spared = true\n\treturn first and passive("first_scrape_free") > 0.0',
  '\tif scrape_spared or passive("first_scrape_free") <= 0.0:\n\t\treturn false\n\tscrape_spared = true\n\treturn true',
  'the leg\'s first scrape is marked only with the charm aboard (as before)'),
 (I, '\tif drawn.is_empty() or tape_spent:\n\t\treturn\n\ttape_spent = true\n\tvar after: float = passive("self_repair_s")\n\tif after <= 0.0:\n\t\treturn\n',
  '\tvar after: float = passive("self_repair_s")\n\tif drawn.is_empty() or tape_spent or after <= 0.0:\n\t\treturn\n\ttape_spent = true\n',
  'the act\'s first fault is marked only with the tape aboard (as before)'),
 # --- What a stop ends is announced (D-f).
 (D, '\titems.come_to_a_stop()\n\t_announce_what_ends()\n\tcheckpoint = capture()\n', '\tcheckpoint = capture()\n\titems.come_to_a_stop()\n\t_announce_what_ends()\n',
  'the save is taken before the stop settles what cannot wait'),
 (D, '\tfor event: Dictionary in items.events:\n\t\t_announce(event)\n\titems.events.clear()\n\t_report_effects()\n', '\titems.events.clear()\n\t_report_effects()\n',
  'what the items say as he stops is dropped (the mend, the call)'),
 (I, '\tfinish_mending()\n\tif caller != &"":\n', '\tfinish_mending()\n\tif false:\n', 'a call ringing as he stops is dropped without a word'),
 (I, '\t\t_hang_up()\n\tfor candidate: Item in items:\n\t\tif candidate.burning:', '\t\tanswered_run = 0\n\t\t_hang_up()\n\tfor candidate: Item in items:\n\t\tif candidate.burning:',
  'a call dropped by a stop breaks his row of answered calls'),
 (I, '"answered": false, "dropped": true,\n\t\t\t\t"cash": 0.0, "nerves": 0.0,', '"answered": false, "dropped": false,\n\t\t\t\t"cash": 0.0, "nerves": 0.0,',
  'a dropped call is announced as a missed one'),
 (D, '\t\tif not items.held_for_leg(id):\n', '\t\tif false:\n', 'the statuses a stop ends are not announced'),
 (D, '\t\tif not items.held_for_leg(id):\n', '\t\tif true:\n', 'what the leg holds is announced as over at its stop'),
 (D, '\t# What the save put back did not begin here: it is not said again.\n\teffects.begin_tick()\n', '\t# What the save put back did not begin here: it is not said again.\n', 'what the save put back is announced as new'),
 (D, '\t_report_effects()\n\tif nerves.snapped and not snap_said:', '\tif nerves.snapped and not snap_said:', 'what ends at the gore is not announced'),
 (D, '\teffects.added.clear()\n\teffects.expired.clear()\n', '', 'statuses are announced twice a tick'),
 (D, '\tif nerves.snapped and not snap_said:\n\t\t_report_snap()\n', '', 'a Snap from a missed Exit is not announced'),
 (D, '\tif nerves.snapped and not snap_said:\n', '\tif nerves.snapped:\n', 'every Snap is announced twice'),
]
