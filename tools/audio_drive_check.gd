extends RefCounted
## The second half of the sound check (tools/audio_check.gd): the Audio
## autoload, taken through the states of a drive and the events of the bus,
## and through what two set pieces bring with simulations of their own: the
## horn behind a car that stands in the Storm, the Call at Dawn.
## Loaded by the first half once the autoloads are there.
##
## Nothing here waits for a sound to play out: frames are stepped by hand
## (`Audio.advance`), as fast as they compute, so the check does not depend
## on how busy the machine is.

## The states are stepped at this many frames a second.
const FPS: float = 60.0
const STEP: float = 1.0 / FPS
## Seconds the sounds that repeat are counted over.
const COUNT_SECONDS: float = 10.0
const CORE_DIR: String = "res://src/core"
const STREAM_FILE: String = "audio_check_stream.wav"
## The path under which the check holds a sound in memory, as an imported
## file would be held; there is no such file.
const SHARED_STREAM: String = "res://tools/audio_check_shared.wav"
const TAPE: StringName = &"mixtape"
const POCKET: StringName = &"pocket"
## The gear a road is driven in at par (GDD 5.2).
const PAR_GEAR: int = 3
## The seed of the bosses the check drives, and of the road's draws on them.
const BOSS_SEED: int = 1
## How many of the Storm's waits the check stands through for something to
## come up behind him: each wait brings it with the Storm's rear_end_chance.
const STORM_WAITS: int = 30
## How far short of where the Call begins the check sets the car down, m.
const CALL_RUN_UP: float = 2.0

var _data: GameData
var _tuning: Tuning
var _base: Dictionary = {}
## How many checks were made.
var checks: int = 0

var _failures: PackedStringArray = []
## The clock of the snapshots that `_run` hands over, s.
var _clock: float = 0.0


## What was wrong, one line for each; `checks` then says how many were made.
func run(data: GameData) -> PackedStringArray:
	_data = data
	_tuning = data.tuning
	print("boot: the game made its sounds, buses and players in %.1f ms" % Audio.setup_msec)
	_check_entries()
	_check_buses()
	if Audio.ids().size() == _data.root("sfx").size():
		_base = DriveSim.new(_data).snapshot()
		_check_requests()
		_check_engine()
		_check_rumble()
		_check_heartbeat()
		_check_radio()
		_check_tape()
		_check_squeals()
		_check_siren()
		_check_phone()
		_check_call()
		_check_hum()
		_check_horn()
		_check_horn_behind()
		_check_indicator()
		_check_events()
		_check_scene_gone()
		_check_stream_files()
		_time_a_frame()
	else:
		_fail("Audio made %d of the %d sounds; the states of the drive were not checked" % [
			Audio.ids().size(), _data.root("sfx").size()])
	return _failures


# --- The entries -------------------------------------------------------------

## An entry says nothing that neither the generator nor the player reads: a
## misspelt key would otherwise be a number that silently does nothing.
func _check_entries() -> void:
	for key: Variant in _data.root("sfx"):
		for name: Variant in _synth(str(key)):
			_expect(SfxSynth.KEYS.has(str(name)) or Audio.PLAY_KEYS.has(str(name)),
					"%s: nothing reads its key \"%s\"" % [str(key), str(name)])


# --- The buses ---------------------------------------------------------------

func _check_buses() -> void:
	for bus: StringName in [Audio.BUS_CUES, Audio.BUS_BED]:
		var index: int = AudioServer.get_bus_index(bus)
		if _expect(index != -1, "there is no bus '%s'" % bus):
			_expect(AudioServer.get_bus_send(index) == Audio.BUS_MASTER, "the bus '%s' must feed Master" % bus)
			_expect(AudioServer.get_bus_volume_db(index) == 0.0 and not AudioServer.is_bus_mute(index),
					"the bus '%s' must rest at 0 dB" % bus)
	for id: String in Audio.ids():
		var functional: bool = GameData.as_bool(_synth(id).get("functional"))
		_expect(Audio.bus_of(id) == (Audio.BUS_CUES if functional else Audio.BUS_BED), "%s plays on the wrong bus" % id)
		_expect(is_equal_approx(Audio.volume_of(id), GameData.as_float(_synth(id).get("gain_db"))),
				"%s: its player is at %.1f dB, its entry says %s" % [id, Audio.volume_of(id), str(_synth(id).get("gain_db"))])


# --- What the simulation asks for --------------------------------------------

## Every id the simulation names in an `sfx_requested`, and every one a
## ritual or an item names in data, is a sound and is heard when asked for.
func _check_requests() -> void:
	var ids: PackedStringArray = _requested_ids()
	print("requests: the simulation asks for %s" % ", ".join(ids))
	_expect(not ids.is_empty(), "no sfx_requested was found in %s" % CORE_DIR)
	for id: String in ids:
		if not _expect(Audio.has_sound(id), "the simulation asks for '%s', which sfx.json does not have" % id):
			continue
		_rest()
		var before: int = Audio.starts_of(id)
		Events.emit_event("sfx_requested", {"id": id})
		_wait(STEP * 2.0)
		_expect(Audio.starts_of(id) == before + 1, "'%s' is asked for and not heard" % id)


func _requested_ids() -> PackedStringArray:
	var found: Dictionary = {}
	var literal: RegEx = RegEx.new()
	literal.compile("sfx_requested.*\"id\":\\s*\"([a-z0-9_]+)\"")
	for path: String in ProjectFiles.find(CORE_DIR, PackedStringArray(["gd"])):
		for line: String in FileAccess.get_file_as_string(path).split("\n"):
			var hit: RegExMatch = literal.search(line)
			if hit != null:
				found[hit.get_string(1)] = true
	for set_name: String in ["rituals", "items"]:
		for record: Dictionary in _data.records(set_name):
			_collect_named(record, found)
	var out: PackedStringArray = []
	for id: Variant in found:
		out.append(str(id))
	out.sort()
	return out


