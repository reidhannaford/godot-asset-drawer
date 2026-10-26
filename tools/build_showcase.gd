extends SceneTree
## Builds the README showcase from the Kenney Prototype Kit in showcase/:
## a small level (showcase/showcase_level.tscn) and a library with folders
## (showcase/prototype_kit.tres). Run it in a headless editor so the models
## have uids:
##   HOME=<scratch> godot --headless --editor --path . -s res://tools/build_showcase.gd

const KIT := "res://showcase/kenney_prototype_kit/"
const LEVEL := "res://showcase/showcase_level.tscn"
const LIBRARY := "res://showcase/prototype_kit.tres"

## Library folders, in drawer order. Models not listed go in the root.
const FOLDERS: Dictionary[String, Array] = {
	"Structures": ["wall", "wall-window-medium", "wall-doorway", "wall-low", "wall-corner", "wall-round",
			"column", "column-rounded", "floor-thick", "floor-square", "stairs", "stairs-small", "shape-slope"],
	"Props": ["crate", "crate-color", "flag", "target-a-round", "weapon-sword", "coin", "ladder", "door-rotate",
			"lever-single", "button-floor-square", "pipe", "pipe-corner", "weapon-shield", "hat-cap"],
	"Shapes": ["shape-cube", "shape-cylinder", "shape-hexagon", "shape-hollow-cylinder"],
	"Characters": ["figurine", "figurine-large", "figurine-cube", "animal-dog", "animal-horse", "animal-bison",
			"vehicle", "vehicle-convertible"],
	"Markers": ["indicator-round-a", "indicator-square-a", "indicator-special-arrow", "indicator-special-cross",
			"number-1", "number-2", "number-3"],
}

var _frame := 0
var _root: Node3D


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 30:
		_build_library()
		_build_level()
		quit()
	return false


func _build_library() -> void:
	var library := AssetDrawerLibrary.new()
	for folder_name: String in FOLDERS:
		var folder := library.add_folder(library, folder_name)
		var entries: Array[AssetDrawerEntry] = []
		for model: String in FOLDERS[folder_name]:
			entries.append(AssetDrawerEntry.from_path(KIT + model + ".glb"))
		library.move_entries(entries, folder, null)
	print("library: ", ResourceSaver.save(library, LIBRARY))


func _build_level() -> void:
	_root = Node3D.new()
	_root.name = "ShowcaseLevel"

	var environment := Environment.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.42, 0.55, 0.78)
	sky_material.sky_horizon_color = Color(0.78, 0.8, 0.86)
	sky_material.ground_horizon_color = Color(0.78, 0.8, 0.86)
	sky_material.ground_bottom_color = Color(0.35, 0.36, 0.42)
	var sky := Sky.new()
	sky.sky_material = sky_material
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.9
	environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	environment.ssao_enabled = true
	environment.ssao_radius = 0.6
	environment.ssao_intensity = 1.6
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.78, 0.8, 0.86)
	environment.fog_density = 0.012
	environment.fog_sky_affect = 0.0
	var world := WorldEnvironment.new()
	world.name = "WorldEnvironment"
	world.environment = environment
	_add(world, _root)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation = Vector3(deg_to_rad(-48.0), deg_to_rad(-35.0), 0.0)
	# Behind the capture camera, so its gizmo stays out of shot.
	sun.position = Vector3(10.0, 8.0, 14.0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	_add(sun, _root)

	# A ground with a collider, in the kit's pale lavender.
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	_add(ground, _root)
	var ground_mesh := MeshInstance3D.new()
	ground_mesh.name = "Mesh"
	var plane := PlaneMesh.new()
	plane.size = Vector2(60.0, 60.0)
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color(0.62, 0.62, 0.74)
	ground_material.roughness = 1.0
	plane.material = ground_material
	ground_mesh.mesh = plane
	_add(ground_mesh, ground)
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var box := BoxShape3D.new()
	box.size = Vector3(60.0, 1.0, 60.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	_add(shape, ground)

	var course := Node3D.new()
	course.name = "Course"
	_add(course, _root)
	var along_x := deg_to_rad(90.0)

	# Back wall along z = -4, x -4..3, with a window and a doorway.
	var back := ["wall", "wall-window-medium", "wall", "wall-doorway", "wall", "wall-window-medium", "wall", "wall"]
	for i: int in back.size():
		_piece(course, back[i], Vector3(-3.5 + i, 0.0, -4.0), along_x)
	_piece(course, "column", Vector3(-4.0, 0.0, -4.0))
	_piece(course, "column", Vector3(4.0, 0.0, -4.0))
	# A low wall down the left side.
	for i: int in 4:
		_piece(course, "wall-low", Vector3(-4.0, 0.0, -3.5 + i))
	_piece(course, "column-rounded", Vector3(-4.0, 0.0, 0.0))

	# A raised platform at the back left, stairs up its front.
	for x: int in 3:
		for z: int in 2:
			_piece(course, "shape-cube", Vector3(-3.0 + x, 0.0, -3.0 + z))
	_piece(course, "stairs", Vector3(-3.0, 0.0, -1.0), PI)

	# Shapes on the right, and a ramp out in the open for aligned copies.
	_piece(course, "shape-slope", Vector3(1.6, 0.0, -0.4), -PI / 2.0, 1.5)
	_piece(course, "shape-hollow-cylinder", Vector3(3.0, 0.0, -2.5))
	_piece(course, "shape-hexagon", Vector3(3.2, 0.0, -1.2), 0.3)
	_piece(course, "wall-round", Vector3(3.5, 0.0, 1.0), -PI / 2.0)
	_piece(course, "floor-square", Vector3(0.0, 0.01, 1.0))
	_piece(course, "floor-square", Vector3(1.0, 0.01, 1.0))
	_piece(course, "floor-square", Vector3(0.0, 0.01, 2.0))
	_piece(course, "floor-square", Vector3(1.0, 0.01, 2.0))
	_piece(course, "indicator-special-arrow", Vector3(-1.5, 0.02, 1.5))
	_piece(course, "flag", Vector3(1.8, 0.0, -3.2))
	_piece(course, "figurine", Vector3(-2.0, 1.0, -3.0), 0.4)
	_piece(course, "crate", Vector3(-3.1, 1.0, -3.1))
	_piece(course, "vehicle", Vector3(2.2, 0.0, 3.0), -0.6)

	var placed := Node3D.new()
	placed.name = "Placed"
	_add(placed, _root)

	var packed := PackedScene.new()
	print("pack: ", packed.pack(_root))
	print("level: ", ResourceSaver.save(packed, LEVEL))
	_root.free()


func _piece(parent: Node3D, model: String, at: Vector3, yaw: float = 0.0, size: float = 1.0) -> void:
	var instance := (load(KIT + model + ".glb") as PackedScene).instantiate() as Node3D
	instance.position = at
	instance.rotation.y = yaw
	instance.scale = Vector3.ONE * size
	parent.add_child(instance, true)
	instance.owner = _root


func _add(node: Node, parent: Node) -> void:
	parent.add_child(node, true)
	node.owner = _root
