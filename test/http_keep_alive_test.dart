// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import "dart:async";

import 'package:http_io/http_io.dart';
import 'package:test/test.dart';

Future<void> getData(HttpClient client, int port, bool chunked, int length) {
  return client
      .get("127.0.0.1", port, "/?chunked=$chunked&length=$length")
      .then((request) => request.close())
      .then((response) {
    return response.fold(0, (bytes, data) => bytes + data.length).then((bytes) {
      expect(length, equals(bytes));
    });
  });
}

Future<HttpServer> startServer() {
  return HttpServer.bind("127.0.0.1", 0).then((server) {
    server.listen((request) {
      bool chunked = request.uri.queryParameters["chunked"] == "true";
      int length = int.parse(request.uri.queryParameters["length"]);
      var buffer = List<int>.filled(length, 0);
      if (!chunked) request.response.contentLength = length;
      request.response.add(buffer);
      request.response.close();
    });
    return server;
  });
}

Future<Null> testKeepAliveNonChunked() {
  final completer = Completer<Null>();
  startServer().then((server) {
    var client = HttpClient();

    getData(client, server.port, false, 100)
        .then((_) => getData(client, server.port, false, 100))
        .then((_) => getData(client, server.port, false, 100))
        .then((_) => getData(client, server.port, false, 100))
        .then((_) => getData(client, server.port, false, 100))
        .then((_) {
      server.close();
      client.close();
      completer.complete();
    });
  });
  return completer.future;
}

Future<Null> testKeepAliveChunked() {
  final completer = Completer<Null>();
  startServer().then((server) {
    var client = HttpClient();

    getData(client, server.port, true, 100)
        .then((_) => getData(client, server.port, true, 100))
        .then((_) => getData(client, server.port, true, 100))
        .then((_) => getData(client, server.port, true, 100))
        .then((_) => getData(client, server.port, true, 100))
        .then((_) {
      server.close();
      client.close();
      completer.complete();
    });
  });
  return completer.future;
}

Future<Null> testKeepAliveMixed() {
  final completer = Completer<Null>();
  startServer().then((server) {
    var client = HttpClient();

    getData(client, server.port, true, 100)
        .then((_) => getData(client, server.port, false, 100))
        .then((_) => getData(client, server.port, true, 100))
        .then((_) => getData(client, server.port, false, 100))
        .then((_) => getData(client, server.port, true, 100))
        .then((_) => getData(client, server.port, false, 100))
        .then((_) => getData(client, server.port, true, 100))
        .then((_) => getData(client, server.port, false, 100))
        .then((_) {
      server.close();
      client.close();
      completer.complete();
    });
  });
  return completer.future;
}

void main() {
  test('keepAliveNonChunked', testKeepAliveNonChunked);
  test('keepAliveChunked', testKeepAliveChunked);
  test('keepAliveMixed', testKeepAliveMixed);
}
