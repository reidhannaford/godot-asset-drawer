@tool
extends ItemList
## The drawer's thumbnail grid. Each item's metadata is its AssetDrawerEntry.
## Takes file drops from the FileSystem dock and reorders its own items by
## drag; the panel decides what a drop means for the library.

## FileSystem files or folders were dropped just before [param before], or at
## the end when it's null.
signal files_dropped(paths: PackedStringArray, before: AssetDrawerEntry)
## Items from this grid were dragged to just before [param before].
signal entries_moved(entries: Array[AssetDrawerEntry], before: AssetDrawerEntry)
signal delete_pressed
signal escape_pressed

## Key the grid adds to its own drag data so it can tell a reorder from a
## FileSystem drop. The rest of the data looks like a FileSystem drag, so
## dragging a tile into the 3D viewport or Scene dock instances it there.
const ENTRIES_KEY := "asset_drawer_entries"

## Shown in the middle of the grid while it has no items.
var empty_text: String = "":
	set(value):
		empty_text = value
		queue_redraw()
## Whether drops are allowed. Off while no library is open.
var accepts_drops: bool = false

var _drop_index: int = -1


func _init() -> void:
	select_mode = SELECT_MULTI
	allow_rmb_select = true
	max_columns = 0
	same_column_width = true
	icon_mode = ICON_MODE_TOP
	max_text_lines = 2
	text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	size_flags_vertical = SIZE_EXPAND_FILL
	# Room for one row of default-size tiles with their names.
	custom_minimum_size.y = 128.0
	set_thumbnail_size(64)


func set_thumbnail_size(pixels: int) -> void:
	fixed_icon_size = Vector2i(pixels, pixels)
	fixed_column_width = pixels + 24


func entry_at(index: int) -> AssetDrawerEntry:
	return get_item_metadata(index) as AssetDrawerEntry


func selected_entries() -> Array[AssetDrawerEntry]:
	var selected: Array[AssetDrawerEntry] = []
	for index: int in get_selected_items():
		selected.append(entry_at(index))
	return selected


func select_entries(entries: Array[AssetDrawerEntry]) -> void:
	deselect_all()
	for index: int in item_count:
		if entries.has(entry_at(index)):
			select(index, false)


## Tints the tile for [param entry] (the one being placed), or clears the
## tint when it's null.
func highlight(entry: AssetDrawerEntry) -> void:
	var tint := get_theme_color(&"accent_color", &"Editor") * Color(1.0, 1.0, 1.0, 0.35)
	for index: int in item_count:
		set_item_custom_bg_color(index, tint if entry != null and entry_at(index) == entry else Color.TRANSPARENT)


func _gui_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if (key.keycode == KEY_DELETE or key.keycode == KEY_BACKSPACE) and not get_selected_items().is_empty():
		delete_pressed.emit()
		accept_event()
	elif key.keycode == KEY_ESCAPE:
		escape_pressed.emit()
		accept_event()


func _get_drag_data(at_position: Vector2) -> Variant:
	var index := get_item_at_position(at_position, true)
	if index == -1:
		return null
	if not is_selected(index):
		select(index)
	var entries := selected_entries()
	var files := PackedStringArray()
	for entry: AssetDrawerEntry in entries:
		var path := entry.resolve_path()
		if not path.is_empty():
			files.append(path)

	var preview := Label.new()
	preview.text = get_item_text(index) if entries.size() == 1 else "%d assets" % entries.size()
	set_drag_preview(preview)
	return {"type": "files", "files": files, "from": self, ENTRIES_KEY: entries}


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	var droppable: bool = accepts_drops and data is Dictionary \
			and ((data as Dictionary).has(ENTRIES_KEY) \
				or (data as Dictionary).get("type") in ["files", "files_and_dirs"])
	var index := _insertion_index(at_position) if droppable else -1
	if index != _drop_index:
		_drop_index = index
		queue_redraw()
	return droppable


func _drop_data(at_position: Vector2, data: Variant) -> void:
	var drop := data as Dictionary
	var index := _insertion_index(at_position)
	var before := entry_at(index) if index < item_count else null
	_clear_drop_marker()
	if drop.has(ENTRIES_KEY):
		var moved: Array[AssetDrawerEntry] = []
		moved.assign(drop[ENTRIES_KEY])
		entries_moved.emit(moved, before)
	else:
		files_dropped.emit(drop["files"] as PackedStringArray, before)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END or what == NOTIFICATION_MOUSE_EXIT:
		_clear_drop_marker()


func _draw() -> void:
	if item_count == 0 and not empty_text.is_empty():
		var font := get_theme_font(&"font")
		var font_size := get_theme_font_size(&"font_size")
		var width := size.x - 16.0
		var height := font.get_string_size(empty_text, HORIZONTAL_ALIGNMENT_CENTER, width, font_size).y
		var baseline := Vector2(8.0, (size.y - height) / 2.0 + font.get_ascent(font_size))
		draw_string(font, baseline, empty_text, HORIZONTAL_ALIGNMENT_CENTER, width, font_size,
				get_theme_color(&"font_color") * Color(1.0, 1.0, 1.0, 0.6))
	if _drop_index != -1 and item_count > 0:
		_draw_drop_marker()


## Draws a bar in the gap the dragged items will land in.
func _draw_drop_marker() -> void:
	var after_last := _drop_index >= item_count
	var rect := _visible_item_rect(item_count - 1 if after_last else _drop_index)
	var gap := float(get_theme_constant(&"h_separation")) / 2.0
	var x := rect.end.x + gap if after_last else rect.position.x - gap
	draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y),
			get_theme_color(&"accent_color", &"Editor"), 2.0)


## Item rects come back in content space; this shifts them by the scroll.
func _visible_item_rect(index: int) -> Rect2:
	var rect := get_item_rect(index)
	rect.position.y -= get_v_scroll_bar().value
	return rect


## Which gap a drop at [param at_position] lands in, from 0 (before the
## first item) to item_count (after the last).
func _insertion_index(at_position: Vector2) -> int:
	if item_count == 0:
		return 0
	var index := get_item_at_position(at_position, false)
	var rect := _visible_item_rect(index)
	var below_row := at_position.y > rect.end.y
	return index + 1 if below_row or at_position.x > rect.get_center().x else index


func _clear_drop_marker() -> void:
	if _drop_index != -1:
		_drop_index = -1
		queue_redraw()
