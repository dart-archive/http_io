// Copyright (c) 2018, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:http_io/http_io.dart';
import 'package:test/test.dart';

Future<Null> runTest(int totalConnections, [String body]) {
  final completer = Completer<Null>();
  HttpServer.bind("127.0.0.1", 0).then((server) async {
    server.listen((HttpRequest request) {
      HttpResponse response = request.response;
      // Cannot mutate request headers.
      expect(() => request.headers.add("X-Request-Header", "value"),
          throwsA(TypeMatcher<HttpException>()));
      expect("value", request.headers.value("X-Request-Header"));
      request.listen((_) {}, onDone: () {
        // Can still mutate response headers as long as no data has been sent.
        response.headers.add("X-Response-Header", "value");
        if (body != null) {
          response.write(body);
          // Cannot change state or reason when data has been sent.
          expect(() => response.statusCode = 200, throwsStateError);
          expect(() => response.reasonPhrase = "OK", throwsStateError);
          // Cannot mutate response headers when data has been sent.
          expect(() => response.headers.add("X-Request-Header", "value2"),
              throwsA(TypeMatcher<HttpException>()));
        }
        response..close();
        // Cannot change state or reason after connection is closed.
        expect(() => response.statusCode = 200, throwsStateError);
        expect(() => response.reasonPhrase = "OK", throwsStateError);
        // Cannot mutate response headers after connection is closed.
        expect(() => response.headers.add("X-Request-Header", "value3"),
            throwsA(TypeMatcher<HttpException>()));
      });
    });

    int count = 0;
    HttpClient client = HttpClient();
    for (int i = 0; i < totalConnections; i++) {
      await client
          .get("127.0.0.1", server.port, "/")
          .then((HttpClientRequest request) {
        if (body != null) {
          request.contentLength = -1;
        }
        // Can still mutate request headers as long as no data has been sent.
        request.headers.add("X-Request-Header", "value");
        if (body != null) {
          request.write(body);
          // Cannot mutate request headers when data has been sent.
          expect(() => request.headers.add("X-Request-Header", "value2"),
              throwsA(TypeMatcher<HttpException>()));
        }
        request.close();
        // Cannot mutate request headers when data has been sent.
        expect(() => request.headers.add("X-Request-Header", "value3"),
            throwsA(TypeMatcher<HttpException>()));
        return request.done;
      }).then((HttpClientResponse response) {
        // Cannot mutate response headers.
        expect(() => response.headers.add("X-Response-Header", "value"),
            throwsA(TypeMatcher<HttpException>()));
        expect("value", response.headers.value("X-Response-Header"));
        response.listen((_) {}, onDone: () {
          // Do not close the connections before we have read the
          // full response bodies for all connections.
          if (++count == totalConnections) {
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
  test('httpHeadersStateTest', () => runTest(5));
  test('httpHeadersStateTestBody', () => runTest(5, "Hello and goodbye"));
}
