// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Directory, File, Platform, SecurityContext, Socket;

import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
import 'package:http_io/http_io.dart';
import 'package:test/test.dart';

String localFile(path) {
  final localPath = '${Directory.current.path}/test/$path';
  if (!(File(localPath).existsSync())) {
    return Platform.script.resolve(path).toFilePath();
  }
  return localPath;
}

final SecurityContext serverContext = SecurityContext()
  ..useCertificateChain(localFile('certificates/server_chain.pem'))
  ..usePrivateKey(localFile('certificates/server_key.pem'),
      password: 'dartdart');

final SecurityContext clientContext = SecurityContext()
  ..setTrustedCertificates(localFile('certificates/trusted_certs.pem'));

class Server {
  HttpServer server;
  bool secure;
  int proxyHops;
  List<String> directRequestPaths;
  int requestCount = 0;

  Server(this.proxyHops, this.directRequestPaths, this.secure);

  Future<Server> start() {
    return (secure
            ? HttpServer.bindSecure("localhost", 0, serverContext)
            : HttpServer.bind("localhost", 0))
        .then((s) {
      server = s;
      server.listen(requestHandler);
      return this;
    });
  }

  void requestHandler(HttpRequest request) {
    var response = request.response;
    requestCount++;
    // Check whether a proxy or direct connection is expected.
    bool direct = directRequestPaths.fold(
        false, (prev, path) => prev ? prev : path == request.uri.path);
    if (!secure && !direct && proxyHops > 0) {
      expect(request.headers[HttpHeaders.VIA], isNotNull);
      expect(1, equals(request.headers[HttpHeaders.VIA].length));
      expect(proxyHops, request.headers[HttpHeaders.VIA][0].split(",").length);
    } else {
      expect(request.headers[HttpHeaders.VIA], isNull);
    }
    var body = StringBuffer();
    onRequestComplete() {
      String path = request.uri.path.substring(1);
      if (path != "A") {
        String content = "$path$path$path";
        expect(content, equals(body.toString()));
      }
      response.write(request.uri.path);
      response.close();
    }

    request.listen((data) {
      body.write(String.fromCharCodes(data));
    }, onDone: onRequestComplete);
  }

  void shutdown() {
    server.close();
  }

  int get port => server.port;
}

Future<Server> setupServer(int proxyHops,
    {List<String> directRequestPaths = const <String>[], secure = false}) {
  Server server = Server(proxyHops, directRequestPaths, secure);
  return server.start();
}

class ProxyServer {
  final bool ipV6;
  HttpServer server;
  HttpClient client;
  int requestCount = 0;
  String authScheme;
  String realm = "test";
  String username;
  String password;

  String ha1;
  String serverAlgorithm = "MD5";
  String serverQop = "auth";
  Set ncs = Set();

  var nonce = "12345678"; // No need for random nonce in test.

  ProxyServer({this.ipV6 = false}) : client = HttpClient();

  void useBasicAuthentication(String username, String password) {
    this.username = username;
    this.password = password;
    authScheme = "Basic";
  }

  void useDigestAuthentication(String username, String password) {
    this.username = username;
    this.password = password;
    authScheme = "Digest";

    // Calculate ha1.
    var digest = md5.convert("$username:$realm:$password".codeUnits);
    ha1 = hex.encode(digest.bytes);
  }

  basicAuthenticationRequired(request) {
    request.fold(null, (x, y) {}).then((_) {
      var response = request.response;
      response.headers
          .set(HttpHeaders.PROXY_AUTHENTICATE, "Basic, realm=$realm");
      response.statusCode = HttpStatus.PROXY_AUTHENTICATION_REQUIRED;
      response.close();
    });
  }

  digestAuthenticationRequired(request, {stale = false}) {
    request.fold(null, (x, y) {}).then((_) {
      var response = request.response;
      response.statusCode = HttpStatus.PROXY_AUTHENTICATION_REQUIRED;
      StringBuffer authHeader = StringBuffer();
      authHeader.write('Digest');
      authHeader.write(', realm="$realm"');
      authHeader.write(', nonce="$nonce"');
      if (stale) authHeader.write(', stale="true"');
      if (serverAlgorithm != null) {
        authHeader.write(', algorithm=$serverAlgorithm');
      }
      if (serverQop != null) authHeader.write(', qop="$serverQop"');
      response.headers.set(HttpHeaders.PROXY_AUTHENTICATE, authHeader);
      response.close();
    });
  }

