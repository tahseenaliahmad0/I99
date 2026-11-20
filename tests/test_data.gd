extends TestSuite
## T-DATA-01: all JSON validates; every referenced id and line id exists.
##
## Three parts:
##   1. The shipped data in res://data validates with no error.
##   2. The schema examples printed in GDD 14 validate (as an in-memory fixture
##      on top of the shipped data), so the validator accepts the spec's own
##      shapes.
##   3. Each way of breaking that fixture is caught with the right error code,
##      so "validates" means something.

const BROKEN_DIR: String = "user://test_runs/broken_data"

## The records of GDD 14, verbatim.
const GDD_ITEM: String = """
{ "id": "cigarettes", "kind": "habit", "slots": ["ashtray"], "tags": ["smoke"],
  "rarity": "common", "price": 15, "contraband": false,
  "supply": { "uses": 10, "restock": 15 },
  "rituals": ["cig_light", "cig_ash"],
  "gives": [ {"effect": "lit", "duration": 25},
             {"resource": "nerves", "amount": -10, "over": 25} ],
  "takes": [ {"effect": "haze_rate", "amount": 0.02, "while": "lit"} ],
  "lapse": { "after": 30, "resource": "nerves", "amount": 8, "once": true },
  "synergies": [ {"with": "tea_glass", "rule": "sip_extends_burn", "amount": 10} ],
  "line_ids": { "name": "item.cigarettes.name" } }
"""
const GDD_RITUAL: String = """
{ "id": "cig_light", "anchor": "ashtray", "gesture": "HOLD", "hold_s": 1.2,
  "eyes_down": false, "blocks_view": null, "requires": ["supply>0", "!lit"],
  "on_complete": ["consume_supply", "add_effect:lit"], "sfx": "lighter_click" }
"""
const GDD_LEG: String = """
{ "id": "patrol", "acts": [2, 3], "lanes": 3, "divided": true, "density": 10,
  "condition": "clear", "par_s": 90,
  "beat_weights": { "CALM": 3, "CLUSTER": 3, "SLOWPOKE": 2, "MERGE": 2, "CURVE": 1, "HAZARD": 1 },
  "special": { "kind": "patrol", "at_s": 20, "duration_s": 35 },
  "modifiers_allowed": ["crosswind", "potholes"] }
"""
const GDD_BEAT: String = """
{ "id": "merge_right_truck", "type": "MERGE", "length_m": 120, "min_lanes": 2,
  "spawns": [ {"vehicle": "truck", "lane": "right_of_player", "s_offset": 60,
               "speed_kmh": 65, "lane_change": {"to": "player", "at_s_offset": 90}} ] }
"""
const GDD_STOP: String = """
{ "id": "fuel_station", "service": "shop", "stock": {"count": 3, "pools": ["habit", "keepsake"]},
  "clock_min": 10, "weight": 30 }
"""
const GDD_PASSENGER: String = """
{ "id": "hajjiya", "rides_legs": 3, "fare": 0,
  "hand": { "kind": "hold_wheel_straight", "duration_s": 6, "on": "tap" },
  "weights": [ {"when": "ritual_tag:smoke", "resource": "nerves", "amount": 10},
               {"when": "gear>=4", "resource": "nerves", "per_s": 3} ],
  "on_leave": ["nerves:-20", "add_effect:blessing"], "line_prefix": "passenger.hajjiya" }
"""
const GDD_TABLE: String = """
{ "id": "uncles", "unlock": "win:drivers", "depart_min": 0,
  "rules": { "patrol_every_act": true, "checkpoint_suspicion_mult": 1.25 },
  "heckle_weights": { "DOUBT": 60, "TWIST": 20, "DARE": 20 }, "line_prefix": "table.uncles" }
"""
const GDD_HECKLE: String = """
{ "id": "doubt_all_night", "type": "DOUBT", "tables": ["uncles", "groom"],
  "line_id": "heckle.uncles.doubt.1", "window_s": 15,
  "answer": ["close_call", "gear4_5s"], "pass": {"nerves": -10}, "fail": {"nerves": 10} }
"""
const GDD_PLACEHOLDER: String = """
{ "veh_truck": { "placeholder": {"shape": "box", "size": [2.5, 3.0, 12.0], "color": "#6C7A89"},
                 "scene": null } }
"""

var _roots: Dictionary = {}
var _lines: Dictionary = {}


func test_data_01() -> void:
	_check_shipped_data()
	_check_gdd_examples()
	_check_broken_records()
	_check_broken_tuning_anchors_lines()
	_check_broken_files()
	_check_broken_item_rules()
	_check_broken_passenger_rules()
	_check_broken_cabin_props()
	_check_broken_boss_rules()


# --- 1. Shipped data ----------------------------------------------------------

func _check_shipped_data() -> void:
	var errors: PackedStringArray = DataValidator.validate(data)
	check(errors.is_empty(), "res://data validates with no error; first: %s" % _first(errors))
	check_eq(data.roots.size(), GameData.JSON_FILES.size(), "every JSON file of GDD 13.2 is loaded")
	check(data.lines.has("en") and data.lines.has("ar"), "both line files are loaded")
	check(data.line_ids("en").size() > 0, "lines_en.csv holds lines")
	check_eq(data.line_ids("ar").size(), data.line_ids("en").size(), "lines_ar.csv carries the same number of ids")
	check(data.tuning.problems.is_empty(), "tuning.json has no duplicate constants")
	check(data.has_line("narrator.start"), "a line of GDD 3.6 exists by id")
	note("%d tuning constants, %d anchors, %d lines" % [
		data.tuning.keys().size(), data.records("anchors").size(), data.line_ids().size()])


# --- 9. The set pieces (M7) ----------------------------------------------------

