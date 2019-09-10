// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library dart.http;

import "dart:async";
import "dart:isolate";
import "dart:math";
import "dart:typed_data";

import 'package:http_io/http_io.dart';
import 'package:http_io/src/http_parser.dart';
import 'package:test/test.dart';

class HttpParserTest {
  static void runAllTests() {
    test('parseRequest', testParseRequest);
    test('parseResponse', testParseResponse);
    test('parseInvalidRequest', testParseInvalidRequest);
    test('parseInvalidResponse', testParseInvalidResponse);
  }

  static void _testParseRequest(
      String request, String expectedMethod, String expectedUri,
      {int expectedTransferLength = 0,
      int expectedBytesReceived = 0,
      Map<String, String> expectedHeaders,
      bool chunked = false,
      bool upgrade = false,
      int unparsedLength = 0,
      bool connectionClose = false,
      String expectedVersion = "1.1"}) {
    StreamController<Uint8List> controller;
    void reset() {
      HttpParser httpParser = HttpParser.requestParser();
      controller = StreamController(sync: true);
      var port1 = ReceivePort();
      var port2 = ReceivePort();

      String method;
      Uri uri;
      HttpHeaders headers;
      int bytesReceived;
      int unparsedBytesReceived;
      bool upgraded;

      httpParser.listenToStream(controller.stream);
      httpParser.listen((incoming) {
        method = incoming.method;
        uri = incoming.uri;
        headers = incoming.headers;
        upgraded = incoming.upgraded;
        expect(upgrade, equals(upgraded));

        if (!chunked) {
          expect(expectedTransferLength, equals(incoming.transferLength));
        } else {
          expect(-1, equals(incoming.transferLength));
        }
        if (expectedHeaders != null) {
          expectedHeaders.forEach((String name, String value) =>
              expect(value, equals(headers[name][0])));
        }
        incoming.listen((List<int> data) {
          expect(upgraded, isFalse);
          bytesReceived += data.length;
        }, onDone: () {
          port2.close();
          expect(expectedMethod, equals(method));
          expect(expectedUri, equals(uri.toString()));
          expect(expectedVersion, equals(headers.protocolVersion));
          if (upgrade) {
            expect(0, equals(bytesReceived));
            // port1 is closed by the listener on the detached data.
          } else {
            expect(expectedBytesReceived, equals(bytesReceived));
          }
        });

        if (upgraded) {
          port1.close();
          httpParser.detachIncoming().listen((List<int> data) {
            unparsedBytesReceived += data.length;
          }, onDone: () {
            expect(unparsedLength, equals(unparsedBytesReceived));
            port2.close();
          });
        }

        incoming.dataDone.then((_) {
          port1.close();
        });
      });

      method = null;
      uri = null;
      headers = null;
      bytesReceived = 0;
      unparsedBytesReceived = 0;
      upgraded = false;
    }

    void testWrite(Uint8List requestData, [int chunkSize = -1]) {
      if (chunkSize == -1) chunkSize = requestData.length;
      reset();
      for (int pos = 0; pos < requestData.length; pos += chunkSize) {
        int end = min(requestData.length, pos + chunkSize);
        controller.add(requestData.sublist(pos, end));
      }
      controller.close();
    }

    // Test parsing the request three times delivering the data in
    // different chunks.
    Uint8List requestData = Uint8List.fromList(request.codeUnits);
    testWrite(requestData);
    testWrite(requestData, 10);
    testWrite(requestData, 1);
  }

  static void _testParseRequestLean(
      String request, String expectedMethod, String expectedUri,
      {int expectedTransferLength = 0,
      int expectedBytesReceived = 0,
      Map<String, String> expectedHeaders,
      bool chunked = false,
      bool upgrade = false,
      int unparsedLength = 0,
      bool connectionClose = false,
      String expectedVersion = "1.1"}) {
    _testParseRequest(request, expectedMethod, expectedUri,
        expectedTransferLength: expectedTransferLength,
        expectedBytesReceived: expectedBytesReceived,
        expectedHeaders: expectedHeaders,
        chunked: chunked,
        upgrade: upgrade,
        unparsedLength: unparsedLength,
        connectionClose: connectionClose,
        expectedVersion: expectedVersion);
    // Same test but with only \n instead of \r\n terminating each header line.
    _testParseRequest(request.replaceAll('\r', ''), expectedMethod, expectedUri,
        expectedTransferLength: expectedTransferLength,
        expectedBytesReceived: expectedBytesReceived,
        expectedHeaders: expectedHeaders,
        chunked: chunked,
        upgrade: upgrade,
        unparsedLength: unparsedLength,
        connectionClose: connectionClose,
        expectedVersion: expectedVersion);
  }

