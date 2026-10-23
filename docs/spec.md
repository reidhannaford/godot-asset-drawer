# Asset Drawer spec

A lightweight Godot 4.7+ editor addon: a drawer of curated asset libraries, and a placement mode that stamps the picked asset into the open 3D scene. Pure GDScript, editor-only.

It is a deliberately small take on [AssetPlacer](https://cookiebadger.itch.io/assetplacer). Everything below came out of a feature interview on 2026-10-23.

## In scope

### Libraries

- A library is an `AssetDrawerLibrary` resource saved as `.tres` anywhere in the project. It holds a display name and an ordered list of assets.
- Assets are stored by `uid://`, so moving files doesn't break a library, and opening one doesn't load every model. A uid that no longer resolves shows as a broken tile with its last known path, rather than disappearing silently.
- Accepted types: scenes (`.tscn`/`.scn`) and imported models (`.glb`/`.gltf`), all of which load as `PackedScene`. Anything else dropped on the drawer is rejected with a warning.
- The drawer toolbar has a library switcher (dropdown) plus new / open / close library actions. The set of open libraries and the active one are remembered per project with `EditorSettings.set_project_metadata`.
- Add assets by dragging files from the FileSystem dock onto the grid. Remove them from the tile's context menu, and reorder by dragging tiles.
- A text filter over asset names. It's cheap, and libraries grow.

### Drawer

- An `EditorDock` that defaults to the bottom panel and can be moved to a side dock or floated (`DOCK_LAYOUT_ALL`).
- A thumbnail grid that uses Godot's built-in previews (`EditorInterface.get_resource_previewer()`), the same images the FileSystem dock shows. Thumbnail size is adjustable with a slider.
- Custom-rendered previews are out of scope for now, but the tile should get its texture from one function so a custom renderer can be swapped in later.

### Placement

- Click a tile to enter placement mode with that asset. Click it again, or press Esc, to leave. Right-click is left alone, because the 3D viewport uses it for freelook.
- While placing, a ghost instance of the asset follows the cursor. Each left click stamps one copy, and you stay in placement mode.
- The ghost isn't part of the edited scene: it has no owner, it never shows in the Scene dock, and it's never saved. Its collision objects are disabled, so the placement raycasts never hit it.
- Placed nodes go under the node that was selected when placement started, or under the scene root if nothing was selected. They are added with readable unique names and the edited scene root as owner, and the selection isn't changed, so repeated clicks keep filling the same parent.
- Every placement is one `EditorUndoRedoManager` action ("Place Crate").

### Surface hits

- **Colliders:** a raycast through `PhysicsDirectSpaceState3D` of the edited scene's world.
- **Visible meshes:** a ray-vs-triangle test against `MeshInstance3D`s in the edited scene. Rule out each instance by its global AABB first, then run `TriangleMesh.intersect_ray` in mesh-local space, caching `Mesh.generate_triangle_mesh()` per mesh. This lets you place on geometry that has no colliders.
- A hit mode dropdown offers Colliders / Meshes / Both. The default is Both, and the nearest hit wins.
- When nothing is hit, the ghost hides and clicks do nothing. There is no fallback plane.
- **Align to normal** is a toggle: the asset's up axis follows the surface normal, and yaw is applied around that normal.

### Transform helpers

- **Rotate / flip shortcuts** while placing: 90° steps around the vertical axis, plus 90° tips around X and Z. The bindings are `Shortcut`s in Editor Settings under `asset_drawer/`, so they can be rebound.
- **Scroll to rotate:** a modifier plus the mouse wheel rotates the ghost's yaw in 15° steps (finer with Shift). The modifier must not clash with the viewport's own wheel zoom.
- **Random rotation / scale:** toggles with ranges in the drawer toolbar, such as yaw 0–360° and uniform scale 0.9–1.1. The roll happens after each placement, so the ghost always shows exactly what the next click will place.
- **Grid snapping:** a toggle plus a step size in the drawer toolbar. It snaps the hit point's position (on the plane the surface defines, when aligning to normals). Reading Godot's own Node3D snap settings would be nicer, but that isn't public API; check before relying on it.

### Settings and shortcuts

Per-user settings, such as the shortcuts and the last-used toolbar values, live in Editor Settings or project metadata. Nothing is written to `project.godot`.

## Out of scope (for now)

- Placement planes, Terrain3D support
- Paint or scatter strokes
- Custom-rendered thumbnails, 3D previews, an "asset zoo" scene
- Tags, nested folders inside a library
- `.fbx`, `.obj`, `.dae`, bare `Mesh` resources
- 2D placement, C#

## Open questions

- **Flip semantics:** a true mirror needs a negative scale, which breaks colliders (Jolt rejects it) and lighting. The plan is to make "flip" a 180° turn, and the X/Z tips 90° turns. Confirm once it's in use.
- **Per-asset overrides:** some assets want their own random range or their own align-to-normal setting (rocks yes, crates no). Leave room in the library's per-entry data, but don't build it until it's needed.
- **Mesh hit cost:** in large scenes, gathering every `MeshInstance3D` on each mouse move may need a cache that `SceneTree.node_added`/`node_removed` keeps up to date.

## Milestones

1. **Libraries and drawer:** the library resource, the dock grid with previews, drag-in from the FileSystem, remove and reorder, the switcher, the filter, remembered open libraries.
2. **Stamping on colliders:** placement mode, the ghost, the physics raycast, click to place, undo, parenting.
3. **Mesh hits and align to normal.**
4. **Transform helpers:** rotate and flip shortcuts, scroll to rotate, random rotation and scale, grid snap.
5. **Real-project adoption:** sync the addon into a game project with `tools/sync_to.sh` and build the first prop libraries.

## Testing

`test/test_level.tscn` has a floor, a 20° ramp, a wall and `MeshOnlyPlinth` (a mesh with no collider, for the mesh hit-test). `test/props/` holds three `.tscn` props and a `.glb`. Script-level checks run headlessly with `godot --headless --editor --path . -s <script>`. Viewport interaction needs a real editor session.
