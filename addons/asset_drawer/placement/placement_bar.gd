@tool
extends HBoxContainer
## Toolbar controls for the placement settings: what the ray lands on, and
## whether assets align to the surface.

const PlacementSettings := preload("placement_settings.gd")

var _settings: PlacementSettings
var _hit_mode: OptionButton
var _align: Button


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

	_align = CheckBox.new()
	_align.text = "Align"
	_align.tooltip_text = "Align to surface: tilt assets so their up axis follows the surface they land on."
	_align.toggled.connect(_on_align_toggled)
	add_child(_align)

	sync()


## Shows the settings' current values, without writing them back.
func sync() -> void:
	_hit_mode.select(_hit_mode.get_item_index(_settings.hit_mode))
	_align.set_pressed_no_signal(_settings.align_to_normal)


func _on_hit_mode_selected(index: int) -> void:
	_settings.hit_mode = _hit_mode.get_item_id(index) as PlacementSettings.HitMode


func _on_align_toggled(pressed: bool) -> void:
	_settings.align_to_normal = pressed
