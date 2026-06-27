import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'audio_player.dart';

const kTextToSpeechMaxInputCharacters = 4000;

class TextToSpeechInput {
  final String text;
  final String voice;

  const TextToSpeechInput({required this.text, required this.voice});
}

abstract interface class TextToSpeechEngine {
  Future<List<int>> synthesize(TextToSpeechInput input);
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

class TextToSpeechService {
  final TextToSpeechEngine engine;
  final AudioPlayerPlatform player;
  final Future<Directory> Function() outputDirectory;
  final DateTime Function() now;

  const TextToSpeechService({
    required this.engine,
    required this.player,
    this.outputDirectory = getTemporaryDirectory,
    this.now = DateTime.now,
  });

  Stream<AudioPlaybackEvent> get playbackEvents => player.events;

  Future<TextToSpeechResult> speak({
    required String text,
    required String voice,
  }) async {
    final normalizedText = normalizeTextToSpeechInput(text);
    final normalizedVoice = normalizeTextToSpeechVoice(voice);
    final bytes = await engine.synthesize(
      TextToSpeechInput(text: normalizedText, voice: normalizedVoice),
    );
    if (bytes.isEmpty) {
      throw const TextToSpeechException('语音播报生成失败，请稍后重试');
    }
    final directory = Directory(
      p.join((await outputDirectory()).path, 'tts_audio'),
    );
    await directory.create(recursive: true);
    final file = File(
      p.join(
        directory.path,
        'simichat-tts-${now().millisecondsSinceEpoch}.mp3',
      ),
    );
    await file.writeAsBytes(bytes, flush: true);
    await player.playFile(file.path);
    return TextToSpeechResult(audioFile: file, fileSize: bytes.length);
  }

  Future<void> stop() => player.stop();
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
  if (!RegExp(r'^[a-zA-Z0-9._-]{1,64}$').hasMatch(value)) {
    throw const TextToSpeechException('TTS 音色格式无效');
  }
  return value;
}
