extends SceneTree
## Scene smoke tests (GDD 13.10): every scene under res://scenes is launched
## headless for 600 frames and must exit cleanly with no error output.
##
##   godot --headless --path . --script res://tools/smoke_all.gd

const SCENE_DIR: String = "res://scenes"


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
	Smoke.clean_test_user_root()
	if scenes.is_empty():
		print("SMOKE FAIL no scenes found under %s" % SCENE_DIR)
		failed += 1
	print("smoke: %d scene(s), %d failure(s)" % [scenes.size(), failed])
	quit(1 if failed > 0 else 0)
