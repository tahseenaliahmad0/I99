"""Mutants for the test gaps the M6 review found in the tests of the items:
changes that the tests of a rule could not see, and that the checks added to
them since must see. All 45 are killed.

    python3 tools/mutants.py T-ITEM-DUCT-TAPE,T-ITEM-PHONE,T-SYN-PHONE-TAXI-SIGN,T-ITEM-BASE,T-ITEM-ARAK-FLASK,T-SYN-FLASK-PAINKILLERS,T-ITEM-ENERGY-DRINK,T-ITEM-PAINKILLERS,T-ITEM-CIGARETTES,T-ITEM-CHARM,T-ITEM-SEEDS,T-SYN-TEA-CIGARETTES,T-ITEM-LUCKY-NOTE,T-ITEM-MIXTAPE tools/mutants/m6_items.py

Each group needs only the test of its rule: GROUPS, below, names it. The
whole list against all fourteen tests is an hour's run or more; with
M6_GROUP set to a test of GROUPS the list is that test's group alone:

    M6_GROUP=T-ITEM-CHARM python3 tools/mutants.py T-ITEM-CHARM tools/mutants/m6_items.py

Before those checks were added, 42 of the 45 lived through the test named
for them. The other three are the review's own, dead already by checks that
came with the fixes of its code findings: 'a boss stop forgets the mend'
(T-ITEM-DUCT-TAPE) and the two of the look at the photo (T-ITEM-BASE). 'A
stop forgets the row of answered calls' lived through T-SYN-PHONE-TAXI-SIGN,
though T-ITEM-PHONE killed it by reading the counter: now the synergy's own
test kills it, by what the row pays.
"""
import os

D = 'src/core/drive_sim.gd'
I = 'src/core/item_sim.gd'
N = 'src/core/nerves_sim.gd'
E = 'src/core/effect_system.gd'
C = 'src/core/collision.gd'

RING = 'caller = CALLER_FAMILY if every > 0 and calls % every == 0 else CALLER_DISPATCHER'
ROW = 'if every > 0 and answered_run % every == 0:'
SAVED = 'return {"calls": calls, "answered_run": answered_run, '
BY_THE_SECOND = '\tif per_second > 0.0:\n\t\tper_second *= gain_mult\n'
SPARED = 'var spared: bool = collision.hit == Collision.Hit.SCRAPE and items.absorbs_scrape()'
CUT_OFF = '\t\tnerves.add(tuning.f("cut_off_nerves"))'
SIP = 'if GameData.as_string(synergy.get("rule")) == "sip_extends_burn" and GameData.as_string(synergy.get("with")) == String(owner.id):'
PUT_OUT_LIT = '\tif item_instance.burning and item_instance.use_effect != &"" and _effects.has_own(item_instance.use_effect):\n\t\t_effects.remove(item_instance.use_effect)\n'
PUT_OUT_HELD = '\tfor standing: Standing in item_instance.standing:\n\t\tif standing.held:\n\t\t\tstanding.held = false\n\t\t\t_effects.hold(standing.effect, item_instance.id, false)\n'
# The car is steered by the wheel's angle of `lag` ago (the flask's test, and the test of Flask + Painkillers).
LATE = (D, 'car.step(_road_dt, wheel.steer(), gate.gear, _braking, _extra_drift())', 'car.step(_road_dt, wheel.angle / wheel.max_angle(), gate.gear, _braking, _extra_drift())', 'the car is steered by the wheel as it is now')

