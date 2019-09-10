// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

abstract class HttpSession implements Map {
  /// Gets the id for the current session.
  String get id;

  /// Destroys the session. This will terminate the session and any further
  /// connections with this id will be given a new id and session.
  void destroy();

  /// Sets a callback that will be called when the session is timed out.
  set onTimeout(void callback());

  /// Is true if the session has not been sent to the client yet.
  bool get isNew;
}
