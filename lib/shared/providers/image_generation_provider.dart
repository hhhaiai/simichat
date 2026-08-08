import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/ai/image_generation_service.dart';

/// 图片生成模型名持久化 key。
const kImageGenerationModelStorageKey = 'image_generation_model_v1';

/// 图片生成配置：目前只需可配置模型名，默认 OpenAI 标准 `dall-e-3`。
class ImageGenerationConfig {
  final String model;
  const ImageGenerationConfig({required this.model});

  bool get isConfigured => model.trim().isNotEmpty;
}

class ImageGenerationConfigNotifier
    extends StateNotifier<ImageGenerationConfig> {
  ImageGenerationConfigNotifier()
    : super(const ImageGenerationConfig(model: kDefaultImageGenerationModel)) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(kImageGenerationModelStorageKey)?.trim();
      if (saved != null && saved.isNotEmpty) {
        state = ImageGenerationConfig(model: saved);
      }
    } catch (_) {
      // 读取失败时保留默认配置。
    }
  }

  Future<void> setModel(String model) async {
    final trimmed = model.trim();
    if (trimmed.isEmpty) return;
    state = ImageGenerationConfig(model: trimmed);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kImageGenerationModelStorageKey, trimmed);
    } catch (_) {
      // 持久化失败不阻断本次使用。
    }
  }
}

final imageGenerationConfigProvider =
    StateNotifierProvider<ImageGenerationConfigNotifier, ImageGenerationConfig>(
      (ref) => ImageGenerationConfigNotifier(),
    );
