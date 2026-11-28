class_name ItemSim
extends RefCounted
## The cabin (GDD 4.6, 6.2, 7): what sits in each slot, which ritual each
## anchor offers right now, and what a completed ritual does.
##
## Items are data (items.json). A ritual's `on_complete` list is run here, one
## op at a time: "nerves:12", "add_effect:awake:20", "consume_supply", "give",
## "toggle:hazards", and the controls' own ops ("horn", "wipe", "photo",
## "indicate", "window", "ash", "radio_step"). Items never change other
## systems directly beyond that: they add, remove or query statuses in the
## EffectSystem and emit resource changes (GDD 13.3).
##
## What an item gives and takes (GDD 7.2) is a list of entries, each one of:
##   {"effect": id, "duration": s}            on use: a timed status
##   {"resource": "nerves"|"cash", "amount": n, "over": s}
##                                            on use: at once, or spread over s
##   {"effect": id, "for": "leg"}             on use: a status held to the leg's end
##   {"effect": id}                           a status held on while it is there
##   {"resource": "nerves", "per_s": r}       Nerves by the second while it is there
##   {"effect": "haze_rate", "amount": r}     haze by the second while it is there
##   {"passive": key, "amount": n}            a standing change to the car or the
##                                            cabin while it is there (see PASSIVES)
## each with an optional "while" condition. A resource entry may name a
## "synergy" rule: when that synergy's partner is there, its amount is used.

const SLOT_ANCHOR: String = "@slot"
## Salt of the wiper's draws (D-074).
const WIPER_SALT: int = 8841
## horn_lane_for: the horn does not move this vehicle.
const NO_LANE: int = -1
## A DRAG_TO's destination: any free slot the thing carried fits in.
const HOME_ANCHOR: String = "@home"
## Slots whose id begins so are cells of the glovebox: what is in one is
## stowed, out of sight and out of use (GDD 7.1, 10.2).
const GLOVEBOX: String = "glovebox"
const FLAG_GLOVEBOX: StringName = &"glovebox_open"
const UNSTOW: String = "unstow"
## The seat, and where what lies on it goes while a passenger sits there
## (GDD 8.1): the back seat, out of reach and out of use.
const SEAT: StringName = &"seat"
const BACK_SEAT: StringName = &"back_seat"
## What a smoke is tagged, and where one handed to him burns (GDD 8.2).
const TAG_SMOKE: String = "smoke"
## What the tea is tagged (a tea stall fills it; the Drummer passes it, GDD 8.2).
const TAG_TEA: String = "tea"
const STATIC: StringName = &"static"
const AWAKE: StringName = &"awake"
const VISOR_DOWN: StringName = &"visor_down"
const HAZE_RATE: String = "haze_rate"
const FLAG_WINDOW: StringName = &"window_open"
const MUSIC: StringName = &"music"
const COURAGE: StringName = &"courage"
const CHEWING: StringName = &"chewing"
## The hook on the wheel ring (GDD 7.6): hung in the ring and waiting for him
## to let go, holding the wheel, and out again for a while.
const HOOK_ARMED: StringName = &"hook_armed"
const HOOK_SET: StringName = &"hook_set"
const HOOK_COOLDOWN: StringName = &"hook_cooldown"
const HOOK: StringName = &"hook"
## Synergy partners that are not items (GDD 7.8).
const TOKEN_MUSIC: String = "music"
const TOKEN_PHOTO: String = "photo"
## What an item that plays in the deck is tagged (the mixtape).
const TAG_TAPE: String = "tape"
## Who holds a status that lasts for the rest of the leg.
const LEG: StringName = &"leg"
## What an item that takes calls is tagged.
const TAG_PHONE: String = "phone"
const CALLER_DISPATCHER: StringName = &"dispatcher"
const CALLER_FAMILY: StringName = &"um_noor"
## The synergy rules the simulation knows (GDD 7.8).
const SYNERGY_RULES: PackedStringArray = [
	"sip_extends_burn", "no_smoke_haze", "bead_calm", "photo_sobers", "numb_courage",
	"hook_holds_lane", "calls_in_a_row", "chewing_keeps_warm", "auto_indicate",
]
## The standing changes an item may make ("passive" entries) and how those of
## several items combine: true for a multiplier, false for an amount added.
const PASSIVES: Dictionary = {
	"call_gap_mult": true,
	"call_cash_bonus": false,
	"first_scrape_free": false,
	"haze_clear_mult": true,
	"self_repair_s": false,
	"close_call_bonus": false,
	"glare_mult": true,
	"night_darker": false,
	# Adaptations (GDD 7.6).
	"turn_rate_mult": true,
	"return_rate_mult": true,
	"hook_lock_s": false,
	"hook_cooldown_s": false,
	"wheel_keys": false,
	"fifth_gear": false,
	"horn_yields_all": false,
	"horn_nerves_more": false,
	"horn_suspicion_more": false,
	"lamp_capacity": false,
	"lat_speed_mult": true,
	"visibility_mult": true,
	"flash_back_nerves": false,
	"mirror_lead_s": false,
	"mirror_scale": true,
	# Deals (GDD 7.7).
	"suspicion_gain_mult": true,
	"close_call_mult": true,
	"high_gear_bonus": false,
	"brake_mult": true,
	"courage_cap_more": false,
	"lag_sources": false,
}

## One thing in the cabin.
class Item:
	extends RefCounted
	var id: StringName = &""
	var record: Dictionary = {}
	var slot: StringName = &""
	## Uses left; -1 for things that are never used up.
	var supply: int = -1
	## Seconds a drink stays hot.
	var hot_left: float = 0.0
	## A smoke: seconds this one has burned, and whether it was ashed.
	var burning: bool = false
	var burn_time: float = 0.0
	var ashed: bool = false
	## The ash of this one fell before he ashed it.
	var ash_fell: bool = false
	## Seconds until neglect bites (GDD 7.2, Lapse); negative when not armed.
	var lapse_left: float = -1.0
	## The status this item's use switches on ("lit"), if any.
	var use_effect: StringName = &""
	## A tape (it has a "side_s"): seconds it has played since it was last flipped.
	var is_tape: bool = false
	var side_time: float = 0.0
	## Its smoke makes no haze (GDD 7.8: an air freshener hangs in the car).
	var smokeless: bool = false
	## It does not cool while he chews (GDD 7.8: seeds and the tea).
	var warm_while_chewing: bool = false
	## What it does by the second while it is in the cabin.
	var standing: Array[Standing] = []
	## What the tick needs of its record, read once when it is put in the
	## cabin: the time by which a smoke must be ashed (0: nothing to ash), the
	## length of a tape's side (INF: no tape), whether it burns down when used
	## (it has an ash time and a status of its own), whether it takes calls,
	## and its synergies as the record lists them.
	var ash_by: float = 0.0
	var side_s: float = INF
	var smokes: bool = false
	var is_phone: bool = false
	var synergies: Array = []


## One thing an item does all the time it is there (its condition allowing).
class Standing:
	extends RefCounted
	const HAZE: int = 0
	const NERVES: int = 1
	const STATUS: int = 2
	var kind: int = HAZE
	var amount: float = 0.0
	var effect: StringName = &""
	var condition: Condition = null
	## The status is being held on right now.
	var held: bool = false
	## Nerves by the second that are the calm of the item's music (see
	## ItemSim.music_rate): given under the condition under which the item
	## holds the status "music" on.
	var music: bool = false


## A condition of items.json or rituals.json, read once: an effect id,
## "supply>0", "hot", "playing", "warbling" or "flag:<switch>", each
## optionally negated with "!".
class Condition:
	extends RefCounted
	const EFFECT: int = 0
	const SUPPLY: int = 1
	const HOT: int = 2
	const FLAG: int = 3
	const PLAYING: int = 4
	const WARBLING: int = 5
	const RINGING: int = 6
	const TAG: int = 7
	const GLOVEBOX_ROOM: int = 8
	const STOWED: int = 9
	var negated: bool = false
	var word: int = EFFECT
	var name: StringName = &""

