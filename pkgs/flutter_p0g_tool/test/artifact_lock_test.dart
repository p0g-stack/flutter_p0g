import 'dart:convert';

import 'package:flutter_p0g_tool/src/artifact_lock.dart';
import 'package:flutter_p0g_tool/src/webui/dart_android.dart';
import 'package:flutter_tools/src/base/common.dart';
import 'package:test/test.dart';

import 'lock_fixture.dart';

Matcher _toolExit(Object message) =>
    throwsA(isA<ToolExit>().having((error) => error.message, 'message', message));

void main() {
  late ArtifactLock lock;
  late Map<String, dynamic> json;

  setUpAll(() async {
    final text = await committedLockText();
    lock = ArtifactLock.parse(text);
    json = jsonDecode(text) as Map<String, dynamic>;
  });

  test('the committed lock names every binary the CLI fetches', () {
    expect(
      lock.artifacts.keys,
      containsAll(['webSdk', 'aeraKit', 'dartAndroidKit', 'webuiTermuxApi']),
    );
    expect(lock.webSdk.single.url, endsWith('/${lock.webSdk.tag}/flutter-webui-web-sdk.tar.xz'));
    expect(lock.webuiTermuxApi.single.url, contains('/${lock.webuiTermuxApi.tag}/'));
    expect(lock.webuiTermuxApi.field('certificateSha256'), matches(RegExp(r'^[0-9a-f]{64}$')));
  });

  test('kits are selected by the exact locked version and every ABI or target', () {
    for (final abi in kDartArchForAbi.keys) {
      expect(
        lock.dartAndroidKit(lock.dartVersion, abi).url,
        endsWith('/dart-android-$abi-${lock.dartVersion}.tar.gz'),
      );
    }
    for (final target in ['linux-arm64-debug', 'linux-x64-debug']) {
      expect(
        lock.aeraKit(lock.flutterVersion, target).url,
        endsWith('/flutter-aera-kit-$target-${lock.flutterVersion}.tar.xz'),
      );
    }
  });

  test('unknown versions, ABIs, targets and modes fail instead of synthesizing a URL', () {
    for (final (version, abi) in [('future', 'x86_64'), (lock.dartVersion, 'mips')]) {
      expect(
        () => lock.dartAndroidKit(version, abi),
        _toolExit(
          'No pinned Dart Android kit for $version/$abi; provide an explicit kit and sha256.',
        ),
      );
    }
    for (final (version, target) in [
      ('future', 'linux-arm64-debug'),
      (lock.flutterVersion, 'linux-arm64-release'),
      (lock.flutterVersion, 'linux-mips-debug'),
    ]) {
      expect(
        () => lock.aeraKit(version, target),
        _toolExit('No pinned AERA kit for $version/$target; provide an explicit kit and sha256.'),
      );
    }
  });

  test('a malformed entry fails the whole lock before any fetch', () {
    Map<String, dynamic> copy() => jsonDecode(jsonEncode(json)) as Map<String, dynamic>;
    Map<String, dynamic> asset(Map<String, dynamic> doc) =>
        ((doc['artifacts'] as Map)['webSdk'] as Map)['assets']['sdk'] as Map<String, dynamic>;

    expect(() => ArtifactLock.parse('{'), throwsA(isA<ToolExit>()));
    expect(() => ArtifactLock.parse(jsonEncode({...json, 'schema': 2})), throwsA(isA<ToolExit>()));
    for (final (field, value) in [
      ('sha256', 'F' * 64),
      ('sha256', 'f' * 63),
      ('url', 'http://example.invalid/sdk.tar.xz'),
      ('size', 0),
    ]) {
      final broken = copy();
      asset(broken)[field] = value;
      expect(() => ArtifactLock.parse(jsonEncode(broken)), throwsA(isA<ToolExit>()), reason: field);
    }
    final shortCommit = copy();
    ((shortCommit['artifacts'] as Map)['aeraKit'] as Map)['commit'] = 'b90bec6';
    expect(() => ArtifactLock.parse(jsonEncode(shortCommit)), throwsA(isA<ToolExit>()));
  });
}
