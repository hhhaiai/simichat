import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ai_chat_app/core/media/audio_player.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('mobile device replaces active native audio playback', (
    tester,
  ) async {
    final tempRoot = await getTemporaryDirectory();
    final audioDir = Directory('${tempRoot.path}/audio_playback_replace_smoke')
      ..createSync(recursive: true);
    final firstAudio = File('${audioDir.path}/simichat-replace-first.wav');
    final secondAudio = File('${audioDir.path}/simichat-replace-second.wav');
    await firstAudio.writeAsBytes(
      _buildSineWaveWav(durationMs: 6500, frequency: 330),
      flush: true,
    );
    await secondAudio.writeAsBytes(
      _buildSineWaveWav(durationMs: 900, frequency: 660),
      flush: true,
    );

    final player = const MethodChannelAudioPlayer();
    addTearDown(() async {
      try {
        await player.stop();
      } catch (_) {
        // Best-effort cleanup only; assertions below cover playback errors.
      }
      if (await audioDir.exists()) await audioDir.delete(recursive: true);
    });

    final events = <AudioPlaybackEvent>[];
    final subscription = player.events.listen(events.add);
    addTearDown(subscription.cancel);

    await player.playFile(firstAudio.path);
    await tester.pump(const Duration(milliseconds: 350));
    await player.playFile(secondAudio.path);

    await _pumpUntil(
      tester,
      () async =>
          events.any((event) => _isStoppedFor(event, firstAudio)) &&
          events.any((event) => _isCompletedFor(event, secondAudio)),
    );

    final firstStoppedIndex = events.indexWhere(
      (event) => _isStoppedFor(event, firstAudio),
    );
    final secondCompletedIndex = events.indexWhere(
      (event) => _isCompletedFor(event, secondAudio),
    );
    expect(firstStoppedIndex, isNonNegative);
    expect(secondCompletedIndex, isNonNegative);
    expect(firstStoppedIndex, lessThan(secondCompletedIndex));
    expect(
      events.where((event) => _isCompletedFor(event, firstAudio)),
      isEmpty,
    );
    expect(
      events.where((event) => event.type == AudioPlaybackEventType.error),
      isEmpty,
    );
    expect(await firstAudio.exists(), isTrue);
    expect(await secondAudio.exists(), isTrue);
    expect(await firstAudio.length(), greaterThan(44));
    expect(await secondAudio.length(), greaterThan(44));
    expect(tester.takeException(), isNull);
  });
}

bool _isStoppedFor(AudioPlaybackEvent event, File file) =>
    event.type == AudioPlaybackEventType.stopped &&
    (event.path?.endsWith(file.uri.pathSegments.last) ?? false);

bool _isCompletedFor(AudioPlaybackEvent event, File file) =>
    event.type == AudioPlaybackEventType.completed &&
    (event.path?.endsWith(file.uri.pathSegments.last) ?? false);

List<int> _buildSineWaveWav({
  int sampleRate = 24000,
  required int durationMs,
  required double frequency,
}) {
  const channels = 1;
  const bitsPerSample = 16;
  final sampleCount = (sampleRate * durationMs / 1000).round();
  final dataSize = sampleCount * channels * bitsPerSample ~/ 8;
  final fileSize = 36 + dataSize;
  final bytes = Uint8List(44 + dataSize);
  final data = ByteData.sublistView(bytes);

  void writeAscii(int offset, String value) {
    for (var i = 0; i < value.length; i++) {
      bytes[offset + i] = value.codeUnitAt(i);
    }
  }

  writeAscii(0, 'RIFF');
  data.setUint32(4, fileSize, Endian.little);
  writeAscii(8, 'WAVE');
  writeAscii(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, channels, Endian.little);
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, sampleRate * channels * bitsPerSample ~/ 8, Endian.little);
  data.setUint16(32, channels * bitsPerSample ~/ 8, Endian.little);
  data.setUint16(34, bitsPerSample, Endian.little);
  writeAscii(36, 'data');
  data.setUint32(40, dataSize, Endian.little);

  for (var i = 0; i < sampleCount; i++) {
    final sample = (math.sin(2 * math.pi * frequency * i / sampleRate) * 12000)
        .round();
    data.setInt16(44 + i * 2, sample, Endian.little);
  }
  return bytes;
}

Future<void> _pumpUntil(
  WidgetTester tester,
  Future<bool> Function() condition, {
  Duration timeout = const Duration(seconds: 8),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (await condition()) return;
  }
  fail('Timed out waiting for condition');
}