  static void _testParseInvalidRequest(String request) {
    HttpParser httpParser;
    bool errorCalled;
    StreamController<Uint8List> controller;

    void reset() {
      httpParser = HttpParser.requestParser();
      controller = StreamController(sync: true);
      var port = ReceivePort();
      httpParser.listenToStream(controller.stream);
      var subscription = httpParser.listen((incoming) {
        fail("Expected request");
      });
      subscription.onError((e) {
        errorCalled = true;
      });
      subscription.onDone(() {
        port.close();
        expect(errorCalled, isTrue);
      });
      errorCalled = false;
    }

    void testWrite(Uint8List requestData, [int chunkSize = -1]) {
      if (chunkSize == -1) chunkSize = requestData.length;
      reset();
      for (int pos = 0;
          pos < requestData.length && !errorCalled;
          pos += chunkSize) {
        int end = min(requestData.length, pos + chunkSize);
        controller.add(requestData.sublist(pos, end));
      }
      controller.close();
    }

    // Test parsing the request three times delivering the data in
    // different chunks.
    Uint8List requestData = Uint8List.fromList(request.codeUnits);
    testWrite(requestData);
    testWrite(requestData, 10);
    testWrite(requestData, 1);
  }

  static void _testParseResponse(
      String response, int expectedStatusCode, String expectedReasonPhrase,
      {int expectedTransferLength = 0,
      int expectedBytesReceived = 0,
      Map<String, String> expectedHeaders,
      bool chunked = false,
      bool close = false,
      String responseToMethod,
      bool connectionClose = false,
      bool upgrade = false,
      int unparsedLength = 0,
      String expectedVersion = "1.1"}) {
    StreamController<Uint8List> controller;

    void reset() {
      HttpParser httpParser;
      bool headersCompleteCalled;
      bool dataEndCalled;
      bool dataEndClose;
      int statusCode;
      String reasonPhrase;
      HttpHeaders headers;
      int bytesReceived;
      httpParser = HttpParser.responseParser();
      controller = StreamController(sync: true);
      var port = ReceivePort();
      httpParser.listenToStream(controller.stream);
      int doneCallCount = 0;
      // Called when done parsing entire message and done parsing body.
      // Only executed when both are done.
      void whenDone() {
        doneCallCount++;
        if (doneCallCount < 2) return;
        expect(expectedVersion, equals(headers.protocolVersion));
        expect(expectedStatusCode, equals(statusCode));
        expect(expectedReasonPhrase, equals(reasonPhrase));
        expect(headersCompleteCalled, isTrue);
        expect(expectedBytesReceived, equals(bytesReceived));
        if (!upgrade) {
          expect(dataEndCalled, isTrue);
          if (close) expect(dataEndClose, isTrue);
          expect(dataEndClose, equals(connectionClose));
        }
      }

      httpParser.listen((incoming) {
        port.close();
        statusCode = incoming.statusCode;
        reasonPhrase = incoming.reasonPhrase;
        headers = incoming.headers;
        expect(headersCompleteCalled, isFalse);
        if (!chunked && !close) {
          expect(expectedTransferLength, equals(incoming.transferLength));
        } else {
          expect(-1, equals(incoming.transferLength));
        }
        if (expectedHeaders != null) {
          expectedHeaders.forEach((String name, String value) {
            expect(value, equals(headers[name][0]));
          });
        }
        expect(upgrade, equals(httpParser.upgrade));
        headersCompleteCalled = true;
        incoming.listen((List<int> data) {
          expect(headersCompleteCalled, isTrue);
          bytesReceived += data.length;
        }, onDone: () {
          dataEndCalled = true;
          dataEndClose = close;
          whenDone();
        });
      }, onDone: whenDone);

      headersCompleteCalled = false;
      dataEndCalled = false;
      dataEndClose = null;
      statusCode = -1;
      reasonPhrase = null;
      headers = null;
      bytesReceived = 0;
    }

    void testWrite(Uint8List requestData, [int chunkSize = -1]) {
      if (chunkSize == -1) chunkSize = requestData.length;
      reset();
      for (int pos = 0; pos < requestData.length; pos += chunkSize) {
        int end = min(requestData.length, pos + chunkSize);
        controller.add(requestData.sublist(pos, end));
      }
      if (close) controller.close();
    }

    // Test parsing the request three times delivering the data in
    // different chunks.
    Uint8List responseData = Uint8List.fromList(response.codeUnits);
    testWrite(responseData);
    testWrite(responseData, 10);
    testWrite(responseData, 1);
  }

