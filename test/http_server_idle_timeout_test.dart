// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import "dart:async";
import 'dart:io' show Socket;

import 'package:http_io/http_io.dart';
import 'package:test/test.dart';

Future<Null> testTimeoutAfterRequest() {
  final completer = Completer<Null>();
  HttpServer.bind("127.0.0.1", 0).then((server) {
    server.idleTimeout = null;

    server.listen((request) {
      server.idleTimeout = const Duration(milliseconds: 100);
      request.response.close();
    });

    Socket.connect("127.0.0.1", server.port).then((socket) {
      var data = "GET / HTTP/1.1\r\nContent-Length: 0\r\n\r\n";
      socket.write(data);
      socket.listen(null, onDone: () {
        socket.close();
        server.close();
        completer.complete();
      });
    });
  });
  return completer.future;
}

Future<Null> testTimeoutBeforeRequest() {
  final completer = Completer<Null>();
  HttpServer.bind("127.0.0.1", 0).then((server) {
    server.idleTimeout = const Duration(milliseconds: 100);

    server.listen((request) => request.response.close());

    Socket.connect("127.0.0.1", server.port).then((socket) {
      socket.listen(null, onDone: () {
        socket.close();
        server.close();
        completer.complete();
      });
    });
  });
  return completer.future;
}

void main() {
  test('timeoutAfterRequest', () => testTimeoutAfterRequest());
  test('timeoutBeforeRequest', () => testTimeoutBeforeRequest());
}
