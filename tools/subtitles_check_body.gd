extends RefCounted
## The checks of tools/subtitles_check.gd (GDD 16.6, with 17.1, 17.3 and
## 3.6), and its pictures (right-to-left subtitles, the Call, the key): the
## body of that tool. It is a file of its own because it names the autoloads
## (Lines, Settings, Events, Game), and a script started with `--script` is
## read before the engine knows them. See there for what is checked and how
## to run it.

const DRIVE_SCENE: String = "res://scenes/drive.tscn"
const VIEW_SCRIPT: String = "res://src/view/subtitles_view.gd"
const FRAME: float = 1.0 / 60.0
const SLOW_FRAME: float = 1.0 / 20.0
## Frames after which a subtitle that should have gone is called stuck.
const MOST_FRAMES: int = 4000
const TOLERANCE: float = 0.000001
## What GDD 16.6 says, to hold the tuning file to it.
const GDD_LINE_CHARS: int = 42
const GDD_MAX_LINES: int = 2
const GDD_MIN_DURATION: float = 1.5
const GDD_CHAR_DURATION: float = 0.06
## The lines of GDD 3.6 this check shows.
const SHORT_LINE: String = "noor.call.1"
const TWO_LINE_LINE: String = "narrator.start"
const EXCHANGE_LINE: String = "wreck.drivers.1"
const LONG_LINE: String = "subtitle.test.long"
## Arabic text in the order it is written and read: "one hand does not
## clap"; "they say one hand does not clap, but it drives the car all night
## to Basra"; and a sentence with Latin letters and digits in it.
const RTL_SHORT: String = "يد واحدة لا تصفق"
const RTL_LONG: String = "يقولون إن اليد الواحدة لا تصفق، لكنها تقود السيارة طوال الليل حتى البصرة"
## A speaker's name in Arabic: Abu Noor.
const RTL_SPEAKER: String = "أبو نور"
const RTL_MIXED: String = "الطريق I-99 طويل، 540 كيلومترا حتى البصرة، والشاي يبرد في الكوب"
## The characters that force a direction on text: the marks, embeddings,
## overrides and isolates of the bidirectional algorithm.
const DIRECTION_MARKS: String = "\u200E\u200F\u061C\u202A\u202B\u202C\u202D\u202E\u2066\u2067\u2068\u2069"
## An Arabic sentence that is cut so that its second line begins with a
## Latin word: "the road to Basra is long, my daughter; I-99 is the name of
## this long road".
const RTL_LATIN_SECOND: String = "الطريق إلى البصرة طويل يا ابنتي I-99 هو اسم هذا الطريق الطويل"
const LATIN_WORD: String = "I-99"
## An exchange as a writer may leave it (wreck.children.1): what each says,
## divided as the English row divides it, and the speaker column filled in
## too, in Arabic ("a child, then Abu Noor"), which is not asked of them.
const RTL_EXCHANGE_LINE: String = "wreck.children.1"
const RTL_CHILD: String = "طفل"
const RTL_SPEAKERS: String = "طفل، ثم أبو نور"
const RTL_ASKED: String = "كيف أنت هنا إذن؟"
const RTL_ANSWERED: String = "سؤال جيد. من جديد."
## A name as its own line may come to be written: not what the speaker
## columns say.
const WRITTEN_NAME: String = "Noor, the bride"

## The Call of Dawn (GDD 10.4): what Noor says when he answers (GDD 3.6), the
## rituals that take it (data/rituals.json), and where his hand goes for it.
const CALL_LINE: String = SHORT_LINE
## Lines that announce something a moment ahead (GDD 2.2 pillar 4): the ring
## of the Call written out, and Noor's last words before the talk ends.
const TELL_LINES: PackedStringArray = ["call.noor.rings", "noor.call.bye"]
## The ring of that phone, written out for as long as it rings (D-050).
const RING_LINE: String = "call.noor.rings"
## What ends the ring's line: the payload's "until" names this event.
const RING_UNTIL: String = "call_resolved"
const POCKET: StringName = &"pocket"
const SHOULDER: StringName = &"passenger_shoulder"
const KEY: StringName = &"key"
## Frames the button is down for a TAP, and seconds it is down at the pocket
## before the phone is carried off, then carried, in a DRAG_TO.
const TAP_FRAMES: int = 2
const DRAG_PRESS: float = 0.1
const DRAG_CARRY: float = 2.5

## Frames the drive scene is given to stand before a line is asked for, and
## frames the line is given before the picture is taken.
const SCENE_FRAMES: int = 10
const SHOT_FRAMES: int = 30
## Ticks the drive scene is given to come to what is asked of it.
const SCENE_GUARD: int = 600
## The Table of the Telling the drive scene is started with.
const TABLE: String = "drivers"

var _root: Window
var _data: GameData
var _tuning: Tuning
var _checks: int = 0
var _failed: int = 0
## A drive of this check's own (the Call): the simulation and what its player
## does; and, since that drive began, the line ids the simulation asked for,
## the events it announced, and each subtitle the view showed with the frames
## it was up.
var _sim: DriveSim
var _input: DriveInput = DriveInput.new()
var _asked: PackedStringArray = []
var _announced: Array[Dictionary] = []
var _seen: PackedStringArray = []
var _seen_frames: PackedInt32Array = []
var _showing: String = ""
## While the drive scene runs: the line ids that went over the Events bus,
## and how often a night ended there.
var _bus_lines: PackedStringArray = []
var _bus_arrivals: int = 0


## Runs every check, printing a PASS or FAIL line for each; returns how many
## failed. A view is put under the root of `tree`; the last checks run the
## drive scene in it, so this takes some frames and is awaited.
func run(tree: SceneTree) -> int:
	_root = tree.root
	_data = Game.data
	_tuning = _data.tuning
	var queue: SubtitleQueue = SubtitleQueue.new()
	queue.configure(_tuning)

	_wrapping(queue)
	_two_lines(queue)
	_durations(queue)
	_three_in_order()
	_until_it_is_over()
	_right_to_left(queue)
	_exchanges()
	_speakers()
	_settings()
	_numbers()
	_view()
	_few_wait()
	_tells_first()
	_written()
	_the_call()
	_scene()
	await _in_the_scene(tree)

	print("subtitles check: %d checks, %d failure(s)" % [_checks, _failed])
	return _failed


## A picture of right-to-left subtitles, saved as a PNG at `path` (it needs a
## renderer). The drive scene is started and a line of GDD 3.6 is asked for
## on the Events bus, with the line table as a writer will leave it: Arabic
## text for that line and for its speaker's name. That table is made in
## memory; lines_ar.csv itself stays empty (GDD 17.3).
func rtl_shot(tree: SceneTree, path: String) -> void:
	await _rtl_picture(tree, path, RTL_LONG)


## The same picture with a sentence whose second line begins with a Latin
## word (I-99): it stands at the right end of that line, where an Arabic
## reader begins it, because both lines are one paragraph.
func rtl_latin_shot(tree: SceneTree, path: String) -> void:
	await _rtl_picture(tree, path, RTL_LATIN_SECOND)


func _rtl_picture(tree: SceneTree, path: String, said: String) -> void:
	var shipped: GameData = Game.data
	var english: Dictionary = GameData.as_dict(shipped.lines.get("en")).duplicate(true)
	var arabic: Dictionary = GameData.as_dict(shipped.lines.get("ar")).duplicate(true)
	arabic[Lines.speaker_line_id(GameData.as_string(shipped.line(TWO_LINE_LINE).get("speaker")))] = {"speaker": "", "text": RTL_SPEAKER, "needs_writer": false}
	arabic[TWO_LINE_LINE] = {"speaker": "", "text": said, "needs_writer": false}
	tree.change_scene_to_file(DRIVE_SCENE)
	for frame: int in SCENE_FRAMES:
		await tree.process_frame
	Lines.setup(GameData.from_parts(shipped.roots, {"en": english, "ar": arabic}))
	Lines.set_locale("ar")
	Events.emit_event("line_requested", {"id": TWO_LINE_LINE})
	for frame: int in SHOT_FRAMES:
		await tree.process_frame
	var view: SubtitlesView = tree.current_scene.get_node("Subtitles") as SubtitlesView
	print("right-to-left: %s | %s" % [view.shown_speaker(), " | ".join(view.shown_lines())])
	_save_picture(tree, path)
	Lines.set_locale(Lines.FALLBACK_LOCALE)
	Lines.setup(shipped)


## A picture of what the simulation asks for, saved as a PNG at `path` (it
## needs a renderer): the drive scene on Dawn's road as the phone in his
## pocket rings (GDD 10.4), the pointer on the pocket, and a TAP there through
## the game's own input. Nothing is put on the Events bus by hand: the
## subtitle in the picture is the one the Call's ritual asked for.
func call_shot(tree: SceneTree, path: String) -> void:
	var drive: Node = await _answer_in_the_scene(tree)
	var sim: DriveSim = drive.get("sim") as DriveSim
	var view: SubtitlesView = drive.get_node("Subtitles") as SubtitlesView
	await _until_she_speaks(tree, drive)
	for frame: int in SHOT_FRAMES:
		_keep_lane(sim)
		await tree.process_frame
	print("the Call (%s, taken %s): %s | %s" % [sim.boss.call, sim.boss.call_taken, view.shown_speaker(), " | ".join(view.shown_lines())])
	_save_picture(tree, path)
	Game.args = {}


## A picture of a subtitle over the key (it needs a renderer): the street of
## the Arrival (GDD 10.5), the car standing in the bay, the pointer on the
## key under the wheel, which he must find and TAP to end the night, and a
## line of two lines asked for on the Events bus.
func key_shot(tree: SceneTree, path: String) -> void:
	var drive: Node = await _park_in_the_scene(tree, {})
	var sim: DriveSim = drive.get("sim") as DriveSim
	var view: SubtitlesView = drive.get_node("Subtitles") as SubtitlesView
	Events.emit_event("line_requested", {"id": TWO_LINE_LINE})
	for frame: int in SHOT_FRAMES:
		await tree.process_frame
	print("in the bay (%s), the hand at %s: %s | %s" % [str(sim.boss.in_bay), sim.hand.at_id(), view.shown_speaker(), " | ".join(view.shown_lines())])
	_save_picture(tree, path)
	Input.action_release("brake")
	Game.args = {}


## The drive scene on Dawn's road with nothing on it, a moment short of where
## the phone rings (GDD 10.4), the pointer held on his pocket; when it rings
## and the hand is there, a TAP through the game's own input. Returns the
## scene once the Call is no longer ringing and a frame has been drawn.
func _answer_in_the_scene(tree: SceneTree) -> Node:
	var drive: Node = await _drive_scene(tree, {"aim": String(POCKET)})
	var sim: DriveSim = drive.get("sim") as DriveSim
	sim.gate.reset(3)
	sim.begin_leg(_quiet_dawn(Game.data))
	sim.car.s = sim.leg.length - GameData.as_float(GameData.as_dict(GameData.as_dict(Game.data.record("bosses", BossSim.DAWN).get(BossSim.DAWN)).get("call")).get("from_end_m")) - 2.0
	var guard: int = SCENE_GUARD
	while (sim.boss.call != BossSim.CALL_RINGING or sim.hand.at_id() != POCKET) and guard > 0:
		guard -= 1
		_keep_lane(sim)
		await tree.physics_frame
	await _tap(tree)
	guard = SCENE_GUARD
	while sim.boss.call == BossSim.CALL_RINGING and guard > 0:
		guard -= 1
		_keep_lane(sim)
		await tree.physics_frame
	await _a_frame_drawn(tree)
	return drive


