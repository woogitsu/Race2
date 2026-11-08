## Lightweight CPU-side mesh accumulator. Pure data (no Nodes or Resources), so
## it can be filled on a worker thread and committed to an ArrayMesh afterwards.
##
## Winding follows Godot's convention (front faces are clockwise). orient_to_normals()
## fixes any triangle whose winding disagrees with the supplied vertex normals.
class_name MeshBuilder
extends RefCounted

var verts: PackedVector3Array = PackedVector3Array()
var norms: PackedVector3Array = PackedVector3Array()
var uvs: PackedVector2Array = PackedVector2Array()
var cols: PackedColorArray = PackedColorArray()
var idx: PackedInt32Array = PackedInt32Array()


func vertex_count() -> int:
	return verts.size()


func triangle_count() -> int:
	return idx.size() / 3


func is_empty() -> bool:
	return verts.is_empty()


func add_vertex(p: Vector3, n: Vector3 = Vector3.UP, uv: Vector2 = Vector2.ZERO, c: Color = Color.WHITE) -> int:
	verts.append(p)
	norms.append(n)
	uvs.append(uv)
	cols.append(c)
	return verts.size() - 1


func add_triangle(a: int, b: int, c: int) -> void:
	idx.append(a)
	idx.append(b)
	idx.append(c)


func add_quad(a: int, b: int, c: int, d: int) -> void:
	idx.append(a)
	idx.append(b)
	idx.append(c)
	idx.append(a)
	idx.append(c)
	idx.append(d)


## Oriented box with flat per-face normals (for trim, posts, spokes, lights).
func add_box(xf: Transform3D, size: Vector3, c: Color) -> void:
	var hx: float = size.x * 0.5
	var hy: float = size.y * 0.5
	var hz: float = size.z * 0.5
	# Each face: four corners in order, and its outward normal.
	var faces: Array = [
		[Vector3(hx, -hy, -hz), Vector3(hx, hy, -hz), Vector3(hx, hy, hz), Vector3(hx, -hy, hz), Vector3.RIGHT],
		[Vector3(-hx, -hy, hz), Vector3(-hx, hy, hz), Vector3(-hx, hy, -hz), Vector3(-hx, -hy, -hz), Vector3.LEFT],
		[Vector3(-hx, hy, -hz), Vector3(hx, hy, -hz), Vector3(hx, hy, hz), Vector3(-hx, hy, hz), Vector3.UP],
		[Vector3(-hx, -hy, hz), Vector3(hx, -hy, hz), Vector3(hx, -hy, -hz), Vector3(-hx, -hy, -hz), Vector3.DOWN],
		[Vector3(-hx, -hy, hz), Vector3(hx, -hy, hz), Vector3(hx, hy, hz), Vector3(-hx, hy, hz), Vector3.BACK],
		[Vector3(hx, -hy, -hz), Vector3(-hx, -hy, -hz), Vector3(-hx, hy, -hz), Vector3(hx, hy, -hz), Vector3.FORWARD],
	]
	var basis: Basis = xf.basis
	for face in faces:
		var n: Vector3 = (basis * (face[4] as Vector3)).normalized()
		var base: int = verts.size()
		for k in range(4):
			add_vertex(xf * (face[k] as Vector3), n, Vector2(float(k & 1), float(k >> 1)), c)
		add_quad(base, base + 1, base + 2, base + 3)


## Parametric surface: fn(u, v) -> Vector3 sampled on an nu x nv grid.
## wrap_u / wrap_v join the first and last sample (closed surfaces such as tyres).
func add_param_surface(nu: int, nv: int, fn: Callable, c: Color, wrap_u: bool = true, wrap_v: bool = false) -> void:
	var base: int = verts.size()
	var cols_n: int = nu if wrap_u else nu + 1
	var rows_n: int = nv if wrap_v else nv + 1
	for j in range(rows_n):
		var v: float = float(j) / float(nv)
		for i in range(cols_n):
			var u: float = float(i) / float(nu)
			var p: Vector3 = fn.call(u, v)
			add_vertex(p, Vector3.UP, Vector2(u, v), c)
	for j in range(nv):
		var j2: int = (j + 1) % rows_n if wrap_v else j + 1
		for i in range(nu):
			var i2: int = (i + 1) % cols_n if wrap_u else i + 1
			var a: int = base + j * cols_n + i
			var b: int = base + j * cols_n + i2
			var cc: int = base + j2 * cols_n + i2
			var d: int = base + j2 * cols_n + i
			add_quad(a, b, cc, d)


## Area-weighted smooth normals for all vertices (use only on closed or grid-like parts).
func smooth_normals() -> void:
	for i in range(norms.size()):
		norms[i] = Vector3.ZERO
	var i: int = 0
	while i < idx.size():
		var a: Vector3 = verts[idx[i]]
		var b: Vector3 = verts[idx[i + 1]]
		var c: Vector3 = verts[idx[i + 2]]
		var fn: Vector3 = (b - a).cross(c - a)
		norms[idx[i]] += fn
		norms[idx[i + 1]] += fn
		norms[idx[i + 2]] += fn
		i += 3
	for k in range(norms.size()):
		var n: Vector3 = norms[k]
		norms[k] = n.normalized() if n.length_squared() > 1e-12 else Vector3.UP


## Flips triangles whose winding does not agree with their vertex normals.
func orient_to_normals() -> void:
	var i: int = 0
	while i < idx.size():
		var a: Vector3 = verts[idx[i]]
		var b: Vector3 = verts[idx[i + 1]]
		var c: Vector3 = verts[idx[i + 2]]
		var n: Vector3 = norms[idx[i]] + norms[idx[i + 1]] + norms[idx[i + 2]]
		# Godot front faces are clockwise: the face cross product opposes the normal.
		if (b - a).cross(c - a).dot(n) > 0.0:
			var t: int = idx[i + 1]
			idx[i + 1] = idx[i + 2]
			idx[i + 2] = t
		i += 3



## Builds the packed arrays expected by ArrayMesh.add_surface_from_arrays.
func to_arrays() -> Array:
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	return arr


## Appends this builder as a new surface of mesh. Call on the main thread.
func commit_surface(mesh: ArrayMesh, material: Material) -> void:
	if is_empty():
		return
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, to_arrays())
	if material != null:
		mesh.surface_set_material(mesh.get_surface_count() - 1, material)


## Appends a new surface to a fresh ArrayMesh containing only this builder.
func to_mesh(material: Material) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	commit_surface(mesh, material)
	return mesh


## Convenience: concave collision shape from this builder's triangles.
func to_trimesh_faces() -> PackedVector3Array:
	var faces := PackedVector3Array()
	faces.resize(idx.size())
	for k in range(idx.size()):
		faces[k] = verts[idx[k]]
	return faces
