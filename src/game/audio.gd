extends Node
## Plays the placeholder sounds by event id (GDD 16.5).
##
## Every sound is an entry of data/sfx.json. At boot each entry's "synth" is
## made into an AudioStreamWAV by SfxSynth, or its "stream" file is loaded
## in its place (GDD 14), and the sound gets a player of its own. Three
## things are heard:
##
##   - `play(id)`, and so every `sfx_requested` on the Events bus (a horn
##     asked for with `behind` is not his own: it is `horn_behind`);
##   - the bus events that have a sound of their own: a hit (scrape, crash),
##     a close call (the chain's rising squeal), a heckle (the ding);
##   - `apply(snapshot)`, once a frame from the drive scene: the engine, the
##     rumble strip, the heartbeat, the radio, the siren, the ringing phone
##     (the one on its mount, and the one in his pocket at Dawn), the
##     indicator's tick, the Phantom's hum, the horn of a Snap, the horn of
##     what comes up behind his standing car, the Rattle, a gust's tell
##     and the Storm's thick dust.
##
## What an entry says about how its sound is played, beside how it is made:
##
##   gain_db              how loud it is played, dB
##   loop                 true: it goes round for as long as it is asked for
##   fade_in, fade_out    a loop: seconds it takes to come in and to go out
##   hold                 a loop that can be asked for by id: seconds it
##                        then sounds (a honk)
##   functional           true: a functional cue (GDD 16.5). It plays on a
##                        bus of its own, and while it sounds everything
##                        else is turned down by duck_db, within duck_attack
##                        seconds, and comes back within duck_release.
##   every, per_minute, speed_kmh, speed_hz, idle_hz, per_gear, warble
##                        when and at what pitch the sounds of `apply` are
##                        heard; each is explained where it is read.
##
## A key on a sound it means nothing for (a hold on a sound that ends, what a
## cue does on a sound that is no cue, "every" on a sound that does not
## repeat) is an error at boot, like a key that nothing reads.
##
## This class reads the snapshot and changes nothing. Set the environment
## variable I99_AUDIO_LOG to have every sound that starts or ends printed.

## What an entry of sfx.json may say about how its sound is played (what it
## may say about how the sound is made is SfxSynth.KEYS).
const PLAY_KEYS: PackedStringArray = [
	"gain_db", "functional", "duck_db", "duck_attack", "duck_release",
	"fade_in", "fade_out", "hold", "every", "per_minute",
	"speed_kmh", "speed_hz", "idle_hz", "per_gear", "warble", "note",
]

const BUS_MASTER: StringName = &"Master"
## The functional cues, and everything else.
const BUS_CUES: StringName = &"Cues"
const BUS_BED: StringName = &"Bed"

const ENGINE: String = "engine"
const ENGINE_HARMONIC: String = "engine_harmonic"
## The Rattle fault (GDD 6.3): the one fault with nothing to show for itself.
const RATTLE: String = "rattle"
const RUMBLE: String = "rumble_strip"
## What a gust's streaks and the Storm's closing dust show (GDD 5.4, 10.3) is
## heard as well (GDD 17.2).
const GUST: String = "gust"
const DUST: String = "dust"
## The soldier of the Checkpoint (GDD 10.2), whom the simulation asks for:
## he whistles as he sets off toward the car and knocks with each sign.
const WHISTLE: String = "soldier_whistle"
const KNOCK: String = "soldier_knock"
const HEARTBEAT: String = "heartbeat"
const HORN: String = "horn"
## The horn of another: of what comes up behind his standing car (GDD 10.3).
const HORN_BEHIND: String = "horn_behind"
const HUM: String = "phantom_hum"
const SIREN: String = "siren_chirp"
const RING: String = "phone_ring"
const TICK: String = "indicator_tick"
const SCRAPE: String = "scrape"
const CRASH: String = "crash"
const HECKLE: String = "heckle"
## squeal_1, squeal_2 ...: one for each step of a close-call chain.
const SQUEAL: String = "squeal_%d"
## radio_music, radio_static ...: one for each station, and for static.
const RADIO: String = "radio_%s"
## The music station's loop, which a tape in the deck plays too.
const MUSIC: String = RADIO % String(ItemSim.MUSIC)
## What only a functional cue says, what only a loop says, and what apply()
## reads from the sounds named here and from no other.
const CUE_KEYS: PackedStringArray = ["duck_db", "duck_attack", "duck_release"]
const LOOP_KEYS: PackedStringArray = ["fade_in", "fade_out", "hold"]
const KEYS_OF: Dictionary = {
	"every": [TICK, RING, SIREN],
	"per_minute": [HEARTBEAT],
	"speed_kmh": [ENGINE],
	"speed_hz": [ENGINE],
	"idle_hz": [ENGINE],
	"per_gear": [ENGINE_HARMONIC],
	"warble": [MUSIC],
}
const TRACE_VARIABLE: String = "I99_AUDIO_LOG"
const SECONDS_PER_MINUTE: float = 60.0
## Frames without a snapshot after which the drive scene is taken to be gone.
const STALE_FRAMES: int = 1
## The most of the simulation's clock that one snapshot moves the sound on by,
## s: a clock that jumps is not caught up with.
const MAX_STEP: float = 0.25
## Steps of the engine's mixer by which it has let go of a stopped sound, and
## the longest that one such step is waited for, s.
const MIXER_STEPS_TO_STOP: int = 2
const MIXER_STEP_MAX: float = 0.25
const USEC_PER_SECOND: float = 1.0e6


