class_name IdealDriver
extends RefCounted
## The scripted ideal driver of T-WALL-01 (GDD 18.1): "A scripted ideal
## driver in gear 3 clears every generated leg with no contact."
##
## His script is the leg's own line: the way through that the generator
## kept open (GDD 9.2 rule 3, the plan's `path`). He holds third gear and
## puts the car on that line, tick by tick, in the real simulation: its
## car, its traffic, its hazards, its encounters. He looks at nothing and
## reacts to nothing. He does not brake for what is in front of him and
## does not wait for what is beside him: if the road is not open where the
## plan says it is, he drives into it, and the test fails.
##
## One thing is in his script besides the line: a stretch with a speed
## limit (Dawn's last checkpoint, GDD 10.4: "waves him through at 70
## km/h"). He brakes to the limit before it, takes the highest gear that
## keeps it, and takes third again where it ends.

const KMH_TO_MS: float = 1.0 / 3.6
const GEAR: int = 3

## Metres he drives beside his line (0: on it). For a test's failure case.
var offset: float = 0.0
## He takes the leg's side road, if it has one (the Motorcade's detour, GDD
## 9.3), and drives that road's own line.
var takes_side_road: bool = false

var _sim: DriveSim
var _tuning: Tuning
var _line: LegChecker
var _limit_from: float = INF
var _limit_to: float = INF
var _limit_kmh: float = INF
var _limit_gear: int = GEAR
var _side: LegChecker
var _side_at: float = INF
var _side_gore: float = INF
var _main_lanes: int = 3


func _init(sim: DriveSim, data: GameData) -> void:
	_sim = sim
	_tuning = data.tuning
	_line = LegChecker.new(data)
	_side = LegChecker.new(data)


## Takes the wheel for a stretch: third gear, on the plan's line.
func begin(plan: Dictionary) -> void:
	_line.load_plan(plan)
	_limit_from = INF
	_limit_to = INF
	_limit_kmh = INF
	_limit_gear = GEAR
	offset = 0.0
	takes_side_road = false
	_side_at = INF
	_side_gore = INF
	var detour: Dictionary = GameData.as_dict(GameData.as_dict(plan.get("motorcade")).get("detour"))
	if not detour.is_empty():
		_side.load_plan(detour)
		_side_at = GameData.as_float(detour.get("at"))
		_side_gore = _side_at + GameData.as_float(detour.get("slip"))
	_main_lanes = GameData.as_int(plan.get("lanes"), 3)
	_sim.gate.reset(GEAR)
	_sim.car.reset(GameData.as_int(plan.get("start_lane")), GEAR)


## From `from` to `to` along the road he may do `kmh` and no more.
func limit(from: float, to: float, kmh: float) -> void:
	_limit_from = from
	_limit_to = to
	_limit_kmh = kmh
	_limit_gear = 1
	for gear: int in range(1, GEAR + 1):
		if _tuning.fi("gear_speeds", gear - 1) <= kmh + 0.001:
			_limit_gear = gear


## Where across the road his line is at `s`.
func line_x(s: float) -> float:
	return _line.line_x(s)


## One tick, before the simulation's: the gear, the brake, and where the car
## is across the road.
func drive(input: DriveInput) -> void:
	input.rmb = false
	var car: CarSim = _sim.car
	if not _sim.leg.active:
		return
	if _sim.gate.gear != GEAR and _limit_from == INF:
		_sim.gate.reset(GEAR)
	if _sim.encounter.side_road == EncounterSim.SIDE_ROAD_TAKEN:
		car.x = _side.line_x(car.s - _side_gore)
		return
	if _sim.leg.on_side_road:
		return
	if takes_side_road and _sim.encounter.side_road != EncounterSim.SIDE_ROAD_BEHIND and car.s >= _side_at:
		# Across into the slip lane, which is one lane right of the road's last.
		car.x = lerpf(_line.line_x(car.s), car.lane_center(_main_lanes), clampf((car.s - _side_at) / (0.5 * (_side_gore - _side_at)), 0.0, 1.0))
		return
	var gear: int = GEAR
	if car.s >= _limit_from and car.s < _limit_to:
		gear = _limit_gear
		input.rmb = car.speed > _limit_kmh
	elif car.s < _limit_from and car.speed > _limit_kmh:
		# The brake goes on where it still gets him down to the limit, and
		# a tick's worth earlier.
		var over: float = (car.speed * car.speed - _limit_kmh * _limit_kmh) * KMH_TO_MS / (2.0 * _tuning.f("brake_decel"))
		input.rmb = _limit_from - car.s <= over + 2.0 * car.speed * KMH_TO_MS * DriveSim.DT
	if _sim.gate.gear != gear:
		_sim.gate.reset(gear)
	car.x = _line.line_x(car.s) + offset
