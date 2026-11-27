class_name HeckleDirector
extends RefCounted
## What the Table says while he tells it (GDD 11.3): "A heckle is always
## followed by a change on the road or a challenge."
##
##   One heckle per leg in Act 1, two per leg after. Never during an
##   encounter or a boss. The subtitle appears heckle_lead before anything
##   changes: that lead is the tell.
##
## A leg's heckles are drawn when the leg is taken, from the `heckle` stream:
## which record of data/heckles.json (by the Table's weights, and the wedding
## guests' two each), and where along the leg it falls due. A Twist that puts
## a stretch of its own on the road (sheep, the wedding, the melon truck) is
## handed to the generator, which lays it out like a modifier's; LegSim keeps
## it off the road until this class says the heckle has been heard.
##
## DriveSim sets the `in_*` fields, calls step() once a tick and applies what
## the step asks for: `nerves`, `cash`, `twist_begins`, `shower_begins`, and
## `ghost_holds` while the Fib's left hand has the wheel.
##
## What a record says (GDD 14, and D-061):
##   type       TWIST, DARE, DOUBT, QUESTION, ORDER or FIB
##   tables     the Tables whose guests say it
##   guest      the passenger who says it once carried to Basra (GDD 11.5)
##   line_id    the subtitle
##   window_s   how long he has (DARE, DOUBT, QUESTION, ORDER); how long the
##              ghost hand holds (FIB)
##   twist      TWIST: a modifier with a stretch of its own, or "shower"
##   duration_s TWIST "shower": how long it rains
##   answer     DARE, DOUBT: any one of these answers it (see parse_answer)
##   keep       QUESTION: all of these for the whole window (see parse_keep)
##   ritual     ORDER: the ritual to perform
##   pass, fail what answering, or not, does: { "nerves": n, "cash": n }

const TWIST: String = "TWIST"
const DARE: String = "DARE"
const DOUBT: String = "DOUBT"
const QUESTION: String = "QUESTION"
const ORDER: String = "ORDER"
const FIB: String = "FIB"
const SHOWER: String = "shower"

const NONE: int = 0
## The subtitle is up; nothing has changed yet.
const LEAD: int = 1
## The change is on the road, or the challenge is running.
const OPEN: int = 2
const PHASE_NAMES: PackedStringArray = ["", "lead", "open"]

## How a heckle ended: he answered it; he did not; it had nothing to answer
## and is over; the leg ended first.
const PASSED: String = "passed"
const FAILED: String = "failed"
const OVER: String = "over"
const LAPSED: String = "lapsed"

const CLOSE_CALL: String = "close_call"
const GEAR: String = "gear"
const HANDS_OFF: String = "hands_off"
const PASS: String = "pass"
const NERVES_UNDER: String = "nerves_under"
const NO_HORN: String = "no_horn"

const KMH_TO_MS: float = 1.0 / 3.6

# --- What DriveSim tells it each tick ----------------------------------------
var in_gear: int = 0
## His hand is on the wheel.
var in_gripping: bool = false
## The road under the car is straight.
var in_straight: bool = true
var in_nerves: float = 0.0
## Close calls counted this tick.
var in_close_calls: int = 0
var in_horn: bool = false
## The ritual completed this tick (&"" for none).
var in_ritual: StringName = &""
## Vehicles going his way that the car passed this tick.
var in_passed: int = 0

# --- What it asks of DriveSim this tick --------------------------------------
var nerves: float = 0.0
var cash: float = 0.0
## The Twist's stretch comes onto the road now.
var twist_begins: bool = false
## A shower begins now: its seconds (0 for none).
var shower_begins: float = 0.0
var events: Array[Dictionary] = []

# --- State ---------------------------------------------------------------------
## The Fib (GDD 11.3): "A ghost left hand holds the lane."
var ghost_holds: bool = false
## The heckle being said or running ({} for none).
var record: Dictionary = {}
var phase: int = NONE
var lead_left: float = 0.0
var window_left: float = 0.0
## This leg's heckles, by where they fall due: { "record", "due_s", "roll" }.
var planned: Array[Dictionary] = []
## How many of them have been said.
var said: int = 0