# --- The duct tape: the first fault of each act, not of each leg.
TAPE = [
 (I, 'func begin_leg() -> void:\n\tphoto_used = false\n\tscrape_spared = false\n', 'func begin_leg() -> void:\n\tphoto_used = false\n\tscrape_spared = false\n\ttape_spent = false\n', 'the tape renews with every leg'),
 (D, '\tif act != act_before:\n\t\titems.begin_act()', '\tif act >= act_before:\n\t\titems.begin_act()', 'an act begins with every stretch of road'),
 (D, '\trun.begin_boss()\n', '\trun.begin_boss()\n\titems.begin_act()\n', 'the boss is a new act for the tape'),
 (D, '\t_shady_here = false\n\t_save_point()\n', '\t_shady_here = false\n\titems.mending = &""\n\t_save_point()\n', 'a boss stop forgets the mend'),
]
# --- The phone: every fourth call of the Telling is hers, stop or no stop; no phone, no calls.
CALLS = [
 (I, '\tcalls = GameData.as_int(state.get("calls"))\n', '\tcalls = 0\n', 'a stop forgets how many calls there were'),
 (I, SAVED, SAVED.replace('"calls": calls', '"calls": 0'), 'the save does not hold the count of calls'),
 (I, RING, RING.replace('calls % every == 0', 'calls == every'), 'only the fourth call is hers'),
 (I, '\t\tif caller != &"" or _call_wait >= 0.0:\n\t\t\t_hang_up()\n\t\treturn\n', '\t\treturn\n', 'a call rings on with no phone'),
]
# --- Phone + Taxi sign: every third answered in a row, stop or no stop.
ROWS = [
 (I, '\tanswered_run = GameData.as_int(state.get("answered_run"))\n', '\tanswered_run = 0\n', 'a stop forgets the row of answered calls'),
 (I, SAVED, SAVED.replace('"answered_run": answered_run', '"answered_run": 0'), 'the save does not hold the row of answered calls'),
 (I, ROW, ROW.replace('answered_run % every == 0', 'answered_run == every'), 'the row pays once'),
]
# --- The photo's once per leg through a stop.
PHOTO = [
 (I, 'return {"photo": photo_used, "spared": scrape_spared, "held": held}', 'return {"photo": false, "spared": scrape_spared, "held": held}', 'the save does not hold the look at the photo'),
 (I, '\tphoto_used = GameData.as_bool(state.get("photo"))\n', '', 'the look at the photo is not read from the save'),
]
# --- The flask: Courage and what comes by the second, Sway per stack, the
# stack a sip at the cap renews, Lag on the car.
FLASK = [
 (N, BY_THE_SECOND, '', 'Courage does not dull what frays him by the second'),
 (N, BY_THE_SECOND, '\tper_second *= gain_mult\n', 'Courage dulls what calms him by the second too'),
 (D, 'float(stacks) * sin(', 'float(mini(stacks, 2)) * sin(', 'Sway stops growing at two stacks'),
 (E, '\t\t\tif stacks[index] < stacks[shortest]:\n\t\t\t\tshortest = index\n', '\t\t\tpass\n', 'a sip at the cap renews the first stack'),
 LATE,
]
# --- Focus: what is the road's and what is his own.
FOCUS = [
 (D, 'encounter.step(_road_dt, _braking, gate.gear)', 'encounter.step(DT, _braking, gate.gear)', 'Focus: the encounter keeps his time'),
 (D, 'collision.step(_road_dt, car, traffic, gate.gear)', 'collision.step(DT, car, traffic, gate.gear)', 'Focus: collisions\' timers keep his time'),
 (D, 'leg.step_hazards(_road_dt)', 'leg.step_hazards(DT)', 'Focus: the potholes\' cooldown keeps his time'),
 (D, 'leg.step_traffic(_road_dt)', 'leg.step_traffic(DT)', 'Focus: what moves on the road keeps his time'),
 (D, 'leg.step_road(_road_dt, DT)', 'leg.step_road(DT, DT)', 'Focus: a gust\'s tell keeps his time'),
 (D, '\t\titems.step(DT)\n', '\t\titems.step(_road_dt)\n', 'Focus: the things in the cabin slow with the road'),
 (D, '\t\tnerves.step(DT)\n', '\t\tnerves.step(_road_dt)\n', 'Focus: his Nerves slow with the road'),
 (D, '\tgate.step(DT, input.pointer_delta', '\tgate.step(_road_dt, input.pointer_delta', 'Focus: the gear gate slows with the road'),
 (D, '\tsuspicion.add(leg.hazard_suspicion)\n\tsuspicion.step(DT)', '\tsuspicion.add(leg.hazard_suspicion)\n\tsuspicion.step(_road_dt)', 'Focus: Suspicion slows with the road'),
]
# --- Painkillers: "for the leg" on every leg.
PILLS = [
 (I, '\t\t_effects.hold(held, LEG, false)\n\t_leg_holds.clear()\n', '\t\t_effects.hold(held, LEG, false)\n', 'what the leg held is not forgotten at the gore'),
]
# --- Cigarettes: the ash rule for every cigarette; the pack taken out while one burns.
SMOKES = [
 (I, '\tcandidate.burn_time = 0.0\n', '', 'the next cigarette burns on from where the last ended'),
 (I, '\tcandidate.ashed = false\n', '', 'ashed once, ashed for good'),
 (I, '\tcandidate.ash_fell = false\n\tcandidate.lapse_left = -1.0\n', '\tcandidate.lapse_left = -1.0\n', 'the ash that fell is still the next cigarette\'s'),
 (I, PUT_OUT_LIT, '', 'a smoke burns on without its pack'),
]
# --- The charm: a scrape is a scrape whatever he touches; one thing hangs at the mirror.
CHARM = [
 (D, SPARED, SPARED.replace('and items', 'and collision.hit_vehicle_id == 0 and items'), 'the charm turns aside only what is no vehicle'),
 (D, SPARED, SPARED.replace('and items', 'and car.edge_touched != CarSim.EDGE_LEFT and items'), 'the charm turns aside nothing on his left'),
 (D, '\tif place != &"":\n\t\titems.remove_item(items.item_in_slot(place))\n', '', 'two things in one slot'),
]
# --- Seeds: being cut off still frays him, a happy honk still calms him.
SEEDS = [
 (D, CUT_OFF, '\t\tfray(SOURCE_TAILGATER, tuning.f("cut_off_nerves"))', 'chewing, being cut off is the tailgater\'s'),
 (D, CUT_OFF, '\t\tfray(SOURCE_HONK, tuning.f("cut_off_nerves"))', 'chewing, being cut off is a honk'),
 (D, CUT_OFF, '\t\tpass', 'being cut off frays nobody'),
 (D, 'nerves.add(collision.honk_nerves - collision.honk_frights)', 'nerves.add((collision.honk_nerves - collision.honk_frights) * (0.0 if effects.immune_to(SOURCE_HONK) else 1.0))', 'chewing, a happy honk does not calm'),
]
# --- Tea + Cigarettes: only the tea.
TEA = [
 (I, SIP, 'if GameData.as_string(synergy.get("rule")) == "sip_extends_burn":', 'anything used while one is lit lengthens the burn'),
]
# --- The lucky note: flat against Courage; one note is one note.
NOTE = [
 (C, 'close_call_cash += pay + cash_bonus', 'close_call_cash += pay + cash_bonus * cash_mult', 'the note is multiplied by what multiplies close calls'),
 (D, 'collision.cash_bonus = items.passive("close_call_bonus")', 'collision.cash_bonus = items.passive("close_call_bonus") * collision.cash_mult', 'the note is worth what close calls paid when it was put there'),
 (D, '\titems.remove_item(items.item(id))\n', '', 'given twice, he has two'),
]
# --- The mixtape taken out of the car.
DECK = [
 (I, PUT_OUT_HELD, '', 'what an item held stays held when it is gone'),
 (I, '\t_put_out(item)\n\titems.erase(item)\n', '\titems.erase(item)\n', 'what is taken out goes on doing what it did'),
]