var items: Array[Item] = []
## Cabin switches: hazards, high_beam, window_open, glovebox_open.
var flags: Dictionary = {}
## Windscreen haze, 0 to haze_cap (GDD 5.8).
var haze: float = 0.0
## The radio: a station id, or "static".
var radio: StringName = STATIC
## Seconds since the last wiper sweep.
var since_wipe: float = 0.0
## How long the last sweep keeps the rain off the glass, and how many sweeps
## there have been (D-074: each lasts wiper_clear_time less or more by up to
## wiper_clear_spread, never the same beat twice running).
var wiper_clear_now: float = 0.0
var wipes: int = 0
## True while it rains (the leg says so): only then does the view blur.
var raining: bool = false
## Dust in the air (the leg says so): haze per second while the window is open.
var dust_rate: float = 0.0
## Dust on the glass (the road says so): the share of the windscreen that one
## sweep of the wipers smears.
var wipe_haze: float = 0.0
## -1 signalling left, +1 right, 0 off.
var indicator: int = 0
var indicator_left: float = 0.0
## The visor photo calms once per leg.
var photo_used: bool = false
## True for the tick in which the horn was blown.
var horn_blown: bool = false
## Cash earned or spent by ops this tick.
var cash_delta: float = 0.0
## What he handed to the officer this tick: &"fine" (his licence) or
## &"bribe" (banknotes), else empty.
var paid: StringName = &""
## How he took the Call this tick (GDD 10.4): &"alone" (a TAP on his
## pocket) or &"passenger" (the phone handed to them), else empty.
var call_taken: StringName = &""
## He turned the key this tick (GDD 10.5).
var key_turned: bool = false
## What he handed out through the driver's window this tick (GDD 10.2):
## &"licence", &"id", &"registration" or &"banknotes", else empty.
var handed: StringName = &""
## True for the tick in which contraband, or the phone, was used.
var contraband_used: bool = false
var phone_used: bool = false
## He tapped his passenger's shoulder this tick (GDD 8.1).
var asked: bool = false
## The tags of the things he used this tick (a cigarette lit, a sip taken):
## for whoever in the seat minds (GDD 8.2).
var used_tags: PackedStringArray = PackedStringArray()
## Somebody sits in the seat: nothing else can lie there.
var seat_occupied: bool = false
## His passenger answers every call for him (GDD 8.2, the Student).
var answered_for_him: bool = false
## Who called, in the tick his passenger took the call for him; else empty.
var taken_for_him: StringName = &""
## What the music out of the dash does to his Nerves this tick, by the second
## (GDD 6.1): the radio's or a tape's, after an open window; 0 when neither
## plays. Music is music once: whoever else makes music (a drum, GDD 8.2)
## gives only what theirs is stronger by.
var music_rate: float = 0.0
## sfx and line requests, drained by DriveSim.
var events: Array[Dictionary] = []

## The phone (GDD 7.4): who is calling ("" while it is silent), how long it
## will go on ringing, and how many of the TAPs that answer it are made.
var caller: StringName = &""
var ring_left: float = 0.0
var call_taps: int = 0
## Calls so far this Telling (every fourth is Um Noor) and calls answered
## in a row.
var calls: int = 0
var answered_run: int = 0
## The leg's first scrape is behind him: the one the charm turns aside (GDD
## 7.5). It is marked with or without a charm, so that one hung up later in
## the leg does not take the next scrape for the first.
var scrape_spared: bool = false
## The act's first fault is behind him: the one the duct tape takes hold of
## (GDD 7.5), marked with or without the tape for the same reason. Then the
## fault the tape is holding now and how long until that fault is mended
## ("" and 0 when it holds none).
var tape_spent: bool = false
var mending: StringName = &""
var mend_left: float = 0.0

var _data: GameData
var _effects: EffectSystem
var _nerves: NervesSim
var _traffic: TrafficSim
var _car: CarSim
var _faults: FaultSim
var _rng: Rng

## anchor id -> Array of control rituals (no owning item) offered there.
var _controls: Dictionary = {}
## anchor id -> Array of rituals an item has at a place of their own, not at
## its slot (the painkillers are taken at his face).
var _placed: Dictionary = {}
## Statuses held until the leg ends.
var _leg_holds: Array[StringName] = []
## Standing changes of what is in the cabin, combined: key -> value.
var _passives: Dictionary = {}
## Read from the cabin whenever it changes (_refresh_passives), for the tick:
## the first thing that takes calls, the first tape, whether anything is kept
## warm by chewing, and the standing change to how fast the haze clears.
var _phone: Item = null
var _tape: Item = null
var _keeps_warm: bool = false
var _haze_clear_mult: float = 1.0
## Counts every change to what is in the cabin, so that who reads the
## standing changes knows when to read them again.
var cabin_serial: int = 0
## Seconds until the phone rings next; negative until it is drawn.
var _call_wait: float = -1.0
## anchor id -> the anchor that takes its place while something sits there
## (anchors.json "over": the tape deck is the radio).
var _covered_by: Dictionary = {}
## condition text -> Condition.
var _conditions: Dictionary = {}
## slot id -> anchor id ("" for slots with no anchor).
var _slot_anchor: Dictionary = {}
var _stations: Array[StringName] = []
var _radio_index: int = -1
var _radio_time: float = 0.0
## The station the radio is holding on as a status, or static.
var _radio_held: StringName = STATIC
var _horn_cooldown: float = 0.0
## Nerves that come spread over a time (a cigarette's calm): for each drip its
## rate per second and the seconds it has left. (64-bit: in a Vector2's 32
## bits a countdown of a minute is a tick out by its end.)
var _drip_rates: PackedFloat64Array = PackedFloat64Array()
var _drip_left: PackedFloat64Array = PackedFloat64Array()

var _haze_cap: float = 0.0
var _haze_clear: float = 0.0
var _window_haze_mult: float = 1.0
var _window_radio_mult: float = 1.0
var _horn_range: float = 0.0
var _horn_yield_time: float = 0.0
var _horn_nerves: float = 0.0
var _horn_cooldown_s: float = 0.0
var _horn_clearance: float = 0.0
var _wiper_clear: float = 0.0
var _wiper_spread: float = 0.0
var _wiper_power: float = 1.0
var _indicator_time: float = 0.0
var _visor_time: float = 0.0
var _visor_nerves: float = 0.0
var _window_awake: float = 0.0
var _radio_drift: float = 0.0
var _radio_music_rate: float = 0.0
var _radio_news_rate: float = 0.0
var _car_half_length: float = 0.0


func configure(data: GameData, effects: EffectSystem, nerves: NervesSim, traffic: TrafficSim,
		car: CarSim, faults: FaultSim, rng: Rng) -> void:
	_data = data
	_effects = effects
	_nerves = nerves
	_traffic = traffic
	_car = car
	_faults = faults
	_rng = rng
	var tuning: Tuning = data.tuning
	_haze_cap = tuning.f("haze_cap")
	_haze_clear = tuning.f("haze_clear_rate")
	_window_haze_mult = tuning.f("window_haze_clear_mult")
	_window_radio_mult = tuning.f("window_radio_mult")
	_horn_range = tuning.f("horn_range")
	_horn_yield_time = tuning.f("horn_yield_time")
	_horn_nerves = tuning.f("horn_nerves")
	_horn_cooldown_s = tuning.f("horn_cooldown")
	_horn_clearance = tuning.f("traffic_follow_gap")
	_wiper_clear = tuning.f("wiper_clear_time")
	_wiper_spread = tuning.f("wiper_clear_spread")
	_wiper_power = tuning.f("wiper_blur_power")
	wiper_clear_now = _wiper_clear
	_indicator_time = tuning.f("indicator_time")
	_visor_time = tuning.f("visor_time")
	_visor_nerves = tuning.f("visor_nerves")
	_window_awake = tuning.f("window_awake")
	_radio_drift = tuning.f("radio_drift_time")
	_radio_music_rate = tuning.f("radio_music_rate")
	_radio_news_rate = tuning.f("radio_news_rate")
	_car_half_length = tuning.f("car_length") * 0.5
	_stations.clear()
	for station: Variant in tuning.a("radio_stations"):
		_stations.append(StringName(GameData.as_string(station)))

	_controls.clear()
	_placed.clear()
	for ritual: Dictionary in data.records("rituals"):
		var anchor: String = GameData.as_string(ritual.get("anchor"))
		if anchor == SLOT_ANCHOR:
			continue
		var at_anchor: Dictionary = _placed if ritual.has("item") else _controls
		var offered: Array = at_anchor.get(anchor, [])
		offered.append(ritual)
		at_anchor[anchor] = offered
	_slot_anchor.clear()
	for slot: Dictionary in data.records("slots"):
		_slot_anchor[GameData.as_string(slot.get("id"))] = GameData.as_string(slot.get("anchor"))
	_covered_by.clear()
	for anchor: Dictionary in data.records("anchors"):
		if anchor.has("over"):
			_covered_by[GameData.as_string(anchor.get("over"))] = GameData.as_string(anchor.get("id"))
	_conditions.clear()
	reset_cabin()


