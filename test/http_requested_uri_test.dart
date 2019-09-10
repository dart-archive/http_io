// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import "dart:async";

import 'package:http_io/http_io.dart';
import 'package:test/test.dart';

const sendPath = '/path?a=b#c';
const expectedPath = '/path?a=b';

Future<Null> runTest(String expected, Map headers) {
  final completer = Completer<Null>();
  HttpServer.bind("localhost", 0).then((server) {
    expected = expected.replaceAll('%PORT', server.port.toString());
    server.listen((request) {
      expect("$expected$expectedPath", equals(request.requestedUri.toString()));
      request.response.close();
    });
    HttpClient client = HttpClient();
    client
        .get("localhost", server.port, sendPath)
        .then((request) {
          for (var v in headers.keys) {
            if (headers[v] != null) {
              request.headers.set(v, headers[v]);
            } else {
              request.headers.removeAll(v);
            }
          }
          return request.close();
        })
        .then((response) => response.drain())
        .then((_) {
          server.close();
          completer.complete();
        });
  });
  return completer.future;
}

void main() {
  test('requestedUri1', () => runTest('http://localhost:%PORT', {}));
  test('requestedUri2',
      () => runTest('https://localhost:%PORT', {'x-forwarded-proto': 'https'}));
  test('requestedUri3',
      () => runTest('ws://localhost:%PORT', {'x-forwarded-proto': 'ws'}));
  test('requestedUri4',
      () => runTest('http://my-host:321', {'x-forwarded-host': 'my-host:321'}));
  test(
      'requestedUri5', () => runTest('http://localhost:%PORT', {'host': null}));
}
