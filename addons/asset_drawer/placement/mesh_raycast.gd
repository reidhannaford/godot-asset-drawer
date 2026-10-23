@tool
extends RefCounted
## Ray hits against the visible meshes under a scene root, so placement can
## land on geometry that has no colliders. Each MeshInstance3D is ruled out
## by its world AABB before its triangles are tested, and each mesh's
## triangles are built once and cached.
##
## Only MeshInstance3D counts: CSG, MultiMesh and GridMap geometry is
## skipped, and skinned meshes are tested in their rest pose.

var _root: Node
var _instances: Array[MeshInstance3D] = []
var _instances_dirty: bool = true
var _triangles: Dictionary[Mesh, TriangleMesh] = {}


func _init(root: Node) -> void:
	_root = root
	var tree := root.get_tree()
	tree.node_added.connect(_on_tree_changed)
	tree.node_removed.connect(_on_tree_changed)


## The nearest mesh hit on the segment [param from] → [param to] as
## {position, normal} in world space, or an empty dictionary on a miss. The
## normal always faces back toward [param from], even on a back face.
func cast(from: Vector3, to: Vector3) -> Dictionary:
	var direction := to - from
	var nearest := {}
	var nearest_distance := INF
	for instance: MeshInstance3D in _gather():
		var mesh := instance.mesh
		if mesh == null or not instance.is_visible_in_tree():
			continue
		var xform := instance.global_transform
		if is_zero_approx(xform.basis.determinant()) \
				or (xform * mesh.get_aabb()).intersects_segment(from, to) == null:
			continue
		var triangles := _triangles_of(mesh)
		if triangles == null:
			continue
		var local := xform.affine_inverse()
		var hit := triangles.intersect_ray(local * from, local.basis * direction)
		if hit.is_empty():
			continue
		var position := xform * (hit["position"] as Vector3)
		var distance := from.distance_squared_to(position)
		if distance >= nearest_distance:
			continue
		var normal := (xform.basis.inverse().transposed() * (hit["normal"] as Vector3)).normalized()
		if normal.dot(direction) > 0.0:
			normal = -normal
		nearest = {"position": position, "normal": normal}
		nearest_distance = distance
	return nearest


func _gather() -> Array[MeshInstance3D]:
	if _instances_dirty:
		_instances.assign(_root.find_children("*", "MeshInstance3D", true, false))
		_instances_dirty = false
	return _instances


func _triangles_of(mesh: Mesh) -> TriangleMesh:
	if not _triangles.has(mesh):
		_triangles[mesh] = mesh.generate_triangle_mesh()
	return _triangles[mesh]


func _on_tree_changed(node: Node) -> void:
	if is_instance_valid(_root) and _root.is_ancestor_of(node):
		_instances_dirty = true
