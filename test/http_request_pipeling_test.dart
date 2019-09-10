// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io' show Socket;

import 'package:http_io/http_io.dart';
import 'package:test/test.dart';

Future<Null> requestPipeling() {
  final completer = Completer<Null>();
  final int REQUEST_COUNT = 100;
  int count = 0;
  HttpServer.bind("127.0.0.1", 0).then((server) {
    server.listen((HttpRequest request) {
      count++;
      request.response.write(request.uri.path);
      request.response.close();
      if (request.uri.path == "/done") {
        request.response.done.then((_) {
          expect(REQUEST_COUNT + 1, equals(count));
          server.close();
          completer.complete();
        });
      }
    });
    Socket.connect("127.0.0.1", server.port).then((s) {
      s.listen((data) {});
      for (int i = 0; i < REQUEST_COUNT; i++) {
        s.write("GET /$i HTTP/1.1\r\nX-Header-1: 111\r\n\r\n");
      }
      s.write("GET /done HTTP/1.1\r\nConnection: close\r\n\r\n");
      s.close();
    });
  });
  return completer.future;
}

void main() {
  test('httpRequestPipeling', requestPipeling);
}
