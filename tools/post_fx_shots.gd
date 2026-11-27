extends SceneTree
## Pictures of the post effects (GDD 16.4), one state at a time.
##
## Most of what the post effects show cannot be had from the command line
## of the drive scene (a lit cigarette, a cracked windscreen, Nerves at
## 100). This tool runs the drive scene as a backdrop, builds a PostFX node
## of its own in the place of the scene's, feeds it the scene's snapshot
## with a few keys set by hand, and saves a screenshot of each state as
## <out>/m10_postfx_<name>.png. It needs a renderer (DECISIONS D-015):
##
##   xvfb-run -a godot --path . --rendering-method gl_compatibility \
##       --rendering-driver opengl3 --audio-driver Dummy --fixed-fps 60 \
##       --script res://tools/post_fx_shots.gd -- [options]
##
## Options, after `--`:
##   --out=<folder>          where the pictures go (default res://artifacts)
##   --only=<name>[,<name>]  only these states
##   --all                   also the states kept for looking, not for the record
##   --list                  print the states and exit
##
## Three effects are driven by the simulation itself in a leg, and their
## pictures are taken from the drive scene (GDD 13.9 arguments, D-019):
##   m10_postfx_darkness.png   --leg=night,2 --bot=line --hud --shot-frame=300
##   m10_postfx_rain_blur.png  --leg=rain,1 --bot=line --hud --shot-frame=480
##   m10_postfx_glare.png      --leg=motorcade,3 --bot=line --hud --shot-frame=2400
##
## A boss has no argument on that command line yet, so the states of the
## Storm and of Dawn (GDD 10.3, 10.4) are taken here, with nothing set by
## hand: the tool starts the boss's road in the scene's own simulation
## (DriveSim.begin_boss), lets the scene's stand-in driver hold the plan's
## line, and has him do what the state names (a sweep of the wipers, the
## visor). This tool is no view: it sets the stage. What the effects are
## given is the simulation's snapshot.

const DRIVE_SCENE: String = "res://scenes/drive.tscn"
const POST_FX_NODE: String = "PostFX"
const FILE_PREFIX: String = "m10_postfx_"
## Frames the backdrop runs before the first picture of it (a leg needs a
## few seconds to put traffic in view), and frames a state is held before
## its picture: every effect has settled long before.
const WARM_FRAMES: int = 240
const SETTLE_FRAMES: int = 45
const FRAMES_PER_SECOND: float = 60.0
## A Telling is driven to one of its stops with nothing drawn, which takes a
## minute; a stop that has not come after this many frames never will.
const STOP_WAIT_FRAMES: int = 90000
## A boss's road is begun as the drive scene begins a leg: in third gear, the
## gear of par. Its seed is the tool's own.
const BOSS_GEAR: int = 3
const BOSS_SEED: int = 1
const KMH_TO_MS: float = 1.0 / 3.6
## Where the drive scene's stand-in driver keeps the plan whose line he
## holds. He takes it from `--leg=`; for a boss the tool hands it to him
## (until the scene takes `--boss=`, which then is one more key of a state's
## backdrop).
const DRIVER_PLAN: StringName = &"_plan"
## Every how many pixels the brightness of a picture is sampled.
const SAMPLE_STEP: int = 8

enum Phase { NEXT, WARM, HOLD, THEN }

var _out: String = "res://artifacts"
var _only: PackedStringArray = []
var _all: bool = false
var _list: bool = false

