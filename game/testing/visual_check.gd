## Renders the real game scene and saves screenshots of each stage. Needs a display:
##   xvfb-run -a godot --path game --rendering-method gl_compatibility -s res://testing/visual_check.gd -- <output_dir>
## Screenshots are written to <output_dir>. Exits with status 1 if the game never starts driving.
## While driving, a road-following autopilot steers so that the asphalt stays in view.
extends SceneTree

var _out_dir: String = ""
var _main: Node = null


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	_out_dir = args[0] if args.size() > 0 else "user://screens"
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred()


func _run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	_main = scene.instantiate()
	root.add_child(_main)
	for i in range(180):
		await process_frame
	await _shot("01_menu.png")

	_main._on_start()
	var started: bool = false
	for i in range(900):
		await process_frame
		if _main.state == 2:
			started = true
			break
	print("driving started: %s, streamer chunks %d" % [str(started), _main.streamer.chunk_count()])

	await _drive(120 * 4, 60.0)
	await _shot("02_driving_chase.png")
	print("after 4 s of throttle: %.1f km/h, distance %.1f m" % [_main.vehicle.speed_kmh, _main.session.odometer_m])

	await _drive(120 * 3, 60.0)
	await _shot("03_driving_curve.png")

	_main.camera_rig.set_mode(2)
	await _drive(40, 60.0)
	await _shot("04_cockpit.png")

	_main.camera_rig.set_mode(3)
	await _drive(40, 60.0)
	await _shot("05_hood.png")

	_main.camera_rig.set_mode(1)
	_main.sky.rain_target = 1.0
	await _drive(60 * 6, 50.0)
	await _shot("06_rain_sport.png")

	_main.sky.rain_target = 0.0
	_main.sky.time_hours = 21.2
	_main.camera_rig.set_mode(0)
	await _drive(60, 40.0)
	await _shot("07_night.png")

	_main.sky.time_hours = 6.6
	await _drive(30, 40.0)
	await _shot("08_dawn.png")

	print("final: speed %.1f km/h, chunks %d, distance %.1f m, state %d, on ground %d" % [
		_main.vehicle.speed_kmh, _main.streamer.chunk_count(), _main.session.odometer_m, _main.state,
		_main.vehicle.wheels_on_ground])
	quit(0 if started else 1)


## Drives for a number of frames with a steady throttle and road-following steering.
func _drive(frames: int, target_kmh: float) -> void:
	for i in range(frames):
		var proj: Dictionary = _main.streamer.project(_main.vehicle.position)
		var err: float = target_kmh - _main.vehicle.speed_kmh
		_main.driver.touch_throttle = clampf(err * 0.2 + 0.2, 0.0, 1.0)
		_main.driver.touch_brake = clampf(-err * 0.15, 0.0, 1.0)
		_main.driver.touch_steer = RoadAutopilot.steer_command(-_main.vehicle.global_transform.basis.z, proj)
		await process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	var path: String = _out_dir.path_join(name)
	var err: int = img.save_png(path)
	print("screenshot %s (%dx%d) err=%d" % [path, img.get_width(), img.get_height(), err])
