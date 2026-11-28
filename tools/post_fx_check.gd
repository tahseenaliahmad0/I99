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
##   - the cabin is told apart from the world: with a real cabin, his arm
##     and an eye, the shader is shown a picture that a camera at the eye
##     takes of the cabin's layer alone; what is drawn under the Cabin node
##     is on that layer, a thing put there later too, and neither a thing of
##     the world nor what the car carries before its windscreen; and the
##     drive scene keeps his hand and the stall under its Cabin node;
##   - the windscreen of tuning is the opening the cabin's props leave;
##   - no effect flashes faster than three times a second: whatever a
##     snapshot key is thrown between, the uniform it drives turns back at
##     most six times in any second, and a light that changes place while
##     its wash is up is moved there, not put there.
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
## The drive scene, and the nodes of it that a stage is built of (GDD 13.5).
const DRIVE_SCENE: String = "res://scenes/drive.tscn"
const EYE_NODE: String = "Camera3D"
const CABIN_NODE: String = "Cabin"
const HAND_NODE: String = "Hand"
const STOP_NODE: String = "Stop"
const ROAD_NODE: String = "Road"
const POST_FX_NODE: String = "PostFX"
## Where the cabin puts the items of its slots, and one to put there.
const ITEM_NODE: String = "ItemMounts"
const AN_ITEM: StringName = &"beads"
## A thing of the world (placeholders.json), and the cabin's props that
## frame the windscreen (anchors.json).
const A_WORLD_THING: String = "stop_stall"
const PILLAR_LEFT: String = "pillar_left"
const PILLAR_RIGHT: String = "pillar_right"
const DASH: String = "dash"
const ROOF: String = "roof"
## How far the windscreen of tuning may lie from the cabin's opening (m).
const GLASS_TOLERANCE: float = 0.002
## The mipmap the rain's blur reads the view from, as both shaders must
## work it out: the post effects' for the view, its helper's for the cabin.
const MIPMAP_LEVEL: String = "float level = max(log2(max(radius / SCREEN_PIXEL_SIZE.y, 1.0)) - 1.0, 0.0);"
## A glance, in degrees up and to the right, to turn the eye by.
const A_GLANCE: Vector2 = Vector2(-6.0, 20.0)

var _data: GameData
var _base: Dictionary = {}
var _checks: int = 0
var _failures: PackedStringArray = []


func _initialize() -> void:
	# The root is in the tree from the first frame on: the stage of the
	# cabin's checks needs that.
	await process_frame
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
	var stage: Node3D = _stage()
	var probe: PostFxView = stage.get_node(POST_FX_NODE) as PostFxView
	probe.apply(_snapshot({"tunnel": 1.0}), FRAME)
	for found: RegExMatch in any_uniform.search_all(code):
		var uniform_name: String = found.get_string(1)
		if uniform_name != SCREEN_TEXTURE:
			_check(probe.shown(StringName(uniform_name)) != null, "the view gives the shader its `%s`" % uniform_name)
	stage.free()

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
	# (The longest a sweep can last, D-074: wiper_clear_time and its spread.)
	_leg_shows("rain", 1, &"", &"rain_blur", 1.0, tuning.f("wiper_clear_time") + tuning.f("wiper_clear_spread") + 1.0)

	# The bosses of the real simulation, and what they are made of.
	_dawn_shows()
	_storm_shows()
	_night_storm_shows()
	_haze_is_made_of()
	_sun_is_behind_the_visor()

	# What is the cabin's and what is the glass's.
	_cabin_is_told_apart()
	_windscreen_is_the_cabins()

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
	_light_moves(spotlight)

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


