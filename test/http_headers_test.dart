// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:http_io/http_io.dart';
import 'package:http_io/src/http_headers_impl.dart';
import 'package:test/test.dart';

void testMultiValue() {
  HttpHeadersImpl headers = HttpHeadersImpl("1.1");
  expect(headers[HttpHeaders.PRAGMA], isNull);
  headers.add(HttpHeaders.PRAGMA, "pragma1");
  expect(1, equals(headers[HttpHeaders.PRAGMA].length));
  expect(1, equals(headers["pragma"].length));
  expect(1, equals(headers["Pragma"].length));
  expect(1, equals(headers["PRAGMA"].length));
  expect("pragma1", equals(headers.value(HttpHeaders.PRAGMA)));

  headers.add(HttpHeaders.PRAGMA, "pragma2");
  expect(2, equals(headers[HttpHeaders.PRAGMA].length));
  expect(() => headers.value(HttpHeaders.PRAGMA), throwsA(isException));

  headers.add(HttpHeaders.PRAGMA, ["pragma3", "pragma4"]);
  expect(["pragma1", "pragma2", "pragma3", "pragma4"],
      equals(headers[HttpHeaders.PRAGMA]));

  headers.remove(HttpHeaders.PRAGMA, "pragma3");
  expect(3, equals(headers[HttpHeaders.PRAGMA].length));
  expect(
      ["pragma1", "pragma2", "pragma4"], equals(headers[HttpHeaders.PRAGMA]));

  headers.remove(HttpHeaders.PRAGMA, "pragma3");
  expect(3, equals(headers[HttpHeaders.PRAGMA].length));

  headers.set(HttpHeaders.PRAGMA, "pragma5");
  expect(1, equals(headers[HttpHeaders.PRAGMA].length));

  headers.set(HttpHeaders.PRAGMA, ["pragma6", "pragma7"]);
  expect(2, equals(headers[HttpHeaders.PRAGMA].length));

  headers.removeAll(HttpHeaders.PRAGMA);
  expect(headers[HttpHeaders.PRAGMA], isNull);
}

void testDate() {
  DateTime date1 = DateTime.utc(1999, DateTime.june, 11, 18, 46, 53, 0);
  String httpDate1 = "Fri, 11 Jun 1999 18:46:53 GMT";
  DateTime date2 = DateTime.utc(2000, DateTime.august, 16, 12, 34, 56, 0);
  String httpDate2 = "Wed, 16 Aug 2000 12:34:56 GMT";

  HttpHeadersImpl headers = HttpHeadersImpl("1.1");
  expect(headers.date, isNull);
  headers.date = date1;
  expect(date1, headers.date);
  expect(httpDate1, headers.value(HttpHeaders.DATE));
  expect(1, headers[HttpHeaders.DATE].length);
  headers.add(HttpHeaders.DATE, httpDate2);
  expect(1, headers[HttpHeaders.DATE].length);
  expect(date2, headers.date);
  expect(httpDate2, headers.value(HttpHeaders.DATE));
  headers.set(HttpHeaders.DATE, httpDate1);
  expect(1, headers[HttpHeaders.DATE].length);
  expect(date1, headers.date);
  expect(httpDate1, headers.value(HttpHeaders.DATE));

  headers.set(HttpHeaders.DATE, "xxx");
  expect("xxx", headers.value(HttpHeaders.DATE));
  expect(null, headers.date);
}

