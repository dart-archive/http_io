// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:collection' show HashMap, UnmodifiableMapView;
import 'dart:convert';
import 'dart:io' show BytesBuilder;

import '../http_io.dart'
    show Cookie, ContentType, HttpHeaders, HttpClient, HeaderValue;
import 'char_code.dart';
import 'http_date.dart';
import 'http_exception.dart';

class HttpHeadersImpl implements HttpHeaders {
  final Map<String, List<String>> headers;
  final String protocolVersion;

  bool mutable = true; // Are the headers currently mutable?
  List<String> _noFoldingHeaders;

  int _contentLength = -1;
  bool _persistentConnection = true;
  bool _chunkedTransferEncoding = false;
  String _host;
  int _port;

  final int _defaultPortForScheme;

  HttpHeadersImpl(this.protocolVersion,
      {int defaultPortForScheme = HttpClient.DEFAULT_HTTP_PORT,
      HttpHeadersImpl initialHeaders})
      : headers = HashMap<String, List<String>>(),
        _defaultPortForScheme = defaultPortForScheme {
    if (initialHeaders != null) {
      initialHeaders.headers.forEach((name, value) => headers[name] = value);
      _contentLength = initialHeaders._contentLength;
      _persistentConnection = initialHeaders._persistentConnection;
      _chunkedTransferEncoding = initialHeaders._chunkedTransferEncoding;
      _host = initialHeaders._host;
      _port = initialHeaders._port;
    }
    if (protocolVersion == "1.0") {
      _persistentConnection = false;
      _chunkedTransferEncoding = false;
    }
  }

  List<String> operator [](String name) => headers[name.toLowerCase()];

  String value(String name) {
    name = name.toLowerCase();
    List<String> values = headers[name];
    if (values == null) return null;
    if (values.length > 1) {
      throw HttpException("More than one value for header $name");
    }
    return values[0];
  }

  void add(String name, value) {
    _checkMutable();
    _addAll(_validateField(name), value);
  }

  void _addAll(String name, value) {
    assert(name == _validateField(name));
    if (value is Iterable) {
      for (var v in value) {
        _add(name, _validateValue(v));
      }
    } else {
      _add(name, _validateValue(value));
    }
  }

  void set(String name, Object value) {
    _checkMutable();
    name = _validateField(name);
    headers.remove(name);
    if (name == HttpHeaders.TRANSFER_ENCODING) {
      _chunkedTransferEncoding = false;
    }
    _addAll(name, value);
  }

  void remove(String name, Object value) {
    _checkMutable();
    name = _validateField(name);
    value = _validateValue(value);
    List<String> values = headers[name];
    if (values != null) {
      int index = values.indexOf(value);
      if (index != -1) {
        values.removeRange(index, index + 1);
      }
      if (values.isEmpty) headers.remove(name);
    }
    if (name == HttpHeaders.TRANSFER_ENCODING && value == "chunked") {
      _chunkedTransferEncoding = false;
    }
  }

  void removeAll(String name) {
    _checkMutable();
    name = _validateField(name);
    headers.remove(name);
  }

  void forEach(void f(String name, List<String> values)) {
    headers.forEach(f);
  }

  void noFolding(String name) {
    _noFoldingHeaders ??= List<String>();
    _noFoldingHeaders.add(name);
  }

  bool get persistentConnection => _persistentConnection;

  set persistentConnection(bool persistentConnection) {
    _checkMutable();
    if (persistentConnection == _persistentConnection) return;
    if (persistentConnection) {
      if (protocolVersion == "1.1") {
        remove(HttpHeaders.CONNECTION, "close");
      } else {
        if (_contentLength == -1) {
          throw HttpException(
              "Trying to set 'Connection: Keep-Alive' on HTTP 1.0 headers with "
              "no ContentLength");
        }
        add(HttpHeaders.CONNECTION, "keep-alive");
      }
    } else {
      if (protocolVersion == "1.1") {
        add(HttpHeaders.CONNECTION, "close");
      } else {
        remove(HttpHeaders.CONNECTION, "keep-alive");
      }
    }
    _persistentConnection = persistentConnection;
  }

  int get contentLength => _contentLength;

