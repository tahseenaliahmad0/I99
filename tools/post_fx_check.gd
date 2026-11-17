extends SceneTree
## A check of the post effects that needs no renderer (GDD 16.4):
##
##   - the shader declares the nine uniforms the GDD names, and the view
##     gives the shader every uniform it declares;
##   - each of the nine follows its key of the snapshot, and with nothing to
##     show the full-screen rectangle is not drawn at all;
##   - a Night leg and a Rain leg of the real simulation come out as
##     darkness and as blur;
##   - no effect flashes faster than three times a second: whatever a
##     snapshot key is thrown between, the uniform it drives turns back at
##     most six times in any second.
##
##   godot --headless --path . --script res://tools/post_fx_check.gd
##
## It builds a PostFX node as the drive scene does and feeds it the snapshot
## of a DriveSim, mostly with keys set by hand. The numbers are those of the
## data files.

const SHADER_PATH: String = "res://shaders/post_fx.gdshader"
const SCREEN_TEXTURE: String = "screen_texture"
## The uniforms of GDD 16.4 and their types in the shader.
const NINE: Dictionary = {
	"tunnel": "float", "lids": "float", "blink": "float", "haze": "float", "rain_blur": "float",
	"cracks": "float", "glare_amount": "float", "glare_position": "vec2", "darkness": "float",
}
const FRAME: float = 1.0 / 60.0
## Frames after which every effect has settled, and frames a flicker is kept up.
const SETTLE_FRAMES: int = 60
const FLICKER_FRAMES: int = 600
## A snapshot key is thrown from one value to the other every so many frames.
const FLICKER_PERIODS: PackedInt32Array = [1, 2, 3, 5, 8, 13, 21]
## Turns a second that are three flashes a second.
const MOST_TURNS: int = 6
const TOLERANCE: float = 0.0001

var _data: GameData
var _base: Dictionary = {}
var _checks: int = 0
var _failures: PackedStringArray = []


