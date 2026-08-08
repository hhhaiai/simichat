# DW Chainless 中转站集成（2026-08-07）

> 目标：把自有 OpenAI 兼容中转站 `https://api.dwchainless.com/` 预置为应用的推荐接入渠道，
> 用户填写 Key 即用；没有 Key 时一键跳转注册页；并在“关于”页鸣谢中转站。

---

## 一、能力确认

- `GET https://api.dwchainless.com/` → 200（官网 / 控制台）。
- `GET https://api.dwchainless.com/v1` → 301（标准 OpenAI 兼容前缀）。
- `GET https://api.dwchainless.com/v1/models` → 401（需 Bearer Key，确认 OpenAI 兼容 API 生效）。
- 因此应用内 OpenAI 兼容 Base URL 取 `https://api.dwchainless.com/v1`。

## 二、代码落点

### 2.1 厂商预设 `lib/core/ai/model_provider_preset.dart`
- `ModelProviderPreset` 新增可选字段 `signUpUrl`（面向需要注册的渠道预设）。
- 新增 `dwchainless` 预设：
  - `protocol: openai_chat`，`openAiCompatible: true`
  - `baseUrl: https://api.dwchainless.com/v1`
  - `docsUrl: https://api.dwchainless.com/`
  - `signUpUrl: https://api.dwchainless.com/sign-up`
  - `recommendedModels: ['gpt-4o-mini', 'deepseek-chat', 'qwen-plus']`
  - 支持按 id / 显示名 / 别名查找（沿用 `findModelProviderPreset` 容错逻辑）。

### 2.2 设置页渠道区推广卡片 `lib/features/settings/settings_page.dart`
- `_buildDwChainlessCard()` 渲染在渠道列表顶部，状态三态：
  1. 未接入 → 「去注册获取 Key」（跳转注册页）+「一键接入」（预填预设）+「访问官网」；
  2. 已接入但未填 Key（`apiKeyEncrypted` 为空）→ 提示补充 Key；
  3. 已接入且有 Key → 「已接入」，可直接添加 / 自动获取模型。
- 预设提示卡 `_ProviderPresetHint` 对带 `signUpUrl` 的预设额外提供「去注册」按钮。

### 2.3 外部链接打开 `lib/shared/providers/external_url_provider.dart`
- 新增 `ExternalUrlOpener` 抽象 + `SystemBrowserUrlOpener`（`url_launcher`，仅放行 HTTP(S)），
  通过 `externalUrlOpenerProvider` 注入，便于测试替换。
- `pubspec.yaml` 新增 `url_launcher: ^6.3.2`。

### 2.4 关于页鸣谢
- 关于区新增「鸣谢 · DW Chainless 中转站」ListTile：图标（hub 徽章）、文案与官网地址，
  点击用系统浏览器打开 `https://api.dwchainless.com/`。

## 三、测试

- `test/model_provider_preset_test.dart`：dwchainless 预设字段、显示名 / 别名匹配。
- `test/settings_page_dwchainless_test.dart`：推广卡片、注册跳转、一键接入预填、
  已接入 / 未填 Key 状态、关于页鸣谢点击。

## 四、隐私与安全

- API Key 仍走既有 `KeyEncryptor` AES-CBC 加密本地保存，不进入日志 / Markdown / 导出包。
- 注册 / 官网链接只打开 HTTP(S) 公网地址；打开失败回退为复制链接。
- 不内置任何中转站 Key；模型连通性测试复用现有结构化解读（401 / 403 / 429 等）。
