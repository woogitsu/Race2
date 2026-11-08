## Procedurally modelled car: lofted superellipse body with station profiles, glass
## cabin, interior, lights, and wheels with tyre tread, rims and brake discs.
## Coordinates: forward is -Z, up is +Y, ground at y = 0 (the caller offsets the
## body by -cg_height so the origin is the centre of mass).
class_name CarModelBuilder
extends RefCounted

const BODY_SEGMENTS: int = 32
# Body profile stations: [z fraction 0..1 front to rear, half-width fraction,
# bottom height fraction, top height fraction].
const STATIONS_COUPE: Array = [
	[0.00, 0.05, 0.12, 0.42], [0.04, 0.85, 0.10, 0.52], [0.14, 0.97, 0.10, 0.58],
	[0.34, 1.00, 0.12, 0.62], [0.55, 1.00, 0.14, 0.64], [0.80, 1.00, 0.14, 0.61],
	[0.94, 0.96, 0.14, 0.58], [0.99, 0.84, 0.13, 0.50], [1.00, 0.04, 0.12, 0.44],
]
const STATIONS_SUPER: Array = [
	[0.00, 0.05, 0.10, 0.36], [0.05, 0.82, 0.10, 0.45], [0.20, 0.98, 0.10, 0.50],
	[0.40, 1.00, 0.12, 0.52], [0.60, 1.00, 0.12, 0.53], [0.85, 1.00, 0.13, 0.55],
	[0.97, 0.90, 0.14, 0.52], [1.00, 0.05, 0.12, 0.45],
]
const STATIONS_GT: Array = [
	[0.00, 0.05, 0.14, 0.45], [0.04, 0.88, 0.13, 0.55], [0.15, 0.99, 0.13, 0.60],
	[0.35, 1.00, 0.14, 0.64], [0.60, 1.00, 0.15, 0.66], [0.85, 1.00, 0.15, 0.63],
	[0.96, 0.95, 0.15, 0.60], [1.00, 0.05, 0.15, 0.50],
]
const CABIN_COUPE: Array = [
	[0.26, 0.80, 0.52, 0.80], [0.36, 0.86, 0.52, 0.98], [0.50, 0.88, 0.52, 1.00],
	[0.64, 0.86, 0.52, 0.96], [0.76, 0.78, 0.52, 0.82],
]
const CABIN_SUPER: Array = [
	[0.36, 0.80, 0.50, 0.70], [0.46, 0.88, 0.50, 0.86], [0.56, 0.88, 0.50, 0.90],
	[0.66, 0.86, 0.50, 0.84], [0.74, 0.78, 0.50, 0.70],
]
const CABIN_GT: Array = [
	[0.30, 0.82, 0.55, 0.82], [0.42, 0.90, 0.55, 0.98], [0.56, 0.92, 0.55, 1.00],
	[0.70, 0.88, 0.55, 0.96], [0.82, 0.78, 0.55, 0.84],
]