  Future<ProxyServer> start() {
    var x = Completer<ProxyServer>();
    var host = ipV6 ? "::1" : "localhost";
    HttpServer.bind(host, 0).then((s) {
      server = s;
      x.complete(this);
      server.listen((HttpRequest request) {
        requestCount++;
        if (username != null && password != null) {
          if (request.headers[HttpHeaders.PROXY_AUTHORIZATION] == null) {
            if (authScheme == "Digest") {
              digestAuthenticationRequired(request);
            } else {
              basicAuthenticationRequired(request);
            }
            return;
          } else {
            expect(
                1,
                equals(
                    request.headers[HttpHeaders.PROXY_AUTHORIZATION].length));
            String authorization =
                request.headers[HttpHeaders.PROXY_AUTHORIZATION][0];
            if (authScheme == "Basic") {
              List<String> tokens = authorization.split(" ");
              expect("Basic", equals(tokens[0]));
              String auth = base64.encode(utf8.encode("$username:$password"));
              if (auth != tokens[1]) {
                basicAuthenticationRequired(request);
                return;
              }
            } else {
              HeaderValue header =
                  HeaderValue.parse(authorization, parameterSeparator: ",");
              expect("Digest", equals(header.value));
              var uri = header.parameters["uri"];
              var qop = header.parameters["qop"];
              var cnonce = header.parameters["cnonce"];
              var nc = header.parameters["nc"];
              expect(username, equals(header.parameters["username"]));
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
                expect(cnonce, isNotNull);
                expect(nc, isNotNull);
              }
              expect(header.parameters["response"], isNotNull);

              var digest = md5.convert("${request.method}:$uri".codeUnits);
              var ha2 = hex.encode(digest.bytes);

              if (qop == null || qop == "" || qop == "none") {
                digest = md5.convert("$ha1:$nonce:$ha2".codeUnits);
              } else {
                digest =
                    md5.convert("$ha1:$nonce:$nc:$cnonce:$qop:$ha2".codeUnits);
              }
              expect(hex.encode(digest.bytes),
                  equals(header.parameters["response"]));

              // Add a bogus Proxy-Authentication-Info for testing.
              var info = 'rspauth="77180d1ab3d6c9de084766977790f482", '
                  'cnonce="8f971178", '
                  'nc=000002c74, '
                  'qop=auth';
              request.response.headers.set("Proxy-Authentication-Info", info);
            }
          }
        }
        // Open the connection from the proxy.
        if (request.method == "CONNECT") {
          var tmp = request.uri.toString().split(":");
          Socket.connect(tmp[0], int.parse(tmp[1])).then((socket) {
            request.response.reasonPhrase = "Connection established";
            request.response.detachSocket().then((detached) {
              socket.cast<List<int>>().pipe(detached);
              detached.cast<List<int>>().pipe(socket);
            });
          });
        } else {
          client
              .openUrl(request.method, request.uri)
              .then((HttpClientRequest clientRequest) {
            // Forward all headers.
            request.headers.forEach((String name, List<String> values) {
              values.forEach((String value) {
                if (name != "content-length" && name != "via") {
                  clientRequest.headers.add(name, value);
                }
              });
            });
            // Special handling of Content-Length and Via.
            clientRequest.contentLength = request.contentLength;
            List<String> via = request.headers[HttpHeaders.VIA];
            String viaPrefix = via == null ? "" : "${via[0]}, ";
            clientRequest.headers
                .add(HttpHeaders.VIA, "${viaPrefix}1.1 localhost:$port");
            // Copy all content.
            return request.pipe(clientRequest);
          }).then((clientResponse) {
            (clientResponse as HttpClientResponse).pipe(request.response);
          });
        }
      });
    });
    return x.future;
  }

  void shutdown() {
    server.close();
    client.close();
  }

  int get port => server.port;
}

Future<ProxyServer> setupProxyServer({ipV6 = false}) {
  ProxyServer proxyServer = ProxyServer(ipV6: ipV6);
  return proxyServer.start();
}

int testProxyIPV6DoneCount = 0;
Future<Null> testProxyIPV6() {
  final completer = Completer<Null>();
  setupProxyServer(ipV6: true).then((proxyServer) {
    setupServer(1, directRequestPaths: ["/4"]).then((server) {
      setupServer(1, directRequestPaths: ["/4"], secure: true)
          .then((secureServer) {
        HttpClient client = HttpClient(context: clientContext);

        List<String> proxy = ["PROXY [::1]:${proxyServer.port}"];
        client.findProxy = (Uri uri) {
          // Pick the proxy configuration based on the request path.
          int index = int.parse(uri.path.substring(1));
          return proxy[index];
        };

        for (int i = 0; i < proxy.length; i++) {
          test(bool secure) {
            String url = secure
                ? "https://localhost:${secureServer.port}/$i"
                : "http://localhost:${server.port}/$i";

            client
                .postUrl(Uri.parse(url))
                .then((HttpClientRequest clientRequest) {
              String content = "$i$i$i";
              clientRequest.write(content);
              return clientRequest.close();
            }).then((HttpClientResponse response) {
              response.listen((_) {}, onDone: () {
                testProxyIPV6DoneCount++;
                if (testProxyIPV6DoneCount == proxy.length * 2) {
                  expect(proxy.length, equals(server.requestCount));
                  expect(proxy.length, equals(secureServer.requestCount));
                  proxyServer.shutdown();
                  server.shutdown();
                  secureServer.shutdown();
                  client.close();
                  completer.complete();
                }
              });
            });
          }

          test(false);
          test(true);
        }
      });
    });
  });
  return completer.future;
}

