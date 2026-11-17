extends Node
## The application: owns the loaded data and the state machine of GDD 13.4.
##
##   BOOT > TITLE > PROLOGUE (first launch) > WEDDING
##   WEDDING > TELLING ... > ARRIVAL > ENDING > WEDDING
##   any LEG or BOSS > WRECK_CUT (3 s) > TELLING restarts
##   ENDING at Noor's Table with the Call > FINALE > CREDITS > WEDDING
##
## Game is the last autoload and wires the others up in `_ready`, so start-up
## order is written down in one place.

enum AppState { BOOT, TITLE, PROLOGUE, WEDDING, TELLING, WRECK_CUT, ENDING, FINALE, CREDITS }

## Command-line arguments after `--` (GDD 13.9), plus three for the build's own
## use: `--user-dir=` keeps saves and settings out of the player's folder,
## `--aim=<anchor id>` points the hand at an anchor without a mouse, and
## `--shot=<file.png>` saves one rendered frame and quits, after
## `--shot-frame=<n>` frames (DECISIONS D-014, D-019).
const VALUE_ARGS: PackedStringArray = ["table", "seed", "leg", "boss", "bot", "user-dir", "aim", "shot", "shot-frame"]
## `--continue` goes on from the save file (until the title screen offers it).
const FLAG_ARGS: PackedStringArray = ["skip-prologue", "continue"]

## Tools and tests started with `--script` never touch the player's files.
const TOOL_USER_DIR: String = "user://test_runs/tool"

var data: GameData
var data_errors: PackedStringArray = []
var args: Dictionary = {}
var user_dir: String = "user://"
var state: AppState = AppState.BOOT
## What persists (GDD 11.5): Tables, guests, modes, whether the prologue was seen.
var profile: Dictionary = Save.default_profile()
## The Telling of the save file, {} when there is none to continue.
var saved_telling: Dictionary = {}


func _ready() -> void:
	if _runs_as_tool():
		# Started with --script: the arguments after `--` belong to that tool.
		user_dir = TOOL_USER_DIR
	else:
		var problems: PackedStringArray = []
		args = parse_user_args(OS.get_cmdline_user_args(), problems)
		for problem: String in problems:
			push_error("Game: %s" % problem)
		if args.has("user-dir"):
			user_dir = str(args["user-dir"])
	if user_dir != "user://":
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(user_dir))

	data = GameData.load_from()
	data_errors = DataValidator.validate(data)
	for message: String in data_errors:
		push_error("Data: %s" % message)

	Settings.setup(user_dir, {})
	Lines.setup(data)
	Audio.setup(data)
	read_save()


# --- The save file (GDD 13.7) ------------------------------------------------

func save_path() -> String:
	return user_dir.path_join(Save.FILE_NAME)


## Reads the save file if there is one. A file that cannot be read leaves a
## new player's profile and no Telling.
func read_save() -> void:
	profile = Save.default_profile()
	saved_telling = {}
	if not FileAccess.file_exists(save_path()):
		return
	var read: Dictionary = Save.from_text(FileAccess.get_file_as_string(save_path()))
	profile = GameData.as_dict(read.get("profile"))
	saved_telling = GameData.as_dict(read.get("telling"))
	if not GameData.as_bool(read.get("ok")):
		push_warning("Game: %s is not a save (%s); starting afresh" % [save_path(), GameData.as_string(read.get("error"))])


## Writes the save file: the profile, and the Telling as it stands at the
## stop he has just come to ({} when no Telling is under way).
func write_save(telling: Dictionary) -> bool:
	saved_telling = telling
	# The folder may have been cleared away since the game started.
	if user_dir != "user://":
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(user_dir))
	var file: FileAccess = FileAccess.open(save_path(), FileAccess.WRITE)
	if file == null:
		push_error("Game: cannot write %s (%s)" % [save_path(), error_string(FileAccess.get_open_error())])
		return false
	file.store_string(Save.to_text(profile, telling))
	return true


func _runs_as_tool() -> bool:
	var engine_args: PackedStringArray = OS.get_cmdline_args()
	return engine_args.has("--script") or engine_args.has("-s")


## Parses `--key=value` and `--flag` arguments. Unknown or malformed arguments
## are reported in `problems` and ignored.
static func parse_user_args(raw: PackedStringArray, problems: PackedStringArray) -> Dictionary:
	var out: Dictionary = {}
	for arg: String in raw:
		if not arg.begins_with("--"):
			problems.append("unexpected argument '%s'" % arg)
			continue
		var body: String = arg.substr(2)
		var eq: int = body.find("=")
		if eq == -1:
			if FLAG_ARGS.has(body):
				out[body] = true
			else:
				problems.append("unknown flag '--%s'" % body)
			continue
		var key: String = body.substr(0, eq)
		var value: String = body.substr(eq + 1)
		if not VALUE_ARGS.has(key):
			problems.append("unknown argument '--%s='" % key)
		elif value.is_empty():
			problems.append("argument '--%s=' has no value" % key)
		else:
			out[key] = value
	return out
