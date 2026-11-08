## Deterministic integer hash and smooth value noise.
## Every function is pure: the same input always produces the same output,
## on any thread and in any call order. This is what makes the infinite road
## reproducible from a seed.
class_name HashNoise
extends RefCounted


## 32-bit avalanche hash of a 2D lattice point combined with a seed.
static func hash3(x: int, y: int, seed_value: int) -> int:
	var h: int = (x * 374761393 + y * 668265263 + seed_value * 982451653) & 0xFFFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
	h = (h ^ (h >> 16)) & 0xFFFFFFFF
	return h


## Uniform value in [0, 1] for a lattice point.
static func rand01(x: int, y: int, seed_value: int) -> float:
	return float(hash3(x, y, seed_value)) / 4294967295.0


## Uniform value in [-1, 1] for a lattice point.
static func rand_signed(x: int, y: int, seed_value: int) -> float:
	return rand01(x, y, seed_value) * 2.0 - 1.0


## Quintic fade curve: C2-continuous interpolation, so derivatives of the
## noise (and therefore road curvature) stay continuous.
static func quintic(t: float) -> float:
	return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)


## 1D smooth value noise in [-1, 1].
static func value1(x: float, seed_value: int) -> float:
	var xi: int = floori(x)
	var xf: float = x - float(xi)
	var a: float = rand_signed(xi, 0, seed_value)
	var b: float = rand_signed(xi + 1, 0, seed_value)
	return lerpf(a, b, quintic(xf))


## 2D smooth value noise in [-1, 1].
static func value2(x: float, y: float, seed_value: int) -> float:
	var xi: int = floori(x)
	var yi: int = floori(y)
	var u: float = quintic(x - float(xi))
	var v: float = quintic(y - float(yi))
	var a: float = rand_signed(xi, yi, seed_value)
	var b: float = rand_signed(xi + 1, yi, seed_value)
	var c: float = rand_signed(xi, yi + 1, seed_value)
	var d: float = rand_signed(xi + 1, yi + 1, seed_value)
	return lerpf(lerpf(a, b, u), lerpf(c, d, u), v)


## Fractal (fBm) 2D noise, normalised to roughly [-1, 1].
static func fbm2(x: float, y: float, seed_value: int, octaves: int) -> float:
	var sum: float = 0.0
	var amp: float = 0.5
	var norm: float = 0.0
	var fx: float = x
	var fy: float = y
	for o in range(octaves):
		sum += amp * value2(fx, fy, seed_value + o * 101)
		norm += amp
		amp *= 0.5
		fx *= 2.03
		fy *= 2.03
	return sum / maxf(norm, 0.0001)
