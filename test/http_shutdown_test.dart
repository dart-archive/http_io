// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import "dart:async";
import "dart:io" show SocketException;

import "package:http_io/http_io.dart";
import "package:test/test.dart";

Future<Null> test1(int totalConnections) {
  final completer = Completer<Null>();
  // Server which just closes immediately.
  HttpServer.bind("127.0.0.1", 0).then((server) {
    server.listen((HttpRequest request) {
      request.response.close();
    });

    int count = 0;
    HttpClient client = HttpClient();
    for (int i = 0; i < totalConnections; i++) {
      client
          .get("127.0.0.1", server.port, "/")
          .then((HttpClientRequest request) => request.close())
          .then((HttpClientResponse response) {
        response.listen((_) {}, onDone: () {
          count++;
          if (count == totalConnections) {
            client.close();
            server.close();
            completer.complete();
          }
        });
      });
    }
  });
  return completer.future;
}

Future<Null> test2(int totalConnections, int outputStreamWrites) {
  final completer = Completer<Null>();
  // Server which responds without waiting for request body.
  HttpServer.bind("127.0.0.1", 0).then((server) {
    server.listen((HttpRequest request) {
      request.response.write("!dlrow ,olleH");
      request.response.close();
    });

    int count = 0;
    HttpClient client = HttpClient();
    for (int i = 0; i < totalConnections; i++) {
      client
          .get("127.0.0.1", server.port, "/")
          .then((HttpClientRequest request) {
        request.contentLength = -1;
        for (int i = 0; i < outputStreamWrites; i++) {
          request.write("Hello, world!");
        }
        request.done.catchError((_) {});
        return request.close();
      }).then((HttpClientResponse response) {
        response.listen((_) {}, onDone: () {
          count++;
          if (count == totalConnections) {
            client.close(force: true);
            server.close();
            completer.complete();
          }
        }, onError: (e) {} /* ignore */);
      }).catchError((error) {
        count++;
        if (count == totalConnections) {
          client.close();
          server.close();
          completer.complete();
        }
      });
    }
  });
  return completer.future;
}

Future<Null> test3(int totalConnections) {
  final completer = Completer<Null>();
  // Server which responds when request body has been received.
  HttpServer.bind("127.0.0.1", 0).then((server) {
    server.listen((HttpRequest request) {
      request.listen((_) {}, onDone: () {
        request.response.write("!dlrow ,olleH");
        request.response.close();
      });
    });

    int count = 0;
    HttpClient client = HttpClient();
    for (int i = 0; i < totalConnections; i++) {
      client
          .get("127.0.0.1", server.port, "/")
          .then((HttpClientRequest request) {
        request.contentLength = -1;
        request.write("Hello, world!");
        return request.close();
      }).then((HttpClientResponse response) {
        response.listen((_) {}, onDone: () {
          count++;
          if (count == totalConnections) {
            client.close();
            server.close();
            completer.complete();
          }
        });
      });
    }
  });
  return completer.future;
}

Future<Null> test4() {
  final completer = Completer<Null>();
  HttpServer.bind("127.0.0.1", 0).then((server) {
    server.listen((var request) {
      request.listen((_) {}, onDone: () {
        Timer.periodic(Duration(milliseconds: 100), (timer) {
          if (server.connectionsInfo().total == 0) {
            server.close();
            timer.cancel();
            completer.complete();
          }
        });
        request.response.close();
      });
    });

    var client = HttpClient();
    client
        .get("127.0.0.1", server.port, "/")
        .then((request) => request.close())
        .then((response) {
      response.listen((_) {}, onDone: () {
        client.close();
      });
    });
  });
  return completer.future;
}

Future<Null> test5(int totalConnections) {
  final completer = Completer<Null>();
  HttpServer.bind("127.0.0.1", 0).then((server) {
    server.listen((request) {
      request.listen((_) {}, onDone: () {
        request.response.close();
        request.response.done.catchError((e) {});
      }, onError: (error) {});
    }, onError: (error) {});

    // Create a number of client requests and keep then active. Then
    // close the client and wait for the server to lose all active
    // connections.
    var client = HttpClient();
    client.maxConnectionsPerHost = totalConnections;
    for (int i = 0; i < totalConnections; i++) {
      client
          .post("127.0.0.1", server.port, "/")
          .then((request) {
            request.add([0]);
            // TODO(sgjesse): Make this test work with
            //request.response instead of request.close() return
            //return request.response;
            request.done.catchError((e) {});
            return request.close();
          })
          .then((response) {})
          .catchError((e) {},
              test: (e) => e is HttpException || e is SocketException);
    }
    bool clientClosed = false;
    Timer.periodic(Duration(milliseconds: 100), (timer) {
      if (!clientClosed) {
        if (server.connectionsInfo().total == totalConnections) {
          clientClosed = true;
          client.close(force: true);
        }
      } else {
        if (server.connectionsInfo().total == 0) {
          server.close();
          timer.cancel();
          completer.complete();
        }
      }
    });
  });
  return completer.future;
}

void main() {
  test('test1_1', () => test1(1));
  test('test1_10', () => test1(10));
  test('test2_1_10', () => test2(1, 10));
  test('test2_10_10', () => test2(10, 10));
  test('test2_10_1000', () => test2(10, 1000));
  test('test3_1', () => test3(1));
  test('test3_10', () => test3(10));
  test('test4', () => test4());
  test('test5_1', () => test5(1));
  test('test5_10', () => test5(10));
}
