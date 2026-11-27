class_name DebugHud
extends CanvasLayer
## The numeric HUD (GDD 13.9, F1; also a setting, GDD 17.1). The game shows
## its state through the cabin, post effects and sound; this is for tuning
## and for players who ask for numbers. Reads the snapshot; changes nothing.

var _label: Label


func _ready() -> void:
	_label = Label.new()
	_label.position = Vector2(24.0, 24.0)
	add_child(_label)
	visible = false


func toggle() -> void:
	visible = not visible


func apply(snapshot: Dictionary) -> void:
	if not visible:
		return
	var gear: int = snapshot["gear"]
	var gear_text: String = Lines.get_text("hud.neutral") if gear == GearGate.NEUTRAL else str(gear)
	var wheel_angle: float = snapshot["wheel_angle"]
	var hand_text: String = str(snapshot["hand_at"])
	if snapshot["hand_gripping"]:
		hand_text = Lines.get_text("hud.hand.wheel")
	elif hand_text.is_empty():
		hand_text = Lines.get_text("hud.hand.free")
	var cam_yaw: float = snapshot["cam_yaw"]
	var cam_pitch: float = snapshot["cam_pitch"]
	var nerves: float = snapshot["nerves"]
	var floor_level: float = snapshot["heavy_floor"]
	var speed: float = snapshot["speed"]
	var cash: float = snapshot["cash"]
	var fault_names: PackedStringArray = []
	var faults: Array[StringName] = snapshot["faults"]
	for fault: StringName in faults:
		fault_names.append(String(fault))
	var effect_names: PackedStringArray = []
	var effects: Array[StringName] = snapshot["effects"]
	for effect: StringName in effects:
		effect_names.append(String(effect))
	if effect_names.is_empty():
		effect_names.append(Lines.get_text("hud.none"))
	var rows: PackedStringArray = [
		Lines.format("hud.nerves", ["%.1f" % nerves, "%.0f" % floor_level]),
		Lines.format("hud.lamps", [str(snapshot["lamps"]), str(snapshot["lamp_capacity"]), " ".join(fault_names)]),
		Lines.format("hud.cash", ["%.1f" % cash]),
		Lines.format("hud.gear", [gear_text]),
		Lines.format("hud.speed", ["%.0f" % speed]),
		Lines.format("hud.wheel", ["%.1f" % wheel_angle]),
		Lines.format("hud.hand", [hand_text]),
		Lines.format("hud.eyes", ["%.1f" % cam_yaw, "%.1f" % cam_pitch]),
		Lines.format("hud.radio", [str(snapshot["radio"])]),
		Lines.format("hud.effects", [", ".join(effect_names)]),
		Lines.format("hud.tick", [str(snapshot["tick"])]),
	]
	rows.append(Lines.format("hud.clock", [str(snapshot["clock"])]))
	if snapshot["telling"]:
		var legs_done: int = snapshot["legs_done"]
		rows.append(Lines.format("hud.telling", [str(snapshot["act"]), str(legs_done + 1), Lines.get_text("stage.%s" % str(snapshot["stage"]))]))
	if snapshot["stopped"]:
		rows.append(Lines.format("hud.stop", [Lines.get_text("stop.%s.name" % str(snapshot["stop"]))]))
	if snapshot["wrecked"]:
		rows.append(Lines.get_text("hud.wrecked"))
	if snapshot["leg_active"]:
		var leg_time: float = snapshot["leg_time"]
		var leg_par: float = snapshot["leg_par"]
		rows.append(Lines.format("hud.leg", [str(snapshot["leg"]), "%.0f" % leg_time, "%.0f" % leg_par]))
	if snapshot["suspicion_watching"]:
		var suspicion: float = snapshot["suspicion"]
		rows.append(Lines.format("hud.suspicion", ["%.0f" % suspicion]))
	var sight: float = snapshot["visibility"]
	if is_finite(sight):
		rows.append(Lines.format("hud.sight", ["%.0f" % sight]))
	var glare: float = snapshot["glare"]
	if glare > 0.0:
		rows.append(Lines.format("hud.glare", ["%.0f" % (glare * 100.0)]))
	var rain_blur: float = snapshot["rain_blur"]
	var haze: float = snapshot["haze"]
	if rain_blur > 0.0 or haze > 0.0:
		rows.append(Lines.format("hud.blur", ["%.2f" % rain_blur, "%.2f" % haze]))
	if snapshot["eyes_shut"]:
		rows.append(Lines.get_text("hud.eyes_shut"))
	var courage: int = snapshot["courage"]
	var lag: float = snapshot["lag"]
	if courage > 0 or lag > 0.0:
		var sway: float = snapshot["sway"]
		rows.append(Lines.format("hud.courage", [str(courage), "%.2f" % sway, "%.0f" % (lag * 1000.0)]))
	# Noor's call has a row of its own, with the set pieces.
	if str(snapshot["mount_caller"]) != "":
		# The phone on its mount (Noor's call has a row of its own).
		var ring_left: float = snapshot["mount_ring_left"]
		rows.append(Lines.format("hud.call", [Lines.get_text("call.%s" % str(snapshot["mount_caller"])), "%.1f" % ring_left, str(snapshot["call_taps"])]))
	if str(snapshot["hook"]) != "":
		rows.append(Lines.format("hud.hook", [Lines.get_text("hook.%s" % str(snapshot["hook"]))]))
	if str(snapshot["cramp"]) != "":
		rows.append(Lines.get_text("hud.cramp.%s" % str(snapshot["cramp"])))
	if str(snapshot["ghost_at"]) != "":
		rows.append(Lines.get_text("hud.ghost"))
	if str(snapshot["heckle"]) != "":
		# What the Table has just said, and how he is doing with it.
		var heckle_left: float = snapshot["heckle_left"]
		var heckle_progress: float = snapshot["heckle_progress"]
		rows.append(Lines.format("hud.heckle", [Lines.get_text("hud.heckle.%s" % str(snapshot["heckle_type"]).to_lower()),
				Lines.get_text("hud.heckle.%s" % str(snapshot["heckle_phase"])), "%.1f" % heckle_left, "%.0f" % (heckle_progress * 100.0)]))
	if snapshot["ghost_hand"]:
		rows.append(Lines.get_text("hud.ghost_hand"))
	if str(snapshot["carrying"]) != "":
		rows.append(Lines.format("hud.carrying", [str(snapshot["carrying"])]))
	_add_passenger_rows(snapshot, rows)
	_add_set_piece_rows(snapshot, rows)
	_label.text = "\n".join(rows)


