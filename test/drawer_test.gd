extends SceneTree
## Drives the drawer panel headlessly. RUN=1 builds two libraries; RUN=2
## (same HOME) checks they come back, then tests a moved asset.

const LIB_A := "res://test_tmp_props.tres"
const LIB_B := "res://test_tmp_other.tres"

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
	filter.text = ""
	_panel.call("_on_filter_changed", "")
	_check("filter cleared", _names() == PackedStringArray(["rock", "crate", "barrel"]), _names())

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
	_panel.call("_on_switcher_selected", 0)
	_check("switched back", (_panel.call("active_library") as Resource).resource_path == LIB_A and _grid.item_count == 3)

	(_panel.get("_size_slider") as HSlider).value = 96
	_check("thumbnail size applied", _grid.fixed_icon_size == Vector2i(96, 96))

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
	_check("thumbnail size restored", _grid.fixed_icon_size == Vector2i(96, 96), _grid.fixed_icon_size)

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
