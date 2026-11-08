## Custom vehicle dynamics on top of RigidBody3D.
##
## Per physics tick (fixed 120 Hz):
##  - each wheel casts a ray for its suspension, with spring-damper forces and
##    anti-roll bars;
##  - each wheel has its own angular speed; tyre forces come from a Pacejka model
##    with a friction ellipse, and feed back into the wheel's rotational dynamics;
##  - the engine speed is derived from driven wheel speed, with torque from a curve
##    and an automatic or manual gearbox;
##  - ABS, traction control and a yaw-damping stability control act on the brake
##    and drive torques;
##  - aerodynamic drag and downforce act on the centre of mass.
## Nothing here moves the transform directly: all motion is produced by forces.
class_name VehicleController
extends RigidBody3D

const SUSP_REST: float = 0.33
const SUSP_MAX_TRAVEL: float = 0.13
const SUSP_STATIC_COMPRESSION: float = 0.085
const SUSP_DAMPING_RATIO: float = 0.35
const ARB_STIFFNESS: float = 26000.0
const WHEEL_INERTIA: float = 1.6
const ROLLING_COEF: float = 0.015
const FRONT_BRAKE_BIAS: float = 0.62
const HANDBRAKE_TORQUE: float = 2600.0
const LAUNCH_FRACTION: float = 0.42
const TC_SLIP_THRESHOLD: float = 0.15
const ABS_SLIP_THRESHOLD: float = -0.12
const ESC_GAIN: float = 4200.0
const ESC_MAX_TORQUE: float = 5000.0
const ESC_DEADBAND: float = 0.35
const STEER_RATE: float = 3.5

var spec: Dictionary = {}
var engine := EngineModel.new()
## Four wheel records in order FL, FR, RL, RR. See _make_wheel().
var wheels: Array = []

# --- inputs (written by the owner every frame) ---
var input_steer: float = 0.0
var input_throttle: float = 0.0
var input_brake: float = 0.0
var input_handbrake: bool = false
var assist_abs: bool = true
var assist_tc: bool = true
var assist_esc: bool = true
var wetness: float = 0.0

# --- telemetry (read by HUD, camera, audio, tests) ---
var speed_kmh: float = 0.0
var forward_speed: float = 0.0
var rpm: float = 0.0
var gear: int = 1
var yaw_rate: float = 0.0
var _prev_velocity: Vector3 = Vector3.ZERO
var lateral_accel: float = 0.0
var abs_active: bool = false
var tc_active: bool = false
var esc_active: bool = false
var wheels_on_ground: int = 0
var steer_angle: float = 0.0

var active: bool = false
var _mass_per_wheel: float = 0.0
var _spring_k: float = 0.0
var _damping_c: float = 0.0
var _mu0: float = 1.0
var _radius: float = 0.34
var _wheelbase: float = 2.6


