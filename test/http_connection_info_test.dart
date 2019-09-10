// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import "dart:async";
import "dart:io" show InternetAddress;
import "package:http_io/http_io.dart";
import "package:test/test.dart";

Future<Null> testHttpConnectionInfo() {
  final completer = Completer<Null>();
  HttpServer.bind("0.0.0.0", 0).then((server) {
    int clientPort;

    server.listen((request) {
      var response = request.response;
      expect(request.connectionInfo.remoteAddress is InternetAddress, isTrue);
      expect(response.connectionInfo.remoteAddress is InternetAddress, isTrue);
      expect(request.connectionInfo.localPort, equals(server.port));
      expect(response.connectionInfo.localPort, equals(server.port));
      expect(clientPort, isNotNull);
      expect(request.connectionInfo.remotePort, equals(clientPort));
      expect(response.connectionInfo.remotePort, equals(clientPort));
      request.listen((_) {}, onDone: () {
        request.response.close();
      });
    });

    HttpClient client = HttpClient();
    client.get("127.0.0.1", server.port, "/").then((request) {
      expect(request.connectionInfo.remoteAddress is InternetAddress, isTrue);
      expect(request.connectionInfo.remotePort, equals(server.port));
      clientPort = request.connectionInfo.localPort;
      return request.close();
    }).then((response) {
      expect(server.port, equals(response.connectionInfo.remotePort));
      expect(clientPort, equals(response.connectionInfo.localPort));
      response.listen((_) {}, onDone: () {
        client.close();
        server.close();
        completer.complete();
      });
    });
  });
  return completer.future;
}

void main() {
  test('HttpConnectionInfo', () => testHttpConnectionInfo());
}