## Returns { "body": Node3D (offset to CG), "wheels": Array of 4 {"pivot", "spin"} }
## in FL, FR, RL, RR order, to be parented under the vehicle RigidBody3D.
static func build(spec: Dictionary) -> Dictionary:
	var length: float = float(spec["length"])
	var width: float = float(spec["width"])
	var height: float = float(spec["height"])
	var cg: float = float(spec["cg_height"])
	var style: int = int(spec["style"])
	var paint_col: Color = spec["body_color"]

	var body_root := Node3D.new()
	body_root.name = "Body"
	body_root.position = Vector3(0.0, -cg, 0.0)

	var stations: Array = STATIONS_COUPE
	var cabin: Array = CABIN_COUPE
	match style:
		1:
			stations = STATIONS_SUPER
			cabin = CABIN_SUPER
		2:
			stations = STATIONS_GT
			cabin = CABIN_GT

	var paint_mat := StandardMaterial3D.new()
	paint_mat.albedo_color = paint_col
	paint_mat.metallic = 0.85
	paint_mat.roughness = 0.22
	paint_mat.clearcoat_enabled = true
	paint_mat.clearcoat = 1.0
	paint_mat.clearcoat_roughness = 0.06

	var glass_mat := StandardMaterial3D.new()
	glass_mat.albedo_color = Color(0.03, 0.05, 0.07, 0.62)
	glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass_mat.metallic = 0.2
	glass_mat.roughness = 0.03
	glass_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var trim_mat := StandardMaterial3D.new()
	trim_mat.albedo_color = Color(0.035, 0.035, 0.04)
	trim_mat.roughness = 0.55

	var head_mat := StandardMaterial3D.new()
	head_mat.albedo_color = Color(1.0, 1.0, 0.95)
	head_mat.emission_enabled = true
	head_mat.emission = Color(1.0, 0.97, 0.9)
	head_mat.emission_energy_multiplier = 2.5

	var tail_mat := StandardMaterial3D.new()
	tail_mat.albedo_color = Color(0.8, 0.02, 0.02)
	tail_mat.emission_enabled = true
	tail_mat.emission = Color(1.0, 0.05, 0.03)
	tail_mat.emission_energy_multiplier = 1.5

	var interior_mat := StandardMaterial3D.new()
	interior_mat.albedo_color = Color(0.09, 0.07, 0.06)
	interior_mat.roughness = 0.75

	var chrome_mat := StandardMaterial3D.new()
	chrome_mat.albedo_color = Color(0.8, 0.8, 0.82)
	chrome_mat.metallic = 1.0
	chrome_mat.roughness = 0.15

	var body_mesh := ArrayMesh.new()

	var paint := MeshBuilder.new()
	_loft(paint, stations, length, width, height, BODY_SEGMENTS, 2.6)
	paint.smooth_normals()
	paint.orient_to_normals()
	paint.commit_surface(body_mesh, paint_mat)

	var glass := MeshBuilder.new()
	_loft(glass, cabin, length, width * 0.92, height, 24, 2.2)
	glass.smooth_normals()
	glass.orient_to_normals()
	glass.commit_surface(body_mesh, glass_mat)

	var trim := MeshBuilder.new()
	# Grille, lower air dam, side sills, diffuser, mirrors, wiper shelf.
	trim.add_box(Transform3D(Basis(), Vector3(0.0, height * 0.36, -length * 0.5 + 0.06)),
		Vector3(width * 0.5, 0.12, 0.05), trim_mat.albedo_color)
	trim.add_box(Transform3D(Basis(), Vector3(0.0, height * 0.12, -length * 0.5 + 0.08)),
		Vector3(width * 0.9, 0.06, 0.12), trim_mat.albedo_color)
	trim.add_box(Transform3D(Basis(), Vector3(0.0, height * 0.12, length * 0.5 - 0.1)),
		Vector3(width * 0.88, 0.1, 0.22), trim_mat.albedo_color)
	for side in [-1.0, 1.0]:
		trim.add_box(Transform3D(Basis(), Vector3(side * width * 0.5, height * 0.26, -0.1)),
			Vector3(0.1, 0.1, length * 0.46), trim_mat.albedo_color)
		trim.add_box(Transform3D(Basis(), Vector3(side * (width * 0.5 + 0.1), height * 0.68, -0.62)),
			Vector3(0.16, 0.1, 0.22), trim_mat.albedo_color)
	trim.commit_surface(body_mesh, trim_mat)

	var lights_head := MeshBuilder.new()
	var lights_tail := MeshBuilder.new()
	for side in [-1.0, 1.0]:
		var hx: float = side * width * 0.36
		lights_head.add_box(Transform3D(Basis(), Vector3(hx, height * 0.48, -length * 0.5 + 0.12)),
			Vector3(0.42, 0.09, 0.05), Color.WHITE)
		lights_tail.add_box(Transform3D(Basis(), Vector3(hx, height * 0.5, length * 0.5 - 0.02)),
			Vector3(0.5, 0.08, 0.04), Color.WHITE)
	lights_head.commit_surface(body_mesh, head_mat)
	lights_tail.commit_surface(body_mesh, tail_mat)

	var chrome := MeshBuilder.new()
	for side in [-1.0, 1.0]:
		var ex := Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(side * width * 0.3, height * 0.16, length * 0.5 + 0.01))
		var tip_fn := func(u: float, v: float) -> Vector3:
			var a: float = u * TAU
			var local := Vector3(cos(a) * 0.04, lerpf(0.0, 0.12, v), sin(a) * 0.04)
			return ex * local
		chrome.add_param_surface(14, 1, tip_fn, Color.WHITE, true, false)
	chrome.smooth_normals()
	chrome.orient_to_normals()
	chrome.commit_surface(body_mesh, chrome_mat)

	var interior := MeshBuilder.new()
	# Dashboard, two seats and a steering wheel (driver on the left).
	var dash_z: float = -length * 0.5 + length * 0.36 + 0.14
	interior.add_box(Transform3D(Basis(), Vector3(0.0, height * 0.6, dash_z)),
		Vector3(width * 0.9, 0.22, 0.3), interior_mat.albedo_color)
	for side in [-1.0, 1.0]:
		var sx: float = side * 0.36
		interior.add_box(Transform3D(Basis(Vector3.RIGHT, -0.18), Vector3(sx, height * 0.56, -0.02)),
			Vector3(0.48, 0.1, 0.5), interior_mat.albedo_color)
		interior.add_box(Transform3D(Basis(Vector3.RIGHT, -0.18), Vector3(sx, height * 0.82, 0.22)),
			Vector3(0.48, 0.58, 0.1), interior_mat.albedo_color)
	var wheel_center := Vector3(-0.36, height * 0.7, dash_z + 0.22)
	var wheel_basis := Basis(Vector3.RIGHT, -0.45)
	var steer_fn := func(u: float, v: float) -> Vector3:
		var a: float = u * TAU
		var rim_r: float = 0.19 + 0.012 * (v - 0.5)
		var local := Vector3((v - 0.5) * 0.03, cos(a) * rim_r, sin(a) * rim_r)
		return wheel_center + wheel_basis * local
	interior.add_param_surface(28, 4, steer_fn, Color.WHITE, true, false)
	interior.smooth_normals()
	interior.orient_to_normals()
	interior.commit_surface(body_mesh, interior_mat)

	if bool(spec.get("spoiler", false)):
		var wing := MeshBuilder.new()
		wing.add_box(Transform3D(Basis(), Vector3(0.0, height * 0.76, length * 0.5 - 0.22)),
			Vector3(width * 0.84, 0.05, 0.26), trim_mat.albedo_color)
		for side in [-1.0, 1.0]:
			wing.add_box(Transform3D(Basis(), Vector3(side * width * 0.3, height * 0.66, length * 0.5 - 0.22)),
				Vector3(0.05, 0.22, 0.12), trim_mat.albedo_color)
		wing.commit_surface(body_mesh, trim_mat)

	var mi := MeshInstance3D.new()
	mi.name = "BodyMesh"
	mi.mesh = body_mesh
	body_root.add_child(mi)

	var wheels: Array = []
	var wheel_mesh: ArrayMesh = _build_wheel_mesh(spec)
	var positions: Array = [
		Vector3(-float(spec["track_front"]) * 0.5, 0.0, -float(spec["wheelbase"]) * 0.5),
		Vector3(float(spec["track_front"]) * 0.5, 0.0, -float(spec["wheelbase"]) * 0.5),
		Vector3(-float(spec["track_rear"]) * 0.5, 0.0, float(spec["wheelbase"]) * 0.5),
		Vector3(float(spec["track_rear"]) * 0.5, 0.0, float(spec["wheelbase"]) * 0.5),
	]
	for p in positions:
		var pivot := Node3D.new()
		pivot.name = "WheelPivot"
		var spin := Node3D.new()
		spin.name = "WheelSpin"
		pivot.add_child(spin)
		var wmi := MeshInstance3D.new()
		wmi.name = "WheelMesh"
		wmi.mesh = wheel_mesh
		spin.add_child(wmi)
		wheels.append({"pivot": pivot, "spin": spin, "position": p})

	return {"body": body_root, "wheels": wheels, "wheel_mesh": wheel_mesh}


