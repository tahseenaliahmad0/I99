extends SceneTree
## The sound check (GDD 16.5): every sound of data/sfx.json is made and
## measured, the mix is weighed, and the Audio autoload is taken through the
## states of a drive (tools/audio_drive_check.gd).
##
##   godot --headless --path . --script res://tools/audio_check.gd [-- --wav=<folder>]
##
## One line for each sound: its length, its peak, its RMS level, how loud its
## loudest moment is. `--wav=` also writes every buffer as a .wav file into a
## folder, to be listened to. The exit code is 1 when
##   - a buffer is empty, silent, clipped or longer than MAX_SECONDS, is not
##     as long as its entry says, or would click (a loop's seam, a sound cut
##     off at its end);
##   - an event of GDD 16.5's table has no sound, or its entry does not hold
##     the numbers the table gives;
##   - a functional cue would not be heard over everything else at once;
##   - a sound the simulation asks for, or a state of the drive, is not heard.

## "Longer than a few seconds": no placeholder is.
const MAX_SECONDS: float = 3.0
## A buffer whose loudest sample is under this is silent (dB below full scale).
const SILENT_DB: float = -30.0
## Loudness is taken over this long, s: a sound shorter than that is spread
## over it, as the ear does.
const LOUD_WINDOW: float = 0.05
## How far a functional cue must stand above everything else at once, dB.
const CLEAR_DB: float = 6.0
## A loop's jump from its last sample to its first, against the largest step
## inside it: above this it is a seam.
const SEAM_RATIO: float = 1.5
## Where a sound that ends may still be at its last sample, as a share of its peak.
const END_SHARE: float = 0.05
const WAV_OPTION: String = "--wav="
## The checks that need the autoloads: a script of its own, loaded once they
## are there (a script started with --script is compiled before them).
const DRIVE_CHECK: String = "res://tools/audio_drive_check.gd"
## squeal_1, squeal_2 ...
const SQUEAL: String = "squeal_%d"
## The horn of another (the Audio autoload's name for it: this half of the
## check is compiled before the autoloads are there).
const HORN_BEHIND: String = "horn_behind"
## Sounds of which only one is heard at a time: the radio's loops, the squeals.
const FAMILIES: PackedStringArray = ["radio_", "squeal_"]
## The events of GDD 16.5's table.
const TABLE_IDS: PackedStringArray = [
	"engine", "rumble_strip", "indicator_tick", "lighter_click", "bead_click", "horn", "wiper",
	"grind", "scrape", "crash", "squeal_1", "squeal_2", "squeal_3", "squeal_4", "squeal_5",
	"squeal_6", "squeal_7", "squeal_8", "heartbeat", "yawn", "yawn_long", "phantom_hum",
	"siren_chirp", "phone_ring", "radio_music", "radio_news", "radio_callin", "radio_static",
	"clap", "ululation", "heckle",
]
## "The rumble strip, the indicator tick and both yawns are functional cues."
const FUNCTIONAL_IDS: PackedStringArray = ["rumble_strip", "indicator_tick", "yawn", "yawn_long"]
## The numbers the table gives: [id, key, value].
const TABLE_NUMBERS: Array = [
	["engine", "wave", "saw"], ["engine", "speed_kmh", [40.0, 160.0]], ["engine", "speed_hz", [60.0, 180.0]],
	["rumble_strip", "wave", "noise"], ["rumble_strip", "burst_hz", 30.0],
	["horn", "wave", "square"], ["horn", "freqs", [400.0, 500.0]],
	["scrape", "wave", "noise"], ["scrape", "duration", 0.3],
	["crash", "wave", "noise"], ["crash", "duration", 0.8],
	["heartbeat", "per_minute", [60.0, 120.0]],
	["yawn", "wave", "sine"], ["yawn", "freq", 400.0], ["yawn", "freq_to", 200.0], ["yawn", "duration", 0.8],
	["yawn_long", "wave", "sine"], ["yawn_long", "freq", 400.0], ["yawn_long", "freq_to", 200.0], ["yawn_long", "duration", 1.3],
	["phantom_hum", "wave", "sine"], ["phantom_hum", "freq", 55.0],
	["radio_static", "wave", "noise"], ["clap", "wave", "noise"],
]

