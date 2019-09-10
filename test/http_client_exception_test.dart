// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import "package:http_io/http_io.dart";
import "package:test/test.dart";

void doExpect(HttpClient client, String url, String error) {
  expect(() => client.getUrl(Uri.parse(url)),
      throwsA(predicate((e) => e.toString().contains(error))));
}

void testInvalidUrl() {
  HttpClient client = HttpClient();
  List<List<String>> tests = <List<String>>[
    <String>["ftp://www.google.com", "Unsupported scheme"],
    <String>["httpx://www.google.com", "Unsupported scheme"],
    <String>["http://user@:1", "No host specified"],
    <String>["http:///", "No host specified"],
    <String>["http:///index.html", "No host specified"],
    <String>["///", "No host specified"],
    <String>["///index.html", "No host specified"],
  ];

  for (List<String> pair in tests) {
    doExpect(client, pair[0], pair[1]);
  }

  expect(() => client.getUrl(Uri.parse("http://::1")), throwsFormatException);
}

void testBadHostName() {
  HttpClient client = HttpClient();
  expect(() => client.get("some.bad.host.name.7654321", 0, "/"),
      throwsA(predicate((e) => e.toString().contains("Failed host lookup"))));
}

void main() {
  test("InvalidUrl", testInvalidUrl);
  test("BadHostName", testBadHostName);
}
