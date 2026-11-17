extends Control
## BOOT (GDD 13.4): the first scene. It reports that the autoloads and the
## data are up, and shows the game's name from the line database.

var _label: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.text = Lines.get_text("title.game_name")
	add_child(_label)

	var autoloads: int = 0
	for autoload_name: String in ["Events", "Settings", "Lines", "Audio", "Game"]:
		if get_tree().root.has_node(autoload_name):
			autoloads += 1
	print("[boot] ready autoloads=%d json_files=%d lines=%d data_errors=%d" % [
		autoloads, Game.data.roots.size(), Game.data.line_ids().size(), Game.data_errors.size()])
