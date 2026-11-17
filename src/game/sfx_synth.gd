class_name SfxSynth
extends RefCounted
## Makes the placeholder sounds (GDD 16.5): one "synth" entry of
## data/sfx.json in, one AudioStreamWAV out, 16 bits, one channel.
##
## Every number of a sound is in its entry. A sound is a source, put through
## a filter if it names one, then shaped in loudness:
##
##   wave        "sine", "saw", "square" or "noise"
##   rate        samples a second
##   duration    seconds
##   peak        the loudest sample of the finished buffer, 0 to 1
##   loop        true: the buffer is made to repeat without a seam
##
## Pitch, for every wave but noise. One of:
##   freq         Hz. With freq_to it glides to that pitch by the end; with
##                trill {"hz", "ratio"} it swings up to freq x ratio and
##                back, hz times a second.
##   freqs        [Hz, ...]: voices that sound together.
##   notes        [[Hz, share], ...]: one after the other, each for its share
##                of the duration; 0 Hz is a rest. With repeat the row is
##                played that many times.
## Timbre:
##   partials     sine only: how strong harmonics 1, 2, 3 ... are.
##   harmonics    saw and square: how many harmonics are kept (the wave is
##                built from them, so nothing folds back below `rate` / 2).
## Noise:
##   seed         the same noise at every boot.
## Filter:
##   filter       "lowpass", "bandpass" or "highpass"
##   cutoff       Hz; with cutoff_to the filter sweeps there by the end
##   q            resonance; 0.7 is flat
## Loudness over time:
##   attack, release      s: straight ramps at the two ends
##   decay                s: the sound dies away by 1/e in each `decay`
##   note_attack, note_release, note_decay     the same, for each note
##   burst_hz, burst_decay                     bursts a second, each dying away
##
## A loop holds a whole number of periods and bursts, and has no glide, sweep
## or ends to ramp: anything else would be heard as a click every turn. Its
## filter is run in before the first sample, and its first samples are written
## again after the last, where the engine reads on as the loop turns.
## What an entry says besides this (how loud it is played, when, how often)
## is read by the Audio autoload.

const SINE: String = "sine"
const SAW: String = "saw"
const SQUARE: String = "square"
const NOISE: String = "noise"
const WAVES: PackedStringArray = [SINE, SAW, SQUARE, NOISE]
const LOWPASS: int = 0
const BANDPASS: int = 1
const HIGHPASS: int = 2
## In the order of the three constants above.
const FILTERS: PackedStringArray = ["lowpass", "bandpass", "highpass"]
## Everything an entry may say about how its sound is made.
const KEYS: PackedStringArray = [
	"wave", "rate", "duration", "peak", "loop",
	"freq", "freq_to", "trill", "freqs", "notes", "repeat",
	"partials", "harmonics", "seed",
	"filter", "cutoff", "cutoff_to", "q",
	"attack", "release", "decay", "note_attack", "note_release", "note_decay",
	"burst_hz", "burst_decay",
]
## Samples in one period of a wave table.
const TABLE_SIZE: int = 2048
## The largest 16-bit sample.
const FULL_SCALE_INT: int = 32767
const FULL_SCALE: float = float(FULL_SCALE_INT)
## What a loop cannot have: each would be heard as a click or a jump every turn.
const LOOP_BREAKERS: PackedStringArray = ["attack", "release", "decay", "freq_to", "cutoff_to", "trill"]
## The three ways of saying a pitch; what goes with notes only; what goes
## with "freq" only.
const PITCH_KEYS: PackedStringArray = ["freq", "freqs", "notes"]
const NOTE_KEYS: PackedStringArray = ["repeat", "note_attack", "note_release", "note_decay"]
const GLIDE_KEYS: PackedStringArray = ["freq_to", "trill"]
## Samples of a loop's beginning that are written again after its end.
const LOOP_TAIL: int = 8
## How far from a whole number of periods a loop may be before it is refused.
const WHOLE_EPSILON: float = 0.001
## A filter has stopped ringing after this many periods of its cutoff, times
## its q (it is down by e to the minus pi times this).
const RING_PERIODS: float = 8.0


