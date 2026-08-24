import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/media/pasted_text_attachment_service.dart';
import '../widgets/chat_input_bar.dart';

/// 仅用于应用私有 SharedPreferences 的会话草稿索引。
///
/// 大粘贴原文仍只存在 composer_drafts 下的 UTF-8 文件中；这里保存恢复界面所需
/// 的短文本、附件元数据和深度思考开关，不保存原始大粘贴文本、附件 bytes、
/// Base64、模型凭据或本机诊断信息。
const kChatComposerDraftStorageKey = 'chat_composer_drafts_v1';

const _chatComposerDraftFormatVersion = 1;

/// 页面和生命周期回调共享同一个 Store，保证同一进程内的串行写入顺序。
final chatComposerDraftStoreProvider = Provider<ChatComposerDraftStore>(
  (ref) => ChatComposerDraftStore(),
);

/// 把 session-scoped Composer 草稿持久化为一个有界、可迁移的私有索引。
///
/// [save] 和 [remove] 被串行化，避免快速输入、附件回调和生命周期回调出现旧
/// 快照覆盖新快照。持久化不可用时保持内存草稿可继续使用，下一次成功写入会
/// 收敛到最新状态。
class ChatComposerDraftStore {
  ChatComposerDraftStore({
    Future<SharedPreferences> Function()? preferencesLoader,
    DateTime Function()? now,
    this.maxEntries = 50,
  }) : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance,
       _now = now ?? DateTime.now {
    if (maxEntries <= 0) {
      throw ArgumentError.value(maxEntries, 'maxEntries', 'must be positive');
    }
  }

  final Future<SharedPreferences> Function() _preferencesLoader;
  final DateTime Function() _now;
  final int maxEntries;

  final Map<String, _StoredComposerDraft> _entries =
      <String, _StoredComposerDraft>{};
  Future<void>? _loadFuture;
  Future<void> _writeTail = Future<void>.value();
  SharedPreferences? _preferences;

  /// 读取一个会话的最新草稿。无记录、损坏记录或空会话 ID 均返回 null。
  Future<ChatComposerDraft?> read(String sessionId) async {
    final normalizedSessionId = _normalizeSessionId(sessionId);
    if (normalizedSessionId == null) return null;
    await _ensureLoaded();
    await _writeTail;
    return _entries[normalizedSessionId]?.draft;
  }

  /// 保存最新草稿。调用方可不等待此 Future；写入仍按调用顺序串行完成。
  Future<void> save(String sessionId, ChatComposerDraft draft) {
    final normalizedSessionId = _normalizeSessionId(sessionId);
    if (normalizedSessionId == null) return Future<void>.value();
    final snapshot = _copyDraft(draft);
    return _enqueue(() async {
      await _ensureLoaded();
      _entries[normalizedSessionId] = _StoredComposerDraft(
        draft: snapshot,
        updatedAt: _now().toUtc(),
      );
      _trimToLimit();
      await _persist();
    });
  }

  /// 删除一个会话的草稿。当前会话成功发送后使用保存空草稿而非本方法，以保留
  /// 深度思考开关；真正删除会话或用户主动丢弃草稿时可调用此方法。
  Future<void> remove(String sessionId) {
    final normalizedSessionId = _normalizeSessionId(sessionId);
    if (normalizedSessionId == null) return Future<void>.value();
    return _enqueue(() async {
      await _ensureLoaded();
      _entries.remove(normalizedSessionId);
      await _persist();
    });
  }

  /// 等待已经排队的所有写入结束，供生命周期收尾和测试使用。
  Future<void> flush() async {
    await _ensureLoaded();
    await _writeTail;
  }

  Future<void> _enqueue(Future<void> Function() action) {
    final next = _writeTail.then<void>((_) => action());
    // 失败不能让后续草稿写入永久卡在 error Future 上。调用方草稿仍保留在
    // ChatPage 内存缓存中，下一次写入会继续尝试落盘。
    _writeTail = next.catchError((Object _) {});
    return _writeTail;
  }

  Future<void> _ensureLoaded() {
    return _loadFuture ??= _load();
  }

  Future<void> _load() async {
    final preferences = await _preferencesLoader();
    _preferences = preferences;
    final encoded = preferences.getString(kChatComposerDraftStorageKey);
    if (encoded == null || encoded.trim().isEmpty) return;

    try {
      final root = _asStringKeyedMap(jsonDecode(encoded));
      if (root == null ||
          root['version'] != _chatComposerDraftFormatVersion ||
          root['drafts'] is! List) {
        return;
      }
      for (final rawEntry in root['drafts'] as List<dynamic>) {
        final decoded = _decodeStoredDraft(rawEntry);
        if (decoded == null) continue;
        final existing = _entries[decoded.sessionId];
        if (existing == null ||
            existing.updatedAt.isBefore(decoded.updatedAt)) {
          _entries[decoded.sessionId] = decoded.value;
        }
      }
      _trimToLimit();
    } catch (_) {
      // 损坏或旧格式只影响草稿恢复，不阻塞聊天主链路，也不将原始 JSON 回显。
    }
  }

