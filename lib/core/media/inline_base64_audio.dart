import 'dart:convert';
import 'dart:typed_data';

import 'openai_speech_to_text_engine.dart' show kSpeechToTextMaxAudioBytes;

class InlineBase64AudioPayload {
  const InlineBase64AudioPayload({
    required this.bytes,
    required this.mimeType,
    required this.extension,
  });

  final Uint8List bytes;
  final String mimeType;
  final String extension;

  String get fileName => 'inline-base64-audio.$extension';
}

class InlineBase64AudioExtraction {
  const InlineBase64AudioExtraction({
    required this.cleanedContent,
    required this.audio,
  });

  final String cleanedContent;
  final InlineBase64AudioPayload? audio;
}

class InlineBase64AudioException implements Exception {
  const InlineBase64AudioException(this.message);

  final String message;

  @override
  String toString() => message;
}

InlineBase64AudioExtraction extractInlineBase64Audio(
  String content, {
  int maxBytes = kSpeechToTextMaxAudioBytes,
}) {
  final dataUrlMatch = _audioDataUrlPattern.firstMatch(content);
  if (dataUrlMatch != null) {
    final type = _normalizeAudioMimeType(dataUrlMatch.group(1)!);
    if (type == null) {
      throw const InlineBase64AudioException('暂不支持该 base64 音频格式');
    }
    final bytes = _decodeAudioBase64(dataUrlMatch.group(2)!, maxBytes);
    return InlineBase64AudioExtraction(
      cleanedContent: _cleanMatchedBase64(content, dataUrlMatch),
      audio: InlineBase64AudioPayload(
        bytes: bytes,
        mimeType: type.mimeType,
        extension: type.extension,
      ),
    );
  }

  final markerMatch = _markedAudioBase64Pattern.firstMatch(content);
  if (markerMatch == null) {
    return InlineBase64AudioExtraction(cleanedContent: content, audio: null);
  }

  final bytes = _decodeAudioBase64(markerMatch.group(1)!, maxBytes);
  final type = _inferAudioType(bytes);
  if (type == null) {
    throw const InlineBase64AudioException(
      '无法识别 base64 音频格式，请使用 m4a、mp3、wav、flac、ogg、opus 或 amr。',
    );
  }
  return InlineBase64AudioExtraction(
    cleanedContent: _cleanMatchedBase64(content, markerMatch),
    audio: InlineBase64AudioPayload(
      bytes: bytes,
      mimeType: type.mimeType,
      extension: type.extension,
    ),
  );
}

final _audioDataUrlPattern = RegExp(
  r'data:(audio/[a-z0-9.+-]+);base64,([A-Za-z0-9+/=_\-\s]+)',
  caseSensitive: false,
);

final _markedAudioBase64Pattern = RegExp(
  r'(?:base64\s*(?:的)?\s*(?:语音|音频)?\s*(?:字符|字符串|内容|数据)?|(?:语音|音频)\s*base64|audio\s*base64)\s*[:：]\s*([A-Za-z0-9+/_=\-\s]{16,})',
  caseSensitive: false,
);

String _cleanMatchedBase64(String content, Match match) {
  final cleaned = content.replaceRange(
    match.start,
    match.end,
    ' [已接收 base64 语音，正在转写] ',
  );
  return cleaned
      .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

Uint8List _decodeAudioBase64(String value, int maxBytes) {
  final normalized = _normalizeBase64(value);
  if (normalized == null) {
    throw const InlineBase64AudioException('base64 音频内容格式无效');
  }
  try {
    final bytes = base64Decode(normalized);
    if (bytes.isEmpty) {
      throw const InlineBase64AudioException('base64 音频内容为空');
    }
    if (bytes.length > maxBytes) {
      throw const InlineBase64AudioException('base64 音频内容过大，单条语音不能超过 25 MB');
    }
    return bytes;
  } on InlineBase64AudioException {
    rethrow;
  } catch (_) {
    throw const InlineBase64AudioException('base64 音频内容格式无效');
  }
}

String? _normalizeBase64(String value) {
  final normalized = value
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll('-', '+')
      .replaceAll('_', '/');
  if (normalized.isEmpty ||
      !RegExp(r'^[A-Za-z0-9+/]*={0,2}$').hasMatch(normalized)) {
    return null;
  }
  final firstPadding = normalized.indexOf('=');
  if (firstPadding >= 0 &&
      normalized.substring(firstPadding).replaceAll('=', '').isNotEmpty) {
    return null;
  }
  final remainder = normalized.length % 4;
  if (remainder == 1) return null;
  if (remainder == 2) return '$normalized==';
  if (remainder == 3) return '$normalized=';
  return normalized;
}

_AudioType? _normalizeAudioMimeType(String value) {
  final normalized = value.trim().toLowerCase();
  final type = _audioTypeFromMime(normalized);
  if (type.extension == 'bin') return null;
  return type;
}

_AudioType _audioTypeFromMime(String mimeType) {
  switch (mimeType.toLowerCase()) {
    case 'audio/mpeg':
    case 'audio/mp3':
      return const _AudioType('audio/mpeg', 'mp3');
    case 'audio/mp4':
    case 'audio/m4a':
    case 'audio/x-m4a':
      return const _AudioType('audio/mp4', 'm4a');
    case 'audio/aac':
      return const _AudioType('audio/aac', 'aac');
    case 'audio/wav':
    case 'audio/x-wav':
      return const _AudioType('audio/wav', 'wav');
    case 'audio/flac':
      return const _AudioType('audio/flac', 'flac');
    case 'audio/ogg':
      return const _AudioType('audio/ogg', 'ogg');
    case 'audio/opus':
      return const _AudioType('audio/opus', 'opus');
    case 'audio/amr':
      return const _AudioType('audio/amr', 'amr');
  }
  return _AudioType(mimeType, 'bin');
}

_AudioType? _inferAudioType(Uint8List bytes) {
  if (_startsWithAscii(bytes, 'RIFF') && _hasAsciiAt(bytes, 'WAVE', 8)) {
    return const _AudioType('audio/wav', 'wav');
  }
  if (_startsWithAscii(bytes, 'ID3') ||
      (bytes.length >= 2 && bytes[0] == 0xff && (bytes[1] & 0xe0) == 0xe0)) {
    return const _AudioType('audio/mpeg', 'mp3');
  }
  if (_hasAsciiAt(bytes, 'ftyp', 4)) {
    return const _AudioType('audio/mp4', 'm4a');
  }
  if (_startsWithAscii(bytes, 'fLaC')) {
    return const _AudioType('audio/flac', 'flac');
  }
  if (_startsWithAscii(bytes, 'OggS')) {
    return const _AudioType('audio/ogg', 'ogg');
  }
  if (_startsWithAscii(bytes, '#!AMR')) {
    return const _AudioType('audio/amr', 'amr');
  }
  return null;
}

bool _startsWithAscii(Uint8List bytes, String marker) =>
    _hasAsciiAt(bytes, marker, 0);

bool _hasAsciiAt(Uint8List bytes, String marker, int offset) {
  final units = ascii.encode(marker);
  if (bytes.length < offset + units.length) return false;
  for (var i = 0; i < units.length; i++) {
    if (bytes[offset + i] != units[i]) return false;
  }
  return true;
}

class _AudioType {
  const _AudioType(this.mimeType, this.extension);

  final String mimeType;
  final String extension;
}
