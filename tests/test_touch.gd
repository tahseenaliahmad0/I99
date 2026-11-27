extends CabinSuite
## M12: touch (GDD 4.1, 17.4) and the export presets. T-TOUCH-01. How a
## thumb is read is D-069.

const KMH: float = 1.0 / 3.6
## A phone, a tablet and a desk: the view in px and its dots per inch.
const SCREENS: Array[Array] = [[2556.0, 1179.0, 460.0], [2048.0, 1536.0, 264.0], [1920.0, 1080.0, 96.0]]
const VIEW: Vector2 = Vector2(1920.0, 1080.0)
const DPI: float = 160.0
const THUMB: int = 0
const OTHER_THUMB: int = 1

var _touch: TouchInput


# --- Helpers -------------------------------------------------------------------

## A new night on a quiet road, to be played by touch.
func _by_touch() -> void:
	_new_sim()
	_sim.heckling = false
	_sim.begin_telling(TABLE, 3)
	_into_next_quiet_leg()
	_touch = TouchInput.new(tuning)
	_events = []
	_keep_lane = true


## One tick with the fingers as they are.
func _touch_tick() -> void:
	_input.clear()
	_touch.apply(_sim, _input)
	_tick()


func _touch_ticks(seconds: float) -> void:
	for _index: int in _ticks_in(seconds):
		_touch_tick()


## Where a finger has to be on the glass for a pointer: anywhere that is
## neither the pedal zone nor the hotspot.
func _on_the_glass() -> Vector2:
	return VIEW * 0.6


func _thumb_down_at(pointer: Vector2) -> void:
	_touch.finger_down(THUMB, _on_the_glass(), pointer, VIEW, DPI)


func _thumb_down_on(anchor: String) -> void:
	_thumb_down_at(_sim.hand.anchor_pointer(_sim.hand.anchor_index(StringName(anchor))))


func _thumb_up() -> void:
	_touch.finger_up(THUMB)


func _wheel() -> Vector2:
	return _sim.space.point_to_pointer(_sim.space.grip_reference)


## A tap: the thumb down on an anchor and up again `seconds` later.
func _tap_on(anchor: String, seconds: float = 0.08) -> void:
	_thumb_down_on(anchor)
	_touch_ticks(seconds)
	_thumb_up()


# --- T-TOUCH-01 ----------------------------------------------------------------

## T-TOUCH-01: Touch of 4.1 and 17.4: the right thumb is the hand and lifting
## it lets go; TAP rituals perform automatically when the hand arrives while
## HOLD, DRAG and CRANK need the gesture; the brake is a pedal zone at the
## bottom left; tap targets are at least 9 mm across; export presets exist
## for Windows, Linux, macOS and iOS.
func test_touch_01() -> void:
	_check_the_thumb_is_the_hand()
	_check_a_tap_performs_on_arrival()
	_check_the_gestures_need_the_thumb()
	_check_the_pedal_zone()
	_check_tap_targets()
	_check_the_scene_takes_touches()
	_check_export_presets()


## The thumb on the wheel grips it; dragged, it steers; lifted, it lets go.
func _check_the_thumb_is_the_hand() -> void:
	_by_touch()
	check(not _touch.active, "(before the first finger nothing is touch)")
	_touch_ticks(0.5)
	check(not _sim.hand.gripping, "with no finger on the glass no hand is on the wheel")
	_thumb_down_at(_wheel())
	check(_touch.active, "a finger on the glass: he plays by touch")
	_touch_ticks(1.0)
	check(_sim.hand.gripping, "GDD 4.1: the thumb held on the wheel grips it")
	# Dragged right, then left.
	var angle: float = _sim.wheel.angle
	for _index: int in _ticks_in(0.3):
		_touch.finger_moved(THUMB, _on_the_glass(), _wheel(), Vector2(3.0, 0.0))
		_touch_tick()
	check(_sim.wheel.angle > angle + 5.0, "dragged right, the wheel turns right (%.0f degrees)" % (_sim.wheel.angle - angle))
	angle = _sim.wheel.angle
	for _index: int in _ticks_in(0.3):
		_touch.finger_moved(THUMB, _on_the_glass(), _wheel(), Vector2(-3.0, 0.0))
		_touch_tick()
	check(_sim.wheel.angle < angle - 5.0, "dragged left, it turns left")
	check(_sim.hand.gripping, "(and the thumb still has it)")
	_thumb_up()
	_touch_ticks(0.1)
	check(not _sim.hand.gripping, "GDD 17.4: lifting the thumb is letting go")
	# The pointer goes where the thumb comes down, and the hand after it.
	_thumb_down_on("horn")
	_touch_ticks(0.02)
	check_eq(_sim.hand.snap_id(), &"horn", "the thumb down on the horn: the pointer is on the horn")
	_thumb_up()


