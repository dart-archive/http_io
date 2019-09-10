// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import "dart:async";
import "dart:io" hide HttpServer, HttpClient, HttpHeaders, HttpRequest;
import "dart:typed_data";

import "package:http_io/http_io.dart";
import "package:test/test.dart";

Future<Null> testDefaultResponseHeaders() {
  checkDefaultHeaders(headers) {
    expect(headers[HttpHeaders.CONTENT_TYPE],
        equals(['text/plain; charset=utf-8']));
    expect(headers['X-Frame-Options'], equals(['SAMEORIGIN']));
    expect(headers['X-Content-Type-Options'], equals(['nosniff']));
    expect(headers['X-XSS-Protection'], equals(['1; mode=block']));
  }

  checkDefaultHeadersClear(headers) {
    expect(headers[HttpHeaders.CONTENT_TYPE], isNull);
    expect(headers['X-Frame-Options'], isNull);
    expect(headers['X-Content-Type-Options'], isNull);
    expect(headers['X-XSS-Protection'], isNull);
  }

  checkDefaultHeadersClearAB(headers) {
    expect(headers[HttpHeaders.CONTENT_TYPE], isNull);
    expect(headers['X-Frame-Options'], isNull);
    expect(headers['X-Content-Type-Options'], isNull);
    expect(headers['X-XSS-Protection'], isNull);
    expect(headers['a'], equals(['b']));
  }

  doTest(bool clearHeaders, Map<String, dynamic> defaultHeaders,
      Function checker) {
    Completer<Null> completer = Completer();
    HttpServer.bind("127.0.0.1", 0).then((server) {
      if (clearHeaders) server.defaultResponseHeaders.clear();
      if (defaultHeaders != null) {
        defaultHeaders.forEach(
            (name, value) => server.defaultResponseHeaders.add(name, value));
      }
      checker(server.defaultResponseHeaders);
      server.listen((request) {
        request.response.close();
      });

      HttpClient client = HttpClient();
      client
          .get("127.0.0.1", server.port, "/")
          .then((request) => request.close())
          .then((response) {
        checker(response.headers);
        server.close();
        client.close();
        completer.complete(null);
      });
    });
    return completer.future;
  }

  return doTest(false, null, checkDefaultHeaders)
      .then((_) => doTest(true, null, checkDefaultHeadersClear))
      .then((_) => doTest(true, {'a': 'b'}, checkDefaultHeadersClearAB));
}

Future<Null> testDefaultResponseHeadersContentType() {
  doTest(bool clearHeaders, String requestBody, List<int> responseBody) {
    Completer<Null> completer = Completer();
    HttpServer.bind("127.0.0.1", 0).then((server) {
      if (clearHeaders) server.defaultResponseHeaders.clear();
      server.listen((request) {
        request.response.write(requestBody);
        request.response.close();
      });

      HttpClient client = HttpClient();
      client
          .get("127.0.0.1", server.port, "/")
          .then((request) => request.close())
          .then((response) {
        response.fold([], (a, b) => a..addAll(b)).then((body) {
          expect(body, equals(responseBody));
        }).whenComplete(() {
          server.close();
          client.close();
          completer.complete(null);
        });
      });
    });
    return completer.future;
  }

  return doTest(false, 'æøå', [195, 166, 195, 184, 195, 165])
      .then((_) => doTest(true, 'æøå', [230, 248, 229]));
}

Future<Null> testListenOn() {
  Completer<Null> completer = Completer();
  ServerSocket socket;
  HttpServer server;

  void doTest(void onDone()) {
    expect(socket.port, equals(server.port));

    HttpClient client = HttpClient();
    client.get("127.0.0.1", socket.port, "/").then((request) {
      return request.close();
    }).then((response) {
      response.listen((_) {}, onDone: () {
        client.close();
        onDone();
      });
    }).catchError((e, trace) {
      String msg = "Unexpected error in Http Client: $e";
      if (trace != null) msg += "\nStackTrace: $trace";
      fail(msg);
    });
  }

  // Test two connection after each other.
  ServerSocket.bind("127.0.0.1", 0).then((s) {
    socket = s;
    server = HttpServer.listenOn(socket);
    expect(server.address.address, equals('127.0.0.1'));
    expect(server.address.host, equals('127.0.0.1'));
    server.listen((HttpRequest request) {
      request.listen((_) {}, onDone: () => request.response.close());
    });

    doTest(() {
      doTest(() {
        server.close();
        expect(() => server.port, throwsException);
        expect(() => server.address, throwsException);
        socket.close();
        completer.complete(null);
      });
    });
  });
  return completer.future;
}

Future<Null> testHttpServerZone() {
  Completer<Null> completer = Completer();
  Zone parent = Zone.current;
  runZoned(() {
    expect(parent, isNot(equals(Zone.current)));
    HttpServer.bind("127.0.0.1", 0).then((server) {
      expect(parent, isNot(equals(Zone.current)));
      server.listen((request) {
        expect(parent, isNot(equals(Zone.current)));
        request.response.close();
        server.close();
      });
      HttpClient()
          .get("127.0.0.1", server.port, '/')
          .then((request) => request.close())
          .then((response) => response.drain())
          .then((_) => completer.complete(null));
    });
  });
  return completer.future;
}

Future<Null> testHttpServerZoneError() {
  Completer<Null> completer = Completer();
  Zone parent = Zone.current;
  runZoned(() {
    expect(parent, isNot(equals(Zone.current)));
    HttpServer.bind("127.0.0.1", 0).then((server) {
      expect(parent, isNot(equals(Zone.current)));
      server.listen((request) {
        expect(parent, isNot(equals(Zone.current)));
        request.listen((_) {}, onError: (error) {
          expect(parent, isNot(equals(Zone.current)));
          server.close();
          throw error;
        });
      });
      Socket.connect("127.0.0.1", server.port).then((socket) {
        socket.write('GET / HTTP/1.1\r\nContent-Length: 100\r\n\r\n');
        socket.write('some body');
        socket.close();
        socket.listen(null);
      });
    });
  }, onError: (e) {
    completer.complete(null);
  });
  return completer.future;
}

Future<Null> testHttpServerClientClose() {
  Completer<Null> completer = Completer();
  HttpServer.bind("127.0.0.1", 0).then((server) {
    runZoned(() {
      server.listen((request) {
        request.response.bufferOutput = false;
        request.response.add(Uint8List(64 * 1024));
        Timer(const Duration(milliseconds: 100), () {
          request.response.close().then((_) {
            server.close();
            completer.complete(null);
          });
        });
      });
    }, onError: (e, s) {
      fail("Unexpected error: $e(${e.hashCode})\n$s");
    });
    var client = HttpClient();
    client
        .get("127.0.0.1", server.port, "/")
        .then((request) => request.close())
        .then((response) {
      response.listen((_) {}).cancel();
    });
  });
  return completer.future;
}

void main() {
  test("DefaultResponseHeaders", () async {
    await testDefaultResponseHeaders();
  });
  test("DefaultResponseHeadersContentType", () async {
    await testDefaultResponseHeadersContentType();
  });
  test("ListenOn", () async {
    await testListenOn();
  });
  test("HttpServerZone", () async {
    await testHttpServerZone();
  });
  test("HttpServerZoneError", () async {
    await testHttpServerZoneError();
  });
  test("HttpServerClientClose", () async {
    await testHttpServerClientClose();
  });
}
