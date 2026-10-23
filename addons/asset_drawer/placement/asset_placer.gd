@tool
extends Node
## Placement mode. A ghost of the picked asset follows the mouse over the
## edited scene's colliders and/or visible meshes, and each left click stamps
## a copy into the scene as one undoable action. The ghost shows exactly what
## the next click places: its turn, tip, random yaw and scale, and snap.
## The plugin forwards 3D viewport input here; keys also count while the
## mouse is over a 3D viewport, even when the drawer has focus.

## Placement ended on its own: Esc, or the asset couldn't be placed.
signal stopped

const MeshRaycast := preload("mesh_raycast.gd")
const PlacementSettings := preload("placement_settings.gd")
const PlacementShortcuts := preload("placement_shortcuts.gd")

## How see-through the ghost is, from 0 (solid) to 1 (invisible).
const GHOST_TRANSPARENCY := 0.4
const TURN_STEP := PI / 2.0
## Alt+wheel turns this much per notch, or FINE_SPIN_STEP with Shift too.
const SPIN_STEP := PI / 12.0
const FINE_SPIN_STEP := PI / 36.0

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
## The asset's visible bounds in its own frame, so a copy can rest on the
## surface it's placed on whatever its origin is.
var _bounds := AABB()
## The last surface hit, kept so a key press can re-pose the ghost without
## a new raycast.
var _last_hit: Dictionary = {}

## Yaw from the turn keys and Alt+wheel, around the surface's up.
var _turn: float = 0.0
## 90° tips from the tip keys, applied in the asset's own frame.
var _tip := Basis.IDENTITY
var _random_yaw: float = 0.0
var _random_scale: float = 1.0
var _rng := RandomNumberGenerator.new()
## The mouse in the editor window, from the motion events seen in _input.
var _mouse_position := Vector2(-INF, -INF)


func _init() -> void:
	name = "AssetDrawerPlacer"


func _exit_tree() -> void:
	stop()


func is_placing() -> bool:
	return _scene != null


func ghost() -> Node3D:
	return _ghost


## Starts placing the scene at [param path]. Returns false, with a warning,
## when no scene is open, the open scene is 2D, or the asset's root isn't a
## Node3D.
func start(path: String) -> bool:
	stop()
	var root := EditorInterface.get_edited_scene_root()
	if root == null or root is CanvasItem:
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
	_bounds = visible_bounds(_ghost)
	_parent = _placement_parent(root)
	_mesh_raycast = MeshRaycast.new(root)
	_turn = 0.0
	_tip = Basis.IDENTITY
	_roll()
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
	_last_hit = {}


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
				_roll()
				# Hit again so the ghost moves onto the copy just placed
				# rather than sitting inside it until the mouse moves.
				_update_hit(camera, button.position)
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if button != null and button.alt_pressed and _is_wheel(button.button_index):
		if button.pressed:
			var up := button.button_index == MOUSE_BUTTON_WHEEL_UP or button.button_index == MOUSE_BUTTON_WHEEL_LEFT
			_turn += (1.0 if up else -1.0) * (FINE_SPIN_STEP if button.shift_pressed else SPIN_STEP)
			_pose_ghost()
		return EditorPlugin.AFTER_GUI_INPUT_STOP

	var key := event as InputEventKey
	if key != null and handle_key(key):
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	return EditorPlugin.AFTER_GUI_INPUT_PASS


## Applies a placement key: Esc, or one of the turn, tip, reset and re-roll
## shortcuts. Returns whether the key was used; re-roll is only used while
## Random is on.
func handle_key(key: InputEventKey) -> bool:
	if not is_placing() or not key.pressed:
		return false
	if key.keycode == KEY_ESCAPE and not key.echo:
		cancel()
		return true
	match PlacementShortcuts.action_for(key):
		PlacementShortcuts.Action.TURN_LEFT:
			_turn += TURN_STEP
		PlacementShortcuts.Action.TURN_RIGHT:
			_turn -= TURN_STEP
		PlacementShortcuts.Action.TIP_FORWARD:
			_tip = _tip * Basis(Vector3.RIGHT, TURN_STEP)
		PlacementShortcuts.Action.TIP_SIDEWAYS:
			_tip = _tip * Basis(Vector3.BACK, TURN_STEP)
		PlacementShortcuts.Action.RESET:
			_turn = 0.0
			_tip = Basis.IDENTITY
		PlacementShortcuts.Action.REROLL:
			if not settings.random_enabled:
				return false
			_roll()
		_:
			return false
	_pose_ghost()
	return true


func _input(event: InputEvent) -> void:
	if not is_placing():
		return
	var motion := event as InputEventMouseMotion
	if motion != null:
		_mouse_position = motion.position
		return
	var key := event as InputEventKey
	if key != null and _mouse_over_3d_viewport() and handle_key(key):
		get_viewport().set_input_as_handled()


