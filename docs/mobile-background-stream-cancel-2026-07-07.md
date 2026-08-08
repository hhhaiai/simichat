# 移动端后台切出取消未完成流式请求（2026-07-07）

## 目标

补齐“后台未完成请求恢复”的第一层保护：应用进入非前台生命周期时，不继续悬挂当前会话的流式模型请求，避免后台网络连接长期占用、恢复前台后 UI 仍显示卡在生成中。

## 实现

- `lib/main.dart`
  - `ResponsiveShell.didChangeAppLifecycleState()` 在非 `resumed` 状态下继续取消 Dreaming 前台 timer。
  - 同时读取当前 active 会话和已加载会话列表；只要某个会话的 `streamStateProvider(sessionId).isStreaming == true`，都会调用 `cancelStreaming(ref, sessionId, error: backgroundStreamingInterruptedMessage)`，不再只处理当前 active 会话。
  - 记录本轮 `_backgroundInterruptedSessionIds`。
  - 同时写入 SharedPreferences：`simichat.background_interrupted_session_ids=[sessionId...]`，并继续保留旧单值 key `simichat.background_interrupted_session_id=<第一条 sessionId>` 作为兼容 marker；写入前会清洗已有列表中的空值、空白和重复 ID，为后台被系统回收后的冷启动恢复保留干净的待重试状态。
  - 恢复到 `AppLifecycleState.resumed` 时，如果仍存在被后台中断且错误状态仍为 `backgroundStreamingInterruptedMessage` 的会话，弹出一次固定 SnackBar；单条时显示 `已停止后台生成，可点“重试”继续`，多条时显示 `已停止 N 个后台生成，可点“重试全部”继续`。action 必须由用户显式点击，单条重试当前会话，多条逐条重试本轮中断会话。
  - 同一进程内恢复前台并显示提示后，会清理 SharedPreferences marker，避免下次冷启动重复提醒。
  - 为避免快速切后台 / 前台时异步 marker 写入晚于清理，恢复前台清理 marker 前会等待本轮 `_persistBackgroundInterruptedSession()` 完成，再删除新旧两类 marker。
  - 首次启动时 `_runStartupTasks()` 会先自动选择 / 创建会话，再读取 SharedPreferences marker 列表；如果只有旧单值 key，也会兼容读取。
  - 读取 marker 时同样会 trim、跳过空值并按顺序去重；对列表中仍存在的唯一会话逐一恢复 `backgroundStreamingInterruptedMessage` 错误态，随后切到第一条有效待重试会话并弹出 SnackBar；单条时显示 `已恢复上次后台中断，可点“重试”继续`，action 为 `重试`；多条时显示 `已恢复 N 个后台中断会话，可点“重试全部”继续`，action 为 `重试全部`。只有用户显式点击 action 时才会逐条调用本地 DAO 读取最后一条 user 消息并重试，不做后台自动重发。最后消费列表 key 和旧单值 key。
  - 如果自动选择的是最新会话、而 marker 指向另一个仍存在的会话，则先切回 marker 会话，再恢复错误条、弹出同一条冷启动重试提示并消费 marker，避免待重试会话被留在历史列表里无提示。
  - 如果 marker 指向的会话已被删除或不存在，则直接清理 SharedPreferences marker，不切换会话、不显示后台恢复提示，避免每次冷启动都残留无效待重试状态；列表中部分会话不存在时会跳过缺失项、恢复其余有效项。
  - `cancelStreaming()` 复用既有停止生成逻辑：取消上游 `CancelToken`、完成等待 completer、取消 stream subscription、清理会话流式状态。
- `lib/shared/providers/chat_provider.dart`
  - 新增 `backgroundStreamingInterruptedMessage`：`应用进入后台，已停止本次生成，回到前台后可重试。`
  - 新增 `kBackgroundInterruptedSessionStorageKey`：`simichat.background_interrupted_session_id`。
  - 新增 `kBackgroundInterruptedSessionsStorageKey`：`simichat.background_interrupted_session_ids`。
  - `cancelStreaming()` 新增可选 `error` 参数；手动停止仍不传错误，后台切出时传入上述提示。
  - ChatPage 既有错误条会展示该提示，并保留“重试 / 关闭”操作。
  - `retryLastUserMessage()` 不再依赖 `messagesProvider` 已预加载；用户主动点“重试”时直接通过 `messageDaoProvider` 查询最后一条用户消息，再进入 `sendMessage()`，避免冷启动 / provider 仍 loading 时静默无效。

## 回归测试

- `test/mobile_main_flow_smoke_test.dart`
  - 新增 `mobile inactive lifecycle cancels active streaming response`。
  - 使用内存 SQLite 和 `ProviderContainer` 启动移动端 shell。
  - 手动把当前 active 会话置为：
    - `isStreaming=true`
    - `currentContent='partial background reply'`
    - `isWaitingForFirstToken=false`
  - 模拟 `AppLifecycleState.inactive`。
  - 断言流式状态被清空：
    - `isStreaming=false`
    - `currentContent=''`
    - `isWaitingForFirstToken=false`
    - `error=backgroundStreamingInterruptedMessage`
  - 断言页面显示后台中断提示和 `重试` 按钮。
  - 模拟 `AppLifecycleState.resumed` 后，断言页面弹出一次 `已停止后台生成，可点“重试”继续` 提醒。
  - 断言后台切出会写入 SharedPreferences 单值兼容 marker 和列表 marker，恢复前台提示后两类 marker 均被消费。
