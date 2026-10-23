@tool
class_name AssetDrawerLibrary
extends AssetDrawerFolder
## A curated set of assets for the drawer, filed in nested folders. Saved as
## a .tres anywhere in the project; its file name is its display name, and
## the library itself is the root folder, holding the assets filed nowhere
## in particular.


func display_name() -> String:
	return resource_path.get_file().get_basename()


## The entry for [param uid] anywhere in the library, or null.
func find_uid(uid: String) -> AssetDrawerEntry:
	for entry: AssetDrawerEntry in all_entries():
		if entry.uid == uid:
			return entry
	return null


## The folder [param entry] is filed in, or null when it isn't in the library.
func folder_of(entry: AssetDrawerEntry) -> AssetDrawerFolder:
	for folder: AssetDrawerFolder in _all_folders():
		if folder.entries.has(entry):
			return folder
	return null


## The folder holding [param folder], or null for the library itself or a
## folder from somewhere else.
func parent_of(folder: AssetDrawerFolder) -> AssetDrawerFolder:
	for candidate: AssetDrawerFolder in _all_folders():
		if candidate.folders.has(folder):
			return candidate
	return null


## Files [param moved] in [param into], just before [param before] (or at the
## end when it's null). Entries already in the library move from wherever
## they were; new ones are added.
func move_entries(moved: Array[AssetDrawerEntry], into: AssetDrawerFolder, before: AssetDrawerEntry) -> void:
	# Dropping a group onto one of its own members anchors on the next entry
	# that isn't moving.
	var anchor: AssetDrawerEntry = null
	var start := into.entries.find(before) if before != null else -1
	if start != -1:
		for i: int in range(start, into.entries.size()):
			if not moved.has(into.entries[i]):
				anchor = into.entries[i]
				break
	for folder: AssetDrawerFolder in _all_folders():
		for entry: AssetDrawerEntry in moved:
			folder.entries.erase(entry)
	var at := into.entries.find(anchor) if anchor != null else into.entries.size()
	for i: int in moved.size():
		into.entries.insert(at + i, moved[i])
	emit_changed()


func remove(removed: Array[AssetDrawerEntry]) -> void:
	for folder: AssetDrawerFolder in _all_folders():
		for entry: AssetDrawerEntry in removed:
			folder.entries.erase(entry)
	emit_changed()


## Adds an empty folder called [param folder_name] at the end of [param parent].
func add_folder(parent: AssetDrawerFolder, folder_name: String) -> AssetDrawerFolder:
	var folder := AssetDrawerFolder.new()
	folder.name = folder_name
	parent.folders.append(folder)
	emit_changed()
	return folder


func rename_folder(folder: AssetDrawerFolder, new_name: String) -> void:
	folder.name = new_name
	emit_changed()


## Removes [param folder] but keeps what was in it: its assets join the end
## of its parent's, and its subfolders take its place.
func delete_folder(folder: AssetDrawerFolder) -> void:
	var parent := parent_of(folder)
	if parent == null:
		return
	parent.entries.append_array(folder.entries)
	var at := parent.folders.find(folder)
	parent.folders.remove_at(at)
	for i: int in folder.folders.size():
		parent.folders.insert(at + i, folder.folders[i])
	emit_changed()


## Moves [param folder] into [param into], just before [param before] (or at
## the end when it's null). Refuses to move a folder into itself or below it.
func move_folder(folder: AssetDrawerFolder, into: AssetDrawerFolder, before: AssetDrawerFolder) -> bool:
	var parent := parent_of(folder)
	if parent == null or folder.contains_folder(into) or folder == before:
		return false
	parent.folders.erase(folder)
	var at := into.folders.find(before) if before != null else -1
	into.folders.insert(at if at != -1 else into.folders.size(), folder)
	emit_changed()
	return true


## Records where each moved asset now lives, and swaps a stored path for a
## uid once the file has one. Returns whether anything changed, so the caller
## knows to save.
func refresh_paths() -> bool:
	var changed := false
	for entry: AssetDrawerEntry in all_entries():
		var path := entry.resolve_path()
		if path.is_empty():
			continue
		var uid := ResourceUID.path_to_uid(path)
		if path != entry.last_path or uid != entry.uid:
			entry.last_path = path
			entry.uid = uid
			changed = true
	if changed:
		emit_changed()
	return changed


func _all_folders() -> Array[AssetDrawerFolder]:
	var found: Array[AssetDrawerFolder] = [self]
	found.append_array(descendants())
	return found
