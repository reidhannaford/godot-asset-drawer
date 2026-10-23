@tool
extends Tree
## The library's folders, with the library itself as the root item. Each
## item's metadata is its AssetDrawerFolder. Folders can be dragged to
## reorder or nest them, and tiles or FileSystem files dropped on a folder
## file them there; the panel decides what each request means.

signal folder_selected(folder: AssetDrawerFolder)
signal new_folder_requested(parent: AssetDrawerFolder)
signal rename_requested(folder: AssetDrawerFolder, new_name: String)
signal delete_requested(folder: AssetDrawerFolder)
## A folder was dragged to just before [param before] in [param into], or to
## its end when [param before] is null.
signal folder_moved(folder: AssetDrawerFolder, into: AssetDrawerFolder, before: AssetDrawerFolder)
signal entries_dropped(entries: Array[AssetDrawerEntry], into: AssetDrawerFolder)
signal files_dropped(paths: PackedStringArray, into: AssetDrawerFolder)

const ENTRIES_KEY := "asset_drawer_entries"
const FOLDER_DRAG := "asset_drawer_folder"

enum MenuItem { NEW_FOLDER, RENAME, DELETE }

var _library: AssetDrawerLibrary
var _collapsed: Dictionary[AssetDrawerFolder, bool] = {}
var _menu: PopupMenu
var _menu_folder: AssetDrawerFolder
var _rebuilding: bool = false


func _init() -> void:
	name = "AssetDrawerFolders"
	custom_minimum_size.x = 160.0 * EditorInterface.get_editor_scale()
	allow_rmb_select = true
	item_selected.connect(_on_item_selected)
	item_mouse_selected.connect(_on_item_mouse_selected)
	item_edited.connect(_on_item_edited)
	item_collapsed.connect(_on_item_collapsed)

	_menu = PopupMenu.new()
	_menu.add_item("New Folder", MenuItem.NEW_FOLDER)
	_menu.add_item("Rename", MenuItem.RENAME)
	_menu.add_item("Delete Folder (keeps its assets)", MenuItem.DELETE)
	_menu.id_pressed.connect(_on_menu_id_pressed)
	add_child(_menu)


## Shows [param library]'s folders and selects [param selected], keeping
## collapsed folders collapsed.
func show_library(library: AssetDrawerLibrary, selected: AssetDrawerFolder) -> void:
	_rebuilding = true
	_library = library
	clear()
	if library != null:
		_add_item(library, null, library.display_name(), selected)
	_rebuilding = false


## The item showing [param folder], or null.
func item_for(folder: AssetDrawerFolder) -> TreeItem:
	var item := get_root()
	while item != null:
		if item.get_metadata(0) == folder:
			return item
		item = item.get_next_in_tree()
	return null


## Starts renaming [param folder] in place.
func begin_rename(folder: AssetDrawerFolder) -> void:
	var item := item_for(folder)
	if item == null or folder == _library:
		return
	item.select(0)
	scroll_to_item(item)
	edit_selected(true)


## Applies a drop on [param item]: [param section] is -1 above it, 0 on it,
## 1 below it, as [method get_drop_section_at_position] reports. Returns
## whether the drop did anything.
func drop_on(item: TreeItem, section: int, data: Variant) -> bool:
	if item == null or not data is Dictionary:
		return false
	var drop := data as Dictionary
	var target := item.get_metadata(0) as AssetDrawerFolder
	if drop.get("type") == FOLDER_DRAG:
		var folder := drop["folder"] as AssetDrawerFolder
		if section == 0 or target == _library:
			folder_moved.emit(folder, target, null)
		else:
			var parent := _library.parent_of(target)
			var index := parent.folders.find(target) + (1 if section > 0 else 0)
			var before: AssetDrawerFolder = parent.folders[index] if index < parent.folders.size() else null
			folder_moved.emit(folder, parent, before)
		return true
	if drop.has(ENTRIES_KEY):
		var moved: Array[AssetDrawerEntry] = []
		moved.assign(drop[ENTRIES_KEY])
		entries_dropped.emit(moved, target)
		return true
	if drop.get("type") in ["files", "files_and_dirs"]:
		files_dropped.emit(drop["files"] as PackedStringArray, target)
		return true
	return false