## The sounds a record names: an "sfx" field, and "sfx:<id>" among its ops.
func _collect_named(value: Variant, found: Dictionary) -> void:
	if value is Dictionary:
		var record: Dictionary = value
		for key: Variant in record:
			if str(key) == "sfx" and record[key] is String:
				found[str(record[key])] = true
			else:
				_collect_named(record[key], found)
	elif value is Array:
		var list: Array = value
		for entry: Variant in list:
			_collect_named(entry, found)
	elif value is String and str(value).begins_with("sfx:"):
		found[str(value).substr(4)] = true


# --- The states of a drive ---------------------------------------------------

func _check_engine() -> void:
	var engine: Dictionary = _synth(Audio.ENGINE)
	var harmonic: Dictionary = _synth(Audio.ENGINE_HARMONIC)
	var kmh: Array = GameData.as_array(engine.get("speed_kmh"))
	var hz: Array = GameData.as_array(engine.get("speed_hz"))
	var per_gear: Array = GameData.as_array(harmonic.get("per_gear"))
	if kmh.size() != 2 or hz.size() != 2 or per_gear.size() < 2:
		_fail("engine: its entries do not hold what the check needs")
		return
	var kmh_from: float = GameData.as_float(kmh[0])
	var kmh_to: float = GameData.as_float(kmh[1])
	var hz_from: float = GameData.as_float(hz[0])
	var hz_to: float = GameData.as_float(hz[1])
	var freq: float = GameData.as_float(engine.get("freq"))
	var harmonic_freq: float = GameData.as_float(harmonic.get("freq"))
	var top_gear: int = per_gear.size() - 1
	_rest()
	# The pitch is the speed: at the two speeds the table names, between them, and standing.
	for share: float in [0.0, 0.5, 1.0]:
		var speed: float = lerpf(kmh_from, kmh_to, share)
		var pitch: float = lerpf(hz_from, hz_to, share)
		_run(_snap({"speed": speed, "gear": top_gear}), 1.0)
		_expect(Audio.is_sounding(Audio.ENGINE), "engine: not heard at %.0f km/h" % speed)
		_expect(is_equal_approx(Audio.pitch_of(Audio.ENGINE) * freq, pitch),
				"engine: %.1f Hz at %.0f km/h, not %.1f" % [Audio.pitch_of(Audio.ENGINE) * freq, speed, pitch])
	var standing: float = maxf(hz_from - kmh_from * (hz_to - hz_from) / (kmh_to - kmh_from), GameData.as_float(engine.get("idle_hz")))
	_run(_snap({"speed": 0.0, "gear": GearGate.NEUTRAL}), 1.0)
	_expect(Audio.is_sounding(Audio.ENGINE), "engine: not heard standing")
	_expect(is_equal_approx(Audio.pitch_of(Audio.ENGINE) * freq, standing),
			"engine: %.1f Hz standing, not %.1f" % [Audio.pitch_of(Audio.ENGINE) * freq, standing])
	# A different added harmonic in each gear; none in neutral.
	var heard: Dictionary = {}
	for gear: int in per_gear.size():
		var multiple: float = GameData.as_float(per_gear[gear])
		_run(_snap({"speed": kmh_from, "gear": gear}), 1.0 + GameData.as_float(harmonic.get("fade_out")))
		_expect(Audio.is_sounding(Audio.ENGINE_HARMONIC) == (multiple > 0.0),
				"engine: gear %d %s an added harmonic" % [gear, "must have" if multiple > 0.0 else "has no"])
		if multiple > 0.0:
			_expect(is_equal_approx(Audio.pitch_of(Audio.ENGINE_HARMONIC) * harmonic_freq, multiple * hz_from),
					"engine: the harmonic of gear %d is at %.1f Hz, not %.1f" % [
						gear, Audio.pitch_of(Audio.ENGINE_HARMONIC) * harmonic_freq, multiple * hz_from])
			_expect(not heard.has(multiple), "engine: gear %d has the harmonic of another gear" % gear)
			heard[multiple] = true
	_expect(GameData.as_float(per_gear[GearGate.NEUTRAL]) == 0.0, "engine: neutral has no added harmonic")
	# A Wreck: the engine dies.
	_run(_snap({"speed": kmh_from, "gear": top_gear, "wrecked": true}), 1.0 + GameData.as_float(engine.get("fade_out")))
	_expect(not Audio.is_sounding(Audio.ENGINE) and not Audio.is_sounding(Audio.ENGINE_HARMONIC), "engine: still heard after a Wreck")