## An eye, a cabin with his arm, a thing of the world and the effects, in the
## tree and named as the drive scene has them (GDD 13.5).
func _stage() -> Node3D:
	var tuning: Tuning = _data.tuning
	var sim: DriveSim = DriveSim.new(_data)
	var factory: PlaceholderFactory = PlaceholderFactory.new(_data)
	var stage: Node3D = Node3D.new()
	root.add_child(stage)
	var eye: Camera3D = Camera3D.new()
	eye.name = EYE_NODE
	eye.position = sim.space.eye
	eye.fov = tuning.f("camera_fov")
	eye.near = tuning.f("camera_near")
	eye.far = tuning.f("camera_far")
	stage.add_child(eye)
	var cabin: CabinView = CabinView.new()
	cabin.name = CABIN_NODE
	stage.add_child(cabin)
	cabin.setup(_data, factory)
	var hand: HandView = HandView.new()
	hand.name = HAND_NODE
	cabin.add_child(hand)
	hand.setup(_data, factory, sim.space)
	var road: Node3D = Node3D.new()
	road.name = ROAD_NODE
	stage.add_child(road)
	road.add_child(factory.make_world(A_WORLD_THING))
	var fx: PostFxView = PostFxView.new()
	fx.name = POST_FX_NODE
	stage.add_child(fx)
	fx.setup(_data, eye, cabin)
	return stage


## Everything that is drawn under `node`.
func _things(node: Node) -> Array[GeometryInstance3D]:
	var out: Array[GeometryInstance3D] = []
	var thing: GeometryInstance3D = node as GeometryInstance3D
	if thing != null:
		out.append(thing)
	for child: Node in node.get_children():
		out.append_array(_things(child))
	return out


## The names of what is drawn under `node` and is not on the cabin's layer.
func _off_layer(node: Node) -> PackedStringArray:
	var out: PackedStringArray = []
	for thing: GeometryInstance3D in _things(node):
		if (thing.layers & PostFxView.CABIN_LAYER) == 0:
			out.append(str(thing.name))
	out.sort()
	return out


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
	var yaw: float = deg_to_rad(GameData.as_float(dawn.get("sun_side")) * tuning.fi("sun_position", 0))
	var pitch: float = deg_to_rad(tuning.fi("sun_position", 1))
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