## One sound: its player and how it is played.
class Voice:
	extends RefCounted
	var id: String = ""
	var player: AudioStreamPlayer
	var gain_db: float = 0.0
	var looped: bool = false
	## A functional cue, and what it does to everything else while it sounds.
	var functional: bool = false
	var duck_db: float = 0.0
	var duck_attack: float = 0.0
	var duck_release: float = 0.0
	## A loop: seconds to come in and to go out; seconds a request sounds.
	var fade_in: float = 0.0
	var fade_out: float = 0.0
	var hold: float = 0.0
	## A loop: the snapshot asks for it; seconds left of a request; how far
	## in it is, 0 to 1.
	var wanted: bool = false
	var held: float = 0.0
	var level: float = 0.0
	## How many times it has been started, and when it last was (in the
	## seconds the sound has moved on by; long ago if never).
	var starts: int = 0
	var started_at: float = -INF


## A sound that repeats while something lasts: the heartbeat, the ringing
## phone, the siren, the indicator.
class Pulse:
	extends RefCounted
	var voice: Voice
	var on: bool = false
	## Seconds from one to the next, and until the next.
	var every: float = 0.0
	var left: float = 0.0
	## Cut short when what it tells of is over (an answered phone).
	var cut: bool = false


## Milliseconds the last setup() took, the making of every buffer included.
var setup_msec: float = 0.0

var _data: GameData
## id -> Voice.
var _voices: Dictionary = {}
var _loops: Array[Voice] = []
var _cues: Array[Voice] = []
var _pulses: Array[Pulse] = []
## id -> its Pulse.
var _pulse_of: Dictionary = {}
var _trace: bool = false
## True once anything has sounded.
var _heard: bool = false

# --- What apply() drives -----------------------------------------------------
## True while snapshots come; frames since the last one; its clock, s.
var _live: bool = false
var _idle_frames: int = 0
var _clock: float = 0.0
## Seconds the sound has moved on by since setup().
var _elapsed: float = 0.0
var _engine: Voice
var _harmonic: Voice
var _rattle: Voice
var _gust: Voice
var _dust: Voice
var _rumble: Voice
var _horn: Voice
var _horn_behind: Voice
var _hum: Voice
var _beat: Pulse
var _ring: Pulse
var _siren: Pulse
var _tick: Pulse
## The engine: the pitch of its buffer, and its pitch by speed.
var _engine_hz: float = 1.0
var _harmonic_hz: float = 1.0
var _speed_from: float = 0.0
var _speed_to: float = 1.0
var _hz_from: float = 0.0
var _hz_to: float = 0.0
var _idle_hz: float = 0.0
## The harmonic the engine adds in each gear, neutral first; 0 is none.
var _per_gear: PackedFloat64Array = PackedFloat64Array()
## The heartbeat: beats a minute where Pound begins and at a Snap.
var _beats_slow: float = 0.0
var _beats_fast: float = 0.0
var _pound_from: float = 0.0
var _snap_at: float = 0.0
## The siren: seconds between chirps with no Suspicion and with all of it.
var _siren_calm: float = 0.0
var _siren_hot: float = 0.0
var _suspicion_max: float = 1.0
## station id (and "static") -> its Voice.
var _radio: Dictionary = {}
var _music: Voice
var _warbling: bool = false
var _warble_hz: float = 0.0
var _warble_depth: float = 0.0
var _warble_turn: float = 0.0
## The sound of each step of a close-call chain, the first first.
var _squeals: PackedStringArray = []

# --- The mix -----------------------------------------------------------------
## How far everything but the cues is turned down now, dB (0 or less).
var _duck: float = 0.0
## The cue that turned it down last: how deep, and how fast it comes back.
var _duck_depth: float = 0.0
var _duck_release: float = 0.0


