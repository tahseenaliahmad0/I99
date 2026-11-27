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
## What is of the glass and of the world outside is not drawn over the
## cabin, so the cabin stays readable. The shader cannot see how far away a
## pixel is, so it is shown the cabin by itself: a second camera, kept where
## the eye is, draws what is under the Cabin node (the cabin, his arm, what
## he carries, a passenger, the stall's tray and people; not what the car
## carries before its windscreen) and nothing else into a picture of its
## own, the shader's `cabin_mask`. Where that picture is solid the pixel is
## of the cabin; everything else is the world, and the part of it he sees
## through the windscreen is found by geometry (postfx_windscreen, a
## rectangle in the cabin frame). While the rain blurs the glass the shader
## is also shown that picture as the blur would smear it (`cabin_smear`),
## so that the cabin's colours can be kept out of the smear.
##
## Each amount is eased toward what the snapshot says, and may not turn back
## sooner than postfx_flash_hold after it last turned; a light that changes
## place while its wash is up is moved there, not put there: whatever the
## simulation does, no effect flashes faster than three times a second.
## Reads the snapshot; changes nothing.

const SHADER: Shader = preload("res://shaders/post_fx.gdshader")
const CABIN_SHADER: Shader = preload("res://shaders/post_fx_cabin.gdshader")
const SCREEN_NODE: String = "Screen"
const MASK_NODE: String = "CabinMask"
const SMEAR_NODE: String = "CabinSmear"
## The visual layer on which the mask's camera sees the cabin and nothing
## else: the last of the engine's twenty. What is of the cabin is drawn on
## it besides its own layer, so the eye's camera sees it as before.
const CABIN_LAYER: int = 1 << 19
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

## The amounts that are eased from frame to frame; the last two are where the
## light is shown, in degrees right of straight ahead and above the horizon.
enum Channel { TUNNEL, LIDS, BLINK, HAZE, RAIN_BLUR, CRACKS, GLARE, DARKNESS, RAIN, DUST, REACH, DARKER, LIGHT_RIGHT, LIGHT_UP }

var _tuning: Tuning
var _camera: Camera3D
var _cabin: Node3D
var _screen: ColorRect
var _material: ShaderMaterial
## The cabin's picture and the camera that takes it; the same picture as
## the rain's blur needs it, and the shader that makes it (null with no cabin).
var _mask: SubViewport
var _mask_camera: Camera3D
var _smear: SubViewport
var _smear_material: ShaderMaterial
var _serial: int = -1

var _fade_rate: float = 0.0
var _blink_rate: float = 0.0
var _flash_hold: float = 0.0
var _light_speed: float = 0.0
var _night_darkness: float = 0.0
var _low_beam: float = 1.0
var _smoke: Color = Color.WHITE
var _dust: Color = Color.WHITE
var _glare_from: Vector2 = Vector2.ZERO
var _sun_position: Vector2 = Vector2.ZERO
## The windscreen in the cabin frame: left, bottom, right, top; its plane.
var _windscreen: Vector4 = Vector4.ZERO
var _windscreen_z: float = 0.0
## Where the light is, or last was: degrees right of straight ahead and
## above the horizon. A wash that is fading stays where its light was.
var _light: Vector2 = Vector2.ZERO

## Per channel: what is shown now, which way it last moved (-1, 0, +1) and
## for how long it has been going that way.
var _values: PackedFloat64Array = PackedFloat64Array()
var _headings: PackedFloat64Array = PackedFloat64Array()
var _since_turn: PackedFloat64Array = PackedFloat64Array()


## `camera` is the eye and `cabin` the node at the wheel hub: between them
## they say where the glass is in the picture, and what is drawn under
## `cabin` is what the shader is shown as the cabin.
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
	_build_mask()
	_configure()
	_light = _glare_from
	_put(Channel.LIGHT_RIGHT, _light.x)
	_put(Channel.LIGHT_UP, _light.y)
	if is_inside_tree():
		_listen()


func _enter_tree() -> void:
	if _material != null:
		_listen()
		_mark_cabin()


func _exit_tree() -> void:
	var tree: SceneTree = get_tree()
	if tree.node_added.is_connected(_on_node_added):
		tree.node_added.disconnect(_on_node_added)


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
	# While nothing of a wash is up the light is shown where it is. A light
	# that changes place while its wash is up (the sun for a spotlight) is
	# moved there at postfx_light_speed, and like every amount it may not
	# turn back at once: the wash never jumps.
	if _values[Channel.GLARE] <= 0.0:
		_put(Channel.LIGHT_RIGHT, _light.x)
		_put(Channel.LIGHT_UP, _light.y)
	var shown_at: Vector2 = Vector2(_ease(Channel.LIGHT_RIGHT, _light.x, _light_speed, delta), _ease(Channel.LIGHT_UP, _light.y, _light_speed, delta))
	var toward: Vector3 = eye.basis.inverse() * _direction(shown_at)
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

	# With nothing to show the rectangle is not drawn: the renderer does not
	# copy the screen for it, and the cabin's picture is not taken.
	_screen.visible = tunnel > 0.0 or lids > 0.0 or blink > 0.0 or haze > 0.0 or rain_blur > 0.0 \
			or cracks > 0.0 or glare > 0.0 or darkness > 0.0 or rain > 0.0
	_aim_mask(_screen.visible and visible, rain_blur)
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