## GDD 17.4: "TAP rituals perform automatically when the hand arrives."
func _check_a_tap_performs_on_arrival() -> void:
	check_eq(GameData.as_string(_ritual("horn").get("gesture")), "TAP", "(the horn is a TAP)")
	_by_touch()
	_thumb_down_at(_wheel())
	_touch_ticks(1.0)
	_thumb_up()
	_touch_ticks(0.1)
	_events = []
	# A TAP that is further from the wheel than a mouse's press is kept for
	# (input_buffer): the glovebox, across the cabin.
	check_eq(GameData.as_string(_ritual("glovebox_toggle").get("gesture")), "TAP", "(and so is the glovebox's lid)")
	var reach: float = _reach_time("glovebox")
	check(reach > tuning.f("input_buffer") + 0.1, "(the glovebox is %.2f s from the wheel: more than the %.2f s a press is kept for)" % [reach, tuning.f("input_buffer")])
	_by_touch()
	_sim.hand.place_at(_sim.space.grip_reference)
	check(not _sim.items.flag(ItemSim.FLAG_GLOVEBOX), "(the glovebox is shut)")
	var tapped_at: int = _sim.tick
	_tap_on("glovebox")
	check(not _sim.items.flag(ItemSim.FLAG_GLOVEBOX) and _sim.hand.at_id() != &"glovebox", "a tap on the glovebox: the thumb is up again before the hand is there")
	var guard: int = _ticks_in(3.0)
	while not _sim.items.flag(ItemSim.FLAG_GLOVEBOX) and guard > 0:
		guard -= 1
		_touch_tick()
	check(_sim.items.flag(ItemSim.FLAG_GLOVEBOX), "the hand arrives and opens it, with no thumb on the glass (%.2f s after the tap)" % (float(_sim.tick - tapped_at) * DT))
	check_eq(_count_events("ritual_completed", "ritual", "glovebox_toggle"), 1, "one TAP")
	_touch_ticks(1.0)
	check_eq(_count_events("ritual_completed", "ritual", "glovebox_toggle"), 1, "and no more, however long the hand rests there")
	check(_sim.items.flag(ItemSim.FLAG_GLOVEBOX), "(it stays open)")
	# The same press and release from a mouse, that long before the hand is
	# there, is no TAP at all.
	_new_sim()
	_sim.heckling = false
	_sim.begin_telling(TABLE, 3)
	_into_next_quiet_leg()
	_sim.hand.place_at(_sim.space.grip_reference)
	_events = []
	_input.clear()
	_input.pointer_is_absolute = true
	_input.pointer = _sim.hand.anchor_pointer(_sim.hand.anchor_index(&"glovebox"))
	_input.lmb = true
	_ticks(_ticks_in(0.08))
	_input.lmb = false
	_ticks(_ticks_in(3.0))
	check(not _sim.items.flag(ItemSim.FLAG_GLOVEBOX), "(a mouse button let go that long before the hand arrives opens nothing)")
	# A tap on one thing and then on another: only the second is done.
	_by_touch()
	_tap_on("face", 0.03)
	_tap_on("horn", 0.03)
	_touch_ticks(2.5)
	check_eq(_count_events("ritual_completed", "ritual", "slap"), 0, "a tap on his face, then one on the horn before the hand is there: no slap")
	check_eq(_count_events("ritual_completed", "ritual", "horn"), 1, "the horn")


