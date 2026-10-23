extends SceneTree
## Drives placement headlessly against test_level.tscn: a camera looking
## straight down, synthetic mouse events through the placer, then undo and
## redo. Never saves the level.

const LEVEL := "res://test/test_level.tscn"
const CRATE := "res://test/props/crate.tscn"
const NODE_ROOT_SCENE := "res://test_tmp_node_root.tscn"
const SCENE_2D := "res://test_tmp_2d.tscn"

var _frame := 0
var _failures := 0
var _placer: Variant
var _panel: Variant
var _camera: Camera3D


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 60:
		EditorInterface.open_scene_from_path(LEVEL)
	if _frame == 90:
		_run.call_deferred()
	if _frame == 3000:
		print("WATCHDOG")
		quit(1)
	return false


func _check(label: String, ok: bool, detail: Variant = "") -> void:
	print(("PASS " if ok else "FAIL ") + label + ("" if ok else "  -> " + str(detail)))
	if not ok:
		_failures += 1


func _motion(screen: Vector2) -> int:
	var event := InputEventMouseMotion.new()
	event.position = screen
	return _placer.call("forward_input", _camera, event)


func _click(screen: Vector2) -> int:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = screen
	press.pressed = true
	var result: int = _placer.call("forward_input", _camera, press)
	var release := press.duplicate() as InputEventMouseButton
	release.pressed = false
	_placer.call("forward_input", _camera, release)
	return result


## Points the camera straight down from above [param ground] and returns the
## screen centre.
func _look_down_at(ground: Vector3) -> Vector2:
	_camera.global_transform = Transform3D(Basis.from_euler(Vector3(-PI / 2.0, 0.0, 0.0)), ground + Vector3.UP * 10.0)
	return _camera.get_viewport().get_visible_rect().size / 2.0


func _history() -> UndoRedo:
	var undo_redo := EditorInterface.get_editor_undo_redo()
	var root := EditorInterface.get_edited_scene_root()
	return undo_redo.get_history_undo_redo(undo_redo.get_object_history_id(root))


