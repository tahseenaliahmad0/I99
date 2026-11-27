class_name Narration
extends RefCounted
## What is said around the wheel that the simulation does not say itself
## (GDD 3.2, 3.6): Abu Noor telling the night to the Table as it goes by,
## the Table's answer when he meets or misses a heckle, a word from a
## vendor, the radio.
##
## It is presentation. It reads the events the drive controller announces
## and names a line to ask for; it never touches the simulation, and the
## game plays the same with it switched off. Its lines take turns (no chance
## is involved) and keep a gap between them, so that the subtitles are never
## a wall of text. A heckle is not its business: those are tells, and the
## simulation asks for them itself.

## The families of lines that take turns: how many of each the data has.
const FAMILIES: PackedStringArray = [
	"narrator.fork", "narrator.scrape", "narrator.close", "narrator.snap", "narrator.lamp",
	"narrator.repaired", "narrator.bought", "narrator.pulled_over", "narrator.clean_leg",
	"radio.news", "radio.callin", "radio.music",
	"vendor.tea", "vendor.fitter", "vendor.fuel", "vendor.shady", "vendor.find",
	"officer.stop", "noor.call",
]
## A stop's service, and whose word greets him there.
const VENDORS: Dictionary = {"tea": "vendor.tea", "repair": "vendor.fitter", "shop": "vendor.fuel", "find": "vendor.find"}
## Noor's call (GDD 10.4): the first of its lines the simulation asks for
## itself; these follow while they talk.
const CALL_FAMILY: String = "noor.call"
const CALL_FIRST: int = 2

var _data: GameData
var _gap: float = 0.0
var _close_gap: float = 0.0
var _radio_every: float = 0.0
var _call_every: float = 0.0
var _quiet_until: float = 0.0
var _close_until: float = 0.0
var _radio_at: float = 0.0
var _call_at: float = -1.0
var _call_next: int = CALL_FIRST
var _counts: Dictionary = {}
var _turns: Dictionary = {}
var _forks: int = 0
var _stops: int = 0
var _acts_said: Dictionary = {}


func setup(data: GameData) -> void:
	_data = data
	var tuning: Tuning = data.tuning
	_gap = tuning.f("narration_gap")
	_close_gap = tuning.f("narration_close_gap")
	_radio_every = tuning.f("narration_radio_every")
	_call_every = tuning.f("narration_call_every")
	for family: String in FAMILIES:
		var count: int = 0
		while data.has_line("%s.%d" % [family, count + 1]):
			count += 1
		_counts[family] = count
	reset()


## A new night: he starts from the beginning.
func reset() -> void:
	_quiet_until = 0.0
	_close_until = 0.0
	_radio_at = _radio_every
	_call_at = -1.0
	_call_next = CALL_FIRST
	_turns = {}
	_forks = 0
	_stops = 0
	_acts_said = {}


## The line to ask for at this event ("" for none). `now` is the
## simulation's time in seconds; `table` the Table he is telling it to.
func on_event(type: String, event: Dictionary, now: float, table: String) -> String:
	match type:
		"leg_started":
			return _leg_line(event, now)
		"fork_taken":
			_forks += 1
			if _forks % 3 == 2:
				return _spoken(_next("narrator.fork"), now)
		"boss_started":
			return _spoken(_if_there("narrator.boss.%s" % GameData.as_string(event.get("boss"))), now, true)
		"stop_entered":
			return _stop_line(event, now)
		"hit":
			if GameData.as_int(event.get("lamps")) == 0:
				return _spoken(_next("narrator.scrape"), now)
		"lamp_lit":
			var faults: Array = GameData.as_array(event.get("faults"))
			var of_fault: String = _if_there("narrator.fault.%s" % str(faults[0])) if not faults.is_empty() else ""
			return _spoken(of_fault if not of_fault.is_empty() else _next("narrator.lamp"), now, true)
		"close_call":
			if now >= _close_until:
				var line: String = _spoken(_next("narrator.close"), now)
				if not line.is_empty():
					_close_until = now + _close_gap
				return line
		"snap":
			return _spoken(_next("narrator.snap"), now, true)
		"fault_repaired":
			return _spoken(_next("narrator.repaired"), now)
		"item_bought":
			if not GameData.as_bool(event.get("restock")):
				return _spoken(_next("narrator.bought"), now)
		"pulled_over":
			return _spoken(_next("officer.stop"), now, true)
		"leg_ended":
			if GameData.as_bool(event.get("clean")):
				return _spoken(_next("narrator.clean_leg"), now)
		"heckle_resolved":
			# The Table's answer to what he made of it. (A Twist and the Fib
			# have nothing to answer.)
			var outcome: String = GameData.as_string(event.get("outcome"))
			if outcome == HeckleDirector.PASSED or outcome == HeckleDirector.FAILED:
				return _if_there("heckle.%s.%s" % [outcome, table])
	return ""


