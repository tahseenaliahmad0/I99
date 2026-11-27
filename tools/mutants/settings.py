"""Mutants of the settings (GDD 17.1) for T-SETTINGS-01.
    python3 tools/mutants.py T-SETTINGS tools/mutants/settings.py
"""
C = 'src/game/drive_controller.gd'
D = 'src/core/drive_sim.gd'
G = 'src/game/game.gd'
P = 'src/view/pointer_view.gd'
S = 'src/core/settings_spec.gd'
V = 'src/view/cabin_view.gd'
W = 'src/view/settings_view.gd'
MUTANTS = [
 (D, '\t\tsteer_sensitivity = SettingsSpec.share(values[SettingsSpec.STEERING])', '\t\tsteer_sensitivity = 1.0', 'the steering setting changes nothing'),
 (D, '\t\tgrip_toggle = GameData.as_string(values[SettingsSpec.GRIP_MODE]) == SettingsSpec.GRIP_TOGGLE', '\t\tgrip_toggle = false', 'the grip is always held'),
 (D, '\t\tsequential_shift = GameData.as_string(values[SettingsSpec.SHIFTING]) == SettingsSpec.SHIFT_SEQUENTIAL', '\t\tsequential_shift = false', 'shifting is always the gate'),
 (D, '\t\tbrake_assist = GameData.as_bool(values[SettingsSpec.BRAKE_ASSIST])', '\t\tbrake_assist = false', 'Brake assist never comes on'),
 (D, '\t\tsteady_start = GameData.as_bool(values[SettingsSpec.STEADY_START])', '\t\tsteady_start = true', 'Steady start cannot be turned off'),
 (D, '\t\tphantom_enabled = GameData.as_bool(values[SettingsSpec.PHANTOM])', '\t\tphantom_enabled = true', 'the Phantom cannot be turned off'),
 (D, '\tassisted_brake = brake_assist and not input.rmb and _crash_is_certain()', '\tassisted_brake = not input.rmb and _crash_is_certain()', 'the brake is assisted with the setting off'),
 (D, '\t_braking = input.rmb or assisted_brake', '\t_braking = input.rmb', 'the assist says it brakes and does not'),
 (D, '\t\tif absf(vehicle.x - car.x) >= vehicle.half_width + car.half_width():\n\t\t\tcontinue\n\t\tvar gap', '\t\tvar gap', 'a truck in the next lane is a certain crash'),
 (D, '\t\tif closing > 0.0 and gap < closing * within:', '\t\tif closing > 0.0 and gap < 0.0:', 'no crash is ever certain'),
 (D, '\t_steady_left = tuning.f("steady_start_s")', '\t_steady_left = 0.0', 'the wheel never holds itself after a stop'),
 (D, '\treturn steady_start and _steady_left > 0.0 and not hand.gripping', '\treturn _steady_left > 0.0 and not hand.gripping', 'the wheel holds itself with the setting off'),
 (D, '\treturn steady_start and _steady_left > 0.0 and not hand.gripping', '\treturn steady_start and not hand.gripping', 'the wheel holds itself all night'),
 (D, '\tif _steady_left > 0.0 and not _standing():\n\t\t_steady_left = maxf(_steady_left - DT, 0.0)', '\tif _steady_left > 0.0 and not _standing():\n\t\t_steady_left = maxf(_steady_left - DT * 0.5, 0.0)', 'the wheel holds itself for 4 s'),
 (D, '\tif steady_holds():\n\t\t# Steady start (GDD 17.1): the wheel holds itself, straight.\n\t\twheel.hold_at(_straight_angle())\n\telif left_hand_on_wheel():', '\tif left_hand_on_wheel():', 'held, the wheel is not held straight'),
 (G, '\treturn clampf(SettingsSpec.share(percent), 0.1, 1.0)', '\treturn 1.0', 'Game speed is always full'),
 (G, '\tif key == SettingsSpec.GAME_SPEED:\n\t\tapply_settings()', '\tif false:\n\t\tapply_settings()', 'a change of Game speed waits for the next launch'),
 (S, '\t\t\treturn (value is float or value is int) and GameData.as_float(value) >= GameData.as_float(record.get("min")) - 0.0001 \\', '\t\t\treturn (value is float or value is int) and true \\', 'a range allows anything below its least'),
 (S, '\t\treturn all[clampi(at + by, 0, all.size() - 1)]', '\t\treturn all[posmod(at + by, all.size())]', 'a range goes round at its ends'),
 (S, '\treturn all[posmod(at + by, all.size())]\n\n\n## A range', '\treturn all[clampi(at + by, 0, all.size() - 1)]\n\n\n## A range', 'a choice stops at its last option'),
 (S, '\treturn value if allows(id, value) else default_of(id)', '\treturn value', 'a value a setting cannot have is kept'),
 (S, '\treturn GameData.as_float(percent, 100.0) / 100.0', '\treturn 1.0', 'every percentage is 100%'),
 (V, '\treturn wheel_angle - wheel_tremor * (1.0 - clampf(shake, 0.0, 1.0))', '\treturn wheel_angle', 'the wheel is drawn trembling at 0%'),
 (V, '\treturn wheel_angle - wheel_tremor * (1.0 - clampf(shake, 0.0, 1.0))', '\treturn wheel_angle - wheel_tremor', 'the wheel is drawn still at 100%'),
 (P, '\treturn Vector2(-motion.x, motion.y) if mirrored else motion', '\treturn motion', 'the mirrored pointer goes the wrong way'),
 (P, '\treturn Vector2(width - at.x, at.y) if mirrored else at', '\treturn at', 'the mirrored pointer is drawn unmirrored'),
 (C, '\t_mirrored = GameData.as_bool(values[SettingsSpec.MIRRORED])', '\t_mirrored = false', 'the cabin is never mirrored'),
 (C, '\t_hud.visible = GameData.as_bool(values[SettingsSpec.NUMERIC_HUD]) or Game.args.has("hud")', '\t_hud.visible = Game.args.has("hud")', 'the Numeric HUD setting shows nothing'),
 (C, '\t_shake = SettingsSpec.share(values[SettingsSpec.SHAKE_VISUALS])', '\t_shake = 1.0', 'the shake setting never reaches the views'),
 (C, '\tsim.apply_settings(values)\n\t_shake', '\t_shake', 'the drive scene keeps the settings from the simulation'),
 (W, '\t\t\treturn Lines.format("settings.value.percent", [str(roundi(GameData.as_float(value)))])', '\t\t\treturn str(value)', 'a range is written as a bare number'),
]