var _started: bool = false
var _shots: Array[Dictionary] = []
var _index: int = 0
var _phase: Phase = Phase.NEXT
var _wait: int = 0
var _backdrop: String = "(none)"
var _game: Node
var _data: GameData
var _drive: Node
## The effects whose picture is taken: the tool's own node while a state sets
## keys by hand, else the scene's.
var _fx: PostFxView
var _by_hand: PostFxView
## Stops still to come before the picture of a state whose backdrop is a
## Telling, and whether he stood at one in the last frame.
var _stops_left: int = 0
var _was_stopped: bool = false
var _failed: int = 0
var _saved: int = 0


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--only="):
			_only = arg.trim_prefix("--only=").split(",", false)
		elif arg == "--all":
			_all = true
		elif arg == "--list":
			_list = true
		else:
			push_error("post_fx_shots: unknown option '%s'" % arg)
	# Autoloads enter the tree on the first frame; wait for them. A script
	# given with --script is compiled before they have their names, so the
	# game is reached as a node.
	await process_frame
	_game = root.get_node("Game")
	_data = _game.get("data") as GameData
	var states: Array[Dictionary] = _states(_data)
	if _list:
		for shot: Dictionary in states:
			print("%-17s %s%s" % [str(shot["name"]), str(shot["what"]), " (with --all)" if shot.has("extra") else ""])
		quit(0)
		return
	for name: String in _only:
		var known: bool = false
		for shot: Dictionary in states:
			known = known or str(shot["name"]) == name
		if not known:
			push_error("post_fx_shots: no state '%s' (see --list)" % name)
	for shot: Dictionary in states:
		if _only.has(str(shot["name"])) or (_only.is_empty() and (_all or not shot.has("extra"))):
			_shots.append(shot)
	_started = true


