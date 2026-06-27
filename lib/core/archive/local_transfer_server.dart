import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

class LocalDataTransferException implements Exception {
  const LocalDataTransferException(this.message);

  final String message;

  @override
  String toString() => 'LocalDataTransferException: $message';
}

class LocalDataTransferSession {
  LocalDataTransferSession._({
    required HttpServer server,
    required File file,
    required this.token,
    required this.startedAt,
    required Duration ttl,
    required DateTime Function() now,
    required bool singleUse,
  }) : _server = server,
       _file = file,
       _now = now,
       _singleUse = singleUse,
       expiresAt = startedAt.add(ttl) {
    _subscription = _server.listen(_handleRequest, onError: (_) {});
  }

  final HttpServer _server;
  final File _file;
  final DateTime Function() _now;
  final bool _singleUse;
  final Completer<void> _closed = Completer<void>();
  late final StreamSubscription<HttpRequest> _subscription;

  final String token;
  final DateTime startedAt;
  final DateTime expiresAt;

  var _completedDownloads = 0;
  var _isClosed = false;

  int get port => _server.port;
  int get completedDownloads => _completedDownloads;
  bool get isClosed => _isClosed;
  Future<void> get closed => _closed.future;

  Uri downloadUriForHost(String host) {
    return Uri(
      scheme: 'http',
      host: host,
      port: port,
      path: '/download',
      queryParameters: {'token': token},
    );
  }

  Uri get loopbackDownloadUri => downloadUriForHost('127.0.0.1');

  Future<List<Uri>> candidateDownloadUris() async {
    final urls = <Uri>[loopbackDownloadUri];
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          if (address.isLoopback) continue;
          final uri = downloadUriForHost(address.address);
          if (!urls.contains(uri)) urls.add(uri);
        }
      }
    } catch (_) {
      // 平台可能拒绝枚举网卡；保留 loopback 地址，界面再提示同机访问。
    }
    return List.unmodifiable(urls);
  }

  Future<void> close() async {
    if (_isClosed) return _closed.future;
    _isClosed = true;
    await _subscription.cancel();
    await _server.close(force: false);
    if (!_closed.isCompleted) _closed.complete();
  }

  Future<void> _handleRequest(HttpRequest request) async {
    if (_isClosed) {
      await _writeText(request, HttpStatus.serviceUnavailable, '传输已关闭');
      return;
    }
    if (_now().isAfter(expiresAt)) {
      await _writeText(request, HttpStatus.gone, '传输链接已过期');
      _closeSoon();
      return;
    }
    if (request.method != 'GET') {
      request.response.headers.set(HttpHeaders.allowHeader, 'GET');
      await _writeText(request, HttpStatus.methodNotAllowed, '只允许下载请求');
      return;
    }
    if (request.uri.path != '/download') {
      await _writeText(request, HttpStatus.notFound, '未找到资源');
      return;
    }
    if (request.uri.queryParameters['token'] != token) {
      await _writeText(request, HttpStatus.forbidden, '令牌无效');
      return;
    }
    if (_singleUse && _completedDownloads > 0) {
      await _writeText(request, HttpStatus.gone, '一次性链接已使用');
      return;
    }

    try {
      final stat = await _file.stat();
      if (stat.type != FileSystemEntityType.file) {
        await _writeText(request, HttpStatus.notFound, '导出包不存在');
        return;
      }
      final fileName = p.basename(_file.path);
      request.response.statusCode = HttpStatus.ok;
      request.response.headers
        ..contentType = ContentType('application', 'gzip')
        ..set(HttpHeaders.contentLengthHeader, stat.size.toString())
        ..set(
          HttpHeaders.contentDisposition,
          'attachment; filename="$fileName"',
        )
        ..set(HttpHeaders.cacheControlHeader, 'no-store')
        ..set('X-Content-Type-Options', 'nosniff');
      await request.response.addStream(_file.openRead());
      await request.response.close();
      _completedDownloads++;
      if (_singleUse) _closeSoon();
    } catch (_) {
      await _writeText(request, HttpStatus.internalServerError, '下载失败');
    }
  }

  void _closeSoon() {
    Timer(const Duration(seconds: 1), () => unawaited(close()));
  }

  Future<void> _writeText(
    HttpRequest request,
    int statusCode,
    String message,
  ) async {
    request.response.statusCode = statusCode;
    request.response.headers
      ..contentType = ContentType.text
      ..set(HttpHeaders.cacheControlHeader, 'no-store')
      ..set('X-Content-Type-Options', 'nosniff');
    request.response.write(message);
    await request.response.close();
  }
}

class LocalDataTransferServer {
  const LocalDataTransferServer({
    DateTime Function()? now,
    String Function()? tokenGenerator,
  }) : _now = now,
       _tokenGenerator = tokenGenerator;

  final DateTime Function()? _now;
  final String Function()? _tokenGenerator;

  Future<LocalDataTransferSession> startExportTransfer({
    required File exportFile,
    InternetAddress? address,
    int port = 0,
    Duration ttl = const Duration(minutes: 10),
    bool singleUse = true,
  }) async {
    if (ttl <= Duration.zero) {
      throw const LocalDataTransferException('传输有效期必须大于 0');
    }
    if (!isSimiChatExportArchiveName(p.basename(exportFile.path))) {
      throw const LocalDataTransferException('只允许传输 SimiChat 导出包');
    }
    if (!await exportFile.exists()) {
      throw const LocalDataTransferException('导出包不存在');
    }
    final stat = await exportFile.stat();
    if (stat.type != FileSystemEntityType.file) {
      throw const LocalDataTransferException('导出包不是普通文件');
    }

    final server = await HttpServer.bind(
      address ?? InternetAddress.anyIPv4,
      port,
      shared: false,
    );
    return LocalDataTransferSession._(
      server: server,
      file: exportFile.absolute,
      token: (_tokenGenerator ?? _generateTransferToken)(),
      startedAt: (_now ?? DateTime.now)(),
      ttl: ttl,
      now: _now ?? DateTime.now,
      singleUse: singleUse,
    );
  }
}

bool isSimiChatExportArchiveName(String fileName) {
  return fileName.startsWith('simichat-export-') &&
      (fileName.endsWith('.tar.gz') || fileName.endsWith('.tgz'));
}

String _generateTransferToken() {
  final random = Random.secure();
  final bytes = List<int>.generate(32, (_) => random.nextInt(256));
  return base64Url.encode(bytes).replaceAll('=', '');
}
