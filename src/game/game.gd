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

## Command-line arguments after `--` (GDD 13.9), plus `--user-dir=` which the
## test harness uses to keep saves and settings out of the player's folder.
const VALUE_ARGS: PackedStringArray = ["table", "seed", "leg", "boss", "bot", "user-dir"]
const FLAG_ARGS: PackedStringArray = ["skip-prologue"]

## Tools and tests started with `--script` never touch the player's files.
const TOOL_USER_DIR: String = "user://test_runs/tool"

var data: GameData
var data_errors: PackedStringArray = []
var args: Dictionary = {}
var user_dir: String = "user://"
var state: AppState = AppState.BOOT


func _ready() -> void:
	var problems: PackedStringArray = []
	args = parse_user_args(OS.get_cmdline_user_args(), problems)
	for problem: String in problems:
		push_error("Game: %s" % problem)
	if args.has("user-dir"):
		user_dir = str(args["user-dir"])
	elif _runs_as_tool():
		user_dir = TOOL_USER_DIR
	if user_dir != "user://":
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(user_dir))

	data = GameData.load_from()
	data_errors = DataValidator.validate(data)
	for message: String in data_errors:
		push_error("Data: %s" % message)

	Settings.setup(user_dir, {})
	Lines.setup(data)
	Audio.setup(data)


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
