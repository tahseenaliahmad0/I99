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
## One contact, one hit. A vehicle that has hit the car cannot hit it again
## until the two no longer overlap along the road and the immunity has run
## out (the half metre the push itself opens does not end the contact).
##
## The car never stays inside a vehicle. An overlap that cannot be a hit (he
## is immune, or that vehicle has hit him in this contact) is undone every
## tick all the same: the car is moved out on the side it came from, with no
## lamp, no Nerves and no scrape. So no push is ever longer than hit_pushback
## plus one tick of motion.
##
## "Clear" is clear of everything. A push sideways must end outside every
## other vehicle and no nearer to a rail than a touch of the rail would leave
## the car. Where it cannot, the car is put along the road instead:
## hit_pushback behind the vehicle's rear bumper, or in front of it when the
## vehicle's middle is behind the car's. Behind a vehicle going his way he is
## no faster than it is.
##
## A close call is passing a vehicle with under close_call_gap of sideways
## gap and at least close_call_min_closing of closing speed, without contact,
## judged when the two stop overlapping along the road. It pays
## close_call_base_cash x the gear multiplier x the chain, double for oncoming
## vehicles. Each close call within chain_window of the last adds chain_step
## to the chain, up to chain_cap. A vehicle that honks at being passed closely
## (a taxi) does so on the same judgement, whatever the closing speed.
##
## This class finds hits, close calls and honks and moves the car clear.
## DriveSim reads the result fields and passes lamps, Nerves, cash and the
## forced gear on to the systems that own them.

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
## Honk Nerves owed for passing honking vehicles closely (taxis).
var honk_nerves: float = 0.0
## The part of honk_nerves that frays him (an angry honk, not a happy one).
var honk_frights: float = 0.0
## Ids of the vehicles that honked this tick, one entry per honk.
var honk_vehicle_ids: PackedInt32Array = PackedInt32Array()

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
	immunity_left -= dt
	if immunity_left < dt * 0.5:
		immunity_left = 0.0
	since_close_call += dt

	if car.edge_touched != CarSim.EDGE_NONE and immunity_left <= 0.0:
		_register_hit(Hit.SCRAPE, 0)
		car.speed *= 1.0 - _scrape_speed_loss

	var car_half_length: float = car.length() * 0.5
	var car_half_width: float = car.half_width()
	for vehicle: TrafficSim.Vehicle in traffic.vehicles:
		var along: bool = absf(vehicle.s - car.s) < vehicle.half_length + car_half_length
		if not along:
			# The contact with a vehicle that has hit him is not over while he
			# is immune: the push itself is what parted them.
			if vehicle.cc_overlap and not (vehicle.cc_hit and immunity_left > 0.0):
				_judge_pass(vehicle, car, gear)
			continue
		var gap: float = absf(vehicle.x - car.x) - (vehicle.half_width + car_half_width)
		vehicle.cc_overlap = true
		vehicle.cc_min_gap = minf(vehicle.cc_min_gap, gap)
		if gap < 0.0:
			vehicle.cc_contact = true
			if immunity_left <= 0.0 and not vehicle.cc_hit:
				_hit_vehicle(vehicle, car, traffic.vehicles)
			else:
				_hold_behind(car, _move_clear(vehicle, car, traffic.vehicles, false))


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
	honk_frights = 0.0
	honk_vehicle_ids = PackedInt32Array()


func _register_hit(kind: Hit, vehicle_id: int) -> void:
	hit = kind
	hit_vehicle_id = vehicle_id
	hit_lamps = int(_hit_lamps[kind - 1])
	hit_nerves = _hit_nerves[kind - 1]
	hit_forces_gear = kind != Hit.SCRAPE
	immunity_left = _immunity


func _hit_vehicle(vehicle: TrafficSim.Vehicle, car: CarSim, vehicles: Array[TrafficSim.Vehicle]) -> void:
	var oncoming: bool = vehicle.direction < 0
	var closing: float = absf(vehicle.closing_speed(car.speed))
	var kind: Hit = classify(closing, oncoming)
	_register_hit(kind, vehicle.id)
	vehicle.cc_hit = true

	var ahead: TrafficSim.Vehicle = _move_clear(vehicle, car, vehicles, true)
	if kind == Hit.SCRAPE:
		car.speed *= 1.0 - _scrape_speed_loss
	if oncoming:
		car.speed = 0.0
	else:
		# He ran into the back of it, or had no room beside it.
		_hold_behind(car, ahead)


# --- Moving the car clear ----------------------------------------------------