func _check_rumble() -> void:
	var spec: Dictionary = _synth(Audio.RUMBLE)
	var duck: float = GameData.as_float(spec.get("duck_db"))
	var bed: int = AudioServer.get_bus_index(Audio.BUS_BED)
	var cruise: float = _tuning.fi("gear_speeds", 2)
	_rest()
	_run(_snap({"on_rumble": true, "speed": cruise}), 1.0)
	_expect(Audio.is_sounding(Audio.RUMBLE), "rumble_strip: not heard on the strip")
	_expect(is_equal_approx(Audio.volume_of(Audio.RUMBLE), GameData.as_float(spec.get("gain_db"))), "rumble_strip: not all the way in after a second")
	_expect(is_equal_approx(Audio.duck_db(), duck), "rumble_strip: everything else is down %.1f dB, not %.1f" % [-Audio.duck_db(), -duck])
	_expect(is_equal_approx(AudioServer.get_bus_volume_db(bed), duck), "rumble_strip: the bus of everything else is at %.1f dB" % AudioServer.get_bus_volume_db(bed))
	_run(_snap({"on_rumble": false, "speed": cruise}), 1.0)
	_expect(not Audio.is_sounding(Audio.RUMBLE), "rumble_strip: still heard off the strip")
	_expect(Audio.duck_db() == 0.0 and AudioServer.get_bus_volume_db(bed) == 0.0, "rumble_strip: everything else did not come back")
	_run(_snap({"on_rumble": true, "speed": 0.0}), 1.0)
	_expect(not Audio.is_sounding(Audio.RUMBLE), "rumble_strip: heard under a car that stands")


## The heartbeat is the tell of Pound: from the first of per_minute where
## Pound begins to the second at the edge of a Snap.
func _check_heartbeat() -> void:
	var per_minute: Array = GameData.as_array(_synth(Audio.HEARTBEAT).get("per_minute"))
	if per_minute.size() != 2:
		_fail("heartbeat: \"per_minute\" must be two rates")
		return
	var pound_from: float = _tuning.f("pound_from")
	var snap_at: float = _tuning.f("snap_at")
	for share: float in [0.0, 0.5, 1.0]:
		var nerves: float = lerpf(pound_from, snap_at, share)
		var rate: float = lerpf(GameData.as_float(per_minute[0]), GameData.as_float(per_minute[1]), share)
		var beats: int = _count(Audio.HEARTBEAT, _snap({"pound": true, "nerves": nerves}), COUNT_SECONDS)
		var asked: float = COUNT_SECONDS * rate / Audio.SECONDS_PER_MINUTE
		_expect(beats >= floori(asked) and beats <= ceili(asked) + 1,
				"heartbeat: %d beats in %.0f s at Nerves %.0f; %.0f a minute is %.1f" % [beats, COUNT_SECONDS, nerves, rate, asked])
	_expect(_count(Audio.HEARTBEAT, _snap({"pound": false, "nerves": pound_from}), COUNT_SECONDS) == 0, "heartbeat: heard without Pound")


func _check_radio() -> void:
	var stations: PackedStringArray = []
	for station: Variant in _tuning.a("radio_stations"):
		stations.append(str(station))
	stations.append(String(ItemSim.STATIC))
	_rest()
	for station: String in stations:
		_run(_snap({"radio": StringName(station)}), 1.0)
		for other: String in stations:
			_expect(Audio.is_sounding(Audio.RADIO % other) == (other == station),
					"radio: tuned to %s, %s %s" % [station, Audio.RADIO % other, "is not heard" if other == station else "is heard"])


## A tape in the deck, through a simulation of its own: it is music whatever
## the dial says, and past the end of its side its pitch wavers.
func _check_tape() -> void:
	if not _data.has_record("items", String(TAPE)):
		_fail("tape: there is no item '%s' to play" % TAPE)
		return
	var music: String = Audio.RADIO % String(ItemSim.MUSIC)
	var still: String = Audio.RADIO % String(ItemSim.STATIC)
	var warble: Dictionary = GameData.as_dict(_synth(music).get("warble"))
	var depth: float = GameData.as_float(warble.get("depth"))
	var side: float = GameData.as_float(GameData.as_dict(_data.record("items", String(TAPE)).get("params")).get("side_s"))
	var sim: DriveSim = DriveSim.new(_data)
	sim.in_encounter = true
	_rest()
	_drive(sim, 1.0)
	_expect(Audio.is_sounding(still) and not Audio.is_sounding(music), "tape: an empty deck off its station is static")
	sim.give_item(TAPE)
	_drive(sim, 1.0)
	_expect(Audio.is_sounding(music) and not Audio.is_sounding(still), "tape: a tape in the deck is not heard as music")
	_expect(is_equal_approx(Audio.pitch_of(music), 1.0), "tape: a tape that plays must not waver")
	_drive(sim, side)
	var low: float = 1.0
	var high: float = 1.0
	for frame: int in roundi(FPS * 2.0):
		_drive(sim, STEP)
		low = minf(low, Audio.pitch_of(music))
		high = maxf(high, Audio.pitch_of(music))
	_expect(Audio.is_sounding(music), "tape: a tape past its side is not heard")
	_expect(low < 1.0 - depth * 0.5 and high > 1.0 + depth * 0.5 and low >= 1.0 - depth - 0.001 and high <= 1.0 + depth + 0.001,
			"tape: past its side the pitch must waver by %s; it went from %.3f to %.3f" % [str(depth), low, high])
	# The moment music is heard that does not waver, it is at its own pitch again.
	var guard: int = roundi(FPS)
	while absf(Audio.pitch_of(music) - 1.0) < depth * 0.5 and guard > 0:
		_drive(sim, STEP)
		guard -= 1
	_expect(guard > 0, "tape: the wavering pitch never left its own for long")
	_run(_snap({"radio": ItemSim.MUSIC}), STEP * 2.0)
	_expect(Audio.is_sounding(music) and is_equal_approx(Audio.pitch_of(music), 1.0), "tape: the radio's music wavers after a tape did")


## A rising tone for each step of a chain; the last one is kept.
func _check_squeals() -> void:
	var steps: int = 0
	while Audio.has_sound(Audio.SQUEAL % (steps + 1)):
		steps += 1
	_rest()
	for chain: int in steps + 2:
		var id: String = Audio.SQUEAL % mini(chain + 1, steps)
		var before: int = Audio.starts_of(id)
		Events.emit_event("close_call", {"count": 1, "cash": 0.0, "mult": 1.0, "chain": chain})
		_expect(Audio.starts_of(id) == before + 1, "squeals: close call %d of a chain is not heard as %s" % [chain + 1, id])


