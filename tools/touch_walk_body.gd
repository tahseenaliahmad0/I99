extends RefCounted
## The body of tools/touch_walk.gd: a night begun at a Table and played by
## screen touches handed to the window as a touch screen would hand them.
## A thumb on the wheel takes it; lifted, the hand lets go; a second thumb
## on the pedal zone brakes; a tap on the hotspot pauses.
##
## Prints "TOUCH ok: ..." or "TOUCH FAIL: ..." for each step and
## "TOUCH DONE steps=N failed=M" at the end.

const GUARD_FRAMES: int = 1200

var _failed: int = 0
var _steps: int = 0
var _tree: SceneTree
var root: Window


func run(tree: SceneTree) -> int:
	_tree = tree
	root = tree.root
	await _walk()
	print("TOUCH DONE steps=%d failed=%d" % [_steps, _failed])
	return _failed


func _ok(passed: bool, what: String) -> bool:
	_steps += 1
	if passed:
		print("TOUCH ok: %s" % what)
	else:
		_failed += 1
		print("TOUCH FAIL: %s" % what)
	return passed


func _finger(index: int, at: Vector2, down: bool) -> void:
	var touch: InputEventScreenTouch = InputEventScreenTouch.new()
	touch.index = index
	touch.position = at
	touch.pressed = down
	root.push_input(touch, true)


func _frames(count: int) -> void:
	for _index: int in count:
		await _tree.process_frame


func _walk() -> void:
	Game.go(Game.AppState.TELLING, {"table": "drivers", "seed": "3"})
	var guard: int = GUARD_FRAMES
	while guard > 0 and (_tree.current_scene == null or _tree.current_scene.scene_file_path != Game.DRIVE_SCENE):
		guard -= 1
		await _tree.process_frame
	await _frames(10)
	var drive: Node = _tree.current_scene
	var sim: DriveSim = drive.get("sim") as DriveSim if drive != null else null
	if not _ok(sim != null and sim.run.active, "(a night at the Drivers' Table, on the road)"):
		return
	var camera: Camera3D = drive.get_node("Camera3D") as Camera3D
	var cabin: Node3D = drive.get_node("Cabin") as Node3D
	var view: Vector2 = root.get_visible_rect().size
	var touch: TouchInput = TouchInput.new(Game.data.tuning)
	var dpi: float = float(DisplayServer.screen_get_dpi()) * view.y / maxf(float(root.size.y), 1.0)
	var zone: Rect2 = touch.pedal_zone(view, dpi)
	var hotspot: Rect2 = touch.hotspot(view, dpi)
	var wheel: Vector2 = camera.unproject_position(cabin.to_global(sim.space.grip_reference))
	_ok(not zone.has_point(wheel) and not hotspot.has_point(wheel) and Rect2(Vector2.ZERO, view).has_point(wheel),
			"(the wheel is on the glass, clear of the pedal zone and the hotspot: %s)" % str(wheel.round()))

	# The right thumb on the wheel.
	_finger(0, wheel, true)
	guard = 240
	while guard > 0 and not sim.hand.gripping:
		guard -= 1
		await _tree.physics_frame
	_ok(sim.hand.gripping, "a thumb on the wheel: the hand has it")
	_finger(0, wheel, false)
	await _frames(12)
	_ok(not sim.hand.gripping, "lifted: the hand lets go")

	# The other thumb on the pedal zone, the car rolling.
	_finger(0, wheel, true)
	guard = 600
	while guard > 0 and sim.car.speed < 30.0:
		guard -= 1
		await _tree.physics_frame
	var speed: float = sim.car.speed
	_finger(1, zone.get_center(), true)
	await _frames(45)
	_ok(sim.car.speed < speed - 5.0, "a thumb on the pedal zone: the car slows (%d to %d km/h)" % [roundi(speed), roundi(sim.car.speed)])
	_ok(sim.hand.gripping, "(and the other thumb still has the wheel)")
	_finger(1, zone.get_center(), false)
	_finger(0, wheel, false)
	await _frames(6)

	# The hotspot.
	_finger(0, hotspot.get_center(), true)
	await _frames(6)
	_finger(0, hotspot.get_center(), false)
	await _frames(6)
	_ok(_tree.paused, "a tap on the hotspot: the night waits")
	_tree.paused = false
