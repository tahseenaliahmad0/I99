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
## each with an optional "while" condition. A resource entry may name a
## "synergy" rule: when that synergy's partner is there, its amount is used.

const SLOT_ANCHOR: String = "@slot"
const STATIC: StringName = &"static"
const AWAKE: StringName = &"awake"
const VISOR_DOWN: StringName = &"visor_down"
const HAZE_RATE: String = "haze_rate"
const FLAG_WINDOW: StringName = &"window_open"
const MUSIC: StringName = &"music"
## Synergy partners that are not items (GDD 7.8).
const TOKEN_MUSIC: String = "music"
const TOKEN_PHOTO: String = "photo"
## What an item that plays in the deck is tagged (the mixtape).
const TAG_TAPE: String = "tape"
## Who holds a status that lasts for the rest of the leg.
const LEG: StringName = &"leg"

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
	## What it does by the second while it is in the cabin.
	var standing: Array[Standing] = []


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
## True while it rains (the leg says so): only then does the view blur.
var raining: bool = false
## Dust in the air (the leg says so): haze per second while the window is open.
var dust_rate: float = 0.0
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
## True for the tick in which contraband, or the phone, was used.
var contraband_used: bool = false
var phone_used: bool = false
## sfx and line requests, drained by DriveSim.
var events: Array[Dictionary] = []

var _data: GameData
var _effects: EffectSystem
var _nerves: NervesSim
var _traffic: TrafficSim
var _car: CarSim
var _faults: FaultSim

## anchor id -> Array of control rituals (no owning item) offered there.
var _controls: Dictionary = {}
## anchor id -> Array of rituals an item has at a place of their own, not at
## its slot (the painkillers are taken at his face).
var _placed: Dictionary = {}
## Statuses held until the leg ends.
var _leg_holds: Array[StringName] = []
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
## Nerves drips: [rate per second, seconds left].
var _drips: Array[Vector2] = []

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
var _indicator_time: float = 0.0
var _visor_time: float = 0.0
var _visor_nerves: float = 0.0
var _window_awake: float = 0.0
var _radio_drift: float = 0.0
var _radio_music_rate: float = 0.0
var _radio_news_rate: float = 0.0
var _car_half_length: float = 0.0


func configure(data: GameData, effects: EffectSystem, nerves: NervesSim, traffic: TrafficSim,
		car: CarSim, faults: FaultSim) -> void:
	_data = data
	_effects = effects
	_nerves = nerves
	_traffic = traffic
	_car = car
	_faults = faults
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
	indicator = 0
	indicator_left = 0.0
	photo_used = false
	horn_blown = false
	cash_delta = 0.0
	_horn_cooldown = 0.0
	_drips.clear()
	_leg_holds.clear()
	events.clear()
	for entry: Variant in GameData.as_array(_data.root("items").get("starting_cabin")):
		var start: Dictionary = GameData.as_dict(entry)
		add_item(StringName(GameData.as_string(start.get("item"))), StringName(GameData.as_string(start.get("slot"))),
				GameData.as_int(start.get("supply"), -1))


## The cabin of a Telling loaded from a save: nothing but what the save lists.
func empty_cabin() -> void:
	items.clear()
	flags.clear()


## Tunes the radio to a station (or to static) without the dial.
func set_radio(station: StringName) -> void:
	_radio_index = _stations.find(station)
	radio = station if _radio_index != -1 else STATIC
	_radio_held = STATIC
	_radio_time = 0.0


## What resets when a new leg begins.
func begin_leg() -> void:
	photo_used = false
	for held: StringName in _leg_holds:
		_effects.hold(held, LEG, false)
	_leg_holds.clear()


## What of this leg a stop must not forget (the save holds it): the photo
## was looked at, and the statuses that last to the leg's end.
func leg_state() -> Dictionary:
	var held: Array = []
	for status: StringName in _leg_holds:
		held.append(String(status))
	return {"photo": photo_used, "held": held}


