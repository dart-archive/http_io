// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:http_io/http_io.dart';
import 'package:test/test.dart';

expectProxy(expected, String uri, environment) {
  expect(
      expected,
      equals(HttpClient.findProxyFromEnvironment(Uri.parse(uri),
          environment: environment)));
}

expectDirect(String uri, Map<String, String> environment) {
  expect(
      "DIRECT",
      equals(HttpClient.findProxyFromEnvironment(Uri.parse(uri),
          environment: environment)));
}

main() {
  test('http_proxy_configuration', () {
    expectDirect("http://www.google.com", {});
    expectDirect("http://www.google.com", {"http_proxy": ""});
    expectDirect("http://www.google.com", {"http_proxy": " "});

    expectProxy("PROXY www.proxy.com:1080", "http://www.google.com",
        {"http_proxy": "www.proxy.com"});
    expectProxy("PROXY www.proxys.com:1080", "https://www.google.com",
        {"https_proxy": "www.proxys.com"});
    expectProxy("PROXY www.proxy.com:8080", "http://www.google.com",
        {"http_proxy": "www.proxy.com:8080"});
    expectProxy("PROXY www.proxys.com:8080", "https://www.google.com",
        {"https_proxy": "www.proxys.com:8080"});
    expectProxy("PROXY www.proxy.com:8080", "http://www.google.com", {
      "http_proxy": "www.proxy.com:8080",
      "https_proxy": "www.proxys.com:8080"
    });
    expectProxy("PROXY www.proxys.com:8080", "https://www.google.com", {
      "http_proxy": "www.proxy.com:8080",
      "https_proxy": "www.proxys.com:8080"
    });

    expectProxy("PROXY [::ffff:1]:1080", "http://www.google.com",
        {"http_proxy": "[::ffff:1]"});
    expectProxy("PROXY [::ffff:2]:1080", "https://www.google.com",
        {"https_proxy": "[::ffff:2]"});
    expectProxy("PROXY [::ffff:1]:8080", "http://www.google.com",
        {"http_proxy": "[::ffff:1]:8080"});
    expectProxy("PROXY [::ffff:2]:8080", "https://www.google.com",
        {"https_proxy": "[::ffff:2]:8080"});
    expectProxy("PROXY [::ffff:1]:8080", "http://www.google.com",
        {"http_proxy": "[::ffff:1]:8080", "https_proxy": "[::ffff:2]:8080"});
    expectProxy("PROXY [::ffff:2]:8080", "https://www.google.com",
        {"http_proxy": "[::ffff:1]:8080", "https_proxy": "[::ffff:2]:8080"});

    expectProxy("PROXY www.proxy.com:1080", "http://www.google.com",
        {"http_proxy": "http://www.proxy.com"});
    expectProxy("PROXY www.proxy.com:1080", "http://www.google.com",
        {"http_proxy": "http://www.proxy.com/"});
    expectProxy("PROXY www.proxy.com:8080", "http://www.google.com",
        {"http_proxy": "http://www.proxy.com:8080/"});
    expectProxy("PROXY www.proxy.com:8080", "http://www.google.com",
        {"http_proxy": "http://www.proxy.com:8080/index.html"});
    expectProxy("PROXY www.proxy.com:8080", "http://www.google.com", {
      "http_proxy": "http://www.proxy.com:8080/",
      "https_proxy": "http://www.proxys.com:8080/"
    });
    expectProxy("PROXY www.proxys.com:8080", "https://www.google.com", {
      "http_proxy": "http://www.proxy.com:8080/",
      "https_proxy": "http://www.proxys.com:8080/"
    });
    expectProxy("PROXY www.proxy.com:8080", "http://www.google.com", {
      "http_proxy": "http://www.proxy.com:8080/",
      "https_proxy": "http://www.proxys.com:8080/index.html"
    });
    expectProxy("PROXY www.proxys.com:8080", "https://www.google.com", {
      "http_proxy": "http://www.proxy.com:8080/",
      "https_proxy": "http://www.proxys.com:8080/index.html"
    });

    expectProxy("PROXY [::ffff:1]:1080", "http://www.google.com",
        {"http_proxy": "http://[::ffff:1]"});
    expectProxy("PROXY [::ffff:1]:1080", "http://www.google.com",
        {"http_proxy": "http://[::ffff:1]/"});
    expectProxy("PROXY [::ffff:1]:8080", "http://www.google.com",
        {"http_proxy": "http://[::ffff:1]:8080/"});
    expectProxy("PROXY [::ffff:1]:8080", "http://www.google.com",
        {"http_proxy": "http://[::ffff:1]:8080/index.html"});
    expectProxy("PROXY [::ffff:1]:8080", "http://www.google.com", {
      "http_proxy": "http://[::ffff:1]:8080/",
      "https_proxy": "http://[::ffff:1]:8080/"
    });
    expectProxy("PROXY [::ffff:2]:8080", "https://www.google.com", {
      "http_proxy": "http://[::ffff:1]:8080/",
      "https_proxy": "http://[::ffff:2]:8080/"
    });
    expectProxy("PROXY [::ffff:1]:8080", "http://www.google.com", {
      "http_proxy": "http://[::ffff:1]:8080/",
      "https_proxy": "http://[::ffff:1]:8080/index.html"
    });
    expectProxy("PROXY [::ffff:2]:8080", "https://www.google.com", {
      "http_proxy": "http://[::ffff:1]:8080/",
      "https_proxy": "http://[::ffff:2]:8080/index.html"
    });

    expectDirect("http://www.google.com",
        {"http_proxy": "www.proxy.com:8080", "no_proxy": "www.google.com"});
    expectDirect("http://www.google.com",
        {"http_proxy": "www.proxy.com:8080", "no_proxy": "google.com"});
    expectDirect("http://www.google.com",
        {"http_proxy": "www.proxy.com:8080", "no_proxy": ".com"});
    expectDirect("http://www.google.com", {
      "http_proxy": "www.proxy.com:8080",
      "no_proxy": ",,  , www.google.edu,,.com    "
    });
    expectDirect("http://www.google.edu", {
      "http_proxy": "www.proxy.com:8080",
      "no_proxy": ",,  , www.google.edu,,.com    "
    });
    expectDirect(
        "http://www.google.com", {"https_proxy": "www.proxy.com:8080"});

    expectProxy("PROXY www.proxy.com:8080", "http://[::ffff:1]",
        {"http_proxy": "www.proxy.com:8080", "no_proxy": "["});
    expectProxy("PROXY www.proxy.com:8080", "http://[::ffff:1]",
        {"http_proxy": "www.proxy.com:8080", "no_proxy": "[]"});

    expectDirect("http://[::ffff:1]",
        {"http_proxy": "www.proxy.com:8080", "no_proxy": "[::ffff:1]"});
    expectDirect("http://[::ffff:1]", {
      "http_proxy": "www.proxy.com:8080",
      "no_proxy": ",,  , www.google.edu,,[::ffff:1]    "
    });
  });
}
