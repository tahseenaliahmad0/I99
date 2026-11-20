extends SceneTree
## A check of the post effects that needs no renderer (GDD 16.4):
##
##   - the shader declares the nine uniforms the GDD names, and the view
##     gives the shader every uniform it declares;
##   - each of the nine follows its key of the snapshot, and with nothing to
##     show the full-screen rectangle is not drawn at all;
##   - a Night leg and a Rain leg of the real simulation come out as
##     darkness and as blur;
##   - the bosses of the real simulation (GDD 10.3, 10.4): Dawn's low sun is
##     a wash ahead and to the left, gone while his visor is down and back
##     when it is up, and it fades where it was when the road ends; the
##     Storm's smear on the glass is dust by day and by night, and a Night
##     storm is dark outside a pool that the dust does not shrink;
##   - the sun stands in the windscreen, where the lowered visor covers it;
##   - no effect flashes faster than three times a second: whatever a
##     snapshot key is thrown between, the uniform it drives turns back at
##     most six times in any second.
##
##   godot --headless --path . --script res://tools/post_fx_check.gd
##
## It builds a PostFX node as the drive scene does and feeds it the snapshot
## of a DriveSim: with keys set by hand for the nine one by one, as the
## simulation gives it for the legs and the bosses. The numbers are those of
## the data files.

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
## A boss's road is begun in third gear, the gear of par, with the tool's seed.
const BOSS_GEAR: int = 3
const BOSS_SEED: int = 1
const KMH_TO_MS: float = 1.0 / 3.6

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

	# The bosses of the real simulation, and what they are made of.
	_dawn_shows()
	_storm_shows()
	_night_storm_shows()
	_haze_is_made_of()
	_sun_is_behind_the_visor()

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
	var at: Vector2 = _light_at(fx)
	fx.free()
	return at


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


## A boss of the real simulation, begun by itself as the drive scene begins
## a leg: in third gear.
func _boss(boss_id: String, modifier: String = "") -> DriveSim:
	var sim: DriveSim = DriveSim.new(_data)
	sim.rng.reseed(BOSS_SEED)
	sim.gate.reset(BOSS_GEAR)
	sim.begin_boss(boss_id, modifier, BOSS_SEED)
	return sim


## Drives `sim` for `seconds` with nobody at the wheel, the car kept on the
## line it is on, and hands the effects the snapshot of every frame.
func _drive(sim: DriveSim, fx: PostFxView, seconds: float) -> void:
	var input: DriveInput = DriveInput.new()
	var line: float = sim.car.x
	var ticks_per_frame: int = roundi(FRAME * float(DriveSim.TICKS_PER_SECOND))
	for frame: int in roundi(seconds / FRAME):
		for tick: int in ticks_per_frame:
			input.clear()
			sim.step(input)
			sim.car.x = line
		fx.apply(sim.snapshot(), FRAME)


## Puts the car `at` metres along the road it is on: what the road held
## before that point is behind him.
func _put(sim: DriveSim, at: float) -> void:
	sim.car.s = at
	sim.leg.fast_forward(at, at / (_data.tuning.fi("gear_speeds", BOSS_GEAR - 1) * KMH_TO_MS))


func _amount(fx: PostFxView, uniform_name: StringName) -> float:
	return GameData.as_float(fx.shown(uniform_name))


func _drawn(fx: PostFxView) -> bool:
	return (fx.get_node(PostFxView.SCREEN_NODE) as CanvasItem).visible


func _light_at(fx: PostFxView) -> Vector2:
	var at: Variant = fx.shown(&"glare_position")
	if at is Vector2:
		return at
	return Vector2.INF


func _is_color(found: Variant, expected: Color) -> bool:
	if found is Color:
		var color: Color = found
		return color.is_equal_approx(expected)
	return false


