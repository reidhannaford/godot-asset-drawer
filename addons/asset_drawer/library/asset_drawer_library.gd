@tool
class_name AssetDrawerLibrary
extends Resource
## A curated, ordered set of assets for the drawer. Saved as a .tres anywhere
## in the project; its file name is its display name.

@export var entries: Array[AssetDrawerEntry] = []


func display_name() -> String:
	return resource_path.get_file().get_basename()


## The entry for [param uid], or null when it isn't in this library.
func find_uid(uid: String) -> AssetDrawerEntry:
	for entry: AssetDrawerEntry in entries:
		if entry.uid == uid:
			return entry
	return null


## Puts [param added] in order just before [param before], or at the end when
## [param before] is null. Entries already in the library are moved.
func insert(added: Array[AssetDrawerEntry], before: AssetDrawerEntry) -> void:
	# Dropping a group onto one of its own members anchors on the next
	# entry that isn't moving.
	var anchor: AssetDrawerEntry = null
	var start := entries.find(before) if before != null else -1
	if start != -1:
		for i: int in range(start, entries.size()):
			if not added.has(entries[i]):
				anchor = entries[i]
				break
	for entry: AssetDrawerEntry in added:
		entries.erase(entry)
	var at := entries.find(anchor) if anchor != null else entries.size()
	for i: int in added.size():
		entries.insert(at + i, added[i])
	emit_changed()


func remove(removed: Array[AssetDrawerEntry]) -> void:
	for entry: AssetDrawerEntry in removed:
		entries.erase(entry)
	emit_changed()


## Records where each moved asset now lives, and swaps a stored path for a
## uid once the file has one. Returns whether anything changed, so the caller
## knows to save.
func refresh_paths() -> bool:
	var changed := false
	for entry: AssetDrawerEntry in entries:
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