  set contentLength(int contentLength) {
    _checkMutable();
    if (protocolVersion == "1.0" &&
        persistentConnection &&
        contentLength == -1) {
      throw HttpException(
          "Trying to clear ContentLength on HTTP 1.0 headers with "
          "'Connection: Keep-Alive' set");
    }
    if (_contentLength == contentLength) return;
    _contentLength = contentLength;
    if (_contentLength >= 0) {
      if (chunkedTransferEncoding) chunkedTransferEncoding = false;
      _set(HttpHeaders.CONTENT_LENGTH, contentLength.toString());
    } else {
      removeAll(HttpHeaders.CONTENT_LENGTH);
      if (protocolVersion == "1.1") {
        chunkedTransferEncoding = true;
      }
    }
  }

  bool get chunkedTransferEncoding => _chunkedTransferEncoding;

  set chunkedTransferEncoding(bool chunkedTransferEncoding) {
    _checkMutable();
    if (chunkedTransferEncoding && protocolVersion == "1.0") {
      throw HttpException(
          "Trying to set 'Transfer-Encoding: Chunked' on HTTP 1.0 headers");
    }
    if (chunkedTransferEncoding == _chunkedTransferEncoding) return;
    if (chunkedTransferEncoding) {
      List<String> values = headers[HttpHeaders.TRANSFER_ENCODING];
      if ((values == null || values.last != "chunked")) {
        // Headers does not specify chunked encoding - add it if set.
        _addValue(HttpHeaders.TRANSFER_ENCODING, "chunked");
      }
      contentLength = -1;
    } else {
      // Headers does specify chunked encoding - remove it if not set.
      remove(HttpHeaders.TRANSFER_ENCODING, "chunked");
    }
    _chunkedTransferEncoding = chunkedTransferEncoding;
  }

  String get host => _host;

  set host(String host) {
    _checkMutable();
    _host = host;
    _updateHostHeader();
  }

  int get port => _port;

  set port(int port) {
    _checkMutable();
    _port = port;
    _updateHostHeader();
  }

  DateTime get ifModifiedSince {
    List<String> values = headers[HttpHeaders.IF_MODIFIED_SINCE];
    if (values != null) {
      try {
        return HttpDate.parse(values[0]);
      } on Exception {
        return null;
      }
    }
    return null;
  }

  set ifModifiedSince(DateTime ifModifiedSince) {
    _checkMutable();
    // Format "ifModifiedSince" header with date in Greenwich Mean Time (GMT).
    String formatted = HttpDate.format(ifModifiedSince.toUtc());
    _set(HttpHeaders.IF_MODIFIED_SINCE, formatted);
  }

  DateTime get date {
    List<String> values = headers[HttpHeaders.DATE];
    if (values != null) {
      try {
        return HttpDate.parse(values[0]);
      } on Exception {
        return null;
      }
    }
    return null;
  }

  set date(DateTime date) {
    _checkMutable();
    // Format "DateTime" header with date in Greenwich Mean Time (GMT).
    String formatted = HttpDate.format(date.toUtc());
    _set("date", formatted);
  }

  DateTime get expires {
    List<String> values = headers[HttpHeaders.EXPIRES];
    if (values != null) {
      try {
        return HttpDate.parse(values[0]);
      } on Exception {
        return null;
      }
    }
    return null;
  }

  set expires(DateTime expires) {
    _checkMutable();
    // Format "Expires" header with date in Greenwich Mean Time (GMT).
    String formatted = HttpDate.format(expires.toUtc());
    _set(HttpHeaders.EXPIRES, formatted);
  }

  ContentType get contentType {
    var values = headers["content-type"];
    if (values != null) {
      return ContentType.parse(values[0]);
    } else {
      return null;
    }
  }

  set contentType(ContentType contentType) {
    _checkMutable();
    _set(HttpHeaders.CONTENT_TYPE, contentType.toString());
  }

  void clear() {
    _checkMutable();
    headers.clear();
    _contentLength = -1;
    _persistentConnection = true;
    _chunkedTransferEncoding = false;
    _host = null;
    _port = null;
  }