var _data: GameData
var _items: ItemSim
var _lead: float = 0.0
var _per_leg: Array = []
var _span: Vector2 = Vector2.ZERO
var _guest_weight: float = 0.0
var _top_ms: float = 0.0
## The records this leg's heckles were drawn from, to draw another from when
## the one planned cannot be asked of him.
var _pool: Array[Dictionary] = []
var _answers: Array[Dictionary] = []
var _keeps: Array[Dictionary] = []
## One number per answer: seconds held, or close calls counted.
var _progress: PackedFloat64Array = PackedFloat64Array()
## When each vehicle was passed, by the window's clock.
var _passes: PackedFloat64Array = PackedFloat64Array()
var _clock: float = 0.0
var _until_s: float = INF
var _s: float = 0.0


func configure(data: GameData, items: ItemSim) -> void:
	_data = data
	_items = items
	var tuning: Tuning = data.tuning
	_lead = tuning.f("heckle_lead")
	_per_leg = tuning.a("heckles_per_leg")
	_span = Vector2(tuning.fi("heckle_span", 0), tuning.fi("heckle_span", 1))
	_guest_weight = tuning.f("guest_heckle_weight")
	var speeds: Array = tuning.a("gear_speeds")
	_top_ms = GameData.as_float(speeds[speeds.size() - 1]) * KMH_TO_MS


# --- The pool (GDD 11.2, 11.5) -----------------------------------------------------