func _check_siren() -> void:
	var gaps: Array = GameData.as_array(_synth(Audio.SIREN).get("every"))
	if gaps.size() != 2:
		_fail("siren_chirp: \"every\" must be two gaps")
		return
	var calm: float = GameData.as_float(gaps[0])
	var hot: float = GameData.as_float(gaps[1])
	var most: float = _tuning.f("suspicion_max")
	_expect(hot < calm, "siren_chirp: the chirps must come faster as Suspicion grows")
	_expect(_count(Audio.SIREN, _snap({"police_lights": true}), calm * 0.5) == 1, "siren_chirp: the blue lights come without a chirp")
	_expect(_count(Audio.SIREN, _snap({"suspicion_watching": true, "suspicion": 0.0}), calm * 3.5) == 4,
			"siren_chirp: with no Suspicion, one chirp every %.1f s" % calm)
	_expect(_count(Audio.SIREN, _snap({"suspicion_watching": true, "suspicion": most}), hot * 3.5) == 4,
			"siren_chirp: with all of it, one chirp every %.1f s" % hot)
	_expect(_count(Audio.SIREN, _snap({"suspicion_watching": true, "suspicion": most, "pulled_over": true}), calm * 2.0) == 0,
			"siren_chirp: heard while the officer stands at the window")
	_expect(_count(Audio.SIREN, _snap({}), calm * 2.0) == 0, "siren_chirp: heard with nobody behind him")


func _check_phone() -> void:
	var every: float = GameData.as_float(_synth(Audio.RING).get("every"))
	var ringing: Dictionary = _snap({"caller": String(ItemSim.CALLER_DISPATCHER)})
	_expect(_count(Audio.RING, ringing, every * 3.5) == 4, "phone_ring: a call must ring at once and every %.1f s" % every)
	_expect(Audio.is_sounding(Audio.RING), "phone_ring: not ringing while the call rings")
	_run(_snap({}), STEP * 2.0)
	_expect(not Audio.is_sounding(Audio.RING), "phone_ring: still ringing when the call is over")
	# The simulation asks for the first ring itself: it is not heard twice.
	_rest()
	var before: int = Audio.starts_of(Audio.RING)
	Events.emit_event("sfx_requested", {"id": Audio.RING})
	_run(ringing, every * 3.5)
	_expect(Audio.starts_of(Audio.RING) - before == 4, "phone_ring: the first ring is heard twice, or the rest are late")


## The Call (GDD 10.4), on Dawn's own road: the phone in his pocket rings as
## the one on its mount does, for as long as the simulation says it rings,
## and is cut the moment he answers.
func _check_call() -> void:
	var every: float = GameData.as_float(_synth(Audio.RING).get("every"))
	var ring_s: float = GameData.as_float(GameData.as_dict(_boss_numbers(BossSim.DAWN).get("call")).get("ring_s"))
	if every <= 0.0 or ring_s <= 0.0:
		_fail("the Call: phone_ring's \"every\" and Dawn's ring_s must be above 0")
		return
	# One ring as the Call begins, and one every `every` s while it rings.
	var rings: int = ceili(ring_s / every)
	_expect(rings >= 2, "phone_ring: one ring every %.1f s is a single ring in the %.0f s of the Call; a phone must ring again while it rings" % [every, ring_s])

	# Ignored: it rings out.
	var before: int = Audio.starts_of(Audio.RING)
	var sim: DriveSim = _to_the_call()
	if sim == null:
		return
	_expect(GameData.as_string(sim.snapshot()["caller"]) == DriveSim.NOOR, "the Call: the snapshot does not name Noor as the caller while it rings")
	_expect(Audio.starts_of(Audio.RING) - before == 1 and Audio.is_sounding(Audio.RING), "phone_ring: the Call begins without a ring")
	# Frames after the one in which it began, to the one in which it is over.
	var frames: int = 0
	var guard: int = roundi((ring_s + 2.0) * FPS)
	while sim.boss.call == BossSim.CALL_RINGING and guard > 0:
		guard -= 1
		frames += 1
		_drive(sim, STEP)
	_expect(absi(frames - roundi(ring_s * FPS)) <= 1, "the Call: it rang for %.2f s, not %.1f" % [float(frames) * STEP, ring_s])
	_expect(Audio.starts_of(Audio.RING) - before == rings,
			"phone_ring: the Call rings %d times in its %.0f s; one ring every %.1f s is %d" % [Audio.starts_of(Audio.RING) - before, ring_s, every, rings])
	_expect(not Audio.is_sounding(Audio.RING), "phone_ring: still ringing when the Call has rung out")
	_drive(sim, every * 2.5)
	_expect(Audio.starts_of(Audio.RING) - before == rings, "phone_ring: it rings on after the Call has rung out")

	# Answered with a TAP on his pocket, early in its ringing and after a
	# second ring if there is time for one: the ring is cut there and then.
	before = Audio.starts_of(Audio.RING)
	sim = _to_the_call()
	if sim == null:
		return
	var began: int = sim.tick
	_drive(sim, minf(every * 1.25, ring_s * 0.25))
	var input: DriveInput = DriveInput.new()
	input.pointer_is_absolute = true
	input.pointer = sim.hand.anchor_pointer(sim.hand.anchor_index(POCKET))
	guard = roundi(3.0 * FPS)
	while sim.hand.at_id() != POCKET and guard > 0:
		guard -= 1
		_drive(sim, STEP, input)
	input.lmb = true
	_drive(sim, STEP * 2.0, input)
	input.lmb = false
	guard = roundi(FPS)
	while sim.boss.call == BossSim.CALL_RINGING and guard > 0:
		guard -= 1
		_drive(sim, STEP, input)
	if not _expect(sim.boss.call == BossSim.CALL_TALKING, "the Call: a TAP on his pocket did not answer it; what an answer does to the ring was not checked"):
		return
	# It rang as it began and every `every` s since (give or take two frames).
	var rung: int = Audio.starts_of(Audio.RING) - before
	var rang_for: float = float(sim.tick - began) * DriveSim.DT
	_expect(rung >= floori(maxf(rang_for - STEP * 2.0, 0.0) / every) + 1 and rung <= floori((rang_for + STEP * 2.0) / every) + 1,
			"phone_ring: the Call rang %d times in the %.2f s before he answered it" % [rung, rang_for])
	_expect(not Audio.is_sounding(Audio.RING), "phone_ring: still ringing with the phone at his ear")
	_drive(sim, every * 2.5, input)
	_expect(Audio.starts_of(Audio.RING) - before == rung, "phone_ring: it rings on while he talks")


