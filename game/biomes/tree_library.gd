## Shared tree prototype: a trunk and a clustered crown built from noise-displaced
## spheres. One MultiMesh per chunk instances this mesh, so draw calls stay at
## one per chunk for all trees in that chunk.
class_name TreeLibrary
extends RefCounted

static var _mesh: ArrayMesh = null


static func prototype() -> ArrayMesh:
	if _mesh != null:
		return _mesh
	var trunk := MeshBuilder.new()
	var trunk_fn := func(u: float, v: float) -> Vector3:
		var a: float = u * TAU
		var y: float = lerpf(0.0, 2.6, v)
		var r: float = lerpf(0.22, 0.12, v)
		return Vector3(cos(a) * r, y, sin(a) * r)
	trunk.add_param_surface(8, 1, trunk_fn, Color.WHITE, true, false)
	trunk.smooth_normals()
	trunk.orient_to_normals()

	var crown := MeshBuilder.new()
	var blobs: Array = [
		[Vector3(0.0, 3.4, 0.0), 1.6],
		[Vector3(0.7, 2.8, 0.25), 1.2],
		[Vector3(-0.6, 2.6, -0.3), 1.15],
	]
	for blob in blobs:
		var center: Vector3 = blob[0]
		var radius: float = blob[1]
		var blob_fn := func(u: float, v: float) -> Vector3:
			var theta: float = u * TAU
			var phi: float = v * PI
			var dir := Vector3(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta))
			# Low-frequency lumpiness so the crown is not a perfect ball.
			var bump: float = 1.0 + 0.16 * sin(3.0 * theta + 2.0 * phi) * sin(2.0 * phi + center.x)
			return center + dir * radius * bump
		crown.add_param_surface(10, 6, blob_fn, Color(1, 1, 1), true, false)
	crown.smooth_normals()
	crown.orient_to_normals()

	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.32, 0.22, 0.14)
	trunk_mat.roughness = 0.95
	var crown_mat := StandardMaterial3D.new()
	crown_mat.vertex_color_use_as_albedo = true
	crown_mat.albedo_color = Color(0.36, 0.56, 0.22)
	crown_mat.roughness = 0.82
	crown_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	_mesh = ArrayMesh.new()
	trunk.commit_surface(_mesh, trunk_mat)
	crown.commit_surface(_mesh, crown_mat)
	return _mesh
