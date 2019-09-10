// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import "dart:async";

import 'package:http_io/http_io.dart';
import 'package:test/test.dart';

Future<HttpServer> setupServer() {
  return HttpServer.bind("127.0.0.1", 0).then((server) {
    var handlers = Map<String, Function>();
    addRequestHandler(
        String path, void handler(HttpRequest request, HttpResponse response)) {
      handlers[path] = handler;
    }

    server.listen((HttpRequest request) {
      if (handlers.containsKey(request.uri.path)) {
        handlers[request.uri.path](request, request.response);
      } else {
        request.listen((_) {}, onDone: () {
          request.response.statusCode = 404;
          request.response.close();
        });
      }
    });

    void addRedirectHandler(int number, int statusCode) {
      addRequestHandler("/$number",
          (HttpRequest request, HttpResponse response) {
        response.redirect(
            Uri.parse("http://127.0.0.1:${server.port}/${number + 1}"));
      });
    }

    // Setup simple redirect.
    addRequestHandler("/redirect",
        (HttpRequest request, HttpResponse response) {
      response.redirect(Uri.parse("http://127.0.0.1:${server.port}/location"),
          status: HttpStatus.MOVED_PERMANENTLY);
    });
    addRequestHandler("/location",
        (HttpRequest request, HttpResponse response) {
      response.close();
    });

    // Setup redirects with relative url.
    addRequestHandler("/redirectUrl",
        (HttpRequest request, HttpResponse response) {
      response.headers.set(HttpHeaders.LOCATION, "/some/relativeUrl");
      response.statusCode = HttpStatus.MOVED_PERMANENTLY;
      response.close();
    });

    addRequestHandler("/some/redirectUrl",
        (HttpRequest request, HttpResponse response) {
      response.headers.set(HttpHeaders.LOCATION, "relativeUrl");
      response.statusCode = HttpStatus.MOVED_PERMANENTLY;
      response.close();
    });

    addRequestHandler("/some/relativeUrl",
        (HttpRequest request, HttpResponse response) {
      response.close();
    });

    addRequestHandler("/some/relativeToAbsolute",
        (HttpRequest request, HttpResponse response) {
      response.redirect(Uri.parse("xxx"), status: HttpStatus.SEE_OTHER);
    });

    addRequestHandler("/redirectUrl2",
        (HttpRequest request, HttpResponse response) {
      response.headers.set(HttpHeaders.LOCATION, "location");
      response.statusCode = HttpStatus.MOVED_PERMANENTLY;
      response.close();
    });

    addRequestHandler("/redirectUrl3",
        (HttpRequest request, HttpResponse response) {
      response.headers.set(HttpHeaders.LOCATION, "./location");
      response.statusCode = HttpStatus.MOVED_PERMANENTLY;
      response.close();
    });

    addRequestHandler("/redirectUrl4",
        (HttpRequest request, HttpResponse response) {
      response.headers.set(HttpHeaders.LOCATION, "./a/b/../../location");
      response.statusCode = HttpStatus.MOVED_PERMANENTLY;
      response.close();
    });

    addRequestHandler("/redirectUrl5",
        (HttpRequest request, HttpResponse response) {
      response.headers
          .set(HttpHeaders.LOCATION, "//127.0.0.1:${server.port}/location");
      response.statusCode = HttpStatus.MOVED_PERMANENTLY;
      response.close();
    });

    // Setup redirect chain.
    int n = 1;
    addRedirectHandler(n++, HttpStatus.MOVED_PERMANENTLY);
    addRedirectHandler(n++, HttpStatus.MOVED_TEMPORARILY);
    addRedirectHandler(n++, HttpStatus.SEE_OTHER);
    addRedirectHandler(n++, HttpStatus.TEMPORARY_REDIRECT);
    for (int i = n; i < 10; i++) {
      addRedirectHandler(i, HttpStatus.MOVED_PERMANENTLY);
    }

    // Setup redirect loop.
    addRequestHandler("/A", (HttpRequest request, HttpResponse response) {
      response.headers
          .set(HttpHeaders.LOCATION, "http://127.0.0.1:${server.port}/B");
      response.statusCode = HttpStatus.MOVED_PERMANENTLY;
      response.close();
    });
    addRequestHandler("/B", (HttpRequest request, HttpResponse response) {
      response.headers
          .set(HttpHeaders.LOCATION, "http://127.0.0.1:${server.port}/A");
      response.statusCode = HttpStatus.MOVED_TEMPORARILY;
      response.close();
    });

    // Setup redirect checking headers.
    addRequestHandler("/src", (HttpRequest request, HttpResponse response) {
      expect("value", equals(request.headers.value("X-Request-Header")));
      response.headers
          .set(HttpHeaders.LOCATION, "http://127.0.0.1:${server.port}/target");
      response.statusCode = HttpStatus.MOVED_PERMANENTLY;
      response.close();
    });
    addRequestHandler("/target", (HttpRequest request, HttpResponse response) {
      expect("value", equals(request.headers.value("X-Request-Header")));
      response.close();
    });

    // Setup redirect for 301 where POST should not redirect.
    addRequestHandler("/301src", (HttpRequest request, HttpResponse response) {
      expect("POST", equals(request.method));
      request.listen((_) {}, onDone: () {
        response.headers.set(
            HttpHeaders.LOCATION, "http://127.0.0.1:${server.port}/301target");
        response.statusCode = HttpStatus.MOVED_PERMANENTLY;
        response.close();
      });
    });
    addRequestHandler("/301target",
        (HttpRequest request, HttpResponse response) {
      fail("Redirect of POST should not happen");
    });

    // Setup redirect for 303 where POST should turn into GET.
    addRequestHandler("/303src", (HttpRequest request, HttpResponse response) {
      request.listen((_) {}, onDone: () {
        expect("POST", equals(request.method));
        response.headers.set(
            HttpHeaders.LOCATION, "http://127.0.0.1:${server.port}/303target");
        response.statusCode = HttpStatus.SEE_OTHER;
        response.close();
      });
    });
    addRequestHandler("/303target",
        (HttpRequest request, HttpResponse response) {
      expect("GET", equals(request.method));
      response.close();
    });

    // Setup redirect where we close the connection.
    addRequestHandler("/closing", (HttpRequest request, HttpResponse response) {
      response.headers
          .set(HttpHeaders.LOCATION, "http://127.0.0.1:${server.port}/");
      response.statusCode = HttpStatus.FOUND;
      response.persistentConnection = false;
      response.close();
    });
    return server;
  });
}