func set_leg_state(state: Dictionary) -> void:
	photo_used = GameData.as_bool(state.get("photo"))
	for status: Variant in GameData.as_array(state.get("held")):
		var id: StringName = StringName(GameData.as_string(status))
		if not _leg_holds.has(id):
			_leg_holds.append(id)
			_effects.hold(id, LEG, true)


func begin_tick() -> void:
	horn_blown = false
	cash_delta = 0.0
	paid = &""
	contraband_used = false
	phone_used = false


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
	item.slot = slot
	var supply_spec: Dictionary = GameData.as_dict(record.get("supply"))
	if supply_spec.has("uses"):
		item.supply = supply if supply >= 0 else GameData.as_int(supply_spec.get("uses"))
	item.hot_left = _param(item, "hot_for_s", 0.0)
	item.is_tape = _param(item, "side_s", 0.0) > 0.0
	for give: Variant in GameData.as_array(record.get("gives")):
		var entry: Dictionary = GameData.as_dict(give)
		if entry.has("effect") and entry.has("duration") and item.use_effect == &"" and not entry.has("while"):
			item.use_effect = StringName(GameData.as_string(entry.get("effect")))
	for list: String in ["gives", "takes"]:
		for listed: Variant in GameData.as_array(record.get(list)):
			var standing: Standing = _standing_of(GameData.as_dict(listed))
			if standing != null:
				item.standing.append(standing)
	items.append(item)
	return item


func remove_item(item: Item) -> void:
	if item == null:
		return
	# What it was doing stops with it: a smoke goes out, a tape falls silent.
	if item.burning and item.use_effect != &"" and _effects.has_own(item.use_effect):
		_effects.remove(item.use_effect)
	for standing: Standing in item.standing:
		if standing.held:
			standing.held = false
			_effects.hold(standing.effect, item.id, false)
	items.erase(item)


## The entry of a "gives" or "takes" list that works all the time the item
## is there, or null for one that works when the item is used.
func _standing_of(entry: Dictionary) -> Standing:
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


func item_in_slot(slot: StringName) -> Item:
	for candidate: Item in items:
		if candidate.slot == slot:
			return candidate
	return null


func flag(flag_name: StringName) -> bool:
	return GameData.as_bool(flags.get(flag_name))


## The anchor an item's rituals are performed at: its slot's anchor.
func anchor_of(item_instance: Item) -> String:
	return GameData.as_string(_slot_anchor.get(String(item_instance.slot)))


## The anchor of a slot ("" for a slot the hand cannot reach).
func anchor_of_slot(slot: String) -> String:
	return GameData.as_string(_slot_anchor.get(slot))


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
		if anchor_of(candidate) != anchor:
			continue
		for ritual_id: Variant in GameData.as_array(candidate.record.get("rituals")):
			var ritual: Dictionary = _data.record("rituals", GameData.as_string(ritual_id))
			if GameData.as_string(ritual.get("anchor")) == SLOT_ANCHOR and _requirements_hold(ritual, candidate):
				return ritual
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


