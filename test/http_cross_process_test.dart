// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io'
    show Directory, File, InternetAddress, Platform, Process, ProcessResult;

import 'package:http_io/http_io.dart';
import 'package:test/test.dart';

const int NUM_SERVERS = 10;

void main([List<String> args]) {
  if (args == null || args.isEmpty) {
    test('httpCrossProcess', runTest);
  } else if (args[0] == '--client') {
    int port = int.parse(args[1]);
    runClient(port);
  } else {
    throw 'Unknown arguments to http_cross_process_test.dart';
  }
}

void runTest() {
  for (int i = 0; i < NUM_SERVERS; ++i) {
    makeServer().then((server) {
      runClientProcess(server.port).then((_) => server.close());
    });
  }
}

Future<HttpServer> makeServer() {
  return HttpServer.bind(InternetAddress.loopbackIPv4, 0).then((server) {
    server.listen((request) {
      request.pipe(request.response);
    });
    return server;
  });
}

Future<void> runClientProcess(int port) {
  var script =
      "${Directory.current.path}/test/http_client_stays_alive_test.dart";
  if (!(File(script)).existsSync()) {
    // If we can't find the file relative to the cwd, then look relative to
    // Platform.script.
    script = Platform.script
        .resolve('http_client_stays_alive_test.dart')
        .toFilePath();
  }

  return Process.run(
          Platform.executable,
          []
            ..addAll(Platform.executableArguments)
            ..add(script)
            ..add('--client')
            ..add(port.toString()))
      .then((ProcessResult result) {
    if (result.exitCode != 0 || !result.stdout.contains('SUCCESS')) {
      print("Client failed, exit code ${result.exitCode}");
      print("  stdout:");
      print(result.stdout);
      print("  stderr:");
      print(result.stderr);
      fail('Client subprocess exit code: ${result.exitCode}');
    }
  });
}

void runClient(int port) {
  var client = HttpClient();
  client
      .get('127.0.0.1', port, "/")
      .then((request) => request.close())
      .then((response) => response.drain())
      .then((_) => client.close())
      .then((_) => print('SUCCESS'));
}
