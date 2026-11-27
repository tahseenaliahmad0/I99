class_name TableRules
extends RefCounted
## The rules of one Table (GDD 11.2), read once from its record in
## tables.json. "Each Table is its own ruleset on top of the base game.
## Rules do not stack from Table to Table." A Table the data does not have
## (a road driven by itself, an old save) has the base rules.
##
## What a record's "rules" may say:
##   price_mult                 every price at a stop times this
##   free_rewinds               Wrecks that return him to the start of the leg
##                              or boss he is on, instead of to Baghdad
##   patrol_every_act           one leg of every act is a Patrol leg
##   checkpoint_suspicion_mult  what Suspicion gains at the Checkpoint times this
##   no_contraband              no stop holds out contraband, or refills it
##   no_deals                   the shady guy is never there
##   no_bribes                  neither officer nor soldier takes banknotes
##   snap_minutes               game minutes each Snap costs
##   heavy_floor_add            added to the Heavy floor all night
##   start_items                items the cabin starts with besides its own
##   full_supplies              items of the starting cabin that start full
##   boss_alone_nerves          Nerves added when a boss begins with nobody
##                              in the seat
##   seed                       the Telling's seed, whatever is asked for:
##                              the road is fixed
##   road                       the leg of each act's three places, in order:
##                              there are no forks
##   stops                      the stop at the end of each of those legs
##   services                   the only services a stop gives (its stock is
##                              not held out); a boss stop offers these alone
##   hitchers                   who waits where: { act, stop (1 to 3), passenger };
##                              nobody else stands anywhere

const UNLOCK_START: String = "start"
const UNLOCK_WIN: String = "win:"
const NO_SEED: int = -1

var id: String = ""
## Game minutes after 22:00 at which he leaves Baghdad.
var depart_min: float = 0.0
var price_mult: float = 1.0
var free_rewinds: int = 0
var patrol_every_act: bool = false
var checkpoint_suspicion_mult: float = 1.0
var no_contraband: bool = false
var no_deals: bool = false
var no_bribes: bool = false
var snap_minutes: float = 0.0
var heavy_floor_add: float = 0.0
var start_items: PackedStringArray = []
var full_supplies: PackedStringArray = []
var boss_alone_nerves: float = 0.0
var seed: int = NO_SEED
## [act - 1][leg index] -> leg id; empty when the road forks as usual.
var road: Array[PackedStringArray] = []
var stops: Array[PackedStringArray] = []
## Empty: every service, and every stop's stock.
var services: PackedStringArray = []
var hitchers: Array[Dictionary] = []
## Heckle type -> weight (GDD 11.3); empty: nobody heckles.
var heckle_weights: Dictionary = {}


static func of(data: GameData, table_id: String) -> TableRules:
	var out: TableRules = TableRules.new()
	out.id = table_id
	if table_id.is_empty() or not data.has_record("tables", table_id):
		return out
	var record: Dictionary = data.record("tables", table_id)
	out.depart_min = GameData.as_float(record.get("depart_min"))
	out.heckle_weights = GameData.as_dict(record.get("heckle_weights")).duplicate()
	var rules: Dictionary = GameData.as_dict(record.get("rules"))
	out.price_mult = GameData.as_float(rules.get("price_mult"), 1.0)
	out.free_rewinds = GameData.as_int(rules.get("free_rewinds"))
	out.patrol_every_act = GameData.as_bool(rules.get("patrol_every_act"))
	out.checkpoint_suspicion_mult = GameData.as_float(rules.get("checkpoint_suspicion_mult"), 1.0)
	out.no_contraband = GameData.as_bool(rules.get("no_contraband"))
	out.no_deals = GameData.as_bool(rules.get("no_deals"))
	out.no_bribes = GameData.as_bool(rules.get("no_bribes"))
	out.snap_minutes = GameData.as_float(rules.get("snap_minutes"))
	out.heavy_floor_add = GameData.as_float(rules.get("heavy_floor_add"))
	out.boss_alone_nerves = GameData.as_float(rules.get("boss_alone_nerves"))
	out.seed = GameData.as_int(rules.get("seed"), NO_SEED)
	out.start_items = _strings(rules.get("start_items"))
	out.full_supplies = _strings(rules.get("full_supplies"))
	out.services = _strings(rules.get("services"))
	for act_legs: Variant in GameData.as_array(rules.get("road")):
		out.road.append(_strings(act_legs))
	for act_stops: Variant in GameData.as_array(rules.get("stops")):
		out.stops.append(_strings(act_stops))
	for entry: Variant in GameData.as_array(rules.get("hitchers")):
		out.hitchers.append(GameData.as_dict(entry))
	return out


