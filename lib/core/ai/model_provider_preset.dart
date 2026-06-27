class ModelProviderPreset {
  final String id;
  final String name;
  final String protocol;
  final String baseUrl;
  final String description;
  final String docsUrl;
  final bool openAiCompatible;

  const ModelProviderPreset({
    required this.id,
    required this.name,
    required this.protocol,
    required this.baseUrl,
    required this.description,
    required this.docsUrl,
    required this.openAiCompatible,
  });
}

const kModelProviderPresets = [
  ModelProviderPreset(
    id: 'openai',
    name: 'OpenAI',
    protocol: 'openai_chat',
    baseUrl: 'https://api.openai.com/v1',
    description: '官方 OpenAI API，支持 Chat Completions 兼容接口。',
    docsUrl: 'https://platform.openai.com/docs',
    openAiCompatible: true,
  ),
  ModelProviderPreset(
    id: 'anthropic',
    name: 'Claude / Anthropic',
    protocol: 'claude',
    baseUrl: 'https://api.anthropic.com',
    description: 'Anthropic Messages API，适合 Claude 系列模型。',
    docsUrl: 'https://docs.anthropic.com/en/api/messages',
    openAiCompatible: false,
  ),
  ModelProviderPreset(
    id: 'gemini',
    name: 'Gemini / Google',
    protocol: 'gemini',
    baseUrl: 'https://generativelanguage.googleapis.com',
    description: 'Google Gemini API，支持模型列表自动获取。',
    docsUrl: 'https://ai.google.dev/gemini-api/docs',
    openAiCompatible: false,
  ),
  ModelProviderPreset(
    id: 'deepseek',
    name: 'DeepSeek',
    protocol: 'openai_chat',
    baseUrl: 'https://api.deepseek.com/v1',
    description: 'DeepSeek OpenAI 兼容接口，适合国内高性价比模型。',
    docsUrl: 'https://api-docs.deepseek.com/',
    openAiCompatible: true,
  ),
  ModelProviderPreset(
    id: 'dashscope',
    name: '通义千问 / 阿里云百炼',
    protocol: 'openai_chat',
    baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    description: '阿里云百炼 OpenAI 兼容接口，适合通义千问与百炼模型。',
    docsUrl:
        'https://help.aliyun.com/zh/model-studio/compatibility-of-openai-with-dashscope',
    openAiCompatible: true,
  ),
  ModelProviderPreset(
    id: 'openrouter',
    name: 'OpenRouter',
    protocol: 'openai_chat',
    baseUrl: 'https://openrouter.ai/api/v1',
    description: 'OpenAI 兼容聚合平台，可接入多家模型并便于免费/低价模型探索。',
    docsUrl: 'https://openrouter.ai/docs/quickstart',
    openAiCompatible: true,
  ),
  ModelProviderPreset(
    id: 'ollama',
    name: 'Ollama 本地模型',
    protocol: 'ollama',
    baseUrl: 'http://localhost:11434',
    description: '本地 Ollama 服务，不需要云端 API Key。',
    docsUrl: 'https://ollama.com',
    openAiCompatible: false,
  ),
];

ModelProviderPreset? findModelProviderPreset(String id) {
  for (final preset in kModelProviderPresets) {
    if (preset.id == id) return preset;
  }
  return null;
}