void testExpires() {
  DateTime date1 = DateTime.utc(1999, DateTime.june, 11, 18, 46, 53, 0);
  String httpDate1 = "Fri, 11 Jun 1999 18:46:53 GMT";
  DateTime date2 = DateTime.utc(2000, DateTime.august, 16, 12, 34, 56, 0);
  String httpDate2 = "Wed, 16 Aug 2000 12:34:56 GMT";

  HttpHeadersImpl headers = HttpHeadersImpl("1.1");
  expect(headers.expires, isNull);
  headers.expires = date1;
  expect(date1, headers.expires);
  expect(httpDate1, headers.value(HttpHeaders.EXPIRES));
  expect(1, headers[HttpHeaders.EXPIRES].length);
  headers.add(HttpHeaders.EXPIRES, httpDate2);
  expect(1, headers[HttpHeaders.EXPIRES].length);
  expect(date2, headers.expires);
  expect(httpDate2, headers.value(HttpHeaders.EXPIRES));
  headers.set(HttpHeaders.EXPIRES, httpDate1);
  expect(1, headers[HttpHeaders.EXPIRES].length);
  expect(date1, headers.expires);
  expect(httpDate1, headers.value(HttpHeaders.EXPIRES));

  headers.set(HttpHeaders.EXPIRES, "xxx");
  expect("xxx", headers.value(HttpHeaders.EXPIRES));
  expect(null, headers.expires);
}

void testIfModifiedSince() {
  DateTime date1 = DateTime.utc(1999, DateTime.june, 11, 18, 46, 53, 0);
  String httpDate1 = "Fri, 11 Jun 1999 18:46:53 GMT";
  DateTime date2 = DateTime.utc(2000, DateTime.august, 16, 12, 34, 56, 0);
  String httpDate2 = "Wed, 16 Aug 2000 12:34:56 GMT";

  HttpHeadersImpl headers = HttpHeadersImpl("1.1");
  expect(headers.ifModifiedSince, isNull);
  headers.ifModifiedSince = date1;
  expect(date1, headers.ifModifiedSince);
  expect(httpDate1, headers.value(HttpHeaders.IF_MODIFIED_SINCE));
  expect(1, headers[HttpHeaders.IF_MODIFIED_SINCE].length);
  headers.add(HttpHeaders.IF_MODIFIED_SINCE, httpDate2);
  expect(1, headers[HttpHeaders.IF_MODIFIED_SINCE].length);
  expect(date2, headers.ifModifiedSince);
  expect(httpDate2, headers.value(HttpHeaders.IF_MODIFIED_SINCE));
  headers.set(HttpHeaders.IF_MODIFIED_SINCE, httpDate1);
  expect(1, headers[HttpHeaders.IF_MODIFIED_SINCE].length);
  expect(date1, headers.ifModifiedSince);
  expect(httpDate1, headers.value(HttpHeaders.IF_MODIFIED_SINCE));

  headers.set(HttpHeaders.IF_MODIFIED_SINCE, "xxx");
  expect("xxx", headers.value(HttpHeaders.IF_MODIFIED_SINCE));
  expect(null, headers.ifModifiedSince);
}

void testHost() {
  String host = "www.google.com";
  HttpHeadersImpl headers = HttpHeadersImpl("1.1");
  expect(headers.host, isNull);
  expect(headers.port, isNull);
  headers.host = host;
  expect(host, headers.value(HttpHeaders.HOST));
  headers.port = 1234;
  expect("$host:1234", headers.value(HttpHeaders.HOST));
  headers.port = HttpClient.DEFAULT_HTTP_PORT;
  expect(host, headers.value(HttpHeaders.HOST));

  headers = HttpHeadersImpl("1.1");
  headers.add(HttpHeaders.HOST, host);
  expect(host, headers.host);
  expect(HttpClient.DEFAULT_HTTP_PORT, headers.port);
  headers.add(HttpHeaders.HOST, "$host:4567");
  expect(1, headers[HttpHeaders.HOST].length);
  expect(host, headers.host);
  expect(4567, headers.port);

  headers = HttpHeadersImpl("1.1");
  headers.add(HttpHeaders.HOST, "$host:xxx");
  expect("$host:xxx", headers.value(HttpHeaders.HOST));
  expect(host, headers.host);
  expect(headers.port, isNull);

  headers = HttpHeadersImpl("1.1");
  headers.add(HttpHeaders.HOST, ":1234");
  expect(":1234", headers.value(HttpHeaders.HOST));
  expect(headers.host, isNull);
  expect(1234, headers.port);
}