## The drive scene on the street of the Arrival (GDD 10.5): the car standing
## in its bay with the brake held, the pointer and the hand on the key under
## the wheel. `more` are further arguments for the scene (a Telling). The
## brake stays held: whoever asked lets it go.
func _park_in_the_scene(tree: SceneTree, more: Dictionary) -> Node:
	var arguments: Dictionary = {"aim": String(KEY)}
	arguments.merge(more)
	var drive: Node = await _drive_scene(tree, arguments)
	var sim: DriveSim = drive.get("sim") as DriveSim
	sim.begin_arrival()
	sim.car.s = sim.leg.length - GameData.as_float(GameData.as_dict(Game.data.root("legs").get(BossSim.ARRIVAL)).get("bay_m")) * 0.5
	sim.car.speed = 0.0
	Input.action_press("brake")
	var guard: int = SCENE_GUARD
	while (not sim.boss.in_bay or sim.hand.at_id() != KEY) and guard > 0:
		guard -= 1
		await tree.physics_frame
	return drive


## The drive scene, started with `arguments` (those of the command line) on
## an empty road, and given a moment to stand.
func _drive_scene(tree: SceneTree, arguments: Dictionary) -> Node:
	Game.args = arguments
	tree.change_scene_to_file(DRIVE_SCENE)
	for frame: int in SCENE_FRAMES:
		await tree.process_frame
	var sim: DriveSim = tree.current_scene.get("sim") as DriveSim
	sim.free_traffic_per_km = 0.0
	sim.traffic.clear()
	return tree.current_scene


## Waits until the Subtitles layer of the drive scene shows what Noor says
## on the Call: at once where nothing else is being shown, and behind it
## otherwise (the ring, where the simulation writes that out). False when it
## never comes.
func _until_she_speaks(tree: SceneTree, drive: Node) -> bool:
	var sim: DriveSim = drive.get("sim") as DriveSim
	var view: SubtitlesView = drive.get_node("Subtitles") as SubtitlesView
	var words: PackedStringArray = PackedStringArray([Lines.get_text(CALL_LINE)])
	var guard: int = SCENE_GUARD
	while not (view.is_showing() and view.shown_lines() == words) and guard > 0:
		guard -= 1
		_keep_lane(sim)
		await tree.physics_frame
	return view.is_showing() and view.shown_lines() == words


## A TAP of the grip button, as a player's: down for the ticks of TAP_FRAMES.
func _tap(tree: SceneTree) -> void:
	Input.action_press("grip")
	for tick: int in TAP_FRAMES * roundi(FRAME / DriveSim.DT):
		await tree.physics_frame
	Input.action_release("grip")


## Waits until the scene has drawn a frame after this moment: every node has
## had its _process once more.
func _a_frame_drawn(tree: SceneTree) -> void:
	await tree.process_frame
	await tree.process_frame


func _save_picture(tree: SceneTree, path: String) -> void:
	var image: Image = tree.root.get_texture().get_image()
	if image == null or image.is_empty():
		print("no picture: this renderer draws nothing")
	else:
		print("shot %s (%s)" % [path, error_string(image.save_png(path))])


# --- The pure class ----------------------------------------------------------

func _wrapping(queue: SubtitleQueue) -> void:
	_heading("42-character wrapping")
	var chars: int = queue.line_chars
	_check(chars == GDD_LINE_CHARS, "a line holds %d characters (tuning: %d)" % [GDD_LINE_CHARS, chars])

	var fits: String = _text_of(chars)
	var fit_lines: PackedStringArray = queue.lines_of(fits)
	_check(fit_lines.size() == 1 and fit_lines[0] == fits, "a text of %d characters is one line, as written" % chars)
	var over: String = _text_of(chars + 1)
	var over_lines: PackedStringArray = queue.lines_of(over)
	_check(over_lines.size() == 2 and " ".join(over_lines) == over, "a text of %d characters is two lines, cut at a space (%s)" % [chars + 1, _lengths(over_lines)])
	_check(_longest(over_lines) <= chars, "and neither is longer than %d" % chars)

	# Greedy filling: each line takes the words that fit, so the next word would not have.
	var long_text: String = _text_of(chars * 7)
	var long_lines: PackedStringArray = queue.lines_of(long_text)
	var greedy: bool = true
	for index: int in long_lines.size() - 1:
		var next_word: String = long_lines[index + 1].split(" ")[0]
		if long_lines[index].length() + 1 + next_word.length() <= chars:
			greedy = false
	_check(_longest(long_lines) <= chars and " ".join(long_lines) == long_text,
			"a text of %d characters is cut into %d lines of at most %d, every word whole and in its place" % [long_text.length(), long_lines.size(), chars])
	_check(greedy, "each of them is as full as its words allow")

	var spaced: PackedStringArray = queue.lines_of("  one   two\tthree\nfour  ")
	_check(spaced.size() == 1 and spaced[0] == "one two three four", "spaces, tabs and line ends between words count as one space")
	# A label breaks the line at these by itself: left in a line, they would make three lines of two.
	var ended: PackedStringArray = queue.lines_of("one\u2028two\u2029three\r\nfour\u000Bfive\u000Csix\u0085seven")
	_check(ended.size() == 1 and ended[0] == "one two three four five six seven", "and so does every other kind of line end (the line separator, the paragraph separator)")

	var word: String = "x".repeat(chars * 2 + 16)
	var word_lines: PackedStringArray = queue.lines_of(word)
	_check(_lengths(word_lines) == "%d, %d, 16" % [chars, chars], "a word of %d letters is cut where the line ends (%s)" % [word.length(), _lengths(word_lines)])

	var worst: int = 0
	var broken: String = ""
	var shown: int = 0
	for id: String in _data.line_ids():
		var entry: Dictionary = _data.line(id)
		if GameData.as_string(entry.get("speaker")).is_empty():
			continue
		for said: PackedStringArray in SubtitleQueue.exchange(GameData.as_string(entry.get("speaker")), GameData.as_string(entry.get("text"))):
			var lines: PackedStringArray = queue.lines_of(said[1])
			shown += 1
			worst = maxi(worst, _longest(lines))
			if " ".join(lines) != said[1]:
				broken = id
	_check(shown > 0 and worst <= chars and broken.is_empty(),
			"the %d things said in the line table wrap whole into lines of at most %d (longest %d%s)" % [shown, chars, worst, "" if broken.is_empty() else ", broken: " + broken])

	var narrator: Array[SubtitleQueue.Part] = queue.parts_of("", _line_text(TWO_LINE_LINE))
	var narrator_lines: PackedStringArray = narrator[0].lines if narrator.size() == 1 else PackedStringArray()
	_check(narrator_lines.size() == 2 and absi(narrator_lines[0].length() - narrator_lines[1].length()) <= 4 and narrator_lines[0].length() <= narrator_lines[1].length(),
			"two lines are cut where they are most alike, the upper the shorter: %s" % " | ".join(narrator_lines))


func _two_lines(queue: SubtitleQueue) -> void:
	_heading("never more than two lines at once")
	var most: int = queue.max_lines
	var chars: int = queue.line_chars
	_check(most == GDD_MAX_LINES, "%d lines are on screen at most (tuning: %d)" % [GDD_MAX_LINES, most])

	var three: String = _text_of(chars * 2 + chars / 2)
	var three_parts: Array[SubtitleQueue.Part] = queue.parts_of("", three)
	_check(queue.lines_of(three).size() == 3 and three_parts.size() == 2 and three_parts[0].lines.size() == 2 and three_parts[1].lines.size() == 1,
			"a text of three lines is shown in two parts, of two lines and of one")
	_check(_rejoined(three_parts) == three, "and the parts hold the whole text, in order")

	var long_parts: Array[SubtitleQueue.Part] = queue.parts_of("", _line_text(LONG_LINE))
	_check(long_parts.size() == 2 and long_parts[0].lines.size() == 2 and long_parts[1].lines.size() == 2,
			"the line %s (%d characters) is two parts of two lines" % [LONG_LINE, _line_text(LONG_LINE).length()])
	for part: SubtitleQueue.Part in long_parts:
		print("        %s" % " | ".join(part.lines))

	var most_found: int = 0
	var widest: int = 0
	var whole: bool = true
	var tried: int = 0
	for length: int in range(1, chars * 12, 7):
		var text: String = _text_of(length)
		var parts: Array[SubtitleQueue.Part] = queue.parts_of("", text)
		tried += 1
		whole = whole and _rejoined(parts) == text
		for part: SubtitleQueue.Part in parts:
			most_found = maxi(most_found, part.lines.size())
			widest = maxi(widest, _longest(part.lines))
	_check(most_found == most and widest <= chars and whole,
			"%d texts of 1 to %d characters: never more than %d lines of %d at once, nothing lost (found %d lines, %d characters)" % [tried, chars * 12, most, chars, most_found, widest])

	var table_most: int = 0
	for id: String in _data.line_ids():
		for part: SubtitleQueue.Part in queue.parts_of("", _line_text(id)):
			table_most = maxi(table_most, part.lines.size())
	_check(table_most <= most, "no line of the line table is ever more than %d lines at once (found %d)" % [most, table_most])


func _durations(queue: SubtitleQueue) -> void:
	_heading("the duration rule at 10, 25 and 100 characters")
	_check(is_equal_approx(queue.min_duration, GDD_MIN_DURATION) and is_equal_approx(queue.char_duration, GDD_CHAR_DURATION),
			"the rule is the larger of %s s and %s s per character (tuning: %s, %s)" % [str(GDD_MIN_DURATION), str(GDD_CHAR_DURATION), str(queue.min_duration), str(queue.char_duration)])
	# 10 characters ask for 0.6 s and 25 for exactly 1.5 s: both are held 1.5 s. 100 ask for 6 s.
	_check(absf(queue.duration_of(10) - 1.5) <= TOLERANCE, "10 characters are held 1.5 s (found %s)" % str(queue.duration_of(10)))
	_check(absf(queue.duration_of(25) - 1.5) <= TOLERANCE, "25 characters are held 1.5 s (found %s)" % str(queue.duration_of(25)))
	_check(absf(queue.duration_of(100) - 6.0) <= TOLERANCE, "100 characters are held 6.0 s (found %s)" % str(queue.duration_of(100)))
	_check(absf(queue.duration_of(26) - 1.56) <= TOLERANCE, "26 characters are held 1.56 s: from there on the length counts (found %s)" % str(queue.duration_of(26)))

	var ten: Array[SubtitleQueue.Part] = queue.parts_of("", _text_of(10))
	var twenty_five: Array[SubtitleQueue.Part] = queue.parts_of("", _text_of(25))
	_check(ten.size() == 1 and absf(ten[0].duration - 1.5) <= TOLERANCE and twenty_five.size() == 1 and absf(twenty_five[0].duration - 1.5) <= TOLERANCE,
			"a text of 10 characters and one of 25 are each one part, held 1.5 s")
	var hundred: Array[SubtitleQueue.Part] = queue.parts_of("", _text_of(100))
	var own_length: bool = hundred.size() == 2
	var sum: float = 0.0
	var told: PackedStringArray = []
	for index: int in hundred.size():
		var part: SubtitleQueue.Part = hundred[index]
		# A part that another follows is timed with the space it was cut off at.
		var length: int = part.joined().length() + (1 if index < hundred.size() - 1 else 0)
		own_length = own_length and absf(part.duration - maxf(queue.min_duration, queue.char_duration * float(length))) <= TOLERANCE
		sum += part.duration
		told.append("%d characters %s s" % [length, str(snappedf(part.duration, 0.001))])
	_check(own_length, "a text of 100 characters is two parts, each timed by its own length, the first with the space it was cut off at (%s)" % ", ".join(told))
	_check(sum >= 6.0 - TOLERANCE, "together they are held no less than the 6.0 s the whole text asks for (%s s)" % str(snappedf(sum, 0.001)))

	# The rule is for the text, however many parts it is shown in: no part's
	# cut may take time away from it.
	var long_text: String = _line_text(LONG_LINE)
	var long_parts: Array[SubtitleQueue.Part] = queue.parts_of("", long_text)
	var long_sum: float = _held(long_parts)
	_check(long_parts.size() == 2 and absf(long_sum - queue.duration_of(long_text.length())) <= TOLERANCE,
			"the two parts of %s are held %s s together: what its %d characters ask for (%s s)" % [LONG_LINE, str(snappedf(long_sum, 0.001)), long_text.length(), str(snappedf(queue.duration_of(long_text.length()), 0.001))])
	var tried: int = 0
	var most_parts: int = 0
	var short_by: float = 0.0
	for length: int in range(1, queue.line_chars * 12):
		var text: String = _text_of(length)
		var parts: Array[SubtitleQueue.Part] = queue.parts_of("", text)
		tried += 1
		most_parts = maxi(most_parts, parts.size())
		short_by = maxf(short_by, queue.duration_of(text.length()) - _held(parts))
	_check(tried > 0 and most_parts > 2 and short_by <= TOLERANCE,
			"%d texts of 1 to %d characters, in up to %d parts: none is held less than its characters ask for (short by %s s at most)" % [tried, queue.line_chars * 12 - 1, most_parts, str(snappedf(short_by, 0.001))])


