## Device and display helpers: platform detection and safe-area insets for
## foldable and notched screens. All values are in viewport pixels.
class_name DeviceInfo
extends RefCounted


## Insets (top, left, bottom, right) of the usable display area, converted to viewport pixels.
## On platforms without a safe-area API the insets are zero.
static func safe_area_insets(viewport_size: Vector2) -> Dictionary:
	var zero: Dictionary = {"top": 0.0, "left": 0.0, "bottom": 0.0, "right": 0.0}
	var screen: Vector2i = DisplayServer.screen_get_size()
	var area: Rect2i = DisplayServer.get_display_safe_area()
	if screen.x <= 0 or screen.y <= 0 or area.size == Vector2i.ZERO:
		return zero
	var sx: float = viewport_size.x / float(screen.x)
	var sy: float = viewport_size.y / float(screen.y)
	return {
		"top": maxf(0.0, float(area.position.y) * sy),
		"left": maxf(0.0, float(area.position.x) * sx),
		"bottom": maxf(0.0, float(screen.y - (area.position.y + area.size.y)) * sy),
		"right": maxf(0.0, float(screen.x - (area.position.x + area.size.x)) * sx),
	}