func _run() -> void:
	_placer = root.find_children("AssetDrawerPlacer", "", true, false)[0]
	_panel = root.find_children("AssetDrawer", "VBoxContainer", true, false)[0]
	# The arming checks need the dock on screen, whatever layout the editor saved.
	(_panel.get_parent() as Node).call("make_visible")
	var level := EditorInterface.get_edited_scene_root() as Node3D
	_check("level open", level != null and level.scene_file_path == LEVEL)
	print("PHYSICS ", ProjectSettings.get_setting("physics/3d/physics_engine"))

	_camera = Camera3D.new()
	level.get_parent().add_child(_camera)
	await physics_frame
	var centre := _look_down_at(Vector3.ZERO)
	var children_before := level.get_child_count()

	# Start: ghost sits outside the scene with its colliders off every layer.
	EditorInterface.get_selection().clear()
	_check("start placing", _placer.call("start", CRATE))
	var ghost: Node3D = _placer.call("ghost")
	_check("ghost is outside the edited scene", ghost != null and ghost.get_parent() == level.get_parent() and not level.is_ancestor_of(ghost))
	var body := ghost.find_children("*", "CollisionObject3D", true, false)[0] as CollisionObject3D
	_check("ghost collider is on no layer", body.collision_layer == 0 and body.collision_mask == 0)
	_check("ghost hidden before a hit", not ghost.visible)

	# Hover: ghost follows the hit on the floor.
	_check("motion passes through", _motion(centre) == EditorPlugin.AFTER_GUI_INPUT_PASS)
	_check("ghost on the floor", ghost.visible and ghost.global_position.distance_to(Vector3.ZERO) < 0.01, ghost.global_position)

	# Click: one crate under the scene root, owned and instanced.
	_check("click is eaten", _click(centre) == EditorPlugin.AFTER_GUI_INPUT_STOP)
	_check("one node added under root", level.get_child_count() == children_before + 1, level.get_child_count())
	var first := level.get_child(level.get_child_count() - 1) as Node3D
	_check("placed crate is an owned instance", first != null and first.owner == level and first.scene_file_path == CRATE,
			[first, first.owner if first else null, first.scene_file_path if first else ""])
	_check("placed at the hit", first.global_position.distance_to(Vector3.ZERO) < 0.01, first.global_position)

	# Stacking: the ray now meets the new crate's top.
	await physics_frame
	_motion(centre)
	_check("ghost stacks on the new crate", absf(ghost.global_position.y - 1.0) < 0.01, ghost.global_position)
	_click(centre)
	var second := level.get_child(level.get_child_count() - 1) as Node3D
	_check("second crate stacked, readable name", second != first and absf(second.global_position.y - 1.0) < 0.01 and second.name == "Crate2",
			[second.name, second.global_position])

	# Undo and redo.
	_history().undo()
	_check("undo removes the second crate", not second.is_inside_tree() and level.get_child_count() == children_before + 1)
	_history().redo()
	_check("redo puts it back", second.is_inside_tree() and second.get_parent() == level and second.owner == level)

	# Something that moves every new node, like the 3D Cursor, doesn't win.
	var mover := func(node: Node) -> void:
		var node_3d := node as Node3D
		if node_3d != null and level.is_ancestor_of(node_3d) and node_3d.scene_file_path == CRATE:
			node_3d.global_position = Vector3(50.0, 0.0, 50.0)
	node_added.connect(mover)
	centre = _look_down_at(Vector3(2.0, 0.0, 6.0))
	_motion(centre)
	_click(centre)
	var moved := level.get_child(level.get_child_count() - 1) as Node3D
	_check("placement beats a node_added mover", _near(moved.global_position, Vector3(2.0, 0.0, 6.0)), moved.global_position)
	_history().undo()
	_history().redo()
	_check("redo beats it too", _near(moved.global_position, Vector3(2.0, 0.0, 6.0)), moved.global_position)
	node_added.disconnect(mover)

	# Miss: nothing under the cursor hides the ghost, and clicks place nothing.
	_camera.global_transform = Transform3D(Basis.from_euler(Vector3(PI / 2.0, 0.0, 0.0)), Vector3.UP * 10.0)
	_motion(centre)
	_check("ghost hidden on a miss", not ghost.visible)
	var count := level.get_child_count()
	_check("click on a miss is still eaten", _click(centre) == EditorPlugin.AFTER_GUI_INPUT_STOP)
	_check("click on a miss places nothing", level.get_child_count() == count)

	# Parenting: the selected node, and the nearest scene node above an instance.
	var props := level.get_node("Props") as Node3D
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(props)
	_placer.call("start", CRATE)
	ghost = _placer.call("ghost")
	centre = _look_down_at(Vector3(3.0, 0.0, -3.0))
	_motion(centre)
	_click(centre)
	_check("placed under the selected node", props.get_child_count() == 1)
	var in_props := props.get_child(0) as Node3D
	_check("transform is global despite the parent", in_props != null and in_props.global_position.distance_to(Vector3(3.0, 0.0, -3.0)) < 0.01,
			in_props.global_position if in_props else null)
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(in_props.get_node("Body"))
	_placer.call("start", CRATE)
	centre = _look_down_at(Vector3(-3.0, 0.0, -1.0))
	_motion(centre)
	_click(centre)
	_check("selection inside an instance defers to its scene parent", props.get_child_count() == 2 and in_props.get_child_count() == 2,
			[props.get_child_count(), in_props.get_child_count()])
	EditorInterface.get_selection().clear()

	await _surface_checks(level)
	_transform_checks(level)

	# The ghost never lands in the saved scene.
	var packed := PackedScene.new()
	packed.pack(level)
	var saved := packed.instantiate()
	_check("ghost not saved", saved.find_children("AssetDrawerGhost", "", true, false).is_empty() and saved.find_child("AssetDrawerGhost") == null)
	saved.free()

	# Esc stops placement and frees the ghost.
	_placer.call("start", CRATE)
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	ghost = _placer.call("ghost")
	_check("esc is eaten", _placer.call("forward_input", _camera, escape) == EditorPlugin.AFTER_GUI_INPUT_STOP)
	await process_frame
	_check("esc stops placing", not _placer.call("is_placing") and not is_instance_valid(ghost))

	# A scene whose root isn't a Node3D is refused.
	var node_root := Node.new()
	node_root.name = "Plain"
	var plain := PackedScene.new()
	plain.pack(node_root)
	node_root.free()
	ResourceSaver.save(plain, NODE_ROOT_SCENE)
	_check("non-Node3D root refused", not _placer.call("start", NODE_ROOT_SCENE))
	DirAccess.remove_absolute(NODE_ROOT_SCENE)

	await _drawer_arming()
	await _scene_2d_refused()

	_camera.queue_free()
	print("FAILURES ", _failures)
	quit(_failures)


