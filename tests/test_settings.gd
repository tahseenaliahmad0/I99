extends CabinSuite
## M10: the settings of GDD 17.1. T-SETTINGS-01.


var _spec: SettingsSpec


func before_each() -> void:
	super.before_each()
	_spec = SettingsSpec.new(tuning)


# --- Helpers -------------------------------------------------------------------

## A Telling under way: on a quiet leg in third gear, the wheel let go.
func _mid_telling() -> void:
	_new_sim()
	_sim.heckling = false
	_sim.begin_telling(TABLE, 3)
	_into_next_quiet_leg()
	check(_sim.run.active and _sim.run.stage == RunState.Stage.LEG, "(a Telling, mid-leg)")


## How far the wheel turns for one pull of `pixels` in a tick, gripped.
func _turn_for_a_pull(pixels: float) -> float:
	_grip()
	_ticks(_ticks_in(0.5))
	var before: float = _sim.wheel.angle
	_input.pointer_is_absolute = false
	_input.pointer_delta = Vector2(pixels, 0.0)
	_tick()
	_input.pointer_delta = Vector2.ZERO
	_ticks(_ticks_in(0.6))
	var turned: float = _sim.wheel.angle - before
	_release()
	return turned


# --- T-SETTINGS-01 ---------------------------------------------------------------

## T-SETTINGS-01: Every setting of 17.1 exists with its options and default,
## is saved and loaded, can be changed mid-Telling, and has its stated
## effect.
func test_settings_01() -> void:
	_check_the_table_of_17_1()
	_check_saved_and_loaded()
	_check_steering_sensitivity()
	_check_grip_mode()
	_check_shifting()
	_check_game_speed()
	_check_brake_assist()
	_check_steady_start()
	_check_the_phantom()
	_check_shake_visuals()
	_check_hud_subtitles_and_mirror()
	_check_the_screen()


