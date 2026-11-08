## Builds all CPU-side geometry for one road chunk: asphalt and shoulders,
## lane markings, guard rails, terrain strip and tree placements.
##
## Pure function of (chunk, terrain field, density). No Nodes or Resources are
## created here, so it can run on a WorkerThreadPool task. Terrain columns are
## laid across the road, compressed on the inside of curves so the ground never
## folds over itself.
class_name RoadChunkBuilder
extends RefCounted

const ROAD_LATERALS: PackedFloat32Array = [-6.0, -4.5, -2.25, 0.0, 2.25, 4.5, 6.0]
const TERRAIN_LATERALS: PackedFloat32Array = [
	-125.0, -100.0, -78.0, -60.0, -46.0, -35.0, -27.0, -20.5, -15.5, -11.5, -8.5, -6.0, -3.0,
	0.0, 3.0, 6.0, 8.5, 11.5, 15.5, 20.5, 27.0, 35.0, 46.0, 60.0, 78.0, 100.0, 125.0,
]
const TERRAIN_MAX_LATERAL: float = 125.0
## Inner side of a curve may extend at most this fraction of the turn radius.
const INNER_RADIUS_FRACTION: float = 0.6
const ROAD_LIFT: float = 0.04
const TREE_ATTEMPTS: int = 150
const TREE_LINE_ALTITUDE: float = 150.0