void checkRedirects(int redirectCount, HttpClientResponse response) {
  if (redirectCount < 2) {
    expect(response.redirects.isEmpty, isTrue);
  } else {
    expect(redirectCount - 1, equals(response.redirects.length));
    for (int i = 0; i < redirectCount - 2; i++) {
      expect(response.redirects[i].location.path, equals("/${i + 2}"));
    }
  }
}

Future<Null> testManualRedirect() {
  final completer = Completer<Null>();
  setupServer().then((server) {
    HttpClient client = HttpClient();

    int redirectCount = 0;
    handleResponse(HttpClientResponse response) {
      response.listen((_) => fail("Response data not expected"), onDone: () {
        redirectCount++;
        if (redirectCount < 10) {
          expect(response.isRedirect, isTrue);
          checkRedirects(redirectCount, response);
          response.redirect().then(handleResponse);
        } else {
          expect(HttpStatus.NOT_FOUND, equals(response.statusCode));
          server.close();
          client.close();
          completer.complete();
        }
      });
    }

    client
        .getUrl(Uri.parse("http://127.0.0.1:${server.port}/1"))
        .then((HttpClientRequest request) {
      request.followRedirects = false;
      return request.close();
    }).then(handleResponse);
  });
  return completer.future;
}

Future<Null> testManualRedirectWithHeaders() {
  final completer = Completer<Null>();
  setupServer().then((server) {
    HttpClient client = HttpClient();

    int redirectCount = 0;

    handleResponse(HttpClientResponse response) {
      response.listen((_) => fail("Response data not expected"), onDone: () {
        redirectCount++;
        if (redirectCount < 2) {
          expect(response.isRedirect, isTrue);
          response.redirect().then(handleResponse);
        } else {
          expect(HttpStatus.OK, equals(response.statusCode));
          server.close();
          client.close();
          completer.complete();
        }
      });
    }

    client
        .getUrl(Uri.parse("http://127.0.0.1:${server.port}/src"))
        .then((HttpClientRequest request) {
      request.followRedirects = false;
      request.headers.add("X-Request-Header", "value");
      return request.close();
    }).then(handleResponse);
  });
  return completer.future;
}

Future<Null> testAutoRedirect() {
  final completer = Completer<Null>();

  setupServer().then((server) {
    HttpClient client = HttpClient();

    client
        .getUrl(Uri.parse("http://127.0.0.1:${server.port}/redirect"))
        .then((HttpClientRequest request) {
      return request.close();
    }).then((HttpClientResponse response) {
      response.listen((_) => fail("Response data not expected"), onDone: () {
        expect(1, equals(response.redirects.length));
        server.close();
        client.close();
        completer.complete();
      });
    });
  });
  return completer.future;
}

Future<Null> testAutoRedirectWithHeaders() {
  final completer = Completer<Null>();
  setupServer().then((server) {
    HttpClient client = HttpClient();

    client
        .getUrl(Uri.parse("http://127.0.0.1:${server.port}/src"))
        .then((HttpClientRequest request) {
      request.headers.add("X-Request-Header", "value");
      return request.close();
    }).then((HttpClientResponse response) {
      response.listen((_) => fail("Response data not expected"), onDone: () {
        expect(1, equals(response.redirects.length));
        server.close();
        client.close();
        completer.complete();
      });
    });
  });
  return completer.future;
}

