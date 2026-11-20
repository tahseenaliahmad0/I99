class_name SubtitleQueue
extends RefCounted
## The wrapping, the timing and the queue of the subtitles (GDD 16.6): "at
## most two lines of 42 characters, with a speaker tag. Duration is the
## larger of 1.5 s and 0.06 s per character."
##
## Pure: no Node, no autoload, no clock of its own. SubtitlesView pushes what
## is said and calls advance() once for every frame it draws;
## tools/subtitles_check.gd checks the rules here without a picture.
##
## A text is cut at its spaces into lines of at most `line_chars` characters.
## What needs more than `max_lines` lines is shown in parts, one after the
## other, and each part is held for the time its own length asks for. What
## is pushed while something is showing waits its turn.
##
## Characters are counted as the text holds them and are never changed or put
## in another order, so right-to-left text goes through as it was written:
## the first line holds the words that are read first, and the label that
## draws a line decides which way it runs.

## The line table writes an exchange as one row (GDD 3.6): its speaker column
## names who speaks, in order ("Guest, then Abu Noor"), and its text holds
## what each of them says, divided by " / ".
const SPEAKERS_THEN: String = GameData.SPEAKERS_THEN
const SAID_THEN: String = " / "


## What is on screen at one time: a speaker tag and a few lines.
class Part:
	extends RefCounted
	var speaker: String = ""
	var lines: PackedStringArray = []
	## Seconds it is held on screen.
	var duration: float = 0.0
	## What ends it before its time: the name of an event (GDD 13.6) after
	## which it is no longer true ("" when it simply runs its time).
	var until: String = ""

	## The lines as the one text they were cut from.
	func joined() -> String:
		return " ".join(lines)


## Characters in a line (GDD 16.6: 42) and lines on screen at once (2).
var line_chars: int = 1
var max_lines: int = 1
## The shortest time anything is held, and the time each character asks for.
var min_duration: float = 0.0
var char_duration: float = 0.0

var _parts: Array[Part] = []
## Seconds the part at the head has been on screen.
var _elapsed: float = 0.0
## The part at the head has not been drawn yet.
var _fresh: bool = false


func configure(tuning: Tuning) -> void:
	line_chars = maxi(1, tuning.i("subtitle_line_chars"))
	max_lines = maxi(1, tuning.i("subtitle_max_lines"))
	min_duration = tuning.f("subtitle_min_duration")
	char_duration = tuning.f("subtitle_char_duration")


# --- Wrapping and timing -----------------------------------------------------

## Who says what in a row of the line table, in order: [[speaker, text], ...].
## A row with one speaker is one entry. A row that names several speakers and
## does not hold as many things said is left whole, under the speakers as
## they are written.
static func exchange(speakers: String, text: String) -> Array[PackedStringArray]:
	var who: PackedStringArray = speakers.split(SPEAKERS_THEN)
	var said: PackedStringArray = text.split(SAID_THEN, true, who.size() - 1)
	var out: Array[PackedStringArray] = []
	if who.size() > 1 and said.size() == who.size():
		for index: int in who.size():
			out.append(PackedStringArray([who[index].strip_edges(), said[index].strip_edges()]))
	else:
		out.append(PackedStringArray([speakers.strip_edges(), text]))
	return out


## `text` cut at its spaces into lines of at most line_chars characters, each
## as full as its words allow. A word longer than a line is cut where the
## line ends: nothing on screen is ever wider than line_chars.
func lines_of(text: String) -> PackedStringArray:
	var lines: PackedStringArray = []
	var line: String = ""
	for word: String in _words(text):
		if line.is_empty():
			line = word
		elif line.length() + 1 + word.length() <= line_chars:
			line += " " + word
		else:
			lines.append(line)
			line = word
	if not line.is_empty():
		lines.append(line)
	return lines