- `test/mobile_main_flow_smoke_test.dart`
  - 新增 `mobile inactive lifecycle cancels all streaming sessions`。
  - 预置两个会话，让当前 active 会话和另一个非当前会话都处于 `isStreaming=true`。
  - 旧逻辑只取消 active 会话，红灯失败于非当前会话 `isStreaming` 仍为 true。
  - 修复后两条会话都会被置为 `backgroundStreamingInterruptedMessage`，SharedPreferences 列表 marker 保留两条 ID，恢复前台提示 `已停止 2 个后台生成，可点“重试全部”继续` 并提供 `重试全部` action。
- `test/chat_provider_retry_test.dart`
  - 新增 `retry loads last user message even before messages provider`。
  - 不预先 watch `messagesProvider`，只通过一个按钮调用 `retryLastUserMessage()`；旧逻辑红灯保持后台中断错误态，修复后会直接查 DAO 并进入发送路径，在无模型配置场景下转换为 `请先选择一个模型`，证明用户主动重试不再静默无效。
- `test/mobile_main_flow_smoke_test.dart`
  - 新增 `mobile startup restores persisted background retry marker`。
  - 使用 `SharedPreferences.setMockInitialValues()` 预置 `kBackgroundInterruptedSessionStorageKey=<sessionId>`。
  - 启动应用后，验证自动选择当前会话、恢复错误条、弹出 `已恢复上次后台中断，可点“重试”继续`，并消费 marker。
- `test/mobile_main_flow_smoke_test.dart`
  - 新增 `mobile startup switches to persisted background retry session`。
  - 预置两个会话，并把非 marker 会话设为最新，复现冷启动自动选择最新会话后忽略 marker 的旧行为。
  - 启动应用后，验证会切回 marker 指向的会话、恢复后台中断错误条、弹出冷启动重试提示，并消费 marker。
- `test/mobile_main_flow_smoke_test.dart`
  - 新增 `mobile startup clears stale background retry marker`。
  - 预置 `kBackgroundInterruptedSessionStorageKey` 指向已删除 / 不存在的会话，同时数据库里保留一个正常会话。
  - 启动应用后，验证仍停留在正常会话，不显示后台中断错误条和冷启动重试 SnackBar，并清理 SharedPreferences marker。
- `test/mobile_main_flow_smoke_test.dart`
  - 新增 `mobile inactive lifecycle sanitizes background retry markers`。
  - 在应用启动后、后台切出前向 SharedPreferences 写入脏列表 marker（空字符串、空白字符串、带空白的会话 ID）。
  - 模拟 `AppLifecycleState.inactive` 后，验证写入侧会把列表清洗成唯一有效会话 ID，并保留旧单值兼容 marker。
- `test/mobile_main_flow_smoke_test.dart`
  - 新增 `mobile resume waits for delayed background retry marker cleanup`。
  - 通过测试专用延迟模拟后台 marker 写入慢于快速恢复前台；旧逻辑会在清理后又写回 stale marker，修复后恢复前台清理会等待 pending persist 完成，最终两类 marker 都为空。
- `test/mobile_main_flow_smoke_test.dart`
  - 新增 `mobile startup restores multiple background retry markers`。
  - 预置 `kBackgroundInterruptedSessionsStorageKey` 为两个有效会话 + 一个缺失会话，并混入重复 ID、空字符串和空白字符串，让非 marker 会话成为最新自动选中候选。
  - 启动应用后，验证会切到第一条有效待重试会话，SnackBar 明确显示已恢复 2 个后台中断会话并提供 `重试全部` action；两条有效唯一会话的 `streamStateProvider` 都恢复后台中断错误态。点击 `重试全部` 后，在无模型配置场景下两条会话都转为 `请先选择一个模型`，证明批量重试必须由用户显式授权触发且能覆盖所有恢复项；继续切到第二条会话，验证错误条已更新；重复 / 空 ID 不污染恢复数量，缺失会话被跳过，单值兼容 marker 和列表 marker 都被清理。

## 验证记录

```bash
flutter --no-version-check test --no-pub -r expanded \
  test/mobile_main_flow_smoke_test.dart \
  --name "mobile inactive lifecycle cancels active streaming response"
dart format lib/shared/providers/chat_provider.dart \
  lib/main.dart \
  test/mobile_main_flow_smoke_test.dart
flutter --no-version-check test --no-pub -r expanded \
  test/mobile_main_flow_smoke_test.dart \
  --name "mobile resume waits for delayed background retry marker cleanup"
flutter --no-version-check test --no-pub -r expanded \
  test/mobile_main_flow_smoke_test.dart \
  --name "mobile inactive lifecycle cancels all streaming sessions"
flutter --no-version-check test --no-pub -r expanded \
  test/chat_provider_retry_test.dart \
  test/mobile_main_flow_smoke_test.dart
flutter --no-version-check analyze
git diff --check
```