func _three_in_order() -> void:
	_heading("a queue of three lines shown in order")
	var texts: PackedStringArray = [_text_of(10), _text_of(30), _text_of(60)]
	for frame_time: float in [FRAME, SLOW_FRAME]:
		var queue: SubtitleQueue = SubtitleQueue.new()
		queue.configure(_tuning)
		var expected: Array[SubtitleQueue.Part] = []
		for index: int in texts.size():
			queue.push("speaker %d" % index, texts[index])
			expected.append_array(queue.parts_of("speaker %d" % index, texts[index]))
			if index == 0:
				_check(queue.current() != null and queue.current().joined() == texts[0], "at %d frames a second: the first line is up as soon as it is asked for" % roundi(1.0 / frame_time))
			else:
				_check(queue.current().joined() == texts[0] and queue.size() == index + 1, "the line asked for next waits behind it (%d waiting)" % index)
		# What is up, frame after frame: each text, its speaker, the frames it was up.
		var shown_texts: PackedStringArray = []
		var shown_speakers: PackedStringArray = []
		var shown_frames: PackedInt32Array = []
		for frame: int in MOST_FRAMES:
			queue.advance(frame_time)
			var part: SubtitleQueue.Part = queue.current()
			if part == null:
				break
			if shown_texts.is_empty() or shown_texts[shown_texts.size() - 1] != part.joined():
				shown_texts.append(part.joined())
				shown_speakers.append(part.speaker)
				shown_frames.append(0)
			shown_frames[shown_frames.size() - 1] += 1
		var in_order: bool = shown_texts.size() == expected.size()
		var held: bool = in_order
		var told: PackedStringArray = []
		for index: int in mini(shown_texts.size(), expected.size()):
			var seconds: float = float(shown_frames[index]) * frame_time
			in_order = in_order and shown_texts[index] == expected[index].joined() and shown_speakers[index] == expected[index].speaker
			# Its whole time at least, and no more than a frame over it.
			held = held and seconds >= expected[index].duration - TOLERANCE and seconds <= expected[index].duration + frame_time + TOLERANCE
			told.append("%s s for %s" % [str(snappedf(seconds, 0.001)), str(snappedf(expected[index].duration, 0.001))])
		_check(in_order, "the three lines come up in the order they were asked for, each under its speaker (%d shown)" % shown_texts.size())
		_check(held, "each is held its own time, never less, a frame more at most (%s)" % ", ".join(told))
		_check(queue.is_empty() and queue.current() == null, "then nothing is showing and nothing waits")

	var cleared: SubtitleQueue = SubtitleQueue.new()
	cleared.configure(_tuning)
	for text: String in texts:
		cleared.push("", text)
	cleared.advance(FRAME)
	cleared.clear()
	cleared.advance(FRAME)
	_check(cleared.is_empty() and cleared.current() == null, "clear() takes away what is showing and what waits")
	cleared.push("", texts[1])
	cleared.advance(FRAME)
	_check(cleared.current() != null and cleared.current().joined() == texts[1], "and what is asked for afterwards is shown")


## A line may be said "until" something has happened: then it is over,
## showing or waiting, and what waited behind it has all of its own time.
func _until_it_is_over() -> void:
	_heading("a line that lasts until something happens is over when it does")
	var texts: PackedStringArray = [_text_of(60), _text_of(30), _text_of(20)]
	# Showing: what waited behind it takes its place at once, with its whole time.
	var queue: SubtitleQueue = SubtitleQueue.new()
	queue.configure(_tuning)
	queue.push("", texts[0], "over")
	queue.push("", texts[1])
	queue.advance(FRAME)
	for _frame: int in 30:
		queue.advance(FRAME)
	_check(queue.current() != null and queue.current().joined() == texts[0], "a line said until something is over is shown like any other while it is not")
	queue.drop("other")
	_check(queue.current().joined() == texts[0] and queue.size() == 2, "what another event ends leaves it alone")
	queue.drop("over")
	_check(queue.current() != null and queue.current().joined() == texts[1] and queue.size() == 1, "when it is over the line is gone and what waited behind it is up")
	var frames: int = 0
	for _frame: int in MOST_FRAMES:
		queue.advance(FRAME)
		if queue.current() == null:
			break
		frames += 1
	_check(_held_for(frames, queue.duration_of(texts[1].length())), "and that one is held its whole time (%d frames)" % frames)

	# Waiting: it never comes up, and what shows keeps the time it has had.
	queue = SubtitleQueue.new()
	queue.configure(_tuning)
	queue.push("", texts[0])
	queue.push("", texts[1], "over")
	queue.push("", texts[2])
	queue.advance(FRAME)
	var before: int = 30
	for _frame: int in before:
		queue.advance(FRAME)
	queue.drop("over")
	_check(queue.current().joined() == texts[0] and queue.size() == 2, "over while it waited, a line is taken out of the queue and what shows stays")
	var shown: PackedStringArray = []
	frames = before
	var first_frames: int = 0
	for _frame: int in MOST_FRAMES:
		queue.advance(FRAME)
		var part: SubtitleQueue.Part = queue.current()
		if part == null:
			break
		if part.joined() == texts[0]:
			frames += 1
			first_frames = frames
		if shown.is_empty() or shown[shown.size() - 1] != part.joined():
			shown.append(part.joined())
	_check(_held_for(first_frames + 1, queue.duration_of(texts[0].length())), "what was showing is held its own time, no longer (%d frames)" % (first_frames + 1))
	_check(shown == PackedStringArray([texts[0], texts[2]]), "and the line that is over never comes up (%d shown after)" % shown.size())
	queue.drop("")
	_check(queue.is_empty(), "nothing is dropped for no name")


func _right_to_left(queue: SubtitleQueue) -> void:
	_heading("right-to-left text passed through unchanged")
	var chars: int = queue.line_chars
	var short_lines: PackedStringArray = queue.lines_of(RTL_SHORT)
	_check(short_lines.size() == 1 and short_lines[0] == RTL_SHORT, "an Arabic text of %d characters is one line, character for character" % RTL_SHORT.length())

	var long_lines: PackedStringArray = queue.lines_of(RTL_LONG)
	_check(RTL_LONG.length() > chars and long_lines.size() == 2 and _longest(long_lines) <= chars,
			"an Arabic text of %d characters is cut into lines of at most %d (%s)" % [RTL_LONG.length(), chars, _lengths(long_lines)])
	_check(" ".join(long_lines) == RTL_LONG, "its lines put together are the text as it was written")
	_check(RTL_LONG.begins_with(long_lines[0]) and RTL_LONG.ends_with(long_lines[1]), "the first line holds the words that are read first, the last line the last")
	var marks: int = 0
	for line: String in long_lines:
		for character: String in line:
			if DIRECTION_MARKS.contains(character):
				marks += 1
	_check(marks == 0 and _longest(long_lines) + long_lines[1].length() + 1 == RTL_LONG.length(), "no direction mark is put in and no character is lost: the label that draws a line decides which way it runs")

	var parts: Array[SubtitleQueue.Part] = queue.parts_of(RTL_SHORT, RTL_LONG)
	_check(parts.size() == 1 and parts[0].speaker == RTL_SHORT and parts[0].joined() == RTL_LONG, "the part on screen holds the same characters in the same order, under an Arabic speaker tag")
	_check(absf(parts[0].duration - queue.duration_of(RTL_LONG.length())) <= TOLERANCE, "and is timed by its %d characters (%s s)" % [RTL_LONG.length(), str(snappedf(parts[0].duration, 0.001))])

	var twice: String = RTL_LONG + " " + RTL_LONG
	var twice_parts: Array[SubtitleQueue.Part] = queue.parts_of("", twice)
	_check(twice_parts.size() == 2 and _rejoined(twice_parts) == twice, "a longer Arabic text (%d characters) goes through in parts, unchanged" % twice.length())

	var mixed_parts: Array[SubtitleQueue.Part] = queue.parts_of("", RTL_MIXED)
	_check(_rejoined(mixed_parts) == RTL_MIXED, "Arabic with Latin letters and digits in it goes through unchanged")

	var said: Array[PackedStringArray] = SubtitleQueue.exchange("Noor, then Abu Noor", RTL_SHORT + " / " + RTL_LONG)
	_check(said.size() == 2 and said[0][1] == RTL_SHORT and said[1][1] == RTL_LONG, "an Arabic exchange is divided at its \" / \", each side unchanged")


func _exchanges() -> void:
	_heading("an exchange is shown as what each speaker says")
	var wreck: Dictionary = _data.line(EXCHANGE_LINE)
	var said: Array[PackedStringArray] = SubtitleQueue.exchange(GameData.as_string(wreck.get("speaker")), GameData.as_string(wreck.get("text")))
	_check(said.size() == 2 and said[0] == PackedStringArray(["Guest", "And then you died?"]) and said[1] == PackedStringArray(["Abu Noor", "No. That is not how it went."]),
			"%s is the Guest's question, then Abu Noor's answer" % EXCHANGE_LINE)
	var alone: Array[PackedStringArray] = SubtitleQueue.exchange("Uncle", "All night? / At your age?")
	_check(alone.size() == 1 and alone[0] == PackedStringArray(["Uncle", "All night? / At your age?"]), "what one speaker says is left whole, whatever is in it")
	var none: Array[PackedStringArray] = SubtitleQueue.exchange("", "[EXIT / FUEL]")
	_check(none.size() == 1 and none[0] == PackedStringArray(["", "[EXIT / FUEL]"]), "and so is a text with no speaker")
	var short: Array[PackedStringArray] = SubtitleQueue.exchange("Guest, then Abu Noor", "And then you died?")
	_check(short.size() == 1 and short[0] == PackedStringArray(["Guest, then Abu Noor", "And then you died?"]), "two speakers and one thing said are left as they are written")
	var more: Array[PackedStringArray] = SubtitleQueue.exchange("Guest, then Abu Noor", "And? / No. / Not like that.")
	_check(more.size() == 2 and more[1][1] == "No. / Not like that.", "the last speaker says all that is left")


# --- The line table, the settings --------------------------------------------

