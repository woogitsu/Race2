## Smooth biome and ground-colour fields. Biomes blend gradually: every value is
## a continuous function of world position, so transitions never snap.
class_name BiomeSampler
extends RefCounted

const MEADOW := Color(0.36, 0.50, 0.20)
const FOREST := Color(0.12, 0.29, 0.10)
const DRY := Color(0.66, 0.56, 0.36)
const ROCK := Color(0.42, 0.40, 0.38)
const SNOW := Color(0.93, 0.94, 0.96)

var seed_value: int = 1


func _init(p_seed: int = 1) -> void:
	seed_value = p_seed


## 0 = open meadow/desert, 1 = dense forest.
func forest_amount(x: float, z: float) -> float:
	var n: float = HashNoise.fbm2(x / 1400.0, z / 1400.0, seed_value + 31, 3)
	return smoothstep(-0.15, 0.35, n)


## 0 = vegetated, 1 = dry/arid.
func dry_amount(x: float, z: float) -> float:
	var n: float = HashNoise.value2(x / 1100.0, z / 1100.0, seed_value + 37)
	return smoothstep(0.30, 0.65, n)


## Ground albedo for a world position and altitude.
func ground_color(x: float, z: float, altitude: float) -> Color:
	var forest: float = forest_amount(x, z)
	var dry: float = dry_amount(x, z) * (1.0 - forest)
	var c: Color = MEADOW.lerp(FOREST, forest).lerp(DRY, dry)
	var rock: float = smoothstep(95.0, 140.0, altitude)
	c = c.lerp(ROCK, rock)
	c = c.lerp(SNOW, smoothstep(170.0, 200.0, altitude))
	return c
