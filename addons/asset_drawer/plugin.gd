@tool
extends EditorPlugin
## Registers the asset drawer dock. Starts in the bottom panel; it can be
## dragged to a side dock or floated like any other EditorDock.

const AssetDrawerPanel := preload("drawer/asset_drawer_panel.gd")

var _dock: EditorDock


func _enter_tree() -> void:
	_dock = EditorDock.new()
	_dock.title = "Assets"
	_dock.layout_key = "asset_drawer"
	_dock.icon_name = "PackedScene"
	_dock.default_slot = EditorDock.DOCK_SLOT_BOTTOM
	_dock.available_layouts = EditorDock.DOCK_LAYOUT_ALL
	_dock.add_child(AssetDrawerPanel.new())
	add_dock(_dock)


func _exit_tree() -> void:
	remove_dock(_dock)
	_dock.queue_free()
	_dock = null