## Sets the specification, builds physical hardpoints and visuals references.
## visuals: Array of 4 Dictionaries {"pivot": Node3D, "spin": Node3D} in FL, FR, RL, RR order.
func configure(p_spec: Dictionary, visuals: Array) -> void:
	spec = p_spec
	mass = float(spec["mass"])
	var m: float = mass
	var l: float = float(spec["length"])
	var w: float = float(spec["width"])
	var h: float = float(spec["height"])
	var cg: float = float(spec["cg_height"])
	_radius = float(spec["wheel_radius"])
	_wheelbase = float(spec["wheelbase"])
	_mu0 = float(spec["tire_mu"])
	# Explicit inertia (pitch, yaw, roll) from a box of the car's dimensions.
	inertia = Vector3(m * (h * h + l * l) / 12.0, m * (w * w + l * l) / 12.0, m * (w * w + h * h) / 12.0)
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3.ZERO
	# REPLACE mode: otherwise Godot adds the world's default damping (0.1) to ours.
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp = 0.05
	linear_damp = 0.0
	can_sleep = false
	continuous_cd = true
	# Tyre grip comes only from the tyre model; the chassis must not add friction
	# when it touches the ground (e.g. on bump stops), or it would pin the car.
	var chassis_material := PhysicsMaterial.new()
	chassis_material.friction = 0.0
	chassis_material.rough = false
	physics_material_override = chassis_material

	# Collision body: from just above the ground to the roof, relative to COM.
	var box := BoxShape3D.new()
	var bottom: float = -cg + 0.2
	var top: float = h - cg
	box.size = Vector3(w * 0.94, top - bottom, l * 0.96)
	var cs := CollisionShape3D.new()
	cs.name = "Chassis"
	cs.shape = box
	cs.position = Vector3(0.0, (bottom + top) * 0.5, 0.0)
	add_child(cs)

	var hard_y: float = -cg + _radius + SUSP_REST
	var tf: float = float(spec["track_front"])
	var tr: float = float(spec["track_rear"])
	var wb: float = _wheelbase
	var front_split: float = float(spec["front_split"])
	var drive: String = str(spec["drive"])

	wheels.clear()
	var positions: Array = [
		Vector3(-tf * 0.5, hard_y, -wb * 0.5),
		Vector3(tf * 0.5, hard_y, -wb * 0.5),
		Vector3(-tr * 0.5, hard_y, wb * 0.5),
		Vector3(tr * 0.5, hard_y, wb * 0.5),
	]
	for i in range(4):
		var is_front: bool = i < 2
		var driven: bool = false
		var share: float = 0.0
		if drive == "AWD":
			driven = true
			share = front_split * 0.5 if is_front else (1.0 - front_split) * 0.5
		elif drive == "RWD":
			driven = not is_front
			share = 0.5 if driven else 0.0
		elif drive == "FWD":
			driven = is_front
			share = 0.5 if driven else 0.0
		wheels.append(_make_wheel(positions[i], is_front, driven, share, visuals[i]))

	_mass_per_wheel = m * 0.25
	_spring_k = _mass_per_wheel * GameConfig.GRAVITY / SUSP_STATIC_COMPRESSION
	_damping_c = 2.0 * SUSP_DAMPING_RATIO * sqrt(_spring_k * _mass_per_wheel)

	engine.configure(spec)
	gear = engine.gear
	rpm = engine.rpm


func _make_wheel(hard: Vector3, is_front: bool, driven: bool, share: float, visual: Dictionary) -> Dictionary:
	return {
		"hard": hard,
		"front": is_front,
		"driven": driven,
		"share": share,
		"visual_pivot": visual["pivot"],
		"visual_spin": visual["spin"],
		"omega": 0.0,
		"spin_angle": 0.0,
		"comp": 0.0,
		"comp_rate": 0.0,
		"susp_len": SUSP_REST,
		"contact": Vector3.ZERO,
		"on": false,
		"fz": 0.0,
		"kappa": 0.0,
		"alpha": 0.0,
		"steer": 0.0,
		"drive": 0.0,
		"brake": 0.0,
		"fx": 0.0,
		"fy": 0.0,
	}


## Height of the centre of mass when the car stands at rest on flat ground, plus a
## small drop. Spawning here avoids a hard landing that would bottom the suspension.
static func rest_height_for(p_spec: Dictionary) -> float:
	return float(p_spec["cg_height"]) - SUSP_STATIC_COMPRESSION + 0.03


## Enables or disables simulation (the body is frozen while disabled).
func set_active(value: bool) -> void:
	active = value
	freeze = not value
	if not value:
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO


## Teleports the car upright at a transform with zero velocity.
func reset_to(xf: Transform3D) -> void:
	global_transform = xf
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	for w in wheels:
		w["omega"] = 0.0
		w["comp"] = SUSP_STATIC_COMPRESSION
		w["comp_rate"] = 0.0
		w["on"] = false
		w["fz"] = 0.0
		w["kappa"] = 0.0
		w["fx"] = 0.0
		w["fy"] = 0.0
		w["spin_angle"] = 0.0
	steer_angle = 0.0
	engine.rpm = engine.idle
	_prev_velocity = Vector3.ZERO
	reset_physics_interpolation()