## Returns a Dictionary of MeshBuilder / arrays:
## road, marks, rail, terrain (MeshBuilder), trees (Array[Transform3D]), tree_colors (PackedColorArray).
static func build(chunk: RoadChunk, field: TerrainField, tree_density: float) -> Dictionary:
	var road := MeshBuilder.new()
	var marks := MeshBuilder.new()
	var rail := MeshBuilder.new()
	var terrain := MeshBuilder.new()
	var n: int = chunk.sample_count()
	var anchor: PackedFloat64Array = chunk.anchor

	# Per-sample frame helpers.
	var rights: PackedVector3Array = PackedVector3Array()
	rights.resize(n)
	for k in range(n):
		rights[k] = RoadChunk.right_of(chunk.headings[k])

	var asphalt_col := Color(0.105, 0.105, 0.115)
	var shoulder_col := Color(0.36, 0.33, 0.29)

	# ---- Road ribbon (asphalt + shoulders) ----
	var road_ids: PackedInt32Array = PackedInt32Array()
	road_ids.resize(n * ROAD_LATERALS.size())
	for k in range(n):
		var p: Vector3 = chunk.points[k]
		var r: Vector3 = rights[k]
		var s_global: float = chunk.start_distance + float(k) * GameConfig.SAMPLE_STEP
		for c in range(ROAD_LATERALS.size()):
			var lat: float = ROAD_LATERALS[c]
			var pos: Vector3 = p + r * lat + Vector3.UP * ROAD_LIFT
			var col: Color = asphalt_col if absf(lat) <= GameConfig.ASPHALT_HALF_WIDTH else shoulder_col
			var uv := Vector2(lat / 6.0, s_global / 6.0)
			road_ids[k * ROAD_LATERALS.size() + c] = road.add_vertex(pos, Vector3.UP, uv, col)
	for k in range(n - 1):
		for c in range(ROAD_LATERALS.size() - 1):
			road.add_quad(
				road_ids[k * ROAD_LATERALS.size() + c],
				road_ids[k * ROAD_LATERALS.size() + c + 1],
				road_ids[(k + 1) * ROAD_LATERALS.size() + c + 1],
				road_ids[(k + 1) * ROAD_LATERALS.size() + c])
	road.smooth_normals()
	road.orient_to_normals()

	# ---- Lane markings ----
	_build_marking_strip(marks, chunk, rights, -4.1, 0.14)
	_build_marking_strip(marks, chunk, rights, 4.1, 0.14)
	_build_dashed_strip(marks, chunk, rights, 0.0, 0.12)
	marks.smooth_normals()
	marks.orient_to_normals()

	# ---- Terrain strip ----
	var nt: int = TERRAIN_LATERALS.size()
	var terrain_ids: PackedInt32Array = PackedInt32Array()
	terrain_ids.resize(n * nt)
	for k in range(n):
		var p: Vector3 = chunk.points[k]
		var r: Vector3 = rights[k]
		var kap: float = chunk.curvatures[k]
		var compress: float = _inner_compression(kap)
		var road_world_y: float = anchor[1] + float(p.y)
		for c in range(nt):
			var lat: float = TERRAIN_LATERALS[c]
			var lat_eff: float = _effective_lateral(lat, kap, compress)
			var lp: Vector3 = p + r * lat_eff
			var wx: float = anchor[0] + float(lp.x)
			var wz: float = anchor[2] + float(lp.z)
			var h_local: float = field.blended_height(wx, wz, road_world_y, absf(lat_eff)) - anchor[1]
			var pos := Vector3(lp.x, h_local, lp.z)
			var col: Color = field.biomes.ground_color(wx, wz, h_local + anchor[1])
			terrain_ids[k * nt + c] = terrain.add_vertex(pos, Vector3.UP, Vector2(lat_eff, 0.0), col)
	for k in range(n - 1):
		for c in range(nt - 1):
			terrain.add_quad(
				terrain_ids[k * nt + c],
				terrain_ids[k * nt + c + 1],
				terrain_ids[(k + 1) * nt + c + 1],
				terrain_ids[(k + 1) * nt + c])
	terrain.smooth_normals()
	terrain.orient_to_normals()

	# ---- Guard rails on both sides, with posts ----
	var rail_ids_l: PackedInt32Array = PackedInt32Array()
	var rail_ids_r: PackedInt32Array = PackedInt32Array()
	rail_ids_l.resize(n * 2)
	rail_ids_r.resize(n * 2)
	for k in range(n):
		var p: Vector3 = chunk.points[k]
		var r: Vector3 = rights[k]
		for side in range(2):
			var lat: float = -GameConfig.RAIL_LATERAL if side == 0 else GameConfig.RAIL_LATERAL
			var lp: Vector3 = p + r * lat
			var wx: float = anchor[0] + float(lp.x)
			var wz: float = anchor[2] + float(lp.z)
			var ground: float = field.blended_height(wx, wz, anchor[1] + float(p.y), absf(lat)) - anchor[1]
			var ids: PackedInt32Array = rail_ids_l if side == 0 else rail_ids_r
			var v_low := Vector3(lp.x, ground + 0.35, lp.z)
			var v_high := Vector3(lp.x, ground + 0.72, lp.z)
			ids[k * 2] = rail.add_vertex(v_low, r * (-1.0 if side == 0 else 1.0), Vector2(0, 0), Color(0.7, 0.72, 0.76))
			ids[k * 2 + 1] = rail.add_vertex(v_high, r * (-1.0 if side == 0 else 1.0), Vector2(0, 1), Color(0.8, 0.82, 0.86))
			# posts every 4 samples (8 m)
			if k % 4 == 0:
				var xf := Transform3D(Basis(), Vector3(lp.x, ground + 0.36, lp.z))
				rail.add_box(xf, Vector3(0.12, 0.7, 0.12), Color(0.45, 0.46, 0.5))
	for side_ids in [rail_ids_l, rail_ids_r]:
		for k in range(n - 1):
			var a: int = side_ids[k * 2]
			var b: int = side_ids[k * 2 + 1]
			var c2: int = side_ids[(k + 1) * 2 + 1]
			var d2: int = side_ids[(k + 1) * 2]
			rail.add_quad(a, d2, c2, b)
	rail.orient_to_normals()

	# ---- Trees ----
	var trees: Array = []
	var tree_colors := PackedColorArray()
	_scatter_trees(chunk, field, rights, tree_density, trees, tree_colors)

	return {
		"road": road,
		"marks": marks,
		"rail": rail,
		"terrain": terrain,
		"trees": trees,
		"tree_colors": tree_colors,
	}


## Compression factor for the inner side of a curve: keeps the terrain inside
## INNER_RADIUS_FRACTION of the radius so parallel offsets never fold over.
static func _inner_compression(kap: float) -> float:
	var k: float = absf(kap)
	if k < 1e-5:
		return 1.0
	return minf(1.0, (INNER_RADIUS_FRACTION / k) / TERRAIN_MAX_LATERAL)


## Lateral distance after inner-side compression (sign is preserved).
static func _effective_lateral(lat: float, kap: float, compress: float) -> float:
	# Positive curvature bends toward +right, so the right side is the inner side.
	var inner: bool = (lat > 0.0 and kap > 0.0) or (lat < 0.0 and kap < 0.0)
	if inner:
		return lat * compress
	return lat