  // [name] must be a lower-case version of the name.
  void _add(String name, value) {
    assert(name == _validateField(name));
    // Use the length as index on what method to call. This is notable
    // faster than computing hash and looking up in a hash-map.
    switch (name.length) {
      case 4:
        if (HttpHeaders.DATE == name) {
          _addDate(name, value);
          return;
        }
        if (HttpHeaders.HOST == name) {
          _addHost(name, value);
          return;
        }
        break;
      case 7:
        if (HttpHeaders.EXPIRES == name) {
          _addExpires(name, value);
          return;
        }
        break;
      case 10:
        if (HttpHeaders.CONNECTION == name) {
          _addConnection(name, value);
          return;
        }
        break;
      case 12:
        if (HttpHeaders.CONTENT_TYPE == name) {
          _addContentType(name, value);
          return;
        }
        break;
      case 14:
        if (HttpHeaders.CONTENT_LENGTH == name) {
          _addContentLength(name, value);
          return;
        }
        break;
      case 17:
        if (HttpHeaders.TRANSFER_ENCODING == name) {
          _addTransferEncoding(name, value);
          return;
        }
        if (HttpHeaders.IF_MODIFIED_SINCE == name) {
          _addIfModifiedSince(name, value);
          return;
        }
    }
    _addValue(name, value);
  }

  void _addContentLength(String name, value) {
    if (value is int) {
      contentLength = value;
    } else if (value is String) {
      contentLength = int.parse(value);
    } else {
      throw HttpException("Unexpected type for header named $name");
    }
  }

  void _addTransferEncoding(String name, value) {
    if (value == "chunked") {
      chunkedTransferEncoding = true;
    } else {
      _addValue(HttpHeaders.TRANSFER_ENCODING, value);
    }
  }

  void _addDate(String name, value) {
    if (value is DateTime) {
      date = value;
    } else if (value is String) {
      _set(HttpHeaders.DATE, value);
    } else {
      throw HttpException("Unexpected type for header named $name");
    }
  }

  void _addExpires(String name, value) {
    if (value is DateTime) {
      expires = value;
    } else if (value is String) {
      _set(HttpHeaders.EXPIRES, value);
    } else {
      throw HttpException("Unexpected type for header named $name");
    }
  }

  void _addIfModifiedSince(String name, value) {
    if (value is DateTime) {
      ifModifiedSince = value;
    } else if (value is String) {
      _set(HttpHeaders.IF_MODIFIED_SINCE, value);
    } else {
      throw HttpException("Unexpected type for header named $name");
    }
  }

  void _addHost(String name, value) {
    if (value is String) {
      int pos = value.indexOf(":");
      if (pos == -1) {
        _host = value;
        _port = HttpClient.DEFAULT_HTTP_PORT;
      } else {
        if (pos > 0) {
          _host = value.substring(0, pos);
        } else {
          _host = null;
        }
        if (pos + 1 == value.length) {
          _port = HttpClient.DEFAULT_HTTP_PORT;
        } else {
          try {
            _port = int.parse(value.substring(pos + 1));
          } on FormatException {
            _port = null;
          }
        }
      }
      _set(HttpHeaders.HOST, value);
    } else {
      throw HttpException("Unexpected type for header named $name");
    }
  }

  void _addConnection(String name, value) {
    var lowerCaseValue = value.toLowerCase();
    if (lowerCaseValue == 'close') {
      _persistentConnection = false;
    } else if (lowerCaseValue == 'keep-alive') {
      _persistentConnection = true;
    }
    _addValue(name, value);
  }

  void _addContentType(String name, value) {
    _set(HttpHeaders.CONTENT_TYPE, value);
  }

  void _addValue(String name, Object value) {
    List<String> values = headers[name];
    if (values == null) {
      values = List<String>();
      headers[name] = values;
    }
    if (value is DateTime) {
      values.add(HttpDate.format(value));
    } else if (value is String) {
      values.add(value);
    } else {
      values.add(_validateValue(value.toString()));
    }
  }

  void _set(String name, String value) {
    assert(name == _validateField(name));
    List<String> values = List<String>();
    headers[name] = values;
    values.add(value);
  }

  _checkMutable() {
    if (!mutable) throw HttpException("HTTP headers are not mutable");
  }

  _updateHostHeader() {
    bool defaultPort = _port == null || _port == _defaultPortForScheme;
    _set("host", defaultPort ? host : "$host:$_port");
  }

  _foldHeader(String name) {
    if (name == HttpHeaders.SET_COOKIE ||
        (_noFoldingHeaders != null && _noFoldingHeaders.contains(name))) {
      return false;
    }
    return true;
  }