## The sound of one entry. What is wrong with the entry is added to
## `problems`; the stream is then null.
static func build(spec: Dictionary, problems: PackedStringArray) -> AudioStreamWAV:
	var before: int = problems.size()
	var wave: String = GameData.as_string(spec.get("wave"))
	if not WAVES.has(wave):
		problems.append("\"wave\" must be one of %s" % ", ".join(WAVES))
	var rate: float = _need(spec, "rate", problems)
	var duration: float = _need(spec, "duration", problems)
	var peak: float = _need(spec, "peak", problems)
	if peak >= 1.0:
		problems.append("\"peak\" must be under 1: a sample at full scale is a clipped one")
	var loop: bool = GameData.as_bool(spec.get("loop"))
	if loop:
		for key: String in LOOP_BREAKERS:
			if spec.has(key):
				problems.append("a loop cannot have \"%s\": it would be heard every turn" % key)
	for key: String in _idle_keys(spec, wave):
		problems.append("\"%s\" says nothing about a sound like this one" % key)
	var pitches: int = 0
	for key: String in PITCH_KEYS:
		if spec.has(key):
			pitches += 1
	if pitches > 1:
		problems.append("the pitch is said more than once: %s are three ways of saying it" % ", ".join(PITCH_KEYS))
	if problems.size() > before:
		return null
	var count: int = roundi(duration * rate)
	if count < 1:
		problems.append("\"duration\" is shorter than one sample")
		return null
	var samples: PackedFloat32Array = PackedFloat32Array()
	samples.resize(count)
	samples.fill(0.0)
	if wave == NOISE:
		_fill_noise(samples, spec, problems)
	else:
		_fill_tone(samples, wave, spec, rate, loop, problems)
	_filter(samples, spec, rate, loop, problems)
	_shape(samples, spec, rate, loop, problems)
	if problems.size() > before:
		return null
	var loudest: float = 0.0
	for index: int in count:
		loudest = maxf(loudest, absf(samples[index]))
	if loudest <= 0.0:
		problems.append("the sound is silent")
		return null
	return to_stream(samples, peak / loudest, roundi(rate), loop)


## Samples, each times `scale`, as a stream the engine can play. A loop is
## followed by its own first samples: the engine reads on past the end of a
## loop as it turns, and must find there what the turn begins with.
static func to_stream(samples: PackedFloat32Array, scale: float, rate: int, loop: bool) -> AudioStreamWAV:
	var count: int = samples.size()
	var written: int = count + (LOOP_TAIL if loop else 0)
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(written * 2)
	var to_sample: float = scale * FULL_SCALE
	for index: int in written:
		bytes.encode_s16(index * 2, clampi(roundi(samples[index % count] * to_sample), -FULL_SCALE_INT, FULL_SCALE_INT))
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = bytes
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = count
	return stream


## The keys of an entry that have no meaning for the sound it describes: a
## pitch for noise, a seed for a tone, a note's shape where there are no
## notes ... Each is a mistake in the entry, not something to pass over.
static func _idle_keys(spec: Dictionary, wave: String) -> PackedStringArray:
	var idle: PackedStringArray = []
	if wave == NOISE:
		idle.append_array(PITCH_KEYS)
		idle.append_array(NOTE_KEYS)
		idle.append_array(GLIDE_KEYS)
		idle.append_array(["partials", "harmonics"])
	else:
		idle.append("seed")
		idle.append("harmonics" if wave == SINE else "partials")
		if not spec.has("notes"):
			idle.append_array(NOTE_KEYS)
		if not spec.has("freq"):
			idle.append_array(GLIDE_KEYS)
	if not spec.has("filter"):
		idle.append_array(["cutoff", "cutoff_to", "q"])
	var found: PackedStringArray = []
	for key: String in idle:
		if spec.has(key) and not found.has(key):
			found.append(key)
	return found


## Makes a sound file loop from its first sample to its last. Plain samples
## (8 or 16 bits) get the loop's beginning written again after its end, as
## the generated loops have it. A compressed file cannot be given one: it
## loops as the engine's own importer would loop it, a sample short of its
## end, and may tick faintly as it turns (import loops uncompressed).
static func loop_whole(stream: AudioStreamWAV) -> void:
	var frame_bytes: int = (2 if stream.stereo else 1) * (2 if stream.format == AudioStreamWAV.FORMAT_16_BITS else 1)
	var plain: bool = stream.format == AudioStreamWAV.FORMAT_16_BITS or stream.format == AudioStreamWAV.FORMAT_8_BITS
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	if plain and stream.data.size() >= LOOP_TAIL * frame_bytes:
		var bytes: PackedByteArray = stream.data
		stream.loop_end = bytes.size() / frame_bytes
		bytes.append_array(bytes.slice(0, LOOP_TAIL * frame_bytes))
		stream.data = bytes
	else:
		stream.loop_end = roundi(stream.get_length() * float(stream.mix_rate)) - 1


