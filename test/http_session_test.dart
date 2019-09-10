// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:http_io/http_io.dart';
import 'package:test/test.dart';

const SESSION_ID = "DARTSESSID";

String getSessionId(List<Cookie> cookies) {
  var id = cookies.fold(null, (last, cookie) {
    if (last != null) return last;
    if (cookie.name.toUpperCase() == SESSION_ID) {
      expect(cookie.httpOnly, isTrue);
      return cookie.value;
    }
    return null;
  });
  expect(id, isNotNull);
  return id;
}

Future<String> connectGetSession(HttpClient client, int port,
    [String session]) {
  return client.get("127.0.0.1", port, "/").then((request) {
    if (session != null) {
      request.cookies.add(Cookie(SESSION_ID, session));
    }
    return request.close();
  }).then((response) {
    return response.fold(getSessionId(response.cookies), (v, _) => v);
  });
}

Future<Null> testSessions(int sessionCount) {
  final completer = Completer<Null>();
  var client = HttpClient();
  HttpServer.bind("127.0.0.1", 0).then((server) {
    var sessions = Set();
    server.listen((request) {
      sessions.add(request.session.id);
      request.response.close();
    });

    var futures = <Future>[];
    for (int i = 0; i < sessionCount; i++) {
      futures.add(connectGetSession(client, server.port).then((session) {
        expect(session, isNotNull);
        expect(sessions.contains(session), isTrue);
        return connectGetSession(client, server.port, session).then((session2) {
          expect(session2, equals(session));
          expect(sessions.contains(session2), isTrue);
          return session2;
        });
      }));
    }
    Future.wait(futures).then((clientSessions) {
      expect(sessions.length, equals(sessionCount));
      expect(Set.from(clientSessions), equals(sessions));
      server.close();
      client.close();
      completer.complete();
    });
  });
  return completer.future;
}

Future<Null> testTimeout(int sessionCount) {
  final completer = Completer<Null>();
  var client = HttpClient();
  HttpServer.bind("127.0.0.1", 0).then((server) {
    server.sessionTimeout = 1;
    var timeouts = <Future>[];
    server.listen((request) {
      var c = Completer();
      timeouts.add(c.future);
      request.session.onTimeout = () {
        c.complete(null);
      };
      request.response.close();
    });

    var futures = <Future>[];
    for (int i = 0; i < sessionCount; i++) {
      futures.add(connectGetSession(client, server.port));
    }
    Future.wait(futures).then((clientSessions) {
      Future.wait(timeouts).then((_) {
        futures = <Future>[];
        for (var id in clientSessions) {
          futures
              .add(connectGetSession(client, server.port, id).then((session) {
            expect(session, isNotNull);
            expect(id == session, isFalse);
          }));
        }
        Future.wait(futures).then((_) {
          server.close();
          client.close();
          completer.complete();
        });
      });
    });
  });
  return completer.future;
}

Future<Null> testSessionsData() {
  final completer = Completer<Null>();
  HttpServer.bind("127.0.0.1", 0).then((server) {
    bool firstHit = false;
    bool secondHit = false;
    server.listen((request) {
      var session = request.session;
      if (session.isNew) {
        expect(firstHit, isFalse);
        expect(secondHit, isFalse);
        firstHit = true;
        session["data"] = "some data";
      } else {
        expect(firstHit, isTrue);
        expect(secondHit, isFalse);
        secondHit = true;
        expect(session.containsKey("data"), isTrue);
        expect("some data", equals(session["data"]));
      }
      request.response.close();
    });

    var client = HttpClient();
    client
        .get("127.0.0.1", server.port, "/")
        .then((request) => request.close())
        .then((response) {
      response.listen((_) {}, onDone: () {
        var id = getSessionId(response.cookies);
        expect(id, isNotNull);
        client.get("127.0.0.1", server.port, "/").then((request) {
          request.cookies.add(Cookie(SESSION_ID, id));
          return request.close();
        }).then((response) {
          response.listen((_) {}, onDone: () {
            expect(firstHit, isTrue);
            expect(secondHit, isTrue);
            expect(id, equals(getSessionId(response.cookies)));
            server.close();
            client.close();
            completer.complete();
          });
        });
      });
    });
  });
  return completer.future;
}

Future<Null> testSessionsDestroy() {
  final completer = Completer<Null>();
  HttpServer.bind("127.0.0.1", 0).then((server) {
    bool firstHit = false;
    server.listen((request) {
      var session = request.session;
      if (session.isNew) {
        expect(firstHit, isFalse);
        firstHit = true;
      } else {
        expect(firstHit, isTrue);
        session.destroy();
        var session2 = request.session;
        expect(session.id == session2.id, isFalse);
      }
      request.response.close();
    });

    var client = HttpClient();
    client
        .get("127.0.0.1", server.port, "/")
        .then((request) => request.close())
        .then((response) {
      response.listen((_) {}, onDone: () {
        var id = getSessionId(response.cookies);
        expect(id, isNotNull);
        client.get("127.0.0.1", server.port, "/").then((request) {
          request.cookies.add(Cookie(SESSION_ID, id));
          return request.close();
        }).then((response) {
          response.listen((_) {}, onDone: () {
            expect(firstHit, isTrue);
            expect(id == getSessionId(response.cookies), isFalse);
            server.close();
            client.close();
            completer.complete();
          });
        });
      });
    });
  });
  return completer.future;
}

void main() {
  test('testSessions', () => testSessions(1));
  test('testTimeout', () => testTimeout(5));
  test('testSessionsData', () => testSessionsData());
  test('testSessionsDestroy', () => testSessionsDestroy());
}