int testProxyFromEnviromentDoneCount = 0;
Future<Null> testProxyFromEnviroment() {
  final completer = Completer<Null>();
  setupProxyServer().then((proxyServer) {
    setupServer(1).then((server) {
      setupServer(1, secure: true).then((secureServer) {
        HttpClient client = HttpClient(context: clientContext);

        client.findProxy = (Uri uri) {
          return HttpClient.findProxyFromEnvironment(uri, environment: {
            "http_proxy": "localhost:${proxyServer.port}",
            "https_proxy": "localhost:${proxyServer.port}"
          });
        };

        const int loopCount = 5;
        for (int i = 0; i < loopCount; i++) {
          test(bool secure) {
            String url = secure
                ? "https://localhost:${secureServer.port}/$i"
                : "http://localhost:${server.port}/$i";

            client
                .postUrl(Uri.parse(url))
                .then((HttpClientRequest clientRequest) {
              String content = "$i$i$i";
              clientRequest.write(content);
              return clientRequest.close();
            }).then((HttpClientResponse response) {
              response.listen((_) {}, onDone: () {
                testProxyFromEnviromentDoneCount++;
                if (testProxyFromEnviromentDoneCount == loopCount * 2) {
                  expect(loopCount, equals(server.requestCount));
                  expect(loopCount, equals(secureServer.requestCount));
                  proxyServer.shutdown();
                  server.shutdown();
                  secureServer.shutdown();
                  client.close();
                  completer.complete();
                }
              });
            });
          }

          test(false);
          test(true);
        }
      });
    });
  });
  return completer.future;
}

int testProxyAuthenticateCount = 0;
Future testProxyAuthenticate(bool useDigestAuthentication) {
  testProxyAuthenticateCount = 0;
  var completer = Completer();

  setupProxyServer().then((proxyServer) {
    setupServer(1).then((server) {
      setupServer(1, secure: true).then((secureServer) {
        HttpClient client = HttpClient(context: clientContext);

        Completer step1 = Completer();
        Completer step2 = Completer();

        if (useDigestAuthentication) {
          proxyServer.useDigestAuthentication("dart", "password");
        } else {
          proxyServer.useBasicAuthentication("dart", "password");
        }

        // Test with no authentication.
        client.findProxy = (Uri uri) {
          return "PROXY localhost:${proxyServer.port}";
        };

        const int loopCount = 2;
        for (int i = 0; i < loopCount; i++) {
          test(bool secure) {
            String url = secure
                ? "https://localhost:${secureServer.port}/$i"
                : "http://localhost:${server.port}/$i";

            client
                .postUrl(Uri.parse(url))
                .then((HttpClientRequest clientRequest) {
              String content = "$i$i$i";
              clientRequest.write(content);
              return clientRequest.close();
            }).then((HttpClientResponse response) {
              fail("No response expected");
            }).catchError((e) {
              testProxyAuthenticateCount++;
              if (testProxyAuthenticateCount == loopCount * 2) {
                expect(0, equals(server.requestCount));
                expect(0, equals(secureServer.requestCount));
                step1.complete(null);
              }
            });
          }

          test(false);
          test(true);
        }
        step1.future.then((_) {
          testProxyAuthenticateCount = 0;
          if (useDigestAuthentication) {
            client.findProxy =
                (Uri uri) => "PROXY localhost:${proxyServer.port}";
            client.addProxyCredentials("localhost", proxyServer.port, "test",
                HttpClientDigestCredentials("dart", "password"));
          } else {
            client.findProxy = (Uri uri) {
              return "PROXY dart:password@localhost:${proxyServer.port}";
            };
          }

          for (int i = 0; i < loopCount; i++) {
            test(bool secure) {
              var path = useDigestAuthentication ? "A" : "$i";
              String url = secure
                  ? "https://localhost:${secureServer.port}/$path"
                  : "http://localhost:${server.port}/$path";

              client
                  .postUrl(Uri.parse(url))
                  .then((HttpClientRequest clientRequest) {
                String content = "$i$i$i";
                clientRequest.write(content);
                return clientRequest.close();
              }).then((HttpClientResponse response) {
                response.listen((_) {}, onDone: () {
                  testProxyAuthenticateCount++;
                  expect(HttpStatus.OK, equals(response.statusCode));
                  if (testProxyAuthenticateCount == loopCount * 2) {
                    expect(loopCount, equals(server.requestCount));
                    expect(loopCount, equals(secureServer.requestCount));
                    step2.complete(null);
                  }
                });
              });
            }

            test(false);
            test(true);
          }
        });

        step2.future.then((_) {
          testProxyAuthenticateCount = 0;
          client.findProxy = (Uri uri) {
            return "PROXY localhost:${proxyServer.port}";
          };

          client.authenticateProxy = (host, port, scheme, realm) {
            client.addProxyCredentials("localhost", proxyServer.port, "realm",
                HttpClientBasicCredentials("dart", "password"));
            return Future.value(true);
          };

          for (int i = 0; i < loopCount; i++) {
            test(bool secure) {
              String url = secure
                  ? "https://localhost:${secureServer.port}/A"
                  : "http://localhost:${server.port}/A";

              client
                  .postUrl(Uri.parse(url))
                  .then((HttpClientRequest clientRequest) {
                String content = "$i$i$i";
                clientRequest.write(content);
                return clientRequest.close();
              }).then((HttpClientResponse response) {
                response.listen((_) {}, onDone: () {
                  testProxyAuthenticateCount++;
                  expect(HttpStatus.OK, equals(response.statusCode));
                  if (testProxyAuthenticateCount == loopCount * 2) {
                    expect(loopCount * 2, equals(server.requestCount));
                    expect(loopCount * 2, equals(secureServer.requestCount));
                    proxyServer.shutdown();
                    server.shutdown();
                    secureServer.shutdown();
                    client.close();
                    completer.complete(null);
                  }
                });
              });
            }

            test(false);
            test(true);
          }
        });
      });
    });
  });

  return completer.future;
}