# --- The source --------------------------------------------------------------

static func _fill_noise(out: PackedFloat32Array, spec: Dictionary, problems: PackedStringArray) -> void:
	if not GameData.is_number(spec.get("seed")):
		problems.append("noise needs a \"seed\"")
		return
	# Seeded here and nowhere else: the same sound at every boot.
	var generator: RandomNumberGenerator = RandomNumberGenerator.new()
	generator.seed = GameData.as_int(spec.get("seed"))
	for index: int in out.size():
		out[index] = generator.randf() * 2.0 - 1.0


static func _fill_tone(out: PackedFloat32Array, wave: String, spec: Dictionary, rate: float,
		loop: bool, problems: PackedStringArray) -> void:
	var count: int = out.size()
	var seconds: float = float(count) / rate
	var strengths: PackedFloat32Array = _strengths(wave, spec, problems)
	if strengths.is_empty():
		return
	var table: PackedFloat32Array = _table(strengths)
	# The highest pitch the wave may be played at before its top harmonic folds back.
	var ceiling: float = rate * 0.5 / float(strengths.size())
	var per_hz: float = float(TABLE_SIZE) / rate

	if spec.has("notes"):
		var notes: Array = GameData.as_array(spec.get("notes"))
		var repeat: int = maxi(GameData.as_int(spec.get("repeat"), 1), 1)
		var total: float = 0.0
		for entry: Variant in notes:
			var note: Array = GameData.as_array(entry)
			if note.size() != 2 or not GameData.is_number(note[0]) or not GameData.is_number(note[1]) \
					or GameData.as_float(note[0]) < 0.0 or GameData.as_float(note[1]) <= 0.0:
				problems.append("\"notes\" must be a row of [Hz, share], Hz 0 or more and share above 0")
				return
			if GameData.as_float(note[0]) > ceiling:
				problems.append("a note of %s Hz folds back: its top harmonic is over half the rate" % str(note[0]))
				return
			total += GameData.as_float(note[1])
		if total <= 0.0:
			problems.append("\"notes\" is empty")
			return
		total *= float(repeat)
		var attack: float = _may(spec, "note_attack", problems)
		var release: float = _may(spec, "note_release", problems)
		var decay: float = _may(spec, "note_decay", problems)
		var at: float = 0.0
		for turn: int in repeat:
			for entry: Variant in notes:
				var note: Array = GameData.as_array(entry)
				var hz: float = GameData.as_float(note[0])
				var from: int = roundi(at / total * float(count))
				at += GameData.as_float(note[1])
				var to: int = mini(roundi(at / total * float(count)), count)
				if hz > 0.0 and to > from:
					_tone(out, from, to, table, hz * per_hz, 1.0, 0.0, 0.0)
					_ramp(out, from, to, attack, release, decay, rate)
		return

	if spec.has("freqs"):
		var voices: Array = GameData.as_array(spec.get("freqs"))
		if voices.is_empty():
			problems.append("\"freqs\" is empty")
		for value: Variant in voices:
			if not GameData.is_number(value) or GameData.as_float(value) <= 0.0:
				problems.append("\"freqs\" must be a row of pitches in Hz")
				return
			var voice_hz: float = GameData.as_float(value)
			if not _fits(voice_hz, "freqs", ceiling, seconds, loop, problems):
				return
			_tone(out, 0, count, table, voice_hz * per_hz, 1.0, 0.0, 0.0)
		return

	var freq: float = _need(spec, "freq", problems)
	var freq_to: float = _need(spec, "freq_to", problems) if spec.has("freq_to") else freq
	var trill_hz: float = 0.0
	var trill_ratio: float = 1.0
	if spec.has("trill"):
		var trill: Dictionary = GameData.as_dict(spec.get("trill"))
		trill_hz = _need(trill, "hz", problems)
		trill_ratio = _need(trill, "ratio", problems)
	if freq <= 0.0 or freq_to <= 0.0 or trill_ratio <= 0.0:
		return
	if not _fits(maxf(freq, freq_to) * maxf(trill_ratio, 1.0), "freq", ceiling, seconds, loop, problems):
		return
	_tone(out, 0, count, table, freq * per_hz, pow(freq_to / freq, 1.0 / float(count)),
			TAU * trill_hz / rate, trill_ratio - 1.0)