func setup(data: GameData) -> void:
	var began: int = Time.get_ticks_usec()
	_data = data
	_trace = OS.has_environment(TRACE_VARIABLE)
	_clear()
	_make_buses()
	var registry: Dictionary = data.root("sfx")
	for key: Variant in registry:
		_make_voice(str(key), GameData.as_dict(registry[key]))
	_configure(data.tuning)
	if not Events.sfx_requested.is_connected(_on_sfx_requested):
		Events.sfx_requested.connect(_on_sfx_requested)
		Events.hit.connect(_on_hit)
		Events.close_call.connect(_on_close_call)
		Events.heckle_started.connect(_on_heckle_started)
	setup_msec = float(Time.get_ticks_usec() - began) / 1000.0


func has_sound(id: String) -> bool:
	return _data != null and _data.root("sfx").has(id)


## Plays a sound once. A loop sounds for its "hold".
func play(id: String) -> void:
	if not has_sound(id):
		push_error("Audio: unknown sfx id '%s'" % id)
		return
	var voice: Voice = _voices.get(id)
	if voice == null:
		# Its entry could not be made into a sound; setup() has said why.
		return
	if not voice.looped:
		_start(voice)
		var pulse: Pulse = _pulse_of.get(id)
		if pulse != null and pulse.on:
			# It has just sounded: the next of its kind is a whole gap away.
			pulse.left = pulse.every
	elif voice.hold > 0.0:
		voice.held = voice.hold
	else:
		push_error("Audio: '%s' is a loop the snapshot drives; it cannot be asked for by id" % id)


## Stops a sound at once.
func stop(id: String) -> void:
	var voice: Voice = _voices.get(id)
	if voice == null:
		return
	voice.player.stop()
	voice.wanted = false
	voice.held = 0.0
	voice.level = 0.0


