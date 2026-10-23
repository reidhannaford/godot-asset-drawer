@tool
extends VBoxContainer
## The drawer's contents: a toolbar for switching, creating and filtering
## libraries over the thumbnail grid. Keeps the open libraries in the
## project's editor metadata so they come back next session.
##
## Clicking a tile arms it for placement; clicking it again, or Esc, lets go.

## A tile was clicked to place the asset at [param path].
signal asset_armed(path: String)
## The armed tile was let go of from the drawer.
signal asset_disarmed

const AssetGrid := preload("asset_grid.gd")

const METADATA_SECTION := "asset_drawer"
const ASSET_TYPE := "PackedScene"
const MIN_THUMBNAIL := 32
const MAX_THUMBNAIL := 192

enum MenuItem { REMOVE, SHOW_IN_FILESYSTEM }

var _libraries: Array[AssetDrawerLibrary] = []
var _active: AssetDrawerLibrary
## The tile being placed, if any.
var _armed: AssetDrawerEntry
## Built-in previews by asset path, filled in as the previewer answers.
var _previews: Dictionary[String, Texture2D] = {}
var _pending_previews: Dictionary[String, bool] = {}

var _toolbar: HFlowContainer
var _switcher: OptionButton
var _new_button: Button
var _open_button: Button
var _close_button: Button
var _filter: LineEdit
var _size_slider: HSlider
var _grid: AssetGrid
var _menu: PopupMenu
var _new_dialog: EditorFileDialog
var _open_dialog: EditorFileDialog


func _init() -> void:
	name = "AssetDrawer"
	size_flags_vertical = SIZE_EXPAND_FILL

	# Wraps onto more rows when the drawer is docked somewhere narrow.
	_toolbar = HFlowContainer.new()
	add_child(_toolbar)

	_switcher = OptionButton.new()
	_switcher.custom_minimum_size.x = 160.0
	_switcher.fit_to_longest_item = false
	_switcher.tooltip_text = "Active library"
	_switcher.item_selected.connect(_on_switcher_selected)
	_toolbar.add_child(_switcher)

	_new_button = _make_tool_button("New library…", _on_new_pressed)
	_toolbar.add_child(_new_button)
	_open_button = _make_tool_button("Open library…", _on_open_pressed)
	_toolbar.add_child(_open_button)
	_close_button = _make_tool_button("Close library", _close_active)
	_toolbar.add_child(_close_button)

	_toolbar.add_child(VSeparator.new())

	_filter = LineEdit.new()
	_filter.placeholder_text = "Filter assets"
	_filter.clear_button_enabled = true
	_filter.size_flags_horizontal = SIZE_EXPAND_FILL
	_filter.text_changed.connect(_on_filter_changed)
	_toolbar.add_child(_filter)

	_size_slider = HSlider.new()
	_size_slider.min_value = MIN_THUMBNAIL
	_size_slider.max_value = MAX_THUMBNAIL
	_size_slider.step = 8
	_size_slider.value = 64
	_size_slider.custom_minimum_size.x = 100.0
	_size_slider.size_flags_vertical = SIZE_SHRINK_CENTER
	_size_slider.tooltip_text = "Thumbnail size"
	_size_slider.value_changed.connect(_on_size_changed)
	_toolbar.add_child(_size_slider)

	_grid = AssetGrid.new()
	_grid.files_dropped.connect(_on_files_dropped)
	_grid.entries_moved.connect(_on_entries_moved)
	_grid.delete_pressed.connect(_remove_selected)
	_grid.escape_pressed.connect(_let_go)
	_grid.item_clicked.connect(_on_item_clicked)
	add_child(_grid)

	_menu = PopupMenu.new()
	_menu.add_item("Remove from Library", MenuItem.REMOVE)
	_menu.add_item("Show in FileSystem", MenuItem.SHOW_IN_FILESYSTEM)
	_menu.id_pressed.connect(_on_menu_id_pressed)
	add_child(_menu)

	_new_dialog = _make_dialog(EditorFileDialog.FILE_MODE_SAVE_FILE, "New Asset Library")
	_new_dialog.file_selected.connect(_create_library)
	_open_dialog = _make_dialog(EditorFileDialog.FILE_MODE_OPEN_FILES, "Open Asset Libraries")
	_open_dialog.files_selected.connect(_on_open_files_selected)