func _physics_process(dt: float) -> void:
	if not active or dt <= 0.0 or wheels.is_empty():
		return
	var xf: Transform3D = global_transform
	var up: Vector3 = xf.basis.y
	var body_fwd: Vector3 = -xf.basis.z
	var vel: Vector3 = linear_velocity
	var speed: float = vel.length()
	speed_kmh = speed * 3.6
	forward_speed = vel.dot(body_fwd)
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var throttle: float = clampf(input_throttle, 0.0, 1.0)
	var brake: float = clampf(input_brake, 0.0, 1.0)

	# ---- Steering: speed-sensitive lock, rate-limited ----
	var max_steer: float = deg_to_rad(lerpf(float(spec["steer_low_deg"]), float(spec["steer_high_deg"]),
		clampf(speed / 40.0, 0.0, 1.0)))
	var target_steer: float = clampf(input_steer, -1.0, 1.0) * max_steer
	steer_angle = move_toward(steer_angle, target_steer, dt * STEER_RATE)
	(wheels[0] as Dictionary)["steer"] = steer_angle
	(wheels[1] as Dictionary)["steer"] = steer_angle

	# ---- Suspension rays, compression and forces ----
	wheels_on_ground = 0
	for w in wheels:
		_update_suspension(w, xf, up, space, dt)
	# Anti-roll bars, per axle.
	_apply_anti_roll(0, 1)
	_apply_anti_roll(2, 3)

	var aero_per_wheel: float = 0.5 * GameConfig.AIR_DENSITY * float(spec["downforce_cl"]) \
		* float(spec["frontal_area"]) * speed * speed * 0.25

	# ---- Driveline: engine speed from driven wheels, gearbox, torque ----
	var driven_sum: float = 0.0
	var driven_count: int = 0
	for w in wheels:
		if w["driven"]:
			driven_sum += float(w["omega"])
			driven_count += 1
	var avg_driven: float = driven_sum / float(maxi(driven_count, 1))
	var target_rpm: float = maxf(engine.idle, engine.rpm_from_wheel_speed(avg_driven))
	if absf(forward_speed) < 2.5 and throttle > 0.05 and engine.gear != 0:
		target_rpm = maxf(target_rpm, engine.idle + throttle * LAUNCH_FRACTION * engine.redline)
	engine.rpm = clampf(lerpf(engine.rpm, target_rpm, 0.6), engine.idle * 0.85, engine.redline * 1.03)
	engine.update_auto(dt, absf(forward_speed), throttle, brake)
	rpm = engine.rpm
	gear = engine.gear
	var total_drive: float = engine.wheel_torque(throttle)

	# ---- Per-wheel tyre forces and wheel dynamics ----
	# Traction control uses one factor for the whole driven group, so it cannot
	# cut torque on one side only (which would create a yaw moment and spin the car).
	abs_active = false
	var tc_factor: float = _traction_factor()
	tc_active = tc_factor < 1.0
	for w in wheels:
		_update_tyre(w, xf, up, body_fwd, total_drive, tc_factor, brake, aero_per_wheel, dt)

	# ---- Aerodynamics on the centre of mass ----
	var rho: float = GameConfig.AIR_DENSITY
	var area: float = float(spec["frontal_area"])
	var cd: float = float(spec["drag_cd"])
	var cl: float = float(spec["downforce_cl"])
	if speed > 0.1:
		apply_central_force(-vel * (0.5 * rho * cd * area * speed))
		apply_central_force(-up * (0.5 * rho * cl * area * speed * speed))

	# ---- Stability control: damp yaw deviating from the kinematic prediction ----
	yaw_rate = angular_velocity.dot(up)
	esc_active = false
	if assist_esc and speed > 6.0:
		var front_steer: float = steer_angle
		var desired_yaw: float = -forward_speed * tan(front_steer) / _wheelbase
		var err: float = yaw_rate - desired_yaw
		if absf(err) > ESC_DEADBAND:
			var excess: float = err - signf(err) * ESC_DEADBAND
			var torque: float = clampf(-ESC_GAIN * excess, -ESC_MAX_TORQUE, ESC_MAX_TORQUE)
			apply_torque(up * torque)
			esc_active = true

	# Lateral acceleration measured from the velocity change, in the car's frame.
	var accel: Vector3 = (linear_velocity - _prev_velocity) / dt
	lateral_accel = accel.dot(xf.basis.x)
	_prev_velocity = linear_velocity