## The starting cabin of GDD 7.3 (items.json "starting_cabin").
func reset_cabin() -> void:
	items.clear()
	flags.clear()
	haze = 0.0
	radio = STATIC
	_radio_index = -1
	_radio_time = 0.0
	_radio_held = STATIC
	since_wipe = 0.0
	wipes = 0
	_draw_wiper_clear()
	indicator = 0
	indicator_left = 0.0
	photo_used = false
	horn_blown = false
	cash_delta = 0.0
	_horn_cooldown = 0.0
	_drip_rates.clear()
	_drip_left.clear()
	_leg_holds.clear()
	events.clear()
	_hang_up()
	calls = 0
	answered_run = 0
	scrape_spared = false
	tape_spent = false
	mending = &""
	mend_left = 0.0
	_refresh_passives()
	for entry: Variant in GameData.as_array(_data.root("items").get("starting_cabin")):
		var start: Dictionary = GameData.as_dict(entry)
		add_item(StringName(GameData.as_string(start.get("item"))), StringName(GameData.as_string(start.get("slot"))),
				GameData.as_int(start.get("supply"), -1))


## The cabin of a Telling loaded from a save: nothing but what the save lists.
func empty_cabin() -> void:
	items.clear()
	flags.clear()
	_refresh_passives()


## Tunes the radio to a station (or to static) without the dial. What the
## station it leaves held on ends with it, as when the dial leaves it (GDD
## 6.2: static has no effect; the news keeps him awake "while tuned").
func set_radio(station: StringName) -> void:
	_radio_index = _stations.find(station)
	radio = station if _radio_index != -1 else STATIC
	if _radio_held != radio:
		_let_station_go()
	_radio_time = 0.0


## The status the radio's station held on is let go.
func _let_station_go() -> void:
	if _radio_held != STATIC:
		_effects.hold(_radio_held, &"radio", false)
	_radio_held = STATIC


## What is once per leg may be done again: a leg begins, or a boss does
## (and nothing else renews it: no stop, no road to a fork, no street).
func begin_leg() -> void:
	photo_used = false
	scrape_spared = false
	for held: StringName in _leg_holds:
		_effects.hold(held, LEG, false)
	_leg_holds.clear()


## What resets when a new act begins.
func begin_act() -> void:
	tape_spent = false


## What of this leg a stop must not forget (the save holds it): the photo
## was looked at, the leg's first scrape is behind him, and the statuses
## that last to the leg's end.
func leg_state() -> Dictionary:
	var held: Array = []
	for status: StringName in _leg_holds:
		held.append(String(status))
	return {"photo": photo_used, "spared": scrape_spared, "held": held}


## True for a status the leg holds to its end: it passes through a stop.
func held_for_leg(status: StringName) -> bool:
	return _leg_holds.has(status)


## What of this Telling a stop must not forget: how many calls there have
## been, how many were answered in a row and how long the wait for the next
## one still is (its exact bits; negative while it is not drawn); and that
## the act's first fault is behind him.
func telling_state() -> Dictionary:
	return {"calls": calls, "answered_run": answered_run, "call_wait": Save.exact(_call_wait), "tape_spent": tape_spent}


func set_telling_state(state: Dictionary) -> void:
	calls = GameData.as_int(state.get("calls"))
	answered_run = GameData.as_int(state.get("answered_run"))
	_call_wait = Save.from_exact(state.get("call_wait"), -1.0)
	tape_spent = GameData.as_bool(state.get("tape_spent"))


func set_leg_state(state: Dictionary) -> void:
	photo_used = GameData.as_bool(state.get("photo"))
	scrape_spared = GameData.as_bool(state.get("spared"))
	for status: Variant in GameData.as_array(state.get("held")):
		var id: StringName = StringName(GameData.as_string(status))
		if not _leg_holds.has(id):
			_leg_holds.append(id)
			_effects.hold(id, LEG, true)


func begin_tick() -> void:
	horn_blown = false
	cash_delta = 0.0
	paid = &""
	call_taken = &""
	key_turned = false
	handed = &""
	contraband_used = false
	phone_used = false
	asked = false
	taken_for_him = &""
	used_tags.clear()


# --- Items and slots ---------------------------------------------------------

## Puts an item in a slot. `supply` -1 means a full supply.
func add_item(id: StringName, slot: StringName, supply: int = -1) -> Item:
	if not _data.has_record("items", String(id)):
		push_error("ItemSim: unknown item '%s'" % id)
		return null
	var record: Dictionary = _data.record("items", String(id))
	var item: Item = Item.new()
	item.id = id
	item.record = record
	# With somebody in the seat, what belongs on it goes behind it.
	item.slot = BACK_SEAT if slot == SEAT and seat_occupied else slot
	var supply_spec: Dictionary = GameData.as_dict(record.get("supply"))
	if supply_spec.has("uses"):
		item.supply = supply if supply >= 0 else GameData.as_int(supply_spec.get("uses"))
	item.hot_left = _param(item, "hot_for_s", 0.0)
	item.is_tape = _param(item, "side_s", 0.0) > 0.0
	item.side_s = _param(item, "side_s", INF)
	item.ash_by = _param(item, "ash_by_s", 0.0)
	item.is_phone = GameData.as_array(record.get("tags")).has(TAG_PHONE)
	item.synergies = GameData.as_array(record.get("synergies"))
	for give: Variant in GameData.as_array(record.get("gives")):
		var entry: Dictionary = GameData.as_dict(give)
		if entry.has("effect") and entry.has("duration") and item.use_effect == &"" and not entry.has("while"):
			item.use_effect = StringName(GameData.as_string(entry.get("effect")))
	item.smokes = not (item.ash_by <= 0.0 or item.use_effect == &"")
	for list: String in ["gives", "takes"]:
		for listed: Variant in GameData.as_array(record.get(list)):
			var standing: Standing = _standing_of(GameData.as_dict(listed))
			if standing != null:
				item.standing.append(standing)
	_mark_music(item)
	items.append(item)
	_refresh_passives()
	return item


func remove_item(item: Item) -> void:
	if item == null:
		return
	# What it was doing stops with it: a smoke goes out, a tape falls silent.
	_put_out(item)
	items.erase(item)
	_refresh_passives()


## What an item gives his Nerves by the second while it holds the status
## "music" on (a tape, while it plays) is that music's calm.
func _mark_music(item: Item) -> void:
	for holding: Standing in item.standing:
		if holding.kind != Standing.STATUS or holding.effect != MUSIC:
			continue
		for other: Standing in item.standing:
			if other.kind == Standing.NERVES and other.condition == holding.condition:
				other.music = true


## The entry of a "gives" or "takes" list that works all the time the item
## is there, or null for one that works when the item is used.
func _standing_of(entry: Dictionary) -> Standing:
	if entry.has("passive"):
		return null
	var standing: Standing = Standing.new()
	if GameData.as_string(entry.get("effect")) == HAZE_RATE:
		standing.kind = Standing.HAZE
		standing.amount = GameData.as_float(entry.get("amount"))
	elif entry.has("per_s"):
		standing.kind = Standing.NERVES
		standing.amount = GameData.as_float(entry.get("per_s"))
	elif entry.has("effect") and not entry.has("duration") and not entry.has("for"):
		standing.kind = Standing.STATUS
		standing.effect = StringName(GameData.as_string(entry.get("effect")))
	else:
		return null
	if entry.has("while"):
		standing.condition = _condition(GameData.as_string(entry.get("while")))
	return standing


func item(id: StringName) -> Item:
	for candidate: Item in items:
		if candidate.id == id:
			return candidate
	return null


## The things in the cabin that carry a tag ("tea", "smoke", "phone").
func tagged(tag: String) -> Array[Item]:
	var out: Array[Item] = []
	for candidate: Item in items:
		if GameData.as_array(candidate.record.get("tags")).has(tag):
			out.append(candidate)
	return out


