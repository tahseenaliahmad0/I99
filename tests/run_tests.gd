extends SceneTree
## The test runner (GDD 13.10).
##
##   godot --headless --path . --script res://tests/run_tests.gd [-- options]
##
## tests/tests.json is the registry: every test id of GDD 18 with a status,
## "failing" or "passing". The registry is append-only (GDD 1.4, rule 4):
## ids are never removed and a passing test never goes back to failing.
##
## Each test is a method on a tests/test_*.gd suite (see TestSuite). For every
## registered test the runner reports one of:
##   PASS  registered passing, and it passes
##   FAIL  registered passing, and it does not pass: a regression, exit 1
##   NEW   registered failing, and it passes: run with --promote, exit 1
##   TODO  registered failing, implemented, still failing
##   PEND  registered failing, not implemented yet
##
## Options, after `--`:
##   --only=T-HAND,T-GATE   run only ids starting with one of these prefixes
##   --promote              mark NEW tests as passing in tests.json (never demotes)
##   --final                every registered test must be passing (GDD 18.2)
##   --verbose              list TODO and PEND tests one by one
##   --list                 print the registry and exit

const REGISTRY_PATH: String = "res://tests/tests.json"
const SUITE_DIR: String = "res://tests"
const STATUSES: PackedStringArray = ["failing", "passing"]

var _only: PackedStringArray = []
var _promote: bool = false
var _final: bool = false
var _verbose: bool = false
var _list: bool = false

var _problems: PackedStringArray = []
var _trap: ErrorTrap = ErrorTrap.new()


func _initialize() -> void:
	# Autoloads enter the tree on the first frame; wait for them.
	await process_frame
	quit(_main())


func _main() -> int:
	_parse_options()
	var registry: Array[Dictionary] = _load_registry()
	if registry.is_empty():
		_print_problems()
		return 1
	if _list:
		for entry: Dictionary in registry:
			print("%-8s %-4s %-26s %s" % [entry["status"], entry["milestone"], entry["id"], entry["passes_when"]])
		return 0

	var data: GameData = GameData.load_from()
	var implementations: Dictionary = _discover_suites(registry, data)
	Smoke.clean_test_user_root()
	OS.add_logger(_trap)

	var counts: Dictionary = {"PASS": 0, "FAIL": 0, "NEW": 0, "TODO": 0, "PEND": 0}
	var new_ids: PackedStringArray = []
	var selected: int = 0
	var started: int = Time.get_ticks_msec()
	print("I-99 tests: %d registered" % registry.size())
	for entry: Dictionary in registry:
		var id: String = entry["id"]
		if not _selected(id):
			continue
		selected += 1
		var registered_passing: bool = entry["status"] == "passing"
		if not implementations.has(id):
			if registered_passing:
				counts["FAIL"] += 1
				print("[FAIL] %s: registered as passing but no test method %s() exists" % [id, method_for(id)])
			else:
				counts["PEND"] += 1
				if _verbose:
					print("[PEND] %s" % id)
			continue
		var implementation: Dictionary = implementations[id]
		var result: Dictionary = _run_one(implementation)
		var passed: bool = result["passed"]
		var outcome: String = ""
		if registered_passing:
			outcome = "PASS" if passed else "FAIL"
		else:
			outcome = "NEW" if passed else "TODO"
		counts[outcome] += 1
		if outcome == "NEW":
			new_ids.append(id)
		if outcome != "TODO" or _verbose:
			print("[%s] %s (%d checks, %d ms)" % [outcome, id, result["checks"], result["msec"]])
		if not passed and (outcome == "FAIL" or _verbose):
			for message: String in result["failures"]:
				print("       - %s" % message)
		if outcome != "TODO" or _verbose:
			for message: String in result["notes"]:
				print("       . %s" % message)
	var seconds: float = float(Time.get_ticks_msec() - started) / 1000.0

	_guard_against_head(registry)

	var promoted: int = 0
	if _promote and not new_ids.is_empty():
		promoted = _promote_in_registry(new_ids)

	var passing_total: int = 0
	for entry: Dictionary in registry:
		if entry["status"] == "passing" or (_promote and new_ids.has(str(entry["id"]))):
			passing_total += 1

	print("")
	print("Ran %d of %d tests in %.1f s: PASS %d, FAIL %d, NEW %d, TODO %d, PEND %d" % [
		selected, registry.size(), seconds,
		counts["PASS"], counts["FAIL"], counts["NEW"], counts["TODO"], counts["PEND"]])
	print("Registry: %d of %d passing" % [passing_total, registry.size()])
	if promoted > 0:
		print("Promoted %d test(s) to passing in tests/tests.json" % promoted)

	var exit_code: int = 0
	if counts["FAIL"] > 0:
		print("RESULT: FAILED, %d regression(s)" % counts["FAIL"])
		exit_code = 1
	if counts["NEW"] > 0 and not _promote:
		print("RESULT: %d test(s) pass but are registered as failing. Run again with: -- --promote" % counts["NEW"])
		exit_code = 1
	if not _problems.is_empty():
		_print_problems()
		exit_code = 1
	if _final and passing_total < registry.size():
		print("RESULT: --final needs every test passing; %d are not" % (registry.size() - passing_total))
		exit_code = 1
	if exit_code == 0:
		print("RESULT: OK")
	return exit_code