## Each row of GDD 17.1: the setting, its options, its default.
func _check_the_table_of_17_1() -> void:
	check_eq(_spec.ids(), PackedStringArray([SettingsSpec.STEERING, SettingsSpec.GRIP_MODE, SettingsSpec.SHIFTING, SettingsSpec.GAME_SPEED, SettingsSpec.BRAKE_ASSIST, SettingsSpec.STEADY_START, SettingsSpec.PHANTOM,
			SettingsSpec.SHAKE_VISUALS, SettingsSpec.NUMERIC_HUD, SettingsSpec.SUBTITLE_SIZE, SettingsSpec.SUBTITLE_BACKGROUND, SettingsSpec.MIRRORED]),
			"the eleven settings of GDD 17.1, in its order (Subtitles is two: size and background)")
	var steering: Array = _spec.options(SettingsSpec.STEERING)
	check(GameData.as_float(steering[0]) == 50.0 and GameData.as_float(steering[steering.size() - 1]) == 200.0, "Steering sensitivity: 50% to 200%")
	check_near(GameData.as_float(_spec.default_of(SettingsSpec.STEERING)), 100.0, 0.000001, "default 100%")
	check_eq(_spec.options(SettingsSpec.GRIP_MODE), ["hold", "toggle"], "Grip mode: hold, or toggle")
	check_eq(_spec.default_of(SettingsSpec.GRIP_MODE), "hold", "default hold")
	check_eq(_spec.options(SettingsSpec.SHIFTING), ["gate", "sequential"], "Shifting: gate, or sequential flicks")
	check_eq(_spec.default_of(SettingsSpec.SHIFTING), "gate", "default gate")
	var speed: Array = _spec.options(SettingsSpec.GAME_SPEED)
	check(GameData.as_float(speed[0]) == 70.0 and GameData.as_float(speed[speed.size() - 1]) == 100.0, "Game speed: 70% to 100%")
	check_near(GameData.as_float(_spec.default_of(SettingsSpec.GAME_SPEED)), 100.0, 0.000001, "default 100%")
	check_eq(_spec.default_of(SettingsSpec.BRAKE_ASSIST), false, "Brake assist: default off")
	check_eq(_spec.default_of(SettingsSpec.STEADY_START), true, "Steady start: default on")
	check_eq(_spec.default_of(SettingsSpec.PHANTOM), true, "The Phantom: default on")
	var shake: Array = _spec.options(SettingsSpec.SHAKE_VISUALS)
	check(GameData.as_float(shake[0]) == 0.0 and GameData.as_float(shake[shake.size() - 1]) == 100.0, "Tremor and shake visuals: 0% to 100%")
	check_near(GameData.as_float(_spec.default_of(SettingsSpec.SHAKE_VISUALS)), 100.0, 0.000001, "default 100%")
	check_eq(_spec.default_of(SettingsSpec.NUMERIC_HUD), false, "Numeric HUD: default off")
	check_eq(_spec.options(SettingsSpec.SUBTITLE_SIZE), ["small", "medium", "large"], "Subtitles: a size")
	check_eq(_spec.default_of(SettingsSpec.SUBTITLE_SIZE), "medium", "default medium")
	check_eq(_spec.default_of(SettingsSpec.SUBTITLE_BACKGROUND), true, "Subtitles: a background, default on")
	check_eq(_spec.default_of(SettingsSpec.MIRRORED), false, "Mirrored cabin: default off")
	for id: String in [SettingsSpec.BRAKE_ASSIST, SettingsSpec.STEADY_START, SettingsSpec.PHANTOM, SettingsSpec.NUMERIC_HUD, SettingsSpec.SUBTITLE_BACKGROUND, SettingsSpec.MIRRORED]:
		check_eq(_spec.options(id), [false, true], "%s is on or off" % id)
	for id: String in _spec.ids():
		check(_spec.allows(id, _spec.default_of(id)), "%s: its default is one of its options" % id)
		check(Lines.has_line("settings.%s.name" % id), "%s: it has a name on the settings screen" % id)
		check(Settings.has_setting(id), "%s: the game knows it" % id)
	# What a setting cannot be.
	check(not _spec.allows(SettingsSpec.STEERING, 250.0) and not _spec.allows(SettingsSpec.STEERING, 40.0) and not _spec.allows(SettingsSpec.STEERING, "fast"), "a sensitivity outside 50 to 200 is not allowed")
	check(not _spec.allows(SettingsSpec.GRIP_MODE, "clench") and not _spec.allows(SettingsSpec.PHANTOM, "on"), "nor an option a setting does not have")
	check_eq(_spec.sane(SettingsSpec.GAME_SPEED, 20.0), _spec.default_of(SettingsSpec.GAME_SPEED), "(such a value is read as the default)")
	# The steps of the screen: a range stops at its ends, the rest go round.
	check_near(GameData.as_float(_spec.stepped(SettingsSpec.STEERING, 100.0, 1)), 110.0, 0.000001, "one step up from 100% is 110%")
	check_near(GameData.as_float(_spec.stepped(SettingsSpec.STEERING, 200.0, 1)), 200.0, 0.000001, "200% is the end")
	check_near(GameData.as_float(_spec.stepped(SettingsSpec.GAME_SPEED, 70.0, -1)), 70.0, 0.000001, "70% is the end")
	check_eq(_spec.stepped(SettingsSpec.SUBTITLE_SIZE, "large", 1), "small", "after large comes small again")
	check_eq(_spec.stepped(SettingsSpec.PHANTOM, true, 1), false, "on, off")


