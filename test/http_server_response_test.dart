// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import "dart:async";
import "dart:io" show Directory, File, Platform;
import "dart:typed_data";

import "package:http_io/http_io.dart";
import "package:test/test.dart";

// Platform.script may refer to a AOT or JIT snapshot, which are significantly
// larger.
File scriptSource;

void testServerRequest(void handler(server, request),
    {int bytes, bool closeClient}) {
  HttpServer.bind("127.0.0.1", 0).then((server) {
    server.defaultResponseHeaders.clear();
    server.listen((request) {
      handler(server, request);
    });

    var client = HttpClient();
    // We only close the client on either
    // - Bad response headers
    // - Response done (with optional errors in between).
    client
        .get("127.0.0.1", server.port, "/")
        .then((request) => request.close())
        .then((response) {
      int received = 0;
      StreamSubscription subscription;
      subscription = response.listen((data) {
        if (closeClient == true) {
          subscription.cancel();
          client.close();
        } else {
          received += data.length;
        }
      }, onDone: () {
        if (bytes != null) expect(received, equals(bytes));
        client.close();
      }, onError: (error) {
        expect(error is HttpException, isTrue);
      });
    }).catchError((error) {
      client.close();
    }, test: (e) => e is HttpException);
  });
}

Future<List> testResponseDone() {
  final completers = List<Future<Null>>();
  final completer = Completer<Null>();
  testServerRequest((server, request) {
    request.response.close();
    request.response.done.then((response) {
      expect(request.response, equals(response));
      server.close();
      completer.complete();
    });
  });
  completers.add(completer.future);

  final completer2 = Completer<Null>();
  testServerRequest((server, request) {
    File("__nonexistent_file_")
        .openRead()
        .cast<List<int>>()
        .pipe(request.response)
        .catchError((e) {
      server.close();
      completer2.complete();
    });
  });
  completers.add(completer2.future);

  final completer3 = Completer<Null>();
  testServerRequest((server, request) {
    request.response.done.then((_) {
      server.close();
      completer3.complete();
    });
    request.response.contentLength = 0;
    request.response.close();
  });
  completers.add(completer3.future);

  return Future.wait(completers);
}

Future<List> testResponseAddStream() {
  File file = scriptSource;
  int bytes = file.lengthSync();
  final completers = List<Future<Null>>();
  final completer = Completer<Null>();
  testServerRequest((server, request) {
    request.response.addStream(file.openRead()).then((response) {
      response.close();
      response.done.then((_) {
        server.close();
        completer.complete();
      });
    });
  }, bytes: bytes);
  completers.add(completer.future);

  final completer2 = Completer<Null>();
  testServerRequest((server, request) {
    request.response.addStream(file.openRead()).then((response) {
      request.response.addStream(file.openRead()).then((response) {
        response.close();
        response.done.then((_) {
          server.close();
          completer2.complete();
        });
      });
    });
  }, bytes: bytes * 2);
  completers.add(completer2.future);

  final completer3 = Completer<Null>();
  testServerRequest((server, request) {
    var controller = StreamController<List<int>>(sync: true);
    request.response.addStream(controller.stream).then((response) {
      response.close();
      response.done.then((_) {
        server.close();
        completer3.complete();
      });
    });
    controller.close();
  }, bytes: 0);
  completers.add(completer3.future);

  final completer4 = Completer<Null>();
  testServerRequest((server, request) {
    request.response
        .addStream(File("__nonexistent_file_").openRead())
        .catchError((e) {
      server.close();
      completer4.complete();
    });
  });
  completers.add(completer4.future);

  final completer5 = Completer<Null>();
  testServerRequest((server, request) {
    File("__nonexistent_file_")
        .openRead()
        .cast<List<int>>()
        .pipe(request.response)
        .catchError((e) {
      server.close();
      completer5.complete();
    });
  });
  completers.add(completer5.future);
  return Future.wait(completers);
}

Future<Null> testResponseAddStreamClosed() {
  final completer = Completer<Null>();
  File file = scriptSource;
  testServerRequest((server, request) {
    request.response
        .addStream(file.openRead().cast<List<int>>())
        .then((response) {
      response.close();
      response.done.then((_) => server.close());
    });
  }, closeClient: true);

  testServerRequest((server, request) {
    int count = 0;
    write() {
      request.response.addStream(file.openRead()).then((response) {
        request.response.write("sync data");
        count++;
        if (count < 1000) {
          write();
        } else {
          response.close();
          response.done.then((_) {
            server.close();
            completer.complete();
          });
        }
      });
    }

    write();
  }, closeClient: true);
  return completer.future;
}