func _speakers() -> void:
	_heading("speaker tags are lines of the line table")
	var names: Dictionary = {}
	for id: String in _data.line_ids():
		var entry: Dictionary = _data.line(id)
		for said: PackedStringArray in SubtitleQueue.exchange(GameData.as_string(entry.get("speaker")), GameData.as_string(entry.get("text"))):
			if not said[0].is_empty():
				names[said[0]] = id
	var missing: PackedStringArray = []
	var untranslatable: PackedStringArray = []
	for speaker: Variant in names:
		var line_id: String = Lines.speaker_line_id(str(speaker))
		if line_id.is_empty() or not _data.has_line(line_id, "en"):
			missing.append("%s (%s, in %s)" % [str(speaker), line_id, str(names[speaker])])
		elif not _data.has_line(line_id, "ar"):
			untranslatable.append(line_id)
	_check(not names.is_empty() and missing.is_empty(), "each of the %d speakers the line table names has a line of its own%s" % [names.size(), "" if missing.is_empty() else "; missing: " + ", ".join(missing)])
	_check(untranslatable.is_empty(), "and each of those is in lines_ar.csv for the writer%s" % ("" if untranslatable.is_empty() else "; missing: " + ", ".join(untranslatable)))
	_check(Lines.speaker_line_id("Old woman") == "speaker.old_woman" and Lines.speaker_line_id(" Um  Noor's cousin ") == "speaker.um_noor_s_cousin",
			"a speaker's line is `speaker.` and the name in lower case with underscores")
	_check(Lines.get_speaker_name("Old woman") == GameData.as_string(_data.line("speaker.old_woman").get("text")), "the tag shown is the text of that line (%s)" % Lines.get_speaker_name("Old woman"))
	_check(Lines.get_speaker_name("A stranger") == "A stranger", "a speaker with no line is shown as the speaker column has it")
	_check(Lines.speaker_line_id(RTL_SHORT).is_empty() and Lines.get_speaker_name(RTL_SHORT) == RTL_SHORT, "and so is a name written in Arabic")

	# Who speaks is read from the English table alone (Lines.get_speaker): the
	# other files translate what is said and, once, each name. So their
	# speaker column stays empty, and what an exchange says stays divided.
	var named: PackedStringArray = []
	var undivided: PackedStringArray = []
	for locale: String in GameData.LINE_LOCALES:
		for id: String in _data.line_ids(locale):
			var row: Dictionary = _data.line(id, locale)
			if locale != Lines.FALLBACK_LOCALE and not GameData.as_string(row.get("speaker")).strip_edges().is_empty():
				named.append("%s (%s)" % [id, locale])
			var who: String = GameData.as_string(_data.line(id).get("speaker")) if _data.has_line(id) else ""
			var speakers: int = who.split(SubtitleQueue.SPEAKERS_THEN).size()
			var text: String = GameData.as_string(row.get("text"))
			if speakers > 1 and not text.strip_edges().is_empty() and SubtitleQueue.exchange(who, text).size() != speakers:
				undivided.append("%s (%s)" % [id, locale])
	_check(named.is_empty(), "no row of another language's file names a speaker: who speaks is the English table's to say%s" % ("" if named.is_empty() else "; named in: " + ", ".join(named)))
	_check(undivided.is_empty(), "a row that holds an exchange says as much as it names speakers, in every language that has its text%s" % ("" if undivided.is_empty() else "; not: " + ", ".join(undivided)))


func _settings() -> void:
	_heading("the Subtitles settings of GDD 17.1")
	Settings.reset_to_defaults()
	_check(Settings.has_setting(SubtitlesView.SIZE_SETTING) and Settings.has_setting(SubtitlesView.BACKGROUND_SETTING), "Settings knows `%s` and `%s`" % [SubtitlesView.SIZE_SETTING, SubtitlesView.BACKGROUND_SETTING])
	_check(GameData.as_string(Settings.get_value(SubtitlesView.SIZE_SETTING)) == "medium" and SubtitlesView.DEFAULT_SIZE == "medium", "the size is medium by default")
	_check(Settings.get_value(SubtitlesView.BACKGROUND_SETTING) is bool and GameData.as_bool(Settings.get_value(SubtitlesView.BACKGROUND_SETTING)), "the background is on by default")
	var sizes: Dictionary = _tuning.d("subtitle_font_sizes")
	_check(sizes.size() == 3 and GameData.as_float(sizes.get("small")) > 0.0 and GameData.as_float(sizes.get("small")) < GameData.as_float(sizes.get("medium")) and GameData.as_float(sizes.get("medium")) < GameData.as_float(sizes.get("large")),
			"tuning has the three sizes, small under medium under large (%s)" % str(sizes))
	# GDD 17.3: "Use a font slot per language in settings; the owner will add an Arabic font."
	var slots: PackedStringArray = []
	var empty: bool = true
	for locale: String in GameData.LINE_LOCALES:
		var slot: String = SubtitlesView.FONT_SETTING + locale
		if Settings.has_setting(slot):
			slots.append(slot)
			empty = empty and Settings.get_value(slot) is String and GameData.as_string(Settings.get_value(slot)).is_empty()
	_check(slots.size() == GameData.LINE_LOCALES.size() and empty, "Settings has a font slot for each language of the line files, empty by default (%s)" % ", ".join(slots))


## The validator knows the constants of GDD 15 by name; these it only reads
## as plain values, so their shapes are held here.
func _numbers() -> void:
	_heading("the tuning constants of the subtitles")
	var colours: PackedStringArray = ["subtitle_text_color", "subtitle_speaker_color", "subtitle_outline_color", "subtitle_background_color"]
	var bad: PackedStringArray = []
	for key: String in colours:
		if not _tuning.has(key) or not Color.html_is_valid(_tuning.s(key)):
			bad.append(key)
	_check(bad.is_empty(), "the four colours are colours%s" % ("" if bad.is_empty() else ": not " + ", ".join(bad)))
	_check(_tuning.i("subtitle_line_chars") >= 1 and _tuning.i("subtitle_max_lines") >= 1 and _tuning.f("subtitle_min_duration") > 0.0 and _tuning.f("subtitle_char_duration") >= 0.0,
			"a line has room for a character, a subtitle for a line, and it is held for some time")
	_check(_tuning.has("subtitle_max_waiting") and GameData.is_number(_tuning.raw("subtitle_max_waiting")) and _tuning.i("subtitle_max_waiting") >= 1,
			"one line at least may wait behind the one on screen (%d)" % _tuning.i("subtitle_max_waiting"))
	_check(_tuning.f("subtitle_speaker_scale") > 0.0 and _tuning.f("subtitle_outline_share") >= 0.0 and _tuning.f("subtitle_bottom_margin") >= 0.0
			and _tuning.a("subtitle_padding").size() == 2 and _tuning.fi("subtitle_padding", 0) >= 0.0 and _tuning.fi("subtitle_padding", 1) >= 0.0
			and _tuning.f("subtitle_line_spacing") >= 0.0 and _tuning.f("subtitle_speaker_gap") >= 0.0 and _tuning.f("subtitle_corner_radius") >= 0.0,
			"sizes, margins and gaps are not negative, and the padding is [sideways, up and down]")
	var alpha: float = _tuning.f("subtitle_background_alpha")
	_check(alpha >= 0.0 and alpha <= 1.0, "the background's opacity is between 0 and 1 (%s)" % str(alpha))
	var units: int = 0
	var keys: PackedStringArray = _tuning.keys_in_group("subtitles_view")
	for key: String in keys:
		if not _tuning.unit_of(key).is_empty():
			units += 1
	_check(keys.size() > 0 and units == keys.size(), "each of the %d constants says what it is in (_units)" % keys.size())


# --- The view ----------------------------------------------------------------

func _view() -> void:
	_heading("the view, from a line asked for on the Events bus to what its labels hold")
	Settings.reset_to_defaults()
	var view: SubtitlesView = SubtitlesView.new()
	view.name = "Subtitles"
	_root.add_child(view)
	view.setup(_data)
	var box: PanelContainer = view.get_node("Box") as PanelContainer
	var speaker: Label = view.get_node("Box/Rows/Speaker") as Label
	var text: Label = view.get_node("Box/Rows/Text") as Label
	var queue: SubtitleQueue = SubtitleQueue.new()
	queue.configure(_tuning)

	view._process(FRAME)
	_check(not view.is_showing() and not box.visible, "with nothing said nothing is drawn")

	# One line, and one asked for while it shows.
	Events.emit_event("line_requested", {"id": SHORT_LINE})
	Events.emit_event("line_requested", {"id": TWO_LINE_LINE})
	view._process(FRAME)
	_check(view.is_showing() and view.shown_speaker() == Lines.get_speaker_name(Lines.get_speaker(SHORT_LINE)) and view.shown_lines() == PackedStringArray([Lines.get_text(SHORT_LINE)]),
			"%s is shown under its speaker: %s: %s" % [SHORT_LINE, view.shown_speaker(), " | ".join(view.shown_lines())])
	_check(speaker.visible and speaker.text == "Noor" and text.text == "Baba? Are you awake?", "the labels hold the name and the words of the line table")
	_check(view.waiting() == 2, "the line asked for meanwhile waits")
	var short_frames: int = _frames_until_change(view)
	_check(_held_for(short_frames, queue.duration_of(Lines.get_text(SHORT_LINE).length())), "it is held 1.5 s (%d frames)" % short_frames)
	var narrator: PackedStringArray = view.shown_lines()
	_check(view.shown_speaker() == "Abu Noor" and narrator.size() == 2 and " ".join(narrator) == Lines.get_text(TWO_LINE_LINE) and text.text == SubtitlesView.LINE_BREAK.join(narrator),
			"then %s, on two lines: %s" % [TWO_LINE_LINE, " | ".join(narrator)])
	_check(SubtitlesView.LINE_BREAK == "\u2028" and not text.text.contains("\n") and text.get_line_count() == 2,
			"the label breaks the line at a line separator, not a line end: its two lines are one paragraph")
	var narrator_frames: int = _frames_until_change(view)
	_check(_held_for(narrator_frames, queue.duration_of(Lines.get_text(TWO_LINE_LINE).length())) and not view.is_showing() and view.waiting() == 0,
			"held %s s (%d frames), and then nothing is drawn" % [str(queue.duration_of(Lines.get_text(TWO_LINE_LINE).length())), narrator_frames])

	# An exchange: each under their own name, one after the other.
	Events.emit_event("line_requested", {"id": EXCHANGE_LINE})
	view._process(FRAME)
	var first: String = "%s: %s" % [view.shown_speaker(), " | ".join(view.shown_lines())]
	_frames_until_change(view)
	var second: String = "%s: %s" % [view.shown_speaker(), " | ".join(view.shown_lines())]
	_frames_until_change(view)
	_check(first == "Guest: And then you died?" and second == "Abu Noor: No. That is not how it went." and not view.is_showing(), "%s is shown as %s, then %s" % [EXCHANGE_LINE, first, second])

	# A line longer than two lines of 42 characters: in parts.
	Events.emit_event("line_requested", {"id": LONG_LINE})
	view._process(FRAME)
	var seen: PackedStringArray = []
	var widest: int = 0
	var most: int = 0
	var parts: int = 0
	while view.is_showing() and parts < MOST_FRAMES:
		parts += 1
		most = maxi(most, view.shown_lines().size())
		widest = maxi(widest, _longest(view.shown_lines()))
		seen.append_array(view.shown_lines())
		_frames_until_change(view)
	_check(parts == 2 and most == queue.max_lines and widest <= queue.line_chars and " ".join(seen) == Lines.get_text(LONG_LINE),
			"%s is shown in %d parts of at most %d lines of at most %d characters, all of it" % [LONG_LINE, parts, most, widest])

	# A line with no speaker has no tag.
	Events.emit_event("line_requested", {"id": "title.game_name"})
	view._process(FRAME)
	_check(view.is_showing() and not speaker.visible and view.shown_speaker().is_empty(), "a line with no speaker is shown without a tag")

	# A Wreck cuts off what was being said; what is asked for after it is shown at once.
	Events.emit_event("line_requested", {"id": TWO_LINE_LINE})
	Events.emit_event("wreck", {"table": "drivers", "act": 1, "retellings": 0})
	_check(not view.is_showing() and view.waiting() == 0, "a `wreck` on the bus takes away what is showing and what waits")
	Events.emit_event("line_requested", {"id": EXCHANGE_LINE})
	view._process(FRAME)
	_check(view.shown_speaker() == "Guest", "and what the Table says about it is shown at once")
	Events.emit_event("line_requested", {"id": SHORT_LINE})
	view.clear()
	view._process(FRAME)
	_check(not view.is_showing() and view.waiting() == 0 and not box.visible, "clear() leaves nothing showing and nothing waiting")

	# Where and how it is drawn.
	_check(is_equal_approx(box.anchor_left, 0.5) and is_equal_approx(box.anchor_right, 0.5) and is_equal_approx(box.anchor_top, 1.0) and is_equal_approx(box.anchor_bottom, 1.0)
			and box.grow_horizontal == Control.GROW_DIRECTION_BOTH and box.grow_vertical == Control.GROW_DIRECTION_BEGIN and is_equal_approx(box.offset_bottom, -_tuning.f("subtitle_bottom_margin")),
			"the box hangs from the bottom centre of the screen, %s px up, and grows from there" % str(_tuning.f("subtitle_bottom_margin")))
	_check(text.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER and speaker.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER, "the tag and the text are centred")
	_check(text.text_direction == Control.TEXT_DIRECTION_AUTO and speaker.text_direction == Control.TEXT_DIRECTION_AUTO, "the text direction of both labels is automatic")
	_check(box.mouse_filter == Control.MOUSE_FILTER_IGNORE and text.mouse_filter == Control.MOUSE_FILTER_IGNORE and speaker.mouse_filter == Control.MOUSE_FILTER_IGNORE, "nothing of it takes the mouse")

	# The two settings, applied the moment they change.
	var sizes: Dictionary = _tuning.d("subtitle_font_sizes")
	var followed: bool = true
	var told: PackedStringArray = []
	for size_name: Variant in sizes:
		Settings.set_value(SubtitlesView.SIZE_SETTING, str(size_name))
		var found: int = text.get_theme_font_size("font_size")
		followed = followed and found == GameData.as_int(sizes[size_name]) and speaker.get_theme_font_size("font_size") == roundi(float(found) * _tuning.f("subtitle_speaker_scale"))
		told.append("%s %d" % [str(size_name), found])
	_check(followed, "the letters take the size of `%s` as soon as it is set (%s)" % [SubtitlesView.SIZE_SETTING, ", ".join(told)])
	var flat: StyleBoxFlat = box.get_theme_stylebox("panel") as StyleBoxFlat
	_check(flat != null and is_equal_approx(flat.bg_color.a, _tuning.f("subtitle_background_alpha")), "with `%s` on the text stands on its background" % SubtitlesView.BACKGROUND_SETTING)
	Settings.set_value(SubtitlesView.BACKGROUND_SETTING, false)
	var bare: StyleBox = box.get_theme_stylebox("panel")
	_check(bare is StyleBoxEmpty and flat != null and is_equal_approx(bare.content_margin_left, flat.content_margin_left) and is_equal_approx(bare.content_margin_top, flat.content_margin_top),
			"set off, the background is gone at once and the text has not moved")
	_check(text.get_theme_constant("outline_size") > 0, "and the letters keep their outline (%d px)" % text.get_theme_constant("outline_size"))
	Settings.set_value(SubtitlesView.BACKGROUND_SETTING, true)
	_check(box.get_theme_stylebox("panel") is StyleBoxFlat, "set on again, it is back")
	# A settings file edited by hand may name a size there is not: the view says so (one warning) and shows medium.
	print("        (one warning about the size 'huge' is expected here)")
	Settings.set_value(SubtitlesView.SIZE_SETTING, "huge")
	_check(text.get_theme_font_size("font_size") == GameData.as_int(sizes.get(SubtitlesView.DEFAULT_SIZE)), "a size that tuning does not have is shown as %s" % SubtitlesView.DEFAULT_SIZE)

	# Nothing is left behind for the next tool or test.
	Settings.reset_to_defaults()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.user_dir.path_join(Settings.FILE_NAME)))
	view.free()