## The states: a name, what the picture shows, the backdrop (`leg`, `aim`,
## `give` as the drive scene takes them on its command line) and the
## snapshot keys set by hand (`set`; `then` is set on top of them for
## `then_frames` frames before the picture, to catch something in motion).
## A state marked `extra` is for looking at, not for the record.
##
## A state with no `set` has nothing by hand: its picture is of the scene's
## own effects, as the game shows them. Such a state may have a boss for its
## backdrop (`boss`: its id, then its modifier; `at_m`: where along its road
## the car is put; `warm_s`: for how long he then drives before the first
## picture), and things he does as the state begins (`rituals`: ids of
## rituals.json, completed in the simulation's cabin; this serves for what
## the cabin does by itself, a sweep of the wipers or the visor, not for
## what the drive must hear of, like the Call). `hud` shows the numeric HUD.
## Or it may have a Telling for its backdrop (`table`, `seed`), driven by the
## scene's stand-in driver to the stop of that number (`stops`) with nothing
## drawn on the way; the picture is taken as soon as the state has settled
## there, before he drives on.
func _states(data: GameData) -> Array[Dictionary]:
	var tuning: Tuning = data.tuning
	var lids_max: float = tuning.f("lids_max")
	var haze_cap: float = tuning.f("haze_cap")
	var cracked: float = GameData.as_float(GameData.as_dict(data.record("faults", "cracked_windscreen").get("params")).get("cracks"))
	var spotlight: float = GameData.as_float(GameData.as_dict(data.record("legs", "motorcade").get("special")).get("glare"))
	var low_beam: float = tuning.f("low_beam_cone")
	var high_beam: float = tuning.f("high_beam_cone")
	var shaded: float = _passive(data, "sunglasses", "gives", "glare_mult")
	var darker: float = _passive(data, "sunglasses", "takes", "night_darker") + _passive(data, "tinted_glass", "takes", "night_darker")
	# Dawn (GDD 10.4): he is put a little short of the sunrise and drives
	# through it, until the sun is wholly up and a second longer.
	var dawn: Dictionary = GameData.as_dict(data.record("bosses", BossSim.DAWN).get(BossSim.DAWN))
	var sun: float = GameData.as_float(dawn.get("glare"))
	var sun_side: float = GameData.as_float(dawn.get("sun_side"))
	var ramp: float = GameData.as_float(dawn.get("glare_ramp_m"))
	var par_ms: float = tuning.fi("gear_speeds", BOSS_GEAR - 1) * KMH_TO_MS
	var before_sunrise: float = GameData.as_float(dawn.get("sunrise_at_m")) - 2.0 * ramp
	var into_the_sun: float = 3.0 * ramp / par_ms + 1.0
	# The Storm (GDD 10.3): thin dust as he drives in, thick after thin_s.
	var storm: Dictionary = GameData.as_dict(data.record("bosses", BossSim.STORM).get(BossSim.STORM))
	var into_the_thick: float = GameData.as_float(storm.get("thin_s")) + 0.5
	var sweeps: Array = ["wipers", "wipers", "wipers"]
	var states: Array[Dictionary] = [
		{"name": "none", "extra": true, "what": "the backdrop with no effect: what the others are compared with", "set": {}},
		{"name": "tunnel", "what": "Tunnel at Nerves 100: the view narrowed to tunnel_min_view", "set": {"tunnel": 1.0}},
		{"name": "tunnel_half", "extra": true, "what": "Tunnel halfway (Nerves 80)", "set": {"tunnel": 0.5}},
		{"name": "lids", "what": "Lids fully down: each bar covers lids_max of the view", "set": {"lids": lids_max}},
		{"name": "blink", "what": "a Blink caught as the lids shut", "set": {"lids": lids_max}, "then": {"eyes_shut": true}, "then_frames": 2},
		{"name": "shut", "extra": true, "what": "eyes shut: the whole view is dark", "set": {"lids": lids_max, "eyes_shut": true}},
		{"name": "haze", "what": "Haze at haze_cap: the windscreen clouded with smoke", "set": {"haze": haze_cap}},
		{"name": "haze_half", "extra": true, "what": "Haze at half of haze_cap", "set": {"haze": 0.5 * haze_cap}},
		{"name": "haze_glance", "what": "Haze at haze_cap with things on the dash and the mirror, eyes toward the glovebox: the haze stays on the windscreen", "give": "seeds,breath_mints,beads,phone", "aim": "glovebox", "set": {"haze": haze_cap}},
		{"name": "haze_reach", "extra": true, "what": "Haze at haze_cap with his hand at the visor: the arm before the glass is not veiled", "aim": "visor", "set": {"haze": haze_cap}},
		{"name": "haze_dust", "extra": true, "what": "Haze at haze_cap in a dust haze: the veil is dust", "leg": "open_road,2,dust_haze", "set": {"haze": haze_cap}},
		{"name": "rain_full", "extra": true, "what": "Rain, six seconds after the last sweep: fully blurred", "leg": "rain,1", "set": {"rain_blur": 1.0, "raining": true}},
		{"name": "rain_wiped", "extra": true, "what": "Rain just after a sweep: streaks, no blur", "leg": "rain,1", "set": {"rain_blur": 0.0, "raining": true}},
		{"name": "rain_reach", "extra": true, "what": "Rain fully blurred with things on the dash and the mirror, his hand at the mirror: nothing of the cabin is blurred or rained on, and none of its colours run into the glass", "leg": "rain,1", "give": "seeds,breath_mints,beads,phone", "aim": "mirror", "set": {"rain_blur": 1.0, "raining": true}},
		{"name": "cracks", "what": "the cracked windscreen fault: a web over that share of the glass, before his eyes", "set": {"cracks": cracked}},
		{"name": "cracks_glance", "extra": true, "what": "the same with the eyes toward the gear lever: the web stays on the glass", "aim": "gear_lever", "set": {"cracks": cracked}},
		{"name": "glare_spot", "extra": true, "what": "Glare of the motorcade's spotlight, straight ahead", "set": {"glare": spotlight}},
		{"name": "glare_shades", "extra": true, "what": "the same through cracked sunglasses", "set": {"glare": shaded * spotlight}},
		{"name": "glare_sun", "what": "Dawn just past its sunrise, by the simulation: Glare 60% from the low sun, ahead and to the left (GDD 10.4)", "boss": "dawn", "at_m": before_sunrise, "warm_s": into_the_sun, "hud": true},
		{"name": "glare_visor", "what": "the same Dawn a moment later, the visor flipped down: the sun is still up and its wash is gone", "boss": "dawn", "at_m": before_sunrise, "warm_s": into_the_sun, "hud": true, "rituals": ["visor_photo"]},
		{"name": "glare_reach", "extra": true, "what": "the same Dawn with his hand at the visor: the arm before the glass takes the cabin's share of the wash, not the glass's", "boss": "dawn", "at_m": before_sunrise, "warm_s": into_the_sun, "aim": "visor", "hud": true},
		{"name": "glare_sun_keys", "extra": true, "what": "the low sun over a day's road, by the keys of Dawn set by hand", "set": {"glare": sun, PostFxView.SUN_KEY: sun, PostFxView.SUN_SIDE_KEY: sun_side}},
		{"name": "glare_placed", "extra": true, "what": "Glare from a light whose place the snapshot gives outright: to the right and high", "set": {"glare": spotlight, PostFxView.GLARE_POSITION_KEY: Vector2(30.0, 12.0)}},
		{"name": "darkness_low", "extra": true, "what": "a Night leg at low beam", "leg": "night,2", "set": {}},
		{"name": "darkness_high", "extra": true, "what": "a Night leg at high beam: the pool is larger", "leg": "night,2", "set": {"headlight_cone": high_beam, "visibility": high_beam}},
		{"name": "darkness_dead", "extra": true, "what": "a Night leg with a dead headlight: the pool is halved", "leg": "night,2", "set": {"headlight_cone": 0.5 * low_beam, "visibility": 0.5 * low_beam}},
		{"name": "darkness_tint", "what": "a Night leg behind sunglasses and tinted glass", "leg": "night,2", "set": {"night_darker": darker, "visibility": (1.0 - darker) * low_beam}},
		{"name": "darkness_left", "extra": true, "what": "a Night leg, eyes toward the window crank: the driver's side glass", "leg": "night,2", "aim": "window_crank", "set": {}},
		{"name": "darkness_right", "extra": true, "what": "a Night leg, eyes toward the passenger: the passenger's side glass", "leg": "night,2", "aim": "passenger_shoulder", "set": {}},
		{"name": "darkness_reach", "what": "a Night leg with things on the dash and the mirror, his hand at the mirror: his arm, the beads, the clock and what stands on the dash keep the cabin's light where the night is behind them", "leg": "night,2", "give": "seeds,breath_mints,beads,phone", "aim": "mirror", "set": {}},
		{"name": "night_stop", "what": "a stop at night, by the simulation (a Telling for the Drivers' Table, seed 1: the fuel station after the Night leg that opens Act 2), his hand at the tray's upper row: the tray, what is on it, the labels, his arm and the vendor keep the cabin's light", "table": "drivers", "seed": 1, "stops": 5, "aim": "offer_8", "hud": true},
		{"name": "storm_thin", "extra": true, "what": "the Storm in thin dust, by the simulation, after three sweeps of the wipers: what they smear on the glass is dust", "boss": "storm", "hud": true, "rituals": sweeps},
		{"name": "storm_thick", "what": "the Storm in thick dust, by the simulation, after three sweeps of the wipers", "boss": "storm", "warm_s": into_the_thick, "hud": true, "rituals": sweeps},
		{"name": "storm_night_thin", "extra": true, "what": "a Night storm in thin dust, by the simulation: the headlights' pool is the low beam's and his view ends where the dust does", "boss": "storm,night_storm", "hud": true},
		{"name": "storm_night", "what": "a Night storm in thick dust, by the simulation, after three sweeps of the wipers: tail lights to follow, and the dust on the glass in the headlights' glow", "boss": "storm,night_storm", "warm_s": into_the_thick, "hud": true, "rituals": sweeps},
		{"name": "all", "what": "everything at once at night, eyes toward the glovebox", "leg": "night,2", "aim": "glovebox", "set": {"tunnel": 0.6, "lids": 0.5 * lids_max, "haze": 0.5 * haze_cap, "rain_blur": 0.7, "raining": true, "cracks": cracked, "glare": 0.5}},
	]
	return states


