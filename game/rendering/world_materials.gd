## Shared material instances for the world. Created lazily on the main thread and
## reused by every chunk, so no per-chunk material allocation happens.
class_name WorldMaterials
extends RefCounted

static var _noise: NoiseTexture2D = null
static var _asphalt: ShaderMaterial = null
static var _terrain: ShaderMaterial = null
static var _markings: StandardMaterial3D = null
static var _rail: StandardMaterial3D = null


static func noise_texture() -> NoiseTexture2D:
	if _noise == null:
		var fnl := FastNoiseLite.new()
		fnl.noise_type = FastNoiseLite.TYPE_PERLIN
		fnl.frequency = 0.045
		fnl.fractal_type = FastNoiseLite.FRACTAL_FBM
		fnl.fractal_octaves = 4
		_noise = NoiseTexture2D.new()
		_noise.width = 256
		_noise.height = 256
		_noise.seamless = true
		_noise.noise = fnl
	return _noise


static func asphalt() -> ShaderMaterial:
	if _asphalt == null:
		_asphalt = ShaderMaterial.new()
		_asphalt.shader = load("res://rendering/shaders/asphalt.gdshader")
		_asphalt.set_shader_parameter("noise_tex", noise_texture())
	return _asphalt


static func terrain() -> ShaderMaterial:
	if _terrain == null:
		_terrain = ShaderMaterial.new()
		_terrain.shader = load("res://rendering/shaders/terrain.gdshader")
		_terrain.set_shader_parameter("noise_tex", noise_texture())
	return _terrain


static func markings() -> StandardMaterial3D:
	if _markings == null:
		_markings = StandardMaterial3D.new()
		_markings.vertex_color_use_as_albedo = true
		_markings.roughness = 0.55
		_markings.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _markings


static func rail() -> StandardMaterial3D:
	if _rail == null:
		_rail = StandardMaterial3D.new()
		_rail.vertex_color_use_as_albedo = true
		_rail.metallic = 0.85
		_rail.roughness = 0.35
		_rail.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _rail


## Sets the wetness of every asphalt chunk at once.
static func set_wetness(value: float) -> void:
	asphalt().set_shader_parameter("wetness", clampf(value, 0.0, 1.0))
