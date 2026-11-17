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
	if snapshot["eyes_shut"]:
		rows.append(Lines.get_text("hud.eyes_shut"))
	_label.text = "\n".join(rows)
