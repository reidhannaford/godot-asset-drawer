extends SceneTree
## Drives the drawer panel headlessly. RUN=1 builds two libraries; RUN=2
## (same HOME) checks they come back, then tests a moved asset.

const LIB_A := "res://test_tmp_props.tres"
const LIB_B := "res://test_tmp_other.tres"
## LIB_B after _folder_checks: folder[assets]{subfolders}.
const EXPECTED_FOLDERS := "root[barrel,crate,pillar]{Items[rock]{},Pick-ups[]{}}"

var _frame := 0
var _failures := 0
var _panel: Variant
var _grid: Variant


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 120:
		_panel = root.find_children("AssetDrawer", "VBoxContainer", true, false)[0]
		_grid = _panel.get("_grid")
		var dock: Variant = _panel.get_parent()
		dock.call("make_visible")
		_grid.custom_minimum_size = Vector2(600, 300)
		if OS.get_environment("RUN") == "2":
			_run_two.call_deferred()
		else:
			_run_one.call_deferred()
	if _frame == 3000:
		print("WATCHDOG")
		quit(1)
	return false


func _check(label: String, ok: bool, detail: Variant = "") -> void:
	print(("PASS " if ok else "FAIL ") + label + ("" if ok else "  -> " + str(detail)))
	if not ok:
		_failures += 1


func _names() -> PackedStringArray:
	var out := PackedStringArray()
	for i: int in _grid.item_count:
		out.append(_grid.get_item_text(i))
	return out


func _lib_names(library: Variant) -> PackedStringArray:
	var out := PackedStringArray()
	for entry: Variant in library.get("entries"):
		out.append(entry.call("display_name"))
	return out


