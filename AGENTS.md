# flutter_p0g: working agreements

Self-contained; no external base file.

- Pattern first. Before designing a feature, check how `flutter_tools`,
  `flutterpi_tool`, flutter-elinux or flutter-tizen do it, and do it their
  way. A new command is a `FlutterCommand`; a new target's build reuses the
  closest `flutter build` subcommand and adds only packing.
- Flutter's own flags keep their meaning. Change a default only where a
  target can't work with it (no CDN, no service worker in a manager), and
  say why next to the override.
- The platform folders (`webui/`, `aera/`) belong to the app once created:
  `create` never overwrites without `--overwrite`, and `build` only fills in
  build variables.
- Patches against upstream (frb, later `web_ui`) live here as numbered
  series against a pinned commit. Nothing is upstreamed until it is tested on
  its own; a stamp of commit plus patch bytes decides when to rebuild.
- Device behaviour (installers, managers) is detected by probing, never by a
  manager's name. Every string sent to a device shell is quoted here.
- Tests are unit tests against fakes and in-memory files. No e2e; device
  claims come from devicelab runs with the device and manager named.
- Pinned Flutter 3.47.5. Bumping it means re-checking every patch series.
