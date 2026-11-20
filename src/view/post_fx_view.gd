class_name PostFxView
extends CanvasLayer
## The post effects (GDD 16.4, 13.5): one full-screen shader between the 3D
## view and what is drawn over it (the pointer, the subtitles, the numeric
## HUD). It shows what the snapshot says of the glass and of his eyes
## (GDD 5.8, 16.3):
##
##   tunnel          dark edges that narrow the view (Nerves 60 and up)
##   lids, blink     dark bars from the top and the bottom; his eyes shut
##   haze            the windscreen clouds, with smoke or with dust
##   rain_blur       the windscreen blurs between wiper sweeps; rain falls
##   cracks          a web of cracks over a share of the windscreen
##   glare_amount,   a bright wash around a light: the motorcade's spotlight,
##   glare_position  the low sun
##   darkness        the night outside the pool of the headlights
##
## What is of the glass is drawn only where he looks through glass, so the
## cabin stays readable. The shader cannot see how far away a pixel is, so
## the glass is found by geometry: the windows are rectangles in the cabin
## frame (postfx_windscreen, postfx_window_left, postfx_window_right), and
## what the cabin hangs before the windscreen (the nodes Mirror and Visor of
## GDD 13.5) is taken out of them again.
##
## Each amount is eased toward what the snapshot says, and may not turn back
## sooner than postfx_flash_hold after it last turned: whatever the
## simulation does, no effect flashes faster than three times a second.
## Reads the snapshot; changes nothing.

const SHADER: Shader = preload("res://shaders/post_fx.gdshader")
const SCREEN_NODE: String = "Screen"
## Where the light that dazzles him is, if the snapshot says: degrees right
## of straight ahead and degrees above the horizon (Vector2). No simulation
## gives this key yet; when one does, it is believed before all else.
const GLARE_POSITION_KEY: String = "glare_position"
## The low sun of Dawn (GDD 10.4): how strong it is before his visor and
## what he wears, and where across his view it stands (-1 the far left, 0
## dead ahead, 1 the far right). While the sun is up the light is the sun,
## his visor down or not; otherwise it is where postfx_glare_position says
## (the motorcade's spotlight, straight ahead).
const SUN_KEY: String = "sun"
const SUN_SIDE_KEY: String = "sun_side"
## Below this a time is no time: nothing is divided by less.
const MIN_TIME: float = 0.0001
## The nodes of the Cabin (GDD 13.5) whose things hang before the windscreen,
## and how many such things the shader takes (its MAX_BLINDS).
const BLIND_NODES: PackedStringArray = ["Mirror", "Visor"]
const MAX_BLINDS: int = 4

## The amounts that are eased from frame to frame.
enum Channel { TUNNEL, LIDS, BLINK, HAZE, RAIN_BLUR, CRACKS, GLARE, DARKNESS, RAIN, DUST, REACH, DARKER }

var _tuning: Tuning
var _camera: Camera3D
var _cabin: Node3D
var _screen: ColorRect
var _material: ShaderMaterial
var _serial: int = -1

var _fade_rate: float = 0.0
var _blink_rate: float = 0.0
var _flash_hold: float = 0.0
var _night_darkness: float = 0.0
var _low_beam: float = 1.0
var _smoke: Color = Color.WHITE
var _dust: Color = Color.WHITE
var _glare_from: Vector2 = Vector2.ZERO
var _sun_position: Vector2 = Vector2.ZERO
## Where the light is, or last was: degrees right of straight ahead and
## above the horizon. A wash that is fading stays where its light was.
var _light: Vector2 = Vector2.ZERO

## Per channel: what is shown now, which way it last moved (-1, 0, +1) and
## for how long it has been going that way.
var _values: PackedFloat64Array = PackedFloat64Array()
var _headings: PackedFloat64Array = PackedFloat64Array()
var _since_turn: PackedFloat64Array = PackedFloat64Array()