  void finalize() {
    mutable = false;
  }

  void build(BytesBuilder builder) {
    for (String name in headers.keys) {
      List<String> values = headers[name];
      bool fold = _foldHeader(name);
      var nameData = name.codeUnits;
      builder.add(nameData);
      builder.addByte(CharCode.COLON);
      builder.addByte(CharCode.SP);
      for (int i = 0; i < values.length; i++) {
        if (i > 0) {
          if (fold) {
            builder.addByte(CharCode.COMMA);
            builder.addByte(CharCode.SP);
          } else {
            builder.addByte(CharCode.CR);
            builder.addByte(CharCode.LF);
            builder.add(nameData);
            builder.addByte(CharCode.COLON);
            builder.addByte(CharCode.SP);
          }
        }
        builder.add(values[i].codeUnits);
      }
      builder.addByte(CharCode.CR);
      builder.addByte(CharCode.LF);
    }
  }

  String toString() {
    StringBuffer sb = StringBuffer();
    headers.forEach((String name, List<String> values) {
      sb..write(name)..write(": ");
      bool fold = _foldHeader(name);
      for (int i = 0; i < values.length; i++) {
        if (i > 0) {
          if (fold) {
            sb.write(", ");
          } else {
            sb..write("\n")..write(name)..write(": ");
          }
        }
        sb.write(values[i]);
      }
      sb.write("\n");
    });
    return sb.toString();
  }

  List<Cookie> parseCookies() {
    // Parse a Cookie header value according to the rules in RFC 6265.
    var cookies = List<Cookie>();
    void parseCookieString(String s) {
      int index = 0;

      bool done() => index == -1 || index == s.length;

      void skipWS() {
        while (!done()) {
          if (s[index] != " " && s[index] != "\t") return;
          index++;
        }
      }

      String parseName() {
        int start = index;
        while (!done()) {
          if (s[index] == " " || s[index] == "\t" || s[index] == "=") break;
          index++;
        }
        return s.substring(start, index);
      }

      String parseValue() {
        int start = index;
        while (!done()) {
          if (s[index] == " " || s[index] == "\t" || s[index] == ";") break;
          index++;
        }
        return s.substring(start, index);
      }

      bool expect(String expected) {
        if (done()) return false;
        if (s[index] != expected) return false;
        index++;
        return true;
      }

      while (!done()) {
        skipWS();
        if (done()) return;
        String name = parseName();
        skipWS();
        if (!expect("=")) {
          index = s.indexOf(';', index);
          continue;
        }
        skipWS();
        String value = parseValue();
        try {
          cookies.add(CookieImpl(name, value));
        } catch (_) {
          // Skip it, invalid cookie data.
        }
        skipWS();
        if (done()) return;
        if (!expect(";")) {
          index = s.indexOf(';', index);
          continue;
        }
      }
    }

    List<String> values = headers[HttpHeaders.COOKIE];
    if (values != null) {
      values.forEach((headerValue) => parseCookieString(headerValue));
    }
    return cookies;
  }

  static String _validateField(String field) {
    for (var i = 0; i < field.length; i++) {
      if (!CharCode.isTokenChar(field.codeUnitAt(i))) {
        throw FormatException(
            "Invalid HTTP header field name: ${jsonEncode(field)}");
      }
    }
    return field.toLowerCase();
  }

  static T _validateValue<T>(T value) {
    if (value is String) {
      for (var i = 0; i < value.length; i++) {
        if (!CharCode.isValueChar(value.codeUnitAt(i))) {
          throw FormatException(
              "Invalid HTTP header field value: ${jsonEncode(value)}");
        }
      }
    }
    return value;
  }
}

class HeaderValueImpl implements HeaderValue {
  String _value;
  Map<String, String> _parameters;
  Map<String, String> _unmodifiableParameters;

  HeaderValueImpl([this._value = "", Map<String, String> parameters]) {
    if (parameters != null) {
      _parameters = HashMap<String, String>.from(parameters);
    }
  }

  static HeaderValueImpl parse(String value,
      {String parameterSeparator = ";",
      String valueSeparator,
      bool preserveBackslash = false}) {
    // Parse the string.
    var result = HeaderValueImpl();
    result._parse(value, parameterSeparator, valueSeparator, preserveBackslash);
    return result;
  }