## The rules a boss's record must keep (GDD 10.2 to 10.4, D-046 to D-048 and
## the review of M7): each broken once.
func _check_broken_boss_rules() -> void:
	_reset_fixture()
	_record("bosses", "storm").erase("storm")
	_expect("E_MISSING", "storm", "a Storm without its numbers")

	_reset_fixture()
	_boss_numbers("storm")["moved_off_kmh"] = _boss_numbers("storm")["stopped_kmh"]
	_expect("E_RANGE", "storm.moved_off_kmh", "a Storm in which driving off is no more than rolling")

	_reset_fixture()
	_boss_numbers("storm")["rear_end_tell_s"] = 1.0
	_expect("E_RANGE", "storm.rear_end_tell_s", "a horn behind him that leaves no time to drive off")

	_reset_fixture()
	GameData.as_dict(_boss_numbers("storm")["tail_lights"])["gap_m"] = [220, 140]
	_expect("E_RANGE", "storm.tail_lights.gap_m", "tail lights whose gaps are not least, most")

	_reset_fixture()
	GameData.as_dict(_boss_numbers("checkpoint")["corridor"])["at_m"] = 20
	_expect("E_RANGE", "checkpoint.corridor", "a taper that begins before the Checkpoint's road")

	_reset_fixture()
	GameData.as_dict(_boss_numbers("checkpoint")["corridor"])["gap_m"] = 1.0
	_expect("E_RANGE", "checkpoint.corridor.gap_m", "barriers nearer than the car is wide")

	_reset_fixture()
	GameData.as_dict(_boss_numbers("checkpoint")["queue"])["cars"] = 40
	_expect("E_RANGE", "checkpoint.queue.cars", "a queue that does not fit between the barriers")

	_reset_fixture()
	_boss_numbers("checkpoint")["pass_under"] = 120
	_expect("E_RANGE", "checkpoint.pass_under", "passing at more Suspicion than turns him back")

	_reset_fixture()
	_boss_numbers("checkpoint")["documents"] = ["licence", "licence", "registration"]
	_expect("E_DUP_ID", "checkpoint.documents", "a document listed twice")

	_reset_fixture()
	_boss_numbers("dawn")["sunrise_at_m"] = 3000
	_expect("E_RULE", "dawn", "a sunrise after the last checkpoint")

	_reset_fixture()
	_record("bosses", "storm")["modifiers"] = ["crosswind", "thorough"]
	_expect("E_RULE", "bosses[storm].modifiers", "a boss with another boss's modifier")


## A boss's own numbers in the fixture (the object under its id).
func _boss_numbers(id: String) -> Dictionary:
	return GameData.as_dict(_record("bosses", id)[id])


# --- 6. What items say they do (M6) -------------------------------------------

## The rules that came with the items of GDD 7: entries of gives and takes,
## synergy rules, tags, standing changes, and what their rituals may say.
func _check_broken_item_rules() -> void:
	_reset_fixture()
	_record("items", "cigarettes")["synergies"] = [{"with": "tea_glass", "rule": "nonsense"}]
	_expect("E_ENUM", "items[cigarettes].synergies[0].rule", "a synergy rule the simulation does not know")

	_reset_fixture()
	_record("items", "cigarettes")["tags"] = ["smoke", "gadget"]
	_expect("E_REF", "items[cigarettes].tags[1]", "a tag that is not in the tag list")

	_reset_fixture()
	_record("items", "cigarettes")["until_boss"] = "ambush"
	_expect("E_REF", "items[cigarettes].until_boss", "an item for a boss the Telling does not have")

	_reset_fixture()
	_record("items", "cigarettes")["gives"] = [{"effect": "lit", "duration": 25, "bogus": 1}]
	_expect("E_UNKNOWN_KEY", "items[cigarettes].gives[0]", "an entry with an unknown key")

	_reset_fixture()
	_record("items", "cigarettes")["gives"] = [{"effect": "glow", "duration": 5}]
	_expect("E_REF", "items[cigarettes].gives[0].effect", "an entry with an unknown status")

	_reset_fixture()
	_record("items", "cigarettes")["gives"] = [{"effect": "lit", "resource": "nerves", "amount": -1}]
	_expect("E_RULE", "items[cigarettes].gives[0]", "an entry that is both a status and a resource")

	_reset_fixture()
	_record("items", "cigarettes")["gives"] = [{"duration": 5}]
	_expect("E_RULE", "items[cigarettes].gives[0]", "an entry that is neither")

	_reset_fixture()
	_record("items", "cigarettes")["takes"] = [{"resource": "fuel", "amount": 1}]
	_expect("E_ENUM", "items[cigarettes].takes[0].resource", "an unknown resource")

	_reset_fixture()
	_record("items", "cigarettes")["takes"] = [{"resource": "nerves", "amount": 1, "per_s": 1}]
	_expect("E_RULE", "items[cigarettes].takes[0]", "a resource entry both at once and by the second")

	_reset_fixture()
	_record("items", "cigarettes")["takes"] = [{"resource": "nerves"}]
	_expect("E_RULE", "items[cigarettes].takes[0]", "a resource entry with no amount")

	_reset_fixture()
	_record("items", "cigarettes")["gives"] = [{"effect": "lit", "duration": "long"}]
	_expect("E_TYPE", "items[cigarettes].gives[0].duration", "a duration that is not a number")

	_reset_fixture()
	_record("items", "cigarettes")["gives"] = [{"effect": "lit", "duration": 5, "while": "moonlight"}]
	_expect("E_REF", "items[cigarettes].gives[0].while", "an entry under an unknown condition")

	_reset_fixture()
	_record("items", "cigarettes")["gives"] = [{"resource": "nerves", "amount": -2, "synergy": "bead_calm"}]
	_expect("E_REF", "items[cigarettes].gives[0].synergy", "an entry naming a synergy the item does not have")

	_reset_fixture()
	_record("items", "cigarettes")["gives"] = [{"passive": "moon_boots", "amount": 1}]
	_expect("E_ENUM", "items[cigarettes].gives[0].passive", "an unknown standing change")

	_reset_fixture()
	_record("items", "cigarettes")["gives"] = [{"passive": "close_call_bonus", "amount": 1, "while": "lit"}]
	_expect("E_RULE", "items[cigarettes].gives[0]", "a standing change with more than its amount")

	_reset_fixture()
	_record("items", "cigarettes")["gives"] = [{"effect": "lit", "for": "act"}]
	_expect("E_RULE", "items[cigarettes].gives[0].for", "a status held for something other than the leg")

	_reset_fixture()
	_record("items", "cigarettes")["takes"] = [{"effect": "haze_rate", "while": "lit"}]
	_expect("E_RULE", "items[cigarettes].takes[0]", "a haze entry with no rate")

	# Rituals.
	_reset_fixture()
	_record("rituals", "cig_light")["on_complete"] = ["refill:soup"]
	_expect("E_REF", "rituals[cig_light].on_complete[0]", "a refill of a tag that is not in the tag list")

	_reset_fixture()
	_record("rituals", "cig_light")["requires"] = ["tag:soup"]
	_expect("E_REF", "rituals[cig_light].requires[0]", "a condition on a tag that is not in the tag list")

	_reset_fixture()
	_record("rituals", "cig_light")["blocks_view"] = "everything"
	_expect("E_ENUM", "rituals[cig_light].blocks_view", "an unknown part of the view")

	_reset_fixture()
	var carried: Dictionary = _record("rituals", "cig_light")
	carried["gesture"] = "DRAG_TO"
	carried["to"] = "@slot"
	_expect("E_RULE", "rituals[cig_light].to", "a carry back to the slot by a ritual that is not at its slot")

	_reset_fixture()
	carried = _record("rituals", "cig_light")
	carried["gesture"] = "DRAG_TO"
	carried["to"] = "moon"
	_expect("E_REF", "rituals[cig_light].to", "a carry to an unknown anchor")

	_reset_fixture()
	carried = _record("rituals", "cig_light")
	carried["gesture"] = "DRAG_TO"
	_expect("E_RULE", "rituals[cig_light]", "a carry with no destination and no distance")

	_reset_fixture()
	carried = _record("rituals", "cig_light")
	carried["gesture"] = "DRAG_TO"
	carried["across_m"] = 0.4
	check(_validate().is_empty(), "a carry across with no destination is valid; first: %s" % _first(_validate()))

	# Statuses and anchors.
	_reset_fixture()
	_record("effects", "lit")["immune"] = ["sneeze"]
	_expect("E_ENUM", "effects[lit].immune[0]", "immunity to an unknown source of Nerves")

	_reset_fixture()
	_record("effects", "lit")["road_speed"] = 3.0
	_expect("E_RANGE", "effects[lit].road_speed", "a road that runs faster than time")

	_reset_fixture()
	_record("anchors", "tape")["over"] = "moon"
	_expect("E_REF", "anchors[tape].over", "an anchor standing over an unknown one")


