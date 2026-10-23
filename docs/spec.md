# Asset Drawer spec

A lightweight Godot 4.7+ editor addon: a drawer of curated asset libraries, and a placement mode that stamps the picked asset into the open 3D scene. Pure GDScript, editor-only.

It is a deliberately small take on [AssetPlacer](https://cookiebadger.itch.io/assetplacer). Everything below came out of a feature interview on 2026-10-23.

## In scope

### Libraries

- A library is an `AssetDrawerLibrary` resource saved as `.tres` anywhere in the project, holding an ordered list of `AssetDrawerEntry` sub-resources. Its file name is its display name, so renaming the file in the FileSystem dock renames the library. Each entry has room for per-asset settings later.
- Assets are stored by `uid://`, so moving files doesn't break a library, and opening one doesn't load every model. A uid that no longer resolves shows as a broken tile with its last known path, rather than disappearing silently. A file with no uid (a hand-written `.tscn`) is stored by path, and switched to its uid once it has one.
- Accepted types: anything the editor imports as a `PackedScene`. That means scenes (`.tscn`/`.scn`) and models (`.glb`/`.gltf`), plus `.fbx`/`.blend` at no extra cost. Anything else dropped on the drawer is rejected with a warning. Dropping a folder adds every scene inside it, recursively.
- The drawer toolbar has a library switcher (dropdown) plus new / open / close library actions. The set of open libraries and the active one are remembered per project with `EditorSettings.set_project_metadata`.
- Add assets by dragging files from the FileSystem dock onto the grid, at the drop marker. Dropping an asset that's already in the library moves it instead of duplicating it. Remove assets with Delete or the tile's context menu, and reorder them by dragging tiles (multi-select works). A tile dragged out of the drawer looks like a FileSystem drag, so the 3D viewport and Scene dock will instance it.
- A text filter over asset names. It's cheap, and libraries grow.

### Drawer

- An `EditorDock` that defaults to the bottom panel and can be moved to a side dock or floated (`DOCK_LAYOUT_ALL`).
- A thumbnail grid that uses Godot's built-in previewer (`EditorInterface.get_resource_previewer()`). Thumbnail size is adjustable with a slider and remembered.
- The previewer only has file thumbnails for scenes saved in the editor, and none at all for imported models; this was checked in 4.7.2. When a file has no thumbnail, the drawer previews the largest mesh the scene uses directly. Meshes inside instanced sub-scenes aren't searched. The previewer renders at 64 px, so large thumbnail sizes look soft.
- Custom-rendered previews are out of scope for now, but the tile should get its texture from one function so a custom renderer can be swapped in later.

### Placement

- Click a tile to enter placement mode with that asset; the tile is tinted while it's armed. Click it again, or press Esc in the viewport or the drawer, to leave. Shift- and Cmd/Ctrl-clicks only change the selection. Removing the armed asset, closing its library, or switching scene tabs also ends placement. Right-click is left alone, because the 3D viewport uses it for freelook.
- While placing, a see-through, shadowless ghost of the asset follows the cursor. Each left click stamps one copy, and you stay in placement mode. Left clicks are always eaten while placing, even on a miss, so they never change the selection. Alt+left-click passes through for the viewport's own use. The plugin gets viewport input through `set_input_event_forwarding_always_enabled()`.
- The ghost isn't part of the edited scene: it's a sibling of the scene root inside the editor's scene viewport, so it shares the scene's world but never shows in the Scene dock and is never saved. Its collision objects are taken off every layer, so the placement raycasts never hit it. Placed props are hit, so you can stack them.
- Placed nodes go under the node that was selected when placement started, or under the scene root if nothing was selected. A selection inside an instanced scene (a crate placed a moment ago, or one of its children) defers to the nearest ancestor that belongs to the edited scene itself. Nodes are added as scene instances with readable unique names (`Crate2`) and the edited scene root as owner. The selection isn't changed, so repeated clicks keep filling the same parent.
- Every placement is one `EditorUndoRedoManager` action ("Place Crate").

### Surface hits

- **Colliders:** a raycast through `PhysicsDirectSpaceState3D` of the edited scene's world.
- **Visible meshes:** a ray-vs-triangle test against `MeshInstance3D`s in the edited scene. Rule out each instance by its global AABB first, then run `TriangleMesh.intersect_ray` in mesh-local space, caching `Mesh.generate_triangle_mesh()` per mesh. This lets you place on geometry that has no colliders.
- A hit mode dropdown offers Colliders / Meshes / Both. The default is Both, and the nearest hit wins.
- When nothing is hit, the ghost hides and clicks do nothing. There is no fallback plane.
- Until align to normal lands, the asset's origin goes exactly at the hit point with no rotation, so a hit on a wall leaves the asset half inside it.
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

1. **Libraries and drawer** (done 2026-10-23): the library resource, the dock grid with previews, drag-in from the FileSystem, remove and reorder, the switcher, the filter, remembered open libraries.
2. **Stamping on colliders** (done 2026-10-23): placement mode, the ghost, the physics raycast, click to place, undo, parenting.
3. **Mesh hits and align to normal.**
4. **Transform helpers:** rotate and flip shortcuts, scroll to rotate, random rotation and scale, grid snap.
5. **Real-project adoption:** sync the addon into a game project with `tools/sync_to.sh` and build the first prop libraries.

## Testing

`test/test_level.tscn` has a floor, a 20° ramp, a wall and `MeshOnlyPlinth` (a mesh with no collider, for the mesh hit-test). `test/props/` holds three `.tscn` props and a `.glb`. `tools/run_tests.sh` runs `test/drawer_test.gd` headlessly in two passes: libraries, drops, reordering, the filter, restoring from metadata, and moved or missing assets. It then runs `test/placement_test.gd`, which feeds synthetic mouse and key events to the placer through a top-down camera: hovering, clicking, stacking, misses, undo and redo, parenting, Esc, and arming tiles. The project uses Jolt (the 4.6+ default); the placement test also passed under Godot Physics on 2026-10-23. A windowed editor run that sends events with `Input.parse_input_event` confirmed the plugin really receives viewport input.