func _initialize() -> void:
	_data = GameData.load_from()
	var tuning: Tuning = _data.tuning
	_base = DriveSim.new(_data).snapshot()
	var lids_max: float = tuning.f("lids_max")
	var haze_cap: float = tuning.f("haze_cap")
	var night: float = tuning.f("postfx_night_darkness")
	var cone: float = tuning.f("low_beam_cone")
	var cracked: float = GameData.as_float(GameData.as_dict(_data.record("faults", "cracked_windscreen").get("params")).get("cracks"))
	var spotlight: float = GameData.as_float(GameData.as_dict(_data.record("legs", "motorcade").get("special")).get("glare"))
	var shades: float = _passive("sunglasses", "takes", "night_darker")

	# The shader takes the nine uniforms, and is given all it declares.
	var code: String = (load(SHADER_PATH) as Shader).code
	for uniform_name: String in NINE:
		var declared: RegEx = RegEx.new()
		declared.compile("(?m)^uniform\\s+%s\\s+%s\\b" % [str(NINE[uniform_name]), uniform_name])
		_check(declared.search(code) != null, "the shader declares `uniform %s %s`" % [str(NINE[uniform_name]), uniform_name])
	var any_uniform: RegEx = RegEx.new()
	any_uniform.compile("(?m)^uniform\\s+\\w+\\s+(\\w+)")
	var probe: PostFxView = _fx()
	probe.apply(_snapshot({"tunnel": 1.0}), FRAME)
	for found: RegExMatch in any_uniform.search_all(code):
		var uniform_name: String = found.get_string(1)
		if uniform_name != SCREEN_TEXTURE:
			_check(probe.shown(StringName(uniform_name)) != null, "the view gives the shader its `%s`" % uniform_name)
	probe.free()

	# Each of the nine follows its key of the snapshot.
	_check(not _visible_after({}), "with nothing to show the rectangle is not drawn")
	_follows("tunnel", {"tunnel": 1.0}, 1.0)
	_follows("lids", {"lids": lids_max}, lids_max)
	_follows("blink", {"eyes_shut": true}, 1.0)
	_follows("haze", {"haze": haze_cap}, haze_cap)
	_follows("rain_blur", {"raining": true, "rain_blur": 1.0}, 1.0)
	_follows("cracks", {"cracks": cracked}, cracked)
	_follows("glare_amount", {"glare": spotlight}, spotlight)
	_follows("darkness", {"night": true, "visibility": cone, "headlight_cone": cone}, night)
	_follows("darkness", {"night": true, "night_darker": shades, "visibility": cone, "headlight_cone": cone}, 1.0 - (1.0 - night) * (1.0 - shades))

	# The light is where the snapshot says: the sun to its side while it is
	# up, a place given outright before all else; otherwise straight ahead.
	var sun_up: Dictionary = {"glare": spotlight, PostFxView.SUN_KEY: spotlight, PostFxView.SUN_SIDE_KEY: -0.5}
	var sun_down: Dictionary = {"glare": spotlight, PostFxView.SUN_KEY: 0.0, PostFxView.SUN_SIDE_KEY: -0.5}
	var placed: Dictionary = sun_up.duplicate()
	placed[PostFxView.GLARE_POSITION_KEY] = Vector2(20.0, -10.0)
	var ahead: Vector2 = _glare_at({"glare": spotlight})
	var at_sun: Vector2 = _glare_at(sun_up)
	var at_place: Vector2 = _glare_at(placed)
	_check(ahead.is_equal_approx(Vector2(0.5, 0.5)), "with no key the light is straight ahead (found %s)" % str(ahead))
	_check(at_sun.x < 0.5 and at_sun.y < 0.5, "the sun on his left is left of the middle and above it (found %s)" % str(at_sun))
	_check(_glare_at(sun_down).is_equal_approx(ahead), "with the sun not up its side counts for nothing")
	_check(at_place.x > 0.5 and at_place.y > 0.5, "a place given outright, right and low, is believed before the sun's (found %s)" % str(at_place))

	# The real simulation: a Night leg behind sunglasses, a Rain leg unwiped.
	_check(shades > 0.0, "the sunglasses make the night darker")
	_leg_shows("night", 2, &"sunglasses", &"darkness", 1.0 - (1.0 - night) * (1.0 - shades), 1.0)
	_leg_shows("rain", 1, &"", &"rain_blur", 1.0, tuning.f("wiper_clear_time") + 1.0)

	# No effect flashes faster than three times a second.
	var most: int = floori(1.0 / maxf(tuning.f("postfx_flash_hold"), FRAME)) + 1
	_check(most <= MOST_TURNS, "postfx_flash_hold allows at most six turns a second (%d)" % most)
	_flickers("tunnel", "tunnel", 0.0, 1.0)
	_flickers("lids", "lids", 0.0, lids_max)
	_flickers("blink", "eyes_shut", false, true)
	_flickers("haze", "haze", 0.0, haze_cap)
	_flickers("rain_blur", "rain_blur", 0.0, 1.0, {"raining": true})
	_flickers("cracks", "cracks", 0.0, cracked)
	_flickers("glare_amount", "glare", 0.0, spotlight)
	_flickers("darkness", "night", false, true)
	_flickers("rain", "raining", false, true)

	for failure: String in _failures:
		print("POSTFX FAIL %s" % failure)
	print("post fx check: %d checks, %d failure(s)" % [_checks, _failures.size()])
	quit(1 if not _failures.is_empty() else 0)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(what)


## What an item changes by being there (items.json: a `passive` entry).
func _passive(item_id: String, side: String, key: String) -> float:
	for entry: Variant in GameData.as_array(_data.record("items", item_id).get(side)):
		var change: Dictionary = GameData.as_dict(entry)
		if GameData.as_string(change.get("passive")) == key:
			return GameData.as_float(change.get("amount"))
	return 0.0


func _fx() -> PostFxView:
	var fx: PostFxView = PostFxView.new()
	fx.setup(_data, null, null)
	return fx


func _snapshot(by_hand: Dictionary) -> Dictionary:
	var snapshot: Dictionary = _base.duplicate()
	snapshot.merge(by_hand, true)
	return snapshot