## How strong each harmonic of a wave is, the first one first.
static func _strengths(wave: String, spec: Dictionary, problems: PackedStringArray) -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	if wave == SINE:
		if not spec.has("partials"):
			out.append(1.0)
			return out
		for value: Variant in GameData.as_array(spec.get("partials")):
			if not GameData.is_number(value) or GameData.as_float(value) < 0.0:
				problems.append("\"partials\" must be a row of strengths, 0 or more")
				return PackedFloat32Array()
			out.append(GameData.as_float(value))
		if out.is_empty() or out[out.size() - 1] <= 0.0:
			problems.append("\"partials\" must end with a harmonic that sounds")
			return PackedFloat32Array()
		return out
	var harmonics: int = roundi(_need(spec, "harmonics", problems))
	for harmonic: int in range(1, harmonics + 1):
		# A saw has every harmonic, a square the odd ones, each at 1/n.
		out.append(1.0 / float(harmonic) if wave == SAW or harmonic % 2 == 1 else 0.0)
	return out


## One period of a wave, and its first sample again at the end so that two
## neighbours can always be read.
static func _table(strengths: PackedFloat32Array) -> PackedFloat32Array:
	var table: PackedFloat32Array = PackedFloat32Array()
	table.resize(TABLE_SIZE + 1)
	table.fill(0.0)
	for harmonic: int in strengths.size():
		var strength: float = strengths[harmonic]
		if strength <= 0.0:
			continue
		var step: float = TAU * float(harmonic + 1) / float(TABLE_SIZE)
		for index: int in TABLE_SIZE + 1:
			table[index] += strength * sin(step * float(index))
	return table


## True when a pitch can be made: its top harmonic is under half the rate,
## and in a loop it turns a whole number of times.
static func _fits(hz: float, key: String, ceiling: float, seconds: float, loop: bool,
		problems: PackedStringArray) -> bool:
	if hz > ceiling:
		problems.append("\"%s\" of %s Hz folds back: its top harmonic is over half the rate" % [key, str(hz)])
		return false
	return _whole(hz, key, seconds, loop, problems)


## True unless this is a loop that would not hold a whole number of them.
static func _whole(per_second: float, key: String, seconds: float, loop: bool,
		problems: PackedStringArray) -> bool:
	if not loop:
		return true
	var turns: float = per_second * seconds
	if turns < 1.0 - WHOLE_EPSILON or absf(turns - roundf(turns)) > WHOLE_EPSILON:
		problems.append("a loop must hold a whole number of periods: \"%s\" of %s in %s s is %s" % [
			key, str(per_second), str(seconds), str(turns)])
		return false
	return true


## Adds a tone to out[from, to): the table read at `step` samples of it per
## sample, the step growing by `glide` each sample. A trill swings the step
## up by `trill_span` of itself and back, `trill_step` radians a sample.
static func _tone(out: PackedFloat32Array, from: int, to: int, table: PackedFloat32Array,
		step: float, glide: float, trill_step: float, trill_span: float) -> void:
	var size: float = float(TABLE_SIZE)
	var phase: float = 0.0
	var swing: float = 0.0
	var trilling: bool = trill_step > 0.0
	for index: int in range(from, to):
		var whole: int = int(phase)
		var part: float = phase - float(whole)
		out[index] += table[whole] + (table[whole + 1] - table[whole]) * part
		if trilling:
			phase += step * (1.0 + trill_span * (0.5 - 0.5 * cos(swing)))
			swing += trill_step
		else:
			phase += step
		if phase >= size:
			phase -= size
		step *= glide


# --- The filter --------------------------------------------------------------