## Dawn (GDD 10.4) by the real simulation: nothing dazzles him in the false
## dawn; past the sunrise the low sun is a wash of its strength, ahead and to
## the left; his visor down takes the wash away and leaves the light where
## the sun is; the visor up again brings it back; and when the road ends,
## what is left of the wash fades where the sun stood.
func _dawn_shows() -> void:
	var record: Dictionary = _data.record("bosses", BossSim.DAWN)
	var dawn: Dictionary = GameData.as_dict(record.get(BossSim.DAWN))
	var full: float = GameData.as_float(dawn.get("glare"))
	var risen: float = GameData.as_float(dawn.get("sunrise_at_m")) + GameData.as_float(dawn.get("glare_ramp_m"))
	var sim: DriveSim = _boss(BossSim.DAWN)
	var fx: PostFxView = _fx()
	_drive(sim, fx, 1.0)
	_check(_amount(fx, &"glare_amount") == 0.0, "in Dawn's false dawn nothing dazzles him")
	_check(not _drawn(fx), "and the rectangle is not drawn")

	_put(sim, risen)
	_drive(sim, fx, 1.0)
	var shot: Dictionary = sim.snapshot()
	var sun_at: Vector2 = _light_at(fx)
	_check(GameData.as_float(shot[PostFxView.SUN_KEY]) > 0.0 and GameData.as_float(shot[PostFxView.SUN_SIDE_KEY]) < 0.0,
			"(past the sunrise the snapshot has the sun up, on his left)")
	_check(absf(_amount(fx, &"glare_amount") - full) <= TOLERANCE, "Dawn's sun is a wash of its strength, %s (found %s)" % [str(full), str(_amount(fx, &"glare_amount"))])
	_check(sun_at.x > 0.0 and sun_at.x < 0.5 and sun_at.y > 0.0 and sun_at.y < 0.5, "ahead and to the left, above the horizon (found %s)" % str(sun_at))

	# His visor, as the ritual at it flips it down (GDD 4.6).
	sim.items.complete(_data.record("rituals", "visor_photo"), 0)
	_drive(sim, fx, 1.0)
	shot = sim.snapshot()
	_check(GameData.as_bool(shot["visor_down"]) and GameData.as_float(shot[PostFxView.SUN_KEY]) > 0.0, "(his visor is down and the sun still up)")
	_check(_amount(fx, &"glare_amount") == 0.0, "with his visor down the wash is gone (found %s)" % str(_amount(fx, &"glare_amount")))
	_check(_light_at(fx).is_equal_approx(sun_at), "and the light is still where the sun is")
	_drive(sim, fx, _data.tuning.f("visor_time"))
	_check(not GameData.as_bool(sim.snapshot()["visor_down"]), "(the visor is up again)")
	_check(absf(_amount(fx, &"glare_amount") - full) <= TOLERANCE, "and the wash is back (found %s)" % str(_amount(fx, &"glare_amount")))

	# The end of Dawn's road: the sun goes out with it, at once.
	_put(sim, GameData.as_float(record.get("length_m")) - 1.0)
	for frame: int in SETTLE_FRAMES:
		if not sim.boss.active:
			break
		_drive(sim, fx, FRAME)
	shot = sim.snapshot()
	_check(GameData.as_float(shot[PostFxView.SUN_KEY]) == 0.0 and GameData.as_float(shot["glare"]) == 0.0, "(Dawn's road has ended: no sun, no Glare)")
	_check(_amount(fx, &"glare_amount") > 0.0 and _light_at(fx).is_equal_approx(sun_at), "what is left of the wash fades where the sun stood (found %s at %s)" % [str(_amount(fx, &"glare_amount")), str(_light_at(fx))])
	_drive(sim, fx, 1.0)
	_check(_amount(fx, &"glare_amount") == 0.0 and not _drawn(fx), "and then it is gone")
	fx.free()

	# Early sun: the same wash from the first metres of the false dawn.
	sim = _boss(BossSim.DAWN, "early_sun")
	fx = _fx()
	_drive(sim, fx, GameData.as_float(dawn.get("glare_ramp_m")) / (_data.tuning.fi("gear_speeds", BOSS_GEAR - 1) * KMH_TO_MS) + 1.0)
	_check(GameData.as_int(sim.snapshot()["dawn_phase"]) == BossSim.FALSE_DAWN, "(Early sun: he is still in the false dawn)")
	_check(absf(_amount(fx, &"glare_amount") - full) <= TOLERANCE and _light_at(fx).is_equal_approx(sun_at),
			"with Early sun the wash is there from the false dawn, in the same place (found %s at %s)" % [str(_amount(fx, &"glare_amount")), str(_light_at(fx))])
	fx.free()


