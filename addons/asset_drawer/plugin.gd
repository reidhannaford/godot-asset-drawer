@tool
extends EditorPlugin
## Registers the asset drawer dock and connects it to placement. The dock
## starts in the bottom panel; it can be dragged to a side dock or floated
## like any other EditorDock.

const AssetDrawerPanel := preload("drawer/asset_drawer_panel.gd")
const AssetPlacer := preload("placement/asset_placer.gd")
const PlacementBar := preload("placement/placement_bar.gd")
const PlacementSettings := preload("placement/placement_settings.gd")
const PlacementShortcuts := preload("placement/placement_shortcuts.gd")

var _dock: EditorDock
var _panel: AssetDrawerPanel
var _placer: AssetPlacer


func _enter_tree() -> void:
	PlacementShortcuts.register()
	var settings := PlacementSettings.new()
	settings.restore()

	_panel = AssetDrawerPanel.new()
	_panel.add_placement_control(PlacementBar.new(settings))
	_placer = AssetPlacer.new()
	_placer.undo_redo = get_undo_redo()
	_placer.settings = settings
	add_child(_placer)

	_panel.asset_armed.connect(_on_asset_armed)
	_panel.asset_disarmed.connect(_on_asset_disarmed)
	_placer.stopped.connect(_on_placement_stopped)
	scene_changed.connect(_on_scene_changed)
	set_input_event_forwarding_always_enabled()

	_dock = EditorDock.new()
	_dock.title = "Assets"
	_dock.layout_key = "asset_drawer"
	_dock.icon_name = "PackedScene"
	_dock.default_slot = EditorDock.DOCK_SLOT_BOTTOM
	_dock.available_layouts = EditorDock.DOCK_LAYOUT_ALL
	_dock.add_child(_panel)
	add_dock(_dock)


func _exit_tree() -> void:
	_placer.stop()
	remove_dock(_dock)
	# Freed now rather than queued: at editor shutdown the queue never runs,
	# and the thumbnail viewport inside must go before the renderer does.
	_dock.free()
	_dock = null
	_panel = null
	_placer.free()
	_placer = null


func _forward_3d_gui_input(viewport_camera: Camera3D, event: InputEvent) -> int:
	return _placer.forward_input(viewport_camera, event)


func _on_asset_armed(path: String) -> void:
	var placing := _placer.start(path)
	if not placing:
		_panel.disarm()
	_panel.set_placing(placing, PlacementShortcuts.hint())


func _on_asset_disarmed() -> void:
	_placer.stop()
	_panel.set_placing(false)


func _on_placement_stopped() -> void:
	_panel.disarm()
	_panel.set_placing(false)


func _on_scene_changed(_scene_root: Node) -> void:
	_placer.cancel()
