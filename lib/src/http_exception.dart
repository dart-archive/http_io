// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io' show IOException;

class HttpException implements IOException {
  final String message;
  final Uri uri;

  const HttpException(this.message, {this.uri});

  String toString() {
    var b = StringBuffer()..write('HttpException: ')..write(message);
    if (uri != null) {
      b.write(', uri = $uri');
    }
    return b.toString();
  }
}
