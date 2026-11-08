## Streams the infinite road in and out.
##
## - Road geometry for the next chunks is generated on the main thread (cheap,
##   sequential, cached boundaries) and the heavy CPU meshing runs on a
##   WorkerThreadPool task. Node and Resource creation happens only on the main
##   thread, within a per-frame time budget.
## - Chunks behind the car are freed; anything the car reverses into is rebuilt
##   from the same seed, so geometry is identical.
## - Floating origin: when the car drifts far from the origin, all chunk nodes and
##   the car are shifted back so float32 positions keep sub-millimetre precision.
class_name WorldStreamer
extends Node3D

signal origin_shifted(shift: Vector3)

const BUDGET_MS: float = 4.0
const MAX_IN_FLIGHT: int = 6

var seed_value: int = 1
var road: RoadPath
var field: TerrainField

## Chunk records: index -> {"node": Node3D, "chunk": RoadChunk, "body": StaticBody3D}
var _chunks: Dictionary = {}
## Tasks in flight: index -> {"task": int, "holder": Dictionary, "chunk": RoadChunk}
var _pending: Dictionary = {}
var _origin: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0])
var _profile: Dictionary = {}
var current_index: int = 0
var _tree_mesh: ArrayMesh = null
var _asphalt_mat: ShaderMaterial
var _terrain_mat: ShaderMaterial
var _marking_mat: StandardMaterial3D
var _rail_mat: StandardMaterial3D
var _chunks_built_total: int = 0


func _ready() -> void:
	_asphalt_mat = WorldMaterials.asphalt()
	_terrain_mat = WorldMaterials.terrain()
	_marking_mat = WorldMaterials.markings()
	_rail_mat = WorldMaterials.rail()
	_tree_mesh = TreeLibrary.prototype()


func setup(p_seed: int, profile: Dictionary) -> void:
	seed_value = p_seed
	road = RoadPath.new(p_seed)
	field = TerrainField.new(p_seed)
	_profile = profile


func set_profile(profile: Dictionary) -> void:
	_profile = profile


func chunk_count() -> int:
	return _chunks.size()


func pending_count() -> int:
	return _pending.size()


func total_chunks_built() -> int:
	return _chunks_built_total


func origin() -> Vector3:
	return Vector3(_origin[0], _origin[1], _origin[2])


## Main per-frame entry point. car_local is the car position in this node's space.
## Returns the road projection of the car: {"distance", "lateral", "heading", "index"}.
func update_streaming(car_local: Vector3, speed_mps: float) -> Dictionary:
	var proj: Dictionary = project(car_local)
	current_index = int(proj.get("index", current_index))

	var ahead: int = clampi(int(ceil(speed_mps * 6.0 / GameConfig.CHUNK_LENGTH)) + 3, 5, int(_profile.get("chunks_ahead", 9)))
	var lo: int = current_index - 2
	var hi: int = current_index + ahead

	# Request missing chunks, nearest first.
	var max_requests: int = MAX_IN_FLIGHT - _pending.size()
	for i in range(current_index - 1, hi + 1):
		if max_requests <= 0:
			break
		if _chunks.has(i) or _pending.has(i):
			continue
		_request(i)
		max_requests -= 1

	# Instantiate finished tasks, within the frame budget.
	_collect_finished(BUDGET_MS)

	# Free chunks that are no longer relevant.
	var to_remove: Array = []
	for key in _chunks.keys():
		if key < lo - 1 or key > hi + 2:
			to_remove.append(key)
	for key in to_remove:
		_free_chunk(key)
	var stale: Array = []
	for key in _pending.keys():
		if key < lo - 1 or key > hi + 2:
			stale.append(key)
	for key in stale:
		_pending.erase(key)

	return proj


## Projects a point onto the nearest loaded centreline sample.
func project(p: Vector3) -> Dictionary:
	var best_d2: float = INF
	var best: Dictionary = {}
	for i in range(current_index - 2, current_index + 3):
		if not _chunks.has(i):
			continue
		var rec: Dictionary = _chunks[i]
		var chunk: RoadChunk = rec["chunk"]
		var node_pos: Vector3 = (rec["node"] as Node3D).position
		var local_p: Vector3 = p - node_pos
		for k in range(chunk.sample_count()):
			var sp: Vector3 = chunk.points[k]
			var dx: float = local_p.x - sp.x
			var dz: float = local_p.z - sp.z
			var d2: float = dx * dx + dz * dz
			if d2 < best_d2:
				best_d2 = d2
				var h: float = chunk.headings[k]
				var right: Vector3 = RoadChunk.right_of(h)
				best = {
					"distance": chunk.start_distance + float(k) * GameConfig.SAMPLE_STEP,
					"lateral": (local_p - sp).dot(right),
					"heading": h,
					"index": i,
					"sample": k,
					"vertical": local_p.y - sp.y,
				}
	if best.is_empty():
		return {"distance": 0.0, "lateral": 0.0, "heading": 0.0, "index": current_index, "sample": 0, "vertical": 0.0}
	return best


## Transform of the road centreline at a projected sample, lifted by height.
## Forward matches the road direction, so a car placed here drives along the road.
func road_transform(proj: Dictionary, height: float) -> Transform3D:
	var idx: int = int(proj.get("index", -1))
	if not _chunks.has(idx):
		return Transform3D(Basis(), Vector3(0.0, height, 0.0))
	var rec: Dictionary = _chunks[idx]
	var chunk: RoadChunk = rec["chunk"]
	var k: int = clampi(int(proj.get("sample", 0)), 0, chunk.sample_count() - 1)
	var node: Node3D = rec["node"]
	var origin: Vector3 = node.position + chunk.points[k] + Vector3.UP * height
	return Transform3D(Basis(Vector3.UP, -chunk.headings[k]), origin)


