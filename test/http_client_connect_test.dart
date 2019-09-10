// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import "package:http_io/http_io.dart";
import "package:test/test.dart";

Future<Null> testGetEmptyRequest() {
  Completer<Null> completer = Completer();
  HttpServer.bind("127.0.0.1", 0).then((server) {
    server.listen((request) {
      request.pipe(request.response);
    });

    var client = HttpClient();
    client
        .get("127.0.0.1", server.port, "/")
        .then((request) => request.close())
        .then((response) {
      response.listen((data) {}, onDone: () {
        server.close();
        completer.complete(null);
      });
    });
  });
  return completer.future;
}

Future<Null> testGetDataRequest() {
  Completer<Null> completer = Completer();
  HttpServer.bind("127.0.0.1", 0).then((server) {
    var data = "lalala".codeUnits;
    server.listen((request) {
      request.response.add(data);
      request.pipe(request.response);
    });

    var client = HttpClient();
    client
        .get("127.0.0.1", server.port, "/")
        .then((request) => request.close())
        .then((response) {
      int count = 0;
      response.listen((data) => count += data.length, onDone: () {
        server.close();
        expect(data.length, equals(count));
        completer.complete(null);
      });
    });
  });
  return completer.future;
}

Future<Null> testGetInvalidHost() {
  Completer<Null> completer = Completer();
  var client = HttpClient();
  client.get("__SOMETHING_INVALID__", 8888, "/").catchError((error) {
    client.close();
    completer.complete(null);
  });
  return completer.future;
}

Future<Null> testGetServerClose() {
  Completer<Null> completer = Completer();
  HttpServer.bind("127.0.0.1", 0).then((server) {
    server.listen((request) {
      server.close();
      Timer(const Duration(milliseconds: 100), () {
        request.response.close();
      });
    });

    var client = HttpClient();
    client
        .get("127.0.0.1", server.port, "/")
        .then((request) => request.close())
        .then((response) => response.drain())
        .then((_) => completer.complete(null));
  });
  return completer.future;
}

Future<Null> testGetServerCloseNoKeepAlive() {
  Completer<Null> completer = Completer();
  var client = HttpClient();
  HttpServer.bind("127.0.0.1", 0).then((server) {
    int port = server.port;
    server.first.then((request) => request.response.close());

    client
        .get("127.0.0.1", port, "/")
        .then((request) => request.close())
        .then((response) => response.drain())
        .then((_) => client.get("127.0.0.1", port, "/"))
        .then((request) => request.close())
        .then((_) => fail('should not succeed'), onError: (_) {})
        .then((_) => completer.complete(null));
  });
  return completer.future;
}

Future<Null> testGetServerForceClose() {
  Completer<Null> completer = Completer();
  HttpServer.bind("127.0.0.1", 0).then((server) {
    server.listen((request) {
      server.close(force: true);
    });

    var client = HttpClient();
    client
        .get("127.0.0.1", server.port, "/")
        .then((request) => request.close())
        .then((response) {
      fail("Request not expected");
    }).catchError((error) => completer.complete(null),
            test: (error) => error is HttpException);
  });
  return completer.future;
}

Future<Null> testGetDataServerForceClose() {
  Completer<Null> testCompleter = Completer();
  var completer = Completer();
  HttpServer.bind("127.0.0.1", 0).then((server) {
    server.listen((request) {
      request.response.bufferOutput = false;
      request.response.contentLength = 100;
      request.response.write("data");
      request.response.write("more data");
      completer.future.then((_) => server.close(force: true));
    });

    var client = HttpClient();
    client
        .get("127.0.0.1", server.port, "/")
        .then((request) => request.close())
        .then((response) {
      // Close the (incomplete) response, now that we have seen
      // the response object.
      completer.complete(null);
      int errors = 0;
      response.listen((data) {},
          onError: (error) => errors++,
          onDone: () {
            expect(1, equals(errors));
            testCompleter.complete(null);
          });
    });
  });
  return testCompleter.future;
}

typedef Callback1 = Future<HttpClientRequest> Function(
    String a1, int a2, String a3);