int testRealProxyDoneCount = 0;
void testRealProxy() {
  setupServer(1).then((server) {
    HttpClient client = HttpClient(context: clientContext);
    client.addProxyCredentials("localhost", 8080, "test",
        HttpClientBasicCredentials("dart", "password"));

    List<String> proxy = [
      "PROXY localhost:8080",
      "PROXY localhost:8080; PROXY hede.hule.hest:8080",
      "PROXY hede.hule.hest:8080; PROXY localhost:8080",
      "PROXY localhost:8080; DIRECT"
    ];

    client.findProxy = (Uri uri) {
      // Pick the proxy configuration based on the request path.
      int index = int.parse(uri.path.substring(1));
      return proxy[index];
    };

    for (int i = 0; i < proxy.length; i++) {
      client
          .getUrl(Uri.parse("http://localhost:${server.port}/$i"))
          .then((HttpClientRequest clientRequest) {
        String content = "$i$i$i";
        clientRequest.contentLength = content.length;
        clientRequest.write(content);
        return clientRequest.close();
      }).then((HttpClientResponse response) {
        response.listen((_) {}, onDone: () {
          if (++testRealProxyDoneCount == proxy.length) {
            expect(proxy.length, equals(server.requestCount));
            server.shutdown();
            client.close();
          }
        });
      });
    }
  });
}

int testRealProxyAuthDoneCount = 0;
void testRealProxyAuth() {
  setupServer(1).then((server) {
    HttpClient client = HttpClient(context: clientContext);

    List<String> proxy = [
      "PROXY dart:password@localhost:8080",
      "PROXY dart:password@localhost:8080; PROXY hede.hule.hest:8080",
      "PROXY hede.hule.hest:8080; PROXY dart:password@localhost:8080",
      "PROXY dart:password@localhost:8080; DIRECT"
    ];

    client.findProxy = (Uri uri) {
      // Pick the proxy configuration based on the request path.
      int index = int.parse(uri.path.substring(1));
      return proxy[index];
    };

    for (int i = 0; i < proxy.length; i++) {
      client
          .getUrl(Uri.parse("http://localhost:${server.port}/$i"))
          .then((HttpClientRequest clientRequest) {
        String content = "$i$i$i";
        clientRequest.contentLength = content.length;
        clientRequest.write(content);
        return clientRequest.close();
      }).then((HttpClientResponse response) {
        response.listen((_) {}, onDone: () {
          if (++testRealProxyAuthDoneCount == proxy.length) {
            expect(proxy.length, equals(server.requestCount));
            server.shutdown();
            client.close();
          }
        });
      });
    }
  });
}

main() {
  test('proxyIPV6', testProxyIPV6);
  test('proxyFromEnvironment', testProxyFromEnviroment);
  // The two invocations use the same global variable for state -
  // run one after the other.
  test('proxyAuth', () {
    testProxyAuthenticate(false).then((_) => testProxyAuthenticate(true));
  });

  // This test is not normally run. It can be used for locally testing
  // with a real proxy server (e.g. Apache).
  // testRealProxy();
  // testRealProxyAuth();
}
