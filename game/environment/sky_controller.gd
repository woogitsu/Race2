## Sun, sky, fog, ambient light and rain. Time of day drives the sun position and
## sky palette continuously, so transitions between dawn, day, dusk and night are
## smooth. Rain raises the wetness value shared with the road and car physics.
class_name SkyController
extends Node3D

const DAY_TOP := Color(0.24, 0.44, 0.86)
const DAY_HORIZON := Color(0.66, 0.80, 0.93)
const SUNSET_TOP := Color(0.22, 0.24, 0.48)
const SUNSET_HORIZON := Color(1.0, 0.56, 0.32)
const NIGHT_TOP := Color(0.01, 0.015, 0.04)
const NIGHT_HORIZON := Color(0.05, 0.07, 0.12)
const RAIN_TOP := Color(0.36, 0.39, 0.43)
const RAIN_HORIZON := Color(0.55, 0.58, 0.62)

var time_hours: float = 16.8
## Hours of in-game time per real second. 0 keeps the light fixed (late afternoon).
var time_speed: float = 0.0
var rain_target: float = 0.0
var rain_amount: float = 0.0

var world_env: WorldEnvironment
var environment: Environment
var sky_material: ProceduralSkyMaterial
var sun: DirectionalLight3D
var rain: GPUParticles3D
var _rain_material: ParticleProcessMaterial


func _ready() -> void:
	sky_material = ProceduralSkyMaterial.new()
	sky_material.sun_angle_max = 1.8
	sky_material.sun_curve = 0.06
	var sky := Sky.new()
	sky.sky_material = sky_material

	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.8
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.0
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	environment.fog_density = 0.0010
	environment.glow_enabled = true
	environment.glow_intensity = 0.25
	environment.glow_bloom = 0.05
	environment.glow_hdr_threshold = 1.0
	environment.adjustment_enabled = true
	environment.adjustment_contrast = 1.05
	environment.adjustment_saturation = 1.08

	world_env = WorldEnvironment.new()
	world_env.environment = environment
	add_child(world_env)

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_max_distance = 260.0
	sun.directional_shadow_split_1 = 0.08
	sun.directional_shadow_split_2 = 0.25
	sun.directional_shadow_split_3 = 0.6
	add_child(sun)

	_build_rain()
	_apply(0.0)


func _build_rain() -> void:
	rain = GPUParticles3D.new()
	rain.name = "Rain"
	rain.amount = 900
	rain.lifetime = 0.9
	rain.preprocess = 0.9
	rain.emitting = false
	rain.visibility_aabb = AABB(Vector3(-40, -30, -40), Vector3(80, 60, 80))
	_rain_material = ParticleProcessMaterial.new()
	_rain_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_rain_material.emission_box_extents = Vector3(30.0, 1.0, 30.0)
	_rain_material.direction = Vector3(0.12, -1.0, 0.05)
	_rain_material.spread = 4.0
	_rain_material.initial_velocity_min = 14.0
	_rain_material.initial_velocity_max = 18.0
	_rain_material.gravity = Vector3(0, -9.8, 0)
	rain.process_material = _rain_material
	var streak := QuadMesh.new()
	streak.size = Vector2(0.03, 0.7)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.8, 0.85, 0.95, 0.22)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	streak.material = mat
	rain.draw_pass_1 = streak
	add_child(rain)


## Advances time and weather. follow_point keeps the rain volume over the camera.
func update(delta: float, follow_point: Vector3) -> void:
	time_hours = fposmod(time_hours + time_speed * delta, 24.0)
	rain_amount = move_toward(rain_amount, rain_target, delta * 0.18)
	rain.global_position = follow_point + Vector3(0.0, 14.0, 0.0)
	rain.emitting = rain_amount > 0.02
	rain.amount_ratio = clampf(rain_amount, 0.05, 1.0)
	_apply(delta)


## Sun elevation in radians; negative below the horizon.
func sun_elevation() -> float:
	return sin((time_hours - 6.0) / 12.0 * PI) * 1.2


## 0 in full daylight, 1 at night; eases through dusk and dawn.
func night_amount() -> float:
	return 1.0 - smoothstep(-0.1, 0.2, sin(sun_elevation()))


func _apply(_delta: float) -> void:
	var e: float = sun_elevation()
	var azimuth: float = (time_hours - 6.0) / 12.0 * PI
	var to_sun := Vector3(cos(e) * cos(azimuth), sin(e), cos(e) * sin(azimuth) + 0.3)
	to_sun = to_sun.normalized()
	sun.global_transform = Transform3D(Basis.looking_at(-to_sun, Vector3.UP), Vector3.ZERO)

	var day: float = smoothstep(-0.05, 0.25, sin(e))
	var dusk: float = 1.0 - absf(sin(e) - 0.08) / 0.4
	dusk = clampf(dusk, 0.0, 1.0)
	var sun_warm: Color = Color(1.0, 0.8, 0.58).lerp(Color(1.0, 0.97, 0.92), smoothstep(0.0, 0.6, sin(e)))
	sun.light_color = sun_warm
	sun.light_energy = lerpf(0.0, 1.25, day) * (1.0 - rain_amount * 0.55)

	var top: Color = NIGHT_TOP.lerp(DAY_TOP, day)
	var horizon: Color = NIGHT_HORIZON.lerp(DAY_HORIZON, day)
	top = top.lerp(SUNSET_TOP, dusk * 0.6)
	horizon = horizon.lerp(SUNSET_HORIZON, dusk)
	top = top.lerp(RAIN_TOP, rain_amount * 0.85)
	horizon = horizon.lerp(RAIN_HORIZON, rain_amount * 0.85)

	sky_material.sky_top_color = top
	sky_material.sky_horizon_color = horizon
	sky_material.ground_horizon_color = horizon.darkened(0.25)
	sky_material.ground_bottom_color = Color(0.08, 0.07, 0.06).lerp(Color(0.02, 0.02, 0.02), 1.0 - day)
	sky_material.sky_energy_multiplier = lerpf(0.25, 1.0, day)

	environment.fog_light_color = horizon
	environment.fog_density = lerpf(0.0009, 0.0021, rain_amount)
	environment.ambient_light_energy = lerpf(0.4, 0.85, day) * (1.0 - rain_amount * 0.2)
	environment.adjustment_saturation = lerpf(1.02, 0.92, rain_amount)


## Call when the view distance changes with the quality profile.
func set_view_distance(distance: float) -> void:
	sun.directional_shadow_max_distance = clampf(distance * 0.22, 120.0, 320.0)
