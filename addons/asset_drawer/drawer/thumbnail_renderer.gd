@tool
extends Node
## Renders asset thumbnails one at a time in an offscreen viewport: its own
## world with its own lights on a transparent background, and a
## three-quarter camera framed to the asset's visible bounds, so editor
## gizmos never show and every tile is framed the same way. An asset can be
## turned around Y first, for one whose front isn't +Z. Thumbnails are
## cached as PNGs in the project's .godot folder, keyed by the asset file's
## (and its .import file's) modified time and the turn, so they re-render
## when either changes.

signal thumbnail_ready(path: String, turn: int, texture: Texture2D)

const SIZE := 256
const FOV_DEGREES := 30.0
## The camera looks down from the front right.
const CAMERA_ANGLES := Vector3(deg_to_rad(-25.0), deg_to_rad(35.0), 0.0)
## Space left around the asset, as a fraction of the frame's half-width.
const MARGIN := 0.08

var _viewport: SubViewport
var _camera: Camera3D
var _stage: Node3D
var _cache_dir: String = ""
var _textures: Dictionary[String, Texture2D] = {}
## Waiting renders, each {"path": String, "turn": int}.
var _queue: Array[Dictionary] = []
var _busy: bool = false
## Off without a real display (a headless editor never draws a frame), or
## once a render comes back empty.
var _can_render: bool = DisplayServer.get_name() != "headless"


func _init() -> void:
	name = "AssetDrawerThumbnails"
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(SIZE, SIZE)
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)

	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.4, 0.42, 0.46)
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world := WorldEnvironment.new()
	world.environment = environment
	_viewport.add_child(world)

	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(30.0), 0.0)
	key.light_energy = 1.0
	key.shadow_enabled = true
	_viewport.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(deg_to_rad(-15.0), deg_to_rad(-140.0), 0.0)
	fill.light_energy = 0.3
	_viewport.add_child(fill)

	_camera = Camera3D.new()
	_camera.fov = FOV_DEGREES
	_camera.near = 0.01
	_camera.far = 10000.0
	_viewport.add_child(_camera)

	_stage = Node3D.new()
	_viewport.add_child(_stage)


func _ready() -> void:
	# Absolute, because Image.load_from_file warns about res:// paths.
	_cache_dir = ProjectSettings.globalize_path(
			EditorInterface.get_editor_paths().get_project_settings_dir().path_join("asset_drawer_thumbnails"))
	DirAccess.make_dir_recursive_absolute(_cache_dir)


func _exit_tree() -> void:
	# A render waiting on a frame holds an instance in the viewport; free it
	# now, or the renderer finds it still alive at shutdown.
	_queue.clear()
	for child: Node in _stage.get_children():
		_stage.remove_child(child)
		child.free()


## The thumbnail for the asset at [param path], turned [param turn] degrees,
## if it's rendered and current, loading it from the disk cache when needed;
## null otherwise.
func cached(path: String, turn: int = 0) -> Texture2D:
	var file := _cache_file(path, turn)
	if _textures.has(file):
		return _textures[file]
	if not FileAccess.file_exists(file):
		return null
	var image := Image.load_from_file(file)
	if image == null or image.is_empty():
		return null
	var texture := ImageTexture.create_from_image(image)
	_textures[file] = texture
	return texture


## Queues the asset at [param path], turned [param turn] degrees around Y,
## for rendering, unless it's cached or already queued.
## [signal thumbnail_ready] fires when it's done.
func request(path: String, turn: int = 0) -> void:
	var job := {"path": path, "turn": turn}
	if not _can_render or _queue.has(job) or cached(path, turn) != null:
		return
	_queue.append(job)
	if not _busy:
		_pump()


## Throws away the asset's cached thumbnail and renders it again.
func regenerate(path: String, turn: int = 0) -> void:
	var file := _cache_file(path, turn)
	_textures.erase(file)
	DirAccess.remove_absolute(file)
	request(path, turn)


func _pump() -> void:
	_busy = true
	while not _queue.is_empty() and is_inside_tree():
		var job: Dictionary = _queue.pop_front()
		var path: String = job["path"]
		var turn: int = job["turn"]
		var image := await _render(path, turn)
		if not is_inside_tree():
			break
		if image == null:
			continue
		_forget_older(path)
		var file := _cache_file(path, turn)
		image.save_png(file)
		var texture := ImageTexture.create_from_image(image)
		_textures[file] = texture
		thumbnail_ready.emit(path, turn, texture)
	_busy = false