## The state of the drive, once a frame: what should be sounding now. The
## sound moves on by the simulation's own clock, so what repeats (a heartbeat,
## a ring) keeps time with what it tells of.
## A Wreck stops the Telling where it stands (GDD 3.2): while the Table
## objects the snapshot stays what it was, and nothing that it says is going
## on is heard to go on. What had been asked for by itself plays out (the
## crash, a honk), and the radio plays over the cut.
func apply(snapshot: Dictionary) -> void:
	var time: float = snapshot["time"]
	var delta: float = clampf(time - _clock, 0.0, MAX_STEP) if _live else 0.0
	_clock = time
	_idle_frames = 0
	_live = true
	var wrecked: bool = snapshot["wrecked"]
	# The key turned in the bay (GDD 10.5): the engine is off. (A snapshot
	# that does not say runs.)
	var engine_on: bool = GameData.as_bool(snapshot.get("engine_on", true), true)
	var speed: float = snapshot["speed"]
	var gear: int = snapshot["gear"]
	var on_rumble: bool = snapshot["on_rumble"]
	var snapped: bool = snapshot["snap"]
	var cramp: String = snapshot["cramp"]
	var pound: bool = snapshot["pound"]
	var nerves: float = snapshot["nerves"]
	var caller: String = snapshot["caller"]
	var suspicion: float = snapshot["suspicion"]
	var watching: bool = snapshot["suspicion_watching"]
	var police_lights: bool = snapshot["police_lights"]
	var pulled_over: bool = snapshot["pulled_over"]
	var indicator: int = snapshot["indicator"]
	var rear_end_in: float = snapshot["rear_end_in"]
	var gust_tell: float = snapshot["gust_tell"]
	var dust_thick: bool = snapshot["dust_thick"]
	var dust_closing: float = snapshot["dust_closing"]

	# The engine (GDD 16.5): its pitch is the speed, its added harmonic the
	# gear. A wrecked engine is a dead one (GDD 6.3).
	if _engine != null and _harmonic != null:
		var hz: float = maxf(remap(speed, _speed_from, _speed_to, _hz_from, _hz_to), _idle_hz)
		var harmonic: float = _per_gear[gear] if gear >= 0 and gear < _per_gear.size() else 0.0
		_engine.wanted = not wrecked and engine_on
		_harmonic.wanted = not wrecked and engine_on and harmonic > 0.0
		_set_pitch(_engine, hz / _engine_hz)
		if harmonic > 0.0:
			_set_pitch(_harmonic, harmonic * hz / _harmonic_hz)

	# The Rattle (GDD 6.3) has nothing to show, so it is heard (GDD 16.3): for
	# as long as its lamp is lit and the engine runs.
	if _rattle != null:
		var faults: Array[StringName] = snapshot["faults"]
		_rattle.wanted = faults.has(DriveSim.FAULT_RATTLE) and not wrecked and engine_on

	# A gust is heard coming for as long as its streaks blow (GDD 5.4), and
	# the Storm's thick dust from when it begins to close in until it thins
	# (GDD 10.3): each tell is heard as well as seen (GDD 17.2).
	if _gust != null:
		_gust.wanted = gust_tell > 0.0 and not wrecked
	if _dust != null:
		_dust.wanted = (dust_thick or dust_closing > 0.0) and not wrecked

	# The rumble strip is heard while the car runs on it.
	if _rumble != null:
		_rumble.wanted = on_rumble and speed > 0.0 and not wrecked

	# A Snap: he leans on the horn for as long as it lasts (GDD 6.1).
	if _horn != null:
		_horn.wanted = snapped and not wrecked

	# What comes up behind his standing car in the Storm (GDD 10.3) leans on
	# its horn until it has hit him or missed him: no longer than it comes.
	if _horn_behind != null:
		_horn_behind.wanted = rear_end_in > 0.0 and not wrecked
		if not _horn_behind.wanted:
			_horn_behind.held = 0.0

	# The Phantom's hum before a cramp (GDD 7.9): no longer than the hum.
	if _hum != null:
		_hum.wanted = cramp == DriveSim.HUM and not wrecked
		if not _hum.wanted:
			_hum.held = 0.0

	_apply_radio(snapshot)

	# The heartbeat is the tell of Pound (GDD 5.8): slow where Pound begins,
	# fast at the edge of a Snap.
	if _beat != null:
		var span: float = _snap_at - _pound_from
		var share: float = clampf((nerves - _pound_from) / span, 0.0, 1.0) if span > 0.0 else 1.0
		_set_pulse(_beat, pound and not wrecked, SECONDS_PER_MINUTE / lerpf(_beats_slow, _beats_fast, share))

	# A phone rings for as long as somebody calls: until the call is answered
	# or lost. The snapshot names the caller of the phone on its mount and,
	# while the Call rings in his pocket at Dawn (GDD 10.4), Noor.
	if _ring != null:
		_set_pulse(_ring, not caller.is_empty() and not wrecked, _ring.every)

	# The siren chirps while the police are behind him, faster as Suspicion
	# grows (GDD 16.3); not while the officer stands at the window.
	if _siren != null:
		_set_pulse(_siren, (watching or police_lights) and not pulled_over and not wrecked,
				lerpf(_siren_calm, _siren_hot, clampf(suspicion / _suspicion_max, 0.0, 1.0)))

	# The indicator ticks for as long as it signals: that it has not yet
	# gone out is what he needs to hear.
	if _tick != null:
		_set_pulse(_tick, indicator != 0 and not wrecked, _tick.every)

	_step(delta)


func _process(delta: float) -> void:
	advance(delta)


## The end of the game. The engine lets go of a sound only at a step of its
## mixer after the sound was stopped, and it stops what still plays as it
## deletes the players, when the mixer no longer runs: every such sound is
## then reported as leaked when the process ends. So if anything has sounded,
## every player is stopped here and the mixer is given its steps.
func _exit_tree() -> void:
	if not _heard:
		return
	for key: Variant in _voices:
		var voice: Voice = _voices[key]
		voice.player.stop()
	for step: int in MIXER_STEPS_TO_STOP:
		OS.delay_usec(roundi(clampf(AudioServer.get_time_to_next_mix(), 0.0, MIXER_STEP_MAX) * USEC_PER_SECOND))


## A frame of the game. While a drive scene hands over its snapshots they
## move the sound on themselves (`apply`); this only notices when they have
## stopped coming, and from then on moves it on by the frame's own time.
func advance(delta: float) -> void:
	_idle_frames = mini(_idle_frames + 1, STALE_FRAMES + 1)
	if _live:
		if _idle_frames <= STALE_FRAMES:
			return
		_fall_silent()
	_step(delta)


## The sound moved on by `delta` seconds: loops come in and go out, what
## repeats is repeated, and everything else makes room for the functional
## cues.
func _step(delta: float) -> void:
	_elapsed += delta
	for voice: Voice in _loops:
		_step_loop(voice, delta)
	for pulse: Pulse in _pulses:
		if not pulse.on:
			continue
		pulse.left -= delta
		if pulse.left <= 0.0:
			_start(pulse.voice)
			pulse.left = maxf(pulse.left + pulse.every, 0.0)
	if _warbling and _music != null:
		# A tape past the end of its side (GDD 7.4): its pitch wavers.
		_warble_turn = fmod(_warble_turn + TAU * _warble_hz * delta, TAU)
		_set_pitch(_music, 1.0 + _warble_depth * sin(_warble_turn))
	_step_duck(delta)


