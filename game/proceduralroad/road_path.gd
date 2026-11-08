## Deterministic, infinite centreline generator.
##
## The road is a sequence of chunks. Curvature and grade are smooth functions of
## distance and the seed, integrated sequentially. Only the state at each chunk
## boundary is cached (four floats per chunk), so revisiting or reversing into an
## earlier chunk regenerates exactly the same geometry without storing it.
##
## Curvature is soft-clamped (tanh) to MIN_TURN_RADIUS, so the path is C1 and its
## curvature is continuous. A heading controller keeps the road from winding back
## on itself over long distances.
class_name RoadPath
extends RefCounted

var seed_value: int = 1

## Boundary states: _boundary[i] = PackedFloat64Array([x, y, z, heading]) at the
## start of chunk i. Only grows; never stores geometry.
var _boundary: Array = []


func _init(p_seed: int = 1) -> void:
	seed_value = p_seed
	_boundary.append(PackedFloat64Array([0.0, 0.0, 0.0, 0.0]))


## Smooth, bounded curvature from the seeded noise plus a heading controller.
func curvature_at(s: float, heading: float) -> float:
	var raw: float = 0.0075 * HashNoise.value1(s / 240.0, seed_value + 1) \
		+ 0.0040 * HashNoise.value1(s / 85.0, seed_value + 2)
	# Macro heading keeps the road drifting around the start direction.
	var macro_heading: float = 1.1 * HashNoise.value1(s / 1500.0, seed_value + 7)
	var err: float = wrapf(heading - macro_heading, -PI, PI)
	raw -= 0.0016 * err
	return GameConfig.MAX_CURVATURE * tanh(raw / GameConfig.MAX_CURVATURE)


## Smooth, bounded grade at distance s.
func slope_at(s: float) -> float:
	var raw: float = 0.075 * HashNoise.value1(s / 320.0, seed_value + 3) \
		+ 0.030 * HashNoise.value1(s / 110.0, seed_value + 4)
	return GameConfig.MAX_GRADE * tanh(raw / GameConfig.MAX_GRADE)


## Returns the chunk with the given index. Deterministic for any call order.
func generate_chunk(index: int) -> RoadChunk:
	if index < 0:
		return _straight_chunk(index)
	_ensure_boundary(index)
	var start: PackedFloat64Array = _boundary[index]
	var chunk := RoadChunk.new()
	chunk.index = index
	chunk.start_distance = float(index) * GameConfig.CHUNK_LENGTH
	chunk.anchor = PackedFloat64Array([start[0], start[1], start[2]])

	var n: int = GameConfig.SAMPLES_PER_CHUNK + 1
	chunk.points.resize(n)
	chunk.headings.resize(n)
	chunk.curvatures.resize(n)
	chunk.slopes.resize(n)

	var x: float = start[0]
	var y: float = start[1]
	var z: float = start[2]
	var h: float = start[3]
	var ds: float = GameConfig.SAMPLE_STEP
	var s0: float = chunk.start_distance

	for k in range(GameConfig.SAMPLES_PER_CHUNK):
		var s: float = s0 + float(k) * ds
		var kap: float = curvature_at(s, h)
		var sl: float = slope_at(s)
		chunk.points[k] = Vector3(x - start[0], y - start[1], z - start[2])
		chunk.headings[k] = h
		chunk.curvatures[k] = kap
		chunk.slopes[k] = sl
		# Midpoint integration of heading and position.
		var h_next: float = h + kap * ds
		var h_mid: float = 0.5 * (h + h_next)
		x += sin(h_mid) * ds
		z += -cos(h_mid) * ds
		y += sl * ds
		h = h_next

	# Final sample: the exact state that chunk index+1 starts from.
	var last: int = GameConfig.SAMPLES_PER_CHUNK
	chunk.points[last] = Vector3(x - start[0], y - start[1], z - start[2])
	chunk.headings[last] = h
	chunk.curvatures[last] = curvature_at(s0 + float(last) * ds, h)
	chunk.slopes[last] = slope_at(s0 + float(last) * ds)
	return chunk


## Road behind the start line: a flat, straight approach that continues the start
## heading (-Z) backwards, so the car can always drive and reverse on asphalt.
func _straight_chunk(index: int) -> RoadChunk:
	var chunk := RoadChunk.new()
	chunk.index = index
	chunk.start_distance = float(index) * GameConfig.CHUNK_LENGTH
	# Chunk -k starts k chunks behind the origin, along +Z.
	chunk.anchor = PackedFloat64Array([0.0, 0.0, -float(index) * GameConfig.CHUNK_LENGTH])
	var n: int = GameConfig.SAMPLES_PER_CHUNK + 1
	chunk.points.resize(n)
	chunk.headings.resize(n)
	chunk.curvatures.resize(n)
	chunk.slopes.resize(n)
	for k in range(n):
		chunk.points[k] = Vector3(0.0, 0.0, -float(k) * GameConfig.SAMPLE_STEP)
		chunk.headings[k] = 0.0
		chunk.curvatures[k] = 0.0
		chunk.slopes[k] = 0.0
	return chunk


## Ensures boundary state for index exists, integrating forward from the last cached one.
func _ensure_boundary(index: int) -> void:
	while _boundary.size() <= index:
		var prev_index: int = _boundary.size() - 1
		_boundary.append(_integrate_chunk_end(prev_index))


## Integrates chunk prev_index without keeping samples and returns the end state.
func _integrate_chunk_end(prev_index: int) -> PackedFloat64Array:
	var start: PackedFloat64Array = _boundary[prev_index]
	var x: float = start[0]
	var y: float = start[1]
	var z: float = start[2]
	var h: float = start[3]
	var ds: float = GameConfig.SAMPLE_STEP
	var s0: float = float(prev_index) * GameConfig.CHUNK_LENGTH
	for k in range(GameConfig.SAMPLES_PER_CHUNK):
		var s: float = s0 + float(k) * ds
		var kap: float = curvature_at(s, h)
		var sl: float = slope_at(s)
		var h_next: float = h + kap * ds
		var h_mid: float = 0.5 * (h + h_next)
		x += sin(h_mid) * ds
		z += -cos(h_mid) * ds
		y += sl * ds
		h = h_next
	return PackedFloat64Array([x, y, z, h])


## Number of chunk boundaries known so far (memory diagnostics).
func cached_boundary_count() -> int:
	return _boundary.size()
