class_name ProjectFiles
extends RefCounted
## Lists project files for the check tools. Skips hidden folders and any folder
## holding a .gdignore file (docs_api, artifacts), as the engine itself does.


static func find(root_dir: String, extensions: PackedStringArray) -> PackedStringArray:
	var out: PackedStringArray = []
	_walk(root_dir, extensions, out)
	out.sort()
	return out


static func _walk(dir_path: String, extensions: PackedStringArray, out: PackedStringArray) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	if dir.file_exists(".gdignore"):
		return
	for sub: String in dir.get_directories():
		if not sub.begins_with("."):
			_walk(dir_path.path_join(sub), extensions, out)
	for file: String in dir.get_files():
		if extensions.has(file.get_extension()):
			out.append(dir_path.path_join(file))