func _check_hum() -> void:
	var spec: Dictionary = _synth(Audio.HUM)
	var out: float = GameData.as_float(spec.get("fade_out")) + STEP * 3.0
	_rest()
	_run(_snap({"cramp": DriveSim.HUM}), 1.0)
	_expect(Audio.is_sounding(Audio.HUM), "phantom_hum: not heard during the hum")
	_run(_snap({"cramp": DriveSim.CRAMPED}), out)
	_expect(not Audio.is_sounding(Audio.HUM), "phantom_hum: still heard when the cramp has come")
	# Asked for by id it lasts its "hold", unless the snapshot knows better.
	_rest()
	Events.emit_event("sfx_requested", {"id": Audio.HUM})
	_wait(GameData.as_float(spec.get("hold")) * 0.5)
	_expect(Audio.is_sounding(Audio.HUM), "phantom_hum: asked for, it is not heard")
	_wait(GameData.as_float(spec.get("hold")) * 0.5 + out)
	_expect(not Audio.is_sounding(Audio.HUM), "phantom_hum: asked for, it does not end")
	Events.emit_event("sfx_requested", {"id": Audio.HUM})
	_run(_snap({"cramp": ""}), out)
	_expect(not Audio.is_sounding(Audio.HUM), "phantom_hum: heard on, though nothing hums")


func _check_horn() -> void:
	var spec: Dictionary = _synth(Audio.HORN)
	var hold: float = GameData.as_float(spec.get("hold"))
	var out: float = GameData.as_float(spec.get("fade_out")) + STEP * 3.0
	_rest()
	Events.emit_event("sfx_requested", {"id": Audio.HORN})
	_wait(hold * 0.5)
	_expect(Audio.is_sounding(Audio.HORN), "horn: a honk is not heard")
	_wait(hold * 0.5 + out)
	_expect(not Audio.is_sounding(Audio.HORN), "horn: a honk does not end")
	# A clock that jumps (another simulation, a long hitch) is not caught up
	# with: the honk that was sounding is not swallowed by it.
	Events.emit_event("sfx_requested", {"id": Audio.HORN})
	_run(_snap({}), STEP * 2.0)
	_clock += Audio.SECONDS_PER_MINUTE
	_run(_snap({}), STEP)
	_expect(Audio.is_sounding(Audio.HORN), "horn: a jump of the snapshot's clock ends a honk")
	_run(_snap({}), hold + out)
	_expect(not Audio.is_sounding(Audio.HORN), "horn: a honk does not end after the clock has jumped")
	# A Snap: he leans on it for as long as the Snap lasts.
	var snap: float = _tuning.f("snap_duration")
	Events.emit_event("sfx_requested", {"id": Audio.HORN})
	_run(_snap({"snap": true}), snap)
	_expect(Audio.is_sounding(Audio.HORN), "horn: not held down through a Snap")
	_run(_snap({"snap": false}), out)
	_expect(not Audio.is_sounding(Audio.HORN), "horn: still heard after the Snap")