var _data: GameData
var _failures: PackedStringArray = []
var _checks: int = 0
## id -> {"loud": dB, "gain": dB, "functional": bool, "duck": dB}.
var _levels: Dictionary = {}


func _initialize() -> void:
	# Autoloads enter the tree on the first frame; wait for them.
	await process_frame
	_data = GameData.load_from()
	var wav_dir: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(WAV_OPTION):
			wav_dir = arg.substr(WAV_OPTION.length())
		else:
			_fail("unknown option '%s'" % arg)

	_check_buffers(wav_dir)
	_check_generator()
	_check_table()
	_check_mix()
	var script: GDScript = load(DRIVE_CHECK) as GDScript
	if script == null or not script.can_instantiate():
		_fail("%s does not compile" % DRIVE_CHECK)
	else:
		var drive: RefCounted = script.new()
		var failures: PackedStringArray = drive.call("run", _data)
		_checks += GameData.as_int(drive.get("checks"))
		_failures.append_array(failures)

	for failure: String in _failures:
		print("AUDIO FAIL %s" % failure)
	print("audio check: %d sounds, %d checks, %d failure(s)" % [_data.root("sfx").size(), _checks, _failures.size()])
	quit(1 if not _failures.is_empty() else 0)


# --- The buffers -------------------------------------------------------------

func _check_buffers(wav_dir: String) -> void:
	if not wav_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(wav_dir)
	var registry: Dictionary = _data.root("sfx")
	print("%-16s %-4s %-4s %6s %7s %6s %8s %8s %8s %8s" % [
		"id", "kind", "bus", "rate", "seconds", "peak", "peak dB", "RMS dB", "loud dB", "gain dB"])
	var usec: int = 0
	var samples: int = 0
	for key: Variant in registry:
		var id: String = str(key)
		var spec: Dictionary = _synth(id)
		var looped: bool = GameData.as_bool(spec.get("loop"))
		var functional: bool = GameData.as_bool(spec.get("functional"))
		var problems: PackedStringArray = []
		var began: int = Time.get_ticks_usec()
		var stream: AudioStreamWAV = SfxSynth.build(spec, problems)
		usec += Time.get_ticks_usec() - began
		for problem: String in problems:
			_fail("%s: %s" % [id, problem])
		if stream == null:
			_fail("%s: no buffer was made" % id)
			continue
		var measured: Dictionary = _measure(stream)
		var count: int = measured["count"]
		var seconds: float = measured["seconds"]
		var peak: float = measured["peak"]
		var rms: float = measured["rms"]
		var loud: float = measured["loud"]
		var clipped: int = measured["clipped"]
		var seam: float = measured["seam"]
		var last: float = measured["last"]
		samples += count
		print("%-16s %-4s %-4s %6d %7.3f %6.3f %8.1f %8.1f %8.1f %8.1f" % [
			id, "loop" if looped else "shot", "Cues" if functional else "Bed", stream.mix_rate, seconds,
			peak, _db(peak), _db(rms), _db(loud), GameData.as_float(spec.get("gain_db"))])
		_levels[id] = {
			"loud": _db(loud), "gain": GameData.as_float(spec.get("gain_db")),
			"functional": functional, "duck": GameData.as_float(spec.get("duck_db")),
		}
		_expect(count > 0, "%s: the buffer is empty" % id)
		_expect(_db(peak) >= SILENT_DB, "%s: the buffer is silent (its peak is %.1f dB)" % [id, _db(peak)])
		_expect(clipped == 0, "%s: the buffer is clipped (%d samples at full scale)" % [id, clipped])
		_expect(seconds <= MAX_SECONDS, "%s: %.2f s is longer than %.1f s" % [id, seconds, MAX_SECONDS])
		_expect(absi(count - roundi(GameData.as_float(spec.get("duration")) * float(stream.mix_rate))) <= 1,
				"%s: the buffer is %.3f s, its entry says %s" % [id, seconds, str(spec.get("duration"))])
		_expect(absf(peak - GameData.as_float(spec.get("peak"))) <= 1.0 / SfxSynth.FULL_SCALE,
				"%s: the peak is %.4f, its entry says %s" % [id, peak, str(spec.get("peak"))])
		if looped:
			_expect(stream.loop_mode == AudioStreamWAV.LOOP_FORWARD and stream.loop_begin == 0 and stream.loop_end == count,
					"%s: the buffer does not loop from end to end" % id)
			_expect(seam <= SEAM_RATIO, "%s: the loop has a seam (a jump %.2f times the largest step inside it)" % [id, seam])
			_expect(_tail_is_head(stream), "%s: after the loop's end the engine must find its beginning again (%d samples)" % [id, SfxSynth.LOOP_TAIL])
		else:
			_expect(stream.loop_mode == AudioStreamWAV.LOOP_DISABLED, "%s: a sound that ends must not loop" % id)
			_expect(last <= END_SHARE * peak, "%s: the sound is cut off at its end (%.3f of %.3f)" % [id, last, peak])
		if not wav_dir.is_empty():
			var err: Error = stream.save_to_wav(wav_dir.path_join(id + ".wav"))
			if err != OK:
				_fail("%s: cannot write %s (%s)" % [id, wav_dir.path_join(id + ".wav"), error_string(err)])
	print("buffers: %d sounds, %.1f s of sound in %d samples, made in %.1f ms" % [
		registry.size(), _total_seconds(), samples, float(usec) / 1000.0])
	if not wav_dir.is_empty():
		print("buffers: written to %s" % wav_dir)