## A state-variable filter (the trapezoidal one: it stays stable up to half
## the rate, swept or not).
static func _filter(out: PackedFloat32Array, spec: Dictionary, rate: float, loop: bool,
		problems: PackedStringArray) -> void:
	if not spec.has("filter"):
		return
	var kind: int = FILTERS.find(GameData.as_string(spec.get("filter")))
	if kind == -1:
		problems.append("\"filter\" must be one of %s" % ", ".join(FILTERS))
	var cutoff: float = _need(spec, "cutoff", problems)
	var cutoff_to: float = _need(spec, "cutoff_to", problems) if spec.has("cutoff_to") else cutoff
	var q: float = _need(spec, "q", problems)
	if kind == -1 or cutoff <= 0.0 or cutoff_to <= 0.0 or q <= 0.0:
		return
	if maxf(cutoff, cutoff_to) >= rate * 0.5:
		problems.append("the filter's cutoff must be under half the rate")
		return
	var count: int = out.size()
	var damping: float = 1.0 / q
	var sweeping: bool = cutoff_to != cutoff
	var sweep: float = pow(cutoff_to / cutoff, 1.0 / float(count))
	var hz: float = cutoff
	var g: float = tan(PI * hz / rate)
	var a1: float = 1.0 / (1.0 + g * (g + damping))
	var a2: float = g * a1
	var a3: float = g * a2
	var first: float = 0.0
	var second: float = 0.0
	if loop:
		# The end of a loop runs into its start. The filter is first run up to
		# the end of the buffer, round and round for as long as it rings, so
		# that it begins the buffer as it will begin it on every turn.
		var warm: int = ceili(RING_PERIODS * q * rate / cutoff)
		var index: int = posmod(-warm, count)
		for step: int in warm:
			var v3: float = out[index] - second
			var v1: float = a1 * first + a2 * v3
			var v2: float = second + a2 * first + a3 * v3
			first = 2.0 * v1 - first
			second = 2.0 * v2 - second
			index += 1
			if index == count:
				index = 0
	for index: int in count:
		if sweeping:
			g = tan(PI * hz / rate)
			a1 = 1.0 / (1.0 + g * (g + damping))
			a2 = g * a1
			a3 = g * a2
			hz *= sweep
		var x: float = out[index]
		var v3: float = x - second
		var v1: float = a1 * first + a2 * v3
		var v2: float = second + a2 * first + a3 * v3
		first = 2.0 * v1 - first
		second = 2.0 * v2 - second
		if kind == LOWPASS:
			out[index] = v2
		elif kind == BANDPASS:
			out[index] = v1
		else:
			out[index] = x - damping * v1 - v2


# --- Loudness over time ------------------------------------------------------

static func _shape(out: PackedFloat32Array, spec: Dictionary, rate: float, loop: bool,
		problems: PackedStringArray) -> void:
	var count: int = out.size()
	if spec.has("burst_hz") or spec.has("burst_decay"):
		var bursts: float = _need(spec, "burst_hz", problems)
		var burst_decay: float = _need(spec, "burst_decay", problems)
		if bursts <= 0.0 or burst_decay <= 0.0:
			return
		if not _whole(bursts, "burst_hz", float(count) / rate, loop, problems):
			return
		var period: float = rate / bursts
		var fade: float = exp(-1.0 / (burst_decay * rate))
		var level: float = 1.0
		var next: float = period
		for index: int in count:
			if float(index) >= next:
				level = 1.0
				next += period
			out[index] *= level
			level *= fade
	_ramp(out, 0, count, _may(spec, "attack", problems), _may(spec, "release", problems),
			_may(spec, "decay", problems), rate)


## Shapes out[from, to): dying away by 1/e each `decay` seconds, rising in a
## straight line over `attack` and falling to nothing over `release`.
static func _ramp(out: PackedFloat32Array, from: int, to: int, attack: float, release: float,
		decay: float, rate: float) -> void:
	var length: int = to - from
	if decay > 0.0:
		var fade: float = exp(-1.0 / (decay * rate))
		var level: float = 1.0
		for index: int in range(from, to):
			out[index] *= level
			level *= fade
	var rise: int = mini(roundi(attack * rate), length)
	for index: int in rise:
		out[from + index] *= float(index) / float(rise)
	var fall: int = mini(roundi(release * rate), length)
	for index: int in fall:
		out[to - 1 - index] *= float(index) / float(fall)


# --- Reading an entry --------------------------------------------------------

## A number the entry must hold, above zero. 0.0 when it does not.
static func _need(spec: Dictionary, key: String, problems: PackedStringArray) -> float:
	var value: Variant = spec.get(key)
	if not GameData.is_number(value) or GameData.as_float(value) <= 0.0:
		problems.append("\"%s\" must be a number above 0" % key)
		return 0.0
	return GameData.as_float(value)


## A number the entry may hold, zero or more. 0.0 when it is not there.
static func _may(spec: Dictionary, key: String, problems: PackedStringArray) -> float:
	if not spec.has(key):
		return 0.0
	var value: Variant = spec.get(key)
	if not GameData.is_number(value) or GameData.as_float(value) < 0.0:
		problems.append("\"%s\" must be a number, 0 or more" % key)
		return 0.0
	return GameData.as_float(value)
