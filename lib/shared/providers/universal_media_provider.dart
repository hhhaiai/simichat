import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/ai/model_capability.dart';
import '../../core/ai/universal_media_service.dart';
import '../../core/database/app_database.dart' as database;
import '../../core/database/dao/channel_dao.dart';
import '../../core/database/dao/media_job_dao.dart' as media_database;
import 'channel_provider.dart';
import 'database_provider.dart';

const kUniversalMediaVideoModelStorageKey = 'universal_media_video_model_v1';
const kUniversalMediaVideoEndpointStorageKey =
    'universal_media_video_endpoint_v1';
const kUniversalMediaVideoChannelModelIdStorageKey =
    'universal_media_video_channel_model_id_v1';
const kUniversalMediaMusicModelStorageKey = 'universal_media_music_model_v1';
const kUniversalMediaMusicEndpointStorageKey =
    'universal_media_music_endpoint_v1';
const kUniversalMediaMusicChannelModelIdStorageKey =
    'universal_media_music_channel_model_id_v1';
const kUniversalMediaVideoTaskOptionsStorageKey =
    'universal_media_video_task_options_v1';
const kUniversalMediaMusicTaskOptionsStorageKey =
    'universal_media_music_task_options_v1';
const kUniversalMediaVideoProfileStorageKey =
    'universal_media_video_profile_v1';
const kUniversalMediaMusicProfileStorageKey =
    'universal_media_music_profile_v1';

/// Built-in media profile IDs.  Profiles only contain public routing defaults;
/// the API key continues to come from the selected chat channel.
const kUniversalMediaProfileOpenAiSora = 'openai_sora';
const kUniversalMediaProfileXaiGrokVideo = 'xai_grok_video';
const kUniversalMediaProfileOpenAiCompatibleCustom = 'openai_compatible_custom';
const kUniversalMediaProfileMusicOpenAiCompatible = 'music_openai_compatible';
const kUniversalMediaProfileMusicCustomAsync = 'music_custom_async';
const kUniversalMediaProfileCustomAsync = 'custom_async';

/// Profile IDs kept as named aliases for callers that prefer a media-specific
/// constant.  They intentionally resolve to the same SharedPreferences-safe
/// values above.
const kUniversalMediaVideoProfileOpenAiSora = kUniversalMediaProfileOpenAiSora;
const kUniversalMediaVideoProfileXaiGrok = kUniversalMediaProfileXaiGrokVideo;
const kUniversalMediaVideoProfileCustom =
    kUniversalMediaProfileOpenAiCompatibleCustom;
const kUniversalMediaProfileOpenAiSoraVideo = kUniversalMediaProfileOpenAiSora;
const kUniversalMediaProfileOpenAiCompatibleVideo =
    kUniversalMediaProfileOpenAiCompatibleCustom;
const kUniversalMediaProfileOpenAiCompatibleMusic =
    kUniversalMediaProfileMusicOpenAiCompatible;
const kUniversalMediaProfileVideoCustomAsync =
    kUniversalMediaProfileCustomAsync;
const kUniversalMediaMusicProfileOpenAiCompatible =
    kUniversalMediaProfileMusicOpenAiCompatible;
const kUniversalMediaMusicProfileCustomAsync =
    kUniversalMediaProfileMusicCustomAsync;

/// A public, credential-free provider preset for one media kind.
///
/// `model` and `endpoint` are quick-fill values only.  They do not prove that
/// the current channel owns the provider, has quota, or accepts the request.
/// [taskOptions] is the exact protocol hint passed to the media service.
class UniversalMediaProviderProfile {
  const UniversalMediaProviderProfile({
    required this.id,
    required this.name,
    required this.kind,
    required this.model,
    required this.endpoint,
    required this.description,
    this.taskOptions = const UniversalMediaTaskOptions(),
  });

  final String id;
  final String name;
  final UniversalMediaKind kind;
  final String model;
  final String endpoint;
  final String description;
  final UniversalMediaTaskOptions taskOptions;

  String get label => name;

  String get defaultModel => model;

  String get defaultEndpoint => endpoint;

  String get protocolLabel => universalMediaProtocolLabel(taskOptions.protocol);

  String get requestFormatLabel =>
      universalMediaRequestFormatLabel(taskOptions.requestFormat);

  String get protocolName => taskOptions.protocol.name;

  String get requestFormatName => taskOptions.requestFormat.name;

  String get wireSummary => universalMediaTaskOptionsSummary(taskOptions);
}

/// The profiles are deliberately relative-endpoint and key-free.  The first
/// two use the two well-known video task shapes; the remaining entries cover a
/// generic OpenAI-compatible route and an explicit music async route.
const kUniversalMediaProviderProfiles = <UniversalMediaProviderProfile>[
  UniversalMediaProviderProfile(
    id: kUniversalMediaProfileOpenAiSora,
    name: 'OpenAI / Sora 视频',
    kind: UniversalMediaKind.video,
    model: 'sora-2',
    endpoint: '/v1/videos',
    description:
        'OpenAI Videos 风格：POST /v1/videos，任务按 /v1/videos/{id} 查询，参考图字段为 input_reference。',
    taskOptions: UniversalMediaTaskOptions.openAiVideo(),
  ),
  UniversalMediaProviderProfile(
    id: kUniversalMediaProfileXaiGrokVideo,
    name: 'xAI / Grok 视频',
    kind: UniversalMediaKind.video,
    model: 'grok-imagine-video',
    endpoint: '/v1/videos/generations',
    description:
        'xAI Imagine 风格：POST /v1/videos/generations，响应 request_id 后查询 /v1/videos/{request_id}。',
    taskOptions: UniversalMediaTaskOptions.xAiVideo(),
  ),
  UniversalMediaProviderProfile(
    id: kUniversalMediaProfileOpenAiCompatibleCustom,
    name: 'OpenAI 兼容自定义视频',
    kind: UniversalMediaKind.video,
    model: kDefaultVideoGenerationModel,
    endpoint: kDefaultVideoGenerationEndpoint,
    description:
        '不猜测厂商协议：保留 model + prompt 与自动响应解析，适合 OpenAI-compatible 中转或自定义视频接口。',
  ),
  UniversalMediaProviderProfile(
    id: kUniversalMediaProfileCustomAsync,
    name: '视频 / 自定义异步任务',
    kind: UniversalMediaKind.video,
    model: 'video-model',
    endpoint: '/v1/video/tasks',
    description:
        '显式 configuredAsync：可编辑轮询、结果和取消 URL 模板；模板中的 {id} 会替换为服务端任务 ID。',
    taskOptions: UniversalMediaTaskOptions.configuredAsync(
      requestFormat: UniversalMediaRequestFormat.json,
      referenceField: 'image',
      pollUrlTemplate: '/v1/video/tasks/{id}/status',
      contentUrlTemplate: '/v1/video/tasks/{id}/content',
      cancelUrlTemplate: '/v1/video/tasks/{id}',
    ),
  ),
  UniversalMediaProviderProfile(
    id: kUniversalMediaProfileMusicOpenAiCompatible,
    name: 'OpenAI 兼容音乐',
    kind: UniversalMediaKind.music,
    model: kDefaultMusicGenerationModel,
    endpoint: kDefaultMusicGenerationEndpoint,
    description: '通用音乐路由：提交 model + prompt；服务端返回二进制、URL 或异步任务均由现有解析器处理。',
    taskOptions: UniversalMediaTaskOptions(
      requestFormat: UniversalMediaRequestFormat.json,
    ),
  ),
  UniversalMediaProviderProfile(
    id: kUniversalMediaProfileMusicCustomAsync,
    name: '音乐 / 自定义异步任务',
    kind: UniversalMediaKind.music,
    model: 'music-model',
    endpoint: '/v1/audio/music/tasks',
    description:
        '显式 configuredAsync：可编辑轮询、结果和取消 URL 模板；模板中的 {id} 会替换为服务端任务 ID。',
    taskOptions: UniversalMediaTaskOptions.configuredAsync(
      requestFormat: UniversalMediaRequestFormat.json,
      pollUrlTemplate: '/v1/audio/music/tasks/{id}',
      contentUrlTemplate: '/v1/audio/music/tasks/{id}/content',
      cancelUrlTemplate: '/v1/audio/music/tasks/{id}',
    ),
  ),
];

List<UniversalMediaProviderProfile> universalMediaProviderProfilesFor(
  UniversalMediaKind kind,
) => kUniversalMediaProviderProfiles
    .where((profile) => profile.kind == kind)
    .toList(growable: false);

/// Compatibility aliases for callers that used the shorter preset API while
/// the settings entry was being introduced.
List<UniversalMediaProviderProfile> universalMediaProfilesFor(
  UniversalMediaKind kind,
) => universalMediaProviderProfilesFor(kind);

/// A model that can be selected for a media route without changing the
/// conversation's Chat model.
///
/// Media capability is intentionally strict: a database row is declared
/// usable for this kind only when its persisted capability is `video` or
/// `music`.  Known media-shaped IDs may still be shown as
/// [kUniversalMediaUndeclaredModelCapability] so an existing configuration is
/// discoverable, but the UI never presents that name as proof of remote
/// support.
class UniversalMediaModelCandidate {
  const UniversalMediaModelCandidate({
    required this.channelName,
    required this.modelName,
    required this.capability,
    required this.isDeclared,
    required this.isCurrent,
    required this.isManual,
    this.channelModelId,
  });

  final String? channelModelId;
  final String channelName;
  final String modelName;
  final String capability;
  final bool isDeclared;
  final bool isCurrent;
  final bool isManual;

  String get capabilityLabel => isDeclared
      ? ModelCapability.label(capability)
      : kUniversalMediaUndeclaredModelCapabilityLabel;

  String get displayLabel => '$channelName / $modelName';

  String get displayText => '$displayLabel · 能力：$capabilityLabel';

  String get selectionKey => channelModelId == null
      ? '$kUniversalMediaManualModelSelectionKey:$modelName'
      : 'channel-model:$channelModelId';

  factory UniversalMediaModelCandidate.manual({
    required String modelName,
    bool isCurrent = false,
  }) {
    return UniversalMediaModelCandidate(
      channelName: kUniversalMediaManualModelChannelLabel,
      modelName: modelName,
      capability: kUniversalMediaUndeclaredModelCapability,
      isDeclared: false,
      isCurrent: isCurrent,
      isManual: true,
    );
  }
}

const kUniversalMediaUndeclaredModelCapability = 'manual';
const kUniversalMediaUndeclaredModelCapabilityLabel = '手动/未声明';
const kUniversalMediaManualModelChannelLabel = '手动输入 / 自定义模型';
const kUniversalMediaManualModelSelectionKey = 'manual-model';

/// Build the media-only catalog from all models in enabled channels.
///
/// This function never infers a real media capability from a model name.  A
/// few recognizable IDs (for example `sora-*` and
/// `grok-imagine-video`) are retained as manual candidates so old channel
/// rows are not lost after the chat selector becomes stricter.  Their
/// capability remains [kUniversalMediaUndeclaredModelCapability].
List<UniversalMediaModelCandidate> buildUniversalMediaModelCandidates({
  required UniversalMediaKind kind,
  required Iterable<ChannelModelWithChannel> models,
  required String currentModel,
  String? currentChannelModelId,
}) {
  final expectedCapability = _mediaCapabilityForKind(kind);
  if (expectedCapability == null) return const [];

  final current = currentModel.trim();
  final currentId = currentChannelModelId?.trim();
  final result = <UniversalMediaModelCandidate>[];
  final seen = <String>{};

  for (final item in models) {
    final modelName = item.channelModel.modelName.trim();
    if (modelName.isEmpty) continue;
    final isCurrent = currentId != null && currentId.isNotEmpty
        ? item.channelModel.id.trim() == currentId
        : current.isNotEmpty && modelName == current;
    final isDeclared = ModelCapability.supportsMediaModel(
      capability: item.channelModel.capability,
      capabilities: item.capabilities,
      modelId: modelName,
      mediaType: expectedCapability,
    );
    final keepAsManual =
        !isDeclared && _looksLikeMediaModelName(modelName, kind);
    if (!isDeclared && !keepAsManual) continue;

    final key = 'channel-model:${item.channelModel.id}';
    if (!seen.add(key)) continue;
    result.add(
      UniversalMediaModelCandidate(
        channelModelId: item.channelModel.id,
        channelName: item.channel.name,
        modelName: modelName,
        capability: isDeclared
            ? expectedCapability
            : kUniversalMediaUndeclaredModelCapability,
        isDeclared: isDeclared,
        isCurrent: isCurrent,
        isManual: !isDeclared,
      ),
    );
  }

  final hasCurrentChannelModel =
      currentId != null &&
      currentId.isNotEmpty &&
      result.any((candidate) => candidate.channelModelId == currentId);
  final hasLegacyCurrentModel =
      (currentId == null || currentId.isEmpty) &&
      result.any((candidate) => candidate.modelName == current);
  if (current.isNotEmpty &&
      ((!hasCurrentChannelModel && currentId != null && currentId.isNotEmpty) ||
          (!hasLegacyCurrentModel &&
              (currentId == null || currentId.isEmpty)))) {
    result.add(
      UniversalMediaModelCandidate.manual(modelName: current, isCurrent: true),
    );
  }
  return result;
}

