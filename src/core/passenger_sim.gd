class_name PassengerSim
extends RefCounted
## The passenger (GDD 8): at most one, in the seat.
##
## A passenger is data (passengers.json): a Hand (what they do when asked
## with a TAP on the shoulder, or all the time), Weights (what they cost),
## how long they ride and what they pay. This class keeps who rides and what
## they are doing right now. It changes Nerves, statuses, the radio, the
## faults and the things in the cabin itself; what belongs to the wheel, the
## gear lever, Suspicion and the road, DriveSim asks it for.

## Who holds a status that a passenger gives.
const HOLDER: StringName = &"passenger"
## The Hajjiya's blessing (GDD 8.2): the first scrape after it lights no lamp.
const BLESSING: StringName = &"blessing"
## The cabin switch that says somebody is in the seat (the Call, GDD 10.4).
const FLAG: StringName = &"passenger"
const RIDES_ACT_END: String = "act_end"
const RIDES_BASRA: String = "basra"

## How the wheel is held for him: not at all; dead straight; where it is.
const HOLD_NONE: int = 0
const HOLD_STRAIGHT: int = 1
const HOLD_ANGLE: int = 2

## A passenger's Hand (passengers.json, "hand.kind").
const HAND_STRAIGHT: String = "hold_wheel_straight"
const HAND_HOLD: String = "hold_wheel"
const HAND_CIGARETTE: String = "cigarette"
const HAND_TEA: String = "pass_tea"

## The repair of one who repairs: nothing; announced; leaning across the lever.
const REPAIR_IDLE: int = 0
const REPAIR_ANNOUNCED: int = 1
const REPAIR_LEANING: int = 2

## When a Weight bites.
const WHEN_TAG: int = 0
const WHEN_GEAR: int = 1
const WHEN_ASLEEP: int = 2
const WHEN_SCRAPE: int = 3
const WHEN_DRUMMING_PATROL: int = 4


## One Weight of the passenger who rides, read once when they board.
class Weight:
	extends RefCounted
	var when: int = 0
	var tag: String = ""
	var gear: int = 0
	var in_rain: bool = false
	var suspicion: bool = false
	var amount: float = 0.0
	var per_s: float = 0.0


## Who rides ("" for nobody) and their record.
var id: String = ""
var record: Dictionary = {}
## Legs whose stall they have ridden past since they boarded.
var legs_ridden: int = 0
## The wheel is held for him, and for how long yet; and, by one who holds it
## "at its current angle", the angle at which.
var hold: int = HOLD_NONE
var hold_left: float = 0.0
var held_angle: float = 0.0
## One who sleeps: seconds they stay awake (0: asleep).
var awake_left: float = 0.0
## One who drums: drumming now. (Not drumming, his hands are free for the tea.)
var drumming: bool = false
## One who repairs: where the repair stands, and the seconds left of that.
var repair: int = REPAIR_IDLE
var repair_left: float = 0.0
## Faults repaired on this leg.
var repaired: int = 0
## Seconds until the radio is turned to static again.
var retune_in: float = 0.0
## The blessing of one who has left: the next scrape lights no lamp.
var blessed: bool = false

## What happened this tick (DriveSim announces these).
var events: Array[Dictionary] = []
var cash_delta: float = 0.0
## The cabin has changed (who rides, what is held out to him): DriveSim fits
## its systems to it again.
var changed: bool = false

var _data: GameData
var _effects: EffectSystem
var _nerves: NervesSim
var _items: ItemSim
var _faults: FaultSim
var _weights: Array[Weight] = []
## The statuses held on now.
var _held: Array[StringName] = []
var _music_rate: float = 0.0
## The Hajjiya's prayer has begun (a line, once each time she starts).
var _weighing: bool = false


func configure(data: GameData, effects: EffectSystem, nerves: NervesSim, items: ItemSim, faults: FaultSim) -> void:
	_data = data
	_effects = effects
	_nerves = nerves
	_items = items
	_faults = faults
	_music_rate = data.tuning.f("radio_music_rate")


func begin_tick() -> void:
	events.clear()
	cash_delta = 0.0
	changed = false