## The records the Table's guests may say, each with its weight: a type's
## weight is shared among the Table's records of that type; each record of a
## wedding guest who is there weighs guest_heckle_weight. A Table with no
## heckle weights has no heckles, whoever sits at it (GDD 11.2: Noor's).
static func pool(data: GameData, table: TableRules, guests: PackedStringArray, guest_weight: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if table.heckle_types().is_empty():
		return out
	var of_type: Dictionary = {}
	var own: Array[Dictionary] = []
	for heckle: Dictionary in data.records("heckles"):
		if not GameData.as_array(heckle.get("tables")).has(table.id):
			continue
		var guest: String = GameData.as_string(heckle.get("guest"))
		if not guest.is_empty():
			if guests.has(guest) and guest_weight > 0.0:
				out.append({"record": heckle, "weight": guest_weight})
			continue
		var type: String = GameData.as_string(heckle.get("type"))
		if GameData.as_float(table.heckle_weights.get(type)) <= 0.0:
			continue
		of_type[type] = GameData.as_int(of_type.get(type)) + 1
		own.append(heckle)
	for heckle: Dictionary in own:
		var type: String = GameData.as_string(heckle.get("type"))
		out.append({"record": heckle, "weight": GameData.as_float(table.heckle_weights.get(type)) / float(GameData.as_int(of_type.get(type)))})
	return out


# --- A leg's heckles ---------------------------------------------------------------

## Draws the heckles of the leg he is taking. Returns the Twist the leg must
## be generated with ({} for none): { "modifier", "at" }. Call begin_leg()
## with the generated plan afterwards.
func plan_leg(rng: Rng, table: TableRules, guests: PackedStringArray, act: int, leg_id: String, modifier_id: String) -> Dictionary:
	_drop()
	planned = []
	said = 0
	_pool = pool(_data, table, guests, _guest_weight)
	var twist: Dictionary = {}
	if _pool.is_empty() or not _data.has_record("legs", leg_id):
		return twist
	var leg: Dictionary = _data.record("legs", leg_id)
	var allowed: Array = GameData.as_array(leg.get("modifiers_allowed"))
	var rainy: bool = GameData.as_string(leg.get("condition")) == "rain"
	var count: int = GameData.as_int(_per_leg[clampi(act, 1, _per_leg.size()) - 1])
	var taken: PackedStringArray = []
	var shower: bool = false
	for index: int in count:
		# The same three draws for every heckle, whatever this leg can take.
		var roll_record: float = rng.unit(Rng.HECKLE)
		var roll_place: float = rng.unit(Rng.HECKLE)
		var roll_other: float = rng.unit(Rng.HECKLE)
		var fitting: Array[Dictionary] = []
		for again: bool in [false, true]:
			for entry: Dictionary in _pool:
				var candidate: Dictionary = entry["record"]
				if not again and taken.has(GameData.as_string(candidate.get("id"))):
					continue
				if GameData.as_string(candidate.get("type")) == TWIST:
					var what: String = GameData.as_string(candidate.get("twist"))
					if what == SHOWER:
						if rainy or shower:
							continue
					elif not twist.is_empty() or what == modifier_id or not allowed.has(what):
						continue
				fitting.append(entry)
			if not fitting.is_empty():
				break
		if fitting.is_empty():
			continue
		var chosen: Dictionary = _weighted(fitting, roll_record)["record"]
		taken.append(GameData.as_string(chosen.get("id")))
		var share: float = lerpf(_span.x, _span.y, (float(index) + roll_place * 0.5) / float(count))
		var entry_planned: Dictionary = {"record": chosen, "share": share, "roll": roll_other}
		if GameData.as_string(chosen.get("type")) == TWIST:
			var what: String = GameData.as_string(chosen.get("twist"))
			if what == SHOWER:
				shower = true
			else:
				twist = {"modifier": what, "at": _twist_place(modifier_id, share)}
				entry_planned["stretch"] = true
		planned.append(entry_planned)
	return twist


## Where along the beats a Twist's stretch goes: ahead of where the heckle is
## due, and clear of the stretch of the leg's own modifier.
func _twist_place(modifier_id: String, share: float) -> float:
	if LegGenerator.ZONE_KINDS.has(modifier_id):
		var modifier: Dictionary = _data.record("modifiers", modifier_id)
		var own: float = GameData.as_float(modifier.get("at"), GameData.as_float(GameData.as_dict(modifier.get("flock")).get("at")))
		return 0.75 if own < 0.5 else 0.25
	return clampf(share + 0.15, 0.3, 0.7)


## The leg has been generated: where each heckle falls due, in metres. A
## Twist with a stretch is due heckle_lead before the first thing of it
## would come onto the road, at the fastest he can drive.
func begin_leg(plan: Dictionary) -> void:
	var beats_end: float = GameData.as_float(plan.get("beats_end"))
	var twist: Dictionary = GameData.as_dict(plan.get("twist"))
	var kept: Array[Dictionary] = []
	for entry: Dictionary in planned:
		if entry.has("stretch"):
			if twist.is_empty():
				# The generator could not lay it out: nothing is said of it.
				continue
			entry["due_s"] = maxf(GameData.as_float(twist.get("first_s")) - _lead * _top_ms, 0.0)
			entry["end_s"] = GameData.as_float(twist.get("end_s"))
		else:
			entry["due_s"] = GameData.as_float(entry["share"]) * beats_end
		kept.append(entry)
	kept.sort_custom(_by_due)
	planned = kept


static func _by_due(a: Dictionary, b: Dictionary) -> bool:
	return GameData.as_float(a["due_s"]) < GameData.as_float(b["due_s"])


## The leg is over (its end, or a stop): what was running lapses, and what
## was not said is not said.
func end_leg() -> void:
	if phase != NONE:
		_resolve(LAPSED, {})
	planned = []
	said = 0


## How many heckles this leg still owes.
func left() -> int:
	return planned.size() - said


func phase_name() -> String:
	return PHASE_NAMES[phase]


# --- One tick ------------------------------------------------------------------------

func begin_tick() -> void:
	in_ritual = &""
	nerves = 0.0
	cash = 0.0
	twist_begins = false
	shower_begins = 0.0
	events = []


## `s` is the car's progress along the leg; `free` whether a heckle may begin
## now (GDD 11.3: "Never during an encounter or a boss").
func step(dt: float, s: float, free: bool) -> void:
	_s = s
	match phase:
		NONE:
			if free and said < planned.size() and s >= GameData.as_float(planned[said]["due_s"]):
				_say(planned[said])
		LEAD:
			lead_left -= dt
			if lead_left < dt * 0.5:
				_open()
		OPEN:
			_step_open(dt)
	in_ritual = &""
	in_close_calls = 0
	in_passed = 0
	in_horn = false


func _say(entry: Dictionary) -> void:
	said += 1
	var chosen: Dictionary = entry["record"]
	if not _can_be_asked(chosen):
		chosen = _another(GameData.as_float(entry["roll"]))
		if chosen.is_empty():
			return
	record = chosen
	_until_s = GameData.as_float(entry.get("end_s"), INF)
	phase = LEAD
	lead_left = _lead
	var line: String = GameData.as_string(record.get("line_id"))
	events.append({"type": "sfx_requested", "id": "heckle"})
	events.append({"type": "line_requested", "id": line, "tell": true})
	events.append({
		"type": "heckle_started",
		"id": GameData.as_string(record.get("id")),
		"heckle": GameData.as_string(record.get("type")),
		"guest": GameData.as_string(record.get("guest")),
		"line": line,
		"lead": _lead,
		"window": GameData.as_float(record.get("window_s")),
	})


## An Order names a ritual: one he cannot perform now (the thing is not in
## the cabin, the glass is empty) is not asked of him.
func _can_be_asked(heckle: Dictionary) -> bool:
	if GameData.as_string(heckle.get("type")) != ORDER:
		return true
	return _items == null or _items.can_perform(GameData.as_string(heckle.get("ritual")))


## Another record of the pool in place of an Order that cannot be asked:
## another Order if one can be, else any challenge. Never a Twist: the road
## was laid out without it.
func _another(roll: float) -> Dictionary:
	for orders_only: bool in [true, false]:
		var fitting: Array[Dictionary] = []
		for entry: Dictionary in _pool:
			var candidate: Dictionary = entry["record"]
			var type: String = GameData.as_string(candidate.get("type"))
			if type == TWIST or (orders_only and type != ORDER):
				continue
			if _can_be_asked(candidate):
				fitting.append(entry)
		if not fitting.is_empty():
			return _weighted(fitting, roll)["record"]
	return {}


static func _weighted(entries: Array[Dictionary], roll: float) -> Dictionary:
	var total: float = 0.0
	for entry: Dictionary in entries:
		total += GameData.as_float(entry["weight"])
	var at: float = clampf(roll, 0.0, 1.0) * total
	for entry: Dictionary in entries:
		at -= GameData.as_float(entry["weight"])
		if at < 0.0:
			return entry
	return entries[entries.size() - 1]


## heckle_lead after the subtitle: the change, or the challenge, begins.
func _open() -> void:
	phase = OPEN
	lead_left = 0.0
	window_left = GameData.as_float(record.get("window_s"))
	_clock = 0.0
	_answers = []
	_keeps = []
	_passes = PackedFloat64Array()
	for token: Variant in GameData.as_array(record.get("answer")):
		_answers.append(parse_answer(GameData.as_string(token)))
	for token: Variant in GameData.as_array(record.get("keep")):
		_keeps.append(parse_keep(GameData.as_string(token)))
	_progress = PackedFloat64Array()
	_progress.resize(_answers.size())
	_progress.fill(0.0)
	match GameData.as_string(record.get("type")):
		TWIST:
			if GameData.as_string(record.get("twist")) == SHOWER:
				window_left = GameData.as_float(record.get("duration_s"))
				shower_begins = window_left
			else:
				window_left = INF
				twist_begins = true
		FIB:
			ghost_holds = true


func _step_open(dt: float) -> void:
	_clock += dt
	var type: String = GameData.as_string(record.get("type"))
	match type:
		TWIST:
			# Over when its stretch is behind him, or the rain has stopped.
			if _s >= _until_s:
				_resolve(OVER, {})
				return
		DARE, DOUBT:
			if _answered(dt):
				_resolve(PASSED, GameData.as_dict(record.get("pass")))
				return
		QUESTION:
			if not _kept():
				_resolve(FAILED, GameData.as_dict(record.get("fail")))
				return
		ORDER:
			if in_ritual != &"" and String(in_ritual) == GameData.as_string(record.get("ritual")):
				_resolve(PASSED, GameData.as_dict(record.get("pass")))
				return
	window_left -= dt
	if window_left < dt * 0.5:
		match type:
			TWIST, FIB:
				_resolve(OVER, {})
			QUESTION:
				_resolve(PASSED, GameData.as_dict(record.get("pass")))
			_:
				_resolve(FAILED, GameData.as_dict(record.get("fail")))


## Any one of the record's answers, given in this window.
func _answered(dt: float) -> bool:
	var passed: int = in_passed
	while passed > 0:
		passed -= 1
		_passes.append(_clock)
	var done: bool = false
	for index: int in _answers.size():
		var answer: Dictionary = _answers[index]
		var seconds: float = GameData.as_float(answer.get("seconds"))
		match GameData.as_string(answer.get("kind")):
			CLOSE_CALL:
				_progress[index] += float(in_close_calls)
				done = done or _progress[index] >= GameData.as_float(answer.get("count")) - 0.5
			GEAR:
				_progress[index] = _progress[index] + dt if in_gear == GameData.as_int(answer.get("gear")) else 0.0
				done = done or _progress[index] >= seconds - dt * 0.5
			HANDS_OFF:
				_progress[index] = _progress[index] + dt if not in_gripping and in_straight else 0.0
				done = done or _progress[index] >= seconds - dt * 0.5
			PASS:
				var within: int = 0
				for at: float in _passes:
					if _clock - at <= seconds:
						within += 1
				_progress[index] = float(within)
				done = done or within >= GameData.as_int(answer.get("count"))
	return done


## Everything the Question asks him to keep is kept this tick.
func _kept() -> bool:
	for keep: Dictionary in _keeps:
		match GameData.as_string(keep.get("kind")):
			NERVES_UNDER:
				if in_nerves >= GameData.as_float(keep.get("value")):
					return false
			NO_HORN:
				if in_horn:
					return false
	return true


func _resolve(outcome: String, effect: Dictionary) -> void:
	nerves += GameData.as_float(effect.get("nerves"))
	cash += GameData.as_float(effect.get("cash"))
	events.append({
		"type": "heckle_resolved",
		"id": GameData.as_string(record.get("id")),
		"heckle": GameData.as_string(record.get("type")),
		"outcome": outcome,
		"nerves": GameData.as_float(effect.get("nerves")),
		"cash": GameData.as_float(effect.get("cash")),
	})
	_drop()


func _drop() -> void:
	record = {}
	phase = NONE
	lead_left = 0.0
	window_left = 0.0
	ghost_holds = false
	_until_s = INF
	_answers = []
	_keeps = []


## What the HUD shows of a running challenge: the furthest any answer has
## come, 0 to 1 (a Question: the share of its window he has kept it for).
func progress() -> float:
	if phase != OPEN:
		return 0.0
	if GameData.as_string(record.get("type")) == QUESTION:
		var window: float = GameData.as_float(record.get("window_s"))
		return clampf(_clock / window, 0.0, 1.0) if window > 0.0 else 0.0
	var best: float = 0.0
	for index: int in _answers.size():
		var answer: Dictionary = _answers[index]
		var goal: float = GameData.as_float(answer.get("seconds"))
		if GameData.as_string(answer.get("kind")) == CLOSE_CALL or GameData.as_string(answer.get("kind")) == PASS:
			goal = GameData.as_float(answer.get("count"))
		if goal > 0.0:
			best = maxf(best, clampf(_progress[index] / goal, 0.0, 1.0))
	return best


# --- The words of a record -------------------------------------------------------------

## An answer, from its token (GDD 14 writes them "close_call", "gear4_5s"):
##   close_call            one close call          close_call_x3   three
##   gear4_5s              fourth gear held for 5 s
##   hands_off_3s          3 s with no hand on the wheel, on a straight
##   pass_x3_10s           three vehicles passed within 10 s
## {} for a token that says none of these.
static func parse_answer(token: String) -> Dictionary:
	var parts: PackedStringArray = token.split("_")
	var count: int = 1
	var seconds: float = 0.0
	while parts.size() > 1:
		var last: String = parts[parts.size() - 1]
		if last.begins_with("x") and last.substr(1).is_valid_int():
			count = last.substr(1).to_int()
		elif last.ends_with("s") and last.left(-1).is_valid_float():
			seconds = last.left(-1).to_float()
		else:
			break
		parts.remove_at(parts.size() - 1)
	var name: String = "_".join(parts)
	if name == CLOSE_CALL and seconds == 0.0 and count >= 1:
		return {"kind": CLOSE_CALL, "count": count}
	if name.begins_with(GEAR) and name.substr(GEAR.length()).is_valid_int() and seconds > 0.0 and count == 1:
		return {"kind": GEAR, "gear": name.substr(GEAR.length()).to_int(), "seconds": seconds}
	if name == HANDS_OFF and seconds > 0.0 and count == 1:
		return {"kind": HANDS_OFF, "seconds": seconds}
	if name == PASS and seconds > 0.0 and count >= 1:
		return {"kind": PASS, "count": count, "seconds": seconds}
	return {}


## What a Question asks him to keep, from its token:
##   nerves_under_50       Nerves below 50
##   no_horn               the horn is not sounded
static func parse_keep(token: String) -> Dictionary:
	if token == NO_HORN:
		return {"kind": NO_HORN}
	if token.begins_with(NERVES_UNDER + "_") and token.substr(NERVES_UNDER.length() + 1).is_valid_float():
		return {"kind": NERVES_UNDER, "value": token.substr(NERVES_UNDER.length() + 1).to_float()}
	return {}