/// Short alias for callers that prefer the provider-style naming.
List<UniversalMediaModelCandidate> universalMediaModelCandidatesFor({
  required UniversalMediaKind kind,
  required Iterable<ChannelModelWithChannel> models,
  required String currentModel,
  String? currentChannelModelId,
}) => buildUniversalMediaModelCandidates(
  kind: kind,
  models: models,
  currentModel: currentModel,
  currentChannelModelId: currentChannelModelId,
);

final universalMediaModelCandidatesProvider = FutureProvider.autoDispose
    .family<List<UniversalMediaModelCandidate>, UniversalMediaKind>((
      ref,
      kind,
    ) async {
      await ref.read(universalMediaConfigProvider.notifier).ready;
      final configuredModels = await ref.watch(
        allConfiguredModelsProvider.future,
      );
      final config = ref.watch(universalMediaConfigProvider);
      final currentModel = kind == UniversalMediaKind.video
          ? config.videoModel
          : kind == UniversalMediaKind.music
          ? config.musicModel
          : '';
      final currentChannelModelId = kind == UniversalMediaKind.video
          ? config.videoChannelModelId
          : kind == UniversalMediaKind.music
          ? config.musicChannelModelId
          : null;
      return buildUniversalMediaModelCandidates(
        kind: kind,
        models: configuredModels,
        currentModel: currentModel,
        currentChannelModelId: currentChannelModelId,
      );
    });

String? _mediaCapabilityForKind(UniversalMediaKind kind) {
  return switch (kind) {
    UniversalMediaKind.video => ModelCapability.video,
    UniversalMediaKind.music => ModelCapability.music,
    UniversalMediaKind.image => null,
  };
}

bool _looksLikeMediaModelName(String modelName, UniversalMediaKind kind) {
  final normalized = modelName.trim().toLowerCase();
  if (normalized.isEmpty) return false;
  return switch (kind) {
    UniversalMediaKind.video =>
      normalized == 'sora' ||
          normalized.startsWith('sora-') ||
          normalized.startsWith('sora/') ||
          normalized.startsWith('veo-') ||
          normalized.contains('video-generation') ||
          normalized.contains('video_generation') ||
          normalized == 'grok-imagine-video',
    UniversalMediaKind.music =>
      normalized.contains('musicgen') ||
          normalized.contains('music-generation') ||
          normalized.contains('music_generation') ||
          normalized.startsWith('lyria-'),
    UniversalMediaKind.image => false,
  };
}

UniversalMediaProviderProfile universalMediaProfileFor({
  required UniversalMediaKind kind,
  required String id,
}) =>
    findUniversalMediaProviderProfile(id, kind: kind) ??
    universalMediaProviderProfilesFor(kind).first;

String normalizeUniversalMediaProfileId({
  required UniversalMediaKind kind,
  required String id,
}) {
  final profile = findUniversalMediaProviderProfile(id, kind: kind);
  if (profile == null) {
    throw ArgumentError.value(id, 'profile', '不是可用的通用媒体 profile');
  }
  return profile.id;
}

/// Resolve a stored or user-entered profile ID.  A few human-friendly aliases
/// make old hand-edited preferences and import snippets migrate safely.
UniversalMediaProviderProfile? findUniversalMediaProviderProfile(
  String? id, {
  UniversalMediaKind? kind,
}) {
  var normalized = _normalizeUniversalMediaProfileId(id);
  if (normalized == kUniversalMediaProfileCustomAsync &&
      kind == UniversalMediaKind.music) {
    normalized = kUniversalMediaProfileMusicCustomAsync;
  }
  if (normalized.isEmpty) return null;
  for (final profile in kUniversalMediaProviderProfiles) {
    if (profile.id == normalized && (kind == null || profile.kind == kind)) {
      return profile;
    }
  }
  return null;
}

String universalMediaProtocolLabel(UniversalMediaProtocol protocol) {
  return switch (protocol) {
    UniversalMediaProtocol.auto => '自动兼容',
    UniversalMediaProtocol.openAiImages => 'OpenAI Images',
    UniversalMediaProtocol.openAiVideo => 'OpenAI Videos',
    UniversalMediaProtocol.xAiVideo => 'xAI Videos',
    UniversalMediaProtocol.configuredAsync => '自定义异步',
  };
}

String universalMediaRequestFormatLabel(UniversalMediaRequestFormat format) {
  return switch (format) {
    UniversalMediaRequestFormat.auto => '自动（无参考图 JSON）',
    UniversalMediaRequestFormat.json => 'JSON',
    UniversalMediaRequestFormat.multipart => 'multipart',
  };
}

String universalMediaTaskOptionsSummary(UniversalMediaTaskOptions options) {
  final parts = <String>[
    'protocol=${options.protocol.name}',
    'request_format=${options.requestFormat.name}',
  ];
  if (options.referenceField != null) {
    parts.add('reference_field=${options.referenceField}');
  }
  if (options.pollUrlTemplate != null) {
    parts.add('poll_url_template=${options.pollUrlTemplate}');
  }
  if (options.contentUrlTemplate != null) {
    parts.add('content_url_template=${options.contentUrlTemplate}');
  }
  if (options.cancelUrlTemplate != null) {
    parts.add('cancel_url_template=${options.cancelUrlTemplate}');
  }
  return parts.join(' · ');
}

String _normalizeUniversalMediaProfileId(String? id) {
  final normalized = id?.trim().toLowerCase() ?? '';
  return switch (normalized.replaceAll('-', '_').replaceAll(' ', '_')) {
    'sora' ||
    'openai' ||
    'openai_video' ||
    'openai_sora' ||
    'openai_sora_video' => kUniversalMediaProfileOpenAiSora,
    'xai' ||
    'grok' ||
    'grok_video' ||
    'xai_video' ||
    'xai_grok_video' => kUniversalMediaProfileXaiGrokVideo,
    'custom' ||
    'video_custom' ||
    'openai_custom' ||
    'openai_compatible' ||
    'openai_compatible_custom' ||
    'openai_compatible_video' => kUniversalMediaProfileOpenAiCompatibleCustom,
    'music' ||
    'music_openai' ||
    'music_compatible' ||
    'music_openai_compatible' ||
    'openai_compatible_music' => kUniversalMediaProfileMusicOpenAiCompatible,
    'async' ||
    'music_async' ||
    'configured_async' ||
    'music_custom_async' => kUniversalMediaProfileMusicCustomAsync,
    'custom_async' => kUniversalMediaProfileCustomAsync,
    _ => normalized,
  };
}

String _inferUniversalMediaProfileId({
  required UniversalMediaKind kind,
  required String model,
  required String endpoint,
  required UniversalMediaTaskOptions taskOptions,
}) {
  if (kind == UniversalMediaKind.music) {
    final hasExplicitAsyncRoute =
        taskOptions.protocol == UniversalMediaProtocol.configuredAsync ||
        taskOptions.pollUrlTemplate != null ||
        taskOptions.contentUrlTemplate != null ||
        taskOptions.cancelUrlTemplate != null;
    return hasExplicitAsyncRoute
        ? kUniversalMediaProfileMusicCustomAsync
        : kUniversalMediaProfileMusicOpenAiCompatible;
  }

  final lowerModel = model.trim().toLowerCase();
  final lowerEndpoint = endpoint.trim().toLowerCase();
  if (taskOptions.protocol == UniversalMediaProtocol.xAiVideo ||
      lowerModel.contains('grok-imagine-video') ||
      lowerEndpoint.contains('api.x.ai') ||
      lowerEndpoint.contains('/videos/generations') &&
          (lowerModel.contains('grok') || lowerModel.contains('xai'))) {
    return kUniversalMediaProfileXaiGrokVideo;
  }
  if (taskOptions.protocol == UniversalMediaProtocol.configuredAsync ||
      taskOptions.pollUrlTemplate != null ||
      taskOptions.contentUrlTemplate != null ||
      taskOptions.cancelUrlTemplate != null) {
    return kUniversalMediaProfileCustomAsync;
  }
  if (taskOptions.protocol == UniversalMediaProtocol.openAiVideo ||
      lowerModel.startsWith('sora') ||
      lowerEndpoint.endsWith('/v1/videos') ||
      lowerEndpoint.endsWith('/videos')) {
    return kUniversalMediaProfileOpenAiSora;
  }
  return kUniversalMediaProfileOpenAiCompatibleCustom;
}

String inferUniversalMediaProfileId({
  required UniversalMediaKind kind,
  required String model,
  required String endpoint,
  required UniversalMediaTaskOptions taskOptions,
}) => _inferUniversalMediaProfileId(
  kind: kind,
  model: model,
  endpoint: endpoint,
  taskOptions: taskOptions,
);

String _profileIdForConfig({
  required UniversalMediaKind kind,
  required String? storedId,
  required String model,
  required String endpoint,
  required UniversalMediaTaskOptions taskOptions,
}) {
  final stored = findUniversalMediaProviderProfile(storedId, kind: kind);
  return stored?.id ??
      _inferUniversalMediaProfileId(
        kind: kind,
        model: model,
        endpoint: endpoint,
        taskOptions: taskOptions,
      );
}

const Object _universalMediaConfigCopyWithUnset = Object();

String? _normalizeUniversalMediaChannelModelId(Object? value) {
  if (value == null) return null;
  if (value is! String) {
    throw ArgumentError.value(value, 'channelModelId', '必须是字符串或 null');
  }
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}

/// 视频 / 音乐使用所选渠道的 Base URL 与 API Key，
/// 这里只保存可替换的模型、endpoint 和渠道模型 ID，避免再复制一份密钥配置。
class UniversalMediaConfig {
  final String videoModel;
  final String videoEndpoint;
  final String? videoChannelModelId;
  final String musicModel;
  final String musicEndpoint;
  final String? musicChannelModelId;
  final UniversalMediaTaskOptions videoTaskOptions;
  final UniversalMediaTaskOptions musicTaskOptions;
  final String videoProfileId;
  final String musicProfileId;

  const UniversalMediaConfig({
    this.videoModel = kDefaultVideoGenerationModel,
    this.videoEndpoint = kDefaultVideoGenerationEndpoint,
    this.videoChannelModelId,
    this.musicModel = kDefaultMusicGenerationModel,
    this.musicEndpoint = kDefaultMusicGenerationEndpoint,
    this.musicChannelModelId,
    this.videoTaskOptions = const UniversalMediaTaskOptions(),
    this.musicTaskOptions = const UniversalMediaTaskOptions(),
    this.videoProfileId = kUniversalMediaProfileOpenAiSora,
    this.musicProfileId = kUniversalMediaProfileMusicOpenAiCompatible,
  });

  UniversalMediaProviderProfile get videoProfile =>
      findUniversalMediaProviderProfile(
        videoProfileId,
        kind: UniversalMediaKind.video,
      ) ??
      kUniversalMediaProviderProfiles.firstWhere(
        (profile) => profile.kind == UniversalMediaKind.video,
      );

  UniversalMediaProviderProfile get musicProfile =>
      findUniversalMediaProviderProfile(
        musicProfileId,
        kind: UniversalMediaKind.music,
      ) ??
      kUniversalMediaProviderProfiles.firstWhere(
        (profile) => profile.kind == UniversalMediaKind.music,
      );

  /// These route checks deliberately do not include channel protocol, model
  /// capability, or API-key state.  The chat composer owns that live gate;
  /// this provider only reports whether the local media route is saved.
  bool get videoRouteConfigured =>
      videoModel.trim().isNotEmpty && videoEndpoint.trim().isNotEmpty;

  bool get musicRouteConfigured =>
      musicModel.trim().isNotEmpty && musicEndpoint.trim().isNotEmpty;

  bool get hasConfiguredVideoRoute => videoRouteConfigured;

  bool get hasConfiguredMusicRoute => musicRouteConfigured;

