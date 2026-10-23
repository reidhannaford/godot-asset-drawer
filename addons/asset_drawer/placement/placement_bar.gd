@tool
extends HFlowContainer
## Toolbar controls for the placement settings: what the ray lands on,
## align to surface, random yaw and scale, and grid snap. While placing it
## also shows the placement keys.

const PlacementSettings := preload("placement_settings.gd")
const PlacementShortcuts := preload("placement_shortcuts.gd")

var _settings: PlacementSettings
var _hit_mode: OptionButton
var _align: CheckBox
var _random: CheckBox
var _random_ranges: Button
var _random_popup: PopupPanel
var _random_yaw: SpinBox
var _random_scale_min: SpinBox
var _random_scale_max: SpinBox
var _snap: CheckBox
var _snap_step: SpinBox
var _hint: Label


func _init(placement_settings: PlacementSettings) -> void:
	name = "AssetDrawerPlacementBar"
	_settings = placement_settings

	_hit_mode = OptionButton.new()
	_hit_mode.tooltip_text = "What placement lands on. With both, the nearer surface wins."
	_hit_mode.add_item("Colliders", PlacementSettings.HitMode.COLLIDERS)
	_hit_mode.add_item("Meshes", PlacementSettings.HitMode.MESHES)
	_hit_mode.add_item("Colliders + meshes", PlacementSettings.HitMode.BOTH)
	_hit_mode.item_selected.connect(_on_hit_mode_selected)
	add_child(_hit_mode)

	_align = _make_check("Align", "Align to surface: tilt assets so their up axis follows the surface they land on.")
	_align.toggled.connect(func(on: bool) -> void: _settings.align_to_normal = on)

	_random = _make_check("Random", "Give each copy a random yaw and scale. The ghost shows the next roll.")
	_random.toggled.connect(func(on: bool) -> void: _settings.random_enabled = on)
	_random_ranges = Button.new()
	_random_ranges.flat = true
	_random_ranges.tooltip_text = "Random ranges"
	_random_ranges.pressed.connect(_show_random_ranges)
	add_child(_random_ranges)
	_build_random_popup()

	_snap = _make_check("Snap", "Snap placement to a world grid, kept on the surface that was hit.")
	_snap.toggled.connect(func(on: bool) -> void: _settings.snap_enabled = on)
	_snap_step = _make_spin(0.01, 100.0, 0.01, " m", "Snap step")
	_snap_step.value_changed.connect(func(value: float) -> void: _settings.snap_step = value)
	add_child(_snap_step)

	_hint = Label.new()
	_hint.visible = false
	_hint.modulate = Color(1.0, 1.0, 1.0, 0.6)
	_hint.size_flags_vertical = SIZE_SHRINK_CENTER
	add_child(_hint)

	sync()


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		_random_ranges.icon = get_theme_icon(&"GuiTabMenuHl", &"EditorIcons")


## Shows the settings' current values, without writing them back.
func sync() -> void:
	_hit_mode.select(_hit_mode.get_item_index(_settings.hit_mode))
	_align.set_pressed_no_signal(_settings.align_to_normal)
	_random.set_pressed_no_signal(_settings.random_enabled)
	_random_yaw.set_value_no_signal(_settings.random_yaw_degrees)
	_random_scale_min.set_value_no_signal(_settings.random_scale_min)
	_random_scale_max.set_value_no_signal(_settings.random_scale_max)
	_snap.set_pressed_no_signal(_settings.snap_enabled)
	_snap_step.set_value_no_signal(_settings.snap_step)


## Shows or hides the reminder of the placement keys.
func show_hint(placing: bool) -> void:
	_hint.text = PlacementShortcuts.hint() if placing else ""
	_hint.visible = placing


func _make_check(text: String, tooltip: String) -> CheckBox:
	var check := CheckBox.new()
	check.text = text
	check.tooltip_text = tooltip
	add_child(check)
	return check


func _make_spin(min_value: float, max_value: float, step: float, suffix: String, tooltip: String) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = min_value
	spin.max_value = max_value
	spin.step = step
	spin.suffix = suffix
	spin.select_all_on_focus = true
	spin.tooltip_text = tooltip
	spin.custom_minimum_size.x = 96.0
	spin.size_flags_vertical = SIZE_SHRINK_CENTER
	return spin


func _build_random_popup() -> void:
	_random_popup = PopupPanel.new()
	var grid := GridContainer.new()
	grid.columns = 2
	_random_popup.add_child(grid)

	_random_yaw = _make_spin(0.0, 360.0, 1.0, "°", "Random yaw goes from 0 up to this")
	_random_yaw.value_changed.connect(func(value: float) -> void: _settings.random_yaw_degrees = value)
	_random_scale_min = _make_spin(0.01, 10.0, 0.01, "", "Smallest random scale")
	_random_scale_min.value_changed.connect(func(value: float) -> void: _settings.random_scale_min = value)
	_random_scale_max = _make_spin(0.01, 10.0, 0.01, "", "Largest random scale")
	_random_scale_max.value_changed.connect(func(value: float) -> void: _settings.random_scale_max = value)
	for row: Array in [["Yaw up to", _random_yaw], ["Scale from", _random_scale_min], ["Scale to", _random_scale_max]]:
		var label := Label.new()
		label.text = row[0]
		grid.add_child(label)
		grid.add_child(row[1] as Control)
	add_child(_random_popup)


func _show_random_ranges() -> void:
	var below := Vector2i(_random_ranges.get_screen_position() + Vector2(0.0, _random_ranges.size.y))
	_random_popup.popup(Rect2i(below, Vector2i.ZERO))


func _on_hit_mode_selected(index: int) -> void:
	_settings.hit_mode = _hit_mode.get_item_id(index) as PlacementSettings.HitMode
