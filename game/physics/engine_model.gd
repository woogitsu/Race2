## Engine torque curve, gearbox and automatic shifting logic. Pure state machine;
## the vehicle controller supplies wheel speeds and reads back rpm and torque.
class_name EngineModel
extends RefCounted

const DRIVETRAIN_EFFICIENCY: float = 0.9
const REVERSE_RATIO: float = -3.2
const SHIFT_COOLDOWN: float = 0.45

var peak_torque: float = 400.0
var redline: float = 7000.0
var idle: float = 850.0
var gears: PackedFloat32Array = PackedFloat32Array([3.0, 2.0, 1.5, 1.2, 1.0, 0.85])
var final_drive: float = 3.5
var auto_shift: bool = true
## 0 = neutral, 1..n = forward gears, -1 = reverse.
var gear: int = 1
var rpm: float = 850.0
var _cooldown: float = 0.0

## Normalised torque curve: x = rpm / redline, y = fraction of peak torque.
const CURVE_X: PackedFloat32Array = [0.0, 0.2, 0.4, 0.6, 0.8, 0.92, 1.0]
const CURVE_Y: PackedFloat32Array = [0.55, 0.78, 0.93, 1.0, 0.96, 0.88, 0.8]


func configure(spec: Dictionary) -> void:
	peak_torque = float(spec["peak_torque"])
	redline = float(spec["redline"])
	idle = float(spec["idle"])
	gears = PackedFloat32Array(spec["gears"])
	final_drive = float(spec["final_drive"])
	rpm = idle


## Engine torque (Nm) at an engine speed. Fuel cut at and above the redline.
func torque_at(engine_rpm: float) -> float:
	if engine_rpm >= redline or engine_rpm <= 0.0:
		return 0.0
	var x: float = clampf(engine_rpm / redline, 0.0, 1.0)
	for i in range(CURVE_X.size() - 1):
		if x <= CURVE_X[i + 1]:
			var t: float = (x - CURVE_X[i]) / maxf(CURVE_X[i + 1] - CURVE_X[i], 1e-6)
			return peak_torque * lerpf(CURVE_Y[i], CURVE_Y[i + 1], t)
	return peak_torque * CURVE_Y[CURVE_Y.size() - 1]


func gear_ratio(g: int) -> float:
	if g == -1:
		return REVERSE_RATIO
	if g <= 0 or g > gears.size():
		return 0.0
	return gears[g - 1]


## Gear ratio from engine to wheel, including the final drive.
func total_ratio() -> float:
	return gear_ratio(gear) * final_drive


## Engine speed implied by a driven wheel angular speed in the current gear.
func rpm_from_wheel_speed(wheel_omega: float) -> float:
	return absf(wheel_omega) * absf(total_ratio()) * 60.0 / TAU


## Wheel torque produced at the driven axle from the engine torque in the current gear.
func wheel_torque(throttle: float) -> float:
	var r: float = total_ratio()
	if r == 0.0:
		return 0.0
	var t: float = torque_at(rpm) * clampf(throttle, 0.0, 1.0)
	return t * r * DRIVETRAIN_EFFICIENCY


func shift_up() -> void:
	if gear >= 0 and gear < gears.size():
		gear += 1 if gear > 0 else 1
		_cooldown = SHIFT_COOLDOWN


func shift_down() -> void:
	if gear > 1:
		gear -= 1
	elif gear == 1:
		gear = 0
	_cooldown = SHIFT_COOLDOWN


## Automatic gearbox: upshift near the redline, downshift when the engine lugs,
## and reverse when braking from a standstill.
func update_auto(dt: float, speed_mps: float, throttle: float, brake: float) -> void:
	_cooldown = maxf(0.0, _cooldown - dt)
	if not auto_shift:
		return
	if gear == -1:
		if throttle > 0.05 and speed_mps < 1.0:
			gear = 1
		return
	if gear == 0:
		if throttle > 0.05:
			gear = 1
		elif brake > 0.2 and speed_mps < 1.0:
			gear = -1
		return
	if _cooldown > 0.0:
		return
	if brake > 0.2 and speed_mps < 0.8 and throttle < 0.05:
		gear = -1
		_cooldown = SHIFT_COOLDOWN
		return
	if gear > 0 and rpm > redline * 0.95 and gear < gears.size():
		gear += 1
		_cooldown = SHIFT_COOLDOWN
	elif gear > 1 and rpm < redline * 0.36:
		gear -= 1
		_cooldown = SHIFT_COOLDOWN
