import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart' show CancelToken;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'audio_player.dart';
import '../storage/atomic_file_writer.dart';

const kTextToSpeechMaxInputCharacters = 4000;
const kTextToSpeechAudioFileExtensions = {'mp3', 'wav', 'opus', 'aac', 'flac'};

class TextToSpeechInput {
  final String text;
  final String voice;

  const TextToSpeechInput({required this.text, required this.voice});
}

abstract interface class TextToSpeechEngine {
  Future<List<int>> synthesize(
    TextToSpeechInput input, {
    CancelToken? cancelToken,
  });
}

class TextToSpeechException implements Exception {
  final String message;

  const TextToSpeechException(this.message);

  @override
  String toString() => message;
}

class TextToSpeechResult {
  final File audioFile;
  final int fileSize;

  const TextToSpeechResult({required this.audioFile, required this.fileSize});
}

/// 本地 TTS 合成与播放器生命周期。该状态只描述客户端行为，不证明
/// 远端 provider 生成了特定音色、声音设计或声音克隆结果。
enum TextToSpeechPlaybackState {
  idle,
  synthesizing,
  playing,
  completed,
  stopped,
  error,
}

class TextToSpeechPlaybackSnapshot {
  const TextToSpeechPlaybackSnapshot({
    required this.state,
    this.path,
    this.message,
  });

  const TextToSpeechPlaybackSnapshot.idle()
    : this(state: TextToSpeechPlaybackState.idle);

  final TextToSpeechPlaybackState state;
  final String? path;
  final String? message;
}

class TextToSpeechService {
  final TextToSpeechEngine engine;
  final AudioPlayerPlatform player;
  final Future<Directory> Function() outputDirectory;
  final DateTime Function() now;
  final String audioFileExtension;
  final StreamController<TextToSpeechPlaybackSnapshot>
  _playbackStateController =
      StreamController<TextToSpeechPlaybackSnapshot>.broadcast(sync: true);
  StreamSubscription<AudioPlaybackEvent>? _playbackSubscription;
  TextToSpeechPlaybackSnapshot _playbackSnapshot =
      const TextToSpeechPlaybackSnapshot.idle();
  String? _activePlaybackPath;

  TextToSpeechService({
    required this.engine,
    required this.player,
    this.outputDirectory = getTemporaryDirectory,
    this.now = DateTime.now,
    this.audioFileExtension = 'mp3',
  });

  Stream<AudioPlaybackEvent> get playbackEvents {
    _ensurePlaybackListener();
    return player.events;
  }

  Stream<TextToSpeechPlaybackSnapshot> get playbackStates {
    _ensurePlaybackListener();
    return _playbackStateController.stream;
  }

  /// Alias for callers that use an event-style name for the state stream.
  Stream<TextToSpeechPlaybackSnapshot> get playbackStateEvents =>
      playbackStates;

  TextToSpeechPlaybackSnapshot get playbackSnapshot => _playbackSnapshot;

  TextToSpeechPlaybackState get playbackState => _playbackSnapshot.state;

  Future<TextToSpeechResult> speak({
    required String text,
    required String voice,
    CancelToken? cancelToken,
  }) async {
    _activePlaybackPath = null;
    _setPlaybackState(TextToSpeechPlaybackState.synthesizing);
    File? file;
    try {
      _throwIfCancelled(cancelToken);
      final normalizedText = normalizeTextToSpeechInput(text);
      final normalizedVoice = normalizeTextToSpeechVoice(voice);
      final bytes = await engine.synthesize(
        TextToSpeechInput(text: normalizedText, voice: normalizedVoice),
        cancelToken: cancelToken,
      );
      _throwIfCancelled(cancelToken);
      if (bytes.isEmpty) {
        throw const TextToSpeechException('语音播报生成失败，请稍后重试');
      }
      final extension = normalizeTextToSpeechAudioFileExtension(
        audioFileExtension,
      );
      final directory = Directory(
        p.join((await outputDirectory()).path, 'tts_audio'),
      );
      _throwIfCancelled(cancelToken);
      await directory.create(recursive: true);
      _throwIfCancelled(cancelToken);
      file = File(
        p.join(
          directory.path,
          'simichat-tts-${now().millisecondsSinceEpoch}.$extension',
        ),
      );
      await writeBytesAtomically(file, bytes);
      if (cancelToken?.isCancelled == true) {
        await _stopAndDelete(file);
        throw const TextToSpeechException('TTS 请求已取消');
      }
      _activePlaybackPath = file.path;
      _setPlaybackState(TextToSpeechPlaybackState.playing, path: file.path);
      try {
        await player.playFile(file.path);
      } catch (error) {
        if (cancelToken?.isCancelled == true) {
          await _stopAndDelete(file);
          throw const TextToSpeechException('TTS 请求已取消');
        }
        await _deleteQuietly(file);
        _setPlaybackState(
          TextToSpeechPlaybackState.error,
          path: file.path,
          message: error.toString(),
        );
        rethrow;
      }
      // Cancellation can happen while the platform player is awaiting its
      // start/replace acknowledgement. Do not return success in that race.
      if (cancelToken?.isCancelled == true) {
        await _stopAndDelete(file);
        throw const TextToSpeechException('TTS 请求已取消');
      }
      return TextToSpeechResult(audioFile: file, fileSize: bytes.length);
    } on TextToSpeechException catch (error) {
      if (cancelToken?.isCancelled == true || error.message.contains('取消')) {
        _setPlaybackState(TextToSpeechPlaybackState.stopped, path: file?.path);
      } else {
        _setPlaybackState(
          TextToSpeechPlaybackState.error,
          path: file?.path,
          message: error.message,
        );
      }
      rethrow;
    } catch (error) {
      _setPlaybackState(
        TextToSpeechPlaybackState.error,
        path: file?.path,
        message: error.toString(),
      );
      rethrow;
    }
  }