void testTransferEncoding() {
  expectChunked(headers) {
    expect(headers['transfer-encoding'], ['chunked']);
    expect(headers.chunkedTransferEncoding, isTrue);
  }

  expectNonChunked(headers) {
    expect(headers['transfer-encoding'], isNull);
    expect(headers.chunkedTransferEncoding, isFalse);
  }

  HttpHeadersImpl headers;

  headers = HttpHeadersImpl("1.1");
  headers.chunkedTransferEncoding = true;
  expectChunked(headers);
  headers.set('transfer-encoding', ['chunked']);
  expectChunked(headers);

  headers = HttpHeadersImpl("1.1");
  headers.set('transfer-encoding', ['chunked']);
  expectChunked(headers);
  headers.chunkedTransferEncoding = true;
  expectChunked(headers);

  headers = HttpHeadersImpl("1.1");
  headers.chunkedTransferEncoding = true;
  headers.chunkedTransferEncoding = false;
  expectNonChunked(headers);

  headers = HttpHeadersImpl("1.1");
  headers.chunkedTransferEncoding = true;
  headers.remove('transfer-encoding', 'chunked');
  expectNonChunked(headers);

  headers = HttpHeadersImpl("1.1");
  headers.set('transfer-encoding', ['chunked']);
  headers.chunkedTransferEncoding = false;
  expectNonChunked(headers);

  headers = HttpHeadersImpl("1.1");
  headers.set('transfer-encoding', ['chunked']);
  headers.remove('transfer-encoding', 'chunked');
  expectNonChunked(headers);
}

void testEnumeration() {
  HttpHeadersImpl headers = HttpHeadersImpl("1.1");
  expect(headers[HttpHeaders.PRAGMA], isNull);
  headers.add("My-Header-1", "value 1");
  headers.add("My-Header-2", "value 2");
  headers.add("My-Header-1", "value 3");
  bool myHeader1 = false;
  bool myHeader2 = false;
  int totalValues = 0;
  headers.forEach((String name, List<String> values) {
    totalValues += values.length;
    if (name == "my-header-1") {
      myHeader1 = true;
      expect(values, contains("value 1"));
      expect(values, contains("value 3"));
    }
    if (name == "my-header-2") {
      myHeader2 = true;
      expect(values, contains("value 2"));
    }
  });
  expect(myHeader1, isTrue);
  expect(myHeader2, isTrue);
  expect(3, totalValues);
}

void testHeaderValue() {
  void check(HeaderValue headerValue, String value,
      [Map<String, String> parameters]) {
    expect(value, headerValue.value);
    if (parameters != null) {
      expect(parameters.length, headerValue.parameters.length);
      parameters.forEach((String name, String value) {
        expect(value, headerValue.parameters[name]);
      });
    } else {
      expect(0, headerValue.parameters.length);
    }
  }

  HeaderValue headerValue;
  headerValue =
      HeaderValue.parse("xxx; aaa=bbb; ccc=\"\\\";\\a\"; ddd=\"    \"");
  check(headerValue, "xxx", {"aaa": "bbb", "ccc": '\";a', "ddd": "    "});
  headerValue =
      HeaderValue("xxx", {"aaa": "bbb", "ccc": '\";a', "ddd": "    "});
  check(headerValue, "xxx", {"aaa": "bbb", "ccc": '\";a', "ddd": "    "});

  headerValue = HeaderValue.parse("attachment; filename=genome.jpeg;"
      "modification-date=\"Wed, 12 February 1997 16:29:51 -0500\"");
  var parameters = {
    "filename": "genome.jpeg",
    "modification-date": "Wed, 12 February 1997 16:29:51 -0500"
  };
  check(headerValue, "attachment", parameters);
  headerValue = HeaderValue("attachment", parameters);
  check(headerValue, "attachment", parameters);
  headerValue = HeaderValue.parse("  attachment  ;filename=genome.jpeg  ;"
      "modification-date = \"Wed, 12 February 1997 16:29:51 -0500\"");
  check(headerValue, "attachment", parameters);
  headerValue = HeaderValue.parse("xxx; aaa; bbb; ccc");
  check(headerValue, "xxx", {"aaa": null, "bbb": null, "ccc": null});
}