func aboard() -> bool:
	return not id.is_empty()


# --- Boarding and leaving ----------------------------------------------------

## He unlocked the door for a hitcher (GDD 8.1). False when the seat is
## taken or there is no such passenger.
func board(passenger_id: String) -> bool:
	if aboard() or not _data.has_record("passengers", passenger_id):
		return false
	_seat(passenger_id)
	legs_ridden = 0
	repaired = 0
	drumming = record.has("drums")
	_hold_statuses()
	events.append({"type": "passenger_boarded", "passenger": id, "fare": GameData.as_float(record.get("fare")),
			"rides_legs": GameData.as_int(record.get("rides_legs")), "rides_until": GameData.as_string(record.get("rides_until"))})
	_say("board")
	return true


## Puts a passenger in the seat: what is on it goes to the back seat.
func _seat(passenger_id: String) -> void:
	id = passenger_id
	record = _data.record("passengers", passenger_id)
	_weights = []
	for entry: Variant in GameData.as_array(record.get("weights")):
		_weights.append(_weight(GameData.as_dict(entry)))
	hold = HOLD_NONE
	hold_left = 0.0
	held_angle = 0.0
	awake_left = 0.0
	repair = REPAIR_IDLE
	repair_left = 0.0
	retune_in = GameData.as_float(GameData.as_dict(record.get("retunes")).get("every_s"))
	_weighing = false
	_items.flags[FLAG] = true
	_items.seat_taken(true)
	_items.answered_for_him = GameData.as_bool(GameData.as_dict(record.get("always")).get("answers_calls"))
	changed = true


func _weight(entry: Dictionary) -> Weight:
	var weight: Weight = Weight.new()
	var when: String = GameData.as_string(entry.get("when"))
	weight.suspicion = GameData.as_string(entry.get("resource")) == "suspicion"
	weight.amount = GameData.as_float(entry.get("amount"))
	weight.per_s = GameData.as_float(entry.get("per_s"))
	if when.begins_with("ritual_tag:"):
		weight.when = WHEN_TAG
		weight.tag = when.substr(11)
	elif when.begins_with("gear>="):
		weight.when = WHEN_GEAR
		weight.in_rain = when.ends_with("&rain")
		weight.gear = when.substr(6).trim_suffix("&rain").to_int()
	elif when == "asleep":
		weight.when = WHEN_ASLEEP
	elif when == "scrape":
		weight.when = WHEN_SCRAPE
	else:
		weight.when = WHEN_DRUMMING_PATROL
	return weight


## True when the ride is over: the legs they ride are behind them, or, for
## one who rides to the end of the act, he stands at the stop after its boss.
## One who rides to Basra never leaves before it.
func ride_over(after_boss: bool) -> bool:
	if not aboard():
		return false
	if record.has("rides_legs"):
		return legs_ridden >= GameData.as_int(record.get("rides_legs"))
	return GameData.as_string(record.get("rides_until")) == RIDES_ACT_END and after_boss


## They get out where the car stands: the fare, and what they leave him with.
func leave(reason: String) -> void:
	if not aboard():
		return
	var fare: float = GameData.as_float(record.get("fare"))
	cash_delta += fare
	for op: Variant in GameData.as_array(record.get("on_leave")):
		_run(GameData.as_string(op))
	events.append({"type": "passenger_left", "passenger": id, "fare": fare, "reason": reason})
	_say("leave")
	_empty_seat()


func _empty_seat() -> void:
	id = ""
	record = {}
	_weights = []
	legs_ridden = 0
	hold = HOLD_NONE
	hold_left = 0.0
	held_angle = 0.0
	awake_left = 0.0
	drumming = false
	repair = REPAIR_IDLE
	repair_left = 0.0
	repaired = 0
	retune_in = 0.0
	_weighing = false
	_hold_statuses()
	_items.flags[FLAG] = false
	_items.seat_taken(false)
	_items.answered_for_him = false
	changed = true