## The line the radio, or Noor on the phone, says by itself now ("" for
## none): asked once a frame with what the snapshot shows.
func on_time(now: float, radio: String, heckle_on: bool, talking: bool) -> String:
	if talking:
		# Noor's call: its lines in their order, call_every apart.
		if _call_at < 0.0:
			_call_at = now + _call_every
		elif now >= _call_at and _call_next <= GameData.as_int(_counts.get(CALL_FAMILY)):
			_call_at = now + _call_every
			_call_next += 1
			_quiet_until = now + _gap
			return "%s.%d" % [CALL_FAMILY, _call_next - 1]
		return ""
	_call_at = -1.0
	if heckle_on or now < _radio_at or now < _quiet_until:
		return ""
	var family: String = "radio.%s" % radio
	if GameData.as_int(_counts.get(family)) == 0:
		return ""
	_radio_at = now + _radio_every
	return _spoken(_next(family), now)


func _leg_line(event: Dictionary, now: float) -> String:
	var act: int = GameData.as_int(event.get("act"), 1)
	if act > 1 and not _acts_said.has(act):
		# The first leg of a new act: he says where the night has got to.
		_acts_said[act] = true
		var of_act: String = _if_there("narrator.act.%d" % act)
		if not of_act.is_empty():
			return _spoken(of_act, now, true)
	var leg: String = GameData.as_string(event.get("leg"))
	var modifier: String = GameData.as_string(event.get("modifier"))
	var turn: int = GameData.as_int(_turns.get("leg"))
	_turns["leg"] = turn + 1
	if not modifier.is_empty() and turn % 2 == 1:
		var of_modifier: String = _if_there("narrator.modifier.%s" % modifier)
		if not of_modifier.is_empty():
			return _spoken(of_modifier, now, true)
	var of_leg: String = _if_there("narrator.leg.%s.%d" % [leg, 1 + (turn / 2) % 2])
	if of_leg.is_empty():
		of_leg = _if_there("narrator.leg.%s.1" % leg)
	return _spoken(of_leg, now, true)


func _stop_line(event: Dictionary, now: float) -> String:
	var stop_id: String = GameData.as_string(event.get("stop"))
	var service: String = "boss" if stop_id == "boss_stop" else GameData.as_string(_data.record("stops", stop_id).get("service")) if _data.has_record("stops", stop_id) else ""
	_stops += 1
	# He and the vendor take turns; the man in the shade speaks for himself.
	if GameData.as_bool(event.get("shady")) and _stops % 3 == 0:
		return _spoken(_next("vendor.shady"), now, true)
	if _stops % 2 == 0 and VENDORS.has(service):
		var word: String = _next(GameData.as_string(VENDORS[service]))
		if not word.is_empty():
			return _spoken(word, now, true)
	return _spoken(_if_there("narrator.stop.%s" % service), now, true)


## The next line of a family in its turn ("" when the family has none).
func _next(family: String) -> String:
	var count: int = GameData.as_int(_counts.get(family))
	if count <= 0:
		return ""
	var turn: int = GameData.as_int(_turns.get(family))
	_turns[family] = turn + 1
	return "%s.%d" % [family, 1 + turn % count]


func _if_there(line_id: String) -> String:
	return line_id if _data.has_line(line_id) else ""


## The line, if he may speak now: not within the gap after his last one,
## unless it marks a moment (`always`). Speaking starts the gap again.
func _spoken(line_id: String, now: float, always: bool = false) -> String:
	if line_id.is_empty() or (not always and now < _quiet_until):
		return ""
	_quiet_until = now + _gap
	return line_id
