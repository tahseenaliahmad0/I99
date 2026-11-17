extends SceneTree
## Parse check (GDD 13.10): every script compiles and every scene and resource
## loads. Also lints the hard constraints of GDD 1.3 that text can show:
## the simulation in src/core is pure (no Node, no autoload, no wall clock)
## and takes randomness only from its own seeded streams.
##
##   godot --headless --path . --script res://tools/parse_check.gd

const CORE_DIR: String = "res://src/core/"
const AUTOLOADS: PackedStringArray = ["Events", "Settings", "Lines", "Audio", "Game"]
## Global random functions, and Array helpers that use the global generator.
const GLOBAL_RANDOM: String = "(?<![\\w.])(randf|randi|randf_range|randi_range|randfn|randomize|seed|rand_from_seed)\\s*\\("
const ARRAY_RANDOM: String = "\\.(shuffle|pick_random)\\s*\\("
const WALL_CLOCK: String = "\\b(Time\\.get_|OS\\.get_ticks|Engine\\.get_frames|Engine\\.get_physics_frames)"
const NODE_BASE: String = "^extends\\s+(Node|Node2D|Node3D|Control|CanvasItem|CanvasLayer|SceneTree|MainLoop)\\b"


func _initialize() -> void:
	var failures: PackedStringArray = []

	var scripts: PackedStringArray = ProjectFiles.find("res://", PackedStringArray(["gd"]))
	for path: String in scripts:
		var script: GDScript = load(path) as GDScript
		if script == null or not script.can_instantiate():
			failures.append("%s: does not compile" % path)

	var resources: PackedStringArray = ProjectFiles.find("res://", PackedStringArray(["tscn", "tres"]))
	for path: String in resources:
		if load(path) == null:
			failures.append("%s: does not load" % path)

	var core_scripts: int = 0
	for path: String in scripts:
		if path.begins_with(CORE_DIR):
			core_scripts += 1
			_lint_core(path, failures)

	for failure: String in failures:
		print("PARSE FAIL %s" % failure)
	print("parse check: %d scripts, %d scenes and resources, %d core scripts linted, %d failure(s)" % [
		scripts.size(), resources.size(), core_scripts, failures.size()])
	quit(1 if not failures.is_empty() else 0)


func _lint_core(path: String, failures: PackedStringArray) -> void:
	var rules: Dictionary = {
		GLOBAL_RANDOM: "global random function; use a seeded stream from rng.gd",
		ARRAY_RANDOM: "Array.shuffle and pick_random use the global generator; use rng.gd",
		WALL_CLOCK: "wall-clock time in the simulation breaks determinism",
		NODE_BASE: "simulation classes are pure and never extend Node",
		"(?<![\\w.\"])(%s)\\." % "|".join(AUTOLOADS): "the simulation never touches an autoload",
	}
	var lines: PackedStringArray = FileAccess.get_file_as_string(path).split("\n")
	for pattern: Variant in rules:
		var regex: RegEx = RegEx.new()
		regex.compile(str(pattern))
		for index: int in lines.size():
			var code: String = lines[index]
			var comment: int = code.find("#")
			if comment != -1:
				code = code.substr(0, comment)
			if regex.search(code) != null:
				failures.append("%s:%d: %s" % [path, index + 1, str(rules[pattern])])
