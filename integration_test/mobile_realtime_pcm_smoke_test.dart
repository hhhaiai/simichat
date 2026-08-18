import 'dart:async';
import 'dart:math' as math;

import 'package:ai_chat_app/core/media/realtime_pcm_audio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android native realtime PCM capture and playback smoke', (
    tester,
  ) async {
    final pcm = MethodChannelRealtimePcmAudio();
    final chunks = <Uint8List>[];
    final firstNonEmptyChunk = Completer<Uint8List>();
    final subscription = pcm.inputPcm.listen(
      (chunk) {
        chunks.add(chunk);
        if (chunk.isNotEmpty && !firstNonEmptyChunk.isCompleted) {
          firstNonEmptyChunk.complete(chunk);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!firstNonEmptyChunk.isCompleted) {
          firstNonEmptyChunk.completeError(error, stackTrace);
        }
      },
    );
    addTearDown(() async {
      await subscription.cancel();
    });

    debugPrint(
      'SIMICHAT_REALTIME_PCM_SMOKE_START '
      'inputSampleRate=16000 outputSampleRate=24000 channels=1 bitsPerSample=16',
    );

    final playbackPayload = _buildPcm16Tone(
      sampleRate: 24000,
      duration: const Duration(milliseconds: 100),
    );
    var playbackStarted = false;
    try {
      await pcm.startPlayback();
      playbackStarted = true;
      await pcm.writePlayback(playbackPayload);
      debugPrint(
        'SIMICHAT_REALTIME_PCM_PLAYBACK_EVIDENCE '
        'sampleRate=24000 bytes=${playbackPayload.length} '
        'nonZeroBytes=${playbackPayload.where((value) => value != 0).length}',
      );
    } finally {
      if (playbackStarted) {
        await pcm.stopPlayback();
      }
    }

    var captureStarted = false;
    try {
      await pcm.startCapture();
      captureStarted = true;
      await firstNonEmptyChunk.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () => throw StateError(
          'AudioRecord did not emit a non-empty PCM16 chunk within 3 seconds',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 250));
    } finally {
      if (captureStarted) {
        await pcm.stopCapture();
      }
    }

    final nonEmptyChunks = chunks.where((chunk) => chunk.isNotEmpty).toList();
    final capturedBytes = nonEmptyChunks.fold<int>(
      0,
      (total, chunk) => total + chunk.length,
    );
    final largestChunk = nonEmptyChunks.fold<int>(
      0,
      (largest, chunk) => math.max(largest, chunk.length),
    );
    debugPrint(
      'SIMICHAT_REALTIME_PCM_CAPTURE_EVIDENCE '
      'sampleRate=16000 chunks=${chunks.length} '
      'nonEmptyChunks=${nonEmptyChunks.length} bytes=$capturedBytes '
      'largestChunk=$largestChunk',
    );

    expect(nonEmptyChunks, isNotEmpty);
    expect(capturedBytes, greaterThan(0));
    expect(nonEmptyChunks.every((chunk) => chunk.length.isEven), isTrue);
    expect(tester.takeException(), isNull);
    debugPrint(
      'SIMICHAT_REALTIME_PCM_SMOKE_PASS '
      'playbackBytes=${playbackPayload.length} captureBytes=$capturedBytes',
    );
  });
}

Uint8List _buildPcm16Tone({
  required int sampleRate,
  required Duration duration,
}) {
  final sampleCount = sampleRate * duration.inMicroseconds ~/ 1000000;
  final bytes = Uint8List(sampleCount * 2);
  for (var index = 0; index < sampleCount; index++) {
    final sample = (math.sin(2 * math.pi * 440 * index / sampleRate) * 2000)
        .round();
    bytes[index * 2] = sample & 0xff;
    bytes[index * 2 + 1] = (sample >> 8) & 0xff;
  }
  return bytes;
}