## `camera` is the eye and `cabin` the node at the wheel hub: between them
## they say where the glass is in the picture.
func setup(data: GameData, camera: Camera3D, cabin: Node3D) -> void:
	_tuning = data.tuning
	_camera = camera
	_cabin = cabin
	_values.resize(Channel.size())
	_headings.resize(Channel.size())
	_since_turn.resize(Channel.size())
	_values.fill(0.0)
	_headings.fill(0.0)
	_since_turn.fill(0.0)
	# Until a night says otherwise the headlights' pool is the low beam's.
	_values[Channel.REACH] = 1.0

	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_screen = get_node_or_null(SCREEN_NODE) as ColorRect
	if _screen == null:
		_screen = ColorRect.new()
		_screen.name = SCREEN_NODE
		add_child(_screen)
	_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen.material = _material
	# Nothing to show yet: the screen is not even copied.
	_screen.visible = false
	_configure()
	_light = _glare_from


func apply(snapshot: Dictionary, delta: float) -> void:
	if _material == null:
		return
	if _tuning.changed_serial != _serial:
		_configure()
	var tunnel_now: float = snapshot["tunnel"]
	var lids_now: float = snapshot["lids"]
	var eyes_shut: bool = snapshot["eyes_shut"]
	var haze_now: float = snapshot["haze"]
	var rain_blur_now: float = snapshot["rain_blur"]
	var raining: bool = snapshot["raining"]
	var cracks_now: float = snapshot["cracks"]
	var glare_now: float = snapshot["glare"]
	var sun: float = snapshot[SUN_KEY]
	var sun_side: float = snapshot[SUN_SIDE_KEY]
	var night: bool = snapshot["night"]
	var night_darker: float = snapshot["night_darker"]
	var sight: float = snapshot["visibility"]
	var cone: float = snapshot["headlight_cone"]
	var time: float = snapshot["time"]

	# The camera in the cabin frame, and where the light is in the picture:
	# where the snapshot says outright, else at the sun while it is up
	# (behind his visor too), else where a spotlight is. When the light goes
	# out (the end of Dawn's road), what is left of its wash fades where it
	# was.
	var eye: Transform3D = _eye()
	var view_tan: Vector2 = _view_tan()
	if snapshot.has(GLARE_POSITION_KEY) and snapshot[GLARE_POSITION_KEY] is Vector2:
		_light = snapshot[GLARE_POSITION_KEY]
	elif sun > 0.0:
		_light = Vector2(sun_side * _sun_position.x, _sun_position.y)
	elif glare_now > 0.0 or _values[Channel.GLARE] <= 0.0:
		_light = _glare_from
	var toward: Vector3 = eye.basis.inverse() * _direction(_light)
	var light_uv: Vector2 = Vector2(0.5, 0.5)
	if toward.z < 0.0:
		light_uv = Vector2(0.5 + 0.5 * toward.x / (-toward.z * view_tan.x), 0.5 - 0.5 * toward.y / (-toward.z * view_tan.y))
	else:
		# The light is behind him: there is nothing to wash the view with.
		glare_now = 0.0

	# Night: the dark beyond the headlights. Sunglasses and tinted glass
	# take their share of what light is left, there and in the headlights'
	# pool (GDD 7.5, 7.7); the pool is as large as the headlights let him
	# see. Dust in the air ends his view sooner (a Night storm, GDD 10.3),
	# but the lamps shine as wide as ever: the pool is no smaller for it, and
	# what lies beyond the dust is hidden by the world's own haze.
	var dark_now: float = 1.0 - (1.0 - _night_darkness) * (1.0 - night_darker) if night else 0.0
	var reach_now: float = _values[Channel.REACH]
	if night:
		reach_now = maxf(sight if is_finite(sight) else cone, cone * (1.0 - night_darker)) / maxf(_low_beam, MIN_TIME)
	# What clouds the glass is dust wherever dust is in the air: in the Storm
	# by day and by night, and by day wherever his view ends (a dust haze).
	var dusty: float = 1.0 if str(snapshot["boss"]) == BossSim.STORM or (is_finite(sight) and not night) else 0.0

	var tunnel: float = _ease(Channel.TUNNEL, tunnel_now, _fade_rate, delta)
	var lids: float = _ease(Channel.LIDS, lids_now, _fade_rate, delta)
	var blink: float = _ease(Channel.BLINK, 1.0 if eyes_shut else 0.0, _blink_rate, delta)
	var haze: float = _ease(Channel.HAZE, haze_now, _fade_rate, delta)
	var rain_blur: float = _ease(Channel.RAIN_BLUR, rain_blur_now, _fade_rate, delta)
	var cracks: float = _ease(Channel.CRACKS, cracks_now, _fade_rate, delta)
	var glare: float = _ease(Channel.GLARE, glare_now, _fade_rate, delta)
	var darkness: float = _ease(Channel.DARKNESS, dark_now, _fade_rate, delta)
	var rain: float = _ease(Channel.RAIN, 1.0 if raining else 0.0, _fade_rate, delta)
	var dust: float = _ease(Channel.DUST, dusty, _fade_rate, delta)
	var reach: float = _ease(Channel.REACH, reach_now, _fade_rate, delta)
	var darker: float = _ease(Channel.DARKER, night_darker if night else 0.0, _fade_rate, delta)

	# The nine uniforms of GDD 16.4.
	_material.set_shader_parameter(&"tunnel", tunnel)
	_material.set_shader_parameter(&"lids", lids)
	_material.set_shader_parameter(&"blink", blink)
	_material.set_shader_parameter(&"haze", haze)
	_material.set_shader_parameter(&"rain_blur", rain_blur)
	_material.set_shader_parameter(&"cracks", cracks)
	_material.set_shader_parameter(&"glare_amount", glare)
	_material.set_shader_parameter(&"glare_position", light_uv)
	_material.set_shader_parameter(&"darkness", darkness)

	# With nothing to show the rectangle is not drawn, and the renderer does
	# not copy the screen for it.
	_screen.visible = tunnel > 0.0 or lids > 0.0 or blink > 0.0 or haze > 0.0 or rain_blur > 0.0 \
			or cracks > 0.0 or glare > 0.0 or darkness > 0.0 or rain > 0.0
	if not _screen.visible:
		return
	_material.set_shader_parameter(&"rain", rain)
	_material.set_shader_parameter(&"fx_time", time)
	_material.set_shader_parameter(&"beam_reach", reach)
	_material.set_shader_parameter(&"night_darker", darker)
	_material.set_shader_parameter(&"haze_color", _smoke.lerp(_dust, dust))
	_material.set_shader_parameter(&"eye_basis", eye.basis)
	_material.set_shader_parameter(&"eye_origin", eye.origin)
	_material.set_shader_parameter(&"view_tan", view_tan)
	_set_blinds(eye.origin)