## The first thing so tagged that stands where the hand can use it: in a
## slot that has an anchor, and not stowed in the glovebox. Null for none.
func in_reach(tag: String) -> Item:
	for candidate: Item in tagged(tag):
		if not is_stowed(candidate) and not anchor_of(candidate).is_empty():
			return candidate
	return null


func item_in_slot(slot: StringName) -> Item:
	for candidate: Item in items:
		if candidate.slot == slot:
			return candidate
	return null


func flag(flag_name: StringName) -> bool:
	return GameData.as_bool(flags.get(flag_name))


## A passenger takes the seat, or leaves it (GDD 8.1): what lay on it lies on
## the back seat while they ride, out of reach, and comes back after.
func seat_taken(on: bool) -> void:
	seat_occupied = on
	var from: StringName = SEAT if on else BACK_SEAT
	var to: StringName = BACK_SEAT if on else SEAT
	for candidate: Item in items:
		if candidate.slot == from and (on or item_in_slot(SEAT) == null):
			_put_out(candidate)
			candidate.slot = to
	_refresh_passives()


## His passenger lights a cigarette and hands it over (GDD 8.2): it burns
## where his own would, with nothing of his used and no ritual. False when
## one is burning already or there is nowhere for it.
func light_handed() -> bool:
	var smoke: Item = null
	for candidate: Item in tagged(TAG_SMOKE):
		if not is_stowed(candidate) and not anchor_of(candidate).is_empty():
			smoke = candidate
			break
	if smoke == null:
		return false
	if smoke.burning or (smoke.use_effect != &"" and _effects.has_own(smoke.use_effect)):
		return false
	_give(smoke)
	return true


## The anchor an item's rituals are performed at: its slot's anchor.
func anchor_of(item_instance: Item) -> String:
	return GameData.as_string(_slot_anchor.get(String(item_instance.slot)))


## The anchor of a slot ("" for a slot the hand cannot reach).
func anchor_of_slot(slot: String) -> String:
	return GameData.as_string(_slot_anchor.get(slot))


# --- The glovebox (GDD 7.1, 10.2) --------------------------------------------

func is_stowed(item_instance: Item) -> bool:
	return String(item_instance.slot).begins_with(GLOVEBOX)


## The first cell of the glovebox with nothing in it ("" when it is full).
func free_cell() -> String:
	for slot: Variant in _slot_anchor:
		var id: String = str(slot)
		if id.begins_with(GLOVEBOX) and item_in_slot(StringName(id)) == null:
			return id
	return ""


## The first stowed thing that has a free place of its own to go back to
## (null: nothing is stowed, or nothing stowed has room outside).
func stowed_with_a_home() -> Item:
	for candidate: Item in items:
		if is_stowed(candidate) and not _free_homes(candidate).is_empty():
			return candidate
	return null


## The anchors that thing may be put down on when it is taken out.
func unstow_destinations() -> Array[String]:
	var out: Array[String] = []
	var candidate: Item = stowed_with_a_home()
	if candidate == null:
		return out
	for slot: String in _free_homes(candidate):
		var anchor: String = anchor_of_slot(slot)
		if not anchor.is_empty() and not out.has(anchor):
			out.append(anchor)
	return out


## It was taken out of the glovebox and put down on `anchor`.
func unstow_to(anchor: String) -> bool:
	var candidate: Item = stowed_with_a_home()
	if candidate == null:
		return false
	for slot: String in _free_homes(candidate):
		if anchor_of_slot(slot) == anchor:
			candidate.slot = StringName(slot)
			_refresh_passives()
			return true
	return false


## The free slots outside the glovebox that an item fits in.
func _free_homes(item_instance: Item) -> Array[String]:
	var out: Array[String] = []
	for slot: Variant in GameData.as_array(item_instance.record.get("slots")):
		var id: String = GameData.as_string(slot)
		if not id.begins_with(GLOVEBOX) and item_in_slot(StringName(id)) == null:
			out.append(id)
	return out


## What an item was doing stops: a smoke goes out, a status it held is let go.
func _put_out(item_instance: Item) -> void:
	if item_instance.burning and item_instance.use_effect != &"" and _effects.has_own(item_instance.use_effect):
		_effects.remove(item_instance.use_effect)
	for standing: Standing in item_instance.standing:
		if standing.held:
			standing.held = false
			_effects.hold(standing.effect, item_instance.id, false)


## A full supply again; a drink is hot again.
func restock(item_instance: Item) -> void:
	var supply: Dictionary = GameData.as_dict(item_instance.record.get("supply"))
	if supply.has("uses"):
		item_instance.supply = GameData.as_int(supply.get("uses"))
	item_instance.hot_left = _param(item_instance, "hot_for_s", 0.0)


## True for a drink that was hot and no longer is: worth refilling though full.
func gone_cold(item_instance: Item) -> bool:
	return _param(item_instance, "hot_for_s", 0.0) > 0.0 and item_instance.hot_left <= 0.0


## True when something can be done at this anchor at all (a control, or an
## item sitting in a slot there). The hand only snaps to such anchors.
func anchor_in_use(anchor: String) -> bool:
	if _covered(anchor):
		return false
	for offered: Variant in GameData.as_array(_controls.get(anchor)):
		var control: Dictionary = offered
		if _requirements_hold(control, null):
			return true
	for candidate: Item in items:
		if anchor_of(candidate) == anchor:
			return true
	for offered: Variant in GameData.as_array(_placed.get(anchor)):
		var placed: Dictionary = offered
		if owner_of(placed) != null:
			return true
	return false


## True while another anchor stands in this one's place: something sits in
## the slot there (a tape in the deck covers the radio's dial).
func _covered(anchor: String) -> bool:
	if not _covered_by.has(anchor):
		return false
	var cover: String = GameData.as_string(_covered_by[anchor])
	for candidate: Item in items:
		if anchor_of(candidate) == cover:
			return true
	return false


# --- Rituals -----------------------------------------------------------------

## The ritual a press at this anchor would start now, or {} for none: the
## first one offered there whose conditions all hold (items before controls).
func ritual_at(anchor: String) -> Dictionary:
	# What must be done first (papers for the officer) comes before the items there.
	for offered: Variant in GameData.as_array(_controls.get(anchor)):
		var urgent: Dictionary = offered
		if GameData.as_bool(urgent.get("over_items")) and _requirements_hold(urgent, null):
			return urgent
	for candidate: Item in items:
		# What is stowed in the glovebox is out of use until it is taken out.
		if anchor_of(candidate) != anchor or is_stowed(candidate):
			continue
		for ritual_id: Variant in GameData.as_array(candidate.record.get("rituals")):
			var ritual: Dictionary = _data.record("rituals", GameData.as_string(ritual_id))
			if GameData.as_string(ritual.get("anchor")) == SLOT_ANCHOR and _requirements_hold(ritual, candidate):
				if ritual.has("item"):
					return ritual
				# A ritual several items share (stowing): this time it is this item's.
				var own: Dictionary = ritual.duplicate()
				own["item"] = String(candidate.id)
				return own
	for offered: Variant in GameData.as_array(_placed.get(anchor)):
		var placed: Dictionary = offered
		var owner: Item = owner_of(placed)
		if owner != null and _requirements_hold(placed, owner):
			return placed
	for offered: Variant in GameData.as_array(_controls.get(anchor)):
		var control: Dictionary = offered
		if _requirements_hold(control, null):
			return control
	return {}


## The control at this anchor that asks for `status` (what he may hand an
## officer asks for "pulled_over"), if its conditions hold now; {} for none.
func ritual_for(status: StringName, anchor: String) -> Dictionary:
	for offered: Variant in GameData.as_array(_controls.get(anchor)):
		var control: Dictionary = offered
		if GameData.as_array(control.get("requires")).has(String(status)) and _requirements_hold(control, null):
			return control
	return {}


## Where a HOLD or a DRAG_TO is offered, a control that is a TAP may be
## offered too (his face: the pills are a HOLD, a slap is a TAP; his pocket
## in the Call: the phone is handed to a passenger, or a TAP answers it). A
## press let go within a TAP's time, with the hand still there, is then that
## TAP. {} when `primary` is neither, or there is no such control.
func tap_alternative(anchor: String, primary: Dictionary) -> Dictionary:
	var gesture: String = GameData.as_string(primary.get("gesture"))
	if gesture != "HOLD" and gesture != "DRAG_TO":
		return {}
	for offered: Variant in GameData.as_array(_controls.get(anchor)):
		var control: Dictionary = offered
		if GameData.as_string(control.get("gesture")) == "TAP" and _requirements_hold(control, null):
			return control
	return {}