  Future<void> _persist() async {
    final preferences = _preferences ?? await _preferencesLoader();
    _preferences = preferences;
    if (_entries.isEmpty) {
      await preferences.remove(kChatComposerDraftStorageKey);
      return;
    }

    final ordered = _entries.entries.toList()
      ..sort((a, b) => b.value.updatedAt.compareTo(a.value.updatedAt));
    final payload = <String, Object?>{
      'version': _chatComposerDraftFormatVersion,
      'drafts': ordered
          .map(
            (entry) => <String, Object?>{
              'session_id': entry.key,
              'updated_at': entry.value.updatedAt.toIso8601String(),
              'draft': _encodeDraft(entry.value.draft),
            },
          )
          .toList(growable: false),
    };
    await preferences.setString(
      kChatComposerDraftStorageKey,
      jsonEncode(payload),
    );
  }

  void _trimToLimit() {
    if (_entries.length <= maxEntries) return;
    final oldest = _entries.entries.toList()
      ..sort((a, b) => a.value.updatedAt.compareTo(b.value.updatedAt));
    for (final entry in oldest.take(_entries.length - maxEntries)) {
      _entries.remove(entry.key);
    }
  }

  static ChatComposerDraft _copyDraft(ChatComposerDraft draft) {
    return ChatComposerDraft(
      text: draft.text,
      attachments: List<PendingAttachment>.unmodifiable(
        draft.attachments.map(_copyAttachment),
      ),
      deepThink: draft.deepThink,
    );
  }

  static PendingAttachment _copyAttachment(PendingAttachment attachment) {
    final pasted = attachment.pastedText;
    return PendingAttachment(
      id: attachment.id,
      path: attachment.path,
      name: attachment.name,
      type: attachment.type,
      fileSize: attachment.fileSize,
      pastedText: pasted == null
          ? null
          : PastedTextAttachment(
              id: pasted.id,
              conversationId: pasted.conversationId,
              draftId: pasted.draftId,
              localPath: pasted.localPath,
              displayName: pasted.displayName,
              mimeType: pasted.mimeType,
              source: pasted.source,
              characterCount: pasted.characterCount,
              utf8ByteCount: pasted.utf8ByteCount,
              estimatedTokens: pasted.estimatedTokens,
              sha256: pasted.sha256,
              createdAt: pasted.createdAt,
            ),
    );
  }

  static Map<String, Object?> _encodeDraft(ChatComposerDraft draft) {
    return <String, Object?>{
      'text': draft.text,
      'deep_think': draft.deepThink,
      'attachments': draft.attachments
          .map(_encodeAttachment)
          .toList(growable: false),
    };
  }

  static Map<String, Object?> _encodeAttachment(PendingAttachment attachment) {
    final pasted = attachment.pastedText;
    return <String, Object?>{
      if (attachment.id != null && attachment.id!.trim().isNotEmpty)
        'id': attachment.id,
      'path': attachment.path,
      'name': attachment.name,
      'type': attachment.type,
      'file_size': attachment.fileSize,
      if (pasted != null)
        'pasted_text': <String, Object?>{
          'id': pasted.id,
          'conversation_id': pasted.conversationId,
          'draft_id': pasted.draftId,
          'local_path': pasted.localPath,
          'display_name': pasted.displayName,
          'mime_type': pasted.mimeType,
          'source': pasted.source.name,
          'character_count': pasted.characterCount,
          'utf8_byte_count': pasted.utf8ByteCount,
          'estimated_tokens': pasted.estimatedTokens,
          'sha256': pasted.sha256,
          'created_at': pasted.createdAt.toUtc().toIso8601String(),
        },
    };
  }