## "Is saved and loaded": the settings file, written at every change.
func _check_saved_and_loaded() -> void:
	var dir: String = Smoke.test_user_root().path_join("t_settings")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var defaults: Dictionary = _spec.defaults()
	Settings.setup(dir, defaults)
	Settings.reset_to_defaults()
	var chosen: Dictionary = {}
	for id: String in _spec.ids():
		# Each setting one step off its default.
		chosen[id] = _spec.stepped(id, _spec.default_of(id), -1 if _spec.kind(id) == SettingsSpec.RANGE else 1)
		var differs: bool = chosen[id] != _spec.default_of(id)
		check(differs, "(%s: %s is not its default)" % [id, str(chosen[id])])
		Settings.set_value(id, chosen[id])
	check(FileAccess.file_exists(dir.path_join(Settings.FILE_NAME)), "a change writes the settings file")
	# The game is started again: the file is all it has.
	Settings.setup(dir, defaults)
	for id: String in _spec.ids():
		check_eq(Settings.get_value(id), chosen[id], "%s is loaded as it was saved: %s" % [id, str(chosen[id])])
	# A file with nonsense in it: the defaults.
	var file: FileAccess = FileAccess.open(dir.path_join(Settings.FILE_NAME), FileAccess.WRITE)
	file.store_string(JSON.stringify({SettingsSpec.GRIP_MODE: 7, SettingsSpec.PHANTOM: "yes", "volume": 11}))
	file = null
	Settings.setup(dir, defaults)
	check_eq(Settings.get_value(SettingsSpec.GRIP_MODE), _spec.default_of(SettingsSpec.GRIP_MODE), "a value of the wrong kind in the file is not taken")
	check_eq(Settings.get_value(SettingsSpec.PHANTOM), _spec.default_of(SettingsSpec.PHANTOM), "(nor another)")
	check(not Settings.has_setting("volume"), "and a setting the game does not have is not made")
	# Back to the game's own.
	var own: Dictionary = defaults.duplicate()
	own["font_en"] = ""
	own["font_ar"] = ""
	Settings.setup(Game.user_dir, own)


func _check_steering_sensitivity() -> void:
	var turned: Dictionary = {}
	for percent: float in [50.0, 100.0, 200.0]:
		_mid_telling()
		_sim.apply_settings({SettingsSpec.STEERING: percent})
		check_near(_sim.steer_sensitivity, percent / 100.0, 0.000001, "(steering %d%%)" % roundi(percent))
		turned[percent] = _turn_for_a_pull(40.0)
	check(absf(GameData.as_float(turned[100.0])) > 0.5, "(a pull of the wheel turns it: %.1f degrees)" % GameData.as_float(turned[100.0]))
	check_near(GameData.as_float(turned[200.0]), GameData.as_float(turned[100.0]) * 2.0, absf(GameData.as_float(turned[100.0])) * 0.02, "Steering sensitivity 200%: the same pull turns the wheel twice as far")
	check_near(GameData.as_float(turned[50.0]), GameData.as_float(turned[100.0]) * 0.5, absf(GameData.as_float(turned[100.0])) * 0.02, "50%: half as far")


func _check_grip_mode() -> void:
	for mode: String in ["hold", "toggle"]:
		_mid_telling()
		_sim.apply_settings({SettingsSpec.GRIP_MODE: mode})
		_input.clear()
		_input.pointer_is_absolute = true
		_input.pointer = _sim.space.point_to_pointer(_sim.space.grip_reference)
		_input.lmb = true
		var guard: int = _ticks_in(3.0)
		while not _sim.hand.gripping and guard > 0:
			guard -= 1
			_tick()
		check(_sim.hand.gripping, "(%s: a press on the rim grips the wheel)" % mode)
		_input.lmb = false
		_ticks(_ticks_in(0.5))
		if mode == "hold":
			check(not _sim.hand.gripping, "Grip mode hold: the button let go, the wheel is let go")
		else:
			check(_sim.hand.gripping, "Grip mode toggle: the button let go, the grip holds")
			_input.lmb = true
			_ticks(4)
			_input.lmb = false
			_ticks(_ticks_in(0.5))
			check(not _sim.hand.gripping, "another click lets go")


func _check_shifting() -> void:
	for mode: String in ["gate", "sequential"]:
		_mid_telling()
		_sim.apply_settings({SettingsSpec.SHIFTING: mode})
		_sim.gate.reset(2)
		_reach("gear_lever")
		_input.pointer_is_absolute = false
		_input.lmb = true
		_input.pointer_delta = Vector2(0.0, -6.0)
		_ticks(10)
		_input.pointer_delta = Vector2.ZERO
		_input.lmb = false
		_ticks(10)
		if mode == "sequential":
			check_eq(_sim.gate.gear, 3, "Shifting sequential: a flick up on the lever goes from second to third")
		else:
			check(_sim.gate.gear != 3, "Shifting gate: a flick is no shift (the lever is in %s)" % ("neutral" if _sim.gate.gear == GearGate.NEUTRAL else str(_sim.gate.gear)))