## Moves the car out of `vehicle`, which it overlaps, and returns the vehicle
## it is behind along the road afterwards (null when it was moved sideways or
## put in front).
##
## The shallower overlap is the side the car came from. Sideways, it is moved
## that way if the place is free. Along the road, or with no room at its
## side, it is put behind the vehicle's rear bumper, or in front of the
## vehicle when the vehicle's middle is behind the car's.
##
## A hit (`counted`) leaves hit_pushback of air. An overlap that is not a hit
## is only undone: the car is left touching the vehicle, so pressing on it is
## a slide along it and not a row of jumps. Put in front of a vehicle he is
## given hit_pushback either way: traffic follows what is ahead of it, not
## what it touches, and would push him on.
func _move_clear(vehicle: TrafficSim.Vehicle, car: CarSim, vehicles: Array[TrafficSim.Vehicle], counted: bool) -> TrafficSim.Vehicle:
	var half_width: float = car.half_width()
	var half_length: float = car.length() * 0.5
	# Every vehicle he is inside right now. Only this one is dealt with here;
	# the others have their own turn this tick and are not in this move's way.
	var inside: Array[TrafficSim.Vehicle] = []
	for other: TrafficSim.Vehicle in vehicles:
		if _overlaps(car, car.s, car.x, other):
			inside.append(other)
	var ds: float = vehicle.s - car.s
	var depth_x: float = vehicle.half_width + half_width - absf(vehicle.x - car.x)
	var depth_s: float = vehicle.half_length + half_length - absf(ds)
	if depth_x <= depth_s:
		var side: float = 1.0 if car.x >= vehicle.x else -1.0
		var air_beside: float = _pushback if counted else 0.0
		var target: float = _apart(vehicle.x, side, vehicle.half_width + half_width + air_beside)
		if _is_free(car, car.s, target, vehicles, inside):
			car.x = target
			# A hit stops him sideways; pressed on its side he cannot go into it.
			if counted or car.v_lat * side < 0.0:
				car.v_lat = 0.0
			return null

	# Along the road, on from one vehicle to the next until he stands free.
	# Where another vehicle is in the place the push ends, he stops against it
	# if he fits between the two, and is put beyond it if he does not.
	var back: bool = ds > 0.0
	var toward: float = -1.0 if back else 1.0
	var air: float = _pushback if counted or not back else 0.0
	var from: TrafficSim.Vehicle = vehicle
	for _hop: int in vehicles.size():
		var nearest: float = _apart(from.s, toward, from.half_length + half_length)
		car.s = _apart(from.s, toward, from.half_length + half_length + air)
		var blocker: TrafficSim.Vehicle = _vehicle_at(car, car.s, vehicles, inside)
		if blocker == null:
			break
		var against: float = _apart(blocker.s, -toward, blocker.half_length + half_length)
		if (against - nearest) * toward >= 0.0 and _vehicle_at(car, against, vehicles, inside) == null:
			car.s = against
			break
		from = blocker
	return from if back else null


## True when the car would stand free at (s, x): no nearer to a rail than a
## touch of the rail itself leaves it (hit_pushback), and in no vehicle but
## those of `except`.
func _is_free(car: CarSim, s: float, x: float, vehicles: Array[TrafficSim.Vehicle], except: Array[TrafficSim.Vehicle]) -> bool:
	if x - car.half_width() < car.left_limit_x() + _pushback or x + car.half_width() > car.guardrail_x() - _pushback:
		return false
	return _vehicle_at(car, s, vehicles, except, x) == null


## The first vehicle the car would overlap at `s` along the road (and at `x`
## across it; where it is now when `x` is not given), leaving out `except`.
## Null when there is none.
func _vehicle_at(car: CarSim, s: float, vehicles: Array[TrafficSim.Vehicle], except: Array[TrafficSim.Vehicle], x: float = NAN) -> TrafficSim.Vehicle:
	var at_x: float = car.x if is_nan(x) else x
	for other: TrafficSim.Vehicle in vehicles:
		if _overlaps(car, s, at_x, other) and not except.has(other):
			return other
	return null


## True when the car's rectangle, with its middle at (s, x), overlaps a vehicle's.
func _overlaps(car: CarSim, s: float, x: float, other: TrafficSim.Vehicle) -> bool:
	return absf(other.s - s) < other.half_length + car.length() * 0.5 and absf(other.x - x) < other.half_width + car.half_width()


## Behind a vehicle going his way he is no faster than it is: he cannot push
## it along, and what follows him must see his true speed (DECISIONS D-023).
func _hold_behind(car: CarSim, ahead: TrafficSim.Vehicle) -> void:
	if ahead != null and ahead.direction > 0:
		car.speed = minf(car.speed, ahead.speed)


## The place `reach` metres from `from` on its `toward` side (+1 or -1), never
## a rounding error nearer: two rectangles put that far apart must not read
## as overlapping on the next tick.
func _apart(from: float, toward: float, reach: float) -> float:
	var at: float = from + toward * reach
	var short: float = reach - absf(at - from)
	while absf(at - from) < reach:
		at += toward * short
		short *= 2.0
	return at


# --- Close calls -------------------------------------------------------------

## The two have stopped overlapping along the road. If that was a pass, it is
## judged; either way the vehicle's bookkeeping starts afresh, and a contact
## it had with the car is over.
func _judge_pass(vehicle: TrafficSim.Vehicle, car: CarSim, gear: int) -> void:
	var passed: bool = car.s > vehicle.s
	var close: bool = vehicle.cc_min_gap < _cc_gap
	if passed and close and not vehicle.cc_contact:
		if vehicle.honk_nerves != 0.0:
			honk_nerves += vehicle.honk_nerves
			honk_frights += maxf(vehicle.honk_nerves, 0.0)
			honk_vehicle_ids.append(vehicle.id)
		if vehicle.closing_speed(car.speed) >= _cc_min_closing:
			_count_close_call(vehicle, gear)
	vehicle.cc_overlap = false
	vehicle.cc_min_gap = INF
	vehicle.cc_contact = false
	vehicle.cc_hit = false


func _count_close_call(vehicle: TrafficSim.Vehicle, gear: int) -> void:
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
	# A happy honk (a wedding car, GDD 9.4) is instead of the close call's
	# Nerves, not on top of them.
	if vehicle.honk_nerves >= 0.0:
		close_call_nerves += _cc_nerves
