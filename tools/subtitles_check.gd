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
##   - a line is not said twice over, and only a few wait
##   - a line table as the writer will leave it: names, right to left, an
##     exchange, a font
##   - the Call of Dawn: the simulation asks for what Noor says, and it is shown
##   - the Subtitles layer of scenes/drive.tscn
##   - the drive scene running: --say, the Call answered, and the night begun again
##
##   godot --headless --path . --script res://tools/subtitles_check.gd
##
## The first five check SubtitleQueue alone, the pure class that holds the
## wrapping, the timing and the queue. The next build a SubtitlesView as the
## drive scene does and step its frames by hand; for the Call a simulation is
## driven beside it, and its events go to the Events bus as the drive scene
## sends them. The last runs the drive scene itself for a second or two and
## plays it through the game's own input. The numbers are those of
## data/tuning.json, and the lines those of data/lines_en.csv (a writer's
## lines, Arabic among them, are a table made in memory). tools/check.sh
## runs it (with `--fixed-fps 60`, as it runs the smoke tests).
##
## With a renderer, and one of these after `--`, it takes a picture of the
## drive scene instead (tools/subtitles_shots.sh does that for artifacts/):
##
##   --rtl-shot=<file.png>   a subtitle in Arabic, to see right-to-left text
##                           run the right way before the writer's lines arrive
##   --rtl-latin-shot=<file.png>  the same, its second line beginning with a
##                           Latin word, which stands at that line's right end
##   --call-shot=<file.png>  Dawn's road, the Call answered with a TAP on his
##                           pocket: the line the simulation asks for
##   --key-shot=<file.png>   the bay of the Arrival, the pointer on the key,
##                           and a subtitle over it
##
## The checks themselves are in subtitles_check_body.gd: they name the
## autoloads, which the engine does not know yet when it reads this script.

const BODY: String = "res://tools/subtitles_check_body.gd"
## The pictures: the argument that asks for one, and the body's method that
## takes it.
const SHOTS: Dictionary = {
	"--rtl-shot=": "rtl_shot",
	"--rtl-latin-shot=": "rtl_latin_shot",
	"--call-shot=": "call_shot",
	"--key-shot=": "key_shot",
}


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
		for shot: String in SHOTS:
			if argument.begins_with(shot):
				await checks.call(GameData.as_string(SHOTS[shot]), self, argument.substr(shot.length()))
				quit(0)
				return
	var failed: int = GameData.as_int(await checks.call("run", self), 1)
	quit(1 if failed > 0 else 0)