func _visible_after(by_hand: Dictionary) -> bool:
	var fx: PostFxView = _fx()
	for frame: int in SETTLE_FRAMES:
		fx.apply(_snapshot(by_hand), FRAME)
	var drawn: bool = (fx.get_node(PostFxView.SCREEN_NODE) as CanvasItem).visible
	fx.free()
	return drawn


func _follows(uniform_name: StringName, by_hand: Dictionary, expected: float) -> void:
	var fx: PostFxView = _fx()
	for frame: int in SETTLE_FRAMES:
		fx.apply(_snapshot(by_hand), FRAME)
	var found: float = GameData.as_float(fx.shown(uniform_name))
	var drawn: bool = (fx.get_node(PostFxView.SCREEN_NODE) as CanvasItem).visible
	_check(absf(found - expected) <= TOLERANCE, "%s is %s with %s (found %s)" % [uniform_name, str(expected), str(by_hand), str(found)])
	_check(drawn, "and the rectangle is drawn")
	# And it goes back to nothing.
	for frame: int in SETTLE_FRAMES:
		fx.apply(_snapshot({}), FRAME)
	_check(GameData.as_float(fx.shown(uniform_name)) == 0.0, "%s is 0 again without it" % uniform_name)
	fx.free()


func _glare_at(by_hand: Dictionary) -> Vector2:
	var fx: PostFxView = _fx()
	fx.apply(_snapshot(by_hand), FRAME)
	var at: Variant = fx.shown(&"glare_position")
	fx.free()
	if at is Vector2:
		return at
	return Vector2.INF


## Drives a leg of the real simulation for `seconds`, hands off, and checks
## what the effects make of its snapshots.
func _leg_shows(leg_id: String, act: int, item: StringName, uniform_name: StringName, expected: float, seconds: float) -> void:
	var sim: DriveSim = DriveSim.new(_data)
	sim.rng.reseed(1)
	sim.begin_leg(LegGenerator.generate(_data, leg_id, act, 1, ""))
	if item != &"":
		_check(sim.give_item(item) != null, "%s is in the cabin" % item)
	var fx: PostFxView = _fx()
	var input: DriveInput = DriveInput.new()
	var ticks_per_frame: int = roundi(FRAME * float(DriveSim.TICKS_PER_SECOND))
	for frame: int in roundi(seconds / FRAME):
		for tick: int in ticks_per_frame:
			input.clear()
			sim.step(input)
		fx.apply(sim.snapshot(), FRAME)
	var found: float = GameData.as_float(fx.shown(uniform_name))
	_check(absf(found - expected) <= TOLERANCE, "a %s leg shows %s %s (found %s)" % [leg_id, uniform_name, str(expected), str(found)])
	fx.free()


## Throws `key` between `low` and `high` every few frames and counts how
## often the uniform turns back: never more than six times in any second.
func _flickers(uniform_name: StringName, key: String, low: Variant, high: Variant, with: Dictionary = {}) -> void:
	var worst: int = 0
	var swing: float = 0.0
	var second: int = roundi(1.0 / FRAME)
	for period: int in FLICKER_PERIODS:
		var fx: PostFxView = _fx()
		var turns: PackedInt32Array = []
		var last: float = 0.0
		var heading: float = 0.0
		for frame: int in FLICKER_FRAMES:
			var by_hand: Dictionary = with.duplicate()
			by_hand[key] = high if frame % (2 * period) < period else low
			fx.apply(_snapshot(by_hand), FRAME)
			var now: float = GameData.as_float(fx.shown(uniform_name))
			var moved: float = signf(now - last)
			if moved != 0.0:
				if heading != 0.0 and moved != heading:
					turns.append(frame)
				heading = moved
			swing = maxf(swing, absf(now - last))
			last = now
		fx.free()
		# The most turns inside any one second.
		for index: int in turns.size():
			var inside: int = 0
			for other: int in range(index, turns.size()):
				if turns[other] - turns[index] < second:
					inside += 1
			worst = maxi(worst, inside)
	_check(worst <= MOST_TURNS, "%s turns back at most six times a second when '%s' flickers (found %d)" % [uniform_name, key, worst])
	_check(swing > 0.0, "%s does answer '%s'" % [uniform_name, key])
