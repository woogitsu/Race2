## Simple road-following steering used by the tests and the visual check. It is not
## part of the game: it only demonstrates that the generated road can be driven.
class_name RoadAutopilot
extends RefCounted


## Steering command in -1..1 (positive = right) from the car pose and its road projection.
## proj comes from WorldStreamer.project(): distance, lateral offset and road heading.
## Cruise speed limited by lateral grip on the upcoming bend (about 0.7 g).
static func target_speed_kmh(proj: Dictionary, cruise_kmh: float) -> float:
	var k: float = maxf(absf(float(proj.get("curvature", 0.0))), 1e-4)
	var limit_kmh: float = sqrt(6.9 / k) * 3.6
	return minf(cruise_kmh, limit_kmh)


static func steer_command(car_forward: Vector3, proj: Dictionary, yaw_rate: float = 0.0,
		heading_gain: float = 1.6, lateral_gain: float = 0.2, yaw_damping: float = 0.0) -> float:
	var car_heading: float = atan2(car_forward.x, -car_forward.z)
	var err: float = wrapf(car_heading - float(proj["heading"]), -PI, PI)
	var lat: float = float(proj["lateral"])
	# The yaw-rate term damps the weave that a pure heading controller produces at speed.
	return clampf(-(heading_gain * err + lateral_gain * lat + yaw_damping * yaw_rate), -1.0, 1.0)