## The rules that came with the passengers of GDD 8: what a Hand can be,
## when a Weight bites, who must exist, where a hitcher stands.
func _check_broken_passenger_rules() -> void:
	_reset_fixture()
	check(_validate().is_empty(), "(the fixture is valid before it is broken; first: %s)" % _first(_validate()))
	_reset_fixture()
	GameData.as_dict(_record("passengers", "hajjiya").get("hand"))["kind"] = "juggle"
	_expect("E_ENUM", "passengers[hajjiya].hand.kind", "a Hand the simulation does not know")

	_reset_fixture()
	GameData.as_dict(_record("passengers", "hajjiya").get("hand")).erase("duration_s")
	_expect("E_RULE", "passengers[hajjiya].hand", "a hand on the wheel for no time")

	_reset_fixture()
	GameData.as_dict(_record("passengers", "drummer").get("hand")).erase("at")
	_expect("E_RULE", "passengers[drummer].hand", "tea passed to nowhere")

	_reset_fixture()
	_record("passengers", "drummer").erase("drums")
	_expect("E_RULE", "passengers[drummer].hand", "a drummer without a drum who passes the tea between drumming")
	_expect("E_RULE", "passengers[drummer].weights[0].when", "and whose drumming a Patrol hears")

	_reset_fixture()
	_record("passengers", "conscript").erase("sleeps")
	_expect("E_RULE", "passengers[conscript].hand", "a cigarette from one who is never woken")
	_expect("E_RULE", "passengers[conscript].weights[0].when", "and who snores without sleeping")

	_reset_fixture()
	GameData.as_dict(GameData.as_array(_record("passengers", "hajjiya").get("weights"))[0])["when"] = "full_moon"
	_expect("E_ENUM", "passengers[hajjiya].weights[0].when", "a Weight that bites at a moment the simulation does not know")

	_reset_fixture()
	GameData.as_dict(GameData.as_array(_record("passengers", "hajjiya").get("weights"))[0])["when"] = "ritual_tag:perfume"
	_expect("E_REF", "passengers[hajjiya].weights[0].when", "a Weight on a tag no item carries")

	_reset_fixture()
	GameData.as_dict(GameData.as_array(_record("passengers", "student").get("weights"))[1])["when"] = "gear>=fast&rain"
	_expect("E_ENUM", "passengers[student].weights[1].when", "a gear that is no number")

	_reset_fixture()
	GameData.as_dict(GameData.as_array(_record("passengers", "student").get("weights"))[0])["per_s"] = 1.0
	_expect("E_RULE", "passengers[student].weights[0]", "a Weight with both an amount and a rate")

	_reset_fixture()
	var by_second: Dictionary = GameData.as_dict(GameData.as_array(_record("passengers", "student").get("weights"))[1])
	by_second.erase("per_s")
	by_second["amount"] = 2.0
	_expect("E_RULE", "passengers[student].weights[1]", "an amount where the Weight counts by the second")

	_reset_fixture()
	GameData.as_dict(GameData.as_array(_record("passengers", "student").get("weights"))[0])["resource"] = "fuel"
	_expect("E_ENUM", "passengers[student].weights[0].resource", "a Weight on something that is not weighed")

	_reset_fixture()
	GameData.as_dict(_record("passengers", "apprentice").get("retunes"))["to"] = "opera"
	_expect("E_REF", "passengers[apprentice].retunes.to", "a radio turned to a station that does not exist")

	_reset_fixture()
	GameData.as_dict(_record("passengers", "apprentice").get("retunes"))["every_s"] = 0
	_expect("E_RULE", "passengers[apprentice].retunes.every_s", "a radio retuned every 0 s")

	_reset_fixture()
	GameData.as_dict(_record("passengers", "conscript").get("always"))["suspicion_gain_mult"] = 1.5
	_expect("E_RANGE", "passengers[conscript].always.suspicion_gain_mult", "a uniform that raises Suspicion")

	_reset_fixture()
	GameData.as_dict(_record("passengers", "student").get("always"))["effects"] = ["glow"]
	_expect("E_REF", "passengers[student].always.effects[0]", "talk that holds on a status that does not exist")

	_reset_fixture()
	_record("passengers", "student")["mood"] = "cheerful"
	_expect("E_UNKNOWN_KEY", "passengers[student].mood", "a key no passenger has")

	_reset_fixture()
	var passengers: Array = _list("passengers", "passengers")
	for index: int in range(passengers.size() - 1, -1, -1):
		if GameData.as_string(GameData.as_dict(passengers[index]).get("id")) == "conscript":
			passengers.remove_at(index)
	_expect("E_MISSING", "passengers[conscript]", "one of the five passengers of GDD 8.2 missing")

	_reset_fixture()
	var english: Dictionary = _lines["en"]
	english.erase("passenger.student.leave")
	var arabic: Dictionary = _lines["ar"]
	arabic.erase("passenger.student.leave")
	_expect("E_REF", "passengers[student].line_prefix", "a passenger with no word for getting out")

	_reset_fixture()
	_record("stops", "fuel_station")["hitcher"] = "often"
	_expect("E_ENUM", "stops[fuel_station].hitcher", "a hitcher who stands there neither always nor sometimes")

	_reset_fixture()
	GameData.as_array(_record("rituals", "passenger_ask").get("on_complete"))[0] = "beg"
	_expect("E_ENUM", "rituals[passenger_ask].on_complete[0]", "an op the shoulder does not know")