func _update_suspension(w: Dictionary, xf: Transform3D, up: Vector3, space: PhysicsDirectSpaceState3D, dt: float) -> void:
	var hard_world: Vector3 = xf * (w["hard"] as Vector3)
	var length: float = SUSP_REST + _radius + SUSP_MAX_TRAVEL
	var query := PhysicsRayQueryParameters3D.create(hard_world, hard_world - up * length, 1, [get_rid()])
	var hit: Dictionary = space.intersect_ray(query)
	var was_on: bool = bool(w["on"])
	# Airborne wheels hang at full droop; they are not compressed.
	var susp_len: float = SUSP_REST + SUSP_MAX_TRAVEL
	if hit.is_empty():
		w["on"] = false
	else:
		w["on"] = true
		w["contact"] = hit["position"]
		susp_len = hard_world.distance_to(hit["position"]) - _radius
		wheels_on_ground += 1
	w["susp_len"] = susp_len
	var comp: float = clampf(SUSP_REST - susp_len, -0.03, SUSP_MAX_TRAVEL)
	# On the first contact tick there is no meaningful compression rate (no damping kick).
	w["comp_rate"] = (comp - float(w["comp"])) / dt if was_on and w["on"] else 0.0
	w["comp"] = comp
	var force: float = 0.0
	if w["on"]:
		force = maxf(0.0, _spring_k * comp + _damping_c * float(w["comp_rate"]))
	w["fz"] = force


func _apply_anti_roll(left_index: int, right_index: int) -> void:
	var wl: Dictionary = wheels[left_index]
	var wr: Dictionary = wheels[right_index]
	# When the body rolls, the more compressed side gets extra upward force and the other
	# side loses the same amount: this opposes the roll.
	if not (bool(wl["on"]) and bool(wr["on"])):
		return  # a bar with one end in the air has no valid reference: leave both springs alone
	var diff: float = float(wl["comp"]) - float(wr["comp"])
	var f: float = ARB_STIFFNESS * diff
	wl["fz"] = maxf(0.0, float(wl["fz"]) + f)
	wr["fz"] = maxf(0.0, float(wr["fz"]) - f)


## Torque factor for the driven wheels, from their mean slip ratio of the last tick.
func _traction_factor() -> float:
	if not assist_tc:
		return 1.0
	var sum: float = 0.0
	var n: int = 0
	for w in wheels:
		if w["driven"]:
			sum += float(w["kappa"])
			n += 1
	if n == 0:
		return 1.0
	var mean: float = sum / float(n)
	if mean <= TC_SLIP_THRESHOLD:
		return 1.0
	return clampf(1.0 - (mean - TC_SLIP_THRESHOLD) * 3.0, 0.2, 1.0)


