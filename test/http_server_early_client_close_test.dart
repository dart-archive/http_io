// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import "dart:async";
import "dart:io" show Directory, File, Platform, Socket;
import "dart:isolate";

import 'package:http_io/http_io.dart';
import 'package:test/test.dart';

Future sendData(List<int> data, int port) {
  return Socket.connect("127.0.0.1", port).then((socket) {
    socket.listen((data) {
      fail("No data response was expected");
    });
    socket.add(data);
    return socket.close().then((_) {
      socket.destroy();
    });
  });
}

class EarlyCloseTest {
  EarlyCloseTest(this.data, [this.exception, this.expectRequest = false]);

  Future execute() {
    return HttpServer.bind("127.0.0.1", 0).then((server) {
      Completer c = Completer();

      bool calledOnRequest = false;
      bool calledOnError = false;
      ReceivePort port = ReceivePort();
      var requestCompleter = Completer();
      server.listen((request) {
        expect(expectRequest, isTrue);
        expect(calledOnError, isFalse);
        expect(calledOnRequest, isFalse);
        calledOnRequest = true;
        request.listen((_) {}, onDone: () {
          requestCompleter.complete();
        }, onError: (error) {
          expect(calledOnError, isFalse);
          expect(exception, equals(error.message));
          calledOnError = true;
          if (exception != null) port.close();
        });
      }, onDone: () {
        expect(expectRequest, equals(calledOnRequest));
        if (exception == null) port.close();
        c.complete(null);
      });

      List<int> d;
      if (data is List<int>) d = data;
      if (data is String) d = data.codeUnits;
      if (d == null) fail("Invalid data");
      sendData(d, server.port).then((_) {
        if (!expectRequest) requestCompleter.complete();
        requestCompleter.future.then((_) => server.close());
      });

      return c.future;
    });
  }

  final dynamic data;
  final String exception;
  final bool expectRequest;
}

Future<Null> testEarlyClose1() async {
  List<EarlyCloseTest> tests = List<EarlyCloseTest>();
  void add(Object data, [String exception, bool expectRequest = false]) {
    tests.add(EarlyCloseTest(data, exception, expectRequest));
  }
  // The empty packet is valid.

  // Close while sending header
  add("G");
  add("GET /");
  add("GET / HTTP/1.1");
  add("GET / HTTP/1.1\r\n");

  // Close while sending content
  add("GET / HTTP/1.1\r\nContent-Length: 100\r\n\r\n",
      "Connection closed while receiving data", true);
  add("GET / HTTP/1.1\r\nContent-Length: 100\r\n\r\n1",
      "Connection closed while receiving data", true);

  for (final t in tests) {
    await t.execute();
  }
}

Future<Null> testEarlyClose2() {
  final completer = Completer<Null>();
  HttpServer.bind("127.0.0.1", 0).then((server) {
    server.listen((request) {
      String name =
          "${Directory.current.path}/test/http_server_early_client_close_test.dart";
      if (!File(name).existsSync()) {
        name = Platform.script.toFilePath();
      }
      File(name)
          .openRead()
          .cast<List<int>>()
          .pipe(request.response)
          .catchError((e) {/* ignore */});
    });

    var count = 0;
    makeRequest() {
      Socket.connect("127.0.0.1", server.port).then((socket) {
        var data = "GET / HTTP/1.1\r\nContent-Length: 0\r\n\r\n";
        socket.write(data);
        socket.close();
        socket.done.then((_) {
          socket.destroy();
          if (++count < 10) {
            makeRequest();
          } else {
            scheduleMicrotask(() {
              server.close();
              completer.complete();
            });
          }
        });
      });
    }

    makeRequest();
  });
  return completer.future;
}

Future<Null> testEarlyClose3() {
  final completer = Completer<Null>();
  HttpServer.bind("127.0.0.1", 0).then((server) {
    server.listen((request) {
      StreamSubscription subscription;
      subscription = request.listen((_) {}, onError: (error) {
        // subscription.cancel should not trigger an error.
        subscription.cancel();
        server.close();
        completer.complete();
      });
    });
    Socket.connect("127.0.0.1", server.port).then((socket) {
      socket.write("GET / HTTP/1.1\r\n");
      socket.write("Content-Length: 10\r\n");
      socket.write("\r\n");
      socket.write("data");
      socket.close();
      socket.listen((_) {}, onError: (_) {});
      socket.done.catchError((_) {});
    });
  });
  return completer.future;
}

void main() {
  test('testEarlyClose1', testEarlyClose1);
  test('testEarlyClose2', testEarlyClose2);
  test('testEarlyClose3', testEarlyClose3);
}
