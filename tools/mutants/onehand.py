"""Mutants of the pointer's way to the pause (GDD 17.2, D-066) for
T-ONEHAND-01: the left button held where the hand has nothing to hold.
    python3 tools/mutants.py T-ONEHAND tools/mutants/onehand.py

Not in the list: `hand_is_free()` also asks that the hand grips nothing, is
not pinned, is in no gesture and holds no lever. Each of those has the
pointer on the rim or snapped to an anchor already; they are there so that
the answer does not hang on that.
"""
C = 'src/game/drive_controller.gd'
D = 'src/core/drive_sim.gd'
H = 'src/game/pause_hold.gd'
T = 'data/tuning.json'
MUTANTS = [
 (H, '\tif not down or not free:\n\t\t_armed = false', '\tif not down:\n\t\t_armed = false', 'a hold carried onto an anchor goes on'),
 (H, '\tif pressed:\n\t\t_armed = true', '\tif down:\n\t\t_armed = true', 'a button held from elsewhere begins a hold in the air'),
 (H, '\tif _held >= hold_s - dt * 0.5:', '\tif _held >= hold_s * 0.5:', 'half the time pauses'),
 (H, '\tif _held >= hold_s - dt * 0.5:\n\t\t_armed = false', '\tif _held >= hold_s - dt * 0.5:\n\t\t_armed = true', 'held on, it pauses again and again'),
 (H, '\t_armed = false\n\t_was_down = down', '\t_armed = false\n\t_was_down = false', 'the press that closed the pause begins a hold'),
 (H, '\tprogress = clampf(_held / hold_s, 0.0, 1.0) if hold_s > 0.0 else 1.0', '\tprogress = 0.0', 'the hold shows no arc'),
 (H, '\t\t_held = 0.0\n\t\tprogress = 0.0\n\t\treturn true', '\t\t_held = 0.0\n\t\treturn true', 'the arc stays full after the pause'),
 (D, '\treturn hand.snap_index == HandSim.NO_ANCHOR and not hand.gripping and', '\treturn not hand.gripping and', 'on an anchor the hand counts as free'),
 (D, ' and not hand.pinned and not hand.carrying \\', ' and not hand.pinned \\', 'carrying something the hand counts as free'),
 (D, 'and not _lever_in_hand and not space.pointer_on_rim(hand.pointer)', 'and not _lever_in_hand', 'on the rim the hand counts as free'),
 (D, '\t\t"hand_free": hand_is_free(),', '\t\t"hand_free": false,', 'the snapshot never says the hand is free'),
 (C, '\tif _bot == null and _leave_in <= 0.0 and _pause_hold.step(DriveSim.DT, _input.lmb, sim.hand_is_free()):', '\tif false:', 'the drive never asks the hold'),
 (C, '\tif _bot == null and _leave_in <= 0.0 and _pause_hold.step(DriveSim.DT, _input.lmb, sim.hand_is_free()):\n\t\t_open_pause.call_deferred()', '\tif _bot == null and _leave_in <= 0.0 and _pause_hold.step(DriveSim.DT, _input.lmb, sim.hand_is_free()):\n\t\tpass', 'the hold complete, nothing pauses'),
 (T, '"pause_hold_s": 1.2', '"pause_hold_s": 0.3', 'the hold that pauses is as short as a TAP'),
]