## One op of "on_leave": "nerves:<n>", "cash:<n>", "add_effect:<id>". The
## blessing is kept until a scrape uses it; any other status is held on.
func _run(op: String) -> void:
	var parts: PackedStringArray = op.split(":")
	match parts[0]:
		"nerves":
			_nerves.add(parts[1].to_float())
		"cash":
			cash_delta += parts[1].to_float()
		"add_effect":
			if StringName(parts[1]) == BLESSING:
				_bless(true)
			elif parts.size() > 2:
				_effects.add(StringName(parts[1]), parts[2].to_float())
		_:
			push_error("PassengerSim: unknown op '%s'" % op)


func _bless(on: bool) -> void:
	blessed = on
	_effects.hold(BLESSING, HOLDER, on)


## A scrape, with nothing else to turn it aside: true when the blessing does
## (and is used up).
func absorbs_scrape() -> bool:
	if not blessed:
		return false
	_bless(false)
	return true


## He has passed a leg's stall, stopping or not.
func leg_ridden() -> void:
	if aboard():
		legs_ridden += 1


## A leg or a boss begins: what is once per leg may be done again.
func begin_leg() -> void:
	repaired = 0


# --- The Hand (GDD 8.1: a TAP on the shoulder) -------------------------------

## `wheel_angle` is the angle one who holds the wheel "at its current angle"
## is to hold it at (DriveSim knows the wheel).
func ask(wheel_angle: float) -> void:
	if not aboard():
		return
	if record.has("sleeps") and awake_left <= 0.0:
		# The tap wakes him; only then does his Hand work.
		_wake()
		return
	var hand: Dictionary = GameData.as_dict(record.get("hand"))
	match GameData.as_string(hand.get("kind")):
		HAND_STRAIGHT:
			hold = HOLD_STRAIGHT
			hold_left = GameData.as_float(hand.get("duration_s"))
		HAND_HOLD:
			hold = HOLD_ANGLE
			hold_left = GameData.as_float(hand.get("duration_s"))
			held_angle = wheel_angle
		HAND_CIGARETTE:
			if not _items.light_handed():
				return
		HAND_TEA:
			# A tap stops the drum, and his hands are free for the tea; the
			# next starts it again. With no tea to pass, the tap stops and
			# starts the drum and he says nothing of tea.
			drumming = not drumming
			_hold_statuses()
			changed = true
			if drumming:
				_say("drum")
			elif passes_tea():
				_say("hand")
			return
		_:
			return
	_say("hand")


func _wake() -> void:
	awake_left = GameData.as_float(GameData.as_dict(record.get("sleeps")).get("awake_s"))
	_say("wake")


## His horn sounded: it wakes one who sleeps.
func on_horn() -> void:
	if aboard() and awake_left <= 0.0 and GameData.as_bool(GameData.as_dict(record.get("sleeps")).get("horn_wakes")):
		_wake()


## One who answers his calls took one (GDD 8.2): what they tell him of it.
## The line of that Hand is the dispatcher's fare; a call from his family has
## a word of its own.
func on_call_taken(caller: StringName) -> void:
	_say("hand" if caller == ItemSim.CALLER_DISPATCHER else "family")


## He took the wheel himself: nobody holds it for him any more.
func wheel_taken() -> void:
	hold = HOLD_NONE
	hold_left = 0.0


## Seconds after the driver's hand has left the wheel in which one who holds
## it "at its current angle" still takes it back to the angle it was let go
## at (GDD 8.2; 0 for everybody else). A wheel let go is back at its centre
## before a TAP can land on a shoulder half a second away (GDD 4.3).
func catch_time() -> float:
	return GameData.as_float(GameData.as_dict(record.get("hand")).get("catch_s"))


func holds_wheel() -> bool:
	return hold != HOLD_NONE


func holds_straight() -> bool:
	return hold == HOLD_STRAIGHT


## A Weight that bites by the second for how he drives is said aloud for as
## long as it bites (GDD 8.2: "she prays aloud").
func aloud() -> bool:
	return aboard() and _weighing


## One who sleeps is asleep.
func asleep() -> bool:
	return record.has("sleeps") and awake_left <= 0.0