# --- The test each group needs. (LATE is in two groups: each of the two tests kills it alone.)
GROUPS = [
 ('T-ITEM-DUCT-TAPE', TAPE),
 ('T-ITEM-PHONE', CALLS),
 ('T-SYN-PHONE-TAXI-SIGN', ROWS),
 ('T-ITEM-BASE', PHOTO),
 ('T-ITEM-ARAK-FLASK', FLASK),
 ('T-SYN-FLASK-PAINKILLERS', [LATE]),
 ('T-ITEM-ENERGY-DRINK', FOCUS),
 ('T-ITEM-PAINKILLERS', PILLS),
 ('T-ITEM-CIGARETTES', SMOKES),
 ('T-ITEM-CHARM', CHARM),
 ('T-ITEM-SEEDS', SEEDS),
 ('T-SYN-TEA-CIGARETTES', TEA),
 ('T-ITEM-LUCKY-NOTE', NOTE),
 ('T-ITEM-MIXTAPE', DECK),
]
MUTANTS = TAPE + CALLS + ROWS + PHOTO + FLASK + FOCUS + PILLS + SMOKES + CHARM + SEEDS + TEA + NOTE + DECK
if os.environ.get('M6_GROUP'):
    MUTANTS = [mutant for tests, group in GROUPS if tests == os.environ['M6_GROUP'] for mutant in group]
