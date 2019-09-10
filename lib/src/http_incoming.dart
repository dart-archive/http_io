// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'http_exception.dart';
import 'http_headers_impl.dart';

class HttpIncoming extends Stream<List<int>> {
  final int _transferLength;
  final _dataCompleter = Completer<bool>();
  final Stream<List<int>> _stream;

  bool fullBodyRead = false;

  // Common properties.
  final HttpHeadersImpl headers;
  bool upgraded = false;

  // ClientResponse properties.
  int statusCode;
  String reasonPhrase;

  // Request properties.
  String method;
  Uri uri;

  bool hasSubscriber = false;

  // The transfer length if the length of the message body as it
  // appears in the message (RFC 2616 section 4.4). This can be -1 if
  // the length of the massage body is not known due to transfer
  // codings.
  int get transferLength => _transferLength;

  HttpIncoming(this.headers, this._transferLength, this._stream);

  StreamSubscription<List<int>> listen(void onData(List<int> event),
      {Function onError, void onDone(), bool cancelOnError}) {
    hasSubscriber = true;
    return _stream.handleError((error) {
      throw HttpException(error.message, uri: uri);
    }).listen(onData,
        onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }

  // Is completed once all data have been received.
  Future<bool> get dataDone => _dataCompleter.future;

  void close(bool closing) {
    fullBodyRead = true;
    hasSubscriber = true;
    _dataCompleter.complete(closing);
  }
}
