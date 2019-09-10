// (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io' show ServerSocket;

import 'package:http_io/http_io.dart';
import 'package:test/test.dart';

// Test that a response line without any reason phrase is handled.
Future<Null> missingReasonPhrase(int statusCode, bool includeSpace) {
  final completer = Completer<Null>();
  var client = HttpClient();
  ServerSocket.bind("127.0.0.1", 0).then((server) {
    server.listen((client) {
      client.listen(null);
      if (includeSpace) {
        client.write("HTTP/1.1 $statusCode \r\n\r\n");
      } else {
        client.write("HTTP/1.1 $statusCode\r\n\r\n");
      }
      client.close();
    });
    client
        .getUrl(Uri.parse("http://127.0.0.1:${server.port}/"))
        .then((request) => request.close())
        .then((response) {
      expect(statusCode, equals(response.statusCode));
      expect("", equals(response.reasonPhrase));
      return response.drain();
    }).whenComplete(() {
      server.close();
      completer.complete();
    });
  });
  return completer.future;
}

void main() {
  test('missingReasonOKSpace', () => missingReasonPhrase(HttpStatus.OK, true));
  test('missingReasonErrorSpace',
      () => missingReasonPhrase(HttpStatus.INTERNAL_SERVER_ERROR, true));
  test('missingReasonOK', () => missingReasonPhrase(HttpStatus.OK, false));
  test('missingReasonError',
      () => missingReasonPhrase(HttpStatus.INTERNAL_SERVER_ERROR, false));
}
