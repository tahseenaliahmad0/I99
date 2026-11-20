extends Node
## The line database (GDD 1.3, 17.3): every player-facing string, by id.
##
## The GDD spells the lookup `Lines.get(id)`. `get` is a native Object method
## that GDScript must not override, so the lookup is `Lines.get_text(id)`
## (see docs/DECISIONS.md).

signal locale_changed(locale: String)

const FALLBACK_LOCALE: String = "en"
## A speaker's name is a line of its own, so that it is written, and
## translated, once: this prefix and the name as a speaker column writes it,
## in lower case with underscores ("Old woman" is `speaker.old_woman`).
const SPEAKER_PREFIX: String = "speaker."

var locale: String = FALLBACK_LOCALE

var _data: GameData


func setup(data: GameData) -> void:
	_data = data


func set_locale(code: String) -> void:
	if _data == null or not _data.lines.has(code):
		push_error("Lines: no line file for locale '%s'" % code)
		return
	if code != locale:
		locale = code
		locale_changed.emit(locale)


func has_line(id: String) -> bool:
	return _data != null and _data.has_line(id, FALLBACK_LOCALE)


## The text of a line in the current locale. A line the writer has not filled
## in yet falls back to its English placeholder. An unknown id is an error and
## shows as the id in square brackets.
func get_text(id: String) -> String:
	return _field(id, "text")


## Who says a line ("" when nobody is named): its speaker column in the
## English table, whatever the locale. Who speaks is not text to translate:
## a row that holds an exchange names its speakers in a form ("Guest, then
## Abu Noor") that another language would not keep, so the speaker column of
## the other line files stays empty and is not read. A name is translated
## once, in the speaker's own line: what a speaker tag shows is
## get_speaker_name().
func get_speaker(id: String) -> String:
	return _field(id, "speaker", false)


## A speaker's name as a speaker tag shows it (GDD 16.6): the text of the
## speaker's own line in the current locale. `speaker` is what a speaker
## column holds. A speaker who has no line is shown as the column has it.
func get_speaker_name(speaker: String) -> String:
	var id: String = speaker_line_id(speaker)
	if not id.is_empty() and has_line(id):
		return get_text(id)
	return speaker


## The id of the line that holds a speaker's name: "Old woman" gives
## "speaker.old_woman". "" for a name with no Latin letter or digit in it.
func speaker_line_id(speaker: String) -> String:
	var key: String = ""
	var gap: bool = false
	for character: String in speaker.to_lower():
		if (character >= "a" and character <= "z") or (character >= "0" and character <= "9"):
			if gap and not key.is_empty():
				key += "_"
			key += character
			gap = false
		else:
			gap = true
	return "" if key.is_empty() else SPEAKER_PREFIX + key


## get_text with printf-style values, e.g. format("stop.price", [15]).
func format(id: String, values: Array) -> String:
	return get_text(id) % values


func needs_writer(id: String) -> bool:
	if not has_line(id):
		return false
	return GameData.as_bool(_data.line(id, FALLBACK_LOCALE).get("needs_writer"))


## A column of a line: as the writer of the current locale has filled it in,
## if `translated` and they have; as the English table has it otherwise.
func _field(id: String, field: String, translated: bool = true) -> String:
	if not has_line(id):
		push_error("Lines: unknown line id '%s'" % id)
		return "[%s]" % id
	if translated and locale != FALLBACK_LOCALE and _data.has_line(id, locale):
		var localized: String = GameData.as_string(_data.line(id, locale).get(field))
		if not localized.strip_edges().is_empty():
			return localized
	return GameData.as_string(_data.line(id, FALLBACK_LOCALE).get(field))
