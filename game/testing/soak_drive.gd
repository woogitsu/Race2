## Long-run soak test: the autopilot drives a long distance on the generated road while
## memory, live chunk count and road-following error are logged. Use it to check that
## memory stays bounded during long drives (not part of the quick test suite).
##   godot --headless --path game -s res://testing/soak_drive.gd -- <distance_m> <speed_kmh>
extends SceneTree

var _distance_goal: float = 5000.0
var _target_kmh: float = 100.0


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		_distance_goal = float(args[0])
	if args.size() > 1:
		_target_kmh = float(args[1])
	_run.call_deferred()


func _run() -> void:
	var streamer := WorldStreamer.new()
	root.add_child(streamer)
	streamer.setup(20260501, GameConfig.quality_profile(2))
	var spec: Dictionary = CarCatalog.vanta_gt()
	var car := VehicleController.new()
	root.add_child(car)
	var built: Dictionary = CarModelBuilder.build(spec)
	car.add_child(built["body"])
	var visuals: Array = []
	for w in built["wheels"]:
		car.add_child(w["pivot"])
		visuals.append({"pivot": w["pivot"], "spin": w["spin"]})
	car.configure(spec, visuals)
	car.reset_to(Transform3D(Basis(), Vector3(0.0, VehicleController.rest_height_for(spec), 0.0)))
	car.set_active(true)

	var t0: int = Time.get_ticks_msec()
	var next_report: float = 500.0
	var max_lat: float = 0.0
	var airborne: int = 0
	var progress: float = 0.0
	var mem_first: float = -1.0
	var mem_max: float = 0.0
	var frames: int = 0
	var stall_ticks: int = 0
	var last_progress: float = 0.0
	while progress < _distance_goal:
		var proj: Dictionary = streamer.update_streaming(car.position, car.forward_speed)
		car.input_steer = RoadAutopilot.steer_command(-car.global_transform.basis.z, proj, car.yaw_rate)
		var err: float = RoadAutopilot.target_speed_kmh(proj, _target_kmh) - car.speed_kmh
		car.input_throttle = clampf(err * 0.2 + 0.2, 0.0, 1.0)
		car.input_brake = clampf(-err * 0.15, 0.0, 1.0)
		await physics_frame
		frames += 1
		max_lat = maxf(max_lat, absf(float(proj["lateral"])))
		if car.wheels_on_ground < 3:
			airborne += 1
		progress = maxf(progress, float(proj["distance"]))
		# Stop early if the car leaves the road for good (it should not with this driver).
		if progress - last_progress < 0.001:
			stall_ticks += 1
		else:
			stall_ticks = 0
			last_progress = progress
		if stall_ticks > 120 * 20:
			print("STALLED at %.0f m, speed %.1f km/h, lateral %.2f m" % [progress, car.speed_kmh, float(proj["lateral"])])
			break
		if progress >= next_report:
			var mem: float = float(OS.get_static_memory_usage()) / 1048576.0
			if mem_first < 0.0:
				mem_first = mem
			mem_max = maxf(mem_max, mem)
			print("progress %6.0f m  t=%5.1f s  speed %5.1f km/h  live chunks %2d  built %4d  pending %d  mem %6.1f MiB  max lat %.2f  airborne %d" % [
				progress, float(Time.get_ticks_msec() - t0) / 1000.0, car.speed_kmh, streamer.chunk_count(),
				streamer.total_chunks_built(), streamer.pending_count(), mem, max_lat, airborne])
			next_report += 500.0
	var elapsed: float = float(Time.get_ticks_msec() - t0) / 1000.0
	print("SOAK DONE: %.0f m in %.1f s wall time (%d ticks), memory first %.1f MiB, max %.1f MiB, max lateral %.2f m, airborne %d ticks" % [
		progress, elapsed, frames, mem_first, mem_max, max_lat, airborne])
	car.queue_free()
	streamer.queue_free()
	quit(0)