## GDD 17.4: "HOLD, DRAG and CRANK need the gesture."
func _check_the_gestures_need_the_thumb() -> void:
	var tea: String = _anchor_of("tea_glass")
	var hold: float = GameData.as_float(_ritual("tea_sip").get("hold_s"))
	check_eq(GameData.as_string(_ritual("tea_sip").get("gesture")), "HOLD", "(a sip of tea is a HOLD)")
	# HOLD: a tap does nothing; the thumb held does it, from when the hand is there.
	_by_touch()
	_tap_on(tea)
	_touch_ticks(3.0)
	check_eq(_count_events("ritual_completed", "ritual", "tea_sip"), 0, "a tap on the tea glass is no sip: a HOLD needs the thumb")
	_thumb_down_on(tea)
	var guard: int = _ticks_in(3.0)
	while _sim.hand.at_id() != StringName(tea) and guard > 0:
		guard -= 1
		_touch_tick()
	check_eq(_count_events("ritual_completed", "ritual", "tea_sip"), 0, "the thumb held on it: nothing yet when the hand arrives")
	_touch_ticks(hold * 0.5)
	check_eq(_count_events("ritual_completed", "ritual", "tea_sip"), 0, "nor half the hold later")
	_touch_ticks(hold * 0.5 + 0.1)
	check_eq(_count_events("ritual_completed", "ritual", "tea_sip"), 1, "held for hold_s from there: a sip")
	_thumb_up()
	# Lifted too soon, no sip.
	_by_touch()
	_thumb_down_on(tea)
	guard = _ticks_in(3.0)
	while _sim.hand.at_id() != StringName(tea) and guard > 0:
		guard -= 1
		_touch_tick()
	_touch_ticks(hold * 0.5)
	_thumb_up()
	_touch_ticks(1.0)
	check_eq(_count_events("ritual_completed", "ritual", "tea_sip"), 0, "the thumb lifted half way through the hold: no sip")

	# DRAG: the radio's dial, the thumb dragged sideways.
	check_eq(GameData.as_string(_ritual("radio_tune").get("gesture")), "DRAG", "(the radio's dial is a DRAG)")
	_by_touch()
	var station: StringName = _sim.items.radio
	_tap_on("radio")
	_touch_ticks(2.0)
	check_eq(_sim.items.radio, station, "a tap on the radio tunes nothing")
	_thumb_down_on("radio")
	guard = _ticks_in(3.0)
	while _sim.hand.at_id() != &"radio" and guard > 0:
		guard -= 1
		_touch_tick()
	_touch_ticks(0.05)
	var radio_at: Vector2 = _sim.hand.anchor_pointer(_sim.hand.anchor_index(&"radio"))
	var step_px: float = tuning.f("radio_step_px")
	for _index: int in 10:
		_touch.finger_moved(THUMB, _on_the_glass(), radio_at, Vector2(step_px * 0.13, 0.0))
		_touch_tick()
	_thumb_up()
	_touch_ticks(0.3)
	check(_sim.items.radio != station, "the thumb held on it and dragged sideways: another station (%s)" % _sim.items.radio)

	# CRANK: the window, the thumb led round.
	check_eq(GameData.as_string(_ritual("window_crank").get("gesture")), "CRANK", "(the window's crank is a CRANK)")
	_by_touch()
	check(not _sim.items.flag(ItemSim.FLAG_WINDOW), "(the window is shut)")
	_tap_on("window_crank")
	_touch_ticks(2.5)
	check(not _sim.items.flag(ItemSim.FLAG_WINDOW), "a tap on the crank winds nothing")
	_thumb_down_on("window_crank")
	guard = _ticks_in(3.0)
	while _sim.hand.at_id() != &"window_crank" and guard > 0:
		guard -= 1
		_touch_tick()
	_touch_ticks(0.05)
	var crank_at: Vector2 = _sim.hand.anchor_pointer(_sim.hand.anchor_index(&"window_crank"))
	var heading: float = 0.0
	guard = _ticks_in(4.0)
	while not _sim.items.flag(ItemSim.FLAG_WINDOW) and guard > 0:
		guard -= 1
		heading += deg_to_rad(12.0)
		_touch.finger_moved(THUMB, _on_the_glass(), crank_at, Vector2(cos(heading), sin(heading)) * 6.5)
		_touch_tick()
	check(_sim.items.flag(ItemSim.FLAG_WINDOW), "the thumb held on it and led round: the window is down")
	_thumb_up()
	# From across the cabin, further than a mouse's press is kept for: the
	# press is made when the hand gets there, because the thumb is still down.
	_by_touch()
	_sim.hand.place_at(_sim.hand.anchor_position(_sim.hand.anchor_index(&"glovebox")))
	_touch_tick()
	var from_tick: int = _sim.tick
	_thumb_down_on("window_crank")
	guard = _ticks_in(4.0)
	while _sim.hand.at_id() != &"window_crank" and guard > 0:
		guard -= 1
		_touch_tick()
	var way: float = float(_sim.tick - from_tick) * DT
	check(way > tuning.f("input_buffer") + 0.1, "(from the glovebox the crank is %.2f s away: more than the %.2f s a press is kept for)" % [way, tuning.f("input_buffer")])
	_touch_ticks(0.05)
	crank_at = _sim.hand.anchor_pointer(_sim.hand.anchor_index(&"window_crank"))
	heading = 0.0
	guard = _ticks_in(4.0)
	while not _sim.items.flag(ItemSim.FLAG_WINDOW) and guard > 0:
		guard -= 1
		heading += deg_to_rad(12.0)
		_touch.finger_moved(THUMB, _on_the_glass(), crank_at, Vector2(cos(heading), sin(heading)) * 6.5)
		_touch_tick()
	check(_sim.items.flag(ItemSim.FLAG_WINDOW), "the thumb down all the way there: the hand takes the crank when it arrives, and winds")
	_thumb_up()


