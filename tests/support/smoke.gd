class_name Smoke
extends RefCounted
## Launches a scene in a child Godot process, headless, and reports what it
## printed (GDD 13.10, scene smoke test).
##
## The child runs with `--fixed-fps 60`, so 600 frames are 10 s of game time
## (1,200 simulation ticks) however fast the machine is.

const ERROR_PREFIXES: PackedStringArray = ["ERROR:", "SCRIPT ERROR:", "USER ERROR:", "USER SCRIPT ERROR:"]
const WARNING_PREFIXES: PackedStringArray = ["WARNING:", "USER WARNING:"]
const DEFAULT_FRAMES: int = 600
## What the folder of a test process begins with; its process id follows.
const TEST_USER_ROOT: String = "user://test_runs"


## The folder this process and the scenes it launches write under. Every copy
## of the project (a worktree, a snapshot) shares `user://`, and several may
## be tested at once: each process that runs tests or a tool has a folder of
## its own, so that one run never clears away what another is using.
static func test_user_root() -> String:
	return "%s_%d" % [TEST_USER_ROOT, OS.get_process_id()]


## Returns { "exit_code": int, "output": String, "errors": PackedStringArray,
## "warnings": PackedStringArray, "seconds": float }.
static func run_scene(scene_path: String, frames: int = DEFAULT_FRAMES,
		user_args: PackedStringArray = PackedStringArray()) -> Dictionary:
	var args: PackedStringArray = [
		"--headless",
		"--path", ProjectSettings.globalize_path("res://"),
		"--fixed-fps", "60",
		scene_path,
		"--quit-after", str(frames),
		"--",
	]
	var has_user_dir: bool = false
	for arg: String in user_args:
		if arg.begins_with("--user-dir="):
			has_user_dir = true
	if not has_user_dir:
		args.append("--user-dir=%s" % test_user_root().path_join("smoke_" + scene_path.get_file().get_basename()))
	args.append_array(user_args)

	var captured: Array = []
	var started: int = Time.get_ticks_msec()
	var exit_code: int = OS.execute(OS.get_executable_path(), args, captured, true)
	var seconds: float = float(Time.get_ticks_msec() - started) / 1000.0

	var output: String = ""
	for chunk: Variant in captured:
		output += str(chunk)
	output = strip_ansi(output)

	var errors: PackedStringArray = []
	var warnings: PackedStringArray = []
	for raw_line: String in output.split("\n"):
		var line: String = raw_line.strip_edges()
		for prefix: String in ERROR_PREFIXES:
			if line.begins_with(prefix):
				errors.append(line)
				break
		for prefix: String in WARNING_PREFIXES:
			if line.begins_with(prefix):
				warnings.append(line)
				break
	return {"exit_code": exit_code, "output": output, "errors": errors, "warnings": warnings, "seconds": seconds}


static func strip_ansi(text: String) -> String:
	var regex: RegEx = RegEx.new()
	regex.compile("\\x1b\\[[0-9;]*[A-Za-z]")
	return regex.sub(text, "", true)


## Deletes everything this process and the scenes it launched wrote.
static func clean_test_user_root() -> void:
	_remove_recursive(test_user_root())


static func _remove_recursive(path: String) -> void:
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return
	dir.include_hidden = true
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while not entry.is_empty():
		var child: String = path.path_join(entry)
		if dir.current_is_dir():
			_remove_recursive(child)
		else:
			dir.remove(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