## Lofts a closed body from stations: rows of [z, half-width, bottom, top].
static func _loft(mb: MeshBuilder, stations: Array, length: float, width: float, height: float,
		segments: int, exponent: float) -> void:
	var count: int = stations.size()
	var fn := func(u: float, v: float) -> Vector3:
		var f: float = v * float(count - 1)
		var i: int = mini(int(floor(f)), count - 2)
		var t: float = f - float(i)
		var a: Array = stations[i]
		var b: Array = stations[i + 1]
		var tz: float = lerpf(float(a[0]), float(b[0]), t)
		var hw: float = lerpf(float(a[1]), float(b[1]), t) * width * 0.5
		var y0: float = lerpf(float(a[2]), float(b[2]), t) * height
		var y1: float = lerpf(float(a[3]), float(b[3]), t) * height
		var ang: float = u * TAU
		var c: float = cos(ang)
		var s: float = sin(ang)
		var x: float = hw * signf(c) * pow(absf(c), 2.0 / exponent)
		var y: float = (y0 + y1) * 0.5 + (y1 - y0) * 0.5 * signf(s) * pow(absf(s), 2.0 / exponent)
		return Vector3(x, y, lerpf(-length * 0.5, length * 0.5, tz))
	mb.add_param_surface(segments, count - 1, fn, Color.WHITE, true, false)


