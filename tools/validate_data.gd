extends SceneTree
## The data validator (GDD 14): every file under res://data, checked for
## required keys, types and dangling ids.
##
##   godot --headless --path . --script res://tools/validate_data.gd


func _initialize() -> void:
	var data: GameData = GameData.load_from()
	var errors: PackedStringArray = DataValidator.validate(data)
	for message: String in errors:
		print("DATA FAIL %s" % message)
	var records: int = 0
	for set_name: Variant in GameData.RECORD_SETS:
		records += data.records(str(set_name)).size()
	print("data validator: %d json files, %d records, %d tuning constants, %d lines, %d error(s)" % [
		data.roots.size(), records, data.tuning.keys().size(), data.line_ids().size(), errors.size()])
	quit(1 if not errors.is_empty() else 0)
