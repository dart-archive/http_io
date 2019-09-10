// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:http_io/http_io.dart';
import 'package:test/test.dart';

Future<int> runServer(int port, int connections, bool clean) {
  Completer<int> completer = Completer<int>();
  HttpServer.bind("127.0.0.1", port).then((server) {
    int i = 0;
    server.listen((request) {
      request.pipe(request.response);
      i++;
      if (!clean && i == 10) {
        int port = server.port;
        server.close().then((_) => completer.complete(port));
      }
    });

    Future.wait(List.generate(connections, (_) {
      var client = HttpClient();
      return client
          .get("127.0.0.1", server.port, "/")
          .then((request) => request.close())
          .then((response) => response.drain())
          .catchError((e) {
        if (clean) throw e;
      });
    })).then((_) {
      if (clean) {
        int port = server.port;
        server.close().then((_) => completer.complete(port));
      }
    });
  });
  return completer.future;
}

Future<Null> testReusePort() {
  final completer = Completer<Null>();
  runServer(0, 10, true).then((int port) {
    // Stress test the port reusing it 10 times.
    Future.forEach(List(10), (_) {
      return runServer(port, 10, true);
    }).then((_) {
      completer.complete();
    });
  });
  return completer.future;
}

Future<Null> testUncleanReusePort() {
  final completer = Completer<Null>();
  runServer(0, 10, false).then((int port) {
    // Stress test the port reusing it 10 times.
    Future.forEach(List(10), (_) {
      return runServer(port, 10, false);
    }).then((_) {
      completer.complete();
    });
  });
  return completer.future;
}

void main() {
  test('reusePort', testReusePort);
  test('uncleanedReusePort', testUncleanReusePort);
}
