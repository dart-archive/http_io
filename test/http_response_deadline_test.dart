// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import "dart:async";
import "dart:io" show BytesBuilder;

import 'package:http_io/http_io.dart';
import 'package:test/test.dart';

Future<Null> testSimpleDeadline(int connections) {
  final completer = Completer<Null>();
  HttpServer.bind('localhost', 0).then((server) {
    server.listen((request) {
      request.response.deadline = const Duration(seconds: 1000);
      request.response.write("stuff");
      request.response.close();
    });

    var futures = <Future>[];
    var client = HttpClient();
    for (int i = 0; i < connections; i++) {
      futures.add(client
          .get('localhost', server.port, '/')
          .then((request) => request.close())
          .then((response) => response.drain()));
    }
    Future.wait(futures).then((_) {
      server.close();
      completer.complete();
    });
  });
  return completer.future;
}

Future<Null> testExceedDeadline(int connections) {
  final completer = Completer<Null>();
  HttpServer.bind('localhost', 0).then((server) {
    server.listen((request) {
      request.response.deadline = const Duration(milliseconds: 100);
      request.response.contentLength = 10000;
      request.response.write("stuff");
    });

    var futures = <Future>[];
    var client = HttpClient();
    for (int i = 0; i < connections; i++) {
      futures.add(client
          .get('localhost', server.port, '/')
          .then((request) => request.close())
          .then((response) => response.drain())
          .then((_) {
        fail("Expected error");
      }, onError: (e) {
        // expect error.
      }));
    }
    Future.wait(futures).then((_) {
      server.close();
      completer.complete();
    });
  });
  return completer.future;
}

Future<Null> testDeadlineAndDetach(int connections) {
  final completer = Completer<Null>();
  HttpServer.bind('localhost', 0).then((server) {
    server.listen((request) {
      request.response.deadline = const Duration(milliseconds: 0);
      request.response.contentLength = 5;
      request.response.persistentConnection = false;
      request.response.detachSocket().then((socket) {
        Timer(const Duration(milliseconds: 100), () {
          socket.write('stuff');
          socket.close();
          socket.listen(null);
        });
      });
    });

    var futures = <Future>[];
    var client = HttpClient();
    for (int i = 0; i < connections; i++) {
      futures.add(client
          .get('localhost', server.port, '/')
          .then((request) => request.close())
          .then((response) {
        return response
            .fold(BytesBuilder(), (b, d) => b..add(d))
            .then((builder) {
          expect('stuff', equals(String.fromCharCodes(builder.takeBytes())));
        });
      }));
    }
    Future.wait(futures).then((_) {
      server.close();
      completer.complete();
    });
  });
  return completer.future;
}

void main() {
  test('simpleDeadline', () => testSimpleDeadline(10));
  test('exceedDeadline', () => testExceedDeadline(10));
  test('deadlineAndDetach', () => testDeadlineAndDetach(10));
}
