// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import "dart:async";
import "dart:io" show Directory, File, Platform, Socket;

import 'package:http_io/http_io.dart';
import 'package:test/test.dart';

Future<Null> httpServerEarlyClientClose2() {
  final completer = Completer<Null>();
  HttpServer.bind("127.0.0.1", 0).then((server) {
    server.listen((request) {
      String name =
          '${Directory.current.path}/test/http_server_early_client_close2_test.dart';
      if (!File(name).existsSync()) {
        name = Platform.script.toFilePath();
      }
      File(name)
          .openRead()
          .cast<List<int>>()
          .pipe(request.response)
          .catchError((e) {/* ignore */});
    });

    var count = 0;
    makeRequest() {
      Socket.connect("127.0.0.1", server.port).then((socket) {
        var data = "GET / HTTP/1.1\r\nContent-Length: 0\r\n\r\n";
        socket.write(data);
        socket.close();
        socket.done.then((_) {
          socket.destroy();
          if (++count < 10) {
            makeRequest();
          } else {
            server.close();
            completer.complete();
          }
        });
      });
    }

    makeRequest();
  });
  return completer.future;
}

main() {
  test('httpServerEarlyClientClose2', httpServerEarlyClientClose2);
}