## What the shader was last given for one of its uniforms (for tools).
func shown(uniform_name: StringName) -> Variant:
	return _material.get_shader_parameter(uniform_name) if _material != null else null


## Moves a channel toward `target` at `rate` per second and returns what it
## shows now. A channel that has turned may not turn back before
## postfx_flash_hold has passed: it waits where it is. So an amount that is
## thrown back and forth reverses at most six times a second, which is three
## flashes (GDD 16.4), whatever it is given.
func _ease(channel: Channel, target: float, rate: float, delta: float) -> float:
	var value: float = _values[channel]
	_since_turn[channel] += delta
	var heading: float = signf(target - value)
	if heading == 0.0:
		return value
	if heading != _headings[channel]:
		if _headings[channel] != 0.0 and _since_turn[channel] < _flash_hold:
			return value
		_headings[channel] = heading
		_since_turn[channel] = 0.0
	value = move_toward(value, target, rate * delta)
	_values[channel] = value
	return value


## Reads the tuning constants and hands the shader those that do not change
## from frame to frame. Again whenever the tuning panel changes one.
func _configure() -> void:
	var tuning: Tuning = _tuning
	_serial = tuning.changed_serial
	_fade_rate = 1.0 / maxf(tuning.f("postfx_fade_time"), MIN_TIME)
	_blink_rate = 1.0 / maxf(tuning.f("postfx_blink_time"), MIN_TIME)
	_flash_hold = tuning.f("postfx_flash_hold")
	_night_darkness = tuning.f("postfx_night_darkness")
	_low_beam = tuning.f("low_beam_cone")
	_smoke = Color.html(tuning.s("postfx_haze_color"))
	_dust = Color.html(tuning.s("sky_color_dust"))
	_glare_from = _pair(tuning, "postfx_glare_position")
	_sun_position = _pair(tuning, "sun_position")

	# The glass: three panes in the cabin frame.
	_set_pane(tuning, "postfx_windscreen", &"windscreen_rect", &"windscreen_z")
	_set_pane(tuning, "postfx_window_left", &"window_left_rect", &"window_left_x")
	_set_pane(tuning, "postfx_window_right", &"window_right_rect", &"window_right_x")
	_material.set_shader_parameter(&"glass_feather", tuning.f("postfx_glass_feather"))
	_material.set_shader_parameter(&"demist_strip", _pair(tuning, "postfx_demist_strip"))

	_material.set_shader_parameter(&"tunnel_color", Color.html(tuning.s("postfx_tunnel_color")))
	_material.set_shader_parameter(&"tunnel_strength", tuning.f("postfx_tunnel_strength"))
	_material.set_shader_parameter(&"tunnel_feather", tuning.f("postfx_tunnel_feather"))
	_material.set_shader_parameter(&"tunnel_onset", tuning.f("postfx_tunnel_onset"))
	_material.set_shader_parameter(&"tunnel_min_view", tuning.f("tunnel_min_view"))

	_material.set_shader_parameter(&"lid_color", Color.html(tuning.s("postfx_lid_color")))
	_material.set_shader_parameter(&"lid_feather", tuning.f("postfx_lid_feather"))
	_material.set_shader_parameter(&"lid_curve", tuning.f("postfx_lid_curve"))

	_material.set_shader_parameter(&"haze_mottle", tuning.f("postfx_haze_mottle"))
	_material.set_shader_parameter(&"haze_patch", tuning.f("postfx_haze_patch"))
	_material.set_shader_parameter(&"haze_drift", tuning.f("postfx_haze_drift"))

	_material.set_shader_parameter(&"rain_blur_radius", tuning.f("postfx_rain_blur_radius"))
	_material.set_shader_parameter(&"rain_streak_color", Color.html(tuning.s("postfx_rain_streak_color")))
	_material.set_shader_parameter(&"rain_streak_alpha", tuning.f("postfx_rain_streak_alpha"))
	_material.set_shader_parameter(&"rain_streak_speed", tuning.f("postfx_rain_streak_speed"))
	_material.set_shader_parameter(&"rain_streak_slant", tuning.f("postfx_rain_streak_slant"))
	_material.set_shader_parameter(&"rain_streak_density", _pair(tuning, "postfx_rain_streak_density"))
	_material.set_shader_parameter(&"rain_streak_width", tuning.f("postfx_rain_streak_width"))

	_material.set_shader_parameter(&"crack_center", _pair(tuning, "postfx_crack_center"))
	_material.set_shader_parameter(&"crack_color", Color.html(tuning.s("postfx_crack_color")))
	_material.set_shader_parameter(&"crack_alpha", tuning.f("postfx_crack_alpha"))
	_material.set_shader_parameter(&"crack_width", tuning.f("postfx_crack_width"))
	_material.set_shader_parameter(&"crack_spokes", tuning.f("postfx_crack_spokes"))
	_material.set_shader_parameter(&"crack_shift", tuning.f("postfx_crack_shift"))
	_material.set_shader_parameter(&"crack_frost", tuning.f("postfx_crack_frost"))
	_material.set_shader_parameter(&"crack_core", tuning.f("postfx_crack_core"))
	_material.set_shader_parameter(&"crack_fray", tuning.f("postfx_crack_fray"))

	_material.set_shader_parameter(&"glare_color", Color.html(tuning.s("postfx_glare_color")))
	_material.set_shader_parameter(&"glare_radius", tuning.f("postfx_glare_radius"))
	_material.set_shader_parameter(&"glare_core", tuning.f("postfx_glare_core"))
	_material.set_shader_parameter(&"glare_cabin_share", tuning.f("postfx_glare_cabin_share"))

	_material.set_shader_parameter(&"darkness_color", Color.html(tuning.s("postfx_darkness_color")))
	_material.set_shader_parameter(&"cabin_darkness_share", tuning.f("postfx_cabin_darkness_share"))
	# The pool of the headlights is given in degrees and drawn in tangents.
	var aim: Vector2 = _pair(tuning, "postfx_beam_aim")
	var size: Vector2 = _pair(tuning, "postfx_beam_size")
	_material.set_shader_parameter(&"beam_aim", Vector2(tan(deg_to_rad(aim.x)), tan(deg_to_rad(aim.y))))
	_material.set_shader_parameter(&"beam_size", Vector2(tan(deg_to_rad(size.x)), tan(deg_to_rad(size.y))))
	_material.set_shader_parameter(&"beam_feather", tuning.f("postfx_beam_feather"))