# --- For the checks and the numeric HUD --------------------------------------

## Every sound that was made, in the order of sfx.json.
func ids() -> PackedStringArray:
	var out: PackedStringArray = []
	for key: Variant in _voices:
		out.append(str(key))
	return out


func stream_of(id: String) -> AudioStream:
	var voice: Voice = _voices.get(id)
	return voice.player.stream if voice != null else null


## True while the sound is heard: a loop that is in or on its way, a one-shot
## that has not ended.
func is_sounding(id: String) -> bool:
	var voice: Voice = _voices.get(id)
	return voice != null and _audible(voice)


## How many times the sound has been started since setup().
func starts_of(id: String) -> int:
	var voice: Voice = _voices.get(id)
	return voice.starts if voice != null else 0


func pitch_of(id: String) -> float:
	var voice: Voice = _voices.get(id)
	return voice.player.pitch_scale if voice != null else 0.0


## The volume of the sound's player now, dB.
func volume_of(id: String) -> float:
	var voice: Voice = _voices.get(id)
	return voice.player.volume_db if voice != null else -INF


## The bus the sound plays on.
func bus_of(id: String) -> StringName:
	var voice: Voice = _voices.get(id)
	return voice.player.bus if voice != null else &""


## How far everything but the functional cues is turned down now, dB.
func duck_db() -> float:
	return _duck


# --- Setting up --------------------------------------------------------------

func _clear() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.free()
	_voices.clear()
	_loops.clear()
	_cues.clear()
	_pulses.clear()
	_pulse_of.clear()
	_radio.clear()
	_squeals.clear()
	_engine = null
	_harmonic = null
	_rattle = null
	_gust = null
	_dust = null
	_rumble = null
	_horn = null
	_horn_behind = null
	_hum = null
	_music = null
	_beat = null
	_ring = null
	_siren = null
	_tick = null
	_live = false
	_warbling = false
	_duck = 0.0
	_elapsed = 0.0


## Two buses into Master: one for the functional cues, one for everything
## else, so that everything else can be turned down as one.
func _make_buses() -> void:
	for bus: StringName in [BUS_CUES, BUS_BED]:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus)
			AudioServer.set_bus_send(AudioServer.bus_count - 1, BUS_MASTER)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(BUS_BED), 0.0)


## The keys of an entry that say how a sound is played and mean nothing for
## the sound `id`: what a cue does to the rest on a sound that is no cue, a
## loop's fades and hold on a sound that ends, and what apply() reads from one
## sound on any other. Each is a mistake in the entry, as the keys that
## SfxSynth finds idle are: a number that would silently do nothing.
func idle_keys(id: String, spec: Dictionary) -> PackedStringArray:
	var idle: PackedStringArray = []
	if not GameData.as_bool(spec.get("functional")):
		idle.append_array(CUE_KEYS)
	if not GameData.as_bool(spec.get("loop")):
		idle.append_array(LOOP_KEYS)
	for key: Variant in KEYS_OF:
		if not GameData.as_array(KEYS_OF[key]).has(id):
			idle.append(str(key))
	var found: PackedStringArray = []
	for key: String in idle:
		if spec.has(key):
			found.append(key)
	return found


func _make_voice(id: String, entry: Dictionary) -> void:
	var spec: Dictionary = GameData.as_dict(entry.get("synth"))
	var problems: PackedStringArray = []
	for key: Variant in spec:
		if not SfxSynth.KEYS.has(str(key)) and not PLAY_KEYS.has(str(key)):
			problems.append("unknown key \"%s\"" % str(key))
	for key: String in idle_keys(id, spec):
		problems.append("\"%s\" says nothing about how a sound like this one is played" % key)
	var voice: Voice = Voice.new()
	voice.id = id
	voice.looped = GameData.as_bool(spec.get("loop"))
	voice.gain_db = _number(spec, "gain_db", problems)
	voice.functional = GameData.as_bool(spec.get("functional"))
	if voice.functional:
		voice.duck_db = minf(_number(spec, "duck_db", problems), 0.0)
		voice.duck_attack = maxf(_number(spec, "duck_attack", problems), 0.0)
		voice.duck_release = maxf(_number(spec, "duck_release", problems), 0.0)
	if voice.looped:
		voice.fade_in = maxf(_number(spec, "fade_in", problems), 0.0)
		voice.fade_out = maxf(_number(spec, "fade_out", problems), 0.0)
		if spec.has("hold"):
			voice.hold = maxf(_number(spec, "hold", problems), 0.0)

	# A file named by "stream" is played instead of the generated buffer (GDD 14).
	var stream: AudioStream = null
	var path: String = GameData.as_string(entry.get("stream"))
	if not path.is_empty():
		stream = _load_stream(path, voice.looped, problems)
	if stream == null:
		stream = SfxSynth.build(spec, problems)
	for problem: String in problems:
		push_error("Audio: sfx '%s': %s" % [id, problem])
	if stream == null:
		return

	voice.player = AudioStreamPlayer.new()
	voice.player.name = id
	voice.player.stream = stream
	voice.player.bus = BUS_CUES if voice.functional else BUS_BED
	voice.player.volume_db = voice.gain_db
	add_child(voice.player)
	_voices[id] = voice
	if voice.looped:
		_loops.append(voice)
	if voice.functional:
		_cues.append(voice)


