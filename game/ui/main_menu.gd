## Start and pause menu. Settings are written to SaveSystem as they change.
## Only Endless Drive is playable; the other modes are listed but disabled, so
## nothing presents unfinished content as finished.
class_name MainMenu
extends Control

signal start_requested
signal resume_requested
signal end_session_requested

const SCHEME_NAMES: PackedStringArray = [
	"Dotyk: przeciąganie", "Akcelerometr", "Dotyk + akcelerometr", "Klawiatura / pad",
]
const MODE_NAMES: PackedStringArray = [
	"Nieskończona jazda", "Swobodna jazda", "Na czas", "Wyścig", "Ruch drogowy", "Tryb foto",
]

var _title: Label
var _subtitle: Label
var _car_buttons: Array = []
var _quality: OptionButton
var _scheme: OptionButton
var _rain: CheckBox
var _abs: CheckBox
var _tc: CheckBox
var _esc: CheckBox
var _auto: CheckBox
var _record: Label
var _primary: Button
var _secondary: Button
var _panel: PanelContainer
var _pause_mode: bool = false
var _loading_label: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP

	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.03, 0.06, 0.62)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.06, 0.1, 0.9)
	sb.set_corner_radius_all(18)
	sb.border_color = Color(0.35, 0.8, 1.0, 0.35)
	sb.set_border_width_all(2)
	sb.set_content_margin_all(22)
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.custom_minimum_size = Vector2(560, 0)
	center.add_child(_panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	_panel.add_child(col)

	_title = Label.new()
	_title.text = "INFINITE DRIVE"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_title)
	_subtitle = Label.new()
	_subtitle.text = "Nieskończona droga · Android · Godot 4"
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.modulate = Color(0.7, 0.85, 1.0, 0.9)
	col.add_child(_subtitle)

	col.add_child(_section("Samochód"))
	var car_row := HBoxContainer.new()
	car_row.add_theme_constant_override("separation", 8)
	col.add_child(car_row)
	var group := ButtonGroup.new()
	for spec in CarCatalog.all():
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.text = "%s\n%s · %d kg" % [spec["name"], spec["drive"], int(spec["mass"])]
		b.custom_minimum_size = Vector2(160, 64)
		b.set_meta("car_id", spec["id"])
		car_row.add_child(b)
		_car_buttons.append(b)
		b.pressed.connect(_on_setting_changed)

	col.add_child(_section("Tryb gry"))
	var mode_row := GridContainer.new()
	mode_row.columns = 3
	col.add_child(mode_row)
	for i in range(MODE_NAMES.size()):
		var mb := Button.new()
		mb.text = MODE_NAMES[i]
		mb.disabled = i != 0
		if i != 0:
			mb.tooltip_text = "Wkrótce"
			mb.text += "\n(wkrótce)"
		mb.custom_minimum_size = Vector2(160, 48)
		mode_row.add_child(mb)

	col.add_child(_section("Ustawienia"))
	var grid := GridContainer.new()
	grid.columns = 2
	col.add_child(grid)
	grid.add_child(_caption("Grafika"))
	_quality = OptionButton.new()
	for name in GameConfig.QUALITY_NAMES:
		_quality.add_item(name)
	_quality.item_selected.connect(func(_i: int) -> void: _on_setting_changed())
	grid.add_child(_quality)
	grid.add_child(_caption("Sterowanie"))
	_scheme = OptionButton.new()
	for name in SCHEME_NAMES:
		_scheme.add_item(name)
	_scheme.item_selected.connect(func(_i: int) -> void: _on_setting_changed())
	grid.add_child(_scheme)
	grid.add_child(_caption("Pogoda"))
	_rain = CheckBox.new()
	_rain.text = "Deszcz"
	_rain.toggled.connect(func(_on: bool) -> void: _on_setting_changed())
	grid.add_child(_rain)

	var assists := HBoxContainer.new()
	assists.add_theme_constant_override("separation", 14)
	col.add_child(assists)
	_abs = _check(assists, "ABS")
	_tc = _check(assists, "Kontrola trakcji")
	_esc = _check(assists, "ESC")
	_auto = _check(assists, "Automat")

	_record = Label.new()
	_record.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_record.modulate = Color(0.8, 0.9, 1.0, 0.85)
	col.add_child(_record)

	_loading_label = Label.new()
	_loading_label.text = "Ładowanie trasy…"
	_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_label.visible = false
	col.add_child(_loading_label)

	_primary = Button.new()
	_primary.custom_minimum_size = Vector2(0, 64)
	_primary.pressed.connect(func() -> void:
		if _pause_mode:
			resume_requested.emit()
		else:
			start_requested.emit())
	col.add_child(_primary)

	_secondary = Button.new()
	_secondary.text = "Zakończ sesję"
	_secondary.custom_minimum_size = Vector2(0, 48)
	_secondary.pressed.connect(func() -> void: end_session_requested.emit())
	_secondary.visible = false
	col.add_child(_secondary)

	get_viewport().size_changed.connect(_relayout)
	_relayout()
	_load_from_settings()


