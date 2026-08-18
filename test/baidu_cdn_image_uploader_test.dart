import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_chat_app/core/media/baidu_cdn_image_uploader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uploader posts pic_edit payload and returns data url', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    String? receivedBody;
    unawaited(
      server.forEach((request) async {
        receivedBody = await utf8.decodeStream(request);
        request.response
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'data': {'url': 'https://cdn.example.com/img/1.png'},
            }),
          );
        await request.response.close();
      }),
    );

    final temp = Directory.systemTemp.createTempSync('baidu-upload-');
    addTearDown(() => temp.deleteSync(recursive: true));
    final file = File('${temp.path}/a.png')..writeAsBytesSync([1, 2, 3]);

    final url = await BaiduCdnImageUploader(
      endpoint: Uri.parse('http://${server.address.host}:${server.port}/up'),
    ).uploadFile(file.path);

    expect(url, 'https://cdn.example.com/img/1.png');
    final decoded = Uri.splitQueryString(receivedBody!);
    expect(decoded['scene'], 'pic_edit');
    expect(decoded['picInfo'], startsWith('data:image/png;base64,'));
    expect(decoded['timestamp'], isNotEmpty);
    expect(decoded['token'], hasLength(5));
  });

  test('uploader rejects empty files without a request', () async {
    final temp = Directory.systemTemp.createTempSync('baidu-empty-');
    addTearDown(() => temp.deleteSync(recursive: true));
    final file = File('${temp.path}/a.png')..writeAsBytesSync([]);

    await expectLater(
      BaiduCdnImageUploader(
        endpoint: Uri.parse('http://127.0.0.1:1/up'),
      ).uploadFile(file.path),
      throwsA(
        isA<BaiduCdnUploadException>().having(
          (e) => e.message,
          'message',
          contains('为空'),
        ),
      ),
    );
  });

  test('uploader retries transient failures then succeeds', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    var attempts = 0;
    unawaited(
      server.forEach((request) async {
        attempts++;
        await request.drain<void>();
        request.response
          ..headers.contentType = ContentType.json
          ..write(
            attempts == 1
                ? jsonEncode({'data': {}})
                : jsonEncode({
                    'data': {'url': 'https://cdn.example.com/img/2.png'},
                  }),
          );
        await request.response.close();
      }),
    );

    final temp = Directory.systemTemp.createTempSync('baidu-retry-');
    addTearDown(() => temp.deleteSync(recursive: true));
    final file = File('${temp.path}/a.png')..writeAsBytesSync([1, 2, 3]);

    final url = await BaiduCdnImageUploader(
      endpoint: Uri.parse('http://${server.address.host}:${server.port}/up'),
    ).uploadFile(file.path);

    expect(url, 'https://cdn.example.com/img/2.png');
    expect(attempts, 2);
  });
}
