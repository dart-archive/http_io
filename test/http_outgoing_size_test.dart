// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:typed_data';

import 'package:http_io/http_io.dart';
import 'package:test/test.dart';

Future<Null> testChunkedBufferSizeMsg() {
  final completer = Completer<Null>();
  // Buffer of same size as our internal buffer, minus 4. Makes us hit the
  // boundary.
  var sendData = Uint8List(8 * 1024 - 4);
  for (int i = 0; i < sendData.length; i++) {
    sendData[i] = i % 256;
  }

  HttpServer.bind('127.0.0.1', 0).then((server) {
    server.listen((request) {
      // Chunked is on by default. Be sure no data is lost when sending several
      // chunks of data.
      request.response.add(sendData);
      request.response.add(sendData);
      request.response.add(sendData);
      request.response.add(sendData);
      request.response.add(sendData);
      request.response.add(sendData);
      request.response.add(sendData);
      request.response.add(sendData);
      request.response.close();
    });
    var client = HttpClient();
    client.get('127.0.0.1', server.port, '/').then((request) {
      request.headers.set(HttpHeaders.ACCEPT_ENCODING, "");
      return request.close();
    }).then((response) {
      var buffer = [];
      response.listen((data) => buffer.addAll(data), onDone: () {
        expect(sendData.length * 8, equals(buffer.length));
        for (int i = 0; i < buffer.length; i++) {
          expect(sendData[i % sendData.length], equals(buffer[i]));
        }
        server.close();
        completer.complete();
      });
    });
  });
  return completer.future;
}

void main() {
  test('chunkedBufferSizeMessage', testChunkedBufferSizeMsg);
}