  UniversalMediaConfig copyWith({
    String? videoModel,
    String? videoEndpoint,
    Object? videoChannelModelId = _universalMediaConfigCopyWithUnset,
    String? musicModel,
    String? musicEndpoint,
    Object? musicChannelModelId = _universalMediaConfigCopyWithUnset,
    UniversalMediaTaskOptions? videoTaskOptions,
    UniversalMediaTaskOptions? musicTaskOptions,
    String? videoProfileId,
    String? musicProfileId,
  }) {
    return UniversalMediaConfig(
      videoModel: videoModel ?? this.videoModel,
      videoEndpoint: videoEndpoint ?? this.videoEndpoint,
      videoChannelModelId:
          identical(videoChannelModelId, _universalMediaConfigCopyWithUnset)
          ? this.videoChannelModelId
          : _normalizeUniversalMediaChannelModelId(videoChannelModelId),
      musicModel: musicModel ?? this.musicModel,
      musicEndpoint: musicEndpoint ?? this.musicEndpoint,
      musicChannelModelId:
          identical(musicChannelModelId, _universalMediaConfigCopyWithUnset)
          ? this.musicChannelModelId
          : _normalizeUniversalMediaChannelModelId(musicChannelModelId),
      videoTaskOptions: videoTaskOptions ?? this.videoTaskOptions,
      musicTaskOptions: musicTaskOptions ?? this.musicTaskOptions,
      videoProfileId: videoProfileId ?? this.videoProfileId,
      musicProfileId: musicProfileId ?? this.musicProfileId,
    );
  }
}

final universalMediaConfigProvider =
    StateNotifierProvider<UniversalMediaConfigNotifier, UniversalMediaConfig>(
      (ref) => UniversalMediaConfigNotifier(),
    );

class UniversalMediaConfigNotifier extends StateNotifier<UniversalMediaConfig> {
  UniversalMediaConfigNotifier() : super(const UniversalMediaConfig()) {
    ready = _load();
  }

  late final Future<void> ready;

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final videoModel = _read(
        prefs,
        kUniversalMediaVideoModelStorageKey,
        kDefaultVideoGenerationModel,
      );
      final videoEndpoint = _read(
        prefs,
        kUniversalMediaVideoEndpointStorageKey,
        kDefaultVideoGenerationEndpoint,
      );
      final videoChannelModelId = _readOptional(
        prefs,
        kUniversalMediaVideoChannelModelIdStorageKey,
      );
      final musicModel = _read(
        prefs,
        kUniversalMediaMusicModelStorageKey,
        kDefaultMusicGenerationModel,
      );
      final musicEndpoint = _read(
        prefs,
        kUniversalMediaMusicEndpointStorageKey,
        kDefaultMusicGenerationEndpoint,
      );
      final musicChannelModelId = _readOptional(
        prefs,
        kUniversalMediaMusicChannelModelIdStorageKey,
      );
      final storedVideoTaskOptions = _readTaskOptions(
        prefs,
        kUniversalMediaVideoTaskOptionsStorageKey,
      );
      final storedMusicTaskOptions = _readTaskOptions(
        prefs,
        kUniversalMediaMusicTaskOptionsStorageKey,
      );
      final storedVideoProfileId = prefs.getString(
        kUniversalMediaVideoProfileStorageKey,
      );
      final storedMusicProfileId = prefs.getString(
        kUniversalMediaMusicProfileStorageKey,
      );
      final videoProfileId = _profileIdForConfig(
        kind: UniversalMediaKind.video,
        storedId: storedVideoProfileId,
        model: videoModel,
        endpoint: videoEndpoint,
        taskOptions: storedVideoTaskOptions,
      );
      final musicProfileId = _profileIdForConfig(
        kind: UniversalMediaKind.music,
        storedId: storedMusicProfileId,
        model: musicModel,
        endpoint: musicEndpoint,
        taskOptions: storedMusicTaskOptions,
      );
      final videoTaskOptions =
          prefs.containsKey(kUniversalMediaVideoTaskOptionsStorageKey)
          ? storedVideoTaskOptions
          : (findUniversalMediaProviderProfile(
                  videoProfileId,
                  kind: UniversalMediaKind.video,
                )?.taskOptions ??
                storedVideoTaskOptions);
      final musicTaskOptions =
          prefs.containsKey(kUniversalMediaMusicTaskOptionsStorageKey)
          ? storedMusicTaskOptions
          : (findUniversalMediaProviderProfile(
                  musicProfileId,
                  kind: UniversalMediaKind.music,
                )?.taskOptions ??
                storedMusicTaskOptions);

      state = UniversalMediaConfig(
        videoModel: videoModel,
        videoEndpoint: videoEndpoint,
        videoChannelModelId: videoChannelModelId,
        musicModel: musicModel,
        musicEndpoint: musicEndpoint,
        musicChannelModelId: musicChannelModelId,
        videoTaskOptions: videoTaskOptions,
        musicTaskOptions: musicTaskOptions,
        videoProfileId: videoProfileId,
        musicProfileId: musicProfileId,
      );

      // Migrate only the new, credential-free profile IDs.  Existing model,
      // endpoint, and task-option keys are read exactly as before.
      await _persistProfileMigration(
        prefs,
        key: kUniversalMediaVideoProfileStorageKey,
        storedId: storedVideoProfileId,
        resolvedId: videoProfileId,
      );
      await _persistProfileMigration(
        prefs,
        key: kUniversalMediaMusicProfileStorageKey,
        storedId: storedMusicProfileId,
        resolvedId: musicProfileId,
      );
    } catch (_) {
      // SharedPreferences 读取失败时继续使用安全默认值。
    }
  }

  Future<void> save({
    required String videoModel,
    required String videoEndpoint,
    Object? videoChannelModelId = _universalMediaConfigCopyWithUnset,
    required String musicModel,
    required String musicEndpoint,
    Object? musicChannelModelId = _universalMediaConfigCopyWithUnset,
    UniversalMediaTaskOptions? videoTaskOptions,
    UniversalMediaTaskOptions? musicTaskOptions,
    String? videoProfileId,
    String? musicProfileId,
  }) async {
    final requestedVideoProfile = videoProfileId == null
        ? null
        : findUniversalMediaProviderProfile(
            videoProfileId,
            kind: UniversalMediaKind.video,
          );
    final requestedMusicProfile = musicProfileId == null
        ? null
        : findUniversalMediaProviderProfile(
            musicProfileId,
            kind: UniversalMediaKind.music,
          );
    if (videoProfileId != null && requestedVideoProfile == null) {
      throw ArgumentError('未知的视频媒体 profile');
    }
    if (musicProfileId != null && requestedMusicProfile == null) {
      throw ArgumentError('未知的音乐媒体 profile');
    }
    final nextVideoTaskOptions =
        videoTaskOptions ??
        (requestedVideoProfile != null &&
                requestedVideoProfile.id != state.videoProfileId
            ? requestedVideoProfile.taskOptions
            : state.videoTaskOptions);
    final nextMusicTaskOptions =
        musicTaskOptions ??
        (requestedMusicProfile != null &&
                requestedMusicProfile.id != state.musicProfileId
            ? requestedMusicProfile.taskOptions
            : state.musicTaskOptions);
    nextVideoTaskOptions.validate();
    nextMusicTaskOptions.validate();
    final nextVideoModel = _required(videoModel, '视频模型');
    final nextVideoEndpoint = _required(videoEndpoint, '视频接口路径');
    final nextMusicModel = _required(musicModel, '音乐模型');
    final nextMusicEndpoint = _required(musicEndpoint, '音乐接口路径');
    final nextVideoChannelModelId =
        identical(videoChannelModelId, _universalMediaConfigCopyWithUnset)
        ? state.videoChannelModelId
        : _normalizeUniversalMediaChannelModelId(videoChannelModelId);
    final nextMusicChannelModelId =
        identical(musicChannelModelId, _universalMediaConfigCopyWithUnset)
        ? state.musicChannelModelId
        : _normalizeUniversalMediaChannelModelId(musicChannelModelId);
    final next = UniversalMediaConfig(
      videoModel: nextVideoModel,
      videoEndpoint: nextVideoEndpoint,
      videoChannelModelId: nextVideoChannelModelId,
      musicModel: nextMusicModel,
      musicEndpoint: nextMusicEndpoint,
      musicChannelModelId: nextMusicChannelModelId,
      videoTaskOptions: nextVideoTaskOptions,
      musicTaskOptions: nextMusicTaskOptions,
      videoProfileId: _profileIdForSave(
        kind: UniversalMediaKind.video,
        requestedId: videoProfileId,
        model: nextVideoModel,
        endpoint: nextVideoEndpoint,
        taskOptions: nextVideoTaskOptions,
      ),
      musicProfileId: _profileIdForSave(
        kind: UniversalMediaKind.music,
        requestedId: musicProfileId,
        model: nextMusicModel,
        endpoint: nextMusicEndpoint,
        taskOptions: nextMusicTaskOptions,
      ),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kUniversalMediaVideoModelStorageKey, next.videoModel);
    await prefs.setString(
      kUniversalMediaVideoEndpointStorageKey,
      next.videoEndpoint,
    );
    await _writeOptional(
      prefs,
      kUniversalMediaVideoChannelModelIdStorageKey,
      next.videoChannelModelId,
    );
    await prefs.setString(kUniversalMediaMusicModelStorageKey, next.musicModel);
    await prefs.setString(
      kUniversalMediaMusicEndpointStorageKey,
      next.musicEndpoint,
    );
    await _writeOptional(
      prefs,
      kUniversalMediaMusicChannelModelIdStorageKey,
      next.musicChannelModelId,
    );
    await prefs.setString(
      kUniversalMediaVideoTaskOptionsStorageKey,
      jsonEncode(next.videoTaskOptions.toJson()),
    );
    await prefs.setString(
      kUniversalMediaMusicTaskOptionsStorageKey,
      jsonEncode(next.musicTaskOptions.toJson()),
    );
    await prefs.setString(
      kUniversalMediaVideoProfileStorageKey,
      next.videoProfileId,
    );
    await prefs.setString(
      kUniversalMediaMusicProfileStorageKey,
      next.musicProfileId,
    );
    state = next;
  }

  static String _read(SharedPreferences prefs, String key, String fallback) {
    final value = prefs.getString(key)?.trim();
    return value == null || value.isEmpty ? fallback : value;
  }

  static String? _readOptional(SharedPreferences prefs, String key) {
    final value = prefs.get(key);
    return _normalizeUniversalMediaChannelModelId(
      value is String ? value : null,
    );
  }

  static Future<void> _writeOptional(
    SharedPreferences prefs,
    String key,
    String? value,
  ) async {
    if (value == null) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, value);
    }
  }

  static String _required(String value, String label) {
    final normalized = value.trim();
    if (normalized.isEmpty) throw ArgumentError('$label不能为空');
    if (normalized.length > 256) throw ArgumentError('$label过长');
    return normalized;
  }

  static String _profileIdForSave({
    required UniversalMediaKind kind,
    required String? requestedId,
    required String model,
    required String endpoint,
    required UniversalMediaTaskOptions taskOptions,
  }) {
    if (requestedId != null) {
      final profile = findUniversalMediaProviderProfile(
        requestedId,
        kind: kind,
      );
      if (profile == null) {
        throw ArgumentError(
          '未知的${kind == UniversalMediaKind.video ? '视频' : '音乐'}媒体 profile',
        );
      }
      return profile.id;
    }
    return _inferUniversalMediaProfileId(
      kind: kind,
      model: model,
      endpoint: endpoint,
      taskOptions: taskOptions,
    );
  }

  static Future<void> _persistProfileMigration(
    SharedPreferences prefs, {
    required String key,
    required String? storedId,
    required String resolvedId,
  }) async {
    final stored = findUniversalMediaProviderProfile(storedId);
    if (stored?.id == resolvedId) return;
    try {
      await prefs.setString(key, resolvedId);
    } catch (_) {
      // A read-only preference store must not make an otherwise valid legacy
      // media configuration unavailable.
    }
  }

  static UniversalMediaTaskOptions _readTaskOptions(
    SharedPreferences prefs,
    String key,
  ) {
    final encoded = prefs.getString(key)?.trim();
    if (encoded == null || encoded.isEmpty) {
      return const UniversalMediaTaskOptions();
    }
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is Map) {
        return UniversalMediaTaskOptions.fromJson(
          Map<String, dynamic>.from(decoded),
        );
      }
    } catch (_) {
      // 配置损坏时回退到无猜测的默认 profile，不阻塞其它媒体配置加载。
    }
    return const UniversalMediaTaskOptions();
  }
}

