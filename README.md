# Asset Drawer

A small Godot 4.7+ editor addon for level building. You organize scenes and models into libraries, pick one from a thumbnail drawer, and click to stamp copies onto colliders or visible meshes in the 3D viewport.

Status: scaffold. The dock registers but does nothing yet. See [docs/spec.md](docs/spec.md) for the plan.

## Layout

- `addons/asset_drawer/`: the addon itself. This is the only folder another project needs.
- `test/`: a test level and props for trying the addon in this repo's project.
- `tools/sync_to.sh`: copies the addon into another project.

## Using it in another project

```bash
tools/sync_to.sh /path/to/your/project
```

Then enable **Asset Drawer** under Project Settings → Plugins.

## License

MIT
