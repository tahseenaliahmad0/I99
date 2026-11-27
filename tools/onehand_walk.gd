extends SceneTree
## A walk through the game with a mouse and nothing else (GDD 17.2), for
## T-ONEHAND-01. See tools/onehand_walk_body.gd, which this loads once the
## autoloads are in the tree.
##
##   godot --headless --path . --fixed-fps 60 --script res://tools/onehand_walk.gd

const BODY: String = "res://tools/onehand_walk_body.gd"


func _initialize() -> void:
	# Autoloads enter the tree on the first frame; the walk needs them.
	await process_frame
	var body: GDScript = load(BODY) as GDScript
	if body == null or not body.can_instantiate():
		print("WALK FAIL: %s does not compile" % BODY)
		quit(1)
		return
	var walk: RefCounted = body.new()
	var failed: int = GameData.as_int(await walk.call("run", self), 1)
	quit(1 if failed > 0 else 0)
