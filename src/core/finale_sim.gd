class_name FinaleSim
extends RefCounted
## The finale, "One Hand" (GDD 10.6). "There is no driving and no failure."
##
##   1. Guests clap a steady rhythm. Noor raises her palm.
##   2. The pointer is his hand. Each TAP on her palm is a clap, and the
##      room's clapping doubles with it. After 8 claps she takes his hand.
##   3. Holding the left button holds her hand. The camera walks them to the
##      groom over 10 s and stops.
##   4. Nothing happens until the player releases the button. There is no
##      prompt and no timer. At 20 s she says "Baba." At 90 s the room
##      starts clapping softly again.
##   5. On release her hand goes to the groom's.
##
## The only thing that ends it is letting go of her hand in front of the
## groom (GDD 18.1, T-FINALE-01). Letting go on the way there ends nothing:
## she waits, her hand out, and the walk goes on when he takes it again
## (D-063).

## Her palm is raised; he claps against it.
const CLAPPING: int = 0
## She has taken his hand, or holds hers out for it: the walk to the groom.
const WALKING: int = 1
## They stand in front of the groom, her hand in his.
const STANDING: int = 2
## He has let go.
const OVER: int = 3
const PHASE_NAMES: PackedStringArray = ["clapping", "walking", "standing", "over"]

var phase: int = CLAPPING
## Claps against her palm so far.
var claps: int = 0
## Her hand is in his now.
var holding: bool = false
## Seconds of the walk that are behind them.
var walked: float = 0.0
## Seconds they have stood in front of the groom, her hand in his.
var stood: float = 0.0
## She has said "Baba."
var said_baba: bool = false
## The room has begun to clap softly again.
var clapping_again: bool = false
## Seconds since the finale began.
var time: float = 0.0

# --- What happened this tick -------------------------------------------------
var events: Array[Dictionary] = []

var _claps_needed: int = 0
var _walk: float = 0.0
var _baba: float = 0.0
var _clap_again: float = 0.0
var _was_down: bool = false


func configure(tuning: Tuning) -> void:
	_claps_needed = tuning.i("finale_claps")
	_walk = tuning.f("finale_walk_s")
	_baba = tuning.f("finale_baba_s")
	_clap_again = tuning.f("finale_clap_again_s")


func begin() -> void:
	phase = CLAPPING
	claps = 0
	holding = false
	walked = 0.0
	stood = 0.0
	said_baba = false
	clapping_again = false
	time = 0.0
	_was_down = false
	events = []


func phase_name() -> String:
	return PHASE_NAMES[phase]


func over() -> bool:
	return phase == OVER


## How far along the walk to the groom they are, 0 to 1.
func walk_share() -> float:
	return clampf(walked / _walk, 0.0, 1.0) if _walk > 0.0 else 1.0


## How loud the room claps, in doublings of the guests' steady rhythm: one
## for each clap of his (GDD 10.6: "the room's clapping doubles with it").
func room_doublings() -> int:
	return claps


## One tick. `down` is the left button; `on_palm` whether the pointer, his
## hand, is on her raised palm.
func step(dt: float, down: bool, on_palm: bool) -> void:
	events = []
	if phase == OVER:
		return
	time += dt
	var pressed: bool = down and not _was_down
	_was_down = down
	match phase:
		CLAPPING:
			if pressed and on_palm:
				claps += 1
				events.append({"type": "sfx_requested", "id": "clap", "claps": claps})
				if claps >= _claps_needed:
					# "After 8 claps she takes his hand."
					phase = WALKING
					holding = true
		WALKING:
			# Her hand is in his while the button is down. Let go, she holds
			# hers out and waits.
			holding = down
			if holding:
				walked += dt
				if walked >= _walk - dt * 0.5:
					walked = _walk
					phase = STANDING
		STANDING:
			if not down:
				# "On release her hand goes to the groom's."
				holding = false
				phase = OVER
				events.append({"type": "line_requested", "id": "finale.proverb"})
				return
			stood += dt
			if not said_baba and stood >= _baba - dt * 0.5:
				said_baba = true
				events.append({"type": "line_requested", "id": "finale.baba"})
			if not clapping_again and stood >= _clap_again - dt * 0.5:
				clapping_again = true
				events.append({"type": "sfx_requested", "id": "clap", "soft": true})


## What a view shows of it.
func snapshot() -> Dictionary:
	return {
		"phase": phase_name(),
		"claps": claps,
		"claps_needed": _claps_needed,
		"holding": holding,
		"walk": walk_share(),
		"stood": stood,
		"said_baba": said_baba,
		"clapping_again": clapping_again,
		"room_doublings": room_doublings(),
		"over": over(),
	}
