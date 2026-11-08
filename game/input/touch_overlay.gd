## On-screen driving controls for touch screens (Galaxy Z Fold, phones, tablets).
##
## Left half: drag horizontally to steer (relative to where the finger went down),
## self-centring on release. Right half: analogue throttle and brake pedals. The
## height of the finger inside the pedal zone sets the amount (higher = more).
## Multi-touch is tracked per finger index, so steering and pedals work together.
## Layout uses fractions of the viewport so it adapts to folded and unfolded screens.
class_name TouchOverlay
extends Control

const STEER_RANGE_FRACTION: float = 0.22
const PEDAL_TOP_FRACTION: float = 0.30

var driver: DriverInput
var sensitivity: float = 1.0
var visible_hints: bool = true
var _fingers: Dictionary = {}  # touch index -> {"role": String, "anchor": Vector2}
var _steer_display: float = 0.0
var _throttle_display: float = 0.0
var _brake_display: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	set_process_input(true)


func bind(p_driver: DriverInput) -> void:
	driver = p_driver


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or driver == null:
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_on_press(t.index, t.position)
		else:
			_on_release(t.index)
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		_on_drag(d.index, d.position)


func _on_press(index: int, pos: Vector2) -> void:
	var size: Vector2 = get_viewport_rect().size
	var role: String = _role_at(pos, size)
	if role == "":
		return
	_fingers[index] = {"role": role, "anchor": pos}
	_apply_role(index, pos, size)
	get_viewport().set_input_as_handled()


func _on_drag(index: int, pos: Vector2) -> void:
	if not _fingers.has(index):
		return
	_apply_role(index, pos, get_viewport_rect().size)
	get_viewport().set_input_as_handled()


func _on_release(index: int) -> void:
	if not _fingers.has(index):
		return
	var role: String = _fingers[index]["role"]
	_fingers.erase(index)
	match role:
		"steer":
			driver.touch_steer = 0.0
		"gas":
			driver.touch_throttle = 0.0
		"brake":
			driver.touch_brake = 0.0
	get_viewport().set_input_as_handled()


func _role_at(pos: Vector2, size: Vector2) -> String:
	var top: float = size.y * 0.16
	if pos.y < top:
		return ""
	if pos.x < size.x * 0.5:
		return "steer"
	if pos.y < size.y * PEDAL_TOP_FRACTION:
		return ""
	if pos.x >= size.x * 0.72:
		return "gas"
	return "brake"


func _apply_role(index: int, pos: Vector2, size: Vector2) -> void:
	var f: Dictionary = _fingers[index]
	var role: String = f["role"]
	match role:
		"steer":
			var range_px: float = size.x * STEER_RANGE_FRACTION / maxf(sensitivity, 0.2)
			var dx: float = pos.x - (f["anchor"] as Vector2).x
			driver.touch_steer = clampf(dx / range_px, -1.0, 1.0)
		"gas":
			driver.touch_throttle = _pedal_amount(pos.y, size)
		"brake":
			driver.touch_brake = _pedal_amount(pos.y, size)


## Pedal travel: 0 at the bottom of the screen, 1 at the top of the pedal zone.
func _pedal_amount(y: float, size: Vector2) -> float:
	var top: float = size.y * PEDAL_TOP_FRACTION
	return clampf((size.y - y) / (size.y - top), 0.0, 1.0)


func _process(delta: float) -> void:
	if driver == null:
		return
	var k: float = 1.0 - exp(-delta * 14.0)
	_steer_display = lerpf(_steer_display, driver.steer, k)
	_throttle_display = lerpf(_throttle_display, driver.throttle, k)
	_brake_display = lerpf(_brake_display, driver.brake, k)
	queue_redraw()


func _draw() -> void:
	var touch_device: bool = OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()
	if not visible_hints or not touch_device:
		return
	var size: Vector2 = get_viewport_rect().size
	var u: float = minf(size.x, size.y)
	var font: Font = ThemeDB.fallback_font

	# Steering wheel hint at the lower left.
	var wheel_c := Vector2(size.x * 0.17, size.y * 0.72)
	var wheel_r: float = u * 0.12
	var ring := Color(1, 1, 1, 0.28)
	var angle: float = _steer_display * 2.2
	draw_arc(wheel_c, wheel_r, 0.0, TAU, 64, ring, u * 0.012, true)
	for k in range(3):
		var a: float = angle + float(k) * TAU / 3.0 - PI * 0.5
		var tip: Vector2 = wheel_c + Vector2(cos(a), sin(a)) * wheel_r
		draw_line(wheel_c, tip, ring, u * 0.012, true)
	draw_circle(wheel_c, wheel_r * 0.14, Color(1, 1, 1, 0.35))
	draw_string(font, wheel_c + Vector2(-wheel_r, wheel_r + u * 0.06), "KIEROWNICA",
		HORIZONTAL_ALIGNMENT_CENTER, wheel_r * 2.0, int(u * 0.03), Color(1, 1, 1, 0.45))

	# Pedals at the lower right.
	var top: float = size.y * PEDAL_TOP_FRACTION
	var bottom: float = size.y * 0.92
	var brake_rect := Rect2(size.x * 0.56, top, size.x * 0.13, bottom - top)
	var gas_rect := Rect2(size.x * 0.75, top, size.x * 0.20, bottom - top)
	_draw_pedal(brake_rect, _brake_display, Color(0.95, 0.25, 0.2), "HAMULEC", font, u)
	_draw_pedal(gas_rect, _throttle_display, Color(0.25, 0.9, 0.45), "GAZ", font, u)


func _draw_pedal(rect: Rect2, amount: float, col: Color, label: String, font: Font, u: float) -> void:
	draw_rect(rect, Color(1, 1, 1, 0.08), true)
	draw_rect(rect, Color(1, 1, 1, 0.25), false, maxf(2.0, u * 0.006))
	var fill_h: float = rect.size.y * amount
	draw_rect(Rect2(rect.position.x, rect.position.y + rect.size.y - fill_h, rect.size.x, fill_h),
		Color(col.r, col.g, col.b, 0.45), true)
	draw_string(font, rect.position + Vector2(0.0, -u * 0.02), label,
		HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, int(u * 0.03), Color(1, 1, 1, 0.5))