## The item a ritual belongs to, as it sits in the cabin now (null for controls).
func owner_of(ritual: Dictionary) -> Item:
	if not ritual.has("item"):
		return null
	return item(StringName(GameData.as_string(ritual.get("item"))))


## Runs a completed ritual. `direction` is the Gesture.DIR_* flag of a FLICK.
## What the ritual requires is asked again now that its gesture is done (the
## glass may have spilled during the HOLD, the phone rung out during the
## TAP): false, and nothing is done, when it no longer holds.
func complete(ritual: Dictionary, direction: int) -> bool:
	var owner: Item = owner_of(ritual)
	if ritual.has("item") and owner == null:
		# The thing it was to be done with is no longer in the cabin.
		return false
	if not _requirements_hold(ritual, owner):
		return false
	# A use is what gives the item's effect. Putting a thing away in the
	# glovebox, or taking it out, is none.
	var used: bool = owner != null and GameData.as_array(ritual.get("on_complete")).has("give")
	if owner != null:
		# Using contraband, or the phone, is something a police car sees (GDD 6.5).
		if used and GameData.as_bool(owner.record.get("contraband")):
			contraband_used = true
		# One use for a call, however many TAPs answer it.
		if GameData.as_array(owner.record.get("tags")).has(TAG_PHONE) and not dialling():
			phone_used = true
	for op: Variant in GameData.as_array(ritual.get("on_complete")):
		_run(GameData.as_string(op), owner, direction)
	if used:
		# What he has just used, by its tags.
		for tag: Variant in GameData.as_array(owner.record.get("tags")):
			if not used_tags.has(GameData.as_string(tag)):
				used_tags.append(GameData.as_string(tag))
	var sfx: String = GameData.as_string(ritual.get("sfx"))
	if not sfx.is_empty():
		events.append({"type": "sfx_requested", "id": sfx})
	return true


## Whether a ritual could be performed now (an Order names one, GDD 11.3):
## what it is done with is in the cabin and not put away, and what it
## requires holds.
func can_perform(ritual_id: String) -> bool:
	if not _data.has_record("rituals", ritual_id):
		return false
	var ritual: Dictionary = _data.record("rituals", ritual_id)
	var owner: Item = owner_of(ritual)
	if ritual.has("item") and (owner == null or is_stowed(owner)):
		return false
	return _requirements_hold(ritual, owner)


## One step of a DRAG ritual (the radio dial). `direction` is +1 right, -1 left.
func drag_step(ritual: Dictionary, direction: int) -> void:
	var owner: Item = owner_of(ritual)
	for op: Variant in GameData.as_array(ritual.get("on_step")):
		_run(GameData.as_string(op), owner, direction)


func _requirements_hold(ritual: Dictionary, owner: Item) -> bool:
	for requirement: Variant in GameData.as_array(ritual.get("requires")):
		if not _holds(GameData.as_string(requirement), owner):
			return false
	return true


## One condition, by its text (see Condition).
func _holds(condition: String, owner: Item) -> bool:
	return _met(_condition(condition), owner)


func _condition(text: String) -> Condition:
	if _conditions.has(text):
		var known: Condition = _conditions[text]
		return known
	var condition: Condition = Condition.new()
	var word: String = text
	if word.begins_with("!"):
		condition.negated = true
		word = word.substr(1)
	if word == "supply>0":
		condition.word = Condition.SUPPLY
	elif word == "ringing":
		condition.word = Condition.RINGING
	elif word == "glovebox_room":
		condition.word = Condition.GLOVEBOX_ROOM
	elif word == "stowed":
		condition.word = Condition.STOWED
	elif word == "hot":
		condition.word = Condition.HOT
	elif word == "playing":
		condition.word = Condition.PLAYING
	elif word == "warbling":
		condition.word = Condition.WARBLING
	elif word.begins_with("flag:"):
		condition.word = Condition.FLAG
		condition.name = StringName(word.substr(5))
	elif word.begins_with("tag:"):
		condition.word = Condition.TAG
		condition.name = StringName(word.substr(4))
	else:
		condition.name = StringName(word)
	_conditions[text] = condition
	return condition


func _met(condition: Condition, owner: Item) -> bool:
	var met: bool = false
	match condition.word:
		Condition.SUPPLY:
			met = owner != null and owner.supply > 0
		Condition.HOT:
			met = owner != null and owner.hot_left > 0.0
		Condition.PLAYING:
			met = owner != null and owner.is_tape and not (owner.side_time >= owner.side_s)
		Condition.WARBLING:
			met = owner != null and owner.is_tape and owner.side_time >= owner.side_s
		Condition.FLAG:
			met = flag(condition.name)
		Condition.RINGING:
			met = caller != &""
		Condition.TAG:
			met = not tagged(String(condition.name)).is_empty()
		Condition.GLOVEBOX_ROOM:
			met = not free_cell().is_empty()
		Condition.STOWED:
			met = not unstow_destinations().is_empty()
		_:
			met = _effects.has(condition.name)
	return met != condition.negated


func _run(op: String, owner: Item, direction: int) -> void:
	var parts: PackedStringArray = op.split(":")
	match parts[0]:
		"nerves":
			_nerves.add(parts[1].to_float())
		"cash":
			cash_delta += parts[1].to_float()
		"add_effect":
			var id: StringName = StringName(parts[1])
			var duration: float = parts[2].to_float() if parts.size() > 2 else _give_duration(owner, id)
			_effects.add(id, duration)
		"remove_effect":
			_effects.remove(StringName(parts[1]))
		"consume_supply":
			if owner != null and owner.supply > 0:
				owner.supply -= 1
		"give":
			_give(owner)
		"toggle":
			var switch: StringName = StringName(parts[1])
			flags[switch] = not flag(switch)
		"horn":
			_horn()
		"wipe":
			since_wipe = 0.0
			wipes += 1
			_draw_wiper_clear()
			# In a dust storm the wipers smear what is on the glass (GDD 10.3).
			if wipe_haze > 0.0:
				haze = minf(haze + wipe_haze, _haze_cap)
		"photo":
			_effects.add(VISOR_DOWN, _visor_time)
			# Flask + Photo (GDD 7.8): looked at with Courage, the photo calms
			# him far more, and the Courage is gone.
			var calm: float = _visor_nerves
			var sobered: Dictionary = pair("photo_sobers") if _effects.has_own(COURAGE) else {}
			if not sobered.is_empty():
				calm = GameData.as_float(sobered.get("amount"))
				_effects.remove(COURAGE)
			if not photo_used:
				photo_used = true
				_nerves.add(calm)
		"indicate":
			# The stalk goes up for right and down for left (GDD 4.6).
			indicate(1 if direction == Gesture.DIR_UP else -1)
		"window":
			var open: bool = not flag(FLAG_WINDOW)
			flags[FLAG_WINDOW] = open
			if open:
				_effects.add(AWAKE, _window_awake)
		"ash":
			if owner != null and owner.burning:
				owner.ashed = true
		"clear_haze":
			haze = 0.0
		"flip":
			if owner != null:
				owner.side_time = 0.0
		"answer":
			_answer_tap(owner)
		"ask":
			asked = true
		"refill":
			# A full supply again for everything of a kind (the Thermos: the tea, hot).
			for refilled: Item in tagged(parts[1]):
				restock(refilled)
		"hook":
			# The hook is hung in the ring: it will hold the wheel when he lets go.
			_effects.hold(HOOK_ARMED, HOOK, true)
		"radio_step":
			_radio_step(direction)
		"pay":
			paid = StringName(parts[1])
		"call":
			call_taken = StringName(parts[1])
		"hand":
			handed = StringName(parts[1])
		"stow":
			# Into a free cell of the glovebox: out of sight, and out of use.
			var cell: String = free_cell()
			if owner != null and not cell.is_empty():
				_put_out(owner)
				owner.slot = StringName(cell)
				_refresh_passives()
		"unstow":
			# DriveSim says where it was put down (unstow_to).
			pass
		"key":
			key_turned = true
		"sfx":
			events.append({"type": "sfx_requested", "id": parts[1]})
		"line":
			events.append({"type": "line_requested", "id": parts[1]})
		_:
			push_error("ItemSim: unknown ritual op '%s'" % op)


