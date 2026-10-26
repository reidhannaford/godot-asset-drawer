@tool
class_name AssetDrawerEntry
extends Resource
## One asset in a library. Stored by uid, so moving or renaming the file
## doesn't break the library.

## The asset's [code]uid://[/code] string. A file without a uid (a scene
## written by hand, say) is stored by its [code]res://[/code] path instead,
## and only follows a move once it has one.
@export var uid: String = ""
## Where the asset was last seen, shown when the uid no longer resolves.
@export var last_path: String = ""
## How far the asset is turned around Y for its thumbnail, in degrees. The
## thumbnail camera looks at the +Z side, so an asset that faces -Z (as
## nodes that move along their forward do) shows its front at 180.
@export_range(0, 270, 90, "degrees") var thumbnail_turn: int = 0


static func from_path(path: String) -> AssetDrawerEntry:
	var entry := AssetDrawerEntry.new()
	entry.uid = ResourceUID.path_to_uid(path)
	entry.last_path = path
	return entry


## The asset's current path, or an empty string when it's missing.
func resolve_path() -> String:
	var path := ResourceUID.ensure_path(uid)
	return path if path.begins_with("res://") and ResourceLoader.exists(path) else ""


## Turns the thumbnail a quarter turn, [param quarters] times: positive
## swings the asset's front to the right of the tile, negative to the left.
func turn_thumbnail(quarters: int) -> void:
	thumbnail_turn = posmod(thumbnail_turn + quarters * 90, 360)
	emit_changed()


## The file name without its extension, from the last known path if missing.
func display_name() -> String:
	var path := resolve_path()
	return (last_path if path.is_empty() else path).get_file().get_basename()
