@tool
class_name AssetDrawerFolder
extends Resource
## A named group of assets in a library, which can hold more folders. Every
## asset lives in exactly one folder of its library.

@export var name: String = "New Folder"
@export var entries: Array[AssetDrawerEntry] = []
@export var folders: Array[AssetDrawerFolder] = []


## Every folder below this one, depth first, parents before children.
func descendants() -> Array[AssetDrawerFolder]:
	var found: Array[AssetDrawerFolder] = []
	for folder: AssetDrawerFolder in folders:
		found.append(folder)
		found.append_array(folder.descendants())
	return found


## Whether [param folder] is this folder or sits anywhere below it.
func contains_folder(folder: AssetDrawerFolder) -> bool:
	return folder == self or descendants().has(folder)


## This folder's assets followed by every subfolder's, depth first.
func all_entries() -> Array[AssetDrawerEntry]:
	var found: Array[AssetDrawerEntry] = entries.duplicate()
	for folder: AssetDrawerFolder in descendants():
		found.append_array(folder.entries)
	return found