## Who rides, how far, and what they are doing; who stands at the roadside.
func _add_passenger_rows(snapshot: Dictionary, rows: PackedStringArray) -> void:
	var who: String = str(snapshot["passenger"])
	if not who.is_empty():
		var doing: String = ""
		var awake_left: float = snapshot["passenger_awake_left"]
		var held_left: float = snapshot["wheel_held_left"]
		var repair_left: float = snapshot["passenger_repair_left"]
		var repair: int = snapshot["passenger_repair"]
		var held: int = snapshot["wheel_held"]
		if snapshot["passenger_asleep"]:
			doing += Lines.get_text("hud.passenger.asleep")
		elif awake_left > 0.0:
			doing += Lines.format("hud.passenger.awake", ["%.1f" % awake_left])
		if snapshot["passenger_drumming"]:
			doing += Lines.get_text("hud.passenger.drumming")
		elif snapshot["tea_passed"]:
			doing += Lines.get_text("hud.passenger.tea")
		if held != PassengerSim.HOLD_NONE:
			doing += Lines.format("hud.passenger.holds", ["%.1f" % held_left])
		if repair == PassengerSim.REPAIR_ANNOUNCED:
			doing += Lines.format("hud.passenger.warns", ["%.1f" % repair_left])
		elif repair == PassengerSim.REPAIR_LEANING:
			doing += Lines.format("hud.passenger.leans", ["%.1f" % repair_left])
		rows.append(Lines.format("hud.passenger", [Lines.get_text("passenger.%s.name" % who), str(snapshot["passenger_legs"]), doing]))
	var hitcher: String = str(snapshot["hitcher"])
	if not hitcher.is_empty():
		rows.append(Lines.format("hud.hitcher", [Lines.get_text("passenger.%s.name" % hitcher)]))
	if snapshot["blessed"]:
		rows.append(Lines.get_text("hud.blessed"))