  String get value => _value;

  void _ensureParameters() {
    _parameters ??= HashMap<String, String>();
  }

  Map<String, String> get parameters {
    _ensureParameters();
    _unmodifiableParameters ??= UnmodifiableMapView(_parameters);

    return _unmodifiableParameters;
  }

  String toString() {
    StringBuffer sb = StringBuffer();
    sb.write(_value);
    if (parameters != null && parameters.isNotEmpty) {
      _parameters.forEach((String name, String value) {
        sb..write("; ")..write(name)..write("=")..write(value);
      });
    }
    return sb.toString();
  }

  void _parse(String s, String parameterSeparator, String valueSeparator,
      bool preserveBackslash) {
    int index = 0;

    bool done() => index == s.length;

    void skipWS() {
      while (!done()) {
        if (s[index] != " " && s[index] != "\t") return;
        index++;
      }
    }

    String parseValue() {
      int start = index;
      while (!done()) {
        if (s[index] == " " ||
            s[index] == "\t" ||
            s[index] == valueSeparator ||
            s[index] == parameterSeparator) break;
        index++;
      }
      return s.substring(start, index);
    }

    void expect(String expected) {
      if (done() || s[index] != expected) {
        throw HttpException("Failed to parse header value");
      }
      index++;
    }

    void maybeExpect(String expected) {
      if (s[index] == expected) index++;
    }

    void parseParameters() {
      var parameters = HashMap<String, String>();
      _parameters = UnmodifiableMapView(parameters);

      String parseParameterName() {
        int start = index;
        while (!done()) {
          if (s[index] == " " ||
              s[index] == "\t" ||
              s[index] == "=" ||
              s[index] == parameterSeparator ||
              s[index] == valueSeparator) break;
          index++;
        }
        return s.substring(start, index).toLowerCase();
      }

      String parseParameterValue() {
        if (!done() && s[index] == "\"") {
          // Parse quoted value.
          StringBuffer sb = StringBuffer();
          index++;
          while (!done()) {
            if (s[index] == "\\") {
              if (index + 1 == s.length) {
                throw HttpException("Failed to parse header value");
              }
              if (preserveBackslash && s[index + 1] != "\"") {
                sb.write(s[index]);
              }
              index++;
            } else if (s[index] == "\"") {
              index++;
              break;
            }
            sb.write(s[index]);
            index++;
          }
          return sb.toString();
        } else {
          // Parse non-quoted value.
          var val = parseValue();
          return val == "" ? null : val;
        }
      }

      while (!done()) {
        skipWS();
        if (done()) return;
        String name = parseParameterName();
        skipWS();
        if (done()) {
          parameters[name] = null;
          return;
        }
        maybeExpect("=");
        skipWS();
        if (done()) {
          parameters[name] = null;
          return;
        }
        String value = parseParameterValue();
        if (name == 'charset' && this is ContentTypeImpl && value != null) {
          // Charset parameter of ContentTypes are always lower-case.
          value = value.toLowerCase();
        }
        parameters[name] = value;
        skipWS();
        if (done()) return;
        // TODO: Implement support for multi-valued parameters.
        if (s[index] == valueSeparator) return;
        expect(parameterSeparator);
      }
    }

    skipWS();
    _value = parseValue();
    skipWS();
    if (done()) return;
    maybeExpect(parameterSeparator);
    parseParameters();
  }
}

class ContentTypeImpl extends HeaderValueImpl implements ContentType {
  String _primaryType = "";
  String _subType = "";

  ContentTypeImpl(String primaryType, String subType, String charset,
      Map<String, String> parameters)
      : _primaryType = primaryType,
        _subType = subType,
        super("") {
    _primaryType ??= _primaryType = "";
    _subType ??= "";
    _value = "$_primaryType/$_subType";
    if (parameters != null) {
      _ensureParameters();
      parameters.forEach((String key, String value) {
        String lowerCaseKey = key.toLowerCase();
        if (lowerCaseKey == "charset") {
          value = value.toLowerCase();
        }
        this._parameters[lowerCaseKey] = value;
      });
    }
    if (charset != null) {
      _ensureParameters();
      this._parameters["charset"] = charset.toLowerCase();
    }
  }

  ContentTypeImpl._();