## Puts a channel where it belongs while nothing of it can be seen: it has
## not moved, so it has not turned either.
func _put(channel: Channel, value: float) -> void:
	_values[channel] = value
	_headings[channel] = 0.0
	_since_turn[channel] = 0.0


## Reads the tuning constants and hands the shader those that do not change
## from frame to frame. Again whenever the tuning panel changes one.
func _configure() -> void:
	var tuning: Tuning = _tuning
	_serial = tuning.changed_serial
	_fade_rate = 1.0 / maxf(tuning.f("postfx_fade_time"), MIN_TIME)
	_blink_rate = 1.0 / maxf(tuning.f("postfx_blink_time"), MIN_TIME)
	_flash_hold = tuning.f("postfx_flash_hold")
	_light_speed = tuning.f("postfx_light_speed")
	_night_darkness = tuning.f("postfx_night_darkness")
	_low_beam = tuning.f("low_beam_cone")
	_smoke = Color.html(tuning.s("postfx_haze_color"))
	_dust = Color.html(tuning.s("sky_color_dust"))
	_glare_from = _pair(tuning, "postfx_glare_position")
	_sun_position = _pair(tuning, "sun_position")

	# The cabin and the glass: what counts as solid, and the windscreen, a
	# rectangle (two corners) in a plane of the cabin frame.
	_windscreen = Vector4(tuning.fi("postfx_windscreen", 0), tuning.fi("postfx_windscreen", 1), tuning.fi("postfx_windscreen", 2), tuning.fi("postfx_windscreen", 3))
	_windscreen_z = tuning.fi("postfx_windscreen", 4)
	_material.set_shader_parameter(&"cabin_solid", _pair(tuning, "postfx_cabin_solid"))
	_material.set_shader_parameter(&"windscreen_rect", _windscreen)
	_material.set_shader_parameter(&"windscreen_z", _windscreen_z)
	_material.set_shader_parameter(&"glass_feather", tuning.f("postfx_glass_feather"))
	_mark_cabin()

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
	_material.set_shader_parameter(&"haze_fine", _pair(tuning, "postfx_haze_fine"))

	_material.set_shader_parameter(&"rain_blur_radius", tuning.f("postfx_rain_blur_radius"))
	if _smear_material != null:
		_smear_material.set_shader_parameter(&"rain_blur_radius", tuning.f("postfx_rain_blur_radius"))
	_material.set_shader_parameter(&"rain_blur_center", tuning.f("postfx_rain_blur_center"))
	_material.set_shader_parameter(&"rain_streak_color", Color.html(tuning.s("postfx_rain_streak_color")))
	_material.set_shader_parameter(&"rain_streak_alpha", tuning.f("postfx_rain_streak_alpha"))
	_material.set_shader_parameter(&"rain_streak_speed", tuning.f("postfx_rain_streak_speed"))
	_material.set_shader_parameter(&"rain_streak_slant", tuning.f("postfx_rain_streak_slant"))
	_material.set_shader_parameter(&"rain_streak_density", _pair(tuning, "postfx_rain_streak_density"))
	_material.set_shader_parameter(&"rain_streak_width", tuning.f("postfx_rain_streak_width"))
	_material.set_shader_parameter(&"rain_streak_share", tuning.f("postfx_rain_streak_share"))
	_material.set_shader_parameter(&"rain_streak_taper", tuning.f("postfx_rain_streak_taper"))
	_material.set_shader_parameter(&"rain_streak_far", tuning.f("postfx_rain_streak_far"))

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