func _check_game_speed() -> void:
	check_near(Game.game_speed(100.0), 1.0, 0.000001, "Game speed 100%: the game's clock runs as the wall's does")
	check_near(Game.game_speed(70.0), 0.7, 0.000001, "70%: seven tenths as fast")
	var kept: Variant = Settings.get_value(SettingsSpec.GAME_SPEED)
	Settings.set_value(SettingsSpec.GAME_SPEED, 70.0)
	check_near(Engine.time_scale, 0.7, 0.000001, "set while the game runs, the engine's time scale follows at once")
	_mid_telling()
	var tick: int = _sim.tick
	_ticks(120)
	check_eq(_sim.tick - tick, 120, "(the simulation's ticks are the same ticks: it is the clock around them that slows)")
	Settings.set_value(SettingsSpec.GAME_SPEED, kept)
	check_near(Engine.time_scale, Game.game_speed(kept), 0.000001, "(and back)")


## "Slows the car when a crash is certain."
func _check_brake_assist() -> void:
	var speeds: Dictionary = {}
	var hits: Dictionary = {}
	for assist: bool in [false, true]:
		_mid_telling()
		_sim.apply_settings({SettingsSpec.BRAKE_ASSIST: assist})
		_sim.traffic.clear()
		var truck: TrafficSim.Vehicle = _sim.traffic.spawn(&"truck", _sim.car.lane_of(_sim.car.x), _sim.car.s + 60.0, 40.0)
		_input.clear()
		_events = []
		var assisted: int = 0
		var closing_at_the_end: float = 0.0
		var guard: int = _ticks_in(6.0)
		while guard > 0 and _count_events("hit") == 0:
			guard -= 1
			# How fast he is closing on it, a tick before whatever happens.
			closing_at_the_end = _sim.car.speed - truck.speed
			_tick()
			if _sim.assisted_brake:
				assisted += 1
		speeds[assist] = closing_at_the_end
		hits[assist] = _count_events("hit")
		if assist:
			check(assisted > 0, "Brake assist on: closing on a truck in his lane, the brake goes on by itself (%d ticks)" % assisted)
			check(GameData.as_bool(_sim.snapshot()["assisted_brake"]) or assisted > 0, "(the snapshot says so)")
		else:
			check_eq(assisted, 0, "Brake assist off: nothing brakes for him")
		check(truck != null, "(the truck)")
	check_eq(GameData.as_int(hits[false]), 1, "(unassisted, he drives into it, closing at %d km/h)" % roundi(GameData.as_float(speeds[false])))
	check(GameData.as_float(speeds[true]) < GameData.as_float(speeds[false]) - 20.0, "the car is slowed: in the end he closes on it at %d km/h, not at %d" % [roundi(GameData.as_float(speeds[true])), roundi(GameData.as_float(speeds[false]))])
	note("with the assist: %d hit(s)" % GameData.as_int(hits[true]))
	# A truck in the next lane is no certain crash.
	_mid_telling()
	_sim.apply_settings({SettingsSpec.BRAKE_ASSIST: true})
	_sim.traffic.clear()
	_sim.traffic.spawn(&"truck", 0 if _sim.car.lane_of(_sim.car.x) != 0 else 1, _sim.car.s + 60.0, 40.0)
	var braked: int = 0
	for _index: int in _ticks_in(6.0):
		_tick()
		if _sim.assisted_brake:
			braked += 1
	check_eq(braked, 0, "a truck in the next lane is passed with no braking: nothing was certain")


