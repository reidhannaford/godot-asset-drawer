@tool
extends Node
## Placement mode. A ghost of the picked asset follows the mouse over the
## edited scene's colliders and/or visible meshes, and each left click stamps
## a copy into the scene as one undoable action. The plugin forwards 3D
## viewport input here.

## Placement ended on its own: Esc, or the asset couldn't be placed.
signal stopped

const MeshRaycast := preload("mesh_raycast.gd")
const PlacementSettings := preload("placement_settings.gd")

## How see-through the ghost is, from 0 (solid) to 1 (invisible).
const GHOST_TRANSPARENCY := 0.4

var undo_redo: EditorUndoRedoManager
var settings: PlacementSettings

var _scene: PackedScene
var _mesh_raycast: MeshRaycast
var _scene_path: String = ""
## Lives beside the edited scene's root, in the same world but outside the
## scene, so it never shows in the Scene dock or gets saved.
var _ghost: Node3D
var _parent: Node
var _has_hit: bool = false
var _hit_transform := Transform3D.IDENTITY


func _init() -> void:
	name = "AssetDrawerPlacer"


func _exit_tree() -> void:
	stop()


func is_placing() -> bool:
	return _scene != null


func ghost() -> Node3D:
	return _ghost


## Starts placing the scene at [param path]. Returns false, with a warning,
## when no scene is open or the asset's root isn't a Node3D.
func start(path: String) -> bool:
	stop()
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		push_warning("Asset Drawer: open a 3D scene to place assets in.")
		return false
	var scene := ResourceLoader.load(path) as PackedScene
	if scene == null:
		push_warning("Asset Drawer: couldn't load %s." % path)
		return false
	var instance := scene.instantiate()
	if not instance is Node3D:
		instance.free()
		push_warning("Asset Drawer: %s can't be placed; its root isn't a Node3D." % path)
		return false

	_scene = scene
	_scene_path = path
	_ghost = instance as Node3D
	_ghost.name = "AssetDrawerGhost"
	_ghost.visible = false
	_make_ghostly(_ghost)
	root.get_parent().add_child(_ghost)
	_parent = _placement_parent(root)
	_mesh_raycast = MeshRaycast.new(root)
	return true


## Ends placement without emitting [signal stopped].
func stop() -> void:
	if is_instance_valid(_ghost):
		_ghost.queue_free()
	_ghost = null
	_scene = null
	_scene_path = ""
	_parent = null
	_mesh_raycast = null
	_has_hit = false


## Ends placement and emits [signal stopped], so the drawer can let go of
## the tile.
func cancel() -> void:
	var was_placing := is_placing()
	stop()
	if was_placing:
		stopped.emit()


## Handles one 3D viewport event; returns an [code]EditorPlugin.AFTER_GUI_INPUT_*[/code]
## value. Left clicks are always eaten while placing, so a click that misses
## doesn't change the selection. Right-click passes through for freelook.
func forward_input(camera: Camera3D, event: InputEvent) -> int:
	if not is_placing():
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	var motion := event as InputEventMouseMotion
	if motion != null:
		_update_hit(camera, motion.position)
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	var button := event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT and not button.alt_pressed:
		if button.pressed:
			_update_hit(camera, button.position)
			if _has_hit:
				place(_hit_transform)
		return EditorPlugin.AFTER_GUI_INPUT_STOP

	var key := event as InputEventKey
	if key != null and key.pressed and key.keycode == KEY_ESCAPE:
		cancel()
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	return EditorPlugin.AFTER_GUI_INPUT_PASS


## Stamps a copy of the asset at [param global_xform] as one undoable action,
## and returns it.
func place(global_xform: Transform3D) -> Node3D:
	var root := EditorInterface.get_edited_scene_root()
	if not is_instance_valid(_parent) or not _parent.is_inside_tree():
		_parent = root
	var node := _scene.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node3D
	node.scene_file_path = _scene_path
	var parent_3d := _parent as Node3D
	node.transform = parent_3d.global_transform.affine_inverse() * global_xform \
			if parent_3d != null else global_xform

	undo_redo.create_action("Place %s" % node.name, UndoRedo.MERGE_DISABLE, root)
	undo_redo.add_do_method(_parent, &"add_child", node, true)
	undo_redo.add_do_method(node, &"set_owner", root)
	undo_redo.add_do_reference(node)
	undo_redo.add_undo_method(_parent, &"remove_child", node)
	undo_redo.commit_action()
	return node


func _update_hit(camera: Camera3D, screen_position: Vector2) -> void:
	var hit := _surface_hit(camera, screen_position)
	_has_hit = not hit.is_empty()
	if _has_hit:
		var basis := surface_basis(hit["normal"] as Vector3) if settings.align_to_normal else Basis.IDENTITY
		_hit_transform = Transform3D(basis, hit["position"] as Vector3)
		_ghost.global_transform = _hit_transform
	_ghost.visible = _has_hit


## The rotation that turns world up onto [param normal] by the shortest arc,
## so a flat floor gives no rotation and slopes tip the asset the least.
static func surface_basis(normal: Vector3) -> Basis:
	if normal.dot(Vector3.UP) < -0.9999:
		# Straight down: every axis is a shortest arc; pick a flip about X.
		return Basis(Vector3.RIGHT, PI)
	return Basis(Quaternion(Vector3.UP, normal.normalized()))


## Where a ray through [param screen_position] first meets a surface the hit
## mode allows, as {position, normal}, or an empty dictionary on a miss.
func _surface_hit(camera: Camera3D, screen_position: Vector2) -> Dictionary:
	var from := camera.project_ray_origin(screen_position)
	var to := from + camera.project_ray_normal(screen_position) * camera.far
	var collider_hit := {}
	var mesh_hit := {}
	if settings.hit_mode != PlacementSettings.HitMode.MESHES:
		collider_hit = _collider_hit(camera.get_world_3d(), from, to)
	if settings.hit_mode != PlacementSettings.HitMode.COLLIDERS:
		mesh_hit = _mesh_raycast.cast(from, to)
	if collider_hit.is_empty() or mesh_hit.is_empty():
		return mesh_hit if collider_hit.is_empty() else collider_hit
	var collider_distance := from.distance_squared_to(collider_hit["position"] as Vector3)
	var mesh_distance := from.distance_squared_to(mesh_hit["position"] as Vector3)
	return collider_hit if collider_distance <= mesh_distance else mesh_hit


func _collider_hit(world: World3D, from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var hit := world.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return {}
	return {"position": hit["position"], "normal": hit["normal"]}


## The selected node, or the scene root when nothing is selected. A node
## inside an instanced scene, such as a crate placed a moment ago, defers to
## the nearest ancestor that belongs to the edited scene itself.
func _placement_parent(root: Node) -> Node:
	var selected := EditorInterface.get_selection().get_selected_nodes()
	var target: Node = selected[0] if not selected.is_empty() else root
	while target != null and target != root \
			and (target.owner != root or not target.scene_file_path.is_empty()):
		target = target.get_parent()
	return target if target != null else root


## Fades the ghost, turns off its shadows, and takes its colliders off every
## layer so the placement ray never hits it.
func _make_ghostly(node: Node) -> void:
	var geometry := node as GeometryInstance3D
	if geometry != null:
		geometry.transparency = GHOST_TRANSPARENCY
		geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var collider := node as CollisionObject3D
	if collider != null:
		collider.collision_layer = 0
		collider.collision_mask = 0
	var area := node as Area3D
	if area != null:
		area.monitoring = false
		area.monitorable = false
	for child: Node in node.get_children():
		_make_ghostly(child)