func _ready() -> void:
	EditorInterface.get_resource_filesystem().filesystem_changed.connect(_refresh)
	EditorInterface.get_resource_previewer().preview_invalidated.connect(_on_preview_invalidated)
	_restore()


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		_new_button.icon = get_theme_icon(&"New", &"EditorIcons")
		_open_button.icon = get_theme_icon(&"Load", &"EditorIcons")
		_close_button.icon = get_theme_icon(&"Close", &"EditorIcons")
		_filter.right_icon = get_theme_icon(&"Search", &"EditorIcons")
		_menu.set_item_icon(_menu.get_item_index(MenuItem.REMOVE), get_theme_icon(&"Remove", &"EditorIcons"))
		_menu.set_item_icon(_menu.get_item_index(MenuItem.SHOW_IN_FILESYSTEM),
				get_theme_icon(&"ShowInFileSystem", &"EditorIcons"))
		if is_node_ready():
			_rebuild_grid()


## Opens [param library] (or switches to it if it's already open) and makes
## it the active one.
func open_library(library: AssetDrawerLibrary) -> void:
	if not _libraries.has(library):
		_libraries.append(library)
	_active = library
	_remember()
	_refresh()


func active_library() -> AssetDrawerLibrary:
	return _active


## Adds [param control] to the end of the toolbar, after a separator.
func add_toolbar_control(control: Control) -> void:
	_toolbar.add_child(VSeparator.new())
	_toolbar.add_child(control)


func armed_entry() -> AssetDrawerEntry:
	return _armed


## Clears the armed tile without emitting [signal asset_disarmed], for when
## placement ended somewhere else.
func disarm() -> void:
	_armed = null
	_grid.highlight(null)


func _arm(entry: AssetDrawerEntry) -> void:
	_armed = entry
	_grid.highlight(entry)
	asset_armed.emit(entry.resolve_path())


## Clears the armed tile and tells the plugin to stop placing.
func _let_go() -> void:
	if _armed != null:
		disarm()
		asset_disarmed.emit()


func open_libraries() -> Array[AssetDrawerLibrary]:
	return _libraries.duplicate()