## Props that show a cabin switch (the window's glass, the hazard lamp).
func _check_broken_cabin_props() -> void:
	_reset_fixture()
	GameData.as_array(_record("props", "window_glass").get("flags"))[0] = "!sunroof_open"
	_expect("E_ENUM", "props[window_glass].flags[0]", "a prop that shows a switch the cabin does not have")

	_reset_fixture()
	_record("props", "window_glass")["alpha"] = 1.5
	_expect("E_RANGE", "props[window_glass].alpha", "glass more than opaque")

	_reset_fixture()
	_record("props", "hazard_lamp")["blink"] = "fast"
	_expect("E_TYPE", "props[hazard_lamp].blink", "a blink that is not yes or no")


# --- 2. The GDD 14 examples ---------------------------------------------------

func _check_gdd_examples() -> void:
	_reset_fixture()
	var errors: PackedStringArray = _validate()
	check(errors.is_empty(), "the GDD 14 example records validate; first: %s" % _first(errors))


## Shipped data plus the GDD 14 examples and the few records they point at.
func _reset_fixture() -> void:
	_roots = data.roots.duplicate(true)
	_lines = data.lines.duplicate(true)

	var items_root: Dictionary = _roots["items"]
	items_root["starting_cabin"] = []
	_put("slots", {"id": "ashtray", "anchor": "ashtray"})
	_put("slots", {"id": "cup_a", "anchor": "cup_a"})
	_put("effects", {"id": "lit"})
	_put("effects", {"id": "blessing"})

	_put("rituals", _parse(GDD_RITUAL))
	_put("rituals", {
		"id": "cig_ash", "anchor": "ashtray", "gesture": "FLICK", "flick_dirs": ["down"], "eyes_down": false,
		"requires": ["lit"], "on_complete": ["ash"], "sfx": null})
	_put("rituals", {
		"id": "tea_sip", "anchor": "cup_a", "gesture": "HOLD", "hold_s": 0.6, "eyes_down": false,
		"requires": ["supply>0"], "on_complete": ["consume_supply"]})

	_put("items", _parse(GDD_ITEM))
	_put("items", {
		"id": "tea_glass", "kind": "habit", "slots": ["cup_a"], "price": 0, "contraband": false,
		"rituals": ["tea_sip"], "gives": [], "takes": [], "line_ids": {"name": "item.tea_glass.name"}})

	_put("modifiers", {"id": "crosswind"})
	_put("modifiers", {"id": "potholes"})
	_put("legs", _parse(GDD_LEG))

	_put("vehicles", {
		"id": "truck", "width": 2.5, "length": 12.0, "speed_kmh": [60, 70],
		"yields_to_horn": false, "honk_nerves": 0, "acts": [1, 2, 3], "placeholder": "veh_truck"})
	_put("beats", _parse(GDD_BEAT))

	_put("stops", _parse(GDD_STOP))
	_put("passengers", _parse(GDD_PASSENGER))

	_put("tables", {
		"id": "drivers", "unlock": "start", "depart_min": 0, "rules": {},
		"heckle_weights": {"DARE": 100}, "line_prefix": "table.drivers"})
	_put("tables", _parse(GDD_TABLE))
	_put("tables", {
		"id": "groom", "unlock": "win:uncles", "depart_min": 45, "rules": {},
		"heckle_weights": {"DARE": 1, "DOUBT": 1, "ORDER": 1}, "line_prefix": "table.groom"})
	_put("heckles", _parse(GDD_HECKLE))

	var placeholders: Dictionary = _roots["placeholders"]
	placeholders.merge(_parse(GDD_PLACEHOLDER))
	var sfx: Dictionary = _roots["sfx"]
	sfx["lighter_click"] = {"synth": {"wave": "click"}, "stream": null}

	for id: String in ["item.cigarettes.name", "item.tea_glass.name", "table.drivers.name",
			"table.uncles.name", "table.groom.name"]:
		_add_line(id, "placeholder")


