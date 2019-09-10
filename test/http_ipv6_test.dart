// (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:http_io/http_io.dart';
import 'package:test/test.dart';

// Client makes a HTTP 1.0 request without connection keep alive. The
// server sets a content length but still needs to close the
// connection as there is no keep alive.
Future<Null> testHttpIPv6() {
  final completer = Completer<Null>();
  HttpServer.bind("::", 0).then((server) {
    server.listen((HttpRequest request) {
      expect(request.headers["host"][0], equals("[::1]:${server.port}"));
      expect(request.requestedUri.host, equals("::1"));
      request.response.close();
    });

    var client = HttpClient();
    var url = Uri.parse('http://[::1]:${server.port}/xxx');
    expect(url.host, equals('::1'));
    client
        .openUrl('GET', url)
        .then((request) => request.close())
        .then((response) {
      expect(response.statusCode, equals(HttpStatus.OK));
    }).whenComplete(() {
      server.close();
      client.close();
      completer.complete();
    });
  });
  return completer.future;
}

void main() {
  test('httpIPv6', testHttpIPv6);
}
