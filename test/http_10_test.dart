// (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import "dart:io" hide HttpServer, HttpClient, HttpRequest, HttpException;

import "package:http_io/http_io.dart";
import "package:test/test.dart";

// Client makes a HTTP 1.0 request without connection keep alive. The
// server sets a content length but still needs to close the
// connection as there is no keep alive.
Future<Null> testHttp10NoKeepAlive() {
  Completer<Null> completer = Completer();
  HttpServer.bind("127.0.0.1", 0).then((server) {
    server.listen((HttpRequest request) {
      expect(request.headers.value('content-length'), isNull);
      expect(-1, equals(request.contentLength));
      var response = request.response;
      response.contentLength = 1;
      expect("1.0", equals(request.protocolVersion));
      response.done
          .then((_) => fail("Unexpected response completion"))
          .catchError((error) => expect((error is HttpException), isTrue));
      response.write("Z");
      response.write("Z");
      response.close();
    }, onError: (e, trace) {
      String msg = "Unexpected error $e";
      if (trace != null) msg += "\nStackTrace: $trace";
      fail(msg);
    });

    int count = 0;
    makeRequest() {
      Socket.connect("127.0.0.1", server.port).then((socket) {
        socket.write("GET / HTTP/1.0\r\n\r\n");

        List<int> response = [];
        socket.listen(response.addAll, onDone: () {
          count++;
          socket.destroy();
          String s = String.fromCharCodes(response).toLowerCase();
          expect(-1, equals(s.indexOf("keep-alive")));
          if (count < 10) {
            makeRequest();
          } else {
            server.close();
            completer.complete(null);
          }
        });
      });
    }

    makeRequest();
  });
  return completer.future;
}

// Client makes a HTTP 1.0 request and the server does not set a
// content length so it has to close the connection to mark the end of
// the response.
Future<Null> testHttp10ServerClose() {
  Completer<Null> completer = Completer();
  HttpServer.bind("127.0.0.1", 0).then((server) {
    server.listen((HttpRequest request) {
      expect(request.headers.value('content-length'), isNull);
      expect(-1, equals(request.contentLength));
      request.listen((_) {}, onDone: () {
        var response = request.response;
        expect("1.0", equals(request.protocolVersion));
        response.write("Z");
        response.close();
      });
    }, onError: (e, trace) {
      String msg = "Unexpected error $e";
      if (trace != null) msg += "\nStackTrace: $trace";
      fail(msg);
    });

    int count = 0;
    makeRequest() {
      Socket.connect("127.0.0.1", server.port).then((socket) {
        socket.write("GET / HTTP/1.0\r\n");
        socket.write("Connection: Keep-Alive\r\n\r\n");

        List<int> response = [];
        socket.listen(response.addAll,
            onDone: () {
              socket.destroy();
              count++;
              String s = String.fromCharCodes(response).toLowerCase();
              expect("z", equals(s[s.length - 1]));
              expect(-1, equals(s.indexOf("content-length:")));
              expect(-1, equals(s.indexOf("keep-alive")));
              if (count < 10) {
                makeRequest();
              } else {
                server.close();
                completer.complete(null);
              }
            },
            onError: (e) => print(e));
      });
    }

    makeRequest();
  });
  return completer.future;
}

// Client makes a HTTP 1.0 request with connection keep alive. The
// server sets a content length so the persistent connection can be
// used.
Future<Null> testHttp10KeepAlive() {
  Completer<Null> completer = Completer();
  HttpServer.bind("127.0.0.1", 0).then((server) {
    server.listen((HttpRequest request) {
      expect(request.headers.value('content-length'), isNull);
      expect(-1, equals(request.contentLength));
      var response = request.response;
      response.contentLength = 1;
      response.persistentConnection = true;
      expect("1.0", equals(request.protocolVersion));
      response.write("Z");
      response.close();
    }, onError: (e, trace) {
      String msg = "Unexpected error $e";
      if (trace != null) msg += "\nStackTrace: $trace";
      fail(msg);
    });

    Socket.connect("127.0.0.1", server.port).then((socket) {
      void sendRequest() {
        socket.write("GET / HTTP/1.0\r\n");
        socket.write("Connection: Keep-Alive\r\n\r\n");
      }

      List<int> response = [];
      int count = 0;
      socket.listen((d) {
        response.addAll(d);
        if (response[response.length - 1] == "Z".codeUnitAt(0)) {
          String s = String.fromCharCodes(response).toLowerCase();
          expect(s.indexOf("\r\nconnection: keep-alive\r\n") > 0, isTrue);
          expect(s.indexOf("\r\ncontent-length: 1\r\n") > 0, isTrue);
          count++;
          if (count < 10) {
            response = [];
            sendRequest();
          } else {
            socket.close();
          }
        }
      }, onDone: () {
        socket.destroy();
        server.close();
        completer.complete(null);
      });
      sendRequest();
    });
  });
  return completer.future;
}

// Client makes a HTTP 1.0 request with connection keep alive. The
// server does not set a content length so it cannot honor connection
// keep alive.
Future<Null> testHttp10KeepAliveServerCloses() {
  Completer<Null> completer = Completer();
  HttpServer.bind("127.0.0.1", 0).then((server) {
    server.listen((HttpRequest request) {
      expect(request.headers.value('content-length'), isNull);
      expect(-1, equals(request.contentLength));
      var response = request.response;
      expect("1.0", equals(request.protocolVersion));
      response.write("Z");
      response.close();
    }, onError: (e, trace) {
      String msg = "Unexpected error $e";
      if (trace != null) msg += "\nStackTrace: $trace";
      fail(msg);
    });

    int count = 0;
    makeRequest() {
      Socket.connect("127.0.0.1", server.port).then((socket) {
        socket.write("GET / HTTP/1.0\r\n");
        socket.write("Connection: Keep-Alive\r\n\r\n");

        List<int> response = [];
        socket.listen(response.addAll, onDone: () {
          socket.destroy();
          count++;
          String s = String.fromCharCodes(response).toLowerCase();
          expect("z", equals(s[s.length - 1]));
          expect(-1, equals(s.indexOf("content-length")));
          expect(-1, equals(s.indexOf("connection")));
          if (count < 10) {
            makeRequest();
          } else {
            server.close();
            completer.complete(null);
          }
        });
      });
    }

    makeRequest();
  });
  return completer.future;
}

void main() {
  test("Http10NoKeepAlive", () async {
    await testHttp10NoKeepAlive();
  });
  test("Http10ServerClose", () async {
    await testHttp10ServerClose();
  });
  test("Http10KeepAlive", () async {
    await testHttp10KeepAlive();
  });
  test("Http10KeepAliveServerCloses", () async {
    await testHttp10KeepAliveServerCloses();
  });
}
