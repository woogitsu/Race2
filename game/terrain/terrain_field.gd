## Analytic height field of the world, blended to the road near the asphalt.
##
## Far from the road the ground is natural terrain. Within a few tens of metres of
## the centreline it converges to the road elevation, so asphalt is never buried
## and never floats. The function is pure and safe to call from worker threads.
class_name TerrainField
extends RefCounted

var seed_value: int = 1
var biomes: BiomeSampler
var _offset: float = 0.0


func _init(p_seed: int = 1) -> void:
	seed_value = p_seed
	biomes = BiomeSampler.new(p_seed)
	# Spawn point sits at altitude 0 so the first road section is level with the origin.
	_offset = _raw_height(0.0, 0.0)


func _raw_height(x: float, z: float) -> float:
	var m: float = HashNoise.fbm2(x / 1000.0, z / 1000.0, seed_value + 11, 4)
	var mountain: float = clampf(m * 1.6 - 0.15, 0.0, 1.4)
	var alt: float = 230.0 * pow(mountain, 1.7)
	var ridge: float = 1.0 - absf(HashNoise.value2(x / 1900.0, z / 1900.0, seed_value + 17))
	alt += 60.0 * pow(ridge, 4.0) * clampf(mountain * 2.0, 0.0, 1.0)
	alt += 22.0 * HashNoise.fbm2(x / 170.0, z / 170.0, seed_value + 23, 3)
	return alt


## Natural ground height at (x, z), metres above the spawn point.
func natural_height(x: float, z: float) -> float:
	return _raw_height(x, z) - _offset


## Terrain height at a point whose road reference is road_y, lateral distance
## lat_abs from the centreline. Blends from road level (inside the shoulder)
## to natural ground (beyond 30 m).
func blended_height(x: float, z: float, road_y: float, lat_abs: float) -> float:
	var w: float = smoothstep(6.5, 30.0, lat_abs)
	return lerpf(road_y, natural_height(x, z), w)
