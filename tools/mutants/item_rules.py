"""Mutants of the item rules the validator refuses (GDD 14, D-040, D-042) for T-DATA-01. All 18 are killed.
    python3 tools/mutants.py T-DATA-01 tools/mutants/item_rules.py
"""
V = 'src/core/data_validator.gd'
PER_S = 'if entry.has("per_s") and (entry.has("effect") or GameData.as_string(entry.get("resource")) == "cash"):'
BACK = 'and to == anchor and not ritual.has("out_m"):'
MUTANTS = [
 (V, '\t"sip_extends_burn": ["amount"],\n', '', 'a sip may lengthen the burn by nothing'),
 (V, '\t"bead_calm": ["amount"],\n', '', 'a bead under music may calm by nothing'),
 (V, '\t"photo_sobers": ["amount"],\n', '', 'the photo may sober him for nothing'),
 (V, '\t"numb_courage": ["amount"],\n', '', 'Courage on the pills may multiply by nothing'),
 (V, '\t"calls_in_a_row": ["every", "amount"],', '\t"calls_in_a_row": ["amount"],', 'calls in a row need not say how many'),
 (V, '\t"calls_in_a_row": ["every", "amount"],', '\t"calls_in_a_row": ["every"],', 'calls in a row may pay nothing'),
 (V, '"every": _opt(_int(1.0))', '"every": _opt(_int(0.0))', 'every no calls'),
 (V, '"every": _opt(_int(1.0))', '"every": _opt(_num(1.0))', 'every two and a half calls'),
 (V, '"every": _opt(_int(1.0))', '"every": _opt(_t("any"))', 'every whatever'),
 (V, 'if anchor.get("over") is String and anchor.get("over") == anchor.get("id"):', 'if false:', 'an anchor may stand over itself'),
 (V, BACK, 'and to == anchor and false:', 'a carry may end where it began at once'),
 (V, BACK, 'and to == SLOT_ANCHOR and not ritual.has("out_m"):', 'only a carry back to the slot needs a distance'),
 (V, BACK, 'and to == anchor:', 'a distance does not make such a carry valid'),
 (V, PER_S, 'if entry.has("per_s") and entry.has("effect"):', 'cash may come by the second'),
 (V, PER_S, 'if entry.has("per_s") and GameData.as_string(entry.get("resource")) == "cash":', 'a status may have a rate'),
 (V, PER_S, 'if entry.has("per_s"):', 'not even Nerves by the second'),
 (V, '\t\telif lacks_amount:', '\t\telif false:', 'an entry may take nothing from its synergy'),
 (V, 'lacks_amount = lacks_amount or not GameData.as_dict(synergy).has("amount")', 'lacks_amount = true', 'no entry may take its amount from a synergy'),
]