## What of the cabin hangs before the windscreen is not glass: the shader
## is told where each such thing is, as the eye sees it, as a rectangle in a
## plane across the car. Whatever is drawn now under the Cabin's Mirror and
## Visor nodes counts: the mirror while it is drawn, the visor, the lowered
## visor.
func _set_blinds(eye: Vector3) -> void:
	var rects: PackedVector4Array = PackedVector4Array()
	var planes: PackedFloat32Array = PackedFloat32Array()
	if _cabin != null:
		var to_cabin: Transform3D = _cabin.global_transform.affine_inverse()
		for node_name: String in BLIND_NODES:
			var group: Node = _cabin.get_node_or_null(node_name)
			if group != null:
				_add_blinds(group, to_cabin, eye, rects, planes)
	var count: int = mini(rects.size(), MAX_BLINDS)
	rects.resize(MAX_BLINDS)
	planes.resize(MAX_BLINDS)
	_material.set_shader_parameter(&"blind_count", count)
	_material.set_shader_parameter(&"blind_rect", rects)
	_material.set_shader_parameter(&"blind_z", planes)


func _add_blinds(node: Node, to_cabin: Transform3D, eye: Vector3, rects: PackedVector4Array, planes: PackedFloat32Array) -> void:
	var thing: VisualInstance3D = node as VisualInstance3D
	if thing != null and thing.is_visible_in_tree():
		# The thing's box, seen from the eye, on the plane through its middle.
		var box: AABB = thing.get_aabb()
		var place: Transform3D = to_cabin * thing.global_transform
		var plane: float = (place * box.get_center()).z
		var low: Vector2 = Vector2(INF, INF)
		var high: Vector2 = Vector2(-INF, -INF)
		var ahead: bool = plane < eye.z
		for index: int in 8:
			var corner: Vector3 = place * box.get_endpoint(index)
			if corner.z >= eye.z:
				ahead = false
				break
			var seen: Vector2 = Vector2(eye.x, eye.y) + (Vector2(corner.x, corner.y) - Vector2(eye.x, eye.y)) * (plane - eye.z) / (corner.z - eye.z)
			low = low.min(seen)
			high = high.max(seen)
		if ahead and high.x > low.x and high.y > low.y:
			rects.append(Vector4(low.x, low.y, high.x, high.y))
			planes.append(plane)
	for child: Node in node.get_children():
		_add_blinds(child, to_cabin, eye, rects, planes)


