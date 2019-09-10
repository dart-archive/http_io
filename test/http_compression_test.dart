// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import "dart:async";
import "dart:io" hide HttpServer, HttpClient, HttpHeaders;
import 'dart:typed_data';

import "package:http_io/http_io.dart";
import "package:test/test.dart";

Future<Null> testWithData(List<int> data, {bool clientAutoUncompress = true}) {
  Completer<Null> completer = Completer();
  HttpServer.bind("127.0.0.1", 0).then((server) {
    server.autoCompress = true;
    server.listen((request) {
      request.response.add(data);
      request.response.close();
    });
    var client = HttpClient();
    client.autoUncompress = clientAutoUncompress;
    client.get("127.0.0.1", server.port, "/").then((request) {
      request.headers.set(HttpHeaders.ACCEPT_ENCODING, "gzip,deflate");
      return request.close();
    }).then((response) {
      expect(
          "gzip", equals(response.headers.value(HttpHeaders.CONTENT_ENCODING)));
      response.fold(<int>[], (list, b) {
        list.addAll(b);
        return list;
      }).then((list) {
        if (clientAutoUncompress) {
          expect(data, equals(list));
        } else {
          expect(data, equals(gzip.decode(list)));
        }
        server.close();
        client.close();
        completer.complete(null);
      });
    });
  });
  return completer.future;
}

Future<Null> testRawServerCompressData({bool clientAutoUncompress = true}) {
  return testWithData("My raw server provided data".codeUnits,
      clientAutoUncompress: clientAutoUncompress);
}

Future<Null> testServerCompressLong({bool clientAutoUncompress = true}) {
  var longBuffer = Uint8List(1024 * 1024);
  for (int i = 0; i < longBuffer.length; i++) {
    longBuffer[i] = i & 0xFF;
  }
  return testWithData(longBuffer, clientAutoUncompress: clientAutoUncompress);
}

void testServerCompress() {
  group('TestServerCompress', () {
    test('RawServerCompressData', testRawServerCompressData);
    test('RawServerCompressData no client uncompress',
        () => testRawServerCompressData(clientAutoUncompress: false));
    test('ServerCompressLong', testServerCompressLong);
    test('ServerCompressLong no client uncompress',
        () => testServerCompressLong(clientAutoUncompress: false));
  });
}

Future<Null> acceptEncodingHeaderHelper(String encoding, bool valid) {
  Completer<Null> completer = Completer();
  HttpServer.bind("127.0.0.1", 0).then((server) {
    server.autoCompress = true;
    server.listen((request) {
      request.response.write("data");
      request.response.close();
    });
    var client = HttpClient();
    client.get("127.0.0.1", server.port, "/").then((request) {
      request.headers.set(HttpHeaders.ACCEPT_ENCODING, encoding);
      return request.close();
    }).then((response) {
      expect(
          valid,
          equals(("gzip" ==
              response.headers.value(HttpHeaders.CONTENT_ENCODING))));
      response.listen((_) {}, onDone: () {
        server.close();
        client.close();
        completer.complete(null);
      });
    });
  });
  return completer.future;
}

void testAcceptEncodingHeader() {
  group('AcceptEncodingHeader', () {
    test('gzip', () => acceptEncodingHeaderHelper('gzip', true));
    test('deflate', () => acceptEncodingHeaderHelper('deflate', false));
    test('gzip, deflate',
        () => acceptEncodingHeaderHelper('gzip, deflate', true));
    test('gzip ,deflate',
        () => acceptEncodingHeaderHelper('gzip ,deflate', true));
    test('gzip  ,  deflate',
        () => acceptEncodingHeaderHelper('gzip  ,  deflate', true));
    test(
        'deflate,gzip', () => acceptEncodingHeaderHelper('deflate,gzip', true));
    test('deflate, gzip',
        () => acceptEncodingHeaderHelper('deflate, gzip', true));
    test('deflate ,gzip',
        () => acceptEncodingHeaderHelper('deflate ,gzip', true));
    test('deflate  ,  gzip',
        () => acceptEncodingHeaderHelper('deflate  ,  gzip', true));
    test(
        'weird',
        () => acceptEncodingHeaderHelper(
            'abc,deflate  ,  gzip,def,,,ghi  ,jkl', true));
    test('xgzip', () => acceptEncodingHeaderHelper('xgzip', false));
    test('gzipx;', () => acceptEncodingHeaderHelper('gzipx;', false));
  });
}

Future<Null> testDisableCompressTest() {
  Completer<Null> completer = Completer();
  HttpServer.bind("127.0.0.1", 0).then((server) {
    expect(false, equals(server.autoCompress));
    server.listen((request) {
      expect(
          'gzip', equals(request.headers.value(HttpHeaders.ACCEPT_ENCODING)));
      request.response.write("data");
      request.response.close();
    });
    var client = HttpClient();
    client
        .get("127.0.0.1", server.port, "/")
        .then((request) => request.close())
        .then((response) {
      expect(
          null, equals(response.headers.value(HttpHeaders.CONTENT_ENCODING)));
      response.listen((_) {}, onDone: () {
        server.close();
        client.close();
        completer.complete(null);
      });
    });
  });
  return completer.future;
}

void main() {
  testServerCompress();
  testAcceptEncodingHeader();
  test('DisableCompressTest', testDisableCompressTest);
}
