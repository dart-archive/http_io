// Copyright (c) 2018, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library dart.http;

import 'package:http_io/http_io.dart';
import 'package:http_io/src/http_headers_impl.dart';
import 'package:test/test.dart';

void testParseHttpCookieDate() {
  expect(() => parseCookieDate(""), throwsA(TypeMatcher<HttpException>()));

  test(int year, int month, int day, int hours, int minutes, int seconds,
      String formatted) {
    DateTime date = DateTime.utc(year, month, day, hours, minutes, seconds, 0);
    expect(date, parseCookieDate(formatted));
  }

  test(2012, DateTime.june, 19, 14, 15, 01, "tue, 19-jun-12 14:15:01 gmt");
  test(2021, DateTime.june, 09, 10, 18, 14, "Wed, 09-Jun-2021 10:18:14 GMT");
  test(2021, DateTime.january, 13, 22, 23, 01, "Wed, 13-Jan-2021 22:23:01 GMT");
  test(2013, DateTime.january, 15, 21, 47, 38, "Tue, 15-Jan-2013 21:47:38 GMT");
  test(1970, DateTime.january, 01, 00, 00, 01, "Thu, 01-Jan-1970 00:00:01 GMT");
}

void main() {
  test('parseHttpCookieDate', testParseHttpCookieDate);
}