func _run_one() -> void:
	await process_frame
	await process_frame
	print("GRID SIZE ", _grid.size)
	_check("starts empty", _grid.item_count == 0 and _panel.call("active_library") == null)

	_panel.call("_create_library", LIB_A)
	var lib: Variant = _panel.call("active_library")
	_check("library created", lib != null and lib.resource_path == LIB_A)
	_check("library has uid", ResourceUID.path_to_uid(LIB_A).begins_with("uid://"), ResourceUID.path_to_uid(LIB_A))

	var folder_drop := {"type": "files_and_dirs", "files": PackedStringArray(["res://test/props/"])}
	_check("accepts folder drop", _grid.call("_can_drop_data", Vector2(10, 10), folder_drop))
	_grid.call("force_update_list_size")
	_grid.call("_drop_data", Vector2(10, 10), folder_drop)
	_check("folder expands to 4 assets", _names() == PackedStringArray(["barrel", "crate", "pillar", "rock"]), _names())

	var bad_drop := {"type": "files", "files": PackedStringArray(["res://project.godot", "res://test/props/crate.tscn"])}
	_grid.call("force_update_list_size")
	_grid.call("_drop_data", Vector2(10, 10), bad_drop)
	_check("rejects non-scene, moves existing crate to front", _names() == PackedStringArray(["crate", "barrel", "pillar", "rock"]), _names())

	# Reorder: rock before crate, then the first two to the end.
	var entries: Array = lib.get("entries")
	_panel.call("_on_entries_moved", [entries[3]] as Array[AssetDrawerEntry], entries[0])
	_check("rock moved first", _names() == PackedStringArray(["rock", "crate", "barrel", "pillar"]), _names())
	entries = lib.get("entries")
	_panel.call("_on_entries_moved", [entries[0], entries[1]] as Array[AssetDrawerEntry], null)
	_check("first two moved to end", _names() == PackedStringArray(["barrel", "pillar", "rock", "crate"]), _names())
	entries = lib.get("entries")
	_panel.call("_on_entries_moved", [entries[0], entries[1]] as Array[AssetDrawerEntry], entries[1])
	_check("drop onto own member is a no-op", _names() == PackedStringArray(["barrel", "pillar", "rock", "crate"]), _names())

	# Grid drag data: reorder key plus FileSystem-shaped files.
	_grid.call("deselect_all")
	_grid.call("select", 0)
	_grid.call("force_update_list_size")
	var rect: Rect2 = _grid.call("_visible_item_rect", 0)
	var drag: Variant = _grid.call("_get_drag_data", rect.get_center())
	_check("drag data looks like a FileSystem drag", drag is Dictionary and drag["type"] == "files"
			and drag["files"] == PackedStringArray(["res://test/props/barrel.glb"]) and drag.has("asset_drawer_entries"), drag)
	var last_rect: Rect2 = _grid.call("_visible_item_rect", 3)
	_check("insertion index past last item", _grid.call("_insertion_index", last_rect.end + Vector2(1, -2)) == 4,
			_grid.call("_insertion_index", last_rect.end + Vector2(1, -2)))
	_grid.call("force_update_list_size")
	_grid.call("_drop_data", last_rect.end + Vector2(1, -2), drag)
	_check("grid drag-drop moves barrel to end", _names() == PackedStringArray(["pillar", "rock", "crate", "barrel"]), _names())

	# Filter.
	var filter: LineEdit = _panel.get("_filter")
	filter.text = "AR"
	_panel.call("_on_filter_changed", filter.text)
	_check("filter is case-insensitive", _names() == PackedStringArray(["pillar", "barrel"]), _names())
	_grid.call("select", 0)
	_panel.call("_remove_selected")
	_check("remove while filtered", _names() == PackedStringArray(["barrel"]), _names())
	var history := EditorInterface.get_editor_undo_redo().get_history_undo_redo(EditorUndoRedoManager.GLOBAL_HISTORY)
	_check("removal is in the global undo history", history.has_undo() and history.get_current_action_name().begins_with("Remove pillar"),
			history.get_current_action_name())
	history.undo()
	_check("undo puts the asset back where it was", _lib_names(lib) == PackedStringArray(["pillar", "rock", "crate", "barrel"])
			and _names() == PackedStringArray(["pillar", "barrel"]), [_lib_names(lib), _names()])
	history.redo()
	_check("redo removes it again", _names() == PackedStringArray(["barrel"]), _names())
	filter.text = ""
	_panel.call("_on_filter_changed", "")
	_check("filter cleared", _names() == PackedStringArray(["rock", "crate", "barrel"]), _names())

	# The tile menu decides its state after ItemList has updated the selection.
	var menu: PopupMenu = _panel.get("_menu")
	var show_item: int = menu.get_item_index(1)
	_grid.call("deselect_all")
	_grid.call("force_update_list_size")
	var rmb := InputEventMouseButton.new()
	rmb.button_index = MOUSE_BUTTON_RIGHT
	rmb.pressed = true
	rmb.position = (_grid.call("_visible_item_rect", 1) as Rect2).get_center()
	_grid.call("_gui_input", rmb)
	_grid.call("select", 1)  # What ItemList does with this press, after _gui_input.
	await process_frame
	_check("right-click on an unselected tile enables Show in FileSystem", menu.visible and not menu.is_item_disabled(show_item),
			[menu.visible, menu.is_item_disabled(show_item)])
	menu.hide()
	_grid.call("select", 0, false)
	_grid.call("_gui_input", rmb)
	await process_frame
	_check("right-click with two selected disables Show in FileSystem", menu.is_item_disabled(show_item))
	menu.hide()
	_grid.call("deselect_all")

	var on_disk: Variant = ResourceLoader.load(LIB_A, "", ResourceLoader.CACHE_MODE_IGNORE)
	_check("saved to disk", _lib_names(on_disk) == PackedStringArray(["rock", "crate", "barrel"]), _lib_names(on_disk))

	# A scene with no uid is stored by path.
	var file := FileAccess.open("res://test_tmp_nouid.tscn", FileAccess.WRITE)
	file.store_string("[gd_scene format=3]\n\n[node name=\"NoUid\" type=\"Node3D\"]\n")
	file.close()
	var fs := EditorInterface.get_resource_filesystem()
	fs.update_file("res://test_tmp_nouid.tscn")
	while fs.get_file_type("res://test_tmp_nouid.tscn") != "PackedScene":
		await process_frame
	_grid.call("force_update_list_size")
	_grid.call("_drop_data", Vector2(10, 10), {"type": "files", "files": PackedStringArray(["res://test_tmp_nouid.tscn"])})
	var nouid: Variant = lib.get("entries")[0]
	_check("no-uid scene stored by path", nouid.get("uid") == "res://test_tmp_nouid.tscn" and _names()[0] == "test_tmp_nouid", [nouid.get("uid"), _names()])
	_grid.call("deselect_all")
	_grid.call("select", 0)
	_panel.call("_remove_selected")
	DirAccess.remove_absolute("res://test_tmp_nouid.tscn")
	fs.scan()
	await fs.filesystem_changed

	_panel.call("_create_library", LIB_B)
	_check("second library active", (_panel.call("active_library") as Resource).resource_path == LIB_B and _grid.item_count == 0)
	var switcher: OptionButton = _panel.get("_switcher")
	_check("switcher lists both", switcher.item_count == 2 and switcher.get_item_text(0) == "test_tmp_props", switcher.item_count)
	await _folder_checks()
	_panel.call("_on_switcher_selected", 0)
	_check("switched back", (_panel.call("active_library") as Resource).resource_path == LIB_A and _grid.item_count == 3)

	(_panel.get("_size_slider") as HSlider).value = 96
	_check("thumbnail size applied", _grid.fixed_icon_size == Vector2i(96, 96))

	var bar: Variant = root.find_children("AssetDrawerPlacementBar", "", true, false)[0]
	var hit_mode: OptionButton = bar.get("_hit_mode")
	hit_mode.select(1)
	hit_mode.item_selected.emit(1)
	(bar.get("_align") as Button).button_pressed = true
	(bar.get("_snap") as Button).button_pressed = true
	(bar.get("_snap_step") as Range).value = 0.25
	(bar.get("_random_scale_max") as Range).value = 1.5
	var placer_settings: Variant = root.find_children("AssetDrawerPlacer", "", true, false)[0].get("settings")
	_check("placement bar sets the settings", placer_settings.get("hit_mode") == 1 and placer_settings.get("align_to_normal") == true
			and placer_settings.get("snap_enabled") == true and is_equal_approx(placer_settings.get("snap_step"), 0.25)
			and is_equal_approx(placer_settings.get("random_scale_max"), 1.5))

	var settings := EditorInterface.get_editor_settings()
	print("META ", settings.get_project_metadata("asset_drawer", "open_libraries", null), " ",
			settings.get_project_metadata("asset_drawer", "active_library", null))
	_finish()