## GDD 17.4: "The brake is a pedal zone at the bottom left for the left thumb."
func _check_the_pedal_zone() -> void:
	_by_touch()
	var zone: Rect2 = _touch.pedal_zone(VIEW, DPI)
	check_near(zone.position.x, 0.0, 0.001, "the pedal zone is at the left edge")
	check_near(zone.end.y, VIEW.y, 0.001, "and at the bottom")
	check(zone.end.x <= VIEW.x * 0.5 and zone.position.y >= VIEW.y * 0.5, "within the bottom left quarter of the glass")
	_cruise(3, 1)
	_thumb_down_at(_wheel())
	_touch_ticks(1.0)
	var speed: float = _sim.car.speed
	check(_sim.hand.gripping and not _touch.braking(), "(his right thumb is on the wheel)")
	_touch.finger_down(OTHER_THUMB, zone.get_center(), Vector2.ZERO, VIEW, DPI)
	check(_touch.braking(), "a second thumb on the pedal zone is his foot on the brake")
	_touch_ticks(1.0)
	check_near(speed - _sim.car.speed, tuning.f("brake_decel"), 1.0, "held for a second, the car is brake_decel slower")
	check(_sim.hand.gripping, "and the hand is where it was: the wheel")
	_touch.finger_up(OTHER_THUMB)
	speed = _sim.car.speed
	_touch_ticks(0.5)
	check(not _touch.braking() and _sim.car.speed > speed, "lifted, the brake is off")
	# A finger just outside the zone is no foot.
	_by_touch()
	_touch.finger_down(OTHER_THUMB, Vector2(zone.end.x + 5.0, zone.get_center().y), _wheel(), VIEW, DPI)
	check(not _touch.braking(), "a finger beside the pedal zone is not on the brake")
	# The hotspot (GDD 4.1): a tap in the top-left corner asks for the pause.
	_by_touch()
	var hotspot: Rect2 = _touch.hotspot(VIEW, DPI)
	check_eq(hotspot.position, Vector2.ZERO, "GDD 4.1: the pause's hotspot is the top-left corner")
	_touch.finger_down(THUMB, hotspot.get_center(), Vector2.ZERO, VIEW, DPI)
	check(_touch.take_pause(), "a tap on it asks for the pause")
	check(not _touch.take_pause(), "once")
	_touch.finger_up(THUMB)
	_touch_tick()
	check(not _input.lmb and not _input.rmb, "and is neither the hand nor the foot")


