## Simple road-following steering used by the tests and the visual check. It is not
## part of the game: it only demonstrates that the generated road can be driven.
class_name RoadAutopilot
extends RefCounted


## Steering command in -1..1 (positive = right) from the car pose and its road projection.
## proj comes from WorldStreamer.project(): distance, lateral offset and road heading.
static func steer_command(car_forward: Vector3, proj: Dictionary,
		heading_gain: float = 1.6, lateral_gain: float = 0.2) -> float:
	var car_heading: float = atan2(car_forward.x, -car_forward.z)
	var err: float = wrapf(car_heading - float(proj["heading"]), -PI, PI)
	var lat: float = float(proj["lateral"])
	return clampf(-(heading_gain * err + lateral_gain * lat), -1.0, 1.0)