static func _build_wheel_mesh(spec: Dictionary) -> ArrayMesh:
	var radius: float = float(spec["wheel_radius"])
	var tire_w: float = float(spec["wheel_width"])
	var tr_r: float = radius * 0.30
	var tr_w: float = tire_w * 0.5
	var major: float = radius - tr_r
	var rim_r: float = radius * 0.64
	var rim_hw: float = tire_w * 0.22

	var tire := MeshBuilder.new()
	var tire_fn := func(u: float, v: float) -> Vector3:
		var ang: float = u * TAU
		var sect: float = v * TAU
		var rad: float = major + tr_r * cos(sect)
		# Shallow tread grooves on the crown.
		rad += 0.004 * sin(u * 60.0) * maxf(0.0, cos(sect))
		return Vector3(tr_w * sin(sect), rad * cos(ang), rad * sin(ang))
	tire.add_param_surface(48, 18, tire_fn, Color.WHITE, true, true)
	tire.smooth_normals()
	tire.orient_to_normals()

	var rim := MeshBuilder.new()
	var barrel_fn := func(u: float, v: float) -> Vector3:
		var ang: float = u * TAU
		return Vector3(lerpf(-rim_hw, rim_hw, v), cos(ang) * rim_r, sin(ang) * rim_r)
	rim.add_param_surface(28, 1, barrel_fn, Color.WHITE, true, false)
	for side in [-1.0, 1.0]:
		var face_x: float = side * rim_hw
		var face_fn := func(u: float, v: float) -> Vector3:
			var ang: float = u * TAU
			return Vector3(face_x, cos(ang) * rim_r * v, sin(ang) * rim_r * v)
		rim.add_param_surface(28, 3, face_fn, Color.WHITE, true, false)
	rim.smooth_normals()
	rim.orient_to_normals()

	var spokes := MeshBuilder.new()
	for k in range(5):
		var a: float = float(k) * TAU / 5.0
		var basis := Basis(Vector3.RIGHT, a)
		spokes.add_box(Transform3D(basis, Vector3(0.0, cos(a) * rim_r * 0.5, sin(a) * rim_r * 0.5)),
			Vector3(rim_hw * 1.2, rim_r * 0.95, 0.045), Color.WHITE)
	# Brake disc behind the rim.
	var disc_r: float = radius * 0.8
	var disc_x: float = -rim_hw - 0.02
	var disc_fn := func(u: float, v: float) -> Vector3:
		var ang: float = u * TAU
		return Vector3(lerpf(disc_x - 0.02, disc_x, v), cos(ang) * disc_r, sin(ang) * disc_r)
	spokes.add_param_surface(32, 1, disc_fn, Color.WHITE, true, false)
	spokes.smooth_normals()
	spokes.orient_to_normals()

	var tire_mat := StandardMaterial3D.new()
	tire_mat.albedo_color = Color(0.03, 0.03, 0.035)
	tire_mat.roughness = 0.9
	var rim_mat := StandardMaterial3D.new()
	rim_mat.albedo_color = spec["rim_color"]
	rim_mat.metallic = 0.95
	rim_mat.roughness = 0.22
	var disc_mat := StandardMaterial3D.new()
	disc_mat.albedo_color = Color(0.22, 0.22, 0.24)
	disc_mat.metallic = 0.5
	disc_mat.roughness = 0.45

	var mesh := ArrayMesh.new()
	tire.commit_surface(mesh, tire_mat)
	rim.commit_surface(mesh, rim_mat)
	spokes.commit_surface(mesh, disc_mat)
	return mesh