  static ContentTypeImpl parse(String value) {
    var result = ContentTypeImpl._();
    result._parse(value, ";", null, false);
    int index = result._value.indexOf("/");
    if (index == -1 || index == (result._value.length - 1)) {
      result._primaryType = result._value.trim().toLowerCase();
      result._subType = "";
    } else {
      result._primaryType =
          result._value.substring(0, index).trim().toLowerCase();
      result._subType = result._value.substring(index + 1).trim().toLowerCase();
    }
    return result;
  }

  String get mimeType => '$primaryType/$subType';

  String get primaryType => _primaryType;

  String get subType => _subType;

  String get charset => parameters["charset"];
}

class CookieImpl implements Cookie {
  String name;
  String value;
  DateTime expires;
  int maxAge;
  String domain;
  String path;
  bool httpOnly = false;
  bool secure = false;

  CookieImpl([this.name, this.value]) {
    // Default value of httponly is true.
    httpOnly = true;
    _validate();
  }

  CookieImpl.fromSetCookieValue(String value) {
    // Parse the 'set-cookie' header value.
    _parseSetCookieValue(value);
  }

  // Parse a 'set-cookie' header value according to the rules in RFC 6265.
  void _parseSetCookieValue(String s) {
    int index = 0;

    bool done() => index == s.length;

    String parseName() {
      int start = index;
      while (!done()) {
        if (s[index] == "=") break;
        index++;
      }
      return s.substring(start, index).trim();
    }

    String parseValue() {
      int start = index;
      while (!done()) {
        if (s[index] == ";") break;
        index++;
      }
      return s.substring(start, index).trim();
    }

    void parseAttributes() {
      String parseAttributeName() {
        int start = index;
        while (!done()) {
          if (s[index] == "=" || s[index] == ";") break;
          index++;
        }
        return s.substring(start, index).trim().toLowerCase();
      }

      String parseAttributeValue() {
        int start = index;
        while (!done()) {
          if (s[index] == ";") break;
          index++;
        }
        return s.substring(start, index).trim().toLowerCase();
      }

      while (!done()) {
        String name = parseAttributeName();
        String value = "";
        if (!done() && s[index] == "=") {
          index++; // Skip the = character.
          value = parseAttributeValue();
        }
        if (name == "expires") {
          expires = parseCookieDate(value);
        } else if (name == "max-age") {
          maxAge = int.parse(value);
        } else if (name == "domain") {
          domain = value;
        } else if (name == "path") {
          path = value;
        } else if (name == "httponly") {
          httpOnly = true;
        } else if (name == "secure") {
          secure = true;
        }
        if (!done()) index++; // Skip the ; character
      }
    }

    name = parseName();
    if (done() || name.isEmpty) {
      throw HttpException("Failed to parse header value [$s]");
    }
    index++; // Skip the = character.
    value = parseValue();
    _validate();
    if (done()) return;
    index++; // Skip the ; character.
    parseAttributes();
  }

  String toString() {
    StringBuffer sb = StringBuffer();
    sb..write(name)..write("=")..write(value);
    if (expires != null) {
      sb..write("; Expires=")..write(HttpDate.format(expires));
    }
    if (maxAge != null) {
      sb..write("; Max-Age=")..write(maxAge);
    }
    if (domain != null) {
      sb..write("; Domain=")..write(domain);
    }
    if (path != null) {
      sb..write("; Path=")..write(path);
    }
    if (secure) sb.write("; Secure");
    if (httpOnly) sb.write("; HttpOnly");
    return sb.toString();
  }

  void _validate() {
    const SEPERATORS = [
      "(",
      ")",
      "<",
      ">",
      "@",
      ",",
      ";",
      ":",
      "\\",
      '"',
      "/",
      "[",
      "]",
      "?",
      "=",
      "{",
      "}"
    ];
    for (int i = 0; i < name.length; i++) {
      int codeUnit = name.codeUnits[i];
      if (codeUnit <= 32 || codeUnit >= 127 || SEPERATORS.contains(name[i])) {
        throw FormatException(
            "Invalid character in cookie name, code unit: '$codeUnit'");
      }
    }
    for (int i = 0; i < value.length; i++) {
      int codeUnit = value.codeUnits[i];
      if (!(codeUnit == 0x21 ||
          (codeUnit >= 0x23 && codeUnit <= 0x2B) ||
          (codeUnit >= 0x2D && codeUnit <= 0x3A) ||
          (codeUnit >= 0x3C && codeUnit <= 0x5B) ||
          (codeUnit >= 0x5D && codeUnit <= 0x7E))) {
        throw FormatException(
            "Invalid character in cookie value, code unit: '$codeUnit'");
      }
    }
  }
}

