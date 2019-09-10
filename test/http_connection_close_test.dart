// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import "dart:async";
import "dart:io" hide HttpServer, HttpClient;

import "package:http_io/http_io.dart";
import "package:test/test.dart";

Future<Null> testHttp10Close(bool closeRequest) {
  Completer<Null> completer = Completer();
  HttpServer.bind("127.0.0.1", 0).then((server) {
    server.listen((request) {
      request.response.close();
    });

    Socket.connect("127.0.0.1", server.port).then((socket) {
      socket.write("GET / HTTP/1.0\r\n\r\n");
      socket.listen((data) {}, onDone: () {
        if (!closeRequest) socket.destroy();
        server.close();
        completer.complete(null);
      });
      if (closeRequest) socket.close();
    });
  });
  return completer.future;
}

Future<Null> testHttp11Close(bool closeRequest) {
  Completer<Null> completer = Completer();
  HttpServer.bind("127.0.0.1", 0).then((server) {
    server.listen((request) {
      request.response.close();
    });

    Socket.connect("127.0.0.1", server.port).then((socket) {
      socket.write("GET / HTTP/1.1\r\nConnection: close\r\n\r\n");
      socket.listen((data) {}, onDone: () {
        if (!closeRequest) socket.destroy();
        server.close();
        completer.complete(null);
      });
      if (closeRequest) socket.close();
    });
  });
  return completer.future;
}

Future<Null> testStreamResponse() {
  Completer<Null> completer = Completer();
  HttpServer.bind("127.0.0.1", 0).then((server) {
    server.listen((request) {
      var timer = Timer.periodic(const Duration(milliseconds: 0), (_) {
        request.response
            .write('data:${DateTime.now().millisecondsSinceEpoch}\n\n');
      });
      request.response.done.whenComplete(() {
        timer.cancel();
      }).catchError((_) {});
    });

    var client = HttpClient();
    client
        .getUrl(Uri.parse("http://127.0.0.1:${server.port}"))
        .then((request) => request.close())
        .then((response) {
      int bytes = 0;
      response.listen((data) {
        bytes += data.length;
        if (bytes > 100) {
          client.close(force: true);
        }
      }, onError: (error) {
        server.close();
        completer.complete(null);
      });
    });
  });
  return completer.future;
}

main() {
  test('Http10Close', () => testHttp10Close(false));
  test('Http10Close close request', () => testHttp10Close(true));
  test('Http11Close', () => testHttp11Close(false));
  test('Http11Close close request', () => testHttp11Close(true));
  test('StreamResponse', testStreamResponse);
}