## GDD 16.6 says nothing of a queue. Lines wait their turn, so that nothing
## said is cut short; but a line of the line table is not queued again while
## it is showing or waiting, and only `subtitle_max_waiting` of them wait:
## for one more, the one that has waited longest gives way. Otherwise six
## TAPs on a passenger's shoulder are six subtitles, and what is said after
## them (the ring of his phone) comes seconds late.
func _few_wait() -> void:
	_heading("a line is not said twice over, and only a few wait")
	var most: int = _tuning.i("subtitle_max_waiting")
	var queue: SubtitleQueue = _new_queue()
	_check(queue.max_waiting == most and most >= 2, "%d lines may wait behind the one on screen (tuning): three asked for at once are all shown" % most)
	var texts: PackedStringArray = [_text_of(30), _text_of(40), _text_of(50), _text_of(60)]
	var hold: int = _frames_in(queue.duration_of(texts[0].length()))

	# Asked for again while it is showing, and while it waits.
	var said: bool = _say(queue, "line.a", texts[0])
	queue.advance(FRAME)
	for _frame: int in hold / 2:
		queue.advance(FRAME)
	var again: bool = _say(queue, "line.a", texts[0])
	_check(said and not again and queue.size() == 1 and queue.holds("line.a"), "a line asked for again while it is showing is not queued again")
	var next: bool = _say(queue, "line.b", texts[1])
	var next_again: bool = _say(queue, "line.b", texts[1])
	_check(next and not next_again and queue.size() == 2 and queue.lines_waiting() == 1, "nor is one that waits")
	var frames: int = 1 + hold / 2
	while queue.current() != null and queue.current().line_id == "line.a" and frames < MOST_FRAMES:
		queue.advance(FRAME)
		frames += 1
	_check(_held_for(frames - 1, queue.duration_of(texts[0].length())), "and the line on screen is held no longer for it (%d frames)" % (frames - 1))
	_check(queue.current() != null and queue.current().line_id == "line.b" and not queue.holds("line.a") and _say(queue, "line.a", texts[0]) and queue.size() == 2,
			"once it has had its time it can be said again")

	# One more than may wait: the one that has waited longest gives way.
	queue = _new_queue()
	var ids: PackedStringArray = []
	for index: int in most + 2:
		ids.append("line.%d" % index)
	for index: int in most + 1:
		_say(queue, ids[index], texts[index % texts.size()])
	queue.advance(FRAME)
	_check(queue.lines_waiting() == most and queue.size() == most + 1, "with one line on screen, %d wait" % most)
	for _frame: int in hold / 2:
		queue.advance(FRAME)
	_check(_say(queue, ids[most + 1], texts[0]) and queue.lines_waiting() == most and not queue.holds(ids[1]) and queue.holds(ids[0]) and queue.holds(ids[most + 1]),
			"one more is asked for: the line that has waited longest gives way to it, and the line on screen stays")
	var order: PackedStringArray = []
	frames = 1 + hold / 2
	var head_frames: int = 0
	for _frame: int in MOST_FRAMES:
		var part: SubtitleQueue.Part = queue.current()
		if part == null:
			break
		if order.is_empty() or order[order.size() - 1] != part.line_id:
			order.append(part.line_id)
		if part.line_id == ids[0]:
			head_frames = frames
		queue.advance(FRAME)
		frames += 1
	var kept: PackedStringArray = ids.duplicate()
	kept.remove_at(1)
	_check(order == kept, "what is left is shown in the order it was asked for (%s)" % ", ".join(order))
	_check(_held_for(head_frames, queue.duration_of(texts[0].length())), "and the line on screen had its whole time, no more (%d frames)" % head_frames)

	# A line of several parts is one line: on screen, its parts to come are
	# not counted; waiting, it gives way whole.
	queue = _new_queue()
	var long_text: String = _text_of(queue.line_chars * (queue.max_lines * 2 + 1))
	var long_parts: int = queue.parts_of("", long_text).size()
	_say(queue, "long.a", long_text)
	queue.advance(FRAME)
	_say(queue, "long.b", long_text)
	for index: int in most - 1:
		_say(queue, ids[index], texts[0])
	_check(long_parts > 2 and queue.lines_waiting() == most and queue.size() == long_parts * 2 + most - 1,
			"a line of %d parts on screen: its parts to come are not lines that wait" % long_parts)
	_check(_say(queue, ids[most], texts[0]) and not queue.holds("long.b") and queue.lines_waiting() == most and queue.size() == long_parts + most,
			"a waiting line of %d parts gives way whole; the parts of the line on screen stay" % long_parts)

	# What is pushed without a line of the table is neither counted nor dropped.
	queue = _new_queue()
	for text: String in texts:
		queue.push("", text)
	queue.advance(FRAME)
	for index: int in most + 1:
		_say(queue, ids[index], texts[0])
	_check(queue.size() == texts.size() + most and queue.lines_waiting() == most and not queue.holds(ids[0]) and not queue.holds(""),
			"what is pushed without a line is not counted and does not give way (%d parts, %d lines waiting)" % [queue.size(), queue.lines_waiting()])
	queue.clear()
	queue.push("", texts[0])
	_check(queue.current().line_id.is_empty(), "after clear() what is pushed belongs to no line")

	# The same through the view: lines asked for on the Events bus.
	Settings.reset_to_defaults()
	var view: SubtitlesView = SubtitlesView.new()
	view.name = "Subtitles"
	_root.add_child(view)
	view.setup(_data)
	var asked: PackedStringArray = [SHORT_LINE, "heckle.children.twist.sheep", "heckle.drivers.dare.gear4", "heckle.uncles.doubt.1", "heckle.aunts.order.tea"]
	Events.emit_event("line_requested", {"id": asked[0]})
	Events.emit_event("line_requested", {"id": asked[0]})
	view._process(FRAME)
	Events.emit_event("line_requested", {"id": asked[0]})
	_check(view.is_showing() and view.waiting() == 1, "%s asked for three times on the bus is on screen once" % asked[0])
	for index: int in range(1, most + 2):
		Events.emit_event("line_requested", {"id": asked[index]})
		Events.emit_event("line_requested", {"id": asked[index]})
	var shown: PackedStringArray = []
	while view.is_showing() and shown.size() < MOST_FRAMES:
		shown.append(" ".join(view.shown_lines()))
		_frames_until_change(view)
	var expected: PackedStringArray = [Lines.get_text(asked[0])]
	for index: int in range(2, most + 2):
		expected.append(Lines.get_text(asked[index]))
	_check(most + 2 <= asked.size() and shown == expected, "%d more asked for twice each: all but the first of them are shown, once each, in order (%d subtitles)" % [most + 1, shown.size()])
	Settings.reset_to_defaults()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.user_dir.path_join(Settings.FILE_NAME)))
	view.free()


## A line of the line table said to a bare queue, as the view says it: false
## if the queue would not have it again.
func _say(queue: SubtitleQueue, line_id: String, text: String) -> bool:
	if not queue.begin_line(line_id):
		return false
	queue.push("", text)
	return true


## A tell is said (GDD 2.2 pillar 4: it announces something a moment ahead).
func _tell(queue: SubtitleQueue, line_id: String, text: String, until: String = "") -> bool:
	if not queue.begin_line(line_id):
		return false
	queue.push("", text, until, true)
	return true


## The lines a queue shows from now until it is empty, in order, and the
## frames each is on screen (counted as _until_it_is_over counts them).
func _play_out(queue: SubtitleQueue) -> Array:
	var order: PackedStringArray = []
	var frames: Dictionary = {}
	for _frame: int in MOST_FRAMES:
		queue.advance(FRAME)
		var part: SubtitleQueue.Part = queue.current()
		if part == null:
			break
		if order.is_empty() or order[order.size() - 1] != part.line_id:
			order.append(part.line_id)
		frames[part.line_id] = GameData.as_int(frames.get(part.line_id)) + 1
	return [order, frames]


