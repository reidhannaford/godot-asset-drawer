@tool
extends RefCounted
## How placement finds surfaces and orients assets. The placement bar edits
## it, the placer reads it on every hover, and each change is remembered in
## the project's editor metadata.

enum HitMode { COLLIDERS, MESHES, BOTH }

const METADATA_SECTION := "asset_drawer"

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

var _restoring: bool = false


## Loads the values saved for this project, keeping the defaults for any
## that were never set.
func restore() -> void:
	var settings := EditorInterface.get_editor_settings()
	_restoring = true
	hit_mode = settings.get_project_metadata(METADATA_SECTION, "hit_mode", hit_mode) as HitMode
	align_to_normal = settings.get_project_metadata(METADATA_SECTION, "align_to_normal", align_to_normal) as bool
	_restoring = false


func _remember(key: StringName, value: Variant) -> void:
	if not _restoring:
		EditorInterface.get_editor_settings().set_project_metadata(METADATA_SECTION, key, value)
