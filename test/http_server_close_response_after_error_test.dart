// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io' show Directory, File, Platform, Process;

import 'package:http_io/http_io.dart';
import 'package:test/test.dart';

const CLIENT_SCRIPT = "http_server_close_response_after_error_client.dart";

Future<Null> serverCloseResponseAfterError() {
  final completer = Completer<Null>();
  HttpServer.bind("127.0.0.1", 0).then((server) {
    server.listen((request) {
      request.listen(null, onError: (e) {}, onDone: () {
        request.response.close();
      });
    });
    var name = '${Directory.current.path}/test/$CLIENT_SCRIPT';
    if (!File(name).existsSync()) {
      name = Platform.script.resolve(CLIENT_SCRIPT).toString();
    }
    Process.run(Platform.executable, [name, server.port.toString()])
        .then((result) {
      if (result.exitCode != 0) throw "Bad exit code";
      server.close();
      completer.complete();
    });
  });
  return completer.future;
}

void main() {
  test('httpServerCloseResponseAfterError', serverCloseResponseAfterError);
}
