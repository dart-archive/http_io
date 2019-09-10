// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import "dart:io" hide HttpServer, HttpClient;

import "package:http_io/http_io.dart";
import "package:test/test.dart";

Future<Null> doTest(responseBytes, bodyLength) async {
  fullRequest(bytes) {
    var len = bytes.length;
    return len > 4 &&
        bytes[len - 4] == 13 &&
        bytes[len - 3] == 10 &&
        bytes[len - 2] == 13 &&
        bytes[len - 1] == 10;
  }

  handleSocket(socket) async {
    var bytes = [];
    await for (var data in socket) {
      bytes.addAll(data);
      if (fullRequest(bytes)) {
        socket.add(responseBytes);
        socket.close();
      }
    }
  }

  var server = await ServerSocket.bind('127.0.0.1', 0);
  server.listen(handleSocket);

  var client = HttpClient();
  var request =
      await client.getUrl(Uri.parse('http://127.0.0.1:${server.port}/'));
  var response = await request.close();
  expect(response.statusCode, equals(200));
  expect(bodyLength,
      equals((await response.fold([], (p, e) => p..addAll(e))).length));
  await server.close();
}

main() {
  var r1 = '''
HTTP/1.1 100 Continue\r
\r
HTTP/1.1 200 OK\r
\r
''';

  var r2 = '''
HTTP/1.1 100 Continue\r
My-Header-1: hello\r
My-Header-2: world\r
\r
HTTP/1.1 200 OK\r
\r
''';

  var r3 = '''
HTTP/1.1 100 Continue\r
\r
HTTP/1.1 200 OK\r
Content-Length: 2\r
\r
AB''';

  test("Continue OK", () async {
    await doTest(ascii.encode(r1), 0);
  });
  test("Continue hello world OK", () async {
    await doTest(ascii.encode(r2), 0);
  });
  test("Continue OK length AB", () async {
    await doTest(ascii.encode(r3), 2);
  });
}