## The cabin is told apart from the world (GDD 16.3: he reads the state off
## the cabin's objects, so the night, the glass and a dazzling light must
## leave them readable). With a real cabin, his arm and an eye in the tree,
## the shader is shown a picture of the cabin by itself: a camera at the eye
## takes it of one layer, on which is what is drawn under the Cabin node and
## nothing else.
func _cabin_is_told_apart() -> void:
	var cone: float = _data.tuning.f("low_beam_cone")
	var stage: Node3D = _stage()
	var eye: Camera3D = stage.get_node(EYE_NODE) as Camera3D
	var cabin: CabinView = stage.get_node(CABIN_NODE) as CabinView
	var fx: PostFxView = stage.get_node(POST_FX_NODE) as PostFxView
	var mask: SubViewport = fx.get_node_or_null(PostFxView.MASK_NODE) as SubViewport
	var mask_eye: Camera3D = mask.get_camera_3d() if mask != null else null
	_check(mask_eye != null and fx.shown(&"cabin_mask") is ViewportTexture, "the shader is shown a picture of the cabin by itself")
	if mask_eye == null:
		stage.free()
		return
	_check(mask_eye.cull_mask == PostFxView.CABIN_LAYER and mask.transparent_bg, "its camera sees the cabin's layer and nothing else, over nothing")
	_check((eye.cull_mask & PostFxView.CABIN_LAYER) != 0, "(the eye sees that layer too)")

	# The cabin as the simulation shows it, with his visor down.
	var sim: DriveSim = DriveSim.new(_data)
	var shot: Dictionary = sim.snapshot()
	shot["visor_down"] = true
	cabin.apply(shot)
	var nose: PackedStringArray = _before_the_windscreen()
	var off: PackedStringArray = _off_layer(cabin)
	_check(_things(cabin).size() > off.size() and off == nose,
			"what is drawn under the Cabin node is on that layer, all but what the car carries before its windscreen (not on it: %s; before the windscreen by the data: %s)" % [str(off), str(nose)])
	_check(not nose.is_empty(), "(the car does carry something before its windscreen)")
	for part: String in [HAND_NODE, "Dash", "Visor", "Mirror", "Wheel"]:
		var group: Node = cabin.get_node_or_null(part)
		_check(group != null and not _things(group).is_empty() and _off_layer(group).is_empty(), "so is all of the cabin's %s" % part)
	var clock: Array[Node] = cabin.get_node("Dash").find_children("*", "Label3D", true, false)
	_check(not clock.is_empty(), "(the dashboard clock is drawn under Dash)")

	# What is put in the cabin later, and what is of the world.
	var mounts: Node = cabin.get_node(ITEM_NODE)
	var before: int = _things(mounts).size()
	_check(sim.give_item(AN_ITEM) != null, "(%s is put in the cabin)" % AN_ITEM)
	cabin.apply(sim.snapshot())
	_check(_things(mounts).size() > before and _off_layer(mounts).is_empty(), "a thing put in the cabin later is on that layer too")
	var road: Node = stage.get_node(ROAD_NODE)
	_check(not _things(road).is_empty() and _off_layer(road).size() == _things(road).size(), "a thing of the world is not")

	# The picture is taken from where the eye is, while there is something
	# to show: the eye turned by a glance, and its view narrowed by as much.
	eye.rotation_degrees = Vector3(A_GLANCE.x, -A_GLANCE.y, 0.0)
	eye.fov -= A_GLANCE.y
	fx.apply(_snapshot({"night": true, "visibility": cone, "headlight_cone": cone}), FRAME)
	_check(_drawn(fx) and mask.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "while there is something to show the cabin's picture is taken")
	_check(mask_eye.global_transform.is_equal_approx(eye.global_transform) and is_equal_approx(mask_eye.fov, eye.fov)
			and is_equal_approx(mask_eye.near, eye.near) and is_equal_approx(mask_eye.far, eye.far),
			"from where the eye is, the way it looks (found %s, the eye is at %s)" % [str(mask_eye.global_transform), str(eye.global_transform)])
	# The cabin's picture as the rain's blur needs it: taken while the rain
	# blurs, from the mipmap the view is read from, and at no other time.
	var smear: SubViewport = fx.get_node_or_null(PostFxView.SMEAR_NODE) as SubViewport
	var smeared: Array[Node] = smear.find_children("*", "ColorRect", false, false) if smear != null else []
	var smear_material: ShaderMaterial = (smeared[0] as ColorRect).material as ShaderMaterial if not smeared.is_empty() else null
	_check(smear_material != null and fx.shown(&"cabin_smear") is ViewportTexture, "the shader is shown the cabin's picture smeared as the rain smears the view")
	if smear_material != null:
		_check(smear.render_target_update_mode == SubViewport.UPDATE_DISABLED, "which is not taken on a dry night")
		for frame: int in SETTLE_FRAMES:
			fx.apply(_snapshot({"raining": true, "rain_blur": 1.0}), FRAME)
		_check(smear.render_target_update_mode == SubViewport.UPDATE_ALWAYS and mask.render_target_update_mode == SubViewport.UPDATE_ALWAYS,
				"and is taken, with the cabin's picture, while the rain blurs the glass")
		_check(smear.get_index() > mask.get_index(), "after the picture it is made from")
		var smear_code: String = smear_material.shader.code
		var view_code: String = (load(SHADER_PATH) as Shader).code
		var any_uniform: RegEx = RegEx.new()
		any_uniform.compile("(?m)^uniform\\s+\\w+\\s+(\\w+)")
		for found: RegExMatch in any_uniform.search_all(smear_code):
			var uniform_name: String = found.get_string(1)
			if uniform_name != SCREEN_TEXTURE:
				var given: Variant = smear_material.get_shader_parameter(StringName(uniform_name))
				var same: bool = given is float and is_equal_approx(GameData.as_float(given), GameData.as_float(fx.shown(StringName(uniform_name))))
				_check(same and GameData.as_float(given) > 0.0, "its shader is given the `%s` of the post effects (found %s)" % [uniform_name, str(given)])
		_check(smear_code.contains(MIPMAP_LEVEL) and view_code.contains(MIPMAP_LEVEL), "and reads the mipmap that the rain's blur reads, by the same arithmetic")
	for frame: int in SETTLE_FRAMES:
		fx.apply(_snapshot({}), FRAME)
	_check(not _drawn(fx) and mask.render_target_update_mode == SubViewport.UPDATE_DISABLED
			and (smear == null or smear.render_target_update_mode == SubViewport.UPDATE_DISABLED), "and with nothing to show neither picture is taken")
	stage.free()

	# In the drive scene his hand and the stall are under the Cabin node,
	# and the road is beside it.
	var scene: String = FileAccess.get_file_as_string(DRIVE_SCENE)
	for child: String in [HAND_NODE, STOP_NODE]:
		_check(_scene_has(scene, child, CABIN_NODE), "in the drive scene %s is under %s" % [child, CABIN_NODE])
	_check(_scene_has(scene, ROAD_NODE, "."), "and %s is not" % ROAD_NODE)


