@tool
extends RefCounted
## How placement finds surfaces and turns, scales and snaps assets. The
## placement bar edits it, the placer reads it on every hover, and each
## change is remembered in the project's editor metadata.

enum HitMode { COLLIDERS, MESHES, BOTH }

const METADATA_SECTION := "asset_drawer"
const _SAVED: Array[StringName] = [
	&"hit_mode", &"align_to_normal", &"random_enabled", &"random_yaw_degrees",
	&"random_scale_min", &"random_scale_max", &"snap_enabled", &"snap_step",
]

## What the placement ray lands on. With BOTH, the nearer hit wins.
var hit_mode: HitMode = HitMode.BOTH:
	set(value):
		hit_mode = value
		_remember(&"hit_mode", value)
## Tilt assets so their up axis follows the surface they land on.
var align_to_normal: bool = false:
	set(value):
		align_to_normal = value
		_remember(&"align_to_normal", value)

## Give each placed copy a random yaw and scale from the ranges below.
var random_enabled: bool = false:
	set(value):
		random_enabled = value
		_remember(&"random_enabled", value)
## Random yaw goes from 0 up to this many degrees.
var random_yaw_degrees: float = 360.0:
	set(value):
		random_yaw_degrees = value
		_remember(&"random_yaw_degrees", value)
var random_scale_min: float = 0.9:
	set(value):
		random_scale_min = value
		_remember(&"random_scale_min", value)
var random_scale_max: float = 1.1:
	set(value):
		random_scale_max = value
		_remember(&"random_scale_max", value)

## Snap placement to a world grid, kept on the surface that was hit.
var snap_enabled: bool = false:
	set(value):
		snap_enabled = value
		_remember(&"snap_enabled", value)
var snap_step: float = 1.0:
	set(value):
		snap_step = value
		_remember(&"snap_step", value)

var _restoring: bool = false


## Loads the values saved for this project, keeping the defaults for any
## that were never set.
func restore() -> void:
	var settings := EditorInterface.get_editor_settings()
	_restoring = true
	for key: StringName in _SAVED:
		set(key, settings.get_project_metadata(METADATA_SECTION, key, get(key)))
	_restoring = false


func _remember(key: StringName, value: Variant) -> void:
	if not _restoring:
		EditorInterface.get_editor_settings().set_project_metadata(METADATA_SECTION, key, value)