## True when chunks index..index+count are built and have colliders ready.
func ready_around(index: int, count: int) -> bool:
	for i in range(index, index + count + 1):
		if not _chunks.has(i):
			return false
	return true


## Moves the floating origin by shift (world units). The caller must move the car
## and any other scene nodes by -shift.
func shift_origin(shift: Vector3) -> void:
	_origin[0] += float(shift.x)
	_origin[1] += float(shift.y)
	_origin[2] += float(shift.z)
	for key in _chunks.keys():
		var node: Node3D = _chunks[key]["node"]
		node.position -= shift
	origin_shifted.emit(shift)


## Discards all chunks; used when restarting a session.
func clear() -> void:
	_wait_for_pending()
	for key in _chunks.keys():
		_free_chunk(key)


## Worker tasks reference this node, so they must finish before it is freed.
func _exit_tree() -> void:
	_wait_for_pending()


func _wait_for_pending() -> void:
	for key in _pending.keys():
		WorkerThreadPool.wait_for_task_completion(_pending[key]["task"])
	_pending.clear()


func _request(index: int) -> void:
	var chunk: RoadChunk = road.generate_chunk(index)
	var holder: Dictionary = {"result": null}
	var density: float = float(_profile.get("tree_density", 0.6))
	var task_id: int = WorkerThreadPool.add_task(Callable(self, "_worker_build").bind(chunk, density, holder))
	_pending[index] = {"task": task_id, "holder": holder, "chunk": chunk}


## Runs on a worker thread. Reads only immutable inputs and writes to its own holder.
func _worker_build(chunk: RoadChunk, density: float, holder: Dictionary) -> void:
	var payload: Dictionary = RoadChunkBuilder.build(chunk, field, density)
	var road_mb: MeshBuilder = payload["road"]
	var terrain_mb: MeshBuilder = payload["terrain"]
	var rail_mb: MeshBuilder = payload["rail"]
	payload["faces_road"] = road_mb.to_trimesh_faces()
	payload["faces_terrain"] = terrain_mb.to_trimesh_faces()
	payload["faces_rail"] = rail_mb.to_trimesh_faces()
	holder["result"] = payload


func _collect_finished(budget_ms: float) -> void:
	var start_us: int = Time.get_ticks_usec()
	var done: Array = []
	for key in _pending.keys():
		var entry: Dictionary = _pending[key]
		if WorkerThreadPool.is_task_completed(entry["task"]):
			done.append(key)
	done.sort()
	for key in done:
		if (Time.get_ticks_usec() - start_us) / 1000.0 > budget_ms:
			break
		var entry: Dictionary = _pending[key]
		WorkerThreadPool.wait_for_task_completion(entry["task"])
		_pending.erase(key)
		var payload = entry["holder"]["result"]
		if not (payload is Dictionary):
			continue
		var idx: int = key
		if idx < current_index - 3 or idx > current_index + 40:
			continue
		_instantiate(idx, entry["chunk"], payload)


func _instantiate(index: int, chunk: RoadChunk, payload: Dictionary) -> void:
	var node := Node3D.new()
	node.name = "Chunk_%d" % index
	var anchor: PackedFloat64Array = chunk.anchor
	node.position = Vector3(
		float(anchor[0] - _origin[0]),
		float(anchor[1] - _origin[1]),
		float(anchor[2] - _origin[2]))
	add_child(node)

	var road_mi := MeshInstance3D.new()
	road_mi.name = "Road"
	road_mi.mesh = (payload["road"] as MeshBuilder).to_mesh(_asphalt_mat)
	node.add_child(road_mi)

	var marks_mi := MeshInstance3D.new()
	marks_mi.name = "Markings"
	marks_mi.mesh = (payload["marks"] as MeshBuilder).to_mesh(_marking_mat)
	node.add_child(marks_mi)

	var terrain_mi := MeshInstance3D.new()
	terrain_mi.name = "Terrain"
	terrain_mi.mesh = (payload["terrain"] as MeshBuilder).to_mesh(_terrain_mat)
	node.add_child(terrain_mi)

	var rail_mi := MeshInstance3D.new()
	rail_mi.name = "Rails"
	rail_mi.mesh = (payload["rail"] as MeshBuilder).to_mesh(_rail_mat)
	node.add_child(rail_mi)

	var trees: Array = payload["trees"]
	if not trees.is_empty():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = _tree_mesh
		mm.instance_count = trees.size()
		var colors: PackedColorArray = payload["tree_colors"]
		for t in range(trees.size()):
			mm.set_instance_transform(t, trees[t])
			mm.set_instance_color(t, colors[t])
		var tree_mmi := MultiMeshInstance3D.new()
		tree_mmi.name = "Trees"
		tree_mmi.multimesh = mm
		node.add_child(tree_mmi)

	var body := StaticBody3D.new()
	body.name = "Colliders"
	body.collision_layer = 1
	body.collision_mask = 0
	node.add_child(body)
	for key in ["faces_road", "faces_terrain", "faces_rail"]:
		var faces: PackedVector3Array = payload[key]
		if faces.is_empty():
			continue
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		var cs := CollisionShape3D.new()
		cs.name = key
		cs.shape = shape
		body.add_child(cs)

	_chunks[index] = {"node": node, "chunk": chunk, "body": body}
	_chunks_built_total += 1


func _free_chunk(index: int) -> void:
	var rec: Dictionary = _chunks[index]
	var node: Node3D = rec["node"]
	_chunks.erase(index)
	node.queue_free()