# --- 3. Broken variants -------------------------------------------------------

func _check_broken_records() -> void:
	# Items
	_reset_fixture()
	_record("items", "cigarettes").erase("price")
	_expect("E_MISSING", "items[cigarettes].price", "a missing required key")

	_reset_fixture()
	_record("items", "cigarettes")["price"] = "cheap"
	_expect("E_TYPE", "items[cigarettes].price", "a string where a number belongs")

	_reset_fixture()
	_record("items", "cigarettes")["pricee"] = 15
	_expect("E_UNKNOWN_KEY", "items[cigarettes].pricee", "a misspelt key")

	_reset_fixture()
	_record("items", "cigarettes")["kind"] = "gadget"
	_expect("E_ENUM", "items[cigarettes].kind", "an unknown item kind")

	_reset_fixture()
	_record("items", "cigarettes")["rituals"] = ["cig_light", "cig_missing"]
	_expect("E_REF", "items[cigarettes].rituals[1]", "an unknown ritual id")

	_reset_fixture()
	_record("items", "cigarettes")["slots"] = ["cup_z"]
	_expect("E_REF", "items[cigarettes].slots[0]", "an unknown slot id")

	_reset_fixture()
	_record("items", "cigarettes")["line_ids"] = {"name": "item.nope.name"}
	_expect("E_REF", "items[cigarettes].line_ids.name", "an unknown line id")

	_reset_fixture()
	_record("items", "cigarettes")["synergies"] = [{"with": "ghost_item", "rule": "x"}]
	_expect("E_REF", "items[cigarettes].synergies[0].with", "a synergy with an unknown item")

	_reset_fixture()
	_list("items", "items").append(_record("items", "cigarettes").duplicate(true))
	_expect("E_DUP_ID", "items[cigarettes]", "a duplicate id")

	_reset_fixture()
	_record("items", "tea_glass")["id"] = "Tea Glass"
	_expect("E_ID", "items[Tea Glass]", "an id that is not lower_snake_case")

	_reset_fixture()
	_record("items", "cigarettes")["supply"] = {"uses": 2.5, "restock": 15}
	_expect("E_TYPE", "items[cigarettes].supply.uses", "a fraction where a whole number belongs")

	# Rituals
	_reset_fixture()
	_record("rituals", "cig_light")["anchor"] = "ash_tray"
	_expect("E_REF", "rituals[cig_light].anchor", "an unknown anchor id")

	_reset_fixture()
	_record("rituals", "cig_light")["gesture"] = "WAVE"
	_expect("E_ENUM", "rituals[cig_light].gesture", "an unknown gesture")

	_reset_fixture()
	_record("rituals", "cig_light")["sfx"] = "missing_click"
	_expect("E_REF", "rituals[cig_light].sfx", "an unknown sfx id")

	_reset_fixture()
	_record("rituals", "cig_light")["eyes_down"] = "no"
	_expect("E_TYPE", "rituals[cig_light].eyes_down", "a string where a boolean belongs")

	_reset_fixture()
	_record("rituals", "cig_light").erase("hold_s")
	_expect("E_RULE", "rituals[cig_light]", "a HOLD ritual with no hold time")

	_reset_fixture()
	_record("rituals", "cig_ash")["flick_dirs"] = ["sideways"]
	_expect("E_ENUM", "rituals[cig_ash].flick_dirs[0]", "an unknown flick direction")

	_reset_fixture()
	_record("rituals", "cig_light")["on_complete"] = ["consume_supply", "explode"]
	_expect("E_ENUM", "rituals[cig_light].on_complete[1]", "an unknown ritual op")

	_reset_fixture()
	_record("rituals", "cig_light")["on_complete"] = ["add_effect:glowing"]
	_expect("E_REF", "rituals[cig_light].on_complete[0]", "an op that names an unknown effect")

	_reset_fixture()
	_record("rituals", "cig_light")["requires"] = ["supply>0", "!glowing"]
	_expect("E_REF", "rituals[cig_light].requires[1]", "a condition that names an unknown effect")

	_reset_fixture()
	_record("rituals", "cig_light")["on_complete"] = ["toggle:sunroof"]
	_expect("E_ENUM", "rituals[cig_light].on_complete[0]", "a toggle of an unknown cabin switch")

	_reset_fixture()
	_record("rituals", "tea_sip")["anchor"] = "@slot"
	_expect("E_RULE", "rituals[tea_sip]", "a ritual at @slot with no item")

	_reset_fixture()
	_record("passengers", "hajjiya")["on_leave"] = ["nerves:-20", "add_effect:halo"]
	_expect("E_REF", "passengers[hajjiya].on_leave[1]", "a passenger op that names an unknown effect")

	_reset_fixture()
	items_root_for_test()["starting_cabin"] = [{"item": "cigarettes", "slot": "cup_a", "supply": 5}]
	_expect("E_RULE", "starting_cabin[0].slot", "a starting item in a slot it does not fit")

	_reset_fixture()
	items_root_for_test()["starting_cabin"] = [{"item": "cigars", "slot": "ashtray", "supply": 5}]
	_expect("E_REF", "starting_cabin[0].item", "a starting item that does not exist")

	_reset_fixture()
	_record("slots", "ashtray")["anchor"] = "ash_tray"
	_expect("E_REF", "slots[ashtray].anchor", "a slot at an unknown anchor")

	# Legs and beats
	_reset_fixture()
	_record("legs", "patrol")["modifiers_allowed"] = ["sandstorm"]
	_expect("E_REF", "legs[patrol].modifiers_allowed[0]", "an unknown modifier id")

	_reset_fixture()
	_record("legs", "patrol")["beat_weights"] = {"CALM": 3, "WALL": 1}
	_expect("E_ENUM", "legs[patrol].beat_weights", "an unknown beat type")

	_reset_fixture()
	_record("legs", "patrol")["lanes"] = 4
	_expect("E_RANGE", "legs[patrol].lanes", "a lane count outside 1 to 3")

	_reset_fixture()
	_record("legs", "patrol")["acts"] = [2, 4]
	_expect("E_RANGE", "legs[patrol].acts[1]", "an act outside 1 to 3")

	_reset_fixture()
	_record("beats", "merge_right_truck")["spawns"] = [{"vehicle": "hovercraft", "lane": "player", "s_offset": 60, "speed_kmh": 65}]
	_expect("E_REF", "beats[merge_right_truck].spawns[0].vehicle", "an unknown vehicle id")

	_reset_fixture()
	_record("beats", "merge_right_truck")["spawns"] = [{"vehicle": "truck", "lane": "middle", "s_offset": 60, "speed_kmh": 65}]
	_expect("E_ENUM", "beats[merge_right_truck].spawns[0].lane", "an unknown lane word")

	_reset_fixture()
	_record("beats", "merge_right_truck")["spawns"] = [{"vehicle": "truck", "lane": "player", "s_offset": 60, "speed_kmh": 140}]
	_expect("E_RULE", "beats[merge_right_truck].spawns[0].speed_kmh", "a beat vehicle faster than third gear")

	_reset_fixture()
	_record("beats", "merge_right_truck")["spawns"] = [{"vehicle": "truck", "lane": "right_of_player", "s_offset": 60, "speed_kmh": 65, "lane_change": {"to": "player", "at_s_offset": 40}}]
	_expect("E_RULE", "beats[merge_right_truck].spawns[0].lane_change.at_s_offset", "a lane change behind the vehicle")

	_reset_fixture()
	_record("beats", "merge_right_truck")["length_m"] = [200, 120]
	_expect("E_TYPE", "beats[merge_right_truck].length_m", "a length range written backwards")

	_reset_fixture()
	_record("legs", "patrol")["condition"] = "fog"
	_expect("E_ENUM", "legs[patrol].condition", "an unknown road condition")

	_reset_fixture()
	_record("legs", "patrol")["special"] = {"kind": "ambush"}
	_expect("E_ENUM", "legs[patrol].special.kind", "an unknown encounter")

	_reset_fixture()
	_list("legs", "legs").erase(_record("legs", "motorcade"))
	_expect("E_MISSING", "legs[motorcade]", "a leg type of GDD 9.1 that is missing")

	_reset_fixture()
	_list("beats", "vehicles").erase(_record("vehicles", "tanker"))
	_expect("E_MISSING", "vehicles[tanker]", "a vehicle of GDD 5.5 that is missing")

	_reset_fixture()
	_record("beats", "merge_right_truck")["type"] = "AMBUSH"
	_expect("E_ENUM", "beats[merge_right_truck].type", "an unknown beat type")

	# Stops, passengers, tables, heckles
	_reset_fixture()
	_record("stops", "fuel_station")["stock"] = {"count": 3, "pools": ["weapon"]}
	_expect("E_ENUM", "stops[fuel_station].stock.pools[0]", "an unknown item pool")

	_reset_fixture()
	_record("passengers", "hajjiya")["line_prefix"] = "passenger.nobody"
	_expect("E_REF", "passengers[hajjiya].line_prefix", "a line prefix with no lines")

	_reset_fixture()
	_record("passengers", "hajjiya")["rides_until"] = "basra"
	_expect("E_RULE", "passengers[hajjiya]", "both rides_legs and rides_until")

	_reset_fixture()
	_record("passengers", "hajjiya").erase("rides_legs")
	_expect("E_RULE", "passengers[hajjiya]", "neither rides_legs nor rides_until")

	_reset_fixture()
	_record("tables", "uncles")["unlock"] = "win:nobody"
	_expect("E_REF", "tables[uncles].unlock", "an unlock that names an unknown table")

	_reset_fixture()
	_record("tables", "uncles")["unlock"] = "whenever"
	_expect("E_ENUM", "tables[uncles].unlock", "an unlock that is neither start nor win:<id>")

	_reset_fixture()
	_record("tables", "uncles")["heckle_weights"] = {"SHOUT": 5}
	_expect("E_ENUM", "tables[uncles].heckle_weights", "an unknown heckle type")

	_reset_fixture()
	_record("heckles", "doubt_all_night")["tables"] = ["uncles", "strangers"]
	_expect("E_REF", "heckles[doubt_all_night].tables[1]", "an unknown table id")

	_reset_fixture()
	_record("heckles", "doubt_all_night")["line_id"] = "heckle.uncles.doubt.99"
	_expect("E_REF", "heckles[doubt_all_night].line_id", "an unknown line id")

	_reset_fixture()
	_record("heckles", "doubt_all_night")["type"] = "INSULT"
	_expect("E_ENUM", "heckles[doubt_all_night].type", "an unknown heckle type")

	# Faults
	_reset_fixture()
	_record("faults", "rattle")["params"] = {"nerves_per_s": "a little"}
	_expect("E_TYPE", "faults[rattle].params.nerves_per_s", "a non-number fault parameter")

	# Registries
	_reset_fixture()
	_registry_entry("placeholders", "veh_truck")["placeholder"] = {"shape": "box", "size": [1, 1, 1], "color": "red"}
	_expect("E_TYPE", "veh_truck.placeholder.color", "a colour that is not #RRGGBB")

	_reset_fixture()
	_registry_entry("placeholders", "veh_truck")["placeholder"] = {"shape": "blob", "size": [1, 1, 1], "color": "#FFFFFF"}
	_expect("E_ENUM", "veh_truck.placeholder.shape", "an unknown placeholder shape")

	_reset_fixture()
	_registry_entry("placeholders", "veh_truck")["scene"] = "res://scenes/no_such_truck.tscn"
	_expect("E_REF", "veh_truck.scene", "a scene path that does not exist")

	_reset_fixture()
	_registry_entry("placeholders", "veh_truck").erase("scene")
	_expect("E_MISSING", "veh_truck.scene", "a registry entry with no scene key")

	_reset_fixture()
	_registry_entry("sfx", "lighter_click")["stream"] = "res://no_such_sound.wav"
	_expect("E_REF", "lighter_click.stream", "a stream path that does not exist")

	_reset_fixture()
	_registry_entry("sfx", "lighter_click").erase("synth")
	_expect("E_MISSING", "lighter_click.synth", "an sfx entry with no synth")