/// 一次媒体操作对应的一组本地交付键。
///
/// 这些键不包含凭据，也不依赖服务端返回的随机任务 ID。它们从本地
/// operation ID 派生，因此进程重启、重复恢复和同一任务的重试都能定位
/// 到同一条消息 / 同一个附件。
class UniversalMediaDeliveryIds {
  const UniversalMediaDeliveryIds({
    required this.userMessageId,
    required this.assistantMessageId,
    required this.attachmentId,
    required this.sourceAttachmentId,
    required this.fileStem,
  });

  final String userMessageId;
  final String assistantMessageId;
  final String attachmentId;
  final String sourceAttachmentId;
  final String fileStem;

  factory UniversalMediaDeliveryIds.forOperationId(String operationId) {
    final normalized = operationId.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(operationId, 'operationId', '不能为空');
    }
    final stem = normalized
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '-')
        .replaceAll(RegExp('-+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final rawStem = stem.isEmpty ? 'media-operation' : stem;
    final bounded = rawStem.substring(
      0,
      rawStem.length > 160 ? 160 : rawStem.length,
    );
    return UniversalMediaDeliveryIds(
      userMessageId: '$bounded-user',
      assistantMessageId: '$bounded-assistant',
      attachmentId: '$bounded-attachment',
      sourceAttachmentId: '$bounded-source',
      fileStem: bounded,
    );
  }

  factory UniversalMediaDeliveryIds.fromDatabaseRow(database.MediaJob row) {
    final fallback = UniversalMediaDeliveryIds.forOperationId(row.id);
    return UniversalMediaDeliveryIds(
      userMessageId: row.deliveryUserMessageId ?? fallback.userMessageId,
      assistantMessageId:
          row.deliveryAssistantMessageId ?? fallback.assistantMessageId,
      attachmentId: row.deliveryAttachmentId ?? fallback.attachmentId,
      sourceAttachmentId:
          row.deliverySourceAttachmentId ?? fallback.sourceAttachmentId,
      fileStem: fallback.fileStem,
    );
  }
}

/// 当前任务没有获得数据库 owner 时，不能继续执行网络轮询。
class UniversalMediaClaimException extends UniversalMediaException {
  const UniversalMediaClaimException(this.operationId)
    : super('媒体任务未获得 worker 所有权：$operationId');

  final String operationId;
}

/// lease 失效后，旧 worker 不得再写入状态或继续下载媒体。
class UniversalMediaLeaseLostException extends UniversalMediaException {
  const UniversalMediaLeaseLostException(this.operationId)
    : super('媒体任务 lease 已失效：$operationId');

  final String operationId;
}

/// 数据库中已有另一个 terminal 结果时，调用方必须使用数据库事实，不能
/// 把自己的旧结果当成成功返回。
class UniversalMediaStateConflictException extends UniversalMediaException {
  const UniversalMediaStateConflictException(this.operationId)
    : super('媒体任务状态已由其它 worker 决定：$operationId');

  final String operationId;
}

enum UniversalMediaTaskPhase {
  submitting,
  pending,
  polling,
  saving,
  completed,
  failed,
  expired,
  cancelled,
}

class UniversalMediaTaskState {
  const UniversalMediaTaskState({
    required this.operationId,
    required this.kind,
    required this.phase,
    this.job,
    this.error,
  });

  final String operationId;
  final UniversalMediaKind kind;
  final UniversalMediaTaskPhase phase;
  final UniversalMediaJob? job;
  final String? error;

  bool get isBusy => switch (phase) {
    UniversalMediaTaskPhase.submitting ||
    UniversalMediaTaskPhase.pending ||
    UniversalMediaTaskPhase.polling ||
    UniversalMediaTaskPhase.saving => true,
    _ => false,
  };

  bool get canRetry =>
      phase == UniversalMediaTaskPhase.failed ||
      phase == UniversalMediaTaskPhase.expired ||
      phase == UniversalMediaTaskPhase.cancelled;

  bool get showInComposer => phase != UniversalMediaTaskPhase.completed;

  String get kindLabel => kind == UniversalMediaKind.video ? '视频' : '音乐';

  String get statusText {
    final attempts = job?.attempts ?? 0;
    return switch (phase) {
      UniversalMediaTaskPhase.submitting => '$kindLabel提交中…',
      UniversalMediaTaskPhase.pending || UniversalMediaTaskPhase.polling =>
        attempts > 0 ? '$kindLabel生成中 · 已查询 $attempts 次' : '$kindLabel生成中…',
      UniversalMediaTaskPhase.saving => '$kindLabel生成完成，正在保存…',
      UniversalMediaTaskPhase.completed => '$kindLabel已完成',
      UniversalMediaTaskPhase.failed => '$kindLabel生成失败：${error ?? '请重试'}',
      UniversalMediaTaskPhase.expired => '$kindLabel任务已过期：${error ?? '请重试'}',
      UniversalMediaTaskPhase.cancelled => '$kindLabel生成已取消，可重试',
    };
  }
}

final universalMediaTaskProvider =
    StateNotifierProvider.family<
      UniversalMediaTaskNotifier,
      UniversalMediaTaskState?,
      String
    >((ref, sessionId) => UniversalMediaTaskNotifier(sessionId));

class UniversalMediaTaskNotifier
    extends StateNotifier<UniversalMediaTaskState?> {
  UniversalMediaTaskNotifier(this.sessionId) : super(null);

  final String sessionId;

  /// Public read-only view used by the chat operation boundary. Keeping the
  /// StateNotifier state protected prevents callers from mutating the state
  /// directly while still allowing cancellation/failure paths to preserve the
  /// latest persisted job metadata.
  UniversalMediaJob? get currentJob => state?.job;

  void begin({required String operationId, required UniversalMediaKind kind}) {
    state = UniversalMediaTaskState(
      operationId: operationId,
      kind: kind,
      phase: UniversalMediaTaskPhase.submitting,
    );
  }

  void updateJob(UniversalMediaJob job) {
    final current = state;
    if (current == null || current.kind != job.kind) return;
    final phase = switch (job.status) {
      UniversalMediaJobStatus.pending =>
        job.attempts > 0
            ? UniversalMediaTaskPhase.polling
            : UniversalMediaTaskPhase.pending,
      UniversalMediaJobStatus.completed => UniversalMediaTaskPhase.completed,
      UniversalMediaJobStatus.failed => UniversalMediaTaskPhase.failed,
      UniversalMediaJobStatus.expired => UniversalMediaTaskPhase.expired,
      UniversalMediaJobStatus.cancelled => UniversalMediaTaskPhase.cancelled,
    };
    state = UniversalMediaTaskState(
      operationId: current.operationId,
      kind: current.kind,
      phase: phase,
      job: job,
      error: job.error,
    );
  }

  void markSaving() {
    final current = state;
    if (current == null) return;
    state = UniversalMediaTaskState(
      operationId: current.operationId,
      kind: current.kind,
      phase: UniversalMediaTaskPhase.saving,
      job: current.job,
    );
  }

  void markFailed(String error, {UniversalMediaJob? job}) {
    final current = state;
    if (current == null) return;
    state = UniversalMediaTaskState(
      operationId: current.operationId,
      kind: current.kind,
      phase: UniversalMediaTaskPhase.failed,
      job: job ?? current.job,
      error: sanitizeUniversalMediaDiagnostic(error) ?? '媒体任务执行失败',
    );
  }

  void markCancelled({UniversalMediaJob? job}) {
    final current = state;
    if (current == null) return;
    state = UniversalMediaTaskState(
      operationId: current.operationId,
      kind: current.kind,
      phase: UniversalMediaTaskPhase.cancelled,
      job: job ?? current.job,
      error: '请求已取消',
    );
  }
}

/// 媒体任务的 Riverpod 状态镜像。
///
/// SQLite 是启动恢复和状态迁移的事实来源；内存 map 只作为当前进程的快速
/// 读模型。旧调用方仍可使用 [restoreRecovery]，但该接口不会替代数据库恢复。
final universalMediaJobsProvider =
    StateNotifierProvider<
      UniversalMediaJobNotifier,
      Map<String, UniversalMediaJob>
    >((ref) {
      final notifier = UniversalMediaJobNotifier(
        mediaJobDao: ref.read(databaseProvider).mediaJobDao,
      );
      return notifier;
    });

/// 单数别名，方便只维护一个任务的调用方使用。
final universalMediaJobProvider = universalMediaJobsProvider;

