"""Mutants of touch (GDD 4.1, 17.4, D-069) for T-TOUCH-01.
    python3 tools/mutants.py T-TOUCH tools/mutants/touch.py

Not in the list: a tap that waits is dropped when the pointer is no longer
on its anchor. A new touch drops it already (finger_down); the line is for
an anchor that stops being one while the hand is on its way, which no test
arranges.
"""
C = 'src/game/drive_controller.gd'
T = 'src/game/touch_input.gd'
MUTANTS = [
 (T, '\t\tif snap != HandSim.NO_ANCHOR and sim.gesture_at(snap) == "TAP":\n\t\t\t_tap_at = snap', '\t\tif false:\n\t\t\t_tap_at = snap', 'a TAP does not perform by itself: it needs the thumb'),
 (T, '\t\tif snap != HandSim.NO_ANCHOR and sim.gesture_at(snap) == "TAP":\n\t\t\t_tap_at = snap', '\t\tif snap != HandSim.NO_ANCHOR:\n\t\t\t_tap_at = snap', 'every ritual performs by itself, a HOLD and a CRANK too'),
 (T, '\t\t\t_tap_ticks = _ticks(_tuning.f("touch_tap_s"))\n\t\t\tinput.lmb = true\n\t\t\treturn', '\t\t\tinput.lmb = true\n\t\t\treturn', 'the press of a TAP never ends'),
 (T, '\t\tinput.lmb = _down\n\t\tif not _down:\n\t\t\t_pressed_at = HandSim.NO_ANCHOR\n\t\treturn', '\t\tinput.lmb = true\n\t\treturn', 'lifting the thumb does not let go'),
 (T, '\tif not _down:\n\t\t_pressed_at = HandSim.NO_ANCHOR\n\t\tinput.lmb = false\n\t\treturn', '\tif false:\n\t\treturn', 'a HOLD goes on after the thumb has lifted'),
 (T, '\tif _pressed_at == snap or hand.at_index == snap:', '\tif true:', 'the press is made before the hand is there'),
 (T, '\tinput.rmb = _foot != NO_FINGER', '\tinput.rmb = false', 'the pedal zone brakes nothing'),
 (T, '\tif _foot == NO_FINGER and pedal_zone(view, dpi).has_point(at):', '\tif _foot == NO_FINGER and at.x < view.x * 0.5:', 'the whole left half of the glass is the brake'),
 (T, '\treturn Rect2(Vector2(0.0, view.y - size.y), size)', '\treturn Rect2(Vector2(view.x - size.x, view.y - size.y), size)', 'the pedal zone is at the bottom right'),
 (T, '\tvar size: Vector2 = Vector2(maxf(view.x * _tuning.fi("touch_pedal_zone", 0), least), maxf(view.y * _tuning.fi("touch_pedal_zone", 1), least))', '\tvar size: Vector2 = Vector2(view.x * 0.002, view.y * 0.002)', 'the pedal zone is a speck'),
 (T, '\tif hotspot(view, dpi).has_point(at):\n\t\tpause_asked = true\n\t\treturn', '\tif false:\n\t\treturn', 'the hotspot asks for nothing'),
 (T, '\treturn Rect2(Vector2.ZERO, Vector2(side, side))', '\treturn Rect2(Vector2.ZERO, Vector2(side, side) * 0.1)', 'the hotspot is a tenth of a tap target'),
 (T, '\treturn maxf(_tuning.f("anchor_snap_radius"), half_target)', '\treturn _tuning.f("anchor_snap_radius")', 'an anchor is no wider under a thumb than under the pointer'),
 (T, '\treturn mm / MM_PER_INCH * maxf(dpi, 1.0)', '\treturn mm / MM_PER_INCH * 96.0', 'every glass has 96 dots to the inch'),
 (T, '\t\t_pointer = pointer\n\t\t_delta += motion', '\t\t_pointer = pointer', 'a dragged thumb turns no wheel and no dial'),
 (C, '\t\tif touch.pressed:\n\t\t\t_touch.finger_down(touch.index, touch.position, _pointer_under(touch.position), _view_size(), _dpi())', '\t\tif touch.pressed:\n\t\t\tpass', 'the drive scene does not hear a finger come down'),
 (C, '\t\telse:\n\t\t\t_touch.finger_up(touch.index)\n\t\treturn', '\t\telse:\n\t\t\tpass\n\t\treturn', 'the drive scene does not hear a finger lift'),
 (C, '\t\t_touch.apply(sim, _input)', '\t\tpass', 'what the fingers do never reaches the simulation'),
 (C, '\tif to_the_pause and _leave_in <= 0.0:\n\t\t_open_pause.call_deferred()', '\tif false:\n\t\t_open_pause.call_deferred()', 'the hotspot pauses nothing'),
]