void testContentType() {
  void check(ContentType contentType, String primaryType, String subType,
      [Map<String, String> parameters]) {
    expect(primaryType, contentType.primaryType);
    expect(subType, contentType.subType);
    expect("$primaryType/$subType", contentType.value);
    if (parameters != null) {
      expect(parameters.length, contentType.parameters.length);
      parameters.forEach((String name, String value) {
        expect(value, contentType.parameters[name]);
      });
    } else {
      expect(0, contentType.parameters.length);
    }
  }

  ContentType contentType;
  contentType = ContentType("", "");
  expect("", contentType.primaryType);
  expect("", contentType.subType);
  expect("/", contentType.value);
  expect(
      () => contentType.parameters["xxx"] = "yyy", throwsA(isUnsupportedError));

  contentType = ContentType.parse("text/html");
  check(contentType, "text", "html");
  expect("text/html", contentType.toString());
  contentType = ContentType("text", "html", charset: "utf-8");
  check(contentType, "text", "html", {"charset": "utf-8"});
  expect("text/html; charset=utf-8", contentType.toString());
  expect(
      () => contentType.parameters["xxx"] = "yyy", throwsA(isUnsupportedError));

  contentType = ContentType("text", "html",
      parameters: {"CHARSET": "UTF-8", "xxx": "YYY"});
  check(contentType, "text", "html", {"charset": "utf-8", "xxx": "YYY"});
  String s = contentType.toString();
  bool expectedToString = (s == "text/html; charset=utf-8; xxx=YYY" ||
      s == "text/html; xxx=YYY; charset=utf-8");
  expect(expectedToString, isTrue);
  contentType = ContentType.parse("text/html; CHARSET=UTF-8; xxx=YYY");
  check(contentType, "text", "html", {"charset": "utf-8", "xxx": "YYY"});
  expect(
      () => contentType.parameters["xxx"] = "yyy", throwsA(isUnsupportedError));

  contentType = ContentType("text", "html",
      charset: "ISO-8859-1", parameters: {"CHARSET": "UTF-8", "xxx": "yyy"});
  check(contentType, "text", "html", {"charset": "iso-8859-1", "xxx": "yyy"});
  s = contentType.toString();
  expectedToString = (s == "text/html; charset=iso-8859-1; xxx=yyy" ||
      s == "text/html; xxx=yyy; charset=iso-8859-1");
  expect(expectedToString, isTrue);

  contentType = ContentType.parse("text/html");
  check(contentType, "text", "html");
  contentType = ContentType.parse(" text/html  ");
  check(contentType, "text", "html");
  contentType = ContentType.parse("text/html; charset=utf-8");
  check(contentType, "text", "html", {"charset": "utf-8"});
  contentType = ContentType.parse("  text/html  ;  charset  =  utf-8  ");
  check(contentType, "text", "html", {"charset": "utf-8"});
  contentType = ContentType.parse("text/html; charset=utf-8; xxx=yyy");
  check(contentType, "text", "html", {"charset": "utf-8", "xxx": "yyy"});
  contentType =
      ContentType.parse("  text/html  ;  charset  =  utf-8  ;  xxx=yyy  ");
  check(contentType, "text", "html", {"charset": "utf-8", "xxx": "yyy"});
  contentType = ContentType.parse('text/html; charset=utf-8; xxx="yyy"');
  check(contentType, "text", "html", {"charset": "utf-8", "xxx": "yyy"});
  contentType =
      ContentType.parse("  text/html  ;  charset  =  utf-8  ;  xxx=yyy  ");
  check(contentType, "text", "html", {"charset": "utf-8", "xxx": "yyy"});

  contentType = ContentType.parse("text/html; charset=;");
  check(contentType, "text", "html", {"charset": null});
  contentType = ContentType.parse("text/html; charset;");
  check(contentType, "text", "html", {"charset": null});

  // Test builtin content types.
  check(ContentType.TEXT, "text", "plain", {"charset": "utf-8"});
  check(ContentType.HTML, "text", "html", {"charset": "utf-8"});
  check(ContentType.JSON, "application", "json", {"charset": "utf-8"});
  check(ContentType.BINARY, "application", "octet-stream");
}