  _DecodedComposerDraft? _decodeStoredDraft(Object? rawEntry) {
    final entry = _asStringKeyedMap(rawEntry);
    if (entry == null) return null;
    final sessionId = _normalizeSessionId(_readString(entry['session_id']));
    final draftMap = _asStringKeyedMap(entry['draft']);
    if (sessionId == null || draftMap == null) return null;
    final updatedAt =
        DateTime.tryParse(_readString(entry['updated_at']) ?? '')?.toUtc() ??
        _now().toUtc();

    final attachments = <PendingAttachment>[];
    final rawAttachments = draftMap['attachments'];
    if (rawAttachments is List) {
      for (final rawAttachment in rawAttachments) {
        final attachment = _decodeAttachment(rawAttachment);
        if (attachment != null) attachments.add(attachment);
      }
    }

    return _DecodedComposerDraft(
      sessionId: sessionId,
      value: _StoredComposerDraft(
        draft: ChatComposerDraft(
          text: _readString(draftMap['text']) ?? '',
          attachments: List<PendingAttachment>.unmodifiable(attachments),
          deepThink: draftMap['deep_think'] == true,
        ),
        updatedAt: updatedAt,
      ),
    );
  }

  static PendingAttachment? _decodeAttachment(Object? rawAttachment) {
    final attachment = _asStringKeyedMap(rawAttachment);
    if (attachment == null) return null;
    final path = _readRequiredString(attachment['path']);
    final name = _readRequiredString(attachment['name']);
    final type = _readRequiredString(attachment['type']);
    if (path == null || name == null || type == null) return null;

    var pasted = _decodePastedTextAttachment(attachment['pasted_text']);
    if (pasted != null) {
      // PendingAttachment 和 pastedText 必须引用同一个私有文件，避免恢复后
      // 预览和发送分别读取两个路径。
      pasted = pasted.copyWith(localPath: path, displayName: name);
    }
    return PendingAttachment(
      id: _readOptionalString(attachment['id']),
      path: path,
      name: name,
      type: type,
      fileSize: _readNonNegativeInt(attachment['file_size']) ?? 0,
      pastedText: pasted,
    );
  }

  static PastedTextAttachment? _decodePastedTextAttachment(Object? rawPasted) {
    final pasted = _asStringKeyedMap(rawPasted);
    if (pasted == null) return null;
    final id = _readRequiredString(pasted['id']);
    final conversationId = _readRequiredString(pasted['conversation_id']);
    final draftId = _readRequiredString(pasted['draft_id']);
    final localPath = _readRequiredString(pasted['local_path']);
    final displayName = _readRequiredString(pasted['display_name']);
    final mimeType = _readRequiredString(pasted['mime_type']);
    final sourceName = _readRequiredString(pasted['source']);
    final sha256 = _readRequiredString(pasted['sha256']);
    final createdAt = DateTime.tryParse(
      _readString(pasted['created_at']) ?? '',
    )?.toUtc();
    if (id == null ||
        conversationId == null ||
        draftId == null ||
        localPath == null ||
        displayName == null ||
        mimeType == null ||
        sourceName == null ||
        sha256 == null ||
        createdAt == null) {
      return null;
    }

    final source = switch (sourceName) {
      'largePaste' => PastedTextAttachmentSource.largePaste,
      _ => null,
    };
    if (source == null) return null;
    return PastedTextAttachment(
      id: id,
      conversationId: conversationId,
      draftId: draftId,
      localPath: localPath,
      displayName: displayName,
      mimeType: mimeType,
      source: source,
      characterCount: _readNonNegativeInt(pasted['character_count']) ?? 0,
      utf8ByteCount: _readNonNegativeInt(pasted['utf8_byte_count']) ?? 0,
      estimatedTokens: _readNonNegativeInt(pasted['estimated_tokens']) ?? 0,
      sha256: sha256,
      createdAt: createdAt,
    );
  }
}

class _StoredComposerDraft {
  const _StoredComposerDraft({required this.draft, required this.updatedAt});

  final ChatComposerDraft draft;
  final DateTime updatedAt;
}

class _DecodedComposerDraft {
  const _DecodedComposerDraft({required this.sessionId, required this.value});

  final String sessionId;
  final _StoredComposerDraft value;

  DateTime get updatedAt => value.updatedAt;
}

Map<String, dynamic>? _asStringKeyedMap(Object? raw) {
  if (raw is! Map) return null;
  final result = <String, dynamic>{};
  for (final entry in raw.entries) {
    if (entry.key is! String) return null;
    result[entry.key as String] = entry.value;
  }
  return result;
}

String? _normalizeSessionId(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

String? _readString(Object? value) => value is String ? value : null;

String? _readOptionalString(Object? value) {
  final trimmed = _readString(value)?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

String? _readRequiredString(Object? value) => _readOptionalString(value);

int? _readNonNegativeInt(Object? value) {
  final number = switch (value) {
    int() => value,
    num() when value.isFinite && value == value.roundToDouble() =>
      value.toInt(),
    _ => null,
  };
  return number == null || number < 0 ? null : number;
}