## GDD 17.4: "Tap targets are at least 9 mm across, even where the drawn
## object is smaller."
func _check_tap_targets() -> void:
	check_near(tuning.f("touch_target_mm"), 9.0, 0.000001, "GDD 17.4: 9 mm")
	_touch = TouchInput.new(tuning)
	for screen: Array in SCREENS:
		var view: Vector2 = Vector2(GameData.as_float(screen[0]), GameData.as_float(screen[1]))
		var dpi: float = GameData.as_float(screen[2])
		var mm_per_px: float = TouchInput.MM_PER_INCH / dpi
		var name: String = "%dx%d at %d dpi" % [roundi(view.x), roundi(view.y), roundi(dpi)]
		# An anchor: its snap radius, which is in reference px, on this glass.
		var radius_px: float = _touch.snap_radius(view, dpi) * view.y / tuning.f("reference_height")
		check(2.0 * radius_px * mm_per_px >= 9.0 - 0.001, "%s: an anchor is a target %.1f mm across" % [name, 2.0 * radius_px * mm_per_px])
		check(_touch.snap_radius(view, dpi) >= tuning.f("anchor_snap_radius") - 0.001, "%s: and never smaller than the pointer's own snap radius" % name)
		var zone: Rect2 = _touch.pedal_zone(view, dpi)
		check(zone.size.x * mm_per_px >= 9.0 - 0.001 and zone.size.y * mm_per_px >= 9.0 - 0.001, "%s: the pedal zone is %.0f by %.0f mm" % [name, zone.size.x * mm_per_px, zone.size.y * mm_per_px])
		var hotspot: Rect2 = _touch.hotspot(view, dpi)
		check(hotspot.size.x * mm_per_px >= 9.0 - 0.001 and hotspot.size.y * mm_per_px >= 9.0 - 0.001, "%s: the hotspot is %.1f mm square" % [name, hotspot.size.x * mm_per_px])
		check(not zone.intersects(hotspot), "%s: and the two do not overlap" % name)
	# The simulation takes the wider snap: a thumb that comes down beyond the
	# pointer's radius and within the thumb's still means the anchor.
	_by_touch()
	var phone: Vector2 = Vector2(2556.0, 1179.0)
	var wide: float = _touch.snap_radius(phone, 460.0)
	check(wide > tuning.f("anchor_snap_radius") + 5.0, "(on a phone the 9 mm are wider than the pointer's snap radius: %.0f reference px)" % wide)
	var horn: Vector2 = _sim.hand.anchor_pointer(_sim.hand.anchor_index(&"horn"))
	var away: float = (tuning.f("anchor_snap_radius") + wide) * 0.5
	var beside: Vector2 = Vector2.INF
	for step: int in 16:
		var at: Vector2 = horn + Vector2.from_angle(TAU * float(step) / 16.0) * away
		var nearest: float = INF
		for index: int in _sim.hand.anchor_count():
			if _sim.hand.anchor_id(index) != &"horn" and _sim.hand.is_anchor_active(index):
				nearest = minf(nearest, at.distance_to(_sim.hand.anchor_pointer(index)))
		if nearest > wide + 1.0 and not _sim.space.pointer_on_rim(at):
			beside = at
			break
	if check(beside != Vector2.INF, "(a place %.0f px from the horn with no other anchor nearer)" % away):
		_sim.hand.set_snap_radius(tuning.f("anchor_snap_radius"))
		_input.clear()
		_input.pointer_is_absolute = true
		_input.pointer = beside
		_tick()
		var with_pointer: StringName = _sim.hand.snap_id()
		_sim.hand.set_snap_radius(wide)
		_tick()
		check(with_pointer != &"horn" and _sim.hand.snap_id() == &"horn", "a thumb down between the two radii from the horn means the horn by touch, and not by mouse")


