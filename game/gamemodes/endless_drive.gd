## Endless Drive session state: distance driven, time, top speed. There is no
## finish line; the road is generated as the car advances.
class_name EndlessDriveMode
extends RefCounted

var odometer_m: float = 0.0
var session_time_s: float = 0.0
var max_speed_kmh: float = 0.0


func reset() -> void:
	odometer_m = 0.0
	session_time_s = 0.0
	max_speed_kmh = 0.0


## speed_mps: actual speed of the car.
func update(delta: float, speed_mps: float) -> void:
	odometer_m += absf(speed_mps) * delta
	session_time_s += delta
	max_speed_kmh = maxf(max_speed_kmh, absf(speed_mps) * 3.6)


func distance_km() -> float:
	return odometer_m / 1000.0