## The tea is held out to him beside the wheel (tea_at: where, in the cabin
## frame): by one whose Hand that is, while his own hands are off the drum
## and a tea stands in the cabin for him to take.
func passes_tea() -> bool:
	return aboard() and record.has("drums") and not drumming \
			and GameData.as_string(GameData.as_dict(record.get("hand")).get("kind")) == HAND_TEA \
			and _items.in_reach(ItemSim.TAG_TEA) != null


func tea_at() -> Vector3:
	return GameData.as_vec3(GameData.as_dict(record.get("hand")).get("at"))


# --- What they do all the time -----------------------------------------------

## What Suspicion gains are multiplied by (the Conscript's uniform).
func suspicion_mult() -> float:
	return GameData.as_float(GameData.as_dict(record.get("always")).get("suspicion_gain_mult"), 1.0)


## Seconds earlier that a fork's sign shows (the Student reads the road).
func fork_sign_lead() -> float:
	return GameData.as_float(GameData.as_dict(record.get("always")).get("fork_sign_lead_s"))


## The share of the view's right side that is blocked (the Drummer's drum).
func view_block_right() -> float:
	return GameData.as_float(record.get("view_block_right"))


## He leans across the gear lever: no shifting.
func blocks_lever() -> bool:
	return repair == REPAIR_LEANING


## Suspicion by the second while a Patrol watches (the drum).
func suspicion_rate() -> float:
	var rate: float = 0.0
	for weight: Weight in _weights:
		if weight.when == WHEN_DRUMMING_PATROL and weight.suspicion and drumming:
			rate += weight.per_s
	return rate


## The statuses a passenger holds on: those of "always", and a drummer's
## while he drums.
func _hold_statuses() -> void:
	var wanted: Array[StringName] = []
	for effect: Variant in GameData.as_array(GameData.as_dict(record.get("always")).get("effects")):
		wanted.append(StringName(GameData.as_string(effect)))
	if drumming:
		for effect: Variant in GameData.as_array(GameData.as_dict(record.get("drums")).get("effects")):
			wanted.append(StringName(GameData.as_string(effect)))
	for effect: StringName in _held:
		if not wanted.has(effect):
			_effects.hold(effect, HOLDER, false)
	for effect: StringName in wanted:
		if not _held.has(effect):
			_effects.hold(effect, HOLDER, true)
	_held = wanted


# --- By the tick -------------------------------------------------------------

## One tick of the ride, while the car is on the road. `gear` is the gear he
## is in, `raining` whether it rains.
func step(dt: float, gear: int, raining: bool) -> void:
	if not aboard():
		return
	if hold != HOLD_NONE:
		hold_left -= dt
		if hold_left < dt * 0.5:
			wheel_taken()
	if awake_left > 0.0:
		awake_left -= dt
		if awake_left < dt * 0.5:
			awake_left = 0.0
	_step_repair(dt)
	_step_retune(dt)
	var weighing: bool = false
	for weight: Weight in _weights:
		if weight.per_s == 0.0 or weight.suspicion:
			continue
		var bites: bool = false
		match weight.when:
			WHEN_GEAR:
				bites = gear >= weight.gear and (raining or not weight.in_rain)
				weighing = weighing or bites
			WHEN_ASLEEP:
				bites = asleep()
		if bites:
			_nerves.add_rate(weight.per_s)
	if weighing and not _weighing:
		_say("prayer")
	_weighing = weighing
	# His drum is music as the radio's is (GDD 6.1), and music is music once:
	# where the radio or a tape plays as well, the drum gives only what it is
	# stronger by. (An open window lets out what comes from the dash, GDD 4.6;
	# his drum is not the radio.)
	if drumming and _held.has(ItemSim.MUSIC):
		_nerves.add_rate(minf(_music_rate - _items.music_rate, 0.0))