## Applies an item's "gives" (GDD 7.2): statuses, and resource changes at once
## or spread over a time.
func _give(owner: Item) -> void:
	if owner == null:
		return
	for list: String in ["gives", "takes"]:
		for listed: Variant in GameData.as_array(owner.record.get(list)):
			_give_entry(owner, GameData.as_dict(listed))
	if owner.use_effect != &"" and _effects.has_own(owner.use_effect) and _param(owner, "ash_by_s", 0.0) > 0.0:
		_start_burn(owner)
	# Tea + Cigarettes (GDD 7.8): a sip while one is lit makes it burn longer.
	for smoke: Item in items:
		if smoke == owner or not smoke.burning:
			continue
		for listed: Variant in GameData.as_array(smoke.record.get("synergies")):
			var synergy: Dictionary = GameData.as_dict(listed)
			if GameData.as_string(synergy.get("rule")) == "sip_extends_burn" and GameData.as_string(synergy.get("with")) == String(owner.id):
				_effects.extend(smoke.use_effect, GameData.as_float(synergy.get("amount")))


## One entry of an item's gives or takes, when the item is used. Entries
## that work all the time (see Standing) are not for here.
func _give_entry(owner: Item, entry: Dictionary) -> void:
	if entry.has("per_s") or entry.has("passive") or GameData.as_string(entry.get("effect")) == HAZE_RATE:
		return
	if entry.has("while") and not _holds(GameData.as_string(entry.get("while")), owner):
		return
	if entry.has("effect"):
		var effect: StringName = StringName(GameData.as_string(entry.get("effect")))
		if entry.has("duration"):
			# The good stuff lets Courage stack higher (GDD 7.7).
			var cap: int = _effects.max_stacks(effect) + roundi(passive("courage_cap_more")) if effect == COURAGE else 0
			_effects.add(effect, GameData.as_float(entry.get("duration")), cap)
		elif GameData.as_string(entry.get("for")) == String(LEG) and not _leg_holds.has(effect):
			_leg_holds.append(effect)
			_effects.hold(effect, LEG, true)
		return
	var amount: float = GameData.as_float(entry.get("amount"))
	if entry.has("synergy"):
		var synergy: Dictionary = _synergy(owner, GameData.as_string(entry.get("synergy")))
		if not synergy.is_empty():
			amount = GameData.as_float(synergy.get("amount"))
	if GameData.as_string(entry.get("resource")) == "nerves":
		var over: float = GameData.as_float(entry.get("over"))
		if over > 0.0:
			_drip_rates.append(amount / over)
			_drip_left.append(over)
		else:
			_nerves.add(amount)
	elif GameData.as_string(entry.get("resource")) == "cash":
		cash_delta += amount


# --- Synergies (GDD 7.8) -----------------------------------------------------

## The synergy under a rule name of whichever item in the cabin has one whose
## partner is there now. {} when there is none.
func pair(rule: String) -> Dictionary:
	for candidate: Item in items:
		var synergy: Dictionary = _synergy(candidate, rule)
		if not synergy.is_empty():
			return synergy
	return {}


## The synergy of `owner` under a rule name, if its partner is there now: an
## item in the cabin, music playing, the photo on the visor. {} otherwise.
func _synergy(owner: Item, rule: String) -> Dictionary:
	if owner == null:
		return {}
	for listed: Variant in owner.synergies:
		var synergy: Dictionary = GameData.as_dict(listed)
		if GameData.as_string(synergy.get("rule")) == rule and _partner_there(GameData.as_string(synergy.get("with"))):
			return synergy
	return {}


func _partner_there(with: String) -> bool:
	if with == TOKEN_MUSIC:
		return _effects.has(MUSIC)
	if with == TOKEN_PHOTO:
		return true
	return item(StringName(with)) != null


## A smoke has just been lit: it burns from now, unashed, and the craving waits.
func _start_burn(candidate: Item) -> void:
	candidate.burning = true
	candidate.burn_time = 0.0
	candidate.ashed = false
	candidate.ash_fell = false
	candidate.lapse_left = -1.0


## How long the item's "gives" say a status lasts.
func _give_duration(owner: Item, id: StringName) -> float:
	if owner == null:
		return 0.0
	for give: Variant in GameData.as_array(owner.record.get("gives")):
		var entry: Dictionary = GameData.as_dict(give)
		if GameData.as_string(entry.get("effect")) == String(id):
			return GameData.as_float(entry.get("duration"))
	return 0.0


func _param(item_instance: Item, key: String, fallback: float) -> float:
	var params: Dictionary = GameData.as_dict(item_instance.record.get("params"))
	return GameData.as_float(params.get(key), fallback)


# --- Standing changes (GDD 7.5 to 7.7) ---------------------------------------

## Anchors that something in the cabin has moved (the crossover stalk moves
## the indicator): anchor id -> where it is now.
func anchor_moves() -> Dictionary:
	var moves: Dictionary = {}
	for candidate: Item in items:
		var params: Dictionary = GameData.as_dict(candidate.record.get("params"))
		if params.has("moves_anchor"):
			moves[GameData.as_string(params.get("moves_anchor"))] = GameData.as_vec3(params.get("moves_to"))
	return moves


## What the things in the cabin change just by being there: the product of
## a multiplier, the sum of an amount (1 or 0 when nothing names the key).
func passive(key: String) -> float:
	if _passives.has(key):
		return GameData.as_float(_passives[key])
	return 1.0 if GameData.as_bool(PASSIVES.get(key)) else 0.0


func _refresh_passives() -> void:
	cabin_serial += 1
	_passives.clear()
	for candidate: Item in items:
		for list: String in ["gives", "takes"]:
			for listed: Variant in GameData.as_array(candidate.record.get(list)):
				var entry: Dictionary = GameData.as_dict(listed)
				if not entry.has("passive"):
					continue
				var key: String = GameData.as_string(entry.get("passive"))
				var amount: float = GameData.as_float(entry.get("amount"))
				if GameData.as_bool(PASSIVES.get(key)):
					_passives[key] = passive(key) * amount
				else:
					_passives[key] = passive(key) + amount
	for candidate: Item in items:
		candidate.smokeless = not _synergy(candidate, "no_smoke_haze").is_empty()
		candidate.warm_while_chewing = false
		for other: Item in items:
			for listed: Variant in GameData.as_array(other.record.get("synergies")):
				var synergy: Dictionary = GameData.as_dict(listed)
				if GameData.as_string(synergy.get("rule")) == "chewing_keeps_warm" and GameData.as_string(synergy.get("with")) == String(candidate.id):
					candidate.warm_while_chewing = true
	# What the tick asks of the cabin as a whole, looked up now and not then:
	# who takes calls, what plays in the deck, whether anything is kept warm,
	# how fast the haze clears.
	var handset: Item = null
	var cassette: Item = null
	var keeps_warm: bool = false
	for candidate: Item in items:
		if handset == null and candidate.is_phone:
			handset = candidate
		if cassette == null and candidate.is_tape:
			cassette = candidate
		keeps_warm = keeps_warm or candidate.warm_while_chewing
	_phone = handset
	_tape = cassette
	_keeps_warm = keeps_warm
	_haze_clear_mult = passive("haze_clear_mult")


# --- The phone (GDD 7.4) -----------------------------------------------------

## The phone in the cabin, or null.
func phone() -> Item:
	return _phone


## True from the first TAP of an answer until the call is answered or lost:
## his eyes are on the phone while his hand is (GDD 4.7).
func dialling() -> bool:
	return caller != &"" and call_taps > 0


## Calls come call_gap_s apart, counted from the end of the last one (or from
## when the phone first rides along). A call rings for ring_s.
func _step_phone(dt: float) -> void:
	var handset: Item = phone()
	if handset == null:
		if caller != &"" or _call_wait >= 0.0:
			_hang_up()
		return
	if caller != &"":
		ring_left -= dt
		if ring_left < dt * 0.5:
			_miss_call(handset)
		return
	if _call_wait < 0.0:
		var gap: Array = GameData.as_array(GameData.as_dict(handset.record.get("params")).get("call_gap_s"))
		if gap.size() < 2:
			# A phone nobody calls.
			return
		_call_wait = _rng.range_f(Rng.ROAD, GameData.as_float(gap[0]), GameData.as_float(gap[1])) * passive("call_gap_mult")
	_call_wait -= dt
	if _call_wait < dt * 0.5:
		_ring(handset)