## Stamps a copy of the asset at [param global_xform] as one undoable action,
## and returns it.
func place(global_xform: Transform3D) -> Node3D:
	var root := EditorInterface.get_edited_scene_root()
	if not is_instance_valid(_parent) or not _parent.is_inside_tree():
		_parent = root
	var node := _scene.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node3D
	node.scene_file_path = _scene_path
	var parent_3d := _parent as Node3D
	var local_xform := parent_3d.global_transform.affine_inverse() * global_xform \
			if parent_3d != null else global_xform
	node.transform = local_xform

	undo_redo.create_action("Place %s" % node.name, UndoRedo.MERGE_DISABLE, root)
	undo_redo.add_do_method(_parent, &"add_child", node, true)
	undo_redo.add_do_method(node, &"set_owner", root)
	# Set the transform again once the node is in the scene: some addons
	# (the 3D Cursor, for one) move every node that enters the tree.
	undo_redo.add_do_property(node, &"transform", local_xform)
	undo_redo.add_do_reference(node)
	undo_redo.add_undo_method(_parent, &"remove_child", node)
	undo_redo.commit_action()
	return node


func _update_hit(camera: Camera3D, screen_position: Vector2) -> void:
	_last_hit = _surface_hit(camera, screen_position)
	_pose_ghost()


## Moves the ghost to where the next click would place, or hides it when the
## mouse is over nothing.
func _pose_ghost() -> void:
	_has_hit = not _last_hit.is_empty()
	if _has_hit:
		_hit_transform = placement_transform(_last_hit["position"] as Vector3, _last_hit["normal"] as Vector3)
		_ghost.global_transform = _hit_transform
	_ghost.visible = _has_hit


## Where a copy lands for a hit at [param position] on a surface facing
## [param normal]: snapped, aligned, turned, tipped, and randomized as the
## settings say, then lifted along the normal so its visible bounds rest on
## the surface rather than its origin.
func placement_transform(position: Vector3, normal: Vector3) -> Transform3D:
	if settings.snap_enabled and settings.snap_step > 0.0:
		position = snap_to_surface(position, normal, settings.snap_step)
	var surface := surface_basis(normal) if settings.align_to_normal else Basis.IDENTITY
	var yaw := _turn + (_random_yaw if settings.random_enabled else 0.0)
	var scale := _random_scale if settings.random_enabled else 1.0
	var basis := (surface * Basis(Vector3.UP, yaw) * _tip).scaled(Vector3.ONE * scale)
	position += normal * rest_offset(_bounds, basis, normal)
	return Transform3D(basis, position)


## How far along [param normal] an asset with local [param bounds], posed
## with [param basis], has to move from the hit point so that its nearest
## corner touches the surface: the way the editor's own drag and drop places
## a scene. An asset whose origin is already on that face moves by nothing;
## one with a centred origin moves out by half its depth. Empty bounds, from
## an asset with nothing visible, move it by nothing.
static func rest_offset(bounds: AABB, basis: Basis, normal: Vector3) -> float:
	if bounds.size.is_zero_approx():
		return 0.0
	var lowest := INF
	for corner: int in 8:
		lowest = minf(lowest, (basis * bounds.get_endpoint(corner)).dot(normal))
	return -lowest


## The combined bounds of everything visible under [param root], in
## [param root]'s own frame. Hidden branches are left out; [param root]'s
## own visibility is ignored, since the ghost starts hidden.
static func visible_bounds(root: Node3D) -> AABB:
	var bounds := AABB()
	var first := true
	var to_root := root.global_transform.affine_inverse()
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		var node_3d := node as Node3D
		if node != root and node_3d != null and not node_3d.visible:
			continue
		var geometry := node as GeometryInstance3D
		if geometry != null:
			var box := to_root * geometry.global_transform * geometry.get_aabb()
			bounds = box if first else bounds.merge(box)
			first = false
		pending.append_array(node.get_children())
	return bounds


## Snaps [param position] to a world grid of [param step], then slides it
## back along [param normal] onto the plane it was hit on, so it stays on
## the surface: a floor snaps X and Z, a wall the two axes across it.
static func snap_to_surface(position: Vector3, normal: Vector3, step: float) -> Vector3:
	var snapped := position.snapped(Vector3.ONE * step)
	return snapped - normal * (snapped - position).dot(normal)


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


## Picks the next random yaw and scale, so the ghost can show them before
## the click that uses them.
func _roll() -> void:
	_random_yaw = deg_to_rad(_rng.randf_range(0.0, settings.random_yaw_degrees))
	_random_scale = _rng.randf_range(minf(settings.random_scale_min, settings.random_scale_max),
			maxf(settings.random_scale_min, settings.random_scale_max))


func _is_wheel(button_index: MouseButton) -> bool:
	return button_index == MOUSE_BUTTON_WHEEL_UP or button_index == MOUSE_BUTTON_WHEEL_DOWN \
			or button_index == MOUSE_BUTTON_WHEEL_LEFT or button_index == MOUSE_BUTTON_WHEEL_RIGHT


## Whether the mouse is over one of the visible 3D editor viewports.
func _mouse_over_3d_viewport() -> bool:
	for index: int in 4:
		var container := EditorInterface.get_editor_viewport_3d(index).get_parent() as Control
		if container != null and container.is_visible_in_tree() \
				and container.get_global_rect().has_point(_mouse_position):
			return true
	return false


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
