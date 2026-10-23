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


static func from_path(path: String) -> AssetDrawerEntry:
	var entry := AssetDrawerEntry.new()
	entry.uid = ResourceUID.path_to_uid(path)
	entry.last_path = path
	return entry


## The asset's current path, or an empty string when it's missing.
func resolve_path() -> String:
	var path := ResourceUID.ensure_path(uid)
	return path if path.begins_with("res://") and ResourceLoader.exists(path) else ""


## The file name without its extension, from the last known path if missing.
func display_name() -> String:
	var path := resolve_path()
	return (last_path if path.is_empty() else path).get_file().get_basename()
