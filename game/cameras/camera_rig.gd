## Camera with seven modes. Follow modes use exponential smoothing that is
## independent of frame rate, avoid geometry by a ray test, and widen the field of
## view with speed. Cockpit, hood and bumper views are rigidly attached to the car.
class_name CameraRig
extends Node3D

enum Mode { CHASE, SPORT, COCKPIT, HOOD, BUMPER, CINEMATIC, FREE }

const MODE_NAMES: PackedStringArray = [
	"Pościg", "Sportowa", "Kokpit", "Nad maską", "Zderzak", "Filmowa", "Swobodna",
]

var camera: Camera3D
var mode: int = Mode.CHASE
var _pos: Vector3 = Vector3.ZERO
var _look: Vector3 = Vector3.ZERO
var _initialized: bool = false
var _orbit_time: float = 0.0
var _free_yaw: float = 0.0
var _free_pitch: float = -0.12
var _free_pos: Vector3 = Vector3(0.0, 3.0, 8.0)
var _roll: float = 0.0


func _ready() -> void:
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.near = 0.12
	camera.far = 3000.0
	camera.current = true
	add_child(camera)


func mode_name() -> String:
	return MODE_NAMES[mode]


func cycle_mode() -> void:
	mode = (mode + 1) % MODE_NAMES.size()
	_initialized = false


func set_mode(value: int) -> void:
	mode = clampi(value, 0, MODE_NAMES.size() - 1)
	_initialized = false


## Keeps smoothing state consistent after a floating-origin shift.
func shift_origin(shift: Vector3) -> void:
	global_position -= shift
	_pos -= shift
	_look -= shift
	_free_pos -= shift


## car: the vehicle node (interpolated transform is used). body: VehicleController.
## free_input: x = turn, y = forward speed for the free camera.
func update(delta: float, car: Node3D, body: VehicleController, free_input: Vector2) -> void:
	var xf: Transform3D = car.get_global_transform_interpolated()
	var origin: Vector3 = xf.origin
	var fwd: Vector3 = -xf.basis.z
	var yaw: float = atan2(-fwd.x, -fwd.z)
	var yaw_basis := Basis(Vector3.UP, yaw)
	var speed_factor: float = clampf(body.speed_kmh / 300.0, 0.0, 1.0)
	var target_roll: float = clampf(-body.lateral_accel * 0.0025, -0.05, 0.05)
	_roll = lerpf(_roll, target_roll, 1.0 - exp(-delta * 6.0))

	match mode:
		Mode.CHASE:
			_follow(delta, origin, yaw_basis, Vector3(0.0, 1.7, 7.0), Vector3(0.0, 0.9, -8.0), 7.0)
			camera.fov = 66.0 + 10.0 * speed_factor
		Mode.SPORT:
			_follow(delta, origin, yaw_basis, Vector3(0.0, 1.05, 4.7), Vector3(0.0, 0.7, -10.0), 11.0)
			camera.fov = 60.0 + 12.0 * speed_factor
		Mode.COCKPIT:
			_attached(xf, Vector3(-0.36, 1.02, -0.22), Vector3(-0.36, 0.95, -20.0))
			camera.fov = 72.0 + 4.0 * speed_factor
		Mode.HOOD:
			_attached(xf, Vector3(0.0, 1.02, -1.15), Vector3(0.0, 0.8, -25.0))
			camera.fov = 70.0 + 6.0 * speed_factor
		Mode.BUMPER:
			_attached(xf, Vector3(0.0, 0.32, -2.5), Vector3(0.0, 0.45, -30.0))
			camera.fov = 78.0 + 6.0 * speed_factor
		Mode.CINEMATIC:
			_orbit_time += delta
			var a: float = _orbit_time * 0.18
			var desired: Vector3 = origin + Vector3(cos(a) * 10.0, 2.4, sin(a) * 10.0)
			_smooth_to(delta, desired, origin + Vector3(0.0, 0.7, 0.0), 2.5)
			camera.fov = 42.0
		Mode.FREE:
			_free_update(delta, origin, free_input)
			camera.fov = 58.0

	camera.global_position = _pos
	if (_look - _pos).length_squared() > 1e-6:
		camera.look_at(_look, Vector3.UP)
	# Lean into lateral acceleration after aiming (look_at would otherwise reset it).
	camera.rotate_object_local(Vector3.FORWARD, _roll)


func _follow(delta: float, origin: Vector3, yaw_basis: Basis, offset: Vector3, look_offset: Vector3,
		rate: float) -> void:
	var desired: Vector3 = origin + yaw_basis * offset
	var look: Vector3 = origin + yaw_basis * look_offset
	desired = _avoid_geometry(origin + Vector3(0.0, 0.8, 0.0), desired)
	if not _initialized:
		_pos = desired
		_look = look
		_initialized = true
	else:
		_smooth_to(delta, desired, look, rate)


func _attached(xf: Transform3D, local_pos: Vector3, local_look: Vector3) -> void:
	_pos = xf * local_pos
	_look = xf * local_look
	_initialized = true


func _smooth_to(delta: float, desired: Vector3, look: Vector3, rate: float) -> void:
	var k: float = 1.0 - exp(-delta * rate)
	_pos = _pos.lerp(desired, k)
	_look = _look.lerp(look, k)


func _free_update(delta: float, origin: Vector3, input: Vector2) -> void:
	if not _initialized:
		_free_pos = origin + Vector3(0.0, 3.0, 8.0)
		_initialized = true
	_free_yaw -= input.x * delta * 1.2
	var forward := Vector3(-sin(_free_yaw), 0.0, -cos(_free_yaw))
	_free_pos += forward * input.y * delta * 25.0
	_pos = _free_pos
	_look = _free_pos + Vector3(-sin(_free_yaw) * cos(_free_pitch), sin(_free_pitch), -cos(_free_yaw) * cos(_free_pitch)) * 10.0


## Pulls the camera in front of any geometry between the car and its desired spot.
func _avoid_geometry(from: Vector3, to: Vector3) -> Vector3:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	if space == null:
		return to
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	var hit: Dictionary = space.intersect_ray(q)
	if hit.is_empty():
		return to
	return (hit["position"] as Vector3) + (from - to).normalized() * 0.35
