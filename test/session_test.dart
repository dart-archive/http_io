// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:http_io/http_io.dart';
import 'package:test/test.dart';

const _sessionId = "DARTSESSID";

String _getSessionId(List<Cookie> cookies) {
  var id = cookies.fold<String>(null, (last, cookie) {
    if (last != null) return last;
    if (cookie.name.toUpperCase() == _sessionId) {
      expect(cookie.httpOnly, isTrue);
      return cookie.value;
    }
    return null;
  });
  expect(id, isNotNull);
  return id;
}

Future<String> _connectGetSession(HttpClient client, int port,
    [String session]) async {
  var request = await client.get("127.0.0.1", port, "/");

  if (session != null) {
    request.cookies.add(Cookie(_sessionId, session));
  }
  var response = await request.close();
  return response.fold(_getSessionId(response.cookies), (v, _) => v);
}

Future _testSessions(int sessionCount) async {
  var client = HttpClient();

  var server = await HttpServer.bind("127.0.0.1", 0);
  var sessions = Set();
  server.listen((request) {
    sessions.add(request.session.id);
    request.response.close();
  });

  var futures = <Future>[];
  for (int i = 0; i < sessionCount; i++) {
    futures.add(_connectGetSession(client, server.port).then((session) async {
      expect(session, isNotNull);
      expect(sessions, contains(session));
      var session2 = await _connectGetSession(client, server.port, session);
      expect(session2, session);
      expect(sessions, contains(session2));
      return session2;
    }));
  }

  var clientSessions = await Future.wait(futures);
  expect(sessions, hasLength(sessionCount));
  expect(sessions, clientSessions);
  await server.close();
  client.close();
}

Future _testTimeout(int sessionCount) async {
  var client = HttpClient();
  var server = await HttpServer.bind("127.0.0.1", 0);
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
    futures.add(_connectGetSession(client, server.port));
  }

  var clientSessions = await Future.wait(futures);

  await Future.wait(timeouts);
  futures = <Future>[];
  for (var id in clientSessions) {
    futures.add(_connectGetSession(client, server.port, id).then((session) {
      expect(session, isNotNull);
      expect(id, isNot(session));
    }));
  }
  await Future.wait(futures);
  await server.close();
  client.close();
}

Future _testSessionsData() async {
  var server = await HttpServer.bind("127.0.0.1", 0);
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
      expect(session, contains("data"));
      expect(session, containsPair('data', "some data"));
    }
    request.response.close();
  });

  var client = HttpClient();
  var request = await client.get("127.0.0.1", server.port, "/");

  var response = await request.close();

  await response.drain();

  var id = _getSessionId(response.cookies);
  expect(id, isNotNull);

  request = await client.get("127.0.0.1", server.port, "/");
  request.cookies.add(Cookie(_sessionId, id));

  response = await request.close();

  await response.drain();
  expect(firstHit, isTrue);
  expect(secondHit, isTrue);
  expect(id, _getSessionId(response.cookies));
  await server.close();
  client.close();
}

Future _testSessionsDestroy() async {
  var server = await HttpServer.bind("127.0.0.1", 0);
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
      expect(session.id, isNot(session2.id));
    }

    request.response.close();
  });

  var client = HttpClient();
  var request = await client.get("127.0.0.1", server.port, "/");

  var response = await request.close();

  await response.drain();

  var id = _getSessionId(response.cookies);
  expect(id, isNotNull);

  request = await client.get("127.0.0.1", server.port, "/");

  request.cookies.add(Cookie(_sessionId, id));
  response = await request.close();

  await response.drain();

  expect(firstHit, isTrue);
  expect(id, isNot(_getSessionId(response.cookies)));
  await server.close();
  client.close();
}

void main() {
  test('core', () => _testSessions(1));
  test('timeout', () => _testTimeout(5));
  test('data', _testSessionsData);
  test('destroy', _testSessionsDestroy);
}
