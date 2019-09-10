// Copyright (c) 2018, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// This test verifies that secure connections that fail due to
// unauthenticated certificates throw exceptions in HttpClient.

import "dart:async";
import 'dart:io'
    show
        Directory,
        File,
        HandshakeException,
        Platform,
        Process,
        ProcessResult,
        SecurityContext;

import 'package:http_io/http_io.dart';
import "package:test/test.dart";

const HOST_NAME = "localhost";
const CERTIFICATE = "localhost_cert";

String localFile(path) {
  var script = "${Directory.current.path}/test/$path";
  if (!(File(script)).existsSync()) {
    // If we can't find the file relative to the cwd, then look relative to
    // Platform.script.
    script = Platform.script.resolve(path).toFilePath();
  }
  return script;
}

SecurityContext untrustedServerContext = SecurityContext()
  ..useCertificateChain(localFile('certificates/untrusted_server_chain.pem'))
  ..usePrivateKey(localFile('certificates/untrusted_server_key.pem'),
      password: 'dartdart');

SecurityContext clientContext = SecurityContext()
  ..setTrustedCertificates(localFile('certificates/trusted_certs.pem'));

Future<HttpServer> runServer() {
  return HttpServer.bindSecure(HOST_NAME, 0, untrustedServerContext, backlog: 5)
      .then((server) {
    server.listen((HttpRequest request) {
      request.listen((_) {}, onDone: () {
        request.response.close();
      });
    }, onError: (e) {
      if (e is! HandshakeException) throw e;
    });
    return server;
  });
}

Future<Null> runTest() {
  final completer = Completer<Null>();
  var clientScript = localFile('https_unauthorized_client.dart');
  Future clientProcess(int port) {
    return Process.run(Platform.executable, [clientScript, port.toString()])
        .then((ProcessResult result) {
      if (result.exitCode != 0 || !result.stdout.contains('SUCCESS')) {
        print("Client failed");
        print("  stdout:");
        print(result.stdout);
        print("  stderr:");
        print(result.stderr);
        fail('Client subprocess exit code: ${result.exitCode}');
      }
    });
  }

  runServer().then((server) {
    clientProcess(server.port).then((_) {
      server.close();
      completer.complete();
    });
  });
  return completer.future;
}

void main() {
  test('httpsUnauthorized', runTest);
}
