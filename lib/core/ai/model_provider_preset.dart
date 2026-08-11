class ModelProviderPreset {
  final String id;
  final String name;
  final String protocol;
  final String baseUrl;
  final String description;
  final String docsUrl;
  final bool openAiCompatible;
  final List<String> recommendedModels;

  /// 面向需要注册才能使用的渠道预设：没有 Key 时引导用户去该地址注册。
  /// 为空表示该预设无需注册（如本地 Ollama 或已有官方账号即可开通）。
  final String? signUpUrl;

  /// 品牌 logo 资源路径（`assets/branding/...`）。
  /// 为空时使用 [getProviderIcon] 的 Material 图标。
  final String? logoAsset;

  const ModelProviderPreset({
    required this.id,
    required this.name,
    required this.protocol,
    required this.baseUrl,
    required this.description,
    required this.docsUrl,
    required this.openAiCompatible,
    this.recommendedModels = const [],
    this.signUpUrl,
    this.logoAsset,
  });
}

/// SimiRouter 的官方入口。注册页保留推广参数，方便用户直接完成注册。
const kSimiRouterHomeUrl = 'https://api.dwchainless.com/';
const kSimiRouterSignUpUrl = 'https://api.dwchainless.com/sign-up?aff=Bslh';

/// 返回协议是否必须配置 API Key。
///
/// 本地 Ollama 默认不需要密钥；保留独立判断函数，避免设置页、批量导入
/// 和其他接入入口各自维护一份不一致的协议判断。
bool modelProtocolRequiresApiKey(String protocol) => protocol != 'ollama';

