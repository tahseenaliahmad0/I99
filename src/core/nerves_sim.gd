class_name NervesSim
extends RefCounted
## Nerves (GDD 6.1, 5.8): one meter, 0 to 100. High is Frayed: he shakes.
## Low is Heavy: he falls asleep. Every impairment is a fixed, learnable
## change with a tell; none adds random noise.
##
##   100               Snap: he leans on the horn, can steer, cannot reach;
##                     Nerves reset to snap_reset
##   pound_from up     Pound: hand speed x hand_pound_mult
##   tunnel_from up    Tunnel: the view narrows
##   tremor_from up    Tremor: the gripped wheel oscillates
##   below the floor   Lids and Blink, unless Awake
##   nod_depth below   Nod, unless Awake
##
## DriveSim feeds it: add() for one-off changes, add_rate() for per-second
## sources, `awake` and the Heavy floor before each step. It reads the
## impairments back and turns the flags into events.

const MIN: float = 0.0
const MAX: float = 100.0

var value: float = 0.0

# --- Set by DriveSim before step() -------------------------------------------
## The Heavy floor now (act, Table, painkillers).
var heavy_floor: float = 0.0
## Awake suppresses Lids, Blink and Nod (GDD 6.1).
var awake: bool = false
## A lit cigarette: no Tremor.
var tremor_muted: bool = false
## Scales Tremor amplitude (painkillers, energy drink).
var tremor_scale: float = 1.0
## Scales every gain of Nerves (Courage).
var gain_mult: float = 1.0

# --- Impairments, read by DriveSim and the views -----------------------------
## Degrees the gripped wheel is off by right now.
var tremor_offset: float = 0.0
var tremor_amplitude: float = 0.0
## 0 to 1: how far the view has narrowed toward tunnel_min_view.
var tunnel: float = 0.0
var pound: bool = false
## Share of the screen each dark bar covers, 0 to lids_max.
var lids: float = 0.0
var eyes_shut: bool = false
var heavy: bool = false
var deep: bool = false
## Seconds left of a Snap.
var snap_left: float = 0.0

# --- What happened this tick -------------------------------------------------
var snapped: bool = false
var blinked: bool = false
var nodded: bool = false
var yawned: bool = false
var yawned_long: bool = false
var woke_from_nod: bool = false
## Names of thresholds crossed, each "+name" (on) or "-name" (off).
var crossed: PackedStringArray = PackedStringArray()

var _start: float = 0.0
var _tremor_from: float = 0.0
var _tunnel_from: float = 0.0
var _pound_from: float = 0.0
var _snap_at: float = 0.0
var _snap_reset: float = 0.0
var _snap_duration: float = 0.0
var _nod_depth: float = 0.0
var _nod_wake: float = 0.0
var _tremor_hz: float = 0.0
var _tremor_max: float = 0.0
var _blink_period: float = 0.0
var _blink_length: float = 0.0
var _blink_tell: float = 0.0
var _nod_period: float = 0.0
var _nod_length: float = 0.0
var _nod_tell: float = 0.0
var _lids_time: float = 0.0
var _lids_max: float = 0.0
var _empty_radius: float = 0.0
var _empty_rate: float = 0.0
var _traffic_radius: float = 0.0
var _traffic_rate: float = 0.0
var _traffic_cap: float = 0.0

var _rate: float = 0.0
var _tremor_phase: float = 0.0
var _blink_clock: float = 0.0
var _nod_clock: float = 0.0
var _nod_cancelled: bool = false
var _was_tremor: bool = false
var _was_tunnel: bool = false
var _was_pound: bool = false
var _was_heavy: bool = false
var _was_deep: bool = false


func configure(tuning: Tuning) -> void:
	_start = tuning.f("nerves_start")
	_tremor_from = tuning.f("tremor_from")
	_tunnel_from = tuning.f("tunnel_from")
	_pound_from = tuning.f("pound_from")
	_snap_at = tuning.f("snap_at")
	_snap_reset = tuning.f("snap_reset")
	_snap_duration = tuning.f("snap_duration")
	_nod_depth = tuning.f("nod_depth")
	_nod_wake = tuning.f("nod_wake_nerves")
	_tremor_hz = tuning.f("tremor_frequency")
	_tremor_max = tuning.f("tremor_max_amplitude")
	_blink_period = tuning.f("blink_period")
	_blink_length = tuning.f("blink_length")
	_blink_tell = tuning.f("blink_tell")
	_nod_period = tuning.f("nod_period")
	_nod_length = tuning.f("nod_length")
	_nod_tell = tuning.f("nod_tell")
	_lids_time = tuning.f("lids_close_time")
	_lids_max = tuning.f("lids_max")
	_empty_radius = tuning.f("empty_road_radius")
	_empty_rate = tuning.f("empty_road_rate")
	_traffic_radius = tuning.f("traffic_radius")
	_traffic_rate = tuning.f("traffic_rate")
	_traffic_cap = tuning.f("traffic_rate_cap")
	reset()


func reset() -> void:
	value = _start
	snap_left = 0.0
	lids = 0.0
	eyes_shut = false
	_rate = 0.0
	_tremor_phase = 0.0
	_blink_clock = 0.0
	_nod_clock = 0.0
	_nod_cancelled = false
	_refresh_impairments()
	_was_tremor = tremor_amplitude > 0.0
	_was_tunnel = tunnel > 0.0
	_was_pound = pound
	_was_heavy = heavy
	_was_deep = deep
	begin_tick()