## Clicking tiles in the drawer arms and lets go of placement.
func _drawer_arming() -> void:
	_panel.call("_create_library", "res://test_tmp_arming.tres")
	var grid: Variant = _panel.get("_grid")
	grid.call("_drop_data", Vector2.ZERO, {"type": "files", "files": PackedStringArray([CRATE, "res://test/props/rock.tscn"])})
	_panel.call("_on_item_clicked", 0, Vector2.ZERO, MOUSE_BUTTON_LEFT)
	_check("clicking a tile starts placing", _placer.call("is_placing") and _panel.call("armed_entry") != null)
	var hint: Label = _panel.get("_status")
	_check("placement row and key hint show while placing", hint.is_visible_in_tree() and hint.text.contains("turn"), hint.text)
	_panel.call("_on_item_clicked", 1, Vector2.ZERO, MOUSE_BUTTON_LEFT)
	_check("clicking another tile switches asset", _placer.call("is_placing") and _panel.call("armed_entry") == grid.call("entry_at", 1))
	_panel.call("_on_item_clicked", 1, Vector2.ZERO, MOUSE_BUTTON_LEFT)
	_check("clicking the armed tile lets go", not _placer.call("is_placing") and _panel.call("armed_entry") == null)

	_panel.call("_on_item_clicked", 0, Vector2.ZERO, MOUSE_BUTTON_LEFT)
	grid.emit_signal("escape_pressed")
	await process_frame
	_check("letting go clears the tile selection", (grid.call("get_selected_items") as PackedInt32Array).is_empty())

	# A press on a tile that's already selected still arms it (ItemList holds
	# back item_clicked for those).
	await process_frame
	grid.call("force_update_list_size")
	grid.call("select", 0)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = (grid.call("_visible_item_rect", 0) as Rect2).get_center()
	grid.call("_gui_input", press)
	_check("pressing an already-selected tile arms it", _placer.call("is_placing") and _panel.call("armed_entry") == grid.call("entry_at", 0))
	_placer.call("cancel")
	await process_frame
	_check("Esc in the viewport clears the tile selection", (grid.call("get_selected_items") as PackedInt32Array).is_empty() and _panel.call("armed_entry") == null)
	_check("esc in the drawer lets go", not _placer.call("is_placing") and _panel.call("armed_entry") == null)
	_check("placement row hides after", not hint.is_visible_in_tree())

	_panel.call("_on_item_clicked", 0, Vector2.ZERO, MOUSE_BUTTON_LEFT)
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	_placer.call("forward_input", _camera, escape)
	_check("esc in the viewport clears the tile", _panel.call("armed_entry") == null)

	_panel.call("_on_item_clicked", 0, Vector2.ZERO, MOUSE_BUTTON_LEFT)
	grid.call("select", 0)
	_panel.call("_remove_selected")
	_check("removing the armed asset stops placing", not _placer.call("is_placing") and _panel.call("armed_entry") == null)

	_panel.call("_on_item_clicked", 0, Vector2.ZERO, MOUSE_BUTTON_LEFT)
	_panel.call("_close_active")
	_check("closing the library stops placing", not _placer.call("is_placing"))
	DirAccess.remove_absolute("res://test_tmp_arming.tres")
	await process_frame