## A tell does not wait its turn: what announces something 1 or 2 s ahead
## would otherwise be read when it has happened.
func _tells_first() -> void:
	_heading("a tell is shown at once, and what it took the screen from is shown again after it")
	var texts: PackedStringArray = [_text_of(50), _text_of(40), _text_of(30), _text_of(35)]
	var queue: SubtitleQueue = _new_queue()
	_say(queue, "line.a", texts[0])
	_say(queue, "line.b", texts[1])
	queue.advance(FRAME)
	for _frame: int in 20:
		queue.advance(FRAME)
	_check(queue.current() != null and queue.current().line_id == "line.a" and queue.size() == 2, "(a line is showing and another waits)")
	_check(_tell(queue, "line.tell", texts[2]) and queue.current().line_id == "line.tell", "a tell takes the screen in the frame it is asked for")
	_check(queue.size() == 3 and queue.holds("line.a") and queue.holds("line.b"), "nothing that was showing or waiting is lost for it")
	_check(not _tell(queue, "line.tell", texts[2]) and queue.size() == 3, "asked for again while it shows, it is not said twice over")
	var played: Array = _play_out(queue)
	var order: PackedStringArray = played[0]
	var frames: Dictionary = played[1]
	_check(order == PackedStringArray(["line.tell", "line.a", "line.b"]), "the tell, then the line it took the screen from, then what waited: %s" % ", ".join(order))
	_check(_held_for(GameData.as_int(frames.get("line.tell")), queue.duration_of(texts[2].length())), "the tell is held its whole time (%d frames)" % GameData.as_int(frames.get("line.tell")))
	_check(_held_for(GameData.as_int(frames.get("line.a")), queue.duration_of(texts[0].length())), "the line it interrupted is shown again for its whole time (%d frames)" % GameData.as_int(frames.get("line.a")))
	_check(_held_for(GameData.as_int(frames.get("line.b")), queue.duration_of(texts[1].length())), "and what waited has its whole time (%d frames)" % GameData.as_int(frames.get("line.b")))

	# With nothing showing a tell is a line like any other.
	queue = _new_queue()
	_tell(queue, "line.tell", texts[2])
	played = _play_out(queue)
	order = played[0]
	frames = played[1]
	_check(order == PackedStringArray(["line.tell"]) and _held_for(GameData.as_int(frames.get("line.tell")), queue.duration_of(texts[2].length())), "said into the silence, a tell is shown for its time like any line")

	# An exchange that is a tell keeps its order, and a later tell goes before an earlier one.
	queue = _new_queue()
	_say(queue, "line.a", texts[0])
	queue.advance(FRAME)
	queue.begin_line("line.two")
	queue.push("One", texts[1], "", true)
	queue.push("Other", texts[2], "", true)
	_check(queue.current().speaker == "One" and queue.size() == 3, "a tell of two speakers: the first of them takes the screen")
	_tell(queue, "line.late", texts[3])
	_check(queue.current().line_id == "line.late", "a tell asked for while another shows goes before it")
	var speakers: PackedStringArray = []
	for _frame: int in MOST_FRAMES:
		queue.advance(FRAME)
		var part: SubtitleQueue.Part = queue.current()
		if part == null:
			break
		var who: String = "%s/%s" % [part.line_id, part.speaker]
		if speakers.is_empty() or speakers[speakers.size() - 1] != who:
			speakers.append(who)
	_check(speakers == PackedStringArray(["line.late/", "line.two/One", "line.two/Other", "line.a/"]), "then the earlier tell, its speakers in their order, then the line: %s" % ", ".join(speakers))

	# A tell that lasts until something happens: over, what it interrupted is back at once.
	queue = _new_queue()
	_say(queue, "line.a", texts[0])
	queue.advance(FRAME)
	for _frame: int in 20:
		queue.advance(FRAME)
	_tell(queue, "line.ring", texts[2], "over")
	_check(queue.current().line_id == "line.ring", "(a tell that lasts until something is over)")
	queue.advance(FRAME)
	queue.advance(FRAME)
	queue.drop("over")
	_check(queue.current() != null and queue.current().line_id == "line.a" and queue.size() == 1, "when it is over the line it interrupted is back")
	played = _play_out(queue)
	frames = played[1]
	_check(_held_for(GameData.as_int(frames.get("line.a")), queue.duration_of(texts[0].length())), "with its whole time before it (%d frames)" % GameData.as_int(frames.get("line.a")))

	# No more lines wait for a tell than may wait.
	var most: int = _tuning.i("subtitle_max_waiting")
	queue = _new_queue()
	_say(queue, "line.0", texts[0])
	queue.advance(FRAME)
	for index: int in most:
		_say(queue, "line.w%d" % index, texts[1])
	_check(queue.lines_waiting() == most, "(as many wait as may: %d)" % most)
	_tell(queue, "line.tell", texts[2])
	_check(queue.current().line_id == "line.tell" and queue.lines_waiting() == most and queue.holds("line.0") and not queue.holds("line.w0"),
			"a tell with the queue full: the one that waited longest gives way, the one on screen comes after the tell")

	# Through the view: asked for on the bus with "tell".
	Settings.reset_to_defaults()
	var view: SubtitlesView = SubtitlesView.new()
	view.name = "Subtitles"
	_root.add_child(view)
	view.setup(_data)
	Events.emit_event("line_requested", {"id": TWO_LINE_LINE})
	view._process(FRAME)
	view._process(FRAME)
	_check(view.is_showing() and " ".join(view.shown_lines()) == Lines.get_text(TWO_LINE_LINE), "(the view shows a line)")
	Events.emit_event("line_requested", {"id": SHORT_LINE, "tell": true})
	view._process(FRAME)
	_check(view.shown_lines() == PackedStringArray([Lines.get_text(SHORT_LINE)]), "a line asked for on the bus as a tell is on screen in the next frame: %s" % " | ".join(view.shown_lines()))
	var tell_frames: int = _frames_until_change(view)
	_check(_held_for(tell_frames, view_duration(SHORT_LINE)) and " ".join(view.shown_lines()) == Lines.get_text(TWO_LINE_LINE), "after its time the line it interrupted is shown again")
	Events.emit_event("line_requested", {"id": SHORT_LINE})
	view._process(FRAME)
	_check(" ".join(view.shown_lines()) == Lines.get_text(TWO_LINE_LINE), "(asked for without \"tell\", the same line waits its turn)")
	view.clear()
	_root.remove_child(view)
	view.free()
	# The simulation's tells: what it writes out a moment ahead is asked for as one.
	var marked: PackedStringArray = []
	var tell: RegEx = RegEx.new()
	tell.compile("line_requested.*\"id\":\\s*\"([a-z0-9_.]+)\".*\"tell\":\\s*true")
	for path: String in ProjectFiles.find("res://src/core", PackedStringArray(["gd"])):
		for line: String in FileAccess.get_file_as_string(path).split("\n"):
			var hit: RegExMatch = tell.search(line)
			if hit != null:
				marked.append(hit.get_string(1))
	marked.sort()
	print("tells: the simulation asks for %s as tells" % ", ".join(marked))
	for id: String in TELL_LINES:
		_check(marked.has(id), "%s announces something a moment ahead: the simulation must ask for it as a tell" % id)


## Seconds the view holds a line of one part.
func view_duration(line_id: String) -> float:
	var queue: SubtitleQueue = _new_queue()
	return queue.duration_of(Lines.get_text(line_id).length())


func _new_queue() -> SubtitleQueue:
	var queue: SubtitleQueue = SubtitleQueue.new()
	queue.configure(_tuning)
	return queue


## The line table as a writer will leave it, made in memory (lines_ar.csv
## itself stays empty, GDD 17.3): a name line that says more than the speaker
## columns do; Arabic for a line that needs two lines, cut so that the second
## begins with a Latin word; and an exchange whose speaker column is filled
## in as well, in Arabic, which no writer is asked for. What is held: the tag
## is the text of the speaker's own line; both lines of a subtitle run the
## way their sentence does; and who speaks, and how many they are, is read
## from the English table whatever another one says. Then the font the owner
## will add for the language (GDD 17.3): its slot in the settings, with a
## font made here standing in for it.
func _written() -> void:
	_heading("a line table as the writer will leave it: names, right to left, an exchange, a font")
	var english: Dictionary = GameData.as_dict(_data.lines.get("en")).duplicate(true)
	var arabic: Dictionary = GameData.as_dict(_data.lines.get("ar")).duplicate(true)
	var written: Dictionary = {"speaker": "", "text": "", "needs_writer": false}
	var exchange: Array[PackedStringArray] = SubtitleQueue.exchange(_line_speaker(RTL_EXCHANGE_LINE), _line_text(RTL_EXCHANGE_LINE))
	english[Lines.speaker_line_id(_line_speaker(SHORT_LINE))] = written.merged({"text": WRITTEN_NAME}, true)
	arabic[Lines.speaker_line_id(_line_speaker(TWO_LINE_LINE))] = written.merged({"text": RTL_SPEAKER}, true)
	arabic[Lines.speaker_line_id(exchange[0][0])] = written.merged({"text": RTL_CHILD}, true)
	arabic[TWO_LINE_LINE] = written.merged({"text": RTL_LATIN_SECOND}, true)
	arabic[RTL_EXCHANGE_LINE] = written.merged({"speaker": RTL_SPEAKERS, "text": RTL_ASKED + SubtitleQueue.SAID_THEN + RTL_ANSWERED}, true)
	Lines.setup(GameData.from_parts(_data.roots, {"en": english, "ar": arabic}))
	Settings.reset_to_defaults()
	var view: SubtitlesView = SubtitlesView.new()
	view.name = "Subtitles"
	_root.add_child(view)
	view.setup(_data)
	var text: Label = view.get_node("Box/Rows/Text") as Label

	# A name is a line: what the tag shows is that line's text.
	Events.emit_event("line_requested", {"id": SHORT_LINE})
	view._process(FRAME)
	_check(_line_speaker(SHORT_LINE) != WRITTEN_NAME and view.shown_speaker() == WRITTEN_NAME,
			"the tag is the text of the speaker's own line, not what the speaker column writes: %s" % view.shown_speaker())
	view.clear()

	# Arabic on two lines, the second beginning with a Latin word.
	Lines.set_locale("ar")
	Events.emit_event("line_requested", {"id": TWO_LINE_LINE})
	view._process(FRAME)
	var lines: PackedStringArray = view.shown_lines()
	_check(view.shown_speaker() == RTL_SPEAKER and lines.size() == 2 and " ".join(lines) == RTL_LATIN_SECOND and lines[1].begins_with(LATIN_WORD),
			"in Arabic, %s is under his Arabic name on two lines, the second beginning with %s" % [TWO_LINE_LINE, LATIN_WORD])
	# Where the label draws its letters: a line that runs right to left has
	# its first letter at its right end. (No frame is drawn here, so the box
	# has not grown yet: the label is given the room its text asks for.)
	text.reset_size()
	var upper_first: Rect2 = text.get_character_bounds(0)
	var upper_last: Rect2 = text.get_character_bounds(lines[0].length() - 1)
	var lower_first: Rect2 = text.get_character_bounds(text.text.find(LATIN_WORD))
	var lower_last: Rect2 = text.get_character_bounds(text.text.length() - 1)
	_check(text.get_line_count() == 2 and upper_first.position.y < lower_first.position.y and is_equal_approx(lower_first.position.y, lower_last.position.y),
			"the label draws them as two lines")
	_check(upper_first.position.x > upper_last.position.x, "the first line runs right to left")
	_check(lower_first.position.x > lower_last.position.x,
			"and so does the second, though it begins with a Latin word: %s stands at its right end (%d px right of its last letter)" % [LATIN_WORD, roundi(lower_first.position.x - lower_last.position.x)])
	view.clear()

	# An exchange: who speaks, and how many they are, is the English table's to say.
	Events.emit_event("line_requested", {"id": RTL_EXCHANGE_LINE})
	view._process(FRAME)
	var asked: String = "%s: %s" % [view.shown_speaker(), " | ".join(view.shown_lines())]
	_frames_until_change(view)
	var answered: String = "%s: %s" % [view.shown_speaker(), " | ".join(view.shown_lines())]
	_frames_until_change(view)
	_check(Lines.get_speaker(RTL_EXCHANGE_LINE) == _line_speaker(RTL_EXCHANGE_LINE), "who says %s is read from the English table, whatever the Arabic row's speaker column holds" % RTL_EXCHANGE_LINE)
	_check(asked == "%s: %s" % [RTL_CHILD, RTL_ASKED] and answered == "%s: %s" % [RTL_SPEAKER, RTL_ANSWERED] and not view.is_showing(),
			"so it is still two subtitles, each under the name its speaker's own line gives in Arabic")

	# The font slot of the language (GDD 17.3). A font made here stands in
	# for the one the owner will add. (Test runs in other checkouts clear the
	# folder the tools share, so it is made again before the font goes in.)
	var speaker: Label = view.get_node("Box/Rows/Speaker") as Label
	var slot: String = SubtitlesView.FONT_SETTING + "ar"
	var font_path: String = Game.user_dir.path_join("subtitles_check_font_%d.tres" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(Game.user_dir))
	var saved: Error = ResourceSaver.save(SystemFont.new(), font_path)
	var own: Font = text.get_theme_font("font")
	_check(saved == OK and _given_font(text).is_empty() and _given_font(speaker).is_empty(), "while the slots are empty the labels take the theme's font")
	Settings.set_value(slot, font_path)
	_check(_given_font(text) == font_path and _given_font(speaker) == font_path,
			"a font named in `%s` is taken by the tag and the text as soon as it is set, the lines being in Arabic" % slot)
	var face: FontVariation = text.get_theme_font("font") as FontVariation
	_check(face != null and face.fallbacks.size() == 1 and is_same(face.fallbacks[0], own), "with the theme's font behind it, for the letters it does not have")
	Lines.set_locale(Lines.FALLBACK_LOCALE)
	_check(_given_font(text).is_empty() and _given_font(speaker).is_empty(), "in English, whose slot is empty, they take the theme's font again")
	Lines.set_locale("ar")
	_check(_given_font(text) == font_path and _given_font(speaker) == font_path, "and in Arabic the Arabic font")
	Settings.set_value(slot, "")
	_check(_given_font(text).is_empty() and _given_font(speaker).is_empty(), "an emptied slot gives the theme's font back at once")
	# A settings file edited by hand may name what is no font: the view says so (one warning) and keeps the theme's.
	print("        (one warning about the font 'res://data/tuning.json' is expected here)")
	Settings.set_value(slot, "res://data/tuning.json")
	_check(_given_font(text).is_empty() and _given_font(speaker).is_empty(), "a slot that names no font leaves the theme's font")

	# Nothing is left behind for the next tool or test.
	Lines.set_locale(Lines.FALLBACK_LOCALE)
	Lines.setup(_data)
	Settings.reset_to_defaults()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.user_dir.path_join(Settings.FILE_NAME)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(font_path))
	view.free()


