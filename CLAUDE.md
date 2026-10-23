## Project

A Godot 4.7+ editor addon: curated asset libraries in a dock, and a placement mode that stamps assets into the 3D scene. The plan and its scope live in `docs/spec.md`. Keep the addon lightweight, and treat anything listed there as out of scope until it's moved in.

## Code conventions

- All GDScript is statically typed: every variable, constant, parameter, return value (including `-> void`), and loop variable has a type, explicit or inferred with `:=` where the right-hand side makes it obvious. Use typed collections and cast with `as` when narrowing.
- Everything in `addons/asset_drawer/` is editor code: `@tool` on every script, and nothing that runs in exported games.
- The addon depends only on Godot. Nothing in it may reference `test/` or any project-specific input actions, layers or paths.
- Every change to the edited scene goes through `EditorUndoRedoManager`.
- Files are grouped by feature inside the addon folder, scene and script side by side.

## Verifying

Godot is `/Applications/Godot 4.7.2.app/Contents/MacOS/Godot`. Run headless checks with `HOME` pointed at a scratch folder, so editor settings and project metadata in the real HOME are left alone:

```bash
HOME=<scratch> "/Applications/Godot 4.7.2.app/Contents/MacOS/Godot" --headless --editor --path . -s <script.gd>
```

`tools/run_tests.sh` runs the tests this way; extend `test/drawer_test.gd` or `test/placement_test.gd` for new behaviour. Editor raycasts work headless (Jolt and Godot Physics both), so placement tests call the placer's `forward_input` with a top-down `Camera3D` added beside the edited scene root. Project metadata (open libraries, thumbnail size) lives in `.godot/editor/project_metadata.cfg`, not HOME, so the runner backs it up and restores it. ItemList item rects only lay out on draw, which never happens headless; call `force_update_list_size()` before using positions. A `-s` script extending `SceneTree` can find the dock with `root.find_children("*", "EditorDock", true, false)`. Thumbnails never arrive headless. To see them, run the editor windowed (`--editor --resolution 1600x900 -s capture.gd`, with the scratch HOME) and save `root.get_texture().get_image()`. Run a warnings pass after changing addon scripts: a temporary `override.cfg` in the repo root with `[debug]` and `gdscript/warnings/<name>=2` for each warning (include `untyped_declaration`), then a `-s` script that `load()`s every addon `.gd` with `CACHE_MODE_IGNORE` and prints `can_instantiate()`. Delete `override.cfg` straight after. Real-mouse code should track the mouse from `InputEventMouseMotion` in `_input` rather than `get_global_mouse_position()`, which ignores synthetic events. Grids created this frame have no size until the next frame, so `await process_frame` before using their item rects. `EditorFileSystem.get_file_type` returns an empty string while a scan runs, so wait for `is_scanning()` to clear before relying on it. Popups are native windows, so save `popup.get_texture().get_image()` to see them. `EditorSpinSlider` built from script drew no text in 4.7.2; use `SpinBox`. To check that real viewport input reaches the plugin, send `InputEventMouseMotion`/`InputEventMouseButton` with `Input.parse_input_event` at points inside `EditorInterface.get_editor_viewport_3d(0).get_parent().get_global_rect()` in a windowed run. Delete any `test_tmp_*.tres` and `.godot/editor/project_metadata.cfg` the run leaves behind.

## Git

Small changes are committed straight to `main`; branch only for big features. No AI attribution lines on commits or PRs.