## The generator itself, on a sound of the check's own: a loop that is
## filtered must still be a loop. A steady tone through a filter that rings
## for longer than the loop lasts is the same in every one of its periods.
func _check_generator() -> void:
	var spec: Dictionary = {
		"wave": "saw", "freq": 100, "harmonics": 8, "filter": "lowpass", "cutoff": 150, "q": 6,
		"rate": 8000, "duration": 0.1, "peak": 0.9, "loop": true,
	}
	var problems: PackedStringArray = []
	var stream: AudioStreamWAV = SfxSynth.build(spec, problems)
	if not _expect(stream != null and problems.is_empty(), "generator: a filtered loop cannot be made (%s)" % "; ".join(problems)):
		return
	var bytes: PackedByteArray = stream.data
	var period: int = roundi(GameData.as_float(spec["rate"]) / GameData.as_float(spec["freq"]))
	var apart: int = 0
	for index: int in stream.loop_end - period:
		apart = maxi(apart, absi(bytes.decode_s16(index * 2) - bytes.decode_s16((index + period) * 2)))
	_expect(apart <= 2, "generator: a filtered loop is not the same on every turn (its periods are %d steps of 16 bits apart)" % apart)
	# The same entry, the same sound: noise is seeded.
	for id: String in ["crash", "rumble_strip"]:
		var first: AudioStreamWAV = SfxSynth.build(_synth(id), problems)
		var second: AudioStreamWAV = SfxSynth.build(_synth(id), problems)
		_expect(first != null and second != null and first.data == second.data, "generator: %s is not the same sound each time it is made" % id)


