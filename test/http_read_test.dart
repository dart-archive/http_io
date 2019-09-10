// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:isolate';

import 'package:http_io/http_io.dart';
import 'package:test/test.dart';

class IsolatedHttpServer {
  IsolatedHttpServer()
      : _statusPort = ReceivePort(),
        _serverPort = null;

  void setServerStartedHandler(void startedCallback(int port)) {
    _startedCallback = startedCallback;
  }

  void start([bool chunkedEncoding = false]) {
    ReceivePort receivePort = ReceivePort();
    Isolate.spawn(startIsolatedHttpServer, receivePort.sendPort);
    receivePort.first.then((port) {
      _serverPort = port;

      if (chunkedEncoding) {
        // Send chunked encoding message to the server.
        port.send([
          IsolatedHttpServerCommand.chunkedEncoding(),
          _statusPort.sendPort
        ]);
      }

      // Send server start message to the server.
      var command = IsolatedHttpServerCommand.start();
      port.send([command, _statusPort.sendPort]);
    });

    // Handle status messages from the server.
    _statusPort.listen((var status) {
      if (status.isStarted) {
        _startedCallback(status.port);
      }
    });
  }

  void shutdown() {
    // Send server stop message to the server.
    _serverPort.send([IsolatedHttpServerCommand.stop(), _statusPort.sendPort]);
    _statusPort.close();
  }

  final ReceivePort _statusPort; // Port for receiving messages from the server.
  SendPort _serverPort; // Port for sending messages to the server.
  void Function(int) _startedCallback;
}

class IsolatedHttpServerCommand {
  static const START = 0;
  static const STOP = 1;
  static const CHUNKED_ENCODING = 2;

  IsolatedHttpServerCommand.start() : _command = START;
  IsolatedHttpServerCommand.stop() : _command = STOP;
  IsolatedHttpServerCommand.chunkedEncoding() : _command = CHUNKED_ENCODING;

  bool get isStart => _command == START;
  bool get isStop => _command == STOP;
  bool get isChunkedEncoding => _command == CHUNKED_ENCODING;

  final int _command;
}

class IsolatedHttpServerStatus {
  static const STARTED = 0;
  static const STOPPED = 1;
  static const ERROR = 2;

  IsolatedHttpServerStatus.started(this.port) : _state = STARTED;

  IsolatedHttpServerStatus.stopped()
      : port = null,
        _state = STOPPED;

  IsolatedHttpServerStatus.error()
      : port = null,
        _state = ERROR;

  bool get isStarted => _state == STARTED;
  bool get isStopped => _state == STOPPED;
  bool get isError => _state == ERROR;

  final int _state;
  final int port;
}

void startIsolatedHttpServer(Object replyToObj) {
  SendPort replyTo = replyToObj;
  var server = TestServer();
  server.init();
  replyTo.send(server.dispatchSendPort);
}

class TestServer {
  // Echo the request content back to the response.
  void _echoHandler(HttpRequest request) {
    var response = request.response;
    if (request.method != 'POST') {
      response.addError('POST expected, got: ${request.method}');
    }
    response.contentLength = request.contentLength;
    request.pipe(response);
  }

  // Return a 404.
  void _notFoundHandler(HttpRequest request) {
    var response = request.response;
    response.statusCode = HttpStatus.NOT_FOUND;
    response.headers.set("Content-Type", "text/html; charset=UTF-8");
    response.write("Page not found");
    response.close();
  }

  void init() {
    // Setup request handlers.
    _requestHandlers = Map();
    _requestHandlers["/echo"] = _echoHandler;
    _dispatchPort = ReceivePort();
    _dispatchPort.listen(dispatch);
  }

  SendPort get dispatchSendPort => _dispatchPort.sendPort;

  void dispatch(message) {
    IsolatedHttpServerCommand command = message[0];
    SendPort replyTo = message[1];
    if (command.isStart) {
      try {
        HttpServer.bind("127.0.0.1", 0).then((server) {
          _server = server;
          _server.listen(_requestReceivedHandler);
          replyTo.send(IsolatedHttpServerStatus.started(_server.port));
        });
      } catch (e) {
        replyTo.send(IsolatedHttpServerStatus.error());
      }
    } else if (command.isStop) {
      _server.close();
      _dispatchPort.close();
      replyTo.send(IsolatedHttpServerStatus.stopped());
    }
  }

  void _requestReceivedHandler(HttpRequest request) {
    var requestHandler = _requestHandlers[request.uri.path];
    if (requestHandler != null) {
      requestHandler(request);
    } else {
      _notFoundHandler(request);
    }
  }

  HttpServer _server; // HTTP server instance.
  ReceivePort _dispatchPort;
  Map _requestHandlers;
}

Future<Null> testRead(bool chunkedEncoding) {
  final completer = Completer<Null>();
  String data = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
  final int kMessageCount = 10;

  IsolatedHttpServer server = IsolatedHttpServer();

  void runTest(int port) {
    int count = 0;
    HttpClient httpClient = HttpClient();
    void sendRequest() {
      httpClient.post("127.0.0.1", port, "/echo").then((request) {
        if (chunkedEncoding) {
          request.write(data.substring(0, 10));
          request.write(data.substring(10, data.length));
        } else {
          request.contentLength = data.length;
          request.add(data.codeUnits);
        }
        return request.close();
      }).then((response) {
        expect(HttpStatus.OK, equals(response.statusCode));
        List<int> body = List<int>();
        response.listen(body.addAll, onDone: () {
          expect(data, equals(String.fromCharCodes(body)));
          count++;
          if (count < kMessageCount) {
            sendRequest();
          } else {
            httpClient.close();
            server.shutdown();
            completer.complete();
          }
        });
      });
    }

    sendRequest();
  }

  server.setServerStartedHandler(runTest);
  server.start(chunkedEncoding);
  return completer.future;
}

void main() {
  test('readChunked', () => testRead(true));
  test('readNotChunked', () => testRead(false));
}