func _run_two() -> void:
	var libs: Array = _panel.call("open_libraries")
	_check("two libraries restored", libs.size() == 2, libs.size())
	var active: Variant = _panel.call("active_library")
	_check("active restored", active != null and active.resource_path == LIB_A)
	_check("order restored", _names() == PackedStringArray(["rock", "crate", "barrel"]), _names())
	var placer_settings: Variant = root.find_children("AssetDrawerPlacer", "", true, false)[0].get("settings")
	_check("placement settings restored", placer_settings.get("hit_mode") == 1 and placer_settings.get("align_to_normal") == true,
			[placer_settings.get("hit_mode"), placer_settings.get("align_to_normal")])
	var bar: Variant = root.find_children("AssetDrawerPlacementBar", "", true, false)[0]
	_check("snap and random settings restored", placer_settings.get("snap_enabled") == true
			and is_equal_approx(placer_settings.get("snap_step"), 0.25) and is_equal_approx(placer_settings.get("random_scale_max"), 1.5),
			[placer_settings.get("snap_enabled"), placer_settings.get("snap_step"), placer_settings.get("random_scale_max")])
	_check("placement bar shows them", (bar.get("_hit_mode") as OptionButton).selected == 1 and (bar.get("_align") as Button).button_pressed
			and (bar.get("_snap") as Button).button_pressed and is_equal_approx((bar.get("_snap_step") as Range).value, 0.25))
	_check("thumbnail size restored", _grid.fixed_icon_size == Vector2i(96, 96), _grid.fixed_icon_size)

	var other: Variant = null
	for library: Variant in libs:
		if library.resource_path == LIB_B:
			other = library
	_check("folders restored", other != null and _describe(other) == EXPECTED_FOLDERS, _describe(other) if other else null)

	# Move rock.tscn on disk and rescan: the uid should follow it.
	DirAccess.rename_absolute("res://test/props/rock.tscn", "res://test/props/boulder.tscn")
	var fs := EditorInterface.get_resource_filesystem()
	fs.scan()
	await fs.filesystem_changed
	await process_frame
	_check("moved asset follows its uid", _names() == PackedStringArray(["boulder", "crate", "barrel"]), _names())
	var on_disk: Variant = ResourceLoader.load(LIB_A, "", ResourceLoader.CACHE_MODE_IGNORE)
	_check("last_path saved", on_disk.get("entries")[0].get("last_path") == "res://test/props/boulder.tscn",
			on_disk.get("entries")[0].get("last_path"))

	# Delete it: the tile should stay, marked missing.
	DirAccess.rename_absolute("res://test/props/boulder.tscn", "res://test_tmp_hidden.txt")
	fs.scan()
	await fs.filesystem_changed
	await process_frame
	_check("missing asset keeps its tile", _names() == PackedStringArray(["boulder", "crate", "barrel"]), _names())
	_check("missing tile tooltip", (_grid.get_item_tooltip(0) as String).begins_with("Missing:"), _grid.get_item_tooltip(0))
	DirAccess.rename_absolute("res://test_tmp_hidden.txt", "res://test/props/rock.tscn")
	fs.scan()
	await fs.filesystem_changed
	_finish()