void testKnownContentTypes() {
  // Well known content types used by the VM service.
  ContentType.parse('text/html; charset=UTF-8');
  ContentType.parse('application/dart; charset=UTF-8');
  ContentType.parse('application/javascript; charset=UTF-8');
  ContentType.parse('text/css; charset=UTF-8');
  ContentType.parse('image/gif');
  ContentType.parse('image/png');
  ContentType.parse('image/jpeg');
  ContentType.parse('image/jpeg');
  ContentType.parse('image/svg+xml');
  ContentType.parse('text/plain');
}

void testContentTypeCache() {
  HttpHeadersImpl headers = HttpHeadersImpl("1.1");
  headers.set(HttpHeaders.CONTENT_TYPE, "text/html");
  expect("text", headers.contentType.primaryType);
  expect("html", headers.contentType.subType);
  expect("text/html", headers.contentType.value);
  headers.set(HttpHeaders.CONTENT_TYPE, "text/plain; charset=utf-8");
  expect("text", headers.contentType.primaryType);
  expect("plain", headers.contentType.subType);
  expect("text/plain", headers.contentType.value);
  headers.removeAll(HttpHeaders.CONTENT_TYPE);
  expect(headers.contentType, isNull);
}

void testCookie() {
  test(String name, String value) {
    void checkCookiesEquals(a, b) {
      expect(a.name, b.name);
      expect(a.value, b.value);
      expect(a.expires, b.expires);
      expect(a.toString(), b.toString());
    }

    void checkCookie(cookie, s) {
      expect(s, cookie.toString());
      var c = Cookie.fromSetCookieValue(s);
      checkCookiesEquals(cookie, c);
    }

    Cookie cookie;
    cookie = Cookie(name, value);
    expect("$name=$value; HttpOnly", cookie.toString());
    DateTime date = DateTime.utc(2014, DateTime.january, 5, 23, 59, 59, 0);
    cookie.expires = date;
    checkCookie(
        cookie,
        "$name=$value"
        "; Expires=Sun, 05 Jan 2014 23:59:59 GMT"
        "; HttpOnly");
    cookie.maxAge = 567;
    checkCookie(
        cookie,
        "$name=$value"
        "; Expires=Sun, 05 Jan 2014 23:59:59 GMT"
        "; Max-Age=567"
        "; HttpOnly");
    cookie.domain = "example.com";
    checkCookie(
        cookie,
        "$name=$value"
        "; Expires=Sun, 05 Jan 2014 23:59:59 GMT"
        "; Max-Age=567"
        "; Domain=example.com"
        "; HttpOnly");
    cookie.path = "/xxx";
    checkCookie(
        cookie,
        "$name=$value"
        "; Expires=Sun, 05 Jan 2014 23:59:59 GMT"
        "; Max-Age=567"
        "; Domain=example.com"
        "; Path=/xxx"
        "; HttpOnly");
    cookie.secure = true;
    checkCookie(
        cookie,
        "$name=$value"
        "; Expires=Sun, 05 Jan 2014 23:59:59 GMT"
        "; Max-Age=567"
        "; Domain=example.com"
        "; Path=/xxx"
        "; Secure"
        "; HttpOnly");
    cookie.httpOnly = false;
    checkCookie(
        cookie,
        "$name=$value"
        "; Expires=Sun, 05 Jan 2014 23:59:59 GMT"
        "; Max-Age=567"
        "; Domain=example.com"
        "; Path=/xxx"
        "; Secure");
    cookie.expires = null;
    checkCookie(
        cookie,
        "$name=$value"
        "; Max-Age=567"
        "; Domain=example.com"
        "; Path=/xxx"
        "; Secure");
    cookie.maxAge = null;
    checkCookie(
        cookie,
        "$name=$value"
        "; Domain=example.com"
        "; Path=/xxx"
        "; Secure");
    cookie.domain = null;
    checkCookie(
        cookie,
        "$name=$value"
        "; Path=/xxx"
        "; Secure");
    cookie.path = null;
    checkCookie(
        cookie,
        "$name=$value"
        "; Secure");
    cookie.secure = false;
    checkCookie(cookie, "$name=$value");
  }

  test("name", "value");
  test("abc", "def");
  test("ABC", "DEF");
  test("Abc", "Def");
  test("SID", "sJdkjKSJD12343kjKj78");
}