func _make_tool_button(tooltip: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.flat = true
	button.tooltip_text = tooltip
	button.pressed.connect(on_pressed)
	return button


func _make_dialog(mode: EditorFileDialog.FileMode, title: String) -> EditorFileDialog:
	var dialog := EditorFileDialog.new()
	dialog.file_mode = mode
	dialog.access = EditorFileDialog.ACCESS_RESOURCES
	dialog.title = title
	dialog.add_filter("*.tres", "Asset Library")
	add_child(dialog)
	return dialog


# Libraries


func _create_library(path: String) -> void:
	var library := AssetDrawerLibrary.new()
	# Saving over a library that's already open replaces it; take_over_path
	# leaves the old one with an empty path.
	library.take_over_path(path)
	var error := ResourceSaver.save(library)
	if error != OK:
		push_error("Asset Drawer: couldn't save %s (%s)." % [path, error_string(error)])
		return
	EditorInterface.get_resource_filesystem().update_file(path)
	for open: AssetDrawerLibrary in _libraries.duplicate():
		if open.resource_path.is_empty():
			_libraries.erase(open)
	open_library(library)


func _on_open_files_selected(paths: PackedStringArray) -> void:
	for path: String in paths:
		var library := _load_library(path)
		if library != null:
			open_library(library)


func _load_library(path: String) -> AssetDrawerLibrary:
	var library := ResourceLoader.load(path) as AssetDrawerLibrary
	if library == null:
		push_warning("Asset Drawer: %s isn't an asset library." % path)
	return library


func _close_active() -> void:
	if _active == null:
		return
	var index := _libraries.find(_active)
	_libraries.remove_at(index)
	_active = _libraries[mini(index, _libraries.size() - 1)] if not _libraries.is_empty() else null
	_remember()
	_refresh()


func _save_active() -> void:
	var error := ResourceSaver.save(_active)
	if error != OK:
		push_error("Asset Drawer: couldn't save %s (%s)." % [_active.resource_path, error_string(error)])


# Remembering open libraries


func _remember() -> void:
	var settings := EditorInterface.get_editor_settings()
	var open := PackedStringArray()
	for library: AssetDrawerLibrary in _libraries:
		open.append(ResourceUID.path_to_uid(library.resource_path))
	settings.set_project_metadata(METADATA_SECTION, "open_libraries", open)
	settings.set_project_metadata(METADATA_SECTION, "active_library",
			ResourceUID.path_to_uid(_active.resource_path) if _active != null else "")


func _restore() -> void:
	var settings := EditorInterface.get_editor_settings()
	_size_slider.set_value_no_signal(
			settings.get_project_metadata(METADATA_SECTION, "thumbnail_size", 64) as int)
	_grid.set_thumbnail_size(int(_size_slider.value))

	var open := settings.get_project_metadata(METADATA_SECTION, "open_libraries",
			PackedStringArray()) as PackedStringArray
	var active_path := ResourceUID.ensure_path(
			settings.get_project_metadata(METADATA_SECTION, "active_library", "") as String)
	for saved: String in open:
		var path := ResourceUID.ensure_path(saved)
		if not ResourceLoader.exists(path):
			push_warning("Asset Drawer: couldn't reopen the library at %s; it was moved or deleted." % saved)
			continue
		var library := _load_library(path)
		if library == null:
			continue
		_libraries.append(library)
		if path == active_path:
			_active = library
	if _active == null and not _libraries.is_empty():
		_active = _libraries[0]
	_refresh()


# Toolbar


func _on_switcher_selected(index: int) -> void:
	_active = _libraries[index]
	_remember()
	_refresh()


func _on_new_pressed() -> void:
	_new_dialog.popup_file_dialog()


func _on_open_pressed() -> void:
	_open_dialog.popup_file_dialog()


func _on_filter_changed(_text: String) -> void:
	_rebuild_grid()


func _on_size_changed(value: float) -> void:
	_grid.set_thumbnail_size(int(value))
	EditorInterface.get_editor_settings().set_project_metadata(
			METADATA_SECTION, "thumbnail_size", int(value))


# Grid


## Rebuilds the switcher and grid from the open libraries, saving the active
## one first if any of its assets moved.
func _refresh() -> void:
	_switcher.clear()
	for library: AssetDrawerLibrary in _libraries:
		_switcher.add_item(library.display_name())
	_switcher.disabled = _libraries.is_empty()
	if _libraries.is_empty():
		_switcher.add_item("No library")
	else:
		_switcher.select(_libraries.find(_active))
	_close_button.disabled = _active == null
	_filter.editable = _active != null

	if _active != null and _active.refresh_paths():
		_save_active()
	_rebuild_grid()


func _rebuild_grid() -> void:
	var selected := _grid.selected_entries()
	_grid.clear()
	_grid.accepts_drops = _active != null
	if _active == null:
		_let_go()
		_grid.empty_text = "Create or open a library to start."
		return

	var needle := _filter.text.strip_edges()
	for entry: AssetDrawerEntry in _active.entries:
		var label := entry.display_name()
		if not needle.is_empty() and not label.containsn(needle):
			continue
		var path := entry.resolve_path()
		var index := _grid.add_item(label, _icon_for(path))
		_grid.set_item_metadata(index, entry)
		if path.is_empty():
			_grid.set_item_tooltip(index, "Missing: %s\n%s" % [entry.last_path, entry.uid])
			_grid.set_item_custom_fg_color(index, get_theme_color(&"error_color", &"Editor"))
		else:
			_grid.set_item_tooltip(index, path)
	_grid.select_entries(selected)
	if not _active.entries.has(_armed):
		_let_go()
	_grid.highlight(_armed)

	if not _active.entries.is_empty():
		_grid.empty_text = "No assets match the filter."
	else:
		_grid.empty_text = "Drag scenes or models here from the FileSystem dock."


func _icon_for(path: String) -> Texture2D:
	if path.is_empty():
		return get_theme_icon(&"FileBroken", &"EditorIcons")
	if _previews.has(path):
		return _previews[path]
	if not _pending_previews.has(path):
		_pending_previews[path] = true
		EditorInterface.get_resource_previewer().queue_resource_preview(path, self, &"_on_file_preview", null)
	return get_theme_icon(&"PackedScene", &"EditorIcons")


func _on_file_preview(path: String, preview: Texture2D, _thumbnail: Texture2D, _userdata: Variant) -> void:
	if preview != null:
		_show_preview(path, preview)
		return
	# The previewer only has thumbnails of scenes saved in the editor, and
	# none of imported models; fall back to previewing the scene's mesh.
	var mesh := _largest_mesh(path)
	if mesh == null:
		_pending_previews.erase(path)
		return
	EditorInterface.get_resource_previewer().queue_edited_resource_preview(mesh, self, &"_on_mesh_preview", path)


func _on_mesh_preview(_id: String, preview: Texture2D, _thumbnail: Texture2D, path: Variant) -> void:
	if preview != null:
		_show_preview(path as String, preview)
	else:
		_pending_previews.erase(path as String)


## The biggest mesh the scene at [param path] uses directly, or null. Meshes
## inside instanced sub-scenes aren't searched.
func _largest_mesh(path: String) -> Mesh:
	var scene := ResourceLoader.load(path) as PackedScene
	if scene == null:
		return null
	var state := scene.get_state()
	var largest: Mesh = null
	var largest_extent := -1.0
	for node: int in state.get_node_count():
		for property: int in state.get_node_property_count(node):
			var value: Variant = state.get_node_property_value(node, property)
			if value is Mesh:
				var extent := (value as Mesh).get_aabb().size.length()
				if extent > largest_extent:
					largest = value as Mesh
					largest_extent = extent
	return largest


func _show_preview(path: String, preview: Texture2D) -> void:
	_pending_previews.erase(path)
	_previews[path] = preview
	for index: int in _grid.item_count:
		if _grid.entry_at(index).resolve_path() == path:
			_grid.set_item_icon(index, preview)


func _on_preview_invalidated(path: String) -> void:
	if _previews.erase(path):
		_rebuild_grid()


func _on_files_dropped(paths: PackedStringArray, before: AssetDrawerEntry) -> void:
	var added: Array[AssetDrawerEntry] = []
	for path: String in _collect_assets(paths):
		var entry := _active.find_uid(ResourceUID.path_to_uid(path))
		if entry == null:
			entry = AssetDrawerEntry.from_path(path)
		if not added.has(entry):
			added.append(entry)
	if added.is_empty():
		return
	_active.insert(added, before)
	_save_active()
	_rebuild_grid()
	_grid.select_entries(added)


## Scene and model files among [param paths], with folders expanded into the
## scenes inside them. Loose files of other types are rejected with a warning.
func _collect_assets(paths: PackedStringArray) -> PackedStringArray:
	var filesystem := EditorInterface.get_resource_filesystem()
	var found := PackedStringArray()
	for path: String in paths:
		if DirAccess.dir_exists_absolute(path):
			found.append_array(_assets_in_folder(path))
		elif filesystem.get_file_type(path) == ASSET_TYPE:
			found.append(path)
		else:
			push_warning("Asset Drawer: %s isn't a scene or model, so it can't go in a library." % path)
	return found


func _assets_in_folder(folder: String) -> PackedStringArray:
	var filesystem := EditorInterface.get_resource_filesystem()
	var found := PackedStringArray()
	var base := folder.trim_suffix("/") + "/"
	for file: String in DirAccess.get_files_at(base):
		if filesystem.get_file_type(base + file) == ASSET_TYPE:
			found.append(base + file)
	for child: String in DirAccess.get_directories_at(base):
		found.append_array(_assets_in_folder(base + child))
	return found


func _on_entries_moved(entries: Array[AssetDrawerEntry], before: AssetDrawerEntry) -> void:
	_active.insert(entries, before)
	_save_active()
	_rebuild_grid()
	_grid.select_entries(entries)


func _remove_selected() -> void:
	var selected := _grid.selected_entries()
	if selected.is_empty():
		return
	_active.remove(selected)
	_save_active()
	_rebuild_grid()


func _on_item_clicked(index: int, at_position: Vector2, mouse_button_index: int) -> void:
	if mouse_button_index == MOUSE_BUTTON_LEFT:
		_on_tile_left_clicked(index)
		return
	if mouse_button_index != MOUSE_BUTTON_RIGHT:
		return
	var selected := _grid.get_selected_items()
	var single_path := _grid.entry_at(index).resolve_path() if selected.size() == 1 else ""
	_menu.set_item_disabled(_menu.get_item_index(MenuItem.SHOW_IN_FILESYSTEM), single_path.is_empty())
	_menu.position = Vector2i(_grid.get_screen_position() + at_position)
	_menu.reset_size()
	_menu.popup()


## A plain click arms the tile, or lets go if it's already armed. Clicks
## with Shift or Cmd/Ctrl only change the selection.
func _on_tile_left_clicked(index: int) -> void:
	if Input.is_key_pressed(KEY_SHIFT) or Input.is_key_pressed(KEY_META) or Input.is_key_pressed(KEY_CTRL):
		return
	var entry := _grid.entry_at(index)
	if entry == _armed:
		_let_go()
	elif not entry.resolve_path().is_empty():
		_arm(entry)


func _on_menu_id_pressed(id: int) -> void:
	match id:
		MenuItem.REMOVE:
			_remove_selected()
		MenuItem.SHOW_IN_FILESYSTEM:
			var selected := _grid.selected_entries()
			if selected.size() == 1:
				EditorInterface.get_file_system_dock().navigate_to_path(selected[0].resolve_path())
