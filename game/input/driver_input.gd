## Merges keyboard, gamepad, touch overlay and accelerometer into one driver state.
## Each source contributes; for steering and pedals the strongest source wins, so a
## keyboard, a pad and touch can be mixed freely.
class_name DriverInput
extends Node

## Touch overlay writes these while fingers are on the screen.
var touch_steer: float = 0.0
var touch_throttle: float = 0.0
var touch_brake: float = 0.0

## Edge-triggered actions consumed once by the owner.
var pressed_camera: bool = false
var pressed_reset: bool = false
var pressed_shift_up: bool = false
var pressed_shift_down: bool = false
var pressed_pause: bool = false

## Output state.
var steer: float = 0.0
var throttle: float = 0.0
var brake: float = 0.0
var handbrake: bool = false

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k: int = (event as InputEventKey).physical_keycode
		match k:
			KEY_C:
				pressed_camera = true
			KEY_R:
				pressed_reset = true
			KEY_E:
				pressed_shift_up = true
			KEY_Q:
				pressed_shift_down = true
			KEY_ESCAPE, KEY_P:
				pressed_pause = true
	elif event is InputEventJoypadButton and event.pressed:
		match (event as InputEventJoypadButton).button_index:
			JOY_BUTTON_Y:
				pressed_camera = true
			JOY_BUTTON_X:
				pressed_reset = true
			JOY_BUTTON_RIGHT_SHOULDER:
				pressed_shift_up = true
			JOY_BUTTON_LEFT_SHOULDER:
				pressed_shift_down = true
			JOY_BUTTON_START:
				pressed_pause = true


## Reads all sources and fills steer, throttle, brake and handbrake.
## sensitivity scales the accelerometer and keyboard steering; tilt_enabled turns on the accelerometer.
func poll(scheme: int, sensitivity: float, tilt_enabled: bool) -> void:
	var kb_steer: float = 0.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		kb_steer -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		kb_steer += 1.0
	var kb_throttle: float = 1.0 if (Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)) else 0.0
	var kb_brake: float = 1.0 if (Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) else 0.0
	handbrake = Input.is_physical_key_pressed(KEY_SPACE)

	var pad_steer: float = 0.0
	var pad_throttle: float = 0.0
	var pad_brake: float = 0.0
	if Input.get_connected_joypads().size() > 0:
		var dead: float = 0.12
		pad_steer = _deadzone(Input.get_joy_axis(0, JOY_AXIS_LEFT_X), dead)
		pad_throttle = _deadzone(Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT), 0.05)
		pad_brake = _deadzone(Input.get_joy_axis(0, JOY_AXIS_TRIGGER_LEFT), 0.05)
		if Input.is_joy_button_pressed(0, JOY_BUTTON_A):
			handbrake = true

	var tilt_steer: float = 0.0
	if tilt_enabled and (scheme == 1 or scheme == 2):
		var g: Vector3 = Input.get_gravity()
		tilt_steer = clampf(-g.x / 4.0 * sensitivity, -1.0, 1.0)

	var drag_steer: float = touch_steer if (scheme == 0 or scheme == 2) else 0.0

	steer = _strongest(_strongest(kb_steer, pad_steer), _strongest(drag_steer, tilt_steer))
	throttle = clampf(maxf(maxf(kb_throttle, pad_throttle), touch_throttle), 0.0, 1.0)
	brake = clampf(maxf(maxf(kb_brake, pad_brake), touch_brake), 0.0, 1.0)


## Clears the edge-triggered flags after the owner has consumed them.
func consume_edges() -> void:
	pressed_camera = false
	pressed_reset = false
	pressed_shift_up = false
	pressed_shift_down = false
	pressed_pause = false


static func _deadzone(v: float, dead: float) -> float:
	if absf(v) < dead:
		return 0.0
	return (v - signf(v) * dead) / (1.0 - dead)


static func _strongest(a: float, b: float) -> float:
	return a if absf(a) >= absf(b) else b