## What an item changes by being there (items.json: a `passive` entry).
func _passive(data: GameData, item_id: String, side: String, key: String) -> float:
	for entry: Variant in GameData.as_array(data.record("items", item_id).get(side)):
		var change: Dictionary = GameData.as_dict(entry)
		if GameData.as_string(change.get("passive")) == key:
			return GameData.as_float(change.get("amount"))
	return 0.0


func _process(delta: float) -> bool:
	if not _started:
		return false
	if _index >= _shots.size():
		print("post_fx_shots: %d picture(s) saved, %d failure(s)" % [_saved, _failed])
		quit(1 if _failed > 0 or _saved == 0 else 0)
		return true
	var shot: Dictionary = _shots[_index]
	match _phase:
		Phase.NEXT:
			var backdrop: String = _backdrop_of(shot)
			if backdrop != _backdrop:
				_backdrop = backdrop
				_build_backdrop(shot)
				_wait = roundi(GameData.as_float(shot.get("warm_s")) * FRAMES_PER_SECOND) if shot.has("warm_s") else WARM_FRAMES
				if _stops_left > 0:
					_wait = STOP_WAIT_FRAMES
				_phase = Phase.WARM
			else:
				_begin(shot)
		Phase.WARM:
			_wait -= 1
			if _stops_left > 0:
				# A Telling: until he has come to the stop the state names.
				var stopped: bool = (_drive.get("sim") as DriveSim).stopped
				if stopped and not _was_stopped:
					_stops_left -= 1
				_was_stopped = stopped
				if _stops_left == 0:
					_begin(shot)
				elif _wait <= 0:
					push_error("post_fx_shots: state '%s' never came to its stop" % str(shot["name"]))
					_stops_left = 0
					_begin(shot)
			elif _wait <= 0:
				_begin(shot)
		Phase.HOLD:
			if _by_hand != null:
				_show(GameData.as_dict(shot.get("set")), {}, delta)
			_wait -= 1
			if _wait <= 0:
				if shot.has("then") and _by_hand != null:
					_wait = GameData.as_int(shot.get("then_frames"), 1)
					_phase = Phase.THEN
				else:
					_save(shot)
		Phase.THEN:
			_show(GameData.as_dict(shot.get("set")), GameData.as_dict(shot.get("then")), delta)
			_wait -= 1
			if _wait <= 0:
				_save(shot)
	return false


