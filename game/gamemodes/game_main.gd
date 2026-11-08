## Root of the game: wires the modules together and runs the session state machine.
##
## MENU     start screen; the car is parked on the road and the camera orbits it.
## LOADING  the first road chunks are being built; the car is still frozen.
## PLAYING  driving; input, streaming, HUD and audio run every frame.
## PAUSED   car frozen; progress is checkpointed to disk.
class_name GameMain
extends Node3D

enum State { MENU, LOADING, PLAYING, PAUSED }

const CHECKPOINT_INTERVAL_S: float = 30.0

var state: int = State.MENU
var profile: Dictionary = {}
var streamer: WorldStreamer
var sky: SkyController
var vehicle: VehicleController
var camera_rig: CameraRig
var driver: DriverInput
var touch: TouchOverlay
var hud: Hud
var menu: MainMenu
var engine_sound: EngineSound
var quality := QualityManager.new()
var session := EndlessDriveMode.new()
var car_spec: Dictionary = {}
var _headlights: Array = []

var _checkpoint_odometer: float = 0.0
var _checkpoint_time: float = 0.0
var _last_checkpoint_clock: float = 0.0
var _clock: float = 0.0


func _ready() -> void:
	sky = SkyController.new()
	sky.name = "Sky"
	add_child(sky)

	streamer = WorldStreamer.new()
	streamer.name = "World"
	add_child(streamer)
	streamer.setup(int(SaveSystem.get_setting("world_seed")), GameConfig.quality_profile(2))

	camera_rig = CameraRig.new()
	camera_rig.name = "CameraRig"
	add_child(camera_rig)

	driver = DriverInput.new()
	driver.name = "Driver"
	add_child(driver)

	engine_sound = EngineSound.new()
	engine_sound.name = "EngineSound"
	add_child(engine_sound)

	var ui := CanvasLayer.new()
	ui.name = "UI"
	ui.layer = 10
	add_child(ui)
	touch = TouchOverlay.new()
	touch.name = "Touch"
	touch.bind(driver)
	ui.add_child(touch)
	hud = Hud.new()
	hud.name = "Hud"
	ui.add_child(hud)
	hud.hide()
	hud.pause_pressed.connect(_pause)
	hud.camera_pressed.connect(_cycle_camera)
	hud.reset_pressed.connect(_reset_car)
	hud.shift_up_pressed.connect(func() -> void: _request_shift(true))
	hud.shift_down_pressed.connect(func() -> void: _request_shift(false))
	menu = MainMenu.new()
	menu.name = "Menu"
	ui.add_child(menu)
	menu.start_requested.connect(_on_start)
	menu.resume_requested.connect(_on_resume)
	menu.end_session_requested.connect(_end_session)

	_apply_quality(int(SaveSystem.get_setting("quality")))
	_spawn_car(str(SaveSystem.get_setting("car_id")))
	camera_rig.set_mode(CameraRig.Mode.CINEMATIC)
	_apply_weather()
	sky.time_speed = 0.0
	menu.show_start()
	state = State.MENU


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		if state == State.PLAYING:
			_pause()
		_checkpoint()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		_checkpoint()


func _process(delta: float) -> void:
	_clock += delta
	# Touch steering/pedals only exist while driving, so menu buttons stay tappable.
	touch.visible = state == State.PLAYING
	var proj: Dictionary = streamer.update_streaming(vehicle.position, vehicle.forward_speed)
	match state:
		State.LOADING:
			if streamer.ready_around(streamer.current_index, 2):
				_activate_driving()
		State.PLAYING:
			_drive_frame(delta, proj)
		_:
			pass

	var free_input := Vector2(driver.steer, driver.throttle - driver.brake)
	camera_rig.update(delta, vehicle, vehicle, free_input)
	sky.update(delta, camera_rig.global_position)
	quality.tick(delta, get_viewport())
	vehicle.wetness = sky.rain_amount
	var night: float = sky.night_amount()
	for lamp in _headlights:
		(lamp as SpotLight3D).light_energy = night * 6.0
	WorldMaterials.set_wetness(sky.rain_amount)
	driver.consume_edges()


func _drive_frame(delta: float, proj: Dictionary) -> void:
	var scheme: int = int(SaveSystem.get_setting("control_scheme"))
	var sens: float = float(SaveSystem.get_setting("steer_sensitivity"))
	driver.poll(scheme, sens, true)
	touch.sensitivity = sens

	vehicle.input_steer = driver.steer
	vehicle.input_throttle = driver.throttle
	vehicle.input_brake = driver.brake
	vehicle.input_handbrake = driver.handbrake
	vehicle.assist_abs = bool(SaveSystem.get_setting("abs_enabled"))
	vehicle.assist_tc = bool(SaveSystem.get_setting("tc_enabled"))
	vehicle.assist_esc = bool(SaveSystem.get_setting("esc_enabled"))
	var auto: bool = bool(SaveSystem.get_setting("auto_gearbox"))
	if vehicle.is_auto_gearbox() != auto:
		vehicle.set_auto_gearbox(auto)
		hud.set_manual_mode(not auto)

	if driver.pressed_camera:
		_cycle_camera()
	if driver.pressed_reset:
		_reset_car()
	if driver.pressed_shift_up:
		_request_shift(true)
	if driver.pressed_shift_down:
		_request_shift(false)
	if driver.pressed_pause:
		_pause()
		return

	session.update(delta, vehicle.forward_speed)
	hud.update_telemetry({
		"speed_kmh": vehicle.speed_kmh,
		"rpm": vehicle.rpm,
		"redline": vehicle.engine.redline,
		"gear": vehicle.gear,
		"distance_km": session.distance_km(),
		"time_s": session.session_time_s,
		"mode": CameraRig.MODE_NAMES[camera_rig.mode],
		"abs": vehicle.abs_active,
		"tc": vehicle.tc_active,
		"esc": vehicle.esc_active,
		"abs_enabled": vehicle.assist_abs,
		"tc_enabled": vehicle.assist_tc,
		"esc_enabled": vehicle.assist_esc,
		"auto_gearbox": vehicle.is_auto_gearbox(),
	})
	engine_sound.set_state(vehicle.rpm, driver.throttle)
	_check_origin_shift()
	if vehicle.position.y < -30.0:
		_reset_car()
	if _clock - _last_checkpoint_clock > CHECKPOINT_INTERVAL_S:
		_checkpoint()