## "The wheel holds itself for the first 2 s after each stop."
func _check_steady_start() -> void:
	check_near(tuning.f("steady_start_s"), 2.0, 0.000001, "GDD 17.1: for the first 2 s")
	var drift: Dictionary = {}
	for steady: bool in [true, false]:
		_new_sim()
		_sim.heckling = false
		_sim.begin_telling(TABLE, _seed_for("tea_stall"))
		_into_next_quiet_leg()
		_into_stall()
		_sim.apply_settings({SettingsSpec.STEADY_START: steady})
		_leave_stop()
		_keep_lane = false
		_sim.gate.reset(2)
		_input.clear()
		var x: float = _sim.car.x
		var held: int = 0
		var worst: float = 0.0
		for _index: int in _ticks_in(2.0) - _ticks_in(0.3):
			_sim.step(_input)
			worst = maxf(worst, absf(_sim.car.x - x))
			if _sim.steady_holds():
				held += 1
		drift[steady] = worst
		if steady:
			check(held > _ticks_in(1.5), "Steady start on: after the stop, his hand off the wheel, the wheel holds itself (%.1f s of the 2)" % (float(held) * DT))
			check(_sim.wheel.locked, "(it is held)")
			_ticks(_ticks_in(0.6))
			check(not _sim.steady_holds() and not _sim.wheel.locked, "after 2 s it is his again")
		else:
			check_eq(held, 0, "Steady start off: nothing holds it")
		_keep_lane = true
	check(GameData.as_float(drift[true]) < 0.05, "held, the car keeps its line (%.2f m off)" % GameData.as_float(drift[true]))
	check(GameData.as_float(drift[false]) > GameData.as_float(drift[true]) + 0.05, "unheld, it drifts (%.2f m in the same time)" % GameData.as_float(drift[false]))
	# His own hand on the wheel is his.
	_mid_telling()
	check(not _sim.steady_holds(), "(in the middle of a leg nothing holds the wheel for him)")


func _check_the_phantom() -> void:
	for on: bool in [true, false]:
		_mid_telling()
		_sim.apply_settings({SettingsSpec.PHANTOM: on})
		_sim.nerves.set_value(maxf(tuning.f("phantom_flinch_from") + 5.0, 0.0))
		_tick()
		if on:
			check(_sim.hand.flinches, "The Phantom on: frayed, his wrong hand flinches for a control on the far side")
		else:
			check(not _sim.hand.flinches, "The Phantom off: no flinch, however frayed")
			check(not _sim.phantom_enabled, "(and no cramp: the Phantom is out of the night)")


## "Tremor and shake visuals: 0% to 100%. The mechanical effect stays."
func _check_shake_visuals() -> void:
	_mid_telling()
	_grip()
	_sim.nerves.set_value(90.0)
	var shook: float = 0.0
	var steered: float = 0.0
	var drawn_full: float = 0.0
	var drawn_none: float = 0.0
	for _index: int in _ticks_in(3.0):
		_sim.nerves.set_value(90.0)
		_tick()
		var shot: Dictionary = _sim.snapshot()
		var tremor: float = GameData.as_float(shot["wheel_tremor"])
		var angle: float = GameData.as_float(shot["wheel_angle"])
		shook = maxf(shook, absf(tremor))
		steered = maxf(steered, absf(angle))
		drawn_full = maxf(drawn_full, absf(CabinView.drawn_wheel_angle(angle, tremor, 1.0) - angle))
		drawn_none = maxf(drawn_none, absf(CabinView.drawn_wheel_angle(angle, tremor, 0.0) - (angle - tremor)))
	check(shook > 0.1, "(at 90 Nerves the wheel trembles in his hand: %.2f degrees)" % shook)
	check(steered > 0.1, "the mechanical effect: the wheel itself trembles, whatever is drawn")
	check_near(drawn_full, 0.0, 0.000001, "at 100% the wheel is drawn as it is")
	check_near(drawn_none, 0.0, 0.000001, "at 0% it is drawn without its trembling")
	check_near(CabinView.drawn_wheel_angle(10.0, 2.0, 0.5), 9.0, 0.000001, "at 50% with half of it")
	check_near(SettingsSpec.share(_spec.default_of(SettingsSpec.SHAKE_VISUALS)), 1.0, 0.000001, "(the default draws all of it)")


