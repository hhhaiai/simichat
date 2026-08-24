import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 一级创作模式。模式属于产品导航状态，不绑定具体模型名称；具体入口是否
/// 可用仍由当前已配置模型能力和语音配置决定。
enum CreationMode {
  chat,
  image,
  video,
  voice;

  String get label => switch (this) {
    CreationMode.chat => '聊天',
    CreationMode.image => '图片',
    CreationMode.video => '视频',
    CreationMode.voice => '语音',
  };
}

/// 语音一级模式下的二级任务。模型选择时由显式能力标签设置，用户也可
/// 在工作区内切换到当前模型支持的其它语音任务。
enum VoiceCreationTool {
  synthesis,
  recognition,
  music,
  design,
  clone;

  String get label => switch (this) {
    VoiceCreationTool.synthesis => '语音合成',
    VoiceCreationTool.recognition => '语音识别',
    VoiceCreationTool.music => '音乐',
    VoiceCreationTool.design => '声音设计',
    VoiceCreationTool.clone => '声音克隆',
  };
}

/// 当前一级模式只在应用进程内保存，切换会话不会重置，创建任务完成后仍回到
/// 当前会话时间线。后续如果需要跨启动恢复，可在此 provider 外增加偏好持久化，
/// 不需要改动各模式工作区。
final creationModeProvider = StateProvider<CreationMode>(
  (ref) => CreationMode.chat,
);

/// 当前工作区真正使用的已配置模型 ID。
///
/// 聊天会话的默认模型仍由 [Session.defaultChannelModelId] 持久化；创作
/// 模式不能偷偷改写它，因为图片 / 视频 / 语音任务可能来自另一条渠道。
/// 这个 provider 是顶部胶囊、任务表单和下一次媒体请求共同读取的短期工作区
/// 选择。切换到聊天时它会由聊天模型选择器更新，切换会话时若没有匹配项则
/// 回退到该模式的已配置首选模型。
final activeCreationModelIdProvider = StateProvider<String?>((ref) => null);

final voiceCreationToolProvider = StateProvider<VoiceCreationTool>(
  (ref) => VoiceCreationTool.synthesis,
);

const _voiceRouteStoragePrefix = 'voice_creation_route_model_v1_';

class VoiceCreationRoutePreferences {
  const VoiceCreationRoutePreferences([this._modelIds = const {}]);

  final Map<VoiceCreationTool, String> _modelIds;

  String? modelIdFor(VoiceCreationTool tool) => _modelIds[tool];

  VoiceCreationRoutePreferences withModel(
    VoiceCreationTool tool,
    String modelId,
  ) {
    return VoiceCreationRoutePreferences(
      Map<VoiceCreationTool, String>.unmodifiable({
        ..._modelIds,
        tool: modelId,
      }),
    );
  }
}

/// Per-task default routes. Standard TTS, voice design and voice clone share
/// the same HTTP family but must not overwrite one another's selected model.
/// Persisting only the configured channel-model ID keeps Base URL and secrets
/// in the channel database as the single source of truth.
final voiceCreationRoutePreferencesProvider =
    StateNotifierProvider<
      VoiceCreationRoutePreferencesNotifier,
      VoiceCreationRoutePreferences
    >((ref) => VoiceCreationRoutePreferencesNotifier());

class VoiceCreationRoutePreferencesNotifier
    extends StateNotifier<VoiceCreationRoutePreferences> {
  VoiceCreationRoutePreferencesNotifier()
    : super(const VoiceCreationRoutePreferences()) {
    ready = _load();
  }

  late final Future<void> ready;

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var next = const VoiceCreationRoutePreferences();
      for (final tool in VoiceCreationTool.values) {
        final id = prefs
            .getString('$_voiceRouteStoragePrefix${tool.name}')
            ?.trim();
        if (id != null && id.isNotEmpty) next = next.withModel(tool, id);
      }
      state = next;
    } catch (_) {
      // A temporary preferences failure must not disable voice generation.
    }
  }

  Future<void> setPreferred(
    VoiceCreationTool tool,
    String channelModelId,
  ) async {
    await ready;
    final id = channelModelId.trim();
    if (id.isEmpty || state.modelIdFor(tool) == id) return;
    state = state.withModel(tool, id);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_voiceRouteStoragePrefix${tool.name}', id);
    } catch (_) {
      // Keep the selected route active for this process.
    }
  }
}