func _check_broken_tuning_anchors_lines() -> void:
	# Tuning
	_reset_fixture()
	_group("hand_wheel").erase("hand_speed")
	_expect("E_MISSING", "hand_speed", "a missing GDD 15 constant")

	_reset_fixture()
	_group("car")["gear_speeds"] = [40, 70, 100, 130]
	_expect("E_RANGE", "gear_speeds", "four gear speeds instead of five")

	# What the code divides by cannot be zero, and the constants the build
	# added to GDD 15 are as required as the GDD's own.
	for divisor: String in ["gate_unit", "wheel_max_angle", "bead_max_rate", "reference_height", "hand_speed"]:
		_reset_fixture()
		_group("hand_wheel")[divisor] = 0
		_expect("E_RANGE", divisor, "a zero where the code divides (%s)" % divisor)
	_reset_fixture()
	_group("hand_wheel")["camera_fov"] = 0
	_expect("E_RANGE", "camera_fov", "a field of view of nothing")
	for added: String in ["gate_grind_lock", "tap_max_time", "hand_free_bounds_min"]:
		_reset_fixture()
		_group("hand_wheel").erase(added)
		_expect("E_MISSING", added, "a missing constant of the build's own (%s)" % added)
	_reset_fixture()
	_group("hand_wheel")["flick_max_time"] = "soon"
	_expect("E_TYPE", "flick_max_time", "a word where a time belongs")
	_reset_fixture()
	_group("hand_wheel")["hand_free_bounds_max"] = [1.0]
	_expect("E_RANGE", "hand_free_bounds_max", "a corner with one number")

	# A control the car always has, and the code names, cannot go missing.
	_reset_fixture()
	_list("anchors", "anchors").erase(_record("anchors", "window_crank"))
	_expect("E_MISSING", "anchors[window_crank]", "a control of GDD 4.6 that is missing")

	_reset_fixture()
	_group("car")["lane_width"] = "wide"
	_expect("E_TYPE", "lane_width", "a string where a number belongs")

	_reset_fixture()
	_group("car_cash_clock_law")["clock_start"] = "25:99"
	_expect("E_TYPE", "clock_start", "an impossible clock time")

	_reset_fixture()
	_group("nerves")["nerves_start"] = 130
	_expect("E_RANGE", "nerves_start", "Nerves outside 0 to 100")

	_reset_fixture()
	_group("structure")["rarity_by_act"] = [[60, 30, 20], [52, 33, 15], [45, 35, 20]]
	_expect("E_RULE", "rarity_by_act[0]", "rarity shares that do not add up to 100")

	_reset_fixture()
	_group("structure")["stop_minutes"] = {"fuel": 10, "fitter": 15, "tea": 20, "find": 5, "hitcher": 2}
	_expect("E_MISSING", "stop_minutes.shady", "a stop with no minutes")

	_reset_fixture()
	_group("car")["hand_speed"] = 2.0
	_expect("E_TUNING", "hand_speed", "one constant defined in two groups")

	_reset_fixture()
	var tuning_root: Dictionary = _roots["tuning"]
	var units: Dictionary = tuning_root["_units"]
	units["hand_sped"] = "m/s"
	_expect("E_REF", "_units.hand_sped", "a unit for a constant that does not exist")

	_reset_fixture()
	_group("car")["extra_blob"] = {"deep": {"deeper": {"deepest": {"too": {"deep": null}}}}}
	_expect("E_TYPE", "extra_blob", "an extra constant that is not plain data")

	# Anchors
	_reset_fixture()
	var anchors_root: Dictionary = _roots["anchors"]
	var points: Dictionary = anchors_root["points"]
	points.erase("W")
	_expect("E_MISSING", "points.W", "a missing cabin point")

	_reset_fixture()
	_record("anchors", "horn")["pos"] = [0.0, 0.0]
	_expect("E_TYPE", "anchors[horn].pos", "a position that is not [x, y, z]")

	_reset_fixture()
	_record("anchors", "horn").erase("time_s")
	_expect("E_MISSING", "anchors[horn].time_s", "an anchor with no expected travel time")

	_reset_fixture()
	_list("anchors", "anchors").append({"id": "horn", "pos": [0, 0, 0], "time_s": 0.13})
	_expect("E_DUP_ID", "anchors[horn]", "a duplicate anchor id")

	# Lines
	_reset_fixture()
	var arabic: Dictionary = _lines["ar"]
	arabic.erase("narrator.start")
	_expect("E_LINES", "narrator.start", "a line missing from lines_ar.csv")

	_reset_fixture()
	arabic = _lines["ar"]
	arabic["only.in.arabic"] = {"speaker": "", "text": "", "needs_writer": true}
	_expect("E_LINES", "only.in.arabic", "a line that exists only in lines_ar.csv")

	_reset_fixture()
	var english: Dictionary = _lines["en"]
	english["narrator.start"] = {"speaker": "Abu Noor", "text": "  ", "needs_writer": true}
	_expect("E_LINES", "narrator.start", "an English line with no text")

	_reset_fixture()
	_add_line("Bad Id", "text")
	_expect("E_ID", "Bad Id", "a line id that is not dotted lower case")

	# Whoever speaks needs a line for their name (the subtitles' speaker tag).
	_reset_fixture()
	english = _lines["en"]
	english["narrator.start"] = {"speaker": "Tea Seller", "text": "Tea?", "needs_writer": true}
	_expect("E_REF", "speaker.tea_seller", "a speaker with no line for the name")
	_reset_fixture()
	english = _lines["en"]
	english["narrator.start"] = {"speaker": "Abu Noor, then Tea Seller", "text": "Tea. / Tea?", "needs_writer": true}
	_expect("E_REF", "speaker.tea_seller", "the second speaker of an exchange with no line for the name")
	_reset_fixture()
	english = _lines["en"]
	english["narrator.start"] = {"speaker": "Abu Noor, then Noor", "text": "So. / Baba.", "needs_writer": true}
	check(_validate().is_empty(), "an exchange between speakers who have their lines validates: %s" % _first(_validate()))
	check_eq(GameData.speaker_line_id("Old woman"), "speaker.old_woman", "a speaker's line is `speaker.` and the name in lower case with underscores")
	check_eq(GameData.speaker_line_id("أبو نور"), "", "a name with no Latin letter has no such line (it is shown as written)")

	# A whole file gone.
	_reset_fixture()
	_roots.erase("legs")
	_expect("E_FILE", "legs.json", "a data file that was never loaded")

	_reset_fixture()
	var beats_root: Dictionary = _roots["beats"]
	beats_root.erase("vehicles")
	_expect("E_MISSING", "vehicles", "a record list missing from its file")