# --- What the simulation asks for ---------------------------------------------

## The Call (GDD 10.4, the simulation's since M7) is the first thing in play
## that somebody says. Dawn's road is driven here by a simulation of this
## check's own, a frame at a time as the drive scene runs it, to where the
## phone in his pocket rings; then it is left to ring out, answered alone
## with a TAP, and handed to a passenger. Nothing is put on the Events bus
## by hand: what the view shows is what the simulation asked for.
##
## What is held is about her line. Whatever else the simulation has written
## out by then (the ring itself, where it does that) is shown as any line
## is, before hers, and is no business of this check.
func _the_call() -> void:
	_heading("the Call of Dawn (GDD 10.4): the simulation asks for what Noor says, and it is shown")
	Settings.reset_to_defaults()
	var view: SubtitlesView = SubtitlesView.new()
	view.name = "Subtitles"
	_root.add_child(view)
	view.setup(_data)
	var queue: SubtitleQueue = SubtitleQueue.new()
	queue.configure(_tuning)
	var ring_s: float = GameData.as_float(_call_numbers().get("ring_s"))
	var tag: String = Lines.get_speaker_name(Lines.get_speaker(CALL_LINE))
	var said: String = "%s: %s" % [tag, Lines.get_text(CALL_LINE)]
	var hold: float = queue.duration_of(Lines.get_text(CALL_LINE).length())

	# What takes the Call is a ritual at his pocket, and it is the ritual that asks for her line.
	var takers: PackedStringArray = []
	var asking: PackedStringArray = []
	for ritual: Dictionary in _data.records("rituals"):
		var takes: bool = false
		var lines: PackedStringArray = []
		for op: Variant in GameData.as_array(ritual.get("on_complete")):
			var text: String = GameData.as_string(op)
			if text.begins_with("call:"):
				takes = true
			elif text.begins_with("line:"):
				lines.append(text.trim_prefix("line:"))
		if takes:
			takers.append(GameData.as_string(ritual.get("id")))
			if lines == PackedStringArray([CALL_LINE]):
				asking.append(GameData.as_string(ritual.get("id")))
	_check(not takers.is_empty() and asking == takers, "each ritual that takes the Call asks for %s, once (%s)" % [CALL_LINE, ", ".join(takers)])

	# It rings, and rings out.
	_to_the_ring(view, false)
	var rang: Dictionary = _last("call_started")
	_check(_count("call_started") == 1 and _unspoken(said), "the phone in his pocket rings: she has not spoken yet")
	_check(Lines.speaker_line_id(Lines.get_speaker(CALL_LINE)) == Lines.SPEAKER_PREFIX + GameData.as_string(rang.get("caller")),
			"who rings is who speaks in %s (%s)" % [CALL_LINE, GameData.as_string(rang.get("caller"))])
	_drive(view, _frames_in(ring_s + 1.0))
	_check(_count("call_resolved") == 1 and not GameData.as_bool(_last("call_resolved").get("answered")) and _unspoken(said),
			"left to ring for its %s s it is over unanswered, and she never spoke" % str(ring_s))

	# Answered alone: a TAP on his pocket.
	_to_the_ring(view, false)
	var at_pocket: bool = _reach(view, POCKET)
	var unspoken: bool = _unspoken(said)
	_input.lmb = true
	_drive(view, TAP_FRAMES)
	_input.lmb = false
	_until_answered(view)
	_check(at_pocket and unspoken and GameData.as_bool(_last("call_resolved").get("answered")) and GameData.as_string(_last("call_resolved").get("taken")) == BossSim.TAKEN_ALONE,
			"a TAP on his pocket answers it alone; until then she has not spoken")
	_check_said(view, said, hold)

	# Handed to a passenger: she does not speak while the phone is carried.
	_to_the_ring(view, true)
	_reach(view, POCKET)
	_input.lmb = true
	_drive(view, _frames_in(DRAG_PRESS))
	_input.pointer = _sim.hand.anchor_pointer(_sim.hand.anchor_index(SHOULDER))
	_drive(view, _frames_in(DRAG_CARRY))
	unspoken = _unspoken(said) and _count("call_resolved") == 0
	_input.lmb = false
	_until_answered(view)
	_check(unspoken and GameData.as_bool(_last("call_resolved").get("answered")) and GameData.as_string(_last("call_resolved").get("taken")) == BossSim.TAKEN_WITH_PASSENGER,
			"dragged to a passenger's shoulder and let go there, it is answered with them; she does not speak while it is carried")
	_check_said(view, said, hold)

	# The ring is written out for as long as it rings (D-050) and no longer:
	# answered at once, its line is gone and she is heard in that frame.
	var ring: String = ": %s" % Lines.get_text(RING_LINE)
	var ring_hold: float = queue.duration_of(Lines.get_text(RING_LINE).length())
	_to_the_ring(view, false)
	_drive(view, 2)
	var asked_until: bool = false
	for event: Dictionary in _announced:
		if GameData.as_string(event.get("type")) == "line_requested" and GameData.as_string(event.get("id")) == RING_LINE:
			asked_until = GameData.as_string(event.get("until")) == RING_UNTIL
	_check(asked_until and _showing == ring, "as it rings the simulation writes the ring out, until `%s` (%s)" % [RING_UNTIL, _showing])
	_reach(view, POCKET)
	_input.lmb = true
	_drive(view, TAP_FRAMES)
	_input.lmb = false
	_until_answered(view)
	var answered_after: float = float(_seen_frames[_seen.find(ring)]) * FRAME if _seen.has(ring) else -1.0
	_check(GameData.as_bool(_last("call_resolved").get("answered")) and answered_after >= 0.0 and answered_after < ring_hold - FRAME,
			"(answered %s s into the ring's %s s)" % [str(snappedf(answered_after, 0.01)), str(snappedf(ring_hold, 0.01))])
	_check(_showing == said, "answered, the ring's line is gone and she is on screen in that frame: %s" % _showing)
	_check_said(view, said, hold)
	_check(_seen.count(ring) == 1, "and the ring's line does not come back")
	# An answer that comes too late is none: a TAP on his pocket that ends
	# after the Call has rung out takes nothing, and she says nothing.
	_to_the_ring(view, false)
	_reach(view, POCKET)
	var guard: int = _frames_in(ring_s + 1.0)
	while _sim.boss.call == BossSim.CALL_RINGING and _sim.boss.call_left > FRAME * 1.5 and guard > 0:
		guard -= 1
		_drive(view, 1)
	var still_ringing: bool = _sim.boss.call == BossSim.CALL_RINGING and _sim.hand.at_id() == POCKET
	_input.lmb = true
	_drive(view, TAP_FRAMES)
	_input.lmb = false
	_drive(view, _frames_in(0.5))
	_check(still_ringing and _count("call_resolved") == 1 and not GameData.as_bool(_last("call_resolved").get("answered")),
			"(a TAP begun in the Call's last frame ends after it has rung out: unanswered)")
	_check(_unspoken(said), "an answer that comes too late asks for nothing: she does not speak")
	# Left to ring, the line has its own time: it is not held for all the ringing.
	_to_the_ring(view, false)
	_drive(view, _frames_in(ring_s + 1.0))
	var ring_frames: int = _seen_frames[_seen.find(ring)] if _seen.has(ring) else 0
	_check(_held_for(ring_frames, ring_hold) and _seen.count(ring) == 1, "left to ring, the line has its own %s s (%d frames), once" % [str(snappedf(ring_hold, 0.01)), ring_frames])

	Settings.reset_to_defaults()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.user_dir.path_join(Settings.FILE_NAME)))
	view.free()
	_sim = null


## Her line has not been asked for in this drive and has not been on screen.
func _unspoken(said: String) -> bool:
	return not _asked.has(CALL_LINE) and not _seen.has(said)


## In the frame of an answer: her line is the last thing the simulation
## asked for, and it asked once. It is on screen in that frame, under her
## name, or comes up the moment what was showing has had its time; it is
## held its own time, once, and nothing follows it.
func _check_said(view: SubtitlesView, said: String, hold: float) -> void:
	_check(_asked.count(CALL_LINE) == 1 and _asked[_asked.size() - 1] == CALL_LINE, "the simulation asks for %s as he answers, once" % CALL_LINE)
	var before: String = _showing
	var waited: int = 0
	var gap: bool = false
	var guard: int = MOST_FRAMES
	while _showing != said and guard > 0:
		guard -= 1
		gap = gap or _showing.is_empty()
		waited += 1
		_drive(view, 1)
	_check(_showing == said and not gap, "and it is on screen %s: %s" % ["in that frame" if waited == 0 else "%d frames on, when '%s' has had its time" % [waited, before], _showing])
	guard = MOST_FRAMES
	while view.is_showing() and guard > 0:
		guard -= 1
		_drive(view, 1)
	var at: int = _seen.find(said)
	var frames: int = _seen_frames[at] if at != -1 else 0
	_check(_seen.count(said) == 1 and at == _seen.size() - 1 and _held_for(frames, hold) and _asked.count(CALL_LINE) == 1,
			"held %s s (%d frames), once; then nothing is drawn" % [str(hold), frames])


## The numbers of the Call in Dawn's record (data/legs.json).
func _call_numbers() -> Dictionary:
	return GameData.as_dict(GameData.as_dict(_data.record("bosses", BossSim.DAWN).get(BossSim.DAWN)).get("call"))


## A new drive: Dawn's road with nothing on it (its plan without its
## vehicles), the car in third gear a moment short of where the phone rings,
## driven on until it does. `passenger`: somebody sits beside him.
func _to_the_ring(view: SubtitlesView, passenger: bool) -> void:
	view.clear()
	_sim = DriveSim.new(_data)
	_input.clear()
	_asked = []
	_announced = []
	_seen = []
	_seen_frames = []
	_showing = ""
	_sim.gate.reset(3)
	_sim.begin_leg(_quiet_dawn(_data))
	_sim.items.flags[&"passenger"] = passenger
	_sim.car.s = _sim.leg.length - GameData.as_float(_call_numbers().get("from_end_m")) - 2.0
	var guard: int = _frames_in(5.0)
	while _sim.boss.call != BossSim.CALL_RINGING and guard > 0:
		guard -= 1
		_drive(view, 1)


