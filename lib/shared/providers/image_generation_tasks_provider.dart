import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/ai/image_generation_task.dart';
import 'database_provider.dart';

const kImageGenerationTaskSnapshotsStorageKey =
    'image_generation_task_snapshots_v1';
const _imageGenerationTaskSnapshotVersion = 1;

typedef ImageGenerationTaskExists =
    Future<bool> Function(ImageGenerationTask task);

/// Credential-free persistence for image placeholders and retry parameters.
///
/// Image generation itself is a synchronous HTTP request and cannot be
/// resumed after the process dies. A task saved as `running` is therefore
/// restored as a failed, explicitly retryable task. The snapshot contains the
/// selected route/profile and app-owned reference paths, but never a Base URL,
/// API key, authorization header, response bytes, or provider error body.
class ImageGenerationTaskSnapshotStore {
  ImageGenerationTaskSnapshotStore({
    Future<SharedPreferences> Function()? preferencesLoader,
    this.maxEntries = 50,
  }) : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance {
    if (maxEntries <= 0) {
      throw ArgumentError.value(maxEntries, 'maxEntries', 'must be positive');
    }
  }

  final Future<SharedPreferences> Function() _preferencesLoader;
  final int maxEntries;
  final Map<String, _StoredImageGenerationTask> _entries = {};
  Future<void>? _loadFuture;
  Future<void> _writeTail = Future<void>.value();
  SharedPreferences? _preferences;

  Future<List<ImageGenerationTask>> readAll() async {
    await _ensureLoaded();
    await _writeTail;
    final ordered = _entries.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return List<ImageGenerationTask>.unmodifiable(
      ordered.map((entry) => _copyTask(entry.task, forRecovery: true)),
    );
  }

  Future<void> upsert(ImageGenerationTask task) => _enqueue(() async {
    await _ensureLoaded();
    _entries[task.messageId] = _StoredImageGenerationTask(
      task: _copyTask(task),
      updatedAt: DateTime.now().toUtc(),
    );
    _trim();
    await _persist();
  });

  Future<void> remove(String messageId) => _enqueue(() async {
    await _ensureLoaded();
    _entries.remove(messageId.trim());
    await _persist();
  });

  Future<void> flush() async {
    await _ensureLoaded();
    await _writeTail;
  }

  Future<void> _ensureLoaded() => _loadFuture ??= _load();

  Future<void> _load() async {
    final preferences = await _preferencesLoader();
    _preferences = preferences;
    final encoded = preferences.getString(
      kImageGenerationTaskSnapshotsStorageKey,
    );
    if (encoded == null || encoded.trim().isEmpty) return;
    try {
      final root = _map(jsonDecode(encoded));
      if (root == null ||
          root['version'] != _imageGenerationTaskSnapshotVersion ||
          root['tasks'] is! List) {
        return;
      }
      for (final raw in root['tasks'] as List<dynamic>) {
        final stored = _decode(raw);
        if (stored == null) continue;
        final current = _entries[stored.task.messageId];
        if (current == null || current.updatedAt.isBefore(stored.updatedAt)) {
          _entries[stored.task.messageId] = stored;
        }
      }
      _trim();
    } catch (_) {
      // A damaged snapshot must not block chat/image startup or echo its raw
      // contents into the UI.
    }
  }

  Future<void> _persist() async {
    final preferences = _preferences ?? await _preferencesLoader();
    _preferences = preferences;
    if (_entries.isEmpty) {
      await preferences.remove(kImageGenerationTaskSnapshotsStorageKey);
      return;
    }
    final ordered = _entries.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    await preferences.setString(
      kImageGenerationTaskSnapshotsStorageKey,
      jsonEncode(<String, Object?>{
        'version': _imageGenerationTaskSnapshotVersion,
        'tasks': ordered
            .map(
              (entry) => <String, Object?>{
                'updated_at': entry.updatedAt.toIso8601String(),
                'task': _encode(entry.task),
              },
            )
            .toList(growable: false),
      }),
    );
  }

  Future<void> _enqueue(Future<void> Function() action) {
    final next = _writeTail.then<void>((_) => action());
    _writeTail = next.catchError((Object _) {});
    return _writeTail;
  }

  void _trim() {
    if (_entries.length <= maxEntries) return;
    final oldest = _entries.values.toList()
      ..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
    for (final entry in oldest.take(_entries.length - maxEntries)) {
      _entries.remove(entry.task.messageId);
    }
  }

