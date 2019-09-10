// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:http_io/http_io.dart';
import 'package:test/test.dart';

Future<Null> testHEAD(int totalConnections) {
  final completer = Completer<Null>();
  HttpServer.bind("127.0.0.1", 0).then((server) async {
    server.listen((request) {
      var response = request.response;
      if (request.uri.path == "/test100") {
        response.contentLength = 100;
        response.close();
      } else if (request.uri.path == "/test200") {
        response.contentLength = 200;
        List<int> data = List<int>.filled(200, 0);
        response.add(data);
        response.close();
      } else if (request.uri.path == "/testChunked100") {
        List<int> data = List<int>.filled(100, 0);
        response.add(data);
        response.close();
      } else if (request.uri.path == "/testChunked200") {
        List<int> data = List<int>.filled(200, 0);
        response.add(data);
        response.close();
      } else {
        assert(false);
      }
    });

    HttpClient client = HttpClient();

    int count = 0;

    requestDone() {
      count++;
      if (count == totalConnections * 2) {
        client.close();
        server.close();
        completer.complete();
      }
    }

    for (int i = 0; i < totalConnections; i++) {
      int len = (i % 2 == 0) ? 100 : 200;
      await client
          .open("HEAD", "127.0.0.1", server.port, "/test$len")
          .then((request) => request.close())
          .then((HttpClientResponse response) {
        expect(len, equals(response.contentLength));
        response.listen((_) => fail("Data from HEAD request"),
            onDone: requestDone);
      });

      await client
          .open("HEAD", "127.0.0.1", server.port, "/testChunked$len")
          .then((request) => request.close())
          .then((HttpClientResponse response) {
        expect(-1, equals(response.contentLength));
        response.listen((_) => fail("Data from HEAD request"),
            onDone: requestDone);
      });
    }
  });
  return completer.future;
}

void main() {
  test('testHEAD', () => testHEAD(4));
}
