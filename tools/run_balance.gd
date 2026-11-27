extends SceneTree
## The balance runner (GDD 13.8, 12.5): the DriverBot drives Tellings at
## three skills and the report says where they stand against GDD 12.5.
##
##   godot --headless --path . --script res://tools/run_balance.gd -- \
##       [--seeds=100] [--first=1] [--tables=drivers,children] [--skills=novice,competent,expert] \
##       [--out=res://artifacts/balance.json] [--part=<file>] [--merge=<file>,<file>...] [--verbose]
##
## --part writes the Tellings themselves instead of a report, so that
## several runs (one for each core: tools/run_balance.sh) can be put
## together with --merge. The report does not fail on the numbers: the
## exit code is 0 when it was written.

const DEFAULT_OUT: String = "res://artifacts/balance.json"


func _initialize() -> void:
	var data: GameData = GameData.load_from("res://data")
	var seeds: int = 100
	var first: int = 1
	var tables: PackedStringArray = []
	var skills: PackedStringArray = DriverBot.SKILLS
	var out: String = DEFAULT_OUT
	var part: String = ""
	var merge: PackedStringArray = []
	var verbose: bool = false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--seeds="):
			seeds = maxi(arg.trim_prefix("--seeds=").to_int(), 1)
		elif arg.begins_with("--first="):
			first = arg.trim_prefix("--first=").to_int()
		elif arg.begins_with("--tables="):
			tables = arg.trim_prefix("--tables=").split(",", false)
		elif arg.begins_with("--skills="):
			skills = arg.trim_prefix("--skills=").split(",", false)
		elif arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		elif arg.begins_with("--part="):
			part = arg.trim_prefix("--part=")
		elif arg.begins_with("--merge="):
			merge = arg.trim_prefix("--merge=").split(",", false)
		elif arg == "--verbose":
			verbose = true
	if tables.is_empty():
		for table: Dictionary in data.records("tables"):
			tables.append(GameData.as_string(table.get("id")))
	var runner: BalanceRun = BalanceRun.new(data)
	var tellings: Array[Dictionary] = []
	if not merge.is_empty():
		for path: String in merge:
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if not parsed is Array:
				printerr("run_balance: %s is no part of a run" % path)
				quit(1)
				return
			for entry: Variant in GameData.as_array(parsed):
				tellings.append(GameData.as_dict(entry))
		seeds = 0
		var counted: Dictionary = {}
		for telling: Dictionary in tellings:
			var key: String = "%s/%s" % [GameData.as_string(telling.get("table")), GameData.as_string(telling.get("skill"))]
			counted[key] = GameData.as_int(counted.get(key)) + 1
			seeds = maxi(seeds, GameData.as_int(counted[key]))
	else:
		var started: int = Time.get_ticks_msec()
		for table: String in tables:
			for skill: String in skills:
				for index: int in seeds:
					var telling: Dictionary = runner.tell(table, skill, first + index, runner.buys_as(table, skill))
					tellings.append(telling)
					if verbose:
						print("%s %s seed %d: %s in act %d (%s), %.0f s, %d hit(s), hand off %.0f%%, last: %s" % [table, skill, first + index,
								GameData.as_string(telling["outcome"]), GameData.as_int(telling["act"]), GameData.as_string(telling["stage"]),
								GameData.as_float(telling["seconds"]), GameData.as_int(telling["hits"]),
								100.0 * float(GameData.as_int(telling["hand_off_ticks"])) / maxf(float(GameData.as_int(telling["road_ticks"])), 1.0),
								str(GameData.as_array(telling["last_hits"]).slice(-1))])
		print("run_balance: %d Tellings in %.0f s" % [tellings.size(), float(Time.get_ticks_msec() - started) / 1000.0])
	if not part.is_empty():
		if not _write(part, JSON.stringify(tellings)):
			quit(1)
			return
		print("run_balance: wrote %d Tellings to %s" % [tellings.size(), part])
		quit(0)
		return
	var report: Dictionary = runner.report(tellings, seeds)
	if not _write(out, JSON.stringify(report, "  ")):
		quit(1)
		return
	for measure: Variant in GameData.as_array(report["measures"]):
		var row: Dictionary = GameData.as_dict(measure)
		print("  %-72s target %-38s measured %s%s" % [GameData.as_string(row["measure"]), GameData.as_string(row["target"]), str(row["measured"]),
				"" if row["measured"] == null else ("  (within)" if GameData.as_bool(row["within"]) else "  (outside)")])
	print("run_balance: report written to %s" % out)
	quit(0)


func _write(path: String, text: String) -> bool:
	var folder: String = path.get_base_dir()
	if not folder.is_empty() and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(folder)):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		printerr("run_balance: cannot write %s" % path)
		return false
	file.store_string(text + "\n")
	file.close()
	return true
