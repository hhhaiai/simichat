import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

void configureDioTransport(Dio dio) {
  final adapter = dio.httpClientAdapter;
  if (adapter is! IOHttpClientAdapter) return;

  adapter.createHttpClient = () {
    final client = HttpClient();
    client.badCertificateCallback =
        (X509Certificate cert, String host, int port) {
          return true;
        };
    return client;
  };
}
