class_name Collision
extends RefCounted
## Collisions and close calls (GDD 5.6, 5.7).
##
## A collision is the overlap of two rectangles in (s, x). Its class depends
## on closing speed: a scrape up to scrape_max_closing, a crash up to
## crash_max_closing, a head-on beyond that or with any oncoming vehicle.
## After a hit the car is pushed hit_pushback clear and cannot be hit again
## for hit_immunity.
##
## A close call is passing a vehicle with under close_call_gap of sideways
## gap and at least close_call_min_closing of closing speed, without contact,
## judged when the two stop overlapping along the road. It pays
## close_call_base_cash x the gear multiplier x the chain, double for oncoming
## vehicles. Each close call within chain_window of the last adds chain_step
## to the chain, up to chain_cap.
##
## This class finds hits and close calls and moves the car clear. DriveSim
## reads the result fields and passes lamps, Nerves, cash and the forced gear
## on to the systems that own them.

enum Hit { NONE, SCRAPE, CRASH, HEAD_ON }

## Seconds during which the car cannot be hit again.
var immunity_left: float = 0.0
## Close calls chained so far in the current run (0 for the first).
var chain: int = 0
## Seconds since the last close call.
var since_close_call: float = INF

# --- What happened this tick -------------------------------------------------
var hit: Hit = Hit.NONE
var hit_lamps: int = 0
var hit_nerves: float = 0.0
var hit_forces_gear: bool = false
## Id of the vehicle hit, or 0 for a guardrail or barrier.
var hit_vehicle_id: int = 0
var close_calls: int = 0
var close_call_cash: float = 0.0
var close_call_nerves: float = 0.0
## Chain multiplier of the last close call judged this tick.
var close_call_mult: float = 1.0
## Honk Nerves owed for passing a honking vehicle closely (a taxi).
var honk_nerves: float = 0.0

## Scales close-call cash (items); 1.0 with the starting cabin.
var cash_mult: float = 1.0
## Added to each close call's cash (Lucky note).
var cash_bonus: float = 0.0

var _scrape_max: float = 0.0
var _crash_max: float = 0.0
var _immunity: float = 0.0
var _pushback: float = 0.0
var _hit_lamps: PackedFloat64Array = PackedFloat64Array()
var _hit_nerves: PackedFloat64Array = PackedFloat64Array()
var _scrape_speed_loss: float = 0.0
var _cc_gap: float = 0.0
var _cc_min_closing: float = 0.0
var _cc_base_cash: float = 0.0
var _cc_nerves: float = 0.0
var _cc_oncoming_mult: float = 1.0
var _chain_window: float = 0.0
var _chain_step: float = 0.0
var _chain_cap: float = 1.0
var _gear_cash_mult: PackedFloat64Array = PackedFloat64Array()


func configure(tuning: Tuning) -> void:
	_scrape_max = tuning.f("scrape_max_closing")
	_crash_max = tuning.f("crash_max_closing")
	_immunity = tuning.f("hit_immunity")
	_pushback = tuning.f("hit_pushback")
	_hit_lamps = tuning.floats("hit_lamps")
	_hit_nerves = tuning.floats("hit_nerves")
	_scrape_speed_loss = tuning.f("scrape_speed_loss")
	_cc_gap = tuning.f("close_call_gap")
	_cc_min_closing = tuning.f("close_call_min_closing")
	_cc_base_cash = tuning.f("close_call_base_cash")
	_cc_nerves = tuning.f("close_call_nerves")
	_cc_oncoming_mult = tuning.f("close_call_oncoming_mult")
	_chain_window = tuning.f("chain_window")
	_chain_step = tuning.f("chain_step")
	_chain_cap = tuning.f("chain_cap")
	_gear_cash_mult = tuning.floats("gear_cash_mult")


func reset() -> void:
	immunity_left = 0.0
	chain = 0
	since_close_call = INF
	_clear_results()


## The class of a hit from its closing speed (km/h).
func classify(closing_kmh: float, oncoming: bool) -> Hit:
	if oncoming or closing_kmh > _crash_max:
		return Hit.HEAD_ON
	if closing_kmh > _scrape_max:
		return Hit.CRASH
	return Hit.SCRAPE


## The chain multiplier after `links` chained close calls.
func chain_multiplier(links: int) -> float:
	return minf(1.0 + _chain_step * float(links), _chain_cap)