## The drive scene takes fingers: a headless build is touched and says what
## happened (tools/touch_walk.gd).
func _check_the_scene_takes_touches() -> void:
	var captured: Array = []
	var args: PackedStringArray = ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--fixed-fps", "60", "--script", "res://tools/touch_walk.gd"]
	var exit_code: int = OS.execute(OS.get_executable_path(), args, captured, true)
	var output: String = ""
	for chunk: Variant in captured:
		output += str(chunk)
	output = Smoke.strip_ansi(output)
	var failed: PackedStringArray = []
	var errors: PackedStringArray = []
	var steps: int = 0
	for raw: String in output.split("\n"):
		var line: String = raw.strip_edges()
		if line.begins_with("TOUCH ok:"):
			steps += 1
		elif line.begins_with("TOUCH FAIL:"):
			failed.append(line)
		for prefix: String in Smoke.ERROR_PREFIXES:
			if line.begins_with(prefix):
				errors.append(line)
	check_eq(exit_code, 0, "the drive scene played with fingers alone ends well")
	check(output.contains("TOUCH DONE"), "it reaches its end")
	check(failed.is_empty(), "no step of it fails; first: %s" % ("(none)" if failed.is_empty() else failed[0]))
	check(errors.is_empty(), "with no error output; first: %s" % ("(none)" if errors.is_empty() else errors[0]))
	for what: String in ["a thumb on the wheel: the hand has it", "lifted: the hand lets go", "a thumb on the pedal zone: the car slows", "a tap on the hotspot: the night waits"]:
		check(output.contains(what), "the scene: %s" % what)
	check(steps >= 4, "(%d steps)" % steps)
	check_eq(GameData.as_int(ProjectSettings.get_setting("display/window/handheld/orientation")), int(DisplayServer.SCREEN_SENSOR_LANDSCAPE), "GDD 17.4: landscape only")


## GDD 18, D-016: export presets for Windows, Linux, macOS and iOS.
func _check_export_presets() -> void:
	var presets: ConfigFile = ConfigFile.new()
	if not check_eq(presets.load("res://export_presets.cfg"), OK, "export_presets.cfg is there"):
		return
	var platforms: Dictionary = {}
	for section: String in presets.get_sections():
		if section.begins_with("preset.") and not section.ends_with(".options"):
			platforms[GameData.as_string(presets.get_value(section, "platform"))] = section
	for platform: String in ["Windows Desktop", "Linux", "macOS", "iOS"]:
		if not check(platforms.has(platform), "there is an export preset for %s" % platform):
			continue
		var section: String = GameData.as_string(platforms[platform])
		check(not GameData.as_string(presets.get_value(section, "export_path", "")).is_empty(), "%s: with a place to export to" % platform)
		check(GameData.as_string(presets.get_value(section, "include_filter", "")).contains("data/*.json"), "%s: the data files go with it" % platform)
		check(GameData.as_string(presets.get_value(section, "exclude_filter", "")).contains("tests/*"), "%s: the tests do not" % platform)
		check(presets.has_section(section + ".options"), "%s: and its options" % platform)
	check_eq(platforms.size(), 4, "four presets")