## Where a HOLD is offered, a control that is a TAP may be offered too (his
## face: the pills are a HOLD, a slap is a TAP). A press let go within a
## TAP's time is then that TAP. {} when `primary` is not a HOLD or there is
## no such control.
func tap_alternative(anchor: String, primary: Dictionary) -> Dictionary:
	if GameData.as_string(primary.get("gesture")) != "HOLD":
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
func complete(ritual: Dictionary, direction: int) -> void:
	var owner: Item = owner_of(ritual)
	if owner != null:
		# Using contraband, or the phone, is something a police car sees (GDD 6.5).
		if GameData.as_bool(owner.record.get("contraband")):
			contraband_used = true
		if GameData.as_array(owner.record.get("tags")).has("phone"):
			phone_used = true
	for op: Variant in GameData.as_array(ritual.get("on_complete")):
		_run(GameData.as_string(op), owner, direction)
	var sfx: String = GameData.as_string(ritual.get("sfx"))
	if not sfx.is_empty():
		events.append({"type": "sfx_requested", "id": sfx})


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
	elif word == "hot":
		condition.word = Condition.HOT
	elif word == "playing":
		condition.word = Condition.PLAYING
	elif word == "warbling":
		condition.word = Condition.WARBLING
	elif word.begins_with("flag:"):
		condition.word = Condition.FLAG
		condition.name = StringName(word.substr(5))
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
			met = owner != null and _is_tape(owner) and not _warbles(owner)
		Condition.WARBLING:
			met = owner != null and _is_tape(owner) and _warbles(owner)
		Condition.FLAG:
			met = flag(condition.name)
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
		"photo":
			_effects.add(VISOR_DOWN, _visor_time)
			if not photo_used:
				photo_used = true
				_nerves.add(_visor_nerves)
		"indicate":
			# The stalk goes up for right and down for left (GDD 4.6).
			indicator = 1 if direction == Gesture.DIR_UP else -1
			indicator_left = _indicator_time
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
		"radio_step":
			_radio_step(direction)
		"pay":
			paid = StringName(parts[1])
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


## One entry of an item's gives or takes, when the item is used. Entries
## that work all the time (see Standing) are not for here.
func _give_entry(owner: Item, entry: Dictionary) -> void:
	if entry.has("per_s") or GameData.as_string(entry.get("effect")) == HAZE_RATE:
		return
	if entry.has("while") and not _holds(GameData.as_string(entry.get("while")), owner):
		return
	if entry.has("effect"):
		var effect: StringName = StringName(GameData.as_string(entry.get("effect")))
		if entry.has("duration"):
			_effects.add(effect, GameData.as_float(entry.get("duration")))
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
			_drips.append(Vector2(amount / over, over))
		else:
			_nerves.add(amount)
	elif GameData.as_string(entry.get("resource")) == "cash":
		cash_delta += amount


# --- Synergies (GDD 7.8) -----------------------------------------------------

## The synergy of `owner` under a rule name, if its partner is there now: an
## item in the cabin, music playing, the photo on the visor. {} otherwise.
func _synergy(owner: Item, rule: String) -> Dictionary:
	if owner == null:
		return {}
	for listed: Variant in GameData.as_array(owner.record.get("synergies")):
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


# --- The tape deck -----------------------------------------------------------

## The tape in the deck, or null.
func tape() -> Item:
	for candidate: Item in items:
		if _is_tape(candidate):
			return candidate
	return null


func _is_tape(candidate: Item) -> bool:
	return candidate.is_tape


## A tape left unflipped past the length of its side warbles (GDD 7.4).
func _warbles(candidate: Item) -> bool:
	return candidate.side_time >= _param(candidate, "side_s", INF)


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
		_nerves.add(_horn_nerves)
	var lane: int = _car.lane_of(_car.x)
	var lane_center: float = _car.lane_center(lane)
	var half_lane: float = _car.lane_width() * 0.5
	for vehicle: TrafficSim.Vehicle in _traffic.vehicles:
		if vehicle.direction < 0 or not vehicle.yields_to_horn:
			continue
		if absf(vehicle.x - lane_center) >= half_lane:
			continue
		var gap: float = (vehicle.s - vehicle.half_length) - (_car.s + _car_half_length)
		if gap < 0.0 or gap > _horn_range:
			continue
		for target: int in [vehicle.lane + 1, vehicle.lane - 1]:
			if target < 0 or target >= _car.lanes:
				continue
			if _traffic.lane_is_free(target, vehicle.s, _horn_clearance, vehicle):
				_traffic.begin_lane_change(vehicle, target, 0.0, _horn_yield_time)
				break


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


## How blurred the rain has made the view: 0 just after a sweep, 1 after the
## wiper's clear time (GDD 4.6, 9.1; a stuck wiper clears for less). In dry
## weather there is nothing to blur it.
func rain_blur() -> float:
	if not raining:
		return 0.0
	var clear_time: float = _faults.param(&"stuck_wiper", "wiper_clear_s", _wiper_clear)
	if clear_time <= 0.0:
		return 1.0
	return clampf(since_wipe / clear_time, 0.0, 1.0)


