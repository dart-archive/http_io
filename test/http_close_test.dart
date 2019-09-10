// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import "dart:async";
import "dart:math";
import "dart:typed_data";

import "package:http_io/http_io.dart";
import "package:test/test.dart";

Future<Null> testClientAndServerCloseNoListen(int connections) {
  Completer<Null> completer = Completer();
  HttpServer.bind("127.0.0.1", 0).then((server) {
    int closed = 0;
    server.listen((request) {
      request.response.close();
      request.response.done.then((_) {
        closed++;
        if (closed == connections) {
          expect(0, equals(server.connectionsInfo().active));
          expect(server.connectionsInfo().total,
              equals(server.connectionsInfo().idle));
          server.close();
          completer.complete(null);
        }
      });
    });
    var client = HttpClient();
    for (int i = 0; i < connections; i++) {
      client
          .get("127.0.0.1", server.port, "/")
          .then((request) => request.close())
          .then((response) {});
    }
  });
  return completer.future;
}

Future<Null> testClientCloseServerListen(int connections) {
  Completer<Null> completer = Completer();
  HttpServer.bind("127.0.0.1", 0).then((server) {
    int closed = 0;
    void check() {
      closed++;
      if (closed == connections * 2) {
        expect(0, equals(server.connectionsInfo().active));
        expect(server.connectionsInfo().total,
            equals(server.connectionsInfo().idle));
        server.close();
        completer.complete(null);
      }
    }

    server.listen((request) {
      request.listen((_) {}, onDone: () {
        request.response.close();
        request.response.done.then((_) => check());
      });
    });
    var client = HttpClient();
    for (int i = 0; i < connections; i++) {
      client
          .get("127.0.0.1", server.port, "/")
          .then((request) => request.close())
          .then((response) => check());
    }
  });
  return completer.future;
}

Future<Null> testClientCloseSendingResponse(int connections) {
  Completer<Null> completer = Completer();
  var buffer = Uint8List(64 * 1024);
  var rand = Random();
  for (int i = 0; i < buffer.length; i++) {
    buffer[i] = rand.nextInt(256);
  }
  HttpServer.bind("127.0.0.1", 0).then((server) {
    int closed = 0;
    void check() {
      closed++;
      // Wait for both server and client to see the connections as closed.
      if (closed == connections * 2) {
        expect(0, equals(server.connectionsInfo().active));
        expect(server.connectionsInfo().total,
            equals(server.connectionsInfo().idle));
        server.close();
        completer.complete(null);
      }
    }

    server.listen((request) {
      var timer = Timer.periodic(const Duration(milliseconds: 50), (_) {
        request.response.add(buffer);
      });
      request.response.done.catchError((_) {}).whenComplete(() {
        check();
        timer.cancel();
      });
    });
    var client = HttpClient();
    for (int i = 0; i < connections; i++) {
      client
          .get("127.0.0.1", server.port, "/")
          .then((request) => request.close())
          .then((response) {
        // Ensure we don't accept the response until we have send the entire
        // request.
        var subscription = response.listen((_) {});
        Timer(const Duration(milliseconds: 20), () {
          subscription.cancel();
          check();
        });
      });
    }
  });
  return completer.future;
}

Future<Null> testClientCloseWhileSendingRequest(int connections) {
  Completer<Null> completer = Completer();
  HttpServer.bind("127.0.0.1", 0).then((server) async {
    server.listen((request) {
      request.listen((_) {}, onError: (e) {
        // A race may cause the connection to be closed while the server is
        // receiving the insufficient number of bytes.
        expect(e is HttpException, isTrue);
      });
    });
    var client = HttpClient();
    int closed = 0;
    for (int i = 0; i < connections; i++) {
      await client.post("127.0.0.1", server.port, "/").then((request) {
        request.contentLength = 110;
        request.write("0123456789");
        // This triggers an error because fewer bytes were written than
        // specified in contentLength.
        return request.close();
      }).catchError((e) {
        closed++;
        if (closed == connections) {
          server.close();
          completer.complete(null);
        }
      });
    }
  });
  return completer.future;
}

void main() {
  test('ClientAndServerCloseNoListen',
      () => testClientAndServerCloseNoListen(10));
  test('ClientCloseServerListen', () => testClientCloseServerListen(10));
  test('ClientCloseSendingResponse', () => testClientCloseSendingResponse(10));
  test('ClientCloseWhileSendingRequest',
      () => testClientCloseWhileSendingRequest(10));
}
