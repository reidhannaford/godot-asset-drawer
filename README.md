# Asset Drawer

A small Godot 4.7+ editor addon for level building. You organize scenes and models into libraries, pick one from a thumbnail drawer, and click to stamp copies onto colliders or visible meshes in the 3D viewport.

Status: milestones 1–4 are done: libraries and the drawer, click-to-stamp onto colliders and/or visible meshes, align to normal, turn/tip keys, Alt+wheel spin, random yaw and scale, and grid snap. It's in use in a real project, synced with `tools/sync_to.sh`. See [docs/spec.md](docs/spec.md) for the plan.

## Layout

- `addons/asset_drawer/`: the addon itself. This is the only folder another project needs.
- `test/`: a test level and props for trying the addon in this repo's project.
- `tools/sync_to.sh`: copies the addon into another project.
- `tools/run_tests.sh`: runs the headless drawer and placement tests.

## Using it in another project

```bash
tools/sync_to.sh /path/to/your/project
```

Then enable **Asset Drawer** under Project Settings → Plugins.

## License

MIT
