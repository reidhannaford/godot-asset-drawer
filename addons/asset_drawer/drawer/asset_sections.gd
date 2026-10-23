@tool
extends ScrollContainer
## The grids for the selected folder: its own assets first, then a headed
## section for each subfolder that has any, depth first, so a parent folder
## works as an overview. Each grid files drops into the folder it shows, so
## dragging a tile between sections moves it between folders.

const AssetGrid := preload("asset_grid.gd")

signal files_dropped(paths: PackedStringArray, before: AssetDrawerEntry, folder: AssetDrawerFolder)
signal entries_moved(entries: Array[AssetDrawerEntry], before: AssetDrawerEntry, folder: AssetDrawerFolder)
signal delete_pressed
signal escape_pressed
signal tile_clicked(grid: AssetGrid, index: int, at_position: Vector2, mouse_button_index: int)

## Gives a tile its icon from an asset path (empty when it's missing).
var icon_for: Callable

var _column: VBoxContainer
## The selected folder's own grid. It stays the same node across rebuilds;
## subsection grids are made fresh each time.
var _primary: AssetGrid
var _sections: Array[Control] = []
var _grids: Array[AssetGrid] = []
var _thumbnail: int = 64


func _init() -> void:
	name = "AssetDrawerSections"
	horizontal_scroll_mode = SCROLL_MODE_DISABLED
	size_flags_horizontal = SIZE_EXPAND_FILL
	size_flags_vertical = SIZE_EXPAND_FILL
	custom_minimum_size.y = 96.0 * EditorInterface.get_editor_scale()

	_column = VBoxContainer.new()
	_column.size_flags_horizontal = SIZE_EXPAND_FILL
	_column.size_flags_vertical = SIZE_EXPAND_FILL
	add_child(_column)

	_primary = _make_grid()
	# Fills the space below the sections, so there's always somewhere to drop.
	_primary.size_flags_vertical = SIZE_EXPAND_FILL
	_column.add_child(_primary)
	_grids = [_primary]


func primary() -> AssetGrid:
	return _primary


func grids() -> Array[AssetGrid]:
	return _grids.duplicate()


## Shows [param folder]: its assets whose names contain [param needle], then
## each subfolder's. [param empty_text] shows when the folder has nothing to
## show at all.
func show_folder(folder: AssetDrawerFolder, needle: String, accepts_drops: bool, empty_text: String) -> void:
	var selected := selected_entries()
	for section: Control in _sections:
		# The drop that triggered this rebuild may still be running in one of
		# these grids, so take them out now and free them later.
		_column.remove_child(section)
		section.queue_free()
	_sections.clear()
	_grids = [_primary]

	_primary.folder = folder
	_primary.accepts_drops = accepts_drops
	_primary.clear()
	if folder != null:
		_fill(_primary, _matching(folder.entries, needle))
		_add_sections(folder, "", needle, accepts_drops)
	# An empty parent with filled subfolders only needs its sections; it can
	# still be dropped on in the folder tree.
	_primary.visible = _primary.item_count > 0 or _sections.is_empty()
	_primary.empty_text = empty_text
	_column.move_child(_primary, 0)
	select_entries(selected)


func selected_entries() -> Array[AssetDrawerEntry]:
	var selected: Array[AssetDrawerEntry] = []
	for grid: AssetGrid in _grids:
		selected.append_array(grid.selected_entries())
	return selected


func select_entries(entries: Array[AssetDrawerEntry]) -> void:
	for grid: AssetGrid in _grids:
		grid.select_entries(entries)


func highlight(entry: AssetDrawerEntry) -> void:
	for grid: AssetGrid in _grids:
		grid.highlight(entry)


func set_icon(path: String, icon: Texture2D) -> void:
	for grid: AssetGrid in _grids:
		for index: int in grid.item_count:
			if grid.entry_at(index).resolve_path() == path:
				grid.set_item_icon(index, icon)


func set_thumbnail_size(pixels: int) -> void:
	_thumbnail = pixels
	for grid: AssetGrid in _grids:
		grid.set_thumbnail_size(pixels)


func _add_sections(parent: AssetDrawerFolder, prefix: String, needle: String, accepts_drops: bool) -> void:
	for folder: AssetDrawerFolder in parent.folders:
		var path := prefix + folder.name
		var matching := _matching(folder.entries, needle)
		if not matching.is_empty():
			var section := VBoxContainer.new()
			var header := Label.new()
			header.text = path
			header.theme_type_variation = &"HeaderSmall"
			section.add_child(header)
			var grid := _make_grid()
			grid.folder = folder
			grid.accepts_drops = accepts_drops
			section.add_child(grid)
			_fill(grid, matching)
			_column.add_child(section)
			_sections.append(section)
			_grids.append(grid)
		_add_sections(folder, path + " / ", needle, accepts_drops)


func _matching(entries: Array[AssetDrawerEntry], needle: String) -> Array[AssetDrawerEntry]:
	var matching: Array[AssetDrawerEntry] = []
	for entry: AssetDrawerEntry in entries:
		if needle.is_empty() or entry.display_name().containsn(needle):
			matching.append(entry)
	return matching


func _fill(grid: AssetGrid, entries: Array[AssetDrawerEntry]) -> void:
	for entry: AssetDrawerEntry in entries:
		var path := entry.resolve_path()
		var index := grid.add_item(entry.display_name(), icon_for.call(path) as Texture2D)
		grid.set_item_metadata(index, entry)
		if path.is_empty():
			grid.set_item_tooltip(index, "Missing: %s\n%s" % [entry.last_path, entry.uid])
			grid.set_item_custom_fg_color(index, get_theme_color(&"error_color", &"Editor"))
		else:
			grid.set_item_tooltip(index, path)


func _make_grid() -> AssetGrid:
	var grid := AssetGrid.new()
	grid.set_thumbnail_size(_thumbnail)
	grid.files_dropped.connect(func(paths: PackedStringArray, before: AssetDrawerEntry) -> void:
		files_dropped.emit(paths, before, grid.folder))
	grid.entries_moved.connect(func(entries: Array[AssetDrawerEntry], before: AssetDrawerEntry) -> void:
		entries_moved.emit(entries, before, grid.folder))
	grid.delete_pressed.connect(delete_pressed.emit)
	grid.escape_pressed.connect(escape_pressed.emit)
	grid.tile_pressed.connect(func(index: int, at_position: Vector2, mouse_button_index: int) -> void:
		_on_tile_pressed(grid, index, at_position, mouse_button_index))
	return grid


func deselect_all() -> void:
	for grid: AssetGrid in _grids:
		grid.deselect_all()


## A plain click selects in one grid only, like one big grid would.
func _on_tile_pressed(grid: AssetGrid, index: int, at_position: Vector2, mouse_button_index: int) -> void:
	var adding := Input.is_key_pressed(KEY_SHIFT) or Input.is_key_pressed(KEY_META) or Input.is_key_pressed(KEY_CTRL)
	if not adding and mouse_button_index == MOUSE_BUTTON_LEFT:
		for other: AssetGrid in _grids:
			if other != grid:
				other.deselect_all()
	tile_clicked.emit(grid, index, at_position, mouse_button_index)
