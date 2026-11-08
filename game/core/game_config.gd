## Central, read-only constants shared by all modules.
class_name GameConfig
extends RefCounted

## Length of one road chunk along the centreline, metres.
const CHUNK_LENGTH: float = 100.0
## Spacing of centreline samples, metres. Chunk = CHUNK_LENGTH / SAMPLE_STEP steps.
const SAMPLE_STEP: float = 2.0
const SAMPLES_PER_CHUNK: int = 50
## Minimum turn radius of the generated road, metres (curvature limit).
const MIN_TURN_RADIUS: float = 80.0
const MAX_CURVATURE: float = 1.0 / MIN_TURN_RADIUS
## Maximum road grade (rise over run).
const MAX_GRADE: float = 0.08

## Half width of the drivable asphalt, metres (two 3.5 m lanes plus margin).
const ASPHALT_HALF_WIDTH: float = 4.5
## Half width including the gravel shoulder, metres.
const SHOULDER_HALF_WIDTH: float = 6.0
## Lateral position of guard rails, metres.
const RAIL_LATERAL: float = 7.2

## Distance at which the car is re-centred to avoid float precision loss.
const FLOATING_ORIGIN_DISTANCE: float = 1200.0

## Physics gravity used by the vehicle model, m/s^2.
const GRAVITY: float = 9.81
## Air density at sea level, kg/m^3.
const AIR_DENSITY: float = 1.225

const QUALITY_NAMES: PackedStringArray = ["Auto", "Performance", "Balanced", "High", "Ultra"]


## Per-profile rendering budget. Values are chosen so that the Performance
## profile is the default fallback on mid-range Android hardware.
static func quality_profile(index: int) -> Dictionary:
	match index:
		1:
			return {"name": "Performance", "scale3d": 0.66, "chunks_ahead": 7, "tree_density": 0.35,
				"shadows": false, "shadow_size": 1024, "msaa": 0, "view_distance": 900.0}
		2:
			return {"name": "Balanced", "scale3d": 0.8, "chunks_ahead": 9, "tree_density": 0.6,
				"shadows": true, "shadow_size": 2048, "msaa": 0, "view_distance": 1200.0}
		3:
			return {"name": "High", "scale3d": 0.9, "chunks_ahead": 12, "tree_density": 0.85,
				"shadows": true, "shadow_size": 2048, "msaa": 2, "view_distance": 1600.0}
		4:
			return {"name": "Ultra", "scale3d": 1.0, "chunks_ahead": 15, "tree_density": 1.0,
				"shadows": true, "shadow_size": 4096, "msaa": 2, "view_distance": 2200.0}
		_:
			return {"name": "Balanced", "scale3d": 0.8, "chunks_ahead": 9, "tree_density": 0.6,
				"shadows": true, "shadow_size": 2048, "msaa": 0, "view_distance": 1200.0}
