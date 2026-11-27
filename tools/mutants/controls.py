"""Mutants of the validator's check of GDD 4.6, "Controls always in the car"
(the M1 review's gesture finding) and of the rule that what the code draws
itself takes no scene (the M2 review's views finding), for T-DATA-01.
    python3 tools/mutants.py T-DATA tools/mutants/controls.py
"""
V = 'src/core/data_validator.gd'
R = 'data/rituals.json'
P = 'data/placeholders.json'
MUTANTS = [
 (V, '\t_check_required_records()\n\t_check_controls()', '\t_check_required_records()', 'the controls are not checked at all'),
 (V, '"visor", "face", "passenger_shoulder"],', '"visor", "face"],', 'the passenger\'s shoulder may be missing'),
 (V, '\t\tif anchor.has("time_s") and absf(GameData.as_float(anchor.get("time_s")) - reach) > REACH_EPSILON:', '\t\tif false:', 'any reach passes'),
 (V, 'const REACH_EPSILON: float = 0.0005', 'const REACH_EPSILON: float = 0.05', 'a reach may be 0.05 s off the table'),
 (V, '\t\tif GameData.as_bool(anchor.get("via_w")) != cross:', '\t\tif false:', 'either side of the hub passes'),
 (V, '\t\t\tif GameData.as_string(ritual.get("anchor")) != anchor_id or ritual.has("item"):', '\t\t\tif GameData.as_string(ritual.get("anchor")) != anchor_id:', 'an item\'s ritual counts as the control\'s'),
 (V, '\t\t\tif GameData.as_string(ritual.get("gesture")) != gesture:\n\t\t\t\tcontinue\n\t\t\tif control.has("flick_dirs")', '\t\t\tif control.has("flick_dirs")', 'any gesture passes'),
 (V, '\t\t\tif control.has("flick_dirs") and not _same_words(GameData.as_array(ritual.get("flick_dirs")), GameData.as_array(control.get("flick_dirs"))):\n\t\t\t\tcontinue\n', '', 'a FLICK any way passes'),
 (V, '\tif a.size() != b.size():\n\t\treturn false\n', '', 'a FLICK with a way too many passes'),
 (V, '\t\t\tif control.has("turns") and not is_equal_approx(GameData.as_float(ritual.get("turns")), GameData.as_float(control.get("turns"))):\n\t\t\t\tcontinue\n', '', 'a CRANK of any length passes'),
 (V, '{"anchor": "glovebox", "reach_s": 0.57,', '{"anchor": "glovebox", "reach_s": 0.75,', 'the validator\'s own table has another reach for the glovebox'),
 (V, '{"anchor": "headlight_knob", "reach_s": 0.53, "cross": true, "gesture": "TAP"}', '{"anchor": "headlight_knob", "reach_s": 0.53, "cross": true, "gesture": "HOLD"}', 'the validator\'s own table has another gesture for the headlights'),
 (V, '\t_check_controls()\n\t_check_drawn_by_code()', '\t_check_controls()', 'a scene on what the code draws is not looked at'),
 (V, '\t\tif GameData.as_bool(entry.get("drawn_by_code")) and entry.get("scene") != null:', '\t\tif entry.get("scene") != null:', 'no placeholder takes a scene'),
 (V, '\t\t"drawn_by_code": _opt(_bool()),', '\t\t"drawn_by_code": _opt(_str()),', 'the mark is a word'),
 (P, '"scene": null,\n    "drawn_by_code": true\n  },\n  "arm_upper"', '"scene": null\n  },\n  "arm_upper"', 'the forearm is not marked'),
 (R, '"gesture": "CRANK", "turns": 3,', '"gesture": "CRANK", "turns": 2,', 'the shipped window opens in two turns'),
]
