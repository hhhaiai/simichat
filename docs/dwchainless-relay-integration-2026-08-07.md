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
  - `signUpUrl: https://api.dwchainless.com/sign-up?aff=Bslh`
  - `recommendedModels: ['gpt-4o-mini', 'deepseek-chat', 'qwen-plus']`
  - 支持按 id / 显示名 / 别名查找（沿用 `findModelProviderPreset` 容错逻辑）。

### 2.2 设置页渠道区推广卡片 `lib/features/settings/settings_page.dart`
- `_buildDwChainlessCard()` 渲染在渠道列表顶部，并收敛为紧凑三态：
  1. 未接入 → 一句定位 +「获取 Key / 一键接入 / 官网」；
  2. 已接入但未填 Key → 「已添加 · 尚未填写 API Key」+「获取 Key / 补充 Key / 官网」；
  3. 已接入且有 Key → 「已接入 · 可管理模型和 API Key」+「管理 / 官网」。
- 六项常驻营销标签从设置页首屏移除；三个动作使用单排等宽布局，320×568、120% 字号下整卡小于 170 logical pixels，按钮点击高度至少 44 logical pixels；已接入状态卡高度小于 190 logical pixels。
- 已存在 SimiRouter 渠道时「补充 Key / 管理」编辑原渠道，不再重复创建；渠道识别同时要求 HTTPS、`Uri.host == api.dwchainless.com`、443 端口且无 userInfo，不接受字符串相似域名、自定义端口或嵌入凭据的 URL。
- 预设提示卡 `_ProviderPresetHint` 对 SimiRouter 单独收敛为品牌、接入说明、推荐模型和「获取 Key / 访问官网」两个主动作，不再显示官网地址、Base URL 和复制链接按钮。

### 2.3 应用内 H5 `lib/shared/widgets/in_app_h5_page.dart`
- 新增 `InAppH5Page`，使用 `webview_flutter` 打开注册页和官网，原生 AppBar 只提供返回 / 刷新 / 标题，不显示地址栏。
- 主帧导航只允许初始可信 host / port 上无 userInfo 的 HTTPS；HTTP 降级、相似域名、跨域、非 443 自定义端口以及 `intent:` / `mailto:` / `tel:` 等自定义 scheme 均阻止并展示明确反馈。非主帧导航保留，避免误拦验证码和 iframe。
- Android / iPhone / Mac 使用系统 WebView；不支持 WebView 的测试 / 桌面平台显示原生状态页，不回退外部浏览器。
- 设置页通过短生命周期隐藏 WebView 预热 `https://api.dwchainless.com/`。官网和注册页共享同一批 hash JS/CSS，后续打开复用系统 WebView 的磁盘资源缓存、Cookie 和 localStorage；同一 App 进程内同 origin 成功后只预热一次，预热完成或 12 秒超时即销毁，不常驻占用内存。
- 不把第三方整站 JS/CSS 固化进 Flutter assets：官网当前主 JS 约 3.45 MB、CSS 约 0.40 MB，部署 hash 会变化，离线拷贝会造成版本漂移、CSP/CORS 和登录/API origin 问题；本地只保留品牌 logo 与加载壳。

### 2.4 登录态持久化 `lib/shared/widgets/in_app_h5_page.dart`
- 官网、获取 Key 和关于页共用系统 WebView 的默认持久 profile；Cookie、localStorage、IndexedDB 与磁盘资源缓存不会在页面关闭时主动清理。
- 当前线上 bundle 会把账号资料写入同 origin 的 `localStorage['user']`，请求使用 `withCredentials: true`；因此再次打开 H5 时可直接复用账号资料与网站下发的原始认证 Cookie。
- App 不再读取、序列化或用 Dart `WebViewCookie` 重建认证 Cookie。该对象只能表达 name / value / domain / path，手工恢复会丢失 Secure / HttpOnly / SameSite / expires 等属性，并可能覆盖更安全的原始 Cookie。
- Android 关闭页面、SPA 跳转、加载完成或 App 进后台时调用原生 `CookieManager.flush()`；iOS 使用 `WKWebsiteDataStore.default()`，以 `WKHTTPCookieStore.getAllCookies` 作为当前 Cookie 操作完成屏障。短时间重复 flush 会合并，关闭按钮最多等待 2 秒，原生通道异常或挂起不会卡住退出。
- 登录态只在网站主动登出、系统清理 App 数据或卸载 App 时清除；App 本身不保存密码，也不复制账号 JSON 到 Flutter 存储。

### 2.5 关于页鸣谢
- 关于区新增「鸣谢 · SimiRouter AI 中转站」ListTile：图标与简洁说明，点击进入无地址栏的内置官网 H5 页面。

## 三、测试

- `test/model_provider_preset_test.dart`：dwchainless 预设字段、显示名 / 别名匹配。
- `test/settings_page_dwchainless_test.dart`：推广卡片、内置注册 / 官网 URL、一键接入预设、已接入 / 未填 Key 状态、320px / 120% 字号紧凑高度、44px 点击目标、编辑原渠道、相似域名 / 自定义端口 / userInfo 拒绝、预热入口和关于页官网点击。
- `test/in_app_h5_page_test.dart`：HTTPS / 同 host / 同 port / 无 userInfo 导航策略、自定义 scheme 阻止、无地址栏页面壳、关闭 / 状态页返回、原生 profile flush 与超时回归；真机集成测试使用带 Max-Age / Secure / SameSite 的测试 Cookie 和独立 localStorage 标记验证关闭后重开复用，不清理或覆盖真实账号状态。
- 2026-08-10 最终主机验证：全量 Flutter 基线 757 项、最后边界修正后的渠道 / H5 / 多模态聚焦 123 项、上下文预算边界 5 项、`flutter analyze`、`git diff --check HEAD`、Android Release 与 iOS unsigned Release 均通过；两端产物均确认包含 `assets/branding/simirouter.png`。H5 flush 合并队列已补齐 drain 结束窗口的尾随请求，避免最后一次 Cookie 提交悬空。按用户要求本轮不执行真机安装和账号登录复验。

## 四、隐私与安全

- API Key 仍走既有 `KeyEncryptor` AES-CBC 加密本地保存，不进入日志 / Markdown / 导出包。
- 注册 / 官网链接只在应用内打开 `api.dwchainless.com` HTTPS 地址；加载失败只展示可重试的原生错误态。
- 不内置任何中转站 Key；模型连通性测试复用现有结构化解读（401 / 403 / 429 等）。
- 不把第三方网页 Cookie 或账号资料降级复制到 SharedPreferences / FlutterSecureStorage；认证属性由网站与系统 WebView 原样维护。
