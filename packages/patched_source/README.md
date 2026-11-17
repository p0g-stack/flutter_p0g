# patched_source

Pure-Dart Git patch materialization shared by stack bootstraps. No Flutter or
flutter_tools dependency. Import `package:patched_source/patched_source.dart`.

- `readPatchPin(File)` reads `repo=`, full 40-hex `commit=`, optional `tag=` and
  optional `package=`. Pub consumers must require `package=` themselves and
  validate that the resulting package exists. A tag is descriptive, not identity.
- `materializePatchedSource(destination:, repository:, commit:, patches:)` applies
  regular `.patch` files in filename order (an empty series is valid). Identity
  records the repository, full commit, ordered patch names/SHA256 digests and
  the Git tree after staging the patched result in `.patched_source.json`, schema 1.
  Calls serialize using a sibling `.lock` file and a same-isolate queue. The
  helper builds in a sibling staging directory and installs only after success.
  It never adopts a nonempty unmarked directory. Modified tracked content or
  untracked nonignored files in a managed tree cause refusal, even on reuse;
  ignored build products are disposable. Keep the lock file outside the tree.
- `setManagedPubOverride(overrides:, package:, relativePath:,
  previousManagedPaths:)` updates only absent/equal/explicitly previously managed
  path overrides. Git/hosted/custom sources and invalid or duplicate YAML keys
  fail without changing the file. Unrelated YAML mappings and comments survive.

Callers own their artifact checks (package manifests, compiled binaries), their
legacy migration proof, and series selection. Validate *all* explicitly requested
series names before materializing any: a missing series must not partially apply
other requested names. Missing optional third_party directories are a caller's
no-op, not a fabricated source fallback.

Run `dart pub get && dart test`. Fixtures use temporary local Git repositories;
no network, devices, SDK source tree or Flutter process is needed.