  static void _testParseInvalidResponse(String response, [bool close = false]) {
    void testWrite(Uint8List requestData, [int chunkSize = -1]) {
      HttpParser httpParser = HttpParser.responseParser();
      StreamController<Uint8List> controller = StreamController(sync: true);
      bool errorCalled = false;

      if (chunkSize == -1) chunkSize = requestData.length;

      var port = ReceivePort();
      httpParser.listenToStream(controller.stream);
      var subscription = httpParser.listen((incoming) {
        incoming.listen((data) {}, onError: (e) {
          expect(errorCalled, isFalse);
          errorCalled = true;
        });
      });
      subscription.onError((e) {
        expect(errorCalled, isFalse);
        errorCalled = true;
      });
      subscription.onDone(() {
        port.close();
        expect(errorCalled, isTrue);
      });

      errorCalled = false;
      for (int pos = 0;
          pos < requestData.length && !errorCalled;
          pos += chunkSize) {
        int end = min(requestData.length, pos + chunkSize);
        controller.add(requestData.sublist(pos, end));
      }
      controller.close();
    }

    // Test parsing the request three times delivering the data in
    // different chunks.
    Uint8List responseData = Uint8List.fromList(response.codeUnits);
    testWrite(responseData);
    testWrite(responseData, 10);
    testWrite(responseData, 1);
  }

