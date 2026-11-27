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
## `--give=<item>[,<item>...]` puts items in the cabin (the debug key F5 of
## GDD 13.9 from the command line).
## `--ride=<passenger id>` puts a passenger in the seat (GDD 8).
## `--say=<line id>[,<line id>...]` asks for those lines when the drive scene
## starts, one after the other (to look at the subtitles).
## `--mode=commute` or `--mode=endless_night` plays a mode in the drive scene
## (GDD 11.5).
## `--ending=late|on_time|call` with `--table=` shows that ending's card in
## the wedding scene; `--ending=finale` its finale; `--ending=credits` the
## credits (to look at them without driving a night).
const VALUE_ARGS: PackedStringArray = ["table", "seed", "leg", "boss", "bot", "user-dir", "aim", "shot", "shot-frame", "give", "ride", "say", "mode", "ending"]
## `--continue` goes on from the save file (until the title screen offers it).
## `--hud` starts with the numeric HUD showing.
## `--prologue` plays the prologue in the drive scene, then `--table=`'s Telling.
const FLAG_ARGS: PackedStringArray = ["skip-prologue", "continue", "hud", "prologue"]

## Tools and tests started with `--script` never touch the player's files:
## each such process writes under a folder of its own, named after its process
## id (the folder the test runner clears away, Smoke.test_user_root()), since
## every copy of the project shares `user://` and several may run at once.
const TOOL_USER_DIR: String = "user://test_runs_%d/tool"

var data: GameData
var data_errors: PackedStringArray = []
var args: Dictionary = {}
var user_dir: String = "user://"
var state: AppState = AppState.BOOT
## What persists (GDD 11.5): Tables, guests, modes, whether the prologue was seen.
var profile: Dictionary = Save.default_profile()
## The Telling of the save file, {} when there is none to continue.
var saved_telling: Dictionary = {}
## The DriveContext (GDD 13.4): what drive.tscn is to do when it is entered
## from the menus. { "prologue": true, "table", "seed" } plays the prologue
## and then that Telling; { "table", "seed" } begins a Telling; { "table",
## "continue": true } goes on with the saved one; { "mode", "seed" } plays a
## mode. Empty when the scene was started by itself: the command line's
## arguments say what it does then (GDD 13.9).
var context: Dictionary = {}
## What he has just come back to the wedding with, for its card: an
## ending (Save.apply_ending's result, with "table" and "clock") or a
## mode's run (Save.apply_mode's result). {} for nothing.
var last_ending: Dictionary = {}


func _ready() -> void:
	if _runs_as_tool():
		# Started with --script: the arguments after `--` belong to that tool.
		user_dir = TOOL_USER_DIR % OS.get_process_id()
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

	Settings.setup(user_dir, {
		# Subtitles (GDD 17.1): size small, medium or large; background on or off.
		"subtitle_size": "medium",
		"subtitle_background": true,
		# A font slot for each language (GDD 17.3): the path of a font of the
		# project, "" for the theme's own.
		"font_en": "",
		"font_ar": "",
	})
	Lines.setup(data)
	Audio.setup(data)
	read_save()


# --- The save file (GDD 13.7) ------------------------------------------------

func save_path() -> String:
	return user_dir.path_join(Save.FILE_NAME)


## Reads the save file if there is one. A file that cannot be read leaves a
## new player's profile and no Telling.
func read_save() -> void:
	profile = Save.new_profile(data) if data != null else Save.default_profile()
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


# --- The way through the game (GDD 13.4) --------------------------------------

## Frames drawn in a menu scene, for `--shot=` there (the drive scene takes
## its own pictures).
var _menu_frames: int = 0


func _process(_delta: float) -> void:
	if not args.has("shot") or get_tree().current_scene == null or get_tree().current_scene.scene_file_path == DRIVE_SCENE:
		return
	_menu_frames += 1
	var at: int = maxi(str(args.get("shot-frame", "30")).split(",")[0].to_int(), 1)
	if _menu_frames != at:
		return
	var texture: ViewportTexture = get_viewport().get_texture()
	var image: Image = texture.get_image() if texture != null else null
	if image == null or image.is_empty():
		print("[game] no image to save: this renderer draws nothing")
	else:
		print("[game] shot %s (%s)" % [str(args["shot"]), error_string(image.save_png(str(args["shot"])))])
	get_tree().quit()


const TITLE_SCENE: String = "res://scenes/title.tscn"
const WEDDING_SCENE: String = "res://scenes/wedding.tscn"
const DRIVE_SCENE: String = "res://scenes/drive.tscn"