  static Map<String, Object?> _encode(ImageGenerationTask task) => {
    'message_id': task.messageId,
    'session_id': task.sessionId,
    'prompt': task.prompt,
    'model_name': task.modelName,
    'channel_id': task.channelId,
    if (task.routeModelId?.trim().isNotEmpty == true)
      'route_model_id': task.routeModelId,
    'provider_profile_id': task.providerProfileId,
    'reference_image_paths': task.referenceImagePaths,
    'reference_image_names': task.referenceImageNames,
    'count': task.count,
    if (task.aspectRatio?.trim().isNotEmpty == true)
      'aspect_ratio': task.aspectRatio,
    if (task.resolution?.trim().isNotEmpty == true)
      'resolution': task.resolution,
    if (task.size?.trim().isNotEmpty == true) 'size': task.size,
    if (task.quality?.trim().isNotEmpty == true) 'quality': task.quality,
    'typed_options': task.typedOptions,
    'status': task.status.name,
    if (task.error?.trim().isNotEmpty == true) 'error': task.compactError,
  };

  static _StoredImageGenerationTask? _decode(Object? raw) {
    final wrapper = _map(raw);
    final value = _map(wrapper?['task']);
    if (wrapper == null || value == null) return null;
    final messageId = _required(value['message_id'], maxLength: 128);
    final sessionId = _required(value['session_id'], maxLength: 128);
    final prompt = _required(value['prompt'], maxLength: 4000);
    final modelName = _required(value['model_name'], maxLength: 256);
    final channelId = _required(value['channel_id'], maxLength: 256);
    if (messageId == null ||
        sessionId == null ||
        prompt == null ||
        modelName == null ||
        channelId == null) {
      return null;
    }
    final updatedAt =
        DateTime.tryParse(_text(wrapper['updated_at']) ?? '')?.toUtc() ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    final paths = _strings(value['reference_image_paths'], maxEntries: 8);
    final names = _strings(value['reference_image_names'], maxEntries: 8);
    final count = _positiveInt(value['count'])?.clamp(1, 10) ?? 1;
    final status = switch (_text(value['status'])) {
      'cancelled' => ImageGenerationTaskStatus.cancelled,
      'failed' => ImageGenerationTaskStatus.failed,
      _ => ImageGenerationTaskStatus.running,
    };
    return _StoredImageGenerationTask(
      task: ImageGenerationTask(
        messageId: messageId,
        sessionId: sessionId,
        prompt: prompt,
        modelName: modelName,
        channelId: channelId,
        routeModelId: _optional(value['route_model_id'], maxLength: 256),
        providerProfileId:
            _optional(value['provider_profile_id'], maxLength: 128) ??
            'openai_images',
        referenceImagePath: paths.isEmpty ? null : paths.first,
        referenceImageName: names.isEmpty ? null : names.first,
        referenceImagePaths: paths,
        referenceImageNames: names,
        count: count,
        aspectRatio: _optional(value['aspect_ratio'], maxLength: 32),
        resolution: _optional(value['resolution'], maxLength: 32),
        size: _optional(value['size'], maxLength: 32),
        quality: _optional(value['quality'], maxLength: 32),
        typedOptions: value['typed_options'] == true,
        status: status,
        error: _optional(value['error'], maxLength: 200),
      ),
      updatedAt: updatedAt,
    );
  }

  static ImageGenerationTask _copyTask(
    ImageGenerationTask task, {
    bool forRecovery = false,
  }) {
    final wasInterrupted =
        forRecovery && task.status == ImageGenerationTaskStatus.running;
    return ImageGenerationTask(
      messageId: task.messageId,
      sessionId: task.sessionId,
      prompt: task.prompt,
      referenceImagePath: task.referenceImagePath,
      referenceImageName: task.referenceImageName,
      modelName: task.modelName,
      channelId: task.channelId,
      routeModelId: task.routeModelId,
      providerProfileId: task.providerProfileId,
      referenceImagePaths: List<String>.unmodifiable(task.referenceImagePaths),
      referenceImageNames: List<String>.unmodifiable(task.referenceImageNames),
      count: task.count,
      aspectRatio: task.aspectRatio,
      resolution: task.resolution,
      size: task.size,
      quality: task.quality,
      typedOptions: task.typedOptions,
      status: wasInterrupted ? ImageGenerationTaskStatus.failed : task.status,
      error: wasInterrupted ? '应用重启后图片任务已中断，可重试' : task.error,
    );
  }

  static Map<String, dynamic>? _map(Object? value) {
    if (value is! Map) return null;
    return value.map((key, item) => MapEntry(key.toString(), item));
  }

  static String? _text(Object? value) => value is String ? value.trim() : null;

  static String? _required(Object? value, {required int maxLength}) {
    final text = _text(value);
    if (text == null || text.isEmpty || text.length > maxLength) return null;
    return text;
  }