void testInvalidCookie() {
  expect(() => Cookie.fromSetCookieValue(""), throwsA(isException));
  expect(() => Cookie.fromSetCookieValue("="), throwsA(isException));
  expect(() => Cookie.fromSetCookieValue("=xxx"), throwsA(isException));
  expect(() => Cookie.fromSetCookieValue("xxx"), throwsA(isException));
  expect(() => Cookie.fromSetCookieValue("xxx=yyy; expires=12 jan 2013"),
      throwsA(isException));
  expect(() => Cookie.fromSetCookieValue("x x = y y"), throwsA(isException));
  expect(() => Cookie("[4", "y"), throwsA(isException));
  expect(() => Cookie("4", "y\""), throwsA(isException));

  HttpHeadersImpl headers = HttpHeadersImpl("1.1");
  headers.set(
      'Cookie', 'DARTSESSID=d3d6fdd78d51aaaf2924c32e991f4349; undefined');
  expect('DARTSESSID', headers.parseCookies().single.name);
  expect(
      'd3d6fdd78d51aaaf2924c32e991f4349', headers.parseCookies().single.value);
}

void testHeaderLists() {
  HttpHeaders.GENERAL_HEADERS.forEach((x) => null);
  HttpHeaders.ENTITY_HEADERS.forEach((x) => null);
  HttpHeaders.RESPONSE_HEADERS.forEach((x) => null);
  HttpHeaders.REQUEST_HEADERS.forEach((x) => null);
}

void testInvalidFieldName() {
  void test(String field) {
    HttpHeadersImpl headers = HttpHeadersImpl("1.1");
    expect(() => headers.add(field, "value"), throwsA(isFormatException));
    expect(() => headers.set(field, "value"), throwsA(isFormatException));
    expect(() => headers.remove(field, "value"), throwsA(isFormatException));
    expect(() => headers.removeAll(field), throwsA(isFormatException));
  }

  test('\r');
  test('\n');
  test(',');
  test('test\x00');
}

void testInvalidFieldValue() {
  void test(value, {bool remove = true}) {
    HttpHeadersImpl headers = HttpHeadersImpl("1.1");
    expect(() => headers.add("field", value), throwsA(isFormatException));
    expect(() => headers.set("field", value), throwsA(isFormatException));
    if (remove) {
      expect(() => headers.remove("field", value), throwsA(isFormatException));
    }
  }

  test('\r');
  test('\n');
  test('test\x00');
  // Test we handle other types correctly.
  test(StringBuffer('\x00'), remove: false);
}

void testClear() {
  HttpHeadersImpl headers = HttpHeadersImpl("1.1");
  headers.add("a", "b");
  headers.contentLength = 7;
  headers.chunkedTransferEncoding = true;
  headers.clear();
  expect(headers["a"], isNull);
  expect(headers.contentLength, -1);
  expect(headers.chunkedTransferEncoding, isFalse);
}

main() {
  test('multiValue', testMultiValue);
  test('date', testDate);
  test('expires', testExpires);
  test('ifModifiedSince', testIfModifiedSince);
  test('host', testHost);
  test('transferEncoding', testTransferEncoding);
  test('enumeration', testEnumeration);
  test('headerValue', testHeaderValue);
  test('contentType', testContentType);
  test('knownContentTypes', testKnownContentTypes);
  test('contentTypeCache', testContentTypeCache);
  test('cookie', testCookie);
  test('invalidCookie', testInvalidCookie);
  test('headerLists', testHeaderLists);
  test('invalidFieldName', testInvalidFieldName);
  test('invalidFieldValue', testInvalidFieldValue);
  test('clear', testClear);
}
