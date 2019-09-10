// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:http_io/http_io.dart';
import 'package:test/test.dart';

Future<Null> testCookies() {
  final completer = Completer<Null>();
  var cookies = [
    {'abc': 'def'},
    {'ABC': 'DEF'},
    {'Abc': 'Def'},
    {'Abc': 'Def', 'SID': 'sffFSDF4FsdfF56765'}
  ];

  HttpServer.bind("127.0.0.1", 0).then((server) {
    server.listen((HttpRequest request) {
      // Collect the cookies in a map.
      var cookiesMap = {};
      request.cookies.forEach((c) => cookiesMap[c.name] = c.value);
      int index = int.parse(request.uri.path.substring(1));
      expect(cookies[index], cookiesMap);
      // Return the same cookies to the client.
      cookiesMap.forEach((k, v) {
        request.response.cookies.add(Cookie(k, v));
      });
      request.response.close();
    });

    int count = 0;
    HttpClient client = HttpClient();
    for (int i = 0; i < cookies.length; i++) {
      client.get("127.0.0.1", server.port, "/$i").then((request) {
        // Send the cookies to the server.
        cookies[i].forEach((k, v) {
          request.cookies.add(Cookie(k, v));
        });
        return request.close();
      }).then((response) {
        // Expect the same cookies back.
        var cookiesMap = {};
        response.cookies.forEach((c) => cookiesMap[c.name] = c.value);
        expect(cookies[i], cookiesMap);
        response.cookies.forEach((c) => expect(c.httpOnly, isTrue));
        response.listen((d) {}, onDone: () {
          if (++count == cookies.length) {
            client.close();
            server.close();
            completer.complete();
          }
        });
      }).catchError((e, trace) {
        String msg = "Unexpected error $e";
        if (trace != null) msg += "\nStackTrace: $trace";
        fail(msg);
      });
    }
  });
  return completer.future;
}

void main() {
  test('cookies', testCookies);
}