## The Storm (GDD 10.3) by the real simulation, by day: with clean glass the
## effects draw nothing (the dust in the air is the world's own haze); what
## his wipers smear on the glass is a veil of that much Haze, and it is dust,
## in thin dust and in thick.
func _storm_shows() -> void:
	var storm: Dictionary = GameData.as_dict(_data.record("bosses", BossSim.STORM).get(BossSim.STORM))
	var smear: float = GameData.as_float(storm.get("wipe_haze"))
	var dust: Color = Color.html(_data.tuning.s("sky_color_dust"))
	var sim: DriveSim = _boss(BossSim.STORM)
	var fx: PostFxView = _fx()
	_drive(sim, fx, 1.0)
	var shot: Dictionary = sim.snapshot()
	_check(is_finite(GameData.as_float(shot["visibility"])) and not GameData.as_bool(shot["night"]), "(by day the Storm's dust ends his view)")
	_check(not _drawn(fx), "in the Storm by day, with clean glass, nothing is drawn: the dust in the air is the world's")
	for sweep: int in 3:
		sim.items.complete(_data.record("rituals", "wipers"), 0)
	_drive(sim, fx, 1.0)
	var haze: float = GameData.as_float(sim.snapshot()["haze"])
	_check(haze > 2.0 * smear, "(three sweeps of his wipers have smeared the glass: Haze %s)" % str(haze))
	_check(absf(_amount(fx, &"haze") - haze) <= TOLERANCE, "what his wipers smear is a veil of that much Haze (found %s)" % str(_amount(fx, &"haze")))
	_check(_is_color(fx.shown(&"haze_color"), dust), "and the veil is dust (found %s)" % str(fx.shown(&"haze_color")))
	_check(_amount(fx, &"darkness") == 0.0, "(by day nothing is dark)")
	_drive(sim, fx, GameData.as_float(storm.get("thin_s")))
	_check(GameData.as_bool(sim.snapshot()["dust_thick"]), "(now the dust is thick)")
	_check(_is_color(fx.shown(&"haze_color"), dust) and _amount(fx, &"darkness") == 0.0, "in thick dust it is the same veil, and no darker")
	fx.free()


## A Night storm by the real simulation: it is as dark as a Night leg
## outside the pool of the headlights, and the pool is the headlights' own in
## thin dust and in thick (the dust ends his view sooner; the lamps shine as
## wide as ever). What his wipers smear on the glass is dust there too.
func _night_storm_shows() -> void:
	var tuning: Tuning = _data.tuning
	var storm: Dictionary = GameData.as_dict(_data.record("bosses", BossSim.STORM).get(BossSim.STORM))
	var night: float = tuning.f("postfx_night_darkness")
	var low_beam: float = tuning.f("low_beam_cone")
	var dust: Color = Color.html(tuning.s("sky_color_dust"))
	var sim: DriveSim = _boss(BossSim.STORM, "night_storm")
	var fx: PostFxView = _fx()
	_drive(sim, fx, 1.0)
	var shot: Dictionary = sim.snapshot()
	var cone: float = GameData.as_float(shot["headlight_cone"])
	_check(GameData.as_bool(shot["night"]) and GameData.as_float(shot["visibility"]) < cone, "(a Night storm: it is night, and the dust is nearer than his headlights reach)")
	_check(absf(_amount(fx, &"darkness") - night) <= TOLERANCE, "a Night storm is as dark as a Night leg outside the headlights' pool (found %s)" % str(_amount(fx, &"darkness")))
	_check(absf(_amount(fx, &"beam_reach") - cone / low_beam) <= TOLERANCE, "thin dust leaves the pool the headlights' own (found %s)" % str(_amount(fx, &"beam_reach")))
	for sweep: int in 3:
		sim.items.complete(_data.record("rituals", "wipers"), 0)
	_drive(sim, fx, GameData.as_float(storm.get("thin_s")))
	shot = sim.snapshot()
	_check(GameData.as_bool(shot["dust_thick"]) and GameData.as_float(shot["haze"]) > 0.0, "(now the dust is thick, and his wipers have smeared the glass)")
	_check(absf(_amount(fx, &"beam_reach") - cone / low_beam) <= TOLERANCE, "and thick dust does not shrink it (found %s)" % str(_amount(fx, &"beam_reach")))
	_check(_is_color(fx.shown(&"haze_color"), dust), "what his wipers smear on the glass at night is dust too (found %s)" % str(fx.shown(&"haze_color")))
	fx.free()
	# One headlight dead, by hand: the pool is that one lamp's, dust or not.
	var one_lamp: float = GameData.as_float(GameData.as_dict(_data.record("faults", "dead_headlight").get("params")).get("night_cone_mult"))
	var thick: float = GameData.as_float(storm.get("thick_m"))
	_check(thick < one_lamp * low_beam, "(thick dust is nearer than one headlight reaches)")
	fx = _fx()
	for frame: int in SETTLE_FRAMES:
		fx.apply(_snapshot({"night": true, "boss": BossSim.STORM, "visibility": thick, "headlight_cone": one_lamp * low_beam}), FRAME)
	_check(absf(_amount(fx, &"beam_reach") - one_lamp) <= TOLERANCE, "with a dead headlight in thick dust the pool is the one lamp's (found %s)" % str(_amount(fx, &"beam_reach")))
	fx.free()


