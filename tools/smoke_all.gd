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
	# What is said (GDD 16.6): a line of two lines, an exchange, a line shown in parts.
	["res://scenes/drive.tscn", ["--leg=open_road,1", "--bot=line", "--say=narrator.start,wreck.drivers.1,subtitle.test.long"], 900],
	# A cabin full of things: every kind of item drawn, the HUD's rows for them.
	["res://scenes/drive.tscn", ["--leg=rain,1", "--bot=line", "--hud",
			"--give=beads,seeds,phone,arak_flask,mixtape,thermos,forged_papers,tissue_box,bull_bar,fog_lamps,taxi_sign,spinner_knob,wheel_ring,crossover_stalk,thumb_keypad,wide_mirror,tinted_glass,turbo,good_stuff"], 3000],
	# A Telling to its first stop and on: fork, leg, Exit, stop and save, fork again.
	["res://scenes/drive.tscn", ["--table=drivers", "--seed=7", "--bot=line"], 9000],
	# The set pieces by themselves, each to its end and into its next round:
	# the queue, the soldier and two documents; the dust and its gusts; the
	# glow, the sun, the last checkpoint and the Call; the street and the key.
	["res://scenes/drive.tscn", ["--boss=checkpoint,thorough", "--bot=line", "--hud"], 5400],
	["res://scenes/drive.tscn", ["--boss=storm,crosswind", "--bot=line", "--hud"], 5400],
	["res://scenes/drive.tscn", ["--boss=dawn,early_sun", "--bot=line", "--hud"], 9600],
	["res://scenes/drive.tscn", ["--boss=arrival", "--bot=line", "--hud"], 2400],
	# Somebody in the seat (GDD 8): the figure, the drum, the HUD's row.
	["res://scenes/drive.tscn", ["--leg=open_road,1", "--bot=line", "--hud", "--ride=drummer"], 900],
	["res://scenes/drive.tscn", ["--leg=rain,1", "--bot=line", "--hud", "--ride=conscript"], 900],
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
		var frames: int = GameData.as_int(run[2]) if run.size() > 2 else Smoke.DEFAULT_FRAMES
		var result: Dictionary = Smoke.run_scene(scene, frames, arguments)
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