Future<Null> testOpenEmptyRequest() async {
  var client = HttpClient();
  var methods = [
    [client.get, 'GET'],
    [client.post, 'POST'],
    [client.put, 'PUT'],
    [client.delete, 'DELETE'],
    [client.patch, 'PATCH'],
    [client.head, 'HEAD']
  ];

  for (var method in methods) {
    Completer<Null> completer = Completer();
    await HttpServer.bind("127.0.0.1", 0).then((server) {
      server.listen((request) {
        expect(method[1], equals(request.method));
        request.pipe(request.response);
      });

      Callback1 cb = method[0] as Callback1;
      cb("127.0.0.1", server.port, "/")
          .then((request) => request.close())
          .then((response) {
        response.listen((data) {}, onDone: () {
          server.close();
          completer.complete(null);
        });
      });
    });
    await completer.future;
  }
}

typedef Callback2 = Future<HttpClientRequest> Function(Uri a1);
Future<Null> testOpenUrlEmptyRequest() async {
  var client = HttpClient();
  var methods = [
    [client.getUrl, 'GET'],
    [client.postUrl, 'POST'],
    [client.putUrl, 'PUT'],
    [client.deleteUrl, 'DELETE'],
    [client.patchUrl, 'PATCH'],
    [client.headUrl, 'HEAD']
  ];

  for (var method in methods) {
    Completer<Null> completer = Completer();
    await HttpServer.bind("127.0.0.1", 0).then((server) {
      server.listen((request) {
        expect(method[1], equals(request.method));
        request.pipe(request.response);
      });

      Callback2 cb = method[0] as Callback2;
      cb(Uri.parse("http://127.0.0.1:${server.port}/"))
          .then((request) => request.close())
          .then((response) {
        response.listen((data) {}, onDone: () {
          server.close();
          completer.complete(null);
        });
      });
    });
    await completer.future;
  }
}

Future<Null> testNoBuffer() {
  Completer<Null> completer = Completer();
  HttpServer.bind("127.0.0.1", 0).then((server) {
    HttpResponse response;
    server.listen((request) {
      response = request.response;
      response.bufferOutput = false;
      response.writeln('init');
    });

    var client = HttpClient();
    client
        .get("127.0.0.1", server.port, "/")
        .then((request) => request.close())
        .then((clientResponse) {
      var iterator = StreamIterator(
          clientResponse.transform(utf8.decoder).transform(LineSplitter()));
      iterator.moveNext().then((hasValue) {
        expect(hasValue, isTrue);
        expect('init', equals(iterator.current));
        int count = 0;
        void run() {
          if (count == 10) {
            response.close();
            iterator.moveNext().then((hasValue) {
              expect(hasValue, isFalse);
              server.close();
              completer.complete(null);
            });
          } else {
            response.writeln('output$count');
            iterator.moveNext().then((hasValue) {
              expect(hasValue, isTrue);
              expect('output$count', equals(iterator.current));
              count++;
              run();
            });
          }
        }

        run();
      });
    });
  });
  return completer.future;
}

Future<Null> testMaxConnectionsPerHost(int connectionCap, int connections) {
  Completer<Null> completer = Completer();
  HttpServer.bind("127.0.0.1", 0).then((server) {
    int handled = 0;
    server.listen((request) {
      expect(server.connectionsInfo().total <= connectionCap, isTrue);
      request.response.close();
      handled++;
      if (handled == connections) {
        server.close();
        completer.complete(null);
      }
    });

    var client = HttpClient();
    client.maxConnectionsPerHost = connectionCap;
    for (int i = 0; i < connections; i++) {
      client
          .get("127.0.0.1", server.port, "/")
          .then((request) => request.close())
          .then((response) {
        response.listen(null);
      });
    }
  });
  return completer.future;
}

void main() {
  test("GetEmptyRequest", testGetEmptyRequest);
  test("GetDataRequest", testGetDataRequest);
  test("GetInvalidHost", testGetInvalidHost);
  test("GetServerClose", testGetServerClose);
  test("GetServerCloseNoKeepAlive", testGetServerCloseNoKeepAlive);
  test("GetServerForceClose", testGetServerForceClose);
  test("GetDataServerForceClose", testGetDataServerForceClose);
  test("OpenEmptyRequest", testOpenEmptyRequest);
  test("OpenUrlEmptyRequest", testOpenUrlEmptyRequest);
  test("NoBuffer", testNoBuffer);
  test("MaxConnectionsPerHost", () => testMaxConnectionsPerHost(1, 1));
  test("MaxConnectionsPerHost", () => testMaxConnectionsPerHost(1, 10));
  test("MaxConnectionsPerHost", () => testMaxConnectionsPerHost(5, 10));
  test("MaxConnectionsPerHost", () => testMaxConnectionsPerHost(10, 50));
}
