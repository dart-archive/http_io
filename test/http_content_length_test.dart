// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import "dart:io";
import "package:test/test.dart";

void testNoBody(int totalConnections, bool explicitContentLength) {
  int count = 0;
  HttpServer.bind("127.0.0.1", 0, backlog: totalConnections).then((server) {
    server.listen((HttpRequest request) {
      expect("0", equals(request.headers.value('content-length')));
      expect(0, equals(request.contentLength));
      var response = request.response;
      response.contentLength = 0;
      response.done.then((_) {
        fail("Unexpected successful response completion");
      }).catchError((error) {
        expect(error is HttpException, isTrue);
        if (++count == totalConnections) {
          server.close();
        }
      });
      // write with content length 0 closes the connection and
      // reports an error.
      response.write("x");
      // Subsequent write are ignored as there is already an
      // error.
      response.write("x");
      // After an explicit close, write becomes a state error
      // because we have said we will not add more.
      response.close();
      response.write("x");
    }, onError: (e, trace) {
      String msg = "Unexpected server error $e";
      if (trace != null) msg += "\nStackTrace: $trace";
      fail(msg);
    });

    HttpClient client = new HttpClient();
    for (int i = 0; i < totalConnections; i++) {
      client.get("127.0.0.1", server.port, "/").then((request) {
        if (explicitContentLength) {
          request.contentLength = 0;
        }
        return request.close();
      }).then((response) {
        expect("0", equals(response.headers.value('content-length')));
        expect(0, equals(response.contentLength));
        response.drain();
      }).catchError((e, trace) {
        // It's also okay to fail, as headers may not be written.
      });
    }
  });
}

void testBody(int totalConnections, bool useHeader) {
  HttpServer.bind("127.0.0.1", 0, backlog: totalConnections).then((server) {
    int serverCount = 0;
    server.listen((HttpRequest request) {
      expect("2", equals(request.headers.value('content-length')));
      expect(2, equals(request.contentLength));
      var response = request.response;
      if (useHeader) {
        response.contentLength = 2;
      } else {
        response.headers.set("content-length", 2);
      }
      request.listen((d) {}, onDone: () {
        response.write("x");
        try {
          response.contentLength = 3;
          fail("Expected HttpException");
        } catch (e) {
          expect(e is HttpException, isTrue);
        }
        response.write("x");
        response.write("x");
        response.done.then((_) {
          fail("Unexpected successful response completion");
        }).catchError((error) {
          expect(error is HttpException, equals("[$error]"));
          if (++serverCount == totalConnections) {
            server.close();
          }
        });
        response.close();
        response.write("x");
      });
    }, onError: (e, trace) {
      String msg = "Unexpected error $e";
      if (trace != null) msg += "\nStackTrace: $trace";
      fail(msg);
    });

    int clientCount = 0;
    HttpClient client = new HttpClient();
    for (int i = 0; i < totalConnections; i++) {
      client.get("127.0.0.1", server.port, "/").then((request) {
        if (useHeader) {
          request.contentLength = 2;
        } else {
          request.headers.add(HttpHeaders.CONTENT_LENGTH, "7");
          request.headers.add(HttpHeaders.CONTENT_LENGTH, "2");
        }
        request.write("x");
        try {
          request.contentLength = 3;
          fail("Expected HttpException");
        } catch (e) {
          expect(e is HttpException, isTrue);
        }
        request.write("x");
        return request.close();
      }).then((response) {
        expect("2", equals(response.headers.value('content-length')));
        expect(2, equals(response.contentLength));
        response.listen((d) {}, onDone: () {
          if (++clientCount == totalConnections) {
            client.close();
          }
        }, onError: (error, trace) {
          // Undefined what server response sends.
        });
      }).catchError((error) {
        // It's also okay to fail, as headers may not be written.
      });
    }
  });
}

void testBodyChunked(int totalConnections, bool useHeader) {
  HttpServer.bind("127.0.0.1", 0, backlog: totalConnections).then((server) {
    server.listen((HttpRequest request) {
      expect(request.headers.value('content-length'), isNull);
      expect(-1, equals(request.contentLength));
      var response = request.response;
      if (useHeader) {
        response.contentLength = 2;
        response.headers.chunkedTransferEncoding = true;
      } else {
        response.headers.set("content-length", 2);
        response.headers.set("transfer-encoding", "chunked");
      }
      request.listen((d) {}, onDone: () {
        response.write("x");
        try {
          response.headers.chunkedTransferEncoding = false;
          fail("Expected HttpException");
        } catch (e) {
          expect(e is HttpException, isTrue);
        }
        response.write("x");
        response.write("x");
        response.close();
        response.write("x");
      });
    }, onError: (e, trace) {
      String msg = "Unexpected error $e";
      if (trace != null) msg += "\nStackTrace: $trace";
      fail(msg);
    });

    int count = 0;
    HttpClient client = new HttpClient();
    for (int i = 0; i < totalConnections; i++) {
      client.get("127.0.0.1", server.port, "/").then((request) {
        if (useHeader) {
          request.contentLength = 2;
          request.headers.chunkedTransferEncoding = true;
        } else {
          request.headers.add(HttpHeaders.CONTENT_LENGTH, "2");
          request.headers.set(HttpHeaders.TRANSFER_ENCODING, "chunked");
        }
        request.write("x");
        try {
          request.headers.chunkedTransferEncoding = false;
          fail("Expected HttpException");
        } catch (e) {
          expect(e is HttpException, isTrue);
        }
        request.write("x");
        request.write("x");
        return request.close();
      }).then((response) {
        expect(response.headers.value('content-length'), isNull);
        expect(-1, equals(response.contentLength));
        response.listen((d) {}, onDone: () {
          if (++count == totalConnections) {
            client.close();
            server.close();
          }
        });
      }).catchError((e, trace) {
        String msg = "Unexpected error $e";
        if (trace != null) msg += "\nStackTrace: $trace";
        fail(msg);
      });
    }
  });
}

void testSetContentLength() {
  HttpServer.bind("127.0.0.1", 0).then((server) {
    server.listen((HttpRequest request) {
      var response = request.response;
      expect(response.headers.value('content-length'), isNull);
      expect(-1, equals(response.contentLength));
      response.headers.set("content-length", 3);
      expect("3", equals(response.headers.value('content-length')));
      expect(3, equals(response.contentLength));
      response.write("xxx");
      response.close();
    });

    var client = new HttpClient();
    client
        .get("127.0.0.1", server.port, "/")
        .then((request) => request.close())
        .then((response) {
      response.listen((_) {}, onDone: () {
        client.close();
        server.close();
      });
    });
  });
}

void main() {
  testNoBody(5, false);
  testNoBody(25, false);
  testNoBody(5, true);
  testNoBody(25, true);
  testBody(5, false);
  testBody(5, true);
  testBodyChunked(5, false);
  testBodyChunked(5, true);
  testSetContentLength();
}