class UniversalMediaJobNotifier
    extends StateNotifier<Map<String, UniversalMediaJob>> {
  UniversalMediaJobNotifier({
    media_database.MediaJobDao? mediaJobDao,
    this.leaseHeartbeatInterval = const Duration(seconds: 30),
  }) : _mediaJobDao = mediaJobDao,
       super(const <String, UniversalMediaJob>{}) {
    if (leaseHeartbeatInterval <= Duration.zero) {
      throw ArgumentError.value(
        leaseHeartbeatInterval,
        'leaseHeartbeatInterval',
        '必须大于 0',
      );
    }
    ready = _restoreFromDatabase();
  }

  final media_database.MediaJobDao? _mediaJobDao;
  final Duration leaseHeartbeatInterval;

  /// 数据库恢复完成后再由调用方开始依赖 pending 任务列表。
  ///
  /// 没有传入 DAO 时保留旧的纯内存构造方式，供不需要持久化的单元测试和
  /// 兼容调用方使用；正式 Riverpod provider 总是注入 AppDatabase DAO。
  late final Future<void> ready;

  final Map<String, _ActiveUniversalMediaOperation> _activeOperations = {};
  final Map<String, _UniversalMediaJobContext> _contexts = {};
  final Map<String, String> _deliveryLeases = {};

  List<UniversalMediaJob> get pendingJobs =>
      _byStatus(UniversalMediaJobStatus.pending);

  List<UniversalMediaJob> get completedJobs =>
      _byStatus(UniversalMediaJobStatus.completed);

  List<UniversalMediaJob> get failedJobs =>
      _byStatus(UniversalMediaJobStatus.failed);

  List<UniversalMediaJob> get expiredJobs =>
      _byStatus(UniversalMediaJobStatus.expired);

  List<UniversalMediaJob> get cancelledJobs =>
      _byStatus(UniversalMediaJobStatus.cancelled);

  Future<void> upsert(
    UniversalMediaJob job, {
    String? sessionId,
    String? provider,
    String? model,
    String? endpoint,
    String? prompt,
    DateTime? deadline,
    String? phase,
    int? progress,
    String? requestUrl,
    String? assetPath,
    String? leaseId,
    String? channelModelId,
    String? deliveryUserMessageId,
    String? deliveryAssistantMessageId,
    String? deliveryAttachmentId,
    String? deliverySourceAttachmentId,
    String? deliveryPhase,
    String? deliveryUserContent,
    String? deliveryAssistantContent,
    String? deliveryFileType,
    String? deliverySourcePath,
    String? deliverySourceFileName,
    String? deliverySourceFileType,
    String? statusOverride,
    String? phaseOverride,
    bool requirePersistedStatus = false,
  }) async {
    final enriched = _withContext(
      job,
      sessionId: sessionId,
      provider: provider,
      model: model,
      endpoint: endpoint,
      prompt: prompt,
      deadline: deadline,
      phase: phase,
      progress: progress,
      requestUrl: requestUrl,
      assetPath: assetPath,
      channelModelId: channelModelId,
      deliveryUserMessageId: deliveryUserMessageId,
      deliveryAssistantMessageId: deliveryAssistantMessageId,
      deliveryAttachmentId: deliveryAttachmentId,
      deliverySourceAttachmentId: deliverySourceAttachmentId,
      deliveryPhase: deliveryPhase,
      deliveryUserContent: deliveryUserContent,
      deliveryAssistantContent: deliveryAssistantContent,
      deliveryFileType: deliveryFileType,
      deliverySourcePath: deliverySourcePath,
      deliverySourceFileName: deliverySourceFileName,
      deliverySourceFileType: deliverySourceFileType,
    );
    if (_mediaJobDao == null) {
      // Preserve the legacy in-memory notifier's synchronous read model for
      // callers that do not await an otherwise asynchronous upsert.
      _setState(enriched);
      return;
    }
    final persisted = await _persist(
      enriched,
      leaseId: leaseId,
      statusOverride: statusOverride,
      phaseOverride: phaseOverride,
      requirePersistedStatus: requirePersistedStatus,
    );
    final expectedPersistedStatus =
        statusOverride ?? _databaseStatus(enriched.status);
    if (persisted != null && persisted.status != expectedPersistedStatus) {
      // DAO 返回的是原子条件 UPDATE 后的权威行。不要把被拒绝的旧状态
      // 写回内存，否则 UI 会看到并不存在的 terminal 成功。
      final authoritative = _jobFromRow(persisted);
      _rememberContext(persisted, authoritative);
      _setState(authoritative, allowTerminalDowngrade: true);
    } else {
      _setState(enriched);
    }
  }

  Future<void> track(UniversalMediaJob job) => upsert(job);

  UniversalMediaJob? find(String id) => state[id];

  /// 只导出恢复所需的任务元数据，不包含媒体二进制。
  List<Map<String, dynamic>> get recoverySnapshots =>
      state.values.map((job) => job.toRecoveryJson()).toList(growable: false);

  /// 从调用方提供的快照恢复内存状态；这不是自动持久化或后台续跑。
  void restoreRecovery(Iterable<Map<String, dynamic>> snapshots) {
    final restored = <String, UniversalMediaJob>{...state};
    for (final snapshot in snapshots) {
      try {
        final job = UniversalMediaJob.fromRecoveryJson(snapshot);
        if (!restored.containsKey(job.id)) restored[job.id] = job;
      } on FormatException {
        // 忽略损坏快照，保留其它任务。
      }
    }
    state = Map<String, UniversalMediaJob>.unmodifiable(restored);
  }

  /// 从 SQLite 重新加载 pending/running 任务。SharedPreferences / 旧快照
  /// 仍可通过 [restoreRecovery] 注入，但不会参与正式启动恢复链路。
  Future<void> restoreFromDatabase() => _restoreFromDatabase();

  /// 兼容调用方使用的简短恢复入口。
  Future<void> restore() => restoreFromDatabase();

  /// 恢复一个任务的最新数据库状态，并在 deadline 已过时原子标记 expired。
  Future<UniversalMediaJob?> restoreJob(String id) async {
    final dao = _mediaJobDao;
    if (dao == null) return find(id);
    var row = await dao.getJob(id);
    if (row == null) return null;
    if (_isExpired(row)) {
      row = await dao.expireJob(row.id, error: '媒体任务已过期') ?? row;
    }
    final job = _jobFromRow(row);
    _rememberContext(row, job);
    _setState(job, allowTerminalDowngrade: true);
    return job;
  }

  /// 恢复后抢占任务并继续有限轮询；如果另一个 worker 已经 claim，则
  /// 返回 null，不会发生重复轮询。
  Future<UniversalMediaJobResult?> restoreAndPoll({
    required String operationId,
    required UniversalMediaService service,
    CancelToken? cancelToken,
    UniversalMediaPollingOptions? pollingOptions,
    String? leaseId,
  }) async {
    final job = await restoreJob(operationId);
    if (job == null) return null;
    if (job.status.isTerminal) {
      return UniversalMediaJobResult(job: job, asset: job.asset);
    }
    final dao = _mediaJobDao;
    if (dao != null) {
      final claimed = leaseId == null
          ? await dao.claimJob(job.id)
          : await _useExistingLease(job.id, leaseId);
      if (claimed == null || claimed.leaseId == null) return null;
      final claimedJob = _jobFromRow(claimed);
      _rememberContext(claimed, claimedJob);
      _setState(claimedJob, allowTerminalDowngrade: true);
      _deliveryLeases[operationId] = claimed.leaseId!;
      final result = await waitFor(
        service: service,
        job: claimedJob,
        cancelToken: cancelToken,
        pollingOptions: pollingOptions,
        leaseId: claimed.leaseId,
      );
      if (result.job.status != UniversalMediaJobStatus.completed) {
        _deliveryLeases.remove(operationId);
      }
      return result;
    }
    return waitFor(
      service: service,
      job: job,
      cancelToken: cancelToken,
      pollingOptions: pollingOptions,
    );
  }

  Future<database.MediaJob?> _useExistingLease(
    String operationId,
    String leaseId,
  ) async {
    final dao = _mediaJobDao;
    if (dao == null) return null;
    final row = await dao.getJob(operationId);
    if (row == null ||
        row.status != media_database.mediaJobRunningStatus ||
        row.leaseId != leaseId) {
      return null;
    }
    return row;
  }

  /// 将 failed/expired/cancelled 任务显式恢复为 pending。
  Future<UniversalMediaJob?> retry(
    String operationId, {
    DateTime? deadline,
  }) async {
    final dao = _mediaJobDao;
    if (dao == null) return find(operationId);
    final row = await dao.retryJob(
      operationId,
      deadline: deadline?.millisecondsSinceEpoch,
    );
    if (row == null) return null;
    final job = _jobFromRow(row);
    _rememberContext(row, job);
    _setState(job, allowTerminalDowngrade: true);
    return job;
  }

  /// 持久化“正在交付”阶段及其所有幂等键。调用方随后才可以写文件和
  /// 会话事务；该方法不会把任务标记为 completed。
  Future<database.MediaJob?> prepareDelivery({
    required String operationId,
    required UniversalMediaJob job,
    required UniversalMediaAsset asset,
    required String assetPath,
    required String userContent,
    required String assistantContent,
    required String fileType,
    String? sourcePath,
    String? sourceFileName,
    String? sourceFileType,
    String deliveryPhase = media_database.mediaJobDeliverySavingPhase,
  }) async {
    final dao = _mediaJobDao;
    if (dao == null) return null;
    final current = await dao.getJob(job.id);
    if (current == null) return null;
    final ids = UniversalMediaDeliveryIds.fromDatabaseRow(current);
    final leaseId = _deliveryLeases[operationId] ?? current.leaseId;
    if (leaseId == null) {
      throw UniversalMediaLeaseLostException(job.id);
    }
    final updated = await dao.updateDeliveryPlan(
      job.id,
      deliveryPhase: deliveryPhase,
      assetPath: assetPath,
      assetMime: asset.mimeType,
      assetExtension: asset.extension,
      deliveryUserMessageId: ids.userMessageId,
      deliveryAssistantMessageId: ids.assistantMessageId,
      deliveryAttachmentId: ids.attachmentId,
      deliverySourceAttachmentId: ids.sourceAttachmentId,
      deliveryUserContent: userContent,
      deliveryAssistantContent: assistantContent,
      deliveryFileType: fileType,
      deliverySourcePath: sourcePath,
      deliverySourceFileName: sourceFileName,
      deliverySourceFileType: sourceFileType,
      leaseId: leaseId,
    );
    if (updated == null ||
        updated.status != media_database.mediaJobRunningStatus ||
        updated.leaseId != leaseId) {
      throw UniversalMediaLeaseLostException(job.id);
    }
    _rememberContext(updated, _jobFromRow(updated));
    _setState(_jobFromRow(updated), allowTerminalDowngrade: true);
    return updated;
  }

  /// 写入失败时把 saving 任务收敛为可显式 retry 的 failed，避免启动恢复
  /// 每次都无界重复下载。
  Future<database.MediaJob?> failDelivery(
    String operationId, {
    required String error,
  }) async {
    final dao = _mediaJobDao;
    if (dao == null) return null;
    final row = await dao.getJob(operationId);
    if (row == null) return null;
    final result = await dao.failJob(
      operationId,
      error: error,
      leaseId: _deliveryLeases[operationId] ?? row.leaseId,
    );
    if (result?.status == media_database.mediaJobFailedStatus) {
      _deliveryLeases.remove(operationId);
      final job = _jobFromRow(result!);
      _rememberContext(result, job);
      _setState(job, allowTerminalDowngrade: true);
    }
    return result;
  }

  /// 交付事务提交后释放进程内 lease 缓存。数据库中的 terminal 状态仍是
  /// 唯一事实来源。
  void releaseDeliveryLease(String operationId) {
    _deliveryLeases.remove(operationId);
  }

  /// 没有活跃 HTTP 操作时也可以取消已恢复任务。
  Future<UniversalMediaJob?> cancelPersisted(String operationId) async {
    final dao = _mediaJobDao;
    if (dao == null) return find(operationId);
    final row = await dao.cancelJob(operationId);
    if (row == null || row.status != media_database.mediaJobCancelledStatus) {
      return null;
    }
    final job = _jobFromRow(row);
    _rememberContext(row, job);
    _setState(job);
    return job;
  }

  Future<List<UniversalMediaJob>> listBySession(String sessionId) async {
    final dao = _mediaJobDao;
    if (dao == null) {
      return state.values
          .where((job) => _contextFor(job).sessionId == sessionId)
          .toList(growable: false);
    }
    final rows = await dao.listJobsBySession(sessionId);
    final jobs = <UniversalMediaJob>[];
    for (final row in rows) {
      final job = _jobFromRow(row);
      _rememberContext(row, job);
      _setState(job);
      jobs.add(job);
    }
    return jobs;
  }

  void remove(String id) {
    if (!state.containsKey(id)) return;
    final next = <String, UniversalMediaJob>{...state}..remove(id);
    state = next;
  }

  void clear() => state = const <String, UniversalMediaJob>{};

  Future<void> deletePersisted(String id) async {
    await _mediaJobDao?.deleteJob(id);
    _contexts.remove(id);
    remove(id);
  }

  Future<void> markPending(UniversalMediaJob job) {
    return upsert(
      _withStatus(job, UniversalMediaJobStatus.pending),
      phase: 'pending',
    );
  }

  Future<void> markCompleted(
    UniversalMediaJob job,
    UniversalMediaAsset asset, {
    String? assetPath,
  }) {
    return upsert(
      _withStatus(
        job,
        UniversalMediaJobStatus.completed,
        asset: asset,
        error: null,
      ),
      phase: 'completed',
      progress: 100,
      assetPath: assetPath,
    );
  }

  Future<void> markFailed(UniversalMediaJob job, {String? error}) {
    return upsert(
      _withStatus(
        job,
        UniversalMediaJobStatus.failed,
        error: error ?? job.error ?? '媒体任务失败',
      ),
      phase: 'failed',
    );
  }

  Future<void> markExpired(UniversalMediaJob job, {String? error}) {
    return upsert(
      _withStatus(
        job,
        UniversalMediaJobStatus.expired,
        error: error ?? job.error ?? '媒体任务已过期',
      ),
      phase: 'expired',
    );
  }

  Future<void> markCancelled(UniversalMediaJob job) {
    return upsert(
      _withStatus(job, UniversalMediaJobStatus.cancelled, error: '请求已取消'),
      phase: 'cancelled',
    );
  }

  Future<void> markSaving(UniversalMediaJob job) async {
    _setState(_withContext(job, phase: 'saving'));
    await _persist(
      job,
      statusOverride: media_database.mediaJobRunningStatus,
      phaseOverride: media_database.mediaJobDeliverySavingPhase,
      leaseId: _deliveryLeases[job.id],
    );
  }

  /// Provider 级 submit 包装：成功得到的 pending / completed / failed
  /// 状态都会先写入内存表，再由调用方决定是否继续轮询。
  Future<UniversalMediaJobResult> submit({
    String? operationId,
    required UniversalMediaService service,
    required UniversalMediaKind kind,
    required String model,
    required String prompt,
    String? endpoint,
    String? referenceImagePath,
    CancelToken? cancelToken,
    UniversalMediaEndpointStyle endpointStyle =
        UniversalMediaEndpointStyle.auto,
    Map<String, dynamic> extra = const <String, dynamic>{},
    UniversalMediaTaskOptions taskOptions = const UniversalMediaTaskOptions(),
    String? sessionId,
    String? provider,
    DateTime? deadline,
    String? channelModelId,
    String? deliveryUserContent,
    String? deliveryAssistantContent,
    String? deliveryFileType,
  }) async {
    final result = await service.submit(
      kind: kind,
      model: model,
      prompt: prompt,
      endpoint: endpoint,
      referenceImagePath: referenceImagePath,
      cancelToken: cancelToken,
      endpointStyle: endpointStyle,
      extra: extra,
      taskOptions: taskOptions,
    );
    final job = _withContext(
      _withOperationId(result.job, operationId),
      sessionId: sessionId,
      provider: provider ?? _providerForService(service),
      model: model,
      endpoint: endpoint ?? _defaultEndpoint(kind),
      prompt: prompt,
      deadline: deadline ?? DateTime.now().add(service.pollingOptions.deadline),
      phase: result.job.status == UniversalMediaJobStatus.pending
          ? 'pending'
          : result.job.status == UniversalMediaJobStatus.completed
          ? media_database.mediaJobDeliverySavingPhase
          : result.job.status.name,
      channelModelId: channelModelId,
      deliveryUserContent: deliveryUserContent,
      deliveryAssistantContent: deliveryAssistantContent,
      deliveryFileType: deliveryFileType,
    );
    final persistAsDeliveryPending =
        result.job.status == UniversalMediaJobStatus.completed;
    await upsert(
      job,
      // Pending submission is allowed to observe an already-running row;
      // run() performs the decisive owner claim immediately afterwards.
      requirePersistedStatus: result.job.status.isTerminal,
      statusOverride: persistAsDeliveryPending
          ? media_database.mediaJobRunningStatus
          : null,
      phaseOverride: persistAsDeliveryPending
          ? media_database.mediaJobDeliverySavingPhase
          : null,
    );
    return UniversalMediaJobResult(job: job, asset: result.asset);
  }

  Future<UniversalMediaJobResult> run({
    required String operationId,
    required UniversalMediaService service,
    required UniversalMediaKind kind,
    required String model,
    required String prompt,
    String? endpoint,
    String? referenceImagePath,
    Map<String, dynamic> extra = const <String, dynamic>{},
    UniversalMediaEndpointStyle endpointStyle =
        UniversalMediaEndpointStyle.auto,
    UniversalMediaTaskOptions taskOptions = const UniversalMediaTaskOptions(),
    void Function(UniversalMediaJob job)? onJobUpdate,
    String? sessionId,
    String? provider,
    DateTime? deadline,
    String? channelModelId,
    String? deliveryUserContent,
    String? deliveryAssistantContent,
    String? deliveryFileType,
  }) async {
    final operation = _ActiveUniversalMediaOperation(
      service: service,
      cancelToken: CancelToken(),
    );
    _activeOperations[operationId] = operation;
    try {
      final effectiveDeadline =
          deadline ?? DateTime.now().add(service.pollingOptions.deadline);
      final ids = UniversalMediaDeliveryIds.forOperationId(operationId);
      final initialJob = UniversalMediaJob(
        id: operationId,
        kind: kind,
        status: UniversalMediaJobStatus.pending,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        metadata: const <String, dynamic>{},
      );
      await upsert(
        initialJob,
        sessionId: sessionId,
        provider: provider ?? _providerForService(service),
        model: model,
        endpoint: endpoint ?? _defaultEndpoint(kind),
        prompt: prompt,
        deadline: effectiveDeadline,
        phase: 'submitting',
        channelModelId: channelModelId,
        deliveryUserMessageId: ids.userMessageId,
        deliveryAssistantMessageId: ids.assistantMessageId,
        deliveryAttachmentId: ids.attachmentId,
        deliverySourceAttachmentId: ids.sourceAttachmentId,
        deliveryPhase: media_database.mediaJobDeliveryPlannedPhase,
        deliveryUserContent: deliveryUserContent,
        deliveryAssistantContent: deliveryAssistantContent,
        deliveryFileType: deliveryFileType,
      );
      operation.job = initialJob;
      final submitted = await submit(
        operationId: operationId,
        service: service,
        kind: kind,
        model: model,
        prompt: prompt,
        endpoint: endpoint,
        referenceImagePath: referenceImagePath,
        cancelToken: operation.cancelToken,
        endpointStyle: endpointStyle,
        extra: extra,
        taskOptions: taskOptions,
        sessionId: sessionId,
        provider: provider,
        deadline: effectiveDeadline,
        channelModelId: channelModelId,
        deliveryUserContent: deliveryUserContent,
        deliveryAssistantContent: deliveryAssistantContent,
        deliveryFileType: deliveryFileType,
      );
      operation.job = submitted.job;
      onJobUpdate?.call(submitted.job);
      if (submitted.job.status == UniversalMediaJobStatus.failed ||
          submitted.job.status == UniversalMediaJobStatus.expired ||
          submitted.job.status == UniversalMediaJobStatus.cancelled) {
        return submitted;
      }
      final dao = _mediaJobDao;
      var claimedJob = submitted.job;
      String? leaseId;
      if (dao != null) {
        final claimed = await _claimPersisted(
          submitted.job.id,
          allowUnleasedRunning:
              submitted.job.status == UniversalMediaJobStatus.completed,
        );
        if (claimed == null || claimed.leaseId == null) {
          throw UniversalMediaClaimException(operationId);
        }
        leaseId = claimed.leaseId;
        claimedJob = _jobFromRow(claimed);
        _rememberContext(claimed, claimedJob);
        _setState(claimedJob, allowTerminalDowngrade: true);
      }
      operation.leaseId = leaseId;
      operation.job = claimedJob;
      if (submitted.job.status == UniversalMediaJobStatus.completed) {
        if (leaseId == null) return submitted;
        _deliveryLeases[operationId] = leaseId;
        final persisted = await _persist(
          submitted.job,
          statusOverride: media_database.mediaJobRunningStatus,
          phaseOverride: media_database.mediaJobDeliverySavingPhase,
          leaseId: leaseId,
        );
        if (persisted?.status != media_database.mediaJobRunningStatus ||
            persisted?.leaseId != leaseId) {
          throw UniversalMediaLeaseLostException(operationId);
        }
        return submitted;
      }
      final result = await waitFor(
        service: service,
        job: claimedJob,
        cancelToken: operation.cancelToken,
        leaseId: leaseId,
      );
      operation.job = result.job;
      onJobUpdate?.call(result.job);
      return result;
    } on UniversalMediaCancelledException {
      final job = operation.job;
      if (job != null) {
        final cancelled = _withStatus(
          job,
          UniversalMediaJobStatus.cancelled,
          error: '请求已取消',
        );
        await upsert(cancelled, leaseId: operation.leaseId);
        onJobUpdate?.call(cancelled);
      }
      rethrow;
    } catch (error) {
      final job = operation.job;
      final dao = _mediaJobDao;
      if (job != null && dao != null) {
        final row = await dao.getJob(job.id);
        if (row != null &&
            (row.status == media_database.mediaJobPendingStatus ||
                (row.status == media_database.mediaJobRunningStatus &&
                    row.leaseId == operation.leaseId))) {
          final failed = await dao.failJob(
            job.id,
            error: _failureText(error),
            leaseId: operation.leaseId,
          );
          if (failed?.status == media_database.mediaJobFailedStatus) {
            _deliveryLeases.remove(operationId);
          }
        }
      }
      rethrow;
    } finally {
      if (identical(_activeOperations[operationId], operation)) {
        _activeOperations.remove(operationId);
      }
    }
  }

  static String _failureText(Object error) {
    return sanitizeUniversalMediaDiagnostic(error) ?? '媒体任务执行失败';
  }

  /// 先中止本地 submit/poll，再尽力向服务端发送取消请求。即使服务端没有
  /// cancel URL，调用方也会得到明确的本地 cancelled 状态，不会写入媒体消息。
  Future<void> cancelActive(String operationId) async {
    final operation = _activeOperations[operationId];
    if (operation == null) {
      await cancelPersisted(operationId);
      return;
    }
    operation.cancelToken.cancel('用户取消');
    final job = operation.job;
    if (job == null || job.status.isTerminal) return;
    try {
      final result = await operation.service.cancelJob(job);
      operation.job = result.job;
      await upsert(result.job, leaseId: operation.leaseId);
    } catch (error) {
      if (error is UniversalMediaLeaseLostException) rethrow;
      final cancelled = _withStatus(
        job,
        UniversalMediaJobStatus.cancelled,
        error: '请求已取消',
      );
      operation.job = cancelled;
      await upsert(cancelled, leaseId: operation.leaseId);
    }
  }

  Future<UniversalMediaJobResult> waitFor({
    required UniversalMediaService service,
    required UniversalMediaJob job,
    CancelToken? cancelToken,
    UniversalMediaPollingOptions? pollingOptions,
    String? leaseId,
  }) async {
    final dao = _mediaJobDao;
    var effectiveJob = job;
    var effectiveLeaseId = leaseId;
    if (dao != null &&
        !effectiveJob.status.isTerminal &&
        effectiveLeaseId == null) {
      final claimed = await _claimPersisted(effectiveJob.id);
      if (claimed == null || claimed.leaseId == null) {
        throw UniversalMediaClaimException(effectiveJob.id);
      }
      effectiveLeaseId = claimed.leaseId;
      effectiveJob = _jobFromRow(claimed);
      _rememberContext(claimed, effectiveJob);
      _setState(effectiveJob, allowTerminalDowngrade: true);
    }
    final effectiveCancelToken =
        cancelToken ?? (effectiveLeaseId == null ? null : CancelToken());
    final heartbeat = dao == null || effectiveLeaseId == null
        ? null
        : _UniversalMediaLeaseHeartbeat(
            dao: dao,
            jobId: effectiveJob.id,
            leaseId: effectiveLeaseId,
            interval: leaseHeartbeatInterval,
            cancelToken: effectiveCancelToken!,
          );
    heartbeat?.start();
    try {
      final result = await service.waitForJob(
        effectiveJob,
        cancelToken: effectiveCancelToken,
        pollingOptions: pollingOptions,
      );
      if (heartbeat?.isLost == true) throw heartbeat!.failure!;
      final statusOverride =
          result.job.status == UniversalMediaJobStatus.pending ||
              result.job.status == UniversalMediaJobStatus.completed
          ? 'running'
          : null;
      final phaseOverride = result.job.status == UniversalMediaJobStatus.pending
          ? 'polling'
          : result.job.status == UniversalMediaJobStatus.completed
          ? media_database.mediaJobDeliverySavingPhase
          : result.job.status.name;
      final persisted = await _persist(
        result.job,
        statusOverride: statusOverride,
        phaseOverride: phaseOverride,
        leaseId: effectiveLeaseId,
      );
      if (heartbeat?.isLost == true) throw heartbeat!.failure!;
      final expectedStatus =
          statusOverride ?? _databaseStatus(result.job.status);
      if (persisted != null && persisted.status != expectedStatus) {
        final authoritative = _jobFromRow(persisted);
        _rememberContext(persisted, authoritative);
        _setState(authoritative, allowTerminalDowngrade: true);
        return UniversalMediaJobResult(
          job: authoritative,
          asset: authoritative.status == result.job.status
              ? result.asset
              : null,
        );
      }
      final next = _withContext(result.job, phase: phaseOverride);
      _setState(next);
      if (result.job.status == UniversalMediaJobStatus.completed &&
          effectiveLeaseId != null &&
          effectiveJob.id.isNotEmpty) {
        // Keep the lease until the session/file delivery transaction has
        // committed. A completed provider response is not a completed local
        // operation yet.
        _deliveryLeases[effectiveJob.id] = effectiveLeaseId;
      }
      return result;
    } on UniversalMediaCancelledException {
      if (heartbeat?.isLost == true) throw heartbeat!.failure!;
      final cancelled = _withStatus(
        effectiveJob,
        UniversalMediaJobStatus.cancelled,
        error: '请求已取消',
      );
      final persisted = await _persist(
        cancelled,
        phaseOverride: 'cancelled',
        leaseId: effectiveLeaseId,
      );
      if (persisted != null &&
          persisted.status != media_database.mediaJobCancelledStatus) {
        final authoritative = _jobFromRow(persisted);
        _rememberContext(persisted, authoritative);
        _setState(authoritative, allowTerminalDowngrade: true);
      } else {
        _setState(cancelled);
      }
      rethrow;
    } finally {
      await heartbeat?.stop();
    }
  }

  Future<UniversalMediaJobResult> cancel({
    required UniversalMediaService service,
    required UniversalMediaJob job,
    CancelToken? cancelToken,
  }) async {
    final result = await service.cancelJob(job, cancelToken: cancelToken);
    await upsert(result.job, phase: 'cancelled');
    return result;
  }

  List<UniversalMediaJob> _byStatus(UniversalMediaJobStatus status) =>
      state.values.where((job) => job.status == status).toList(growable: false);

  Future<void> _restoreFromDatabase() async {
    final dao = _mediaJobDao;
    if (dao == null) return;
    try {
      final rows = await dao.listRecoverableJobs();
      final restored = <String, UniversalMediaJob>{...state};
      for (var row in rows) {
        if (_isExpired(row)) {
          row = await dao.expireJob(row.id, error: '媒体任务已过期') ?? row;
        }
        final job = _jobFromRow(row);
        _rememberContext(row, job);
        final current = restored[job.id];
        if (current == null) {
          restored[job.id] = job;
        }
      }
      state = Map<String, UniversalMediaJob>.unmodifiable(restored);
    } catch (_) {
      // 数据库暂时不可用时保留当前进程内状态；下一次 ready/restore 会重试。
    }
  }

  bool _isExpired(database.MediaJob row) {
    final deadline = row.deadline;
    return deadline != null &&
        deadline <= DateTime.now().millisecondsSinceEpoch;
  }

  Future<database.MediaJob?> _claimPersisted(
    String id, {
    bool allowUnleasedRunning = false,
  }) async {
    final dao = _mediaJobDao;
    if (dao == null) return null;
    try {
      return await dao.claimJob(id, allowUnleasedRunning: allowUnleasedRunning);
    } catch (_) {
      // 数据库异常同样是 claim 失败；绝不能在未持有 owner 时继续轮询。
      throw UniversalMediaClaimException(id);
    }
  }

  UniversalMediaJob _jobFromRow(database.MediaJob row) {
    final status = _statusFromDatabase(row.status);
    final metadata = <String, dynamic>{
      if (row.requestUrl != null) 'submit_url': row.requestUrl,
      if (row.sessionId != null) _mediaSessionIdKey: row.sessionId,
      if (row.provider != null) _mediaProviderKey: row.provider,
      if (row.model != null) _mediaModelKey: row.model,
      if (row.endpoint != null) _mediaEndpointKey: row.endpoint,
      if (row.prompt != null) _mediaPromptKey: row.prompt,
      if (row.deadline != null) _mediaDeadlineKey: row.deadline,
      if (row.phase != null) _mediaPhaseKey: row.phase,
      if (row.progress != null) _mediaProgressKey: row.progress,
      if (row.assetPath != null) _mediaAssetPathKey: row.assetPath,
      if (row.assetMime != null) _mediaAssetMimeKey: row.assetMime,
      if (row.assetExtension != null)
        _mediaAssetExtensionKey: row.assetExtension,
      if (row.channelModelId != null)
        _mediaChannelModelIdKey: row.channelModelId,
      if (row.deliveryUserMessageId != null)
        _mediaDeliveryUserMessageIdKey: row.deliveryUserMessageId,
      if (row.deliveryAssistantMessageId != null)
        _mediaDeliveryAssistantMessageIdKey: row.deliveryAssistantMessageId,
      if (row.deliveryAttachmentId != null)
        _mediaDeliveryAttachmentIdKey: row.deliveryAttachmentId,
      if (row.deliverySourceAttachmentId != null)
        _mediaDeliverySourceAttachmentIdKey: row.deliverySourceAttachmentId,
      if (row.deliveryPhase != null) _mediaDeliveryPhaseKey: row.deliveryPhase,
      if (row.deliveryUserContent != null)
        _mediaDeliveryUserContentKey: row.deliveryUserContent,
      if (row.deliveryAssistantContent != null)
        _mediaDeliveryAssistantContentKey: row.deliveryAssistantContent,
      if (row.deliveryFileType != null)
        _mediaDeliveryFileTypeKey: row.deliveryFileType,
      if (row.deliverySourcePath != null)
        _mediaDeliverySourcePathKey: row.deliverySourcePath,
      if (row.deliverySourceFileName != null)
        _mediaDeliverySourceFileNameKey: row.deliverySourceFileName,
      if (row.deliverySourceFileType != null)
        _mediaDeliverySourceFileTypeKey: row.deliverySourceFileType,
    };
    return UniversalMediaJob(
      id: row.id,
      kind: _kindFromDatabase(row.kind),
      status: status,
      jobId: row.providerJobId,
      requestId: row.requestId,
      pollUrl: _httpUri(row.pollUrl),
      cancelUrl: _httpUri(row.cancelUrl),
      contentUrl: _httpUri(row.contentUrl),
      createdAt: _dateFromMillis(row.createdAt),
      updatedAt: _dateFromMillis(row.updatedAt),
      attempts: row.attempts,
      error: row.error,
      endpointStyle: _endpointStyleFromDatabase(row.endpointStyle),
      metadata: metadata,
    );
  }

  void _rememberContext(database.MediaJob row, UniversalMediaJob job) {
    _contexts[row.id] = _UniversalMediaJobContext(
      sessionId: row.sessionId,
      provider: row.provider,
      model: row.model,
      endpoint: row.endpoint,
      prompt: row.prompt,
      deadline: row.deadline == null ? null : _dateFromMillis(row.deadline!),
      phase: row.phase,
      progress: row.progress,
      requestUrl: row.requestUrl,
      assetPath: row.assetPath,
      assetMime: row.assetMime,
      assetExtension: row.assetExtension,
      channelModelId: row.channelModelId,
      deliveryUserMessageId: row.deliveryUserMessageId,
      deliveryAssistantMessageId: row.deliveryAssistantMessageId,
      deliveryAttachmentId: row.deliveryAttachmentId,
      deliverySourceAttachmentId: row.deliverySourceAttachmentId,
      deliveryPhase: row.deliveryPhase,
      deliveryUserContent: row.deliveryUserContent,
      deliveryAssistantContent: row.deliveryAssistantContent,
      deliveryFileType: row.deliveryFileType,
      deliverySourcePath: row.deliverySourcePath,
      deliverySourceFileName: row.deliverySourceFileName,
      deliverySourceFileType: row.deliverySourceFileType,
    );
  }

  _UniversalMediaJobContext _contextFor(UniversalMediaJob job) {
    final remembered = _contexts[job.id];
    if (remembered != null) return remembered;
    return _UniversalMediaJobContext(
      sessionId: _metaString(job, _mediaSessionIdKey),
      provider: _metaString(job, _mediaProviderKey),
      model: _metaString(job, _mediaModelKey),
      endpoint: _metaString(job, _mediaEndpointKey),
      prompt: _metaString(job, _mediaPromptKey),
      deadline: _metaDate(job, _mediaDeadlineKey),
      phase: _metaString(job, _mediaPhaseKey),
      progress: _metaInt(job, _mediaProgressKey),
      requestUrl:
          _metaString(job, _mediaRequestUrlKey) ??
          _metaString(job, 'submit_url'),
      assetPath: _metaString(job, _mediaAssetPathKey),
      assetMime: _metaString(job, _mediaAssetMimeKey),
      assetExtension: _metaString(job, _mediaAssetExtensionKey),
      channelModelId: _metaString(job, _mediaChannelModelIdKey),
      deliveryUserMessageId: _metaString(job, _mediaDeliveryUserMessageIdKey),
      deliveryAssistantMessageId: _metaString(
        job,
        _mediaDeliveryAssistantMessageIdKey,
      ),
      deliveryAttachmentId: _metaString(job, _mediaDeliveryAttachmentIdKey),
      deliverySourceAttachmentId: _metaString(
        job,
        _mediaDeliverySourceAttachmentIdKey,
      ),
      deliveryPhase: _metaString(job, _mediaDeliveryPhaseKey),
      deliveryUserContent: _metaString(job, _mediaDeliveryUserContentKey),
      deliveryAssistantContent: _metaString(
        job,
        _mediaDeliveryAssistantContentKey,
      ),
      deliveryFileType: _metaString(job, _mediaDeliveryFileTypeKey),
      deliverySourcePath: _metaString(job, _mediaDeliverySourcePathKey),
      deliverySourceFileName: _metaString(job, _mediaDeliverySourceFileNameKey),
      deliverySourceFileType: _metaString(job, _mediaDeliverySourceFileTypeKey),
    );
  }

  UniversalMediaJob _withContext(
    UniversalMediaJob job, {
    String? sessionId,
    String? provider,
    String? model,
    String? endpoint,
    String? prompt,
    DateTime? deadline,
    String? phase,
    int? progress,
    String? requestUrl,
    String? assetPath,
    String? channelModelId,
    String? deliveryUserMessageId,
    String? deliveryAssistantMessageId,
    String? deliveryAttachmentId,
    String? deliverySourceAttachmentId,
    String? deliveryPhase,
    String? deliveryUserContent,
    String? deliveryAssistantContent,
    String? deliveryFileType,
    String? deliverySourcePath,
    String? deliverySourceFileName,
    String? deliverySourceFileType,
  }) {
    final next = _contextFor(job).copyWith(
      sessionId: sessionId,
      provider: provider,
      model: model,
      endpoint: endpoint,
      prompt: prompt,
      deadline: deadline,
      phase: phase,
      progress: progress,
      requestUrl: requestUrl,
      assetPath: assetPath,
      channelModelId: channelModelId,
      deliveryUserMessageId: deliveryUserMessageId,
      deliveryAssistantMessageId: deliveryAssistantMessageId,
      deliveryAttachmentId: deliveryAttachmentId,
      deliverySourceAttachmentId: deliverySourceAttachmentId,
      deliveryPhase: deliveryPhase,
      deliveryUserContent: deliveryUserContent,
      deliveryAssistantContent: deliveryAssistantContent,
      deliveryFileType: deliveryFileType,
      deliverySourcePath: deliverySourcePath,
      deliverySourceFileName: deliverySourceFileName,
      deliverySourceFileType: deliverySourceFileType,
    );
    _contexts[job.id] = next;
    final metadata = <String, dynamic>{
      ...job.metadata,
      if (next.sessionId != null) _mediaSessionIdKey: next.sessionId,
      if (next.provider != null) _mediaProviderKey: next.provider,
      if (next.model != null) _mediaModelKey: next.model,
      if (next.endpoint != null) _mediaEndpointKey: next.endpoint,
      if (next.prompt != null) _mediaPromptKey: next.prompt,
      if (next.deadline != null)
        _mediaDeadlineKey: next.deadline!.millisecondsSinceEpoch,
      if (next.phase != null) _mediaPhaseKey: next.phase,
      if (next.progress != null) _mediaProgressKey: next.progress,
      if (next.requestUrl != null) _mediaRequestUrlKey: next.requestUrl,
      if (next.assetPath != null) _mediaAssetPathKey: next.assetPath,
      if (next.assetMime != null) _mediaAssetMimeKey: next.assetMime,
      if (next.assetExtension != null)
        _mediaAssetExtensionKey: next.assetExtension,
      if (next.channelModelId != null)
        _mediaChannelModelIdKey: next.channelModelId,
      if (next.deliveryUserMessageId != null)
        _mediaDeliveryUserMessageIdKey: next.deliveryUserMessageId,
      if (next.deliveryAssistantMessageId != null)
        _mediaDeliveryAssistantMessageIdKey: next.deliveryAssistantMessageId,
      if (next.deliveryAttachmentId != null)
        _mediaDeliveryAttachmentIdKey: next.deliveryAttachmentId,
      if (next.deliverySourceAttachmentId != null)
        _mediaDeliverySourceAttachmentIdKey: next.deliverySourceAttachmentId,
      if (next.deliveryPhase != null)
        _mediaDeliveryPhaseKey: next.deliveryPhase,
      if (next.deliveryUserContent != null)
        _mediaDeliveryUserContentKey: next.deliveryUserContent,
      if (next.deliveryAssistantContent != null)
        _mediaDeliveryAssistantContentKey: next.deliveryAssistantContent,
      if (next.deliveryFileType != null)
        _mediaDeliveryFileTypeKey: next.deliveryFileType,
      if (next.deliverySourcePath != null)
        _mediaDeliverySourcePathKey: next.deliverySourcePath,
      if (next.deliverySourceFileName != null)
        _mediaDeliverySourceFileNameKey: next.deliverySourceFileName,
      if (next.deliverySourceFileType != null)
        _mediaDeliverySourceFileTypeKey: next.deliverySourceFileType,
    };
    return job.copyWith(metadata: metadata);
  }

  Future<database.MediaJob?> _persist(
    UniversalMediaJob job, {
    String? statusOverride,
    String? phaseOverride,
    String? leaseId,
    bool requirePersistedStatus = false,
  }) async {
    final dao = _mediaJobDao;
    if (dao == null) return null;
    final context = _contextFor(job).copyWith(
      phase: phaseOverride,
      progress: phaseOverride == 'completed' ? 100 : null,
      assetMime: job.asset?.mimeType,
      assetExtension: job.asset?.extension,
    );
    _contexts[job.id] = context;
    final expectedStatus = statusOverride ?? _databaseStatus(job.status);
    try {
      final persisted = await dao.upsertJob(
        id: job.id,
        sessionId: context.sessionId,
        kind: job.kind.name,
        provider: context.provider,
        model: context.model,
        endpoint: context.endpoint,
        status: expectedStatus,
        progress: context.progress,
        phase: context.phase ?? job.status.name,
        requestUrl: context.requestUrl ?? _metaString(job, 'submit_url'),
        providerJobId: job.jobId,
        requestId: job.requestId,
        pollUrl: job.pollUrl?.toString(),
        cancelUrl: job.cancelUrl?.toString(),
        contentUrl: job.contentUrl?.toString(),
        assetPath: context.assetPath,
        assetMime: context.assetMime,
        assetExtension: context.assetExtension,
        prompt: context.prompt,
        error: job.error,
        attempts: job.attempts,
        createdAt: job.createdAt.millisecondsSinceEpoch,
        updatedAt: job.updatedAt.millisecondsSinceEpoch,
        deadline: context.deadline?.millisecondsSinceEpoch,
        endpointStyle: job.endpointStyle.name,
        leaseId: leaseId,
        channelModelId: context.channelModelId,
        deliveryUserMessageId: context.deliveryUserMessageId,
        deliveryAssistantMessageId: context.deliveryAssistantMessageId,
        deliveryAttachmentId: context.deliveryAttachmentId,
        deliverySourceAttachmentId: context.deliverySourceAttachmentId,
        deliveryPhase: context.deliveryPhase,
        deliveryUserContent: context.deliveryUserContent,
        deliveryAssistantContent: context.deliveryAssistantContent,
        deliveryFileType: context.deliveryFileType,
        deliverySourcePath: context.deliverySourcePath,
        deliverySourceFileName: context.deliverySourceFileName,
        deliverySourceFileType: context.deliverySourceFileType,
      );
      if (leaseId != null) {
        final ownerIsValid =
            expectedStatus == media_database.mediaJobRunningStatus
            ? persisted?.status == media_database.mediaJobRunningStatus &&
                  persisted?.leaseId == leaseId
            : persisted?.status == expectedStatus;
        if (!ownerIsValid) {
          throw UniversalMediaLeaseLostException(job.id);
        }
      }
      if (requirePersistedStatus &&
          (persisted == null || persisted.status != expectedStatus)) {
        throw UniversalMediaStateConflictException(job.id);
      }
      return persisted;
    } on UniversalMediaException {
      rethrow;
    } catch (_) {
      if (leaseId != null) {
        throw UniversalMediaLeaseLostException(job.id);
      }
      if (requirePersistedStatus) {
        throw UniversalMediaStateConflictException(job.id);
      }
      return null;
    }
  }

  void _setState(UniversalMediaJob job, {bool allowTerminalDowngrade = false}) {
    final current = state[job.id];
    if (current != null &&
        current.status.isTerminal &&
        !job.status.isTerminal &&
        !allowTerminalDowngrade) {
      return;
    }
    state = <String, UniversalMediaJob>{...state, job.id: job};
  }

  static UniversalMediaJob _withOperationId(
    UniversalMediaJob job,
    String? operationId,
  ) {
    final id = operationId?.trim();
    return id == null || id.isEmpty || id == job.id
        ? job
        : job.copyWith(id: id);
  }

  static String _databaseStatus(UniversalMediaJobStatus status) {
    return status == UniversalMediaJobStatus.pending
        ? media_database.mediaJobPendingStatus
        : status.name;
  }

  static UniversalMediaJobStatus _statusFromDatabase(String status) {
    return switch (status) {
      media_database.mediaJobCompletedStatus =>
        UniversalMediaJobStatus.completed,
      media_database.mediaJobFailedStatus => UniversalMediaJobStatus.failed,
      media_database.mediaJobExpiredStatus => UniversalMediaJobStatus.expired,
      media_database.mediaJobCancelledStatus =>
        UniversalMediaJobStatus.cancelled,
      _ => UniversalMediaJobStatus.pending,
    };
  }

  static UniversalMediaKind _kindFromDatabase(String kind) {
    return UniversalMediaKind.values.firstWhere(
      (value) => value.name == kind,
      orElse: () => UniversalMediaKind.video,
    );
  }

  static UniversalMediaEndpointStyle _endpointStyleFromDatabase(String? value) {
    return UniversalMediaEndpointStyle.values.firstWhere(
      (style) => style.name == value,
      orElse: () => UniversalMediaEndpointStyle.auto,
    );
  }

  static Uri? _httpUri(String? value) {
    final uri = Uri.tryParse(value ?? '');
    final scheme = uri?.scheme.toLowerCase();
    if (uri == null ||
        uri.host.isEmpty ||
        (scheme != 'http' && scheme != 'https')) {
      return null;
    }
    return uri;
  }

  static DateTime _dateFromMillis(int value) =>
      DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);

  static String? _providerForService(UniversalMediaService service) {
    final uri = Uri.tryParse(service.baseUrl.trim());
    final host = uri?.host.trim();
    return host == null || host.isEmpty ? null : host;
  }

  static String _defaultEndpoint(UniversalMediaKind kind) {
    return switch (kind) {
      UniversalMediaKind.image => kDefaultImageGenerationEndpoint,
      UniversalMediaKind.video => kDefaultVideoGenerationEndpoint,
      UniversalMediaKind.music => kDefaultMusicGenerationEndpoint,
    };
  }

  static String? _metaString(UniversalMediaJob job, String key) {
    final value = job.metadata[key]?.toString().trim();
    return value == null || value.isEmpty ? null : value;
  }

  static int? _metaInt(UniversalMediaJob job, String key) {
    final value = job.metadata[key];
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static DateTime? _metaDate(UniversalMediaJob job, String key) {
    final value = _metaInt(job, key);
    return value == null ? null : _dateFromMillis(value);
  }

  UniversalMediaJob _withStatus(
    UniversalMediaJob job,
    UniversalMediaJobStatus status, {
    UniversalMediaAsset? asset,
    String? error,
  }) {
    return UniversalMediaJob(
      id: job.id,
      kind: job.kind,
      status: status,
      jobId: job.jobId,
      requestId: job.requestId,
      pollUrl: job.pollUrl,
      cancelUrl: job.cancelUrl,
      contentUrl: job.contentUrl,
      createdAt: job.createdAt,
      updatedAt: DateTime.now(),
      attempts: job.attempts,
      error: error,
      asset: asset,
      endpointStyle: job.endpointStyle,
      metadata: job.metadata,
    );
  }
}