func _render(path: String, turn: int) -> Image:
	var scene := ResourceLoader.load(path) as PackedScene
	if scene == null:
		return null
	var instance := scene.instantiate()
	if not instance is Node3D:
		instance.free()
		return null
	(instance as Node3D).rotate_y(deg_to_rad(turn))
	_strip(instance)
	_stage.add_child(instance)
	# Let CSG and other deferred geometry build before measuring it. Tool
	# scripts may have added editor signs by now too, so strip again.
	await get_tree().process_frame
	if not is_instance_valid(instance):
		return null
	_strip(instance)
	_frame(_visible_bounds(instance as Node3D))

	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var drawn_by := Engine.get_frames_drawn() + 2
	while Engine.get_frames_drawn() < drawn_by:
		# An idle editor only draws a frame when something has changed, and a
		# viewport set to update doesn't count. Re-setting the camera does.
		_camera.global_transform = _camera.global_transform
		await get_tree().process_frame
		if not is_instance_valid(instance):
			return null
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if not is_instance_valid(instance):
		return null
	var image := _viewport.get_texture().get_image()
	instance.queue_free()
	if image == null or image.is_empty():
		_can_render = false
		_queue.clear()
		return null
	return image


## Quiets what would take over the thumbnail or clutter it: cameras and
## environments inside the asset, and Label3D text, usually editor signs a
## tool script added (often as internal children). Nothing is freed, so
## those scripts can still reach their nodes.
func _strip(node: Node) -> void:
	for child: Node in node.get_children(true):
		if child is Label3D:
			(child as Label3D).visible = false
		elif child is Camera3D:
			(child as Camera3D).current = false
		elif child is WorldEnvironment:
			(child as WorldEnvironment).environment = null
			(child as WorldEnvironment).camera_attributes = null
		_strip(child)
	_camera.make_current()


## The combined world bounds of everything visible in [param root].
func _visible_bounds(root: Node3D) -> AABB:
	var bounds := AABB()
	var first := true
	for node: Node in [root] + root.find_children("*", "GeometryInstance3D", true, false):
		var geometry := node as GeometryInstance3D
		if geometry == null or not geometry.is_visible_in_tree():
			continue
		var box := geometry.global_transform * geometry.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	if first or bounds.size.length() < 0.001:
		return AABB(root.global_position - Vector3.ONE * 0.5, Vector3.ONE)
	return bounds


## Points the camera at [param bounds] from the thumbnail angle, just far
## enough back that all eight of its corners fit the square frame.
func _frame(bounds: AABB) -> void:
	var view := Basis.from_euler(CAMERA_ANGLES)
	var center := bounds.get_center()
	var tangent := tan(deg_to_rad(FOV_DEGREES / 2.0)) * (1.0 - MARGIN)
	var distance := 0.0
	for i: int in 8:
		# The corner relative to the centre, in the camera's axes; the camera
		# sits along +Z (back) and looks down -Z.
		var corner := view.inverse() * (bounds.get_endpoint(i) - center)
		var spread := maxf(absf(corner.x), absf(corner.y))
		distance = maxf(distance, corner.z + spread / tangent)
	_camera.global_transform = Transform3D(view, center + view * Vector3.BACK * distance)


## The PNG for the asset's current version: named after the asset, plus a
## hash of its modified times and turn so an edited or turned asset gets a
## new file.
func _cache_file(path: String, turn: int) -> String:
	var import_file := path + ".import"
	var imported := FileAccess.get_modified_time(import_file) if FileAccess.file_exists(import_file) else 0
	var stamp := "%s:%d:%d" % [path, FileAccess.get_modified_time(path), imported]
	# Unturned thumbnails keep the names they had before turns existed.
	if turn != 0:
		stamp += ":%d" % turn
	return _cache_dir.path_join("%s_%s.png" % [_asset_key(path), stamp.md5_text().left(10)])


func _asset_key(path: String) -> String:
	return ResourceUID.path_to_uid(path).md5_text()


## Deletes this asset's thumbnails from older versions of it.
func _forget_older(path: String) -> void:
	var prefix := _asset_key(path) + "_"
	for file: String in DirAccess.get_files_at(_cache_dir):
		if file.begins_with(prefix):
			DirAccess.remove_absolute(_cache_dir.path_join(file))
			_textures.erase(_cache_dir.path_join(file))