func _check_broken_files() -> void:
	var dir_path: String = ProjectSettings.globalize_path(BROKEN_DIR)
	DirAccess.make_dir_recursive_absolute(dir_path)
	_write(BROKEN_DIR.path_join("tuning.json"), "{ \"hand_wheel\": { \"hand_speed\": 1.5 ")
	_write(BROKEN_DIR.path_join("items.json"), "[1, 2, 3]")
	_write(BROKEN_DIR.path_join("lines_en.csv"), "key,en,ar\nnarrator.start,hello,\n")
	_write(BROKEN_DIR.path_join("lines_ar.csv"),
			"id,speaker,text,needs_writer\na.b,,,true\na.b,,,true\nc.d,,\ne.f,,,maybe\n")
	var broken: GameData = GameData.load_from(BROKEN_DIR)
	var errors: PackedStringArray = DataValidator.validate(broken)
	check(_has(errors, "E_JSON", "tuning.json"), "a JSON syntax error is reported with its file")
	check(_has(errors, "E_JSON", "items.json"), "a JSON file whose top level is not an object is reported")
	check(_has(errors, "E_FILE", "rituals.json"), "a missing JSON file is reported")
	check(_has(errors, "E_LINES", "lines_en.csv"), "a line file with the wrong header is reported")
	check(_has(errors, "E_DUP_ID", "a.b"), "a duplicate line id is reported")
	check(_has(errors, "E_LINES", "lines_ar.csv:4"), "a line row with too few columns is reported")
	check(_has(errors, "E_LINES", "lines_ar.csv:5"), "a needs_writer that is not true or false is reported")
	Smoke.clean_test_user_root()