const _mediaSessionIdKey = 'media_session_id';
const _mediaProviderKey = 'media_provider';
const _mediaModelKey = 'media_model';
const _mediaEndpointKey = 'media_endpoint';
const _mediaPromptKey = 'media_prompt';
const _mediaDeadlineKey = 'media_deadline';
const _mediaPhaseKey = 'media_phase';
const _mediaProgressKey = 'media_progress';
const _mediaRequestUrlKey = 'media_request_url';
const _mediaAssetPathKey = 'media_asset_path';
const _mediaAssetMimeKey = 'media_asset_mime';
const _mediaAssetExtensionKey = 'media_asset_extension';
const _mediaChannelModelIdKey = 'media_channel_model_id';
const _mediaDeliveryUserMessageIdKey = 'media_delivery_user_message_id';
const _mediaDeliveryAssistantMessageIdKey =
    'media_delivery_assistant_message_id';
const _mediaDeliveryAttachmentIdKey = 'media_delivery_attachment_id';
const _mediaDeliverySourceAttachmentIdKey =
    'media_delivery_source_attachment_id';
const _mediaDeliveryPhaseKey = 'media_delivery_phase';
const _mediaDeliveryUserContentKey = 'media_delivery_user_content';
const _mediaDeliveryAssistantContentKey = 'media_delivery_assistant_content';
const _mediaDeliveryFileTypeKey = 'media_delivery_file_type';
const _mediaDeliverySourcePathKey = 'media_delivery_source_path';
const _mediaDeliverySourceFileNameKey = 'media_delivery_source_file_name';
const _mediaDeliverySourceFileTypeKey = 'media_delivery_source_file_type';

