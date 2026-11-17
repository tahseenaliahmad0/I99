extends Node
## Plays generated placeholder sounds by event id (GDD 16.5).
##
## Every sound is listed in data/sfx.json. The buffers are generated in code at
## boot (M10); until then this autoload only checks that requested ids exist,
## so a misspelt id fails the smoke tests long before there is anything to hear.

var _data: GameData


func setup(data: GameData) -> void:
	_data = data
	if not Events.sfx_requested.is_connected(_on_sfx_requested):
		Events.sfx_requested.connect(_on_sfx_requested)


func has_sound(id: String) -> bool:
	return _data != null and _data.root("sfx").has(id)


func play(id: String) -> void:
	if not has_sound(id):
		push_error("Audio: unknown sfx id '%s'" % id)
		return


func _on_sfx_requested(data: Dictionary) -> void:
	play(GameData.as_string(data.get("id")))