## The cabin's picture, the shader's `cabin_mask`: a viewport as large as the
## view, in which a camera of its own sees what is on the cabin's layer over
## nothing. It shares the eye's world; it is drawn before the view is, in the
## same frame, and only while there is something to show.
##
## And that picture once more as the rain's blur needs it, the shader's
## `cabin_smear`: a second viewport, drawn after the first, in which the
## first is copied and then read from the mipmap the blur reads the view
## from (post_fx_cabin.gdshader). It is drawn only while the rain blurs.
func _build_mask() -> void:
	if _camera == null or _cabin == null:
		return
	_mask = _picture(MASK_NODE)
	_mask.positional_shadow_atlas_size = 0
	_mask_camera = Camera3D.new()
	_mask_camera.cull_mask = CABIN_LAYER
	# Whatever the sky does (its colour, an artist's glow) is not the cabin's.
	_mask_camera.environment = Environment.new()
	_mask.add_child(_mask_camera)
	_mask_camera.current = true
	_material.set_shader_parameter(&"cabin_mask", _mask.get_texture())

	_smear = _picture(SMEAR_NODE)
	_smear.disable_3d = true
	# The copy: the cabin's picture as it is, colour and alpha.
	var copy: TextureRect = TextureRect.new()
	copy.texture = _mask.get_texture()
	copy.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	copy.stretch_mode = TextureRect.STRETCH_SCALE
	var as_it_is: CanvasItemMaterial = CanvasItemMaterial.new()
	as_it_is.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	copy.material = as_it_is
	_smear_material = ShaderMaterial.new()
	_smear_material.shader = CABIN_SHADER
	var smeared: ColorRect = ColorRect.new()
	smeared.material = _smear_material
	for layer: Control in [copy, smeared]:
		layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_smear.add_child(layer)
		layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_material.set_shader_parameter(&"cabin_smear", _smear.get_texture())


## A picture of the view's own: a viewport with nothing behind what is drawn
## in it, which takes no input and is not drawn until it is asked for.
func _picture(node_name: String) -> SubViewport:
	var picture: SubViewport = get_node_or_null(node_name) as SubViewport
	if picture == null:
		picture = SubViewport.new()
		picture.name = node_name
		add_child(picture)
	picture.transparent_bg = true
	picture.handle_input_locally = false
	picture.gui_disable_input = true
	picture.render_target_update_mode = SubViewport.UPDATE_DISABLED
	return picture


## Keeps the mask's camera where the eye is and the cabin's pictures as large
## as the view's, and has them drawn this frame or not: the first while
## there is something to show, the second while the rain blurs (`rain_blur`).
func _aim_mask(wanted: bool, rain_blur: float) -> void:
	if _mask == null:
		return
	_mask.render_target_update_mode = SubViewport.UPDATE_ALWAYS if wanted else SubViewport.UPDATE_DISABLED
	_smear.render_target_update_mode = SubViewport.UPDATE_ALWAYS if wanted and rain_blur > 0.0 else SubViewport.UPDATE_DISABLED
	if not wanted or not is_inside_tree() or not _camera.is_inside_tree():
		return
	_smear_material.set_shader_parameter(&"rain_blur", rain_blur)
	var size: Vector2i = Vector2i(get_viewport().get_texture().get_size())
	if size.x > 0 and size.y > 0 and _mask.size != size:
		_mask.size = size
		_smear.size = size
	_mask_camera.global_transform = _camera.global_transform
	_mask_camera.projection = _camera.projection
	_mask_camera.keep_aspect = _camera.keep_aspect
	_mask_camera.fov = _camera.fov
	_mask_camera.near = _camera.near
	_mask_camera.far = _camera.far
	_mask_camera.h_offset = _camera.h_offset
	_mask_camera.v_offset = _camera.v_offset


## Hears of everything that is added to the scene: what is added under the
## Cabin node (an item bought, what he carries, a passenger) is of the cabin.
func _listen() -> void:
	var tree: SceneTree = get_tree()
	if not tree.node_added.is_connected(_on_node_added):
		tree.node_added.connect(_on_node_added)


func _on_node_added(node: Node) -> void:
	if _mask != null and is_instance_valid(_cabin) and node is GeometryInstance3D and _cabin.is_ancestor_of(node):
		_mark(node)


## Puts what is drawn under the Cabin node on the cabin's layer.
func _mark_cabin() -> void:
	if _mask != null and is_instance_valid(_cabin):
		_mark(_cabin)


func _mark(node: Node) -> void:
	var thing: GeometryInstance3D = node as GeometryInstance3D
	if thing != null:
		if _on_the_nose(thing):
			thing.layers &= ~CABIN_LAYER
		else:
			thing.layers |= CABIN_LAYER
	for child: Node in node.get_children():
		_mark(child)


## What the car carries before its windscreen (the hood, a bull bar, fog
## lamps) he sees through the glass, like the road: it is not of the cabin.
## Such a thing stands where it is put, so where it is when it is added says
## it. Who stands beside the car (a vendor, a hitcher) is not on its nose.
func _on_the_nose(thing: GeometryInstance3D) -> bool:
	if not thing.is_inside_tree() or not _cabin.is_inside_tree():
		return false
	var at: Vector3 = _cabin.global_transform.affine_inverse() * (thing.global_transform * thing.get_aabb().get_center())
	return at.z < _windscreen_z and at.x > _windscreen.x and at.x < _windscreen.z


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