func _load_stream(path: String, looped: bool, problems: PackedStringArray) -> AudioStream:
	var stream: AudioStream = null
	if ResourceLoader.exists(path):
		stream = load(path) as AudioStream
	elif path.get_extension().to_lower() == "wav" and FileAccess.file_exists(path):
		# A sound file the engine has not imported: read as it is.
		stream = AudioStreamWAV.load_from_file(path)
	if stream == null:
		problems.append("the stream '%s' cannot be loaded as a sound; the generated one is played" % path)
		return null
	# Whether it loops is the entry's word. The file itself is left as it is
	# (another entry may play it too): what has to change is a copy.
	var wav: AudioStreamWAV = stream as AudioStreamWAV
	if wav != null:
		var loops: bool = wav.loop_mode != AudioStreamWAV.LOOP_DISABLED
		if looped and not loops:
			wav = wav.duplicate() as AudioStreamWAV
			SfxSynth.loop_whole(wav)
		elif loops and not looped:
			wav = wav.duplicate() as AudioStreamWAV
			wav.loop_mode = AudioStreamWAV.LOOP_DISABLED
		# A file that brings its own loop points keeps them.
		return wav
	if "loop" in stream and GameData.as_bool(stream.get("loop")) != looped:
		stream = stream.duplicate() as AudioStream
		stream.set("loop", looped)
	return stream


## The numbers apply() works with, read once (GDD 1.3).
func _configure(tuning: Tuning) -> void:
	_engine = _voices.get(ENGINE)
	_harmonic = _voices.get(ENGINE_HARMONIC)
	if _engine == null or _harmonic == null:
		push_error("Audio: sfx.json needs '%s' and '%s'" % [ENGINE, ENGINE_HARMONIC])
	else:
		var engine: Dictionary = _spec(ENGINE)
		var harmonic: Dictionary = _spec(ENGINE_HARMONIC)
		var kmh: Vector2 = _pair(ENGINE, engine, "speed_kmh")
		var hz: Vector2 = _pair(ENGINE, engine, "speed_hz")
		_speed_from = kmh.x
		_speed_to = kmh.y
		_hz_from = hz.x
		_hz_to = hz.y
		_idle_hz = _above_zero(ENGINE, engine, "idle_hz")
		_engine_hz = _above_zero(ENGINE, engine, "freq")
		_harmonic_hz = _above_zero(ENGINE_HARMONIC, harmonic, "freq")
		_per_gear = PackedFloat64Array()
		for value: Variant in GameData.as_array(harmonic.get("per_gear")):
			_per_gear.append(GameData.as_float(value))
		if _per_gear.size() != tuning.a("gear_speeds").size() + 1:
			push_error("Audio: sfx '%s': \"per_gear\" must name a harmonic for neutral and for each gear" % ENGINE_HARMONIC)
		if _speed_to <= _speed_from:
			push_error("Audio: sfx '%s': \"speed_kmh\" must rise" % ENGINE)

	_rattle = _voices.get(RATTLE)
	_gust = _voices.get(GUST)
	_dust = _voices.get(DUST)
	_rumble = _voices.get(RUMBLE)
	_horn = _voices.get(HORN)
	_horn_behind = _voices.get(HORN_BEHIND)
	_hum = _voices.get(HUM)
	for id: String in [RATTLE, GUST, DUST, RUMBLE, HORN, HORN_BEHIND, HUM]:
		var voice: Voice = _voices.get(id)
		if voice == null or not voice.looped:
			push_error("Audio: sfx.json needs '%s', as a loop" % id)

	_beat = _make_pulse(HEARTBEAT, false)
	if _beat != null:
		var beats: Vector2 = _pair(HEARTBEAT, _spec(HEARTBEAT), "per_minute")
		_beats_slow = beats.x
		_beats_fast = beats.y
		_beat.every = SECONDS_PER_MINUTE / _beats_slow if _beats_slow > 0.0 else 0.0
		_pound_from = tuning.f("pound_from")
		_snap_at = tuning.f("snap_at")
	_ring = _make_pulse(RING, true)
	if _ring != null:
		_ring.every = _above_zero(RING, _spec(RING), "every")
	_tick = _make_pulse(TICK, false)
	if _tick != null:
		_tick.every = _above_zero(TICK, _spec(TICK), "every")
	_siren = _make_pulse(SIREN, false)
	if _siren != null:
		var gaps: Vector2 = _pair(SIREN, _spec(SIREN), "every")
		_siren_calm = gaps.x
		_siren_hot = gaps.y
		_siren.every = _siren_calm
		_suspicion_max = tuning.f("suspicion_max")

	# One loop for each station of the dial, and one for static.
	var stations: Array = tuning.a("radio_stations").duplicate()
	stations.append(String(ItemSim.STATIC))
	for station: Variant in stations:
		var id: String = RADIO % str(station)
		var voice: Voice = _voices.get(id)
		if voice == null or not voice.looped:
			push_error("Audio: sfx.json needs '%s', as a loop" % id)
			continue
		_radio[StringName(str(station))] = voice
	_music = _radio.get(ItemSim.MUSIC)
	if _music != null:
		var warble: Dictionary = GameData.as_dict(_spec(MUSIC).get("warble"))
		_warble_hz = _above_zero(_music.id, warble, "hz")
		_warble_depth = _above_zero(_music.id, warble, "depth")

	var step: int = 1
	while _voices.has(SQUEAL % step):
		_squeals.append(SQUEAL % step)
		step += 1
	if _squeals.is_empty():
		push_error("Audio: sfx.json needs '%s' and those after it" % (SQUEAL % 1))


