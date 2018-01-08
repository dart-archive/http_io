// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

class CryptoUtils {
  static final Random _rng = new Random.secure();

  static Uint8List getRandomBytes(int count) {
    final Uint8List result = new Uint8List(count);
    for (int i = 0; i < count; i++) {
      result[i] = _rng.nextInt(0xff);
    }
    return result;
  }

  static String bytesToHex(List<int> bytes) {
    var result = new StringBuffer();
    for (var part in bytes) {
      result.write(part.toRadixString(16).padLeft(2, '0'));
    }
    return result.toString();
  }

  static String userNamePasswordBase64(String userName, String password) =>
      stringToUtf8Base64('$userName:$password');

  static String stringToUtf8Base64(String input) =>
      BASE64.encode(UTF8.encode(input));
}

/// Convenience class that emulates the older MD5 class fromm `package:crypto`.
class MD5 {
  final _DigestSink _digestSink;
  final ByteConversionSink _conversionSink;

  MD5._(this._digestSink, this._conversionSink);

  factory MD5() {
    var digestSink = new _DigestSink();
    var conversionSink = md5.startChunkedConversion(digestSink);
    return new MD5._(digestSink, conversionSink);
  }

  void add(List<int> bytes) {
    _conversionSink.add(bytes);
  }

  List<int> close() {
    _conversionSink.close();
    return _digestSink.value.bytes;
  }
}

/// A sink used to get a digest value out of `Hash.startChunkedConversion`.
///
/// From github.com/dart-lang/crypto/blob/30ec20b7f6c94/lib/src/digest_sink.dart
class _DigestSink extends Sink<Digest> {
  /// The value added to the sink, if any.
  Digest get value {
    assert(_value != null);
    return _value;
  }

  Digest _value;

  /// Adds [value] to the sink.
  ///
  /// Unlike most sinks, this may only be called once.
  @override
  void add(Digest value) {
    assert(_value == null);
    _value = value;
  }

  @override
  void close() {
    assert(_value != null);
  }
}