## The set pieces (GDD 10.2 to 10.5): which boss, and what it is doing.
func _add_set_piece_rows(snapshot: Dictionary, rows: PackedStringArray) -> void:
	var boss: String = str(snapshot["boss"])
	var boss_time: float = snapshot["boss_time"]
	if snapshot["leg_active"] and Lines.has_line("boss.%s.name" % boss) and (boss_time > 0.0 or not snapshot["telling"]):
		var modifier: String = str(snapshot["boss_modifier"])
		rows.append(Lines.format("hud.boss", [Lines.get_text("boss.%s.name" % boss),
				" " + Lines.get_text("sign.boss_modifier.%s" % modifier) if not modifier.is_empty() else "", "%.0f" % boss_time]))
	var dust_change_in: float = snapshot["dust_change_in"]
	if dust_change_in > 0.0:
		rows.append(Lines.format("hud.dust", [Lines.get_text("hud.dust.thick" if snapshot["dust_thick"] else "hud.dust.thin"), "%.1f" % dust_change_in]))
	var rear_end_in: float = snapshot["rear_end_in"]
	if rear_end_in > 0.0:
		rows.append(Lines.format("hud.rear_end", ["%.1f" % rear_end_in]))
	var dawn_phase: int = snapshot["dawn_phase"]
	if dawn_phase > 0:
		rows.append(Lines.format("hud.dawn", [Lines.get_text("hud.dawn.%d" % dawn_phase)]))
	var call: String = str(snapshot["call"])
	var call_left: float = snapshot["call_left"]
	match call:
		BossSim.CALL_RINGING:
			rows.append(Lines.format("hud.the_call", [Lines.format("hud.the_call.ringing", ["%.1f" % call_left])]))
		BossSim.CALL_TALKING:
			rows.append(Lines.format("hud.the_call", [Lines.format("hud.the_call.talking", ["%.1f" % call_left, str(snapshot["call_taken"])])]))
		BossSim.CALL_OVER:
			rows.append(Lines.format("hud.the_call", [Lines.get_text("hud.the_call.over")]))
	var checkpoint_phase: int = snapshot["checkpoint_phase"]
	match checkpoint_phase:
		BossSim.QUEUE:
			rows.append(Lines.get_text("hud.checkpoint.queue"))
		BossSim.STOW:
			var stow_left: float = snapshot["stow_left"]
			rows.append(Lines.format("hud.checkpoint.stow", ["%.1f" % stow_left]))
		BossSim.PAPERS:
			var papers_delay: float = snapshot["papers_delay"]
			var wanted: String = str(snapshot["wanted"])
			rows.append(Lines.format("hud.checkpoint.papers", [Lines.get_text("sign.document.%s" % wanted) if not wanted.is_empty() else "", "%.1f" % papers_delay]))
		BossSim.THROUGH:
			rows.append(Lines.get_text("hud.checkpoint.passed"))
	var bay: Vector2 = snapshot["bay"]
	if bay.y > bay.x:
		if snapshot["in_bay"]:
			rows.append(Lines.get_text("hud.bay"))
		else:
			var car_s: float = snapshot["car_s"]
			rows.append(Lines.format("hud.arrival", ["%.0f" % maxf(bay.x - car_s, 0.0)]))