class _UniversalMediaJobContext {
  const _UniversalMediaJobContext({
    this.sessionId,
    this.provider,
    this.model,
    this.endpoint,
    this.prompt,
    this.deadline,
    this.phase,
    this.progress,
    this.requestUrl,
    this.assetPath,
    this.assetMime,
    this.assetExtension,
    this.channelModelId,
    this.deliveryUserMessageId,
    this.deliveryAssistantMessageId,
    this.deliveryAttachmentId,
    this.deliverySourceAttachmentId,
    this.deliveryPhase,
    this.deliveryUserContent,
    this.deliveryAssistantContent,
    this.deliveryFileType,
    this.deliverySourcePath,
    this.deliverySourceFileName,
    this.deliverySourceFileType,
  });

  final String? sessionId;
  final String? provider;
  final String? model;
  final String? endpoint;
  final String? prompt;
  final DateTime? deadline;
  final String? phase;
  final int? progress;
  final String? requestUrl;
  final String? assetPath;
  final String? assetMime;
  final String? assetExtension;
  final String? channelModelId;
  final String? deliveryUserMessageId;
  final String? deliveryAssistantMessageId;
  final String? deliveryAttachmentId;
  final String? deliverySourceAttachmentId;
  final String? deliveryPhase;
  final String? deliveryUserContent;
  final String? deliveryAssistantContent;
  final String? deliveryFileType;
  final String? deliverySourcePath;
  final String? deliverySourceFileName;
  final String? deliverySourceFileType;

