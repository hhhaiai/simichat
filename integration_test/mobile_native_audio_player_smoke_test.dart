import 'dart:io';
import 'dart:typed_data';

import 'package:ai_chat_app/core/media/audio_player.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('mobile device native audio player plays private wav and stops', (
    tester,
  ) async {
    final tempRoot = await getTemporaryDirectory();
    final audioDir = Directory('${tempRoot.path}/native_audio_player_smoke')
      ..createSync(recursive: true);
    final audioFile = File('${audioDir.path}/simichat-native-smoke.wav');
    await audioFile.writeAsBytes(_buildSilentWav(), flush: true);
    addTearDown(() async {
      if (await audioDir.exists()) await audioDir.delete(recursive: true);
    });

    final player = const MethodChannelAudioPlayer();
    final events = <AudioPlaybackEvent>[];
    final subscription = player.events.listen(events.add);
    addTearDown(subscription.cancel);

    await player
        .playFileForTesting(audioFile.path, skipAudioFocusRequest: true)
        .timeout(_stepTimeout, onTimeout: () => fail('playFile timed out'));
    await Future<void>.delayed(const Duration(milliseconds: 250)).timeout(
      _stepTimeout,
      onTimeout: () => fail('delay after play timed out'),
    );
    await player.stop().timeout(
      _stepTimeout,
      onTimeout: () => fail('stop timed out'),
    );
    await _waitUntil(
      () async =>
          events.any((event) => event.type == AudioPlaybackEventType.stopped),
    );

    expect(
      events.where((event) => event.type == AudioPlaybackEventType.stopped),
      isNotEmpty,
    );
    expect(await audioFile.exists(), isTrue);
    expect(await audioFile.length(), greaterThan(44));
    expect(
      events.where((event) => event.type == AudioPlaybackEventType.error),
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });
}

const _stepTimeout = Duration(seconds: 8);

List<int> _buildSilentWav({int sampleRate = 44100, int durationMs = 1800}) {
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

  // Leave the PCM payload zero-filled so device smoke tests verify native
  // playback events without producing an audible tone.
  return bytes;
}

Future<void> _waitUntil(
  Future<bool> Function() condition, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    if (await condition()) return;
  }
  fail('Timed out waiting for condition');
}