## Thin strip along the road at a constant lateral offset.
static func _build_marking_strip(mb: MeshBuilder, chunk: RoadChunk, rights: PackedVector3Array,
		lat: float, width: float) -> void:
	var n: int = chunk.sample_count()
	var ids_a := PackedInt32Array()
	var ids_b := PackedInt32Array()
	ids_a.resize(n)
	ids_b.resize(n)
	var white := Color(0.92, 0.92, 0.9)
	for k in range(n):
		var p: Vector3 = chunk.points[k]
		var r: Vector3 = rights[k]
		var up := Vector3.UP * (ROAD_LIFT + 0.012)
		ids_a[k] = mb.add_vertex(p + r * (lat - width * 0.5) + up, Vector3.UP, Vector2.ZERO, white)
		ids_b[k] = mb.add_vertex(p + r * (lat + width * 0.5) + up, Vector3.UP, Vector2.ZERO, white)
	for k in range(n - 1):
		mb.add_quad(ids_a[k], ids_b[k], ids_b[k + 1], ids_a[k + 1])


## Dashed centre line: 6 m dash, 6 m gap, sampled on the 2 m grid.
static func _build_dashed_strip(mb: MeshBuilder, chunk: RoadChunk, rights: PackedVector3Array,
		lat: float, width: float) -> void:
	var n: int = chunk.sample_count()
	var white := Color(0.95, 0.85, 0.35)
	var up := Vector3.UP * (ROAD_LIFT + 0.012)
	for k in range(n - 1):
		if (k % 6) >= 3:
			continue
		var p0: Vector3 = chunk.points[k]
		var p1: Vector3 = chunk.points[k + 1]
		var r0: Vector3 = rights[k]
		var r1: Vector3 = rights[k + 1]
		var a: int = mb.add_vertex(p0 + r0 * (lat - width * 0.5) + up, Vector3.UP, Vector2.ZERO, white)
		var b: int = mb.add_vertex(p0 + r0 * (lat + width * 0.5) + up, Vector3.UP, Vector2.ZERO, white)
		var c: int = mb.add_vertex(p1 + r1 * (lat + width * 0.5) + up, Vector3.UP, Vector2.ZERO, white)
		var d: int = mb.add_vertex(p1 + r1 * (lat - width * 0.5) + up, Vector3.UP, Vector2.ZERO, white)
		mb.add_quad(a, b, c, d)


## Deterministic tree placement from (chunk index, seed). Accept/reject uses the biome field.
static func _scatter_trees(chunk: RoadChunk, field: TerrainField, rights: PackedVector3Array,
		density: float, out_trees: Array, out_colors: PackedColorArray) -> void:
	var n: int = chunk.sample_count()
	var anchor: PackedFloat64Array = chunk.anchor
	var attempts: int = int(round(TREE_ATTEMPTS * density))
	var seed_base: int = field.seed_value * 7919 + 1009
	for t in range(attempts):
		var u1: float = HashNoise.rand01(chunk.index, t * 4 + 0, seed_base)
		var u2: float = HashNoise.rand01(chunk.index, t * 4 + 1, seed_base)
		var u3: float = HashNoise.rand01(chunk.index, t * 4 + 2, seed_base)
		var u4: float = HashNoise.rand01(chunk.index, t * 4 + 3, seed_base)
		var k: int = mini(int(u1 * float(n - 1)), n - 2)
		var side: float = 1.0 if u2 < 0.5 else -1.0
		var lat_mag: float = 13.0 + u3 * 105.0
		var p: Vector3 = chunk.points[k]
		var kap: float = chunk.curvatures[k]
		var lat_eff: float = _effective_lateral(side * lat_mag, kap, _inner_compression(kap))
		var lp: Vector3 = p + rights[k] * lat_eff
		var wx: float = anchor[0] + float(lp.x)
		var wz: float = anchor[2] + float(lp.z)
		var ground_world_y: float = field.blended_height(wx, wz, anchor[1] + float(p.y), absf(lat_eff))
		var forest: float = field.biomes.forest_amount(wx, wz)
		var dry: float = field.biomes.dry_amount(wx, wz)
		var accept: float = lerpf(0.12, 1.0, forest) * (1.0 - 0.85 * dry)
		if u4 > accept or ground_world_y > TREE_LINE_ALTITUDE:
			continue
		var scale: float = 0.8 + 0.7 * HashNoise.rand01(chunk.index, t * 4 + 0, seed_base + 5)
		var rot: float = TAU * HashNoise.rand01(chunk.index, t, seed_base + 9)
		var basis := Basis(Vector3.UP, rot).scaled(Vector3(scale, scale * (0.9 + 0.3 * u2), scale))
		out_trees.append(Transform3D(basis, Vector3(lp.x, ground_world_y - anchor[1], lp.z)))
		var tint: float = HashNoise.rand01(chunk.index, t, seed_base + 13)
		out_colors.append(Color(0.82 + 0.3 * tint, 0.9 + 0.15 * tint, 0.82 + 0.2 * (1.0 - tint), 1.0))
