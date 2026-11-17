class_name PlaceholderFactory
extends RefCounted
## Builds what a thing looks like from data/placeholders.json (GDD 14, 16.1).
##
## Every visible object has an entry: a primitive (shape, size, flat colour)
## and an optional "scene". When "scene" is set the view instantiates it
## instead of the primitive, so an artist replaces any placeholder by editing
## the registry, with no code change (GDD 1.1).
##
## Sizes: box [x, y, z]; cylinder and capsule [radius, height]; sphere [radius];
## quad [width, height]; label [pixel size] with a "text" key.

const WORLD_SHADER: Shader = preload("res://shaders/world_bend.gdshader")
## The global shader parameters of the world shader (project settings).
const GLOBAL_BEND: StringName = &"world_bend"
const GLOBAL_BEND_ORIGIN: StringName = &"world_bend_origin_z"
const GLOBAL_FOG_COLOR: StringName = &"world_fog_color"
const GLOBAL_FOG_NEAR: StringName = &"world_fog_near"
const GLOBAL_FOG_FAR: StringName = &"world_fog_far"
## A distance no road reaches: fog that begins here hides nothing.
const NO_FOG: float = 1.0e9

var _registry: Dictionary = {}
var _materials: Dictionary = {}
## Materials of things outside the cabin, which bend with the road.
var _world_materials: Dictionary = {}
var _bend: float = 0.0
var _bend_origin_z: float = 0.0
var _fog_color: Color = Color.BLACK
var _fog_near: float = NO_FOG
var _fog_far: float = NO_FOG * 2.0


func _init(data: GameData) -> void:
	_registry = data.root("placeholders")


func has(id: String) -> bool:
	return _registry.has(id)


## A new node for something outside the cabin: drawn with the world-bend
## shader so it follows the curve of the road (GDD 13.5).
func make_world(id: String) -> Node3D:
	var node: Node3D = make(id)
	_use_world_material(node, false)
	return node


## The same for a light (a head lamp, a tail lamp, a beacon): it shows
## through the dark and the haze.
func make_world_light(id: String) -> Node3D:
	var node: Node3D = make(id)
	_use_world_material(node, true)
	return node


## Sets how the world bends this frame: sideways offset per metre ahead,
## squared, measured from `origin_z` toward -Z.
func set_world_bend(bend: float, origin_z: float) -> void:
	if bend == _bend and origin_z == _bend_origin_z:
		return
	_bend = bend
	_bend_origin_z = origin_z
	RenderingServer.global_shader_parameter_set(GLOBAL_BEND, bend)
	RenderingServer.global_shader_parameter_set(GLOBAL_BEND_ORIGIN, origin_z)


## Sets what hides the distance this frame: everything outside the cabin
## fades into `color` between `near` and `far` metres. Lights do not.
func set_world_fog(color: Color, near: float, far: float) -> void:
	if color == _fog_color and near == _fog_near and far == _fog_far:
		return
	_fog_color = color
	_fog_near = near
	_fog_far = far
	RenderingServer.global_shader_parameter_set(GLOBAL_FOG_COLOR, color)
	RenderingServer.global_shader_parameter_set(GLOBAL_FOG_NEAR, near)
	RenderingServer.global_shader_parameter_set(GLOBAL_FOG_FAR, far)


func world_material_for(color: Color, light: bool = false) -> ShaderMaterial:
	var key: String = color.to_html() + ("L" if light else "")
	if _world_materials.has(key):
		var cached: ShaderMaterial = _world_materials[key]
		return cached
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = WORLD_SHADER
	material.set_shader_parameter("albedo", color)
	material.set_shader_parameter("lit", 1.0 if light else 0.0)
	_world_materials[key] = material
	return material


func _use_world_material(node: Node, light: bool) -> void:
	var instance: MeshInstance3D = node as MeshInstance3D
	if instance != null:
		var flat: StandardMaterial3D = instance.material_override as StandardMaterial3D
		if flat != null:
			instance.material_override = world_material_for(flat.albedo_color, light)
	for child: Node in node.get_children():
		_use_world_material(child, light)


## A new node for this id. Unknown ids are an error and give an empty node.
func make(id: String) -> Node3D:
	if not _registry.has(id):
		push_error("PlaceholderFactory: no placeholder '%s'" % id)
		return Node3D.new()
	var entry: Dictionary = _registry[id]
	var scene_path: String = GameData.as_string(entry.get("scene"))
	if not scene_path.is_empty():
		var packed: PackedScene = load(scene_path) as PackedScene
		if packed != null:
			var instance: Node3D = packed.instantiate() as Node3D
			if instance != null:
				instance.name = id
				return instance
		push_error("PlaceholderFactory: scene '%s' for '%s' is not a 3D scene" % [scene_path, id])
	var node: Node3D = _primitive(GameData.as_dict(entry.get("placeholder")))
	node.name = id
	return node


func color_of(id: String) -> Color:
	if not _registry.has(id):
		push_error("PlaceholderFactory: no placeholder '%s'" % id)
		return Color.MAGENTA
	var entry: Dictionary = _registry[id]
	var spec: Dictionary = GameData.as_dict(entry.get("placeholder"))
	return Color.html(GameData.as_string(spec.get("color"), "#FF00FF"))


## The entry's size list, padded with zeros to three numbers.
func size_of(id: String) -> Vector3:
	if not _registry.has(id):
		push_error("PlaceholderFactory: no placeholder '%s'" % id)
		return Vector3.ZERO
	var entry: Dictionary = _registry[id]
	var spec: Dictionary = GameData.as_dict(entry.get("placeholder"))
	return _size(spec)


func material_for(color: Color) -> StandardMaterial3D:
	var key: String = color.to_html()
	if _materials.has(key):
		var cached: StandardMaterial3D = _materials[key]
		return cached
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	_materials[key] = material
	return material


func _size(spec: Dictionary) -> Vector3:
	var list: Array = GameData.as_array(spec.get("size"))
	var out: Vector3 = Vector3.ZERO
	for index: int in mini(list.size(), 3):
		out[index] = GameData.as_float(list[index])
	return out


func _primitive(spec: Dictionary) -> Node3D:
	var size: Vector3 = _size(spec)
	var color: Color = Color.html(GameData.as_string(spec.get("color"), "#FF00FF"))
	var shape: String = GameData.as_string(spec.get("shape"))
	if shape == "label":
		var label: Label3D = Label3D.new()
		label.text = GameData.as_string(spec.get("text"))
		label.modulate = color
		if size.x > 0.0:
			label.pixel_size = size.x
		return label
	var mesh: Mesh = null
	match shape:
		"box":
			var box: BoxMesh = BoxMesh.new()
			box.size = size
			mesh = box
		"cylinder":
			var cylinder: CylinderMesh = CylinderMesh.new()
			cylinder.top_radius = size.x
			cylinder.bottom_radius = size.x
			cylinder.height = size.y
			mesh = cylinder
		"capsule":
			var capsule: CapsuleMesh = CapsuleMesh.new()
			capsule.radius = size.x
			capsule.height = maxf(size.y, size.x * 2.0)
			mesh = capsule
		"sphere":
			var sphere: SphereMesh = SphereMesh.new()
			sphere.radius = size.x
			sphere.height = size.x * 2.0
			mesh = sphere
		"quad":
			var quad: QuadMesh = QuadMesh.new()
			quad.size = Vector2(size.x, size.y)
			mesh = quad
		_:
			push_error("PlaceholderFactory: unknown shape '%s'" % shape)
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material_for(color)
	return instance
