extends SceneTree
## A check of the subtitles that needs no renderer (GDD 16.6, with 17.1,
## 17.3 and 3.6). It prints one PASS or FAIL line for every check, under
## these headings, and ends with a count (exit code 1 if anything failed):
##
##   - 42-character wrapping
##   - never more than two lines at once
##   - the duration rule at 10, 25 and 100 characters
##   - a queue of three lines shown in order
##   - right-to-left text passed through unchanged
##   - an exchange is shown as what each speaker says
##   - speaker tags are lines of the line table
##   - the Subtitles settings of GDD 17.1
##   - the tuning constants of the subtitles
##   - the view, from a line asked for on the Events bus to what its labels hold
##   - the Subtitles layer of scenes/drive.tscn
##
##   godot --headless --path . --script res://tools/subtitles_check.gd
##
## The first five check SubtitleQueue alone, the pure class that holds the
## wrapping, the timing and the queue. The rest build a SubtitlesView as the
## drive scene does and step its frames by hand. The numbers are those of
## data/tuning.json, and the lines those of data/lines_en.csv.
##
## With a renderer, and `--rtl-shot=<file.png>` after `--`, it takes a picture
## instead: the drive scene with a subtitle in Arabic, to see right-to-left
## text run the right way before the writer's lines arrive
## (tools/subtitles_shots.sh does that for artifacts/).
##
## The checks themselves are in subtitles_check_body.gd: they name the
## autoloads, which the engine does not know yet when it reads this script.

const BODY: String = "res://tools/subtitles_check_body.gd"
const RTL_SHOT: String = "--rtl-shot="


func _initialize() -> void:
	# Autoloads enter the tree on the first frame; the view needs them.
	await process_frame
	var body: GDScript = load(BODY) as GDScript
	if body == null or not body.can_instantiate():
		print("FAIL  %s does not compile" % BODY)
		quit(1)
		return
	var checks: RefCounted = body.new()
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(RTL_SHOT):
			await checks.call("rtl_shot", self, argument.substr(RTL_SHOT.length()))
			quit(0)
			return
	var failed: int = GameData.as_int(checks.call("run", root), 1)
	quit(1 if failed > 0 else 0)
