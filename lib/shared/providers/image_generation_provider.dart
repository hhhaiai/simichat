import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/ai/image_generation_service.dart';
import '../../core/database/dao/channel_dao.dart';

/// 图片生成模型名持久化 key。
const kImageGenerationModelStorageKey = 'image_generation_model_v1';
const kImageGenerationChannelModelIdStorageKey =
    'image_generation_channel_model_id_v1';

/// 图片生成尺寸持久化 key（最近一次用户选择）。
const kImageGenerationSizeStorageKey = 'image_generation_size_v1';

/// 生成后自动上传百度 CDN 图床的开关 key。
const kImageGenerationAutoCdnStorageKey = 'image_generation_auto_cdn_v1';

/// 可选的生成尺寸（ChatGPT 风格常用比例）。
const kImageGenerationSizeOptions = <String>[
  '1024x1024',
  '1536x1024',
  '1024x1536',
  'auto',
];

/// 图片生成配置：模型名 + 最近一次使用的尺寸。
class ImageGenerationConfig {
  final String model;

  /// The configured channel-model that owns [model].  Keeping the id instead
  /// of copying a second Base URL/API key prevents image requests from
  /// silently falling back to the conversation channel.
  final String? channelModelId;
  final String size;

  /// 图片生成成功后是否自动上传百度 CDN 图床并把地址附在消息里。
  final bool autoUploadToCdn;

  const ImageGenerationConfig({
    required this.model,
    this.channelModelId,
    this.size = kImageGenerationSize,
    this.autoUploadToCdn = false,
  });

  bool get isConfigured => model.trim().isNotEmpty;
}

class ImageGenerationConfigNotifier
    extends StateNotifier<ImageGenerationConfig> {
  ImageGenerationConfigNotifier()
    : super(const ImageGenerationConfig(model: kDefaultImageGenerationModel)) {
    ready = _load();
  }

  late final Future<void> ready;

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(kImageGenerationModelStorageKey)?.trim();
      final savedSize = prefs.getString(kImageGenerationSizeStorageKey)?.trim();
      final savedChannelModelId = prefs
          .getString(kImageGenerationChannelModelIdStorageKey)
          ?.trim();
      state = ImageGenerationConfig(
        model: saved != null && saved.isNotEmpty
            ? saved
            : kDefaultImageGenerationModel,
        channelModelId: savedChannelModelId?.isNotEmpty == true
            ? savedChannelModelId
            : null,
        size: kImageGenerationSizeOptions.contains(savedSize)
            ? savedSize!
            : kImageGenerationSize,
        autoUploadToCdn:
            prefs.getBool(kImageGenerationAutoCdnStorageKey) ?? false,
      );
    } catch (_) {
      // 读取失败时保留默认配置。
    }
  }

  Future<void> setModel(String model) async {
    final trimmed = model.trim();
    if (trimmed.isEmpty) return;
    state = ImageGenerationConfig(
      model: trimmed,
      // A manually edited model name no longer has a trustworthy channel
      // owner. Clear the previous binding instead of sending the new name
      // with an old channel's Base URL/API key.
      channelModelId: null,
      size: state.size,
      autoUploadToCdn: state.autoUploadToCdn,
    );
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kImageGenerationModelStorageKey, trimmed);
      await prefs.remove(kImageGenerationChannelModelIdStorageKey);
    } catch (_) {
      // 持久化失败不阻断本次使用。
    }
  }

  /// Bind image generation to an already configured channel model.  The
  /// channel's encrypted key and Base URL remain in the channel table; only
  /// this stable id is persisted here.
  Future<void> applyChannelModel(ChannelModelWithChannel model) async {
    final name = model.channelModel.modelName.trim();
    final id = model.channelModel.id.trim();
    if (name.isEmpty || id.isEmpty) return;
    state = ImageGenerationConfig(
      model: name,
      channelModelId: id,
      size: state.size,
      autoUploadToCdn: state.autoUploadToCdn,
    );
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kImageGenerationModelStorageKey, name);
      await prefs.setString(kImageGenerationChannelModelIdStorageKey, id);
    } catch (_) {
      // Persistence failure must not block this request; the in-memory route
      // remains correct until the next restart.
    }
  }

  Future<void> setSize(String size) async {
    final trimmed = size.trim();
    if (!kImageGenerationSizeOptions.contains(trimmed)) return;
    state = ImageGenerationConfig(
      model: state.model,
      channelModelId: state.channelModelId,
      size: trimmed,
      autoUploadToCdn: state.autoUploadToCdn,
    );
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kImageGenerationSizeStorageKey, trimmed);
    } catch (_) {
      // 持久化失败不阻断本次使用。
    }
  }

  Future<void> setAutoUploadToCdn(bool enabled) async {
    state = ImageGenerationConfig(
      model: state.model,
      channelModelId: state.channelModelId,
      size: state.size,
      autoUploadToCdn: enabled,
    );
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(kImageGenerationAutoCdnStorageKey, enabled);
    } catch (_) {
      // 持久化失败不阻断本次使用。
    }
  }
}

final imageGenerationConfigProvider =
    StateNotifierProvider<ImageGenerationConfigNotifier, ImageGenerationConfig>(
      (ref) => ImageGenerationConfigNotifier(),
    );
