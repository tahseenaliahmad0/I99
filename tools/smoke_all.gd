extends SceneTree
## Scene smoke tests (GDD 13.10): every scene under res://scenes is launched
## headless for 600 frames and must exit cleanly with no error output.
##
##   godot --headless --path . --script res://tools/smoke_all.gd

const SCENE_DIR: String = "res://scenes"
## Scenes that are also run with arguments, so that what a leg puts on the
## road is drawn at least once: [scene, arguments].
const WITH_ARGUMENTS: Array = [
	["res://scenes/drive.tscn", ["--leg=night,2", "--bot=line"]],
	["res://scenes/drive.tscn", ["--leg=roadworks,2", "--bot=line"]],
	["res://scenes/drive.tscn", ["--leg=motorcade,3", "--bot=line"]],
]


func _initialize() -> void:
	var scenes: PackedStringArray = ProjectFiles.find(SCENE_DIR, PackedStringArray(["tscn"]))
	var failed: int = 0
	for scene: String in scenes:
		var result: Dictionary = Smoke.run_scene(scene)
		var errors: PackedStringArray = result["errors"]
		var exit_code: int = result["exit_code"]
		var seconds: float = result["seconds"]
		if exit_code == 0 and errors.is_empty():
			print("[ OK ] %s (%.1f s)" % [scene, seconds])
		else:
			failed += 1
			print("SMOKE FAIL %s: exit code %d, %d error line(s)" % [scene, exit_code, errors.size()])
			for line: String in errors:
				print("       - %s" % line)
	var extra: int = 0
	for entry: Variant in WITH_ARGUMENTS:
		var run: Array = entry
		var scene: String = run[0]
		var arguments: PackedStringArray = PackedStringArray(run[1] as Array)
		var result: Dictionary = Smoke.run_scene(scene, Smoke.DEFAULT_FRAMES, arguments)
		var errors: PackedStringArray = result["errors"]
		var exit_code: int = result["exit_code"]
		var seconds: float = result["seconds"]
		extra += 1
		if exit_code == 0 and errors.is_empty():
			print("[ OK ] %s %s (%.1f s)" % [scene, " ".join(arguments), seconds])
		else:
			failed += 1
			print("SMOKE FAIL %s %s: exit code %d, %d error line(s)" % [scene, " ".join(arguments), exit_code, errors.size()])
			for line: String in errors:
				print("       - %s" % line)
	Smoke.clean_test_user_root()
	if scenes.is_empty():
		print("SMOKE FAIL no scenes found under %s" % SCENE_DIR)
		failed += 1
	print("smoke: %d scene(s) and %d run(s) with arguments, %d failure(s)" % [scenes.size(), extra, failed])
	quit(1 if failed > 0 else 0)
