// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'package:http_io/http_io.dart'
    show
        HttpClient,
        HttpClientRequest,
        HttpClientResponse,
        HttpHeaders,
        HttpRequest,
        HttpServer;
import 'package:test/test.dart';

void setConnectionHeaders(HttpHeaders headers) {
  headers.add(HttpHeaders.CONNECTION, "my-connection-header1");
  headers.add("My-Connection-Header1", "some-value1");
  headers.add(HttpHeaders.CONNECTION, "my-connection-header2");
  headers.add("My-Connection-Header2", "some-value2");
}

void checkExpectedConnectionHeaders(
    HttpHeaders headers, bool persistentConnection) {
  expect("some-value1", equals(headers.value("My-Connection-Header1")));
  expect("some-value2", equals(headers.value("My-Connection-Header2")));
  expect(
      headers[HttpHeaders.CONNECTION]
          .any((value) => value.toLowerCase() == "my-connection-header1"),
      isTrue);
  expect(
      headers[HttpHeaders.CONNECTION]
          .any((value) => value.toLowerCase() == "my-connection-header2"),
      isTrue);
  if (persistentConnection) {
    expect(headers[HttpHeaders.CONNECTION].length, equals(2));
  } else {
    expect(headers[HttpHeaders.CONNECTION].length, equals(3));
    expect(
        headers[HttpHeaders.CONNECTION]
            .any((value) => value.toLowerCase() == "close"),
        isTrue);
  }
}

Future<Null> headerTest(int totalConnections, bool clientPersistentConnection) {
  final completer = Completer<Null>();
  HttpServer.bind("127.0.0.1", 0).then((server) {
    server.listen((HttpRequest request) {
      // Check expected request.
      expect(clientPersistentConnection, equals(request.persistentConnection));
      expect(clientPersistentConnection,
          equals(request.response.persistentConnection));
      checkExpectedConnectionHeaders(
          request.headers, request.persistentConnection);

      // Generate response. If the client signaled non-persistent
      // connection the server should not need to set it.
      if (request.persistentConnection) {
        request.response.persistentConnection = false;
      }
      setConnectionHeaders(request.response.headers);
      request.response.close();
    });

    int count = 0;
    HttpClient client = HttpClient();
    for (int i = 0; i < totalConnections; i++) {
      client
          .get("127.0.0.1", server.port, "/")
          .then((HttpClientRequest request) {
        setConnectionHeaders(request.headers);
        request.persistentConnection = clientPersistentConnection;
        return request.close();
      }).then((HttpClientResponse response) {
        expect(response.persistentConnection, isFalse);
        checkExpectedConnectionHeaders(
            response.headers, response.persistentConnection);
        response.listen((_) {}, onDone: () {
          count++;
          if (count == totalConnections) {
            client.close();
            server.close();
            completer.complete();
          }
        });
      });
    }
  });
  return completer.future;
}

void main() {
  test('test_a', () => headerTest(2, false));
  test('test_b', () => headerTest(2, true));
}