结果：

- 第一轮红灯阶段目标用例失败于 `Expected: false Actual: <true>`，证明旧逻辑进入 `inactive` 后不会取消当前生成。
- 第二轮红灯阶段目标用例编译失败于缺少 `backgroundStreamingInterruptedMessage`，证明还没有后台中断可重试提示状态。
- 第三轮红灯阶段目标用例失败于找不到 `已停止后台生成，可点“重试”继续`，证明恢复前台没有显式提示。
- 第四轮红灯阶段冷启动恢复用例失败于缺少 `kBackgroundInterruptedSessionStorageKey`，随后补持久化 marker；继续补充断言发现同进程恢复提示后 marker 未清理，再补消费逻辑。
- 第五轮红灯阶段 marker 指向非当前自动选中会话的用例失败于 `Expected: session-persisted-background-retry-target`、`Actual: session-newer-without-marker`，证明旧逻辑会忽略非当前会话的待重试 marker。
- 第六轮红灯阶段 stale marker 用例失败于 `Actual: 'session-deleted-background-retry'`，证明 marker 指向不存在会话时旧逻辑会直接返回并留下无效 marker；修复后会清理 marker 并保持当前正常会话。
- 第七轮红灯阶段多 marker 用例编译失败于缺少 `kBackgroundInterruptedSessionsStorageKey`，证明当前只有单值 marker；修复后后台切出写入列表 key，冷启动可恢复多条有效待重试会话，缺失会话自动跳过，并清理新旧两类 marker。继续增强多条恢复 UX，红灯失败于找不到 `已恢复 2 个后台中断会话，可逐个点“重试”继续`，修复后多条恢复提示显示数量，且切到第二条待重试会话时错误条仍可见。继续补 marker 列表数据卫生，红灯确认重复 ID 会污染恢复数量，修复后读取 marker 时 trim、跳过空值并按顺序去重；继续补写入侧清洗，红灯确认后台切出会把已有脏列表原样保留，修复后持久化前也会清洗已有列表。随后把多条恢复 action 从只重试第一条推进为显式用户授权的 `重试全部`，红灯失败于找不到 `已恢复 2 个后台中断会话，可点“重试全部”继续`，修复后点击 `重试全部` 会逐条触发恢复项的用户消息重试。
- 第八轮红灯阶段主动重试用例失败于 `Actual: 应用进入后台，已停止本次生成...`，证明 `retryLastUserMessage()` 在 `messagesProvider` 仍 loading 时会静默无效；修复后改为直接查 DAO，用户主动重试能进入发送路径。
- 第九轮红灯阶段延迟 marker 写入竞态用例失败于 `Actual: session-background-marker-race`，证明快速切后台 / 前台时旧逻辑可能先清理、后写回 stale marker；修复后同进程恢复前台会等待 pending marker 写入完成再清理。
- 第十轮红灯阶段非当前会话后台流用例失败于 `Expected: false Actual: <true>`，证明旧生命周期处理只取消 active 会话；修复后后台切出会遍历已加载会话中所有 streaming 状态，逐条取消并写入列表 marker。
- 修复后目标用例通过。
- `test/mobile_main_flow_smoke_test.dart` 17 项通过；`test/chat_provider_retry_test.dart` 1 项通过。
- `flutter --no-version-check analyze` 无问题，`git diff --check` 无输出；正式 `pubspec.yaml` / `pubspec.lock` 未保留临时 sqlite hook。

## 边界

- 本轮是后台切出时的“停止悬挂请求”保护，并把持久化 marker 从单值推进到列表恢复；仍不等同于完整后台请求自动恢复队列。
- 恢复前台 / 冷启动后只提示，不自动重试，避免后台 / 前台切换造成重复 API 调用或费用；当前依赖错误条或 SnackBar 里的“重试”入口。
- 当前列表恢复只负责标记“可手动重试”：后台切出写入和冷启动读取都会清洗 marker；冷启动会恢复所有仍存在且去重后的 marker 会话错误条，并切到第一条有效会话提示用户手动重试。单条恢复时 `重试` 只作用于当前会话；多条恢复时 `重试全部` 是显式用户动作，会逐条触发已恢复会话的最后一条 user 消息重试，但仍不会在恢复前台 / 冷启动时自动调用模型接口。若未来允许多个会话并行生成，还需要扩展为遍历所有 active stream 和更完整的队列 UI / 进度反馈。
- 设备侧真实慢流取消补证见 `docs/mobile-background-stream-cancel-smoke-2026-07-07.md`；该 smoke 使用 Android 真机内真实 HTTP 慢流请求 + integration lifecycle 注入，物理 Home 恢复仍由独立后台恢复 smoke 覆盖。
