# Upstream packet: file_picker web handles and read/write access

Status: rebased preparation branch pushed to the org fork, PR text ready. **No PR opened** (opening upstream
PRs is not authorized). This package is not carried as a patch file in the stack; the fork branch *is* the
carrier.

| | |
| --- | --- |
| Upstream repository | https://github.com/miguelpruivo/flutter_file_picker |
| Base commit | `7b8aec331c177bf6050c72b2ff48518b1e024f39` (`Add the copyToCache entries to the changelogs of 13.4.0 and 2.2.0`; upstream `main` tip at preparation time) |
| Fork | https://github.com/p0g-stack/flutter_file_picker (existing; its `main` is at `bf434d2`, 63 commits behind upstream — the branch is based on upstream directly) |
| Head branch | `web-fs-access-handles` @ `7d4171e34b3e0f31fb71beafbc49a569ac69da95` |
| Compare URL | https://github.com/miguelpruivo/flutter_file_picker/compare/7b8aec331c177bf6050c72b2ff48518b1e024f39...p0g-stack:flutter_file_picker:web-fs-access-handles |
| Commits | `318e8d8` *feat(web): pick through the file system access dialog and remember handles*, `7d4171e` *feat(web): ask for readwrite access by mode, not read* |
| Diff | 11 files, +1295 −21 |
| Previous branch | `web-file-system-access-handles` (tip `56b5707`) is unchanged and still 63 commits behind; see "Why a new branch" |

## What the change does

`packages/file_picker_web`:

- `FilePickerWebOptions.dialog` (`input` | `fileSystemAccess` | `auto`), `types` and `pickerId`. `auto` uses the
  dialog only when the browser has `showOpenFilePicker()` *and* the pick has a `types` filter (or
  `FileType.any`), because the dialog cannot express `accept`; `fileSystemAccess` reports why it cannot be shown
  instead of silently falling back, and `input` keeps the existing behaviour.
- `web_file_system_access.dart`: a `showOpenFilePicker()` wrapper, `supportsShowOpenFilePicker`, and the
  permission helpers. The second commit replaces the read-only `_readMode` with `FilePermissionMode`
  (`read`/`readWrite`), so `hasPermission`/`requestPermission` can check and renew write access for a handle the
  page kept to resume an interrupted save (`createWritable()` otherwise throws `NotAllowedError` after a
  reload); `WebPlatformFile.hasAccess`/`requestAccess` take the same mode, defaulting to `read`.
- `web_handle_store.dart`: persists picked handles as tokens, so a pick can be restored after a page reload
  (with the page still needing permission).
- `WebPlatformFile`: `persist`, `restore`, `forget`, and the handle kept on a picked file.
- Tests: `test/web_file_system_access_test.dart` (484 lines) covering the dialog choice, the store, the
  permission modes and `WebPlatformFile`; README/CHANGELOG entries for both packages.

## Why a new branch

The existing `web-file-system-access-handles` branch (`56b5707`) is based on `bf434d2`, 63 commits behind
`main`, and merging it into current `main` conflicts in
`packages/file_picker_web/lib/src/file_picker_web.dart`, because `main` gained the picker-session lifecycle
(`_activeSession`, stale-session cancellation) after that branch was cut. `web-fs-access-handles` is the same
two commits rebased onto current `main`; the conflict was resolved by keeping `main`'s session
supersede/cancel logic untouched and placing the file-system-access branch before any `<input>` session is
created (a dialog pick returns before the input session exists). The old branch was not reset or force-pushed.

## Behavioral checks actually executed

Flutter 3.47.9 / Dart 3.13.7, Chrome 157.0.8103.50.

1. `cd packages/file_picker_web && flutter pub get && flutter analyze` → `No issues found!`
2. `flutter test --platform chrome test/web_file_system_access_test.dart` → 18 passed.
3. `flutter test --platform chrome` (whole package) → 67 passed.

The wider monorepo suites (Android/iOS/desktop) were not run: this change is web-only.

## PR body

```text
feat(web): pick through the file system access dialog and remember handles

Where the browser has `showOpenFilePicker()`, `file_picker` always uses an
`<input type="file">`. That cannot express a filter the dialog can, and it
cannot hand back anything the page may keep: the picked file is readable
once and gone after a reload.

Add `FilePickerWebOptions.dialog` (`input` | `fileSystemAccess` | `auto`),
`types` and `pickerId`. `auto` uses the dialog only when the browser has it
and the filter is expressible (`types`, or `FileType.any`); otherwise the
input stays in charge and its `accept` behaviour is unchanged. A pick that
asks for the dialog and cannot show it reports why.

Picked handles are kept on the returned file and can be persisted as tokens
(`WebPlatformFile.persist`/`restore`/`forget`), so an app can resume work on
a file the user already chose; permission is still checked with the browser
before use.

A handle the page kept to write to later needs `readwrite`, not `read`:
`FilePermissionMode` lets `hasPermission`/`requestPermission` (and
`WebPlatformFile.hasAccess`/`requestAccess`) ask for the mode the caller
needs, defaulting to `read` as before. Without it `createWritable()` throws
`NotAllowedError` after a reload even though the page may request the
permission.

Tests: `packages/file_picker_web/test/web_file_system_access_test.dart`
(dialog choice and fallback, store round trip, both permission modes,
`WebPlatformFile` read and write paths). `flutter analyze` clean,
`flutter test --platform chrome` for the package: 67 passed.
```

## Notes

- Two commits are kept because the second one builds on the API the first adds; review them in order, or
  squash if preferred.
- The fork's `main` is stale (`bf434d2`). It does not affect the compare URL, but updating it before opening the
  PR keeps later rebases simple.