static func method_for(id: String) -> String:
	return "test_" + id.substr(2).to_lower().replace("-", "_")


static func id_for(method: String) -> String:
	return "T-" + method.substr(5).to_upper().replace("_", "-")


func _parse_options() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--promote":
			_promote = true
		elif arg == "--final":
			_final = true
		elif arg == "--verbose":
			_verbose = true
		elif arg == "--list":
			_list = true
		elif arg.begins_with("--only="):
			for prefix: String in arg.substr(7).split(",", false):
				_only.append(prefix.strip_edges())
		else:
			_problems.append("unknown option '%s'" % arg)


func _selected(id: String) -> bool:
	if _only.is_empty():
		return true
	for prefix: String in _only:
		if id.begins_with(prefix):
			return true
	return false


func _load_registry() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(REGISTRY_PATH))
	if not parsed is Dictionary:
		_problems.append("%s is missing or is not a JSON object" % REGISTRY_PATH)
		return out
	var root: Dictionary = parsed
	var seen: Dictionary = {}
	for raw: Variant in GameData.as_array(root.get("tests")):
		if not raw is Dictionary:
			_problems.append("tests.json: every entry must be an object")
			continue
		var entry: Dictionary = raw
		var id: String = GameData.as_string(entry.get("id"))
		var ok: bool = true
		for key: String in ["id", "milestone", "status", "source", "passes_when"]:
			if GameData.as_string(entry.get(key)).is_empty():
				_problems.append("tests.json: entry '%s' needs a non-empty \"%s\"" % [id, key])
				ok = false
		if not ok:
			continue
		if not id.begins_with("T-") or id != id.to_upper():
			_problems.append("tests.json: id '%s' must look like T-NAME-01" % id)
		if seen.has(id):
			_problems.append("tests.json: duplicate id '%s'" % id)
			continue
		if not STATUSES.has(str(entry["status"])):
			_problems.append("tests.json: '%s' has status '%s'; use failing or passing" % [id, str(entry["status"])])
			continue
		seen[id] = true
		out.append(entry)
	return out