## Does the text of a scene have the node `child` with the parent `parent`?
func _scene_has(scene: String, child: String, parent: String) -> bool:
	var node: RegEx = RegEx.new()
	node.compile("(?m)^\\[node name=\"%s\"[^\\]]* parent=\"%s\"[^\\]]*\\]" % [child, parent.replace(".", "\\.")])
	return node.search(scene) != null


## The cabin's props and fittings that stand before the windscreen by the
## data: beyond its plane and within its width (the hood, a bull bar).
func _before_the_windscreen() -> PackedStringArray:
	var tuning: Tuning = _data.tuning
	var out: PackedStringArray = []
	for set_name: String in ["props", "fittings"]:
		for entry: Dictionary in _data.records(set_name):
			var at: Vector3 = GameData.as_vec3(entry.get("pos"))
			if at.z < tuning.fi("postfx_windscreen", 4) and at.x > tuning.fi("postfx_windscreen", 0) and at.x < tuning.fi("postfx_windscreen", 2):
				out.append(GameData.as_string(entry.get("id")))
	out.sort()
	return out


## The windscreen of tuning is the opening the cabin leaves (GDD 1.1: an
## artist may move a pillar in the registry with no code change): seen from
## his resting eye on the plane of the glass, it lies between the pillars,
## above the dash and below the roof.
func _windscreen_is_the_cabins() -> void:
	var tuning: Tuning = _data.tuning
	var eye: Vector3 = DriveSim.new(_data).space.eye
	var plane: float = tuning.fi("postfx_windscreen", 4)
	var opening: Array[float] = [
		_prop_seen(PILLAR_LEFT, eye, plane).end.x,
		_prop_seen(DASH, eye, plane).end.y,
		_prop_seen(PILLAR_RIGHT, eye, plane).position.x,
		_prop_seen(ROOF, eye, plane).position.y,
	]
	var edges: PackedStringArray = ["left edge (the left pillar)", "foot (the dash)", "right edge (the right pillar)", "top (the roof)"]
	for index: int in edges.size():
		var found: float = tuning.fi("postfx_windscreen", index)
		_check(absf(found - opening[index]) <= GLASS_TOLERANCE,
				"the windscreen's %s is where the cabin's props leave it, at %.4f (postfx_windscreen has %s)" % [edges[index], opening[index], str(found)])


## The box of one of the cabin's props (anchors.json) as his eye sees it on
## the plane of the windscreen: the bounds of its corners that lie before
## the eye.
func _prop_seen(id: String, eye: Vector3, plane: float) -> Rect2:
	var prop: Dictionary = _data.record("props", id)
	var half: Vector3 = PlaceholderFactory.new(_data).size_of(GameData.as_string(prop.get("placeholder"))) * 0.5
	var turn: Vector3 = GameData.as_vec3(prop.get("rot"))
	var place: Transform3D = Transform3D(Basis.from_euler(Vector3(deg_to_rad(turn.x), deg_to_rad(turn.y), deg_to_rad(turn.z))), GameData.as_vec3(prop.get("pos")))
	var low: Vector2 = Vector2(INF, INF)
	var high: Vector2 = Vector2(-INF, -INF)
	for index: int in 8:
		var corner: Vector3 = place * (half * Vector3(1.0 if index & 1 else -1.0, 1.0 if index & 2 else -1.0, 1.0 if index & 4 else -1.0))
		if corner.z < eye.z - TOLERANCE:
			var seen: Vector2 = Vector2(eye.x, eye.y) + (Vector2(corner.x, corner.y) - Vector2(eye.x, eye.y)) * (plane - eye.z) / (corner.z - eye.z)
			low = low.min(seen)
			high = high.max(seen)
	return Rect2(low, high - low)


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