## One fault per leg (GDD 8.2): announced, then for a while he leans across
## the gear lever, and then the oldest fault that is his to mend is mended.
func _step_repair(dt: float) -> void:
	var repairs: Dictionary = GameData.as_dict(record.get("repairs"))
	if repairs.is_empty():
		return
	match repair:
		REPAIR_IDLE:
			if repaired < GameData.as_int(repairs.get("per_leg")) and _fault_to_mend() != &"":
				repair = REPAIR_ANNOUNCED
				repair_left = GameData.as_float(repairs.get("announce_s"))
				# The warning is a tell (GDD 8.2: "announced 2 s ahead"): it is
				# read at once, and heard as well (GDD 17.2).
				_say("repair", true)
				events.append({"type": "sfx_requested", "id": "passenger_clink"})
		REPAIR_ANNOUNCED:
			repair_left -= dt
			if repair_left < dt * 0.5:
				repair = REPAIR_LEANING
				repair_left = GameData.as_float(repairs.get("lean_s"))
		REPAIR_LEANING:
			repair_left -= dt
			if repair_left < dt * 0.5:
				repair = REPAIR_IDLE
				repair_left = 0.0
				var fault: StringName = _fault_to_mend()
				if fault != &"":
					repaired += 1
					_faults.repair(fault)
					events.append({"type": "fault_repaired", "fault": String(fault), "lamps": _faults.lamps, "price": 0.0, "by": id})


## The fault he would mend: the oldest lit one that duct tape is not already
## mending (GDD 7.5: that one repairs itself; he does not spend his repair
## on it). Empty when there is none.
func _fault_to_mend() -> StringName:
	for fault: StringName in _faults.active:
		if fault != _items.mending:
			return fault
	return &""


## The radio, turned to static every so often (GDD 8.2). Where it is there
## already (nothing plays, or a tape is in the deck) there is no dial for him
## to turn and nothing to say.
func _step_retune(dt: float) -> void:
	var retunes: Dictionary = GameData.as_dict(record.get("retunes"))
	if retunes.is_empty():
		return
	retune_in -= dt
	if retune_in < dt * 0.5:
		retune_in = GameData.as_float(retunes.get("every_s"))
		var to: StringName = StringName(GameData.as_string(retunes.get("to")))
		if _items.radio != to:
			_items.set_radio(to)
			_say("radio")


## He used things with these tags (a cigarette lit, a sip from the flask):
## what the passenger forbids costs him each time.
func on_used(tags: PackedStringArray) -> void:
	for weight: Weight in _weights:
		if weight.when == WHEN_TAG and tags.has(weight.tag):
			_nerves.add(weight.amount)
			_say("weight")


## A scrape: what one who watches the road makes of it.
func on_scrape() -> void:
	for weight: Weight in _weights:
		if weight.when == WHEN_SCRAPE:
			_nerves.add(weight.amount)
			_say("weight")


# --- Lines and the save ------------------------------------------------------

func _line(what: String) -> String:
	return "%s.%s" % [GameData.as_string(record.get("line_prefix")), what]


## A line of the passenger's, if they have one for this.
func _say(what: String, tell: bool = false) -> void:
	if _data.has_line(_line(what)):
		var asked: Dictionary = {"type": "line_requested", "id": _line(what)}
		if tell:
			# What announces something a moment ahead does not wait its turn.
			asked["tell"] = true
		events.append(asked)


## What the save keeps (GDD 13.7): who rides and how far they have come; null
## when nobody rides and no blessing is left.
func state() -> Variant:
	if not aboard() and not blessed:
		return null
	return {"id": id, "legs": legs_ridden, "drumming": drumming, "repaired": repaired, "blessed": blessed}


## Who was riding when the save was made sits in the seat again. What lasts
## seconds (the hand on the wheel, the woken sleeper) does not outlast a stop.
func set_state(saved: Variant) -> void:
	var kept: Dictionary = GameData.as_dict(saved)
	var passenger_id: String = GameData.as_string(kept.get("id"))
	if not passenger_id.is_empty() and _data.has_record("passengers", passenger_id):
		_seat(passenger_id)
		legs_ridden = GameData.as_int(kept.get("legs"))
		repaired = GameData.as_int(kept.get("repaired"))
		drumming = record.has("drums") and GameData.as_bool(kept.get("drumming"), true)
		_hold_statuses()
	if GameData.as_bool(kept.get("blessed")):
		_bless(true)