## Loads every tests/test_*.gd and maps test id -> { "suite": TestSuite, "method": String }.
func _discover_suites(registry: Array[Dictionary], data: GameData) -> Dictionary:
	var registered: Dictionary = {}
	for entry: Dictionary in registry:
		registered[entry["id"]] = true
	var implementations: Dictionary = {}
	var files: PackedStringArray = []
	var dir: DirAccess = DirAccess.open(SUITE_DIR)
	if dir == null:
		_problems.append("cannot open %s" % SUITE_DIR)
		return implementations
	for file: String in dir.get_files():
		if file.begins_with("test_") and file.ends_with(".gd"):
			files.append(file)
	files.sort()
	for file: String in files:
		var path: String = SUITE_DIR.path_join(file)
		var script: GDScript = load(path) as GDScript
		if script == null or not script.can_instantiate():
			_problems.append("%s does not compile" % path)
			continue
		var instance: Variant = script.new()
		if not instance is TestSuite:
			_problems.append("%s must extend TestSuite" % path)
			continue
		var suite: TestSuite = instance
		suite.data = data
		suite.tuning = data.tuning
		for method_info: Dictionary in script.get_script_method_list():
			var method: String = method_info["name"]
			if not method.begins_with("test_"):
				continue
			var id: String = id_for(method)
			if not registered.has(id):
				_problems.append("%s: %s() has no entry '%s' in tests.json" % [path, method, id])
			elif implementations.has(id):
				_problems.append("%s: %s() is implemented twice" % [path, method])
			else:
				implementations[id] = {"suite": suite, "method": method}
	return implementations


func _run_one(implementation: Dictionary) -> Dictionary:
	var suite: TestSuite = implementation["suite"]
	var method: String = implementation["method"]
	_trap.reset()
	suite.reset_case()
	var started: int = Time.get_ticks_msec()
	suite.before_each()
	suite.call(method)
	suite.after_each()
	var msec: int = Time.get_ticks_msec() - started
	var failures: PackedStringArray = suite.case_failures().duplicate()
	if _trap.count() > 0:
		failures.append("%d engine or script error(s) were logged; first: %s" % [_trap.count(), _trap.first()])
	if suite.case_checks() == 0:
		failures.append("the test made no checks")
	return {
		"passed": failures.is_empty(),
		"failures": failures,
		"notes": suite.case_notes().duplicate(),
		"checks": suite.case_checks(),
		"msec": msec,
	}


## Append-only guard: compared with the committed registry, no id may vanish
## and no passing test may go back to failing.
func _guard_against_head(registry: Array[Dictionary]) -> void:
	var captured: Array = []
	var project_dir: String = ProjectSettings.globalize_path("res://")
	var code: int = OS.execute("git", ["-C", project_dir, "show", "HEAD:tests/tests.json"], captured, false)
	if code != 0 or captured.is_empty():
		return
	var parsed: Variant = JSON.parse_string(str(captured[0]))
	if not parsed is Dictionary:
		return
	var current: Dictionary = {}
	for entry: Dictionary in registry:
		current[entry["id"]] = entry["status"]
	var head_root: Dictionary = parsed
	for raw: Variant in GameData.as_array(head_root.get("tests")):
		var head_entry: Dictionary = GameData.as_dict(raw)
		var id: String = GameData.as_string(head_entry.get("id"))
		if id.is_empty():
			continue
		if not current.has(id):
			_problems.append("tests.json: '%s' exists in the last commit and was removed (tests are append-only)" % id)
		elif head_entry.get("status") == "passing" and current[id] != "passing":
			_problems.append("tests.json: '%s' was passing in the last commit and is now marked failing (never loosen a test)" % id)


## Rewrites the status of each id in place. Entries sit on one line each.
func _promote_in_registry(ids: PackedStringArray) -> int:
	var text: String = FileAccess.get_file_as_string(REGISTRY_PATH)
	var lines: PackedStringArray = text.split("\n")
	var promoted: int = 0
	for index: int in lines.size():
		var line: String = lines[index]
		for id: String in ids:
			if line.contains("\"id\": \"%s\"" % id) and line.contains("\"status\": \"failing\""):
				lines[index] = line.replace("\"status\": \"failing\"", "\"status\": \"passing\"")
				promoted += 1
	if promoted != ids.size():
		_problems.append("tests.json: could not promote every test; keep one entry per line")
	var file: FileAccess = FileAccess.open(REGISTRY_PATH, FileAccess.WRITE)
	if file == null:
		_problems.append("tests.json: cannot write (%s)" % error_string(FileAccess.get_open_error()))
		return 0
	file.store_string("\n".join(lines))
	return promoted


func _print_problems() -> void:
	print("RESULT: FAILED, %d problem(s) with the test setup" % _problems.size())
	for problem: String in _problems:
		print("  ! %s" % problem)
