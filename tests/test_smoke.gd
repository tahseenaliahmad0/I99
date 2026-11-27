extends TestSuite
## Scene smoke tests: scenes launched headless in a child process must run and
## exit cleanly with no engine error in their output (GDD 13.10).

const AUTOLOAD_COUNT: int = 5


## T-SMOKE-BOOT: boot.tscn runs 600 frames at a fixed 60 fps and exits 0 with no
## error output; the five autoloads exist and every data file loads and validates.
func test_smoke_boot() -> void:
	var result: Dictionary = Smoke.run_scene("res://scenes/boot.tscn", Smoke.DEFAULT_FRAMES)
	var output: String = result["output"]
	var errors: PackedStringArray = result["errors"]
	check_eq(result["exit_code"], 0, "boot.tscn exits with code 0")
	check(errors.is_empty(), "boot.tscn prints no engine error; first: %s" % ("(none)" if errors.is_empty() else errors[0]))
	check(output.contains("[boot] ready"), "the boot scene ran its script")
	check(output.contains("autoloads=%d" % AUTOLOAD_COUNT), "Events, Settings, Lines, Audio and Game are autoloaded")
	check(output.contains("json_files=%d" % GameData.JSON_FILES.size()), "every JSON data file is loaded")
	check(output.contains("lines=%d" % data.line_ids().size()), "the line database is loaded")
	check(output.contains("data_errors=0"), "the data validates at boot")
	note("%.1f s" % GameData.as_float(result["seconds"]))


# --- T-SMOKE-ALL -----------------------------------------------------------------

## One headless run of a scene: 600 frames at a fixed 60 fps (more where
## `frames` says so), exit code 0, no error output, and the line that shows
## it did what it was started for.
func _smoke(what: String, scene: String, arguments: PackedStringArray, says: String, frames: int = Smoke.DEFAULT_FRAMES) -> String:
	var result: Dictionary = Smoke.run_scene(scene, frames, arguments)
	var output: String = result["output"]
	var errors: PackedStringArray = result["errors"]
	check_eq(result["exit_code"], 0, "%s: exits with code 0" % what)
	check(errors.is_empty(), "%s: no error output; first: %s" % [what, "(none)" if errors.is_empty() else errors[0]])
	check(output.contains(says), "%s: it ran (\"%s\")" % [what, says])
	return output


## T-SMOKE-ALL: Every scene (boot, title, wedding, and drive in each of its
## DriveContext kinds) launched headless runs 600 frames at a fixed 60 fps
## and exits 0 with no error output.
func test_smoke_all() -> void:
	check_eq(Smoke.DEFAULT_FRAMES, 600, "GDD 13.10: 600 frames")
	var drive: String = "res://scenes/drive.tscn"
	var wedding: String = "res://scenes/wedding.tscn"
	var none: PackedStringArray = []

	# Every scene of the project is one of the four of GDD 13.2.
	var scenes: PackedStringArray = ProjectFiles.find("res://scenes", PackedStringArray(["tscn"]))
	scenes.sort()
	check_eq(scenes, PackedStringArray(["res://scenes/boot.tscn", "res://scenes/drive.tscn", "res://scenes/title.tscn", "res://scenes/wedding.tscn"]),
			"the scenes are boot, drive, title and wedding")

	var booted: String = _smoke("boot", "res://scenes/boot.tscn", none, "[boot] ready")
	check(booted.contains("[title] ready"), "boot: it goes on to the title (GDD 13.4)")
	_smoke("title", "res://scenes/title.tscn", none, "[title] ready")
	_smoke("wedding", wedding, none, "[wedding] ready tables=%d" % data.records("tables").size())
	# The wedding scene's other states: an ending's card, the finale, the credits.
	_smoke("wedding, an ending", wedding, PackedStringArray(["--ending=call", "--table=noor"]), "state=ending")
	_smoke("wedding, the finale", wedding, PackedStringArray(["--ending=finale"]), "state=finale")
	_smoke("wedding, the credits", wedding, PackedStringArray(["--ending=credits"]), "state=credits")

	# drive.tscn in each of its kinds (GDD 13.4: "the prologue, legs, bosses,
	# stops and modes").
	_smoke("drive, by itself", drive, none, "[drive] ready")
	_smoke("drive, the prologue", drive, PackedStringArray(["--prologue", "--table=children", "--seed=1"]), "[drive] the prologue")
	_smoke("drive, a Telling", drive, PackedStringArray(["--table=drivers", "--seed=1", "--bot=line"]), "[drive] a Telling for drivers")
	_smoke("drive, a leg", drive, PackedStringArray(["--leg=open_road,1", "--bot=line"]), "[drive] leg open_road")
	for boss: Dictionary in data.records("bosses"):
		var boss_id: String = GameData.as_string(boss.get("id"))
		_smoke("drive, the %s" % boss_id, drive, PackedStringArray(["--boss=%s" % boss_id, "--bot=line"]), "[drive] boss %s" % boss_id)
	_smoke("drive, the arrival", drive, PackedStringArray(["--boss=arrival", "--bot=line"]), "[drive] the arrival")
	_smoke("drive, the Commute", drive, PackedStringArray(["--mode=%s" % Save.COMMUTE, "--seed=1", "--bot=line"]), "[drive] mode %s" % Save.COMMUTE)
	_smoke("drive, Endless Night", drive, PackedStringArray(["--mode=%s" % Save.ENDLESS_NIGHT, "--seed=1", "--bot=line"]), "[drive] mode %s" % Save.ENDLESS_NIGHT)

	# A stop, and a Telling continued from it: a night driven by the stand-in
	# until a stall saves it, and then begun again from that save.
	var user_dir: String = "--user-dir=%s" % Smoke.test_user_root().path_join("smoke_continue")
	var to_a_stop: String = _smoke("drive, to a stop", drive, PackedStringArray(["--table=drivers", "--seed=7", "--bot=line", user_dir]), "saved (frame", 9000)
	if to_a_stop.contains("saved (frame"):
		_smoke("drive, a Telling continued at its stop", drive, PackedStringArray(["--continue", user_dir]), "[drive] continuing the Telling of drivers")
