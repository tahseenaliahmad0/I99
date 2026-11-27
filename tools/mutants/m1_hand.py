"""Mutants of the hand, the wheel, the gear gate and the gestures (GDD 4.2 to
4.7) for the M1 tests: T-HAND-01..03, T-WHEEL-01..02, T-GATE-01..02 and
T-GEST-01. They are the M1 review's "test honesty" findings (2026-11-17) put
as changes a test has to notice.
    python3 tools/mutants.py T-HAND,T-WHEEL,T-GATE,T-GEST tools/mutants/m1_hand.py

Equivalent, and so not in the list:
  - `PUSH_SHARE` between 0.5 and 0.9: a wall takes all of a push or none.
  - In `HandSim.step`, a buffered press applied "at whatever anchor the hand
    is at": a press is dropped when the pointer leaves its anchor, and the
    hand rests only at the anchor the pointer is on.
  - `HandSim._let_go` without `target = pos`: the target is chosen again on
    the same tick, from the pointer (or it is his ear).
  - `GearGate.release` without `column != NO_COLUMN`: between two columns
    the lever is never further along than the neutral channel is wide.
  - `GearGate.shift_sequential` without its case for neutral: one step up
    or down from 0, kept to 1 and above, is first either way.
  - `GearGate.release` without `_push = Vector2.ZERO`: `press` clears it.
  - `gate_grind_max` a tenth higher is equivalent with the shipped numbers
    only (0.8 is where gears begin to engage); it is in the list, and
    T-GATE-02 tries it in a gate whose gears engage from 0.9.
"""
S = 'src/core/cabin_space.gd'
H = 'src/core/hand_sim.gd'
W = 'src/core/wheel_sim.gd'
G = 'src/core/gear_gate.gd'
R = 'src/core/gesture.gd'
D = 'src/core/drive_sim.gd'
MUTANTS = [
 # --- The pointer and the cabin ---
 (S, '\treturn motion * (center.y * 2.0 / view_height)', '\treturn motion', 'pointer motion is not scaled to reference pixels'),
 (S, '\treturn Vector2(center.x + yaw * px_per_rad, center.y - pitch * px_per_rad)', '\treturn Vector2(center.x + yaw * px_per_rad, center.y + pitch * px_per_rad)', 'the pointer map is upside down'),
 (S, '\treturn absf(radius - wheel_radius) <= grip_zone_half_width', '\treturn absf(radius - wheel_radius) <= grip_zone_half_width * 0.5', 'the grip zone is half as wide'),
 (S, '\treturn absf(radius - wheel_radius) <= grip_zone_half_width', '\treturn radius - wheel_radius <= grip_zone_half_width', 'the hole of the wheel grips'),
 (S, '\tvar x: float = clampf(eye.x + direction.x * reach, free_min.x, free_max.x)', '\tvar x: float = eye.x + direction.x * reach', 'the free hand is not kept in its box sideways'),
 (S, '\tvar y: float = clampf(eye.y + direction.y * reach, free_min.y, free_max.y)', '\tvar y: float = eye.y + direction.y * reach', 'the free hand is not kept in its box up and down'),
 (S, '\tif off_axis <= start:\n\t\treturn Vector2.ZERO', '\tif off_axis <= start * 0.5:\n\t\treturn Vector2.ZERO', 'the glance begins at half glance_start'),
 (S, '\tvar turn: float = minf(glance_gain * (off_axis - start), off_axis)', '\tvar turn: float = minf(glance_gain * off_axis, off_axis)', 'the glance turns by a share of the whole angle'),
 (S, '\tvar turn: float = minf(glance_gain * (off_axis - start), off_axis)', '\tvar turn: float = minf(off_axis - start, off_axis)', 'the glance turns by all of the excess'),
 (S, 'clampf(yaw, -glance_max_yaw, glance_max_yaw)', 'yaw', 'the glance has no most yaw'),
 (S, 'clampf(pitch, -glance_max_pitch, 0.0))', 'clampf(pitch, -90.0, 0.0))', 'the glance has no most pitch'),
 (S, 'clampf(pitch, -glance_max_pitch, 0.0))', 'clampf(pitch, -glance_max_pitch, glance_max_pitch))', 'the eyes glance upward'),
 # --- The hand ---
 (H, '\t\telse:\n\t\t\tpointer = _space.clamp_pointer(pointer + input.pointer_delta)\n\t\t_choose_target(down, pressed)', '\t\telse:\n\t\t\tpointer = _space.clamp_pointer(pointer + input.pointer_delta * 0.5)\n\t\t_choose_target(down, pressed)', 'relative motion moves the pointer half as far'),
 (H, '\t\telse:\n\t\t\tpointer = _space.clamp_pointer(pointer + input.pointer_delta)\n\t\t_choose_target(down, pressed)', '\t\telse:\n\t\t\tpointer = pointer + input.pointer_delta\n\t\t_choose_target(down, pressed)', 'relative motion takes the pointer out of its range'),
 (H, '\t\t\tpos = _space.rim_point_at(_grip_angle - deg_to_rad(wheel_angle_deg))', '\t\t\tpos = _space.rim_point_at(_grip_angle)', 'the gripped hand does not ride the wheel'),
 (H, '\t\t\tpos = _space.rim_point_at(_grip_angle - deg_to_rad(wheel_angle_deg))', '\t\t\tpos = _space.rim_point_at(_grip_angle + deg_to_rad(wheel_angle_deg))', 'the gripped hand rides the wheel the wrong way'),
 (H, '\t\ttook_grip = true\n\t\t_wants_grip = false\n\t\t_grip_angle = atan2(pos.y, pos.x) + deg_to_rad(wheel_angle_deg)', '\t\ttook_grip = true\n\t\t_wants_grip = false\n\t\t_grip_angle = atan2(pos.y, pos.x)', 'a grip on a turned wheel forgets the wheel\'s angle'),
 (H, '\tgripping = true\n\tpinned = true\n\t_was_down = not grip_toggle\n\t_grip_latched = grip_toggle\n\t_grip_angle = atan2(pos.y, pos.x) + deg_to_rad(wheel_angle_deg)', '\tgripping = true\n\tpinned = true\n\t_was_down = not grip_toggle\n\t_grip_latched = grip_toggle\n\t_grip_angle = atan2(pos.y, pos.x)', 'starting on a turned wheel forgets the wheel\'s angle'),
 (H, '\t\t\tsteer_px = input.pointer_delta.x\n', '\t\t\tsteer_px = input.pointer_delta.x * 0.5\n', 'half the sideways motion steers'),
 (H, '\t\t\tsteer_px = input.pointer_delta.x\n', '\t\t\tsteer_px = input.pointer_delta.x + input.pointer_delta.y\n', 'vertical motion steers too'),
 (H, 'time - _press_time <= _buffer + dt * 0.5:', 'time - _press_time <= _buffer * 2.0 + dt * 0.5:', 'a press is applied up to twice input_buffer early'),
 (H, 'time - _press_time <= _buffer + dt * 0.5:', 'time - _press_time <= _buffer * 0.5 + dt * 0.5:', 'a press is applied only half input_buffer early'),
 (H, '\tif _press_pending and snap_index != _press_anchor:\n\t\t_press_pending = false', '\tif false:\n\t\t_press_pending = false', 'a press meant for one anchor is kept when the pointer leaves it'),
 (H, '\tvar best_distance: float = _snap_radius\n', '\tvar best_distance: float = _snap_radius * 1.5\n', 'the pointer snaps from half as far again'),
 (H, '\tvar best_distance: float = _snap_radius\n', '\tvar best_distance: float = _snap_radius * 0.7\n', 'the pointer snaps from nearer only'),
 (H, '\t\tif distance <= best_distance and (best == NO_ANCHOR or distance < best_distance):', '\t\tif distance <= _snap_radius:', 'the pointer snaps to the last anchor in range, not the nearest'),
 (H, '\t\tif _anchor_active[index] == 0:\n\t\t\tcontinue\n', '', 'the pointer snaps to anchors that are not active'),
 (H, '\t\t\tspeed *= _left_mult', '\t\t\tpass', 'the hand is as fast left of the hub'),
 (H, '\t\tif pos.x < 0.0 or goal.x < 0.0:', '\t\tif pos.x < 0.0:', 'the hand is slow only once it is left of the hub'),
 (H, '\t\tif crossing and pos.distance_to(_space.waypoint) > _arrive_epsilon:', '\t\tif false:', 'the hand crosses sides in a straight line'),
 (H, '\t\tvar speed: float = _speed * speed_mult', '\t\tvar speed: float = _speed', 'nothing slows the hand'),
 (H, '\tif _glance_tau > 0.0:\n\t\tblend = 1.0 - exp(-dt / _glance_tau)', '\tif false:\n\t\tblend = 1.0 - exp(-dt / _glance_tau)', 'the glance jumps'),
 (H, '\tif _glance_tau > 0.0:\n\t\tblend = 1.0 - exp(-dt / _glance_tau)', '\tif _glance_tau > 0.0:\n\t\tblend = 1.0 - exp(-dt / (_glance_tau * 2.0))', 'the glance is twice as slow'),
 (H, '\t\twant.y = -_eyes_down_pitch', '\t\twant.y = _eyes_down_pitch', 'an eyes-down ritual looks up'),
 (H, '\tcam_pitch += (want.y - cam_pitch) * blend', '\tcam_pitch += (want.y * 0.5 - cam_pitch) * blend', 'the camera pitches half of what the glance asks'),
 (H, '\tcam_yaw += (want.x - cam_yaw) * blend', '\tcam_yaw += (want.x * 0.5 - cam_yaw) * blend', 'the camera turns half of what the glance asks'),
 (H, '\tvar want: Vector2 = _space.glance_for(pos)\n\tif at_ear:', '\tvar want: Vector2 = _space.glance_for(target)\n\tif at_ear:', 'the eyes go where the hand is going, not where it is'),
 (H, '\t\tif rim_distance < _snap_distance:\n\t\t\tsnap_index = NO_ANCHOR', '\t\tif false:\n\t\t\tsnap_index = NO_ANCHOR', 'an anchor near the wheel takes a piece of the rim'),
 (H, '\tif _wants_grip and not frozen and pos.is_equal_approx(target) and _wants_wheel(down):', '\tif _wants_grip and not frozen and _wants_wheel(down):', 'the hand grips before it is at the rim'),
 (H, '\tif on_rim and grip_toggle and pressed:\n\t\t_grip_latched = true', '\tif on_rim and grip_toggle and down:\n\t\t_grip_latched = true', 'in toggle mode a held button latches again'),
 (H, '\tif not on_rim:\n\t\t_grip_latched = false', '\tif false:\n\t\t_grip_latched = false', 'a click latched on the rim stays when the pointer leaves it'),
 (H, '\t\tvar release: bool = (pressed if _grip_latched else not down) and not frozen', '\t\tvar release: bool = (not down) and not frozen', 'in toggle mode letting the button up lets go'),
 (H, '\tvar on_rim: bool = _space.pointer_on_rim(pointer) and not carrying', '\tvar on_rim: bool = _space.pointer_on_rim(pointer)', 'a hand that carries something takes the wheel'),
 # --- The wheel ---
 (W, '\t\t_held = angle - tremor\n\t\tcommand = _held', '\t\t_held = 0.0\n\t\tcommand = _held', 'gripping snaps the wheel to centre'),
 (W, '\t\t_held = angle - tremor\n\t\tcommand = _held', '\t\t_held = angle - tremor', 'gripping keeps the old command'),
 (W, '\t\tangle = move_toward(angle, 0.0, _return_rate * return_rate_mult * dt)', '\t\tangle = move_toward(angle, 0.0, _return_rate * return_rate_mult * dt * 1.1)', 'the wheel returns a tenth faster'),
 (W, '\t\tangle = move_toward(angle, 0.0, _return_rate * return_rate_mult * dt)\n\t\tcommand = angle', '\t\tangle = move_toward(angle, 0.0, _return_rate * return_rate_mult * dt)', 'a released wheel remembers its command'),
 (W, 'command + steer_px * _deg_per_px * sensitivity * turn_rate_mult', 'command + steer_px * _deg_per_px * turn_rate_mult', 'the sensitivity setting does not reach the wheel'),
 (W, '\t\t_held += (command - _held) * blend\n', '\t\t_held = command\n', 'the wheel has no smoothing'),
 (W, '\t\t\tblend = 1.0 - exp(-dt / _smoothing_s)', '\t\t\tblend = 1.0 - exp(-dt / (_smoothing_s * 1.2))', 'the wheel\'s smoothing is a fifth longer'),
 (W, '\treturn lagged_angle() / _max_angle', '\treturn command / _max_angle', 'the car is steered by the command, not the wheel'),
 (W, '\t\tangle = clampf(_held + tremor, -_max_angle, _max_angle)', '\t\tangle = _held + tremor', 'the wheel passes its stop'),
 (D, '\twheel.step(DT, hand.steer_px, steer_sensitivity)', '\twheel.step(DT, hand.steer_px, 1.0)', 'DriveSim does not pass the sensitivity on'),
 # --- The gear gate ---
 (G, '\t\tif slot_gear != NEUTRAL and 1.0 - along <= _engage_radius + EDGE_EPSILON:', '\t\tif slot_gear != NEUTRAL and 1.0 - along <= _engage_radius * 1.3 + EDGE_EPSILON:', 'a gear engages from further out'),
 (G, '\t\tif slot_gear != NEUTRAL and 1.0 - along <= _engage_radius + EDGE_EPSILON:', '\t\tif slot_gear != NEUTRAL and 1.0 - along <= _engage_radius * 0.7 + EDGE_EPSILON:', 'a gear engages only nearer its end'),
 (G, 'along >= _grind_min - EDGE_EPSILON and', 'along >= _grind_min * 0.8 - EDGE_EPSILON and', 'the grind band begins lower'),
 (G, 'along >= _grind_min - EDGE_EPSILON and', 'along >= _grind_min * 1.2 - EDGE_EPSILON and', 'the grind band begins higher'),
 (G, 'and along <= _grind_max + EDGE_EPSILON:', 'and along <= _grind_max * 1.1 + EDGE_EPSILON:', 'the grind band ends higher'),
 (G, 'and along <= _grind_max + EDGE_EPSILON:', 'and along <= _grind_max * 0.9 + EDGE_EPSILON:', 'the grind band ends lower'),
 (G, '\t_half_width = tuning.f("gate_channel_half_width")', '\t_half_width = tuning.f("gate_channel_half_width") * 1.5', 'the channels are half as wide again'),
 (G, '\t_half_width = tuning.f("gate_channel_half_width")', '\t_half_width = tuning.f("gate_channel_half_width") * 0.6', 'the channels are narrower'),
 (G, '\t\tif _push.length() > _wall_push + EDGE_EPSILON:', '\t\tif _push.length() > _wall_push * 1.5 + EDGE_EPSILON:', 'a wall takes half as much again before it grinds'),
 (G, '\t\tif _push.length() > _wall_push + EDGE_EPSILON:', '\t\tif _push.length() > _wall_push * 0.6 + EDGE_EPSILON:', 'a wall grinds sooner'),
 (G, '\tlock_left = _grind_lock', '\tlock_left = _grind_lock * 0.5', 'a grind locks the lever half as long'),
 (G, '\tlock_left = _grind_lock', '\tlock_left = _grind_lock * 1.5', 'a grind locks the lever half as long again'),
 (G, '\tif _at_slot_stop(before, move.y):\n\t\tasked.y = 0.0', '\tif false:\n\t\tasked.y = 0.0', 'pushing the lever home is pushing into a wall'),
 (G, '\tif absf(move.x) >= absf(move.y):\n\t\tlever.x = _stop_x', '\tif true:\n\t\tlever.x = _stop_x', 'the sideways part always goes first'),
 (G, '\tif absf(move.x) >= absf(move.y):\n\t\tlever.x = _stop_x', '\tif false:\n\t\tlever.x = _stop_x', 'the lengthways part always goes first'),
 (G, ' * (speed_mult / _unit_px)', ' * (1.0 / _unit_px)', 'nothing slows the lever'),
 (G, '\treturn -_half_width if column == 1 else -1.0', '\treturn -1.0', 'there is a slot below fifth'),
 (G, '\treturn 1.0 if has_fifth else 0.0', '\treturn 1.0', 'fifth\'s channel is open without the adaptation'),
 (G, '\tif gear != NEUTRAL and not _in_slot(gear):\n\t\tgear = NEUTRAL', '\tif false:\n\t\tgear = NEUTRAL', 'a lever pulled out of its slot stays in gear'),
 (G, '\treturn signf(lever.y) == signf(home.y) and 1.0 - absf(lever.y) <= _engage_radius + EDGE_EPSILON', '\treturn signf(lever.y) == signf(home.y) and 1.0 - absf(lever.y) <= _engage_radius * 2.0 + EDGE_EPSILON', 'the lever stays in gear twice as far out'),
 (G, '\treturn signf(lever.y) == signf(home.y) and 1.0 - absf(lever.y) <= _engage_radius + EDGE_EPSILON', '\treturn signf(lever.y) == signf(home.y) and 1.0 - absf(lever.y) <= _engage_radius * 0.5 + EDGE_EPSILON', 'the lever leaves its gear half as far out'),
 (G, '\t\t_push = _push.limit_length(maxf(_push.length() - moved.length(), 0.0))', '\t\tpass', 'a push into a wall is never forgiven'),
 (G, '\t\t_push += asked - moved\n', '\t\t_push += asked\n', 'what the lever travels counts as pushing'),
 (G, '\tvar top: int = MAX_GEAR if has_fifth else MAX_GEAR - 1', '\tvar top: int = MAX_GEAR', 'the assist shifts into fifth without the adaptation'),
 (G, '\tif lock_left > 0.0:\n\t\tlock_left -= dt', '\tif lock_left > 0.0 and held:\n\t\tlock_left -= dt', 'the lock runs only while the knob is held'),
 # --- The gestures ---
 (R, '\tif elapsed > _tap_max + 0.000001 and down:\n\t\tcancel()', '\tif false:\n\t\tcancel()', 'a TAP held too long waits for its release to fail'),
 (R, '\t\tif elapsed <= _tap_max + 0.000001:', '\t\tif elapsed <= _tap_max * 1.2 + 0.000001:', 'a TAP may last a fifth longer'),
 (R, '\t\tif elapsed <= _tap_max + 0.000001:', '\t\tif elapsed <= _tap_max * 0.8 + 0.000001:', 'a TAP must be a fifth shorter'),
 (R, '\t\t\tif elapsed >= _amount - dt * 0.5 and down:', '\t\t\tif elapsed >= _amount * 0.9 - dt * 0.5 and down:', 'a HOLD completes a tenth early'),
 (R, '\t\t\tif elapsed >= _amount - dt * 0.5 and down:', '\t\t\tif elapsed >= _amount * 1.1 - dt * 0.5 and down:', 'a HOLD completes a tenth late'),
 (R, '\t\t\telif not down:\n\t\t\t\tcancel()\n\t\t\telif _amount > 0.0:\n\t\t\t\tprogress', '\t\t\telif false:\n\t\t\t\tcancel()\n\t\t\telif _amount > 0.0:\n\t\t\t\tprogress', 'a HOLD let go early is not cancelled'),
 (R, '\tif best != 0 and best_distance >= _flick_distance and', '\tif best != 0 and best_distance >= _flick_distance * 0.8 and', 'a FLICK needs a fifth less travel'),
 (R, '\tif best != 0 and best_distance >= _flick_distance and', '\tif best != 0 and best_distance >= _flick_distance * 1.2 and', 'a FLICK needs a fifth more travel'),
 (R, 'elapsed <= _flick_max + dt * 0.5:\n\t\tdirection = best\n\t\t_finish()\n\telif elapsed > _flick_max:', 'elapsed <= _flick_max * 1.2 + dt * 0.5:\n\t\tdirection = best\n\t\t_finish()\n\telif elapsed > _flick_max * 1.2:', 'a FLICK may take a fifth longer'),
 (R, 'elapsed <= _flick_max + dt * 0.5:\n\t\tdirection = best\n\t\t_finish()\n\telif elapsed > _flick_max:', 'elapsed <= _flick_max * 0.8 + dt * 0.5:\n\t\tdirection = best\n\t\t_finish()\n\telif elapsed > _flick_max * 0.8:', 'a FLICK must be a fifth quicker'),
 (R, '\t\t_finish()\n\telif elapsed > _flick_max:\n\t\tcancel()', '\t\t_finish()\n\telif false:\n\t\tcancel()', 'a FLICK that ran out of time stays open'),
 (R, '\tif absf(_travel.y) >= absf(_travel.x):', '\tif absf(_travel.y) >= absf(_travel.x) * 0.6:', 'a swipe that goes more sideways counts as up or down'),
 (R, '\tif absf(_travel.y) >= absf(_travel.x):', '\tif absf(_travel.y) * 0.6 >= absf(_travel.x):', 'a swipe that goes more up or down counts as sideways'),
 (R, '\t\tbest = DIR_UP if _travel.y < 0.0 else DIR_DOWN', '\t\tbest = DIR_DOWN if _travel.y < 0.0 else DIR_UP', 'up and down are swapped'),
 (R, '\t\tbest = DIR_LEFT if _travel.x < 0.0 else DIR_RIGHT', '\t\tbest = DIR_RIGHT if _travel.x < 0.0 else DIR_LEFT', 'left and right are swapped'),
 (R, '\tif (_dirs & best) == 0:\n\t\tbest = 0', '\tif false:\n\t\tbest = 0', 'a FLICK in a direction that is not allowed counts'),
 (R, '\tif not down:\n\t\tcancel()\n\t\treturn\n\t_travel += delta', '\tif false:\n\t\tcancel()\n\t\treturn\n\t_travel += delta', 'a FLICK goes on with the button up'),
 (R, '\tif _crank_pending.length() < _crank_min_step:\n\t\treturn', '\tif false:\n\t\treturn', 'the CRANK reads headings from the smallest motion'),
 (R, '\t\tif absf(turned) <= _crank_max_turn:\n\t\t\t_crank_turned += turned', '\t\tif true:\n\t\t\t_crank_turned += turned', 'doubling back counts as half a turn'),
 (R, '\t\tif absf(turned) <= _crank_max_turn:\n\t\t\t_crank_turned += turned', '\t\tif absf(turned) <= _crank_max_turn:\n\t\t\t_crank_turned += absf(turned)', 'turning back counts forward'),
 (R, '\tvar needed: float = _amount * TAU', '\tvar needed: float = _amount * TAU * 0.9', 'a CRANK needs a tenth less turning'),
 (R, '\tvar needed: float = _amount * TAU', '\tvar needed: float = _amount * TAU * 1.1', 'a CRANK needs a tenth more turning'),
 (R, '\t\tcrank_sign = 1 if _crank_turned > 0.0 else -1', '\t\tcrank_sign = -1 if _crank_turned > 0.0 else 1', 'the CRANK\'s direction is reported the wrong way'),
 (R, '\tif not down:\n\t\tcancel()\n\t\treturn\n\t_crank_pending += delta', '\tif false:\n\t\tcancel()\n\t\treturn\n\t_crank_pending += delta', 'a CRANK goes on with the button up'),
 (R, '\t\t\t\tif _bead_times.size() >= _bead_rate:', '\t\t\t\tif _bead_times.size() > _bead_rate:', 'one bead more than bead_max_rate counts in a second'),
 (R, '_clock - _bead_times[0] > 1.0 - dt * 0.5:', '_clock - _bead_times[0] > 0.8 - dt * 0.5:', 'the bead rate is counted over 0.8 s'),
 (R, '\t\t\t\tif over_destination:\n\t\t\t\t\t_finish()', '\t\t\t\tif true:\n\t\t\t\t\t_finish()', 'a DRAG_TO dropped anywhere completes'),
 (R, '\t\t\t\twhile _travel.x >= _amount:\n\t\t\t\t\t_travel.x -= _amount\n\t\t\t\t\tdrag_steps += 1', '\t\t\t\twhile _travel.x >= _amount * 0.5:\n\t\t\t\t\t_travel.x -= _amount * 0.5\n\t\t\t\t\tdrag_steps += 1', 'a DRAG steps twice as often to the right'),
 (R, '\t\t\t\t\tdrag_steps -= 1', '\t\t\t\t\tdrag_steps += 1', 'a DRAG to the left steps to the right'),
 (R, '\t\t\tif not down:\n\t\t\t\t_finish()\n\t\t\telif _amount > 0.0:\n\t\t\t\t_travel += delta', '\t\t\tif false:\n\t\t\t\t_finish()\n\t\t\telif _amount > 0.0:\n\t\t\t\t_travel += delta', 'a DRAG never ends'),
]
