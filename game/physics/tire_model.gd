## Simplified Pacejka "magic formula" tyre model with a friction-ellipse limit,
## load sensitivity and wetness. Outputs are normalised to peak 1.0 and then scaled
## by the friction coefficient and normal load in the vehicle controller.
class_name TireModel
extends RefCounted

const LOAD_REFERENCE: float = 3500.0
const WET_GRIP_LOSS: float = 0.38


## Pacejka magic formula: sin(C * atan(B x - E (B x - atan(B x)))).
static func magic(x: float, b: float, c: float, e: float) -> float:
	var bx: float = b * x
	return sin(c * atan(bx - e * (bx - atan(bx))))


static var _long_peak: float = -1.0
static var _lat_peak: float = -1.0


## Normalised longitudinal force for slip ratio kappa (peak exactly 1.0).
static func longitudinal(kappa: float) -> float:
	if _long_peak < 0.0:
		_long_peak = _find_peak(10.5, 1.6, 0.97)
	return magic(clampf(kappa, -1.5, 1.5), 10.5, 1.6, 0.97) / _long_peak


## Normalised lateral force for slip angle alpha (radians, peak exactly 1.0).
## Positive alpha yields a positive value; the controller applies the sign opposing the slip.
static func lateral(alpha: float) -> float:
	if _lat_peak < 0.0:
		_lat_peak = _find_peak(7.0, 1.35, 0.97)
	return magic(clampf(alpha, -1.2, 1.2), 7.0, 1.35, 0.97) / _lat_peak


## Numerical maximum of the magic formula over the positive range; used to normalise.
static func _find_peak(b: float, c: float, e: float) -> float:
	var m: float = 0.0
	for i in range(1, 4001):
		m = maxf(m, magic(float(i) * 0.0005, b, c, e))
	return m


## Friction coefficient including load sensitivity and wetness.
static func friction(mu0: float, normal_load: float, wetness: float) -> float:
	var load_factor: float = clampf(1.0 - 0.10 * (normal_load / LOAD_REFERENCE - 1.0), 0.6, 1.1)
	return mu0 * load_factor * (1.0 - WET_GRIP_LOSS * clampf(wetness, 0.0, 1.0))


## Limits (fx, fy) to the friction ellipse of radius 1 in normalised units.
## Returns a Vector2 with the scaled normalised components.
static func friction_ellipse(fxn: float, fyn: float) -> Vector2:
	var m: float = sqrt(fxn * fxn + fyn * fyn)
	if m > 1.0:
		return Vector2(fxn / m, fyn / m)
	return Vector2(fxn, fyn)
