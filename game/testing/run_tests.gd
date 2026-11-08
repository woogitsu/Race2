## Headless test suite. Run with:
##   godot --headless --path game -s res://testing/run_tests.gd
## Exit code 0 when every check passes, 1 otherwise. Output lists each check with
## the measured values, so numbers in reports come from actual runs.
extends SceneTree

const _save_script := preload("res://savesystem/save_system.gd")

var _passed: int = 0
var _failed: int = 0
var _report: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	_run_all.call_deferred()


func _run_all() -> void:
	print("== Infinite Drive test suite (Godot %s) ==" % Engine.get_version_info()["string"])
	test_all_scripts_compile()
	test_hash_noise()
	test_car_catalog()
	await test_road_determinism()
	test_road_continuity()
	test_road_1000_km()
	test_terrain_blend()
	test_chunk_builder()
	test_save_round_trip()
	await test_pacejka_sanity()
	await test_streamer_runtime()
	await test_streamer_road_projection()
	await test_car_acceleration()
	await test_car_braking()
	await test_car_steering()
	await test_car_rate_independence()
	await test_car_slope_hold()
	await test_car_wall_collision()
	await test_autopilot_follows_road()
	print("")
	for line in _report:
		print(line)
	print("RESULT: %d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


# ---------------------------------------------------------------- helpers

func _check(ok: bool, name: String, detail: String = "") -> void:
	var line: String = ("PASS  " if ok else "FAIL  ") + name
	if detail != "":
		line += "  [" + detail + "]"
	_report.append(line)
	if ok:
		_passed += 1
	else:
		_failed += 1


func _spawn_car(spec: Dictionary, pos: Transform3D) -> VehicleController:
	var car := VehicleController.new()
	root.add_child(car)
	var built: Dictionary = CarModelBuilder.build(spec)
	car.add_child(built["body"])
	var visuals: Array = []
	for w in built["wheels"]:
		car.add_child(w["pivot"])
		visuals.append({"pivot": w["pivot"], "spin": w["spin"]})
	car.configure(spec, visuals)
	car.reset_to(pos)
	car.set_active(true)
	return car


func _ground(xf: Transform3D, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	body.transform = xf
	root.add_child(body)
	return body


func _flat_ground() -> StaticBody3D:
	return _ground(Transform3D(Basis(), Vector3(0.0, -1.0, 0.0)), Vector3(3000.0, 2.0, 3000.0))


func _upright(car: VehicleController) -> bool:
	return car.global_transform.basis.y.y > 0.95


func _start_pos(spec: Dictionary, yaw: float = 0.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw), Vector3(0.0, VehicleController.rest_height_for(spec), 0.0))


func _drive_for(car: VehicleController, seconds: float, throttle: float, brake: float = 0.0, steer: float = 0.0) -> void:
	var steps: int = int(round(seconds * float(Engine.physics_ticks_per_second)))
	for i in range(steps):
		car.input_throttle = throttle
		car.input_brake = brake
		car.input_steer = steer
		await physics_frame


# ---------------------------------------------------------------- static checks

func test_all_scripts_compile() -> void:
	var failures: PackedStringArray = PackedStringArray()
	var count: int = 0
	for path in _list_scripts("res://"):
		count += 1
		var script: GDScript = load(path) as GDScript
		if script == null or not script.can_instantiate():
			failures.append(path)
	_check(failures.is_empty(), "all GDScript files compile", "%d files, %d failed %s" % [count, failures.size(), str(failures)])


func _list_scripts(dir_path: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		if name.begins_with("."):
			name = dir.get_next()
			continue
		var full: String = dir_path.path_join(name)
		if dir.current_is_dir():
			out.append_array(_list_scripts(full))
		elif name.ends_with(".gd"):
			out.append(full)
		name = dir.get_next()
	dir.list_dir_end()
	return out


func test_hash_noise() -> void:
	var ok_range: bool = true
	var ok_det: bool = true
	var sum: float = 0.0
	for i in range(2000):
		var x: float = float(i) * 0.37 - 300.0
		var v: float = HashNoise.value2(x, x * 0.7, 99)
		if v < -1.0 or v > 1.0:
			ok_range = false
		if v != HashNoise.value2(x, x * 0.7, 99):
			ok_det = false
		sum += absf(v)
	var differ: bool = HashNoise.value2(3.3, 1.1, 1) != HashNoise.value2(3.3, 1.1, 2)
	_check(ok_range and ok_det and differ, "hash noise: range, determinism, seed sensitivity",
		"mean |v| = %.3f" % (sum / 2000.0))


func test_car_catalog() -> void:
	var ok: bool = true
	for spec in CarCatalog.all():
		ok = ok and float(spec["mass"]) > 800.0 and float(spec["peak_torque"]) > 100.0
		ok = ok and (spec["gears"] as Array).size() >= 5
		ok = ok and float(spec["wheelbase"]) > 2.0 and float(spec["cg_height"]) < float(spec["height"])
	_check(ok and CarCatalog.all().size() == 3, "car catalogue: three validated cars", "%d cars" % CarCatalog.all().size())


# ---------------------------------------------------------------- road

func test_road_determinism() -> void:
	var a := RoadPath.new(42)
	var c30_a: RoadChunk = a.generate_chunk(30)
	var b := RoadPath.new(42)
	var c30_b: RoadChunk = b.generate_chunk(30)
	var c5_after: RoadChunk = a.generate_chunk(5)
	var c5_fresh: RoadChunk = RoadPath.new(42).generate_chunk(5)
	var diff30: float = _max_point_diff(c30_a, c30_b)
	var diff5: float = _max_point_diff(c5_after, c5_fresh)
	var other: RoadChunk = RoadPath.new(43).generate_chunk(30)
	var seed_diff: float = _max_point_diff(c30_a, other)
	_check(diff30 < 1e-9 and diff5 < 1e-9 and seed_diff > 1.0,
		"road is reproducible from seed, also when revisiting earlier chunks",
		"max diff %.9f / %.9f, other seed %.1f m" % [diff30, diff5, seed_diff])
	await process_frame


func _max_point_diff(c1: RoadChunk, c2: RoadChunk) -> float:
	var m: float = 0.0
	for k in range(c1.sample_count()):
		m = maxf(m, (c1.points[k] - c2.points[k]).length())
		m = maxf(m, absf(c1.headings[k] - c2.headings[k]))
	return m


func test_road_continuity() -> void:
	var path := RoadPath.new(7)
	var max_step_err: float = 0.0
	var max_turn_err: float = 0.0
	var max_kappa: float = 0.0
	var max_slope: float = 0.0
	var max_kappa_jump: float = 0.0
	var max_seam: float = 0.0
	var prev: RoadChunk = null
	for i in range(120):
		var c: RoadChunk = path.generate_chunk(i)
		for k in range(c.sample_count() - 1):
			var step: Vector3 = c.points[k + 1] - c.points[k]
			max_step_err = maxf(max_step_err, absf(Vector2(step.x, step.z).length() - GameConfig.SAMPLE_STEP))
			max_turn_err = maxf(max_turn_err, absf((c.headings[k + 1] - c.headings[k]) - c.curvatures[k] * GameConfig.SAMPLE_STEP))
			max_kappa_jump = maxf(max_kappa_jump, absf(c.curvatures[k + 1] - c.curvatures[k]))
		for k in range(c.sample_count()):
			max_kappa = maxf(max_kappa, absf(c.curvatures[k]))
			max_slope = maxf(max_slope, absf(c.slopes[k]))
		if prev != null:
			# The next anchor must equal the previous chunk's last sample, and headings must match.
			var end_prev: Vector3 = prev.points[GameConfig.SAMPLES_PER_CHUNK]
			var seam := Vector3(c.anchor[0] - prev.anchor[0] - end_prev.x,
				c.anchor[1] - prev.anchor[1] - end_prev.y,
				c.anchor[2] - prev.anchor[2] - end_prev.z)
			max_seam = maxf(max_seam, seam.length())
			max_seam = maxf(max_seam, absf(c.headings[0] - prev.headings[GameConfig.SAMPLES_PER_CHUNK]))
		prev = c
	_check(max_step_err < 1e-3, "road: samples are evenly spaced", "max error %.9f m" % max_step_err)
	_check(max_turn_err < 1e-4, "road: heading integrates curvature exactly", "max error %.9f rad" % max_turn_err)
	_check(max_kappa <= GameConfig.MAX_CURVATURE + 1e-9, "road: curvature within minimum radius",
		"max curvature 1/%.1f m (limit 1/%.0f m)" % [1.0 / maxf(max_kappa, 1e-9), GameConfig.MIN_TURN_RADIUS])
	_check(max_slope <= GameConfig.MAX_GRADE + 1e-9, "road: grade within limit", "max %.2f %%" % (max_slope * 100.0))
	_check(max_kappa_jump < 0.002, "road: curvature continuous (C1 tangent)", "max jump %.9f per 2 m" % max_kappa_jump)
	_check(max_seam < 1e-3, "road: chunk seams are exact", "max seam error %.9f" % max_seam)


func test_road_1000_km() -> void:
	var path := RoadPath.new(20260501)
	var t0: int = Time.get_ticks_msec()
	var max_k: float = 0.0
	var max_s: float = 0.0
	var finite: bool = true
	var min_turn_radius_seen: float = INF
	var last: RoadChunk = null
	var chunks: int = int(1000000.0 / GameConfig.CHUNK_LENGTH)
	for i in range(chunks):
		var c: RoadChunk = path.generate_chunk(i)
		for k in range(0, c.sample_count(), 5):
			var kap: float = absf(c.curvatures[k])
			max_k = maxf(max_k, kap)
			max_s = maxf(max_s, absf(c.slopes[k]))
			if kap > 1e-6:
				min_turn_radius_seen = minf(min_turn_radius_seen, 1.0 / kap)
		var p: Vector3 = c.points[GameConfig.SAMPLES_PER_CHUNK]
		if is_nan(p.x) or is_nan(p.z) or is_inf(p.x) or is_inf(p.z):
			finite = false
		last = c
	var elapsed_s: float = (Time.get_ticks_msec() - t0) / 1000.0
	var anchor_v := Vector3(last.anchor[0], last.anchor[1], last.anchor[2])
	var end_pos: Vector3 = anchor_v + last.points[GameConfig.SAMPLES_PER_CHUNK]
	_check(finite and last.index == chunks - 1, "road: 1000 km generated without NaN or overflow",
		"%d chunks, %.1f s, end %.0f m from start, boundaries cached %d" % [
			chunks, elapsed_s, end_pos.length(), path.cached_boundary_count()])
	_check(max_s <= GameConfig.MAX_GRADE + 1e-9 and max_k <= GameConfig.MAX_CURVATURE + 1e-9,
		"road: limits hold over 1000 km", "min radius %.1f m, max grade %.2f %%" % [min_turn_radius_seen, max_s * 100.0])
	await process_frame


func test_terrain_blend() -> void:
	var field := TerrainField.new(5)
	var road_y: float = 12.5
	var at_road: float = field.blended_height(100.0, -50.0, road_y, 0.0)
	var far: float = field.blended_height(100.0, -50.0, road_y, 90.0)
	var natural: float = field.natural_height(100.0, -50.0)
	_check(absf(at_road - road_y) < 1e-4 and absf(far - natural) < 1e-4,
		"terrain: ground meets road level at the asphalt and returns to natural terrain far away",
		"road %.2f, far %.2f, natural %.2f" % [at_road, far, natural])


func test_chunk_builder() -> void:
	var field := TerrainField.new(3)
	var path := RoadPath.new(3)
	var chunk: RoadChunk = path.generate_chunk(4)
	var t0: int = Time.get_ticks_usec()
	var payload_a: Dictionary = RoadChunkBuilder.build(chunk, field, 1.0)
	var build_ms: float = (Time.get_ticks_usec() - t0) / 1000.0
	var payload_b: Dictionary = RoadChunkBuilder.build(chunk, field, 1.0)
	var road: MeshBuilder = payload_a["road"]
	var terrain: MeshBuilder = payload_a["terrain"]
	var trees_a: Array = payload_a["trees"]
	var trees_b: Array = payload_b["trees"]
	var same_trees: bool = trees_a.size() == trees_b.size()
	if same_trees and not trees_a.is_empty():
		same_trees = (trees_a[0] as Transform3D).is_equal_approx(trees_b[0] as Transform3D)
	var road_y_ok: bool = true
	for k in range(chunk.sample_count()):
		var y_road: float = (road.verts[k * 7 + 3]).y - chunk.points[k].y
		if absf(y_road - 0.04) > 1e-3:
			road_y_ok = false
	_check(road.triangle_count() > 300 and terrain.triangle_count() > 2000 and not trees_a.is_empty(),
		"chunk builder: road, terrain and trees generated",
		"road %d tri, terrain %d tri, trees %d, build %.1f ms" % [
			road.triangle_count(), terrain.triangle_count(), trees_a.size(), build_ms])
	_check(same_trees and road_y_ok, "chunk builder: identical output for identical input, road sits on centreline",
		"trees repeat: %s" % str(same_trees))


# ---------------------------------------------------------------- persistence

func test_save_round_trip() -> void:
	var path: String = "user://test_save_roundtrip.json"
	var data: Dictionary = {"settings": {"quality": 3, "car_id": "kestrel_r", "steer_sensitivity": 1.25},
		"records": {"best_distance_m": 12345.5, "sessions": 4}}
	var wrote: bool = _save_script.write_file(path, data)
	var read_back: Dictionary = _save_script.read_file(path)
	var merged: Dictionary = _save_script._validated(_save_script.default_settings(), read_back.get("settings", {}))
	var ok_values: bool = int(merged["quality"]) == 3 and str(merged["car_id"]) == "kestrel_r" \
		and absf(float(merged["steer_sensitivity"]) - 1.25) < 1e-9 and bool(merged["abs_enabled"]) == true
	# Corrupt the file: wrong types must fall back to defaults instead of breaking the game.
	_save_script.write_file(path, {"settings": {"quality": "high", "car_id": 7}})
	var corrupt: Dictionary = _save_script.read_file(path)
	var safe: Dictionary = _save_script._validated(_save_script.default_settings(), corrupt.get("settings", {}))
	var ok_defaults: bool = int(safe["quality"]) == 0 and str(safe["car_id"]) == "vanta_gt"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_check(wrote and ok_values and ok_defaults, "save system: JSON round trip, corrupt values fall back to defaults")


# ---------------------------------------------------------------- physics

func test_streamer_runtime() -> void:
	var streamer := WorldStreamer.new()
	root.add_child(streamer)
	streamer.setup(11, GameConfig.quality_profile(1))
	var frames: int = 0
	while streamer.total_chunks_built() < 6 and frames < 900:
		streamer.update_streaming(Vector3.ZERO, 0.0)
		await process_frame
		frames += 1
	var built_start: bool = streamer.total_chunks_built() >= 6
	# Drive 80 m/s straight along -Z for a while; the streamer must keep up.
	var pos := Vector3.ZERO
	var max_pending: int = 0
	var max_chunks: int = 0
	var t0: int = Time.get_ticks_msec()
	for i in range(60 * 12):
		pos.z -= 80.0 / 60.0
		streamer.update_streaming(pos, 80.0)
		max_pending = maxi(max_pending, streamer.pending_count())
		max_chunks = maxi(max_chunks, streamer.chunk_count())
		await process_frame
	var elapsed_s: float = (Time.get_ticks_msec() - t0) / 1000.0
	_check(built_start and max_chunks > 5 and max_chunks < 40,
		"streaming: chunks spawn ahead of the car and are freed behind it",
		"start %d frames, peak %d live chunks, peak %d in flight, %.2f s for 12 s driven" % [
			frames, max_chunks, max_pending, elapsed_s])

	# Floating origin: shifting moves every chunk and keeps world positions consistent.
	var node: Node3D = streamer.get_child(0) as Node3D
	var shift := Vector3(0.0, 0.0, -1500.0)
	var before: Vector3 = node.position
	streamer.shift_origin(shift)
	var after: Vector3 = node.position
	var moved_ok: bool = (after - (before - shift)).length() < 1e-4
	var origin_ok: bool = streamer.origin().is_equal_approx(shift)
	_check(moved_ok and origin_ok, "streaming: floating-origin shift moves chunks and origin consistently",
		"chunk moved %.3f m (expected 1500 m), origin %s" % [(after - before).length(), str(streamer.origin())])
	streamer.queue_free()
	await process_frame


func test_streamer_road_projection() -> void:
	var streamer := WorldStreamer.new()
	root.add_child(streamer)
	streamer.setup(21, GameConfig.quality_profile(1))
	var frames: int = 0
	while streamer.total_chunks_built() < 4 and frames < 900:
		streamer.update_streaming(Vector3.ZERO, 0.0)
		await process_frame
		frames += 1
	# Put the car 3 m to the right of the road start: lateral offset must be measured.
	var proj: Dictionary = streamer.project(Vector3(3.0, 0.4, -2.0))
	var lateral: float = float(proj["lateral"])
	var rt: Transform3D = streamer.road_transform(proj, 0.5)
	var fwd: Vector3 = -rt.basis.z
	var expected_fwd: Vector3 = RoadChunk.forward_of(float(proj["heading"]))
	_check(absf(absf(lateral) - 3.0) < 0.5 and fwd.dot(expected_fwd) > 0.999,
		"streaming: road projection gives lateral offset and road-aligned frame",
		"lateral %.2f m, distance %.1f m, heading error %.4f" % [
			lateral, float(proj["distance"]), 1.0 - fwd.dot(expected_fwd)])
	streamer.queue_free()
	await process_frame


func test_pacejka_sanity() -> void:
	var peak_long: float = 0.0
	var peak_lat: float = 0.0
	for i in range(1, 2001):
		var x: float = float(i) * 0.001
		peak_long = maxf(peak_long, TireModel.longitudinal(x))
		peak_lat = maxf(peak_lat, TireModel.lateral(x))
	var ell: Vector2 = TireModel.friction_ellipse(0.9, 0.9)
	_check(peak_long > 0.95 and peak_long <= 1.001 and peak_lat > 0.95 and peak_lat <= 1.001 and ell.length() <= 1.0 + 1e-6,
		"tyre model: normalised peaks near 1 and friction ellipse respected",
		"peak long %.3f, lat %.3f, ellipse |F| %.3f" % [peak_long, peak_lat, ell.length()])
	await process_frame


func test_car_acceleration() -> void:
	var spec: Dictionary = CarCatalog.kestrel_r()
	var ground := _flat_ground()
	var car := _spawn_car(spec, _start_pos(spec))
	await _drive_for(car, 0.6, 0.0)  # settle on suspension
	var t_100: float = -1.0
	var t_200: float = -1.0
	var steps: int = 0
	var max_roll: float = 0.0
	while steps < 120 * 45:
		car.input_throttle = 1.0
		car.input_brake = 0.0
		await physics_frame
		steps += 1
		var v: float = car.speed_kmh
		if t_100 < 0.0 and v >= 100.0:
			t_100 = steps / 120.0
		if t_200 < 0.0 and v >= 200.0:
			t_200 = steps / 120.0
		max_roll = maxf(max_roll, absf(car.global_transform.basis.x.y))
		if v >= 300.0 or is_nan(car.linear_velocity.x):
			break
	var ok: bool = t_100 > 0.0 and t_100 < 6.0 and _upright(car) and not is_nan(car.linear_velocity.x)
	_check(ok, "physics: Kestrel R accelerates 0-100 km/h, stays upright",
		"0-100 in %.2f s, 0-200 in %.2f s, top %.0f km/h" % [t_100, t_200, car.speed_kmh])
	car.queue_free()
	ground.queue_free()
	await process_frame


func test_car_braking() -> void:
	var spec: Dictionary = CarCatalog.vanta_gt()
	var ground := _flat_ground()
	var car := _spawn_car(spec, _start_pos(spec))
	await _drive_for(car, 0.6, 0.0)
	var guard: int = 0
	while car.speed_kmh < 100.0 and guard < 120 * 30:
		car.input_throttle = 1.0
		await physics_frame
		guard += 1
	var entry_speed: float = car.speed_kmh
	var grounded: int = car.wheels_on_ground
	var start_x: Vector3 = car.global_position
	var stop_dist: float = -1.0
	guard = 0
	while guard < 120 * 15:
		car.input_throttle = 0.0
		car.input_brake = 1.0
		await physics_frame
		guard += 1
		if car.speed_kmh < 1.0:
			stop_dist = Vector2(car.global_position.x - start_x.x, car.global_position.z - start_x.z).length()
			break
	var ok: bool = entry_speed >= 99.0 and grounded == 4 and stop_dist > 0.0 and stop_dist < 55.0 and _upright(car)
	_check(ok, "physics: 100 km/h to standstill under ABS braking",
		"entry %.1f km/h, on %d wheels, stop distance %.1f m, upright %s" % [entry_speed, grounded, stop_dist, str(_upright(car))])
	car.queue_free()
	ground.queue_free()
	await process_frame


func test_car_steering() -> void:
	var spec: Dictionary = CarCatalog.aurora_veloce()
	var ground := _flat_ground()
	var car := _spawn_car(spec, _start_pos(spec))
	await _drive_for(car, 0.6, 0.0)
	var guard: int = 0
	while car.speed_kmh < 60.0 and guard < 120 * 20:
		car.input_throttle = 0.6
		await physics_frame
		guard += 1
	var entry_speed: float = car.speed_kmh
	var grounded: int = car.wheels_on_ground
	var peak_yaw: float = 0.0
	var peak_lat: float = 0.0
	for i in range(120 * 3):
		car.input_throttle = 0.35
		car.input_steer = 0.5
		await physics_frame
		peak_yaw = maxf(peak_yaw, absf(car.yaw_rate))
		peak_lat = maxf(peak_lat, absf(car.lateral_accel))
	var turn_ok: bool = entry_speed >= 55.0 and grounded == 4 and peak_yaw > 0.2 and _upright(car) and peak_lat < 15.0
	_check(turn_ok, "physics: AWD GT turns at 60 km/h without rolling over",
		"entry %.0f km/h on %d wheels, peak yaw %.2f rad/s, peak lateral %.1f m/s² (%.2f g)" % [
			entry_speed, grounded, peak_yaw, peak_lat, peak_lat / GameConfig.GRAVITY])
	car.queue_free()
	ground.queue_free()
	await process_frame


func test_car_rate_independence() -> void:
	var spec: Dictionary = CarCatalog.vanta_gt()
	var ground := _flat_ground()
	var distances: Array = []
	for rate in [120, 60]:
		Engine.physics_ticks_per_second = rate
		var car := _spawn_car(spec, _start_pos(spec))
		await _drive_for(car, 0.6, 0.0)
		var start: Vector3 = car.global_position
		await _drive_for(car, 8.0, 1.0)
		distances.append(Vector2(car.global_position.x - start.x, car.global_position.z - start.z).length())
		car.queue_free()
		await process_frame
	Engine.physics_ticks_per_second = 120
	var d120: float = distances[0]
	var d60: float = distances[1]
	var rel: float = absf(d120 - d60) / maxf(d120, 1.0)
	_check(rel < 0.10 and d120 > 20.0 and d60 > 20.0, "physics: result independent of physics rate (120 Hz vs 60 Hz)",
		"120 Hz %.1f m, 60 Hz %.1f m, difference %.1f %%" % [d120, d60, rel * 100.0])
	ground.queue_free()
	await process_frame


func test_car_slope_hold() -> void:
	var spec: Dictionary = CarCatalog.vanta_gt()
	# A 2 m thick slab tilted 5 degrees; its top surface passes through the origin.
	var tilt := Basis(Vector3.RIGHT, deg_to_rad(5.0))
	var ramp := _ground(Transform3D(tilt, Vector3(0.0, -1.0, 0.0)), Vector3(60.0, 2.0, 400.0))
	var car := _spawn_car(spec, Transform3D(Basis(Vector3.UP, 0.0), Vector3(0.0, VehicleController.rest_height_for(spec), 0.0)))
	await _drive_for(car, 1.0, 0.0, 1.0)
	var grounded: int = car.wheels_on_ground
	var start: Vector3 = car.global_position
	await _drive_for(car, 4.0, 0.0, 1.0)
	var drift: float = (car.global_position - start).length()
	_check(drift < 0.6 and grounded == 4 and _upright(car), "physics: parked on a 5 degree slope, brakes hold the car",
		"on %d wheels, drift %.2f m in 4 s" % [grounded, drift])
	car.queue_free()
	ramp.queue_free()
	await process_frame


## End-to-end: the generated road, its colliders, the streamer and the car together.
## A simple road-following driver must stay on the asphalt for 40 s at about 60 km/h.
func test_autopilot_follows_road() -> void:
	var streamer := WorldStreamer.new()
	root.add_child(streamer)
	streamer.setup(20260501, GameConfig.quality_profile(2))
	var frames: int = 0
	while streamer.total_chunks_built() < 8 and frames < 900:
		streamer.update_streaming(Vector3.ZERO, 0.0)
		await process_frame
		frames += 1
	var spec: Dictionary = CarCatalog.vanta_gt()
	var car := _spawn_car(spec, Transform3D(Basis(), Vector3(0.0, VehicleController.rest_height_for(spec), 0.0)))
	var max_lat: float = 0.0
	var airborne: int = 0
	var max_speed: float = 0.0
	var progress: float = 0.0
	for i in range(120 * 40):
		var proj: Dictionary = streamer.update_streaming(car.position, car.forward_speed)
		car.input_steer = RoadAutopilot.steer_command(-car.global_transform.basis.z, proj)
		var err: float = 60.0 - car.speed_kmh
		car.input_throttle = clampf(err * 0.2 + 0.2, 0.0, 1.0)
		car.input_brake = clampf(-err * 0.15, 0.0, 1.0)
		await physics_frame
		max_lat = maxf(max_lat, absf(float(proj["lateral"])))
		max_speed = maxf(max_speed, car.speed_kmh)
		if car.wheels_on_ground < 3:
			airborne += 1
		progress = maxf(progress, float(proj["distance"]))
	var ok: bool = max_lat < 2.0 and airborne < 10 and progress > 400.0 and _upright(car)
	_check(ok, "end-to-end: autopilot drives the generated road for 40 s without leaving the asphalt",
		"progress %.0f m, max lateral %.2f m, airborne %d ticks, top %.0f km/h, chunks %d" % [
			progress, max_lat, airborne, max_speed, streamer.chunk_count()])
	car.queue_free()
	streamer.queue_free()
	await process_frame


func test_car_wall_collision() -> void:
	var spec: Dictionary = CarCatalog.vanta_gt()
	var ground := _flat_ground()
	var wall := _ground(Transform3D(Basis(), Vector3(0.0, 1.5, -40.0)), Vector3(40.0, 3.0, 1.0))
	var car := _spawn_car(spec, _start_pos(spec))
	await _drive_for(car, 0.6, 0.0)
	var guard: int = 0
	var peak_speed: float = 0.0
	while guard < 120 * 6:
		car.input_throttle = 0.8
		await physics_frame
		peak_speed = maxf(peak_speed, car.speed_kmh)
		guard += 1
	var blocked: bool = peak_speed > 30.0 and car.global_position.z > -40.0 - 1.5 and car.speed_kmh < 25.0
	_check(blocked and _upright(car), "physics: car stops against a wall, does not pass through it",
		"peak %.1f km/h, final z %.2f m, speed %.1f km/h" % [peak_speed, car.global_position.z, car.speed_kmh])
	car.queue_free()
	wall.queue_free()
	ground.queue_free()
	await process_frame