// Parse a cookie date string.
DateTime parseCookieDate(String date) {
  const List monthsLowerCase = [
    "jan",
    "feb",
    "mar",
    "apr",
    "may",
    "jun",
    "jul",
    "aug",
    "sep",
    "oct",
    "nov",
    "dec"
  ];

  int position = 0;

  void error() {
    throw HttpException("Invalid cookie date $date");
  }

  bool isEnd() => position == date.length;

  bool isDelimiter(String s) {
    int char = s.codeUnitAt(0);
    if (char == 0x09) return true;
    if (char >= 0x20 && char <= 0x2F) return true;
    if (char >= 0x3B && char <= 0x40) return true;
    if (char >= 0x5B && char <= 0x60) return true;
    if (char >= 0x7B && char <= 0x7E) return true;
    return false;
  }

  bool isNonDelimiter(String s) {
    int char = s.codeUnitAt(0);
    if (char >= 0x00 && char <= 0x08) return true;
    if (char >= 0x0A && char <= 0x1F) return true;
    if (char >= 0x30 && char <= 0x39) return true; // Digit
    if (char == 0x3A) return true; // ':'
    if (char >= 0x41 && char <= 0x5A) return true; // Alpha
    if (char >= 0x61 && char <= 0x7A) return true; // Alpha
    if (char >= 0x7F && char <= 0xFF) return true; // Alpha
    return false;
  }

  bool isDigit(String s) {
    int char = s.codeUnitAt(0);
    if (char > 0x2F && char < 0x3A) return true;
    return false;
  }

  int getMonth(String month) {
    if (month.length < 3) return -1;
    return monthsLowerCase.indexOf(month.substring(0, 3));
  }

  int toInt(String s) {
    int index = 0;
    for (; index < s.length && isDigit(s[index]); index++) {}
    return int.parse(s.substring(0, index));
  }

  var tokens = <String>[];
  while (!isEnd()) {
    while (!isEnd() && isDelimiter(date[position])) {
      position++;
    }
    int start = position;
    while (!isEnd() && isNonDelimiter(date[position])) {
      position++;
    }
    tokens.add(date.substring(start, position).toLowerCase());
    while (!isEnd() && isDelimiter(date[position])) {
      position++;
    }
  }

  String timeStr;
  String dayOfMonthStr;
  String monthStr;
  String yearStr;

  for (var token in tokens) {
    if (token.isEmpty) continue;
    if (timeStr == null &&
        token.length >= 5 &&
        isDigit(token[0]) &&
        (token[1] == ":" || (isDigit(token[1]) && token[2] == ":"))) {
      timeStr = token;
    } else if (dayOfMonthStr == null && isDigit(token[0])) {
      dayOfMonthStr = token;
    } else if (monthStr == null && getMonth(token) >= 0) {
      monthStr = token;
    } else if (yearStr == null &&
        token.length >= 2 &&
        isDigit(token[0]) &&
        isDigit(token[1])) {
      yearStr = token;
    }
  }

  if (timeStr == null ||
      dayOfMonthStr == null ||
      monthStr == null ||
      yearStr == null) {
    error();
  }

  int year = toInt(yearStr);
  if (year >= 70 && year <= 99) {
    year += 1900;
  } else if (year >= 0 && year <= 69) year += 2000;
  if (year < 1601) error();

  int dayOfMonth = toInt(dayOfMonthStr);
  if (dayOfMonth < 1 || dayOfMonth > 31) error();

  int month = getMonth(monthStr) + 1;

  var timeList = timeStr.split(":");
  if (timeList.length != 3) error();
  int hour = toInt(timeList[0]);
  int minute = toInt(timeList[1]);
  int second = toInt(timeList[2]);
  if (hour > 23) error();
  if (minute > 59) error();
  if (second > 59) error();

  return DateTime.utc(year, month, dayOfMonth, hour, minute, second, 0);
}