const kModelProviderPresets = [
  ModelProviderPreset(
    id: 'openai',
    name: 'OpenAI',
    protocol: 'openai_chat',
    baseUrl: 'https://api.openai.com/v1',
    description: '官方 OpenAI API，支持 Chat Completions 兼容接口。',
    docsUrl: 'https://platform.openai.com/docs',
    openAiCompatible: true,
    recommendedModels: ['gpt-4o-mini', 'gpt-4.1-mini'],
  ),
  ModelProviderPreset(
    id: 'dwchainless',
    name: 'SimiRouter AI 中转站',
    protocol: 'openai_chat',
    baseUrl: 'https://api.dwchainless.com/v1',
    description:
        '高并发、低延迟的企业级 AI API 服务。一个 API 统一接入主流 AI 模型，支持智能路由、负载均衡与自动故障切换；对话内容默认不持久化存储，计费公开透明。',
    docsUrl: kSimiRouterHomeUrl,
    signUpUrl: kSimiRouterSignUpUrl,
    openAiCompatible: true,
    logoAsset: 'assets/branding/simirouter.png',
    recommendedModels: ['gpt-4o-mini', 'deepseek-chat', 'qwen-plus'],
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
    recommendedModels: ['deepseek-chat', 'deepseek-reasoner'],
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
    recommendedModels: ['qwen-plus', 'qwen-turbo'],
  ),
  ModelProviderPreset(
    id: 'qianfan',
    name: '百度千帆 / 文心一言',
    protocol: 'openai_chat',
    baseUrl: 'https://qianfan.baidubce.com/v2',
    description: '百度智能云千帆 v2 OpenAI 兼容接口，适合 ERNIE 与千帆托管模型。',
    docsUrl: 'https://cloud.baidu.com/doc/qianfan-api/s/3m7of64lb',
    openAiCompatible: true,
    recommendedModels: ['ernie-4.5-turbo-128k', 'ernie-x1-turbo-32k'],
  ),
  ModelProviderPreset(
    id: 'xfyun-spark',
    name: '讯飞星火',
    protocol: 'openai_chat',
    baseUrl: 'https://spark-api-open.xf-yun.com/v1',
    description: '讯飞星火 HTTP OpenAI 兼容接口，适合 Spark Lite / Pro / Max / Ultra 系列。',
    docsUrl:
        'https://www.xfyun.cn/doc/spark/HTTP%E8%B0%83%E7%94%A8%E6%96%87%E6%A1%A3.html',
    openAiCompatible: true,
    recommendedModels: ['lite', 'generalv3.5'],
  ),
  ModelProviderPreset(
    id: 'moonshot',
    name: 'Kimi / Moonshot AI',
    protocol: 'openai_chat',
    baseUrl: 'https://api.moonshot.ai/v1',
    description: 'Moonshot AI OpenAI 兼容接口，适合 Kimi 系列长上下文模型。',
    docsUrl: 'https://platform.kimi.ai/docs/api/overview',
    openAiCompatible: true,
    recommendedModels: ['kimi-k2-0711-preview', 'moonshot-v1-8k'],
  ),
  ModelProviderPreset(
    id: 'siliconflow',
    name: '硅基流动 / SiliconFlow',
    protocol: 'openai_chat',
    baseUrl: 'https://api.siliconflow.cn/v1',
    description: 'SiliconFlow OpenAI 兼容接口，适合低价 / 免费额度模型探索。',
    docsUrl:
        'https://docs.siliconflow.cn/cn/api-reference/chat-completions/chat-completions',
    openAiCompatible: true,
    recommendedModels: ['Qwen/Qwen3-8B', 'deepseek-ai/DeepSeek-V3'],
  ),
  ModelProviderPreset(
    id: 'groq',
    name: 'Groq',
    protocol: 'openai_chat',
    baseUrl: 'https://api.groq.com/openai/v1',
    description: 'Groq OpenAI 兼容接口，适合低延迟推理和 Llama 系列模型。',
    docsUrl: 'https://console.groq.com/docs/openai',
    openAiCompatible: true,
    recommendedModels: ['llama-3.1-8b-instant', 'llama-3.3-70b-versatile'],
  ),
  ModelProviderPreset(
    id: 'mistral',
    name: 'Mistral AI',
    protocol: 'openai_chat',
    baseUrl: 'https://api.mistral.ai/v1',
    description: 'Mistral OpenAI 兼容接口，适合 Mistral 系列欧洲模型。',
    docsUrl: 'https://docs.mistral.ai/api/',
    openAiCompatible: true,
    recommendedModels: ['mistral-small-latest', 'mistral-large-latest'],
  ),
  ModelProviderPreset(
    id: 'together',
    name: 'Together AI',
    protocol: 'openai_chat',
    baseUrl: 'https://api.together.ai/v1',
    description: 'Together AI OpenAI 兼容接口，适合开源模型托管和低价模型探索。',
    docsUrl: 'https://docs.together.ai/docs/inference/openai-compatibility',
    openAiCompatible: true,
    recommendedModels: [
      'MiniMaxAI/MiniMax-M3',
      'Qwen/Qwen3-235B-A22B-fp8-tput',
    ],
  ),
  ModelProviderPreset(
    id: 'fireworks',
    name: 'Fireworks AI',
    protocol: 'openai_chat',
    baseUrl: 'https://api.fireworks.ai/inference/v1',
    description: 'Fireworks AI OpenAI 兼容接口，适合开源模型推理和托管模型。',
    docsUrl: 'https://docs.fireworks.ai/api-reference/post-chatcompletions',
    openAiCompatible: true,
    recommendedModels: [
      'accounts/fireworks/models/llama-v3p1-8b-instruct',
      'accounts/fireworks/models/deepseek-v3',
    ],
  ),
  ModelProviderPreset(
    id: 'xai',
    name: 'xAI / Grok',
    protocol: 'openai_chat',
    baseUrl: 'https://api.x.ai/v1',
    description: 'xAI OpenAI 兼容接口，适合 Grok 系列模型。',
    docsUrl: 'https://docs.x.ai/docs/overview',
    openAiCompatible: true,
    recommendedModels: ['grok-4.3'],
  ),
  ModelProviderPreset(
    id: 'perplexity',
    name: 'Perplexity',
    protocol: 'openai_chat',
    baseUrl: 'https://api.perplexity.ai',
    description: 'Perplexity OpenAI 兼容接口，适合 Sonar 搜索增强回答。',
    docsUrl: 'https://docs.perplexity.ai/guides/chat-completions-guide',
    openAiCompatible: true,
    recommendedModels: ['sonar-pro', 'sonar'],
  ),
  ModelProviderPreset(
    id: 'deepinfra',
    name: 'DeepInfra',
    protocol: 'openai_chat',
    baseUrl: 'https://api.deepinfra.com/v1/openai',
    description: 'DeepInfra OpenAI 兼容接口，适合开源模型托管和低价推理。',
    docsUrl: 'https://deepinfra.com/docs/openai_api',
    openAiCompatible: true,
    recommendedModels: [
      'deepseek-ai/DeepSeek-V3',
      'meta-llama/Meta-Llama-3.1-8B-Instruct',
    ],
  ),
  ModelProviderPreset(
    id: 'volcengine-ark',
    name: '火山方舟 / 豆包',
    protocol: 'openai_chat',
    baseUrl: 'https://ark.cn-beijing.volces.com/api/v3',
    description: '火山方舟 OpenAI 兼容接口，适合豆包与方舟托管模型。',
    docsUrl: 'https://www.volcengine.com/docs/82379/1399008',
    openAiCompatible: true,
    recommendedModels: ['doubao-seed-1-6-250615', 'deepseek-v3-250324'],
  ),
  ModelProviderPreset(
    id: 'tencent-hunyuan',
    name: '腾讯混元',
    protocol: 'openai_chat',
    baseUrl: 'https://api.hunyuan.cloud.tencent.com/v1',
    description: '腾讯混元 OpenAI 兼容接口，适合混元大模型系列。',
    docsUrl: 'https://cloud.tencent.com/document/product/1729/111007',
    openAiCompatible: true,
    recommendedModels: ['hunyuan-turbos-latest', 'hunyuan-lite'],
  ),
  ModelProviderPreset(
    id: 'openrouter',
    name: 'OpenRouter',
    protocol: 'openai_chat',
    baseUrl: 'https://openrouter.ai/api/v1',
    description: 'OpenAI 兼容聚合平台，可接入多家模型并便于免费/低价模型探索。',
    docsUrl: 'https://openrouter.ai/docs/quickstart',
    openAiCompatible: true,
    recommendedModels: [
      'openai/gpt-4o-mini',
      'deepseek/deepseek-chat-v3-0324:free',
    ],
  ),
  ModelProviderPreset(
    id: 'ollama',
    name: 'Ollama 本地模型',
    protocol: 'ollama',
    baseUrl: 'http://localhost:11434',
    description: '本地 Ollama 服务，不需要云端 API Key。',
    docsUrl: 'https://ollama.com',
    openAiCompatible: false,
    recommendedModels: ['gemma4', 'qwen3:4b', 'llama3.2:3b'],
  ),
];

ModelProviderPreset? findModelProviderPreset(String id) {
  final normalizedId = _normalizeProviderPresetLookup(id);
  for (final preset in kModelProviderPresets) {
    final normalizedName = _normalizeProviderPresetLookup(preset.name);
    final nameAliases = normalizedName
        .split('/')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty);
    if (_normalizeProviderPresetLookup(preset.id) == normalizedId ||
        normalizedName == normalizedId ||
        nameAliases.contains(normalizedId)) {
      return preset;
    }
  }
  return null;
}

String _normalizeProviderPresetLookup(String value) {
  return value.trim().toLowerCase().replaceAll(RegExp(r'\s*/\s*'), '/');
}
