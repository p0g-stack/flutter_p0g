import 'dart:convert';

import 'package:flutter_tools/src/base/common.dart';
import 'package:flutter_tools/src/base/file_system.dart';

import 'p0g_repository.dart';

/// The repository root's lock: url, sha256 and size of every binary the
/// stack consumes, all for one Flutter release. Bump it here only; the
/// published assets are never replaced.
const kArtifactLockFile = 'artifacts.lock.json';

final _sha256 = RegExp(r'^[0-9a-f]{64}$');
final _commit = RegExp(r'^[0-9a-f]{40}$');

/// One release asset: where it is and the bytes it must have.
final class LockedAsset {
  const LockedAsset({required this.url, required this.sha256, required this.size});

  final String url;
  final String sha256;
  final int size;
}

/// One producer release and its assets by variant (an ABI, `<target>-<mode>`).
final class LockedRelease {
  const LockedRelease({
    required this.repo,
    required this.tag,
    required this.commit,
    required this.assets,
    required this.fields,
  });

  final String repo;
  final String tag;
  final String commit;
  final Map<String, LockedAsset> assets;

  /// The release's other identity fields (`webUiTree`, `package`, ...).
  final Map<String, Object?> fields;

  /// A required string field beyond the common ones.
  String field(String name) => switch (fields[name]) {
    final String value => value,
    _ => throwToolExit('$kArtifactLockFile: $tag lacks $name.'),
  };

  /// The single asset of a one-asset release.
  LockedAsset get single => assets.length == 1
      ? assets.values.single
      : throwToolExit('$kArtifactLockFile: $tag has ${assets.length} assets, expected one.');
}

final class ArtifactLock {
  const ArtifactLock({
    required this.flutterVersion,
    required this.engine,
    required this.dartVersion,
    required this.artifacts,
  });

  /// Parses and checks the whole lock, so a bad entry fails before any fetch.
  factory ArtifactLock.parse(String text) {
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException catch (e) {
      throwToolExit('$kArtifactLockFile: ${e.message}.');
    }
    if (json
        case {
          'schema': 1,
          'flutter': {
            'version': final String version,
            'engine': final String engine,
            'dart': final String dart,
          },
          'artifacts': final Map<String, Object?> artifacts,
        }
        when _commit.hasMatch(engine)) {
      return ArtifactLock(
        flutterVersion: version,
        engine: engine,
        dartVersion: dart,
        artifacts: {
          for (final MapEntry(:key, :value) in artifacts.entries) key: _release(key, value),
        },
      );
    }
    throwToolExit('$kArtifactLockFile: expected schema 1 with flutter and artifacts.');
  }

  final String flutterVersion;
  final String engine;
  final String dartVersion;
  final Map<String, LockedRelease> artifacts;

  LockedRelease release(String name) =>
      artifacts[name] ?? throwToolExit('$kArtifactLockFile: no $name release.');

  /// flutter-webui's patched web SDK (`flutter_web_sdk/`, `ui_web/`).
  LockedRelease get webSdk => release('webSdk');

  /// The webui-termux-api APK the app plane is made from.
  LockedRelease get webuiTermuxApi => release('webuiTermuxApi');

  /// The Dart Android kit for exactly [dartVersion] and [abi].
  LockedAsset dartAndroidKit(String dartVersion, String abi) =>
      _kit(release('dartAndroidKit'), 'Dart Android', this.dartVersion, dartVersion, abi);

  /// The AERA runtime kit for exactly [flutterVersion] and `<target>-<mode>`.
  LockedAsset aeraKit(String flutterVersion, String target) =>
      _kit(release('aeraKit'), 'AERA', this.flutterVersion, flutterVersion, target);

  static LockedAsset _kit(
    LockedRelease release,
    String kind,
    String locked,
    String version,
    String target,
  ) {
    final asset = version == locked ? release.assets[target] : null;
    if (asset == null) {
      throwToolExit(
        'No pinned $kind kit for $version/$target; provide an explicit kit and sha256.',
      );
    }
    return asset;
  }

  static LockedRelease _release(String name, Object? json) {
    if (json case final Map<String, Object?> map) {
      if (map
          case {
            'repo': final String repo,
            'tag': final String tag,
            'commit': final String commit,
            'assets': final Map<String, Object?> assets,
          }
          when _commit.hasMatch(commit) && assets.isNotEmpty) {
        return LockedRelease(
          repo: repo,
          tag: tag,
          commit: commit,
          assets: {
            for (final MapEntry(:key, :value) in assets.entries) key: _asset('$name.$key', value),
          },
          fields: {
            for (final MapEntry(:key, :value) in map.entries)
              if (!const {'repo', 'tag', 'commit', 'assets'}.contains(key)) key: value,
          },
        );
      }
    }
    throwToolExit('$kArtifactLockFile: $name needs repo, tag, a full commit and assets.');
  }

  static LockedAsset _asset(String name, Object? json) {
    if (json case {'url': final String url, 'sha256': final String sha256, 'size': final int size}
        when url.startsWith('https://') && _sha256.hasMatch(sha256) && size > 0) {
      return LockedAsset(url: url, sha256: sha256, size: size);
    }
    throwToolExit('$kArtifactLockFile: $name needs an https url, a lowercase sha256 and a size.');
  }
}

/// Reads [kArtifactLockFile] from the repository commit this tool runs from.
Future<ArtifactLock> artifactLock() async {
  final File file = (await p0gRepository()).childFile(kArtifactLockFile);
  if (!file.existsSync()) throwToolExit('$kArtifactLockFile is missing: ${file.path}.');
  return ArtifactLock.parse(file.readAsStringSync());
}
