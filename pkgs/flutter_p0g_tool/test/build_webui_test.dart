import 'package:args/args.dart';
import 'package:flutter_p0g_tool/src/commands/build_webui.dart';
import 'package:flutter_tools/src/web/file_generators/flutter_service_worker_js.dart';
import 'package:flutter_tools/src/web/web_options.dart';
import 'package:test/test.dart';

void main() {
  final parser = ArgParser();
  for (final option in const WebUiCoreOptionsBundle().descriptors) {
    option.addTo(parser);
  }

  test('WebUI defaults bundle resources without a service worker', () {
    final args = parser.parse([]);
    expect(WebOptions.webResourcesCdn.getValue(args), isFalse);
    expect(WebOptions.pwaStrategy.getValue(args), ServiceWorkerStrategy.none);
  });

  test('explicit SDK options take precedence over WebUI defaults', () {
    final args = parser.parse(['--web-resources-cdn', '--pwa-strategy=offline-first']);
    expect(WebOptions.webResourcesCdn.getValue(args), isTrue);
    expect(WebOptions.pwaStrategy.getValue(args), ServiceWorkerStrategy.offlineFirst);
  });
}