## A 2D scene can't take 3D assets, however the drawer is used.
func _scene_2d_refused() -> void:
	var control := Control.new()
	control.name = "Menu"
	var packed := PackedScene.new()
	packed.pack(control)
	control.free()
	ResourceSaver.save(packed, SCENE_2D)
	EditorInterface.open_scene_from_path(SCENE_2D)
	for i: int in 60:
		if EditorInterface.get_edited_scene_root() is Control:
			break
		await process_frame
	_check("2D scene is open", EditorInterface.get_edited_scene_root() is Control)
	_check("placing into a 2D scene is refused", not _placer.call("start", CRATE) and not _placer.call("is_placing"))
	DirAccess.remove_absolute(SCENE_2D)


func _near(a: Vector3, b: Vector3) -> bool:
	return a.distance_to(b) < 0.01


## Hit modes against meshes without colliders and colliders without meshes,
## and align to normal on the ramp and the wall.
func _surface_checks(level: Node3D) -> void:
	var settings: Variant = _placer.get("settings")
	EditorInterface.get_selection().clear()
	_placer.call("start", CRATE)
	var ghost: Node3D = _placer.call("ghost")

	# MeshOnlyPlinth's top is at y=1 and has no collider.
	var centre := _look_down_at(Vector3(-4.0, 0.0, 3.0))
	settings.set("hit_mode", 0)
	_motion(centre)
	_check("colliders mode passes through a mesh-only plinth", _near(ghost.global_position, Vector3(-4.0, 0.0, 3.0)), ghost.global_position)
	settings.set("hit_mode", 1)
	_motion(centre)
	_check("meshes mode lands on the plinth", _near(ghost.global_position, Vector3(-4.0, 1.0, 3.0)), ghost.global_position)
	settings.set("hit_mode", 2)
	_motion(centre)
	_check("both mode lands on the plinth", _near(ghost.global_position, Vector3(-4.0, 1.0, 3.0)), ghost.global_position)

	# A collider with no mesh, 3 m up: only the collider modes see it.
	var blocker := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 0.2, 2.0)
	shape.shape = box
	blocker.add_child(shape)
	level.add_child(blocker)
	blocker.global_position = Vector3(6.0, 3.0, -6.0)
	await physics_frame
	centre = _look_down_at(Vector3(6.0, 0.0, -6.0))
	_motion(centre)
	_check("both mode lands on a mesh-less collider", _near(ghost.global_position, Vector3(6.0, 3.1, -6.0)), ghost.global_position)
	settings.set("hit_mode", 1)
	_motion(centre)
	_check("meshes mode ignores a mesh-less collider", _near(ghost.global_position, Vector3(6.0, 0.0, -6.0)), ghost.global_position)
	blocker.free()

	# The ramp is tilted 20 degrees about X; align on, then off.
	var ramp_normal := Vector3(0.0, cos(deg_to_rad(20.0)), sin(deg_to_rad(20.0)))
	settings.set("align_to_normal", true)
	centre = _look_down_at(Vector3(5.0, 0.0, 0.0))
	for mode: int in [0, 1]:
		settings.set("hit_mode", mode)
		_motion(centre)
		var up := ghost.global_basis.y
		_check("ramp hit aligns the ghost (mode %d)" % mode, up.dot(ramp_normal) > 0.999 and absf(ghost.global_position.y - 1.106) < 0.01,
				[up, ghost.global_position])
	settings.set("hit_mode", 2)
	_click(centre)
	var on_ramp := level.get_child(level.get_child_count() - 1) as Node3D
	_check("placed crate keeps the ramp tilt", on_ramp.global_basis.y.dot(ramp_normal) > 0.999 and on_ramp.global_basis.is_conformal(),
			on_ramp.global_basis)
	_check("aligned crate is orthonormal", is_equal_approx(on_ramp.global_basis.determinant(), 1.0), on_ramp.global_basis.determinant())
	settings.set("align_to_normal", false)
	_motion(centre)
	_check("align off keeps the ghost upright", ghost.global_basis.is_equal_approx(Basis.IDENTITY), ghost.global_basis)

	# The wall's front face points +Z at z=-4.85; look at it head-on.
	settings.set("align_to_normal", true)
	settings.set("hit_mode", 1)
	_camera.global_transform = Transform3D(Basis.IDENTITY, Vector3(-4.0, 1.5, 5.0))
	_motion(_camera.get_viewport().get_visible_rect().size / 2.0)
	_check("wall hit by mesh", _near(ghost.global_position, Vector3(-4.0, 1.5, -4.85)), ghost.global_position)
	_check("wall hit aligns up to the wall normal", ghost.global_basis.y.dot(Vector3.BACK) > 0.999, ghost.global_basis.y)

	var ceiling: Basis = _placer.call("surface_basis", Vector3.DOWN)
	_check("ceiling basis flips up to down", ceiling.y.dot(Vector3.DOWN) > 0.999 and is_equal_approx(ceiling.determinant(), 1.0), ceiling)

	settings.set("align_to_normal", false)
	settings.set("hit_mode", 2)
	_placer.call("stop")