func _make_pulse(id: String, cut: bool) -> Pulse:
	var voice: Voice = _voices.get(id)
	if voice == null or voice.looped:
		push_error("Audio: sfx.json needs '%s', as a sound that ends" % id)
		return null
	var pulse: Pulse = Pulse.new()
	pulse.voice = voice
	pulse.cut = cut
	_pulses.append(pulse)
	_pulse_of[id] = pulse
	return pulse


## The "synth" object of an entry.
func _spec(id: String) -> Dictionary:
	return GameData.as_dict(GameData.as_dict(_data.root("sfx").get(id)).get("synth"))


## A number an entry must hold.
func _number(spec: Dictionary, key: String, problems: PackedStringArray) -> float:
	if not GameData.is_number(spec.get(key)):
		problems.append("\"%s\" must be a number" % key)
		return 0.0
	return GameData.as_float(spec.get(key))


## A number an entry must hold, above zero.
func _above_zero(id: String, spec: Dictionary, key: String) -> float:
	var value: float = GameData.as_float(spec.get(key))
	if value <= 0.0:
		push_error("Audio: sfx '%s': \"%s\" must be a number above 0" % [id, key])
	return value


## Two numbers above zero an entry must hold, as [first, second].
func _pair(id: String, spec: Dictionary, key: String) -> Vector2:
	var pair: Array = GameData.as_array(spec.get(key))
	if pair.size() != 2 or GameData.as_float(pair[0]) <= 0.0 or GameData.as_float(pair[1]) <= 0.0:
		push_error("Audio: sfx '%s': \"%s\" must be two numbers above 0" % [id, key])
		return Vector2.ONE
	return Vector2(GameData.as_float(pair[0]), GameData.as_float(pair[1]))


# --- The radio ---------------------------------------------------------------

## The loop of the station he is tuned to, or of static. A tape in the deck
## is music whatever the dial says, and wavers once its side has run out.
func _apply_radio(snapshot: Dictionary) -> void:
	var station: StringName = snapshot["radio"]
	var heard: Voice = _radio.get(station)
	var warbling: bool = false
	if station == ItemSim.STATIC and _music != null:
		var effects: Array[StringName] = snapshot["effects"]
		if effects.has(ItemSim.MUSIC):
			heard = _music
		else:
			var items: Array[Dictionary] = snapshot["items"]
			for item: Dictionary in items:
				if item["warbling"]:
					heard = _music
					warbling = true
					break
	for key: Variant in _radio:
		var voice: Voice = _radio[key]
		voice.wanted = voice == heard
	if _warbling and not warbling and _music != null:
		_set_pitch(_music, 1.0)
	_warbling = warbling