## The road is one fixed course (Noor's): no forks.
func fixed_road() -> bool:
	return not road.is_empty()


## The leg at place `leg_index` (0 to 2) of `act` on a fixed road, or "".
func leg_at(act: int, leg_index: int) -> String:
	if act < 1 or act > road.size() or leg_index < 0 or leg_index >= road[act - 1].size():
		return ""
	return road[act - 1][leg_index]


## The stop at the end of that leg on a fixed road, or "".
func stop_at(act: int, leg_index: int) -> String:
	if act < 1 or act > stops.size() or leg_index < 0 or leg_index >= stops[act - 1].size():
		return ""
	return stops[act - 1][leg_index]


## Whether a stop gives this service at this Table.
func allows_service(service: String) -> bool:
	return services.is_empty() or services.has(service)


## A stop's stock is held out (not at a Table that names its services).
func stock_offered() -> bool:
	return services.is_empty()


## The shady guy may join a stop: not where there are no Deals, nor where
## nothing is sold at all.
func deals_offered() -> bool:
	return not no_deals and stock_offered()


## Who this Table has waiting at the stop after leg `leg_index` (0 to 2) of
## `act` ("" for nobody), and whether the Table says who waits at all.
func places_hitchers() -> bool:
	return not hitchers.is_empty() or fixed_road()


func hitcher_at(act: int, leg_index: int) -> String:
	for entry: Dictionary in hitchers:
		if GameData.as_int(entry.get("act")) == act and GameData.as_int(entry.get("stop")) == leg_index + 1:
			return GameData.as_string(entry.get("passenger"))
	return ""


## The heckle types this Table's guests use, in the order of its record.
func heckle_types() -> PackedStringArray:
	var out: PackedStringArray = []
	for key: Variant in heckle_weights:
		if GameData.as_float(heckle_weights[key]) > 0.0:
			out.append(str(key))
	return out


## Whether `profile` (GDD 13.7) has this Table open.
static func unlocked(profile: Dictionary, table_id: String) -> bool:
	return GameData.as_array(profile.get("tables_unlocked")).has(table_id)


## The Tables that winning `table_id` on time opens (GDD 11.2: "a Table
## unlocks by winning the one before it on time").
static func opened_by(data: GameData, table_id: String) -> PackedStringArray:
	var out: PackedStringArray = []
	for table: Dictionary in data.records("tables"):
		if GameData.as_string(table.get("unlock")) == UNLOCK_WIN + table_id:
			out.append(GameData.as_string(table.get("id")))
	return out


## He won `table_id` on time: the Tables that opens are added to `profile`
## (GDD 11.2, 11.5). Returns the ones that were not open before.
static func win(data: GameData, profile: Dictionary, table_id: String) -> PackedStringArray:
	var opened: PackedStringArray = []
	var open: Array = GameData.as_array(profile.get("tables_unlocked")).duplicate()
	for next: String in opened_by(data, table_id):
		if not open.has(next):
			open.append(next)
			opened.append(next)
	profile["tables_unlocked"] = open
	return opened


## The Tables open from the start.
static func open_at_start(data: GameData) -> PackedStringArray:
	var out: PackedStringArray = []
	for table: Dictionary in data.records("tables"):
		if GameData.as_string(table.get("unlock")) == UNLOCK_START:
			out.append(GameData.as_string(table.get("id")))
	return out


static func _strings(value: Variant) -> PackedStringArray:
	var out: PackedStringArray = []
	for entry: Variant in GameData.as_array(value):
		out.append(GameData.as_string(entry))
	return out