## Clears the per-tick flags. DriveSim calls this at the start of its tick.
func begin_tick() -> void:
	snapped = false
	blinked = false
	nodded = false
	yawned = false
	yawned_long = false
	woke_from_nod = false
	crossed = PackedStringArray()
	_rate = 0.0


## A one-off change. Gains are scaled by gain_mult; reaching snap_at is a Snap.
func add(amount: float) -> void:
	if amount > 0.0:
		amount *= gain_mult
	value = clampf(value + amount, MIN, MAX)
	if value >= _snap_at:
		_snap()


## Sets Nerves outright (the tea stall).
func set_value(new_value: float) -> void:
	value = clampf(new_value, MIN, MAX)


## A per-second source for this tick (traffic, the radio, the shoulder...).
func add_rate(per_second: float) -> void:
	if per_second > 0.0:
		per_second *= gain_mult
	_rate += per_second


## The ambient rate of GDD 6.1 from the road: each vehicle within
## traffic_radius adds traffic_rate, up to traffic_rate_cap; an empty road
## (nothing within empty_road_radius, no encounter) gives empty_road_rate.
func road_rate(vehicles_near: int, nearest_distance: float, in_encounter: bool) -> float:
	if vehicles_near > 0:
		return minf(_traffic_rate * float(vehicles_near), _traffic_cap)
	if nearest_distance > _empty_radius and not in_encounter:
		return _empty_rate
	return 0.0


func traffic_radius() -> float:
	return _traffic_radius


## The rumble strip or any hit ends a Nod and adds nod_wake_nerves (GDD 5.8).
func jolt() -> void:
	if eyes_shut and deep and not _nod_cancelled:
		_nod_cancelled = true
		eyes_shut = false
		woke_from_nod = true
		add(_nod_wake)


func step(dt: float) -> void:
	if _rate != 0.0:
		value = clampf(value + _rate * dt, MIN, MAX)
		if value >= _snap_at:
			_snap()
	snap_left -= dt
	if snap_left < dt * 0.5:
		snap_left = 0.0
	_tremor_phase = fmod(_tremor_phase + TAU * _tremor_hz * dt, TAU)
	_refresh_impairments()
	_step_sleep(dt)
	_note_crossings()


func _snap() -> void:
	snapped = true
	value = _snap_reset
	snap_left = _snap_duration


func _refresh_impairments() -> void:
	var span: float = _snap_at - _tremor_from
	tremor_amplitude = 0.0
	if value >= _tremor_from and not tremor_muted and span > 0.0:
		tremor_amplitude = _tremor_max * (value - _tremor_from) / span * tremor_scale
	tremor_offset = tremor_amplitude * sin(_tremor_phase)
	tunnel = 0.0
	if value >= _tunnel_from and _snap_at > _tunnel_from:
		tunnel = clampf((value - _tunnel_from) / (_snap_at - _tunnel_from), 0.0, 1.0)
	pound = value >= _pound_from
	heavy = value < heavy_floor and not awake
	deep = heavy and value <= heavy_floor - _nod_depth


## Lids, Blink and Nod: fixed rhythms with a tell before each closing.
func _step_sleep(dt: float) -> void:
	var lid_rate: float = _lids_max / _lids_time if _lids_time > 0.0 else _lids_max
	if heavy:
		lids = minf(lids + lid_rate * dt, _lids_max)
	else:
		lids = maxf(lids - lid_rate * dt, 0.0)

	if not heavy:
		_blink_clock = 0.0
		_nod_clock = 0.0
		_nod_cancelled = false
		eyes_shut = false
		return

	if deep:
		_blink_clock = 0.0
		var before: float = _nod_clock
		_nod_clock += dt
		if _crossed_tell(before, _nod_clock, _nod_period, _nod_tell):
			yawned_long = true
		var shut: bool = _nod_clock >= _nod_period and fmod(_nod_clock, _nod_period) < _nod_length
		if shut and not eyes_shut and not _nod_cancelled:
			nodded = true
		if not shut:
			_nod_cancelled = false
		eyes_shut = shut and not _nod_cancelled
	else:
		_nod_clock = 0.0
		_nod_cancelled = false
		var before: float = _blink_clock
		_blink_clock += dt
		if _crossed_tell(before, _blink_clock, _blink_period, _blink_tell):
			yawned = true
		var shut: bool = _blink_clock >= _blink_period and fmod(_blink_clock, _blink_period) < _blink_length
		if shut and not eyes_shut:
			blinked = true
		eyes_shut = shut


## True when the clock passed the moment `tell` seconds before a closing.
func _crossed_tell(before: float, after: float, period: float, tell: float) -> bool:
	var shifted_before: float = before + tell
	var shifted_after: float = after + tell
	if shifted_after < period:
		return false
	return floorf(shifted_after / period) > floorf(shifted_before / period)


func _note_crossings() -> void:
	_was_tremor = _note("tremor", _was_tremor, value >= _tremor_from)
	_was_tunnel = _note("tunnel", _was_tunnel, value >= _tunnel_from)
	_was_pound = _note("pound", _was_pound, pound)
	_was_heavy = _note("heavy", _was_heavy, heavy)
	_was_deep = _note("nod", _was_deep, deep)


func _note(name: String, was: bool, now: bool) -> bool:
	if now != was:
		crossed.append(("+" if now else "-") + name)
	return now