  _UniversalMediaJobContext copyWith({
    String? sessionId,
    String? provider,
    String? model,
    String? endpoint,
    String? prompt,
    DateTime? deadline,
    String? phase,
    int? progress,
    String? requestUrl,
    String? assetPath,
    String? assetMime,
    String? assetExtension,
    String? channelModelId,
    String? deliveryUserMessageId,
    String? deliveryAssistantMessageId,
    String? deliveryAttachmentId,
    String? deliverySourceAttachmentId,
    String? deliveryPhase,
    String? deliveryUserContent,
    String? deliveryAssistantContent,
    String? deliveryFileType,
    String? deliverySourcePath,
    String? deliverySourceFileName,
    String? deliverySourceFileType,
  }) {
    return _UniversalMediaJobContext(
      sessionId: sessionId ?? this.sessionId,
      provider: provider ?? this.provider,
      model: model ?? this.model,
      endpoint: endpoint ?? this.endpoint,
      prompt: prompt ?? this.prompt,
      deadline: deadline ?? this.deadline,
      phase: phase ?? this.phase,
      progress: progress ?? this.progress,
      requestUrl: requestUrl ?? this.requestUrl,
      assetPath: assetPath ?? this.assetPath,
      assetMime: assetMime ?? this.assetMime,
      assetExtension: assetExtension ?? this.assetExtension,
      channelModelId: channelModelId ?? this.channelModelId,
      deliveryUserMessageId:
          deliveryUserMessageId ?? this.deliveryUserMessageId,
      deliveryAssistantMessageId:
          deliveryAssistantMessageId ?? this.deliveryAssistantMessageId,
      deliveryAttachmentId: deliveryAttachmentId ?? this.deliveryAttachmentId,
      deliverySourceAttachmentId:
          deliverySourceAttachmentId ?? this.deliverySourceAttachmentId,
      deliveryPhase: deliveryPhase ?? this.deliveryPhase,
      deliveryUserContent: deliveryUserContent ?? this.deliveryUserContent,
      deliveryAssistantContent:
          deliveryAssistantContent ?? this.deliveryAssistantContent,
      deliveryFileType: deliveryFileType ?? this.deliveryFileType,
      deliverySourcePath: deliverySourcePath ?? this.deliverySourcePath,
      deliverySourceFileName:
          deliverySourceFileName ?? this.deliverySourceFileName,
      deliverySourceFileType:
          deliverySourceFileType ?? this.deliverySourceFileType,
    );
  }
}

class _ActiveUniversalMediaOperation {
  _ActiveUniversalMediaOperation({
    required this.service,
    required this.cancelToken,
  });

  final UniversalMediaService service;
  final CancelToken cancelToken;
  UniversalMediaJob? job;
  String? leaseId;
}

/// 在服务的长轮询 / 下载期间保持数据库 lease。Timer 回调失败时先取消
/// Dio 请求，再由 waitFor 把失败转换成 [UniversalMediaLeaseLostException]；
/// 这样旧 worker 不会在 lease 被新 owner 接管后继续写 terminal 状态。
class _UniversalMediaLeaseHeartbeat {
  _UniversalMediaLeaseHeartbeat({
    required this.dao,
    required this.jobId,
    required this.leaseId,
    required this.interval,
    required this.cancelToken,
  });

  final media_database.MediaJobDao dao;
  final String jobId;
  final String leaseId;
  final Duration interval;
  final CancelToken cancelToken;

  Timer? _timer;
  Future<void>? _inFlight;
  UniversalMediaLeaseLostException? failure;

  bool get isLost => failure != null;

  void start() {
    _timer = Timer.periodic(interval, (_) => _tick());
  }

  void _tick() {
    if (isLost || _inFlight != null) return;
    final future = _heartbeat();
    _inFlight = future;
    future.whenComplete(() {
      if (identical(_inFlight, future)) _inFlight = null;
    });
  }

  Future<void> _heartbeat() async {
    try {
      final row = await dao.heartbeatJob(jobId, leaseId);
      if (row == null) _lose();
    } catch (_) {
      _lose();
    }
  }

  void _lose() {
    if (isLost) return;
    failure = UniversalMediaLeaseLostException(jobId);
    cancelToken.cancel('媒体任务 lease 已失效');
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    final inFlight = _inFlight;
    if (inFlight != null) await inFlight;
  }
}
