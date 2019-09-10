// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import "package:http_io/http_io.dart";
import "package:test/test.dart";

class Server {
  HttpServer server;
  bool passwordChanged = false;

  Future<Server> start() {
    var completer = Completer<Server>();
    HttpServer.bind("127.0.0.1", 0).then((s) {
      server = s;
      server.listen((HttpRequest request) {
        var response = request.response;
        if (request.uri.path == "/passwdchg") {
          passwordChanged = true;
          response.close();
          return;
        }

        String username;
        String password;
        if (request.uri.path == "/") {
          username = "username";
          password = "password";
        } else {
          username = request.uri.path.substring(1, 6);
          password = request.uri.path.substring(1, 6);
        }
        if (passwordChanged) password = "${password}1";
        if (request.headers[HttpHeaders.AUTHORIZATION] != null) {
          expect(1, equals(request.headers[HttpHeaders.AUTHORIZATION].length));
          String authorization = request.headers[HttpHeaders.AUTHORIZATION][0];
          List<String> tokens = authorization.split(" ");
          expect("Basic", equals(tokens[0]));
          String auth = base64Encode(utf8.encode("$username:$password"));
          if (passwordChanged && auth != tokens[1]) {
            response.statusCode = HttpStatus.UNAUTHORIZED;
            response.headers
                .set(HttpHeaders.WWW_AUTHENTICATE, "Basic, realm=realm");
          } else {
            expect(auth, equals(tokens[1]));
          }
        } else {
          response.statusCode = HttpStatus.UNAUTHORIZED;
          response.headers
              .set(HttpHeaders.WWW_AUTHENTICATE, "Basic, realm=realm");
        }
        response.close();
      });
      completer.complete(this);
    });
    return completer.future;
  }

  void shutdown() {
    server.close();
  }

  int get port => server.port;
}

Future<Server> setupServer() {
  return Server().start();
}

Future<Null> testUrlUserInfo() {
  Completer<Null> completer = Completer();
  setupServer().then((server) {
    HttpClient client = HttpClient();

    client
        .getUrl(Uri.parse("http://username:password@127.0.0.1:${server.port}/"))
        .then((request) => request.close())
        .then((HttpClientResponse response) {
      response.listen((_) {}, onDone: () {
        server.shutdown();
        client.close();
        completer.complete(null);
      });
    });
  });
  return completer.future;
}

Future<Null> testBasicNoCredentials() {
  Completer<Null> completer = Completer();
  setupServer().then((server) {
    HttpClient client = HttpClient();

    Future makeRequest(Uri url) {
      return client
          .getUrl(url)
          .then((HttpClientRequest request) => request.close())
          .then((HttpClientResponse response) {
        expect(HttpStatus.UNAUTHORIZED, equals(response.statusCode));
        return response.fold(null, (x, y) {});
      });
    }

    var futures = <Future>[];
    for (int i = 0; i < 5; i++) {
      futures.add(
          makeRequest(Uri.parse("http://127.0.0.1:${server.port}/test$i")));
      futures.add(
          makeRequest(Uri.parse("http://127.0.0.1:${server.port}/test$i/xxx")));
    }
    Future.wait(futures).then((_) {
      server.shutdown();
      client.close();
      completer.complete(null);
    });
  });
  return completer.future;
}

Future<Null> testBasicCredentials() {
  Completer<Null> completer = Completer();
  setupServer().then((server) {
    HttpClient client = HttpClient();

    Future makeRequest(Uri url) {
      return client
          .getUrl(url)
          .then((HttpClientRequest request) => request.close())
          .then((HttpClientResponse response) {
        expect(HttpStatus.OK, equals(response.statusCode));
        return response.fold(null, (x, y) {});
      });
    }

    for (int i = 0; i < 5; i++) {
      client.addCredentials(Uri.parse("http://127.0.0.1:${server.port}/test$i"),
          "realm", HttpClientBasicCredentials("test$i", "test$i"));
    }

    var futures = <Future>[];
    for (int i = 0; i < 5; i++) {
      futures.add(
          makeRequest(Uri.parse("http://127.0.0.1:${server.port}/test$i")));
      futures.add(
          makeRequest(Uri.parse("http://127.0.0.1:${server.port}/test$i/xxx")));
    }
    Future.wait(futures).then((_) {
      server.shutdown();
      client.close();
      completer.complete(null);
    });
  });
  return completer.future;
}

Future<Null> testBasicAuthenticateCallback() {
  Completer<Null> completer = Completer();
  setupServer().then((server) {
    HttpClient client = HttpClient();
    bool passwordChanged = false;

    client.authenticate = (Uri url, String scheme, String realm) {
      expect("Basic", equals(scheme));
      expect("realm", equals(realm));
      String username = url.path.substring(1, 6);
      String password = url.path.substring(1, 6);
      if (passwordChanged) password = "${password}1";
      Completer<bool> completer = Completer<bool>();
      Timer(const Duration(milliseconds: 10), () {
        client.addCredentials(
            url, realm, HttpClientBasicCredentials(username, password));
        completer.complete(true);
      });
      return completer.future;
    };

    Future makeRequest(Uri url) {
      return client
          .getUrl(url)
          .then((HttpClientRequest request) => request.close())
          .then((HttpClientResponse response) {
        expect(HttpStatus.OK, equals(response.statusCode));
        return response.fold(null, (x, y) {});
      });
    }

    List<Future> makeRequests() {
      var futures = <Future>[];
      for (int i = 0; i < 5; i++) {
        futures.add(
            makeRequest(Uri.parse("http://127.0.0.1:${server.port}/test$i")));
        futures.add(makeRequest(
            Uri.parse("http://127.0.0.1:${server.port}/test$i/xxx")));
      }
      return futures;
    }

    Future.wait(makeRequests()).then((_) {
      makeRequest(Uri.parse("http://127.0.0.1:${server.port}/passwdchg"))
          .then((_) {
        passwordChanged = true;
        Future.wait(makeRequests()).then((_) {
          server.shutdown();
          client.close();
          completer.complete(null);
        });
      });
    });
  });
  return completer.future;
}

main() {
  test("UrlUserInfo", () async {
    await testUrlUserInfo();
  });
  test("BasicNoCredentials", () async {
    await testBasicNoCredentials();
  });
  test("BasicCredentials", () async {
    await testBasicCredentials();
  });
  test("BasicAuthenticateCallback", () async {
    await testBasicAuthenticateCallback();
  });
}