## What tells one backdrop from another: states that share it follow one
## another on the same road, the later ones a little further along it.
func _backdrop_of(shot: Dictionary) -> String:
	var parts: PackedStringArray = []
	for key: String in ["leg", "aim", "give", "boss", "at_m", "warm_s", "hud", "table", "seed", "stops"]:
		parts.append(str(shot.get(key, "")))
	return "|".join(parts)


## Runs the drive scene behind the effects, as its command line would.
func _build_backdrop(shot: Dictionary) -> void:
	if _drive != null:
		_drive.free()
		_drive = null
		_by_hand = null
		_fx = null
	var args: Dictionary = {"bot": "line", "seed": "1"}
	for key: String in ["leg", "aim", "give", "table", "seed"]:
		if shot.has(key):
			args[key] = str(shot[key])
	if shot.has("hud"):
		args["hud"] = true
	_game.set("args", args)
	var scene: PackedScene = load(DRIVE_SCENE) as PackedScene
	_drive = scene.instantiate()
	root.add_child(_drive)
	_stops_left = GameData.as_int(shot.get("stops"))
	_was_stopped = false
	if _stops_left > 0:
		# The way to the stop is driven, not drawn.
		RenderingServer.render_loop_enabled = false
	if shot.has("boss"):
		_begin_boss(shot)


## Starts the road of a boss (`<id>[,<modifier>]`) in the scene's own
## simulation, as the scene itself starts a leg: in third gear, with no
## traffic but the boss's own. The scene's stand-in driver is given the
## plan, whose line he then holds. With `at_m` the car is put that far along
## the road, and what the road held before that point is behind him.
func _begin_boss(shot: Dictionary) -> void:
	var sim: DriveSim = _drive.get("sim") as DriveSim
	var parts: PackedStringArray = str(shot["boss"]).split(",")
	sim.free_traffic_per_km = 0.0
	sim.gate.reset(BOSS_GEAR)
	sim.begin_boss(parts[0], parts[1] if parts.size() > 1 else "", BOSS_SEED)
	_drive.set(DRIVER_PLAN, sim.leg.plan)
	if not is_same(_drive.get(DRIVER_PLAN), sim.leg.plan):
		push_error("post_fx_shots: the drive scene's stand-in driver takes no plan: nobody holds the car on the line of '%s'" % str(shot["boss"]))
	var at: float = GameData.as_float(shot.get("at_m"))
	if shot.has("at_m"):
		sim.car.s = at
		sim.leg.fast_forward(at, at / (_data.tuning.fi("gear_speeds", BOSS_GEAR - 1) * KMH_TO_MS))
	print("post_fx_shots: boss %s modifier '%s' seed %d from %d m" % [sim.boss.kind, sim.boss.modifier, BOSS_SEED, roundi(at)])