# --- Events ------------------------------------------------------------------

## A horn asked for with `behind` is the horn of what comes up behind his
## standing car (GDD 10.3), not his own.
func _on_sfx_requested(data: Dictionary) -> void:
	var id: String = GameData.as_string(data.get("id"))
	play(HORN_BEHIND if id == HORN and GameData.as_bool(data.get("behind")) else id)


## A scrape sounds like one; a crash and a head-on are both a crash.
func _on_hit(data: Dictionary) -> void:
	var kind: int = GameData.as_int(data.get("kind"))
	if kind == Collision.Hit.SCRAPE:
		play(SCRAPE)
	elif kind != Collision.Hit.NONE:
		play(CRASH)


## A rising tone for each step of a chain (GDD 16.3): the first close call is
## the lowest, and the chain's last tone is held once it is reached.
func _on_close_call(data: Dictionary) -> void:
	if _squeals.is_empty():
		return
	play(_squeals[clampi(GameData.as_int(data.get("chain")), 0, _squeals.size() - 1)])


## A soft ding before each heckle's subtitle.
func _on_heckle_started(_data: Dictionary) -> void:
	play(HECKLE)


# --- Sounding ----------------------------------------------------------------

func _start(voice: Voice) -> void:
	voice.player.play()
	voice.starts += 1
	voice.started_at = _elapsed
	_heard = true
	if _trace:
		print("[audio] %d %s" % [Engine.get_process_frames(), voice.id])


func _set_pitch(voice: Voice, pitch: float) -> void:
	if pitch > 0.0 and not is_equal_approx(voice.player.pitch_scale, pitch):
		voice.player.pitch_scale = pitch


func _set_pulse(pulse: Pulse, on: bool, every: float) -> void:
	pulse.every = every
	# A gap that has grown shorter (a jump in Suspicion, in Nerves) is not
	# waited out at the length it had: the next sound is at most one new gap off.
	pulse.left = minf(pulse.left, every)
	if on == pulse.on:
		return
	pulse.on = on
	if on:
		# It begins with a sound, unless that sound has only just been heard
		# (the simulation asks for a call's first ring itself): then the next
		# one comes a whole gap after it.
		pulse.left = maxf(every - (_elapsed - pulse.voice.started_at), 0.0)
	elif pulse.cut:
		pulse.voice.player.stop()


## A loop comes in while it is asked for and goes out when it is not.
func _step_loop(voice: Voice, delta: float) -> void:
	if voice.held > 0.0:
		voice.held = maxf(voice.held - delta, 0.0)
	var on: bool = voice.wanted or voice.held > 0.0
	var target: float = 1.0 if on else 0.0
	if voice.level == target:
		return
	var time: float = voice.fade_in if on else voice.fade_out
	voice.level = target if time <= 0.0 else move_toward(voice.level, target, delta / time)
	if voice.level <= 0.0:
		if voice.player.playing:
			voice.player.stop()
			if _trace:
				print("[audio] %d %s ends" % [Engine.get_process_frames(), voice.id])
		return
	voice.player.volume_db = voice.gain_db + linear_to_db(voice.level)
	if not voice.player.playing:
		_start(voice)


func _audible(voice: Voice) -> bool:
	return voice.level > 0.0 if voice.looped else voice.player.playing


## While a functional cue sounds, everything else is turned down by that
## cue's "duck_db" within its "duck_attack", and comes back within its
## "duck_release" once it is over (GDD 16.5).
func _step_duck(delta: float) -> void:
	var target: float = 0.0
	var attack: float = 0.0
	for cue: Voice in _cues:
		if cue.duck_db < target and _audible(cue):
			target = cue.duck_db
			attack = cue.duck_attack
			_duck_depth = -cue.duck_db
			_duck_release = cue.duck_release
	if target == _duck:
		return
	if target < _duck:
		_duck = target if attack <= 0.0 else move_toward(_duck, target, -target / attack * delta)
	else:
		_duck = target if _duck_release <= 0.0 else move_toward(_duck, target, _duck_depth / _duck_release * delta)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(BUS_BED), _duck)


## The drive scene is gone: what the snapshot asked for is asked for no more.
func _fall_silent() -> void:
	_live = false
	for voice: Voice in _loops:
		voice.wanted = false
	for pulse: Pulse in _pulses:
		_set_pulse(pulse, false, pulse.every)
	if _warbling and _music != null:
		_set_pitch(_music, 1.0)
	_warbling = false