func _finish() -> void:
	print("FAILURES ", _failures)
	quit(_failures)


func _typed(items: Array) -> Array[AssetDrawerEntry]:
	var out: Array[AssetDrawerEntry] = []
	out.assign(items)
	return out


## A library as folder[assets]{subfolders}, recursively.
func _describe(folder: Variant, label: String = "root") -> String:
	var names := PackedStringArray()
	for entry: Variant in folder.get("entries"):
		names.append(entry.call("display_name"))
	var children := PackedStringArray()
	for child: Variant in folder.get("folders"):
		children.append(_describe(child, child.get("name")))
	return "%s[%s]{%s}" % [label, ",".join(names), ",".join(children)]


func _headers() -> PackedStringArray:
	var sections: Variant = _panel.get("_sections")
	var out := PackedStringArray()
	for section: Control in sections.get("_sections"):
		out.append((section.get_child(0) as Label).text)
	return out


## Folders in LIB_B, which is active and empty when this runs.
func _folder_checks() -> void:
	var lib: Variant = _panel.call("active_library")
	var tree: Variant = _panel.get("_tree")
	var sections: Variant = _panel.get("_sections")
	var fs := EditorInterface.get_resource_filesystem()
	var scanning := fs.is_scanning()
	_grid.call("_drop_data", Vector2.ZERO, {"type": "files_and_dirs", "files": PackedStringArray(["res://test/props/"])})
	while fs.is_scanning():
		await fs.filesystem_changed
	await process_frame
	_check("a drop during a rescan waits for it", _describe(lib) == "root[barrel,crate,pillar,rock]{}", [scanning, _describe(lib)])

	var level: Variant = _panel.call("_new_folder", lib)
	_check("new folder is selected", _panel.call("selected_folder") == level and level.get("name") == "New Folder")
	_panel.call("_rename_folder", level, "Level")
	var pickups: Variant = _panel.call("_new_folder", lib)
	_panel.call("_rename_folder", pickups, "Pick-ups")
	var items: Variant = _panel.call("_new_folder", pickups)
	_panel.call("_rename_folder", items, "Items")
	_check("folders nest", _describe(lib) == "root[barrel,crate,pillar,rock]{Level[]{},Pick-ups[]{Items[]{}}}", _describe(lib))
	_check("tree shows every folder", tree.call("item_for", items) != null and tree.call("item_for", lib) == tree.call("get_root")
			and (tree.call("item_for", items) as TreeItem).get_parent() == tree.call("item_for", pickups))

	# Filing: FileSystem files and tiles dropped on tree folders.
	_panel.call("_on_folder_selected", lib)
	var files := {"type": "files", "files": PackedStringArray(["res://test/props/crate.tscn", "res://test/props/pillar.tscn"])}
	_check("files drop on a tree folder", tree.call("drop_on", tree.call("item_for", level), 0, files))
	var rock: Variant = lib.call("find_uid", ResourceUID.path_to_uid("res://test/props/rock.tscn"))
	var tile := {"type": "files", "files": PackedStringArray(), "asset_drawer_entries": _typed([rock])}
	tree.call("drop_on", tree.call("item_for", items), 0, tile)
	_check("existing assets move rather than copy", _describe(lib) == "root[barrel]{Level[crate,pillar]{},Pick-ups[]{Items[rock]{}}}", _describe(lib))

	# The root shows everything, grouped; a parent shows its subfolders.
	_check("root view groups subfolders", _names() == PackedStringArray(["barrel"]) and _headers() == PackedStringArray(["Level", "Pick-ups / Items"]),
			[_names(), _headers()])
	_panel.call("_on_folder_selected", pickups)
	_check("empty parent shows only its subfolders", not _grid.visible and _headers() == PackedStringArray(["Items"]), [_grid.visible, _headers()])
	_panel.call("_on_folder_selected", lib)
	var filter: LineEdit = _panel.get("_filter")
	filter.text = "ock"
	_panel.call("_on_filter_changed", filter.text)
	_check("filter reaches into subfolders", _headers() == PackedStringArray(["Pick-ups / Items"]) and not _grid.visible, [_headers(), _grid.visible])
	filter.text = ""
	_panel.call("_on_filter_changed", "")

	# Dragging a tile from a subsection onto the root grid moves it to the root.
	await process_frame
	var level_grid: Variant = sections.call("grids")[1]
	_check("subsection grid is Level's", level_grid.get("folder") == level and level_grid.get("item_count") == 2)
	level_grid.call("force_update_list_size")
	level_grid.call("select", 0)
	var drag: Variant = level_grid.call("_get_drag_data", (level_grid.call("_visible_item_rect", 0) as Rect2).get_center())
	_grid.call("force_update_list_size")
	var end := (_grid.call("_visible_item_rect", 0) as Rect2).end + Vector2(1, -2)
	_grid.call("_drop_data", end, drag)
	_check("tile dragged between sections changes folder", _describe(lib) == "root[barrel,crate]{Level[pillar]{},Pick-ups[]{Items[rock]{}}}", _describe(lib))

	# Arming works from any section.
	var items_grid: Variant = sections.call("grids")[2]
	_panel.call("_on_item_clicked", 0, Vector2.ZERO, MOUSE_BUTTON_LEFT, items_grid)
	_check("tile in a subsection arms", _panel.call("armed_entry") == rock)
	_panel.call("_let_go")

	# Moving folders: before a sibling, and never into themselves.
	tree.call("drop_on", tree.call("item_for", level), -1, {"type": "asset_drawer_folder", "folder": items})
	_check("folder drops above a sibling", _describe(lib) == "root[barrel,crate]{Items[rock]{},Level[pillar]{},Pick-ups[]{}}", _describe(lib))
	_check("folder can't go inside itself", not lib.call("move_folder", pickups, pickups, null))
	lib.call("move_folder", items, pickups, null)
	_check("folder can't go inside its child", not lib.call("move_folder", pickups, items, null))
	lib.call("move_folder", items, lib, pickups)

	# Deleting a folder keeps its assets. Backspace counts as Delete, as it's
	# the Delete key on Mac keyboards.
	(tree.call("item_for", level) as TreeItem).select(0)
	var backspace := InputEventKey.new()
	backspace.keycode = KEY_BACKSPACE
	backspace.pressed = true
	tree.call("_gui_input", backspace)
	_check("deleted folder's assets move up", _describe(lib) == EXPECTED_FOLDERS and _panel.call("selected_folder") == lib, _describe(lib))
	var on_disk: Variant = ResourceLoader.load(LIB_B, "", ResourceLoader.CACHE_MODE_IGNORE)
	_check("folders saved to disk", _describe(on_disk) == EXPECTED_FOLDERS, _describe(on_disk))
	await process_frame