func _ring(handset: Item) -> void:
	calls += 1
	var every: int = int(_param(handset, "family_every", 0.0))
	caller = CALLER_FAMILY if every > 0 and calls % every == 0 else CALLER_DISPATCHER
	ring_left = _param(handset, "ring_s", 0.0)
	call_taps = 0
	events.append({"type": "call_started", "caller": String(caller), "ring_s": ring_left})
	events.append({"type": "sfx_requested", "id": "phone_ring"})
	if answered_for_him:
		# His passenger picks it up: what the call gives, without his hand.
		taken_for_him = caller
		_answer(handset, true)


## One of the TAPs that answer a call; the last answers. (The first has shown
## the phone in his hand to whoever is watching: see complete().)
func _answer_tap(handset: Item) -> void:
	if handset == null or caller == &"":
		return
	call_taps += 1
	if call_taps < int(_param(handset, "answer_taps", 1.0)):
		return
	_answer(handset, false)


## The call is answered: the dispatcher's fare, or his family's voice.
func _answer(handset: Item, for_him: bool) -> void:
	var paid: float = 0.0
	var calmed: float = 0.0
	if caller == CALLER_FAMILY:
		calmed = _param(handset, "family_nerves", 0.0)
		_nerves.add(calmed)
	else:
		paid = _param(handset, "dispatcher_cash", 0.0) + passive("call_cash_bonus")
	answered_run += 1
	# Phone + Taxi sign (GDD 7.8): every so many calls answered in a row pay a bonus.
	var in_a_row: Dictionary = _synergy(handset, "calls_in_a_row")
	var every: int = GameData.as_int(in_a_row.get("every"))
	if every > 0 and answered_run % every == 0:
		paid += GameData.as_float(in_a_row.get("amount"))
	cash_delta += paid
	events.append({"type": "call_resolved", "caller": String(caller), "answered": true, "cash": paid, "nerves": calmed, "in_a_row": answered_run, "for_him": for_him})
	_hang_up()


func _miss_call(handset: Item) -> void:
	var frayed: float = _param(handset, "missed_nerves", 0.0)
	_nerves.add(frayed)
	answered_run = 0
	events.append({"type": "call_resolved", "caller": String(caller), "answered": false, "cash": 0.0, "nerves": frayed, "in_a_row": 0})
	_hang_up()


## The phone is silent, and the wait for the next call has not begun.
func _hang_up() -> void:
	caller = &""
	ring_left = 0.0
	call_taps = 0
	_call_wait = -1.0


# --- The tape deck -----------------------------------------------------------

## The tape in the deck, or null.
func tape() -> Item:
	return _tape


func _is_tape(candidate: Item) -> bool:
	return candidate.is_tape


## A tape left unflipped past the length of its side warbles (GDD 7.4).
func _warbles(candidate: Item) -> bool:
	return candidate.side_time >= candidate.side_s


## For the views: this item is a tape, and it warbles.
func warbling(candidate: Item) -> bool:
	return candidate.is_tape and _warbles(candidate)


# --- Controls ----------------------------------------------------------------

## The horn (GDD 4.6): vehicles that yield, within horn_range ahead in his
## lane, move over within horn_yield_time if the next lane is free. It calms
## him by horn_nerves at most once per horn_cooldown.
func _horn() -> void:
	horn_blown = true
	if _horn_cooldown <= 0.0:
		_horn_cooldown = _horn_cooldown_s
		_nerves.add(_horn_nerves + passive("horn_nerves_more"))
	for vehicle: TrafficSim.Vehicle in _traffic.vehicles:
		if not horn_reaches(vehicle):
			continue
		var target: int = horn_lane_for(vehicle)
		if target != NO_LANE:
			_traffic.begin_lane_change(vehicle, target, 0.0, _horn_yield_time)


## True for a vehicle the horn is heard by: going his way, in his lane, its
## tail no more than horn_range ahead of his nose.
func horn_reaches(vehicle: TrafficSim.Vehicle) -> bool:
	if vehicle.direction < 0:
		return false
	if absf(vehicle.x - _car.lane_center(_car.lane_of(_car.x))) >= _car.lane_width() * 0.5:
		return false
	var gap: float = (vehicle.s - vehicle.half_length) - (_car.s + _car_half_length)
	return gap >= 0.0 and gap <= _horn_range


## The lane a vehicle would move to for the horn: the one on its right if
## that is free, else the one on its left; NO_LANE if it does not yield (a
## loud horn moves every vehicle, GDD 7.6) or has no free lane beside it.
func horn_lane_for(vehicle: TrafficSim.Vehicle) -> int:
	if not (vehicle.yields_to_horn or passive("horn_yields_all") > 0.0):
		return NO_LANE
	for target: int in [vehicle.lane + 1, vehicle.lane - 1]:
		if target < 0 or target >= _car.lanes:
			continue
		if _traffic.lane_is_free(target, vehicle.s, _horn_clearance, vehicle):
			return target
	return NO_LANE


## The dial: one station per step, in the order of radio_stations. From
## static, right finds the station after the last one heard, left the one before.
func _radio_step(direction: int) -> void:
	if _stations.is_empty():
		return
	if _radio_index == -1:
		_radio_index = 0 if direction > 0 else _stations.size() - 1
	else:
		_radio_index = posmod(_radio_index + (1 if direction > 0 else -1), _stations.size())
	radio = _stations[_radio_index]
	_radio_time = 0.0


## How blurred the rain has made the view: 0 just after a sweep, 1 once the
## sweep's time is up (GDD 4.6, 9.1, D-074). It comes back slowly at first
## and then fast: the share of the time gone by, to wiper_blur_power. A
## stuck wiper clears for less, fog lamps for longer. In dry weather there
## is nothing to blur it.
func rain_blur() -> float:
	if not raining:
		return 0.0
	var clear_time: float = wiper_clear_time()
	if clear_time <= 0.0:
		return 1.0
	return pow(clampf(since_wipe / clear_time, 0.0, 1.0), _wiper_power)


## Seconds the last sweep keeps the glass clear for: its own draw; a stuck
## wiper's fixed time in its place (GDD 6.3); fog lamps stretch either
## (GDD 7.6: what they add to his view in rain is time before it blurs).
func wiper_clear_time() -> float:
	return _faults.param(&"stuck_wiper", "wiper_clear_s", wiper_clear_now) * passive("visibility_mult")


## The time the sweep just made lasts: wiper_clear_time less or more by up
## to wiper_clear_spread. Drawn from the night's seed and the count of
## sweeps, not from a stream: the same night gives the same sweeps, and
## nothing else that is drawn moves.
func _draw_wiper_clear() -> void:
	var seed_value: int = Rng.derive(Rng.derive(_rng.telling_seed if _rng != null else 0, WIPER_SALT), wipes)
	wiper_clear_now = _wiper_clear + (Rng.seeded(seed_value).randf() * 2.0 - 1.0) * _wiper_spread


# --- Things that happen to the cabin -----------------------------------------

## A hit: drinks spill from `kind` up (GDD 7.4: the tea spills in a crash).
func on_hit(kind: int) -> void:
	for candidate: Item in items:
		var spills_from: float = _param(candidate, "spills_on_hit", 0.0)
		if spills_from > 0.0 and float(kind) >= spills_from and candidate.supply > 0:
			candidate.supply = 0


## True while something in the cabin passes a check by itself (use_pass).
func has_pass(what: String) -> bool:
	for candidate: Item in items:
		if GameData.as_string(GameData.as_dict(candidate.record.get("params")).get("passes")) == what:
			return true
	return false


## Something in the cabin that passes a check by itself (forged papers pass
## a checkpoint's Papers phase, GDD 7.7). True when he had it: it is used up.
func use_pass(what: String) -> bool:
	for candidate: Item in items:
		if GameData.as_string(GameData.as_dict(candidate.record.get("params")).get("passes")) == what:
			remove_item(candidate)
			return true
	return false


## A scrape. The charm (GDD 7.5): the first scrape of a leg lights no lamp.
## True when this scrape is that one and a charm hangs there to turn it
## aside. Charm or no charm, the leg's first scrape is behind him after it.
func absorbs_scrape() -> bool:
	var first: bool = not scrape_spared
	scrape_spared = true
	return first and passive("first_scrape_free") > 0.0


