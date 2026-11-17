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
const WALL_CLOCK: String = "\\b(Time\\.get_|OS\\.get_|Engine\\.get_frames|Engine\\.get_physics_frames|Engine\\.get_process_frames|Performance\\.)"
## A generator of its own is unseeded until someone seeds it; rng.gd owns the streams.
const OWN_GENERATOR: String = "RandomNumberGenerator\\.new\\s*\\(|\\.randomize\\s*\\("
const RNG_FILE: String = "rng.gd"


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
		WALL_CLOCK: "wall-clock time, frame counters and machine facts in the simulation break determinism",
		"(?<![\\w.\"])(%s)\\." % "|".join(AUTOLOADS): "the simulation never touches an autoload",
	}
	if path.get_file() != RNG_FILE:
		rules[OWN_GENERATOR] = "a generator of its own; the seeded streams live in rng.gd"
	var lines: PackedStringArray = FileAccess.get_file_as_string(path).split("\n")
	for pattern: Variant in rules:
		var regex: RegEx = RegEx.new()
		regex.compile(str(pattern))
		for index: int in lines.size():
			if regex.search(_code_of(lines[index])) != null:
				failures.append("%s:%d: %s" % [path, index + 1, str(rules[pattern])])
	# No Node anywhere in it: the engine knows what a class is, whatever the
	# text looks like (a base class with another name, an inner class).
	var script: GDScript = load(path) as GDScript
	if script != null:
		_lint_base(path, script, "", failures)


func _lint_base(path: String, script: GDScript, inner: String, failures: PackedStringArray) -> void:
	var base: StringName = script.get_instance_base_type()
	if base == &"Node" or ClassDB.is_parent_class(base, &"Node"):
		failures.append("%s: %s extends %s: simulation classes are pure and never Nodes" % [
			path, "the script" if inner.is_empty() else "inner class %s" % inner, base])
	var constants: Dictionary = script.get_script_constant_map()
	for key: Variant in constants:
		# An inner class is a constant of its script; a preloaded script is not ours to judge here.
		if not constants[key] is GDScript:
			continue
		var nested: GDScript = constants[key]
		if nested.resource_path.is_empty():
			_lint_base(path, nested, str(key), failures)


## A line without its comment and with the insides of its strings blanked, so
## that a '#' or a name inside a string is not read as code.
func _code_of(line: String) -> String:
	var out: String = ""
	var quote: String = ""
	var index: int = 0
	while index < line.length():
		var character: String = line[index]
		if quote.is_empty():
			if character == "#":
				break
			if character == "\"" or character == "'":
				quote = character
			out += character
		elif character == "\\":
			index += 1
		elif character == quote:
			quote = ""
			out += character
		index += 1
	return out