  static void testParseRequest() {
    String request;
    Map<String, String> headers;
    var methods = [
      // RFC 2616 methods.
      "OPTIONS", "GET", "HEAD", "POST", "PUT", "DELETE", "TRACE", "CONNECT",
      // WebDAV methods from RFC 4918.
      "PROPFIND", "PROPPATCH", "MKCOL", "COPY", "MOVE", "LOCK", "UNLOCK",
      // WebDAV methods from RFC 5323.
      "SEARCH",
      // Methods with HTTP prefix.
      "H", "HT", "HTT", "HTTP", "HX", "HTX", "HTTX", "HTTPX"
    ];
    methods = ['GET'];
    methods.forEach((method) {
      request = "$method / HTTP/1.1\r\n\r\n";
      _testParseRequestLean(request, method, "/");
      request = "$method /index.html HTTP/1.1\r\n\r\n";
      _testParseRequestLean(request, method, "/index.html");
    });
    request = "GET / HTTP/1.0\r\n\r\n";
    _testParseRequestLean(request, "GET", "/",
        expectedVersion: "1.0", connectionClose: true);

    request = "GET / HTTP/1.0\r\nConnection: keep-alive\r\n\r\n";
    _testParseRequestLean(request, "GET", "/", expectedVersion: "1.0");

    request = """
POST /test HTTP/1.1\r
AAA: AAA\r
\r
""";
    _testParseRequestLean(request, "POST", "/test");

    request = """
POST /test HTTP/1.1\r
\r
""";
    _testParseRequestLean(request, "POST", "/test");

    request = """
POST /test HTTP/1.1\r
Header-A: AAA\r
X-Header-B: bbb\r
\r
""";
    headers = Map();
    headers["header-a"] = "AAA";
    headers["x-header-b"] = "bbb";
    _testParseRequestLean(request, "POST", "/test", expectedHeaders: headers);

    request = """
POST /test HTTP/1.1\r
Empty-Header-1:\r
Empty-Header-2:\r
        \r
\r
""";
    headers = Map();
    headers["empty-header-1"] = "";
    headers["empty-header-2"] = "";
    _testParseRequestLean(request, "POST", "/test", expectedHeaders: headers);

    request = """
POST /test HTTP/1.1\r
Header-A:   AAA\r
X-Header-B:\t \t bbb\r
\r
""";
    headers = Map();
    headers["header-a"] = "AAA";
    headers["x-header-b"] = "bbb";
    _testParseRequestLean(request, "POST", "/test", expectedHeaders: headers);

    request = """
POST /test HTTP/1.1\r
Header-A:   AA\r
 A\r
X-Header-B:           b\r
  b\r
\t    b\r
\r
""";

    headers = Map();
    headers["header-a"] = "AAA";
    headers["x-header-b"] = "bbb";
    _testParseRequestLean(request, "POST", "/test", expectedHeaders: headers);

    request = """
POST /test HTTP/1.1\r
Content-Length: 10\r
\r
0123456789""";
    _testParseRequestLean(request, "POST", "/test",
        expectedTransferLength: 10, expectedBytesReceived: 10);

    // Test connection close header.
    request = "GET /test HTTP/1.1\r\nConnection: close\r\n\r\n";
    _testParseRequest(request, "GET", "/test", connectionClose: true);

    // Test chunked encoding.
    request = """
POST /test HTTP/1.1\r
Transfer-Encoding: chunked\r
\r
5\r
01234\r
5\r
56789\r
0\r\n\r\n""";
    _testParseRequest(request, "POST", "/test",
        expectedTransferLength: -1, expectedBytesReceived: 10, chunked: true);

    // Test mixing chunked encoding and content length (content length
    // is ignored).
    request = """
POST /test HTTP/1.1\r
Content-Length: 7\r
Transfer-Encoding: chunked\r
\r
5\r
01234\r
5\r
56789\r
0\r\n\r\n""";
    _testParseRequest(request, "POST", "/test",
        expectedTransferLength: -1, expectedBytesReceived: 10, chunked: true);

    // Test mixing chunked encoding and content length (content length
    // is ignored).
    request = """
POST /test HTTP/1.1\r
Transfer-Encoding: chunked\r
Content-Length: 3\r
\r
5\r
01234\r
5\r
56789\r
0\r\n\r\n""";
    _testParseRequest(request, "POST", "/test",
        expectedTransferLength: -1, expectedBytesReceived: 10, chunked: true);

    // Test upper and lower case hex digits in chunked encoding.
    request = """
POST /test HTTP/1.1\r
Transfer-Encoding: chunked\r
\r
1E\r
012345678901234567890123456789\r
1e\r
012345678901234567890123456789\r
0\r\n\r\n""";
    _testParseRequest(request, "POST", "/test",
        expectedTransferLength: -1, expectedBytesReceived: 60, chunked: true);

    // Test chunk extensions in chunked encoding.
    request = """
POST /test HTTP/1.1\r
Transfer-Encoding: chunked\r
\r
1E;xxx\r
012345678901234567890123456789\r
1E;yyy=zzz\r
012345678901234567890123456789\r
0\r\n\r\n""";
    _testParseRequest(request, "POST", "/test",
        expectedTransferLength: -1, expectedBytesReceived: 60, chunked: true);

    // Test HTTP upgrade.
    request = """
GET /irc HTTP/1.1\r
Upgrade: irc/1.2\r
Connection: Upgrade\r
\r\n\x01\x01\x01\x01\x01\x02\x02\x02\x02\xFF""";
    headers = Map();
    headers["upgrade"] = "irc/1.2";
    _testParseRequest(request, "GET", "/irc",
        expectedHeaders: headers, upgrade: true, unparsedLength: 10);

    // Test HTTP upgrade with protocol data.
    request = """
GET /irc HTTP/1.1\r
Upgrade: irc/1.2\r
Connection: Upgrade\r
\r\n""";
    headers = Map();
    headers["upgrade"] = "irc/1.2";
    _testParseRequest(request, "GET", "/irc",
        expectedHeaders: headers, upgrade: true);

    // Test websocket upgrade.
    request = """
GET /chat HTTP/1.1\r
Host: server.example.com\r
Upgrade: websocket\r
Connection: Upgrade\r
Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r
Origin: http://example.com\r
Sec-WebSocket-Version: 13\r
\r\n""";
    headers = Map();
    headers["host"] = "server.example.com";
    headers["upgrade"] = "websocket";
    headers["sec-websocket-key"] = "dGhlIHNhbXBsZSBub25jZQ==";
    headers["origin"] = "http://example.com";
    headers["sec-websocket-version"] = "13";
    _testParseRequest(request, "GET", "/chat",
        expectedHeaders: headers, upgrade: true);

    // Test websocket upgrade with protocol data. NOTE: When using the
    // WebSocket protocol this should never happen as the client
    // should not send protocol data before processing the request
    // part of the opening handshake. However the HTTP parser should
    // still handle this.
    request = """
GET /chat HTTP/1.1\r
Host: server.example.com\r
Upgrade: websocket\r
Connection: Upgrade\r
Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r
Origin: http://example.com\r
Sec-WebSocket-Version: 13\r
\r\n0123456""";
    headers = Map();
    headers["host"] = "server.example.com";
    headers["upgrade"] = "websocket";
    headers["sec-websocket-key"] = "dGhlIHNhbXBsZSBub25jZQ==";
    headers["origin"] = "http://example.com";
    headers["sec-websocket-version"] = "13";
    _testParseRequest(request, "GET", "/chat",
        expectedHeaders: headers, upgrade: true, unparsedLength: 7);
  }