func _key(keycode: Key, shift: bool = false, alt: bool = false) -> InputEventKey:
	var key := InputEventKey.new()
	key.keycode = keycode
	key.shift_pressed = shift
	key.alt_pressed = alt
	key.pressed = true
	return key


func _wheel(button_index: MouseButton, screen: Vector2, alt: bool, shift: bool = false) -> int:
	var wheel := InputEventMouseButton.new()
	wheel.button_index = button_index
	wheel.position = screen
	wheel.alt_pressed = alt
	wheel.shift_pressed = shift
	wheel.pressed = true
	return _placer.call("forward_input", _camera, wheel)


func _yaw_is(basis: Basis, degrees: float) -> bool:
	return basis.orthonormalized().is_equal_approx(Basis(Vector3.UP, deg_to_rad(degrees)))


## Turn and tip keys, Alt+wheel, random yaw and scale, and grid snap.
func _transform_checks(level: Node3D) -> void:
	var settings: Variant = _placer.get("settings")
	var editor_settings := EditorInterface.get_editor_settings()
	_check("shortcuts registered", editor_settings.has_shortcut("asset_drawer/turn_left")
			and editor_settings.has_shortcut("asset_drawer/reset_rotation"))
	EditorInterface.get_selection().clear()
	_placer.call("start", CRATE)
	var ghost: Node3D = _placer.call("ghost")
	var centre := _look_down_at(Vector3(-7.0, 0.0, 7.0))
	_motion(centre)

	# Keys.
	_check("R is used", _placer.call("handle_key", _key(KEY_R)))
	_check("R turns 90 left", _yaw_is(ghost.global_basis, 90.0), ghost.global_basis)
	_placer.call("handle_key", _key(KEY_R, true))
	_placer.call("handle_key", _key(KEY_R, true))
	_check("Shift+R turns right", _yaw_is(ghost.global_basis, -90.0), ghost.global_basis)
	_placer.call("handle_key", _key(KEY_R, false, true))
	_check("Alt+R resets", ghost.global_basis.is_equal_approx(Basis.IDENTITY), ghost.global_basis)
	_placer.call("handle_key", _key(KEY_T))
	_check("T tips forward onto Z", ghost.global_basis.y.dot(Vector3.BACK) > 0.999, ghost.global_basis.y)
	_placer.call("handle_key", _key(KEY_T))
	_check("T twice flips upside down", ghost.global_basis.y.dot(Vector3.DOWN) > 0.999, ghost.global_basis.y)
	_placer.call("handle_key", _key(KEY_R, false, true))
	_placer.call("handle_key", _key(KEY_T, true))
	_check("Shift+T tips sideways", absf(ghost.global_basis.y.dot(Vector3.UP)) < 0.001 and absf(ghost.global_basis.y.z) < 0.001,
			ghost.global_basis.y)
	_placer.call("handle_key", _key(KEY_R, false, true))
	_check("unbound key passes through", not _placer.call("handle_key", _key(KEY_W))
			and _placer.call("forward_input", _camera, _key(KEY_W)) == EditorPlugin.AFTER_GUI_INPUT_PASS)

	# Alt+wheel spins; a plain wheel still zooms.
	_check("alt+wheel is eaten", _wheel(MOUSE_BUTTON_WHEEL_UP, centre, true) == EditorPlugin.AFTER_GUI_INPUT_STOP)
	_check("alt+wheel turns 15", _yaw_is(ghost.global_basis, 15.0), ghost.global_basis)
	_wheel(MOUSE_BUTTON_WHEEL_RIGHT, centre, true, true)
	_check("alt+shift+wheel turns back 5", _yaw_is(ghost.global_basis, 10.0), ghost.global_basis)
	_check("plain wheel passes through", _wheel(MOUSE_BUTTON_WHEEL_UP, centre, false) == EditorPlugin.AFTER_GUI_INPUT_PASS)
	_placer.call("handle_key", _key(KEY_R, false, true))

	# Random: each click places exactly what the ghost showed, then re-rolls.
	settings.set("random_enabled", true)
	settings.set("random_scale_min", 0.5)
	settings.set("random_scale_max", 2.0)
	_placer.call("start", CRATE)
	ghost = _placer.call("ghost")
	_motion(centre)
	var shown: Array[Transform3D] = []
	var all_match := true
	var all_in_range := true
	for i: int in 5:
		var before := ghost.global_transform
		shown.append(before)
		_click(centre)
		var placed := level.get_child(level.get_child_count() - 1) as Node3D
		all_match = all_match and placed.global_transform.is_equal_approx(before)
		var scale := before.basis.get_scale().x
		all_in_range = all_in_range and scale >= 0.5 - 0.001 and scale <= 2.0 + 0.001
	_check("random copies match the ghost", all_match)
	var shown_before := ghost.global_transform
	_check("D re-rolls while random is on", _placer.call("handle_key", _key(KEY_D)) and not ghost.global_transform.basis.is_equal_approx(shown_before.basis),
			[shown_before.basis, ghost.global_transform.basis])
	settings.set("random_enabled", false)
	_check("D passes through with random off", not _placer.call("handle_key", _key(KEY_D)))
	settings.set("random_enabled", true)
	_check("random scale in range", all_in_range, shown)
	_check("each click re-rolls", not shown[0].basis.is_equal_approx(shown[1].basis) and not shown[1].basis.is_equal_approx(shown[2].basis))
	var top := level.get_child(level.get_child_count() - 1) as Node3D
	var top_height := (top.global_basis * Vector3.UP).length()
	_check("ghost moves onto the copy just placed", ghost.global_position.y > top.global_position.y + top_height * 0.5,
			[ghost.global_position, top.global_position])
	settings.set("random_enabled", false)
	settings.set("random_scale_min", 0.9)
	settings.set("random_scale_max", 1.1)

	# Snap.
	settings.set("snap_enabled", true)
	settings.set("snap_step", 1.0)
	_motion(_look_down_at(Vector3(8.3, 0.0, 7.6)))
	_check("snap rounds on the floor", _near(ghost.global_position, Vector3(8.0, 0.0, 8.0)), ghost.global_position)
	settings.set("snap_step", 0.5)
	_motion(_look_down_at(Vector3(8.3, 0.0, 7.6)))
	_check("snap step follows the setting", _near(ghost.global_position, Vector3(8.5, 0.0, 7.5)), ghost.global_position)
	var on_wall: Vector3 = _placer.call("snap_to_surface", Vector3(1.4, 2.6, -4.85), Vector3.BACK, 1.0)
	_check("snap on a wall keeps its depth", _near(on_wall, Vector3(1.0, 3.0, -4.85)), on_wall)
	var slope := Vector3(0.0, cos(deg_to_rad(20.0)), sin(deg_to_rad(20.0)))
	var hit := Vector3(5.3, 1.2, 0.4)
	var on_slope: Vector3 = _placer.call("snap_to_surface", hit, slope, 1.0)
	_check("snap on a slope stays on its plane", absf((on_slope - hit).dot(slope)) < 0.001, on_slope)
	settings.set("snap_enabled", false)
	settings.set("snap_step", 1.0)
	_placer.call("stop")