## What `text` is on screen: one part for a text of up to max_lines lines,
## several for a longer one, each timed by its own length.
func parts_of(speaker: String, text: String) -> Array[Part]:
	var parts: Array[Part] = []
	var lines: PackedStringArray = lines_of(text)
	var index: int = 0
	while index < lines.size():
		var part: Part = Part.new()
		part.speaker = speaker
		part.lines = _balanced(lines.slice(index, index + max_lines))
		part.duration = duration_of(part.joined().length())
		parts.append(part)
		index += max_lines
	return parts


## Seconds a text of so many characters is held: min_duration at least.
func duration_of(characters: int) -> float:
	return maxf(min_duration, char_duration * float(characters))


# --- The queue ---------------------------------------------------------------

## Something is said: it is shown at once if nothing is showing, and after
## what is showing and waiting otherwise. `until` names what ends it early.
func push(speaker: String, text: String, until: String = "") -> void:
	var was_empty: bool = _parts.is_empty()
	for part: Part in parts_of(speaker, text):
		part.until = until
		_parts.append(part)
	if was_empty and not _parts.is_empty():
		_elapsed = 0.0
		_fresh = true


## What was said "until" this has happened is over, showing or waiting (a
## phone that was ringing has been answered). What waited behind the part
## on screen takes its place with all of its own time before it.
func drop(until: String) -> void:
	if until.is_empty() or _parts.is_empty():
		return
	var head_gone: bool = _parts[0].until == until
	var kept: Array[Part] = []
	for part: Part in _parts:
		if part.until != until:
			kept.append(part)
	_parts = kept
	if head_gone:
		_elapsed = 0.0
		_fresh = not _parts.is_empty()


## Called once for every frame that is drawn, with the seconds since the
## frame before, and before current() is read for the new frame. A part's
## time begins with the frame it is first drawn in, so it is on screen for
## its whole duration at least, whatever the frame rate; then the next part
## takes its place, with all of its own time before it.
func advance(delta: float) -> void:
	if _parts.is_empty():
		return
	if _fresh:
		_fresh = false
		return
	_elapsed += delta
	if _elapsed >= _parts[0].duration:
		_parts.remove_at(0)
		_elapsed = 0.0


## What is on screen now; null when nothing is.
func current() -> Part:
	if _parts.is_empty():
		return null
	return _parts[0]


## Parts showing and waiting.
func size() -> int:
	return _parts.size()


func is_empty() -> bool:
	return _parts.is_empty()


## Nothing is showing and nothing waits (a Telling that begins again).
func clear() -> void:
	_parts.clear()
	_elapsed = 0.0
	_fresh = false


# --- Internals ---------------------------------------------------------------

## The words of a text: what stands between its spaces, tabs and line ends.
## A word longer than a line comes as pieces of a line's length.
func _words(text: String) -> PackedStringArray:
	var words: PackedStringArray = []
	var spaced: String = text.replace("\n", " ").replace("\r", " ").replace("\t", " ")
	for entry: String in spaced.split(" ", false):
		var word: String = entry
		while word.length() > line_chars:
			words.append(word.substr(0, line_chars))
			word = word.substr(line_chars)
		words.append(word)
	return words


## Two lines read best when they are about as long as each other: the same
## words, cut where the two lines differ least in length (the upper line the
## shorter one where two cuts are as good). Any other number of lines is left
## as it was wrapped.
func _balanced(lines: PackedStringArray) -> PackedStringArray:
	if lines.size() != 2:
		return lines
	var words: PackedStringArray = lines[0].split(" ")
	words.append_array(lines[1].split(" "))
	var total: int = lines[0].length() + 1 + lines[1].length()
	var best_count: int = 0
	var best_gap: int = total
	var upper: int = -1
	for count: int in range(1, words.size()):
		upper += 1 + words[count - 1].length()
		var lower: int = total - upper - 1
		if upper > line_chars or lower > line_chars:
			continue
		var gap: int = absi(upper - lower)
		if gap < best_gap:
			best_gap = gap
			best_count = count
	if best_count == 0:
		return lines
	return PackedStringArray([" ".join(words.slice(0, best_count)), " ".join(words.slice(best_count))])