  static String? _optional(Object? value, {required int maxLength}) {
    final text = _text(value);
    if (text == null || text.isEmpty) return null;
    return text.length <= maxLength ? text : text.substring(0, maxLength);
  }

  static int? _positiveInt(Object? value) {
    final number = value is num ? value.toInt() : int.tryParse('$value');
    return number != null && number > 0 ? number : null;
  }

  static List<String> _strings(Object? value, {required int maxEntries}) {
    if (value is! List) return const [];
    final result = <String>[];
    final seen = <String>{};
    for (final raw in value) {
      final text = _optional(raw, maxLength: 2048);
      if (text != null && seen.add(text)) result.add(text);
      if (result.length >= maxEntries) break;
    }
    return List<String>.unmodifiable(result);
  }
}

/// Placeholder id -> image task. The in-memory map remains the fast UI read
/// model; [ImageGenerationTaskSnapshotStore] is the cold-start retry source.
final imageGenerationTasksProvider =
    StateNotifierProvider<
      ImageGenerationTasksNotifier,
      Map<String, ImageGenerationTask>
    >((ref) {
      final database = ref.read(databaseProvider);
      return ImageGenerationTasksNotifier(
        store: ImageGenerationTaskSnapshotStore(),
        taskExists: (task) async {
          final messages = await database.messageDao.getMessagesBySession(
            task.sessionId,
          );
          return messages.any((message) => message.id == task.messageId);
        },
      );
    });

class ImageGenerationTasksNotifier
    extends StateNotifier<Map<String, ImageGenerationTask>> {
  ImageGenerationTasksNotifier({
    ImageGenerationTaskSnapshotStore? store,
    ImageGenerationTaskExists? taskExists,
  }) : _store = store ?? ImageGenerationTaskSnapshotStore(),
       _taskExists = taskExists,
       super(const {}) {
    ready = _restore();
  }

  final ImageGenerationTaskSnapshotStore _store;
  final ImageGenerationTaskExists? _taskExists;
  final Map<String, CancelToken> _cancelTokens = {};
  int _mutationGeneration = 0;

  late final Future<void> ready;

  Future<void> _restore() async {
    final generation = _mutationGeneration;
    final restored = await _store.readAll();
    if (generation != _mutationGeneration) return;
    final valid = <String, ImageGenerationTask>{};
    for (final task in restored) {
      final exists = _taskExists == null || await _taskExists(task);
      if (exists) {
        valid[task.messageId] = task;
      } else {
        unawaited(_store.remove(task.messageId));
      }
    }
    if (generation == _mutationGeneration && valid.isNotEmpty) {
      state = Map<String, ImageGenerationTask>.unmodifiable(valid);
      for (final task in valid.values) {
        unawaited(_store.upsert(task));
      }
    }
  }

  CancelToken start(ImageGenerationTask task) {
    _mutationGeneration++;
    final cancelToken = CancelToken();
    _cancelTokens[task.messageId] = cancelToken;
    state = {...state, task.messageId: task};
    unawaited(_store.upsert(task));
    return cancelToken;
  }

  void markFailed(String messageId, String error) {
    final task = state[messageId];
    if (task == null) return;
    _mutationGeneration++;
    task.status = ImageGenerationTaskStatus.failed;
    task.error = error;
    state = {...state, messageId: task};
    _cancelTokens.remove(messageId);
    unawaited(_store.upsert(task));
  }

  void markCancelled(String messageId) {
    final task = state[messageId];
    if (task == null) return;
    _mutationGeneration++;
    task.status = ImageGenerationTaskStatus.cancelled;
    state = {...state, messageId: task};
    _cancelTokens.remove(messageId);
    unawaited(_store.upsert(task));
  }

  void finish(String messageId) {
    if (!state.containsKey(messageId)) return;
    _mutationGeneration++;
    final updated = Map<String, ImageGenerationTask>.from(state)
      ..remove(messageId);
    state = updated;
    _cancelTokens.remove(messageId);
    unawaited(_store.remove(messageId));
  }

  Future<void> cancelForSession(String sessionId) async {
    final running = state.values
        .where(
          (task) =>
              task.sessionId == sessionId &&
              task.status == ImageGenerationTaskStatus.running,
        )
        .toList();
    for (final task in running) {
      final token = _cancelTokens[task.messageId];
      if (token != null && !token.isCancelled) token.cancel();
      markCancelled(task.messageId);
    }
  }
}

class _StoredImageGenerationTask {
  const _StoredImageGenerationTask({
    required this.task,
    required this.updatedAt,
  });

  final ImageGenerationTask task;
  final DateTime updatedAt;
}
