## Vehicle specifications. All values are SI units (kg, m, Nm, rpm, m/s).
## Names are original; no manufacturer models or trademarks are used.
class_name CarCatalog
extends RefCounted


static func all() -> Array:
	return [vanta_gt(), kestrel_r(), aurora_veloce()]


static func by_id(id: String) -> Dictionary:
	for spec in all():
		if spec["id"] == id:
			return spec
	return vanta_gt()


## Rear-engine lightweight sports coupe, rear-wheel drive.
static func vanta_gt() -> Dictionary:
	return {
		"id": "vanta_gt",
		"name": "Vanta GT Coupe",
		"drive": "RWD",
		"mass": 1320.0,
		"cg_height": 0.46,
		"wheelbase": 2.62,
		"track_front": 1.60,
		"track_rear": 1.58,
		"length": 4.47,
		"width": 1.86,
		"height": 1.27,
		"wheel_radius": 0.34,
		"wheel_width": 0.245,
		"peak_torque": 430.0,
		"redline": 7000.0,
		"idle": 850.0,
		"gears": [3.20, 2.14, 1.61, 1.27, 1.03, 0.85],
		"final_drive": 3.45,
		"drag_cd": 0.31,
		"frontal_area": 2.1,
		"downforce_cl": 0.05,
		"tire_mu": 1.02,
		"brake_torque": 2600.0,
		"front_split": 0.5,
		"steer_low_deg": 34.0,
		"steer_high_deg": 8.0,
		"body_color": Color(0.10, 0.22, 0.55),
		"rim_color": Color(0.72, 0.74, 0.78),
		"spoiler": false,
		"style": 0,
	}


## Mid-engine supercar, rear-wheel drive with high downforce.
static func kestrel_r() -> Dictionary:
	return {
		"id": "kestrel_r",
		"name": "Kestrel R",
		"drive": "RWD",
		"mass": 1480.0,
		"cg_height": 0.42,
		"wheelbase": 2.70,
		"track_front": 1.66,
		"track_rear": 1.66,
		"length": 4.55,
		"width": 2.00,
		"height": 1.14,
		"wheel_radius": 0.345,
		"wheel_width": 0.285,
		"peak_torque": 620.0,
		"redline": 8200.0,
		"idle": 900.0,
		"gears": [2.90, 2.10, 1.66, 1.38, 1.18, 1.02, 0.90],
		"final_drive": 3.10,
		"drag_cd": 0.29,
		"frontal_area": 1.9,
		"downforce_cl": 0.22,
		"tire_mu": 1.08,
		"brake_torque": 3800.0,
		"front_split": 0.4,
		"steer_low_deg": 30.0,
		"steer_high_deg": 7.0,
		"body_color": Color(0.85, 0.42, 0.06),
		"rim_color": Color(0.1, 0.1, 0.11),
		"spoiler": true,
		"style": 1,
	}


## Grand tourer with all-wheel drive, 40/60 front/rear torque split.
static func aurora_veloce() -> Dictionary:
	return {
		"id": "aurora_veloce",
		"name": "Aurora Veloce",
		"drive": "AWD",
		"mass": 1720.0,
		"cg_height": 0.52,
		"wheelbase": 2.85,
		"track_front": 1.66,
		"track_rear": 1.66,
		"length": 4.85,
		"width": 1.95,
		"height": 1.36,
		"wheel_radius": 0.35,
		"wheel_width": 0.265,
		"peak_torque": 560.0,
		"redline": 7000.0,
		"idle": 800.0,
		"gears": [3.60, 2.40, 1.78, 1.36, 1.08, 0.90, 0.78],
		"final_drive": 3.20,
		"drag_cd": 0.33,
		"frontal_area": 2.4,
		"downforce_cl": 0.12,
		"tire_mu": 1.0,
		"brake_torque": 3200.0,
		"front_split": 0.4,
		"steer_low_deg": 32.0,
		"steer_high_deg": 8.0,
		"body_color": Color(0.74, 0.76, 0.80),
		"rim_color": Color(0.62, 0.64, 0.68),
		"spoiler": false,
		"style": 2,
	}
