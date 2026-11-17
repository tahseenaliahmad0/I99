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
	if str(snapshot["caller"]) != "":
		var ring_left: float = snapshot["ring_left"]
		rows.append(Lines.format("hud.call", [Lines.get_text("call.%s" % str(snapshot["caller"])), "%.1f" % ring_left, str(snapshot["call_taps"])]))
	if str(snapshot["hook"]) != "":
		rows.append(Lines.format("hud.hook", [Lines.get_text("hook.%s" % str(snapshot["hook"]))]))
	if str(snapshot["cramp"]) != "":
		rows.append(Lines.get_text("hud.cramp.%s" % str(snapshot["cramp"])))
	if str(snapshot["ghost_at"]) != "":
		rows.append(Lines.get_text("hud.ghost"))
	if str(snapshot["carrying"]) != "":
		rows.append(Lines.format("hud.carrying", [str(snapshot["carrying"])]))
	_label.text = "\n".join(rows)
