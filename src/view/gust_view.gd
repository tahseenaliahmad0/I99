class_name GustView
extends Node3D
## The tell of a gust (GDD 5.4): for the second before it pushes, streaks of
## dust blow across the road the way the car will be pushed. A child of
## RoadView: a road point (x, s) is at local (x, 0, -(s - car_s)). Reads the
## snapshot; changes nothing.

## Shares of one that spread the streaks evenly and never in rows: the
## golden ratio's, and two more that do not repeat with it.
const SPREAD_ALONG: float = 0.618034
const SPREAD_ACROSS: float = 0.381966
const SPREAD_UP: float = 0.754878

var _streaks: Array[Node3D] = []
var _tell: float = 1.0
var _near: float = 0.0
var _far: float = 0.0
var _across: float = 0.0
var _speed: float = 0.0
var _low: float = 0.0
var _high: float = 0.0
var _fog_near_share: float = 0.5


func setup(data: GameData, factory: PlaceholderFactory) -> void:
	var tuning: Tuning = data.tuning
	_tell = tuning.f("gust_tell")
	_near = tuning.fi("gust_streak_ahead", 0)
	_far = tuning.fi("gust_streak_ahead", 1)
	_across = tuning.f("gust_streak_across")
	_speed = tuning.f("gust_streak_speed")
	_low = tuning.fi("gust_streak_height", 0)
	_high = tuning.fi("gust_streak_height", 1)
	_fog_near_share = tuning.f("fog_near_share")
	for index: int in tuning.i("gust_streak_count"):
		var streak: Node3D = factory.make_world("road_gust_streak")
		streak.visible = false
		add_child(streak)
		_streaks.append(streak)


func apply(snapshot: Dictionary) -> void:
	var left: float = snapshot["gust_tell"]
	var direction: int = snapshot["gust_dir"]
	if left <= 0.0 or direction == 0:
		for streak: Node3D in _streaks:
			streak.visible = false
		return
	var car_x: float = snapshot["car_x"]
	var sight: float = snapshot["visibility"]
	# In dust they blow where he can still see them.
	var far: float = _far
	if is_finite(sight):
		far = clampf(sight * _fog_near_share, _near, _far)
	# Each crosses the middle of its band halfway through the tell.
	var blown: float = float(direction) * _speed * (_tell * 0.5 - left)
	for index: int in _streaks.size():
		var streak: Node3D = _streaks[index]
		var along: float = fposmod(float(index) * SPREAD_ALONG, 1.0)
		var across: float = fposmod(float(index) * SPREAD_ACROSS, 1.0) - 0.5
		var up: float = fposmod(float(index) * SPREAD_UP, 1.0)
		streak.visible = true
		streak.position = Vector3(car_x + across * _across + blown, lerpf(_low, _high, up), -lerpf(_near, far, along))