## A pane of glass is five numbers: its rectangle (two corners) and where
## its plane lies.
func _set_pane(tuning: Tuning, key: String, rect_uniform: StringName, plane_uniform: StringName) -> void:
	_material.set_shader_parameter(rect_uniform, Vector4(tuning.fi(key, 0), tuning.fi(key, 1), tuning.fi(key, 2), tuning.fi(key, 3)))
	_material.set_shader_parameter(plane_uniform, tuning.fi(key, 4))


func _pair(tuning: Tuning, key: String) -> Vector2:
	return Vector2(tuning.fi(key, 0), tuning.fi(key, 1))


## The camera in the cabin frame.
func _eye() -> Transform3D:
	if _camera == null:
		return Transform3D.IDENTITY
	var eye: Transform3D = _camera.global_transform
	if _cabin != null:
		eye = _cabin.global_transform.affine_inverse() * eye
	return eye


## The tangents of half the camera's field of view, across and up.
func _view_tan() -> Vector2:
	if _camera == null:
		return Vector2.ONE
	var projection: Projection = _camera.get_camera_projection()
	if is_zero_approx(projection.x.x) or is_zero_approx(projection.y.y):
		return Vector2.ONE
	return Vector2(1.0 / projection.x.x, 1.0 / projection.y.y)


## The way toward something that lies `from.x` degrees right of straight
## ahead and `from.y` degrees above the horizon, in the cabin frame.
func _direction(from: Vector2) -> Vector3:
	var yaw: float = deg_to_rad(from.x)
	var pitch: float = deg_to_rad(from.y)
	return Vector3(sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
