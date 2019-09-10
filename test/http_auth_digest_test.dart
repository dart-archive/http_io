// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import "package:convert/convert.dart";
import "package:crypto/crypto.dart";
import "package:http_io/http_io.dart";
import "package:test/test.dart";

class Server {
  HttpServer server;
  int unauthCount = 0; // Counter of the 401 responses.
  int successCount = 0; // Counter of the successful responses.
  int nonceCount = 0; // Counter of use of current nonce.
  String ha1;

  static Future<Server> start(String algorithm, String qop,
      {int nonceStaleAfter, bool useNextNonce = false}) {
    return Server()._start(algorithm, qop, nonceStaleAfter, useNextNonce);
  }

  Future<Server> _start(String serverAlgorithm, String serverQop,
      int nonceStaleAfter, bool useNextNonce) {
    Set ncs = Set();
    // Calculate ha1.
    String realm = "test";
    String username = "dart";
    String password = "password";
    var hasher = md5.convert("$username:$realm:$password".codeUnits);
    ha1 = hex.encode(hasher.bytes);

    var nonce = "12345678"; // No need for random nonce in test.

    var completer = Completer<Server>();
    HttpServer.bind("127.0.0.1", 0).then((s) {
      server = s;
      server.listen((HttpRequest request) {
        sendUnauthorizedResponse(HttpResponse response, {stale = false}) {
          response.statusCode = HttpStatus.UNAUTHORIZED;
          StringBuffer authHeader = StringBuffer();
          authHeader.write('Digest');
          authHeader.write(', realm="$realm"');
          authHeader.write(', nonce="$nonce"');
          if (stale) authHeader.write(', stale="true"');
          if (serverAlgorithm != null) {
            authHeader.write(', algorithm=$serverAlgorithm');
          }
          authHeader.write(', domain="/digest/"');
          if (serverQop != null) authHeader.write(', qop="$serverQop"');
          response.headers.set(HttpHeaders.WWW_AUTHENTICATE, authHeader);
          unauthCount++;
        }

        var response = request.response;
        if (request.headers[HttpHeaders.AUTHORIZATION] != null) {
          expect(1, equals(request.headers[HttpHeaders.AUTHORIZATION].length));
          String authorization = request.headers[HttpHeaders.AUTHORIZATION][0];
          HeaderValue header =
              HeaderValue.parse(authorization, parameterSeparator: ",");
          if (header.value.toLowerCase() == "basic") {
            sendUnauthorizedResponse(response);
          } else if (!useNextNonce && nonceCount == nonceStaleAfter) {
            nonce = "87654321";
            nonceCount = 0;
            sendUnauthorizedResponse(response, stale: true);
          } else {
            var uri = header.parameters["uri"];
            var qop = header.parameters["qop"];
            var cnonce = header.parameters["cnonce"];
            var nc = header.parameters["nc"];
            expect("digest", equals(header.value.toLowerCase()));
            expect("dart", equals(header.parameters["username"]));
            expect(realm, equals(header.parameters["realm"]));
            expect("MD5", equals(header.parameters["algorithm"]));
            expect(nonce, equals(header.parameters["nonce"]));
            expect(request.uri.toString(), equals(uri));
            if (qop != null) {
              // A server qop of auth-int is downgraded to none by the client.
              expect("auth", equals(serverQop));
              expect("auth", equals(header.parameters["qop"]));
              expect(cnonce, isNotNull);
              expect(nc, isNotNull);
              expect(ncs.contains(nc), isFalse);
              ncs.add(nc);
            } else {
              expect(cnonce, isNull);
              expect(nc, isNull);
            }
            expect(header.parameters["response"], isNotNull);

            var hasher = md5.convert("${request.method}:$uri".codeUnits);
            var ha2 = hex.encode(hasher.bytes);

            Digest digest;
            if (qop == null || qop == "" || qop == "none") {
              digest = md5.convert("$ha1:$nonce:$ha2".codeUnits);
            } else {
              digest =
                  md5.convert("$ha1:$nonce:$nc:$cnonce:$qop:$ha2".codeUnits);
            }
            expect(hex.encode(digest.bytes),
                equals(header.parameters["response"]));

            successCount++;
            nonceCount++;

            // Add a bogus Authentication-Info for testing.
            var info = 'rspauth="77180d1ab3d6c9de084766977790f482", '
                'cnonce="8f971178", '
                'nc=000002c74, '
                'qop=auth';
            if (useNextNonce && nonceCount == nonceStaleAfter) {
              nonce = "abcdef01";
              info += ', nextnonce="$nonce"';
            }
            response.headers.set("Authentication-Info", info);
          }
        } else {
          sendUnauthorizedResponse(response);
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

Future<Null> testNoCredentials(String algorithm, String qop) {
  Completer<Null> completer = Completer();
  Server.start(algorithm, qop).then((server) {
    HttpClient client = HttpClient();

    // Add digest credentials which does not match the path requested.
    client.addCredentials(Uri.parse("http://127.0.0.1:${server.port}/xxx"),
        "test", HttpClientDigestCredentials("dart", "password"));

    // Add basic credentials for the path requested.
    client.addCredentials(Uri.parse("http://127.0.0.1:${server.port}/digest"),
        "test", HttpClientBasicCredentials("dart", "password"));

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
          makeRequest(Uri.parse("http://127.0.0.1:${server.port}/digest")));
    }
    Future.wait(futures).then((_) {
      server.shutdown();
      client.close();
      completer.complete(null);
    });
  });
  return completer.future;
}

Future<Null> testCredentials(String algorithm, String qop) {
  Completer<Null> completer = Completer();
  Server.start(algorithm, qop).then((server) {
    HttpClient client = HttpClient();

    Future makeRequest(Uri url) {
      return client
          .getUrl(url)
          .then((HttpClientRequest request) => request.close())
          .then((HttpClientResponse response) {
        expect(HttpStatus.OK, equals(response.statusCode));
        expect(1, equals(response.headers["Authentication-Info"].length));
        return response.fold(null, (x, y) {});
      });
    }

    client.addCredentials(Uri.parse("http://127.0.0.1:${server.port}/digest"),
        "test", HttpClientDigestCredentials("dart", "password"));

    var futures = <Future>[];
    for (int i = 0; i < 2; i++) {
      String uriBase = "http://127.0.0.1:${server.port}/digest";
      futures.add(makeRequest(Uri.parse(uriBase)));
      futures.add(makeRequest(Uri.parse("$uriBase?querystring")));
      futures.add(makeRequest(Uri.parse("$uriBase?querystring#fragment")));
    }
    Future.wait(futures).then((_) {
      server.shutdown();
      client.close();
      completer.complete(null);
    });
  });
  return completer.future;
}

Future<Null> testAuthenticateCallback(String algorithm, String qop) {
  Completer<Null> completer = Completer();
  Server.start(algorithm, qop).then((server) {
    HttpClient client = HttpClient();

    client.authenticate = (Uri url, String scheme, String realm) {
      expect("Digest", equals(scheme));
      expect("test", equals(realm));
      Completer<bool> completer = Completer<bool>();
      Timer(const Duration(milliseconds: 10), () {
        client.addCredentials(
            Uri.parse("http://127.0.0.1:${server.port}/digest"),
            "test",
            HttpClientDigestCredentials("dart", "password"));
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
        expect(1, equals(response.headers["Authentication-Info"].length));
        return response.fold(null, (x, y) {});
      });
    }

    var futures = <Future>[];
    for (int i = 0; i < 5; i++) {
      futures.add(
          makeRequest(Uri.parse("http://127.0.0.1:${server.port}/digest")));
    }
    Future.wait(futures).then((_) {
      server.shutdown();
      client.close();
      completer.complete(null);
    });
  });
  return completer.future;
}

Future<Null> testStaleNonce() {
  Completer<Null> completer = Completer();
  Server.start("MD5", "auth", nonceStaleAfter: 2).then((server) {
    HttpClient client = HttpClient();

    Future makeRequest(Uri url) {
      return client
          .getUrl(url)
          .then((HttpClientRequest request) => request.close())
          .then((HttpClientResponse response) {
        expect(HttpStatus.OK, equals(response.statusCode));
        expect(1, equals(response.headers["Authentication-Info"].length));
        return response.fold(null, (x, y) {});
      });
    }

    Uri uri = Uri.parse("http://127.0.0.1:${server.port}/digest");
    var credentials = HttpClientDigestCredentials("dart", "password");
    client.addCredentials(uri, "test", credentials);

    makeRequest(uri)
        .then((_) => makeRequest(uri))
        .then((_) => makeRequest(uri))
        .then((_) => makeRequest(uri))
        .then((_) {
      expect(2, equals(server.unauthCount));
      expect(4, equals(server.successCount));
      server.shutdown();
      client.close();
      completer.complete(null);
    });
  });
  return completer.future;
}

Future<Null> testNextNonce() {
  Completer<Null> completer = Completer();
  Server.start("MD5", "auth", nonceStaleAfter: 2, useNextNonce: true)
      .then((server) {
    HttpClient client = HttpClient();

    Future makeRequest(Uri url) {
      return client
          .getUrl(url)
          .then((HttpClientRequest request) => request.close())
          .then((HttpClientResponse response) {
        expect(HttpStatus.OK, equals(response.statusCode));
        expect(1, equals(response.headers["Authentication-Info"].length));
        return response.fold(null, (x, y) {});
      });
    }

    Uri uri = Uri.parse("http://127.0.0.1:${server.port}/digest");
    var credentials = HttpClientDigestCredentials("dart", "password");
    client.addCredentials(uri, "test", credentials);

    makeRequest(uri)
        .then((_) => makeRequest(uri))
        .then((_) => makeRequest(uri))
        .then((_) => makeRequest(uri))
        .then((_) {
      expect(1, equals(server.unauthCount));
      expect(4, equals(server.successCount));
      server.shutdown();
      client.close();
      completer.complete(null);
    });
  });
  return completer.future;
}

main() {
  test("NoCredentials", () async {
    await testNoCredentials(null, null);
  });
  test("NoCredentials MD5", () async {
    await testNoCredentials("MD5", null);
  });
  test("NoCredentials MD5 auth", () async {
    await testNoCredentials("MD5", "auth");
  });
  test("Credentials", () async {
    await testCredentials(null, null);
  });
  test("Credentials MD5", () async {
    await testCredentials("MD5", null);
  });
  test("Credentials MD5 auth", () async {
    await testCredentials("MD5", "auth");
  });
  test("Credentials MD5 auth-int", () async {
    await testCredentials("MD5", "auth-int");
  });
  test("AuthenticateCallback", () async {
    await testAuthenticateCallback(null, null);
  });
  test("AuthenticateCallback MD5", () async {
    await testAuthenticateCallback("MD5", null);
  });
  test("AuthenticateCallback MD5 auth", () async {
    await testAuthenticateCallback("MD5", "auth");
  });
  test("AuthenticateCallback MD5 auth-int", () async {
    await testAuthenticateCallback("MD5", "auth-int");
  });
  test("StaleNonce", () async {
    await testStaleNonce();
  });
  test("NextNonce", () async {
    await testNextNonce();
  });
}