Future<Null> testAutoRedirect301POST() {
  final completer = Completer<Null>();
  setupServer().then((server) {
    HttpClient client = HttpClient();

    client
        .postUrl(Uri.parse("http://127.0.0.1:${server.port}/301src"))
        .then((HttpClientRequest request) {
      return request.close();
    }).then((HttpClientResponse response) {
      expect(HttpStatus.MOVED_PERMANENTLY, equals(response.statusCode));
      response.listen((_) => fail("Response data not expected"), onDone: () {
        expect(0, equals(response.redirects.length));
        server.close();
        client.close();
        completer.complete();
      });
    });
  });
  return completer.future;
}

Future<Null> testAutoRedirect303POST() {
  final completer = Completer<Null>();
  setupServer().then((server) {
    HttpClient client = HttpClient();

    client
        .postUrl(Uri.parse("http://127.0.0.1:${server.port}/303src"))
        .then((HttpClientRequest request) {
      return request.close();
    }).then((HttpClientResponse response) {
      expect(HttpStatus.OK, equals(response.statusCode));
      response.listen((_) => fail("Response data not expected"), onDone: () {
        expect(1, equals(response.redirects.length));
        server.close();
        client.close();
        completer.complete();
      });
    });
  });
  return completer.future;
}

Future<Null> testAutoRedirectLimit() {
  final completer = Completer<Null>();
  setupServer().then((server) {
    HttpClient client = HttpClient();
    client
        .getUrl(Uri.parse("http://127.0.0.1:${server.port}/1"))
        .then((HttpClientRequest request) => request.close())
        .catchError((error) {
      expect(5, equals(error.redirects.length));
      server.close();
      client.close();
      completer.complete();
    }, test: (e) => e is RedirectException);
  });
  return completer.future;
}

Future<Null> testRedirectLoop() {
  final completer = Completer<Null>();
  setupServer().then((server) {
    HttpClient client = HttpClient();
    client
        .getUrl(Uri.parse("http://127.0.0.1:${server.port}/A"))
        .then((HttpClientRequest request) => request.close())
        .catchError((error) {
      expect(2, equals(error.redirects.length));
      server.close();
      client.close();
      completer.complete();
    }, test: (e) => e is RedirectException);
  });
  return completer.future;
}

Future<Null> testRedirectClosingConnection() {
  final completer = Completer<Null>();
  setupServer().then((server) {
    HttpClient client = HttpClient();
    client
        .getUrl(Uri.parse("http://127.0.0.1:${server.port}/closing"))
        .then((request) => request.close())
        .then((response) {
      response.listen((_) {}, onDone: () {
        expect(1, equals(response.redirects.length));
        server.close();
        client.close();
        completer.complete();
      });
    });
  });
  return completer.future;
}

Future<Null> testRedirectRelativeUrl() async {
  Future<Null> testPath(String path) {
    final completer = Completer<Null>();
    setupServer().then((server) {
      HttpClient client = HttpClient();
      client
          .getUrl(Uri.parse("http://127.0.0.1:${server.port}$path"))
          .then((request) => request.close())
          .then((response) {
        response.listen((_) {}, onDone: () {
          expect(HttpStatus.OK, equals(response.statusCode));
          expect(1, equals(response.redirects.length));
          server.close();
          client.close();
          completer.complete();
        });
      });
    });
    return completer.future;
  }

  await testPath("/redirectUrl");
  await testPath("/some/redirectUrl");
  await testPath("/redirectUrl2");
  await testPath("/redirectUrl3");
  await testPath("/redirectUrl4");
  await testPath("/redirectUrl5");
}

Future<Null> testRedirectRelativeToAbsolute() {
  final completer = Completer<Null>();
  setupServer().then((server) {
    HttpClient client = HttpClient();

    handleResponse(HttpClientResponse response) {
      response.listen((_) => fail("Response data not expected"), onDone: () {
        expect(HttpStatus.SEE_OTHER, equals(response.statusCode));
        expect("xxx", equals(response.headers["Location"][0]));
        expect(response.isRedirect, isTrue);
        server.close();
        client.close();
        completer.complete();
      });
    }

    client
        .getUrl(Uri.parse(
            "http://127.0.0.1:${server.port}/some/relativeToAbsolute"))
        .then((HttpClientRequest request) {
      request.followRedirects = false;
      return request.close();
    }).then(handleResponse);
  });
  return completer.future;
}

main() {
  test('manualRedirect', testManualRedirect);
  test('manualRedirectWithHeaders', testManualRedirectWithHeaders);
  test('autoRedirect', testAutoRedirect);
  test('autoRedirectWithHeaders', testAutoRedirectWithHeaders);
  test('autoRedirect301POST', testAutoRedirect301POST);
  test('autoRedirect303POST', testAutoRedirect303POST);
  test('autoRedirectLimit', testAutoRedirectLimit);
  test('redirectLoop', testRedirectLoop);
  test('redirectClosingConnection', testRedirectClosingConnection);
  test('redirectRelativeUrl', testRedirectRelativeUrl);
  test('redirectRelativeToAbsolute', testRedirectRelativeToAbsolute);
}
