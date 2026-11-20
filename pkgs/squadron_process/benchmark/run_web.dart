// Runs the browser benchmark in headless Chromium.
//
//   dart run benchmark/run_web.dart <build-dir> <serve-executable> <chrome>
//
// <build-dir> holds index.html, bench.dart.js and bench_worker.dart.js (see
// tool/bench.sh). Starts the process place host, serves the page, opens it in
// <chrome> and prints the results as a Markdown table.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:squadron_process/squadron_process.dart';

import 'src/measure.dart';

Future<void> main(List<String> args) async {
  if (args.length < 3) {
    stderr.writeln('usage: run_web.dart <build-dir> <serve-exe> <chrome>');
    exit(64);
  }
  final [buildDir, serveExe, chrome, ...] = args;

  final host = await Process.start(serveExe, [
    '--first-link-grace-ms',
    '300000',
    '--grace-ms',
    '500',
  ]);
  host.stderr.listen(stderr.add);
  final lines = host.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .asBroadcastStream();
  final endpoint = ProcessEndpoint.tryParse(await lines.first)!;

  final results = Completer<List>();
  final http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  http.listen((req) async {
    if (req.method == 'POST' && req.uri.path == '/results') {
      results.complete(jsonDecode(await utf8.decodeStream(req)) as List);
      req.response.statusCode = 204;
    } else {
      final f = File('$buildDir${req.uri.path}');
      if (await f.exists()) {
        req.response.headers.contentType = req.uri.path.endsWith('.html')
            ? ContentType.html
            : ContentType('text', 'javascript', charset: 'utf-8');
        await req.response.addStream(f.openRead());
      } else {
        req.response.statusCode = 404;
      }
    }
    await req.response.close();
  });

  final version = (await Process.run(chrome, [
    '--version',
  ])).stdout.toString().trim();
  final url = Uri(
    scheme: 'http',
    host: '127.0.0.1',
    port: http.port,
    path: '/index.html',
    queryParameters: {
      'port': '${endpoint.port}',
      'token': endpoint.token,
      'runtime': '$version, dart2js',
    },
  );
  final browser = await Process.start(chrome, [
    '--headless=new',
    '--no-sandbox',
    '--disable-gpu',
    '--user-data-dir=${Directory.systemTemp.createTempSync('bench').path}',
    '$url',
  ]);
  browser.stdout.drain<void>();
  browser.stderr.drain<void>();

  try {
    final out = await results.future.timeout(const Duration(minutes: 5));
    print(BenchResult.header);
    for (final m in out.cast<Map>()) {
      if (m['error'] != null) {
        stderr.writeln(m['error']);
        exitCode = 1;
      } else {
        print(BenchResult.fromJson(m).row());
      }
    }
  } finally {
    browser.kill();
    host.kill();
    await http.close(force: true);
  }
  exit(exitCode);
}