  static void testParseResponse() {
    String response;
    Map<String, String> headers;
    response = "HTTP/1.1 100 Continue\r\nContent-Length: 0\r\n\r\n";
    _testParseResponse(response, 100, "Continue");

    response = "HTTP/1.1 100 Continue\r\nContent-Length: 0\r\n\r\n";
    _testParseResponse(response, 100, "Continue");

    response = "HTTP/1.1 100 Continue\r\nContent-Length: 10\r\n\r\n";
    _testParseResponse(response, 100, "Continue",
        expectedTransferLength: 10, expectedBytesReceived: 0);

    response = "HTTP/1.1 200 OK\r\nContent-Length: 0\r\n"
        "Connection: Close\r\n\r\n";
    _testParseResponse(response, 200, "OK", connectionClose: true);

    response = "HTTP/1.0 200 OK\r\nContent-Length: 0\r\n\r\n";
    _testParseResponse(response, 200, "OK",
        expectedVersion: "1.0", connectionClose: true);

    response = "HTTP/1.0 200 OK\r\nContent-Length: 0\r\n"
        "Connection: Keep-Alive\r\n\r\n";
    _testParseResponse(response, 200, "OK", expectedVersion: "1.0");

    response = "HTTP/1.1 204 No Content\r\nContent-Length: 11\r\n\r\n";
    _testParseResponse(response, 204, "No Content",
        expectedTransferLength: 11, expectedBytesReceived: 0);

    response = "HTTP/1.1 304 Not Modified\r\nContent-Length: 12\r\n\r\n";
    _testParseResponse(response, 304, "Not Modified",
        expectedTransferLength: 12, expectedBytesReceived: 0);

    response = "HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n";
    _testParseResponse(response, 200, "OK");

    response = "HTTP/1.1 404 Not found\r\nContent-Length: 0\r\n\r\n";
    _testParseResponse(response, 404, "Not found");

    response = "HTTP/1.1 500 Server error\r\nContent-Length: 0\r\n\r\n";
    _testParseResponse(response, 500, "Server error");

    // Test response to HEAD request.
    response = """
HTTP/1.1 200 OK\r
Content-Length: 20\r
Content-Type: text/html\r
\r\n""";
    headers = Map();
    headers["content-length"] = "20";
    headers["content-type"] = "text/html";
    _testParseResponse(response, 200, "OK",
        responseToMethod: "HEAD",
        expectedTransferLength: 20,
        expectedBytesReceived: 0,
        expectedHeaders: headers);

    // Test content.
    response = """
HTTP/1.1 200 OK\r
Content-Length: 20\r
\r
01234567890123456789""";
    _testParseResponse(response, 200, "OK",
        expectedTransferLength: 20, expectedBytesReceived: 20);

    // Test upper and lower case hex digits in chunked encoding.
    response = """
HTTP/1.1 200 OK\r
Transfer-Encoding: chunked\r
\r
1A\r
01234567890123456789012345\r
1f\r
0123456789012345678901234567890\r
0\r\n\r\n""";
    _testParseResponse(response, 200, "OK",
        expectedTransferLength: -1, expectedBytesReceived: 57, chunked: true);

    // Test connection close header.
    response = """
HTTP/1.1 200 OK\r
Content-Length: 0\r
Connection: close\r
\r\n""";
    _testParseResponse(response, 200, "OK", connectionClose: true);

    // Test HTTP response without any transfer length indications
    // where closing the connections indicates end of body.
    response = """
HTTP/1.1 200 OK\r
\r
01234567890123456789012345
0123456789012345678901234567890
""";
    _testParseResponse(response, 200, "OK",
        expectedTransferLength: -1,
        expectedBytesReceived: 59,
        close: true,
        connectionClose: true);

    // Test HTTP upgrade.
    response = """
HTTP/1.1 101 Switching Protocols\r
Upgrade: irc/1.2\r
Connection: Upgrade\r
\r\n""";
    headers = Map();
    headers["upgrade"] = "irc/1.2";
    _testParseResponse(response, 101, "Switching Protocols",
        expectedHeaders: headers, upgrade: true);

    // Test HTTP upgrade with protocol data.
    response = """
HTTP/1.1 101 Switching Protocols\r
Upgrade: irc/1.2\r
Connection: Upgrade\r
\r\n\x00\x10\x20\x30\x40\x50\x60\x70\x80\x90\xA0\xB0\xC0\xD0\xE0\xF0""";
    headers = Map();
    headers["upgrade"] = "irc/1.2";
    _testParseResponse(response, 101, "Switching Protocols",
        expectedHeaders: headers, upgrade: true, unparsedLength: 16);

    // Test websocket upgrade.
    response = """
HTTP/1.1 101 Switching Protocols\r
Upgrade: websocket\r
Connection: Upgrade\r
Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=\r
\r\n""";
    headers = Map();
    headers["upgrade"] = "websocket";
    headers["sec-websocket-accept"] = "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=";
    _testParseResponse(response, 101, "Switching Protocols",
        expectedHeaders: headers, upgrade: true);

    // Test websocket upgrade with protocol data.
    response = """
HTTP/1.1 101 Switching Protocols\r
Upgrade: websocket\r
Connection: Upgrade\r
Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=\r
\r\nABCD""";
    headers = Map();
    headers["upgrade"] = "websocket";
    headers["sec-websocket-accept"] = "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=";
    _testParseResponse(response, 101, "Switching Protocols",
        expectedHeaders: headers, upgrade: true, unparsedLength: 4);
  }

