## Persistent settings and records, stored as JSON in user://.
## Loading validates every field against its default, so a corrupt or outdated
## file falls back to defaults instead of breaking the game.
extends Node

const SAVE_PATH: String = "user://savegame.json"
const SAVE_VERSION: int = 1

var settings: Dictionary = {}
var records: Dictionary = {}


func _ready() -> void:
	load_data()


static func default_settings() -> Dictionary:
	return {
		"quality": 0,
		"car_id": "vanta_gt",
		"control_scheme": 0,
		"steer_sensitivity": 1.0,
		"tilt_enabled": false,
		"auto_gearbox": true,
		"abs_enabled": true,
		"tc_enabled": true,
		"esc_enabled": true,
		"rain": false,
		"world_seed": 20260501,
		"hints_visible": true,
	}


static func default_records() -> Dictionary:
	return {
		"best_distance_m": 0.0,
		"best_speed_kmh": 0.0,
		"total_distance_m": 0.0,
		"total_time_s": 0.0,
		"sessions": 0,
	}


func load_data() -> void:
	var data: Dictionary = read_file(SAVE_PATH)
	settings = _validated(default_settings(), data.get("settings", {}))
	records = _validated(default_records(), data.get("records", {}))


func save_data() -> bool:
	return write_file(SAVE_PATH, {
		"version": SAVE_VERSION,
		"settings": settings,
		"records": records,
	})


## Reads and parses a JSON file. Returns an empty dictionary on any failure.
static func read_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("SaveSystem: cannot open %s (error %d)" % [path, FileAccess.get_open_error()])
		return {}
	var text: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("SaveSystem: invalid JSON in %s" % path)
		return {}
	return parsed


## Writes a dictionary as JSON. Returns true on success.
static func write_file(path: String, data: Dictionary) -> bool:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("SaveSystem: cannot write %s (error %d)" % [path, FileAccess.get_open_error()])
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	return true


## Copies keys from source into a copy of defaults when the type matches.
static func _validated(defaults: Dictionary, source: Variant) -> Dictionary:
	var out: Dictionary = defaults.duplicate()
	if typeof(source) != TYPE_DICTIONARY:
		return out
	for key in defaults.keys():
		if not (source as Dictionary).has(key):
			continue
		var value: Variant = (source as Dictionary)[key]
		var want: int = typeof(defaults[key])
		if want == TYPE_INT and (typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT):
			out[key] = int(value)
		elif want == TYPE_FLOAT and (typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT):
			out[key] = float(value)
		elif typeof(value) == want:
			out[key] = value
	return out


func set_setting(key: String, value: Variant) -> void:
	settings[key] = value


func get_setting(key: String) -> Variant:
	return settings.get(key, default_settings().get(key))


## Counts a new driving session.
func begin_session() -> void:
	records["sessions"] = int(records["sessions"]) + 1


## Checkpoint of the running session: adds the increments since the last checkpoint
## to the totals and updates the bests with the session's current values. Safe to
## call repeatedly (pause, background, periodic saves).
func checkpoint(delta_distance_m: float, delta_time_s: float, session_distance_m: float,
		session_max_speed_kmh: float) -> void:
	records["total_distance_m"] = float(records["total_distance_m"]) + maxf(delta_distance_m, 0.0)
	records["total_time_s"] = float(records["total_time_s"]) + maxf(delta_time_s, 0.0)
	records["best_distance_m"] = maxf(float(records["best_distance_m"]), session_distance_m)
	records["best_speed_kmh"] = maxf(float(records["best_speed_kmh"]), session_max_speed_kmh)
	save_data()