  Future<void> stop() async {
    final path = _activePlaybackPath;
    try {
      await player.stop();
      _activePlaybackPath = null;
      _setPlaybackState(TextToSpeechPlaybackState.stopped, path: path);
    } catch (error) {
      _setPlaybackState(
        TextToSpeechPlaybackState.error,
        path: path,
        message: error.toString(),
      );
      rethrow;
    }
  }

  void dispose() {
    unawaited(_playbackSubscription?.cancel() ?? Future<void>.value());
    unawaited(_playbackStateController.close());
  }

  void _ensurePlaybackListener() {
    _playbackSubscription ??= player.events.listen(_handlePlaybackEvent);
  }

  void _handlePlaybackEvent(AudioPlaybackEvent event) {
    final activePath = _activePlaybackPath;
    if (activePath == null) return;
    if (event.path != null && event.path != activePath) return;
    switch (event.type) {
      case AudioPlaybackEventType.completed:
        _setPlaybackState(
          TextToSpeechPlaybackState.completed,
          path: event.path ?? activePath,
        );
      case AudioPlaybackEventType.stopped:
        _setPlaybackState(
          TextToSpeechPlaybackState.stopped,
          path: event.path ?? activePath,
        );
      case AudioPlaybackEventType.error:
        _setPlaybackState(
          TextToSpeechPlaybackState.error,
          path: event.path ?? activePath,
          message: event.message,
        );
    }
  }

  void _setPlaybackState(
    TextToSpeechPlaybackState state, {
    String? path,
    String? message,
  }) {
    _playbackSnapshot = TextToSpeechPlaybackSnapshot(
      state: state,
      path: path,
      message: message,
    );
    if (!_playbackStateController.isClosed) {
      _playbackStateController.add(_playbackSnapshot);
    }
  }

  void _throwIfCancelled(CancelToken? cancelToken) {
    if (cancelToken?.isCancelled == true) {
      throw const TextToSpeechException('TTS 请求已取消');
    }
  }

  Future<void> _stopAndDelete(File file) async {
    try {
      await player.stop();
    } catch (_) {}
    await _deleteQuietly(file);
    _activePlaybackPath = null;
  }

  Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}

String normalizeTextToSpeechAudioFileExtension(String extension) {
  final value = extension.trim().toLowerCase();
  if (!kTextToSpeechAudioFileExtensions.contains(value)) {
    throw const TextToSpeechException('不支持的 TTS 音频文件格式');
  }
  return value;
}

String normalizeTextToSpeechInput(String text) {
  final value = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (value.isEmpty) {
    throw const TextToSpeechException('没有可播报的文本');
  }
  if (value.length > kTextToSpeechMaxInputCharacters) {
    return value.substring(0, kTextToSpeechMaxInputCharacters);
  }
  return value;
}

String normalizeTextToSpeechVoice(String voice) {
  final value = voice.trim();
  if (value.isEmpty) {
    throw const TextToSpeechException('TTS 音色不能为空');
  }
  // 声音克隆的 voice 是 base64 data URI（data:audio/...;base64,...）。
  final isDataUri = RegExp(
    r'^data:[a-zA-Z0-9]+/[a-zA-Z0-9.+-]+;base64,[a-zA-Z0-9+/=]+$',
  ).hasMatch(value);
  if (!isDataUri && !RegExp(r'^[a-zA-Z0-9._-]{1,64}$').hasMatch(value)) {
    throw const TextToSpeechException('TTS 音色格式无效');
  }
  return value;
}