# --- Things that happen to the cabin -----------------------------------------

## A hit: drinks spill from `kind` up (GDD 7.4: the tea spills in a crash).
func on_hit(kind: int) -> void:
	for candidate: Item in items:
		var spills_from: float = _param(candidate, "spills_on_hit", 0.0)
		if spills_from > 0.0 and float(kind) >= spills_from and candidate.supply > 0:
			candidate.supply = 0


## The officer takes the contraband he can see (GDD 6.5): everything marked
## contraband that is not hidden in the glovebox. Returns what was taken.
func take_visible_contraband() -> Array[StringName]:
	var taken: Array[StringName] = []
	var index: int = 0
	while index < items.size():
		var candidate: Item = items[index]
		if GameData.as_bool(candidate.record.get("contraband")) and not String(candidate.slot).begins_with("glovebox"):
			taken.append(candidate.id)
			items.remove_at(index)
		else:
			index += 1
	return taken


## The car crossed a lane line: the indicator cancels (GDD 4.6).
func on_lane_line_crossed() -> void:
	indicator = 0
	indicator_left = 0.0


# --- The tick ----------------------------------------------------------------

func step(dt: float) -> void:
	_horn_cooldown = maxf(_horn_cooldown - dt, 0.0)
	since_wipe += dt
	if indicator != 0:
		indicator_left -= dt
		if indicator_left <= 0.0:
			indicator = 0

	var index: int = 0
	while index < _drips.size():
		var drip: Vector2 = _drips[index]
		_nerves.add_rate(drip.x)
		drip.y -= dt
		if drip.y <= 0.0:
			_drips.remove_at(index)
		else:
			_drips[index] = drip
			index += 1

	var haze_rate: float = 0.0
	var deck_mult: float = _window_radio_mult if flag(FLAG_WINDOW) else 1.0
	for candidate: Item in items:
		candidate.hot_left -= dt
		if candidate.hot_left < dt * 0.5:
			candidate.hot_left = 0.0
		if _is_tape(candidate):
			candidate.side_time += dt
		for standing: Standing in candidate.standing:
			var on: bool = standing.condition == null or _met(standing.condition, candidate)
			match standing.kind:
				Standing.HAZE:
					if on:
						haze_rate += standing.amount
				Standing.NERVES:
					if on:
						# What comes out of the deck is halved by an open window.
						_nerves.add_rate(standing.amount * (deck_mult if _is_tape(candidate) else 1.0))
				Standing.STATUS:
					if on != standing.held:
						standing.held = on
						_effects.hold(standing.effect, candidate.id, on)
		_step_smoke(candidate, dt)
		_step_lapse(candidate, dt)

	if flag(FLAG_WINDOW):
		haze_rate += dust_rate
	if haze_rate > 0.0:
		haze = minf(haze + haze_rate * dt, _haze_cap)
	else:
		var clear: float = _haze_clear * (_window_haze_mult if flag(FLAG_WINDOW) else 1.0)
		haze = maxf(haze - clear * dt, 0.0)

	_step_radio(dt)


## A smoke burns while its status lasts. It must be ashed once before
## ash_by_s or the ash falls (GDD 7.4).
func _step_smoke(candidate: Item, dt: float) -> void:
	var ash_by: float = _param(candidate, "ash_by_s", 0.0)
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
	elif radio == &"news":
		_nerves.add_rate(_radio_news_rate * mult)
	# The station is a status while it plays: "news" implies Awake, "music"
	# is what the beads answer to (GDD 7.8).
	if radio != _radio_held:
		if _radio_held != STATIC:
			_effects.hold(_radio_held, &"radio", false)
		if radio != STATIC and _data.has_record("effects", String(radio)):
			_effects.hold(radio, &"radio", true)
			_radio_held = radio
		else:
			_radio_held = STATIC
