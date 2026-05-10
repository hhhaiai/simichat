import 'package:dio/dio.dart';

import 'http_client_adapter_factory_stub.dart'
    if (dart.library.io) 'http_client_adapter_factory_io.dart' as impl;

void configureDioTransport(Dio dio) {
  impl.configureDioTransport(dio);
}