func _spawn_car(car_id: String) -> void:
	if vehicle != null:
		vehicle.queue_free()
		vehicle = null
	car_spec = CarCatalog.by_id(car_id)
	vehicle = VehicleController.new()
	vehicle.name = "Car"
	add_child(vehicle)
	var built: Dictionary = CarModelBuilder.build(car_spec)
	vehicle.add_child(built["body"])
	var visuals: Array = []
	for w in built["wheels"]:
		vehicle.add_child(w["pivot"])
		visuals.append({"pivot": w["pivot"], "spin": w["spin"]})
	vehicle.configure(car_spec, visuals)
	vehicle.set_active(false)
	_headlights.clear()
	for side in [-1.0, 1.0]:
		var lamp := SpotLight3D.new()
		lamp.name = "Headlight"
		lamp.position = Vector3(side * 0.62, 0.12, -2.2)
		lamp.light_color = Color(1.0, 0.95, 0.85)
		lamp.light_energy = 0.0
		lamp.spot_range = 70.0
		lamp.spot_angle = 30.0
		lamp.spot_attenuation = 0.6
		lamp.shadow_enabled = false
		vehicle.add_child(lamp)
		_headlights.append(lamp)
	vehicle.reset_to(Transform3D(Basis(), Vector3(0.0, VehicleController.rest_height_for(car_spec), 0.0)))


func _apply_quality(index: int) -> void:
	profile = quality.apply(index, get_viewport(), sky.sun)
	streamer.set_profile(profile)
	sky.set_view_distance(float(profile["view_distance"]))
	camera_rig.camera.far = float(profile["view_distance"]) * 1.25


func _apply_weather() -> void:
	var rain: bool = bool(SaveSystem.get_setting("rain"))
	sky.rain_target = 1.0 if rain else 0.0


func _on_start() -> void:
	var car_id: String = menu.selected_car_id()
	SaveSystem.set_setting("car_id", car_id)
	if str(car_spec.get("id", "")) != car_id:
		_spawn_car(car_id)
	_apply_quality(int(SaveSystem.get_setting("quality")))
	_apply_weather()
	session.reset()
	SaveSystem.begin_session()
	_checkpoint_odometer = 0.0
	_checkpoint_time = 0.0
	_last_checkpoint_clock = _clock
	vehicle.set_auto_gearbox(bool(SaveSystem.get_setting("auto_gearbox")))
	hud.set_manual_mode(not bool(SaveSystem.get_setting("auto_gearbox")))
	_reset_car()
	camera_rig.set_mode(CameraRig.Mode.CHASE)
	hud.show()
	menu.show_loading()
	state = State.LOADING


func _activate_driving() -> void:
	vehicle.set_active(true)
	menu.hide()
	menu.hide_loading()
	state = State.PLAYING


func _on_resume() -> void:
	_apply_quality(int(SaveSystem.get_setting("quality")))
	_apply_weather()
	menu.hide()
	hud.show()
	vehicle.set_active(true)
	state = State.PLAYING


func _pause() -> void:
	if state != State.PLAYING:
		return
	state = State.PAUSED
	vehicle.set_active(false)
	hud.hide()
	_checkpoint()
	menu.show_pause()


func _end_session() -> void:
	_checkpoint()
	vehicle.set_active(false)
	hud.hide()
	camera_rig.set_mode(CameraRig.Mode.CINEMATIC)
	_reset_car()
	state = State.MENU
	menu.show_start()


## Writes progress since the last checkpoint.
func _checkpoint() -> void:
	if state == State.MENU:
		return
	var delta_d: float = session.odometer_m - _checkpoint_odometer
	var delta_t: float = session.session_time_s - _checkpoint_time
	SaveSystem.checkpoint(delta_d, delta_t, session.odometer_m, session.max_speed_kmh)
	_checkpoint_odometer = session.odometer_m
	_checkpoint_time = session.session_time_s
	_last_checkpoint_clock = _clock


func _cycle_camera() -> void:
	camera_rig.cycle_mode()


func _request_shift(up: bool) -> void:
	if vehicle.is_auto_gearbox():
		return
	if up:
		vehicle.request_shift_up()
	else:
		vehicle.request_shift_down()


## Places the car on the road at its projected position, facing along the road.
func _reset_car() -> void:
	var proj: Dictionary = streamer.project(vehicle.position)
	vehicle.reset_to(streamer.road_transform(proj, VehicleController.rest_height_for(car_spec)))


## Keeps the car near the scene origin so float32 precision stays high.
func _check_origin_shift() -> void:
	var p: Vector3 = vehicle.position
	var far_xz: float = maxf(absf(p.x), absf(p.z))
	if far_xz < GameConfig.FLOATING_ORIGIN_DISTANCE:
		return
	var shift: Vector3 = p
	vehicle.position -= shift
	vehicle.reset_physics_interpolation()
	streamer.shift_origin(shift)
	camera_rig.shift_origin(shift)