## What comes up behind his standing car in the Storm (GDD 10.3) is heard by
## a horn that is not his own, from the moment it shows itself until it has
## hit him or missed him.
func _check_horn_behind() -> void:
	var spec: Dictionary = _synth(Audio.HORN_BEHIND)
	var hold: float = GameData.as_float(spec.get("hold"))
	var out: float = GameData.as_float(spec.get("fade_out")) + STEP * 3.0
	var tell: float = GameData.as_float(_boss_numbers(BossSim.STORM).get("rear_end_tell_s"))
	# Asked for on the bus, as the simulation asks: another horn than his.
	_rest()
	var own: int = Audio.starts_of(Audio.HORN)
	Events.emit_event("sfx_requested", {"id": Audio.HORN, "behind": true})
	_wait(hold * 0.5)
	_expect(Audio.is_sounding(Audio.HORN_BEHIND), "horn_behind: a horn asked for from behind him is not heard")
	_expect(Audio.starts_of(Audio.HORN) == own and not Audio.is_sounding(Audio.HORN), "horn_behind: the horn behind him is heard as his own")
	_wait(hold * 0.5 + out)
	_expect(not Audio.is_sounding(Audio.HORN_BEHIND), "horn_behind: asked for, it does not end")
	# His own honk, and that of a vehicle he passes, stay what they were.
	for request: Dictionary in [{"id": Audio.HORN}, {"id": Audio.HORN, "vehicle": 1}, {"id": Audio.HORN, "behind": false}]:
		_rest()
		Events.emit_event("sfx_requested", request)
		_wait(STEP * 2.0)
		_expect(Audio.is_sounding(Audio.HORN) and not Audio.is_sounding(Audio.HORN_BEHIND), "horn: the honk %s is heard as the horn behind him" % str(request))
	# The snapshot knows how long it comes: longer than the hold, or not at all.
	_rest()
	Events.emit_event("sfx_requested", {"id": Audio.HORN, "behind": true})
	_run(_snap({"rear_end_in": hold}), hold * 2.0)
	_expect(Audio.is_sounding(Audio.HORN_BEHIND), "horn_behind: not heard for as long as something comes up behind him")
	_run(_snap({"rear_end_in": 0.0}), out)
	_expect(not Audio.is_sounding(Audio.HORN_BEHIND), "horn_behind: still heard when nothing comes any more")
	Events.emit_event("sfx_requested", {"id": Audio.HORN, "behind": true})
	_run(_snap({"rear_end_in": 0.0}), out)
	_expect(not Audio.is_sounding(Audio.HORN_BEHIND), "horn_behind: heard on, though nothing comes")
	if tell <= 0.0:
		_fail("the Storm: its rear_end_tell_s must be above 0")
		return

	# The Storm itself. He stands dark in his lane, and stays: the horn is
	# heard for the whole of the tell, and then the crash.
	var brake: DriveInput = DriveInput.new()
	var sim: DriveSim = _stand_in_the_storm(brake)
	if sim == null:
		return
	own = Audio.starts_of(Audio.HORN)
	var crashes: int = Audio.starts_of(Audio.CRASH)
	var fell_silent: bool = false
	var frames: int = 0
	var guard: int = roundi((tell + 1.0) * FPS)
	while Audio.starts_of(Audio.CRASH) == crashes and guard > 0:
		guard -= 1
		if not Audio.is_sounding(Audio.HORN_BEHIND):
			fell_silent = true
		_drive(sim, STEP, brake)
		frames += 1
	if _expect(guard > 0, "the Storm: what came up behind him did not hit him; its horn up to the hit was not checked"):
		_expect(not fell_silent, "horn_behind: it falls silent before it has hit him")
		_expect(absi(frames - roundi(tell * FPS)) <= 1, "horn_behind: heard %.2f s before the crash; the tell is %.1f s" % [float(frames) * STEP, tell])
		_expect(Audio.starts_of(Audio.CRASH) == crashes + 1, "crash: what hits him from behind is not heard as one crash")
		_drive(sim, out, brake)
		_expect(not Audio.is_sounding(Audio.HORN_BEHIND), "horn_behind: still heard after it has hit him")
	_expect(Audio.starts_of(Audio.HORN) == own, "horn: his own horn sounds when another comes up behind him")

	# The same Storm, and he drives off within the tell: it misses him, and
	# its horn is over.
	sim = _stand_in_the_storm(brake)
	if sim == null:
		return
	_drive(sim, tell * 0.5, brake)
	_expect(Audio.is_sounding(Audio.HORN_BEHIND), "horn_behind: not heard half-way through the tell")
	crashes = Audio.starts_of(Audio.CRASH)
	brake.rmb = false
	sim.car.speed = _tuning.fi("gear_speeds", PAR_GEAR - 1)
	_drive(sim, out, brake)
	_expect(not Audio.is_sounding(Audio.HORN_BEHIND), "horn_behind: still heard when he has driven off and nothing comes any more")
	_drive(sim, tell * 2.0, brake)
	_expect(Audio.starts_of(Audio.CRASH) == crashes, "the Storm: he drove off within the tell and was hit all the same")


func _check_indicator() -> void:
	var every: float = GameData.as_float(_synth(Audio.TICK).get("every"))
	_expect(_count(Audio.TICK, _snap({"indicator": 1}), every * 3.5) == 4, "indicator_tick: the indicator must tick at once and every %.2f s" % every)
	_expect(_count(Audio.TICK, _snap({"indicator": -1}), every * 3.5) == 4, "indicator_tick: the left indicator must tick too")
	_expect(_count(Audio.TICK, _snap({}), every * 3.5) == 0, "indicator_tick: heard with nothing signalling")
	# A tick asked for while it ticks (the hazard button) takes the place of the next one.
	_rest()
	var before: int = Audio.starts_of(Audio.TICK)
	_run(_snap({"indicator": 1}), every * 0.5)
	Events.emit_event("sfx_requested", {"id": Audio.TICK})
	_run(_snap({"indicator": 1}), every * 0.75)
	_expect(Audio.starts_of(Audio.TICK) - before == 2, "indicator_tick: a tick asked for while it ticks must put off the next one")
	# A cue that ends: everything else makes room while it sounds, and comes back.
	var yawn: Dictionary = _synth("yawn")
	_rest()
	Audio.play("yawn")
	_wait(GameData.as_float(yawn.get("duck_attack")) + STEP * 2.0)
	_expect(is_equal_approx(Audio.duck_db(), GameData.as_float(yawn.get("duck_db"))), "yawn: everything else is down %.1f dB during a yawn" % -Audio.duck_db())
	Audio.stop("yawn")
	_wait(GameData.as_float(yawn.get("duck_release")) + STEP * 2.0)
	_expect(Audio.duck_db() == 0.0, "yawn: everything else did not come back after it")