## A state begins. With keys set by hand, a PostFX node of the tool's own
## takes the place of the scene's: it starts from nothing, like the scene's
## at the start of a drive. With none, the scene's own effects are what is
## shown. Then he does what the state names.
func _begin(shot: Dictionary) -> void:
	RenderingServer.render_loop_enabled = true
	var own: PostFxView = _drive.get_node(POST_FX_NODE) as PostFxView
	if _by_hand != null:
		_by_hand.free()
		_by_hand = null
	if shot.has("set"):
		own.visible = false
		_by_hand = PostFxView.new()
		_by_hand.name = "PostFXByHand"
		_drive.add_child(_by_hand)
		_drive.move_child(_by_hand, own.get_index())
		_by_hand.setup(_data, _drive.get_node("Camera3D") as Camera3D, _drive.get_node("Cabin") as Node3D)
		_fx = _by_hand
	else:
		own.visible = true
		_fx = own
	var sim: DriveSim = _drive.get("sim") as DriveSim
	for id: Variant in GameData.as_array(shot.get("rituals")):
		if _data.has_record("rituals", str(id)):
			sim.items.complete(_data.record("rituals", str(id)), 0)
		else:
			push_error("post_fx_shots: state '%s' names an unknown ritual '%s'" % [str(shot["name"]), str(id)])
	_wait = SETTLE_FRAMES
	_phase = Phase.HOLD


## The scene's snapshot with some keys set by hand goes to the effects.
func _show(by_hand: Dictionary, on_top: Dictionary, delta: float) -> void:
	var sim: DriveSim = _drive.get("sim") as DriveSim
	var snapshot: Dictionary = sim.snapshot()
	snapshot.merge(by_hand, true)
	snapshot.merge(on_top, true)
	_by_hand.apply(snapshot, delta)


func _save(shot: Dictionary) -> void:
	var name: String = str(shot["name"])
	var texture: ViewportTexture = root.get_texture()
	var image: Image = texture.get_image() if texture != null else null
	if image == null or image.is_empty():
		print("post_fx_shots: no image for '%s': this renderer draws nothing (run under xvfb with gl_compatibility)" % name)
		_failed += 1
	else:
		var folder: String = ProjectSettings.globalize_path(_out)
		DirAccess.make_dir_recursive_absolute(folder)
		var path: String = folder.path_join(FILE_PREFIX + name + ".png")
		var err: Error = image.save_png(path)
		if err != OK:
			_failed += 1
		else:
			_saved += 1
		print("post_fx_shots: %s (%s) brightness %.3f | %s" % [path, error_string(err), _brightness(image), _uniforms()])
	_index += 1
	_phase = Phase.NEXT


## The nine uniforms of GDD 16.4 as the shader has them now.
func _uniforms() -> String:
	var parts: PackedStringArray = []
	for uniform_name: StringName in [&"tunnel", &"lids", &"blink", &"haze", &"rain_blur", &"cracks", &"glare_amount", &"darkness"]:
		parts.append("%s %.3f" % [uniform_name, GameData.as_float(_fx.shown(uniform_name))])
	var at: Variant = _fx.shown(&"glare_position")
	if at is Vector2:
		var uv: Vector2 = at
		parts.append("glare_position (%.3f, %.3f)" % [uv.x, uv.y])
	return ", ".join(parts)


## Mean brightness of a picture, 0 (black) to 1 (white).
func _brightness(image: Image) -> float:
	var sum: float = 0.0
	var count: int = 0
	for y: int in range(0, image.get_height(), SAMPLE_STEP):
		for x: int in range(0, image.get_width(), SAMPLE_STEP):
			sum += image.get_pixel(x, y).get_luminance()
			count += 1
	return sum / float(maxi(count, 1))
