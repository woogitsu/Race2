## Procedural engine tone: harmonic-rich pulses whose fundamental follows engine
## speed, with load-dependent harmonics and a noise floor. Generated sample by
## sample into an AudioStreamGenerator, so there are no audio assets to ship.
class_name EngineSound
extends AudioStreamPlayer

const MIX_RATE: float = 22050.0
const CYLINDER_PULSES_PER_REV: float = 2.0

var enabled: bool = true
var rpm: float = 900.0
var load: float = 0.0
var _playback: AudioStreamGeneratorPlayback
var _phase: float = 0.0
var _phase2: float = 0.0


func _ready() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	gen.buffer_length = 0.12
	stream = gen
	volume_db = -6.0
	play()
	_playback = get_stream_playback() as AudioStreamGeneratorPlayback


## Sets the engine state from the vehicle. load is throttle in 0..1.
func set_state(engine_rpm: float, throttle: float) -> void:
	rpm = engine_rpm
	load = clampf(throttle, 0.0, 1.0)


func _process(_delta: float) -> void:
	if _playback == null or not enabled:
		return
	var frames: int = _playback.get_frames_available()
	if frames <= 0:
		return
	var f0: float = maxf(rpm, 300.0) / 60.0 * CYLINDER_PULSES_PER_REV
	var f1: float = f0 * 0.5
	var amp: float = 0.05 + 0.13 * load
	var inc0: float = f0 / MIX_RATE
	var inc1: float = f1 / MIX_RATE
	for i in range(frames):
		_phase = fposmod(_phase + inc0, 1.0)
		_phase2 = fposmod(_phase2 + inc1, 1.0)
		var saw: float = _phase * 2.0 - 1.0
		var saw2: float = _phase2 * 2.0 - 1.0
		var sq: float = 1.0 if _phase < 0.45 else -0.4
		var tone: float = saw * 0.45 + sq * 0.25 * load + saw2 * 0.3
		var noise: float = randf_range(-1.0, 1.0) * (0.04 + 0.08 * load)
		var s: float = (tone * amp + noise * 0.4) * 0.8
		_playback.push_frame(Vector2(s, s))