## The bus events that have a sound of their own.
func _check_events() -> void:
	_rest()
	for pair: Array in [[Collision.Hit.SCRAPE, Audio.SCRAPE], [Collision.Hit.CRASH, Audio.CRASH], [Collision.Hit.HEAD_ON, Audio.CRASH]]:
		var kind: int = pair[0]
		var id: String = pair[1]
		var before: int = Audio.starts_of(id)
		Events.emit_event("hit", {"kind": kind, "lamps": 1, "vehicle": 0, "spared": false})
		_expect(Audio.starts_of(id) == before + 1, "a hit of kind %d is not heard as %s" % [kind, id])
	var dings: int = Audio.starts_of(Audio.HECKLE)
	Events.emit_event("heckle_started", {})
	_expect(Audio.starts_of(Audio.HECKLE) == dings + 1, "a heckle begins without its ding")


## When no snapshot comes any more, what it asked for goes quiet.
func _check_scene_gone() -> void:
	_rest()
	_run(_snap({"speed": _tuning.fi("gear_speeds", 2), "radio": ItemSim.MUSIC, "pound": true, "nerves": _tuning.f("snap_at"), "rear_end_in": 1.0}), 1.0)
	_expect(Audio.is_sounding(Audio.ENGINE) and Audio.is_sounding(Audio.RADIO % String(ItemSim.MUSIC)) and Audio.is_sounding(Audio.HORN_BEHIND),
			"the drive is not heard")
	var beats: int = Audio.starts_of(Audio.HEARTBEAT)
	_wait(2.0)
	for id: String in Audio.ids():
		if GameData.as_bool(_synth(id).get("loop")):
			_expect(not Audio.is_sounding(id), "%s is still heard when the drive scene is gone" % id)
	_expect(Audio.starts_of(Audio.HEARTBEAT) - beats <= 1, "the heartbeat goes on when the drive scene is gone")


## An artist's file in "stream" is played in place of the generated buffer
## (GDD 14). Whether it loops is the entry's word, and the file itself is
## never changed: two entries may name one file.
func _check_stream_files() -> void:
	var yawn: AudioStreamWAV = Audio.stream_of("yawn") as AudioStreamWAV
	var music: String = Audio.RADIO % String(ItemSim.MUSIC)
	var disk_path: String = Game.user_dir.path_join(STREAM_FILE)
	if yawn == null or yawn.save_to_wav(disk_path) != OK:
		_fail("stream: cannot write %s to try it" % disk_path)
		return
	var frames: int = yawn.data.size() / 2
	# A file the engine has imported is one object for all who load it: here
	# a sound held under a path of its own. One that it has not imported is
	# read from the disk.
	var shared: AudioStreamWAV = yawn.duplicate() as AudioStreamWAV
	shared.take_over_path(SHARED_STREAM)
	var changed: GameData = GameData.load_from(_data.dir)
	GameData.as_dict(changed.root("sfx").get(Audio.HECKLE))["stream"] = SHARED_STREAM
	GameData.as_dict(changed.root("sfx").get(music))["stream"] = SHARED_STREAM
	GameData.as_dict(changed.root("sfx").get(Audio.SCRAPE))["stream"] = disk_path
	Audio.setup(changed)
	var once: AudioStreamWAV = Audio.stream_of(Audio.HECKLE) as AudioStreamWAV
	var round: AudioStreamWAV = Audio.stream_of(music) as AudioStreamWAV
	var read: AudioStreamWAV = Audio.stream_of(Audio.SCRAPE) as AudioStreamWAV
	_expect(once == shared, "stream: heckle must play the file its entry names, as it is")
	# A loop: the whole of a copy of the file, and its beginning again after its end.
	_expect(round != null and round != shared and round.loop_mode == AudioStreamWAV.LOOP_FORWARD and round.loop_end == frames
			and round.data.size() / 2 == frames + SfxSynth.LOOP_TAIL, "stream: radio_music must loop the whole of a copy of its file")
	_expect(shared.loop_mode == AudioStreamWAV.LOOP_DISABLED and shared.data.size() / 2 == frames,
			"stream: a file that an entry loops must itself be left as it is")
	_expect(read != null and read.loop_mode == AudioStreamWAV.LOOP_DISABLED and read.data.size() / 2 == frames,
			"stream: scrape must play the file on the disk that its entry names")
	# A file that loops by itself keeps its loop for an entry that loops, and
	# is played once, as a copy, by an entry that ends.
	shared.loop_mode = AudioStreamWAV.LOOP_FORWARD
	shared.loop_end = frames - 1
	Audio.setup(changed)
	once = Audio.stream_of(Audio.HECKLE) as AudioStreamWAV
	_expect(Audio.stream_of(music) == shared, "stream: a file with a loop of its own must be played with it")
	_expect(once != null and once != shared and once.loop_mode == AudioStreamWAV.LOOP_DISABLED,
			"stream: heckle must not loop a file that loops")
	_expect(shared.loop_mode == AudioStreamWAV.LOOP_FORWARD, "stream: a file that an entry plays once must itself be left as it is")
	Audio.setup(_data)
	_expect(Audio.stream_of(Audio.HECKLE).get_length() < yawn.get_length() * 0.5
			and (Audio.stream_of(music) as AudioStreamWAV).loop_end != frames,
			"stream: the generated sounds did not come back")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(disk_path))


## What a frame of sound costs: a busy snapshot applied and stepped.
func _time_a_frame() -> void:
	var busy: Dictionary = _snap({
		"speed": _tuning.fi("gear_speeds", 2), "gear": 3, "on_rumble": true, "radio": ItemSim.MUSIC,
		"pound": true, "nerves": _tuning.f("snap_at"), "suspicion_watching": true, "indicator": 1,
	})
	_rest()
	var frames: int = roundi(COUNT_SECONDS * FPS)
	var began: int = Time.get_ticks_usec()
	for frame: int in frames:
		_clock += STEP
		busy["time"] = _clock
		Audio.advance(STEP)
		Audio.apply(busy)
	print("frame: apply() and a frame of sound cost %.1f microseconds, with everything sounding" % (
		float(Time.get_ticks_usec() - began) / float(frames)))
	_rest()


