## In-game HUD: speed, gear, rev arc with redline, distance, time, driving
## assist indicators, and the pause / camera / reset buttons. Layout is relative
## to the viewport and honours the display safe area, so it adapts to folding.
class_name Hud
extends Control

signal pause_pressed
signal camera_pressed
signal reset_pressed
signal shift_up_pressed
signal shift_down_pressed

const ACCENT := Color(0.35, 0.9, 1.0)
const WARN := Color(1.0, 0.55, 0.2)

var _speed: Label
var _speed_unit: Label
var _gear: Label
var _distance: Label
var _time: Label
var _mode: Label
var _abs: Label
var _tc: Label
var _esc: Label
var _manual: Label
var _rpm_ratio: float = 0.0
var _rpm_redline_ratio: float = 0.92
var _btn_pause: Button
var _btn_camera: Button
var _btn_reset: Button
var _btn_up: Button
var _btn_down: Button
var _top_box: VBoxContainer
var _bottom_box: VBoxContainer
var _buttons_box: HBoxContainer
var _pad_right: float = 16.0
var _pad_top: float = 16.0


func _process(_delta: float) -> void:
	# Keep the button row pinned to the top-right corner whatever its width is.
	var vp: Vector2 = get_viewport_rect().size
	_buttons_box.position = Vector2(vp.x - _pad_right - _buttons_box.size.x, _pad_top)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_top_box = VBoxContainer.new()
	_top_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top_box.set_anchors_preset(Control.PRESET_TOP_LEFT)
	add_child(_top_box)
	_distance = _label(_top_box)
	_time = _label(_top_box)
	_mode = _label(_top_box)

	_buttons_box = HBoxContainer.new()
	_buttons_box.add_theme_constant_override("separation", 12)
	add_child(_buttons_box)
	_btn_pause = _button(_buttons_box, "II")
	_btn_camera = _button(_buttons_box, "KAMERA")
	_btn_reset = _button(_buttons_box, "RESET")
	_btn_pause.pressed.connect(func() -> void: pause_pressed.emit())
	_btn_camera.pressed.connect(func() -> void: camera_pressed.emit())
	_btn_reset.pressed.connect(func() -> void: reset_pressed.emit())

	_bottom_box = VBoxContainer.new()
	_bottom_box.alignment = BoxContainer.ALIGNMENT_END
	_bottom_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bottom_box)
	_speed = _label(_bottom_box)
	_speed.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_speed.add_theme_color_override("font_color", Color(1, 1, 1))
	_speed_unit = _label(_bottom_box)
	_speed_unit.text = "km/h"
	_speed_unit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_speed_unit.add_theme_color_override("font_color", ACCENT)
	_gear = _label(_bottom_box)
	_gear.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_gear.add_theme_color_override("font_color", ACCENT)
	var status := HBoxContainer.new()
	status.alignment = BoxContainer.ALIGNMENT_CENTER
	status.add_theme_constant_override("separation", 14)
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bottom_box.add_child(status)
	_abs = _label(status)
	_tc = _label(status)
	_esc = _label(status)
	_manual = _label(status)

	# Manual shift buttons live in the top row, outside the touch-pedal zone.
	_btn_up = _button(_buttons_box, "+")
	_btn_down = _button(_buttons_box, "-")
	_btn_up.pressed.connect(func() -> void: shift_up_pressed.emit())
	_btn_down.pressed.connect(func() -> void: shift_down_pressed.emit())
	_btn_up.visible = false
	_btn_down.visible = false

	get_viewport().size_changed.connect(_relayout)
	_relayout()


func _label(parent: Node) -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 6)
	parent.add_child(l)
	return l


func _button(parent: Node, text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.1, 0.55)
	sb.border_color = Color(0.6, 0.8, 1.0, 0.35)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(14)
	b.add_theme_stylebox_override("normal", sb)
	var hover := sb.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.1, 0.16, 0.22, 0.7)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
	parent.add_child(b)
	return b


