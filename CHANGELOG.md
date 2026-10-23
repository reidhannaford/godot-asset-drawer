# Changelog

## 0.1.0 (alpha), 2026-10-23

First public release.

- Libraries as `.tres` resources, with nested folders, assets tracked by uid, and missing assets marked rather than dropped.
- An **Assets** dock (bottom panel, side dock or floating) with rendered, cached thumbnails, a text filter, drag-in from the FileSystem dock, reordering, and drag-out to the viewport and Scene dock.
- Placement mode: a ghost follows the mouse, each click stamps one undoable copy under the selected node, onto colliders, visible meshes or both.
- Align to the surface normal, turn and tip keys, Alt/Option+wheel spin, random yaw and scale with a re-roll key, and grid snap kept on the surface.
- Rebindable shortcuts under `asset_drawer/` in Editor Settings; toolbar settings remembered per project.
- Removing assets from a library is undoable.