## The numeric HUD, the subtitles and the mirrored cabin are the views':
## the drive scene, started with a settings file, says what it made of it.
func _check_hud_subtitles_and_mirror() -> void:
	check_eq(SubtitlesView.SIZE_SETTING, SettingsSpec.SUBTITLE_SIZE, "the subtitles read their size from the setting")
	check_eq(SubtitlesView.BACKGROUND_SETTING, SettingsSpec.SUBTITLE_BACKGROUND, "and whether they have a background")
	check_eq(PointerView.mirrored_motion(Vector2(12.0, -3.0), true), Vector2(-12.0, -3.0), "Mirrored cabin: the pointer's way across the picture is reversed with it")
	check_eq(PointerView.mirrored_motion(Vector2(12.0, -3.0), false), Vector2(12.0, -3.0), "(not mirrored: as it is)")
	check_eq(PointerView.shown_at(Vector2(100.0, 40.0), 1280.0, true), Vector2(1180.0, 40.0), "and the pointer is drawn where the reversed picture has it")
	check(ResourceLoader.exists("res://shaders/mirror.gdshader"), "(the picture is reversed by a shader of its own)")
	var dir: String = Smoke.test_user_root().path_join("t_settings_scene")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	for chosen: bool in [false, true]:
		var values: Dictionary = _spec.defaults()
		if chosen:
			values[SettingsSpec.NUMERIC_HUD] = true
			values[SettingsSpec.MIRRORED] = true
			values[SettingsSpec.SHAKE_VISUALS] = 0.0
			values[SettingsSpec.GAME_SPEED] = 70.0
			values[SettingsSpec.BRAKE_ASSIST] = true
			values[SettingsSpec.GRIP_MODE] = "toggle"
		var file: FileAccess = FileAccess.open(dir.path_join(Settings.FILE_NAME), FileAccess.WRITE)
		file.store_string(JSON.stringify(values))
		file = null
		var run: Dictionary = Smoke.run_scene("res://scenes/drive.tscn", 120, PackedStringArray(["--user-dir=%s" % dir, "--table=drivers", "--seed=1"]))
		var output: String = run["output"]
		check(GameData.as_int(run["exit_code"]) == 0 and (run["errors"] as PackedStringArray).is_empty(), "(the drive scene runs with %s)" % ("those settings" if chosen else "the defaults"))
		if chosen:
			check(output.contains("hud=true"), "Numeric HUD on: the drive scene shows it")
			check(output.contains("mirrored=true"), "Mirrored cabin on: the picture is reversed")
			check(output.contains("shake=0.00"), "Tremor and shake visuals 0%: nothing of them is drawn")
			check(output.contains("speed=0.70"), "Game speed 70%: its clock runs at seven tenths")
			check(output.contains("assist=true") and output.contains("grip=toggle"), "(and the simulation has its own)")
		else:
			check(output.contains("hud=false") and output.contains("mirrored=false") and output.contains("shake=1.00") and output.contains("speed=1.00"),
					"by default: no HUD, no mirror, every shake drawn, full speed")
			check(output.contains("steady=true") and output.contains("phantom=true") and output.contains("assist=false") and output.contains("grip=hold") and output.contains("shifting=gate"),
					"and the simulation's defaults are those of GDD 17.1")


## The settings screen: a row for each, and a press takes the next option.
func _check_the_screen() -> void:
	var kept: Dictionary = Game.setting_values()
	for id: String in _spec.ids():
		var value: Variant = _spec.default_of(id)
		var text: String = SettingsView.value_text(_spec, id, value)
		check(not text.is_empty() and not text.begins_with("settings."), "%s: the screen writes its value (%s)" % [id, text])
	check_eq(SettingsView.value_text(_spec, SettingsSpec.STEERING, 150.0), "150%", "a range is written as a percentage")
	check_eq(SettingsView.value_text(_spec, SettingsSpec.PHANTOM, false), Lines.get_text("settings.value.off"), "a toggle as on or off")
	# Changed on the screen in the middle of a Telling: kept, and in effect.
	_mid_telling()
	_sim.apply_settings(Game.setting_values())
	check(not _sim.brake_assist, "(mid-Telling, Brake assist is off)")
	Settings.set_value(SettingsSpec.BRAKE_ASSIST, _spec.stepped(SettingsSpec.BRAKE_ASSIST, Settings.get_value(SettingsSpec.BRAKE_ASSIST), 1))
	_sim.apply_settings(Game.setting_values())
	check(_sim.brake_assist, "one step on its row, and the Telling under way has it on")
	check(_sim.run.active and _sim.run.stage == RunState.Stage.LEG, "(the Telling goes on)")
	for id: Variant in kept:
		Settings.set_value(str(id), kept[id])
