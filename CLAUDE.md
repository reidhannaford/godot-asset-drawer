## Project

A Godot 4.7+ editor addon: curated asset libraries in a dock, and a placement mode that stamps assets into the 3D scene. The scope and its reasons live in `docs/design.md`; treat anything listed out of scope there as out of scope until it's moved in. Keep the addon lightweight.

## Code conventions

- All GDScript is statically typed: every variable, constant, parameter, return value (including `-> void`), and loop variable has a type, explicit or inferred with `:=` where the right-hand side makes it obvious. Use typed collections and cast with `as` when narrowing.
- Everything in `addons/asset_drawer/` is editor code: `@tool` on every script, and nothing that runs in exported games.
- The addon depends only on Godot. Nothing in it may reference `test/` or any project-specific input actions, layers or paths.
- Every change to the edited scene goes through `EditorUndoRedoManager`. Removing assets from a library does too, in the global history.
- Files are grouped by feature inside the addon folder, scene and script side by side.

## Verifying

`docs/development.md` has the full procedure and the headless-editor gotchas. In short: `tools/run_tests.sh` must print `FAILURES 0` three times, and after changing addon scripts run the warnings pass described there (a temporary `override.cfg` with the warnings at error level, every addon script loaded with `CACHE_MODE_IGNORE`; delete the override after). Headless runs point `HOME` at a scratch folder. Extend `test/drawer_test.gd` or `test/placement_test.gd` for new behaviour.

## Git

Small changes are committed straight to `main`; branch only for big features. No AI attribution lines on commits or PRs. Releases: bump `plugin.cfg`, update `CHANGELOG.md`, tag `vX.Y.Z` (see `docs/development.md`).
