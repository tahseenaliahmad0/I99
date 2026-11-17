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
