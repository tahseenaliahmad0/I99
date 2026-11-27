"""Mutants of the heckles (GDD 11.3) for T-HECKLE-01.
    python3 tools/mutants.py T-HECKLE tools/mutants/heckles.py
"""
D = 'src/core/drive_sim.gd'
E = 'src/core/encounter_sim.gd'
G = 'src/core/leg_generator.gd'
H = 'src/core/heckle_director.gd'
L = 'src/core/leg_sim.gd'
MUTANTS = [
 # How many, and when.
 (H, '\tvar count: int = GameData.as_int(_per_leg[clampi(act, 1, _per_leg.size()) - 1])', '\tvar count: int = GameData.as_int(_per_leg[0])', 'one heckle per leg in every act'),
 (H, '\tvar count: int = GameData.as_int(_per_leg[clampi(act, 1, _per_leg.size()) - 1])', '\tvar count: int = GameData.as_int(_per_leg[_per_leg.size() - 1])', 'two heckles per leg in every act'),
 (H, '\t\t\tif free and said < planned.size() and s >= GameData.as_float(planned[said]["due_s"]):', '\t\t\tif said < planned.size() and s >= GameData.as_float(planned[said]["due_s"]):', 'a heckle begins whether or not it may'),
 (H, '\t\t\tif free and said < planned.size() and s >= GameData.as_float(planned[said]["due_s"]):', '\t\t\tif free and said < planned.size():', 'every heckle is said at once'),
 (D, '\treturn heckling and _exit == EXIT_AHEAD and not wrecked and not pulled_over and not encounter.pressing()', '\treturn heckling and _exit == EXIT_AHEAD and not wrecked and not pulled_over', 'heckles begin during an encounter'),
 (D, '\treturn heckling and _exit == EXIT_AHEAD and not wrecked and not pulled_over and not encounter.pressing()', '\treturn heckling and _exit != EXIT_NONE and not wrecked and not pulled_over and not encounter.pressing()', 'heckles begin after the Exit has opened'),
 (E, '\tif patrol_phase == PATROL_LIGHTS or patrol_phase == PATROL_WATCHING:\n\t\treturn true\n\tif tail_phase', '\tif patrol_phase == PATROL_WATCHING:\n\t\treturn true\n\tif tail_phase', 'the Patrol\'s lights are no encounter yet'),
 (E, '\tif patrol_phase == PATROL_LIGHTS or patrol_phase == PATROL_WATCHING:\n\t\treturn true\n\tif tail_phase', '\tif tail_phase', 'the Patrol is no encounter'),
 (E, '\treturn glare > 0.0\n\n\n# --- Motorcade', '\treturn false\n\n\n# --- Motorcade', 'the Motorcade\'s spotlight is no encounter'),
 (H, '\tif phase != NONE:\n\t\t_resolve(LAPSED, {})\n\tplanned = []\n\tsaid = 0\n', '\tif phase != NONE:\n\t\t_resolve(LAPSED, {})\n', 'what was not said is kept for later'),
 # The lead.
 (H, '\tphase = LEAD\n\tlead_left = _lead\n', '\tphase = LEAD\n\tlead_left = 0.0\n', 'no lead: the change comes with the subtitle'),
 (H, '\tphase = LEAD\n\tlead_left = _lead\n', '\tphase = LEAD\n\tlead_left = _lead * 0.5\n', 'half the lead'),
 (H, '\tevents.append({"type": "line_requested", "id": line, "tell": true})', '\tevents.append({"type": "line_requested", "id": line})', 'the heckle\'s line is no tell'),
 (H, '\tevents.append({"type": "sfx_requested", "id": "heckle"})\n', '', 'no ding before the subtitle'),
 (H, '\t\tLEAD:\n\t\t\tlead_left -= dt\n\t\t\tif lead_left < dt * 0.5:\n\t\t\t\t_open()', '\t\tLEAD:\n\t\t\t_step_open(dt)\n\t\t\tlead_left -= dt\n\t\t\tif lead_left < dt * 0.5:\n\t\t\t\t_open()', 'what he does during the lead counts'),
 # Dare, Doubt.
 (H, '\t\t\t\tdone = done or _progress[index] >= GameData.as_float(answer.get("count")) - 0.5', '\t\t\t\tdone = done or _progress[index] >= 1.0', 'one close call is enough for any Dare'),
 (H, '\t\t\t\t_progress[index] = _progress[index] + dt if in_gear == GameData.as_int(answer.get("gear")) else 0.0', '\t\t\t\t_progress[index] = _progress[index] + dt if in_gear == GameData.as_int(answer.get("gear")) else _progress[index]', 'the seconds in gear need not be in one piece'),
 (H, '\t\t\t\t_progress[index] = _progress[index] + dt if in_gear == GameData.as_int(answer.get("gear")) else 0.0', '\t\t\t\t_progress[index] = _progress[index] + dt if in_gear >= 3 else 0.0', 'third gear answers for fourth'),
 (H, '\t\t\t\t_progress[index] = _progress[index] + dt if not in_gripping and in_straight else 0.0', '\t\t\t\t_progress[index] = _progress[index] + dt if not in_gripping else 0.0', 'hands-off counts in a bend'),
 (H, '\t\t\t\t_progress[index] = _progress[index] + dt if not in_gripping and in_straight else 0.0', '\t\t\t\t_progress[index] = _progress[index] + dt if in_straight else 0.0', 'hands-off counts with a hand on the wheel'),
 (H, '\t\t\t\t\tif _clock - at <= seconds:\n\t\t\t\t\t\twithin += 1', '\t\t\t\t\twithin += 1', 'three passes in the window, however far apart'),
 (D, '\t\tif vehicle.direction < 0:\n\t\t\tcontinue\n\t\tvar ahead: bool = vehicle.s > car.s', '\t\tvar ahead: bool = vehicle.s > car.s', 'oncoming vehicles are passed too'),
 (H, '\t\t\tif _answered(dt):\n\t\t\t\t_resolve(PASSED, GameData.as_dict(record.get("pass")))', '\t\t\tif _answered(dt):\n\t\t\t\t_resolve(PASSED, {})', 'an answered Dare or Doubt gives nothing'),
 (H, '\t\t\t_:\n\t\t\t\t_resolve(FAILED, GameData.as_dict(record.get("fail")))', '\t\t\t_:\n\t\t\t\t_resolve(FAILED, {})', 'an unanswered Doubt or Order costs nothing'),
 (H, '\t\t\t_:\n\t\t\t\t_resolve(FAILED, GameData.as_dict(record.get("fail")))', '\t\t\t_:\n\t\t\t\t_resolve(FAILED, GameData.as_dict(record.get("pass")))', 'what runs out pays as if it were answered'),
 (D, '\tnerves.add(heckles.nerves)\n', '', 'a heckle does nothing to his Nerves'),
 (D, '\tcash = maxf(cash + heckles.cash, 0.0)\n\t_announce_heckles()', '\t_announce_heckles()', 'a heckle pays no cash'),
 (D, '\theckles.in_close_calls = collision.close_calls\n', '', 'the Table sees no close call'),
 (D, '\theckles.in_gear = gate.gear\n', '', 'the Table does not see his gear'),
 # Question.
 (H, '\t\t\tif not _kept():', '\t\t\tif false:', 'a Question is never lost'),
 (H, '\t\t\t\tif in_nerves >= GameData.as_float(keep.get("value")):', '\t\t\t\tif in_nerves > GameData.as_float(keep.get("value")):', 'Nerves at 50 are under 50'),
 (H, '\t\t\tNO_HORN:\n\t\t\t\tif in_horn:\n\t\t\t\t\treturn false', '\t\t\tNO_HORN:\n\t\t\t\tpass', 'the horn does not lose a Question'),
 (H, '\t\t\tQUESTION:\n\t\t\t\t_resolve(PASSED, GameData.as_dict(record.get("pass")))', '\t\t\tQUESTION:\n\t\t\t\t_resolve(FAILED, {})', 'a Question kept to its end gives nothing'),
 # Order.
 (H, '\t\t\tif in_ritual != &"" and String(in_ritual) == GameData.as_string(record.get("ritual")):', '\t\t\tif in_ritual != &"":', 'any ritual obeys an Order'),
 (D, '\theckles.in_ritual = StringName(ritual_id)\n\t_emit("ritual_completed", {\n\t\t"ritual": ritual_id,', '\t_emit("ritual_completed", {\n\t\t"ritual": ritual_id,', 'the Table sees no ritual'),
 (H, '\tif not _can_be_asked(chosen):\n\t\tchosen = _another(GameData.as_float(entry["roll"]))\n\t\tif chosen.is_empty():\n\t\t\treturn\n', '', 'an Order he cannot obey is given all the same'),
 # The Fib.
 (H, '\t\tFIB:\n\t\t\tghost_holds = true', '\t\tFIB:\n\t\t\tpass', 'the Fib has no hand'),
 (H, '\tlead_left = 0.0\n\twindow_left = 0.0\n\tghost_holds = false\n', '\tlead_left = 0.0\n\twindow_left = 0.0\n', 'the ghost hand never lets go'),
 (D, '\treturn heckles.ghost_holds and not hand.gripping and not _wrist_on_wheel', '\treturn heckles.ghost_holds and not _wrist_on_wheel', 'the ghost hand takes the wheel from his own'),
 (D, '\telif ghost_on_wheel():\n\t\t# The Fib (GDD 11.3): "A ghost left hand holds the lane", bends and\n\t\t# all, while his own hand is elsewhere.\n\t\twheel.hold_at(_lane_keeping_angle())\n', '', 'the ghost hand holds the wheel where it is'),
 (D, '\twheel.locked = effects.has_own(ItemSim.HOOK_SET) or passengers.holds_wheel() or ghost_on_wheel()', '\twheel.locked = effects.has_own(ItemSim.HOOK_SET) or passengers.holds_wheel()', 'the ghost hand does not hold the wheel'),
 # Twists.
 (D, '\tif heckles.twist_begins:\n\t\tleg.twist_begins()\n', '', 'a Twist never comes onto the road'),
 (L, '\ttwist_live = twist.is_empty()\n\tshower_left = 0.0', '\ttwist_live = true\n\tshower_left = 0.0', 'a Twist is on the road before anybody says so'),
 (L, '\tif not (_twist_flock and not twist_live):\n\t\t_stand_the_flock()', '\t_stand_the_flock()', 'the Twist\'s sheep stand there from the start'),
 (L, '\t\tif not twist_live and _twist_role != &"" and StringName(GameData.as_string(spawn.get("role"))) == _twist_role:', '\t\tif false:', 'the Twist\'s vehicles come whenever their trigger does'),
 (L, '\tfor spawn: Dictionary in _held:\n\t\t_waiting.append(spawn)\n\t_held = []\n', '\t_held = []\n', 'vehicles held back for a Twist never come'),
 (H, '\t\t\tentry["due_s"] = maxf(GameData.as_float(twist.get("first_s")) - _lead * _top_ms, 0.0)', '\t\t\tentry["due_s"] = GameData.as_float(twist.get("first_s"))', 'a Twist is said as its first thing shows'),
 (H, '\t\t\tif _s >= _until_s:\n\t\t\t\t_resolve(OVER, {})\n\t\t\t\treturn', '\t\t\tif _s >= 0.0:\n\t\t\t\t_resolve(OVER, {})\n\t\t\t\treturn', 'a Twist is over as it begins'),
 (H, '\t\t\t\t\telif not twist.is_empty() or what == modifier_id or not allowed.has(what):', '\t\t\t\t\telif what == modifier_id or not allowed.has(what):', 'two stretches on one leg'),
 (H, '\t\t\t\t\telif not twist.is_empty() or what == modifier_id or not allowed.has(what):', '\t\t\t\t\telif not twist.is_empty() or what == modifier_id:', 'a Twist on a leg that takes no such modifier'),
 (H, '\t\t\t\t\t\tif rainy or shower:\n\t\t\t\t\t\t\tcontinue', '\t\t\t\t\t\tif shower:\n\t\t\t\t\t\t\tcontinue', 'a shower on a Rain leg'),
 (G, '\tif twist_at >= 0.0 and _in_zone(s - _tuning.f("calm_length"), s + ceilf(length) + _tuning.f("calm_length")):\n\t\treturn false\n', '', 'a Twist may lie on the leg\'s own stretch'),
 # The shower.
 (D, '\tif heckles.shower_begins > 0.0:\n\t\tleg.begin_shower(heckles.shower_begins)\n', '', 'the shower never rains'),
 (D, '\t\titems.raining = leg.raining\n\t\tcar.lat_tau_mult = _rain_response if leg.raining else 1.0\n\tnerves.add', '\t\titems.raining = leg.raining\n\tnerves.add', 'the shower does not wet the road'),
 (D, '\t\titems.raining = leg.raining\n\t\tcar.lat_tau_mult = _rain_response if leg.raining else 1.0\n\tnerves.add', '\t\tcar.lat_tau_mult = _rain_response if leg.raining else 1.0\n\tnerves.add', 'the shower does not wet the glass'),
 (L, '\tif shower_left > 0.0:\n\t\tshower_left -= dt\n\t\tif shower_left < dt * 0.5:\n\t\t\tbegin_shower(0.0)\n', '', 'the shower never stops'),
 (H, '\t\t\t\twindow_left = GameData.as_float(record.get("duration_s"))\n\t\t\t\tshower_begins = window_left', '\t\t\t\twindow_left = GameData.as_float(record.get("duration_s"))\n\t\t\t\tshower_begins = window_left * 0.5', 'half a shower'),
 # The pool.
 (H, '\t\t\tif guests.has(guest) and guest_weight > 0.0:\n\t\t\t\tout.append({"record": heckle, "weight": guest_weight})\n\t\t\tcontinue', '\t\t\tcontinue', 'the wedding guests say nothing'),
 (H, '\t\t\tif guests.has(guest) and guest_weight > 0.0:', '\t\t\tif guest_weight > 0.0:', 'every passenger heckles, carried or not'),
 (H, '\tif table.heckle_types().is_empty():\n\t\treturn out\n', '', 'the guests heckle at Noor\'s Table'),
 (H, '\t\tif GameData.as_float(table.heckle_weights.get(type)) <= 0.0:\n\t\t\tcontinue\n', '', 'a Table says types it has no weight for'),
 (H, '\t\tat -= GameData.as_float(entry["weight"])\n\t\tif at < 0.0:\n\t\t\treturn entry', '\t\tat -= 1.0\n\t\tif at < 0.0:\n\t\t\treturn entry', 'every record is as likely as any other'),
 # The words.
 (H, '\tif name == CLOSE_CALL and seconds == 0.0 and count >= 1:', '\tif name == CLOSE_CALL and count >= 1:', '"close_call_5s" is read as a close call'),
 (H, '\tif name == HANDS_OFF and seconds > 0.0 and count == 1:', '\tif name == HANDS_OFF and count == 1:', '"hands_off" with no seconds is an answer'),
]
