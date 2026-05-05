import 'package:flutter/material.dart';

/// 根据协议类型返回对应图标
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