## What the veil on the glass is made of: smoke, unless dust is in the air
## (in the Storm by day and by night; by day wherever his view ends).
func _haze_is_made_of() -> void:
	var tuning: Tuning = _data.tuning
	var cap: float = tuning.f("haze_cap")
	var cone: float = tuning.f("low_beam_cone")
	var smoke: Color = Color.html(tuning.s("postfx_haze_color"))
	var dust: Color = Color.html(tuning.s("sky_color_dust"))
	var dust_haze: float = GameData.as_float(_data.record("modifiers", "dust_haze").get("visibility_m"))
	var thick: float = GameData.as_float(GameData.as_dict(_data.record("bosses", BossSim.STORM).get(BossSim.STORM)).get("thick_m"))
	_check(not smoke.is_equal_approx(dust), "(smoke and dust are two colours)")
	_check(_is_color(_veil({"haze": cap}), smoke), "on a clear day the veil on the glass is smoke")
	_check(_is_color(_veil({"haze": cap, "night": true, "visibility": cone, "headlight_cone": cone}), smoke), "and on a Night leg")
	_check(_is_color(_veil({"haze": cap, "visibility": dust_haze}), dust), "by day in a dust haze it is dust")
	_check(_is_color(_veil({"haze": cap, "boss": BossSim.STORM, "night": true, "visibility": thick, "headlight_cone": cone}), dust), "in the Storm it is dust by night as by day")


## The colour of the veil once the effects have settled on a snapshot.
func _veil(by_hand: Dictionary) -> Variant:
	var fx: PostFxView = _fx()
	for frame: int in SETTLE_FRAMES:
		fx.apply(_snapshot(by_hand), FRAME)
	var color: Variant = fx.shown(&"haze_color")
	fx.free()
	return color


## Dawn's sun stands in the windscreen, where his lowered visor covers it
## (GDD 10.4: flipping the visor blocks it): the ray from his resting eye
## toward the sun meets the lowered visor, and the windscreen's glass.
func _sun_is_behind_the_visor() -> void:
	var tuning: Tuning = _data.tuning
	var dawn: Dictionary = GameData.as_dict(_data.record("bosses", BossSim.DAWN).get(BossSim.DAWN))
	var yaw: float = deg_to_rad(GameData.as_float(dawn.get("sun_side")) * tuning.fi("postfx_sun_position", 0))
	var pitch: float = deg_to_rad(tuning.fi("postfx_sun_position", 1))
	var toward: Vector3 = Vector3(sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
	var eye: Vector3 = DriveSim.new(_data).space.eye
	var visor: Vector3 = Vector3(tuning.fi("visor_down_pos", 0), tuning.fi("visor_down_pos", 1), tuning.fi("visor_down_pos", 2))
	var half: Vector3 = PlaceholderFactory.new(_data).size_of("cabin_visor_down") * 0.5
	var on_visor: Vector3 = eye + toward * (visor.z - eye.z) / toward.z
	_check(absf(on_visor.x - visor.x) < half.x and absf(on_visor.y - visor.y) < half.y,
			"Dawn's sun stands where his lowered visor covers it (the ray meets the visor's plane at %s)" % str(on_visor))
	var glass_z: float = tuning.fi("postfx_windscreen", 4)
	var on_glass: Vector3 = eye + toward * (glass_z - eye.z) / toward.z
	_check(on_glass.x > tuning.fi("postfx_windscreen", 0) and on_glass.x < tuning.fi("postfx_windscreen", 2)
			and on_glass.y > tuning.fi("postfx_windscreen", 1) and on_glass.y < tuning.fi("postfx_windscreen", 3),
			"and in the windscreen, where he sees it with the visor up (the ray meets the glass at %s)" % str(on_glass))


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