## Lamps have just lit. Duct tape (GDD 7.5) takes hold of the first fault of
## the act: it mends itself after self_repair_s. Tape or no tape, the act's
## first fault is behind him after it.
func on_faults_lit(drawn: Array[StringName]) -> void:
	if drawn.is_empty() or tape_spent:
		return
	tape_spent = true
	var after: float = passive("self_repair_s")
	if after <= 0.0:
		return
	mending = drawn[0]
	mend_left = after


## The fault the tape holds is mended now (he has stopped: nothing waits).
func finish_mending() -> void:
	if mending == &"":
		return
	var fault: StringName = mending
	mending = &""
	mend_left = 0.0
	if _faults.repair(fault):
		events.append({"type": "fault_repaired", "fault": String(fault), "lamps": _faults.lamps, "price": 0.0, "by": "duct_tape"})


func _step_mending(dt: float) -> void:
	if mending == &"":
		return
	mend_left -= dt
	if mend_left < dt * 0.5:
		finish_mending()


## He has come to a stop (GDD 9.6), where the night waits: what cannot wait
## is settled first, and said (`events`). The fault the tape holds is
## mended; a call still ringing is dropped, unanswered and at no cost to his
## Nerves or to his row of answered calls; a cigarette that is burning is
## put out, and its craving waits from here.
func come_to_a_stop() -> void:
	finish_mending()
	if caller != &"":
		events.append({"type": "call_resolved", "caller": String(caller), "answered": false, "dropped": true,
				"cash": 0.0, "nerves": 0.0, "in_a_row": answered_run})
		_hang_up()
	for candidate: Item in items:
		if candidate.burning:
			_burn_out(candidate)


## The officer takes the contraband he can see (GDD 6.5): everything marked
## contraband that is not hidden in the glovebox. Returns what was taken.
func take_visible_contraband() -> Array[StringName]:
	var taken: Array[StringName] = []
	var index: int = 0
	while index < items.size():
		var candidate: Item = items[index]
		if GameData.as_bool(candidate.record.get("contraband")) and not is_stowed(candidate):
			taken.append(candidate.id)
			remove_item(candidate)
		else:
			index += 1
	return taken


## A search (GDD 10.2): every piece of contraband is taken, stowed or not.
func take_all_contraband() -> Array[StringName]:
	var taken: Array[StringName] = []
	var index: int = 0
	while index < items.size():
		var candidate: Item = items[index]
		if GameData.as_bool(candidate.record.get("contraband")):
			taken.append(candidate.id)
			remove_item(candidate)
		else:
			index += 1
	return taken


## The contraband that is not stowed in the glovebox (GDD 10.2: left out).
func contraband_in_view() -> int:
	var count: int = 0
	for candidate: Item in items:
		if GameData.as_bool(candidate.record.get("contraband")) and not is_stowed(candidate):
			count += 1
	return count


## The indicator comes on: +1 for right, -1 for left, for indicator_time.
func indicate(way: int) -> void:
	indicator = way
	indicator_left = _indicator_time


## The car crossed a lane line: the indicator cancels (GDD 4.6).
func on_lane_line_crossed() -> void:
	indicator = 0
	indicator_left = 0.0


# --- The tick ----------------------------------------------------------------

func step(dt: float) -> void:
	music_rate = 0.0
	_horn_cooldown = maxf(_horn_cooldown - dt, 0.0)
	since_wipe += dt
	if indicator != 0:
		indicator_left -= dt
		if indicator_left <= 0.0:
			indicator = 0

	# A drip is counted in whole ticks like every other countdown: it is over
	# when less than half a tick of it is left.
	var index: int = 0
	while index < _drip_left.size():
		_nerves.add_rate(_drip_rates[index])
		_drip_left[index] -= dt
		if _drip_left[index] < dt * 0.5:
			_drip_rates.remove_at(index)
			_drip_left.remove_at(index)
		else:
			index += 1

	# What follows is done for everything in the cabin on every tick: it reads
	# what the items carry and what _refresh_passives keeps, never the records.
	var haze_rate: float = 0.0
	var window_open: bool = flag(FLAG_WINDOW)
	var deck_mult: float = _window_radio_mult if window_open else 1.0
	var chewing: bool = _keeps_warm and _effects.has_own(CHEWING)
	var half_tick: float = dt * 0.5
	for candidate: Item in items:
		var hot: float = candidate.hot_left
		if not (chewing and candidate.warm_while_chewing):
			hot -= dt
		if hot < half_tick:
			hot = 0.0
		candidate.hot_left = hot
		if candidate.is_tape:
			candidate.side_time += dt
		for standing: Standing in candidate.standing:
			var on: bool = standing.condition == null or _met(standing.condition, candidate)
			match standing.kind:
				Standing.HAZE:
					if on and not candidate.smokeless:
						haze_rate += standing.amount
				Standing.NERVES:
					if on:
						# What comes out of the deck is halved by an open window.
						var rate: float = standing.amount * (deck_mult if candidate.is_tape else 1.0)
						_nerves.add_rate(rate)
						if standing.music:
							music_rate += rate
				Standing.STATUS:
					if on != standing.held:
						standing.held = on
						_effects.hold(standing.effect, candidate.id, on)
		if candidate.smokes:
			_step_smoke(candidate, dt)
		if not (candidate.lapse_left < 0.0 or candidate.burning):
			_step_lapse(candidate, dt)

	if window_open:
		haze_rate += dust_rate
	if haze_rate > 0.0:
		haze = minf(haze + haze_rate * dt, _haze_cap)
	else:
		var clear: float = _haze_clear * _haze_clear_mult * (_window_haze_mult if window_open else 1.0)
		haze = maxf(haze - clear * dt, 0.0)

	_step_radio(dt)
	_step_phone(dt)
	_step_mending(dt)


## A smoke burns while its status lasts. It must be ashed once before
## ash_by_s or the ash falls (GDD 7.4).
func _step_smoke(candidate: Item, dt: float) -> void:
	var ash_by: float = candidate.ash_by
	if ash_by <= 0.0 or candidate.use_effect == &"":
		return
	var lit: bool = _effects.has_own(candidate.use_effect)
	if lit:
		if not candidate.burning:
			_start_burn(candidate)
		candidate.burn_time += dt
		if not candidate.ashed and candidate.burn_time >= ash_by:
			candidate.ashed = true
			candidate.ash_fell = true
			_nerves.add(_param(candidate, "ash_nerves", 0.0))
	elif candidate.burning:
		_burn_out(candidate)


## A smoke is out: from now the craving waits (GDD 7.4).
func _burn_out(candidate: Item) -> void:
	candidate.burning = false
	var lapse: Dictionary = GameData.as_dict(candidate.record.get("lapse"))
	if lapse.has("after"):
		candidate.lapse_left = GameData.as_float(lapse.get("after"))


## Lapse (GDD 7.2): what happens when a habit is neglected.
func _step_lapse(candidate: Item, dt: float) -> void:
	if candidate.lapse_left < 0.0 or candidate.burning:
		return
	candidate.lapse_left -= dt
	if candidate.lapse_left > 0.0:
		return
	candidate.lapse_left = -1.0
	var lapse: Dictionary = GameData.as_dict(candidate.record.get("lapse"))
	if GameData.as_string(lapse.get("resource")) == "nerves":
		_nerves.add(GameData.as_float(lapse.get("amount")))


## Stations (GDD 6.2): music calms, the news frays and keeps him awake, the
## call-in show does nothing; every station drifts to static.
func _step_radio(dt: float) -> void:
	if radio != STATIC and tape() != null:
		# The deck plays the tape, not the radio.
		radio = STATIC
	if radio != STATIC:
		_radio_time += dt
		if _radio_time >= _radio_drift:
			radio = STATIC
	var mult: float = _window_radio_mult if flag(FLAG_WINDOW) else 1.0
	if radio == &"music":
		_nerves.add_rate(_radio_music_rate * mult)
		music_rate += _radio_music_rate * mult
	elif radio == &"news":
		_nerves.add_rate(_radio_news_rate * mult)
	# The station is a status while it plays: "news" implies Awake, "music"
	# is what the beads answer to (GDD 7.8).
	if radio != _radio_held:
		_let_station_go()
		if radio != STATIC and _data.has_record("effects", String(radio)):
			_effects.hold(radio, &"radio", true)
			_radio_held = radio