# --- Stepping ----------------------------------------------------------------

## The base snapshot with some of its entries changed.
func _snap(changes: Dictionary) -> Dictionary:
	var out: Dictionary = _base.duplicate()
	out.merge(changes, true)
	return out


## Frames of a drive in this state, as the game runs them: the autoload's
## frame first, then the scene hands over the snapshot, whose clock has moved
## on by a frame.
func _run(snapshot: Dictionary, seconds: float) -> void:
	for frame: int in roundi(seconds * FPS):
		_clock += STEP
		snapshot["time"] = _clock
		Audio.advance(STEP)
		Audio.apply(snapshot)


## Frames with no snapshot.
func _wait(seconds: float) -> void:
	for frame: int in roundi(seconds * FPS):
		Audio.advance(STEP)


## Everything quiet, and everything else back at its level.
func _rest() -> void:
	_wait(STEP * 3.0)
	for id: String in Audio.ids():
		Audio.stop(id)
	_wait(1.0)


## How many times a sound starts in `seconds` of a state, from quiet.
func _count(id: String, snapshot: Dictionary, seconds: float) -> int:
	_rest()
	var before: int = Audio.starts_of(id)
	_run(snapshot, seconds)
	return Audio.starts_of(id) - before


## The numbers of a boss: the object of its own name in its record.
func _boss_numbers(boss_id: String) -> Dictionary:
	return GameData.as_dict(_data.record("bosses", boss_id).get(boss_id))


## A boss by itself with nothing of its plan on the road: the car in the
## gear of par in the middle lane, at the start of its road.
func _quiet_boss(boss_id: String) -> DriveSim:
	var sim: DriveSim = DriveSim.new(_data)
	var plan: Dictionary = BossSim.plan(_data, boss_id, "", BOSS_SEED)
	for key: String in ["spawns", "hazards", "curves"]:
		plan[key] = []
	sim.gate.reset(PAR_GEAR)
	sim.begin_leg(plan)
	sim.in_encounter = true
	sim.drain_events()
	return sim


## Dawn from quiet, set down a little short of where the phone in his pocket
## begins to ring and driven until it does. Null (and a failure) when it
## does not ring.
func _to_the_call() -> DriveSim:
	var from_end: float = GameData.as_float(GameData.as_dict(_boss_numbers(BossSim.DAWN).get("call")).get("from_end_m"))
	var sim: DriveSim = _quiet_boss(BossSim.DAWN)
	sim.car.s = GameData.as_float(_data.record("bosses", BossSim.DAWN).get("length_m")) - from_end - CALL_RUN_UP
	_rest()
	var guard: int = roundi(5.0 * FPS)
	while sim.boss.call != BossSim.CALL_RINGING and guard > 0:
		guard -= 1
		_drive(sim, STEP)
	if not _expect(sim.boss.call == BossSim.CALL_RINGING, "the Call: the phone in his pocket does not ring %.0f m from Dawn's end; its ring was not checked" % from_end):
		return null
	return sim


## The Storm from quiet, his car standing dark in its lane with the brake
## held (`brake` is made that input), driven until something comes up behind
## it. Null (and a failure) when nothing comes in STORM_WAITS waits.
func _stand_in_the_storm(brake: DriveInput) -> DriveSim:
	var every: float = GameData.as_float(_boss_numbers(BossSim.STORM).get("rear_end_every_s"))
	var sim: DriveSim = _quiet_boss(BossSim.STORM)
	sim.rng.reseed(BOSS_SEED)
	sim.car.speed = 0.0
	brake.clear()
	brake.rmb = true
	_rest()
	var guard: int = roundi(every * float(STORM_WAITS) * FPS)
	while sim.boss.rear_end_in <= 0.0 and guard > 0:
		guard -= 1
		_drive(sim, STEP, brake)
	if not _expect(sim.boss.rear_end_in > 0.0, "the Storm: nothing came up behind a car standing dark in its lane for %.0f s; its horn was not checked" % (every * float(STORM_WAITS))):
		return null
	return sim


## A simulation driven as the drive scene drives it: two ticks a frame, its
## events onto the bus, its snapshot to Audio. The car is kept in its lane.
## `input` is what the player does meanwhile (nothing, if it is not given).
func _drive(sim: DriveSim, seconds: float, input: DriveInput = null) -> void:
	if input == null:
		input = DriveInput.new()
	for frame: int in roundi(seconds * FPS):
		for tick: int in roundi(STEP / DriveSim.DT):
			sim.car.x = sim.car.lane_center(clampi(sim.car.lane_of(sim.car.x), 0, sim.car.lanes - 1))
			sim.step(input)
			for event: Dictionary in sim.drain_events():
				Events.emit_event(GameData.as_string(event.get("type")), event)
		Audio.advance(STEP)
		Audio.apply(sim.snapshot())


# --- Helpers -----------------------------------------------------------------

func _synth(id: String) -> Dictionary:
	return GameData.as_dict(GameData.as_dict(_data.root("sfx").get(id)).get("synth"))


func _expect(condition: bool, failure: String) -> bool:
	checks += 1
	if not condition:
		_failures.append(failure)
	return condition


func _fail(failure: String) -> void:
	checks += 1
	_failures.append(failure)
