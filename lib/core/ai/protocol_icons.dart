import 'package:flutter/material.dart';

import 'model_provider_preset.dart';

/// 根据协议类型返回对应图标（仅作为没有厂商预设时的兜底）。
IconData getProtocolIcon(String protocol) {
  switch (protocol) {
    case 'openai_chat':
    case 'openai_response':
      return Icons.auto_awesome;
    case 'claude':
      return Icons.psychology;
    case 'gemini':
      return Icons.diamond;
    case 'ollama':
      return Icons.terminal;
    default:
      return Icons.smart_toy;
  }
}

/// 根据厂商预设返回对应图标（内置渠道按品牌区分，而不是统一用协议图标）。
///
/// 没有真实品牌 logo 资源，用语义相近的 Material 图标区分各内置渠道。
IconData getProviderIcon(String presetId) {
  switch (presetId) {
    case 'openai':
      return Icons.auto_awesome;
    case 'dwchainless':
      return Icons.hub;
    case 'anthropic':
      return Icons.psychology;
    case 'gemini':
      return Icons.diamond;
    case 'deepseek':
      return Icons.bolt;
    case 'dashscope':
      return Icons.cloud;
    case 'qianfan':
      return Icons.sailing;
    case 'xfyun-spark':
      return Icons.local_fire_department;
    case 'moonshot':
      return Icons.rocket_launch;
    case 'siliconflow':
      return Icons.memory;
    case 'groq':
      return Icons.flash_on;
    case 'mistral':
      return Icons.air;
    case 'together':
      return Icons.group_work;
    case 'fireworks':
      return Icons.celebration;
    case 'xai':
      return Icons.stars;
    case 'perplexity':
      return Icons.travel_explore;
    case 'deepinfra':
      return Icons.data_object;
    case 'volcengine-ark':
      return Icons.volcano;
    case 'tencent-hunyuan':
      return Icons.blur_circular;
    case 'openrouter':
      return Icons.route;
    case 'ollama':
      return Icons.terminal;
    default:
      return Icons.smart_toy;
  }
}

/// 渠道图标：能匹配到内置厂商预设时用品牌图标，否则回退到协议图标。
IconData getChannelIcon(String protocol, String baseUrl) {
  final preset = findModelProviderPresetByBaseUrl(protocol, baseUrl);
  if (preset != null) return getProviderIcon(preset.id);
  return getProtocolIcon(protocol);
}

/// 渠道品牌 logo 资源路径：预设配置了真实 logo（如 SimiRouter）时返回
/// `assets/branding/...`，UI 用它显示图片；没有则返回 null 并回退
/// [getChannelIcon] 的 Material 图标。
String? getChannelLogoAsset(String protocol, String baseUrl) {
  return findModelProviderPresetByBaseUrl(protocol, baseUrl)?.logoAsset;
}

/// 按（协议 + Base URL）匹配内置厂商预设，供渠道图标等场景复用。
ModelProviderPreset? findModelProviderPresetByBaseUrl(
  String protocol,
  String baseUrl,
) {
  final normalizedBaseUrl = _stripTrailingSlashes(baseUrl);
  for (final preset in kModelProviderPresets) {
    if (preset.protocol != protocol) continue;
    if (_stripTrailingSlashes(preset.baseUrl) == normalizedBaseUrl) {
      return preset;
    }
  }
  return null;
}

String _stripTrailingSlashes(String value) {
  var normalized = value.trim();
  while (normalized.endsWith('/') && normalized.length > 1) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized;
}