## Dawn's road as BossSim plans it, without the vehicles of its plan.
func _quiet_dawn(data: GameData) -> Dictionary:
	var plan: Dictionary = BossSim.plan(data, BossSim.DAWN, "", 1)
	for key: String in ["spawns", "hazards", "curves"]:
		plan[key] = []
	return plan


## Frames of the drive scene as its controller makes them: the simulation's
## ticks, every event it announces sent to the Events bus, then the view's
## frame. Nobody steers here, so the road is kept under the car.
func _drive(view: SubtitlesView, frames: int) -> void:
	for _frame: int in frames:
		for _tick: int in roundi(FRAME / DriveSim.DT):
			_keep_lane(_sim)
			_sim.step(_input)
			for event: Dictionary in _sim.drain_events():
				var type: String = GameData.as_string(event.get("type"))
				_announced.append(event)
				if type == "line_requested":
					_asked.append(GameData.as_string(event.get("id")))
				Events.emit_event(type, event)
		view._process(FRAME)
		var now: String = "%s: %s" % [view.shown_speaker(), " | ".join(view.shown_lines())] if view.is_showing() else ""
		if not now.is_empty():
			if now != _showing:
				_seen.append(now)
				_seen_frames.append(0)
			_seen_frames[_seen_frames.size() - 1] += 1
		_showing = now


## The car in the middle of the lane it is in.
func _keep_lane(sim: DriveSim) -> void:
	sim.car.x = sim.car.lane_center(clampi(sim.car.lane_of(sim.car.x), 0, sim.car.lanes - 1))


## The pointer goes to an anchor and stays there; the hand follows until it
## rests on it.
func _reach(view: SubtitlesView, anchor: StringName) -> bool:
	_input.clear()
	_input.pointer_is_absolute = true
	_input.pointer = _sim.hand.anchor_pointer(_sim.hand.anchor_index(anchor))
	var guard: int = _frames_in(3.0)
	while _sim.hand.at_id() != anchor and guard > 0:
		guard -= 1
		_drive(view, 1)
	return _sim.hand.at_id() == anchor


## Drives on, a frame at a time, until the Call has been answered or has rung out.
func _until_answered(view: SubtitlesView) -> void:
	var guard: int = _frames_in(1.0)
	while _count("call_resolved") == 0 and guard > 0:
		guard -= 1
		_drive(view, 1)


## The last event of a kind that the drive announced ({} when there was none).
func _last(type: String) -> Dictionary:
	for index: int in range(_announced.size() - 1, -1, -1):
		if GameData.as_string(_announced[index].get("type")) == type:
			return _announced[index]
	return {}


func _count(type: String) -> int:
	var count: int = 0
	for event: Dictionary in _announced:
		if GameData.as_string(event.get("type")) == type:
			count += 1
	return count


## Whole frames in a time.
func _frames_in(seconds: float) -> int:
	return roundi(seconds / FRAME)


func _scene() -> void:
	_heading("the Subtitles layer of %s" % DRIVE_SCENE)
	var scene: PackedScene = load(DRIVE_SCENE) as PackedScene
	var state: SceneState = scene.get_state()
	# The children of the scene's root, in the order they are drawn in.
	var order: PackedStringArray = []
	var subtitles: int = -1
	for index: int in state.get_node_count():
		if index > 0 and state.get_node_path(index, true) == NodePath("."):
			order.append(String(state.get_node_name(index)))
			if state.get_node_name(index) == &"Subtitles":
				subtitles = index
	_check(subtitles != -1 and state.get_node_type(subtitles) == &"CanvasLayer", "the scene has a CanvasLayer named Subtitles under its root (GDD 13.5)")
	var script_path: String = ""
	if subtitles != -1:
		for property: int in state.get_node_property_count(subtitles):
			if state.get_node_property_name(subtitles, property) == &"script":
				script_path = (state.get_node_property_value(subtitles, property) as Script).resource_path
	_check(script_path == VIEW_SCRIPT, "it runs %s" % VIEW_SCRIPT)
	var at: int = order.find("Subtitles")
	var pointer: int = order.find("Overlay")
	var post_fx: int = order.find("PostFX")
	_check(at != -1 and pointer != -1 and at < pointer, "it comes before the Overlay: the pointer is drawn over the subtitles")
	if post_fx != -1:
		_check(post_fx < at, "it comes after PostFX: the subtitles are drawn over the post effects")
	else:
		print("        (no PostFX layer in this scene yet: it belongs before Subtitles)")
	print("        %s" % ", ".join(order))


## The drive scene itself, running (it needs no renderer): started with
## `--say=`, and driven through the game's own input as far as M7 lets it be
## driven in a moment: the Call answered on Dawn's road, and a Telling ended
## with the key in the bay of the Arrival. What is checked is the scene's own
## wiring: its controller asks for the lines of `--say`, it sends what the
## simulation announces to the Events bus, its Subtitles layer listens there,
## and the controller clears it where the night begins again.
func _in_the_scene(tree: SceneTree) -> void:
	_heading("the drive scene running: --say, the Call answered, and the night begun again")
	Events.line_requested.connect(_on_bus_line)
	Events.arrived.connect(_on_bus_arrived)

	# `--say=`: the scene asks for those lines as it starts, and they are shown.
	_bus_lines = []
	var said: PackedStringArray = [LONG_LINE, SHORT_LINE]
	var drive: Node = await _drive_scene(tree, {"say": ",".join(said)})
	var layer: SubtitlesView = drive.get_node("Subtitles") as SubtitlesView
	var queue: SubtitleQueue = SubtitleQueue.new()
	queue.configure(_tuning)
	var first: Array[SubtitleQueue.Part] = queue.parts_of("", Lines.get_text(said[0]))
	_check(_bus_lines == said, "started with --say=%s, the scene asks for those lines on the Events bus, in that order" % ",".join(said))
	_check(layer.is_showing() and layer.shown_lines() == first[0].lines and layer.shown_speaker() == Lines.get_speaker_name(Lines.get_speaker(said[0])) and layer.waiting() == first.size() + 1,
			"and its Subtitles layer shows the first of them, the other waiting: %s: %s" % [layer.shown_speaker(), " | ".join(layer.shown_lines())])

	# Dawn's road: the phone rings, the hand is on his pocket, a TAP.
	_bus_lines = []
	drive = await _answer_in_the_scene(tree)
	var sim: DriveSim = drive.get("sim") as DriveSim
	var view: SubtitlesView = drive.get_node("Subtitles") as SubtitlesView
	_check(sim.boss.call == BossSim.CALL_TALKING and sim.boss.call_taken == BossSim.TAKEN_ALONE,
			"on Dawn's road a TAP of the grip button with the pointer on his pocket answers the Call")
	_check(_bus_lines.count(CALL_LINE) == 1 and _bus_lines[_bus_lines.size() - 1] == CALL_LINE,
			"the scene sends what the Call's ritual asks for to the Events bus, once (%s)" % ", ".join(_bus_lines))
	var spoken: bool = await _until_she_speaks(tree, drive)
	_check(spoken and view.shown_speaker() == Lines.get_speaker_name(Lines.get_speaker(CALL_LINE)) and view.waiting() == 1,
			"and its Subtitles layer shows it: %s: %s" % [view.shown_speaker(), " | ".join(view.shown_lines())])

	# A Telling, its car put in the bay of the Arrival while something is being said: the key ends the night.
	drive = await _park_in_the_scene(tree, {"table": TABLE, "seed": "1"})
	sim = drive.get("sim") as DriveSim
	view = drive.get_node("Subtitles") as SubtitlesView
	var telling_seed: int = sim.run.seed
	var parked: bool = sim.run.active and sim.boss.in_bay and sim.hand.at_id() == KEY
	Events.emit_event("line_requested", {"id": LONG_LINE})
	await _a_frame_drawn(tree)
	_check(parked and view.is_showing() and view.waiting() == 2, "a Telling's car stands in the bay of the Arrival, the hand on the key, while a line of two parts is said")
	_bus_arrivals = 0
	await _tap(tree)
	var guard: int = SCENE_GUARD
	while _bus_arrivals == 0 and guard > 0:
		guard -= 1
		await tree.physics_frame
	await _a_frame_drawn(tree)
	Input.action_release("brake")
	_check(_bus_arrivals == 1 and sim.run.active and sim.run.seed == telling_seed + 1, "a TAP on the key ends the night (`arrived`), and the scene begins the Telling again")
	_check(not view.is_showing() and view.waiting() == 0, "nothing that was being said is left on screen or waiting")

	# Nothing is left behind for the next tool or test.
	Events.line_requested.disconnect(_on_bus_line)
	Events.arrived.disconnect(_on_bus_arrived)
	Game.args = {}
	drive.queue_free()
	await tree.process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.save_path()))


func _on_bus_line(event: Dictionary) -> void:
	_bus_lines.append(GameData.as_string(event.get("id")))


func _on_bus_arrived(_event: Dictionary) -> void:
	_bus_arrivals += 1


# --- Helpers -----------------------------------------------------------------

func _heading(what: String) -> void:
	print("== %s" % what)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
	print("%s  %s" % ["PASS" if ok else "FAIL", what])


## A text of exactly `length` characters: words of one to nine letters with
## single spaces between them, ending in a letter.
func _text_of(length: int) -> String:
	var text: String = ""
	var word: int = 0
	while text.length() < length:
		if not text.is_empty():
			text += " "
		word += 1
		text += "abcdefghi".substr(0, 1 + (word * 4) % 9)
	text = text.substr(0, length)
	if text.ends_with(" "):
		text = text.substr(0, length - 1) + "z"
	return text


func _line_text(id: String) -> String:
	return GameData.as_string(_data.line(id).get("text"))


## Who says a line, as the speaker column of the English table writes it.
func _line_speaker(id: String) -> String:
	return GameData.as_string(_data.line(id).get("speaker"))


## The path of the font a label has been given in place of the theme's own
## ("" while it has the theme's).
func _given_font(label: Label) -> String:
	if not label.has_theme_font_override("font"):
		return ""
	var face: FontVariation = label.get_theme_font("font") as FontVariation
	return face.base_font.resource_path if face != null and face.base_font != null else "?"


func _longest(lines: PackedStringArray) -> int:
	var longest: int = 0
	for line: String in lines:
		longest = maxi(longest, line.length())
	return longest


func _lengths(lines: PackedStringArray) -> String:
	var lengths: PackedStringArray = []
	for line: String in lines:
		lengths.append(str(line.length()))
	return ", ".join(lengths)


## The parts' lines put together again as one text.
func _rejoined(parts: Array[SubtitleQueue.Part]) -> String:
	var texts: PackedStringArray = []
	for part: SubtitleQueue.Part in parts:
		texts.append(part.joined())
	return " ".join(texts)


## Seconds the parts are held, one after the other.
func _held(parts: Array[SubtitleQueue.Part]) -> float:
	var seconds: float = 0.0
	for part: SubtitleQueue.Part in parts:
		seconds += part.duration
	return seconds


## Steps the view frame by frame until what it shows is something else (or
## nothing) and returns the frames the old subtitle was on screen.
func _frames_until_change(view: SubtitlesView) -> int:
	var speaker: String = view.shown_speaker()
	var lines: PackedStringArray = view.shown_lines()
	var frames: int = 1
	while frames < MOST_FRAMES:
		view._process(FRAME)
		if not view.is_showing() or view.shown_speaker() != speaker or view.shown_lines() != lines:
			break
		frames += 1
	return frames


## On screen for its whole time, and a frame more at most.
func _held_for(frames: int, duration: float) -> bool:
	var seconds: float = float(frames) * FRAME
	return seconds >= duration - TOLERANCE and seconds <= duration + FRAME + TOLERANCE