## A light that changes place while its wash is up (the sun for a spotlight,
## a place the snapshot gives outright) is moved to its new place, not put
## there; and however its place is thrown about, the wash turns back at most
## six times a second, across and up (GDD 16.4).
func _light_moves(strength: float) -> void:
	var spot: Dictionary = {"glare": strength}
	var sun_up: Dictionary = {"glare": strength, PostFxView.SUN_KEY: strength, PostFxView.SUN_SIDE_KEY: -0.5}
	var at_sun: Vector2 = _glare_at(sun_up)
	var fx: PostFxView = _fx()
	for frame: int in SETTLE_FRAMES:
		fx.apply(_snapshot(spot), FRAME)
	var from: Vector2 = _light_at(fx)
	fx.apply(_snapshot(sun_up), FRAME)
	var first: Vector2 = _light_at(fx)
	_check(absf(_amount(fx, &"glare_amount") - strength) <= TOLERANCE, "(a spotlight's wash is up as the sun takes its place)")
	_check(not first.is_equal_approx(from) and not first.is_equal_approx(at_sun),
			"a light that changes place while its wash is up is moved there, not put there (after one frame at %s, on its way from %s to %s)" % [str(first), str(from), str(at_sun)])
	for frame: int in 2 * SETTLE_FRAMES:
		fx.apply(_snapshot(sun_up), FRAME)
	_check(_light_at(fx).is_equal_approx(at_sun), "and it comes to its new place (found %s)" % str(_light_at(fx)))
	fx.free()
	_light_flickers("the sun comes and goes under a spotlight", PostFxView.SUN_KEY, 0.0, strength, {"glare": strength, PostFxView.SUN_SIDE_KEY: -0.5})
	_light_flickers("a place given outright is thrown from side to side", PostFxView.GLARE_POSITION_KEY, Vector2(-30.0, 10.0), Vector2(30.0, -5.0), spot)


## Where the light is shown, back in degrees right of straight ahead and
## above the horizon: a view with no camera looks straight ahead and sees a
## right angle each way.
func _light_degrees(fx: PostFxView) -> Vector2:
	var at: Vector2 = _light_at(fx)
	var right: float = atan(2.0 * at.x - 1.0)
	return Vector2(rad_to_deg(right), rad_to_deg(atan((1.0 - 2.0 * at.y) * cos(right))))


## Throws `key` between `low` and `high` every few frames while a wash is up
## and counts how often the light turns back, to the side and up or down.
## (Counted in degrees, as the light is moved: in the picture a light that
## passes straight ahead well above the horizon dips there, which is its
## path, not a turn.)
func _light_flickers(what: String, key: String, low: Variant, high: Variant, with: Dictionary) -> void:
	var worst: int = 0
	var swing: float = 0.0
	var second: int = roundi(1.0 / FRAME)
	for period: int in FLICKER_PERIODS:
		var fx: PostFxView = _fx()
		var settled: Dictionary = with.duplicate()
		settled[key] = low
		for frame: int in SETTLE_FRAMES:
			fx.apply(_snapshot(settled), FRAME)
		var turns: Array[PackedInt32Array] = [PackedInt32Array(), PackedInt32Array()]
		var last: Vector2 = _light_degrees(fx)
		var heading: Vector2 = Vector2.ZERO
		for frame: int in FLICKER_FRAMES:
			var by_hand: Dictionary = with.duplicate()
			by_hand[key] = high if frame % (2 * period) < period else low
			fx.apply(_snapshot(by_hand), FRAME)
			var now: Vector2 = _light_degrees(fx)
			for axis: int in 2:
				if absf(now[axis] - last[axis]) > TOLERANCE:
					var moved: float = signf(now[axis] - last[axis])
					if heading[axis] != 0.0 and moved != heading[axis]:
						turns[axis].append(frame)
					heading[axis] = moved
			swing = maxf(swing, (now - last).length())
			last = now
		fx.free()
		# The most turns inside any one second, on either axis.
		for axis: int in 2:
			for index: int in turns[axis].size():
				var inside: int = 0
				for other: int in range(index, turns[axis].size()):
					if turns[axis][other] - turns[axis][index] < second:
						inside += 1
				worst = maxi(worst, inside)
	_check(worst <= MOST_TURNS, "the light's place turns back at most six times a second when %s (found %d)" % [what, worst])
	_check(swing > 0.0, "the light's place does answer when %s" % what)
