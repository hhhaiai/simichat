import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:ai_chat_app/core/media/realtime_pcm_audio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _methodChannelName = 'simichat/realtime_pcm_audio';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('iOS realtime PCM native capture/playback smoke', (tester) async {
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      debugPrint(
        'SIMICHAT_IOS_REALTIME_PCM_SMOKE_SKIPPED '
        'reason=ios_device_required platform=$defaultTargetPlatform',
      );
      return;
    }

    final pcm = MethodChannelRealtimePcmAudio();
    const methodChannel = MethodChannel(_methodChannelName);
    final chunks = <Uint8List>[];
    final eventErrors = <String>[];
    final firstNonEmptyChunk = Completer<Uint8List>();
    final subscription = pcm.inputPcm.listen(
      (chunk) {
        chunks.add(chunk);
        if (chunk.isNotEmpty && !firstNonEmptyChunk.isCompleted) {
          firstNonEmptyChunk.complete(chunk);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        final code = error is PlatformException
            ? error.code
            : error.runtimeType.toString();
        eventErrors.add(code);
        if (!firstNonEmptyChunk.isCompleted) {
          firstNonEmptyChunk.completeError(error, stackTrace);
        }
      },
      cancelOnError: false,
    );
    addTearDown(subscription.cancel);

    debugPrint(
      'SIMICHAT_IOS_REALTIME_PCM_SMOKE_START '
      'inputSampleRate=16000 outputSampleRate=24000 '
      'channels=1 bitsPerSample=16 audioFiles=none',
    );

    final playbackPayload = _buildPcm16Tone(
      sampleRate: kRealtimePcmOutputSampleRate,
      duration: const Duration(milliseconds: 120),
    );
    var playbackStarted = false;
    var captureStarted = false;
    try {
      await pcm.startPlayback(
        sampleRate: kRealtimePcmOutputSampleRate,
        channels: kRealtimePcmChannels,
        bitsPerSample: kRealtimePcmBitsPerSample,
      );
      playbackStarted = true;
      await pcm.writePlayback(playbackPayload);
      final playbackDiagnostics = await _diagnostics(methodChannel);
      expect(playbackDiagnostics['playbackActive'], isTrue);
      expect(playbackDiagnostics['outputSampleRate'], 24000);
      expect(playbackDiagnostics['outputChannels'], 1);
      expect(playbackDiagnostics['outputBitsPerSample'], 16);
      expect(playbackDiagnostics['protocolOutputSampleRate'], 24000);
      expect(playbackDiagnostics['channels'], 1);
      expect(playbackDiagnostics['bitsPerSample'], 16);
      expect(playbackDiagnostics['writesAudioFiles'], isFalse);
      debugPrint(
        'SIMICHAT_IOS_REALTIME_PCM_PLAYBACK_EVIDENCE '
        'sampleRate=24000 channels=1 bitsPerSample=16 '
        'bytes=${playbackPayload.length}',
      );

      await pcm.startCapture(
        sampleRate: kRealtimePcmInputSampleRate,
        channels: kRealtimePcmChannels,
        bitsPerSample: kRealtimePcmBitsPerSample,
      );
      captureStarted = true;
      final captureDiagnostics = await _diagnostics(methodChannel);
      expect(captureDiagnostics['captureActive'], isTrue);
      expect(captureDiagnostics['inputTargetSampleRate'], 16000);
      expect(captureDiagnostics['inputTargetChannels'], 1);
      expect(captureDiagnostics['inputTargetBitsPerSample'], 16);
      expect(captureDiagnostics['protocolInputSampleRate'], 16000);
      expect(captureDiagnostics['inputSourceSampleRate'], greaterThan(0));
      expect(captureDiagnostics['inputSourceChannels'], greaterThan(0));

      try {
        await firstNonEmptyChunk.future.timeout(const Duration(seconds: 5));
      } on PlatformException catch (error) {
        throw TestFailure(
          'iOS microphone capture failed (${error.code}): ${error.message}. '
          'Grant microphone permission to the isolated smoke app and rerun.',
        );
      } on TimeoutException {
        throw TestFailure(
          'iOS microphone did not emit PCM16 data within 5 seconds; '
          'chunks=${chunks.length} eventErrors=$eventErrors',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    } on RealtimePcmAudioException catch (error) {
      if (error.code == 'PERMISSION_DENIED' ||
          error.kind == RealtimePcmAudioErrorKind.permission) {
        throw TestFailure(
          'iOS microphone permission denied. Grant permission to the isolated '
          'smoke app and rerun.',
        );
      }
      rethrow;
    } finally {
      if (captureStarted) {
        await pcm.stopCapture();
      }
      if (playbackStarted) {
        await pcm.stopPlayback();
      }
    }

    final nonEmptyChunks = chunks.where((chunk) => chunk.isNotEmpty).toList();
    final capturedBytes = nonEmptyChunks.fold<int>(
      0,
      (total, chunk) => total + chunk.length,
    );
    expect(nonEmptyChunks, isNotEmpty);
    expect(capturedBytes, greaterThan(0));
    expect(nonEmptyChunks.every((chunk) => chunk.length.isEven), isTrue);
    final stoppedDiagnostics = await _diagnostics(methodChannel);
    expect(stoppedDiagnostics['captureActive'], isFalse);
    expect(stoppedDiagnostics['playbackActive'], isFalse);
    expect(stoppedDiagnostics['audioEngineRunning'], isFalse);
    expect(stoppedDiagnostics['audioSessionActive'], isFalse);
    expect(stoppedDiagnostics['writesAudioFiles'], isFalse);
    debugPrint(
      'SIMICHAT_IOS_REALTIME_PCM_CAPTURE_EVIDENCE '
      'sampleRate=16000 channels=1 bitsPerSample=16 '
      'chunks=${nonEmptyChunks.length} bytes=$capturedBytes',
    );
    debugPrint(
      'SIMICHAT_IOS_REALTIME_PCM_STOP_CLEANUP_EVIDENCE '
      'captureActive=${stoppedDiagnostics['captureActive']} '
      'playbackActive=${stoppedDiagnostics['playbackActive']} '
      'audioEngineRunning=${stoppedDiagnostics['audioEngineRunning']} '
      'audioSessionActive=${stoppedDiagnostics['audioSessionActive']} '
      'audioFiles=${stoppedDiagnostics['writesAudioFiles']}',
    );

    if (kReleaseMode) {
      debugPrint(
        'SIMICHAT_IOS_REALTIME_PCM_NOTIFICATION_EVIDENCE '
        'mode=release physicalInterruption=manual physicalRouteChange=manual',
      );
    } else {
      await _exerciseDebugInterruption(
        pcm: pcm,
        methodChannel: methodChannel,
        eventErrors: eventErrors,
      );
      await _exerciseDebugRouteChange(
        pcm: pcm,
        methodChannel: methodChannel,
        eventErrors: eventErrors,
      );
      debugPrint(
        'SIMICHAT_IOS_REALTIME_PCM_NOTIFICATION_EVIDENCE '
        'mode=debug interruption=synthetic routeChange=synthetic',
      );
    }

    expect(tester.takeException(), isNull);
    debugPrint(
      'SIMICHAT_IOS_REALTIME_PCM_SMOKE_PASS '
      'playbackBytes=${playbackPayload.length} captureBytes=$capturedBytes '
      'notificationErrors=$eventErrors',
    );
  });
}

Future<Map<String, dynamic>> _diagnostics(MethodChannel channel) async {
  final value = await channel.invokeMapMethod<String, dynamic>(
    'getDiagnostics',
  );
  if (value == null) {
    throw TestFailure('iOS realtime PCM diagnostics returned null');
  }
  debugPrint('SIMICHAT_IOS_REALTIME_PCM_DIAGNOSTICS ${jsonEncode(value)}');
  return value;
}

Future<void> _exerciseDebugInterruption({
  required MethodChannelRealtimePcmAudio pcm,
  required MethodChannel methodChannel,
  required List<String> eventErrors,
}) async {
  var playbackStarted = false;
  var captureStarted = false;
  try {
    await pcm.startPlayback();
    playbackStarted = true;
    await pcm.startCapture();
    captureStarted = true;
    await methodChannel.invokeMethod<bool>('debugSimulateInterruption');
    await _waitForEventError(eventErrors, 'AUDIO_SESSION_INTERRUPTED');
    final diagnostics = await _diagnostics(methodChannel);
    expect(diagnostics['captureActive'], isFalse);
    expect(diagnostics['playbackActive'], isFalse);
    expect(diagnostics['lastExternalStopCode'], 'AUDIO_SESSION_INTERRUPTED');
    debugPrint(
      'SIMICHAT_IOS_REALTIME_PCM_INTERRUPTION_EVIDENCE '
      'code=${diagnostics['lastExternalStopCode']} stopped=true',
    );
  } finally {
    if (captureStarted) await pcm.stopCapture();
    if (playbackStarted) await pcm.stopPlayback();
  }
}

Future<void> _exerciseDebugRouteChange({
  required MethodChannelRealtimePcmAudio pcm,
  required MethodChannel methodChannel,
  required List<String> eventErrors,
}) async {
  var playbackStarted = false;
  try {
    await pcm.startPlayback();
    playbackStarted = true;
    await methodChannel.invokeMethod<bool>('debugSimulateRouteUnavailable');
    await _waitForEventError(eventErrors, 'AUDIO_ROUTE_CHANGED');
    final diagnostics = await _diagnostics(methodChannel);
    expect(diagnostics['captureActive'], isFalse);
    expect(diagnostics['playbackActive'], isFalse);
    expect(diagnostics['lastExternalStopCode'], 'AUDIO_ROUTE_CHANGED');
    debugPrint(
      'SIMICHAT_IOS_REALTIME_PCM_ROUTE_CHANGE_EVIDENCE '
      'code=${diagnostics['lastExternalStopCode']} stopped=true',
    );
  } finally {
    if (playbackStarted) await pcm.stopPlayback();
  }
}

Future<void> _waitForEventError(List<String> errors, String expected) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (DateTime.now().isBefore(deadline)) {
    if (errors.contains(expected)) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  throw TestFailure(
    'Expected iOS realtime PCM event error $expected; got $errors',
  );
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