## Enters a state: its scene, with the DriveContext for the drive.
func go(next: AppState, drive_context: Dictionary = {}) -> void:
	state = next
	context = drive_context
	var scene: String = WEDDING_SCENE
	match next:
		AppState.BOOT, AppState.TITLE:
			scene = TITLE_SCENE
		AppState.PROLOGUE, AppState.TELLING, AppState.WRECK_CUT:
			scene = DRIVE_SCENE
	print("[game] %s" % state_name())
	get_tree().change_scene_to_file.call_deferred(scene)


func state_name() -> String:
	return str(AppState.keys()[state]).to_lower()


## The title's first entry: the prologue on first launch, else the wedding.
func begin() -> void:
	if after_title() == AppState.PROLOGUE:
		play_prologue()
	else:
		go(AppState.WEDDING)


## The prologue, and after it tonight at the Table that is open from the
## start (GDD 10.1, D-063).
func play_prologue() -> void:
	var first: PackedStringArray = TableRules.open_at_start(data)
	go(AppState.PROLOGUE, {"prologue": true, "table": first[0] if not first.is_empty() else "", "seed": new_seed()})


## He sits down at a Table (GDD 3.2): the Telling he left at its last stop
## goes on, or a new one begins.
func sit_at(table_id: String) -> void:
	if not saved_telling.is_empty() and GameData.as_string(saved_telling.get("table")) == table_id:
		go(AppState.TELLING, {"table": table_id, "continue": true})
	else:
		go(AppState.TELLING, {"table": table_id, "seed": new_seed()})


## A mode (GDD 11.5): the Commute has the day's seed, Endless Night its own.
func play_mode(mode: String) -> void:
	go(AppState.TELLING, {"mode": mode, "seed": daily_seed() if mode == Save.COMMUTE else new_seed()})


## A seed for a night nobody has driven: `--seed=` when the build was
## started with one, else from the clock on the wall.
func new_seed() -> int:
	if args.has("seed"):
		return int(str(args["seed"]))
	return int(Time.get_unix_time_from_system()) % 1000000 * 1000 + Time.get_ticks_usec() % 1000


## The Commute's seed (GDD 11.5: "a daily seed"): today's date.
func daily_seed() -> int:
	if args.has("seed"):
		return int(str(args["seed"]))
	var today: Dictionary = Time.get_date_dict_from_system()
	return GameData.as_int(today.get("year")) * 10000 + GameData.as_int(today.get("month")) * 100 + GameData.as_int(today.get("day"))


## A mode's run is over: its score is kept (GDD 11.5: statistics, always).
func end_mode(mode: String, score: float, finished: bool) -> Dictionary:
	var result: Dictionary = Save.apply_mode(profile, mode, score, finished)
	write_save(saved_telling)
	return result


## The prologue plays on first launch (GDD 10.1): until it has been seen,
## unless the build was started with --skip-prologue (GDD 13.9). It can be
## played again from the title at any time.
func wants_prologue() -> bool:
	return not GameData.as_bool(profile.get("prologue_seen")) and not args.has("skip-prologue")


## Where the title leads (GDD 13.4): BOOT > TITLE > PROLOGUE (first launch)
## > WEDDING.
func after_title() -> AppState:
	return AppState.PROLOGUE if wants_prologue() else AppState.WEDDING


## The prologue has been played: it is not played by itself again.
func prologue_played() -> void:
	profile["prologue_seen"] = true
	write_save(saved_telling)


## The Telling is over: he has parked (GDD 10.5). What its ending leaves
## behind goes into the profile (GDD 11.4, 11.5: Tables, told true, modes,
## the guest) and the save file, which has no Telling to continue any more.
## Returns what is new (Save.apply_ending).
func end_telling(arrived: Dictionary) -> Dictionary:
	var result: Dictionary = Save.apply_ending(data, profile, arrived)
	write_save({})
	return result


## A passenger carried to Basra sits at a Table from then on (GDD 11.5).
## False when they already do.
func add_guest(passenger_id: String) -> bool:
	var guests: Array = GameData.as_array(profile.get("guests"))
	if passenger_id.is_empty() or guests.has(passenger_id):
		return false
	guests.append(passenger_id)
	profile["guests"] = guests
	return true


func _runs_as_tool() -> bool:
	var engine_args: PackedStringArray = OS.get_cmdline_args()
	return engine_args.has("--script") or engine_args.has("-s")


## The folder of a tool's own process goes with the tool, with whatever it
## and the scenes it launched left there.
func _exit_tree() -> void:
	if _runs_as_tool():
		_remove_folder(user_dir.get_base_dir())


static func _remove_folder(path: String) -> void:
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return
	dir.include_hidden = true
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while not entry.is_empty():
		if dir.current_is_dir():
			_remove_folder(path.path_join(entry))
		else:
			dir.remove(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


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
