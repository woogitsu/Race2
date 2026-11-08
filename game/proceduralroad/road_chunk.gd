## Geometry of one road segment, expressed relative to its anchor point so that
## float32 precision stays high even hundreds of kilometres from the origin.
class_name RoadChunk
extends RefCounted

var index: int = 0
## World position of the chunk start in double precision: [x, y, z].
var anchor: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0])
## Centreline samples relative to the anchor (sample 0 is (0,0,0)).
var points: PackedVector3Array = PackedVector3Array()
## Heading of each sample in radians. Direction = (sin h, 0, -cos h).
var headings: PackedFloat32Array = PackedFloat32Array()
## Signed curvature (1/m) at each sample. Positive bends toward the right.
var curvatures: PackedFloat32Array = PackedFloat32Array()
## Grade (rise over run) at each sample.
var slopes: PackedFloat32Array = PackedFloat32Array()
## Distance from the world origin of the path (metres) at sample 0.
var start_distance: float = 0.0


func sample_count() -> int:
	return points.size()


## Forward direction (horizontal) for a heading.
static func forward_of(heading: float) -> Vector3:
	return Vector3(sin(heading), 0.0, -cos(heading))


## Right-hand direction (horizontal) for a heading.
static func right_of(heading: float) -> Vector3:
	return Vector3(cos(heading), 0.0, sin(heading))
