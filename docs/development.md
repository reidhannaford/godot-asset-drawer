# Working on the Asset Drawer

Everything a contributor needs that isn't obvious from the code: the layout, how to run the checks, the headless-editor gotchas the tests work around, and how a release goes out. The design record, with what's in scope and why, is [design.md](design.md).

## Layout

- `addons/asset_drawer/`: the addon. The only folder another project needs. Scripts are grouped by feature: `library/` (the resources), `drawer/` (the dock), `placement/` (the ghost, the raycasts, the toolbar and shortcuts), and `plugin.gd`, the only file that knows about all three.
- `test/`: a test level (a floor, a 20° ramp, a wall and a mesh with no collider), four props, and the two headless test scripts.
- `tools/run_tests.sh`: runs the tests. `tools/sync_to.sh <project>`: copies the addon into another project, replacing any older copy.
- `docs/`: this file, the design notes, and the README images.

## Conventions

- All GDScript is statically typed: every variable, constant, parameter, return value (including `-> void`) and loop variable has a type, explicit or inferred with `:=` where the right-hand side makes it obvious. Typed collections; narrow with `as`. The warnings pass below enforces it.
- Everything in `addons/asset_drawer/` is editor code: `@tool` on every script, and nothing that runs in exported games.
- The addon depends only on Godot. Nothing in it may reference `test/` or any project-specific input actions, layers or paths.
- Every change to the edited scene goes through `EditorUndoRedoManager`. Removing assets from a library goes through it too, in the global history; other library edits save straight to the `.tres`.
- Files are grouped by feature inside the addon folder, scene and script side by side.

## Running the checks

Godot 4.7.2 is assumed at `/Applications/Godot 4.7.2.app/Contents/MacOS/Godot`; set `GODOT` to use another binary.

```bash
tools/run_tests.sh
```

It runs `test/drawer_test.gd` twice (the first pass builds libraries, the second checks they come back from project metadata, then moves and deletes an asset on disk), then `test/placement_test.gd`, which feeds synthetic mouse and key events to the placer through a top-down camera. Expect `FAILURES 0` three times. The runner uses a throwaway `HOME`, backs up this project's own drawer metadata, and puts back the prop `drawer_test` renames if a run dies mid-way.

Each test script extends `SceneTree` and is run with `--headless --editor -s`, so the real editor, plugin and dock are up. Point `HOME` at a scratch folder for any such run, so editor settings in the real `HOME` are left alone:

```bash
HOME=<scratch> "/Applications/Godot 4.7.2.app/Contents/MacOS/Godot" --headless --editor --path . -s res://test/drawer_test.gd
```

### The warnings pass

After changing addon scripts, promote the warnings to errors and load every script. Put a temporary `override.cfg` in the repo root:

```ini
[debug]
gdscript/warnings/untyped_declaration=2
gdscript/warnings/unused_variable=2
gdscript/warnings/unused_parameter=2
gdscript/warnings/shadowed_variable=2
gdscript/warnings/unsafe_property_access=2
gdscript/warnings/unsafe_method_access=2
gdscript/warnings/unsafe_cast=2
gdscript/warnings/unsafe_call_argument=2
gdscript/warnings/return_value_discarded=2
```

then run a `-s` script that `load()`s each `addons/asset_drawer/**/*.gd` with `ResourceLoader.CACHE_MODE_IGNORE` and prints `can_instantiate()`. All of them must load. Delete `override.cfg` straight after; it's not ignored by git. As of 0.1.0 the addon passes with every one of those at error level.

## Headless editor gotchas

These are the reasons the tests look the way they do.

- Editor raycasts work headless, with Jolt and with Godot Physics. The project uses Jolt, the 4.6+ default.
- Project metadata (open libraries, thumbnail size, placement settings) lives in `.godot/editor/project_metadata.cfg`, not in `HOME`, which is why the runner backs it up.
- `ItemList` item rects only lay out on draw, which never happens headless; call `force_update_list_size()` before using positions. A grid created this frame has no size until the next frame, so `await process_frame` first.
- `ItemList` doesn't emit `item_clicked` for an already-selected item; the grid reports presses itself from `_gui_input`, as `tile_pressed`. A script's `_gui_input` runs before the control's own handling, so the selection it sees is the one from before the press.
- The dock's visibility depends on the editor's saved layout. A test that needs it on screen calls `make_visible()` on the dock (the panel's parent) rather than trusting the layout.
- `EditorFileSystem.get_file_type` returns an empty string while a scan runs; wait for `is_scanning()` to clear.
- Thumbnails never arrive headless, since nothing is ever drawn: tiles keep the generic scene icon.
- Popups are separate windows. Headless they open embedded and `visible` is reliable; windowed, save `popup.get_texture().get_image()` to see one.
- Real-mouse code tracks the mouse from `InputEventMouseMotion` in `_input`, because `get_global_mouse_position()` ignores synthetic events.
- `EditorSpinSlider` built from script drew no text in 4.7.2; the toolbar uses `SpinBox`.
- A queued free never runs at editor shutdown; the plugin frees its dock immediately on exit, so the thumbnail viewport goes before the renderer does.

## Windowed checks

Some things only show in a real window. Use the scratch `HOME` and a fixed size:

```bash
HOME=<scratch> "/Applications/Godot 4.7.2.app/Contents/MacOS/Godot" --editor --resolution 1600x900 --path . -s res://<capture>.gd
```

- Thumbnails: render a few into one sheet with `Image.blend_rect`, or save the whole editor with `root.get_texture().get_image()`.
- Real viewport input: send `InputEventMouseMotion`/`InputEventMouseButton` with `Input.parse_input_event` at points inside `EditorInterface.get_editor_viewport_3d(0).get_parent().get_global_rect()`.
- Delete any `test_tmp_*` files and `.godot/editor/project_metadata.cfg` such a run leaves behind.

## Using it in a game project

```bash
tools/sync_to.sh /path/to/your/project
```

copies `addons/asset_drawer/` over, deleting stale files. Edit here, then sync; don't edit the copy.

## Releasing

1. Bump `version` in `addons/asset_drawer/plugin.cfg` and add the entry to `CHANGELOG.md`.
2. Run `tools/run_tests.sh` and the warnings pass.
3. Commit, tag `vX.Y.Z` and push the tag; make a GitHub release from it, which is the zip the Asset Library points at.
4. For the Asset Library listing: category Tools, Godot version 4.7, licence MIT, the icon at `icon.svg`, and a screenshot from `docs/images/`. Submitting a new version is a new submission against the same listing with the new tag.
