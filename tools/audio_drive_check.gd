extends RefCounted
## The second half of the sound check (tools/audio_check.gd): the Audio
## autoload, taken through the states of a drive and the events of the bus.
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
		_check_hum()
		_check_horn()
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
	_run(_snap({"speed": _tuning.fi("gear_speeds", 2), "radio": ItemSim.MUSIC, "pound": true, "nerves": _tuning.f("snap_at")}), 1.0)
	_expect(Audio.is_sounding(Audio.ENGINE) and Audio.is_sounding(Audio.RADIO % String(ItemSim.MUSIC)), "the drive is not heard")
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


## A simulation driven as the drive scene drives it: two ticks a frame, its
## events onto the bus, its snapshot to Audio. The car is kept in its lane.
func _drive(sim: DriveSim, seconds: float) -> void:
	var input: DriveInput = DriveInput.new()
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
