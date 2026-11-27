extends RefCounted
## A walk through the game with a mouse and nothing else (GDD 17.2: "Every
## function works with pointer motion and two buttons. Keyboard keys only
## duplicate."), for T-ONEHAND-01:
##
##   godot --headless --path . --fixed-fps 60 --script res://tools/onehand_walk.gd
##
## (This is its body: tools/onehand_walk.gd loads it once the autoloads are
## in the tree.)
##
## Every input it gives is a mouse motion or a press of the left or right
## mouse button, fed to the engine as a player's would be. It goes: the
## title; its options (a setting changed with each button, and back); on to
## the wedding; the pointer to a Table and a press to sit; in the car, the
## left button held on nothing to pause; from the pause back to the wedding; back to the title;
## then an ending's card, the finale (eight claps, the walk, letting go),
## the proverb and the credits. Each step prints "WALK ok: ..." or "WALK
## FAIL: ...", and the last line is "WALK DONE".

const TITLE: String = "res://scenes/title.tscn"
const WEDDING: String = "res://scenes/wedding.tscn"
const GUARD_FRAMES: int = 6000

var _failed: int = 0
var _steps: int = 0
var _at: Vector2 = Vector2.ZERO
var _tree: SceneTree
var root: Window


## Walks; returns how many steps failed.
func run(tree: SceneTree) -> int:
	_tree = tree
	root = tree.root
	await _walk()
	return _failed


func _ok(passed: bool, what: String) -> bool:
	_steps += 1
	if passed:
		print("WALK ok: %s" % what)
	else:
		_failed += 1
		print("WALK FAIL: %s" % what)
	return passed


# --- The mouse -------------------------------------------------------------------

func _move_to(position: Vector2) -> void:
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	motion.relative = position - _at
	_at = position
	_give(motion)


func _move_by(relative: Vector2) -> void:
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	_at += relative
	motion.position = _at
	motion.global_position = _at
	motion.relative = relative
	_give(motion)


func _button(index: MouseButton, down: bool) -> void:
	var press: InputEventMouseButton = InputEventMouseButton.new()
	press.button_index = index
	press.pressed = down
	press.position = _at
	press.global_position = _at
	press.button_mask = (MOUSE_BUTTON_MASK_LEFT if index == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT) if down else 0
	_give(press)


## Hands the scene a mouse event as its window would: to the viewport, in
## the viewport's own coordinates (a headless build has a window of 64
## pixels, whatever the game draws on). A button is also told to the Input
## singleton, which is what the game asks when it polls "is the grip held".
func _give(event: InputEvent) -> void:
	var press: InputEventMouseButton = event as InputEventMouseButton
	if press != null:
		var action: String = "grip" if press.button_index == MOUSE_BUTTON_LEFT else "brake"
		if press.pressed:
			Input.action_press(action)
		else:
			Input.action_release(action)
	root.push_input(event, true)


func _frames(count: int) -> void:
	for _index: int in count:
		await _tree.process_frame


