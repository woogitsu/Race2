## Applies quality profiles and, in Auto mode, adapts the 3D render scale to the
## measured frame time: it lowers resolution after sustained overload and raises it
## again slowly once there is headroom. Dynamic resolution keeps the frame rate
## stable without changing the rest of the scene.
class_name QualityManager
extends RefCounted

const MIN_SCALE: float = 0.5
const OVER_MS: float = 18.0
const UNDER_MS: float = 11.5

var profile_index: int = 0
var profile: Dictionary = {}
var render_scale: float = 0.8
var avg_frame_ms: float = 16.0
var _over_time: float = 0.0
var _under_time: float = 0.0


func is_auto() -> bool:
	return profile_index == 0


## Applies a profile index (0 = Auto). Returns the active profile dictionary.
func apply(index: int, viewport: Viewport, sun: DirectionalLight3D) -> Dictionary:
	profile_index = clampi(index, 0, GameConfig.QUALITY_NAMES.size() - 1)
	var effective: int = profile_index if profile_index > 0 else _auto_start_index()
	profile = GameConfig.quality_profile(effective)
	render_scale = float(profile["scale3d"])
	viewport.scaling_3d_scale = render_scale
	viewport.msaa_3d = Viewport.MSAA_2X if int(profile["msaa"]) >= 2 else Viewport.MSAA_DISABLED
	RenderingServer.directional_shadow_atlas_set_size(int(profile["shadow_size"]), true)
	if sun != null:
		sun.shadow_enabled = bool(profile["shadows"])
	_over_time = 0.0
	_under_time = 0.0
	return profile


## Auto mode starts from Balanced; devices with few cores start one step lower.
func _auto_start_index() -> int:
	return 1 if OS.get_processor_count() <= 4 else 2


## Call once per frame with the frame delta in seconds.
func tick(delta: float, viewport: Viewport) -> void:
	avg_frame_ms = lerpf(avg_frame_ms, delta * 1000.0, 0.05)
	if not is_auto():
		return
	var target: float = float(profile["scale3d"])
	if avg_frame_ms > OVER_MS:
		_over_time += delta
		_under_time = 0.0
	elif avg_frame_ms < UNDER_MS:
		_under_time += delta
		_over_time = 0.0
	else:
		_over_time = 0.0
		_under_time = 0.0
	if _over_time > 1.5 and render_scale > MIN_SCALE:
		render_scale = maxf(MIN_SCALE, render_scale - 0.05)
		viewport.scaling_3d_scale = render_scale
		_over_time = 0.0
	elif _under_time > 4.0 and render_scale < target:
		render_scale = minf(target, render_scale + 0.03)
		viewport.scaling_3d_scale = render_scale
		_under_time = 0.0