Future<List> testResponseAddClosed() {
  File file = scriptSource;
  final completers = List<Future<Null>>();

  final completer = Completer<Null>();
  testServerRequest((server, request) {
    request.response.add(file.readAsBytesSync());
    request.response.close();
    request.response.done.then((_) {
      server.close();
      completer.complete();
    });
  }, closeClient: true);
  completers.add(completer.future);

  final completer2 = Completer<Null>();
  testServerRequest((server, request) {
    for (int i = 0; i < 1000; i++) {
      request.response.add(file.readAsBytesSync());
    }
    request.response.close();
    request.response.done.then((_) {
      server.close();
      completer2.complete();
    });
  }, closeClient: true);
  completers.add(completer2.future);

  final completer3 = Completer<Null>();
  testServerRequest((server, request) {
    int count = 0;
    write() {
      request.response.add(file.readAsBytesSync());
      Timer.run(() {
        count++;
        if (count < 1000) {
          write();
        } else {
          request.response.close();
          request.response.done.then((_) {
            server.close();
            completer3.complete();
          });
        }
      });
    }

    write();
  }, closeClient: true);
  completers.add(completer3.future);
  return Future.wait(completers);
}

Future<List> testBadResponseAdd() {
  final completers = List<Future<Null>>();
  final completer = Completer<Null>();
  testServerRequest((server, request) {
    request.response.contentLength = 0;
    request.response.add([0]);
    request.response.close();
    request.response.done.catchError((error) {
      server.close();
      completer.complete();
    }, test: (e) => e is HttpException);
  });
  completers.add(completer.future);

  final completer2 = Completer<Null>();
  testServerRequest((server, request) {
    request.response.contentLength = 5;
    request.response.add([0, 0, 0]);
    request.response.add([0, 0, 0]);
    request.response.close();
    request.response.done.catchError((error) {
      server.close();
      completer2.complete();
    }, test: (e) => e is HttpException);
  });
  completers.add(completer2.future);

  final completer3 = Completer<Null>();
  testServerRequest((server, request) {
    request.response.contentLength = 0;
    request.response.add(Uint8List(64 * 1024));
    request.response.add(Uint8List(64 * 1024));
    request.response.add(Uint8List(64 * 1024));
    request.response.close();
    request.response.done.catchError((error) {
      server.close();
      completer3.complete();
    }, test: (e) => e is HttpException);
  });
  completers.add(completer3.future);
  return Future.wait(completers);
}

Future<List> testBadResponseClose() {
  final completers = List<Future<Null>>();
  final completer = Completer<Null>();
  testServerRequest((server, request) {
    request.response.contentLength = 5;
    request.response.close();
    request.response.done.catchError((error) {
      server.close();
      completer.complete();
    }, test: (e) => e is HttpException);
  });
  completers.add(completer.future);

  final completer2 = Completer<Null>();
  testServerRequest((server, request) {
    request.response.contentLength = 5;
    request.response.add([0]);
    request.response.close();
    request.response.done.catchError((error) {
      server.close();
      completer2.complete();
    }, test: (e) => e is HttpException);
  });
  completers.add(completer2.future);
  return Future.wait(completers);
}

Future<Null> testIgnoreRequestData() {
  final completer = Completer<Null>();
  HttpServer.bind("127.0.0.1", 0).then((server) {
    server.listen((request) {
      // Ignore request data.
      request.response.write("all-okay");
      request.response.close();
    });

    var client = HttpClient();
    client.get("127.0.0.1", server.port, "/").then((request) {
      request.contentLength = 1024 * 1024;
      request.add(Uint8List(1024 * 1024));
      return request.close();
    }).then((response) {
      response.fold(0, (s, b) => s + b.length).then((bytes) {
        expect(8, equals(bytes));
        server.close();
        completer.complete();
      });
    });
  });
  return completer.future;
}

Future<Null> testWriteCharCode() {
  final completer = Completer<Null>();
  testServerRequest((server, request) {
    // Test that default is latin-1 (only 2 bytes).
    request.response.writeCharCode(0xFF);
    request.response.writeCharCode(0xFF);
    request.response.close().then((_) {
      server.close();
      completer.complete();
    });
  }, bytes: 2);
  return completer.future;
}

void main() {
  scriptSource =
      File('${Directory.current.path}/test/http_server_response_test.dart');
  if (!scriptSource.existsSync()) {
    // If we can't find the file relative to the cwd, then look relative
    // to Platform.script.
    scriptSource = File(
        Platform.script.resolve('http_server_response_test.dart').toFilePath());
  }
  test('responseDone', () => testResponseDone());
  test('responseAddStream', () => testResponseAddStream());
  test('responseAddStreamClosed', () => testResponseAddStreamClosed());
  test('responseAddClosed', () => testResponseAddClosed());
  test('badResponseAdd', () => testBadResponseAdd());
  test('badResponseClose', () => testBadResponseClose());
  test('ignoreRequestData', () => testIgnoreRequestData());
  test('writeCharCode', () => testWriteCharCode());
}