func _section(text: String) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.modulate = Color(0.45, 0.85, 1.0)
	return l


func _caption(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


func _check(parent: Node, text: String) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.toggled.connect(func(_on: bool) -> void: _on_setting_changed())
	parent.add_child(c)
	return c


func _relayout() -> void:
	var vp: Vector2 = get_viewport_rect().size
	var u: float = minf(vp.x, vp.y)
	var insets: Dictionary = DeviceInfo.safe_area_insets(vp)
	_panel.custom_minimum_size = Vector2(minf(560.0, vp.x - 32.0 - float(insets["left"]) - float(insets["right"])), 0)
	_title.add_theme_font_size_override("font_size", int(u * 0.1))
	_subtitle.add_theme_font_size_override("font_size", int(u * 0.035))
	_record.add_theme_font_size_override("font_size", int(u * 0.032))
	_loading_label.add_theme_font_size_override("font_size", int(u * 0.035))
	_primary.add_theme_font_size_override("font_size", int(u * 0.05))
	_secondary.add_theme_font_size_override("font_size", int(u * 0.035))


func _load_from_settings() -> void:
	var car_id: String = str(SaveSystem.get_setting("car_id"))
	for b in _car_buttons:
		var btn := b as Button
		btn.set_pressed_no_signal(btn.get_meta("car_id") == car_id)
	_quality.select(int(SaveSystem.get_setting("quality")))
	_scheme.select(int(SaveSystem.get_setting("control_scheme")))
	_rain.set_pressed_no_signal(bool(SaveSystem.get_setting("rain")))
	_abs.set_pressed_no_signal(bool(SaveSystem.get_setting("abs_enabled")))
	_tc.set_pressed_no_signal(bool(SaveSystem.get_setting("tc_enabled")))
	_esc.set_pressed_no_signal(bool(SaveSystem.get_setting("esc_enabled")))
	_auto.set_pressed_no_signal(bool(SaveSystem.get_setting("auto_gearbox")))
	var rec: Dictionary = SaveSystem.records
	_record.text = "Najdłuższa jazda: %.2f km · Najwyższa prędkość: %d km/h · Sesje: %d" % [
		float(rec["best_distance_m"]) / 1000.0, int(float(rec["best_speed_kmh"])), int(rec["sessions"])]


## Writes the controls into SaveSystem.settings.
func _on_setting_changed() -> void:
	for b in _car_buttons:
		var btn := b as Button
		if btn.button_pressed:
			SaveSystem.set_setting("car_id", str(btn.get_meta("car_id")))
	SaveSystem.set_setting("quality", _quality.selected)
	SaveSystem.set_setting("control_scheme", _scheme.selected)
	SaveSystem.set_setting("rain", _rain.button_pressed)
	SaveSystem.set_setting("abs_enabled", _abs.button_pressed)
	SaveSystem.set_setting("tc_enabled", _tc.button_pressed)
	SaveSystem.set_setting("esc_enabled", _esc.button_pressed)
	SaveSystem.set_setting("auto_gearbox", _auto.button_pressed)
	SaveSystem.save_data()


## Shows the start screen.
func show_start() -> void:
	_pause_mode = false
	_primary.text = "START"
	_secondary.visible = false
	_loading_label.visible = false
	_load_from_settings()
	_primary.disabled = false
	show()


## Shows the pause screen over the game.
func show_pause() -> void:
	_pause_mode = true
	_primary.text = "WZNÓW"
	_secondary.visible = true
	_loading_label.visible = false
	_load_from_settings()
	show()


## Shows the loading state while the first road chunks are built.
func show_loading() -> void:
	_primary.disabled = true
	_loading_label.visible = true


func hide_loading() -> void:
	_primary.disabled = false
	_loading_label.visible = false


func selected_car_id() -> String:
	for b in _car_buttons:
		var btn := b as Button
		if btn.button_pressed:
			return str(btn.get_meta("car_id"))
	return "vanta_gt"