## What is in a buffer: how many samples, how long, its peak, its RMS level,
## the level of its loudest LOUD_WINDOW, how many samples sit at full scale,
## the jump at its seam against the largest step inside it, and where its
## last sample is. Levels are shares of full scale.
func _measure(stream: AudioStreamWAV) -> Dictionary:
	var bytes: PackedByteArray = stream.data
	# Of a loop, what is turned round: not the samples written after its end.
	var count: int = bytes.size() / 2
	if stream.loop_mode != AudioStreamWAV.LOOP_DISABLED:
		count = mini(count, stream.loop_end)
	var window: int = maxi(roundi(LOUD_WINDOW * float(stream.mix_rate)), 1)
	var squares: PackedFloat64Array = PackedFloat64Array()
	squares.resize(count)
	var peak: int = 0
	var clipped: int = 0
	var sum: float = 0.0
	var largest_step: int = 0
	var first: int = 0
	var previous: int = 0
	for index: int in count:
		var value: int = bytes.decode_s16(index * 2)
		peak = maxi(peak, absi(value))
		if absi(value) >= SfxSynth.FULL_SCALE_INT:
			clipped += 1
		var unit: float = float(value) / SfxSynth.FULL_SCALE
		squares[index] = unit * unit
		sum += unit * unit
		if index == 0:
			first = value
		else:
			largest_step = maxi(largest_step, absi(value - previous))
		previous = value
	var run: float = 0.0
	var loudest: float = 0.0
	for index: int in count:
		run += squares[index]
		if index >= window:
			run -= squares[index - window]
		loudest = maxf(loudest, run)
	return {
		"count": count,
		"seconds": float(count) / float(stream.mix_rate),
		"peak": float(peak) / SfxSynth.FULL_SCALE,
		"rms": sqrt(sum / float(maxi(count, 1))),
		"loud": sqrt(maxf(loudest, 0.0) / float(window)),
		"clipped": clipped,
		"seam": float(absi(first - previous)) / float(maxi(largest_step, 1)),
		"last": float(absi(previous)) / SfxSynth.FULL_SCALE,
	}


## True when the samples written after a loop's end are its first ones: the
## engine reads on past the end as the loop turns.
func _tail_is_head(stream: AudioStreamWAV) -> bool:
	var bytes: PackedByteArray = stream.data
	if bytes.size() != (stream.loop_end + SfxSynth.LOOP_TAIL) * 2:
		return false
	for index: int in SfxSynth.LOOP_TAIL:
		if bytes.decode_s16(index * 2) != bytes.decode_s16((stream.loop_end + index) * 2):
			return false
	return true


func _total_seconds() -> float:
	var total: float = 0.0
	for key: Variant in _data.root("sfx"):
		total += GameData.as_float(_synth(str(key)).get("duration"))
	return total


# --- The table of GDD 16.5 ---------------------------------------------------

func _check_table() -> void:
	var registry: Dictionary = _data.root("sfx")
	for id: String in TABLE_IDS:
		_expect(registry.has(id), "GDD 16.5 lists '%s' and sfx.json has no such sound" % id)
	for key: Variant in registry:
		var id: String = str(key)
		_expect(GameData.as_bool(_synth(id).get("functional")) == FUNCTIONAL_IDS.has(id),
				"%s: the functional cues are %s, no more and no fewer" % [id, ", ".join(FUNCTIONAL_IDS)])
	for row: Variant in TABLE_NUMBERS:
		var entry: Array = row
		var id: String = entry[0]
		var key: String = entry[1]
		_expect(_same(_synth(id).get(key), entry[2]), "%s: GDD 16.5 gives \"%s\" as %s, sfx.json has %s" % [
			id, key, str(entry[2]), str(_synth(id).get(key))])
	# "squeal_1 to squeal_8: rising tone per chain step."
	var below: float = 0.0
	var step: int = 1
	while registry.has(SQUEAL % step):
		var freq: float = GameData.as_float(_synth(SQUEAL % step).get("freq"))
		_expect(freq > below, "%s: each step of a chain must be a higher tone than the one before" % (SQUEAL % step))
		below = freq
		step += 1
	# "Short clicks at different pitches."
	var clicks: Dictionary = {}
	for id: String in ["indicator_tick", "lighter_click", "bead_click"]:
		clicks[GameData.as_float(_synth(id).get("freq"))] = true
	_expect(clicks.size() == 3, "the three clicks must have three pitches")
	# "A four-note loop."
	_expect(GameData.as_array(_synth("radio_music").get("notes")).size() == 4, "radio_music: a four-note loop has four notes")
	# "Speech-like blips; a different blip rhythm."
	_expect(not _same(_shares("radio_news"), _shares("radio_callin")), "radio_callin: its rhythm must differ from the news")
	# Not of the table: the horn of what comes up behind him (GDD 10.3) is a
	# horn like his, and every note of it lower than any of his own, so that
	# he cannot take the one for the other.
	_expect(registry.has(HORN_BEHIND), "sfx.json has no '%s' for what comes up behind his standing car" % HORN_BEHIND)
	_expect(_same(_synth(HORN_BEHIND).get("wave"), _synth("horn").get("wave")), "%s: a horn has the wave of his own" % HORN_BEHIND)
	var own_lowest: float = INF
	for note: Variant in GameData.as_array(_synth("horn").get("freqs")):
		own_lowest = minf(own_lowest, GameData.as_float(note))
	var behind: Array = GameData.as_array(_synth(HORN_BEHIND).get("freqs"))
	_expect(not behind.is_empty(), "%s: a horn has its notes in \"freqs\"" % HORN_BEHIND)
	for note: Variant in behind:
		_expect(GameData.as_float(note) < own_lowest, "%s: its note of %s Hz is not lower than his own horn's %s" % [HORN_BEHIND, str(note), str(own_lowest)])