func _add_item(folder: AssetDrawerFolder, parent: TreeItem, text: String, selected: AssetDrawerFolder) -> void:
	var item := create_item(parent)
	item.set_text(0, text)
	item.set_metadata(0, folder)
	item.set_icon(0, get_theme_icon(&"Folder" if parent != null else &"Object", &"EditorIcons"))
	item.collapsed = _collapsed.get(folder, false) as bool
	if folder == selected:
		item.select(0)
	for child: AssetDrawerFolder in folder.folders:
		_add_item(child, item, child.name, selected)


func _get_drag_data(at_position: Vector2) -> Variant:
	var item := get_item_at_position(at_position)
	if item == null or item.get_metadata(0) == _library:
		return null
	var preview := Label.new()
	preview.text = item.get_text(0)
	set_drag_preview(preview)
	return {"type": FOLDER_DRAG, "folder": item.get_metadata(0)}


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if _library == null or not data is Dictionary:
		return false
	var drop := data as Dictionary
	var item := get_item_at_position(at_position)
	if drop.get("type") == FOLDER_DRAG:
		drop_mode_flags = DROP_MODE_ON_ITEM | DROP_MODE_INBETWEEN
		var folder := drop["folder"] as AssetDrawerFolder
		return item != null and not folder.contains_folder(item.get_metadata(0) as AssetDrawerFolder)
	drop_mode_flags = DROP_MODE_ON_ITEM
	return item != null and (drop.has(ENTRIES_KEY) or drop.get("type") in ["files", "files_and_dirs"])


func _drop_data(at_position: Vector2, data: Variant) -> void:
	drop_on(get_item_at_position(at_position), get_drop_section_at_position(at_position), data)


func _on_item_selected() -> void:
	if not _rebuilding:
		folder_selected.emit(get_selected().get_metadata(0) as AssetDrawerFolder)


func _on_item_mouse_selected(mouse_position: Vector2, mouse_button_index: int) -> void:
	if mouse_button_index != MOUSE_BUTTON_RIGHT:
		return
	_menu_folder = get_selected().get_metadata(0) as AssetDrawerFolder
	var is_root := _menu_folder == _library
	_menu.set_item_disabled(_menu.get_item_index(MenuItem.RENAME), is_root)
	_menu.set_item_disabled(_menu.get_item_index(MenuItem.DELETE), is_root)
	_menu.position = Vector2i(get_screen_position() + mouse_position)
	_menu.reset_size()
	_menu.popup()


func _on_menu_id_pressed(id: int) -> void:
	match id:
		MenuItem.NEW_FOLDER:
			new_folder_requested.emit(_menu_folder)
		MenuItem.RENAME:
			begin_rename(_menu_folder)
		MenuItem.DELETE:
			delete_requested.emit(_menu_folder)


func _on_item_edited() -> void:
	var item := get_edited()
	var new_name := item.get_text(0).strip_edges()
	var folder := item.get_metadata(0) as AssetDrawerFolder
	if new_name.is_empty():
		item.set_text(0, folder.name)
	elif new_name != folder.name:
		rename_requested.emit(folder, new_name)


func _on_item_collapsed(item: TreeItem) -> void:
	if not _rebuilding:
		_collapsed[item.get_metadata(0) as AssetDrawerFolder] = item.collapsed


func _gui_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or get_selected() == null:
		return
	var folder := get_selected().get_metadata(0) as AssetDrawerFolder
	if key.keycode == KEY_F2 or (key.keycode == KEY_ENTER and OS.get_name() == "macOS"):
		begin_rename(folder)
		accept_event()
	elif key.keycode == KEY_DELETE and folder != _library:
		delete_requested.emit(folder)
		accept_event()