## One tick: finds hits and close calls against every vehicle, and against
## the road's edges (car.edge_touched). `gear` is the engaged gear (0 neutral).
func step(dt: float, car: CarSim, traffic: TrafficSim, gear: int) -> void:
	_clear_results()
	immunity_left = maxf(immunity_left - dt, 0.0)
	since_close_call += dt

	if car.edge_touched != CarSim.EDGE_NONE and immunity_left <= 0.0:
		_register_hit(Hit.SCRAPE, 0)
		car.speed *= 1.0 - _scrape_speed_loss

	var car_half_length: float = car.length() * 0.5
	var car_half_width: float = car.half_width()
	for vehicle: TrafficSim.Vehicle in traffic.vehicles:
		var ds: float = vehicle.s - car.s
		var along: bool = absf(ds) < vehicle.half_length + car_half_length
		if not along:
			if vehicle.cc_overlap:
				_judge_close_call(vehicle, car, gear)
			continue
		var gap: float = absf(vehicle.x - car.x) - (vehicle.half_width + car_half_width)
		vehicle.cc_overlap = true
		vehicle.cc_min_gap = minf(vehicle.cc_min_gap, gap)
		if gap < 0.0:
			vehicle.cc_contact = true
			if immunity_left <= 0.0:
				_hit_vehicle(vehicle, car, ds, gap, car_half_length)


func _clear_results() -> void:
	hit = Hit.NONE
	hit_lamps = 0
	hit_nerves = 0.0
	hit_forces_gear = false
	hit_vehicle_id = 0
	close_calls = 0
	close_call_cash = 0.0
	close_call_nerves = 0.0
	close_call_mult = 1.0
	honk_nerves = 0.0


func _register_hit(kind: Hit, vehicle_id: int) -> void:
	hit = kind
	hit_vehicle_id = vehicle_id
	hit_lamps = int(_hit_lamps[kind - 1])
	hit_nerves = _hit_nerves[kind - 1]
	hit_forces_gear = kind != Hit.SCRAPE
	immunity_left = _immunity


func _hit_vehicle(vehicle: TrafficSim.Vehicle, car: CarSim, ds: float, gap: float, car_half_length: float) -> void:
	var oncoming: bool = vehicle.direction < 0
	var closing: float = absf(vehicle.closing_speed(car.speed))
	var kind: Hit = classify(closing, oncoming)
	_register_hit(kind, vehicle.id)

	# Push the car clear along the shallower overlap.
	var depth_x: float = -gap
	var depth_s: float = vehicle.half_length + car_half_length - absf(ds)
	if depth_x <= depth_s:
		var side: float = 1.0 if car.x >= vehicle.x else -1.0
		car.x += side * (depth_x + _pushback)
		car.v_lat = 0.0
	elif ds > 0.0:
		car.s -= depth_s + _pushback
	else:
		car.s += depth_s + _pushback

	if kind == Hit.SCRAPE:
		car.speed *= 1.0 - _scrape_speed_loss
	if oncoming:
		car.speed = 0.0
	elif ds > 0.0 and depth_x > depth_s:
		# He ran into the back of it: he is now no faster than it is.
		car.speed = minf(car.speed, vehicle.speed)


func _judge_close_call(vehicle: TrafficSim.Vehicle, car: CarSim, gear: int) -> void:
	var passed: bool = car.s > vehicle.s
	var closing: float = vehicle.closing_speed(car.speed)
	var close: bool = vehicle.cc_min_gap < _cc_gap
	if passed and close and not vehicle.cc_contact and closing >= _cc_min_closing:
		if since_close_call <= _chain_window:
			chain += 1
		else:
			chain = 0
		since_close_call = 0.0
		close_call_mult = chain_multiplier(chain)
		var gear_mult: float = 0.0
		if gear >= 1 and gear <= _gear_cash_mult.size():
			gear_mult = _gear_cash_mult[gear - 1]
		var pay: float = _cc_base_cash * gear_mult * close_call_mult * cash_mult
		if vehicle.direction < 0:
			pay *= _cc_oncoming_mult
		close_calls += 1
		close_call_cash += pay + cash_bonus
		close_call_nerves += _cc_nerves
		honk_nerves += vehicle.honk_nerves
	vehicle.cc_overlap = false
	vehicle.cc_min_gap = INF
	vehicle.cc_contact = false