## The rhythm of a row of notes: sounding or resting, and for what share.
func _shares(id: String) -> Array:
	var out: Array = []
	for entry: Variant in GameData.as_array(_synth(id).get("notes")):
		var note: Array = GameData.as_array(entry)
		if note.size() == 2:
			out.append([GameData.as_float(note[0]) > 0.0, GameData.as_float(note[1])])
	return out


## True when two values of an entry are the same: numbers as numbers, rows
## entry by entry.
func _same(a: Variant, b: Variant) -> bool:
	if GameData.is_number(a) and GameData.is_number(b):
		return is_equal_approx(GameData.as_float(a), GameData.as_float(b))
	if a is Array and b is Array:
		var left: Array = a
		var right: Array = b
		if left.size() != right.size():
			return false
		for index: int in left.size():
			if not _same(left[index], right[index]):
				return false
		return true
	return typeof(a) == typeof(b) and a == b


# --- The mix -----------------------------------------------------------------

## "The functional cues must be audible over everything else": each of them,
## at its loudest, against every other sound at once at its loudest, turned
## down as that cue turns it down. Of the radio's loops and of the squeals
## only one sounds at a time: the loudest counts.
func _check_mix() -> void:
	var families: Dictionary = {}
	for key: Variant in _levels:
		var id: String = str(key)
		var level: Dictionary = _levels[key]
		if GameData.as_bool(level.get("functional")):
			continue
		var family: String = id
		for prefix: String in FAMILIES:
			if id.begins_with(prefix):
				family = prefix
		var heard: float = GameData.as_float(level.get("loud")) + GameData.as_float(level.get("gain"))
		families[family] = maxf(GameData.as_float(families.get(family), -INF), heard)
	var power: float = 0.0
	for family: Variant in families:
		power += db_to_linear(GameData.as_float(families[family])) ** 2.0
	var rest: float = _db(sqrt(power))
	print("mix: everything but the functional cues, all at once, is %.1f dB" % rest)
	for key: Variant in _levels:
		var level: Dictionary = _levels[key]
		if not GameData.as_bool(level.get("functional")):
			continue
		var heard: float = GameData.as_float(level.get("loud")) + GameData.as_float(level.get("gain"))
		var duck: float = GameData.as_float(level.get("duck"))
		var clear: float = heard - (rest + duck)
		print("mix: %-14s is %6.1f dB, turns the rest down by %4.1f dB and stands %5.1f dB clear of it" % [
			str(key), heard, -duck, clear])
		_expect(clear >= CLEAR_DB, "%s: it stands %.1f dB clear of everything else at once; %.1f dB is asked" % [
			str(key), clear, CLEAR_DB])


# --- Helpers -----------------------------------------------------------------

func _synth(id: String) -> Dictionary:
	return GameData.as_dict(GameData.as_dict(_data.root("sfx").get(id)).get("synth"))


func _db(linear: float) -> float:
	return linear_to_db(maxf(linear, 1.0e-9))


func _expect(condition: bool, failure: String) -> bool:
	_checks += 1
	if not condition:
		_failures.append(failure)
	return condition


func _fail(failure: String) -> void:
	_checks += 1
	_failures.append(failure)