## Lays out text sizes and margins from the current viewport and safe area.
func _relayout() -> void:
	var vp: Vector2 = get_viewport_rect().size
	var u: float = minf(vp.x, vp.y)
	var insets: Dictionary = DeviceInfo.safe_area_insets(vp)
	var pad: float = maxf(u * 0.03, 14.0)
	var left: float = pad + float(insets["left"])
	var right: float = pad + float(insets["right"])
	var top: float = pad + float(insets["top"])
	var bottom: float = pad + float(insets["bottom"])

	_top_box.position = Vector2(left, top)
	var small: int = maxi(14, int(u * 0.034))
	for l in [_distance, _time, _mode]:
		(l as Label).add_theme_font_size_override("font_size", small)
	_pad_right = right
	_pad_top = top
	var bsize: float = maxf(u * 0.075, 40.0)
	for b in [_btn_pause, _btn_camera, _btn_reset]:
		(b as Button).custom_minimum_size = Vector2(bsize * 1.9, bsize)
		(b as Button).add_theme_font_size_override("font_size", int(bsize * 0.38))

	_bottom_box.position = Vector2(vp.x * 0.5 - u * 0.3, vp.y - bottom - u * 0.42)
	_bottom_box.size = Vector2(u * 0.6, u * 0.42)
	(_speed as Label).add_theme_font_size_override("font_size", int(u * 0.2))
	(_speed_unit as Label).add_theme_font_size_override("font_size", int(u * 0.045))
	(_gear as Label).add_theme_font_size_override("font_size", int(u * 0.09))
	for l in [_abs, _tc, _esc, _manual]:
		(l as Label).add_theme_font_size_override("font_size", maxi(12, int(u * 0.03)))

	var side: float = bsize
	for b in [_btn_up, _btn_down]:
		(b as Button).custom_minimum_size = Vector2(side, side)
		(b as Button).add_theme_font_size_override("font_size", int(bsize * 0.5))
	queue_redraw()


## Shows or hides the manual-shift buttons.
func set_manual_mode(manual: bool) -> void:
	_btn_up.visible = manual
	_btn_down.visible = manual


## Refreshes all values. Called every frame while driving.
func update_telemetry(t: Dictionary) -> void:
	var speed_kmh: float = float(t.get("speed_kmh", 0.0))
	_speed.text = "%d" % int(round(speed_kmh))
	var g: int = int(t.get("gear", 1))
	_gear.text = "R" if g < 0 else ("N" if g == 0 else str(g))
	_distance.text = "Dystans  %.2f km" % float(t.get("distance_km", 0.0))
	var secs: int = int(t.get("time_s", 0.0))
	_time.text = "Czas  %02d:%02d" % [secs / 60, secs % 60]
	_mode.text = str(t.get("mode", ""))
	_set_flag(_abs, "ABS", bool(t.get("abs", false)), bool(t.get("abs_enabled", true)))
	_set_flag(_tc, "TC", bool(t.get("tc", false)), bool(t.get("tc_enabled", true)))
	_set_flag(_esc, "ESC", bool(t.get("esc", false)), bool(t.get("esc_enabled", true)))
	_manual.text = "" if bool(t.get("auto_gearbox", true)) else "MANUAL"
	_manual.add_theme_color_override("font_color", ACCENT)
	var rpm: float = float(t.get("rpm", 0.0))
	var redline: float = maxf(float(t.get("redline", 7000.0)), 1.0)
	_rpm_ratio = clampf(rpm / redline, 0.0, 1.05)
	_rpm_redline_ratio = 0.93
	queue_redraw()


func _set_flag(l: Label, name: String, active: bool, enabled: bool) -> void:
	if not enabled:
		l.text = ""
		return
	l.text = name
	var col: Color = WARN if active else Color(0.6, 0.65, 0.7, 0.8)
	l.add_theme_color_override("font_color", col)


func _draw() -> void:
	var vp: Vector2 = get_viewport_rect().size
	var u: float = minf(vp.x, vp.y)
	var center := Vector2(vp.x * 0.5, vp.y - u * 0.36)
	var radius: float = u * 0.33
	var start: float = PI * 0.75
	var sweep: float = PI * 1.5
	var width: float = maxf(4.0, u * 0.022)
	draw_arc(center, radius, start, start + sweep, 96, Color(1, 1, 1, 0.12), width, true)
	var red_from: float = start + sweep * _rpm_redline_ratio
	draw_arc(center, radius, red_from, start + sweep, 32, Color(1.0, 0.3, 0.25, 0.35), width, true)
	var filled: float = minf(_rpm_ratio, 1.0) * sweep
	if filled > 0.0:
		var col: Color = ACCENT.lerp(Color(1.0, 0.35, 0.25), smoothstep(0.85, 1.0, _rpm_ratio))
		draw_arc(center, radius, start, start + filled, 96, col, width, true)