func _update_tyre(w: Dictionary, xf: Transform3D, up: Vector3, body_fwd: Vector3,
		total_drive: float, tc_factor: float, brake: float, aero_per_wheel: float, dt: float) -> void:
	var steer: float = float(w["steer"])
	var fwd_w: Vector3 = body_fwd.rotated(up, -steer) if w["front"] else body_fwd
	var right_w: Vector3 = fwd_w.cross(up).normalized()
	var omega: float = float(w["omega"])
	var fz: float = float(w["fz"]) + aero_per_wheel
	var kappa: float = 0.0
	var alpha: float = 0.0
	var contact_offset: Vector3 = Vector3.ZERO
	var on: bool = bool(w["on"]) and fz > 1.0

	# Drive torque, scaled by the axle-wide traction factor.
	var drive_t: float = 0.0
	if w["driven"]:
		drive_t = total_drive * float(w["share"]) * tc_factor
	w["drive"] = drive_t

	# Brake torque with ABS. The holding limit below stops the wheel from oscillating at standstill.
	var bias: float = FRONT_BRAKE_BIAS if w["front"] else 1.0 - FRONT_BRAKE_BIAS
	var brake_t: float = float(spec["brake_torque"]) * brake * bias
	if not w["front"] and input_handbrake:
		brake_t += HANDBRAKE_TORQUE
	if assist_abs and brake_t > 0.0 and float(w["kappa"]) < ABS_SLIP_THRESHOLD and on:
		# Proportional release: the further the wheel locks, the more torque is removed.
		brake_t *= clampf(1.0 - (-float(w["kappa"]) + ABS_SLIP_THRESHOLD) * 5.0, 0.2, 1.0)
		abs_active = true

	var mu: float = TireModel.friction(_mu0, fz, wetness)
	var vx: float = 0.0
	var vy: float = 0.0
	var denom: float = 1.0
	if on:
		contact_offset = (w["contact"] as Vector3) - global_position
		# Suspension (spring, damper and anti-roll) pushes the body up at the contact.
		# Aerodynamic downforce is applied to the centre of mass separately.
		apply_force(up * float(w["fz"]), contact_offset)
		# Contact velocity is taken once per physics tick. Wheel spin is integrated in
		# substeps so that the stiff slip coupling stays stable with a realistic wheel inertia.
		var v_c: Vector3 = linear_velocity + angular_velocity.cross(contact_offset)
		vx = v_c.dot(fwd_w)
		vy = v_c.dot(right_w)
		denom = maxf(absf(vx), 1.0)
		alpha = atan2(vy, denom)

	var fx: float = 0.0
	var fy: float = 0.0
	kappa = 0.0
	var sgn: float = signf(omega)
	var brake_applied: float = 0.0
	if on:
		# Implicit wheel update. The longitudinal force is linearised around the current
		# slip, F(w') = F0 + slope * r * (w' - w) / d, and the wheel equation is solved in
		# closed form: unconditionally stable even with the stiff tyre coupling at low speed.
		kappa = (omega * _radius - vx) / denom
		var ell: Vector2 = TireModel.friction_ellipse(TireModel.longitudinal(kappa), -TireModel.lateral(alpha))
		var f0: float = ell.x * mu * fz
		fy = ell.y * mu * fz
		var d_k: float = 0.01
		var slope: float = (TireModel.longitudinal(kappa + d_k) - TireModel.longitudinal(kappa - d_k)) / (2.0 * d_k) * mu * fz
		var omega_start: float = omega
		var rolling: float = -sgn * ROLLING_COEF * fz * _radius
		var other: float = drive_t + rolling - f0 * _radius
		var stiffness: float = slope * _radius * _radius / denom
		# Static hold: a braked wheel that can be held stops completely, and the brake
		# supplies exactly the torque that balances the others (up to its limit).
		if brake_t > 0.0 and absf(omega) < 0.5 and absf(other) <= brake_t:
			brake_applied = -other
			omega = 0.0
		else:
			brake_applied = -sgn * brake_t if (brake_t > 0.0 and sgn != 0.0) else 0.0
			var torque: float = other + brake_applied
			var d_omega: float = torque / (WHEEL_INERTIA / dt + stiffness)
			var new_omega: float = omega + d_omega
			if brake_t > 0.0 and sgn != 0.0 and new_omega * sgn < 0.0:
				# The brake would reverse the wheel within this tick: it stops at zero instead.
				new_omega = 0.0
				brake_applied = -other
			omega = new_omega
		fx = f0 + slope * _radius / denom * (omega - omega_start)
		kappa = (omega * _radius - vx) / denom
		apply_force(fwd_w * fx + right_w * fy, contact_offset)
	else:
		# Airborne: the wheel only sees its brake and drive torque (no tyre force).
		if brake_t > 0.0 and sgn != 0.0:
			brake_applied = -sgn * minf(brake_t, absf(omega) * WHEEL_INERTIA / dt)
		omega += (drive_t + brake_applied) / WHEEL_INERTIA * dt
	w["kappa"] = kappa
	w["alpha"] = alpha
	w["fx"] = fx
	w["fy"] = fy
	w["brake"] = brake_applied
	w["omega"] = omega
	w["spin_angle"] = float(w["spin_angle"]) + omega * dt

	# Visual wheel placement from the suspension state.
	var pivot: Node3D = w["visual_pivot"]
	var spin: Node3D = w["visual_spin"]
	var hard: Vector3 = w["hard"]
	pivot.position = hard + Vector3.DOWN * float(w["susp_len"])
	pivot.basis = Basis(Vector3.UP, -steer)
	spin.basis = Basis(Vector3.RIGHT, float(w["spin_angle"]))


## Gearbox controls for the UI (manual mode).
func request_shift_up() -> void:
	engine.shift_up()
	gear = engine.gear


func request_shift_down() -> void:
	engine.shift_down()
	gear = engine.gear


func set_auto_gearbox(value: bool) -> void:
	engine.auto_shift = value


func is_auto_gearbox() -> bool:
	return engine.auto_shift

