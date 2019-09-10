// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io' hide HttpClient, HttpServer;

import "package:http_io/http_io.dart";
import "package:test/test.dart";

Future<Null> testBindShared(String host, bool v6Only) async {
  // Sent a single request using a new HttpClient to ensure a new TCP
  // connection is used.
  Future singleRequest(host, port, statusCode) async {
    var client = HttpClient();
    var request = await client.open('GET', host, port, '/');
    var response = await request.close();
    await response.drain();
    expect(statusCode, equals(response.statusCode));
    client.close(force: true);
  }

  Completer server1Request = Completer();
  Completer server2Request = Completer();

  var server1 = await HttpServer.bind(host, 0, v6Only: v6Only, shared: true);
  var port = server1.port;
  expect(port > 0, isTrue);

  var server2 = await HttpServer.bind(host, port, v6Only: v6Only, shared: true);
  expect(server1.address.address, equals(server2.address.address));
  expect(port, equals(server2.port));

  server1.listen((request) {
    server1Request.complete();
    request.response.statusCode = 501;
    request.response.close();
  });

  await singleRequest(host, port, 501);
  await server1.close();

  server2.listen((request) {
    server2Request.complete();
    request.response.statusCode = 502;
    request.response.close();
  });

  await singleRequest(host, port, 502);
  await server2.close();

  await server1Request.future;
  await server2Request.future;
}

void main() {
  test("BindShared ipv4 not v6only", () async {
    const String host = '127.0.0.1';
    await testBindShared(host, false);
  });

  test("BindShared ipv4 v6only", () async {
    const String host = '127.0.0.1';
    await testBindShared(host, true);
  });

  test("BindShared ipv6 not v6only", () async {
    bool useIPv6 = await supportsIPV6();
    if (!useIPv6) return;
    const String host = '::1';
    await testBindShared(host, false);
  });

  test("BindShared ipv6 v6only", () async {
    bool useIPv6 = await supportsIPV6();
    if (!useIPv6) return;
    const String host = '::1';
    await testBindShared(host, true);
  });
}

Future<bool> supportsIPV6() async {
  try {
    var socket = await ServerSocket.bind('::1', 0);
    await socket.close();
    return true;
  } catch (e) {
    return false;
  }
}
