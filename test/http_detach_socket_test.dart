// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io' show ServerSocket, Socket;

import 'package:http_io/http_io.dart';
import 'package:test/test.dart';

Future<Null> testServerDetachSocket() {
  final completer = Completer<Null>();
  HttpServer.bind("127.0.0.1", 0).then((server) {
    server.defaultResponseHeaders.clear();
    server.serverHeader = null;
    server.listen((request) {
      var response = request.response;
      response.contentLength = 0;
      response.detachSocket().then((socket) {
        expect(socket, isNotNull);
        var body = StringBuffer();
        socket.listen((data) => body.write(String.fromCharCodes(data)),
            onDone: () => expect("Some data", body.toString()));
        socket.write("Test!");
        socket.close();
      });
      server.close();
      completer.complete();
    });

    Socket.connect("127.0.0.1", server.port).then((socket) {
      socket.write("GET / HTTP/1.1\r\n"
          "content-length: 0\r\n\r\n"
          "Some data");
      var body = StringBuffer();
      socket.listen((data) => body.write(String.fromCharCodes(data)),
          onDone: () {
        expect(
            "HTTP/1.1 200 OK\r\n"
            "content-length: 0\r\n"
            "\r\n"
            "Test!",
            body.toString());
        socket.close();
      });
    });
  });
  return completer.future;
}

Future<Null> testServerDetachSocketNoWriteHeaders() {
  final completer = Completer<Null>();
  HttpServer.bind("127.0.0.1", 0).then((server) {
    server.listen((request) {
      var response = request.response;
      response.contentLength = 0;
      response.detachSocket(writeHeaders: false).then((socket) {
        expect(socket, isNotNull);
        var body = StringBuffer();
        socket.listen((data) => body.write(String.fromCharCodes(data)),
            onDone: () => expect("Some data", body.toString()));
        socket.write("Test!");
        socket.close();
      });
      server.close();
      completer.complete();
    });

    Socket.connect("127.0.0.1", server.port).then((socket) {
      socket.write("GET / HTTP/1.1\r\n"
          "content-length: 0\r\n\r\n"
          "Some data");
      var body = StringBuffer();
      socket.listen((data) => body.write(String.fromCharCodes(data)),
          onDone: () {
        expect("Test!", body.toString());
        socket.close();
      });
    });
  });
  return completer.future;
}

Future<Null> testBadServerDetachSocket() {
  final completer = Completer<Null>();
  HttpServer.bind("127.0.0.1", 0).then((server) {
    server.listen((request) {
      var response = request.response;
      response.contentLength = 0;
      response.close();
      expect(response.detachSocket, throwsA(TypeMatcher<StateError>()));
      server.close();
      completer.complete();
    });

    Socket.connect("127.0.0.1", server.port).then((socket) {
      socket.write("GET / HTTP/1.1\r\n"
          "content-length: 0\r\n\r\n");
      socket.listen((_) {}, onDone: () {
        socket.close();
      });
    });
  });
  return completer.future;
}

Future<Null> testClientDetachSocket() {
  final completer = Completer<Null>();
  ServerSocket.bind("127.0.0.1", 0).then((server) {
    server.listen((socket) {
      int port = server.port;
      socket.write("HTTP/1.1 200 OK\r\n"
          "\r\n"
          "Test!");
      var body = StringBuffer();
      socket.listen((data) => body.write(String.fromCharCodes(data)),
          onDone: () {
        List<String> lines = body.toString().split("\r\n");
        expect(6, lines.length);
        expect("GET / HTTP/1.1", lines[0]);
        expect("", lines[4]);
        expect("Some data", lines[5]);
        lines.sort(); // Lines 1-3 becomes 3-5 in a fixed order.
        expect("accept-encoding: gzip", lines[3]);
        expect("content-length: 0", lines[4]);
        expect("host: 127.0.0.1:$port", lines[5]);
        socket.close();
      });
      server.close();
      completer.complete();
    });

    var client = HttpClient();
    client.userAgent = null;
    client
        .get("127.0.0.1", server.port, "/")
        .then((request) => request.close())
        .then((response) {
      response.detachSocket().then((socket) {
        var body = StringBuffer();
        socket.listen((data) => body.write(String.fromCharCodes(data)),
            onDone: () {
          expect("Test!", body.toString());
          client.close();
        });
        socket.write("Some data");
        socket.close();
      });
    });
  });
  return completer.future;
}

Future<Null> testUpgradedConnection() {
  final completer = Completer<Null>();
  HttpServer.bind("127.0.0.1", 0).then((server) {
    server.listen((request) {
      request.response.headers.set('connection', 'upgrade');
      if (request.headers.value('upgrade') == 'mine') {
        request.response.detachSocket().then((socket) {
          socket.cast<List<int>>().pipe(socket).then((_) {});
        });
      } else {
        request.response.close();
      }
    });

    var client = HttpClient();
    client.userAgent = null;
    client.get("127.0.0.1", server.port, "/").then((request) {
      request.headers.set('upgrade', 'mine');
      return request.close();
    }).then((response) {
      client.get("127.0.0.1", server.port, "/").then((request) {
        response.detachSocket().then((socket) {
          // We are testing that we can detach the socket, even though
          // we made a new connection (testing it was not reused).
          request.close().then((response) {
            response.listen(null, onDone: () {
              server.close();
              completer.complete();
            });
            socket.add([0]);
            socket.close();
            socket.fold([], (l, d) => l..addAll(d)).then((data) {
              expect([0], data);
            });
          });
        });
      });
    });
  });
  return completer.future;
}

void main() {
  test('serverDetachSocket', testServerDetachSocket);
  test(
      'serverDetachSocketNoWriteHeaders', testServerDetachSocketNoWriteHeaders);
  test('badServerDetachSocket', testBadServerDetachSocket);
  test('clientDetachSocket', testClientDetachSocket);
  test('upgradedConnection', testUpgradedConnection);
}