  static void testParseInvalidRequest() {
    String request;
    request = "GET /\r\n\r\n";
    _testParseInvalidRequest(request);

    request = "GET / \r\n\r\n";
    _testParseInvalidRequest(request);

    request = "/ HTTP/1.1\r\n\r\n";
    _testParseInvalidRequest(request);

    request = "GET HTTP/1.1\r\n\r\n";
    _testParseInvalidRequest(request);

    request = " / HTTP/1.1\r\n\r\n";
    _testParseInvalidRequest(request);

    request = "@ / HTTP/1.1\r\n\r\n";
    _testParseInvalidRequest(request);

    request = "GET / TTP/1.1\r\n\r\n";
    _testParseInvalidRequest(request);

    request = "GET / HTTP/1.\r\n\r\n";
    _testParseInvalidRequest(request);

    request = "GET / HTTP/1.1\r\nKeep-Alive: False\r\nbadheader\r\n\r\n";
    _testParseInvalidRequest(request);
  }

  static void testParseInvalidResponse() {
    String response;

    response = "HTTP/1.1\r\nContent-Length: 0\r\n\r\n";
    _testParseInvalidResponse(response);

    response = "HTTP/1.1 \r\nContent-Length: 0\r\n\r\n";
    _testParseInvalidResponse(response);

    response = "HTTP/1.1 200\r\nContent-Length: 0\r\n\r\n";
    _testParseInvalidResponse(response);

    response = "HTTP/1.1 200 \r\nContent-Length: 0\r\n\r\n";
    _testParseInvalidResponse(response);

    response = "HTTP/1.1 OK\r\nContent-Length: 0\r\n\r\n";
    _testParseInvalidResponse(response);

    response = "200 OK\r\nContent-Length: 0\r\n\r\n";
    _testParseInvalidResponse(response);

    response = "HTTP/1. 200 OK\r\nContent-Length: 0\r\n\r\n";
    _testParseInvalidResponse(response);

    response = "HTTP/1.1 200 O\rK\r\nContent-Length: 0\r\n\r\n";
    _testParseInvalidResponse(response);

    response = "HTTP/1.1 000 OK\r\nContent-Length: 0\r\n\r\n";
    _testParseInvalidResponse(response);

    response = "HTTP/1.1 999 Server Error\r\nContent-Length: 0\r\n\r\n";
    _testParseInvalidResponse(response);

    response = "HTTP/1.1 200 OK\r\nContent-Length: x\r\n\r\n";
    _testParseInvalidResponse(response);

    response = "HTTP/1.1 200 OK\r\nbadheader\r\n\r\n";
    _testParseInvalidResponse(response);

    response = """
HTTP/1.1 200 OK\r
Transfer-Encoding: chunked\r
\r
1A\r
01234567890123456789012345\r
1g\r
0123456789012345678901234567890\r
0\r\n\r\n""";
    _testParseInvalidResponse(response);
  }
}

void main() {
  HttpParserTest.runAllTests();
}
