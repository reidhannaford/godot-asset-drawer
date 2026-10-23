# Asset Drawer spec

A lightweight Godot 4.7+ editor addon: a drawer of curated asset libraries, and a placement mode that stamps the picked asset into the open 3D scene. Pure GDScript, editor-only.

It is a deliberately small take on [AssetPlacer](https://cookiebadger.itch.io/assetplacer). Everything below came out of a feature interview on 2026-10-23.

## In scope

### Libraries

- A library is an `AssetDrawerLibrary` resource saved as `.tres` anywhere in the project. Its file name is its display name, so renaming the file in the FileSystem dock renames the library.
- **Folders (added 2026-10-23):** a library is itself an `AssetDrawerFolder`, its root, and folders nest. Each folder holds an ordered list of `AssetDrawerEntry` sub-resources and an ordered list of subfolders. Every asset lives in exactly one folder of its library, and assets filed nowhere in particular sit at the root. Libraries saved before folders existed load unchanged, with all their assets at the root. A game might have one library with Enemies, NPCs, Pick-ups › Items / Throwables, Level and so on. Each entry has room for per-asset settings later.
- Assets are stored by `uid://`, so moving files doesn't break a library, and opening one doesn't load every model. A uid that no longer resolves shows as a broken tile with its last known path, rather than disappearing silently. A file with no uid (a hand-written `.tscn`) is stored by path, and switched to its uid once it has one.
- Accepted types: anything the editor imports as a `PackedScene`. That means scenes (`.tscn`/`.scn`) and models (`.glb`/`.gltf`), plus `.fbx`/`.blend` at no extra cost. Anything else dropped on the drawer is rejected with a warning. Dropping a folder adds every scene inside it, recursively.
- The drawer toolbar has a library switcher (dropdown) plus new / open / close library actions. The set of open libraries and the active one are remembered per project with `EditorSettings.set_project_metadata`.
- Add assets by dragging files from the FileSystem dock onto a grid (at the drop marker) or onto a folder in the tree. Dropping an asset that's already in the library moves it into that folder instead of duplicating it. If the editor is mid-rescan, as it is right after new models import, the drop waits for the scan to finish; file types read as unknown until then. Remove assets with Delete or the tile's context menu, and reorder them by dragging tiles (multi-select works). A tile dragged onto another section's grid, or onto a tree folder, moves it to that folder. A tile dragged out of the drawer looks like a FileSystem drag, so the 3D viewport and Scene dock will instance it.
- Folder actions are in the tree: right-click for New Folder, Rename and Delete Folder. There's also a new-folder button in the toolbar, F2 renames, and Delete deletes. Deleting a folder keeps its contents: its assets join the end of its parent's, and its subfolders take its place. Folders drag to reorder (drop above or below a sibling) or to nest (drop on a folder). A folder can't be dropped into itself or below itself. Collapsed folders stay collapsed for the session.
- A text filter over asset names, across the selected folder and everything below it. It's cheap, and libraries grow.

### Drawer

- An `EditorDock` that defaults to the bottom panel and can be moved to a side dock or floated (`DOCK_LAYOUT_ALL`).
- **Layout:** one toolbar row (library switcher, new / open / close library, new folder, filter, thumbnail size) over the folder tree and the sections view, side by side. The placement options and the key hint appear on a second row only while placing, so the idle drawer stays one row. Toolbar controls keep their own height; an earlier nested flow layout stretched them to three rows. Fixed sizes are multiplied by `EditorInterface.get_editor_scale()`, so they hold up on Retina.
- **Sections view:** the selected folder's own assets come first, then a headed section ("Pick-ups / Items") for each subfolder with any assets, depth first. So the root, or any parent folder, works as an overview. An empty parent with filled subfolders shows only the sections. Each section is its own grid that grows to fit its tiles, and the view around them scrolls. The grids pass the mouse wheel and trackpad pan up to the scroll view, because an ItemList otherwise swallows them. A plain click selects in one grid at a time.
- A thumbnail grid that uses Godot's built-in previewer (`EditorInterface.get_resource_previewer()`). Thumbnail size is adjustable with a slider and remembered.
- The previewer only has file thumbnails for scenes saved in the editor, and none at all for imported models; this was checked in 4.7.2. When a file has no thumbnail, the drawer previews the largest mesh the scene uses directly. Meshes inside instanced sub-scenes aren't searched. The previewer renders at 64 px, so large thumbnail sizes look soft.
- Custom-rendered previews are out of scope for now, but the tile should get its texture from one function so a custom renderer can be swapped in later.

### Placement

- Click a tile to enter placement mode with that asset; the tile is tinted while it's armed. Click it again, or press Esc in the viewport or the drawer, to leave. Shift- and Cmd/Ctrl-clicks only change the selection. Removing the armed asset, closing its library, or switching scene tabs also ends placement. Right-click is left alone, because the 3D viewport uses it for freelook.
- While placing, a see-through, shadowless ghost of the asset follows the cursor. Each left click stamps one copy, and you stay in placement mode. Left clicks are always eaten while placing, even on a miss, so they never change the selection. Alt+left-click passes through for the viewport's own use. The plugin gets viewport input through `set_input_event_forwarding_always_enabled()`.
- The ghost isn't part of the edited scene: it's a sibling of the scene root inside the editor's scene viewport, so it shares the scene's world but never shows in the Scene dock and is never saved. Its collision objects are taken off every layer, so the placement raycasts never hit it. Placed props are hit, so you can stack them.
- Placed nodes go under the node that was selected when placement started, or under the scene root if nothing was selected. A selection inside an instanced scene (a crate placed a moment ago, or one of its children) defers to the nearest ancestor that belongs to the edited scene itself. Nodes are added as scene instances with readable unique names (`Crate2`) and the edited scene root as owner. The selection isn't changed, so repeated clicks keep filling the same parent.
- Every placement is one `EditorUndoRedoManager` action ("Place Crate"). It sets the node's transform again after adding it, because some addons move every node that enters the tree. The 3D Cursor addon, for one, moves new Node3Ds to the cursor. Re-setting the transform keeps the copy where it was aimed, through undo and redo too. Checked against the 3D Cursor addon on 2026-10-23.

### Surface hits

- **Colliders:** a raycast through `PhysicsDirectSpaceState3D` of the edited scene's world.
- **Visible meshes:** a ray-vs-triangle test against the visible `MeshInstance3D`s in the edited scene, including those inside placed instances. Each instance is ruled out by its global AABB first, then `TriangleMesh.intersect_ray` runs in mesh-local space, with `Mesh.generate_triangle_mesh()` cached per mesh for as long as placement lasts. This lets you place on geometry that has no colliders. Hits on back faces get a normal flipped toward the camera. CSG, MultiMesh and GridMap geometry isn't tested, and skinned meshes are tested in their rest pose.
- The drawer toolbar has a hit mode dropdown (Colliders / Meshes / Colliders + meshes) and an Align checkbox. The default is both, and the nearer hit wins. Both settings are remembered per project. The toolbar wraps onto more rows when the drawer is docked somewhere narrow.
- When nothing is hit, the ghost hides and clicks do nothing. There is no fallback plane.
- **Align to normal** (off by default): the asset's up axis follows the surface normal, using the shortest-arc rotation from world up. A flat floor gives no rotation, slopes tip the asset as little as possible, and ceilings flip it about X. Yaw from the transform helpers will be applied around that normal. With align off, assets stay upright, so a hit on a wall leaves the asset half inside it.

### Transform helpers

The ghost's pose is `surface × yaw × tip`, then uniform scale: the surface rotation (when aligning), then yaw around the surface's up (turn keys, Alt+wheel and random yaw added together), then the tips in the asset's own frame.

- **Turn and tip shortcuts** while placing:
  - R turns 90° left and Shift+R 90° right.
  - T tips 90° forward (about the asset's X) and Shift+T 90° sideways (about Z).
  - Alt+R (Option+R on macOS) resets the turn and tips.
  - Tipping twice is the flip: a 180° turn, not a mirror (see below).
  - The keys are registered with `EditorSettings.add_shortcut` under `asset_drawer/`, so they can be rebound in Editor Settings → Shortcuts, and the binding persists.
  - Keys count when the 3D viewport has focus, and also whenever the mouse is over a 3D viewport, so they work straight after clicking a tile, while the drawer still has focus. The placer's `_input` tracks the mouse from motion events for this.
  - Unbound keys pass through to the viewport. Turns and tips reset each time placement starts.
- **Scroll to rotate:** Alt+wheel (Option on macOS) turns 15° per notch, or 5° with Shift as well. Horizontal wheel events count too, because macOS turns Shift+wheel into a horizontal scroll. A plain wheel still zooms. Trackpad pan gestures aren't handled.
- **Random yaw and scale:** a Random checkbox in the toolbar, plus a ⋮ button for the ranges: yaw from 0 up to N° (default 360) and uniform scale from min to max (default 0.9–1.1). A new roll happens when placement starts and after each click, so the ghost always shows exactly what the next click places.
- **Grid snapping:** a Snap checkbox and a step field (default 1 m) in the toolbar. The hit point snaps to the world grid, then slides back along the surface normal onto the plane it was hit on. A floor snaps X and Z and keeps its height, a wall snaps the two axes across it, and a slope stays on the slope. There's no grid offset. Godot's own Node3D snap settings aren't public API, so they aren't read.
- After each click the ghost raycasts again, so it moves onto the copy just placed instead of sitting inside it until the mouse moves.

### Settings and shortcuts

Shortcuts live in Editor Settings. The toolbar values (hit mode, align, random and its ranges, snap and its step) live in the project's editor metadata, through a small `PlacementSettings` object shared by the toolbar and the placer. Nothing is written to `project.godot`.

## Out of scope (for now)

- Placement planes, Terrain3D support
- Paint or scatter strokes
- Custom-rendered thumbnails, 3D previews, an "asset zoo" scene
- Tags (folders cover grouping)
- `.fbx`, `.obj`, `.dae`, bare `Mesh` resources
- 2D placement, C#

## Open questions

- **Flip semantics:** a true mirror needs a negative scale, which breaks colliders (Jolt rejects it) and lighting. So "flip" is two 90° tips, a 180° turn, and there's no mirror. Confirm once it's in use.
- **Per-asset overrides:** some assets want their own random range or their own align-to-normal setting (rocks yes, crates no). Leave room in the library's per-entry data, but don't build it until it's needed.
- **Mesh hit cost (measured 2026-10-23):** the list of `MeshInstance3D`s is cached and rebuilt only after a node under the scene root is added or removed. Each hover walks that list with an AABB test per instance. Across one game's levels (4–189 meshes) a hover cost 0.002–0.056 ms on average, worst 0.13 ms on the largest, against about 0.002 ms for the physics ray. No spatial index is needed at that scale; look again past a few thousand meshes.

## Milestones

1. **Libraries and drawer** (done 2026-10-23): the library resource, the dock grid with previews, drag-in from the FileSystem, remove and reorder, the switcher, the filter, remembered open libraries.
2. **Stamping on colliders** (done 2026-10-23): placement mode, the ghost, the physics raycast, click to place, undo, parenting.
3. **Mesh hits and align to normal** (done 2026-10-23).
4. **Transform helpers** (done 2026-10-23): rotate and flip shortcuts, scroll to rotate, random rotation and scale, grid snap.
5. **Real-project adoption:** the addon was synced into a game project with `tools/sync_to.sh`, enabled, and loads cleanly (2026-10-23). Building the first prop libraries is next, by hand.

## Testing

`test/test_level.tscn` has a floor, a 20° ramp, a wall and `MeshOnlyPlinth` (a mesh with no collider, for the mesh hit-test). `test/props/` holds three `.tscn` props and a `.glb`. `tools/run_tests.sh` runs `test/drawer_test.gd` headlessly in two passes: libraries, drops, reordering, the filter, restoring from metadata, and moved or missing assets. It also covers folders: nesting, filing from the tree and between sections, the grouped parent view, the filter in subfolders, moving folders, refusing cycles, deleting a folder, persistence, and a drop during a rescan. It then runs `test/placement_test.gd`, which feeds synthetic mouse and key events to the placer through a top-down camera: hovering, clicking, stacking, misses, undo and redo, parenting, each hit mode (a mesh-only plinth, and a collider with no mesh), align to normal on the ramp and the wall, the turn and tip keys, Alt+wheel, random yaw and scale (each copy matches its ghost, and each click re-rolls), snap on floors, walls and slopes, beating a `node_added` handler that moves new nodes, Esc, and arming tiles with the placement row. The project uses Jolt (the 4.6+ default); the placement test also passed under Godot Physics on 2026-10-23. A windowed editor run that sends events with `Input.parse_input_event` confirmed the plugin really receives viewport input.