# --- Helpers ------------------------------------------------------------------

func _validate() -> PackedStringArray:
	return DataValidator.validate(GameData.from_parts(_roots, _lines))


## Validates the current fixture and checks one error with this code and place.
func _expect(code: String, where: String, what: String) -> void:
	var errors: PackedStringArray = _validate()
	check(_has(errors, code, where), "%s is reported as %s at %s; got: %s" % [what, code, where, _first(errors)])


func _has(errors: PackedStringArray, code: String, where: String) -> bool:
	for message: String in errors:
		if message.begins_with("[%s]" % code) and message.contains(where):
			return true
	return false


func _first(errors: PackedStringArray) -> String:
	if errors.is_empty():
		return "(none)"
	return "%s (%d in all)" % [errors[0], errors.size()]


func _parse(json_text: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(json_text)
	if parsed is Dictionary:
		return parsed
	fail("fixture JSON does not parse: %s" % json_text.substr(0, 40))
	return {}


## Adds a record to the fixture, replacing any shipped record with the same id
## (the shipped data grows toward the GDD's examples; the fixture stays exact).
func _put(set_name: String, record: Dictionary) -> void:
	var where: Array = GameData.RECORD_SETS[set_name]
	var file: String = where[0]
	var key: String = where[1]
	var list: Array = _list(file, key)
	for index: int in range(list.size() - 1, -1, -1):
		var existing: Dictionary = list[index]
		if existing.get("id") == record.get("id"):
			list.remove_at(index)
	list.append(record)


func _list(file: String, key: String) -> Array:
	var root: Dictionary = _roots[file]
	var list: Array = root[key]
	return list


func _record(set_name: String, id: String) -> Dictionary:
	var where: Array = GameData.RECORD_SETS[set_name]
	var file: String = where[0]
	var key: String = where[1]
	for entry: Variant in _list(file, key):
		var record: Dictionary = entry
		if record.get("id") == id:
			return record
	fail("fixture has no %s record '%s'" % [set_name, id])
	return {}


func items_root_for_test() -> Dictionary:
	var root: Dictionary = _roots["items"]
	return root


func _registry_entry(file: String, id: String) -> Dictionary:
	var root: Dictionary = _roots[file]
	var entry: Dictionary = root[id]
	return entry


func _group(group_name: String) -> Dictionary:
	var root: Dictionary = _roots["tuning"]
	var group: Dictionary = root[group_name]
	return group


func _add_line(id: String, text: String) -> void:
	var english: Dictionary = _lines["en"]
	var arabic: Dictionary = _lines["ar"]
	english[id] = {"speaker": "", "text": text, "needs_writer": true}
	arabic[id] = {"speaker": "", "text": "", "needs_writer": true}


func _write(path: String, text: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		fail("cannot write %s" % path)
		return
	file.store_string(text)