## A press and release of a mouse button where the pointer is.
func _click(index: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	_button(index, true)
	await _frames(2)
	_button(index, false)
	await _frames(2)


func _click_at(position: Vector2, index: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	_move_to(position)
	await _frames(2)
	await _click(index)


# --- What is on the screen ---------------------------------------------------------

## The button of the scene that shows `text` (null for none).
func _find_button(node: Node, text: String) -> Button:
	if node is Button and (node as Button).is_visible_in_tree() and (node as Button).text.begins_with(text):
		return node as Button
	for child: Node in node.get_children():
		var found: Button = _find_button(child, text)
		if found != null:
			return found
	return null


func _press_button(text: String) -> bool:
	var button: Button = _find_button(root, text)
	if button == null:
		return false
	await _click_at(button.get_global_rect().get_center())
	return true


func _scene_is(path: String) -> bool:
	return _tree.current_scene != null and _tree.current_scene.scene_file_path == path


func _until_scene(path: String) -> bool:
	var guard: int = GUARD_FRAMES
	while not _scene_is(path) and guard > 0:
		guard -= 1
		await _tree.process_frame
	await _frames(3)
	return _scene_is(path)


# --- The walk ------------------------------------------------------------------------

func _walk() -> void:
	var data: GameData = Game.data
	var tuning: Tuning = data.tuning
	# A player who has seen the prologue: the title leads to the wedding.
	Game.profile = Save.new_profile(data)
	Game.profile["prologue_seen"] = true
	Game.saved_telling = {}
	Game.args = {"seed": "3"}

	# 1. The title, and its options.
	_tree.change_scene_to_file(TITLE)
	_ok(await _until_scene(TITLE), "the title is on the screen")
	_ok(await _press_button(Lines.get_text("title.options")), "a press on Options")
	await _frames(3)
	var name_of: String = Lines.get_text("settings.%s.name" % SettingsSpec.STEERING)
	var before: float = GameData.as_float(Settings.get_value(SettingsSpec.STEERING))
	var row: Button = _find_button(root, name_of)
	_ok(row != null, "the settings are on the screen")
	if row != null:
		await _click_at(row.get_global_rect().get_center(), MOUSE_BUTTON_LEFT)
		_ok(GameData.as_float(Settings.get_value(SettingsSpec.STEERING)) > before, "the left button on a row takes its next option")
		await _click_at(row.get_global_rect().get_center(), MOUSE_BUTTON_RIGHT)
		_ok(is_equal_approx(GameData.as_float(Settings.get_value(SettingsSpec.STEERING)), before), "the right button the one before")
	_ok(await _press_button(Lines.get_text("settings.back")), "a press on Back")
	await _frames(3)
	_ok(_find_button(root, name_of) == null, "the settings are closed")

	# 2. On to the wedding, and a Table.
	_ok(await _press_button(Lines.get_text("title.continue")), "a press on Continue")
	_ok(await _until_scene(WEDDING), "the wedding room")
	var table_id: String = TableRules.open_at_start(data)[0]
	var spot: Array = GameData.as_array(data.record("tables", table_id).get("room_pos"))
	var factory: PlaceholderFactory = PlaceholderFactory.new(data)
	var table_at: Vector3 = Vector3(GameData.as_float(spot[0]), factory.size_of("wedding_table").y, GameData.as_float(spot[1]))
	var camera: Camera3D = root.get_camera_3d()
	_move_to(camera.unproject_position(table_at))
	await _frames(4)
	await _click()
	_ok(await _until_scene(Game.DRIVE_SCENE), "the pointer on an open Table and a press: he sits, and the night begins")
	_ok(Game.state == Game.AppState.TELLING, "(a Telling)")

	# 3. In the car: the left button held on nothing is the pause (D-066).
	var drive: Node = _tree.current_scene
	var sim: DriveSim = drive.get("sim") as DriveSim
	_ok(sim != null and sim.run.active, "(he is on the road)")
	# The pointer is his hand: moved by the mouse's motion, up and away from
	# the wheel until it points at nothing.
	var guard: int = 600
	while not sim.hand_is_free() and guard > 0:
		guard -= 1
		_move_by(Vector2(-6.0, -6.0))
		await _tree.physics_frame
		await _tree.physics_frame
	_ok(sim.hand_is_free(), "moved by the mouse alone, the pointer is on nothing")
	_button(MOUSE_BUTTON_LEFT, true)
	guard = 600
	while not _tree.paused and guard > 0:
		guard -= 1
		await _tree.physics_frame
	_button(MOUSE_BUTTON_LEFT, false)
	_ok(_tree.paused, "the left button held on nothing: the night waits")
	await _frames(3)
	_ok(_find_button(root, Lines.get_text("settings.steady_start.name")) != null, "and the settings are there to change, mid-Telling")
	var tick: int = sim.tick
	await _frames(30)
	_ok(sim.tick == tick, "(nothing moves while it waits)")
	_ok(await _press_button(Lines.get_text("settings.leave")), "a press on \"Back to the wedding\"")
	_ok(await _until_scene(WEDDING) and not _tree.paused, "the wedding room again")

	# 4. Back to the title.
	_ok(await _press_button(Lines.get_text("wedding.back")), "a press on \"Back to the title\"")
	_ok(await _until_scene(TITLE), "the title again")
	_ok(_find_button(root, Lines.get_text("title.quit")) != null, "(with its Quit)")

	# 5. An ending's card, the finale, the proverb and the credits.
	Game.args = {"ending": Save.THE_CALL, "table": "noor"}
	_tree.change_scene_to_file(WEDDING)
	_ok(await _until_scene(WEDDING) and Game.state == Game.AppState.ENDING, "an ending's card: the Call, at Noor's Table")
	_move_to(root.get_visible_rect().size * 0.5)
	await _click()
	await _frames(4)
	_ok(Game.state == Game.AppState.FINALE, "a press: the finale")
	var noor_at: Vector3 = _vec3(tuning.a("finale_noor_pos"))
	camera = root.get_camera_3d()
	_move_to(camera.unproject_position(noor_at + _vec3(tuning.a("finale_palm"))))
	await _frames(4)
	for _clap: int in tuning.i("finale_claps") - 1:
		await _click()
		await _frames(6)
	# The eighth clap is not let go: she takes his hand, and they walk.
	_button(MOUSE_BUTTON_LEFT, true)
	guard = GUARD_FRAMES
	var walked: float = 0.0
	while guard > 0 and walked < tuning.f("finale_walk_s") + 2.0:
		guard -= 1
		walked += 1.0 / float(Engine.physics_ticks_per_second)
		await _tree.physics_frame
	_ok(Game.state == Game.AppState.FINALE, "eight claps on her palm and the button held for the walk: they stand, and nothing ends it")
	_button(MOUSE_BUTTON_LEFT, false)
	await _frames(10)
	var card: String = Lines.get_text("finale.proverb").get_slice(" / ", 0)
	_ok(_shows(root, card), "the button let go: the proverb's card")
	await _frames(90)
	await _click()
	await _frames(4)
	_ok(Game.state == Game.AppState.CREDITS, "a press: the credits")
	await _click()
	await _frames(4)
	_ok(Game.state == Game.AppState.WEDDING, "a press: the wedding room")

	print("WALK DONE steps=%d failed=%d" % [_steps, _failed])


## Whether a label of the scene shows `text`.
func _shows(node: Node, text: String) -> bool:
	if node is Label and (node as Label).is_visible_in_tree() and (node as Label).text.contains(text):
		return true
	for child: Node in node.get_children():
		if _shows(child, text):
			return true
	return false


func _vec3(values: Array) -> Vector3:
	return Vector3(GameData.as_float(values[0]), GameData.as_float(values[1]), GameData.as_float(values[2])) if values.size() >= 3 else Vector3.ZERO
